-- AnchorInteraction.server.lua
-- Adds a ProximityPrompt to the "Center of sticks" part of every
-- Anchor_part in workspace and, each time the player presses E,
-- increments the RopeConstraint's Length by ROPE_STEP so the anchor
-- gradually lowers under its own weight.

local CollectionService = game:GetService("CollectionService")

local ROPE_STEP = 0.2          -- rope grows by this many studs per press
local HOLD_DURATION = 0        -- instant tap, no hold
local ACTIVATION_DISTANCE = 10 -- studs
local ACTION_TEXT = "Lower anchor"
local OBJECT_TEXT = "Anchor"

-- Walk the anchor model for the parts we care about.
local function findRopeConstraint(anchorModel)
	-- The RopeConstraint lives inside a child model called "anchor".
	local inner = anchorModel:FindFirstChild("anchor")
	if inner then
		local rc = inner:FindFirstChildOfClass("RopeConstraint")
		if rc then return rc end
	end
	-- Fallback: search anywhere inside the full model.
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
	-- Fallback: search the whole model for the named part.
	local c = anchorModel:FindFirstChild("Center of sticks", true)
	if c and c:IsA("BasePart") then return c end
	return nil
end

local function setupAnchor(anchorModel)
	if anchorModel:GetAttribute("AnchorInteractionReady") then return end

	local center = findCenterOfSticks(anchorModel)
	local rope = findRopeConstraint(anchorModel)
	if not center or not rope then return end

	-- Avoid stacking prompts if this runs more than once.
	if center:FindFirstChildOfClass("ProximityPrompt") then
		anchorModel:SetAttribute("AnchorInteractionReady", true)
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = ACTION_TEXT
	prompt.ObjectText = OBJECT_TEXT
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = HOLD_DURATION
	prompt.MaxActivationDistance = ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = center

	prompt.Triggered:Connect(function()
		rope.Length = rope.Length + ROPE_STEP
	end)

	anchorModel:SetAttribute("AnchorInteractionReady", true)
end

local function isAnchor(inst)
	return inst:IsA("Model") and inst.Name == "Anchor_part"
end

-- Initial pass: set up any anchors already in the world.
for _, d in workspace:GetDescendants() do
	if isAnchor(d) then setupAnchor(d) end
end

-- Watch for anchors placed later (via BuildingSystem "anchor" build).
workspace.DescendantAdded:Connect(function(d)
	if isAnchor(d) then
		-- Wait a frame for children to finish replicating before the
		-- "Center of sticks" / RopeConstraint lookups.
		task.defer(setupAnchor, d)
	end
end)
