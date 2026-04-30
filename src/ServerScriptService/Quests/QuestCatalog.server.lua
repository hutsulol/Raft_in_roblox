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
