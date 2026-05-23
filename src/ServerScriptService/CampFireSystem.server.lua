-- CampFireSystem.server.lua
-- Placement + fuel/burn mechanics for the FireCamp campfire.
--
-- FireCamp template (cloned from ReplicatedStorage on placement):
--   FireCamp (Model)
--     ├─ Logs_work (Model)
--     │    ├─ log_1 / log_2 / log_3 / log_last   (each: Union + Part)
--     │    └─ Fire (BasePart)
--     │         ├─ FireParticle (ParticleEmitter)
--     │         ├─ PointLight  (PointLight)
--     │         └─ Smoke       (Smoke)
--     ├─ Logs_ne_work (Model)  -- burned-out logs (MeshParts)
--     ├─ Rocks (Model)         -- ring of "rock" parts
--     └─ Bottom (BasePart)     -- soot, permanent after first burnout
--
-- Lifecycle:
--   * Placed → only Rocks visible. Logs/burned-logs/Bottom hidden, no
--     fire/smoke/light.
--   * Feed a Log (E) → next work-log appears, fire/smoke/light scale
--     with the live log count, shared burn timer extends.
--   * Burn timer hits 0 → ALL logs vanish at once, Bottom soot turns
--     permanent, Logs_ne_work (burned model) shows, light/smoke drop
--     to the smouldering ember baseline.
--   * Feed again after burnout → burned model hides, count restarts
--     from the logs the player adds.

local rs      = game:GetService("ReplicatedStorage")
local Players  = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local cupActionEvent = rs:WaitForChild("CupAction")

local LOG_TAG = "[CampFire]"

-- ─── Tunables ─────────────────────────────────────────────────────
local MAX_LOGS        = 4
local LOG_BASE_TIME   = 20    -- seconds a single fresh log burns
local MAX_BONUS       = 10    -- +50% of base when topping up a dying fire
local BONUS_THRESHOLD = 20    -- remaining < this → proportional bonus
local GROWTH_PER_LOG  = 0.4   -- +40% intensity per extra log
local TICK            = 0.5   -- burn-timer resolution
local PROMPT_RANGE    = 12

-- Visual baseline @ 1 log.
local SMOKE_OPACITY_BASE = 0.1
local SMOKE_SIZE_BASE    = 0.16
local FIRE_BRIGHT_BASE   = 0.085
local LIGHT_BRIGHT_BASE  = 0.3
local LIGHT_RANGE_BASE   = 8
local LIGHT_COLOR_ON     = Color3.fromRGB(255, 188, 20)  -- #ffbc14 lively flame

-- Smouldering aftermath (burned out, 0 logs).
local SMOKE_OPACITY_OUT = 0.1
local SMOKE_SIZE_OUT    = 0.12
local LIGHT_BRIGHT_OUT  = 0.2
local LIGHT_RANGE_OUT   = 6
local LIGHT_COLOR_OUT   = Color3.fromRGB(171, 76, 28)    -- #ab4c1c dim embers

-- Burning-sound reach. RollOffMaxDistance @ 1 log, growing with the
-- same +40%/log curve so a roaring fire is heard from further away.
local SOUND_DIST_BASE = 60
local SOUND_FADE_IN   = 1.5   -- volume ramp when the fire lights
local SOUND_FADE_OUT  = 2.0   -- volume ramp when the fire dies

local ORIG_ATTR = "CampFireOrigTransparency"

local states = {}  -- [model] = state

-- ─── Part helpers ─────────────────────────────────────────────────
local function collectBaseParts(parent)
	local out = {}
	if parent then
		for _, d in parent:GetDescendants() do
			if d:IsA("BasePart") then table.insert(out, d) end
		end
		if parent:IsA("BasePart") then table.insert(out, parent) end
	end
	return out
end

local function cacheOriginals(parts)
	for _, p in parts do
		if p:GetAttribute(ORIG_ATTR) == nil then
			p:SetAttribute(ORIG_ATTR, p.Transparency)
		end
	end
end

local function shownTransparency(p)
	-- Preserve an authored semi-transparency, but if the part was
	-- saved fully invisible (author pre-hid it), "shown" means opaque.
	local o = p:GetAttribute(ORIG_ATTR)
	if o == nil or o >= 1 then return 0 end
	return o
end

local function setHidden(parts, hidden)
	for _, p in parts do
		p.Transparency = hidden and 1 or shownTransparency(p)
	end
end

-- ─── Burning-sound fade / reach ──────────────────────────────────
local function updateSound(state)
	local sound = state.sound
	if not sound then return end

	if state.soundTween then
		state.soundTween:Cancel()
		state.soundTween = nil
	end

	if state.logsAdded >= 1 then
		-- Fade up to full volume and push the audible range out with
		-- the log count. If it wasn't already going, start it silent
		-- so the ramp is from zero (smooth light-up).
		local factor = 1 + GROWTH_PER_LOG * (state.logsAdded - 1)
		sound.Looped = true
		if not sound.IsPlaying then
			sound.Volume = 0
			sound:Play()
		end
		state.soundTween = TweenService:Create(
			sound,
			TweenInfo.new(SOUND_FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Volume = state.soundFullVolume, RollOffMaxDistance = SOUND_DIST_BASE * factor }
		)
		state.soundTween:Play()
	elseif sound.IsPlaying then
		-- Fire died: ease the volume down rather than cutting it, then
		-- stop — but only if the player didn't re-light mid-fade.
		local tween = TweenService:Create(
			sound,
			TweenInfo.new(SOUND_FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Volume = 0 }
		)
		state.soundTween = tween
		tween:Play()
		tween.Completed:Connect(function()
			if state.logsAdded == 0 and sound.Volume <= 0.001 then
				sound:Stop()
			end
		end)
	end
end

-- ─── Visual state application ─────────────────────────────────────
local function applyVisuals(state)
	local n = state.logsAdded

	-- Work logs: first n visible, rest hidden.
	for i, parts in ipairs(state.logParts) do
		setHidden(parts, i > n)
	end

	-- Rocks: always visible.
	setHidden(state.rockParts, false)

	-- Bottom soot: visible only once the fire has burned out at least once.
	setHidden(state.bottomParts, not state.burnedOnce)

	-- Burned-logs model: only during the smouldering aftermath.
	local aftermath = (n == 0 and state.burnedOnce)
	setHidden(state.burnedParts, not aftermath)

	-- Hide the "Add Log" prompt once the fire is at max capacity;
	-- bring it back when there's room again (after a burnout resets
	-- the count, or a re-light cycle begins).
	if state.prompt then
		state.prompt.Enabled = (state.logsAdded < MAX_LOGS)
	end

	-- Fire / smoke / light.
	if n >= 1 then
		local factor = 1 + GROWTH_PER_LOG * (n - 1)
		if state.fireParticle then
			state.fireParticle.Enabled    = true
			state.fireParticle.Brightness = FIRE_BRIGHT_BASE * factor
		end
		if state.smoke then
			state.smoke.Enabled = true
			state.smoke.Opacity = SMOKE_OPACITY_BASE * factor
			state.smoke.Size    = SMOKE_SIZE_BASE * factor
		end
		if state.pointLight then
			state.pointLight.Enabled    = true
			state.pointLight.Brightness = LIGHT_BRIGHT_BASE * factor
			state.pointLight.Range      = LIGHT_RANGE_BASE * factor
			state.pointLight.Color      = LIGHT_COLOR_ON
		end
	elseif aftermath then
		-- Embers: no flame, faint smoke, dim glow.
		if state.fireParticle then state.fireParticle.Enabled = false end
		if state.smoke then
			state.smoke.Enabled = true
			state.smoke.Opacity = SMOKE_OPACITY_OUT
			state.smoke.Size    = SMOKE_SIZE_OUT
		end
		if state.pointLight then
			state.pointLight.Enabled    = true
			state.pointLight.Brightness = LIGHT_BRIGHT_OUT
			state.pointLight.Range      = LIGHT_RANGE_OUT
			state.pointLight.Color      = LIGHT_COLOR_OUT
		end
	else
		-- Fresh, never lit: everything off.
		if state.fireParticle then state.fireParticle.Enabled = false end
		if state.smoke then state.smoke.Enabled = false end
		if state.pointLight then state.pointLight.Enabled = false end
	end

	updateSound(state)
end

-- ─── Burn timer ───────────────────────────────────────────────────
local function burnout(state)
	state.burning    = false
	state.remaining  = 0
	state.logsAdded  = 0
	state.burnedOnce = true
	applyVisuals(state)
end

local function ensureBurnLoop(state)
	if state.burning then return end
	state.burning = true
	state.loopId  = state.loopId + 1
	local myId = state.loopId
	task.spawn(function()
		while state.burning and state.loopId == myId and state.model.Parent do
			task.wait(TICK)
			if not (state.burning and state.loopId == myId and state.model.Parent) then
				break
			end
			state.remaining = state.remaining - TICK
			if state.remaining <= 0 then
				burnout(state)
				break
			end
		end
	end)
end

-- ─── Feed a log ───────────────────────────────────────────────────
local function addLog(state, player)
	if state.logsAdded >= MAX_LOGS then return end

	local inv = _G.GetInventory and _G.GetInventory(player) or {}
	if (inv.Log or 0) < 1 then return end

	if _G.RemoveResourceFromInventory then
		_G.RemoveResourceFromInventory(player, "Log", 1)
	else
		inv.Log = (inv.Log or 0) - 1
	end
	if _G.SendInventory then _G.SendInventory(player) end

	-- Contribution: a fresh start (no live fire) burns the flat base.
	-- Topping up a dying fire converts the log into up to +50% so a
	-- last-second log buys ~30 s instead of 20.
	local contribution
	if state.remaining <= 0 then
		contribution = LOG_BASE_TIME
	else
		local bonus = MAX_BONUS * math.clamp((BONUS_THRESHOLD - state.remaining) / BONUS_THRESHOLD, 0, 1)
		contribution = LOG_BASE_TIME + bonus
	end

	state.remaining = state.remaining + contribution
	state.logsAdded = state.logsAdded + 1
	applyVisuals(state)
	ensureBurnLoop(state)
end

-- ─── Setup a placed / pre-existing campfire ───────────────────────
local function setupCampFire(model)
	if states[model] then return end

	local logsWork = model:FindFirstChild("Logs_work")
	local logsNe   = model:FindFirstChild("Logs_ne_work")
	local rocks    = model:FindFirstChild("Rocks")
	local bottom   = model:FindFirstChild("Bottom")

	-- Ordered work logs.
	local logParts = {}
	if logsWork then
		for _, name in {"log_1", "log_2", "log_3", "log_last"} do
			local m = logsWork:FindFirstChild(name)
			if m then
				table.insert(logParts, collectBaseParts(m))
			end
		end
	end

	local rockParts   = collectBaseParts(rocks)
	local burnedParts = collectBaseParts(logsNe)
	local bottomParts = collectBaseParts(bottom)

	-- Effects (search the whole model so authoring depth doesn't matter).
	local fireParticle, smoke, pointLight, sound
	for _, d in model:GetDescendants() do
		if not fireParticle and d:IsA("ParticleEmitter") and d.Name == "FireParticle" then
			fireParticle = d
		elseif not smoke and d:IsA("Smoke") then
			smoke = d
		elseif not pointLight and d:IsA("Light") then
			pointLight = d
		elseif not sound and d:IsA("Sound") then
			sound = d
		end
	end
	-- Loose fallback: any ParticleEmitter if none was literally named FireParticle.
	if not fireParticle then
		for _, d in model:GetDescendants() do
			if d:IsA("ParticleEmitter") then fireParticle = d break end
		end
	end

	-- Capture the authored volume as the fade-in target, then mute +
	-- stop so a fresh campfire is silent until the first log lights it.
	local soundFullVolume = 0.5
	if sound then
		soundFullVolume = (sound.Volume > 0) and sound.Volume or 0.5
		sound.Looped = true
		sound.Volume = 0
		sound:Stop()
	end

	for _, parts in logParts do cacheOriginals(parts) end
	cacheOriginals(rockParts)
	cacheOriginals(burnedParts)
	cacheOriginals(bottomParts)

	local state = {
		model        = model,
		logsAdded    = 0,
		remaining    = 0,
		burning      = false,
		burnedOnce   = false,
		loopId       = 0,
		logParts     = logParts,
		rockParts    = rockParts,
		burnedParts  = burnedParts,
		bottomParts  = bottomParts,
		fireParticle = fireParticle,
		smoke        = smoke,
		pointLight   = pointLight,
		sound        = sound,
		soundFullVolume = soundFullVolume,
	}
	states[model] = state

	-- Prompt on the centre-most part (Bottom preferred, then PrimaryPart).
	local anchor = bottom
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	if anchor then
		local prompt = anchor:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Parent = anchor
		end
		prompt.ActionText            = "Add Log"
		prompt.ObjectText            = "Campfire"
		prompt.KeyboardKeyCode       = Enum.KeyCode.E
		prompt.HoldDuration          = 0
		prompt.MaxActivationDistance = PROMPT_RANGE
		prompt.RequiresLineOfSight   = false
		prompt.Enabled               = true
		state.prompt = prompt
		prompt.Triggered:Connect(function(player)
			addLog(state, player)
		end)
	else
		warn(LOG_TAG .. " no BasePart anchor for prompt under " .. model:GetFullName())
	end

	-- Initial look: rocks only.
	applyVisuals(state)

	model.AncestryChanged:Connect(function()
		if not model.Parent then states[model] = nil end
	end)

	print(string.format("%s ready at %s | logs=%d rocks=%d burned=%d",
		LOG_TAG, model:GetFullName(), #logParts, #rockParts, #burnedParts))
end

-- ─── Placement (mirrors the Furnace flow) ─────────────────────────
cupActionEvent.OnServerEvent:Connect(function(player, action, target)
	if action ~= "placeCampFire" then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "FireCamp" then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end
	if typeof(target) ~= "CFrame" then return end

	local template = rs:FindFirstChild("FireCamp")
	if not template then
		warn(LOG_TAG .. " ReplicatedStorage.FireCamp template missing")
		return
	end

	local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

	local model = template:Clone()
	model.Name = "FireCamp"
	for _, d in model:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
	end

	if model:IsA("Model") and not model.PrimaryPart then
		local bbCF = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(bbCF.Position)
	end
	model:PivotTo(worldCF)
	model.Parent = raft

	-- Weld to the raft while anchored, then restore velocity (same
	-- handshake the Furnace placement uses to avoid momentum loss).
	local primary = raft.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then p.Anchored = true end
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = p
			weld.Part1 = primary
			weld.Parent = p
		end
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then p.Anchored = false end
	end
	primary.AssemblyLinearVelocity  = linVel
	primary.AssemblyAngularVelocity = angVel

	setupCampFire(model)
	tool:Destroy()
end)

-- ─── Adopt any campfires already in the world at boot ─────────────
for _, child in workspace:GetDescendants() do
	if child:IsA("Model") and child.Name == "FireCamp" then
		setupCampFire(child)
	end
end
