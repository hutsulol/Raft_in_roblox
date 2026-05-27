-- InteractHighlight.client.lua
-- Animated white outline on whatever the player can currently
-- interact with. Hooks every ProximityPrompt's PromptShown /
-- PromptHidden so the glow appears exactly while the prompt is on
-- screen, and pulses the outline each frame for a "living" look.
--
-- Drop this in StarterPlayerScripts. Any object that has a
-- ProximityPrompt (campfire, furnace, the rum bottle, etc.) glows
-- automatically — no per-object wiring needed.

local RunService = game:GetService("RunService")

-- ─── Look / feel ──────────────────────────────────────────────────
local OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)
local FILL_COLOR    = Color3.fromRGB(255, 255, 255)
local FILL_TRANSP   = 0.85   -- faint inner glow; set to 1 for outline-only
local OUTLINE_MIN   = 0.0    -- brightest point of the pulse
local OUTLINE_MAX   = 0.5    -- dimmest point of the pulse
local PULSE_SPEED   = 4      -- higher = faster pulse
-- Occluded: outline only where the object is actually visible (natural).
-- Swap to AlwaysOnTop to let it glow through walls.
local DEPTH_MODE    = Enum.HighlightDepthMode.Occluded

local active = {}  -- [prompt] = Highlight

local function targetFor(prompt)
	-- Prefer the whole interactable Model; fall back to the part the
	-- prompt is parented to.
	local part = prompt.Parent
	if part then
		local model = part:FindFirstAncestorWhichIsA("Model")
		if model then return model end
	end
	return part
end

local function addHighlight(prompt)
	if active[prompt] then return end
	local target = targetFor(prompt)
	if not target then return end

	local hl = Instance.new("Highlight")
	hl.Name                = "InteractHighlight"
	hl.DepthMode           = DEPTH_MODE
	hl.OutlineColor        = OUTLINE_COLOR
	hl.FillColor           = FILL_COLOR
	hl.FillTransparency    = FILL_TRANSP
	hl.OutlineTransparency = OUTLINE_MIN
	hl.Adornee             = target
	hl.Parent              = target
	active[prompt] = hl
end

local function removeHighlight(prompt)
	local hl = active[prompt]
	if hl then
		hl:Destroy()
		active[prompt] = nil
	end
end

local function hook(inst)
	if not inst:IsA("ProximityPrompt") then return end
	inst.PromptShown:Connect(function() addHighlight(inst) end)
	inst.PromptHidden:Connect(function() removeHighlight(inst) end)
	inst.AncestryChanged:Connect(function()
		if not inst.Parent then removeHighlight(inst) end
	end)
end

for _, d in workspace:GetDescendants() do hook(d) end
workspace.DescendantAdded:Connect(hook)

-- Pulse every active outline together.
RunService.RenderStepped:Connect(function()
	if next(active) == nil then return end
	local t = (math.sin(os.clock() * PULSE_SPEED) + 1) / 2  -- 0..1
	local outline = OUTLINE_MIN + (OUTLINE_MAX - OUTLINE_MIN) * t
	for prompt, hl in active do
		if hl.Parent then
			hl.OutlineTransparency = outline
		else
			active[prompt] = nil
		end
	end
end)
