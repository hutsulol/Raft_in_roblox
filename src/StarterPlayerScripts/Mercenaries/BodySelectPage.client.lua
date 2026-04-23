-- BodySelectPage.client.lua
-- Mercenary backpack picker reached from HandlingPage's BODY tile.
-- Exposes _G.OpenBodySelectPage(ctx) + _G.CloseBodySelectPage().
--
-- Structurally a near-twin of WeaponSelectPage: same holo scaffold,
-- same centre viewport handoff, same arsenal-grid + detail-card +
-- EQUIP-button flow. Differences: pulls from EQUIP_ITEMS.Artifacts
-- instead of .Weapons, has no profession tabs (backpacks aren't
-- profession-specific), writes the merc's EquippedBackpack attribute
-- instead of EquippedBackpack, and displays Storage Slots as the
-- per-item primary stat (6 for basic, 9 for Lvl 2).
--
-- ctx fields (all optional unless marked):
--   screenGui             — ScreenGui to parent the page under (required)
--   mercName              — selected mercenary key (required)
--   theme                 — MERC_THEMES entry (displayName, role, etc.)
--   equipItems            — MercenariesMenu's EQUIP_ITEMS handoff (Artifacts list)
--   hidePhonePanels       — phone-panel hide hook
--   detachCachedViewports — called on close so the rig survives
--                            the round-trip back to HandlingPage
--   buildMercViewport     — rig builder used to hot-swap the backpack
--   onBack()              — called when BACK is pressed

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

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

-- ─── Backpack glyph (ARSENAL header icon + fallback) ────────────────
-- Same shape HandlingPage's BODY tile uses, scaled down. Rounded
-- satchel body + top flap + small front-pocket hint — reads as
-- "backpack" at ~12-14 px without needing an image asset. Used for
-- the arsenal header and as the fallback for any backpack def that
-- doesn't ship a rbxassetid icon.
local function makeBackpackIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "BackpackIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromScale(0.5, 0.92)
	body.Size = UDim2.fromOffset(size * 0.66, size * 0.60)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Parent = c
	local bodyCorner = Instance.new("UICorner")
	bodyCorner.CornerRadius = UDim.new(0, math.max(2, math.floor(size * 0.12)))
	bodyCorner.Parent = body
	local bodyStroke = Instance.new("UIStroke")
	bodyStroke.Color     = color
	bodyStroke.Thickness = 1.5
	bodyStroke.Parent    = body

	local flap = Instance.new("Frame")
	flap.AnchorPoint = Vector2.new(0.5, 1)
	flap.Position = UDim2.fromScale(0.5, 0.40)
	flap.Size = UDim2.fromOffset(size * 0.50, size * 0.18)
	flap.BackgroundTransparency = 1
	flap.BorderSizePixel = 0
	flap.Parent = c
	local flapCorner = Instance.new("UICorner")
	flapCorner.CornerRadius = UDim.new(0, math.max(2, math.floor(size * 0.08)))
	flapCorner.Parent = flap
	local flapStroke = Instance.new("UIStroke")
	flapStroke.Color     = color
	flapStroke.Thickness = 1.5
	flapStroke.Parent    = flap

	local pocket = Instance.new("Frame")
	pocket.AnchorPoint = Vector2.new(0.5, 0.5)
	pocket.Position = UDim2.fromScale(0.5, 0.68)
	pocket.Size = UDim2.fromOffset(size * 0.40, math.max(1, math.floor(size * 0.06)))
	pocket.BackgroundColor3 = color
	pocket.BackgroundTransparency = 0.25
	pocket.BorderSizePixel = 0
	pocket.Parent = c

	return c
end

-- ─── Rarity star row (image-asset stars, 4 total) ────────────────
-- Mirrors HandlingPage's makeImageStarRow so the rarity visual stays
-- in lock-step across every phone sub-page. `filled` can be fractional:
-- a boundary slot more than 25% of the way toward the next integer
-- renders as a half-star.
local COLOR_GOLD = Color3.fromRGB(230, 190, 100) -- retained for other
                                                 -- golden UI accents

local STAR_IMAGE_FULL  = "rbxassetid://128398990741410"
local STAR_IMAGE_EMPTY = "rbxassetid://96860361998800"
local STAR_IMAGE_HALF  = "rbxassetid://97995242534538"

local function makeStarRow(parent, filled, total, size)
	size   = size   or 12
	total  = total  or 4
	filled = math.clamp(tonumber(filled) or 0, 0, total)

	local gap = 2
	local c = Instance.new("Frame")
	c.Name = "StarRow"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(total * size + (total - 1) * gap, size)
	c.Parent = parent

	for i = 1, total do
		local assetId
		if filled >= i then
			assetId = STAR_IMAGE_FULL
		elseif (i - filled) < 0.75 then
			assetId = STAR_IMAGE_HALF
		else
			assetId = STAR_IMAGE_EMPTY
		end

		local star = Instance.new("ImageLabel")
		star.Name = "Star" .. i
		star.BackgroundTransparency = 1
		star.BorderSizePixel = 0
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.new(0, (i - 1) * (size + gap) + size * 0.5, 0.5, 0)
		star.Size = UDim2.fromOffset(size, size)
		star.Image = assetId
		star.ScaleType = Enum.ScaleType.Fit
		star.Parent = c
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
-- Stashed across open/close so closeBodySelectPage can call
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
local function closeBodySelectPage()
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
local function openBodySelectPage(ctx)
	ctx = ctx or {}
	local screenGui = ctx.screenGui
	if not screenGui then
		warn("[BodySelectPage] open called without ctx.screenGui")
		return
	end

	closeBodySelectPage()
	activeCtx = ctx

	local page = Instance.new("Frame")
	page.Name = "BodySelectPage"
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

	local function triggerBack()
		closeBodySelectPage()
		if ctx.onBack then ctx.onBack() end
	end
	backBtn.MouseButton1Click:Connect(triggerBack);
	(_G.AttachBackHotkey or function() end)(backBtn, triggerBack, {
		activeConnections = activeConnections,
		color             = COLOR_TEXT,
		haloColor         = HOLO_EDGE,
		fontTitle         = FONT_TITLE,
	})

	-- ── Centred title: "SELECT BACKPACK" ──────────────────────────────
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
	title.Text = "SELECT BACKPACK"
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
	-- We need both the current WEAPON (to preserve on viewport rebuilds)
	-- and the current BACKPACK (as the initial-selection in the grid +
	-- detail card). buildMercViewport takes a weapon id; the backpack
	-- visibility syncs from the merc's EquippedBackpack attribute which
	-- we mutate directly on equip.
	local equippedWeaponId   = "Sword"
	local equippedBackpackId = ""
	local mercFolder = player:FindFirstChild("Mercenaries")
	if mercFolder and ctx.mercName then
		local entry = mercFolder:FindFirstChild(ctx.mercName)
		if entry then
			local wep = entry:GetAttribute("EquippedBackpack")
			if wep and wep ~= "" then equippedWeaponId = wep end
			local bp = entry:GetAttribute("EquippedBackpack")
			if bp and bp ~= "" then equippedBackpackId = bp end
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

	local headerGlyph = makeBackpackIcon(header, 14, HOLO_EDGE)
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

	-- Body page has no profession tabs — Artifacts aren't profession-
	-- specific, so the arsenal panel shows every unlocked backpack in
	-- a single grid. We still need a TAB_INNER_W local for the card
	-- sizing math below so we don't have to retune all the widths.
	local TAB_INNER_W = ARSENAL_W - ARSENAL_PAD_X * 2

	-- Forward-declared so the click handlers reach it without caring
	-- about declaration order. Real implementation is assigned after
	-- the card helpers exist.
	local buildGrid

	-- Which item the detail card is currently previewing. Defaults to
	-- the equipped backpack so opening the page lands the player on
	-- "what am I wearing right now?". Falls back to the first id in the
	-- Artifacts list if no backpack is equipped yet.
	-- setSelectedCard + refreshDetailCard are assigned later; forward-
	-- declared so buildCard's click handler can invoke them.
	local selectedBackpackId = equippedBackpackId
	if selectedBackpackId == "" then
		local arts = ctx.equipItems and ctx.equipItems.Artifacts or {}
		if arts[1] and arts[1].id then
			selectedBackpackId = arts[1].id
		end
	end
	local setSelectedCard
	local refreshDetailCard

	-- ── Arsenal backpack grid (cards) ───────────────────────────────
	-- 3-column grid under the header. No profession tabs to clear so
	-- the grid starts closer to the top than WeaponSelectPage's.
	local GRID_TOP      = 52
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

	-- NEW-badge set, kept in sync with the WeaponSeenState DataStore
	-- (shared across WeaponSelect + BodySelect since it's item-id
	-- keyed; starter Backpack + starter Sword coexist in one table).
	-- Starter gear (alwaysUnlocked items) never shows NEW — those are
	-- default-equipped items, not discoveries. Anything the player
	-- has unlocked but hasn't clicked yet in this or a prior session
	-- gets the NEW chip.
	local seenWeapons = {}
	local seenEvent   = ReplicatedStorage:FindFirstChild("WeaponSeenState")
	local function isNew(def, unlocked)
		if not unlocked then return false end
		if def.alwaysUnlocked then return false end
		return not seenWeapons[def.id]
	end

	-- Pull the persisted seen set on page open. The grid is already
	-- built by the time the response fires, so on arrival we merge
	-- into the local table and rebuild the grid in place so any NEW
	-- chips stamped by the initial (empty) state disappear.
	if seenEvent then
		table.insert(activeConnections, seenEvent.OnClientEvent:Connect(function(action, payload)
			if action ~= "state" then return end
			if type(payload) ~= "table" then return end
			for weaponId, flag in pairs(payload) do
				if flag == true and type(weaponId) == "string" then
					seenWeapons[weaponId] = true
				end
			end
			if buildGrid then buildGrid() end
		end))
		seenEvent:FireServer("getState")
	end

	-- Flips a weapon to "seen" locally and tells the server. Safe to
	-- call on already-seen ids (early-outs).
	local function markWeaponSeen(weaponId)
		if not weaponId or weaponId == "" then return end
		if seenWeapons[weaponId] then return end
		seenWeapons[weaponId] = true
		if seenEvent then
			seenEvent:FireServer("markSeen", weaponId)
		end
	end

	-- Single weapon card. Returns a table of its named sub-refs so
	-- Step 10's selection + Step 11's equip-refresh can flip chip
	-- states without rebuilding the card.
	local function buildCard(def, col, row, unlocked, equipped, selected)
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

		-- Stroke tracks SELECTION (which card is previewed in the
		-- detail panel), not equipped state — the "E" chip marks the
		-- equipped card so both concerns stay independent.
		local stroke = Instance.new("UIStroke")
		stroke.Color     = selected and CARD_STROKE_SEL or CARD_STROKE
		stroke.Thickness = selected and 1.4 or 1
		stroke.Parent    = card

		-- Hover state: only brighten non-selected cards so the
		-- selected card's cyan stroke stays visually dominant. The
		-- hover color sits midway between the default border and the
		-- selection cyan so hovering doesn't mimic selection.
		local CARD_STROKE_HOVER = Color3.fromRGB(130, 170, 210)
		card.MouseEnter:Connect(function()
			if def.id == selectedBackpackId then return end
			stroke.Color = CARD_STROKE_HOVER
			stroke.Thickness = 1.2
		end)
		card.MouseLeave:Connect(function()
			if def.id == selectedBackpackId then return end
			stroke.Color = CARD_STROKE
			stroke.Thickness = 1
		end)

		card.MouseButton1Click:Connect(function()
			if setSelectedCard then setSelectedCard(def.id) end
		end)

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
			local glyph = makeBackpackIcon(iconBox, ICON_BOX_SIZE, HOLO_EDGE)
			glyph.AnchorPoint = Vector2.new(0.5, 0.5)
			glyph.Position = UDim2.fromScale(0.5, 0.5)
		end

		-- Rarity star row pinned to the bottom of the card.
		local stars = math.clamp(def.stars or 0, 0, 5)
		local starRow = makeStarRow(card, math.min(stars, 4), 4, 10)
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
	local itemCardRefs = {}

	local function clearGrid()
		for _, ref in pairs(itemCardRefs) do
			if ref.card then ref.card:Destroy() end
		end
		table.clear(itemCardRefs)
	end

	-- Assign the forward-declared upvalue. No profession filter —
	-- backpacks aren't profession-specific, so every Artifacts entry
	-- gets a card. Equipped status comes from equippedBackpackId so
	-- the "E" chip tracks the real world, not the weapon.
	buildGrid = function()
		clearGrid()
		local items = ctx.equipItems and ctx.equipItems.Artifacts or {}
		local unlockedSet = collectUnlockedSet()
		local visible = 0
		for _, def in ipairs(items) do
			local col = (visible % GRID_COLS) + 1
			local row = math.floor(visible / GRID_COLS) + 1
			local unlocked = def.alwaysUnlocked or unlockedSet[def.id] == true
			local equipped = (def.id == equippedBackpackId)
			local selected = (def.id == selectedBackpackId)
			itemCardRefs[def.id] = buildCard(def, col, row, unlocked, equipped, selected)
			visible = visible + 1
		end
		arsenalCountLabel.Text = string.format("%d · ITEMS", visible)
	end

	buildGrid()

	-- ── Detail card (right column) ──────────────────────────────────
	-- Mirrors the arsenal's geometry on the right edge. Shell is
	-- built once; its inner labels / icon / stars / stat rows are
	-- rewritten by refreshDetailCard(def). Step 8 paints it once
	-- with the currently-equipped weapon; Step 10 hooks grid card
	-- clicks to refreshDetailCard, and Step 11 wires the EQUIP
	-- button + viewport swap.
	local DETAIL_X     = REFERENCE_W - 40 - 280
	local DETAIL_Y     = 60
	local DETAIL_W     = 280
	local DETAIL_H     = 510
	local DETAIL_PAD_X = 14

	local detailCard = Instance.new("Frame")
	detailCard.Name = "DetailCard"
	detailCard.BackgroundColor3 = HOLO_PANEL_FILL
	detailCard.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	detailCard.BorderSizePixel = 0
	detailCard.Position = UDim2.fromOffset(DETAIL_X, DETAIL_Y)
	detailCard.Size = UDim2.fromOffset(DETAIL_W, DETAIL_H)
	detailCard.ZIndex = 52
	detailCard.Parent = scaleWrap
	local detailStroke = Instance.new("UIStroke")
	detailStroke.Color     = HOLO_PANEL_BORDER
	detailStroke.Thickness = 1
	detailStroke.Parent    = detailCard

	-- ── Header row: icon box + name / type / EQUIPPED chip ──────────
	local HEADER_TOP   = 14
	local ICON_SIZE    = 56
	local detailIconBox = Instance.new("Frame")
	detailIconBox.Name = "IconBox"
	detailIconBox.BackgroundColor3 = Color3.fromRGB(16, 34, 58)
	detailIconBox.BackgroundTransparency = 0.3
	detailIconBox.BorderSizePixel = 0
	detailIconBox.Position = UDim2.fromOffset(DETAIL_PAD_X, HEADER_TOP)
	detailIconBox.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	detailIconBox.ZIndex = 53
	detailIconBox.Parent = detailCard
	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color     = HOLO_PANEL_BORDER
	iconStroke.Thickness = 1
	iconStroke.Parent    = detailIconBox

	local headerTextX = DETAIL_PAD_X + ICON_SIZE + 12
	local detailName = Instance.new("TextLabel")
	detailName.Name = "WeaponName"
	detailName.BackgroundTransparency = 1
	detailName.BorderSizePixel = 0
	detailName.Position = UDim2.fromOffset(headerTextX, HEADER_TOP + 2)
	detailName.Size = UDim2.new(1, -(headerTextX + DETAIL_PAD_X), 0, 20)
	detailName.Font = FONT_TITLE
	detailName.TextSize = 17
	detailName.TextColor3 = COLOR_TEXT
	detailName.TextXAlignment = Enum.TextXAlignment.Left
	detailName.Text = "—"
	detailName.ZIndex = 53
	detailName.Parent = detailCard

	local detailType = Instance.new("TextLabel")
	detailType.Name = "WeaponType"
	detailType.BackgroundTransparency = 1
	detailType.BorderSizePixel = 0
	detailType.Position = UDim2.fromOffset(headerTextX, HEADER_TOP + 24)
	detailType.Size = UDim2.fromOffset(120, 16)
	detailType.Font = FONT_BODY
	detailType.TextSize = 12
	detailType.TextColor3 = COLOR_TEXT_DIM
	detailType.TextXAlignment = Enum.TextXAlignment.Left
	detailType.Text = "—"
	detailType.ZIndex = 53
	detailType.Parent = detailCard

	-- EQUIPPED chip in the header — shown only when the currently
	-- selected weapon is the one actually equipped on the merc.
	local detailEquippedChip = Instance.new("Frame")
	detailEquippedChip.Name = "EquippedChip"
	detailEquippedChip.BackgroundColor3 = Color3.fromRGB(40, 74, 50)
	detailEquippedChip.BackgroundTransparency = 0.15
	detailEquippedChip.BorderSizePixel = 0
	detailEquippedChip.Position = UDim2.fromOffset(headerTextX, HEADER_TOP + 42)
	detailEquippedChip.Size = UDim2.fromOffset(64, 14)
	detailEquippedChip.Visible = false
	detailEquippedChip.ZIndex = 53
	detailEquippedChip.Parent = detailCard
	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = UDim.new(0, 2)
	chipCorner.Parent = detailEquippedChip
	local chipStroke = Instance.new("UIStroke")
	chipStroke.Color     = Color3.fromRGB(90, 190, 120)
	chipStroke.Thickness = 1
	chipStroke.Parent    = detailEquippedChip
	local chipLabel = Instance.new("TextLabel")
	chipLabel.BackgroundTransparency = 1
	chipLabel.BorderSizePixel = 0
	chipLabel.Size = UDim2.fromScale(1, 1)
	chipLabel.Font = FONT_TITLE
	chipLabel.TextSize = 10
	chipLabel.TextColor3 = Color3.fromRGB(200, 240, 210)
	chipLabel.TextXAlignment = Enum.TextXAlignment.Center
	chipLabel.Text = "EQUIPPED"
	chipLabel.ZIndex = 54
	chipLabel.Parent = detailEquippedChip

	-- Hairline divider below the header.
	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = HOLO_PANEL_BORDER
	divider.BackgroundTransparency = 0.35
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromOffset(DETAIL_PAD_X, HEADER_TOP + ICON_SIZE + 10)
	divider.Size = UDim2.new(1, -DETAIL_PAD_X * 2, 0, 1)
	divider.ZIndex = 53
	divider.Parent = detailCard

	-- ── Primary stat row (Base Attack / Fishing Speed / Extraction Speed)
	-- Label on top, big numeric value on the left, and a dim speed-bonus
	-- chip on the right when the weapon's stat scales with merc speed.
	-- Profession decides the label + which base field we read from the
	-- def; refreshDetailCard writes the actual text.
	local STAT_ROW_H = 58
	local detailStatRow = Instance.new("Frame")
	detailStatRow.Name = "StatRow"
	detailStatRow.BackgroundTransparency = 1
	detailStatRow.BorderSizePixel = 0
	detailStatRow.Position = UDim2.fromOffset(DETAIL_PAD_X, HEADER_TOP + ICON_SIZE + 20)
	detailStatRow.Size = UDim2.new(1, -DETAIL_PAD_X * 2, 0, STAT_ROW_H)
	detailStatRow.ZIndex = 53
	detailStatRow.Parent = detailCard

	local statLabel = Instance.new("TextLabel")
	statLabel.Name = "StatLabel"
	statLabel.BackgroundTransparency = 1
	statLabel.BorderSizePixel = 0
	statLabel.Position = UDim2.fromOffset(0, 0)
	statLabel.Size = UDim2.new(1, 0, 0, 14)
	statLabel.Font = FONT_BODY
	statLabel.TextSize = 11
	statLabel.TextColor3 = COLOR_TEXT_DIM
	statLabel.TextXAlignment = Enum.TextXAlignment.Left
	statLabel.Text = "BASE ATTACK"
	statLabel.ZIndex = 54
	statLabel.Parent = detailStatRow

	local statValue = Instance.new("TextLabel")
	statValue.Name = "StatValue"
	statValue.BackgroundTransparency = 1
	statValue.BorderSizePixel = 0
	statValue.Position = UDim2.fromOffset(0, 16)
	statValue.Size = UDim2.new(0.5, 0, 0, 30)
	statValue.Font = FONT_TITLE
	statValue.TextSize = 24
	statValue.TextColor3 = COLOR_TEXT
	statValue.TextXAlignment = Enum.TextXAlignment.Left
	statValue.TextYAlignment = Enum.TextYAlignment.Center
	statValue.Text = "0"
	statValue.ZIndex = 54
	statValue.Parent = detailStatRow

	local statBonus = Instance.new("TextLabel")
	statBonus.Name = "StatBonus"
	statBonus.BackgroundTransparency = 1
	statBonus.BorderSizePixel = 0
	statBonus.AnchorPoint = Vector2.new(1, 0.5)
	statBonus.Position = UDim2.new(1, 0, 0, 31)
	statBonus.Size = UDim2.fromOffset(130, 14)
	statBonus.Font = FONT_BODY
	statBonus.TextSize = 11
	statBonus.TextColor3 = Color3.fromRGB(150, 210, 235)
	statBonus.TextXAlignment = Enum.TextXAlignment.Right
	statBonus.Text = ""
	statBonus.Visible = false
	statBonus.ZIndex = 54
	statBonus.Parent = detailStatRow

	-- Mini progress bar under the value so the number has visual
	-- weight even when values are small. Fill ratio = value / cap;
	-- cap varies by stat type so fishing/extraction bars aren't
	-- crushed by the higher Base-Attack scale.
	local statBarTrack = Instance.new("Frame")
	statBarTrack.Name = "StatBar"
	statBarTrack.BackgroundColor3 = Color3.fromRGB(24, 40, 62)
	statBarTrack.BackgroundTransparency = 0.2
	statBarTrack.BorderSizePixel = 0
	statBarTrack.Position = UDim2.fromOffset(0, 49)
	statBarTrack.Size = UDim2.new(1, 0, 0, 4)
	statBarTrack.ZIndex = 54
	statBarTrack.Parent = detailStatRow
	local statBarCorner = Instance.new("UICorner")
	statBarCorner.CornerRadius = UDim.new(1, 0)
	statBarCorner.Parent = statBarTrack

	local statBarFill = Instance.new("Frame")
	statBarFill.Name = "Fill"
	statBarFill.BackgroundColor3 = HOLO_EDGE
	statBarFill.BorderSizePixel = 0
	statBarFill.Size = UDim2.new(0, 0, 1, 0)
	statBarFill.ZIndex = 55
	statBarFill.Parent = statBarTrack
	local statBarFillCorner = Instance.new("UICorner")
	statBarFillCorner.CornerRadius = UDim.new(1, 0)
	statBarFillCorner.Parent = statBarFill

	-- ── Star row + level line ───────────────────────────────────────
	-- Star row gets rebuilt on every refresh (so the filled count
	-- tracks def.stars), so we keep a parent Frame with a constant
	-- position and destroy the previous stars before drawing new.
	local STATS_BOTTOM = HEADER_TOP + ICON_SIZE + 20 + STAT_ROW_H
	local detailStarsRow = Instance.new("Frame")
	detailStarsRow.Name = "StarsRow"
	detailStarsRow.BackgroundTransparency = 1
	detailStarsRow.BorderSizePixel = 0
	detailStarsRow.Position = UDim2.fromOffset(DETAIL_PAD_X, STATS_BOTTOM + 8)
	detailStarsRow.Size = UDim2.new(1, -DETAIL_PAD_X * 2, 0, 16)
	detailStarsRow.ZIndex = 53
	detailStarsRow.Parent = detailCard

	local detailLevelLabel = Instance.new("TextLabel")
	detailLevelLabel.Name = "LevelLine"
	detailLevelLabel.BackgroundTransparency = 1
	detailLevelLabel.BorderSizePixel = 0
	detailLevelLabel.Position = UDim2.fromOffset(DETAIL_PAD_X, STATS_BOTTOM + 28)
	detailLevelLabel.Size = UDim2.new(1, -DETAIL_PAD_X * 2, 0, 18)
	detailLevelLabel.Font = FONT_TITLE
	detailLevelLabel.TextSize = 12
	detailLevelLabel.TextColor3 = HOLO_EDGE
	detailLevelLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLevelLabel.Text = "Lv 1"
	detailLevelLabel.ZIndex = 53
	detailLevelLabel.Parent = detailCard

	-- ── Description / flavor text ───────────────────────────────────
	-- Word-wrapped body copy pulled from def.description. No ability
	-- block above it per Q7.
	local detailDescription = Instance.new("TextLabel")
	detailDescription.Name = "Description"
	detailDescription.BackgroundTransparency = 1
	detailDescription.BorderSizePixel = 0
	detailDescription.Position = UDim2.fromOffset(DETAIL_PAD_X, STATS_BOTTOM + 58)
	detailDescription.Size = UDim2.new(1, -DETAIL_PAD_X * 2, 0, 200)
	detailDescription.Font = FONT_BODY
	detailDescription.TextSize = 12
	detailDescription.TextColor3 = COLOR_TEXT_DIM
	detailDescription.TextXAlignment = Enum.TextXAlignment.Left
	detailDescription.TextYAlignment = Enum.TextYAlignment.Top
	detailDescription.TextWrapped = true
	detailDescription.Text = ""
	detailDescription.ZIndex = 53
	detailDescription.Parent = detailCard

	-- ── EQUIP button pinned to the bottom ───────────────────────────
	-- Renders one of three visual states:
	--   equipped → solid green outline 'EQUIPPED' label, not clickable.
	--   unlocked → active cyan-fill 'EQUIP' button.
	--   locked   → dim grey 'LOCKED' label, not clickable.
	-- Step 11 wires the click + viewport swap.
	local detailEquipButton = Instance.new("TextButton")
	detailEquipButton.Name = "EquipButton"
	detailEquipButton.AutoButtonColor = false
	detailEquipButton.Text = ""
	detailEquipButton.BackgroundColor3 = Color3.fromRGB(24, 56, 96)
	detailEquipButton.BackgroundTransparency = 0
	detailEquipButton.BorderSizePixel = 0
	detailEquipButton.AnchorPoint = Vector2.new(0, 1)
	detailEquipButton.Position = UDim2.new(0, DETAIL_PAD_X, 1, -DETAIL_PAD_X)
	detailEquipButton.Size = UDim2.new(1, -DETAIL_PAD_X * 2, 0, 38)
	detailEquipButton.ZIndex = 53
	detailEquipButton.Parent = detailCard
	local eqStroke = Instance.new("UIStroke")
	eqStroke.Color     = HOLO_EDGE
	eqStroke.Thickness = 1.2
	eqStroke.Parent    = detailEquipButton
	local eqLabel = Instance.new("TextLabel")
	eqLabel.Name = "Label"
	eqLabel.BackgroundTransparency = 1
	eqLabel.BorderSizePixel = 0
	eqLabel.Size = UDim2.fromScale(1, 1)
	eqLabel.Font = FONT_TITLE
	eqLabel.TextSize = 15
	eqLabel.TextColor3 = COLOR_TEXT
	eqLabel.TextXAlignment = Enum.TextXAlignment.Center
	eqLabel.Text = "EQUIP"
	eqLabel.ZIndex = 54
	eqLabel.Parent = detailEquipButton

	-- ── Detail refresh: paints the card from a weapon def ───────────
	local function findItemDef(weaponId)
		local weapons = ctx.equipItems and ctx.equipItems.Artifacts or {}
		for _, def in ipairs(weapons) do
			if def.id == weaponId then return def end
		end
		return nil
	end

	local function isItemUnlocked(def, unlockedSet)
		if not def then return false end
		if def.alwaysUnlocked then return true end
		unlockedSet = unlockedSet or collectUnlockedSet()
		return unlockedSet[def.id] == true
	end

-- Per-item backpack slot counts. Matches the server-side
	-- BACKPACK_SLOT_COUNTS table in MercenaryMovement / HarvestResources
	-- so the number the UI shows is the real storage capacity used at
	-- runtime. Anything not listed falls back to 0 slots.
	local BACKPACK_SLOTS = {
		Backpack      = 6,
		BackPack_lvl2 = 9,
	}

	local function getBackpackSlots(def)
		if not def then return 0 end
		if tonumber(def.slotCount) then return tonumber(def.slotCount) end
		return BACKPACK_SLOTS[def.id] or 0
	end

	-- Cap for the mini progress bar: twice the best slot count we know
	-- about, so the current top-tier still leaves room for future
	-- Lvl 3 / Lvl 4 backpacks without the bar slamming to 100%.
	local SLOT_BAR_CAP = 18

	refreshDetailCard = function(def)
		if not def then
			detailName.Text = "—"
			detailType.Text = "—"
			detailDescription.Text = ""
			detailEquippedChip.Visible = false
			statLabel.Text = "—"
			statValue.Text = "0"
			statBonus.Visible = false
			statBarFill.Size = UDim2.new(0, 0, 1, 0)
			for _, child in detailIconBox:GetChildren() do
				if child:IsA("GuiObject") then child:Destroy() end
			end
			for _, child in detailStarsRow:GetChildren() do
				if child:IsA("GuiObject") then child:Destroy() end
			end
			return
		end

		detailName.Text = def.displayName or def.id or "—"
		detailType.Text = string.upper(def.typeName or "")

		local unlocked = isItemUnlocked(def)
		local equipped = (def.id == equippedBackpackId)
		detailEquippedChip.Visible = equipped

		-- Swap icon box content.
		for _, child in detailIconBox:GetChildren() do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		if def.icon and def.icon ~= "" then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.BorderSizePixel = 0
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.fromScale(0.5, 0.5)
			img.Size = UDim2.fromOffset(ICON_SIZE - 12, ICON_SIZE - 12)
			img.Image = def.icon
			img.ScaleType = Enum.ScaleType.Fit
			img.ImageColor3 = Color3.new(1, 1, 1)
			img.ZIndex = 54
			img.Parent = detailIconBox
		else
			local glyph = makeBackpackIcon(detailIconBox, ICON_SIZE - 12, HOLO_EDGE)
			glyph.AnchorPoint = Vector2.new(0.5, 0.5)
			glyph.Position = UDim2.fromScale(0.5, 0.5)
			glyph.ZIndex = 54
		end

		-- Stat row — Storage Slots. Flat stat (doesn't scale with merc
		-- speed), so the bonus chip stays hidden. Bar ratio is the slot
		-- count against SLOT_BAR_CAP so future larger backpacks have
		-- headroom before the bar saturates.
		local slots = getBackpackSlots(def)
		statLabel.Text = "STORAGE SLOTS"
		statValue.Text = string.format("%d", slots)
		statBonus.Visible = false
		local ratio = (SLOT_BAR_CAP > 0) and math.clamp(slots / SLOT_BAR_CAP, 0, 1) or 0
		statBarFill.Size = UDim2.new(ratio, 0, 1, 0)
		statBarFill.BackgroundColor3 = HOLO_EDGE

		-- Star row — destroy the old and draw fresh.
		for _, child in detailStarsRow:GetChildren() do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		local stars = makeStarRow(detailStarsRow, math.min(def.stars or 0, 4), 4, 13)
		stars.AnchorPoint = Vector2.new(0, 0.5)
		stars.Position = UDim2.new(0, 0, 0.5, 0)
		stars.ZIndex = 54

		-- Level line placeholder (real weapon-leveling comes later).
		detailLevelLabel.Text = string.format("Lv %d", def.level or 1)

		detailDescription.Text = def.description or ""

		-- EQUIP button state.
		if not unlocked then
			detailEquipButton.BackgroundColor3 = Color3.fromRGB(28, 34, 46)
			detailEquipButton.Active = false
			detailEquipButton.AutoButtonColor = false
			eqStroke.Color = HOLO_PANEL_BORDER
			eqLabel.Text = "LOCKED"
			eqLabel.TextColor3 = COLOR_TEXT_MUTE
		elseif equipped then
			detailEquipButton.BackgroundColor3 = Color3.fromRGB(32, 64, 46)
			detailEquipButton.Active = false
			detailEquipButton.AutoButtonColor = false
			eqStroke.Color = Color3.fromRGB(90, 190, 120)
			eqLabel.Text = "EQUIPPED"
			eqLabel.TextColor3 = Color3.fromRGB(200, 240, 210)
		else
			detailEquipButton.BackgroundColor3 = Color3.fromRGB(24, 56, 96)
			detailEquipButton.Active = true
			detailEquipButton.AutoButtonColor = true
			eqStroke.Color = HOLO_EDGE
			eqLabel.Text = "EQUIP"
			eqLabel.TextColor3 = COLOR_TEXT
		end
	end

	-- Clicking a card preselects that weapon: flip the old highlight
	-- off, flip the new one on, and repaint the detail panel. No-op
	-- if the clicked card is already selected.
	setSelectedCard = function(weaponId)
		local def = findItemDef(weaponId)
		if not def then return end
		if selectedBackpackId == weaponId then
			-- Even a re-click on the same card should dismiss its NEW
			-- chip — the user has clearly seen it.
			local ref = itemCardRefs[weaponId]
			if ref and ref.newChip then
				ref.newChip:Destroy()
				ref.newChip = nil
				markWeaponSeen(weaponId)
			end
			return
		end

		local prevRef = itemCardRefs[selectedBackpackId]
		if prevRef and prevRef.stroke then
			prevRef.stroke.Color     = CARD_STROKE
			prevRef.stroke.Thickness = 1
		end

		selectedBackpackId = weaponId

		local newRef = itemCardRefs[weaponId]
		if newRef and newRef.stroke then
			newRef.stroke.Color     = CARD_STROKE_SEL
			newRef.stroke.Thickness = 1.4
		end
		-- Strip the NEW chip off the just-clicked card so the player
		-- gets instant feedback even before the server round-trip.
		if newRef and newRef.newChip then
			newRef.newChip:Destroy()
			newRef.newChip = nil
		end
		markWeaponSeen(weaponId)

		refreshDetailCard(def)
	end

	-- ── EQUIP button wiring ─────────────────────────────────────────
	-- Mirrors the MercenariesMenu Equipment page: fires the remote,
	-- optimistically flips the merc's EquippedBackpack attribute, plays
	-- the per-weapon equip SFX, hot-swaps the viewport rig's tool via
	-- ctx.buildMercViewport (cache-hit path), then rebuilds the grid
	-- + repaints the detail card so the "E" chip and button state
	-- track the new equipped weapon.
	local equipEvent = ReplicatedStorage:FindFirstChild("MercenaryEquipment")
	-- MercenariesMenu currently only ships one backpack equip SFX —
	-- both tiers play the same cue. Keyed by id so we can add tier-
	-- specific sounds later without touching the handler.
	local EQUIP_SOUND_BY_BACKPACK = {
		Backpack      = "backpack_equip",
		BackPack_lvl2 = "backpack_equip",
	}

	detailEquipButton.MouseButton1Click:Connect(function()
		-- Guard rails: no-op if nothing picked, already equipped, or
		-- the backpack is still locked. The detail button's visual
		-- state already reflects these, but the click is still callable
		-- because TextButton.Active is advisory for rendering only.
		if not selectedBackpackId or selectedBackpackId == "" then return end
		if selectedBackpackId == equippedBackpackId then return end
		local def = findItemDef(selectedBackpackId)
		if not def then return end
		if not isItemUnlocked(def) then return end

		if equipEvent then
			equipEvent:FireServer("equip", ctx.mercName, selectedBackpackId)
		end

		local mercFolder = player:FindFirstChild("Mercenaries")
		local mercEntry  = mercFolder and mercFolder:FindFirstChild(ctx.mercName)
		if mercEntry then
			mercEntry:SetAttribute("EquippedBackpack", selectedBackpackId)
		end

		local soundName = EQUIP_SOUND_BY_BACKPACK[selectedBackpackId]
		if soundName then
			local equipSoundsFolder = SoundService:FindFirstChild("Items_equip")
			local snd = equipSoundsFolder and equipSoundsFolder:FindFirstChild(soundName)
			if snd then snd:Play() end
		end

		equippedBackpackId = selectedBackpackId

		-- Reuse the cached merc viewport. The weapon id is unchanged
		-- (we're only touching the backpack), so buildMercViewport's
		-- cache hit path skips applyWeaponToClone and runs
		-- syncBackpackVisibility — which reads the EquippedBackpack
		-- attribute we just set and flips the right backpack mesh on.
		if ctx.buildMercViewport and ctx.mercName then
			local vp = ctx.buildMercViewport(viewportHost, ctx.mercName, equippedWeaponId)
			if vp then vp.ZIndex = 60 end
		end

		-- Rebuild the grid so the "E" chip moves to the new card.
		-- selectedBackpackId now == equippedBackpackId so the same card
		-- also keeps the selection stroke.
		buildGrid()
		refreshDetailCard(def)
	end)

	-- Initial paint — selectedBackpackId was seeded at page-open to the
	-- currently-equipped backpack (or the first entry if none), so this
	-- just fills the detail panel to match whatever buildGrid already
	-- highlighted.
	refreshDetailCard(findItemDef(selectedBackpackId))

	updateResponsiveScale()

	-- Cleanup listeners when the page leaves the hierarchy (belt-and-
	-- suspenders: closeBodySelectPage already disconnects, but if
	-- something reparents activePage externally we catch it here too).
	table.insert(activeConnections, page.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			disconnectAll(activeConnections)
		end
	end))
end

_G.OpenBodySelectPage  = openBodySelectPage
_G.CloseBodySelectPage = closeBodySelectPage
