-- Characteristics.server.lua
-- Player level / upgrade points / attributes system.
--
-- Creates a `Characteristics` Folder under each Player containing the
-- IntValues the Phone menu reads to drive its level badge, upgrade-points
-- counter, attribute rows and XP bar. IntValue children replicate
-- automatically, so the client only needs to subscribe to them.
--
-- Rules (development phase):
--   * Each in-game day lived grants 10 XP.
--   * Levelling up costs 50 XP (flat for now).
--   * Each level-up grants 1 upgrade point.
--   * Upgrade points can be spent on attributes. Strength is the only
--     attribute wired up right now; Mana / Mutation will be added later
--     using the same phoneMenuEvent dispatch pattern.
--   * Dev defaults: players start at Level 3 with 20 unspent points so
--     the UI is exercisable end-to-end without grinding.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEV_START_LEVEL          = 3
local DEV_START_UPGRADE_POINTS = 20
local XP_PER_DAY               = 10
local XP_PER_LEVEL             = 50

-- ─── Shared RemoteEvent ─────────────────────────────────────────────────
-- Created by PhoneMenu.server.lua; we piggyback on it so attribute
-- upgrades flow through the same pipe the rest of the phone menu uses.
local phoneMenuEvent = ReplicatedStorage:FindFirstChild("PhoneMenuAction")
if not phoneMenuEvent then
	phoneMenuEvent = Instance.new("RemoteEvent")
	phoneMenuEvent.Name = "PhoneMenuAction"
	phoneMenuEvent.Parent = ReplicatedStorage
end

-- ─── Per-player data ────────────────────────────────────────────────────

local function intValue(name, value, parent)
	local v = Instance.new("IntValue")
	v.Name = name
	v.Value = value
	v.Parent = parent
	return v
end

local function setupPlayer(player)
	if player:FindFirstChild("Characteristics") then return end

	local folder = Instance.new("Folder")
	folder.Name = "Characteristics"
	folder.Parent = player

	intValue("Level",         DEV_START_LEVEL,          folder)
	intValue("XP",            0,                        folder)
	intValue("XPRequired",    XP_PER_LEVEL,             folder)
	intValue("UpgradePoints", DEV_START_UPGRADE_POINTS, folder)
	intValue("Strength",      0,                        folder)
end

for _, p in Players:GetPlayers() do
	setupPlayer(p)
end
Players.PlayerAdded:Connect(setupPlayer)

-- ─── XP / levelling helpers ─────────────────────────────────────────────

local function addXP(player, amount)
	local folder = player:FindFirstChild("Characteristics")
	if not folder then return end

	local xp            = folder:FindFirstChild("XP")
	local level         = folder:FindFirstChild("Level")
	local xpRequired    = folder:FindFirstChild("XPRequired")
	local upgradePoints = folder:FindFirstChild("UpgradePoints")
	if not (xp and level and xpRequired and upgradePoints) then return end

	xp.Value = xp.Value + amount

	-- Handle multi-level gains cleanly — unlikely in normal play but we
	-- still want the loop to settle correctly if a big chunk of XP is
	-- granted at once (e.g. future quest rewards).
	while xp.Value >= xpRequired.Value do
		xp.Value = xp.Value - xpRequired.Value
		level.Value = level.Value + 1
		upgradePoints.Value = upgradePoints.Value + 1
	end
end

-- ─── Day hook ───────────────────────────────────────────────────────────
-- DayCount is replicated by DayNightCycle.server.lua and increments once
-- per full day/night cycle, so its Changed signal is our "one day lived"
-- trigger. Every player still in the server at that moment earns the
-- daily XP payout.
local dayCount = ReplicatedStorage:WaitForChild("DayCount")
dayCount:GetPropertyChangedSignal("Value"):Connect(function()
	for _, player in Players:GetPlayers() do
		addXP(player, XP_PER_DAY)
	end
end)

-- ─── Upgrade dispatch ───────────────────────────────────────────────────
-- The Phone menu fires PhoneMenuAction with an action string. We only
-- react to the handful this module owns (just "upgradeStrength" for
-- now) and silently ignore everything else so other handlers on the
-- same event keep working.
phoneMenuEvent.OnServerEvent:Connect(function(player, action)
	if action ~= "upgradeStrength" then return end

	local folder = player:FindFirstChild("Characteristics")
	if not folder then return end

	local upgradePoints = folder:FindFirstChild("UpgradePoints")
	local strength      = folder:FindFirstChild("Strength")
	if not (upgradePoints and strength) then return end

	if upgradePoints.Value > 0 then
		upgradePoints.Value = upgradePoints.Value - 1
		strength.Value = strength.Value + 1
	end
end)
