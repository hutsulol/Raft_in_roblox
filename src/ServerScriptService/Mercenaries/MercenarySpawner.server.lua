-- MercenarySpawner.server.lua
-- Spawns a mercenary model in front of the player when requested
-- from the Mercenaries phone menu.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local spawnEvent = Instance.new("RemoteEvent")
spawnEvent.Name = "SpawnMercenary"
spawnEvent.Parent = ReplicatedStorage

-- Map recruited mercenary names to the model to clone
local SPAWN_MAP = {
	["Pirate lvl1"] = "Pirate_2",
}

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

	local template = ReplicatedStorage:FindFirstChild(modelName)
	if not template then
		warn("[MercenarySpawner] Model not found:", modelName)
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

	-- Read equipped weapon and swap to the correct one
	local mercEntry = folder:FindFirstChild(mercName)
	local equippedWeapon = mercEntry and mercEntry:GetAttribute("EquippedWeapon") or "Sword"

	-- Remove all existing tools from the clone (template may have a FishingRod, etc.)
	for _, child in clone:GetChildren() do
		if child:IsA("Tool") then
			child:Destroy()
		end
	end

	-- Equip the chosen weapon from ReplicatedStorage
	local weaponName = equippedWeapon
	-- For default sword, try common names
	if weaponName == "Sword" then
		weaponName = "ClassicSword"
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

	-- Remove EquipFishingRod script if present (handled by spawner now)
	local equipScript = clone:FindFirstChild("EquipFishingRod")
	if equipScript then equipScript:Destroy() end

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

	local configs = clone:FindFirstChild("Configurations")
	if configs then
		local canRespawn = configs:FindFirstChild("CanRespawn")
		if canRespawn then canRespawn.Value = false end
	end

	-- Tag BEFORE the script runs (clone.Parent = workspace starts it) so
	-- SearchForTarget sees the mercenary role on its very first tick.
	CollectionService:AddTag(clone, "SpawnedMercenary")

	local spawnCF = hrp.CFrame * CFrame.new(0, 0, -8)
	clone:PivotTo(spawnCF)
	clone.Parent = workspace

	clone:SetAttribute("OwnerUserId", player.UserId)
	clone:SetAttribute("MercName", mercName)
	clone:SetAttribute("EquippedWeapon", equippedWeapon or "Sword")

	-- Track active mercenary
	if not activeMercs[player] then
		activeMercs[player] = {}
	end
	activeMercs[player][mercName] = clone
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
