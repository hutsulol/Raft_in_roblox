-- MercenaryMovement.server.lua
-- Handles movement and fishing commands for spawned mercenaries.
-- The client sends a raft part + local offset for walking, and a water
-- position for casting. After the pirate arrives, it fishes automatically.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local commandEvent = Instance.new("RemoteEvent")
commandEvent.Name = "MercenaryCommand"
commandEvent.Parent = ReplicatedStorage

-- Active task tokens per mercenary (cancel previous walk/fish on new command)
local activeTokens = {} -- [model] = token

-- ── Catch pools (same as FishingRod Script) ─────────────────────────────

local CATCH_FISH = {
	{ inventoryName = "Blue_Fish",      templateName = "Blue Fish",      weight = 3 },
	{ inventoryName = "Carp_Fish",      templateName = "Carp Fish",      weight = 3 },
	{ inventoryName = "Tilapia_Fish",   templateName = "Tilapia Fish",   weight = 3 },
	{ inventoryName = "Seabass_Fish",   templateName = "Seabass Fish",   weight = 2 },
	{ inventoryName = "Foil_Fish",      templateName = "Foil Fish",      weight = 2 },
	{ inventoryName = "Jelly_Fish",     templateName = "Jelly Fish",     weight = 2 },
	{ inventoryName = "Fish_Bones",     templateName = "Fish Bones",     weight = 2 },
	{ inventoryName = "Legendary_Fish", templateName = "Legendary Fish", weight = 1 },
}

local CATCH_ITEMS = {
	{ inventoryName = "Log", templateName = "Log", weight = 1 },
}

local FISH_BITE_CHANCE = 0.5

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
	local category = preferFish and "fish" or "item"
	if not pick then
		local fallback = preferFish and CATCH_ITEMS or CATCH_FISH
		pick = pickFromPool(fallback)
		category = preferFish and "item" or "fish"
	end
	if not pick then return nil end
	return {
		inventoryName = pick.inventoryName,
		templateName = pick.templateName,
		category = category,
	}
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

local function grantCatchToPlayer(player, resourceName)
	if not player then return end
	if _G.GetInventory then
		local inv = _G.GetInventory(player)
		if inv then
			inv[resourceName] = (inv[resourceName] or 0) + 1
			if _G.SendInventory then
				_G.SendInventory(player)
			end
			if _G.OnQuestResource then
				_G.OnQuestResource(player, resourceName, 1)
			end
		end
	end
end

-- ── Find the fishing rod tool on the mercenary ──────────────────────────

local function findFishingRod(model)
	for _, child in model:GetChildren() do
		if child:IsA("Tool") and (
			child.Name == "FishingRod"
			or child.Name == "FishingRod ( Tool )"
			or child.Name:find("FishingRod")
		) then
			return child
		end
	end
	return nil
end

-- Disable the tool's built-in scripts and rope so they don't conflict
-- with our NPC fishing logic, but keep Pointer and Device accessible.
local function prepareRodForNPC(rod)
	for _, desc in rod:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc.Enabled = false
		elseif desc:IsA("RopeConstraint") then
			desc.Enabled = false
			desc.Visible = false
		end
	end
end

-- ── Spawn hooked catch prop ─────────────────────────────────────────────

local function spawnHookedProp(templateName, position)
	local template = ReplicatedStorage:FindFirstChild(templateName)
	if not template then
		template = ReplicatedStorage:FindFirstChild(templateName, true)
	end
	if not template then return nil end

	local clone = template:Clone()
	if clone:IsA("Model") and not clone.PrimaryPart then
		local first = clone:FindFirstChildWhichIsA("BasePart")
		if first then clone.PrimaryPart = first end
	end

	if clone:IsA("Model") then
		clone:PivotTo(CFrame.new(position))
	elseif clone:IsA("BasePart") then
		clone.CFrame = CFrame.new(position)
	end

	local function neuter(part)
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
	end
	if clone:IsA("BasePart") then neuter(clone) end
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then neuter(part) end
	end

	clone.Parent = workspace
	return clone
end

-- ── NPC fishing cycle ───────────────────────────────────────────────────

local function runFishingLoop(model, token, castTarget, ownerUserId)
	local rod = findFishingRod(model)
	if not rod then
		warn("[MercenaryMovement] No fishing rod found on", model.Name)
		return
	end

	-- Disable built-in rod scripts so they don't interfere
	prepareRodForNPC(rod)

	local pointer = rod:FindFirstChild("Pointer")
	local device = rod:FindFirstChild("Device") or rod:FindFirstChild("Handle")
	if not pointer then
		warn("[MercenaryMovement] No Pointer found on rod", rod:GetFullName())
		-- List children for debugging
		for _, c in rod:GetChildren() do
			warn("  -", c.Name, c.ClassName)
		end
		return
	end
	if not device then
		warn("[MercenaryMovement] No Device/Handle found on rod")
		return
	end

	-- Ensure pointer is unanchored and detached for casting
	pointer.Anchored = false
	pointer.CanCollide = false

	-- Sounds
	local fishBiteSound = rod:FindFirstChild("Fish Bite")
	local itemBiteSound = rod:FindFirstChild("Item Bite")
	local pickUpSound = rod:FindFirstChild("PickUp")
	local wooshSound = (device:FindFirstChild("woosh"))
		or (rod:FindFirstChild("Handle") and rod.Handle:FindFirstChild("woosh"))

	local player = getPlayerByUserId(ownerUserId)

	while activeTokens[model] == token do
		if not model.Parent then break end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then break end

		-- ── CAST ──
		-- Detach bobber
		local existingWeld = device:FindFirstChild("thing")
		if existingWeld then existingWeld:Destroy() end

		local startPos = device.Position
		local arcHeight = math.max((castTarget - startPos).Magnitude * 0.15, 3)
		local flightTime = math.clamp((castTarget - startPos).Magnitude / 40, 0.25, 1.5)

		if wooshSound then wooshSound:Play() end

		pointer.Anchored = true
		local launchTick = tick()
		while activeTokens[model] == token do
			local elapsed = tick() - launchTick
			local t = elapsed / flightTime
			if t >= 1 then break end
			local linear = startPos:Lerp(castTarget, t)
			local arc = Vector3.new(0, arcHeight * math.sin(t * math.pi), 0)
			pointer.CFrame = CFrame.new(linear + arc)
			RunService.Heartbeat:Wait()
		end
		if activeTokens[model] ~= token then break end

		-- Land on water
		pointer.CFrame = CFrame.new(castTarget)
		pointer.Anchored = true

		-- ── WAIT FOR BITE ──
		local biteDelay = math.random(2, 4)
		local waited = 0
		while waited < biteDelay and activeTokens[model] == token do
			RunService.Heartbeat:Wait()
			waited = waited + RunService.Heartbeat:Wait()
		end
		if activeTokens[model] ~= token then break end

		-- ── BITE ──
		local catchDef = rollCatch()
		local hookedClone = nil

		if catchDef then
			-- Spawn visual catch at bobber
			hookedClone = spawnHookedProp(catchDef.templateName, pointer.Position)
			if hookedClone then
				local primaryPart = hookedClone:IsA("BasePart") and hookedClone or hookedClone.PrimaryPart
				if primaryPart then
					local weld = Instance.new("WeldConstraint")
					weld.Name = "HookWeld"
					weld.Part0 = pointer
					weld.Part1 = primaryPart
					weld.Parent = primaryPart
				end
			end

			-- Bite sound
			if catchDef.category == "fish" then
				if fishBiteSound then fishBiteSound:Play() end
			else
				if itemBiteSound then itemBiteSound:Play() end
			end
		end

		-- Short pause before auto-reel
		local reelDelay = math.random(1, 2)
		waited = 0
		while waited < reelDelay and activeTokens[model] == token do
			RunService.Heartbeat:Wait()
			waited = waited + RunService.Heartbeat:Wait()
		end
		if activeTokens[model] ~= token then
			if hookedClone and hookedClone.Parent then hookedClone:Destroy() end
			break
		end

		-- ── REEL IN ──
		local reelStart = pointer.Position
		local returnTime = 0.7
		local reelArc = 4
		local reelTick = tick()

		while activeTokens[model] == token do
			local elapsed = tick() - reelTick
			local t = elapsed / returnTime
			if t >= 1 then break end
			local endPos = device.Position
			local linear = reelStart:Lerp(endPos, t)
			local arc = Vector3.new(0, reelArc * math.sin(t * math.pi), 0)
			pointer.CFrame = CFrame.new(linear + arc)
			RunService.Heartbeat:Wait()
		end
		if activeTokens[model] ~= token then
			if hookedClone and hookedClone.Parent then hookedClone:Destroy() end
			break
		end

		-- ── GRANT CATCH ──
		if catchDef then
			player = getPlayerByUserId(ownerUserId) -- refresh in case of reconnect
			grantCatchToPlayer(player, catchDef.inventoryName)
			if pickUpSound then pickUpSound:Play() end
		end

		-- Clean up catch prop
		if hookedClone and hookedClone.Parent then
			hookedClone:Destroy()
		end

		-- Re-attach bobber to rod
		pointer.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Name = "thing"
		pointer.CFrame = device.CFrame
		weld.Part0 = pointer
		weld.Part1 = device
		weld.Parent = device

		-- Brief pause before next cast
		task.wait(1)
	end

	-- Ensure bobber is attached when loop ends
	if pointer and pointer.Parent and device and device.Parent then
		pointer.Anchored = false
		local w = device:FindFirstChild("thing")
		if not w then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "thing"
			pointer.CFrame = device.CFrame
			weld.Part0 = pointer
			weld.Part1 = device
			weld.Parent = device
		end
	end
end

-- ── Walk then fish ──────────────────────────────────────────────────────

local function walkThenFish(model, raftPart, localOffset, castTarget, ownerUserId)
	activeTokens[model] = nil

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local token = {}
	activeTokens[model] = token

	task.spawn(function()
		-- Phase 1: walk to raft point
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

		-- Stop walking
		if humanoid and humanoid.Parent then
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if hrp then
				humanoid:MoveTo(hrp.Position)
			end
		end

		-- Face the cast target
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if hrp and castTarget then
			local lookDir = (castTarget - hrp.Position) * Vector3.new(1, 0, 1)
			if lookDir.Magnitude > 0.1 then
				hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + lookDir)
			end
		end

		task.wait(0.3)

		-- Phase 2: fish in a loop
		if activeTokens[model] == token then
			runFishingLoop(model, token, castTarget, ownerUserId)
		end

		if activeTokens[model] == token then
			activeTokens[model] = nil
		end
	end)
end

-- ── Remote handler ──────────────────────────────────────────────────────

commandEvent.OnServerEvent:Connect(function(player, action, mercName, raftPart, localOffset, castTarget)
	if typeof(action) ~= "string" then return end

	if action == "setFishingLocation" then
		if typeof(mercName) ~= "string" then return end
		if typeof(raftPart) ~= "Instance" or not raftPart:IsA("BasePart") then return end
		if typeof(localOffset) ~= "Vector3" then return end
		if typeof(castTarget) ~= "Vector3" then return end

		local raft = workspace:FindFirstChild("Raft")
		if not raft or not raftPart:IsDescendantOf(raft) then return end

		local model = findMercenary(player, mercName)
		if not model then return end

		walkThenFish(model, raftPart, localOffset, castTarget, player.UserId)
	end
end)

CollectionService:GetInstanceRemovedSignal("SpawnedMercenary"):Connect(function(model)
	activeTokens[model] = nil
end)
