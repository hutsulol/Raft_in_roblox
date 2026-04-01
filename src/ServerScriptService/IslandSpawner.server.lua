-- IslandSpawner.server.lua
-- Generates RAFT-style islands: sandy beach rim, elevated green center with rocks

local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ─── Config ───
local SPAWN_INTERVAL = 8
local SPAWN_DISTANCE_MIN = 300
local SPAWN_DISTANCE_MAX = 600
local DESPAWN_DISTANCE = 1000
local MAX_ISLANDS = 6
local ISLAND_Y_OFFSET = -2

local ISLAND_MIN_RADIUS = 50
local ISLAND_MAX_RADIUS = 80

-- ─── Colors ───
local SAND_COLOR = Color3.fromRGB(220, 205, 160)
local SAND_DARK = Color3.fromRGB(190, 175, 130)
local DIRT_COLOR = Color3.fromRGB(110, 80, 45)
local DIRT_DARK = Color3.fromRGB(80, 55, 30)
local GRASS_TOP = Color3.fromRGB(65, 135, 50)
local ROCK_COLOR = Color3.fromRGB(100, 95, 85)
local ROCK_DARK = Color3.fromRGB(75, 70, 60)

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
_G.IslandPositions = {}

local function updateGlobalIslandPositions()
	local positions = {}
	for _, island in islands do
		if island.model and island.model.Parent then
			table.insert(positions, {center = island.center, radius = island.radius})
		end
	end
	_G.IslandPositions = positions
end

local function randomPointInRing(center, innerR, outerR)
	local angle = math.random() * math.pi * 2
	local dist = innerR + math.random() * (outerR - innerR)
	return center.X + math.cos(angle) * dist, center.Z + math.sin(angle) * dist
end

local function randomPointInCircle(center, radius)
	local angle = math.random() * math.pi * 2
	local dist = math.random() * radius
	return center.X + math.cos(angle) * dist, center.Z + math.sin(angle) * dist
end

-- ─── Create a tree ───
local function createTree(parent, position)
	local trunkHeight = math.random(10, 18)
	local trunkWidth = math.random() * 0.6 + 1.2

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
	for _ = 1, math.random(3, 5) do
		local leaf = Instance.new("Part")
		leaf.Name = "Leaves"
		leaf.Shape = Enum.PartType.Ball
		local leafSize = math.random(5, 10)
		leaf.Size = Vector3.new(leafSize, leafSize, leafSize)
		leaf.Position = position + Vector3.new(
			(math.random() - 0.5) * 5,
			trunkHeight + math.random() * 4 - 1,
			(math.random() - 0.5) * 5
		)
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

-- ─── Spawn pirate ───
local function spawnIslandPirate(model, centerPos, surfaceY)
	local pirateTemplate = rs:FindFirstChild("Pirate lvl1")
	if not pirateTemplate then return end

	local pirate = pirateTemplate:Clone()
	local px, pz = randomPointInCircle(centerPos, 15)
	local piratePos = Vector3.new(px, surfaceY + 5, pz)

	if pirate:IsA("Model") then
		pirate:PivotTo(CFrame.new(piratePos))
	end
	pirate.Parent = workspace

	for _, part in pirate:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	local hum = pirate:FindFirstChildWhichIsA("Humanoid")
	if hum then
		hum.WalkSpeed = 12
		hum.JumpPower = 30

		task.spawn(function()
			while pirate.Parent and hum.Health > 0 do
				local wx, wz = randomPointInCircle(centerPos, 20)
				hum:MoveTo(Vector3.new(wx, surfaceY + 2, wz))
				hum.MoveToFinished:Wait()
				task.wait(math.random(2, 5))
			end
		end)

		hum.Died:Connect(function()
			task.wait(3)
			pirate:Destroy()
		end)
	end

	pirate:SetAttribute("IslandPirate", true)
	return pirate
end

-- ─── Place Destroyed House ───
local function placeDestroyedHouse(parent, centerPos, surfaceY)
	local houseTemplate = rs:FindFirstChild("Destroyed house")
	if not houseTemplate then return end

	local house = houseTemplate:Clone()
	local hx = centerPos.X + (math.random() - 0.5) * 16
	local hz = centerPos.Z + (math.random() - 0.5) * 16

	-- Place ON the surface (use surfaceY + small offset so it sits on top)
	local houseY = surfaceY + 1

	if house:IsA("Model") then
		-- Get bounding box to offset properly
		local bbCF, bbSize = house:GetBoundingBox()
		houseY = surfaceY + bbSize.Y / 2
		house:PivotTo(CFrame.new(hx, houseY, hz) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0))
	elseif house:IsA("BasePart") then
		house.CFrame = CFrame.new(hx, houseY, hz)
	end

	for _, part in house:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	house.Parent = parent
end

-- ─── Create RAFT-style island ───
local function createIsland(centerPos, waterY)
	local radiusX = math.random(ISLAND_MIN_RADIUS, ISLAND_MAX_RADIUS)
	local radiusZ = math.random(ISLAND_MIN_RADIUS, ISLAND_MAX_RADIUS)
	local radius = math.max(radiusX, radiusZ)

	local model = Instance.new("Model")
	model.Name = "Island"

	local islandY = waterY + ISLAND_Y_OFFSET

	-- ══════════════════════════════════════
	-- LAYER 1: Sandy beach rim (outer ring, flat, at water level)
	-- ══════════════════════════════════════
	local beachHeight = 2
	local beach = Instance.new("Part")
	beach.Name = "Beach"
	beach.Size = Vector3.new(radiusX * 2.3, beachHeight, radiusZ * 2.3)
	beach.Position = Vector3.new(centerPos.X, islandY + beachHeight / 2, centerPos.Z)
	beach.Color = SAND_COLOR
	beach.Material = Enum.Material.Sand
	beach.Anchored = true
	beach.CanCollide = true
	beach.Parent = model

	local beachMesh = Instance.new("SpecialMesh")
	beachMesh.MeshType = Enum.MeshType.Sphere
	beachMesh.Scale = Vector3.new(1, 0.15, 1)
	beachMesh.Parent = beach

	-- Beach lobes for irregular coastline
	for _ = 1, math.random(3, 6) do
		local lobeAngle = math.random() * math.pi * 2
		local lobeDist = 0.35 + math.random() * 0.3
		local lobeRX = radiusX * (0.3 + math.random() * 0.4)
		local lobeRZ = radiusZ * (0.3 + math.random() * 0.4)

		local lobe = Instance.new("Part")
		lobe.Name = "BeachLobe"
		lobe.Size = Vector3.new(lobeRX * 2, beachHeight * 0.9, lobeRZ * 2)
		lobe.Position = Vector3.new(
			centerPos.X + math.cos(lobeAngle) * radiusX * lobeDist,
			islandY + beachHeight * 0.4,
			centerPos.Z + math.sin(lobeAngle) * radiusZ * lobeDist
		)
		lobe.Color = SAND_COLOR
		lobe.Material = Enum.Material.Sand
		lobe.Anchored = true
		lobe.CanCollide = true
		lobe.Parent = model

		local lobeMesh = Instance.new("SpecialMesh")
		lobeMesh.MeshType = Enum.MeshType.Sphere
		lobeMesh.Scale = Vector3.new(1, 0.15, 1)
		lobeMesh.Parent = lobe
	end

	-- ══════════════════════════════════════
	-- LAYER 2: Elevated dirt/grass center (inner area, raised)
	-- ══════════════════════════════════════
	local centerRadius = radius * 0.6
	local centerRX = radiusX * 0.6
	local centerRZ = radiusZ * 0.6
	local hillHeight = math.random(8, 14)

	local hillBase = Instance.new("Part")
	hillBase.Name = "HillBase"
	hillBase.Size = Vector3.new(centerRX * 2, hillHeight, centerRZ * 2)
	hillBase.Position = Vector3.new(centerPos.X, islandY + hillHeight / 2, centerPos.Z)
	hillBase.Color = DIRT_COLOR
	hillBase.Material = Enum.Material.Ground
	hillBase.Anchored = true
	hillBase.CanCollide = true
	hillBase.Parent = model

	local hillMesh = Instance.new("SpecialMesh")
	hillMesh.MeshType = Enum.MeshType.Sphere
	hillMesh.Scale = Vector3.new(1, 0.5, 1)
	hillMesh.Parent = hillBase

	-- Green grass cap on the hill
	local grassCap = Instance.new("Part")
	grassCap.Name = "GrassCap"
	grassCap.Size = Vector3.new(centerRX * 1.9, hillHeight * 0.3, centerRZ * 1.9)
	grassCap.Position = Vector3.new(centerPos.X, islandY + hillHeight * 0.75, centerPos.Z)
	grassCap.Color = GRASS_TOP
	grassCap.Material = Enum.Material.Grass
	grassCap.Anchored = true
	grassCap.CanCollide = true
	grassCap.Parent = model

	local grassCapMesh = Instance.new("SpecialMesh")
	grassCapMesh.MeshType = Enum.MeshType.Sphere
	grassCapMesh.Scale = Vector3.new(1, 0.3, 1)
	grassCapMesh.Parent = grassCap

	-- Hill lobes for uneven shape
	for _ = 1, math.random(3, 5) do
		local lobeAngle = math.random() * math.pi * 2
		local lobeDist = 0.2 + math.random() * 0.4
		local lobeRX = centerRX * (0.3 + math.random() * 0.4)
		local lobeRZ = centerRZ * (0.3 + math.random() * 0.4)
		local lobeH = hillHeight * (0.5 + math.random() * 0.4)

		local hillLobe = Instance.new("Part")
		hillLobe.Name = "HillLobe"
		hillLobe.Size = Vector3.new(lobeRX * 2, lobeH, lobeRZ * 2)
		hillLobe.Position = Vector3.new(
			centerPos.X + math.cos(lobeAngle) * centerRX * lobeDist,
			islandY + lobeH / 2,
			centerPos.Z + math.sin(lobeAngle) * centerRZ * lobeDist
		)
		hillLobe.Color = DIRT_COLOR
		hillLobe.Material = Enum.Material.Ground
		hillLobe.Anchored = true
		hillLobe.CanCollide = true
		hillLobe.Parent = model

		local hlMesh = Instance.new("SpecialMesh")
		hlMesh.MeshType = Enum.MeshType.Sphere
		hlMesh.Scale = Vector3.new(1, 0.45, 1)
		hlMesh.Parent = hillLobe

		-- Grass on top of each lobe
		local lobeCap = Instance.new("Part")
		lobeCap.Name = "LobeGrass"
		lobeCap.Size = Vector3.new(lobeRX * 1.8, lobeH * 0.2, lobeRZ * 1.8)
		lobeCap.Position = Vector3.new(
			hillLobe.Position.X,
			islandY + lobeH * 0.75,
			hillLobe.Position.Z
		)
		lobeCap.Color = GRASS_TOP
		lobeCap.Material = Enum.Material.Grass
		lobeCap.Anchored = true
		lobeCap.CanCollide = false
		lobeCap.Parent = model

		local lcMesh = Instance.new("SpecialMesh")
		lcMesh.MeshType = Enum.MeshType.Sphere
		lcMesh.Scale = Vector3.new(1, 0.2, 1)
		lcMesh.Parent = lobeCap
	end

	-- ══════════════════════════════════════
	-- LAYER 3: Rocky peak (small elevated rocky area)
	-- ══════════════════════════════════════
	local peakOffsetX = (math.random() - 0.5) * centerRX * 0.4
	local peakOffsetZ = (math.random() - 0.5) * centerRZ * 0.4
	local peakHeight = hillHeight * (0.6 + math.random() * 0.4)
	local peakRX = centerRX * (0.2 + math.random() * 0.2)
	local peakRZ = centerRZ * (0.2 + math.random() * 0.2)

	local peak = Instance.new("Part")
	peak.Name = "RockyPeak"
	peak.Size = Vector3.new(peakRX * 2, peakHeight, peakRZ * 2)
	peak.Position = Vector3.new(
		centerPos.X + peakOffsetX,
		islandY + hillHeight * 0.5 + peakHeight * 0.3,
		centerPos.Z + peakOffsetZ
	)
	peak.Color = ROCK_COLOR
	peak.Material = Enum.Material.Slate
	peak.Anchored = true
	peak.CanCollide = true
	peak.Parent = model

	local peakMesh = Instance.new("SpecialMesh")
	peakMesh.MeshType = Enum.MeshType.Sphere
	peakMesh.Scale = Vector3.new(1, 0.6, 1)
	peakMesh.Parent = peak

	-- Extra rock formations
	for _ = 1, math.random(3, 6) do
		local rx, rz = randomPointInCircle(centerPos, centerRadius * 0.7)
		local rockSize = math.random(3, 8)
		local rock = Instance.new("Part")
		rock.Name = "Rock"
		rock.Size = Vector3.new(rockSize, rockSize * (0.5 + math.random() * 0.5), rockSize * 0.8)
		rock.Position = Vector3.new(rx, islandY + hillHeight * 0.4 + rockSize * 0.2, rz)
		rock.Color = math.random() > 0.5 and ROCK_COLOR or ROCK_DARK
		rock.Material = Enum.Material.Slate
		rock.Anchored = true
		rock.CanCollide = true
		rock.CFrame = rock.CFrame * CFrame.Angles(
			math.rad(math.random(-20, 20)),
			math.rad(math.random(0, 360)),
			math.rad(math.random(-20, 20))
		)
		rock.Parent = model
	end

	-- ══════════════════════════════════════
	-- LAYER 4: Underwater base
	-- ══════════════════════════════════════
	local underwaterHeight = math.random(15, 25)
	local underwaterBase = Instance.new("Part")
	underwaterBase.Name = "UnderwaterBase"
	underwaterBase.Size = Vector3.new(radiusX * 2, underwaterHeight, radiusZ * 2)
	underwaterBase.Position = Vector3.new(centerPos.X, islandY - underwaterHeight / 2 + 1, centerPos.Z)
	underwaterBase.Color = SAND_DARK
	underwaterBase.Material = Enum.Material.Sand
	underwaterBase.Anchored = true
	underwaterBase.CanCollide = true
	underwaterBase.Parent = model

	local uwMesh = Instance.new("SpecialMesh")
	uwMesh.MeshType = Enum.MeshType.Sphere
	uwMesh.Scale = Vector3.new(1, 0.5, 1)
	uwMesh.Parent = underwaterBase

	-- ══════════════════════════════════════
	-- DECORATIONS: Trees (only on dirt/grass area, NOT beach)
	-- ══════════════════════════════════════
	local hillSurfaceY = islandY + hillHeight * 0.5
	local numTrees = math.random(5, 12)
	for _ = 1, numTrees do
		local tx, tz = randomPointInCircle(centerPos, centerRadius * 0.85)
		createTree(model, Vector3.new(tx, hillSurfaceY, tz))
	end

	-- Grass tufts on the green area
	for _ = 1, math.random(10, 25) do
		local gx, gz = randomPointInCircle(centerPos, centerRadius * 0.9)
		createGrass(model, Vector3.new(gx, hillSurfaceY, gz))
	end

	-- Place Destroyed House on the hill surface
	placeDestroyedHouse(model, centerPos, hillSurfaceY)

	model.Parent = workspace
	model.PrimaryPart = beach

	-- Spawn pirate on the hill
	local pirate = spawnIslandPirate(model, centerPos, hillSurfaceY)

	return {
		model = model,
		center = centerPos,
		radius = radius,
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

	updateGlobalIslandPositions()

	if #islands < MAX_ISLANDS then
		local angle = math.random() * math.pi * 2
		local dist = math.random(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX)

		local spawnPos = Vector3.new(
			raftPos.X + math.cos(angle) * dist,
			waterY,
			raftPos.Z + math.sin(angle) * dist
		)

		if not isTooCloseToIsland(spawnPos, ISLAND_MIN_RADIUS * 3) then
			local island = createIsland(spawnPos, waterY)
			table.insert(islands, island)
			updateGlobalIslandPositions()
		end
	end
end
