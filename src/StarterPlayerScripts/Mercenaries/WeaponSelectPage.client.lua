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
