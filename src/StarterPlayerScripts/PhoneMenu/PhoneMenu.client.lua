-- PhoneMenu.client.lua
-- Full-screen menu that opens when the player presses E while holding the
-- Phone tool. This milestone is VISUALS ONLY — layout, panels and labels
-- are built, but none of the buttons/bars are wired to gameplay.
--
-- Layout (matches the reference mockup):
--   top-left     : level badge + upgrade points counter
--   left column  : attribute bars (Strength / Mana / Mutation)
--   bottom       : XP bar
--   top-right    : daily tasks + reward
--   bottom-right : Arsenal / Mercenaries buttons

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

-- Pose used for the viewport character. Custom looping idle that keeps the
-- rig in a clean standing stance for the UI preview.
local IDLE_ANIMATION_ID = "rbxassetid://78578604994580"

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── Theme ────────────────────────────────────────────────────────────────
local COLOR_BG          = Color3.fromRGB(10, 24, 46)
local COLOR_PANEL       = Color3.fromRGB(16, 34, 66)
local COLOR_PANEL_EDGE  = Color3.fromRGB(92, 195, 255)
local COLOR_ACCENT      = Color3.fromRGB(130, 220, 255)
local COLOR_TEXT        = Color3.fromRGB(220, 240, 255)
local COLOR_TEXT_DIM    = Color3.fromRGB(155, 198, 232)
local COLOR_BAR_BG      = Color3.fromRGB(26, 58, 96)
local COLOR_BAR_FILL    = Color3.fromRGB(118, 210, 255)
local COLOR_XP_FILL     = Color3.fromRGB(138, 228, 255)

-- Holo panel palette — ported from the Claude Design mockup. Panels use a
-- translucent navy fill with a hairline oklch-approximated border and a
-- softer cyan colour for the four corner L-brackets. Declared up top so
-- the rest of the file can reuse them as we progressively swap old
-- elements over to the new visual language.
local HOLO_PANEL_FILL         = Color3.fromRGB(14, 34, 62)   -- brighter navy
local HOLO_PANEL_TRANSPARENCY = 0.22
local HOLO_PANEL_BORDER       = Color3.fromRGB(90, 132, 172)
local HOLO_PANEL_LBRACKET     = Color3.fromRGB(116, 188, 232)
local HOLO_EDGE               = Color3.fromRGB(176, 232, 255)
local HOLO_DEEP               = Color3.fromRGB(28, 58, 92)
local COLOR_GOLD              = Color3.fromRGB(230, 190, 100)-- oklch(0.85 0.14 85)
local HORIZON                 = Color3.fromRGB(98, 168, 218) -- cyan horizon band
local PLUS_BTN_BG_ACTIVE      = Color3.fromRGB(52, 64, 82)
local PLUS_BTN_BG_INACTIVE    = Color3.fromRGB(16, 34, 58)

local FONT_TITLE = Enum.Font.GothamBold
local FONT_BODY  = Enum.Font.Gotham

-- Panels registered here occlude the drifting backdrop motes — when a
-- mote drifts behind any of these rects, the Heartbeat loop inside
-- buildHoloBackground bumps its transparency to nearly 1 so the holo
-- surfaces don't read as "speckled". Populated by buildMenu() once
-- each card is created.
local motesOccludeList = {}

-- ─── State ────────────────────────────────────────────────────────────────
local menuOpen              = false
local phoneEquipped         = false
local screenGui             = nil
-- Refs used by the inline holo-open animation. While the animation is
-- running, `holoCover` sits over the whole UI as an opaque fullscreen
-- Frame that hides the menu content; at the reveal moment we tween
-- its BackgroundTransparency out (while `menuRootScale` scales the
-- panels in underneath) so the menu "materializes" as the cover
-- dissolves. `loadingOverlay` is on top of the cover. `menuRoot` and
-- `menuRootBasePosition` are used by the lightweight slide-up open
-- animation played on every open after the first.
local menuRoot              = nil
local menuRootBasePosition  = nil
local menuRootScale         = nil
local holoCover             = nil
local loadingOverlay        = nil
local loadingBar            = nil
local loadingText           = nil
local loadingStroke         = nil
-- Incremented every time the menu is opened so an in-flight animation
-- from a previous open can bail out cleanly if the user closes and
-- reopens before it finishes.
local openAnimationToken    = 0
-- Set to true the first time the full holo-open animation finishes in
-- this session. Once set, subsequent opens play the much shorter
-- slide-up animation instead so only the initial reveal has the heavy
-- sci-fi effect.
local holoOpenPlayed        = false
-- Set to true after `refreshCharacterViewport()` has built the rig for the
-- current life. Gates the refresh so subsequent menu opens are instant and
-- reuse the same viewport contents. Reset to false when the player respawns
-- so the next open rebuilds against the new character.
local viewportInitialized   = false

-- ─── Small UI helpers ─────────────────────────────────────────────────────
local function stroke(parent, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 1.5
	s.Color     = color or COLOR_PANEL_EDGE
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function padding(parent, px)
	local p = Instance.new("UIPadding")
	p.PaddingTop    = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft   = UDim.new(0, px)
	p.PaddingRight  = UDim.new(0, px)
	p.Parent = parent
	return p
end

-- Four small L-shaped brackets tucked just outside each corner of a panel
-- — the signature angular accent from the Claude Design mockup. Each
-- bracket is two thin Frames (horizontal + vertical) sharing the corner
-- anchor. Offset 1px outward so the brackets kiss the panel border
-- cleanly instead of overlapping it.
local function cornerLs(parent, size, color, thickness)
	size      = size      or 10
	color     = color     or HOLO_PANEL_LBRACKET
	thickness = thickness or 1.5

	-- If the parent has UIPadding, every descendant (including these
	-- brackets) is shifted inward by the pad amount, which would park
	-- the L's *inside* the content box instead of on the panel's
	-- outer border. Read the pad offsets and counter them so the
	-- brackets always sit on the real edge of the parent frame. Peek
	-- at each side separately so asymmetric padding (XPPanel's 14/8
	-- case) still lands correctly.
	local pad = parent:FindFirstChildOfClass("UIPadding")
	local padL = (pad and pad.PaddingLeft.Offset)   or 0
	local padR = (pad and pad.PaddingRight.Offset)  or 0
	local padT = (pad and pad.PaddingTop.Offset)    or 0
	local padB = (pad and pad.PaddingBottom.Offset) or 0

	local function addL(ax, ay, ox, oy)
		local effOx = (ax < 0.5) and (ox - padL) or (ox + padR)
		local effOy = (ay < 0.5) and (oy - padT) or (oy + padB)

		local horiz = Instance.new("Frame")
		horiz.Name = "CornerL_H"
		horiz.AnchorPoint = Vector2.new(ax, ay)
		horiz.Position = UDim2.new(ax, effOx, ay, effOy)
		horiz.Size = UDim2.fromOffset(size, thickness)
		horiz.BackgroundColor3 = color
		horiz.BorderSizePixel = 0
		horiz.ZIndex = (parent.ZIndex or 1) + 1
		horiz.Parent = parent

		local vert = Instance.new("Frame")
		vert.Name = "CornerL_V"
		vert.AnchorPoint = Vector2.new(ax, ay)
		vert.Position = UDim2.new(ax, effOx, ay, effOy)
		vert.Size = UDim2.fromOffset(thickness, size)
		vert.BackgroundColor3 = color
		vert.BorderSizePixel = 0
		vert.ZIndex = (parent.ZIndex or 1) + 1
		vert.Parent = parent
	end

	addL(0, 0, -1, -1) -- top-left
	addL(1, 0,  1, -1) -- top-right
	addL(0, 1, -1,  1) -- bottom-left
	addL(1, 1,  1,  1) -- bottom-right
end

-- Drop-in replacement for the hand-drawn icon factories when a real
-- image asset exists. Same call shape (parent, size, ...) so the
-- stats/loadout tables can hold either a function or just swap over
-- to an assetId via this helper.
local function imageIcon(parent, size, assetId)
	local img = Instance.new("ImageLabel")
	img.Name = "IconImage"
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Size = UDim2.fromOffset(size, size)
	img.ScaleType = Enum.ScaleType.Fit
	img.Image = assetId
	img.Parent = parent
	return img
end

-- Hand-drawn 4-point starburst — two crossed thin Frames inside a
-- square container. Used for gold accents (Upgrade Points row, XP
-- rewards). Returns the container so callers can reposition it.
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


-- Holo progress bar — dark track, thin holo border, gradient fill from
-- mid-holo to HOLO_EDGE. If `segments` > 0 the track is chopped by
-- (segments - 1) thin vertical dividers — matches the design's segment
-- indicator on stat and XP bars. Returns (track, fillFrame) so callers
-- resize the fill later to reflect progress.
local function makeHoloBar(parent, size, segments)
	local track = Instance.new("Frame")
	track.Name = "HoloBar"
	track.BackgroundColor3 = Color3.fromRGB(14, 34, 58)
	track.BackgroundTransparency = 0.15
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
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
			d.BackgroundColor3 = Color3.fromRGB(12, 30, 52)
			d.BackgroundTransparency = 0.28
			d.BorderSizePixel = 0
			d.ZIndex = (track.ZIndex or 1) + 2
			d.Parent = track
		end
	end

	return track, fill
end


-- Scroll — rounded rectangle body with three short horizontal lines
-- inside, hinting at a written parchment. Used as the Daily Tasks
-- header glyph.
local function makeScrollIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "ScrollIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromOffset(size * 0.78, size * 0.9)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Parent = c
	local uc = Instance.new("UICorner")
	uc.CornerRadius = UDim.new(0, math.max(1, math.floor(size * 0.15)))
	uc.Parent = body
	local bs = Instance.new("UIStroke")
	bs.Color     = color
	bs.Thickness = 1.5
	bs.Parent    = body

	local thick = math.max(1, math.floor(size * 0.08))
	for i = 1, 3 do
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0)
		line.Position = UDim2.fromScale(0.5, 0.25 + (i - 1) * 0.2)
		line.Size = UDim2.fromOffset(size * 0.44, thick)
		line.BackgroundColor3 = color
		line.BorderSizePixel = 0
		line.Parent = body
	end

	return c
end

-- Clock — circle outline with a minute hand (vertical up) and an hour
-- hand (short horizontal right). Used beside the daily-reset
-- countdown.
local function makeClockIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "ClockIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(size * 0.9, size * 0.9)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.Parent = c
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(1, 0)
	rc.Parent = ring
	local rs = Instance.new("UIStroke")
	rs.Color     = color
	rs.Thickness = 1.2
	rs.Parent    = ring

	local thick = math.max(1, math.floor(size * 0.09))
	local minute = Instance.new("Frame")
	minute.AnchorPoint = Vector2.new(0.5, 1)
	minute.Position = UDim2.fromScale(0.5, 0.5)
	minute.Size = UDim2.fromOffset(thick, size * 0.3)
	minute.BackgroundColor3 = color
	minute.BorderSizePixel = 0
	minute.Parent = c

	local hour = Instance.new("Frame")
	hour.AnchorPoint = Vector2.new(0, 0.5)
	hour.Position = UDim2.fromScale(0.5, 0.5)
	hour.Size = UDim2.fromOffset(size * 0.22, thick)
	hour.BackgroundColor3 = color
	hour.BorderSizePixel = 0
	hour.Parent = c

	return c
end

-- Check — two thin rotated Frames forming a ✓. Short leg at 45°, long
-- leg at -45°, meeting near the bottom-left. Used inside the Daily
-- Tasks checkbox when a quest is complete.
local function makeCheckIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "CheckIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local thick = math.max(1, math.floor(size * 0.18))
	local short = Instance.new("Frame")
	short.AnchorPoint = Vector2.new(0.5, 1)
	short.Position = UDim2.fromScale(0.30, 0.78)
	short.Size = UDim2.fromOffset(thick, size * 0.44)
	short.BackgroundColor3 = color
	short.BorderSizePixel = 0
	short.Rotation = 45
	short.Parent = c

	local long = Instance.new("Frame")
	long.AnchorPoint = Vector2.new(0.5, 1)
	long.Position = UDim2.fromScale(0.62, 0.64)
	long.Size = UDim2.fromOffset(thick, size * 0.80)
	long.BackgroundColor3 = color
	long.BorderSizePixel = 0
	long.Rotation = -45
	long.Parent = c

	return c
end

-- Chevron-right — two thin Frames meeting at the right forming a ">"
-- arrowhead. Used as the list-row affordance on Loadout buttons.
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

local function makePanel(name, parent)
	-- Holo panel ported from the Claude Design mockup: translucent
	-- navy fill, hairline cyan border, sharp corners. The four corner
	-- L brackets are NOT added here — callers add them *after* they
	-- apply UIPadding, so cornerLs can read the pad values and park
	-- the brackets exactly on the panel's outer edge instead of
	-- being shoved inward by the pad.
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = HOLO_PANEL_FILL
	f.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	f.BorderSizePixel = 0
	f.Parent = parent

	local s = Instance.new("UIStroke")
	s.Color           = HOLO_PANEL_BORDER
	s.Thickness       = 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent          = f

	return f
end

local function makeLabel(parent, text, font, size, color, align)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = font or FONT_BODY
	t.TextSize = size or 18
	t.TextColor3 = color or COLOR_TEXT
	t.Text = text or ""
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Parent = parent
	return t
end


-- ─── Holo background ─────────────────────────────────────────────────────
-- Deep-ocean sea-mist backdrop ported from the Claude Design mockup.
-- Layers: vertical gradient (bgA → bgB → bgC) → horizon glow band → top +
-- bottom vignette → drifting light motes. Built inside a single root
-- Frame so the rest of the UI can still treat the backdrop as one child
-- of the ScreenGui.
local function buildHoloBackground(parent)
	local BG_TOP   = Color3.fromRGB(18, 38, 66)
	local BG_MID   = Color3.fromRGB(28, 58, 92)
	local BG_BOT   = Color3.fromRGB(40, 80, 122)
	local MOTE_COL = Color3.fromRGB(180, 215, 240)
	local MOTE_COL = Color3.fromRGB(205, 236, 255)

	local root = Instance.new("Frame")
	root.Name = "Backdrop"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = BG_MID
	root.BorderSizePixel = 0
	root.ZIndex = 0
	root.Parent = parent

	-- Base vertical gradient
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    BG_TOP),
		ColorSequenceKeypoint.new(0.45, BG_MID),
		ColorSequenceKeypoint.new(1,    BG_BOT),
	})
	grad.Rotation = 90 -- top → bottom
	grad.Parent = root

	-- Horizon fog (no hard top/bottom borders): build many thin,
	-- overlapping horizontal-fade bands with Gaussian-weighted opacity.
	-- The stack approximates a blurred volumetric mist strip.
	local function buildHorizonFog(centerY, totalHeight, rows, peakOpacity)
		for i = 1, rows do
			local t = ((i - 1) / math.max(rows - 1, 1)) * 2 - 1 -- -1..1
			local weight = math.exp(-(t * t) * 3.2)
			local y = centerY + (t * totalHeight * 0.42)
			local band = Instance.new("Frame")
			band.Name = "HorizonFogBand"
			band.AnchorPoint = Vector2.new(0.5, 0.5)
			band.Position = UDim2.fromScale(0.5, y)
			band.Size = UDim2.fromScale(1.9, totalHeight / rows * 1.9)
			band.BackgroundColor3 = HORIZON
			band.BackgroundTransparency = 1 - (peakOpacity * weight)
			band.BorderSizePixel = 0
			band.ZIndex = 1
			band.Parent = root

			local g = Instance.new("UIGradient")
			local edge = 0.90 - (0.12 * weight)
			local center = 1 - (0.96 * weight)
			g.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0,    1),
				NumberSequenceKeypoint.new(0.30, edge),
				NumberSequenceKeypoint.new(0.50, center),
				NumberSequenceKeypoint.new(0.70, edge),
				NumberSequenceKeypoint.new(1,    1),
			})
			g.Rotation = 0
			g.Parent = band
		end
	end
	buildHorizonFog(0.42, 0.30, 22, 0.22)

	-- Vignette: darken top and bottom toward the screen edges so the
	-- panels sit in a soft tunnel of light.
	local function makeVignette(yPos, flip)
		local v = Instance.new("Frame")
		v.Name = flip and "VignetteBottom" or "VignetteTop"
		v.Size = UDim2.new(1, 0, 0.26, 0)
		v.Position = UDim2.fromScale(0, yPos)
		v.BackgroundColor3 = BG_MID
		v.BackgroundTransparency = 1
		v.BorderSizePixel = 0
		v.ZIndex = 2
		v.Parent = root
		local g = Instance.new("UIGradient")
		g.Transparency = flip
			and NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0.92),
			})
			or NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.92),
				NumberSequenceKeypoint.new(1, 1),
			})
		g.Rotation = 90
		g.Parent = v
	end
	makeVignette(0,    false)
	makeVignette(0.62, true)

	-- Drifting light motes: ~24 small glowing dots floating upward with
	-- per-mote random size, opacity, duration and slight horizontal drift
	-- — reshuffles after each pass so the loop never visibly resets.
	local motes = Instance.new("Frame")
	motes.Name = "Motes"
	motes.Size = UDim2.fromScale(1, 1)
	motes.BackgroundTransparency = 1
	motes.BorderSizePixel = 0
	motes.ClipsDescendants = true
	motes.ZIndex = 3
	motes.Parent = root

	-- +20% motes vs the previous 24 baseline.
	for _ = 1, 29 do
		local sizePx     = math.random(12, 32) / 10   -- 1.2 .. 3.2 px
		local duration   = 14 + math.random() * 14    -- 14 .. 28 s
		local startDelay = math.random() * 18
		local opacity    = 0.32 + math.random() * 0.58

		local mote = Instance.new("Frame")
		mote.Name = "Mote"
		mote.AnchorPoint = Vector2.new(0.5, 0.5)
		mote.Size = UDim2.fromOffset(sizePx, sizePx)
		mote.BackgroundColor3 = MOTE_COL
		mote.BackgroundTransparency = 1 - opacity
		mote.BorderSizePixel = 0
		mote.ZIndex = 4
		mote.Parent = motes
		-- Base transparency so the Heartbeat occlusion check below can
		-- restore it when a mote leaves a panel rect.
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

	-- Expose the motes container so the panel code below can register
	-- occluders (panels that should hide motes drifting behind them).
	-- Heartbeat runs the check every frame — 24 motes × ~6 panels is a
	-- trivial workload.
	RunService.Heartbeat:Connect(function()
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
	end)

	return root
end


-- ─── Menu construction ────────────────────────────────────────────────────
local viewportFrame = nil
local viewportWorld = nil
local viewportCamera = nil
local viewportCharModel = nil

-- Live references the Characteristics binding updates. Set during
-- buildMenu() and re-read by refreshCharacteristics() every time a
-- replicated IntValue changes.
local levelBadgeLabel    = nil
local upgradePointsLabel = nil
-- Upgradable attribute rows. Each entry is populated by buildMenu() and
-- consumed by refreshCharacteristics() to drive the bar, level label and
-- "+" button state from the replicated Characteristics folder.
local statRows = {
	Strength = { fill = nil, lvl = nil, button = nil, stroke = nil, plusIcon = nil, action = "upgradeStrength" },
	Mana     = { fill = nil, lvl = nil, button = nil, stroke = nil, plusIcon = nil, action = "upgradeMana"     },
	Mutation = { fill = nil, lvl = nil, button = nil, stroke = nil, plusIcon = nil, action = "upgradeMutation" },
}
local xpAmountLabel      = nil
local xpFillFrame        = nil
local xpLevelLabel       = nil

-- Tasks panel refs. `dailyQuestRows` is rebuilt every time the
-- replicated DailyQuests folder changes shape (new day, different
-- quest count) — each entry is keyed by quest id and holds the row
-- frame plus the check-box / label elements we repaint on progress
-- updates. `dailyClaimButton` becomes clickable once every quest is
-- complete, and goes away once the reward is claimed.
local dailyQuestsHolder  = nil
local dailyAllCompleteLabel = nil
local dailyRewardLabel   = nil
local dailyClaimButton   = nil
local dailyTimerLabel    = nil
local dailyResetButton   = nil
local dailyXPButton      = nil
local dailyQuestRows     = {}
local dailyQuestConnections = {}
local reflowDailyTasksLayout = nil

-- Build a static preview rig from the player's HumanoidDescription. This
-- gives us a fresh model in a clean neutral pose (like the Avatar Editor)
-- that matches the player's appearance, instead of a snapshot of the
-- live character mid-animation. Rig type is mirrored from the live
-- player so R6 / R15 idles drive the correct rig.
local function buildPreviewRig()
	local rigType = Enum.HumanoidRigType.R15
	local liveChar = player.Character
	if liveChar then
		local liveHum = liveChar:FindFirstChildOfClass("Humanoid")
		if liveHum and liveHum.RigType then
			rigType = liveHum.RigType
		end
	end

	local ok, rig = pcall(function()
		local desc = Players:GetHumanoidDescriptionFromUserId(player.UserId)
		return Players:CreateHumanoidModelFromDescription(desc, rigType)
	end)
	if ok and rig then return rig end

	-- Fallback: clone the live character.
	local char = player.Character
	if not char then return nil end
	local wasArchivable = char.Archivable
	char.Archivable = true
	local clone = char:Clone()
	char.Archivable = wasArchivable
	return clone
end

-- Rebuild the character display inside the ViewportFrame. Builds a fresh
-- preview rig from the player's HumanoidDescription (so the pose is always
-- clean and neutral), strips scripts, anchors parts, rotates it so its
-- front faces the camera, and attaches lights for depth. Called every time
-- the menu opens so the clone always reflects the current appearance.
local function refreshCharacterViewport()
	if not viewportFrame or not viewportWorld then return end

	if viewportCharModel then
		viewportCharModel:Destroy()
		viewportCharModel = nil
	end

	local clone = buildPreviewRig()
	if not clone then return end

	-- Destroy every Script / LocalScript on the rig — in particular the
	-- `Animate` LocalScript that drives walk/jump/idle animations on live
	-- characters. Without this the clone would keep cycling animations.
	-- Also strip Highlight / SelectionBox instances so the preview rig
	-- doesn't carry over any gameplay outlines (mining highlight, pickup
	-- glow, etc.) that might have been attached to the live character.
	for _, d in clone:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("Highlight") or d:IsA("SelectionBox") then
			d:Destroy()
		end
	end

	-- Stop any AnimationTracks that may already be playing on the humanoid
	-- / animator before we force our idle pose.
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local animator
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		-- Do NOT disable EvaluateStateMachine or SetStateEnabled(...) on
		-- every HumanoidStateType — that stops the Animator from ticking
		-- tracks (Motor6D.Transform never updates, rig stays in T-pose).
		-- Anchoring the HumanoidRootPart below is enough to keep the rig
		-- in place inside the WorldModel without simulating physics.
		animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end

	-- Only the HumanoidRootPart is anchored — the rest of the rig must
	-- remain unanchored so the idle AnimationTrack can pose the limbs via
	-- Motor6D.Transform. WorldModel does not simulate physics so the limbs
	-- cannot fall or drift regardless.
	local hrp = clone:FindFirstChild("HumanoidRootPart")
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Massless = true
			d.Anchored = (d == hrp)
		end
	end

	-- Place the clone at a slightly raised origin, rotated 180° around Y so
	-- its front faces the +Z axis — that's where the camera sits. The small
	-- +Y lift keeps the feet from sinking against the bottom of the frame.
	clone:PivotTo(CFrame.new(0, 0.5, 0) * CFrame.Angles(0, math.pi, 0))

	-- Force the custom idle animation. This mirrors the exact order that
	-- used to work with the stock Roblox idle — load the track, loop it,
	-- play it at Action priority. The clone gets parented to the
	-- WorldModel AFTER the lights block below, just like the original
	-- working version.
	if animator then
		local anim = Instance.new("Animation")
		anim.AnimationId = IDLE_ANIMATION_ID
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0)
	end

	-- Multi-light setup to give the clone depth and shape. A single light
	-- flattens the model — we need a bright key light in front and a cyan
	-- rim light behind for an outline glow. PointLights only render inside
	-- a ViewportFrame when their ancestor is a WorldModel (which the clone
	-- is parented to below). Attachments are used to position each light
	-- relative to the HumanoidRootPart.
	local root = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
	if root and root:IsA("BasePart") then
		-- Key light: white, in front and slightly above (camera side).
		local keyAtt = Instance.new("Attachment")
		keyAtt.Name = "PhoneMenuKeyLightAtt"
		keyAtt.Position = Vector3.new(0, 2, 4)
		keyAtt.Parent = root

		local keyLight = Instance.new("PointLight")
		keyLight.Name = "PhoneMenuKeyLight"
		keyLight.Color = Color3.fromRGB(255, 255, 255)
		keyLight.Brightness = 2
		keyLight.Range = 16
		keyLight.Shadows = false
		keyLight.Parent = keyAtt

		-- Rim light: cyan, behind the character for an outline glow.
		local rimAtt = Instance.new("Attachment")
		rimAtt.Name = "PhoneMenuRimLightAtt"
		rimAtt.Position = Vector3.new(0, 2, -4)
		rimAtt.Parent = root

		local rimLight = Instance.new("PointLight")
		rimLight.Name = "PhoneMenuRimLight"
		rimLight.Color = Color3.fromRGB(0, 255, 255)
		rimLight.Brightness = 2
		rimLight.Range = 14
		rimLight.Shadows = false
		rimLight.Parent = rimAtt

		-- Soft fill from below so the legs/torso don't read as a black slab.
		local fillAtt = Instance.new("Attachment")
		fillAtt.Name = "PhoneMenuFillLightAtt"
		fillAtt.Position = Vector3.new(-2, -1, 3)
		fillAtt.Parent = root

		local fillLight = Instance.new("PointLight")
		fillLight.Name = "PhoneMenuFillLight"
		fillLight.Color = Color3.fromRGB(180, 210, 255)
		fillLight.Brightness = 1
		fillLight.Range = 12
		fillLight.Shadows = false
		fillLight.Parent = fillAtt
	end

	clone.Parent = viewportWorld
	viewportCharModel = clone

	if viewportCamera then
		-- Centered front view, pulled in closer and aimed at chest height so
		-- the character reads larger and sits dead-center in the viewport.
		-- Narrower FOV (50) tightens the framing without cropping.
		viewportCamera.FieldOfView = 50
		viewportCamera.CFrame = CFrame.new(Vector3.new(0, 2.2, 6.2), Vector3.new(0, 1.2, 0))
	end
end

local function buildMenu()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PhoneMenu"
	screenGui.ResetOnSpawn = false
	-- IgnoreGuiInset = true so the backdrop covers the ENTIRE screen
	-- (including the strip behind the Roblox topbar). The Root frame
	-- below is manually pushed down past the topbar so the interactive
	-- panels still stay clear of the Roblox chrome.
	screenGui.IgnoreGuiInset = true
	screenGui.Enabled = false
	screenGui.DisplayOrder = 50
	screenGui.Parent = playerGui

	-- Holo backdrop ported from the Claude Design mockup. Fills the whole
	-- ScreenGui with the sea-mist gradient + horizon band + vignette +
	-- drifting light motes. Renders as the first child so the Root /
	-- holoCover siblings created below sit on top of it.
	local backdrop = buildHoloBackground(screenGui)

	-- Responsive artboard: keep a fixed reference canvas and scale it to
	-- fit the player viewport. A slightly smaller reference frame than
	-- before makes cards/rows read larger on common desktop resolutions
	-- while still remaining fully adaptive on smaller windows.
	-- Make `scaleWrap` a fixed frame centred
	-- on screen and drive its UIScale so the whole artboard grows or
	-- shrinks to match the viewport. Because UIScale multiplies the
	-- scale *and* offset parts of children's UDim2s, a screen-sized
	-- parent would push right-anchored panels (Position (1, 0, …)) to
	-- screen.width × scale — i.e. off the right edge on large displays.
	-- Fixing scaleWrap's own size keeps every Position (1, 0) landing
	-- on the artboard's own 960 mark, which the UIScale then maps
	-- correctly back onto the player's screen.
	local topInset = GuiService:GetGuiInset().Y
	local REFERENCE_W, REFERENCE_H = 860, 540

	local scaleWrap = Instance.new("Frame")
	scaleWrap.Name = "ScaleWrap"
	scaleWrap.BackgroundTransparency = 1
	scaleWrap.BorderSizePixel = 0
	-- Centred horizontally. Pushed down by topInset/2 so the artboard
	-- never clips into the Roblox topbar, even at maximum scale.
	scaleWrap.AnchorPoint = Vector2.new(0.5, 0.5)
	scaleWrap.Position = UDim2.new(0.5, 0, 0.5, topInset / 2)
	scaleWrap.Size = UDim2.fromOffset(REFERENCE_W, REFERENCE_H)
	scaleWrap.Parent = screenGui

	local responsiveScale = Instance.new("UIScale")
	responsiveScale.Name = "ResponsiveScale"
	responsiveScale.Scale = 1
	responsiveScale.Parent = scaleWrap

	-- Layout metrics used by all main cards so the menu can be tuned in one
	-- place. Wider columns + taller right cards reduce dead space and keep
	-- the composition dense (closer to the target Photoshop mockup).
	local COLUMN_W      = 320
	local EDGE_BLEED_X  = 28
	local LEVEL_Y       = 46
	local LEVEL_H       = 88
	local COLUMN_GAP    = 14
	local STATS_Y       = LEVEL_Y + LEVEL_H + COLUMN_GAP
	local STATS_H       = 220
	local TASKS_Y       = 12
	local TASKS_H       = 336
	local tasksPanelHeight = TASKS_H
	local SIDE_Y        = TASKS_Y + TASKS_H + COLUMN_GAP
	local SIDE_H        = 146

	local levelPanel, statsPanel, tasksPanel, sidePanel

	local function updateResponsiveScale()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then return end
		-- min(sx, sy) so the scaled artboard always fits — a 1920x1080
		-- window scales to ~1.74x, a Studio 1520x700 to ~1.11x, a tiny
		-- 800x450 window to ~0.69x. Floor at 0.5 so text never becomes
		-- unreadable on very small windows.
		local sx = size.X / REFERENCE_W
		local sy = (size.Y - topInset) / REFERENCE_H
		local s = math.min(sx, sy)
		if s < 0.5 then s = 0.5 end
		responsiveScale.Scale = s

		local artboardScreenW = REFERENCE_W * s
		local sideGapPx = math.max(0, size.X - artboardScreenW) * 0.5
		-- Pull columns back from the absolute edge so cards stay fully visible.
		-- We use only part of free side space and clamp the extra bleed.
		local sideGapArtboard = sideGapPx / s
		local extraBleed = math.clamp(sideGapArtboard * 0.75, 0, 120)
		local dynamicBleed = EDGE_BLEED_X + math.floor(extraBleed + 0.5)

		if levelPanel then
			levelPanel.Position = UDim2.fromOffset(-dynamicBleed, LEVEL_Y)
		end
		if statsPanel then
			statsPanel.Position = UDim2.fromOffset(-dynamicBleed, STATS_Y)
		end
		if tasksPanel then
			tasksPanel.Position = UDim2.new(1, dynamicBleed, 0, TASKS_Y)
		end
		if sidePanel then
			sidePanel.Position = UDim2.new(1, dynamicBleed, 0, TASKS_Y + tasksPanelHeight + COLUMN_GAP)
		end
	end
	updateResponsiveScale()
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateResponsiveScale)

	-- Root fills the scale wrap. Panels live here and position themselves
	-- within the 960x600 artboard coordinate space — e.g. right-column
	-- panels with Position (1, 0, …) anchor on the 960 mark and Anchor
	-- (1, 0) extends them leftward from there.
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.fromOffset(0, 0)
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = scaleWrap

	-- HoloScale on root (inner wrapper) — separate ancestor from the
	-- responsive scale above so the two UIScales compound correctly
	-- (Roblox honours only one UIScale per parent but multiplies
	-- across ancestors).
	local rootScale = Instance.new("UIScale")
	rootScale.Name = "HoloScale"
	rootScale.Scale = 1
	rootScale.Parent = root

	menuRoot             = root
	menuRootBasePosition = root.Position
	menuRootScale        = rootScale

	-- ── Center: character viewport ───────────────────────────────────────
	-- Plain ViewportFrame — no pedestal / rim rings / corner brackets.
	-- The character reads cleanest against the raw holo backdrop.
	viewportFrame = Instance.new("ViewportFrame")
	viewportFrame.Name = "CharacterViewport"
	viewportFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	viewportFrame.Position = UDim2.fromScale(0.5, 0.44)
	viewportFrame.Size = UDim2.fromOffset(420, 560)
	viewportFrame.BackgroundTransparency = 1
	viewportFrame.BorderSizePixel = 0
	viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)
	viewportFrame.LightDirection = Vector3.new(-0.3, -1, -0.5)
	viewportFrame.Ambient = Color3.fromRGB(180, 200, 230)
	viewportFrame.Parent = root
	table.insert(motesOccludeList, viewportFrame)

	-- WorldModel enables PointLight rendering inside the ViewportFrame.
	viewportWorld = Instance.new("WorldModel")
	viewportWorld.Name = "World"
	viewportWorld.Parent = viewportFrame

	viewportCamera = Instance.new("Camera")
	viewportCamera.FieldOfView = 55
	viewportCamera.CFrame = CFrame.new(Vector3.new(1.5, 2, 8), Vector3.new(0, 1, 0))
	viewportCamera.Parent = viewportFrame
	viewportFrame.CurrentCamera = viewportCamera

	-- ── Top-left: level + upgrade points ─────────────────────────────────
	-- Left column (level badge + stats) is nudged ~60px below the root's
	-- top edge so it clears the Roblox topbar icons (logo / menu / chat)
	-- on non-Studio clients where those buttons extend past GuiInset.
	-- Column geometry from MainMenu.jsx: left/right 24, top 70 (screen);
	-- Root is already inset by (30, topInset+20) so we position the
	-- panels inside it with fixed 280 width and 14 px gaps. Left column
	-- is pushed down further (y=50) so the Roblox default topbar icons
	-- (logo / menu / chat at top-left) never sit behind the LevelCard.
	levelPanel = makePanel("LevelPanel", root)
	levelPanel.AnchorPoint = Vector2.new(0, 0)
	levelPanel.Position = UDim2.fromOffset(-EDGE_BLEED_X, LEVEL_Y)
	levelPanel.Size = UDim2.fromOffset(COLUMN_W, LEVEL_H)
	padding(levelPanel, 12)
	cornerLs(levelPanel, 10, HOLO_PANEL_LBRACKET, 1.5)
	table.insert(motesOccludeList, levelPanel)

	-- Holo level badge: 50×50 square with the holo-edge border, a
	-- diagonal HOLO_DEEP → transparent sheen, mini corner L brackets,
	-- "LVL" tag above the big number. Sharp corners on purpose — the
	-- angular look matches the panel language.
	local lvlBadge = Instance.new("Frame")
	lvlBadge.Name = "LevelBadge"
	lvlBadge.BackgroundColor3 = HOLO_DEEP
	lvlBadge.BorderSizePixel = 0
	lvlBadge.Size = UDim2.fromOffset(58, 58)
	lvlBadge.Position = UDim2.fromOffset(0, 0)
	lvlBadge.Parent = levelPanel
	local lvlStroke = Instance.new("UIStroke")
	lvlStroke.Color     = HOLO_EDGE
	lvlStroke.Thickness = 1
	lvlStroke.Parent    = lvlBadge
	local lvlGrad = Instance.new("UIGradient")
	lvlGrad.Rotation = 135
	lvlGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0),
		NumberSequenceKeypoint.new(0.8, 0.85),
		NumberSequenceKeypoint.new(1,   1),
	})
	lvlGrad.Parent = lvlBadge
	cornerLs(lvlBadge, 5, HOLO_EDGE, 1.5)

	local lvlTag = makeLabel(lvlBadge, "LVL", FONT_TITLE, 11, HOLO_EDGE, Enum.TextXAlignment.Center)
	lvlTag.Size = UDim2.new(1, 0, 0, 14)
	lvlTag.Position = UDim2.fromOffset(0, 6)

	local lvlNum = makeLabel(lvlBadge, "1", FONT_TITLE, 26, COLOR_TEXT, Enum.TextXAlignment.Center)
	lvlNum.Size = UDim2.new(1, 0, 0, 30)
	lvlNum.Position = UDim2.fromOffset(0, 20)
	levelBadgeLabel = lvlNum

	-- Display name in the display weight, then the "Upgrade points:"
	-- row. The row is split across three instances so the spark icon,
	-- static label and live count can each be styled independently;
	-- refreshCharacteristics() only needs to drive the count.
	local nameLbl = makeLabel(levelPanel,
		player.DisplayName ~= "" and player.DisplayName or player.Name,
		FONT_TITLE, 22, COLOR_TEXT)
	nameLbl.Position = UDim2.fromOffset(70, 0)
	nameLbl.Size = UDim2.new(1, -70, 0, 32)

	local sparkIcon = makeSparkIcon(levelPanel, 13, COLOR_GOLD)
	sparkIcon.AnchorPoint = Vector2.new(0, 0.5)
	sparkIcon.Position = UDim2.fromOffset(70, 48)

	local upgradeLbl = makeLabel(levelPanel, "Upgrade points:", FONT_BODY, 14, COLOR_TEXT_DIM)
	upgradeLbl.Position = UDim2.fromOffset(88, 38)
	upgradeLbl.Size = UDim2.fromOffset(136, 20)

	local pointsLbl = makeLabel(levelPanel, "0", FONT_TITLE, 16, COLOR_GOLD)
	pointsLbl.TextXAlignment = Enum.TextXAlignment.Left
	pointsLbl.Position = UDim2.fromOffset(228, 38)
	pointsLbl.Size = UDim2.fromOffset(56, 20)
	upgradePointsLabel = pointsLbl

	-- ── Left column: player stats card ───────────────────────────────
	-- Stacked under LevelPanel: y = 50 (top) + 76 (LevelPanel) + 14 (gap).
	statsPanel = makePanel("StatsPanel", root)
	statsPanel.AnchorPoint = Vector2.new(0, 0)
	statsPanel.Position = UDim2.fromOffset(-EDGE_BLEED_X, STATS_Y)
	statsPanel.Size = UDim2.fromOffset(COLUMN_W, STATS_H)
	padding(statsPanel, 14)
	cornerLs(statsPanel, 10, HOLO_PANEL_LBRACKET, 1.5)
	table.insert(motesOccludeList, statsPanel)

	-- Card header: diamond glyph + uppercase title + thin divider under.
	local headerRow = Instance.new("Frame")
	headerRow.Name = "HeaderRow"
	headerRow.BackgroundTransparency = 1
	headerRow.Size = UDim2.new(1, 0, 0, 18)
	headerRow.Parent = statsPanel

	local headerDiamond = imageIcon(headerRow, 15, "rbxassetid://139484845530559")
	headerDiamond.AnchorPoint = Vector2.new(0, 0.5)
	headerDiamond.Position = UDim2.fromScale(0, 0.5)

	local statsTitle = makeLabel(headerRow, "PLAYER STATS", FONT_TITLE, 15, COLOR_TEXT)
	statsTitle.Position = UDim2.fromOffset(22, 0)
	statsTitle.Size = UDim2.new(1, -22, 1, 0)

	local headerDivider = Instance.new("Frame")
	headerDivider.Name = "Divider"
	headerDivider.BackgroundColor3 = HOLO_PANEL_BORDER
	headerDivider.BackgroundTransparency = 0.3
	headerDivider.BorderSizePixel = 0
	headerDivider.Size = UDim2.new(1, 0, 0, 1)
	headerDivider.Position = UDim2.fromOffset(0, 28)
	headerDivider.Parent = statsPanel

	-- Row holder — vertical list of 3 stat rows.
	local rowHolder = Instance.new("Frame")
	rowHolder.Name = "StatRows"
	rowHolder.BackgroundTransparency = 1
	rowHolder.Position = UDim2.fromOffset(0, 40)
	rowHolder.Size = UDim2.new(1, 0, 1, -40)
	rowHolder.Parent = statsPanel

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 14)
	list.Parent = rowHolder

	-- Stat row: 22×22 icon (left) + [label / LV line + segmented holo
	-- bar] (middle) + 22×22 upgrade button (right). Each stat picks a
	-- distinct hand-drawn glyph so the eye can find the row without
	-- reading the label. refreshCharacteristics() drives fill, LV label
	-- and the button's gold/dim state by hitting the refs we store in
	-- statRows[key].
	local stats = {
		{ key = "Strength", label = "STRENGTH", iconId = "rbxassetid://121469289292513" },
		{ key = "Mana",     label = "MANA",     iconId = "rbxassetid://77622787705265"  },
		{ key = "Mutation", label = "MUTATION", iconId = "rbxassetid://78141836386820"  },
	}
	for i, s in ipairs(stats) do
		local row = Instance.new("Frame")
		row.Name = "StatRow_" .. s.key
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 38)
		row.LayoutOrder = i
		row.Parent = rowHolder

		local rowIcon = imageIcon(row, 24, s.iconId)
		rowIcon.AnchorPoint = Vector2.new(0, 0.5)
		rowIcon.Position = UDim2.fromScale(0, 0.5)

		local content = Instance.new("Frame")
		content.Name = "Content"
		content.BackgroundTransparency = 1
		content.Position = UDim2.fromOffset(36, 0)
		content.Size = UDim2.new(1, -70, 1, 0)
		content.Parent = row

		local labelLine = makeLabel(content, s.label, FONT_BODY, 13, COLOR_TEXT_DIM)
		labelLine.Position = UDim2.fromOffset(0, 0)
		labelLine.Size = UDim2.new(0.6, 0, 0, 14)

		local lvlLabel = makeLabel(content, "LV 0", FONT_TITLE, 14, COLOR_TEXT, Enum.TextXAlignment.Right)
		lvlLabel.Position = UDim2.new(0.6, 0, 0, 0)
		lvlLabel.Size = UDim2.new(0.4, 0, 0, 14)

		local track, fill = makeHoloBar(content, UDim2.new(1, 0, 0, 8), STAT_BAR_SEGMENTS)
		track.Position = UDim2.fromOffset(0, 24)

		local btn = Instance.new("TextButton")
		btn.Name = s.key .. "Upgrade"
		btn.AnchorPoint = Vector2.new(1, 0.5)
		btn.Position = UDim2.new(1, 0, 0.5, 0)
		btn.Size = UDim2.fromOffset(24, 24)
		btn.BackgroundColor3 = PLUS_BTN_BG_INACTIVE
		btn.BackgroundTransparency = 0.08
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.AutoButtonColor = true
		btn.Parent = row

		local bStroke = Instance.new("UIStroke")
		bStroke.Color     = HOLO_PANEL_BORDER
		bStroke.Thickness = 1
		bStroke.Parent    = btn

		local plus = makeSparkIcon(btn, 13, COLOR_TEXT_DIM)
		plus.AnchorPoint = Vector2.new(0.5, 0.5)
		plus.Position = UDim2.fromScale(0.5, 0.5)

		local rec = statRows[s.key]
		rec.fill     = fill
		rec.lvl      = lvlLabel
		rec.button   = btn
		rec.stroke   = bStroke
		rec.plusIcon = plus
	end

	-- ── Top-right: daily tasks ─────────────────────────────────────────
	-- Holo-style card matching the TasksCard in MainMenu.jsx. Header =
	-- scroll glyph + "DAILY TASKS" title + clock glyph + countdown on
	-- the right; quests holder mid-card; reward summary with gold XP
	-- and iron chips; full-width claim button at the bottom, then the
	-- two DEV buttons muted underneath.
	tasksPanel = makePanel("TasksPanel", root)
	tasksPanel.AnchorPoint = Vector2.new(1, 0)
	tasksPanel.Position = UDim2.new(1, EDGE_BLEED_X, 0, TASKS_Y)
	tasksPanel.Size = UDim2.fromOffset(COLUMN_W, TASKS_H)
	padding(tasksPanel, 14)
	cornerLs(tasksPanel, 10, HOLO_PANEL_LBRACKET, 1.5)
	table.insert(motesOccludeList, tasksPanel)

	local taskHeader = Instance.new("Frame")
	taskHeader.Name = "HeaderRow"
	taskHeader.BackgroundTransparency = 1
	taskHeader.Size = UDim2.new(1, 0, 0, 18)
	taskHeader.Parent = tasksPanel

	local scrollGlyph = makeScrollIcon(taskHeader, 13, HOLO_EDGE)
	scrollGlyph.AnchorPoint = Vector2.new(0, 0.5)
	scrollGlyph.Position = UDim2.fromScale(0, 0.5)

	local tasksTitle = makeLabel(taskHeader, "DAILY TASKS", FONT_TITLE, 15, COLOR_TEXT)
	tasksTitle.Position = UDim2.fromOffset(22, 0)
	tasksTitle.Size = UDim2.fromOffset(140, 18)

	-- Countdown until the next UTC midnight. dailyTimerLabel is a
	-- module-level ref so the heartbeat task below can rewrite it
	-- every second while the menu exists. HH:MM:SS needs ~56 px at
	-- 11 pt Gotham; leave a little slack, then park the clock glyph
	-- just to the left with a 4 px gap.
	local TIMER_WIDTH = 60
	local timerLbl = makeLabel(taskHeader, "", FONT_BODY, 11, COLOR_TEXT_DIM, Enum.TextXAlignment.Right)
	timerLbl.AnchorPoint = Vector2.new(1, 0.5)
	timerLbl.Position = UDim2.new(1, 0, 0.5, 0)
	timerLbl.Size = UDim2.fromOffset(TIMER_WIDTH, 18)
	dailyTimerLabel = timerLbl

	local clockGlyph = makeClockIcon(taskHeader, 11, COLOR_TEXT_DIM)
	clockGlyph.AnchorPoint = Vector2.new(1, 0.5)
	clockGlyph.Position = UDim2.new(1, -(TIMER_WIDTH + 4), 0.5, 0)

	local taskDivider = Instance.new("Frame")
	taskDivider.BackgroundColor3 = HOLO_PANEL_BORDER
	taskDivider.BackgroundTransparency = 0.3
	taskDivider.BorderSizePixel = 0
	taskDivider.Size = UDim2.new(1, 0, 0, 1)
	taskDivider.Position = UDim2.fromOffset(0, 28)
	taskDivider.Parent = tasksPanel

	local tasksHolder = Instance.new("Frame")
	tasksHolder.Name = "TasksHolder"
	tasksHolder.BackgroundTransparency = 1
	tasksHolder.Position = UDim2.fromOffset(0, 40)
	tasksHolder.Size = UDim2.new(1, 0, 0, 82)
	tasksHolder.Parent = tasksPanel

	local tList = Instance.new("UIListLayout")
	tList.SortOrder = Enum.SortOrder.LayoutOrder
	tList.Padding = UDim.new(0, 8)
	tList.Parent = tasksHolder

	-- Shown in place of the quest rows once every quest is complete.
	local allDoneLbl = makeLabel(tasksPanel, "All tasks completed!", FONT_TITLE, 15, HOLO_EDGE, Enum.TextXAlignment.Center)
	allDoneLbl.Position = UDim2.fromOffset(0, 40)
	allDoneLbl.Size = UDim2.new(1, 0, 0, 82)
	allDoneLbl.Visible = false
	dailyAllCompleteLabel = allDoneLbl

	-- Reward line: "REWARD" tag + xp chip + iron chip, all on one row.
	local rewardRow = Instance.new("Frame")
	rewardRow.BackgroundTransparency = 1
	rewardRow.Position = UDim2.fromOffset(0, 134)
	rewardRow.Size = UDim2.new(1, 0, 0, 18)
	rewardRow.Parent = tasksPanel

	local rewardLbl = makeLabel(rewardRow, "REWARD", FONT_TITLE, 11, COLOR_TEXT)
	rewardLbl.Position = UDim2.fromOffset(0, 0)
	rewardLbl.Size = UDim2.fromOffset(54, 18)

	-- The "+X XP  +Y Iron" string lands here verbatim from
	-- updateDailyRewardAndButton. HOLO_EDGE so the count reads as an
	-- accent against the dim REWARD tag.
	local rewardValue = makeLabel(rewardRow, "", FONT_TITLE, 12, HOLO_EDGE)
	rewardValue.Position = UDim2.fromOffset(58, 0)
	rewardValue.Size = UDim2.new(1, -58, 1, 0)

	local claimBtn = Instance.new("TextButton")
	claimBtn.Name = "ClaimButton"
	claimBtn.BackgroundColor3 = Color3.fromRGB(22, 62, 110)
	claimBtn.BackgroundTransparency = 0.6
	claimBtn.BorderSizePixel = 0
	claimBtn.Position = UDim2.fromOffset(0, 164)
	claimBtn.Size = UDim2.new(1, 0, 0, 34)
	claimBtn.Font = FONT_TITLE
	claimBtn.TextSize = 14
	claimBtn.TextColor3 = COLOR_TEXT_DIM
	claimBtn.AutoButtonColor = false
	claimBtn.Text = "CLAIM REWARD"
	claimBtn.Active = false
	claimBtn.Parent = tasksPanel
	local claimStroke = Instance.new("UIStroke")
	claimStroke.Color = HOLO_PANEL_BORDER
	claimStroke.Thickness = 1
	claimStroke.Parent = claimBtn

	-- DEV: reset tasks button (rerolls quests for testing). Muted red
	-- variant of the holo button style.
	local resetBtn = Instance.new("TextButton")
	resetBtn.Name = "ResetTasksButton"
	resetBtn.BackgroundColor3 = Color3.fromRGB(90, 30, 30)
	resetBtn.BackgroundTransparency = 0.3
	resetBtn.BorderSizePixel = 0
	resetBtn.Position = UDim2.fromOffset(0, 206)
	resetBtn.Size = UDim2.new(1, 0, 0, 22)
	resetBtn.Font = FONT_BODY
	resetBtn.TextSize = 12
	resetBtn.TextColor3 = Color3.fromRGB(255, 180, 180)
	resetBtn.AutoButtonColor = true
	resetBtn.Text = "RESET TASKS (DEV)"
	resetBtn.Parent = tasksPanel
	local resetStroke = Instance.new("UIStroke")
	resetStroke.Color = Color3.fromRGB(180, 80, 80)
	resetStroke.Thickness = 1
	resetStroke.Parent = resetBtn

	-- DEV: +25 XP button for testing level-ups
	local xpBtn = Instance.new("TextButton")
	xpBtn.Name = "AddXPButton"
	xpBtn.BackgroundColor3 = Color3.fromRGB(30, 80, 40)
	xpBtn.BackgroundTransparency = 0.3
	xpBtn.BorderSizePixel = 0
	xpBtn.Position = UDim2.fromOffset(0, 236)
	xpBtn.Size = UDim2.new(1, 0, 0, 22)
	xpBtn.Font = FONT_BODY
	xpBtn.TextSize = 12
	xpBtn.TextColor3 = Color3.fromRGB(180, 255, 180)
	xpBtn.AutoButtonColor = true
	xpBtn.Text = "+25 XP (DEV)"
	xpBtn.Parent = tasksPanel
	local xpStroke = Instance.new("UIStroke")
	xpStroke.Color = Color3.fromRGB(80, 160, 90)
	xpStroke.Thickness = 1
	xpStroke.Parent = xpBtn

	dailyQuestsHolder = tasksHolder
	dailyRewardLabel  = rewardValue
	dailyClaimButton  = claimBtn
	dailyResetButton  = resetBtn
	dailyXPButton     = xpBtn

	-- Collapse/expand the Daily Tasks card to the actual quest-row count so
	-- the middle dead zone disappears for 2-3 quests but still scales when a
	-- day has more tasks.
	reflowDailyTasksLayout = function(questCount)
		questCount = math.max(questCount or 0, 0)
		local holderH = 54
		if questCount > 0 then
			holderH = (questCount * 22) + (math.max(0, questCount - 1) * 8)
		end
		holderH = math.clamp(holderH, 54, 140)

		tasksHolder.Size = UDim2.new(1, 0, 0, holderH)
		allDoneLbl.Size = UDim2.new(1, 0, 0, holderH)

		local rewardY = 40 + holderH + 8
		rewardRow.Position = UDim2.fromOffset(0, rewardY)
		claimBtn.Position = UDim2.fromOffset(0, rewardY + 30)
		resetBtn.Position = UDim2.fromOffset(0, rewardY + 72)
		xpBtn.Position = UDim2.fromOffset(0, rewardY + 102)

		tasksPanelHeight = (rewardY + 102 + 22) + 14
		tasksPanel.Size = UDim2.fromOffset(COLUMN_W, tasksPanelHeight)
		updateResponsiveScale()
	end
	reflowDailyTasksLayout(2)

	-- ── Bottom-right: Loadout ──────────────────────────────────────────
	-- Matches the Claude Design card: crown header + compact list-row
	-- buttons with [icon] [label] [> chevron]. Buttons sit against the
	-- card's own translucent fill — no rounded corners, thin holo-dim
	-- stroke — so they read as rows rather than CTA pills.
	-- Stacked directly under TasksPanel in the right column:
	-- y = 14 (top) + 292 (TasksPanel) + 14 (gap) = 320. Pinned to the
	-- right edge with AnchorPoint (1, 0) so it mirrors the left column.
	sidePanel = makePanel("SidePanel", root)
	sidePanel.AnchorPoint = Vector2.new(1, 0)
	sidePanel.Position = UDim2.new(1, EDGE_BLEED_X, 0, SIDE_Y)
	sidePanel.Size = UDim2.fromOffset(COLUMN_W, SIDE_H)
	padding(sidePanel, 14)
	cornerLs(sidePanel, 10, HOLO_PANEL_LBRACKET, 1.5)
	table.insert(motesOccludeList, sidePanel)

	local sideHeader = Instance.new("Frame")
	sideHeader.Name = "HeaderRow"
	sideHeader.BackgroundTransparency = 1
	sideHeader.Size = UDim2.new(1, 0, 0, 18)
	sideHeader.Parent = sidePanel

	local crown = imageIcon(sideHeader, 16, "rbxassetid://73744559499866")
	crown.AnchorPoint = Vector2.new(0, 0.5)
	crown.Position = UDim2.fromScale(0, 0.5)

	local sideTitle = makeLabel(sideHeader, "LOADOUT", FONT_TITLE, 15, COLOR_TEXT)
	sideTitle.Position = UDim2.fromOffset(22, 0)
	sideTitle.Size = UDim2.new(1, -22, 1, 0)

	local sideDivider = Instance.new("Frame")
	sideDivider.BackgroundColor3 = HOLO_PANEL_BORDER
	sideDivider.BackgroundTransparency = 0.3
	sideDivider.BorderSizePixel = 0
	sideDivider.Size = UDim2.new(1, 0, 0, 1)
	sideDivider.Position = UDim2.fromOffset(0, 28)
	sideDivider.Parent = sidePanel

	local btnHolder = Instance.new("Frame")
	btnHolder.Name = "Buttons"
	btnHolder.BackgroundTransparency = 1
	btnHolder.Position = UDim2.fromOffset(0, 40)
	btnHolder.Size = UDim2.new(1, 0, 1, -40)
	btnHolder.Parent = sidePanel

	local btnList = Instance.new("UIListLayout")
	btnList.FillDirection = Enum.FillDirection.Vertical
	btnList.SortOrder = Enum.SortOrder.LayoutOrder
	btnList.Padding = UDim.new(0, 10)
	btnList.Parent = btnHolder

	local function makeLoadoutButton(label, iconId, order)
		local b = Instance.new("TextButton")
		b.Name = label .. "Button"
		b.BackgroundColor3 = Color3.fromRGB(10, 24, 44)
		b.BackgroundTransparency = 0.5
		b.BorderSizePixel = 0
		b.Size = UDim2.new(1, 0, 0, 40)
		b.Font = FONT_TITLE
		b.TextSize = 14
		b.TextColor3 = COLOR_TEXT
		b.Text = ""           -- label drawn as a child for precise positioning
		b.AutoButtonColor = true
		b.LayoutOrder = order
		b.Parent = btnHolder
		local s = Instance.new("UIStroke")
		s.Color     = HOLO_PANEL_BORDER
		s.Thickness = 1
		s.Parent    = b

		local glyph = imageIcon(b, 18, iconId)
		glyph.AnchorPoint = Vector2.new(0, 0.5)
		glyph.Position = UDim2.new(0, 12, 0.5, 0)

		local txt = makeLabel(b, label, FONT_TITLE, 14, COLOR_TEXT)
		txt.Position = UDim2.fromOffset(38, 0)
		txt.Size = UDim2.new(1, -68, 1, 0)
		txt.TextXAlignment = Enum.TextXAlignment.Left

		local chev = makeChevronRight(b, 12, COLOR_TEXT_DIM)
		chev.AnchorPoint = Vector2.new(1, 0.5)
		chev.Position = UDim2.new(1, -12, 0.5, 0)

		return b
	end

	makeLoadoutButton("ARSENAL",     "rbxassetid://96460681124178",  1)
	local mercButton = makeLoadoutButton("MERCENARIES", "rbxassetid://113825300328145", 2)
	mercButton.MouseButton1Click:Connect(function()
		if typeof(_G.OpenMercenariesMenu) == "function" then
			_G.OpenMercenariesMenu()
		end
	end)

	-- Re-apply now that side-column panels exist (first call happened before
	-- panel creation), so they immediately push toward screen edges.
	updateResponsiveScale()

	-- ── Bottom: XP bar ─────────────────────────────────────────────────
	-- Matches XPBar in MainMenu.jsx: holo-framed row pinned to the
	-- bottom-centre of the menu, 460 wide / 48 tall / 24 px above the
	-- screen edge. Contents left-to-right: spark + "XP" label, live
	-- amount, segmented holo bar, Lv badge with gold-accent number.
	local xpPanel = makePanel("XPPanel", root)
	xpPanel.AnchorPoint = Vector2.new(0.5, 1)
	xpPanel.Position = UDim2.new(0.5, 0, 1, -24)
	xpPanel.Size = UDim2.fromOffset(470, 54)
	xpPanel.BackgroundTransparency = 0.16
	local xpPad = Instance.new("UIPadding")
	xpPad.PaddingTop    = UDim.new(0, 10)
	xpPad.PaddingBottom = UDim.new(0, 10)
	xpPad.PaddingLeft   = UDim.new(0, 16)
	xpPad.PaddingRight  = UDim.new(0, 16)
	xpPad.Parent = xpPanel
	cornerLs(xpPanel, 10, HOLO_PANEL_LBRACKET, 1.5)
	table.insert(motesOccludeList, xpPanel)

	-- No spark icon — "XP" sits at the left edge of the bar on its own.
	local xpTag = makeLabel(xpPanel, "XP", FONT_TITLE, 17, HOLO_EDGE)
	xpTag.Position = UDim2.fromOffset(2, 0)
	xpTag.Size = UDim2.new(0, 30, 1, 0)

	local xpAmount = makeLabel(xpPanel, "0 / 50", FONT_BODY, 14, COLOR_TEXT_DIM)
	xpAmount.Position = UDim2.fromOffset(44, 0)
	xpAmount.Size = UDim2.new(0, 62, 1, 0)
	xpAmountLabel = xpAmount

	-- Holo bar fills the middle. Reserve 52 px on the right for the Lv
	-- badge (40 + 12 gap), 102 on the left for the tag + amount cluster.
	local xpTrack, xpFill = makeHoloBar(xpPanel, UDim2.new(1, -154, 0, 12), XP_BAR_SEGMENTS)
	xpTrack.AnchorPoint = Vector2.new(0, 0.5)
	xpTrack.Position = UDim2.new(0, 104, 0.5, 0)
	xpFillFrame = xpFill

	-- Lv badge on the right. RichText so we can dim the "Lv" prefix
	-- and gold-accent the number in a single label.
	local xpLv = makeLabel(xpPanel,
		'Lv <font color="rgb(230,190,100)">0</font>',
		FONT_TITLE, 15, COLOR_TEXT)
	xpLv.RichText = true
	xpLv.AnchorPoint = Vector2.new(1, 0.5)
	xpLv.Position = UDim2.new(1, 0, 0.5, 0)
	xpLv.Size = UDim2.fromOffset(52, 18)
	xpLv.TextXAlignment = Enum.TextXAlignment.Right
	xpLevelLabel = xpLv

	-- ── Holo-open cover ────────────────────────────────────────────────
	-- Opaque fullscreen Frame stacked over `root` (created AFTER root so
	-- it sits on top of it in sibling draw order) that completely hides
	-- the menu content during the holo-open animation. At the reveal
	-- moment Phase 5 tweens its BackgroundTransparency from 0 → 1, so
	-- the menu "materializes" as the cover dissolves.
	local cover = Instance.new("Frame")
	cover.Name = "HoloCover"
	cover.BackgroundColor3 = COLOR_BG
	cover.BackgroundTransparency = 0
	cover.BorderSizePixel = 0
	cover.Size = UDim2.fromScale(1, 1)
	cover.Visible = false
	cover.Parent = screenGui
	holoCover = cover

	-- ── Holo-open LOAD… overlay ────────────────────────────────────────
	-- Sibling of `root` / `holoCover` (NOT a child), created LAST so it
	-- renders on top of the cover. The overlay is visible *while* the
	-- menu is hidden, and hides itself once the menu is revealed.
	local overlay = Instance.new("Frame")
	overlay.Name = "LoadingOverlay"
	overlay.BackgroundTransparency = 1
	overlay.AnchorPoint = Vector2.new(0.5, 0.5)
	overlay.Position = UDim2.fromScale(0.5, 0.5)
	overlay.Size = UDim2.fromOffset(300, 60)
	overlay.Visible = false
	overlay.Parent = screenGui

	local loadText = makeLabel(overlay, "LOAD...", FONT_TITLE, 22, COLOR_TEXT, Enum.TextXAlignment.Center)
	loadText.Name = "LoadText"
	loadText.AnchorPoint = Vector2.new(0.5, 0)
	loadText.Position = UDim2.new(0.5, 0, 0, 0)
	loadText.Size = UDim2.fromOffset(260, 28)

	local loadTrack = Instance.new("Frame")
	loadTrack.Name = "LoadTrack"
	loadTrack.BackgroundColor3 = COLOR_BAR_BG
	loadTrack.BorderSizePixel = 0
	loadTrack.AnchorPoint = Vector2.new(0.5, 0)
	loadTrack.Position = UDim2.new(0.5, 0, 0, 34)
	loadTrack.Size = UDim2.fromOffset(260, 8)
	loadTrack.Parent = overlay
	corner(loadTrack, 4)

	local loadBar = Instance.new("Frame")
	loadBar.Name = "LoadBar"
	loadBar.BackgroundColor3 = COLOR_XP_FILL
	loadBar.BorderSizePixel = 0
	loadBar.AnchorPoint = Vector2.new(0, 0.5)
	loadBar.Position = UDim2.new(0, 0, 0.5, 0)
	loadBar.Size = UDim2.fromScale(0, 1)
	loadBar.Parent = loadTrack
	corner(loadBar, 4)

	-- Cyan glow stroke so the bar has the "holo" feel, and also doubles
	-- as one of the channels we tint during the RGB-shift phase.
	local loadGlow = Instance.new("UIStroke")
	loadGlow.Color = COLOR_XP_FILL
	loadGlow.Thickness = 2
	loadGlow.Transparency = 0.3
	loadGlow.Parent = loadBar

	loadingOverlay = overlay
	loadingBar     = loadBar
	loadingText    = loadText
	loadingStroke  = loadGlow
end

-- ─── Holo-open animation (inline) ─────────────────────────────────────────
-- Solo-Leveling / sci-fi HUD style opener. Runs entirely on the loading
-- overlay: the menu panels stay hidden beneath an opaque `holoCover`
-- Frame until the loading sequence finishes, at which point the cover
-- dissolves and the panels subtly scale in as the "result" of the
-- animation completing. All tuning lives here so it's easy to tweak
-- feel without touching the flow.

local HOLO_GLITCH_DURATION   = 0.22
local HOLO_GLITCH_STEP       = 0.025
local HOLO_GLITCH_OFFSET_MAX = 7

local HOLO_RGB_STEPS         = 6
local HOLO_RGB_STEP          = 0.03

local HOLO_LOAD_DURATION     = 0.8

local HOLO_FLICKER_COUNT     = 3
local HOLO_FLICKER_STEP      = 0.045

local HOLO_APPEAR_DURATION   = 0.35
local HOLO_APPEAR_FROM_SCALE = 0.85

local HOLO_RED = Color3.fromRGB(255, 64, 96)
local HOLO_BLU = Color3.fromRGB(64, 160, 255)

local function holoJitter(range)
	return (math.random() * 2 - 1) * range
end

-- Returns true if `token` is still the latest open token. Used so an
-- in-flight animation can abort if the user closed+reopened the menu.
local function holoTokenAlive(token)
	return token == openAnimationToken and menuOpen
end

local function runHoloOpenAnimation(token)
	-- Reset loading state before showing it.
	loadingText.Text                  = "LOAD..."
	loadingText.TextColor3            = COLOR_TEXT
	loadingText.TextTransparency      = 0
	loadingBar.BackgroundTransparency = 0
	loadingBar.Size                   = UDim2.fromScale(0, 1)
	loadingStroke.Color               = COLOR_XP_FILL
	loadingStroke.Transparency        = 0.3
	loadingOverlay.Position           = UDim2.fromScale(0.5, 0.5)
	loadingOverlay.Visible            = true

	-- Keep the menu fully hidden behind the cover + slightly zoomed
	-- until the final reveal.
	holoCover.BackgroundTransparency = 0
	holoCover.Visible                = true
	menuRootScale.Scale              = HOLO_APPEAR_FROM_SCALE

	-- Kick the progress-bar fill in parallel with the glitch + RGB phases.
	local fillTween = TweenService:Create(
		loadingBar,
		TweenInfo.new(HOLO_LOAD_DURATION, Enum.EasingStyle.Linear),
		{ Size = UDim2.fromScale(1, 1) }
	)
	fillTween:Play()

	-- Phase 1: glitch jitter — random position + transparency flicker.
	local origPos = loadingOverlay.Position
	local elapsed = 0
	while elapsed < HOLO_GLITCH_DURATION do
		if not holoTokenAlive(token) then fillTween:Cancel() return end
		loadingOverlay.Position = origPos + UDim2.fromOffset(
			math.floor(holoJitter(HOLO_GLITCH_OFFSET_MAX)),
			math.floor(holoJitter(HOLO_GLITCH_OFFSET_MAX))
		)
		loadingText.TextTransparency      = 0.2 + math.random() * 0.55
		loadingBar.BackgroundTransparency = 0.2 + math.random() * 0.55
		task.wait(HOLO_GLITCH_STEP)
		elapsed += HOLO_GLITCH_STEP
	end
	loadingOverlay.Position           = origPos
	loadingText.TextTransparency      = 0
	loadingBar.BackgroundTransparency = 0

	-- Phase 2: RGB channel shift on text + bar stroke.
	for i = 1, HOLO_RGB_STEPS do
		if not holoTokenAlive(token) then fillTween:Cancel() return end
		local odd = (i % 2) == 1
		loadingText.TextColor3 = odd and HOLO_RED or HOLO_BLU
		loadingStroke.Color    = odd and HOLO_BLU or HOLO_RED
		task.wait(HOLO_RGB_STEP + math.random() * 0.015)
	end
	loadingText.TextColor3 = COLOR_TEXT
	loadingStroke.Color    = COLOR_XP_FILL

	-- Phase 3: wait for the loading bar to reach 100%.
	if fillTween.PlaybackState ~= Enum.PlaybackState.Completed then
		fillTween.Completed:Wait()
	end
	if not holoTokenAlive(token) then return end

	-- Phase 4: "SYSTEM READY" swap + short final flicker.
	loadingText.Text = "SYSTEM READY"
	for _ = 1, HOLO_FLICKER_COUNT do
		if not holoTokenAlive(token) then return end
		loadingText.TextTransparency = 0.55
		task.wait(HOLO_FLICKER_STEP)
		loadingText.TextTransparency = 0
		task.wait(HOLO_FLICKER_STEP)
	end

	-- Gate: don't reveal until the viewport rig build started by
	-- setMenuOpen has finished. On the first open this can take a
	-- second or more (GetHumanoidDescriptionFromUserId is a web call),
	-- so we poll every frame here. If the user closes the menu mid-
	-- wait the token changes and we bail out.
	while not viewportInitialized do
		if not holoTokenAlive(token) then return end
		task.wait()
	end

	-- Phase 5: reveal the menu — dissolve the opaque cover and scale
	-- the panels up underneath, while the loading overlay fades out in
	-- parallel. The menu materializing is the "result" of the loading
	-- animation completing, per the spec.
	local appearInfo = TweenInfo.new(
		HOLO_APPEAR_DURATION,
		Enum.EasingStyle.Quint,
		Enum.EasingDirection.Out
	)
	TweenService:Create(menuRootScale, appearInfo, { Scale = 1 }):Play()
	TweenService:Create(holoCover, appearInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(loadingText, appearInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(loadingBar,  appearInfo, { BackgroundTransparency = 1 }):Play()
	local fadeStroke = TweenService:Create(loadingStroke, appearInfo, { Transparency = 1 })
	fadeStroke:Play()
	fadeStroke.Completed:Wait()

	if holoTokenAlive(token) then
		loadingOverlay.Visible     = false
		holoCover.Visible          = false
		loadingStroke.Transparency = 0.3
	end
end

-- ─── Slide open / close animations ────────────────────────────────────────
-- Lightweight slide used for every menu open after the first of the
-- session, and the universal close animation. The whole `root` frame
-- slides up from below the screen on open, and back down on close.

local SLIDE_OPEN_DURATION  = 0.28
local SLIDE_CLOSE_DURATION = 0.25

-- Module-level reference to whichever slide tween is currently running
-- on `menuRoot.Position`, so a rapid close+reopen (or open+close) can
-- cancel the previous tween before starting a new one on the same
-- property — otherwise both would drive Position in parallel.
local activeSlideTween = nil

-- Returns the "fully off-screen below" position for `menuRoot` —
-- one full screen-height below its base position.
local function slideOffscreenPosition()
	local basePos = menuRootBasePosition
	return UDim2.new(
		basePos.X.Scale, basePos.X.Offset,
		basePos.Y.Scale + 1, basePos.Y.Offset
	)
end

local function runSlideOpenAnimation(token)
	if not (menuRoot and menuRootBasePosition) then return end

	-- Cancel any in-flight close tween before we overwrite Position.
	if activeSlideTween then activeSlideTween:Cancel() end

	-- Start one full screen-height below the base position so the
	-- entire menu sits off-screen, then tween up.
	menuRoot.Position = slideOffscreenPosition()

	local tween = TweenService:Create(
		menuRoot,
		TweenInfo.new(
			SLIDE_OPEN_DURATION,
			Enum.EasingStyle.Quint,
			Enum.EasingDirection.Out
		),
		{ Position = menuRootBasePosition }
	)
	activeSlideTween = tween
	tween:Play()
	tween.Completed:Wait()
	if activeSlideTween == tween then activeSlideTween = nil end

	-- If the user closed mid-slide, snap back to base so the next open
	-- isn't starting from a random in-between position.
	if not holoTokenAlive(token) then
		menuRoot.Position = menuRootBasePosition
	end
end

-- Slide-down close: tween `root` from its current position to one
-- full screen-height below, then disable the ScreenGui. Runs for
-- every close regardless of which open animation played, so the menu
-- always exits by sliding off the bottom of the screen.
local function runSlideCloseAnimation(token)
	if not (screenGui and menuRoot and menuRootBasePosition) then
		if screenGui then screenGui.Enabled = false end
		return
	end

	-- Cancel any in-flight open tween so we don't fight it.
	if activeSlideTween then activeSlideTween:Cancel() end

	local tween = TweenService:Create(
		menuRoot,
		TweenInfo.new(
			SLIDE_CLOSE_DURATION,
			Enum.EasingStyle.Quint,
			Enum.EasingDirection.In
		),
		{ Position = slideOffscreenPosition() }
	)
	activeSlideTween = tween
	tween:Play()
	tween.Completed:Wait()
	if activeSlideTween == tween then activeSlideTween = nil end

	-- Only disable the GUI and reset position if no new open has
	-- started in the meantime — otherwise the newer open coroutine is
	-- already setting its own starting position and we'd stomp it.
	if token == openAnimationToken then
		screenGui.Enabled = false
		menuRoot.Position = menuRootBasePosition
	end
end

-- ─── Show / hide ──────────────────────────────────────────────────────────
local function setMenuOpen(open)
	if not screenGui then buildMenu() end
	menuOpen = open

	if open then
		screenGui.Enabled = true
		if typeof(_G.CloseInventory) == "function" then
			_G.CloseInventory()
		end

		openAnimationToken += 1
		local token = openAnimationToken

		-- Kick off the viewport rig build in parallel on the first
		-- open of the current life (the rig build yields on
		-- GetHumanoidDescriptionFromUserId — a web call that can
		-- take a second or more — so we never want it blocking the
		-- open flow). Runs for both animation paths: on session
		-- start the holo-open animation waits for it before the
		-- reveal; after a respawn the slide path just lets the
		-- rig pop in whenever it's ready.
		if not viewportInitialized then
			task.spawn(function()
				refreshCharacterViewport()
				viewportInitialized = true
			end)
		end

		if not holoOpenPlayed then
			-- First open this session: run the full holo-open
			-- animation. Hide the menu behind the opaque cover
			-- IMMEDIATELY, before any potentially-yielding work,
			-- so the menu never flashes visible during the
			-- viewport rig build.
			if holoCover then
				holoCover.BackgroundTransparency = 0
				holoCover.Visible                = true
			end
			if menuRootScale then
				menuRootScale.Scale = HOLO_APPEAR_FROM_SCALE
			end
			if menuRoot and menuRootBasePosition then
				menuRoot.Position = menuRootBasePosition
			end

			task.spawn(function()
				runHoloOpenAnimation(token)
				if token == openAnimationToken then
					holoOpenPlayed = true
				end
			end)
		else
			-- Subsequent opens: quick slide-up from the bottom of
			-- the screen, no cover / no glitch / no loading bar.
			-- The viewport rig is already cached from the first
			-- open so there's nothing to wait on.
			if holoCover then
				holoCover.Visible = false
			end
			if loadingOverlay then
				loadingOverlay.Visible = false
			end
			if menuRootScale then
				menuRootScale.Scale = 1
			end
			task.spawn(function()
				runSlideOpenAnimation(token)
			end)
		end
	else
		-- Close: invalidate any in-flight open animation so it bails
		-- out, clear cover / overlay / scale left over from the holo
		-- path, and play the slide-down close animation. The
		-- ScreenGui stays enabled until the slide finishes so the
		-- user actually sees it.
		holoOpenPlayed = true
		openAnimationToken += 1
		local token = openAnimationToken
		if loadingOverlay then loadingOverlay.Visible = false end
		if holoCover      then holoCover.Visible      = false end
		if menuRootScale  then menuRootScale.Scale    = 1       end
		task.spawn(function()
			runSlideCloseAnimation(token)
		end)
	end
end

-- ─── Tool equip tracking (Phone) ──────────────────────────────────────────
-- While the Phone is equipped we block InventoryUI's own E handler via the
-- `_G.SuppressInventoryToggle` hook it already exposes — otherwise pressing E
-- would open both the phone menu AND the inventory at the same time. We also
-- force-close the inventory on equip in case it's already open.
local function setPhoneEquipped(eq)
	phoneEquipped = eq
	_G.SuppressInventoryToggle = eq or nil
	if eq and typeof(_G.CloseInventory) == "function" then
		_G.CloseInventory()
	end
end

local function onToolEquipped(tool)
	if tool.Name == "Phone" then
		setPhoneEquipped(true)
	end
end

local function onToolUnequipped(tool)
	if tool.Name == "Phone" then
		setPhoneEquipped(false)
		if menuOpen then setMenuOpen(false) end
	end
end

local function setupCharacter(char)
	if not char then return end
	setPhoneEquipped(false)
	if menuOpen then setMenuOpen(false) end

	-- Invalidate the cached viewport rig so the next menu open rebuilds
	-- against the freshly-spawned character. Everything else about the
	-- viewport (ViewportFrame, WorldModel, Camera) is reused.
	viewportInitialized = false

	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then onToolEquipped(child) end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then onToolUnequipped(child) end
	end)
	for _, child in char:GetChildren() do
		if child:IsA("Tool") and child.Name == "Phone" then
			onToolEquipped(child)
			break
		end
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

-- Build the GUI once up-front so the first open has no hitch.
buildMenu()

-- Expose root frame and ScreenGui so the Mercenaries page can parent
-- itself inside the phone menu.
_G.PhoneMenuRoot = menuRoot
_G.PhoneScreenGui = screenGui
_G.ClosePhoneMenu = function()
	if not menuOpen then return end
	menuOpen = false
	openAnimationToken += 1
	if activeSlideTween then activeSlideTween:Cancel(); activeSlideTween = nil end
	if loadingOverlay then loadingOverlay.Visible = false end
	if holoCover      then holoCover.Visible      = false end
	if menuRootScale  then menuRootScale.Scale    = 1     end
	if menuRoot and menuRootBasePosition then menuRoot.Position = menuRootBasePosition end
	if screenGui then screenGui.Enabled = false end
	-- Mark holo animation as done so subsequent opens use the slide animation
	holoOpenPlayed = true
end

-- ─── Characteristics binding ─────────────────────────────────────────────
-- Pushes the replicated per-player `Characteristics` IntValues (created by
-- Characteristics.server.lua) into the phone-menu labels and bars, and wires
-- the Strength "+" button up to the shared PhoneMenuAction RemoteEvent.
local phoneMenuEvent = ReplicatedStorage:WaitForChild("PhoneMenuAction")

-- Dev-phase: treat 10 levels in any attribute as a full bar.
local STAT_BAR_MAX = 10
local STAT_BAR_SEGMENTS = 10
local XP_BAR_SEGMENTS = 10

-- Align filled width to exact segment steps (1/10, 2/10, ...). This avoids
-- the visual "slightly more than one level" effect caused by fractional
-- interpolation/anti-aliasing on segmented tracks.
local function getSteppedBarRatio(value, maxValue, segments)
	if maxValue <= 0 then return 0 end
	local raw = math.clamp(value / maxValue, 0, 1)
	if not segments or segments <= 0 then
		return raw
	end
	local stepped = math.floor(raw * segments + 1e-6) / segments
	-- Tiny inset keeps the fill from touching the next segment divider
	-- prematurely; full bars still end exactly at 100%.
	if stepped > 0 and stepped < 1 then
		stepped = math.max(0, stepped - 0.002)
	end
	return stepped
end

local function refreshCharacteristics()
	local folder = player:FindFirstChild("Characteristics")
	if not folder then return end

	local level         = folder:FindFirstChild("Level")
	local xp            = folder:FindFirstChild("XP")
	local xpRequired    = folder:FindFirstChild("XPRequired")
	local upgradePoints = folder:FindFirstChild("UpgradePoints")

	if levelBadgeLabel and level then
		levelBadgeLabel.Text = tostring(level.Value)
	end

	if upgradePointsLabel and upgradePoints then
		-- Row split into a static "Upgrade points:" label + this live
		-- count; just drive the count.
		upgradePointsLabel.Text = tostring(upgradePoints.Value)
	end

	local hasPoints = upgradePoints and upgradePoints.Value > 0
	for key, rec in statRows do
		local stat = folder:FindFirstChild(key)
		if stat then
			if rec.lvl then
				rec.lvl.Text = "LV " .. stat.Value
			end
			if rec.fill then
				local ratio = getSteppedBarRatio(stat.Value, STAT_BAR_MAX, STAT_BAR_SEGMENTS)
				rec.fill.Size = UDim2.new(ratio, 0, 1, 0)
			end
		end
		if rec.button then
			-- Holo button: gold stroke + gold plus glyph when upgrade
			-- is available, dim otherwise. No text on the button any
			-- more — the plus is drawn as a Frame icon.
			rec.button.AutoButtonColor = hasPoints or false
			rec.button.BackgroundColor3 = hasPoints and PLUS_BTN_BG_ACTIVE or PLUS_BTN_BG_INACTIVE
			rec.button.BackgroundTransparency = hasPoints and 0 or 0.08
			if rec.stroke then
				rec.stroke.Color = hasPoints and COLOR_GOLD or HOLO_PANEL_BORDER
			end
			if rec.plusIcon then
				for _, child in rec.plusIcon:GetChildren() do
					if child:IsA("Frame") then
						child.BackgroundColor3 = hasPoints and COLOR_GOLD or COLOR_TEXT_DIM
						child.BackgroundTransparency = hasPoints and 0 or 0.4
					end
				end
			end
		end
	end

	if xpAmountLabel and xp and xpRequired then
		xpAmountLabel.Text = xp.Value .. " / " .. xpRequired.Value
	end
	if xpFillFrame and xp and xpRequired then
		local ratio = getSteppedBarRatio(
			xp.Value,
			xpRequired.Value,
			math.max(1, xpRequired.Value)
		)
		xpFillFrame.Size = UDim2.new(ratio, 0, 1, 0)
	end
	if xpLevelLabel and level then
		-- Dim "Lv" prefix + gold level number to match MainMenu.jsx.
		xpLevelLabel.Text = string.format(
			'Lv <font color="rgb(230,190,100)">%d</font>',
			level.Value)
	end
end

task.spawn(function()
	local folder = player:WaitForChild("Characteristics")
	for _, v in folder:GetChildren() do
		if v:IsA("IntValue") then
			v:GetPropertyChangedSignal("Value"):Connect(refreshCharacteristics)
		end
	end
	folder.ChildAdded:Connect(function(v)
		if v:IsA("IntValue") then
			v:GetPropertyChangedSignal("Value"):Connect(refreshCharacteristics)
			refreshCharacteristics()
		end
	end)
	refreshCharacteristics()
end)

for _, rec in statRows do
	if rec.button then
		local action = rec.action
		rec.button.MouseButton1Click:Connect(function()
			phoneMenuEvent:FireServer(action)
		end)
	end
end

-- ─── Daily quests binding ────────────────────────────────────────────────
-- Mirror the replicated `DailyQuests` folder (produced by
-- DailyQuests.server.lua) into the phone-menu tasks panel: one row per
-- quest with a live progress label and a checkbox that lights up when
-- the quest is complete, plus the reward line and the claim button.

local function clearDailyQuestRows()
	for _, conn in dailyQuestConnections do
		conn:Disconnect()
	end
	table.clear(dailyQuestConnections)
	if dailyQuestsHolder then
		for _, child in dailyQuestsHolder:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		dailyQuestsHolder.Visible = true
	end
	if dailyAllCompleteLabel then
		dailyAllCompleteLabel.Visible = false
	end
	table.clear(dailyQuestRows)
end

local function formatQuestLabel(questFolder)
	local label    = questFolder:FindFirstChild("Label")
	local progress = questFolder:FindFirstChild("Progress")
	local target   = questFolder:FindFirstChild("Target")
	local base     = (label and label.Value) or questFolder.Name
	if progress and target and target.Value > 0 then
		return string.format("%s (%d/%d)", base, progress.Value, target.Value)
	end
	return base
end

local function repaintQuestRow(id)
	local rec = dailyQuestRows[id]
	if not rec then return end
	local quest = rec.folder
	if not quest or not quest.Parent then return end

	local progress  = quest:FindFirstChild("Progress")
	local target    = quest:FindFirstChild("Target")
	local completed = quest:FindFirstChild("Completed")
	local done      = completed and completed.Value

	local labelText = formatQuestLabel(quest)
	if done then
		-- Strike through the whole line so the player can see at a
		-- glance which quests they've already finished.
		rec.label.Text = "<s>" .. labelText .. "</s>"
		rec.label.TextColor3 = COLOR_TEXT_DIM
	else
		rec.label.Text = labelText
		rec.label.TextColor3 = COLOR_TEXT
	end

	-- Holo checkbox: hairline border when empty, edge-bright when done,
	-- with a hand-drawn ✓ glyph inside. The box is a plain Frame now
	-- (no solid fill), so toggling the stroke colour is enough to
	-- communicate the state — the glyph adds the check.
	local boxStroke = rec.box:FindFirstChildOfClass("UIStroke")
	if done then
		if boxStroke then boxStroke.Color = HOLO_EDGE end
		if not rec.check then
			local check = makeCheckIcon(rec.box, 16, HOLO_EDGE)
			check.AnchorPoint = Vector2.new(0.5, 0.5)
			check.Position = UDim2.fromScale(0.5, 0.5)
			rec.check = check
		end
	else
		if boxStroke then boxStroke.Color = HOLO_PANEL_BORDER end
		if rec.check then
			rec.check:Destroy()
			rec.check = nil
		end
	end
end

local function updateDailyRewardAndButton(folder)
	local claimedVal = folder:FindFirstChild("Claimed")
	local rewardXP   = folder:FindFirstChild("RewardXP")
	local rewardIron = folder:FindFirstChild("RewardIronIngots")

	if dailyRewardLabel then
		local xp   = rewardXP and rewardXP.Value or 0
		local iron = rewardIron and rewardIron.Value or 0
		if iron > 0 then
			dailyRewardLabel.Text = string.format("+%d XP   +%d Iron", xp, iron)
		else
			dailyRewardLabel.Text = string.format("+%d XP", xp)
		end
	end

	if not dailyClaimButton then return end

	-- The button lights up only when every quest is complete and the
	-- reward hasn't been claimed yet.
	local allDone = true
	local questCount = 0
	for _, child in folder:GetChildren() do
		if child:IsA("Folder") and child.Name:sub(1, 6) == "Quest_" then
			questCount = questCount + 1
			local c = child:FindFirstChild("Completed")
			if not (c and c.Value) then
				allDone = false
			end
		end
	end
	if questCount == 0 then allDone = false end

	-- Once every quest is done, swap the row list out for a single
	-- celebratory label. Rebuilding for a new day re-shows the holder.
	if dailyQuestsHolder and dailyAllCompleteLabel then
		if allDone then
			dailyQuestsHolder.Visible = false
			dailyAllCompleteLabel.Visible = true
		else
			dailyQuestsHolder.Visible = true
			dailyAllCompleteLabel.Visible = false
		end
	end

	local claimed = claimedVal and claimedVal.Value or false

	-- Holo claim button: bright holo-edge text + matching stroke when
	-- ready, dim when claimed or not yet eligible. UIStroke is the
	-- first UIStroke child we attached during buildMenu().
	local claimStroke = dailyClaimButton:FindFirstChildOfClass("UIStroke")
	if claimed then
		dailyClaimButton.Text        = "REWARD CLAIMED"
		dailyClaimButton.TextColor3  = COLOR_TEXT_DIM
		dailyClaimButton.Active      = false
		dailyClaimButton.AutoButtonColor = false
		if claimStroke then claimStroke.Color = HOLO_PANEL_BORDER end
	elseif allDone then
		dailyClaimButton.Text        = "CLAIM REWARD"
		dailyClaimButton.TextColor3  = HOLO_EDGE
		dailyClaimButton.Active      = true
		dailyClaimButton.AutoButtonColor = true
		if claimStroke then claimStroke.Color = HOLO_EDGE end
	else
		dailyClaimButton.Text        = "CLAIM REWARD"
		dailyClaimButton.TextColor3  = COLOR_TEXT_DIM
		dailyClaimButton.Active      = false
		dailyClaimButton.AutoButtonColor = false
		if claimStroke then claimStroke.Color = HOLO_PANEL_BORDER end
	end
end

local function rebuildDailyQuests(folder)
	clearDailyQuestRows()
	if not dailyQuestsHolder or not folder then return end

	-- Gather the quest folders, sort by their `Order` IntValue so the
	-- phone menu always displays them in the same sequence.
	local questFolders = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Folder") and child.Name:sub(1, 6) == "Quest_" then
			table.insert(questFolders, child)
		end
	end
	table.sort(questFolders, function(a, b)
		local ao = a:FindFirstChild("Order")
		local bo = b:FindFirstChild("Order")
		return (ao and ao.Value or 0) < (bo and bo.Value or 0)
	end)

	for i, quest in questFolders do
		local idVal = quest:FindFirstChild("Id")
		local id    = (idVal and idVal.Value) or quest.Name

		local row = Instance.new("Frame")
		row.Name = "Row_" .. id
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 22)
		row.LayoutOrder = i
		row.Parent = dailyQuestsHolder

		local box = Instance.new("Frame")
		box.Name = "Checkbox"
		box.BackgroundTransparency = 1
		box.BorderSizePixel = 0
		box.Size = UDim2.fromOffset(18, 18)
		box.AnchorPoint = Vector2.new(0, 0.5)
		box.Position = UDim2.new(0, 0, 0.5, 0)
		box.Parent = row
		local boxStroke = Instance.new("UIStroke")
		boxStroke.Color     = HOLO_PANEL_BORDER
		boxStroke.Thickness = 1
		boxStroke.Parent    = box

		local label = makeLabel(row, quest.Name, FONT_BODY, 13, COLOR_TEXT)
		label.Position = UDim2.fromOffset(28, 0)
		label.Size = UDim2.new(1, -28, 1, 0)
		-- RichText lets repaintQuestRow wrap the text in <s>…</s> to
		-- strike through completed quests.
		label.RichText = true

		dailyQuestRows[id] = { folder = quest, row = row, box = box, label = label, check = nil }

		-- Watch Progress and Completed for changes so the row repaints
		-- immediately as the player earns resources.
		local progress  = quest:FindFirstChild("Progress")
		local completed = quest:FindFirstChild("Completed")
		if progress then
			table.insert(dailyQuestConnections,
				progress:GetPropertyChangedSignal("Value"):Connect(function()
					repaintQuestRow(id)
					updateDailyRewardAndButton(folder)
				end))
		end
		if completed then
			table.insert(dailyQuestConnections,
				completed:GetPropertyChangedSignal("Value"):Connect(function()
					repaintQuestRow(id)
					updateDailyRewardAndButton(folder)
				end))
		end

		repaintQuestRow(id)
	end

	if reflowDailyTasksLayout then
		reflowDailyTasksLayout(#questFolders)
	end

	updateDailyRewardAndButton(folder)
end

task.spawn(function()
	-- The folder may arrive before or after the menu GUI is built, so
	-- wait for it and then rebuild on every change. We also rebuild on
	-- Date change (new day → reroll) by watching the folder's
	-- ChildRemoved/ChildAdded — simpler is to watch the Player for a
	-- new DailyQuests folder entirely.
	local function bind(folder)
		rebuildDailyQuests(folder)

		-- Reward / claimed state updates also repaint the button.
		local claimed  = folder:FindFirstChild("Claimed")
		local rewardXP = folder:FindFirstChild("RewardXP")
		local rewardIr = folder:FindFirstChild("RewardIronIngots")
		if claimed then
			table.insert(dailyQuestConnections,
				claimed:GetPropertyChangedSignal("Value"):Connect(function()
					updateDailyRewardAndButton(folder)
				end))
		end
		if rewardXP then
			table.insert(dailyQuestConnections,
				rewardXP:GetPropertyChangedSignal("Value"):Connect(function()
					updateDailyRewardAndButton(folder)
				end))
		end
		if rewardIr then
			table.insert(dailyQuestConnections,
				rewardIr:GetPropertyChangedSignal("Value"):Connect(function()
					updateDailyRewardAndButton(folder)
				end))
		end
	end

	local folder = player:WaitForChild("DailyQuests")
	bind(folder)

	player.ChildAdded:Connect(function(child)
		if child.Name == "DailyQuests" and child:IsA("Folder") then
			bind(child)
		end
	end)
end)

if dailyClaimButton then
	dailyClaimButton.MouseButton1Click:Connect(function()
		if not dailyClaimButton.Active then return end
		phoneMenuEvent:FireServer("claimDailyReward")
	end)
end

if dailyResetButton then
	dailyResetButton.MouseButton1Click:Connect(function()
		phoneMenuEvent:FireServer("resetQuests")
	end)
end

if dailyXPButton then
	dailyXPButton.MouseButton1Click:Connect(function()
		phoneMenuEvent:FireServer("devAddXP")
	end)
end

-- ─── Daily quests reset countdown ────────────────────────────────────────
-- Daily quests reset at 00:00 UTC every day. Compute how much time is
-- left until that instant and repaint the label once a second. The loop
-- only runs while the menu is open so it doesn't fire every second for
-- the entire session.
local function secondsUntilNextUtcMidnight()
	local now = os.time()
	local t = os.date("!*t", now)
	return 86400 - (t.hour * 3600 + t.min * 60 + t.sec)
end

local function formatResetCountdown(secs)
	if secs < 0 then secs = 0 end
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	local s = secs % 60
	-- HH:MM:SS only — the clock glyph beside the label already tells
	-- the player what the number represents, matching the
	-- Daily Tasks header in MainMenu.jsx.
	return string.format("%02d:%02d:%02d", h, m, s)
end

task.spawn(function()
	while true do
		if dailyTimerLabel then
			dailyTimerLabel.Text = formatResetCountdown(secondsUntilNextUtcMidnight())
		end
		task.wait(1)
	end
end)

-- ─── Input ────────────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E and phoneEquipped then
		setMenuOpen(not menuOpen)
	end
end)
