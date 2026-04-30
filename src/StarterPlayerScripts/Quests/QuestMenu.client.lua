-- QuestMenu.client.lua
-- Full-screen quest log opened by the left-side QuestEntryButton or
-- the J key. Builds incrementally across B1 → B10 so each commit is
-- testable on its own.
--
-- B1 scope: lazy ScreenGui host + _G.OpenQuestMenu / _G.CloseQuestMenu
-- stubs that flip the host's Enabled flag. Nothing visible yet —
-- B2 lands the wood panel, B3 the tab rail, etc.
--
-- DisplayOrder 110 sits above PhoneMenu (200? actually phone uses
-- 200 for its main screenGui; the OnboardingTooltip uses 200 too,
-- and QuestNotificationGui uses 8). Lifting QuestMenu to 110 keeps
-- it ABOVE in-game HUD and the QuestEntryButton (90) but BELOW the
-- phone if both happen to be open — phone takes precedence as the
-- bigger, more deliberate UI.
--
-- Public API (final shape across B1 → B10):
--   _G.OpenQuestMenu()    -- show the menu (no-op if already open)
--   _G.CloseQuestMenu()   -- hide the menu (no-op if already hidden)

local Players = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SCREENGUI_DISPLAY_ORDER = 110

-- Lazy build: the ScreenGui isn't created until the menu is first
-- opened. Cuts the cost of one always-resident GUI for players who
-- never open the quest log.
local screenGui

local function ensureScreenGui()
	if screenGui and screenGui.Parent then return screenGui end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "QuestMenuGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = SCREENGUI_DISPLAY_ORDER
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false   -- shown only after openQuestMenu()
	screenGui.Parent = playerGui
	return screenGui
end

-- B2 onward attach the panel + tabs + content as children of the
-- ensureScreenGui() return. B1 just wires the open / close lifecycle
-- so callers (the entry-button click + J hotkey) can be tested
-- against a real "menu" target before the visuals land.

local function openQuestMenu()
	local gui = ensureScreenGui()
	gui.Enabled = true
end

local function closeQuestMenu()
	if not screenGui then return end
	screenGui.Enabled = false
end

_G.OpenQuestMenu  = openQuestMenu
_G.CloseQuestMenu = closeQuestMenu
