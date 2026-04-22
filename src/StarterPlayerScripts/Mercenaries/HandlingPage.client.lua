-- HandlingPage.client.lua
-- Mercenary Handling sub-page (LocalScript).
-- Exposes _G.OpenHandlingPage(ctx) + _G.CloseHandlingPage() so
-- MercenariesMenu can route the HANDLING pill here.
--
-- Step 1 of the redesign: the holo scaffold — sea-mist gradient +
-- horizon + vignette + drifting motes backdrop, a 960x600 responsive
-- scaleWrap centred on the screen, and a placeholder BACK button wired
-- to ctx.onBack. Slot tiles, detail card and DNA research card land in
-- subsequent steps.

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

-- ─── Artboard reference (matches the Claude Design MercHandlingPage
-- 960x600 canvas — used as the reference size for the responsive
-- UIScale below) ─────────────────────────────────────────────────────
local REFERENCE_W        = 960
local REFERENCE_H        = 600
local HORIZONTAL_PADDING = 80 -- per-total px reserved for overflow

-- ─── Panels registered here fade the drifting motes when they drift
-- behind them. Populated by future steps as slot tiles / cards come
-- online; step 1 doesn't register any. ───────────────────────────────
local motesOccludeList = {}

-- ─── Module state ────────────────────────────────────────────────────
local activePage = nil
local activeConnections = {}

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
	if activePage then
		activePage:Destroy()
		activePage = nil
	end
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
	backBtn.Size = UDim2.fromOffset(88, 34)
	backBtn.BackgroundColor3 = HOLO_PANEL_FILL
	backBtn.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	backBtn.BorderSizePixel = 0
	backBtn.AutoButtonColor = true
	backBtn.Text = "" -- glyph + label drawn as children
	backBtn.ZIndex = 6
	backBtn.Parent = scaleWrap
	local bStroke = Instance.new("UIStroke")
	bStroke.Color     = HOLO_PANEL_BORDER
	bStroke.Thickness = 1
	bStroke.Parent    = backBtn
	backBtnRef = backBtn

	local backGlyph = makeBackIcon(backBtn, 14, COLOR_TEXT)
	backGlyph.AnchorPoint = Vector2.new(0, 0.5)
	backGlyph.Position = UDim2.new(0, 12, 0.5, 0)

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
	backLabel.Parent = backBtn

	backBtn.MouseButton1Click:Connect(function()
		closeHandlingPage()
		if ctx.onBack then ctx.onBack() end
	end)

	-- ── Centred "MERCENARY / <NAME> / LV N" cluster ──────────────────
	-- Horizontal UIListLayout with three AutomaticSize.X children so
	-- the cluster fits any merc name without needing a hand-tuned
	-- container width. scaleWrap centres it by default (AnchorPoint
	-- 0.5, scale x=0.5).
	local topCluster = Instance.new("Frame")
	topCluster.Name = "TopCluster"
	topCluster.BackgroundTransparency = 1
	topCluster.BorderSizePixel = 0
	topCluster.AnchorPoint = Vector2.new(0.5, 0.5)
	topCluster.Position = UDim2.new(0.5, 0, 0, BACK_BTN_Y + 17)
	topCluster.AutomaticSize = Enum.AutomaticSize.X
	topCluster.Size = UDim2.fromOffset(0, 28)
	topCluster.ZIndex = 6
	topCluster.Parent = scaleWrap

	local clusterList = Instance.new("UIListLayout")
	clusterList.FillDirection = Enum.FillDirection.Horizontal
	clusterList.VerticalAlignment = Enum.VerticalAlignment.Center
	clusterList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	clusterList.Padding = UDim.new(0, 10)
	clusterList.SortOrder = Enum.SortOrder.LayoutOrder
	clusterList.Parent = topCluster

	local mercTag = Instance.new("TextLabel")
	mercTag.Name = "MercTag"
	mercTag.BackgroundTransparency = 1
	mercTag.BorderSizePixel = 0
	mercTag.AutomaticSize = Enum.AutomaticSize.X
	mercTag.Size = UDim2.fromOffset(0, 20)
	mercTag.Font = FONT_TITLE
	mercTag.TextSize = 11
	mercTag.TextColor3 = COLOR_TEXT_MUTE
	mercTag.Text = "MERCENARY"
	mercTag.LayoutOrder = 1
	mercTag.Parent = topCluster

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "MercName"
	nameLabel.BackgroundTransparency = 1
	nameLabel.BorderSizePixel = 0
	nameLabel.AutomaticSize = Enum.AutomaticSize.X
	nameLabel.Size = UDim2.fromOffset(0, 22)
	nameLabel.Font = FONT_TITLE
	nameLabel.TextSize = 18
	nameLabel.TextColor3 = HOLO_EDGE
	nameLabel.Text = mercDisplay
	nameLabel.LayoutOrder = 2
	nameLabel.Parent = topCluster

	-- LV N badge — small stroked Frame with a padded text label.
	local lvBadge = Instance.new("Frame")
	lvBadge.Name = "LvBadge"
	lvBadge.BackgroundTransparency = 1
	lvBadge.BorderSizePixel = 0
	lvBadge.AutomaticSize = Enum.AutomaticSize.X
	lvBadge.Size = UDim2.fromOffset(0, 20)
	lvBadge.LayoutOrder = 3
	lvBadge.Parent = topCluster
	local lvStroke = Instance.new("UIStroke")
	lvStroke.Color     = HOLO_PANEL_BORDER
	lvStroke.Thickness = 1
	lvStroke.Parent    = lvBadge
	local lvPad = Instance.new("UIPadding")
	lvPad.PaddingLeft  = UDim.new(0, 7)
	lvPad.PaddingRight = UDim.new(0, 7)
	lvPad.PaddingTop    = UDim.new(0, 2)
	lvPad.PaddingBottom = UDim.new(0, 2)
	lvPad.Parent = lvBadge

	local lvText = Instance.new("TextLabel")
	lvText.BackgroundTransparency = 1
	lvText.BorderSizePixel = 0
	lvText.AutomaticSize = Enum.AutomaticSize.X
	lvText.Size = UDim2.fromOffset(0, 14)
	lvText.Font = FONT_TITLE
	lvText.TextSize = 11
	lvText.TextColor3 = COLOR_TEXT_DIM
	lvText.Text = string.format("LV %d", mercLevel)
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
	chip.ZIndex = 6
	chip.Parent = scaleWrap
	local chipStroke = Instance.new("UIStroke")
	chipStroke.Color     = HOLO_PANEL_BORDER
	chipStroke.Thickness = 1
	chipStroke.Parent    = chip
	chipRef = chip

	local gemGlyph = makeGemIcon(chip, 13, COLOR_GOLD)
	gemGlyph.AnchorPoint = Vector2.new(0, 0.5)
	gemGlyph.Position = UDim2.new(0, 10, 0.5, 0)

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
	chipLabel.Parent = chip

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
