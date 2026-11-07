--!strict
local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ПРОИГРЫВАТЕЛЬ КЛИПОВ ЭКИПАЖА — БЕЗ ПУБЛИКАЦИИ.

	⚠️ ГЛАВНОЕ, РАДИ ЧЕГО ЭТОТ МОДУЛЬ СУЩЕСТВУЕТ.
	Animation.AnimationId заставляет движок идти за ассетом на серверы Roblox, и в
	неопубликованном плейсе (serverplaceid=0) это молча не работает — ровно то, что
	видно в логе на каждый звериный клип. Здесь ассеты не нужны вообще: поза лежит
	в ReplicatedStorage.PirateCrewClips обычной таблицей и кладётся в Motor6D.Transform
	напрямую, теми же числами, из которых BuildAnimations делает KeyframeSequence.
	Именно так с самого начала анимирован экипаж катеров, поэтому у него всё
	работает без единой публикации.

	Данные: на каждый кадр — CFrame по шести частям R6. Motor6D, который эту часть
	двигает, называется иначе (Torso двигает RootJoint, Head — Neck и так далее),
	поэтому имена сопоставляются таблицей ниже.

	Использование:
		local CrewClips = require(ReplicatedStorage.CrewClips)
		local anim = CrewClips.attach(model)      -- один раз на модель
		anim:play("MeleeWalk")                    -- цикл
		anim:once("SabreSwing")                   -- событие, потом вернётся цикл
		anim:step(dt)                             -- каждый кадр
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrewClips = {}

-- часть тела в клипе → Motor6D, который её двигает
local MOTOR_OF = {
	["Torso"]     = "RootJoint",
	["Head"]      = "Neck",
	["Left Arm"]  = "Left Shoulder",
	["Right Arm"] = "Right Shoulder",
	["Left Leg"]  = "Left Hip",
	["Right Leg"] = "Right Hip",
}

local FADE = 0.18   -- секунд на переход между позами

--[[ ⚠️ РЕТАРГЕТ НА «СВОЙ» R6 (атрибут модели RigRetarget = "R6").
     Клипы записаны как Motor6D.Transform стандартного R6, у которого C0/C1
     суставов повёрнуты (плечи на 90° по Y, шея и корень на −90° по X). У
     выживших из пака (Captain Rose) суставы без этих поворотов, а поза покоя та
     же. Та же поза в мире получается, если Transform пересчитать:
         Tr = C0r⁻¹ · C0s · Ts · C1s⁻¹ · C1r
     (s — стандартный R6, r — сустав модели). В покое (Ts = 1) это ровно 1. ]]
local STD_R6 = {
	["RootJoint"]      = { CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	["Neck"]           = { CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	["Right Shoulder"] = { CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	["Left Shoulder"]  = { CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
	["Right Hip"]      = { CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	["Left Hip"]       = { CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
}

-- ── загрузка ──
local CLIPS: { [string]: any } = {}
local loaded = false

local function load()
	if loaded then return end
	loaded = true
	local mod = ReplicatedStorage:FindFirstChild("PirateCrewClips")
	if not mod then
		-- ограниченное ожидание: Rojo мог ещё не досинхронить, но вешать модуль на
		-- бесконечный WaitForChild нельзя — он тогда не отдаст управление вообще
		local t0 = os.clock()
		while not mod and os.clock() - t0 < 10 do
			task.wait(0.25)
			mod = ReplicatedStorage:FindFirstChild("PirateCrewClips")
		end
	end
	if not (mod and mod:IsA("ModuleScript")) then
		warn("[CrewClips] ReplicatedStorage.PirateCrewClips не найден — анимаций не будет")
		return
	end
	local ok, data = pcall(require, mod)
	if not ok or type(data) ~= "table" or type(data.clips) ~= "table" then
		warn("[CrewClips] PirateCrewClips не отдал данные")
		return
	end

	local n = 0
	for name, clip in pairs(data.clips) do
		local keys = {}
		for _, k in ipairs(clip.keys) do
			local pose = {}
			for part, v in pairs(k.p) do
				pose[part] = CFrame.new(v[1], v[2], v[3],
					v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12])
			end
			table.insert(keys, { t = k.t, p = pose })
		end
		table.sort(keys, function(a, b) return a.t < b.t end)
		CLIPS[name] = { loop = clip.loop, length = clip.length or 0, keys = keys }
		n += 1
	end
	print(("[CrewClips] загружено клипов: %d (без публикации, прямо из таблицы)"):format(n))
end

function CrewClips.has(name: string): boolean
	load()
	return CLIPS[name] ~= nil
end

-- ── выборка позы ──
local function sample(clip, t)
	local keys = clip.keys
	local last = keys[#keys]
	if clip.loop and clip.length > 0 then
		t = t % clip.length
	elseif t >= last.t then
		return last.p, true
	elseif t < 0 then
		t = 0
	end

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
	for part, cfA in pairs(a.p) do
		local cfB = b.p[part] or cfA
		out[part] = cfA:Lerp(cfB, alpha)
	end
	return out, false
end

-- ── проигрыватель на модель ──
local Player = {}
Player.__index = Player

-- отчёт по одному разу на ТИП модели, иначе четырнадцать пиратов дадут четырнадцать строк
local reported: { [string]: boolean } = {}

function CrewClips.attach(model: Instance)
	load()
	local self = setmetatable({}, Player)
	self.model = model
	self.motors = {}
	for part, motorName in pairs(MOTOR_OF) do
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Motor6D") and d.Name == motorName then
				self.motors[part] = d
				break
			end
		end
	end
	self.t = 0
	self.fade = 0

	-- ⚠️ ДИАГНОСТИКА: «анимаций нет» выглядит одинаково и когда клипы не нашлись, и
	-- когда суставы не те. Клипы уже видно по строке загрузки выше, поэтому здесь
	-- проверяем вторую половину — сколько Motor6D удалось привязать и как они вообще
	-- называются в этой модели. У R15 имена другие (Waist, LeftShoulder…), и тогда
	-- набор R6 к ней не подойдёт.
	local kind = model.Name:match("^([%a_]+)_") or model.Name
	if not reported[kind] then
		reported[kind] = true
		local found = 0
		for _ in pairs(self.motors) do found += 1 end
		local names = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Motor6D") then table.insert(names, d.Name) end
		end
		if found < 6 then
			warn(("[CrewClips] %s: привязано суставов %d из 6. Motor6D в модели: %s")
				:format(model.Name, found,
					(#names > 0) and table.concat(names, ", ") or "НЕТ НИ ОДНОГО (риг не R6?)"))
		else
			print(("[CrewClips] %s: суставы привязаны (6 из 6)"):format(model.Name))
		end
	end

	return self
end

-- Зациклённая поза. Повтор того же имени ничего не сбрасывает — можно звать каждый кадр.
function Player:play(name: string)
	if self.loopName == name and not self.onceClip then return end
	local clip = CLIPS[name]
	if not clip then return end
	self.loopName = name
	if not self.onceClip then
		self.clip, self.t, self.fade = clip, 0, FADE
	end
end

-- Событие: доиграет и вернётся к текущему циклу.
function Player:once(name: string)
	local clip = CLIPS[name]
	if not clip then return end
	self.onceClip = clip
	self.clip, self.t, self.fade = clip, 0, FADE * 0.5
end

-- ── НАЛОЖЕНИЕ КЛИПА НА ЧАСТЬ ТЕЛА ──
-- Удар на бегу: сам бег продолжает крутиться, а клип удара накладывается ТОЛЬКО
-- на перечисленные суставы (обычно правая рука). Раньше атака подменяла позу
-- целиком, и пират ради взмаха останавливался столбом.
--   p:overlay("SabreSwing", { ["Right Arm"] = true })
function Player:overlay(name: string, joints)
	local clip = CLIPS[name]
	if not clip then return end
	self.ovClip = clip
	self.ovT = 0
	self.ovJoints = joints
end

function Player:overlayDone()
	return self.ovClip == nil
end

-- Суставы могли ПОЯВИТЬСЯ ПОЗЖЕ привязки: сервер строит их при спавне, а клиентский
-- attach() успевает раньше, чем Motor6D доедут по репликации. Кэш с пустым списком
-- раньше жил вечно — «0 из 6» оставалось навсегда. Теперь пустой список
-- перепроверяется раз в секунду, пока суставы не найдутся.
function Player:rescan()
	self.rescanT = (self.rescanT or 0)
	if self.rescanT > 0 then return end
	self.rescanT = 1
	local found = 0
	for part, motorName in pairs(MOTOR_OF) do
		if not self.motors[part] then
			for _, d in ipairs(self.model:GetDescendants()) do
				if d:IsA("Motor6D") and d.Name == motorName then
					self.motors[part] = d
					break
				end
			end
		end
		if self.motors[part] then found += 1 end
	end
	if found >= 6 and not self.rescanDone then
		self.rescanDone = true
		print(("[CrewClips] %s: суставы доехали (%d из 6) — анимация пошла"):format(self.model.Name, found))
	end
end

-- Распустить позу: суставы в покой, проигрывание остановлено. Зовётся по смерти —
-- дальше трупом занимается физика (рэгдолл/отброс), а не клип ходьбы.
function Player:relax()
	self.clip, self.onceClip, self.loopName = nil, nil, nil
	self.ovClip, self.ovJoints = nil, nil
	for _, motor in pairs(self.motors) do
		motor.Transform = CFrame.new()
	end
end

function Player:step(dt: number)
	if not next(self.motors) then
		self.rescanT = (self.rescanT or 0) - dt
		self:rescan()
		if not next(self.motors) then return end
	end
	if not self.clip then return end
	self.t += dt

	local pose, finished = sample(self.clip, self.t)
	if finished and self.onceClip then
		-- событие кончилось — возвращаемся к циклу
		self.onceClip = nil
		local back = self.loopName and CLIPS[self.loopName]
		if back then
			self.clip, self.t, self.fade = back, 0, FADE
			pose = sample(back, 0)
		end
	end

	-- Переход считаем ЛИНЕЙНО от предыдущей позы: без него смена клипа выглядит
	-- рывком, особенно при ударе из ходьбы.
	local blend = 1
	if self.fade > 0 then
		self.fade = math.max(0, self.fade - dt)
		blend = 1 - (self.fade / FADE)
	end

	-- ── НАЛОЖЕННЫЙ КЛИП поверх основного, только на свои суставы ──
	-- Считаем ПОСЛЕ основной позы и просто перекрываем в ней нужные записи:
	-- бег продолжает вести ноги и корпус, а рука в это время бьёт.
	if self.ovClip then
		self.ovT += dt
		local ovPose, ovDone = sample(self.ovClip, self.ovT)
		-- на въезде и выезде смешиваем с базой, иначе рука дёргается на стыке
		local L = self.ovClip.length
		local EDGE = math.min(0.12, L * 0.25)
		local w = 1
		if self.ovT < EDGE then
			w = self.ovT / EDGE
		elseif self.ovT > L - EDGE then
			w = math.max(0, (L - self.ovT) / EDGE)
		end
		for part in pairs(self.ovJoints or {}) do
			local target = ovPose[part]
			if target then
				local base = pose[part]
				pose[part] = base and base:Lerp(target, w) or target
			end
		end
		if ovDone then
			self.ovClip, self.ovJoints = nil, nil
		end
	end

	local retarget = self.model:GetAttribute("RigRetarget") == "R6"
	if retarget and not self.conv then self.conv = {} end
	for part, motor in pairs(self.motors) do
		local target = pose[part]
		if target and retarget then
			-- пересчёт позы стандартного R6 в суставы этой модели (см. STD_R6)
			local c = self.conv[part]
			local std = STD_R6[motor.Name]
			if not c and std then
				c = { motor.C0:Inverse() * std[1], std[2]:Inverse() * motor.C1 }
				self.conv[part] = c
			end
			if c then target = c[1] * target * c[2] end
		end
		if target then
			if blend < 1 then
				motor.Transform = motor.Transform:Lerp(target, math.clamp(blend, 0.05, 1))
			else
				motor.Transform = target
			end
		end
	end
end

return CrewClips
