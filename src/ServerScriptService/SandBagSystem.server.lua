-- SandBagSystem.server.lua
-- The "Sand Bag" Tool is the sole storage for Sand. The shovel
-- writes dig payloads into the equipped bag's SandFill attribute
-- (0..100, percent) and the inventory never sees a Sand resource
-- entry. Without a bag in the player's inventory the dug pile spills
-- out as a physical ground drop instead, so the player can't lose
-- the resource — they just can't keep it until they craft a bag.
--
-- One sand pile (one Diggable Sand part finishing its 5-hit chain)
-- yields PILE_PERCENT = 15 %. The bag fits PILE_PERCENT × (~7)
-- piles before it's full.
--
-- Adding a new bag-style storage (clay, etc.) later means cloning
-- this file and changing BAG_TOOL_NAME + ATTRIBUTE_NAME.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BAG_TOOL_NAME    = "Sand Bag"
local ATTRIBUTE_NAME   = "SandFill"  -- 0..100, percent
local MAX_FILL         = 100
local PILE_PERCENT     = 15          -- one full sand pile = 15 %

local sandBagEvent = ReplicatedStorage:FindFirstChild("SandBagAction")
if not sandBagEvent then
	sandBagEvent = Instance.new("RemoteEvent")
	sandBagEvent.Name = "SandBagAction"
	sandBagEvent.Parent = ReplicatedStorage
end

while not _G.GetInventory do
	task.wait(0.1)
end

-- Soft match — same trick the leaf bag uses, so a Studio rename
-- ("sand bag", "Sand_Bag", …) doesn't break the system.
local function isBagTool(tool)
	if not tool or not tool:IsA("Tool") then return false end
	local a = tool.Name:lower():gsub("[_%s]", "")
	local b = BAG_TOOL_NAME:lower():gsub("[_%s]", "")
	return a == b
end

local function initBag(tool)
	if tool:GetAttribute(ATTRIBUTE_NAME) == nil then
		tool:SetAttribute(ATTRIBUTE_NAME, 0)
	end
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

_G.PlayerHasSandBag = function(player)
	return #iterPlayerBags(player) > 0
end

-- Sum of remaining space across every bag the player owns. Used by
-- the shovel + ground-pickup paths to decide whether to keep the
-- sand or drop it on the floor.
_G.GetSandBagSpace = function(player)
	local space = 0
	for _, bag in ipairs(iterPlayerBags(player)) do
		local fill = bag:GetAttribute(ATTRIBUTE_NAME) or 0
		space = space + math.max(0, MAX_FILL - fill)
	end
	return space
end

-- Tries to dump `percent` worth of sand into the player's bags,
-- topping the first one up before moving on to the next. Returns
-- whatever percent couldn't fit so the caller can fall back to a
-- ground drop / refusal toast.
_G.AddSandToBag = function(player, percent, dropPosition)
	percent = tonumber(percent) or 0
	if percent <= 0 then return 0 end

	local bags = iterPlayerBags(player)
	local remaining = percent
	for _, bag in ipairs(bags) do
		if remaining <= 0 then break end
		local fill = bag:GetAttribute(ATTRIBUTE_NAME) or 0
		local fit  = math.min(remaining, MAX_FILL - fill)
		if fit > 0 then
			bag:SetAttribute(ATTRIBUTE_NAME, fill + fit)
			remaining = remaining - fit
		end
	end

	local added = percent - remaining
	if added > 0 then
		-- Notify-card surfaces the gain. Reuses InventoryNotify so
		-- the player gets the same "+N Sand" cue every other pickup
		-- uses; the count is the percent gained, displayed as
		-- "Sand +15".
		local notifyEvent = ReplicatedStorage:FindFirstChild("InventoryNotify")
		if notifyEvent then
			notifyEvent:FireClient(player, "Sand", added)
		end
	end

	return added, remaining
end

-- Shovel-friendly wrapper: drops one pile's worth of sand into the
-- bag. Returns true if it landed, false if no room / no bag (caller
-- should drop on the ground in that case).
_G.AddSandPileToBag = function(player, dropPosition)
	if not _G.PlayerHasSandBag(player) then return false end
	if (_G.GetSandBagSpace(player) or 0) <= 0 then return false end
	local added = _G.AddSandToBag(player, PILE_PERCENT, dropPosition)
	return added > 0
end

-- Tells the client how much of a stack of dropped sand it can pick
-- up given the current bag space. Used by the DropItem pickup
-- handler to mirror the seed-bag behaviour.
_G.GetSandBagPercentPerUnit = function()
	-- One "Sand" resource unit = 5 % bag fill (user spec).
	return 5
end

-- Action handler ------------------------------------------------------
sandBagEvent.OnServerEvent:Connect(function(player, action)
	local bag = getEquippedBag(player)
	if not bag then return end

	if action == "open" then
		local fill = bag:GetAttribute(ATTRIBUTE_NAME) or 0
		sandBagEvent:FireClient(player, "show", fill, MAX_FILL)
	end
end)
