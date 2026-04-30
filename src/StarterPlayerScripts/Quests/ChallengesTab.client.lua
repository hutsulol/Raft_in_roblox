-- ChallengesTab.client.lua
-- Renders the timed challenges into the QuestMenu's "Challenges" tab.
-- Builds incrementally across F1 → F10 so each commit is testable.
--
-- Challenge cards are similar to the daily quest cards but with a
-- prominent live countdown and a 4-state action button: Start →
-- Tracking → Claim → (back to Start once expired or claimed). The
-- catalog ships 4 challenges today; the layout stacks them
-- vertically inside a scroll frame so each card has room to display
-- the timer at full size.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_WOOD_DARK    = Color3.fromRGB( 91,  58,  34)
local COLOR_WOOD_MID     = Color3.fromRGB(138, 106,  68)
local COLOR_WOOD_BASE    = Color3.fromRGB(176, 138,  92)
local COLOR_PAPER        = Color3.fromRGB(233, 217, 184)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(243, 230, 204)
local COLOR_PROGRESS     = Color3.fromRGB(126, 175,  90)
local COLOR_TIMER        = Color3.fromRGB(178,  79,  64)   -- redder when running

local CARD_RADIUS = 12

local function waitForMountPoint(timeoutSec)
	local deadline = os.clock() + (timeoutSec or 30)
	while os.clock() < deadline do
		local pages = _G.QuestMenuContentPages
		if pages and pages.challenges then
			return pages.challenges
		end
		task.wait(0.1)
	end
	return nil
end

local function waitForQuestStateEvent(timeoutSec)
	local deadline = os.clock() + (timeoutSec or 30)
	while os.clock() < deadline do
		local evt = ReplicatedStorage:FindFirstChild("QuestState")
		if evt and evt:IsA("RemoteEvent") then
			return evt
		end
		task.wait(0.1)
	end
	return nil
end

-- Forward-declared so buildCard's click handler can capture it.
local questStateEvent

-- ─── Mount + vertical scroll container (F2) ─────────────────────────
local CHALLENGES_TAB_PAD = 12
local CARD_GAP           = 10

local function mount(parent)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ChallengesScroll"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = COLOR_WOOD_DARK
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 6
	scroll.Parent = parent

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, CHALLENGES_TAB_PAD)
	pad.PaddingBottom = UDim.new(0, CHALLENGES_TAB_PAD)
	pad.PaddingLeft   = UDim.new(0, CHALLENGES_TAB_PAD)
	pad.PaddingRight  = UDim.new(0, CHALLENGES_TAB_PAD)
	pad.Parent = scroll

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, CARD_GAP)
	list.Parent = scroll

	return scroll
end

-- ─── Challenge card chrome (F3) ─────────────────────────────────────
-- Full-width card that stacks vertically inside the scroll. Same
-- chrome treatment as the story card: paper fill, wood-dark stroke,
-- rounded corners. Internal layout uses absolute positioning so the
-- countdown timer can sit on the right of the header without being
-- pushed by the title length.
local function buildCard(parent, layoutOrder)
	local card = Instance.new("Frame")
	card.Name = "ChallengeCard"
	card.LayoutOrder = layoutOrder or 0
	card.Size = UDim2.new(1, 0, 0, 110)
	card.BackgroundColor3 = COLOR_PAPER
	card.BorderSizePixel = 0
	card.ZIndex = 7
	card.Parent = parent
	-- Card attributes drive the click handler dispatch (F8). F9's paint
	-- path overwrites these per snapshot:
	--   QuestId : "" | "<id>"
	--   Mode    : "start" | "tracking" | "claim"
	card:SetAttribute("QuestId", "")
	card:SetAttribute("Mode", "start")

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0, CARD_RADIUS)
	cCorner.Parent = card

	local cStroke = Instance.new("UIStroke")
	cStroke.Color = COLOR_WOOD_DARK
	cStroke.Thickness = 2
	cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cStroke.Parent = card

	local cPad = Instance.new("UIPadding")
	cPad.PaddingTop    = UDim.new(0, 10)
	cPad.PaddingBottom = UDim.new(0, 10)
	cPad.PaddingLeft   = UDim.new(0, 12)
	cPad.PaddingRight  = UDim.new(0, 12)
	cPad.Parent = card

	-- ── Header (F4) ───────────────────────────────────────────────────
	-- Icon on the left, title + body stacked to the right. Reserves
	-- 80 px on the right edge for the timer (F6) so a long title
	-- can't overlap the countdown.
	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "Icon"
	iconImage.AnchorPoint = Vector2.new(0, 0)
	iconImage.Position = UDim2.new(0, 0, 0, 0)
	iconImage.Size = UDim2.fromOffset(54, 54)
	iconImage.BackgroundTransparency = 1
	iconImage.BorderSizePixel = 0
	iconImage.ScaleType = Enum.ScaleType.Fit
	iconImage.Image = ""
	iconImage.ZIndex = card.ZIndex + 1
	iconImage.Parent = card

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0, 0)
	title.Position = UDim2.new(0, 64, 0, 2)
	title.Size = UDim2.new(1, -64 - 80, 0, 22)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextColor3 = COLOR_WOOD_DARKEST
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = ""
	title.ZIndex = card.ZIndex + 1
	title.Parent = card

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0, 0)
	body.Position = UDim2.new(0, 64, 0, 26)
	body.Size = UDim2.new(1, -64 - 80, 0, 28)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.Gotham
	body.TextSize = 11
	body.TextColor3 = COLOR_WOOD_DARK
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.Text = ""
	body.ZIndex = card.ZIndex + 1
	body.Parent = card

	-- ── Progress bar (F5) ─────────────────────────────────────────────
	-- Sits at fixed Y below the header; goal/progress label is anchored
	-- inside the bar's right edge so a long quest title above can't
	-- collide with it.
	local PROGRESS_Y = 60
	local PROGRESS_H = 8
	local progressTrack = Instance.new("Frame")
	progressTrack.Name = "ProgressTrack"
	progressTrack.AnchorPoint = Vector2.new(0, 0)
	progressTrack.Position = UDim2.new(0, 0, 0, PROGRESS_Y)
	progressTrack.Size = UDim2.new(1, -64, 0, PROGRESS_H)
	progressTrack.BackgroundColor3 = COLOR_WOOD_DARK
	progressTrack.BackgroundTransparency = 0.55
	progressTrack.BorderSizePixel = 0
	progressTrack.ZIndex = card.ZIndex + 1
	progressTrack.Parent = card
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, math.floor(PROGRESS_H / 2))
	trackCorner.Parent = progressTrack

	local progressFill = Instance.new("Frame")
	progressFill.Name = "ProgressFill"
	progressFill.AnchorPoint = Vector2.new(0, 0.5)
	progressFill.Position = UDim2.fromScale(0, 0.5)
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.BackgroundColor3 = COLOR_PROGRESS
	progressFill.BorderSizePixel = 0
	progressFill.ZIndex = progressTrack.ZIndex + 1
	progressFill.Parent = progressTrack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, math.floor(PROGRESS_H / 2))
	fillCorner.Parent = progressFill

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "ProgressLabel"
	progressLabel.AnchorPoint = Vector2.new(0, 0)
	progressLabel.Position = UDim2.new(0, 0, 0, PROGRESS_Y + PROGRESS_H + 2)
	progressLabel.Size = UDim2.new(1, -64, 0, 12)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Font = Enum.Font.GothamMedium
	progressLabel.TextSize = 11
	progressLabel.TextColor3 = COLOR_WOOD_DARK
	progressLabel.TextXAlignment = Enum.TextXAlignment.Right
	progressLabel.Text = ""
	progressLabel.ZIndex = card.ZIndex + 1
	progressLabel.Parent = card

	-- F6-F7 layer timer / footer onto refs.
	local refs = {
		card          = card,
		iconImage     = iconImage,
		title         = title,
		body          = body,
		progressTrack = progressTrack,
		progressFill  = progressFill,
		progressLabel = progressLabel,
	}
	return card, refs
end

local mountPoint = waitForMountPoint(30)
if not mountPoint then
	warn("[ChallengesTab] _G.QuestMenuContentPages.challenges not available within 30 s; tab disabled")
	return
end

questStateEvent = waitForQuestStateEvent(30)
if not questStateEvent then
	warn("[ChallengesTab] QuestState RemoteEvent missing; tab disabled")
	return
end

local scrollFrame = mount(mountPoint)

-- Subscribe to state pushes from the server. F9 implements the real
-- repaint; F2 just leaves the wiring testable.
questStateEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "state" then return end
	if type(payload) ~= "table" then return end
	-- Phase F9 will iterate payload.quests filtered by kind=="challenge".
end)
