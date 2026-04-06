local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local rs = ReplicatedStorage

local sawmillActionEvent = Instance.new("RemoteEvent")
sawmillActionEvent.Name = "SawmillAction"
sawmillActionEvent.Parent = rs

-- Constants
local SLIDE_TIME = 5       -- seconds: log slides from placer to saw
local SAW_TIME = 1.5       -- seconds: sawing pause
local OUTPUT_TIME = 3      -- seconds: planks slide from saw to claimer
local PLANKS_PER_LOG = 2
local DETECT_RADIUS = 6    -- studs: how close a dropped log must be to the placer

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

local function weldToRaft(obj, raft)
	for _, part in obj:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = raft.PrimaryPart
			weld.Parent = part
		end
	end
end

local function getSawmillParts(sawmill)
	local parts = { hexagonPlacer = nil, hexagonClaimer = nil, sawBlade = nil }
	for _, child in sawmill:GetDescendants() do
		if child.Name == "Hexagon_placer" then parts.hexagonPlacer = child end
		if child.Name == "Hexagon_claimer" then parts.hexagonClaimer = child end
		if child.Name == "SawBlade" then parts.sawBlade = child end
	end
	return parts
end

local function getPartPosition(part)
	if part:IsA("Model") then return part:GetPivot().Position end
	return part.CFrame.Position
end

-- Ensure PrimaryPart on a model clone
local function ensurePrimaryPart(model)
	if model:IsA("Model") and not model.PrimaryPart then
		local first = model:FindFirstChildWhichIsA("BasePart")
		if first then model.PrimaryPart = first end
	end
end

-- Animate a model sliding from A to B (anchored, in workspace)
local function slideModel(model, startPos, endPos, duration)
	if not model or not model.Parent then return end

	local dir = (endPos - startPos)
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	if flatDir.Magnitude < 0.01 then flatDir = Vector3.new(1, 0, 0) end
	flatDir = flatDir.Unit

	local startCF = CFrame.lookAt(startPos, startPos + flatDir) * CFrame.Angles(0, 0, math.rad(90))
	local endCF = CFrame.lookAt(endPos, endPos + flatDir) * CFrame.Angles(0, 0, math.rad(90))

	-- Anchor everything
	if model:IsA("BasePart") then
		model.Anchored = true
		model.CanCollide = false
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
		end
	end

	model:PivotTo(startCF)

	local steps = math.max(1, math.ceil(duration * 30))
	for i = 1, steps do
		if not model or not model.Parent then return end
		model:PivotTo(startCF:Lerp(endCF, i / steps))
		task.wait(1 / 30)
	end
end

-- ─── Process a log through the sawmill ───
local function processLog(sawmill, droppedLog)
	if sawmill:GetAttribute("SawmillState") ~= "idle" then return end

	-- Get the resource info before destroying
	local resType = droppedLog:GetAttribute("ResourceType")
	if resType ~= "Log" then return end

	sawmill:SetAttribute("SawmillState", "processing")

	-- Destroy the dropped log
	droppedLog:Destroy()

	local parts = getSawmillParts(sawmill)

	-- Notify clients to start spinning
	sawmillActionEvent:FireAllClients("startProcessing", sawmill)

	task.spawn(function()
		local placerPos = parts.hexagonPlacer and getPartPosition(parts.hexagonPlacer) or sawmill:GetPivot().Position
		local sawBladePos = parts.sawBlade and getPartPosition(parts.sawBlade) or sawmill:GetPivot().Position
		local claimerPos = parts.hexagonClaimer and getPartPosition(parts.hexagonClaimer) or sawmill:GetPivot().Position

		-- Raise above belt surface
		placerPos = placerPos + Vector3.new(0, 1.5, 0)
		sawBladePos = sawBladePos + Vector3.new(0, 1.5, 0)
		claimerPos = claimerPos + Vector3.new(0, 1.5, 0)

		-- Phase 1: Spawn log and slide to saw blade
		local logTemplate = rs:FindFirstChild("Log")
		if not logTemplate then
			sawmill:SetAttribute("SawmillState", "idle")
			sawmillActionEvent:FireAllClients("stopProcessing", sawmill)
			return
		end

		local logClone = logTemplate:Clone()
		logClone.Name = "SawmillLog"
		ensurePrimaryPart(logClone)
		logClone.Parent = workspace

		slideModel(logClone, placerPos, sawBladePos, SLIDE_TIME)

		-- Phase 2: Destroy log at saw, pause
		if logClone and logClone.Parent then
			logClone:Destroy()
		end
		task.wait(SAW_TIME)

		-- Phase 3: Spawn planks and slide to claimer
		local plankTemplate = rs:FindFirstChild("plank")
		if plankTemplate then
			local plankClone = plankTemplate:Clone()
			plankClone.Name = "SawmillPlank"
			ensurePrimaryPart(plankClone)
			plankClone.Parent = workspace

			slideModel(plankClone, sawBladePos, claimerPos, OUTPUT_TIME)

			-- Turn planks into a pickupable dropped item at the end
			if plankClone and plankClone.Parent then
				plankClone:SetAttribute("ResourceType", "Plank")
				plankClone:SetAttribute("ResourceAmount", PLANKS_PER_LOG)
				plankClone:SetAttribute("IsToolDrop", false)
				CollectionService:AddTag(plankClone, "DroppedItem")

				-- Unanchor so highlight/pickup works normally
				if plankClone:IsA("BasePart") then
					plankClone.Anchored = false
					plankClone:SetNetworkOwner(nil)
				end
				for _, p in plankClone:GetDescendants() do
					if p:IsA("BasePart") then
						p.Anchored = false
						p:SetNetworkOwner(nil)
					end
				end

				-- Auto-despawn after 2 minutes
				task.delay(120, function()
					if plankClone and plankClone.Parent then
						plankClone:Destroy()
					end
				end)
			end
		end

		sawmill:SetAttribute("SawmillState", "idle")
		sawmillActionEvent:FireAllClients("stopProcessing", sawmill)
	end)
end

-- ─── Check for dropped logs near sawmill placers ───
local function checkForLogsNearSawmills()
	for _, sawmill in CollectionService:GetTagged("Sawmill") do
		if sawmill:GetAttribute("SawmillState") ~= "idle" then continue end

		local parts = getSawmillParts(sawmill)
		if not parts.hexagonPlacer then continue end

		local placerPos = getPartPosition(parts.hexagonPlacer)

		-- Look for dropped logs near the placer
		for _, droppedItem in CollectionService:GetTagged("DroppedItem") do
			if not droppedItem or not droppedItem.Parent then continue end
			if droppedItem:GetAttribute("ResourceType") ~= "Log" then continue end

			local itemPos
			if droppedItem:IsA("Model") then
				itemPos = droppedItem:GetPivot().Position
			else
				itemPos = droppedItem.Position
			end

			if (itemPos - placerPos).Magnitude <= DETECT_RADIUS then
				processLog(sawmill, droppedItem)
				break -- one log at a time
			end
		end
	end
end

-- Poll for nearby logs every 0.5 seconds
task.spawn(function()
	while true do
		task.wait(0.5)
		checkForLogsNearSawmills()
	end
end)

-- ─── Place sawmill on raft (unchanged) ───
sawmillActionEvent.OnServerEvent:Connect(function(player, action, data)
	if action == "placeSawmill" then
		local char = player.Character
		if not char then return end
		local tool = char:FindFirstChildWhichIsA("Tool")
		if not tool or tool.Name ~= "Sawmill" then return end
		if typeof(data) ~= "CFrame" then return end

		local raft = getRaft()
		if not raft or not raft.PrimaryPart then return end

		local template = rs:FindFirstChild("Sawmill")
		if not template then return end

		local sawmill = template:Clone()
		sawmill.Name = "Sawmill"

		for _, desc in sawmill:GetDescendants() do
			if desc:IsA("Script") or desc:IsA("LocalScript") then
				desc:Destroy()
			end
		end

		if sawmill:IsA("Model") then
			local bbCF = sawmill:GetBoundingBox()
			sawmill.WorldPivot = CFrame.new(bbCF.Position)
		end

		local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(data)
		sawmill:PivotTo(worldCF)
		sawmill.Parent = raft
		weldToRaft(sawmill, raft)

		sawmill:SetAttribute("IsSawmill", true)
		sawmill:SetAttribute("SawmillState", "idle")
		CollectionService:AddTag(sawmill, "Sawmill")

		tool:Destroy()
	end
end)
