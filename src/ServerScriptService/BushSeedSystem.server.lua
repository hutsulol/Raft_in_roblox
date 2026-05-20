-- BushSeedSystem.server.lua
-- Equip-from-inventory plumbing for bush seeds (Pineapple_Bush_Seed
-- today; same pattern handles any future bush seed). Mirrors
-- FoodSystem's flow: the inventory click fires
-- EquipBushSeedAsTool(player, resourceName); we decrement one from
-- the inventory, clone the matching Tool template into Backpack,
-- force-equip it (UnequipTools → EquipTool so it lands in hand even
-- if something else was held), and set up a refund guard so the
-- resource comes back if the player unequips without using the Tool.
--
-- The Tool itself is detected by CupPurifier's onToolEquipped and
-- drives the existing bush-placement ghost. HungerSystem's placeBush
-- action consumes the Tool on a successful place (sets Consumed =
-- true, then Destroy), which is the same flag the refund guard
-- checks below.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Each entry: { template = "<RS Tool name>", toolName = "<runtime name>" }.
-- Reusing the existing Pineapple_Seed Tool art avoids needing a brand
-- new asset; we just rename the clone so CupPurifier / HungerSystem
-- recognise it as a bush-placement Tool rather than a tree seed.
local BUSH_SEEDS = {
	Pineapple_Bush_Seed = {
		template = "Pineapple_Seed",
		toolName = "Pineapple_Bush_Seed",
	},
}

local equipEvent = ReplicatedStorage:FindFirstChild("EquipBushSeedAsTool")
if not equipEvent then
	equipEvent = Instance.new("RemoteEvent")
	equipEvent.Name = "EquipBushSeedAsTool"
	equipEvent.Parent = ReplicatedStorage
end

-- Wait for the inventory helpers so the first request can't outrun
-- their definitions.
while not _G.GetInventory or not _G.RemoveResourceFromInventory
	or not _G.AddResourceToInventory do
	task.wait(0.1)
end

local function refundBushSeed(player, resourceName)
	if not BUSH_SEEDS[resourceName] then return end
	_G.AddResourceToInventory(player, resourceName, 1, nil, true)
	if _G.SendInventory then _G.SendInventory(player) end
end

equipEvent.OnServerEvent:Connect(function(player, resourceName)
	local spec = BUSH_SEEDS[resourceName]
	if not spec then return end

	local char = player.Character
	if not char then return end
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	local inv = _G.GetInventory(player)
	if (inv[resourceName] or 0) <= 0 then return end

	-- Resolve the Tool template before touching the inventory so a
	-- missing asset can't eat the resource silently.
	local template = ReplicatedStorage:FindFirstChild(spec.template)
		or ReplicatedStorage:FindFirstChild(spec.template, true)
	if not template or not template:IsA("Tool") then
		warn("[BushSeed] Tool template missing: " .. spec.template)
		return
	end

	_G.RemoveResourceFromInventory(player, resourceName, 1)
	if _G.SendInventory then _G.SendInventory(player) end

	local tool = template:Clone()
	tool.Name = spec.toolName
	tool:SetAttribute("BushSeedResource", resourceName)
	tool:SetAttribute("OwnerUserId", player.UserId)
	tool.CanBeDropped = false
	tool.Parent = backpack

	-- Force-equip — drop whatever is in hand and put the seed in it.
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function() humanoid:UnequipTools() end)
		pcall(function() humanoid:EquipTool(tool) end)
	end

	-- Refund guard: arm `Ready` on the first Equipped so the initial
	-- Backpack→Character shuffle EquipTool just performed doesn't
	-- masquerade as the player putting it back. Consumed is set by
	-- HungerSystem.placeBush when the Tool is spent on a Garden.
	tool.Equipped:Once(function()
		tool:SetAttribute("Ready", true)
	end)
	tool.AncestryChanged:Connect(function(_, newParent)
		if not tool:GetAttribute("Ready") then return end
		if tool:GetAttribute("Consumed") then return end
		if newParent == nil or (newParent and newParent:IsA("Backpack")) then
			task.defer(function()
				refundBushSeed(player, resourceName)
				if tool.Parent then tool:Destroy() end
			end)
		end
	end)
end)
