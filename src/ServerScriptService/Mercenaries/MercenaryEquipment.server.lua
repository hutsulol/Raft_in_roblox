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

-- Items that occupy the "backpack" slot (a separate equipment slot from
-- the weapon slot, and which enables a 6-slot mercenary inventory).
local EQUIPPABLE_BACKPACKS = {
	Backpack = true,
}

local MERC_INVENTORY_SLOTS = 6

-- ── Backpack inventory helpers ──────────────────────────────────────────

local function initBackpackSlots(mercEntry)
	for i = 1, MERC_INVENTORY_SLOTS do
		if mercEntry:GetAttribute("Slot" .. i .. "_Name") == nil then
			mercEntry:SetAttribute("Slot" .. i .. "_Name", "")
			mercEntry:SetAttribute("Slot" .. i .. "_Count", 0)
		end
	end
end

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
	-- Backpack is always available (free starter artifact)
	if not folder:FindFirstChild("Backpack") then
		local sv = Instance.new("StringValue")
		sv.Name = "Backpack"
		sv.Value = "Backpack"
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

-- ── Equip / inventory request ──────────────────────────────────────────

equipEvent.OnServerEvent:Connect(function(player, action, mercName, arg)
	if typeof(action) ~= "string" then return end
	if typeof(mercName) ~= "string" then return end

	-- Verify player owns the mercenary
	local mercFolder = player:FindFirstChild("Mercenaries")
	if not mercFolder then return end
	local mercEntry = mercFolder:FindFirstChild(mercName)
	if not mercEntry then return end

	if action == "equip" then
		if typeof(arg) ~= "string" then return end
		local itemId = arg

		-- Verify item is unlocked (folder, then fallback to Backpack/Character)
		local eqFolder = ensureFolder(player)
		if not eqFolder:FindFirstChild(itemId) then
			local found = false
			local backpack = player:FindFirstChild("Backpack")
			if backpack and backpack:FindFirstChild(itemId) then found = true end
			if not found and player.Character and player.Character:FindFirstChild(itemId) then
				found = true
			end
			if not found and itemId ~= "Sword" and itemId ~= "Backpack" then return end
			if found then
				tryUnlock(player, backpack:FindFirstChild(itemId) or player.Character:FindFirstChild(itemId))
			end
		end

		-- Split: backpack vs weapon (they occupy separate slots)
		if EQUIPPABLE_BACKPACKS[itemId] then
			mercEntry:SetAttribute("EquippedBackpack", itemId)
			initBackpackSlots(mercEntry)

			-- Make the Backpack part visible on the spawned model so
			-- the player sees it appear immediately.
			local CollectionService = game:GetService("CollectionService")
			for _, model in CollectionService:GetTagged("SpawnedMercenary") do
				if model:GetAttribute("OwnerUserId") == player.UserId
					and model:GetAttribute("MercName") == mercName
					and model.Parent then
					local bp = model:FindFirstChild("Backpack")
					if bp then
						if bp:IsA("BasePart") then
							bp.Transparency = 0
						end
						for _, desc in bp:GetDescendants() do
							if desc:IsA("BasePart") then
								desc.Transparency = 0
							end
						end
					end
				end
			end
		else
			mercEntry:SetAttribute("EquippedWeapon", itemId)
		end

		equipEvent:FireClient(player, "equipped", mercName, itemId)

	elseif action == "takeItem" then
		-- Transfer one slot's contents from mercenary inventory to player inventory
		local slotIndex = arg
		if typeof(slotIndex) ~= "number" then return end
		slotIndex = math.floor(slotIndex)
		if slotIndex < 1 or slotIndex > MERC_INVENTORY_SLOTS then return end

		local itemName = mercEntry:GetAttribute("Slot" .. slotIndex .. "_Name")
		local count = mercEntry:GetAttribute("Slot" .. slotIndex .. "_Count")
		if typeof(itemName) ~= "string" or itemName == "" then return end
		if typeof(count) ~= "number" or count <= 0 then return end

		if _G.GetInventory then
			local inv = _G.GetInventory(player)
			if inv then
				inv[itemName] = (inv[itemName] or 0) + count
				if _G.SendInventory then
					_G.SendInventory(player)
				end
			end
		end

		-- Clear the slot
		mercEntry:SetAttribute("Slot" .. slotIndex .. "_Name", "")
		mercEntry:SetAttribute("Slot" .. slotIndex .. "_Count", 0)
	end
end)
