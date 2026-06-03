-- OnboardingTooltip.client.lua
-- Wood/paper hint widget that slides in from the upper-left of the
-- screen below Roblox's CoreGui top bar. Built on the same pattern
-- QuestNotification.client.lua already uses successfully:
--
--   * plain Frame container with AutomaticSize.Y so the panel
--     shrink-wraps to its content,
--   * UIListLayout for vertical stacking of header + body,
--   * UISizeConstraint clamps the panel width,
--   * a single Position tween for slide-in / slide-out — no fade,
--     no CanvasGroup. (CanvasGroup + AutomaticSize.Y was the bug
--     that made the previous panel fill the screen.)
--
-- Public API:
--   handle = _G.ShowOnboardingTip({
--       id          = "chopTrees",
--       eyebrow     = "HINT",
--       title       = "Chop down trees",
--       body        = "Use your <b>axe</b> on a floating tree to gather <b>logs</b>.",
--       iconKind    = "axe",                 -- axe | log | drop | fish
--       iconImage   = "rbxassetid://...",    -- optional override
--       goal        = 3,                      -- nil = no progress bar
--       progress    = 0,
--       showClose   = true,
--       onDismiss   = function() ... end,
--       onComplete  = function() ... end,
--       autoDismissAfterComplete = 1.4,
--   })
--   handle.setProgress(n)
--   handle.complete()
--   handle.dismiss()
--   handle.instance       -- the panel Frame (read-only)

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── Palette (lifted from Claude Design's CSS variables) ──────────────
local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_WOOD_DARK    = Color3.fromRGB( 91,  58,  34)
local COLOR_WOOD_MID     = Color3.fromRGB(138, 106,  68)
local COLOR_WOOD_BASE    = Color3.fromRGB(176, 138,  92)
local COLOR_PAPER        = Color3.fromRGB(233, 217, 184)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(243, 230, 204)
-- Lighter than the mockup's #4A7C3A — the original gradient read as
-- almost-black against the wood panel. Bumped each stop ~30-40 RGB
-- points toward white so the fill pops as a clear positive signal.
local COLOR_GREEN        = Color3.fromRGB(116, 176,  82)
local COLOR_GREEN_LIGHT  = Color3.fromRGB(160, 220, 110)
local COLOR_GREEN_DARK   = Color3.fromRGB( 92, 148,  64)

local FONT_TITLE = Enum.Font.GothamBold
local FONT_BODY  = Enum.Font.Gotham

local PANEL_WIDTH    = 320
local MARGIN_X       = 16
-- 16-px gap measured from the bottom of Roblox's top-bar inset
-- (IgnoreGuiInset=false on the ScreenGui below already bakes the
-- 36-px inset in for us). Plus another 24 px so the tooltip sits
-- visibly below the chat / menu / Roblox icons rather than tucking
-- right against them.
local MARGIN_Y       = 24
local SLIDE_TIME     = 0.35
local SLIDE_OFFSET_Y = 80   -- pre-entrance + post-exit Y delta

-- ─── Geometry helpers ─────────────────────────────────────────────────
local function corner(parent, radiusPx)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radiusPx)
	c.Parent = parent
	return c
end

local function stroke(parent, thicknessPx, color, transparency)
	local s = Instance.new("UIStroke")
	s.Thickness = thicknessPx
	s.Color = color
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function pad(parent, all)
	local p = Instance.new("UIPadding")
	p.PaddingTop    = UDim.new(0, all)
	p.PaddingBottom = UDim.new(0, all)
	p.PaddingLeft   = UDim.new(0, all)
	p.PaddingRight  = UDim.new(0, all)
	p.Parent = parent
	return p
end

-- ─── Built-in icon glyphs (axe / log / drop / fish) ───────────────────
-- Same shapes as before, just collected into one builder block. Each
-- takes (parent, sizePx) and centres the glyph inside the parent.

local OUTLINE = COLOR_WOOD_DARKEST

local function makeIconContainer(parent, sizePx)
	local c = Instance.new("Frame")
	c.Name = "IconGlyph"
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	c.Position = UDim2.fromScale(0.5, 0.5)
	c.Size = UDim2.fromOffset(sizePx, sizePx)
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Parent = parent
	return c
end

local function makeAxeIcon(parent, s)
	local c = makeIconContainer(parent, s)
	local handle = Instance.new("Frame")
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.Position = UDim2.new(0.55, 0, 0.55, 0)
	handle.Size = UDim2.fromOffset(math.max(2, math.floor(s * 0.10)), math.floor(s * 0.78))
	handle.BackgroundColor3 = Color3.fromRGB(164, 113, 72)
	handle.BorderSizePixel = 0
	handle.Rotation = 22
	handle.Parent = c
	corner(handle, 2)
	stroke(handle, 1, OUTLINE)

	local blade = Instance.new("Frame")
	blade.AnchorPoint = Vector2.new(0.5, 0.5)
	blade.Position = UDim2.new(0.32, 0, 0.32, 0)
	blade.Size = UDim2.fromOffset(math.floor(s * 0.46), math.floor(s * 0.28))
	blade.BackgroundColor3 = Color3.fromRGB(184, 184, 184)
	blade.BorderSizePixel = 0
	blade.Rotation = -18
	blade.Parent = c
	corner(blade, 3)
	stroke(blade, 1, OUTLINE)

	local edge = Instance.new("Frame")
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Position = UDim2.new(0.32, 0, 0.32, 0)
	edge.Size = UDim2.fromOffset(math.floor(s * 0.32), math.max(1, math.floor(s * 0.05)))
	edge.BackgroundColor3 = Color3.fromRGB(110, 110, 110)
	edge.BorderSizePixel = 0
	edge.Rotation = -18
	edge.Parent = c

	return c
end

local function makeLogIcon(parent, s)
	local c = makeIconContainer(parent, s)
	local barrel = Instance.new("Frame")
	barrel.AnchorPoint = Vector2.new(0.5, 0.5)
	barrel.Position = UDim2.new(0.5, 0, 0.5, 0)
	barrel.Size = UDim2.fromOffset(math.floor(s * 0.55), math.floor(s * 0.50))
	barrel.BackgroundColor3 = Color3.fromRGB(164, 113, 72)
	barrel.BorderSizePixel = 0
	barrel.Parent = c
	stroke(barrel, 1, OUTLINE)

	local left = Instance.new("Frame")
	left.AnchorPoint = Vector2.new(1, 0.5)
	left.Position = UDim2.new(0.5, math.floor(-s * 0.27), 0.5, 0)
	left.Size = UDim2.fromOffset(math.floor(s * 0.32), math.floor(s * 0.50))
	left.BackgroundColor3 = Color3.fromRGB(122, 79, 43)
	left.BorderSizePixel = 0
	left.Parent = c
	local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(1, 0); lc.Parent = left
	stroke(left, 1, OUTLINE)

	local right = Instance.new("Frame")
	right.AnchorPoint = Vector2.new(0, 0.5)
	right.Position = UDim2.new(0.5, math.floor(s * 0.27), 0.5, 0)
	right.Size = UDim2.fromOffset(math.floor(s * 0.28), math.floor(s * 0.50))
	right.BackgroundColor3 = Color3.fromRGB(122, 79, 43)
	right.BorderSizePixel = 0
	right.Parent = c
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = right
	stroke(right, 1, OUTLINE)

	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.new(0.55, 0, 0.55, 0)
	ring.BackgroundColor3 = Color3.fromRGB(90, 56, 25)
	ring.BorderSizePixel = 0
	ring.Parent = right
	local rgc = Instance.new("UICorner"); rgc.CornerRadius = UDim.new(1, 0); rgc.Parent = ring
	return c
end

local function makeDropIcon(parent, s)
	local c = makeIconContainer(parent, s)
	local round = Instance.new("Frame")
	round.AnchorPoint = Vector2.new(0.5, 0.5)
	round.Position = UDim2.new(0.5, 0, 0.62, 0)
	round.Size = UDim2.fromOffset(math.floor(s * 0.62), math.floor(s * 0.62))
	round.BackgroundColor3 = Color3.fromRGB(74, 144, 200)
	round.BorderSizePixel = 0
	round.Parent = c
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = round
	stroke(round, 1, OUTLINE)

	local point = Instance.new("Frame")
	point.AnchorPoint = Vector2.new(0.5, 0.5)
	point.Position = UDim2.new(0.5, 0, 0.36, 0)
	point.Size = UDim2.fromOffset(math.floor(s * 0.42), math.floor(s * 0.42))
	point.BackgroundColor3 = Color3.fromRGB(74, 144, 200)
	point.BorderSizePixel = 0
	point.Rotation = 45
	point.Parent = c
	stroke(point, 1, OUTLINE)
	return c
end

local function makeFishIcon(parent, s)
	local c = makeIconContainer(parent, s)
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.new(0.55, 0, 0.5, 0)
	body.Size = UDim2.fromOffset(math.floor(s * 0.62), math.floor(s * 0.40))
	body.BackgroundColor3 = Color3.fromRGB(201, 122, 58)
	body.BorderSizePixel = 0
	body.Parent = c
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0.5, 0); bc.Parent = body
	stroke(body, 1, OUTLINE)

	local tail = Instance.new("Frame")
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.22, 0, 0.5, 0)
	tail.Size = UDim2.fromOffset(math.floor(s * 0.30), math.floor(s * 0.30))
	tail.BackgroundColor3 = Color3.fromRGB(168, 90, 34)
	tail.BorderSizePixel = 0
	tail.Rotation = 45
	tail.Parent = c
	stroke(tail, 1, OUTLINE)

	local eye = Instance.new("Frame")
	eye.AnchorPoint = Vector2.new(0.5, 0.5)
	eye.Position = UDim2.new(0.74, 0, 0.46, 0)
	eye.Size = UDim2.fromOffset(math.max(2, math.floor(s * 0.06)), math.max(2, math.floor(s * 0.06)))
	eye.BackgroundColor3 = OUTLINE
	eye.BorderSizePixel = 0
	eye.Parent = c
	local ec = Instance.new("UICorner"); ec.CornerRadius = UDim.new(1, 0); ec.Parent = eye
	return c
end

local ICON_BUILDERS = {
	axe = makeAxeIcon, log = makeLogIcon, drop = makeDropIcon, fish = makeFishIcon,
}

-- ─── Singleton ScreenGui + container (built once on first show) ──────
local screenGui
local container

local function ensureGui()
	if screenGui and screenGui.Parent then return end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "OnboardingTooltipGui"
	screenGui.ResetOnSpawn = false
	-- IgnoreGuiInset = false so the GUI starts BELOW Roblox's top-bar
	-- (chat / menu / Roblox icon) instead of sliding under them. The
	-- previous value (true) had the tooltip clipping behind those
	-- buttons.
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 200
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	-- Top-left, anchored at (0, 0) plus the GUI inset margin. Width is
	-- a fixed offset; height auto-fits the active tooltip (one at a
	-- time). We don't ClipsDescendants so the slide-in tween starts
	-- fully off-screen above the container without showing a sliver.
	container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0, 0)
	container.Position = UDim2.fromOffset(MARGIN_X, MARGIN_Y)
	container.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = screenGui
end

-- ─── One tooltip at a time ────────────────────────────────────────────
local activeHandle

-- ─── Build the static panel ───────────────────────────────────────────
local function buildPanel(opts)
	ensureGui()

	local panel = Instance.new("Frame")
	panel.Name = "Tooltip"
	panel.Size = UDim2.new(1, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	-- Park off-screen above; slide-in tweens into the resting Y=0
	-- (i.e. the container's anchor).
	panel.Position = UDim2.fromOffset(0, -SLIDE_OFFSET_Y)
	panel.BackgroundColor3 = COLOR_WOOD_BASE
	panel.BorderSizePixel = 0
	panel.Parent = container
	corner(panel, 18)
	stroke(panel, 3, COLOR_WOOD_DARK)
	pad(panel, 14)

	-- Vertical stack inside the panel: header row, then body card.
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 10)
	listLayout.Parent = panel

	-- ── Header row ────────────────────────────────────────────────────
	-- Horizontal stack: 56-px paper icon box + text column. Width
	-- math reserves a 32-px slot on the right for the close button so
	-- the title doesn't sit underneath it.
	local CLOSE_RESERVE = 34
	local HEADER_H = 56

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.Parent = panel

	-- Icon box: paper-fill, wood-dark border, RADIUS_MD corner. The
	-- background + stroke only show for kind-built icons (axe / log /
	-- drop / fish). A custom iconImage usually ships its own framed
	-- art, so we drop the chrome and let the asset fill the slot
	-- edge-to-edge.
	local iconBox = Instance.new("Frame")
	iconBox.Name = "IconBox"
	iconBox.AnchorPoint = Vector2.new(0, 0.5)
	iconBox.Position = UDim2.new(0, 0, 0.5, 0)
	iconBox.Size = UDim2.fromOffset(56, 56)
	iconBox.BorderSizePixel = 0
	iconBox.Parent = header

	local hasCustomImage = typeof(opts.iconImage) == "string" and opts.iconImage ~= ""
	if hasCustomImage then
		iconBox.BackgroundTransparency = 1
	else
		iconBox.BackgroundColor3 = COLOR_PAPER
		corner(iconBox, 12)
		stroke(iconBox, 2, COLOR_WOOD_DARK)
	end

	-- Render the icon: rbxassetid wins over iconKind.
	if hasCustomImage then
		local img = Instance.new("ImageLabel")
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		-- Fill the slot — the asset's own art has the rounded
		-- border baked in.
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.Image = opts.iconImage
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = iconBox
	else
		local builder = ICON_BUILDERS[opts.iconKind]
		if builder then
			builder(iconBox, 40)
		end
	end

	-- Text column: eyebrow + title stacked.
	local titles = Instance.new("Frame")
	titles.Name = "Titles"
	titles.AnchorPoint = Vector2.new(0, 0.5)
	titles.Position = UDim2.new(0, 56 + 12, 0.5, 0)
	titles.Size = UDim2.new(1, -(56 + 12 + CLOSE_RESERVE), 1, 0)
	titles.BackgroundTransparency = 1
	titles.BorderSizePixel = 0
	titles.Parent = header

	local eyebrow = Instance.new("TextLabel")
	eyebrow.Name = "Eyebrow"
	eyebrow.AnchorPoint = Vector2.new(0, 0)
	eyebrow.Position = UDim2.fromOffset(0, 4)
	eyebrow.Size = UDim2.new(1, 0, 0, 14)
	eyebrow.BackgroundTransparency = 1
	eyebrow.BorderSizePixel = 0
	eyebrow.Font = FONT_TITLE
	eyebrow.TextSize = 11
	eyebrow.TextColor3 = COLOR_WOOD_DARKEST
	eyebrow.TextTransparency = 0.3
	eyebrow.TextXAlignment = Enum.TextXAlignment.Left
	eyebrow.TextYAlignment = Enum.TextYAlignment.Top
	eyebrow.Text = string.upper(tostring(opts.eyebrow or "HINT"))
	eyebrow.Parent = titles

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0, 0)
	title.Position = UDim2.fromOffset(0, 22)
	title.Size = UDim2.new(1, 0, 0, 26)
	title.BackgroundTransparency = 1
	title.BorderSizePixel = 0
	title.Font = FONT_TITLE
	title.TextSize = 20
	title.TextColor3 = COLOR_WOOD_DARKEST
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = tostring(opts.title or "")
	title.Parent = titles

	-- ── Close button ──────────────────────────────────────────────────
	local closeBtn
	if opts.showClose ~= false then
		closeBtn = Instance.new("TextButton")
		closeBtn.Name = "Close"
		closeBtn.AnchorPoint = Vector2.new(1, 0)
		closeBtn.Position = UDim2.new(1, 0, 0, 0)
		closeBtn.Size = UDim2.fromOffset(26, 26)
		closeBtn.BackgroundColor3 = COLOR_WOOD_MID
		closeBtn.BorderSizePixel = 0
		closeBtn.AutoButtonColor = false
		closeBtn.Font = FONT_TITLE
		closeBtn.TextSize = 14
		closeBtn.TextColor3 = COLOR_PAPER_LIGHT
		closeBtn.Text = "✕"
		closeBtn.Parent = header
		corner(closeBtn, 8)
		stroke(closeBtn, 2, COLOR_WOOD_DARK)
		closeBtn.MouseEnter:Connect(function()
			closeBtn.BackgroundColor3 = COLOR_WOOD_DARK
		end)
		closeBtn.MouseLeave:Connect(function()
			closeBtn.BackgroundColor3 = COLOR_WOOD_MID
		end)
	end

	-- ── Body card ─────────────────────────────────────────────────────
	-- Paper-fill rounded card. UIListLayout vertical stacks bodyText +
	-- progressWrap. AutomaticSize.Y on the body grows the panel's
	-- overall height naturally.
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.LayoutOrder = 2
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundColor3 = COLOR_PAPER
	body.BorderSizePixel = 0
	body.Parent = panel
	corner(body, 12)
	stroke(body, 2, COLOR_WOOD_DARK)

	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingTop    = UDim.new(0, 12)
	bodyPad.PaddingBottom = UDim.new(0, 12)
	bodyPad.PaddingLeft   = UDim.new(0, 14)
	bodyPad.PaddingRight  = UDim.new(0, 14)
	bodyPad.Parent = body

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.FillDirection = Enum.FillDirection.Vertical
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 10)
	bodyLayout.Parent = body

	local bodyText = Instance.new("TextLabel")
	bodyText.Name = "BodyText"
	bodyText.LayoutOrder = 1
	bodyText.Size = UDim2.new(1, 0, 0, 0)
	bodyText.AutomaticSize = Enum.AutomaticSize.Y
	bodyText.BackgroundTransparency = 1
	bodyText.BorderSizePixel = 0
	bodyText.Font = FONT_BODY
	bodyText.TextSize = 15
	bodyText.TextColor3 = Color3.fromRGB(46, 29, 16)
	bodyText.TextXAlignment = Enum.TextXAlignment.Left
	bodyText.TextYAlignment = Enum.TextYAlignment.Top
	bodyText.TextWrapped = true
	bodyText.RichText = true
	bodyText.LineHeight = 1.25
	bodyText.Text = tostring(opts.body or "")
	bodyText.Parent = body

	-- ── Progress pill (only when goal is set) ─────────────────────────
	local progressFill, progressLabel, goalRaw
	goalRaw = tonumber(opts.goal)
	local goal = (goalRaw and goalRaw > 0) and math.floor(goalRaw) or nil
	if goal then
		local progressWrap = Instance.new("Frame")
		progressWrap.Name = "ProgressWrap"
		progressWrap.LayoutOrder = 2
		progressWrap.Size = UDim2.new(1, 0, 0, 14)
		progressWrap.BackgroundTransparency = 1
		progressWrap.BorderSizePixel = 0
		progressWrap.Parent = body

		local LABEL_W = 44
		local LABEL_GAP = 10

		local track = Instance.new("Frame")
		track.AnchorPoint = Vector2.new(0, 0.5)
		track.Position = UDim2.new(0, 0, 0.5, 0)
		track.Size = UDim2.new(1, -(LABEL_W + LABEL_GAP), 1, 0)
		track.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		track.BackgroundTransparency = 0.82
		track.BorderSizePixel = 0
		track.ClipsDescendants = true
		track.Parent = progressWrap
		corner(track, 999)
		stroke(track, 2, COLOR_WOOD_DARK)

		progressFill = Instance.new("Frame")
		progressFill.AnchorPoint = Vector2.new(0, 0.5)
		progressFill.Position = UDim2.new(0, 0, 0.5, 0)
		progressFill.Size = UDim2.new(0, 0, 1, 0)
		progressFill.BackgroundColor3 = COLOR_GREEN
		progressFill.BorderSizePixel = 0
		progressFill.Parent = track
		local fillGrad = Instance.new("UIGradient")
		fillGrad.Rotation = 90
		fillGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,   COLOR_GREEN_LIGHT),
			ColorSequenceKeypoint.new(0.6, COLOR_GREEN),
			ColorSequenceKeypoint.new(1,   COLOR_GREEN_DARK),
		})
		fillGrad.Parent = progressFill

		progressLabel = Instance.new("TextLabel")
		progressLabel.AnchorPoint = Vector2.new(1, 0.5)
		progressLabel.Position = UDim2.new(1, 0, 0.5, 0)
		progressLabel.Size = UDim2.fromOffset(LABEL_W, 16)
		progressLabel.BackgroundTransparency = 1
		progressLabel.BorderSizePixel = 0
		progressLabel.Font = FONT_TITLE
		progressLabel.TextSize = 14
		progressLabel.TextColor3 = COLOR_WOOD_DARK
		progressLabel.TextXAlignment = Enum.TextXAlignment.Right
		progressLabel.TextYAlignment = Enum.TextYAlignment.Center
		progressLabel.Text = "0/" .. tostring(goal)
		progressLabel.Parent = progressWrap
	end

	return {
		panel         = panel,
		closeBtn      = closeBtn,
		progressFill  = progressFill,
		progressLabel = progressLabel,
		goal          = goal,
	}
end

-- ─── Public API ───────────────────────────────────────────────────────
local function showOnboardingTip(opts)
	opts = opts or {}

	if activeHandle and activeHandle.dismiss then
		activeHandle.dismiss()
	end

	local refs = buildPanel(opts)
	local handle = { instance = refs.panel }

	local currentProgress = 0
	local completed = false
	local dismissing = false

	-- Slide in: simple Position tween. Same easing as QuestNotification.
	TweenService:Create(refs.panel,
		TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(0, 0) }):Play()

	function handle.setProgress(n)
		if not refs.goal or not refs.progressFill then return end
		local clamped = math.clamp(tonumber(n) or 0, 0, refs.goal)
		if clamped == currentProgress then return end
		currentProgress = clamped
		local pct = clamped / refs.goal
		TweenService:Create(refs.progressFill,
			TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.new(pct, 0, 1, 0) }):Play()
		if refs.progressLabel then
			refs.progressLabel.Text = string.format("%d/%d", clamped, refs.goal)
			refs.progressLabel.TextColor3 = (clamped >= refs.goal) and COLOR_GREEN or COLOR_WOOD_DARK
		end
	end

	function handle.complete()
		if completed then return end
		completed = true
		if refs.goal then handle.setProgress(refs.goal) end
		if typeof(opts.onComplete) == "function" then task.spawn(opts.onComplete) end
		local delaySec = tonumber(opts.autoDismissAfterComplete)
		if delaySec and delaySec > 0 then
			task.delay(delaySec, function()
				if not dismissing then handle.dismiss() end
			end)
		end
	end

	function handle.dismiss()
		if dismissing then return end
		dismissing = true
		if not refs.panel or not refs.panel.Parent then
			if typeof(opts.onDismiss) == "function" then task.spawn(opts.onDismiss) end
			if activeHandle == handle then activeHandle = nil end
			return
		end

		local outTween = TweenService:Create(refs.panel,
			TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.fromOffset(0, -SLIDE_OFFSET_Y) })
		outTween:Play()
		outTween.Completed:Once(function()
			if refs.panel and refs.panel.Parent then refs.panel:Destroy() end
			refs.panel = nil
			if activeHandle == handle then activeHandle = nil end
			if typeof(opts.onDismiss) == "function" then task.spawn(opts.onDismiss) end
		end)
	end

	-- Apply starting progress without tween so the entrance doesn't
	-- fight a 0.5 s width tween on first paint.
	if refs.goal and refs.progressFill then
		local startN = math.clamp(tonumber(opts.progress) or 0, 0, refs.goal)
		currentProgress = startN
		refs.progressFill.Size = UDim2.new(startN / refs.goal, 0, 1, 0)
		if refs.progressLabel then
			refs.progressLabel.Text = string.format("%d/%d", startN, refs.goal)
			refs.progressLabel.TextColor3 = (startN >= refs.goal) and COLOR_GREEN or COLOR_WOOD_DARK
		end
	end

	if refs.closeBtn then
		refs.closeBtn.MouseButton1Click:Connect(function()
			handle.dismiss()
		end)
	end

	activeHandle = handle
	return handle
end

_G.ShowOnboardingTip = showOnboardingTip
