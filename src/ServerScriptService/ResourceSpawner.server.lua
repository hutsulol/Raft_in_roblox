local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")

local CLICKS_TO_COLLECT = 5
local LIFETIME = 120

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

local inventoryEvent = rs:FindFirstChild("InventoryUpdate")
if not inventoryEvent then
	inventoryEvent = Instance.new("RemoteEvent")
	inventoryEvent.Name = "InventoryUpdate"
	inventoryEvent.Parent = rs
end

local _G_Inventories = {}
_G.GetInventory = function(player)
	if not _G_Inventories[player] then
		_G_Inventories[player] = {Log = 0}
	end
	return _G_Inventories[player]
end

_G.SendInventory = function(player)
	inventoryEvent:FireClient(player, _G.GetInventory(player))
end

local clickCounts = {}

local function getBoat()
	return workspace:FindFirstChild("raft")
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

Players.PlayerRemoving:Connect(function(player)
	_G_Inventories[player] = nil
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
		local inv = _G.GetInventory(player)
		inv.Log = (inv.Log or 0) + 1
		collectNotify:FireClient(player, "collected", resource)
		_G.SendInventory(player)
		resource:Destroy()
	end
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
