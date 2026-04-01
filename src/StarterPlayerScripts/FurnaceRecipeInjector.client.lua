-- FurnaceRecipeInjector.client.lua
-- Injects the Furnace recipe into the workbench UI recipe list

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local craftEvent = ReplicatedStorage:WaitForChild("CraftItem")

local FURNACE_RECIPE = {
	name = "Furnace",
	displayName = "Furnace",
	icon = "rbxassetid://110032041583533", -- placeholder, will show model in workbench
	costs = {Stone = 10, Log = 5},
	craftType = "placeable",
}

local injected = false

craftEvent.OnClientEvent:Connect(function(action, data, inv)
	if action ~= "recipes" then return end
	if not data or typeof(data) ~= "table" then return end

	-- Check if Furnace already in list
	for _, r in data do
		if r.name == "Furnace" then
			injected = true
			return
		end
	end

	-- Inject
	table.insert(data, FURNACE_RECIPE)
	injected = true
end)
