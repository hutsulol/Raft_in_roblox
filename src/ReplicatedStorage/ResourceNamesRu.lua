-- ResourceNamesRu.lua
-- РУССКИЕ НАЗВАНИЯ РЕСУРСОВ ДЛЯ ИНТЕРФЕЙСА.
--
-- Ключи ресурсов (Log, Iron_Ingot, Blue_Fish…) — служебные: по ним идёт
-- инвентарь, рецепты, сохранения и обмен с сервером. Переименовывать их нельзя,
-- поэтому переводим ТОЛЬКО подпись, и делаем это в одном месте: раньше списки
-- материалов в крафте, ценники построек и панель ремонта показывали игроку
-- сырой ключ («Log: 3 / 5», «5 Log»), а где-то были свои копии перевода.
--
-- Ключи взяты из RESOURCE_NAMES в InventoryManager — добавляя туда ресурс,
-- добавь строку и сюда, иначе в UI снова вылезет английский ключ.

local Names = {
	Log        = "Дерево",
	Plank      = "Доска",
	Plastic    = "Пластик",
	Stone      = "Камень",
	Leaves     = "Листва",
	Compost    = "Компост",
	Rope       = "Верёвка",
	Wet_Brick  = "Сырой кирпич",
	Dry_Brick  = "Кирпич",
	Iron_Ore   = "Железная руда",
	Iron_Ingot = "Слиток железа",

	Blue_Fish      = "Синяя рыба",
	Carp_Fish      = "Карп",
	Foil_Fish      = "Фольгированная рыба",
	Jelly_Fish     = "Медуза",
	Legendary_Fish = "Легендарная рыба",
	Seabass_Fish   = "Морской окунь",
	Tilapia_Fish   = "Тилапия",
	Fish_Bones     = "Рыбьи кости",
	Meat           = "Мясо",

	-- дропы с животных пиратского острова (шаблоны-меши в ReplicatedStorage)
	Chicken_drumstick = "Куриный окорочок",
	Chicken_feather   = "Куриное перо",
	Cow_Hide          = "Коровья шкура",
	Wool              = "Шерсть",          -- продукция фермы (FarmSystem)

	Nail = "Гвоздь",

	-- плавильня
	Seaweed = "Водоросли",
	Glue    = "Клей",
	Crab_Claw = "Клешня краба",

	Blue_Fish_Cooked      = "Жареная синяя рыба",
	Carp_Fish_Cooked      = "Жареный карп",
	Foil_Fish_Cooked      = "Жареная фольгированная рыба",
	Jelly_Fish_Cooked     = "Жареная медуза",
	Legendary_Fish_Cooked = "Жареная легендарная рыба",
	Seabass_Fish_Cooked   = "Жареный морской окунь",
	Tilapia_Fish_Cooked   = "Жареная тилапия",
	Meat_Cooked           = "Жареное мясо",

	Potato        = "Картофель",
	Beet          = "Свёкла",
	Potato_Cooked = "Печёный картофель",
	Beet_Cooked   = "Печёная свёкла",

	Banana              = "Банан",
	Coconut             = "Кокос",
	Pineapple           = "Ананас",
	Pineapple_Bush_Seed = "Семена ананаса",
	Rubbish             = "Мусор",
}

-- Неизвестный ключ возвращаем как есть: лучше английское слово, чем пустота.
return setmetatable(Names, {
	__call = function(self, key)
		return self[key] or tostring(key)
	end,
})
