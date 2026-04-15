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
local screenGui = _G.PhoneScreenGui
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
		-- Stats mirror src/Pirate_2/Combat.script ATTR so the card doesn't
		-- lie to the player about how tough their merc actually is.
		stats       = { hp = 250, damage = 18, mana = "20/min" },
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
local hiddenPanels = {}    -- panels hidden while mercenaries page is open
local currentMercNames = {}  -- remembered across page switches
local currentSelectedMerc = nil

-- Forward declarations so character page and equipment page can call each other
local buildPage
local buildEquipmentPage

-- Hide all phone-menu panels (direct children of root) except the
-- mercenaries page itself.
local function hidePhonePanels()
	if #hiddenPanels > 0 then return end -- already hidden
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

local function buildMercViewport(parent, mercName, weaponId)
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
	cam.CFrame = CFrame.new(Vector3.new(0, 2.2, 7.5), Vector3.new(0, 0, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam

	-- Clone the spawn template from ReplicatedStorage. The recruited
	-- mercenary name ("Pirate lvl1") is a roster identifier, not a model
	-- name — the actual rig is mapped via MERC_THEMES[mercName].spawnModel
	-- (e.g. "Pirate_2"). Fall back to mercName for any theme that doesn't
	-- set a dedicated spawnModel.
	local theme = MERC_THEMES[mercName] or DEFAULT_THEME
	local templateName = theme.spawnModel or mercName
	local template = ReplicatedStorage:FindFirstChild(templateName)
	if not template then
		warn("[MercenariesMenu] Template not found:", templateName)
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
	-- alone doesn't work for R6 in ViewportFrame). We used to disable
	-- every HumanoidStateType to stop the rig from falling inside the
	-- WorldModel, but that also prevents the Animator from evaluating
	-- tracks (and skips the accessory auto-weld pass). Instead, just
	-- anchor HumanoidRootPart below — that's enough to keep the rig in
	-- place while leaving state / Animator intact so the idle animation
	-- actually plays.
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local animator
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
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

	-- Manually weld accessories (and legacy Hat instances) to the Head.
	-- The auto-weld pass that normally fires on Accessory-added doesn't
	-- always run for rigs inside a WorldModel, so the hat ends up floating
	-- free. Cover three classes of rigging:
	--
	--   1. Accessory / Hat (both inherit from Accoutrement): standard case,
	--      weld Handle attachment → same-named attachment on Head.
	--   2. The Handle's attachment names don't match anything on the Head
	--      (rare but happens with custom hats): fall back to the first
	--      attachment we can find on Head.
	--   3. Custom hat Models (no Accoutrement wrapper) that contain a
	--      "Handle" part directly. PirateHat looks like a standard
	--      Accoutrement from the Explorer, but the fallback is cheap.
	local head = clone:FindFirstChild("Head")
	local headAttachments = {}
	if head then
		for _, att in head:GetChildren() do
			if att:IsA("Attachment") then
				headAttachments[att.Name] = att
			end
		end
	end

	-- Standard R6 Head attachment offsets. The Pirate_2 template's Head
	-- ships with NO attachments at all (the Output shows "Head has no
	-- Attachment at all"), so the PirateHat's HatAttachment has nothing
	-- to align to. Create whichever attachment a clothing handle asks for
	-- on demand, using the canonical R6 position.
	local DEFAULT_HEAD_ATTACHMENTS = {
		HatAttachment         = CFrame.new(0, 0.6, 0),
		HairAttachment        = CFrame.new(0, 0.6, 0),
		FaceFrontAttachment   = CFrame.new(0, 0, -0.6),
		FaceCenterAttachment  = CFrame.new(0, 0, 0),
		NeckAttachment        = CFrame.new(0, -0.5, 0),
	}

	local function ensureHeadAttachment(name)
		if not head then return nil end
		local existing = headAttachments[name]
		if existing then return existing end
		local cf = DEFAULT_HEAD_ATTACHMENTS[name] or CFrame.new(0, 0.6, 0)
		local att = Instance.new("Attachment")
		att.Name = name
		att.CFrame = cf
		att.Parent = head
		headAttachments[name] = att
		return att
	end

	local function weldHandleToHead(handle, sourceName)
		if not head or not handle then return end
		local handleAtt
		for _, a in handle:GetChildren() do
			if a:IsA("Attachment") then
				handleAtt = a
				break
			end
		end
		if not handleAtt then
			warn("[MercenariesMenu] "..sourceName..".Handle has no Attachment — cannot weld")
			return
		end
		local headAtt = ensureHeadAttachment(handleAtt.Name)
		if not headAtt then
			warn("[MercenariesMenu] could not create Head attachment for "..sourceName)
			return
		end
		for _, w in handle:GetChildren() do
			if w:IsA("Weld") or w:IsA("Motor6D") or w:IsA("WeldConstraint") then
				w:Destroy()
			end
		end
		handle.Anchored = false
		handle.CanCollide = false
		handle.Massless = true
		local weld = Instance.new("Motor6D")
		weld.Name = "AccessoryWeld"
		weld.Part0 = head
		weld.Part1 = handle
		weld.C0 = headAtt.CFrame
		weld.C1 = handleAtt.CFrame
		weld.Parent = handle
	end

	if head then
		for _, acc in clone:GetChildren() do
			-- Accoutrement is the shared base for both Accessory and
			-- legacy Hat, so this catches both. PirateHat in the current
			-- template is showing up in Explorer with the Hat/Accoutrement
			-- icon — :IsA("Accessory") would miss a legacy Hat.
			if acc:IsA("Accoutrement") then
				local handle = acc:FindFirstChild("Handle")
					or acc:FindFirstChildWhichIsA("BasePart")
				if handle then
					weldHandleToHead(handle, acc.Name)
				else
					warn("[MercenariesMenu] "..acc.Name.." has no Handle part — cannot weld")
				end
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

	-- ── Weapon swap in viewport ─────────────────────────────────────
	-- For the default sword ("Sword" / nil): DON'T TOUCH anything. The
	-- Pirate_2 template in the .rbxl already ships with its sword welded
	-- into the right hand at a known-good grip — every rotation hack we
	-- tried rebuilding this ourselves (custom C0, 180° flip, canonical C0,
	-- +90° Y) ended up twisted because Tool.Grip's expected base frame
	-- isn't reproducible inside a WorldModel without the live Humanoid
	-- equip flow. Leaving the template weapon alone is what was working
	-- before, and it's what we go back to.
	--
	-- Only swap when the player picks a different weapon (e.g. FishingRod).
	-- In that case we reuse the template's own RightGrip.C0 as the base —
	-- that's a proven orientation from the asset itself, not a guess.
	if weaponId and weaponId ~= "Sword" then
		local rightArm = clone:FindFirstChild("Right Arm")

		-- Capture the template's existing grip orientation before we tear
		-- anything down. Check RightGrip on the arm first, then fall back
		-- to any Motor6D/Weld in the clone whose Part0 is the right arm
		-- (NPC rigs sometimes use a differently-named weld).
		local priorGripC0
		if rightArm then
			local existing = rightArm:FindFirstChild("RightGrip")
			if existing and existing:IsA("JointInstance") then
				priorGripC0 = existing.C0
				existing:Destroy()
			else
				for _, d in clone:GetDescendants() do
					if (d:IsA("Motor6D") or d:IsA("Weld")) and d.Part0 == rightArm then
						priorGripC0 = d.C0
						break
					end
				end
			end
		end

		-- Remove template-supplied Tools so only the picked weapon remains.
		for _, child in clone:GetChildren() do
			if child:IsA("Tool") then child:Destroy() end
		end

		local weaponTemplate = ReplicatedStorage:FindFirstChild(weaponId)
			or ReplicatedStorage:FindFirstChild(weaponId, true)

		if weaponTemplate and rightArm then
			local wArchivable = weaponTemplate.Archivable
			weaponTemplate.Archivable = true
			local wClone = weaponTemplate:Clone()
			weaponTemplate.Archivable = wArchivable

			for _, d in wClone:GetDescendants() do
				if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
			end
			for _, d in wClone:GetDescendants() do
				if d:IsA("BasePart") then
					d.Transparency = 0
					d.CanCollide   = false
					d.Anchored     = false
					d.Massless     = true
				end
			end

			local handle = wClone:FindFirstChild("Handle")
			if not handle then
				handle = wClone:FindFirstChildWhichIsA("BasePart", true)
			end

			local toolGripC1 = CFrame.new()
			if wClone:IsA("Tool") then
				toolGripC1 = wClone.Grip
			end

			if handle then
				-- Only purge welds that link the Handle to parts OUTSIDE
				-- the weapon — internal welds (e.g. FishingRod's multi-part
				-- assembly) have to stay or the rod falls apart.
				for _, w in handle:GetChildren() do
					if w:IsA("Motor6D") or w:IsA("Weld") then
						local p0 = w.Part0
						if not p0 or not p0:IsDescendantOf(wClone) then
							w:Destroy()
						end
					end
				end

				local newGrip = Instance.new("Motor6D")
				newGrip.Name  = "RightGrip"
				newGrip.Part0 = rightArm
				newGrip.Part1 = handle
				newGrip.C0    = priorGripC0 or CFrame.new(0, -1, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0)
				newGrip.C1    = toolGripC1
				newGrip.Parent = rightArm

				if wClone:IsA("Tool") then
					for _, child in wClone:GetChildren() do
						child.Parent = clone
					end
					wClone:Destroy()
				else
					wClone.Parent = clone
				end
			else
				wClone:Destroy()
			end
		end
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

buildPage = function(mercNames)
	if page then page:Destroy() end

	currentMercNames = mercNames
	local selectedName = mercNames[1]
	currentSelectedMerc = selectedName
	local theme        = MERC_THEMES[selectedName] or DEFAULT_THEME

	-- ── Full-page container (phone-style blue background) ────────────
	page = Instance.new("Frame")
	page.Name = "MercenariesPage"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundColor3 = COLOR_BG
	page.BackgroundTransparency = 0.15
	page.BorderSizePixel = 0
	page.ZIndex = 50
	page.Parent = screenGui

	-- Hide phone main panels so they don't show through
	hidePhonePanels()

	-- ── Top bar: character selector ──────────────────────────────────
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.BackgroundTransparency = 1
	topBar.Size = UDim2.new(1, 0, 0, 56)
	topBar.Position = UDim2.fromOffset(0, 36)
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

	-- ── Left side: menu buttons ─────────────────────────────────────
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
		local row = Instance.new("TextButton")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 32)
		row.Position = UDim2.fromOffset(0, (i - 1) * 40)
		row.Font = FONT_BODY
		row.TextSize = 17
		row.TextColor3 = COLOR_TEXT
		row.Text = "◇ " .. itemText
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.AutoButtonColor = false
		row.ZIndex = 51
		row.Parent = leftPanel

		if itemText == "Equipment" then
			row.MouseButton1Click:Connect(function()
				buildEquipmentPage(selectedName, mercNames)
			end)
		end
	end

	-- ── Right side: stats panel ──────────────────────────────────────
	local rightPanel = Instance.new("Frame")
	rightPanel.Name = "RightStats"
	rightPanel.BackgroundColor3 = COLOR_PANEL
	rightPanel.BackgroundTransparency = 0.4
	rightPanel.BorderSizePixel = 0
	rightPanel.AnchorPoint = Vector2.new(1, 0)
	rightPanel.Size = UDim2.fromOffset(260, 320)
	rightPanel.Position = UDim2.new(1, -20, 0, 106)
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

-- ─── Equipment data ─────────────────────────────────────────────────────

local EQUIP_CATEGORIES = { "Weapons", "Artifacts" }

local EQUIP_ITEMS = {
	Weapons = {
		{
			id            = "Sword",
			displayName   = "Pirate Sword",
			typeName      = "Melee",
			stars         = 1,
			baseAttack    = 10,
			description   = "A basic pirate cutlass. Short range but reliable in close combat.",
			alwaysUnlocked = true,
		},
		{
			id            = "FishingRod",
			displayName   = "Fishing Rod",
			typeName      = "Utility",
			stars         = 1,
			baseAttack    = 0,
			description   = "Cast your line to catch fish. Equip to a mercenary for automated fishing.",
		},
	},
	Artifacts = {
		{
			id            = "Backpack",
			displayName   = "Backpack",
			typeName      = "Artifact",
			stars         = 1,
			baseAttack    = 0,
			description   = "A sturdy pirate backpack. Free starter gear given to all captains.",
			icon          = "rbxassetid://87410058497044",
			alwaysUnlocked = true,
		},
	},
}

-- ─── Build equipment page ───────────────────────────────────────────────

buildEquipmentPage = function(mercName, mercNames)
	if page then page:Destroy() end

	currentSelectedMerc = mercName
	currentMercNames = mercNames
	local theme = MERC_THEMES[mercName] or DEFAULT_THEME

	-- Which category is active
	local activeCategory = "Weapons"
	local selectedItemId = "Sword" -- default selection

	-- Read currently equipped weapon from attribute
	local mercFolder = player:FindFirstChild("Mercenaries")
	if mercFolder then
		local entry = mercFolder:FindFirstChild(mercName)
		if entry then
			local eq = entry:GetAttribute("EquippedWeapon")
			if eq then selectedItemId = eq end
		end
	end

	-- Read unlocked equipment
	local unlockedSet = {}
	local eqFolder = player:FindFirstChild("UnlockedEquipment")
	if eqFolder then
		for _, child in eqFolder:GetChildren() do
			unlockedSet[child.Name] = true
		end
	end
	-- Sword is always unlocked
	unlockedSet["Sword"] = true
	-- Backpack is always unlocked (free starter artifact)
	unlockedSet["Backpack"] = true
	-- Fallback: also scan Backpack and Character for tools the server
	-- may not have tracked yet (race with save-data restore).
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") then unlockedSet[child.Name] = true end
		end
	end
	local char = player.Character
	if char then
		for _, child in char:GetChildren() do
			if child:IsA("Tool") then unlockedSet[child.Name] = true end
		end
	end

	-- ── Full-page container ─────────────────────────────────────────
	page = Instance.new("Frame")
	page.Name = "MercenariesPage"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundColor3 = COLOR_BG
	page.BackgroundTransparency = 0.15
	page.BorderSizePixel = 0
	page.ZIndex = 50
	page.Parent = screenGui

	hidePhonePanels()

	-- ── Top bar ─────────────────────────────────────────────────────
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.BackgroundTransparency = 1
	topBar.Size = UDim2.new(1, 0, 0, 56)
	topBar.Position = UDim2.fromOffset(0, 36)
	topBar.ZIndex = 51
	topBar.Parent = page

	-- Back button
	local backBtn = Instance.new("TextButton")
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

	backBtn.MouseButton1Click:Connect(function()
		buildPage(currentMercNames)
	end)

	-- ── Category tabs (centered) ────────────────────────────────────
	local tabW, tabH, tabGap = 110, 34, 10
	local totalTabW = #EQUIP_CATEGORIES * tabW + (#EQUIP_CATEGORIES - 1) * tabGap
	local tabContainer = Instance.new("Frame")
	tabContainer.BackgroundTransparency = 1
	tabContainer.AnchorPoint = Vector2.new(0.5, 0)
	tabContainer.Position = UDim2.new(0.5, 0, 0, 11)
	tabContainer.Size = UDim2.fromOffset(totalTabW, tabH)
	tabContainer.ZIndex = 51
	tabContainer.Parent = topBar

	local tabButtons = {}

	-- ── Right side: item details panel ──────────────────────────────
	local detailPanel = Instance.new("Frame")
	detailPanel.Name = "DetailPanel"
	detailPanel.BackgroundColor3 = COLOR_PANEL
	detailPanel.BackgroundTransparency = 0.4
	detailPanel.BorderSizePixel = 0
	detailPanel.AnchorPoint = Vector2.new(1, 0)
	detailPanel.Size = UDim2.fromOffset(260, 400)
	detailPanel.Position = UDim2.new(1, -20, 0, 98)
	detailPanel.ZIndex = 51
	detailPanel.Parent = page
	corner(detailPanel, 10)

	local dPad = Instance.new("UIPadding")
	dPad.PaddingTop    = UDim.new(0, 14)
	dPad.PaddingLeft   = UDim.new(0, 16)
	dPad.PaddingRight  = UDim.new(0, 16)
	dPad.Parent = detailPanel

	-- Detail labels (will be updated on selection)
	local detailName = Instance.new("TextLabel")
	detailName.BackgroundTransparency = 1
	detailName.Size = UDim2.new(1, 0, 0, 26)
	detailName.Font = FONT_TITLE
	detailName.TextSize = 20
	detailName.TextColor3 = COLOR_TEXT
	detailName.TextXAlignment = Enum.TextXAlignment.Left
	detailName.ZIndex = 52
	detailName.Parent = detailPanel

	local detailType = Instance.new("TextLabel")
	detailType.BackgroundTransparency = 1
	detailType.Size = UDim2.new(1, 0, 0, 20)
	detailType.Position = UDim2.fromOffset(0, 28)
	detailType.Font = FONT_BODY
	detailType.TextSize = 14
	detailType.TextColor3 = COLOR_TEXT_DIM
	detailType.TextXAlignment = Enum.TextXAlignment.Left
	detailType.ZIndex = 52
	detailType.Parent = detailPanel

	local detailStars = Instance.new("TextLabel")
	detailStars.BackgroundTransparency = 1
	detailStars.Size = UDim2.new(1, 0, 0, 20)
	detailStars.Position = UDim2.fromOffset(0, 50)
	detailStars.Font = FONT_BODY
	detailStars.TextSize = 16
	detailStars.TextColor3 = Color3.fromRGB(255, 220, 100)
	detailStars.TextXAlignment = Enum.TextXAlignment.Left
	detailStars.ZIndex = 52
	detailStars.Parent = detailPanel

	local detailAttackLabel = Instance.new("TextLabel")
	detailAttackLabel.BackgroundTransparency = 1
	detailAttackLabel.Size = UDim2.new(0.6, 0, 0, 22)
	detailAttackLabel.Position = UDim2.fromOffset(0, 82)
	detailAttackLabel.Font = FONT_BODY
	detailAttackLabel.TextSize = 14
	detailAttackLabel.TextColor3 = COLOR_TEXT_DIM
	detailAttackLabel.Text = "Base Attack"
	detailAttackLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailAttackLabel.ZIndex = 52
	detailAttackLabel.Parent = detailPanel

	local detailAttackVal = Instance.new("TextLabel")
	detailAttackVal.BackgroundTransparency = 1
	detailAttackVal.AnchorPoint = Vector2.new(1, 0)
	detailAttackVal.Size = UDim2.new(0.4, 0, 0, 22)
	detailAttackVal.Position = UDim2.new(1, 0, 0, 82)
	detailAttackVal.Font = FONT_TITLE
	detailAttackVal.TextSize = 16
	detailAttackVal.TextColor3 = COLOR_TEXT
	detailAttackVal.TextXAlignment = Enum.TextXAlignment.Right
	detailAttackVal.ZIndex = 52
	detailAttackVal.Parent = detailPanel

	local detailLevelLabel = Instance.new("TextLabel")
	detailLevelLabel.BackgroundTransparency = 1
	detailLevelLabel.Size = UDim2.new(1, 0, 0, 22)
	detailLevelLabel.Position = UDim2.fromOffset(0, 112)
	detailLevelLabel.Font = FONT_TITLE
	detailLevelLabel.TextSize = 14
	detailLevelLabel.TextColor3 = COLOR_ACCENT
	detailLevelLabel.Text = "Lv. 1/20"
	detailLevelLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLevelLabel.ZIndex = 52
	detailLevelLabel.Parent = detailPanel

	local detailDesc = Instance.new("TextLabel")
	detailDesc.BackgroundTransparency = 1
	detailDesc.Size = UDim2.new(1, 0, 0, 80)
	detailDesc.Position = UDim2.fromOffset(0, 144)
	detailDesc.Font = FONT_BODY
	detailDesc.TextSize = 13
	detailDesc.TextColor3 = COLOR_TEXT_DIM
	detailDesc.TextWrapped = true
	detailDesc.TextYAlignment = Enum.TextYAlignment.Top
	detailDesc.TextXAlignment = Enum.TextXAlignment.Left
	detailDesc.ZIndex = 52
	detailDesc.Parent = detailPanel

	-- EQUIP button
	local equipBtn = Instance.new("TextButton")
	equipBtn.Name = "EquipButton"
	equipBtn.BackgroundColor3 = theme.accent
	equipBtn.BorderSizePixel = 0
	equipBtn.Size = UDim2.new(1, 0, 0, 40)
	equipBtn.Position = UDim2.fromOffset(0, 340)
	equipBtn.Font = FONT_TITLE
	equipBtn.TextSize = 18
	equipBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	equipBtn.Text = "EQUIP"
	equipBtn.AutoButtonColor = true
	equipBtn.ZIndex = 52
	equipBtn.Parent = detailPanel
	corner(equipBtn, 8)

	-- ── Left side: equipment grid ───────────────────────────────────
	local gridFrame = Instance.new("ScrollingFrame")
	gridFrame.Name = "EquipGrid"
	gridFrame.BackgroundTransparency = 1
	gridFrame.BorderSizePixel = 0
	gridFrame.Size = UDim2.new(0.55, -10, 1, -102)
	gridFrame.Position = UDim2.fromOffset(10, 98)
	gridFrame.ScrollBarThickness = 4
	gridFrame.ScrollBarImageColor3 = COLOR_PANEL_EDGE
	gridFrame.CanvasSize = UDim2.new(0, 0, 0, 0) -- auto-sized below
	gridFrame.ZIndex = 51
	gridFrame.Parent = page

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(90, 115)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.FillDirection = Enum.FillDirection.Horizontal
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridFrame

	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop  = UDim.new(0, 6)
	gridPad.PaddingLeft = UDim.new(0, 6)
	gridPad.Parent = gridFrame

	-- ── Viewport (behind grid, center) ──────────────────────────────
	local currentViewport = nil

	local function rebuildViewport()
		if currentViewport then currentViewport:Destroy() end
		-- Pass the selected weapon so the pirate holds it in the viewport
		local weaponToShow = selectedItemId
		if activeCategory ~= "Weapons" then
			-- If browsing artifacts, show currently equipped weapon
			local mercEntry = mercFolder and mercFolder:FindFirstChild(mercName)
			weaponToShow = mercEntry and mercEntry:GetAttribute("EquippedWeapon") or "Sword"
		end
		currentViewport = buildMercViewport(page, mercName, weaponToShow)
	end

	rebuildViewport()

	-- ── Helpers to refresh UI on selection ───────────────────────────

	local gridCards = {}

	local function refreshDetails()
		local items = EQUIP_ITEMS[activeCategory] or {}
		local item
		for _, it in items do
			if it.id == selectedItemId then item = it; break end
		end
		if not item then
			detailName.Text = ""
			detailType.Text = ""
			detailStars.Text = ""
			detailAttackVal.Text = ""
			detailDesc.Text = activeCategory == "Artifacts" and "No artifacts yet." or ""
			equipBtn.Visible = false
			return
		end
		detailName.Text = item.displayName
		detailType.Text = item.typeName
		detailStars.Text = string.rep("★", item.stars) .. string.rep("☆", 6 - item.stars)
		detailAttackVal.Text = tostring(item.baseAttack)
		detailDesc.Text = item.description
		equipBtn.Visible = unlockedSet[item.id] == true

		-- Update equip button text (Artifacts use a separate slot from Weapons)
		local mercEntry = mercFolder and mercFolder:FindFirstChild(mercName)
		local currentEquip
		if activeCategory == "Artifacts" then
			currentEquip = mercEntry and mercEntry:GetAttribute("EquippedBackpack") or ""
		else
			currentEquip = mercEntry and mercEntry:GetAttribute("EquippedWeapon") or "Sword"
		end
		if currentEquip == selectedItemId then
			equipBtn.Text = "EQUIPPED"
			equipBtn.BackgroundColor3 = COLOR_BAR_BG
		else
			equipBtn.Text = "EQUIP"
			equipBtn.BackgroundColor3 = theme.accent
		end
	end

	local function highlightCard(id)
		for cardId, card in gridCards do
			local ring = card:FindFirstChildOfClass("UIStroke")
			if ring then
				ring.Thickness = (cardId == id) and 2.5 or 1
				ring.Color = (cardId == id) and Color3.fromRGB(255, 255, 255) or COLOR_PANEL_EDGE
			end
		end
	end

	local function buildGrid()
		-- Clear old cards
		for _, card in gridCards do card:Destroy() end
		gridCards = {}

		local items = EQUIP_ITEMS[activeCategory] or {}
		if #items == 0 then
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.fromOffset(200, 40)
			empty.Font = FONT_BODY
			empty.TextSize = 15
			empty.TextColor3 = COLOR_TEXT_DIM
			empty.Text = "No items yet."
			empty.ZIndex = 52
			empty.Parent = gridFrame
			gridCards["_empty"] = empty
			selectedItemId = nil
			refreshDetails()
			return
		end

		-- Auto-select first if current selection not in this category
		local found = false
		for _, it in items do
			if it.id == selectedItemId then found = true; break end
		end
		if not found then selectedItemId = items[1].id end

		for idx, item in items do
			local unlocked = unlockedSet[item.id] or item.alwaysUnlocked

			local card = Instance.new("TextButton")
			card.Name = item.id
			card.BackgroundColor3 = COLOR_PANEL
			card.BackgroundTransparency = unlocked and 0.3 or 0.6
			card.BorderSizePixel = 0
			card.AutoButtonColor = false
			card.LayoutOrder = idx
			card.Size = UDim2.fromOffset(90, 115) -- driven by grid
			card.ZIndex = 52
			card.Parent = gridFrame
			corner(card, 8)
			stroke(card, 1, COLOR_PANEL_EDGE)

			-- Level label (top-left)
			local lvl = Instance.new("TextLabel")
			lvl.BackgroundTransparency = 1
			lvl.Size = UDim2.new(1, -8, 0, 16)
			lvl.Position = UDim2.fromOffset(6, 4)
			lvl.Font = FONT_BODY
			lvl.TextSize = 11
			lvl.TextColor3 = COLOR_TEXT_DIM
			lvl.Text = "Lv. 1"
			lvl.TextXAlignment = Enum.TextXAlignment.Left
			lvl.ZIndex = 53
			lvl.Parent = card

			-- Icon (center) — use image asset if provided, otherwise emoji
			local iconLabel
			if item.icon then
				iconLabel = Instance.new("ImageLabel")
				iconLabel.BackgroundTransparency = 1
				iconLabel.AnchorPoint = Vector2.new(0.5, 0.5)
				iconLabel.Position = UDim2.new(0.5, 0, 0.45, 0)
				iconLabel.Size = UDim2.fromOffset(50, 50)
				iconLabel.Image = item.icon
				iconLabel.ImageColor3 = unlocked and Color3.fromRGB(255, 255, 255) or COLOR_TEXT_DIM
				iconLabel.ZIndex = 53
				iconLabel.Parent = card
			else
				iconLabel = Instance.new("TextLabel")
				iconLabel.BackgroundTransparency = 1
				iconLabel.AnchorPoint = Vector2.new(0.5, 0.5)
				iconLabel.Position = UDim2.new(0.5, 0, 0.45, 0)
				iconLabel.Size = UDim2.fromOffset(50, 40)
				iconLabel.Font = FONT_TITLE
				iconLabel.TextSize = 28
				iconLabel.TextColor3 = unlocked and COLOR_TEXT or COLOR_TEXT_DIM
				iconLabel.Text = item.id == "Sword" and "⚔" or "🎣"
				iconLabel.ZIndex = 53
				iconLabel.Parent = card
			end

			-- Stars (bottom)
			local starLbl = Instance.new("TextLabel")
			starLbl.BackgroundTransparency = 1
			starLbl.Size = UDim2.new(1, 0, 0, 14)
			starLbl.AnchorPoint = Vector2.new(0, 1)
			starLbl.Position = UDim2.new(0, 6, 1, -20)
			starLbl.Font = FONT_BODY
			starLbl.TextSize = 12
			starLbl.TextColor3 = Color3.fromRGB(255, 220, 100)
			starLbl.Text = string.rep("★", item.stars)
			starLbl.TextXAlignment = Enum.TextXAlignment.Left
			starLbl.ZIndex = 53
			starLbl.Parent = card

			-- Name (very bottom)
			local nameLbl = Instance.new("TextLabel")
			nameLbl.BackgroundTransparency = 1
			nameLbl.Size = UDim2.new(1, -8, 0, 14)
			nameLbl.AnchorPoint = Vector2.new(0, 1)
			nameLbl.Position = UDim2.new(0, 6, 1, -4)
			nameLbl.Font = FONT_BODY
			nameLbl.TextSize = 11
			nameLbl.TextColor3 = COLOR_TEXT
			nameLbl.Text = item.displayName
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.ZIndex = 53
			nameLbl.Parent = card

			-- Locked overlay
			if not unlocked then
				local lock = Instance.new("TextLabel")
				lock.BackgroundTransparency = 1
				lock.AnchorPoint = Vector2.new(1, 0)
				lock.Position = UDim2.new(1, -4, 0, 2)
				lock.Size = UDim2.fromOffset(20, 16)
				lock.Font = FONT_TITLE
				lock.TextSize = 14
				lock.TextColor3 = COLOR_TEXT_DIM
				lock.Text = "🔒"
				lock.ZIndex = 54
				lock.Parent = card
			end

			gridCards[item.id] = card

			card.MouseButton1Click:Connect(function()
				selectedItemId = item.id
				highlightCard(item.id)
				refreshDetails()
				if activeCategory == "Weapons" then
					rebuildViewport()
				end
			end)
		end

		-- Update canvas size
		task.defer(function()
			gridFrame.CanvasSize = UDim2.fromOffset(0, gridLayout.AbsoluteContentSize.Y + 16)
		end)

		highlightCard(selectedItemId)
		refreshDetails()
	end

	-- ── Build category tabs ─────────────────────────────────────────
	for i, cat in EQUIP_CATEGORIES do
		local tab = Instance.new("TextButton")
		tab.BackgroundColor3 = COLOR_PANEL
		tab.BackgroundTransparency = (cat == activeCategory) and 0.2 or 0.6
		tab.BorderSizePixel = 0
		tab.Size = UDim2.fromOffset(tabW, tabH)
		tab.Position = UDim2.fromOffset((i - 1) * (tabW + tabGap), 0)
		tab.Font = FONT_TITLE
		tab.TextSize = 14
		tab.TextColor3 = (cat == activeCategory) and COLOR_TEXT or COLOR_TEXT_DIM
		tab.Text = cat
		tab.AutoButtonColor = true
		tab.ZIndex = 52
		tab.Parent = tabContainer
		corner(tab, 8)

		tabButtons[cat] = tab

		tab.MouseButton1Click:Connect(function()
			activeCategory = cat
			-- Update tab visuals
			for c, btn in tabButtons do
				btn.BackgroundTransparency = (c == cat) and 0.2 or 0.6
				btn.TextColor3 = (c == cat) and COLOR_TEXT or COLOR_TEXT_DIM
			end
			buildGrid()
		end)
	end

	-- ── EQUIP handler ───────────────────────────────────────────────
	local equipEvent = ReplicatedStorage:FindFirstChild("MercenaryEquipment")
	equipBtn.MouseButton1Click:Connect(function()
		if not selectedItemId then return end
		if not unlockedSet[selectedItemId] then return end
		if equipEvent then
			equipEvent:FireServer("equip", mercName, selectedItemId)
		end
		-- Optimistic update (Artifacts use a separate slot so the weapon is preserved)
		local mercEntry = mercFolder and mercFolder:FindFirstChild(mercName)
		if mercEntry then
			if activeCategory == "Artifacts" then
				mercEntry:SetAttribute("EquippedBackpack", selectedItemId)
			else
				mercEntry:SetAttribute("EquippedWeapon", selectedItemId)
			end
		end
		refreshDetails()
		rebuildViewport()
	end)

	-- ── Rescan unlocks (called when Backpack changes) ──────────────
	local function rescanUnlocks()
		unlockedSet = {}
		local ef = player:FindFirstChild("UnlockedEquipment")
		if ef then
			for _, child in ef:GetChildren() do
				unlockedSet[child.Name] = true
			end
		end
		unlockedSet["Sword"] = true
		local bp = player:FindFirstChild("Backpack")
		if bp then
			for _, child in bp:GetChildren() do
				if child:IsA("Tool") then unlockedSet[child.Name] = true end
			end
		end
		local ch = player.Character
		if ch then
			for _, child in ch:GetChildren() do
				if child:IsA("Tool") then unlockedSet[child.Name] = true end
			end
		end
	end

	-- ── Initial build ───────────────────────────────────────────────
	buildGrid()

	-- ── Live-update when player crafts a new tool ───────────────────
	local backpackConn
	local bp = player:FindFirstChild("Backpack")
	if bp then
		backpackConn = bp.ChildAdded:Connect(function(child)
			if not page then return end
			if child:IsA("Tool") and not unlockedSet[child.Name] then
				rescanUnlocks()
				buildGrid()
			end
		end)
	end

	-- Clean up listener when page closes
	local pageRef = page
	task.spawn(function()
		while pageRef and pageRef.Parent do task.wait(0.5) end
		if backpackConn then backpackConn:Disconnect() end
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
