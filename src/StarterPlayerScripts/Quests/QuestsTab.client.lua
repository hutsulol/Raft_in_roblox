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

-- ─── Mount + horizontal row container ───────────────────────────────
-- Four daily quest cards laid out in a single horizontal row across
-- the content area. UIListLayout.Horizontal handles the spacing so
-- removing a card (when the player claims one daily) collapses the
-- remaining cards toward the left without leaving a gap. Card width
-- + gap math is sized against the QuestMenu's content area:
--   PANEL_W (720) - TAB_RAIL_W (130) - CONTENT_GAP (12) = 578
--   578 - 2*QUESTS_TAB_PAD (24) - 3*CARD_GAP (30) = 524
--   524 / 4 = 131 → CARD_W = 130 leaves a 4 px slack
local QUESTS_TAB_PAD = 12
local CARD_W         = 130
local CARD_H         = 260   -- vertical UIListLayout inside; sized to fit
                              -- icon + title + body + bar + reward + button
local CARD_GAP       = 10

local function mount(parent)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "QuestsScroll"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 0   -- 4 cards fit in one row; no scroll
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 6
	scroll.Parent = parent

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, QUESTS_TAB_PAD)
	pad.PaddingBottom = UDim.new(0, QUESTS_TAB_PAD)
	pad.PaddingLeft   = UDim.new(0, QUESTS_TAB_PAD)
	pad.PaddingRight  = UDim.new(0, QUESTS_TAB_PAD)
	pad.Parent = scroll

	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Left
	row.VerticalAlignment = Enum.VerticalAlignment.Top
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, CARD_GAP)
	row.Parent = scroll

	return scroll
end

-- ─── Single quest card ──────────────────────────────────────────────
-- Returns the outer card Frame plus a refs table the reactive paint
-- path updates. Layout uses a vertical UIListLayout so the rows
-- (icon → title → body → progress → reward → button) stack with
-- consistent gaps regardless of dynamic content (e.g. wrapped body
-- text adding a line, progress bar showing/hiding the count label).
local function buildCard(parent, layoutOrder)
	local card = Instance.new("Frame")
	card.Name = "QuestCard"
	card.LayoutOrder = layoutOrder or 0
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundColor3 = COLOR_PAPER
	card.BorderSizePixel = 0
	card.ZIndex = 7
	card.Parent = parent
	-- Card attributes drive the click handler dispatch. The paint path
	-- overwrites these per snapshot:
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

	local cLayout = Instance.new("UIListLayout")
	cLayout.FillDirection = Enum.FillDirection.Vertical
	cLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	cLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cLayout.Padding = UDim.new(0, 4)
	cLayout.Parent = card

	-- ── Icon (top, decorative) ────────────────────────────────────────
	-- Compact 44×44 icon at the top of the card — no surrounding frame
	-- since the catalog icons already have their own background.
	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "Icon"
	iconImage.LayoutOrder = 1
	iconImage.Size = UDim2.fromOffset(44, 44)
	iconImage.BackgroundTransparency = 1
	iconImage.BorderSizePixel = 0
	iconImage.ScaleType = Enum.ScaleType.Fit
	iconImage.Image = ""
	iconImage.ZIndex = card.ZIndex + 1
	iconImage.Parent = card

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 2
	title.Size = UDim2.new(1, 0, 0, 18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextColor3 = COLOR_WOOD_DARKEST
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = ""
	title.ZIndex = card.ZIndex + 1
	title.Parent = card

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.LayoutOrder = 3
	body.Size = UDim2.new(1, 0, 0, 28)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.Gotham
	body.TextSize = 10
	body.TextColor3 = COLOR_WOOD_DARK
	body.TextXAlignment = Enum.TextXAlignment.Center
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.TextTruncate = Enum.TextTruncate.AtEnd
	body.Text = ""
	body.ZIndex = card.ZIndex + 1
	body.Parent = card

	-- ── Progress bar ──────────────────────────────────────────────────
	local PROGRESS_H = 6
	local progressTrack = Instance.new("Frame")
	progressTrack.Name = "ProgressTrack"
	progressTrack.LayoutOrder = 4
	progressTrack.Size = UDim2.new(1, -8, 0, PROGRESS_H)
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
	progressFill.BackgroundColor3 = Color3.fromRGB(126, 175, 90)   -- pale green to match target
	progressFill.BorderSizePixel = 0
	progressFill.ZIndex = progressTrack.ZIndex + 1
	progressFill.Parent = progressTrack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, math.floor(PROGRESS_H / 2))
	fillCorner.Parent = progressFill

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "ProgressLabel"
	progressLabel.LayoutOrder = 5
	progressLabel.Size = UDim2.new(1, 0, 0, 11)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Font = Enum.Font.GothamMedium
	progressLabel.TextSize = 10
	progressLabel.TextColor3 = COLOR_WOOD_DARK
	progressLabel.TextXAlignment = Enum.TextXAlignment.Center
	progressLabel.Text = ""
	progressLabel.ZIndex = card.ZIndex + 1
	progressLabel.Parent = card

	-- ── Reward (caption + icon + count) ───────────────────────────────
	-- "Reward" caption above the icon+count row. Matches the target
	-- design where each card calls out the reward as its own labelled
	-- mini-section, not just an inline row.
	local rewardCaption = Instance.new("TextLabel")
	rewardCaption.Name = "RewardCaption"
	rewardCaption.LayoutOrder = 6
	rewardCaption.Size = UDim2.new(1, 0, 0, 12)
	rewardCaption.BackgroundTransparency = 1
	rewardCaption.Font = Enum.Font.Gotham
	rewardCaption.TextSize = 10
	rewardCaption.TextColor3 = COLOR_WOOD_MID
	rewardCaption.TextXAlignment = Enum.TextXAlignment.Center
	rewardCaption.Text = "Reward"
	rewardCaption.ZIndex = card.ZIndex + 1
	rewardCaption.Parent = card

	local rewardRow = Instance.new("Frame")
	rewardRow.Name = "RewardRow"
	rewardRow.LayoutOrder = 7
	rewardRow.Size = UDim2.new(1, 0, 0, 22)
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
	rewardIcon.Size = UDim2.fromOffset(20, 20)
	rewardIcon.BackgroundTransparency = 1
	rewardIcon.ScaleType = Enum.ScaleType.Fit
	rewardIcon.Image = ""
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

	-- ── Track button ──────────────────────────────────────────────────
	-- Star + label per the target design. Three states the paint path
	-- cycles through:
	--   • Track        — paper-light fill (default)
	--   • Tracking     — wood-dark fill, paper text (active)
	--   • Claim Reward — wood-base fill, paper text (claimable)
	local TRACK_BTN_H = 26
	local trackBtn = Instance.new("TextButton")
	trackBtn.Name = "TrackBtn"
	trackBtn.LayoutOrder = 8
	trackBtn.Size = UDim2.new(1, 0, 0, TRACK_BTN_H)
	trackBtn.AutoButtonColor = false
	trackBtn.BackgroundColor3 = COLOR_PAPER_LIGHT
	trackBtn.BorderSizePixel = 0
	trackBtn.Font = Enum.Font.GothamBold
	trackBtn.TextSize = 12
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

	-- Click dispatch — same connection drives all 3 modes; we read
	-- the card's current Mode attribute at click time so the paint
	-- path can swap modes without us re-binding.
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
		body           = body,
		progressTrack  = progressTrack,
		progressFill   = progressFill,
		progressLabel  = progressLabel,
		rewardCaption  = rewardCaption,
		rewardRow      = rewardRow,
		rewardIcon     = rewardIcon,
		rewardLabel    = rewardLabel,
		trackBtn       = trackBtn,
		trackBtnStroke = btnStroke,
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

-- ─── Empty state (D10) ──────────────────────────────────────────────
-- Sits as a sibling of the scroll frame so the UIGridLayout inside
-- the scroll frame doesn't try to lay it out as a card. Hidden by
-- default; D9's repaint flips Visible based on whether any daily
-- cards remain after the snapshot has been processed. Catches three
-- defensive cases:
--   1. Daily roll legitimately returned 0 (every daily is in the
--      player's permanentlyCompleted set — possible after long-term
--      progression once single-use crafting gates are exhausted).
--   2. The catalog never loaded server-side, so the snapshot is empty.
--   3. First-frame race where the snapshot hasn't arrived yet.
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
emptyState.Text = "No daily quests right now.\nCheck back tomorrow."
emptyState.Visible = false
emptyState.ZIndex = 6
emptyState.Parent = mountPoint

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
		refs.trackBtn.Text = "★ Claim"
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

	-- D10: flip the empty-state label after the sweep so it only
	-- shows when there are no live cards.
	emptyState.Visible = (next(cardsById) == nil)
end

questStateEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "state" then return end
	if type(payload) ~= "table" then return end
	repaint(payload)
end)

-- Request initial state on mount in case the server's PlayerAdded
-- snapshot fired before this LocalScript was ready.
questStateEvent:FireServer("getState")
