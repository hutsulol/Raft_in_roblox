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

-- ─── Enable grapes on bushes inside a garden ───
local function enableBushGrapes(garden)
	for _, child in garden:GetChildren() do
		if child:GetAttribute("IsBush") then
			child:SetAttribute("GrapesAvailable", true)
			local grapes = child:FindFirstChild("grapes") or child:FindFirstChild("Grapes")
			if grapes then
				if grapes:IsA("BasePart") then
					grapes.Transparency = 0
				elseif grapes:IsA("Model") then
					for _, p in grapes:GetDescendants() do
						if p:IsA("BasePart") then p.Transparency = 0 end
					end
				end
			end
		end
	end
end

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

	-- If just watered, enable grapes on any bushes
	if watered then
		enableBushGrapes(garden)
	end
end

-- ─── Water a garden bed ───
local function waterGarden(garden, player)
	-- Check if player has a cup with fresh water equipped
	local char = player.Character
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

		-- Strip pitch/roll from target so garden is level
		local tp = target.Position
		local _, ty, _ = target:ToEulerAnglesYXZ()
		local cleanTarget = CFrame.new(tp) * CFrame.Angles(0, ty, 0)
		local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(cleanTarget)

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

		-- Remove tool from player
		tool:Destroy()

	elseif action == "waterGarden" then
		-- Player presses E while looking at a garden bed with fresh water cup
		if not target or not target:IsA("Model") or not target:GetAttribute("IsGarden") then return end
		if target:GetAttribute("IsWatered") == true then return end -- already watered
		waterGarden(target, player)
	end
end)
