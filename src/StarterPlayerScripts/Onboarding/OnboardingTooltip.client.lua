-- OnboardingTooltip.client.lua
-- Wood/paper-styled hint widget that floats in the upper-left of the
-- screen below the Roblox CoreGui. Modelled after the Claude Design
-- "Onboarding Tooltip.html" mockup; built incrementally so each step's
-- commit is testable on its own.
--
-- This file (Step 1A) installs the scaffold:
--   * palette tokens lifted from the Claude Design CSS variables,
--   * font tokens (Roblox stand-in for Trebuchet MS),
--   * common geometry helpers (corner, stroke, padding),
--   * a stub _G.ShowOnboardingTip that warns "not yet implemented" so
--     callers wired up in advance get a clear message instead of a
--     silent miss.
-- Steps 1B-1F replace the stub with real visuals + animations.
--
-- Public API (final, planned for Step 1F):
--   handle = _G.ShowOnboardingTip({
--       id          = "chopTrees",
--       eyebrow     = "HINT",
--       title       = "Chop down trees",
--       body        = "Use your axe on a floating tree to gather logs.",
--       iconKind    = "axe",                  -- axe|log|drop|fish
--       iconImage   = "rbxassetid://...",     -- overrides iconKind
--       goal        = 3,                       -- nil → no progress bar
--       progress    = 0,
--       showClose   = true,
--       onDismiss   = function() ... end,
--       onComplete  = function() ... end,
--       autoDismissAfterComplete = 1.5,
--   })
--   handle.setProgress(n)
--   handle.complete()
--   handle.dismiss()
--   handle.instance       -- the panel Frame (read-only)

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── Palette (lifted from Claude Design CSS variables) ────────────────
-- Numeric hex from the mockup, converted to Color3 for Roblox.
local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23) -- body text, deep border
local COLOR_WOOD_DARK    = Color3.fromRGB( 91,  58,  34) -- secondary border
local COLOR_WOOD_MID     = Color3.fromRGB(138, 106,  68) -- close button, secondary action
local COLOR_WOOD_BASE    = Color3.fromRGB(176, 138,  92) -- main panel fill
local COLOR_WOOD_LIGHT   = Color3.fromRGB(201, 168, 119)
local COLOR_PAPER        = Color3.fromRGB(233, 217, 184) -- body card + icon-box fill
local COLOR_PAPER_LIGHT  = Color3.fromRGB(243, 230, 204) -- close button glyph
local COLOR_GREEN        = Color3.fromRGB( 74, 124,  58) -- progress fill mid
local COLOR_GREEN_LIGHT  = Color3.fromRGB(111, 168,  74) -- progress fill highlight
local COLOR_GREEN_DARK   = Color3.fromRGB( 61, 102,  48) -- progress fill shadow
local COLOR_HIGHLIGHT_W  = Color3.fromRGB(255, 255, 255) -- inner inset stroke (with alpha)

-- Trebuchet MS isn't shipped in Roblox; GothamBold reads similarly weighty
-- and matches the rest of the phone-menu typography we already use.
local FONT_TITLE = Enum.Font.GothamBold
local FONT_BODY  = Enum.Font.Gotham

-- Standard tooltip sizes (slightly narrower than the 440-wide centred
-- mockup since we're anchoring to the corner of the screen, not the
-- middle).
local TOOLTIP_WIDTH    = 320
local TOOLTIP_PAD      = 14
local TOOLTIP_MARGIN_X = 16   -- distance from screen edge
local TOOLTIP_MARGIN_Y = 16   -- distance from top edge (after GUI inset)

local RADIUS_LG = 18  -- outer panel
local RADIUS_MD = 12  -- inner cards
local RADIUS_SM = 8   -- close button

-- ─── Geometry helpers ─────────────────────────────────────────────────

local function corner(parent, radiusPx)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radiusPx or RADIUS_MD)
	c.Parent = parent
	return c
end

local function stroke(parent, thicknessPx, color, transparency)
	local s = Instance.new("UIStroke")
	s.Thickness = thicknessPx or 2
	s.Color     = color or COLOR_WOOD_DARK
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function padding(parent, all)
	local p = Instance.new("UIPadding")
	p.PaddingTop    = UDim.new(0, all)
	p.PaddingBottom = UDim.new(0, all)
	p.PaddingLeft   = UDim.new(0, all)
	p.PaddingRight  = UDim.new(0, all)
	p.Parent = parent
	return p
end

-- ─── Singleton ScreenGui ──────────────────────────────────────────────
-- Lazy-built on first show. High DisplayOrder so the tip sits above
-- the rest of our UI (PhoneMenu uses 100; 200 keeps us comfortably on
-- top); IgnoreGuiInset stays false so we don't clip into Roblox's
-- top-bar buttons.

local screenGui

local function ensureScreenGui()
	if screenGui and screenGui.Parent then return screenGui end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "OnboardingTooltipGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 200
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui
	return screenGui
end

-- ─── Public API stub (Step 1A) ────────────────────────────────────────
-- Real implementation lands in Step 1B+. The stub returns a handle
-- shaped like the final API so callers wired up in Step 2 can be
-- written + reviewed before the visuals are done.

local function showOnboardingTip(opts)
	opts = opts or {}
	warn(string.format(
		"[OnboardingTooltip] _G.ShowOnboardingTip is a stub — visuals land in Step 1B. "
		.. "Called for id=%s title=%q",
		tostring(opts.id), tostring(opts.title)))

	-- Reserve the GUI host so anything that probes for the screen gui
	-- (e.g. occlusion checks similar to _G.PhoneScreenGui) finds the
	-- right Instance even before Step 1B paints anything into it.
	ensureScreenGui()

	local handle = {
		instance    = nil,
		setProgress = function() end,
		complete    = function() end,
		dismiss     = function() end,
	}
	return handle
end

_G.ShowOnboardingTip = showOnboardingTip
