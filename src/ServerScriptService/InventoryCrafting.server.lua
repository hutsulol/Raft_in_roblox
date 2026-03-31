local rs = game:GetService("ReplicatedStorage")

local inventoryCraftEvent = rs:FindFirstChild("InventoryCraft")
if not inventoryCraftEvent then
	inventoryCraftEvent = Instance.new("RemoteEvent")
	inventoryCraftEvent.Name = "InventoryCraft"
	inventoryCraftEvent.Parent = rs
end

local recipes = {
	{
		name = "Wooden_Spear",
		displayName = "Wooden Spear",
		icon = "rbxassetid://110032041583533",
		costs = {Log = 10},
		craftType = "tool",
		category = "Tools",
		description = "A sharp wooden spear for fighting off pirates and defending your raft.",
	},
	{
		name = "WorkBench",
		displayName = "Work Bench",
		icon = "rbxassetid://110032041583533",
		costs = {Log = 3},
		craftType = "place",
		category = "Technology",
		description = "A workbench that allows crafting of advanced items when placed on the raft.",
	},
	{
		name = "Hammer",
		displayName = "Hammer",
		icon = "rbxassetid://110032041583533",
		costs = {Log = 1},
		craftType = "tool",
		category = "Tools",
		description = "Used to build and expand your raft with new floor tiles.",
	},
	{
		name = "Machete",
		displayName = "Machete",
		icon = "rbxassetid://110032041583533",
		costs = {Log = 1},
		craftType = "tool",
		category = "Tools",
		description = "A sharp blade for close combat against enemies.",
	},
	{
		name = "Cup",
		displayName = "Cup",
		icon = "rbxassetid://110032041583533",
		costs = {Plastic = 2},
		craftType = "tool",
		initAttributes = {CupState = "empty"},
		category = "Misc",
		description = "A cup for scooping ocean water. Fill it, purify it, and drink to quench your thirst.",
	},
	{
		name = "Destitalor",
		displayName = "Water Purifier",
		icon = "rbxassetid://110032041583533",
		costs = {Plastic = 4},
		craftType = "tool",
		category = "Technology",
		description = "Purifies saltwater into drinkable fresh water. Place on your raft to use.",
	},
	{
		name = "bush",
		displayName = "Grape Bush",
		icon = "rbxassetid://97055584624105",
		costs = {Log = 1},
		craftType = "placeable",
		category = "Technology",
		description = "A grape bush that grows berries every 20 seconds. Place on your raft and click to harvest.",
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
	for item, amount in recipe.costs do
		if (inv[item] or 0) < amount then
			return
		end
	end

	for item, amount in recipe.costs do
		inv[item] = inv[item] - amount
	end

	local template = rs:FindFirstChild(recipe.name)

	if recipe.craftType == "tool" then
		if template then
			local cloned = template:Clone()
			local tool

			if cloned:IsA("Tool") then
				tool = cloned
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

			-- Set initial attributes if defined
			if recipe.initAttributes then
				for attr, val in recipe.initAttributes do
					tool:SetAttribute(attr, val)
				end
			end
			local backpack = player:FindFirstChild("Backpack")
			if backpack then
				tool.Parent = backpack
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

		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			tool.Parent = backpack
		end

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

	inventoryCraftEvent:FireClient(player, "success", recipe.name)
end)
