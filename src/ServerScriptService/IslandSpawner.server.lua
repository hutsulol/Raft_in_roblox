-- IslandSpawner.server.lua
-- Spawns Island_1 and Island_2 models from ReplicatedStorage near the player randomly

local rs = game:GetService("ReplicatedStorage")

-- ─── Config ───
local SPAWN_INTERVAL = 8
local SPAWN_DISTANCE_MIN = 300
local SPAWN_DISTANCE_MAX = 600
local DESPAWN_DISTANCE = 1000
local MAX_ISLANDS = 6
local MIN_ISLAND_SPACING = 200

-- ─── Templates ───
local ISLAND_TEMPLATES = { "Island_1", "Island_2" }

local islands = {}
_G.IslandPositions = {}

local function updateGlobalIslandPositions()
	local positions = {}
	for _, island in islands do
		if island.model and island.model.Parent then
			table.insert(positions, { center = island.center, radius = island.radius })
		end
	end
	_G.IslandPositions = positions
end

local function getIslandRadius(model)
	local _, size = model:GetBoundingBox()
	return math.max(size.X, size.Z) / 2
end

local function isTooCloseToIsland(pos, minDist)
	for _, island in islands do
		if island.model and island.model.Parent then
			local dist = (pos - island.center).Magnitude
			if dist < minDist then
				return true
			end
		end
	end
	return false
end

local function getRaft()
	local raft = workspace:FindFirstChild("Raft")
	if raft and raft.PrimaryPart then
		return raft
	end
	return nil
end

local function spawnIsland(spawnPos)
	-- Pick a random template
	local templateName = ISLAND_TEMPLATES[math.random(#ISLAND_TEMPLATES)]
	local template = rs:FindFirstChild(templateName)
	if not template then
		warn("IslandSpawner: template not found: " .. templateName)
		return nil
	end

	local island = template:Clone()

	-- Anchor all parts
	for _, part in island:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	-- Position the island at spawn location with random rotation
	local rotation = math.rad(math.random(0, 360))
	island:PivotTo(CFrame.new(spawnPos) * CFrame.Angles(0, rotation, 0))
	island.Parent = workspace

	local radius = getIslandRadius(island)

	return {
		model = island,
		center = spawnPos,
		radius = radius,
	}
end

-- ─── Main spawn loop ───
task.wait(5)

while true do
	task.wait(SPAWN_INTERVAL)

	local raft = getRaft()
	if not raft then continue end

	local raftPos = raft.PrimaryPart.Position

	-- Cleanup: remove despawned or destroyed islands
	for i = #islands, 1, -1 do
		local island = islands[i]
		if not island.model or not island.model.Parent then
			table.remove(islands, i)
		else
			local dist = (raftPos - island.center).Magnitude
			if dist > DESPAWN_DISTANCE then
				island.model:Destroy()
				table.remove(islands, i)
			end
		end
	end

	updateGlobalIslandPositions()

	-- Spawn new island if under max
	if #islands < MAX_ISLANDS then
		local angle = math.random() * math.pi * 2
		local dist = math.random(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX)

		local spawnPos = Vector3.new(
			raftPos.X + math.cos(angle) * dist,
			raftPos.Y,
			raftPos.Z + math.sin(angle) * dist
		)

		if not isTooCloseToIsland(spawnPos, MIN_ISLAND_SPACING) then
			local island = spawnIsland(spawnPos)
			if island then
				table.insert(islands, island)
				updateGlobalIslandPositions()
			end
		end
	end
end
