-- PhoneMenu.client.lua
-- Full-screen menu that opens when the player presses E while holding the
-- Phone tool. This milestone is VISUALS ONLY — layout, panels and labels
-- are built, but none of the buttons/bars are wired to gameplay.
--
-- Layout (matches the reference mockup):
--   top-left     : level badge + upgrade points counter
--   left column  : attribute bars (HP / Stamina / Strength / Agility)
--   bottom       : XP bar
--   top-right    : daily tasks + reward
--   bottom-right : Arsenal / Mercenaries buttons

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── Theme ────────────────────────────────────────────────────────────────
local COLOR_BG          = Color3.fromRGB(5, 15, 35)
local COLOR_PANEL       = Color3.fromRGB(10, 25, 55)
local COLOR_PANEL_EDGE  = Color3.fromRGB(80, 180, 255)
local COLOR_ACCENT      = Color3.fromRGB(120, 210, 255)
local COLOR_TEXT        = Color3.fromRGB(220, 240, 255)
local COLOR_TEXT_DIM    = Color3.fromRGB(140, 180, 220)
local COLOR_BAR_BG      = Color3.fromRGB(15, 35, 70)
local COLOR_BAR_FILL    = Color3.fromRGB(90, 200, 255)
local COLOR_XP_FILL     = Color3.fromRGB(120, 220, 255)

local FONT_TITLE = Enum.Font.GothamBold
local FONT_BODY  = Enum.Font.Gotham

-- ─── State ────────────────────────────────────────────────────────────────
local menuOpen      = false
local phoneEquipped = false
local screenGui     = nil

-- ─── Small UI helpers ─────────────────────────────────────────────────────
local function stroke(parent, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 1.5
	s.Color     = color or COLOR_PANEL_EDGE
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function padding(parent, px)
	local p = Instance.new("UIPadding")
	p.PaddingTop    = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft   = UDim.new(0, px)
	p.PaddingRight  = UDim.new(0, px)
	p.Parent = parent
	return p
end

local function makePanel(name, parent)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = COLOR_PANEL
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	f.Parent = parent
	corner(f, 10)
	stroke(f, 1.5, COLOR_PANEL_EDGE)
	return f
end

local function makeLabel(parent, text, font, size, color, align)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = font or FONT_BODY
	t.TextSize = size or 18
	t.TextColor3 = color or COLOR_TEXT
	t.Text = text or ""
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Parent = parent
	return t
end

-- Horizontal progress bar with an optional label on the right.
local function makeBar(parent, fill01, label)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 26)
	row.Parent = parent

	local name = makeLabel(row, label or "", FONT_BODY, 14, COLOR_TEXT_DIM)
	name.Size = UDim2.new(0, 82, 1, 0)
	name.Position = UDim2.new(0, 0, 0, 0)

	local track = Instance.new("Frame")
	track.BackgroundColor3 = COLOR_BAR_BG
	track.BorderSizePixel = 0
	track.Position = UDim2.new(0, 88, 0.5, -5)
	track.Size = UDim2.new(1, -130, 0, 10)
	track.Parent = row
	corner(track, 5)
	stroke(track, 1, COLOR_PANEL_EDGE)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = COLOR_BAR_FILL
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(math.clamp(fill01 or 0, 0, 1), 0, 1, 0)
	fill.Parent = track
	corner(fill, 5)

	local lvl = makeLabel(row, "lvl 1", FONT_BODY, 14, COLOR_TEXT_DIM, Enum.TextXAlignment.Right)
	lvl.AnchorPoint = Vector2.new(1, 0.5)
	lvl.Position = UDim2.new(1, 0, 0.5, 0)
	lvl.Size = UDim2.new(0, 40, 1, 0)

	return row, fill, lvl
end

local function makeIconBox(parent, glyph)
	-- Simple square "icon slot" placeholder (single letter stand-in so the
	-- file has zero asset dependencies).
	local box = Instance.new("Frame")
	box.BackgroundColor3 = COLOR_BAR_BG
	box.BorderSizePixel = 0
	box.Size = UDim2.fromOffset(26, 26)
	box.Parent = parent
	corner(box, 6)
	stroke(box, 1, COLOR_PANEL_EDGE)
	local g = makeLabel(box, glyph or "", FONT_TITLE, 16, COLOR_ACCENT, Enum.TextXAlignment.Center)
	g.Size = UDim2.fromScale(1, 1)
	return box
end

-- ─── Menu construction ────────────────────────────────────────────────────
local viewportFrame = nil
local viewportWorld = nil
local viewportCamera = nil
local viewportCharModel = nil

-- Rebuild the character display inside the ViewportFrame. Clones the live
-- LocalPlayer.Character, strips scripts, anchors parts, rotates it so its
-- front faces the camera, and attaches a subtle cyan PointLight so it reads
-- clearly against the dark backdrop. Called every time the menu opens so
-- the clone always reflects the current appearance.
local function refreshCharacterViewport()
	if not viewportFrame or not viewportWorld then return end

	if viewportCharModel then
		viewportCharModel:Destroy()
		viewportCharModel = nil
	end

	local char = player.Character
	if not char then return end

	-- Archivable must be true for Clone() to succeed on the live character.
	local wasArchivable = char.Archivable
	char.Archivable = true
	local clone = char:Clone()
	char.Archivable = wasArchivable

	-- Remove all Scripts / LocalScripts from the clone and anchor parts so
	-- the model behaves as a static display rig.
	for _, d in clone:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.Massless = true
		end
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	-- Place the clone at origin, rotated 180° around Y so its front faces
	-- the +Z axis — that's where the camera sits.
	clone:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.pi, 0))

	-- Subtle cyan PointLight attached to the root for visibility. A
	-- PointLight only renders inside a ViewportFrame when its ancestor
	-- is a WorldModel, which is why the clone lives under `viewportWorld`.
	local root = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
	if root and root:IsA("BasePart") then
		local light = Instance.new("PointLight")
		light.Name = "PhoneMenuCharLight"
		light.Color = Color3.fromRGB(120, 220, 255)
		light.Brightness = 1.5
		light.Range = 12
		light.Shadows = false
		light.Parent = root
	end

	clone.Parent = viewportWorld
	viewportCharModel = clone

	if viewportCamera then
		-- Front view, slightly above, looking at chest height.
		viewportCamera.CFrame = CFrame.new(Vector3.new(0, 1.5, 6), Vector3.new(0, 0.5, 0))
	end
end

local function buildMenu()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PhoneMenu"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Enabled = false
	screenGui.DisplayOrder = 50
	screenGui.Parent = playerGui

	-- Dimming backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.BackgroundColor3 = COLOR_BG
	backdrop.BackgroundTransparency = 0.25
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = screenGui

	-- Root frame (full screen minus a small inset)
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(1, -60, 1, -60)
	root.Parent = screenGui

	-- ── Center: character viewport ───────────────────────────────────────
	-- ViewportFrame occupies the same space as before; only its contents
	-- (WorldModel + cloned character + camera + light) changed.
	viewportFrame = Instance.new("ViewportFrame")
	viewportFrame.Name = "CharacterViewport"
	viewportFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	viewportFrame.Position = UDim2.fromScale(0.5, 0.45)
	viewportFrame.Size = UDim2.fromOffset(360, 500)
	viewportFrame.BackgroundTransparency = 1
	viewportFrame.BorderSizePixel = 0
	viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)
	viewportFrame.LightDirection = Vector3.new(-0.3, -1, -0.5)
	viewportFrame.Ambient = Color3.fromRGB(180, 200, 230)
	viewportFrame.Parent = root

	-- WorldModel enables PointLight rendering inside the ViewportFrame.
	viewportWorld = Instance.new("WorldModel")
	viewportWorld.Name = "World"
	viewportWorld.Parent = viewportFrame

	viewportCamera = Instance.new("Camera")
	viewportCamera.FieldOfView = 40
	viewportCamera.CFrame = CFrame.new(Vector3.new(0, 1.5, 6), Vector3.new(0, 0.5, 0))
	viewportCamera.Parent = viewportFrame
	viewportFrame.CurrentCamera = viewportCamera

	-- ── Top-left: level + upgrade points ─────────────────────────────────
	local levelPanel = makePanel("LevelPanel", root)
	levelPanel.AnchorPoint = Vector2.new(0, 0)
	levelPanel.Position = UDim2.fromScale(0, 0)
	levelPanel.Size = UDim2.fromOffset(300, 70)
	padding(levelPanel, 10)

	local lvlBadge = Instance.new("Frame")
	lvlBadge.BackgroundColor3 = COLOR_BAR_BG
	lvlBadge.BorderSizePixel = 0
	lvlBadge.Size = UDim2.fromOffset(50, 50)
	lvlBadge.Position = UDim2.fromOffset(0, 0)
	lvlBadge.Parent = levelPanel
	corner(lvlBadge, 8)
	stroke(lvlBadge, 1.5, COLOR_ACCENT)

	local lvlTag = makeLabel(lvlBadge, "LVL", FONT_BODY, 12, COLOR_TEXT_DIM, Enum.TextXAlignment.Center)
	lvlTag.Size = UDim2.new(1, 0, 0, 16)
	lvlTag.Position = UDim2.fromOffset(0, 4)

	local lvlNum = makeLabel(lvlBadge, "5", FONT_TITLE, 22, COLOR_ACCENT, Enum.TextXAlignment.Center)
	lvlNum.Size = UDim2.new(1, 0, 0, 28)
	lvlNum.Position = UDim2.fromOffset(0, 18)

	local nameLbl = makeLabel(levelPanel, "usernam3", FONT_TITLE, 22, COLOR_TEXT)
	nameLbl.Position = UDim2.fromOffset(60, 0)
	nameLbl.Size = UDim2.new(1, -60, 0, 28)

	local pointsLbl = makeLabel(levelPanel, "Upgrade points: 3", FONT_BODY, 14, COLOR_ACCENT)
	pointsLbl.Position = UDim2.fromOffset(60, 30)
	pointsLbl.Size = UDim2.new(1, -60, 0, 20)

	-- ── Left column: attribute bars ────────────────────────────────────
	local statsPanel = makePanel("StatsPanel", root)
	statsPanel.AnchorPoint = Vector2.new(0, 0)
	statsPanel.Position = UDim2.fromOffset(0, 85)
	statsPanel.Size = UDim2.fromOffset(340, 230)
	padding(statsPanel, 12)

	local statsTitle = makeLabel(statsPanel, "Player stats", FONT_TITLE, 18, COLOR_TEXT)
	statsTitle.Size = UDim2.new(1, 0, 0, 22)

	local rowHolder = Instance.new("Frame")
	rowHolder.BackgroundTransparency = 1
	rowHolder.Position = UDim2.fromOffset(0, 28)
	rowHolder.Size = UDim2.new(1, 0, 1, -28)
	rowHolder.Parent = statsPanel

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)
	list.Parent = rowHolder

	local stats = {
		{ name = "HP",        fill = 0.8, lvl = "lvl 5", glyph = "+" },
		{ name = "Stamina",   fill = 0.2, lvl = "lvl 1", glyph = "S" },
		{ name = "Strength",  fill = 0.6, lvl = "lvl 3", glyph = "ST" },
		{ name = "Agility",   fill = 0.2, lvl = "lvl 1", glyph = "A" },
	}
	for i, s in ipairs(stats) do
		local row, _, lvlLabel = makeBar(rowHolder, s.fill, s.name)
		row.LayoutOrder = i
		lvlLabel.Text = s.lvl
		local icon = makeIconBox(row, s.glyph)
		icon.AnchorPoint = Vector2.new(1, 0.5)
		icon.Position = UDim2.new(1, -46, 0.5, 0)
	end

	-- ── Top-right: daily tasks ─────────────────────────────────────────
	local tasksPanel = makePanel("TasksPanel", root)
	tasksPanel.AnchorPoint = Vector2.new(1, 0)
	tasksPanel.Position = UDim2.new(1, 0, 0, 0)
	tasksPanel.Size = UDim2.fromOffset(320, 180)
	padding(tasksPanel, 12)

	local tasksTitle = makeLabel(tasksPanel, "Tasks for today:", FONT_TITLE, 18, COLOR_TEXT)
	tasksTitle.Size = UDim2.new(1, 0, 0, 22)

	local tasksHolder = Instance.new("Frame")
	tasksHolder.BackgroundTransparency = 1
	tasksHolder.Position = UDim2.fromOffset(0, 30)
	tasksHolder.Size = UDim2.new(1, 0, 0, 70)
	tasksHolder.Parent = tasksPanel

	local tList = Instance.new("UIListLayout")
	tList.SortOrder = Enum.SortOrder.LayoutOrder
	tList.Padding = UDim.new(0, 8)
	tList.Parent = tasksHolder

	local tasks = {
		{ text = "Collect 10 logs",  done = false },
		{ text = "Kill 10 enemies",  done = true  },
	}
	for i, t in ipairs(tasks) do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 26)
		row.LayoutOrder = i
		row.Parent = tasksHolder

		local box = Instance.new("Frame")
		box.BackgroundColor3 = COLOR_BAR_BG
		box.BorderSizePixel = 0
		box.Size = UDim2.fromOffset(22, 22)
		box.Position = UDim2.fromOffset(0, 2)
		box.Parent = row
		corner(box, 4)
		stroke(box, 1.5, COLOR_PANEL_EDGE)

		if t.done then
			local check = makeLabel(box, "X", FONT_TITLE, 18, COLOR_ACCENT, Enum.TextXAlignment.Center)
			check.Size = UDim2.fromScale(1, 1)
		end

		local label = makeLabel(row, t.text, FONT_BODY, 16, COLOR_TEXT)
		label.Position = UDim2.fromOffset(32, 0)
		label.Size = UDim2.new(1, -32, 1, 0)
	end

	local rewardLbl = makeLabel(tasksPanel, "Reward:", FONT_TITLE, 16, COLOR_TEXT)
	rewardLbl.Position = UDim2.fromOffset(0, 110)
	rewardLbl.Size = UDim2.fromOffset(80, 22)

	local rewardValue = makeLabel(tasksPanel, "+100 XP", FONT_TITLE, 18, COLOR_ACCENT)
	rewardValue.Position = UDim2.fromOffset(82, 110)
	rewardValue.Size = UDim2.new(1, -82, 0, 22)

	-- ── Bottom-right: Arsenal / Mercenaries ────────────────────────────
	local sidePanel = makePanel("SidePanel", root)
	sidePanel.AnchorPoint = Vector2.new(1, 1)
	sidePanel.Position = UDim2.new(1, 0, 1, -70)
	sidePanel.Size = UDim2.fromOffset(220, 140)
	padding(sidePanel, 12)

	local sideTitle = makeLabel(sidePanel, "Loadout", FONT_TITLE, 16, COLOR_TEXT)
	sideTitle.Size = UDim2.new(1, 0, 0, 20)

	local function makeSideButton(text, y)
		local b = Instance.new("Frame")
		b.BackgroundColor3 = COLOR_BAR_BG
		b.BorderSizePixel = 0
		b.Position = UDim2.fromOffset(0, y)
		b.Size = UDim2.new(1, 0, 0, 38)
		b.Parent = sidePanel
		corner(b, 8)
		stroke(b, 1.5, COLOR_ACCENT)
		local l = makeLabel(b, text, FONT_TITLE, 16, COLOR_TEXT, Enum.TextXAlignment.Center)
		l.Size = UDim2.fromScale(1, 1)
		return b
	end

	makeSideButton("ARSENAL",    28)
	makeSideButton("MERCENARIES", 74)

	-- ── Bottom: XP counter ─────────────────────────────────────────────
	local xpPanel = makePanel("XPPanel", root)
	xpPanel.AnchorPoint = Vector2.new(0.5, 1)
	xpPanel.Position = UDim2.new(0.5, 0, 1, 0)
	xpPanel.Size = UDim2.new(0.6, 0, 0, 48)
	padding(xpPanel, 10)

	local xpTag = makeLabel(xpPanel, "XP", FONT_TITLE, 18, COLOR_TEXT)
	xpTag.Size = UDim2.fromOffset(40, 1)
	xpTag.Size = UDim2.new(0, 40, 1, 0)

	local xpAmount = makeLabel(xpPanel, "256 / 850", FONT_BODY, 16, COLOR_TEXT_DIM)
	xpAmount.Position = UDim2.fromOffset(46, 0)
	xpAmount.Size = UDim2.new(0, 120, 1, 0)

	local xpTrack = Instance.new("Frame")
	xpTrack.BackgroundColor3 = COLOR_BAR_BG
	xpTrack.BorderSizePixel = 0
	xpTrack.Position = UDim2.fromOffset(175, 9)
	xpTrack.Size = UDim2.new(1, -185, 0, 14)
	xpTrack.Parent = xpPanel
	corner(xpTrack, 7)
	stroke(xpTrack, 1, COLOR_PANEL_EDGE)

	local xpFill = Instance.new("Frame")
	xpFill.BackgroundColor3 = COLOR_XP_FILL
	xpFill.BorderSizePixel = 0
	xpFill.Size = UDim2.fromScale(256 / 850, 1)
	xpFill.Parent = xpTrack
	corner(xpFill, 7)
end

-- ─── Show / hide ──────────────────────────────────────────────────────────
local function setMenuOpen(open)
	if not screenGui then buildMenu() end
	menuOpen = open
	screenGui.Enabled = open
	if open then
		if typeof(_G.CloseInventory) == "function" then
			_G.CloseInventory()
		end
		refreshCharacterViewport()
	end
end

-- ─── Tool equip tracking (Phone) ──────────────────────────────────────────
-- While the Phone is equipped we block InventoryUI's own E handler via the
-- `_G.SuppressInventoryToggle` hook it already exposes — otherwise pressing E
-- would open both the phone menu AND the inventory at the same time. We also
-- force-close the inventory on equip in case it's already open.
local function setPhoneEquipped(eq)
	phoneEquipped = eq
	_G.SuppressInventoryToggle = eq or nil
	if eq and typeof(_G.CloseInventory) == "function" then
		_G.CloseInventory()
	end
end

local function onToolEquipped(tool)
	if tool.Name == "Phone" then
		setPhoneEquipped(true)
	end
end

local function onToolUnequipped(tool)
	if tool.Name == "Phone" then
		setPhoneEquipped(false)
		if menuOpen then setMenuOpen(false) end
	end
end

local function setupCharacter(char)
	if not char then return end
	setPhoneEquipped(false)
	if menuOpen then setMenuOpen(false) end

	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then onToolEquipped(child) end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then onToolUnequipped(child) end
	end)
	for _, child in char:GetChildren() do
		if child:IsA("Tool") and child.Name == "Phone" then
			onToolEquipped(child)
			break
		end
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

-- Build the GUI once up-front so the first open has no hitch.
buildMenu()

-- ─── Input ────────────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E and phoneEquipped then
		setMenuOpen(not menuOpen)
	end
end)
