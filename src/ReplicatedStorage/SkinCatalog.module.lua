-- SkinCatalog.module.lua
-- Shared, read-only catalog of every mercenary skin. Lives under
-- ReplicatedStorage so both the server (MercenarySkin, MercenarySpawner
-- via _G.ApplyMercSkin) and the client (SkinSelectPage, MercenariesMenu's
-- cached-rig sync) require the same source of truth — no RemoteEvent
-- payload trip needed for static metadata.
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

-- ─── Corsair ────────────────────────────────────────────────────────
-- Placeholder default kit so the wardrobe page has something to render
-- the moment the player recruits a Corsair. Reuses the Pirate's
-- default clothing assets — swap shirtName / pantsName here once the
-- user drops a dedicated Corsair shirt + pants under
-- ReplicatedStorage.Skins.
addSkin({
	id              = "corsair_default",
	mercName        = "Corsair",
	displayName     = "Privateer's Coat",
	rarity          = 2,
	category        = "Crew",
	palette         = { "#3A2A1E", "#A07235", "#1F1B17" },
	setName         = "Corsair",
	source          = "Recruited Outfit",
	description     = "Heavy seafarer's coat — stitched leather and brass fittings.",
	shirtName       = "Clothing_Default_top",
	pantsName       = "Clothing_Default_under",
	ownedByDefault  = true,
})

-- ─── Filtered queries ───────────────────────────────────────────────

local function getByMerc(mercName)
	local out = {}
	for _, entry in pairs(catalog) do
		if entry.mercName == mercName then
			table.insert(out, entry)
		end
	end
	-- Stable order: rarity ascending, then displayName.
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
	for _, entry in pairs(catalog) do
		if entry.mercName == mercName then return entry end
	end
	return nil
end

return {
	get            = function(id) return catalog[id] end,
	all            = function() return catalog end,
	getByMerc      = getByMerc,
	defaultForMerc = defaultForMerc,
}
