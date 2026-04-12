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
local TweenService      = game:GetService("TweenService")

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
-- Refs used by the inline holo-open animation. While the animation is
-- running, `holoCover` sits over the whole UI as an opaque fullscreen
-- Frame that hides the menu content; at the reveal moment we tween
-- its BackgroundTransparency out (while `menuRootScale` scales the
-- panels in underneath) so the menu "materializes" as the cover
-- dissolves. `loadingOverlay` is on top of the cover. `menuRoot` and
-- `menuRootBasePosition` are used by the lightweight slide-up open
-- animation played on every open after the first.
local menuRoot              = nil
local menuRootBasePosition  = nil
local menuRootScale         = nil
local holoCover             = nil
local loadingOverlay        = nil
local loadingBar            = nil
local loadingText           = nil
local loadingStroke         = nil
-- Incremented every time the menu is opened so an in-flight animation
-- from a previous open can bail out cleanly if the user closes and
-- reopens before it finishes.
local openAnimationToken    = 0
-- Set to true the first time the full holo-open animation finishes in
-- this session. Once set, subsequent opens play the much shorter
-- slide-up animation instead so only the initial reveal has the heavy
-- sci-fi effect.
local holoOpenPlayed        = false
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
local dailyResetButton   = nil
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

	-- Root hosts the interactive UI. It's a plain Frame — the menu stays
	-- fully built and laid out beneath an opaque `holoCover` sibling
	-- (created later in this function) that hides it during the holo
	-- open animation and fades out at the reveal moment. Inset by the
	-- Roblox topbar height at the top (plus a small margin) so the
	-- level / tasks panels never slide under the Roblox chrome on any
	-- device.
	local topInset = GuiService:GetGuiInset().Y
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.new(0, 30, 0, topInset + 20)
	root.Size = UDim2.new(1, -60, 1, -(topInset + 50))
	root.Parent = screenGui

	-- UIScale we drive for the final "materialize" tween (0.85 → 1),
	-- so the panels subtly zoom in behind the dissolving cover.
	local rootScale = Instance.new("UIScale")
	rootScale.Name = "HoloScale"
	rootScale.Scale = 1
	rootScale.Parent = root

	menuRoot             = root
	menuRootBasePosition = root.Position
	menuRootScale        = rootScale

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
	tasksPanel.Size = UDim2.fromOffset(320, 260)
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

	-- DEV: reset tasks button (rerolls quests for testing)
	local resetBtn = Instance.new("TextButton")
	resetBtn.Name = "ResetTasksButton"
	resetBtn.BackgroundColor3 = Color3.fromRGB(120, 50, 50)
	resetBtn.BorderSizePixel = 0
	resetBtn.Position = UDim2.fromOffset(0, 212)
	resetBtn.Size = UDim2.new(1, 0, 0, 24)
	resetBtn.Font = FONT_BODY
	resetBtn.TextSize = 13
	resetBtn.TextColor3 = Color3.fromRGB(255, 180, 180)
	resetBtn.AutoButtonColor = true
	resetBtn.Text = "Reset Tasks (DEV)"
	resetBtn.Parent = tasksPanel
	corner(resetBtn, 6)

	dailyQuestsHolder = tasksHolder
	dailyRewardLabel  = rewardValue
	dailyClaimButton  = claimBtn
	dailyResetButton  = resetBtn

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

	-- ── Holo-open cover ────────────────────────────────────────────────
	-- Opaque fullscreen Frame stacked over `root` (created AFTER root so
	-- it sits on top of it in sibling draw order) that completely hides
	-- the menu content during the holo-open animation. At the reveal
	-- moment Phase 5 tweens its BackgroundTransparency from 0 → 1, so
	-- the menu "materializes" as the cover dissolves.
	local cover = Instance.new("Frame")
	cover.Name = "HoloCover"
	cover.BackgroundColor3 = COLOR_BG
	cover.BackgroundTransparency = 0
	cover.BorderSizePixel = 0
	cover.Size = UDim2.fromScale(1, 1)
	cover.Visible = false
	cover.Parent = screenGui
	holoCover = cover

	-- ── Holo-open LOAD… overlay ────────────────────────────────────────
	-- Sibling of `root` / `holoCover` (NOT a child), created LAST so it
	-- renders on top of the cover. The overlay is visible *while* the
	-- menu is hidden, and hides itself once the menu is revealed.
	local overlay = Instance.new("Frame")
	overlay.Name = "LoadingOverlay"
	overlay.BackgroundTransparency = 1
	overlay.AnchorPoint = Vector2.new(0.5, 0.5)
	overlay.Position = UDim2.fromScale(0.5, 0.5)
	overlay.Size = UDim2.fromOffset(300, 60)
	overlay.Visible = false
	overlay.Parent = screenGui

	local loadText = makeLabel(overlay, "LOAD...", FONT_TITLE, 22, COLOR_TEXT, Enum.TextXAlignment.Center)
	loadText.Name = "LoadText"
	loadText.AnchorPoint = Vector2.new(0.5, 0)
	loadText.Position = UDim2.new(0.5, 0, 0, 0)
	loadText.Size = UDim2.fromOffset(260, 28)

	local loadTrack = Instance.new("Frame")
	loadTrack.Name = "LoadTrack"
	loadTrack.BackgroundColor3 = COLOR_BAR_BG
	loadTrack.BorderSizePixel = 0
	loadTrack.AnchorPoint = Vector2.new(0.5, 0)
	loadTrack.Position = UDim2.new(0.5, 0, 0, 34)
	loadTrack.Size = UDim2.fromOffset(260, 8)
	loadTrack.Parent = overlay
	corner(loadTrack, 4)

	local loadBar = Instance.new("Frame")
	loadBar.Name = "LoadBar"
	loadBar.BackgroundColor3 = COLOR_XP_FILL
	loadBar.BorderSizePixel = 0
	loadBar.AnchorPoint = Vector2.new(0, 0.5)
	loadBar.Position = UDim2.new(0, 0, 0.5, 0)
	loadBar.Size = UDim2.fromScale(0, 1)
	loadBar.Parent = loadTrack
	corner(loadBar, 4)

	-- Cyan glow stroke so the bar has the "holo" feel, and also doubles
	-- as one of the channels we tint during the RGB-shift phase.
	local loadGlow = Instance.new("UIStroke")
	loadGlow.Color = COLOR_XP_FILL
	loadGlow.Thickness = 2
	loadGlow.Transparency = 0.3
	loadGlow.Parent = loadBar

	loadingOverlay = overlay
	loadingBar     = loadBar
	loadingText    = loadText
	loadingStroke  = loadGlow
end

-- ─── Holo-open animation (inline) ─────────────────────────────────────────
-- Solo-Leveling / sci-fi HUD style opener. Runs entirely on the loading
-- overlay: the menu panels stay hidden beneath an opaque `holoCover`
-- Frame until the loading sequence finishes, at which point the cover
-- dissolves and the panels subtly scale in as the "result" of the
-- animation completing. All tuning lives here so it's easy to tweak
-- feel without touching the flow.

local HOLO_GLITCH_DURATION   = 0.22
local HOLO_GLITCH_STEP       = 0.025
local HOLO_GLITCH_OFFSET_MAX = 7

local HOLO_RGB_STEPS         = 6
local HOLO_RGB_STEP          = 0.03

local HOLO_LOAD_DURATION     = 0.8

local HOLO_FLICKER_COUNT     = 3
local HOLO_FLICKER_STEP      = 0.045

local HOLO_APPEAR_DURATION   = 0.35
local HOLO_APPEAR_FROM_SCALE = 0.85

local HOLO_RED = Color3.fromRGB(255, 64, 96)
local HOLO_BLU = Color3.fromRGB(64, 160, 255)

local function holoJitter(range)
	return (math.random() * 2 - 1) * range
end

-- Returns true if `token` is still the latest open token. Used so an
-- in-flight animation can abort if the user closed+reopened the menu.
local function holoTokenAlive(token)
	return token == openAnimationToken and menuOpen
end

local function runHoloOpenAnimation(token)
	-- Reset loading state before showing it.
	loadingText.Text                  = "LOAD..."
	loadingText.TextColor3            = COLOR_TEXT
	loadingText.TextTransparency      = 0
	loadingBar.BackgroundTransparency = 0
	loadingBar.Size                   = UDim2.fromScale(0, 1)
	loadingStroke.Color               = COLOR_XP_FILL
	loadingStroke.Transparency        = 0.3
	loadingOverlay.Position           = UDim2.fromScale(0.5, 0.5)
	loadingOverlay.Visible            = true

	-- Keep the menu fully hidden behind the cover + slightly zoomed
	-- until the final reveal.
	holoCover.BackgroundTransparency = 0
	holoCover.Visible                = true
	menuRootScale.Scale              = HOLO_APPEAR_FROM_SCALE

	-- Kick the progress-bar fill in parallel with the glitch + RGB phases.
	local fillTween = TweenService:Create(
		loadingBar,
		TweenInfo.new(HOLO_LOAD_DURATION, Enum.EasingStyle.Linear),
		{ Size = UDim2.fromScale(1, 1) }
	)
	fillTween:Play()

	-- Phase 1: glitch jitter — random position + transparency flicker.
	local origPos = loadingOverlay.Position
	local elapsed = 0
	while elapsed < HOLO_GLITCH_DURATION do
		if not holoTokenAlive(token) then fillTween:Cancel() return end
		loadingOverlay.Position = origPos + UDim2.fromOffset(
			math.floor(holoJitter(HOLO_GLITCH_OFFSET_MAX)),
			math.floor(holoJitter(HOLO_GLITCH_OFFSET_MAX))
		)
		loadingText.TextTransparency      = 0.2 + math.random() * 0.55
		loadingBar.BackgroundTransparency = 0.2 + math.random() * 0.55
		task.wait(HOLO_GLITCH_STEP)
		elapsed += HOLO_GLITCH_STEP
	end
	loadingOverlay.Position           = origPos
	loadingText.TextTransparency      = 0
	loadingBar.BackgroundTransparency = 0

	-- Phase 2: RGB channel shift on text + bar stroke.
	for i = 1, HOLO_RGB_STEPS do
		if not holoTokenAlive(token) then fillTween:Cancel() return end
		local odd = (i % 2) == 1
		loadingText.TextColor3 = odd and HOLO_RED or HOLO_BLU
		loadingStroke.Color    = odd and HOLO_BLU or HOLO_RED
		task.wait(HOLO_RGB_STEP + math.random() * 0.015)
	end
	loadingText.TextColor3 = COLOR_TEXT
	loadingStroke.Color    = COLOR_XP_FILL

	-- Phase 3: wait for the loading bar to reach 100%.
	if fillTween.PlaybackState ~= Enum.PlaybackState.Completed then
		fillTween.Completed:Wait()
	end
	if not holoTokenAlive(token) then return end

	-- Phase 4: "SYSTEM READY" swap + short final flicker.
	loadingText.Text = "SYSTEM READY"
	for _ = 1, HOLO_FLICKER_COUNT do
		if not holoTokenAlive(token) then return end
		loadingText.TextTransparency = 0.55
		task.wait(HOLO_FLICKER_STEP)
		loadingText.TextTransparency = 0
		task.wait(HOLO_FLICKER_STEP)
	end

	-- Gate: don't reveal until the viewport rig build started by
	-- setMenuOpen has finished. On the first open this can take a
	-- second or more (GetHumanoidDescriptionFromUserId is a web call),
	-- so we poll every frame here. If the user closes the menu mid-
	-- wait the token changes and we bail out.
	while not viewportInitialized do
		if not holoTokenAlive(token) then return end
		task.wait()
	end

	-- Phase 5: reveal the menu — dissolve the opaque cover and scale
	-- the panels up underneath, while the loading overlay fades out in
	-- parallel. The menu materializing is the "result" of the loading
	-- animation completing, per the spec.
	local appearInfo = TweenInfo.new(
		HOLO_APPEAR_DURATION,
		Enum.EasingStyle.Quint,
		Enum.EasingDirection.Out
	)
	TweenService:Create(menuRootScale, appearInfo, { Scale = 1 }):Play()
	TweenService:Create(holoCover, appearInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(loadingText, appearInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(loadingBar,  appearInfo, { BackgroundTransparency = 1 }):Play()
	local fadeStroke = TweenService:Create(loadingStroke, appearInfo, { Transparency = 1 })
	fadeStroke:Play()
	fadeStroke.Completed:Wait()

	if holoTokenAlive(token) then
		loadingOverlay.Visible     = false
		holoCover.Visible          = false
		loadingStroke.Transparency = 0.3
	end
end

-- ─── Slide open / close animations ────────────────────────────────────────
-- Lightweight slide used for every menu open after the first of the
-- session, and the universal close animation. The whole `root` frame
-- slides up from below the screen on open, and back down on close.

local SLIDE_OPEN_DURATION  = 0.28
local SLIDE_CLOSE_DURATION = 0.25

-- Module-level reference to whichever slide tween is currently running
-- on `menuRoot.Position`, so a rapid close+reopen (or open+close) can
-- cancel the previous tween before starting a new one on the same
-- property — otherwise both would drive Position in parallel.
local activeSlideTween = nil

-- Returns the "fully off-screen below" position for `menuRoot` —
-- one full screen-height below its base position.
local function slideOffscreenPosition()
	local basePos = menuRootBasePosition
	return UDim2.new(
		basePos.X.Scale, basePos.X.Offset,
		basePos.Y.Scale + 1, basePos.Y.Offset
	)
end

local function runSlideOpenAnimation(token)
	if not (menuRoot and menuRootBasePosition) then return end

	-- Cancel any in-flight close tween before we overwrite Position.
	if activeSlideTween then activeSlideTween:Cancel() end

	-- Start one full screen-height below the base position so the
	-- entire menu sits off-screen, then tween up.
	menuRoot.Position = slideOffscreenPosition()

	local tween = TweenService:Create(
		menuRoot,
		TweenInfo.new(
			SLIDE_OPEN_DURATION,
			Enum.EasingStyle.Quint,
			Enum.EasingDirection.Out
		),
		{ Position = menuRootBasePosition }
	)
	activeSlideTween = tween
	tween:Play()
	tween.Completed:Wait()
	if activeSlideTween == tween then activeSlideTween = nil end

	-- If the user closed mid-slide, snap back to base so the next open
	-- isn't starting from a random in-between position.
	if not holoTokenAlive(token) then
		menuRoot.Position = menuRootBasePosition
	end
end

-- Slide-down close: tween `root` from its current position to one
-- full screen-height below, then disable the ScreenGui. Runs for
-- every close regardless of which open animation played, so the menu
-- always exits by sliding off the bottom of the screen.
local function runSlideCloseAnimation(token)
	if not (screenGui and menuRoot and menuRootBasePosition) then
		if screenGui then screenGui.Enabled = false end
		return
	end

	-- Cancel any in-flight open tween so we don't fight it.
	if activeSlideTween then activeSlideTween:Cancel() end

	local tween = TweenService:Create(
		menuRoot,
		TweenInfo.new(
			SLIDE_CLOSE_DURATION,
			Enum.EasingStyle.Quint,
			Enum.EasingDirection.In
		),
		{ Position = slideOffscreenPosition() }
	)
	activeSlideTween = tween
	tween:Play()
	tween.Completed:Wait()
	if activeSlideTween == tween then activeSlideTween = nil end

	-- Only disable the GUI and reset position if no new open has
	-- started in the meantime — otherwise the newer open coroutine is
	-- already setting its own starting position and we'd stomp it.
	if token == openAnimationToken then
		screenGui.Enabled = false
		menuRoot.Position = menuRootBasePosition
	end
end

-- ─── Show / hide ──────────────────────────────────────────────────────────
local function setMenuOpen(open)
	if not screenGui then buildMenu() end
	menuOpen = open

	if open then
		screenGui.Enabled = true
		if typeof(_G.CloseInventory) == "function" then
			_G.CloseInventory()
		end

		openAnimationToken += 1
		local token = openAnimationToken

		-- Kick off the viewport rig build in parallel on the first
		-- open of the current life (the rig build yields on
		-- GetHumanoidDescriptionFromUserId — a web call that can
		-- take a second or more — so we never want it blocking the
		-- open flow). Runs for both animation paths: on session
		-- start the holo-open animation waits for it before the
		-- reveal; after a respawn the slide path just lets the
		-- rig pop in whenever it's ready.
		if not viewportInitialized then
			task.spawn(function()
				refreshCharacterViewport()
				viewportInitialized = true
			end)
		end

		if not holoOpenPlayed then
			-- First open this session: run the full holo-open
			-- animation. Hide the menu behind the opaque cover
			-- IMMEDIATELY, before any potentially-yielding work,
			-- so the menu never flashes visible during the
			-- viewport rig build.
			if holoCover then
				holoCover.BackgroundTransparency = 0
				holoCover.Visible                = true
			end
			if menuRootScale then
				menuRootScale.Scale = HOLO_APPEAR_FROM_SCALE
			end
			if menuRoot and menuRootBasePosition then
				menuRoot.Position = menuRootBasePosition
			end

			task.spawn(function()
				runHoloOpenAnimation(token)
				if token == openAnimationToken then
					holoOpenPlayed = true
				end
			end)
		else
			-- Subsequent opens: quick slide-up from the bottom of
			-- the screen, no cover / no glitch / no loading bar.
			-- The viewport rig is already cached from the first
			-- open so there's nothing to wait on.
			if holoCover then
				holoCover.Visible = false
			end
			if loadingOverlay then
				loadingOverlay.Visible = false
			end
			if menuRootScale then
				menuRootScale.Scale = 1
			end
			task.spawn(function()
				runSlideOpenAnimation(token)
			end)
		end
	else
		-- Close: invalidate any in-flight open animation so it bails
		-- out, clear cover / overlay / scale left over from the holo
		-- path, and play the slide-down close animation. The
		-- ScreenGui stays enabled until the slide finishes so the
		-- user actually sees it.
		openAnimationToken += 1
		local token = openAnimationToken
		if loadingOverlay then loadingOverlay.Visible = false end
		if holoCover      then holoCover.Visible      = false end
		if menuRootScale  then menuRootScale.Scale    = 1       end
		task.spawn(function()
			runSlideCloseAnimation(token)
		end)
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

if dailyResetButton then
	dailyResetButton.MouseButton1Click:Connect(function()
		phoneMenuEvent:FireServer("resetQuests")
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
