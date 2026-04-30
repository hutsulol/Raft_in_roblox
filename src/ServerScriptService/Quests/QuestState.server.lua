-- QuestState.server.lua
-- Per-player quest state. Built up across C6 → C10:
--
--   C6 (this commit): DataStore + state cache + load / save / auto-save
--                     + read-only globals for the rest of the system.
--   C7: daily-roll on join.
--   C8: _G.OnQuestEvent generic objective hook.
--   C9: RemoteEvent (getState / track / untrack / startChallenge /
--       claimReward) handlers.
--   C10: _G.OnQuestResource shim so existing ResourceSpawner /
--        ShovelSystem / PickAxeSystem / FurnaceCraft callers still
--        feed the quest progress path.
--
-- State shape per player (extensible — every flow type the catalog
-- defines today fits this shape):
--   {
--     active = {
--       [questId] = {
--         progress = { N1, N2, ... }    -- one slot per objective; same
--                                       -- order as catalog.objectives
--         startedAt = os.time(),         -- challenges only; nil otherwise
--         tracked   = bool,              -- true when the player tracked
--                                       -- this quest in the menu (Phase H
--                                       -- shows the corner card for it).
--       }
--     },
--     permanentlyCompleted = { [questId] = true, ... },
--     pendingRewards       = { [questId] = true, ... }, -- waiting for claim
--     lastDailyDate        = N,                          -- os.date("*t").yday
--                                                         -- of the last roll
--     dailySelection       = { questId, questId, ... }, -- the 4 dailies
--                                                         -- chosen for today
--     historyLog           = { { id, completedAt }, ... }, -- newest first
--   }

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local AUTO_SAVE_INTERVAL = 120  -- seconds; matches DNAResearch / OnboardingState

-- ─── DataStore (defensive — Studio Play Solo without API access
-- still leaves us with a working in-memory cache, just no persistence).
local store
pcall(function()
	store = DataStoreService:GetDataStore("QuestState_v1")
end)

-- ─── State cache + dirty tracking ────────────────────────────────────
local states = {}    -- [player] = state table
local dirty  = {}    -- [player] = true when in-memory state has
                     -- diverged from the last persisted snapshot

local function freshState()
	return {
		active               = {},   -- [questId] = { progress, startedAt, tracked }
		permanentlyCompleted = {},
		pendingRewards       = {},
		lastDailyDate        = 0,
		dailySelection       = {},
		historyLog           = {},
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
			-- Sanitise every field so a malformed blob (older schema,
			-- corrupt write) can't propagate bad types into the rest
			-- of the system.
			if type(data.active) == "table" then
				for id, entry in pairs(data.active) do
					if type(id) == "string" and type(entry) == "table" then
						local progress = {}
						if type(entry.progress) == "table" then
							for i, n in ipairs(entry.progress) do
								progress[i] = tonumber(n) or 0
							end
						end
						loaded.active[id] = {
							progress  = progress,
							startedAt = tonumber(entry.startedAt),  -- may be nil
							tracked   = entry.tracked == true,
						}
					end
				end
			end
			if type(data.permanentlyCompleted) == "table" then
				for id, v in pairs(data.permanentlyCompleted) do
					if type(id) == "string" and v == true then
						loaded.permanentlyCompleted[id] = true
					end
				end
			end
			if type(data.pendingRewards) == "table" then
				for id, v in pairs(data.pendingRewards) do
					if type(id) == "string" and v == true then
						loaded.pendingRewards[id] = true
					end
				end
			end
			loaded.lastDailyDate = tonumber(data.lastDailyDate) or 0
			if type(data.dailySelection) == "table" then
				for i, id in ipairs(data.dailySelection) do
					if type(id) == "string" then
						loaded.dailySelection[i] = id
					end
				end
			end
			if type(data.historyLog) == "table" then
				for i, entry in ipairs(data.historyLog) do
					if type(entry) == "table"
						and type(entry.id) == "string"
						and type(entry.completedAt) == "number"
					then
						table.insert(loaded.historyLog, {
							id          = entry.id,
							completedAt = entry.completedAt,
						})
					end
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

-- ─── Lifecycle hooks ─────────────────────────────────────────────────
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

-- ─── Read-only globals ───────────────────────────────────────────────
-- Other server scripts can read state via these accessors. Mutations
-- always go through helpers (added in C7-C9) so the dirty flag stays
-- accurate.
_G.GetQuestState   = function(player) return states[player] or loadState(player) end
_G.MarkQuestDirty  = markDirty
_G.SaveQuestState  = saveState
