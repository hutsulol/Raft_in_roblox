-- SeedBagSystem.server.lua
-- Routes the "press E on a watered tree bed while holding the leaf
-- bag" interaction. Instead of running the resource-→-Tool equip
-- dance that we tried in SeedToolSystem (and that the user reported
-- as flaky), the leaf bag opens a small selection UI listing every
-- seed the player has in their main inventory. They click one, the
-- server consumes that resource and plants Stage_1 on the target
-- bed (palm seeds keep growing through Stage_4, as before).
--
-- The bag itself doesn't store seeds — it's a Tool whose only job
-- is to surface the picker UI. Keeps the inventory model simple
-- (one source of truth for seed counts).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BAG_TOOL_NAME    = "leaf bag"   -- matches the user's Tool template
local INTERACT_RANGE   = 15           -- studs from player to bed
local SEED_NAMES       = { "Banana_Seed", "Coconut_Seed", "Pineapple_Seed" }

local seedBagEvent = ReplicatedStorage:FindFirstChild("SeedBagAction")
if not seedBagEvent then
	seedBagEvent = Instance.new("RemoteEvent")
	seedBagEvent.Name = "SeedBagAction"
	seedBagEvent.Parent = ReplicatedStorage
end

while not _G.GetInventory or not _G.RemoveResourceFromInventory do
	task.wait(0.1)
end

-- ─── Helpers ───
local function getEquippedBag(player)
	local char = player.Character
	if not char then return nil end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if tool and tool.Name == BAG_TOOL_NAME then return tool end
	return nil
end

local function isValidBed(target, hrp)
	if not target or not target:IsA("Model") then return false end
	if not target:GetAttribute("IsBedGardenForTree") then return false end
	if not target:GetAttribute("IsWatered") then return false end
	if target:GetAttribute("GrowthStage") then return false end
	if (hrp.Position - target:GetPivot().Position).Magnitude > INTERACT_RANGE then return false end
	return true
end

-- Build the seed-counts snapshot we ship to the client UI so it can
-- render exactly the slots the player owns.
local function buildSeedCounts(player)
	local inv = _G.GetInventory(player)
	local list = {}
	for _, seedName in ipairs(SEED_NAMES) do
		local count = inv[seedName] or 0
		if count > 0 then
			list[#list + 1] = { name = seedName, count = count }
		end
	end
	return list
end

-- ─── Action handler ───
seedBagEvent.OnServerEvent:Connect(function(player, action, target, seedName)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if action == "open" then
		if not getEquippedBag(player) then return end
		if not isValidBed(target, hrp) then return end

		seedBagEvent:FireClient(player, "show", target, buildSeedCounts(player))

	elseif action == "plant" then
		if not getEquippedBag(player) then return end
		if not isValidBed(target, hrp) then return end
		if typeof(seedName) ~= "string" then return end

		-- Confirm the player still owns at least one of the selected
		-- seed. Their inventory could've changed between opening the
		-- bag and clicking a slot.
		local inv = _G.GetInventory(player)
		if (inv[seedName] or 0) < 1 then return end

		-- Whitelist the seed name so a hostile client can't pass
		-- "Log" or some other resource to consume.
		local ok = false
		for _, allowed in ipairs(SEED_NAMES) do
			if allowed == seedName then ok = true break end
		end
		if not ok then return end

		_G.RemoveResourceFromInventory(player, seedName, 1)
		if _G.SendInventory then
			_G.SendInventory(player)
		end

		target:SetAttribute("PlantedSeed", seedName)
		target:SetAttribute("GrowthStage", 0)
		target:SetAttribute("WateredTime", nil)

		-- Call GardenSystem's growTree via the global hook. Set up
		-- below in this file so we don't have a hard module-order
		-- dependency on GardenSystem.
		if typeof(_G.GrowTreeFromSeed) == "function" then
			_G.GrowTreeFromSeed(target)
		end

		-- Tell the client to close the picker + refresh.
		seedBagEvent:FireClient(player, "close")
	end
end)
