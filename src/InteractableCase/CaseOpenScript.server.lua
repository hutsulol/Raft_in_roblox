-- CaseOpenScript.server.lua
-- Lives directly inside the InteractableCase Model in workspace.
-- script.Parent == InteractableCase. Wires up an E-key
-- ProximityPrompt and plays CaseOpenAnimation once; no other
-- side effects.
--
-- Expected sibling structure under script.Parent:
--   StandardCase2Model (Model)
--     ├─ RootPart (BasePart)         -- prompt anchor
--     ├─ AnimationController
--     │    ├─ Animator
--     │    └─ CaseOpenAnimation (Animation)
--     └─ ... (Lower_part, Upper_part, Neon, Motor6Ds, …)

local PROMPT_ACTION_TEXT = "Open"
local PROMPT_OBJECT_TEXT = "Case"
local PROMPT_DISTANCE    = 8
local PROMPT_HOLD_SECS   = 0   -- instant on E tap
local OPEN_ATTR          = "CaseOpened"
local LOG_TAG            = "[CaseOpen]"

local caseModel = script.Parent
print(string.format("%s booting under %s", LOG_TAG, caseModel:GetFullName()))

local function findStandard()
	-- Accept the exact name first; fall back to any inner Model that
	-- has the AnimationController so variants with different naming
	-- still work.
	local m = caseModel:FindFirstChild("StandardCase2Model")
	if m then return m end
	for _, child in caseModel:GetChildren() do
		if child:IsA("Model") and child:FindFirstChildOfClass("AnimationController") then
			return child
		end
	end
	return nil
end

local function findPromptAnchor(standardModel)
	-- Prefer a top-level PrimaryPart on the InteractableCase Model
	-- (it's the part actually centred on the visible mesh, so the
	-- prompt floats over the case rather than hidden inside its
	-- inner geometry). Fall back through BoundingBox -> RootPart ->
	-- standardModel.PrimaryPart -> first BasePart so the script
	-- still works for cases authored without a specific anchor.
	if caseModel.PrimaryPart then return caseModel.PrimaryPart end
	local bb = standardModel:FindFirstChild("BoundingBox")
	if bb and bb:IsA("BasePart") then return bb end
	local root = standardModel:FindFirstChild("RootPart")
	if root and root:IsA("BasePart") then return root end
	if standardModel.PrimaryPart then return standardModel.PrimaryPart end
	for _, d in standardModel:GetDescendants() do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

local standard = findStandard()
if not standard then
	warn(LOG_TAG .. " no StandardCase2Model under " .. caseModel:GetFullName())
	return
end

local controller = standard:FindFirstChildOfClass("AnimationController")
if not controller then
	warn(LOG_TAG .. " no AnimationController under " .. standard:GetFullName())
	return
end
local animator = controller:FindFirstChildOfClass("Animator")
	or Instance.new("Animator", controller)

local animation = controller:FindFirstChild("CaseOpenAnimation")
if not (animation and animation:IsA("Animation")) then
	warn(LOG_TAG .. " no CaseOpenAnimation under " .. controller:GetFullName())
	return
end

local anchor = findPromptAnchor(standard)
if not anchor then
	warn(LOG_TAG .. " no BasePart anchor under " .. standard:GetFullName())
	return
end

-- Reuse an existing prompt if the author dropped one in, otherwise
-- create one. Either way force the key + display props so behaviour
-- is consistent.
local prompt = anchor:FindFirstChildOfClass("ProximityPrompt")
if not prompt then
	prompt = Instance.new("ProximityPrompt")
	prompt.Parent = anchor
end
prompt.KeyboardKeyCode       = Enum.KeyCode.E
prompt.ActionText            = PROMPT_ACTION_TEXT
prompt.ObjectText            = PROMPT_OBJECT_TEXT
prompt.MaxActivationDistance = PROMPT_DISTANCE
prompt.HoldDuration          = PROMPT_HOLD_SECS
prompt.RequiresLineOfSight   = false
prompt.Style                 = Enum.ProximityPromptStyle.Default
prompt.Exclusivity           = Enum.ProximityPromptExclusivity.OnePerButton
prompt.Enabled               = true
print(string.format("%s prompt ready on %s (distance %d)",
	LOG_TAG, anchor:GetFullName(), PROMPT_DISTANCE))

local track = animator:LoadAnimation(animation)
track.Priority = Enum.AnimationPriority.Action

local playing = false
prompt.Triggered:Connect(function(_player)
	if caseModel:GetAttribute(OPEN_ATTR) or playing then return end
	playing = true
	prompt.Enabled = false
	track:Play()
	track.Stopped:Wait()
	caseModel:SetAttribute(OPEN_ATTR, true)
	playing = false
	-- Prompt stays disabled: case is one-shot, "nothing else
	-- happens" per spec.
end)
