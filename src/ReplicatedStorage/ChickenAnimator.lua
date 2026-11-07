--[[
	ChickenAnimator — keyframed poses driven straight into Motor6D.Transform.

	No Animation assets and no rig upload needed: each clip is a table of tracks,
	one per joint, and each track is a list of {t, rot, pos} keys. t runs 0..1
	over the clip, rot is XYZ euler DEGREES, pos is a stud offset (optional).

		local a = chicken.animator
		a:play("Walk")            -- loops
		a:play("Jump", 0.08)      -- one shot, 0.08s crossfade in
		RunService.Heartbeat:Connect(function(dt) a:step(dt) end)

	Joint axis cheat sheet (all joints inherit the torso's axes: +X right,
	+Y up, -Z forward, because every C0/C1 is a pure translation):
		rot.X on a hip   > 0 swings that leg FORWARD
		rot.X on Neck    > 0 lifts the beak, < 0 pecks down
		rot.Z on WingR   > 0 raises it;  WingL is mirrored for you
		pos.Y on Root      lifts the whole body (squash / hop)
]]

local Animator = {}
Animator.__index = Animator

local Z = { 0, 0, 0 }

-- Left-side joints get their Y and Z rotation negated so a clip can be written
-- once and read the same on both sides.
local MIRROR = { WingL = true, HipL = true }

local Clips = {}
Animator.Clips = Clips

------------------------------------------------------------------ walking ----
Clips.Walk = {
	length = 0.70, loop = true,
	tracks = {
		HipL = { { 0, { -24, 0, 0 } }, { 0.25, { 4, 0, 0 } }, { 0.50, { 24, 0, 0 } },
			{ 0.75, { 2, 0, 0 } }, { 1, { -24, 0, 0 } } },
		HipR = { { 0, { 24, 0, 0 } }, { 0.25, { 2, 0, 0 } }, { 0.50, { -24, 0, 0 } },
			{ 0.75, { 4, 0, 0 } }, { 1, { 24, 0, 0 } } },
		Root = { { 0, { 0, 0, 0 }, { 0, 0, 0 } }, { 0.25, { -2, 0, 0 }, { 0, 0.05, 0 } },
			{ 0.50, { 0, 0, 0 }, { 0, 0, 0 } }, { 0.75, { -2, 0, 0 }, { 0, 0.05, 0 } },
			{ 1, { 0, 0, 0 }, { 0, 0, 0 } } },
		-- the classic chicken head-bob: the head hangs back while the body walks
		-- out from under it, then darts forward to catch up
		Neck = { { 0, { 0, 0, 0 }, { 0, 0, -0.06 } }, { 0.40, { 4, 0, 0 }, { 0, 0, 0.05 } },
			{ 0.50, { 0, 0, 0 }, { 0, 0, -0.06 } }, { 0.90, { 4, 0, 0 }, { 0, 0, 0.05 } },
			{ 1, { 0, 0, 0 }, { 0, 0, -0.06 } } },
		WingL = { { 0, { 0, 0, 5 } }, { 0.5, { 0, 0, 9 } }, { 1, { 0, 0, 5 } } },
		WingR = { { 0, { 0, 0, 5 } }, { 0.5, { 0, 0, 9 } }, { 1, { 0, 0, 5 } } },
	},
}

Clips.Run = {
	length = 0.42, loop = true,
	tracks = {
		HipL = { { 0, { -38, 0, 0 } }, { 0.22, { 10, 0, 0 } }, { 0.50, { 40, 0, 0 } },
			{ 0.74, { 0, 0, 0 } }, { 1, { -38, 0, 0 } } },
		HipR = { { 0, { 40, 0, 0 } }, { 0.24, { 0, 0, 0 } }, { 0.50, { -38, 0, 0 } },
			{ 0.72, { 10, 0, 0 } }, { 1, { 40, 0, 0 } } },
		Root = { { 0, { -15, 0, 0 }, { 0, 0, 0 } }, { 0.25, { -17, 0, 0 }, { 0, 0.09, 0 } },
			{ 0.50, { -15, 0, 0 }, { 0, 0, 0 } }, { 0.75, { -17, 0, 0 }, { 0, 0.09, 0 } },
			{ 1, { -15, 0, 0 }, { 0, 0, 0 } } },
		Neck = { { 0, { 14, 0, 0 }, { 0, 0.02, -0.13 } }, { 0.5, { 18, 0, 0 }, { 0, 0.04, -0.16 } },
			{ 1, { 14, 0, 0 }, { 0, 0.02, -0.13 } } },
		WingL = { { 0, { -8, 0, 20 } }, { 0.5, { -12, 0, 30 } }, { 1, { -8, 0, 20 } } },
		WingR = { { 0, { -8, 0, 20 } }, { 0.5, { -12, 0, 30 } }, { 1, { -8, 0, 20 } } },
	},
}

-- startled bolt: everything doubles in rate, the wings go up and the head
-- snaps side to side instead of bobbing
Clips.Panic = {
	length = 0.30, loop = true,
	tracks = {
		HipL = { { 0, { -44, 0, 0 } }, { 0.25, { 14, 0, 0 } }, { 0.50, { 46, 0, 0 } },
			{ 0.75, { 0, 0, 0 } }, { 1, { -44, 0, 0 } } },
		HipR = { { 0, { 46, 0, 0 } }, { 0.25, { 0, 0, 0 } }, { 0.50, { -44, 0, 0 } },
			{ 0.75, { 14, 0, 0 } }, { 1, { 46, 0, 0 } } },
		Root = { { 0, { -8, 3, 0 }, { 0, 0.02, 0 } }, { 0.25, { -10, -4, 0 }, { 0, 0.12, 0 } },
			{ 0.50, { -8, 3, 0 }, { 0, 0.02, 0 } }, { 0.75, { -10, -4, 0 }, { 0, 0.12, 0 } },
			{ 1, { -8, 3, 0 }, { 0, 0.02, 0 } } },
		Neck = { { 0, { 26, -16, 0 }, { 0, 0.05, -0.06 } }, { 0.28, { 30, 12, 0 }, { 0, 0.07, -0.04 } },
			{ 0.55, { 24, -10, 0 }, { 0, 0.04, -0.07 } }, { 0.80, { 31, 15, 0 }, { 0, 0.07, -0.03 } },
			{ 1, { 26, -16, 0 }, { 0, 0.05, -0.06 } } },
		WingL = { { 0, { -14, 0, 18 } }, { 0.30, { -22, 0, 68 } }, { 0.62, { -10, 0, 14 } },
			{ 1, { -14, 0, 18 } } },
		WingR = { { 0, { -10, 0, 62 } }, { 0.32, { -18, 0, 16 } }, { 0.66, { -22, 0, 66 } },
			{ 1, { -10, 0, 62 } } },
	},
}

-- jump and flap: crouch, launch, four wingbeats of hang time, then land
Clips.Jump = {
	length = 1.05, loop = false,
	tracks = {
		Root = { { 0, { 0, 0, 0 }, { 0, 0, 0 } }, { 0.13, { 6, 0, 0 }, { 0, -0.16, 0 } },
			{ 0.24, { -10, 0, 0 }, { 0, 0.26, 0 } }, { 0.40, { -14, 0, 0 }, { 0, 0.34, 0 } },
			{ 0.62, { -6, 0, 0 }, { 0, 0.30, 0 } }, { 0.80, { 4, 0, 0 }, { 0, 0.05, 0 } },
			{ 0.88, { 10, 0, 0 }, { 0, -0.12, 0 } }, { 1, { 0, 0, 0 }, { 0, 0, 0 } } },
		HipL = { { 0, { 0, 0, 0 } }, { 0.13, { 34, 0, 0 } }, { 0.26, { -34, 0, 0 } },
			{ 0.45, { 44, 0, 0 } }, { 0.70, { 40, 0, 0 } }, { 0.84, { -14, 0, 0 } },
			{ 1, { 0, 0, 0 } } },
		HipR = { { 0, { 0, 0, 0 } }, { 0.13, { 30, 0, 0 } }, { 0.26, { -30, 0, 0 } },
			{ 0.45, { 48, 0, 0 } }, { 0.70, { 42, 0, 0 } }, { 0.84, { -10, 0, 0 } },
			{ 1, { 0, 0, 0 } } },
		Neck = { { 0, { 0, 0, 0 }, { 0, 0, 0 } }, { 0.13, { -14, 0, 0 }, { 0, -0.03, 0.03 } },
			{ 0.28, { 26, 0, 0 }, { 0, 0.04, -0.08 } }, { 0.62, { 20, 0, 0 }, { 0, 0.03, -0.06 } },
			{ 0.88, { -10, 0, 0 }, { 0, -0.02, 0.02 } }, { 1, { 0, 0, 0 }, { 0, 0, 0 } } },
		WingL = { { 0, { 0, 0, 6 } }, { 0.14, { 0, 0, -6 } }, { 0.26, { -18, 0, 74 } },
			{ 0.38, { 6, 0, 10 } }, { 0.48, { -18, 0, 72 } }, { 0.58, { 6, 0, 12 } },
			{ 0.68, { -16, 0, 66 } }, { 0.80, { 0, 0, 16 } }, { 1, { 0, 0, 6 } } },
		WingR = { { 0, { 0, 0, 6 } }, { 0.14, { 0, 0, -6 } }, { 0.26, { -18, 0, 74 } },
			{ 0.38, { 6, 0, 10 } }, { 0.48, { -18, 0, 72 } }, { 0.58, { 6, 0, 12 } },
			{ 0.68, { -16, 0, 66 } }, { 0.80, { 0, 0, 16 } }, { 1, { 0, 0, 6 } } },
	},
}

-- standing about, pecking at the ground three times then straightening up
Clips.IdlePeck = {
	length = 2.60, loop = true,
	tracks = {
		Neck = { { 0, { 0, 0, 0 }, { 0, 0, 0 } }, { 0.10, { 6, -8, 0 }, { 0, 0.01, 0 } },
			{ 0.20, { -20, 0, 0 }, { 0, -0.06, -0.05 } },
			{ 0.28, { -56, 0, 0 }, { 0, -0.20, -0.12 } },
			{ 0.34, { -30, 0, 0 }, { 0, -0.10, -0.07 } },
			{ 0.42, { -58, 0, 0 }, { 0, -0.21, -0.12 } },
			{ 0.48, { -28, 0, 0 }, { 0, -0.09, -0.06 } },
			{ 0.56, { -57, 0, 0 }, { 0, -0.20, -0.12 } },
			{ 0.66, { -12, 0, 0 }, { 0, -0.03, -0.02 } },
			{ 0.76, { 8, 14, 0 }, { 0, 0.02, 0 } }, { 0.88, { 4, -12, 0 }, { 0, 0.01, 0 } },
			{ 1, { 0, 0, 0 }, { 0, 0, 0 } } },
		Root = { { 0, { 0, 0, 0 }, { 0, 0, 0 } }, { 0.28, { 5, 0, 0 }, { 0, -0.04, 0 } },
			{ 0.56, { 5, 0, 0 }, { 0, -0.04, 0 } }, { 0.70, { 0, 0, 0 }, { 0, 0, 0 } },
			{ 1, { 0, 0, 0 }, { 0, 0, 0 } } },
		HipL = { { 0, { 0, 0, 0 } }, { 0.30, { 4, 0, 0 } }, { 0.72, { -3, 0, 0 } },
			{ 1, { 0, 0, 0 } } },
		HipR = { { 0, { 0, 0, 0 } }, { 0.30, { -3, 0, 0 } }, { 0.72, { 4, 0, 0 } },
			{ 1, { 0, 0, 0 } } },
		WingL = { { 0, { 0, 0, 4 } }, { 0.5, { 0, 0, 7 } }, { 0.62, { 0, 0, 3 } },
			{ 1, { 0, 0, 4 } } },
		WingR = { { 0, { 0, 0, 4 } }, { 0.5, { 0, 0, 7 } }, { 0.62, { 0, 0, 3 } },
			{ 1, { 0, 0, 4 } } },
	},
}

-- ambling idle: short shuffling steps, head turning to look around
Clips.IdleWalk = {
	length = 2.00, loop = true,
	tracks = {
		HipL = { { 0, { -11, 0, 0 } }, { 0.25, { 2, 0, 0 } }, { 0.50, { 11, 0, 0 } },
			{ 0.75, { 1, 0, 0 } }, { 1, { -11, 0, 0 } } },
		HipR = { { 0, { 11, 0, 0 } }, { 0.25, { 1, 0, 0 } }, { 0.50, { -11, 0, 0 } },
			{ 0.75, { 2, 0, 0 } }, { 1, { 11, 0, 0 } } },
		Root = { { 0, { 0, 0, 0 }, { 0, 0, 0 } }, { 0.25, { -1, 0, 0 }, { 0, 0.02, 0 } },
			{ 0.50, { 0, 0, 0 }, { 0, 0, 0 } }, { 0.75, { -1, 0, 0 }, { 0, 0.02, 0 } },
			{ 1, { 0, 0, 0 }, { 0, 0, 0 } } },
		Neck = { { 0, { 0, 0, 0 }, { 0, 0, -0.03 } }, { 0.18, { 3, 24, 0 }, { 0, 0.01, 0.02 } },
			{ 0.34, { 0, 20, 0 }, { 0, 0, -0.03 } }, { 0.52, { 4, -6, 0 }, { 0, 0.01, 0.02 } },
			{ 0.68, { -2, -26, 0 }, { 0, 0, -0.03 } }, { 0.86, { 3, -18, 0 }, { 0, 0.01, 0.02 } },
			{ 1, { 0, 0, 0 }, { 0, 0, -0.03 } } },
		WingL = { { 0, { 0, 0, 4 } }, { 0.5, { 0, 0, 6 } }, { 1, { 0, 0, 4 } } },
		WingR = { { 0, { 0, 0, 4 } }, { 0.5, { 0, 0, 6 } }, { 1, { 0, 0, 4 } } },
	},
}

--------------------------------------------------------------- evaluation ----
local function lerp3(a, b, t)
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function sampleTrack(track, t)
	local n = #track
	if n == 0 then return Z, Z end
	if t <= track[1][1] then return track[1][2], track[1][3] or Z end
	for i = 1, n - 1 do
		local k0, k1 = track[i], track[i + 1]
		if t <= k1[1] then
			local span = k1[1] - k0[1]
			local f = span > 1e-6 and (t - k0[1]) / span or 0
			f = f * f * (3 - 2 * f)                      -- ease, so keys do not tick
			return lerp3(k0[2], k1[2], f), lerp3(k0[3] or Z, k1[3] or Z, f)
		end
	end
	return track[n][2], track[n][3] or Z
end

-- ⚠️ ОСИ ЭТОГО ИМПОРТА (правка против оригинала пакета): +Z на крыле машет ВНИЗ,
-- а не вверх, как ждёт шпаргалка клипов, — в прыжке крылья уходили под тушку.
-- Инвертируем Z обоим крыльям ПОСЛЕ зеркала, чтобы мах остался симметричным.
local WING_FLIP = { WingL = true, WingR = true }

local function toCFrame(name, rot, pos)
	local sx, sy, sz = rot[1], rot[2], rot[3]
	if MIRROR[name] then
		sy, sz = -sy, -sz
	end
	if WING_FLIP[name] then
		sz = -sz
	end
	return CFrame.new(pos[1], pos[2], pos[3])
		* CFrame.fromEulerAnglesXYZ(math.rad(sx), math.rad(sy), math.rad(sz))
end

function Animator.new(motors)
	return setmetatable({
		motors = motors,
		clip = nil,
		name = nil,
		t = 0,
		speed = 1,
		fade = 0,
		fadeLen = 0,
		from = {},          -- joint -> {rot, pos} snapshot for the crossfade
		current = {},       -- joint -> {rot, pos} last evaluated
		finished = false,
	}, Animator)
end

function Animator:play(name: string, fadeTime: number?, speed: number?)
	local clip = Clips[name]
	assert(clip, "ChickenAnimator: no clip named " .. tostring(name))
	if self.name == name and not self.finished then
		self.speed = speed or self.speed
		return
	end
	self.from = {}
	for j, v in pairs(self.current) do
		self.from[j] = { v[1], v[2] }
	end
	self.clip = clip
	self.name = name
	self.t = 0
	self.speed = speed or 1
	self.fadeLen = fadeTime or 0.12
	self.fade = self.fadeLen
	self.finished = false
end

function Animator:stop()
	self.clip, self.name = nil, nil
	for _, m in pairs(self.motors) do
		m.Transform = CFrame.new()
	end
end

--[[ Call every frame. Returns true while a non-looping clip is still running. ]]
function Animator:step(dt: number)
	local clip = self.clip
	if not clip then return false end

	self.t += dt * self.speed / clip.length
	if self.t >= 1 then
		if clip.loop then
			self.t %= 1
		else
			self.t = 1
			self.finished = true
		end
	end
	if self.fade > 0 then
		self.fade = math.max(self.fade - dt, 0)
	end
	local blend = (self.fadeLen > 0) and (1 - self.fade / self.fadeLen) or 1

	for name, motor in pairs(self.motors) do
		local track = clip.tracks[name]
		local rot, pos = Z, Z
		if track then
			rot, pos = sampleTrack(track, self.t)
		end
		if blend < 1 then
			local prev = self.from[name]
			if prev then
				rot = lerp3(prev[1], rot, blend)
				pos = lerp3(prev[2], pos, blend)
			else
				rot = lerp3(Z, rot, blend)
				pos = lerp3(Z, pos, blend)
			end
		end
		self.current[name] = { rot, pos }
		motor.Transform = toCFrame(name, rot, pos)
	end
	return not self.finished
end

return Animator
