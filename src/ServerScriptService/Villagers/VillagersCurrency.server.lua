-- VillagersCurrency.server.lua
-- Валюта «жители/наёмники» (Villagers): население острова, которое тратится на
-- постройку/прокачку пассивных ферм. Пока системы захвата островов нет — у каждого
-- игрока по стандарту START_VILLAGERS (20).
--
-- Хранится как АТРИБУТ игрока player:GetAttribute("Villagers") — он автоматически
-- реплицируется на клиент (HUD читает его). Глобальный API для других серверных
-- систем (борд фермы и т.п.):
--   _G.GetVillagers(player)        -> number
--   _G.AddVillagers(player, n)     -> новое значение
--   _G.SpendVillagers(player, n)   -> true, если хватило и списали; иначе false

local Players = game:GetService("Players")

local START_VILLAGERS = 20

local function ensure(player)
	if player:GetAttribute("Villagers") == nil then
		player:SetAttribute("Villagers", START_VILLAGERS)
	end
end

Players.PlayerAdded:Connect(ensure)
for _, p in ipairs(Players:GetPlayers()) do
	ensure(p)
end

_G.GetVillagers = function(player)
	return player:GetAttribute("Villagers") or 0
end

_G.AddVillagers = function(player, n)
	local v = (player:GetAttribute("Villagers") or 0) + (n or 0)
	player:SetAttribute("Villagers", v)
	return v
end

_G.SpendVillagers = function(player, n)
	n = n or 0
	local have = player:GetAttribute("Villagers") or 0
	if have < n then
		return false
	end
	player:SetAttribute("Villagers", have - n)
	return true
end
