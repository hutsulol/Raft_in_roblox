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

	-- Read equipped weapon and swap if not default (Sword/ClassicSword)
	local mercEntry = folder:FindFirstChild(mercName)
	local equippedWeapon = mercEntry and mercEntry:GetAttribute("EquippedWeapon")

	if equippedWeapon and equippedWeapon ~= "Sword" then
		-- Remove existing weapon tools from clone
		for _, child in clone:GetChildren() do
			if child:IsA("Tool") then
				child:Destroy()
			end
		end

		-- Clone the selected weapon from ReplicatedStorage
		local weaponTemplate = ReplicatedStorage:FindFirstChild(equippedWeapon)
			or ReplicatedStorage:FindFirstChild(equippedWeapon, true)
		if weaponTemplate then
			local wArchivable = weaponTemplate.Archivable
			weaponTemplate.Archivable = true
			local weaponClone = weaponTemplate:Clone()
			weaponTemplate.Archivable = wArchivable
			-- Parent to character — Humanoid auto-equips it
			local hum = clone:FindFirstChildOfClass("Humanoid")
			if hum then
				weaponClone.Parent = clone
			end
		end
	end

	-- Remove EquipFishingRod script if present (handled by spawner now)
	local equipScript = clone:FindFirstChild("EquipFishingRod")
	if equipScript then equipScript:Destroy() end

	-- Remove Zombie AI so the mercenary doesn't attack the player
	local zombieScript = clone:FindFirstChild("Zombie") or clone:FindFirstChild("MonsterScript")
	if zombieScript then zombieScript:Destroy() end

	-- Prepare any fishing rod tool on the mercenary (replaces what EquipFishingRod did)
	for _, child in clone:GetChildren() do
		if child:IsA("Tool") and (child.Name:find("FishingRod")) then
			-- Disable built-in rod scripts and rope so they don't interfere
			for _, desc in child:GetDescendants() do
				if desc:IsA("Script") or desc:IsA("LocalScript") then
					desc.Enabled = false
				elseif desc:IsA("RopeConstraint") then
					desc.Enabled = false
					desc.Visible = false
				end
			end
			child.CanBeDropped = false
			-- NPC fishing stance grip
			child.Grip = CFrame.new(0.1, -0.9, -0.25)
				* CFrame.Angles(math.rad(15), math.rad(-90), math.rad(180))
			-- Stabilize Pointer (bobber) by welding it to Handle
			local handle = child:FindFirstChild("Handle")
			local pointer = child:FindFirstChild("Pointer")
			if handle and pointer and handle:IsA("BasePart") and pointer:IsA("BasePart") then
				pointer.Anchored = false
				pointer.Massless = true
				pointer.CanCollide = false
				pointer.CanTouch = false
				pointer.CanQuery = false
				pointer.CFrame = handle.CFrame
				local weld = Instance.new("WeldConstraint")
				weld.Name = "NPCPointerWeld"
				weld.Part0 = handle
				weld.Part1 = pointer
				weld.Parent = pointer
			end
			break
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
