local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")

local CLICKS_TO_COLLECT = 5
local LIFETIME = 120
local AREA_SIZE = 25
local MAX_PER_AREA = 25

-- Per-resource click overrides (default = CLICKS_TO_COLLECT)
local CLICKS_BY_TYPE = {
	Leaves = 3,
}

-- ─── Raft collision damage config ───
local COLLISION_VEL_THRESHOLD = 3  -- minimum relative velocity for damage
local COLLISION_DAMAGE_DIVISOR = 5 -- damage = floor(velocity / divisor)
local COLLISION_COOLDOWN = 0.5     -- seconds between damage events per resource

local collectEvent = rs:FindFirstChild("CollectResource")
if not collectEvent then
	collectEvent = Instance.new("RemoteEvent")
	collectEvent.Name = "CollectResource"
	collectEvent.Parent = rs
end

local collectNotify = rs:FindFirstChild("CollectNotify")
if not collectNotify then
	collectNotify = Instance.new("RemoteEvent")
	collectNotify.Name = "CollectNotify"
	collectNotify.Parent = rs
end

local inventoryEvent = rs:FindFirstChild("InventoryUpdate")
if not inventoryEvent then
	inventoryEvent = Instance.new("RemoteEvent")
	inventoryEvent.Name = "InventoryUpdate"
	inventoryEvent.Parent = rs
end

local _G_Inventories = {}
_G.GetInventory = function(player)
	if not _G_Inventories[player] then
		_G_Inventories[player] = {Log = 0, Plastic = 0}
	end
	-- Ensure fields exist for old inventories
	if not _G_Inventories[player].Plastic then
		_G_Inventories[player].Plastic = 0
	end
	if not _G_Inventories[player].Stone then
		_G_Inventories[player].Stone = 0
	end
	if not _G_Inventories[player].Plank then
		_G_Inventories[player].Plank = 0
	end
	if not _G_Inventories[player].Leaves then
		_G_Inventories[player].Leaves = 0
	end
	if not _G_Inventories[player].Rope then
		_G_Inventories[player].Rope = 0
	end
	if not _G_Inventories[player].Sand then
		_G_Inventories[player].Sand = 0
	end
	if not _G_Inventories[player].Clay then
		_G_Inventories[player].Clay = 0
	end
	if not _G_Inventories[player].Wet_Brick then
		_G_Inventories[player].Wet_Brick = 0
	end
	if not _G_Inventories[player].Dry_Brick then
		_G_Inventories[player].Dry_Brick = 0
	end
	-- Fish species (ReplicatedStorage.Fish). They're stored as stackable
	-- resources so the player can catch, drop, and pick them back up.
	local fishSpecies = {
		"Blue_Fish", "Carp_Fish", "Fish_Bones", "Foil_Fish",
		"Jelly_Fish", "Legendary_Fish", "Seabass_Fish", "Tilapia_Fish",
	}
	for _, species in fishSpecies do
		if not _G_Inventories[player][species] then
			_G_Inventories[player][species] = 0
		end
	end
	return _G_Inventories[player]
end

_G.SendInventory = function(player)
	inventoryEvent:FireClient(player, _G.GetInventory(player))
end

-- Spawn cycle counter for different spawn rates
local spawnCycle = 0

local function getBoat()
	return workspace:FindFirstChild("Raft")
end

local function getResourceFromPart(part)
	if CollectionService:HasTag(part, "Resource") then
		return part
	end

	local model = part:FindFirstAncestorOfClass("Model")
	if model and CollectionService:HasTag(model, "Resource") then
		return model
	end

	return nil
end

Players.PlayerRemoving:Connect(function(player)
	_G_Inventories[player] = nil
end)

-- ═══════════════════════════════════════════════════════════════════════
-- Unified HP system: both clicks and raft collisions reduce the same HP
-- pool. The progress bar updates for all clients from either source.
-- ═══════════════════════════════════════════════════════════════════════

local function damageResource(resource, amount)
	local hp = resource:GetAttribute("ResourceHP")
	local maxHP = resource:GetAttribute("ResourceMaxHP")
	if not hp or not maxHP or hp <= 0 then return 0 end

	hp = math.max(0, hp - amount)
	resource:SetAttribute("ResourceHP", hp)

	-- Notify all clients so everyone's progress bar updates
	local totalDamage = maxHP - hp
	collectNotify:FireAllClients("progress", resource, totalDamage, maxHP)

	return hp
end

collectEvent.OnServerEvent:Connect(function(player, targetPart)
	if typeof(targetPart) ~= "Instance" then return end
	if not targetPart:IsDescendantOf(workspace) then return end

	local resource = getResourceFromPart(targetPart)
	if not resource then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local resourcePos
	if resource:IsA("Model") then
		resourcePos = resource:GetPivot().Position
	else
		resourcePos = resource.Position
	end

	local dist = (char.HumanoidRootPart.Position - resourcePos).Magnitude
	if dist > 50 then return end

	local hp = damageResource(resource, 1)

	if hp <= 0 then
		-- Collected by player click: give reward
		local inv = _G.GetInventory(player)

		local resType = resource:GetAttribute("ResourceType") or "Log"
		local resAmount = resource:GetAttribute("ResourceAmount") or 1

		inv[resType] = (inv[resType] or 0) + resAmount
		collectNotify:FireClient(player, "collected", resource, resType, resAmount)
		collectNotify:FireAllClients("broke", resource, resType)
		_G.SendInventory(player)

		resource:Destroy()
	end
end)

-- ═══════════════════════════════════════════════════════════════════════
-- Raft collision damage: resources lose HP when the raft runs into them.
-- A fatal collision destroys the resource without giving any reward.
-- ═══════════════════════════════════════════════════════════════════════

local collisionCooldowns = setmetatable({}, {__mode = "k"})

local function setupResourceCollision(resource, maxHP)
	resource:SetAttribute("ResourceHP", maxHP)
	resource:SetAttribute("ResourceMaxHP", maxHP)

	local function onTouched(resPart, otherPart)
		-- Only take damage from the Raft model
		local raft = getBoat()
		if not raft then return end
		if not otherPart:IsDescendantOf(raft) then return end

		-- Per-resource cooldown so Touched spam doesn't shred HP in one frame
		local now = tick()
		local lastHit = collisionCooldowns[resource]
		if lastHit and (now - lastHit) < COLLISION_COOLDOWN then return end

		-- Relative velocity between resource part and raft part
		local relVel = (resPart.AssemblyLinearVelocity - otherPart.AssemblyLinearVelocity).Magnitude
		if relVel < COLLISION_VEL_THRESHOLD then return end

		local damage = math.max(1, math.floor(relVel / COLLISION_DAMAGE_DIVISOR))
		collisionCooldowns[resource] = now

		local hp = damageResource(resource, damage)

		if hp <= 0 then
			-- Fatal collision: destroy without reward, play break sound
			local resType = resource:GetAttribute("ResourceType") or "Log"
			collectNotify:FireAllClients("broke", resource, resType)
			resource:Destroy()
		end
	end

	-- Connect Touched on every BasePart in the resource
	if resource:IsA("BasePart") then
		resource.Touched:Connect(function(other) onTouched(resource, other) end)
	end
	for _, part in resource:GetDescendants() do
		if part:IsA("BasePart") then
			part.Touched:Connect(function(other) onTouched(part, other) end)
		end
	end
end

local function spawnResource(templateName, resourceType, resourceAmount, boat)
	local root = boat.PrimaryPart
	local waterY = root.Position.Y
	-- Use raft's actual movement direction so resources always spawn ahead
	local velocity = root.AssemblyLinearVelocity
	local flatVel = Vector3.new(velocity.X, 0, velocity.Z)
	local forward
	if flatVel.Magnitude > 0.5 then
		forward = flatVel.Unit
	else
		-- Fallback when raft hasn't started moving yet
		local rawForward = root.CFrame.LookVector
		forward = Vector3.new(rawForward.X, 0, rawForward.Z).Unit
	end
	local spawnPos = Vector3.new(
		root.Position.X + forward.X * math.random(300, 450) + math.random(-75, 75),
		waterY,
		root.Position.Z + forward.Z * math.random(300, 450) + math.random(-75, 75)
	)

	-- Don't spawn resources on islands
	local islandPositions = _G.IslandPositions or {}
	for _, island in islandPositions do
		local dx = spawnPos.X - island.center.X
		local dz = spawnPos.Z - island.center.Z
		if math.sqrt(dx * dx + dz * dz) < (island.radius or 100) + 20 then
			return
		end
	end

	-- Check density in the area around the spawn position
	local nearby = 0
	for _, res in CollectionService:GetTagged("Resource") do
		local resPos
		if res:IsA("Model") then
			resPos = res:GetPivot().Position
		else
			resPos = res.Position
		end
		if math.abs(resPos.X - spawnPos.X) < AREA_SIZE / 2 and math.abs(resPos.Z - spawnPos.Z) < AREA_SIZE / 2 then
			nearby = nearby + 1
		end
	end
	if nearby >= MAX_PER_AREA then return end

	local template = rs:FindFirstChild(templateName)
	if not template then
		-- Case-insensitive fallback in case the model was renamed
		local lower = string.lower(templateName)
		for _, child in rs:GetChildren() do
			if string.lower(child.Name) == lower then
				template = child
				break
			end
		end
	end
	if not template then
		warn("[ResourceSpawner] template not found: " .. templateName)
		return
	end
	local clone = template:Clone()

	if not clone.PrimaryPart then
		local first = clone:FindFirstChildWhichIsA("BasePart", true)
		if first then
			clone.PrimaryPart = first
		end
	end

	-- Align the model's pivot with its PrimaryPart so PivotTo positions the
	-- visible part exactly where we want it (otherwise WorldPivot can be at
	-- the bounding box center and the part ends up far from the spawn point).
	if clone.PrimaryPart then
		clone.WorldPivot = clone.PrimaryPart.CFrame
	end

	clone:SetAttribute("ResourceType", resourceType)
	clone:SetAttribute("ResourceAmount", resourceAmount)

	-- Lay logs flat (rotate 90° around Z) with a random spin so they look natural
	if resourceType == "Log" then
		local yaw = math.random() * math.pi * 2
		clone:PivotTo(CFrame.new(spawnPos) * CFrame.Angles(0, yaw, math.rad(90)))
	else
		clone:PivotTo(CFrame.new(spawnPos))
	end

	clone.Parent = workspace

	-- Unanchor the clone itself if it's a BasePart (GetDescendants doesn't
	-- include the instance itself, so single-part resources stayed anchored).
	if clone:IsA("BasePart") then
		clone.Anchored = false
		clone:SetNetworkOwner(nil)
	end

	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part:SetNetworkOwner(nil)
		end
	end

	-- Give resources a small random drift so they move visibly on the water
	local driftAngle = math.random() * math.pi * 2
	local driftSpeed = math.random(2, 5)
	local driftVel = Vector3.new(math.cos(driftAngle) * driftSpeed, 0, math.sin(driftAngle) * driftSpeed)
	local rootPart = clone:IsA("BasePart") and clone or clone.PrimaryPart
	if rootPart then
		rootPart.AssemblyLinearVelocity = driftVel
	end

	CollectionService:AddTag(clone, "Resource")

	-- Set up collision damage so the raft can crush resources
	local maxHP = CLICKS_BY_TYPE[resourceType] or CLICKS_TO_COLLECT
	setupResourceCollision(clone, maxHP)

	task.delay(LIFETIME, function()
		if clone and clone.Parent then
			clone:Destroy()
		end
	end)
end

while true do
	task.wait(3)

	local boat = getBoat()
	if not boat then continue end

	spawnCycle = spawnCycle + 1

	-- Log: every cycle
	spawnResource("Log", "Log", 1, boat)

	-- plastic_bottle: every 2nd cycle (half as often)
	if spawnCycle % 2 == 0 then
		spawnResource("plastic_bottle", "Plastic", 1, boat)
	end

	-- plastic_canister: every 4th cycle (quarter as often)
	if spawnCycle % 4 == 0 then
		spawnResource("plastic_canister", "Plastic", 3, boat)
	end

	-- Leaves: every cycle (same chance as Log)
	spawnResource("leaves", "Leaves", 1, boat)

end
