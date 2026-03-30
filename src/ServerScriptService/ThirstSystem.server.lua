local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")

-- ─── Config ───
local MAX_THIRST = 100
local THIRST_DRAIN_AMOUNT = 2
local THIRST_DRAIN_INTERVAL = 5  -- lose 2 thirst every 5 seconds
local DRINK_RESTORE = 25
local PURIFY_TIME = 20
local THIRST_DAMAGE = 5  -- damage per second at 0 thirst
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
				thirstData[player] = math.max(0, thirstData[player] - THIRST_DRAIN_AMOUNT)
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

local function setCupState(tool, state)
	tool:SetAttribute("CupState", state)
	-- Swap visual model
	local modelName
	if state == "empty" then
		modelName = "Cup"
	elseif state == "salty" then
		modelName = "Cup_full_salty"
	elseif state == "fresh" then
		modelName = "Cup_full"
	end

	local template = rs:FindFirstChild(modelName)
	if not template then
		warn("ThirstSystem: cup model not found: " .. tostring(modelName))
		return
	end

	-- Remove ALL children from the tool (visual parts, meshes, etc.)
	for _, child in tool:GetChildren() do
		child:Destroy()
	end

	-- Clone new visual parts from template
	local hasHandle = false
	if template:IsA("Model") then
		for _, child in template:GetChildren() do
			local clone = child:Clone()
			clone.Parent = tool
			-- First BasePart becomes Handle (required for Tool)
			if not hasHandle and clone:IsA("BasePart") then
				clone.Name = "Handle"
				hasHandle = true
			end
		end
		-- If no direct BasePart child, search descendants
		if not hasHandle then
			local firstPart = tool:FindFirstChildWhichIsA("BasePart", true)
			if firstPart then
				firstPart.Name = "Handle"
				firstPart.Parent = tool -- move to direct child
			end
		end
	elseif template:IsA("BasePart") then
		local clone = template:Clone()
		clone.Name = "Handle"
		clone.Parent = tool
	end

	-- Update tool name for display
	if state == "empty" then
		tool.Name = "Cup"
	elseif state == "salty" then
		tool.Name = "Cup (Saltwater)"
	elseif state == "fresh" then
		tool.Name = "Cup (Fresh Water)"
	end
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
	local template = rs:FindFirstChild(modelName)
	if not template then
		warn("ThirstSystem: model not found: " .. modelName)
		return
	end

	-- Save the current world CFrame from an actual part (more reliable than GetPivot)
	local savedCF = nil
	local primaryPart = purifier.PrimaryPart
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

	-- Get the template's PrimaryPart CFrame to compute the offset
	-- Then position so purifier.PrimaryPart ends up at savedCF
	if purifier.PrimaryPart and savedCF then
		-- Use PivotTo which accounts for the model's pivot/PrimaryPart
		local templatePivot = template:GetPivot()
		local templatePrimaryCF = template.PrimaryPart and template.PrimaryPart.CFrame or templatePivot
		-- Simply PivotTo the saved CFrame
		purifier:PivotTo(savedCF)
	elseif savedCF then
		purifier:PivotTo(savedCF)
	end

	-- Weld to raft, then unanchor
	local raft = workspace:FindFirstChild("Raft")
	if raft and raft.PrimaryPart then
		for _, part in purifier:GetDescendants() do
			if part:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raft.PrimaryPart
				weld.Parent = part
				part.Anchored = false
			end
		end
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
		setCupState(tool, "salty")

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
		setCupState(tool, "empty")
		swapPurifierModel(purifier)

		-- Start or restart purification timer
		startPurification(purifier)

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
		setCupState(tool, "fresh")
		swapPurifierModel(purifier)

	elseif action == "drink" then
		-- Player has fresh cup, drinks it
		if not tool or getCupState(tool) ~= "fresh" then return end

		-- Restore thirst
		if thirstData[player] then
			thirstData[player] = math.min(MAX_THIRST, thirstData[player] + DRINK_RESTORE)
			thirstEvent:FireClient(player, thirstData[player], MAX_THIRST)
		end

		-- Play drinking animation
		local hum = char:FindFirstChildWhichIsA("Humanoid")
		if hum then
			local drinkAnim = rs:FindFirstChild("Drinking Animation")
				or rs:FindFirstChild("DrinkingAnimation")
				or rs:FindFirstChild("Drinking")
			if drinkAnim then
				local track = hum:LoadAnimation(drinkAnim)
				track:Play()
			end
		end

		setCupState(tool, "empty")

	elseif action == "placePurifier" then
		-- Player has Destitalor tool, place it on the raft
		if not tool or tool.Name ~= "Destitalor" then return end

		local raft = workspace:FindFirstChild("Raft")
		if not raft or not raft.PrimaryPart then return end

		-- Get placement position from target (CFrame sent from client)
		if typeof(target) ~= "CFrame" then return end

		local template = rs:FindFirstChild("Destitalor")
		if not template then return end

		local purifier = template:Clone()
		purifier.Name = "Purifier"
		purifier:SetAttribute("WaterLevel", 0)
		purifier:SetAttribute("WaterType", "none")
		purifier:SetAttribute("PlacedBy", player.UserId)

		-- Ensure PrimaryPart is set
		if purifier:IsA("Model") and not purifier.PrimaryPart then
			if template.PrimaryPart then
				local pp = purifier:FindFirstChild(template.PrimaryPart.Name)
				if pp then purifier.PrimaryPart = pp end
			end
			if not purifier.PrimaryPart then
				local first = purifier:FindFirstChildWhichIsA("BasePart", true)
				if first then purifier.PrimaryPart = first end
			end
		end

		purifier:PivotTo(target)
		purifier.Parent = raft

		-- Weld to raft
		for _, part in purifier:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raft.PrimaryPart
				weld.Parent = part
			end
		end

		-- Remove tool from player
		tool:Destroy()
	end
end)
