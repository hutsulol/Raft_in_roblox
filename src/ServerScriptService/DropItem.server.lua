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

	-- Captured from a tool drop so we can recreate placeholder-only
	-- tools (those without a ReplicatedStorage template, e.g. Phone) on
	-- pickup without losing their icon.
	local toolTextureId = nil

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
		if tool:IsA("Tool") then
			toolTextureId = tool.TextureId
		end
		tool:Destroy()
	end

	-- Find the template. For resources we prefer the mapped name and fall
	-- back to FALLBACK_TEMPLATE (e.g. Rope/Sand/Clay may not have their
	-- own 3D models yet). For tool drops we still use the fallback box
	-- model as the physical representation — the actual Tool instance is
	-- re-cloned from its own template only on pickup.
	local templateName = RESOURCE_TEMPLATES[itemName] or FALLBACK_TEMPLATE
	local template = findTemplate(templateName)
	if not template then
		template = findTemplate(FALLBACK_TEMPLATE)
	end
	if not template then return end

	-- Determine spawn position
	local spawnPos
	if dropPosition and (dropPosition - hrp.Position).Magnitude < MAX_DROP_DISTANCE then
		spawnPos = dropPosition + Vector3.new(0, 2, 0)
	else
		local lookDir = hrp.CFrame.LookVector
		spawnPos = hrp.Position + lookDir * 4 + Vector3.new(0, -1, 0)
	end

	local clone = template:Clone()

	-- Ensure the model has a PrimaryPart
	if clone:IsA("Model") and not clone.PrimaryPart then
		local first = clone:FindFirstChildWhichIsA("BasePart")
		if first then
			clone.PrimaryPart = first
		end
	end

	-- Set attributes so pickup knows what this is
	clone:SetAttribute("ResourceType", itemName)
	clone:SetAttribute("ResourceAmount", dropCount)
	clone:SetAttribute("IsToolDrop", not isResource)
	clone:SetAttribute("DropperUserId", player.UserId)
	if toolTextureId and toolTextureId ~= "" then
		clone:SetAttribute("ToolTextureId", toolTextureId)
	end

	clone:PivotTo(CFrame.new(spawnPos))
	clone.Parent = workspace

	-- Unanchor and set up physics (Massless so they don't affect raft speed)
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			part:SetNetworkOwner(nil)
		end
	end

	-- Inherit the raft's velocity so the item stays with the raft long enough
	-- to be detected by on-raft systems (e.g. the sawmill log polling). The
	-- raft cruises at 25 studs/s; without this, a freshly dropped log has
	-- zero horizontal velocity and the raft slides out from under it within
	-- a single detection cycle.
	local raft = workspace:FindFirstChild("Raft")
	local primaryClonePart = clone:IsA("BasePart") and clone or (clone:IsA("Model") and clone.PrimaryPart)
	if raft and raft.PrimaryPart and primaryClonePart then
		primaryClonePart.AssemblyLinearVelocity = raft.PrimaryPart.AssemblyLinearVelocity
	end

	-- Tag as DroppedItem for E-key instant pickup
	CollectionService:AddTag(clone, "DroppedItem")

	-- Auto-despawn after lifetime
	task.delay(DROPPED_LIFETIME, function()
		if clone and clone.Parent then
			clone:Destroy()
		end
	end)

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
		-- falls back to a recursive search — otherwise tools like
		-- FishingRod would silently fail to restore on pickup.
		--
		-- Some tools have no ReplicatedStorage template at all (e.g.
		-- Phone, whose UI lives entirely in PhoneMenu). For those we
		-- reconstruct a transparent-handled placeholder Tool, mirroring
		-- the fallback path in InventoryCrafting.server.lua. The icon is
		-- restored from the ToolTextureId attribute captured on drop.
		local backpack = player:FindFirstChild("Backpack")
		if not backpack then return end

		local toolTemplate = findTemplate(resType)
		local toolClone
		if toolTemplate then
			toolClone = toolTemplate:Clone()
		else
			toolClone = Instance.new("Tool")
			toolClone.Name = resType
			toolClone.CanBeDropped = false
			toolClone.RequiresHandle = false

			local handle = Instance.new("Part")
			handle.Name = "Handle"
			handle.Size = Vector3.new(1, 1, 1)
			handle.Transparency = 1
			handle.CanCollide = false
			handle.Massless = true
			handle.Parent = toolClone

			local savedTextureId = droppedItem:GetAttribute("ToolTextureId")
			if savedTextureId and savedTextureId ~= "" then
				toolClone.TextureId = savedTextureId
			end
		end
		toolClone.Parent = backpack
	else
		-- Resource pickup: add to inventory count
		local inv = _G.GetInventory and _G.GetInventory(player)
		if not inv then return end
		inv[resType] = (inv[resType] or 0) + resAmount
	end

	-- Destroy the dropped item
	droppedItem:Destroy()

	-- Sync inventory to client
	if _G.SendInventory then
		_G.SendInventory(player)
	end
end)

-- Cleanup on player leave
game:GetService("Players").PlayerRemoving:Connect(function(player)
	lastDropTime[player] = nil
end)
