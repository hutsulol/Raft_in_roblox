-- WeaponCollectionCatalog.lua  (ReplicatedStorage, shared module)
-- Every weapon that appears in the "mystery crate" collection menu
-- (WeaponCollectionMenu.client). Seeded from the roulette (RewardRoll) cannons —
-- extend this list with your own weapons.
--
-- Per weapon:
--   id          unique, DataStore-stable key (used for obtained/donate tracking)
--   name        display name
--   icon        rbxassetid image (the same icons the roulette uses)
--   stars       0..5 rating (fractional .5 → a half-star), shown in the corner + detail
--   rarity      "gray" | "green" | "blue" | "epic" | "legendary"  → card background
--   droppable   true = can drop from the crate; false = "archive" (locked until obtained)
--   donate      true = premium; shown ONLY to players who own it (ownsDonateWeapon hook)
--   dropChance  optional %, shown in the detail panel for droppable weapons
--   description optional flavour text for the detail panel

local Catalog = {}

-- rarity tier → background image (the assets you provided)
Catalog.RARITY_BG = {
	gray      = "rbxassetid://102629356027549",
	green     = "rbxassetid://138465181653245",
	blue      = "rbxassetid://77490699463857",
	epic      = "rbxassetid://110600259969843",
	legendary = "rbxassetid://124526617638001",
}

-- sort weight (common → legendary)
Catalog.RARITY_ORDER = { gray = 1, green = 2, blue = 3, epic = 4, legendary = 5 }

-- star icons (match the roulette)
Catalog.STAR_FULL = "rbxassetid://128165533748650"
Catalog.STAR_HALF = "rbxassetid://104758515646132"

Catalog.Weapons = {
	{ id = "Cannon",           name = "Пушка",               icon = "rbxassetid://118236242385241",
	  stars = 0.5, rarity = "gray",      droppable = true,  donate = false, dropChance = 38,
	  description = "Базовая пушка." },
	{ id = "Deffender",        name = "ПВО",                 icon = "rbxassetid://86928740553428",
	  stars = 0.5, rarity = "green",     droppable = true,  donate = false, dropChance = 24,
	  description = "Сбивает воздушные цели." },
	{ id = "Pulemet_lvl_1",    name = "Пулемёт",             icon = "rbxassetid://106277044945645",
	  stars = 1.5, rarity = "blue",      droppable = true,  donate = false, dropChance = 14,
	  description = "Скорострельная турель: садись за неё и поливай деревянными снарядами." },
	{ id = "MagmaCannon",      name = "Магма-пушка",         icon = "rbxassetid://97658619335375",
	  stars = 0.5, rarity = "blue",      droppable = true,  donate = false, dropChance = 12,
	  description = "Стреляет раскалённой магмой." },
	{ id = "Big_Magma_Cannon", name = "Большая магма-пушка", icon = "rbxassetid://90669361199026",
	  stars = 2,   rarity = "epic",      droppable = true,  donate = false, dropChance = 7,
	  description = "Тяжёлая магма-пушка с большим уроном." },
	{ id = "Pulemet_lvl_2",    name = "Пулемёт II",          icon = "rbxassetid://79105833790080",
	  stars = 3,   rarity = "epic",      droppable = true,  donate = false, dropChance = 5,
	  description = "Эпическая турель: тот же Гатлинг, но урон вдвое выше." },
	-- ↑ добавляй сюда свои пушки. У КАЖДОЙ должна быть своя иконка, иначе будут дубли.
	--   donate = true  → видна только владельцу (хук ownsDonateWeapon);
	--   droppable = false → «особая», не выпадает из ящика.
}

-- id → weapon lookup
Catalog.ById = {}
for _, w in ipairs(Catalog.Weapons) do
	Catalog.ById[w.id] = w
end

return Catalog
