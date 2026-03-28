local rs = game:GetService("ReplicatedStorage")

local placeBlockEvent = rs:FindFirstChild("PlaceBlock")
if not placeBlockEvent then
	placeBlockEvent = Instance.new("RemoteEvent")
	placeBlockEvent.Name = "PlaceBlock"
	placeBlockEvent.Parent = rs
end

local raftPartTemplate = rs:WaitForChild("Raft_part")
local wallTemplate = rs:FindFirstChild("Wall")

-- Measure grid size from the actual template
local GRID_SIZE
if raftPartTemplate:IsA("Model") and raftPartTemplate.PrimaryPart then
	GRID_SIZE = raftPartTemplate.PrimaryPart.Size.X
elseif raftPartTemplate:IsA("BasePart") then
	GRID_SIZE = raftPartTemplate.Size.X
else
	GRID_SIZE = 6
end

raftPartTemplate:SetAttribute("GridSize", GRID_SIZE)

-- Measure wall height for vertical offset
local WALL_HEIGHT = 0
if wallTemplate then
	if wallTemplate:IsA("Model") then
		local size = wallTemplate:GetExtentsSize()
		WALL_HEIGHT = size.Y
	elseif wallTemplate:IsA("BasePart") then
		WALL_HEIGHT = wallTemplate.Size.Y
	end
end

local RAFT_COST = 2
local WALL_COST = 3

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

local function getFloorOffsets(raft)
	local offsets = {}
	table.insert(offsets, {x = 0, z = 0})

	for _, child in raft:GetChildren() do
		local gx = child:GetAttribute("GridX")
		local gz = child:GetAttribute("GridZ")
		if gx and gz and child:GetAttribute("BuildType") ~= "wall" then
			table.insert(offsets, {x = gx, z = gz})
		end
	end

	return offsets
end

local function getWallKeys(raft)
	local keys = {}
	for _, child in raft:GetChildren() do
		local wk = child:GetAttribute("WallKey")
		if wk then
			keys[wk] = true
		end
	end
	return keys
end

local function isFloorOccupied(offsets, gx, gz)
	for _, o in offsets do
		if o.x == gx and o.z == gz then
			return true
		end
	end
	return false
end

local function isFloorAdjacent(offsets, gx, gz)
	for _, o in offsets do
		if (math.abs(o.x - gx) == 1 and o.z == gz) or (math.abs(o.z - gz) == 1 and o.x == gx) then
			return true
		end
	end
	return false
end

-- side: 0=front(+Z), 1=back(-Z), 2=left(-X), 3=right(+X)
local function wallCFrame(raft, gx, gz, side)
	local primaryCF = raft.PrimaryPart.CFrame
	local half = GRID_SIZE / 2

	local localPos, localRot
	if side == 0 then -- front (+Z)
		localPos = Vector3.new(gx * GRID_SIZE, WALL_HEIGHT / 2, gz * GRID_SIZE + half)
		localRot = CFrame.Angles(0, 0, 0)
	elseif side == 1 then -- back (-Z)
		localPos = Vector3.new(gx * GRID_SIZE, WALL_HEIGHT / 2, gz * GRID_SIZE - half)
		localRot = CFrame.Angles(0, math.rad(180), 0)
	elseif side == 2 then -- left (-X)
		localPos = Vector3.new(gx * GRID_SIZE - half, WALL_HEIGHT / 2, gz * GRID_SIZE)
		localRot = CFrame.Angles(0, math.rad(90), 0)
	elseif side == 3 then -- right (+X)
		localPos = Vector3.new(gx * GRID_SIZE + half, WALL_HEIGHT / 2, gz * GRID_SIZE)
		localRot = CFrame.Angles(0, math.rad(-90), 0)
	end

	return primaryCF * CFrame.new(localPos) * localRot
end

local function weldToRaft(obj, raft)
	if obj:IsA("Model") then
		for _, desc in obj:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = desc
				weld.Part1 = raft.PrimaryPart
				weld.Parent = desc
			end
		end
	elseif obj:IsA("BasePart") then
		obj.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = obj
		weld.Part1 = raft.PrimaryPart
		weld.Parent = obj
	end
end

placeBlockEvent.OnServerEvent:Connect(function(player, buildType, ...)
	if type(buildType) ~= "string" then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return end

	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Hammer" then return end

	local inv = _G.GetInventory and _G.GetInventory(player) or {}

	if buildType == "raft" then
		local gridX, gridZ = ...
		if type(gridX) ~= "number" or type(gridZ) ~= "number" then return end
		if (inv.Log or 0) < RAFT_COST then return end

		local gx = math.round(gridX)
		local gz = math.round(gridZ)

		local offsets = getFloorOffsets(raft)
		if isFloorOccupied(offsets, gx, gz) then return end
		if not isFloorAdjacent(offsets, gx, gz) then return end

		local localOffset = Vector3.new(gx * GRID_SIZE, 0, gz * GRID_SIZE)
		local worldCF = raft.PrimaryPart.CFrame * CFrame.new(localOffset)

		if (char.HumanoidRootPart.Position - worldCF.Position).Magnitude > 80 then return end

		inv.Log = inv.Log - RAFT_COST

		local newPart = raftPartTemplate:Clone()
		newPart:SetAttribute("GridX", gx)
		newPart:SetAttribute("GridZ", gz)
		newPart:SetAttribute("BuildType", "raft")

		if newPart:IsA("Model") and newPart.PrimaryPart then
			newPart:PivotTo(worldCF)
		elseif newPart:IsA("BasePart") then
			newPart.CFrame = worldCF
		end
		newPart.Parent = raft
		weldToRaft(newPart, raft)

	elseif buildType == "wall" then
		if not wallTemplate then return end
		local gridX, gridZ, side = ...
		if type(gridX) ~= "number" or type(gridZ) ~= "number" or type(side) ~= "number" then return end
		if (inv.Log or 0) < WALL_COST then return end

		local gx = math.round(gridX)
		local gz = math.round(gridZ)
		side = math.round(side)
		if side < 0 or side > 3 then return end

		-- Must have a floor tile at this grid position
		local offsets = getFloorOffsets(raft)
		if not isFloorOccupied(offsets, gx, gz) then return end

		-- Check wall not already placed here
		local wallKey = gx .. "_" .. gz .. "_" .. side
		local existingWalls = getWallKeys(raft)
		if existingWalls[wallKey] then return end

		local wCF = wallCFrame(raft, gx, gz, side)
		if (char.HumanoidRootPart.Position - wCF.Position).Magnitude > 80 then return end

		inv.Log = inv.Log - WALL_COST

		local newWall = wallTemplate:Clone()
		newWall:SetAttribute("WallKey", wallKey)
		newWall:SetAttribute("BuildType", "wall")
		newWall:SetAttribute("GridX", gx)
		newWall:SetAttribute("GridZ", gz)

		if newWall:IsA("Model") and newWall.PrimaryPart then
			newWall:PivotTo(wCF)
		elseif newWall:IsA("BasePart") then
			newWall.CFrame = wCF
		end
		newWall.Parent = raft
		weldToRaft(newWall, raft)
	end

	if _G.SendInventory then
		_G.SendInventory(player)
	end

	placeBlockEvent:FireClient(player, "placed")
end)
