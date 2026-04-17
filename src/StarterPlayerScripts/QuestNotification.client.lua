-- QuestNotification.client.lua
-- Shows a toast notification at the top-right of the screen when a
-- daily quest is completed. Styled to match the Phone menu theme.

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── Theme (matches PhoneMenu) ───────────────────────────────────────────
local COLOR_PANEL      = Color3.fromRGB(10, 25, 55)
local COLOR_PANEL_EDGE = Color3.fromRGB(80, 180, 255)
local COLOR_ACCENT     = Color3.fromRGB(120, 210, 255)
local COLOR_TEXT       = Color3.fromRGB(220, 240, 255)
local FONT_TITLE       = Enum.Font.GothamBold
local FONT_BODY        = Enum.Font.Gotham

local DISPLAY_TIME     = 4     -- seconds the toast stays visible
local SLIDE_TIME       = 0.35  -- tween duration for slide in/out

-- ─── Notification queue ──────────────────────────────────────────────────
local queue     = {}
local showing   = false

-- ─── Build the ScreenGui (persists across notifications) ─────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QuestNotificationGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 8
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Container anchored at the top-right; notifications slide in from the
-- right edge. Width scales with viewport; height auto-sizes to content.
local container = Instance.new("Frame")
container.Name = "NotifContainer"
container.BackgroundTransparency = 1
container.AnchorPoint = Vector2.new(1, 0)
container.Position = UDim2.new(1, -16, 0, 16)
container.Size = UDim2.new(0.28, 0, 0, 0)
container.AutomaticSize = Enum.AutomaticSize.Y
container.Parent = screenGui

local containerSizeConstraint = Instance.new("UISizeConstraint")
containerSizeConstraint.MinSize = Vector2.new(260, 0)
containerSizeConstraint.MaxSize = Vector2.new(420, math.huge)
containerSizeConstraint.Parent = container

-- ─── Build a toast frame ─────────────────────────────────────────────────
local function buildToast()
	local panel = Instance.new("Frame")
	panel.Name = "QuestToast"
	panel.BackgroundColor3 = COLOR_PANEL
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Size = UDim2.new(1, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	-- Start offscreen to the right
	panel.Position = UDim2.new(1, 20, 0, 0)
	panel.Parent = container

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 10)
	uiCorner.Parent = panel

	local uiStroke = Instance.new("UIStroke")
	uiStroke.Thickness = 1.5
	uiStroke.Color = COLOR_PANEL_EDGE
	uiStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	uiStroke.Parent = panel

	local uiPadding = Instance.new("UIPadding")
	uiPadding.PaddingTop    = UDim.new(0, 8)
	uiPadding.PaddingBottom = UDim.new(0, 8)
	uiPadding.PaddingLeft   = UDim.new(0, 12)
	uiPadding.PaddingRight  = UDim.new(0, 12)
	uiPadding.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 0)
	title.AutomaticSize = Enum.AutomaticSize.Y
	title.Font = FONT_TITLE
	title.TextSize = 16
	title.TextColor3 = COLOR_ACCENT
	title.Text = "Task completed!"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.TextWrapped = true
	title.LayoutOrder = 1
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, 0, 0, 0)
	subtitle.AutomaticSize = Enum.AutomaticSize.Y
	subtitle.Font = FONT_BODY
	subtitle.TextSize = 14
	subtitle.TextColor3 = COLOR_TEXT
	subtitle.Text = ""
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.TextWrapped = true
	subtitle.LayoutOrder = 2
	subtitle.Parent = panel

	return panel, subtitle, title
end

-- ─── Show / queue logic ──────────────────────────────────────────────────
local function showNext()
	if showing or #queue == 0 then return end
	showing = true

	local entry = table.remove(queue, 1)
	local panel, subtitle, title = buildToast()
	subtitle.Text = entry.subtitle
	if entry.title then title.Text = entry.title end

	-- Play completion sound
	local soundFolder = SoundService:FindFirstChild("Sound_Menu")
	local questSound = soundFolder and soundFolder:FindFirstChild("Completed_Quest")
	if questSound then questSound:Play() end

	-- Slide in from the right
	local slideIn = TweenService:Create(
		panel,
		TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 0, 0, 0) }
	)
	slideIn:Play()

	task.delay(DISPLAY_TIME, function()
		-- Slide out to the right
		local slideOut = TweenService:Create(
			panel,
			TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(1, 20, 0, 0) }
		)
		slideOut:Play()
		slideOut.Completed:Wait()
		panel:Destroy()
		showing = false
		showNext()
	end)
end

local function notify(subtitleText, titleText)
	table.insert(queue, { subtitle = subtitleText, title = titleText })
	showNext()
end

_G.ShowQuestNotification = notify

-- ─── Watch quest completions ─────────────────────────────────────────────
local connections = {}

local function watchQuest(questFolder)
	local completed = questFolder:FindFirstChild("Completed")
	local label     = questFolder:FindFirstChild("Label")
	if not completed or not label then return end

	-- Only fire when flipping from false → true
	local conn = completed:GetPropertyChangedSignal("Value"):Connect(function()
		if completed.Value == true then
			notify(label.Value)
		end
	end)
	table.insert(connections, conn)
end

local function bindFolder(folder)
	-- Disconnect old watchers
	for _, conn in connections do
		conn:Disconnect()
	end
	table.clear(connections)

	-- Watch existing quests
	for _, child in folder:GetChildren() do
		if child:IsA("Folder") and child.Name:sub(1, 6) == "Quest_" then
			watchQuest(child)
		end
	end

	-- Watch for new quests (e.g. after a reset)
	local addedConn = folder.ChildAdded:Connect(function(child)
		if child:IsA("Folder") and child.Name:sub(1, 6) == "Quest_" then
			watchQuest(child)
		end
	end)
	table.insert(connections, addedConn)
end

-- ─── Initial bind ────────────────────────────────────────────────────────
task.spawn(function()
	local folder = player:WaitForChild("DailyQuests")
	bindFolder(folder)

	-- Re-bind when the folder is replaced (quest reset / new day)
	player.ChildAdded:Connect(function(child)
		if child.Name == "DailyQuests" and child:IsA("Folder") then
			bindFolder(child)
		end
	end)
end)
