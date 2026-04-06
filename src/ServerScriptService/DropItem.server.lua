local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local dropEvent = Instance.new("RemoteEvent")
dropEvent.Name = "DropItem"
dropEvent.Parent = ReplicatedStorage

-- Map resource names to their 3D template names in ReplicatedStorage
local RESOURCE_TEMPLATES = {
	Log = "Log",
	Plastic = "plastic_bottle",
	Stone = "Stone",
	Iron_Ore = "Iron_Ore",
	Iron_Ingot = "Iron_Ingot",
}

local DROP_COOLDOWN = 0.3
local DROPPED_LIFETIME = 120
local MAX_DROP_DISTANCE = 80
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

	-- Check if it's a resource
	local templateName = RESOURCE_TEMPLATES[itemName]
	if not templateName then return end

	local inv = _G.GetInventory and _G.GetInventory(player)
	if not inv then return end
	if (inv[itemName] or 0) < dropCount then return end

	local template = ReplicatedStorage:FindFirstChild(templateName)
	if not template then return end

	-- Deduct from inventory
	inv[itemName] = inv[itemName] - dropCount

	-- Determine spawn position: use client's mouse hit position if valid, fallback to in front of player
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

	-- Set resource attributes so the collection system can pick it up
	clone:SetAttribute("ResourceType", itemName)
	clone:SetAttribute("ResourceAmount", dropCount)

	clone:PivotTo(CFrame.new(spawnPos))
	clone.Parent = workspace

	-- Unanchor and set up physics
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part:SetNetworkOwner(nil)
		end
	end

	-- Tag as Resource so existing collection system works
	CollectionService:AddTag(clone, "Resource")

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

-- Cleanup on player leave
game:GetService("Players").PlayerRemoving:Connect(function(player)
	lastDropTime[player] = nil
end)
