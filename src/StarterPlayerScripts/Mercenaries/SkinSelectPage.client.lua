-- SkinSelectPage.client.lua
-- Wardrobe / skin picker reached from HandlingPage's SKINS tile.
-- Exposes _G.OpenSkinSelectPage(ctx) + _G.CloseSkinSelectPage().
--
-- Three columns laid out on the shared 960×600 holo artboard:
--   ┌── BACK ── SELECT SKIN ─────────────────────── FOR · <MERC> ─┐
--   │ [WARDROBE]   N/M OWNED                                       │
--   │  ALL  OWNED  SEA  CREW  FESTIVE                              │
--   │  ┌──┐ ┌──┐ ┌──┐                                              │
--   │  │  │ │  │ │  │            ┌── viewport ──┐  ┌── detail ──┐ │
--   │  └──┘ └──┘ └──┘            │   Pirate     │  │  name + ★   │ │
--   │  ...                       │              │  │  PALETTE    │ │
--   │                            └──────────────┘  │  SOURCE     │ │
--   │                                              │  desc       │ │
--   │                                              │  [ WORN ]   │ │
--   └──────────────────────────────────────────────┴─────────────┘
--
-- Server is the source of truth. The page asks for a snapshot on open
-- ("getState"), repaints whenever the server pushes a new "state", and
-- fires "equip" on WORN-button click. The server validates the skin
-- exists in catalog + is unlocked for this player before persisting.
--
-- ctx fields (mirror WeaponSelectPage / BodySelectPage):
--   screenGui             — required
--   mercName              — required
--   theme                 — MERC_THEMES entry (displayName, role, etc.)
--   hidePhonePanels       — phone-panel hide hook
--   detachCachedViewports — called on close so the cached merc rig survives
--   buildMercViewport     — rig builder for the centre viewport
--   resolveMercWeapon     — used so the centre viewport renders the merc
--                            holding the right weapon
--   onBack()              — invoked when BACK is pressed

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- ─── Palette (matches WeaponSelectPage / HandlingPage holo theme) ────
local COLOR_TEXT              = Color3.fromRGB(220, 240, 255)
local COLOR_TEXT_DIM          = Color3.fromRGB(140, 180, 220)
local COLOR_TEXT_MUTE         = Color3.fromRGB(100, 125, 155)
local HOLO_PANEL_FILL         = Color3.fromRGB(10, 24, 44)
local HOLO_PANEL_TRANSPARENCY = 0.28
local HOLO_PANEL_BORDER       = Color3.fromRGB(75, 100, 125)
local HOLO_EDGE               = Color3.fromRGB(190, 220, 245)
local CHIP_FILL               = Color3.fromRGB(6, 16, 30)
local CHIP_FILL_ALPHA         = 0.25
local EQUIP_GREEN             = Color3.fromRGB(90, 190, 120)
local EQUIP_GREEN_TEXT        = Color3.fromRGB(230, 255, 235)
local LOCK_GREY               = Color3.fromRGB(100, 110, 130)

local FONT_TITLE = Enum.Font.GothamBold
local FONT_BODY  = Enum.Font.Gotham

-- ─── Star assets (shared across pages) ───────────────────────────────
local STAR_IMAGE_FULL  = "rbxassetid://128398990741410"
local STAR_IMAGE_EMPTY = "rbxassetid://96860361998800"

local REFERENCE_W        = 960
local REFERENCE_H        = 600
local HORIZONTAL_PADDING = 80

-- Active state
local activePage        = nil
local activeConnections = {}
local activeCtx         = nil

-- Repaint state — held outside the open closure so the snapshot
-- handler can reach it.
local catalogById       = {}     -- { id = def, ... } from server snapshot
local ownedSet          = {}     -- { id = true }
local equippedByMerc    = {}     -- { mercName = id }

local function disconnectAll(tbl)
	for _, c in tbl do
		pcall(function() c:Disconnect() end)
	end
	table.clear(tbl)
end

-- Convert "#RRGGBB" → Color3. Strips a leading "#" and parses three pairs.
-- Falls back to a neutral grey if the input isn't a 6-digit hex.
local function hexToColor3(hex)
	if typeof(hex) ~= "string" then return COLOR_TEXT_DIM end
	local h = hex:gsub("^#", "")
	if #h ~= 6 then return COLOR_TEXT_DIM end
	local r = tonumber(h:sub(1, 2), 16)
	local g = tonumber(h:sub(3, 4), 16)
	local b = tonumber(h:sub(5, 6), 16)
	if not (r and g and b) then return COLOR_TEXT_DIM end
	return Color3.fromRGB(r, g, b)
end

-- ─── Star row (image-asset stars, 4 total) ──────────────────────────
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
		local s = Instance.new("ImageLabel")
		s.BackgroundTransparency = 1
		s.BorderSizePixel = 0
		s.Position = UDim2.fromOffset((i - 1) * (size + gap), 0)
		s.Size = UDim2.fromOffset(size, size)
		s.Image = (i <= filled) and STAR_IMAGE_FULL or STAR_IMAGE_EMPTY
		s.ZIndex = (parent.ZIndex or 1) + 1
		s.Parent = c
	end
	return c
end

-- ─── Chevron-back glyph (matches WeaponSelectPage's BACK button) ────
local function makeBackIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "BackIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local bar1 = Instance.new("Frame")
	bar1.AnchorPoint = Vector2.new(0.5, 0.5)
	bar1.Position = UDim2.fromScale(0.5, 0.32)
	bar1.Size = UDim2.fromOffset(size * 0.8, 1.6)
	bar1.BackgroundColor3 = color
	bar1.BorderSizePixel = 0
	bar1.Rotation = -45
	bar1.Parent = c

	local bar2 = Instance.new("Frame")
	bar2.AnchorPoint = Vector2.new(0.5, 0.5)
	bar2.Position = UDim2.fromScale(0.5, 0.68)
	bar2.Size = UDim2.fromOffset(size * 0.8, 1.6)
	bar2.BackgroundColor3 = color
	bar2.BorderSizePixel = 0
	bar2.Rotation = 45
	bar2.Parent = c
	return c
end

-- ─── Filter-tab bar (ALL / OWNED / SEA / CREW / FESTIVE) ────────────
local FILTER_DEFS = {
	{ id = "ALL",     label = "ALL"     },
	{ id = "OWNED",   label = "OWNED"   },
	{ id = "SEA",     label = "SEA"     },
	{ id = "CREW",    label = "CREW"    },
	{ id = "FESTIVE", label = "FESTIVE" },
}

local function entryMatchesFilter(def, filterId, isOwned)
	if filterId == "ALL"   then return true end
	if filterId == "OWNED" then return isOwned == true end
	-- Category filter: match case-insensitively.
	local cat = string.upper(def.category or "")
	return cat == filterId
end

-- Collect every catalog entry for the given merc, sorted as the server
-- catalog returned them. Stable across pushes so the grid doesn't
-- reshuffle when "OWNED" toggles.
local function catalogForMerc(mercName)
	local out = {}
	for _, def in pairs(catalogById) do
		if def.mercName == mercName then
			table.insert(out, def)
		end
	end
	table.sort(out, function(a, b)
		if a.rarity ~= b.rarity then return (a.rarity or 0) < (b.rarity or 0) end
		return (a.displayName or a.id) < (b.displayName or b.id)
	end)
	return out
end

-- ─── Wardrobe cell (one card in the grid) ───────────────────────────
-- Mini-tile. Top half = the skin's primary palette swatch (so the
-- player can read the colour at a glance). Bottom = display name +
-- rarity stars. Lock icon / EQUIPPED chip / SELECTED stroke layered
-- on top.
local CARD_FILL       = Color3.fromRGB(10, 24, 44)
local CARD_FILL_ALPHA = 0.30
local CARD_STROKE     = HOLO_PANEL_BORDER
local CARD_STROKE_SEL = HOLO_EDGE

local function buildSkinCard(parent, def, x, y, w, h, opts)
	opts = opts or {}
	local card = Instance.new("TextButton")
	card.Name = "Skin_" .. def.id
	card.AutoButtonColor = false
	card.Text = ""
	card.BackgroundColor3 = CARD_FILL
	card.BackgroundTransparency = CARD_FILL_ALPHA
	card.BorderSizePixel = 0
	card.Position = UDim2.fromOffset(x, y)
	card.Size = UDim2.fromOffset(w, h)
	card.ZIndex = (parent.ZIndex or 1) + 2
	card.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = opts.selected and CARD_STROKE_SEL or CARD_STROKE
	stroke.Thickness = opts.selected and 1.6 or 1
	stroke.Parent = card

	-- Palette swatch (top region). Uses the first hex from the def's
	-- palette as the dominant colour; drops alpha if the skin is locked
	-- so it reads as "greyed out".
	local swatchH = math.floor(h * 0.62)
	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.BackgroundColor3 = hexToColor3((def.palette and def.palette[1]) or "#5FA8C6")
	swatch.BackgroundTransparency = opts.locked and 0.55 or 0
	swatch.BorderSizePixel = 0
	swatch.Position = UDim2.fromOffset(0, 0)
	swatch.Size = UDim2.fromOffset(w, swatchH)
	swatch.ZIndex = card.ZIndex + 1
	swatch.Parent = card

	-- Two thin accent stripes mimic the design's wardrobe-mannequin look
	-- without needing a viewport per cell.
	if def.palette and def.palette[2] then
		local stripe = Instance.new("Frame")
		stripe.AnchorPoint = Vector2.new(0.5, 1)
		stripe.Position = UDim2.fromScale(0.5, 1)
		stripe.Size = UDim2.fromOffset(math.floor(w * 0.6), math.floor(swatchH * 0.32))
		stripe.BackgroundColor3 = hexToColor3(def.palette[2])
		stripe.BackgroundTransparency = opts.locked and 0.55 or 0
		stripe.BorderSizePixel = 0
		stripe.ZIndex = swatch.ZIndex + 1
		stripe.Parent = swatch
	end

	-- Display name (centre, single line, truncated)
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.BorderSizePixel = 0
	name.Position = UDim2.fromOffset(0, swatchH + 4)
	name.Size = UDim2.fromOffset(w, 14)
	name.Font = FONT_TITLE
	name.TextSize = 11
	name.TextColor3 = opts.locked and COLOR_TEXT_MUTE or COLOR_TEXT
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = def.displayName or def.id
	name.ZIndex = card.ZIndex + 2
	name.Parent = card

	-- Rarity stars below the name
	local starRow = makeStarRow(card, def.rarity or 1, 4, 9)
	starRow.AnchorPoint = Vector2.new(0.5, 0)
	starRow.Position = UDim2.new(0.5, 0, 0, swatchH + 22)
	starRow.ZIndex = card.ZIndex + 2

	-- EQUIPPED chip (top-right) when this skin is currently worn.
	if opts.equipped then
		local chip = Instance.new("Frame")
		chip.AnchorPoint = Vector2.new(1, 0)
		chip.Position = UDim2.new(1, -4, 0, 4)
		chip.Size = UDim2.fromOffset(14, 14)
		chip.BackgroundColor3 = EQUIP_GREEN
		chip.BorderSizePixel = 0
		chip.ZIndex = card.ZIndex + 3
		chip.Parent = card
		local chipCorner = Instance.new("UICorner")
		chipCorner.CornerRadius = UDim.new(1, 0)
		chipCorner.Parent = chip
		local tick = Instance.new("TextLabel")
		tick.BackgroundTransparency = 1
		tick.Size = UDim2.fromScale(1, 1)
		tick.Font = FONT_TITLE
		tick.TextSize = 10
		tick.TextColor3 = EQUIP_GREEN_TEXT
		tick.Text = "✓"
		tick.ZIndex = chip.ZIndex + 1
		tick.Parent = chip
	end

	-- LOCK overlay for skins the player doesn't own yet.
	if opts.locked then
		local lock = Instance.new("TextLabel")
		lock.AnchorPoint = Vector2.new(1, 1)
		lock.Position = UDim2.new(1, -4, 1, -4)
		lock.Size = UDim2.fromOffset(14, 14)
		lock.BackgroundTransparency = 1
		lock.Font = FONT_TITLE
		lock.TextSize = 12
		lock.TextColor3 = LOCK_GREY
		lock.Text = "🔒"
		lock.ZIndex = card.ZIndex + 3
		lock.Parent = card
	end

	return card, stroke
end

-- ─── Close + re-open helpers ────────────────────────────────────────
local function closeSkinSelectPage()
	disconnectAll(activeConnections)
	if activeCtx and activeCtx.detachCachedViewports then
		activeCtx.detachCachedViewports()
	end
	if activePage then
		activePage:Destroy()
		activePage = nil
	end
	activeCtx = nil
end

-- ─── Open ───────────────────────────────────────────────────────────
local function openSkinSelectPage(ctx)
	ctx = ctx or {}
	local screenGui = ctx.screenGui
	if not screenGui then
		warn("[SkinSelectPage] open called without ctx.screenGui")
		return
	end

	closeSkinSelectPage()
	activeCtx = ctx

	local page = Instance.new("Frame")
	page.Name = "SkinSelectPage"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ZIndex = 50
	page.Parent = screenGui
	activePage = page

	if ctx.hidePhonePanels then ctx.hidePhonePanels() end

	-- Responsive 960×600 artboard, centred on screen.
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

	-- Track viewport changes so the artboard re-fits on resize.
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

	-- ── BACK button ─────────────────────────────────────────────────
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
	bStroke.Color = HOLO_PANEL_BORDER
	bStroke.Thickness = 1
	bStroke.Parent = backBtn
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
		closeSkinSelectPage()
		if ctx.onBack then ctx.onBack() end
	end
	backBtn.MouseButton1Click:Connect(triggerBack);
	(_G.AttachBackHotkey or function() end)(backBtn, triggerBack, {
		activeConnections = activeConnections,
		color             = COLOR_TEXT,
		haloColor         = HOLO_EDGE,
		fontTitle         = FONT_TITLE,
	})

	-- ── Centred title: "SELECT SKIN" + FOR · MERC subtitle ──────────
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
	title.Text = "◆  SELECT SKIN"
	title.ZIndex = 52
	title.Parent = scaleWrap

	local theme = ctx.theme or {}
	local mercDisplay = string.upper(theme.displayName or ctx.mercName or "")
	if mercDisplay ~= "" then
		local subtitle = Instance.new("TextLabel")
		subtitle.Name = "PageSubtitle"
		subtitle.BackgroundTransparency = 1
		subtitle.BorderSizePixel = 0
		subtitle.AnchorPoint = Vector2.new(1, 0)
		subtitle.Position = UDim2.new(1, -16, 0, BACK_BTN_Y + 12)
		subtitle.Size = UDim2.fromOffset(220, 16)
		subtitle.Font = FONT_BODY
		subtitle.TextSize = 11
		subtitle.TextColor3 = COLOR_TEXT_DIM
		subtitle.TextXAlignment = Enum.TextXAlignment.Right
		subtitle.Text = "FOR · " .. mercDisplay
		subtitle.ZIndex = 52
		subtitle.Parent = scaleWrap
	end

	-- ── Centre viewport (cached merc rig from MercenariesMenu) ──────
	-- Resolve the equipped weapon the same way WeaponSelectPage does
	-- so the rig in the centre holds the right tool.
	local mercFolder = player:FindFirstChild("Mercenaries")
	local mercEntry  = mercFolder and ctx.mercName and mercFolder:FindFirstChild(ctx.mercName)
	local equippedWeaponId
	if typeof(ctx.resolveMercWeapon) == "function" then
		equippedWeaponId = ctx.resolveMercWeapon(ctx.mercName, mercEntry, theme)
	else
		equippedWeaponId = theme.defaultWeapon or "Sword"
		if mercEntry then
			local eq = mercEntry:GetAttribute("EquippedWeapon")
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
		if vp then vp.ZIndex = 60 end
	end

	-- "CURRENTLY WEARING" plate above the viewport — shows the actively
	-- equipped skin's name + star row so the centre of the screen
	-- always answers "what am I previewing?".
	local nowPlate = Instance.new("Frame")
	nowPlate.Name = "NowWearing"
	nowPlate.BackgroundColor3 = HOLO_PANEL_FILL
	nowPlate.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY + 0.1
	nowPlate.BorderSizePixel = 0
	nowPlate.AnchorPoint = Vector2.new(0.5, 0)
	nowPlate.Position = UDim2.fromOffset(REFERENCE_W / 2, 70)
	nowPlate.Size = UDim2.fromOffset(220, 46)
	nowPlate.ZIndex = 53
	nowPlate.Parent = scaleWrap
	local nowStroke = Instance.new("UIStroke")
	nowStroke.Color = HOLO_PANEL_BORDER
	nowStroke.Thickness = 1
	nowStroke.Parent = nowPlate

	local nowCaption = Instance.new("TextLabel")
	nowCaption.BackgroundTransparency = 1
	nowCaption.Position = UDim2.fromOffset(0, 4)
	nowCaption.Size = UDim2.new(1, 0, 0, 12)
	nowCaption.Font = FONT_BODY
	nowCaption.TextSize = 9
	nowCaption.TextColor3 = COLOR_TEXT_MUTE
	nowCaption.TextXAlignment = Enum.TextXAlignment.Center
	nowCaption.Text = "CURRENTLY WEARING"
	nowCaption.ZIndex = nowPlate.ZIndex + 1
	nowCaption.Parent = nowPlate

	local nowName = Instance.new("TextLabel")
	nowName.Name = "Name"
	nowName.BackgroundTransparency = 1
	nowName.Position = UDim2.fromOffset(0, 16)
	nowName.Size = UDim2.new(1, 0, 0, 16)
	nowName.Font = FONT_TITLE
	nowName.TextSize = 13
	nowName.TextColor3 = COLOR_TEXT
	nowName.TextXAlignment = Enum.TextXAlignment.Center
	nowName.TextTruncate = Enum.TextTruncate.AtEnd
	nowName.Text = ""
	nowName.ZIndex = nowPlate.ZIndex + 1
	nowName.Parent = nowPlate

	-- Now-wearing star host. Rebuilt on each paint so the row is always
	-- in sync with the equipped skin's rarity without depending on the
	-- order makeStarRow added its children.
	local nowStarsHost = Instance.new("Frame")
	nowStarsHost.Name = "Stars"
	nowStarsHost.BackgroundTransparency = 1
	nowStarsHost.AnchorPoint = Vector2.new(0.5, 1)
	nowStarsHost.Position = UDim2.new(0.5, 0, 1, -4)
	nowStarsHost.Size = UDim2.fromOffset(40, 10)
	nowStarsHost.ZIndex = nowPlate.ZIndex + 1
	nowStarsHost.Parent = nowPlate

	-- ── WARDROBE panel (left) ───────────────────────────────────────
	local WARDROBE_X = 40
	local WARDROBE_Y = 60
	local WARDROBE_W = 280
	local WARDROBE_H = 510
	local WARDROBE_PAD_X = 14

	local wardrobe = Instance.new("Frame")
	wardrobe.Name = "WardrobeCard"
	wardrobe.BackgroundColor3 = HOLO_PANEL_FILL
	wardrobe.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	wardrobe.BorderSizePixel = 0
	wardrobe.Position = UDim2.fromOffset(WARDROBE_X, WARDROBE_Y)
	wardrobe.Size = UDim2.fromOffset(WARDROBE_W, WARDROBE_H)
	wardrobe.ZIndex = 52
	wardrobe.Parent = scaleWrap
	local wStroke = Instance.new("UIStroke")
	wStroke.Color = HOLO_PANEL_BORDER
	wStroke.Thickness = 1
	wStroke.Parent = wardrobe

	-- Header row: 'WARDROBE' label + N/M OWNED counter.
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.Position = UDim2.fromOffset(WARDROBE_PAD_X, 14)
	header.Size = UDim2.new(1, -WARDROBE_PAD_X * 2, 0, 18)
	header.ZIndex = 53
	header.Parent = wardrobe

	local headerLabel = Instance.new("TextLabel")
	headerLabel.BackgroundTransparency = 1
	headerLabel.Size = UDim2.new(0.5, 0, 1, 0)
	headerLabel.Font = FONT_TITLE
	headerLabel.TextSize = 13
	headerLabel.TextColor3 = COLOR_TEXT
	headerLabel.TextXAlignment = Enum.TextXAlignment.Left
	headerLabel.Text = "🔒  WARDROBE"
	headerLabel.ZIndex = 54
	headerLabel.Parent = header

	local wardrobeCount = Instance.new("TextLabel")
	wardrobeCount.Name = "OwnedCount"
	wardrobeCount.BackgroundTransparency = 1
	wardrobeCount.AnchorPoint = Vector2.new(1, 0.5)
	wardrobeCount.Position = UDim2.new(1, 0, 0.5, 0)
	wardrobeCount.Size = UDim2.fromOffset(110, 16)
	wardrobeCount.Font = FONT_TITLE
	wardrobeCount.TextSize = 11
	wardrobeCount.TextColor3 = COLOR_TEXT_DIM
	wardrobeCount.TextXAlignment = Enum.TextXAlignment.Right
	wardrobeCount.Text = "0/0 OWNED"
	wardrobeCount.ZIndex = 54
	wardrobeCount.Parent = header

	-- Filter tabs row.
	local TAB_ROW_Y   = 40
	local TAB_H       = 24
	local TAB_GAP     = 4
	local TAB_INNER_W = WARDROBE_W - WARDROBE_PAD_X * 2
	local TAB_W       = (TAB_INNER_W - TAB_GAP * (#FILTER_DEFS - 1)) / #FILTER_DEFS

	local tabRow = Instance.new("Frame")
	tabRow.BackgroundTransparency = 1
	tabRow.Position = UDim2.fromOffset(WARDROBE_PAD_X, TAB_ROW_Y)
	tabRow.Size = UDim2.fromOffset(TAB_INNER_W, TAB_H)
	tabRow.ZIndex = 53
	tabRow.Parent = wardrobe

	local TAB_FILL_SEL         = Color3.fromRGB(16, 42, 72)
	local TAB_FILL_SEL_ALPHA   = 0.10
	local TAB_FILL_UNSEL       = HOLO_PANEL_FILL
	local TAB_FILL_UNSEL_ALPHA = 0.45
	local TAB_STROKE_SEL       = HOLO_EDGE
	local TAB_STROKE_UNSEL     = HOLO_PANEL_BORDER
	local TAB_TEXT_SEL         = Color3.fromRGB(230, 245, 255)
	local TAB_TEXT_UNSEL       = COLOR_TEXT_DIM

	local activeFilter = "ALL"
	local tabRefs = {}
	-- buildGrid forward-declared so the tab handler can call it.
	local buildGrid

	local function refreshTabVisuals()
		for id, ref in pairs(tabRefs) do
			local selected = (id == activeFilter)
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

	for i, def in ipairs(FILTER_DEFS) do
		local tile = Instance.new("TextButton")
		tile.AutoButtonColor = false
		tile.Text = ""
		tile.Position = UDim2.fromOffset((i - 1) * (TAB_W + TAB_GAP), 0)
		tile.Size = UDim2.fromOffset(TAB_W, TAB_H)
		tile.BorderSizePixel = 0
		tile.ZIndex = 54
		tile.Parent = tabRow
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = tile

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = FONT_TITLE
		label.TextSize = 10
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Text = def.label
		label.ZIndex = 55
		label.Parent = tile

		tabRefs[def.id] = { tile = tile, stroke = stroke, label = label }

		tile.MouseButton1Click:Connect(function()
			if activeFilter == def.id then return end
			activeFilter = def.id
			refreshTabVisuals()
			if buildGrid then buildGrid() end
		end)
	end

	-- Scroll grid host
	local GRID_TOP = TAB_ROW_Y + TAB_H + 10
	local gridScroll = Instance.new("ScrollingFrame")
	gridScroll.Name = "Grid"
	gridScroll.BackgroundTransparency = 1
	gridScroll.BorderSizePixel = 0
	gridScroll.Position = UDim2.fromOffset(WARDROBE_PAD_X, GRID_TOP)
	gridScroll.Size = UDim2.fromOffset(TAB_INNER_W, WARDROBE_H - GRID_TOP - 14)
	gridScroll.ScrollBarThickness = 4
	gridScroll.ScrollBarImageColor3 = HOLO_PANEL_BORDER
	gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	gridScroll.CanvasSize = UDim2.new()
	gridScroll.ZIndex = 53
	gridScroll.Parent = wardrobe

	-- ── DETAIL panel (right) ────────────────────────────────────────
	local DETAIL_X = REFERENCE_W - 40 - 280
	local DETAIL_Y = WARDROBE_Y
	local DETAIL_W = 280
	local DETAIL_H = WARDROBE_H
	local DETAIL_PAD_X = 14

	local detail = Instance.new("Frame")
	detail.Name = "DetailCard"
	detail.BackgroundColor3 = HOLO_PANEL_FILL
	detail.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	detail.BorderSizePixel = 0
	detail.Position = UDim2.fromOffset(DETAIL_X, DETAIL_Y)
	detail.Size = UDim2.fromOffset(DETAIL_W, DETAIL_H)
	detail.ZIndex = 52
	detail.Parent = scaleWrap
	local dStroke = Instance.new("UIStroke")
	dStroke.Color = HOLO_PANEL_BORDER
	dStroke.Thickness = 1
	dStroke.Parent = detail

	-- Detail header: skin name + EQUIPPED chip + category tag below.
	local detailHeader = Instance.new("Frame")
	detailHeader.BackgroundTransparency = 1
	detailHeader.Position = UDim2.fromOffset(DETAIL_PAD_X, 14)
	detailHeader.Size = UDim2.new(1, -DETAIL_PAD_X * 2, 0, 44)
	detailHeader.ZIndex = 53
	detailHeader.Parent = detail

	local detailName = Instance.new("TextLabel")
	detailName.Name = "Name"
	detailName.BackgroundTransparency = 1
	detailName.Position = UDim2.fromOffset(0, 0)
	detailName.Size = UDim2.new(1, -64, 0, 22)
	detailName.Font = FONT_TITLE
	detailName.TextSize = 16
	detailName.TextColor3 = HOLO_EDGE
	detailName.TextXAlignment = Enum.TextXAlignment.Left
	detailName.TextTruncate = Enum.TextTruncate.AtEnd
	detailName.Text = "—"
	detailName.ZIndex = 54
	detailName.Parent = detailHeader

	local equippedChip = Instance.new("Frame")
	equippedChip.Name = "EquippedChip"
	equippedChip.AnchorPoint = Vector2.new(1, 0)
	equippedChip.Position = UDim2.new(1, 0, 0, 2)
	equippedChip.Size = UDim2.fromOffset(58, 16)
	equippedChip.BackgroundColor3 = EQUIP_GREEN
	equippedChip.BackgroundTransparency = 0.05
	equippedChip.BorderSizePixel = 0
	equippedChip.ZIndex = 54
	equippedChip.Visible = false
	equippedChip.Parent = detailHeader
	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = UDim.new(0, 3)
	chipCorner.Parent = equippedChip
	local chipLabel = Instance.new("TextLabel")
	chipLabel.BackgroundTransparency = 1
	chipLabel.Size = UDim2.fromScale(1, 1)
	chipLabel.Font = FONT_TITLE
	chipLabel.TextSize = 10
	chipLabel.TextColor3 = EQUIP_GREEN_TEXT
	chipLabel.TextXAlignment = Enum.TextXAlignment.Center
	chipLabel.Text = "EQUIPPED"
	chipLabel.ZIndex = 55
	chipLabel.Parent = equippedChip

	local detailCategory = Instance.new("TextLabel")
	detailCategory.Name = "Category"
	detailCategory.BackgroundTransparency = 1
	detailCategory.Position = UDim2.fromOffset(0, 22)
	detailCategory.Size = UDim2.new(1, 0, 0, 14)
	detailCategory.Font = FONT_TITLE
	detailCategory.TextSize = 11
	detailCategory.TextColor3 = COLOR_TEXT_DIM
	detailCategory.TextXAlignment = Enum.TextXAlignment.Left
	detailCategory.Text = ""
	detailCategory.ZIndex = 54
	detailCategory.Parent = detailHeader

	-- PALETTE caption + 3 swatches
	local PALETTE_Y = 70
	local paletteCaption = Instance.new("TextLabel")
	paletteCaption.BackgroundTransparency = 1
	paletteCaption.Position = UDim2.fromOffset(DETAIL_PAD_X, PALETTE_Y)
	paletteCaption.Size = UDim2.new(1, -DETAIL_PAD_X * 2, 0, 12)
	paletteCaption.Font = FONT_TITLE
	paletteCaption.TextSize = 10
	paletteCaption.TextColor3 = COLOR_TEXT_DIM
	paletteCaption.TextXAlignment = Enum.TextXAlignment.Left
	paletteCaption.Text = "PALETTE"
	paletteCaption.ZIndex = 53
	paletteCaption.Parent = detail

	local SWATCH_GAP = 8
	local SWATCH_W = (DETAIL_W - DETAIL_PAD_X * 2 - SWATCH_GAP * 2) / 3
	local SWATCH_H = 28
	local swatchHosts = {}
	for i = 1, 3 do
		local sw = Instance.new("Frame")
		sw.Name = "Swatch_" .. i
		sw.Position = UDim2.fromOffset(
			DETAIL_PAD_X + (i - 1) * (SWATCH_W + SWATCH_GAP),
			PALETTE_Y + 16)
		sw.Size = UDim2.fromOffset(SWATCH_W, SWATCH_H)
		sw.BackgroundColor3 = HOLO_PANEL_BORDER
		sw.BorderSizePixel = 0
		sw.ZIndex = 53
		sw.Parent = detail

		local swLabel = Instance.new("TextLabel")
		swLabel.Name = "Hex"
		swLabel.BackgroundTransparency = 1
		swLabel.Position = UDim2.fromOffset(0, SWATCH_H + 2)
		swLabel.Size = UDim2.new(1, 0, 0, 11)
		swLabel.Font = FONT_BODY
		swLabel.TextSize = 9
		swLabel.TextColor3 = COLOR_TEXT_MUTE
		swLabel.TextXAlignment = Enum.TextXAlignment.Center
		swLabel.Text = ""
		swLabel.ZIndex = 53
		swLabel.Parent = sw
		swatchHosts[i] = sw
	end

	-- Stars + SET row.
	local STAR_ROW_Y = PALETTE_Y + 16 + SWATCH_H + 24
	-- Star host: rebuilt on every paintDetail so we don't have to
	-- worry about iteration order over makeStarRow's children.
	local detailStarsHost = Instance.new("Frame")
	detailStarsHost.Name = "DetailStars"
	detailStarsHost.BackgroundTransparency = 1
	detailStarsHost.BorderSizePixel = 0
	detailStarsHost.Position = UDim2.fromOffset(DETAIL_PAD_X, STAR_ROW_Y)
	detailStarsHost.Size = UDim2.fromOffset(120, 14)
	detailStarsHost.ZIndex = 53
	detailStarsHost.Parent = detail

	local setChip = Instance.new("TextLabel")
	setChip.Name = "SetChip"
	setChip.BackgroundColor3 = CHIP_FILL
	setChip.BackgroundTransparency = CHIP_FILL_ALPHA
	setChip.BorderSizePixel = 0
	setChip.AnchorPoint = Vector2.new(1, 0)
	setChip.Position = UDim2.new(1, -DETAIL_PAD_X, 0, STAR_ROW_Y - 1)
	setChip.Size = UDim2.fromOffset(120, 16)
	setChip.Font = FONT_TITLE
	setChip.TextSize = 10
	setChip.TextColor3 = COLOR_TEXT_DIM
	setChip.TextXAlignment = Enum.TextXAlignment.Center
	setChip.Text = ""
	setChip.Visible = false
	setChip.ZIndex = 53
	setChip.Parent = detail
	local setStroke = Instance.new("UIStroke")
	setStroke.Color = HOLO_PANEL_BORDER
	setStroke.Thickness = 1
	setStroke.Parent = setChip

	-- SOURCE caption + value
	local SOURCE_Y = STAR_ROW_Y + 30
	local sourceCaption = Instance.new("TextLabel")
	sourceCaption.BackgroundTransparency = 1
	sourceCaption.Position = UDim2.fromOffset(DETAIL_PAD_X, SOURCE_Y)
	sourceCaption.Size = UDim2.new(1, -DETAIL_PAD_X * 2, 0, 12)
	sourceCaption.Font = FONT_TITLE
	sourceCaption.TextSize = 10
	sourceCaption.TextColor3 = COLOR_TEXT_DIM
	sourceCaption.TextXAlignment = Enum.TextXAlignment.Left
	sourceCaption.Text = "SOURCE"
	sourceCaption.ZIndex = 53
	sourceCaption.Parent = detail

	local sourceValue = Instance.new("TextLabel")
	sourceValue.Name = "SourceValue"
	sourceValue.BackgroundTransparency = 1
	sourceValue.Position = UDim2.fromOffset(DETAIL_PAD_X, SOURCE_Y + 14)
	sourceValue.Size = UDim2.new(1, -DETAIL_PAD_X * 2, 0, 16)
	sourceValue.Font = FONT_TITLE
	sourceValue.TextSize = 13
	sourceValue.TextColor3 = COLOR_TEXT
	sourceValue.TextXAlignment = Enum.TextXAlignment.Left
	sourceValue.TextTruncate = Enum.TextTruncate.AtEnd
	sourceValue.Text = ""
	sourceValue.ZIndex = 53
	sourceValue.Parent = detail

	-- Description block (multi-line, wrapped)
	local DESC_Y = SOURCE_Y + 42
	local description = Instance.new("TextLabel")
	description.Name = "Description"
	description.BackgroundTransparency = 1
	description.Position = UDim2.fromOffset(DETAIL_PAD_X, DESC_Y)
	description.Size = UDim2.new(1, -DETAIL_PAD_X * 2, 0, 110)
	description.Font = FONT_BODY
	description.TextSize = 12
	description.TextColor3 = COLOR_TEXT_DIM
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextWrapped = true
	description.Text = ""
	description.ZIndex = 53
	description.Parent = detail

	-- WORN button (footer)
	local FOOTER_H = 44
	local footer = Instance.new("Frame")
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 0, 1, -10)
	footer.Size = UDim2.new(1, 0, 0, FOOTER_H)
	footer.ZIndex = 53
	footer.Parent = detail

	local wornByCaption = Instance.new("TextLabel")
	wornByCaption.BackgroundTransparency = 1
	wornByCaption.Position = UDim2.fromOffset(DETAIL_PAD_X, 0)
	wornByCaption.Size = UDim2.new(0.5, -DETAIL_PAD_X, 0, 12)
	wornByCaption.Font = FONT_TITLE
	wornByCaption.TextSize = 9
	wornByCaption.TextColor3 = COLOR_TEXT_MUTE
	wornByCaption.TextXAlignment = Enum.TextXAlignment.Left
	wornByCaption.Text = "WORN BY"
	wornByCaption.ZIndex = 54
	wornByCaption.Parent = footer

	local wornByValue = Instance.new("TextLabel")
	wornByValue.BackgroundTransparency = 1
	wornByValue.Position = UDim2.fromOffset(DETAIL_PAD_X, 14)
	wornByValue.Size = UDim2.new(0.5, -DETAIL_PAD_X, 0, 16)
	wornByValue.Font = FONT_TITLE
	wornByValue.TextSize = 13
	wornByValue.TextColor3 = COLOR_TEXT
	wornByValue.TextXAlignment = Enum.TextXAlignment.Left
	wornByValue.Text = theme.displayName or ctx.mercName or ""
	wornByValue.ZIndex = 54
	wornByValue.Parent = footer

	local wornBtn = Instance.new("TextButton")
	wornBtn.Name = "WornButton"
	wornBtn.AutoButtonColor = false
	wornBtn.Text = ""
	wornBtn.AnchorPoint = Vector2.new(1, 0.5)
	wornBtn.Position = UDim2.new(1, -DETAIL_PAD_X, 0.5, 0)
	wornBtn.Size = UDim2.fromOffset(108, 30)
	wornBtn.BackgroundColor3 = EQUIP_GREEN
	wornBtn.BackgroundTransparency = 0.1
	wornBtn.BorderSizePixel = 0
	wornBtn.ZIndex = 54
	wornBtn.Parent = footer
	local wbCorner = Instance.new("UICorner")
	wbCorner.CornerRadius = UDim.new(0, 4)
	wbCorner.Parent = wornBtn
	local wbStroke = Instance.new("UIStroke")
	wbStroke.Color = EQUIP_GREEN
	wbStroke.Thickness = 1
	wbStroke.Parent = wornBtn

	local wornBtnLabel = Instance.new("TextLabel")
	wornBtnLabel.BackgroundTransparency = 1
	wornBtnLabel.Size = UDim2.fromScale(1, 1)
	wornBtnLabel.Font = FONT_TITLE
	wornBtnLabel.TextSize = 12
	wornBtnLabel.TextColor3 = EQUIP_GREEN_TEXT
	wornBtnLabel.TextXAlignment = Enum.TextXAlignment.Center
	wornBtnLabel.Text = "✓ WORN"
	wornBtnLabel.ZIndex = 55
	wornBtnLabel.Parent = wornBtn

	-- ── Reactive paint (snapshot push or local selection change) ────
	-- selectedSkinId follows whatever the player has clicked; the page
	-- opens already pointing at the merc's currently-equipped skin.
	local selectedSkinId = nil
	local cardRefs = {}   -- skinId → { card, stroke } so paint loop can repaint stroke

	local function rebuildStars(host, filled, size)
		for _, child in ipairs(host:GetChildren()) do child:Destroy() end
		size = size or 12
		local total = 4
		local gap = 2
		filled = math.clamp(tonumber(filled) or 0, 0, total)
		host.Size = UDim2.fromOffset(total * size + (total - 1) * gap, size)
		for i = 1, total do
			local s = Instance.new("ImageLabel")
			s.BackgroundTransparency = 1
			s.BorderSizePixel = 0
			s.Position = UDim2.fromOffset((i - 1) * (size + gap), 0)
			s.Size = UDim2.fromOffset(size, size)
			s.Image = (i <= filled) and STAR_IMAGE_FULL or STAR_IMAGE_EMPTY
			s.ZIndex = (host.ZIndex or 1) + 1
			s.Parent = host
		end
	end

	local function paintDetail()
		local def = selectedSkinId and catalogById[selectedSkinId]
		if not def then
			detailName.Text = "—"
			detailCategory.Text = ""
			equippedChip.Visible = false
			for _, sw in ipairs(swatchHosts) do
				sw.BackgroundColor3 = HOLO_PANEL_BORDER
				sw.Hex.Text = ""
			end
			rebuildStars(detailStarsHost, 0, 12)
			setChip.Visible = false
			sourceValue.Text = ""
			description.Text = ""
			wornBtn.Visible = false
			return
		end

		detailName.Text = def.displayName or def.id
		detailCategory.Text = string.upper(def.category or "")
		local isEquipped = (equippedByMerc[ctx.mercName] == def.id)
		equippedChip.Visible = isEquipped

		for i, sw in ipairs(swatchHosts) do
			local hex = def.palette and def.palette[i]
			if hex then
				sw.BackgroundColor3 = hexToColor3(hex)
				sw.Hex.Text = string.upper(hex)
			else
				sw.BackgroundColor3 = HOLO_PANEL_BORDER
				sw.Hex.Text = ""
			end
		end

		rebuildStars(detailStarsHost, def.rarity or 0, 12)

		if def.setName and def.setName ~= "" then
			setChip.Text = "SET · " .. string.upper(def.setName)
			setChip.Visible = true
		else
			setChip.Visible = false
		end
		sourceValue.Text = def.source or "—"
		description.Text = def.description or ""

		-- WORN button state: green "WORN" if equipped, "WEAR" otherwise.
		-- Locked skins hide the button entirely so the player can't equip
		-- something they don't own.
		local owned = ownedSet[def.id] == true
		if not owned then
			wornBtn.Visible = false
		elseif isEquipped then
			wornBtn.Visible = true
			wornBtn.BackgroundColor3 = EQUIP_GREEN
			wbStroke.Color = EQUIP_GREEN
			wornBtnLabel.Text = "✓ WORN"
			wornBtnLabel.TextColor3 = EQUIP_GREEN_TEXT
		else
			wornBtn.Visible = true
			wornBtn.BackgroundColor3 = HOLO_PANEL_FILL
			wbStroke.Color = HOLO_EDGE
			wornBtnLabel.Text = "WEAR"
			wornBtnLabel.TextColor3 = HOLO_EDGE
		end
	end

	local function paintNowWearing()
		local id = equippedByMerc[ctx.mercName]
		local def = id and catalogById[id]
		if def then
			nowName.Text = def.displayName or def.id
			rebuildStars(nowStarsHost, def.rarity or 0, 8)
		else
			nowName.Text = "—"
			rebuildStars(nowStarsHost, 0, 8)
		end
	end

	local GRID_COLS    = 3
	local GRID_GAP     = 6
	local GRID_INNER_W = TAB_INNER_W
	local CARD_W = (GRID_INNER_W - GRID_GAP * (GRID_COLS - 1)) / GRID_COLS
	local CARD_H = 96

	buildGrid = function()
		-- Wipe any existing cards (a re-build from a tab change or
		-- snapshot push). Layout-managed via direct positioning so we
		-- don't have to fight UIGridLayout for the spacing.
		for _, child in gridScroll:GetChildren() do
			if child:IsA("TextButton") then child:Destroy() end
		end
		table.clear(cardRefs)

		local entries = catalogForMerc(ctx.mercName)
		local ownedCount, totalCount = 0, #entries
		for _, def in ipairs(entries) do
			if ownedSet[def.id] then ownedCount = ownedCount + 1 end
		end
		wardrobeCount.Text = string.format("%d/%d OWNED", ownedCount, totalCount)

		local visible = {}
		for _, def in ipairs(entries) do
			local owned = ownedSet[def.id] == true
			if entryMatchesFilter(def, activeFilter, owned) then
				table.insert(visible, def)
			end
		end

		for i, def in ipairs(visible) do
			local col = (i - 1) % GRID_COLS
			local row = math.floor((i - 1) / GRID_COLS)
			local x = col * (CARD_W + GRID_GAP)
			local y = row * (CARD_H + GRID_GAP)
			local owned = ownedSet[def.id] == true
			local equipped = equippedByMerc[ctx.mercName] == def.id
			local card, stroke = buildSkinCard(gridScroll, def, x, y, CARD_W, CARD_H, {
				selected = (selectedSkinId == def.id),
				equipped = equipped,
				locked   = not owned,
			})
			cardRefs[def.id] = { card = card, stroke = stroke }
			card.MouseButton1Click:Connect(function()
				if selectedSkinId == def.id then return end
				selectedSkinId = def.id
				-- Repaint every card stroke so the previous selection
				-- drops back to plain border weight.
				for id, ref in pairs(cardRefs) do
					if id == selectedSkinId then
						ref.stroke.Color = CARD_STROKE_SEL
						ref.stroke.Thickness = 1.6
					else
						ref.stroke.Color = CARD_STROKE
						ref.stroke.Thickness = 1
					end
				end
				paintDetail()
			end)
		end
	end

	local function repaintAll()
		-- If the last-selected skin no longer matches anything in the
		-- catalog (e.g. it was removed in a hot-reload), drop back to
		-- whatever's currently equipped.
		if selectedSkinId and not catalogById[selectedSkinId] then
			selectedSkinId = nil
		end
		if not selectedSkinId then
			selectedSkinId = equippedByMerc[ctx.mercName]
		end
		buildGrid()
		paintNowWearing()
		paintDetail()
	end

	-- WORN-button click → fire equip on server. Server pushes a fresh
	-- snapshot back; repaintAll handles the visual update.
	local skinEvent = ReplicatedStorage:FindFirstChild("MercenarySkin")
	wornBtn.MouseButton1Click:Connect(function()
		if not skinEvent then return end
		if not selectedSkinId then return end
		if equippedByMerc[ctx.mercName] == selectedSkinId then return end
		if not ownedSet[selectedSkinId] then return end
		skinEvent:FireServer("equip", ctx.mercName, selectedSkinId)
	end)

	-- Subscribe to server pushes.
	if skinEvent then
		table.insert(activeConnections,
			skinEvent.OnClientEvent:Connect(function(action, payload)
				if action ~= "state" then return end
				if type(payload) ~= "table" then return end
				catalogById    = payload.catalog    or {}
				ownedSet       = payload.ownedSkins or {}
				equippedByMerc = payload.equipped   or {}
				repaintAll()
			end))
		-- Kick off — server replies via OnClientEvent above.
		skinEvent:FireServer("getState")
	else
		warn("[SkinSelectPage] MercenarySkin RemoteEvent missing — page will be empty")
	end

	refreshTabVisuals()

	-- Catch external destroy (e.g. screen-gui rebuild) so we tear down
	-- our connections; mirrors WeaponSelectPage's safety net.
	table.insert(activeConnections, page.AncestryChanged:Connect(function(_, newParent)
		if newParent == nil then
			disconnectAll(activeConnections)
			activePage = nil
			activeCtx  = nil
		end
	end))
end

_G.OpenSkinSelectPage  = openSkinSelectPage
_G.CloseSkinSelectPage = closeSkinSelectPage
