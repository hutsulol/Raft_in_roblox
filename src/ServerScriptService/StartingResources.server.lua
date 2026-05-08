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
while not _G.AddResourceToInventory do
	task.wait(0.5)
end

local function giveStartResources(player)
	task.wait(3)

	-- silent=true on the initial spawn grants — these aren't "pickup"
	-- events from the player's perspective and would spawn 4 cards
	-- the moment they join.
	if START_LOG > 0 then _G.AddResourceToInventory(player, "Log", START_LOG, nil, true) end
	if START_PLASTIC > 0 then _G.AddResourceToInventory(player, "Plastic", START_PLASTIC, nil, true) end
	if START_STONE > 0 then _G.AddResourceToInventory(player, "Stone", START_STONE, nil, true) end
	if START_LEAVES > 0 then _G.AddResourceToInventory(player, "Leaves", START_LEAVES, nil, true) end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(giveStartResources, player)
end)

for _, player in Players:GetPlayers() do
	task.spawn(giveStartResources, player)
end
