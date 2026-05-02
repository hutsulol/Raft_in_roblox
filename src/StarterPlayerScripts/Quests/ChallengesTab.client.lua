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

	-- ── Progress counter ──────────────────────────────────────────────
	-- The visual progress bar (track + fill) was removed: it added a
	-- lot of descendants for the QuestMenu's open-fade tween to walk,
	-- which produced a visible hitch on first open of the Challenges
	-- tab. The "N / M" counter stays as a compact text-only readout
	-- on the right side of the card, sitting where the bar used to be.
	local PROGRESS_Y = 64
	local ACTION_RESERVE = 140   -- button (120) + 20 px gap
	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "ProgressLabel"
	progressLabel.AnchorPoint = Vector2.new(0, 0)
	progressLabel.Position = UDim2.new(0, 0, 0, PROGRESS_Y + 2)
	progressLabel.Size = UDim2.new(1, -ACTION_RESERVE, 0, 14)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Font = Enum.Font.GothamMedium
	progressLabel.TextSize = 12
	progressLabel.TextColor3 = COLOR_WOOD_DARK
	progressLabel.TextXAlignment = Enum.TextXAlignment.Right
	progressLabel.Text = ""
	progressLabel.ZIndex = card.ZIndex + 1
	progressLabel.Parent = card

	-- ── Timer (F6) ────────────────────────────────────────────────────
	-- Top-right of the card. Reads "0:30" when idle (the catalog
	-- duration), "0:23" while counting down, "Done!" when the player
	-- has hit the goal but not claimed yet. F10 drives the live
	-- countdown via RunService.Heartbeat.
	local timerBox = Instance.new("Frame")
	timerBox.Name = "TimerBox"
	timerBox.AnchorPoint = Vector2.new(1, 0)
	timerBox.Position = UDim2.new(1, 0, 0, 0)
	timerBox.Size = UDim2.fromOffset(76, 36)
	timerBox.BackgroundColor3 = COLOR_PAPER_LIGHT
	timerBox.BackgroundTransparency = 0.25
	timerBox.BorderSizePixel = 0
	timerBox.ZIndex = card.ZIndex + 1
	timerBox.Parent = card
	local tCorner = Instance.new("UICorner")
	tCorner.CornerRadius = UDim.new(0, 8)
	tCorner.Parent = timerBox
	local tStroke = Instance.new("UIStroke")
	tStroke.Color = COLOR_WOOD_DARK
	tStroke.Thickness = 1
	tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tStroke.Parent = timerBox

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	timerLabel.Position = UDim2.fromScale(0.5, 0.5)
	timerLabel.Size = UDim2.fromScale(1, 1)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextSize = 16
	timerLabel.TextColor3 = COLOR_WOOD_DARKEST
	timerLabel.TextXAlignment = Enum.TextXAlignment.Center
	timerLabel.TextYAlignment = Enum.TextYAlignment.Center
	timerLabel.Text = "0:00"
	timerLabel.ZIndex = timerBox.ZIndex + 1
	timerLabel.Parent = timerBox

	-- ── Footer: reward + action button (F7) ───────────────────────────
	-- Reward stays compact on the left (icon + count); action button
	-- on the right cycles Start → Tracking → Claim depending on the
	-- challenge's current state.
	local FOOTER_Y = 90 - 10  -- 80; relative to padded inner area
	local rewardRow = Instance.new("Frame")
	rewardRow.Name = "RewardRow"
	rewardRow.AnchorPoint = Vector2.new(0, 1)
	rewardRow.Position = UDim2.new(0, 0, 1, 0)
	rewardRow.Size = UDim2.new(1, -130, 0, 22)
	rewardRow.BackgroundTransparency = 1
	rewardRow.ZIndex = card.ZIndex + 1
	rewardRow.Parent = card

	local rwLayout = Instance.new("UIListLayout")
	rwLayout.FillDirection = Enum.FillDirection.Horizontal
	rwLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	rwLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rwLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rwLayout.Padding = UDim.new(0, 6)
	rwLayout.Parent = rewardRow

	local rewardCaption = Instance.new("TextLabel")
	rewardCaption.Name = "RewardCaption"
	rewardCaption.LayoutOrder = 1
	rewardCaption.Size = UDim2.fromOffset(50, 22)
	rewardCaption.BackgroundTransparency = 1
	rewardCaption.Font = Enum.Font.Gotham
	rewardCaption.TextSize = 11
	rewardCaption.TextColor3 = COLOR_WOOD_MID
	rewardCaption.TextXAlignment = Enum.TextXAlignment.Left
	rewardCaption.Text = "Reward"
	rewardCaption.ZIndex = rewardRow.ZIndex + 1
	rewardCaption.Parent = rewardRow

	local rewardIcon = Instance.new("ImageLabel")
	rewardIcon.Name = "RewardIcon"
	rewardIcon.LayoutOrder = 2
	rewardIcon.Size = UDim2.fromOffset(22, 22)
	rewardIcon.BackgroundTransparency = 1
	rewardIcon.ScaleType = Enum.ScaleType.Fit
	rewardIcon.Image = ""
	rewardIcon.ZIndex = rewardRow.ZIndex + 1
	rewardIcon.Parent = rewardRow

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "RewardLabel"
	rewardLabel.LayoutOrder = 3
	rewardLabel.Size = UDim2.new(0, 0, 1, 0)
	rewardLabel.AutomaticSize = Enum.AutomaticSize.X
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.TextSize = 14
	rewardLabel.TextColor3 = COLOR_WOOD_DARKEST
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	rewardLabel.TextYAlignment = Enum.TextYAlignment.Center
	rewardLabel.Text = ""
	rewardLabel.ZIndex = rewardRow.ZIndex + 1
	rewardLabel.Parent = rewardRow

	local actionBtn = Instance.new("TextButton")
	actionBtn.Name = "ActionBtn"
	actionBtn.AnchorPoint = Vector2.new(1, 1)
	actionBtn.Position = UDim2.new(1, 0, 1, 0)
	actionBtn.Size = UDim2.fromOffset(120, 30)
	actionBtn.AutoButtonColor = false
	actionBtn.BackgroundColor3 = COLOR_PAPER_LIGHT
	actionBtn.BorderSizePixel = 0
	actionBtn.Font = Enum.Font.GothamBold
	actionBtn.TextSize = 13
	actionBtn.TextColor3 = COLOR_WOOD_DARKEST
	actionBtn.Text = "▶ Start"
	actionBtn.ZIndex = card.ZIndex + 2
	actionBtn.Parent = card
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = actionBtn
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = COLOR_WOOD_DARK
	btnStroke.Thickness = 1.5
	btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	btnStroke.Parent = actionBtn

	-- ── Click dispatch (F8) ───────────────────────────────────────────
	-- Challenges have a 4th mode the daily/story cards don't: "start".
	-- The card defaults to that mode (no startedAt yet); clicking
	-- fires startChallenge which the server handles by stamping
	-- startedAt + auto-tracking. From there it cycles like the others:
	-- Tracking re-click → untrack, Claim → claimReward.
	actionBtn.Activated:Connect(function()
		local id   = card:GetAttribute("QuestId")
		local mode = card:GetAttribute("Mode")
		if type(id) ~= "string" or id == "" then return end
		if not questStateEvent then return end
		if mode == "start" then
			questStateEvent:FireServer("startChallenge", id)
		elseif mode == "tracking" then
			questStateEvent:FireServer("untrack", id)
		elseif mode == "claim" then
			questStateEvent:FireServer("claimReward", id)
		end
	end)

	local refs = {
		card           = card,
		iconImage      = iconImage,
		title          = title,
		body           = body,
		progressLabel  = progressLabel,
		timerBox       = timerBox,
		timerLabel     = timerLabel,
		rewardCaption  = rewardCaption,
		rewardIcon     = rewardIcon,
		rewardLabel    = rewardLabel,
		actionBtn      = actionBtn,
		actionBtnStroke= btnStroke,
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

-- ─── Empty state (F10) ──────────────────────────────────────────────
-- Sibling of the scroll so the UIListLayout doesn't treat it as a
-- card. Visible when no challenges live in the snapshot — only fires
-- if the catalog server-side returns nothing or fails to load.
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
emptyState.Text = "No challenges available right now."
emptyState.Visible = false
emptyState.ZIndex = 6
emptyState.Parent = mountPoint

-- ─── Reactive paint (F9) ────────────────────────────────────────────
-- Stash the latest challenge snapshot per quest id so the live
-- countdown loop (F10) can advance the timer locally between server
-- pushes without waiting for another snapshot.
local cardsById = {}     -- [questId] = { card, refs, q (last snapshot) }

local function fmtSeconds(secs)
	secs = math.max(0, math.floor(secs + 0.5))
	local m = math.floor(secs / 60)
	local s = secs % 60
	return string.format("%d:%02d", m, s)
end

local function paintMode(refs, mode)
	if mode == "claim" then
		refs.card:SetAttribute("Mode", "claim")
		refs.actionBtn.Text = "★ Claim"
		refs.actionBtn.BackgroundColor3 = COLOR_WOOD_BASE
		refs.actionBtn.TextColor3       = COLOR_PAPER_LIGHT
		refs.actionBtnStroke.Color      = COLOR_WOOD_DARKEST
	elseif mode == "tracking" then
		refs.card:SetAttribute("Mode", "tracking")
		refs.actionBtn.Text = "● Tracking"
		refs.actionBtn.BackgroundColor3 = COLOR_WOOD_DARK
		refs.actionBtn.TextColor3       = COLOR_PAPER_LIGHT
		refs.actionBtnStroke.Color      = COLOR_WOOD_DARKEST
	else   -- "start"
		refs.card:SetAttribute("Mode", "start")
		refs.actionBtn.Text = "▶ Start"
		refs.actionBtn.BackgroundColor3 = COLOR_PAPER_LIGHT
		refs.actionBtn.TextColor3       = COLOR_WOOD_DARKEST
		refs.actionBtnStroke.Color      = COLOR_WOOD_DARK
	end
end

local function paintCard(refs, q)
	refs.iconImage.Image = q.icon or ""
	refs.title.Text      = q.title or ""
	refs.body.Text       = q.body or ""

	local prog, goal = 0, 0
	for _, obj in ipairs(q.objectives or {}) do
		prog = prog + (tonumber(obj.progress) or 0)
		goal = goal + (tonumber(obj.goal) or 0)
	end
	refs.progressLabel.Text = string.format("%d / %d", prog, goal)

	if q.reward and q.reward.count then
		refs.rewardIcon.Image = q.icon or ""
		refs.rewardLabel.Text = "x" .. tostring(q.reward.count)
	else
		refs.rewardIcon.Image = ""
		refs.rewardLabel.Text = ""
	end

	refs.card:SetAttribute("QuestId", q.id or "")

	-- Mode + timer wiring. Three states the player sees:
	--   • Idle (no startedAt): button = Start, timer shows duration
	--   • Running (startedAt set, secondsRemaining > 0, not claimable):
	--     button = Tracking, timer counts down (F10 advances it live)
	--   • Done (rewardPending): button = Claim, timer shows "Done!"
	if q.rewardPending then
		paintMode(refs, "claim")
		refs.timerLabel.Text       = "Done!"
		refs.timerLabel.TextColor3 = COLOR_WOOD_DARKEST
	elseif q.startedAt then
		paintMode(refs, "tracking")
		local remaining = q.secondsRemaining or q.durationSec or 0
		refs.timerLabel.Text       = fmtSeconds(remaining)
		refs.timerLabel.TextColor3 = COLOR_TIMER
	else
		paintMode(refs, "start")
		refs.timerLabel.Text       = fmtSeconds(q.durationSec or 0)
		refs.timerLabel.TextColor3 = COLOR_WOOD_DARKEST
	end
end

local function repaint(payload)
	local incoming = {}
	local order = 1
	for _, q in ipairs(payload.quests or {}) do
		if q.kind == "challenge" then
			incoming[q.id] = true
			local entry = cardsById[q.id]
			if not entry then
				local card, refs = buildCard(scrollFrame, order)
				entry = { card = card, refs = refs }
				cardsById[q.id] = entry
			else
				entry.card.LayoutOrder = order
			end
			-- Stash the snapshot so the heartbeat tick (F10) can
			-- advance the visible timer between server pushes.
			entry.q = q
			-- Pre-compute a client-side absolute deadline so the
			-- live tick subtracts from os.clock() instead of os.time()
			-- and we don't drift on long-running sessions.
			if q.startedAt and q.secondsRemaining then
				entry.deadline = os.clock() + q.secondsRemaining
			else
				entry.deadline = nil
			end
			paintCard(entry.refs, q)
			order = order + 1
		end
	end
	for id, entry in pairs(cardsById) do
		if not incoming[id] then
			entry.card:Destroy()
			cardsById[id] = nil
		end
	end

	emptyState.Visible = (next(cardsById) == nil)
end

questStateEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "state" then return end
	if type(payload) ~= "table" then return end
	repaint(payload)
end)

-- ─── Live countdown loop ────────────────────────────────────────────
-- Re-renders the timer label off the cached deadline every frame
-- (cheap — a 4-card Heartbeat at 60Hz is ~240 string formats/sec).
-- When a running challenge hits 0 we ping the server with getState
-- so its expiry sweep snaps the card back to "Start". A small
-- debounce (justExpired) keeps us from spamming the RemoteEvent
-- while waiting for the server's snapshot to arrive.
local justExpired = {}
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for id, entry in pairs(cardsById) do
		local q = entry.q
		if q and q.startedAt and not q.rewardPending and entry.deadline then
			local remaining = entry.deadline - now
			if remaining <= 0 then
				entry.refs.timerLabel.Text = "0:00"
				if not justExpired[id] then
					justExpired[id] = true
					-- Server's expiry sweep flips startedAt → nil on
					-- the next snapshot; we just nudge it.
					if questStateEvent then
						questStateEvent:FireServer("getState")
					end
				end
			else
				entry.refs.timerLabel.Text = fmtSeconds(remaining)
				justExpired[id] = nil
			end
		else
			justExpired[id] = nil
		end
	end
end)
