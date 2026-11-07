--[[
	SeagullAnimator — проигрыватель SeagullClips прямо в Motor6D.Transform.
	Близнец CowAnimator: тот же формат данных и тот же интерфейс (new / play / stop / step).

	Ключ клипа: { t = секунды, p = { Torso = {12 чисел}, Head = …, WingL = … } }.
	12 чисел — {px, py, pz, r00..r22}: сдвиг и матрица поворота. Отличие от коровы одно:
	сдвиг записан В ЕДИНИЦАХ МОДЕЛИ, а не «100 = 1 студ», и домножается на posScale —
	измеренный масштаб импорта (SeagullRig кладёт его в атрибут RigScale). Поэтому
	чайку можно импортировать любого размера, клипы не поедут.

	Имена в p — это ДЕТАЛИ; их суставы см. SeagullRig.MOTORS. Словарь моторов подаётся
	снаружи с теми же ключами, что в p. Детали, которой нет в клипе, ставится identity.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DATA = require(ReplicatedStorage:WaitForChild("SeagullClips"))

local SeagullAnimator = {}
local IDENTITY_CF = CFrame.identity
SeagullAnimator.__index = SeagullAnimator

-- ── предрасчёт: 12 чисел → CFrame, один раз на клип и на масштаб ──
local preparedByScale = {}
local function clips(posScale)
	local prepared = preparedByScale[posScale]
	if prepared then return prepared end
	prepared = {}
	for name, clip in pairs(DATA) do
		local keys = {}
		for _, k in ipairs(clip.keys) do
			local pose = {}
			for joint, n in pairs(k.p) do
				pose[joint] = CFrame.new(
					n[1] * posScale, n[2] * posScale, n[3] * posScale,
					n[4], n[5], n[6], n[7], n[8], n[9], n[10], n[11], n[12])
			end
			table.insert(keys, { t = k.t, pose = pose })
		end
		table.sort(keys, function(a, b) return a.t < b.t end)
		prepared[name] = {
			loop = clip.loop,
			length = (#keys > 0) and keys[#keys].t or 0,
			keys = keys,
		}
	end
	--[[ КЛИП «Rest» СОБИРАЕТСЯ ЗДЕСЬ, А НЕ В SeagullClips (тот файл генерирует
	     gull_anim.py, руками его не правят). Поза — первый кадр Idle; голова медленно
	     поднимается, птица замирает и так же медленно опускает её. Голова вниз в
	     клипе Peck — это поворот по X в минус, значит вверх — в плюс. ]]
	local idle = prepared.Idle
	if idle and idle.keys[1] then
		local base = idle.keys[1].pose
		local function restKey(t, headDeg, torsoDeg, yawDeg)
			local pose = {}
			for j, cf in pairs(base) do pose[j] = cf end
			pose.Head = (base.Head or IDENTITY_CF) * CFrame.Angles(math.rad(headDeg), math.rad(yawDeg), 0)
			pose.Torso = (base.Torso or IDENTITY_CF) * CFrame.Angles(math.rad(torsoDeg), 0, 0)
			return { t = t, pose = pose }
		end
		prepared.Rest = { loop = true, length = 6, keys = {
			restKey(0, 0, 0, 0), restKey(0.5, 4, 1, 0), restKey(1.6, 24, 5, 0), restKey(2.0, 27, 6, 0),
			restKey(3.2, 26, 6, 7), restKey(4.2, 27, 6, -5), restKey(4.8, 22, 5, 0), restKey(5.6, 4, 1, 0), restKey(6, 0, 0, 0),
		} }
	end
	--[[ КЛИП «Panic» (горит): тот же взмах Fly, но частый, с рысканьем корпуса,
	     креном и мотанием головы — птица мечется, сбивая пламя. Строится кодом
	     по той же причине, что Rest: SeagullClips генерирует gull_anim.py. ]]
	local fly = prepared.Fly
	if fly and #fly.keys > 0 then
		local keys = {}
		local len = fly.length
		for cycle = 0, 2 do
			for _, k in ipairs(fly.keys) do
				local t = cycle * len + k.t
				local ph = t / (len * 3) * math.pi * 2
				local pose = {}
				for j, cf in pairs(k.pose) do pose[j] = cf end
				pose.Torso = (k.pose.Torso or IDENTITY_CF)
					* CFrame.Angles(math.sin(ph * 3) * 0.18, math.sin(ph * 2) * 0.5, math.sin(ph * 5) * 0.55)
				pose.Head = (k.pose.Head or IDENTITY_CF)
					* CFrame.Angles(math.sin(ph * 7) * 0.35, math.sin(ph * 9) * 0.6, 0)
				table.insert(keys, { t = t, pose = pose })
			end
		end
		prepared.Panic = { loop = true, length = len * 3, keys = keys }
	end
	preparedByScale[posScale] = prepared
	return prepared
end

local IDENTITY = CFrame.identity

local function sample(clip, t)
	local keys = clip.keys
	local last = keys[#keys]
	if clip.loop and clip.length > 0 then
		t = t % clip.length
	elseif t >= last.t then
		return last.pose, true          -- не-луп доиграл: держим последний кадр
	end
	if t < 0 then t = 0 end

	local a, b = keys[1], last
	for i = 1, #keys - 1 do
		if t >= keys[i].t and t <= keys[i + 1].t then
			a, b = keys[i], keys[i + 1]
			break
		end
	end
	local span = b.t - a.t
	local alpha = (span > 0) and ((t - a.t) / span) or 0

	local out = {}
	for joint, cfA in pairs(a.pose) do
		out[joint] = cfA:Lerp(b.pose[joint] or cfA, alpha)
	end
	return out, false
end

-- motors: { Torso = Motor6D(RootJoint), Head = Motor6D(Neck), WingL = Motor6D(ShoulderL), … }
function SeagullAnimator.new(motors, posScale)
	return setmetatable({
		motors = motors,
		posScale = posScale or 1,
		clip = nil,
		name = nil,
		t = 0,
		speed = 1,
		fade = 0,
		fadeLen = 0,
		from = {},      -- сустав → CFrame на момент смены клипа (кроссфейд)
		current = {},   -- сустав → последний выставленный CFrame
		finished = false,
	}, SeagullAnimator)
end

function SeagullAnimator.has(name)
	return DATA[name] ~= nil or name == "Rest" or name == "Panic"   -- Rest/Panic собираются кодом, см. clips()
end

function SeagullAnimator:play(name, fadeTime, speed)
	local clip = clips(self.posScale)[name]
	if not clip then
		warn("SeagullAnimator: нет клипа " .. tostring(name))
		return
	end
	if self.name == name and not self.finished then
		self.speed = speed or self.speed
		return
	end
	self.from = {}
	for j, cf in pairs(self.current) do self.from[j] = cf end
	self.clip = clip
	self.name = name
	self.t = 0
	self.speed = speed or 1
	self.fadeLen = fadeTime or 0.12
	self.fade = self.fadeLen
	self.finished = false
end

function SeagullAnimator:stop()
	self.clip, self.name = nil, nil
	for _, m in pairs(self.motors) do
		m.Transform = IDENTITY
	end
end

-- Звать каждый кадр. Возвращает true, пока не-луповый клип ещё идёт.
function SeagullAnimator:step(dt)
	local clip = self.clip
	if not clip then return false end

	self.t += dt * self.speed
	if self.fade > 0 then
		self.fade = math.max(self.fade - dt, 0)
	end
	local blend = (self.fadeLen > 0) and (1 - self.fade / self.fadeLen) or 1

	local pose, done = sample(clip, self.t)
	if done then self.finished = true end

	for joint, motor in pairs(self.motors) do
		local target = pose[joint] or IDENTITY
		if blend < 1 then
			local prev = self.from[joint]
			target = (prev or IDENTITY):Lerp(target, blend)
		end
		self.current[joint] = target
		motor.Transform = target
	end
	return not self.finished
end

return SeagullAnimator
