--[[
	ТОПЛИВО: КАНИСТРА ИГРОКА, КАНИСТРЫ НА КАТЕРАХ, БАК НА ПЛОТУ.

	Всё считается в МИЛЛИЛИТРАХ. Канистра игрока — 3 литра, канистра на катере —
	600–900 мл (одна даёт 20–30% канистры), бак на плоту — 50 литров.

	Два направления перелива, и оба работают одинаково:
	  • канистра на КАТЕРЕ  → канистра игрока  («Наливать»)
	  • канистра игрока     → БАК на плоту     («Заливать»)

	НАЛИВ ПЛАВНЫЙ: пока игрок держит кнопку, топливо идёт порциями по POUR_TICK, и
	шкала над хотбаром (как и цифра на баке) ползёт непрерывно. Отпустил — перелив
	встал, перелитое осталось. Кольцо подсказки заведено ровно на время перелива,
	чтобы показывать прогресс, а не жить своей жизнью.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OilCanister = require(ReplicatedStorage:WaitForChild("OilCanister"))

-- ⚠️ ТЕСТОВЫЙ РЕЖИМ: бак на плоту стартует полным (100 л). Выключить перед
-- релизом — топливо должно добываться с катеров, иначе механика теряет смысл.
local TEST_FULL_TANK = true

local notifyEvent = ReplicatedStorage:FindFirstChild("CanisterNotify")
if not notifyEvent then
	notifyEvent = Instance.new("RemoteEvent")
	notifyEvent.Name = "CanisterNotify"
	notifyEvent.Parent = ReplicatedStorage
end

-- ═══════════ канистра игрока ═══════════
local function initCanister(tool)
	if not OilCanister.isCanister(tool) then return end
	-- Объём — свойство самой механики, а не конкретной канистры: выставляем всегда.
	-- Заодно чинятся канистры, скрафченные до перехода на миллилитры.
	tool:SetAttribute(OilCanister.ATTR_CAP, OilCanister.CAPACITY)
	local fill = tool:GetAttribute(OilCanister.ATTR_FILL)
	if type(fill) ~= "number" then
		tool:SetAttribute(OilCanister.ATTR_FILL, 0)
	elseif fill > OilCanister.CAPACITY then
		tool:SetAttribute(OilCanister.ATTR_FILL, OilCanister.CAPACITY)
	end
end

-- Канистру берём и из рук, и из рюкзака: доставать её ради заправки незачем.
local function anyCanister(player)
	local char = player.Character
	if char then
		for _, t in ipairs(char:GetChildren()) do
			if OilCanister.isCanister(t) then return t end
		end
	end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then
		for _, t in ipairs(bp:GetChildren()) do
			if OilCanister.isCanister(t) then return t end
		end
	end
	return nil
end

-- ═══════════ ёмкости ═══════════
-- Единый интерфейс для всего, что может отдавать и принимать топливо: так один и
-- тот же цикл перелива обслуживает и «с катера в канистру», и «из канистры в бак».
local function canisterVessel(tool)
	local cap = tool:GetAttribute(OilCanister.ATTR_CAP) or OilCanister.CAPACITY
	return {
		get   = function() return tool:GetAttribute(OilCanister.ATTR_FILL) or 0 end,
		set   = function(v) tool:SetAttribute(OilCanister.ATTR_FILL, v) end,
		room  = function() return math.max(0, cap - (tool:GetAttribute(OilCanister.ATTR_FILL) or 0)) end,
		alive = function() return tool.Parent ~= nil end,
	}
end

local function boatCanVessel(part)
	local A = OilCanister.SOURCE_LEFT_ATTR
	return {
		get   = function() local v = part:GetAttribute(A); return (type(v) == "number") and math.max(0, v) or 0 end,
		set   = function(v) part:SetAttribute(A, v) end,
		room  = function() return 0 end,   -- обратно в неё не льют
		alive = function() return part.Parent ~= nil end,
	}
end

local function tankVessel(tank)
	local A = OilCanister.TANK_ATTR
	return {
		get   = function() return OilCanister.tankStored(tank) end,
		set   = function(v) tank:SetAttribute(A, v) end,
		room  = function() return math.max(0, OilCanister.TANK_CAPACITY - OilCanister.tankStored(tank)) end,
		alive = function() return tank.Parent ~= nil end,
	}
end

-- ═══════════ перелив ═══════════
local pouring = {}   -- [prompt] = state

local function stopPour(prompt, reason)
	local state = pouring[prompt]
	if not state then return end
	pouring[prompt] = nil
	if state.moved > 0 then
		notifyEvent:FireClient(state.player, state.okKind, math.floor(state.moved))
	elseif reason then
		notifyEvent:FireClient(state.player, reason)
	end
end

-- src → dst, порциями, пока держат кнопку. okKind/emptyKind/fullKind — что сказать
-- игроку по итогу: у двух направлений разные слова.
local function startPour(prompt, player, part, src, dst, kinds)
	stopPour(prompt)

	if src.get() <= 0 then
		notifyEvent:FireClient(player, kinds.empty)
		return
	end
	if dst.room() <= 0 then
		notifyEvent:FireClient(player, kinds.full)
		return
	end

	local state = { player = player, moved = 0, okKind = kinds.ok }
	pouring[prompt] = state

	task.spawn(function()
		while pouring[prompt] == state do
			-- отошёл — перелив прекращается сам, не дожидаясь отпускания кнопки
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not (part.Parent and hrp and src.alive() and dst.alive()) then break end
			if (hrp.Position - part.Position).Magnitude > OilCanister.REACH + 4 then break end

			local step = math.min(OilCanister.POUR_RATE * OilCanister.POUR_TICK,
				src.get(), dst.room())
			if step <= 0 then
				-- важно, ЧТО именно кончилось: пусто в источнике или полно в приёмнике
				stopPour(prompt, (src.get() <= 0) and kinds.empty or kinds.full)
				return
			end
			src.set(src.get() - step)
			dst.set(dst.get() + step)
			state.moved += step
			task.wait(OilCanister.POUR_TICK)
		end
		stopPour(prompt)
	end)
end

-- Кольцо подсказки заводим ровно на время перелива: сколько реально перельётся.
-- Тогда полное кольцо честно значит «больше не влезет / больше нечего лить».
local function armPrompt(prompt, src, dst)
	local ml = math.min(src.get(), dst.room())
	prompt.HoldDuration = math.clamp(ml / OilCanister.POUR_RATE, 0.3, 10)
end

local function makePrompt(part, actionText, objectText)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OilPrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 2
	prompt.MaxActivationDistance = OilCanister.REACH
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return prompt
end

-- ═══════════ канистры на катерах ═══════════
local function setupSource(source)
	if not OilCanister.isSource(source) then return end
	local part = source:IsA("BasePart") and source
		or (source:IsA("Model") and (source.PrimaryPart or source:FindFirstChildWhichIsA("BasePart", true)))
	if not part or part:FindFirstChild("OilPrompt") then return end

	-- Запас: случайный в заданных пределах, но ОДИН раз — дальше живёт в атрибуте и
	-- переживает и обыск соседнего груза, и уход-возврат игрока.
	if type(source:GetAttribute(OilCanister.SOURCE_LEFT_ATTR)) ~= "number" then
		source:SetAttribute(OilCanister.SOURCE_LEFT_ATTR,
			math.random(OilCanister.SOURCE_ML_MIN, OilCanister.SOURCE_ML_MAX))
	end

	local prompt = makePrompt(part, OilCanister.PROMPT_TEXT, OilCanister.PROMPT_OBJECT)
	-- груз на катере не толкает игрока, но подсказку ловить должен
	part.CanCollide = false
	part.CanQuery = true

	local src = boatCanVessel(source)
	local KINDS = { ok = "filled", empty = "empty_source", full = "full" }

	prompt.PromptShown:Connect(function(player)
		local tool = anyCanister(player)
		armPrompt(prompt, src, tool and canisterVessel(tool) or { room = function() return 0 end })
	end)
	prompt.PromptButtonHoldBegan:Connect(function(player)
		local tool = anyCanister(player)
		if not tool then notifyEvent:FireClient(player, "no_canister") return end
		startPour(prompt, player, part, src, canisterVessel(tool), KINDS)
	end)
	prompt.PromptButtonHoldEnded:Connect(function() stopPour(prompt) end)
	prompt.Triggered:Connect(function() stopPour(prompt) end)

	-- Опустела — подсказка уходит совсем, чтобы игрок не жал в пустоту.
	local function sync() prompt.Enabled = src.get() > 0 end
	source:GetAttributeChangedSignal(OilCanister.SOURCE_LEFT_ATTR):Connect(sync)
	sync()
end

-- ═══════════ бак на плоту ═══════════
local function setupTank(tank)
	local funnel = OilCanister.findTankPart(tank, OilCanister.TANK_FUNNEL)
	-- Воронки может не быть в модели — тогда льём в сам бак, а не молчим.
	funnel = funnel or (tank:IsA("Model") and (tank.PrimaryPart or tank:FindFirstChildWhichIsA("BasePart", true)))
	if not funnel or funnel:FindFirstChild("OilPrompt") then return end

	if type(tank:GetAttribute(OilCanister.TANK_ATTR)) ~= "number" then
		tank:SetAttribute(OilCanister.TANK_ATTR, 0)
	end

	-- ⚠️ ТЕСТОВАЯ ЗАЛИВКА. Пока проверяем огнемёт, бак на старте полный — чтобы
	-- не мотаться за нефтью на катера ради каждой заправки. Перед релизом
	-- поставить false: иначе топливо перестанет быть ресурсом.
	if TEST_FULL_TANK then
		tank:SetAttribute(OilCanister.TANK_ATTR, OilCanister.TANK_CAPACITY)
	end
	funnel.CanQuery = true

	local prompt = makePrompt(funnel, OilCanister.TANK_PROMPT, OilCanister.TANK_OBJECT)
	local dst = tankVessel(tank)
	local KINDS = { ok = "stored", empty = "canister_empty", full = "tank_full" }

	-- ⚠️ ОДНА КНОПКА НА ДВА ДЕЙСТВИЯ, ПО ТОМУ, ЧТО В РУКАХ.
	-- Раньше огнемёт вешал на ту же воронку свой второй промпт, и рядом росли
	-- две кнопки — игрок жал не ту и получал «в канистре пусто». Теперь кнопка
	-- одна и смотрит на руки: канистра — заливаем бак, огнемёт — заправляем
	-- огнемёт, пусто — говорим, что взять, и ничего не делаем.
	local function heldNamed(player, name)
		local char = player.Character
		if not char then return nil end
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") and t.Name == name then return t end
		end
		return nil
	end

	local function modeOf(player)
		if heldNamed(player, "Flamethrower") then return "flame" end
		if heldNamed(player, OilCanister.TOOL_NAME) then return "canister" end
		return "empty"
	end

	-- Бак огнемёта — такая же ёмкость, как канистра, поэтому и заправляется тем
	-- же переливом: держишь — льётся, отпустил — осталось сколько успело. Одним
	-- нажатием «сразу полный» было проще, но тогда топливо перестаёт быть
	-- ресурсом: отлить половину и уйти становится невозможно.
	local Flame = require(ReplicatedStorage:WaitForChild("FlamethrowerDefs"))
	local function flameVessel(tool)
		local cap = tool:GetAttribute(Flame.ATTR_CAP) or Flame.CAPACITY
		return {
			get   = function() return tool:GetAttribute(Flame.ATTR_FUEL) or 0 end,
			set   = function(v) tool:SetAttribute(Flame.ATTR_FUEL, v) end,
			room  = function() return math.max(0, cap - (tool:GetAttribute(Flame.ATTR_FUEL) or 0)) end,
			alive = function() return tool.Parent ~= nil end,
		}
	end
	local FLAME_KINDS = { ok = "flame_filled", empty = "tank_empty", full = "flame_full" }

	prompt.PromptShown:Connect(function(player)
		local mode = modeOf(player)
		if mode == "flame" then
			prompt.ActionText = "Заправить огнемёт"
			armPrompt(prompt, dst, flameVessel(heldNamed(player, "Flamethrower")))
		elseif mode == "canister" then
			prompt.ActionText = OilCanister.TANK_PROMPT
			armPrompt(prompt, canisterVessel(heldNamed(player, OilCanister.TOOL_NAME)), dst)
		else
			prompt.ActionText = "Возьми в руки канистру или огнемёт"
			prompt.HoldDuration = 0
		end
	end)

	prompt.PromptButtonHoldBegan:Connect(function(player)
		local mode = modeOf(player)
		if mode == "canister" then
			startPour(prompt, player, funnel,
				canisterVessel(heldNamed(player, OilCanister.TOOL_NAME)), dst, KINDS)
		elseif mode == "flame" then
			-- из бака В ОГНЕМЁТ, тем же плавным переливом
			startPour(prompt, player, funnel,
				dst, flameVessel(heldNamed(player, "Flamethrower")), FLAME_KINDS)
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function() stopPour(prompt) end)
	prompt.Triggered:Connect(function() stopPour(prompt) end)

	print(("[Канистра] бак %s найден, в нём %s"):format(tank.Name,
		OilCanister.formatVolume(OilCanister.tankStored(tank))))
end

-- ═══════════ подписки ═══════════
local function watchContainer(container)
	if not container then return end
	for _, d in ipairs(container:GetDescendants()) do initCanister(d) end
	container.DescendantAdded:Connect(initCanister)
end

local function onPlayer(player)
	watchContainer(player:FindFirstChildOfClass("Backpack"))
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then watchContainer(child) end
	end)
	if player.Character then watchContainer(player.Character) end
	player.CharacterAdded:Connect(watchContainer)
end

for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end
Players.PlayerAdded:Connect(onPlayer)

-- Канистры ищем и среди уже стоящих, и среди тех, что приплывут позже: катера
-- спавнятся по расписанию, их груз появляется в Workspace на ходу.
for _, d in ipairs(workspace:GetDescendants()) do setupSource(d) end
workspace.DescendantAdded:Connect(function(inst)
	-- атрибуты приезжают отдельным пакетом от самого инстанса, поэтому не в тот же кадр
	task.defer(setupSource, inst)
end)

-- Бак стоит на плоту с самого начала, но плот собирается не мгновенно.
task.spawn(function()
	for _ = 1, 60 do
		local tank = OilCanister.findTank(workspace)
		if tank then setupTank(tank) return end
		task.wait(1)
	end
	warn("[Канистра] бак (" .. OilCanister.TANK_NAMES[1] .. ") в Workspace не найден — заливать некуда")
end)

print(("[Канистра] топливо готово: канистра %s, канистра на катере %d–%d мл, бак %s")
	:format(OilCanister.formatVolume(OilCanister.CAPACITY),
		OilCanister.SOURCE_ML_MIN, OilCanister.SOURCE_ML_MAX,
		OilCanister.formatVolume(OilCanister.TANK_CAPACITY)))
