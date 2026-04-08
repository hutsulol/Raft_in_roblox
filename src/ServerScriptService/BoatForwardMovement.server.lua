local SPEED = 25
local PADDLE_BOOST = 5 -- extra m/s added to base speed during a paddle stroke
local PADDLE_DECAY = 1.5 -- seconds for paddle boost to decay
local PADDLE_COURSE_NUDGE = math.rad(3) -- max course rotation per paddle stroke

-- Strength of the velocity correction. Higher = the raft locks onto its
-- bow-aligned target velocity faster (kills sideways drift more aggressively).
local VELOCITY_GAIN = 6

-- ─── Ocean current ───
local CURRENT_INTERVAL = 120 -- seconds between random current changes
local TURN_SPEED = 0.35 -- radians/sec the raft rotates to face the current

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

-- The raft's PrimaryPart is oriented so that its LookVector points along the
-- visible bow of the model. For a CFrame built with Euler order YXZ, the
-- horizontal projection of the LookVector at yaw Y is always (-sin Y, 0, -cos Y),
-- regardless of pitch and roll — so we don't need to rebuild the CFrame here.
local function computeVisualFront(yaw)
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

-- Inverse: yaw such that computeVisualFront(yaw) == dir.
local function yawFromVisualFront(dir)
	return math.atan2(-dir.X, -dir.Z)
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

	-- The raft moves along its current bow direction. The bow rotates smoothly
	-- toward the ocean current (above), so during a turn the velocity simply
	-- arcs along with the bow — the raft can never end up moving sideways or
	-- backwards relative to its front.
	forwardDirection = computeVisualFront(lockedYaw)

	local totalMass = primaryPart.AssemblyMass
	local currentVelocity = primaryPart.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)

	-- Target velocity: constant SPEED along the bow.
	local targetSpeed = SPEED
	if paddleBoostRemaining > 0 then
		targetSpeed = targetSpeed + PADDLE_BOOST * (paddleBoostRemaining / PADDLE_DECAY)
		paddleBoostRemaining = math.max(0, paddleBoostRemaining - dt)
	end
	local desiredVelocity = forwardDirection * targetSpeed

	-- Velocity correction force. This simultaneously:
	--   • kills any lateral velocity (sideways drift)
	--   • kills any backwards velocity
	--   • holds forward speed constant at SPEED regardless of turning
	local velocityError = desiredVelocity - flatVelocity
	vectorForce.Force = velocityError * totalMass * VELOCITY_GAIN

	-- Scale torque with raft mass so it always rotates, even with many tiles
	alignOrientation.MaxTorque = totalMass * 500
	alignOrientation.CFrame = CFrame.fromEulerAnglesYXZ(initialPitch, lockedYaw, initialRoll)

	-- Update RestCFrame so building systems use the current yaw
	local pos = primaryPart.Position
	primaryPart:SetAttribute("RestCFrame", CFrame.new(pos.X, restY, pos.Z) * CFrame.fromEulerAnglesYXZ(initialPitch, lockedYaw, initialRoll))
	primaryPart:SetAttribute("RestYaw", lockedYaw)
end)
