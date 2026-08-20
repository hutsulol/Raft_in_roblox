local ReplicatedStorage = game:GetService("ReplicatedStorage")

local event = ReplicatedStorage:FindFirstChild("CoinRain")
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "CoinRain"
	event.Parent = ReplicatedStorage
end

function _G.PlayCoinRainFor(player, count)
	if typeof(player) == "Instance" and player:IsA("Player") then
		event:FireClient(player, count)
	end
end
