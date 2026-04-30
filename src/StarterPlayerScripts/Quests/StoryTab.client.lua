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

-- ─── Story card chrome (E3) ─────────────────────────────────────────
-- Full-width card that stacks vertically inside the scroll. Each
-- card holds a header row, an objectives checklist, and a reward+button
-- footer (added in E4-E7). Card height adjusts to its content via
-- AutomaticSize.Y so a 4-objective story takes more vertical space
-- than a 3-objective one without stretching.
local function buildCard(parent, layoutOrder)
	local card = Instance.new("Frame")
	card.Name = "StoryCard"
	card.LayoutOrder = layoutOrder or 0
	card.Size = UDim2.new(1, 0, 0, 0)   -- height auto-sized below
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = COLOR_PAPER
	card.BorderSizePixel = 0
	card.ZIndex = 7
	card.Parent = parent
	-- Card attributes drive the click handler dispatch (E8). E9's paint
	-- path overwrites these per snapshot:
	--   QuestId : "" | "<id>"
	--   Mode    : "track" | "tracking" | "claim"
	card:SetAttribute("QuestId", "")
	card:SetAttribute("Mode", "track")

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0, CARD_RADIUS)
	cCorner.Parent = card

	local cStroke = Instance.new("UIStroke")
	cStroke.Color = COLOR_WOOD_DARK
	cStroke.Thickness = 2
	cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cStroke.Parent = card

	local cPad = Instance.new("UIPadding")
	cPad.PaddingTop    = UDim.new(0, 12)
	cPad.PaddingBottom = UDim.new(0, 12)
	cPad.PaddingLeft   = UDim.new(0, 14)
	cPad.PaddingRight  = UDim.new(0, 14)
	cPad.Parent = card

	local cLayout = Instance.new("UIListLayout")
	cLayout.FillDirection = Enum.FillDirection.Vertical
	cLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	cLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	cLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cLayout.Padding = UDim.new(0, 10)
	cLayout.Parent = card

	-- ── Header row (E4) ───────────────────────────────────────────────
	-- Icon on the left, title + body stacked on the right. Layout sits
	-- above the objectives list so the story reads "this is the quest,
	-- here's what to do" top-down.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundTransparency = 1
	header.ZIndex = card.ZIndex + 1
	header.Parent = card

	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "Icon"
	iconImage.AnchorPoint = Vector2.new(0, 0.5)
	iconImage.Position = UDim2.new(0, 0, 0.5, 0)
	iconImage.Size = UDim2.fromOffset(60, 60)
	iconImage.BackgroundTransparency = 1
	iconImage.BorderSizePixel = 0
	iconImage.ScaleType = Enum.ScaleType.Fit
	iconImage.Image = ""   -- E9 fills from snapshot.icon
	iconImage.ZIndex = header.ZIndex + 1
	iconImage.Parent = header

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0, 0)
	title.Position = UDim2.new(0, 70, 0, 2)
	title.Size = UDim2.new(1, -70, 0, 22)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = COLOR_WOOD_DARKEST
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = ""
	title.ZIndex = header.ZIndex + 1
	title.Parent = header

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0, 0)
	body.Position = UDim2.new(0, 70, 0, 26)
	body.Size = UDim2.new(1, -70, 0, 32)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.Gotham
	body.TextSize = 12
	body.TextColor3 = COLOR_WOOD_DARK
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.Text = ""
	body.ZIndex = header.ZIndex + 1
	body.Parent = header

	-- E5-E7 layer objectives / footer onto refs.
	local refs = {
		card      = card,
		iconImage = iconImage,
		title     = title,
		body      = body,
	}
	return card, refs
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
