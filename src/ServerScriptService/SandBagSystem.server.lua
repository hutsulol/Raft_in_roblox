-- SandBagSystem.server.lua
-- The "Sand Bag" Tool is a unified bag-storage for granular dig
-- resources (Sand or Clay). Per-bag state:
--
--   * BagContent  — "Sand" / "Clay" / nil. An empty bag accepts
--                   either. Once it has fill, it locks to that type
--                   until it's drained back to 0, at which point
--                   BagContent is cleared and the bag can be used for
--                   the other resource.
--   * SandFill    — 0..100 percent. (Legacy name; kept so existing
--                   bags in players' Backpacks don't reset.)
--
-- One dug pile (a Diggable mesh finishing its 5-hit chain) yields
-- PILE_PERCENT = 15 %. One ground-pickup unit = 5 %. Crafts that used
-- to consume Sand/Clay from inventory now drain from bags instead via
-- _G.RemoveBagUnits.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BAG_TOOL_NAME    = "Sand Bag"
local FILL_ATTR        = "SandFill"     -- 0..100 % (legacy name)
local CONTENT_ATTR     = "BagContent"   -- "Sand" / "Clay" / nil
local MAX_FILL         = 100
local PILE_PERCENT     = 15
local PERCENT_PER_UNIT = 5

-- Resources the bag will accept. Any new bag-routed dig type just needs
-- adding to this set; the helpers below are otherwise generic.
local SUPPORTED = { Sand = true, Clay = true }

local sandBagEvent = ReplicatedStorage:FindFirstChild("SandBagAction")
if not sandBagEvent then
	sandBagEvent = Instance.new("RemoteEvent")
	sandBagEvent.Name = "SandBagAction"
	sandBagEvent.Parent = ReplicatedStorage
end

while not _G.GetInventory do
	task.wait(0.1)
end

local function isBagTool(tool)
	if not tool or not tool:IsA("Tool") then return false end
	local a = tool.Name:lower():gsub("[_%s]", "")
	local b = BAG_TOOL_NAME:lower():gsub("[_%s]", "")
	return a == b
end

local function initBag(tool)
	if tool:GetAttribute(FILL_ATTR) == nil then
		tool:SetAttribute(FILL_ATTR, 0)
	end
	-- BagContent stays unset on empty bags — nil = accepts anything.
end

local function getBagContent(tool)
	return tool:GetAttribute(CONTENT_ATTR)
end

-- Returns true if the bag has room AND its locked-in type matches (or
-- it's empty and therefore accepts anything). Also self-heals an
-- inconsistent state where fill is 0 but a stale content type lingered.
local function isCompatibleBag(tool, resourceName)
	local fill = tool:GetAttribute(FILL_ATTR) or 0
	if fill <= 0 then
		if getBagContent(tool) ~= nil then
			tool:SetAttribute(CONTENT_ATTR, nil)
		end
		return true
	end
	return getBagContent(tool) == resourceName
end

local function iterPlayerBags(player)
	local list = {}
	local function gather(container)
		if not container then return end
		for _, child in container:GetChildren() do
			if isBagTool(child) then
				initBag(child)
				list[#list + 1] = child
			end
		end
	end
	gather(player.Character)
	gather(player:FindFirstChild("Backpack"))
	return list
end

local function iterCompatibleBags(player, resourceName)
	local list = {}
	for _, bag in iterPlayerBags(player) do
		if isCompatibleBag(bag, resourceName) then
			list[#list + 1] = bag
		end
	end
	return list
end

local function getEquippedBag(player)
	local char = player.Character
	if not char then return nil end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if tool and isBagTool(tool) then
		initBag(tool)
		return tool
	end
	return nil
end

-- Public helpers ------------------------------------------------------

_G.PlayerHasBag = function(player)
	return #iterPlayerBags(player) > 0
end

-- Total free space (in percent) across every bag that can accept
-- `resourceName`. Empty bags count their full MAX_FILL.
_G.GetBagSpaceFor = function(player, resourceName)
	if not SUPPORTED[resourceName] then return 0 end
	local space = 0
	for _, bag in iterCompatibleBags(player, resourceName) do
		local fill = bag:GetAttribute(FILL_ATTR) or 0
		space = space + math.max(0, MAX_FILL - fill)
	end
	return space
end

-- How many resource units (5 % each) are currently stashed across the
-- player's bags. Used by InventoryCrafting so a Wet_Brick recipe can
-- spend Sand / Clay that the player only ever stored in a bag.
_G.GetBagUnitsFor = function(player, resourceName)
	if not SUPPORTED[resourceName] then return 0 end
	local totalPercent = 0
	for _, bag in iterPlayerBags(player) do
		if getBagContent(bag) == resourceName then
			totalPercent = totalPercent + (bag:GetAttribute(FILL_ATTR) or 0)
		end
	end
	return math.floor(totalPercent / PERCENT_PER_UNIT)
end

-- Drains up to `units * 5 %` from the player's bags holding
-- `resourceName`. Returns the unit count actually removed (caller can
-- fall back to inventory for any shortfall). An emptied bag has its
-- BagContent cleared so it can be reused for the other resource.
_G.RemoveBagUnits = function(player, resourceName, units)
	if not SUPPORTED[resourceName] then return 0 end
	units = tonumber(units) or 0
	if units <= 0 then return 0 end

	local percentToRemove = units * PERCENT_PER_UNIT
	local removed = 0
	for _, bag in iterPlayerBags(player) do
		if percentToRemove <= 0 then break end
		if getBagContent(bag) == resourceName then
			local fill = bag:GetAttribute(FILL_ATTR) or 0
			local take = math.min(percentToRemove, fill)
			if take > 0 then
				local newFill = fill - take
				bag:SetAttribute(FILL_ATTR, newFill)
				if newFill <= 0 then
					bag:SetAttribute(CONTENT_ATTR, nil)
				end
				percentToRemove = percentToRemove - take
				removed = removed + take
			end
		end
	end
	return math.floor(removed / PERCENT_PER_UNIT)
end

-- Adds `percent` of `resourceName` into compatible bags. Returns
-- (added, remaining). The first matching bag is topped to MAX_FILL
-- before moving on, so partially-full bags get finished first.
_G.AddToBag = function(player, resourceName, percent, dropPosition)
	percent = tonumber(percent) or 0
	if percent <= 0 then return 0, percent end
	if not SUPPORTED[resourceName] then return 0, percent end

	local bags = iterCompatibleBags(player, resourceName)
	local remaining = percent
	for _, bag in ipairs(bags) do
		if remaining <= 0 then break end
		local fill = bag:GetAttribute(FILL_ATTR) or 0
		local fit  = math.min(remaining, MAX_FILL - fill)
		if fit > 0 then
			bag:SetAttribute(FILL_ATTR, fill + fit)
			bag:SetAttribute(CONTENT_ATTR, resourceName)
			remaining = remaining - fit
		end
	end

	local added = percent - remaining
	if added > 0 then
		local notifyEvent = ReplicatedStorage:FindFirstChild("InventoryNotify")
		if notifyEvent then
			notifyEvent:FireClient(player, resourceName, added)
		end
	end

	return added, remaining
end

-- Shovel-friendly wrapper. Returns true if any of the pile landed, so
-- the caller can decide whether to fall back to a ground drop.
_G.AddPileToBag = function(player, resourceName, dropPosition)
	if (_G.GetBagSpaceFor(player, resourceName) or 0) <= 0 then
		return false
	end
	local added = _G.AddToBag(player, resourceName, PILE_PERCENT, dropPosition)
	return added > 0
end

_G.GetBagPercentPerUnit = function()
	return PERCENT_PER_UNIT
end

-- ── Legacy aliases ─────────────────────────────────────────────────
-- Older callers (and any third-party scripts in the game) keep working
-- through these thin wrappers.
_G.PlayerHasSandBag        = _G.PlayerHasBag
_G.GetSandBagSpace         = function(p) return _G.GetBagSpaceFor(p, "Sand") end
_G.AddSandToBag            = function(p, pct, dp) return _G.AddToBag(p, "Sand", pct, dp) end
_G.AddSandPileToBag        = function(p, dp) return _G.AddPileToBag(p, "Sand", dp) end
_G.GetSandBagPercentPerUnit = _G.GetBagPercentPerUnit

-- Action handler ------------------------------------------------------
-- Inspect-the-equipped-bag → send fill, max AND the locked-in content
-- type so the UI can pick the right stage textures (sand vs clay).
sandBagEvent.OnServerEvent:Connect(function(player, action)
	local bag = getEquippedBag(player)
	if not bag then return end

	if action == "open" then
		local fill    = bag:GetAttribute(FILL_ATTR) or 0
		local content = getBagContent(bag)
		sandBagEvent:FireClient(player, "show", fill, MAX_FILL, content)
	end
end)
