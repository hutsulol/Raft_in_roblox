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

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- Forward-declared so onQuestEvent (defined further down) can push
-- a snapshot to the client whenever progress changes. The actual
-- function body lives further down next to buildSnapshot — this
-- declaration is just a placeholder so the upvalue resolves.
local fireSnapshot

-- Coalesces multiple onQuestEvent calls in the same frame into a
-- single snapshot push. Without this, chopping 10 logs would push
-- 10 separate state events.
local snapshotPending = {}
local function schedulePush(player)
	if snapshotPending[player] then return end
	snapshotPending[player] = true
	task.defer(function()
		snapshotPending[player] = nil
		if states[player] and fireSnapshot then
			fireSnapshot(player)
		end
	end)
end

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

-- ─── Daily roll (C7) ────────────────────────────────────────────────
-- Called on player join. Compares os.date('*t').yday against the
-- player's saved lastDailyDate; if they differ, picks 4 fresh daily
-- ids from the catalog filtered against permanentlyCompleted (so
-- single-use crafting gates don't reappear) and clears any active
-- entries for the OLD daily ids so the new selection is the only
-- visible set on the Quests tab.
--
-- Story + challenge entries are unaffected — story is permanent, and
-- challenges are explicitly Started/Expired by the player so they
-- never spend a "daily slot".
local DAILIES_PER_DAY = 3
-- The catalog lives on _G.QuestCatalog (set by QuestCatalog.server.lua,
-- a sibling .server.lua so they should parse before this script for
-- alphabetical-folder-order reasons). Wait briefly + warn-fallback for
-- the rare load-order quirk.
local function waitForCatalog(timeoutSec)
	local deadline = os.clock() + (timeoutSec or 5)
	while os.clock() < deadline do
		if _G.QuestCatalog and _G.QuestCatalog.getByKind then
			return _G.QuestCatalog
		end
		task.wait(0.1)
	end
	return nil
end

local function rollDailiesIfNeeded(player)
	local s = states[player]
	if not s then return end

	local today = os.date("*t").yday
	if s.lastDailyDate == today and #s.dailySelection > 0 then
		-- Already rolled today; keep the same selection so progress
		-- across a relog mid-day doesn't reset.
		return
	end

	local catalog = waitForCatalog(5)
	if not catalog then
		warn("[QuestState] _G.QuestCatalog never appeared; skipping daily roll for "
			.. tostring(player.Name))
		return
	end

	-- Build the eligibility pool: every daily entry whose id isn't
	-- already in permanentlyCompleted. Workbench gate + future single-
	-- use crafting dailies fall out here automatically.
	local pool = {}
	for _, q in ipairs(catalog.getByKind("daily")) do
		if not s.permanentlyCompleted[q.id] then
			table.insert(pool, q.id)
		end
	end

	-- Shuffle (Fisher-Yates) so the same 4 don't cluster on
	-- consecutive days, then take the first N.
	for i = #pool, 2, -1 do
		local j = math.random(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end

	-- Drop any active entries from the previous day's daily set so
	-- only the new picks show on the Quests tab. Story + challenge
	-- active entries survive the swap.
	for _, oldId in ipairs(s.dailySelection) do
		s.active[oldId] = nil
		s.pendingRewards[oldId] = nil
	end

	s.dailySelection = {}
	for i = 1, math.min(DAILIES_PER_DAY, #pool) do
		local id = pool[i]
		table.insert(s.dailySelection, id)
		-- Seed an active entry with zero-filled progress per
		-- objective slot so the event hook in C8 has a target to
		-- increment without re-checking the catalog every tick.
		local def = catalog.get(id)
		if def then
			local progress = {}
			for objIdx = 1, #def.objectives do
				progress[objIdx] = 0
			end
			s.active[id] = {
				progress  = progress,
				startedAt = nil,
				tracked   = false,
			}
		end
	end

	s.lastDailyDate = today
	markDirty(player)
end

-- Story quests aren't part of the daily roll, but they DO need an
-- active entry on first sight so the event hook (C8) can match
-- objectives. This runs after the daily roll on first join + every
-- relog as a no-op.
local function ensureStoryActiveEntries(player)
	local s = states[player]
	if not s then return end
	local catalog = waitForCatalog(5)
	if not catalog then return end

	for _, q in ipairs(catalog.getByKind("story")) do
		if not s.permanentlyCompleted[q.id] and not s.active[q.id] then
			local progress = {}
			for objIdx = 1, #q.objectives do
				progress[objIdx] = 0
			end
			s.active[q.id] = {
				progress  = progress,
				startedAt = nil,
				tracked   = false,
			}
			markDirty(player)
		end
	end
end

-- Player-init helper that loadState calls into below.
local function initPlayerQuestState(player)
	loadState(player)
	rollDailiesIfNeeded(player)
	ensureStoryActiveEntries(player)
end

-- ─── Lifecycle hooks ─────────────────────────────────────────────────
Players.PlayerAdded:Connect(initPlayerQuestState)

Players.PlayerRemoving:Connect(function(player)
	saveState(player)
	states[player] = nil
	dirty[player]  = nil
end)

-- Already-in-game players (live-reload / Studio Play Solo).
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(initPlayerQuestState, player)
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

-- ─── Generic event hook (C8) ────────────────────────────────────────
-- _G.OnQuestEvent(player, eventType, count) is the single entry point
-- for every gameplay system that wants to credit quest progress.
-- Each gameplay subsystem fires its own eventType string:
--   "resource:Log", "resource:Plastic", "resource:Stone", "resource:Leaves"
--   "pirate:kill", "pirate:bloodTaken"
--   "merc:hired", "dna:analyzed"
--   "crafted:Workbench", "crafted:WallPanel"
--   "planted:BerryBush"
-- The catalog declares which eventType each objective listens to;
-- this hook walks the player's active entries and bumps any matching
-- objective slot, marking permanentlyCompleted on quests that flip
-- all objectives to goal.
local function onQuestEvent(player, eventType, count)
	if not player or typeof(eventType) ~= "string" or eventType == "" then return end
	count = (type(count) == "number" and count > 0) and count or 1

	local s = states[player]
	if not s then return end
	local catalog = _G.QuestCatalog
	if not catalog then return end

	local stateChanged = false

	for questId, entry in pairs(s.active) do
		local def = catalog.get(questId)
		if def and not s.permanentlyCompleted[questId] then
			local allDone = true
			local touched = false
			for objIdx, obj in ipairs(def.objectives) do
				local current = entry.progress[objIdx] or 0
				if obj.eventType == eventType and current < obj.goal then
					-- Challenge expiry guard — if this is a timed
					-- quest and the timer has already elapsed,
					-- silently drop the increment (the player just
					-- ran out of time on a kill / chop swing). The
					-- expiry sweep elsewhere clears the entry; we
					-- just don't credit progress past it here.
					if def.kind == "challenge" and entry.startedAt
						and (os.time() - entry.startedAt) > (def.durationSec or 0)
					then
						-- expired
					else
						local new = math.min(obj.goal, current + count)
						if new ~= current then
							entry.progress[objIdx] = new
							touched = true
						end
					end
				end
				if (entry.progress[objIdx] or 0) < obj.goal then
					allDone = false
				end
			end

			if touched then
				stateChanged = true
				if allDone then
					-- Mark the reward as claimable. Permanent quests
					-- (story + single-use dailies like the workbench
					-- gate) also flip permanentlyCompleted so the
					-- daily roll never reissues them. Non-permanent
					-- dailies stay claimable until the next roll
					-- swaps them out anyway.
					s.pendingRewards[questId] = true
					if def.permanent then
						s.permanentlyCompleted[questId] = true
					end
					-- Auto-untrack on completion (T10) so the corner
					-- tracker card slides out cleanly. The menu's
					-- card flips to "Claim Reward" off rewardPending,
					-- which doesn't depend on tracked, so claiming
					-- still works from any tab.
					entry.tracked = false
				end
			end
		end
	end

	if stateChanged then
		markDirty(player)
		-- Push the new state to the client so the menu's progress bars
		-- update live. schedulePush coalesces multiple events in the
		-- same frame into one snapshot.
		schedulePush(player)
	end
end

_G.OnQuestEvent = onQuestEvent

-- ─── _G.OnQuestResource shim (C10) ──────────────────────────────────
-- Existing gameplay systems (ResourceSpawner, ShovelSystem,
-- PickAxeSystem, FurnaceCraft) already call _G.OnQuestResource on
-- every harvest. DailyQuests + ChopTreesFlow have prior claims on
-- the same global, so we chain instead of overwrite — capture the
-- previous hook inside task.defer (which fires after every
-- ServerScriptService script's top-level body has parsed regardless
-- of folder order), then route every call through both the previous
-- chain and our generic _G.OnQuestEvent("resource:"..resType) hook.
task.defer(function()
	local previous = _G.OnQuestResource
	_G.OnQuestResource = function(player, resType, amount)
		if typeof(previous) == "function" then
			-- pcall isolates a buggy peer (DailyQuests' progress
			-- table corruption, ChopTreesFlow's onboarding bookkeeping)
			-- so a downstream error doesn't break our own credit path.
			pcall(previous, player, resType, amount)
		end
		if typeof(resType) == "string" and resType ~= "" then
			pcall(onQuestEvent, player, "resource:" .. resType, amount or 1)
		end
	end
end)

-- ─── RemoteEvent + handlers (C9) ────────────────────────────────────
-- One channel for every menu/tracker → server quest action. Server
-- replies with snapshots that bake in the catalog data the client
-- needs to render (titles, body, icon, reward) so the client never
-- has to require the catalog itself — keeps quest content swappable
-- without a client redeploy.
local event = ReplicatedStorage:FindFirstChild("QuestState")
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "QuestState"
	event.Parent = ReplicatedStorage
end

-- ─── Challenge expiry sweep (F1) ────────────────────────────────────
-- Called before each snapshot so the client never sees a stale
-- "still running" challenge whose timer has actually run out. If the
-- elapsed time exceeds durationSec AND the goal isn't hit, we reset
-- the entry (clear startedAt, zero progress, drop tracked) so the
-- card flips back to its "Start" state. Completed challenges leave
-- startedAt set so the player can claim — the daily-roll handler
-- below cleans them up on the next day.
local function sweepExpiredChallenges(player)
	local s = states[player]
	if not s then return end
	local catalog = _G.QuestCatalog
	if not catalog then return end

	local now = os.time()
	for id, entry in pairs(s.active) do
		local def = catalog.get(id)
		if def and def.kind == "challenge" and entry.startedAt then
			local elapsed = now - entry.startedAt
			if elapsed > (def.durationSec or 0) then
				-- Did the player hit every goal before the timer expired?
				local allDone = true
				for i, obj in ipairs(def.objectives) do
					if (entry.progress[i] or 0) < obj.goal then
						allDone = false
						break
					end
				end
				if not allDone and not s.pendingRewards[id] then
					-- Expired without a win → reset for retry.
					entry.startedAt = nil
					entry.tracked   = false
					for i = 1, #def.objectives do
						entry.progress[i] = 0
					end
					markDirty(player)
				end
			end
		end
	end
end

-- Build a defensive snapshot the client can render directly. Each
-- visible-to-player quest goes in once, with display fields baked
-- in alongside the player's progress so the menu has everything
-- needed to paint a card without follow-up server calls.
local function buildSnapshot(player)
	sweepExpiredChallenges(player)
	local s = states[player] or loadState(player)
	local catalog = _G.QuestCatalog
	if not catalog then
		return { quests = {}, pendingRewards = {}, historyLog = {} }
	end

	local quests = {}

	local function pushQuest(def, activeEntry)
		local objectives = {}
		for i, obj in ipairs(def.objectives) do
			objectives[i] = {
				eventType = obj.eventType,
				goal      = obj.goal,
				label     = obj.label,
				progress  = (activeEntry and activeEntry.progress[i]) or 0,
			}
		end
		local secondsRemaining
		if def.kind == "challenge" and activeEntry and activeEntry.startedAt then
			local elapsed = os.time() - activeEntry.startedAt
			secondsRemaining = math.max(0, (def.durationSec or 0) - elapsed)
		end
		table.insert(quests, {
			id               = def.id,
			kind             = def.kind,
			title            = def.title,
			body             = def.body,
			icon             = def.icon,
			reward           = def.reward,
			durationSec      = def.durationSec,
			objectives       = objectives,
			tracked          = (activeEntry and activeEntry.tracked) == true,
			startedAt        = activeEntry and activeEntry.startedAt,
			secondsRemaining = secondsRemaining,
			completed        = s.permanentlyCompleted[def.id] == true,
			rewardPending    = s.pendingRewards[def.id] == true,
		})
	end

	-- Story quests are always visible until permanentlyCompleted.
	for _, def in ipairs(catalog.getByKind("story")) do
		if not s.permanentlyCompleted[def.id] then
			pushQuest(def, s.active[def.id])
		end
	end
	-- Today's daily picks (the C7 selection).
	for _, id in ipairs(s.dailySelection) do
		local def = catalog.get(id)
		if def and not s.permanentlyCompleted[def.id] then
			pushQuest(def, s.active[def.id])
		end
	end
	-- Every challenge is always visible (Phase F handles Start/expire).
	for _, def in ipairs(catalog.getByKind("challenge")) do
		pushQuest(def, s.active[def.id])
	end

	-- History payload: copy ids + completedAt only. Client maps the
	-- ids against the same catalog field info if it wants display
	-- titles for past quests — for now the server includes them.
	local history = {}
	for i, entry in ipairs(s.historyLog) do
		local def = catalog.get(entry.id)
		history[i] = {
			id          = entry.id,
			completedAt = entry.completedAt,
			title       = def and def.title,
			icon        = def and def.icon,
			reward      = def and def.reward,
		}
	end

	return {
		quests         = quests,
		pendingRewards = s.pendingRewards,
		historyLog     = history,
	}
end

function fireSnapshot(player)
	event:FireClient(player, "state", buildSnapshot(player))
end

-- Helper used by track / untrack / startChallenge / claimReward.
local function getActiveEntry(player, questId)
	local s = states[player]
	if not s then return nil, nil end
	local entry = s.active[questId]
	local def   = _G.QuestCatalog and _G.QuestCatalog.get(questId)
	return entry, def, s
end

event.OnServerEvent:Connect(function(player, action, ...)
	if typeof(action) ~= "string" then return end

	if action == "getState" then
		-- Self-heal: if the player's state never recorded a successful
		-- roll for today (lastDailyDate stuck on a previous day, or 0
		-- because the catalog-load race meant the first PlayerAdded
		-- roll silently dropped), retry now. We DON'T re-roll just
		-- because dailySelection is empty same-day — that's the legit
		-- "claimed all 4 dailies, wait for tomorrow" state and we
		-- don't want infinite quest farming.
		local s = states[player]
		if s and s.lastDailyDate ~= os.date("*t").yday
			and #s.dailySelection == 0
		then
			rollDailiesIfNeeded(player)
		end
		fireSnapshot(player)

	elseif action == "track" then
		-- One quest tracked at a time — clear any previous tracked
		-- flag, then flip the new one. Phase H's tracker card subscribes
		-- to the snapshot to know which quest to display.
		local questId = (select(1, ...))
		if typeof(questId) ~= "string" then return end
		local entry, def, s = getActiveEntry(player, questId)
		if not entry or not def then return end
		for _, other in pairs(s.active) do other.tracked = false end
		entry.tracked = true
		markDirty(player)
		fireSnapshot(player)

	elseif action == "untrack" then
		local s = states[player]
		if not s then return end
		for _, other in pairs(s.active) do other.tracked = false end
		markDirty(player)
		fireSnapshot(player)

	elseif action == "startChallenge" then
		local questId = (select(1, ...))
		if typeof(questId) ~= "string" then return end
		local s = states[player]
		if not s then return end
		local def = _G.QuestCatalog and _G.QuestCatalog.get(questId)
		if not def or def.kind ~= "challenge" then return end

		-- Challenges aren't seeded at init time the way story / dailies
		-- are — the player picks which one to engage with by clicking
		-- Start. If there's no active entry yet, create one here so
		-- the rest of the handler has somewhere to write progress.
		local entry = s.active[questId]
		if not entry then
			local progress = {}
			for i = 1, #def.objectives do progress[i] = 0 end
			entry = { progress = progress, startedAt = nil, tracked = false }
			s.active[questId] = entry
		end

		if entry.startedAt then return end -- already running

		entry.startedAt = os.time()
		-- Reset progress so a relogged challenge starts clean.
		for i = 1, #def.objectives do
			entry.progress[i] = 0
		end
		-- Auto-track started challenges so the corner card shows up
		-- immediately (per the spec: timed quests jump to tracking).
		for _, other in pairs(s.active) do other.tracked = false end
		entry.tracked = true
		markDirty(player)
		fireSnapshot(player)

	elseif action == "claimReward" then
		local questId = (select(1, ...))
		if typeof(questId) ~= "string" then return end
		local s = states[player]
		if not s or not s.pendingRewards[questId] then return end
		local def = _G.QuestCatalog and _G.QuestCatalog.get(questId)
		if not def then return end

		-- Grant the reward via the existing inventory pipeline.
		-- Resource rewards route through _G.AddResourceToInventory
		-- (used by ResourceSpawner / FurnaceCraft for the same
		-- inventory-full overflow handling); item rewards fall back
		-- to the same path with the item's name string.
		if def.reward and def.reward.kind and def.reward.name then
			local fn = _G.AddResourceToInventory
			if typeof(fn) == "function" then
				pcall(fn, player, def.reward.name, def.reward.count or 1, nil)
			else
				warn("[QuestState] _G.AddResourceToInventory not available; reward dropped")
			end
		end

		-- Bookkeeping: remove from pending, append to history,
		-- clear the active slot for daily quests so the card flips
		-- to "claimed" and clears on next roll. Story / single-use
		-- dailies stay in permanentlyCompleted from the C8 hook.
		s.pendingRewards[questId] = nil
		table.insert(s.historyLog, 1, { id = questId, completedAt = os.time() })
		-- Cap the history at 50 entries so the DataStore blob stays
		-- small over a long-running save file.
		while #s.historyLog > 50 do
			table.remove(s.historyLog)
		end
		if def.kind == "daily" then
			s.active[questId] = nil
			-- Drop the slot from today's selection too so the card
			-- actually disappears for the rest of the day instead of
			-- re-appearing with 0/N progress on the next snapshot.
			-- The remaining 1-3 dailies stay visible; the slot is not
			-- back-filled — players can grind out the others or wait
			-- for tomorrow's roll.
			for i = #s.dailySelection, 1, -1 do
				if s.dailySelection[i] == questId then
					table.remove(s.dailySelection, i)
				end
			end
		end
		markDirty(player)
		saveState(player)
		fireSnapshot(player)
	end
end)

-- Push a snapshot once initPlayerQuestState has finished so the
-- client controller's getState round-trip isn't the only path that
-- delivers state. Wrap in task.spawn so we don't block the join
-- handler chain.
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		-- Wait one tick so initPlayerQuestState (also bound to
		-- PlayerAdded) finishes before we snapshot.
		task.wait(0)
		fireSnapshot(player)
	end)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(fireSnapshot, player)
end

-- ─── Read-only globals ───────────────────────────────────────────────
-- Other server scripts can read state via these accessors. Mutations
-- always go through helpers (added in C7-C9) so the dirty flag stays
-- accurate.
_G.GetQuestState     = function(player) return states[player] or loadState(player) end
_G.MarkQuestDirty    = markDirty
_G.SaveQuestState    = saveState
_G.QuestStateEvent   = event
_G.SnapshotQuestState = buildSnapshot
