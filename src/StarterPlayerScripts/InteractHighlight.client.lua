-- InteractHighlight.client.lua
-- ONE global client script (place in StarterPlayerScripts, NOT inside
-- a model — LocalScripts don't run inside Workspace models). It draws
-- an animated white outline on whatever the player can interact with.
--
-- An object lights up if EITHER:
--   * it has a ProximityPrompt that's currently on screen, OR
--   * it (a Model or BasePart) is tagged "Interactable" via the Studio
--     Tag Editor and the player is within HIGHLIGHT_RANGE.
-- So to make the rum bottle glow: just tag its model "Interactable".

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

-- ─── Look / feel ──────────────────────────────────────────────────
local TAG           = "Interactable"
local HIGHLIGHT_RANGE = 16   -- studs, for tag-based proximity glow
local OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)
local FILL_COLOR    = Color3.fromRGB(255, 255, 255)
-- The whole surface glows white and breathes. Fill + outline pulse
-- together between their bright (MIN) and faint (MAX) transparency.
local SHOW_OUTLINE  = false  -- toggle the edge outline (the glow fill stays either way)
local FILL_MIN      = 0.85   -- strongest glow (lower = more white)
local FILL_MAX      = 0.95   -- faintest glow — the gap MIN..MAX is the visible "breath"
local OUTLINE_MIN   = 0.0
local OUTLINE_MAX   = 0.4
local PULSE_SPEED   = 4      -- higher = faster pulse
local DEPTH_MODE    = Enum.HighlightDepthMode.Occluded  -- hide highlight behind walls/occluders
local HIGHLIGHT_BUILD_DELAY = 0.06 -- short delay prevents visible flicker right after helper Humanoid insertion
local RAMP_SPEED_MULTIPLIER = 0.5 -- first and last pulse are slower (half speed)

local highlights   = {}  -- [target Instance] = Highlight
local shownPrompts = {}  -- [ProximityPrompt] = true while its prompt is visible
local helperHumanoids = {} -- [target Model] = persistent Humanoid for transparent highlight support
local pendingHighlight = {} -- [target] = timestamp; delay highlight until model settles
local pulseState = {} -- [target] = {phase="ramp_in"|"steady"|"ramp_out", startedAt=number, holdFill=number}

-- ─── Helpers ──────────────────────────────────────────────────────
local function targetForPrompt(prompt)
	local part = prompt.Parent
	if part then
		local model = part:FindFirstAncestorWhichIsA("Model")
		if model then return model end
	end
	return part
end

local function instPos(inst)
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then
		local ok, cf = pcall(function() return inst:GetPivot() end)
		if ok then return cf.Position end
	end
	return nil
end

-- Always highlight a whole Model rather than a lone part, so a tag on
-- any sub-part still outlines the entire object as one silhouette.
local function resolveTarget(inst)
	if inst:IsA("Model") then return inst end
	local model = inst:FindFirstAncestorWhichIsA("Model")
	return model or inst
end

local function ensureHelperHumanoid(model)
	local existing = model:FindFirstChildOfClass("Humanoid")
	if existing then return existing end
	local cached = helperHumanoids[model]
	if cached and cached.Parent == model then return cached end

	local hum = Instance.new("Humanoid")
	hum.Name = "_InteractHighlightHumanoid"
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.Parent = model
	helperHumanoids[model] = hum
	return hum
end

local function ensureHighlight(target)
	if highlights[target] then return end

	-- Roblox Highlight can fail on transparent/glass meshes. We add a
	-- local helper Humanoid once, then wait a tiny moment so rendering
	-- settles before showing the Highlight (prevents pop/flicker).
	if target:IsA("Model") then
		ensureHelperHumanoid(target)
		local t0 = pendingHighlight[target]
		if not t0 then
			pendingHighlight[target] = os.clock()
			return
		end
		if os.clock() - t0 < HIGHLIGHT_BUILD_DELAY then return end
		pendingHighlight[target] = nil
	end

	local hl = Instance.new("Highlight")
	hl.Name                = "InteractHighlight"
	hl.DepthMode           = DEPTH_MODE
	hl.OutlineColor        = OUTLINE_COLOR
	hl.FillColor           = FILL_COLOR
	hl.FillTransparency    = FILL_MIN
	hl.OutlineTransparency = SHOW_OUTLINE and OUTLINE_MIN or 1
	hl.Adornee             = target
	hl.Parent              = target
	highlights[target] = hl
	pulseState[target] = { phase = "ramp_in", startedAt = os.clock() }
end

local function beginRampOut(target, holdFill)
	local st = pulseState[target]
	if st and st.phase == "ramp_out" then return end
	pulseState[target] = {
		phase = "ramp_out",
		startedAt = os.clock(),
		holdFill = holdFill or FILL_MIN,
	}
end

local function clearHighlight(target)
	local hl = highlights[target]
	if hl then
		hl:Destroy()
		highlights[target] = nil
	end
	pendingHighlight[target] = nil
	pulseState[target] = nil
end

-- ─── ProximityPrompt source ───────────────────────────────────────
local function hookPrompt(inst)
	if not inst:IsA("ProximityPrompt") then return end
	inst.PromptShown:Connect(function() shownPrompts[inst] = true end)
	inst.PromptHidden:Connect(function() shownPrompts[inst] = nil end)
	inst.AncestryChanged:Connect(function()
		if not inst.Parent then shownPrompts[inst] = nil end
	end)
end

for _, d in workspace:GetDescendants() do hookPrompt(d) end
workspace.DescendantAdded:Connect(hookPrompt)

-- Pre-warm helper Humanoids for tagged models so the first nearby
-- highlight does not cause a visible model pop.
for _, inst in CollectionService:GetTagged(TAG) do
	local tgt = resolveTarget(inst)
	if tgt and tgt:IsA("Model") then
		ensureHelperHumanoid(tgt)
	end
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
	local tgt = resolveTarget(inst)
	if tgt and tgt:IsA("Model") then
		ensureHelperHumanoid(tgt)
	end
end)

-- ─── Per-frame: decide who glows, then pulse ──────────────────────
RunService.RenderStepped:Connect(function()
	local wanted = {}

	-- 1. Objects whose ProximityPrompt is on screen.
	for prompt in pairs(shownPrompts) do
		if prompt.Parent then
			local tgt = targetForPrompt(prompt)
			if tgt then wanted[tgt] = true end
		else
			shownPrompts[prompt] = nil
		end
	end

	-- 2. Tagged "Interactable" objects within range of the player.
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		for _, inst in CollectionService:GetTagged(TAG) do
			local pos = instPos(inst)
			if pos and (pos - hrp.Position).Magnitude <= HIGHLIGHT_RANGE then
				wanted[resolveTarget(inst)] = true
			end
		end
	end

	-- Sync highlights to the wanted set.
	for tgt in pairs(wanted) do
		ensureHighlight(tgt)
		local st = pulseState[tgt]
		if st and st.phase == "ramp_out" then
			pulseState[tgt] = { phase = "steady", startedAt = os.clock() }
		end
	end
	for tgt, hl in pairs(highlights) do
		if (not wanted[tgt] or not tgt.Parent) then
			if tgt.Parent then
				beginRampOut(tgt, hl.FillTransparency)
			else
				clearHighlight(tgt)
				helperHumanoids[tgt] = nil
			end
		end
	end

	-- Per-target pulse with smooth ramp-in/ramp-out phases.
	local now = os.clock()
	for tgt, hl in pairs(highlights) do
		local st = pulseState[tgt] or { phase = "steady", startedAt = now }
		pulseState[tgt] = st
		local fill = FILL_MIN
		local outline = SHOW_OUTLINE and OUTLINE_MIN or 1

		if st.phase == "ramp_in" then
			local dur = (1 / PULSE_SPEED) / RAMP_SPEED_MULTIPLIER
			local a = math.clamp((now - st.startedAt) / dur, 0, 1)
			fill = 1 + (FILL_MIN - 1) * a
			outline = SHOW_OUTLINE and (1 + (OUTLINE_MIN - 1) * a) or 1
			if a >= 1 then
				st.phase = "steady"
				st.startedAt = now
			end
		elseif st.phase == "ramp_out" then
			local dur = (1 / PULSE_SPEED) / RAMP_SPEED_MULTIPLIER
			local a = math.clamp((now - st.startedAt) / dur, 0, 1)
			local fromFill = st.holdFill or FILL_MIN
			fill = fromFill + (1 - fromFill) * a
			local fromOutline = SHOW_OUTLINE and OUTLINE_MIN or 1
			outline = SHOW_OUTLINE and (fromOutline + (1 - fromOutline) * a) or 1
			if a >= 1 then
				clearHighlight(tgt)
			end
		else
			local t = (math.sin(now * PULSE_SPEED) + 1) / 2
			fill = FILL_MIN + (FILL_MAX - FILL_MIN) * t
			outline = SHOW_OUTLINE and (OUTLINE_MIN + (OUTLINE_MAX - OUTLINE_MIN) * t) or 1
		end

		hl.FillTransparency = fill
		hl.OutlineTransparency = outline
	end
end)
