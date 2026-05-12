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

	-- Snapshot raft velocity + capture garden pose AS RAFT-RELATIVE
	-- BEFORE any destroy/clone work (T14/T19). The destroy + clone
	-- steps span a couple of physics frames during which the raft
	-- drifts, so saving a world CFrame and PivotTo'ing it back later
	-- places the new parts against a stale raft pose. Welds then
	-- lock that drift in and the solver kicks the assembly to fix
	-- it → the bouncing.
	local raft = workspace:FindFirstChild("Raft")
	local raftPrimary = raft and raft.PrimaryPart or nil
	local linVel, angVel
	if raftPrimary then
		linVel = raftPrimary.AssemblyLinearVelocity
		angVel = raftPrimary.AssemblyAngularVelocity
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
	local savedRelCF
	if raftPrimary and savedCF then
		savedRelCF = raftPrimary.CFrame:ToObjectSpace(savedCF)
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

	-- Position against the raft's CURRENT pose, not the stale one.
	if savedRelCF and raftPrimary then
		garden:PivotTo(raftPrimary.CFrame * savedRelCF)
	elseif savedCF then
		garden:PivotTo(savedCF)
	end

	-- T15/T16: weld FIRST while anchored (the swap pass-1 already
	-- anchored the new parts on clone), THEN unanchor in a separate
	-- pass so the parts inherit the raft's velocity through the
	-- rigid weld instead of being equalised from a free-body state.
	if raftPrimary then
		for _, part in garden:GetDescendants() do
			if part:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raftPrimary
				weld.Parent = part
			end
		end
		for _, part in garden:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end
		raftPrimary.AssemblyLinearVelocity  = linVel
		raftPrimary.AssemblyAngularVelocity = angVel
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

	-- Both action handlers below share the same place-a-static-bed-on-
	-- the-raft flow; only the tool name, ReplicatedStorage template,
	-- and post-place model Name differ.
	local function placeBedTemplate(toolName, templateName, finalName, extraAttributes)
		local tool = char:FindFirstChildWhichIsA("Tool")
		if not tool or tool.Name ~= toolName then return end

		local raft = workspace:FindFirstChild("Raft")
		if not raft or not raft.PrimaryPart then return end

		if typeof(target) ~= "CFrame" then return end

		local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

		local template = rs:FindFirstChild(templateName)
		if not template then
			warn("GardenSystem: template not found in ReplicatedStorage: " .. templateName)
			return
		end

		local placed = template:Clone()
		placed.Name = finalName
		placed:SetAttribute("PlacedBy", player.UserId)
		if extraAttributes then
			for k, v in pairs(extraAttributes) do
				placed:SetAttribute(k, v)
			end
		end

		-- Remove scripts from the clone
		for _, desc in placed:GetDescendants() do
			if desc:IsA("Script") or desc:IsA("LocalScript") then
				desc:Destroy()
			end
		end

		-- Reset WorldPivot to bounding box center with identity rotation
		if placed:IsA("Model") then
			local bbCF = placed:GetBoundingBox()
			placed.WorldPivot = CFrame.new(bbCF.Position)
		end

		placed:PivotTo(worldCF)
		placed.Parent = raft

		-- Same 3-pass weld pattern used by the regular Garden / Bed /
		-- WorkBench placements: snapshot raft velocity, anchor, weld
		-- while anchored, unanchor, restore velocity. Without this the
		-- placement kicks the buoyancy spring into a vertical bob.
		local primary = raft.PrimaryPart
		local linVel = primary.AssemblyLinearVelocity
		local angVel = primary.AssemblyAngularVelocity

		for _, part in placed:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		for _, part in placed:GetDescendants() do
			if part:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raft.PrimaryPart
				weld.Parent = part
			end
		end
		for _, part in placed:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end

		primary.AssemblyLinearVelocity  = linVel
		primary.AssemblyAngularVelocity = angVel

		-- Remove tool from player
		tool:Destroy()
	end

	if action == "placeGarden" then
		placeBedTemplate("Garden", "Garden", "Garden", {
			IsGarden  = true,
			IsWatered = false,
		})

	elseif action == "placeBedGardenForTree" then
		-- Larger tree-sized garden bed. Uses the same on-raft welding
		-- flow as the regular garden but carries a different name +
		-- IsBedGardenForTree attribute so downstream systems (future
		-- tree-planting logic) can distinguish it from a regular
		-- bush-hosting garden.
		placeBedTemplate("Bed_Garden_For_Tree", "Bed_Garden_For_Tree", "Bed_Garden_For_Tree", {
			IsBedGardenForTree = true,
		})

	elseif action == "waterGarden" then
		-- Player presses E while looking at a garden bed with fresh water cup
		if not target or not target:IsA("Model") or not target:GetAttribute("IsGarden") then return end
		if target:GetAttribute("IsWatered") == true then return end -- already watered
		waterGarden(target, player)
	end
end)
