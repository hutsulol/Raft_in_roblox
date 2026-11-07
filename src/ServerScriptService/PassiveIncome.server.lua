--[[
	ПАССИВНЫЙ ДОХОД — НАЧИСЛЕНИЕ РАЗ В ИГРОВОЙ ЧАС (хендофф HANDOFF.md, разд. 2, 6).

	Вышка и ферма больше не платят игроку в момент действия: монеты и нефть
	копятся здесь в «ожидающем» пуле и выдаются ровно на границе игрового часа
	(Lighting.ClockTime переходит через целое). Тогда же клиенту летит
	HourlyIncome(money, oilMl) — и HUD рисует всплывашку под временем.

	⚠️ ЧАСЫ ОБЩИЕ. День 6→18 идёт 380 реальных секунд, ночь 18→6 — 120
	(DayNightCircle), то есть ночной час короче дневного втрое. Границу берём по
	ClockTime, а не по своему таймеру — иначе всплывашка разошлась бы с часами.

		_G.PassiveIncomeAdd(player, moneyCoins, oilMl)   -- положить в пул
		_G.PassiveIncomePending(player)                  -- сколько накопилось
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Lighting          = game:GetService("Lighting")
local Workspace         = game:GetService("Workspace")

local OilCanister = nil
pcall(function() OilCanister = require(ReplicatedStorage:WaitForChild("OilCanister", 5)) end)

local LOG = "[Доход]"

local remote = ReplicatedStorage:FindFirstChild("HourlyIncome")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "HourlyIncome"
	remote.Parent = ReplicatedStorage
end

local pending = {}   -- [player] = { money = float, oil = float }

local function pool(player)
	local p = pending[player]
	if not p then p = { money = 0, oil = 0 }; pending[player] = p end
	return p
end

_G.PassiveIncomeAdd = function(player, money, oilMl)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
	local p = pool(player)
	p.money += tonumber(money) or 0
	p.oil += tonumber(oilMl) or 0
	return true
end

_G.PassiveIncomePending = function(player)
	local p = pending[player]
	return p and p.money or 0, p and p.oil or 0
end

-- нефть — в ту же бочку на плоту, что и канистры (тот же атрибут, что у вышки)
local function addOil(ml)
	if not OilCanister then return false end
	local tank = OilCanister.findTank(Workspace)
	if not tank then return false end
	local have = OilCanister.tankStored(tank)
	tank:SetAttribute(OilCanister.TANK_ATTR, math.min(OilCanister.TANK_CAPACITY, have + ml))
	return true
end

-- ⚠️ ВЫДАЁМ ЦЕЛЫЕ, ХВОСТ ОСТАВЛЯЕМ. Дробная часть остаётся в пуле до следующего
-- часа — так за сутки набегает ровно столько, сколько накопилось, без потерь на
-- округлении.
local function flush(player)
	local p = pending[player]
	if not p or not player.Parent then return end
	local money = math.floor(p.money)
	local oil = math.floor(p.oil)
	if money <= 0 and oil <= 0 then return end
	p.money -= money
	p.oil -= oil
	if money > 0 and typeof(_G.AddPirate) == "function" then pcall(_G.AddPirate, player, money) end
	if oil > 0 then addOil(oil) end
	remote:FireClient(player, money, oil)
	print(("%s %s: +%d пиратов, +%d мл нефти (час %d)"):format(LOG, player.Name, money, oil, math.floor(Lighting.ClockTime)))
end

Players.PlayerRemoving:Connect(function(player) pending[player] = nil end)

-- граница часа по общим часам
local lastHour = math.floor(Lighting.ClockTime)
RunService.Heartbeat:Connect(function()
	local hour = math.floor(Lighting.ClockTime)
	if hour == lastHour then return end
	lastHour = hour
	for _, plr in ipairs(Players:GetPlayers()) do
		flush(plr)
	end
end)

print(LOG .. " готов: монеты и нефть от построек выдаются раз в игровой час (_G.PassiveIncomeAdd)")
