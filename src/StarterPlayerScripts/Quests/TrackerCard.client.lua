-- TrackerCard.client.lua
-- The always-on HUD card in the top-right that shows the currently
-- tracked quest. Built across H1 → H6:
--
--   H1 (this commit): ScreenGui + container Frame anchored top-right.
--   H2: card chrome (paper fill, wood-dark stroke, rounded corners).
--   H3: card content (icon + title + objective + progress bar + timer).
--   H4: reactive paint — find q.tracked == true in the QuestState snapshot.
--   H5: live tick for tracked challenges (RunService.Heartbeat).
--   H6: click-to-open-QuestMenu + slide-in/out animations.
--
-- The card is fed by the same QuestState RemoteEvent the in-menu
-- tabs use, so tracking from any tab updates the HUD without an
-- extra round-trip.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local localPlayer = Players.LocalPlayer

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

-- ─── ScreenGui + anchor (H1) ────────────────────────────────────────
-- Pinned to the top-right corner with IgnoreGuiInset = true so the
-- card sits in the same band as the rest of the HUD (above CoreGui's
-- top inset). Two-frame structure: outer ScreenGui owns input layer,
-- container Frame is sized to fit the card so animations/visibility
-- toggles affect the whole thing without leaking into HUD geometry.
local TRACKER_W = 240
local TRACKER_H = 110
local TRACKER_MARGIN = 16

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QuestTrackerGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 80   -- below QuestMenu (110) + entry button (90) + phone (200)
screenGui.Enabled = false      -- H4 enables once a tracked quest exists
screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

local container = Instance.new("Frame")
container.Name = "Tracker"
container.AnchorPoint = Vector2.new(1, 0)
container.Position = UDim2.new(1, -TRACKER_MARGIN, 0, TRACKER_MARGIN + 36)
-- ↑ +36 keeps us clear of the Roblox top bar / coreGui chrome.
container.Size = UDim2.fromOffset(TRACKER_W, TRACKER_H)
container.BackgroundTransparency = 1
container.BorderSizePixel = 0
container.Parent = screenGui

-- ─── Card chrome (H2) ───────────────────────────────────────────────
-- Same wood/paper palette as the menu cards so the tracker reads as
-- "this is a quest UI". The card is a TextButton (not a Frame) so
-- H6 can wire the click-to-open-menu action to the whole surface
-- without a fragile MouseButton1 hit on a child object.
local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_WOOD_DARK    = Color3.fromRGB( 91,  58,  34)
local COLOR_WOOD_MID     = Color3.fromRGB(138, 106,  68)
local COLOR_WOOD_BASE    = Color3.fromRGB(176, 138,  92)
local COLOR_PAPER        = Color3.fromRGB(233, 217, 184)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(243, 230, 204)
local COLOR_PROGRESS     = Color3.fromRGB(126, 175,  90)
local COLOR_TIMER        = Color3.fromRGB(178,  79,  64)

local card = Instance.new("TextButton")
card.Name = "Card"
card.AutoButtonColor = false
card.Size = UDim2.fromScale(1, 1)
card.BackgroundColor3 = COLOR_PAPER
card.BackgroundTransparency = 0.05
card.BorderSizePixel = 0
card.Text = ""   -- click target only, no text on the button itself
card.ZIndex = 1
card.Parent = container

local cCorner = Instance.new("UICorner")
cCorner.CornerRadius = UDim.new(0, 10)
cCorner.Parent = card

local cStroke = Instance.new("UIStroke")
cStroke.Color = COLOR_WOOD_DARK
cStroke.Thickness = 2
cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
cStroke.Parent = card

local cPad = Instance.new("UIPadding")
cPad.PaddingTop    = UDim.new(0, 8)
cPad.PaddingBottom = UDim.new(0, 8)
cPad.PaddingLeft   = UDim.new(0, 10)
cPad.PaddingRight  = UDim.new(0, 10)
cPad.Parent = card

-- ─── Card content (H3) ──────────────────────────────────────────────
-- Top row: icon (left) + title (center) + tiny timer label (right,
-- only visible when tracking a challenge).
-- Bottom row: objective label + progress bar + N/M.
local iconImage = Instance.new("ImageLabel")
iconImage.Name = "Icon"
iconImage.AnchorPoint = Vector2.new(0, 0)
iconImage.Position = UDim2.new(0, 0, 0, 0)
iconImage.Size = UDim2.fromOffset(36, 36)
iconImage.BackgroundTransparency = 1
iconImage.ScaleType = Enum.ScaleType.Fit
iconImage.Image = ""
iconImage.ZIndex = card.ZIndex + 1
iconImage.Parent = card

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0, 0)
title.Position = UDim2.new(0, 44, 0, 0)
title.Size = UDim2.new(1, -44 - 60, 0, 18)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = COLOR_WOOD_DARKEST
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextYAlignment = Enum.TextYAlignment.Center
title.TextTruncate = Enum.TextTruncate.AtEnd
title.Text = ""
title.ZIndex = card.ZIndex + 1
title.Parent = card

local objective = Instance.new("TextLabel")
objective.Name = "Objective"
objective.AnchorPoint = Vector2.new(0, 0)
objective.Position = UDim2.new(0, 44, 0, 18)
objective.Size = UDim2.new(1, -44 - 60, 0, 16)
objective.BackgroundTransparency = 1
objective.Font = Enum.Font.Gotham
objective.TextSize = 11
objective.TextColor3 = COLOR_WOOD_MID
objective.TextXAlignment = Enum.TextXAlignment.Left
objective.TextYAlignment = Enum.TextYAlignment.Center
objective.TextTruncate = Enum.TextTruncate.AtEnd
objective.Text = ""
objective.ZIndex = card.ZIndex + 1
objective.Parent = card

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "TimerLabel"
timerLabel.AnchorPoint = Vector2.new(1, 0)
timerLabel.Position = UDim2.new(1, 0, 0, 2)
timerLabel.Size = UDim2.fromOffset(60, 18)
timerLabel.BackgroundTransparency = 1
timerLabel.Font = Enum.Font.GothamBold
timerLabel.TextSize = 14
timerLabel.TextColor3 = COLOR_TIMER
timerLabel.TextXAlignment = Enum.TextXAlignment.Right
timerLabel.TextYAlignment = Enum.TextYAlignment.Center
timerLabel.Text = ""
timerLabel.Visible = false
timerLabel.ZIndex = card.ZIndex + 1
timerLabel.Parent = card

local PROGRESS_H = 8
local progressTrack = Instance.new("Frame")
progressTrack.Name = "ProgressTrack"
progressTrack.AnchorPoint = Vector2.new(0, 1)
progressTrack.Position = UDim2.new(0, 0, 1, -16)
progressTrack.Size = UDim2.new(1, 0, 0, PROGRESS_H)
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
progressFill.BackgroundColor3 = COLOR_PROGRESS
progressFill.BorderSizePixel = 0
progressFill.ZIndex = progressTrack.ZIndex + 1
progressFill.Parent = progressTrack
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, math.floor(PROGRESS_H / 2))
fillCorner.Parent = progressFill

local progressLabel = Instance.new("TextLabel")
progressLabel.Name = "ProgressLabel"
progressLabel.AnchorPoint = Vector2.new(1, 1)
progressLabel.Position = UDim2.new(1, 0, 1, 0)
progressLabel.Size = UDim2.new(1, 0, 0, 12)
progressLabel.BackgroundTransparency = 1
progressLabel.Font = Enum.Font.GothamMedium
progressLabel.TextSize = 11
progressLabel.TextColor3 = COLOR_WOOD_DARK
progressLabel.TextXAlignment = Enum.TextXAlignment.Right
progressLabel.TextYAlignment = Enum.TextYAlignment.Bottom
progressLabel.Text = ""
progressLabel.ZIndex = card.ZIndex + 1
progressLabel.Parent = card

local questStateEvent = waitForQuestStateEvent(30)
if not questStateEvent then
	warn("[TrackerCard] QuestState RemoteEvent missing; tracker disabled")
	return
end

-- ─── Reactive paint (H4) ────────────────────────────────────────────
-- Server enforces "one tracked at a time" in the QuestState handlers,
-- so we just hunt for the first q.tracked == true. If none is found
-- the tracker hides itself; otherwise we paint title/objective/
-- progress/timer and show the ScreenGui.
local trackedQuest    -- cached for H5's heartbeat tick
local trackedDeadline -- os.clock()-based deadline for challenges

local function fmtSeconds(secs)
	secs = math.max(0, math.floor(secs + 0.5))
	local m = math.floor(secs / 60)
	local s = secs % 60
	return string.format("%d:%02d", m, s)
end

local function paint(q)
	trackedQuest = q

	if not q then
		screenGui.Enabled = false
		trackedDeadline = nil
		return
	end

	screenGui.Enabled = true
	iconImage.Image = q.icon or ""
	title.Text      = q.title or q.id or ""

	-- Objective text — story has multiple, dailies/challenges have one.
	-- Show the first not-yet-completed objective; if all are done,
	-- show the last one so the line doesn't blank out before claim.
	local objs = q.objectives or {}
	local prog, goal = 0, 0
	local activeObj = objs[#objs]
	local pickedActive = false
	for _, obj in ipairs(objs) do
		local p = tonumber(obj.progress) or 0
		local g = tonumber(obj.goal) or 0
		prog = prog + p
		goal = goal + g
		if not pickedActive and p < g then
			activeObj = obj
			pickedActive = true
		end
	end
	objective.Text = activeObj and (activeObj.label or activeObj.eventType or "") or ""

	local pct = (goal > 0) and math.clamp(prog / goal, 0, 1) or 0
	progressFill.Size  = UDim2.new(pct, 0, 1, 0)
	progressLabel.Text = string.format("%d / %d", prog, goal)

	-- Timer — only for tracked challenges that are still running.
	if q.kind == "challenge" and q.startedAt and q.secondsRemaining
		and not q.rewardPending then
		timerLabel.Visible = true
		timerLabel.Text    = fmtSeconds(q.secondsRemaining)
		trackedDeadline    = os.clock() + q.secondsRemaining
	else
		timerLabel.Visible = false
		trackedDeadline    = nil
	end
end

questStateEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "state" then return end
	if type(payload) ~= "table" then return end
	local picked
	for _, q in ipairs(payload.quests or {}) do
		if q.tracked then picked = q; break end
	end
	paint(picked)
end)
