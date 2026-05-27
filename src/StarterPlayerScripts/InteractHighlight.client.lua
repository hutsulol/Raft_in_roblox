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
local FILL_TRANSP   = 0.85   -- faint inner glow; 1 = outline-only
local OUTLINE_MIN   = 0.0    -- brightest point of the pulse
local OUTLINE_MAX   = 0.5    -- dimmest point of the pulse
local PULSE_SPEED   = 4      -- higher = faster pulse
local DEPTH_MODE    = Enum.HighlightDepthMode.Occluded  -- AlwaysOnTop = glow through walls

local highlights   = {}  -- [target Instance] = Highlight
local shownPrompts = {}  -- [ProximityPrompt] = true while its prompt is visible

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

local function ensureHighlight(target)
	if highlights[target] then return end
	local hl = Instance.new("Highlight")
	hl.Name                = "InteractHighlight"
	hl.DepthMode           = DEPTH_MODE
	hl.OutlineColor        = OUTLINE_COLOR
	hl.FillColor           = FILL_COLOR
	hl.FillTransparency    = FILL_TRANSP
	hl.OutlineTransparency = OUTLINE_MIN
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
				wanted[inst] = true
			end
		end
	end

	-- Sync highlights to the wanted set.
	for tgt in pairs(wanted) do ensureHighlight(tgt) end
	for tgt in pairs(highlights) do
		if not wanted[tgt] or not tgt.Parent then clearHighlight(tgt) end
	end

	-- Pulse them all together.
	if next(highlights) then
		local t = (math.sin(os.clock() * PULSE_SPEED) + 1) / 2
		local outline = OUTLINE_MIN + (OUTLINE_MAX - OUTLINE_MIN) * t
		for _, hl in pairs(highlights) do
			hl.OutlineTransparency = outline
		end
	end
end)
