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
-- The user's reference design ("Lost in the Woods") for the Story
-- tab: 4 multi-step objectives covering early-game progression
-- through pirate combat + DNA research, then a single big reward.
-- Permanent so it never re-rolls or shows up twice.
addQuest({
	id    = "lostInTheWoods",
	kind  = "story",
	title = "Lost in the Woods",
	body  = "The path is blocked. Clear the way and find your way forward.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "merc:hired",        goal = 1, label = "Hire 1 mercenary" },
		{ eventType = "pirate:kill",       goal = 3, label = "Defeat 3 hostile pirates" },
		{ eventType = "pirate:bloodTaken", goal = 5, label = "Collect 5 blood samples" },
		{ eventType = "dna:analyzed",      goal = 1, label = "Analyse a mercenary's DNA" },
	},
	reward    = { kind = "item", name = "WoodcutterChest", count = 1 },
	permanent = true,
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
