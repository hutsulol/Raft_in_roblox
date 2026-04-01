-- DevStartResources.server.lua
-- DEV ONLY: Gives starting resources for testing. Delete or disable before release.

local ENABLED = true -- Set to false to disable

if not ENABLED then return end

local START_LOG = 200
local START_PLASTIC = 200

local Players = game:GetService("Players")

-- Wait for inventory system to be ready
while not _G.GetInventory do
	task.wait(0.5)
end

Players.PlayerAdded:Connect(function(player)
	-- Wait for player's inventory to be created
	task.wait(3)

	local inv = _G.GetInventory(player)
	inv.Log = (inv.Log or 0) + START_LOG
	inv.Plastic = (inv.Plastic or 0) + START_PLASTIC

	if _G.SendInventory then
		_G.SendInventory(player)
	end
end)

-- Also handle players already in game (in case script loads late)
for _, player in Players:GetPlayers() do
	task.spawn(function()
		task.wait(3)
		local inv = _G.GetInventory(player)
		inv.Log = (inv.Log or 0) + START_LOG
		inv.Plastic = (inv.Plastic or 0) + START_PLASTIC

		if _G.SendInventory then
			_G.SendInventory(player)
		end
	end)
end
