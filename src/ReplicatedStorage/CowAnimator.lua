local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	CowAnimator — проигрыватель CowClips прямо в Motor6D.Transform.

	Близнец ChickenAnimator по интерфейсу (play / step / stop), но формат данных
	другой: у курицы ключи — эйлеры по трекам, у коровы CowClips хранит готовый
	CFrame на сустав на кадр (30 fps, ~280 ключей на шесть клипов). Ассеты и
	публикация не нужны — ровно поэтому всё работает в неопубликованном плейсе.

	Ключ клипа: { t = секунды, p = { Torso = {12 чисел}, Head = …, LegFL = … } }.
	12 чисел — это {px, py, pz, r00..r22}: СДВИГ В ЕДИНИЦАХ РИГА (100 = 1 студ,
	поэтому POS_SCALE = 0.01 под импорт со Scale 0.01) и матрица поворота.
	Имена в p — это ДЕТАЛИ; их суставы: Torso→RootJoint, Head→Neck, LegFL→HipFL,
	LegRR→HipRR, Tail→TailJoint. Словарь моторов подаётся снаружи с теми же
	ключами, что в p (см. PirateIslandAnim.client).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DATA = require(ReplicatedStorage:WaitForChild("CowClips"))

local POS_SCALE = 0.01   -- меш импортирован со Scale 0.01; при импорте в 1.0 — ставить 1.0

local CowAnimator = {}
CowAnimator.__index = CowAnimator

-- ── предрасчёт: 12 чисел → CFrame, один раз на клип ──
local prepared = nil
local function clips()
	if prepared then return prepared end
	prepared = {}
	for name, clip in pairs(DATA) do
		local keys = {}
		for _, k in ipairs(clip.keys) do
			local pose = {}
			for joint, n in pairs(k.p) do
				pose[joint] = CFrame.new(
					n[1] * POS_SCALE, n[2] * POS_SCALE, n[3] * POS_SCALE,
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

-- motors: { Torso = Motor6D(RootJoint), Head = Motor6D(Neck), LegFL = …, Tail = … }
function CowAnimator.new(motors)
	return setmetatable({
		motors = motors,
		clip = nil,
		name = nil,
		t = 0,
		speed = 1,
		fade = 0,
		fadeLen = 0,
		from = {},      -- сустав → CFrame на момент смены клипа (кроссфейд)
		current = {},   -- сустав → последний выставленный CFrame
		finished = false,
	}, CowAnimator)
end

function CowAnimator:play(name, fadeTime, speed)
	local clip = clips()[name]
	if not clip then
		warn("CowAnimator: нет клипа " .. tostring(name))
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

function CowAnimator:stop()
	self.clip, self.name = nil, nil
	for _, m in pairs(self.motors) do
		m.Transform = IDENTITY
	end
end

-- Звать каждый кадр. Возвращает true, пока не-луповый клип ещё идёт.
function CowAnimator:step(dt)
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

return CowAnimator
