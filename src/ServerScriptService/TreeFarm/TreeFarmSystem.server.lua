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
	TREE_NAME    = "palm_solo",  -- модель дерева для рубки
	SIT_NAME     = "Sit",        -- парты-места отдыха (внутри дерева), берём все с таким именем

	-- Склад.
	STORAGE_NAME    = "Storage_Palm",
	STORAGE_TRIGGER = "Triger",   -- парт, к которому рабочий несёт бревно
	STORAGE_SLOTS   = 12,
	STORAGE_TAG     = "TreeFarmStorage",

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
	WALK_BASE = 10, WALK_STEP = 0.6, WALK_MAX = 22, -- скорость ходьбы растёт от Speed-апгрейда
	DROP_TIME = 1.2,   -- длительность анимации выкладки
	REACH = 4.5,       -- считаем «дошёл», если ближе этого (по горизонтали)

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

local function setupStorage(storage)
	storage:SetAttribute("SlotCount", CFG.STORAGE_SLOTS)
	for i = 1, CFG.STORAGE_SLOTS do
		if storage:GetAttribute("Slot" .. i .. "_Name") == nil then
			storage:SetAttribute("Slot" .. i .. "_Name", "")
			storage:SetAttribute("Slot" .. i .. "_Count", 0)
		end
	end
	CollectionService:AddTag(storage, CFG.STORAGE_TAG)

	-- ProximityPrompt → открыть как сундук.
	local part = storage.PrimaryPart
		or findDeep(storage, CFG.STORAGE_TRIGGER)
		or storage:FindFirstChildWhichIsA("BasePart", true)
	if part and part:IsA("BasePart") and not part:FindFirstChildOfClass("ProximityPrompt") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Открыть"
		prompt.ObjectText = "Склад"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0.2
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
		prompt.Triggered:Connect(function(player)
			OpenContainer:FireClient(player, storage)
		end)
	end
end

-- Обработчик переноса предметов склад↔инвентарь (только для НАШИХ складов).
ContainerAction.OnServerEvent:Connect(function(player, action, container, slot, item, count, kind)
	if typeof(container) ~= "Instance" or not container:IsDescendantOf(workspace) then return end
	if not CollectionService:HasTag(container, CFG.STORAGE_TAG) then return end

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

local workerTemplate = nil
do
	local t = ServerStorage:FindFirstChild(CFG.WORKER_TEMPLATE, true)
		or ReplicatedStorage:FindFirstChild(CFG.WORKER_TEMPLATE, true)
		or workspace:FindFirstChild(CFG.WORKER_TEMPLATE, true)
	if t then
		workerTemplate = t:Clone()
		-- Если оригинал стоял в Workspace «для вида» — убираем, рабочие появятся при постройке.
		if t:IsDescendantOf(workspace) then
			t:Destroy()
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
	return state
end

-- Дойти до точки (простой MoveTo, без пасфайндинга — для v1). Возвращает true, если дошёл.
local function walkTo(worker, humanoid, hrp, anims, pos, speed)
	humanoid.WalkSpeed = speed
	anims.play("Walk", true)
	local start = os.clock()
	while worker.Parent and humanoid.Health > 0 do
		if flatDist(hrp.Position, pos) <= CFG.REACH then
			return true
		end
		if os.clock() - start > 25 then
			return false -- застрял — выходим, чтобы не зависнуть
		end
		humanoid:MoveTo(pos)
		humanoid.MoveToFinished:Wait()
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
local function walkSpeed(board)
	local lv = board:GetAttribute("SpeedLevel") or 1
	return math.min(CFG.WALK_MAX, CFG.WALK_BASE + (lv - 1) * CFG.WALK_STEP)
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
					local maxed = lv >= info.max
					priceLbl.Text = maxed and "MAX" or string.format("Цена: %d %s", c.amount, c.item)
				end
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

-- FSM одного рабочего.
local function runWorker(board, env, worker)
	local humanoid = worker:FindFirstChildOfClass("Humanoid")
	local hrp = worker:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then worker:Destroy() return end
	local anims = loadAnims(worker, humanoid)

	hrp.CFrame = CFrame.new(env.spawnPos + Vector3.new(0, 3, 0))
	worker.Parent = env.folder

	task.spawn(function()
		while worker.Parent and humanoid.Health > 0 and board:GetAttribute("Built") do
			-- 1) к дереву и рубим
			walkTo(worker, humanoid, hrp, anims, env.choppos, walkSpeed(board))
			anims.play("Axe_1", true)
			task.wait(chopTime(board))
			-- +1 бревно несём (счётчик не нужен — кладём 1 за цикл)

			-- 2) к складу, выкладываем
			walkTo(worker, humanoid, hrp, anims, env.storagepos, walkSpeed(board))
			anims.play("Drop", false)
			task.wait(CFG.DROP_TIME)
			if env.storage then
				addToStorage(env.storage, CFG.DEPOSIT_RESOURCE, 1)
			end

			-- 3) на отдых (случайное свободное место)
			local sit = claimSit(env.sits)
			if sit then
				walkTo(worker, humanoid, hrp, anims, sit.Position, walkSpeed(board))
				humanoid.WalkSpeed = 0
				anims.play("Sitting", true)
				task.wait(restTime(board))
				sitOccupied[sit] = nil
			else
				anims.play("Idle", true)
				task.wait(restTime(board))
			end
		end
		if worker.Parent then worker:Destroy() end
	end)
end

local function spawnWorker(board, env)
	if not workerTemplate then return end
	local w = workerTemplate:Clone()
	w.Name = "Villager"
	table.insert(env.workers, w)
	runWorker(board, env, w)
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

local function buildEnv(board)
	local part = findDeep(board, CFG.BOARD_PART) or board
	local spawnPart = findDeep(board, CFG.SPAWN_NAME) or findDeep(workspace, CFG.SPAWN_NAME)
	local tree = findDeep(workspace, CFG.TREE_NAME)
	local storage = findDeep(workspace, CFG.STORAGE_NAME)
	local trigger = storage and (findDeep(storage, CFG.STORAGE_TRIGGER) or storage)

	local sits = {}
	if tree then
		for _, d in ipairs(tree:GetDescendants()) do
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

	return {
		folder = folder,
		spawnPos = partPosition(spawnPart) or partPosition(part) or Vector3.new(0, 5, 0),
		choppos = partPosition(tree) or Vector3.new(0, 5, 0),
		storagepos = partPosition(trigger) or Vector3.new(0, 5, 0),
		storage = storage,
		sits = sits,
		workers = {},
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
