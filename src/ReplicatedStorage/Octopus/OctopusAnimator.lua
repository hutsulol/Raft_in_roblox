--[[
	OctopusAnimator — layered animation for the RIGID octopus, written into
	Motor6D.Transform. No Animation assets, no rig upload, and no deformation
	of any kind.

	Nothing here scales a part and nothing here relies on skinning. Every clip
	is rigid rotation and translation of whole parts, because that is all that
	survives reliably in Roblox. An earlier version squashed the head's Size to
	fake a dent; the crown, collar and eyes are separate parts on fixed offsets,
	so they stayed put while the head shrank and visibly came off. Impact is now
	sold with WHIP instead: the fittings lag behind the body and catch up.

	Three things stack every frame, in this order:

	  drift      procedural, always on. Each tentacle swings on its own axis
	             with its own phase, so it reads as hanging in a current.
	  base       one keyframed clip at a time, crossfaded.
	  additive   any number of one-shots on top (Hit, Blink), holding DELTAS,
	             so a hit landing mid-swim adds a shove and decays to nothing.

		local a = octo.animator
		a:setBase("SwimIdle")
		a:fire("Hit")               -- safe to call a hundred times, they overlap
		RunService.Heartbeat:Connect(function(dt) a:step(dt) end)
]]

local Animator = {}
Animator.__index = Animator

local Z3 = { 0, 0, 0 }

--------------------------------------------------------------- drift --------
local DRIFT = {
	rate = 0.23,
	baseSwing = 6.0,      -- degrees at the tentacle's root joint
	tipSwing = 11.0,      -- and at its elbow
	side = 4.0,
	tipLag = 0.30,
	bob = 0.055,          -- studs the body rises and falls
	roll = 2.4,
}

------------------------------------------------------------ keyframed -------
local Clips = {}
Animator.Clips = Clips

-- Rises out of the dark. The travel is a plain translation of the root; the
-- tentacles stream DOWNWARD on the way up, because water drags them behind the
-- body rather than with it. Ends on the rest pose so SwimIdle can take over.
Clips.Emerge = {
	length = 1.7, loop = false, additive = false, driftMul = 0.45,
	flinch = { { 0, -22 }, { 0.45, -15 }, { 0.80, 4 }, { 1, 0 } },
	tracks = {
		Root = { { 0, { 0, 0, 0 }, { 0, -4.6, 0 } }, { 0.55, { -5, 0, 0 }, { 0, -0.95, 0 } },
			{ 0.80, { 4, 0, 0 }, { 0, 0.30, 0 } }, { 1, { 0, 0, 0 }, { 0, 0, 0 } } },
		crown = { { 0, { 8, 0, 0 } }, { 0.6, { -5, 0, 0 } }, { 1, { 0, 0, 0 } } },
		collar = { { 0, { 5, 0, 0 } }, { 0.7, { -2, 0, 0 } }, { 1, { 0, 0, 0 } } },
		-- comes up with its eyes shut, opens them once it is clear
		eye_l = { { 0, Z3, { 0, 0, 0.075 } }, { 0.44, Z3, { 0, 0, 0.075 } },
			{ 0.66, Z3, { 0, 0, 0 } }, { 1, Z3, { 0, 0, 0 } } },
		eye_r = { { 0, Z3, { 0, 0, 0.075 } }, { 0.44, Z3, { 0, 0, 0.075 } },
			{ 0.66, Z3, { 0, 0, 0 } }, { 1, Z3, { 0, 0, 0 } } },
	},
}

-- Almost empty on purpose: the tentacles are the drift's job.
Clips.SwimIdle = {
	length = 6.0, loop = true, additive = false,
	tracks = {
		crown = { { 0, { 0, 0, 0 } }, { 0.30, { 1.4, 0, -1.0 } },
			{ 0.65, { -1.2, 0, 1.1 } }, { 1, { 0, 0, 0 } } },
		collar = { { 0, { 0, 0, 0 } }, { 0.5, { 0.8, 0, 0 } }, { 1, { 0, 0, 0 } } },
	},
}

-- Gives up and sinks. Same drag the other way round: going down, the tentacles
-- stream UP. Eyes close on the way out.
Clips.Submerge = {
	length = 2.0, loop = false, additive = false, driftMul = 0.5,
	flinch = { { 0, 0 }, { 0.25, 10 }, { 0.70, 19 }, { 1, 23 } },
	tracks = {
		Root = { { 0, { 0, 0, 0 }, { 0, 0, 0 } }, { 0.20, { 6, 0, 0 }, { 0, 0.34, 0 } },
			{ 0.50, { -6, 0, 0 }, { 0, -1.25, 0 } },
			{ 1, { -10, 0, 0 }, { 0, -4.9, 0 } } },
		crown = { { 0, { 0, 0, 0 } }, { 0.30, { -6, 0, 0 } }, { 1, { 10, 0, 0 } } },
		collar = { { 0, { 0, 0, 0 } }, { 1, { 6, 0, 0 } } },
		eye_l = { { 0, Z3, { 0, 0, 0 } }, { 0.55, Z3, { 0, 0, 0 } },
			{ 0.82, Z3, { 0, 0, 0.075 } }, { 1, Z3, { 0, 0, 0.075 } } },
		eye_r = { { 0, Z3, { 0, 0, 0 } }, { 0.55, Z3, { 0, 0, 0 } },
			{ 0.82, Z3, { 0, 0, 0.075 } }, { 1, Z3, { 0, 0, 0.075 } } },
	},
}

-- Impact, entirely rigid. The body is shoved back on the root, and the crown,
-- collar and eyes WHIP: they swing late and overshoot on the way back. That
-- lag is what sells a hit when nothing is allowed to deform.
Clips.Hit = {
	length = 0.44, loop = false, additive = true,
	flinch = { { 0, 0 }, { 0.10, -13 }, { 0.34, 5 }, { 0.62, -2 }, { 1, 0 } },
	tracks = {
		-- The punch lives on the ROOT, where the whole body moves as one piece
		-- and no internal gap can open. The crown and collar sit flush against
		-- the mantle, so they get a few degrees of lag and nothing more.
		Root = { { 0, Z3, { 0, 0, 0 } }, { 0.08, { -9, 2, 0 }, { 0, -0.16, 0.26 } },
			{ 0.30, { 6, -1, 0 }, { 0, 0.10, -0.12 } },
			{ 0.60, { -2.5, 0, 0 }, { 0, -0.03, 0.04 } }, { 1, Z3, { 0, 0, 0 } } },
		crown = { { 0, { 0, 0, 0 } }, { 0.14, { -5, 2, 0 } }, { 0.38, { 2.5, -1, 0 } },
			{ 0.66, { -1, 0, 0 } }, { 1, { 0, 0, 0 } } },
		collar = { { 0, { 0, 0, 0 } }, { 0.12, { 3, 0, 0 } }, { 0.40, { -1.5, 0, 0 } },
			{ 1, { 0, 0, 0 } } },
		-- a hard blink on impact reads as a wince
		eye_l = { { 0, Z3, { 0, 0, 0 } }, { 0.10, Z3, { 0, 0, 0.070 } },
			{ 0.34, Z3, { 0, 0, 0.070 } }, { 0.60, Z3, { 0, 0, 0 } },
			{ 1, Z3, { 0, 0, 0 } } },
		eye_r = { { 0, Z3, { 0, 0, 0 } }, { 0.10, Z3, { 0, 0, 0.070 } },
			{ 0.34, Z3, { 0, 0, 0.070 } }, { 0.60, Z3, { 0, 0, 0 } },
			{ 1, Z3, { 0, 0, 0 } } },
	},
}

-- Nothing rotates: the eyes are pushed back into the mantle, which hides them.
Clips.Blink = {
	length = 0.20, loop = false, additive = true,
	tracks = {
		eye_l = { { 0, Z3, { 0, 0, 0 } }, { 0.35, Z3, { 0, 0, 0.075 } },
			{ 0.62, Z3, { 0, 0, 0.075 } }, { 1, Z3, { 0, 0, 0 } } },
		eye_r = { { 0, Z3, { 0, 0, 0 } }, { 0.35, Z3, { 0, 0, 0.075 } },
			{ 0.62, Z3, { 0, 0, 0.075 } }, { 1, Z3, { 0, 0, 0 } } },
	},
}

-- The last second before it comes apart. Still rigid: it shudders, the crown
-- tips off, the tentacles go slack.
Clips.BreakUp = {
	length = 0.85, loop = false, additive = false,
	-- Kept inside what the joints can hide: the tentacle sleeve holds to about
	-- 25 degrees, and the crown and collar to about 6 before the mantle's dark
	-- inside shows through. The parts fly apart a moment later anyway — this
	-- clip only has to read as a shudder, not as a collapse.
	flinch = { { 0, 0 }, { 0.40, 11 }, { 0.72, -15 }, { 1, -19 } },
	tracks = {
		Root = { { 0, Z3, { 0, 0, 0 } }, { 0.35, { 4, 5, 0 }, { 0, 0.12, 0 } },
			{ 0.62, { -7, -7, 0 }, { 0, -0.06, 0 } },
			{ 1, { -14, 10, 0 }, { 0, -0.34, 0 } } },
		crown = { { 0, { 0, 0, 0 } }, { 0.45, { -3, 4, 0 } }, { 0.8, { 5, -5, 0 } },
			{ 1, { 6, -6, 0 } } },
		collar = { { 0, { 0, 0, 0 } }, { 0.5, { 2.5, -3, 0 } }, { 1, { 5, -5, 0 } } },
		eye_l = { { 0, Z3, { 0, 0, 0 } }, { 0.7, Z3, { 0, 0, 0.075 } },
			{ 1, Z3, { 0, 0, 0.075 } } },
		eye_r = { { 0, Z3, { 0, 0, 0 } }, { 0.7, Z3, { 0, 0, 0.075 } },
			{ 1, Z3, { 0, 0, 0.075 } } },
	},
}

---------------------------------------------------------------- maths -------
local function lerp3(a, b, t)
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function ease(f)
	return f * f * (3 - 2 * f)
end

local function sample(track, t)
	local n = #track
	if n == 0 then return Z3, Z3 end
	if t <= track[1][1] then return track[1][2], track[1][3] or Z3 end
	for i = 1, n - 1 do
		local k0, k1 = track[i], track[i + 1]
		if t <= k1[1] then
			local f = ease((t - k0[1]) / math.max(k1[1] - k0[1], 1e-6))
			return lerp3(k0[2], k1[2], f), lerp3(k0[3] or Z3, k1[3] or Z3, f)
		end
	end
	return track[n][2], track[n][3] or Z3
end

local function sample1(track, t)
	local n = #track
	if n == 0 then return 0 end
	if t <= track[1][1] then return track[1][2] end
	for i = 1, n - 1 do
		local k0, k1 = track[i], track[i + 1]
		if t <= k1[1] then
			local f = ease((t - k0[1]) / math.max(k1[1] - k0[1], 1e-6))
			return k0[2] + (k1[2] - k0[2]) * f
		end
	end
	return track[n][2]
end

local function toCF(rot, pos)
	return CFrame.new(pos[1], pos[2], pos[3])
		* CFrame.fromEulerAnglesXYZ(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
end

--------------------------------------------------------------- object -------
function Animator.new(motors)
	local self = setmetatable({
		motors = motors,
		base = nil, baseName = nil, baseT = 0, baseDone = false,
		fade = 0, fadeLen = 0, prev = {}, lastBase = {},
		layers = {},
		clock = 0, nextBlink = 2.5,
		driftWeight = 1,
		axes = {},
	}, Animator)

	-- Each tentacle needs its own swing axis, worked out from where its joint
	-- sits. One shared Euler cannot bend eight limbs pointing eight ways.
	local i = 0
	for name, m in pairs(motors) do
		if name:sub(1, 4) == "tent" then
			local p = m.C0.Position
			local radial = Vector3.new(p.X, 0, p.Z)
			radial = radial.Magnitude > 1e-3 and radial.Unit or Vector3.new(0, 0, -1)
			self.axes[name] = {
				tangent = Vector3.new(-radial.Z, 0, radial.X),
				tip = name:sub(-2) == "_b",
				phase = (i * 0.6180339887) % 1,
			}
			i += 1
		end
	end
	return self
end

function Animator:setBase(name: string, fade: number?)
	local clip = Clips[name]
	assert(clip and not clip.additive, "OctopusAnimator: no base clip " .. tostring(name))
	if self.baseName == name then return end
	self.prev = {}
	for j, v in pairs(self.lastBase) do
		self.prev[j] = { v[1], v[2] }
	end
	self.base, self.baseName, self.baseT = clip, name, 0
	self.baseDone = false
	self.fadeLen = fade or 0.25
	self.fade = self.fadeLen
end

--[[ One-shot additive layer. Each call is its own instance, so rapid hits
     stack and decay independently. ]]
function Animator:fire(name: string, speed: number?)
	local clip = Clips[name]
	assert(clip and clip.additive, "OctopusAnimator: no additive clip " .. tostring(name))
	table.insert(self.layers, { clip = clip, t = 0, speed = speed or 1 })
	while #self.layers > 6 do
		table.remove(self.layers, 1)   -- more than this just fights itself
	end
end

function Animator:stop()
	self.base, self.baseName = nil, nil
	self.layers = {}
	for _, m in pairs(self.motors) do
		m.Transform = CFrame.new()
	end
end

function Animator:step(dt: number)
	self.clock += dt

	-- blinking belongs to every state, so it lives here and not in a clip
	self.nextBlink -= dt
	if self.nextBlink <= 0 then
		self:fire("Blink")
		self.nextBlink = 2.0 + math.random() * 3.5
	end

	if self.base then
		self.baseT += dt / self.base.length
		if self.baseT >= 1 then
			if self.base.loop then
				self.baseT %= 1
			else
				self.baseT = 1
				if not self.baseDone then
					self.baseDone = true
					local cb = self.onBaseDone
					if cb then cb(self.baseName) end
				end
			end
		end
	end
	if self.fade > 0 then self.fade = math.max(self.fade - dt, 0) end
	local blend = (self.fadeLen > 0) and (1 - self.fade / self.fadeLen) or 1

	for i = #self.layers, 1, -1 do
		local L = self.layers[i]
		L.t += dt * L.speed / L.clip.length
		if L.t >= 1 then table.remove(self.layers, i) end
	end

	local flinch = 0
	if self.base and self.base.flinch then
		flinch += sample1(self.base.flinch, self.baseT)
	end
	for _, L in ipairs(self.layers) do
		if L.clip.flinch then flinch += sample1(L.clip.flinch, L.t) end
	end

	local d = DRIFT
	local ph = self.clock * d.rate
	-- Emerging and sinking already move the body a long way; the idle drift at
	-- full strength on top of that reads as jitter.
	local dw = self.driftWeight * ((self.base and self.base.driftMul) or 1)

	for name, motor in pairs(self.motors) do
		local rot, pos = Z3, Z3
		if self.base then
			local tr = self.base.tracks[name]
			if tr then rot, pos = sample(tr, self.baseT) end
		end
		self.lastBase[name] = { rot, pos }
		if blend < 1 then
			local pv = self.prev[name]
			rot = lerp3(pv and pv[1] or Z3, rot, blend)
			pos = lerp3(pv and pv[2] or Z3, pos, blend)
		end
		local cf = toCF(rot, pos)

		local ax = self.axes[name]
		if ax then
			local a = (ph + ax.phase - (ax.tip and d.tipLag or 0)) * 2 * math.pi
			local swing = (ax.tip and d.tipSwing or d.baseSwing) * dw
			cf = cf
				* CFrame.fromAxisAngle(ax.tangent,
					math.rad(swing * math.sin(a) + flinch * (ax.tip and 1 or 0.6)))
				* CFrame.fromAxisAngle(Vector3.yAxis,
					math.rad(d.side * dw * math.sin(a * 0.63 + 1.1)))
		end

		for _, L in ipairs(self.layers) do
			local tr = L.clip.tracks[name]
			if tr then
				local r2, p2 = sample(tr, L.t)
				cf = cf * toCF(r2, p2)
			end
		end
		motor.Transform = cf
	end

	-- Root already picked up whatever the clip put on it above; the idle bob is
	-- COMPOSED onto that, never written over it, or Emerge and Submerge would
	-- have their travel wiped out every frame.
	local rootM = self.motors.Root
	if rootM then
		rootM.Transform = rootM.Transform
			* CFrame.new(0, d.bob * dw * math.sin(ph * 2 * math.pi * 0.8), 0)
			* CFrame.Angles(math.rad(d.roll * dw * math.sin(ph * 2 * math.pi * 0.5)),
				math.rad(d.roll * 0.8 * dw * math.sin(ph * 2 * math.pi * 0.37)),
				math.rad(d.roll * dw * math.sin(ph * 2 * math.pi * 0.61 + 2.0)))
	end
end

return Animator
