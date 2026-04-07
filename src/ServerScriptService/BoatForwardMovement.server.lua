local SPEED = 25
local FORCE_PER_MASS = 33 -- force scales with total raft mass
local PADDLE_BOOST = 6 -- small extra push from a paddle stroke
local PADDLE_DECAY = 1.5 -- seconds for paddle boost to decay
local PADDLE_NUDGE_RATIO = 0.15 -- how much of the boost goes sideways (0..1)

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

-- Forward direction is always derived from the locked yaw + initial pitch/roll
-- so it stays consistent with the AlignOrientation target, even if the raft
-- is pivoted (e.g., by RaftSaveSystem on load) after this script started.
local function computeForwardDirection(yaw)
	local cf = CFrame.fromEulerAnglesYXZ(initialPitch, yaw, initialRoll)
	local lv = cf.LookVector
	local flat = Vector3.new(lv.X, 0, lv.Z)
	if flat.Magnitude > 0.001 then
		return flat.Unit
	end
	return Vector3.new(0, 0, -1)
end

local forwardDirection = computeForwardDirection(lockedYaw)

-- Paddle state
local paddleBoostRemaining = 0 -- seconds left of boost
local paddleDirection = Vector3.zero -- direction of last paddle stroke

-- Handle paddle input from clients. The paddle gives a small forward boost
-- and a tiny sideways nudge toward the swing direction. It does NOT change
-- the raft's locked heading.
paddleEvent.OnServerEvent:Connect(function(player, direction)
	if typeof(direction) ~= "Vector3" then return end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.5 then return end
	paddleDirection = flat.Unit
	paddleBoostRemaining = PADDLE_DECAY
end)

game:GetService("RunService").Heartbeat:Connect(function(dt)
	if not primaryPart or not primaryPart.Parent then
		return
	end

	-- Use the current physical raft heading to compute forward, so
	-- any drift in raft yaw doesn't push the raft off-course (we always push
	-- along the raft's actual forward, not a stale cached vector).
	-- Rotate by -45° around Y to align with the raft's true front.
	local actualLook = primaryPart.CFrame.LookVector
	local flatLook = Vector3.new(-actualLook.X, 0, -actualLook.Z)
	if flatLook.Magnitude > 0.001 then
		flatLook = flatLook.Unit
		local cosA = math.cos(math.rad(-45))
		local sinA = math.sin(math.rad(-45))
		forwardDirection = Vector3.new(
			flatLook.X * cosA + flatLook.Z * sinA,
			0,
			-flatLook.X * sinA + flatLook.Z * cosA
		).Unit
	end

	local currentVelocity = primaryPart.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local flatSpeed = flatVelocity.Magnitude

	local forceFactor = math.clamp(1 - (flatSpeed / SPEED), 0, 1)

	local totalMass = primaryPart.AssemblyMass
	local baseForce = forwardDirection * FORCE_PER_MASS * totalMass * forceFactor

	-- Paddle gives a small extra forward push plus a tiny sideways nudge
	-- toward the swing direction. The raft's heading is NOT changed.
	local paddleForce = Vector3.zero
	if paddleBoostRemaining > 0 then
		local boostFactor = paddleBoostRemaining / PADDLE_DECAY

		-- Forward component (most of the boost)
		local forwardPush = forwardDirection * (1 - PADDLE_NUDGE_RATIO)

		-- Small lateral nudge perpendicular to forward, signed by where the
		-- player paddled relative to forward.
		local right = Vector3.new(forwardDirection.Z, 0, -forwardDirection.X)
		local sideSign = math.clamp(paddleDirection:Dot(right), -1, 1)
		local lateralNudge = right * sideSign * PADDLE_NUDGE_RATIO

		paddleForce = (forwardPush + lateralNudge) * PADDLE_BOOST * totalMass * boostFactor
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
