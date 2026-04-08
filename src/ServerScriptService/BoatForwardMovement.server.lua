local SPEED = 25
local PADDLE_BOOST = 5 -- extra m/s added to base speed during a paddle stroke
local PADDLE_DECAY = 1.5 -- seconds for paddle boost to decay
local PADDLE_COURSE_NUDGE = math.rad(3) -- max course rotation per paddle stroke

-- Strength of the velocity correction. Higher = the raft locks onto its
-- bow-aligned target velocity faster (kills sideways drift more aggressively).
local VELOCITY_GAIN = 6

-- ─── Wind event ───
local WIND_INTERVAL_MIN = 10 -- seconds, min delay between wind events (TEMP: testing)
local WIND_INTERVAL_MAX = 10 -- seconds, max delay between wind events (TEMP: testing)
local WIND_DURATION = 6 -- seconds the wind blows
local WIND_PLAYER_ACCEL = 80 -- studs/s² horizontal force applied to players standing on the raft
local TURN_SPEED = 0.6 -- radians/sec the raft rotates to face the wind

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

local windEvent = Instance.new("RemoteEvent")
windEvent.Name = "WindUpdate"
windEvent.Parent = ReplicatedStorage

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

-- ─── Course state ───
-- The course only changes during a wind event. Outside of wind events the
-- raft holds its current heading.
local currentDirection = computeVisualFront(lockedYaw) -- start matching the raft's current heading

local function broadcastCurrent()
	currentEvent:FireAllClients(currentDirection)
end

-- ─── Wind state ───
local windActive = false
local windRemainingTime = 0
local windDirection = Vector3.new(0, 0, -1)
-- player -> { force = VectorForce, attach = Attachment }
local affectedPlayers = {}

local function startWindEvent()
	windDirection = randomHorizontalDirection()
	-- The wind redirects the raft's course immediately. The raft will rotate
	-- toward this new heading via the existing turn logic.
	currentDirection = windDirection
	windActive = true
	windRemainingTime = WIND_DURATION

	for _, plr in Players:GetPlayers() do
		plr:SetAttribute("WindActive", true)
	end

	windEvent:FireAllClients(true, WIND_DURATION, WIND_DURATION, windDirection)
	broadcastCurrent()
	print(string.format("[Wind] Wind event started, direction (%.2f, %.2f)", windDirection.X, windDirection.Z))
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
	local attach = Instance.new("Attachment")
	attach.Name = "WindAttach"
	attach.Parent = hrp

	local force = Instance.new("VectorForce")
	force.Name = "WindForce"
	force.Attachment0 = attach
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = windDirection * hrp.AssemblyMass * WIND_PLAYER_ACCEL
	force.Parent = hrp

	affectedPlayers[plr] = {force = force, attach = attach}
end

local function releaseAffectedPlayers()
	for plr in pairs(affectedPlayers) do
		detachWindForce(plr)
	end
end

local function endWindEvent()
	windActive = false
	windRemainingTime = 0
	releaseAffectedPlayers()
	for _, plr in Players:GetPlayers() do
		plr:SetAttribute("WindActive", false)
	end
	windEvent:FireAllClients(false, 0, WIND_DURATION, windDirection)
end

task.spawn(function()
	while true do
		local delay = math.random(WIND_INTERVAL_MIN, WIND_INTERVAL_MAX)
		task.wait(delay)
		startWindEvent()
	end
end)

-- Re-broadcast on player join
Players.PlayerAdded:Connect(function(plr)
	task.wait(2)
	currentEvent:FireClient(plr, currentDirection)
	if windActive then
		plr:SetAttribute("WindActive", true)
		windEvent:FireClient(plr, true, windRemainingTime, WIND_DURATION, windDirection)
	end
end)

-- ─── Player push (raycast filter set up once) ───
local windRayParams = RaycastParams.new()
windRayParams.FilterType = Enum.RaycastFilterType.Include
windRayParams.FilterDescendantsInstances = {boat}

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

	-- ─── Wind event: apply a horizontal force to players standing on the raft ───
	-- Using a VectorForce (instead of overriding velocity) lets the Humanoid
	-- walk controller still respond to player input — they get pushed but can
	-- walk against the wind.
	if windActive then
		windRemainingTime = math.max(0, windRemainingTime - dt)
		for _, plr in Players:GetPlayers() do
			local char = plr.Character
			if char then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp then
					local origin = hrp.Position
					local result = workspace:Raycast(origin, Vector3.new(0, -8, 0), windRayParams)
					if result then
						attachWindForce(plr, hrp)
					end
				end
			end
		end
		if windRemainingTime <= 0 then
			endWindEvent()
		end
	end
end)

-- Clean up if a player leaves mid-wind
Players.PlayerRemoving:Connect(function(plr)
	detachWindForce(plr)
end)
