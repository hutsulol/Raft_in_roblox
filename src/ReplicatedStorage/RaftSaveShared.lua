-- RaftSaveShared.lua  (ReplicatedStorage, shared module)
-- ЕДИНЫЙ контракт системы сохранений между ДВУМЯ плейсами. Копия
-- должна совпадать байт-в-байт:
--   игра (океан): Desktop/Roblox/src/ReplicatedStorage/RaftSaveShared.lua
--   лобби:        Desktop/Lobby_Loongoliers/src/Shared/RaftSaveShared.lua
--
-- Мульти-слот поверх существующего одиночного сейва (RaftSaveData_v1):
--   • slot 1  → ключ "player_<UserId>"  (СТАРЫЙ формат, обратная
--     совместимость: имеющееся сохранение автоматически = слот 1);
--   • slot N>1 → ключ "player_<UserId>_s<N>";
--   • индекс   → ключ "raftindex_<UserId>": список слотов {name, savedAt},
--     режим доступа к плоту и активный слот.
--
-- TeleportData (лобби → океан): { loadSave, raftOwnerId, saveOwnerId,
--   saveSlot, accessMode }. saveSlot — какой слот владельца грузить/писать.

local Shared = {}

Shared.STORE_NAME = "RaftSaveData_v1"
Shared.MAX_SLOTS  = 3
-- слот автосохранения при выходе/по таймеру (последний слот, «АВТО» в UI).
-- Ручное сохранение пишет в активный слот, автосейв — сюда.
Shared.AUTO_SLOT  = 3

Shared.ACCESS_EVERYONE = "everyone"
Shared.ACCESS_FRIENDS  = "friends"

-- атрибуты игрока в ЛОББИ (мост между SaveMenuService и LobbyServer,
-- без обращения к базе): актуальный режим доступа и активный слот
Shared.ATTR_ACCESS = "RaftAccessMode"
Shared.ATTR_SLOT   = "RaftActiveSlot"

-- ключ конкретного слота (слот 1 = старый формат для совместимости)
function Shared.slotKey(userId, slot)
	slot = tonumber(slot) or 1
	if slot <= 1 then
		return "player_" .. userId
	end
	return "player_" .. userId .. "_s" .. slot
end

-- ключ индекса слотов игрока
function Shared.indexKey(userId)
	return "raftindex_" .. userId
end

-- нормализация записи индекса из базы (DataStore может отдать
-- разрежённый массив как словарь со строковыми ключами — учитываем оба)
function Shared.normalizeIndex(raw)
	raw = type(raw) == "table" and raw or {}
	local rawSlots = type(raw.slots) == "table" and raw.slots or {}
	local out = {
		slots = {}, -- [i] = { name, savedAt } или nil (пусто)
		access = (raw.access == Shared.ACCESS_FRIENDS) and Shared.ACCESS_FRIENDS or Shared.ACCESS_EVERYONE,
		activeSlot = math.clamp(math.floor(tonumber(raw.activeSlot) or 1), 1, Shared.MAX_SLOTS),
	}
	for i = 1, Shared.MAX_SLOTS do
		local s = rawSlots[i]
		if type(s) ~= "table" then s = rawSlots[tostring(i)] end
		if type(s) == "table" then
			out.slots[i] = {
				name = tostring(s.name or ("Слот " .. i)),
				savedAt = math.max(0, math.floor(tonumber(s.savedAt) or 0)),
			}
		end
	end
	return out
end

-- имя слота по умолчанию
function Shared.defaultSlotName(slot)
	return "Слот " .. slot
end

return Shared
