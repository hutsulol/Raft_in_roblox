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
	-- Silence "unused" lint until Steps 6-10 fill them.
	local _ = { leftColumn, centreColumn, rightColumn }

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
