-- MercenaryEquipment.server.lua
-- Tracks which equipment each player has unlocked for mercenaries,
-- and handles equip requests from the Equipment page in the phone menu.
--
-- Unlocked equipment is stored in a replicated Folder under the player
-- so the client can enumerate it. Sword is always unlocked. Other items
-- (e.g. FishingRod) are unlocked when the player crafts them.

local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")

local equipEvent = Instance.new("RemoteEvent")
equipEvent.Name = "MercenaryEquipment"
equipEvent.Parent = rs

-- Tools that can be equipped on mercenaries
local EQUIPPABLE_TOOLS = {
	FishingRod = true,
}

-- ── Per-player folder ───────────────────────────────────────────────────

local function ensureFolder(player)
	local folder = player:FindFirstChild("UnlockedEquipment")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "UnlockedEquipment"
		folder.Parent = player
	end
	-- Sword is always available
	if not folder:FindFirstChild("Sword") then
		local sv = Instance.new("StringValue")
		sv.Name = "Sword"
		sv.Value = "Sword"
		sv.Parent = folder
	end
	return folder
end

-- ── Unlock equipment when player obtains a matching tool ────────────────

local function tryUnlock(player, tool)
	if not tool:IsA("Tool") then return end
	if not EQUIPPABLE_TOOLS[tool.Name] then return end
	local folder = ensureFolder(player)
	if folder:FindFirstChild(tool.Name) then return end
	local sv = Instance.new("StringValue")
	sv.Name = tool.Name
	sv.Value = tool.Name
	sv.Parent = folder
end

local function watchContainer(player, container)
	container.ChildAdded:Connect(function(child)
		tryUnlock(player, child)
	end)
	for _, child in container:GetChildren() do
		tryUnlock(player, child)
	end
end

-- ── Player setup ────────────────────────────────────────────────────────

Players.PlayerAdded:Connect(function(player)
	ensureFolder(player)

	local backpack = player:WaitForChild("Backpack")
	watchContainer(player, backpack)

	player.CharacterAdded:Connect(function(char)
		watchContainer(player, char)
	end)
	if player.Character then
		watchContainer(player, player.Character)
	end
end)

-- Handle players already in game
for _, player in Players:GetPlayers() do
	task.spawn(function()
		ensureFolder(player)
		local backpack = player:FindFirstChild("Backpack")
		if backpack then watchContainer(player, backpack) end
		if player.Character then watchContainer(player, player.Character) end
		player.CharacterAdded:Connect(function(char)
			watchContainer(player, char)
		end)
	end)
end

-- ── Equip request ───────────────────────────────────────────────────────

equipEvent.OnServerEvent:Connect(function(player, action, mercName, weaponId)
	if action ~= "equip" then return end
	if typeof(mercName) ~= "string" or typeof(weaponId) ~= "string" then return end

	-- Verify player owns the mercenary
	local mercFolder = player:FindFirstChild("Mercenaries")
	if not mercFolder then return end
	local mercEntry = mercFolder:FindFirstChild(mercName)
	if not mercEntry then return end

	-- Verify weapon is unlocked
	local eqFolder = player:FindFirstChild("UnlockedEquipment")
	if not eqFolder or not eqFolder:FindFirstChild(weaponId) then return end

	-- Store equipped weapon as attribute (replicated to client)
	mercEntry:SetAttribute("EquippedWeapon", weaponId)

	-- Confirm to client
	equipEvent:FireClient(player, "equipped", mercName, weaponId)
end)
