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

-- ─── Single objective row (E6) ──────────────────────────────────────
-- One row per objective inside a story card. Layout reads "label on
-- the left, N/M on the right, thin progress bar below the row".
-- Returned refs let E9's paint path update progress without rebuilding
-- the row.
-- Compacter rows now that the progress bar is hidden — the new
-- design uses checkmark / hollow-circle status indicators instead
-- of a thin under-bar.
local OBJ_ROW_H    = 22
local OBJ_BAR_H    = 4
local function buildObjectiveRow(parent, layoutOrder)
	local row = Instance.new("Frame")
	row.Name = "ObjectiveRow"
	row.LayoutOrder = layoutOrder or 0
	row.Size = UDim2.new(1, 0, 0, OBJ_ROW_H)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.ZIndex = 8
	row.Parent = parent

	-- No internal padding here — the parent Objectives box already
	-- supplies padding and the status icon hugs the left edge.

	-- Status icon on the very left: filled green check when the
	-- objective is complete, hollow circle while it's in progress.
	-- Mirrors the reference mockup's "tick / unticked" indicators.
	local STATUS_ICON_W = 18
	local statusIcon = Instance.new("TextLabel")
	statusIcon.Name = "Status"
	statusIcon.AnchorPoint = Vector2.new(0, 0.5)
	statusIcon.Position = UDim2.new(0, 0, 0.5, 0)
	statusIcon.Size = UDim2.fromOffset(STATUS_ICON_W, OBJ_ROW_H)
	statusIcon.BackgroundTransparency = 1
	statusIcon.Font = Enum.Font.GothamBold
	statusIcon.TextSize = 14
	statusIcon.TextColor3 = COLOR_WOOD_DARK
	statusIcon.Text = "○"
	statusIcon.ZIndex = row.ZIndex + 1
	statusIcon.Parent = row

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0, 0)
	label.Position = UDim2.new(0, STATUS_ICON_W + 6, 0, 0)
	label.Size = UDim2.new(1, -(STATUS_ICON_W + 6 + 50), 0, 14)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 12
	label.TextColor3 = COLOR_WOOD_DARKEST
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.ZIndex = row.ZIndex + 1
	label.Parent = row

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, 0, 0, 0)
	count.Size = UDim2.new(0, 50, 0, 14)
	count.BackgroundTransparency = 1
	count.Font = Enum.Font.GothamBold
	count.TextSize = 12
	count.TextColor3 = COLOR_WOOD_DARK
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextYAlignment = Enum.TextYAlignment.Center
	count.Text = ""
	count.ZIndex = row.ZIndex + 1
	count.Parent = row

	-- Progress bar — hidden on the new design but kept in the tree
	-- so the paint path's barFill.Size assignment stays a no-op
	-- without an extra nil-check.
	local barTrack = Instance.new("Frame")
	barTrack.Name = "BarTrack"
	barTrack.AnchorPoint = Vector2.new(0, 1)
	barTrack.Position = UDim2.new(0, 0, 1, 0)
	barTrack.Size = UDim2.new(1, 0, 0, OBJ_BAR_H)
	barTrack.BackgroundColor3 = COLOR_WOOD_DARK
	barTrack.BackgroundTransparency = 0.6
	barTrack.BorderSizePixel = 0
	barTrack.Visible = false
	barTrack.ZIndex = row.ZIndex + 1
	barTrack.Parent = row
	local btCorner = Instance.new("UICorner")
	btCorner.CornerRadius = UDim.new(0, math.floor(OBJ_BAR_H / 2))
	btCorner.Parent = barTrack

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.AnchorPoint = Vector2.new(0, 0.5)
	barFill.Position = UDim2.fromScale(0, 0.5)
	barFill.Size = UDim2.fromScale(0, 1)   -- E9 paints Size.X.Scale
	barFill.BackgroundColor3 = COLOR_PROGRESS
	barFill.BorderSizePixel = 0
	barFill.ZIndex = barTrack.ZIndex + 1
	barFill.Parent = barTrack
	local bfCorner = Instance.new("UICorner")
	bfCorner.CornerRadius = UDim.new(0, math.floor(OBJ_BAR_H / 2))
	bfCorner.Parent = barFill

	return {
		row        = row,
		label      = label,
		count      = count,
		barFill    = barFill,
		statusIcon = statusIcon,
	}
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
	-- Outer card uses the wood mid-tone so the Objectives / Reward
	-- panels (paper-light) read as panels-on-wood. The header
	-- (icon + title + body) sits directly on this wood — no panel
	-- chrome — to match the reference mockup.
	card.BackgroundColor3 = COLOR_WOOD_BASE
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

	-- ── Header row ─────────────────────────────────────────────────
	-- Quest icon + title + body floats directly on the wood card with
	-- no panel chrome (no fill, no corner, no stroke) — the panels
	-- live below for Objectives / Reward / Track button only.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, 0, 0, 70)
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.ZIndex = card.ZIndex + 1
	header.Parent = card

	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "Icon"
	iconImage.AnchorPoint = Vector2.new(0, 0.5)
	iconImage.Position = UDim2.new(0, 0, 0.5, 0)
	iconImage.Size = UDim2.fromOffset(54, 54)
	iconImage.BackgroundTransparency = 1
	iconImage.BorderSizePixel = 0
	iconImage.ScaleType = Enum.ScaleType.Fit
	iconImage.Image = ""   -- E9 fills from snapshot.icon
	iconImage.ZIndex = header.ZIndex + 1
	iconImage.Parent = header

	-- Title + body share the right-side column (icon takes the left).
	-- Text colour goes a touch lighter than COLOR_WOOD_DARKEST so it
	-- reads on the wood-base card without the paper backdrop.
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0, 0)
	title.Position = UDim2.new(0, 70, 0, 4)
	title.Size = UDim2.new(1, -70, 0, 22)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = COLOR_PAPER_LIGHT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = ""
	title.ZIndex = header.ZIndex + 1
	title.Parent = header

	local bodyText = Instance.new("TextLabel")
	bodyText.Name = "Body"
	bodyText.AnchorPoint = Vector2.new(0, 0)
	bodyText.Position = UDim2.new(0, 70, 0, 28)
	bodyText.Size = UDim2.new(1, -70, 0, 38)
	bodyText.BackgroundTransparency = 1
	bodyText.Font = Enum.Font.Gotham
	bodyText.TextSize = 12
	bodyText.TextColor3 = COLOR_PAPER
	bodyText.TextXAlignment = Enum.TextXAlignment.Left
	bodyText.TextYAlignment = Enum.TextYAlignment.Top
	bodyText.TextWrapped = true
	bodyText.Text = ""
	bodyText.ZIndex = header.ZIndex + 1
	bodyText.Parent = header

	-- ── Two-column body: objectives box (left) + reward box (right) ────
	-- Mirrors the reference mockup: tasks + progress on the left, the
	-- chest reward on the right. Both share the same paper-light fill
	-- so they read as paired panels. The row itself uses a horizontal
	-- UIListLayout so it auto-sizes to the taller column — no fixed
	-- 120-px height, no empty space.
	local OBJ_BOX_RATIO = 0.62  -- 62% objectives column, 38% reward column
	local BODY_GAP      = 8
	local OBJ_BOX_PAD   = 10

	local bodyRow = Instance.new("Frame")
	bodyRow.Name = "BodyRow"
	bodyRow.LayoutOrder = 2
	bodyRow.Size = UDim2.new(1, 0, 0, 0)
	bodyRow.AutomaticSize = Enum.AutomaticSize.Y
	bodyRow.BackgroundTransparency = 1
	bodyRow.ZIndex = card.ZIndex + 1
	bodyRow.Parent = card

	local bodyRowLayout = Instance.new("UIListLayout")
	bodyRowLayout.FillDirection = Enum.FillDirection.Horizontal
	bodyRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	bodyRowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	bodyRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyRowLayout.Padding = UDim.new(0, BODY_GAP)
	bodyRowLayout.Parent = bodyRow

	local objBox = Instance.new("Frame")
	objBox.Name = "Objectives"
	objBox.LayoutOrder = 1
	objBox.Size = UDim2.new(OBJ_BOX_RATIO, -BODY_GAP / 2, 0, 0)
	objBox.AutomaticSize = Enum.AutomaticSize.Y
	objBox.BackgroundColor3 = COLOR_PAPER_LIGHT
	objBox.BackgroundTransparency = 0.05
	objBox.BorderSizePixel = 0
	objBox.ZIndex = bodyRow.ZIndex + 1
	objBox.Parent = bodyRow

	local objBoxCorner = Instance.new("UICorner")
	objBoxCorner.CornerRadius = UDim.new(0, 8)
	objBoxCorner.Parent = objBox

	local objBoxStroke = Instance.new("UIStroke")
	objBoxStroke.Color = COLOR_WOOD_DARK
	objBoxStroke.Thickness = 1
	objBoxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	objBoxStroke.Parent = objBox

	local objBoxPad = Instance.new("UIPadding")
	objBoxPad.PaddingTop    = UDim.new(0, OBJ_BOX_PAD)
	objBoxPad.PaddingBottom = UDim.new(0, OBJ_BOX_PAD)
	objBoxPad.PaddingLeft   = UDim.new(0, OBJ_BOX_PAD)
	objBoxPad.PaddingRight  = UDim.new(0, OBJ_BOX_PAD)
	objBoxPad.Parent = objBox

	local objCaption = Instance.new("TextLabel")
	objCaption.Name = "Caption"
	objCaption.LayoutOrder = 1
	objCaption.Size = UDim2.new(1, 0, 0, 14)
	objCaption.BackgroundTransparency = 1
	objCaption.Font = Enum.Font.GothamBold
	objCaption.TextSize = 12
	objCaption.TextColor3 = COLOR_WOOD_DARK
	objCaption.TextXAlignment = Enum.TextXAlignment.Left
	objCaption.Text = "Objectives"
	objCaption.ZIndex = objBox.ZIndex + 1
	objCaption.Parent = objBox

	local objList = Instance.new("Frame")
	objList.Name = "List"
	objList.LayoutOrder = 2
	objList.Size = UDim2.new(1, 0, 0, 0)
	objList.AutomaticSize = Enum.AutomaticSize.Y
	objList.BackgroundTransparency = 1
	objList.ZIndex = objBox.ZIndex + 1
	objList.Parent = objBox

	local objBoxLayout = Instance.new("UIListLayout")
	objBoxLayout.FillDirection = Enum.FillDirection.Vertical
	objBoxLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	objBoxLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	objBoxLayout.SortOrder = Enum.SortOrder.LayoutOrder
	objBoxLayout.Padding = UDim.new(0, 6)
	objBoxLayout.Parent = objBox

	local objLayout = Instance.new("UIListLayout")
	objLayout.FillDirection = Enum.FillDirection.Vertical
	objLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	objLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	objLayout.SortOrder = Enum.SortOrder.LayoutOrder
	objLayout.Padding = UDim.new(0, 6)
	objLayout.Parent = objList

	-- Reward box on the right: "Reward" caption + chest icon + name,
	-- stacked via UIListLayout so the box auto-sizes to its content
	-- (no empty space below the label).
	local rewardBox = Instance.new("Frame")
	rewardBox.Name = "RewardBox"
	rewardBox.LayoutOrder = 2
	rewardBox.Size = UDim2.new(1 - OBJ_BOX_RATIO, -BODY_GAP / 2, 0, 0)
	rewardBox.AutomaticSize = Enum.AutomaticSize.Y
	rewardBox.BackgroundColor3 = COLOR_PAPER_LIGHT
	rewardBox.BackgroundTransparency = 0.05
	rewardBox.BorderSizePixel = 0
	rewardBox.ZIndex = bodyRow.ZIndex + 1
	rewardBox.Parent = bodyRow

	local rewardBoxCorner = Instance.new("UICorner")
	rewardBoxCorner.CornerRadius = UDim.new(0, 8)
	rewardBoxCorner.Parent = rewardBox

	local rewardBoxStroke = Instance.new("UIStroke")
	rewardBoxStroke.Color = COLOR_WOOD_DARK
	rewardBoxStroke.Thickness = 1
	rewardBoxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rewardBoxStroke.Parent = rewardBox

	local rewardBoxPad = Instance.new("UIPadding")
	rewardBoxPad.PaddingTop    = UDim.new(0, OBJ_BOX_PAD)
	rewardBoxPad.PaddingBottom = UDim.new(0, OBJ_BOX_PAD)
	rewardBoxPad.PaddingLeft   = UDim.new(0, OBJ_BOX_PAD)
	rewardBoxPad.PaddingRight  = UDim.new(0, OBJ_BOX_PAD)
	rewardBoxPad.Parent = rewardBox

	local rewardBoxLayout = Instance.new("UIListLayout")
	rewardBoxLayout.FillDirection = Enum.FillDirection.Vertical
	rewardBoxLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rewardBoxLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	rewardBoxLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rewardBoxLayout.Padding = UDim.new(0, 6)
	rewardBoxLayout.Parent = rewardBox

	local rewardCaption = Instance.new("TextLabel")
	rewardCaption.Name = "Caption"
	rewardCaption.LayoutOrder = 1
	rewardCaption.Size = UDim2.new(1, 0, 0, 14)
	rewardCaption.BackgroundTransparency = 1
	rewardCaption.Font = Enum.Font.GothamBold
	rewardCaption.TextSize = 12
	rewardCaption.TextColor3 = COLOR_WOOD_DARK
	rewardCaption.TextXAlignment = Enum.TextXAlignment.Center
	rewardCaption.Text = "Reward"
	rewardCaption.ZIndex = rewardBox.ZIndex + 1
	rewardCaption.Parent = rewardBox

	local DEFAULT_REWARD_ICON = "rbxassetid://82337855669175"
	local rewardIcon = Instance.new("ImageLabel")
	rewardIcon.Name = "Icon"
	rewardIcon.LayoutOrder = 2
	rewardIcon.Size = UDim2.fromOffset(56, 56)
	rewardIcon.BackgroundTransparency = 1
	rewardIcon.BorderSizePixel = 0
	rewardIcon.ScaleType = Enum.ScaleType.Fit
	rewardIcon.Image = DEFAULT_REWARD_ICON
	rewardIcon.ZIndex = rewardBox.ZIndex + 1
	rewardIcon.Parent = rewardBox

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "Label"
	rewardLabel.LayoutOrder = 3
	rewardLabel.Size = UDim2.new(1, 0, 0, 16)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.TextSize = 12
	rewardLabel.TextColor3 = COLOR_WOOD_DARKEST
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Center
	rewardLabel.Text = ""
	rewardLabel.ZIndex = rewardBox.ZIndex + 1
	rewardLabel.Parent = rewardBox

	-- ── Bottom action button: full-width "Claim Reward" / "Track" ──
	-- Replaces the right-aligned 130-px button. The button still
	-- cycles modes (Track / Tracking / Claim Reward) — paint path
	-- below swaps the label and colours.
	local CLAIM_BTN_H = 38
	local trackBtn = Instance.new("TextButton")
	trackBtn.Name = "ClaimBtn"
	trackBtn.LayoutOrder = 3
	trackBtn.Size = UDim2.new(1, 0, 0, CLAIM_BTN_H)
	trackBtn.AutoButtonColor = false
	trackBtn.BackgroundColor3 = COLOR_PAPER_LIGHT
	trackBtn.BorderSizePixel = 0
	trackBtn.Font = Enum.Font.GothamBold
	trackBtn.TextSize = 14
	trackBtn.TextColor3 = COLOR_WOOD_DARKEST
	trackBtn.Text = "★ Track"
	trackBtn.ZIndex = card.ZIndex + 2
	trackBtn.Parent = card
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = trackBtn
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = COLOR_WOOD_DARK
	btnStroke.Thickness = 1.5
	btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	btnStroke.Parent = trackBtn

	-- ── Click dispatch (E8) ───────────────────────────────────────────
	-- Same approach as the daily card: one connection that reads the
	-- card's current Mode + QuestId attributes at click time so the
	-- paint path can swap modes without us re-binding. Server is
	-- the source of truth; we don't optimistically mutate.
	trackBtn.Activated:Connect(function()
		local id   = card:GetAttribute("QuestId")
		local mode = card:GetAttribute("Mode")
		if type(id) ~= "string" or id == "" then return end
		if not questStateEvent then return end
		if mode == "tracking" then
			questStateEvent:FireServer("untrack", id)
		elseif mode == "claim" then
			questStateEvent:FireServer("claimReward", id)
		else
			questStateEvent:FireServer("track", id)
		end
	end)

	local refs = {
		card           = card,
		iconImage      = iconImage,
		title          = title,
		body           = bodyText,
		objList        = objList,
		-- Per-objective rows live here, keyed by objective index. E9's
		-- paint path adds + reuses them per snapshot to avoid rebuilding
		-- the row Frame on every push.
		objRows        = {},
		rewardCaption  = rewardCaption,
		rewardIcon     = rewardIcon,
		rewardLabel    = rewardLabel,
		trackBtn       = trackBtn,
		trackBtnStroke = btnStroke,
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

-- ─── Empty state (E10) ──────────────────────────────────────────────
-- Sibling of the scroll frame so it isn't laid out by the UIListLayout.
-- Visible when the player has no story quests left in the snapshot —
-- i.e. they've permanently completed every story arc the catalog
-- ships, or the catalog never loaded server-side. Sits centered with
-- a brief congratulations note.
local emptyState = Instance.new("TextLabel")
emptyState.Name = "EmptyState"
emptyState.AnchorPoint = Vector2.new(0.5, 0.5)
emptyState.Position = UDim2.fromScale(0.5, 0.5)
emptyState.Size = UDim2.new(1, -40, 0, 40)
emptyState.BackgroundTransparency = 1
emptyState.Font = Enum.Font.GothamMedium
emptyState.TextSize = 14
emptyState.TextColor3 = COLOR_WOOD_DARK
emptyState.TextWrapped = true
emptyState.TextXAlignment = Enum.TextXAlignment.Center
emptyState.TextYAlignment = Enum.TextYAlignment.Center
emptyState.Text = "No story quests right now.\nMore arcs coming soon."
emptyState.Visible = false
emptyState.ZIndex = 6
emptyState.Parent = mountPoint

-- ─── Reactive paint (E9) ────────────────────────────────────────────
-- cardsById maps quest id → { card, refs } so each snapshot repaints
-- in place. Per-objective rows are reused across pushes too: the
-- paint loop calls refs.objRows[i] if present, otherwise builds a
-- new row and stashes it. Rows past the current objective count are
-- destroyed (rare — only fires if the catalog mutates), keeping the
-- UI in sync without a full rebuild.
local cardsById = {}

local function paintCard(refs, q)
	refs.iconImage.Image = q.icon or ""
	refs.title.Text      = q.title or ""
	refs.body.Text       = q.body or ""

	-- Objectives — one row per entry; reuse existing rows where we can.
	local objs = q.objectives or {}
	for i, obj in ipairs(objs) do
		local row = refs.objRows[i]
		if not row then
			row = buildObjectiveRow(refs.objList, i)
			refs.objRows[i] = row
		end
		local prog = tonumber(obj.progress) or 0
		local goal = tonumber(obj.goal) or 0
		local pct = (goal > 0) and math.clamp(prog / goal, 0, 1) or 0
		row.label.Text   = obj.label or obj.eventType or "Objective"
		row.count.Text   = string.format("%d / %d", prog, goal)
		row.barFill.Size = UDim2.new(pct, 0, 1, 0)
		-- Status indicator — green check when complete, hollow circle
		-- while in progress. Mirrors the reference mockup's tick /
		-- unticked state. Completed objectives also dim slightly so
		-- the player's eye lands on what's still outstanding.
		if pct >= 1 then
			row.statusIcon.Text      = "✓"
			row.statusIcon.TextColor3 = COLOR_PROGRESS
			row.label.TextColor3     = COLOR_WOOD_MID
		else
			row.statusIcon.Text      = "○"
			row.statusIcon.TextColor3 = COLOR_WOOD_DARK
			row.label.TextColor3     = COLOR_WOOD_DARKEST
		end
	end
	-- Trim any leftover rows from a previous repaint with more objectives.
	for i = #objs + 1, #refs.objRows do
		refs.objRows[i].row:Destroy()
		refs.objRows[i] = nil
	end

	-- Reward — show the chest icon (or the quest's own icon if it
	-- ships one) and the reward's display name. The server snapshot
	-- may carry q.reward.label / .name; fall back to a count badge
	-- so older quests still render something useful.
	local rewardName
	if q.reward then
		rewardName = q.reward.label or q.reward.name
		if not rewardName and q.reward.count then
			rewardName = "x" .. tostring(q.reward.count)
		end
	end
	refs.rewardLabel.Text = rewardName or "Mystery Chest"
	-- Default is the chest asset assigned at build time; only swap
	-- it out when the snapshot ships its own reward icon.
	local rewardIconAsset = q.reward and (q.reward.icon or q.reward.image)
	if rewardIconAsset and rewardIconAsset ~= "" then
		refs.rewardIcon.Image = rewardIconAsset
	end

	refs.card:SetAttribute("QuestId", q.id or "")

	-- Three-mode track button — same priority as daily: rewardPending
	-- beats tracked beats default, because "Claim" is the action the
	-- player should take next. Labels match the reference mockup
	-- ("Claim Reward" instead of just "Claim").
	if q.rewardPending then
		refs.card:SetAttribute("Mode", "claim")
		refs.trackBtn.Text = "Claim Reward"
		refs.trackBtn.BackgroundColor3 = COLOR_WOOD_BASE
		refs.trackBtn.TextColor3       = COLOR_PAPER_LIGHT
		refs.trackBtnStroke.Color      = COLOR_WOOD_DARKEST
	elseif q.tracked then
		refs.card:SetAttribute("Mode", "tracking")
		refs.trackBtn.Text = "★ Tracking"
		refs.trackBtn.BackgroundColor3 = COLOR_WOOD_DARK
		refs.trackBtn.TextColor3       = COLOR_PAPER_LIGHT
		refs.trackBtnStroke.Color      = COLOR_WOOD_DARKEST
	else
		refs.card:SetAttribute("Mode", "track")
		refs.trackBtn.Text = "★ Track"
		refs.trackBtn.BackgroundColor3 = COLOR_PAPER_LIGHT
		refs.trackBtn.TextColor3       = COLOR_WOOD_DARKEST
		refs.trackBtnStroke.Color      = COLOR_WOOD_DARK
	end
end

local function repaint(payload)
	-- Only ONE story quest is active at a time, per the redesign:
	-- the player can't hold two parallel storylines. Pick the first
	-- with a pending reward (so the player gets the Claim Reward
	-- prompt as soon as a chapter wraps), else the tracked one,
	-- else the first not-yet-completed story in catalog order.
	local activeQuest
	local fallback
	local pendingReward
	for _, q in ipairs(payload.quests or {}) do
		if q.kind == "story" then
			if q.rewardPending and not pendingReward then
				pendingReward = q
			elseif q.tracked and not activeQuest then
				activeQuest = q
			elseif not fallback then
				fallback = q
			end
		end
	end
	activeQuest = pendingReward or activeQuest or fallback

	-- Always destroy + rebuild the card on each repaint. Reusing the
	-- card across tab switches caused the auto-sized two-column body
	-- to settle into a stale layout the second time the Story tab
	-- was opened — full rebuild keeps the layout deterministic.
	for id, entry in pairs(cardsById) do
		entry.card:Destroy()
		cardsById[id] = nil
	end

	if activeQuest then
		local card, refs = buildCard(scrollFrame, 1)
		cardsById[activeQuest.id] = { card = card, refs = refs }
		paintCard(refs, activeQuest)
	end

	emptyState.Visible = (activeQuest == nil)
end

questStateEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "state" then return end
	if type(payload) ~= "table" then return end
	repaint(payload)
end)

-- The Quests tab also fires getState on mount; we don't fire again
-- here because both tabs receive the same broadcast.
