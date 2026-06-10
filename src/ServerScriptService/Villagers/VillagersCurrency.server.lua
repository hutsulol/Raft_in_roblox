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

--====================================================
-- Награда за зачистку острова (+жители)
--====================================================
-- Клиентская анимация «Остров зачищен!» в момент кадра-1 просит начислить жителей.
-- ВРЕМЕННО клиент-инициировано (тест-кнопкой): когда появится реальный СЕРВЕРНЫЙ
-- триггер зачистки, награду должен выдавать он, а этот обработчик — закрыть/убрать
-- (иначе эксплойт «бесконечные жители»). Пока — кулдаун на игрока против спама.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ISLAND_REWARD_VILLAGERS = 5
local ISLAND_REWARD_COOLDOWN  = 20

local rewardRemote = ReplicatedStorage:FindFirstChild("IslandClearedReward")
if not rewardRemote then
	rewardRemote = Instance.new("RemoteEvent")
	rewardRemote.Name = "IslandClearedReward"
	rewardRemote.Parent = ReplicatedStorage
end

local lastReward = {}
rewardRemote.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if lastReward[player] and now - lastReward[player] < ISLAND_REWARD_COOLDOWN then
		return
	end
	lastReward[player] = now
	_G.AddVillagers(player, ISLAND_REWARD_VILLAGERS)
end)

Players.PlayerRemoving:Connect(function(player)
	lastReward[player] = nil
end)
