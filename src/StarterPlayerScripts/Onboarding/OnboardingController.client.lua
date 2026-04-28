-- OnboardingController.client.lua
-- Step 2C of the onboarding system: bridge the OnboardingFlow
-- RemoteEvent to the _G.ShowOnboardingTip widget.
--
-- Flow today (chop-trees only):
--
--   server "state" snapshot ─────────────────────────────────────┐
--     if chopTrees.completed / dismissed → ignore                │
--     else _G.ShowOnboardingTip({ goal=3, iconKind="axe", ... }) │
--                                                                ▼
--   server "chopTrees:progress" (n, goal) ──► handle.setProgress(n)
--                                                                │
--   server "chopTrees:complete"             ──► handle.complete()
--                                                                │ (autoDismiss 1.4 s)
--   handle.onDismiss callback ──► server "chopTrees:dismiss"
--
-- Future flows slot into the same controller — `activeHandles` is a
-- map keyed by flow id so multiple flows can co-exist later (e.g.
-- chopTrees done, water flow showing).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CHOP_TREES_GOAL = 3   -- mirror of CHOP_TREES_GOAL in
                            -- ChopTreesFlow.server.lua. Used only for
                            -- the initial render before the server's
                            -- first progress packet arrives.

-- ─── Wait for the RemoteEvent + the tooltip widget API ────────────────
local event = ReplicatedStorage:WaitForChild("OnboardingFlow", 30)
if not event then
	warn("[OnboardingController] OnboardingFlow RemoteEvent missing after 30 s; controller disabled")
	return
end

local function waitForShowTip(timeout)
	local deadline = os.clock() + (timeout or 30)
	while os.clock() < deadline do
		if typeof(_G.ShowOnboardingTip) == "function" then return true end
		task.wait(0.1)
	end
	return false
end

if not waitForShowTip(30) then
	warn("[OnboardingController] _G.ShowOnboardingTip not available after 30 s; controller disabled")
	return
end

-- ─── Per-flow handles ────────────────────────────────────────────────
-- Keyed by the flow id (today only "chopTrees"). Mid-flow we hold a
-- reference to the tooltip handle so server packets can poke it.
local activeHandles = {}

-- Per-flow flag set in onComplete. We check this in onDismiss so
-- the auto-dismiss-after-complete path doesn't re-tell the server
-- "user dismissed me" — the server already saw the goal hit and
-- marked completed=true, so a redundant dismiss flag would muddy
-- the persisted state.
local completedFlags = {}

local function startChopTreesTip(initialProgress)
	if activeHandles.chopTrees then return end -- already showing

	completedFlags.chopTrees = false

	activeHandles.chopTrees = _G.ShowOnboardingTip({
		id        = "chopTrees",
		eyebrow   = "HINT",
		title     = "Chop down trees",
		body      = "Use your <b>axe</b> on a floating tree to gather <b>logs</b>.",
		iconKind  = "axe",
		goal      = CHOP_TREES_GOAL,
		progress  = initialProgress or 0,
		showClose = true,
		autoDismissAfterComplete = 1.4,

		onComplete = function()
			-- Server has already marked completed=true and persisted.
			-- Just remember so onDismiss doesn't double-report.
			completedFlags.chopTrees = true
		end,

		onDismiss = function()
			local wasComplete = completedFlags.chopTrees == true
			activeHandles.chopTrees = nil
			completedFlags.chopTrees = nil
			if not wasComplete then
				-- Manual X: tell the server so we don't show the tip
				-- again on rejoin. Idempotent; server early-outs if
				-- the dismissed flag is already set.
				event:FireServer("chopTrees:dismiss")
			end
		end,
	})
end

-- ─── Server → client dispatch ────────────────────────────────────────
event.OnClientEvent:Connect(function(action, ...)
	if typeof(action) ~= "string" then return end

	if action == "state" then
		local snap = ...
		if type(snap) ~= "table" then return end
		local flow = snap.chopTrees
		if not flow then return end
		if flow.completed or flow.dismissed then return end
		startChopTreesTip(flow.progress or 0)

	elseif action == "chopTrees:progress" then
		local progress = ...
		local handle = activeHandles.chopTrees
		if handle and handle.setProgress then
			handle.setProgress(progress)
		end

	elseif action == "chopTrees:complete" then
		local handle = activeHandles.chopTrees
		if handle and handle.complete then
			handle.complete()  -- the widget runs its celebration pop
			                   -- and auto-dismisses after 1.4 s.
		end
	end
end)

-- ─── Kick off ────────────────────────────────────────────────────────
-- ChopTreesFlow.server.lua already pushes a "state" snapshot to every
-- player it sees on init, so this round-trip is mostly insurance —
-- if our LocalScript ran before that snapshot arrived, the explicit
-- request guarantees we still get state.
event:FireServer("getState")
