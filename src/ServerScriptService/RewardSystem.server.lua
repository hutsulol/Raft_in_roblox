-- RewardSystem.server.lua
-- Grants the building won in the post-wave reward roll (RewardRoll.client.lua).
-- The win is a placeable Tool (same shape CraftingSystem makes), handed over with
-- _G.GiveToolOrDrop — it slots into the hotbar, or drops/vanishes if there's no
-- room. The Cannon then places via the existing CanonPlacer; the AA via its placer.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradeConfig = require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig"))

-- name → hotbar icon for the granted tool
local PLACEABLES = {
	Cannon           = "rbxassetid://118236242385241",
	Deffender        = "rbxassetid://86928740553428",
	MagmaCannon      = "rbxassetid://97658619335375",
	Big_Magma_Cannon = "rbxassetid://90669361199026",
	Pulemet_lvl_1    = "rbxassetid://106277044945645", -- пулемёт (TurretSystem рерижит его после установки)
	Pulemet_lvl_2    = "rbxassetid://79105833790080",  -- эпический пулемёт
}

local claimEvent = ReplicatedStorage:FindFirstChild("RewardClaim")
if not claimEvent then
	claimEvent = Instance.new("RemoteEvent")
	claimEvent.Name = "RewardClaim"
	claimEvent.Parent = ReplicatedStorage
end

-- Build the placeholder tool EXACTLY like CraftingSystem does, so it equips and
-- places through the same CanonPlacer / CanonSystem path as a crafted one.
local function makePlaceableTool(name, icon)
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.CanBeDropped = false
	if icon then tool.TextureId = icon end
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.Parent = tool
	return tool
end

claimEvent.OnServerEvent:Connect(function(plr, itemName)
	local icon = PLACEABLES[itemName]
	if not icon then return end -- only the known buildings can be claimed
	-- Заблокированную пушку выдать нельзя, даже если клиент попросил напрямую:
	-- разблокировка покупается в лобби (атрибут WUnlock_<id>), сервер — истина.
	if not UpgradeConfig.isUnlocked(plr, itemName) then
		warn(("[Reward] %s просит заблокированную %s — отказ"):format(plr.Name, itemName))
		return
	end
	local tool = makePlaceableTool(itemName, icon)
	if _G.GiveToolOrDrop then
		_G.GiveToolOrDrop(plr, tool) -- slots into the hotbar, or drops if there's no room
	else
		local bp = plr:FindFirstChildOfClass("Backpack")
		if bp then tool.Parent = bp else tool:Destroy() end
	end
	if _G.SendInventory then _G.SendInventory(plr) end -- refresh the hotbar/inventory
end)
