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

	-- Remove Zombie AI so the mercenary doesn't attack the player.
	-- Match any of the names the script has shipped under over time
	-- ("Zombie", "MonsterScript", "ZombieScript") so the restored pirate
	-- template doesn't keep its hostile AI after being recruited.
	for _, child in clone:GetChildren() do
		if (child:IsA("Script") or child:IsA("LocalScript"))
			and (child.Name == "Zombie"
				or child.Name == "ZombieScript"
				or child.Name == "MonsterScript"
				or child.Name == "Ragdoller") then
			child:Destroy()
		end
	end

	local spawnCF = hrp.CFrame * CFrame.new(0, 0, -8)
	clone:PivotTo(spawnCF)
	clone.Parent = workspace

	-- Tag for identification by other scripts (movement, client hover)
	CollectionService:AddTag(clone, "SpawnedMercenary")
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
