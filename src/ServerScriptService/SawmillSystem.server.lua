local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")

local rs = ReplicatedStorage

-- Create a collision group for sawmill belt items that collides with nothing
PhysicsService:RegisterCollisionGroup("SawmillBelt")
PhysicsService:CollisionGroupSetCollidable("SawmillBelt", "Default", false)
PhysicsService:CollisionGroupSetCollidable("SawmillBelt", "SawmillBelt", false)

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

-- Names of parts that need to spin (use Motor6D so client can rotate via C0)
local SPIN_PART_NAMES = { Hexagon = true, Hexagon_placer = true, Hexagon_claimer = true, SawBlade = true }

local function weldToRaft(obj, raft)
	local raftPart = raft.PrimaryPart
	for _, part in obj:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			if SPIN_PART_NAMES[part.Name] then
				-- Use Motor6D so the client can spin via Transform/C0
				local motor = Instance.new("Motor6D")
				motor.Name = "SpinMotor"
				motor.Part0 = raftPart
				motor.Part1 = part
				motor.C0 = raftPart.CFrame:Inverse() * part.CFrame
				motor.C1 = CFrame.new()
				motor.Parent = part
			else
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raftPart
				weld.Parent = part
			end
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

-- Fully neutralize physics on a clone: anchor, no collision, no mass, separate collision group
local function disablePhysics(model)
	if model:IsA("BasePart") then
		model.Anchored = true
		model.CanCollide = false
		model.CanTouch = false
		model.CanQuery = false
		model.Massless = true
		model.CollisionGroup = "SawmillBelt"
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = true
			p.CollisionGroup = "SawmillBelt"
		end
	end
end

-- Animate a model sliding between two sawmill parts (reads positions live each frame)
-- startPart/endPart: the actual BaseParts to interpolate between
-- sawmill: used to get the belt orientation
local function slideModel(model, startPart, endPart, duration, sawmill)
	if not model or not model.Parent then return end

	-- Ensure anchored + no collision
	disablePhysics(model)

	local steps = math.max(1, math.ceil(duration * 30))
	for i = 0, steps do
		if not model or not model.Parent then return end
		if not startPart or not startPart.Parent then return end
		if not endPart or not endPart.Parent then return end

		local t = i / steps

		-- Read current world positions each frame (follows raft movement)
		local startPos = getPartPosition(startPart) + Vector3.new(0, 1.5, 0)
		local endPos = getPartPosition(endPart) + Vector3.new(0, 1.5, 0)
		local worldPos = startPos:Lerp(endPos, t)

		-- Get belt direction from sawmill's current orientation
		local beltDir = sawmill:GetPivot().RightVector
		beltDir = Vector3.new(beltDir.X, 0, beltDir.Z)
		if beltDir.Magnitude < 0.01 then beltDir = Vector3.new(1, 0, 0) end
		beltDir = beltDir.Unit

		-- Orient log: face along belt, then roll 90° on Z so it lies sideways
		local orientCF = CFrame.lookAt(worldPos, worldPos + beltDir) * CFrame.Angles(0, 0, math.rad(90))

		model:PivotTo(orientCF)

		if i < steps then
			task.wait(1 / 30)
		end
	end
end

-- ─── Process a log through the sawmill ───
local function processLog(sawmill, droppedLog)
	if sawmill:GetAttribute("SawmillState") ~= "idle" then return end

	local resType = droppedLog:GetAttribute("ResourceType")
	if resType ~= "Log" then return end

	sawmill:SetAttribute("SawmillState", "processing")

	-- Destroy the dropped log immediately
	droppedLog:Destroy()

	local parts = getSawmillParts(sawmill)

	-- Notify clients to start spinning
	sawmillActionEvent:FireAllClients("startProcessing", sawmill)

	task.spawn(function()
		if not parts.hexagonPlacer or not parts.sawBlade or not parts.hexagonClaimer then
			sawmill:SetAttribute("SawmillState", "idle")
			sawmillActionEvent:FireAllClients("stopProcessing", sawmill)
			return
		end

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
		disablePhysics(logClone)
		logClone.Parent = workspace

		slideModel(logClone, parts.hexagonPlacer, parts.sawBlade, SLIDE_TIME, sawmill)

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
			disablePhysics(plankClone)
			plankClone.Parent = workspace

			slideModel(plankClone, parts.sawBlade, parts.hexagonClaimer, OUTPUT_TIME, sawmill)

			-- Turn planks into a pickupable dropped item
			if plankClone and plankClone.Parent then
				-- Re-enable CanQuery so pickup raycast can detect it
				if plankClone:IsA("BasePart") then plankClone.CanQuery = true end
				for _, p in plankClone:GetDescendants() do
					if p:IsA("BasePart") then p.CanQuery = true end
				end
				plankClone:SetAttribute("ResourceType", "Plank")
				plankClone:SetAttribute("ResourceAmount", PLANKS_PER_LOG)
				plankClone:SetAttribute("IsToolDrop", false)
				CollectionService:AddTag(plankClone, "DroppedItem")

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
				break
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

-- ─── Place sawmill on raft ───
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
