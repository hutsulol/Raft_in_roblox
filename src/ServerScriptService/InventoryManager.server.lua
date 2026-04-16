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

-- ─── Helper: how many unique tool names does the player hold? ───
local function countToolSlots(player)
	local seen = {}
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, tool in backpack:GetChildren() do
			if tool:IsA("Tool") then seen[tool.Name] = true end
		end
	end
	local char = player.Character
	if char then
		for _, tool in char:GetChildren() do
			if tool:IsA("Tool") then seen[tool.Name] = true end
		end
	end
	local n = 0
	for _ in pairs(seen) do n = n + 1 end
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

_G.GetInventoryCapacity = function(player, itemName)
	local inv = _G.GetInventory(player)
	local unlocked = getUnlockedSlots(player)
	local tools = countToolSlots(player)

	local existing = (itemName and inv[itemName]) or 0
	local existingStacks = existing > 0 and math.ceil(existing / MAX_STACK) or 0
	local partialSpace = existingStacks > 0
		and (existingStacks * MAX_STACK - existing) or 0

	local otherStacks = 0
	for _, name in RESOURCE_NAMES do
		if name ~= itemName then
			local count = inv[name]
			if type(count) == "number" and count > 0 then
				otherStacks = otherStacks + math.ceil(count / MAX_STACK)
			end
		end
	end

	local usedSlots = tools + existingStacks + otherStacks
	-- Already over budget (historical overflow) → no room at all
	if usedSlots > unlocked then return 0 end

	local emptySlots = unlocked - usedSlots
	return emptySlots * MAX_STACK + partialSpace
end

-- How many completely empty inventory slots does this player have?
-- Used by the pickup handler to enforce slot-level fullness: if every
-- slot is occupied (even with partial stacks), ground pickups are blocked.
_G.GetEmptySlotCount = function(player)
	local inv = _G.GetInventory(player)
	local unlocked = getUnlockedSlots(player)
	local tools = countToolSlots(player)
	local totalStacks = getTotalResourceStacks(inv)
	return math.max(0, unlocked - tools - totalStacks)
end

_G.SendInventory = function(player)
	local inv = _G.GetInventory(player)
	local maxSlots = getMaxResourceSlots(player)
	local dropPos = getDropPosition(player)

	-- ── ENFORCE: trim until total resource stacks fit the budget ──
	local totalStacks = getTotalResourceStacks(inv)
	if totalStacks > maxSlots then
		print("[InventoryManager] TRIM: totalStacks=" .. totalStacks .. " > maxSlots=" .. maxSlots .. " for " .. player.Name)
	end
	while totalStacks > maxSlots do
		-- Pick the resource whose last (partial) stack is smallest
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

		-- Remove from inventory
		inv[trimName] = inv[trimName] - trimAmount
		if inv[trimName] <= 0 then inv[trimName] = 0 end
		totalStacks = totalStacks - 1
		print("[InventoryManager] TRIMMED: " .. trimName .. " x" .. trimAmount .. " dropped for " .. player.Name)

		-- Spawn physical drop in front of the player
		if trimAmount > 0 and _G.SpawnResourceDrop then
			_G.SpawnResourceDrop(player, trimName, trimAmount, dropPos)
		end
	end

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
	end

	-- Drop overflow as physical item
	if overflow > 0 and _G.SpawnResourceDrop then
		_G.SpawnResourceDrop(player, itemName, overflow, dropPosition)
	end

	_G.SendInventory(player)
	return toAdd, overflow
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
