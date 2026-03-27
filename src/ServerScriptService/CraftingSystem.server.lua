local rs = game:GetService("ReplicatedStorage")

local WORKBENCH_RANGE = 15

local craftEvent = rs:FindFirstChild("CraftItem")
if not craftEvent then
	craftEvent = Instance.new("RemoteEvent")
	craftEvent.Name = "CraftItem"
	craftEvent.Parent = rs
end

local recipes = {
	{
		name = "Wood_Knife",
		displayName = "Wood Knife",
		icon = "rbxassetid://110032041583533",
		costs = {Log = 2},
		model = "Wood_Knife",
	},
}

local function findWorkBench()
	for _, v in workspace:GetDescendants() do
		if v:IsA("Model") and v.Name == "WorkBench" then
			return v
		end
	end
	return nil
end

local function getWorkBenchPos()
	local wb = findWorkBench()
	if not wb then return nil end
	if wb.PrimaryPart then
		return wb.PrimaryPart.Position
	end
	local part = wb:FindFirstChildWhichIsA("BasePart", true)
	if part then
		return part.Position
	end
	return wb:GetPivot().Position
end

craftEvent.OnServerEvent:Connect(function(player, action, data)
	if action == "requestRecipes" then
		local inv = _G.GetInventory and _G.GetInventory(player) or {Log = 0}
		craftEvent:FireClient(player, "recipes", recipes, inv)
		return
	end

	if action ~= "craft" then return end
	if typeof(data) ~= "string" then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local wbPos = getWorkBenchPos()
	if not wbPos then return end

	local dist = (char.HumanoidRootPart.Position - wbPos).Magnitude
	if dist > WORKBENCH_RANGE then return end

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

	local template = rs:FindFirstChild(recipe.model)
	if template then
		local tool = template:Clone()
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			tool.Parent = backpack
		end
	end

	if _G.SendInventory then
		_G.SendInventory(player)
	end

	craftEvent:FireClient(player, "success", recipe.name)
end)
