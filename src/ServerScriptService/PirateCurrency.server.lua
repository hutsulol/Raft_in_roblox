-- PirateCurrency.server.lua
-- Валюта «Pirate» — монеты, выпадающие с уничтоженных кораблей (и для покупок,
-- напр. меню яйца). Хранится как АТРИБУТ игрока player:GetAttribute("Pirate") —
-- автоматически реплицируется на клиент. Глобальный API для других систем:
--   _G.GetPirate(player)      -> number
--   _G.AddPirate(player, n)   -> новое значение
--   _G.SpendPirate(player, n) -> true, если хватило и списали; иначе false

local Players = game:GetService("Players")

local ATTR = "Pirate"
local START = 0

-- Сколько монет реально НАЧИСЛЕНО за эту сессию (только через AddPirate).
-- PirateProgression читает этот счётчик при загрузке базы, чтобы не потерять
-- монеты, заработанные до завершения GetAsync. Раньше он брал сам атрибут —
-- и если атрибут уже содержал баланс из базы (второй загрузчик/дубликат
-- скрипта), баланс УДВАИВАЛСЯ каждую сессию.
local sessionEarned = {} -- [player] = number
--[[ ⚠️ ТРАТЫ СЧИТАЕМ ТОЖЕ, И НЕ РАДИ СТАТИСТИКИ.
     Имея начисленное и потраченное, любой момент времени можно проверить
     арифметикой: баланс обязан быть равен «база из DataStore + заработано −
     потрачено». Всё, что не сходится, — это чужая запись в атрибут мимо этих
     ручек, и именно так ловится удвоение баланса (см. сторож в
     PirateProgression.server.lua). ]]
local sessionSpent = {} -- [player] = number

local function ensure(player)
	if player:GetAttribute(ATTR) == nil then
		player:SetAttribute(ATTR, START)
	end
end

Players.PlayerAdded:Connect(ensure)
for _, p in ipairs(Players:GetPlayers()) do
	ensure(p)
end

Players.PlayerRemoving:Connect(function(player)
	sessionEarned[player] = nil
	sessionSpent[player] = nil
end)

_G.GetPirate = function(player)
	return player:GetAttribute(ATTR) or 0
end

_G.AddPirate = function(player, n)
	n = n or 0
	local v = (player:GetAttribute(ATTR) or 0) + n
	player:SetAttribute(ATTR, v)
	if n > 0 then
		sessionEarned[player] = (sessionEarned[player] or 0) + n
	end
	return v
end

_G.GetSessionEarnedPirate = function(player)
	return sessionEarned[player] or 0
end

_G.GetSessionSpentPirate = function(player)
	return sessionSpent[player] or 0
end

--[[ Баланс выставили вручную (админская кнопка в настройках) — прежние счётчики
     к новому числу отношения не имеют, иначе сторож баланса примет установку за
     чужую запись и откатит её. ]]
_G.ResetPirateSessionCounters = function(player)
	sessionEarned[player] = 0
	sessionSpent[player] = 0
end

_G.SpendPirate = function(player, n)
	n = n or 0
	local have = player:GetAttribute(ATTR) or 0
	if have < n then
		return false
	end
	player:SetAttribute(ATTR, have - n)
	if n > 0 then
		sessionSpent[player] = (sessionSpent[player] or 0) + n
	end
	return true
end
