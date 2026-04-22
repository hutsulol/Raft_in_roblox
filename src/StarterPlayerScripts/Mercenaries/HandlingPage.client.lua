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

	local backBtnRef
	local BACK_BTN_Y = 39

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

	-- Placeholder BACK button, positioned with the same dynamicBleed
	-- trick the MercenariesMenu's BACK uses so it sits flush with the
	-- screen's left edge at any window size. Step 2 will wrap it in a
	-- full top bar with a centred "MERCENARY / name / LV N" cluster
	-- and a gem currency chip on the right.
	local backBtn = Instance.new("TextButton")
	backBtn.Name = "BackButton"
	backBtn.AnchorPoint = Vector2.new(0, 0)
	backBtn.Position = UDim2.fromOffset(0, BACK_BTN_Y)
	backBtn.Size = UDim2.fromOffset(88, 34)
	backBtn.BackgroundColor3 = HOLO_PANEL_FILL
	backBtn.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	backBtn.BorderSizePixel = 0
	backBtn.AutoButtonColor = true
	backBtn.Font = FONT_TITLE
	backBtn.TextSize = 13
	backBtn.TextColor3 = COLOR_TEXT
	backBtn.Text = "← BACK"
	backBtn.ZIndex = 6
	backBtn.Parent = scaleWrap
	local bStroke = Instance.new("UIStroke")
	bStroke.Color     = HOLO_PANEL_BORDER
	bStroke.Thickness = 1
	bStroke.Parent    = backBtn
	backBtnRef = backBtn

	backBtn.MouseButton1Click:Connect(function()
		closeHandlingPage()
		if ctx.onBack then ctx.onBack() end
	end)

	-- Visible placeholder title so the scaffold renders with something
	-- besides the backdrop. Replaced in Step 2 by the real top-bar
	-- cluster.
	local title = Instance.new("TextLabel")
	title.Name = "Placeholder"
	title.BackgroundTransparency = 1
	title.BorderSizePixel = 0
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.Size = UDim2.fromOffset(600, 60)
	title.Font = FONT_TITLE
	title.TextSize = 24
	title.TextColor3 = HOLO_EDGE
	title.Text = string.format(
		"HANDLING · %s",
		tostring(ctx.mercName or "—"):upper()
	)
	title.ZIndex = 51
	title.Parent = scaleWrap

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
