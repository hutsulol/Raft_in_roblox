-- MercenariesMenu.client.lua
-- Full-page mercenary roster inside the Phone menu.
-- Opens when the player clicks the MERCENARIES button on the phone.
-- Genshin-style layout: character selector at top, 3D model in center,
-- menu buttons on the left, stats panel on the right.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local RunService        = game:GetService("RunService")
local GuiService        = game:GetService("GuiService")

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
local COLOR_TEXT_MUTE  = Color3.fromRGB(100, 125, 155)
local COLOR_BAR_BG     = Color3.fromRGB(15, 35, 70)
local COLOR_BAR_FILL   = Color3.fromRGB(90, 200, 255)
local FONT_TITLE       = Enum.Font.GothamBold
local FONT_BODY        = Enum.Font.Gotham

-- Holo palette ported from Claude Design primitives.jsx so the
-- Mercenaries page shares the exact panel / backdrop language with
-- the refreshed PhoneMenu.
local HOLO_PANEL_FILL         = Color3.fromRGB(10, 24, 44)
local HOLO_PANEL_TRANSPARENCY = 0.28
local HOLO_PANEL_BORDER       = Color3.fromRGB(75, 100, 125)
local HOLO_PANEL_LBRACKET     = Color3.fromRGB(118, 155, 190)
local HOLO_EDGE               = Color3.fromRGB(190, 220, 245)
local HOLO_DEEP               = Color3.fromRGB(40, 60, 90)
local COLOR_GOLD              = Color3.fromRGB(230, 190, 100)
-- Horizon stripe + motes stay on PhoneMenu's holo-cyan; only the base
-- gradient underneath is swapped to near-black (see buildHoloBackground
-- below) so the Mercenary page reads as a distinct darker section
-- while the cyan accent language stays consistent with the rest of
-- the menu system.
local HORIZON                 = Color3.fromRGB(80, 140, 190)

local IDLE_ANIMATION_ID = "rbxassetid://107139405334393"

-- Per-mercenary data
local MERC_THEMES = {
	["Pirate lvl1"] = {
		accent      = Color3.fromRGB(255, 80, 80),
		displayName = "Pirate",
		stars       = 1,
		role        = "Sailor · Melee",
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
	role        = "Crew",
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

-- Panels registered here fade the drifting backdrop motes — same
-- technique as PhoneMenu. Populated as panels are created in
-- subsequent steps.
local motesOccludeList = {}

-- Four small L brackets tucked 1 px outside each corner of `parent`.
-- Counter-offsets any UIPadding on the parent so the brackets always
-- sit on the panel's outer edge, not on the padded content box.
local function cornerLs(parent, size, color, thickness)
	size      = size      or 10
	color     = color     or HOLO_PANEL_LBRACKET
	thickness = thickness or 1.5

	local pad = parent:FindFirstChildOfClass("UIPadding")
	local padL = (pad and pad.PaddingLeft.Offset)   or 0
	local padR = (pad and pad.PaddingRight.Offset)  or 0
	local padT = (pad and pad.PaddingTop.Offset)    or 0
	local padB = (pad and pad.PaddingBottom.Offset) or 0

	local function addL(ax, ay, ox, oy)
		local effOx = (ax < 0.5) and (ox - padL) or (ox + padR)
		local effOy = (ay < 0.5) and (oy - padT) or (oy + padB)

		local horiz = Instance.new("Frame")
		horiz.Name = "CornerL_H"
		horiz.AnchorPoint = Vector2.new(ax, ay)
		horiz.Position = UDim2.new(ax, effOx, ay, effOy)
		horiz.Size = UDim2.fromOffset(size, thickness)
		horiz.BackgroundColor3 = color
		horiz.BorderSizePixel = 0
		horiz.ZIndex = (parent.ZIndex or 1) + 1
		horiz.Parent = parent

		local vert = Instance.new("Frame")
		vert.Name = "CornerL_V"
		vert.AnchorPoint = Vector2.new(ax, ay)
		vert.Position = UDim2.new(ax, effOx, ay, effOy)
		vert.Size = UDim2.fromOffset(thickness, size)
		vert.BackgroundColor3 = color
		vert.BorderSizePixel = 0
		vert.ZIndex = (parent.ZIndex or 1) + 1
		vert.Parent = parent
	end

	addL(0, 0, -1, -1)
	addL(1, 0,  1, -1)
	addL(0, 1, -1,  1)
	addL(1, 1,  1,  1)
end

-- Near-black holo backdrop — same five-layer composition as PhoneMenu
-- (base vertical gradient → horizon glow band → top + bottom vignette
-- → drifting motes with panel-occlusion fade). Only the base gradient
-- differs: PhoneMenu uses a navy wash, the Mercenary page darkens all
-- the way to near-black so the two screens are clearly distinct while
-- the cyan horizon stripe and motes stay identical for continuity.
local function buildHoloBackground(parent)
	local BG_TOP   = Color3.fromRGB(2,  2,  6)    -- almost pure black
	local BG_MID   = Color3.fromRGB(4,  6, 12)
	local BG_BOT   = Color3.fromRGB(8, 12, 22)    -- barely-there navy hint
	local MOTE_COL = Color3.fromRGB(180, 215, 240) -- cyan-white, matches PhoneMenu

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

	RunService.Heartbeat:Connect(function()
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
	end)

	return root
end

-- ─── Text label helper ─────────────────────────────────────────────────
local function makeLabel(parent, text, font, size, color, align)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Font = font or FONT_BODY
	t.TextSize = size or 14
	t.TextColor3 = color or COLOR_TEXT
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Text = text or ""
	t.Parent = parent
	return t
end

-- ─── Hand-drawn icons ───────────────────────────────────────────────────
-- Drop-in geometry helpers matching the style used in PhoneMenu — each
-- takes (parent, size, color), builds itself inside a square container
-- and returns that container so the caller can reposition it.

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

-- Users — two stylised people, one slightly behind and smaller.
local function makeUsersIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "UsersIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local function person(cx, headSize, bodyW, bodyH)
		local head = Instance.new("Frame")
		head.AnchorPoint = Vector2.new(0.5, 0)
		head.Position = UDim2.fromScale(cx, 0.1)
		head.Size = UDim2.fromOffset(headSize, headSize)
		head.BackgroundColor3 = color
		head.BorderSizePixel = 0
		head.Parent = c
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(1, 0)
		hc.Parent = head

		local body = Instance.new("Frame")
		body.AnchorPoint = Vector2.new(0.5, 0)
		body.Position = UDim2.fromScale(cx, 0.55)
		body.Size = UDim2.fromOffset(bodyW, bodyH)
		body.BackgroundColor3 = color
		body.BorderSizePixel = 0
		body.Parent = c
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0.3, 0)
		bc.Parent = body
	end

	person(0.35, size * 0.40, size * 0.60, size * 0.34)
	person(0.72, size * 0.30, size * 0.44, size * 0.28)

	return c
end

-- Character silhouette — round head + rounded body block. Used as the
-- placeholder glyph inside a MercCard portrait slot.
local function makeCharacterIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "CharacterIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	local head = Instance.new("Frame")
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.fromScale(0.5, 0.1)
	head.Size = UDim2.fromOffset(size * 0.42, size * 0.42)
	head.BackgroundColor3 = color
	head.BorderSizePixel = 0
	head.Parent = c
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(1, 0)
	hc.Parent = head

	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.fromScale(0.5, 0.58)
	body.Size = UDim2.fromOffset(size * 0.78, size * 0.36)
	body.BackgroundColor3 = color
	body.BorderSizePixel = 0
	body.Parent = c
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0.4, 0)
	bc.Parent = body

	return c
end

-- Padlock — rounded body + half-circle shackle. Used for locked
-- mercenary cards.
local function makeLockIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "LockIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	-- Shackle: hollow-top half of a circle via a circle Frame with
	-- UIStroke, clipped by a covering Frame below.
	local shackleH = size * 0.46
	local shackle = Instance.new("Frame")
	shackle.AnchorPoint = Vector2.new(0.5, 0)
	shackle.Position = UDim2.fromScale(0.5, 0.06)
	shackle.Size = UDim2.fromOffset(size * 0.56, shackleH)
	shackle.BackgroundTransparency = 1
	shackle.BorderSizePixel = 0
	shackle.Parent = c
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0.5, 0)
	sc.Parent = shackle
	local ss = Instance.new("UIStroke")
	ss.Color     = color
	ss.Thickness = math.max(1, math.floor(size * 0.12))
	ss.Parent    = shackle

	-- Body: rounded-top rectangle that covers the lower half of the
	-- shackle, leaving only the U-shape visible above.
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.fromScale(0.5, 0.42)
	body.Size = UDim2.fromOffset(size * 0.78, size * 0.5)
	body.BackgroundColor3 = color
	body.BorderSizePixel = 0
	body.Parent = c
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, math.max(1, math.floor(size * 0.08)))
	bc.Parent = body

	return c
end

-- Rarity row — N small rotated-square "stars". The first `filled` are
-- solid gold, the rest are hollow outlines at reduced opacity. Returns
-- a container Frame sized to fit `total` stars with a 2 px gap.
local function makeStarRow(parent, filled, total, size, color)
	size  = size  or 10
	color = color or COLOR_GOLD
	total = total or 5
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

local function makeGemIcon(parent, size, color)
	local c = Instance.new("Frame")
	c.Name = "GemIcon"
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(size, size)
	c.Parent = parent

	-- Outer rotated-square outline.
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromOffset(size * 0.7, size * 0.7)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Rotation = 45
	body.Parent = c
	local s = Instance.new("UIStroke")
	s.Color     = color
	s.Thickness = 1.4
	s.Parent    = body

	-- Short horizontal "table" facet line across the upper third so
	-- the silhouette reads as a cut gem, not just a plain diamond.
	local facet = Instance.new("Frame")
	facet.AnchorPoint = Vector2.new(0.5, 0.5)
	facet.Position = UDim2.fromScale(0.5, 0.33)
	facet.Size = UDim2.fromOffset(size * 0.5, math.max(1, math.floor(size * 0.08)))
	facet.BackgroundColor3 = color
	facet.BorderSizePixel = 0
	facet.Parent = c

	return c
end

-- ─── State ──────────────────────────────────────────────────────────────
local page = nil
local hiddenPanels = {}    -- panels hidden while mercenaries page is open
local currentMercNames = {}  -- remembered across page switches
local currentSelectedMerc = nil

-- Persistent viewport cache so switching between the character page and the
-- equipment page (and swapping weapons within the equipment page) doesn't
-- tear down the rig and restart the idle animation. Keyed by merc name —
-- we detach the ViewportFrame from the outgoing page *before* the page
-- itself is destroyed, then reparent it to the new page.
--   [mercName] = { vp = ViewportFrame, clone = Model, weaponId = string }
local viewportCache = {}

-- Forward declarations so character page and equipment page can call each other
local buildPage
local buildEquipmentPage

-- Detach every cached viewport from its current parent. Call BEFORE
-- destroying a page so the viewport survives the teardown and can be
-- reparented to the new page.
local function detachCachedViewports()
	for _, entry in viewportCache do
		if entry.vp and entry.vp.Parent then
			entry.vp.Parent = nil
		end
	end
end

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

-- Rebuild only the weapon inside an already-constructed clone. Called at
-- viewport creation time and on every equipment change so swapping
-- between Sword and FishingRod doesn't restart the idle animation.
local function applyWeaponToClone(clone, weaponId)
	local requestedTool = weaponId
	if not requestedTool or requestedTool == "Sword" then
		requestedTool = "ClassicSword"
	end

	local rightArm = clone:FindFirstChild("Right Arm")

	-- Strip any Tool we previously flattened into the clone so only the
	-- picked weapon remains.
	for _, child in clone:GetChildren() do
		if child:IsA("Tool") then
			child:Destroy()
		end
	end
	-- Remove the previous grip + anything we previously parented directly
	-- into the clone (Handle + any aux parts from a flattened Tool).
	-- Identify previously-flattened weapon parts by their AccessoryWeld /
	-- RightGrip attachments — but simpler: tag them with an attribute when
	-- we flatten so we can find and remove them on swap.
	if rightArm then
		for _, d in rightArm:GetChildren() do
			if (d:IsA("Motor6D") or d:IsA("Weld")) and d.Name == "RightGrip" then
				d:Destroy()
			end
		end
	end
	for _, child in clone:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("MercWeaponPart") then
			child:Destroy()
		elseif (child:IsA("Model") or child:IsA("Folder"))
			and child:GetAttribute("MercWeaponPart")
		then
			child:Destroy()
		end
	end

	if weaponId == "Unarmed" then
		return false
	end

	local hasWeapon = false
	local weaponTemplate = ReplicatedStorage:FindFirstChild(requestedTool)
		or ReplicatedStorage:FindFirstChild(requestedTool, true)
	if weaponTemplate and rightArm then
		local wArchivable = weaponTemplate.Archivable
		weaponTemplate.Archivable = true
		local wClone = weaponTemplate:Clone()
		weaponTemplate.Archivable = wArchivable

		for _, d in wClone:GetDescendants() do
			if d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Transparency = 0
				d.CanCollide   = false
				d.Anchored     = false
				d.Massless     = true
			end
		end

		local handle = wClone:FindFirstChild("Handle")
			or wClone:FindFirstChildWhichIsA("BasePart", true)
		local toolGripC1 = wClone:IsA("Tool") and wClone.Grip or CFrame.new()

		if handle then
			for _, w in handle:GetChildren() do
				if w:IsA("Motor6D") or w:IsA("Weld") then
					local p0 = w.Part0
					if not p0 or not p0:IsDescendantOf(wClone) then
						w:Destroy()
					end
				end
			end

			local grip = Instance.new("Motor6D")
			grip.Name  = "RightGrip"
			grip.Part0 = rightArm
			grip.Part1 = handle
			-- Engine-canonical RightGrip.C0 composed with two 90° rotations
			-- dialed in by iteration: the X-axis pitch pivots the weapon
			-- forward out of the hand, and the Z-axis roll flips the blade
			-- from pointing down at the ground to pointing up — the "ready"
			-- pose the pirate uses in-game.
			local baseGripC0 = CFrame.new(0, -1, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0)
			grip.C0    = baseGripC0 * CFrame.Angles(-math.pi / 2, 0, math.pi / 2)
			grip.C1    = toolGripC1
			grip.Parent = rightArm

			-- Tag the weapon parts so we can find and remove them on the
			-- next swap without touching rig parts (Head, Torso, arms, etc.)
			-- or accessories.
			if wClone:IsA("Tool") then
				for _, child in wClone:GetChildren() do
					child.Parent = clone
					pcall(function() child:SetAttribute("MercWeaponPart", true) end)
				end
				wClone:Destroy()
			else
				wClone.Parent = clone
				pcall(function() wClone:SetAttribute("MercWeaponPart", true) end)
			end
			hasWeapon = true
		else
			wClone:Destroy()
		end
	end

	return hasWeapon
end

-- All backpack model names on the pirate rig
local BACKPACK_MODELS = { "Backpack", "BackPack_lvl2" }

-- Sync the Backpack accessory visibility on a viewport clone based on
-- which backpack the player has equipped for this mercenary.
local function syncBackpackVisibility(clone, mercName)
	local mFolder = player:FindFirstChild("Mercenaries")
	local mEntry = mFolder and mFolder:FindFirstChild(mercName)
	local equipped = mEntry and mEntry:GetAttribute("EquippedBackpack") or ""

	for _, bpName in BACKPACK_MODELS do
		local bpPart = clone:FindFirstChild(bpName)
		if bpPart then
			local show = (equipped == bpName)
			local t = show and 0 or 1
			if bpPart:IsA("BasePart") then bpPart.Transparency = t end
			for _, desc in bpPart:GetDescendants() do
				if desc:IsA("BasePart") then desc.Transparency = t end
			end
		end
	end
end

local function buildMercViewport(parent, mercName, weaponId)
	-- Cache hit: reparent the existing viewport to the new page, swap the
	-- weapon if needed, and return. No rig rebuild, no animation restart.
	local cached = viewportCache[mercName]
	if cached and cached.vp and cached.vp.Parent ~= parent then
		cached.vp.Parent = parent
	end
	if cached and cached.vp then
		if cached.weaponId ~= weaponId then
			applyWeaponToClone(cached.clone, weaponId)
			cached.weaponId = weaponId
		end
		syncBackpackVisibility(cached.clone, mercName)
		return cached.vp
	end

	-- Cache miss: build the full viewport (rig + hat welding + lights).
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

	-- Show or hide the Backpack accessory based on equipped state.
	syncBackpackVisibility(clone, mercName)

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

	-- Set up the picked weapon (sword / rod) on the rig.
	applyWeaponToClone(clone, weaponId)

	-- Play the plain body idle so the pirate has its breathing / sway in
	-- the preview. Runs once during the initial build; subsequent equipment
	-- swaps keep this track alive via the persistent viewport cache.
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

	-- Remember this viewport so future page switches / weapon swaps can
	-- reuse it instead of tearing down the rig (which restarts the idle
	-- animation and blinks the preview for a frame).
	viewportCache[mercName] = {
		vp       = vp,
		clone    = clone,
		weaponId = weaponId,
	}

	return vp
end

-- ─── Build the full page ────────────────────────────────────────────────

buildPage = function(mercNames)
	-- Detach cached viewports from the outgoing page so :Destroy() below
	-- doesn't take them (and the rig + animation tracks) down with it.
	detachCachedViewports()
	if page then page:Destroy() end

	currentMercNames = mercNames
	local selectedName = mercNames[1]
	currentSelectedMerc = selectedName

	-- Full-screen page container, fully transparent — the holo
	-- backdrop below occludes the phone's own backdrop and gives the
	-- Mercenaries screen its own atmosphere.
	page = Instance.new("Frame")
	page.Name = "MercenariesPage"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ZIndex = 50
	page.Parent = screenGui

	-- Hide phone main panels so they don't show through
	hidePhonePanels()

	-- Reset any panels registered from a previous mercenaries-page
	-- lifetime — subsequent steps will push cards here as they're
	-- built so the mote-fade heartbeat finds them.
	table.clear(motesOccludeList)

	-- Holo sea-mist backdrop — first child so everything below
	-- renders on top of it.
	buildHoloBackground(page)

	-- ── Responsive artboard (matches PhoneMenu) ──────────────────────
	-- The Claude Design canvas is 960x600; make `scaleWrap` that exact
	-- size and centre it on screen so right-anchored panels land on
	-- the artboard's own 960 mark instead of the viewport edge (which
	-- UIScale would push off-screen on large monitors).
	local topInset = GuiService:GetGuiInset().Y
	local REFERENCE_W, REFERENCE_H = 960, 600

	local scaleWrap = Instance.new("Frame")
	scaleWrap.Name = "ScaleWrap"
	scaleWrap.BackgroundTransparency = 1
	scaleWrap.BorderSizePixel = 0
	scaleWrap.AnchorPoint = Vector2.new(0.5, 0.5)
	scaleWrap.Position = UDim2.new(0.5, 0, 0.5, topInset / 2)
	scaleWrap.Size = UDim2.fromOffset(REFERENCE_W, REFERENCE_H)
	scaleWrap.ZIndex = 50
	scaleWrap.Parent = page

	local responsiveScale = Instance.new("UIScale")
	responsiveScale.Name = "ResponsiveScale"
	responsiveScale.Scale = 1
	responsiveScale.Parent = scaleWrap

	local function updateResponsiveScale()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then return end
		local sx = size.X / REFERENCE_W
		local sy = (size.Y - topInset) / REFERENCE_H
		local s = math.min(sx, sy)
		if s < 0.5 then s = 0.5 end
		responsiveScale.Scale = s
	end
	updateResponsiveScale()
	local scaleConn = screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateResponsiveScale)
	-- Disconnect when the page goes away so we don't leak listeners
	-- across repeated open/close cycles.
	page.AncestryChanged:Connect(function(_, newParent)
		if not newParent and scaleConn then
			scaleConn:Disconnect()
			scaleConn = nil
		end
	end)

	-- ── Top bar ────────────────────────────────────────────────────────
	-- Matches the MercenaryPage.jsx header: translucent holo BACK button
	-- on the left, centred uppercase MERCENARIES title, gem currency
	-- chip on the right. Lives inside scaleWrap so it resizes with the
	-- rest of the artboard on large monitors.
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.BackgroundTransparency = 1
	topBar.BorderSizePixel = 0
	topBar.Position = UDim2.fromOffset(16, 16)
	topBar.Size = UDim2.new(1, -32, 0, 34)
	topBar.ZIndex = 5
	topBar.Parent = scaleWrap

	-- Back button: holo stroke + hand-drawn back-arrow glyph + uppercase
	-- letter-spaced label.
	local backBtn = Instance.new("TextButton")
	backBtn.Name = "BackButton"
	backBtn.AnchorPoint = Vector2.new(0, 0)
	backBtn.Position = UDim2.fromOffset(0, 0)
	backBtn.Size = UDim2.fromOffset(88, 34)
	backBtn.BackgroundColor3 = HOLO_PANEL_FILL
	backBtn.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	backBtn.BorderSizePixel = 0
	backBtn.AutoButtonColor = true
	backBtn.Text = "" -- label drawn as a child for precise positioning
	backBtn.Parent = topBar
	local backStroke = Instance.new("UIStroke")
	backStroke.Color     = HOLO_PANEL_BORDER
	backStroke.Thickness = 1
	backStroke.Parent    = backBtn

	local backGlyph = makeBackIcon(backBtn, 14, COLOR_TEXT)
	backGlyph.AnchorPoint = Vector2.new(0, 0.5)
	backGlyph.Position = UDim2.new(0, 12, 0.5, 0)

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
	backLabel.Parent = backBtn

	backBtn.MouseButton1Click:Connect(function()
		closePage()
	end)

	-- Centred uppercase MERCENARIES title in holo-edge cyan.
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.BorderSizePixel = 0
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.Size = UDim2.fromOffset(240, 22)
	title.Font = FONT_TITLE
	title.TextSize = 18
	title.TextColor3 = HOLO_EDGE
	title.Text = "MERCENARIES"
	title.Parent = topBar

	-- Gem currency chip. Static "0" placeholder for now — wire to a
	-- real player attribute when Step 7 lands. Chip autosizes around
	-- the gem + number so a 5-digit count still reads cleanly.
	local chip = Instance.new("Frame")
	chip.Name = "CurrencyChip"
	chip.AnchorPoint = Vector2.new(1, 0.5)
	chip.Position = UDim2.new(1, 0, 0.5, 0)
	chip.Size = UDim2.fromOffset(96, 28)
	chip.BackgroundColor3 = HOLO_PANEL_FILL
	chip.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	chip.BorderSizePixel = 0
	chip.Parent = topBar
	local chipStroke = Instance.new("UIStroke")
	chipStroke.Color     = HOLO_PANEL_BORDER
	chipStroke.Thickness = 1
	chipStroke.Parent    = chip

	local gemGlyph = makeGemIcon(chip, 13, COLOR_GOLD)
	gemGlyph.AnchorPoint = Vector2.new(0, 0.5)
	gemGlyph.Position = UDim2.new(0, 10, 0.5, 0)

	local chipLabel = Instance.new("TextLabel")
	chipLabel.Name = "CurrencyLabel"
	chipLabel.BackgroundTransparency = 1
	chipLabel.BorderSizePixel = 0
	chipLabel.Position = UDim2.fromOffset(28, 0)
	chipLabel.Size = UDim2.new(1, -36, 1, 0)
	chipLabel.Font = FONT_TITLE
	chipLabel.TextSize = 13
	chipLabel.TextColor3 = COLOR_GOLD
	chipLabel.TextXAlignment = Enum.TextXAlignment.Left
	chipLabel.Text = "0"
	chipLabel.Parent = chip

	-- ── Left column: mercenary list ────────────────────────────────────
	-- Position from MercenaryPage.jsx: left 24, top 70, bottom 24,
	-- width 300. All panels live inside scaleWrap so they share the
	-- responsive UIScale.
	local leftCol = Instance.new("Frame")
	leftCol.Name = "LeftColumn"
	leftCol.BackgroundColor3 = HOLO_PANEL_FILL
	leftCol.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
	leftCol.BorderSizePixel = 0
	leftCol.Position = UDim2.fromOffset(24, 70)
	leftCol.Size = UDim2.new(0, 300, 1, -(70 + 24))
	leftCol.ZIndex = 3
	leftCol.Parent = scaleWrap

	local leftStroke = Instance.new("UIStroke")
	leftStroke.Color     = HOLO_PANEL_BORDER
	leftStroke.Thickness = 1
	leftStroke.Parent    = leftCol

	local leftPad = Instance.new("UIPadding")
	leftPad.PaddingTop    = UDim.new(0, 12)
	leftPad.PaddingBottom = UDim.new(0, 12)
	leftPad.PaddingLeft   = UDim.new(0, 12)
	leftPad.PaddingRight  = UDim.new(0, 12)
	leftPad.Parent = leftCol

	cornerLs(leftCol, 10, HOLO_PANEL_LBRACKET, 1.5)
	table.insert(motesOccludeList, leftCol)

	-- Header row: users glyph + "MERCENARIES" + "X / Y HIRED" count
	-- aligned right, with a hairline divider under it.
	local leftHeader = Instance.new("Frame")
	leftHeader.Name = "HeaderRow"
	leftHeader.BackgroundTransparency = 1
	leftHeader.Size = UDim2.new(1, 0, 0, 18)
	leftHeader.Parent = leftCol

	local headerGlyph = makeUsersIcon(leftHeader, 14, HOLO_EDGE)
	headerGlyph.AnchorPoint = Vector2.new(0, 0.5)
	headerGlyph.Position = UDim2.fromScale(0, 0.5)

	local leftTitle = makeLabel(leftHeader, "MERCENARIES", FONT_TITLE, 15, COLOR_TEXT)
	leftTitle.Position = UDim2.fromOffset(22, 0)
	leftTitle.Size = UDim2.new(1, -132, 1, 0)

	-- Cap of 6 matches the design's MERCS roster — it's purely a text
	-- hint; actual slot count is driven by what's in player.Mercenaries.
	local ROSTER_CAP = 6
	local countLabel = makeLabel(leftHeader,
		string.format("%d / %d HIRED", #mercNames, ROSTER_CAP),
		FONT_BODY, 11, COLOR_TEXT_DIM, Enum.TextXAlignment.Right)
	countLabel.AnchorPoint = Vector2.new(1, 0.5)
	countLabel.Position = UDim2.new(1, 0, 0.5, 0)
	countLabel.Size = UDim2.fromOffset(110, 18)

	local leftDivider = Instance.new("Frame")
	leftDivider.Name = "Divider"
	leftDivider.BackgroundColor3 = HOLO_PANEL_BORDER
	leftDivider.BackgroundTransparency = 0.3
	leftDivider.BorderSizePixel = 0
	leftDivider.Size = UDim2.new(1, 0, 0, 1)
	leftDivider.Position = UDim2.fromOffset(0, 28)
	leftDivider.Parent = leftCol

	-- Scrolling card list.
	local cardList = Instance.new("ScrollingFrame")
	cardList.Name = "CardList"
	cardList.BackgroundTransparency = 1
	cardList.BorderSizePixel = 0
	cardList.Position = UDim2.fromOffset(0, 40)
	cardList.Size = UDim2.new(1, 0, 1, -40)
	cardList.CanvasSize = UDim2.new(0, 0, 0, 0)
	cardList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	cardList.ScrollBarThickness = 4
	cardList.ScrollBarImageColor3 = HOLO_PANEL_BORDER
	cardList.ScrollBarImageTransparency = 0.3
	cardList.Parent = leftCol

	local cardLayout = Instance.new("UIListLayout")
	cardLayout.FillDirection = Enum.FillDirection.Vertical
	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardLayout.Padding = UDim.new(0, 8)
	cardLayout.Parent = cardList

	-- Per-card refs keyed by merc name, populated below. setSelectedCard
	-- iterates this to refresh stroke + corner-bracket + portrait-stroke
	-- colours on the selected and previously-selected rows.
	local mercCards = {}

	local function setSelectedCard(mercName)
		currentSelectedMerc = mercName
		for name, rec in pairs(mercCards) do
			local isSel = (name == mercName)
			local color = isSel and HOLO_EDGE or HOLO_PANEL_BORDER
			rec.stroke.Color = color
			rec.portraitStroke.Color = color
			for _, bracket in rec.brackets do
				bracket.BackgroundColor3 = isSel and HOLO_EDGE or HOLO_PANEL_LBRACKET
			end
		end
		-- Later steps will hook into this to refresh the centre viewport
		-- and the right-column characteristics panel.
	end

	-- Build one holo card per recruited mercenary.
	for i, mercName in mercNames do
		local theme = MERC_THEMES[mercName] or DEFAULT_THEME
		local displayName = theme.displayName or mercName

		local card = Instance.new("TextButton")
		card.Name = "Card_" .. mercName
		card.BackgroundColor3 = HOLO_PANEL_FILL
		card.BackgroundTransparency = HOLO_PANEL_TRANSPARENCY
		card.BorderSizePixel = 0
		card.AutoButtonColor = false
		card.Text = ""
		card.Size = UDim2.new(1, -6, 0, 72)
		card.LayoutOrder = i
		card.Parent = cardList

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color     = HOLO_PANEL_BORDER
		cardStroke.Thickness = 1
		cardStroke.Parent    = card

		local cardPad = Instance.new("UIPadding")
		cardPad.PaddingTop    = UDim.new(0, 10)
		cardPad.PaddingBottom = UDim.new(0, 10)
		cardPad.PaddingLeft   = UDim.new(0, 10)
		cardPad.PaddingRight  = UDim.new(0, 10)
		cardPad.Parent = card

		-- Portrait slot — 52x52, translucent fill, hairline border, mini
		-- corner L's. Character icon sits centred inside.
		local portrait = Instance.new("Frame")
		portrait.Name = "Portrait"
		portrait.AnchorPoint = Vector2.new(0, 0.5)
		portrait.Position = UDim2.new(0, 0, 0.5, 0)
		portrait.Size = UDim2.fromOffset(52, 52)
		portrait.BackgroundColor3 = Color3.fromRGB(15, 35, 65)
		portrait.BackgroundTransparency = 0.65
		portrait.BorderSizePixel = 0
		portrait.Parent = card

		local portraitStroke = Instance.new("UIStroke")
		portraitStroke.Color     = HOLO_PANEL_BORDER
		portraitStroke.Thickness = 1
		portraitStroke.Parent    = portrait

		cornerLs(portrait, 5, HOLO_PANEL_LBRACKET, 1.5)

		local charGlyph = makeCharacterIcon(portrait, 28, HOLO_PANEL_LBRACKET)
		charGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
		charGlyph.Position = UDim2.fromScale(0.5, 0.5)

		-- Right side of the card: name row (+ OWNED chip) / star row / role
		-- line, all left-aligned starting 62 px in so they sit clear of
		-- the 52-wide portrait plus its 10 px gap.
		local name = makeLabel(card, displayName, FONT_TITLE, 15, COLOR_TEXT)
		name.Position = UDim2.fromOffset(62, 0)
		name.Size = UDim2.fromOffset(130, 18)

		-- OWNED chip in green stroke — every merc we render here comes
		-- from player.Mercenaries, so they're by definition recruited.
		local ownedChip = Instance.new("Frame")
		ownedChip.Name = "OwnedChip"
		ownedChip.AnchorPoint = Vector2.new(0, 0.5)
		ownedChip.Position = UDim2.new(0, 62 + 80, 0, 9)
		ownedChip.Size = UDim2.fromOffset(44, 14)
		ownedChip.BackgroundTransparency = 1
		ownedChip.BorderSizePixel = 0
		ownedChip.Parent = card
		local ownedStroke = Instance.new("UIStroke")
		ownedStroke.Color     = Color3.fromRGB(110, 200, 140)
		ownedStroke.Thickness = 1
		ownedStroke.Parent    = ownedChip
		local ownedLbl = makeLabel(ownedChip, "OWNED", FONT_TITLE, 8,
			Color3.fromRGB(110, 200, 140), Enum.TextXAlignment.Center)
		ownedLbl.Size = UDim2.fromScale(1, 1)

		local starRow = makeStarRow(card, theme.stars or 1, 5, 9, COLOR_GOLD)
		starRow.Position = UDim2.fromOffset(62, 24)

		local role = makeLabel(card, theme.role or "Crew", FONT_BODY, 10, COLOR_TEXT_DIM)
		role.Position = UDim2.fromOffset(62, 38)
		role.Size = UDim2.fromOffset(150, 14)

		-- Collect bracket refs so selection recolouring can tint them
		-- without re-creating the Frames.
		local brackets = {}
		for _, child in card:GetChildren() do
			if child.Name == "CornerL_H" or child.Name == "CornerL_V" then
				table.insert(brackets, child)
			end
		end
		-- Panel-level brackets haven't been added yet — do it now so
		-- they can also tint with selection.
		cornerLs(card, 8, HOLO_PANEL_LBRACKET, 1.5)
		for _, child in card:GetChildren() do
			if (child.Name == "CornerL_H" or child.Name == "CornerL_V")
				and not table.find(brackets, child) then
				table.insert(brackets, child)
			end
		end

		card.MouseButton1Click:Connect(function()
			setSelectedCard(mercName)
		end)

		mercCards[mercName] = {
			frame          = card,
			stroke         = cardStroke,
			portraitStroke = portraitStroke,
			brackets       = brackets,
		}
	end

	-- Apply initial selection (first merc in the roster).
	if selectedName then setSelectedCard(selectedName) end
end

-- ─── Equipment data ─────────────────────────────────────────────────────

local EQUIP_CATEGORIES = { "Weapons", "Artifacts" }

local EQUIP_ITEMS = {
	Weapons = {
		{
			id            = "Unarmed",
			displayName   = "Unarmed",
			typeName      = "None",
			stars         = 1,
			baseAttack    = 0,
			description   = "No weapon. Mercenary carries nothing in hand.",
			alwaysUnlocked = true,
		},
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
			icon          = "rbxassetid://105180666555503",
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
		{
			id            = "BackPack_lvl2",
			displayName   = "Backpack Lvl 2",
			typeName      = "Artifact",
			stars         = 2,
			baseAttack    = 0,
			description   = "An upgraded pirate backpack with extra storage. Holds 9 items.",
			icon          = "rbxassetid://85728179321673",
		},
	},
}

-- ─── Build equipment page ───────────────────────────────────────────────

buildEquipmentPage = function(mercName, mercNames)
	-- Detach cached viewports from the outgoing page so :Destroy() below
	-- doesn't take them (and the rig + animation tracks) down with it.
	detachCachedViewports()
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
	-- Unarmed is always available (removes the held weapon)
	unlockedSet["Unarmed"] = true
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
		-- Don't destroy the cached viewport — buildMercViewport reuses the
		-- existing rig + animator and only swaps the weapon in-place, so the
		-- preview doesn't blink and the idle track keeps playing.
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
				iconLabel.Text = (item.id == "Sword" and "⚔")
					or (item.id == "Unarmed" and "✋")
					or "🎣"
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
			local equipSoundsFolder = SoundService:FindFirstChild("Items_equip")
			if activeCategory == "Artifacts" then
				local alreadyEquipped = mercEntry:GetAttribute("EquippedBackpack") == selectedItemId
				mercEntry:SetAttribute("EquippedBackpack", selectedItemId)
				if not alreadyEquipped and equipSoundsFolder then
					local bpSound = equipSoundsFolder:FindFirstChild("backpack_equip")
					if bpSound then bpSound:Play() end
				end
			else
				local alreadyEquipped = mercEntry:GetAttribute("EquippedWeapon") == selectedItemId
				mercEntry:SetAttribute("EquippedWeapon", selectedItemId)
				if not alreadyEquipped and equipSoundsFolder then
					local soundName = nil
					if selectedItemId == "Sword" then
						soundName = "Sword_pirate_equip"
					elseif selectedItemId == "FishingRod" then
						soundName = "FishingRod_1lvl_equip"
					end
					if soundName then
						local snd = equipSoundsFolder:FindFirstChild(soundName)
						if snd then snd:Play() end
					end
				end
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
	-- Clear the viewport cache before tearing down the page. The cached
	-- ViewportFrames live inside `page`, so p:Destroy() below kills them
	-- anyway — but if we leave stale entries in the table, the next
	-- openMercenariesMenu() call would hit them, try to reparent a
	-- destroyed instance, and the character would silently fail to
	-- appear. A fresh open rebuilds from scratch.
	for mercName in pairs(viewportCache) do
		viewportCache[mercName] = nil
	end
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
