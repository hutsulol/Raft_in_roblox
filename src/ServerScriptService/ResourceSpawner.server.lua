local CollectionService = game:GetService("CollectionService")
local rs = game:GetService("ReplicatedStorage")

local CLICKS_TO_COLLECT = 5
local LIFETIME = 120
local WORKBENCH_RANGE = 15

local collectEvent = rs:FindFirstChild("CollectResource")
if not collectEvent then
	collectEvent = Instance.new("RemoteEvent")
	collectEvent.Name = "CollectResource"
	collectEvent.Parent = rs
end

local collectNotify = rs:FindFirstChild("CollectNotify")
if not collectNotify then
	collectNotify = Instance.new("RemoteEvent")
	collectNotify.Name = "CollectNotify"
	collectNotify.Parent = rs
end

local craftEvent = rs:FindFirstChild("CraftItem")
if not craftEvent then
	craftEvent = Instance.new("RemoteEvent")
	craftEvent.Name = "CraftItem"
	craftEvent.Parent = rs
end

local inventoryEvent = rs:FindFirstChild("InventoryUpdate")
if not inventoryEvent then
	inventoryEvent = Instance.new("RemoteEvent")
	inventoryEvent.Name = "InventoryUpdate"
	inventoryEvent.Parent = rs
end

local inventories = {}
local clickCounts = {}

local recipes = {
	{
		name = "Wood_Knife",
		displayName = "Wood Knife",
		icon = "rbxassetid://110032041583533",
		costs = {Log = 2},
		model = "Wood_Knife",
	},
}

local function getInventory(player)
	if not inventories[player] then
		inventories[player] = {Log = 0}
	end
	return inventories[player]
end

local function sendInventory(player)
	inventoryEvent:FireClient(player, getInventory(player), recipes)
end

local function getBoat()
	for _, v in pairs(workspace:GetChildren()) do
		if v:IsA("Model") and v.PrimaryPart then
			if not CollectionService:HasTag(v, "Resource") then
				return v
			end
		end
	end
end

local function getResourceFromPart(part)
	if CollectionService:HasTag(part, "Resource") then
		return part
	end

	local model = part:FindFirstAncestorOfClass("Model")
	if model and CollectionService:HasTag(model, "Resource") then
		return model
	end

	return nil
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	inventories[player] = nil
end)

collectEvent.OnServerEvent:Connect(function(player, targetPart)
	if typeof(targetPart) ~= "Instance" then return end
	if not targetPart:IsDescendantOf(workspace) then return end

	local resource = getResourceFromPart(targetPart)
	if not resource then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local resourcePos
	if resource:IsA("Model") then
		resourcePos = resource:GetPivot().Position
	else
		resourcePos = resource.Position
	end

	local dist = (char.HumanoidRootPart.Position - resourcePos).Magnitude
	if dist > 50 then return end

	if not clickCounts[resource] then
		clickCounts[resource] = {}
	end

	if not clickCounts[resource][player] then
		clickCounts[resource][player] = 0
	end

	clickCounts[resource][player] = clickCounts[resource][player] + 1
	local clicks = clickCounts[resource][player]

	collectNotify:FireClient(player, "progress", resource, clicks, CLICKS_TO_COLLECT)

	if clicks >= CLICKS_TO_COLLECT then
		clickCounts[resource] = nil
		local inv = getInventory(player)
		inv.Log = (inv.Log or 0) + 1
		collectNotify:FireClient(player, "collected", resource)
		sendInventory(player)
		resource:Destroy()
	end
end)

craftEvent.OnServerEvent:Connect(function(player, recipeName)
	if typeof(recipeName) ~= "string" then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local workbench = workspace:FindFirstChild("Workbench")
	if not workbench then return end

	local wbPos
	if workbench:IsA("Model") and workbench.PrimaryPart then
		wbPos = workbench.PrimaryPart.Position
	elseif workbench:IsA("Model") then
		wbPos = workbench:GetPivot().Position
	elseif workbench:IsA("BasePart") then
		wbPos = workbench.Position
	else
		return
	end

	local dist = (char.HumanoidRootPart.Position - wbPos).Magnitude
	if dist > WORKBENCH_RANGE then return end

	local recipe = nil
	for _, r in recipes do
		if r.name == recipeName then
			recipe = r
			break
		end
	end
	if not recipe then return end

	local inv = getInventory(player)
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

	sendInventory(player)
	craftEvent:FireClient(player, "success", recipeName)
end)

while true do
	task.wait(3)

	local boat = getBoat()
	if not boat then continue end

	local root = boat.PrimaryPart

	local spawnPos =
		root.Position
		+ root.CFrame.LookVector * math.random(400, 600)
		+ Vector3.new(math.random(-100, 100), 0, math.random(-100, 100))

	local clone = rs:FindFirstChild("Log"):Clone()

	if not clone.PrimaryPart then
		local first = clone:FindFirstChildWhichIsA("BasePart", true)
		if first then
			clone.PrimaryPart = first
		end
	end

	clone:PivotTo(CFrame.new(spawnPos))
	clone.Parent = workspace

	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	CollectionService:AddTag(clone, "Resource")

	task.delay(LIFETIME, function()
		if clone and clone.Parent then
			clickCounts[clone] = nil
			clone:Destroy()
		end
	end)
end
