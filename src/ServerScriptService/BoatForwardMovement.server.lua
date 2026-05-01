local SPEED = 27
local PADDLE_BOOST = 6
local PADDLE_DECAY = 1.3
local PADDLE_COURSE_NUDGE = math.rad(4)

local SURGE_ACCEL = 4.8
local WATER_DRAG = 1.9
local LATERAL_DRAG = 5.2
local ANGULAR_DAMPING = 2.6

local BUOYANCY_STIFFNESS = 56
local BUOYANCY_DAMPING = 15
local WATERLINE_OFFSET = -0.7
local BOB_AMPLITUDE = 0.35
local BOB_FREQUENCY = 0.45
local ROLL_AMPLITUDE = math.rad(2.2)
local PITCH_AMPLITUDE = math.rad(0.8)
local WAVE_RESPONSIVENESS = 4.2

local WIND_START_DAY = 6
local WIND_INTERVAL = 2 * (300 + 120)
local WIND_DURATION = 15
local WIND_PLAYER_ACCEL = 400
local WIND_AIRBORNE_ACCEL = 30
local WIND_SHELTER_DISTANCE = 50
local WIND_SHELTER_BOX_SIZE = Vector3.new(3, 5, 3)
local TURN_SPEED = 0.6

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local boat = workspace:WaitForChild("Raft")
while not boat.PrimaryPart do task.wait(0.1) end
local primaryPart = boat.PrimaryPart

local baseWaterY = primaryPart.Position.Y + WATERLINE_OFFSET
local wavePhase = math.random() * math.pi * 2
local waveClock = 0

local function ensureGroup(name)
	pcall(function() PhysicsService:RegisterCollisionGroup(name) end)
end
ensureGroup("Raft")
ensureGroup("FloatingResource")
pcall(function() PhysicsService:CollisionGroupSetCollidable("Raft", "FloatingResource", false) end)

local RESOURCE_NAME_HINTS = {
	["log"] = true,
	["leaf"] = true,
	["plastic"] = true,
	["resource"] = true,
}

local function isFloatingResourcePart(part)
	if not part or not part:IsA("BasePart") then return false end
	if part:GetAttribute("IsFloatingResource") == true then return true end
	local current = part
	while current and current ~= workspace do
		local n = string.lower(current.Name)
		for hint in pairs(RESOURCE_NAME_HINTS) do
			if string.find(n, hint, 1, true) then
				return true
			end
		end
		if current:GetAttribute("IsFloatingResource") == true then return true end
		current = current.Parent
	end
	return false
end

local function isRobotPart(part)
	local current = part
	while current and current ~= boat do
		if current.Name == "Robot" then return true end
		current = current.Parent
	end
	return false
end

local function isDecorativeRaftPart(part)
	local current = part
	while current and current ~= boat do
		if current.Name == "CommunityBoard" or current.Name == "Robot" then
			return true
		end
		current = current.Parent
	end
	return false
end

local function tagRaftPart(part)
	if part and part:IsA("BasePart") then
		part.CollisionGroup = "Raft"
		if isDecorativeRaftPart(part) then
			part.Massless = true
			part.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0.3, 0.5)
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = true
			if isRobotPart(part) then
				part.CanTouch = true
			end
		end
		task.defer(function()
			if part.Parent and not part.Anchored then
				pcall(function() part:SetNetworkOwner(nil) end)
			end
		end)
	end
end

local function tagFloatingResourcePart(part)
	if part and part:IsA("BasePart") then
		part.CollisionGroup = "FloatingResource"
	end
end

for _, desc in boat:GetDescendants() do
	if desc:IsA("BasePart") then
		desc.Anchored = false
		tagRaftPart(desc)
		pcall(function() desc:SetNetworkOwner(nil) end)
	end
end

task.defer(function()
	for _, desc in workspace:GetDescendants() do
		if desc:IsA("BasePart") and isFloatingResourcePart(desc) then
			tagFloatingResourcePart(desc)
		end
	end
end)

primaryPart.Anchored = false
tagRaftPart(primaryPart)

boat.DescendantAdded:Connect(function(d)
	if d:IsA("BasePart") then tagRaftPart(d) end
end)
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("BasePart") and isFloatingResourcePart(d) then
		tagFloatingResourcePart(d)
	end
end)

pcall(function() primaryPart:SetNetworkOwner(nil) end)

local initialRotation = primaryPart.CFrame.Rotation
local _, initialYaw, _ = primaryPart.CFrame:ToEulerAnglesYXZ()
local lockedYaw = initialYaw
primaryPart:SetAttribute("RestCFrame", primaryPart.CFrame)
primaryPart:SetAttribute("RestYaw", lockedYaw)

local paddleEvent = Instance.new("RemoteEvent")
paddleEvent.Name = "PaddleAction"
paddleEvent.Parent = ReplicatedStorage

local currentEvent = Instance.new("RemoteEvent")
currentEvent.Name = "OceanCurrentChanged"
currentEvent.Parent = ReplicatedStorage

local windEvent = Instance.new("RemoteEvent")
windEvent.Name = "WindUpdate"
windEvent.Parent = ReplicatedStorage

local attachment = Instance.new("Attachment")
attachment.Parent = primaryPart

local vectorForce = Instance.new("VectorForce")
vectorForce.Attachment0 = attachment
vectorForce.ApplyAtCenterOfMass = true
vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
vectorForce.Parent = primaryPart

local alignOrientation = Instance.new("AlignOrientation")
alignOrientation.Attachment0 = attachment
alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
alignOrientation.RigidityEnabled = false
alignOrientation.MaxTorque = 500000
alignOrientation.Responsiveness = 7
alignOrientation.Parent = primaryPart

local function computeVisualFront(yaw)
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end
local function yawFromVisualFront(dir)
	return math.atan2(-dir.X, -dir.Z)
end
local function randomHorizontalDirection()
	local angle = math.random() * math.pi * 2
	return Vector3.new(math.sin(angle), 0, math.cos(angle))
end

local currentDirection = computeVisualFront(lockedYaw)
local function broadcastCurrent() currentEvent:FireAllClients(currentDirection) end

local windActive, windRemainingTime = false, 0
local windDirection = Vector3.new(0,0,-1)
local affectedPlayers = {}

local function startWindEvent()
	windDirection = randomHorizontalDirection()
	currentDirection = windDirection
	windActive = true
	windRemainingTime = WIND_DURATION
	for _, p in Players:GetPlayers() do p:SetAttribute("WindActive", true) end
	windEvent:FireAllClients(true, WIND_DURATION, WIND_DURATION, windDirection)
	broadcastCurrent()
end

local function detachWindForce(plr)
	local data = affectedPlayers[plr]
	if not data then return end
	if data.force then data.force:Destroy() end
	if data.attach then data.attach:Destroy() end
	affectedPlayers[plr] = nil
end

local function attachWindForce(plr, hrp)
	if affectedPlayers[plr] then return end
	local attach = Instance.new("Attachment", hrp)
	local force = Instance.new("VectorForce")
	force.Attachment0 = attach
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = windDirection * hrp.AssemblyMass * WIND_PLAYER_ACCEL
	force.Parent = hrp
	affectedPlayers[plr] = {force = force, attach = attach, hrp = hrp}
end

local shelterRayParams = RaycastParams.new()
shelterRayParams.FilterType = Enum.RaycastFilterType.Exclude
local function isShelteredFromWind(hrp, char)
	shelterRayParams.FilterDescendantsInstances = {char}
	return workspace:Blockcast(CFrame.new(hrp.Position), WIND_SHELTER_BOX_SIZE, -windDirection * WIND_SHELTER_DISTANCE, shelterRayParams) ~= nil
end

local function updateWindForces()
	for plr, data in pairs(affectedPlayers) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = data.hrp
		if hum and hrp and data.force and data.force.Parent then
			if isShelteredFromWind(hrp, char) then
				data.force.Force = Vector3.zero
			else
				local accel = hum.FloorMaterial == Enum.Material.Air and WIND_AIRBORNE_ACCEL or WIND_PLAYER_ACCEL
				data.force.Force = windDirection * hrp.AssemblyMass * accel
			end
		end
	end
end

local function endWindEvent()
	windActive = false
	windRemainingTime = 0
	for p in pairs(affectedPlayers) do detachWindForce(p) end
	for _, p in Players:GetPlayers() do p:SetAttribute("WindActive", false) end
	windEvent:FireAllClients(false, 0, WIND_DURATION, windDirection)
end

task.spawn(function()
	local dayCount = ReplicatedStorage:WaitForChild("DayCount")
	while dayCount.Value < WIND_START_DAY do dayCount:GetPropertyChangedSignal("Value"):Wait() end
	while true do startWindEvent(); task.wait(WIND_INTERVAL) end
end)

Players.PlayerAdded:Connect(function(plr)
	task.wait(2)
	currentEvent:FireClient(plr, currentDirection)
	if windActive then
		plr:SetAttribute("WindActive", true)
		windEvent:FireClient(plr, true, windRemainingTime, WIND_DURATION, windDirection)
	end
end)

local windRayParams = RaycastParams.new()
windRayParams.FilterType = Enum.RaycastFilterType.Include
windRayParams.FilterDescendantsInstances = {boat}

local paddleBoostRemaining = 0
paddleEvent.OnServerEvent:Connect(function(_, direction)
	if typeof(direction) ~= "Vector3" then return end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.5 then return end
	paddleBoostRemaining = PADDLE_DECAY
	local pDir = flat.Unit
	local curAngle = math.atan2(currentDirection.X, currentDirection.Z)
	local pAngle = math.atan2(pDir.X, pDir.Z)
	local diff = math.atan2(math.sin(pAngle - curAngle), math.cos(pAngle - curAngle))
	local nudge = math.clamp(diff, -PADDLE_COURSE_NUDGE, PADDLE_COURSE_NUDGE)
	local cosA, sinA = math.cos(nudge), math.sin(nudge)
	currentDirection = Vector3.new(currentDirection.X * cosA + currentDirection.Z * sinA, 0, -currentDirection.X * sinA + currentDirection.Z * cosA).Unit
	broadcastCurrent()
end)

local forwardDirection = computeVisualFront(lockedYaw)
task.delay(2, broadcastCurrent)

RunService.Heartbeat:Connect(function(dt)
	if not primaryPart or not primaryPart.Parent then return end
	waveClock += dt

	local desiredYaw = yawFromVisualFront(currentDirection)
	local yawDiff = math.atan2(math.sin(desiredYaw - lockedYaw), math.cos(desiredYaw - lockedYaw))
	local yawStep = TURN_SPEED * dt
	lockedYaw = math.abs(yawDiff) <= yawStep and desiredYaw or (lockedYaw + math.sign(yawDiff) * yawStep)
	forwardDirection = computeVisualFront(lockedYaw)

	local mass = primaryPart.AssemblyMass
	local velocity = primaryPart.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local forwardSpeed = flatVelocity:Dot(forwardDirection)
	local sideways = flatVelocity - forwardDirection * forwardSpeed

	local targetSpeed = SPEED
	if paddleBoostRemaining > 0 then
		targetSpeed += PADDLE_BOOST * (paddleBoostRemaining / PADDLE_DECAY)
		paddleBoostRemaining = math.max(0, paddleBoostRemaining - dt)
	end
	local anchorDepth = boat:GetAttribute("AnchorDepth") or 0
	if anchorDepth > 0.7 then
		local brake = math.clamp((anchorDepth - 0.7) / 0.3, 0, 1)
		targetSpeed *= (1 - brake)
	end

	local surgeForce = forwardDirection * ((targetSpeed - forwardSpeed) * mass * SURGE_ACCEL)
	local dragForce = (-flatVelocity * WATER_DRAG - sideways * LATERAL_DRAG) * mass

	local wave = math.sin(waveClock * BOB_FREQUENCY * math.pi * 2 + wavePhase)
	local targetWaterY = baseWaterY + wave * BOB_AMPLITUDE
	local yError = targetWaterY - primaryPart.Position.Y
	local buoyancyForce = mass * workspace.Gravity + (yError * BUOYANCY_STIFFNESS - velocity.Y * BUOYANCY_DAMPING) * mass

	vectorForce.Force = Vector3.new(surgeForce.X + dragForce.X, buoyancyForce, surgeForce.Z + dragForce.Z)

	local right = forwardDirection:Cross(Vector3.yAxis)
	if right.Magnitude < 0.001 then right = Vector3.xAxis else right = right.Unit end
	local rollAngle = wave * ROLL_AMPLITUDE + math.clamp(sideways:Dot(right) / 20, -0.08, 0.08)
	local pitchAngle = math.sin((waveClock * BOB_FREQUENCY * 1.2) * math.pi * 2 + wavePhase * 0.4) * PITCH_AMPLITUDE
	local yawDelta = lockedYaw - initialYaw
	local targetRotation = CFrame.Angles(0, yawDelta, 0) * initialRotation * CFrame.Angles(pitchAngle, 0, rollAngle)
	alignOrientation.Responsiveness = WAVE_RESPONSIVENESS
	alignOrientation.MaxTorque = mass * 900
	alignOrientation.CFrame = targetRotation

	local w = primaryPart.AssemblyAngularVelocity
	primaryPart.AssemblyAngularVelocity = Vector3.new(w.X * (1 - math.clamp(ANGULAR_DAMPING * dt, 0, 0.95)), w.Y, w.Z * (1 - math.clamp(ANGULAR_DAMPING * dt, 0, 0.95)))

	local pos = primaryPart.Position
	local restRotation = CFrame.Angles(0, yawDelta, 0) * initialRotation
	primaryPart:SetAttribute("RestCFrame", CFrame.new(pos) * restRotation)
	primaryPart:SetAttribute("RestYaw", lockedYaw)

	if windActive then
		windRemainingTime = math.max(0, windRemainingTime - dt)
		for _, plr in Players:GetPlayers() do
			local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if hrp and workspace:Raycast(hrp.Position, Vector3.new(0, -8, 0), windRayParams) then attachWindForce(plr, hrp) end
		end
		updateWindForces()
		if windRemainingTime <= 0 then endWindEvent() end
	end
end)

Players.PlayerRemoving:Connect(detachWindForce)
