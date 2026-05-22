-- CaseOpenInteraction.server.lua
-- Auto-discovers every Model named "InteractableCase" in workspace
-- and wires up an E-key ProximityPrompt that plays the model's
-- CaseOpenAnimation. The case has no other side effects — opening
-- it just runs the animation once.
--
-- Expected per-case structure:
--   InteractableCase (Model)
--     └─ StandardCase2Model (Model)
--          ├─ RootPart (BasePart)         -- prompt anchor + Animator parent
--          ├─ AnimationController
--          │    ├─ Animator
--          │    └─ CaseOpenAnimation (Animation)
--          └─ ... (Lower_part, Upper_part, Neon, Motor6Ds, …)

local PROMPT_ACTION_TEXT  = "Open"
local PROMPT_OBJECT_TEXT  = "Case"
local PROMPT_DISTANCE     = 8
local PROMPT_HOLD_SECS    = 0   -- instant on E tap
local OPEN_ATTR           = "CaseOpened"
local LOG_TAG             = "[CaseOpen]"

local function findStandard(caseModel)
	-- Accept either "StandardCase2Model" specifically or, as a
	-- fallback, any Model child carrying the AnimationController so
	-- variants with different inner names still work.
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
	-- Prefer a BasePart literally named RootPart; fall back to the
	-- model's PrimaryPart or first BasePart so authoring the prompt
	-- doesn't depend on an exact naming convention.
	local root = standardModel:FindFirstChild("RootPart")
	if root and root:IsA("BasePart") then return root end
	if standardModel.PrimaryPart then return standardModel.PrimaryPart end
	for _, d in standardModel:GetDescendants() do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

local function setupCase(caseModel)
	if caseModel:GetAttribute("CaseInteractionReady") then return end

	local standard = findStandard(caseModel)
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

	-- Reuse an existing ProximityPrompt if the author dropped one in,
	-- otherwise create one. Either way force the key + display props
	-- so behaviour is consistent across cases.
	local prompt = anchor:FindFirstChildOfClass("ProximityPrompt")
		or Instance.new("ProximityPrompt", anchor)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.ActionText      = PROMPT_ACTION_TEXT
	prompt.ObjectText      = PROMPT_OBJECT_TEXT
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.HoldDuration    = PROMPT_HOLD_SECS
	prompt.RequiresLineOfSight = false

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

	caseModel:SetAttribute("CaseInteractionReady", true)
end

local function isCase(inst)
	return inst:IsA("Model") and inst.Name == "InteractableCase"
end

for _, d in workspace:GetDescendants() do
	if isCase(d) then setupCase(d) end
end

workspace.DescendantAdded:Connect(function(d)
	if isCase(d) then
		task.defer(setupCase, d)
	end
end)
