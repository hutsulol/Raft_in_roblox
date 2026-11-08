-- LobbySpeaker.client.lua
-- Оживляет колонку в лобби под музыку:
--   • музыка звучит ИЗ колонки: рядом громко, дальше тише;
--   • корпус пружинит на басах: сплющивается, подпрыгивает и колышется с затуханием;
--   • конус динамика выталкивает вперёд на каждом ударе баса;
--   • из динамика (одна точка) расходится басовая волна — ровно на басах трека;
--   • ноты всплывают на новых нотах мелодии; цвет и высота зависят от высоты звука.
-- Положи в StarterPlayerScripts места лобби.
--
-- ЧТО НУЖНО В STUDIO
--   Колонка в Workspace — модель LobbySpeaker с мешами Speaker_Body и
--   Speaker_WooferCone (имена из FBX), все детали Anchored.
--
-- ⚠️ ВСЁ ЛОКАЛЬНО. У каждого игрока своя громкость и своя кнопка ♪.
-- Кто выключил музыку — у того колонка затихает.
--
-- КАК УСТРОЕН ЗВУК
--   Музыку играет ваш Sound (его находим сами, см. findMusic). Скрипт его не
--   двигает и не меняет громкость — кнопка ♪ работает как раньше. Вместо этого:
--   1. Оригинал глушим локальной SoundGroup с нулевой громкостью.
--   2. Его копия играет из корпуса колонки как 3D-звук с затуханием
--      (HEAR_FULL / HEAR_MAX) и повторяет за оригиналом: играет/пауза, время,
--      громкость, трек.
--   3. Ещё одна копия трека идёт в AudioAnalyzer (никуда не выводится) —
--      по её спектру ловим басы (30–150 Гц) и ноты мелодии (300–3000 Гц).
--   Если спектр недоступен, удары ловим по общей громкости, как раньше.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local OCEAN_PLACE_ID = 77272676169005
if game.PlaceId == OCEAN_PLACE_ID then return end

local CFG = {
	SPEAKER_NAME = "LobbySpeaker",

	-- ID картинок из lobby_speaker/vfx (Asset Manager → Import → Copy ID)
	TEXTURES = {
		NOTES = {
			"rbxassetid://71364857647624", -- note_eighth.png    ♪
			"rbxassetid://80313367324787", -- note_beamed.png    ♫
			"rbxassetid://88098239782027", -- note_sixteenth.png ♬
			"rbxassetid://80712811477390", -- note_quarter.png   ♩
		},
		RING = "rbxassetid://83798873980188", -- wave_ring.png
	},

	-- 12 цветов — по одному на каждую ноту октавы (до, до#, ре …)
	NOTE_COLORS = {
		Color3.fromRGB(255, 90, 90),   Color3.fromRGB(255, 140, 80),  Color3.fromRGB(255, 190, 70),
		Color3.fromRGB(255, 225, 90),  Color3.fromRGB(190, 235, 80),  Color3.fromRGB(110, 225, 110),
		Color3.fromRGB(60, 230, 200),  Color3.fromRGB(80, 200, 255),  Color3.fromRGB(110, 150, 255),
		Color3.fromRGB(165, 130, 255), Color3.fromRGB(220, 120, 255), Color3.fromRGB(255, 110, 190),
	},
	WAVE_COLOR = Color3.fromRGB(150, 255, 240),

	-- звук из колонки
	HEAR_FULL = 30,      -- ближе этого — полная громкость, стадов
	HEAR_MAX = 180,      -- дальше этого — тишина
	RESYNC = 0.25,       -- копии подтягиваем к оригиналу, если разошлись больше чем на столько секунд

	-- полосы спектра, Гц
	BASS_BAND = { 30, 150 },
	MELODY_BAND = { 300, 3000 },

	-- ритм: по последним секундам басов находим темп и долю,
	-- волна, толчок и ноты идут строго по сетке бита
	BEAT_WINDOW = 8,         -- сколько секунд слушаем, чтобы найти темп
	BPM_MIN = 70,
	BPM_MAX = 180,
	BEAT_CONFIDENCE = 0.25,  -- ниже — ритм неясен, бьём прямо по ударам баса
	TEMPO_SWITCH = 1.3,      -- новый темп сменит старый, только если он настолько увереннее
	BEAT_LEAD = 0.03,        -- бьём на столько секунд раньше доли: частице нужно время проявиться
	BASS_PRESENT = 0.2,      -- басы тише этой доли от пика (брейк) — волну не пускаем
	NOTE_EVERY = 2,          -- нота раз в столько битов
	NOTE_MIN_GAP = 0.5,      -- и не чаще раза в столько секунд

	-- детектор басов без сетки (пока темп не найден)
	BASS_RATIO = 1.45,   -- «быстрая» энергия баса выше средней во столько раз = удар
	BASS_REARM = 1.1,
	BASS_GAP = 0.25,

	-- басовая волна (размеры — в диаметрах динамика)
	WAVE_SIZE_FROM = 0.8,
	WAVE_SIZE_TO = 1.8,
	WAVE_LIFE = 0.5,
	WAVE_SPEED = 6,

	-- запасной детектор (без спектра): общая громкость
	BEAT_RATIO = 1.22,
	REARM_RATIO = 1.06,
	MIN_LOUD = 25,
	MIN_GAP = 0.2,

	-- упругость корпуса: пружина с затуханием
	BODY_K = 260,        -- жёсткость (больше — чаще дрожит)
	BODY_DAMP = 9,       -- затухание (меньше — дольше колышется)
	BODY_KICK = -1.8,    -- толчок на удар: минус = сначала сплющивает
	BODY_LIMIT = 0.2,
	WIDEN = 0.5,         -- насколько раздаётся вширь при сплющивании

	TILT_K = 140,
	TILT_DAMP = 7,
	TILT_KICK = 0.6,

	CONE_K = 1200,
	CONE_DAMP = 22,
	CONE_KICK = 3,
	CONE_LIMIT = 0.15,

	FX_DISTANCE = 250,   -- дальше этого частицы не пускаем
	ANIM_DISTANCE = 450, -- дальше этого колонку не анимируем
	BLEND_BODY_HEIGHT = 19.77, -- высота Speaker_Body в Blender: по ней считаем масштаб
}

local player = Players.LocalPlayer

-- ─── Слежка за звуками ───
local sounds = {}
local function track(root)
	for _, d in root:GetDescendants() do
		if d:IsA("Sound") then sounds[d] = true end
	end
	root.DescendantAdded:Connect(function(d)
		if d:IsA("Sound") then sounds[d] = true end
	end)
	root.DescendantRemoving:Connect(function(d)
		sounds[d] = nil
	end)
end
track(SoundService)
track(workspace)
task.spawn(function()
	track(player:WaitForChild("PlayerGui"))
end)

-- Оригиналы глушим этой группой; их настоящую группу помним здесь.
local muteGroup = Instance.new("SoundGroup")
muteGroup.Name = "LobbySpeakerMute"
muteGroup.Volume = 0
muteGroup.Parent = SoundService
local realGroup = {}   -- [оригинал] = его SoundGroup до нас (или false)
local ours = {}        -- наши копии — их не принимаем за музыку

local MUSIC_WORDS = { "music", "музык", "song", "track", "bgm", "lobby", "theme", "soundtrack" }

local function groupOf(s)
	local g = realGroup[s]
	if g == nil then return s.SoundGroup end
	return g or nil
end

local function audible(s)
	if not (s.Parent and s.IsPlaying and s.Volume > 0.01) then return false end
	local group = groupOf(s)
	return not group or group.Volume > 0.01
end

local function findMusic(wanted)
	local best, bestScore = nil, 0
	for s in sounds do
		if not ours[s] and audible(s) then
			local score = 0
			if wanted ~= "" then
				if s.Name == wanted then score = 100 end
			else
				local name = string.lower(s.Name)
				for _, w in MUSIC_WORDS do
					if string.find(name, w, 1, true) then score += 3; break end
				end
				if s.Looped then score += 2 end
				if s.TimeLength > 25 then score += 2 end
				-- шаги персонажа зациклены, но короткие: 2 очка — не музыка
				if score < 3 then score = 0 end
			end
			if score > bestScore then best, bestScore = s, score end
		end
	end
	return best
end

-- ─── Частицы ───
local function hasTexture(id)
	return type(id) == "string" and id ~= "" and id ~= "rbxassetid://0"
end

local function seq(points)
	local kps = {}
	for _, p in points do
		table.insert(kps, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(kps)
end

-- Волна: кольцо летит вдоль направления выброса и расширяется.
local function waveEmitter(att, sizeFrom, sizeTo, life, speed)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Wave"
	e.Texture = CFG.TEXTURES.RING
	e.Rate = 0
	e.EmissionDirection = Enum.NormalId.Front
	e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	e.Speed = NumberRange.new(speed)
	e.SpreadAngle = Vector2.zero
	e.Lifetime = NumberRange.new(life)
	e.Size = seq({ { 0, sizeFrom }, { 1, sizeTo } })
	e.Transparency = seq({ { 0, 0.05 }, { 0.55, 0.45 }, { 1, 1 } })
	e.Color = ColorSequence.new(CFG.WAVE_COLOR)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Brightness = 2
	e.ZOffset = 0.5
	e.Parent = att
	return e
end

local function noteEmitter(att, texture, color, scale)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Note"
	e.Texture = texture
	e.Rate = 0
	e.EmissionDirection = Enum.NormalId.Top
	e.Orientation = Enum.ParticleOrientation.FacingCamera
	e.Speed = NumberRange.new(2.5 * scale, 4.5 * scale)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Drag = 0.8
	e.Lifetime = NumberRange.new(1.8, 2.4)
	local s = 2 * scale
	e.Size = seq({ { 0, 0 }, { 0.1, s * 1.15 }, { 0.2, s }, { 0.8, s * 0.9 }, { 1, s * 0.6 } })
	e.Transparency = seq({ { 0, 0 }, { 0.7, 0 }, { 1, 1 } })
	e.Rotation = NumberRange.new(-20, 20)
	e.RotSpeed = NumberRange.new(-45, 45)
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.25
	e.LightInfluence = 0
	e.Parent = att
	return e
end

local function stepSpring(sp, k, c, dt)
	sp.v += (-k * sp.x - c * sp.v) * dt
	sp.x += sp.v * dt
end

-- Детектор удара по одной огибающей: резкий рост над средней.
local function newDetector()
	return { fast = 0, slow = 0, armed = true, last = 0 }
end

local function detect(d, value, dt, now, ratio, rearm, gap, floor)
	d.fast += (value - d.fast) * (1 - math.exp(-dt * 25))
	d.slow += (value - d.slow) * (1 - math.exp(-dt * 1.5))
	if d.armed and d.fast > d.slow * ratio and d.fast > floor and now - d.last > gap then
		d.armed, d.last = false, now
		return math.clamp((d.fast / math.max(d.slow, 1e-6) - 1) / 0.8, 0.45, 1)
	elseif not d.armed and d.fast < d.slow * rearm then
		d.armed = true
	end
	return nil
end

-- ─── Сетка бита ───
-- Копим «атаки» баса за BEAT_WINDOW секунд с шагом HOP. Раз в секунду:
--   темп — по автокорреляции (через сколько повторяется рисунок ударов),
--   доля — по гребёнке (при каком сдвиге сетки удары ложатся точнее всего).
-- Дальше бьём по предсказанной сетке, а не по каждому всплеску.
local HOP = 0.02
local function newBeatTracker()
	local n = math.floor(CFG.BEAT_WINDOW / HOP + 0.5)
	local tr = { buf = table.create(n, 0), lin = table.create(n, 0), w = 0, filled = 0,
		acc = 0, pend = 0, period = nil, nextBeat = nil, conf = 0, cand = nil,
		nextCalc = 0, lastFire = 0 }

	function tr.reset()
		if tr.filled == 0 and not tr.period then return end
		for i = 1, n do tr.buf[i] = 0 end
		tr.w, tr.filled, tr.acc, tr.pend = 0, 0, 0, 0
		tr.period, tr.nextBeat, tr.conf, tr.cand = nil, nil, 0, nil
	end

	function tr.push(onset, dt)
		tr.pend = math.max(tr.pend, onset)
		tr.acc += dt
		while tr.acc >= HOP do
			tr.acc -= HOP
			tr.w = tr.w % n + 1
			tr.buf[tr.w] = tr.pend
			tr.pend = 0
			tr.filled = math.min(tr.filled + 1, n)
		end
	end

	function tr.estimate(now)
		local m = tr.filled
		if m < n * 0.5 then return end
		local lin, mean = tr.lin, 0
		for i = 1, m do
			local v = tr.buf[(tr.w - m + i - 1) % n + 1] -- lin[m] — самое свежее
			lin[i] = v
			mean += v
		end
		mean /= m
		local r0 = 0
		for i = 1, m do
			local d = lin[i] - mean
			r0 += d * d
		end
		if r0 <= 1e-12 then tr.conf = 0; return end

		-- темп
		local lo = math.floor(60 / CFG.BPM_MAX / HOP)
		local hi = math.ceil(60 / CFG.BPM_MIN / HOP)
		local r = {}
		for L = lo - 1, hi + 1 do
			local s = 0
			for i = 1, m - L do
				s += (lin[i] - mean) * (lin[i + L] - mean)
			end
			r[L] = (s / (m - L)) / (r0 / m)
		end
		local best, bestScore = nil, -math.huge
		for L = lo, hi do
			-- лёгкое предпочтение ~120 BPM, чтобы не схватить половинный/двойной темп
			local prior = math.exp(-0.5 * (math.log(L * HOP / 0.5, 2) / 0.8) ^ 2)
			local score = r[L] * prior
			if r[L] >= r[L - 1] and r[L] >= r[L + 1] and score > bestScore then
				best, bestScore = L, score
			end
		end
		if not best then tr.conf = 0; return end
		local a, b, c = r[best - 1], r[best], r[best + 1]
		local den = a - 2 * b + c
		local off = den < 0 and math.clamp(0.5 * (a - c) / den, -0.5, 0.5) or 0
		local period = (best + off) * HOP

		-- насколько чётко держится уже найденный темп
		local curConf = 0
		if tr.period then
			local L = math.floor(tr.period / HOP + 0.5)
			curConf = r[L] or 0
		end

		if tr.period and math.abs(period / tr.period - 1) < 0.05 then
			tr.period += (period - tr.period) * 0.3
			tr.cand = nil
			tr.conf = b
		elseif not tr.period or (b > curConf * CFG.TEMPO_SWITCH and b >= CFG.BEAT_CONFIDENCE
			and tr.cand and math.abs(period / tr.cand - 1) < 0.05) then
			-- новый темп принимаем, только если он дважды подряд заметно увереннее старого
			tr.period, tr.cand, tr.nextBeat = period, nil, nil
			tr.conf = b
		else
			-- держим старый темп; уверенность — по нему
			tr.cand = b > curConf * CFG.TEMPO_SWITCH and period or nil
			tr.conf = curConf
			if curConf < CFG.BEAT_CONFIDENCE then return end
		end

		-- доля
		local P = tr.period / HOP
		local bestPh, bestSum = 0, -1
		for ph = 0, math.floor(P) - 1 do
			local s, k = 0, ph
			while k < m - 2 do
				local idx = m - math.floor(k + 0.5)
				s += lin[idx] + 0.5 * (lin[idx - 1] + (idx < m and lin[idx + 1] or 0))
				k += P
			end
			if s > bestSum then bestPh, bestSum = ph, s end
		end
		local target = now - bestPh * HOP + tr.period
		if tr.nextBeat then
			local half = tr.period / 2
			local err = (target - tr.nextBeat + half) % tr.period - half
			tr.nextBeat += err * 0.5
		else
			tr.nextBeat = target
		end
	end

	function tr.locked()
		return tr.period ~= nil and tr.nextBeat ~= nil and tr.conf >= CFG.BEAT_CONFIDENCE
	end

	-- true ровно один раз на каждую долю
	function tr.tick(now)
		if now >= tr.nextCalc then
			tr.nextCalc = now + 1
			tr.estimate(now)
		end
		if not tr.locked() then return false end
		local fire = false
		if now + CFG.BEAT_LEAD >= tr.nextBeat then
			while tr.nextBeat <= now + CFG.BEAT_LEAD do
				tr.nextBeat += tr.period
			end
			if now - tr.lastFire > tr.period * 0.5 then
				tr.lastFire = now
				fire = true
			end
		end
		return fire
	end

	return tr
end

-- ─── Звук из колонки ───
-- Копия оригинала играет из корпуса; вторая копия — в анализатор спектра.
local function newMirror(emitPart)
	local m = { orig = nil, voice = nil, player = nil, analyzer = nil, wire = nil,
		playing = false, nextSync = 0, soundId = "" }

	function m.detach()
		if m.orig then
			local g = realGroup[m.orig]
			if g ~= nil and m.orig.SoundGroup == muteGroup then
				m.orig.SoundGroup = g or nil
			end
			realGroup[m.orig] = nil
		end
		if m.voice then ours[m.voice] = nil; m.voice:Destroy() end
		for _, inst in { m.wire, m.player, m.analyzer } do
			if inst then inst:Destroy() end
		end
		m.orig, m.voice, m.player, m.analyzer, m.wire = nil, nil, nil, nil, nil
		m.playing = false
	end

	function m.attach(s)
		m.detach()
		m.orig = s
		realGroup[s] = s.SoundGroup or false
		s.SoundGroup = muteGroup

		local v = Instance.new("Sound")
		v.Name = "LobbySpeakerVoice"
		v.SoundId = s.SoundId
		v.Looped = s.Looped
		v.PlaybackSpeed = s.PlaybackSpeed
		v.RollOffMode = Enum.RollOffMode.InverseTapered
		v.RollOffMinDistance = CFG.HEAR_FULL
		v.RollOffMaxDistance = CFG.HEAR_MAX
		v.SoundGroup = realGroup[s] or nil
		ours[v] = true
		v.Parent = emitPart
		m.voice = v

		-- анализатор: работает только если новый Audio API доступен
		pcall(function()
			local p = Instance.new("AudioPlayer")
			p.Name = "LobbySpeakerAnalysis"
			p.Asset = s.SoundId
			p.Looping = s.Looped
			p.Volume = 1
			local a = Instance.new("AudioAnalyzer")
			a.Name = "LobbySpeakerAnalyzer"
			a.SpectrumEnabled = true
			local w = Instance.new("Wire")
			w.SourceInstance = p
			w.TargetInstance = a
			p.Parent = emitPart
			a.Parent = emitPart
			w.Parent = emitPart
			m.player, m.analyzer, m.wire = p, a, w
		end)
		m.soundId = s.SoundId
		m.playing = false
	end

	-- Повторяем за оригиналом: играет/пауза, время, громкость, смена трека.
	function m.sync(now)
		local s, v = m.orig, m.voice
		if not (s and v) then return end
		if s.SoundId ~= m.soundId then
			m.attach(s)
			s, v = m.orig, m.voice
		end
		v.Volume = s.Volume
		v.PlaybackSpeed = s.PlaybackSpeed
		local want = s.IsPlaying
		if want and not m.playing then
			v.TimePosition = s.TimePosition
			v:Play()
			v.TimePosition = s.TimePosition
			if m.player then
				pcall(function()
					m.player.TimePosition = s.TimePosition
					m.player:Play()
				end)
			end
			m.playing = true
			m.nextSync = now + 1
		elseif not want and m.playing then
			v:Pause()
			if m.player then pcall(function() m.player:Stop() end) end
			m.playing = false
		end
		if m.playing and now >= m.nextSync then
			m.nextSync = now + 1
			if math.abs(v.TimePosition - s.TimePosition) > CFG.RESYNC then
				v.TimePosition = s.TimePosition
			end
			if m.player then
				pcall(function()
					if math.abs(m.player.TimePosition - s.TimePosition) > CFG.RESYNC then
						m.player.TimePosition = s.TimePosition
					end
				end)
			end
		end
	end

	function m.spectrum()
		if m.broken or not (m.analyzer and m.playing) then return nil end
		local ok, spec = pcall(function() return m.analyzer:GetSpectrum() end)
		if ok and type(spec) == "table" and #spec > 8 then return spec end
		return nil
	end

	return m
end

-- ─── Колонка ───
local function run(model)
	local body = model:WaitForChild("Speaker_Body", 10)
	if not body then
		warn("[LobbySpeaker] в модели нет Speaker_Body — анимация выключена")
		return
	end
	local cone = model:FindFirstChild("Speaker_WooferCone", true)

	-- Опорная система: низ модели, «вперёд» — туда, куда смотрит динамик.
	local bbCF, bbSize = model:GetBoundingBox()
	local up = Vector3.yAxis
	local front = bbCF.LookVector
	if cone then
		local f = cone.Position - body.Position
		f = Vector3.new(f.X, 0, f.Z)
		if f.Magnitude > 1e-3 then front = f.Unit end
	end
	local bottom = bbCF.Position - up * (bbSize.Y / 2)
	local root0 = CFrame.lookAt(bottom, bottom + front)
	local scale = body.Size.Y / CFG.BLEND_BODY_HEIGHT
	local height = bbSize.Y

	local recs, parts = {}, {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			if not p.Anchored then
				warn(("[LobbySpeaker] %s не Anchored — включи Anchored у всех деталей колонки"):format(p.Name))
			end
			local rel = root0:ToObjectSpace(p.CFrame)
			table.insert(recs, {
				part = p, rel = rel, size = p.Size, isCone = p == cone,
				wy = Vector3.new(math.abs(rel.RightVector.Y), math.abs(rel.UpVector.Y), math.abs(rel.LookVector.Y)),
			})
			table.insert(parts, p)
		end
	end
	local cfs = table.create(#parts)
	local coneDiameter = cone and math.max(cone.Size.X, cone.Size.Y, cone.Size.Z) or 5 * scale
	local forwardLocal = Vector3.new(0, 0, -1)

	-- Невидимая деталь для частиц и звука. Звук — у динамика, чтобы он
	-- шёл именно оттуда, а не из центра модели.
	local fxPart = Instance.new("Part")
	fxPart.Name = "LobbySpeakerFX"
	fxPart.Anchored = true
	fxPart.CanCollide = false
	fxPart.CanQuery = false
	fxPart.CanTouch = false
	fxPart.Transparency = 1
	fxPart.Size = Vector3.one * 0.2
	local conePos = cone and cone.Position or (bottom + up * height * 0.33 + front * bbSize.Z / 2)
	fxPart.CFrame = CFrame.lookAt(conePos, conePos + front)
	fxPart.Parent = workspace

	local function attachment(worldCF)
		local a = Instance.new("Attachment")
		a.Parent = fxPart
		a.WorldCFrame = worldCF
		return a
	end

	-- одна точка волны — перед большим динамиком
	local wooferOut = conePos + front * coneDiameter * 0.15
	local wooferAtt = attachment(CFrame.lookAt(wooferOut, wooferOut + front))
	local noteAtt = attachment(root0)

	local wave
	if hasTexture(CFG.TEXTURES.RING) then
		wave = waveEmitter(wooferAtt, coneDiameter * CFG.WAVE_SIZE_FROM, coneDiameter * CFG.WAVE_SIZE_TO,
			CFG.WAVE_LIFE, CFG.WAVE_SPEED * scale)
	end
	-- byColor[i] = эмиттеры всех форм нот цвета i
	local byColor = {}
	for i, color in CFG.NOTE_COLORS do
		byColor[i] = {}
		for _, tex in CFG.TEXTURES.NOTES do
			if hasTexture(tex) then
				table.insert(byColor[i], noteEmitter(noteAtt, tex, color, scale))
			end
		end
	end
	if not wave or #byColor[1] == 0 then
		warn("[LobbySpeaker] нет ID картинок в CFG.TEXTURES — часть частиц не появится")
	end

	-- pitch01: 0 — низкая нота, 1 — высокая; pitchClass: 0..11 (до, до#, …)
	local function spawnNote(strength, pitch01, pitchClass)
		local list = byColor[(pitchClass % #CFG.NOTE_COLORS) + 1]
		if not list or #list == 0 then return end
		local ang = math.rad(math.random(-140, 140))
		local radius = (bbSize.X / 2 + 1 + math.random() * 3) * (0.9 + 0.2 * strength)
		local h = height * (0.3 + 0.6 * pitch01)   -- выше звук — выше нота
		local localPos = Vector3.new(math.sin(ang) * radius, h, -math.cos(ang) * radius)
		noteAtt.WorldPosition = root0:PointToWorldSpace(localPos)
		list[math.random(#list)]:Emit(1)
	end

	local mirror = newMirror(fxPart)

	-- состояние
	local nextScan = 0
	local bassDet, loudDet = newDetector(), newDetector()
	local beat = newBeatTracker()
	local prevSpec, prevLoud, lastNote, specZeroSince = nil, 0, 0, nil
	local envPeak, beatCount, trackId = 1e-6, 0, nil
	-- что звучит в мелодии последние ~0.3 с: энергия по 12 нотам октавы и средняя высота
	local chroma = table.create(12, 0)
	local melLog, melW = 0, 0
	local levelPeak, level, quietSince, act = 1e-6, 0, 0, 0
	local bodySp = { x = 0, v = 0 }
	local tiltSp = { x = 0, v = 0 }
	local coneSp = { x = 0, v = 0 }
	local tiltDir = 1
	local atRest = true

	local function bassHit(strength, nearFx)
		tiltDir = -tiltDir
		bodySp.v += CFG.BODY_KICK * strength
		tiltSp.v += CFG.TILT_KICK * strength * tiltDir
		coneSp.v += CFG.CONE_KICK * strength
		if nearFx and wave then wave:Emit(1) end
	end

	-- Сумма спектра в полосе частот. Бины линейные от 0 до 24 кГц.
	local function band(spec, lo, hi)
		local n = #spec
		local hz = 24000 / n
		local a = math.max(1, math.floor(lo / hz) + 1)
		local b = math.min(n, math.ceil(hi / hz) + 1)
		local sum = 0
		for i = a, b do sum += spec[i] end
		return sum, a, b, hz
	end

	local conn = RunService.Heartbeat:Connect(function(dt)
		dt = math.min(dt, 1 / 20)
		local now = os.clock()
		local cam = workspace.CurrentCamera
		local dist = cam and (cam.CFrame.Position - bottom).Magnitude or 0
		local nearFx = dist < CFG.FX_DISTANCE

		-- 1. какая музыка играет
		local orig = mirror.orig
		if not (orig and orig.Parent and audible(orig)) then
			if orig and not orig.Parent then mirror.detach() end
			if now >= nextScan then
				nextScan = now + 1
				local found = findMusic(model:GetAttribute("MusicName") or "")
				if found and found ~= mirror.orig then mirror.attach(found) end
			end
		end
		mirror.sync(now)
		local playing = mirror.orig ~= nil and audible(mirror.orig) and mirror.playing

		-- 2. басы и мелодия
		if mirror.soundId ~= trackId then
			trackId = mirror.soundId
			beat.reset() -- другой трек — темп ищем заново
		end
		local spec = playing and mirror.spectrum() or nil
		local onset, env, det = nil, 0, bassDet
		local keep = math.exp(-dt * 4)
		for i = 1, 12 do chroma[i] = chroma[i] * keep end
		melLog *= keep
		melW *= keep
		if spec then
			-- басы: энергия и её прирост («атака» удара)
			local _, ba, bb = band(spec, CFG.BASS_BAND[1], CFG.BASS_BAND[2])
			local bass, bassFlux = 0, 0
			for i = ba, bb do
				local v = spec[i]
				bass += v
				if prevSpec and prevSpec[i] then
					local d = v - prevSpec[i]
					if d > 0 then bassFlux += d end
				end
			end
			onset, env = bassFlux, bass
			if detect(bassDet, bass, dt, now, CFG.BASS_RATIO, CFG.BASS_REARM, CFG.BASS_GAP, 1e-5) then
				det.hit = true
			end

			-- мелодия: какие ноты сейчас звучат — по ним цвет и высота нот
			local _, a, b, hz = band(spec, CFG.MELODY_BAND[1], CFG.MELODY_BAND[2])
			local total = 0
			for i = a, b do
				local v = spec[i]
				total += v
				local freq = (i - 1) * hz
				if freq > 1 and v > 0 then
					local pc = math.floor(12 * math.log(freq / 261.63, 2) + 0.5) % 12 -- от «до»
					chroma[pc + 1] = chroma[pc + 1] + v * dt
					melLog += math.log(freq) * v * dt
					melW += v * dt
				end
			end
			prevSpec = spec
			levelPeak = math.max(levelPeak * math.exp(-dt * 0.15), total)
			level = math.clamp(total / levelPeak, 0, 1)
			if total > 1e-6 then
				quietSince = now
				specZeroSince = nil
			elseif mirror.voice and mirror.voice.PlaybackLoudness > CFG.MIN_LOUD then
				-- музыка слышна, а спектр пустой: анализатор не работает —
				-- переходим на запасной детектор по громкости
				specZeroSince = specZeroSince or now
				if now - specZeroSince > 1.5 then
					mirror.broken = true
					warn("[LobbySpeaker] спектр пустой — ловлю удары по громкости")
				end
			end
		elseif playing then
			-- запасной путь: общая громкость, ноты на ударах
			prevSpec = nil
			local loud = mirror.voice and mirror.voice.PlaybackLoudness or 0
			onset, env, det = math.max(0, loud - prevLoud), loud, loudDet
			prevLoud = loud
			if detect(loudDet, loud, dt, now, CFG.BEAT_RATIO, CFG.REARM_RATIO, CFG.MIN_GAP, CFG.MIN_LOUD) then
				det.hit = true
			end
			levelPeak = math.max(levelPeak * math.exp(-dt * 0.15), loud, 60)
			level = math.clamp(loud / levelPeak, 0, 1)
			if loud > CFG.MIN_LOUD then quietSince = now end
		else
			prevSpec = nil
			level = 0
			beat.reset()
		end

		-- 2б. удар: по сетке бита, а пока темп не найден — прямо по басу
		if onset then
			beat.push(onset, dt)
			envPeak = math.max(envPeak * math.exp(-dt * 0.3), env)
			local onGrid = beat.tick(now)
			local strength
			if beat.locked() then
				-- в брейке без басов сетка идёт дальше, но волну не пускаем
				if onGrid and det.slow > envPeak * CFG.BASS_PRESENT then
					strength = math.clamp(det.slow / envPeak * 1.6, 0.5, 1)
				end
			elseif det.hit then
				strength = math.clamp((det.fast / math.max(det.slow, 1e-6) - 1) / 0.8, 0.45, 1)
			end
			det.hit = nil
			if strength then
				bassHit(strength, nearFx)
				beatCount += 1
				if nearFx and beatCount % CFG.NOTE_EVERY == 0 and now - lastNote >= CFG.NOTE_MIN_GAP then
					lastNote = now
					local pc, top = 0, 0
					for i = 1, 12 do
						if chroma[i] > top then pc, top = i - 1, chroma[i] end
					end
					if top > 0 and melW > 0 then
						local lo, hi = math.log(CFG.MELODY_BAND[1]), math.log(CFG.MELODY_BAND[2])
						spawnNote(strength, math.clamp((melLog / melW - lo) / (hi - lo), 0, 1), pc)
					else
						-- без спектра: цвета идут по кругу квинт, высота случайная
						spawnNote(strength, math.random(), (math.floor(beatCount / CFG.NOTE_EVERY) * 7) % 12)
					end
				end
			end
		end
		local active = playing and now - quietSince < 0.6
		act += ((active and 1 or 0) - act) * (1 - math.exp(-dt * 4))

		-- 3. пружины (два полушага — устойчивее на низком FPS)
		for _ = 1, 2 do
			stepSpring(bodySp, CFG.BODY_K, CFG.BODY_DAMP, dt / 2)
			stepSpring(tiltSp, CFG.TILT_K, CFG.TILT_DAMP, dt / 2)
			stepSpring(coneSp, CFG.CONE_K, CFG.CONE_DAMP, dt / 2)
		end
		bodySp.x = math.clamp(bodySp.x, -CFG.BODY_LIMIT, CFG.BODY_LIMIT)
		coneSp.x = math.clamp(coneSp.x, -CFG.CONE_LIMIT, CFG.CONE_LIMIT)

		if dist > CFG.ANIM_DISTANCE then return end
		local lv = level * act
		local moving = math.abs(bodySp.x) + math.abs(bodySp.v) * 0.05 + math.abs(tiltSp.x)
			+ math.abs(coneSp.x) + lv
		if moving < 0.001 then
			if atRest then return end
			atRest = true
			bodySp.x, tiltSp.x, coneSp.x, lv = 0, 0, 0, 0
		else
			atRest = false
		end

		-- 4. поза: растяжение от низа, наклон вокруг оси «вперёд»
		local sy = 1 + bodySp.x
		local sxz = 1 - bodySp.x * CFG.WIDEN
		local root = root0 * CFrame.fromAxisAngle(forwardLocal, tiltSp.x)
		local push = (coneSp.x + math.sin(now * 40) * 0.012 * lv) * coneDiameter

		for i, r in recs do
			local pos = r.rel.Position
			local newPos = Vector3.new(pos.X * sxz, pos.Y * sy, pos.Z * sxz)
			if r.isCone then
				newPos += forwardLocal * push
			end
			local w, s = r.wy, r.size
			r.part.Size = Vector3.new(
				s.X * (sxz + (sy - sxz) * w.X),
				s.Y * (sxz + (sy - sxz) * w.Y),
				s.Z * (sxz + (sy - sxz) * w.Z)
			)
			cfs[i] = root * (CFrame.new(newPos) * r.rel.Rotation)
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)

	-- колонку удалили или выгрузил стриминг — возвращаем звук и ждём новую
	while model:IsDescendantOf(workspace) do
		model.AncestryChanged:Wait()
	end
	conn:Disconnect()
	mirror.detach()
	fxPart:Destroy()
end

while true do
	local model = workspace:FindFirstChild(CFG.SPEAKER_NAME)
	if model and model:IsA("Model") then
		run(model)
		task.wait(1)
	else
		workspace.ChildAdded:Wait()
	end
end
