-- Configure API URL and Creator Hub secret before enabling this adapter.
-- This example publishes read-only history + server notifications. Issuing is server-only.
local API_URL = "" -- e.g. https://rewards.example.com
if API_URL == "" then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Codes = require(script.Parent:WaitForChild("RewardCodes"))
local changed = Instance.new("RemoteEvent")
changed.Name = "RewardCodeIssued"
changed.Parent = ReplicatedStorage
local list = Instance.new("RemoteFunction")
list.Name = "RewardCodesList"
list.Parent = ReplicatedStorage
local nextAllowed = {}
list.OnServerInvoke = function(player, after)
	if (nextAllowed[player] or 0) > os.clock() then return { error = "rate_limited" } end
	nextAllowed[player] = os.clock() + 3
	local data, err = Codes.List(player, after)
	return data or { error = err }
end
Players.PlayerRemoving:Connect(function(player) nextAllowed[player] = nil end)
Codes.Start({
	baseUrl = API_URL,
	secretName = "PIRATE_REWARDS_API_KEY",
	rewardIds = { pirate_card_100 = true, pirate_card_500 = true, pirate_card_1000 = true },
	onIssued = function(player, card) changed:FireClient(player, card) end,
})

-- Call ONLY from an authoritative server-side pack handler:
-- local accepted, why = Codes.Queue(player, savedPackResult.dropId, savedPackResult.rewardId)
-- Keep savedPackResult pending until accepted=true. Never accept dropId/rewardId from a client.
-- Keep the SAME dropId after retries/rejoins. Do not GenerateGUID on each retry.
