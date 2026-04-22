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

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

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

-- ─── Flask / capsule glyph (SAMPLES chip icon) ──────────────────────
-- A tall outlined rectangle with a rounded bottom, pinched neck and a
-- cap line near the top — reads as "blood vial" at small sizes
-- without needing an image asset.
local function makeFlaskIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "FlaskIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.58)
	body.Size = UDim2.fromOffset(size * 0.55, size * 0.72)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Parent = c
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, math.max(1, math.floor(size * 0.14)))
	bc.Parent = body
	local bs = Instance.new("UIStroke")
	bs.Color     = color
	bs.Thickness = 1.4
	bs.Parent    = body

	-- Cap line — two small horizontal ticks sitting at the top of the body
	-- read as a vial stopper.
	local cap = Instance.new("Frame")
	cap.AnchorPoint = Vector2.new(0.5, 0)
	cap.Position = UDim2.fromScale(0.5, 0.12)
	cap.Size = UDim2.fromOffset(size * 0.4, math.max(1, math.floor(size * 0.08)))
	cap.BackgroundColor3 = color
	cap.BorderSizePixel = 0
	cap.Parent = c

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
					if tool:IsA("Tool") and tool.Name == "FullCapsule"
						and tool:GetAttribute("BloodType") == mercName then
						n = n + 1
					end
				end
			end
		end
		return n
	end
	local function refreshSamplesChip()
		chipLabel.Text = string.format("SAMPLES · %d", countMatchingSamples())
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

	dropZone.MouseButton1Click:Connect(function()
		-- Step 11 replaces this stub with a DNAResearch.insertBlood
		-- fire + countdown UI. Leaving a print so the click path is
		-- observable during review.
		print("[DNAStudyPage] Sample slot clicked for", ctx.mercName)
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
	addRow(3, "FRAGMENTS", "FRAGMENTS",    "0 / 16")
	addRow(4, "KILLS",     "KILLS LOGGED", "0")

	-- Expose the refs so Step 12 can plug a DNAResearch snapshot
	-- subscription in without needing to re-query the logCard tree.
	local _ = logValueRefs

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
