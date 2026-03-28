local rs = game:GetService("ReplicatedStorage")

local RAFT_PART_SIZE = 6

local placeBlockEvent = rs:FindFirstChild("PlaceBlock")
if not placeBlockEvent then
	placeBlockEvent = Instance.new("RemoteEvent")
	placeBlockEvent.Name = "PlaceBlock"
	placeBlockEvent.Parent = rs
end

local raftPartTemplate = rs:WaitForChild("Raft_part")

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

-- Get local grid offsets of all existing raft parts (including main)
local function getOccupiedOffsets(raft)
	local offsets = {}
	local primaryCF = raft.PrimaryPart.CFrame

	-- Main raft at offset (0, 0)
	table.insert(offsets, {x = 0, z = 0})

	for _, child in raft:GetDescendants() do
		if child:IsA("BasePart") and child:GetAttribute("RaftPart") then
			local localPos = primaryCF:PointToObjectSpace(child.Position)
			local gx = math.round(localPos.X / RAFT_PART_SIZE)
			local gz = math.round(localPos.Z / RAFT_PART_SIZE)
			table.insert(offsets, {x = gx, z = gz})
		end
	end

	return offsets
end

local function isOccupied(offsets, gx, gz)
	for _, o in offsets do
		if o.x == gx and o.z == gz then
			return true
		end
	end
	return false
end

local function isAdjacent(offsets, gx, gz)
	for _, o in offsets do
		if (math.abs(o.x - gx) == 1 and o.z == gz) or (math.abs(o.z - gz) == 1 and o.x == gx) then
			return true
		end
	end
	return false
end

placeBlockEvent.OnServerEvent:Connect(function(player, gridX, gridZ)
	if type(gridX) ~= "number" or type(gridZ) ~= "number" then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return end

	-- Check player has Hammer equipped
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Hammer" then return end

	-- Check resources
	local inv = _G.GetInventory and _G.GetInventory(player) or {}
	if (inv.Log or 0) < 2 then return end

	local gx = math.round(gridX)
	local gz = math.round(gridZ)

	local offsets = getOccupiedOffsets(raft)

	if isOccupied(offsets, gx, gz) then return end
	if not isAdjacent(offsets, gx, gz) then return end

	-- Compute world CFrame from raft-local grid offset
	local localOffset = Vector3.new(gx * RAFT_PART_SIZE, 0, gz * RAFT_PART_SIZE)
	local worldCF = raft.PrimaryPart.CFrame * CFrame.new(localOffset)

	-- Check distance from player
	if (char.HumanoidRootPart.Position - worldCF.Position).Magnitude > 80 then return end

	-- Deduct cost
	inv.Log = inv.Log - 2

	-- Clone Raft_part from ReplicatedStorage
	local newPart = raftPartTemplate:Clone()
	newPart:SetAttribute("RaftPart", true)

	if newPart:IsA("Model") then
		if newPart.PrimaryPart then
			newPart:PivotTo(worldCF)
		end
		newPart.Parent = raft

		-- Weld all base parts to the raft
		for _, desc in newPart:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = desc
				weld.Part1 = raft.PrimaryPart
				weld.Parent = desc
			end
		end
	elseif newPart:IsA("BasePart") then
		newPart.CFrame = worldCF
		newPart.Anchored = false
		newPart.Parent = raft

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = newPart
		weld.Part1 = raft.PrimaryPart
		weld.Parent = newPart
	end

	-- Sync inventory
	if _G.SendInventory then
		_G.SendInventory(player)
	end

	placeBlockEvent:FireClient(player, "placed")
end)
