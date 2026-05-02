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
local CollectionService = game:GetService("CollectionService")

local CHOP_TREES_GOAL = 3   -- mirror of CHOP_TREES_GOAL in
                            -- ChopTreesFlow.server.lua. Used only for
                            -- the initial render before the server's
                            -- first progress packet arrives.

-- Delay before the tooltip first appears, measured from the point the
-- player's character lands in the world. Gives the player a beat to
-- orient themselves before a UI overlay slides in.
local SHOW_DELAY_SECONDS = 5

-- Resolves once the LocalPlayer's character has spawned at least once.
-- Used to anchor SHOW_DELAY_SECONDS to a real "player appears" moment
-- instead of the LocalScript's first tick (which can be seconds
-- before the character even loads).
local function waitForCharacter()
	if Players.LocalPlayer.Character then return end
	Players.LocalPlayer.CharacterAdded:Wait()
end

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

-- ─── Green log highlights (chop-trees flow only) ─────────────────────
-- While the tooltip is up, every floating Log in the workspace gets a
-- green Highlight so the player can spot them at a glance. ResourceSpawner
-- tags every spawned resource model with "Resource" + sets a ResourceType
-- attribute, so we listen on CollectionService and filter by attribute.
-- Highlights are parented to the resource itself — when ResourceSpawner
-- destroys the model on harvest the Highlight goes with it, no manual
-- cleanup needed for the per-log case.

local LOG_HIGHLIGHT_NAME = "OnboardingChopTreesHighlight"
local LOG_ARROW_NAME     = "OnboardingChopTreesArrow"
local LOG_HIGHLIGHT_FILL    = Color3.fromRGB(120, 220,  90)
local LOG_HIGHLIGHT_OUTLINE = Color3.fromRGB(180, 255, 140)

-- Green floating arrow above each Log (added in the same lifetime as
-- the green Highlight). Asset is the arrow_green icon the project
-- registered. Y offset puts it ~2 studs above the log so it's
-- visible without overlapping the Highlight outline.
--
-- Size uses the Scale dimension of UDim2 (studs in 3D space), not
-- Offset (fixed pixels). Stud-based sizing means the arrow shrinks
-- with distance instead of staying at a constant screen size — at a
-- distance the old pixel-sized 48×48 dwarfed the now-tiny log.
local LOG_ARROW_ASSET    = "rbxassetid://74129628763110"
local LOG_ARROW_SIZE     = UDim2.fromScale(2, 2)   -- 2x2 studs
local LOG_ARROW_OFFSET_Y = 6.0   -- raised so the arrow clears the log

local logHighlightAddedConn   -- CollectionService:GetInstanceAddedSignal handle
local logArrowBobConn         -- RunService:Heartbeat handle for the bob animation

local function isLogResource(resource)
	if not resource then return false end
	-- Resource models are tagged on the Model itself; the Log type
	-- check on the same node confirms we're not lighting up Plastic
	-- canisters or future resource types.
	return resource:GetAttribute("ResourceType") == "Log"
end

local function tryHighlightLog(resource)
	if not isLogResource(resource) then return end
	if resource:FindFirstChild(LOG_HIGHLIGHT_NAME) then return end
	local hl = Instance.new("Highlight")
	hl.Name = LOG_HIGHLIGHT_NAME
	-- Edge-only treatment: full FillTransparency, opaque outline.
	-- A filled highlight tinted the whole log green, which read as a
	-- "this is a green item" indicator instead of a tactical glow.
	hl.FillTransparency = 1
	hl.OutlineColor = LOG_HIGHLIGHT_OUTLINE
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = resource
	hl.Parent = resource
end

-- Use the model's PrimaryPart as the centre reference — the log's
-- PrimaryPart is set at its visual middle, and the previous bbox-
-- based picker was throwing the arrow off-axis because invisible
-- helper parts in the model dragged the bbox centre to one side.
-- Falls back to the first BasePart we find for malformed resources
-- without a PrimaryPart.
local function pickArrowAdornee(resource)
	if resource:IsA("BasePart") then return resource end
	if resource.PrimaryPart then return resource.PrimaryPart end
	for _, child in ipairs(resource:GetDescendants()) do
		if child:IsA("BasePart") then return child end
	end
	return nil
end

local function tryAddArrow(resource)
	if not isLogResource(resource) then return end
	if resource:FindFirstChild(LOG_ARROW_NAME) then return end
	local adornee = pickArrowAdornee(resource)
	if not adornee then return end

	-- The log model's PrimaryPart is at its visual centre, so we
	-- adornee directly — no centre compensation needed. Just push
	-- the billboard up by LOG_ARROW_OFFSET_Y studs in world space
	-- so the arrow sits above the log instead of on it.
	local bb = Instance.new("BillboardGui")
	bb.Name = LOG_ARROW_NAME
	bb.Adornee = adornee
	bb.Size = LOG_ARROW_SIZE
	bb.StudsOffsetWorldSpace = Vector3.new(0, LOG_ARROW_OFFSET_Y, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 250
	bb.ResetOnSpawn = false
	bb.Parent = resource

	local img = Instance.new("ImageLabel")
	img.Name = "Arrow"
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	img.Image = LOG_ARROW_ASSET
	img.Parent = bb
end

local function sweepArrows()
	for _, resource in ipairs(CollectionService:GetTagged("Resource")) do
		local arrow = resource:FindFirstChild(LOG_ARROW_NAME)
		if arrow then arrow:Destroy() end
	end
end

local function startLogHighlights()
	-- Tag every Log already in the world.
	for _, resource in ipairs(CollectionService:GetTagged("Resource")) do
		tryHighlightLog(resource)
		tryAddArrow(resource)
	end
	-- And every Log that spawns while the flow is active. The
	-- ResourceType attribute is set before the model is parented +
	-- tagged, so it's available by the time this signal fires.
	if not logHighlightAddedConn then
		logHighlightAddedConn = CollectionService:GetInstanceAddedSignal("Resource"):Connect(function(r)
			tryHighlightLog(r)
			tryAddArrow(r)
		end)
	end

	-- Gentle vertical bob so the arrows visually pulse instead of
	-- sitting dead still — easier to spot a moving indicator on a
	-- choppy ocean. Cheap: a single sin() per arrow per frame.
	if not logArrowBobConn then
		local RunService = game:GetService("RunService")
		logArrowBobConn = RunService.Heartbeat:Connect(function()
			local t = os.clock()
			local dy = math.sin(t * 4) * 0.35
			for _, resource in ipairs(CollectionService:GetTagged("Resource")) do
				local arrow = resource:FindFirstChild(LOG_ARROW_NAME)
				if arrow and arrow:IsA("BillboardGui") then
					arrow.StudsOffsetWorldSpace = Vector3.new(0, LOG_ARROW_OFFSET_Y + dy, 0)
				end
			end
		end)
	end
end

local function stopLogHighlights()
	if logHighlightAddedConn then
		logHighlightAddedConn:Disconnect()
		logHighlightAddedConn = nil
	end
	if logArrowBobConn then
		logArrowBobConn:Disconnect()
		logArrowBobConn = nil
	end
	-- Sweep any Highlights still attached to surviving logs (a Log
	-- the player didn't chop yet stays in the workspace; we just
	-- want the green to disappear when the flow ends).
	for _, resource in ipairs(CollectionService:GetTagged("Resource")) do
		local hl = resource:FindFirstChild(LOG_HIGHLIGHT_NAME)
		if hl then hl:Destroy() end
	end
	sweepArrows()
end

local function startChopTreesTip(initialProgress)
	if activeHandles.chopTrees then return end -- already showing

	completedFlags.chopTrees = false

	-- Light up every Log in the world while this tooltip is up. Will
	-- be torn down via stopLogHighlights() in onDismiss below.
	startLogHighlights()

	activeHandles.chopTrees = _G.ShowOnboardingTip({
		id        = "chopTrees",
		eyebrow   = "HINT",
		title     = "Get the first logs",
		body      = "To break a log, click on it <b>5 times</b>.",
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
			-- Drop the green Highlights regardless of how the flow
			-- ended (manual X, auto-complete, server pushed an
			-- already-complete state on rejoin) — they're scoped to
			-- the tooltip's on-screen lifetime.
			stopLogHighlights()
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

		-- Defer the first show so the player has a few seconds to
		-- orient themselves after spawning before a UI overlay slides
		-- in. Anchored to the character's first appearance, not to
		-- this LocalScript's startup, so the delay still feels like
		-- "5 seconds after I land in the world" on slow loads.
		-- Bail in the wait if the flow has been completed/dismissed
		-- by harvest progress that arrived in the meantime, or if a
		-- prior "state" already kicked off the show.
		task.spawn(function()
			waitForCharacter()
			task.wait(SHOW_DELAY_SECONDS)
			if activeHandles.chopTrees then return end
			startChopTreesTip(flow.progress or 0)
		end)

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
