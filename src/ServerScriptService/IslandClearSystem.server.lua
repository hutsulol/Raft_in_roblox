-- IslandClearSystem.server.lua
-- Триггер катсцены «Остров зачищен»: следит за врагами в папке Enemies каждого
-- острова (например Island_1) и, когда ВСЕ они мертвы, шлёт клиентам RemoteEvent
-- IslandClearedEffect — тот запускает баннер + катсцену, а катсцена выращивает
-- постройки (Tree_Farm, Storage_Palm) и выводит освобождённых жителей.
--
-- Заодно чинит HP пиратов, чтобы зачистка вообще была возможна:
--   • снимаем ForceField (через него Humanoid:TakeDamage не проходит — пират
--     казался бессмертным);
--   • включаем скрипт Health, если он был Disabled (регенерация HP);
--   • выключаем скрипт Respawn — он клонировал пирата обратно через 20 сек после
--     смерти, поэтому остров не мог «зачиститься», а HP казалось «не работает»
--     (убил — а он вернулся). Для разовой зачистки смерть должна быть постоянной.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local ENEMIES_FOLDER = "Enemies"

-- RemoteEvent, который слушает IslandClearedEffect.client.lua.
local effectRemote = ReplicatedStorage:FindFirstChild("IslandClearedEffect")
if not effectRemote then
	effectRemote = Instance.new("RemoteEvent")
	effectRemote.Name = "IslandClearedEffect"
	effectRemote.Parent = ReplicatedStorage
end

local islands  = {}  -- [islandModel] = { aliveSet, registeredAny, armed, cleared, model }
local setupDone = setmetatable({}, { __mode = "k" })

--====================================================
-- Починка HP конкретного пирата
--====================================================
local function normalizeEnemy(model, humanoid)
	-- 1) ForceField рвёт TakeDamage — убираем любые.
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("ForceField") then
			obj:Destroy()
		end
	end
	-- 2) Скрипты HP/респавна внутри модели.
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("Script") then
			if obj.Name == "Health" and obj.Disabled then
				obj.Disabled = false          -- вернуть регенерацию
			elseif obj.Name == "Respawn" and not obj.Disabled then
				obj.Disabled = true           -- запретить воскрешение (нужно для зачистки)
			end
		end
	end
	-- 3) Дегенеративный риг (сохранён с MaxHealth 0) — даём ему нормальное HP.
	if humanoid.MaxHealth <= 0 then
		humanoid.MaxHealth = 100
		humanoid.Health = 100
	end
end

--====================================================
-- Учёт живых врагов острова
--====================================================
local function checkCleared(island)
	if island.cleared or not island.armed or not island.registeredAny then return end
	if next(island.aliveSet) ~= nil then return end -- ещё есть живые
	island.cleared = true
	print("[IslandClear] " .. island.model.Name .. " зачищен — запускаю катсцену")
	effectRemote:FireAllClients(island.model:GetPivot().Position)
end

local function registerEnemy(island, model)
	if not model:IsA("Model") then return end
	if island.aliveSet[model] then return end

	task.spawn(function()
		local humanoid = model:FindFirstChildWhichIsA("Humanoid")
			or model:WaitForChild("Humanoid", 5)
		-- Только ЖИВОЙ враг считается целью зачистки; трупы (Health<=0) игнорим.
		if not humanoid or humanoid.Health <= 0 then return end

		normalizeEnemy(model, humanoid)

		island.aliveSet[model] = true
		island.registeredAny = true

		local function down()
			if island.aliveSet[model] == nil then return end
			island.aliveSet[model] = nil
			checkCleared(island)
		end

		humanoid.Died:Connect(down)
		humanoid:GetPropertyChangedSignal("Health"):Connect(function()
			if humanoid.Health <= 0 then down() end
		end)
		model.AncestryChanged:Connect(function(_, parent)
			if parent == nil then down() end
		end)
	end)
end

local function setupIsland(islandModel)
	if setupDone[islandModel] then return end
	local enemies = islandModel:FindFirstChild(ENEMIES_FOLDER)
	if not enemies or not enemies:IsA("Folder") then return end
	setupDone[islandModel] = true

	local island = {
		model         = islandModel,
		aliveSet      = {},
		registeredAny = false,
		armed         = false,
		cleared       = false,
	}
	islands[islandModel] = island

	-- Текущие враги.
	for _, child in ipairs(enemies:GetChildren()) do
		registerEnemy(island, child)
	end
	-- Новые враги (стриминг / случайный респавн, который мы не успели погасить).
	enemies.ChildAdded:Connect(function(child)
		registerEnemy(island, child)
	end)

	-- Взводим проверку после паузы, чтобы успели зарегистрироваться стартовые
	-- враги (WaitForChild на Humanoid у каждого — асинхронно).
	task.delay(1, function()
		island.armed = true
		checkCleared(island)
	end)
end

--====================================================
-- Поиск островов (размещённых и заспавненных IslandSpawner'ом)
--====================================================
local function scanModel(inst)
	if inst:IsA("Model") and inst:FindFirstChild(ENEMIES_FOLDER) then
		setupIsland(inst)
	end
end

for _, child in ipairs(Workspace:GetChildren()) do
	scanModel(child)
end

Workspace.ChildAdded:Connect(function(child)
	if not child:IsA("Model") then return end
	-- Папка Enemies может появиться на пару кадров позже самой модели.
	if child:FindFirstChild(ENEMIES_FOLDER) then
		setupIsland(child)
	else
		local conn
		conn = child.ChildAdded:Connect(function(sub)
			if sub.Name == ENEMIES_FOLDER and sub:IsA("Folder") then
				if conn then conn:Disconnect() end
				setupIsland(child)
			end
		end)
		-- Не держим соединение вечно.
		task.delay(10, function() if conn then conn:Disconnect() end end)
	end
end)
