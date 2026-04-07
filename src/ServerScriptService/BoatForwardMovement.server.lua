local SPEED = 25
local FORCE_PER_MASS = 33 -- force scales with total raft mass
local PADDLE_BOOST = 6 -- small extra push from a paddle stroke
local PADDLE_DECAY = 1.5 -- seconds for paddle boost to decay
local PADDLE_COURSE_NUDGE = math.rad(3) -- max course rotation per paddle stroke

-- ─── Ocean current ───
local CURRENT_INTERVAL = 120 -- seconds between random current changes
local TURN_SPEED = 0.25 -- radians/sec the raft rotates to face the current

-- Model has a -45° offset between its LookVector and its visible front.
local MODEL_FRONT_OFFSET = math.rad(-45)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local boat = workspace:WaitForChild("Raft")
while not boat.PrimaryPart do
	task.wait(0.1)
end

local primaryPart = boat.PrimaryPart

-- Preserve initial pitch/roll (from the sideways-log PrimaryPart orientation)
local initialPitch, initialYaw, initialRoll = primaryPart.CFrame:ToEulerAnglesYXZ()
local lockedYaw = initialYaw

-- Store the rest CFrame (used by BuildingSystem for stable placement)
local restY = primaryPart.Position.Y
primaryPart:SetAttribute("RestCFrame", primaryPart.CFrame)
primaryPart:SetAttribute("RestYaw", lockedYaw)

-- RemoteEvents
local paddleEvent = Instance.new("RemoteEvent")
paddleEvent.Name = "PaddleAction"
paddleEvent.Parent = ReplicatedStorage

local currentEvent = Instance.new("RemoteEvent")
currentEvent.Name = "OceanCurrentChanged"
currentEvent.Parent = ReplicatedStorage

local attachment = Instance.new("Attachment")
attachment.Parent = primaryPart

local vectorForce = Instance.new("VectorForce")
vectorForce.Attachment0 = attachment
vectorForce.ApplyAtCenterOfMass = true
vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
vectorForce.Force = Vector3.new(0, 0, 0)
vectorForce.Parent = primaryPart

local alignOrientation = Instance.new("AlignOrientation")
alignOrientation.Attachment0 = attachment
alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
alignOrientation.RigidityEnabled = false
alignOrientation.MaxTorque = 500000
alignOrientation.Responsiveness = 5
alignOrientation.Parent = primaryPart

-- ─── Direction helpers ───

-- Compute the visible "front" direction of the raft for a given yaw.
-- This is the direction the bow points (and where the raft should move).
local function computeVisualFront(yaw)
	local cf = CFrame.fromEulerAnglesYXZ(initialPitch, yaw, initialRoll)
	local lv = cf.LookVector
	local flat = Vector3.new(-lv.X, 0, -lv.Z)
	if flat.Magnitude < 0.001 then
		return Vector3.new(0, 0, -1)
	end
	flat = flat.Unit
	local cosA = math.cos(MODEL_FRONT_OFFSET)
	local sinA = math.sin(MODEL_FRONT_OFFSET)
	return Vector3.new(
		flat.X * cosA + flat.Z * sinA,
		0,
		-flat.X * sinA + flat.Z * cosA
	).Unit
end

-- Inverse of computeVisualFront: yaw such that the raft's bow points along `dir`.
-- Derived from: visualFront(y) = ((sin(y)-cos(y))/√2, 0, (sin(y)+cos(y))/√2)
local function yawFromVisualFront(dir)
	return math.atan2(dir.X + dir.Z, dir.Z - dir.X)
end

local function randomHorizontalDirection()
	local angle = math.random() * math.pi * 2
	return Vector3.new(math.sin(angle), 0, math.cos(angle))
end

-- ─── Ocean current state ───
local currentDirection = computeVisualFront(lockedYaw) -- start matching the raft's current heading

local function broadcastCurrent()
	currentEvent:FireAllClients(currentDirection)
end

task.spawn(function()
	while true do
		task.wait(CURRENT_INTERVAL)
		currentDirection = randomHorizontalDirection()
		broadcastCurrent()
		print(string.format("[OceanCurrent] New direction (%.2f, %.2f)", currentDirection.X, currentDirection.Z))
	end
end)

-- Re-broadcast on player join
Players.PlayerAdded:Connect(function(plr)
	task.wait(2)
	currentEvent:FireClient(plr, currentDirection)
end)

-- ─── Paddle state ───
local paddleBoostRemaining = 0
local paddleDirection = Vector3.zero

paddleEvent.OnServerEvent:Connect(function(player, direction)
	if typeof(direction) ~= "Vector3" then return end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.5 then return end
	paddleDirection = flat.Unit
	paddleBoostRemaining = PADDLE_DECAY

	-- Apply a tiny rotation to the current direction toward where the player paddled.
	-- This is the only way the player can influence the course, and it's intentionally minimal.
	local curAngle = math.atan2(currentDirection.X, currentDirection.Z)
	local pAngle = math.atan2(paddleDirection.X, paddleDirection.Z)
	local diff = math.atan2(math.sin(pAngle - curAngle), math.cos(pAngle - curAngle))
	local nudge = math.clamp(diff, -PADDLE_COURSE_NUDGE, PADDLE_COURSE_NUDGE)
	local cosA = math.cos(nudge)
	local sinA = math.sin(nudge)
	currentDirection = Vector3.new(
		currentDirection.X * cosA + currentDirection.Z * sinA,
		0,
		-currentDirection.X * sinA + currentDirection.Z * cosA
	).Unit
	broadcastCurrent()
end)

-- Initial broadcast after a brief delay so clients can subscribe
task.delay(2, broadcastCurrent)

local forwardDirection = computeVisualFront(lockedYaw)

RunService.Heartbeat:Connect(function(dt)
	if not primaryPart or not primaryPart.Parent then
		return
	end

	-- Steer locked yaw toward the yaw that points the bow at the current direction
	local desiredYaw = yawFromVisualFront(currentDirection)
	local diff = desiredYaw - lockedYaw
	diff = math.atan2(math.sin(diff), math.cos(diff))
	local step = TURN_SPEED * dt
	if math.abs(diff) <= step then
		lockedYaw = desiredYaw
	else
		lockedYaw = lockedYaw + math.sign(diff) * step
	end

	-- Forward force is always along the bow's current visual front,
	-- so the raft front always leads (no sideways drifting).
	forwardDirection = computeVisualFront(lockedYaw)

	local currentVelocity = primaryPart.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	-- Use velocity component along forward, not magnitude, so cross-currents don't kill thrust
	local forwardSpeed = flatVelocity:Dot(forwardDirection)
	local forceFactor = math.clamp(1 - (forwardSpeed / SPEED), 0, 1)

	local totalMass = primaryPart.AssemblyMass
	local baseForce = forwardDirection * FORCE_PER_MASS * totalMass * forceFactor

	-- Paddle: small forward boost only (course is influenced via the nudge above)
	local paddleForce = Vector3.zero
	if paddleBoostRemaining > 0 then
		local boostFactor = paddleBoostRemaining / PADDLE_DECAY
		paddleForce = forwardDirection * PADDLE_BOOST * totalMass * boostFactor
		paddleBoostRemaining = math.max(0, paddleBoostRemaining - dt)
	end

	vectorForce.Force = baseForce + paddleForce

	-- Scale torque with raft mass so it always rotates, even with many tiles
	alignOrientation.MaxTorque = totalMass * 500
	alignOrientation.CFrame = CFrame.fromEulerAnglesYXZ(initialPitch, lockedYaw, initialRoll)

	-- Update RestCFrame so building systems use the current yaw
	local pos = primaryPart.Position
	primaryPart:SetAttribute("RestCFrame", CFrame.new(pos.X, restY, pos.Z) * CFrame.fromEulerAnglesYXZ(initialPitch, lockedYaw, initialRoll))
	primaryPart:SetAttribute("RestYaw", lockedYaw)
end)
