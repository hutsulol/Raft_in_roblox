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

-- ─── Outbound dispatch (D8) ─────────────────────────────────────────
-- Forward-declared here so buildCard's click handler can capture it
-- as an upvalue. Real assignment happens further down once the
-- RemoteEvent has been resolved.
local questStateEvent

-- ─── Mount + scroll container (D1) ──────────────────────────────────
-- 4-column grid of quest cards (the daily picks). The grid is large
-- enough that all 4 cards fit in a row at the menu's current width;
-- ScrollingFrame.AutomaticCanvasSize lets the page grow if more
-- cards land in later phases (history, etc.).
local QUESTS_TAB_PAD = 12
local CARD_W         = 132
local CARD_H         = 244   -- D6 bumped from 220 to fit reward row + button reserve
local CARD_GAP       = 10
local TRACK_BTN_H    = 28    -- bottom-anchored area D7 fills with the track button

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
	-- Card attributes drive the click handler dispatch (D8). D9's paint
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

	-- ── Title + body (D4) ─────────────────────────────────────────────
	-- Title sits right under the icon box (80 + 8 padding = 88). Bold
	-- + wood-darkest so it punches against the paper fill. Body sits
	-- under the title, wrapped to 2 lines max so cards stay uniform
	-- height; D9's paint path overwrites .Text on both labels per
	-- snapshot.
	local TITLE_Y = 80 + 8
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, TITLE_Y)
	title.Size = UDim2.new(1, 0, 0, 18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextColor3 = COLOR_WOOD_DARKEST
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = ""
	title.ZIndex = card.ZIndex + 1
	title.Parent = card

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.new(0.5, 0, 0, TITLE_Y + 20)
	body.Size = UDim2.new(1, 0, 0, 30)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.Gotham
	body.TextSize = 11
	body.TextColor3 = COLOR_WOOD_DARK
	body.TextXAlignment = Enum.TextXAlignment.Center
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.TextTruncate = Enum.TextTruncate.AtEnd
	body.Text = ""
	body.ZIndex = card.ZIndex + 1
	body.Parent = card

	-- ── Progress bar (D5) ─────────────────────────────────────────────
	-- Pill bar that mirrors OnboardingTooltip's style: wood-dark track,
	-- bright wood-base fill, fully rounded with UICorner using half the
	-- bar height. Sits below the body block; D9's paint path scales
	-- progressFill.Size.X.Scale and overwrites progressLabel.Text.
	local PROGRESS_Y = TITLE_Y + 20 + 30 + 4   -- body bottom + 4
	local PROGRESS_H = 8

	local progressTrack = Instance.new("Frame")
	progressTrack.Name = "ProgressTrack"
	progressTrack.AnchorPoint = Vector2.new(0.5, 0)
	progressTrack.Position = UDim2.new(0.5, 0, 0, PROGRESS_Y)
	progressTrack.Size = UDim2.new(1, 0, 0, PROGRESS_H)
	progressTrack.BackgroundColor3 = COLOR_WOOD_DARK
	progressTrack.BackgroundTransparency = 0.35
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
	progressFill.Size = UDim2.fromScale(0, 1)   -- D9 paints Size.X.Scale
	progressFill.BackgroundColor3 = COLOR_PAPER_LIGHT
	progressFill.BorderSizePixel = 0
	progressFill.ZIndex = progressTrack.ZIndex + 1
	progressFill.Parent = progressTrack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, math.floor(PROGRESS_H / 2))
	fillCorner.Parent = progressFill

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "ProgressLabel"
	progressLabel.AnchorPoint = Vector2.new(0.5, 0)
	progressLabel.Position = UDim2.new(0.5, 0, 0, PROGRESS_Y + PROGRESS_H + 2)
	progressLabel.Size = UDim2.new(1, 0, 0, 12)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Font = Enum.Font.GothamBold
	progressLabel.TextSize = 10
	progressLabel.TextColor3 = COLOR_WOOD_DARK
	progressLabel.TextXAlignment = Enum.TextXAlignment.Center
	progressLabel.Text = ""
	progressLabel.ZIndex = card.ZIndex + 1
	progressLabel.Parent = card

	-- ── Reward row (D6) ───────────────────────────────────────────────
	-- Bottom-anchored. The track button (D7) reserves TRACK_BTN_H at
	-- the very bottom; the reward row + divider stack just above it
	-- with AnchorPoint Y=1 so the layout adapts cleanly even if the
	-- card height changes later. Reward row is icon + count text:
	-- D9's paint path sets rewardIcon.Image + rewardLabel.Text per
	-- snapshot.reward.
	local REWARD_H = 20
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.AnchorPoint = Vector2.new(0.5, 1)
	divider.Position = UDim2.new(0.5, 0, 1, -(TRACK_BTN_H + 6 + REWARD_H + 4))
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.BackgroundColor3 = COLOR_WOOD_DARK
	divider.BackgroundTransparency = 0.55
	divider.BorderSizePixel = 0
	divider.ZIndex = card.ZIndex + 1
	divider.Parent = card

	local rewardRow = Instance.new("Frame")
	rewardRow.Name = "RewardRow"
	rewardRow.AnchorPoint = Vector2.new(0.5, 1)
	rewardRow.Position = UDim2.new(0.5, 0, 1, -(TRACK_BTN_H + 6))
	rewardRow.Size = UDim2.new(1, 0, 0, REWARD_H)
	rewardRow.BackgroundTransparency = 1
	rewardRow.ZIndex = card.ZIndex + 1
	rewardRow.Parent = card

	local rwLayout = Instance.new("UIListLayout")
	rwLayout.FillDirection = Enum.FillDirection.Horizontal
	rwLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rwLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rwLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rwLayout.Padding = UDim.new(0, 4)
	rwLayout.Parent = rewardRow

	local rewardIcon = Instance.new("ImageLabel")
	rewardIcon.Name = "RewardIcon"
	rewardIcon.LayoutOrder = 1
	rewardIcon.Size = UDim2.fromOffset(REWARD_H, REWARD_H)
	rewardIcon.BackgroundTransparency = 1
	rewardIcon.ScaleType = Enum.ScaleType.Fit
	rewardIcon.Image = ""   -- D9 fills from snapshot.reward.icon
	rewardIcon.ZIndex = rewardRow.ZIndex + 1
	rewardIcon.Parent = rewardRow

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "RewardLabel"
	rewardLabel.LayoutOrder = 2
	rewardLabel.Size = UDim2.new(0, 0, 1, 0)
	rewardLabel.AutomaticSize = Enum.AutomaticSize.X
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.TextSize = 12
	rewardLabel.TextColor3 = COLOR_WOOD_DARKEST
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	rewardLabel.TextYAlignment = Enum.TextYAlignment.Center
	rewardLabel.Text = ""
	rewardLabel.ZIndex = rewardRow.ZIndex + 1
	rewardLabel.Parent = rewardRow

	-- ── Track button (D7) ─────────────────────────────────────────────
	-- Full-width button pinned to the bottom of the card. Three states
	-- the paint path (D9) cycles through:
	--   • "Track"        — paper-light fill, default label
	--   • "Tracking"     — wood-dark fill, paper text (active)
	--   • "Claim Reward" — gold-ish wood-base fill, paper text (done)
	-- D7 here only builds the button chrome + a single text label;
	-- state painting + click handlers land in D8/D9.
	local trackBtn = Instance.new("TextButton")
	trackBtn.Name = "TrackBtn"
	trackBtn.AnchorPoint = Vector2.new(0.5, 1)
	trackBtn.Position = UDim2.new(0.5, 0, 1, 0)
	trackBtn.Size = UDim2.new(1, 0, 0, TRACK_BTN_H)
	trackBtn.AutoButtonColor = false
	trackBtn.BackgroundColor3 = COLOR_PAPER_LIGHT
	trackBtn.BorderSizePixel = 0
	trackBtn.Font = Enum.Font.GothamBold
	trackBtn.TextSize = 12
	trackBtn.TextColor3 = COLOR_WOOD_DARKEST
	trackBtn.Text = "Track"
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

	-- ── Click dispatch (D8) ───────────────────────────────────────────
	-- Single click wired here; we read the card's current Mode + QuestId
	-- attributes (set by D9's paint path) at click time so the same
	-- button object can move between Track / Tracking / Claim states
	-- without us re-binding the connection. The server is the source
	-- of truth — every dispatch round-trips back as a 'state' push that
	-- D9 paints, so we intentionally don't optimistically mutate the
	-- card here.
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

	-- refs is the live handle the reactive paint path (D9) updates.
	-- D3-D7 add nodes (iconImage, title, body, progressFill, label,
	-- rewardLabel, trackBtn) into it.
	local refs = {
		card          = card,
		iconBox       = iconBox,
		iconImage     = iconImage,
		title         = title,
		body          = body,
		progressTrack = progressTrack,
		progressFill  = progressFill,
		progressLabel = progressLabel,
		divider       = divider,
		rewardRow     = rewardRow,
		rewardIcon    = rewardIcon,
		rewardLabel   = rewardLabel,
		trackBtn      = trackBtn,
		trackBtnStroke= btnStroke,
	}
	return card, refs
end

local mountPoint = waitForMountPoint(30)
if not mountPoint then
	warn("[QuestsTab] _G.QuestMenuContentPages.quests not available within 30 s; tab disabled")
	return
end
questStateEvent = waitForQuestStateEvent(30)
if not questStateEvent then
	warn("[QuestsTab] QuestState RemoteEvent missing; tab disabled")
	return
end

local scrollFrame = mount(mountPoint)

-- ─── Reactive paint (D9) ────────────────────────────────────────────
-- cardsById keeps live card refs keyed by quest id so each snapshot
-- repaints in place — no full rebuild, no flicker, no lost button-
-- press connections. Cards whose id disappears from a snapshot get
-- :Destroy()-ed; cards that appear for the first time are built once
-- via buildCard and then painted.
local cardsById = {}

local function paintCard(refs, q)
	refs.iconImage.Image = q.icon or ""
	refs.title.Text      = q.title or ""
	refs.body.Text       = q.body or ""

	-- Daily quests are single-objective by design (per QuestCatalog C4).
	-- We sum across objectives anyway so the same paint path can later
	-- handle multi-objective story quests if Phase E reuses it.
	local prog, goal = 0, 0
	for _, obj in ipairs(q.objectives or {}) do
		prog = prog + (tonumber(obj.progress) or 0)
		goal = goal + (tonumber(obj.goal) or 0)
	end
	local pct = (goal > 0) and math.clamp(prog / goal, 0, 1) or 0
	refs.progressFill.Size  = UDim2.new(pct, 0, 1, 0)
	refs.progressLabel.Text = string.format("%d / %d", prog, goal)

	-- Reward row. Without a resource→icon registry on the client we
	-- reuse the quest icon as a stand-in; it still reads as "this is
	-- the reward associated with this quest" because the card layout
	-- groups it under the divider with the count text.
	if q.reward and q.reward.count then
		refs.rewardIcon.Image  = q.icon or ""
		refs.rewardLabel.Text  = "x" .. tostring(q.reward.count)
	else
		refs.rewardIcon.Image  = ""
		refs.rewardLabel.Text  = ""
	end

	refs.card:SetAttribute("QuestId", q.id or "")

	-- Three-mode track button. Attribute set first so the click
	-- handler reads the current mode even if the visual paint races
	-- a click. rewardPending takes priority over tracked because a
	-- quest can be both (objectives done + still flagged tracked) —
	-- the user-facing affordance is "Claim" first.
	if q.rewardPending then
		refs.card:SetAttribute("Mode", "claim")
		refs.trackBtn.Text = "Claim Reward"
		refs.trackBtn.BackgroundColor3 = COLOR_WOOD_BASE
		refs.trackBtn.TextColor3       = COLOR_PAPER_LIGHT
		refs.trackBtnStroke.Color      = COLOR_WOOD_DARKEST
	elseif q.tracked then
		refs.card:SetAttribute("Mode", "tracking")
		refs.trackBtn.Text = "Tracking"
		refs.trackBtn.BackgroundColor3 = COLOR_WOOD_DARK
		refs.trackBtn.TextColor3       = COLOR_PAPER_LIGHT
		refs.trackBtnStroke.Color      = COLOR_WOOD_DARKEST
	else
		refs.card:SetAttribute("Mode", "track")
		refs.trackBtn.Text = "Track"
		refs.trackBtn.BackgroundColor3 = COLOR_PAPER_LIGHT
		refs.trackBtn.TextColor3       = COLOR_WOOD_DARKEST
		refs.trackBtnStroke.Color      = COLOR_WOOD_DARK
	end
end

local function repaint(payload)
	local incoming = {}
	local order = 1
	for _, q in ipairs(payload.quests or {}) do
		if q.kind == "daily" then
			incoming[q.id] = true
			local entry = cardsById[q.id]
			if not entry then
				local card, refs = buildCard(scrollFrame, order)
				entry = { card = card, refs = refs }
				cardsById[q.id] = entry
			else
				entry.card.LayoutOrder = order
			end
			paintCard(entry.refs, q)
			order = order + 1
		end
	end
	-- Sweep any card whose quest dropped out of the snapshot (daily
	-- roll swap, story quest finishing into permanentlyCompleted).
	for id, entry in pairs(cardsById) do
		if not incoming[id] then
			entry.card:Destroy()
			cardsById[id] = nil
		end
	end
end

questStateEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "state" then return end
	if type(payload) ~= "table" then return end
	repaint(payload)
end)

-- Request initial state on mount in case the server's PlayerAdded
-- snapshot fired before this LocalScript was ready.
questStateEvent:FireServer("getState")
