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
	},
	{
		name = "WorkBench",
		displayName = "Work Bench",
		icon = "rbxassetid://110032041583533",
		costs = {Log = 3},
		craftType = "place",
	},
	{
		name = "Hammer",
		displayName = "Hammer",
		icon = "rbxassetid://110032041583533",
		costs = {Log = 1},
		craftType = "tool",
	},
	{
		name = "Machete",
		displayName = "Machete",
		icon = "rbxassetid://110032041583533",
		costs = {Log = 1},
		craftType = "tool",
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
			local tool = template:Clone()
			local backpack = player:FindFirstChild("Backpack")
			if backpack then
				tool.Parent = backpack
			end
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
