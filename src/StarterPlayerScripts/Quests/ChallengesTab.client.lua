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
