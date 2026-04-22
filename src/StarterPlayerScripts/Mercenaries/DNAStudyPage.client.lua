-- DNAStudyPage.client.lua
-- "05 · DNA Study" sub-page. Reached from HandlingPage's STUDY DNA
-- button and currently a minimal scaffold — holo backdrop + responsive
-- 960×600 artboard + BACK button + centred placeholder title. The real
-- DNA-research UI (helix inspection, fragment decoding, etc.) grows
-- inside this file later; for now it just needs to exist so Handling →
-- Back round-trips cleanly.
--
-- Exposes _G.OpenDNAStudyPage(ctx) + _G.CloseDNAStudyPage() so
-- HandlingPage can route the STUDY DNA click here.
--
-- ctx fields (all optional unless marked):
--   screenGui     — ScreenGui to parent the page under (required).
--   mercName      — currently selected merc, shown in the title.
--   onBack()      — invoked when BACK is pressed. Typically closes
--                   this page and reopens HandlingPage with the
--                   original Handling ctx.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Server-owned remote (ServerScriptService/Mercenaries/DNAResearch.server.lua
-- creates it on script load). Use a 10-second wait so the DNA Study page can
-- surface a clear warning instead of silently failing if the server script
-- hasn't registered the remote yet.
local dnaResearchEvent = ReplicatedStorage:WaitForChild("DNAResearch", 10)

-- ─── Palette (matches HandlingPage/MercenariesMenu's amethyst-dark) ──
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

local player = Players.LocalPlayer

-- ─── BACK glyph (crossed diagonals — same shape as HandlingPage) ─────
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

-- Asset id for the DNA-sample (blood-capsule) icon used throughout
-- this page. User-supplied — swap here to rebrand every call site.
local SAMPLE_ICON_ID = "rbxassetid://115522744020445"

-- ─── Flask / capsule glyph (SAMPLES chip + sample-slot icons) ───────
-- Returns an ImageLabel wrapping the SAMPLE_ICON_ID asset. Keeps the
-- same (parent, size, color) signature as the older primitive-Frame
-- helpers so the surrounding layout code doesn't care which kind of
-- icon it receives. `color` maps to ImageColor3.
local function makeFlaskIcon(parent, size, color)
	local img = Instance.new("ImageLabel")
	img.Name = "CapsuleIcon"
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Size = UDim2.fromOffset(size, size)
	img.Image = SAMPLE_ICON_ID
	img.ImageColor3 = color or Color3.new(1, 1, 1)
	img.ScaleType = Enum.ScaleType.Fit
	img.Parent = parent
	return img
end

-- ─── Simple trait glyphs (all drawn from primitive Frames) ──────────
-- Minimal silhouettes, not image assets — each takes a square `size`
-- container and renders inside it.

local function makePersonIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "PersonIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local head = Instance.new("Frame")
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.Position = UDim2.fromScale(0.5, 0.3)
	head.Size = UDim2.fromOffset(size * 0.38, size * 0.38)
	head.BackgroundTransparency = 1
	head.BorderSizePixel = 0
	head.Parent = c
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(1, 0)
	hc.Parent = head
	local hs = Instance.new("UIStroke")
	hs.Color     = color
	hs.Thickness = 1.4
	hs.Parent    = head

	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.fromScale(0.5, 0.58)
	body.Size = UDim2.fromOffset(size * 0.62, size * 0.34)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Parent = c
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0.5, 0)
	bc.Parent = body
	local bs = Instance.new("UIStroke")
	bs.Color     = color
	bs.Thickness = 1.4
	bs.Parent    = body

	return c
end

-- 5-point star drawn with two crossed 4-point stars (rotated).
local function makeStarIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "StarIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local thick = math.max(1, math.floor(size * 0.18))
	for _, rot in ipairs({ 0, 45, 90 }) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(size * 0.85, thick)
		bar.BackgroundColor3 = color
		bar.BorderSizePixel = 0
		bar.Rotation = rot
		bar.Parent = c
	end

	return c
end

-- "Run" glyph — slanted arrow approximating a motion line.
local function makeRunIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "RunIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local thick = math.max(1, math.floor(size * 0.14))
	for i = 0, 2 do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.38 + i * 0.16, 0.5)
		bar.Size = UDim2.fromOffset(size * 0.54, thick)
		bar.BackgroundColor3 = color
		bar.BackgroundTransparency = i * 0.3
		bar.BorderSizePixel = 0
		bar.Rotation = -20
		bar.Parent = c
	end

	return c
end

-- Shield-like "behaviour" glyph (rounded square with a diagonal stripe).
local function makeShieldIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "ShieldIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromOffset(size * 0.75, size * 0.75)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Parent = c
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, math.max(1, math.floor(size * 0.18)))
	bc.Parent = body
	local bs = Instance.new("UIStroke")
	bs.Color     = color
	bs.Thickness = 1.4
	bs.Parent    = body

	local stripe = Instance.new("Frame")
	stripe.AnchorPoint = Vector2.new(0.5, 0.5)
	stripe.Position = UDim2.fromScale(0.5, 0.5)
	stripe.Size = UDim2.fromOffset(size * 0.55, math.max(1, math.floor(size * 0.1)))
	stripe.BackgroundColor3 = color
	stripe.BorderSizePixel = 0
	stripe.Rotation = -32
	stripe.Parent = c

	return c
end

-- "+" plus-sign glyph (ABILITY SEED).
local function makePlusIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "PlusIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local thick = math.max(1, math.floor(size * 0.18))
	local vert = Instance.new("Frame")
	vert.AnchorPoint = Vector2.new(0.5, 0.5)
	vert.Position = UDim2.fromScale(0.5, 0.5)
	vert.Size = UDim2.fromOffset(thick, size * 0.75)
	vert.BackgroundColor3 = color
	vert.BorderSizePixel = 0
	vert.Parent = c

	local horiz = Instance.new("Frame")
	horiz.AnchorPoint = Vector2.new(0.5, 0.5)
	horiz.Position = UDim2.fromScale(0.5, 0.5)
	horiz.Size = UDim2.fromOffset(size * 0.75, thick)
	horiz.BackgroundColor3 = color
	horiz.BorderSizePixel = 0
	horiz.Parent = c

	return c
end

-- Padlock glyph (rendered for locked trait tiles).
local function makeLockIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "LockIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	-- Shackle arc, approximated by a top-half outlined rectangle.
	local arc = Instance.new("Frame")
	arc.AnchorPoint = Vector2.new(0.5, 1)
	arc.Position = UDim2.fromScale(0.5, 0.48)
	arc.Size = UDim2.fromOffset(size * 0.5, size * 0.4)
	arc.BackgroundTransparency = 1
	arc.BorderSizePixel = 0
	arc.Parent = c
	local ac = Instance.new("UICorner")
	ac.CornerRadius = UDim.new(0.5, 0)
	ac.Parent = arc
	local as = Instance.new("UIStroke")
	as.Color     = color
	as.Thickness = 1.4
	as.Parent    = arc

	-- Body — solid rounded rectangle sitting below the arc.
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.fromScale(0.5, 0.48)
	body.Size = UDim2.fromOffset(size * 0.72, size * 0.42)
	body.BackgroundColor3 = color
	body.BorderSizePixel = 0
	body.Parent = c
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, math.max(1, math.floor(size * 0.14)))
	bc.Parent = body

	return c
end

-- Mini DNA helix glyph for the MUTATION trait — two rails with short
-- horizontal rungs. Not drawn as a true sine wave (too small), just
-- slight diagonals that read as "helix" at 16-20 px.
local function makeMiniHelixIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "MiniHelixIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local railThick = math.max(1, math.floor(size * 0.08))
	for _, spec in ipairs({ { 0.3, -12 }, { 0.7, 12 } }) do
		local rail = Instance.new("Frame")
		rail.AnchorPoint = Vector2.new(0.5, 0.5)
		rail.Position = UDim2.fromScale(spec[1], 0.5)
		rail.Size = UDim2.fromOffset(railThick, size * 0.92)
		rail.BackgroundColor3 = color
		rail.BorderSizePixel = 0
		rail.Rotation = spec[2]
		rail.Parent = c
	end

	for i = 1, 3 do
		local rung = Instance.new("Frame")
		rung.AnchorPoint = Vector2.new(0.5, 0.5)
		rung.Position = UDim2.fromScale(0.5, 0.25 + (i - 1) * 0.25)
		rung.Size = UDim2.fromOffset(size * 0.46, railThick)
		rung.BackgroundColor3 = color
		rung.BorderSizePixel = 0
		rung.BackgroundTransparency = 0.35
		rung.Parent = c
	end

	return c
end

-- ─── Small outlined diamond glyph (RESEARCH LOG header prefix) ──────
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

-- ─── Horizontal dotted leader (label ... value) ─────────────────────
-- A row of small square dots sitting on the baseline between the
-- label and value columns of a research-log row. Count is rounded so
-- the dots space evenly inside `width`. Individual dots are created
-- under `parent` at absolute offsets, so the caller owns the positioning.
local function dottedLeader(parent, x, y, width, color, dotSize, gap)
	dotSize = dotSize or 2
	gap     = gap     or 3
	color   = color   or HOLO_PANEL_BORDER

	local step = dotSize + gap
	local count = math.max(1, math.floor((width + gap) / step))
	local stride = width / count

	for i = 0, count - 1 do
		local dot = Instance.new("Frame")
		dot.BackgroundColor3 = color
		dot.BackgroundTransparency = 0.2
		dot.BorderSizePixel = 0
		dot.Position = UDim2.fromOffset(math.floor(x + i * stride + 0.5), y)
		dot.Size = UDim2.fromOffset(dotSize, dotSize)
		dot.ZIndex = (parent.ZIndex or 1) + 1
		dot.Parent = parent
	end
end

-- ─── Continuous sine-wave double-helix rails ────────────────────────
-- Draws two rails twisting around each other as two phase-shifted sine
-- waves, forming a proper DNA silhouette. The phase is offset by +π/2
-- so the rails START at their maximum left/right separation at y=topY
-- (and again at y=topY+H, since H is tuned to a full multiple of the
-- period). This gives the bracket-capped look from the reference image
-- instead of a helix that pinches at its endpoints.
--
-- x_L(y) = cx - A * sin(2π (y-topY) / period + π/2)
-- x_R(y) = cx + A * sin(2π (y-topY) / period + π/2)
-- (at y=topY both are ±A, sin(π/2)=1)
--
-- `thickness` is the on-screen line weight. Each rail is approximated
-- by `segments` short rotated Frames; 72+ keeps the curve smooth at
-- ~360 px helix heights.
local function drawHelixRails(parent, cx, topY, amplitude, H, period, color, thickness, segments)
	segments  = segments  or 72
	thickness = thickness or 3

	local function addSegment(ax, ay, bx, by)
		local dx = bx - ax
		local dy = by - ay
		local len = math.sqrt(dx * dx + dy * dy)
		if len <= 0 then return end
		local seg = Instance.new("Frame")
		seg.BackgroundColor3 = color
		seg.BorderSizePixel = 0
		seg.AnchorPoint = Vector2.new(0.5, 0.5)
		seg.Position = UDim2.fromOffset((ax + bx) * 0.5, (ay + by) * 0.5)
		-- +thickness so consecutive segments overlap and hide the seam.
		seg.Size = UDim2.fromOffset(len + thickness, thickness)
		seg.Rotation = math.deg(math.atan2(dy, dx))
		seg.ZIndex = (parent.ZIndex or 1) + 1
		seg.Parent = parent
	end

	local prevL, prevR
	for i = 0, segments do
		local y = topY + (i / segments) * H
		local phase = 2 * math.pi * (y - topY) / period + math.pi * 0.5
		local dx = amplitude * math.sin(phase)
		local xL = cx - dx
		local xR = cx + dx
		if prevL then
			addSegment(prevL.x, prevL.y, xL, y)
			addSegment(prevR.x, prevR.y, xR, y)
		end
		prevL = { x = xL, y = y }
		prevR = { x = xR, y = y }
	end
end

-- ─── Dashed rectangular border ──────────────────────────────────────
-- Roblox UIStroke can't render a dashed pattern, so we draw the four
-- edges as evenly-distributed short Frames. `parent` is the frame we
-- want the border INSIDE (position 0,0 → w,h). Dash counts are rounded
-- to keep spacing even on each edge, so the corners line up regardless
-- of the rectangle's aspect ratio.
local function dashedStrokeRect(parent, w, h, color, dashLen, gap, thickness)
	dashLen   = dashLen   or 6
	gap       = gap       or 4
	thickness = thickness or 1

	local step = dashLen + gap

	local function seg(x, y, sw, sh)
		local s = Instance.new("Frame")
		s.BackgroundColor3 = color
		s.BackgroundTransparency = 0
		s.BorderSizePixel = 0
		s.Position = UDim2.fromOffset(x, y)
		s.Size = UDim2.fromOffset(sw, sh)
		s.ZIndex = (parent.ZIndex or 1) + 1
		s.Parent = parent
	end

	local hCount = math.max(1, math.floor((w + gap) / step))
	local hStride = w / hCount
	for i = 0, hCount - 1 do
		local x = math.floor(i * hStride + 0.5)
		local segLen = math.min(dashLen, w - x)
		if segLen > 0 then
			seg(x, 0,              segLen, thickness)
			seg(x, h - thickness,  segLen, thickness)
		end
	end

	local vCount = math.max(1, math.floor((h + gap) / step))
	local vStride = h / vCount
	for i = 0, vCount - 1 do
		local y = math.floor(i * vStride + 0.5)
		local segLen = math.min(dashLen, h - y)
		if segLen > 0 then
			seg(0,             y, thickness, segLen)
			seg(w - thickness, y, thickness, segLen)
		end
	end
end

-- ─── Artboard reference (matches HandlingPage) ──────────────────────
local REFERENCE_W        = 960
local REFERENCE_H        = 600
local HORIZONTAL_PADDING = 80

-- ─── Module state ────────────────────────────────────────────────────
local activePage = nil
local activeConnections = {}

local function disconnectAll(tbl)
	for _, conn in ipairs(tbl) do conn:Disconnect() end
	table.clear(tbl)
end

-- ─── Holo backdrop (trimmed copy of HandlingPage's recipe) ──────────
-- Base gradient + horizon band + vignettes + drifting motes. No
-- occlusion list here — this page has no panels that need the motes
-- dimmed behind them yet, and adding one later is a two-line change.
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

	return root
end

-- ─── Close ───────────────────────────────────────────────────────────
local function closeDNAStudyPage()
	disconnectAll(activeConnections)
	if activePage then
		activePage:Destroy()
		activePage = nil
	end
end

-- ─── Open ────────────────────────────────────────────────────────────
local function openDNAStudyPage(ctx)
	ctx = ctx or {}
	local screenGui = ctx.screenGui
	if not screenGui then
		warn("[DNAStudyPage] open called without ctx.screenGui")
		return
	end

	closeDNAStudyPage()

	local page = Instance.new("Frame")
	page.Name = "DNAStudyPage"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ZIndex = 50
	page.Parent = screenGui
	activePage = page

	buildHoloBackground(page)

	-- Responsive 960×600 artboard (same math as HandlingPage).
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
	responsiveScale.Scale = 1
	responsiveScale.Parent = scaleWrap

	local backBtnRef, chipRef
	local BACK_BTN_Y = 39
	local CHIP_Y     = 39

	local function updateResponsiveScale()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then return end
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

	-- BACK button (pinned via dynamicBleed, same as HandlingPage)
	local backBtn = Instance.new("TextButton")
	backBtn.Name = "BackButton"
	backBtn.AnchorPoint = Vector2.new(0, 0)
	backBtn.Position = UDim2.fromOffset(0, BACK_BTN_Y)
	backBtn.Size = UDim2.fromOffset(92, 34)
	backBtn.BackgroundColor3 = HOLO_PANEL_FILL
	backBtn.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	backBtn.BorderSizePixel = 0
	backBtn.AutoButtonColor = true
	backBtn.Text = ""
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
		closeDNAStudyPage()
		if ctx.onBack then ctx.onBack() end
	end)

	-- ── Centred "DNA · STUDY · <MERCNAME>" cluster ──────────────────
	-- Fixed widths + absolute positioning (same recipe as HandlingPage's
	-- top cluster — AutomaticSize + UIListLayout renders blank on the
	-- first frame). "DNA" and "STUDY" are dim tags, the merc name is
	-- the bright headline.
	local mercDisplay = tostring(ctx.mercName or "—"):upper()
	local CLUSTER_Y    = BACK_BTN_Y + 6
	local TAG_DNA_W    = 40  -- "DNA" at 11 pt
	local DOT_W        = 14
	local TAG_STUDY_W  = 52  -- "STUDY" at 11 pt
	local NAME_W       = 160 -- big merc name
	local CLUSTER_W    = TAG_DNA_W + DOT_W + TAG_STUDY_W + DOT_W + NAME_W

	local topCluster = Instance.new("Frame")
	topCluster.Name = "TopCluster"
	topCluster.BackgroundTransparency = 1
	topCluster.BorderSizePixel = 0
	topCluster.AnchorPoint = Vector2.new(0.5, 0)
	topCluster.Position = UDim2.new(0.5, 0, 0, CLUSTER_Y)
	topCluster.Size = UDim2.fromOffset(CLUSTER_W, 24)
	topCluster.ZIndex = 52
	topCluster.Parent = scaleWrap

	local function tagLabel(name, text, xOffset, width, color, size)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.BorderSizePixel = 0
		l.Position = UDim2.fromOffset(xOffset, 0)
		l.Size = UDim2.fromOffset(width, 24)
		l.Font = FONT_TITLE
		l.TextSize = size
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.Text = text
		l.ZIndex = 53
		l.Parent = topCluster
		return l
	end

	tagLabel("DnaTag",   "DNA",       0,                                               TAG_DNA_W,   COLOR_TEXT_MUTE, 11)
	tagLabel("Dot1",     "·",         TAG_DNA_W,                                       DOT_W,       COLOR_TEXT_MUTE, 14)
	tagLabel("StudyTag", "STUDY",     TAG_DNA_W + DOT_W,                               TAG_STUDY_W, COLOR_TEXT_MUTE, 11)
	tagLabel("Dot2",     "·",         TAG_DNA_W + DOT_W + TAG_STUDY_W,                 DOT_W,       COLOR_TEXT_MUTE, 14)
	tagLabel("MercName", mercDisplay, TAG_DNA_W + DOT_W + TAG_STUDY_W + DOT_W,         NAME_W,      HOLO_EDGE,       18)

	-- ── SAMPLES · N chip, right-edge pinned via dynamicBleed ─────────
	-- Live-counts FullCapsule tools (in Backpack + Character) whose
	-- BloodType attribute matches this merc, so the count mirrors
	-- exactly what the SAMPLES slot would accept.
	local chip = Instance.new("Frame")
	chip.Name = "SamplesChip"
	chip.AnchorPoint = Vector2.new(1, 0)
	chip.Position = UDim2.new(1, 0, 0, CHIP_Y)
	chip.Size = UDim2.fromOffset(118, 34)
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

	local flask = makeFlaskIcon(chip, 14, HOLO_EDGE)
	flask.AnchorPoint = Vector2.new(0, 0.5)
	flask.Position = UDim2.new(0, 10, 0.5, 0)
	flask.ZIndex = 53

	local chipLabel = Instance.new("TextLabel")
	chipLabel.Name = "SamplesLabel"
	chipLabel.BackgroundTransparency = 1
	chipLabel.BorderSizePixel = 0
	chipLabel.Position = UDim2.fromOffset(28, 0)
	chipLabel.Size = UDim2.new(1, -36, 1, 0)
	chipLabel.Font = FONT_TITLE
	chipLabel.TextSize = 13
	chipLabel.TextColor3 = HOLO_EDGE
	chipLabel.TextXAlignment = Enum.TextXAlignment.Left
	chipLabel.Text = "SAMPLES · 0"
	chipLabel.ZIndex = 53
	chipLabel.Parent = chip

	local function countMatchingSamples()
		local mercName = ctx.mercName
		if not mercName then return 0 end
		local n = 0
		local containers = { player:FindFirstChild("Backpack"), player.Character }
		for _, container in ipairs(containers) do
			if container then
				for _, tool in container:GetChildren() do
					if tool:IsA("Tool") and tool.Name == "FullCapsule" then
						-- Lenient: untagged capsules (from collections
						-- that pre-date Step 1's BloodType stamp)
						-- count as legacy-valid so the player's
						-- existing inventory is usable.
						local bt = tool:GetAttribute("BloodType")
						if bt == nil or bt == "" or bt == mercName then
							n = n + 1
						end
					end
				end
			end
		end
		return n
	end
	-- Sample-count chip inside the SAMPLE SLOT card header (built a
	-- bit further down in Step 6's block). Forward-declared so the
	-- refresher below can populate it without caring about build
	-- order.
	local sampleCardCountLabel

	local function refreshSamplesChip()
		local n = countMatchingSamples()
		chipLabel.Text = string.format("SAMPLES · %d", n)
		if sampleCardCountLabel then
			sampleCardCountLabel.Text = tostring(n)
		end
	end
	refreshSamplesChip()

	-- Subscribe to Backpack + Character tool add/remove so the counter
	-- ticks in real-time when the player picks up / uses a capsule.
	local function hookContainer(container)
		if not container then return end
		table.insert(activeConnections,
			container.ChildAdded:Connect(refreshSamplesChip))
		table.insert(activeConnections,
			container.ChildRemoved:Connect(refreshSamplesChip))
	end
	hookContainer(player:FindFirstChild("Backpack"))
	hookContainer(player.Character)
	table.insert(activeConnections,
		player.CharacterAdded:Connect(function(char)
			hookContainer(char)
			refreshSamplesChip()
		end))

	-- ── Column scaffolds (contents land in Steps 6-10) ──────────────
	-- Positions / sizes derived from the Claude Design mockup:
	--   left  : Sample Slot (top) + Research Log (bottom)
	--   centre: DNA helix + decoded %
	--   right : Decoded Traits list (8 entries)
	local COLS_Y       = 104
	local COLS_H       = 476
	local LEFT_COL_X   = 40
	local LEFT_COL_W   = 240
	local RIGHT_COL_X  = REFERENCE_W - 40 - 240
	local RIGHT_COL_W  = 240
	local CENTRE_COL_X = LEFT_COL_X + LEFT_COL_W + 40
	local CENTRE_COL_W = RIGHT_COL_X - CENTRE_COL_X - 40

	local function makeColumn(name, x, w)
		local col = Instance.new("Frame")
		col.Name = name
		col.BackgroundTransparency = 1
		col.BorderSizePixel = 0
		col.Position = UDim2.fromOffset(x, COLS_Y)
		col.Size = UDim2.fromOffset(w, COLS_H)
		col.ZIndex = 51
		col.Parent = scaleWrap
		return col
	end
	local leftColumn   = makeColumn("LeftColumn",   LEFT_COL_X,   LEFT_COL_W)
	local centreColumn = makeColumn("CentreColumn", CENTRE_COL_X, CENTRE_COL_W)
	local rightColumn  = makeColumn("RightColumn",  RIGHT_COL_X,  RIGHT_COL_W)
	local _ = { centreColumn, rightColumn } -- Steps 8-10 fill these

	-- ── Sample Slot card (top of left column) ─────────────────────────
	-- Holo panel with a flask-glyph header, a dashed inner drop zone
	-- sized so the corner dashes line up, and a helper-text block at
	-- the bottom. The drop zone is clickable (TextButton) — Step 11
	-- wires it to fire DNAResearch.insertBlood. For now, click is a
	-- print stub so the shape of the interaction shows during review.
	local SAMPLE_CARD_H = 220

	local sampleCard = Instance.new("Frame")
	sampleCard.Name = "SampleSlotCard"
	sampleCard.BackgroundColor3 = HOLO_PANEL_FILL
	sampleCard.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	sampleCard.BorderSizePixel = 0
	sampleCard.Position = UDim2.fromOffset(0, 0)
	sampleCard.Size = UDim2.fromOffset(LEFT_COL_W, SAMPLE_CARD_H)
	sampleCard.ZIndex = 52
	sampleCard.Parent = leftColumn
	local scStroke = Instance.new("UIStroke")
	scStroke.Color     = HOLO_PANEL_BORDER
	scStroke.Thickness = 1
	scStroke.Parent    = sampleCard

	-- Header: flask glyph + "SAMPLE SLOT" label
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.Position = UDim2.fromOffset(14, 12)
	header.Size = UDim2.new(1, -28, 0, 16)
	header.ZIndex = 53
	header.Parent = sampleCard

	local headerFlask = makeFlaskIcon(header, 12, HOLO_EDGE)
	headerFlask.AnchorPoint = Vector2.new(0, 0.5)
	headerFlask.Position = UDim2.new(0, 0, 0.5, 0)
	headerFlask.ZIndex = 54

	local headerLabel = Instance.new("TextLabel")
	headerLabel.BackgroundTransparency = 1
	headerLabel.BorderSizePixel = 0
	headerLabel.Position = UDim2.fromOffset(18, 0)
	headerLabel.Size = UDim2.new(1, -18, 1, 0)
	headerLabel.Font = FONT_TITLE
	headerLabel.TextSize = 12
	headerLabel.TextColor3 = COLOR_TEXT
	headerLabel.TextXAlignment = Enum.TextXAlignment.Left
	headerLabel.Text = "SAMPLE SLOT"
	headerLabel.ZIndex = 54
	headerLabel.Parent = header

	-- Matching-capsule counter on the right of the card header.
	-- Shares state with the top-right SAMPLES chip — refreshSamplesChip
	-- writes to both. Assigned to the forward-declared upvalue above
	-- so the first refreshSamplesChip() call that already ran picks
	-- it up on the next refresh (after inventory changes).
	local countIcon = makeFlaskIcon(header, 14, HOLO_EDGE)
	countIcon.AnchorPoint = Vector2.new(1, 0.5)
	countIcon.Position = UDim2.new(1, 0, 0.5, 0)
	countIcon.ZIndex = 54

	local cardCountLabel = Instance.new("TextLabel")
	cardCountLabel.Name = "SampleCount"
	cardCountLabel.BackgroundTransparency = 1
	cardCountLabel.BorderSizePixel = 0
	cardCountLabel.AnchorPoint = Vector2.new(1, 0.5)
	cardCountLabel.Position = UDim2.new(1, -18, 0.5, 0)
	cardCountLabel.Size = UDim2.fromOffset(40, 16)
	cardCountLabel.Font = FONT_TITLE
	cardCountLabel.TextSize = 14
	cardCountLabel.TextColor3 = HOLO_EDGE
	cardCountLabel.TextXAlignment = Enum.TextXAlignment.Right
	cardCountLabel.Text = "0"
	cardCountLabel.ZIndex = 54
	cardCountLabel.Parent = header

	sampleCardCountLabel = cardCountLabel
	refreshSamplesChip()

	-- Drop zone — the dashed-outline rectangle itself is a TextButton so
	-- the whole area is clickable without extra event routing.
	local DROP_ZONE_TOP    = 38
	local DROP_ZONE_SIDE   = 14
	local DROP_ZONE_W      = LEFT_COL_W - DROP_ZONE_SIDE * 2
	local DROP_ZONE_H      = 120

	local dropZone = Instance.new("TextButton")
	dropZone.Name = "DropZone"
	dropZone.AutoButtonColor = false
	dropZone.Text = ""
	dropZone.BackgroundColor3 = Color3.fromRGB(8, 22, 40)
	dropZone.BackgroundTransparency = 0.25
	dropZone.BorderSizePixel = 0
	dropZone.Position = UDim2.fromOffset(DROP_ZONE_SIDE, DROP_ZONE_TOP)
	dropZone.Size = UDim2.fromOffset(DROP_ZONE_W, DROP_ZONE_H)
	dropZone.ZIndex = 53
	dropZone.Parent = sampleCard

	dashedStrokeRect(dropZone, DROP_ZONE_W, DROP_ZONE_H, HOLO_PANEL_BORDER, 6, 4, 1)

	-- Big flask glyph inside the drop zone, biased slightly upward so
	-- the "DROP DNA SAMPLE" label sits below it comfortably.
	local bigFlask = makeFlaskIcon(dropZone, 34, COLOR_TEXT_DIM)
	bigFlask.AnchorPoint = Vector2.new(0.5, 0.5)
	bigFlask.Position = UDim2.fromScale(0.5, 0.38)
	bigFlask.ZIndex = 54

	local dropLabel = Instance.new("TextLabel")
	dropLabel.Name = "DropLabel"
	dropLabel.BackgroundTransparency = 1
	dropLabel.BorderSizePixel = 0
	dropLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	dropLabel.Position = UDim2.fromScale(0.5, 0.76)
	dropLabel.Size = UDim2.new(1, -20, 0, 16)
	dropLabel.Font = FONT_TITLE
	dropLabel.TextSize = 12
	dropLabel.TextColor3 = COLOR_TEXT_DIM
	dropLabel.TextXAlignment = Enum.TextXAlignment.Center
	dropLabel.Text = "DROP DNA SAMPLE"
	dropLabel.ZIndex = 54
	dropLabel.Parent = dropZone

	-- Helper text under the drop zone.
	local helper = Instance.new("TextLabel")
	helper.Name = "Helper"
	helper.BackgroundTransparency = 1
	helper.BorderSizePixel = 0
	helper.Position = UDim2.fromOffset(14, DROP_ZONE_TOP + DROP_ZONE_H + 8)
	helper.Size = UDim2.new(1, -28, 0, 32)
	helper.Font = FONT_BODY
	helper.TextSize = 11
	helper.TextColor3 = COLOR_TEXT_MUTE
	helper.TextWrapped = true
	helper.TextXAlignment = Enum.TextXAlignment.Center
	helper.TextYAlignment = Enum.TextYAlignment.Top
	helper.Text = "Click the slot to insert a DNA sample. Each decode unlocks one fragment."
	helper.ZIndex = 53
	helper.Parent = sampleCard

	-- ── Countdown overlay inside the drop zone ───────────────────────
	-- Sits above the flask/drop-label; invisible while the slot is
	-- idle. When a study is running it:
	--   * hides the drop-zone prompt,
	--   * shows a large MM:SS timer and a progress bar,
	--   * blocks the click until the study completes.
	local countdownOverlay = Instance.new("Frame")
	countdownOverlay.Name = "CountdownOverlay"
	countdownOverlay.BackgroundColor3 = Color3.fromRGB(6, 18, 34)
	countdownOverlay.BackgroundTransparency = 0.15
	countdownOverlay.BorderSizePixel = 0
	countdownOverlay.Size = UDim2.fromScale(1, 1)
	countdownOverlay.Visible = false
	countdownOverlay.ZIndex = 55
	countdownOverlay.Parent = dropZone

	local countdownLabel = Instance.new("TextLabel")
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.BorderSizePixel = 0
	countdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	countdownLabel.Position = UDim2.fromScale(0.5, 0.38)
	countdownLabel.Size = UDim2.new(1, -16, 0, 32)
	countdownLabel.Font = FONT_TITLE
	countdownLabel.TextSize = 24
	countdownLabel.TextColor3 = HOLO_EDGE
	countdownLabel.TextXAlignment = Enum.TextXAlignment.Center
	countdownLabel.Text = "00:00"
	countdownLabel.ZIndex = 56
	countdownLabel.Parent = countdownOverlay

	local studyingLabel = Instance.new("TextLabel")
	studyingLabel.BackgroundTransparency = 1
	studyingLabel.BorderSizePixel = 0
	studyingLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	studyingLabel.Position = UDim2.fromScale(0.5, 0.62)
	studyingLabel.Size = UDim2.new(1, -16, 0, 16)
	studyingLabel.Font = FONT_BODY
	studyingLabel.TextSize = 11
	studyingLabel.TextColor3 = COLOR_TEXT_DIM
	studyingLabel.TextXAlignment = Enum.TextXAlignment.Center
	studyingLabel.Text = "STUDYING DNA SAMPLE"
	studyingLabel.ZIndex = 56
	studyingLabel.Parent = countdownOverlay

	local progressTrack = Instance.new("Frame")
	progressTrack.BackgroundColor3 = Color3.fromRGB(8, 20, 38)
	progressTrack.BackgroundTransparency = 0.2
	progressTrack.BorderSizePixel = 0
	progressTrack.AnchorPoint = Vector2.new(0.5, 1)
	progressTrack.Position = UDim2.new(0.5, 0, 1, -12)
	progressTrack.Size = UDim2.new(1, -24, 0, 4)
	progressTrack.ZIndex = 56
	progressTrack.Parent = countdownOverlay
	local ptStroke = Instance.new("UIStroke")
	ptStroke.Color     = HOLO_PANEL_BORDER
	ptStroke.Thickness = 1
	ptStroke.Parent    = progressTrack

	local progressFill = Instance.new("Frame")
	progressFill.BackgroundColor3 = HOLO_EDGE
	progressFill.BorderSizePixel = 0
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.ZIndex = 57
	progressFill.Parent = progressTrack

	-- Transient "NO SAMPLE" / "SLOT BUSY" message, shown under the
	-- drop-label when an insert is rejected by the server.
	local toast = Instance.new("TextLabel")
	toast.Name = "Toast"
	toast.BackgroundTransparency = 1
	toast.BorderSizePixel = 0
	toast.AnchorPoint = Vector2.new(0.5, 0.5)
	toast.Position = UDim2.fromScale(0.5, 0.92)
	toast.Size = UDim2.new(1, -16, 0, 14)
	toast.Font = FONT_TITLE
	toast.TextSize = 11
	toast.TextColor3 = Color3.fromRGB(255, 160, 140)
	toast.TextXAlignment = Enum.TextXAlignment.Center
	toast.TextTransparency = 1
	toast.Text = ""
	toast.ZIndex = 56
	toast.Parent = dropZone

	local toastToken = 0
	local function showToast(message)
		toastToken = toastToken + 1
		local myToken = toastToken
		toast.Text = message
		toast.TextTransparency = 0
		task.delay(2.4, function()
			if myToken == toastToken then
				toast.TextTransparency = 1
			end
		end)
	end

	-- Forward declaration. The real implementation is assigned after
	-- the trait tiles + fragment refs + log refs + genome label all
	-- exist (further down in this function). Callers reach it through
	-- this upvalue so the OnClientEvent handler below can dispatch
	-- snapshots to it without caring about declaration order.
	local refreshFromSnapshot

	-- ── State machine for the sample slot ────────────────────────────
	-- Driven by snapshots from DNAResearch.getState / insertBlood /
	-- the server's study tick. The client's countdown is a simple
	-- local decrement of `secondsRemaining`; the server fires a fresh
	-- snapshot when the tick actually completes so we just re-sync
	-- from that instead of trying to reach zero on our own clock.
	local studyRemaining = 0
	local studyDuration  = 60
	local studyActive    = false

	local function renderSlotFromSnapshot(snapshot)
		local slot = snapshot and snapshot.activeSlot or nil
		studyDuration  = (slot and slot.totalDuration) or 60
		studyRemaining = math.max(0, (slot and slot.secondsRemaining) or 0)
		studyActive    = (slot ~= nil and slot.bloodType ~= nil and studyRemaining > 0)

		countdownOverlay.Visible = studyActive
		bigFlask.Visible  = not studyActive
		dropLabel.Visible = not studyActive

		if studyActive then
			local mins = math.floor(studyRemaining / 60)
			local secs = studyRemaining - mins * 60
			countdownLabel.Text = string.format("%02d:%02d", mins, secs)
			local pct = 1 - (studyRemaining / math.max(1, studyDuration))
			progressFill.Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0)
		end
	end

	-- Local 1 Hz ticker — only runs while studyActive. Decrements the
	-- locally-cached remaining seconds and re-renders the MM:SS +
	-- progress bar. Server still owns the authoritative completion
	-- event; this is just for smooth UI.
	table.insert(activeConnections, RunService.Heartbeat:Connect(function(dt)
		if not studyActive then return end
		studyRemaining = math.max(0, studyRemaining - dt)
		local mins = math.floor(studyRemaining / 60)
		local secs = math.floor(studyRemaining - mins * 60)
		countdownLabel.Text = string.format("%02d:%02d", mins, secs)
		local pct = 1 - (studyRemaining / math.max(1, studyDuration))
		progressFill.Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0)
		if studyRemaining <= 0 then
			-- Server will fire 'studyComplete' within ~1 s; hide the
			-- overlay now so the UI doesn't look stuck on 00:00.
			studyActive = false
			countdownOverlay.Visible = false
			bigFlask.Visible  = true
			dropLabel.Visible = true
		end
	end))

	-- Initial fetch — populates the overlay immediately on page open
	-- so a study already in progress from a previous session (or a
	-- Handling→DNA Study round-trip) is reflected right away.
	if dnaResearchEvent and ctx.mercName then
		dnaResearchEvent:FireServer("getState", ctx.mercName)
	end

	-- Server → client frames. Step 12 will extend this switch to also
	-- repaint the helix fragments / research log / trait tiles; this
	-- step only handles the slot-state bits.
	--
	-- Server call shapes (from DNAResearch.server.lua):
	--   "state"          mercName, snapshot
	--   "studyComplete"  mercName, fragmentIndex, snapshot, meta
	--   "insertFailed"   mercName, reason
	if dnaResearchEvent then
		table.insert(activeConnections,
			dnaResearchEvent.OnClientEvent:Connect(function(action, mercName, ...)
				if mercName ~= ctx.mercName then return end
				local args = table.pack(...)
				if action == "state" then
					renderSlotFromSnapshot(args[1])
					if refreshFromSnapshot then refreshFromSnapshot(args[1]) end
				elseif action == "studyComplete" then
					-- args[1] = fragmentIndex, args[2] = snapshot, args[3] = meta
					renderSlotFromSnapshot(args[2])
					if refreshFromSnapshot then
						refreshFromSnapshot(args[2], args[1], args[3])
					end
				elseif action == "insertFailed" then
					local reason = args[1]
					if reason == "busy" then
						showToast("SLOT BUSY")
					elseif reason == "noSample" then
						showToast("NO MATCHING SAMPLE")
					else
						showToast("INSERT FAILED")
					end
				end
			end))
	end

	dropZone.MouseButton1Click:Connect(function()
		if studyActive then
			showToast("SLOT BUSY")
			return
		end
		if not dnaResearchEvent or not ctx.mercName then return end
		dnaResearchEvent:FireServer("insertBlood", ctx.mercName)
	end)

	-- ── Research Log card (bottom of left column) ─────────────────────
	-- Four-row data table with dotted leaders between label and value.
	-- Values exposed via logValueRefs so Step 12 can refresh them when
	-- a DNAResearch snapshot arrives without re-rendering the card.
	local LOG_CARD_TOP  = SAMPLE_CARD_H + 14
	local LOG_CARD_H    = COLS_H - LOG_CARD_TOP

	local logCard = Instance.new("Frame")
	logCard.Name = "ResearchLogCard"
	logCard.BackgroundColor3 = HOLO_PANEL_FILL
	logCard.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	logCard.BorderSizePixel = 0
	logCard.Position = UDim2.fromOffset(0, LOG_CARD_TOP)
	logCard.Size = UDim2.fromOffset(LEFT_COL_W, LOG_CARD_H)
	logCard.ZIndex = 52
	logCard.Parent = leftColumn
	local logStroke = Instance.new("UIStroke")
	logStroke.Color     = HOLO_PANEL_BORDER
	logStroke.Thickness = 1
	logStroke.Parent    = logCard

	-- Header: diamond glyph + 'RESEARCH LOG'
	local logHeader = Instance.new("Frame")
	logHeader.BackgroundTransparency = 1
	logHeader.BorderSizePixel = 0
	logHeader.Position = UDim2.fromOffset(14, 12)
	logHeader.Size = UDim2.new(1, -28, 0, 16)
	logHeader.ZIndex = 53
	logHeader.Parent = logCard

	local logDiamond = makeDiamondIcon(logHeader, 12, HOLO_EDGE)
	logDiamond.AnchorPoint = Vector2.new(0, 0.5)
	logDiamond.Position = UDim2.new(0, 0, 0.5, 0)
	logDiamond.ZIndex = 54

	local logTitle = Instance.new("TextLabel")
	logTitle.BackgroundTransparency = 1
	logTitle.BorderSizePixel = 0
	logTitle.Position = UDim2.fromOffset(18, 0)
	logTitle.Size = UDim2.new(1, -18, 1, 0)
	logTitle.Font = FONT_TITLE
	logTitle.TextSize = 12
	logTitle.TextColor3 = COLOR_TEXT
	logTitle.TextXAlignment = Enum.TextXAlignment.Left
	logTitle.Text = "RESEARCH LOG"
	logTitle.ZIndex = 54
	logTitle.Parent = logHeader

	-- Four rows. Layout per row:
	--   [label left] [··· dotted leader ···] [value right]
	local ROW_PAD_X    = 14
	local ROW_FIRST_Y  = 42
	local ROW_HEIGHT   = 24
	local ROW_INNER_W  = LEFT_COL_W - ROW_PAD_X * 2
	local LABEL_W      = 96
	local VALUE_W      = 70
	local LEADER_PAD   = 4
	local LEADER_X     = ROW_PAD_X + LABEL_W + LEADER_PAD
	local LEADER_W     = ROW_INNER_W - LABEL_W - VALUE_W - LEADER_PAD * 2

	local logValueRefs = {}
	local function addRow(index, key, labelText, valueText)
		local y = ROW_FIRST_Y + (index - 1) * ROW_HEIGHT

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.BorderSizePixel = 0
		lbl.Position = UDim2.fromOffset(ROW_PAD_X, y)
		lbl.Size = UDim2.fromOffset(LABEL_W, ROW_HEIGHT)
		lbl.Font = FONT_TITLE
		lbl.TextSize = 11
		lbl.TextColor3 = COLOR_TEXT_DIM
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextYAlignment = Enum.TextYAlignment.Center
		lbl.Text = labelText
		lbl.ZIndex = 53
		lbl.Parent = logCard

		dottedLeader(logCard, LEADER_X, y + math.floor(ROW_HEIGHT / 2),
			LEADER_W, HOLO_PANEL_BORDER, 2, 3)

		local val = Instance.new("TextLabel")
		val.Name = "Value_" .. key
		val.BackgroundTransparency = 1
		val.BorderSizePixel = 0
		val.AnchorPoint = Vector2.new(1, 0)
		val.Position = UDim2.fromOffset(ROW_PAD_X + ROW_INNER_W, y)
		val.Size = UDim2.fromOffset(VALUE_W, ROW_HEIGHT)
		val.Font = FONT_TITLE
		val.TextSize = 12
		val.TextColor3 = HOLO_EDGE
		val.TextXAlignment = Enum.TextXAlignment.Right
		val.TextYAlignment = Enum.TextYAlignment.Center
		val.Text = valueText
		val.ZIndex = 53
		val.Parent = logCard

		logValueRefs[key] = val
	end

	-- Resolve SUBJECT / CLASS from ctx.theme when available; fall back to
	-- sensible defaults so the card still reads cleanly for mercs the
	-- theme table doesn't know about yet.
	local theme = ctx.theme or {}
	local subject = theme.displayName or tostring(ctx.mercName or "—")
	local class   = theme.role or "Unclassified"

	addRow(1, "SUBJECT",   "SUBJECT",      subject)
	addRow(2, "CLASS",     "CLASS",        class)
	addRow(3, "FRAGMENTS", "FRAGMENTS",    "0 / 9")
	addRow(4, "KILLS",     "KILLS LOGGED", "0")

	-- logValueRefs is consumed by refreshFromSnapshot below.

	-- ── Centre column: DNA double helix + GENOME DECODED % ───────────
	-- Two continuous sine-wave rails twisting around each other with
	-- a +π/2 phase shift so the rails START at their widest (top
	-- bracket cap) and end there too (bottom bracket cap). Over a
	-- HELIX_H of 360 px the rails cross each other 4 times (y = 45,
	-- 135, 225, 315), which cuts the span into three full lenses
	-- plus two half-lens caps — the exact silhouette from the new
	-- reference image.
	--
	-- Layout (centreColumn-local):
	--   HELIX_CENTRE_X = CENTRE_COL_W / 2
	--   HELIX_TOP_Y    = 30
	--   HELIX_H        = 360                         (2 * period)
	--   HELIX_AMP      = 44                          (bracket half-width)
	--   HELIX_PERIOD   = 180                         (lens = period/2 = 90)
	--   GENOME_Y       = HELIX_TOP_Y + HELIX_H + 16  = 406
	local HELIX_CENTRE_X = CENTRE_COL_W / 2
	local HELIX_TOP_Y    = 30
	local HELIX_H        = 360
	local HELIX_AMP      = 44
	local HELIX_PERIOD   = 180

	-- Two rails with a slight "glow" underlay: wider low-opacity pass
	-- first, thinner bright pass on top. Reads as a soft cyan beam at
	-- screen size without needing shader tricks.
	drawHelixRails(centreColumn, HELIX_CENTRE_X, HELIX_TOP_Y, HELIX_AMP,
		HELIX_H, HELIX_PERIOD,
		Color3.fromRGB(70, 140, 200), 6, 96)
	drawHelixRails(centreColumn, HELIX_CENTRE_X, HELIX_TOP_Y, HELIX_AMP,
		HELIX_H, HELIX_PERIOD, HOLO_EDGE, 3, 96)

	-- ── 9 fragment bars ───────────────────────────────────────────────
	-- F01-F03 strength (top lens), F04-F06 luck (middle lens),
	-- F07-F09 speed (bottom lens) — matches the server's SECTION_STAT
	-- map. Three rungs per lens, placed at the quarter / half / three-
	-- quarter points of the lens's vertical span so the middle rung
	-- sits at the widest part of the rail gap. Widths derive from the
	-- actual rail gap at each rung's Y (|2 * amp * sin(phase)|) scaled
	-- slightly so the bars stop just shy of the rails.
	local FRAGMENT_COUNT = 9
	local LENS_COUNT     = 3
	local BARS_PER_LENS  = 3
	local BAR_THICKNESS  = 2
	local DOT_SIZE       = 4
	local LENS_BAR_SCALE = 0.82

	local function buildFragmentBar(index, y, width)
		local frag = Instance.new("Frame")
		frag.Name = string.format("Fragment_F%02d", index)
		frag.BackgroundTransparency = 1
		frag.BorderSizePixel = 0
		frag.AnchorPoint = Vector2.new(0.5, 0.5)
		frag.Position = UDim2.fromOffset(HELIX_CENTRE_X, y)
		frag.Size = UDim2.fromOffset(width + DOT_SIZE, math.max(BAR_THICKNESS, DOT_SIZE))
		frag.ZIndex = (centreColumn.ZIndex or 1) + 2
		frag.Parent = centreColumn

		-- Dim track across the full bar width. The filled overlay
		-- underneath grows from the left as the fragment is studied.
		local track = Instance.new("Frame")
		track.Name = "Track"
		track.AnchorPoint = Vector2.new(0.5, 0.5)
		track.Position = UDim2.fromScale(0.5, 0.5)
		track.Size = UDim2.fromOffset(width, BAR_THICKNESS)
		track.BackgroundColor3 = HOLO_PANEL_BORDER
		track.BackgroundTransparency = 0.35
		track.BorderSizePixel = 0
		track.ZIndex = frag.ZIndex
		track.Parent = frag

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.AnchorPoint = Vector2.new(0, 0.5)
		fill.Position = UDim2.new(0, 0, 0.5, 0)
		fill.Size = UDim2.new(0, 0, 1, 0)  -- starts empty; Step 12 resizes
		fill.BackgroundColor3 = HOLO_EDGE
		fill.BackgroundTransparency = 0
		fill.BorderSizePixel = 0
		fill.ZIndex = track.ZIndex + 1
		fill.Parent = track

		local function makeDot(xScale)
			local d = Instance.new("Frame")
			d.AnchorPoint = Vector2.new(0.5, 0.5)
			d.Position = UDim2.fromScale(xScale, 0.5)
			d.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
			d.BackgroundColor3 = HOLO_EDGE
			d.BorderSizePixel = 0
			d.ZIndex = frag.ZIndex + 2
			d.Parent = frag
			local dc = Instance.new("UICorner")
			dc.CornerRadius = UDim.new(1, 0)
			dc.Parent = d
		end
		makeDot(0)
		makeDot(1)

		-- Fragment label, centred above the bar. Small muted text so it
		-- reads as metadata, not content — matches the mockup's F01..F10
		-- row labels.
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.fromScale(0.5, 0)
		label.Size = UDim2.fromOffset(30, 10)
		label.Font = FONT_BODY
		label.TextSize = 9
		label.TextColor3 = COLOR_TEXT_MUTE
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Text = string.format("F%02d", index)
		label.ZIndex = frag.ZIndex + 2
		label.Parent = frag

		return { frame = frag, track = track, fill = fill, width = width }
	end

	local fragmentRefs = {}

	-- Each lens spans HELIX_PERIOD / 2 = 90 px and lives between two
	-- consecutive rail crossovers. With the +π/2 phase shift the
	-- crossovers fall at y = HELIX_TOP_Y + (k + 0.25) * HELIX_PERIOD
	-- for k = 0, 1, 2, 3 — so the three usable lenses start at
	--   lens 1: HELIX_TOP_Y + 0.25 * P   (y = 75)
	--   lens 2: HELIX_TOP_Y + 0.75 * P   (y = 165)
	--   lens 3: HELIX_TOP_Y + 1.25 * P   (y = 255)
	-- Half-lens regions above and below host no fragments — they're
	-- the bracket caps from the reference image.
	local LENS_H     = HELIX_PERIOD / 2       -- 90
	local LENS_1_TOP = HELIX_TOP_Y + HELIX_PERIOD * 0.25
	for lensIdx = 1, LENS_COUNT do
		local lensTopY = LENS_1_TOP + (lensIdx - 1) * LENS_H
		for rung = 1, BARS_PER_LENS do
			local t = rung / (BARS_PER_LENS + 1)  -- 1/4, 2/4, 3/4
			local y = lensTopY + t * LENS_H
			-- Rail gap at this y, matching drawHelixRails' math
			-- (same +π/2 phase shift).
			local phase = 2 * math.pi * (y - HELIX_TOP_Y) / HELIX_PERIOD + math.pi * 0.5
			local gap   = 2 * HELIX_AMP * math.abs(math.sin(phase))
			local width = gap * LENS_BAR_SCALE
			local idx = (lensIdx - 1) * BARS_PER_LENS + rung
			fragmentRefs[idx] = buildFragmentBar(idx, y, width)
		end
	end

	-- fragmentRefs is consumed by refreshFromSnapshot below.

	-- GENOME DECODED label + percentage. Percentage value ref stashed
	-- so Step 12 can tween it when fragments advance.
	local GENOME_Y = HELIX_TOP_Y + HELIX_H + 16
	local genomeRow = Instance.new("Frame")
	genomeRow.Name = "GenomeDecoded"
	genomeRow.BackgroundTransparency = 1
	genomeRow.BorderSizePixel = 0
	genomeRow.AnchorPoint = Vector2.new(0.5, 0)
	genomeRow.Position = UDim2.new(0.5, 0, 0, GENOME_Y)
	genomeRow.Size = UDim2.fromOffset(260, 22)
	genomeRow.ZIndex = 52
	genomeRow.Parent = centreColumn

	local genomeLabel = Instance.new("TextLabel")
	genomeLabel.BackgroundTransparency = 1
	genomeLabel.BorderSizePixel = 0
	genomeLabel.Position = UDim2.fromOffset(0, 0)
	genomeLabel.Size = UDim2.new(1, -56, 1, 0)
	genomeLabel.Font = FONT_TITLE
	genomeLabel.TextSize = 12
	genomeLabel.TextColor3 = COLOR_TEXT_DIM
	genomeLabel.TextXAlignment = Enum.TextXAlignment.Right
	genomeLabel.Text = "GENOME DECODED"
	genomeLabel.ZIndex = 53
	genomeLabel.Parent = genomeRow

	local genomeValue = Instance.new("TextLabel")
	genomeValue.Name = "Percent"
	genomeValue.BackgroundTransparency = 1
	genomeValue.BorderSizePixel = 0
	genomeValue.AnchorPoint = Vector2.new(1, 0)
	genomeValue.Position = UDim2.fromScale(1, 0)
	genomeValue.Size = UDim2.fromOffset(56, 22)
	genomeValue.Font = FONT_TITLE
	genomeValue.TextSize = 16
	genomeValue.TextColor3 = HOLO_EDGE
	genomeValue.TextXAlignment = Enum.TextXAlignment.Right
	genomeValue.Text = "0%"
	genomeValue.ZIndex = 53
	genomeValue.Parent = genomeRow

	-- genomeValue is consumed by refreshFromSnapshot below.

	-- ── Right column: Decoded Traits ──────────────────────────────────
	-- Holo card at top ("DECODED TRAITS" header) stacked over 8 trait
	-- tiles. Tiles 1-5 are always-unlocked descriptive entries;
	-- tiles 6-8 auto-unlock at 70 / 85 / 100 % genome and become
	-- click-to-spend — a click consumes one research point and bumps
	-- the trait's effect %. Spend wiring lands in Step 12 when the
	-- snapshot subscription plugs in.
	local TRAIT_HEADER_H = 22
	local TRAIT_TILE_H   = 46
	local TRAIT_GAP      = 6
	local TRAIT_PAD_X    = 12

	local traitHeader = Instance.new("Frame")
	traitHeader.BackgroundTransparency = 1
	traitHeader.BorderSizePixel = 0
	traitHeader.Position = UDim2.fromOffset(0, 0)
	traitHeader.Size = UDim2.fromOffset(RIGHT_COL_W, TRAIT_HEADER_H)
	traitHeader.ZIndex = 52
	traitHeader.Parent = rightColumn

	local traitDiamond = makeDiamondIcon(traitHeader, 12, HOLO_EDGE)
	traitDiamond.AnchorPoint = Vector2.new(0, 0.5)
	traitDiamond.Position = UDim2.new(0, TRAIT_PAD_X, 0.5, 0)
	traitDiamond.ZIndex = 53

	local traitTitle = Instance.new("TextLabel")
	traitTitle.BackgroundTransparency = 1
	traitTitle.BorderSizePixel = 0
	traitTitle.Position = UDim2.fromOffset(TRAIT_PAD_X + 18, 0)
	traitTitle.Size = UDim2.new(1, -(TRAIT_PAD_X + 18 + 70 + TRAIT_PAD_X), 1, 0)
	traitTitle.Font = FONT_TITLE
	traitTitle.TextSize = 12
	traitTitle.TextColor3 = COLOR_TEXT
	traitTitle.TextXAlignment = Enum.TextXAlignment.Left
	traitTitle.TextYAlignment = Enum.TextYAlignment.Center
	traitTitle.Text = "DECODED TRAITS"
	traitTitle.ZIndex = 53
	traitTitle.Parent = traitHeader

	-- Research-points counter, right-aligned. Live-updated in the
	-- snapshot subscription below. Click an unlocked trait tile to
	-- spend a point and bump that trait's effect %.
	local rpLabel = Instance.new("TextLabel")
	rpLabel.Name = "RPCounter"
	rpLabel.BackgroundTransparency = 1
	rpLabel.BorderSizePixel = 0
	rpLabel.AnchorPoint = Vector2.new(1, 0.5)
	rpLabel.Position = UDim2.new(1, -TRAIT_PAD_X, 0.5, 0)
	rpLabel.Size = UDim2.fromOffset(70, 14)
	rpLabel.Font = FONT_TITLE
	rpLabel.TextSize = 11
	rpLabel.TextColor3 = HOLO_EDGE
	rpLabel.TextXAlignment = Enum.TextXAlignment.Right
	rpLabel.Text = "0 RP"
	rpLabel.ZIndex = 53
	rpLabel.Parent = traitHeader

	-- Trait metadata. `unlockPct` = nil means the trait is always
	-- unlocked (descriptive); otherwise it unlocks when the merc's
	-- genome-decoded percentage crosses that threshold. `key`
	-- matches the server's `traitEffect` sub-table keys for the 3
	-- mutation slots.
	local TRAITS = {
		{ key = "species",      name = "SPECIES",       body = "Humanoid · Pirate lineage", icon = makePersonIcon,    unlockPct = nil },
		{ key = "baseStrength", name = "BASE STRENGTH", body = "Above average",             icon = makeStarIcon,      unlockPct = nil },
		{ key = "mobility",     name = "MOBILITY",      body = "Agile, coastal",            icon = makeRunIcon,       unlockPct = nil },
		{ key = "behaviour",    name = "BEHAVIOUR",     body = "Aggressive, grouping",      icon = makeShieldIcon,    unlockPct = nil },
		{ key = "abilitySeed",  name = "ABILITY SEED",  body = "Iron Grip unlocked",        icon = makePlusIcon,      unlockPct = nil },
		{ key = "rareMarker",   name = "RARE MARKER",   body = "Decodes at 70%",            icon = makeLockIcon,      unlockPct = 70  },
		{ key = "mutation",     name = "MUTATION",      body = "Decodes at 85%",            icon = makeMiniHelixIcon, unlockPct = 85  },
		{ key = "fullGenome",   name = "FULL GENOME",   body = "Decodes at 100%",           icon = makeDiamondIcon,   unlockPct = 100 },
	}

	local traitRefs = {}

	local function buildTraitTile(index, def)
		local y = TRAIT_HEADER_H + (index - 1) * (TRAIT_TILE_H + TRAIT_GAP) + TRAIT_GAP

		local tile = Instance.new("TextButton")
		tile.Name = "Trait_" .. def.key
		tile.AutoButtonColor = false
		tile.Text = ""
		tile.BackgroundColor3 = HOLO_PANEL_FILL
		tile.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
		tile.BorderSizePixel = 0
		tile.Position = UDim2.fromOffset(0, y)
		tile.Size = UDim2.fromOffset(RIGHT_COL_W, TRAIT_TILE_H)
		tile.ZIndex = 52
		tile.Parent = rightColumn

		local stroke = Instance.new("UIStroke")
		stroke.Color     = HOLO_PANEL_BORDER
		stroke.Thickness = 1
		stroke.Parent    = tile

		local iconBox = Instance.new("Frame")
		iconBox.BackgroundColor3 = Color3.fromRGB(16, 34, 58)
		iconBox.BackgroundTransparency = 0.3
		iconBox.BorderSizePixel = 0
		iconBox.Position = UDim2.fromOffset(TRAIT_PAD_X, (TRAIT_TILE_H - 26) / 2)
		iconBox.Size = UDim2.fromOffset(26, 26)
		iconBox.ZIndex = 53
		iconBox.Parent = tile
		local ibStroke = Instance.new("UIStroke")
		ibStroke.Color     = HOLO_PANEL_BORDER
		ibStroke.Thickness = 1
		ibStroke.Parent    = iconBox

		local glyph = def.icon(iconBox, 18, HOLO_EDGE)
		if glyph then
			glyph.AnchorPoint = Vector2.new(0.5, 0.5)
			glyph.Position = UDim2.fromScale(0.5, 0.5)
			glyph.ZIndex = 54
		end

		local textX = TRAIT_PAD_X + 26 + 10
		local nameLbl = Instance.new("TextLabel")
		nameLbl.BackgroundTransparency = 1
		nameLbl.BorderSizePixel = 0
		nameLbl.Position = UDim2.fromOffset(textX, 6)
		nameLbl.Size = UDim2.new(1, -(textX + TRAIT_PAD_X), 0, 14)
		nameLbl.Font = FONT_TITLE
		nameLbl.TextSize = 11
		nameLbl.TextColor3 = COLOR_TEXT
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Text = def.name
		nameLbl.ZIndex = 53
		nameLbl.Parent = tile

		local bodyLbl = Instance.new("TextLabel")
		bodyLbl.BackgroundTransparency = 1
		bodyLbl.BorderSizePixel = 0
		bodyLbl.Position = UDim2.fromOffset(textX, 22)
		bodyLbl.Size = UDim2.new(1, -(textX + TRAIT_PAD_X), 0, 16)
		bodyLbl.Font = FONT_BODY
		bodyLbl.TextSize = 11
		bodyLbl.TextColor3 = COLOR_TEXT_DIM
		bodyLbl.TextXAlignment = Enum.TextXAlignment.Left
		bodyLbl.Text = def.body
		bodyLbl.ZIndex = 53
		bodyLbl.Parent = tile

		local ref = {
			tile = tile, stroke = stroke, iconBox = iconBox,
			nameLbl = nameLbl, bodyLbl = bodyLbl,
			def = def, unlocked = (def.unlockPct == nil),
		}

		-- Default visual state: unlocked for descriptive traits,
		-- locked (dimmed, "Decodes at N%") for mutation traits.
		local function applyVisualState()
			if ref.unlocked then
				tile.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
				stroke.Color      = HOLO_PANEL_BORDER
				nameLbl.TextColor3 = COLOR_TEXT
				bodyLbl.TextColor3 = COLOR_TEXT_DIM
			else
				tile.BackgroundTransparency = 0.6
				stroke.Color      = Color3.fromRGB(55, 75, 100)
				nameLbl.TextColor3 = COLOR_TEXT_DIM
				bodyLbl.TextColor3 = COLOR_TEXT_MUTE
			end
		end
		ref.applyVisualState = applyVisualState
		applyVisualState()

		tile.MouseButton1Click:Connect(function()
			if not ref.unlocked then return end
			if def.unlockPct == nil then return end -- descriptive trait
			if not dnaResearchEvent or not ctx.mercName then return end
			dnaResearchEvent:FireServer("spendResearchPoint", ctx.mercName, def.key)
		end)

		return ref
	end

	for i, def in ipairs(TRAITS) do
		traitRefs[def.key] = buildTraitTile(i, def)
	end

	-- ── Snapshot subscription (assigns the forward-declared upvalue) ──
	-- Called from the OnClientEvent handler above. One pass updates:
	--   * fragment fill bars (tweened) + optional pulse on the bar
	--     that just advanced (passed in as `studiedIdx`)
	--   * genome decoded %                 (centre column footer)
	--   * research log: FRAGMENTS row      (count of fragments at 100)
	--   * RP counter in the trait header
	--   * trait tile unlock states + body text (effect % when unlocked)
	local FILL_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Sine,
		Enum.EasingDirection.Out)
	local PULSE_TWEEN = TweenInfo.new(0.65, Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out)

	refreshFromSnapshot = function(snapshot, studiedIdx, _meta)
		if type(snapshot) ~= "table" then return end

		-- Fragment fills + genome %.
		local frags = snapshot.fragments or {}
		local sum, completed = 0, 0
		for i = 1, FRAGMENT_COUNT do
			local pct = math.clamp(frags[i] or 0, 0, 100)
			sum = sum + pct
			if pct >= 100 then completed = completed + 1 end
			local ref = fragmentRefs[i]
			if ref then
				TweenService:Create(ref.fill, FILL_TWEEN, {
					Size = UDim2.new(pct / 100, 0, 1, 0),
				}):Play()
			end
		end
		local genomePct = sum / FRAGMENT_COUNT
		genomeValue.Text = string.format("%d%%", math.floor(genomePct + 0.5))

		-- Pulse the fragment that just advanced — flash the track to
		-- white then tween it back to its dim default. Fill colour is
		-- unchanged, so the bright newly-grown segment also gets a
		-- short halo.
		if studiedIdx then
			local ref = fragmentRefs[studiedIdx]
			if ref and ref.track then
				ref.track.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				ref.track.BackgroundTransparency = 0
				TweenService:Create(ref.track, PULSE_TWEEN, {
					BackgroundColor3 = HOLO_PANEL_BORDER,
					BackgroundTransparency = 0.35,
				}):Play()
			end
		end

		-- Research log.
		if logValueRefs.FRAGMENTS then
			logValueRefs.FRAGMENTS.Text = string.format("%d / %d",
				completed, FRAGMENT_COUNT)
		end

		-- RP counter.
		rpLabel.Text = string.format("%d RP", snapshot.researchPoints or 0)

		-- Trait tile unlocks + effect %.
		local effects = snapshot.traitEffect or {}
		for _, def in ipairs(TRAITS) do
			local ref = traitRefs[def.key]
			if ref then
				local nowUnlocked
				if def.unlockPct == nil then
					nowUnlocked = true
				else
					nowUnlocked = genomePct >= def.unlockPct
				end
				ref.unlocked = nowUnlocked
				ref.applyVisualState()

				if def.unlockPct ~= nil then
					if nowUnlocked then
						local eff = effects[def.key] or 0
						ref.bodyLbl.Text = string.format(
							"Effect: %d%%  ·  click to enhance", eff)
					else
						ref.bodyLbl.Text = def.body
					end
				end
			end
		end
	end

	updateResponsiveScale()

	-- Cleanup listeners when the page leaves the hierarchy.
	table.insert(activeConnections, page.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			disconnectAll(activeConnections)
		end
	end))
end

_G.OpenDNAStudyPage  = openDNAStudyPage
_G.CloseDNAStudyPage = closeDNAStudyPage
