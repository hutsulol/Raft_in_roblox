-- MercenaryMovement.server.lua
-- Handles movement commands for spawned mercenaries.
-- The client sends a raft part + local offset; the server walks the
-- mercenary to that point, continuously recalculating the world position
-- so the target moves with the raft.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local commandEvent = Instance.new("RemoteEvent")
commandEvent.Name = "MercenaryCommand"
commandEvent.Parent = ReplicatedStorage

-- Active walk coroutines per mercenary model, so we can cancel a walk if
-- a new destination is set before the old one is reached.
local activeWalks = {} -- [model] = token

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

local function walkToRaftPoint(model, raftPart, localOffset)
	-- Cancel any previous walk for this model
	activeWalks[model] = nil

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Unique token for this walk; if activeWalks[model] changes, we stop.
	local token = {}
	activeWalks[model] = token

	task.spawn(function()
		while activeWalks[model] == token do
			if not humanoid or not humanoid.Parent or humanoid.Health <= 0 then break end
			if not raftPart or not raftPart.Parent then break end

			local currentHRP = model:FindFirstChild("HumanoidRootPart")
			if not currentHRP then break end

			-- Recalculate world target from raft part every tick
			local worldTarget = raftPart.CFrame:PointToWorldSpace(localOffset)
			local dist = (currentHRP.Position - worldTarget).Magnitude

			if dist < 2 then
				-- Arrived — stop walking
				break
			end

			-- Continuously redirect toward the moving target
			humanoid:MoveTo(worldTarget)
			task.wait(0.15)
		end

		-- Ensure the humanoid stops moving
		if humanoid and humanoid.Parent then
			local finalHRP = model:FindFirstChild("HumanoidRootPart")
			if finalHRP then
				humanoid:MoveTo(finalHRP.Position)
			end
		end

		if activeWalks[model] == token then
			activeWalks[model] = nil
		end
	end)
end

commandEvent.OnServerEvent:Connect(function(player, action, mercName, raftPart, localOffset)
	if typeof(action) ~= "string" then return end

	if action == "setFishingLocation" then
		if typeof(mercName) ~= "string" then return end
		if typeof(raftPart) ~= "Instance" or not raftPart:IsA("BasePart") then return end
		if typeof(localOffset) ~= "Vector3" then return end

		-- Verify the part is actually on the raft
		local raft = workspace:FindFirstChild("Raft")
		if not raft or not raftPart:IsDescendantOf(raft) then return end

		local model = findMercenary(player, mercName)
		if not model then return end

		walkToRaftPoint(model, raftPart, localOffset)
	end
end)

-- Clean up walk tracking when mercenary is destroyed
CollectionService:GetInstanceRemovedSignal("SpawnedMercenary"):Connect(function(model)
	activeWalks[model] = nil
end)
