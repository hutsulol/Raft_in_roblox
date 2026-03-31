local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")

-- ─── Config ───
local WATER_DRY_TIME = 60 -- seconds before watered garden dries out

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

local gardenActionEvent = getOrCreate("GardenAction")

-- ─── Forward declarations ───
local setupGardenPrompt

-- ─── Model Swap (dry ↔ watered, like purifier) ───
local function swapGardenModel(garden, watered)
	local templateName = watered and "Garden_watered" or "Garden"
	local template = rs:FindFirstChild(templateName)
	if not template then
		warn("GardenSystem: model not found: " .. templateName)
		return
	end

	-- Save position from an actual part
	local savedCF = nil
	local primaryPart = garden.PrimaryPart
	if primaryPart then
		savedCF = primaryPart.CFrame
	else
		local firstPart = garden:FindFirstChildWhichIsA("BasePart", true)
		if firstPart then
			savedCF = firstPart.CFrame
		else
			savedCF = garden:GetPivot()
		end
	end

	-- Save attributes
	local placedBy = garden:GetAttribute("PlacedBy")

	-- Save bush children (don't destroy them during swap!)
	local bushes = {}
	for _, child in garden:GetChildren() do
		if child:GetAttribute("IsBush") then
			table.insert(bushes, child)
			child.Parent = workspace -- temporarily move out
		end
	end

	-- Clear old children
	for _, child in garden:GetChildren() do
		child:Destroy()
	end

	-- Clone new model contents, anchor everything first
	if template:IsA("Model") then
		for _, child in template:GetChildren() do
			local clone = child:Clone()
			if clone:IsA("BasePart") then clone.Anchored = true end
			for _, desc in clone:GetDescendants() do
				if desc:IsA("BasePart") then desc.Anchored = true end
			end
			clone.Parent = garden
		end
		-- Set PrimaryPart from template
		if template.PrimaryPart then
			local newPrimary = garden:FindFirstChild(template.PrimaryPart.Name)
			if newPrimary then
				garden.PrimaryPart = newPrimary
			end
		end
		if not garden.PrimaryPart then
			local first = garden:FindFirstChildWhichIsA("BasePart", true)
			if first then garden.PrimaryPart = first end
		end
	end

	-- Position at saved CFrame
	if savedCF then
		garden:PivotTo(savedCF)
	end

	-- Weld to raft
	local raft = workspace:FindFirstChild("Raft")
	if raft and raft.PrimaryPart then
		for _, part in garden:GetDescendants() do
			if part:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raft.PrimaryPart
				weld.Parent = part
				part.Anchored = false
			end
		end
	end

	-- Restore bushes back into garden
	for _, bush in bushes do
		bush.Parent = garden
	end

	-- Restore attributes
	garden:SetAttribute("IsGarden", true)
	garden:SetAttribute("IsWatered", watered)
	garden:SetAttribute("PlacedBy", placedBy)
	garden.Name = "Garden"

	-- Re-setup ProximityPrompt on the new model
	setupGardenPrompt(garden)
end

-- ─── Setup ProximityPrompt for watering ───
setupGardenPrompt = function(garden)
	-- Remove any existing prompts
	for _, desc in garden:GetDescendants() do
		if desc:IsA("ProximityPrompt") then
			desc:Destroy()
		end
	end

	local promptPart = garden.PrimaryPart or garden:FindFirstChildWhichIsA("BasePart", true)
	if not promptPart then return end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Water"
	prompt.ObjectText = "Garden Bed"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = true
	prompt.Parent = promptPart

	prompt.Triggered:Connect(function(triggerPlayer)
		-- Check if player has a cup with fresh water equipped
		local char = triggerPlayer.Character
		if not char then return end

		local tool = char:FindFirstChildWhichIsA("Tool")
		if not tool then return end

		local cupState = tool:GetAttribute("CupState")
		if cupState ~= "fresh" then return end

		-- Empty the cup
		tool:SetAttribute("CupState", "empty")
		tool.Name = "Cup"

		-- Water the garden
		garden:SetAttribute("IsWatered", true)
		swapGardenModel(garden, true)

		-- Start dry timer
		local wateredTime = tick()
		garden:SetAttribute("WateredTime", wateredTime)

		task.delay(WATER_DRY_TIME, function()
			if not garden or not garden.Parent then return end
			-- Only dry out if this is still the same watering session
			if garden:GetAttribute("WateredTime") == wateredTime then
				garden:SetAttribute("IsWatered", false)
				swapGardenModel(garden, false)
			end
		end)
	end)
end

-- ─── Handle Garden Actions ───
gardenActionEvent.OnServerEvent:Connect(function(player, action, target)
	local char = player.Character
	if not char then return end

	if action == "placeGarden" then
		local tool = char:FindFirstChildWhichIsA("Tool")
		if not tool or tool.Name ~= "Garden" then return end

		local raft = workspace:FindFirstChild("Raft")
		if not raft or not raft.PrimaryPart then return end

		if typeof(target) ~= "CFrame" then return end

		-- Convert raft-relative offset to world space
		local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

		local template = rs:FindFirstChild("Garden")
		if not template then
			warn("GardenSystem: Garden template not found in ReplicatedStorage")
			return
		end

		local garden = template:Clone()
		garden.Name = "Garden"
		garden:SetAttribute("IsGarden", true)
		garden:SetAttribute("IsWatered", false)
		garden:SetAttribute("PlacedBy", player.UserId)

		-- Remove scripts from the clone
		for _, desc in garden:GetDescendants() do
			if desc:IsA("Script") or desc:IsA("LocalScript") then
				desc:Destroy()
			end
		end

		-- Reset WorldPivot to bounding box center with identity rotation
		if garden:IsA("Model") then
			local bbCF = garden:GetBoundingBox()
			garden.WorldPivot = CFrame.new(bbCF.Position)
		end

		garden:PivotTo(worldCF)
		garden.Parent = raft

		-- Weld to raft
		for _, part in garden:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raft.PrimaryPart
				weld.Parent = part
			end
		end

		-- Setup ProximityPrompt for watering
		setupGardenPrompt(garden)

		-- Remove tool from player
		tool:Destroy()
	end
end)
