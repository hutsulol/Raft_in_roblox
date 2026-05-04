-- QuestCatalog.server.lua
-- Static, read-only catalog of every quest in the game. Built up
-- across C1 → C5 (this file) and read by QuestState.server.lua
-- (lands in C6). Published on _G.QuestCatalog so the rest of the
-- server can iterate it without re-requiring a module.
--
-- C1 (this commit): empty scaffold + shape comment. The actual quest
-- entries land in C2 (story #1), C3 (story #2), C4 (4 dailies), and
-- C5 (4 timed challenges).
--
-- Quest entry shape (every entry must conform):
--   {
--     id        = "string",                     -- unique key (DataStore-stable)
--     kind      = "story" | "daily" | "challenge",
--     title     = "string",                     -- shown on the quest card
--     body      = "string",                     -- one-line description
--     icon      = "rbxassetid://...",           -- card icon
--     objectives = {                            -- 1+ entries; multi only for story
--         { eventType = "resource:Log", goal = 10, label = "Chop logs" },
--         ...
--     },
--     reward    = { kind = "resource"|"item", name = "Log", count = 10 },
--     durationSec = 30,                          -- challenges only; nil otherwise
--     permanent = true,                          -- when true, completion sticks
--                                                -- across rerolls (story + craft
--                                                -- gates use this); see C4 for
--                                                -- the workbench dedup case.
--   }

local catalog = {}

-- C2 onward writes into `catalog` via the helpers below. Doing it
-- through helpers (instead of inline table construction) gives us a
-- single place to validate shape if/when a quest is mistyped.

local function addQuest(entry)
	assert(type(entry.id) == "string" and entry.id ~= "", "quest id required")
	assert(catalog[entry.id] == nil, "duplicate quest id: " .. entry.id)
	assert(type(entry.objectives) == "table" and #entry.objectives > 0,
		"quest " .. entry.id .. " needs at least one objective")
	catalog[entry.id] = entry
end

-- ─── Story quest #1 — Lost in the Woods (C2) ───────────────────────
-- Early-game story arc: the player chops the path open, scavenges
-- the trash for raft mats, and crafts their first workbench. Three
-- objectives matching the user's reference design. Reward is a
-- single Woodcutter's Chest. Permanent so it never re-rolls.
addQuest({
	id    = "lostInTheWoods",
	kind  = "story",
	title = "Lost in the Woods",
	body  = "The path is blocked. Clear the way and find your way forward.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "resource:Log",       goal = 10, label = "Chop down 10 trees" },
		{ eventType = "resource:Plastic",   goal = 15, label = "Collect 15 pieces of trash" },
		{ eventType = "crafted:WorkBench",  goal = 1,  label = "Build a workbench" },
	},
	reward    = {
		kind  = "item",
		name  = "WoodcutterChest",
		label = "Woodcutter's Chest",
		icon  = "rbxassetid://82337855669175",
		count = 1,
	},
	permanent = true,
})

-- ─── Story quest #2 — Stranded Survivor (C3, placeholder) ──────────
-- Second story arc, focused on raft expansion + survival mechanics.
-- Final reward + balance numbers are provisional; the user can fine-
-- tune after testing. Same permanent contract as story #1 — never
-- re-rolls, never duplicates.
addQuest({
	id    = "strandedSurvivor",
	kind  = "story",
	title = "Stranded Survivor",
	body  = "The sea won't feed itself. Build out the raft and stockpile.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "crafted:WorkBench",  goal = 1,  label = "Craft a workbench" },
		{ eventType = "crafted:WallPanel",  goal = 4,  label = "Build 4 wall panels" },
		{ eventType = "resource:Log",       goal = 50, label = "Stockpile 50 logs" },
	},
	reward    = {
		kind  = "item",
		name  = "SurvivorChest",
		label = "Survivor's Chest",
		icon  = "rbxassetid://82337855669175",
		count = 1,
	},
	permanent = true,
})

-- ─── Daily quest pool (C4) ──────────────────────────────────────────
-- 6 candidates; the daily-roll logic in C7 will randomly pick 4 each
-- day from this pool, filtered against the player's permanentlyCompleted
-- set so already-crafted single-use objectives (workbench) don't
-- re-appear.
--
-- Single-objective quests by design — multi-step quests live in the
-- story arc instead. Numbers are tuned for ~5–10 minutes of casual
-- play each, so a player who logs in once a day can plausibly clear
-- all 4 in one session.
addQuest({
	id    = "daily_logs",
	kind  = "daily",
	title = "Fallen Branches",
	body  = "Chop down 10 logs.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "resource:Log", goal = 10, label = "Chop logs" },
	},
	reward = { kind = "resource", name = "Log", count = 10 },
})

addQuest({
	id    = "daily_plastic",
	kind  = "daily",
	title = "Plastic Patrol",
	body  = "Fish 8 plastic canisters out of the sea.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "resource:Plastic", goal = 8, label = "Collect plastic" },
	},
	reward = { kind = "resource", name = "Plastic", count = 8 },
})

addQuest({
	id    = "daily_leaves",
	kind  = "daily",
	title = "Green Harvest",
	body  = "Gather 12 bunches of leaves.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "resource:Leaves", goal = 12, label = "Gather leaves" },
	},
	reward = { kind = "resource", name = "Leaves", count = 6 },
})

addQuest({
	id    = "daily_stones",
	kind  = "daily",
	title = "Stone Cold",
	body  = "Mine 6 stones from floating rocks.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "resource:Stone", goal = 6, label = "Mine stones" },
	},
	reward = { kind = "resource", name = "Stone", count = 6 },
})

addQuest({
	id    = "daily_craft_workbench",
	kind  = "daily",
	title = "First Workshop",
	body  = "Craft your very first workbench.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "crafted:WorkBench", goal = 1, label = "Craft workbench" },
	},
	reward = { kind = "resource", name = "Log", count = 15 },
	-- Single-use: once a player has crafted a workbench, this quest
	-- is filtered out of every future daily roll. Other crafting-
	-- gate dailies follow the same pattern.
	permanent = true,
})

addQuest({
	id    = "daily_plant_berries",
	kind  = "daily",
	title = "Sunny Garden",
	body  = "Plant 5 berry bushes.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "planted:BerryBush", goal = 5, label = "Plant berry bushes" },
	},
	reward = { kind = "resource", name = "Leaves", count = 10 },
})

-- ─── Timed challenges (C5) ──────────────────────────────────────────
-- Player presses "Start" on the card, which kicks off a timer; the
-- challenge auto-shows in the upper-right tracker (Phase H) and the
-- card flips to a live countdown. If the goal isn't hit before the
-- timer expires the quest disappears with no reward and the player
-- has to wait for the next day's pool. Phase F drives the timer +
-- expiry server-side; this catalog just declares durations + goals.
addQuest({
	id    = "challenge_logs_30s",
	kind  = "challenge",
	title = "Speed Chopper",
	body  = "Chop 10 logs before time runs out.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "resource:Log", goal = 10, label = "Chop logs" },
	},
	reward      = { kind = "resource", name = "Log", count = 25 },
	durationSec = 30,
})

addQuest({
	id    = "challenge_pirate_kills_30s",
	kind  = "challenge",
	title = "Quick Draw",
	body  = "Defeat 3 hostile pirates before time runs out.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "pirate:kill", goal = 3, label = "Defeat hostile pirates" },
	},
	reward      = { kind = "resource", name = "Plastic", count = 15 },
	durationSec = 30,
})

addQuest({
	id    = "challenge_stones_45s",
	kind  = "challenge",
	title = "Quarry Sprint",
	body  = "Mine 5 stones in 45 seconds.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "resource:Stone", goal = 5, label = "Mine stones" },
	},
	reward      = { kind = "resource", name = "Stone", count = 12 },
	durationSec = 45,
})

addQuest({
	id    = "challenge_plastic_60s",
	kind  = "challenge",
	title = "Reef Cleanup",
	body  = "Fish 8 plastic canisters in 60 seconds.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "resource:Plastic", goal = 8, label = "Collect plastic" },
	},
	reward      = { kind = "resource", name = "Plastic", count = 20 },
	durationSec = 60,
})

-- ─── Filtered views (helper queries used by QuestState in C6+) ───────
-- Returned tables are fresh copies so callers can mutate freely.

local function getByKind(kind)
	local out = {}
	for _, q in pairs(catalog) do
		if q.kind == kind then table.insert(out, q) end
	end
	return out
end

-- ─── Publish ────────────────────────────────────────────────────────

_G.QuestCatalog = {
	get        = function(id) return catalog[id] end,
	all        = function() return catalog end,
	getByKind  = getByKind,
	addQuest   = addQuest,   -- re-exported in case future flows want to register dynamically
}
