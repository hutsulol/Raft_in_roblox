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

-- ─── Built-in icon glyphs (axe / log / drop / fish) ───────────────────
-- Each builder draws its glyph as a set of Frames + UICorners centred
-- in `parent`. Approximations of the SVG icons in the Claude Design
-- mockup (Roblox doesn't draw arbitrary paths, so curved bits become
-- rounded-corner rectangles and "diamonds" become Rotation = 45 Frames).
-- All builders share a 38×38 design space mapped to a `sizePx`-sided
-- container that's centred in the icon box. Returns the container
-- Frame so the pulse animator in Step 1F can target a single node.

local ICON_COL_AXE_WOOD       = Color3.fromRGB(164, 113,  72) -- handle
local ICON_COL_AXE_METAL      = Color3.fromRGB(184, 184, 184)
local ICON_COL_AXE_METAL_DARK = Color3.fromRGB(110, 110, 110)
local ICON_COL_LOG_WOOD       = Color3.fromRGB(164, 113,  72) -- middle barrel
local ICON_COL_LOG_DARK       = Color3.fromRGB(122,  79,  43) -- end caps
local ICON_COL_LOG_RING       = Color3.fromRGB( 90,  56,  25) -- inner ring
local ICON_COL_DROP_BLUE      = Color3.fromRGB( 74, 144, 200)
local ICON_COL_DROP_HIGHLIGHT = Color3.fromRGB(207, 230, 245)
local ICON_COL_FISH_BODY      = Color3.fromRGB(201, 122,  58)
local ICON_COL_FISH_TAIL      = Color3.fromRGB(168,  90,  34)
local ICON_COL_OUTLINE        = COLOR_WOOD_DARKEST

local function makeIconContainer(parent, sizePx)
	local c = Instance.new("Frame")
	c.Name = "IconGlyph"
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	c.Position = UDim2.fromScale(0.5, 0.5)
	c.Size = UDim2.fromOffset(sizePx, sizePx)
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.ZIndex = (parent.ZIndex or 1) + 1
	c.Parent = parent
	return c
end

local function makeAxeIcon(parent, sizePx)
	local c = makeIconContainer(parent, sizePx)
	local s = sizePx
	-- Handle: a thin wood-coloured strip rotated 22° so the axe has
	-- the diagonal pose from the mockup. Anchored just below centre
	-- so the head sits at the top-left when rotated.
	local handle = Instance.new("Frame")
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.Position = UDim2.new(0.55, 0, 0.55, 0)
	handle.Size = UDim2.fromOffset(math.max(2, math.floor(s * 0.10)), math.floor(s * 0.78))
	handle.BackgroundColor3 = ICON_COL_AXE_WOOD
	handle.BorderSizePixel = 0
	handle.Rotation = 22
	handle.ZIndex = c.ZIndex
	handle.Parent = c
	corner(handle, 2)
	stroke(handle, 1, ICON_COL_OUTLINE)

	-- Blade: a wider grey rectangle rotated to suggest the axe head's
	-- wedge silhouette. Two stacked rotations (the visible blade and
	-- a thinner darker strip behind it) read as "axe" at small sizes
	-- without needing real polygons.
	local blade = Instance.new("Frame")
	blade.AnchorPoint = Vector2.new(0.5, 0.5)
	blade.Position = UDim2.new(0.32, 0, 0.32, 0)
	blade.Size = UDim2.fromOffset(math.floor(s * 0.46), math.floor(s * 0.28))
	blade.BackgroundColor3 = ICON_COL_AXE_METAL
	blade.BorderSizePixel = 0
	blade.Rotation = -18
	blade.ZIndex = c.ZIndex + 1
	blade.Parent = c
	corner(blade, 3)
	stroke(blade, 1, ICON_COL_OUTLINE)

	-- Inner shadow line on the blade (dark stripe) so the head reads
	-- as having a forged ridge rather than a flat slab.
	local edge = Instance.new("Frame")
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Position = UDim2.new(0.32, 0, 0.32, 0)
	edge.Size = UDim2.fromOffset(math.floor(s * 0.32), math.max(1, math.floor(s * 0.05)))
	edge.BackgroundColor3 = ICON_COL_AXE_METAL_DARK
	edge.BorderSizePixel = 0
	edge.Rotation = -18
	edge.ZIndex = c.ZIndex + 2
	edge.Parent = c

	return c
end

local function makeLogIcon(parent, sizePx)
	local c = makeIconContainer(parent, sizePx)
	local s = sizePx
	-- Middle barrel of the log — light wood rectangle.
	local barrel = Instance.new("Frame")
	barrel.AnchorPoint = Vector2.new(0.5, 0.5)
	barrel.Position = UDim2.new(0.5, 0, 0.5, 0)
	barrel.Size = UDim2.fromOffset(math.floor(s * 0.55), math.floor(s * 0.50))
	barrel.BackgroundColor3 = ICON_COL_LOG_WOOD
	barrel.BorderSizePixel = 0
	barrel.ZIndex = c.ZIndex
	barrel.Parent = c
	stroke(barrel, 1, ICON_COL_OUTLINE)

	-- Left end cap: tall ellipse via 100% corner radius on a vertical
	-- rectangle. Sits on the left edge of the barrel.
	local left = Instance.new("Frame")
	left.AnchorPoint = Vector2.new(1, 0.5)
	left.Position = UDim2.new(0.5, math.floor(-s * 0.27), 0.5, 0)
	left.Size = UDim2.fromOffset(math.floor(s * 0.32), math.floor(s * 0.50))
	left.BackgroundColor3 = ICON_COL_LOG_DARK
	left.BorderSizePixel = 0
	left.ZIndex = c.ZIndex + 1
	left.Parent = c
	corner(left, 1)
	-- Use scale-based corner so the radius always matches the height
	-- and the cap reads as a half-ellipse instead of a rounded rect.
	left:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
	stroke(left, 1, ICON_COL_OUTLINE)

	-- Right end cap (slightly smaller on the mockup so the log has a
	-- bit of taper from the camera angle). Plus an even darker inner
	-- "growth ring" centred inside it.
	local right = Instance.new("Frame")
	right.AnchorPoint = Vector2.new(0, 0.5)
	right.Position = UDim2.new(0.5, math.floor(s * 0.27), 0.5, 0)
	right.Size = UDim2.fromOffset(math.floor(s * 0.28), math.floor(s * 0.50))
	right.BackgroundColor3 = ICON_COL_LOG_DARK
	right.BorderSizePixel = 0
	right.ZIndex = c.ZIndex + 1
	right.Parent = c
	corner(right, 1)
	right:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
	stroke(right, 1, ICON_COL_OUTLINE)

	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.new(0.55, 0, 0.55, 0)
	ring.BackgroundColor3 = ICON_COL_LOG_RING
	ring.BorderSizePixel = 0
	ring.ZIndex = c.ZIndex + 2
	ring.Parent = right
	corner(ring, 1)
	ring:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)

	return c
end

local function makeDropIcon(parent, sizePx)
	local c = makeIconContainer(parent, sizePx)
	local s = sizePx
	-- The teardrop shape is faked by a circle with a 45° rotated
	-- square sitting on top — the square's lower half disappears
	-- behind the circle, leaving a pointed top. Both share the same
	-- blue fill so the seam is invisible.
	local round = Instance.new("Frame")
	round.AnchorPoint = Vector2.new(0.5, 0.5)
	round.Position = UDim2.new(0.5, 0, 0.62, 0)
	round.Size = UDim2.fromOffset(math.floor(s * 0.62), math.floor(s * 0.62))
	round.BackgroundColor3 = ICON_COL_DROP_BLUE
	round.BorderSizePixel = 0
	round.ZIndex = c.ZIndex + 1
	round.Parent = c
	corner(round, 1)
	round:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
	stroke(round, 1, ICON_COL_OUTLINE)

	local point = Instance.new("Frame")
	point.AnchorPoint = Vector2.new(0.5, 0.5)
	point.Position = UDim2.new(0.5, 0, 0.36, 0)
	point.Size = UDim2.fromOffset(math.floor(s * 0.42), math.floor(s * 0.42))
	point.BackgroundColor3 = ICON_COL_DROP_BLUE
	point.BorderSizePixel = 0
	point.Rotation = 45
	point.ZIndex = c.ZIndex
	point.Parent = c
	stroke(point, 1, ICON_COL_OUTLINE)

	-- Inner highlight crescent on the lower-left, suggesting reflected
	-- light. Drawn as a small rotated bar.
	local hl = Instance.new("Frame")
	hl.AnchorPoint = Vector2.new(0.5, 0.5)
	hl.Position = UDim2.new(0.36, 0, 0.74, 0)
	hl.Size = UDim2.fromOffset(math.floor(s * 0.18), math.max(2, math.floor(s * 0.06)))
	hl.BackgroundColor3 = ICON_COL_DROP_HIGHLIGHT
	hl.BorderSizePixel = 0
	hl.Rotation = -55
	hl.ZIndex = c.ZIndex + 2
	hl.Parent = c
	corner(hl, 2)

	return c
end

local function makeFishIcon(parent, sizePx)
	local c = makeIconContainer(parent, sizePx)
	local s = sizePx
	-- Body: rounded oval orange. Big corner radius makes the rectangle
	-- read as a fish body.
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.new(0.55, 0, 0.5, 0)
	body.Size = UDim2.fromOffset(math.floor(s * 0.62), math.floor(s * 0.40))
	body.BackgroundColor3 = ICON_COL_FISH_BODY
	body.BorderSizePixel = 0
	body.ZIndex = c.ZIndex
	body.Parent = c
	corner(body, 1)
	body:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
	stroke(body, 1, ICON_COL_OUTLINE)

	-- Tail: a 45°-rotated darker square at the body's left, half-
	-- hidden behind it so the visible part forms a triangle.
	local tail = Instance.new("Frame")
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.22, 0, 0.5, 0)
	tail.Size = UDim2.fromOffset(math.floor(s * 0.30), math.floor(s * 0.30))
	tail.BackgroundColor3 = ICON_COL_FISH_TAIL
	tail.BorderSizePixel = 0
	tail.Rotation = 45
	tail.ZIndex = c.ZIndex - 1
	tail.Parent = c
	stroke(tail, 1, ICON_COL_OUTLINE)

	-- Eye: small dark dot near the front (right side of body).
	local eye = Instance.new("Frame")
	eye.AnchorPoint = Vector2.new(0.5, 0.5)
	eye.Position = UDim2.new(0.74, 0, 0.46, 0)
	eye.Size = UDim2.fromOffset(math.max(2, math.floor(s * 0.06)), math.max(2, math.floor(s * 0.06)))
	eye.BackgroundColor3 = ICON_COL_OUTLINE
	eye.BorderSizePixel = 0
	eye.ZIndex = c.ZIndex + 1
	eye.Parent = c
	corner(eye, 1)
	eye:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)

	return c
end

local ICON_BUILDERS = {
	axe  = makeAxeIcon,
	log  = makeLogIcon,
	drop = makeDropIcon,
	fish = makeFishIcon,
}

-- Paints the icon box with whichever option the caller specified.
-- iconImage (rbxassetid string) wins over iconKind so a caller that
-- ships a real asset gets an exact match instead of the geometric
-- fallback. Returns the inner glyph node so the pulse animator (Step
-- 1F) has a single Instance to tween.
local function paintIconBox(iconBox, opts)
	local pad = 8  -- inset so the glyph doesn't touch the icon-box border
	if typeof(opts.iconImage) == "string" and opts.iconImage ~= "" then
		local img = Instance.new("ImageLabel")
		img.Name = "IconImage"
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.new(1, -pad * 2, 1, -pad * 2)
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.Image = opts.iconImage
		img.ScaleType = Enum.ScaleType.Fit
		img.ImageColor3 = Color3.new(1, 1, 1)
		img.ZIndex = (iconBox.ZIndex or 1) + 1
		img.Parent = iconBox
		return img
	end

	local builder = ICON_BUILDERS[opts.iconKind]
	if builder then
		local glyphSize = ICON_BOX_SIZE - pad * 2
		return builder(iconBox, glyphSize)
	end

	return nil
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

-- ─── Static tooltip build (Step 1B) ───────────────────────────────────
-- Renders the panel + header (icon box, eyebrow, title) + paper body
-- card + X close button. No animations / progress bar / icon glyph
-- yet — Steps 1C-1F layer those on. The ZIndex ladder is set up
-- ahead so later steps don't have to renumber every child:
--   2 inner highlight inset
--   3 close button
--   4 header (icon box + text)
--   5 body card
--   6 progress + future content
--   8 close button glyph (text inside the button)

local PANEL_BASE_Z   = 1
local HIGHLIGHT_Z    = PANEL_BASE_Z + 1
local CLOSE_BG_Z     = PANEL_BASE_Z + 2
local HEADER_Z       = PANEL_BASE_Z + 3
local BODY_Z         = PANEL_BASE_Z + 4
local CLOSE_GLYPH_Z  = PANEL_BASE_Z + 7

local ICON_BOX_SIZE   = 56
local CLOSE_BTN_SIZE  = 26
local HEADER_GAP      = 12

-- Single active tooltip — calling showOnboardingTip a second time
-- replaces the first. Step 1F may upgrade this to "update in place
-- if id matches" but the contract is the same.
local activeHandle

local function buildTooltipPanel(opts)
	local gui = ensureScreenGui()

	-- CanvasGroup as the panel root so the entrance / exit animations
	-- can fade the whole tooltip via a single GroupTransparency knob
	-- (no manual walk over every TextLabel / Frame / UIStroke). UIScale
	-- handles the bounce-in scale so AutomaticSize.Y on the panel still
	-- works — UIScale only multiplies the rendered size, not the
	-- layout box.
	local panel = Instance.new("CanvasGroup")
	panel.Name = "OnboardingTooltip"
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.fromOffset(TOOLTIP_MARGIN_X, TOOLTIP_MARGIN_Y)
	panel.Size = UDim2.fromOffset(TOOLTIP_WIDTH, 0)   -- height auto-fits
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = COLOR_WOOD_BASE
	panel.BorderSizePixel = 0
	panel.ZIndex = PANEL_BASE_Z
	-- Hidden until the entrance tween fades us in. GroupTransparency
	-- starts at 1.0 (fully transparent for the whole subtree) so
	-- nothing flashes on screen for a frame between buildTooltipPanel
	-- finishing and the entrance tween kicking off.
	panel.GroupTransparency = 1
	panel.Parent = gui
	corner(panel, RADIUS_LG)
	stroke(panel, 3, COLOR_WOOD_DARK)
	padding(panel, TOOLTIP_PAD)

	local panelScale = Instance.new("UIScale")
	panelScale.Scale = 0.96   -- entrance start
	panelScale.Parent = panel

	-- Inner 1px white-18% alpha highlight stroke, inset 2 px from the
	-- outer border. Same trick the mockup's `.tip::before` uses to
	-- make the wood panel feel raised.
	local highlight = Instance.new("Frame")
	highlight.Name = "InnerHighlight"
	highlight.AnchorPoint = Vector2.new(0.5, 0.5)
	highlight.Position = UDim2.fromScale(0.5, 0.5)
	-- The Frame must extend past the parent's UIPadding so the inner
	-- stroke kisses the panel's outer edge instead of the padding box.
	highlight.Size = UDim2.new(1, (TOOLTIP_PAD - 2) * 2, 1, (TOOLTIP_PAD - 2) * 2)
	highlight.BackgroundTransparency = 1
	highlight.BorderSizePixel = 0
	highlight.ZIndex = HIGHLIGHT_Z
	highlight.Parent = panel
	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, RADIUS_LG - 4)
	hCorner.Parent = highlight
	stroke(highlight, 1, COLOR_HIGHLIGHT_W, 0.82)

	-- Vertical layout inside the panel. UIListLayout + AutomaticSize.Y
	-- saves us from manually summing header + body heights every time
	-- the body wraps to a different number of lines.
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = panel

	-- ── Header row ────────────────────────────────────────────────────
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, 0, 0, ICON_BOX_SIZE)
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.ZIndex = HEADER_Z
	header.Parent = panel

	-- Icon box on the left. paintIconBox drops in either an ImageLabel
	-- (when opts.iconImage is set) or a built-in axe/log/drop/fish
	-- glyph drawn from Frames + UICorner.
	local iconBox = Instance.new("Frame")
	iconBox.Name = "IconBox"
	iconBox.AnchorPoint = Vector2.new(0, 0.5)
	iconBox.Position = UDim2.new(0, 0, 0.5, 0)
	iconBox.Size = UDim2.fromOffset(ICON_BOX_SIZE, ICON_BOX_SIZE)
	iconBox.BackgroundColor3 = COLOR_PAPER
	iconBox.BorderSizePixel = 0
	iconBox.ZIndex = HEADER_Z
	iconBox.Parent = header
	corner(iconBox, RADIUS_MD)
	stroke(iconBox, 2, COLOR_WOOD_DARK)

	local iconGlyph = paintIconBox(iconBox, opts)

	-- UIScale on the glyph drives the looping pulse (Step 1F) without
	-- fighting the icon box's fixed Size or any UIPadding inside it.
	local iconScale
	if iconGlyph then
		iconScale = Instance.new("UIScale")
		iconScale.Scale = 1
		iconScale.Parent = iconGlyph
	end

	-- Eyebrow + title stack to the right of the icon box.
	local titles = Instance.new("Frame")
	titles.Name = "Titles"
	titles.AnchorPoint = Vector2.new(0, 0.5)
	titles.Position = UDim2.new(0, ICON_BOX_SIZE + HEADER_GAP, 0.5, 0)
	titles.Size = UDim2.new(1, -(ICON_BOX_SIZE + HEADER_GAP + CLOSE_BTN_SIZE + 8), 1, 0)
	titles.BackgroundTransparency = 1
	titles.BorderSizePixel = 0
	titles.ZIndex = HEADER_Z
	titles.Parent = header

	local eyebrow = Instance.new("TextLabel")
	eyebrow.Name = "Eyebrow"
	eyebrow.AnchorPoint = Vector2.new(0, 0)
	eyebrow.Position = UDim2.fromOffset(0, 4)
	eyebrow.Size = UDim2.new(1, 0, 0, 14)
	eyebrow.BackgroundTransparency = 1
	eyebrow.BorderSizePixel = 0
	eyebrow.Font = FONT_TITLE
	eyebrow.TextSize = 11
	eyebrow.TextColor3 = COLOR_WOOD_DARKEST
	eyebrow.TextTransparency = 0.35   -- mockup uses rgba(61,40,23,.65)
	eyebrow.TextXAlignment = Enum.TextXAlignment.Left
	eyebrow.TextYAlignment = Enum.TextYAlignment.Top
	eyebrow.Text = string.upper(tostring(opts.eyebrow or "HINT"))
	eyebrow.ZIndex = HEADER_Z
	eyebrow.Parent = titles

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0, 0)
	title.Position = UDim2.fromOffset(0, 22)
	title.Size = UDim2.new(1, 0, 0, 26)
	title.BackgroundTransparency = 1
	title.BorderSizePixel = 0
	title.Font = FONT_TITLE
	title.TextSize = 20
	title.TextColor3 = COLOR_WOOD_DARKEST
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = tostring(opts.title or "")
	title.ZIndex = HEADER_Z
	title.Parent = titles

	-- ── Close button (top-right of the panel) ─────────────────────────
	local closeBtn
	if opts.showClose ~= false then
		closeBtn = Instance.new("TextButton")
		closeBtn.Name = "CloseButton"
		closeBtn.AnchorPoint = Vector2.new(1, 0)
		-- Anchored to the panel's top-right corner, then nudged out
		-- past the parent UIPadding so it lands 8 px from the visible
		-- panel edge — same offset the mockup's `.close-btn` uses.
		-- (padding - desiredMargin) = (14 - 8) = 6.
		closeBtn.Position = UDim2.new(1, TOOLTIP_PAD - 8, 0, -(TOOLTIP_PAD - 8))
		closeBtn.Size = UDim2.fromOffset(CLOSE_BTN_SIZE, CLOSE_BTN_SIZE)
		closeBtn.BackgroundColor3 = COLOR_WOOD_MID
		closeBtn.BorderSizePixel = 0
		closeBtn.AutoButtonColor = false
		closeBtn.Text = ""
		closeBtn.ZIndex = CLOSE_BG_Z
		closeBtn.Parent = panel
		corner(closeBtn, RADIUS_SM)
		stroke(closeBtn, 2, COLOR_WOOD_DARK)

		local glyph = Instance.new("TextLabel")
		glyph.BackgroundTransparency = 1
		glyph.BorderSizePixel = 0
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.Font = FONT_TITLE
		glyph.TextSize = 14
		glyph.TextColor3 = COLOR_PAPER_LIGHT
		glyph.Text = "✕"
		glyph.ZIndex = CLOSE_GLYPH_Z
		glyph.Parent = closeBtn

		-- Pressed-state visual feedback (mockup uses a 1px shift +
		-- darker fill on :active / :hover).
		closeBtn.MouseEnter:Connect(function()
			closeBtn.BackgroundColor3 = COLOR_WOOD_DARK
		end)
		closeBtn.MouseLeave:Connect(function()
			closeBtn.BackgroundColor3 = COLOR_WOOD_MID
		end)
	end

	-- ── Body card (paper-fill) ────────────────────────────────────────
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.LayoutOrder = 2
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundColor3 = COLOR_PAPER
	body.BorderSizePixel = 0
	body.ZIndex = BODY_Z
	body.Parent = panel
	corner(body, RADIUS_MD)
	stroke(body, 2, COLOR_WOOD_DARK)

	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingTop    = UDim.new(0, 12)
	bodyPad.PaddingBottom = UDim.new(0, 12)
	bodyPad.PaddingLeft   = UDim.new(0, 14)
	bodyPad.PaddingRight  = UDim.new(0, 14)
	bodyPad.Parent = body

	-- Vertical stack inside the body card so bodyText + progress row
	-- auto-flow without manually summing heights every render. Step 1D
	-- adds the progress row as a second child.
	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.FillDirection = Enum.FillDirection.Vertical
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 10)
	bodyLayout.Parent = body

	local bodyText = Instance.new("TextLabel")
	bodyText.Name = "BodyText"
	bodyText.LayoutOrder = 1
	bodyText.Size = UDim2.new(1, 0, 0, 0)
	bodyText.AutomaticSize = Enum.AutomaticSize.Y
	bodyText.BackgroundTransparency = 1
	bodyText.BorderSizePixel = 0
	bodyText.Font = FONT_BODY
	bodyText.TextSize = 15
	bodyText.TextColor3 = Color3.fromRGB(46, 29, 16) -- mockup #2e1d10
	bodyText.TextXAlignment = Enum.TextXAlignment.Left
	bodyText.TextYAlignment = Enum.TextYAlignment.Top
	bodyText.TextWrapped = true
	bodyText.RichText = true
	bodyText.LineHeight = 1.25
	bodyText.Text = tostring(opts.body or "")
	bodyText.ZIndex = BODY_Z
	bodyText.Parent = body

	-- ── Progress row (only rendered when opts.goal is a positive int) ─
	-- Pill track + green-gradient fill + "N/M" label. Mirrors the
	-- mockup's `.progress-wrap`. Fill width tweens from old → new on
	-- handle.setProgress(n).
	local progressTrack, progressFill, progressLabel
	local goalRaw = tonumber(opts.goal)
	local goal = (goalRaw and goalRaw > 0) and math.floor(goalRaw) or nil
	if goal then
		local progressWrap = Instance.new("Frame")
		progressWrap.Name = "ProgressWrap"
		progressWrap.LayoutOrder = 2
		progressWrap.Size = UDim2.new(1, 0, 0, 14)
		progressWrap.BackgroundTransparency = 1
		progressWrap.BorderSizePixel = 0
		progressWrap.ZIndex = BODY_Z
		progressWrap.Parent = body

		-- Reserve a small fixed slot on the right for the "N/M" label
		-- so the track + label never overlap regardless of goal size.
		local LABEL_W = 44
		local LABEL_GAP = 10

		progressTrack = Instance.new("Frame")
		progressTrack.Name = "Track"
		progressTrack.AnchorPoint = Vector2.new(0, 0.5)
		progressTrack.Position = UDim2.new(0, 0, 0.5, 0)
		progressTrack.Size = UDim2.new(1, -(LABEL_W + LABEL_GAP), 1, 0)
		-- Mockup background: rgba(0,0,0,.18) — solid dark with low
		-- alpha. Roblox doesn't blend Frame fills with the parent the
		-- same way CSS does (BackgroundTransparency only, no real
		-- alpha-multiply on color), so use a near-black colour with
		-- partial transparency to land on the same visual.
		progressTrack.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		progressTrack.BackgroundTransparency = 0.82
		progressTrack.BorderSizePixel = 0
		progressTrack.ClipsDescendants = true     -- so the fill can't poke past the pill
		progressTrack.ZIndex = BODY_Z + 1
		progressTrack.Parent = progressWrap
		corner(progressTrack, 999)
		stroke(progressTrack, 2, COLOR_WOOD_DARK)

		progressFill = Instance.new("Frame")
		progressFill.Name = "Fill"
		progressFill.AnchorPoint = Vector2.new(0, 0.5)
		progressFill.Position = UDim2.new(0, 0, 0.5, 0)
		progressFill.Size = UDim2.new(0, 0, 1, 0) -- starts empty; setProgress fills it
		progressFill.BackgroundColor3 = COLOR_GREEN
		progressFill.BorderSizePixel = 0
		progressFill.ZIndex = BODY_Z + 2
		progressFill.Parent = progressTrack

		-- Vertical gradient: light → mid → dark. Mockup uses
		-- `linear-gradient(180deg, #6fa84a, var(--green) 60%, #3d6630)`.
		local fillGrad = Instance.new("UIGradient")
		fillGrad.Rotation = 90
		fillGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    COLOR_GREEN_LIGHT),
			ColorSequenceKeypoint.new(0.6,  COLOR_GREEN),
			ColorSequenceKeypoint.new(1,    COLOR_GREEN_DARK),
		})
		fillGrad.Parent = progressFill

		progressLabel = Instance.new("TextLabel")
		progressLabel.Name = "Label"
		progressLabel.AnchorPoint = Vector2.new(1, 0.5)
		progressLabel.Position = UDim2.new(1, 0, 0.5, 0)
		progressLabel.Size = UDim2.fromOffset(LABEL_W, 16)
		progressLabel.BackgroundTransparency = 1
		progressLabel.BorderSizePixel = 0
		progressLabel.Font = FONT_TITLE
		progressLabel.TextSize = 14
		progressLabel.TextColor3 = COLOR_WOOD_DARK -- not-done default; turns green when done
		progressLabel.TextXAlignment = Enum.TextXAlignment.Right
		progressLabel.TextYAlignment = Enum.TextYAlignment.Center
		progressLabel.Text = "0/" .. tostring(goal)
		progressLabel.ZIndex = BODY_Z + 1
		progressLabel.Parent = progressWrap
	end

	return {
		panel          = panel,
		panelScale     = panelScale,
		header         = header,
		iconBox        = iconBox,
		iconGlyph      = iconGlyph,
		iconScale      = iconScale,       -- nil when no glyph
		eyebrow        = eyebrow,
		title          = title,
		body           = body,
		bodyText       = bodyText,
		closeBtn       = closeBtn,
		progressTrack  = progressTrack,   -- nil when no progress bar
		progressFill   = progressFill,
		progressLabel  = progressLabel,
		goal           = goal,
	}
end

-- ─── Public API ───────────────────────────────────────────────────────

local function showOnboardingTip(opts)
	opts = opts or {}

	-- One tooltip at a time: dismiss the current one before painting
	-- the new one. Step 1F can extend this to "update in place when
	-- the id matches" so progress updates don't replay the entrance.
	if activeHandle and activeHandle.dismiss then
		activeHandle.dismiss()
	end

	local refs = buildTooltipPanel(opts)

	local handle = {
		instance = refs.panel,
	}

	-- Internal progress state. Tracked separately from the bar's
	-- visual width so handle.setProgress(n) can clamp + de-dup
	-- repeated calls (e.g. server fires "still 2/3" twice in a row).
	local currentProgress = 0

	-- ── Entrance / exit animation state ───────────────────────────────
	-- Mockup keyframes (.tipIn / .tipOut) adapted for the upper-corner
	-- anchor: the original "rise from below" becomes "drop in from
	-- above", and the exit retreats back up the way the panel arrived.
	--   Entrance — 0.55 s Back/Out on Position (Y starts 28 px above
	--              resting and overshoots past, settles to rest),
	--              GroupTransparency 1 → 0, UIScale 0.96 → 1.0.
	--   Exit     — 0.25 s Quad/In, Y back up to (rest − 20) while
	--              GroupTransparency goes 0 → 1 and Scale 1.0 → 0.97.
	-- The dismissing flag prevents re-entry; a second dismiss() call
	-- mid-exit is a no-op.
	local restPosition       = refs.panel.Position
	local ENTRANCE_Y_OFFSET  = -28   -- pre-entrance Y, relative to rest
	local EXIT_Y_OFFSET      = -20   -- post-exit Y, relative to rest

	-- Park the panel at its pre-entrance offset before showing it so
	-- a frame between buildTooltipPanel and the tween kicking off
	-- doesn't flash the panel at its rest position.
	refs.panel.Position = restPosition + UDim2.fromOffset(0, ENTRANCE_Y_OFFSET)

	local entranceInfo = TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local exitInfo     = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local dismissing   = false
	-- Forward-declared so handle.dismiss (defined below) can reference
	-- it; the real assignment happens further down once the icon-pulse
	-- helper is in scope. Lua captures upvalues by name at closure
	-- creation, so without the forward decl here dismiss would
	-- resolve `stopPulse` against the global table (nil) instead of
	-- against the later local.
	local stopPulse

	local function playEntrance()
		TweenService:Create(refs.panel, entranceInfo,
			{ Position = restPosition, GroupTransparency = 0 }):Play()
		TweenService:Create(refs.panelScale, entranceInfo,
			{ Scale = 1.0 }):Play()
	end

	function handle.dismiss()
		if dismissing then return end
		dismissing = true
		-- Stop the icon pulse loop so the glyph holds its rest pose
		-- during the exit fade — without this it'd keep wobbling for
		-- 0.25 s while the panel slides away. stopPulse is forward-
		-- declared above so this upvalue reference resolves to the
		-- later local instead of falling back to the global table.
		if stopPulse then stopPulse() end

		if not refs.panel or not refs.panel.Parent then
			-- Already destroyed somehow (e.g. ScreenGui was nuked) —
			-- still fire onDismiss so callers can clean their state.
			if typeof(opts.onDismiss) == "function" then
				task.spawn(opts.onDismiss)
			end
			if activeHandle == handle then activeHandle = nil end
			return
		end

		local exitPos = restPosition + UDim2.fromOffset(0, EXIT_Y_OFFSET)
		local posTween   = TweenService:Create(refs.panel, exitInfo,
			{ Position = exitPos, GroupTransparency = 1 })
		local scaleTween = TweenService:Create(refs.panelScale, exitInfo,
			{ Scale = 0.97 })
		posTween:Play()
		scaleTween:Play()

		posTween.Completed:Once(function()
			if refs.panel and refs.panel.Parent then
				refs.panel:Destroy()
			end
			refs.panel = nil
			if activeHandle == handle then
				activeHandle = nil
			end
			if typeof(opts.onDismiss) == "function" then
				task.spawn(opts.onDismiss)
			end
		end)
	end

	-- Tween the fill width to match `n / goal`. No-op when the panel
	-- has no progress bar (caller didn't pass `goal`). The label flips
	-- from wood-dark to green once the goal is reached, mirroring the
	-- mockup's `style={{color: done ? "var(--green)" : "var(--wood-dark)"}}`.
	function handle.setProgress(n)
		if not refs.goal or not refs.progressFill then return end
		local goal = refs.goal
		local clamped = math.clamp(tonumber(n) or 0, 0, goal)
		if clamped == currentProgress then return end
		currentProgress = clamped

		local pct = clamped / goal
		-- Mockup: `transition: width .5s cubic-bezier(.4,1.4,.5,1)`.
		-- Roblox's closest with the same overshoot feel is Back/Out.
		local tw = TweenService:Create(refs.progressFill,
			TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.new(pct, 0, 1, 0) })
		tw:Play()

		if refs.progressLabel then
			refs.progressLabel.Text = string.format("%d/%d", clamped, goal)
			refs.progressLabel.TextColor3 = (clamped >= goal)
				and COLOR_GREEN
				or  COLOR_WOOD_DARK
		end
	end

	-- ── Icon pulse loop + completion flash (Step 1F) ──────────────────
	-- Mockup keyframes:
	--   @keyframes iconPulse {
	--     0%, 100% { transform: scale(1); }
	--     50%      { transform: scale(1.06) rotate(-3deg); }
	--   }
	--   .tip-icon .pulser{ animation: iconPulse 2.4s ease-in-out infinite; }
	-- Roblox doesn't expose @keyframes; we emulate with a TweenInfo
	-- whose RepeatCount = -1 + Reverses = true so it ping-pongs
	-- forever between (1, 0°) and (1.06, -3°). 1.2 s each direction =
	-- 2.4 s round trip, matching the mockup exactly.
	local pulseTweens = {}
	if refs.iconScale and refs.iconGlyph then
		local pulseInfo = TweenInfo.new(
			1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		local scaleTw = TweenService:Create(refs.iconScale,  pulseInfo, { Scale    = 1.06 })
		local rotTw   = TweenService:Create(refs.iconGlyph,  pulseInfo, { Rotation = -3   })
		scaleTw:Play()
		rotTw:Play()
		pulseTweens[1] = scaleTw
		pulseTweens[2] = rotTw
	end

	-- Assigns to the upvalue forward-declared near the entrance/exit
	-- block above; using `local` here would shadow it and dismiss()
	-- would silently see nil.
	stopPulse = function()
		for _, tw in ipairs(pulseTweens) do
			pcall(function() tw:Cancel() end)
		end
		pulseTweens = {}
	end

	local completed = false   -- de-dup repeat complete() calls

	function handle.complete()
		if completed then return end
		completed = true

		-- Snap the bar full + flip the label green (matches setProgress
		-- but tween is unconditional on first complete — reaching the
		-- goal at the same moment as setProgress(goal) was last called
		-- still earns the celebration tween).
		if refs.goal then
			handle.setProgress(refs.goal)
		end

		-- Replace the looping pulse with a single "pop" — scale up to
		-- 1.20 / rotate 0 over 0.18 s then ease back to rest. Reads as
		-- a celebration beat without a separate flash overlay.
		stopPulse()
		if refs.iconScale and refs.iconGlyph then
			local up = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			local down = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(refs.iconGlyph, up, { Rotation = 0 }):Play()
			local upScale = TweenService:Create(refs.iconScale, up, { Scale = 1.20 })
			upScale:Play()
			upScale.Completed:Once(function()
				if refs.iconScale and refs.iconScale.Parent then
					TweenService:Create(refs.iconScale, down, { Scale = 1 }):Play()
				end
			end)
		end

		if typeof(opts.onComplete) == "function" then
			task.spawn(opts.onComplete)
		end

		-- Optional auto-dismiss after the celebration plays. Default
		-- 1.4 s gives the tween + the bar fill time to register before
		-- the panel slides away. Pass 0 / nil to keep the tip up.
		local delaySec = tonumber(opts.autoDismissAfterComplete)
		if delaySec and delaySec > 0 then
			task.delay(delaySec, function()
				if not dismissing then
					handle.dismiss()
				end
			end)
		end
	end

	-- Apply the caller's starting progress, if any. Snap (no tween)
	-- so the entrance animation doesn't fight a half-second tween on
	-- first paint — the tween path only kicks in for later updates.
	if refs.goal then
		local startN = math.clamp(tonumber(opts.progress) or 0, 0, refs.goal)
		currentProgress = startN
		if refs.progressFill then
			refs.progressFill.Size = UDim2.new(startN / refs.goal, 0, 1, 0)
		end
		if refs.progressLabel then
			refs.progressLabel.Text = string.format("%d/%d", startN, refs.goal)
			refs.progressLabel.TextColor3 = (startN >= refs.goal)
				and COLOR_GREEN
				or  COLOR_WOOD_DARK
		end
	end

	if refs.closeBtn then
		refs.closeBtn.MouseButton1Click:Connect(function()
			handle.dismiss()
		end)
	end

	activeHandle = handle
	playEntrance()
	return handle
end

_G.ShowOnboardingTip = showOnboardingTip
