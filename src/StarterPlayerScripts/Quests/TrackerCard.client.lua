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

local questStateEvent = waitForQuestStateEvent(30)
if not questStateEvent then
	warn("[TrackerCard] QuestState RemoteEvent missing; tracker disabled")
	return
end

-- Subscribe so H4's paint path can read incoming snapshots.
questStateEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "state" then return end
	if type(payload) ~= "table" then return end
	-- Phase H4 will hunt for q.tracked and paint the card.
end)
