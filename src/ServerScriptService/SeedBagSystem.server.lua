-- SeedBagSystem.server.lua
-- The "leaf bag" Tool is now a real 6-slot seed container — not a
-- pass-through onto the main inventory. Seeds are routed here by
-- whichever system would otherwise call _G.AddResourceToInventory
-- for them (StoneAxeSystem tree drops, FruitBushSystem pineapple
-- harvests). If the player owns no bag the seeds spawn as a
-- physical drop on the ground instead of vanishing.
--
-- Slot state lives on the Tool instance as attributes
-- (Slot{i}_Name + Slot{i}_Count, i = 1..6). The Tool persists across
-- equip / unequip / Backpack moves, so the bag remembers its
-- contents for the session. Save/load support is not implemented
-- here — if the player rejoins they get an empty bag.
--
-- Interaction flow:
--   1. Player holds "leaf bag", stands next to a watered
--      Bed_Garden_For_Tree, presses E.
--   2. SeedBagUI.client.lua fires SeedBagAction("open", bed).
--   3. We validate + reply with SeedBagAction("show", bed, slots).
--   4. Player clicks a slot → SeedBagAction("plant", bed, slotIndex).
--   5. We decrement that slot, call _G.GrowTreeFromSeed, reply
--      SeedBagAction("close").

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local BAG_TOOL_NAME  = "leaf bag"
local SLOT_COUNT     = 6
local MAX_STACK      = 30
local INTERACT_RANGE = 15

-- Whitelist of seed names. Any resource the chop/harvest paths might
-- award gets sieved through here before AddSeedToBag accepts it.
local SEED_NAMES = {
	Banana_Seed    = true,
	Coconut_Seed   = true,
	Pineapple_Seed = true,
}

local seedBagEvent = ReplicatedStorage:FindFirstChild("SeedBagAction")
if not seedBagEvent then
	seedBagEvent = Instance.new("RemoteEvent")
	seedBagEvent.Name = "SeedBagAction"
	seedBagEvent.Parent = ReplicatedStorage
end

while not _G.GetInventory do
	task.wait(0.1)
end

-- ─── Bag helpers ───
local function initBagSlots(tool)
	for i = 1, SLOT_COUNT do
		if tool:GetAttribute("Slot" .. i .. "_Name") == nil then
			tool:SetAttribute("Slot" .. i .. "_Name", "")
			tool:SetAttribute("Slot" .. i .. "_Count", 0)
		end
	end
end

-- Walks every leaf bag the player owns (Backpack + held Tool). Each
-- container's children are scanned by Tool.Name so the player can
-- have multiple bags and we fill them in order.
local function iterPlayerBags(player)
	local list = {}
	local function gather(container)
		if not container then return end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child.Name == BAG_TOOL_NAME then
				initBagSlots(child)
				list[#list + 1] = child
			end
		end
	end
	gather(player.Character)
	gather(player:FindFirstChild("Backpack"))
	return list
end

local function getEquippedBag(player)
	local char = player.Character
	if not char then return nil end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if tool and tool.Name == BAG_TOOL_NAME then
		initBagSlots(tool)
		return tool
	end
	return nil
end

local function bagSnapshot(tool)
	local snap = {}
	for i = 1, SLOT_COUNT do
		local name = tool:GetAttribute("Slot" .. i .. "_Name") or ""
		local count = tool:GetAttribute("Slot" .. i .. "_Count") or 0
		snap[i] = { name = name, count = count }
	end
	return snap
end

-- Try to fit `amount` of seedName into this bag. Returns the number
-- of seeds NOT placed (leftover for the next bag or the floor).
local function pushSeedIntoBag(tool, seedName, amount)
	-- First pass: top up existing partial stacks of the same seed.
	for i = 1, SLOT_COUNT do
		if amount <= 0 then break end
		local name = tool:GetAttribute("Slot" .. i .. "_Name")
		local count = tool:GetAttribute("Slot" .. i .. "_Count") or 0
		if name == seedName and count < MAX_STACK then
			local fit = math.min(MAX_STACK - count, amount)
			tool:SetAttribute("Slot" .. i .. "_Count", count + fit)
			amount = amount - fit
		end
	end
	-- Second pass: fresh slots.
	for i = 1, SLOT_COUNT do
		if amount <= 0 then break end
		local name = tool:GetAttribute("Slot" .. i .. "_Name")
		if name == "" or name == nil then
			local fit = math.min(MAX_STACK, amount)
			tool:SetAttribute("Slot" .. i .. "_Name", seedName)
			tool:SetAttribute("Slot" .. i .. "_Count", fit)
			amount = amount - fit
		end
	end
	return amount
end

-- Public helper: route a seed pickup into the player's bag(s).
-- Anything that doesn't fit overflows to the floor as a physical
-- drop via _G.SpawnResourceDrop, so seeds are never silently lost.
_G.AddSeedToBag = function(player, seedName, amount, dropPosition)
	if not SEED_NAMES[seedName] then return 0 end
	amount = tonumber(amount) or 0
	if amount <= 0 then return 0 end

	local bags = iterPlayerBags(player)
	local remaining = amount
	for _, bag in ipairs(bags) do
		if remaining <= 0 then break end
		remaining = pushSeedIntoBag(bag, seedName, remaining)
	end

	local added = amount - remaining
	if added > 0 then
		-- Notify-card so the player sees the pickup. Mirrors the
		-- InventoryNotify path used by _G.AddResourceToInventory.
		local notifyEvent = ReplicatedStorage:FindFirstChild("InventoryNotify")
		if notifyEvent then
			notifyEvent:FireClient(player, seedName, added)
		end
	end

	if remaining > 0 and _G.SpawnResourceDrop then
		-- Couldn't fit (no bag, or all bags full). Drop on the ground
		-- so the player can craft a bag and pick them up later.
		_G.SpawnResourceDrop(player, seedName, remaining, dropPosition)
	end

	return added
end

-- ─── Action handler ───
local function isValidBed(target, hrp)
	if not target or not target:IsA("Model") then return false end
	if not target:GetAttribute("IsBedGardenForTree") then return false end
	if not target:GetAttribute("IsWatered") then return false end
	if target:GetAttribute("GrowthStage") then return false end
	if (hrp.Position - target:GetPivot().Position).Magnitude > INTERACT_RANGE then return false end
	return true
end

seedBagEvent.OnServerEvent:Connect(function(player, action, target, slotIndex)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local bag = getEquippedBag(player)
	if not bag then return end

	if action == "open" then
		if not isValidBed(target, hrp) then return end
		seedBagEvent:FireClient(player, "show", target, bagSnapshot(bag))

	elseif action == "plant" then
		if not isValidBed(target, hrp) then return end
		slotIndex = tonumber(slotIndex)
		if not slotIndex or slotIndex < 1 or slotIndex > SLOT_COUNT then return end

		local seedName = bag:GetAttribute("Slot" .. slotIndex .. "_Name")
		local count    = bag:GetAttribute("Slot" .. slotIndex .. "_Count") or 0
		if not seedName or seedName == "" or count <= 0 then return end
		if not SEED_NAMES[seedName] then return end

		-- Consume one from this slot. Clear name when the stack
		-- empties so the slot reads as empty in the snapshot.
		count = count - 1
		bag:SetAttribute("Slot" .. slotIndex .. "_Count", count)
		if count <= 0 then
			bag:SetAttribute("Slot" .. slotIndex .. "_Name", "")
		end

		target:SetAttribute("PlantedSeed", seedName)
		target:SetAttribute("GrowthStage", 0)
		target:SetAttribute("WateredTime", nil)

		if typeof(_G.GrowTreeFromSeed) == "function" then
			_G.GrowTreeFromSeed(target)
		end

		seedBagEvent:FireClient(player, "close")
	end
end)
