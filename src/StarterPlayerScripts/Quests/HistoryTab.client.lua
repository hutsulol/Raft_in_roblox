-- HistoryTab.client.lua
-- Renders the player's historyLog into the QuestMenu's "History" tab.
-- The server caps the log at 50 entries and pushes them newest-first
-- in every state snapshot, so this tab is a thin reactive view: one
-- row per entry, with the icon + title + reward count + how long ago
-- the player claimed it.
--
-- Built across G1 → G5 so each commit is testable. G1 (this commit)
-- mounts the scroll + UIListLayout into the History page; G2-G5 add
-- the row component + reactive paint.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_WOOD_DARK    = Color3.fromRGB( 91,  58,  34)
local COLOR_WOOD_MID     = Color3.fromRGB(138, 106,  68)
local COLOR_PAPER        = Color3.fromRGB(233, 217, 184)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(243, 230, 204)

local function waitForMountPoint(timeoutSec)
	local deadline = os.clock() + (timeoutSec or 30)
	while os.clock() < deadline do
		local pages = _G.QuestMenuContentPages
		if pages and pages.history then
			return pages.history
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

-- ─── Mount + scroll container (G1) ──────────────────────────────────
local HISTORY_TAB_PAD = 12
local ROW_GAP         = 6

local function mount(parent)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "HistoryScroll"
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
	pad.PaddingTop    = UDim.new(0, HISTORY_TAB_PAD)
	pad.PaddingBottom = UDim.new(0, HISTORY_TAB_PAD)
	pad.PaddingLeft   = UDim.new(0, HISTORY_TAB_PAD)
	pad.PaddingRight  = UDim.new(0, HISTORY_TAB_PAD)
	pad.Parent = scroll

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, ROW_GAP)
	list.Parent = scroll

	return scroll
end

local mountPoint = waitForMountPoint(30)
if not mountPoint then
	warn("[HistoryTab] _G.QuestMenuContentPages.history not available within 30 s; tab disabled")
	return
end

local questStateEvent = waitForQuestStateEvent(30)
if not questStateEvent then
	warn("[HistoryTab] QuestState RemoteEvent missing; tab disabled")
	return
end

local scrollFrame = mount(mountPoint)

-- Subscribe to state pushes; G4 lands the real repaint.
questStateEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "state" then return end
	if type(payload) ~= "table" then return end
	-- Phase G4 will iterate payload.historyLog and paint rows.
end)
