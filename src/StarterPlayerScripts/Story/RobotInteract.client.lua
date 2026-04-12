-- RobotInteract.client.lua
-- Hover highlight + "E - Interact" prompt on the broken Robot.
-- Press E to open a dialogue menu with typewriter text and a Claim
-- button that grants the player a Phone.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = workspace.CurrentCamera
local mouse     = player:GetMouse()

local storyEvent = ReplicatedStorage:WaitForChild("StoryAction")

-- ─── Theme (matches PhoneMenu) ───────────────────────────────────────────
local COLOR_BG         = Color3.fromRGB(5, 15, 35)
local COLOR_PANEL      = Color3.fromRGB(10, 25, 55)
local COLOR_PANEL_EDGE = Color3.fromRGB(80, 180, 255)
local COLOR_ACCENT     = Color3.fromRGB(120, 210, 255)
local COLOR_TEXT       = Color3.fromRGB(220, 240, 255)
local COLOR_TEXT_DIM   = Color3.fromRGB(140, 180, 220)
local COLOR_BAR_BG     = Color3.fromRGB(15, 35, 70)
local FONT_TITLE       = Enum.Font.GothamBold
local FONT_BODY        = Enum.Font.Gotham

local INTERACT_DISTANCE  = 15
local TYPEWRITER_SPEED   = 0.035 -- seconds per character
local ROBOT_ICON         = "rbxassetid://86743841980627"

-- ─── State ───────────────────────────────────────────────────────────────
local currentHighlight  = nil
local promptBillboard   = nil
local isHovering        = false
local dialogueOpen      = false

-- ─── Wait for Robot ──────────────────────────────────────────────────────
local robot = workspace:WaitForChild("Robot", 60)
if not robot then
	warn("[RobotInteract] Robot not found in workspace")
	return
end

-- ─── Helpers ─────────────────────────────────────────────────────────────

local function getRobotPart()
	if robot:IsA("Model") then
		return robot.PrimaryPart or robot:FindFirstChildWhichIsA("BasePart", true)
	end
	return robot
end

local function isPlayerNear()
	local char = player.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local part = getRobotPart()
	if not part then return false end
	return (hrp.Position - part.Position).Magnitude <= INTERACT_DISTANCE
end

local function isMouseOverRobot()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		params.FilterDescendantsInstances = { player.Character }
	end

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	if not result or not result.Instance then return false end

	local hit = result.Instance
	return hit == robot or hit:IsDescendantOf(robot)
end

-- ─── Highlight / Prompt ──────────────────────────────────────────────────

local function clearHighlight()
	if currentHighlight then
		currentHighlight:Destroy()
		currentHighlight = nil
	end
	if promptBillboard then
		promptBillboard:Destroy()
		promptBillboard = nil
	end
	isHovering = false
	task.defer(function()
		if not isHovering then
			_G.SuppressInventoryToggle = false
		end
	end)
end

local function showHighlight()
	if currentHighlight then return end
	isHovering = true
	_G.SuppressInventoryToggle = true

	local hl = Instance.new("Highlight")
	hl.FillColor        = COLOR_ACCENT
	hl.FillTransparency = 0.5
	hl.OutlineColor     = COLOR_ACCENT
	hl.OutlineTransparency = 0
	hl.Parent = robot
	currentHighlight = hl

	-- Billboard prompt
	local adornee = getRobotPart()
	if not adornee then return end

	local bb = Instance.new("BillboardGui")
	bb.Size          = UDim2.new(5, 0, 1, 0)
	bb.StudsOffset   = Vector3.new(0, 2.5, 0)
	bb.AlwaysOnTop   = true
	bb.Adornee       = adornee
	bb.Parent        = playerGui

	local lbl = Instance.new("TextLabel")
	lbl.Size                 = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text                 = "E - Interact"
	lbl.TextColor3           = COLOR_ACCENT
	lbl.TextStrokeTransparency = 0.3
	lbl.TextStrokeColor3     = Color3.fromRGB(0, 0, 0)
	lbl.Font                 = FONT_TITLE
	lbl.TextScaled           = true
	lbl.Parent               = bb

	promptBillboard = bb
end

-- ─── Hover loop ──────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function()
	if dialogueOpen then
		clearHighlight()
		return
	end

	local over = isMouseOverRobot() and isPlayerNear()

	if over and not isHovering then
		showHighlight()
	elseif not over and isHovering then
		clearHighlight()
	end
end)

-- ─── Small UI helpers ────────────────────────────────────────────────────

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

-- ─── Robot photo (ImageLabel) ────────────────────────────────────────────

local function createRobotPhoto(parent, size, position)
	local frame = Instance.new("Frame")
	frame.Size                 = size
	frame.Position             = position
	frame.BackgroundColor3     = COLOR_BAR_BG
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel      = 0
	frame.Parent               = parent
	corner(frame, 8)
	stroke(frame, 1, COLOR_PANEL_EDGE)

	local img = Instance.new("ImageLabel")
	img.Size                 = UDim2.new(1, -12, 1, -12)
	img.AnchorPoint          = Vector2.new(0.5, 0.5)
	img.Position             = UDim2.new(0.5, 0, 0.5, 0)
	img.BackgroundTransparency = 1
	img.Image                = ROBOT_ICON
	img.ScaleType            = Enum.ScaleType.Fit
	img.Parent               = frame

	return frame
end

-- ─── Shared dialogue builder ─────────────────────────────────────────────
-- Both quest and idle paths share the same layout; only the text, button
-- behaviour and whether a reward is granted differ.

local function buildDialogueShell()
	local gui = Instance.new("ScreenGui")
	gui.Name           = "RobotDialogueGui"
	gui.ResetOnSpawn   = false
	gui.DisplayOrder   = 90
	gui.IgnoreGuiInset = true
	gui.Parent         = playerGui

	-- Backdrop
	local backdrop = Instance.new("Frame")
	backdrop.BackgroundColor3       = COLOR_BG
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel        = 0
	backdrop.Size                   = UDim2.new(1, 0, 1, 0)
	backdrop.Parent                 = gui

	-- Main panel (starts above screen)
	local panel = Instance.new("Frame")
	panel.BackgroundColor3       = COLOR_PANEL
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel        = 0
	panel.AnchorPoint            = Vector2.new(0.5, 0.5)
	panel.Size                   = UDim2.fromOffset(620, 370)
	panel.Position               = UDim2.new(0.5, 0, -0.5, 0)
	panel.Parent                 = gui
	corner(panel, 14)
	stroke(panel, 2, COLOR_PANEL_EDGE)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, 20)
	pad.PaddingBottom = UDim.new(0, 20)
	pad.PaddingLeft   = UDim.new(0, 20)
	pad.PaddingRight  = UDim.new(0, 20)
	pad.Parent        = panel

	-- Left column: 3 robot photos
	local photosFrame = Instance.new("Frame")
	photosFrame.BackgroundTransparency = 1
	photosFrame.Size     = UDim2.fromOffset(150, 310)
	photosFrame.Position = UDim2.fromOffset(0, 0)
	photosFrame.Parent   = panel

	for i = 1, 3 do
		createRobotPhoto(
			photosFrame,
			UDim2.fromOffset(140, 92),
			UDim2.fromOffset(0, (i - 1) * 105)
		)
	end

	-- Right column: speaker name + dialogue text
	local textBg = Instance.new("Frame")
	textBg.BackgroundColor3       = COLOR_BAR_BG
	textBg.BackgroundTransparency = 0.3
	textBg.BorderSizePixel        = 0
	textBg.Size     = UDim2.new(1, -170, 0, 250)
	textBg.Position = UDim2.fromOffset(165, 0)
	textBg.Parent   = panel
	corner(textBg, 8)

	local textPad = Instance.new("UIPadding")
	textPad.PaddingTop    = UDim.new(0, 14)
	textPad.PaddingBottom = UDim.new(0, 14)
	textPad.PaddingLeft   = UDim.new(0, 16)
	textPad.PaddingRight  = UDim.new(0, 16)
	textPad.Parent        = textBg

	local speakerLbl = Instance.new("TextLabel")
	speakerLbl.BackgroundTransparency = 1
	speakerLbl.Size           = UDim2.new(1, 0, 0, 22)
	speakerLbl.Position       = UDim2.fromOffset(0, 0)
	speakerLbl.Font           = FONT_TITLE
	speakerLbl.TextSize       = 17
	speakerLbl.TextColor3     = COLOR_ACCENT
	speakerLbl.Text           = "Broken Robot"
	speakerLbl.TextXAlignment = Enum.TextXAlignment.Left
	speakerLbl.Parent         = textBg

	local dialogueLbl = Instance.new("TextLabel")
	dialogueLbl.BackgroundTransparency = 1
	dialogueLbl.Size           = UDim2.new(1, 0, 1, -32)
	dialogueLbl.Position       = UDim2.fromOffset(0, 30)
	dialogueLbl.Font           = FONT_BODY
	dialogueLbl.TextSize       = 15
	dialogueLbl.TextColor3     = COLOR_TEXT
	dialogueLbl.Text           = ""
	dialogueLbl.TextXAlignment = Enum.TextXAlignment.Left
	dialogueLbl.TextYAlignment = Enum.TextYAlignment.Top
	dialogueLbl.TextWrapped    = true
	dialogueLbl.Parent         = textBg

	-- Action button
	local actionBtn = Instance.new("TextButton")
	actionBtn.Name             = "ActionButton"
	actionBtn.BackgroundColor3 = COLOR_BAR_BG
	actionBtn.BorderSizePixel  = 0
	actionBtn.Size     = UDim2.new(1, -170, 0, 38)
	actionBtn.Position = UDim2.fromOffset(165, 262)
	actionBtn.Font     = FONT_TITLE
	actionBtn.TextSize = 17
	actionBtn.TextColor3       = COLOR_TEXT_DIM
	actionBtn.Text             = "Skip"
	actionBtn.AutoButtonColor  = true
	actionBtn.Parent           = panel
	corner(actionBtn, 8)
	stroke(actionBtn, 1.5, COLOR_PANEL_EDGE)

	-- Slide-in animation
	TweenService:Create(
		backdrop,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.2 }
	):Play()
	TweenService:Create(
		panel,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0.5, 0) }
	):Play()

	-- Close helper
	local closed = false
	local inputConn = nil

	local function closeDialogue()
		if closed then return end
		closed = true

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
			dialogueOpen = false
		end)

		if inputConn then
			inputConn:Disconnect()
			inputConn = nil
		end
	end

	-- Close on Escape
	inputConn = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			closeDialogue()
		end
	end)

	return dialogueLbl, actionBtn, closeDialogue
end

-- ─── Open Dialogue ───────────────────────────────────────────────────────

local function openDialogue()
	if dialogueOpen then return end
	dialogueOpen = true
	clearHighlight()

	local questDone = player:GetAttribute("RobotQuest1Done") == true

	local dialogueLbl, actionBtn, closeDialogue = buildDialogueShell()

	if questDone then
		-- ── Idle dialogue (no active quest) ──────────────────────
		local idleText = "I need repairs, fix me..."
		local textFinished = false

		actionBtn.Text       = "Skip"
		actionBtn.TextColor3 = COLOR_TEXT_DIM

		task.spawn(function()
			for i = 1, #idleText do
				if textFinished then break end
				dialogueLbl.Text = string.sub(idleText, 1, i)
				task.wait(TYPEWRITER_SPEED)
			end
			if not textFinished then
				textFinished = true
				dialogueLbl.Text     = idleText
				actionBtn.Text       = "Close"
				actionBtn.TextColor3 = COLOR_ACCENT
			end
		end)

		actionBtn.MouseButton1Click:Connect(function()
			if not textFinished then
				textFinished = true
				dialogueLbl.Text     = idleText
				actionBtn.Text       = "Close"
				actionBtn.TextColor3 = COLOR_ACCENT
			else
				closeDialogue()
			end
		end)
	else
		-- ── Quest 1: Phone hand-off ──────────────────────────────
		local fullText = "I... I... Still working? I saved the magic phone; the astronaut left it to me. He said it would help restore humanity. Take it."
		local textFinished = false

		task.spawn(function()
			for i = 1, #fullText do
				if textFinished then break end
				dialogueLbl.Text = string.sub(fullText, 1, i)
				task.wait(TYPEWRITER_SPEED)
			end
			if not textFinished then
				textFinished = true
				dialogueLbl.Text     = fullText
				actionBtn.Text       = "Claim"
				actionBtn.TextColor3 = COLOR_ACCENT
			end
		end)

		actionBtn.MouseButton1Click:Connect(function()
			if not textFinished then
				textFinished = true
				dialogueLbl.Text     = fullText
				actionBtn.Text       = "Claim"
				actionBtn.TextColor3 = COLOR_ACCENT
			else
				storyEvent:FireServer("claimRobotPhone")
				closeDialogue()
			end
		end)
	end
end

-- ─── E-key handler ───────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.E and isHovering and not dialogueOpen then
		openDialogue()
	end
end)
