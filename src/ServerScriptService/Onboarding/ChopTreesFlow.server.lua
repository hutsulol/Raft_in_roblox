-- ChopTreesFlow.server.lua
-- Step 2B of the onboarding system: drive the first-run "Chop down
-- 3 logs" tooltip from the server side.
--
-- Inputs:
--   _G.OnQuestResource(player, resType, amount) — fired by
--     ResourceSpawner whenever a player chops down a resource.
--     DailyQuests.server.lua owns the global; we chain on top so
--     both subsystems hear every Log harvest.
--
-- Outputs (over the OnboardingFlow RemoteEvent published in Step 2A):
--   "state"               (snapshot)            — answers a client "getState" request
--   "chopTrees:progress"  (progress, goal)      — every increment
--   "chopTrees:complete"                        — fires once when progress hits goal
--
-- Listens for:
--   "getState"             — client just connected, asks for the
--                            current state so the controller can
--                            decide whether to show the tooltip.
--   "chopTrees:dismiss"    — user clicked X. Persist the dismissed
--                            flag so we don't re-show on rejoin.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local CHOP_TREES_GOAL = 3   -- logs required before the tooltip auto-completes

-- The State script publishes the RemoteEvent and the helper API on
-- _G — wait for them. The State script lives next to this file in
-- ServerScriptService/Onboarding/, so in practice they're parsed in
-- the same frame; the wait guards against any future re-ordering.
local function waitForOnboardingApi(timeout)
	local deadline = os.clock() + (timeout or 5)
	while os.clock() < deadline do
		if _G.OnboardingFlowEvent and _G.GetOnboardingState then
			return true
		end
		task.wait(0.1)
	end
	return false
end

if not waitForOnboardingApi(5) then
	warn("[ChopTreesFlow] OnboardingState API didn't appear within 5 s; flow disabled")
	return
end

local event = _G.OnboardingFlowEvent

-- Increment the player's chopTrees progress and broadcast it. No-op
-- for players who already finished or dismissed the flow so a late
-- harvest doesn't re-open the tooltip.
local function onLogHarvested(player, amount)
	local state = _G.GetOnboardingState(player)
	if not state then return end
	local flow = state.chopTrees
	if not flow then return end
	if flow.completed or flow.dismissed then return end

	amount = (type(amount) == "number" and amount > 0) and amount or 1
	local newProgress = math.min(CHOP_TREES_GOAL, (flow.progress or 0) + amount)
	if newProgress == flow.progress then return end
	flow.progress = newProgress

	_G.MarkOnboardingDirty(player)
	event:FireClient(player, "chopTrees:progress", flow.progress, CHOP_TREES_GOAL)

	if flow.progress >= CHOP_TREES_GOAL then
		flow.completed = true
		_G.MarkOnboardingDirty(player)
		-- Persist immediately on completion so a crash-then-rejoin
		-- doesn't replay the tooltip after the user has finished.
		_G.SaveOnboardingState(player)
		event:FireClient(player, "chopTrees:complete")
	end
end

-- ─── Chain on top of any existing _G.OnQuestResource ─────────────────
-- DailyQuests.server.lua sets _G.OnQuestResource at its script init.
-- We defer the chain capture so we run AFTER every script's top-level
-- code has executed regardless of folder ordering — task.defer fires
-- at the end of the current resumption cycle, by which point all
-- ServerScriptService scripts have finished their init bodies.
task.defer(function()
	local previous = _G.OnQuestResource
	_G.OnQuestResource = function(player, resType, amount)
		-- Forward to whatever was previously hooked (DailyQuests)
		-- before running our own logic. pcall isolates a buggy peer
		-- so our chop-trees progress still ticks.
		if typeof(previous) == "function" then
			pcall(previous, player, resType, amount)
		end
		if resType == "Log" then
			pcall(onLogHarvested, player, amount or 1)
		end
	end
end)

-- ─── Client requests ──────────────────────────────────────────────────

event.OnServerEvent:Connect(function(player, action, ...)
	if typeof(action) ~= "string" then return end

	if action == "getState" then
		event:FireClient(player, "state", _G.SnapshotOnboardingState(player))

	elseif action == "chopTrees:dismiss" then
		local state = _G.GetOnboardingState(player)
		if not state or not state.chopTrees then return end
		if state.chopTrees.dismissed then return end
		state.chopTrees.dismissed = true
		_G.MarkOnboardingDirty(player)
		_G.SaveOnboardingState(player)
	end
end)

-- ─── Re-emit state to already-loaded players ─────────────────────────
-- A live-reload (Studio Play Solo, after-the-fact server script edit)
-- won't fire PlayerAdded for players already in-game — push them a
-- fresh snapshot so the client controller's "getState" round-trip
-- isn't the only way to recover.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		event:FireClient(player, "state", _G.SnapshotOnboardingState(player))
	end)
end
