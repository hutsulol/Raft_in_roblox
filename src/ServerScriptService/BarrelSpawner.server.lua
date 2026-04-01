-- BarrelSpawner.server.lua
-- Spawns WoodenBarrel resources in the ocean, separate from ResourceSpawner

local CollectionService = game:GetService("CollectionService")
local rs = game:GetService("ReplicatedStorage")

local SPAWN_INTERVAL = 3 -- same as main resource spawner
local LIFETIME = 120

local function getBoat()
	return workspace:FindFirstChild("Raft")
end

-- Wait for boat
local boat = getBoat()
while not boat do
	task.wait(1)
	boat = getBoat()
end
while not boat.PrimaryPart do
	task.wait(0.1)
end

local function spawnBarrel()
	boat = getBoat()
	if not boat or not boat.PrimaryPart then return end

	local root = boat.PrimaryPart
	local waterY = root.Position.Y
	local spawnPos = Vector3.new(
		root.Position.X + root.CFrame.LookVector.X * math.random(300, 450) + math.random(-75, 75),
		waterY,
		root.Position.Z + root.CFrame.LookVector.Z * math.random(300, 450) + math.random(-75, 75)
	)

	-- Don't spawn on islands
	local islandPositions = _G.IslandPositions or {}
	for _, island in islandPositions do
		local dx = spawnPos.X - island.center.X
		local dz = spawnPos.Z - island.center.Z
		if math.sqrt(dx * dx + dz * dz) < (island.radius or 100) + 20 then
			return
		end
	end

	local template = rs:FindFirstChild("WoodenBarrel")
	if not template then
		warn("BarrelSpawner: WoodenBarrel not found in ReplicatedStorage")
		return
	end

	local clone = template:Clone()

	if clone:IsA("Model") and not clone.PrimaryPart then
		local first = clone:FindFirstChildWhichIsA("BasePart", true)
		if first then
			clone.PrimaryPart = first
		end
	end

	clone:SetAttribute("ResourceType", "Barrel")
	clone:SetAttribute("ResourceAmount", 0)

	clone:PivotTo(CFrame.new(spawnPos))
	clone.Parent = workspace

	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part:SetNetworkOwner(nil)
		end
	end

	CollectionService:AddTag(clone, "Resource")

	task.delay(LIFETIME, function()
		if clone and clone.Parent then
			clone:Destroy()
		end
	end)
end

while true do
	task.wait(SPAWN_INTERVAL)
	spawnBarrel()
end
