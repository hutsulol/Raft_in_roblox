--[[
	TreeFarmSystem.server.lua — пассивная добыча дерева («ДОБЫЧА ДЕРЕВА»).

	Общая островная ферма: игрок тратит 1 «жителя» (валюта Villagers) и строит
	ферму на борде Tree_Farm. Появляются рабочие-villager'ы, которые по кругу:
	рубят дерево → несут бревно на склад → отдыхают на свободном месте → снова рубят.
	Склад накапливает брёвна; игрок открывает его как сундук (общий ContainerUI)
	и забирает брёвна в инвентарь.

	Состояние фермы — атрибуты на модели борда (Built / SpeedLevel / WorkersLevel /
	RestLevel). Сервер авторитетен и сам обновляет тексты/видимость GUI борда.
	Клиентский скрипт (TreeFarmBoard.client.lua) только вешает клики на кнопки.

	ВСЕ пути к моделям/партам и числа — в CFG ниже. При старте печатает, что нашёл
	и что нет, — подгони CFG под свою иерархию по выводу в Output.

	Интеграция (уже в проекте):
	  • инвентарь: _G.AddResourceToInventory / _G.RemoveResourceFromInventory / _G.GetInventory
	  • валюта: _G.SpendVillagers (VillagersCurrency.server.lua)
	  • склад как сундук: RemoteEvent OpenContainer + ContainerAction + ContainerUI.client.lua
--]]

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")
local CollectionService  = game:GetService("CollectionService")
local RunService         = game:GetService("RunService")

--====================================================
-- КОНФИГ
--====================================================

local CFG = {
	-- Модель борда (их может быть несколько; ищем по имени в Workspace).
	BOARD_NAME   = "Tree_Farm",
	-- Внутри борда: парт с GUI Unwork/Work, и точка спавна рабочих.
	BOARD_PART   = "Part",            -- BasePart, на котором висят Unwork/Work
	UNWORK_GUI   = "Unwork",          -- GUI «не построено» (lock + кнопка Начать)
	WORK_GUI     = "Work",            -- GUI «построено» (апгрейды)
	WORK_FRAME   = "Frame",           -- контейнер с категориями внутри Work
	SPAWN_NAME   = "Spawnpoint_Work", -- точка появления рабочего (в борде ИЛИ в Workspace)

	-- Дерево, которое рубят, и места отдыха.
	TREE_NAME    = "Palm_Solo",  -- модель дерева (внешняя обёртка); внутри Palm + парты Sit
	PALM_NAME    = "Palm",       -- ствол (точка рубки + габарит); парты Sit лежат РЯДОМ с ним в Palm_Solo
	SIT_NAME     = "Sit",        -- парты-места отдыха (внутри модели дерева)
	CHOP_RADIUS_PAD = 1.2,       -- стоят вплотную к стволу (топор достаёт), не далеко

	-- Склад.
	STORAGE_NAME     = "Storage_Palm",
	STORAGE_BUILDING = "Storage",  -- видимый парт здания (на нём промпт E — перед складом)
	STORAGE_TRIGGER  = "Triger",   -- запасной парт-якорь
	STORAGE_SLOTS    = 12,

	-- Кокосы: при рубке есть шанс добыть ещё и кокос (нужен для апгрейда отдыха).
	COCONUT_RESOURCE = "Coconut",
	COCONUT_CHANCE   = 0.3,        -- шанс кокоса за цикл рубки (0..1)

	-- Эффект щепок при ударе топором (Part с ParticleEmitter в ReplicatedStorage).
	AXE_EFFECT_NAME    = "Axe_Effect",
	AXE_EFFECT_EMIT    = 14,   -- частиц за удар (burst); можно переопределить атрибутом EmitCount на парте
	AXE_EFFECT_HEIGHT  = 1.0,  -- высота точки удара над корнем рабочего (HRP); X/Z берём на поверхности ствола

	-- Рабочий (R6 Humanoid). Шаблон ищем в ServerStorage/ReplicatedStorage/Workspace.
	WORKER_TEMPLATE = "Villager_Axe",
	WORKER_FOLDER   = "TreeFarmWorkers",
	DEPOSIT_RESOURCE = "Log",   -- что кладёт на склад (бревно = Log)

	-- Числа баланса.
	BUILD_COST_VILLAGERS = 1,
	WORKERS_MAX = 3,
	SPEED_MAX   = 20,
	REST_MAX    = 10,

	CHOP_BASE = 60, CHOP_STEP = 5,  CHOP_MIN = 10,  -- время рубки: 60 → 55 → … (мин 10)
	REST_BASE = 30, REST_STEP = 2.5, REST_MIN = 5,  -- время отдыха: 30 → … (мин 5)
	-- Скорость передвижения рабочих (studs/сек). Прокачка Speed НЕ ускоряет ходьбу —
	-- она только сокращает время рубки. Бег включается, когда Speed прокачан выше
	-- RUN_SPEED_LEVEL. Игрок по умолчанию ходит на 16 — тут заметно медленнее.
	WORKER_WALK_SPEED = 6,
	WORKER_RUN_SPEED  = 9,
	RUN_SPEED_LEVEL = 10, -- выше этого уровня Speed — бег (Run) вместо ходьбы
	DROP_TIME = 1.2,   -- длительность анимации выкладки
	REACH = 4.5,       -- считаем «дошёл», если ближе этого (по горизонтали)
	DEPOSIT_REACH = 2, -- к Trigger подходим ближе, чтобы встать на него

	-- Цена апгрейдов: {item=имя ресурса/валюты, amount=сколько, currency="inventory"|"villagers"}.
	-- ПОДГОНИ под свою экономику. На картинке: Speed=5 брёвен, Workers=5 «пиратов»(?),
	-- Rest=5 кокосов. «Пиратов» как валюты нет — по умолчанию Workers стоит жителей.
	COST = {
		Speed   = { item = "Log",      amount = 5, currency = "inventory" },
		Workers = { item = "Villagers", amount = 5, currency = "villagers" },
		Rest    = { item = "Coconut",  amount = 5, currency = "inventory" },
	},

	MAX_STACK = 30,
}

-- Соответствие категории апгрейда → атрибут уровня и имя фрейма в GUI Work.
local CATS = {
	Speed   = { attr = "SpeedLevel",   frame = "Speed",     max = CFG.SPEED_MAX },
	Workers = { attr = "WorkersLevel", frame = "Workers",   max = CFG.WORKERS_MAX },
	Rest    = { attr = "RestLevel",    frame = "Rest_time", max = CFG.REST_MAX },
}

--====================================================
-- RemoteEvents
--====================================================

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local TreeFarmAction = ensureRemote("TreeFarmAction")
local OpenContainer  = ensureRemote("OpenContainer")
local ContainerAction = ensureRemote("ContainerAction")

--====================================================
-- ОБЩИЕ ХЕЛПЕРЫ
--====================================================

local function findDeep(root, name)
	if not root then return nil end
	if root:FindFirstChild(name) then return root:FindFirstChild(name) end
	return root:FindFirstChild(name, true)
end

local function partPosition(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then
		if inst.PrimaryPart then return inst.PrimaryPart.Position end
		local p = inst:FindFirstChildWhichIsA("BasePart", true)
		return p and p.Position or nil
	end
	return nil
end

local function flatDist(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

--====================================================
-- СКЛАД (контейнер на атрибутах, открывается общим ContainerUI)
--====================================================

local function storageSlots(storage)
	return storage:GetAttribute("SlotCount") or CFG.STORAGE_SLOTS
end

-- Добавить ресурс в слоты склада. Возвращает остаток, который не влез (overflow).
local function addToStorage(storage, item, amount)
	local n = storageSlots(storage)
	for i = 1, n do
		if storage:GetAttribute("Slot" .. i .. "_Name") == item then
			local ct = storage:GetAttribute("Slot" .. i .. "_Count") or 0
			if ct < CFG.MAX_STACK then
				local add = math.min(amount, CFG.MAX_STACK - ct)
				storage:SetAttribute("Slot" .. i .. "_Count", ct + add)
				amount -= add
				if amount <= 0 then return 0 end
			end
		end
	end
	for i = 1, n do
		local nm = storage:GetAttribute("Slot" .. i .. "_Name")
		if nm == nil or nm == "" then
			local add = math.min(amount, CFG.MAX_STACK)
			storage:SetAttribute("Slot" .. i .. "_Name", item)
			storage:SetAttribute("Slot" .. i .. "_Count", add)
			amount -= add
			if amount <= 0 then return 0 end
		end
	end
	return amount
end

-- Парт-«якорь» склада: ВИДИМОЕ здание (Storage), чтобы кнопка E была ПЕРЕД складом,
-- а не у Triger вдалеке. Данные/промпт держим на нём (помечаем атрибутом, без тега).
local function storageAnchor(storageModel)
	local b = findDeep(storageModel, CFG.STORAGE_BUILDING)
	if b and b:IsA("BasePart") then return b end
	if storageModel:IsA("BasePart") then return storageModel end
	return storageModel.PrimaryPart
		or findDeep(storageModel, CFG.STORAGE_TRIGGER)
		or storageModel:FindFirstChildWhichIsA("BasePart", true)
end

local function setupStorage(storageModel)
	local anchor = storageAnchor(storageModel)
	if not (anchor and anchor:IsA("BasePart")) then
		warn("[TreeFarm] склад: не нашёл парт-якорь (Triger) в " .. storageModel:GetFullName())
		return
	end

	-- Анти-«призрак»: при StreamingEnabled/LOD склад при подходе «доезжает» и мигает
	-- упрощённой моделью. Держим его всегда загруженным и без LOD-подмены.
	if storageModel:IsA("Model") then
		pcall(function() storageModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
		pcall(function() storageModel.LevelOfDetail = Enum.ModelLevelOfDetail.Disabled end)
	end

	anchor:SetAttribute("IsTreeFarmStorage", true)
	if anchor:GetAttribute("SlotCount") == nil then
		anchor:SetAttribute("SlotCount", CFG.STORAGE_SLOTS)
	end
	for i = 1, (anchor:GetAttribute("SlotCount") or CFG.STORAGE_SLOTS) do
		if anchor:GetAttribute("Slot" .. i .. "_Name") == nil then
			anchor:SetAttribute("Slot" .. i .. "_Name", "")
			anchor:SetAttribute("Slot" .. i .. "_Count", 0)
		end
	end

	if not anchor:FindFirstChildOfClass("ProximityPrompt") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Открыть"
		prompt.ObjectText = "Склад"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0.2
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Parent = anchor
		prompt.Triggered:Connect(function(player)
			OpenContainer:FireClient(player, anchor)
		end)
	end
end

-- Обработчик переноса предметов склад↔инвентарь (только для НАШИХ складов).
ContainerAction.OnServerEvent:Connect(function(player, action, container, slot, item, count, kind)
	if typeof(container) ~= "Instance" then return end
	if not container:GetAttribute("IsTreeFarmStorage") then return end

	if action == "take" then
		local i = slot
		local nm = container:GetAttribute("Slot" .. i .. "_Name")
		local ct = container:GetAttribute("Slot" .. i .. "_Count") or 0
		if typeof(nm) ~= "string" or nm == "" or ct <= 0 then return end
		local cap = (_G.GetInventoryCapacity and _G.GetInventoryCapacity(player, nm)) or ct
		local toTake = math.min(ct, cap)
		if toTake > 0 and _G.AddResourceToInventory then
			_G.AddResourceToInventory(player, nm, toTake, nil, true)
			local left = ct - toTake
			container:SetAttribute("Slot" .. i .. "_Count", left)
			if left <= 0 then container:SetAttribute("Slot" .. i .. "_Name", "") end
		end

	elseif action == "put" then
		if kind ~= nil and kind ~= "resource" then return end -- склад только под ресурсы
		local nm = item
		if typeof(nm) ~= "string" or nm == "" then return end
		local inv = (_G.GetInventory and _G.GetInventory(player)) or {}
		local have = inv[nm] or 0
		local want = math.min(count or 0, have)
		if want <= 0 then return end
		local i = slot
		if typeof(i) == "number" then
			local snm = container:GetAttribute("Slot" .. i .. "_Name")
			local sct = container:GetAttribute("Slot" .. i .. "_Count") or 0
			if snm == nil or snm == "" then
				local put = math.min(want, CFG.MAX_STACK)
				_G.RemoveResourceFromInventory(player, nm, put)
				container:SetAttribute("Slot" .. i .. "_Name", nm)
				container:SetAttribute("Slot" .. i .. "_Count", put)
			elseif snm == nm and sct < CFG.MAX_STACK then
				local put = math.min(want, CFG.MAX_STACK - sct)
				_G.RemoveResourceFromInventory(player, nm, put)
				container:SetAttribute("Slot" .. i .. "_Count", sct + put)
			end
		else
			-- авто-слот
			_G.RemoveResourceFromInventory(player, nm, want)
			local overflow = addToStorage(container, nm, want)
			if overflow > 0 and _G.AddResourceToInventory then
				_G.AddResourceToInventory(player, nm, overflow, nil, true)
			end
		end

	elseif action == "move" then
		local a, b = slot, item -- src, dst
		if typeof(a) ~= "number" or typeof(b) ~= "number" then return end
		local an = container:GetAttribute("Slot" .. a .. "_Name")
		local ac = container:GetAttribute("Slot" .. a .. "_Count") or 0
		local bn = container:GetAttribute("Slot" .. b .. "_Name")
		local bc = container:GetAttribute("Slot" .. b .. "_Count") or 0
		if bn == an and bn ~= nil and bn ~= "" then
			local move = math.min(ac, CFG.MAX_STACK - bc)
			container:SetAttribute("Slot" .. b .. "_Count", bc + move)
			container:SetAttribute("Slot" .. a .. "_Count", ac - move)
			if (ac - move) <= 0 then container:SetAttribute("Slot" .. a .. "_Name", "") end
		else
			container:SetAttribute("Slot" .. a .. "_Name", bn or "")
			container:SetAttribute("Slot" .. a .. "_Count", bc)
			container:SetAttribute("Slot" .. b .. "_Name", an or "")
			container:SetAttribute("Slot" .. b .. "_Count", ac)
		end
	end

	if _G.SendInventory then _G.SendInventory(player) end
end)

--====================================================
-- РАБОЧИЙ (Villager_Axe) — анимации, движение, FSM
--====================================================

-- Шаблон рабочего берём лениво и с защитой: Archivable=false у модели заставляет
-- Clone() ТИХО вернуть nil (классическая причина «рабочий не спавнится») — чиним и
-- говорим об этом. Если шаблон не взялся при старте — пробуем снова при спавне.
local workerTemplate = nil
local function getWorkerTemplate()
	if workerTemplate then return workerTemplate end
	local t = ServerStorage:FindFirstChild(CFG.WORKER_TEMPLATE, true)
		or ReplicatedStorage:FindFirstChild(CFG.WORKER_TEMPLATE, true)
		or workspace:FindFirstChild(CFG.WORKER_TEMPLATE, true)
	if not t then
		warn("[TreeFarm] шаблон рабочего '" .. CFG.WORKER_TEMPLATE .. "' не найден (ServerStorage/ReplicatedStorage/Workspace)")
		return nil
	end
	if not t.Archivable then
		t.Archivable = true
		warn("[TreeFarm] у шаблона '" .. CFG.WORKER_TEMPLATE .. "' был Archivable=false (Clone() возвращал nil) — включил")
	end
	workerTemplate = t:Clone()
	-- Если оригинал стоял в Workspace «для вида» — убираем, рабочие появятся при постройке.
	if t:IsDescendantOf(workspace) then
		t:Destroy()
	end
	if not workerTemplate then
		warn("[TreeFarm] Clone() шаблона рабочего не удался")
	end
	return workerTemplate
end
getWorkerTemplate()

-- Эффект щепок при ударе: Part c ParticleEmitter из ReplicatedStorage. Готовим шаблон
-- ОДИН раз: гасим эмиттеры (бьём одиночным burst'ом через :Emit) и берём число частиц.
-- Поиск рекурсивный — найдём, даже если парт лежит во вложенной папке.
local axeEffectTemplate, axeEffectEmit
do
	local name = CFG.AXE_EFFECT_NAME
	local src = ReplicatedStorage:FindFirstChild(name, true)
		or ServerStorage:FindFirstChild(name, true)
		or workspace:FindFirstChild(name, true)
	if src and src:IsA("BasePart") then
		axeEffectTemplate = src:Clone()
		axeEffectTemplate.Anchored = true
		axeEffectTemplate.CanCollide = false
		axeEffectTemplate.CanQuery = false
		axeEffectTemplate.CanTouch = false
		axeEffectTemplate.Massless = true
		axeEffectEmit = src:GetAttribute("EmitCount") or CFG.AXE_EFFECT_EMIT
		for _, pe in ipairs(axeEffectTemplate:GetDescendants()) do
			if pe:IsA("ParticleEmitter") then pe.Enabled = false end
		end
	end
	print("[TreeFarm] эффект '" .. name .. "': " ..
		(axeEffectTemplate and ("OK, частиц=" .. tostring(axeEffectEmit)) or "НЕ НАЙДЕН"))
end

-- Персональный эффект щепок рабочего. Клонируем шаблон В рабочего ОДИН раз — он успевает
-- реплицироваться на клиентов, поэтому :Emit() надёжно виден (нет гонки «создал-и-сразу
-- -Emit» и нет мусора клонов на каждый удар). Возвращаем burst(): ставим эффект в точку
-- контакта (перед рабочим, на высоте удара) и выбрасываем частицы.
local function createAxeEffect(worker, hrp, env)
	if not axeEffectTemplate then return nil end
	local fx = axeEffectTemplate:Clone()
	local emitters = {}
	for _, pe in ipairs(fx:GetDescendants()) do
		if pe:IsA("ParticleEmitter") then table.insert(emitters, pe) end
	end
	-- Точка контакта — РЕЙКАСТОМ от рабочего к стволу: эффект ложится на реальную
	-- поверхность пальмы (наклонный ствол по bounding-box давал точку в воздухе или
	-- в самом НПС). Запасной путь — по радиусу ствола, если луч вдруг не попал.
	local rayParams
	if env.palmInst then
		rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances = { env.palmInst }
	end
	local function impactPos()
		local hp = hrp.Position
		local c = env.treeCenter
		local origin = Vector3.new(hp.X, hp.Y + CFG.AXE_EFFECT_HEIGHT, hp.Z)
		if rayParams then
			local toTree = Vector3.new(c.X - origin.X, 0, c.Z - origin.Z)
			if toTree.Magnitude > 0.001 then
				local hit = workspace:Raycast(origin, toTree.Unit * (toTree.Magnitude + 4), rayParams)
				if hit then
					return hit.Position - toTree.Unit * 0.1 -- чуть наружу от поверхности
				end
			end
		end
		local toWorker = Vector3.new(hp.X - c.X, 0, hp.Z - c.Z)
		local dir = (toWorker.Magnitude > 0.001) and toWorker.Unit or hrp.CFrame.LookVector
		local surfR = math.max(0, env.treeRadius - CFG.CHOP_RADIUS_PAD) -- радиус самого ствола
		return Vector3.new(c.X, origin.Y, c.Z) + dir * surfR
	end
	-- .Position (а не CFrame) — сохраняем ориентацию эмиттера как в ReplicatedStorage.
	fx.Position = impactPos()
	fx.Parent = worker
	return function()
		if not (fx.Parent and hrp.Parent) then return end
		fx.Position = impactPos()
		for _, pe in ipairs(emitters) do
			pe:Emit(axeEffectEmit)
		end
	end
end

local function loadAnims(worker, humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local folder = worker:FindFirstChild("Animation") or worker:FindFirstChild("Animations")
	local tracks = {}
	if folder then
		for _, a in ipairs(folder:GetDescendants()) do
			if a:IsA("Animation") then
				local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
				if ok then tracks[a.Name] = tr end
			end
		end
	end
	local state = { tracks = tracks, current = nil }
	function state.play(name, loop)
		local t = tracks[name]
		if state.current == t then return end
		if state.current then state.current:Stop(0.15) end
		state.current = t
		if t then
			t.Looped = (loop ~= false)
			t:Play(0.15)
		end
	end
	-- Проиграть анимацию ОДИН раз и подождать её длину (для чередования взмахов).
	function state.playOnce(name)
		local t = tracks[name]
		if not t then task.wait(0.5); return end
		if state.current then state.current:Stop(0.05); state.current = nil end
		t.Looped = false
		t:Play(0.05)
		local len = t.Length
		if len <= 0 then len = 0.6 end -- ещё не загрузилась — запасная длина
		task.wait(len)
	end
	return state
end

-- Звуки рабочего (tree_hit_1 / tree_hit_2 / putting). Переселяем их на корпус (HRP),
-- чтобы звук был 3D — от самого рабочего, а не глобально.
local function loadSounds(worker, hrp)
	local sounds = {}
	for _, name in ipairs({ "tree_hit_1", "tree_hit_2", "putting" }) do
		local s = worker:FindFirstChild(name, true)
		if s and s:IsA("Sound") then
			s.Parent = hrp
			sounds[name] = s
		end
	end
	return sounds
end

local function playSound(sounds, name)
	local s = sounds[name]
	if s then
		s.TimePosition = 0
		s:Play()
	end
end

-- Билборд статуса над головой рабочего (показываем во время отдыха). TextLabel с
-- AutoLocalize=true — Roblox сам переводит текст под локаль игрока (как обычный
-- TextLabel). Создаём на сервере, реплицируется и локализуется у каждого клиента.
local function createStatusGui(worker)
	local head = worker:FindFirstChild("Head") or worker:FindFirstChild("HumanoidRootPart")
	if not head then return nil end

	local gui = Instance.new("BillboardGui")
	gui.Name = "WorkerStatus"
	gui.Size = UDim2.fromOffset(130, 54)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.Enabled = false
	gui.Adornee = head
	gui.Parent = head

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, 0, 0.55, 0)
	status.Font = Enum.Font.GothamBold
	status.TextScaled = true
	status.TextColor3 = Color3.fromRGB(255, 255, 255)
	status.TextStrokeTransparency = 0.4
	status.AutoLocalize = true
	status.Text = "\u{1F634} Отдыхает"
	status.Parent = gui

	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.BackgroundTransparency = 1
	timer.Position = UDim2.new(0, 0, 0.55, 0)
	timer.Size = UDim2.new(1, 0, 0.45, 0)
	timer.Font = Enum.Font.GothamMedium
	timer.TextScaled = true
	timer.TextColor3 = Color3.fromRGB(220, 230, 245)
	timer.TextStrokeTransparency = 0.5
	timer.AutoLocalize = true
	timer.Text = ""
	timer.Parent = gui

	return { gui = gui, status = status, timer = timer }
end

-- Отдых с показом статуса и обратным отсчётом (секунды). Прерывается, если рабочего
-- удалили / он умер.
local function restWithStatus(statusGui, worker, humanoid, duration)
	if statusGui then
		statusGui.status.Text = "\u{1F634} Отдыхает"
		statusGui.gui.Enabled = true
	end
	local left = math.ceil(duration)
	while left > 0 and worker.Parent and humanoid.Health > 0 do
		if statusGui then
			statusGui.timer.Text = string.format("%d сек", left)
		end
		task.wait(1)
		left -= 1
	end
	if statusGui then statusGui.gui.Enabled = false end
end

-- Дойти до точки. anim — какую анимацию ходьбы играть ("Walk"/"Run"). reach — на
-- сколько близко считать «дошёл» (для Trigger меньше, чтобы встал на него).
local function walkTo(worker, humanoid, hrp, anims, pos, speed, anim, reach)
	reach = reach or CFG.REACH
	humanoid.WalkSpeed = speed
	anims.play(anim or "Walk", true)
	humanoid:MoveTo(pos)
	local start = os.clock()
	local lastPos, lastMove = hrp.Position, os.clock()
	while worker.Parent and humanoid.Health > 0 do
		if flatDist(hrp.Position, pos) <= reach then
			return true
		end
		if (hrp.Position - lastPos).Magnitude > 0.4 then
			lastPos, lastMove = hrp.Position, os.clock()
		elseif os.clock() - lastMove > 1.5 then
			return true -- ~1.5с не двигаемся → упёрлись в цель (дерево/склад)
		end
		if os.clock() - start > 25 then
			return false
		end
		humanoid:MoveTo(pos)
		task.wait(0.2)
	end
	return false
end

-- Занятость мест отдыха (общая по серверу): [sitPart] = true.
local sitOccupied = {}
local function claimSit(sits)
	local free = {}
	for _, s in ipairs(sits) do
		if not sitOccupied[s] then table.insert(free, s) end
	end
	if #free == 0 then return nil end
	local s = free[math.random(1, #free)]
	sitOccupied[s] = true
	return s
end

--====================================================
-- БОРД: состояние, числа, постройка, апгрейды
--====================================================

local boards = {}  -- [boardModel] = { workers = {}, env = {...} }

local function chopTime(board)
	local lv = board:GetAttribute("SpeedLevel") or 1
	return math.max(CFG.CHOP_MIN, CFG.CHOP_BASE - (lv - 1) * CFG.CHOP_STEP)
end
local function restTime(board)
	local lv = board:GetAttribute("RestLevel") or 1
	return math.max(CFG.REST_MIN, CFG.REST_BASE - (lv - 1) * CFG.REST_STEP)
end
-- Бежит ли рабочий (Speed прокачан выше RUN_SPEED_LEVEL).
local function isRunning(board)
	return (board:GetAttribute("SpeedLevel") or 1) > CFG.RUN_SPEED_LEVEL
end
-- Скорость передвижения (studs/сек): ходьба или бег. От уровня Speed сама ходьба НЕ
-- ускоряется — это только сокращает время рубки.
local function walkSpeed(board)
	return isRunning(board) and CFG.WORKER_RUN_SPEED or CFG.WORKER_WALK_SPEED
end
local function workerCount(board)
	return board:GetAttribute("WorkersLevel") or 1
end

-- Текст «текущее → следующее» для категории.
local function statusText(board, cat)
	if cat == "Speed" then
		local lv = board:GetAttribute("SpeedLevel") or 1
		local cur = math.max(CFG.CHOP_MIN, CFG.CHOP_BASE - (lv - 1) * CFG.CHOP_STEP)
		local nxt = math.max(CFG.CHOP_MIN, CFG.CHOP_BASE - lv * CFG.CHOP_STEP)
		return string.format("%ds \u{2192} %ds", cur, nxt)
	elseif cat == "Rest" then
		local lv = board:GetAttribute("RestLevel") or 1
		local cur = math.max(CFG.REST_MIN, CFG.REST_BASE - (lv - 1) * CFG.REST_STEP)
		local nxt = math.max(CFG.REST_MIN, CFG.REST_BASE - lv * CFG.REST_STEP)
		return string.format("%gs \u{2192} %gs", cur, nxt)
	else -- Workers
		local lv = board:GetAttribute("WorkersLevel") or 1
		return string.format("%d \u{2192} %d", lv, math.min(CFG.WORKERS_MAX, lv + 1))
	end
end

-- Показать/скрыть GUI: .Enabled у SurfaceGui/BillboardGui/ScreenGui, иначе .Visible.
local function setShown(gui, shown)
	if not gui then return end
	if gui:IsA("LayerCollector") then
		gui.Enabled = shown
	elseif gui:IsA("GuiObject") then
		gui.Visible = shown
	end
end

-- На MAX кнопку полностью прячем (её вообще не должно быть видно).
local function setFaded(gui, faded)
	if gui and gui:IsA("GuiObject") then
		gui.Visible = not faded
	end
end

-- Перерисовать GUI борда по состоянию (сервер авторитетен).
local function renderBoard(board)
	local part = findDeep(board, CFG.BOARD_PART) or board
	local unwork = findDeep(part, CFG.UNWORK_GUI)
	local work   = findDeep(part, CFG.WORK_GUI)
	local built  = board:GetAttribute("Built") == true
	setShown(unwork, not built)
	setShown(work, built)

	if work then
		local frame = findDeep(work, CFG.WORK_FRAME) or work
		for cat, info in pairs(CATS) do
			local catFrame = findDeep(frame, info.frame)
			if catFrame then
				local lv = board:GetAttribute(info.attr) or 1
				local maxed = lv >= info.max
				local levelLbl  = findDeep(catFrame, "Level")
				local priceLbl  = findDeep(catFrame, "Price")
				local statusLbl = findDeep(catFrame, "Current_Status")
				if levelLbl and levelLbl:IsA("TextLabel") then
					levelLbl.Text = string.format("Уровень: %d/%d", lv, info.max)
				end
				if statusLbl and statusLbl:IsA("TextLabel") then
					statusLbl.Text = statusText(board, cat)
				end
				if priceLbl and priceLbl:IsA("TextLabel") then
					local c = CFG.COST[cat]
					priceLbl.Text = maxed and "MAX" or string.format("Цена: %d %s", c.amount, c.item)
				end
				-- На MAX — кнопки прозрачные/некликабельные.
				setFaded(findDeep(catFrame, "Buy"), maxed)
				setFaded(findDeep(catFrame, "Max"), maxed)
			end
		end
	end
end

-- Списать стоимость апгрейда.
local function payCost(player, cat)
	local c = CFG.COST[cat]
	if not c then return false end
	if c.currency == "villagers" then
		return _G.SpendVillagers and _G.SpendVillagers(player, c.amount) or false
	else -- inventory
		local inv = (_G.GetInventory and _G.GetInventory(player)) or {}
		if (inv[c.item] or 0) < c.amount then return false end
		if _G.RemoveResourceFromInventory then
			_G.RemoveResourceFromInventory(player, c.item, c.amount)
			if _G.SendInventory then _G.SendInventory(player) end
			return true
		end
		return false
	end
end

-- Поднять риг к движению: снять якоря (иначе MoveTo НЕ двигает — рабочий стоит),
-- сбросить PlatformStand/Sit, включить состояния ходьбы.
local function prepRig(worker, humanoid)
	for _, d in ipairs(worker:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	humanoid.PlatformStand = false
	humanoid.Sit = false
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
	end)
end

-- Развернуть корпус лицом к точке (по горизонтали). Рабочий стоит на месте, поэтому
-- сначала гасим цель движения (MoveTo в себя), чтобы AutoRotate не крутил наружу.
local function faceFlat(humanoid, hrp, target)
	humanoid:MoveTo(hrp.Position)
	local flat = Vector3.new(target.X, hrp.Position.Y, target.Z)
	if (flat - hrp.Position).Magnitude > 0.1 then
		hrp.CFrame = CFrame.lookAt(hrp.Position, flat)
	end
end

-- Рубка: лицом к стволу, чередуем взмахи Axe_1, Axe_1, Axe_2 + звук удара на каждый
-- взмах (Axe_1 → tree_hit_1, Axe_2 → tree_hit_2).
local function chopFor(anims, sounds, worker, humanoid, hrp, center, duration, shake, axeBurst)
	humanoid.WalkSpeed = 0
	local seq = {
		{ anim = "Axe_1", sfx = "tree_hit_1" },
		{ anim = "Axe_1", sfx = "tree_hit_1" },
		{ anim = "Axe_2", sfx = "tree_hit_2" },
	}
	local start = os.clock()
	local i = 1
	while worker.Parent and humanoid.Health > 0 and os.clock() - start < duration do
		faceFlat(humanoid, hrp, center) -- держим лицом к стволу
		-- Удар приходится не в начале взмаха, а ~0.11с спустя — в момент контакта
		-- топора. Тогда же звук удара и одиночная тряска дерева (всё синхронно).
		local sfx = seq[i].sfx
		task.delay(0.11, function()
			if worker.Parent and humanoid.Health > 0 then
				playSound(sounds, sfx)
				if shake then shake() end
				if axeBurst then axeBurst() end -- щепки в точке контакта топора со стволом
			end
		end)
		anims.playOnce(seq[i].anim)
		i = i % #seq + 1
	end
end

-- Точка рубки для конкретного рабочего — со СВОЕЙ стороны дерева (по углу slot).
local function chopPosForSlot(env, slot)
	local angle = (slot - 1) * (2 * math.pi / math.max(1, CFG.WORKERS_MAX))
	return env.treeCenter + Vector3.new(math.cos(angle), 0, math.sin(angle)) * env.treeRadius
end

-- FSM одного рабочего. slot (1..N) задаёт сторону дерева, с которой он рубит.
local function runWorker(board, env, worker, slot)
	local humanoid = worker:FindFirstChildOfClass("Humanoid")
	local hrp = worker:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then
		warn("[TreeFarm] у рабочего нет " .. (humanoid and "HumanoidRootPart" or "Humanoid") .. " — удаляю")
		worker:Destroy()
		return
	end
	local anims = loadAnims(worker, humanoid)
	local sounds = loadSounds(worker, hrp)

	prepRig(worker, humanoid)
	worker.Parent = env.folder
	worker:PivotTo(CFrame.new(env.spawnPos + Vector3.new(0, 3, 0)))
	-- Управление физикой — на сервере (иначе клиент-владелец дерётся с MoveTo).
	pcall(function() hrp:SetNetworkOwner(nil) end)
	local statusGui = createStatusGui(worker)
	local axeBurst = createAxeEffect(worker, hrp, env)

	task.spawn(function()
		while worker.Parent and humanoid.Health > 0 and board:GetAttribute("Built") do
			-- Анимация ходьбы: бег, если скорость прокачана выше RUN_SPEED_LEVEL.
			local moveAnim = isRunning(board) and "Run" or "Walk"

			-- 1) к СВОЕЙ стороне дерева, лицом к стволу, рубим (звук удара на взмах)
			walkTo(worker, humanoid, hrp, anims, chopPosForSlot(env, slot), walkSpeed(board), moveAnim)
			chopFor(anims, sounds, worker, humanoid, hrp, env.treeCenter, chopTime(board), env.treeShake, axeBurst)

			-- 2) встаём НА парт Trigger (малый reach), лицом к складу, кладём бревно
			walkTo(worker, humanoid, hrp, anims, env.depositpos, walkSpeed(board), moveAnim, CFG.DEPOSIT_REACH)
			humanoid.WalkSpeed = 0
			faceFlat(humanoid, hrp, env.facepos)
			playSound(sounds, "putting")
			anims.playOnce("Drop")
			if env.storage and env.storage:IsDescendantOf(workspace) then
				addToStorage(env.storage, CFG.DEPOSIT_RESOURCE, 1)
				-- шанс добыть ещё и кокос
				if math.random() < CFG.COCONUT_CHANCE then
					addToStorage(env.storage, CFG.COCONUT_RESOURCE, 1)
				end
			end

			-- 3) на свободное место Sit (внутри Palm) — доходим, садимся, отдыхаем
			local sit = claimSit(env.sits)
			if sit then
				walkTo(worker, humanoid, hrp, anims, sit.Position, walkSpeed(board), moveAnim)
				humanoid.WalkSpeed = 0
				anims.play("Sitting", true)
				restWithStatus(statusGui, worker, humanoid, restTime(board))
				sitOccupied[sit] = nil
			else
				anims.play("Idle", true)
				restWithStatus(statusGui, worker, humanoid, restTime(board))
			end
		end
		if worker.Parent then worker:Destroy() end
	end)
end

local function spawnWorker(board, env)
	local tpl = getWorkerTemplate()
	if not tpl then
		warn("[TreeFarm] спавн рабочего ОТМЕНЁН: нет шаблона '" .. CFG.WORKER_TEMPLATE .. "'")
		return
	end
	local w = tpl:Clone()
	if not w then
		warn("[TreeFarm] спавн рабочего ОТМЕНЁН: Clone() вернул nil (проверь Archivable у '" .. CFG.WORKER_TEMPLATE .. "')")
		return
	end
	w.Name = "Villager"
	env.spawnCount = (env.spawnCount or 0) + 1
	local slot = (env.spawnCount - 1) % math.max(1, CFG.WORKERS_MAX) + 1
	table.insert(env.workers, w)
	print(string.format("[TreeFarm] рабочий заспавнен (слот %d, всего %d)", slot, #env.workers))
	runWorker(board, env, w, slot)
end

-- Привести число рабочих к WorkersLevel.
local function syncWorkers(board, env)
	-- убрать «мертвых»
	for i = #env.workers, 1, -1 do
		if not env.workers[i].Parent then table.remove(env.workers, i) end
	end
	local need = workerCount(board)
	while #env.workers < need do
		spawnWorker(board, env)
	end
end

-- Ближайший к fromPos объект (Model/BasePart) с именем name во всём Workspace.
local function nearestNamed(name, fromPos)
	local best, bestD = nil, math.huge
	for _, m in ipairs(workspace:GetDescendants()) do
		if (m:IsA("Model") or m:IsA("BasePart")) and m.Name == name then
			local p = partPosition(m)
			if p then
				local d = (p - fromPos).Magnitude
				if d < bestD then best, bestD = m, d end
			end
		end
	end
	return best
end

-- Горизонтальный «радиус» объекта (по X/Z), чтобы стоять у ствола, а не в нём.
local function objectRadius(inst)
	if inst and inst:IsA("BasePart") then
		return math.max(inst.Size.X, inst.Size.Z) * 0.5
	elseif inst and inst:IsA("Model") then
		local ok, size = pcall(function() return inst:GetExtentsSize() end)
		if ok then return math.max(size.X, size.Z) * 0.5 end
	end
	return 1.5
end

-- Контроллер тряски дерева: при ударе вся модель дерева КРОМЕ партов Sit слегка
-- качается (одиночно) вокруг основания ствола и точно возвращается на место.
-- Возвращает функцию shake() — её зовём В МОМЕНТ удара (через ~0.11с после начала
-- взмаха), а не в начале. Парты дерева анкорятся (статичный декор), поэтому двигаем
-- их CFrame; busy-флаг не даёт нескольким рабочим перетягивать тряску.
local function makeTreeShaker(tree)
	if not tree then return nil end
	local parts = {}
	local list = tree:IsA("Model") and tree:GetDescendants() or { tree }
	for _, d in ipairs(list) do
		if d:IsA("BasePart") and d.Name ~= CFG.SIT_NAME then
			table.insert(parts, { part = d, cf = d.CFrame })
		end
	end
	if #parts == 0 then return nil end

	-- Точка опоры — низ модели (основание ствола): крона качается сильнее низа.
	local pivotPos
	if tree:IsA("Model") then
		local ok, bbCF, bbSize = pcall(function()
			local c, s = tree:GetBoundingBox()
			return c, s
		end)
		if ok and bbCF and bbSize then
			pivotPos = bbCF.Position - Vector3.new(0, bbSize.Y * 0.5, 0)
		end
	end
	pivotPos = pivotPos or parts[1].part.Position
	local pivotCF  = CFrame.new(pivotPos)
	local invPivot = pivotCF:Inverse()

	local busy = false
	return function()
		if busy then return end
		busy = true
		task.spawn(function()
			-- наклон в случайную горизонтальную сторону на маленький угол, туда-обратно
			local theta = math.random() * math.pi * 2
			local axis  = Vector3.new(math.cos(theta), 0, math.sin(theta))
			local DUR, PEAK = 0.22, math.rad(2)
			local t = 0
			while t < DUR do
				t += RunService.Heartbeat:Wait()
				local f = math.min(t / DUR, 1)
				local m = pivotCF * CFrame.fromAxisAngle(axis, PEAK * math.sin(f * math.pi)) * invPivot
				for _, e in ipairs(parts) do
					if e.part.Parent then e.part.CFrame = m * e.cf end
				end
			end
			for _, e in ipairs(parts) do
				if e.part.Parent then e.part.CFrame = e.cf end
			end
			busy = false
		end)
	end
end

local function buildEnv(board)
	local part = findDeep(board, CFG.BOARD_PART) or board
	local boardPos = partPosition(part) or partPosition(board) or Vector3.zero

	-- точка спавна, дерево, склад — ближайшие к ЭТОМУ борду (на случай нескольких).
	local spawnPart = findDeep(board, CFG.SPAWN_NAME) or nearestNamed(CFG.SPAWN_NAME, boardPos)
	local tree      = nearestNamed(CFG.TREE_NAME, boardPos)
	-- Ствол Palm: и точка рубки, и контейнер мест Sit. Берём ближайший к борду
	-- (если внутри дерева — внутри дерева; иначе отдельную модель Palm).
	local palm      = (tree and findDeep(tree, CFG.PALM_NAME)) or nearestNamed(CFG.PALM_NAME, boardPos) or tree
	local storageModel = nearestNamed(CFG.STORAGE_NAME, boardPos)
	local storage   = storageModel and storageAnchor(storageModel)  -- здание (контейнер + промпт)
	local trigerPart = storageModel and findDeep(storageModel, CFG.STORAGE_TRIGGER) -- куда ВСТАЁТ рабочий

	-- Места отдыха Sit — все парты с именем Sit внутри модели ДЕРЕВА (рядом с Palm).
	local sits = {}
	local sitRoot = tree or palm
	if sitRoot then
		for _, d in ipairs(sitRoot:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == CFG.SIT_NAME then
				table.insert(sits, d)
			end
		end
	end

	local folder = workspace:FindFirstChild(CFG.WORKER_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CFG.WORKER_FOLDER
		folder.Parent = workspace
	end

	local treeCenter = partPosition(palm) or partPosition(tree) or boardPos
	local treeRadius = objectRadius(palm) + CFG.CHOP_RADIUS_PAD

	warn(string.format(
		"[TreeFarm] окружение: spawn=%s tree=%s palm=%s storage=%s sits=%d r=%.1f",
		spawnPart and "OK" or "НЕТ", tree and tree.Name or "НЕТ",
		palm and "OK" or "НЕТ('" .. CFG.PALM_NAME .. "')",
		storage and "OK" or "НЕТ", #sits, treeRadius
	))

	return {
		folder = folder,
		spawnPos = partPosition(spawnPart) or boardPos + Vector3.new(0, 0, 6),
		treeCenter = treeCenter,
		treeRadius = treeRadius,
		treeShake = makeTreeShaker(tree), -- тряска дерева при ударе (кроме партов Sit)
		palmInst = palm,                  -- геометрия ствола (рейкаст точки удара)
		depositpos = partPosition(trigerPart) or partPosition(storage) or boardPos, -- встаём на Trigger
		facepos = partPosition(storage) or partPosition(trigerPart) or boardPos,     -- лицом к зданию склада
		storage = storage,
		sits = sits,
		workers = {},
		spawnCount = 0,
	}
end

--====================================================
-- ОБРАБОТКА ДЕЙСТВИЙ БОРДА (клиент → сервер)
--====================================================

TreeFarmAction.OnServerEvent:Connect(function(player, action, board, cat, buyMax)
	if typeof(board) ~= "Instance" or not boards[board] then
		warn(string.format("[TreeFarm] действие '%s' от %s — борд не зарегистрирован (%s)",
			tostring(action), player.Name, tostring(board)))
		return
	end
	local data = boards[board]

	if action == "build" then
		print(string.format("[TreeFarm] build от %s | жителей=%s | уже построено=%s",
			player.Name, tostring(_G.GetVillagers and _G.GetVillagers(player)), tostring(board:GetAttribute("Built"))))
		if board:GetAttribute("Built") then return end
		if not (_G.SpendVillagers and _G.SpendVillagers(player, CFG.BUILD_COST_VILLAGERS)) then
			warn("[TreeFarm] постройка: не хватило жителей у " .. player.Name)
			return -- не хватило жителей
		end
		board:SetAttribute("Built", true)
		board:SetAttribute("SpeedLevel", 1)
		board:SetAttribute("WorkersLevel", 1)
		board:SetAttribute("RestLevel", 1)
		data.env = buildEnv(board)
		syncWorkers(board, data.env)
		renderBoard(board)

	elseif action == "buy" then
		if not board:GetAttribute("Built") then return end
		local info = CATS[cat]
		if not info then return end
		local lv = board:GetAttribute(info.attr) or 1
		repeat
			if lv >= info.max then break end
			if not payCost(player, cat) then break end
			lv += 1
			board:SetAttribute(info.attr, lv)
			if cat == "Workers" and data.env then
				syncWorkers(board, data.env)
			end
		until not buyMax
		renderBoard(board)
	end
end)

--====================================================
-- ИНИЦИАЛИЗАЦИЯ
--====================================================

local function setupBoard(board)
	if boards[board] then return end
	boards[board] = { workers = {}, env = nil }
	-- Полная репликация без стриминга/LOD: клиент прячет борд до катсцены «зачистки»
	-- и масштабирует целиком — частично подгруженная модель ломала бы скрытие.
	pcall(function() board.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
	pcall(function() board.LevelOfDetail = Enum.ModelLevelOfDetail.Disabled end)
	if board:GetAttribute("Built") == nil then
		board:SetAttribute("Built", false)
	end
	board:SetAttribute("SpeedLevel", board:GetAttribute("SpeedLevel") or 1)
	board:SetAttribute("WorkersLevel", board:GetAttribute("WorkersLevel") or 1)
	board:SetAttribute("RestLevel", board:GetAttribute("RestLevel") or 1)
	-- Тег нужен клиенту, чтобы надёжно (без гонки загрузки) найти борд и навесить кнопки.
	CollectionService:AddTag(board, "TreeFarmBoard")
	renderBoard(board)
	-- если уже было построено (после рестарта сервера) — поднять рабочих
	if board:GetAttribute("Built") then
		boards[board].env = buildEnv(board)
		syncWorkers(board, boards[board].env)
	end
end

local foundBoards, foundStorage = 0, 0
for _, m in ipairs(workspace:GetDescendants()) do
	if m:IsA("Model") and m.Name == CFG.BOARD_NAME then
		setupBoard(m); foundBoards += 1
	elseif m:IsA("Model") and m.Name == CFG.STORAGE_NAME then
		setupStorage(m); foundStorage += 1
	end
end
workspace.DescendantAdded:Connect(function(m)
	if m:IsA("Model") and m.Name == CFG.BOARD_NAME then
		task.wait(0.1); setupBoard(m)
	elseif m:IsA("Model") and m.Name == CFG.STORAGE_NAME then
		task.wait(0.1); setupStorage(m)
	end
end)

print(string.format(
	"[TreeFarm] Загружено. Бордов=%d, складов=%d, шаблон рабочего=%s",
	foundBoards, foundStorage, workerTemplate and "OK" or "НЕ НАЙДЕН ('" .. CFG.WORKER_TEMPLATE .. "')"
))
