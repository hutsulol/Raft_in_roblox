-- FoodSystem.server.lua
-- Lets the player "take fruit in hand" and eat it for hunger + HP.
-- Mirrors the seed-as-Tool pattern from SeedToolSystem (now retired):
-- the resource lives in the main inventory as a stack, clicking the
-- slot temporarily promotes one unit into a Tool, and an unconsumed
-- Tool returns to the stack on unequip.
--
-- Per-fruit hunger / HP values live in FOOD_DATA — extend that table
-- to add new consumables (cooked fish, jelly, etc.) without
-- touching the equip logic.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOOD_DATA = {
	Banana    = { hunger = 15, hp = 5 },
	Coconut   = { hunger = 25, hp = 5 },
	Pineapple = { hunger = 20, hp = 5 },
}

local equipEvent = ReplicatedStorage:FindFirstChild("EquipFoodAsTool")
if not equipEvent then
	equipEvent = Instance.new("RemoteEvent")
	equipEvent.Name = "EquipFoodAsTool"
	equipEvent.Parent = ReplicatedStorage
end

while not _G.AddResourceToInventory or not _G.RemoveResourceFromInventory or not _G.GetInventory do
	task.wait(0.1)
end

local function findFoodTemplate(foodName)
	-- Prefer a user-authored Tool template (so the in-world visual
	-- matches) — direct lookup first, then a recursive sweep so the
	-- template can live inside Trees_Grow or any other folder.
	local hit = ReplicatedStorage:FindFirstChild(foodName)
	if hit and hit:IsA("Tool") then return hit end
	hit = ReplicatedStorage:FindFirstChild(foodName, true)
	if hit and hit:IsA("Tool") then return hit end
	return nil
end

local function makeFoodTool(foodName)
	local template = findFoodTemplate(foodName)
	if template then
		local clone = template:Clone()
		clone.Name = foodName
		return clone
	end
	-- Placeholder Tool — invisible Handle so the equip mechanic still
	-- works even when no model has been authored yet. The icon shows
	-- up correctly in the hotbar via TOOL_ICONS in InventoryUI.
	local tool = Instance.new("Tool")
	tool.Name = foodName
	local handle = Instance.new("Part")
	handle.Name         = "Handle"
	handle.Size         = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.CanCollide   = false
	handle.Massless     = true
	handle.Parent       = tool
	return tool
end

local function alreadyHoldingFood(player, foodName)
	local char     = player.Character
	local backpack = player:FindFirstChild("Backpack")
	for _, container in ipairs({ char, backpack }) do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child.Name == foodName and child:GetAttribute("FoodResource") == foodName then
					return true
				end
			end
		end
	end
	return false
end

local function refundFood(player, tool)
	if not tool or tool:GetAttribute("Refunded") or tool:GetAttribute("Consumed") then
		if tool then tool:Destroy() end
		return
	end
	tool:SetAttribute("Refunded", true)
	local foodName = tool:GetAttribute("FoodResource")
	if foodName and player and player.Parent then
		_G.AddResourceToInventory(player, foodName, 1, nil, true)
	end
	tool:Destroy()
end

equipEvent.OnServerEvent:Connect(function(player, foodName)
	if typeof(foodName) ~= "string" then return end
	local data = FOOD_DATA[foodName]
	if not data then return end

	local inv = _G.GetInventory(player)
	if (inv[foodName] or 0) < 1 then return end

	if alreadyHoldingFood(player, foodName) then return end

	local char     = player.Character
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	_G.RemoveResourceFromInventory(player, foodName, 1)
	if _G.SendInventory then
		_G.SendInventory(player)
	end

	local tool = makeFoodTool(foodName)
	tool:SetAttribute("FoodResource", foodName)
	tool:SetAttribute("OwnerUserId", player.UserId)
	tool.CanBeDropped = false

	tool.Parent = backpack

	-- Force-equip — drop whatever's currently held and put the fruit
	-- in the player's hand. Without this the new Tool just parks in
	-- Backpack and the player thinks the click did nothing.
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function() humanoid:UnequipTools() end)
		pcall(function() humanoid:EquipTool(tool) end)
	end

	-- Refund guard arms on first Equipped — the Backpack→Character
	-- shuffle EquipTool just performed otherwise looks like an
	-- unequip and triggers a false refund.
	tool.Equipped:Once(function()
		tool:SetAttribute("Ready", true)
	end)

	tool.Activated:Connect(function()
		-- Player clicked while holding the fruit → eat one.
		-- Mark Consumed BEFORE Destroy so the AncestryChanged hook
		-- knows the spend was intentional.
		if tool:GetAttribute("Consumed") then return end
		tool:SetAttribute("Consumed", true)
		_G.RestoreHunger(player, data.hunger, data.hp)
		tool:Destroy()
	end)

	tool.AncestryChanged:Connect(function(_, newParent)
		if not tool:GetAttribute("Ready") then return end
		if tool:GetAttribute("Consumed") then return end
		if newParent == nil then
			task.defer(function() refundFood(player, tool) end)
		elseif newParent and newParent:IsA("Backpack") then
			task.defer(function() refundFood(player, tool) end)
		end
	end)
end)
