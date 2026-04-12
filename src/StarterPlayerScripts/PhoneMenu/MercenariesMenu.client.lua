-- MercenariesMenu.client.lua
-- Full-page mercenary roster inside the Phone menu.
-- Opens when the player clicks the MERCENARIES button on the phone.
-- Genshin-style layout: character selector at top, 3D model in center,
-- menu buttons on the left, stats panel on the right.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ─── Wait for SpawnMercenary remote ─────────────────────────────────────
local spawnEvent = ReplicatedStorage:WaitForChild("SpawnMercenary", 30)

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

-- ─── Theme (matches PhoneMenu) ──────────────────────────────────────────
local COLOR_BG         = Color3.fromRGB(5, 15, 35)
local COLOR_PANEL      = Color3.fromRGB(10, 25, 55)
local COLOR_PANEL_EDGE = Color3.fromRGB(80, 180, 255)
local COLOR_ACCENT     = Color3.fromRGB(120, 210, 255)
local COLOR_TEXT       = Color3.fromRGB(220, 240, 255)
local COLOR_TEXT_DIM   = Color3.fromRGB(140, 180, 220)
local COLOR_BAR_BG     = Color3.fromRGB(15, 35, 70)
local COLOR_BAR_FILL   = Color3.fromRGB(90, 200, 255)
local FONT_TITLE       = Enum.Font.GothamBold
local FONT_BODY        = Enum.Font.Gotham

local IDLE_ANIMATION_ID = "rbxassetid://107139405334393"

-- Per-mercenary data
local MERC_THEMES = {
	["Pirate lvl1"] = {
		accent      = Color3.fromRGB(255, 80, 80),
		displayName = "Pirate",
		stars       = 1,
		stats       = { hp = 100, damage = 15, mana = "20/min" },
		spawnModel  = "Pirate_2",
	},
}
local DEFAULT_THEME = {
	accent      = COLOR_ACCENT,
	displayName = "Unknown",
	stars       = 1,
	stats       = { hp = 50, damage = 5, mana = "0/min" },
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
local page = nil
local hiddenPanels = {} -- panels hidden while mercenaries page is open

-- Hide all phone-menu panels (direct children of root) except the
-- mercenaries page itself.
local function hidePhonePanels()
	hiddenPanels = {}
	for _, child in phoneRoot:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "MercenariesPage" and child.Visible then
			child.Visible = false
			table.insert(hiddenPanels, child)
		end
	end
end

local function showPhonePanels()
	for _, child in hiddenPanels do
		if child and child.Parent then
			child.Visible = true
		end
	end
	hiddenPanels = {}
end

-- ─── Build the 3D viewport for a mercenary model ────────────────────────

local function buildMercViewport(parent, mercName)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "MercViewport"
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.55)
	vp.Size = UDim2.fromOffset(360, 480)
	vp.BackgroundTransparency = 1
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-0.3, -1, -0.5)
	vp.Ambient = Color3.fromRGB(180, 200, 230)
	vp.ZIndex = 50
	vp.Parent = parent

	local world = Instance.new("WorldModel")
	world.Parent = vp

	local cam = Instance.new("Camera")
	cam.FieldOfView = 50
	cam.CFrame = CFrame.new(Vector3.new(0, 2.2, 6.2), Vector3.new(0, 1.2, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam

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

	-- Strip scripts and gameplay visuals
	for _, d in clone:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("Highlight") or d:IsA("SelectionBox") then
			d:Destroy()
		end
	end

	-- Ensure all parts are visible
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 0
			d.CanCollide = false
			d.Massless = true
		elseif d:IsA("Decal") then
			d.Transparency = 0
		end
	end

	-- Hide HumanoidRootPart — it's an invisible physics block that the
	-- "ensure visible" loop above accidentally made visible.
	local hrpPart = clone:FindFirstChild("HumanoidRootPart")
	if hrpPart then
		hrpPart.Transparency = 1
	end

	-- Configure humanoid for animation (keep it — AnimationController
	-- alone doesn't work for R6 in ViewportFrame)
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local animator
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		pcall(function() humanoid.EvaluateStateMachine = false end)
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

	-- Anchor root part, leave limbs unanchored for Motor6D animation
	local hrp = clone:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.Anchored = true
	else
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
	end

	-- Position and rotate to face camera
	clone:PivotTo(CFrame.new(0, 0.5, 0) * CFrame.Angles(0, math.pi, 0))

	-- Play idle animation
	if animator then
		pcall(function()
			local anim = Instance.new("Animation")
			anim.AnimationId = IDLE_ANIMATION_ID
			local track = animator:LoadAnimation(anim)
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Action
			track:Play(0)
		end)
	end

	clone.Parent = world

	-- 3-point lighting
	local lightRoot = clone:FindFirstChild("HumanoidRootPart")
		or clone:FindFirstChild("Torso")
		or clone.PrimaryPart
		or clone:FindFirstChildWhichIsA("BasePart", true)
	if lightRoot then
		local keyAtt = Instance.new("Attachment")
		keyAtt.Position = Vector3.new(0, 2, 4)
		keyAtt.Parent = lightRoot
		local keyLight = Instance.new("PointLight")
		keyLight.Color = Color3.fromRGB(255, 255, 255)
		keyLight.Brightness = 2
		keyLight.Range = 16
		keyLight.Shadows = false
		keyLight.Parent = keyAtt

		local rimAtt = Instance.new("Attachment")
		rimAtt.Position = Vector3.new(0, 2, -4)
		rimAtt.Parent = lightRoot
		local rimLight = Instance.new("PointLight")
		rimLight.Color = Color3.fromRGB(255, 100, 100)
		rimLight.Brightness = 2
		rimLight.Range = 14
		rimLight.Shadows = false
		rimLight.Parent = rimAtt

		local fillAtt = Instance.new("Attachment")
		fillAtt.Position = Vector3.new(-2, -1, 3)
		fillAtt.Parent = lightRoot
		local fillLight = Instance.new("PointLight")
		fillLight.Color = Color3.fromRGB(180, 210, 255)
		fillLight.Brightness = 1
		fillLight.Range = 12
		fillLight.Shadows = false
		fillLight.Parent = fillAtt
	end

	return vp
end

-- ─── Build the full page ────────────────────────────────────────────────

local function buildPage(mercNames)
	if page then page:Destroy() end

	local selectedName = mercNames[1]
	local theme        = MERC_THEMES[selectedName] or DEFAULT_THEME

	-- ── Full-page container (phone-style blue background) ────────────
	page = Instance.new("Frame")
	page.Name = "MercenariesPage"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundColor3 = COLOR_BG
	page.BackgroundTransparency = 0.15
	page.BorderSizePixel = 0
	page.ZIndex = 50
	page.Parent = phoneRoot

	-- Hide phone main panels so they don't show through
	hidePhonePanels()

	-- ── Top bar: character selector ──────────────────────────────────
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.BackgroundTransparency = 1
	topBar.Size = UDim2.new(1, 0, 0, 56)
	topBar.Position = UDim2.fromOffset(0, 0)
	topBar.ZIndex = 51
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
	backBtn.ZIndex = 52
	backBtn.Parent = topBar
	corner(backBtn, 8)

	-- Character circles (centered)
	local circleSize = 42
	local circleGap = 8
	local totalW = #mercNames * circleSize + (#mercNames - 1) * circleGap

	local circleContainer = Instance.new("Frame")
	circleContainer.BackgroundTransparency = 1
	circleContainer.AnchorPoint = Vector2.new(0.5, 0)
	circleContainer.Position = UDim2.new(0.5, 0, 0, 7)
	circleContainer.Size = UDim2.fromOffset(totalW, circleSize)
	circleContainer.ZIndex = 51
	circleContainer.Parent = topBar

	for i, name in mercNames do
		local cTheme = MERC_THEMES[name] or DEFAULT_THEME

		local circle = Instance.new("Frame")
		circle.BackgroundColor3 = cTheme.accent
		circle.BackgroundTransparency = 0.3
		circle.BorderSizePixel = 0
		circle.Size = UDim2.fromOffset(circleSize, circleSize)
		circle.Position = UDim2.fromOffset((i - 1) * (circleSize + circleGap), 0)
		circle.ZIndex = 52
		circle.Parent = circleContainer
		corner(circle, circleSize / 2)

		local ring = Instance.new("UIStroke")
		ring.Thickness = i == 1 and 3 or 1.5
		ring.Color = i == 1 and Color3.fromRGB(255, 255, 255) or COLOR_PANEL_EDGE
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = circle

		local initLabel = Instance.new("TextLabel")
		initLabel.BackgroundTransparency = 1
		initLabel.Size = UDim2.fromScale(1, 1)
		initLabel.Font = FONT_TITLE
		initLabel.TextSize = 18
		initLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		initLabel.Text = string.sub(cTheme.displayName, 1, 1)
		initLabel.ZIndex = 53
		initLabel.Parent = circle
	end

	-- ── Left side: menu buttons (visual only) ────────────────────────
	local leftPanel = Instance.new("Frame")
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
	local starsLabel = Instance.new("TextLabel")
	starsLabel.BackgroundTransparency = 1
	starsLabel.Size = UDim2.new(1, 0, 0, 20)
	starsLabel.Position = UDim2.fromOffset(0, 30)
	starsLabel.Font = FONT_BODY
	starsLabel.TextSize = 16
	starsLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	starsLabel.Text = string.rep("★", theme.stars) .. string.rep("☆", 6 - theme.stars)
	starsLabel.TextXAlignment = Enum.TextXAlignment.Left
	starsLabel.ZIndex = 52
	starsLabel.Parent = rightPanel

	-- Level
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
	xpFill.Size = UDim2.new(0, 0, 1, 0)
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
		{ label = "Max HP",           value = tostring(theme.stats.hp)     },
		{ label = "Damage",           value = tostring(theme.stats.damage) },
		{ label = "Mana consumption", value = theme.stats.mana            },
	}

	local statY = 124
	for _, def in statDefs do
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(0.65, 0, 0, 26)
		lbl.Position = UDim2.fromOffset(0, statY)
		lbl.Font = FONT_BODY
		lbl.TextSize = 14
		lbl.TextColor3 = COLOR_TEXT_DIM
		lbl.Text = def.label
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.ZIndex = 52
		lbl.Parent = rightPanel

		local val = Instance.new("TextLabel")
		val.BackgroundTransparency = 1
		val.Size = UDim2.new(0.35, 0, 0, 26)
		val.AnchorPoint = Vector2.new(1, 0)
		val.Position = UDim2.new(1, 0, 0, statY)
		val.Font = FONT_TITLE
		val.TextSize = 15
		val.TextColor3 = COLOR_TEXT
		val.Text = def.value
		val.TextXAlignment = Enum.TextXAlignment.Right
		val.ZIndex = 52
		val.Parent = rightPanel

		statY += 30
	end

	-- ── SPAWN button ────────────────────────────────────────────────
	local spawnBtn = Instance.new("TextButton")
	spawnBtn.Name = "SpawnButton"
	spawnBtn.BackgroundColor3 = theme.accent
	spawnBtn.BorderSizePixel = 0
	spawnBtn.AnchorPoint = Vector2.new(1, 0)
	spawnBtn.Size = UDim2.fromOffset(260, 44)
	spawnBtn.Position = UDim2.new(1, -20, 0, 400)
	spawnBtn.Font = FONT_TITLE
	spawnBtn.TextSize = 20
	spawnBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	spawnBtn.Text = "SPAWN"
	spawnBtn.AutoButtonColor = true
	spawnBtn.ZIndex = 52
	spawnBtn.Parent = page
	corner(spawnBtn, 10)

	spawnBtn.MouseButton1Click:Connect(function()
		if spawnEvent then
			spawnEvent:FireServer(selectedName)
		end
		closePage()
		if typeof(_G.ClosePhoneMenu) == "function" then
			_G.ClosePhoneMenu()
		end
	end)

	-- ── Center: 3D character viewport ────────────────────────────────
	buildMercViewport(page, selectedName)

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
	p:Destroy()
	showPhonePanels()
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
		return
	end

	buildPage(mercNames)
end

_G.OpenMercenariesMenu = openMercenariesMenu
