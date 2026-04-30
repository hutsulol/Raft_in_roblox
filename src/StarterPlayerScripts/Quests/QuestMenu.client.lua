-- QuestMenu.client.lua
-- Full-screen quest log opened by the left-side QuestEntryButton or
-- the J key. Builds incrementally across B1 → B10 so each commit is
-- testable on its own.
--
-- B1 scope: lazy ScreenGui host + _G.OpenQuestMenu / _G.CloseQuestMenu
-- stubs that flip the host's Enabled flag. Nothing visible yet —
-- B2 lands the wood panel, B3 the tab rail, etc.
--
-- DisplayOrder 110 sits above PhoneMenu (200? actually phone uses
-- 200 for its main screenGui; the OnboardingTooltip uses 200 too,
-- and QuestNotificationGui uses 8). Lifting QuestMenu to 110 keeps
-- it ABOVE in-game HUD and the QuestEntryButton (90) but BELOW the
-- phone if both happen to be open — phone takes precedence as the
-- bigger, more deliberate UI.
--
-- Public API (final shape across B1 → B10):
--   _G.OpenQuestMenu()    -- show the menu (no-op if already open)
--   _G.CloseQuestMenu()   -- hide the menu (no-op if already hidden)

local Players = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SCREENGUI_DISPLAY_ORDER = 110

-- ─── Wood/paper palette (matches OnboardingTooltip + Claude Design
-- handoff) ────────────────────────────────────────────────────────────
local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_WOOD_DARK    = Color3.fromRGB( 91,  58,  34)
local COLOR_WOOD_MID     = Color3.fromRGB(138, 106,  68)
local COLOR_WOOD_BASE    = Color3.fromRGB(176, 138,  92)
local COLOR_PAPER        = Color3.fromRGB(233, 217, 184)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(243, 230, 204)

-- ─── Layout constants ────────────────────────────────────────────────
local PANEL_W      = 540
local PANEL_H      = 360
local PANEL_RADIUS = 18
local PANEL_PAD    = 14

-- Lazy build: the ScreenGui isn't created until the menu is first
-- opened. Cuts the cost of one always-resident GUI for players who
-- never open the quest log. Panel + tabs + content are also built
-- once during ensureScreenGui's first call.
local screenGui
local panel        -- the wood panel root (built in B2)

local function buildPanel(parent)
	-- Outer wood panel: same recipe as the onboarding tooltip's
	-- panel — wood-base fill, 3 px wood-dark border, inner 1 px
	-- white-18% inset highlight stroke. Centred in the screen via
	-- AnchorPoint (0.5, 0.5).
	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.BackgroundColor3 = COLOR_WOOD_BASE
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Parent = parent

	local pCorner = Instance.new("UICorner")
	pCorner.CornerRadius = UDim.new(0, PANEL_RADIUS)
	pCorner.Parent = panel

	local pStroke = Instance.new("UIStroke")
	pStroke.Color = COLOR_WOOD_DARK
	pStroke.Thickness = 3
	pStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	pStroke.Parent = panel

	local pPad = Instance.new("UIPadding")
	pPad.PaddingTop    = UDim.new(0, PANEL_PAD)
	pPad.PaddingBottom = UDim.new(0, PANEL_PAD)
	pPad.PaddingLeft   = UDim.new(0, PANEL_PAD)
	pPad.PaddingRight  = UDim.new(0, PANEL_PAD)
	pPad.Parent = panel

	-- Inner highlight (mockup's `.tip::before` trick): 1 px white-18%
	-- inset stroke 2 px from the outer border so the panel feels
	-- raised. Sized to overlap the parent's UIPadding so it kisses
	-- the visible edge instead of the padded box.
	local highlight = Instance.new("Frame")
	highlight.Name = "InnerHighlight"
	highlight.AnchorPoint = Vector2.new(0.5, 0.5)
	highlight.Position = UDim2.fromScale(0.5, 0.5)
	highlight.Size = UDim2.new(1, (PANEL_PAD - 2) * 2, 1, (PANEL_PAD - 2) * 2)
	highlight.BackgroundTransparency = 1
	highlight.BorderSizePixel = 0
	highlight.ZIndex = 3
	highlight.Parent = panel
	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, PANEL_RADIUS - 4)
	hCorner.Parent = highlight
	local hStroke = Instance.new("UIStroke")
	hStroke.Color = Color3.fromRGB(255, 255, 255)
	hStroke.Thickness = 1
	hStroke.Transparency = 0.82
	hStroke.Parent = highlight

	return panel
end

local function ensureScreenGui()
	if screenGui and screenGui.Parent then return screenGui end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "QuestMenuGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = SCREENGUI_DISPLAY_ORDER
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false   -- shown only after openQuestMenu()
	screenGui.Parent = playerGui

	buildPanel(screenGui)
	return screenGui
end

local function openQuestMenu()
	local gui = ensureScreenGui()
	gui.Enabled = true
end

local function closeQuestMenu()
	if not screenGui then return end
	screenGui.Enabled = false
end

_G.OpenQuestMenu  = openQuestMenu
_G.CloseQuestMenu = closeQuestMenu
