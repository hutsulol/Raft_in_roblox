local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local rs = game:GetService("ReplicatedStorage")

local CLICKS_TO_COLLECT = 5
local LIFETIME = 120
local AREA_SIZE = 25
local MAX_PER_AREA = 25

-- Per-resource click overrides (default = CLICKS_TO_COLLECT)
local CLICKS_BY_TYPE = {
	Leaves = 3,
}

local collectEvent = rs:FindFirstChild("CollectResource")
if not collectEvent then
	collectEvent = Instance.new("RemoteEvent")
	collectEvent.Name = "CollectResource"
	collectEvent.Parent = rs
end

local collectNotify = rs:FindFirstChild("CollectNotify")
if not collectNotify then
	collectNotify = Instance.new("RemoteEvent")
	collectNotify.Name = "CollectNotify"
	collectNotify.Parent = rs
end

local inventoryEvent = rs:FindFirstChild("InventoryUpdate")
if not inventoryEvent then
	inventoryEvent = Instance.new("RemoteEvent")
	inventoryEvent.Name = "InventoryUpdate"
	inventoryEvent.Parent = rs
end

local _G_Inventories = {}
_G.GetInventory = function(player)
	if not _G_Inventories[player] then
		_G_Inventories[player] = {Log = 0, Plastic = 0}
	end
	-- Ensure fields exist for old inventories
	if not _G_Inventories[player].Plastic then
		_G_Inventories[player].Plastic = 0
	end
	if not _G_Inventories[player].Stone then
		_G_Inventories[player].Stone = 0
	end
	if not _G_Inventories[player].Plank then
		_G_Inventories[player].Plank = 0
	end
	if not _G_Inventories[player].Leaves then
		_G_Inventories[player].Leaves = 0
	end
	if not _G_Inventories[player].Rope then
		_G_Inventories[player].Rope = 0
	end
	if not _G_Inventories[player].Sand then
		_G_Inventories[player].Sand = 0
	end
	if not _G_Inventories[player].Clay then
		_G_Inventories[player].Clay = 0
	end
	if not _G_Inventories[player].Wet_Brick then
		_G_Inventories[player].Wet_Brick = 0
	end
	if not _G_Inventories[player].Dry_Brick then
		_G_Inventories[player].Dry_Brick = 0
	end
	-- Fish species (ReplicatedStorage.Fish). They're stored as stackable
	-- resources so the player can catch, drop, and pick them back up.
	local fishSpecies = {
		"Blue_Fish", "Carp_Fish", "Fish_Bones", "Foil_Fish",
		"Jelly_Fish", "Legendary_Fish", "Seabass_Fish", "Tilapia_Fish",
	}
	for _, species in fishSpecies do
		if not _G_Inventories[player][species] then
			_G_Inventories[player][species] = 0
		end
	end
	return _G_Inventories[player]
end

_G.SendInventory = function(player)
	inventoryEvent:FireClient(player, _G.GetInventory(player))
end

local clickCounts = {}

-- Spawn cycle counter for different spawn rates
local spawnCycle = 0

local function getBoat()
	return workspace:FindFirstChild("Raft")
end

local function getResourceFromPart(part)
	if CollectionService:HasTag(part, "Resource") then
		return part
	end

	local model = part:FindFirstAncestorOfClass("Model")
	if model and CollectionService:HasTag(model, "Resource") then
		return model
	end

	return nil
end

Players.PlayerRemoving:Connect(function(player)
	_G_Inventories[player] = nil
end)

collectEvent.OnServerEvent:Connect(function(player, targetPart)
	if typeof(targetPart) ~= "Instance" then return end
	if not targetPart:IsDescendantOf(workspace) then return end

	local resource = getResourceFromPart(targetPart)
	if not resource then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local resourcePos
	if resource:IsA("Model") then
		resourcePos = resource:GetPivot().Position
	else
		resourcePos = resource.Position
	end

	local dist = (char.HumanoidRootPart.Position - resourcePos).Magnitude
	if dist > 50 then return end

	if not clickCounts[resource] then
		clickCounts[resource] = {}
	end

	if not clickCounts[resource][player] then
		clickCounts[resource][player] = 0
	end

	clickCounts[resource][player] = clickCounts[resource][player] + 1
	local clicks = clickCounts[resource][player]

	local resTypeForClicks = resource:GetAttribute("ResourceType") or "Log"
	local clicksNeeded = CLICKS_BY_TYPE[resTypeForClicks] or CLICKS_TO_COLLECT

	collectNotify:FireClient(player, "progress", resource, clicks, clicksNeeded)

	if clicks >= clicksNeeded then
		clickCounts[resource] = nil
		local inv = _G.GetInventory(player)

		local resType = resource:GetAttribute("ResourceType") or "Log"
		local resAmount = resource:GetAttribute("ResourceAmount") or 1

		inv[resType] = (inv[resType] or 0) + resAmount
		collectNotify:FireClient(player, "collected", resource, resType, resAmount)
		_G.SendInventory(player)

		-- Play the breaking SFX for the collected resource.
		--
		-- Leaves and Log pack their Sound inside the resource template
		-- (Ruin_Leaves, Wood Break), so we yank the Sound out to workspace
		-- before destroying the resource — otherwise the Destroy below would
		-- take the Sound with it and you'd hear nothing.
		--
		-- The Plastic Break sound lives in SoundService (global, not stored
		-- inside any resource model), so we clone it and play the clone so
		-- rapid-fire collections don't restart a single shared instance.
		if resType == "Leaves" then
			local ruinSound = resource:FindFirstChild("Ruin_Leaves", true)
			if ruinSound and ruinSound:IsA("Sound") then
				ruinSound.Parent = workspace
				ruinSound:Play()
				Debris:AddItem(ruinSound, 5)
			end
		elseif resType == "Log" then
			local woodBreak = resource:FindFirstChild("Wood Break", true)
			if woodBreak and woodBreak:IsA("Sound") then
				woodBreak.Parent = workspace
				woodBreak:Play()
				Debris:AddItem(woodBreak, 5)
			end
		elseif resType == "Plastic" then
			local plasticBreak = SoundService:FindFirstChild("Plastic Break")
			if plasticBreak and plasticBreak:IsA("Sound") then
				local clone = plasticBreak:Clone()
				clone.Parent = SoundService
				clone:Play()
				Debris:AddItem(clone, 5)
			end
		end

		resource:Destroy()
	end
end)

local function spawnResource(templateName, resourceType, resourceAmount, boat)
	local root = boat.PrimaryPart
	local waterY = root.Position.Y
	-- Use raft's actual movement direction so resources always spawn ahead
	local velocity = root.AssemblyLinearVelocity
	local flatVel = Vector3.new(velocity.X, 0, velocity.Z)
	local forward
	if flatVel.Magnitude > 0.5 then
		forward = flatVel.Unit
	else
		-- Fallback when raft hasn't started moving yet
		local rawForward = root.CFrame.LookVector
		forward = Vector3.new(rawForward.X, 0, rawForward.Z).Unit
	end
	local spawnPos = Vector3.new(
		root.Position.X + forward.X * math.random(300, 450) + math.random(-75, 75),
		waterY,
		root.Position.Z + forward.Z * math.random(300, 450) + math.random(-75, 75)
	)

	-- Don't spawn resources on islands
	local islandPositions = _G.IslandPositions or {}
	for _, island in islandPositions do
		local dx = spawnPos.X - island.center.X
		local dz = spawnPos.Z - island.center.Z
		if math.sqrt(dx * dx + dz * dz) < (island.radius or 100) + 20 then
			return
		end
	end

	-- Check density in the area around the spawn position
	local nearby = 0
	for _, res in CollectionService:GetTagged("Resource") do
		local resPos
		if res:IsA("Model") then
			resPos = res:GetPivot().Position
		else
			resPos = res.Position
		end
		if math.abs(resPos.X - spawnPos.X) < AREA_SIZE / 2 and math.abs(resPos.Z - spawnPos.Z) < AREA_SIZE / 2 then
			nearby = nearby + 1
		end
	end
	if nearby >= MAX_PER_AREA then return end

	local template = rs:FindFirstChild(templateName)
	if not template then
		-- Case-insensitive fallback in case the model was renamed
		local lower = string.lower(templateName)
		for _, child in rs:GetChildren() do
			if string.lower(child.Name) == lower then
				template = child
				break
			end
		end
	end
	if not template then
		warn("[ResourceSpawner] template not found: " .. templateName)
		return
	end
	local clone = template:Clone()

	if not clone.PrimaryPart then
		local first = clone:FindFirstChildWhichIsA("BasePart", true)
		if first then
			clone.PrimaryPart = first
		end
	end

	-- Align the model's pivot with its PrimaryPart so PivotTo positions the
	-- visible part exactly where we want it (otherwise WorldPivot can be at
	-- the bounding box center and the part ends up far from the spawn point).
	if clone.PrimaryPart then
		clone.WorldPivot = clone.PrimaryPart.CFrame
	end

	clone:SetAttribute("ResourceType", resourceType)
	clone:SetAttribute("ResourceAmount", resourceAmount)

	clone:PivotTo(CFrame.new(spawnPos))
	clone.Parent = workspace

	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part:SetNetworkOwner(nil)
		end
	end

	CollectionService:AddTag(clone, "Resource")

	task.delay(LIFETIME, function()
		if clone and clone.Parent then
			clickCounts[clone] = nil
			clone:Destroy()
		end
	end)
end

while true do
	task.wait(3)

	local boat = getBoat()
	if not boat then continue end

	spawnCycle = spawnCycle + 1

	-- Log: every cycle
	spawnResource("Log", "Log", 1, boat)

	-- plastic_bottle: every 2nd cycle (half as often)
	if spawnCycle % 2 == 0 then
		spawnResource("plastic_bottle", "Plastic", 1, boat)
	end

	-- plastic_canister: every 4th cycle (quarter as often)
	if spawnCycle % 4 == 0 then
		spawnResource("plastic_canister", "Plastic", 3, boat)
	end

	-- Leaves: every cycle (same chance as Log)
	spawnResource("leaves", "Leaves", 1, boat)

end
