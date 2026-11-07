-- ServerScriptService/BuildingUpgradeServer (Script)
-- Каждая постройка — Model с атрибутами:
--   BuildingName (string), Level (number), OwnerUserId (number), Building (bool, сборка идёт)
-- Тег CollectionService "UpgradableBuilding". Клиент шлёт Remotes.UpgradeBuilding:FireServer(model).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Data = require(ReplicatedStorage:WaitForChild("BuildingUpgradeData"))

local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"; remotes.Parent = ReplicatedStorage
local Upgrade = remotes:FindFirstChild("UpgradeBuilding") or Instance.new("RemoteEvent")
Upgrade.Name = "UpgradeBuilding"; Upgrade.Parent = remotes

-- TODO: заменить на свою систему валюты
local function getCoins(player) local ls = player:FindFirstChild("leaderstats"); return ls and ls:FindFirstChild("Coins") end

Upgrade.OnServerEvent:Connect(function(player, model)
	if typeof(model) ~= "Instance" or not CollectionService:HasTag(model, "UpgradableBuilding") then return end
	if model:GetAttribute("OwnerUserId") ~= player.UserId then return end
	if model:GetAttribute("Building") then return end
	local lvl = model:GetAttribute("Level") or 0
	if lvl >= Data.MaxLevel then return end
	local cost = Data.Costs[lvl]
	local coins = getCoins(player)
	if not coins or coins.Value < cost then return end

	coins.Value -= cost
	model:SetAttribute("Building", true)
	model:SetAttribute("BuildStart", workspace:GetServerTimeNow())
	task.delay(Data.BuildTime, function()
		model:SetAttribute("Level", lvl + 1)
		model:SetAttribute("Building", false)
		-- TODO: сохранить уровень (DataStore), сменить модель здания на следующий уровень
	end)
end)

-- Множитель для расчёта прибыли где-то в экономике:
-- local mult = Data.Mults[model:GetAttribute("Level") or 0]
