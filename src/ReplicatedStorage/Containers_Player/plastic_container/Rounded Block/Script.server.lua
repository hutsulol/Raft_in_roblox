local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local cooler = script.Parent
local prompt = cooler:FindFirstChildOfClass("ProximityPrompt")

-- Common drinks (loser ones)
local drinks = {
	"BloxyCola",
	"WitchesBrew",
	"ChocolateMilk"
}

-- Rare item table low to highest
local rareItems = {
	{ name = "RollingPin", chance = 0.1 },
	{ name = "MashPotion", chance = 1 },
	{ name = "EpicSauce", chance = 10 }
}

-- Count how many drink-type items the player already has
local function countDrinks(player)
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return 0 end

	local count = 0
	for _, tool in pairs(backpack:GetChildren()) do
		if tool:IsA("Tool") then
			local name = tool.Name
			if name == "BloxyCola" or name == "WitchesBrew" or name == "ChocolateMilk"
				or name == "EpicSauce" or name == "MashPotion" or name == "RollingPin" then
				count += 1
			end
		end
	end
	return count
end

prompt.Triggered:Connect(function(player)
	if countDrinks(player) >= 2 then return end

	-- Roll a number from 0.1 to 100
	local roll = math.random() * 100
	local cumulative = 0

	for _, item in ipairs(rareItems) do
		cumulative += item.chance
		if roll <= cumulative then
			local tool = ServerStorage:FindFirstChild(item.name)
			if tool then
				local clone = tool:Clone()
				clone.CanBeDropped = false
				clone.Parent = player:FindFirstChild("Backpack")
			end
			return
		end
	end

	--  give normal drink
	local drinkName = drinks[math.random(1, #drinks)]
	local drink = ServerStorage:FindFirstChild(drinkName)
	if drink then
		local clone = drink:Clone()
		clone.CanBeDropped = false
		clone.Parent = player:FindFirstChild("Backpack")
	end
end)
