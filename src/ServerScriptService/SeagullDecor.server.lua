-- SeagullDecor.server.lua
-- Декоративные чайки. Раз в 1–2 игровых дня над плотом пролетает стайка из 1–3 чаек:
-- они появляются сбоку, летят по прямой через небо на ~65 студов выше плота и исчезают
-- с другой стороны. Прозрачные, неубиваемые (не коллизят, не таргетятся) — чистый декор.
-- Линия пролёта каждый раз чуть смещена влево-вправо, так что чайки не идут всегда над
-- одной точкой. Иногда во время пролёта звучит крик чайки (позиционный, от самой птицы).
--
-- Модель: ReplicatedStorage.SeagullTween (собственная анимация полёта уже внутри).
-- Спавн — на сервере: одна стайка видна всем игрокам одинаково.

local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local Debris            = game:GetService("Debris")
local RunService        = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig"))

-- Ремоут ручного спавна для теста (кнопка у админа шлёт сюда). Создаём заранее,
-- чтобы клиент успел его дождаться.
local spawnRemote = ReplicatedStorage:FindFirstChild("SeagullSpawn")
if not spawnRemote then
	spawnRemote = Instance.new("RemoteEvent")
	spawnRemote.Name = "SeagullSpawn"
	spawnRemote.Parent = ReplicatedStorage
end

local function isAdmin(plr)
	return plr ~= nil and (table.find(Config.ADMIN_USER_IDS or {}, plr.UserId) ~= nil
		or (game.CreatorType == Enum.CreatorType.User and plr.UserId == game.CreatorId))
end

-- ── настройки ──
local MODEL_NAME   = "SeagullTween"
local ALTITUDE     = 35     -- на сколько студов ВЫШЕ плота летят (снизил с 65 для теста —
                            -- чтобы точно попадали в кадр; верни на 65, когда убедишься)
local FLOCK_MIN    = 1      -- сколько чаек в стайке
local FLOCK_MAX    = 2      -- было 3: троица над плотом кричала слишком плотно
local SPAWN_MIN    = 120    -- следующая стайка через 2..4 минуты (реальное время), сек
local SPAWN_MAX    = 240
local CROSS_DIST   = 220    -- половина длины пролёта (вход/выход за кадр)
local SIDE_SPREAD  = 45     -- случайный сдвиг линии пролёта влево-вправо от центра плота
local ALT_JITTER   = 8      -- разброс высоты между особями
local FLIGHT_MIN   = 15     -- длительность пролёта, сек (чем больше — тем медленнее/спокойнее)
local FLIGHT_MAX   = 24
local DAYTIME_ONLY = false  -- true = пускать только днём (ClockTime 6..18); false = в любое время

-- ── Крик чайки (3D-звук идёт от самой птицы: чем дальше, тем тише) ──
-- Каждая чайка каждые 6–12 сек (рандом) проигрывает СЛУЧАЙНЫЙ из этих звуков. У каждой
-- птицы свой независимый таймер + стартовый сдвиг → две чайки не кричат в один момент.
local SEAGULL_SOUND_IDS = {
	"rbxassetid://98190333485420",
	"rbxassetid://79677781256416",
	"rbxassetid://89446038273872",
}
local SOUND_VOLUME       = 0.6
-- вдвое реже, чем было (3–6): интервал — это ПАУЗА между криками, поэтому
-- «реже в 2 раза» = удвоенные границы
local SOUND_INTERVAL_MIN = 6   -- секунд между криками одной чайки (рандом MIN..MAX)
local SOUND_INTERVAL_MAX = 12

-- Если чайка визуально летит «задом наперёд» — выстави math.rad(180) (или ±90).
local MODEL_YAW_OFFSET = 0

-- ── подготовка клона ──
-- Не коллизит, не таргетится. Способ движения зависит от структуры модели:
--   * Motor6D-риг (кости-части двигает анимация): якорим ТОЛЬКО корень, остальное
--     невесомое и НЕ заякоренное — моторы/анимация двигают части, корень ведём твином.
--   * иначе (скин-меш / жёсткая сборка / свободные части): якорим ВСЁ, чтобы ничего
--     не отваливалось в океан; двигаем модель целиком через PivotTo. Скелетная
--     (bone) анимация при этом продолжает играть — она внутри меша, а не в физике.
-- Раньше корень якорился всегда, а остальное распускалось — если модель НЕ Motor6D-риг,
-- части просто падали/разлетались, и чайку было не видно.
local function prep(model)
	local root = model.PrimaryPart
	if not root then
		root = model:FindFirstChild("HumanoidRootPart")
			or model:FindFirstChildWhichIsA("BasePart", true)
		if root then model.PrimaryPart = root end
	end
	if not root then return nil, false end

	-- "Motor" ловит и legacy Motor (эта модель именно такая: Body.LeftMotor/RightMotor),
	-- и Motor6D (он наследует Motor). Раньше проверяли только Motor6D → legacy-риг не
	-- распознавался, всё якорилось, и крылья не могли двигаться.
	local isRig = model:FindFirstChildWhichIsA("Motor", true) ~= nil

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery   = false   -- лучи/таргет оружия проходят сквозь → «нельзя убить»
			d.CanTouch   = false
			if isRig and d ~= root then
				d.Anchored = false
				d.Massless = true
			else
				d.Anchored = true
			end
		end
	end
	return root, isRig
end

-- Взмахи крыльев. Родной скрипт модели (AnimationControl) вырезан вместе с его
-- конфликтующим движением, поэтому машем сами — той же механикой, что была в нём:
-- Body.LeftMotor/RightMotor.DesiredAngle по синусу (амплитуда 0.3, частота 5).
-- Если у модели вдруг есть и объект Animation — тоже запустим его через Animator.
local function driveFlap(model)
	local body = model:FindFirstChild("Body") or model.PrimaryPart
	local lm = body and body:FindFirstChild("LeftMotor")
	local rm = body and body:FindFirstChild("RightMotor")

	if lm and rm then
		pcall(function() -- чтобы DesiredAngle реально анимировал (legacy Motor)
			if lm.MaxVelocity < 0.1 then lm.MaxVelocity = 0.15 end
			if rm.MaxVelocity < 0.1 then rm.MaxVelocity = 0.15 end
		end)
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			if not model.Parent then conn:Disconnect(); return end
			local a = 0.3 * math.sin((os.clock() - t0) * 5)
			lm.DesiredAngle = a
			rm.DesiredAngle = -a
		end)
	end

	-- бонус: если внутри есть загружаемая Animation — заодно проигрываем и её
	local anim = model:FindFirstChildWhichIsA("Animation", true)
	if anim and anim.AnimationId ~= "" then
		local animator = model:FindFirstChildWhichIsA("Animator", true)
		if not animator then
			local ctrl = model:FindFirstChildWhichIsA("AnimationController")
				or Instance.new("AnimationController")
			ctrl.Parent = model
			animator = Instance.new("Animator", ctrl)
		end
		pcall(function()
			local track = animator:LoadAnimation(anim)
			track.Looped = true
			track:Play()
		end)
	end
end

-- Каждая чайка сама «поёт»: пока летит, каждые SOUND_INTERVAL_MIN..MAX сек проигрывает
-- СЛУЧАЙНЫЙ из звуков на своём личном 3D-Sound (сидит на птице → чем дальше, тем тише).
-- Личный таймер у каждой птицы + случайный стартовый сдвиг → 3 чайки не кричат синхронно.
local function birdSoundLoop(bird, root)
	if #SEAGULL_SOUND_IDS == 0 then return end

	local snd = Instance.new("Sound")
	snd.Volume             = SOUND_VOLUME
	snd.RollOffMode        = Enum.RollOffMode.InverseTapered
	snd.RollOffMinDistance = 30
	snd.RollOffMaxDistance = 300
	snd.Parent             = root -- позиционный: звук исходит от самой чайки

	task.spawn(function()
		task.wait(math.random() * SOUND_INTERVAL_MIN) -- разный старт у птиц (0..MIN)
		while bird.Parent and snd.Parent do
			snd.SoundId      = SEAGULL_SOUND_IDS[math.random(1, #SEAGULL_SOUND_IDS)]
			snd.TimePosition = 0
			snd:Play()
			task.wait(SOUND_INTERVAL_MIN + math.random() * (SOUND_INTERVAL_MAX - SOUND_INTERVAL_MIN))
		end
	end)
end

-- ── один пролёт одной чайки ──
local function launchSeagull(template, center, dir, perp)
	local bird = template:Clone()

	-- Вырезаем родные скрипты модели (AnimationControl + SeagullControlTween). Оба
	-- гонят собственные твины движения (вперёд на 2500 студов в цикле) и конфликтуют
	-- и между собой, и с нашим полётом. Взмахи крыльев и движение делаем сами.
	for _, s in bird:GetDescendants() do
		if s:IsA("BaseScript") then s:Destroy() end
	end

	local root, isRig = prep(bird)
	if not root then
		warn("[SeagullDecor] в модели нет ни одной BasePart — пропуск")
		bird:Destroy(); return
	end

	local side = (math.random() * 2 - 1) * SIDE_SPREAD
	local alt  = ALTITUDE + (math.random() * 2 - 1) * ALT_JITTER
	local yaw  = CFrame.Angles(0, MODEL_YAW_OFFSET, 0)

	local sPos = center + dir * (-CROSS_DIST) + perp * side + Vector3.new(0, alt, 0)
	local ePos = center + dir * ( CROSS_DIST) + perp * side + Vector3.new(0, alt, 0)
	local sCF  = CFrame.lookAt(sPos, sPos + dir) * yaw
	local eCF  = CFrame.lookAt(ePos, ePos + dir) * yaw

	-- поставить на старт
	if isRig then root.CFrame = sCF else bird:PivotTo(sCF) end
	bird.Parent = Workspace
	driveFlap(bird)
	birdSoundLoop(bird, root)

	local dur = FLIGHT_MIN + math.random() * (FLIGHT_MAX - FLIGHT_MIN)
	if isRig then
		-- корень заякорен, части висят на моторах → твиним CFrame корня
		local tw = TweenService:Create(root,
			TweenInfo.new(dur, Enum.EasingStyle.Linear),
			{ CFrame = eCF })
		tw.Completed:Connect(function() bird:Destroy() end)
		tw:Play()
	else
		-- всё заякорено → двигаем модель целиком ручным lerp пивота
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			if not bird.Parent then conn:Disconnect(); return end
			local a = (os.clock() - t0) / dur
			if a >= 1 then
				conn:Disconnect()
				bird:Destroy()
			else
				bird:PivotTo(sCF:Lerp(eCF, a))
			end
		end)
	end
	Debris:AddItem(bird, dur + 5) -- страховка от утечки
end

-- ── стайка: 1–3 чайки, общая линия/направление, лёгкий разброс и сдвиг по времени ──
local function spawnFlock()
	-- ищем модель сначала прямо в ReplicatedStorage, потом рекурсивно (вдруг вложена в папку)
	local template = ReplicatedStorage:FindFirstChild(MODEL_NAME)
		or ReplicatedStorage:FindFirstChild(MODEL_NAME, true)
	local raft     = Workspace:FindFirstChild("Raft")
	local pp       = raft and raft.PrimaryPart

	if not template then
		warn("[SeagullDecor] модель '" .. MODEL_NAME .. "' НЕ найдена в ReplicatedStorage. " ..
			"Проверь: точное имя (без пробелов, регистр) и что она лежит в ReplicatedStorage.")
		return
	end
	if not pp then
		warn("[SeagullDecor] нет Workspace.Raft с PrimaryPart — плот ещё не готов?")
		return
	end

	local center = pp.Position
	local ang    = math.random() * 2 * math.pi
	local dir    = Vector3.new(math.cos(ang), 0, math.sin(ang)) -- случайное горизонт. направление
	local perp   = Vector3.new(-dir.Z, 0, dir.X)                -- ось «лево-право» относительно полёта

	local n = math.random(FLOCK_MIN, FLOCK_MAX)
	print(("[SeagullDecor] стайка: %d шт., центр плота (%.0f, %.0f, %.0f), высота полёта Y=%.0f")
		:format(n, center.X, center.Y, center.Z, center.Y + ALTITUDE))
	for i = 1, n do
		task.delay((i - 1) * (0.4 + math.random() * 1.2), function()
			launchSeagull(template, center, dir, perp)
		end)
	end
end

-- Ручной спавн для теста: команда из бара (_G.SpawnSeagullFlock()) или кнопка админа.
_G.SpawnSeagullFlock = spawnFlock
spawnRemote.OnServerEvent:Connect(function(plr)
	local ok = isAdmin(plr)
	print("[SeagullDecor] ручной спавн от " .. plr.Name .. " (admin=" .. tostring(ok) .. ")")
	if ok then spawnFlock() end
end)

-- ── планировщик: реальное время, каждые SPAWN_MIN..MAX секунд ──
local function isDaytime()
	local t = Lighting.ClockTime
	return t >= 6 and t < 18
end

task.spawn(function()
	Workspace:WaitForChild("Raft", 30) -- дать плоту заспавниться

	while true do
		task.wait(SPAWN_MIN + math.random() * (SPAWN_MAX - SPAWN_MIN))
		if not DAYTIME_ONLY or isDaytime() then
			spawnFlock()
		end
	end
end)

print(("[SeagullDecor] ready (чайки каждые %d-%d сек, по %d-%d шт.)")
	:format(SPAWN_MIN, SPAWN_MAX, FLOCK_MIN, FLOCK_MAX))
