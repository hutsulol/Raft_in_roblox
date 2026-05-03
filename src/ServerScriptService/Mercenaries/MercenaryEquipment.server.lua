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

-- Tools that can be equipped on mercenaries. Adding a new equippable
-- weapon is a one-line entry here plus a Tool template under
-- ReplicatedStorage. Per-mercenary restriction (e.g. firearms only for
-- Infected Military) is enforced by the client menu via restrictedTo;
-- the server still validates that the merc actually owns the weapon
-- folder entry below.
local EQUIPPABLE_TOOLS = {
	FishingRod = true,
	Firearm    = true,
	Shotgun    = true,
}

-- Items that occupy the "backpack" slot (a separate equipment slot from
-- the weapon slot, and which enables a mercenary inventory).
local EQUIPPABLE_BACKPACKS = {
	Backpack = true,
	BackPack_lvl2 = true,
}

-- Slot counts per backpack type
local BACKPACK_SLOT_COUNTS = {
	Backpack = 6,
	BackPack_lvl2 = 9,
}
local DEFAULT_SLOTS = 6

-- All backpack model names on the pirate rig (for visibility toggling)
local BACKPACK_MODELS = { "Backpack", "BackPack_lvl2" }

local function getSlotCount(mercEntry)
	local bp = mercEntry:GetAttribute("EquippedBackpack") or ""
	return BACKPACK_SLOT_COUNTS[bp] or DEFAULT_SLOTS
end

-- ── Backpack inventory helpers ──────────────────────────────────────────

local function initBackpackSlots(mercEntry)
	local slots = getSlotCount(mercEntry)
	for i = 1, slots do
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
	-- BackPack_lvl2 unlocked for testing
	if not folder:FindFirstChild("BackPack_lvl2") then
		local sv = Instance.new("StringValue")
		sv.Name = "BackPack_lvl2"
		sv.Value = "BackPack_lvl2"
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

-- Equipment automatically unlocked when the player recruits a given
-- mercenary type. Lets the Infected Military come pre-equipped with
-- its loadout the moment the player adds it to their roster.
local AUTO_UNLOCK_BY_MERC = {
	["Infected Military"] = { "Firearm", "Shotgun" },
}

-- Mirror of the client's EQUIP_ITEMS restrictedTo metadata. The
-- server uses this to (a) reject equip requests that target a
-- weapon the merc isn't allowed to hold, and (b) scrub stale
-- EquippedWeapon attributes left over from earlier builds where
-- the restriction wasn't enforced (e.g. a Soldier carrying "Sword"
-- from a pre-T45 session).
local ALLOWED_WEAPONS_BY_MERC = {
	["Pirate lvl1"]       = { Sword = true, FishingRod = true, Unarmed = true },
	["Infected Military"] = { Firearm = true, Shotgun = true, FishingRod = true, Unarmed = true },
}

local function isWeaponAllowedForMerc(mercName, weaponId)
	local allowed = ALLOWED_WEAPONS_BY_MERC[mercName]
	if not allowed then return true end -- unknown merc → unrestricted
	return allowed[weaponId] == true
end

local function validateMercWeapon(mercEntry)
	local allowed = ALLOWED_WEAPONS_BY_MERC[mercEntry.Name]
	if not allowed then return end
	local cur = mercEntry:GetAttribute("EquippedWeapon")
	if cur and not allowed[cur] then
		-- Clear so the client falls back to MERC_THEMES.defaultWeapon
		-- (Pirate → Sword, Soldier → Firearm) — keeps stale state
		-- from polluting any of the management pages.
		mercEntry:SetAttribute("EquippedWeapon", nil)
	end
end

local function grantUnlock(player, itemId)
	local folder = ensureFolder(player)
	if folder:FindFirstChild(itemId) then return end
	local sv = Instance.new("StringValue")
	sv.Name = itemId
	sv.Value = itemId
	sv.Parent = folder
end

local function watchMercenaries(player)
	local mercFolder = player:FindFirstChild("Mercenaries")
		or player:WaitForChild("Mercenaries", 10)
	if not mercFolder then return end

	local function onMercAdded(child)
		-- Scrub any stale EquippedWeapon attribute that's no longer
		-- valid for this merc (carried over from earlier sessions
		-- before per-merc restrictedTo was enforced).
		validateMercWeapon(child)

		local list = AUTO_UNLOCK_BY_MERC[child.Name]
		if not list then return end
		for _, itemId in list do
			grantUnlock(player, itemId)
		end
	end
	mercFolder.ChildAdded:Connect(onMercAdded)
	for _, child in mercFolder:GetChildren() do onMercAdded(child) end
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

	task.spawn(watchMercenaries, player)
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
		watchMercenaries(player)
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
			if not found
				and itemId ~= "Sword"
				and itemId ~= "Backpack"
				and itemId ~= "Unarmed"
			then return end
			if found then
				tryUnlock(player, backpack:FindFirstChild(itemId) or player.Character:FindFirstChild(itemId))
			end
		end

		-- Split: backpack vs weapon (they occupy separate slots)
		if EQUIPPABLE_BACKPACKS[itemId] then
			mercEntry:SetAttribute("EquippedBackpack", itemId)
			initBackpackSlots(mercEntry)

			-- Toggle visibility: hide every backpack-ish child on the
			-- live merc, then show the one whose Name matches the
			-- equip request. Fuzzy-matches by "backpack" substring so
			-- soldier rigs that name accessories slightly differently
			-- still get toggled. Accessory instances also toggle via
			-- their Handle child.
			local CollectionService = game:GetService("CollectionService")
			local function nameContainsBackpack(s)
				return s:lower():find("backpack", 1, true) ~= nil
			end
			for _, model in CollectionService:GetTagged("SpawnedMercenary") do
				if model:GetAttribute("OwnerUserId") == player.UserId
					and model:GetAttribute("MercName") == mercName
					and model.Parent then
					for _, child in model:GetChildren() do
						if nameContainsBackpack(child.Name) then
							local show = (child.Name == itemId)
							local t = show and 0 or 1
							if child:IsA("BasePart") then child.Transparency = t end
							if child:IsA("Accessory") then
								local handle = child:FindFirstChild("Handle")
								if handle and handle:IsA("BasePart") then handle.Transparency = t end
							end
							for _, desc in child:GetDescendants() do
								if desc:IsA("BasePart") then desc.Transparency = t end
								if desc:IsA("Decal") then desc.Transparency = t end
							end
						end
					end
				end
			end
		else
			-- Reject equipping a weapon that's restricted away from
			-- this merc (e.g. a Soldier trying to equip Pirate Sword,
			-- or a Pirate trying to equip Firearm). Without this check
			-- a malicious client could bypass the per-merc UI filter
			-- by firing the RemoteEvent directly.
			if not isWeaponAllowedForMerc(mercName, itemId) then
				return
			end
			mercEntry:SetAttribute("EquippedWeapon", itemId)

			-- Update visibility of any rig-baked weapon Models on the
			-- live merc immediately. The Soldier's AK-47 rig piece
			-- toggles based on whether the equipped weapon is Firearm
			-- so the merc isn't holding both at once. Mirrors the
			-- per-merc table in MercenarySpawner.
			local CollectionService = game:GetService("CollectionService")
			local RIG_BUILTIN_WEAPONS = {
				["Infected Military"] = { Firearm = "AK-47" },
			}
			local builtinMap = RIG_BUILTIN_WEAPONS[mercName]

			-- If Unarmed, strip the tool from any currently-spawned merc
			-- owned by this player so the change is visible immediately.
			for _, model in CollectionService:GetTagged("SpawnedMercenary") do
				if model:GetAttribute("OwnerUserId") == player.UserId
					and model:GetAttribute("MercName") == mercName
					and model.Parent then
					if itemId == "Unarmed" then
						model:SetAttribute("EquippedWeapon", "Unarmed")
						for _, child in model:GetChildren() do
							if child:IsA("Tool") then
								child:Destroy()
							end
						end
					end

					-- Sync rig-baked weapon visibility to the new equip.
					if builtinMap then
						for slotId, modelName in pairs(builtinMap) do
							local part = model:FindFirstChild(modelName)
							if part then
								local visible = (slotId == itemId)
								local t = visible and 0 or 1
								if part:IsA("BasePart") then part.Transparency = t end
								for _, desc in part:GetDescendants() do
									if desc:IsA("BasePart") then desc.Transparency = t end
									if desc:IsA("Decal") then desc.Transparency = t end
								end
							end
						end
					end
				end
			end
		end

		equipEvent:FireClient(player, "equipped", mercName, itemId)

	elseif action == "takeItem" then
		-- Transfer one slot's contents from mercenary inventory to player inventory
		local slotIndex = arg
		if typeof(slotIndex) ~= "number" then return end
		slotIndex = math.floor(slotIndex)
		local maxSlots = getSlotCount(mercEntry)
		if slotIndex < 1 or slotIndex > maxSlots then return end

		local itemName = mercEntry:GetAttribute("Slot" .. slotIndex .. "_Name")
		local count = mercEntry:GetAttribute("Slot" .. slotIndex .. "_Count")
		if typeof(itemName) ~= "string" or itemName == "" then return end
		if typeof(count) ~= "number" or count <= 0 then return end

		if _G.AddResourceToInventory then
			_G.AddResourceToInventory(player, itemName, count, nil)
		end

		-- Clear the slot
		mercEntry:SetAttribute("Slot" .. slotIndex .. "_Name", "")
		mercEntry:SetAttribute("Slot" .. slotIndex .. "_Count", 0)
	end
end)
