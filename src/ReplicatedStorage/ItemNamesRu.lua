--[[
	НАЗВАНИЯ ПРЕДМЕТОВ ДЛЯ ИГРОКА.

	Служебные ключи (Plastic_canister, Stone_Axe, Log…) переименовывать нельзя — по
	ним идут инвентарь, рецепты, сохранения и обмен с сервером. Поэтому переводим
	только ПОДПИСЬ, в одном месте.

	Порядок поиска: инструменты отсюда → ресурсы из ResourceNamesRu → как есть,
	с подчёркиваниями, заменёнными на пробелы.

	ДРУГИЕ ЯЗЫКИ. Русский здесь — исходный текст, а не потолок: localize() гоняет
	готовую строку через переводчик Roblox (LocalizationService), поэтому игроку с
	другой локалью подпись приедет на его языке. Чтобы это заработало, у опыта
	должен быть включён автоперевод: Creator Dashboard → Localization → Automatic
	Translation, и там же добавлены нужные языки. Пока он выключен (или перевода на
	эту строку нет), Translate возвращает исходную строку — то есть русский.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local LocalizationService = game:GetService("LocalizationService")

local ResourceNamesRu = require(ReplicatedStorage:WaitForChild("ResourceNamesRu"))

local ItemNamesRu = {}

-- Инструменты, оружие, постройки и прочее, чего нет среди ресурсов.
ItemNamesRu.TOOLS = {
	-- контейнеры (крафт, дроп)
	SmallContainer    = "Малый контейнер",
	PlasticContainer  = "Пластиковый контейнер",
	-- инструменты
	Hammer            = "Молоток",
	["Pick-Axe"]      = "Кирка",
	PickAxe           = "Кирка",
	Shovel            = "Лопата",
	Paddle            = "Весло",
	FishingRod        = "Удочка",
	Cup               = "Кружка",
	Phone             = "Телефон",
	Injector          = "Инъектор",
	Destitalor        = "Очиститель воды",
	Plastic_canister  = "Пластиковая канистра",

	-- оружие
	Axe               = "Топор",
	Stone_Axe         = "Каменный топор",
	Fire_Axe          = "Огненный топор",
	Machete           = "Мачете",
	Wood_Knife        = "Деревянный нож",
	Torch             = "Факел",
	Revolver          = "Револьвер",
	Pirate_Gun        = "Пиратская пушка",
	["Pirate Gun"]    = "Пиратская пушка",
	PirateGun         = "Пиратская пушка",
	["AK-47"]         = "АК-47",
	AK47              = "АК-47",

	-- экипировка
	DivingMask        = "Маска для ныряния",

	-- мешки и ёмкости
	bag_empty_2       = "Пустой мешок",
	["leaf bag"]      = "Мешок из листьев",
	["Sand Bag"]      = "Мешок с песком",
	EmptyCapsule      = "Пустая капсула",
	FullCapsule       = "Капсула с кровью",

	-- постройки и предметы
	WorkBench         = "Верстак",
	Furnace           = "Печь",
	FireCamp          = "Костёр",
	Raft_grill        = "Костровая жаровня",
	Raft_scarecrow    = "Пугало",
	Raft_farm_block   = "Ферма 2×2",
	Raft_farmer_hut   = "Дом фермера",
	Raft_farm_trough  = "Корыто",
	RaftDecor_bunting = "Гирлянда",
	RaftDecor_can_flower = "Цветок в банке",
	RaftDecor_deckchair = "Шезлонг",
	RaftDecor_lantern = "Фонарь",
	RaftDecor_lifebuoy = "Спасательный круг",
	RaftDecor_rug = "Коврик",
	RaftDecor_shelf = "Полка",
	RaftDecor_sign = "Указатель",
	RaftDecor_spool_table = "Стол-катушка",
	RaftDecor_stool = "Табурет",
	RaftDecor_wheel = "Штурвал",
	OilBarrel_SCENE   = "Бочка с нефтью",
	Monolit_Aquamen   = "Тотем водолазов",
	Raft_repair_station = "Ремонтная станция",
	Raft_wool_bin     = "Ящик для шерсти",
	Pirate_Net_Launcher = "Сеткомёт",
	Raft_chair        = "Стул",
	Raft_chair_leaf   = "Стул с листвой",
	Raft_table_leaves = "Стол с листвой",
	Sawmill           = "Лесопилка",
	Garden            = "Грядка",
	Bed               = "Лежанка",
	Bed_T             = "Лежанка",
	bush              = "Куст",
	Anchor_part       = "Якорь",
	Boat_3x           = "Причал с лодкой",
	Hook              = "Крюк",

	-- семена и прочее
	Palm_seed         = "Семена пальмы",
	Banana_Seed       = "Семена банана",
	Coconut_Seed      = "Семена кокоса",
	Pineapple_seed    = "Семена ананаса",
	Pineapple_Seed    = "Семена ананаса",
	Grapes            = "Виноград",
}

-- «Revolver (6/18)» → «Revolver»: стволы переименовываются под счётчик патронов
-- прямо в игре, и точное имя у них не совпадает почти никогда.
local function baseKey(key)
	local base = key:match("^(.-)%s*%(")
	return (base and base ~= "" ) and base or key
end

-- Русская подпись или nil, если ключ неизвестен.
function ItemNamesRu.lookup(key)
	if type(key) ~= "string" or key == "" then return nil end
	local name = ItemNamesRu.TOOLS[key] or ResourceNamesRu[key]
	if name then return name end
	local base = baseKey(key)
	if base ~= key then
		return ItemNamesRu.TOOLS[base] or ResourceNamesRu[base]
	end
	return nil
end

-- Подпись «как есть» для неизвестного ключа: подчёркивания на пробелы.
function ItemNamesRu.pretty(key)
	if type(key) ~= "string" then return nil end
	return (key:gsub("_", " "))
end

-- ── перевод на язык игрока ──
-- Переводчик получается один раз и асинхронно: GetTranslatorForPlayerAsync ждёт
-- сеть, и дёргать его на каждую подсказку нельзя.
local translator = nil
if RunService:IsClient() then
	task.spawn(function()
		local ok, t = pcall(function()
			return LocalizationService:GetTranslatorForPlayerAsync(Players.LocalPlayer)
		end)
		if ok then translator = t end
	end)
end

-- Возвращает текст на языке игрока. Нет переводчика или перевода — возвращается
-- исходная строка, то есть русская: подпись не пропадёт ни при каких условиях.
function ItemNamesRu.localize(text, context)
	if type(text) ~= "string" or text == "" then return text end
	if not translator then return text end
	local ok, out = pcall(function()
		return translator:Translate(context or game, text)
	end)
	if ok and type(out) == "string" and out ~= "" then return out end
	return text
end

-- Всё вместе: ключ предмета → готовая подпись на языке игрока.
function ItemNamesRu.display(key, context)
	local name = ItemNamesRu.lookup(key) or ItemNamesRu.pretty(key)
	if not name then return nil end
	return ItemNamesRu.localize(name, context)
end

return ItemNamesRu
