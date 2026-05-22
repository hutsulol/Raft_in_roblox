-- CaseOpenScript.server.lua
-- Lives inside StandardCase2Model. The author has already placed
-- a ProximityPrompt on the sibling PrimaryPart (under
-- InteractableCase); this script just hooks its Triggered event
-- and plays CaseOpenAnimation once. No other side effects.
--
-- Expected structure:
--   InteractableCase (Model)
--     ├─ PrimaryPart (BasePart)
--     │    └─ ProximityPrompt           ← author-placed
--     ├─ StandardCase2Model (Model)
--     │    ├─ Script                    ← THIS
--     │    ├─ AnimationController
--     │    │    └─ Animator
--     │    ├─ CaseOpenAnimation
--     │    └─ RootPart, BoundingBox, Lower_part, Upper_part, Neon, …
--     └─ … (AbilityOrb, BundlePromptPart, etc.)

local OPEN_ATTR = "CaseOpened"
local LOG_TAG   = "[CaseOpen]"

local standardModel = script.Parent
local caseModel     = standardModel.Parent
print(string.format("%s booting under %s", LOG_TAG, standardModel:GetFullName()))

-- ── Find the author-placed ProximityPrompt on the case's PrimaryPart.
local primaryPart = caseModel:FindFirstChild("PrimaryPart")
if not (primaryPart and primaryPart:IsA("BasePart")) then
	warn(string.format("%s no PrimaryPart sibling under %s", LOG_TAG, caseModel:GetFullName()))
	return
end
local prompt = primaryPart:FindFirstChildOfClass("ProximityPrompt")
if not prompt then
	warn(string.format("%s no ProximityPrompt under %s", LOG_TAG, primaryPart:GetFullName()))
	return
end

-- ── Find the animation. It may live directly under StandardCase2Model
-- (as in the current authoring) or under the AnimationController.
local controller = standardModel:FindFirstChildOfClass("AnimationController")
if not controller then
	warn(string.format("%s no AnimationController under %s", LOG_TAG, standardModel:GetFullName()))
	return
end
local animator = controller:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = controller
end
local animation = standardModel:FindFirstChild("CaseOpenAnimation")
	or controller:FindFirstChild("CaseOpenAnimation")
if not (animation and animation:IsA("Animation")) then
	warn(string.format("%s no CaseOpenAnimation under %s", LOG_TAG, standardModel:GetFullName()))
	return
end

local track = animator:LoadAnimation(animation)
track.Priority = Enum.AnimationPriority.Action
print(string.format("%s bound to prompt at %s | animId=%q | trackLength=%.3f",
	LOG_TAG, primaryPart:GetFullName(), tostring(animation.AnimationId), track.Length))

local playing = false
prompt.Triggered:Connect(function(player)
	if caseModel:GetAttribute(OPEN_ATTR) or playing then return end
	playing = true
	prompt.Enabled = false
	print(string.format("%s triggered by %s — playing animation", LOG_TAG, player.Name))
	track:Play()
	-- Some empty / mis-uploaded animations end before Stopped can
	-- fire — fall back on a length-based wait instead.
	if track.Length > 0 then
		task.wait(track.Length)
	else
		warn(string.format("%s track length is 0 — animation %q may be empty / not uploaded / not owned by the game",
			LOG_TAG, tostring(animation.AnimationId)))
	end
	caseModel:SetAttribute(OPEN_ATTR, true)
	playing = false
	-- Prompt stays disabled — case is one-shot per spec.
end)
