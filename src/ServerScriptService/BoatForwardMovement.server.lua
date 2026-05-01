local SPEED = 25
local PADDLE_BOOST = 5 -- extra m/s added to base speed during a paddle stroke
local PADDLE_DECAY = 1.5 -- seconds for paddle boost to decay
local PADDLE_COURSE_NUDGE = math.rad(3) -- max course rotation per paddle stroke

-- Strength of the velocity correction. Higher = the raft locks onto its
-- bow-aligned target velocity faster (kills sideways drift more aggressively).
local VELOCITY_GAIN = 6

-- Custom buoyancy: fully counteracts gravity so the raft hovers at waterY,
-- then a spring-damper corrects any displacement. Without gravity
-- compensation, the spring alone would need enormous stiffness to fight
-- the 196.2 studs/s² gravity — at stiffness 8 the raft sinks ~25 studs.
local BUOYANCY_STIFFNESS = 10 -- spring correction for displacement from waterY
local BUOYANCY_DAMPING = 6    -- damping to prevent vertical oscillation

-- ─── Wind event ───
-- Wind only starts once the players have survived past the 5th day, then
-- fires once every 2 in-game days. One full day cycle in DayNightCycle.lua
-- is 300s (day) + 120s (night) = 420s, so "every 2 days" = 840s.
local WIND_START_DAY = 6 -- wind is unlocked at the start of this day
local WIND_INTERVAL = 2 * (300 + 120) -- seconds between wind events
local WIND_DURATION = 15 -- seconds the wind blows
local WIND_PLAYER_ACCEL = 400 -- studs/s² horizontal force applied to players standing on the raft
local WIND_AIRBORNE_ACCEL = 30 -- much smaller force while the player is in the air, so a jump doesn't launch them
local WIND_SHELTER_DISTANCE = 50 -- studs; max distance the upwind shelter probe checks
local WIND_SHELTER_BOX_SIZE = Vector3.new(3, 5, 3) -- approximate character cross-section for the Blockcast
local TURN_SPEED = 0.6 -- radians/sec the raft rotates to face the wind

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local boat = workspace:WaitForChild("Raft")
while not boat.PrimaryPart do
	task.wait(0.1)
end

local primaryPart = boat.PrimaryPart

-- Capture water surface Y while the raft is still anchored at its placed
-- position. This is the target height for the buoyancy spring.
local waterY = primaryPart.Position.Y

-- Ensure all raft parts are unanchored so physics (buoyancy, movement) work.
-- SpawnLocations are anchored by default in Studio; if any part in a welded
-- assembly is anchored the entire raft is frozen in place.
for _, desc in boat:GetDescendants() do
	if desc:IsA("BasePart") then
		desc.Anchored = false
		pcall(function()
			desc:SetNetworkOwner(nil)
		end)
	end
end
primaryPart.Anchored = false

-- Lock the raft as server-controlled. Without this, Roblox auto-assigns
-- network ownership to the nearest player, and any time a new part is
-- welded into the raft assembly the ownership gets recomputed — that
-- transition causes a brief replication desync where the raft visibly
-- disappears and teleports for one frame on every placement.
pcall(function()
	primaryPart:SetNetworkOwner(nil)
end)

-- Store the initial rotation as a full CFrame to avoid gimbal lock.
-- With a PrimaryPart oriented at 90° pitch (e.g. SpawnLocation with
-- Orientation 90,0,0), Euler decomposition via ToEulerAnglesYXZ hits
-- a singularity where yaw and roll become indistinguishable. By keeping
-- the initial rotation as a CFrame and applying yaw changes via direct
-- rotation composition (pre-multiplying a world-Y rotation), the
-- AlignOrientation stays stable at any pitch angle.
local initialRotation = primaryPart.CFrame.Rotation
local _, initialYaw, _ = primaryPart.CFrame:ToEulerAnglesYXZ()
local lockedYaw = initialYaw

-- Store the rest CFrame (used by BuildingSystem for stable placement).
-- The Y component is updated every heartbeat to the raft's actual current Y;
-- we do NOT cache the initial Y, because if the raft happens to spawn above
-- the water surface it still has to fall and settle, and a cached boot-time
-- Y would pin RestCFrame.Y to that stale (non-settled) position forever.
-- BuildingSystem uses RestCFrame.Y to place the cursor projection plane, so
-- a stale Y makes the client think the raft is at a coordinate different
-- from where it actually is, creating a dead strip for the build cursor.
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

	affectedPlayers[plr] = {force = force, attach = attach, hrp = hrp}
end

-- Reusable raycast params for the shelter check (filter is set per call).
local shelterRayParams = RaycastParams.new()
shelterRayParams.FilterType = Enum.RaycastFilterType.Exclude

-- A player is sheltered if a Blockcast the size of their body, swept from
-- their HRP toward the wind source (i.e. opposite of the wind direction),
-- hits any obstacle. We use a Blockcast instead of a single ray so a wall
-- that's slightly off-center from the HRP still counts as cover, and we
-- give it enough range to cover any reasonable raft layout.
local function isShelteredFromWind(hrp, char)
	if not hrp or not hrp.Parent then return false end
	shelterRayParams.FilterDescendantsInstances = {char}
	local cf = CFrame.new(hrp.Position)
	local result = workspace:Blockcast(cf, WIND_SHELTER_BOX_SIZE, -windDirection * WIND_SHELTER_DISTANCE, shelterRayParams)
	return result ~= nil
end

-- Update force magnitude based on whether the player is grounded and exposed.
-- The grounded force is large (so the wind feels strong while walking), but
-- when the Humanoid leaves the floor (jump / fall) we drop it to a small
-- value so the player doesn't get launched off the raft. If the player is
-- behind an obstacle (wall, log, etc.) on the upwind side, the force is zero.
local function updateWindForces()
	for plr, data in pairs(affectedPlayers) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = data.hrp
		if hum and hrp and data.force and data.force.Parent then
			if isShelteredFromWind(hrp, char) then
				data.force.Force = Vector3.zero
			else
				local airborne = hum.FloorMaterial == Enum.Material.Air
				local accel = airborne and WIND_AIRBORNE_ACCEL or WIND_PLAYER_ACCEL
				data.force.Force = windDirection * hrp.AssemblyMass * accel
			end
		end
	end
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
	-- Don't blow any wind until the players have lived through the first five
	-- days. DayCount is populated by DayNightCycle.server.lua.
	local dayCount = ReplicatedStorage:WaitForChild("DayCount")
	while dayCount.Value < WIND_START_DAY do
		dayCount:GetPropertyChangedSignal("Value"):Wait()
	end

	while true do
		startWindEvent()
		task.wait(WIND_INTERVAL)
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
	-- Anchor drag: below 70% depth the anchor doesn't bite at all.
	-- Between 70% and 100% the raft's speed ramps linearly down to 0,
	-- so fully-deployed anchor = full stop and the last ~30% of the
	-- rope produces a natural-feeling braking arc.
	local anchorDepth = boat:GetAttribute("AnchorDepth") or 0
	if anchorDepth > 0.7 then
		local brake = math.clamp((anchorDepth - 0.7) / 0.3, 0, 1)
		targetSpeed = targetSpeed * (1 - brake)
	end
	local desiredVelocity = forwardDirection * targetSpeed

	-- Velocity correction force. This simultaneously:
	--   • kills any lateral velocity (sideways drift)
	--   • kills any backwards velocity
	--   • holds forward speed constant at SPEED regardless of turning
	local velocityError = desiredVelocity - flatVelocity
	local horizontalForce = velocityError * totalMass * VELOCITY_GAIN

	-- Custom buoyancy: first counteract gravity entirely so the raft is
	-- weightless, then apply a spring-damper to lock it at waterY.
	-- gravityCompensation alone makes the raft hover; the spring corrects
	-- any drift above or below the water surface.
	local gravityCompensation = totalMass * workspace.Gravity
	local yError = waterY - primaryPart.Position.Y
	local yVelocity = currentVelocity.Y
	local springForce = (yError * BUOYANCY_STIFFNESS - yVelocity * BUOYANCY_DAMPING) * totalMass
	local buoyancyForce = gravityCompensation + springForce

	vectorForce.Force = Vector3.new(horizontalForce.X, buoyancyForce, horizontalForce.Z)

	-- Hard Y clamp (T27). The buoyancy spring above is correct in
	-- principle but soft enough that a strong impulse — Motor6D
	-- reaction torque from a running sawmill, multiple plank welds
	-- in the same frame, a player jumping on the raft right after a
	-- placement — can briefly drive the raft well above or below
	-- waterY before the spring catches up. Clamping pos.Y to a
	-- small ±band around waterY and zeroing the corresponding
	-- velocity component if the clamp triggers means the raft
	-- physically can't fly up or sink: any disturbance gets eaten
	-- here without the spring having to swing back through zero.
	local Y_CLAMP_UP   = 0.6   -- studs above waterY
	local Y_CLAMP_DOWN = 1.5   -- studs below waterY
	local curY = primaryPart.Position.Y
	if curY > waterY + Y_CLAMP_UP then
		primaryPart.CFrame = primaryPart.CFrame
			- Vector3.new(0, curY - (waterY + Y_CLAMP_UP), 0)
		local v = primaryPart.AssemblyLinearVelocity
		if v.Y > 0 then
			primaryPart.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
		end
	elseif curY < waterY - Y_CLAMP_DOWN then
		primaryPart.CFrame = primaryPart.CFrame
			+ Vector3.new(0, (waterY - Y_CLAMP_DOWN) - curY, 0)
		local v = primaryPart.AssemblyLinearVelocity
		if v.Y < 0 then
			primaryPart.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
		end
	end

	-- Scale torque with raft mass so it always rotates, even with many tiles
	alignOrientation.MaxTorque = totalMass * 500
	-- Compose the target rotation from the initial rotation + a world-Y yaw
	-- change. This avoids the Euler gimbal lock at 90° pitch that made
	-- CFrame.fromEulerAnglesYXZ(π/2, yaw, 0) unstable.
	local yawDelta = lockedYaw - initialYaw
	local targetRotation = CFrame.Angles(0, yawDelta, 0) * initialRotation
	alignOrientation.CFrame = targetRotation

	-- Update RestCFrame so building systems use the current yaw. Use the
	-- live pos.Y (not a captured init-time value) so the rest frame always
	-- tracks the raft's real vertical position, even if the raft spawned
	-- above or below its settled water-level Y.
	local pos = primaryPart.Position
	primaryPart:SetAttribute("RestCFrame", CFrame.new(pos) * targetRotation)
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
		updateWindForces()
		if windRemainingTime <= 0 then
			endWindEvent()
		end
	end
end)

-- Clean up if a player leaves mid-wind
Players.PlayerRemoving:Connect(function(plr)
	detachWindForce(plr)
end)
