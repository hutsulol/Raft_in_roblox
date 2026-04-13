-- MercenaryMovement.server.lua
-- Handles movement commands for spawned mercenaries.
-- The client sends a target position; the server walks the mercenary there.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local commandEvent = Instance.new("RemoteEvent")
commandEvent.Name = "MercenaryCommand"
commandEvent.Parent = ReplicatedStorage

-- Active walk coroutines per mercenary model, so we can cancel a walk if
-- a new destination is set before the old one is reached.
local activeWalks = {} -- [model] = true (flag checked by walk loop)

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

local function walkTo(model, targetPos)
	-- Cancel any previous walk for this model
	activeWalks[model] = nil

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Unique token for this walk; if activeWalks[model] changes, we stop.
	local token = {}
	activeWalks[model] = token

	-- Repeatedly call MoveTo until we're close enough (MoveTo has an 8s timeout).
	task.spawn(function()
		while activeWalks[model] == token do
			if not humanoid or not humanoid.Parent or humanoid.Health <= 0 then break end

			humanoid:MoveTo(targetPos)
			humanoid.MoveToFinished:Wait()

			local currentHRP = model:FindFirstChild("HumanoidRootPart")
			if not currentHRP then break end

			local dist = (currentHRP.Position - targetPos).Magnitude
			if dist < 3 then
				break
			end
		end

		-- Clear walk token if it's still ours
		if activeWalks[model] == token then
			activeWalks[model] = nil
		end
	end)
end

commandEvent.OnServerEvent:Connect(function(player, action, mercName, data)
	if typeof(action) ~= "string" then return end

	if action == "setFishingLocation" then
		if typeof(mercName) ~= "string" then return end
		if typeof(data) ~= "Vector3" then return end

		local model = findMercenary(player, mercName)
		if not model then return end

		walkTo(model, data)
	end
end)

-- Clean up walk tracking when mercenary is destroyed
CollectionService:GetInstanceRemovedSignal("SpawnedMercenary"):Connect(function(model)
	activeWalks[model] = nil
end)
