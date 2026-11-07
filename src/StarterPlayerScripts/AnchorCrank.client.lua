local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ВРАЩЕНИЕ ЛЕБЁДКИ ЯКОРЯ — поза игрока у рукоятки + сам крутящийся узел.

	⚠️ ПРИЁМ ТОТ ЖЕ, ЧТО У МОЛОТКА (HammerSwing) И ВЗМАХА ПРИ РУБКЕ.
	У здешнего персонажа НЕТ Motor6D — части держит AnimationConstraint, у него
	нет ни C0, ни C1, только Transform. Поэтому: ищем «сустав» по имени ДЕТАЛИ,
	принимаем все три вида сочленений, пишем в Transform ПОСЛЕ аниматора
	(BindToRenderStep с приоритетом Character + 1) и повторяем в Stepped — у
	физического рига Transform это ЦЕЛЬ для решателя.

	⚠️ ЭТО ЦИКЛ, А НЕ УДАР.
	Молоток — одноразовое движение с началом и концом. Здесь игрок крутит, пока
	держит, поэтому фаза считается от времени начала и не заканчивается сама:
	снаружи зовут start(dir) и stop().

	⚠️ ПОЧЕМУ РУКА ХОДИТ ПО КОНУСУ, А НЕ ПО ДУГЕ.
	Рукоятка ездит по ОКРУЖНОСТИ радиуса 0.108 клетки вокруг оси. Одним поворотом
	плеча такую траекторию не получить — выйдет дуга. Нужны два поворота в
	противофазе (наклон и отведение) плюс подработка локтем на глубину:
	плечо рисует конус, локоть превращает конус в круг.
	Амплитуды не выдуманы: они получены перебором в Blender, где для каждой фазы
	искались углы, при которых ладонь садится на реальную окружность рукоятки
	(промах вышел ≤ 0.05 студа). ARM_SWING ≈ atan(радиус_рукоятки / длина_руки).

	⚠️ ДВА НАПРАВЛЕНИЯ — ЭТО НЕ ОДИН КЛИП ЗАДОМ НАПЕРЁД.
	Подъём идёт против веса якоря: корпус наваливается, амплитуда больше, темп
	ниже. Спуск только придерживают: поза прямее, цикл быстрее. Разворот задаёт
	знак dir, разницу усилия — таблица EFFORT.

	Колесо крутится у КАЖДОГО клиента по атрибуту Winding на модели лебёдки:
	Transform и CFrame, выставленные на сервере, до других игроков не доедут
	(см. ANIMATIONS.md §6), а атрибут реплицируется.
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- ═══════════ числа из замеров ═══════════
-- Плечо: наклон и отведение в противофазе рисуют конус вокруг оси рукоятки.
local ARM_SWING   = 21      -- градусов, ≈ atan(0.108 / 0.28) — радиус ручки к длине руки
local ELBOW_SWING = 14      -- локоть добирает глубину, иначе конус, а не круг
local ELBOW_BASE  = 18      -- средний сгиб: рука не выпрямляется в струну
local TORSO_LEAN  = 9       -- корпус ходит за рукой

-- Подъём тяжелее спуска: больше корпуса, медленнее оборот.
local EFFORT = {
	Raise = { period = 4.0, lean = 1.00, arm = 1.00 },
	Lower = { period = 3.2, lean = 0.45, arm = 0.88 },
}

-- Имена деталей на всех ригах, что встречаются в проекте.
local SHOULDER_NAMES = { ["Right Arm"] = true, ["RightUpperArm"] = true }
local ELBOW_NAMES    = { ["RightLowerArm"] = true }
local TORSO_NAMES    = { ["Torso"] = true, ["UpperTorso"] = true }

local WHEEL_NAME = "raft_anchor_wheel"

-- ═══════════ поиск суставов ═══════════
local physicalRig = false

local function jointLimbName(d)
	if d:IsA("AnimationConstraint") then
		return d.Attachment1 and d.Attachment1.Parent and d.Attachment1.Parent.Name, true
	elseif d:IsA("Motor6D") then
		return d.Part1 and d.Part1.Name, false
	elseif d:IsA("Bone") then
		return d.Name, false
	end
	return nil, false
end

local function findJoints(char)
	physicalRig = false
	local found = { shoulder = nil, elbow = nil, torso = nil }
	for _, d in ipairs(char:GetDescendants()) do
		local limb, physical = jointLimbName(d)
		if limb then
			if SHOULDER_NAMES[limb] and not found.shoulder then
				found.shoulder = d
				if physical then physicalRig = true end
			elseif ELBOW_NAMES[limb] and not found.elbow then
				found.elbow = d
			elseif TORSO_NAMES[limb] and not found.torso then
				found.torso = d
			end
		end
	end
	return found
end

-- ═══════════ состояние ═══════════
local joints, bases, scannedChar = {}, {}, nil
local crankStart, crankDir, crankKind = nil, 1, "Raise"

local function bind(char)
	joints, bases, scannedChar = {}, {}, char
	if not char then return end
	joints = findJoints(char)
	local have, miss = {}, {}
	for _, k in ipairs({ "shoulder", "elbow", "torso" }) do
		table.insert(joints[k] and have or miss, k)
	end
	print(("[Лебёдка] риг %s | найдено: %s | не найдено: %s")
		:format(physicalRig and "физический" or "обычный",
			#have > 0 and table.concat(have, ", ") or "—",
			#miss > 0 and table.concat(miss, ", ") or "—"))
end

-- ═══════════ поза ═══════════
local function applyCrank()
	if not crankStart then return end
	local sh = joints.shoulder
	if not (sh and sh.Parent and bases.shoulder) then return end

	local cfg = EFFORT[crankKind] or EFFORT.Raise
	-- фаза: 0..1 за оборот. Направление — знаком, темп — периодом.
	local ph = ((os.clock() - crankStart) / cfg.period) * crankDir
	local a = ph * math.pi * 2

	local sw = ARM_SWING * cfg.arm
	-- ⚠️ МНОЖИТЕЛЬ СЛЕВА. Справа поворот шёл бы вокруг собственных, уже
	-- повёрнутых осей детали — то есть вокруг предплечья, а не плеча, и вместо
	-- вращения рукоятки получилось бы кручение кисти.
	sh.Transform = CFrame.Angles(math.rad(math.sin(a) * sw), 0,
		math.rad(math.cos(a) * sw)) * bases.shoulder

	if joints.elbow and joints.elbow.Parent and bases.elbow then
		-- локоть идёт на той же частоте, но со сдвигом на четверть оборота:
		-- когда рукоятка ближе всего к плечу, рука сложена сильнее всего
		local e = ELBOW_BASE + math.cos(a) * ELBOW_SWING
		joints.elbow.Transform = CFrame.Angles(math.rad(e), 0, 0) * bases.elbow
	end

	if joints.torso and joints.torso.Parent and bases.torso then
		local lean = TORSO_LEAN * cfg.lean * (0.6 - 0.4 * math.sin(a))
		joints.torso.Transform = CFrame.Angles(math.rad(lean), 0, 0) * bases.torso
	end
end

RunService:BindToRenderStep("AnchorCrank",
	Enum.RenderPriority.Character.Value + 1, applyCrank)

-- Физический риг читает цель на шаге физики, а не при отрисовке.
RunService.Stepped:Connect(function()
	if physicalRig then applyCrank() end
end)

-- ═══════════ ручки наружу ═══════════
-- kind: "Raise" (якорь вверх) или "Lower" (вниз). Повторный вызов с тем же
-- направлением ничего не сбрасывает — фаза продолжается, рука не дёргается.
_G.StartAnchorCrank = function(kind)
	local char = player.Character
	if not char then return end
	if scannedChar ~= char or not (joints.shoulder and joints.shoulder.Parent) then
		bind(char)
	end
	if not joints.shoulder then
		warn("[Лебёдка] сустав правой руки не найден — поза не сыграет")
		return
	end
	kind = (kind == "Lower") and "Lower" or "Raise"
	if crankStart and crankKind == kind then return end

	-- ⚠️ СЛЕПОК СНИМАЕМ ТОЛЬКО КОГДА ВРАЩЕНИЯ НЕТ.
	-- Иначе накопление: повторный вызов посреди цикла прочитал бы из Transform
	-- НАШ ЖЕ повёрнутый кадр вместо позы, которую положил аниматор, и рука
	-- уезжала бы всё дальше с каждым нажатием.
	if not crankStart then
		bases.shoulder = joints.shoulder.Transform
		bases.elbow    = joints.elbow and joints.elbow.Transform or nil
		bases.torso    = joints.torso and joints.torso.Transform or nil
	end
	crankKind = kind
	crankDir  = (kind == "Raise") and 1 or -1
	crankStart = os.clock()
end

_G.StopAnchorCrank = function()
	-- ⚠️ НА ВЫХОДЕ НИЧЕГО НЕ ПИШЕМ.
	-- Поза руки принадлежит аниматору, он кладёт её каждый кадр. Вернём слепок
	-- или единицу — на кадр подменим то, что он уже посчитал, и будет рывок.
	crankStart, bases = nil, {}
end

-- ═══════════ само колесо ═══════════
-- Крутим у каждого клиента по атрибуту: CFrame с сервера до других игроков
-- доедет с задержкой и рывками, а атрибут реплицируется дёшево.
-- Ось меша совпадает с его собственной осью X и проходит через центр габарита
-- по Y и Z (проверено при экспорте), поэтому поправка на пивот не нужна.
local wheels = {}

local function noteWheel(inst)
	if inst:IsA("BasePart") and inst.Name == WHEEL_NAME then
		wheels[inst] = inst.CFrame
	end
end

for _, d in ipairs(workspace:GetDescendants()) do noteWheel(d) end
workspace.DescendantAdded:Connect(noteWheel)
workspace.DescendantRemoving:Connect(function(inst) wheels[inst] = nil end)

RunService.RenderStepped:Connect(function()
	for part, rest in pairs(wheels) do
		if not part.Parent then
			wheels[part] = nil
		else
			local owner = part.Parent
			local state = owner and owner:GetAttribute("Winding")
			if state == "Raise" or state == "Lower" then
				local cfg = EFFORT[state]
				local dir = (state == "Raise") and 1 or -1
				local a = (os.clock() / cfg.period) * math.pi * 2 * dir
				part.CFrame = rest * CFrame.Angles(a, 0, 0)
			elseif rest then
				-- запоминаем позу покоя заново, если деталь передвинули
				if state == nil and part.CFrame.Position ~= rest.Position then
					wheels[part] = part.CFrame
				end
			end
		end
	end
end)

player.CharacterAdded:Connect(function(char)
	crankStart, joints, bases, scannedChar = nil, {}, {}, nil
	task.defer(bind, char)
end)
bind(player.Character)

print("[Лебёдка] готово: _G.StartAnchorCrank(\"Raise\"/\"Lower\"), _G.StopAnchorCrank()")
