-- IslandSpawner.server.lua
-- Generates random islands in the ocean around the player's raft

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ─── Config ───
local SPAWN_INTERVAL = 10       -- check every 10 seconds
local SPAWN_DISTANCE_MIN = 400  -- min distance from raft to spawn
local SPAWN_DISTANCE_MAX = 800  -- max distance from raft
local DESPAWN_DISTANCE = 1200   -- remove islands too far away
local MAX_ISLANDS = 8           -- max islands at a time
local ISLAND_Y_OFFSET = -2      -- slightly below raft level (partially submerged look)

-- Island size ranges
local ISLAND_MIN_RADIUS = 20
local ISLAND_MAX_RADIUS = 50

-- Tree/grass config
local TREES_PER_ISLAND_MIN = 2
local TREES_PER_ISLAND_MAX = 6
local GRASS_PER_ISLAND_MIN = 4
local GRASS_PER_ISLAND_MAX = 12

-- ─── Materials ───
local SAND_COLOR = Color3.fromRGB(220, 200, 150)
local DIRT_COLOR = Color3.fromRGB(120, 85, 50)

local TREE_TRUNK_COLOR = Color3.fromRGB(100, 70, 40)
local TREE_LEAF_COLORS = {
	Color3.fromRGB(50, 130, 50),
	Color3.fromRGB(60, 150, 40),
	Color3.fromRGB(40, 110, 55),
	Color3.fromRGB(70, 140, 30),
}
local GRASS_COLORS = {
	Color3.fromRGB(60, 140, 50),
	Color3.fromRGB(50, 120, 40),
	Color3.fromRGB(70, 150, 55),
	Color3.fromRGB(45, 110, 35),
}

local islands = {}

-- ─── Helper: random point on island surface ───
local function randomPointOnIsland(center, radiusX, radiusZ)
	local angle = math.random() * math.pi * 2
	local dist = math.random() * 0.8 -- keep away from edges
	local x = center.X + math.cos(angle) * radiusX * dist
	local z = center.Z + math.sin(angle) * radiusZ * dist
	return x, z
end

-- ─── Create a tree ───
local function createTree(parent, position, islandType)
	local trunkHeight = math.random(8, 16)
	local trunkWidth = math.random() * 0.5 + 1

	local trunk = Instance.new("Part")
	trunk.Name = "TreeTrunk"
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Size = Vector3.new(trunkHeight, trunkWidth, trunkWidth)
	trunk.CFrame = CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	trunk.Color = TREE_TRUNK_COLOR
	trunk.Material = Enum.Material.Wood
	trunk.Anchored = true
	trunk.CanCollide = true
	trunk.Parent = parent

	-- Leaves (multiple spheres for a natural look)
	local leafColor = TREE_LEAF_COLORS[math.random(#TREE_LEAF_COLORS)]
	local numLeafClusters = math.random(2, 4)

	for i = 1, numLeafClusters do
		local leaf = Instance.new("Part")
		leaf.Name = "Leaves"
		leaf.Shape = Enum.PartType.Ball

		local leafSize = math.random(4, 8)
		leaf.Size = Vector3.new(leafSize, leafSize, leafSize)

		local offsetX = (math.random() - 0.5) * 4
		local offsetY = math.random() * 3
		local offsetZ = (math.random() - 0.5) * 4
		leaf.Position = position + Vector3.new(offsetX, trunkHeight + offsetY, offsetZ)

		leaf.Color = leafColor
		leaf.Material = Enum.Material.Grass
		leaf.Anchored = true
		leaf.CanCollide = false
		leaf.Parent = parent
	end
end

-- ─── Create grass tuft ───
local function createGrass(parent, position)
	local grassColor = GRASS_COLORS[math.random(#GRASS_COLORS)]
	local grassHeight = math.random() * 1.5 + 0.5
	local grassWidth = math.random() * 0.8 + 0.3

	local grass = Instance.new("Part")
	grass.Name = "Grass"
	grass.Size = Vector3.new(grassWidth, grassHeight, grassWidth)
	grass.Position = position + Vector3.new(0, grassHeight / 2, 0)
	grass.Color = grassColor
	grass.Material = Enum.Material.Grass
	grass.Anchored = true
	grass.CanCollide = false
	grass.Parent = parent
end

-- ─── Create an island ───
local function createIsland(centerPos, waterY)
	local islandType = math.random() > 0.5 and "sand" or "dirt"
	local radiusX = math.random(ISLAND_MIN_RADIUS, ISLAND_MAX_RADIUS)
	local radiusZ = math.random(ISLAND_MIN_RADIUS, ISLAND_MAX_RADIUS)

	local model = Instance.new("Model")
	model.Name = "Island_" .. islandType

	-- Main island body (flattened ellipsoid)
	local baseColor = islandType == "sand" and SAND_COLOR or DIRT_COLOR
	local baseMaterial = islandType == "sand" and Enum.Material.Sand or Enum.Material.Ground

	-- Create layered island (top surface + underwater base)
	local topHeight = math.random(2, 4)
	local islandY = waterY + ISLAND_Y_OFFSET

	-- Top surface
	local top = Instance.new("Part")
	top.Name = "IslandTop"
	top.Size = Vector3.new(radiusX * 2, topHeight, radiusZ * 2)
	top.Position = Vector3.new(centerPos.X, islandY + topHeight / 2, centerPos.Z)
	top.Color = baseColor
	top.Material = baseMaterial
	top.Anchored = true
	top.CanCollide = true
	top.Parent = model

	local topMesh = Instance.new("SpecialMesh")
	topMesh.MeshType = Enum.MeshType.Sphere
	topMesh.Scale = Vector3.new(1, 0.3, 1)
	topMesh.Parent = top

	-- Underwater base (darker, larger)
	local baseHeight = math.random(6, 12)
	local base = Instance.new("Part")
	base.Name = "IslandBase"
	base.Size = Vector3.new(radiusX * 2.2, baseHeight, radiusZ * 2.2)
	base.Position = Vector3.new(centerPos.X, islandY - baseHeight / 2 + 1, centerPos.Z)

	local darkerColor
	if islandType == "sand" then
		darkerColor = Color3.fromRGB(180, 160, 110)
	else
		darkerColor = Color3.fromRGB(80, 55, 30)
	end
	base.Color = darkerColor
	base.Material = baseMaterial
	base.Anchored = true
	base.CanCollide = true
	base.Parent = model

	local baseMesh = Instance.new("SpecialMesh")
	baseMesh.MeshType = Enum.MeshType.Sphere
	baseMesh.Scale = Vector3.new(1, 0.5, 1)
	baseMesh.Parent = base

	-- Surface Y for placing objects
	local surfaceY = islandY + topHeight * 0.3

	-- Add trees
	local numTrees = math.random(TREES_PER_ISLAND_MIN, TREES_PER_ISLAND_MAX)
	for _ = 1, numTrees do
		local tx, tz = randomPointOnIsland(centerPos, radiusX * 0.7, radiusZ * 0.7)
		createTree(model, Vector3.new(tx, surfaceY, tz), islandType)
	end

	-- Add grass
	local numGrass = math.random(GRASS_PER_ISLAND_MIN, GRASS_PER_ISLAND_MAX)
	for _ = 1, numGrass do
		local gx, gz = randomPointOnIsland(centerPos, radiusX * 0.85, radiusZ * 0.85)
		createGrass(model, Vector3.new(gx, surfaceY, gz))
	end

	-- Optional: add a green top layer for dirt islands
	if islandType == "dirt" then
		local grassLayer = Instance.new("Part")
		grassLayer.Name = "GrassLayer"
		grassLayer.Size = Vector3.new(radiusX * 1.8, topHeight * 0.5, radiusZ * 1.8)
		grassLayer.Position = Vector3.new(centerPos.X, islandY + topHeight * 0.35, centerPos.Z)
		grassLayer.Color = Color3.fromRGB(60, 130, 45)
		grassLayer.Material = Enum.Material.Grass
		grassLayer.Anchored = true
		grassLayer.CanCollide = false
		grassLayer.Parent = model

		local grassMesh = Instance.new("SpecialMesh")
		grassMesh.MeshType = Enum.MeshType.Sphere
		grassMesh.Scale = Vector3.new(1, 0.15, 1)
		grassMesh.Parent = grassLayer
	end

	model.Parent = workspace

	-- Set primary part for distance checks
	model.PrimaryPart = top

	return {
		model = model,
		center = centerPos,
	}
end

-- ─── Get raft reference ───
local function getRaft()
	local raft = workspace:FindFirstChild("Raft")
	if raft and raft.PrimaryPart then
		return raft
	end
	return nil
end

-- ─── Check if position is too close to existing islands ───
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

-- ─── Main spawn loop ───
task.wait(5) -- let the game settle

while true do
	task.wait(SPAWN_INTERVAL)

	local raft = getRaft()
	if not raft then continue end

	local raftPos = raft.PrimaryPart.Position
	local waterY = raftPos.Y

	-- Remove far-away islands
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

	-- Spawn new islands if under limit
	if #islands < MAX_ISLANDS then
		-- Pick a random direction
		local angle = math.random() * math.pi * 2
		local dist = math.random(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX)

		local spawnPos = Vector3.new(
			raftPos.X + math.cos(angle) * dist,
			waterY,
			raftPos.Z + math.sin(angle) * dist
		)

		-- Don't spawn too close to other islands
		if not isTooCloseToIsland(spawnPos, ISLAND_MIN_RADIUS * 4) then
			local island = createIsland(spawnPos, waterY)
			table.insert(islands, island)
		end
	end
end
