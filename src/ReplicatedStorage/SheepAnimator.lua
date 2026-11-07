--[[
	SheepAnimator — проигрыватель SheepClips прямо в Motor6D.Transform.

	Близнец CowAnimator (play / step / stop / finished), отличие одно: сдвиги в
	клипах заданы ДОЛЯМИ ВЫСОТЫ ТУШИ, а не единицами рига, — множитель берётся
	у самой детали Torso (Part1 сустава RootJoint), и клип одинаково ложится на
	овцу любого масштаба импорта.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DATA = require(ReplicatedStorage:WaitForChild("SheepClips"))

local SheepAnimator = {}
SheepAnimator.__index = SheepAnimator

local prepared = nil
local function clips()
	if prepared then return prepared end
	prepared = {}
	for name, clip in pairs(DATA) do
		local keys = {}
		for _, k in ipairs(clip.keys) do
			local pose = {}
			for joint, n in pairs(k.p) do
				pose[joint] = {
					pos = Vector3.new(n[1], n[2], n[3]),
					rot = CFrame.new(0, 0, 0, n[4], n[5], n[6], n[7], n[8], n[9], n[10], n[11], n[12]),
				}
			end
			table.insert(keys, { t = k.t, pose = pose })
		end
		table.sort(keys, function(a, b) return a.t < b.t end)
		prepared[name] = { loop = clip.loop, length = (#keys > 0) and keys[#keys].t or 0, keys = keys }
	end
	return prepared
end

local IDENTITY = CFrame.identity

--[[ ⚠️ ОСИ СУСТАВА ≠ ОСИ КЛИПА. Клипы написаны в канонической системе овцы:
     Y вверх, +Z к голове, X вправо. У нарезанного рига оси суставов с ней
     совпадали, у авторского (25 деталей) — нет: голова на Eat шла вниз вместо
     вверх. Для каждого сустава один раз считаем поворот Rc из его рамы (Part0 ×
     C0) в каноническую (корень, развёрнутый к голове) и применяем клип как
     Rc · T · Rc⁻¹. Считается при покое, когда Transform ещё единичный. ]]
local function canonicalOf(motors)
	local rj = motors.Torso
	local root = rj and rj.Part0
	if not root then return nil end
	return root.CFrame * CFrame.Angles(0, math.pi, 0)
end

local function sample(clip, t, unit)
	local keys = clip.keys
	local last = keys[#keys]
	local done = false
	if clip.loop and clip.length > 0 then
		t = t % clip.length
	elseif t >= last.t then
		t = last.t
		done = true
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
	for joint, ja in pairs(a.pose) do
		local jb = b.pose[joint] or ja
		local pos = ja.pos:Lerp(jb.pos, alpha) * unit
		out[joint] = CFrame.new(pos) * ja.rot:Lerp(jb.rot, alpha)
	end
	return out, done
end

function SheepAnimator.new(motors)
	return setmetatable({
		motors = motors, clip = nil, name = nil, t = 0, speed = 1,
		fade = 0, fadeLen = 0, from = {}, current = {}, finished = false,
		basis = {},   -- сустав → Rc (поворот из рамы сустава в каноническую)
	}, SheepAnimator)
end

function SheepAnimator:basisFor(joint, motor)
	local rc = self.basis[joint]
	if rc then return rc end
	local canon = canonicalOf(self.motors)
	if not canon or not motor.Part0 then return IDENTITY end
	local j = motor.Part0.CFrame * motor.C0
	rc = (j:Inverse() * canon).Rotation
	self.basis[joint] = rc
	return rc
end

function SheepAnimator:unit()
	local rj = self.motors.Torso
	local torso = rj and rj.Part1
	return (torso and torso:IsA("BasePart")) and torso.Size.Y or 1
end

function SheepAnimator:play(name, fadeTime, speed)
	local clip = clips()[name]
	if not clip then
		warn("SheepAnimator: нет клипа " .. tostring(name))
		return
	end
	if self.name == name and not self.finished then
		self.speed = speed or self.speed
		return
	end
	self.from = {}
	for j, cf in pairs(self.current) do self.from[j] = cf end
	self.clip, self.name, self.t = clip, name, 0
	self.speed = speed or 1
	self.fadeLen = fadeTime or 0.15
	self.fade = self.fadeLen
	self.finished = false
end

function SheepAnimator:stop()
	self.clip, self.name = nil, nil
	for _, m in pairs(self.motors) do m.Transform = IDENTITY end
end

function SheepAnimator:step(dt)
	local clip = self.clip
	if not clip then return false end
	self.t += dt * self.speed
	if self.fade > 0 then self.fade = math.max(self.fade - dt, 0) end
	local blend = (self.fadeLen > 0) and (1 - self.fade / self.fadeLen) or 1
	local pose, done = sample(clip, self.t, self:unit())
	if done then self.finished = true end
	for joint, motor in pairs(self.motors) do
		local target = pose[joint] or IDENTITY
		if target ~= IDENTITY then
			local rc = self:basisFor(joint, motor)
			target = rc * target * rc:Inverse()
		end
		if blend < 1 then
			target = (self.from[joint] or IDENTITY):Lerp(target, blend)
		end
		self.current[joint] = target
		motor.Transform = target
	end
	return not self.finished
end

return SheepAnimator
