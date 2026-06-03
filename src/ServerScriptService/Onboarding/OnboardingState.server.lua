-- OnboardingState.server.lua
-- Per-player onboarding flow state. Step 2A wires the persistence
-- skeleton — DataStore, RemoteEvent, in-memory cache, load/save/auto-
-- save lifecycle. Step 2B adds the actual chop-trees event handler
-- and the _G.OnQuestResource hook; Step 2C wires the client.
--
-- The state shape lives at _G.OnboardingState for any other server
-- script to inspect read-only. Mutations always go through this
-- module so the dirty flag + DataStore stays in sync.
--
-- State shape per player (extensible for future flows):
--   {
--     chopTrees = { progress = N, completed = bool, dismissed = bool },
--     -- (later flows append additional sub-tables here)
--   }

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AUTO_SAVE_INTERVAL = 120  -- seconds; matches DNAResearch / WeaponSeenState

-- ─── DataStore (defensive — running in Studio without API access
-- still leaves us with a working in-memory cache, just no persistence).
local store
pcall(function()
	store = DataStoreService:GetDataStore("OnboardingState_v1")
end)

-- ─── RemoteEvent (one channel for every flow) ────────────────────────
-- Server fires:
--   "state"       (snapshot table)         — full per-player state on
--                                            request, after save, etc.
--   "<flow>:progress" (n, goal)            — added in Step 2B
--   "<flow>:complete"                      — added in Step 2B
-- Client fires:
--   "getState"                              — request initial snapshot
--   "<flow>:dismiss"                        — user closed the tip
local event = ReplicatedStorage:FindFirstChild("OnboardingFlow")
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "OnboardingFlow"
	event.Parent = ReplicatedStorage
end

-- ─── State cache + dirty tracking ─────────────────────────────────────
local states = {}    -- [player] = state table
local dirty  = {}    -- [player] = true when the in-memory state has
                     -- diverged from the last persisted snapshot

local function freshState()
	return {
		chopTrees = { progress = 0, completed = false, dismissed = false },
	}
end

-- Defensive copy so a server-side mutation can't ripple into the
-- packet that's already queued for the client.
local function snapshotState(s)
	return {
		chopTrees = {
			progress  = (s.chopTrees and s.chopTrees.progress)  or 0,
			completed = (s.chopTrees and s.chopTrees.completed) == true,
			dismissed = (s.chopTrees and s.chopTrees.dismissed) == true,
		},
	}
end

local function loadState(player)
	if states[player] then return states[player] end
	local loaded = freshState()

	if store then
		local ok, data = pcall(function()
			return store:GetAsync("Player_" .. player.UserId)
		end)
		if ok and type(data) == "table" then
			if type(data.chopTrees) == "table" then
				loaded.chopTrees.progress  = tonumber(data.chopTrees.progress) or 0
				loaded.chopTrees.completed = data.chopTrees.completed == true
				loaded.chopTrees.dismissed = data.chopTrees.dismissed == true
			end
		end
	end

	states[player] = loaded
	return loaded
end

local function saveState(player)
	if not store then return end
	if not dirty[player] then return end
	local s = states[player]
	if not s then return end
	local ok = pcall(function()
		store:SetAsync("Player_" .. player.UserId, s)
	end)
	if ok then dirty[player] = nil end
end

local function markDirty(player)
	if states[player] then
		dirty[player] = true
	end
end

-- ─── Lifecycle hooks ──────────────────────────────────────────────────

Players.PlayerAdded:Connect(loadState)

Players.PlayerRemoving:Connect(function(player)
	saveState(player)
	states[player] = nil
	dirty[player]  = nil
end)

-- Already-in-game players (live-reload / Studio Play Solo).
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadState, player)
end

-- Auto-save tick. Same cadence as the rest of the per-player state
-- in this repo so a crash never costs more than ~2 minutes.
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

-- ─── Read-only exports for other server scripts (Step 2B uses these) ─
-- These are intentionally read-mostly: callers should mutate via the
-- helper API that lands in 2B, not by reaching into the table.
_G.GetOnboardingState = function(player)
	if not player or not player.Parent then return nil end
	return states[player] or loadState(player)
end

_G.SnapshotOnboardingState = function(player)
	local s = states[player] or loadState(player)
	return snapshotState(s)
end

_G.MarkOnboardingDirty = markDirty
_G.SaveOnboardingState  = saveState
_G.OnboardingFlowEvent  = event
