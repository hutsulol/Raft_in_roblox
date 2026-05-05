-- SkinCatalog.server.lua
-- Static, read-only catalog of every mercenary skin in the game.
-- Published on _G.SkinCatalog for the rest of the server (and the
-- client, via the snapshot pushed by MercenarySkin.server.lua).
--
-- A skin is a (Shirt, Pants) pair living under ReplicatedStorage.Skins.
-- The catalog ties those raw clothing instances to display metadata —
-- name, rarity, category, palette swatches, source / description text
-- — so the SkinSelectPage UI can render the wardrobe cards + detail
-- panel from a single source of truth.
--
-- Skin entry shape:
--   {
--     id              = "default"          -- DataStore-stable key
--     mercName        = "Pirate lvl1"      -- which merc this skin is for
--     displayName     = "Standard Issue",
--     rarity          = 1..5,              -- star count for the row
--     category        = "Crew" | "Sea" | "Festive",
--     palette         = { "#RRGGBB", "#RRGGBB", "#RRGGBB" }, -- 3 swatches
--     setName         = "Crewmate",        -- optional, shown next to stars
--     source          = "Starter Issue",   -- one-line "where this came from"
--     description     = "...",             -- 1-2 sentence flavour text
--     shirtName       = "Clothing_Default_top",   -- child of ReplicatedStorage.Skins
--     pantsName       = "Clothing_Default_under", -- child of ReplicatedStorage.Skins
--     ownedByDefault  = true | false,      -- granted on PlayerAdded if true
--   }

local catalog = {}

local function addSkin(entry)
	assert(type(entry.id) == "string" and entry.id ~= "", "skin id required")
	assert(catalog[entry.id] == nil, "duplicate skin id: " .. entry.id)
	assert(type(entry.mercName) == "string" and entry.mercName ~= "",
		"skin " .. entry.id .. " missing mercName")
	assert(type(entry.shirtName) == "string" and entry.shirtName ~= "",
		"skin " .. entry.id .. " missing shirtName")
	assert(type(entry.pantsName) == "string" and entry.pantsName ~= "",
		"skin " .. entry.id .. " missing pantsName")
	catalog[entry.id] = entry
end

-- ─── Pirate ─────────────────────────────────────────────────────────
-- Default crew kit. Free starter skin — granted on PlayerAdded so the
-- wardrobe is never empty for a fresh player.
addSkin({
	id              = "pirate_default",
	mercName        = "Pirate lvl1",
	displayName     = "Standard Issue",
	rarity          = 1,
	category        = "Crew",
	palette         = { "#F2EBDA", "#3B2E2A", "#7E6043" },
	setName         = "Crewmate",
	source          = "Starter Issue",
	description     = "Standard sailor's clothes — patched, salt-cured, comfortable.",
	shirtName       = "Clothing_Default_top",
	pantsName       = "Clothing_Default_under",
	ownedByDefault  = true,
})

-- Summer drift — tropical blue shirt + sand-coloured shorts. Owned by
-- default for now (no shop yet); flip ownedByDefault to false once an
-- earn-flow exists.
addSkin({
	id              = "pirate_summer",
	mercName        = "Pirate lvl1",
	displayName     = "Summer Drift",
	rarity          = 3,
	category        = "Sea",
	palette         = { "#9ADCF8", "#5FA8C6", "#E6E9D8" },
	setName         = "Tideborn",
	source          = "Tide Pool · Common",
	description     = "Light tropical shirt and shorts patterned with breaking waves.",
	shirtName       = "Clothing_skin_summer_top",
	pantsName       = "Clothing_skin_summer_under",
	ownedByDefault  = true,
})

-- ─── Filtered queries (used by MercenarySkin + SkinSelectPage) ──────

local function getByMerc(mercName)
	local out = {}
	for _, entry in pairs(catalog) do
		if entry.mercName == mercName then
			table.insert(out, entry)
		end
	end
	-- Stable order: rarity ascending, then displayName, so the grid
	-- always lays out the same way across opens.
	table.sort(out, function(a, b)
		if a.rarity ~= b.rarity then return a.rarity < b.rarity end
		return a.displayName < b.displayName
	end)
	return out
end

local function defaultForMerc(mercName)
	for _, entry in pairs(catalog) do
		if entry.mercName == mercName and entry.ownedByDefault then
			return entry
		end
	end
	-- Fall back to whatever the first catalog entry for this merc is —
	-- never returns nil for a merc that has any skin defined, so the
	-- spawner always has something to apply.
	for _, entry in pairs(catalog) do
		if entry.mercName == mercName then return entry end
	end
	return nil
end

_G.SkinCatalog = {
	get            = function(id) return catalog[id] end,
	all            = function() return catalog end,
	getByMerc      = getByMerc,
	defaultForMerc = defaultForMerc,
}
