-- IslandSpawner.server.lua
-- Generates random islands in the ocean around the player's raft

local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ─── Config ───
local SPAWN_INTERVAL = 8        -- check every 8 seconds
local SPAWN_DISTANCE_MIN = 100  -- min distance from raft to spawn
local SPAWN_DISTANCE_MAX = 300  -- max distance from raft
local DESPAWN_DISTANCE = 600    -- remove islands too far away
local MAX_ISLANDS = 8           -- max islands at a time
local ISLAND_Y_OFFSET = -2      -- slightly below raft level

-- Island size ranges (bigger)
local ISLAND_MIN_RADIUS = 40
local ISLAND_MAX_RADIUS = 70

-- Tree/grass config
local TREES_PER_ISLAND_MIN = 4
local TREES_PER_ISLAND_MAX = 10
local GRASS_PER_ISLAND_MIN = 8
local GRASS_PER_ISLAND_MAX = 20

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
	local dist = math.random() * 0.75
	local x = center.X + math.cos(angle) * radiusX * dist
	local z = center.Z + math.sin(angle) * radiusZ * dist
	return x, z
end

-- ─── Create a tree ───
local function createTree(parent, position)
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

	local leafColor = TREE_LEAF_COLORS[math.random(#TREE_LEAF_COLORS)]
	local numLeafClusters = math.random(2, 4)

	for _ = 1, numLeafClusters do
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

-- ─── Create uneven terrain bumps ───
local function createTerrainBumps(parent, centerPos, radiusX, radiusZ, surfaceY, baseColor, baseMaterial)
	local numBumps = math.random(5, 10)
	for _ = 1, numBumps do
		local angle = math.random() * math.pi * 2
		local dist = math.random() * 0.85
		local bx = centerPos.X + math.cos(angle) * radiusX * dist
		local bz = centerPos.Z + math.sin(angle) * radiusZ * dist

		local bumpWidth = math.random(8, 20)
		local bumpHeight = math.random() * 2 + 0.5
		local bumpDepth = math.random(8, 20)

		local bump = Instance.new("Part")
		bump.Name = "TerrainBump"
		bump.Size = Vector3.new(bumpWidth, bumpHeight, bumpDepth)
		bump.Position = Vector3.new(bx, surfaceY + bumpHeight * 0.3, bz)
		bump.Color = baseColor
		bump.Material = baseMaterial
		bump.Anchored = true
		bump.CanCollide = true
		bump.Parent = parent

		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 0.4, 1)
		mesh.Parent = bump
	end
end

-- ─── Create rock formations ───
local function createRocks(parent, centerPos, radiusX, radiusZ, surfaceY)
	local numRocks = math.random(2, 5)
	for _ = 1, numRocks do
		local angle = math.random() * math.pi * 2
		local dist = math.random() * 0.9
		local rx = centerPos.X + math.cos(angle) * radiusX * dist
		local rz = centerPos.Z + math.sin(angle) * radiusZ * dist

		local rockSize = math.random(2, 6)
		local rock = Instance.new("Part")
		rock.Name = "Rock"
		rock.Size = Vector3.new(rockSize, rockSize * 0.7, rockSize * 0.9)
		rock.Position = Vector3.new(rx, surfaceY + rockSize * 0.2, rz)
		rock.Color = Color3.fromRGB(
			math.random(80, 120),
			math.random(80, 110),
			math.random(80, 100)
		)
		rock.Material = Enum.Material.Slate
		rock.Anchored = true
		rock.CanCollide = true
		rock.Parent = parent

		-- Random rotation for variety
		rock.CFrame = rock.CFrame * CFrame.Angles(
			math.rad(math.random(-15, 15)),
			math.rad(math.random(0, 360)),
			math.rad(math.random(-15, 15))
		)
	end
end

-- ─── Spawn a pirate on the island ───
local function spawnIslandPirate(model, centerPos, surfaceY)
	local pirateTemplate = rs:FindFirstChild("Pirate lvl1")
	if not pirateTemplate then return end

	local pirate = pirateTemplate:Clone()
	-- Place near center of island
	local px, pz = randomPointOnIsland(centerPos, 10, 10)
	local piratePos = Vector3.new(px, surfaceY + 5, pz)

	if pirate:IsA("Model") then
		pirate:PivotTo(CFrame.new(piratePos))
	end
	pirate.Parent = workspace

	local hum = pirate:FindFirstChildWhichIsA("Humanoid")
	if hum then
		hum.WalkSpeed = 10
		hum.JumpPower = 0

		-- Clean up pirate when it dies
		hum.Died:Connect(function()
			task.wait(3)
			pirate:Destroy()
		end)
	end

	-- Store reference so it gets cleaned up with island
	pirate:SetAttribute("IslandPirate", true)

	return pirate
end

-- ─── Place Destroyed House on island ───
local function placeDestroyedHouse(parent, centerPos, surfaceY)
	local houseTemplate = rs:FindFirstChild("Destroyed house")
	if not houseTemplate then return end

	local house = houseTemplate:Clone()
	-- Place slightly off-center
	local hx = centerPos.X + (math.random() - 0.5) * 15
	local hz = centerPos.Z + (math.random() - 0.5) * 15

	if house:IsA("Model") then
		house:PivotTo(CFrame.new(hx, surfaceY, hz) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0))
	elseif house:IsA("BasePart") then
		house.CFrame = CFrame.new(hx, surfaceY, hz)
	end

	-- Anchor all parts
	for _, part in house:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	house.Parent = parent
end

-- ─── Create an island ───
local function createIsland(centerPos, waterY)
	local islandType = math.random() > 0.5 and "sand" or "dirt"
	local radiusX = math.random(ISLAND_MIN_RADIUS, ISLAND_MAX_RADIUS)
	local radiusZ = math.random(ISLAND_MIN_RADIUS, ISLAND_MAX_RADIUS)

	local model = Instance.new("Model")
	model.Name = "Island_" .. islandType

	local baseColor = islandType == "sand" and SAND_COLOR or DIRT_COLOR
	local baseMaterial = islandType == "sand" and Enum.Material.Sand or Enum.Material.Ground

	local topHeight = math.random(3, 5)
	local islandY = waterY + ISLAND_Y_OFFSET

	-- Main top surface (uneven shape using multiple overlapping parts)
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

	-- Add offset lobes to break the symmetry
	local numLobes = math.random(3, 6)
	for _ = 1, numLobes do
		local lobeAngle = math.random() * math.pi * 2
		local lobeDist = math.random() * 0.4 + 0.3
		local lobeRadiusX = radiusX * (math.random() * 0.4 + 0.3)
		local lobeRadiusZ = radiusZ * (math.random() * 0.4 + 0.3)

		local lobe = Instance.new("Part")
		lobe.Name = "IslandLobe"
		lobe.Size = Vector3.new(lobeRadiusX * 2, topHeight * 0.9, lobeRadiusZ * 2)
		lobe.Position = Vector3.new(
			centerPos.X + math.cos(lobeAngle) * radiusX * lobeDist,
			islandY + topHeight * 0.4,
			centerPos.Z + math.sin(lobeAngle) * radiusZ * lobeDist
		)
		lobe.Color = baseColor
		lobe.Material = baseMaterial
		lobe.Anchored = true
		lobe.CanCollide = true
		lobe.Parent = model

		local lobeMesh = Instance.new("SpecialMesh")
		lobeMesh.MeshType = Enum.MeshType.Sphere
		lobeMesh.Scale = Vector3.new(1, 0.3, 1)
		lobeMesh.Parent = lobe
	end

	-- Underwater base
	local baseHeight = math.random(8, 15)
	local base = Instance.new("Part")
	base.Name = "IslandBase"
	base.Size = Vector3.new(radiusX * 2.2, baseHeight, radiusZ * 2.2)
	base.Position = Vector3.new(centerPos.X, islandY - baseHeight / 2 + 1, centerPos.Z)

	local darkerColor = islandType == "sand"
		and Color3.fromRGB(180, 160, 110)
		or Color3.fromRGB(80, 55, 30)
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

	-- Add terrain bumps for uneven surface
	createTerrainBumps(model, centerPos, radiusX, radiusZ, surfaceY, baseColor, baseMaterial)

	-- Add rocks
	createRocks(model, centerPos, radiusX, radiusZ, surfaceY)

	-- Add trees
	local numTrees = math.random(TREES_PER_ISLAND_MIN, TREES_PER_ISLAND_MAX)
	for _ = 1, numTrees do
		local tx, tz = randomPointOnIsland(centerPos, radiusX * 0.7, radiusZ * 0.7)
		createTree(model, Vector3.new(tx, surfaceY, tz))
	end

	-- Add grass
	local numGrass = math.random(GRASS_PER_ISLAND_MIN, GRASS_PER_ISLAND_MAX)
	for _ = 1, numGrass do
		local gx, gz = randomPointOnIsland(centerPos, radiusX * 0.85, radiusZ * 0.85)
		createGrass(model, Vector3.new(gx, surfaceY, gz))
	end

	-- Green top layer for dirt islands
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

	-- Place Destroyed House
	placeDestroyedHouse(model, centerPos, surfaceY)

	model.Parent = workspace
	model.PrimaryPart = top

	-- Spawn 1 pirate on the island
	local pirate = spawnIslandPirate(model, centerPos, surfaceY)

	return {
		model = model,
		center = centerPos,
		pirate = pirate,
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
task.wait(5)

while true do
	task.wait(SPAWN_INTERVAL)

	local raft = getRaft()
	if not raft then continue end

	local raftPos = raft.PrimaryPart.Position
	local waterY = raftPos.Y

	-- Remove far-away islands (and their pirates)
	for i = #islands, 1, -1 do
		local island = islands[i]
		if not island.model or not island.model.Parent then
			if island.pirate and island.pirate.Parent then
				island.pirate:Destroy()
			end
			table.remove(islands, i)
		else
			local dist = (raftPos - island.center).Magnitude
			if dist > DESPAWN_DISTANCE then
				if island.pirate and island.pirate.Parent then
					island.pirate:Destroy()
				end
				island.model:Destroy()
				table.remove(islands, i)
			end
		end
	end

	-- Spawn new islands if under limit
	if #islands < MAX_ISLANDS then
		local angle = math.random() * math.pi * 2
		local dist = math.random(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX)

		local spawnPos = Vector3.new(
			raftPos.X + math.cos(angle) * dist,
			waterY,
			raftPos.Z + math.sin(angle) * dist
		)

		if not isTooCloseToIsland(spawnPos, ISLAND_MIN_RADIUS * 4) then
			local island = createIsland(spawnPos, waterY)
			table.insert(islands, island)
		end
	end
end
