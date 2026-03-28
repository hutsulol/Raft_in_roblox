local rs = game:GetService("ReplicatedStorage")

local placeBlockEvent = rs:FindFirstChild("PlaceBlock")
if not placeBlockEvent then
	placeBlockEvent = Instance.new("RemoteEvent")
	placeBlockEvent.Name = "PlaceBlock"
	placeBlockEvent.Parent = rs
end

local raftPartTemplate = rs:WaitForChild("Raft_part")

-- Measure grid size from the actual template
local GRID_SIZE
if raftPartTemplate:IsA("Model") and raftPartTemplate.PrimaryPart then
	GRID_SIZE = raftPartTemplate.PrimaryPart.Size.X
elseif raftPartTemplate:IsA("BasePart") then
	GRID_SIZE = raftPartTemplate.Size.X
else
	GRID_SIZE = 6
end

-- Store grid size in an attribute so the client can read it
raftPartTemplate:SetAttribute("GridSize", GRID_SIZE)

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

-- Get occupied grid offsets using stored GridX/GridZ attributes
local function getOccupiedOffsets(raft)
	local offsets = {}

	-- Main raft at (0, 0)
	table.insert(offsets, {x = 0, z = 0})

	-- Find all placed Raft_parts by GridX/GridZ attributes
	for _, child in raft:GetChildren() do
		local gx = child:GetAttribute("GridX")
		local gz = child:GetAttribute("GridZ")
		if gx and gz then
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

	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Hammer" then return end

	local inv = _G.GetInventory and _G.GetInventory(player) or {}
	if (inv.Log or 0) < 2 then return end

	local gx = math.round(gridX)
	local gz = math.round(gridZ)

	local offsets = getOccupiedOffsets(raft)

	if isOccupied(offsets, gx, gz) then return end
	if not isAdjacent(offsets, gx, gz) then return end

	local localOffset = Vector3.new(gx * GRID_SIZE, 0, gz * GRID_SIZE)
	local worldCF = raft.PrimaryPart.CFrame * CFrame.new(localOffset)

	if (char.HumanoidRootPart.Position - worldCF.Position).Magnitude > 80 then return end

	inv.Log = inv.Log - 2

	local newPart = raftPartTemplate:Clone()
	newPart:SetAttribute("GridX", gx)
	newPart:SetAttribute("GridZ", gz)

	if newPart:IsA("Model") then
		if newPart.PrimaryPart then
			newPart:PivotTo(worldCF)
		end
		newPart.Parent = raft

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

	if _G.SendInventory then
		_G.SendInventory(player)
	end

	placeBlockEvent:FireClient(player, "placed")
end)
