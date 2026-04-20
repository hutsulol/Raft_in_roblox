-- AnchorInteraction.server.lua
-- Server side of the anchor: exposes a RemoteEvent the client UI
-- fires to raise/lower each anchor, clamps the RopeConstraint's
-- Length to [MIN_ROPE, MAX_ROPE], and sets an AnchorDeployed
-- attribute on the raft so BoatForwardMovement can halt it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MIN_ROPE         = 5    -- fully raised (anchor rests inside the frame)
local MAX_ROPE         = 11   -- fully lowered, the raft stops
local ROPE_STEP        = 0.2  -- per key press
local INTERACTION_RANGE = 15  -- server-side anti-cheat gate

local anchorEvent = ReplicatedStorage:FindFirstChild("AnchorAction")
if not anchorEvent then
	anchorEvent = Instance.new("RemoteEvent")
	anchorEvent.Name = "AnchorAction"
	anchorEvent.Parent = ReplicatedStorage
end

-- ─── Helpers ─────────────────────────────────────────────────────────
local function findRope(anchorModel)
	local inner = anchorModel:FindFirstChild("anchor")
	if inner then
		local rc = inner:FindFirstChildOfClass("RopeConstraint")
		if rc then return rc end
	end
	for _, d in anchorModel:GetDescendants() do
		if d:IsA("RopeConstraint") then return d end
	end
	return nil
end

local function findCenterOfSticks(anchorModel)
	local sticks = anchorModel:FindFirstChild("sticks")
	if sticks then
		local c = sticks:FindFirstChild("Center of sticks", true)
		if c and c:IsA("BasePart") then return c end
	end
	local c = anchorModel:FindFirstChild("Center of sticks", true)
	if c and c:IsA("BasePart") then return c end
	return nil
end

-- Find the HingeConstraint the template ships inside HingePart —
-- that's what the user wired up as the wheel's Motor actuator.
local function findHinge(anchorModel)
	local wheel = anchorModel:FindFirstChild("Wooden_Wheel")
	if not wheel then return nil end
	local hinge = wheel:FindFirstChild("HingePart", true)
	if not hinge then return nil end
	local hc = hinge:FindFirstChildOfClass("HingeConstraint")
	return hc
end

-- The user's Wooden_Wheel ships with its own internal weld + hinge
-- configuration. We no longer touch those welds during setup — the
-- HingeConstraint handles rotation on its own; any weld adjustments
-- here just risk detaching pieces of the wheel. Kept as a stub so
-- the call site stays the same.
local function freeWheelRotor(_anchorModel)
end

-- ─── Hinge pulse ────────────────────────────────────────────────────
-- Each press of E (direction +1) or Q (-1) drives the wheel's
-- HingeConstraint motor for SPIN_PULSE_DURATION seconds, then coasts
-- to a stop. Overlapping presses extend the pulse and can flip
-- direction instantly — MotorMaxTorque is held high while the pulse
-- is live so the motor actually develops the commanded velocity.
local SPIN_PULSE_DURATION  = 0.5
local SPIN_TORQUE          = 50000
local SPIN_ANGULAR_VELOCITY = 4  -- rad/s magnitude
local pulseTokens = {}

local function pulseWheel(anchorModel, direction)
	local hc = findHinge(anchorModel)
	if not hc then return end
	hc.MotorMaxTorque  = SPIN_TORQUE
	hc.AngularVelocity = direction * SPIN_ANGULAR_VELOCITY

	pulseTokens[anchorModel] = (pulseTokens[anchorModel] or 0) + 1
	local token = pulseTokens[anchorModel]
	task.delay(SPIN_PULSE_DURATION, function()
		if pulseTokens[anchorModel] ~= token then return end
		if not hc or not hc.Parent then return end
		hc.MotorMaxTorque  = 0
		hc.AngularVelocity = 0
	end)
end

-- Raft's AnchorDepth ∈ [0, 1] is the deepest anchor currently deployed
-- on it (0 = all anchors up, 1 = at least one rope fully out). Set
-- alongside the existing AnchorDeployed bool so BoatForwardMovement
-- can smoothly scale the raft's forward speed instead of a hard stop.
local function recomputeRaftAnchoredState()
	local raft = workspace:FindFirstChild("Raft")
	if not raft then return end
	local range = math.max(0.001, MAX_ROPE - MIN_ROPE)
	local depth = 0
	for _, child in raft:GetChildren() do
		if child:IsA("Model") and child.Name == "Anchor_part" then
			local rc = findRope(child)
			if rc then
				local d = math.clamp((rc.Length - MIN_ROPE) / range, 0, 1)
				if d > depth then depth = d end
			end
		end
	end
	raft:SetAttribute("AnchorDepth", depth)
	raft:SetAttribute("AnchorDeployed", depth >= 1 - 1e-3)
end

-- ─── Setup per anchor ────────────────────────────────────────────────
-- Each new anchor gets its rope length clamped to MIN_ROPE at spawn so
-- the anchor rests cleanly inside the frame, and a changed-signal so
-- the raft's AnchorDeployed state follows whatever the rope is doing.
local function setupAnchor(anchorModel)
	if anchorModel:GetAttribute("AnchorInteractionReady") then return end
	local rope = findRope(anchorModel)
	if not rope then return end
	-- Clamp initial length into the valid range.
	if rope.Length < MIN_ROPE then rope.Length = MIN_ROPE end
	if rope.Length > MAX_ROPE then rope.Length = MAX_ROPE end
	rope:GetPropertyChangedSignal("Length"):Connect(recomputeRaftAnchoredState)
	freeWheelRotor(anchorModel)
	-- HingeConstraint ships idle (MotorMaxTorque 0) — pulseWheel
	-- turns it on for each E / Q press, then zeroes it again.
	local hc = findHinge(anchorModel)
	if hc then hc.MotorMaxTorque = 0; hc.AngularVelocity = 0 end
	anchorModel:SetAttribute("AnchorInteractionReady", true)
	recomputeRaftAnchoredState()
end

for _, d in workspace:GetDescendants() do
	if d:IsA("Model") and d.Name == "Anchor_part" then setupAnchor(d) end
end

workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") and d.Name == "Anchor_part" then
		task.defer(setupAnchor, d)
	end
end)

workspace.DescendantRemoving:Connect(function(d)
	if d:IsA("Model") and d.Name == "Anchor_part" then
		task.defer(recomputeRaftAnchoredState)
	end
end)

-- ─── Remote handler ─────────────────────────────────────────────────
anchorEvent.OnServerEvent:Connect(function(player, action, anchorModel)
	if typeof(action) ~= "string" then return end
	if typeof(anchorModel) ~= "Instance" then return end
	if not anchorModel:IsDescendantOf(workspace) then return end
	if anchorModel.Name ~= "Anchor_part" then return end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local center = findCenterOfSticks(anchorModel)
	if not center then return end
	if (center.Position - hrp.Position).Magnitude > INTERACTION_RANGE then return end

	local rope = findRope(anchorModel)
	if not rope then return end

	if action == "lower" then
		rope.Length = math.clamp(rope.Length + ROPE_STEP, MIN_ROPE, MAX_ROPE)
		pulseWheel(anchorModel, 1)
	elseif action == "raise" then
		rope.Length = math.clamp(rope.Length - ROPE_STEP, MIN_ROPE, MAX_ROPE)
		pulseWheel(anchorModel, -1)
	end
end)

-- Published so other server scripts (the UI client, BoatForwardMovement)
-- can agree on the rope limits without duplicating constants.
_G.AnchorConfig = {
	MinRope  = MIN_ROPE,
	MaxRope  = MAX_ROPE,
	Step     = ROPE_STEP,
}
