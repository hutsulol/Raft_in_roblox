local rs = game:GetService("ReplicatedStorage")

local RAFT_PART_SIZE = 6 -- studs, square raft piece

local placeBlockEvent = rs:FindFirstChild("PlaceBlock")
if not placeBlockEvent then
	placeBlockEvent = Instance.new("RemoteEvent")
	placeBlockEvent.Name = "PlaceBlock"
	placeBlockEvent.Parent = rs
end

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

-- Get all parts that are valid anchors for new placement (main raft + placed Raft_parts)
local function getRaftParts()
	local raft = getRaft()
	if not raft then return {} end

	local parts = {}

	-- The main raft primary part
	if raft.PrimaryPart then
		table.insert(parts, raft.PrimaryPart)
	end

	-- All Raft_part children
	for _, child in raft:GetDescendants() do
		if child:IsA("BasePart") and child:GetAttribute("RaftPart") then
			table.insert(parts, child)
		end
	end

	return parts
end

-- Check if a position is adjacent to any existing raft part
local function isValidPlacement(position)
	local raftParts = getRaftParts()
	if #raftParts == 0 then return false end

	for _, part in raftParts do
		local partPos = Vector3.new(part.Position.X, position.Y, part.Position.Z)
		local diff = position - partPos
		local dist = diff.Magnitude

		-- Must be exactly one RAFT_PART_SIZE away (adjacent)
		if math.abs(dist - RAFT_PART_SIZE) < 1 then
			-- Must be aligned on one axis (not diagonal)
			local ax = math.abs(diff.X)
			local az = math.abs(diff.Z)
			if (math.abs(ax - RAFT_PART_SIZE) < 1 and az < 1) or (math.abs(az - RAFT_PART_SIZE) < 1 and ax < 1) then
				return true
			end
		end
	end

	return false
end

-- Check if a position is already occupied by a raft part
local function isOccupied(position)
	local raftParts = getRaftParts()
	for _, part in raftParts do
		local partPos = Vector3.new(part.Position.X, position.Y, part.Position.Z)
		local dist = (position - partPos).Magnitude
		if dist < 1 then
			return true
		end
	end
	return false
end

placeBlockEvent.OnServerEvent:Connect(function(player, worldPosition)
	if typeof(worldPosition) ~= "Vector3" then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return end

	-- Check player has Hammer equipped
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Hammer" then return end

	-- Check player has enough resources (2 Logs per raft piece)
	local inv = _G.GetInventory and _G.GetInventory(player) or {}
	if (inv.Log or 0) < 2 then return end

	-- Snap position to raft grid
	local raftY = raft.PrimaryPart.Position.Y
	local snappedPos = Vector3.new(
		math.round(worldPosition.X / RAFT_PART_SIZE) * RAFT_PART_SIZE,
		raftY,
		math.round(worldPosition.Z / RAFT_PART_SIZE) * RAFT_PART_SIZE
	)

	-- Validate placement
	if isOccupied(snappedPos) then return end
	if not isValidPlacement(snappedPos) then return end

	-- Check distance from player
	local dist = (char.HumanoidRootPart.Position - snappedPos).Magnitude
	if dist > 80 then return end

	-- Deduct cost
	inv.Log = inv.Log - 2

	-- Create raft part
	local part = Instance.new("Part")
	part.Name = "Raft_part"
	part.Size = Vector3.new(RAFT_PART_SIZE, 1, RAFT_PART_SIZE)
	part.Position = snappedPos
	part.Anchored = false
	part.Material = Enum.Material.Wood
	part.BrickColor = BrickColor.new("Brown")
	part:SetAttribute("RaftPart", true)
	part.Parent = raft

	-- Weld to the raft so it moves together
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = raft.PrimaryPart
	weld.Parent = part

	-- Notify client
	if _G.SendInventory then
		_G.SendInventory(player)
	end

	placeBlockEvent:FireClient(player, "placed", snappedPos)
end)
