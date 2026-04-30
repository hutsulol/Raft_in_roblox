-- StoryTab.client.lua
-- Renders the story arc into the QuestMenu's "Story" tab.
-- Builds incrementally across E1 → E10 so each commit is testable.
--
-- Story quests differ from dailies in two ways: they have multiple
-- objectives per card (a checklist), and they live forever once
-- shown until the player marks them permanently completed (then the
-- card disappears and stays gone). The catalog ships two story
-- quests today (Lost in the Woods, Stranded Survivor); the layout
-- here scales to N stacked vertically inside a scrolling frame.
--
-- Same _G handshake as QuestsTab — we read the mount point off
-- _G.QuestMenuContentPages.story so QuestMenu doesn't need to know
-- about per-tab content modules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_WOOD_DARK    = Color3.fromRGB( 91,  58,  34)
local COLOR_WOOD_MID     = Color3.fromRGB(138, 106,  68)
local COLOR_WOOD_BASE    = Color3.fromRGB(176, 138,  92)
local COLOR_PAPER        = Color3.fromRGB(233, 217, 184)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(243, 230, 204)
local COLOR_PROGRESS     = Color3.fromRGB(126, 175,  90)

local CARD_RADIUS = 12

local function waitForMountPoint(timeoutSec)
	local deadline = os.clock() + (timeoutSec or 30)
	while os.clock() < deadline do
		local pages = _G.QuestMenuContentPages
		if pages and pages.story then
			return pages.story
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

-- ─── Mount + vertical scroll container ──────────────────────────────
-- Stacks story cards top-to-bottom in a scroll frame; AutomaticCanvasSize
-- lets the canvas grow if the catalog ever adds more story quests.
local STORY_TAB_PAD  = 12
local CARD_GAP       = 10

local function mount(parent)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "StoryScroll"
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
	pad.PaddingTop    = UDim.new(0, STORY_TAB_PAD)
	pad.PaddingBottom = UDim.new(0, STORY_TAB_PAD)
	pad.PaddingLeft   = UDim.new(0, STORY_TAB_PAD)
	pad.PaddingRight  = UDim.new(0, STORY_TAB_PAD)
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
	warn("[StoryTab] _G.QuestMenuContentPages.story not available within 30 s; tab disabled")
	return
end

questStateEvent = waitForQuestStateEvent(30)
if not questStateEvent then
	warn("[StoryTab] QuestState RemoteEvent missing; tab disabled")
	return
end

local scrollFrame = mount(mountPoint)

-- Subscribe to state pushes from the server. E9 implements the real
-- repaint; E2 just logs so the wiring is testable.
questStateEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "state" then return end
	if type(payload) ~= "table" then return end
	-- Phase E9 will iterate payload.quests filtered by kind=="story".
end)

-- The Quests tab also fires getState on mount; we don't fire again
-- here because both tabs receive the same broadcast.
