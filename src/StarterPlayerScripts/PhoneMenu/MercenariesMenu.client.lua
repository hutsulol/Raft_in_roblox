-- MercenariesMenu.client.lua
-- Full-page mercenary roster inside the Phone menu.
-- Opens when the player clicks the MERCENARIES button on the phone.
-- Genshin-style layout: character selector at top, 3D model in center,
-- menu buttons on the left, stats panel on the right, gradient background
-- tinted to the character's primary colour.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ─── Wait for PhoneMenu to expose its root ──────────────────────────────
local TIMEOUT = 30
local waited  = 0
while not _G.PhoneMenuRoot and waited < TIMEOUT do
	task.wait(0.25)
	waited += 0.25
end
local phoneRoot = _G.PhoneMenuRoot
if not phoneRoot then
	warn("[MercenariesMenu] PhoneMenuRoot not available")
	return
end

-- ─── Theme ──────────────────────────────────────────────────────────────
local COLOR_PANEL      = Color3.fromRGB(10, 25, 55)
local COLOR_PANEL_EDGE = Color3.fromRGB(80, 180, 255)
local COLOR_ACCENT     = Color3.fromRGB(120, 210, 255)
local COLOR_TEXT       = Color3.fromRGB(220, 240, 255)
local COLOR_TEXT_DIM   = Color3.fromRGB(140, 180, 220)
local COLOR_BAR_BG     = Color3.fromRGB(15, 35, 70)
local COLOR_BAR_FILL   = Color3.fromRGB(90, 200, 255)
local FONT_TITLE       = Enum.Font.GothamBold
local FONT_BODY        = Enum.Font.Gotham

local IDLE_ANIMATION_ID = "rbxassetid://78578604994580"

-- Per-mercenary theme colours (gradient + accent).
-- The background uses a radial-style two-colour UIGradient.
local MERC_THEMES = {
	["Pirate lvl1"] = {
		gradientTop    = Color3.fromRGB(35, 8, 12),
		gradientBottom = Color3.fromRGB(120, 20, 30),
		accent         = Color3.fromRGB(255, 80, 80),
		displayName    = "Pirate",
		stars          = 1,
		stats          = { hp = 100, damage = 15, mana = "20/min" },
	},
}
-- Fallback for unknown pirate types
local DEFAULT_THEME = {
	gradientTop    = Color3.fromRGB(10, 15, 35),
	gradientBottom = Color3.fromRGB(30, 50, 100),
	accent         = COLOR_ACCENT,
	displayName    = "Unknown",
	stars          = 1,
	stats          = { hp = 50, damage = 5, mana = "0/min" },
}

-- ─── Small UI helpers ───────────────────────────────────────────────────

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
end

local function stroke(parent, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness       = thickness or 1.5
	s.Color           = color or COLOR_PANEL_EDGE
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent          = parent
end

-- ─── State ──────────────────────────────────────────────────────────────
local page            = nil   -- the full-page Frame
local currentMerc     = nil   -- selected mercenary name
local viewportWorld   = nil
local viewportModel   = nil
local viewportCamera  = nil

-- ─── Build the 3D viewport for a mercenary model ────────────────────────

local function buildMercViewport(parent, mercName)
	-- ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = "MercViewport"
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.55)
	vp.Size = UDim2.fromOffset(360, 480)
	vp.BackgroundTransparency = 1
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-0.3, -1, -0.5)
	vp.Ambient = Color3.fromRGB(180, 200, 230)
	vp.Parent = parent

	local world = Instance.new("WorldModel")
	world.Parent = vp
	viewportWorld = world

	local cam = Instance.new("Camera")
	cam.FieldOfView = 50
	cam.CFrame = CFrame.new(Vector3.new(0, 2.2, 6.2), Vector3.new(0, 1.2, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	viewportCamera = cam

	-- Clone pirate template from ReplicatedStorage
	local template = ReplicatedStorage:FindFirstChild(mercName)
	if not template then
		warn("[MercenariesMenu] Template not found:", mercName)
		return vp
	end

	local wasArchivable = template.Archivable
	template.Archivable = true
	local clone = template:Clone()
	template.Archivable = wasArchivable

	-- Strip scripts
	for _, d in clone:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("Highlight") or d:IsA("SelectionBox") then
			d:Destroy()
		end
	end

	-- Configure humanoid
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local animator
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.EvaluateStateMachine = false
		for _, state in Enum.HumanoidStateType:GetEnumItems() do
			pcall(function() humanoid:SetStateEnabled(state, false) end)
		end
		animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end

	-- Physics setup
	local hrp = clone:FindFirstChild("HumanoidRootPart")
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Massless = true
			d.Anchored = (d == hrp)
		end
	end

	-- Position and rotate
	clone:PivotTo(CFrame.new(0, 0.5, 0) * CFrame.Angles(0, math.pi, 0))

	-- Play idle animation
	if animator then
		local anim = Instance.new("Animation")
		anim.AnimationId = IDLE_ANIMATION_ID
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0)
	end

	-- Lighting (same 3-point setup as PhoneMenu)
	local rootPart = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
	if rootPart and rootPart:IsA("BasePart") then
		local keyAtt = Instance.new("Attachment")
		keyAtt.Position = Vector3.new(0, 2, 4)
		keyAtt.Parent = rootPart
		local keyLight = Instance.new("PointLight")
		keyLight.Color = Color3.fromRGB(255, 255, 255)
		keyLight.Brightness = 2
		keyLight.Range = 16
		keyLight.Shadows = false
		keyLight.Parent = keyAtt

		local rimAtt = Instance.new("Attachment")
		rimAtt.Position = Vector3.new(0, 2, -4)
		rimAtt.Parent = rootPart
		local rimLight = Instance.new("PointLight")
		rimLight.Color = Color3.fromRGB(255, 100, 100)
		rimLight.Brightness = 2
		rimLight.Range = 14
		rimLight.Shadows = false
		rimLight.Parent = rimAtt

		local fillAtt = Instance.new("Attachment")
		fillAtt.Position = Vector3.new(-2, -1, 3)
		fillAtt.Parent = rootPart
		local fillLight = Instance.new("PointLight")
		fillLight.Color = Color3.fromRGB(180, 210, 255)
		fillLight.Brightness = 1
		fillLight.Range = 12
		fillLight.Shadows = false
		fillLight.Parent = fillAtt
	end

	clone.Parent = world
	viewportModel = clone

	return vp
end

-- ─── Build the full page ────────────────────────────────────────────────

local selectorCircles = {}  -- references to top-bar circles for highlight

local function buildPage(mercNames)
	if page then page:Destroy() end

	local selectedIndex = 1
	local selectedName  = mercNames[1]
	local theme         = MERC_THEMES[selectedName] or DEFAULT_THEME

	-- ── Full-page container ──────────────────────────────────────────
	page = Instance.new("Frame")
	page.Name = "MercenariesPage"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundColor3 = theme.gradientTop
	page.BorderSizePixel = 0
	page.ZIndex = 50
	page.Parent = phoneRoot

	-- Gradient background
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(theme.gradientTop, theme.gradientBottom)
	gradient.Rotation = 180  -- top darker, bottom lighter
	gradient.Parent = page

	-- ── Top bar: character selector ──────────────────────────────────
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.BackgroundTransparency = 1
	topBar.Size = UDim2.new(1, 0, 0, 56)
	topBar.Position = UDim2.fromOffset(0, 0)
	topBar.Parent = page

	-- Back button
	local backBtn = Instance.new("TextButton")
	backBtn.Name = "BackButton"
	backBtn.BackgroundColor3 = COLOR_BAR_BG
	backBtn.BackgroundTransparency = 0.3
	backBtn.BorderSizePixel = 0
	backBtn.Size = UDim2.fromOffset(70, 36)
	backBtn.Position = UDim2.fromOffset(12, 10)
	backBtn.Font = FONT_TITLE
	backBtn.TextSize = 16
	backBtn.TextColor3 = COLOR_ACCENT
	backBtn.Text = "← Back"
	backBtn.AutoButtonColor = true
	backBtn.ZIndex = 51
	backBtn.Parent = topBar
	corner(backBtn, 8)

	-- Character circles (centered in the top bar)
	local circleSize = 42
	local circleGap = 8
	local totalW = #mercNames * circleSize + (#mercNames - 1) * circleGap
	local startX = math.floor((0.5 * 1000) - totalW / 2)  -- approximate; use UDim2 centering

	local circleContainer = Instance.new("Frame")
	circleContainer.BackgroundTransparency = 1
	circleContainer.AnchorPoint = Vector2.new(0.5, 0)
	circleContainer.Position = UDim2.new(0.5, 0, 0, 7)
	circleContainer.Size = UDim2.fromOffset(totalW, circleSize)
	circleContainer.ZIndex = 51
	circleContainer.Parent = topBar

	selectorCircles = {}
	for i, name in mercNames do
		local circleTheme = MERC_THEMES[name] or DEFAULT_THEME

		local circle = Instance.new("Frame")
		circle.Name = "Circle_" .. name
		circle.BackgroundColor3 = circleTheme.accent
		circle.BackgroundTransparency = 0.3
		circle.BorderSizePixel = 0
		circle.Size = UDim2.fromOffset(circleSize, circleSize)
		circle.Position = UDim2.fromOffset((i - 1) * (circleSize + circleGap), 0)
		circle.ZIndex = 51
		circle.Parent = circleContainer
		corner(circle, circleSize / 2) -- fully round

		-- Selection ring
		local ring = Instance.new("UIStroke")
		ring.Thickness = i == selectedIndex and 3 or 1.5
		ring.Color = i == selectedIndex and Color3.fromRGB(255, 255, 255) or COLOR_PANEL_EDGE
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = circle

		-- Name initial
		local initLabel = Instance.new("TextLabel")
		initLabel.BackgroundTransparency = 1
		initLabel.Size = UDim2.fromScale(1, 1)
		initLabel.Font = FONT_TITLE
		initLabel.TextSize = 18
		initLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		initLabel.Text = string.sub(circleTheme.displayName, 1, 1)
		initLabel.ZIndex = 52
		initLabel.Parent = circle

		-- Click handler for circle
		local clickBtn = Instance.new("TextButton")
		clickBtn.BackgroundTransparency = 1
		clickBtn.Size = UDim2.fromScale(1, 1)
		clickBtn.Text = ""
		clickBtn.ZIndex = 53
		clickBtn.Parent = circle

		selectorCircles[i] = { frame = circle, ring = ring, name = name }
	end

	-- ── Left side: menu buttons (visual only) ────────────────────────
	local leftPanel = Instance.new("Frame")
	leftPanel.Name = "LeftMenu"
	leftPanel.BackgroundTransparency = 1
	leftPanel.Size = UDim2.fromOffset(200, 260)
	leftPanel.Position = UDim2.new(0, 20, 0.5, -100)
	leftPanel.ZIndex = 51
	leftPanel.Parent = page

	local menuItems = {
		"Characteristics",
		"Current Tasks",
		"Equipment",
		"Mutation",
		"About character",
	}

	for i, itemText in menuItems do
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 32)
		row.Position = UDim2.fromOffset(0, (i - 1) * 40)
		row.Font = FONT_BODY
		row.TextSize = 17
		row.TextColor3 = COLOR_TEXT
		row.Text = "◇ " .. itemText
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.ZIndex = 51
		row.Parent = leftPanel
	end

	-- ── Right side: stats panel ──────────────────────────────────────
	local rightPanel = Instance.new("Frame")
	rightPanel.Name = "RightStats"
	rightPanel.BackgroundColor3 = COLOR_PANEL
	rightPanel.BackgroundTransparency = 0.4
	rightPanel.BorderSizePixel = 0
	rightPanel.AnchorPoint = Vector2.new(1, 0)
	rightPanel.Size = UDim2.fromOffset(260, 320)
	rightPanel.Position = UDim2.new(1, -20, 0, 70)
	rightPanel.ZIndex = 51
	rightPanel.Parent = page
	corner(rightPanel, 10)

	local rPad = Instance.new("UIPadding")
	rPad.PaddingTop    = UDim.new(0, 16)
	rPad.PaddingBottom = UDim.new(0, 16)
	rPad.PaddingLeft   = UDim.new(0, 18)
	rPad.PaddingRight  = UDim.new(0, 18)
	rPad.Parent = rightPanel

	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 28)
	nameLabel.Position = UDim2.fromOffset(0, 0)
	nameLabel.Font = FONT_TITLE
	nameLabel.TextSize = 22
	nameLabel.TextColor3 = COLOR_TEXT
	nameLabel.Text = theme.displayName
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 52
	nameLabel.Parent = rightPanel

	-- Stars
	local starsText = string.rep("★", theme.stars) .. string.rep("☆", 6 - theme.stars)
	local starsLabel = Instance.new("TextLabel")
	starsLabel.BackgroundTransparency = 1
	starsLabel.Size = UDim2.new(1, 0, 0, 20)
	starsLabel.Position = UDim2.fromOffset(0, 30)
	starsLabel.Font = FONT_BODY
	starsLabel.TextSize = 16
	starsLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	starsLabel.Text = starsText
	starsLabel.TextXAlignment = Enum.TextXAlignment.Left
	starsLabel.ZIndex = 52
	starsLabel.Parent = rightPanel

	-- Level label
	local levelLabel = Instance.new("TextLabel")
	levelLabel.BackgroundTransparency = 1
	levelLabel.Size = UDim2.new(1, 0, 0, 22)
	levelLabel.Position = UDim2.fromOffset(0, 56)
	levelLabel.Font = FONT_TITLE
	levelLabel.TextSize = 17
	levelLabel.TextColor3 = COLOR_TEXT
	levelLabel.Text = "Level 1"
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.ZIndex = 52
	levelLabel.Parent = rightPanel

	-- XP bar
	local xpBarBg = Instance.new("Frame")
	xpBarBg.BackgroundColor3 = COLOR_BAR_BG
	xpBarBg.BorderSizePixel = 0
	xpBarBg.Size = UDim2.new(1, 0, 0, 12)
	xpBarBg.Position = UDim2.fromOffset(0, 82)
	xpBarBg.ZIndex = 52
	xpBarBg.Parent = rightPanel
	corner(xpBarBg, 6)

	local xpFill = Instance.new("Frame")
	xpFill.BackgroundColor3 = theme.accent
	xpFill.BorderSizePixel = 0
	xpFill.Size = UDim2.new(0, 0, 1, 0) -- 0/100
	xpFill.ZIndex = 53
	xpFill.Parent = xpBarBg
	corner(xpFill, 6)

	local xpLabel = Instance.new("TextLabel")
	xpLabel.BackgroundTransparency = 1
	xpLabel.Size = UDim2.new(1, 0, 0, 14)
	xpLabel.Position = UDim2.fromOffset(0, 96)
	xpLabel.Font = FONT_BODY
	xpLabel.TextSize = 12
	xpLabel.TextColor3 = COLOR_TEXT_DIM
	xpLabel.Text = "0/100"
	xpLabel.TextXAlignment = Enum.TextXAlignment.Right
	xpLabel.ZIndex = 52
	xpLabel.Parent = rightPanel

	-- Stat rows
	local statDefs = {
		{ label = "Max HP",            value = tostring(theme.stats.hp)     },
		{ label = "Damage",            value = tostring(theme.stats.damage) },
		{ label = "Mana consumption",  value = theme.stats.mana            },
	}

	local statY = 124
	for _, def in statDefs do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 26)
		row.Position = UDim2.fromOffset(0, statY)
		row.ZIndex = 52
		row.Parent = rightPanel

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(0.6, 0, 1, 0)
		lbl.Font = FONT_BODY
		lbl.TextSize = 14
		lbl.TextColor3 = COLOR_TEXT_DIM
		lbl.Text = def.label
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.ZIndex = 52
		lbl.Parent = row

		local val = Instance.new("TextLabel")
		val.BackgroundTransparency = 1
		val.Size = UDim2.new(0.4, 0, 1, 0)
		val.AnchorPoint = Vector2.new(1, 0)
		val.Position = UDim2.new(1, 0, 0, 0)
		val.Font = FONT_TITLE
		val.TextSize = 15
		val.TextColor3 = COLOR_TEXT
		val.Text = def.value
		val.TextXAlignment = Enum.TextXAlignment.Right
		val.ZIndex = 52
		val.Parent = row

		statY += 30
	end

	-- ── Center: 3D character viewport ────────────────────────────────
	buildMercViewport(page, selectedName)

	-- ── Fade-in animation ────────────────────────────────────────────
	page.BackgroundTransparency = 1
	-- Fade all descendants in
	for _, desc in page:GetDescendants() do
		if desc:IsA("TextLabel") or desc:IsA("TextButton") then
			desc.TextTransparency = 1
		elseif desc:IsA("Frame") and desc ~= page then
			desc.BackgroundTransparency = 1
		elseif desc:IsA("ViewportFrame") then
			desc.ImageTransparency = 1
		end
	end

	-- Tween everything in
	TweenService:Create(page, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
	for _, desc in page:GetDescendants() do
		if desc:IsA("TextLabel") or desc:IsA("TextButton") then
			TweenService:Create(desc, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		elseif desc:IsA("Frame") and desc.Name == "RightStats" then
			TweenService:Create(desc, TweenInfo.new(0.3), { BackgroundTransparency = 0.4 }):Play()
		elseif desc:IsA("ViewportFrame") then
			TweenService:Create(desc, TweenInfo.new(0.3), { ImageTransparency = 0 }):Play()
		end
	end

	-- Bar backgrounds need to become visible
	TweenService:Create(xpBarBg, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(xpFill, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()

	-- ── Back button handler ──────────────────────────────────────────
	backBtn.MouseButton1Click:Connect(function()
		closePage()
	end)
end

-- ─── Close the page ─────────────────────────────────────────────────────

function closePage()
	if not page then return end

	local p = page
	page = nil

	-- Fade out
	TweenService:Create(p, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
	for _, desc in p:GetDescendants() do
		if desc:IsA("TextLabel") or desc:IsA("TextButton") then
			TweenService:Create(desc, TweenInfo.new(0.2), {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			}):Play()
		elseif desc:IsA("Frame") then
			TweenService:Create(desc, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		elseif desc:IsA("ViewportFrame") then
			TweenService:Create(desc, TweenInfo.new(0.2), { ImageTransparency = 1 }):Play()
		elseif desc:IsA("UIStroke") then
			TweenService:Create(desc, TweenInfo.new(0.2), { Transparency = 1 }):Play()
		end
	end

	task.delay(0.25, function()
		p:Destroy()
		viewportModel = nil
		viewportWorld = nil
		viewportCamera = nil
	end)
end

-- ─── Open handler (called via _G by PhoneMenu) ─────────────────────────

local function openMercenariesMenu()
	if page then return end

	-- Read recruited mercenaries from the replicated Folder
	local folder = player:FindFirstChild("Mercenaries")
	local mercNames = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("StringValue") then
				table.insert(mercNames, child.Value)
			end
		end
	end

	if #mercNames == 0 then
		-- No mercenaries recruited — show empty state briefly
		-- For now, just return; later we can show a message
		return
	end

	buildPage(mercNames)
end

_G.OpenMercenariesMenu = openMercenariesMenu
