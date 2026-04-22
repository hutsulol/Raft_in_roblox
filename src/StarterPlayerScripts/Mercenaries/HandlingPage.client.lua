-- HandlingPage.client.lua
-- Mercenary Handling sub-page (LocalScript).
-- Exposes _G.OpenHandlingPage(ctx) + _G.CloseHandlingPage() so
-- MercenariesMenu can route the HANDLING pill here.
--
-- Built so far:
--   Step 1 — holo scaffold + responsive 960×600 artboard.
--   Step 2 — top bar (BACK + MERCENARY/NAME/LV cluster + gem chip).
--   Step 3 — left column: MAIN HAND + RELIC slot tiles. MAIN HAND
--            reflects the equipped weapon's rarity (via ctx.equipItems);
--            RELIC is a decorative placeholder (no server state).
--   Step 4 — right column: SKINS + ARTIFACTS slot tiles. Both render
--            as empty placeholders (no server state for either in the
--            current data model) with a "+" badge in the icon zone.
--            Selection is tracked across all four tiles.
--   Step 5 — centre character viewport. Visible 280×320 frame with
--            corner L brackets + concentric rings + ground glow wraps
--            the intended viewport area; an invisible 160×472 host
--            mirrors MercenariesMenu's centreCol.slot so the cached
--            ViewportFrame reparents to identical global coords
--            (no idle-animation restart, no character jump).
--   Step 6 — bottom row: detail card + DNA Research card. Detail
--            card reflects the currently-selected slot (populated
--            variant for MAIN HAND via the Weapons EQUIP_ITEMS
--            lookup, empty-placeholder variant for RELIC / SKINS /
--            ARTIFACTS until those slots gain server state). DNA
--            card has a helix + fragment bar + STUDY DNA button
--            wired to a stub; the click-through to the dedicated
--            DNA Study sub-page lands in Step 7.
--
-- Still to land: STUDY DNA navigation + equip-remote wiring.

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local TweenService   = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ─── Palette (matches MercenariesMenu's amethyst-dark holo variant) ──
local COLOR_TEXT              = Color3.fromRGB(220, 240, 255)
local COLOR_TEXT_DIM          = Color3.fromRGB(140, 180, 220)
local HOLO_PANEL_FILL         = Color3.fromRGB(10, 24, 44)
local HOLO_PANEL_TRANSPARENCY = 0.28
local HOLO_PANEL_BORDER       = Color3.fromRGB(75, 100, 125)
local HOLO_EDGE               = Color3.fromRGB(190, 220, 245)
local HORIZON                 = Color3.fromRGB(80, 140, 190)

local FONT_TITLE = Enum.Font.GothamBold
local FONT_BODY  = Enum.Font.Gotham

local COLOR_TEXT_MUTE = Color3.fromRGB(100, 125, 155)
local COLOR_GOLD      = Color3.fromRGB(230, 190, 100)

-- ─── Hand-drawn top-bar icons ─────────────────────────────────────────
-- Same geometric style the rest of the menus use — each takes
-- (parent, size, color), builds inside a square container and returns
-- that container so the caller can reposition it.

local function makeBackIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "BackIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local thick = math.max(1, math.floor(size * 0.14))
	local legLen = size * 0.68

	local top = Instance.new("Frame")
	top.AnchorPoint = Vector2.new(0, 0.5)
	top.Position = UDim2.fromScale(0.1, 0.35)
	top.Size = UDim2.fromOffset(legLen, thick)
	top.BackgroundColor3 = color
	top.BorderSizePixel = 0
	top.Rotation = -45
	top.Parent = c

	local bot = Instance.new("Frame")
	bot.AnchorPoint = Vector2.new(0, 0.5)
	bot.Position = UDim2.fromScale(0.1, 0.65)
	bot.Size = UDim2.fromOffset(legLen, thick)
	bot.BackgroundColor3 = color
	bot.BorderSizePixel = 0
	bot.Rotation = 45
	bot.Parent = c

	return c
end

local function makeGemIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "GemIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromOffset(size * 0.7, size * 0.7)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Rotation = 45
	body.Parent = c
	local s = Instance.new("UIStroke")
	s.Color     = color
	s.Thickness = 1.4
	s.Parent    = body

	local facet = Instance.new("Frame")
	facet.AnchorPoint = Vector2.new(0.5, 0.5)
	facet.Position = UDim2.fromScale(0.5, 0.33)
	facet.Size = UDim2.fromOffset(size * 0.5, math.max(1, math.floor(size * 0.08)))
	facet.BackgroundColor3 = color
	facet.BorderSizePixel = 0
	facet.Parent = c

	return c
end

-- Rotated-square "stars" row. `filled` entries render as solid fills,
-- the remainder as hollow outlines at reduced opacity. Mirrors the
-- MercenariesMenu rarity-row recipe so both pages stay visually in sync.
local function makeStarRow(parent, filled, total, size, color)
	size   = size   or 9
	total  = total  or 5
	color  = color  or COLOR_GOLD
	filled = math.clamp(filled or 0, 0, total)

	local gap = 2
	local c = Instance.new("Frame")
	c.Name = "StarRow"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(total * size + (total - 1) * gap, size)
	c.Parent = parent

	for i = 1, total do
		local star = Instance.new("Frame")
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.new(0, (i - 1) * (size + gap) + size * 0.5, 0.5, 0)
		star.Size = UDim2.fromOffset(size * 0.72, size * 0.72)
		star.Rotation = 45
		star.BorderSizePixel = 0
		if i <= filled then
			star.BackgroundColor3 = color
			star.BackgroundTransparency = 0
			star.Parent = c
		else
			star.BackgroundTransparency = 1
			star.Parent = c
			local ss = Instance.new("UIStroke")
			ss.Color       = color
			ss.Thickness   = 1
			ss.Transparency = 0.6
			ss.Parent      = star
		end
	end

	return c
end

-- Slanted-blade weapon glyph (matches the MAIN HAND tile in the mockup:
-- a thin parallelogram blade with a small crossguard + pommel dot).
local function makeWeaponIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "WeaponIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local blade = Instance.new("Frame")
	blade.AnchorPoint = Vector2.new(0.5, 0.5)
	blade.Position = UDim2.fromScale(0.5, 0.45)
	blade.Size = UDim2.fromOffset(size * 0.22, size * 0.78)
	blade.BackgroundTransparency = 1
	blade.BorderSizePixel = 0
	blade.Rotation = -28
	blade.Parent = c
	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0, math.max(1, math.floor(size * 0.06)))
	bCorner.Parent = blade
	local bStroke = Instance.new("UIStroke")
	bStroke.Color     = color
	bStroke.Thickness = 1.4
	bStroke.Parent    = blade

	local guard = Instance.new("Frame")
	guard.AnchorPoint = Vector2.new(0.5, 0.5)
	guard.Position = UDim2.fromScale(0.62, 0.72)
	guard.Size = UDim2.fromOffset(size * 0.42, math.max(1, math.floor(size * 0.10)))
	guard.BackgroundColor3 = color
	guard.BorderSizePixel = 0
	guard.Rotation = -28
	guard.Parent = c

	local pommel = Instance.new("Frame")
	pommel.AnchorPoint = Vector2.new(0.5, 0.5)
	pommel.Position = UDim2.fromScale(0.78, 0.86)
	pommel.Size = UDim2.fromOffset(size * 0.18, size * 0.18)
	pommel.BackgroundColor3 = color
	pommel.BorderSizePixel = 0
	pommel.Parent = c
	local pCorner = Instance.new("UICorner")
	pCorner.CornerRadius = UDim.new(1, 0)
	pCorner.Parent = pommel

	return c
end

-- Three-point crown glyph (RELIC slot placeholder in the mockup).
-- Drawn as a flat base bar + three triangular peaks via rotated
-- squares so it reads at small sizes without needing an image asset.
local function makeCrownIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "CrownIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local baseThick = math.max(1, math.floor(size * 0.12))
	local base = Instance.new("Frame")
	base.AnchorPoint = Vector2.new(0.5, 1)
	base.Position = UDim2.fromScale(0.5, 0.78)
	base.Size = UDim2.fromOffset(size * 0.78, baseThick)
	base.BackgroundColor3 = color
	base.BorderSizePixel = 0
	base.Parent = c

	local function peak(xScale, heightScale)
		local p = Instance.new("Frame")
		p.AnchorPoint = Vector2.new(0.5, 1)
		p.Position = UDim2.fromScale(xScale, 0.78)
		p.Size = UDim2.fromOffset(size * 0.22, size * heightScale)
		p.BackgroundTransparency = 1
		p.BorderSizePixel = 0
		p.Parent = c
		local s = Instance.new("UIStroke")
		s.Color     = color
		s.Thickness = 1.4
		s.Parent    = p
		return p
	end
	peak(0.22, 0.46)
	peak(0.50, 0.60)
	peak(0.78, 0.46)

	return c
end

-- Four-point spark glyph (stat-row prefix on the detail card).
-- Two crossed thin Frames — same recipe as MercenariesMenu.
local function makeSparkIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "SparkIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local thick = math.max(1, math.floor(size * 0.2))
	local vert = Instance.new("Frame")
	vert.AnchorPoint = Vector2.new(0.5, 0.5)
	vert.Position = UDim2.fromScale(0.5, 0.5)
	vert.Size = UDim2.fromOffset(thick, size)
	vert.BackgroundColor3 = color
	vert.BorderSizePixel = 0
	vert.Parent = c

	local horiz = Instance.new("Frame")
	horiz.AnchorPoint = Vector2.new(0.5, 0.5)
	horiz.Position = UDim2.fromScale(0.5, 0.5)
	horiz.Size = UDim2.fromOffset(size, thick)
	horiz.BackgroundColor3 = color
	horiz.BorderSizePixel = 0
	horiz.Parent = c

	return c
end

-- Right-pointing chevron (STUDY DNA button suffix).
local function makeChevronRight(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "ChevronRight"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local thick = math.max(1, math.floor(size * 0.14))
	local legLen = size * 0.68
	local top = Instance.new("Frame")
	top.AnchorPoint = Vector2.new(1, 0.5)
	top.Position = UDim2.fromScale(0.92, 0.35)
	top.Size = UDim2.fromOffset(legLen, thick)
	top.BackgroundColor3 = color
	top.BorderSizePixel = 0
	top.Rotation = 45
	top.Parent = c

	local bot = Instance.new("Frame")
	bot.AnchorPoint = Vector2.new(1, 0.5)
	bot.Position = UDim2.fromScale(0.92, 0.65)
	bot.Size = UDim2.fromOffset(legLen, thick)
	bot.BackgroundColor3 = color
	bot.BorderSizePixel = 0
	bot.Rotation = -45
	bot.Parent = c

	return c
end

-- Abstract DNA-helix glyph — two vertical side bars + four short
-- horizontal rungs at alternating offsets. Not an anatomically correct
-- double-helix (Roblox Frames can't draw sine curves), but reads as
-- "genetic thing" at the small size the DNA card uses it.
local function makeHelixIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "HelixIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size * 1.25)
	c.Parent = parent

	local railThick = math.max(1, math.floor(size * 0.08))
	local function rail(xScale, rot)
		local r = Instance.new("Frame")
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.Position = UDim2.fromScale(xScale, 0.5)
		r.Size = UDim2.fromOffset(railThick, size * 1.2)
		r.BackgroundColor3 = color
		r.BorderSizePixel = 0
		r.Rotation = rot
		r.Parent = c
	end
	rail(0.26, -6)
	rail(0.74,  6)

	local rungThick = math.max(1, math.floor(size * 0.07))
	local rungs = 4
	for i = 1, rungs do
		local t = (i - 0.5) / rungs
		local inset = math.sin(t * math.pi) * size * 0.12
		local rung = Instance.new("Frame")
		rung.AnchorPoint = Vector2.new(0.5, 0.5)
		rung.Position = UDim2.fromScale(0.5, t)
		rung.Size = UDim2.fromOffset(size * 0.5 - inset, rungThick)
		rung.BackgroundColor3 = color
		rung.BorderSizePixel = 0
		rung.BackgroundTransparency = 0.35
		rung.Parent = c
	end

	return c
end

-- Segmented holo progress bar (DNA-fragment indicator). Dark track,
-- holo-gradient fill, optional segment dividers. Returns (track, fill)
-- so callers can resize the fill. Mirrors MercenariesMenu.makeHoloBar.
local function makeHoloBar(parent, size, segments)
	local track = Instance.new("Frame")
	track.Name = "HoloBar"
	track.BackgroundColor3 = Color3.fromRGB(8, 20, 38)
	track.BackgroundTransparency = 0.2
	track.BorderSizePixel = 0
	track.Size = size
	track.Parent = parent

	local s = Instance.new("UIStroke")
	s.Color     = HOLO_PANEL_BORDER
	s.Thickness = 1
	s.Parent    = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = HOLO_EDGE
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = track
	local fGrad = Instance.new("UIGradient")
	fGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(140, 200, 235)),
		ColorSequenceKeypoint.new(1, HOLO_EDGE),
	})
	fGrad.Parent = fill

	if segments and segments > 0 then
		for i = 1, segments - 1 do
			local d = Instance.new("Frame")
			d.Name = "Seg" .. i
			d.AnchorPoint = Vector2.new(0.5, 0)
			d.Position = UDim2.fromScale(i / segments, 0)
			d.Size = UDim2.new(0, 1, 1, 0)
			d.BackgroundColor3 = Color3.fromRGB(8, 20, 38)
			d.BackgroundTransparency = 0.35
			d.BorderSizePixel = 0
			d.ZIndex = (track.ZIndex or 1) + 2
			d.Parent = track
		end
	end

	return track, fill
end

-- Four L-shaped corner brackets pinned to the inside corners of
-- `parent`. Each L is a horizontal + vertical Frame pair sharing an
-- anchor point so the elbow lines up regardless of stroke thickness.
-- Mirrors MercenariesMenu.cornerLs minus the UIPadding-aware offset
-- math (nothing inside the Handling centre frame uses UIPadding).
local function cornerLs(parent, size, color, thickness)
	size      = size      or 10
	color     = color     or HOLO_EDGE
	thickness = thickness or 1.5

	local function addL(ax, ay, ox, oy)
		local horiz = Instance.new("Frame")
		horiz.Name = "CornerL_H"
		horiz.AnchorPoint = Vector2.new(ax, ay)
		horiz.Position = UDim2.new(ax, ox, ay, oy)
		horiz.Size = UDim2.fromOffset(size, thickness)
		horiz.BackgroundColor3 = color
		horiz.BorderSizePixel = 0
		horiz.ZIndex = (parent.ZIndex or 1) + 1
		horiz.Parent = parent

		local vert = Instance.new("Frame")
		vert.Name = "CornerL_V"
		vert.AnchorPoint = Vector2.new(ax, ay)
		vert.Position = UDim2.new(ax, ox, ay, oy)
		vert.Size = UDim2.fromOffset(thickness, size)
		vert.BackgroundColor3 = color
		vert.BorderSizePixel = 0
		vert.ZIndex = (parent.ZIndex or 1) + 1
		vert.Parent = parent
	end

	addL(0, 0,  0,  0)
	addL(1, 0,  0,  0)
	addL(0, 1,  0,  0)
	addL(1, 1,  0,  0)
end

-- Plain outlined diamond glyph (ARTIFACTS slot placeholder). Same
-- rotated-square shape as the gem, minus the facet line — so the two
-- right-column slots read as related-but-distinct.
local function makeDiamondIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "DiamondIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromOffset(size * 0.7, size * 0.7)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Rotation = 45
	body.Parent = c
	local s = Instance.new("UIStroke")
	s.Color     = color
	s.Thickness = 1.4
	s.Parent    = body

	return c
end

-- ─── Artboard reference (matches the Claude Design MercHandlingPage
-- 960x600 canvas — used as the reference size for the responsive
-- UIScale below) ─────────────────────────────────────────────────────
local REFERENCE_W        = 960
local REFERENCE_H        = 600
local HORIZONTAL_PADDING = 80 -- per-total px reserved for overflow

-- ─── Panels registered here fade the drifting motes when they drift
-- behind them. Populated as slot tiles / cards come online. ──────────
local motesOccludeList = {}

-- ─── Slot-tile appearance constants (shared selected/unselected look
-- used by both the left and right equipment columns). ────────────────
local SLOT_W                   = 120
local SLOT_H                   = 140
local SLOT_LABEL_H             = 32
local SLOT_ICON_SIZE           = 48

local SLOT_FILL_UNSELECTED     = HOLO_PANEL_FILL
local SLOT_FILL_UNSEL_ALPHA    = 0.40
local SLOT_FILL_SELECTED       = Color3.fromRGB(16, 42, 72)
local SLOT_FILL_SEL_ALPHA      = 0.15
local SLOT_STROKE_UNSELECTED   = Color3.fromRGB(60, 85, 110)
local SLOT_STROKE_UNSEL_THICK  = 1
local SLOT_STROKE_SELECTED     = Color3.fromRGB(120, 220, 255)
local SLOT_STROKE_SEL_THICK    = 1.6
local SLOT_LABEL_FILL          = Color3.fromRGB(6, 16, 30)
local SLOT_LABEL_FILL_ALPHA    = 0.55
local SLOT_LABEL_COLOR_SEL     = Color3.fromRGB(230, 245, 255)
local SLOT_LABEL_COLOR_UNSEL   = Color3.fromRGB(140, 170, 200)
local SLOT_ICON_COLOR_SEL      = Color3.fromRGB(130, 220, 255)
local SLOT_ICON_COLOR_UNSEL    = Color3.fromRGB(110, 160, 200)

-- buildSlotTile — 120×140 holo tile used for MAIN HAND / RELIC / SKINS
-- / ARTIFACTS. Returns a small handle with `setSelected(bool)` so the
-- caller can flip the visual without rebuilding the tile. `opts`:
--   name      — uppercase label text ("MAIN HAND", "RELIC", …)
--   iconBuilder(parent, size, color) — draws the slot glyph; pass nil
--                  for empty slots (see `emptyGlyph`).
--   emptyGlyph — when true, renders a top-right "+" marker and dims
--                the icon area further (right-column empty look).
--   stars     — integer 0..5 (hidden when emptyGlyph is true).
--   selected  — initial selection state.
--   position  — UDim2 passed straight through to tile.Position.
--   zIndex    — base z for the tile; children use zIndex+1/+2.
--   onClick() — fired on MouseButton1Click; receives the handle so
--               callers can re-paint multiple tiles cooperatively.
local function buildSlotTile(parent, opts)
	opts = opts or {}
	local zBase = opts.zIndex or 55

	local tile = Instance.new("TextButton")
	tile.Name = opts.name or "SlotTile"
	tile.AutoButtonColor = false
	tile.Text = ""
	tile.AnchorPoint = opts.anchorPoint or Vector2.new(0, 0)
	tile.Position = opts.position or UDim2.fromOffset(0, 0)
	tile.Size = UDim2.fromOffset(SLOT_W, SLOT_H)
	tile.BorderSizePixel = 0
	tile.ZIndex = zBase
	tile.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = tile

	-- Inner icon zone: everything except the bottom label band. The
	-- icon itself is centred inside it, with the star row pinned to
	-- the bottom-right corner (matches the mockup).
	local iconZone = Instance.new("Frame")
	iconZone.Name = "IconZone"
	iconZone.BackgroundTransparency = 1
	iconZone.BorderSizePixel = 0
	iconZone.Position = UDim2.fromOffset(0, 0)
	iconZone.Size = UDim2.new(1, 0, 0, SLOT_H - SLOT_LABEL_H)
	iconZone.ZIndex = zBase + 1
	iconZone.Parent = tile

	local iconContainer = Instance.new("Frame")
	iconContainer.Name = "Icon"
	iconContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	iconContainer.Position = UDim2.fromScale(0.5, 0.45)
	iconContainer.Size = UDim2.fromOffset(SLOT_ICON_SIZE, SLOT_ICON_SIZE)
	iconContainer.BackgroundTransparency = 1
	iconContainer.BorderSizePixel = 0
	iconContainer.ZIndex = zBase + 2
	iconContainer.Parent = iconZone

	local iconGlyph
	if opts.iconBuilder then
		iconGlyph = opts.iconBuilder(iconContainer, SLOT_ICON_SIZE, SLOT_ICON_COLOR_UNSEL)
		if iconGlyph then
			iconGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
			iconGlyph.Position = UDim2.fromScale(0.5, 0.5)
			iconGlyph.ZIndex = zBase + 2
		end
	end

	-- "+" badge for empty right-column slots.
	local plusBadge
	if opts.emptyGlyph then
		plusBadge = Instance.new("TextLabel")
		plusBadge.Name = "PlusBadge"
		plusBadge.AnchorPoint = Vector2.new(1, 0)
		plusBadge.Position = UDim2.new(1, -8, 0, 8)
		plusBadge.Size = UDim2.fromOffset(14, 14)
		plusBadge.BackgroundTransparency = 1
		plusBadge.Font = FONT_TITLE
		plusBadge.TextSize = 16
		plusBadge.TextColor3 = COLOR_TEXT_DIM
		plusBadge.Text = "+"
		plusBadge.ZIndex = zBase + 2
		plusBadge.Parent = iconZone
	end

	-- Rarity row, hidden for empty slots.
	local starRow
	if not opts.emptyGlyph then
		local starsCount = math.clamp(opts.stars or 0, 0, 5)
		starRow = makeStarRow(iconZone, starsCount, 5, 9, COLOR_GOLD)
		starRow.Name = "Stars"
		starRow.AnchorPoint = Vector2.new(1, 1)
		starRow.Position = UDim2.new(1, -8, 1, -6)
		starRow.ZIndex = zBase + 2
	end

	-- Label band pinned to the bottom of the tile.
	local labelBand = Instance.new("Frame")
	labelBand.Name = "LabelBand"
	labelBand.AnchorPoint = Vector2.new(0, 1)
	labelBand.Position = UDim2.new(0, 0, 1, 0)
	labelBand.Size = UDim2.new(1, 0, 0, SLOT_LABEL_H)
	labelBand.BackgroundColor3 = SLOT_LABEL_FILL
	labelBand.BackgroundTransparency = SLOT_LABEL_FILL_ALPHA
	labelBand.BorderSizePixel = 0
	labelBand.ZIndex = zBase + 1
	labelBand.Parent = tile

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = FONT_TITLE
	label.TextSize = 12
	label.TextColor3 = SLOT_LABEL_COLOR_UNSEL
	label.Text = tostring(opts.name or ""):upper()
	label.ZIndex = zBase + 2
	label.Parent = labelBand

	-- Selection glow (enabled only when selected — a soft blurred square
	-- behind the tile, same color as the selected stroke).
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, 14, 1, 14)
	glow.BackgroundColor3 = SLOT_STROKE_SELECTED
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.ZIndex = zBase - 1
	glow.Parent = tile
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(0, 8)
	glowCorner.Parent = glow

	table.insert(motesOccludeList, tile)

	local handle = { tile = tile }

	function handle.setSelected(selected)
		handle.selected = selected and true or false
		if selected then
			tile.BackgroundColor3 = SLOT_FILL_SELECTED
			tile.BackgroundTransparency = SLOT_FILL_SEL_ALPHA
			stroke.Color     = SLOT_STROKE_SELECTED
			stroke.Thickness = SLOT_STROKE_SEL_THICK
			label.TextColor3 = SLOT_LABEL_COLOR_SEL
			if iconGlyph then
				local iconStroke = iconGlyph:FindFirstChildWhichIsA("UIStroke")
				if iconStroke then iconStroke.Color = SLOT_ICON_COLOR_SEL end
				for _, d in iconGlyph:GetDescendants() do
					if d:IsA("Frame") and d.BackgroundTransparency == 0 then
						d.BackgroundColor3 = SLOT_ICON_COLOR_SEL
					elseif d:IsA("UIStroke") then
						d.Color = SLOT_ICON_COLOR_SEL
					end
				end
			end
			glow.BackgroundTransparency = 0.80
		else
			tile.BackgroundColor3 = SLOT_FILL_UNSELECTED
			tile.BackgroundTransparency = SLOT_FILL_UNSEL_ALPHA
			stroke.Color     = SLOT_STROKE_UNSELECTED
			stroke.Thickness = SLOT_STROKE_UNSEL_THICK
			label.TextColor3 = SLOT_LABEL_COLOR_UNSEL
			if iconGlyph then
				for _, d in iconGlyph:GetDescendants() do
					if d:IsA("Frame") and d.BackgroundTransparency == 0 then
						d.BackgroundColor3 = SLOT_ICON_COLOR_UNSEL
					elseif d:IsA("UIStroke") then
						d.Color = SLOT_ICON_COLOR_UNSEL
					end
				end
			end
			glow.BackgroundTransparency = 1
		end
	end

	handle.setSelected(opts.selected and true or false)

	if opts.onClick then
		tile.MouseButton1Click:Connect(function()
			opts.onClick(handle)
		end)
	end

	return handle
end

-- ─── Module state ────────────────────────────────────────────────────
local activePage = nil
local activeConnections = {}
-- Stashed across open/close so closeHandlingPage can call ctx.detach-
-- CachedViewports() before destroying the page — otherwise Destroy
-- cascades into the cached ViewportFrame and the idle animation
-- restarts when the user goes back to the mercenary roster.
local activeCtx = nil

local function disconnectAll(tbl)
	for _, conn in ipairs(tbl) do conn:Disconnect() end
	table.clear(tbl)
end

-- ─── Holo backdrop (shared five-layer composition) ───────────────────
-- Same recipe as PhoneMenu / MercenariesMenu: base vertical gradient →
-- horizon glow band → top + bottom vignette → drifting motes. Returned
-- Frame fills `parent`.
local function buildHoloBackground(parent)
	local BG_TOP   = Color3.fromRGB(2,  2,  6)
	local BG_MID   = Color3.fromRGB(4,  6, 12)
	local BG_BOT   = Color3.fromRGB(8, 12, 22)
	local MOTE_COL = Color3.fromRGB(180, 215, 240)

	local root = Instance.new("Frame")
	root.Name = "Backdrop"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = BG_MID
	root.BorderSizePixel = 0
	root.ZIndex = 0
	root.Parent = parent

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    BG_TOP),
		ColorSequenceKeypoint.new(0.45, BG_MID),
		ColorSequenceKeypoint.new(1,    BG_BOT),
	})
	grad.Rotation = 90
	grad.Parent = root

	local function horizonLayer(scaleX, scaleY, bgTrans, centerTrans)
		local h = Instance.new("Frame")
		h.Name = "Horizon"
		h.AnchorPoint = Vector2.new(0.5, 0.5)
		h.Position = UDim2.fromScale(0.5, 0.42)
		h.Size = UDim2.fromScale(scaleX, scaleY)
		h.BackgroundColor3 = HORIZON
		h.BackgroundTransparency = bgTrans
		h.BorderSizePixel = 0
		h.ZIndex = 1
		h.Parent = root
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,    1),
			NumberSequenceKeypoint.new(0.28, 0.85),
			NumberSequenceKeypoint.new(0.5,  centerTrans),
			NumberSequenceKeypoint.new(0.72, 0.85),
			NumberSequenceKeypoint.new(1,    1),
		})
		g.Rotation = 0
		g.Parent = h
	end
	horizonLayer(1.6, 0.22, 0.90, 0.50)
	horizonLayer(1.0, 0.08, 0.72, 0.15)

	local function makeVignette(yPos, flip)
		local v = Instance.new("Frame")
		v.Name = flip and "VignetteBottom" or "VignetteTop"
		v.Size = UDim2.new(1, 0, 0.38, 0)
		v.Position = UDim2.fromScale(0, yPos)
		v.BackgroundColor3 = Color3.new(0, 0, 0)
		v.BorderSizePixel = 0
		v.ZIndex = 2
		v.Parent = root
		local g = Instance.new("UIGradient")
		g.Transparency = flip
			and NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0.35),
			})
			or NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			})
		g.Rotation = 90
		g.Parent = v
	end
	makeVignette(0,    false)
	makeVignette(0.62, true)

	local motes = Instance.new("Frame")
	motes.Name = "Motes"
	motes.Size = UDim2.fromScale(1, 1)
	motes.BackgroundTransparency = 1
	motes.BorderSizePixel = 0
	motes.ClipsDescendants = true
	motes.ZIndex = 3
	motes.Parent = root

	for _ = 1, 20 do
		local sizePx     = math.random(12, 32) / 10
		local duration   = 14 + math.random() * 14
		local startDelay = math.random() * 18
		local opacity    = 0.2 + math.random() * 0.6

		local mote = Instance.new("Frame")
		mote.Name = "Mote"
		mote.AnchorPoint = Vector2.new(0.5, 0.5)
		mote.Size = UDim2.fromOffset(sizePx, sizePx)
		mote.BackgroundColor3 = MOTE_COL
		mote.BackgroundTransparency = 1 - opacity
		mote.BorderSizePixel = 0
		mote.ZIndex = 4
		mote.Parent = motes
		mote:SetAttribute("BaseTransparency", 1 - opacity)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = mote

		task.spawn(function()
			task.wait(startDelay)
			while mote.Parent do
				local startX = math.random()
				local driftX = (math.random() - 0.5) * 0.06
				mote.Position = UDim2.new(startX, 0, 1.05, 0)
				local goal = UDim2.new(startX + driftX, 0, -0.05, 0)
				local tw = TweenService:Create(mote,
					TweenInfo.new(duration, Enum.EasingStyle.Linear),
					{ Position = goal })
				tw:Play()
				tw.Completed:Wait()
			end
		end)
	end

	table.insert(activeConnections, RunService.Heartbeat:Connect(function()
		if #motesOccludeList == 0 then return end
		for _, mote in motes:GetChildren() do
			if mote:IsA("Frame") then
				local base = mote:GetAttribute("BaseTransparency") or 0.5
				local p = mote.AbsolutePosition
				local s = mote.AbsoluteSize
				local cx = p.X + s.X * 0.5
				local cy = p.Y + s.Y * 0.5
				local hidden = false
				for _, panel in motesOccludeList do
					if panel.Visible then
						local pp = panel.AbsolutePosition
						local ps = panel.AbsoluteSize
						if cx >= pp.X and cx <= pp.X + ps.X
							and cy >= pp.Y and cy <= pp.Y + ps.Y then
							hidden = true
							break
						end
					end
				end
				mote.BackgroundTransparency = hidden and 0.97 or base
			end
		end
	end))

	return root
end

-- ─── Close ───────────────────────────────────────────────────────────
local function closeHandlingPage()
	disconnectAll(activeConnections)
	table.clear(motesOccludeList)
	-- Detach the cached merc ViewportFrame FIRST so activePage:Destroy()
	-- below doesn't take the rig + idle animation tracks down with it.
	-- MercenariesMenu's own detachCachedViewports repoints every cached
	-- vp.Parent to nil, leaving the cache entry intact so buildMerc-
	-- Viewport can reparent it on the next open.
	if activeCtx and activeCtx.detachCachedViewports then
		activeCtx.detachCachedViewports()
	end
	if activePage then
		activePage:Destroy()
		activePage = nil
	end
	activeCtx = nil
end

-- ─── Open ────────────────────────────────────────────────────────────
-- ctx fields:
--   screenGui             — ScreenGui to parent the page under
--   mercName              — currently selected merc (for the title)
--   mercNames             — full roster list (unused yet)
--   theme                 — MERC_THEMES[mercName] or DEFAULT_THEME
--   onBack()              — invoked when BACK is pressed
--   hidePhonePanels()     — phone-panel hide hook (optional)
--   detachCachedViewports() — rig-cache detach hook (optional)
--   buildMercViewport()   — rig builder (used in Step 6)
local function openHandlingPage(ctx)
	ctx = ctx or {}
	local screenGui = ctx.screenGui
	if not screenGui then
		warn("[HandlingPage] open called without ctx.screenGui")
		return
	end

	closeHandlingPage()
	activeCtx = ctx

	local page = Instance.new("Frame")
	page.Name = "HandlingPage"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ZIndex = 50
	page.Parent = screenGui
	activePage = page

	if ctx.hidePhonePanels then ctx.hidePhonePanels() end

	-- Backdrop (first child so everything else renders over it).
	buildHoloBackground(page)

	-- Responsive 960x600 artboard, centred on screen. Same recipe as
	-- MercenariesMenu — UIScale driven off Camera.ViewportSize so the
	-- scale actually recomputes on window resize. HORIZONTAL_PADDING
	-- reserves room for elements that overhang the artboard (BACK
	-- button sits at scaleWrap x=-24 once Step 2's top bar lands).
	local MENU_VERTICAL_SHIFT = 30

	local scaleWrap = Instance.new("Frame")
	scaleWrap.Name = "ScaleWrap"
	scaleWrap.BackgroundTransparency = 1
	scaleWrap.BorderSizePixel = 0
	scaleWrap.AnchorPoint = Vector2.new(0.5, 0.5)
	scaleWrap.Position = UDim2.new(0.5, 0, 0.5, MENU_VERTICAL_SHIFT)
	scaleWrap.Size = UDim2.fromOffset(REFERENCE_W, REFERENCE_H)
	scaleWrap.ZIndex = 50
	scaleWrap.Parent = page

	local responsiveScale = Instance.new("UIScale")
	responsiveScale.Name = "ResponsiveScale"
	responsiveScale.Scale = 1
	responsiveScale.Parent = scaleWrap

	local backBtnRef, chipRef
	local BACK_BTN_Y = 39
	local CHIP_Y     = 39

	local function updateResponsiveScale()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then return end
		-- Reserve HORIZONTAL_PADDING so overflow elements (BACK at
		-- scaleWrap x=-24 once styled) stay on-screen. 2 * shift
		-- accounted for vertically so the artboard still fits when
		-- MENU_VERTICAL_SHIFT pushes it down.
		local sx = (size.X - HORIZONTAL_PADDING) / REFERENCE_W
		local verticalBudget = size.Y - 2 * math.abs(MENU_VERTICAL_SHIFT)
		local sy = verticalBudget / REFERENCE_H
		local s = math.min(sx, sy)
		if s < 0.5 then s = 0.5 end
		responsiveScale.Scale = s

		local SCREEN_MARGIN = 16
		local dynamicBleed = math.max(0,
			size.X / (2 * s) - REFERENCE_W / 2 - SCREEN_MARGIN / s
		)
		dynamicBleed = math.floor(dynamicBleed + 0.5)

		if backBtnRef then
			backBtnRef.Position = UDim2.fromOffset(-dynamicBleed, BACK_BTN_Y)
		end
		if chipRef then
			chipRef.Position = UDim2.new(1, dynamicBleed, 0, CHIP_Y)
		end
	end

	-- Hook Camera.ViewportSize so the scale recomputes whenever the
	-- window resizes; AbsoluteSize alone doesn't fire reliably on
	-- Roblox. Rehook on CurrentCamera swaps (respawn, etc.).
	local viewportConn
	local function hookCamera(cam)
		if viewportConn then
			viewportConn:Disconnect()
			viewportConn = nil
		end
		if cam then
			viewportConn = cam:GetPropertyChangedSignal("ViewportSize")
				:Connect(updateResponsiveScale)
			table.insert(activeConnections, viewportConn)
		end
		updateResponsiveScale()
	end
	hookCamera(workspace.CurrentCamera)
	table.insert(activeConnections,
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			hookCamera(workspace.CurrentCamera)
		end))
	table.insert(activeConnections,
		screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateResponsiveScale))

	local theme = ctx.theme or {}
	local mercDisplay = tostring(theme.displayName or ctx.mercName or "—"):upper()
	local mercLevel   = theme.level or 1

	-- ── BACK button (glyph + uppercase label), pinned by dynamicBleed
	-- so it always sits at SCREEN_MARGIN from the screen's left edge.
	local backBtn = Instance.new("TextButton")
	backBtn.Name = "BackButton"
	backBtn.AnchorPoint = Vector2.new(0, 0)
	backBtn.Position = UDim2.fromOffset(0, BACK_BTN_Y)
	backBtn.Size = UDim2.fromOffset(92, 34)
	backBtn.BackgroundColor3 = HOLO_PANEL_FILL
	backBtn.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	backBtn.BorderSizePixel = 0
	backBtn.AutoButtonColor = true
	backBtn.Text = "" -- glyph + label drawn as children
	backBtn.ZIndex = 52
	backBtn.Parent = scaleWrap
	local bStroke = Instance.new("UIStroke")
	bStroke.Color     = HOLO_PANEL_BORDER
	bStroke.Thickness = 1
	bStroke.Parent    = backBtn
	backBtnRef = backBtn

	local backGlyph = makeBackIcon(backBtn, 14, COLOR_TEXT)
	backGlyph.AnchorPoint = Vector2.new(0, 0.5)
	backGlyph.Position = UDim2.new(0, 12, 0.5, 0)
	backGlyph.ZIndex = 53

	local backLabel = Instance.new("TextLabel")
	backLabel.BackgroundTransparency = 1
	backLabel.BorderSizePixel = 0
	backLabel.Position = UDim2.fromOffset(30, 0)
	backLabel.Size = UDim2.new(1, -34, 1, 0)
	backLabel.Font = FONT_TITLE
	backLabel.TextSize = 13
	backLabel.TextColor3 = COLOR_TEXT
	backLabel.TextXAlignment = Enum.TextXAlignment.Left
	backLabel.Text = "BACK"
	backLabel.ZIndex = 53
	backLabel.Parent = backBtn

	backBtn.MouseButton1Click:Connect(function()
		closeHandlingPage()
		if ctx.onBack then ctx.onBack() end
	end)

	-- ── Centred MERCENARY / <NAME> / LV N cluster ────────────────────
	-- Fixed widths + absolute positioning inside a centred container,
	-- sized generously so long merc names still fit without cropping.
	-- AutomaticSize + UIListLayout bit us on first pass (renders were
	-- blank until the layout pass caught up), so we side-step that by
	-- doing the math here.
	local CLUSTER_W = 320
	local TAG_W     = 96     -- "MERCENARY" at 11 pt
	local NAME_W    = 160    -- big title at 18 pt — room for "QUARTERMASTER"
	local BADGE_W   = 48     -- LV N badge with padding
	local GAP       = 8
	local CLUSTER_Y = BACK_BTN_Y + 6

	local topCluster = Instance.new("Frame")
	topCluster.Name = "TopCluster"
	topCluster.BackgroundTransparency = 1
	topCluster.BorderSizePixel = 0
	topCluster.AnchorPoint = Vector2.new(0.5, 0)
	topCluster.Position = UDim2.new(0.5, 0, 0, CLUSTER_Y)
	topCluster.Size = UDim2.fromOffset(CLUSTER_W, 24)
	topCluster.ZIndex = 52
	topCluster.Parent = scaleWrap

	local mercTag = Instance.new("TextLabel")
	mercTag.Name = "MercTag"
	mercTag.BackgroundTransparency = 1
	mercTag.BorderSizePixel = 0
	mercTag.Position = UDim2.fromOffset(0, 0)
	mercTag.Size = UDim2.fromOffset(TAG_W, 24)
	mercTag.Font = FONT_TITLE
	mercTag.TextSize = 11
	mercTag.TextColor3 = COLOR_TEXT_MUTE
	mercTag.TextXAlignment = Enum.TextXAlignment.Right
	mercTag.Text = "MERCENARY"
	mercTag.ZIndex = 53
	mercTag.Parent = topCluster

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "MercName"
	nameLabel.BackgroundTransparency = 1
	nameLabel.BorderSizePixel = 0
	nameLabel.Position = UDim2.fromOffset(TAG_W + GAP, 0)
	nameLabel.Size = UDim2.fromOffset(NAME_W, 24)
	nameLabel.Font = FONT_TITLE
	nameLabel.TextSize = 18
	nameLabel.TextColor3 = HOLO_EDGE
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.Text = mercDisplay
	nameLabel.ZIndex = 53
	nameLabel.Parent = topCluster

	local lvBadge = Instance.new("Frame")
	lvBadge.Name = "LvBadge"
	lvBadge.BackgroundTransparency = 1
	lvBadge.BorderSizePixel = 0
	lvBadge.AnchorPoint = Vector2.new(0, 0.5)
	lvBadge.Position = UDim2.fromOffset(TAG_W + GAP + NAME_W + GAP, 12)
	lvBadge.Size = UDim2.fromOffset(BADGE_W, 20)
	lvBadge.ZIndex = 53
	lvBadge.Parent = topCluster
	local lvStroke = Instance.new("UIStroke")
	lvStroke.Color     = HOLO_PANEL_BORDER
	lvStroke.Thickness = 1
	lvStroke.Parent    = lvBadge

	local lvText = Instance.new("TextLabel")
	lvText.BackgroundTransparency = 1
	lvText.BorderSizePixel = 0
	lvText.Size = UDim2.fromScale(1, 1)
	lvText.Font = FONT_TITLE
	lvText.TextSize = 11
	lvText.TextColor3 = COLOR_TEXT_DIM
	lvText.TextXAlignment = Enum.TextXAlignment.Center
	lvText.Text = string.format("LV %d", mercLevel)
	lvText.ZIndex = 54
	lvText.Parent = lvBadge

	-- ── Gem currency chip, right-edge pinned via dynamicBleed ────────
	local chip = Instance.new("Frame")
	chip.Name = "CurrencyChip"
	chip.AnchorPoint = Vector2.new(1, 0)
	chip.Position = UDim2.new(1, 0, 0, CHIP_Y)
	chip.Size = UDim2.fromOffset(84, 34)
	chip.BackgroundColor3 = HOLO_PANEL_FILL
	chip.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	chip.BorderSizePixel = 0
	chip.ZIndex = 52
	chip.Parent = scaleWrap
	local chipStroke = Instance.new("UIStroke")
	chipStroke.Color     = HOLO_PANEL_BORDER
	chipStroke.Thickness = 1
	chipStroke.Parent    = chip
	chipRef = chip

	local gemGlyph = makeGemIcon(chip, 13, COLOR_GOLD)
	gemGlyph.AnchorPoint = Vector2.new(0, 0.5)
	gemGlyph.Position = UDim2.new(0, 10, 0.5, 0)
	gemGlyph.ZIndex = 53

	local chipLabel = Instance.new("TextLabel")
	chipLabel.Name = "CurrencyLabel"
	chipLabel.BackgroundTransparency = 1
	chipLabel.BorderSizePixel = 0
	chipLabel.Position = UDim2.fromOffset(28, 0)
	chipLabel.Size = UDim2.new(1, -36, 1, 0)
	chipLabel.Font = FONT_TITLE
	chipLabel.TextSize = 13
	chipLabel.TextColor3 = COLOR_GOLD
	chipLabel.TextXAlignment = Enum.TextXAlignment.Left
	chipLabel.Text = "0"
	chipLabel.ZIndex = 53
	chipLabel.Parent = chip

	-- ── Equipment columns: MAIN HAND + RELIC (left) / SKINS + ARTIFACTS
	-- (right). Left column is backed by real data (MAIN HAND reflects
	-- the equipped weapon's rarity); the other three are decorative
	-- placeholders per the current data model — RELIC renders empty
	-- with zero stars, SKINS + ARTIFACTS render empty with a "+" badge.
	-- Selection is tracked across all four so Step 7's detail card can
	-- pull from whichever slot is active; equip wiring lands in Step 8.
	local LEFT_COL_X    = 40
	local RIGHT_COL_X   = REFERENCE_W - SLOT_W - LEFT_COL_X
	local TILE_TOP_Y    = 130
	local TILE_BOTTOM_Y = TILE_TOP_Y + SLOT_H + 20

	-- Resolve the equipped weapon's rarity from ctx.equipItems when
	-- provided; fall back to 1 star otherwise. MAIN HAND defaults
	-- to selected on open.
	local equippedWeaponId = "Sword"
	local mercFolder = player:FindFirstChild("Mercenaries")
	if mercFolder and ctx.mercName then
		local entry = mercFolder:FindFirstChild(ctx.mercName)
		if entry then
			local eq = entry:GetAttribute("EquippedWeapon")
			if eq and eq ~= "" then equippedWeaponId = eq end
		end
	end

	local function rarityForWeapon(id)
		local items = ctx.equipItems and ctx.equipItems.Weapons
		if not items then return 1 end
		for _, def in ipairs(items) do
			if def.id == id then return def.stars or 1 end
		end
		return 1
	end

	local slotHandles = {}
	local selectedSlot = "MainHand"

	local function selectSlot(slotKey)
		selectedSlot = slotKey
		for key, handle in pairs(slotHandles) do
			handle.setSelected(key == slotKey)
		end
	end

	slotHandles.MainHand = buildSlotTile(scaleWrap, {
		name         = "MAIN HAND",
		iconBuilder  = makeWeaponIcon,
		stars        = rarityForWeapon(equippedWeaponId),
		selected     = true,
		position     = UDim2.fromOffset(LEFT_COL_X, TILE_TOP_Y),
		zIndex       = 55,
		onClick      = function() selectSlot("MainHand") end,
	})

	slotHandles.Relic = buildSlotTile(scaleWrap, {
		name         = "RELIC",
		iconBuilder  = makeCrownIcon,
		stars        = 0,
		selected     = false,
		position     = UDim2.fromOffset(LEFT_COL_X, TILE_BOTTOM_Y),
		zIndex       = 55,
		onClick      = function() selectSlot("Relic") end,
	})

	slotHandles.Skins = buildSlotTile(scaleWrap, {
		name         = "SKINS",
		iconBuilder  = makeGemIcon,
		emptyGlyph   = true,
		selected     = false,
		position     = UDim2.fromOffset(RIGHT_COL_X, TILE_TOP_Y),
		zIndex       = 55,
		onClick      = function() selectSlot("Skins") end,
	})

	slotHandles.Artifacts = buildSlotTile(scaleWrap, {
		name         = "ARTIFACTS",
		iconBuilder  = makeDiamondIcon,
		emptyGlyph   = true,
		selected     = false,
		position     = UDim2.fromOffset(RIGHT_COL_X, TILE_BOTTOM_Y),
		zIndex       = 55,
		onClick      = function() selectSlot("Artifacts") end,
	})

	-- ── Centre: character viewport ───────────────────────────────────
	-- Two containers, same scaleWrap:
	--
	--   centreFrame  — visible 280×320 "viewport box" framed by
	--                  corner L brackets + two concentric rings + a
	--                  ground-glow ellipse. This is the Handling
	--                  mockup's decorative frame.
	--   viewportHost — invisible 160×506 host whose position + size
	--                  match MercenariesMenu's centreCol (400, 70,
	--                  160×506) 1:1. buildMercViewport reparents the
	--                  cached ViewportFrame here via UDim2.fromScale
	--                  (0.5, 0.34), so the character lands at the
	--                  exact same global artboard coords as on the
	--                  roster page — no animation restart, no jump.
	--
	-- vp.ZIndex is bumped above the frame decorations so the rig
	-- renders on top of the rings / L's / glow.
	local centreFrame = Instance.new("Frame")
	centreFrame.Name = "CentreFrame"
	centreFrame.BackgroundTransparency = 1
	centreFrame.BorderSizePixel = 0
	centreFrame.Position = UDim2.fromOffset(340, 130)
	centreFrame.Size = UDim2.fromOffset(280, 320)
	centreFrame.ZIndex = 50
	centreFrame.Parent = scaleWrap

	local groundGlow = Instance.new("Frame")
	groundGlow.Name = "GroundGlow"
	groundGlow.AnchorPoint = Vector2.new(0.5, 1)
	groundGlow.Position = UDim2.new(0.5, 0, 1, -14)
	groundGlow.Size = UDim2.fromOffset(200, 36)
	groundGlow.BackgroundColor3 = HORIZON
	groundGlow.BackgroundTransparency = 0.25
	groundGlow.BorderSizePixel = 0
	groundGlow.ZIndex = 51
	groundGlow.Parent = centreFrame
	local groundCorner = Instance.new("UICorner")
	groundCorner.CornerRadius = UDim.new(1, 0)
	groundCorner.Parent = groundGlow
	local groundGrad = Instance.new("UIGradient")
	groundGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1,   1),
	})
	groundGrad.Rotation = 0
	groundGrad.Parent = groundGlow

	local function rimCircle(sizePx, strokeColor, strokeTransparency)
		local r = Instance.new("Frame")
		r.Name = "RimCircle"
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.Position = UDim2.fromScale(0.5, 0.48)
		r.Size = UDim2.fromOffset(sizePx, sizePx)
		r.BackgroundTransparency = 1
		r.BorderSizePixel = 0
		r.ZIndex = 52
		r.Parent = centreFrame
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(1, 0)
		rc.Parent = r
		local rs = Instance.new("UIStroke")
		rs.Color        = strokeColor
		rs.Thickness    = 1
		rs.Transparency = strokeTransparency or 0
		rs.Parent       = r
		return r
	end
	rimCircle(240, HOLO_EDGE,          0.70)
	rimCircle(200, HOLO_PANEL_BORDER,  0.55)

	cornerLs(centreFrame, 16, HOLO_EDGE, 1.5)

	-- Clip frame around the viewport: stops the character at the
	-- top edge of the bottom cards (Y=452) so the pirate's legs are
	-- physically cropped, not covered by an opaque panel. Extends
	-- above the artboard top (Y=-100) so the cached vp — whose top
	-- edge lives at ~Y=-11 in scaleWrap-local — isn't trimmed at
	-- the head.
	local CLIP_TOP_OVERHANG = 100
	local CLIP_BOTTOM_Y     = 452 -- must equal BOTTOM_CARD_Y below
	local centreClip = Instance.new("Frame")
	centreClip.Name = "CentreClip"
	centreClip.BackgroundTransparency = 1
	centreClip.BorderSizePixel = 0
	centreClip.ClipsDescendants = true
	centreClip.Position = UDim2.fromOffset(0, -CLIP_TOP_OVERHANG)
	centreClip.Size = UDim2.fromOffset(REFERENCE_W, CLIP_BOTTOM_Y + CLIP_TOP_OVERHANG)
	centreClip.ZIndex = 50
	centreClip.Parent = scaleWrap

	local viewportHost = Instance.new("Frame")
	viewportHost.Name = "ViewportHost"
	viewportHost.BackgroundTransparency = 1
	viewportHost.BorderSizePixel = 0
	-- Mirrors MercenariesMenu's `slot` (which is the vp's direct parent
	-- there): slot lives at centreCol (Y=70) + (META_HEIGHT - 10) = 104
	-- with height = centreCol.H - 34 = 472. buildMercViewport positions
	-- the cached vp at UDim2.fromScale(0.5, 0.34), so the vp center Y
	-- resolves to (104 + 472*0.34) = 264.48 in scaleWrap-local —
	-- pixel-matching the roster page. Because centreClip is offset
	-- -CLIP_TOP_OVERHANG on Y, we add that back into viewportHost's
	-- local Y so the final global Y is unchanged.
	viewportHost.Position = UDim2.fromOffset(400, 104 + CLIP_TOP_OVERHANG)
	viewportHost.Size = UDim2.fromOffset(160, 472)
	viewportHost.ZIndex = 55
	viewportHost.Parent = centreClip

	if ctx.buildMercViewport and ctx.mercName then
		local vp = ctx.buildMercViewport(viewportHost, ctx.mercName, equippedWeaponId)
		if vp then
			vp.ZIndex = 60 -- above rings / glow / L brackets
		end
	end

	-- ── Bottom row: detail card + DNA Research card ──────────────────
	-- Two 360×130 holo panels side-by-side at the foot of the artboard.
	-- Detail card reflects the currently-selected slot (rebuilt in full
	-- on selectSlot so populated / empty variants share no stale UI
	-- state). DNA card is static placeholder data for now — the STUDY
	-- DNA click-through to the dedicated DNA Study sub-page lands in
	-- Step 7 (commit-numbering) alongside the equip-remote wiring.

	local BOTTOM_CARD_W = 360
	local BOTTOM_CARD_H = 130
	local BOTTOM_CARD_Y = 452
	local BOTTOM_CARD_GAP = 20
	local BOTTOM_LEFT_X  = (REFERENCE_W - (BOTTOM_CARD_W * 2 + BOTTOM_CARD_GAP)) / 2
	local BOTTOM_RIGHT_X = BOTTOM_LEFT_X + BOTTOM_CARD_W + BOTTOM_CARD_GAP

	-- Slot-card metadata — drives the detail card's icon / label /
	-- data-category lookup when selectSlot fires. `category` is the
	-- EQUIP_ITEMS key to search for the equipped item; nil = no server
	-- data, render the empty-placeholder variant.
	local SLOT_DEFS = {
		MainHand  = { label = "MAIN HAND", iconBuilder = makeWeaponIcon,  category = "Weapons" },
		Relic     = { label = "RELIC",     iconBuilder = makeCrownIcon,   category = nil       },
		Skins     = { label = "SKINS",     iconBuilder = makeGemIcon,     category = nil       },
		Artifacts = { label = "ARTIFACTS", iconBuilder = makeDiamondIcon, category = nil       },
	}

	local function resolveSlotItem(slotKey)
		local def = SLOT_DEFS[slotKey]
		if not def or not def.category then return nil end
		local items = ctx.equipItems and ctx.equipItems[def.category]
		if not items then return nil end
		if slotKey == "MainHand" then
			for _, w in ipairs(items) do
				if w.id == equippedWeaponId then return w end
			end
		end
		return nil
	end

	-- Detail card shell. Keeps the same holo translucency as the slot
	-- tiles — the pirate is cropped by a dedicated ClipsDescendants
	-- frame around the viewport below, NOT by painting the card fully
	-- opaque (which would lose the holo aesthetic).
	local detailCard = Instance.new("Frame")
	detailCard.Name = "DetailCard"
	detailCard.BackgroundColor3 = HOLO_PANEL_FILL
	detailCard.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	detailCard.BorderSizePixel = 0
	detailCard.Position = UDim2.fromOffset(BOTTOM_LEFT_X, BOTTOM_CARD_Y)
	detailCard.Size = UDim2.fromOffset(BOTTOM_CARD_W, BOTTOM_CARD_H)
	-- ZIndex 70 sits above the viewport subtree (Z 55) so the cards
	-- clip the character — the pirate's legs disappear behind the
	-- card edges instead of spilling over them. ViewportFrame's
	-- internal 3D render seems to beat equal-Z Sibling ordering, so
	-- we need a decisively higher Z here rather than relying on
	-- creation-order tie-breaks.
	detailCard.ZIndex = 70
	detailCard.Parent = scaleWrap
	local dcStroke = Instance.new("UIStroke")
	dcStroke.Color     = HOLO_PANEL_BORDER
	dcStroke.Thickness = 1
	dcStroke.Parent    = detailCard
	table.insert(motesOccludeList, detailCard)

	local detailPad = 14
	local detailContent = Instance.new("Frame")
	detailContent.Name = "Content"
	detailContent.BackgroundTransparency = 1
	detailContent.BorderSizePixel = 0
	detailContent.Position = UDim2.fromOffset(detailPad, detailPad)
	detailContent.Size = UDim2.new(1, -detailPad * 2, 1, -detailPad * 2)
	detailContent.ZIndex = 71
	detailContent.Parent = detailCard

	local function refreshDetailCard(slotKey)
		for _, child in detailContent:GetChildren() do child:Destroy() end

		local def = SLOT_DEFS[slotKey] or SLOT_DEFS.MainHand
		local item = resolveSlotItem(slotKey)

		if item then
			-- Populated variant: icon + name + stars/tag + divider + stat
			local iconBox = Instance.new("Frame")
			iconBox.Name = "IconBox"
			iconBox.BackgroundColor3 = Color3.fromRGB(16, 34, 58)
			iconBox.BackgroundTransparency = 0.3
			iconBox.BorderSizePixel = 0
			iconBox.Position = UDim2.fromOffset(0, 0)
			iconBox.Size = UDim2.fromOffset(40, 40)
			iconBox.ZIndex = 72
			iconBox.Parent = detailContent
			local iconStroke = Instance.new("UIStroke")
			iconStroke.Color     = HOLO_PANEL_BORDER
			iconStroke.Thickness = 1
			iconStroke.Parent    = iconBox

			local glyph = def.iconBuilder(iconBox, 26, HOLO_EDGE)
			if glyph then
				glyph.AnchorPoint = Vector2.new(0.5, 0.5)
				glyph.Position = UDim2.fromScale(0.5, 0.5)
				glyph.ZIndex = 73
			end

			local textX = 50
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "Name"
			nameLabel.BackgroundTransparency = 1
			nameLabel.BorderSizePixel = 0
			nameLabel.Position = UDim2.fromOffset(textX, 0)
			nameLabel.Size = UDim2.new(1, -textX, 0, 22)
			nameLabel.Font = FONT_TITLE
			nameLabel.TextSize = 17
			nameLabel.TextColor3 = COLOR_TEXT
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Text = item.displayName or item.id or "—"
			nameLabel.ZIndex = 72
			nameLabel.Parent = detailContent

			local starRow = makeStarRow(detailContent, item.stars or 1, 5, 9, COLOR_GOLD)
			starRow.Name = "Stars"
			starRow.AnchorPoint = Vector2.new(0, 0)
			starRow.Position = UDim2.fromOffset(textX, 26)
			starRow.ZIndex = 72

			local tag = Instance.new("TextLabel")
			tag.Name = "SlotTag"
			tag.BackgroundTransparency = 1
			tag.BorderSizePixel = 0
			tag.Position = UDim2.fromOffset(textX + 5 * 9 + 4 * 2 + 10, 24)
			tag.Size = UDim2.fromOffset(140, 14)
			tag.Font = FONT_TITLE
			tag.TextSize = 11
			tag.TextColor3 = COLOR_TEXT_DIM
			tag.TextXAlignment = Enum.TextXAlignment.Left
			tag.Text = def.label
			tag.ZIndex = 72
			tag.Parent = detailContent

			local divider = Instance.new("Frame")
			divider.Name = "Divider"
			divider.BackgroundColor3 = HOLO_PANEL_BORDER
			divider.BackgroundTransparency = 0.4
			divider.BorderSizePixel = 0
			divider.Position = UDim2.fromOffset(0, 58)
			divider.Size = UDim2.new(1, 0, 0, 1)
			divider.ZIndex = 72
			divider.Parent = detailContent

			local statRow = Instance.new("Frame")
			statRow.Name = "StatRow"
			statRow.BackgroundTransparency = 1
			statRow.BorderSizePixel = 0
			statRow.Position = UDim2.fromOffset(0, 72)
			statRow.Size = UDim2.new(1, 0, 0, 20)
			statRow.ZIndex = 72
			statRow.Parent = detailContent

			local spark = makeSparkIcon(statRow, 12, HOLO_EDGE)
			spark.AnchorPoint = Vector2.new(0, 0.5)
			spark.Position = UDim2.new(0, 0, 0.5, 0)
			spark.ZIndex = 73

			local statLbl = Instance.new("TextLabel")
			statLbl.BackgroundTransparency = 1
			statLbl.BorderSizePixel = 0
			statLbl.Position = UDim2.fromOffset(18, 0)
			statLbl.Size = UDim2.new(1, -18, 1, 0)
			statLbl.Font = FONT_BODY
			statLbl.TextSize = 13
			statLbl.TextColor3 = COLOR_TEXT_DIM
			statLbl.TextXAlignment = Enum.TextXAlignment.Left
			statLbl.Text = "Damage"
			statLbl.ZIndex = 73
			statLbl.Parent = statRow

			local statVal = Instance.new("TextLabel")
			statVal.BackgroundTransparency = 1
			statVal.BorderSizePixel = 0
			statVal.AnchorPoint = Vector2.new(1, 0)
			statVal.Position = UDim2.fromScale(1, 0)
			statVal.Size = UDim2.fromOffset(60, 20)
			statVal.Font = FONT_TITLE
			statVal.TextSize = 15
			statVal.TextColor3 = HOLO_EDGE
			statVal.TextXAlignment = Enum.TextXAlignment.Right
			statVal.Text = string.format("+%d", item.baseAttack or 0)
			statVal.ZIndex = 73
			statVal.Parent = statRow
		else
			-- Empty variant: centred slot label + "not equipped" subtext
			local emptyHeader = Instance.new("TextLabel")
			emptyHeader.Name = "EmptyHeader"
			emptyHeader.BackgroundTransparency = 1
			emptyHeader.BorderSizePixel = 0
			emptyHeader.Position = UDim2.fromScale(0, 0.25)
			emptyHeader.Size = UDim2.new(1, 0, 0, 22)
			emptyHeader.Font = FONT_TITLE
			emptyHeader.TextSize = 17
			emptyHeader.TextColor3 = COLOR_TEXT_DIM
			emptyHeader.TextXAlignment = Enum.TextXAlignment.Center
			emptyHeader.Text = def.label
			emptyHeader.ZIndex = 72
			emptyHeader.Parent = detailContent

			local emptyBody = Instance.new("TextLabel")
			emptyBody.Name = "EmptyBody"
			emptyBody.BackgroundTransparency = 1
			emptyBody.BorderSizePixel = 0
			emptyBody.Position = UDim2.fromScale(0, 0.55)
			emptyBody.Size = UDim2.new(1, 0, 0, 18)
			emptyBody.Font = FONT_BODY
			emptyBody.TextSize = 13
			emptyBody.TextColor3 = COLOR_TEXT_MUTE
			emptyBody.TextXAlignment = Enum.TextXAlignment.Center
			emptyBody.Text = "No " .. def.label:lower() .. " equipped"
			emptyBody.ZIndex = 72
			emptyBody.Parent = detailContent
		end
	end

	-- Extend selectSlot to also refresh the detail card. The tile
	-- onClick closures captured `selectSlot` as a mutable upvalue, so
	-- reassigning it here is enough — their next click picks up the
	-- extended version automatically (no reconnection needed).
	local baseSelectSlot = selectSlot
	selectSlot = function(slotKey)
		baseSelectSlot(slotKey)
		refreshDetailCard(slotKey)
	end
	refreshDetailCard(selectedSlot)

	-- DNA Research card (placeholder data for now)
	local dnaCard = Instance.new("Frame")
	dnaCard.Name = "DnaCard"
	dnaCard.BackgroundColor3 = HOLO_PANEL_FILL
	dnaCard.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	dnaCard.BorderSizePixel = 0
	dnaCard.Position = UDim2.fromOffset(BOTTOM_RIGHT_X, BOTTOM_CARD_Y)
	dnaCard.Size = UDim2.fromOffset(BOTTOM_CARD_W, BOTTOM_CARD_H)
	dnaCard.ZIndex = 70 -- see DetailCard ZIndex note above
	dnaCard.Parent = scaleWrap
	local dnStroke = Instance.new("UIStroke")
	dnStroke.Color     = HOLO_PANEL_BORDER
	dnStroke.Thickness = 1
	dnStroke.Parent    = dnaCard
	table.insert(motesOccludeList, dnaCard)

	local dnaPad = 14
	local dnaContent = Instance.new("Frame")
	dnaContent.BackgroundTransparency = 1
	dnaContent.BorderSizePixel = 0
	dnaContent.Position = UDim2.fromOffset(dnaPad, dnaPad)
	dnaContent.Size = UDim2.new(1, -dnaPad * 2, 1, -dnaPad * 2)
	dnaContent.ZIndex = 71
	dnaContent.Parent = dnaCard

	-- Header: helix glyph (small) + DNA RESEARCH title + NN% (right)
	local dnaHeader = Instance.new("Frame")
	dnaHeader.BackgroundTransparency = 1
	dnaHeader.BorderSizePixel = 0
	dnaHeader.Size = UDim2.new(1, 0, 0, 18)
	dnaHeader.ZIndex = 72
	dnaHeader.Parent = dnaContent

	local dnaHeaderGlyph = makeHelixIcon(dnaHeader, 10, HOLO_EDGE)
	dnaHeaderGlyph.AnchorPoint = Vector2.new(0, 0.5)
	dnaHeaderGlyph.Position = UDim2.new(0, 0, 0.5, 0)
	dnaHeaderGlyph.ZIndex = 73

	local dnaTitle = Instance.new("TextLabel")
	dnaTitle.BackgroundTransparency = 1
	dnaTitle.BorderSizePixel = 0
	dnaTitle.Position = UDim2.fromOffset(18, 0)
	dnaTitle.Size = UDim2.new(1, -58, 1, 0)
	dnaTitle.Font = FONT_TITLE
	dnaTitle.TextSize = 13
	dnaTitle.TextColor3 = COLOR_TEXT
	dnaTitle.TextXAlignment = Enum.TextXAlignment.Left
	dnaTitle.Text = "DNA RESEARCH"
	dnaTitle.ZIndex = 73
	dnaTitle.Parent = dnaHeader

	-- Placeholder progress numbers — real values get wired in a later step.
	local FRAGMENTS_DECODED = 10
	local FRAGMENTS_TOTAL   = 16
	local progressPct       = math.floor((FRAGMENTS_DECODED / FRAGMENTS_TOTAL) * 100 + 0.5)

	local dnaPct = Instance.new("TextLabel")
	dnaPct.BackgroundTransparency = 1
	dnaPct.BorderSizePixel = 0
	dnaPct.AnchorPoint = Vector2.new(1, 0)
	dnaPct.Position = UDim2.fromScale(1, 0)
	dnaPct.Size = UDim2.fromOffset(50, 18)
	dnaPct.Font = FONT_TITLE
	dnaPct.TextSize = 13
	dnaPct.TextColor3 = HOLO_EDGE
	dnaPct.TextXAlignment = Enum.TextXAlignment.Right
	dnaPct.Text = progressPct .. "%"
	dnaPct.ZIndex = 73
	dnaPct.Parent = dnaHeader

	-- Body: large helix on the left, fragments / bar / subtext stack on right
	local dnaBody = Instance.new("Frame")
	dnaBody.BackgroundTransparency = 1
	dnaBody.BorderSizePixel = 0
	dnaBody.Position = UDim2.fromOffset(0, 24)
	dnaBody.Size = UDim2.new(1, 0, 0, 52)
	dnaBody.ZIndex = 72
	dnaBody.Parent = dnaContent

	local bigHelix = makeHelixIcon(dnaBody, 28, HOLO_EDGE)
	bigHelix.AnchorPoint = Vector2.new(0, 0.5)
	bigHelix.Position = UDim2.new(0, 4, 0.5, 0)
	bigHelix.ZIndex = 73

	local fragmentsLbl = Instance.new("TextLabel")
	fragmentsLbl.BackgroundTransparency = 1
	fragmentsLbl.BorderSizePixel = 0
	fragmentsLbl.Position = UDim2.fromOffset(56, 0)
	fragmentsLbl.Size = UDim2.new(1, -56, 0, 16)
	fragmentsLbl.Font = FONT_BODY
	fragmentsLbl.TextSize = 13
	fragmentsLbl.TextColor3 = COLOR_TEXT_DIM
	fragmentsLbl.TextXAlignment = Enum.TextXAlignment.Left
	fragmentsLbl.RichText = true
	fragmentsLbl.Text = string.format(
		"Fragments decoded: <b><font color=\"rgb(220,240,255)\">%d/%d</font></b>",
		FRAGMENTS_DECODED, FRAGMENTS_TOTAL)
	fragmentsLbl.ZIndex = 73
	fragmentsLbl.Parent = dnaBody

	local barTrack, barFill = makeHoloBar(
		dnaBody,
		UDim2.new(1, -60, 0, 6),
		FRAGMENTS_TOTAL)
	barTrack.Position = UDim2.fromOffset(56, 20)
	barTrack.ZIndex = 73
	barFill.Size = UDim2.new(FRAGMENTS_DECODED / FRAGMENTS_TOTAL, 0, 1, 0)

	local dnaSubtext = Instance.new("TextLabel")
	dnaSubtext.BackgroundTransparency = 1
	dnaSubtext.BorderSizePixel = 0
	dnaSubtext.Position = UDim2.fromOffset(56, 30)
	dnaSubtext.Size = UDim2.new(1, -56, 0, 16)
	dnaSubtext.Font = FONT_BODY
	dnaSubtext.TextSize = 11
	dnaSubtext.TextColor3 = COLOR_TEXT_MUTE
	dnaSubtext.TextXAlignment = Enum.TextXAlignment.Left
	dnaSubtext.Text = "Hunt more pirates to decode additional DNA fragments."
	dnaSubtext.ZIndex = 73
	dnaSubtext.Parent = dnaBody

	-- STUDY DNA button
	local studyBtn = Instance.new("TextButton")
	studyBtn.Name = "StudyDna"
	studyBtn.BackgroundColor3 = Color3.fromRGB(18, 44, 78)
	studyBtn.BackgroundTransparency = 0.1
	studyBtn.BorderSizePixel = 0
	studyBtn.AnchorPoint = Vector2.new(0, 1)
	studyBtn.Position = UDim2.new(0, 0, 1, 0)
	studyBtn.Size = UDim2.new(1, 0, 0, 26)
	studyBtn.AutoButtonColor = true
	studyBtn.Text = ""
	studyBtn.ZIndex = 72
	studyBtn.Parent = dnaContent
	local sbStroke = Instance.new("UIStroke")
	sbStroke.Color     = HOLO_EDGE
	sbStroke.Thickness = 1
	sbStroke.Parent    = studyBtn
	local sbGrad = Instance.new("UIGradient")
	sbGrad.Rotation = 90
	sbGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 90, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 50, 90)),
	})
	sbGrad.Parent = studyBtn

	local studyLbl = Instance.new("TextLabel")
	studyLbl.BackgroundTransparency = 1
	studyLbl.BorderSizePixel = 0
	studyLbl.AnchorPoint = Vector2.new(0.5, 0.5)
	studyLbl.Position = UDim2.fromScale(0.5, 0.5)
	studyLbl.Size = UDim2.fromScale(1, 1)
	studyLbl.Font = FONT_TITLE
	studyLbl.TextSize = 14
	studyLbl.TextColor3 = COLOR_TEXT
	studyLbl.Text = "STUDY DNA"
	studyLbl.ZIndex = 73
	studyLbl.Parent = studyBtn

	local studyChev = makeChevronRight(studyBtn, 12, COLOR_TEXT)
	studyChev.AnchorPoint = Vector2.new(1, 0.5)
	studyChev.Position = UDim2.new(1, -14, 0.5, 0)
	studyChev.ZIndex = 73

	studyBtn.MouseButton1Click:Connect(function()
		-- Stub — Step 7 (commit-numbering) will close the Handling page
		-- and open the dedicated DNA Study sub-page per the Claude
		-- Design `05 · DNA Study` mockup.
		print("[HandlingPage] STUDY DNA clicked (stub)")
	end)

	-- Force the first scale computation now that the refs are all
	-- set (the earlier updateResponsiveScale() call happened before
	-- backBtnRef was assigned).
	updateResponsiveScale()

	-- Clean up listeners when the page leaves the hierarchy.
	table.insert(activeConnections, page.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			disconnectAll(activeConnections)
			table.clear(motesOccludeList)
		end
	end))
end

_G.OpenHandlingPage  = openHandlingPage
_G.CloseHandlingPage = closeHandlingPage
