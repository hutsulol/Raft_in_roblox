local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SPAWN_INTERVAL = 2
local MAX_RESOURCES = 20
local SPAWN_DISTANCE_MIN = 80
local SPAWN_DISTANCE_MAX = 140
local SPAWN_SPREAD = 60
local DRIFT_FORCE = 300
local DRIFT_VARIATION = 0.3
local PULL_FORCE = 1500
local RESOURCE_LIFETIME = 30
local WATER_LEVEL = 0

local boat = workspace:WaitForChild("Model")
local primaryPart = boat.PrimaryPart

local pullEvent = Instance.new("RemoteEvent")
pullEvent.Name = "PullResource"
pullEvent.Parent = ReplicatedStorage

local templates = {
	ReplicatedStorage:WaitForChild("Log"),
	ReplicatedStorage:WaitForChild("WoodenBarrel"),
}

local activeResources = {}
local spawnTimer = 0
local pullTargets = {}

local function createResource()
	if #activeResources >= MAX_RESOURCES then
		return
	end

	local template = templates[math.random(1, #templates)]
	local clone = template:Clone()

	local boatCF = primaryPart.CFrame
	local lookVector = boatCF.LookVector
	local rightVector = boatCF.RightVector

	local forwardDist = math.random(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX)
	local sideDist = (math.random() - 0.5) * 2 * SPAWN_SPREAD

	local spawnPos = boatCF.Position
		+ Vector3.new(lookVector.X, 0, lookVector.Z).Unit * forwardDist
		+ Vector3.new(rightVector.X, 0, rightVector.Z).Unit * sideDist
		+ Vector3.new(0, WATER_LEVEL, 0)

	clone:PivotTo(CFrame.new(spawnPos) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	clone.Parent = workspace

	local root = clone.PrimaryPart
	if not root then
		clone:Destroy()
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Parent = root

	local vectorForce = Instance.new("VectorForce")
	vectorForce.Name = "DriftForce"
	vectorForce.Attachment0 = attachment
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.Force = Vector3.new(0, 0, 0)
	vectorForce.Parent = root

	local alignPos = Instance.new("AlignPosition")
	alignPos.Name = "PullForce"
	alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPos.Attachment0 = attachment
	alignPos.MaxForce = 0
	alignPos.MaxVelocity = 40
	alignPos.Responsiveness = 15
	alignPos.Parent = root

	local variationAngle = (math.random() - 0.5) * 2 * DRIFT_VARIATION

	table.insert(activeResources, {
		model = clone,
		root = root,
		vectorForce = vectorForce,
		alignPos = alignPos,
		variationAngle = variationAngle,
		spawnTime = tick(),
	})
end

local function cleanupResource(index)
	local data = activeResources[index]
	if data.model and data.model.Parent then
		data.model:Destroy()
	end
	pullTargets[data.model] = nil
	table.remove(activeResources, index)
end

pullEvent.OnServerEvent:Connect(function(player, resourceModel, pulling)
	if typeof(resourceModel) ~= "Instance" or not resourceModel:IsA("Model") then
		return
	end
	if not resourceModel:IsDescendantOf(workspace) then
		return
	end

	local found = false
	for _, data in activeResources do
		if data.model == resourceModel then
			found = true
			break
		end
	end
	if not found then
		return
	end

	if pulling then
		pullTargets[resourceModel] = player
	else
		if pullTargets[resourceModel] == player then
			pullTargets[resourceModel] = nil
		end
	end
end)

RunService.Heartbeat:Connect(function(dt)
	if not primaryPart or not primaryPart.Parent then
		return
	end

	spawnTimer = spawnTimer + dt
	if spawnTimer >= SPAWN_INTERVAL then
		spawnTimer = 0
		createResource()
	end

	local boatPos = primaryPart.Position

	for i = #activeResources, 1, -1 do
		local data = activeResources[i]

		if not data.root or not data.root.Parent then
			cleanupResource(i)
			continue
		end

		if tick() - data.spawnTime > RESOURCE_LIFETIME then
			cleanupResource(i)
			continue
		end

		local resourcePos = data.root.Position
		local toBoat = boatPos - resourcePos
		local flatToBoat = Vector3.new(toBoat.X, 0, toBoat.Z)
		local dist = flatToBoat.Magnitude

		if dist < 5 then
			cleanupResource(i)
			continue
		end

		local puller = pullTargets[data.model]
		if puller and puller.Character and puller.Character:FindFirstChild("HumanoidRootPart") then
			local playerPos = puller.Character.HumanoidRootPart.Position
			data.alignPos.Position = playerPos
			data.alignPos.MaxForce = PULL_FORCE
			data.vectorForce.Force = Vector3.new(0, 0, 0)
		else
			pullTargets[data.model] = nil
			data.alignPos.MaxForce = 0

			local driftDir = flatToBoat.Unit
			local angle = math.atan2(driftDir.Z, driftDir.X) + data.variationAngle
			local variedDir = Vector3.new(math.cos(angle), 0, math.sin(angle))

			data.vectorForce.Force = variedDir * DRIFT_FORCE
		end
	end
end)
