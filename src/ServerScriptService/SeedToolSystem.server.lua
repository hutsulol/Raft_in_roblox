-- SeedToolSystem.server.lua
-- Bridges the seed-resource inventory representation with the seed
-- Tool representation. Players see stacked Banana_Seed /
-- Coconut_Seed / Pineapple_Seed counts in their inventory; when they
-- click the slot (or press the matching hotbar number) the client
-- fires EquipSeedAsTool. The server then:
--
--   1. Decrements the resource stack by 1.
--   2. Clones the corresponding Tool template from ReplicatedStorage.
--   3. Parents the Tool to the character so it equips immediately.
--   4. Watches the Tool's ancestry: if the player switches away (Tool
--      parent goes from character → Backpack), we refund the resource
--      and destroy the Tool so it never lingers as a standalone
--      Backpack entry — keeps the inventory single-source-of-truth.
--
-- GardenSystem.plantSeedTool sets the "Consumed" attribute on the
-- Tool *before* destroying it, so the refund check below knows the
-- plant path already "spent" the seed and doesn't double-refund.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Resource name → Tool template name. The user's Tool templates use
-- "Palm_seed" for the coconut seed (since it grows into a palm) and
-- a lowercase "_seed" suffix on Pineapple — verbatim mirror of what
-- they placed in ReplicatedStorage.Trees_Grow.
local SEED_RESOURCE_TO_TOOL = {
	Banana_Seed    = "Banana_Seed",
	Coconut_Seed   = "Palm_seed",
	Pineapple_Seed = "Pineapple_seed",
}

-- Inverse map populated below — Tool name → resource name for the
-- refund path.
local SEED_TOOL_TO_RESOURCE = {}
for resName, toolName in pairs(SEED_RESOURCE_TO_TOOL) do
	SEED_TOOL_TO_RESOURCE[toolName] = resName
end

local equipEvent = ReplicatedStorage:FindFirstChild("EquipSeedAsTool")
if not equipEvent then
	equipEvent = Instance.new("RemoteEvent")
	equipEvent.Name = "EquipSeedAsTool"
	equipEvent.Parent = ReplicatedStorage
end

-- Wait for the inventory globals before accepting any client requests.
while not _G.AddResourceToInventory or not _G.RemoveResourceFromInventory or not _G.GetInventory do
	task.wait(0.1)
end

local function findSeedToolTemplate(toolName)
	-- ReplicatedStorage.Trees_Grow holds the user's authored Tool
	-- templates. Try the top-level direct lookup first (covers anyone
	-- who keeps them at the root), then a recursive search.
	return ReplicatedStorage:FindFirstChild(toolName, true)
end

-- Refund a Tool's resource back to the player's inventory and destroy
-- the Tool. Idempotent — flips the Refunded attribute so a double-fire
-- of the ancestry handler doesn't double the resource.
local function refundSeed(player, tool)
	if not tool or tool:GetAttribute("Refunded") then return end
	if tool:GetAttribute("Consumed") then
		tool:Destroy()
		return
	end
	tool:SetAttribute("Refunded", true)

	local seedName = tool:GetAttribute("SeedResource")
	if not seedName then
		tool:Destroy()
		return
	end

	if player and player.Parent then
		_G.AddResourceToInventory(player, seedName, 1, nil, true)
	end
	tool:Destroy()
end

equipEvent.OnServerEvent:Connect(function(player, seedName)
	if typeof(seedName) ~= "string" then return end
	local toolName = SEED_RESOURCE_TO_TOOL[seedName]
	if not toolName then return end

	local inv = _G.GetInventory(player)
	if (inv[seedName] or 0) < 1 then return end

	local template = findSeedToolTemplate(toolName)
	if not template or not template:IsA("Tool") then
		warn(("[SeedToolSystem] template %q not found in ReplicatedStorage"):format(toolName))
		return
	end

	-- Block re-equipping a seed of the same kind while one is already
	-- in hand or in Backpack — otherwise the player could decant the
	-- whole stack into a wall of Backpack Tools and the refund path
	-- would chain.
	local char     = player.Character
	local backpack = player:FindFirstChild("Backpack")
	for _, container in ipairs({ char, backpack }) do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child.Name == toolName and child:GetAttribute("SeedResource") == seedName then
					return
				end
			end
		end
	end

	if not backpack then return end

	_G.RemoveResourceFromInventory(player, seedName, 1)
	if _G.SendInventory then
		_G.SendInventory(player)
	end

	local tool = template:Clone()
	tool.Name = toolName
	tool:SetAttribute("SeedResource", seedName)
	tool:SetAttribute("OwnerUserId", player.UserId)
	tool.CanBeDropped = false

	-- Parent into Backpack first. The AncestryChanged refund watcher
	-- below is gated on the "Ready" attribute so this initial parent
	-- change AND the subsequent EquipTool() shuffle don't trip a
	-- false refund. Ready flips to true once Tool.Equipped has fired
	-- once — only AFTER that point does an unequip mean "the player
	-- changed their mind".
	tool.Parent = backpack

	-- Force-equip: drop whatever else is in hand, then equip the new
	-- seed Tool. Without UnequipTools() first, Roblox parks the new
	-- Tool inside Character but keeps the existing one (e.g. the
	-- Stone_Axe) visibly held, which the user reported as "the seed
	-- doesn't come into hand". EquipTool also re-parents from
	-- Backpack to Character, which is the cue we wait for below.
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function() humanoid:UnequipTools() end)
		pcall(function() humanoid:EquipTool(tool) end)
	end

	-- Connect the refund-on-leave watcher. We start it disabled and
	-- arm it on the first Equipped event so the Backpack-→-Character
	-- transition we just performed (via EquipTool) doesn't refund.
	tool.Equipped:Once(function()
		tool:SetAttribute("Ready", true)
	end)

	tool.AncestryChanged:Connect(function(_, newParent)
		if not tool:GetAttribute("Ready") then return end
		if newParent == nil then
			-- Tool fully removed from the world. Refund unless the
			-- plant action stamped Consumed=true.
			task.defer(function()
				refundSeed(player, tool)
			end)
		elseif newParent and newParent:IsA("Backpack") then
			-- Player swapped slots. Refund + destroy so the count
			-- returns to the inventory stack.
			task.defer(function()
				refundSeed(player, tool)
			end)
		end
	end)
end)
