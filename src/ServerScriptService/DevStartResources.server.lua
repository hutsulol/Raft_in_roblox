-- DevStartResources.server.lua
-- DEV ONLY: Gives starting resources for testing. Delete or disable before release.

local ENABLED = true -- Set to false to disable

if not ENABLED then return end

local START_LOG = 200
local START_PLASTIC = 200

local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	-- Wait for inventory system to initialize
	task.wait(2)

	if _G.GetInventory then
		local inv = _G.GetInventory(player)
		inv.Log = (inv.Log or 0) + START_LOG
		inv.Plastic = (inv.Plastic or 0) + START_PLASTIC

		if _G.SendInventory then
			_G.SendInventory(player)
		end
	end
end)
