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

local highlights   = {}  -- [target Instance] = Highlight
local shownPrompts = {}  -- [ProximityPrompt] = true while its prompt is visible
local helperHumanoids = {} -- [target Model] = persistent Humanoid for transparent highlight support
local pendingHighlight = {} -- [target] = timestamp; delay highlight until model settles

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
end

local function clearHighlight(target)
	local hl = highlights[target]
	if hl then
		hl:Destroy()
		highlights[target] = nil
	end
	pendingHighlight[target] = nil
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
	for tgt in pairs(wanted) do ensureHighlight(tgt) end
	for tgt in pairs(highlights) do
		if not wanted[tgt] or not tgt.Parent then
			clearHighlight(tgt)
			if not tgt.Parent then helperHumanoids[tgt] = nil end
		end
	end

	-- Pulse fill + outline together — the whole surface breathes white.
	if next(highlights) then
		local t = (math.sin(os.clock() * PULSE_SPEED) + 1) / 2
		local fill    = FILL_MIN + (FILL_MAX - FILL_MIN) * t
		local outline = SHOW_OUTLINE and (OUTLINE_MIN + (OUTLINE_MAX - OUTLINE_MIN) * t) or 1
		for _, hl in pairs(highlights) do
			hl.FillTransparency    = fill
			hl.OutlineTransparency = outline
		end
	end
end)
