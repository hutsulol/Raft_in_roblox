-- CanonSystem.server.lua
-- Unified building placement (Cannon, Deffender/ПВО, …). Clones the chosen model
-- from ReplicatedStorage onto the raft where the player clicked, welds it to the raft
-- (massless) so it rides along, and names it so the right system takes it over:
--   • Cannon     → "Cannon"            (CannonControl + ShipCombat)
--   • Deffender  → "Deffender_placedN" (AADefense matches the "Deffender_" prefix)

local rs = game:GetService("ReplicatedStorage")
local PlaceCheck = require(game:GetService("ReplicatedStorage"):WaitForChild("PlaceCheck"))   -- «место занято» — общая проверка

local AssetFind = require(rs:WaitForChild("AssetFind"))
local RaftShake = require(rs:WaitForChild("RaftShake"))

local cupActionEvent = rs:WaitForChild("CupAction")

-- Pulemet_lvl_1 ставится как обычное здание; сразу после парента в Raft его подхватывает
-- TurretSystem (workspace.DescendantAdded по префиксу "Pulemet_") — снимает жёсткие велды
-- отсюда и пересобирает на шарнирах (поворот/наклон/проворот стволов, сиденье).
local BUILDINGS = { Cannon = "Cannon", Deffender = "Deffender", MagmaCannon = "MagmaCannon",
	Big_Magma_Cannon = "Big_Magma_Cannon", Torch = "Torch",
	Pulemet_lvl_1 = "Pulemet_lvl_1", Pulemet_lvl_2 = "Pulemet_lvl_2" }
local placedCount = 0
local torchCount = 0

-- ── подбор оружия (пушки/ПВО/пулемёты) обратно в инвентарь за пиратскую валюту ──
-- Цена = 10 + 20 за каждый ПРЕДЫДУЩИЙ подбор (счётчик player.WeaponPickups): 1й=10, 2й=30, 3й=50.
-- ИНВЕНТАРНЫЕ иконки тулов (как в RewardSystem) — их видно в хотбаре после подбора.
local WEAPON_TOOL_ICONS = {
	Cannon           = "rbxassetid://118236242385241",
	Deffender        = "rbxassetid://86928740553428",
	MagmaCannon      = "rbxassetid://97658619335375",
	Big_Magma_Cannon = "rbxassetid://90669361199026",
	Pulemet_lvl_1    = "rbxassetid://106277044945645",
	Pulemet_lvl_2    = "rbxassetid://79105833790080",
}
-- имя модели на плоту → базовый тип оружия (Deffender ставится как "Deffender_placedN")
local function weaponTypeOf(model)
	if WEAPON_TOOL_ICONS[model.Name] then return model.Name end
	if model.Name:sub(1, 10) == "Deffender_" then return "Deffender" end
	return nil
end
-- защита от двойного подбора одной постройки (см. ветку pickupWeapon)
local pickupBusy = {}
game:GetService("Players").PlayerRemoving:Connect(function(plr) pickupBusy[plr] = nil end)

-- модель лежит внутри вражеского корабля? (у кораблей свои префиксы имён)
local ENEMY_SHIP_PREFIXES = { "Ship_enemy", "Magma_Ship", "ice_ship" }
local function underEnemyShip(inst)
	local m = inst
	while m and m ~= workspace do
		if m:IsA("Model") then
			for _, p in ipairs(ENEMY_SHIP_PREFIXES) do
				if m.Name:sub(1, #p) == p then return true end
			end
		end
		m = m.Parent
	end
	return false
end

local function makePlaceableTool(name, icon)
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.CanBeDropped = false
	if icon then tool.TextureId = icon end
	local handle = Instance.new("Part")
	handle.Name = "Handle"; handle.Size = Vector3.new(1, 1, 1); handle.Transparency = 1
	handle.Parent = tool
	return tool
end

-- resolve a template by exact name, else by prefix (so "Deffender" finds "Deffender_1")
-- ⚠️ Именно findPrefix, а не find: у турели ПВО внутри модели лежит ДЕТАЛЬ с тем же
-- именем, и обычный поиск отдавал её вместо всей турели. Подробности в AssetFind.
local function findTemplate(name)
	return AssetFind.findPrefix(name)
end

cupActionEvent.OnServerEvent:Connect(function(player, action, buildingName, target)
	-- ── ПОДБОР поставленного факела: модель исчезает, Tool возвращается в инвентарь ──
	if action == "pickupTorch" then
		local model = buildingName -- вторым аргументом клиент шлёт саму модель
		if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
		if model.Name:sub(1, 11) ~= "PlacedTorch" then return end
		local raftM = workspace:FindFirstChild("Raft")
		if not raftM or not model:IsDescendantOf(raftM) then return end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		if (model:GetPivot().Position - hrp.Position).Magnitude > 12 then return end
		local tpl = findTemplate("Torch")
		if not tpl then return end
		model:Destroy()
		local tool = tpl:Clone()
		if _G.GiveToolOrDrop then
			_G.GiveToolOrDrop(player, tool)
		else
			tool.Parent = player:FindFirstChildOfClass("Backpack") or char
		end
		return
	end

	-- ── ПОДБОР ОРУЖИЯ за пиратов: модель исчезает, Tool возвращается в инвентарь ──
	if action == "pickupWeapon" then
		local model = buildingName
		if typeof(model) ~= "Instance" or not model:IsA("Model") then return end

		-- ТОЛЬКО постройки ВЕРХНЕГО УРОВНЯ: прямой ребёнок Raft (поставлено игроком)
		-- либо прямой ребёнок Workspace (расставлено в эдиторе). Ровно это сканирует
		-- клиент. Проверка на «любой потомок Workspace» была дырой: пушки вражеских
		-- кораблей лежат ВНУТРИ модели корабля, и по ней их можно было купить за 10
		-- пиратов, попутно вырвав деталь из корабля и сломав расчёт урона по зонам.
		local raftM = workspace:FindFirstChild("Raft")
		if not (model.Parent == workspace or (raftM and model.Parent == raftM)) then return end

		-- подстраховка на случай, если корабль когда-нибудь окажется в другой иерархии
		if underEnemyShip(model) then return end

		local wtype = weaponTypeOf(model)
		if not wtype then return end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		-- до ЖИВОЙ детали, а не GetPivot: у турели без PrimaryPart пивот не едет за
		-- плотом и сервер отклонял бы подбор, который клиент честно предложил
		local rpart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if not rpart or (rpart.Position - hrp.Position).Magnitude > 16 then return end
		-- турель занята наводчиком → подбирать нельзя
		local seat = model:FindFirstChildWhichIsA("Seat", true) or model:FindFirstChildWhichIsA("VehicleSeat", true)
		if seat and seat.Occupant then return end

		-- ДЕБАУНС: списание сейчас синхронное, но если в SpendPirate когда-нибудь
		-- появится йелд (DataStore/ProfileService), два быстрых клика по одной модели
		-- прочитали бы один и тот же WeaponPickups и выдали два тула за одну постройку.
		if pickupBusy[player] then return end
		pickupBusy[player] = true

		local count = player:GetAttribute("WeaponPickups") or 0
		local price = 10 + 20 * count
		-- тул делаем ДО списания: если бы он не создался после оплаты, игрок остался
		-- бы и без денег, и без постройки
		local tool = makePlaceableTool(wtype, WEAPON_TOOL_ICONS[wtype])
		if not (_G.SpendPirate and _G.SpendPirate(player, price)) then
			tool:Destroy()
			pickupBusy[player] = nil
			return
		end
		player:SetAttribute("WeaponPickups", count + 1)
		model:Destroy()
		if _G.GiveToolOrDrop then
			_G.GiveToolOrDrop(player, tool)
		else
			tool.Parent = player:FindFirstChildOfClass("Backpack") or char
		end
		if _G.SendInventory then _G.SendInventory(player) end
		pickupBusy[player] = nil
		return
	end

	if action ~= "placeBuilding" then return end
	if type(buildingName) ~= "string" then return end
	local templateName = BUILDINGS[buildingName]
	if not templateName then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= buildingName then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end
	if typeof(target) ~= "CFrame" then return end

	local template = findTemplate(templateName)
	if not template then return end

	-- ── ФАКЕЛ: это Tool. Собираем его видимую часть (Handle+пламя+свет) в модель и варим
	-- к плоту с ПОЛНОЙ ориентацией (target уже содержит наклон по X/Z с клиента).
	-- Тул ТРАТИТСЯ: один факел в руке = один поставленный факел.
	if buildingName == "Torch" then
		local clone = template:Clone()
		local placed = Instance.new("Model")
		torchCount += 1
		placed.Name = "PlacedTorch" .. torchCount
		for _, d in ipairs(clone:GetChildren()) do
			if d:IsA("BasePart") then d.Parent = placed end
		end
		clone:Destroy()
		local handle = placed:FindFirstChild("Handle") or placed:FindFirstChildWhichIsA("BasePart")
		if not handle then placed:Destroy(); return end
		placed.PrimaryPart = handle
		placed:PivotTo(raft.PrimaryPart.CFrame:ToWorldSpace(target))
		for _, part in ipairs(placed:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false; part.Massless = true; part.CanCollide = false
				local w = Instance.new("WeldConstraint")
				w.Part0 = raft.PrimaryPart; w.Part1 = part; w.Parent = part
			elseif part:IsA("Script") or part:IsA("LocalScript") then
				part:Destroy() -- скрипты тула не нужны на размещённом факеле
			elseif part:IsA("Fire") or part:IsA("ParticleEmitter") or part:IsA("Smoke")
				or part:IsA("PointLight") or part:IsA("SpotLight") then
				part.Enabled = true -- пламя/свет горят на поставленном факеле
			end
		end
		placed:SetAttribute("RaftLocalCF", target)
		if PlaceCheck.refuseIfBlocked(placed, raft, player) then return end   -- в предмет ставить нельзя
		placed.Parent = raft
		tool:Destroy() -- факел ТРАТИТСЯ: один тул = один поставленный факел
		return
	end

	local model = template:Clone()
	if buildingName == "Deffender" then
		placedCount += 1
		model.Name = "Deffender_placed" .. placedCount
	else
		model.Name = buildingName
	end

	-- ⚠️ PrimaryPart СНИМАЕМ НА ВРЕМЯ ПОСТАНОВКИ.
	-- У модели с заданным PrimaryPart пивотом становится он, а WorldPivot движок
	-- игнорирует. У пушек PrimaryPart далеко от центра, и PivotTo ставил в точку
	-- прицела именно его — модель уезжала в сторону. Ставим по центру габарита, а
	-- PrimaryPart возвращаем: он нужен системам, которые потом берут пушку.
	local savedPrimary = model.PrimaryPart
	if model:IsA("Model") then
		model.PrimaryPart = nil
		local bbCF = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(bbCF.Position)
	end
	model:PivotTo(raft.PrimaryPart.CFrame:ToWorldSpace(target))
	if savedPrimary then model.PrimaryPart = savedPrimary end

	-- ⚠️ СНАЧАЛА ЗАЯКОРИТЬ, ПОТОМ ПРИВАРИТЬ, И ТОЛЬКО ПОТОМ ОТПУСТИТЬ.
	-- Здесь было наоборот: каждой детали сразу снимался якорь, а сварка создавалась
	-- следующей строкой. Между этими двумя действиями деталь — свободное тело, и
	-- стоит она ровно там, где игрок только что целился, то есть у него под ногами.
	-- Физика разруливала пересечение толчком — игрока подбрасывало и переворачивало.
	-- Ровно тот же порядок уже принят у печи, костра, гриля и кровати.
	local parts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.Massless = true
			parts[#parts + 1] = part
		end
	end
	for _, part in ipairs(parts) do
		local w = Instance.new("WeldConstraint")
		w.Part0 = raft.PrimaryPart
		w.Part1 = part
		w.Parent = part
	end
	-- скорость плота снимаем ДО отпускания и возвращаем после: добавление сборки
	-- отнимает у неё ход на шаг физики (см. RaftShake)
	local linVel = raft.PrimaryPart.AssemblyLinearVelocity
	local angVel = raft.PrimaryPart.AssemblyAngularVelocity
	for _, part in ipairs(parts) do part.Anchored = false end
	raft.PrimaryPart.AssemblyLinearVelocity = linVel
	raft.PrimaryPart.AssemblyAngularVelocity = angVel
	RaftShake.notify()   -- а игрока на палубе удержит его собственный клиент

	model:SetAttribute("RaftLocalCF", target)
	if buildingName ~= "Deffender" then model:SetAttribute("Loaded", false) end -- all cannons
	model.Parent = raft

	tool:Destroy()
end)
