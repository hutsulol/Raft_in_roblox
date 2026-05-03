-- WeaponSeenState.server.lua
-- Persists per-player which weapon ids have been seen in the Weapon
-- Select arsenal so the NEW badge only fires once per weapon across
-- sessions. Mirrors the shape of DNAResearch.server.lua:
--   DataStore "WeaponSeenState_v1"  — Player_<UserId> → { [weaponId] = true, ... }
--   RemoteEvent "WeaponSeenState"   — getState / markSeen actions
--
-- Client contract:
--   :FireServer("getState")                 → server replies with:
--     :FireClient(player, "state", { [weaponId] = true, ... })
--   :FireServer("markSeen", weaponId)       → adds weaponId to the set
--     (no reply; persistence auto-saves on interval + player leave)

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AUTO_SAVE_INTERVAL = 120

local store
pcall(function()
	store = DataStoreService:GetDataStore("WeaponSeenState_v1")
end)

local seenEvent = ReplicatedStorage:FindFirstChild("WeaponSeenState")
if not seenEvent then
	seenEvent = Instance.new("RemoteEvent")
	seenEvent.Name = "WeaponSeenState"
	seenEvent.Parent = ReplicatedStorage
end

-- [player] = { [weaponId] = true, ... }
local states = {}
-- [player] = true when the current in-memory state has changes that
-- haven't been pushed to the datastore yet.
local dirty  = {}

local function snapshot(player)
	local src = states[player] or {}
	-- Defensive copy so later server mutations don't leak into a
	-- packet that's already queued for the client.
	local copy = {}
	for k, v in pairs(src) do
		if v then copy[k] = true end
	end
	return copy
end

local function loadState(player)
	if states[player] then return states[player] end
	local loaded = {}
	if store then
		local ok, data = pcall(function()
			return store:GetAsync("Player_" .. player.UserId)
		end)
		if ok and type(data) == "table" then
			for k, v in pairs(data) do
				if type(k) == "string" and v == true then
					loaded[k] = true
				end
			end
		end
	end
	states[player] = loaded
	return loaded
end

local function saveState(player)
	if not store then return end
	if not dirty[player] then return end
	local src = states[player]
	if not src then return end
	local toSave = {}
	for k, v in pairs(src) do
		if v then toSave[k] = true end
	end
	local ok = pcall(function()
		store:SetAsync("Player_" .. player.UserId, toSave)
	end)
	if ok then dirty[player] = nil end
end

seenEvent.OnServerEvent:Connect(function(player, action, weaponId)
	if typeof(action) ~= "string" then return end
	local state = loadState(player)

	if action == "getState" then
		seenEvent:FireClient(player, "state", snapshot(player))

	elseif action == "markSeen" then
		if typeof(weaponId) ~= "string" or weaponId == "" then return end
		if state[weaponId] then return end
		state[weaponId] = true
		dirty[player] = true
	end
end)

Players.PlayerAdded:Connect(loadState)
Players.PlayerRemoving:Connect(function(player)
	saveState(player)
	states[player] = nil
	dirty[player]  = nil
end)

-- Auto-save loop. Same cadence as other server state in this repo so
-- a crash / disconnect loses at most ~2 min of NEW-badge dismissals.
task.spawn(function()
	while true do
		task.wait(AUTO_SAVE_INTERVAL)
		for player in pairs(states) do
			saveState(player)
		end
	end
end)

game:BindToClose(function()
	for player in pairs(states) do
		saveState(player)
	end
end)
