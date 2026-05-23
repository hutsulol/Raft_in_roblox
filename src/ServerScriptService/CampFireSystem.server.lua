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
local ADD_COOLDOWN    = 0.2   -- min seconds between feeding logs

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
local function playDropSound(state)
	local template = state.dropSound
	if not template then return end
	-- Clone so rapid feeds overlap cleanly instead of cutting each other.
	local clone = template:Clone()
	clone.Parent = template.Parent
	clone:Play()
	clone.Ended:Once(function() clone:Destroy() end)
	-- Fallback cleanup in case Ended never fires (asset not loaded).
	task.delay((clone.TimeLength > 0 and clone.TimeLength or 3) + 1, function()
		if clone and clone.Parent then clone:Destroy() end
	end)
end

local function addLog(state, player)
	if state.logsAdded >= MAX_LOGS then return end

	-- Throttle feeds so a held / spammed E can't dump every log in a
	-- single frame.
	local now = os.clock()
	if now - (state.lastAddAt or 0) < ADD_COOLDOWN then return end

	local inv = _G.GetInventory and _G.GetInventory(player) or {}
	if (inv.Log or 0) < 1 then return end

	state.lastAddAt = now

	if _G.RemoveResourceFromInventory then
		_G.RemoveResourceFromInventory(player, "Log", 1)
	else
		inv.Log = (inv.Log or 0) - 1
	end
	if _G.SendInventory then _G.SendInventory(player) end

	playDropSound(state)

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
	-- Two sounds: the looped "Drop Log" one-shot at the model root, and
	-- the looped burning sound ("Camp Fire") inside the Fire part — tell
	-- them apart by name so we don't fade the wrong one.
	local fireParticle, smoke, pointLight, sound, dropSound
	for _, d in model:GetDescendants() do
		if not fireParticle and d:IsA("ParticleEmitter") and d.Name == "FireParticle" then
			fireParticle = d
		elseif not smoke and d:IsA("Smoke") then
			smoke = d
		elseif not pointLight and d:IsA("Light") then
			pointLight = d
		elseif d:IsA("Sound") then
			if d.Name == "Drop Log" then
				dropSound = d
			elseif not sound then
				sound = d
			end
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
		dropSound    = dropSound,
		lastAddAt    = 0,
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

-- ═══════════════════════════════════════════════════════════════════
-- COOKING
-- A dropped fish (any item carrying both a "raw" and a "cooked" Decal)
-- left inside a LIT campfire's bounds cooks over COOK_TIME. On
-- completion the raw decal cross-fades into the cooked one, the fish
-- is flagged Cooked (its authored wiggle Script reads this attribute
-- to stop flopping), and its ResourceType flips to the "_Cooked"
-- variant so picking it up yields the edible cooked fish.
-- ═══════════════════════════════════════════════════════════════════
local CollectionService = game:GetService("CollectionService")

local COOK_TIME      = 10    -- seconds in the heat to finish
local COOK_FADE      = 1     -- decal cross-fade duration
local COOK_POLL      = 0.5   -- detection cadence
local COOK_ZONE_PAD  = 3     -- vertical slack above/below the model bbox
local COOKED_SUFFIX  = "_Cooked"

local cookProgress = {}  -- [droppedModel] = seconds accumulated in heat

local function findFishDecals(model)
	local raw, cooked
	for _, d in model:GetDescendants() do
		if d:IsA("Decal") then
			if d.Name == "raw" then raw = d
			elseif d.Name == "cooked" then cooked = d end
		end
	end
	return raw, cooked
end

local function itemPosition(item)
	if item:IsA("BasePart") then return item.Position end
	if item:IsA("Model") then
		local ok, cf = pcall(function() return item:GetPivot() end)
		if ok then return cf.Position end
	end
	return nil
end

-- Bounds of every campfire that's actually burning (≥1 live log).
local function litCampfireZones()
	local zones = {}
	for model, state in pairs(states) do
		if model.Parent and state.logsAdded >= 1 then
			local cf, size = model:GetBoundingBox()
			table.insert(zones, { cf = cf, half = size * 0.5 })
		end
	end
	return zones
end

local function posInZones(pos, zones)
	for _, z in zones do
		local rel = z.cf:PointToObjectSpace(pos)
		if math.abs(rel.X) <= z.half.X
			and math.abs(rel.Z) <= z.half.Z
			and math.abs(rel.Y) <= z.half.Y + COOK_ZONE_PAD then
			return true
		end
	end
	return false
end

local function cookFish(model, raw, cooked)
	model:SetAttribute("Cooked", true)  -- authored wiggle Script stops on this

	if cooked then
		cooked.Transparency = 1
		TweenService:Create(cooked, TweenInfo.new(COOK_FADE, Enum.EasingStyle.Linear),
			{ Transparency = 0 }):Play()
	end
	if raw then
		TweenService:Create(raw, TweenInfo.new(COOK_FADE, Enum.EasingStyle.Linear),
			{ Transparency = 1 }):Play()
	end

	-- Flip the resource so pickup yields the edible cooked variant.
	local resType = model:GetAttribute("ResourceType")
	if typeof(resType) == "string" and resType:sub(-#COOKED_SUFFIX) ~= COOKED_SUFFIX then
		model:SetAttribute("ResourceType", resType .. COOKED_SUFFIX)
	end
end

local COOK_DEBUG = true  -- flip off once cooking is verified

task.spawn(function()
	while true do
		task.wait(COOK_POLL)
		local zones = litCampfireZones()

		for _, item in CollectionService:GetTagged("DroppedItem") do
			if not item.Parent then
				cookProgress[item] = nil
			elseif not item:GetAttribute("Cooked") then
				local raw, cooked = findFishDecals(item)
				if raw and cooked then
					local pos = itemPosition(item)
					local inZone = pos ~= nil and #zones > 0 and posInZones(pos, zones)
					if COOK_DEBUG then
						print(string.format("%s cook-check %q: litZones=%d hasDecals=true inZone=%s progress=%.1f",
							LOG_TAG, item.Name, #zones, tostring(inZone), cookProgress[item] or 0))
					end
					if inZone then
						local t = (cookProgress[item] or 0) + COOK_POLL
						if t >= COOK_TIME then
							cookProgress[item] = nil
							cookFish(item, raw, cooked)
							if COOK_DEBUG then print(LOG_TAG .. " COOKED " .. item.Name) end
						else
							cookProgress[item] = t
						end
					end
				elseif COOK_DEBUG and (item.Name:lower():find("fish")) then
					print(string.format("%s %q is a fish but missing decals (raw=%s cooked=%s)",
						LOG_TAG, item.Name, tostring(raw ~= nil), tostring(cooked ~= nil)))
				end
			end
		end
	end
end)

