local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local dropEvent = Instance.new("RemoteEvent")
dropEvent.Name = "DropItem"
dropEvent.Parent = ReplicatedStorage

local pickupEvent = Instance.new("RemoteEvent")
pickupEvent.Name = "PickupDroppedItem"
pickupEvent.Parent = ReplicatedStorage

-- Map resource names to their 3D template names in ReplicatedStorage
local RESOURCE_TEMPLATES = {
	Log = "Log",
	Plastic = "plastic_model",
	Stone = "stone",
	Iron_Ore = "iron_model",
	Iron_Ingot = "box_model",
	Plank = "plank",
}

-- Known resource names (items stored as counts in inventory)
local RESOURCE_ITEMS = {
	Log = true,
	Plastic = true,
	Stone = true,
	Iron_Ore = true,
	Iron_Ingot = true,
	Plank = true,
}

-- Fallback template for any unmapped items (tools, etc.)
local FALLBACK_TEMPLATE = "box_model"

local DROP_COOLDOWN = 0.3
local DROPPED_LIFETIME = 120
local MAX_DROP_DISTANCE = 80
local PICKUP_DISTANCE = 15
local lastDropTime = {}

dropEvent.OnServerEvent:Connect(function(player, itemName, dropCount, dropPosition)
	if type(itemName) ~= "string" then return end
	if type(dropCount) ~= "number" then return end
	if typeof(dropPosition) ~= "Vector3" then dropPosition = nil end

	dropCount = math.floor(math.clamp(dropCount, 1, 30))

	-- Cooldown
	local now = tick()
	if lastDropTime[player] and now - lastDropTime[player] < DROP_COOLDOWN then return end
	lastDropTime[player] = now

	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local isResource = RESOURCE_ITEMS[itemName]

	if isResource then
		-- Resource drop: deduct from inventory count
		local inv = _G.GetInventory and _G.GetInventory(player)
		if not inv then return end
		if (inv[itemName] or 0) < dropCount then return end
		inv[itemName] = inv[itemName] - dropCount
	else
		-- Tool drop: find and remove the tool from backpack or character
		local tool = nil
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			tool = backpack:FindFirstChild(itemName)
		end
		if not tool and char then
			tool = char:FindFirstChild(itemName)
			if tool and not tool:IsA("Tool") then tool = nil end
		end
		if not tool then return end
		tool:Destroy()
	end

	-- Find the template
	local templateName = RESOURCE_TEMPLATES[itemName] or FALLBACK_TEMPLATE
	local template = ReplicatedStorage:FindFirstChild(templateName)
	if not template then
		template = ReplicatedStorage:FindFirstChild(FALLBACK_TEMPLATE)
	end
	if not template then return end

	-- Determine spawn position
	local spawnPos
	if dropPosition and (dropPosition - hrp.Position).Magnitude < MAX_DROP_DISTANCE then
		spawnPos = dropPosition + Vector3.new(0, 2, 0)
	else
		local lookDir = hrp.CFrame.LookVector
		spawnPos = hrp.Position + lookDir * 4 + Vector3.new(0, -1, 0)
	end

	local clone = template:Clone()

	-- Ensure the model has a PrimaryPart
	if clone:IsA("Model") and not clone.PrimaryPart then
		local first = clone:FindFirstChildWhichIsA("BasePart")
		if first then
			clone.PrimaryPart = first
		end
	end

	-- Set attributes so pickup knows what this is
	clone:SetAttribute("ResourceType", itemName)
	clone:SetAttribute("ResourceAmount", dropCount)
	clone:SetAttribute("IsToolDrop", not isResource)

	clone:PivotTo(CFrame.new(spawnPos))
	clone.Parent = workspace

	-- Unanchor and set up physics
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part:SetNetworkOwner(nil)
		end
	end

	-- Tag as DroppedItem for E-key instant pickup
	CollectionService:AddTag(clone, "DroppedItem")

	-- Auto-despawn after lifetime
	task.delay(DROPPED_LIFETIME, function()
		if clone and clone.Parent then
			clone:Destroy()
		end
	end)

	-- Sync inventory to client
	if _G.SendInventory then
		_G.SendInventory(player)
	end
end)

-- E-key instant pickup for dropped items
pickupEvent.OnServerEvent:Connect(function(player, targetPart)
	if not targetPart or not targetPart.Parent then return end

	-- Find the dropped item (could be a part or a model)
	local droppedItem = nil
	if CollectionService:HasTag(targetPart, "DroppedItem") then
		droppedItem = targetPart
	else
		local model = targetPart:FindFirstAncestorOfClass("Model")
		if model and CollectionService:HasTag(model, "DroppedItem") then
			droppedItem = model
		end
	end
	if not droppedItem then return end

	-- Distance check
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local itemPos
	if droppedItem:IsA("Model") then
		itemPos = droppedItem:GetPivot().Position
	else
		itemPos = droppedItem.Position
	end
	if (hrp.Position - itemPos).Magnitude > PICKUP_DISTANCE then return end

	-- Get item info
	local resType = droppedItem:GetAttribute("ResourceType")
	local resAmount = droppedItem:GetAttribute("ResourceAmount") or 1
	local isToolDrop = droppedItem:GetAttribute("IsToolDrop")
	if not resType then return end

	if isToolDrop then
		-- Tool pickup: clone the tool template and give to player
		local toolTemplate = ReplicatedStorage:FindFirstChild(resType)
		if not toolTemplate then return end
		local backpack = player:FindFirstChild("Backpack")
		if not backpack then return end
		local toolClone = toolTemplate:Clone()
		toolClone.Parent = backpack
	else
		-- Resource pickup: add to inventory count
		local inv = _G.GetInventory and _G.GetInventory(player)
		if not inv then return end
		inv[resType] = (inv[resType] or 0) + resAmount
	end

	-- Destroy the dropped item
	droppedItem:Destroy()

	-- Sync inventory to client
	if _G.SendInventory then
		_G.SendInventory(player)
	end
end)

-- Cleanup on player leave
game:GetService("Players").PlayerRemoving:Connect(function(player)
	lastDropTime[player] = nil
end)
