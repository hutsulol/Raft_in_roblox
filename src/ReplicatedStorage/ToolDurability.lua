--[[
	ПРОЧНОСТЬ ИНСТРУМЕНТОВ И ОРУЖИЯ — общий модуль для сервера и клиента.

	Каждое применение тула тратит прочность. Значение живёт в АТРИБУТАХ самого
	Tool (Durability / MaxDurability): атрибуты реплицируются с сервера на клиент
	сами, поэтому шкале в инвентаре не нужен ни свой ремоут, ни опрос сервера.

	СПИСОК ЯВНЫЙ, а не «всё подряд». Тулами в этой игре являются ещё и еда, семена,
	капсулы, кружка, мешки и целые постройки (причал, верстак) — шкала прочности на
	банане не нужна, а «сломать» размещаемую постройку означало бы её потерять.
	Поэтому изнашивается только то, что перечислено ниже.

	ДОБАВИТЬ НОВЫЙ ИНСТРУМЕНТ = дописать имя в TOOLS (или в FIREARM_PREFIXES, если
	это ствол). Больше нигде ничего править не нужно.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AxeTools = require(ReplicatedStorage:WaitForChild("AxeTools"))

local ToolDurability = {}

ToolDurability.ATTR_CUR = "Durability"
ToolDurability.ATTR_MAX = "MaxDurability"

ToolDurability.DEFAULT_MAX = 100   -- всё оружие и инструменты
ToolDurability.FIREARM_MAX = 250   -- револьвер, ручная пушка — любой огнестрел

-- Сколько прочности снимает одно применение. Отдельная таблица на случай, если
-- какой-то инструмент должен изнашиваться быстрее или медленнее остальных.
ToolDurability.COST_PER_USE = 1
ToolDurability.COST_OVERRIDE = {}

-- ⚠️ ПО ПРЕФИКСУ: стволы переименовываются под счётчик патронов прямо в игре
-- («Revolver» → «Revolver (6/18)», см. WeaponIcons/AmmoCaseSystem), и точное имя
-- у них не совпадает почти никогда.
ToolDurability.FIREARM_PREFIXES = {
	"Revolver", "Pirate_Gun", "Pirate Gun", "PirateGun", "AK-47", "AK47",
}

-- Инструменты и оружие ближнего боя. Топоры сюда не пишем — их единый список
-- живёт в AxeTools и подхватывается ниже автоматически.
ToolDurability.TOOLS = {
	Hammer     = true,
	Machete    = true,
	Wood_Knife = true,
	["Pick-Axe"] = true,
	PickAxe    = true,
	Shovel     = true,
	Paddle     = true,
	FishingRod = true,
	-- Факела здесь НЕТ намеренно: он не изнашивается.
}

-- ── ИЗ ЧЕГО СДЕЛАН ИНСТРУМЕНТ: от этого зависит звук поломки ──
-- Огнестрел всегда металл, поэтому в таблице его нет. Чего нет в таблице —
-- считается деревянным: большинство инструментов здесь именно такие.
ToolDurability.MATERIAL = {
	Paddle       = "plastic",  -- крафтится из пластика
	Machete      = "metal",
	Axe          = "metal",    -- боевой
	Fire_Axe     = "metal",
	["Pick-Axe"] = "metal",
	PickAxe      = "metal",
	Shovel       = "metal",
	Stone_Axe    = "wood",     -- камень на деревянном топорище
	Hammer       = "wood",
	Wood_Knife   = "wood",
	FishingRod   = "wood",
}
ToolDurability.MATERIAL_DEFAULT = "wood"

-- ЗВУК ПОЛОМКИ. Ищем сверху вниз: сперва готовые звуки, которые в игре уже есть,
-- и только в конце встроенный звук клиента.
--   templates — {модель в ReplicatedStorage, имя Sound внутри неё};
--   service   — имена Sound в SoundService (ищутся рекурсивно);
--   ids       — прямые SoundId, последний рубеж;
--   pitch/volume — PlaybackSpeed и громкость.
ToolDurability.BREAK_SOUNDS = {
	-- «Wood Break» лежит внутри шаблона ресурса Log — им озвучена рубка деревьев
	wood = {
		templates = { { "Log", "Wood Break" } },
		service   = { "Wood_Break", "Wood Break" },
		ids       = { "rbxasset://sounds/clickfast.wav" },
		pitch = 0.85, volume = 0.9,
	},
	plastic = {
		service   = { "Plastic Break", "Plastic_Break" },
		templates = {},
		ids       = { "rbxasset://sounds/clickfast.wav" },
		pitch = 1, volume = 0.9,
	},
	-- metal собирается ниже: он берётся из укрепления плота
}

-- МЕТАЛЛ ЗВУЧИТ ТЕМ ЖЕ, ЧТО ВЫБРАНО ДЛЯ УКРЕПЛЕНИЯ ПЛОТА. Звук металла в игре
-- один, и настраивается он в одном месте: сменишь RaftReinforce.SOUND_PICK —
-- поменяется и укрепление, и поломка железных инструментов.
-- Поле start тянем тоже: у выбранного звука в начале файла тишина, и без обрезки
-- удар опаздывал бы на те же 0.2 с.
do
	local RaftReinforce = require(ReplicatedStorage:WaitForChild("RaftReinforce"))
	local pick = RaftReinforce.SOUND_VARIANTS and RaftReinforce.SOUND_VARIANTS[RaftReinforce.SOUND_PICK]

	local metal = {
		service   = { "Metal_Break" },   -- свой звук, если положат в SoundService
		templates = {},
		ids       = {},
		pitch = 0.4, volume = 0.9, start = 0,
	}
	if pick then
		if pick.sound then table.insert(metal.service, pick.sound) end
		if pick.id then table.insert(metal.ids, pick.id) end
		metal.pitch  = pick.pitch or metal.pitch
		metal.volume = pick.volume or metal.volume
		metal.start  = pick.start or 0
	end
	table.insert(metal.ids, "rbxasset://sounds/clickfast.wav")   -- последний рубеж
	ToolDurability.BREAK_SOUNDS.metal = metal
end

-- Цвета шкалы: без цифр, цвет и есть значение.
ToolDurability.BANDS = {
	{ min = 0.60, color = Color3.fromRGB( 76, 200,  84) },  -- зелёный — целый
	{ min = 0.35, color = Color3.fromRGB(236, 200,  60) },  -- жёлтый — потрёпан
	{ min = 0.15, color = Color3.fromRGB(238, 140,  40) },  -- оранжевый — почти всё
	{ min = 0.00, color = Color3.fromRGB(214,  60,  52) },  -- красный — вот-вот сломается
}

function ToolDurability.colorFor(pct)
	pct = math.clamp(tonumber(pct) or 0, 0, 1)
	for _, band in ipairs(ToolDurability.BANDS) do
		if pct >= band.min then return band.color end
	end
	return ToolDurability.BANDS[#ToolDurability.BANDS].color
end

local function isFirearm(name)
	for _, p in ipairs(ToolDurability.FIREARM_PREFIXES) do
		if name:sub(1, #p) == p then return true end
	end
	return false
end

-- Максимум прочности для тула с таким именем; nil — значит не изнашивается.
function ToolDurability.maxFor(name)
	if type(name) ~= "string" or name == "" then return nil end
	if isFirearm(name) then return ToolDurability.FIREARM_MAX end
	if AxeTools.isAxeName(name) then return ToolDurability.DEFAULT_MAX end
	if ToolDurability.TOOLS[name] then return ToolDurability.DEFAULT_MAX end
	-- «Имя (что-то в скобках)» — на случай, если счётчик приделают и не стволу
	local base = name:match("^(.-)%s*%(")
	if base and ToolDurability.TOOLS[base] then return ToolDurability.DEFAULT_MAX end
	return nil
end

-- Материал тула по имени: огнестрел — всегда металл, остальное по таблице.
function ToolDurability.materialFor(name)
	if type(name) ~= "string" or name == "" then return ToolDurability.MATERIAL_DEFAULT end
	if isFirearm(name) then return "metal" end
	local m = ToolDurability.MATERIAL[name]
	if m then return m end
	local base = name:match("^(.-)%s*%(")
	return (base and ToolDurability.MATERIAL[base]) or ToolDurability.MATERIAL_DEFAULT
end

function ToolDurability.costFor(name)
	return ToolDurability.COST_OVERRIDE[name] or ToolDurability.COST_PER_USE
end

-- Доля прочности тула: число 0..1 или nil, если у тула её нет.
function ToolDurability.fractionOf(tool)
	if not tool then return nil end
	local max = tool:GetAttribute(ToolDurability.ATTR_MAX)
	local cur = tool:GetAttribute(ToolDurability.ATTR_CUR)
	if type(max) ~= "number" or max <= 0 or type(cur) ~= "number" then return nil end
	return math.clamp(cur / max, 0, 1)
end

return ToolDurability
