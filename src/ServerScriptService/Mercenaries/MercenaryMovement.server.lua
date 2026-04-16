-- MercenaryMovement.server.lua
-- Handles movement commands for spawned mercenaries.
-- The client sends a raft part + local offset. The pirate walks there
-- and, if it has a fishing rod, swaps the fake rod for the real one.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local commandEvent = Instance.new("RemoteEvent")
commandEvent.Name = "MercenaryCommand"
commandEvent.Parent = ReplicatedStorage

local activeTokens = {} -- [model] = token

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

-- ── Rod swap ────────────────────────────────────────────────────────────
-- When the pirate reaches its position, swap the visual-only
-- FishingRod_Fake for the real FishingRod_ForPirate.

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
		-- Walk to the raft point
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

		-- If this is a fishing-rod merc, swap to the real rod
		local equippedWeapon = model:GetAttribute("EquippedWeapon") or "Sword"
		if equippedWeapon == "FishingRod" then
			swapToRealRod(model)
		end

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
	end
end)

CollectionService:GetInstanceRemovedSignal("SpawnedMercenary"):Connect(function(model)
	activeTokens[model] = nil
end)
