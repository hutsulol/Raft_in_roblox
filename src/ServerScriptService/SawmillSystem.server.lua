local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local rs = ReplicatedStorage

local sawmillActionEvent = Instance.new("RemoteEvent")
sawmillActionEvent.Name = "SawmillAction"
sawmillActionEvent.Parent = rs

-- Constants
local SLIDE_TIME = 5
local SAW_TIME = 1.5
local OUTPUT_TIME = 3
local PLANKS_PER_LOG = 2
local DETECT_RADIUS = 6

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

-- Names of parts that need to spin (client uses Motor6D Transform for visual spin)
local SPIN_PART_NAMES = { Hexagon = true, Hexagon_placer = true, Hexagon_claimer = true, SawBlade = true }

-- Track sawmills so each Heartbeat we can update their part CFrames relative to the raft.
-- Using anchored parts + manual CFrame updates eliminates ALL physics interaction
-- between the sawmill and the raft (no mass, no buoyancy, no joints, no drift).
local trackedSawmills = {}

local function attachToRaft(sawmill, raft)
	local raftPart = raft.PrimaryPart
	if not raftPart then return end

	local raftInverse = raftPart.CFrame:Inverse()
	local entries = {}

	for _, part in sawmill:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			-- Store the part's pose relative to the raft's PrimaryPart
			local relCF = raftInverse * part.CFrame
			table.insert(entries, { part = part, relCF = relCF })

			-- Spin parts still need a Motor6D so the client animation
			-- (motor.Transform = CFrame.Angles(...)) keeps working.
			if SPIN_PART_NAMES[part.Name] then
				local motor = Instance.new("Motor6D")
				motor.Name = "SpinMotor"
				motor.Part0 = part
				motor.Part1 = part
				motor.C0 = CFrame.new()
				motor.C1 = CFrame.new()
				motor.Parent = part
			end
		end
	end

	trackedSawmills[sawmill] = { raft = raft, entries = entries }
end

RunService.Heartbeat:Connect(function()
	for sawmill, data in trackedSawmills do
		if not sawmill.Parent or not data.raft.Parent or not data.raft.PrimaryPart then
			trackedSawmills[sawmill] = nil
		else
			local raftCF = data.raft.PrimaryPart.CFrame
			for _, entry in data.entries do
				if entry.part.Parent then
					entry.part.CFrame = raftCF * entry.relCF
				end
			end
		end
	end
end)

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

-- ─── Process a log through the sawmill ───
-- Server: handles inventory/state only, tells clients to animate visuals
local function processLog(sawmill, droppedLog)
	if sawmill:GetAttribute("SawmillState") ~= "idle" then return end

	local resType = droppedLog:GetAttribute("ResourceType")
	if resType ~= "Log" then return end

	local parts = getSawmillParts(sawmill)
	if not parts.hexagonPlacer or not parts.sawBlade or not parts.hexagonClaimer then return end

	-- Take only one log; return any extras to the dropper's inventory
	local stackAmount = droppedLog:GetAttribute("ResourceAmount") or 1
	if stackAmount > 1 then
		local dropperId = droppedLog:GetAttribute("DropperUserId")
		local dropper = dropperId and Players:GetPlayerByUserId(dropperId) or nil
		if dropper and _G.GetInventory then
			local inv = _G.GetInventory(dropper)
			if inv then
				inv["Log"] = (inv["Log"] or 0) + (stackAmount - 1)
				if _G.SendInventory then
					_G.SendInventory(dropper)
				end
			end
		end
	end

	sawmill:SetAttribute("SawmillState", "processing")
	droppedLog:Destroy()

	-- Tell clients to start visual animation (spinning + log/plank models)
	sawmillActionEvent:FireAllClients("startProcessing", sawmill)

	task.spawn(function()
		-- Wait for full animation: log slide + sawing + plank slide
		task.wait(SLIDE_TIME + SAW_TIME + OUTPUT_TIME)

		-- Spawn the final plank as a DroppedItem at the claimer position
		local plankTemplate = rs:FindFirstChild("plank")
		if plankTemplate and parts.hexagonClaimer and parts.hexagonClaimer.Parent then
			local plankClone = plankTemplate:Clone()
			plankClone.Name = "SawmillPlank"

			if plankClone:IsA("Model") and not plankClone.PrimaryPart then
				local first = plankClone:FindFirstChildWhichIsA("BasePart")
				if first then plankClone.PrimaryPart = first end
			end

			-- No collision, no touch, massless — pickup target welded to raft
			if plankClone:IsA("BasePart") then
				plankClone.Anchored = false
				plankClone.CanCollide = false
				plankClone.CanTouch = false
				plankClone.Massless = true
			end
			for _, p in plankClone:GetDescendants() do
				if p:IsA("BasePart") then
					p.Anchored = false
					p.CanCollide = false
					p.CanTouch = false
					p.Massless = true
				end
			end

			-- Place upright at claimer position
			local claimerPos = getPartPosition(parts.hexagonClaimer) + Vector3.new(0, 0.5, 0)
			plankClone:PivotTo(CFrame.new(claimerPos))
			plankClone.Parent = workspace

			-- Weld to raft so it stays in place as raft moves
			local raft = getRaft()
			if raft and raft.PrimaryPart then
				for _, p in plankClone:GetDescendants() do
					if p:IsA("BasePart") then
						local w = Instance.new("WeldConstraint")
						w.Part0 = p
						w.Part1 = raft.PrimaryPart
						w.Parent = p
					end
				end
				if plankClone:IsA("BasePart") then
					local w = Instance.new("WeldConstraint")
					w.Part0 = plankClone
					w.Part1 = raft.PrimaryPart
					w.Parent = plankClone
				end
			end

			plankClone:SetAttribute("ResourceType", "Plank")
			plankClone:SetAttribute("ResourceAmount", PLANKS_PER_LOG)
			plankClone:SetAttribute("IsToolDrop", false)
			CollectionService:AddTag(plankClone, "DroppedItem")

			task.delay(120, function()
				if plankClone and plankClone.Parent then
					plankClone:Destroy()
				end
			end)
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
			if (desc:IsA("Script") or desc:IsA("LocalScript")) and desc.Name ~= "BoilerSoundController" then
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
		attachToRaft(sawmill, raft)

		sawmill:SetAttribute("IsSawmill", true)
		sawmill:SetAttribute("SawmillState", "idle")
		CollectionService:AddTag(sawmill, "Sawmill")

		tool:Destroy()
	end
end)
