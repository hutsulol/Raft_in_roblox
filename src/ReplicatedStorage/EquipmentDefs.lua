--[[
	ЭКИПИРОВКА — общий модуль для сервера и клиента.

	Четыре слота: голова, торс, штаны, ноги. Надетое хранится в АТРИБУТАХ игрока
	(Equip_Head, Equip_Torso, …) — атрибуты реплицируются сами, поэтому интерфейсу
	не нужен ни свой ремоут, ни опрос сервера: он просто читает и слушает их.

	В слоте лежит ИМЯ предмета — тот же ключ, что у ресурса в инвентаре. Сама вещь
	берётся из ReplicatedStorage по этому имени (Accessory надевается через
	Humanoid:AddAccessory).

	ДОБАВИТЬ ВЕЩЬ = дописать строку в ITEMS и положить модель в ReplicatedStorage.
]]

local EquipmentDefs = {}

EquipmentDefs.ATTR_PREFIX = "Equip_"

-- Порядок здесь = порядок слотов в интерфейсе, сверху вниз.
EquipmentDefs.SLOTS = {
	{ key = "Head",  ru = "Голова" },
	{ key = "Torso", ru = "Торс" },
	{ key = "Pants", ru = "Штаны" },
	{ key = "Legs",  ru = "Ноги" },
}

EquipmentDefs.ITEMS = {
	DivingMask = { slot = "Head", ru = "Маска для ныряния" },
}

-- ── МАСКА ДЛЯ НЫРЯНИЯ ──
-- Все числа механики в одном месте: их читают и сервер (заряд, воздух, радиация),
-- и клиент (снятие подводного затемнения).
EquipmentDefs.MASK = {
	item    = "DivingMask",
	slot    = "Head",
	charge  = 300,   -- секунд работы, тратятся ТОЛЬКО под водой
	air     = 60,    -- секунд под водой на одном запасе воздуха
	refill  = 8,     -- секунд на полное восстановление воздуха на поверхности
	warnAt  = 30,    -- за сколько секунд до поломки предупредить игрока
	attr    = "MaskCharge",   -- остаток заряда живёт в атрибуте игрока
}

-- Надета ли маска. Одна проверка на всю игру: и на сервере, и на клиенте.
function EquipmentDefs.hasMask(player)
	return EquipmentDefs.worn(player, EquipmentDefs.MASK.slot) == EquipmentDefs.MASK.item
end

function EquipmentDefs.attr(slotKey)
	return EquipmentDefs.ATTR_PREFIX .. slotKey
end

function EquipmentDefs.slotOf(itemName)
	local def = itemName and EquipmentDefs.ITEMS[itemName]
	return def and def.slot or nil
end

function EquipmentDefs.isEquippable(itemName)
	return EquipmentDefs.slotOf(itemName) ~= nil
end

-- Что сейчас надето в слоте: имя предмета или nil.
function EquipmentDefs.worn(player, slotKey)
	local v = player:GetAttribute(EquipmentDefs.attr(slotKey))
	return (type(v) == "string" and v ~= "") and v or nil
end

return EquipmentDefs
