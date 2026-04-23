-- WeaponSelectPage.client.lua
-- Mercenary weapon picker reached from HandlingPage's MAIN HAND tile.
-- Exposes _G.OpenWeaponSelectPage(ctx) + _G.CloseWeaponSelectPage().
--
-- Step 2 scope (this file): holo scaffold + responsive 960×600
-- artboard + BACK button + centred 'SELECT WEAPON' title + the
-- viewport-cache handoff glue so closing the page detaches the
-- cached merc rig the same way HandlingPage / DNAStudyPage do.
--
-- Arsenal panel, weapon grid, detail card, EQUIP wiring and NEW
-- badge persistence land in Steps 3-12.
--
-- ctx fields (all optional unless marked):
--   screenGui             — ScreenGui to parent the page under (required)
--   mercName              — selected mercenary key (required)
--   theme                 — MERC_THEMES entry (displayName, role, etc.)
--   equipItems            — MercenariesMenu's EQUIP_ITEMS handoff (Weapons list)
--   hidePhonePanels       — phone-panel hide hook
--   detachCachedViewports — called on close so the rig survives
--                            the round-trip back to HandlingPage
--   buildMercViewport     — rig builder used by Step 3
--   onBack()              — called when BACK is pressed

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- ─── Palette (matches HandlingPage / DNAStudyPage amethyst-dark) ─────
local COLOR_TEXT              = Color3.fromRGB(220, 240, 255)
local COLOR_TEXT_DIM          = Color3.fromRGB(140, 180, 220)
local COLOR_TEXT_MUTE         = Color3.fromRGB(100, 125, 155)
local HOLO_PANEL_FILL         = Color3.fromRGB(10, 24, 44)
local HOLO_PANEL_TRANSPARENCY = 0.28
local HOLO_PANEL_BORDER       = Color3.fromRGB(75, 100, 125)
local HOLO_EDGE               = Color3.fromRGB(190, 220, 245)
local HORIZON                 = Color3.fromRGB(80, 140, 190)

local FONT_TITLE = Enum.Font.GothamBold
local FONT_BODY  = Enum.Font.Gotham

-- ─── Slanted-blade weapon glyph (ARSENAL header icon) ──────────────
-- Same recipe HandlingPage's MAIN HAND tile uses, scaled down. Thin
-- parallelogram blade with a small crossguard + pommel — reads as
-- "sword" at ~12-14 px without needing an image asset.
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

-- ─── Rarity star row (N small rotated-square stars) ───────────────
-- Mirrors HandlingPage / MercenariesMenu's makeStarRow so the rarity
-- visual stays in lock-step across every phone sub-page. Filled
-- stars render as solid rotated squares, empty as outlines.
local COLOR_GOLD = Color3.fromRGB(230, 190, 100)

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

-- ─── Padlock glyph (overlay for locked weapon cards) ────────────────
local function makeLockIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "LockIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

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

-- ─── BACK glyph (crossed diagonals — matches the other sub-pages) ────
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

-- ─── Artboard reference (matches HandlingPage / DNAStudyPage) ───────
local REFERENCE_W        = 960
local REFERENCE_H        = 600
local HORIZONTAL_PADDING = 80

-- ─── Module state ────────────────────────────────────────────────────
local activePage        = nil
local activeConnections = {}
-- Stashed across open/close so closeWeaponSelectPage can call
-- ctx.detachCachedViewports() before destroying the page — otherwise
-- Destroy would cascade into the cached merc ViewportFrame and the
-- idle animation would restart on the round-trip back to Handling.
local activeCtx         = nil

local function disconnectAll(tbl)
	for _, conn in ipairs(tbl) do conn:Disconnect() end
	table.clear(tbl)
end

-- ─── Holo backdrop ───────────────────────────────────────────────────
-- Same recipe as the other phone sub-pages: base vertical gradient,
-- two horizon glow bands, drifting motes. No occlusion list here —
-- Step 4 onward can add one if the arsenal / detail cards need the
-- motes dimmed behind them.
local function buildHoloBackground(parent)
	local BG_TOP   = Color3.fromRGB(18, 38, 66)
	local BG_MID   = Color3.fromRGB(28, 58, 92)
	local BG_BOT   = Color3.fromRGB(40, 80, 122)
	local MOTE_COL = Color3.fromRGB(205, 236, 255)

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
		g.Rotation = 90
		g.Parent = h
	end
	horizonLayer(1.6, 0.22, 0.90, 0.50)
	horizonLayer(1.0, 0.08, 0.72, 0.15)

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
local function closeWeaponSelectPage()
	disconnectAll(activeConnections)
	-- Detach the cached merc ViewportFrame FIRST so activePage:Destroy()
	-- below doesn't cascade into the rig and kill the idle animation
	-- tracks. MercenariesMenu's own detachCachedViewports repoints
	-- every cached vp.Parent to nil, leaving the cache entry intact so
	-- buildMercViewport can reparent it on the next open.
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
local function openWeaponSelectPage(ctx)
	ctx = ctx or {}
	local screenGui = ctx.screenGui
	if not screenGui then
		warn("[WeaponSelectPage] open called without ctx.screenGui")
		return
	end

	closeWeaponSelectPage()
	activeCtx = ctx

	local page = Instance.new("Frame")
	page.Name = "WeaponSelectPage"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ZIndex = 50
	page.Parent = screenGui
	activePage = page

	if ctx.hidePhonePanels then ctx.hidePhonePanels() end

	buildHoloBackground(page)

	-- Responsive 960×600 artboard (same math as HandlingPage /
	-- DNAStudyPage), centred on screen with a small downward shift
	-- so the content clears the Roblox chrome.
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

	local backBtnRef
	local BACK_BTN_Y = 10

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
	end

	-- ViewportSize listener — Roblox doesn't reliably fire
	-- AbsoluteSize changes on window resize, so follow the camera
	-- directly. Rehook on CurrentCamera swaps (respawn, etc.).
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

	-- ── BACK button (matches DNAStudyPage / HandlingPage style) ──────
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
		closeWeaponSelectPage()
		if ctx.onBack then ctx.onBack() end
	end)

	-- ── Centred title: "SELECT WEAPON" ──────────────────────────────
	-- Single label for the scaffold step; Step 4 onward can add a
	-- small weapon glyph or merc tag alongside if the design calls
	-- for one. Anchored to the artboard centre so the title follows
	-- the scale wrap, not the screen edge.
	local title = Instance.new("TextLabel")
	title.Name = "PageTitle"
	title.BackgroundTransparency = 1
	title.BorderSizePixel = 0
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, BACK_BTN_Y + 8)
	title.Size = UDim2.fromOffset(260, 22)
	title.Font = FONT_TITLE
	title.TextSize = 16
	title.TextColor3 = HOLO_EDGE
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Text = "SELECT WEAPON"
	title.ZIndex = 52
	title.Parent = scaleWrap

	-- ── Centre viewport ─────────────────────────────────────────────
	-- Host is positioned + sized identically to HandlingPage's
	-- viewportHost (400, 104, 160×472), so the cached rig lands at
	-- the exact same scaleWrap-local coords (centre Y = 264.48) and
	-- the Merc→Handling→WeaponSelect→Handling round-trip doesn't make
	-- the character jump. No clip frame here — no bottom cards need
	-- to crop the rig on this page, so the pirate renders fully.
	-- Per Q9 we don't add any "FOR · <MERC>" label — just the model.
	local equippedWeaponId = "Sword"
	local mercFolder = player:FindFirstChild("Mercenaries")
	if mercFolder and ctx.mercName then
		local entry = mercFolder:FindFirstChild(ctx.mercName)
		if entry then
			local eq = entry:GetAttribute("EquippedWeapon")
			if eq and eq ~= "" then equippedWeaponId = eq end
		end
	end

	local viewportHost = Instance.new("Frame")
	viewportHost.Name = "ViewportHost"
	viewportHost.BackgroundTransparency = 1
	viewportHost.BorderSizePixel = 0
	viewportHost.Position = UDim2.fromOffset(400, 104)
	viewportHost.Size = UDim2.fromOffset(160, 472)
	viewportHost.ZIndex = 55
	viewportHost.Parent = scaleWrap

	if ctx.buildMercViewport and ctx.mercName then
		local vp = ctx.buildMercViewport(viewportHost, ctx.mercName, equippedWeaponId)
		if vp then
			vp.ZIndex = 60 -- above future arsenal / detail panels
		end
	end

	-- ── Arsenal panel (left column) ─────────────────────────────────
	-- Holo card containing: [ARSENAL header + item counter] + [three
	-- profession filter tabs] + (grid area reserved for Step 6). Tab
	-- click currently just flips the active-visual state; wiring the
	-- filter rebuild lands in Step 7 once EQUIP_ITEMS carries the
	-- profession field (Step 5).
	local ARSENAL_X     = 40
	local ARSENAL_Y     = 60
	local ARSENAL_W     = 280
	local ARSENAL_H     = 510
	local ARSENAL_PAD_X = 14

	local arsenal = Instance.new("Frame")
	arsenal.Name = "ArsenalCard"
	arsenal.BackgroundColor3 = HOLO_PANEL_FILL
	arsenal.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	arsenal.BorderSizePixel = 0
	arsenal.Position = UDim2.fromOffset(ARSENAL_X, ARSENAL_Y)
	arsenal.Size = UDim2.fromOffset(ARSENAL_W, ARSENAL_H)
	arsenal.ZIndex = 52
	arsenal.Parent = scaleWrap
	local arsenalStroke = Instance.new("UIStroke")
	arsenalStroke.Color     = HOLO_PANEL_BORDER
	arsenalStroke.Thickness = 1
	arsenalStroke.Parent    = arsenal

	-- Header row: weapon glyph + 'ARSENAL' label (left) + 'N · ITEMS'
	-- counter (right). Count label ref stashed in arsenalCountLabel
	-- so Step 7 can overwrite it whenever the active filter changes.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.Position = UDim2.fromOffset(ARSENAL_PAD_X, 14)
	header.Size = UDim2.new(1, -ARSENAL_PAD_X * 2, 0, 18)
	header.ZIndex = 53
	header.Parent = arsenal

	local headerGlyph = makeWeaponIcon(header, 14, HOLO_EDGE)
	headerGlyph.AnchorPoint = Vector2.new(0, 0.5)
	headerGlyph.Position = UDim2.new(0, 0, 0.5, 0)
	headerGlyph.ZIndex = 54

	local headerLabel = Instance.new("TextLabel")
	headerLabel.BackgroundTransparency = 1
	headerLabel.BorderSizePixel = 0
	headerLabel.Position = UDim2.fromOffset(20, 0)
	headerLabel.Size = UDim2.new(1, -90, 1, 0)
	headerLabel.Font = FONT_TITLE
	headerLabel.TextSize = 13
	headerLabel.TextColor3 = COLOR_TEXT
	headerLabel.TextXAlignment = Enum.TextXAlignment.Left
	headerLabel.Text = "ARSENAL"
	headerLabel.ZIndex = 54
	headerLabel.Parent = header

	local arsenalCountLabel = Instance.new("TextLabel")
	arsenalCountLabel.Name = "ItemCount"
	arsenalCountLabel.BackgroundTransparency = 1
	arsenalCountLabel.BorderSizePixel = 0
	arsenalCountLabel.AnchorPoint = Vector2.new(1, 0.5)
	arsenalCountLabel.Position = UDim2.new(1, 0, 0.5, 0)
	arsenalCountLabel.Size = UDim2.fromOffset(80, 16)
	arsenalCountLabel.Font = FONT_TITLE
	arsenalCountLabel.TextSize = 11
	arsenalCountLabel.TextColor3 = COLOR_TEXT_DIM
	arsenalCountLabel.TextXAlignment = Enum.TextXAlignment.Right
	arsenalCountLabel.Text = "0 · ITEMS"
	arsenalCountLabel.ZIndex = 54
	arsenalCountLabel.Parent = header
	local _ = arsenalCountLabel -- Step 7 will overwrite Text on filter change

	-- ── Profession filter tabs (WARRIOR / FISHERMAN / ASSISTANT) ────
	-- Three equal-width pills below the header. One active at a time;
	-- default = Warrior per the plan. Only flips the visual state for
	-- now — grid rebuild wires up in Step 7.
	local TAB_ROW_Y   = 40
	local TAB_H       = 26
	local TAB_GAP     = 6
	local TAB_INNER_W = ARSENAL_W - ARSENAL_PAD_X * 2
	local TAB_W       = (TAB_INNER_W - TAB_GAP * 2) / 3

	local tabRow = Instance.new("Frame")
	tabRow.Name = "FilterTabs"
	tabRow.BackgroundTransparency = 1
	tabRow.BorderSizePixel = 0
	tabRow.Position = UDim2.fromOffset(ARSENAL_PAD_X, TAB_ROW_Y)
	tabRow.Size = UDim2.fromOffset(TAB_INNER_W, TAB_H)
	tabRow.ZIndex = 53
	tabRow.Parent = arsenal

	local TAB_FILL_SEL       = Color3.fromRGB(16, 42, 72)
	local TAB_FILL_SEL_ALPHA = 0.10
	local TAB_FILL_UNSEL     = HOLO_PANEL_FILL
	local TAB_FILL_UNSEL_ALPHA = 0.45
	local TAB_STROKE_SEL     = HOLO_EDGE
	local TAB_STROKE_UNSEL   = HOLO_PANEL_BORDER
	local TAB_TEXT_SEL       = Color3.fromRGB(230, 245, 255)
	local TAB_TEXT_UNSEL     = COLOR_TEXT_DIM

	local arsenalActiveProfession = "Warrior"
	local arsenalTabRefs = {}

	local function refreshTabVisuals()
		for profession, ref in pairs(arsenalTabRefs) do
			local selected = (profession == arsenalActiveProfession)
			if selected then
				ref.tile.BackgroundColor3 = TAB_FILL_SEL
				ref.tile.BackgroundTransparency = TAB_FILL_SEL_ALPHA
				ref.stroke.Color = TAB_STROKE_SEL
				ref.stroke.Thickness = 1.4
				ref.label.TextColor3 = TAB_TEXT_SEL
			else
				ref.tile.BackgroundColor3 = TAB_FILL_UNSEL
				ref.tile.BackgroundTransparency = TAB_FILL_UNSEL_ALPHA
				ref.stroke.Color = TAB_STROKE_UNSEL
				ref.stroke.Thickness = 1
				ref.label.TextColor3 = TAB_TEXT_UNSEL
			end
		end
	end

	local function buildTab(profession, displayText, index)
		local tile = Instance.new("TextButton")
		tile.Name = "Tab_" .. profession
		tile.AutoButtonColor = false
		tile.Text = ""
		tile.BorderSizePixel = 0
		tile.Position = UDim2.fromOffset((index - 1) * (TAB_W + TAB_GAP), 0)
		tile.Size = UDim2.fromOffset(TAB_W, TAB_H)
		tile.ZIndex = 54
		tile.Parent = tabRow
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = tile

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.Size = UDim2.fromScale(1, 1)
		label.Font = FONT_TITLE
		label.TextSize = 11
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Text = displayText
		label.ZIndex = 55
		label.Parent = tile

		arsenalTabRefs[profession] = { tile = tile, stroke = stroke, label = label }

		tile.MouseButton1Click:Connect(function()
			if arsenalActiveProfession == profession then return end
			arsenalActiveProfession = profession
			refreshTabVisuals()
			-- Step 7 will also rebuild the weapon grid here.
		end)
	end

	buildTab("Warrior",   "WARRIOR",   1)
	buildTab("Fisherman", "FISHERMAN", 2)
	buildTab("Assistant", "ASSISTANT", 3)
	refreshTabVisuals()

	-- ── Arsenal weapon grid (cards) ─────────────────────────────────
	-- 3-column grid under the filter tabs. One card per EQUIP_ITEMS
	-- .Weapons entry. Step 6 renders ALL weapons (no filter yet);
	-- Step 7 hooks the tabs so buildGrid gets called again with the
	-- active profession.
	local GRID_TOP      = 80
	local GRID_COLS     = 3
	local GRID_COL_GAP  = 6
	local GRID_ROW_GAP  = 6
	local CARD_H        = 96
	local CARD_W        = (TAB_INNER_W - GRID_COL_GAP * (GRID_COLS - 1)) / GRID_COLS

	-- Unlocked-weapon set: UnlockedEquipment folder children +
	-- anything already in Backpack / Character as a tool fallback.
	-- `alwaysUnlocked` flag on the def overrides both.
	local function collectUnlockedSet()
		local set = {}
		local eq = player:FindFirstChild("UnlockedEquipment")
		if eq then
			for _, child in eq:GetChildren() do
				set[child.Name] = true
			end
		end
		local bp = player:FindFirstChild("Backpack")
		if bp then
			for _, child in bp:GetChildren() do
				if child:IsA("Tool") then set[child.Name] = true end
			end
		end
		local char = player.Character
		if char then
			for _, child in char:GetChildren() do
				if child:IsA("Tool") then set[child.Name] = true end
			end
		end
		return set
	end

	-- Card-visual palette (local to the grid so the constants stay
	-- beside the buildCard body below).
	local CARD_FILL         = Color3.fromRGB(10, 24, 44)
	local CARD_FILL_ALPHA   = 0.30
	local CARD_STROKE       = HOLO_PANEL_BORDER
	local CARD_STROKE_SEL   = HOLO_EDGE
	local CHIP_FILL         = Color3.fromRGB(6, 16, 30)
	local CHIP_FILL_ALPHA   = 0.25
	local NEW_CHIP_COLOR    = Color3.fromRGB(230, 160,  70)
	local NEW_CHIP_TEXT     = Color3.fromRGB(255, 245, 220)
	local EQUIP_CHIP_COLOR  = Color3.fromRGB( 90, 190, 120)
	local EQUIP_CHIP_TEXT   = Color3.fromRGB(230, 255, 235)

	-- Placeholder: NEW-badge set. Step 12 replaces this with a
	-- DataStore-backed table of weapons the player has already
	-- clicked; for Step 6 everything the player owns counts as
	-- not-new so no NEW badges flash unless the step's commits land
	-- independently from 12.
	local seenWeapons = {}
	local function isNew(def, unlocked)
		if not unlocked then return false end
		return not seenWeapons[def.id]
	end

	-- Single weapon card. Returns a table of its named sub-refs so
	-- Step 10's selection + Step 11's equip-refresh can flip chip
	-- states without rebuilding the card.
	local function buildCard(def, col, row, unlocked, equipped)
		local x = (col - 1) * (CARD_W + GRID_COL_GAP)
		local y = GRID_TOP + (row - 1) * (CARD_H + GRID_ROW_GAP)

		local card = Instance.new("TextButton")
		card.Name = "Card_" .. def.id
		card.AutoButtonColor = false
		card.Text = ""
		card.BackgroundColor3 = CARD_FILL
		card.BackgroundTransparency = CARD_FILL_ALPHA
		card.BorderSizePixel = 0
		card.Position = UDim2.fromOffset(ARSENAL_PAD_X + x, y)
		card.Size = UDim2.fromOffset(CARD_W, CARD_H)
		card.ZIndex = 54
		card.Parent = arsenal

		local stroke = Instance.new("UIStroke")
		stroke.Color     = equipped and CARD_STROKE_SEL or CARD_STROKE
		stroke.Thickness = equipped and 1.4 or 1
		stroke.Parent    = card

		-- Level chip top-left. EQUIP_ITEMS has no per-weapon level
		-- mechanic yet, so every card reads 'Lv 1' for now; the chip
		-- will pull from def.level once that mechanic exists.
		local levelChip = Instance.new("Frame")
		levelChip.Name = "LevelChip"
		levelChip.BackgroundColor3 = CHIP_FILL
		levelChip.BackgroundTransparency = CHIP_FILL_ALPHA
		levelChip.BorderSizePixel = 0
		levelChip.Position = UDim2.fromOffset(4, 4)
		levelChip.Size = UDim2.fromOffset(28, 14)
		levelChip.ZIndex = 55
		levelChip.Parent = card
		local lvStroke = Instance.new("UIStroke")
		lvStroke.Color     = CARD_STROKE
		lvStroke.Thickness = 1
		lvStroke.Parent    = levelChip
		local lvLabel = Instance.new("TextLabel")
		lvLabel.BackgroundTransparency = 1
		lvLabel.BorderSizePixel = 0
		lvLabel.Size = UDim2.fromScale(1, 1)
		lvLabel.Font = FONT_TITLE
		lvLabel.TextSize = 10
		lvLabel.TextColor3 = COLOR_TEXT_DIM
		lvLabel.TextXAlignment = Enum.TextXAlignment.Center
		lvLabel.Text = string.format("Lv %d", def.level or 1)
		lvLabel.ZIndex = 56
		lvLabel.Parent = levelChip

		-- Icon area — big enough to read at the card size. Image
		-- asset if the def supplies one, otherwise the generic
		-- slanted-blade glyph as a placeholder.
		local ICON_BOX_SIZE = 40
		local iconBox = Instance.new("Frame")
		iconBox.Name = "IconBox"
		iconBox.BackgroundTransparency = 1
		iconBox.BorderSizePixel = 0
		iconBox.AnchorPoint = Vector2.new(0.5, 0)
		iconBox.Position = UDim2.new(0.5, 0, 0, 24)
		iconBox.Size = UDim2.fromOffset(ICON_BOX_SIZE, ICON_BOX_SIZE)
		iconBox.ZIndex = 55
		iconBox.Parent = card

		if def.icon and def.icon ~= "" then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.BorderSizePixel = 0
			img.Size = UDim2.fromScale(1, 1)
			img.Image = def.icon
			img.ScaleType = Enum.ScaleType.Fit
			img.ImageColor3 = Color3.new(1, 1, 1)
			img.ZIndex = 56
			img.Parent = iconBox
		else
			local glyph = makeWeaponIcon(iconBox, ICON_BOX_SIZE, HOLO_EDGE)
			glyph.AnchorPoint = Vector2.new(0.5, 0.5)
			glyph.Position = UDim2.fromScale(0.5, 0.5)
		end

		-- Rarity star row pinned to the bottom of the card.
		local stars = math.clamp(def.stars or 0, 0, 5)
		local starRow = makeStarRow(card, stars, 5, 8, COLOR_GOLD)
		starRow.Name = "Stars"
		starRow.AnchorPoint = Vector2.new(0.5, 1)
		starRow.Position = UDim2.new(0.5, 0, 1, -8)
		for _, d in starRow:GetDescendants() do
			if d:IsA("Frame") then d.ZIndex = 56 end
		end

		-- Top-right badge area. EQUIPPED chip wins over NEW; if
		-- neither applies we render nothing. Both chips sit at the
		-- same coords so the visual lines up no matter which shows.
		local badgeHolder = Instance.new("Frame")
		badgeHolder.Name = "BadgeHolder"
		badgeHolder.BackgroundTransparency = 1
		badgeHolder.BorderSizePixel = 0
		badgeHolder.AnchorPoint = Vector2.new(1, 0)
		badgeHolder.Position = UDim2.new(1, -4, 0, 4)
		badgeHolder.Size = UDim2.fromOffset(36, 14)
		badgeHolder.ZIndex = 55
		badgeHolder.Parent = card

		local function mkChip(text, fill, textColor)
			local chip = Instance.new("Frame")
			chip.Name = "Chip_" .. text
			chip.BackgroundColor3 = fill
			chip.BackgroundTransparency = 0
			chip.BorderSizePixel = 0
			chip.AnchorPoint = Vector2.new(1, 0)
			chip.Position = UDim2.new(1, 0, 0, 0)
			chip.Size = UDim2.fromOffset(#text <= 1 and 16 or 36, 14)
			chip.ZIndex = 55
			chip.Parent = badgeHolder
			local cc = Instance.new("UICorner")
			cc.CornerRadius = UDim.new(0, 2)
			cc.Parent = chip
			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.BorderSizePixel = 0
			lbl.Size = UDim2.fromScale(1, 1)
			lbl.Font = FONT_TITLE
			lbl.TextSize = 10
			lbl.TextColor3 = textColor
			lbl.TextXAlignment = Enum.TextXAlignment.Center
			lbl.Text = text
			lbl.ZIndex = 56
			lbl.Parent = chip
			return chip
		end

		local equippedChip, newChip
		if equipped then
			equippedChip = mkChip("E", EQUIP_CHIP_COLOR, EQUIP_CHIP_TEXT)
		elseif isNew(def, unlocked) then
			newChip = mkChip("NEW", NEW_CHIP_COLOR, NEW_CHIP_TEXT)
		end

		-- Lock treatment: dims the card contents + centres a small
		-- padlock glyph on top. Only applied when the weapon isn't
		-- in the unlocked set.
		local lockOverlay, lockIcon
		if not unlocked then
			lockOverlay = Instance.new("Frame")
			lockOverlay.Name = "LockOverlay"
			lockOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			lockOverlay.BackgroundTransparency = 0.35
			lockOverlay.BorderSizePixel = 0
			lockOverlay.Size = UDim2.fromScale(1, 1)
			lockOverlay.ZIndex = 57
			lockOverlay.Parent = card

			lockIcon = makeLockIcon(lockOverlay, 20, COLOR_TEXT_DIM)
			lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			lockIcon.Position = UDim2.fromScale(0.5, 0.5)
			for _, d in lockIcon:GetDescendants() do
				if d:IsA("Frame") then d.ZIndex = 58 end
			end
		end

		return {
			def          = def,
			card         = card,
			stroke       = stroke,
			levelChip    = levelChip,
			lvLabel      = lvLabel,
			iconBox      = iconBox,
			starRow      = starRow,
			badgeHolder  = badgeHolder,
			equippedChip = equippedChip,
			newChip      = newChip,
			lockOverlay  = lockOverlay,
			unlocked     = unlocked,
		}
	end

	-- Cached refs so Step 7 can destroy the old cards on re-filter,
	-- and Steps 10 / 11 can mutate chips in place without rebuilding.
	local weaponCardRefs = {}

	local function clearGrid()
		for _, ref in pairs(weaponCardRefs) do
			if ref.card then ref.card:Destroy() end
		end
		table.clear(weaponCardRefs)
	end

	local function buildGrid(profession)
		clearGrid()
		local weapons = ctx.equipItems and ctx.equipItems.Weapons or {}
		local unlockedSet = collectUnlockedSet()
		local visible = 0
		for _, def in ipairs(weapons) do
			-- Step 6 ignores `profession` and shows every weapon;
			-- Step 7 will filter here.
			local _ = profession
			local col = (visible % GRID_COLS) + 1
			local row = math.floor(visible / GRID_COLS) + 1
			local unlocked = def.alwaysUnlocked or unlockedSet[def.id] == true
			local equipped = (def.id == equippedWeaponId)
			weaponCardRefs[def.id] = buildCard(def, col, row, unlocked, equipped)
			visible = visible + 1
		end
		arsenalCountLabel.Text = string.format("%d · ITEMS", visible)
	end

	buildGrid(arsenalActiveProfession)

	updateResponsiveScale()

	-- Cleanup listeners when the page leaves the hierarchy (belt-and-
	-- suspenders: closeWeaponSelectPage already disconnects, but if
	-- something reparents activePage externally we catch it here too).
	table.insert(activeConnections, page.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			disconnectAll(activeConnections)
		end
	end))
end

_G.OpenWeaponSelectPage  = openWeaponSelectPage
_G.CloseWeaponSelectPage = closeWeaponSelectPage
