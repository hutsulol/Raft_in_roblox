-- PhoneMenu.client.lua
-- Full-screen menu that opens when the player presses E while holding the
-- Phone tool. This milestone is VISUALS ONLY — layout, panels and labels
-- are built, but none of the buttons/bars are wired to gameplay.
--
-- Layout (matches the reference mockup):
--   top-left     : level badge + upgrade points counter
--   left column  : attribute bars (Strength / Mana / Mutation)
--   bottom       : XP bar
--   top-right    : daily tasks + reward
--   bottom-right : Arsenal / Mercenaries buttons

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Holographic glitch-in animation. Plays on every open; requires a
-- LoadBar (Frame) and LoadText (TextLabel) as direct children of the
-- frame we pass in — both are created in buildMenu() below.
local HoloOpenAnimation = require(script.Parent:WaitForChild("HoloOpenAnimation"))

-- Pose used for the viewport character. Custom looping idle that keeps the
-- rig in a clean standing stance for the UI preview.
local IDLE_ANIMATION_ID = "rbxassetid://78578604994580"

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
local menuOpen              = false
local phoneEquipped         = false
local screenGui             = nil
-- Refs used by the holo-open animation. `holoRootFrame` is the frame
-- we scale/fade on every open, and holoLoadBar / holoLoadText are
-- the per-open LOAD… progress pair the HoloOpenAnimation module drives.
-- `holoPulseStop` is the stop handle for the idle heartbeat the module
-- returns — we call it on close so the pulse doesn't leak across opens.
local holoRootFrame         = nil
local holoLoadBar           = nil
local holoLoadText          = nil
local holoPulseStop         = nil
-- Set to true after `refreshCharacterViewport()` has built the rig for the
-- current life. Gates the refresh so subsequent menu opens are instant and
-- reuse the same viewport contents. Reset to false when the player respawns
-- so the next open rebuilds against the new character.
local viewportInitialized   = false

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

-- ─── Menu construction ────────────────────────────────────────────────────
local viewportFrame = nil
local viewportWorld = nil
local viewportCamera = nil
local viewportCharModel = nil

-- Live references the Characteristics binding updates. Set during
-- buildMenu() and re-read by refreshCharacteristics() every time a
-- replicated IntValue changes.
local levelBadgeLabel    = nil
local upgradePointsLabel = nil
-- Upgradable attribute rows. Each entry is populated by buildMenu() and
-- consumed by refreshCharacteristics() to drive the bar, level label and
-- "+" button state from the replicated Characteristics folder.
local statRows = {
	Strength = { fill = nil, lvl = nil, button = nil, action = "upgradeStrength" },
	Mana     = { fill = nil, lvl = nil, button = nil, action = "upgradeMana"     },
	Mutation = { fill = nil, lvl = nil, button = nil, action = "upgradeMutation" },
}
local xpAmountLabel      = nil
local xpFillFrame        = nil

-- Tasks panel refs. `dailyQuestRows` is rebuilt every time the
-- replicated DailyQuests folder changes shape (new day, different
-- quest count) — each entry is keyed by quest id and holds the row
-- frame plus the check-box / label elements we repaint on progress
-- updates. `dailyClaimButton` becomes clickable once every quest is
-- complete, and goes away once the reward is claimed.
local dailyQuestsHolder  = nil
local dailyAllCompleteLabel = nil
local dailyRewardLabel   = nil
local dailyClaimButton   = nil
local dailyTimerLabel    = nil
local dailyQuestRows     = {}
local dailyQuestConnections = {}

-- Build a static preview rig from the player's HumanoidDescription. This
-- gives us a fresh R15 model in a clean neutral pose (like the Avatar
-- Editor) that matches the player's appearance, instead of a snapshot of
-- the live character mid-animation. Falls back to a plain clone if the
-- description API fails for any reason.
local function buildPreviewRig()
	local ok, rig = pcall(function()
		local desc = Players:GetHumanoidDescriptionFromUserId(player.UserId)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if ok and rig then return rig end

	-- Fallback: clone the live character.
	local char = player.Character
	if not char then return nil end
	local wasArchivable = char.Archivable
	char.Archivable = true
	local clone = char:Clone()
	char.Archivable = wasArchivable
	return clone
end

-- Rebuild the character display inside the ViewportFrame. Builds a fresh
-- preview rig from the player's HumanoidDescription (so the pose is always
-- clean and neutral), strips scripts, anchors parts, rotates it so its
-- front faces the camera, and attaches lights for depth. Called every time
-- the menu opens so the clone always reflects the current appearance.
local function refreshCharacterViewport()
	if not viewportFrame or not viewportWorld then return end

	if viewportCharModel then
		viewportCharModel:Destroy()
		viewportCharModel = nil
	end

	local clone = buildPreviewRig()
	if not clone then return end

	-- Destroy every Script / LocalScript on the rig — in particular the
	-- `Animate` LocalScript that drives walk/jump/idle animations on live
	-- characters. Without this the clone would keep cycling animations.
	-- Also strip Highlight / SelectionBox instances so the preview rig
	-- doesn't carry over any gameplay outlines (mining highlight, pickup
	-- glow, etc.) that might have been attached to the live character.
	for _, d in clone:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("Highlight") or d:IsA("SelectionBox") then
			d:Destroy()
		end
	end

	-- Stop any AnimationTracks that may already be playing on the humanoid
	-- / animator before we force our idle pose.
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local animator
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.EvaluateStateMachine = false
		-- Disable every Humanoid state so the rig can't ragdoll, fall,
		-- jump, swim, climb, or otherwise react to anything in the
		-- WorldModel. The idle animation is what poses the limbs.
		for _, state in Enum.HumanoidStateType:GetEnumItems() do
			pcall(function()
				humanoid:SetStateEnabled(state, false)
			end)
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

	-- Only the HumanoidRootPart is anchored — the rest of the rig must
	-- remain unanchored so the idle AnimationTrack can pose the limbs via
	-- Motor6D.Transform. WorldModel does not simulate physics so the limbs
	-- cannot fall or drift regardless.
	local hrp = clone:FindFirstChild("HumanoidRootPart")
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Massless = true
			d.Anchored = (d == hrp)
		end
	end

	-- Place the clone at a slightly raised origin, rotated 180° around Y so
	-- its front faces the +Z axis — that's where the camera sits. The small
	-- +Y lift keeps the feet from sinking against the bottom of the frame.
	clone:PivotTo(CFrame.new(0, 0.5, 0) * CFrame.Angles(0, math.pi, 0))

	-- Force the custom idle animation. This mirrors the exact order that
	-- used to work with the stock Roblox idle — load the track, loop it,
	-- play it at Action priority. The clone gets parented to the
	-- WorldModel AFTER the lights block below, just like the original
	-- working version.
	if animator then
		local anim = Instance.new("Animation")
		anim.AnimationId = IDLE_ANIMATION_ID
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0)
	end

	-- Multi-light setup to give the clone depth and shape. A single light
	-- flattens the model — we need a bright key light in front and a cyan
	-- rim light behind for an outline glow. PointLights only render inside
	-- a ViewportFrame when their ancestor is a WorldModel (which the clone
	-- is parented to below). Attachments are used to position each light
	-- relative to the HumanoidRootPart.
	local root = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
	if root and root:IsA("BasePart") then
		-- Key light: white, in front and slightly above (camera side).
		local keyAtt = Instance.new("Attachment")
		keyAtt.Name = "PhoneMenuKeyLightAtt"
		keyAtt.Position = Vector3.new(0, 2, 4)
		keyAtt.Parent = root

		local keyLight = Instance.new("PointLight")
		keyLight.Name = "PhoneMenuKeyLight"
		keyLight.Color = Color3.fromRGB(255, 255, 255)
		keyLight.Brightness = 2
		keyLight.Range = 16
		keyLight.Shadows = false
		keyLight.Parent = keyAtt

		-- Rim light: cyan, behind the character for an outline glow.
		local rimAtt = Instance.new("Attachment")
		rimAtt.Name = "PhoneMenuRimLightAtt"
		rimAtt.Position = Vector3.new(0, 2, -4)
		rimAtt.Parent = root

		local rimLight = Instance.new("PointLight")
		rimLight.Name = "PhoneMenuRimLight"
		rimLight.Color = Color3.fromRGB(0, 255, 255)
		rimLight.Brightness = 2
		rimLight.Range = 14
		rimLight.Shadows = false
		rimLight.Parent = rimAtt

		-- Soft fill from below so the legs/torso don't read as a black slab.
		local fillAtt = Instance.new("Attachment")
		fillAtt.Name = "PhoneMenuFillLightAtt"
		fillAtt.Position = Vector3.new(-2, -1, 3)
		fillAtt.Parent = root

		local fillLight = Instance.new("PointLight")
		fillLight.Name = "PhoneMenuFillLight"
		fillLight.Color = Color3.fromRGB(180, 210, 255)
		fillLight.Brightness = 1
		fillLight.Range = 12
		fillLight.Shadows = false
		fillLight.Parent = fillAtt
	end

	clone.Parent = viewportWorld
	viewportCharModel = clone

	if viewportCamera then
		-- Centered front view, pulled in closer and aimed at chest height so
		-- the character reads larger and sits dead-center in the viewport.
		-- Narrower FOV (50) tightens the framing without cropping.
		viewportCamera.FieldOfView = 50
		viewportCamera.CFrame = CFrame.new(Vector3.new(0, 2.2, 6.2), Vector3.new(0, 1.2, 0))
	end
end

local function buildMenu()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PhoneMenu"
	screenGui.ResetOnSpawn = false
	-- IgnoreGuiInset = true so the backdrop covers the ENTIRE screen
	-- (including the strip behind the Roblox topbar). The Root frame
	-- below is manually pushed down past the topbar so the interactive
	-- panels still stay clear of the Roblox chrome.
	screenGui.IgnoreGuiInset = true
	screenGui.Enabled = false
	screenGui.DisplayOrder = 50
	screenGui.Parent = playerGui

	-- Dimming backdrop — full-screen because the ScreenGui ignores the
	-- topbar inset. No visible strip of world behind the topbar anymore.
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.BackgroundColor3 = COLOR_BG
	backdrop.BackgroundTransparency = 0.25
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = screenGui

	-- Root frame hosts the interactive UI. Inset by the Roblox topbar
	-- height at the top (plus a small margin) so the level / tasks
	-- panels never slide under the Roblox chrome on any device.
	local topInset = GuiService:GetGuiInset().Y
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.new(0, 30, 0, topInset + 20)
	root.Size = UDim2.new(1, -60, 1, -(topInset + 50))
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
	viewportCamera.FieldOfView = 55
	viewportCamera.CFrame = CFrame.new(Vector3.new(1.5, 2, 8), Vector3.new(0, 1, 0))
	viewportCamera.Parent = viewportFrame
	viewportFrame.CurrentCamera = viewportCamera

	-- ── Top-left: level + upgrade points ─────────────────────────────────
	-- Left column (level badge + stats) is nudged ~60px below the root's
	-- top edge so it clears the Roblox topbar icons (logo / menu / chat)
	-- on non-Studio clients where those buttons extend past GuiInset.
	local levelPanel = makePanel("LevelPanel", root)
	levelPanel.AnchorPoint = Vector2.new(0, 0)
	levelPanel.Position = UDim2.fromOffset(0, 60)
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

	local lvlNum = makeLabel(lvlBadge, "1", FONT_TITLE, 22, COLOR_ACCENT, Enum.TextXAlignment.Center)
	lvlNum.Size = UDim2.new(1, 0, 0, 28)
	lvlNum.Position = UDim2.fromOffset(0, 18)
	levelBadgeLabel = lvlNum

	local nameLbl = makeLabel(levelPanel, player.DisplayName ~= "" and player.DisplayName or player.Name, FONT_TITLE, 22, COLOR_TEXT)
	nameLbl.Position = UDim2.fromOffset(60, 0)
	nameLbl.Size = UDim2.new(1, -60, 0, 28)

	local pointsLbl = makeLabel(levelPanel, "Upgrade points: 0", FONT_BODY, 14, COLOR_ACCENT)
	pointsLbl.Position = UDim2.fromOffset(60, 30)
	pointsLbl.Size = UDim2.new(1, -60, 0, 20)
	upgradePointsLabel = pointsLbl

	-- ── Left column: attribute bars ────────────────────────────────────
	local statsPanel = makePanel("StatsPanel", root)
	statsPanel.AnchorPoint = Vector2.new(0, 0)
	statsPanel.Position = UDim2.fromOffset(0, 145)
	statsPanel.Size = UDim2.fromOffset(340, 190)
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

	-- Attribute rows — Strength / Mana / Mutation. All three are
	-- upgradable: each has a "+" button that fires its action string on
	-- PhoneMenuAction, and Characteristics.server.lua bumps the matching
	-- IntValue back down into refreshCharacteristics().
	local stats = {
		{ name = "Strength", key = "Strength" },
		{ name = "Mana",     key = "Mana"     },
		{ name = "Mutation", key = "Mutation" },
	}
	for i, s in ipairs(stats) do
		local row, fill, lvlLabel = makeBar(rowHolder, 0, s.name)
		row.LayoutOrder = i
		lvlLabel.Text = "lvl 0"

		local btn = Instance.new("TextButton")
		btn.Name = s.key .. "Upgrade"
		btn.BackgroundColor3 = COLOR_BAR_BG
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = true
		btn.Size = UDim2.fromOffset(26, 26)
		btn.AnchorPoint = Vector2.new(1, 0.5)
		btn.Position = UDim2.new(1, -46, 0.5, 0)
		btn.Font = FONT_TITLE
		btn.TextSize = 18
		btn.TextColor3 = COLOR_ACCENT
		btn.Text = "+"
		btn.Parent = row
		corner(btn, 6)
		stroke(btn, 1, COLOR_PANEL_EDGE)

		local rec = statRows[s.key]
		rec.fill   = fill
		rec.lvl    = lvlLabel
		rec.button = btn
	end

	-- ── Top-right: daily tasks ─────────────────────────────────────────
	-- Structure only — the quest rows, reward label and claim button
	-- are all (re)populated by refreshDailyQuests() from the replicated
	-- DailyQuests folder.
	local tasksPanel = makePanel("TasksPanel", root)
	tasksPanel.AnchorPoint = Vector2.new(1, 0)
	tasksPanel.Position = UDim2.new(1, 0, 0, 0)
	tasksPanel.Size = UDim2.fromOffset(320, 230)
	padding(tasksPanel, 12)

	local tasksTitle = makeLabel(tasksPanel, "Tasks for today:", FONT_TITLE, 18, COLOR_TEXT)
	tasksTitle.Size = UDim2.new(0, 170, 0, 22)

	-- Countdown until the next UTC midnight. dailyTimerLabel is a
	-- module-level ref so the heartbeat task below can rewrite it
	-- every second while the menu exists.
	local timerLbl = makeLabel(tasksPanel, "", FONT_BODY, 14, COLOR_TEXT_DIM, Enum.TextXAlignment.Right)
	timerLbl.Position = UDim2.new(1, -170, 0, 2)
	timerLbl.Size = UDim2.fromOffset(170, 20)
	dailyTimerLabel = timerLbl

	local tasksHolder = Instance.new("Frame")
	tasksHolder.Name = "TasksHolder"
	tasksHolder.BackgroundTransparency = 1
	tasksHolder.Position = UDim2.fromOffset(0, 30)
	tasksHolder.Size = UDim2.new(1, 0, 0, 110)
	tasksHolder.Parent = tasksPanel

	local tList = Instance.new("UIListLayout")
	tList.SortOrder = Enum.SortOrder.LayoutOrder
	tList.Padding = UDim.new(0, 8)
	tList.Parent = tasksHolder

	-- Shown in place of the quest rows once every quest is complete — the
	-- individual rows still live in `tasksHolder` so rebuilding for a new
	-- day just re-shows the holder and hides this label again.
	local allDoneLbl = makeLabel(tasksPanel, "All tasks completed!", FONT_TITLE, 18, COLOR_ACCENT, Enum.TextXAlignment.Center)
	allDoneLbl.Position = UDim2.fromOffset(0, 30)
	allDoneLbl.Size = UDim2.new(1, 0, 0, 110)
	allDoneLbl.Visible = false
	dailyAllCompleteLabel = allDoneLbl

	local rewardLbl = makeLabel(tasksPanel, "Reward:", FONT_TITLE, 16, COLOR_TEXT)
	rewardLbl.Position = UDim2.fromOffset(0, 146)
	rewardLbl.Size = UDim2.fromOffset(80, 22)

	local rewardValue = makeLabel(tasksPanel, "", FONT_TITLE, 16, COLOR_ACCENT)
	rewardValue.Position = UDim2.fromOffset(82, 146)
	rewardValue.Size = UDim2.new(1, -82, 0, 22)

	local claimBtn = Instance.new("TextButton")
	claimBtn.Name = "ClaimButton"
	claimBtn.BackgroundColor3 = COLOR_BAR_BG
	claimBtn.BorderSizePixel = 0
	claimBtn.Position = UDim2.fromOffset(0, 175)
	claimBtn.Size = UDim2.new(1, 0, 0, 32)
	claimBtn.Font = FONT_TITLE
	claimBtn.TextSize = 16
	claimBtn.TextColor3 = COLOR_TEXT_DIM
	claimBtn.AutoButtonColor = false
	claimBtn.Text = "Claim reward"
	claimBtn.Active = false
	claimBtn.Parent = tasksPanel
	corner(claimBtn, 8)
	stroke(claimBtn, 1.5, COLOR_PANEL_EDGE)

	dailyQuestsHolder = tasksHolder
	dailyRewardLabel  = rewardValue
	dailyClaimButton  = claimBtn

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
	-- Anchored to the bottom edge of the ViewportFrame so that the XP bar
	-- always sits directly under the character no matter the screen size.
	-- The ViewportFrame is centered at (0.5, 0.45) with Size (360, 500),
	-- so its bottom edge = (0.5 scale, 0.45 scale + 250 offset). Place the
	-- XP panel's top edge 10 px below that via AnchorPoint (0.5, 0) and
	-- Position (0.5, 0, 0.45, 260). Fixed-offset width keeps the bar the
	-- same visual size across resolutions (desktop and mobile alike).
	local xpPanel = makePanel("XPPanel", root)
	xpPanel.AnchorPoint = Vector2.new(0.5, 0)
	-- Offset 240 puts the top edge of the XP bar exactly on the crop
	-- line of the viewport character (waist height) — touching the
	-- character without overlapping and without leaving a gap.
	xpPanel.Position = UDim2.new(0.5, 0, 0.45, 240)
	xpPanel.Size = UDim2.fromOffset(440, 48)
	padding(xpPanel, 10)

	local xpTag = makeLabel(xpPanel, "XP", FONT_TITLE, 18, COLOR_TEXT)
	xpTag.Size = UDim2.new(0, 28, 1, 0)

	local xpAmount = makeLabel(xpPanel, "0 / 50", FONT_BODY, 16, COLOR_TEXT_DIM)
	xpAmount.Position = UDim2.fromOffset(30, 0)
	xpAmount.Size = UDim2.new(0, 50, 1, 0)
	xpAmountLabel = xpAmount

	local xpTrack = Instance.new("Frame")
	xpTrack.BackgroundColor3 = COLOR_BAR_BG
	xpTrack.BorderSizePixel = 0
	xpTrack.Position = UDim2.fromOffset(82, 9)
	xpTrack.Size = UDim2.new(1, -92, 0, 14)
	xpTrack.Parent = xpPanel
	corner(xpTrack, 7)
	stroke(xpTrack, 1, COLOR_PANEL_EDGE)

	local xpFill = Instance.new("Frame")
	xpFill.BackgroundColor3 = COLOR_XP_FILL
	xpFill.BorderSizePixel = 0
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.Parent = xpTrack
	corner(xpFill, 7)
	xpFillFrame = xpFill

	-- ── Holo-open LOAD… overlay ────────────────────────────────────────
	-- LoadText / LoadBar are direct children of `root` so the
	-- HoloOpenAnimation module can find them by name. They sit in the
	-- empty space above the character viewport, centered horizontally,
	-- and are hidden once the open animation finishes.
	local loadText = makeLabel(root, "LOAD...", FONT_TITLE, 22, COLOR_TEXT, Enum.TextXAlignment.Center)
	loadText.Name = "LoadText"
	loadText.AnchorPoint = Vector2.new(0.5, 0.5)
	loadText.Position = UDim2.new(0.5, 0, 0.45, -180)
	loadText.Size = UDim2.fromOffset(240, 28)
	loadText.Visible = false

	local loadBar = Instance.new("Frame")
	loadBar.Name = "LoadBar"
	loadBar.BackgroundColor3 = COLOR_XP_FILL
	loadBar.BorderSizePixel = 0
	loadBar.AnchorPoint = Vector2.new(0, 0.5)
	loadBar.Position = UDim2.new(0.5, -120, 0.45, -150)
	loadBar.Size = UDim2.fromOffset(240, 8)
	loadBar.Visible = false
	loadBar.Parent = root
	corner(loadBar, 4)
	-- Cyan glow stroke so the bar has the "holo" feel called for in the
	-- animation spec.
	local loadGlow = Instance.new("UIStroke")
	loadGlow.Color = COLOR_XP_FILL
	loadGlow.Thickness = 2
	loadGlow.Transparency = 0.3
	loadGlow.Parent = loadBar

	holoRootFrame = root
	holoLoadBar   = loadBar
	holoLoadText  = loadText
end

-- ─── Show / hide ──────────────────────────────────────────────────────────
local function setMenuOpen(open)
	if not screenGui then buildMenu() end
	menuOpen = open
	screenGui.Enabled = open

	-- Always stop any idle pulse from the previous open so a rapid
	-- close→open doesn't leak a pulse coroutine into the new session.
	if holoPulseStop then
		holoPulseStop()
		holoPulseStop = nil
	end

	if open then
		if typeof(_G.CloseInventory) == "function" then
			_G.CloseInventory()
		end
		-- Build the viewport rig only on the first open per life. On every
		-- subsequent open the cached model / lights / camera are reused as-is
		-- so the menu appears instantly with no clone or setup cost.
		if not viewportInitialized then
			refreshCharacterViewport()
			viewportInitialized = true
		end

		-- Play the holographic glitch-in animation. LoadBar / LoadText
		-- live inside `root` only to drive the opener — reveal them for
		-- the duration of the animation and hide them again afterward.
		if holoRootFrame and holoLoadBar and holoLoadText then
			holoLoadBar.Visible  = true
			holoLoadText.Visible = true
			task.spawn(function()
				local stop = HoloOpenAnimation.PlayOpenAnimation(holoRootFrame)
				holoLoadBar.Visible  = false
				holoLoadText.Visible = false
				-- Only keep the pulse handle if the menu is still open;
				-- the user may have closed mid-animation.
				if menuOpen then
					holoPulseStop = stop
				else
					stop()
				end
			end)
		end
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

	-- Invalidate the cached viewport rig so the next menu open rebuilds
	-- against the freshly-spawned character. Everything else about the
	-- viewport (ViewportFrame, WorldModel, Camera) is reused.
	viewportInitialized = false

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

-- ─── Characteristics binding ─────────────────────────────────────────────
-- Pushes the replicated per-player `Characteristics` IntValues (created by
-- Characteristics.server.lua) into the phone-menu labels and bars, and wires
-- the Strength "+" button up to the shared PhoneMenuAction RemoteEvent.
local phoneMenuEvent = ReplicatedStorage:WaitForChild("PhoneMenuAction")

-- Dev-phase: treat 10 levels in any attribute as a full bar.
local STAT_BAR_MAX = 10

local function refreshCharacteristics()
	local folder = player:FindFirstChild("Characteristics")
	if not folder then return end

	local level         = folder:FindFirstChild("Level")
	local xp            = folder:FindFirstChild("XP")
	local xpRequired    = folder:FindFirstChild("XPRequired")
	local upgradePoints = folder:FindFirstChild("UpgradePoints")

	if levelBadgeLabel and level then
		levelBadgeLabel.Text = tostring(level.Value)
	end

	if upgradePointsLabel and upgradePoints then
		upgradePointsLabel.Text = "Upgrade points: " .. upgradePoints.Value
	end

	local hasPoints = upgradePoints and upgradePoints.Value > 0
	for key, rec in statRows do
		local stat = folder:FindFirstChild(key)
		if stat then
			if rec.lvl then
				rec.lvl.Text = "lvl " .. stat.Value
			end
			if rec.fill then
				local ratio = math.clamp(stat.Value / STAT_BAR_MAX, 0, 1)
				rec.fill.Size = UDim2.new(ratio, 0, 1, 0)
			end
		end
		if rec.button then
			rec.button.AutoButtonColor = hasPoints or false
			rec.button.TextTransparency = hasPoints and 0 or 0.5
		end
	end

	if xpAmountLabel and xp and xpRequired then
		xpAmountLabel.Text = xp.Value .. " / " .. xpRequired.Value
	end
	if xpFillFrame and xp and xpRequired then
		local ratio = xpRequired.Value > 0 and xp.Value / xpRequired.Value or 0
		xpFillFrame.Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0)
	end
end

task.spawn(function()
	local folder = player:WaitForChild("Characteristics")
	for _, v in folder:GetChildren() do
		if v:IsA("IntValue") then
			v:GetPropertyChangedSignal("Value"):Connect(refreshCharacteristics)
		end
	end
	folder.ChildAdded:Connect(function(v)
		if v:IsA("IntValue") then
			v:GetPropertyChangedSignal("Value"):Connect(refreshCharacteristics)
			refreshCharacteristics()
		end
	end)
	refreshCharacteristics()
end)

for _, rec in statRows do
	if rec.button then
		local action = rec.action
		rec.button.MouseButton1Click:Connect(function()
			phoneMenuEvent:FireServer(action)
		end)
	end
end

-- ─── Daily quests binding ────────────────────────────────────────────────
-- Mirror the replicated `DailyQuests` folder (produced by
-- DailyQuests.server.lua) into the phone-menu tasks panel: one row per
-- quest with a live progress label and a checkbox that lights up when
-- the quest is complete, plus the reward line and the claim button.

local function clearDailyQuestRows()
	for _, conn in dailyQuestConnections do
		conn:Disconnect()
	end
	table.clear(dailyQuestConnections)
	if dailyQuestsHolder then
		for _, child in dailyQuestsHolder:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		dailyQuestsHolder.Visible = true
	end
	if dailyAllCompleteLabel then
		dailyAllCompleteLabel.Visible = false
	end
	table.clear(dailyQuestRows)
end

local function formatQuestLabel(questFolder)
	local label    = questFolder:FindFirstChild("Label")
	local progress = questFolder:FindFirstChild("Progress")
	local target   = questFolder:FindFirstChild("Target")
	local base     = (label and label.Value) or questFolder.Name
	if progress and target and target.Value > 0 then
		return string.format("%s (%d/%d)", base, progress.Value, target.Value)
	end
	return base
end

local function repaintQuestRow(id)
	local rec = dailyQuestRows[id]
	if not rec then return end
	local quest = rec.folder
	if not quest or not quest.Parent then return end

	local progress  = quest:FindFirstChild("Progress")
	local target    = quest:FindFirstChild("Target")
	local completed = quest:FindFirstChild("Completed")
	local done      = completed and completed.Value

	local labelText = formatQuestLabel(quest)
	if done then
		-- Strike through the whole line so the player can see at a
		-- glance which quests they've already finished.
		rec.label.Text = "<s>" .. labelText .. "</s>"
		rec.label.TextColor3 = COLOR_TEXT_DIM
	else
		rec.label.Text = labelText
		rec.label.TextColor3 = COLOR_TEXT
	end

	if done then
		if not rec.check then
			local check = makeLabel(rec.box, "X", FONT_TITLE, 18, COLOR_ACCENT, Enum.TextXAlignment.Center)
			check.Size = UDim2.fromScale(1, 1)
			rec.check = check
		end
	else
		if rec.check then
			rec.check:Destroy()
			rec.check = nil
		end
	end
end

local function updateDailyRewardAndButton(folder)
	local claimedVal = folder:FindFirstChild("Claimed")
	local rewardXP   = folder:FindFirstChild("RewardXP")
	local rewardIron = folder:FindFirstChild("RewardIronIngots")

	if dailyRewardLabel then
		local xp   = rewardXP and rewardXP.Value or 0
		local iron = rewardIron and rewardIron.Value or 0
		if iron > 0 then
			dailyRewardLabel.Text = string.format("+%d XP   +%d Iron", xp, iron)
		else
			dailyRewardLabel.Text = string.format("+%d XP", xp)
		end
	end

	if not dailyClaimButton then return end

	-- The button lights up only when every quest is complete and the
	-- reward hasn't been claimed yet.
	local allDone = true
	local questCount = 0
	for _, child in folder:GetChildren() do
		if child:IsA("Folder") and child.Name:sub(1, 6) == "Quest_" then
			questCount = questCount + 1
			local c = child:FindFirstChild("Completed")
			if not (c and c.Value) then
				allDone = false
			end
		end
	end
	if questCount == 0 then allDone = false end

	-- Once every quest is done, swap the row list out for a single
	-- celebratory label. Rebuilding for a new day re-shows the holder.
	if dailyQuestsHolder and dailyAllCompleteLabel then
		if allDone then
			dailyQuestsHolder.Visible = false
			dailyAllCompleteLabel.Visible = true
		else
			dailyQuestsHolder.Visible = true
			dailyAllCompleteLabel.Visible = false
		end
	end

	local claimed = claimedVal and claimedVal.Value or false

	if claimed then
		dailyClaimButton.Text        = "Reward claimed"
		dailyClaimButton.TextColor3  = COLOR_TEXT_DIM
		dailyClaimButton.Active      = false
		dailyClaimButton.AutoButtonColor = false
	elseif allDone then
		dailyClaimButton.Text        = "Claim reward"
		dailyClaimButton.TextColor3  = COLOR_ACCENT
		dailyClaimButton.Active      = true
		dailyClaimButton.AutoButtonColor = true
	else
		dailyClaimButton.Text        = "Claim reward"
		dailyClaimButton.TextColor3  = COLOR_TEXT_DIM
		dailyClaimButton.Active      = false
		dailyClaimButton.AutoButtonColor = false
	end
end

local function rebuildDailyQuests(folder)
	clearDailyQuestRows()
	if not dailyQuestsHolder or not folder then return end

	-- Gather the quest folders, sort by their `Order` IntValue so the
	-- phone menu always displays them in the same sequence.
	local questFolders = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Folder") and child.Name:sub(1, 6) == "Quest_" then
			table.insert(questFolders, child)
		end
	end
	table.sort(questFolders, function(a, b)
		local ao = a:FindFirstChild("Order")
		local bo = b:FindFirstChild("Order")
		return (ao and ao.Value or 0) < (bo and bo.Value or 0)
	end)

	for i, quest in questFolders do
		local idVal = quest:FindFirstChild("Id")
		local id    = (idVal and idVal.Value) or quest.Name

		local row = Instance.new("Frame")
		row.Name = "Row_" .. id
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 26)
		row.LayoutOrder = i
		row.Parent = dailyQuestsHolder

		local box = Instance.new("Frame")
		box.BackgroundColor3 = COLOR_BAR_BG
		box.BorderSizePixel = 0
		box.Size = UDim2.fromOffset(22, 22)
		box.Position = UDim2.fromOffset(0, 2)
		box.Parent = row
		corner(box, 4)
		stroke(box, 1.5, COLOR_PANEL_EDGE)

		local label = makeLabel(row, quest.Name, FONT_BODY, 15, COLOR_TEXT)
		label.Position = UDim2.fromOffset(32, 0)
		label.Size = UDim2.new(1, -32, 1, 0)
		-- RichText lets repaintQuestRow wrap the text in <s>…</s> to
		-- strike through completed quests.
		label.RichText = true

		dailyQuestRows[id] = { folder = quest, row = row, box = box, label = label, check = nil }

		-- Watch Progress and Completed for changes so the row repaints
		-- immediately as the player earns resources.
		local progress  = quest:FindFirstChild("Progress")
		local completed = quest:FindFirstChild("Completed")
		if progress then
			table.insert(dailyQuestConnections,
				progress:GetPropertyChangedSignal("Value"):Connect(function()
					repaintQuestRow(id)
					updateDailyRewardAndButton(folder)
				end))
		end
		if completed then
			table.insert(dailyQuestConnections,
				completed:GetPropertyChangedSignal("Value"):Connect(function()
					repaintQuestRow(id)
					updateDailyRewardAndButton(folder)
				end))
		end

		repaintQuestRow(id)
	end

	updateDailyRewardAndButton(folder)
end

task.spawn(function()
	-- The folder may arrive before or after the menu GUI is built, so
	-- wait for it and then rebuild on every change. We also rebuild on
	-- Date change (new day → reroll) by watching the folder's
	-- ChildRemoved/ChildAdded — simpler is to watch the Player for a
	-- new DailyQuests folder entirely.
	local function bind(folder)
		rebuildDailyQuests(folder)

		-- Reward / claimed state updates also repaint the button.
		local claimed  = folder:FindFirstChild("Claimed")
		local rewardXP = folder:FindFirstChild("RewardXP")
		local rewardIr = folder:FindFirstChild("RewardIronIngots")
		if claimed then
			table.insert(dailyQuestConnections,
				claimed:GetPropertyChangedSignal("Value"):Connect(function()
					updateDailyRewardAndButton(folder)
				end))
		end
		if rewardXP then
			table.insert(dailyQuestConnections,
				rewardXP:GetPropertyChangedSignal("Value"):Connect(function()
					updateDailyRewardAndButton(folder)
				end))
		end
		if rewardIr then
			table.insert(dailyQuestConnections,
				rewardIr:GetPropertyChangedSignal("Value"):Connect(function()
					updateDailyRewardAndButton(folder)
				end))
		end
	end

	local folder = player:WaitForChild("DailyQuests")
	bind(folder)

	player.ChildAdded:Connect(function(child)
		if child.Name == "DailyQuests" and child:IsA("Folder") then
			bind(child)
		end
	end)
end)

if dailyClaimButton then
	dailyClaimButton.MouseButton1Click:Connect(function()
		if not dailyClaimButton.Active then return end
		phoneMenuEvent:FireServer("claimDailyReward")
	end)
end

-- ─── Daily quests reset countdown ────────────────────────────────────────
-- Daily quests reset at 00:00 UTC every day. Compute how much time is
-- left until that instant and repaint the label once a second. The loop
-- only runs while the menu is open so it doesn't fire every second for
-- the entire session.
local function secondsUntilNextUtcMidnight()
	local now = os.time()
	local t = os.date("!*t", now)
	return 86400 - (t.hour * 3600 + t.min * 60 + t.sec)
end

local function formatResetCountdown(secs)
	if secs < 0 then secs = 0 end
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	local s = secs % 60
	return string.format("Resets in %02d:%02d:%02d", h, m, s)
end

task.spawn(function()
	while true do
		if dailyTimerLabel then
			dailyTimerLabel.Text = formatResetCountdown(secondsUntilNextUtcMidnight())
		end
		task.wait(1)
	end
end)

-- ─── Input ────────────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E and phoneEquipped then
		setMenuOpen(not menuOpen)
	end
end)
