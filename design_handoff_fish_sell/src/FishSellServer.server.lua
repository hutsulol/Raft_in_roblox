-- ServerScriptService/FishSellServer (Script)
-- Пример: при продаже улова сервер роллит рыбу, начисляет pirate и шлёт попап клиенту.
-- Подключите SellFish() к своей механике рыбалки или продажи.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FishData = require(ReplicatedStorage:WaitForChild("FishData"))

local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"; remotes.Parent = ReplicatedStorage
local FishSold = remotes:FindFirstChild("FishSold") or Instance.new("RemoteEvent")
FishSold.Name = "FishSold"; FishSold.Parent = remotes

local rng = Random.new()

local function SellFish(player: Player)
	local res = FishData.Roll(rng)
	-- TODO: начислить валюту своим способом (DataStore / leaderstats)
	local ls = player:FindFirstChild("leaderstats")
	local cur = ls and ls:FindFirstChild("Pirate")
	if cur then cur.Value += res.pay end
	FishSold:FireClient(player, res.fishId, res.weight, res.pay)
	return res
end

return SellFish
