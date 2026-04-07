-- StartingResources.server.lua
-- DEV ONLY: Gives starting resources for testing. Delete or disable before release.

local ENABLED = true -- Set to false to disable

if not ENABLED then return end

local START_LOG = 200
local START_PLASTIC = 0
local START_STONE = 60
local START_LEAVES = 60

local Players = game:GetService("Players")

-- Wait for inventory system to be ready
while not _G.GetInventory do
	task.wait(0.5)
end

local function giveStartResources(player)
	task.wait(3)

	local inv = _G.GetInventory(player)
	if START_LOG > 0 then inv.Log = (inv.Log or 0) + START_LOG end
	if START_PLASTIC > 0 then inv.Plastic = (inv.Plastic or 0) + START_PLASTIC end
	if START_STONE > 0 then inv.Stone = (inv.Stone or 0) + START_STONE end
	if START_LEAVES > 0 then inv.Leaves = (inv.Leaves or 0) + START_LEAVES end

	if _G.SendInventory then
		_G.SendInventory(player)
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(giveStartResources, player)
end)

for _, player in Players:GetPlayers() do
	task.spawn(giveStartResources, player)
end
