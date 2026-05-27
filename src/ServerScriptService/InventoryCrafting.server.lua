local rs = game:GetService("ReplicatedStorage")

local inventoryCraftEvent = rs:FindFirstChild("InventoryCraft")
if not inventoryCraftEvent then
	inventoryCraftEvent = Instance.new("RemoteEvent")
	inventoryCraftEvent.Name = "InventoryCraft"
	inventoryCraftEvent.Parent = rs
end

local recipes = {
	{
		name = "WorkBench",
		displayName = "Work Bench",
		icon = "rbxassetid://116083064101694",
		costs = {Log = 3},
		craftType = "placeable",
		category = "Technology",
		description = "A workbench that allows crafting of advanced items when placed on the raft.",
	},
	{
		name = "FireCamp",
		displayName = "Campfire",
		icon = "rbxassetid://116083064101694",
		costs = {Log = 1},
		craftType = "placeable",
		category = "Technology",
		description = "A campfire. Place it on your raft, then press E to feed it logs — more logs burn brighter and longer.",
	},
	{
		name = "Hammer",
		displayName = "Hammer",
		icon = "rbxassetid://72168072336946",
		costs = {Log = 1},
		craftType = "tool",
		category = "Tools",
		description = "Used to build and expand your raft with new floor tiles.",
	},
	{
		name = "Machete",
		displayName = "Machete",
		icon = "rbxassetid://92926554091794",
		costs = {Log = 1},
		craftType = "tool",
		category = "Tools",
		description = "A sharp blade for close combat against enemies.",
	},
	{
		name = "Cup",
		displayName = "Cup",
		icon = "rbxassetid://99673504095026",
		costs = {Plastic = 2},
		craftType = "tool",
		initAttributes = {CupState = "empty"},
		category = "Misc",
		description = "A cup for scooping ocean water. Fill it, purify it, and drink to quench your thirst.",
	},
	{
		name = "bag_empty_2",
		displayName = "Empty Bag",
		icon = "rbxassetid://89398456198664",
		costs = {Leaves = 5},
		craftType = "tool",
		category = "Misc",
		description = "An empty woven bag. Fill it with sand or clay on an island.",
	},
	{
		name = "leaf bag",
		displayName = "Leaf Bag",
		icon = "rbxassetid://89398456198664",
		costs = {Leaves = 5},
		craftType = "tool",
		category = "Misc",
		description = "A small leaf bag for storing seeds. Hold it and press E next to a watered tree garden bed to plant.",
	},
	{
		name = "Sand Bag",
		displayName = "Sand Bag",
		icon = "rbxassetid://107012847180882",
		costs = {Leaves = 5},
		craftType = "tool",
		category = "Misc",
		description = "A leaf bag for storing sand. Hold it and press E to inspect, or dig sand with the shovel to fill it up.",
	},
	{
		name = "Destitalor",
		displayName = "Water Purifier",
		icon = "rbxassetid://90221080738714",
		costs = {Plastic = 4},
		craftType = "tool",
		category = "Technology",
		description = "Purifies saltwater into drinkable fresh water. Place on your raft to use.",
	},
	{
		name = "Garden",
		displayName = "Garden Bed",
		icon = "rbxassetid://137766871451752",
		costs = {Log = 4},
		craftType = "placeable",
		category = "Technology",
		description = "A garden bed for planting bushes. Water it with fresh water to let your plants bear fruit.",
	},
	{
		-- Larger variant of the regular Garden Bed, sized to host a
		-- tree. Same placement / R-rotate / raft-weld flow as Garden;
		-- the server handler lives alongside the regular garden in
		-- GardenSystem.server.lua and clones the Bed_T
		-- template from ReplicatedStorage.
		name = "Bed_T",
		displayName = "Tree Garden Bed",
		icon = "rbxassetid://137766871451752",
		costs = {Log = 1},
		craftType = "placeable",
		category = "Technology",
		description = "A larger garden bed sized for growing a tree. Takes up more space on the raft than a regular garden.",
	},
	{
		name = "bush",
		displayName = "Grape Bush",
		icon = "rbxassetid://93957489757544",
		costs = {Log = 1},
		craftType = "placeable",
		category = "Technology",
		description = "A grape bush that grows berries every 20 seconds. Must be planted on a garden bed.",
	},
	{
		name = "Paddle",
		displayName = "Paddle",
		icon = "rbxassetid://93358108538106",
		costs = {Log = 1, Plastic = 3},
		craftType = "tool",
		category = "Tools",
		description = "A paddle to steer and boost your raft. Click where you want to go.",
	},
	{
		name = "Rope",
		displayName = "Rope",
		icon = "rbxassetid://78492721752628",
		costs = {Leaves = 4},
		craftType = "resource",
		category = "Resources",
		description = "A sturdy rope woven from leaves. Used to craft advanced equipment.",
	},
	{
		name = "Wet_Brick",
		displayName = "Wet Brick",
		icon = "rbxassetid://139059474647090",
		costs = {Sand = 2, Clay = 2},
		craftType = "placeable",
		category = "Resources",
		description = "A wet brick made from sand and clay. Place it on the raft and let it dry in the sun.",
	},
	{
		name = "Shovel",
		displayName = "Shovel",
		icon = "rbxassetid://123765089142597",
		costs = {Rope = 1, Stone = 3, Log = 1},
		craftType = "tool",
		category = "Tools",
		description = "A shovel for digging sand and clay on islands.",
	},
	{
		name = "FishingRod",
		displayName = "Fishing Rod",
		icon = "rbxassetid://105180666555503",
		costs = {Log = 3, Rope = 2},
		craftType = "tool",
		category = "Tools",
		description = "Cast your line into the ocean to catch fish for food.",
	},
	{
		name = "Phone",
		displayName = "Phone",
		icon = "rbxassetid://123703470055474",
		costs = {Log = 1},
		craftType = "tool",
		category = "Tools",
		description = "A phone for communication.",
	},
	{
		name = "Injector",
		displayName = "Injector",
		icon = "rbxassetid://81132472504693",
		costs = {Log = 1},
		craftType = "tool",
		category = "Tools",
		description = "A syringe used to hack a downed pirate's mind and recruit them as a mercenary.",
	},
	{
		name = "EmptyCapsule",
		displayName = "Empty Capsule",
		icon = "rbxassetid://116714708119585",
		costs = {Log = 1},
		craftType = "tool",
		category = "Tools",
		description = "An empty capsule for collecting pirate blood with an Injector.",
	},
}

inventoryCraftEvent.OnServerEvent:Connect(function(player, action, data)
	if action == "requestRecipes" then
		local inv = _G.GetInventory and _G.GetInventory(player) or {Log = 0}
		inventoryCraftEvent:FireClient(player, "recipes", recipes, inv)
		return
	end

	if action ~= "craft" then return end
	if typeof(data) ~= "string" then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local recipe = nil
	for _, r in recipes do
		if r.name == data then
			recipe = r
			break
		end
	end
	if not recipe then return end

	local inv = _G.GetInventory and _G.GetInventory(player) or {}

	-- Sand / Clay don't live in the inventory — they're stashed in the
	-- Sand Bag tool. Treat bag units as if they were inventory units
	-- for both the affordability check and the actual deduction below.
	local function availableFor(item)
		local count = inv[item] or 0
		if (item == "Sand" or item == "Clay") and _G.GetBagUnitsFor then
			count = count + _G.GetBagUnitsFor(player, item)
		end
		return count
	end

	for item, amount in recipe.costs do
		if availableFor(item) < amount then
			return
		end
	end

	for item, amount in recipe.costs do
		local remaining = amount
		if (item == "Sand" or item == "Clay") and _G.RemoveBagUnits then
			local fromBag = _G.RemoveBagUnits(player, item, remaining)
			remaining = remaining - fromBag
		end
		if remaining > 0 then
			if _G.RemoveResourceFromInventory then
				_G.RemoveResourceFromInventory(player, item, remaining)
			else
				inv[item] = (inv[item] or 0) - remaining
			end
		end
	end

	-- Templates normally live directly under ReplicatedStorage, but a few
	-- (e.g. FishingRod) are packaged inside ReplicatedStorage.MainModule.
	-- Fall back to a recursive search so recipes don't need to know the path.
	local template = rs:FindFirstChild(recipe.name)
	if not template then
		template = rs:FindFirstChild(recipe.name, true)
	end

	if recipe.craftType == "tool" then
		local tool

		if template then
			local cloned = template:Clone()

			if cloned:IsA("Tool") then
				tool = cloned
				-- Ensure the tool has a Handle (required for Activated to fire)
				if not tool:FindFirstChild("Handle") then
					local firstPart = tool:FindFirstChildWhichIsA("BasePart", true)
					if firstPart then
						firstPart.Name = "Handle"
					end
				end
			else
				-- Wrap Model/BasePart in a Tool so it appears in Backpack
				tool = Instance.new("Tool")
				tool.Name = recipe.name
				tool.CanBeDropped = false

				-- Find or create a Handle part
				if cloned:IsA("Model") then
					local handle = cloned:FindFirstChild("Handle")
					if not handle then
						handle = cloned:FindFirstChildWhichIsA("BasePart", true)
					end
					-- Move all parts into the Tool
					for _, child in cloned:GetChildren() do
						child.Parent = tool
					end
					-- Ensure one part is named Handle
					if handle and handle.Name ~= "Handle" then
						handle.Name = "Handle"
					end
				elseif cloned:IsA("BasePart") then
					cloned.Name = "Handle"
					cloned.Parent = tool
				end

				cloned:Destroy()
			end
		else
			-- No template in ReplicatedStorage — build a minimal placeholder
			-- Tool so the item still appears in the backpack with its icon.
			tool = Instance.new("Tool")
			tool.Name = recipe.name
			tool.CanBeDropped = false
			local handle = Instance.new("Part")
			handle.Name = "Handle"
			handle.Size = Vector3.new(1, 1, 1)
			handle.Transparency = 1
			handle.Parent = tool
		end

		if tool then
			if recipe.initAttributes then
				for attr, val in recipe.initAttributes do
					tool:SetAttribute(attr, val)
				end
			end
			if recipe.icon and tool.TextureId == "" then
				tool.TextureId = recipe.icon
			end
			if _G.GiveToolOrDrop then
				_G.GiveToolOrDrop(player, tool)
			else
				local backpack = player:FindFirstChild("Backpack")
				if backpack then tool.Parent = backpack end
			end
		end
	elseif recipe.craftType == "placeable" then
		-- Create a small placeholder tool (the full model is cloned on placement)
		local tool = Instance.new("Tool")
		tool.Name = recipe.name
		tool.CanBeDropped = false
		if recipe.icon then
			tool.TextureId = recipe.icon
		end

		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(1, 1, 1)
		handle.Transparency = 1
		handle.Parent = tool

		if _G.GiveToolOrDrop then
			_G.GiveToolOrDrop(player, tool)
		else
			local backpack = player:FindFirstChild("Backpack")
			if backpack then tool.Parent = backpack end
		end

	elseif recipe.craftType == "resource" then
		-- Route through AddResourceToInventory so full-inventory
		-- overflow spills to the ground instead of being silently stored.
		_G.AddResourceToInventory(player, recipe.name, 1, nil)

	elseif recipe.craftType == "place" then
		if template then
			local clone = template:Clone()
			local raft = workspace:FindFirstChild("Raft")
			if raft and raft.PrimaryPart then
				local raftPos = raft.PrimaryPart.Position
				clone:PivotTo(CFrame.new(raftPos + Vector3.new(0, 5, 0)))
			else
				local hrp = char:FindFirstChild("HumanoidRootPart")
				clone:PivotTo(CFrame.new(hrp.Position + hrp.CFrame.LookVector * 5))
			end
			clone.Parent = workspace
		end
	end

	if _G.SendInventory then
		_G.SendInventory(player)
	end

	-- Quest hook (Phase I): credit any "crafted:<name>" objectives. We
	-- fire the recipe name verbatim so future quests that gate on a
	-- new recipe just need to add it to the catalog without touching
	-- this dispatch.
	if typeof(_G.OnQuestEvent) == "function" then
		pcall(_G.OnQuestEvent, player, "crafted:" .. recipe.name, 1)
	end

	inventoryCraftEvent:FireClient(player, "success", recipe.name)
end)
