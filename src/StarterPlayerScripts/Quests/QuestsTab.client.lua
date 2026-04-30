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

-- ─── Wood/paper palette (matches OnboardingTooltip + QuestMenu) ─────
local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_WOOD_DARK    = Color3.fromRGB( 91,  58,  34)
local COLOR_WOOD_MID     = Color3.fromRGB(138, 106,  68)
local COLOR_WOOD_BASE    = Color3.fromRGB(176, 138,  92)
local COLOR_PAPER        = Color3.fromRGB(233, 217, 184)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(243, 230, 204)

local CARD_RADIUS = 12

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

-- ─── Single quest card (D2 → D7) ────────────────────────────────────
-- Returns the outer card Frame plus a refs table that later substeps
-- (D9 reactive paint) populate to update the card without rebuilding.
-- D2 (this commit) covers the outer paper-fill card chrome only;
-- D3-D7 layer in the icon, title, body, progress bar, reward, and
-- track button on top.
local function buildCard(parent, layoutOrder)
	local card = Instance.new("Frame")
	card.Name = "QuestCard"
	card.LayoutOrder = layoutOrder or 0
	card.BackgroundColor3 = COLOR_PAPER
	card.BorderSizePixel = 0
	card.ZIndex = 7
	card.Parent = parent

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
	cPad.PaddingLeft   = UDim.new(0, 10)
	cPad.PaddingRight  = UDim.new(0, 10)
	cPad.Parent = card

	-- ── Icon box (D3) ─────────────────────────────────────────────────
	-- 80x80 square pinned to the top of the card. Slightly darker
	-- paper fill than the card itself so the icon reads as elevated.
	-- Quest icon is filled in by D9's paint path; for now D3 just
	-- creates the empty box and the inner ImageLabel.
	local ICON_BOX_SIZE = 80
	local iconBox = Instance.new("Frame")
	iconBox.Name = "IconBox"
	iconBox.AnchorPoint = Vector2.new(0.5, 0)
	iconBox.Position = UDim2.new(0.5, 0, 0, 0)
	iconBox.Size = UDim2.fromOffset(ICON_BOX_SIZE, ICON_BOX_SIZE)
	iconBox.BackgroundColor3 = COLOR_WOOD_BASE
	iconBox.BackgroundTransparency = 0.45
	iconBox.BorderSizePixel = 0
	iconBox.ZIndex = card.ZIndex + 1
	iconBox.Parent = card
	local iCorner = Instance.new("UICorner")
	iCorner.CornerRadius = UDim.new(0, 10)
	iCorner.Parent = iconBox
	local iStroke = Instance.new("UIStroke")
	iStroke.Color = COLOR_WOOD_DARK
	iStroke.Thickness = 1.5
	iStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	iStroke.Parent = iconBox

	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "Icon"
	iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
	iconImage.Position = UDim2.fromScale(0.5, 0.5)
	iconImage.Size = UDim2.new(1, -12, 1, -12)
	iconImage.BackgroundTransparency = 1
	iconImage.BorderSizePixel = 0
	iconImage.Image = ""   -- D9 fills from snapshot.icon
	iconImage.ScaleType = Enum.ScaleType.Fit
	iconImage.ZIndex = iconBox.ZIndex + 1
	iconImage.Parent = iconBox

	-- refs is the live handle the reactive paint path (D9) updates.
	-- D3-D7 add nodes (iconImage, title, body, progressFill, label,
	-- rewardLabel, trackBtn) into it.
	local refs = {
		card      = card,
		iconBox   = iconBox,
		iconImage = iconImage,
	}
	return card, refs
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
