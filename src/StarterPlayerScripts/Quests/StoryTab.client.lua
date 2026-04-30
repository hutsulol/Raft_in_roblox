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
local OBJ_ROW_H    = 32
local OBJ_BAR_H    = 4
local function buildObjectiveRow(parent, layoutOrder)
	local row = Instance.new("Frame")
	row.Name = "ObjectiveRow"
	row.LayoutOrder = layoutOrder or 0
	row.Size = UDim2.new(1, 0, 0, OBJ_ROW_H)
	row.BackgroundColor3 = COLOR_PAPER_LIGHT
	row.BackgroundTransparency = 0.35
	row.BorderSizePixel = 0
	row.ZIndex = 8
	row.Parent = parent

	local rCorner = Instance.new("UICorner")
	rCorner.CornerRadius = UDim.new(0, 6)
	rCorner.Parent = row

	local rPad = Instance.new("UIPadding")
	rPad.PaddingTop    = UDim.new(0, 4)
	rPad.PaddingBottom = UDim.new(0, 4)
	rPad.PaddingLeft   = UDim.new(0, 8)
	rPad.PaddingRight  = UDim.new(0, 8)
	rPad.Parent = row

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0, 0)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.Size = UDim2.new(1, -50, 0, 14)
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

	-- Progress bar pinned to the bottom of the row.
	local barTrack = Instance.new("Frame")
	barTrack.Name = "BarTrack"
	barTrack.AnchorPoint = Vector2.new(0, 1)
	barTrack.Position = UDim2.new(0, 0, 1, 0)
	barTrack.Size = UDim2.new(1, 0, 0, OBJ_BAR_H)
	barTrack.BackgroundColor3 = COLOR_WOOD_DARK
	barTrack.BackgroundTransparency = 0.6
	barTrack.BorderSizePixel = 0
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
		row     = row,
		label   = label,
		count   = count,
		barFill = barFill,
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

	-- ── Objectives list container (E5) ────────────────────────────────
	-- Holds one Frame per objective (built in E6). UIListLayout stacks
	-- them vertically; AutomaticSize.Y lets the container grow with
	-- the row count so a 4-objective story takes more vertical room
	-- than a 3-objective one. The list itself doesn't get a background
	-- — each row will have its own subtle paper-light fill.
	local objList = Instance.new("Frame")
	objList.Name = "Objectives"
	objList.LayoutOrder = 2
	objList.Size = UDim2.new(1, 0, 0, 0)
	objList.AutomaticSize = Enum.AutomaticSize.Y
	objList.BackgroundTransparency = 1
	objList.ZIndex = card.ZIndex + 1
	objList.Parent = card

	local objLayout = Instance.new("UIListLayout")
	objLayout.FillDirection = Enum.FillDirection.Vertical
	objLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	objLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	objLayout.SortOrder = Enum.SortOrder.LayoutOrder
	objLayout.Padding = UDim.new(0, 6)
	objLayout.Parent = objList

	-- ── Footer: reward row + track button (E7) ────────────────────────
	-- Reward block on the left ("Reward" caption + icon + count text),
	-- track button on the right at fixed width. The button cycles
	-- through Track / Tracking / Claim Reward states the same way the
	-- daily cards do; E8 wires the click and E9 paints the visuals.
	local FOOTER_H = 36
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.LayoutOrder = 3
	footer.Size = UDim2.new(1, 0, 0, FOOTER_H)
	footer.BackgroundTransparency = 1
	footer.ZIndex = card.ZIndex + 1
	footer.Parent = card

	local rewardBlock = Instance.new("Frame")
	rewardBlock.Name = "Reward"
	rewardBlock.AnchorPoint = Vector2.new(0, 0.5)
	rewardBlock.Position = UDim2.new(0, 0, 0.5, 0)
	rewardBlock.Size = UDim2.new(1, -140, 1, 0)   -- leaves 140 px for the button
	rewardBlock.BackgroundTransparency = 1
	rewardBlock.ZIndex = footer.ZIndex + 1
	rewardBlock.Parent = footer

	local rewardCaption = Instance.new("TextLabel")
	rewardCaption.Name = "RewardCaption"
	rewardCaption.AnchorPoint = Vector2.new(0, 0)
	rewardCaption.Position = UDim2.new(0, 0, 0, 0)
	rewardCaption.Size = UDim2.new(1, 0, 0, 12)
	rewardCaption.BackgroundTransparency = 1
	rewardCaption.Font = Enum.Font.Gotham
	rewardCaption.TextSize = 11
	rewardCaption.TextColor3 = COLOR_WOOD_MID
	rewardCaption.TextXAlignment = Enum.TextXAlignment.Left
	rewardCaption.Text = "Reward"
	rewardCaption.ZIndex = rewardBlock.ZIndex + 1
	rewardCaption.Parent = rewardBlock

	local rewardRow = Instance.new("Frame")
	rewardRow.Name = "RewardRow"
	rewardRow.AnchorPoint = Vector2.new(0, 1)
	rewardRow.Position = UDim2.new(0, 0, 1, 0)
	rewardRow.Size = UDim2.new(1, 0, 0, 22)
	rewardRow.BackgroundTransparency = 1
	rewardRow.ZIndex = rewardBlock.ZIndex + 1
	rewardRow.Parent = rewardBlock

	local rwLayout = Instance.new("UIListLayout")
	rwLayout.FillDirection = Enum.FillDirection.Horizontal
	rwLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	rwLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rwLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rwLayout.Padding = UDim.new(0, 6)
	rwLayout.Parent = rewardRow

	local rewardIcon = Instance.new("ImageLabel")
	rewardIcon.Name = "RewardIcon"
	rewardIcon.LayoutOrder = 1
	rewardIcon.Size = UDim2.fromOffset(22, 22)
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
	rewardLabel.TextSize = 14
	rewardLabel.TextColor3 = COLOR_WOOD_DARKEST
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	rewardLabel.TextYAlignment = Enum.TextYAlignment.Center
	rewardLabel.Text = ""
	rewardLabel.ZIndex = rewardRow.ZIndex + 1
	rewardLabel.Parent = rewardRow

	local trackBtn = Instance.new("TextButton")
	trackBtn.Name = "TrackBtn"
	trackBtn.AnchorPoint = Vector2.new(1, 0.5)
	trackBtn.Position = UDim2.new(1, 0, 0.5, 0)
	trackBtn.Size = UDim2.fromOffset(130, FOOTER_H)
	trackBtn.AutoButtonColor = false
	trackBtn.BackgroundColor3 = COLOR_PAPER_LIGHT
	trackBtn.BorderSizePixel = 0
	trackBtn.Font = Enum.Font.GothamBold
	trackBtn.TextSize = 14
	trackBtn.TextColor3 = COLOR_WOOD_DARKEST
	trackBtn.Text = "★ Track"
	trackBtn.ZIndex = footer.ZIndex + 2
	trackBtn.Parent = footer
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
		body           = body,
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
		-- Once an objective is done, dim its label slightly so the
		-- player can scan which steps remain at a glance.
		if pct >= 1 then
			row.label.TextColor3 = COLOR_WOOD_MID
		else
			row.label.TextColor3 = COLOR_WOOD_DARKEST
		end
	end
	-- Trim any leftover rows from a previous repaint with more objectives.
	for i = #objs + 1, #refs.objRows do
		refs.objRows[i].row:Destroy()
		refs.objRows[i] = nil
	end

	-- Reward — same icon-as-stand-in approach as the daily cards.
	if q.reward and q.reward.count then
		refs.rewardIcon.Image = q.icon or ""
		refs.rewardLabel.Text = "x" .. tostring(q.reward.count)
	else
		refs.rewardIcon.Image = ""
		refs.rewardLabel.Text = ""
	end

	refs.card:SetAttribute("QuestId", q.id or "")

	-- Three-mode track button — same priority as daily: rewardPending
	-- beats tracked beats default, because "Claim" is the action the
	-- player should take next.
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
		if q.kind == "story" then
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
	-- Sweep cards for stories that have flipped into permanentlyCompleted
	-- (they drop out of the snapshot once finished).
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

-- The Quests tab also fires getState on mount; we don't fire again
-- here because both tabs receive the same broadcast.
