local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SPAWN_INTERVAL = 2.5
local MAX_RESOURCES = 15
local SPAWN_DISTANCE_MIN = 50
local SPAWN_DISTANCE_MAX = 120
local SPAWN_SPREAD = 50
local DRIFT_SPEED = 12
local PULL_SPEED = 35
local RESOURCE_LIFETIME = 30
local WATER_Y = 1
local BOBBING_AMPLITUDE = 0.3
local BOBBING_SPEED = 2

local boat = workspace:WaitForChild("Boat")
local primaryPart = boat.PrimaryPart

local pullEvent = Instance.new("RemoteEvent")
pullEvent.Name = "PullResource"
pullEvent.Parent = ReplicatedStorage

local templates = {}
for _, name in {"Log", "Wooden Barrel"} do
	local model = ReplicatedStorage:FindFirstChild(name)
	if model then
		table.insert(templates, model)
	end
end

local activeResources = {}
local spawnTimer = 0
local pullTargets = {}

local function setupPhysics(model)
	local root = nil
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = true
			if not root then
				root = part
			end
		end
	end

	if not model.PrimaryPart then
		model.PrimaryPart = root
	end

	return model.PrimaryPart
end

local function createResource()
	if #activeResources >= MAX_RESOURCES then
		return
	end

	if #templates == 0 then
		return
	end

	local template = templates[math.random(1, #templates)]
	local clone = template:Clone()

	local root = setupPhysics(clone)
	if not root then
		clone:Destroy()
		return
	end

	local boatCF = primaryPart.CFrame
	local lookFlat = Vector3.new(boatCF.LookVector.X, 0, boatCF.LookVector.Z)
	if lookFlat.Magnitude < 0.01 then
		lookFlat = Vector3.new(0, 0, -1)
	end
	lookFlat = lookFlat.Unit

	local rightFlat = Vector3.new(boatCF.RightVector.X, 0, boatCF.RightVector.Z)
	if rightFlat.Magnitude < 0.01 then
		rightFlat = Vector3.new(1, 0, 0)
	end
	rightFlat = rightFlat.Unit

	local forwardDist = SPAWN_DISTANCE_MIN + math.random() * (SPAWN_DISTANCE_MAX - SPAWN_DISTANCE_MIN)
	local sideDist = (math.random() - 0.5) * 2 * SPAWN_SPREAD

	local spawnPos = boatCF.Position + lookFlat * forwardDist + rightFlat * sideDist
	spawnPos = Vector3.new(spawnPos.X, WATER_Y, spawnPos.Z)

	clone:PivotTo(CFrame.new(spawnPos) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	clone.Parent = workspace

	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	table.insert(activeResources, {
		model = clone,
		root = root,
		spawnTime = tick(),
		bobbingOffset = math.random() * math.pi * 2,
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
	local now = tick()

	for i = #activeResources, 1, -1 do
		local data = activeResources[i]

		if not data.root or not data.root.Parent then
			cleanupResource(i)
			continue
		end

		if now - data.spawnTime > RESOURCE_LIFETIME then
			cleanupResource(i)
			continue
		end

		local resourcePos = data.root.Position
		local toBoat = boatPos - resourcePos
		local flatToBoat = Vector3.new(toBoat.X, 0, toBoat.Z)
		local dist = flatToBoat.Magnitude

		if dist < 6 then
			cleanupResource(i)
			continue
		end

		local targetSpeed = DRIFT_SPEED
		local targetPos = boatPos

		local puller = pullTargets[data.model]
		if puller and puller.Character and puller.Character:FindFirstChild("HumanoidRootPart") then
			targetPos = puller.Character.HumanoidRootPart.Position
			targetSpeed = PULL_SPEED
		else
			pullTargets[data.model] = nil
		end

		local toTarget = targetPos - resourcePos
		local flatDir = Vector3.new(toTarget.X, 0, toTarget.Z)
		if flatDir.Magnitude > 0.1 then
			flatDir = flatDir.Unit
		end

		local bobY = WATER_Y + math.sin(now * BOBBING_SPEED + data.bobbingOffset) * BOBBING_AMPLITUDE
		local yCorrection = (bobY - resourcePos.Y) * 5

		data.root.AssemblyLinearVelocity = flatDir * targetSpeed + Vector3.new(0, yCorrection, 0)
		data.root.AssemblyAngularVelocity = Vector3.new(0, 0.3, 0)
	end
end)
