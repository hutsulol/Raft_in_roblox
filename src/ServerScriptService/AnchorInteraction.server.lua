-- AnchorInteraction.server.lua
-- Server side of the anchor: exposes a RemoteEvent the client UI
-- fires to raise/lower each anchor, clamps the RopeConstraint's
-- Length to [MIN_ROPE, MAX_ROPE], and sets an AnchorDeployed
-- attribute on the raft so BoatForwardMovement can halt it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local AnchorRig = require(ReplicatedStorage:WaitForChild("AnchorRig"))

local MIN_ROPE         = 5    -- fully raised (anchor rests inside the frame)
local MAX_ROPE         = 11   -- fully lowered, the raft stops

--[[ ⚠️ У НОВОЙ ЛЕБЁДКИ ШКАЛА ОТНОСИТЕЛЬНАЯ, А НЕ ОТ ПЯТИ ДО ОДИННАДЦАТИ.
     Числа выше — от СТАРОЙ модели Anchor_part: там трос сделан такой длины,
     и её якорь ходит шесть студов. У Raft_anchor трос свой, короткий, и
     попытка выставить ему длину «5..11» уводила её за пределы всякого
     смысла — кнопка нажималась, а якорь не двигался.
     Владелец сформулировал правило прямо: одно нажатие ВНИЗ = +0.2 студа к
     длине троса. Десять нажатий (шаг интерфейса 10%) дают ход в два студа.
     Ноль шкалы — длина, с которой лебёдка пришла из ReplicatedStorage: её
     запоминаем в атрибуте троса при первом обращении, чтобы «поднят до упора»
     означало ровно исходную модель, а не подобранное число. ]]
-- ⚠️ ШАГ ОБЪЯВЛЕН ЗДЕСЬ, ХОТЯ НУЖЕН СИЛЬНО НИЖЕ: через него считается ход
-- троса, а в Lua имя, объявленное ниже по файлу, внутри функции выше — nil.
-- То же число зашито в кнопках (AnchorHudUI, STEP): расходятся — сервер
-- молча отвергает нажатия, и кнопки перестают работать без единой ошибки.
local ANCHOR_STEP      = 5                        -- процентов за нажатие
local WINCH_STEP_STUDS = 0.35                     -- студов за нажатие
local WINCH_TRAVEL     = WINCH_STEP_STUDS * (100 / ANCHOR_STEP)   -- 20 шагов = 100%

local function ropeSpan(model, rope)
	if model and model.Name == "Raft_anchor" then
		local base = rope:GetAttribute("AnchorRopeBase")
		if not base then
			base = rope.Length
			rope:SetAttribute("AnchorRopeBase", base)
		end
		return base, WINCH_TRAVEL
	end
	return MIN_ROPE, math.max(0.001, MAX_ROPE - MIN_ROPE)
end
local ROPE_STEP        = 0.2  -- per key press
local INTERACTION_RANGE = 15  -- server-side anti-cheat gate

local anchorEvent = ReplicatedStorage:FindFirstChild("AnchorAction")
if not anchorEvent then
	anchorEvent = Instance.new("RemoteEvent")
	anchorEvent.Name = "AnchorAction"
	anchorEvent.Parent = ReplicatedStorage
end

-- ─── Helpers ─────────────────────────────────────────────────────────
-- ⚠️ Правило поиска троса и груза общее на всю игру — см. AnchorRig.
-- Здесь оставлена только обёртка, чтобы не переписывать вызовы ниже.
local function findRope(anchorModel)
	return AnchorRig.rope(anchorModel)
end

local function findCenterOfSticks(anchorModel)
	local sticks = anchorModel:FindFirstChild("sticks")
	if sticks then
		local c = sticks:FindFirstChild("Center of sticks", true)
		if c and c:IsA("BasePart") then return c end
	end
	local c = anchorModel:FindFirstChild("Center of sticks", true)
	if c and c:IsA("BasePart") then return c end
	return nil
end

-- Find the HingeConstraint the template ships inside HingePart —
-- that's what the user wired up as the wheel's Motor actuator.
local function findHinge(anchorModel)
	local wheel = anchorModel:FindFirstChild("Wooden_Wheel")
	if not wheel then return nil end
	local hinge = wheel:FindFirstChild("HingePart", true)
	if not hinge then return nil end
	local hc = hinge:FindFirstChildOfClass("HingeConstraint")
	return hc
end

-- The user's Wooden_Wheel ships with its own internal weld + hinge
-- configuration. We no longer touch those welds during setup — the
-- HingeConstraint handles rotation on its own; any weld adjustments
-- here just risk detaching pieces of the wheel. Kept as a stub so
-- the call site stays the same.
local function freeWheelRotor(_anchorModel)
end

-- ─── Hinge pulse ────────────────────────────────────────────────────
-- Each press of E (direction +1) or Q (-1) drives the wheel's
-- HingeConstraint motor for SPIN_PULSE_DURATION seconds, then coasts
-- to a stop. Overlapping presses extend the pulse and can flip
-- direction instantly — MotorMaxTorque is held high while the pulse
-- is live so the motor actually develops the commanded velocity.
local SPIN_PULSE_DURATION  = 0.5
local SPIN_TORQUE          = 50000
local SPIN_ANGULAR_VELOCITY = 4  -- rad/s magnitude
local pulseTokens = {}

local function pulseWheel(anchorModel, direction)
	local hc = findHinge(anchorModel)
	if not hc then return end
	hc.MotorMaxTorque  = SPIN_TORQUE
	hc.AngularVelocity = direction * SPIN_ANGULAR_VELOCITY

	pulseTokens[anchorModel] = (pulseTokens[anchorModel] or 0) + 1
	local token = pulseTokens[anchorModel]
	task.delay(SPIN_PULSE_DURATION, function()
		if pulseTokens[anchorModel] ~= token then return end
		if not hc or not hc.Parent then return end
		hc.MotorMaxTorque  = 0
		hc.AngularVelocity = 0
	end)
end

-- Raft's AnchorDepth ∈ [0, 1] is the deepest anchor currently deployed
-- on it (0 = all anchors up, 1 = at least one rope fully out). Set
-- alongside the existing AnchorDeployed bool so BoatForwardMovement
-- can smoothly scale the raft's forward speed instead of a hard stop.
local function recomputeRaftAnchoredState()
	local raft = workspace:FindFirstChild("Raft")
	if not raft then return end
	local range = math.max(0.001, MAX_ROPE - MIN_ROPE)
	local depth = 0
	for _, child in raft:GetChildren() do
		-- ⚠️ Якорей в игре ДВА РАЗНЫХ: старый Anchor_part (ставится крафтовым
		-- предметом) и новая лебёдка Raft_anchor (строится молотком). Глубина у
		-- плота одна на всех: берём самый глубоко опущенный.
		if child:IsA("Model")
			and (child.Name == "Anchor_part" or child.Name == "Raft_anchor") then
			local rc = findRope(child)
			if rc then
				-- ⚠️ Шкала СВОЯ у каждой модели (см. ropeSpan): у старой она в
				-- абсолютных студах, у новой — от собственной длины троса.
				local base, span = ropeSpan(child, rc)
				local d = math.clamp((rc.Length - base) / span, 0, 1)
				if d > depth then depth = d end
			end
		end
	end
	raft:SetAttribute("AnchorDepth", depth)
	raft:SetAttribute("AnchorDeployed", depth >= 1 - 1e-3)
end

-- ─── Setup per anchor ────────────────────────────────────────────────
-- Each new anchor gets its rope length clamped to MIN_ROPE at spawn so
-- the anchor rests cleanly inside the frame, and a changed-signal so
-- the raft's AnchorDeployed state follows whatever the rope is doing.
local function setupAnchor(anchorModel)
	if anchorModel:GetAttribute("AnchorInteractionReady") then return end
	local rope = findRope(anchorModel)
	if not rope then return end
	-- Clamp initial length into the valid range.
	if rope.Length < MIN_ROPE then rope.Length = MIN_ROPE end
	if rope.Length > MAX_ROPE then rope.Length = MAX_ROPE end
	rope:GetPropertyChangedSignal("Length"):Connect(recomputeRaftAnchoredState)
	freeWheelRotor(anchorModel)
	-- HingeConstraint ships idle (MotorMaxTorque 0) — pulseWheel
	-- turns it on for each E / Q press, then zeroes it again.
	local hc = findHinge(anchorModel)
	if hc then hc.MotorMaxTorque = 0; hc.AngularVelocity = 0 end
	anchorModel:SetAttribute("AnchorInteractionReady", true)
	recomputeRaftAnchoredState()
end

for _, d in workspace:GetDescendants() do
	if d:IsA("Model") and d.Name == "Anchor_part" then setupAnchor(d) end
end

workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") and d.Name == "Anchor_part" then
		task.defer(setupAnchor, d)
	end
end)

workspace.DescendantRemoving:Connect(function(d)
	if d:IsA("Model") and d.Name == "Anchor_part" then
		task.defer(recomputeRaftAnchoredState)
	end
end)

-- ─── Remote handler ─────────────────────────────────────────────────
anchorEvent.OnServerEvent:Connect(function(player, action, anchorModel)
	if typeof(action) ~= "string" then return end
	if typeof(anchorModel) ~= "Instance" then return end
	if not anchorModel:IsDescendantOf(workspace) then return end
	if anchorModel.Name ~= "Anchor_part" then return end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local center = findCenterOfSticks(anchorModel)
	if not center then return end
	if (center.Position - hrp.Position).Magnitude > INTERACTION_RANGE then return end

	local rope = findRope(anchorModel)
	if not rope then return end

	if action == "lower" then
		rope.Length = math.clamp(rope.Length + ROPE_STEP, MIN_ROPE, MAX_ROPE)
		pulseWheel(anchorModel, 1)
	elseif action == "raise" then
		rope.Length = math.clamp(rope.Length - ROPE_STEP, MIN_ROPE, MAX_ROPE)
		pulseWheel(anchorModel, -1)
	end
end)

-- Published so other server scripts (the UI client, BoatForwardMovement)
-- can agree on the rope limits without duplicating constants.
_G.AnchorConfig = {
	MinRope  = MIN_ROPE,
	MaxRope  = MAX_ROPE,
	Step     = ROPE_STEP,
}

-- ═══════════ ЛЕБЁДКА RAFT_ANCHOR: HUD, ЗОНА, ГЛУБИНА ═══════════

--[[ ⚠️ У НОВОЙ ЛЕБЁДКИ СВОЙ РЕМОУТ И СВОЙ ЯЗЫК — ПРОЦЕНТЫ, А НЕ ДЛИНА ТРОСА.
     Старый якорь Anchor_part управляется клавишами и говорит длиной верёвки
     (AnchorAction, шаг 0.2 студа). Интерфейс лебёдки по хендоффу говорит
     процентами: «Высота: 100%», шаг 25. Переводить одно в другое на клиенте
     значит развести два представления одной величины, поэтому перевод живёт
     здесь, а наружу отдаются только проценты.
     depth = 0 — якорь поднят, плот идёт; depth = 100 — опущен до конца, плот
     стоит. Скорость между ними падает пропорционально (см. BoatMovement,
     атрибут AnchorDepth). ]]
local Players = game:GetService("Players")

--[[ ⚠️ ЗОНА — ЭТО КЛЕТКА ПОЛА С ЯКОРЕМ, А НЕ ШАР ВОКРУГ МОДЕЛИ.
     Владелец сформулировал правило прямо: стоишь на блоке с якорем — видишь
     интерфейс, сошёл — не видишь. Шар вокруг габарита давал не то: лебёдка
     высокая, и её коробка накрывала соседние клетки, а игрока, стоящего
     сбоку внизу, наоборот теряла.
     Поэтому меряем ПО ГОРИЗОНТАЛИ до центра её доски: клетка плота 6 студов,
     половина клетки плюс запас на ширину персонажа = 4.5. По вертикали окно шире:
     игрок может стоять на самой лебёдке или подпрыгнуть. ]]
local HUD_CELL_R  = 4.5    -- студов по горизонтали от центра клетки
local HUD_CELL_H  = 10     -- студов по вертикали, вверх и вниз
local ZONE_PERIOD = 0.25   -- как часто проверяем, кто рядом: чаще незачем

local winchEvent = ReplicatedStorage:FindFirstChild("RaftAnchorAction")
if not winchEvent then
	winchEvent = Instance.new("RemoteEvent")
	winchEvent.Name = "RaftAnchorAction"
	winchEvent.Parent = ReplicatedStorage
end

--[[ ═══════════ КОЛЕСО ЛЕБЁДКИ: РАЗГОН, ВЫБЕГ, НАПРАВЛЕНИЕ ═══════════

     ⚠️ КОЛЕСО КРУТИТ МОТОР НА ШАРНИРЕ, А НЕ ПОКАДРОВЫЙ CFrame.
     Соблазн был поворачивать деталь кодом каждый кадр — и это тот самый
     случай, когда «просто» ломается: колесо приварено к плоту, а плот сам
     едет и качается на волне. Любая запись CFrame конфликтовала бы с
     репликацией физики и давала дрожь, причём только у тех, кто смотрит со
     стороны. Шарнир с мотором — это то же вращение, но физическое: движок
     сам держит его относительно плота и сам рассылает клиентам.

     ⚠️ ОСЬ — ЛОКАЛЬНАЯ X ДЕТАЛИ, ТА САМАЯ «КРАСНАЯ» В STUDIO.
     У HingeConstraint осью служит X аттачмента. Аттач в колесе кладём
     единичным, без поворота, — значит его X совпадает с X колеса. Второй
     аттач ставим в деталь рамы РОВНО в то же место и с теми же осями
     (WorldCFrame), иначе шарнир при первом же кадре дёрнет колесо, совмещая
     их сам.

     ⚠️ РАЗГОН И ВЫБЕГ СЧИТАЕМ САМИ, А НЕ ЖДЁМ ОТ ФИЗИКИ.
     Свободное колесо на подшипнике вращалось бы по инерции, но её величина
     зависела бы от массы модели — то есть от того, как художник нарисовал
     деталь. Вместо этого держим свою скорость: нажатие добавляет рывок,
     каждый кадр скорость линейно тает. Частые нажатия складываются и колесо
     раскручивается — ровно это и просили. ]]
local WHEEL_NAME   = "Raft_anchor_wheel"
local WHEEL_KICK   = 5      -- рад/с прибавки за одно нажатие
local WHEEL_MAX    = 22     -- потолок скорости, чтобы не превратилось в блендер
local WHEEL_DECAY  = 4      -- рад/с² выбега: с потолка до нуля примерно за 5 с
local WHEEL_TORQUE = 50000  -- столько же, сколько у старой лебёдки (SPIN_TORQUE)
-- ⚠️ ЗНАК ЗАДАЁТ, КУДА ЕДЕТ КОЛЕСО НА «ВВЕРХ». Направление зависит от того,
-- как деталь развернули в модели, и на глаз его не вычислить: крутится не
-- туда — поменяй здесь на -1, больше нигде трогать не надо.
local WHEEL_UP_DIR = 1

local wheelSpin = {}   -- [модель лебёдки] = текущая скорость, рад/с

local function wheelOf(winch)
	local w = winch and winch:FindFirstChild(WHEEL_NAME, true)
	return (w and w:IsA("BasePart")) and w or nil
end

--[[ Опора для второго конца оси. Нужна деталь, ПРИВАРЕННАЯ к плоту, иначе
     шарнир соединит колесо с чем-то, что само болтается. Доска лебёдки
     подходит идеально: она и есть клетка пола под ней. ]]
local function wheelBase(winch, wheel)
	local deck = winch:FindFirstChild("Raft_anchor_deck", true)
	if deck and deck:IsA("BasePart") then return deck end
	local hang = AnchorRig.hangingPart(winch)
	for _, d in winch:GetDescendants() do
		if d:IsA("BasePart") and d ~= wheel and d ~= hang then return d end
	end
	return nil
end

local function ensureWheelHinge(winch)
	local wheel = wheelOf(winch)
	if not wheel then return nil end
	local hc = wheel:FindFirstChildOfClass("HingeConstraint")
	if hc then return hc end
	local base = wheelBase(winch, wheel)
	if not base then return nil end

	--[[ ⚠️ СНИМАЕМ СВАРКИ: приваренное колесо шарнир не провернёт никогда, а
	     выглядеть это будет как «мотор не работает». Ставим и метку для
	     страховочного сварщика, иначе после перезахода приварит снова. ]]
	for _, d in ipairs(wheel:GetChildren()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") then d:Destroy() end
	end
	for _, d in winch:GetDescendants() do
		if (d:IsA("WeldConstraint") or d:IsA("Weld"))
			and (d.Part0 == wheel or d.Part1 == wheel) then d:Destroy() end
	end
	wheel.Anchored = false
	-- столкновения выключаем: колесо сидит вплотную к раме и без этого
	-- скребло бы по ней, гася вращение и дёргая плот
	wheel.CanCollide = false
	wheel:SetAttribute("NoRaftWeld", true)
	pcall(function() wheel:SetNetworkOwner(nil) end)

	local axis = Instance.new("Attachment")
	axis.Name = "WheelAxis"
	axis.Parent = wheel          -- CFrame единичный: ось = X самой детали
	local seat = Instance.new("Attachment")
	seat.Name = "WheelAxisBase"
	seat.Parent = base
	seat.WorldCFrame = axis.WorldCFrame

	hc = Instance.new("HingeConstraint")
	hc.Attachment0 = seat
	hc.Attachment1 = axis
	hc.ActuatorType = Enum.ActuatorType.Motor
	hc.MotorMaxAcceleration = math.huge
	hc.MotorMaxTorque = 0
	hc.AngularVelocity = 0
	hc.Parent = wheel
	print(("[Якорь] колесо «%s» посажено на ось (опора «%s»)")
		:format(wheel.Name, base.Name))
	return hc
end

--[[ Нажатие = рывок в свою сторону. Складывается с тем, что уже есть, поэтому
     частые нажатия раскручивают колесо, а редкие только поддерживают ход.
     Нажатие в обратную сторону не разворачивает мгновенно: оно вычитается из
     текущей скорости, и колесо сперва замедляется — как настоящее. ]]
local function kickWheel(winch, dir)
	local hc = ensureWheelHinge(winch)
	if not hc then return end
	local v = math.clamp((wheelSpin[winch] or 0) + dir * WHEEL_KICK,
		-WHEEL_MAX, WHEEL_MAX)
	wheelSpin[winch] = v
	hc.MotorMaxTorque = WHEEL_TORQUE
	hc.AngularVelocity = v
end

--[[ Выбег. Отдельный цикл, а не task.delay на каждое нажатие: задержки от
     частых нажатий накладывались бы друг на друга и гасили колесо посреди
     разгона — этим уже обжигалась старая лебёдка (см. pulseTokens). ]]
RunService.Heartbeat:Connect(function(dt)
	for winch, v in pairs(wheelSpin) do
		if not winch.Parent then
			wheelSpin[winch] = nil
		else
			local step = WHEEL_DECAY * dt
			local nv = (v > 0) and math.max(0, v - step) or math.min(0, v + step)
			local hc = wheelOf(winch)
			hc = hc and hc:FindFirstChildOfClass("HingeConstraint")
			if hc then
				hc.AngularVelocity = nv
				-- на нуле отпускаем мотор совсем: иначе он продолжал бы держать
				-- колесо намертво, и рукой его было бы не тронуть
				if nv == 0 then hc.MotorMaxTorque = 0 end
			end
			wheelSpin[winch] = (nv ~= 0) and nv or nil
		end
	end
end)

local winchSeen = false
local function findWinch()
	local raft = workspace:FindFirstChild("Raft")
	if not raft then return nil end
	local m = raft:FindFirstChild("Raft_anchor")
	if m and m:IsA("Model") then
		if not winchSeen then
			winchSeen = true
			--[[ ⚠️ ЛЕЧИМ МОДЕЛЬ СРАЗУ, А НЕ ПРИ ПЕРВОМ НАЖАТИИ.
			     Две болячки видны только изнутри: трос без аттачей (длина
			     меняется, держать нечего) и приваренный/заякоренный груз.
			     Обе чинятся одинаково дёшево, и обе одинаково выглядят как
			     «лебёдка не работает».
			     Разбор модели печатаем один раз: если автоматика выберет не ту
			     деталь, это видно прямо в строках, а не по симптомам. ]]
			local _, ropeNote = AnchorRig.ensureRope(m)
			local part, freeNote = AnchorRig.free(m)
			print("[Якорь] лебёдка на плоту найдена — интерфейс включится при подходе")
			if ropeNote then print("[Якорь] " .. ropeNote) end
			if part and freeNote then
				print(("[Якорь] груз «%s» освобождён: %s"):format(part.Name, freeNote))
			end
			ensureWheelHinge(m)
			print("[Якорь] " .. AnchorRig.describe(m))
		end
		return m
	end
	return nil
end

--[[ ⚠️ РАССТОЯНИЕ МЕРЯЕМ ДО САМОЙ МОДЕЛИ, А НЕ ДО ЕЁ ПИВОТА.
     Первая версия брала GetPivot(), и это оказалось прямой ошибкой: у модели
     из FBX пивот сидит где угодно — у Raft_anchor он далеко от геометрии, —
     поэтому игрок, стоящий НА лебёдке, оказывался «в двадцати студах от неё»,
     и интерфейс не появлялся. Один раз он всё же вылезал: сразу после
     постановки игрок случайно стоял рядом с самим пивотом.
     Считаем честно: расстояние от точки до ГРАНИЦЫ габаритной коробки. Внутри
     коробки оно ноль, значит «стою на лебёдке» всегда попадает в зону при
     любом радиусе. ]]
--[[ ⚠️ ТОЧКА ОТСЧЁТА — СОБСТВЕННАЯ ДОСКА ЛЕБЁДКИ.
     Пивот у модели из FBX стоит в стороне, центр габарита уезжает вверх
     вместе с рамой, а доска — ровно та клетка, на которой игрок стоит.
     Если доски вдруг нет (переименовали), падаем на центр габарита: хуже,
     но не мимо. ]]
local function cellCentreOf(winch)
	local deck = winch:FindFirstChild("Raft_anchor_deck", true)
	if deck and deck:IsA("BasePart") then return deck.Position end
	local ok, boxCF = pcall(function() return (winch:GetBoundingBox()) end)
	if ok and boxCF then return boxCF.Position end
	return winch:GetPivot().Position
end

local function onAnchorCell(winch, pos)
	local c = cellCentreOf(winch)
	if math.abs(pos.Y - c.Y) > HUD_CELL_H then return false end
	return Vector2.new(pos.X - c.X, pos.Z - c.Z).Magnitude <= HUD_CELL_R
end

local function distanceToModel(model, pos)
	local ok, boxCF, boxSize = pcall(function()
		local a, b = model:GetBoundingBox()
		return a, b
	end)
	if not ok or not boxCF then return math.huge end
	local p = boxCF:PointToObjectSpace(pos)
	local half = boxSize * 0.5
	local dx = math.max(0, math.abs(p.X) - half.X)
	local dy = math.max(0, math.abs(p.Y) - half.Y)
	local dz = math.max(0, math.abs(p.Z) - half.Z)
	return Vector3.new(dx, dy, dz).Magnitude
end

-- Проценты ↔ длина троса. Диапазон общий со старым якорем: трос у обеих
-- моделей отмеряет одно и то же — насколько якорь ушёл под воду.
--[[ ⚠️ ПЕРЕД КАЖДЫМ ДВИЖЕНИЕМ УБЕЖДАЕМСЯ, ЧТО ЯКОРЬ ВООБЩЕ МОЖЕТ ПАДАТЬ.
     Правило и починка живут в AnchorRig — здесь только вызов и лог.
     Печатаем ТОЛЬКО когда что-то реально сняли: молчание значит, что груз
     и так был свободен, и причину надо искать не здесь. ]]
local function freeHangingPart(winch)
	local part, note = AnchorRig.free(winch)
	if part and note then
		print(("[Якорь] груз «%s» освобождён: %s"):format(part.Name, note))
	end
end
local function winchDepthPercent(winch)
	local rope = findRope(winch)
	if not rope then return 0 end
	local base, span = ropeSpan(winch, rope)
	return math.clamp((rope.Length - base) / span, 0, 1) * 100
end

local inZone = {}   -- [player] = true, пока он у лебёдки
local winchLogged = false
local zoneErrLogged = false

local function pushState(player, winch, zoneFlag)
	winchEvent:FireClient(player, "state", {
		depth = winch and math.round(winchDepthPercent(winch)) or 0,
		inZone = zoneFlag,
	})
end

--[[ ⚠️ ЗОНУ СЧИТАЕТ СЕРВЕР, А НЕ КЛИЕНТ.
     Клиент мог бы мерить расстояние сам и не гонять ремоут, но тогда он же
     решал бы, можно ли крутить лебёдку, — а это ровно то, что нельзя отдавать
     клиенту. Раз в четверть секунды на игрока — это дешевле любого кадрового
     цикла и незаметно на глаз: игрок не успевает подойти и нажать быстрее. ]]
task.spawn(function()
	while true do
		task.wait(ZONE_PERIOD)
		--[[ ⚠️ СОСТОЯНИЕ ШЛЁМ КАЖДЫЙ ТИК ТЕМ, КТО В ЗОНЕ, А НЕ ТОЛЬКО НА ПЕРЕХОДЕ.
		     На переходах интерфейс однажды показался и пропал навсегда: любая
		     потерянная посылка (или один сбойный тик, в котором лебёдка не
		     нашлась) оставляла клиента в «не в зоне» до следующего перехода,
		     которого не будет — игрок-то стоит на месте.
		     Четыре маленькие таблицы в секунду на стоящего рядом игрока — это
		     дешевле любой попытки угадать, дошло ли предыдущее сообщение.
		     Ошибку внутри ловим и печатаем ОДИН раз: без pcall упавший тик убивал
		     бы весь цикл молча, и симптом был бы ровно тем же. ]]
		local ok, err = pcall(function()
			local winch = findWinch()
			for _, plr in ipairs(Players:GetPlayers()) do
				local char = plr.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local near = false
				if hrp and winch then
					near = onAnchorCell(winch, hrp.Position)
				end
				if near then
					inZone[plr] = true
					pushState(plr, winch, true)
				elseif inZone[plr] then
					inZone[plr] = nil
					pushState(plr, winch, false)
				end
			end
		end)
		if not ok and not zoneErrLogged then
			zoneErrLogged = true
			warn("[Якорь] сбой в опросе зоны: " .. tostring(err))
		end
	end
end)

Players.PlayerRemoving:Connect(function(plr) inZone[plr] = nil end)

winchEvent.OnServerEvent:Connect(function(player, action, delta)
	if action ~= "step" then return end
	if typeof(delta) ~= "number" then return end
	-- ⚠️ Шаг принимаем только тот, что рисуют кнопки. Клиент может прислать
	-- любое число, и без этой проверки одним сообщением опускали бы якорь на
	-- сколько угодно — или на дробную величину, которой нет в интерфейсе.
	if math.abs(delta) ~= ANCHOR_STEP then return end

	local winch = findWinch()
	if not winch then return end
	if not inZone[player] then return end   -- не у лебёдки — не крутит

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	-- та же мера, что и у зоны: по пивоту кнопка отказывала бы стоящему вплотную
	if distanceToModel(winch, hrp.Position) > INTERACTION_RANGE then return end

	freeHangingPart(winch)
	local rope = findRope(winch)
	if not rope then return end
	local base, span = ropeSpan(winch, rope)
	local was = rope.Length
	local want = math.clamp(winchDepthPercent(winch) + delta, 0, 100)
	rope.Length = base + span * (want / 100)
	--[[ ⚠️ ОДНА СТРОКА В ЛОГ НА ПЕРВОЕ НАЖАТИЕ — ЧТОБЫ НЕ ГАДАТЬ.
	     «Якорь не опускается» выглядит одинаково при трёх разных причинах:
	     трос не удлиняется, груз заякорен, груз приварен к плоту. Строка ниже
	     разводит все три. Печатается один раз за сессию. ]]
	if not winchLogged then
		winchLogged = true
		-- груз — ДАЛЬНИЙ конец троса: ближний это деталь рамы, в которой лежит
		-- сам констрейнт (её как раз приваривают к плоту)
		local a0 = rope.Attachment0 and rope.Attachment0.Parent
		local a1 = rope.Attachment1 and rope.Attachment1.Parent
		local weight = (a0 and a0 ~= rope.Parent and a0)
			or (a1 and a1 ~= rope.Parent and a1) or a0 or a1
		local welds = 0
		if weight and weight:IsA("BasePart") then
			for _, d in ipairs(winch:GetDescendants()) do
				if d:IsA("WeldConstraint") and (d.Part0 == weight or d.Part1 == weight) then
					welds += 1
				end
			end
			print(("[Якорь] трос «%s» в «%s»: %.2f → %.2f (ноль шкалы %.2f) | "
				.. "груз «%s» заякорен=%s сварок=%d")
				:format(rope.Name, rope.Parent and rope.Parent.Name or "?",
					was, rope.Length, base, weight.Name,
					tostring(weight.Anchored), welds))
		else
			warn("[Якорь] у троса нет детали-груза: опускать нечего")
		end
	end
	-- ⚠️ ВВЕРХ — ВПЕРЁД, ВНИЗ — НАЗАД. delta положительна на «ВНИЗ» (глубина
	-- растёт), поэтому знак здесь перевёрнут относительно неё.
	kickWheel(winch, (delta < 0) and WHEEL_UP_DIR or -WHEEL_UP_DIR)
	-- старая модель крутится своим коротким импульсом: у неё колесо на
	-- собственном шарнире из Studio, и трогать её незачем
	pulseWheel(winch, delta > 0 and 1 or -1)
	recomputeRaftAnchoredState()

	-- состояние получают ВСЕ, кто стоит у лебёдки: якорь общий, и сосед должен
	-- видеть, что его подняли, а не гадать по звуку
	for plr in pairs(inZone) do
		if plr.Parent then pushState(plr, winch, true) end
	end
end)