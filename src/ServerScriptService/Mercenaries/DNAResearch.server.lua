-- DNAResearch.server.lua
-- Per-mercenary DNA research state, persisted via DataStore and
-- exposed to the client through the DNAResearch RemoteEvent.
--
-- Step 2 scope (this file): state + persistence + two remote actions.
--   getState(mercName)      — snapshot the merc's state to the client.
--   insertBlood(mercName)   — consume one FullCapsule whose BloodType
--                             attribute matches the mercenary, hand
--                             the player an EmptyCapsule in return,
--                             and start a 60-second study timer.
-- Step 3 will add the study tick that fills a random fragment by
-- +10% when the timer elapses, and Step 4 will layer on stat / level
-- / upgrade-point / research-point rewards when a fragment hits 100%.
--
-- State shape (per player, keyed by merc):
--   {
--     [mercName] = {
--       fragments      = { 0..100 } × 16,
--       activeSlot     = { bloodType = <mercName>|nil, endsAt = <epoch> },
--       researchPoints = N,            -- spent on trait mutations
--       traitEffect    = { rareMarker, mutation, fullGenome },  -- %
--     }
--   }
--
-- Globals exported for Steps 3 / 4 and the DNAStudyPage client script:
--   _G.GetDNAResearchMercState(player, mercName)
--   _G.FireDNAResearchState(player, mercName)
--   _G.DNAResearch_FragmentCount = 9
--   _G.DNAResearch_StudyDuration = 60

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── Constants ────────────────────────────────────────────────────────
local FRAGMENT_COUNT     = 6
local STUDY_DURATION     = 30   -- seconds per study tick
local FIRST_BAR_FILL_PCT = 10   -- % each study adds while F01 < 100
local LATER_BAR_FILL_PCT = 5    -- % each study adds once F01 is full
local TICK_INTERVAL      = 1    -- how often the server checks for expired slots
local AUTO_SAVE_INTERVAL = 120  -- seconds, mirrors InventoryManager

-- Per-tick stat reward (granted every study tick, regardless of whether
-- the bar fills to 100 %). Rolled uniformly inside [min, max].
local STAT_TICK_MIN      = 1
local STAT_TICK_MAX      = 2

-- Fragment-index → stat-name map. F01-F02 strength (top lens),
-- F03-F04 luck (middle lens), F05-F06 speed (bottom lens). Three
-- equal sections × 2 bars each = 6 fragments total — matches the
-- compact 3-lens client helix.
local SECTION_STAT = {
	"strength", "strength",
	"luck",     "luck",
	"speed",    "speed",
}

_G.DNAResearch_FragmentCount = FRAGMENT_COUNT
_G.DNAResearch_StudyDuration = STUDY_DURATION

-- ─── DataStore ────────────────────────────────────────────────────────
local dnaStore
pcall(function()
	dnaStore = DataStoreService:GetDataStore("DNAResearchState_v1")
end)

-- ─── RemoteEvent ──────────────────────────────────────────────────────
local dnaEvent = ReplicatedStorage:FindFirstChild("DNAResearch")
if not dnaEvent then
	dnaEvent = Instance.new("RemoteEvent")
	dnaEvent.Name = "DNAResearch"
	dnaEvent.Parent = ReplicatedStorage
end

-- ─── Per-player state ─────────────────────────────────────────────────
local states = {}

local function freshMercState()
	local fragments = table.create(FRAGMENT_COUNT, 0)
	return {
		fragments      = fragments,
		activeSlot     = { bloodType = nil, endsAt = 0 },
		researchPoints = 0,
		traitEffect    = { rareMarker = 0, mutation = 0, fullGenome = 0 },
		-- Per-merc progression. These used to live only in the client's
		-- hardcoded MERC_THEMES table; the DNA research loop is the
		-- first server-side writer so it owns the canonical values
		-- until something else needs to mutate them.
		stats          = { strength = 0, speed = 0, luck = 0, level = 1, upgradePoints = 0 },
	}
end

local function getOrCreateMercState(player, mercName)
	if not states[player] then states[player] = {} end
	local playerState = states[player]
	if not playerState[mercName] then
		playerState[mercName] = freshMercState()
	end
	return playerState[mercName]
end

-- Serialisable snapshot. Converts the absolute endsAt into a
-- secondsRemaining so the client doesn't have to reason about the
-- server clock — it just counts down locally from the value we send.
local function snapshotMerc(mercState)
	local now = os.time()
	local slot = mercState.activeSlot or {}
	local remaining = math.max(0, (slot.endsAt or 0) - now)
	-- Defensive copy of fragments so later server mutations can't
	-- ripple into the frame already queued to the client.
	local fragmentsCopy = table.create(FRAGMENT_COUNT, 0)
	for i = 1, FRAGMENT_COUNT do
		fragmentsCopy[i] = mercState.fragments[i] or 0
	end
	return {
		fragments = fragmentsCopy,
		activeSlot = {
			bloodType        = slot.bloodType,
			secondsRemaining = remaining,
			totalDuration    = STUDY_DURATION,
		},
		researchPoints = mercState.researchPoints or 0,
		traitEffect    = {
			rareMarker = mercState.traitEffect.rareMarker or 0,
			mutation   = mercState.traitEffect.mutation   or 0,
			fullGenome = mercState.traitEffect.fullGenome or 0,
		},
		stats = {
			strength      = mercState.stats.strength      or 0,
			speed         = mercState.stats.speed         or 0,
			luck          = mercState.stats.luck          or 0,
			level         = mercState.stats.level         or 1,
			upgradePoints = mercState.stats.upgradePoints or 0,
		},
	}
end

-- ─── DataStore load / save ────────────────────────────────────────────
local function loadState(player)
	if states[player] then return states[player] end
	local loaded = {}
	if dnaStore then
		local ok, data = pcall(function()
			return dnaStore:GetAsync("Player_" .. player.UserId)
		end)
		if ok and type(data) == "table" then
			for mercName, mercData in pairs(data) do
				if type(mercName) == "string" and type(mercData) == "table" then
					local mercState = freshMercState()
					if type(mercData.fragments) == "table" then
						for i = 1, FRAGMENT_COUNT do
							local n = tonumber(mercData.fragments[i])
							mercState.fragments[i] = math.clamp(n or 0, 0, 100)
						end
					end
					if type(mercData.activeSlot) == "table" then
						mercState.activeSlot.bloodType = mercData.activeSlot.bloodType
						mercState.activeSlot.endsAt   = tonumber(mercData.activeSlot.endsAt) or 0
					end
					mercState.researchPoints = tonumber(mercData.researchPoints) or 0
					if type(mercData.traitEffect) == "table" then
						mercState.traitEffect.rareMarker = tonumber(mercData.traitEffect.rareMarker) or 0
						mercState.traitEffect.mutation   = tonumber(mercData.traitEffect.mutation)   or 0
						mercState.traitEffect.fullGenome = tonumber(mercData.traitEffect.fullGenome) or 0
					end
					if type(mercData.stats) == "table" then
						mercState.stats.strength      = tonumber(mercData.stats.strength)      or 0
						mercState.stats.speed         = tonumber(mercData.stats.speed)         or 0
						mercState.stats.luck          = tonumber(mercData.stats.luck)          or 0
						mercState.stats.level         = tonumber(mercData.stats.level)         or 1
						mercState.stats.upgradePoints = tonumber(mercData.stats.upgradePoints) or 0
					end
					loaded[mercName] = mercState
				end
			end
		end
	end
	states[player] = loaded
	return loaded
end

local function saveState(player)
	local playerState = states[player]
	if not playerState or not dnaStore then return end
	local saveData = {}
	for mercName, mercState in pairs(playerState) do
		saveData[mercName] = {
			fragments = mercState.fragments,
			activeSlot = {
				bloodType = mercState.activeSlot.bloodType,
				endsAt    = mercState.activeSlot.endsAt,
			},
			researchPoints = mercState.researchPoints,
			traitEffect    = mercState.traitEffect,
			stats          = mercState.stats,
		}
	end
	pcall(function()
		dnaStore:SetAsync("Player_" .. player.UserId, saveData)
	end)
end

-- ─── Capsule helpers ──────────────────────────────────────────────────
local function findMatchingCapsule(player, bloodType)
	local containers = { player:FindFirstChild("Backpack"), player.Character }
	for _, container in ipairs(containers) do
		if container then
			for _, tool in container:GetChildren() do
				if tool:IsA("Tool") and tool.Name == "FullCapsule" then
					-- Lenient match: untagged capsules (created before
					-- RecruitmentSystem started stamping BloodType)
					-- count as legacy-valid for any merc the player
					-- has recruited. Keeps pre-Step-1 inventories
					-- usable without a data migration.
					local bt = tool:GetAttribute("BloodType")
					if bt == nil or bt == "" or bt == bloodType then
						return tool
					end
				end
			end
		end
	end
	return nil
end

local function giveEmptyCapsule(player)
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end
	local template = ReplicatedStorage:FindFirstChild("EmptyCapsule")
		or ReplicatedStorage:FindFirstChild("EmptyCapsule", true)
	local tool
	if template and template:IsA("Tool") then
		tool = template:Clone()
	else
		tool = Instance.new("Tool")
		tool.Name = "EmptyCapsule"
		tool.CanBeDropped = false
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(1, 1, 1)
		handle.Transparency = 1
		handle.Parent = tool
	end
	tool.Parent = backpack
	return tool
end

-- ─── RemoteEvent handler ──────────────────────────────────────────────
-- spendResearchPoint mutation deltas. One click = +EFFECT_PER_POINT
-- on the trait's effect %, capped at 100. Costs 1 research point.
local EFFECT_PER_POINT = 5
local TRAIT_UNLOCK_PCT = { rareMarker = 70, mutation = 85, fullGenome = 100 }

dnaEvent.OnServerEvent:Connect(function(player, action, mercName, ...)
	if typeof(action) ~= "string" then return end
	if typeof(mercName) ~= "string" or mercName == "" then return end

	-- Only mercs the player has recruited are valid targets.
	local mercFolder = player:FindFirstChild("Mercenaries")
	if not mercFolder or not mercFolder:FindFirstChild(mercName) then return end

	local mercState = getOrCreateMercState(player, mercName)

	if action == "getState" then
		dnaEvent:FireClient(player, "state", mercName, snapshotMerc(mercState))

	elseif action == "insertBlood" then
		-- Reject if the slot is still running a study.
		if (mercState.activeSlot.endsAt or 0) > os.time() then
			dnaEvent:FireClient(player, "insertFailed", mercName, "busy")
			return
		end

		local capsule = findMatchingCapsule(player, mercName)
		if not capsule then
			dnaEvent:FireClient(player, "insertFailed", mercName, "noSample")
			return
		end

		capsule:Destroy()
		giveEmptyCapsule(player)
		mercState.activeSlot.bloodType = mercName
		mercState.activeSlot.endsAt    = os.time() + STUDY_DURATION
		dnaEvent:FireClient(player, "state", mercName, snapshotMerc(mercState))

	elseif action == "spendResearchPoint" then
		-- Args: (mercName, traitKey). Bumps the named trait's effect %
		-- by EFFECT_PER_POINT (capped at 100), at a cost of 1 research
		-- point. Refuses if the trait isn't unlocked yet (genome %
		-- below its threshold) or the player has no points to spend.
		local traitKey = (select(1, ...))
		local unlockPct = traitKey and TRAIT_UNLOCK_PCT[traitKey]
		if not unlockPct then return end
		if (mercState.researchPoints or 0) <= 0 then return end

		-- Compute genome % so we can confirm the trait is unlocked.
		local total = 0
		for i = 1, FRAGMENT_COUNT do
			total = total + (mercState.fragments[i] or 0)
		end
		local genomePct = total / FRAGMENT_COUNT
		if genomePct < unlockPct then return end

		mercState.researchPoints = mercState.researchPoints - 1
		local current = mercState.traitEffect[traitKey] or 0
		mercState.traitEffect[traitKey] = math.min(100, current + EFFECT_PER_POINT)
		dnaEvent:FireClient(player, "state", mercName, snapshotMerc(mercState))
	end
end)

-- ─── Player lifecycle ─────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	loadState(player)
end)

Players.PlayerRemoving:Connect(function(player)
	saveState(player)
	states[player] = nil
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		saveState(player)
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTO_SAVE_INTERVAL)
		for _, player in Players:GetPlayers() do
			task.spawn(saveState, player)
		end
	end
end)

-- ─── Study tick ───────────────────────────────────────────────────────
-- Scans every TICK_INTERVAL seconds for merc slots whose endsAt has
-- elapsed. Each finished study picks a uniform-random fragment and
-- adds STUDY_FILL_PCT (clamped at 100). The active slot is cleared so
-- the client UI knows it's safe to insert another sample, and a
-- 'studyComplete' event is fired so the client can animate the
-- specific fragment that advanced (plus 'state' carries the full
-- snapshot for anything that diffs).
--
-- Bar-completion rewards (stats / level / upgrade point / research
-- point) land in Step 4 — see the TODO at `wasFull` below.

local function applyStudyTick(player, mercName, mercState)
	-- User-spec advance rule:
	--   * F01 is the "first strip". While it is below 100 % every study
	--     adds FIRST_BAR_FILL_PCT (10 %) to F01 specifically → 10 studies
	--     to fill the first bar.
	--   * Once F01 is full, every study picks a uniform-random bar from
	--     the remaining-unfilled F02..F06 and adds LATER_BAR_FILL_PCT
	--     (5 %) → 20 studies to fill each of the other bars.
	--   * When every bar is at 100 % the helix is fully decoded; we
	--     still fire a snapshot so the client can reflect the RP /
	--     stat gains but no fragment moves.
	local idx
	local delta
	if (mercState.fragments[1] or 0) < 100 then
		idx   = 1
		delta = FIRST_BAR_FILL_PCT
	else
		local candidates = {}
		for i = 2, FRAGMENT_COUNT do
			if (mercState.fragments[i] or 0) < 100 then
				table.insert(candidates, i)
			end
		end
		if #candidates > 0 then
			idx   = candidates[math.random(1, #candidates)]
			delta = LATER_BAR_FILL_PCT
		end
	end

	local before, after = 0, 0
	if idx then
		before = mercState.fragments[idx] or 0
		after  = math.clamp(before + delta, 0, 100)
		mercState.fragments[idx] = after
	end

	mercState.activeSlot.bloodType = nil
	mercState.activeSlot.endsAt    = 0

	-- Per-tick stat bump — rolled random inside the section the bar
	-- lives in. No-op when the helix is already fully decoded (idx nil).
	local statName, statDelta
	if idx then
		statName  = SECTION_STAT[idx] or "strength"
		statDelta = math.random(STAT_TICK_MIN, STAT_TICK_MAX)
		mercState.stats[statName] = (mercState.stats[statName] or 0) + statDelta
	end

	-- +1 research point per *study completion*, not per bar completion.
	-- User spec: "Points are awarded immediately after the study is
	-- completed, at the end of the time".
	mercState.researchPoints = (mercState.researchPoints or 0) + 1

	-- Level + upgrade point still fire only when a bar hits 100 %.
	local barCompleted = idx ~= nil and (before < 100 and after >= 100)
	if barCompleted then
		mercState.stats.level         = (mercState.stats.level or 1) + 1
		mercState.stats.upgradePoints = (mercState.stats.upgradePoints or 0) + 1
	end

	local snapshot = snapshotMerc(mercState)
	dnaEvent:FireClient(player, "studyComplete", mercName, idx, snapshot, {
		statName     = statName,
		statDelta    = statDelta,
		barCompleted = barCompleted,
	})
	dnaEvent:FireClient(player, "state", mercName, snapshot)
end

task.spawn(function()
	while true do
		task.wait(TICK_INTERVAL)
		local now = os.time()
		for player, playerState in pairs(states) do
			if player.Parent then
				for mercName, mercState in pairs(playerState) do
					local slot = mercState.activeSlot
					if slot and slot.endsAt and slot.endsAt > 0 and slot.endsAt <= now then
						-- pcall so a single merc's tick error doesn't kill
						-- the whole loop for every other player.
						local ok, err = pcall(applyStudyTick, player, mercName, mercState)
						if not ok then
							warn("[DNAResearch] tick error for", player.Name, mercName, err)
							-- Still clear the slot so we don't re-enter the
							-- error every second.
							mercState.activeSlot.bloodType = nil
							mercState.activeSlot.endsAt    = 0
						end
					end
				end
			end
		end
	end
end)

-- ─── Exports for Step 3 / Step 4 and the DNAStudyPage client ──────────
_G.GetDNAResearchMercState = function(player, mercName)
	if not player or not mercName then return nil end
	return getOrCreateMercState(player, mercName)
end

_G.FireDNAResearchState = function(player, mercName)
	if not player or not mercName then return end
	local mercState = getOrCreateMercState(player, mercName)
	dnaEvent:FireClient(player, "state", mercName, snapshotMerc(mercState))
end

_G.SnapshotDNAResearch = snapshotMerc
