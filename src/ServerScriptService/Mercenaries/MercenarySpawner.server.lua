-- MercenarySpawner.server.lua
-- Spawns a mercenary model in front of the player when requested
-- from the Mercenaries phone menu.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local spawnEvent = Instance.new("RemoteEvent")
spawnEvent.Name = "SpawnMercenary"
spawnEvent.Parent = ReplicatedStorage

-- Map recruited mercenary names to the model to clone. Add a new
-- recruitable type by dropping its rig under ReplicatedStorage and
-- registering both this map and NpcTypes.module.lua. The map points
-- at the FRIENDLY rig (e.g. Pirate_2 / Infected_Military_Menu);
-- the hostile encounter rigs ("Pirate lvl1" / "Infected Military")
-- are separate models and live in their own spawners.
local SPAWN_MAP = {
	["Pirate lvl1"]       = "Pirate_2",
	["Infected Military"] = "Infected_Military_Menu",
}

-- Per-mercenary baseline overrides applied when the rig is spawned.
-- Lets the Infected Military come out of the gate tougher than Pirate
-- without hand-editing every rig template. nil entries leave the
-- rig's authored values untouched.
local SPAWN_STAT_OVERRIDES = {
	["Infected Military"] = {
		MaxHealth = 420,
		WalkSpeed = 14,
	},
}

-- Default weapon a merc spawns with when its EquippedWeapon attribute
-- isn't set yet (i.e. fresh recruit who has never visited the
-- equipment page). Pirates default to Sword; Soldiers default to
-- Firearm so the rig comes out holding an automatic pistol instead
-- of a sword.
local DEFAULT_WEAPON_BY_MERC = {
	["Pirate lvl1"]       = "Sword",
	["Infected Military"] = "Firearm",
}

-- Per-merc map: equip-slot id → child Model name baked into the rig
-- as the visual for that weapon. The Soldier rig ships with an
-- "AK-47" Model that visualises the Firearm equip; we hide it when
-- a different weapon is selected so the rig isn't holding two
-- weapons at once. Mirror of MERC_THEMES.rigBuiltinWeapons on the
-- client.
local RIG_BUILTIN_WEAPONS_BY_MERC = {
	["Infected Military"] = { Firearm = "AK-47" },
}

local function syncRigBuiltinWeapons(clone, mercName, equippedWeapon)
	local map = RIG_BUILTIN_WEAPONS_BY_MERC[mercName]
	if not map then return end
	for slotId, modelName in pairs(map) do
		local part = clone:FindFirstChild(modelName)
		if part then
			local visible = (slotId == equippedWeapon)
			local t = visible and 0 or 1
			if part:IsA("BasePart") then part.Transparency = t end
			for _, desc in part:GetDescendants() do
				if desc:IsA("BasePart") then desc.Transparency = t end
				if desc:IsA("Decal") then desc.Transparency = t end
			end
		end
	end
end

-- Locate a rig template anywhere it might reasonably live: top-level
-- of ReplicatedStorage / ServerStorage, or nested inside a folder
-- under either. Lets the user organise their assets without forcing a
-- flat layout on the spawner.
local function findTemplate(modelName)
	local candidates = {
		ReplicatedStorage:FindFirstChild(modelName),
		ReplicatedStorage:FindFirstChild(modelName, true),
		ServerStorage:FindFirstChild(modelName),
		ServerStorage:FindFirstChild(modelName, true),
	}
	for _, c in candidates do
		if c then return c end
	end
	return nil
end

-- Prevent spam: one active mercenary per player per type
local activeMercs = {} -- [player] = { [mercName] = modelInstance }

spawnEvent.OnServerEvent:Connect(function(player, mercName)
	if typeof(mercName) ~= "string" then return end

	-- Verify the player actually owns this mercenary
	local folder = player:FindFirstChild("Mercenaries")
	if not folder or not folder:FindFirstChild(mercName) then return end

	-- Look up spawn model name
	local modelName = SPAWN_MAP[mercName]
	if not modelName then return end

	local template = findTemplate(modelName)
	if not template then
		warn("[MercenarySpawner] Model not found:", modelName,
			"(searched ReplicatedStorage + ServerStorage, recursive)")
		return
	end

	-- Clean up previous instance of this mercenary type
	if activeMercs[player] and activeMercs[player][mercName] then
		local old = activeMercs[player][mercName]
		if old and old.Parent then
			old:Destroy()
		end
	end

	-- Get player position and facing direction
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Clone and place 8 studs in front of the player
	local wasArchivable = template.Archivable
	template.Archivable = true
	local clone = template:Clone()
	template.Archivable = wasArchivable

	-- Read equipped weapon and swap to the correct one. Falls back to
	-- the per-merc default so a fresh recruit (never visited equipment
	-- page) gets the right weapon — Pirate → Sword, Soldier → Unarmed.
	local mercEntry = folder:FindFirstChild(mercName)
	local equippedWeapon = (mercEntry and mercEntry:GetAttribute("EquippedWeapon"))
		or DEFAULT_WEAPON_BY_MERC[mercName]
		or "Sword"

	-- Remove all existing tools from the clone (template may have a FishingRod, etc.)
	for _, child in clone:GetChildren() do
		if child:IsA("Tool") then
			child:Destroy()
		end
	end

	-- Equip the chosen weapon from ReplicatedStorage.
	-- FishingRod mercs spawn with a fake (visual-only) rod so they can walk
	-- around holding it. The real rod is swapped in by MercenaryMovement
	-- when the pirate reaches the fishing spot.
	if equippedWeapon ~= "Unarmed" then
		local weaponName = equippedWeapon
		if weaponName == "Sword" then
			weaponName = "ClassicSword"
		elseif weaponName == "FishingRod" then
			weaponName = "FishingRod_Fake"
		end

		local weaponTemplate = ReplicatedStorage:FindFirstChild(weaponName)
			or ReplicatedStorage:FindFirstChild(weaponName, true)
			or ReplicatedStorage:FindFirstChild(equippedWeapon)
			or ReplicatedStorage:FindFirstChild(equippedWeapon, true)
		if weaponTemplate and weaponTemplate:IsA("Tool") then
			local wArchivable = weaponTemplate.Archivable
			weaponTemplate.Archivable = true
			local weaponClone = weaponTemplate:Clone()
			weaponTemplate.Archivable = wArchivable
			weaponClone.Parent = clone
		end
	end

	-- Remove EquipFishingRod script if present (handled by spawner now)
	local equipScript = clone:FindFirstChild("EquipFishingRod")
	if equipScript then equipScript:Destroy() end

	-- Toggle rig-baked weapon Models (e.g. the Soldier's AK-47) so the
	-- merc never holds two weapons at once: the welded equip and the
	-- baked rig piece.
	syncRigBuiltinWeapons(clone, mercName, equippedWeapon)

	-- Toggle backpack model visibility: show only the equipped one,
	-- hide all others. If none is equipped, hide them all. The match
	-- is fuzzy — any direct child whose name contains "ackpack" /
	-- "ackPack" counts, so rigs that name accessories slightly
	-- differently (Backpack, BackPack_lvl2, Soldier_Backpack, …) all
	-- work without per-rig hooks. Accessory instances toggle their
	-- Handle's Transparency (and any descendant BaseParts).
	local equippedBp = mercEntry and mercEntry:GetAttribute("EquippedBackpack") or ""

	local function nameContainsBackpack(s)
		return s:lower():find("backpack", 1, true) ~= nil
	end

	local function setVisible(inst, visible)
		local t = visible and 0 or 1
		if inst:IsA("BasePart") then inst.Transparency = t end
		if inst:IsA("Accessory") then
			local handle = inst:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then handle.Transparency = t end
		end
		for _, desc in inst:GetDescendants() do
			if desc:IsA("BasePart") then desc.Transparency = t end
			if desc:IsA("Decal") then desc.Transparency = t end
		end
	end

	for _, child in clone:GetChildren() do
		if nameContainsBackpack(child.Name) then
			setVisible(child, child.Name == equippedBp)
		end
	end

	-- Apply the chosen skin (Shirt + Pants pair from ReplicatedStorage.Skins)
	-- before the rig hits workspace so the player never sees a one-frame
	-- flash of the rig's authored default clothing. _G.ApplyMercSkin is
	-- published by MercenarySkin.server.lua; if that script hasn't loaded
	-- yet (boot-order race) we silently fall back to the rig's authored
	-- clothing — the live retro-fit path will catch up the next time the
	-- player equips.
	local equippedSkin = mercEntry and mercEntry:GetAttribute("EquippedSkin")
	if typeof(equippedSkin) == "string" and equippedSkin ~= ""
		and typeof(_G.ApplyMercSkin) == "function" then
		_G.ApplyMercSkin(clone, equippedSkin)
	end

	-- Keep the ZombieScript alive on the mercenary so it can fight back
	-- against hostile pirates — the script's SearchForTarget is now
	-- role-aware (it checks the "SpawnedMercenary" tag and will only
	-- pick enemies tagged "HostilePirate", never players).
	--
	-- Strip only the legacy Ragdoller so a dying merc doesn't run the
	-- old R6 ragdoll-cloning path, and disable CanRespawn so a killed
	-- merc stays dead instead of respawning at its spawn point.
	local ragdoller = clone:FindFirstChild("Ragdoller")
	if ragdoller and (ragdoller:IsA("Script") or ragdoller:IsA("LocalScript")) then
		ragdoller:Destroy()
	end

	-- Per-merc-rig scripts (NPC AI, Health, HurtScript, Respawn, etc.)
	-- are left alone — the user authors them on the rig in Studio and
	-- expects them to drive the merc behaviour. The legacy Ragdoller
	-- strip above is the only blanket removal we still do, because
	-- the old R6 ragdoll-cloning path doesn't survive the spawn flow.

	-- Inject the Pirate_2 mercenary behaviours that aren't expected to
	-- be authored on every rig. The Soldier rig ships its own "NPC AI"
	-- that plays the combat role, so we don't inject Combat — only
	-- Fishing + HarvestResources, which are rig-agnostic and the
	-- Soldier rig doesn't author itself. The injector skips when the
	-- clone already carries an authored copy with the same name.
	local pirateMercTemplate = ReplicatedStorage:FindFirstChild("Pirate_2")
		or ReplicatedStorage:FindFirstChild("Pirate_2", true)
	if pirateMercTemplate then
		local MERC_SCRIPTS = { "Fishing", "HarvestResources" }
		for _, scriptName in MERC_SCRIPTS do
			if not clone:FindFirstChild(scriptName) then
				local source = pirateMercTemplate:FindFirstChild(scriptName)
				if source and (source:IsA("Script") or source:IsA("LocalScript")) then
					local wasArchivable = source.Archivable
					source.Archivable = true
					local copy = source:Clone()
					source.Archivable = wasArchivable
					copy.Parent = clone
				end
			end
		end
	end

	local configs = clone:FindFirstChild("Configurations")
	if configs then
		local canRespawn = configs:FindFirstChild("CanRespawn")
		if canRespawn then canRespawn.Value = false end
	end

	-- Force the rig into a live, walkable state before it hits workspace.
	-- The Pirate_2 template ships in a static/"wooden" pose (anchored parts,
	-- no AI script wakes the Humanoid up), which is why the clone just
	-- stands there while being hit. Unanchor every BasePart, restore any
	-- dropped Motor6Ds won't return — but at minimum we can clear anchors,
	-- set a sane WalkSpeed, and clear PlatformStand so MoveTo actually
	-- drives the character.
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end

	local mercHum = clone:FindFirstChildOfClass("Humanoid")
	if mercHum then
		if mercHum.WalkSpeed <= 0 then
			mercHum.WalkSpeed = 12
		end
		-- Per-type baseline overrides. Future tuning of HP / speed for
		-- a specific mercenary type happens in SPAWN_STAT_OVERRIDES,
		-- not by editing the shared rig template.
		local override = SPAWN_STAT_OVERRIDES[mercName]
		if override then
			if override.MaxHealth then
				mercHum.MaxHealth = override.MaxHealth
				mercHum.Health    = override.MaxHealth
			end
			if override.WalkSpeed then
				mercHum.WalkSpeed = override.WalkSpeed
			end
		end
		mercHum.PlatformStand = false
		mercHum.Sit = false
		mercHum.JumpPower = 0
		mercHum.JumpHeight = 0
		pcall(function()
			mercHum:SetStateEnabled(Enum.HumanoidStateType.Running, true)
			mercHum:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, true)
			mercHum:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
		end)
	else
		warn("[MercenarySpawner] Pirate_2 clone has no Humanoid — AI will not run")
	end

	-- Tag BEFORE the script runs (clone.Parent = workspace starts it) so
	-- SearchForTarget sees the mercenary role on its very first tick.
	CollectionService:AddTag(clone, "SpawnedMercenary")

	-- Set attributes BEFORE parenting to workspace. Parenting starts all
	-- scripts inside the model (Combat, Fishing, Animate) and they read
	-- these attributes on their first tick — if the attributes aren't set
	-- yet the scripts make wrong decisions (e.g. Fishing.script exits
	-- because EquippedWeapon is nil → defaults to "Sword").
	clone:SetAttribute("OwnerUserId", player.UserId)
	clone:SetAttribute("MercName", mercName)
	clone:SetAttribute("EquippedWeapon", equippedWeapon or "Sword")

	local spawnCF = hrp.CFrame * CFrame.new(0, 0, -8)
	clone:PivotTo(spawnCF)
	clone.Parent = workspace

	-- After parenting, make the server authoritative for physics so
	-- Humanoid:MoveTo is actually honored (default ownership on a
	-- newly-parented character can fall to the nearest client).
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			pcall(function() d:SetNetworkOwner(nil) end)
		end
	end

	-- Track active mercenary
	if not activeMercs[player] then
		activeMercs[player] = {}
	end
	activeMercs[player][mercName] = clone

	-- Clean up body when mercenary dies
	if mercHum then
		mercHum.Died:Connect(function()
			task.wait(5)
			if not clone or not clone.Parent then return end
			-- Fade out over 1.5 seconds
			local steps = 30
			for step = 1, steps do
				if not clone or not clone.Parent then break end
				local alpha = step / steps
				for _, desc in clone:GetDescendants() do
					if desc:IsA("BasePart") or desc:IsA("Decal") then
						desc.Transparency = alpha
					end
				end
				task.wait(0.05)
			end
			if clone and clone.Parent then
				clone:Destroy()
			end
			if activeMercs[player] and activeMercs[player][mercName] == clone then
				activeMercs[player][mercName] = nil
			end
		end)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if activeMercs[player] then
		for _, model in activeMercs[player] do
			if model and model.Parent then
				model:Destroy()
			end
		end
		activeMercs[player] = nil
	end
end)
