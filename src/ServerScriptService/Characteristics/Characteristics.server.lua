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
--   * Upgrade points can be spent on attributes. Strength, Mana and
--     Mutation are the three attributes surfaced on the phone menu; each
--     one consumes one upgrade point per level via its own
--     phoneMenuEvent action string.
--   * Dev defaults: players start at Level 3 with 20 unspent points so
--     the UI is exercisable end-to-end without grinding.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEV_START_LEVEL          = 3
local DEV_START_UPGRADE_POINTS = 20
local XP_PER_DAY               = 10
local XP_PER_LEVEL             = 50

-- ─── Mana pool tuning ───────────────────────────────────────────────────
-- The Mana attribute is an upgrade level bumped via the phone menu. It
-- drives a replicated mana pool the client reads to render the mana
-- bar above the hotbar: max = BASE_MANA + Mana * MANA_PER_LEVEL.
local BASE_MANA                = 100
local MANA_PER_LEVEL           = 20

local function computeManaMax(manaLevel)
	return BASE_MANA + manaLevel * MANA_PER_LEVEL
end

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

	local level         = intValue("Level",         DEV_START_LEVEL,          folder)
	local xp            = intValue("XP",            0,                        folder)
	local xpRequired    = intValue("XPRequired",    XP_PER_LEVEL,             folder)
	local upgradePoints = intValue("UpgradePoints", DEV_START_UPGRADE_POINTS, folder)
	intValue("Strength",      0,                        folder)
	local manaStat = intValue("Mana",          0,       folder)
	intValue("Mutation",      0,                        folder)

	-- Mana resource pool, derived from the Mana attribute. ManaMax is
	-- recomputed whenever the Mana attribute changes; ManaCurrent
	-- starts at full and is preserved across level-ups by granting
	-- the delta (so the UI feels like a full refill on upgrade).
	local initialMax = computeManaMax(manaStat.Value)
	local manaMax     = intValue("ManaMax",     initialMax, folder)
	local manaCurrent = intValue("ManaCurrent", initialMax, folder)

	manaStat:GetPropertyChangedSignal("Value"):Connect(function()
		local oldMax = manaMax.Value
		local newMax = computeManaMax(manaStat.Value)
		if newMax == oldMax then return end
		manaMax.Value = newMax
		if newMax > oldMax then
			manaCurrent.Value = math.min(manaCurrent.Value + (newMax - oldMax), newMax)
		else
			manaCurrent.Value = math.clamp(manaCurrent.Value, 0, newMax)
		end
	end)

	-- Auto level-up: whenever XP changes from ANY source (day payout,
	-- quest rewards, future systems), check for level-ups. A reentrancy
	-- guard prevents the nested Changed signals from double-processing.
	local levelingUp = false
	xp:GetPropertyChangedSignal("Value"):Connect(function()
		if levelingUp then return end
		levelingUp = true
		while xp.Value >= xpRequired.Value and xpRequired.Value > 0 do
			xp.Value = xp.Value - xpRequired.Value
			level.Value = level.Value + 1
			upgradePoints.Value = upgradePoints.Value + 1
		end
		levelingUp = false
	end)
end

for _, p in Players:GetPlayers() do
	setupPlayer(p)
end
Players.PlayerAdded:Connect(setupPlayer)

-- ─── XP / levelling helpers ─────────────────────────────────────────────

local function addXP(player, amount)
	local folder = player:FindFirstChild("Characteristics")
	if not folder then return end
	local xp = folder:FindFirstChild("XP")
	if not xp then return end
	-- Level-up is handled automatically by the XP Changed listener
	xp.Value = xp.Value + amount
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
-- The Phone menu fires PhoneMenuAction with an action string. We map each
-- supported action to the attribute IntValue it should bump and silently
-- ignore everything else so other handlers on the same event (daily-quest
-- claim, etc.) keep working.
local UPGRADE_ACTIONS = {
	upgradeStrength = "Strength",
	upgradeMana     = "Mana",
	upgradeMutation = "Mutation",
}

phoneMenuEvent.OnServerEvent:Connect(function(player, action)
	local statName = UPGRADE_ACTIONS[action]
	if not statName then return end

	local folder = player:FindFirstChild("Characteristics")
	if not folder then return end

	local upgradePoints = folder:FindFirstChild("UpgradePoints")
	local stat          = folder:FindFirstChild(statName)
	if not (upgradePoints and stat) then return end

	if upgradePoints.Value > 0 then
		upgradePoints.Value = upgradePoints.Value - 1
		stat.Value = stat.Value + 1
	end
end)
