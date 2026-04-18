-- MercenaryMovement.server.lua
-- Handles movement commands for spawned mercenaries and the automatic
-- fishing catch loop for FishingRod mercenaries.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local commandEvent = Instance.new("RemoteEvent")
commandEvent.Name = "MercenaryCommand"
commandEvent.Parent = ReplicatedStorage

-- Remote used to tell the owning client about a catch (for the +1 popup).
local catchNotifyEvent = Instance.new("RemoteEvent")
catchNotifyEvent.Name = "MercFishingCatch"
catchNotifyEvent.Parent = ReplicatedStorage

local activeTokens = {} -- [model] = token

-- ── Catch pools (same as the player's FishingRod) ──────────────────────

local CATCH_FISH = {
	{ inventoryName = "Blue_Fish",      weight = 3 },
	{ inventoryName = "Carp_Fish",      weight = 3 },
	{ inventoryName = "Tilapia_Fish",   weight = 3 },
	{ inventoryName = "Seabass_Fish",   weight = 2 },
	{ inventoryName = "Foil_Fish",      weight = 2 },
	{ inventoryName = "Jelly_Fish",     weight = 2 },
	{ inventoryName = "Fish_Bones",     weight = 2 },
	{ inventoryName = "Legendary_Fish", weight = 1 },
}

local CATCH_ITEMS = {
	{ inventoryName = "Log", weight = 1 },
}

local FISH_BITE_CHANCE = 0.5
local CATCH_INTERVAL = 60 -- seconds between catches (matches animation cycle)

-- Slot counts per backpack type
local BACKPACK_SLOT_COUNTS = {
	Backpack = 6,
	BackPack_lvl2 = 9,
}
local DEFAULT_SLOTS = 6

local function getSlotCount(mercEntry)
	local bp = mercEntry:GetAttribute("EquippedBackpack") or ""
	return BACKPACK_SLOT_COUNTS[bp] or DEFAULT_SLOTS
end

local function pickFromPool(pool)
	local total = 0
	for _, entry in pool do total = total + (entry.weight or 0) end
	if total <= 0 then return nil end
	local roll = math.random() * total
	local acc = 0
	for _, entry in pool do
		acc = acc + (entry.weight or 0)
		if roll <= acc then return entry end
	end
	return pool[#pool]
end

local function rollCatch()
	local preferFish = math.random() < FISH_BITE_CHANCE
	local primary = preferFish and CATCH_FISH or CATCH_ITEMS
	local pick = pickFromPool(primary)
	if not pick then
		local fallback = preferFish and CATCH_ITEMS or CATCH_FISH
		pick = pickFromPool(fallback)
	end
	return pick
end

-- ── Helpers ─────────────────────────────────────────────────────────────

local function findMercenary(player, mercName)
	for _, model in CollectionService:GetTagged("SpawnedMercenary") do
		if model:GetAttribute("OwnerUserId") == player.UserId
			and model:GetAttribute("MercName") == mercName
			and model.Parent then
			return model
		end
	end
	return nil
end

local function getPlayerByUserId(userId)
	for _, p in Players:GetPlayers() do
		if p.UserId == userId then return p end
	end
	return nil
end

-- ── Mercenary backpack inventory ────────────────────────────────────────

local function addToMercBackpack(mercEntry, itemName)
	local slots = getSlotCount(mercEntry)
	-- Try to stack on an existing slot with the same item
	for i = 1, slots do
		local name = mercEntry:GetAttribute("Slot" .. i .. "_Name")
		if name == itemName then
			local count = mercEntry:GetAttribute("Slot" .. i .. "_Count") or 0
			mercEntry:SetAttribute("Slot" .. i .. "_Count", count + 1)
			return true
		end
	end
	-- Find an empty slot
	for i = 1, slots do
		local name = mercEntry:GetAttribute("Slot" .. i .. "_Name")
		if name == nil or name == "" then
			mercEntry:SetAttribute("Slot" .. i .. "_Name", itemName)
			mercEntry:SetAttribute("Slot" .. i .. "_Count", 1)
			return true
		end
	end
	return false -- backpack is full
end

-- ── Fishing catch loop ─────────────────────────────────────────────────

local function startFishingLoop(model)
	local ownerUserId = model:GetAttribute("OwnerUserId")
	local mercName = model:GetAttribute("MercName")
	if not ownerUserId or not mercName then return end

	task.spawn(function()
		while model.Parent do
			task.wait(CATCH_INTERVAL)
			if not model.Parent then break end

			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then break end

			-- Roll a catch
			local catch = rollCatch()
			if not catch then continue end

			-- Find the owning player and merc entry
			local player = getPlayerByUserId(ownerUserId)
			if not player then continue end
			local mercFolder = player:FindFirstChild("Mercenaries")
			local mercEntry = mercFolder and mercFolder:FindFirstChild(mercName)
			if not mercEntry then continue end

			-- Only deposit into backpack if one is equipped
			local equippedBp = mercEntry:GetAttribute("EquippedBackpack")
			if not equippedBp or equippedBp == "" then continue end

			-- Add to the mercenary's backpack
			local added = addToMercBackpack(mercEntry, catch.inventoryName)
			if added then
				-- Notify the client so it can show the +1 popup and sound
				catchNotifyEvent:FireClient(player, model, catch.inventoryName)
			else
				-- Backpack is full — tell the client so it can show a warning
				catchNotifyEvent:FireClient(player, model, "__BACKPACK_FULL__")
			end
		end
	end)
end

-- Start the fishing loop for any FishingRod merc that spawns
CollectionService:GetInstanceAddedSignal("SpawnedMercenary"):Connect(function(model)
	-- Wait a frame for attributes to be set by the spawner
	task.defer(function()
		local weapon = model:GetAttribute("EquippedWeapon")
		if weapon == "FishingRod" then
			startFishingLoop(model)
		end
	end)
end)

-- Also check mercs that are already tagged (in case this script loads late)
for _, model in CollectionService:GetTagged("SpawnedMercenary") do
	task.defer(function()
		local weapon = model:GetAttribute("EquippedWeapon")
		if weapon == "FishingRod" then
			startFishingLoop(model)
		end
	end)
end

-- ── Rod swap ────────────────────────────────────────────────────────────

local function swapToRealRod(model)
	for _, child in model:GetChildren() do
		if child:IsA("Tool") then
			child:Destroy()
		end
	end
	local realRod = ReplicatedStorage:FindFirstChild("FishingRod_ForPirate", true)
	if realRod then
		local archivable = realRod.Archivable
		realRod.Archivable = true
		local clone = realRod:Clone()
		realRod.Archivable = archivable
		clone.Parent = model
	end
end

-- ── Walk to position ────────────────────────────────────────────────────

local function walkToPosition(model, raftPart, localOffset)
	activeTokens[model] = nil

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local token = {}
	activeTokens[model] = token

	task.spawn(function()
		while activeTokens[model] == token do
			if not humanoid or not humanoid.Parent or humanoid.Health <= 0 then return end
			if not raftPart or not raftPart.Parent then return end

			local currentHRP = model:FindFirstChild("HumanoidRootPart")
			if not currentHRP then return end

			local worldTarget = raftPart.CFrame:PointToWorldSpace(localOffset)
			local dist = (currentHRP.Position - worldTarget).Magnitude

			if dist < 2 then break end

			humanoid:MoveTo(worldTarget)
			task.wait(0.15)
		end

		if activeTokens[model] ~= token then return end

		if humanoid and humanoid.Parent then
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if hrp then
				humanoid:MoveTo(hrp.Position)
			end
		end

		local equippedWeapon = model:GetAttribute("EquippedWeapon") or "Sword"
		if equippedWeapon == "FishingRod" then
			swapToRealRod(model)
		end

		if activeTokens[model] == token then
			activeTokens[model] = nil
		end
	end)
end

-- ── Harvest floating resources ─────────────────────────────────────────

local HARVEST_RADIUS = 50   -- matches player pickup radius (ResourceSpawner)
local HARVEST_DURATION = 15 -- seconds per resource
local HARVEST_TYPES = { Log = true, Plastic = true, Leaves = true }
local HIT_ANIM_ID = "rbxassetid://73185099694139"

local function getHitAnimation(model)
	local animate = model:FindFirstChild("Animate")
	if animate then
		local hit = animate:FindFirstChild("hit")
		if hit then
			local hitAnim = hit:FindFirstChild("HitAnim")
			if hitAnim and hitAnim:IsA("Animation") then
				return hitAnim
			end
		end
	end
	local fallback = Instance.new("Animation")
	fallback.AnimationId = HIT_ANIM_ID
	return fallback
end

local function getResourcePosition(resource)
	if resource:IsA("Model") then
		return resource:GetPivot().Position
	end
	return resource.Position
end

local function findNearestFloatingResource(position, radius)
	local closest, closestDist = nil, radius
	for _, resource in CollectionService:GetTagged("Resource") do
		if resource.Parent then
			local resType = resource:GetAttribute("ResourceType")
			local hp = resource:GetAttribute("ResourceHP") or 0
			if HARVEST_TYPES[resType] and hp > 0 then
				local d = (getResourcePosition(resource) - position).Magnitude
				if d < closestDist then
					closest, closestDist = resource, d
				end
			end
		end
	end
	return closest
end

local function startHarvestLoop(model, raftPart, localOffset)
	activeTokens[model] = nil
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local hitTrack
	local ok, err = pcall(function()
		hitTrack = animator:LoadAnimation(getHitAnimation(model))
		hitTrack.Priority = Enum.AnimationPriority.Action3
		hitTrack.Looped = true
	end)
	if not ok then
		warn("[MercHarvest] Failed to load HitAnim: " .. tostring(err))
	end

	local function playHit()
		if hitTrack and not hitTrack.IsPlaying then hitTrack:Play() end
	end
	local function stopHit()
		if hitTrack and hitTrack.IsPlaying then hitTrack:Stop() end
	end

	local token = {}
	activeTokens[model] = token

	task.spawn(function()
		-- Phase 1: walk to the placement point
		while activeTokens[model] == token do
			if not humanoid.Parent or humanoid.Health <= 0 then return end
			if not raftPart or not raftPart.Parent then return end
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			local worldTarget = raftPart.CFrame:PointToWorldSpace(localOffset)
			if (hrp.Position - worldTarget).Magnitude < 2 then break end
			humanoid:MoveTo(worldTarget)
			task.wait(0.15)
		end

		print("[MercHarvest] arrived at harvest point, entering scan loop")

		-- Phase 2: stand still and harvest
		while activeTokens[model] == token do
			if not humanoid.Parent or humanoid.Health <= 0 then break end
			if not raftPart or not raftPart.Parent then break end
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if not hrp then break end

			humanoid:MoveTo(hrp.Position)

			local ownerUserId = model:GetAttribute("OwnerUserId")
			local mercName = model:GetAttribute("MercName")
			local owner = getPlayerByUserId(ownerUserId)
			if not owner then break end
			local mercFolder = owner:FindFirstChild("Mercenaries")
			local mercEntry = mercFolder and mercFolder:FindFirstChild(mercName)
			if not mercEntry then break end

			local resource = findNearestFloatingResource(hrp.Position, HARVEST_RADIUS)
			if not resource then
				stopHit()
				task.wait(2)
				continue
			end

			print(string.format(
				"[MercHarvest] targeting %s at %.1f studs",
				tostring(resource:GetAttribute("ResourceType")),
				(getResourcePosition(resource) - hrp.Position).Magnitude
			))

			-- Face the resource
			local resPos = getResourcePosition(resource)
			hrp.CFrame = CFrame.lookAt(
				hrp.Position,
				Vector3.new(resPos.X, hrp.Position.Y, resPos.Z)
			)

			playHit()

			-- Wait HARVEST_DURATION, with periodic checks
			local elapsed = 0
			while elapsed < HARVEST_DURATION and activeTokens[model] == token do
				task.wait(0.5)
				elapsed = elapsed + 0.5
				if not resource.Parent then break end
				if not humanoid.Parent or humanoid.Health <= 0 then break end
			end

			if activeTokens[model] ~= token then break end
			if not resource.Parent then continue end
			if not humanoid.Parent or humanoid.Health <= 0 then break end

			local resType = resource:GetAttribute("ResourceType") or ""
			local resAmount = resource:GetAttribute("ResourceAmount") or 1
			if not HARVEST_TYPES[resType] then continue end

			local delivered = 0
			for _ = 1, resAmount do
				if addToMercBackpack(mercEntry, resType) then
					delivered = delivered + 1
				else
					break
				end
			end

			if delivered > 0 then
				print(string.format("[MercHarvest] harvested %dx %s", delivered, resType))
				catchNotifyEvent:FireClient(owner, model, resType)
				resource:Destroy()
			else
				catchNotifyEvent:FireClient(owner, model, "__BACKPACK_FULL__")
				stopHit()
				task.wait(2)
			end
		end

		stopHit()
		if activeTokens[model] == token then
			activeTokens[model] = nil
		end
	end)
end

-- ── Remote handler ──────────────────────────────────────────────────────

commandEvent.OnServerEvent:Connect(function(player, action, mercName, raftPart, localOffset)
	if typeof(action) ~= "string" then return end

	if action == "setFishingLocation" then
		if typeof(mercName) ~= "string" then return end
		if typeof(raftPart) ~= "Instance" or not raftPart:IsA("BasePart") then return end
		if typeof(localOffset) ~= "Vector3" then return end

		local raft = workspace:FindFirstChild("Raft")
		if not raft or not raftPart:IsDescendantOf(raft) then return end

		local model = findMercenary(player, mercName)
		if not model then return end

		walkToPosition(model, raftPart, localOffset)

	elseif action == "setHarvestLocation" then
		if typeof(mercName) ~= "string" then return end
		if typeof(raftPart) ~= "Instance" or not raftPart:IsA("BasePart") then return end
		if typeof(localOffset) ~= "Vector3" then return end

		local raft = workspace:FindFirstChild("Raft")
		if not raft or not raftPart:IsDescendantOf(raft) then return end

		local model = findMercenary(player, mercName)
		if not model then return end

		startHarvestLoop(model, raftPart, localOffset)
	end
end)

CollectionService:GetInstanceRemovedSignal("SpawnedMercenary"):Connect(function(model)
	activeTokens[model] = nil
end)
