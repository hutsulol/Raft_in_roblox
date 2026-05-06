-- MercStats.module.lua
-- Single source of truth for the per-merc Strength / Speed / Luck
-- system spec'd in src/GameDesign/StatsSystem.md. Required by the
-- mercenary menu (display) and by the per-rig combat / harvest
-- scripts (gameplay effects).
--
-- The doc defines five tiers (Pirate / Marauder / Mutant / Military /
-- Prototype) on a 10–200 universal scale. We currently ship three of
-- them in the game; mapped here by the in-game merc id:
--   "Pirate lvl1"       → Pirate
--   "Corsair"           → Marauder
--   "Infected Military" → Military
-- Mutant and Prototype are absent from the rig roster so they're
-- omitted; add them here when their rigs land.
--
-- Per the user's brief: implement DAMAGE and RESOURCE COLLECTION
-- only. Fishing isn't fully wired so luck → fishingTime is provided
-- but no script reads it yet.

local MercStats = {}

-- Level-1 starting values (Section 3 of the doc).
MercStats.BASE = {
	["Pirate lvl1"]       = { strength = 10,  speed = 10,  luck = 10 },
	["Corsair"]           = { strength = 30,  speed = 62,  luck = 35 },
	["Infected Military"] = { strength = 110, speed = 131, luck = 75 },
}

-- Level-10 fully-upgraded values (Section 4 of the doc). Used by the
-- menu UI to draw the bar's max tick — the actual interpolation
-- between base and max lives in the upgrade system.
MercStats.MAX = {
	["Pirate lvl1"]       = { strength = 45,  speed = 45,  luck = 45 },
	["Corsair"]           = { strength = 65,  speed = 97,  luck = 70 },
	["Infected Military"] = { strength = 145, speed = 166, luck = 110 },
}

-- Universal display ceiling — per the doc all stats live on a 10–200
-- scale. The menu's stat bars normalise against this.
MercStats.UNIVERSAL_MAX = 200

local function clampNum(n)
	return tonumber(n) or 10
end

-- ── Strength → fist / swing damage ───────────────────────────────────
-- 5 + (strength - 10) * 0.5 → str 10 = 5 dmg, str 200 = 100 dmg.
-- Reads as "the merc's bare-hand power"; we apply this same number to
-- weapon swings (Pirate ClassicSword, Corsair Cutlass, Corsair Revolver
-- bullet) and the Soldier's AK bullet so a higher-tier merc hits
-- demonstrably harder regardless of weapon. Weapons remain a flavour
-- + animation distinction; numeric output is stat-driven.
function MercStats.fistDamage(strength)
	return 5 + (clampNum(strength) - 10) * 0.5
end

-- ── Speed → resource gather time (seconds) ───────────────────────────
-- 15 - (speed - 10) * 11/190 → speed 10 = 15 s, speed 200 = 4 s.
-- Used by HarvestResources.script as the cooldown between harvest
-- swings, replacing the previous ad-hoc 1+speed/100 multiplier.
function MercStats.gatherTime(speed)
	local t = 15 - (clampNum(speed) - 10) * 11 / 190
	if t < 1 then t = 1 end
	return t
end

-- ── Luck → fishing time + rare catch chance ─────────────────────────
-- Provided for completeness; no script reads these yet because
-- fishing isn't fully implemented per the user's note.
function MercStats.fishingTime(luck)
	local t = 15 - (clampNum(luck) - 10) * 11 / 190
	if t < 1 then t = 1 end
	return t
end

function MercStats.rareCatchChance(luck)
	return (clampNum(luck) / 200) * 0.35
end

-- ── Lookups ──────────────────────────────────────────────────────────
local DEFAULT_STATS = { strength = 10, speed = 10, luck = 10 }

function MercStats.baseFor(mercName)
	return MercStats.BASE[mercName] or DEFAULT_STATS
end

function MercStats.maxFor(mercName)
	return MercStats.MAX[mercName] or DEFAULT_STATS
end

-- Convenience: resolve a rig-side stat by reading the rig's MercName
-- attribute (set by MercenarySpawner) or, as a fallback, the Model
-- name. Hostile rigs placed manually in workspace can use the model
-- name directly so e.g. an "Infected Military" hostile picks up the
-- 110/131/75 values without further setup.
function MercStats.statsFromRig(model)
	if not model then return DEFAULT_STATS end
	local mercName = (model.GetAttribute and model:GetAttribute("MercName")) or model.Name
	return MercStats.baseFor(mercName)
end

return MercStats
