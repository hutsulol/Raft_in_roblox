local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local PICKUP_TAG = "PickupHint"
local PICKUP_DISTANCE = 12

local pickupEvent = ReplicatedStorage:FindFirstChild("TaggedPickupRequest")
if not pickupEvent then
	pickupEvent = Instance.new("RemoteEvent")
	pickupEvent.Name = "TaggedPickupRequest"
	pickupEvent.Parent = ReplicatedStorage
end

local function resolveTarget(inst)
	if not inst then return nil end
	if inst:IsA("Model") then return inst end
	local model = inst:FindFirstAncestorWhichIsA("Model")
	return model or inst
end

local function isTaggedPickupTarget(target)
	if not target then return false end
	if CollectionService:HasTag(target, PICKUP_TAG) then return true end
	for _, d in target:GetDescendants() do
		if CollectionService:HasTag(d, PICKUP_TAG) then
			return true
		end
	end
	return false
end

local function getWorldPos(inst)
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then
		local ok, cf = pcall(function() return inst:GetPivot() end)
		if ok then return cf.Position end
	end
	return nil
end

pickupEvent.OnServerEvent:Connect(function(player, target)
	if typeof(target) ~= "Instance" then return end
	if not target:IsDescendantOf(workspace) then return end

	target = resolveTarget(target)
	if not target or not target:IsDescendantOf(workspace) then return end
	if not isTaggedPickupTarget(target) then return end

	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local pos = getWorldPos(target)
	if not hrp or not pos then return end
	if (pos - hrp.Position).Magnitude > PICKUP_DISTANCE then return end

	local itemName = target:GetAttribute("PickupItemName") or target.Name
	local amount = tonumber(target:GetAttribute("PickupAmount")) or 1
	if amount < 1 then amount = 1 end

	if _G.AddResourceToInventory then
		_G.AddResourceToInventory(player, itemName, amount, pos)
	end

	target:Destroy()
end)
