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
--      Bed_T, presses E.
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

-- Soft match — lowercase + strip spaces / underscores so an
-- accidental rename ("Leaf Bag", "leafbag", "leaf_bag") still
-- registers as the bag tool.
local function isBagTool(tool)
	if not tool or not tool:IsA("Tool") then return false end
	local name = tool.Name:lower():gsub("[_%s]", "")
	return name == BAG_TOOL_NAME:lower():gsub("[_%s]", "")
end

-- Walks every leaf bag the player owns (Backpack + held Tool). Soft-
-- matches Tool.Name via isBagTool so the player can have multiple
-- bags or a rename of the template still resolves.
local function iterPlayerBags(player)
	local list = {}
	local function gather(container)
		if not container then return end
		for _, child in container:GetChildren() do
			if isBagTool(child) then
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
	if tool and isBagTool(tool) then
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

-- Public helper: how many of `seedName` can be fit into the player's
-- bags right now? Used by DropItem's seed-pickup path so picking up
-- a ground seed fails cleanly when the player owns no bag (or every
-- bag is full) instead of silently re-dropping it.
_G.GetSeedBagSpace = function(player, seedName)
	if not SEED_NAMES[seedName] then return 0 end
	local total = 0
	for _, bag in ipairs(iterPlayerBags(player)) do
		for i = 1, SLOT_COUNT do
			local name = bag:GetAttribute("Slot" .. i .. "_Name")
			local count = bag:GetAttribute("Slot" .. i .. "_Count") or 0
			if name == seedName then
				total = total + (MAX_STACK - count)
			elseif (name == "" or name == nil) then
				total = total + MAX_STACK
			end
		end
	end
	return total
end

_G.PlayerHasSeedBag = function(player)
	return #iterPlayerBags(player) > 0
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
	if not hrp then
		print(("[SeedBag] %s: no HRP, abort action %q"):format(player.Name, tostring(action)))
		return
	end

	local bag = getEquippedBag(player)
	if not bag then
		print(("[SeedBag] %s: no equipped leaf bag (action=%q)"):format(player.Name, tostring(action)))
		return
	end

	if action == "open" then
		-- Open without a bed (player just wants to peek inside) is
		-- fine — we pass nil down to the client which disables the
		-- per-slot plant click. Target only gets carried if the
		-- player is actually near a valid watered bed.
		local bed = isValidBed(target, hrp) and target or nil
		print(("[SeedBag] open ok — bed=%s, snapshot built for %s"):format(tostring(bed), player.Name))
		seedBagEvent:FireClient(player, "show", bed, bagSnapshot(bag))

	elseif action == "plant" then
		-- Take one seed out of the chosen slot and put the matching
		-- Tool directly into the player's hand. The player aims at
		-- whatever they want themselves (tree bed → press E to plant
		-- a sapling, regular Garden → ghost-place a bush). If the
		-- Tool is unequipped without being used (Backpack drop / drop
		-- to world) we refund the seed back to the bag.
		slotIndex = tonumber(slotIndex)
		if not slotIndex or slotIndex < 1 or slotIndex > SLOT_COUNT then return end

		local seedName = bag:GetAttribute("Slot" .. slotIndex .. "_Name")
		local count    = bag:GetAttribute("Slot" .. slotIndex .. "_Count") or 0
		if not seedName or seedName == "" or count <= 0 then return end
		if not SEED_NAMES[seedName] then return end

		-- Resolve the Tool template before touching the bag — if the
		-- template is missing we don't want to silently eat the seed.
		local template = ReplicatedStorage:FindFirstChild(seedName)
			or ReplicatedStorage:FindFirstChild(seedName, true)
		if not template or not template:IsA("Tool") then
			warn("[SeedBag] seed Tool template missing: " .. seedName)
			return
		end

		-- Consume one from this slot.
		count = count - 1
		bag:SetAttribute("Slot" .. slotIndex .. "_Count", count)
		if count <= 0 then
			bag:SetAttribute("Slot" .. slotIndex .. "_Name", "")
		end

		-- Spawn the Tool and force-equip it. Parenting to Character
		-- auto-equips on most setups, but the explicit Unequip+Equip
		-- handles the case where another tool is already in hand.
		local tool = template:Clone()
		tool:SetAttribute("FromSeedBag", true)
		tool:SetAttribute("SeedName", seedName)
		tool.Parent = char
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			pcall(function() humanoid:UnequipTools() end)
			pcall(function() humanoid:EquipTool(tool) end)
		end

		-- Refund guard: only arm AFTER the first Equipped fires, so the
		-- initial Backpack→Character shuffle EquipTool just performed
		-- isn't mistaken for the player putting the tool back.
		tool.Equipped:Once(function()
			tool:SetAttribute("Ready", true)
		end)
		tool.AncestryChanged:Connect(function(_, newParent)
			if not tool:GetAttribute("Ready") then return end
			if tool:GetAttribute("Consumed") then return end
			if newParent == nil or (newParent and newParent:IsA("Backpack")) then
				task.defer(function()
					if _G.AddSeedToBag then
						_G.AddSeedToBag(player, seedName, 1)
					end
					if tool.Parent then tool:Destroy() end
				end)
			end
		end)

		print(string.format(
			"[SeedBag] equip-to-hand: seed=%s slot=%d (player=%s)",
			seedName, slotIndex, player.Name
		))

		seedBagEvent:FireClient(player, "close")
	end
end)
