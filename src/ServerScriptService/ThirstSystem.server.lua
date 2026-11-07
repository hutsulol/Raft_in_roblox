local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local PlaceCheck = require(game:GetService("ReplicatedStorage"):WaitForChild("PlaceCheck"))   -- «место занято» — общая проверка

local Config = require(rs:WaitForChild("WeaponUpgradeConfig"))
local AssetFind = require(rs:WaitForChild("AssetFind"))
local RaftShake = require(rs:WaitForChild("RaftShake"))

-- ─── Config ───
local MAX_THIRST = 100
local THIRST_DRAIN_AMOUNT = 2
-- Полный запас (100) должен уходить РОВНО ЗА ОДИН ДЕНЬ (380с), чтобы к закату
-- жажда начинала мучить, если не пить. 100/2 = 50 тиков → 380/50 = 7.6с на тик.
-- Питьё восстанавливает 25 (DRINK_RESTORE), так что за день нужно ~4 глотка.
-- Класс «Выживший» 1 ур. вдвое замедляет расход (см. ниже) — ему хватает на 2 дня.
local THIRST_DRAIN_INTERVAL = 7.6 -- lose 2 thirst every 7.6s → ~100 за день
local DRINK_RESTORE = 25
-- Сколько длится глоток и как часто в это время подливается шкала. Столько же
-- держится поза питья на клиенте (DrinkPose читает атрибут Drinking).
local DRINK_TIME = 1.6
local DRINK_STEP = 0.1
local PURIFY_TIME = 20
local THIRST_DAMAGE = 0.625  -- damage per tick at 0 thirst (5 / 8)
local MAX_PURIFIER_WATER = 3

-- ─── Remote Events ───
local function getOrCreate(name)
	local e = rs:FindFirstChild(name)
	if not e then
		e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = rs
	end
	return e
end

local thirstEvent = getOrCreate("ThirstUpdate")
local cupActionEvent = getOrCreate("CupAction")  -- client → server

-- ─── Player Thirst Data ───
local thirstData = {}

local function initPlayer(player)
	thirstData[player] = MAX_THIRST
	thirstEvent:FireClient(player, thirstData[player], MAX_THIRST)
end

Players.PlayerAdded:Connect(function(player)
	initPlayer(player)
	player.CharacterAdded:Connect(function()
		thirstData[player] = MAX_THIRST
		thirstEvent:FireClient(player, MAX_THIRST, MAX_THIRST)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	thirstData[player] = nil
end)

for _, player in Players:GetPlayers() do
	initPlayer(player)
	player.CharacterAdded:Connect(function()
		thirstData[player] = MAX_THIRST
		thirstEvent:FireClient(player, MAX_THIRST, MAX_THIRST)
	end)
end

-- ─── Thirst Drain Loop ───
task.spawn(function()
	while true do
		task.wait(THIRST_DRAIN_INTERVAL)
		for _, player in Players:GetPlayers() do
			if thirstData[player] then
				-- ВЫЖИВШИЙ (1 ур.): жажда расходуется в 2 раза медленнее
				local drain = THIRST_DRAIN_AMOUNT
				if Config.activeClassLevel(player, "survivor") >= 1 then drain = drain * 0.5 end
				thirstData[player] = math.max(0, thirstData[player] - drain)
				thirstEvent:FireClient(player, thirstData[player], MAX_THIRST)

				if thirstData[player] <= 0 then
					local char = player.Character
					if char then
						local hum = char:FindFirstChildWhichIsA("Humanoid")
						if hum and hum.Health > 0 then
							hum:TakeDamage(THIRST_DAMAGE)
						end
					end
				end
			end
		end
	end
end)

-- ─── Cup Tool Helpers ───
local function getCupState(tool)
	return tool:GetAttribute("CupState") or "empty"
end

-- ⚠️ СОСУД НЕ ОБЯЗАН БЫТЬ КРУЖКОЙ.
-- Имя собиралось жёстко из «Cup», и любая ёмкость после первого же действия
-- становилась кружкой — бутылка теряла и имя, и иконку. Базовое имя держим на
-- самом туле (CupBase): вся остальная механика воды смотрит на атрибут CupState,
-- а не на имя, поэтому новый сосуд достаточно создать с этими двумя атрибутами.
local CUP_SUFFIX = { empty = "", salty = " (Saltwater)", fresh = " (Fresh Water)" }

local function cupBase(tool)
	local base = tool:GetAttribute("CupBase")
	if typeof(base) == "string" and base ~= "" then return base end
	return "Cup"
end

-- ⚠️ ЁМКОСТЬ СОСУДА — В ГЛОТКАХ, А НЕ В «ПОЛНЫЙ/ПУСТОЙ».
-- У кружки один глоток, у бутылки два: она больше. Раньше состояние было
-- двоичным, и налить в бутылку «побольше» было некуда — любой сосуд опустошался
-- первым же глотком. CupMax задаётся при создании тула (кружка 1, бутылка 2),
-- CupCharges — сколько осталось сейчас.
local function cupMax(tool)
	local m = tonumber(tool:GetAttribute("CupMax"))
	return (m and m >= 1) and math.floor(m) or 1
end

local function cupCharges(tool)
	local c = tonumber(tool:GetAttribute("CupCharges"))
	return c and math.max(0, math.floor(c)) or 0
end

local function setCupState(player, tool, state)
	tool:SetAttribute("CupState", state)
	-- набрали — сосуд полон; опустел — зарядов нет
	tool:SetAttribute("CupCharges", (state == "empty") and 0 or cupMax(tool))
	tool.Name = cupBase(tool) .. (CUP_SUFFIX[state] or "")
	return tool
end

-- Наружу: тем же способом переименовывает сосуд полив грядки (PlanterService).
_G.SetCupState = function(tool, state)
	if typeof(tool) ~= "Instance" then return end
	setCupState(nil, tool, state)
end

-- ─── Purifier Helpers ───
local function getPurifierModel(purifier)
	local waterLevel = purifier:GetAttribute("WaterLevel") or 0
	local waterType = purifier:GetAttribute("WaterType") or "none"

	if waterLevel == 0 or waterType == "none" then
		return "Destitalor"
	elseif waterType == "salty" then
		return "Destitalor_salty_" .. waterLevel
	elseif waterType == "fresh" then
		return "Destitalor_unleavened_" .. waterLevel
	end
	return "Destitalor"
end

local function swapPurifierModel(purifier)
	local modelName = getPurifierModel(purifier)
	-- ⚠️ СТАДИИ ИЩЕМ ПО ИМЕНИ, А НЕ ПРЯМЫМ РЕБЁНКОМ ХРАНИЛИЩА.
	-- Установку очистителя на AssetFind уже перевели, а вот эту подмену — нет, и
	-- она отвалилась молча: FindFirstChild перестал видеть стадии, как только их
	-- сложили в папку. Снаружи это выглядит как «очиститель не меняется при
	-- наполнении» — вода-то заливается, атрибуты растут, а модель остаётся
	-- пустой. Ошибки при этом нет, только warn в логе.
	local template = AssetFind.find(modelName)
	if not template then
		warn("ThirstSystem: не найдена стадия очистителя: " .. modelName)
		return
	end

	-- Snapshot raft velocity + capture the purifier's raft-relative pose
	-- BEFORE we touch anything. T13's snapshot/restore was running too
	-- late — the destroy + clone steps span a couple of physics frames
	-- during which the raft drifts, so saving the world CFrame and then
	-- PivotTo()'ing back to it leaves the new parts at a stale position
	-- relative to the (now-moved) raft. Welds then lock that offset in
	-- and Roblox's solver corrects with a jolt → the bouncing.
	local raft = workspace:FindFirstChild("Raft")
	local raftPrimary = raft and raft.PrimaryPart or nil
	local linVel, angVel
	if raftPrimary then
		linVel = raftPrimary.AssemblyLinearVelocity
		angVel = raftPrimary.AssemblyAngularVelocity
	end

	-- Save the current pose AS A RAFT-LOCAL CFrame so we can restore it
	-- against whatever the raft's pose is at the end of the swap, not
	-- where the raft was at the start.
	local savedRelCF = nil
	local primaryPart = purifier.PrimaryPart
	local savedCF = nil
	if primaryPart then
		savedCF = primaryPart.CFrame
	else
		local firstPart = purifier:FindFirstChildWhichIsA("BasePart", true)
		if firstPart then
			savedCF = firstPart.CFrame
		else
			savedCF = purifier:GetPivot()
		end
	end
	if raftPrimary and savedCF then
		savedRelCF = raftPrimary.CFrame:ToObjectSpace(savedCF)
	end

	-- Save attributes
	local waterLevel = purifier:GetAttribute("WaterLevel")
	local waterType = purifier:GetAttribute("WaterType")
	local purifyStart = purifier:GetAttribute("PurifyStartTime")
	local placedBy = purifier:GetAttribute("PlacedBy")

	-- Clear all old children
	for _, child in purifier:GetChildren() do
		child:Destroy()
	end

	-- Clone new model contents, anchor everything first so nothing moves
	if template:IsA("Model") then
		for _, child in template:GetChildren() do
			local clone = child:Clone()
			if clone:IsA("BasePart") then
				clone.Anchored = true
			end
			-- Also anchor descendants (nested parts)
			for _, desc in clone:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.Anchored = true
				end
			end
			clone.Parent = purifier
		end
		-- Set PrimaryPart from template
		if template.PrimaryPart then
			local newPrimary = purifier:FindFirstChild(template.PrimaryPart.Name)
			if newPrimary then
				purifier.PrimaryPart = newPrimary
			end
		end
		-- Fallback: set first BasePart as PrimaryPart
		if not purifier.PrimaryPart then
			local first = purifier:FindFirstChildWhichIsA("BasePart", true)
			if first then
				purifier.PrimaryPart = first
			end
		end
	end

	-- Position relative to the raft's CURRENT pose, not the stale one.
	-- This way the new parts always land at the right spot on the raft
	-- regardless of how far the raft drifted between destroy + clone.
	if purifier.PrimaryPart and savedRelCF and raftPrimary then
		purifier:PivotTo(raftPrimary.CFrame * savedRelCF)
	elseif savedCF then
		purifier:PivotTo(savedCF)
	end

	-- Weld FIRST while every part is still anchored, THEN unanchor in
	-- a second pass (T15). Unanchoring first leaves each part as a
	-- zero-velocity free body that the weld's solver has to equalise
	-- against the moving raft, and that drain is what kicks the
	-- buoyancy spring into a bob with multi-part models like the
	-- Destitalor.
	if raftPrimary then
		for _, part in purifier:GetDescendants() do
			if part:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raftPrimary
				weld.Parent = part
			end
		end
		for _, part in purifier:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end
		-- Restore the raft's velocity from the pre-destroy snapshot so
		-- nothing the swap did (destroy / clone / weld) bleeds momentum
		-- out of the assembly.
		raftPrimary.AssemblyLinearVelocity  = linVel
		raftPrimary.AssemblyAngularVelocity = angVel
		-- Скорость плоту вернули, а игрока на палубе — нет: он чужая сборка и
		-- принадлежит своему клиенту. Просим клиентов удержать место (см. RaftShake).
		RaftShake.notify()
	end

	-- Restore attributes
	purifier:SetAttribute("WaterLevel", waterLevel)
	purifier:SetAttribute("WaterType", waterType)
	purifier:SetAttribute("PurifyStartTime", purifyStart)
	purifier:SetAttribute("PlacedBy", placedBy)
	purifier.Name = "Purifier"
end

local function startPurification(purifier)
	purifier:SetAttribute("PurifyStartTime", tick())

	task.delay(PURIFY_TIME, function()
		if not purifier or not purifier.Parent then return end
		local waterType = purifier:GetAttribute("WaterType")
		if waterType == "salty" then
			purifier:SetAttribute("WaterType", "fresh")
			swapPurifierModel(purifier)
		end
	end)
end

-- ─── Handle Cup Actions ───
cupActionEvent.OnServerEvent:Connect(function(player, action, target)
	local char = player.Character
	if not char then return end

	local tool = char:FindFirstChildWhichIsA("Tool")

	if action == "scoopSaltwater" then
		-- Player has empty cup equipped, wants to scoop saltwater
		if not tool or not tool:GetAttribute("CupState") then return end
		if getCupState(tool) ~= "empty" then return end
		setCupState(player, tool, "salty")

	elseif action == "dumpWater" then
		-- Player has salty cup, dumps it back into the ocean
		if not tool or getCupState(tool) ~= "salty" then return end
		setCupState(player, tool, "empty")

	elseif action == "fillPurifier" then
		-- Player has salty cup, clicks on purifier
		if not tool or getCupState(tool) ~= "salty" then return end
		if not target or not target.Parent then return end

		-- Find the purifier model (target might be a descendant)
		local purifier = target
		while purifier and purifier.Parent ~= workspace do
			if purifier:GetAttribute("WaterType") ~= nil then break end
			purifier = purifier.Parent
		end
		-- Also check raft children
		local raft = workspace:FindFirstChild("Raft")
		if raft then
			while purifier and purifier.Parent ~= raft and purifier.Parent ~= workspace do
				if purifier:GetAttribute("WaterType") ~= nil then break end
				purifier = purifier.Parent
			end
		end

		if not purifier or purifier:GetAttribute("WaterType") == nil then return end

		local waterLevel = purifier:GetAttribute("WaterLevel") or 0
		local waterType = purifier:GetAttribute("WaterType") or "none"

		-- Can only fill if empty or already salty, and not full
		if waterType == "fresh" then return end -- can't mix
		if waterLevel >= MAX_PURIFIER_WATER then return end

		purifier:SetAttribute("WaterLevel", waterLevel + 1)
		purifier:SetAttribute("WaterType", "salty")
		setCupState(player, tool, "empty")
		swapPurifierModel(purifier)

		-- Start or restart purification timer
		startPurification(purifier)

		-- Квест-хук: онбординг-квест #2 «Fresh Water» (onboarding_purifier)
		-- слушает purifier:filled как финальную цель. pcall — чтобы сбой в
		-- квестовой системе не ломал заливку воды.
		if typeof(_G.OnQuestEvent) == "function" then
			pcall(_G.OnQuestEvent, player, "purifier:filled", 1)
		end

	elseif action == "collectWater" then
		-- Player has empty cup, clicks on purifier with fresh water
		if not tool or getCupState(tool) ~= "empty" then return end
		if not target or not target.Parent then return end

		local purifier = target
		while purifier and purifier.Parent ~= workspace do
			if purifier:GetAttribute("WaterType") ~= nil then break end
			purifier = purifier.Parent
		end
		local raft = workspace:FindFirstChild("Raft")
		if raft then
			while purifier and purifier.Parent ~= raft and purifier.Parent ~= workspace do
				if purifier:GetAttribute("WaterType") ~= nil then break end
				purifier = purifier.Parent
			end
		end

		if not purifier or purifier:GetAttribute("WaterType") == nil then return end

		local waterLevel = purifier:GetAttribute("WaterLevel") or 0
		local waterType = purifier:GetAttribute("WaterType") or "none"

		if waterType ~= "fresh" or waterLevel <= 0 then return end

		purifier:SetAttribute("WaterLevel", waterLevel - 1)
		if waterLevel - 1 <= 0 then
			purifier:SetAttribute("WaterType", "none")
		end
		setCupState(player, tool, "fresh")
		swapPurifierModel(purifier)

	elseif action == "drink" then
		-- Player has fresh cup, drinks it
		if not tool or getCupState(tool) ~= "fresh" then return end
		-- два глотка разом не начинаем: иначе одна порция воды восстановила бы две
		if char:GetAttribute("Drinking") == true then return end

		-- ⚠️ ТРАТИМ ОДИН ГЛОТОК, А НЕ ВЕСЬ СОСУД.
		-- Бутылка держит два: после первого она остаётся полной наполовину, и
		-- второй глоток доступен без похода к очистителю.
		local left = cupCharges(tool) - 1
		if left > 0 then
			tool:SetAttribute("CupCharges", left)
		else
			setCupState(player, tool, "empty")
		end

		-- ⚠️ ШКАЛА НАПОЛНЯЕТСЯ ВО ВРЕМЯ ГЛОТКА, А НЕ РАЗОМ.
		-- Раньше вся порция прибавлялась одним числом в тот же кадр: анимация
		-- питья ещё только начиналась, а шкала уже стояла полной — выглядело так,
		-- будто персонаж пьёт «задним числом». Теперь порция размазана по времени
		-- анимации, и полоска ползёт ровно пока он держит сосуд у рта.
		--
		-- Флаг Drinking реплицируется — по нему клиент (DrinkPose) ведёт позу.
		char:SetAttribute("Drinking", true)
		task.spawn(function()
			local steps = math.max(1, math.floor(DRINK_TIME / DRINK_STEP))
			local per = DRINK_RESTORE / steps
			for _ = 1, steps do
				task.wait(DRINK_STEP)
				-- игрок мог выйти, умереть или сменить тело — глоток обрывается
				if not player.Parent then return end
				local c = player.Character
				if not c or c ~= char then break end
				local hum = c:FindFirstChildWhichIsA("Humanoid")
				if not hum or hum.Health <= 0 then break end
				if thirstData[player] then
					thirstData[player] = math.min(MAX_THIRST, thirstData[player] + per)
					thirstEvent:FireClient(player, thirstData[player], MAX_THIRST)
				end
			end
			if char.Parent then char:SetAttribute("Drinking", false) end
		end)

		-- ФИНАЛ ОНБОРДИНГА «Пресная вода». Квест закрывается ИМЕННО ЗДЕСЬ, а не
		-- на заливке очистителя: смысл цепочки — утолить жажду, а между заливкой
		-- и глотком ещё два действия (дождаться очистки и набрать воду). Раньше
		-- награда выдавалась с полным очистителем и пустой шкалой жажды.
		if typeof(_G.OnQuestEvent) == "function" then
			pcall(_G.OnQuestEvent, player, "purifier:drank", 1)
			-- «чистая вода пошла в дело» — та же цель закрывается и поливом грядки
			-- (см. purifier:used в QuestCatalog и PlanterService)
			pcall(_G.OnQuestEvent, player, "purifier:used", 1)
		end

		-- Play drinking animation (pcall to prevent errors from blocking)
		pcall(function()
			local hum = char:FindFirstChildWhichIsA("Humanoid")
			if hum then
				local drinkAnim = AssetFind.findClass("Animation",
					"R6 Drinking Animation", "Drinking Animation",
					"DrinkingAnimation", "Drinking")
				if drinkAnim and drinkAnim:IsA("Animation") then
					local animator = hum:FindFirstChildOfClass("Animator")
					if not animator then
						animator = Instance.new("Animator")
						animator.Parent = hum
					end
					local track = animator:LoadAnimation(drinkAnim)
					track:Play()
				end
			end
		end)

	elseif action == "placePurifier" then
		-- Player has Destitalor tool, place it on the raft
		if not tool or tool.Name ~= "Destitalor" then return end

		local raft = workspace:FindFirstChild("Raft")
		if not raft or not raft.PrimaryPart then return end

		-- Get placement offset relative to raft (CFrame sent from client)
		if typeof(target) ~= "CFrame" then return end

		-- Convert raft-relative offset to world space
		local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

		-- по имени, а не по месту: модели разложены по папкам (см. AssetFind)
		local template = AssetFind.find("Destitalor")
		if not template then return end

		local purifier = template:Clone()
		purifier.Name = "Purifier"
		purifier:SetAttribute("WaterLevel", 0)
		purifier:SetAttribute("WaterType", "none")
		purifier:SetAttribute("PlacedBy", player.UserId)

		-- Reset WorldPivot to bounding box center with no rotation (match client ghost)
		if purifier:IsA("Model") then
			local bbCF = purifier:GetBoundingBox()
			purifier.WorldPivot = CFrame.new(bbCF.Position)
		end

		purifier:PivotTo(worldCF)
		if PlaceCheck.refuseIfBlocked(purifier, raft, player) then return end   -- в предмет ставить нельзя
		purifier.Parent = raft

		-- Same velocity-preservation pattern as the workbench branch
		-- above so placing the purifier doesn't kick the raft's vertical
		-- buoyancy out of equilibrium. Force-anchor every part FIRST
		-- (T16) — the Destitalor template stores its parts unanchored,
		-- so the cloned model otherwise starts free-falling under
		-- gravity before our welds attach, and Roblox's solver then
		-- has to equalise the falling part with the moving raft. Then
		-- weld while anchored (T15) and only unanchor in a third pass
		-- so the parts inherit the raft's velocity through the rigid
		-- weld instead of starting at zero.
		local primary = raft.PrimaryPart
		local linVel = primary.AssemblyLinearVelocity
		local angVel = primary.AssemblyAngularVelocity

		-- Pass 0: anchor every part regardless of how the template was authored.
		for _, part in purifier:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		-- Pass 1: weld every part to the raft while still anchored.
		for _, part in purifier:GetDescendants() do
			if part:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raft.PrimaryPart
				weld.Parent = part
			end
		end
		-- Pass 2: unanchor (parts inherit raft velocity via the weld).
		for _, part in purifier:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end

		primary.AssemblyLinearVelocity  = linVel
		primary.AssemblyAngularVelocity = angVel
		RaftShake.notify()

		-- Remove tool from player
		tool:Destroy()

	elseif action == "placeWorkbench" then
		-- Player places a workbench on the raft
		if not tool or tool.Name ~= "WorkBench" then return end

		local raft = workspace:FindFirstChild("Raft")
		if not raft or not raft.PrimaryPart then return end

		if typeof(target) ~= "CFrame" then return end

		local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

		-- по имени, а не по месту: модели разложены по папкам (см. AssetFind)
		local template = AssetFind.find("WorkBench")
		if not template then return end

		local workbench = template:Clone()
		workbench.Name = "WorkBench"

		-- Reset WorldPivot to bounding box center with no rotation (match client ghost)
		if workbench:IsA("Model") then
			local bbCF = workbench:GetBoundingBox()
			workbench.WorldPivot = CFrame.new(bbCF.Position)
		end

		workbench:PivotTo(worldCF)
		if PlaceCheck.refuseIfBlocked(workbench, raft, player) then return end   -- в предмет ставить нельзя
		workbench.Parent = raft

		-- T13/T15/T16: snapshot raft velocity, force-anchor every part
		-- (templates may be stored unanchored), weld while anchored,
		-- then unanchor so the new parts inherit the raft's velocity
		-- through the rigid weld.
		local primary = raft.PrimaryPart
		local linVel = primary.AssemblyLinearVelocity
		local angVel = primary.AssemblyAngularVelocity

		for _, part in workbench:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		for _, part in workbench:GetDescendants() do
			if part:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raft.PrimaryPart
				weld.Parent = part
			end
		end
		for _, part in workbench:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end

		primary.AssemblyLinearVelocity  = linVel
		primary.AssemblyAngularVelocity = angVel
		RaftShake.notify()

		-- Add ProximityPrompt if not already present
		local hasPrompt = workbench:FindFirstChildWhichIsA("ProximityPrompt", true)
		if not hasPrompt then
			local promptPart = workbench.PrimaryPart or workbench:FindFirstChildWhichIsA("BasePart", true)
			if promptPart then
				local openEvent = rs:FindFirstChild("OpenWorkbench")
				if not openEvent then
					openEvent = Instance.new("RemoteEvent")
					openEvent.Name = "OpenWorkbench"
					openEvent.Parent = rs
				end

				local prompt = Instance.new("ProximityPrompt")
				prompt.ActionText = "Создать"
				prompt.ObjectText = "Верстак"
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.HoldDuration = 0.5
				prompt.MaxActivationDistance = 10
				prompt.RequiresLineOfSight = true
				prompt.Parent = promptPart

				prompt.Triggered:Connect(function(triggerPlayer)
					openEvent:FireClient(triggerPlayer)
				end)
			end
		end

		-- Remove tool from player
		tool:Destroy()
	end
end)
-- СЕЙВ: жажда переживает выход из игры
_G.GetThirst = function(player) return thirstData[player] end
_G.SetThirst = function(player, v)
	v = tonumber(v); if not v then return end
	thirstData[player] = math.clamp(v, 0, MAX_THIRST)
	thirstEvent:FireClient(player, thirstData[player], MAX_THIRST)
end


--[[ ═══ КРУЖКА: ВОДА ВИДНА В РУКЕ ═══
     Модель Cup — одна на все состояния: Handle (корпус) + WaterFresh + WaterSalty.
     По CupState показываем нужную воду и прячем другую; тул не пересоздаём.
     (Жило отдельным скриптом CupVisuals, но новый файл Rojo в плейс не довёз —
     здесь, рядом с setCupState, оно точно на месте.) ]]
do
	local Players = game:GetService("Players")

	local LOG = "[Кружка]"
	local WATER = { fresh = "WaterFresh", salty = "WaterSalty" }

	local function partNamed(tool, name)
		local p = tool:FindFirstChild(name, true)
		return (p and p:IsA("BasePart")) and p or nil
	end

	-- один раз на тул: ручка = CupBody, вода приварена к ней
	local function prepare(tool)
		if tool:GetAttribute("CupPrepared") then return true end
		local body = partNamed(tool, "CupBody")
		local handle = tool:FindFirstChild("Handle")
		if not partNamed(tool, "WaterFresh") and not partNamed(tool, "WaterSalty") and not body then
			return false   -- старая кружка без мешей воды — показывать нечего
		end
		-- крафт назвал «Handle» первую попавшуюся деталь: если это вода — вернуть имя
		if handle and body and handle ~= body then
			local missing = nil
			for _, n in pairs(WATER) do
				if not partNamed(tool, n) then missing = n end
			end
			if missing then   -- «Handle» — это пропавшая вода; своя ручка у тула — не трогаем
				handle.Name = missing
				body.Name = "Handle"
				handle = body
			end
		elseif body and not handle then
			body.Name = "Handle"
			handle = body
		end
		if not (handle and handle:IsA("BasePart")) then return false end
		for _, n in pairs(WATER) do
			local w = partNamed(tool, n)
			if w then
				w.Anchored = false
				w.CanCollide = false
				w.CanTouch = false
				w.CanQuery = false
				w.Massless = true
				local welded = false
				for _, j in ipairs(tool:GetDescendants()) do
					if (j:IsA("JointInstance") or j:IsA("WeldConstraint"))
						and ((j.Part0 == w and j.Part1 == handle) or (j.Part0 == handle and j.Part1 == w)) then
						welded = true
						break
					end
				end
				if not welded then
					local c = Instance.new("WeldConstraint")
					c.Part0 = handle
					c.Part1 = w
					c.Parent = w
				end
				if w:GetAttribute("CupOrigTransparency") == nil then
					w:SetAttribute("CupOrigTransparency", w.Transparency)
				end
			end
		end
		handle.Anchored = false
		tool:SetAttribute("CupPrepared", true)
		return true
	end

	local function applyLook(tool)
		if not prepare(tool) then return end
		local state = tool:GetAttribute("CupState") or "empty"
		for st, n in pairs(WATER) do
			local w = partNamed(tool, n)
			if w then
				-- в шаблоне вода может быть скрыта (Transparency 1) — тогда видимая = 0
				local orig = w:GetAttribute("CupOrigTransparency") or 0
				if orig >= 0.99 then orig = 0 end
				w.Transparency = (state == st) and orig or 1
			end
		end
		print(("%s %s: вода «%s», WaterFresh=%s WaterSalty=%s"):format(LOG, tool.Name, state,
			tostring(partNamed(tool, "WaterFresh") and partNamed(tool, "WaterFresh").Transparency),
			tostring(partNamed(tool, "WaterSalty") and partNamed(tool, "WaterSalty").Transparency)))
	end

	local function watch(tool)
		if not tool:IsA("Tool") or tool:GetAttribute("CupWatched") then return end
		if tool:GetAttribute("CupState") == nil then
			-- атрибут ставят чуть позже (крафт: initAttributes)
			local c
			c = tool:GetAttributeChangedSignal("CupState"):Connect(function()
				c:Disconnect()
				watch(tool)
			end)
			return
		end
		tool:SetAttribute("CupWatched", true)
		tool:GetAttributeChangedSignal("CupState"):Connect(function() applyLook(tool) end)
		applyLook(tool)
	end

	local function scan(container)
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("Tool") then watch(d) end
		end
		container.DescendantAdded:Connect(function(d)
			if d:IsA("Tool") then task.defer(watch, d) end
		end)
	end

	Players.PlayerAdded:Connect(scan)
	for _, p in ipairs(Players:GetPlayers()) do scan(p) end
	scan(workspace)

	print(LOG .. " готово: вода в руке по CupState (WaterFresh / WaterSalty в модели Cup)")
end
