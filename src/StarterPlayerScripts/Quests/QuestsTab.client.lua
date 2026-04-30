-- QuestsTab.client.lua
-- Renders daily quest cards into the Quests tab's content page.
-- Builds incrementally across D1 → D10 so each commit is testable.
--
-- D1 scope: wait for the QuestMenu's contentPages.quests Frame to
-- exist + the QuestState RemoteEvent to appear, then mount a
-- ScrollingFrame + UIGridLayout there. Subscribe to "state" events
-- and log them. Card visuals + reactive painting land in D2 → D10.
--
-- This file decouples cleanly from QuestMenu — it reads the mount
-- point off _G.QuestMenuContentPages instead of being driven by
-- QuestMenu, so QuestMenu doesn't need to know about per-tab
-- content modules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function waitForMountPoint(timeoutSec)
	local deadline = os.clock() + (timeoutSec or 30)
	while os.clock() < deadline do
		local pages = _G.QuestMenuContentPages
		if pages and pages.quests then
			return pages.quests
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

-- ─── Mount + scroll container (D1) ──────────────────────────────────
-- 4-column grid of quest cards (the daily picks). The grid is large
-- enough that all 4 cards fit in a row at the menu's current width;
-- ScrollingFrame.AutomaticCanvasSize lets the page grow if more
-- cards land in later phases (history, etc.).
local QUESTS_TAB_PAD = 12
local CARD_W         = 132
local CARD_H         = 220
local CARD_GAP       = 10

local function mount(parent)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "QuestsScroll"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Color3.fromRGB(91, 58, 34)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 6
	scroll.Parent = parent

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, QUESTS_TAB_PAD)
	pad.PaddingBottom = UDim.new(0, QUESTS_TAB_PAD)
	pad.PaddingLeft   = UDim.new(0, QUESTS_TAB_PAD)
	pad.PaddingRight  = UDim.new(0, QUESTS_TAB_PAD)
	pad.Parent = scroll

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
	grid.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.VerticalAlignment = Enum.VerticalAlignment.Top
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	return scroll
end

local mountPoint = waitForMountPoint(30)
if not mountPoint then
	warn("[QuestsTab] _G.QuestMenuContentPages.quests not available within 30 s; tab disabled")
	return
end
local questStateEvent = waitForQuestStateEvent(30)
if not questStateEvent then
	warn("[QuestsTab] QuestState RemoteEvent missing; tab disabled")
	return
end

local scrollFrame = mount(mountPoint)

-- Subscribe to state pushes from the server. D9 implements the real
-- repaint; D1 just logs so the wiring is testable.
questStateEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "state" then return end
	if type(payload) ~= "table" then return end
	-- Phase D9 will iterate payload.quests and build cards here.
	print(string.format("[QuestsTab] state received with %d quests",
		#((payload.quests) or {})))
end)

-- Request initial state on mount in case the server's PlayerAdded
-- snapshot fired before this LocalScript was ready.
questStateEvent:FireServer("getState")
