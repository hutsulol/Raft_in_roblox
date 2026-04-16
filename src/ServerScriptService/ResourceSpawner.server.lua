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

-- ─── Inventory capacity helpers ────────────────────────────────────────
-- The client lays out inventory as slots of MAX_STACK, constrained by
-- the player's UnlockedInventorySlots (driven by the Strength stat).
-- The helpers below mirror the client's layout math so overflow is
-- redirected to a world drop instead of becoming invisible items.
local MAX_STACK = 30
local DEFAULT_HOTBAR_SLOTS = 8
local DEFAULT_BASE_GRID_SLOTS = 5

local TOTAL_SLOTS = 28

local function getUnlockedSlots(player)
	local chars = player and player:FindFirstChild("Characteristics")
	if chars then
		local unlocked = chars:FindFirstChild("UnlockedInventorySlots")
		if unlocked and typeof(unlocked.Value) == "number" then
			return math.clamp(unlocked.Value, DEFAULT_HOTBAR_SLOTS + DEFAULT_BASE_GRID_SLOTS, TOTAL_SLOTS)
		end
	end
	return DEFAULT_HOTBAR_SLOTS + DEFAULT_BASE_GRID_SLOTS
end

-- Count unique tool names (matching client layout: one slot per unique name)
local function countToolSlots(player)
	local seen = {}
	local backpack = player and player:FindFirstChild("Backpack")
	if backpack then
		for _, tool in backpack:GetChildren() do
			if tool:IsA("Tool") then seen[tool.Name] = true end
		end
	end
	local char = player and player.Character
	if char then
		for _, tool in char:GetChildren() do
			if tool:IsA("Tool") then seen[tool.Name] = true end
		end
	end
	local n = 0
	for _ in pairs(seen) do n = n + 1 end
	return n
end

local function countResourceStacks(inv, excludeName)
	local n = 0
	for name, count in pairs(inv) do
		if name ~= excludeName and type(count) == "number" and count > 0 then
			n = n + math.ceil(count / MAX_STACK)
		end
	end
	return n
end

-- Total resource stacks in the inventory
local function getTotalResourceStacks(inv)
	local total = 0
	for _, count in pairs(inv) do
		if type(count) == "number" and count > 0 then
			total = total + math.ceil(count / MAX_STACK)
		end
	end
	return total
end

-- Get the player's HumanoidRootPart position (for drop location)
local function getPlayerPosition(player)
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position or nil
end

-- ─── Centralised overflow guard ────────────────────────────────────────
-- RULE: the inventory sent to the client NEVER has more resource stacks
-- than the player's unlocked slot budget. Any excess is trimmed and
-- dropped as a physical item at the player's feet. This runs on EVERY
-- SendInventory call regardless of how items were added.

_G.SendInventory = function(player)
	local inv = _G.GetInventory(player)
	local unlocked = getUnlockedSlots(player)
	local tools = countToolSlots(player)
	local maxResourceSlots = math.max(0, unlocked - tools)
	local dropPos = getPlayerPosition(player)

	-- Trim until total resource stacks fit within the budget
	local totalStacks = getTotalResourceStacks(inv)
	while totalStacks > maxResourceSlots do
		-- Find the resource whose last (partial) stack is smallest
		local trimName = nil
		local trimAmount = MAX_STACK + 1
		for name, count in pairs(inv) do
			if type(count) == "number" and count > 0 then
				local stacks = math.ceil(count / MAX_STACK)
				local lastStack = count - (stacks - 1) * MAX_STACK
				if lastStack < trimAmount then
					trimAmount = lastStack
					trimName = name
				end
			end
		end
		if not trimName then break end

		inv[trimName] = inv[trimName] - trimAmount
		if inv[trimName] <= 0 then inv[trimName] = 0 end
		totalStacks = totalStacks - 1

		if trimAmount > 0 and _G.SpawnResourceDrop then
			_G.SpawnResourceDrop(player, trimName, trimAmount, dropPos)
		end
	end

	inventoryEvent:FireClient(player, inv)
end

-- How many more units of `itemName` can this player accept without
-- overflowing the visible (unlocked) inventory? Accounts for room left
-- in the partial stack of the same item plus any fully-empty slots.
_G.GetInventoryCapacity = function(player, itemName)
	local inv = _G.GetInventory(player)
	local unlocked = getUnlockedSlots(player)
	local tools = countToolSlots(player)

	local existing = (itemName and inv[itemName]) or 0
	local existingStacks = existing > 0 and math.ceil(existing / MAX_STACK) or 0
	local partialSpace = existingStacks > 0
		and (existingStacks * MAX_STACK - existing)
		or 0

	local otherStacks = countResourceStacks(inv, itemName)
	local usedSlots   = tools + existingStacks + otherStacks

	-- If already over capacity (historical overflow), no room at all
	if usedSlots > unlocked then
		return 0
	end

	local emptySlots = unlocked - usedSlots
	return emptySlots * MAX_STACK + partialSpace
end

-- Canonical "player gained a resource" entry point. Adds what fits and
-- spawns the overflow as a physical drop next to the player (via
-- _G.SpawnResourceDrop, defined by DropItem.server.lua). Callers that
-- previously wrote `inv[x] = (inv[x] or 0) + amount` should use this.
--
-- Returns (added, overflow). `dropPosition` is optional; if nil, the
-- overflow spawns in front of the player.
_G.AddResourceToInventory = function(player, itemName, amount, dropPosition)
	if type(itemName) ~= "string" or itemName == "" then return 0, 0 end
	amount = tonumber(amount) or 0
	if amount <= 0 then return 0, 0 end

	local inv = _G.GetInventory(player)
	local capacity = _G.GetInventoryCapacity(player, itemName)
	local toAdd    = math.min(amount, math.max(0, capacity))
	local overflow = amount - toAdd

	if toAdd > 0 then
		inv[itemName] = (inv[itemName] or 0) + toAdd
	end

	if overflow > 0 and _G.SpawnResourceDrop then
		_G.SpawnResourceDrop(player, itemName, overflow, dropPosition)
	end

	_G.SendInventory(player)
	return toAdd, overflow
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
	_prevInvState[player] = nil
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
		-- Collected by player click: give reward. Routes through
		-- AddResourceToInventory so a full inventory doesn't silently
		-- eat the reward — overflow spawns as a world drop next to
		-- where the resource was.
		local resType = resource:GetAttribute("ResourceType") or "Log"
		local resAmount = resource:GetAttribute("ResourceAmount") or 1

		_G.AddResourceToInventory(player, resType, resAmount, resourcePos)
		collectNotify:FireClient(player, "collected", resource, resType, resAmount)
		collectNotify:FireAllClients("broke", resource, resType)

		if _G.OnQuestResource then
			_G.OnQuestResource(player, resType, resAmount)
		end

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
			-- Fatal collision: destroy without reward, no break sound
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

	-- plastic_canister: every 4th cycle (quarter as often)
	if spawnCycle % 4 == 0 then
		spawnResource("plastic_canister", "Plastic", 3, boat)
	end

	-- Leaves: every cycle (same chance as Log)
	spawnResource("leaves", "Leaves", 1, boat)

end
