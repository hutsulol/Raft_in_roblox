--[[
	ПЛАВИЛЬНЯ ПЛОТА (Raft_smelter): железо → слиток, водоросли → клей.

	Модель — слоёный конструктор (авторские детали внутри Raft_smelter):
	  raft_smelter_body            — корпус, виден всегда
	  raft_smelter_planks          — дрова: видны только пока горит огонь,
	                                 на них слабенький огонёк (как у гриля, тише)
	  raft_smelter_iron_raw        — руда в печи. Пустая печь держит её
	                                 ПРИЗРАКОМ (полупрозрачной): игрок с рудой в
	                                 руках наводится — клиент подсвечивает зелёным,
	                                 кликом ставит — призрак становится плотным
	  raft_smelter_iron_molten     — расплав: появляется, когда плавка дошла
	  raft_smelter_seaweed_raw     — то же для водорослей
	  raft_smelter_seaweed_molten  — расплав водорослей (клей)

	ЦИКЛ: бревно в топку (E, ProximityPrompt) = +1 минута огня; плавка партии
	идёт 3 минуты И ТОЛЬКО ПОКА ГОРИТ. Готовое кликом забирается в инвентарь.

	«В РУКАХ» руда/водоросли оказываются тем же механизмом, что еда:
	клик по слоту инвентаря → EquipMaterialAsTool → сервер снимает 1 со стака и
	выдаёт Tool с атрибутом MaterialResource; снял с рук — вернулось в стак.
	Наводку, зелёную подсветку и клики ведёт SmelterPlace.client.

	Состояние живёт атрибутами модели (реплицируются сами):
	  FireLeft (сек), IronState/SeaweedState = "none"|"raw"|"done",
	  IronProg/SeaweedProg (сек плавки).
]]

local RaftShake = require(game:GetService("ReplicatedStorage"):WaitForChild("RaftShake"))   -- постройка без рывка плота
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local PlaceCheck = require(game:GetService("ReplicatedStorage"):WaitForChild("PlaceCheck"))   -- «место занято» — общая проверка

local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

-- ── конфиг ──
local FUEL_PER_LOG = 60      -- 1 бревно = 1 минута огня
local SMELT_TIME   = 180     -- партия готовится 3 минуты
local MAX_LOGS     = 3       -- больше трёх брёвен разом в топку не влезает
local FIRE_CAP     = FUEL_PER_LOG * MAX_LOGS
local REACH        = 16      -- дистанция взаимодействий
-- Пустая печь ПОЛНОСТЬЮ чистая: заготовки в ней невидимы (100% прозрачности).
-- Куда ставить — показывает клиент зелёным призраком при наводке (SmelterPlace).
local GHOST_T      = 1

-- пламя — грилевый флипбук (тот же ассет, что у мангала), только слабее
local TEX_FLAME = "rbxassetid://140408648514726"

local MATERIALS = {
	Iron_Ore = {
		kind = "iron", output = "Iron_Ingot",
		rawName = "raft_smelter_iron_raw", moltenName = "raft_smelter_iron_molten",
		stateAttr = "IronState", progAttr = "IronProg",
		-- где искать меш для тула «в руках»
		toolTemplates = { "iron_model", "Iron_Ore", "Iron ore" },
		icon = "rbxassetid://78456892304314",
	},
	Seaweed = {
		kind = "seaweed", output = "Glue",
		rawName = "raft_smelter_seaweed_raw", moltenName = "raft_smelter_seaweed_molten",
		stateAttr = "SeaweedState", progAttr = "SeaweedProg",
		toolTemplates = { "Seaweed", "seaweed", "Vodorosli" },
		icon = "rbxassetid://135792112167502",
	},
}
local KIND_TO_KEY = { iron = "Iron_Ore", seaweed = "Seaweed" }

-- ── ремоуты ──
local function getOrCreate(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local actionEvent = getOrCreate("SmelterAction")
local equipEvent  = getOrCreate("EquipMaterialAsTool")

-- ── видимость слоёв ──
-- Слой бывает и Part'ом, и моделью с потрохами — красим все BasePart внутри.
local function setLayer(container, transparency)
	if not container then return end
	if container:IsA("BasePart") then container.Transparency = transparency end
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") then d.Transparency = transparency end
	end
end

local function layerOf(smelter, name)
	return smelter:FindFirstChild(name, true)
end

-- ── реестр плавилен ──
local smelters = {}   -- [model] = { body, planks, fire, prompt }

--[[ Можно ли сейчас подбросить бревно. Единственное правило: не больше
     MAX_LOGS разом (по остатку огня).

     ⚠️ РАНЬШЕ ТОПКА ЗАКРЫВАЛАСЬ НА ВРЕМЯ ПЛАВКИ — И ЭТО БЫЛА ЖАЛОБА
     «не могу закинуть дерево». Партия плавится 3 минуты, бревно горит одну.
     Игрок кладёт бревно, кладёт руду, видит, что огонь вот-вот догорит,
     тянется подбросить — а подсказка «Подбросить бревно» пропала без
     объяснений (промпт выключен). Ждать, пока огонь погаснет и плавка
     встанет, чтобы только тогда разрешили дрова, — правило, которое никто
     не угадает. Теперь дрова принимаются в любой момент, пока в топке есть
     место; отказы объясняются уведомлением (см. промпт ниже). ]]
local function fuelRoom(smelter)
	local fireLeft = smelter:GetAttribute("FireLeft") or 0
	return fireLeft <= FIRE_CAP - FUEL_PER_LOG
end
local function canFuel(smelter)
	return fuelRoom(smelter)
end

local function applyVisuals(smelter)
	local st = smelters[smelter]
	if not st then return end
	local fire = (smelter:GetAttribute("FireLeft") or 0) > 0
	if st.planks then setLayer(st.planks, fire and 0 or 1) end
	if st.flame then st.flame.Enabled = fire end
	if st.flameLight then st.flameLight.Enabled = fire end
	-- полная топка — подсказки нет; догорело до места под бревно — вернётся (см. тик плавки)
	if st.prompt then st.prompt.Enabled = canFuel(smelter) end

	for _, mat in pairs(MATERIALS) do
		local state = smelter:GetAttribute(mat.stateAttr) or "none"
		local raw = layerOf(smelter, mat.rawName)
		local molten = layerOf(smelter, mat.moltenName)
		if state == "none" then
			setLayer(raw, GHOST_T)   -- призрак-заготовка: видно, КУДА ставить
			setLayer(molten, 1)
		elseif state == "raw" then
			setLayer(raw, 0)
			setLayer(molten, 1)
		else -- done
			setLayer(raw, 1)
			setLayer(molten, 0)
		end
	end
end

local function registerSmelter(model)
	if smelters[model] then return end
	local body = layerOf(model, "raft_smelter_body")
	if not body then return end

	-- PrimaryPart обязателен: без него WorldPivot модели статичен, и когда плот
	-- с приваренной печью уплывает, GetPivot продолжает показывать точку
	-- установки — все замеры расстояния до печи врали бы всё сильнее
	if not model.PrimaryPart then
		local bodyPart = body:IsA("BasePart") and body
			or body:FindFirstChildWhichIsA("BasePart", true)
		if bodyPart then model.PrimaryPart = bodyPart end
	end

	local st = { body = body, planks = layerOf(model, "raft_smelter_planks") }
	smelters[model] = st

	-- Огонёк на дровах: ГРИЛЕВЫЙ флипбук-эмиттер, только слабее. Стоковый
	-- Instance Fire не годился дважды: выглядит чужеродно и его частицы живут
	-- в мире — плывущий плот оставлял за собой огненный шлейф. У эмиттера
	-- LockedToPart: частицы едут вместе с деталью, никакого «ветра».
	local firePart = st.planks
	if firePart and firePart:IsA("Model") then
		firePart = firePart:FindFirstChildWhichIsA("BasePart", true)
	end
	if firePart then
		local old = firePart:FindFirstChild("SmelterFire")
		if old and old:IsA("Fire") then old:Destroy() end   -- след прежней версии

		local at = firePart:FindFirstChild("SmelterFireRoot")
		if not at then
			at = Instance.new("Attachment")
			at.Name = "SmelterFireRoot"
			at.Position = Vector3.new(0, firePart.Size.Y * 0.35, 0)
			at.Parent = firePart
		end

		local flame = at:FindFirstChild("SmelterFire")
		if not flame then
			flame = Instance.new("ParticleEmitter")
			flame.Name = "SmelterFire"
			flame.Texture = TEX_FLAME
			flame.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
			flame.FlipbookFramerate = NumberRange.new(20, 20)
			flame.FlipbookMode = Enum.ParticleFlipbookMode.Loop
			flame.FlipbookStartRandom = true   -- иначе все языки пульсируют хором
			flame.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
			flame.Rate = 9
			flame.Lifetime = NumberRange.new(0.35, 0.55)
			flame.Speed = NumberRange.new(0.4, 0.8)
			flame.SpreadAngle = Vector2.new(6, 6)
			flame.Acceleration = Vector3.new(0, 1.6, 0)
			flame.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.32),
				NumberSequenceKeypoint.new(0.35, 0.5),
				NumberSequenceKeypoint.new(1, 0.1),
			})
			flame.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.15),
				NumberSequenceKeypoint.new(0.6, 0.05),
				NumberSequenceKeypoint.new(1, 1),
			})
			flame.LightEmission = 1
			flame.LightInfluence = 0
			flame.ZOffset = 0.05
			flame.LockedToPart = true
			flame.Enabled = false
			flame.Parent = at
		end
		st.flame = flame

		local light = at:FindFirstChild("SmelterFireLight")
		if not light then
			light = Instance.new("PointLight")
			light.Name = "SmelterFireLight"
			light.Color = Color3.fromRGB(255, 140, 55)
			light.Brightness = 1.2
			light.Range = 6
			light.Enabled = false
			light.Parent = at
		end
		st.flameLight = light
	end

	-- топка: бревно по E
	local promptHost = body:IsA("BasePart") and body or body:FindFirstChildWhichIsA("BasePart", true)
	if promptHost then
		--[[ ⚠️ Промпт, который уже висит на детали (старая копия, клон живой печи),
		     раньше просто пропускался: st.prompt оставался nil, Triggered никто
		     не слушал, и «E» молча ничего не делала. Теперь чужой промпт сносим
		     и вешаем свой — с живым обработчиком. ]]
		local old = promptHost:FindFirstChild("SmelterFuelPrompt")
		if old then old:Destroy() end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "SmelterFuelPrompt"
		prompt.ActionText = "Подбросить бревно"
		prompt.ObjectText = "Плавильня"
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		-- на тесном плоту рядом сундук, лежанка, грядка — все на «E». По умолчанию
		-- Roblox показывает один промпт на клавишу, ближайший, и печь проигрывала
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
		prompt.Parent = promptHost
		prompt.Triggered:Connect(function(player)
			local inv = _G.GetInventory and _G.GetInventory(player)
			if not inv or (inv.Log or 0) < 1 then
				if _G.NotifyPlayer then
					_G.NotifyPlayer(player, { type = "warn", icon = "log", title = "Нет брёвен",
						body = "Наруби дерева — одно бревно горит минуту" })
				end
				return
			end
			if not canFuel(model) then
				if _G.NotifyPlayer then
					_G.NotifyPlayer(player, { type = "warn", icon = "🔥", title = "Топка полна",
						body = ("Больше %d брёвен разом не влезает"):format(MAX_LOGS) })
				end
				return
			end
			local left = model:GetAttribute("FireLeft") or 0
			if _G.RemoveResourceFromInventory then
				_G.RemoveResourceFromInventory(player, "Log", 1)
			end
			if _G.SendInventory then _G.SendInventory(player) end
			model:SetAttribute("FireLeft", math.min(left + FUEL_PER_LOG, FIRE_CAP))
			applyVisuals(model)
		end)
		st.prompt = prompt
	end

	-- стартовое состояние
	for _, mat in pairs(MATERIALS) do
		if model:GetAttribute(mat.stateAttr) == nil then
			model:SetAttribute(mat.stateAttr, "none")
			model:SetAttribute(mat.progAttr, 0)
		end
	end
	if model:GetAttribute("FireLeft") == nil then
		model:SetAttribute("FireLeft", 0)
	end
	applyVisuals(model)
	print("[Плавильня] подключена: " .. model:GetFullName())
end

local function scan()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name:lower():find("raft_smelter", 1, true) then
			registerSmelter(d)
		end
	end
	for model in pairs(smelters) do
		if not model.Parent then smelters[model] = nil end
	end
end

-- ── плавка ──
task.spawn(function()
	while true do
		task.wait(0.5)
		for smelter in pairs(smelters) do
			if smelter.Parent then
				local fire = smelter:GetAttribute("FireLeft") or 0
				if fire > 0 then
					smelter:SetAttribute("FireLeft", math.max(0, fire - 0.5))
					-- огонь догорел до места под ещё одно бревно → подсказка возвращается
					local st = smelters[smelter]
					if st and st.prompt then
						local can = canFuel(smelter)
						if st.prompt.Enabled ~= can then st.prompt.Enabled = can end
					end
					local changed = false
					for _, mat in pairs(MATERIALS) do
						if smelter:GetAttribute(mat.stateAttr) == "raw" then
							local p = (smelter:GetAttribute(mat.progAttr) or 0) + 0.5
							smelter:SetAttribute(mat.progAttr, p)
							if p >= SMELT_TIME then
								smelter:SetAttribute(mat.stateAttr, "done")
								changed = true
							end
						end
					end
					-- огонь мог догореть на этом тике / партия дошла
					if changed or (smelter:GetAttribute("FireLeft") or 0) <= 0 then
						applyVisuals(smelter)
					end
				end
			end
		end
	end
end)

-- периодический поиск новых плавилен (поставили/заспавнили)
task.spawn(function()
	while true do
		scan()
		task.wait(5)
	end
end)

-- ── дистанция ──
local function inReach(player, smelter)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local st = smelters[smelter]
	local ref = st and (st.body:IsA("BasePart") and st.body
		or st.body:FindFirstChildWhichIsA("BasePart", true))
	if not hrp or not ref then return false end
	return (hrp.Position - ref.Position).Magnitude <= REACH + 6
end

-- ── установка и сбор ──
actionEvent.OnServerEvent:Connect(function(player, action, smelter, kind)
	if typeof(action) ~= "string" or typeof(kind) ~= "string" then return end
	if typeof(smelter) ~= "Instance" or not smelters[smelter] then return end
	if not inReach(player, smelter) then return end
	local key = KIND_TO_KEY[kind]
	local mat = key and MATERIALS[key]
	if not mat then return end

	if action == "place" then
		if (smelter:GetAttribute(mat.stateAttr) or "none") ~= "none" then return end
		-- сырьё обязано быть В РУКАХ: это и есть проверка честности клиента
		local char = player.Character
		local tool = char and char:FindFirstChildWhichIsA("Tool")
		if not tool or tool:GetAttribute("MaterialResource") ~= key then return end
		tool:SetAttribute("Consumed", true)   -- рефанду при снятии больше не бывать
		tool:Destroy()
		smelter:SetAttribute(mat.stateAttr, "raw")
		smelter:SetAttribute(mat.progAttr, 0)
		applyVisuals(smelter)

	elseif action == "collect" then
		if smelter:GetAttribute(mat.stateAttr) ~= "done" then return end
		if _G.AddResourceToInventory then
			_G.AddResourceToInventory(player, mat.output, 1, nil)
		end
		if _G.SendInventory then _G.SendInventory(player) end
		smelter:SetAttribute(mat.stateAttr, "none")
		smelter:SetAttribute(mat.progAttr, 0)
		applyVisuals(smelter)
	end
end)

-- ── материал в руки (зеркало EquipFoodAsTool из FoodSystem) ──
local function findToolTemplate(mat)
	local containers = { ServerStorage:FindFirstChild("Resourses"), ServerStorage, ReplicatedStorage }
	for _, name in ipairs(mat.toolTemplates) do
		for _, c in ipairs(containers) do
			if c then
				local t = c:FindFirstChild(name, true)
				if t then return t end
			end
		end
	end
	return nil
end

local function makeMaterialTool(key, mat)
	local tool = Instance.new("Tool")
	tool.Name = key
	tool.CanBeDropped = false
	if mat.icon then tool.TextureId = mat.icon end

	local tpl = findToolTemplate(mat)
	local handle
	if tpl then
		local src = tpl:IsA("BasePart") and tpl or tpl:FindFirstChildWhichIsA("BasePart", true)
		if src then handle = src:Clone() end
	end
	if not handle then
		-- Шаблона нет — берём меш «сырого» слоя с любой плавильни: он всегда есть.
		-- ⚠️ Клон приезжает С ЕЁ СВАРКАМИ (каждая деталь печи приварена к плоту) —
		-- их обязательно вычистить ниже, иначе тул притянет игрока к плавильне.
		for smelter in pairs(smelters) do
			local raw = layerOf(smelter, mat.rawName)
			local src = raw and (raw:IsA("BasePart") and raw or raw:FindFirstChildWhichIsA("BasePart", true))
			if src then
				handle = src:Clone()
				break
			end
		end
	end
	if not handle then
		handle = Instance.new("Part")
		handle.Size = Vector3.new(1, 1, 1)
	end

	handle.Name = "Handle"
	handle.Transparency = 0
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Massless = true

	-- ⚠️ ЧИСТИМ ВСЁ, ЧТО ПРИЕХАЛО С КЛОНОМ. Шаблона в ReplicatedStorage может не
	-- быть, и тогда деталь снимается копией со СТОЯЩЕЙ плавильни — вместе с её
	-- сварками. Клон сварки держит ссылку на деталь печи, и как только тул
	-- попадал в руки, персонаж прирастал к плавильне: его к ней и утаскивало.
	-- Заодно убираем чужие эффекты, промпты и скрипты — в руке им делать нечего.
	for _, d in ipairs(handle:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint")
			or d:IsA("ProximityPrompt") or d:IsA("ClickDetector")
			or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("ParticleEmitter")
			or d:IsA("Light") or d:IsA("Sound")
			or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	-- в руке вещь не должна быть размером с печку
	local m = math.max(handle.Size.X, handle.Size.Y, handle.Size.Z)
	if m > 1.8 then
		handle.Size = handle.Size * (1.8 / m)
	end
	handle.Parent = tool
	return tool
end

equipEvent.OnServerEvent:Connect(function(player, key)
	if typeof(key) ~= "string" then return end
	local mat = MATERIALS[key]
	if not mat then return end

	local char = player.Character
	local backpack = player:FindFirstChild("Backpack")
	if not char or not backpack then return end

	-- уже держит материал — сначала вернуть его в стак (свап без потерь)
	for _, container in ipairs({ char, backpack }) do
		for _, t in ipairs(container:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute("MaterialResource")
				and not t:GetAttribute("Consumed") and not t:GetAttribute("Refunded") then
				t:SetAttribute("Refunded", true)
				if _G.AddResourceToInventory then
					_G.AddResourceToInventory(player, t:GetAttribute("MaterialResource"), 1, nil)
				end
				t:Destroy()
			end
		end
	end

	local inv = _G.GetInventory and _G.GetInventory(player)
	if not inv or (inv[key] or 0) < 1 then
		if _G.SendInventory then _G.SendInventory(player) end
		return
	end
	if _G.RemoveResourceFromInventory then
		_G.RemoveResourceFromInventory(player, key, 1)
	end
	if _G.SendInventory then _G.SendInventory(player) end

	local tool = makeMaterialTool(key, mat)
	tool:SetAttribute("MaterialResource", key)
	tool:SetAttribute("OwnerUserId", player.UserId)
	tool.Parent = backpack

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		pcall(function() hum:UnequipTools() end)
		pcall(function() hum:EquipTool(tool) end)
	end

	-- рефанд при снятии с рук: страж взводится ПОСЛЕ первого Equipped, иначе
	-- перекладка Backpack→Character при EquipTool сама выглядит как «снял»
	tool.Equipped:Once(function()
		tool:SetAttribute("Armed", true)
	end)
	tool.AncestryChanged:Connect(function(_, parent)
		if not tool:GetAttribute("Armed") then return end
		if tool:GetAttribute("Consumed") or tool:GetAttribute("Refunded") then return end
		if parent == nil or parent:IsA("Backpack") then
			tool:SetAttribute("Refunded", true)
			if _G.AddResourceToInventory then
				_G.AddResourceToInventory(player, key, 1, nil)
			end
			if _G.SendInventory then _G.SendInventory(player) end
			task.defer(function()
				if tool.Parent then tool:Destroy() end
			end)
		end
	end)
end)

-- ── УСТАНОВКА НА ПЛОТ (крафт "Raft_smelter" → призрак SmelterBuildPlace →
-- сюда прилетает смещение относительно плота; путь печки FurnaceCraft) ──
local cupActionEvent = getOrCreate("CupAction")

local function findPlaceTemplate()
	local t = AssetFind.find("Raft_smelter")
	if t then return t end
	-- шаблона в RS нет — снимаем копию с уже стоящей плавильни
	for smelter in pairs(smelters) do
		if smelter.Parent then return smelter end
	end
	return nil
end

cupActionEvent.OnServerEvent:Connect(function(player, action, target)
	if action ~= "placeSmelter" then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Raft_smelter" then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end
	if typeof(target) ~= "CFrame" then return end

	local template = findPlaceTemplate()
	if not template then
		warn("[Плавильня] шаблона Raft_smelter нет ни в ReplicatedStorage, ни в мире — ставить нечего")
		return
	end

	local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)
	local smelter = template:Clone()
	smelter.Name = "Raft_smelter"

	-- клон мог сняться с ЖИВОЙ плавильни: вычищаем её состояние и обвес,
	-- registerSmelter соберёт всё заново с нуля
	for _, attr in ipairs({ "FireLeft", "IronState", "SeaweedState", "IronProg", "SeaweedProg" }) do
		smelter:SetAttribute(attr, nil)
	end
	for _, d in ipairs(smelter:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript")
			or d.Name == "SmelterFire" or d.Name == "SmelterFireRoot"
			or d.Name == "SmelterFireLight"
			or (d:IsA("ProximityPrompt") and d.Name == "SmelterFuelPrompt") then
			d:Destroy()
		end
	end

	if smelter:IsA("Model") then
		local bbCF = smelter:GetBoundingBox()
		smelter.WorldPivot = CFrame.new(bbCF.Position)
	end
	smelter:PivotTo(worldCF)
	if PlaceCheck.refuseIfBlocked(smelter, raft, player) then return end   -- в предмет ставить нельзя
	smelter.Parent = raft

	-- как у печки: заякорить → приварить к плоту → отпустить, скорость вернуть
	local primary = raft.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity
	for _, part in ipairs(smelter:GetDescendants()) do
		if part:IsA("BasePart") then part.Anchored = true end
	end
	for _, part in ipairs(smelter:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Massless = true   -- без массы: иначе сборка теряет ход (рывок плота)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = primary
			weld.Parent = part
		end
	end
	for _, part in ipairs(smelter:GetDescendants()) do
		if part:IsA("BasePart") then part.Anchored = false end
	end
	primary.AssemblyLinearVelocity = linVel
	primary.AssemblyAngularVelocity = angVel
	RaftShake.notify()   -- скорость ещё раз после шага физики + удержать игроков (RaftShake)

	tool:Destroy()
	registerSmelter(smelter)
	print(("[Плавильня] %s поставил плавильню на плот"):format(player.Name))
end)

scan()
print(("[Плавильня] готова: бревно = %d сек огня, плавка %d сек; железо → слиток, водоросли → клей")
	:format(FUEL_PER_LOG, SMELT_TIME))
