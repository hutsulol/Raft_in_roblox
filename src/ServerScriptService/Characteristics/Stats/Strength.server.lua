-- Strength.server.lua
-- Stat-specific logic for the Strength attribute.
--
-- Mechanic #1 — Inventory expansion:
--   Players always have the 8 hotbar slots + 5 inventory grid slots
--   (the first row) unlocked. Each 2 points of Strength unlocks one
--   additional grid slot, up to the full 4×5 grid (20 grid slots /
--   28 total).
--
-- The canonical value lives as an IntValue named `UnlockedInventorySlots`
-- inside the per-player `Characteristics` folder created by
-- Characteristics.server.lua. InventoryUI.client.lua subscribes to it and
-- greys out / blocks any slot whose index exceeds the value.

local Players = game:GetService("Players")

local HOTBAR_SLOTS     = 8
local BASE_GRID_SLOTS  = 5   -- always-unlocked first row
local MAX_GRID_SLOTS   = 20  -- 4 rows × 5 cols
local MAX_TOTAL_SLOTS  = HOTBAR_SLOTS + MAX_GRID_SLOTS
local SLOTS_PER_LEVELS = 2   -- 1 extra grid slot per 2 Strength

local function computeUnlockedSlots(strengthValue)
	local bonus = math.floor(strengthValue / SLOTS_PER_LEVELS)
	local grid  = math.min(BASE_GRID_SLOTS + bonus, MAX_GRID_SLOTS)
	return HOTBAR_SLOTS + grid
end

local function bindPlayer(player)
	-- Characteristics.server.lua creates the folder/IntValues on
	-- PlayerAdded but we may run before it, so wait on them.
	local folder = player:WaitForChild("Characteristics")
	local strength = folder:WaitForChild("Strength")

	local unlocked = folder:FindFirstChild("UnlockedInventorySlots")
	if not unlocked then
		unlocked = Instance.new("IntValue")
		unlocked.Name = "UnlockedInventorySlots"
		unlocked.Parent = folder
	end

	local function refresh()
		unlocked.Value = computeUnlockedSlots(strength.Value)
	end

	refresh()
	strength:GetPropertyChangedSignal("Value"):Connect(refresh)
end

for _, p in Players:GetPlayers() do
	task.spawn(bindPlayer, p)
end
Players.PlayerAdded:Connect(function(p)
	task.spawn(bindPlayer, p)
end)
