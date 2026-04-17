-- RecruitmentSystem.client.lua
-- Shows a recruitment UI when the player presses E near a downed pirate.
-- The UI displays a success chance bar and two buttons: Recruit / Keep.
-- "Recruit" launches a bouncing-ball minigame; "Keep" kills the pirate.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local recruitEvent = ReplicatedStorage:WaitForChild("RecruitPirate")

-- ═══════════════════════════════════════════════════════════════════════
-- State
-- ═══════════════════════════════════════════════════════════════════════
local currentPirate = nil
local uiOpen = false
local minigameRunning = false
local claimedLocally = {} -- client-side set; immune to server replication overwriting
local firstDefeatShown = false
local defeatDialogueOpen = false
local mercenariesUnlockShown = false

-- ═══════════════════════════════════════════════════════════════════════
-- UI construction
-- ═══════════════════════════════════════════════════════════════════════

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RecruitmentGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ─── Hint label (shows when aiming at a downed pirate) ───────────────
local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "HintLabel"
hintLabel.Size = UDim2.new(0, 250, 0, 36)
hintLabel.Position = UDim2.new(0.5, -125, 0.65, 0)
hintLabel.BackgroundTransparency = 1
hintLabel.Text = "[E] Recruit"
hintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
hintLabel.TextStrokeTransparency = 0.4
hintLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
hintLabel.TextScaled = true
hintLabel.Font = Enum.Font.GothamBold
hintLabel.Visible = false
hintLabel.Parent = screenGui

-- ─── Main panel ──────────────────────────────────────────────────────
local panel = Instance.new("Frame")
panel.Name = "RecruitPanel"
panel.Size = UDim2.new(0, 360, 0, 210)
panel.Position = UDim2.new(0.5, -180, 0.5, -105)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local panelStroke = Instance.new("UIStroke")
panelStroke.Thickness = 2
panelStroke.Color = Color3.fromRGB(180, 160, 100)
panelStroke.Parent = panel

-- Title
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 36)
title.Position = UDim2.new(0, 0, 0, 8)
title.BackgroundTransparency = 1
title.Text = "Recruit Pirate?"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.Parent = panel

-- ─── Chance bar / minigame track ─────────────────────────────────────
local TRACK_HEIGHT = 44
local BALL_SIZE = 32

local trackBg = Instance.new("Frame")
trackBg.Name = "Track"
trackBg.Size = UDim2.new(0.88, 0, 0, TRACK_HEIGHT)
trackBg.Position = UDim2.new(0.06, 0, 0, 52)
trackBg.BackgroundColor3 = Color3.fromRGB(220, 220, 220) -- white zone
trackBg.BorderSizePixel = 0
trackBg.ClipsDescendants = true
trackBg.Parent = panel

Instance.new("UICorner", trackBg).CornerRadius = UDim.new(0, 8)

local trackStroke = Instance.new("UIStroke")
trackStroke.Thickness = 2
trackStroke.Color = Color3.fromRGB(60, 60, 60)
trackStroke.Parent = trackBg

-- Green zone (left portion)
local greenZone = Instance.new("Frame")
greenZone.Name = "GreenZone"
greenZone.Size = UDim2.new(0.7, 0, 1, 0)
greenZone.BackgroundColor3 = Color3.fromRGB(70, 190, 70)
greenZone.BorderSizePixel = 0
greenZone.Parent = trackBg

Instance.new("UICorner", greenZone).CornerRadius = UDim.new(0, 8)

-- Divider line
local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.Size = UDim2.new(0, 2, 1, 0)
divider.Position = UDim2.new(0.7, -1, 0, 0)
divider.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
divider.BorderSizePixel = 0
divider.ZIndex = 2
divider.Parent = trackBg

-- Chance text
local chanceLabel = Instance.new("TextLabel")
chanceLabel.Size = UDim2.new(1, 0, 1, 0)
chanceLabel.BackgroundTransparency = 1
chanceLabel.Text = "100%"
chanceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
chanceLabel.TextScaled = true
chanceLabel.Font = Enum.Font.GothamBold
chanceLabel.TextStrokeTransparency = 0.4
chanceLabel.ZIndex = 3
chanceLabel.Parent = trackBg

-- Ball (red circle, hidden until minigame starts)
local ball = Instance.new("Frame")
ball.Name = "Ball"
ball.Size = UDim2.new(0, BALL_SIZE, 0, BALL_SIZE)
ball.Position = UDim2.new(0, 0, 0.5, -BALL_SIZE / 2)
ball.BackgroundColor3 = Color3.fromRGB(210, 40, 40)
ball.BorderSizePixel = 0
ball.Visible = false
ball.ZIndex = 4
ball.Parent = trackBg

Instance.new("UICorner", ball).CornerRadius = UDim.new(0.5, 0)

local ballStroke = Instance.new("UIStroke")
ballStroke.Thickness = 2
ballStroke.Color = Color3.fromRGB(140, 20, 20)
ballStroke.Parent = ball

-- ─── Buttons ─────────────────────────────────────────────────────────
local function makeButton(name, text, color, posX)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0.4, 0, 0, 42)
	btn.Position = UDim2.new(posX, 0, 0, 110)
	btn.BackgroundColor3 = color
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextScaled = true
	btn.Font = Enum.Font.GothamBold
	btn.BorderSizePixel = 0
	btn.Parent = panel
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
	return btn
end

local recruitBtn = makeButton("RecruitBtn", "Recruit", Color3.fromRGB(60, 160, 60), 0.06)
local keepBtn = makeButton("KeepBtn", "Keep", Color3.fromRGB(180, 50, 50), 0.54)

-- ─── Result label ────────────────────────────────────────────────────
local resultLabel = Instance.new("TextLabel")
resultLabel.Name = "ResultLabel"
resultLabel.Size = UDim2.new(1, 0, 0, 36)
resultLabel.Position = UDim2.new(0, 0, 0, 165)
resultLabel.BackgroundTransparency = 1
resultLabel.Text = ""
resultLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
resultLabel.TextScaled = true
resultLabel.Font = Enum.Font.GothamBold
resultLabel.TextStrokeTransparency = 0.4
resultLabel.Parent = panel

-- ─── Recruited notification (top of screen, temporary) ───────────────
local function showNotification(text, color)
	local notif = Instance.new("TextLabel")
	notif.Size = UDim2.new(0, 300, 0, 50)
	notif.Position = UDim2.new(0.5, -150, 0, -60)
	notif.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	notif.BackgroundTransparency = 0.2
	notif.Text = text
	notif.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	notif.TextScaled = true
	notif.Font = Enum.Font.GothamBold
	notif.TextStrokeTransparency = 0.5
	notif.BorderSizePixel = 0
	notif.Parent = screenGui
	Instance.new("UICorner", notif).CornerRadius = UDim.new(0, 10)

	-- Slide in
	TweenService:Create(notif, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -150, 0, 20),
	}):Play()

	-- Fade out after 2.5s
	task.delay(2.5, function()
		local fadeOut = TweenService:Create(notif, TweenInfo.new(0.5), {
			Position = UDim2.new(0.5, -150, 0, -60),
			BackgroundTransparency = 1,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			notif:Destroy()
		end)
	end)
end

-- ═══════════════════════════════════════════════════════════════════════
-- First-defeat dialogue (orange/white theme)
-- ═══════════════════════════════════════════════════════════════════════

local DEFEAT_ICON = "rbxassetid://90285585534580"

local DEFEAT_PAGES = {
	{
		phrases = {
			{ text = "How did you get here?", t0 = 0.00, t1 = 1.40 },
		},
	},
	{
		phrases = {
			{ text = "The whole world",                    t0 = 0.15, t1 = 1.1  },
			{ text = " is swarming with the infected,",    t0 = 1.65, t1 = 3.66 },
			{ text = " yet you managed to survive...",     t0 = 4.74, t1 = 6.782 },
		},
	},
	{
		phrases = {
			{ text = "You are strong! ",                          t0 = 0.06, t1 = 1.19  },
			{ text = "I am ready to serve you for the sak",       t0 = 1.619, t1 = 4.5  },
			{ text = "e of humanity's ",                          t0 = 4.89, t1 = 6.23 },
			{ text = "rebirth!",                                  t0 = 6.5,  t1 = 7.2  },
		},
	},
}

local pirateSoundsFolder = SoundService:WaitForChild("Story"):WaitForChild("Pirate")
local DEFEAT_SOUNDS = {
	pirateSoundsFolder:WaitForChild("1.pirate"),
	pirateSoundsFolder:WaitForChild("2.pirate"),
	pirateSoundsFolder:WaitForChild("3.pirate"),
}

local DLG_COLOR_PANEL    = Color3.fromRGB(245, 228, 195)
local DLG_COLOR_EDGE     = Color3.fromRGB(230, 140, 30)
local DLG_COLOR_ACCENT   = Color3.fromRGB(235, 120, 0)
local DLG_COLOR_TEXT     = Color3.fromRGB(60, 40, 20)
local DLG_COLOR_TEXT_DIM = Color3.fromRGB(160, 120, 60)
local DLG_COLOR_INNER    = Color3.fromRGB(250, 235, 205)

local function showFirstDefeatDialogue(onDone)
	local PANEL_PAD = 20
	local ICON_SZ   = 120
	local GAP_      = 14
	local TXT_PAD_H = 16
	local TXT_PAD_V = 14
	local SPK_H     = 22
	local SPK_GAP   = 8
	local BTN_H_    = 38
	local BTN_GAP_  = 12
	local DLG_W     = 500

	local textColW  = DLG_W - 2 * PANEL_PAD - ICON_SZ - GAP_
	local textBodyW = textColW - 2 * TXT_PAD_H

	-- Size panel to fit the longest dialogue page
	local textBodyH = 20
	for _, page in DEFEAT_PAGES do
		local fullText = ""
		for _, p in page.phrases do fullText = fullText .. p.text end
		local bounds = TextService:GetTextSize(
			fullText, 15, Enum.Font.Gotham, Vector2.new(textBodyW, 9999)
		)
		textBodyH = math.max(textBodyH, bounds.Y + 20)
	end
	local textColH  = TXT_PAD_V + SPK_H + SPK_GAP + textBodyH + TXT_PAD_V
	local contentH  = math.max(ICON_SZ, textColH)
	local panelH    = 2 * PANEL_PAD + contentH + BTN_GAP_ + BTN_H_

	local gui = Instance.new("ScreenGui")
	gui.Name           = "DefeatDialogueGui"
	gui.ResetOnSpawn   = false
	gui.DisplayOrder   = 91
	gui.IgnoreGuiInset = true
	gui.Parent         = playerGui

	local backdrop = Instance.new("Frame")
	backdrop.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel        = 0
	backdrop.Size                   = UDim2.new(1, 0, 1, 0)
	backdrop.Parent                 = gui

	local dlgPanel = Instance.new("Frame")
	dlgPanel.BackgroundColor3       = DLG_COLOR_PANEL
	dlgPanel.BackgroundTransparency = 0.05
	dlgPanel.BorderSizePixel        = 0
	dlgPanel.AnchorPoint            = Vector2.new(0.5, 0.5)
	dlgPanel.Size                   = UDim2.fromOffset(DLG_W, panelH)
	dlgPanel.Position               = UDim2.new(0.5, 0, -0.5, 0)
	dlgPanel.Parent                 = gui
	Instance.new("UICorner", dlgPanel).CornerRadius = UDim.new(0, 14)

	local edgeStroke = Instance.new("UIStroke")
	edgeStroke.Thickness       = 2
	edgeStroke.Color           = DLG_COLOR_EDGE
	edgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edgeStroke.Parent          = dlgPanel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, PANEL_PAD)
	pad.PaddingBottom = UDim.new(0, PANEL_PAD)
	pad.PaddingLeft   = UDim.new(0, PANEL_PAD)
	pad.PaddingRight  = UDim.new(0, PANEL_PAD)
	pad.Parent        = dlgPanel

	-- Icon
	local iconFrame = Instance.new("Frame")
	iconFrame.Size                    = UDim2.fromOffset(ICON_SZ, ICON_SZ)
	iconFrame.Position                = UDim2.fromOffset(0, 0)
	iconFrame.BackgroundTransparency  = 1
	iconFrame.BorderSizePixel         = 0
	iconFrame.Parent                  = dlgPanel
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 8)
	local iconEdge = Instance.new("UIStroke")
	iconEdge.Thickness = 1
	iconEdge.Color     = DLG_COLOR_EDGE
	iconEdge.Parent    = iconFrame

	local iconImg = Instance.new("ImageLabel")
	iconImg.Size                    = UDim2.new(1, 0, 1, 0)
	iconImg.BackgroundTransparency  = 1
	iconImg.Image                   = DEFEAT_ICON
	iconImg.ScaleType               = Enum.ScaleType.Stretch
	iconImg.Parent                  = iconFrame
	Instance.new("UICorner", iconImg).CornerRadius = UDim.new(0, 8)

	-- Text column
	local textBg = Instance.new("Frame")
	textBg.BackgroundColor3       = DLG_COLOR_INNER
	textBg.BackgroundTransparency = 0.3
	textBg.BorderSizePixel        = 0
	textBg.Size                   = UDim2.fromOffset(textColW, textColH)
	textBg.Position               = UDim2.fromOffset(ICON_SZ + GAP_, 0)
	textBg.Parent                 = dlgPanel
	Instance.new("UICorner", textBg).CornerRadius = UDim.new(0, 8)

	local txtPad = Instance.new("UIPadding")
	txtPad.PaddingTop    = UDim.new(0, TXT_PAD_V)
	txtPad.PaddingBottom = UDim.new(0, TXT_PAD_V)
	txtPad.PaddingLeft   = UDim.new(0, TXT_PAD_H)
	txtPad.PaddingRight  = UDim.new(0, TXT_PAD_H)
	txtPad.Parent        = textBg

	local speakerLbl = Instance.new("TextLabel")
	speakerLbl.BackgroundTransparency = 1
	speakerLbl.Size           = UDim2.new(1, 0, 0, SPK_H)
	speakerLbl.Font           = Enum.Font.GothamBold
	speakerLbl.TextSize       = 17
	speakerLbl.TextColor3     = DLG_COLOR_ACCENT
	speakerLbl.Text           = "Defeated Pirate"
	speakerLbl.TextXAlignment = Enum.TextXAlignment.Left
	speakerLbl.Parent         = textBg

	local dialogueLbl = Instance.new("TextLabel")
	dialogueLbl.BackgroundTransparency = 1
	dialogueLbl.Size           = UDim2.new(1, 0, 0, textBodyH)
	dialogueLbl.Position       = UDim2.fromOffset(0, SPK_H + SPK_GAP)
	dialogueLbl.Font           = Enum.Font.Gotham
	dialogueLbl.TextSize       = 15
	dialogueLbl.TextColor3     = DLG_COLOR_TEXT
	dialogueLbl.Text           = ""
	dialogueLbl.TextXAlignment = Enum.TextXAlignment.Left
	dialogueLbl.TextYAlignment = Enum.TextYAlignment.Top
	dialogueLbl.TextWrapped    = true
	dialogueLbl.Parent         = textBg

	-- Action button (full width)
	local actionBtn = Instance.new("TextButton")
	actionBtn.BackgroundColor3 = DLG_COLOR_INNER
	actionBtn.BorderSizePixel  = 0
	actionBtn.Size             = UDim2.new(1, 0, 0, BTN_H_)
	actionBtn.Position         = UDim2.fromOffset(0, contentH + BTN_GAP_)
	actionBtn.Font             = Enum.Font.GothamBold
	actionBtn.TextSize         = 17
	actionBtn.TextColor3       = DLG_COLOR_TEXT_DIM
	actionBtn.Text             = "Skip"
	actionBtn.AutoButtonColor  = true
	actionBtn.Parent           = dlgPanel
	Instance.new("UICorner", actionBtn).CornerRadius = UDim.new(0, 8)
	local btnEdge = Instance.new("UIStroke")
	btnEdge.Thickness       = 1.5
	btnEdge.Color           = DLG_COLOR_EDGE
	btnEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	btnEdge.Parent          = actionBtn

	-- Slide in
	TweenService:Create(
		backdrop,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.4 }
	):Play()
	TweenService:Create(
		dlgPanel,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0.5, 0) }
	):Play()

	local closed = false
	local inputConn = nil

	local function stopAllSounds()
		for _, snd in DEFEAT_SOUNDS do
			snd:Stop()
		end
	end

	local function closeDialogue()
		if closed then return end
		closed = true
		stopAllSounds()

		for _, desc in gui:GetDescendants() do
			if desc:IsA("TextLabel") or desc:IsA("TextButton") then
				TweenService:Create(desc, TweenInfo.new(0.2), {
					TextTransparency = 1,
					BackgroundTransparency = 1,
				}):Play()
			elseif desc:IsA("ImageLabel") then
				TweenService:Create(desc, TweenInfo.new(0.2), {
					ImageTransparency = 1,
				}):Play()
			elseif desc:IsA("Frame") then
				TweenService:Create(desc, TweenInfo.new(0.2), {
					BackgroundTransparency = 1,
				}):Play()
			elseif desc:IsA("UIStroke") then
				TweenService:Create(desc, TweenInfo.new(0.2), {
					Transparency = 1,
				}):Play()
			end
		end

		task.delay(0.25, function()
			gui:Destroy()
			if inputConn then inputConn:Disconnect() end
			if onDone then onDone() end
		end)
	end

	inputConn = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			closeDialogue()
		end
	end)

	-- Multi-page phrase-timed typewriter (synced to voiceover)
	local currentPage = 1
	local pageFinished = false
	local typewriterCancel = false

	local function getPageFullText(pageIndex)
		local full = ""
		for _, p in DEFEAT_PAGES[pageIndex].phrases do
			full = full .. p.text
		end
		return full
	end

	local function showPage(pageIndex)
		currentPage = pageIndex
		pageFinished = false
		typewriterCancel = false
		dialogueLbl.Text = ""
		actionBtn.Text = "Skip"
		actionBtn.TextColor3 = DLG_COLOR_TEXT_DIM

		stopAllSounds()
		local sound = DEFEAT_SOUNDS[pageIndex]
		if sound then sound:Play() end

		local page = DEFEAT_PAGES[pageIndex]
		task.spawn(function()
			local startClock = os.clock()
			local displayed = ""

			for _, phrase in page.phrases do
				if typewriterCancel then break end

				local waitFor = phrase.t0 - (os.clock() - startClock)
				if waitFor > 0 then task.wait(waitFor) end
				if typewriterCancel then break end

				local charDelay = (phrase.t1 - phrase.t0) / #phrase.text
				for c = 1, #phrase.text do
					if typewriterCancel then break end
					displayed = displayed .. string.sub(phrase.text, c, c)
					dialogueLbl.Text = displayed
					if c < #phrase.text then
						task.wait(charDelay)
					end
				end
			end

			if not typewriterCancel then
				pageFinished = true
				dialogueLbl.Text = getPageFullText(pageIndex)
				actionBtn.Text = "Continue"
				actionBtn.TextColor3 = DLG_COLOR_ACCENT
			end
		end)
	end

	actionBtn.MouseButton1Click:Connect(function()
		if not pageFinished then
			stopAllSounds()
			typewriterCancel = true
			pageFinished = true
			dialogueLbl.Text = getPageFullText(currentPage)
			actionBtn.Text = "Continue"
			actionBtn.TextColor3 = DLG_COLOR_ACCENT
		elseif currentPage < #DEFEAT_PAGES then
			showPage(currentPage + 1)
		else
			closeDialogue()
		end
	end)

	showPage(1)
end

-- ═══════════════════════════════════════════════════════════════════════
-- Helpers
-- ═══════════════════════════════════════════════════════════════════════

local function closeUI()
	panel.Visible = false
	hintLabel.Visible = false
	ball.Visible = false
	recruitBtn.Visible = true
	keepBtn.Visible = true
	chanceLabel.Visible = true
	resultLabel.Text = ""
	uiOpen = false
	minigameRunning = false
	currentPirate = nil
	_G.SuppressInventoryToggle = false
end

-- A pirate model counts as "downed" if it has the server-set Downed
-- attribute OR if its Humanoid shows ragdoll indicators. The baked
-- ZombieScript/Ragdoller may knock out the pirate without zeroing
-- Humanoid.Health, so we check multiple signals.
local function isModelDowned(model)
	if model:GetAttribute("Downed") then return true end
	local hum = model:FindFirstChildWhichIsA("Humanoid")
	if not hum then return false end
	if hum.Health <= 0 then return true end
	-- Humanoid state (Dead or Physics = ragdoll)
	local state = hum:GetState()
	if state == Enum.HumanoidStateType.Dead
		or state == Enum.HumanoidStateType.Physics then
		return true
	end
	-- PlatformStand is a common ragdoll flag
	if hum.PlatformStand then return true end
	-- Motor6D absence: a ragdolled R6 character has its joints replaced
	-- with BallSocketConstraints, leaving zero Motor6Ds.
	local hasMotor = false
	for _, desc in model:GetDescendants() do
		if desc:IsA("Motor6D") then
			hasMotor = true
			break
		end
	end
	if not hasMotor then return true end
	return false
end

local function findDownedPirateNearby()
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local playerPos = hrp.Position

	local closest, closestDist = nil, 15
	for _, child in workspace:GetChildren() do
		if child:IsA("Model")
			and child:FindFirstChild("HumanoidRootPart")
			and child:FindFirstChildWhichIsA("Humanoid")
			and not Players:GetPlayerFromCharacter(child)
			and not CollectionService:HasTag(child, "SpawnedMercenary")
			and isModelDowned(child)
			and not child:GetAttribute("Claimed")
			and not claimedLocally[child]
		then
			-- Use Torso or Head first — HumanoidRootPart can end up at a
			-- weird position after ragdoll.
			local part = child:FindFirstChild("Torso")
				or child:FindFirstChild("Head")
				or child:FindFirstChild("HumanoidRootPart")
				or child:FindFirstChildWhichIsA("BasePart", true)
			if part then
				local d = (playerPos - part.Position).Magnitude
				if d < closestDist then
					closest = child
					closestDist = d
				end
			end
		end
	end
	return closest
end

-- ═══════════════════════════════════════════════════════════════════════
-- Ball physics minigame
-- ═══════════════════════════════════════════════════════════════════════

local function runMinigame(chance)
	minigameRunning = true
	recruitBtn.Visible = false
	keepBtn.Visible = false
	chanceLabel.Visible = false
	resultLabel.Text = ""
	ball.Visible = true

	local trackWidth = trackBg.AbsoluteSize.X - BALL_SIZE
	if trackWidth <= 0 then trackWidth = 300 end

	-- 1-D physics: ball bounces between x=0 and x=1
	local x = 0
	local velocity = math.random(250, 450) / 100 -- 2.5 – 4.5 units/s
	local damping = 0.6   -- speed retained per bounce
	local friction = 0.4  -- deceleration per second
	local stopThreshold = 0.02

	ball.Position = UDim2.new(0, 0, 0.5, -BALL_SIZE / 2)

	local startTime = tick()
	local MAX_TIME = 10

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not minigameRunning then
			if conn then conn:Disconnect() end
			return
		end

		-- Friction
		if velocity > 0 then
			velocity = math.max(0, velocity - friction * dt)
		else
			velocity = math.min(0, velocity + friction * dt)
		end

		-- Move
		x = x + velocity * dt

		-- Bounce off walls
		if x > 1 then
			x = 2 - x
			velocity = -velocity * damping
		elseif x < 0 then
			x = -x
			velocity = -velocity * damping
		end

		x = math.clamp(x, 0, 1)

		-- Update visual
		ball.Position = UDim2.new(0, x * trackWidth, 0.5, -BALL_SIZE / 2)

		-- Check if ball has stopped
		if math.abs(velocity) < stopThreshold or (tick() - startTime) > MAX_TIME then
			conn:Disconnect()

			local successZone = (chance or 100) / 100
			local success = x <= successZone

			if currentPirate then
				claimedLocally[currentPirate] = true
			end

			if success then
				if currentPirate then
					recruitEvent:FireServer("recruit", currentPirate)
				end
			else
				if currentPirate then
					recruitEvent:FireServer("fail", currentPirate)
				end
			end

			closeUI()
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════
-- Button handlers
-- ═══════════════════════════════════════════════════════════════════════

recruitBtn.MouseButton1Click:Connect(function()
	if not currentPirate or minigameRunning then return end
	local chance = currentPirate:GetAttribute("RecruitChance") or 100
	runMinigame(chance)
end)

keepBtn.MouseButton1Click:Connect(function()
	if not currentPirate or minigameRunning then return end
	claimedLocally[currentPirate] = true
	recruitEvent:FireServer("keep", currentPirate)
	closeUI()
end)

-- ═══════════════════════════════════════════════════════════════════════
-- E key interaction
-- ═══════════════════════════════════════════════════════════════════════

local function openRecruitPanel(pirate)
	currentPirate = pirate
	uiOpen = true

	if _G.OpenBrainMaze then
		_G.OpenBrainMaze(pirate, function(result)
			if result == "completed" and pirate then
				claimedLocally[pirate] = true
				recruitEvent:FireServer("recruit", pirate)

				if not mercenariesUnlockShown then
					mercenariesUnlockShown = true
					task.delay(2, function()
						if typeof(_G.ShowQuestNotification) == "function" then
							_G.ShowQuestNotification(
								"Your device now has access to the 'Mercenaries' section.",
								"New feature unlocked",
								{ icon = "📱", sound = "achievement_complete", duration = 6 }
							)
						end
					end)
				end
			end
			uiOpen = false
			currentPirate = nil
			_G.SuppressInventoryToggle = false
		end)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.E then return end
	if defeatDialogueOpen then return end

	if uiOpen and not minigameRunning then
		closeUI()
		return
	end

	if uiOpen then return end

	local pirate = findDownedPirateNearby()
	if pirate then
		if mercenariesUnlockShown then
			local char = player.Character
			local equipped = char and char:FindFirstChildOfClass("Tool")
			if not equipped or equipped.Name ~= "Injector" then
				showNotification("You need an Injector.", Color3.fromRGB(255, 200, 80))
			end
			return
		end

		if not firstDefeatShown then
			firstDefeatShown = true
			defeatDialogueOpen = true
			_G.SuppressInventoryToggle = true
			showFirstDefeatDialogue(function()
				defeatDialogueOpen = false
				local p = pirate
				if not p or not p.Parent then
					p = findDownedPirateNearby()
				end
				if p then
					openRecruitPanel(p)
				else
					_G.SuppressInventoryToggle = false
				end
			end)
		else
			openRecruitPanel(pirate)
		end
	end
end)

-- ═══════════════════════════════════════════════════════════════════════
-- Hint label + proximity validation loop
-- ═══════════════════════════════════════════════════════════════════════

RunService.RenderStepped:Connect(function()
	-- Show "[E] Recruit" hint when looking at a downed pirate nearby.
	-- Suppress the inventory E-key toggle while the hint is visible or
	-- the recruitment UI is open so the two systems don't fight.
	if defeatDialogueOpen then
		hintLabel.Visible = false
		_G.SuppressInventoryToggle = true
		return
	end

	if not uiOpen then
		local pirate = findDownedPirateNearby()
		if pirate then
			hintLabel.Visible = true
			_G.SuppressInventoryToggle = true
		else
			hintLabel.Visible = false
			_G.SuppressInventoryToggle = false
		end
	else
		hintLabel.Visible = false
		_G.SuppressInventoryToggle = true
	end

	-- Close UI if pirate destroyed or player moved too far
	if uiOpen and not minigameRunning and currentPirate then
		if not currentPirate.Parent then
			closeUI()
			return
		end
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			local pHRP = currentPirate:FindFirstChild("HumanoidRootPart")
				or currentPirate:FindFirstChild("Torso")
				or currentPirate:FindFirstChildWhichIsA("BasePart", true)
			if pHRP and (char.HumanoidRootPart.Position - pHRP.Position).Magnitude > 20 then
				closeUI()
			end
		end
	end
end)

-- ═══════════════════════════════════════════════════════════════════════
-- Server notifications
-- ═══════════════════════════════════════════════════════════════════════

recruitEvent.OnClientEvent:Connect(function(action, data)
	if action == "recruited" then
		showNotification("Pirate Recruited!  (Total: " .. tostring(data) .. ")", Color3.fromRGB(80, 255, 80))
	elseif action == "failed" then
		showNotification("Recruitment Failed", Color3.fromRGB(255, 100, 100))
	end
end)
