--[[
	ДВИЖЕНИЕ РЫБАЦКОЙ ЛОДКИ — ОБЩАЯ МАТЕМАТИКА ДЛЯ СЕРВЕРА И КЛИЕНТА.

	⚠️ ЗАЧЕМ ОБЩИЙ МОДУЛЬ. Лодка кинематическая: её детали заякорены, а положение
	пишется CFrame'ом. Свойства реплицируются РЕЖЕ, чем идут кадры, поэтому лодка,
	которую двигает только сервер, приезжает клиенту ступеньками — и трясётся всё:
	и сама лодка, и стоящий на ней игрок, и камера за ним.

	Лечится так: сервер публикует НЕ ПОЗИЦИЮ, А СОСТОЯНИЕ (откуда вышла, куда
	идёт, когда стартовала) в атрибутах модели, а положение по этому состоянию
	считает КАЖДАЯ сторона сама — по общим часам workspace:GetServerTimeNow().
	Клиент делает это каждый кадр и получает идеально гладкий ход; сервер — редко,
	только чтобы остальные игроки и его собственные запросы видели лодку на месте.
	Формула одна на всех, поэтому расхождения нет.

	Атрибуты модели (пишет сервер, читают оба):
	  StartX/StartZ, HeadX/HeadZ  — точка и направление выхода
	  StartT                      — время старта (серверные часы)
	  Speed, WaterY               — ход и уровень воды
	  SinkAt                      — когда начала тонуть (nil, пока идёт)
	  ChefRel                     — место моряка в системе лодки (CFrame)
	  ClipName, ClipStart         — что играет моряк и с какого момента
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

local SkiffMotion = {}

SkiffMotion.SINK_TIME  = 6      -- сколько тонет, прежде чем исчезнуть
SkiffMotion.SINK_DEPTH = 9      -- на сколько студов уходит под воду
SkiffMotion.SINK_ROLL  = math.rad(28)

-- ── положение лодки в момент t (серверные часы) ──
function SkiffMotion.originCF(model, t)
	local sx, sz = model:GetAttribute("StartX"), model:GetAttribute("StartZ")
	local hx, hz = model:GetAttribute("HeadX"), model:GetAttribute("HeadZ")
	local t0 = model:GetAttribute("StartT")
	local speed = model:GetAttribute("Speed")
	local waterY = model:GetAttribute("WaterY")
	if not (sx and sz and hx and hz and t0 and speed and waterY) then return nil end

	local age = math.max(0, t - t0)
	local heading = Vector3.new(hx, 0, hz)
	if heading.Magnitude < 1e-4 then heading = Vector3.new(0, 0, -1) end
	heading = heading.Unit

	-- ход: во время затопления мотор глохнет и лодка теряет скорость
	local sinkAt = model:GetAttribute("SinkAt")
	local travel
	if sinkAt then
		local before = math.max(0, sinkAt - t0)
		local st = math.clamp(t - sinkAt, 0, SkiffMotion.SINK_TIME)
		-- скорость линейно падает до нуля за половину времени затопления
		local decayFor = SkiffMotion.SINK_TIME * 0.5
		local extra
		if st <= decayFor then
			extra = speed * st * (1 - st / (2 * decayFor))
		else
			extra = speed * decayFor * 0.5
		end
		travel = before * speed + extra
	else
		travel = age * speed
	end

	local pos = Vector3.new(sx, 0, sz) + heading * travel

	-- качка: детерминированная, от общих часов — обе стороны считают одинаково
	local w = t * 0.9
	local heave = math.sin(w) * 0.22 + math.sin(t * 0.37) * 0.12
	local roll  = math.rad(math.sin(t * 0.7) * 1.1)
	local pitch = math.rad(math.sin(t * 1.05) * 0.5)

	local y = waterY + heave
	if sinkAt then
		local k = math.clamp((t - sinkAt) / SkiffMotion.SINK_TIME, 0, 1)
		-- уходит под воду с ускорением и заваливается на борт
		y -= SkiffMotion.SINK_DEPTH * (k * k)
		roll += SkiffMotion.SINK_ROLL * k
		pitch += math.rad(7) * k
	end

	local p = Vector3.new(pos.X, y, pos.Z)
	return CFrame.lookAt(p, p + heading) * CFrame.Angles(pitch, 0, roll)
end

-- ── клипы моряка (тот же формат, что у экипажа катеров) ──
local CLIPS
function SkiffMotion.clips()
	if CLIPS ~= nil then return CLIPS end
	CLIPS = false
	local mod = ReplicatedStorage:FindFirstChild("PirateCrewClips")
		or (ServerStorage and ServerStorage:FindFirstChild("PirateCrewClips"))
	if mod and mod:IsA("ModuleScript") then
		local ok, data = pcall(require, mod)
		if ok and type(data) == "table" and type(data.clips) == "table" then
			CLIPS = {}
			for name, clip in pairs(data.clips) do
				local keys = {}
				for _, k in ipairs(clip.keys) do
					local p = {}
					for joint, v in pairs(k.p) do
						p[joint] = CFrame.new(v[1], v[2], v[3],
							v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12])
					end
					table.insert(keys, { t = k.t, p = p })
				end
				table.sort(keys, function(a, b) return a.t < b.t end)
				CLIPS[name] = { loop = clip.loop, length = clip.length, keys = keys }
			end
		end
	end
	return CLIPS
end

function SkiffMotion.sample(clip, t)
	local keys = clip.keys
	local last = keys[#keys]
	if clip.loop and clip.length > 0 then
		t = t % clip.length
	elseif t >= last.t then
		return last.p
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
	local alpha = (span > 1e-5) and ((t - a.t) / span) or 0
	local out = {}
	for joint, cf in pairs(a.p) do
		out[joint] = cf:Lerp(b.p[joint] or cf, alpha)
	end
	return out
end

-- ── риг R6: ручная FK-раскладка (заякоренным деталям Motor6D не указ) ──
local BODY = { "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local IS_BODY = { Torso = true, Head = true, ["Left Arm"] = true,
	["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true }

function SkiffMotion.buildRig(model)
	local hrp = model:FindFirstChild("HumanoidRootPart", true)
	local torso = model:FindFirstChild("Torso", true)
	if not hrp or not torso then return nil end

	local rig = { hrp = hrp, torso = torso, joints = {}, extras = {} }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			rig.joints[d.Part1.Name] = { part = d.Part1, c0 = d.C0, c1i = d.C1:Inverse() }
		end
	end
	if not rig.joints["Torso"] then return nil end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= hrp and not IS_BODY[d.Name] then
			local host, hostD = nil, math.huge
			for name in pairs(IS_BODY) do
				local part = (name == "Torso") and torso or (rig.joints[name] and rig.joints[name].part)
				if part then
					local dist = (part.Position - d.Position).Magnitude
					if dist < hostD then host, hostD = name, dist end
				end
			end
			if host then
				local hp = (host == "Torso") and torso or rig.joints[host].part
				table.insert(rig.extras, { part = d, host = host, offset = hp.CFrame:ToObjectSpace(d.CFrame) })
			end
		end
	end
	return rig
end

function SkiffMotion.applyRig(rig, rootCF, pose)
	pose = pose or {}
	local cfs = { HumanoidRootPart = rootCF }
	rig.hrp.CFrame = rootCF

	local jt = rig.joints["Torso"]
	local torsoCF = rootCF * jt.c0 * (pose["Torso"] or CFrame.identity) * jt.c1i
	rig.torso.CFrame = torsoCF
	cfs["Torso"] = torsoCF

	for _, name in ipairs(BODY) do
		local j = rig.joints[name]
		if j then
			local cf = torsoCF * j.c0 * (pose[name] or CFrame.identity) * j.c1i
			j.part.CFrame = cf
			cfs[name] = cf
		end
	end
	for _, e in ipairs(rig.extras) do
		local base = cfs[e.host]
		if base and e.part.Parent then e.part.CFrame = base * e.offset end
	end
end

-- Поза моряка на момент t — по опубликованным ClipName/ClipStart.
function SkiffMotion.chefPose(model, t)
	local clips = SkiffMotion.clips()
	if not clips then return nil end
	local name = model:GetAttribute("ClipName")
	local start = model:GetAttribute("ClipStart") or 0
	local clip = name and clips[name]
	if not clip then return nil end
	return SkiffMotion.sample(clip, t - start)
end

return SkiffMotion
