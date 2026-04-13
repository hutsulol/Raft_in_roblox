-- MercenaryMovement.server.lua
-- Handles movement and fishing commands for spawned mercenaries.
-- The client sends a raft part + local offset for walking, and a water
-- position for casting. After the pirate arrives, it fishes automatically
-- using the actual fishing rod tool's Pointer (bobber) and Device (rod tip).
-- Falls back to a standalone bobber if the rod parts are missing.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local commandEvent = Instance.new("RemoteEvent")
commandEvent.Name = "MercenaryCommand"
commandEvent.Parent = ReplicatedStorage

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

local function playSound(sound)
	if sound then sound:Play() end
end

-- Fallback: approximate rod tip from the NPC's right hand
local function getRodTipPosition(model)
	local rightArm = model:FindFirstChild("Right Arm")
		or model:FindFirstChild("RightHand")
		or model:FindFirstChild("RightLowerArm")
	if rightArm then
		return rightArm.Position + Vector3.new(0, 3, 0)
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp then
		return hrp.Position + hrp.CFrame.LookVector * 2 + Vector3.new(0, 3, 0)
	end
	return model:GetPivot().Position + Vector3.new(0, 5, 0)
end

-- ── Fishing rod management ──────────────────────────────────────────────

local function findFishingRod(model)
	for _, child in model:GetChildren() do
		if child:IsA("Tool") and (
			child.Name == "FishingRod ( Tool )"
			or child.Name == "FishingRod"
			or child.Name:find("FishingRod")
		) then
			return child
		end
	end
	-- Check descendants (tool might be nested)
	for _, desc in model:GetDescendants() do
		if desc:IsA("Tool") and (
			desc.Name == "FishingRod ( Tool )"
			or desc.Name == "FishingRod"
			or desc.Name:find("FishingRod")
		) then
			return desc
		end
	end
	return nil
end

local function prepareRodForNPC(rod)
	for _, desc in rod:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc.Enabled = false
		elseif desc:IsA("RopeConstraint") then
			desc.Enabled = false
			desc.Visible = false
		end
	end
	rod.CanBeDropped = false
	rod.Grip = CFrame.new(0.1, -0.9, -0.25)
		* CFrame.Angles(math.rad(15), math.rad(-90), math.rad(180))
end

local function weldPointerToHandle(pointer, handle)
	local existing = pointer:FindFirstChild("NPCPointerWeld")
	if existing then existing:Destroy() end
	-- Also remove any "thing" weld from the original rod system
	local tool = pointer.Parent
	if tool then
		local device = tool:FindFirstChild("Device")
		if device then
			local thingWeld = device:FindFirstChild("thing")
			if thingWeld then thingWeld:Destroy() end
		end
	end

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

local function detachPointer(pointer)
	local weld = pointer:FindFirstChild("NPCPointerWeld")
	if weld then weld:Destroy() end
	local tool = pointer.Parent
	if tool then
		local device = tool:FindFirstChild("Device")
		if device then
			local thingWeld = device:FindFirstChild("thing")
			if thingWeld then thingWeld:Destroy() end
		end
	end
	pointer.Anchored = true
end

-- ── Spawn hooked catch prop ─────────────────────────────────────────────

local function spawnHookedProp(templateName, bobber)
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
		clone:PivotTo(CFrame.new(bobber.Position))
	elseif clone:IsA("BasePart") then
		clone.CFrame = CFrame.new(bobber.Position)
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

	-- Weld to bobber
	local primaryPart = clone:IsA("BasePart") and clone or clone.PrimaryPart
	if primaryPart then
		local weld = Instance.new("WeldConstraint")
		weld.Name = "HookWeld"
		weld.Part0 = bobber
		weld.Part1 = primaryPart
		weld.Parent = primaryPart
	end

	return clone
end

-- ── Create a standalone bobber (fallback) ───────────────────────────────

local function createBobber()
	local part = Instance.new("Part")
	part.Name = "NPCBobber"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(0.6, 0.6, 0.6)
	part.Color = Color3.fromRGB(200, 40, 40)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Parent = workspace
	return part
end

-- ── Timed wait that checks token ────────────────────────────────────────

local function waitSeconds(model, token, seconds)
	local elapsed = 0
	while elapsed < seconds and activeTokens[model] == token do
		local dt = RunService.Heartbeat:Wait()
		elapsed = elapsed + dt
	end
	return activeTokens[model] == token
end

-- ── NPC fishing cycle ───────────────────────────────────────────────────

local function runFishingLoop(model, token, castTarget, ownerUserId)
	-- Try to find the actual fishing rod and its parts
	local rod = findFishingRod(model)
	local pointer, device, handle
	if rod then
		prepareRodForNPC(rod)
		pointer = rod:FindFirstChild("Pointer")
		device = rod:FindFirstChild("Device")
		handle = rod:FindFirstChild("Handle")
		if pointer and handle then
			weldPointerToHandle(pointer, handle)
		end
	end

	local useRodParts = pointer and (device or handle)
	local bobber

	if useRodParts then
		bobber = pointer
	else
		-- Fallback: standalone bobber
		bobber = createBobber()
		bobber.CFrame = CFrame.new(getRodTipPosition(model))
		bobber.Transparency = 1
	end

	-- Start position source
	local function getStartPos()
		if device and device.Parent then
			return device.Position
		elseif handle and handle.Parent then
			return handle.Position
		end
		return getRodTipPosition(model)
	end

	-- Sounds from the rod
	local wooshSound = handle and handle:FindFirstChild("woosh")
	local fishBiteSound = rod and rod:FindFirstChild("Fish Bite")
	local itemBiteSound = rod and rod:FindFirstChild("Item Bite")
	local pickUpSound = rod and rod:FindFirstChild("PickUp")

	local player = getPlayerByUserId(ownerUserId)

	while activeTokens[model] == token do
		if not model.Parent then break end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then break end

		-- ── CAST: bobber flies from rod tip to water ──
		if useRodParts then
			detachPointer(bobber)
		else
			bobber.Transparency = 0
			bobber.Anchored = true
		end

		local startPos = getStartPos()
		local distance = (castTarget - startPos).Magnitude
		local arcHeight = math.max(distance * 0.15, 3)
		local flightTime = math.clamp(distance / 40, 0.3, 1.5)

		playSound(wooshSound)

		local launchTick = tick()
		while activeTokens[model] == token do
			local elapsed = tick() - launchTick
			local t = elapsed / flightTime
			if t >= 1 then break end
			local linear = startPos:Lerp(castTarget, t)
			local arc = Vector3.new(0, arcHeight * math.sin(t * math.pi), 0)
			bobber.CFrame = CFrame.new(linear + arc)
			RunService.Heartbeat:Wait()
		end
		if activeTokens[model] ~= token then break end

		-- Land on water
		bobber.CFrame = CFrame.new(castTarget)

		-- ── WAIT FOR BITE (2-4 seconds) ──
		if not waitSeconds(model, token, math.random(2, 4)) then break end

		-- ── BITE: roll catch ──
		local catchDef = rollCatch()
		local hookedClone = nil

		if catchDef then
			hookedClone = spawnHookedProp(catchDef.templateName, bobber)
			if catchDef.category == "fish" then
				playSound(fishBiteSound)
			else
				playSound(itemBiteSound)
			end
		end

		-- Brief pause before auto-reel (1-2 seconds)
		if not waitSeconds(model, token, math.random(1, 2)) then
			if hookedClone and hookedClone.Parent then hookedClone:Destroy() end
			break
		end

		-- ── REEL IN: bobber arcs back to rod tip ──
		local reelStart = bobber.Position
		local returnTime = 0.7
		local reelArc = 4
		local reelTick = tick()

		while activeTokens[model] == token do
			local elapsed = tick() - reelTick
			local t = elapsed / returnTime
			if t >= 1 then break end
			local endPos = getStartPos()
			local linear = reelStart:Lerp(endPos, t)
			local arc = Vector3.new(0, reelArc * math.sin(t * math.pi), 0)
			bobber.CFrame = CFrame.new(linear + arc)
			RunService.Heartbeat:Wait()
		end
		if activeTokens[model] ~= token then
			if hookedClone and hookedClone.Parent then hookedClone:Destroy() end
			break
		end

		-- ── GRANT CATCH ──
		if catchDef then
			player = getPlayerByUserId(ownerUserId)
			grantCatchToPlayer(player, catchDef.inventoryName)
			playSound(pickUpSound)
		end

		-- Clean up catch prop
		if hookedClone and hookedClone.Parent then
			hookedClone:Destroy()
		end

		-- Re-attach bobber between casts
		if useRodParts and handle and handle.Parent then
			weldPointerToHandle(bobber, handle)
		else
			bobber.Transparency = 1
			bobber.CFrame = CFrame.new(getRodTipPosition(model))
		end

		-- Pause before next cast
		if not waitSeconds(model, token, 1.5) then break end
	end

	-- Clean up on exit
	if useRodParts then
		if bobber and bobber.Parent and handle and handle.Parent then
			weldPointerToHandle(bobber, handle)
		end
	else
		if bobber and bobber.Parent then
			bobber:Destroy()
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

		task.wait(0.5)

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
