local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local dropEvent = Instance.new("RemoteEvent")
dropEvent.Name = "DropItem"
dropEvent.Parent = ReplicatedStorage

local pickupEvent = Instance.new("RemoteEvent")
pickupEvent.Name = "PickupDroppedItem"
pickupEvent.Parent = ReplicatedStorage

-- Map resource names to their 3D template names in ReplicatedStorage.
-- Missing entries fall through to FALLBACK_TEMPLATE below. The template
-- lookup tries a top-level `FindFirstChild` first and then a recursive
-- search, so templates nested inside folders (ReplicatedStorage.Fish,
-- ReplicatedStorage.MainModule, etc.) resolve without hard-coding paths.
local RESOURCE_TEMPLATES = {
	Log        = "Log",
	Plastic    = "plastic_model",
	Stone      = "stone",
	Iron_Ore   = "iron_model",
	Iron_Ingot = "box_model",
	Plank      = "plank",
	Leaves     = "leaves",
	-- Craftable / dug resources introduced after the initial set. They
	-- may not have dedicated 3D models yet; if the named template can't
	-- be found, the lookup silently falls back to FALLBACK_TEMPLATE so
	-- they still drop as a generic box until proper art is added.
	Rope       = "Rope",
	Sand       = "Sand",
	Clay       = "Clay",
	Wet_Brick  = "Wet_Brick",
	Dry_Brick  = "Dry_Brick",
	-- Fish (templates live in ReplicatedStorage.Fish, which the lookup
	-- below searches recursively so the space-in-name children resolve).
	Blue_Fish       = "Blue Fish",
	Carp_Fish       = "Carp Fish",
	Fish_Bones      = "Fish Bones",
	Foil_Fish       = "Foil Fish",
	Jelly_Fish      = "Jelly Fish",
	Legendary_Fish  = "Legendary Fish",
	Seabass_Fish    = "Seabass Fish",
	Tilapia_Fish    = "Tilapia Fish",
}

-- Known resource names (items stored as counts in inventory, not as
-- Tool instances in the backpack). Anything not in this set is handled
-- through the tool-drop branch below. Keep this list in sync with
-- ResourceSpawner.server.lua's `GetInventory` defaults and the client
-- inventory's RESOURCE_ICONS table.
local RESOURCE_ITEMS = {
	Log        = true,
	Plastic    = true,
	Stone      = true,
	Iron_Ore   = true,
	Iron_Ingot = true,
	Plank      = true,
	Leaves     = true,
	Rope       = true,
	Sand       = true,
	Clay       = true,
	Wet_Brick  = true,
	Dry_Brick  = true,
	Blue_Fish       = true,
	Carp_Fish       = true,
	Fish_Bones      = true,
	Foil_Fish       = true,
	Jelly_Fish      = true,
	Legendary_Fish  = true,
	Seabass_Fish    = true,
	Tilapia_Fish    = true,
}

-- Fallback template for any unmapped items (tools, etc.)
local FALLBACK_TEMPLATE = "box_model"

-- Shared helper: find a template by name, top-level first and then
-- recursively. Mirrors InventoryCrafting.server.lua so tools stored
-- inside subfolders (e.g. ReplicatedStorage.MainModule.FishingRod) are
-- picked up for both the physical drop and the pickup restore.
local function findTemplate(name)
	if type(name) ~= "string" or name == "" then return nil end
	local t = ReplicatedStorage:FindFirstChild(name)
	if not t then
		t = ReplicatedStorage:FindFirstChild(name, true)
	end
	return t
end

local DROP_COOLDOWN = 0.3
local DROPPED_LIFETIME = 120
local MAX_DROP_DISTANCE = 80
local PICKUP_DISTANCE = 15
local lastDropTime = {}

-- Spawn a physical dropped-item in the world near the player. Shared
-- between the explicit "drop from inventory" event and the
-- inventory-full overflow path (_G.SpawnResourceDrop below). Caller is
-- responsible for any inventory / tool bookkeeping before calling this.
local function spawnPhysicalDrop(player, itemName, amount, isToolDrop, dropPosition)
	if type(itemName) ~= "string" or itemName == "" then return nil end
	amount = tonumber(amount) or 0
	if amount <= 0 then return nil end

	local char = player and player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	-- Find the template. Resources prefer their mapped name and fall
	-- back to FALLBACK_TEMPLATE; tool drops use the fallback box.
	local templateName = RESOURCE_TEMPLATES[itemName] or FALLBACK_TEMPLATE
	local template = findTemplate(templateName)
	if not template then
		template = findTemplate(FALLBACK_TEMPLATE)
	end
	if not template then return nil end

	-- Determine spawn position
	local spawnPos
	if typeof(dropPosition) == "Vector3"
		and (dropPosition - hrp.Position).Magnitude < MAX_DROP_DISTANCE then
		spawnPos = dropPosition + Vector3.new(0, 2, 0)
	else
		local lookDir = hrp.CFrame.LookVector
		spawnPos = hrp.Position + lookDir * 4 + Vector3.new(0, -1, 0)
	end

	local clone = template:Clone()

	if clone:IsA("Model") and not clone.PrimaryPart then
		local first = clone:FindFirstChildWhichIsA("BasePart")
		if first then
			clone.PrimaryPart = first
		end
	end

	clone:SetAttribute("ResourceType", itemName)
	clone:SetAttribute("ResourceAmount", amount)
	clone:SetAttribute("IsToolDrop", isToolDrop and true or false)
	clone:SetAttribute("DropperUserId", player.UserId)

	clone:PivotTo(CFrame.new(spawnPos))
	clone.Parent = workspace

	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = true
			part.Massless = true
			part:SetNetworkOwner(nil)
		end
	end
	-- Also handle the clone itself if it's a BasePart (not a Model)
	if clone:IsA("BasePart") then
		clone.Anchored = false
		clone.CanCollide = true
		clone.Massless = true
		clone:SetNetworkOwner(nil)
	end

	-- Inherit the raft's velocity so the item stays with the raft long
	-- enough to be detected by on-raft systems (e.g. sawmill log polling).
	local raft = workspace:FindFirstChild("Raft")
	local primaryClonePart = clone:IsA("BasePart") and clone or (clone:IsA("Model") and clone.PrimaryPart)
	if raft and raft.PrimaryPart and primaryClonePart then
		primaryClonePart.AssemblyLinearVelocity = raft.PrimaryPart.AssemblyLinearVelocity
	end

	-- Strip any "Resource" tags the template may carry so the
	-- ResourceSpawner click-to-collect system ignores dropped items.
	CollectionService:RemoveTag(clone, "Resource")
	for _, desc in clone:GetDescendants() do
		CollectionService:RemoveTag(desc, "Resource")
	end

	CollectionService:AddTag(clone, "DroppedItem")

	task.delay(DROPPED_LIFETIME, function()
		if clone and clone.Parent then
			clone:Destroy()
		end
	end)

	return clone
end

-- Exposed so the inventory-add path can overflow directly to the world
-- without routing through the drop event.
_G.SpawnResourceDrop = function(player, itemName, amount, dropPosition)
	return spawnPhysicalDrop(player, itemName, amount, false, dropPosition)
end

dropEvent.OnServerEvent:Connect(function(player, itemName, dropCount, dropPosition)
	if type(itemName) ~= "string" then return end
	if type(dropCount) ~= "number" then return end
	if typeof(dropPosition) ~= "Vector3" then dropPosition = nil end

	dropCount = math.floor(math.clamp(dropCount, 1, 30))

	-- Cooldown
	local now = tick()
	if lastDropTime[player] and now - lastDropTime[player] < DROP_COOLDOWN then return end
	lastDropTime[player] = now

	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local isResource = RESOURCE_ITEMS[itemName]

	if isResource then
		-- Resource drop: deduct from inventory count
		local inv = _G.GetInventory and _G.GetInventory(player)
		if not inv then return end
		if (inv[itemName] or 0) < dropCount then return end
		inv[itemName] = inv[itemName] - dropCount
	else
		-- Tool drop: find and remove the tool from backpack or character
		local tool = nil
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			tool = backpack:FindFirstChild(itemName)
		end
		if not tool and char then
			tool = char:FindFirstChild(itemName)
			if tool and not tool:IsA("Tool") then tool = nil end
		end
		if not tool then return end
		tool:Destroy()
	end

	spawnPhysicalDrop(player, itemName, dropCount, not isResource, dropPosition)

	-- Sync inventory to client
	if _G.SendInventory then
		_G.SendInventory(player)
	end
end)

-- E-key instant pickup for dropped items
pickupEvent.OnServerEvent:Connect(function(player, targetPart)
	if not targetPart or not targetPart.Parent then return end

	-- Find the dropped item (could be a part or a model)
	local droppedItem = nil
	if CollectionService:HasTag(targetPart, "DroppedItem") then
		droppedItem = targetPart
	else
		local model = targetPart:FindFirstAncestorOfClass("Model")
		if model and CollectionService:HasTag(model, "DroppedItem") then
			droppedItem = model
		end
	end
	if not droppedItem then return end

	-- Distance check
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local itemPos
	if droppedItem:IsA("Model") then
		itemPos = droppedItem:GetPivot().Position
	else
		itemPos = droppedItem.Position
	end
	if (hrp.Position - itemPos).Magnitude > PICKUP_DISTANCE then return end

	-- Get item info
	local resType = droppedItem:GetAttribute("ResourceType")
	local resAmount = droppedItem:GetAttribute("ResourceAmount") or 1
	local isToolDrop = droppedItem:GetAttribute("IsToolDrop")
	if not resType then return end

	if isToolDrop then
		-- Tool pickup: clone the tool template and give to player. Tool
		-- templates may live under ReplicatedStorage.MainModule or other
		-- subfolders (same pattern InventoryCrafting uses), so the lookup
		-- must fall back to a recursive search — otherwise tools like
		-- Phone / FishingRod silently fail to restore on pickup.
		local toolTemplate = findTemplate(resType)
		if not toolTemplate then return end
		local backpack = player:FindFirstChild("Backpack")
		if not backpack then return end
		local toolClone = toolTemplate:Clone()
		toolClone.Parent = backpack

		droppedItem:Destroy()
		if _G.SendInventory then _G.SendInventory(player) end
	else
		-- Resource pickup: only allow when there is a truly empty slot.
		-- Partial stack space (e.g. 29/30) does NOT count — mining and
		-- crafting fill partials via AddResourceToInventory, but ground
		-- pickups require a free slot so that "drop one, pick one" cycling
		-- is impossible when the inventory is visually full.
		if not _G.GetInventory then
			print("[DropItem] PICKUP BLOCKED: _G.GetInventory not defined")
			return
		end

		-- Belt-and-suspenders: compute empty slots inline even if
		-- _G.GetEmptySlotCount isn't available (e.g. InventoryManager
		-- hasn't loaded yet). This duplicates the logic so pickup
		-- ALWAYS enforces slot-level fullness.
		local inv = _G.GetInventory(player)
		local MAX_STACK_LOCAL = 30
		local TOTAL_SLOTS_LOCAL = 28
		local DEFAULT_UNLOCKED_LOCAL = 13

		-- Count unlocked slots (same logic as InventoryManager)
		local unlockedSlots = DEFAULT_UNLOCKED_LOCAL
		local chars = player:FindFirstChild("Characteristics")
		if chars then
			local uSlots = chars:FindFirstChild("UnlockedInventorySlots")
			if uSlots and typeof(uSlots.Value) == "number" then
				unlockedSlots = math.clamp(uSlots.Value, DEFAULT_UNLOCKED_LOCAL, TOTAL_SLOTS_LOCAL)
			end
		end

		-- Count tool slots (unique tool names in backpack + character)
		local seenTools = {}
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			for _, t in backpack:GetChildren() do
				if t:IsA("Tool") then seenTools[t.Name] = true end
			end
		end
		if char then
			for _, t in char:GetChildren() do
				if t:IsA("Tool") then seenTools[t.Name] = true end
			end
		end
		local toolCount = 0
		for _ in pairs(seenTools) do toolCount = toolCount + 1 end

		-- Count total resource stacks
		local totalStacks = 0
		for _, count in pairs(inv) do
			if type(count) == "number" and count > 0 then
				totalStacks = totalStacks + math.ceil(count / MAX_STACK_LOCAL)
			end
		end

		local emptySlots = math.max(0, unlockedSlots - toolCount - totalStacks)
		print("[DropItem] PICKUP CHECK: unlocked=" .. unlockedSlots .. " tools=" .. toolCount .. " stacks=" .. totalStacks .. " empty=" .. emptySlots .. " item=" .. resType)

		if emptySlots <= 0 then
			pickupEvent:FireClient(player, "inventoryFull")
			return
		end

		-- There are empty slots — pick up what fits (clamped to real capacity
		-- so we never exceed the budget).
		local cap = _G.GetInventoryCapacity and _G.GetInventoryCapacity(player, resType) or 0
		if cap <= 0 then
			pickupEvent:FireClient(player, "inventoryFull")
			return
		end

		local toPickup = math.min(resAmount, cap)
		local leftover = resAmount - toPickup

		inv[resType] = (inv[resType] or 0) + toPickup
		if _G.SendInventory then _G.SendInventory(player) end

		if leftover > 0 then
			droppedItem:SetAttribute("ResourceAmount", leftover)
		else
			droppedItem:Destroy()
		end
	end
end)

-- Cleanup on player leave
game:GetService("Players").PlayerRemoving:Connect(function(player)
	lastDropTime[player] = nil
end)
