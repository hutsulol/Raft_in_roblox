-- InventoryManager.server.lua
-- Centralized inventory: stores data, enforces capacity, persists via DataStore.
-- Defines _G.GetInventory, _G.SendInventory, _G.AddResourceToInventory,
-- _G.GetInventoryCapacity. All other scripts use these globals.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── Constants ───
local MAX_STACK = 30
local TOTAL_SLOTS = 28
local DEFAULT_HOTBAR_SLOTS = 8
local DEFAULT_BASE_GRID_SLOTS = 5
local DEFAULT_UNLOCKED = DEFAULT_HOTBAR_SLOTS + DEFAULT_BASE_GRID_SLOTS -- 13
local AUTO_SAVE_INTERVAL = 120 -- seconds

-- All known resource names (keys the inventory can hold)
local RESOURCE_NAMES = {
	"Log", "Plastic", "Stone", "Plank", "Leaves", "Rope",
	"Sand", "Clay", "Wet_Brick", "Dry_Brick",
	"Iron_Ore", "Iron_Ingot",
	"Blue_Fish", "Carp_Fish", "Fish_Bones", "Foil_Fish",
	"Jelly_Fish", "Legendary_Fish", "Seabass_Fish", "Tilapia_Fish",
}

local RESOURCE_SET = {}
for _, name in RESOURCE_NAMES do
	RESOURCE_SET[name] = true
end

-- ─── DataStore ───
local inventoryStore = nil
pcall(function()
	inventoryStore = DataStoreService:GetDataStore("PlayerInventory_v1")
end)

-- ─── RemoteEvent ───
local inventoryEvent = ReplicatedStorage:FindFirstChild("InventoryUpdate")
if not inventoryEvent then
	inventoryEvent = Instance.new("RemoteEvent")
	inventoryEvent.Name = "InventoryUpdate"
	inventoryEvent.Parent = ReplicatedStorage
end

-- ─── Per-player inventory storage ───
local inventories = {}

-- ─── Helper: build a fresh empty inventory table ───
local function createEmptyInventory()
	local inv = {}
	for _, name in RESOURCE_NAMES do
		inv[name] = 0
	end
	return inv
end

-- ─── Helper: count each Tool instance the player holds ───
-- Client inventory now assigns one slot per Tool Instance (no more
-- name-based stacking), so the server's slot bookkeeping has to match:
-- three Machetes occupy three slots, not one.
local function countToolSlots(player)
	local n = 0
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, tool in backpack:GetChildren() do
			if tool:IsA("Tool") then n = n + 1 end
		end
	end
	local char = player.Character
	if char then
		for _, tool in char:GetChildren() do
			if tool:IsA("Tool") then n = n + 1 end
		end
	end
	return n
end

-- ─── Helper: unlocked slot count (mirrors client clamping) ───
local function getUnlockedSlots(player)
	local chars = player:FindFirstChild("Characteristics")
	if chars then
		local unlocked = chars:FindFirstChild("UnlockedInventorySlots")
		if unlocked and typeof(unlocked.Value) == "number" then
			return math.clamp(unlocked.Value, DEFAULT_UNLOCKED, TOTAL_SLOTS)
		end
	end
	return DEFAULT_UNLOCKED
end

-- ─── Helper: total resource stacks in an inventory table ───
-- Only counts KNOWN resource names. Unknown keys (from legacy save data
-- or bugs elsewhere) are ignored so they don't occupy invisible slots
-- the client can't render.
local function getTotalResourceStacks(inv)
	local total = 0
	for _, name in RESOURCE_NAMES do
		local count = inv[name]
		if type(count) == "number" and count > 0 then
			total = total + math.ceil(count / MAX_STACK)
		end
	end
	return total
end

-- ─── Helper: max resource slots available (unlocked minus tools) ───
local function getMaxResourceSlots(player)
	return math.max(0, getUnlockedSlots(player) - countToolSlots(player))
end

-- ─── Helper: drop position in front of the player ───
-- Used by the trim guard and overflow drops. Returns a point ~5 studs
-- ahead of the character so items land on the ground in front of the
-- player instead of spawning inside the character's head.
local function getDropPosition(player)
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	return hrp.Position + hrp.CFrame.LookVector * 5
end

-- ═══════════════════════════════════════════════════════════════════════
-- DataStore: load / save
-- ═══════════════════════════════════════════════════════════════════════

local function loadInventory(player)
	local inv = createEmptyInventory()

	if inventoryStore then
		local ok, data = pcall(function()
			return inventoryStore:GetAsync("Player_" .. player.UserId)
		end)
		if ok and type(data) == "table" then
			for name, count in pairs(data) do
				if RESOURCE_SET[name] and type(count) == "number" then
					inv[name] = math.max(0, math.floor(count))
				end
			end
		end
	end

	inventories[player] = inv
	return inv
end

local function saveInventory(player)
	local inv = inventories[player]
	if not inv or not inventoryStore then return end

	local saveData = {}
	for name, count in pairs(inv) do
		if type(count) == "number" and count > 0 then
			saveData[name] = count
		end
	end

	pcall(function()
		inventoryStore:SetAsync("Player_" .. player.UserId, saveData)
	end)
end

-- ═══════════════════════════════════════════════════════════════════════
-- _G API — used by every other server script
-- ═══════════════════════════════════════════════════════════════════════

_G.GetInventory = function(player)
	if not inventories[player] then
		loadInventory(player)
	end
	-- Ensure every known resource key exists
	local inv = inventories[player]
	for _, name in RESOURCE_NAMES do
		if inv[name] == nil then inv[name] = 0 end
	end
	-- Strip any unknown keys (e.g. from legacy save data or bugs elsewhere).
	-- Without this, they would count as invisible slots because the client
	-- can't render them but the server counts them in getTotalResourceStacks.
	for key in pairs(inv) do
		if not RESOURCE_SET[key] then
			print("[InventoryManager] Stripping unknown inventory key: " .. tostring(key))
			inv[key] = nil
		end
	end
	return inv
end

-- ─── Layout-based capacity ───
-- The client's cached layout is the source of truth for slot positions.
-- The server NEVER modifies it — only reads it.  Between client syncs,
-- we track how many items were added/removed per resource so the
-- capacity check stays accurate without touching the layout itself.

local pendingDeltas = {}  -- [player] = { [resName] = number }

local function getPendingDelta(player, resName)
	local pd = pendingDeltas[player]
	if not pd then return 0 end
	return pd[resName] or 0
end

local function addPendingDelta(player, resName, amount)
	if not pendingDeltas[player] then
		pendingDeltas[player] = {}
	end
	pendingDeltas[player][resName] = (pendingDeltas[player][resName] or 0) + amount
end

local function clearPendingDeltas(player)
	pendingDeltas[player] = nil
end

_G.ClearPendingDeltas = clearPendingDeltas

-- Called when the client syncs a fresh layout.  Instead of blindly
-- clearing deltas we compare the layout totals against the server's
-- actual inventory.  If the layout is short (client couldn't fit items
-- into slotData), we keep a positive delta for the difference so
-- capacity checks still block further pickups.
_G.ReconcilePendingDeltas = function(player)
	local inv = inventories[player]
	if not inv then
		clearPendingDeltas(player)
		return
	end

	local layout = _G.GetClientSlotLayout and _G.GetClientSlotLayout(player)
	if not layout then
		clearPendingDeltas(player)
		return
	end

	local unlocked = getUnlockedSlots(player)
	local newDeltas = nil

	for _, resName in RESOURCE_NAMES do
		local serverCount = inv[resName] or 0
		local layoutCount = 0
		for idx = 1, unlocked do
			local slot = layout[tostring(idx)]
			if slot and slot.type == "resource" and slot.name == resName
				and typeof(slot.count) == "number" then
				layoutCount = layoutCount + slot.count
			end
		end
		local diff = serverCount - layoutCount
		if diff > 0 then
			if not newDeltas then newDeltas = {} end
			newDeltas[resName] = diff
		end
	end

	pendingDeltas[player] = newDeltas
end

local function getLayout(player)
	return _G.GetClientSlotLayout and _G.GetClientSlotLayout(player)
end

local function computeLayoutCapacity(player, itemName)
	local layout = getLayout(player)
	if not layout then
		return { emptySlots = 0, partialSpace = 0, capacity = 0 }
	end

	local unlocked = getUnlockedSlots(player)

	-- Build per-resource totals from the layout, then apply pending
	-- deltas to get the effective counts.  This lets us figure out
	-- which slots are now empty (count dropped to 0 after removals)
	-- and which gained items (count increased after additions).
	local slotInfo = {}          -- [idx] = { name, count } (resource only)
	local partialSpaceSameType = 0
	local occupied = 0

	for idxStr, slot in pairs(layout) do
		local idx = tonumber(idxStr)
		if idx and idx >= 1 and idx <= unlocked then
			occupied = occupied + 1
			if slot.type == "resource" and typeof(slot.count) == "number" then
				slotInfo[idx] = { name = slot.name, count = slot.count }
			end
		end
	end

	-- Apply pending deltas to slot counts so we get accurate occupancy.
	local pd = pendingDeltas[player]
	if pd then
		for resName, delta in pairs(pd) do
			if delta > 0 then
				-- Items added: fill partial same-type slots, then empty slots
				local rem = delta
				for idx = 1, unlocked do
					if rem <= 0 then break end
					local si = slotInfo[idx]
					if si and si.name == resName then
						local space = MAX_STACK - si.count
						if space > 0 then
							local fit = math.min(rem, space)
							si.count = si.count + fit
							rem = rem - fit
						end
					end
				end
				-- Remaining goes into new (empty) slots
				for idx = 1, unlocked do
					if rem <= 0 then break end
					if not slotInfo[idx] and not layout[tostring(idx)] then
						local fit = math.min(rem, MAX_STACK)
						slotInfo[idx] = { name = resName, count = fit }
						occupied = occupied + 1
						rem = rem - fit
					end
				end
			elseif delta < 0 then
				-- Items removed: drain from last slots first
				local rem = -delta
				for idx = unlocked, 1, -1 do
					if rem <= 0 then break end
					local si = slotInfo[idx]
					if si and si.name == resName then
						if rem >= si.count then
							rem = rem - si.count
							slotInfo[idx] = nil
							occupied = occupied - 1
						else
							si.count = si.count - rem
							rem = 0
						end
					end
				end
			end
		end
	end

	-- Now compute final capacity from the adjusted slot picture
	local emptySlots = math.max(0, unlocked - occupied)
	if itemName then
		for _, si in pairs(slotInfo) do
			if si.name == itemName then
				local space = MAX_STACK - si.count
				if space > 0 then
					partialSpaceSameType = partialSpaceSameType + space
				end
			end
		end
	end

	return {
		emptySlots = emptySlots,
		partialSpace = partialSpaceSameType,
		capacity = emptySlots * MAX_STACK + partialSpaceSameType,
	}
end

_G.GetInventoryCapacity = function(player, itemName)
	return computeLayoutCapacity(player, itemName).capacity
end

_G.GetEmptySlotCount = function(player)
	return computeLayoutCapacity(player, nil).emptySlots
end

-- True when the player can accept one more Tool instance. The client's
-- layout is the source of truth for resource occupancy; tools are
-- counted straight from Backpack / Character. If unlocked slots minus
-- resource stacks minus tool instances >= 1, there's room.
_G.HasFreeToolSlot = function(player)
	local unlocked = getUnlockedSlots(player)
	local tools = countToolSlots(player)
	local inv = _G.GetInventory(player)
	local stacks = getTotalResourceStacks(inv)
	return (unlocked - tools - stacks) > 0
end

_G.SendInventory = function(player)
	local inv = _G.GetInventory(player)
	local maxSlots = getMaxResourceSlots(player)
	local dropPos = getDropPosition(player)

	local totalStacks = getTotalResourceStacks(inv)
	if totalStacks > maxSlots then
		print("[InventoryManager] TRIM: totalStacks=" .. totalStacks .. " > maxSlots=" .. maxSlots .. " for " .. player.Name)
	end
	while totalStacks > maxSlots do
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
		print("[InventoryManager] TRIMMED: " .. trimName .. " x" .. trimAmount .. " dropped for " .. player.Name)

		if trimAmount > 0 and _G.SpawnResourceDrop then
			_G.SpawnResourceDrop(player, trimName, trimAmount, dropPos)
		end
	end

	-- Pending deltas are NOT cleared here — they stay until the client
	-- syncs its fresh layout back (SlotLayoutSync), at which point
	-- RaftSaveSystem calls _G.ClearPendingDeltas.  This ensures that
	-- between SendInventory and the client round-trip, capacity checks
	-- still account for the items we just added/removed.
	inventoryEvent:FireClient(player, inv)
end

_G.AddResourceToInventory = function(player, itemName, amount, dropPosition)
	if type(itemName) ~= "string" or itemName == "" then return 0, 0 end
	amount = tonumber(amount) or 0
	if amount <= 0 then return 0, 0 end

	local inv = _G.GetInventory(player)
	local cap = _G.GetInventoryCapacity(player, itemName)
	local toAdd = math.min(amount, math.max(0, cap))
	local overflow = amount - toAdd

	if overflow > 0 then
		print("[InventoryManager] OVERFLOW: " .. itemName .. " add=" .. toAdd .. " overflow=" .. overflow .. " cap=" .. cap .. " for " .. player.Name)
	end

	if toAdd > 0 then
		inv[itemName] = (inv[itemName] or 0) + toAdd
		addPendingDelta(player, itemName, toAdd)
	end

	if overflow > 0 and _G.SpawnResourceDrop then
		_G.SpawnResourceDrop(player, itemName, overflow, dropPosition)
	end

	_G.SendInventory(player)
	return toAdd, overflow
end

_G.RemoveResourceFromInventory = function(player, itemName, amount)
	if type(itemName) ~= "string" or itemName == "" then return end
	amount = tonumber(amount) or 0
	if amount <= 0 then return end

	local inv = _G.GetInventory(player)
	local current = inv[itemName] or 0
	local toRemove = math.min(amount, current)
	if toRemove <= 0 then return end

	inv[itemName] = current - toRemove
	addPendingDelta(player, itemName, -toRemove)
end

-- ═══════════════════════════════════════════════════════════════════════
-- Player lifecycle
-- ═══════════════════════════════════════════════════════════════════════

Players.PlayerAdded:Connect(function(player)
	loadInventory(player)
	task.spawn(function()
		task.wait(2)
		if player.Parent then
			_G.SendInventory(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	saveInventory(player)
	inventories[player] = nil
	pendingDeltas[player] = nil
end)

-- Save all on server shutdown
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		saveInventory(player)
	end
end)

-- Auto-save every 2 minutes
task.spawn(function()
	while true do
		task.wait(AUTO_SAVE_INTERVAL)
		for _, player in Players:GetPlayers() do
			task.spawn(saveInventory, player)
		end
	end
end)

-- Handle players already in game (if script loads late)
for _, player in Players:GetPlayers() do
	if not inventories[player] then
		loadInventory(player)
	end
end

print("[InventoryManager] Loaded — _G API defined (GetInventory, SendInventory, AddResourceToInventory, GetInventoryCapacity, GetEmptySlotCount)")
