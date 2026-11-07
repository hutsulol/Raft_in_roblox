local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	СТУК МОЛОТКОМ ПРИ СТРОЙКЕ — правая рука опускается вперёд и возвращается.

	⚠️ ПРИЁМ ТОТ ЖЕ, ЧТО У ВЗМАХА ПРИ РУБКЕ (ResourcePull) И У ОГНЕМЁТА.
	У здешнего персонажа НЕТ Motor6D — части держит AnimationConstraint, и у него
	нет ни C0, ни C1, только Transform. Поэтому: ищем «сустав» по имени ДЕТАЛИ,
	пишем в Transform, делаем это ПОСЛЕ аниматора (BindToRenderStep с приоритетом
	Character + 1) и повторяем в Stepped — у физического рига Transform это ЦЕЛЬ
	для решателя, и на шаге физики он берёт то, что осталось от аниматора.

	⚠️ ПОЗУ С ТУЛОМ НЕ СТИРАЕМ, А ДОВОРАЧИВАЕМ.
	Взмах при рубке пишет в Transform голый поворот, то есть на время удара
	подменяет позу руки целиком. Здесь так нельзя: рука должна начать движение
	ИЗ ТОЙ ЖЕ позы, в которой держит молоток. Поэтому в начале удара снимаем
	слепок того, что положил аниматор, и дальше поворачиваем его:

	    Transform = CFrame.Angles(x, 0, 0) * поза_с_тулом

	Множитель именно СЛЕВА. Справа он крутил бы руку вокруг её собственных,
	уже повёрнутых осей — то есть вокруг предплечья, а не плеча, и вместо замаха
	получилось бы вращение молотка в кисти.
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- ⚠️ ЗНАК ЗДЕСЬ ОБРАТНЫЙ ТОМУ, ЧТО У ВЗМАХА ПРИ РУБКЕ. И ЭТО НЕ ОПЕЧАТКА.
-- Там (ResourcePull) поворот ЗАМЕНЯЕТ позу руки, то есть отсчитывается от позы
-- покоя, где рука опущена вдоль тела: +X поднимает её вперёд, и на фоне рубки
-- это читается как удар. Здесь поворот КЛАДЁТСЯ ПОВЕРХ позы с молотком, а в ней
-- рука уже поднята — тот же плюс продолжает крутить в ту же сторону и задирает
-- её ещё выше. Опускает отсюда минус. Правило простое: знак зависит не от оси, а
-- от того, ОТ ЧЕГО считается поворот.
local SWING_X = -90       -- градусов вниз-вперёд от позы с молотком

-- ⚠️ ВНИЗ БЫСТРО, ОБРАТНО МЕДЛЕННО — И НИ ОДНОГО РОВНОГО УЧАСТКА.
-- Линейная скорость читается как механизм, а не как удар. Удар разгоняется к
-- моменту касания, поэтому вниз идёт квадратичный разгон (f²: скорость растёт и
-- обрывается на самом низу), а возврат — сглаженный (плавно тронулся, плавно
-- встал). Отсюда и разные доли цикла: замах короче возврата.
local SWING_TIME = 0.38   -- весь цикл: удар и возврат
local DOWN_PART  = 0.34   -- какая доля цикла уходит на удар

-- Имена детали правой руки на всех ригах, которые встречаются в проекте.
local ARM_NAMES = { ["Right Arm"] = true, ["RightUpperArm"] = true }

local swingStart, swingBase, armJoint = nil, nil, nil
local physicalRig, scannedChar = false, nil

-- Ищем по ДЕТАЛИ, к которой сустав приделан, и принимаем все три вида
-- сочленений, что бывают у здешних ригов.
local function findArmJoint(char)
	physicalRig = false
	for _, d in ipairs(char:GetDescendants()) do
		local limb
		if d:IsA("AnimationConstraint") then
			limb = d.Attachment1 and d.Attachment1.Parent and d.Attachment1.Parent.Name
			if limb and ARM_NAMES[limb] then
				physicalRig = true
				return d
			end
		elseif d:IsA("Motor6D") then
			limb = d.Part1 and d.Part1.Name
			if limb and ARM_NAMES[limb] then return d end
		elseif d:IsA("Bone") then
			if ARM_NAMES[d.Name] then return d end
		end
	end
	return nil
end

local function bindArm(char)
	swingStart, swingBase, armJoint, scannedChar = nil, nil, nil, char
	if not char then return end
	armJoint = findArmJoint(char)
end

local function ease(f)
	return f * f * (3 - 2 * f)
end

-- Один и тот же расчёт для обоих мест записи: и при отрисовке, и на шаге физики.
local function applySwing()
	if not (swingStart and armJoint and armJoint.Parent and swingBase) then return end
	local t = (os.clock() - swingStart) / SWING_TIME
	if t >= 1 then
		-- ⚠️ В КОНЦЕ НИЧЕГО НЕ ПИШЕМ.
		-- Поза руки принадлежит аниматору, он кладёт её каждый кадр. Верни мы сюда
		-- слепок или единицу — на кадр подменили бы то, что он уже посчитал.
		swingStart, swingBase = nil, nil
		return
	end

	local x
	if t < DOWN_PART then
		local f = t / DOWN_PART
		x = SWING_X * f * f                      -- разгон в удар
	else
		local g = (t - DOWN_PART) / (1 - DOWN_PART)
		x = SWING_X * (1 - ease(g))              -- плавный возврат
	end
	armJoint.Transform = CFrame.Angles(math.rad(x), 0, 0) * swingBase
end

-- ═══════════ ручка наружу ═══════════
-- Зовёт BuildingSystem на каждой установке. Повторный вызов начинает удар заново:
-- частые клики дают частые удары, и рука не застревает на полпути прерванного
-- твина — отсчёт идёт по времени, а не анимацией на объекте.
_G.PlayHammerSwing = function()
	local char = player.Character
	if not char then return end
	-- пересобираем при смене персонажа: старый сустав уже мёртв
	if scannedChar ~= char or not (armJoint and armJoint.Parent) then bindArm(char) end
	if not armJoint then return end
	-- ⚠️ СЛЕПОК СНИМАЕМ ТОЛЬКО КОГДА УДАРА НЕТ.
	-- Иначе получалось накопление: при быстрой стройке следующий клик приходил
	-- посреди предыдущего удара и читал из Transform НАШ ЖЕ повёрнутый кадр, а не
	-- позу с молотком. Каждый клик добавлял к предыдущему свои девяносто
	-- градусов, и рука прокручивалась на полный оборот. Отсюда же и «лимит»:
	-- поворот всегда отсчитывается от одной и той же снятой позы, поэтому дальше
	-- SWING_X он уйти не может — сколько по ней ни щёлкай.
	if not swingStart then
		swingBase = armJoint.Transform
	end
	swingStart = os.clock()
end

RunService:BindToRenderStep("HammerSwing",
	Enum.RenderPriority.Character.Value + 1, applySwing)

-- Физический риг читает цель на шаге физики, а не при отрисовке: без повтора
-- решатель возьмёт то, что оставил аниматор, и удара снова не будет видно.
RunService.Stepped:Connect(function()
	if physicalRig then applySwing() end
end)

player.CharacterAdded:Connect(function(char)
	swingStart, swingBase, armJoint, scannedChar = nil, nil, nil, nil
	task.defer(bindArm, char)
end)
bindArm(player.Character)

print("[Молоток] удар при стройке готов (_G.PlayHammerSwing)")
