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

-- ─── Relative-time formatter (G3) ───────────────────────────────────
-- Server stamps completedAt as os.time() seconds. Convert to a
-- human-readable "x ago" string. Anything beyond a week falls back
-- to a date so a year-old entry doesn't read "52 weeks ago".
local function relativeTime(completedAt)
	if type(completedAt) ~= "number" or completedAt <= 0 then
		return ""
	end
	local now = os.time()
	local secs = math.max(0, now - completedAt)
	if secs < 60 then
		return "just now"
	elseif secs < 3600 then
		local m = math.floor(secs / 60)
		return m == 1 and "1 minute ago" or (m .. " minutes ago")
	elseif secs < 86400 then
		local h = math.floor(secs / 3600)
		return h == 1 and "1 hour ago" or (h .. " hours ago")
	elseif secs < 7 * 86400 then
		local d = math.floor(secs / 86400)
		return d == 1 and "yesterday" or (d .. " days ago")
	else
		return os.date("%b %d", completedAt)
	end
end

-- ─── Single history row (G2) ────────────────────────────────────────
-- Compact horizontal layout: icon on the left, title + relative
-- timestamp stacked in the middle, reward on the right. Returned
-- refs let G4's paint path overwrite text + image without rebuilding.
local ROW_HEIGHT = 44
local function buildRow(parent, layoutOrder)
	local row = Instance.new("Frame")
	row.Name = "HistoryRow"
	row.LayoutOrder = layoutOrder or 0
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = COLOR_PAPER_LIGHT
	row.BackgroundTransparency = 0.35
	row.BorderSizePixel = 0
	row.ZIndex = 7
	row.Parent = parent

	local rCorner = Instance.new("UICorner")
	rCorner.CornerRadius = UDim.new(0, 8)
	rCorner.Parent = row

	local rPad = Instance.new("UIPadding")
	rPad.PaddingTop    = UDim.new(0, 6)
	rPad.PaddingBottom = UDim.new(0, 6)
	rPad.PaddingLeft   = UDim.new(0, 8)
	rPad.PaddingRight  = UDim.new(0, 8)
	rPad.Parent = row

	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "Icon"
	iconImage.AnchorPoint = Vector2.new(0, 0.5)
	iconImage.Position = UDim2.new(0, 0, 0.5, 0)
	iconImage.Size = UDim2.fromOffset(32, 32)
	iconImage.BackgroundTransparency = 1
	iconImage.ScaleType = Enum.ScaleType.Fit
	iconImage.Image = ""
	iconImage.ZIndex = row.ZIndex + 1
	iconImage.Parent = row

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0, 0)
	title.Position = UDim2.new(0, 40, 0, 0)
	title.Size = UDim2.new(1, -40 - 110, 0, 18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextColor3 = COLOR_WOOD_DARKEST
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = ""
	title.ZIndex = row.ZIndex + 1
	title.Parent = row

	local timestamp = Instance.new("TextLabel")
	timestamp.Name = "Timestamp"
	timestamp.AnchorPoint = Vector2.new(0, 1)
	timestamp.Position = UDim2.new(0, 40, 1, 0)
	timestamp.Size = UDim2.new(1, -40 - 110, 0, 12)
	timestamp.BackgroundTransparency = 1
	timestamp.Font = Enum.Font.Gotham
	timestamp.TextSize = 11
	timestamp.TextColor3 = COLOR_WOOD_MID
	timestamp.TextXAlignment = Enum.TextXAlignment.Left
	timestamp.TextYAlignment = Enum.TextYAlignment.Center
	timestamp.Text = ""
	timestamp.ZIndex = row.ZIndex + 1
	timestamp.Parent = row

	local reward = Instance.new("TextLabel")
	reward.Name = "Reward"
	reward.AnchorPoint = Vector2.new(1, 0.5)
	reward.Position = UDim2.new(1, 0, 0.5, 0)
	reward.Size = UDim2.new(0, 105, 1, 0)
	reward.BackgroundTransparency = 1
	reward.Font = Enum.Font.GothamBold
	reward.TextSize = 13
	reward.TextColor3 = COLOR_WOOD_DARK
	reward.TextXAlignment = Enum.TextXAlignment.Right
	reward.TextYAlignment = Enum.TextYAlignment.Center
	reward.Text = ""
	reward.ZIndex = row.ZIndex + 1
	reward.Parent = row

	return {
		row       = row,
		iconImage = iconImage,
		title     = title,
		timestamp = timestamp,
		reward    = reward,
	}
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

-- ─── Reactive paint (G4) ────────────────────────────────────────────
-- History is a positional list (newest first), not keyed by id —
-- the same quest id can recur if the player completes a daily on
-- multiple days. We reuse rows by index so a refreshed snapshot
-- repaints in place: rows that already exist get new text/icon,
-- extra rows get built once, leftover rows get destroyed.
local rowsByIndex = {}

local function repaint(payload)
	local hist = payload.historyLog or {}
	for i, entry in ipairs(hist) do
		local row = rowsByIndex[i]
		if not row then
			row = buildRow(scrollFrame, i)
			rowsByIndex[i] = row
		else
			row.row.LayoutOrder = i
		end
		row.iconImage.Image = entry.icon or ""
		row.title.Text      = entry.title or entry.id or "Quest"
		row.timestamp.Text  = relativeTime(entry.completedAt)
		if entry.reward and entry.reward.count then
			row.reward.Text = "+" .. tostring(entry.reward.count)
		else
			row.reward.Text = ""
		end
	end
	-- Drop any rows past the current history length.
	for i = #hist + 1, #rowsByIndex do
		rowsByIndex[i].row:Destroy()
		rowsByIndex[i] = nil
	end
end

questStateEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "state" then return end
	if type(payload) ~= "table" then return end
	repaint(payload)
end)
