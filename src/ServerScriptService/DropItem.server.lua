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
-- Cooked fish ("<fish>_Cooked") re-drop using the same fish model as
-- their raw counterpart, so dropping a cooked fish from the inventory
-- spawns the fish (not the fallback box).
setmetatable(RESOURCE_TEMPLATES, {
	__index = function(t, k)
		if type(k) == "string" and #k > 7 and k:sub(-7) == "_Cooked" then
			return rawget(t, k:sub(1, #k - 7))
		end
		return nil
	end,
})

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
-- Cooked fish behave as stackable resources just like their raw form.
setmetatable(RESOURCE_ITEMS, {
	__index = function(_, k)
		if type(k) == "string" and #k > 7 and k:sub(-7) == "_Cooked" then
			return true
		end
		return nil
	end,
})

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

	-- Fish ship with both a "raw" and a "cooked" Decal authored visible,
	-- which overlap. Show only the one matching this drop's state so the
	-- fish looks raw (or cooked, if it's already a "_Cooked" variant).
	local isCookedFish = itemName:sub(-7) == "_Cooked"
	for _, d in clone:GetDescendants() do
		if d:IsA("Decal") then
			if d.Name == "raw" then
				d.Transparency = isCookedFish and 1 or 0
			elseif d.Name == "cooked" then
				d.Transparency = isCookedFish and 0 or 1
			end
		end
	end
	if isCookedFish then
		clone:SetAttribute("Cooked", true)
	end

	-- Strip "Resource" tags and add "DroppedItem" BEFORE parenting to
	-- workspace. This closes the race window where a client could detect
	-- the clone with a stale "Resource" tag and fire CollectResource,
	-- bypassing the empty-slot pickup check.
	CollectionService:RemoveTag(clone, "Resource")
	for _, desc in clone:GetDescendants() do
		CollectionService:RemoveTag(desc, "Resource")
	end
	CollectionService:AddTag(clone, "DroppedItem")

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

-- Hide / reveal helpers for tools attached to a drop model. Tool
-- BaseParts still render in Workspace folders; if we left them visible
-- they'd clip through the box visual. Same pattern SmallContainerSystem
-- uses for chest storage.
local TOOL_DROP_HIDDEN_TAG = "DropHidden"

local function hideAttachedTool(tool)
	if tool:GetAttribute(TOOL_DROP_HIDDEN_TAG) then return end
	tool:SetAttribute(TOOL_DROP_HIDDEN_TAG, true)
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("__dt", d.Transparency)
			d:SetAttribute("__dc", d.CanCollide)
			d:SetAttribute("__dq", d.CanQuery)
			d:SetAttribute("__dh", d.CanTouch)
			d:SetAttribute("__da", d.Anchored)
			d.Transparency = 1
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = true
		end
	end
end

local function revealAttachedTool(tool)
	if not tool:GetAttribute(TOOL_DROP_HIDDEN_TAG) then return end
	tool:SetAttribute(TOOL_DROP_HIDDEN_TAG, nil)
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			local t = d:GetAttribute("__dt")
			local c = d:GetAttribute("__dc")
			local q = d:GetAttribute("__dq")
			local h = d:GetAttribute("__dh")
			local a = d:GetAttribute("__da")
			if t ~= nil then d.Transparency = t; d:SetAttribute("__dt", nil) end
			if c ~= nil then d.CanCollide = c; d:SetAttribute("__dc", nil) end
			if q ~= nil then d.CanQuery = q; d:SetAttribute("__dq", nil) end
			if h ~= nil then d.CanTouch = h; d:SetAttribute("__dh", nil) end
			if a ~= nil then d.Anchored = a; d:SetAttribute("__da", nil) end
		end
	end
end

-- Parent the Tool into the player's Backpack if there's a free slot.
-- Otherwise spawn a physical drop carrying THIS exact Tool instance so
-- pickup restores it intact — important for placeable stubs that have
-- no template in ReplicatedStorage. Returns true if the tool went into
-- Backpack, false if it dropped to the world.
_G.GiveToolOrDrop = function(player, tool, dropPosition)
	if not tool or not tool:IsA("Tool") then return false end
	local backpack = player:FindFirstChild("Backpack")
	local hasSlot = _G.HasFreeToolSlot and _G.HasFreeToolSlot(player)
	if backpack and hasSlot then
		tool.Parent = backpack
		return true
	end

	local drop = spawnPhysicalDrop(player, tool.Name, 1, true, dropPosition)
	if not drop then
		-- No drop template available — last resort, drop into Backpack
		-- anyway so the item isn't destroyed.
		if backpack then tool.Parent = backpack end
		return false
	end

	local attached = drop:FindFirstChild("AttachedTools")
	if not attached then
		attached = Instance.new("Folder")
		attached.Name = "AttachedTools"
		attached.Parent = drop
	end
	hideAttachedTool(tool)
	tool.Parent = attached
	drop:SetAttribute("HasAttachedTool", true)
	return false
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
		local inv = _G.GetInventory and _G.GetInventory(player)
		if not inv then return end
		if (inv[itemName] or 0) < dropCount then return end
		if _G.RemoveResourceFromInventory then
			_G.RemoveResourceFromInventory(player, itemName, dropCount)
		else
			inv[itemName] = inv[itemName] - dropCount
		end
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
		local backpack = player:FindFirstChild("Backpack")
		if not backpack then return end

		-- Prefer the Tool instance attached to the drop (used by
		-- _G.GiveToolOrDrop overflow). Only fall back to template-
		-- cloning for drops that carry no instance, e.g. when a tool
		-- was explicitly world-dropped via DropItem and no longer
		-- exists as an object.
		local attached = droppedItem:FindFirstChild("AttachedTools")
		local moved = false
		if attached then
			for _, t in attached:GetChildren() do
				if t:IsA("Tool") then
					revealAttachedTool(t)
					t.Parent = backpack
					moved = true
					break
				end
			end
		end

		if not moved then
			local toolTemplate = findTemplate(resType)
			if not toolTemplate then return end
			local toolClone = toolTemplate:Clone()
			toolClone.Parent = backpack
		end

		droppedItem:Destroy()
		if _G.SendInventory then _G.SendInventory(player) end
	else
		-- Seeds (Banana_Seed / Coconut_Seed / Pineapple_Seed) live in
		-- the leaf bag rather than the main inventory. Route them
		-- through _G.AddSeedToBag and reject the pickup outright if
		-- the player has no bag at all — the client surfaces a hint
		-- so the player knows they need to craft one first.
		local isSeed = type(resType) == "string" and resType:find("_Seed$") ~= nil
		if isSeed and typeof(_G.AddSeedToBag) == "function" then
			if typeof(_G.PlayerHasSeedBag) == "function" and not _G.PlayerHasSeedBag(player) then
				pickupEvent:FireClient(player, "needSeedBag")
				return
			end
			local cap = typeof(_G.GetSeedBagSpace) == "function" and _G.GetSeedBagSpace(player, resType) or 0
			if cap <= 0 then
				pickupEvent:FireClient(player, "seedBagFull")
				return
			end
			local toPickup = math.min(resAmount, cap)
			local leftover = resAmount - toPickup
			_G.AddSeedToBag(player, resType, toPickup)
			if leftover > 0 then
				droppedItem:SetAttribute("ResourceAmount", leftover)
			else
				droppedItem:Destroy()
			end
			return
		end

		-- Sand and Clay both route through the Sand Bag system. A bag
		-- can hold either type at a time; the bag system checks
		-- compatibility (empty bag accepts anything; partial bag only
		-- accepts more of its current type). Pickup refused with a
		-- toast if the player has no compatible bag — the drop stays
		-- on the ground until they craft / empty one.
		if (resType == "Sand" or resType == "Clay") and typeof(_G.AddToBag) == "function" then
			if typeof(_G.PlayerHasBag) == "function" and not _G.PlayerHasBag(player) then
				pickupEvent:FireClient(player, "needSandBag")
				return
			end
			local perUnit = typeof(_G.GetBagPercentPerUnit) == "function"
				and _G.GetBagPercentPerUnit() or 5
			local space   = typeof(_G.GetBagSpaceFor) == "function" and _G.GetBagSpaceFor(player, resType) or 0
			if space <= 0 then
				pickupEvent:FireClient(player, "sandBagFull")
				return
			end
			local maxUnits = math.floor(space / perUnit)
			if maxUnits <= 0 then
				pickupEvent:FireClient(player, "sandBagFull")
				return
			end
			local toPickup = math.min(resAmount, maxUnits)
			local leftover = resAmount - toPickup
			_G.AddToBag(player, resType, toPickup * perUnit, droppedItem.Parent and droppedItem.Position or nil)
			if leftover > 0 then
				droppedItem:SetAttribute("ResourceAmount", leftover)
			else
				droppedItem:Destroy()
			end
			return
		end

		if not _G.AddResourceToInventory or not _G.GetInventoryCapacity then
			print("[DropItem] PICKUP BLOCKED: InventoryManager globals missing")
			return
		end

		local cap = _G.GetInventoryCapacity(player, resType) or 0
		if cap <= 0 then
			pickupEvent:FireClient(player, "inventoryFull")
			return
		end

		local toPickup = math.min(resAmount, cap)
		local leftover = resAmount - toPickup

		_G.AddResourceToInventory(player, resType, toPickup)

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
