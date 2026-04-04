local SPEED = 25
local FORCE_PER_MASS = 33 -- force scales with total raft mass
local PADDLE_BOOST = 20 -- extra force from a paddle stroke
local PADDLE_DECAY = 2.0 -- seconds for paddle boost to decay
local PADDLE_TURN_SPEED = 1.5 -- radians/sec for yaw steering

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local boat = workspace:WaitForChild("Raft")
while not boat.PrimaryPart do
	task.wait(0.1)
end

local primaryPart = boat.PrimaryPart

-- Lock the raft heading at startup so it travels in a straight line
-- Preserve initial pitch/roll (from the sideways-log PrimaryPart orientation)
local initialPitch, initialYaw, initialRoll = primaryPart.CFrame:ToEulerAnglesYXZ()
local lockedYaw = initialYaw

-- Store the rest CFrame (used by BuildingSystem for stable placement)
-- Must include the log's inherent pitch/roll so floor placement works correctly
local restY = primaryPart.Position.Y
primaryPart:SetAttribute("RestCFrame", primaryPart.CFrame)
primaryPart:SetAttribute("RestYaw", lockedYaw)

-- RemoteEvent for paddle input
local paddleEvent = Instance.new("RemoteEvent")
paddleEvent.Name = "PaddleAction"
paddleEvent.Parent = ReplicatedStorage

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

-- Compute forward direction once (LookVector = along the logs)
local forwardVector = primaryPart.CFrame.LookVector
local forwardDirection = Vector3.new(forwardVector.X, 0, forwardVector.Z)
if forwardDirection.Magnitude > 0.001 then
	forwardDirection = forwardDirection.Unit
else
	forwardDirection = Vector3.new(0, 0, -1)
end

-- Paddle state
local paddleBoostRemaining = 0 -- seconds left of boost
local paddleDirection = Vector3.zero -- direction of last paddle stroke
local targetYaw = lockedYaw -- yaw the paddle is steering toward

-- Handle paddle input from clients
paddleEvent.OnServerEvent:Connect(function(player, direction)
	if typeof(direction) ~= "Vector3" then return end

	-- Validate: must be a unit-ish horizontal vector
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.5 then return end
	flat = flat.Unit

	-- Apply paddle boost
	paddleDirection = flat
	paddleBoostRemaining = PADDLE_DECAY

	-- Set the target yaw to the paddle direction
	targetYaw = math.atan2(-flat.X, -flat.Z)
end)

game:GetService("RunService").Heartbeat:Connect(function(dt)
	if not primaryPart or not primaryPart.Parent then
		return
	end

	-- Smoothly steer lockedYaw toward targetYaw
	if lockedYaw ~= targetYaw then
		local diff = targetYaw - lockedYaw
		-- Normalize angle difference to [-pi, pi]
		diff = math.atan2(math.sin(diff), math.cos(diff))
		local step = PADDLE_TURN_SPEED * dt
		if math.abs(diff) <= step then
			lockedYaw = targetYaw
		else
			lockedYaw = lockedYaw + math.sign(diff) * step
		end
		-- Update forward direction to match new yaw
		forwardDirection = Vector3.new(-math.sin(lockedYaw), 0, -math.cos(lockedYaw)).Unit
	end

	local currentVelocity = primaryPart.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local flatSpeed = flatVelocity.Magnitude

	local forceFactor = math.clamp(1 - (flatSpeed / SPEED), 0, 1)

	local totalMass = primaryPart.AssemblyMass
	local baseForce = forwardDirection * FORCE_PER_MASS * totalMass * forceFactor

	-- Add paddle boost (decays over time)
	local paddleForce = Vector3.zero
	if paddleBoostRemaining > 0 then
		local boostFactor = paddleBoostRemaining / PADDLE_DECAY
		paddleForce = paddleDirection * PADDLE_BOOST * totalMass * boostFactor
		paddleBoostRemaining = math.max(0, paddleBoostRemaining - dt)
	end

	vectorForce.Force = baseForce + paddleForce

	-- Scale torque with raft mass so it always rotates, even with many tiles
	alignOrientation.MaxTorque = totalMass * 500
	-- Preserve log's natural pitch/roll, only control yaw (use YXZ Euler order to match decomposition)
	alignOrientation.CFrame = CFrame.fromEulerAnglesYXZ(initialPitch, lockedYaw, initialRoll)

	-- Update RestCFrame so building systems use the current yaw (not startup yaw)
	-- Preserve the log's inherent pitch/roll, only update yaw + position
	local pos = primaryPart.Position
	primaryPart:SetAttribute("RestCFrame", CFrame.new(pos.X, restY, pos.Z) * CFrame.fromEulerAnglesYXZ(initialPitch, lockedYaw, initialRoll))
	-- Store yaw as a plain number — avoids Euler decomposition issues with rotated log
	primaryPart:SetAttribute("RestYaw", lockedYaw)
end)
