local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ОГНЕМЁТ — клиент: струя, поза стрельбы, шкала топлива.

	Стреляем УДЕРЖАНИЕМ: нажал — сервер запускает струю, отпустил — гасит (но не
	раньше своей минимальной порции, это его дело). Клиент только шлёт start/stop
	и рисует.

	⚠️ СТРУЮ РИСУЕМ ПО АТРИБУТУ Firing НА ИНСТРУМЕНТЕ, А НЕ ПО СВОЕМУ НАЖАТИЮ.
	Атрибут ставит сервер, и он реплицируется всем — значит чужой огнемёт тоже
	виден. Рисовать по локальному нажатию значило бы, что чужие стреляют молча.

	⚠️ ПОЗА СЧИТАЕТСЯ КОДОМ И ПИШЕТСЯ ПОСЛЕ АНИМАТОРА.
	Тот же приём, что у карты (см. MapItem): у здешнего рига нет Motor6D, части
	держат AnimationConstraint, у которых есть свой Transform. Пишем в
	BindToRenderStep с приоритетом Character + 1 и повторяем в Stepped, потому
	что цель физического рига забирает решатель на шаге физики.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")

local Defs = require(ReplicatedStorage:WaitForChild("FlamethrowerDefs"))
local fireEvent = ReplicatedStorage:WaitForChild("FlamethrowerFire")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════ струя ═══════════

local jets = {}   -- [tool] = { emitters, light, sound }

-- ⚠️ ПРОВЕРКА ТЕКСТУР С ПОДМЕНОЙ.
-- Частица с незагрузившейся текстурой не рисуется вовсе — эмиттер работает,
-- топливо тратится, а на экране пусто, и понять это по игре нельзя. Поэтому
-- при старте прогружаем все свои картинки: какая не отдалась — пишем в лог и
-- подменяем встроенной, чтобы струя была видна в любом случае.
local BUILTIN_FLAME = "rbxasset://textures/particles/fire_main.dds"
local BUILTIN_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local texOverride = {}      -- [наш id] = запасная встроенная текстура

local function tex(id, fallback)
	return texOverride[id] or id
end

task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local checks = {
		{ id = Defs.TEX_FLAME_A, alt = BUILTIN_FLAME, name = "язык A" },
		{ id = Defs.TEX_FLAME_B, alt = BUILTIN_FLAME, name = "язык B" },
		{ id = Defs.TEX_FLAME_C, alt = BUILTIN_FLAME, name = "язык C" },
		{ id = Defs.TEX_PUFF,    alt = BUILTIN_FLAME, name = "клуб" },
		{ id = Defs.TEX_SMOKE,   alt = BUILTIN_SMOKE, name = "дым" },
		{ id = Defs.TEX_EMBER,   alt = "rbxasset://textures/particles/sparkles_main.dds", name = "уголёк" },
		-- чернила кракена: та же беда с молчаливой незагрузкой, тот же разбор
		{ id = Defs.TEX_INK_A,     alt = BUILTIN_FLAME, name = "клякса A" },
		{ id = Defs.TEX_INK_B,     alt = BUILTIN_FLAME, name = "клякса B" },
		{ id = Defs.TEX_INK_C,     alt = BUILTIN_FLAME, name = "клякса C" },
		{ id = Defs.TEX_INK_PUFF,  alt = BUILTIN_FLAME, name = "клуб чернил" },
		{ id = Defs.TEX_INK_WISP,  alt = BUILTIN_SMOKE, name = "хвост чернил" },
		{ id = Defs.TEX_INK_DROP,  alt = "rbxasset://textures/particles/sparkles_main.dds", name = "капля" },
		{ id = Defs.TEX_INK_CLING, alt = BUILTIN_FLAME, name = "потёки на жертве" },
		{ id = Defs.TEX_INK_FLIP,  alt = BUILTIN_FLAME, name = "флипбук чернил" },
	}
	local probes, byProbe = {}, {}
	for _, c in ipairs(checks) do
		if c.id and c.id ~= "" then
			local probe = Instance.new("ImageLabel")
			probe.Image = c.id
			table.insert(probes, probe)
			byProbe[c.id] = c
		end
	end
	if #probes == 0 then return end

	local ok = pcall(function()
		ContentProvider:PreloadAsync(probes, function(contentId, status)
			local c = byProbe[contentId]
			if c and status ~= Enum.AssetFetchStatus.Success then
				texOverride[c.id] = c.alt
				warn(("[Огнемёт/клиент] текстура «%s» (%s) не загрузилась: %s — беру встроенную")
					:format(c.name, contentId, tostring(status)))
			end
		end)
	end)
	if not ok then return end

	-- что-то подменили — пересобираем уже созданные струи
	if next(texOverride) then
		for tool, jet in pairs(jets) do
			for _, p in ipairs(jet.parts) do p:Destroy() end
			if jet.light then jet.light:Destroy() end
			if jet.sound then jet.sound:Destroy() end
			jets[tool] = nil
		end
	end
	for _, p in ipairs(probes) do p:Destroy() end
end)

-- ⚠️ ОРУЖИЙ ДВА: ОГНЕМЁТ И РУКА КРАКЕНА (Defs.VARIANTS).
-- Отличаются дулом, цветом и числами; вся остальная струя у них общая.
local function variantOf(tool)
	return Defs.variant(tool)
end

local function muzzleOf(tool)
	local v = variantOf(tool)
	local m = tool:FindFirstChild(v and v.muzzle or Defs.MUZZLE, true)
	if m and m:IsA("BasePart") then return m end
	local h = tool:FindFirstChild("Handle")
	return (h and h:IsA("BasePart")) and h or tool:FindFirstChildWhichIsA("BasePart", true)
end

-- ⚠️ СТРУЯ СОБРАНА СЛОЯМИ, А НЕ ОДНИМ ЭМИТТЕРОМ.
-- Одна текстура на всю струю выглядит мёртвой: спрайт один, значит все частицы
-- одинаковые, и глаз это ловит сразу. Слои дают жизнь:
--   ядро   — короткое, яркое, у самого дула;
--   тело   — три РАЗНЫХ языка пламени, у каждого свой силуэт и скорость;
--   клубы  — крупные катящиеся шары на излёте, иначе конец струи обрублен;
--   дым    — тёмный хвост позади огня;
--   искры  — мелкие угольки, летят дальше всех.
local function emitter(parent, cfg)
	local p = Instance.new("ParticleEmitter")
	p.Name = cfg.name
	p.Texture = cfg.texture
	p.Enabled = false
	p.Rate = cfg.rate
	p.Lifetime = cfg.life
	p.Speed = cfg.speed
	p.SpreadAngle = Vector2.new(cfg.spread, cfg.spread)
	p.EmissionDirection = Enum.NormalId.Front
	p.Size = cfg.size
	p.Transparency = cfg.transparency
	p.Color = cfg.color
	p.LightEmission = cfg.light or 0.9
	p.LightInfluence = 0
	p.Drag = cfg.drag or 0
	p.Acceleration = cfg.accel or Vector3.zero
	p.Rotation = cfg.rotation or NumberRange.new(0, 0)
	p.RotSpeed = cfg.rotSpeed or NumberRange.new(0, 0)
	p.ZOffset = cfg.z or 0
	if cfg.flipbook then
		-- см. предупреждение в FlamethrowerDefs: слой необязательный
		p.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		p.FlipbookMode = Enum.ParticleFlipbookMode.Loop
		p.FlipbookFramerate = NumberRange.new(20, 28)
	end
	p.Parent = parent
	return p
end

local HOT  = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 200)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 165, 45)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 45, 15)),
})
local FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.35),
	NumberSequenceKeypoint.new(0.25, 0.12),
	NumberSequenceKeypoint.new(1, 1),
})

local function buildJet(tool)
	local muzzle = muzzleOf(tool)
	if not muzzle then return nil end

	-- ⚠️ ЧАСТИЦЫ ВЫХОДЯТ ИЗ СОПЛА-ATTACHMENT, А НЕ ИЗ САМОЙ ДЕТАЛИ.
	-- У импортированного меша свои оси: EmissionDirection.Front — это -Z детали,
	-- и куда он смотрит, знает один импортёр. Первый заход бил струёй вдоль этой
	-- оси, и она уходила в самого игрока — эмиттеры работали, а на экране пусто.
	-- Attachment мы разворачиваем сами каждый кадр, ровно туда же, куда сервер
	-- считает урон, поэтому картинка и попадания сходятся.
	local nozzle = Instance.new("Attachment")
	nozzle.Name = "JetNozzle"
	nozzle.Parent = muzzle

	-- ⚠️ У КАЖДОГО ВАРИАНТА СВОЙ НАБОР СПРАЙТОВ.
	-- Огнемёт бьёт нарисованными языками пламени, рука кракена — кляксами
	-- чернил со щупальцами. Цвет у чернил уже в текстуре, поэтому tintFor
	-- отдаёт для них белый: второе домножение превратило бы градиент в грязь.
	local v = variantOf(tool) or Defs.VARIANTS[Defs.TOOL_NAME]
	local tex = Defs.bodyTextures(v)
	local parts = {}

	local CORE = Defs.tintFor(v, v.hot:Lerp(Color3.new(1, 1, 1), 0.6), v.hot)
	local BODY = Defs.tintFor(v, v.hot, v.cool)
	local SPARK = Defs.tintFor(v, v.hot, v.light)
	local GLOW = v.glow or 1

	-- ⚠️ РАЗМЕРЫ ПОДОБРАНЫ НА ГЛАЗ И ЗАНИЖЕНЫ ВТРОЕ ОТ ПЕРВОЙ ВЕРСИИ.
	-- Первый заход рисовал струю «как в кино»: клубы по 13 студов закрывали
	-- пол-экрана и самого игрока. Хочешь крупнее — тяни S, оно множит все слои
	-- разом и держит их пропорции.
	local S = 0.34

	-- ядро у дула: короткое и злое
	table.insert(parts, emitter(nozzle, {
		name = "JetCore", texture = tex[1], rate = 60,
		life = NumberRange.new(0.14, 0.2), speed = NumberRange.new(30, 40),
		spread = Defs.CONE_DEG * 0.5,
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8 * S),
			NumberSequenceKeypoint.new(0.5, 2.6 * S),
			NumberSequenceKeypoint.new(1, 1.2 * S),
		}),
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 0.9),
		}),
		color = CORE,
		light = GLOW, z = 0.5,
	}))

	-- тело струи: три языка с разной скоростью и вращением
	for i = 1, 3 do
		table.insert(parts, emitter(nozzle, {
			name = "JetBody" .. i, texture = tex[i], rate = 34,
			life = NumberRange.new(0.26 + i * 0.03, 0.4 + i * 0.04),
			speed = NumberRange.new(48 + i * 6, 62 + i * 6),
			spread = Defs.CONE_DEG * (0.7 + i * 0.15),
			size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1.2 * S),
				NumberSequenceKeypoint.new(0.45, (4.5 + i) * S),
				NumberSequenceKeypoint.new(1, (7.5 + i) * S),
			}),
			transparency = FADE, color = HOT, drag = 3,
			rotation = NumberRange.new(-25 * i, 25 * i),
			rotSpeed = NumberRange.new(-40, 40),
		}))
	end

	-- необязательный флипбук поверх тела — если в плейсе он вообще заработает
	local flip = Defs.flipFor(v)
	if flip then
		table.insert(parts, emitter(nozzle, {
			name = "JetFlip", texture = flip, rate = 26,
			life = NumberRange.new(0.3, 0.45), speed = NumberRange.new(50, 64),
			spread = Defs.CONE_DEG * 0.9,
			size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1.4 * S),
				NumberSequenceKeypoint.new(0.5, 5 * S),
				NumberSequenceKeypoint.new(1, 8 * S),
			}),
			-- у чернил цвет в текстуре: белый; у огня — готовый градиент HOT
			transparency = FADE, color = v.ink and Defs.tintFor(v) or HOT,
			drag = 3, flipbook = true, light = GLOW,
		}))
	end

	-- клубы на излёте: медленные, крупные, крутятся
	table.insert(parts, emitter(nozzle, {
		name = "JetPuff", texture = Defs.puffFor(v), rate = 12,
		life = NumberRange.new(0.5, 0.8), speed = NumberRange.new(34, 46),
		spread = Defs.CONE_DEG * 1.3,
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2 * S),
			NumberSequenceKeypoint.new(0.6, 9 * S),
			NumberSequenceKeypoint.new(1, 13 * S),
		}),
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.4, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		color = BODY,
		-- ⚠️ ТЕЛУ СТРУИ СВЕТИМОСТЬ ПОДНЯЛИ: на 0.6 фиолетовый уходил в бордовый,
		-- потому что оранжевая текстура просвечивала сквозь тон.
		drag = 5, accel = Vector3.new(0, 8, 0), light = GLOW * 0.95,
		rotSpeed = NumberRange.new(-70, 70), z = -0.5,
	}))

	-- дым: позади огня, живёт дольше всех
	table.insert(parts, emitter(nozzle, {
		name = "JetSmoke", texture = Defs.smokeFor(v), rate = 8,
		life = NumberRange.new(0.9, 1.5), speed = NumberRange.new(20, 32),
		spread = Defs.CONE_DEG * 1.5,
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2 * S),
			NumberSequenceKeypoint.new(1, 16 * S),
		}),
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(0.35, 0.65),
			NumberSequenceKeypoint.new(1, 1),
		}),
		color = ColorSequence.new(Color3.fromRGB(90, 75, 68), Color3.fromRGB(45, 40, 38)),
		drag = 4, accel = Vector3.new(0, 10, 0), light = 0,
		rotSpeed = NumberRange.new(-30, 30), z = -1,
	}))

	-- искры: летят дальше всех и падают
	table.insert(parts, emitter(nozzle, {
		name = "JetEmbers", texture = Defs.emberFor(v), rate = 30,
		life = NumberRange.new(0.5, 1.1), speed = NumberRange.new(25, 60),
		spread = Defs.CONE_DEG * 1.6,
		size = NumberSequence.new(0.6 * S, 0.03),
		transparency = NumberSequence.new(0.2, 1),
		color = SPARK,
		light = GLOW, drag = 2, accel = Vector3.new(0, 6, 0),
	}))

	local light = Instance.new("PointLight")
	light.Color = v.light
	light.Brightness = 0
	light.Range = 18   -- вместе со струёй: раньше засвечивал полплота
	light.Parent = muzzle

	-- звук тоже вариантный: огонь шипит, чернила хлюпают
	local sc = v.sndJet or { id = "rbxasset://sounds/snap.mp3", speed = 0.28, volume = 0.65 }
	local snd = Instance.new("Sound")
	snd.SoundId = sc.id
	snd.PlaybackSpeed = sc.speed
	snd.Volume = sc.volume
	snd.Looped = true
	snd.RollOffMaxDistance = 120
	snd.Parent = muzzle

	return { parts = parts, light = light, sound = snd, muzzle = muzzle, nozzle = nozzle }
end

-- Куда бьёт струя. ⚠️ ПРАВИЛО ОДИН-В-ОДИН С СЕРВЕРОМ (tickFlame): берём ось
-- ствола, но если она смотрит не туда, куда персонаж, доверяем персонажу.
-- Разойдутся правила — огонь будет рисоваться в одну сторону, а жечь в другую.
local function aimJet(tool, jet)
	local muzzle = jet.muzzle
	if not (muzzle and jet.nozzle) then return end
	local dir = muzzle.CFrame.LookVector
	local char = tool.Parent
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and dir:Dot(hrp.CFrame.LookVector) < 0.2 then
		dir = hrp.CFrame.LookVector
	end
	-- сопло выносим вперёд от центра детали, иначе частицы рождаются внутри меша
	local from = muzzle.Position + dir * 0.8
	jet.nozzle.WorldCFrame = CFrame.lookAt(from, from + dir)
end

-- Разовый отчёт при включении струи: по нему видно, дошёл ли до клиента флаг
-- Firing, куда прицеплены эмиттеры и живы ли они. Без него «эффекта нет»
-- неотличимо от «эффект есть, но не там».
local function reportJet(tool, jet, on)
	local muzzle = jet.muzzle
	print(("[Огнемёт/клиент] Firing=%s | слоёв %d | ствол %s | в Workspace=%s | текстура %s | Enabled=%s")
		:format(tostring(on), #jet.parts,
			muzzle and muzzle:GetFullName() or "НЕТ",
			tostring(muzzle and muzzle:IsDescendantOf(Workspace)),
			jet.parts[1] and jet.parts[1].Texture or "—",
			tostring(jet.parts[1] and jet.parts[1].Enabled)))
end

local function setJet(tool, on)
	local jet = jets[tool]
	if not jet then
		jet = buildJet(tool)
		jets[tool] = jet
	end
	if not jet then return end

	-- ⚠️ ЭМИТТЕР МОГ ПОГИБНУТЬ ВМЕСТЕ СО СТВОЛОМ.
	-- Сервер пересобирает инструмент при каждом взятии в руки (снимает якоря и
	-- варит заново), а деталь могла быть заменена целиком — тогда наши частицы
	-- остались висеть на осиротевшей детали и в мире их нет. Проверяем и
	-- пересобираем, иначе струя молча пропадает после первого же перезахвата.
	local alive = jet.muzzle and jet.muzzle:IsDescendantOf(Workspace)
		and jet.nozzle and jet.nozzle.Parent == jet.muzzle
		and jet.parts[1] and jet.parts[1].Parent == jet.nozzle
	if not alive then
		for _, p in ipairs(jet.parts) do p:Destroy() end
		if jet.light then jet.light:Destroy() end
		if jet.sound then jet.sound:Destroy() end
		jet = buildJet(tool)
		jets[tool] = jet
		if not jet then return end
	end

	for _, p in ipairs(jet.parts) do p.Enabled = on end
	jet.light.Brightness = on and 4 or 0
	if on then
		aimJet(tool, jet)   -- каждый кадр: ствол ходит вместе с игроком
		if not jet.sound.IsPlaying then jet.sound:Play() end
	else
		jet.sound:Stop()
	end

	if jet.lastOn ~= on then
		jet.lastOn = on
		if on then reportJet(tool, jet, on) end
	end
end

-- Обходим ВСЁ огненное оружие в мире, а не только своё: чужая струя должна быть
-- видна. Инструментов два вида (огнемёт и рука кракена), поэтому идём по
-- вариантам, а не по одному имени.
local function eachFlamethrower(fn)
	for _, char in ipairs(Workspace:GetChildren()) do
		if char:IsA("Model") then
			for _, tool in ipairs(char:GetChildren()) do
				if variantOf(tool) then fn(tool) end
			end
		end
	end
end

-- ═══════════ поза стрельбы ═══════════

-- Огнемёт держат обеими руками и водят стволом: руки и корпус качает вправо-
-- влево, голова провожает ствол. Торс сам по себе не крутим — иначе персонаж
-- разворачивается на месте и стрелять становится неудобно.
local POSE = {
	R6  = { ["Right Arm"] = { -70, 0, -14 }, ["Left Arm"] = { -62, 0, 16 }, ["Head"] = { -6, 0, 0 } },
	R15 = {
		RightUpperArm = { 40, 0, -12 },
		LeftUpperArm  = { 34, 0, 14 },
		RightLowerArm = { 55, 0, 0 },
		LeftLowerArm  = { 62, 0, 0 },
		Head          = { -6, 0, 0 },
	},
}

-- ⚠️ У РУКИ КРАКЕНА ПОЗА СВОЯ: ОНА ОДНОРУЧНАЯ.
-- Огнемёт держат двумя руками за корпус и цевьё — вторая рука там нужна. Рука
-- кракена надета на правую, и левая в той же позе висела бы в воздухе, будто
-- держит несуществующий ствол. Правая вытянута вперёд и чуть в сторону, левая
-- отведена назад для упора, голова вдоль выброса.
local POSE_KRAKEN = {
	R6  = { ["Right Arm"] = { -84, 0, -26 }, ["Left Arm"] = { 24, 0, 34 }, ["Head"] = { -8, 0, 0 } },
	R15 = {
		RightUpperArm = { 62, 0, -22 },
		LeftUpperArm  = { -18, 0, 26 },
		RightLowerArm = { 20, 0, 0 },
		LeftLowerArm  = { 34, 0, 0 },
		Head          = { -8, 0, 0 },
	},
}

-- ⚠️ С ОРУЖИЕМ В РУКАХ РУКА ВИСИТ ВНИЗ, А НЕ ТОРЧИТ ВПЕРЁД.
-- Штатная роблоксовская поза «держу инструмент» выносит руку горизонтально
-- вперёд, и раньше именно она была видна всё время, пока не стреляешь: игрок
-- ходил, вытянув огнемёт перед собой, а поза начиналась только с выстрелом —
-- будто он каждый раз поднимает оружие с пояса. Теперь пока оружие в руках,
-- играет ЭТА поза (рука опущена вдоль тела), а выстрел уже поднимает её из неё.
--
-- ⚠️ ЗНАК ТУТ ОБРАТЕН БОЕВОЙ ПОЗЕ, А ВЕЛИЧИНА — РОВНО ДО ВЕРТИКАЛИ.
-- У боевой по X отрицательные числа поднимают руку, значит опускают —
-- положительные. Но это поворот ОТ роблоксовской позы «рука вперёд», то есть от
-- горизонтали: сколько градусов положишь, на столько она и уйдёт вниз. Первый
-- заход поставил 76 — рука ушла далеко за спину, 42 всё ещё заносили назад.
-- Вертикаль здесь примерно на 25: похоже, штатная поза держит руку не под
-- прямым углом к телу, а заметно ниже, и «докручивать» до 90 не нужно.
local POSE_IDLE = {
	R6 = {
		["Right Arm"] = { 25, 0, -4 },
		["Left Arm"]  = { 22, 0, 4 },
		["Head"]      = { 0, 0, 0 },
	},
	R15 = {
		RightUpperArm = { -15, 0, -4 },
		LeftUpperArm  = { -13, 0, 4 },
		RightLowerArm = { -4, 0, 0 },
		LeftLowerArm  = { -4, 0, 0 },
		Head          = { 0, 0, 0 },
	},
}

-- какой набор поз играть — решает инструмент в руках
local poseSet = POSE

local motors, rig, scanned = {}, "R6", nil
local physicalRig = false

-- ⚠️ ПОЗА РАБОТАЕТ НА ЛЮБОМ РИГЕ, ВКЛЮЧАЯ ФИЗИЧЕСКИЙ.
-- Её однажды пришлось выключить: игрока отбрасывало назад, и подозрение пало
-- на неё — у AnimationConstraint Transform это цель для решателя, он тянет к
-- ней силой. Виновата оказалась не она, а сварка инструмента: сервер двигал
-- деталь ствола, когда огнемёт уже приварен к руке, и тащил за собой всю
-- сборку персонажа (см. weldTool в FlamethrowerSystem). Поза возвращена.
-- Амплитуды оставлены заниженными намеренно: на физическом риге резкая тряска
-- всё равно отдаёт в корпус, а разница на глаз невелика.
local function collectMotors(char)
	motors = {}
	scanned = char
	physicalRig = false
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	if not hum then return end
	rig = (hum.RigType == Enum.HumanoidRigType.R15) and "R15" or "R6"
	local set = POSE[rig]
	for _, d in ipairs(char:GetDescendants()) do
		local limb
		if d:IsA("AnimationConstraint") then
			physicalRig = true
			limb = d.Attachment1 and d.Attachment1.Parent and d.Attachment1.Parent.Name
		elseif d:IsA("Motor6D") then
			limb = d.Part1 and d.Part1.Name
		elseif d:IsA("Bone") then
			limb = d.Name
		end
		if limb and set[limb] then motors[limb] = d end
	end
end

local poseK, lastK, holdK = 0, 0, 0

-- ⚠️ ПОЗ ТЕПЕРЬ ДВЕ, И ОНИ ВЛОЖЕНЫ ДРУГ В ДРУГА.
--   hold — насколько оружие в руках: от штатной роблоксовской позы к опущенной;
--   k    — насколько идёт струя: от опущенной к боевой.
-- Раньше был один переход «штатная → боевая», и в промежутке игрок всё время
-- ходил с вытянутой вперёд рукой. Ведение стволом и отдачу множим на k: покой
-- должен быть спокойным, иначе опущенная рука качается сама по себе.
local function applyPose(hold, k, t)
	lastK = math.max(hold, k)
	local idleSet = POSE_IDLE[rig]
	local fireSet = poseSet[rig]
	-- ⚠️ АМПЛИТУДЫ НАРОЧНО МАЛЕНЬКИЕ, А ЧАСТОТА НИЗКАЯ.
	-- У здешнего рига суставы держит физика (AnimationConstraint), и поза — это
	-- ЦЕЛЬ для решателя, а не жёсткая установка. Первая версия трясла руками на
	-- 18 рад/с: решатель отрабатывал эту дрожь силой, и отдача расходилась по
	-- телу — персонажа отбрасывало на пару метров назад, ровно как когда-то на
	-- стройке плота. Медленное ведение стволом такого эффекта не даёт.
	local sweep = math.sin(t * 1.4) * 7 * k
	local kick  = math.sin(t * 6) * 0.5 * k     -- еле заметная отдача струи
	for name, motor in pairs(motors) do
		local idle = idleSet[name] or { 0, 0, 0 }
		local fire = fireSet[name] or idle
		local extraY = (name == "Head") and sweep * 0.8 or sweep
		local x = idle[1] + (fire[1] - idle[1]) * k + kick
		local y = idle[2] + (fire[2] - idle[2]) * k + extraY
		local z = idle[3] + (fire[3] - idle[3]) * k
		local target = CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
		motor.Transform = CFrame.identity:Lerp(target, hold)
	end
end

local function relaxPose()
	for _, motor in pairs(motors) do motor.Transform = CFrame.identity end
end

-- ═══════════ ввод ═══════════

local myTool = nil
local holding = false

local function myFlamethrower()
	local char = player.Character
	if not char then return nil end
	for _, t in ipairs(char:GetChildren()) do
		if variantOf(t) then return t end
	end
	return nil
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.KeyCode ~= Enum.KeyCode.ButtonR2 then return end
	if not myFlamethrower() then return end
	holding = true
	fireEvent:FireServer("start")
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.KeyCode ~= Enum.KeyCode.ButtonR2 then return end
	if not holding then return end
	holding = false
	fireEvent:FireServer("stop")
end)

-- ═══════════ шкала топлива ═══════════

local gui = Instance.new("ScreenGui")
gui.Name = "FlamethrowerFuel"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
gui.Enabled = false
gui.Parent = playerGui

local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -118)
bar.Size = UDim2.fromOffset(220, 16)
bar.BackgroundColor3 = Color3.fromRGB(25, 20, 18)
bar.BorderSizePixel = 0
bar.Parent = gui
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 8)
barCorner.Parent = bar

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Color3.fromRGB(255, 140, 40)
fill.BorderSizePixel = 0
fill.Parent = bar
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 8)
fillCorner.Parent = fill

local fuelText = Instance.new("TextLabel")
fuelText.Size = UDim2.fromScale(1, 1)
fuelText.BackgroundTransparency = 1
fuelText.Font = Enum.Font.GothamBold
fuelText.TextSize = 12
fuelText.TextColor3 = Color3.new(1, 1, 1)
fuelText.TextStrokeTransparency = 0.4
fuelText.Text = ""
fuelText.Parent = bar

-- ═══════════ покадровая работа ═══════════

RunService:BindToRenderStep("FlamePose", Enum.RenderPriority.Character.Value + 1, function(dt)
	-- струя у всех, включая чужие огнемёты
	eachFlamethrower(function(tool)
		setJet(tool, tool:GetAttribute("Firing") == true)
	end)

	myTool = myFlamethrower()
	gui.Enabled = myTool ~= nil
	-- набор поз выбираем по инструменту: рука кракена машет одной рукой
	poseSet = (myTool and myTool.Name == Defs.KRAKEN_NAME) and POSE_KRAKEN or POSE
	if myTool then
		local cap = myTool:GetAttribute(Defs.ATTR_CAP) or Defs.CAPACITY
		local have = myTool:GetAttribute(Defs.ATTR_FUEL) or 0
		local frac = math.clamp(have / math.max(cap, 1), 0, 1)
		local v = variantOf(myTool) or Defs.VARIANTS[Defs.TOOL_NAME]
		fill.Size = UDim2.fromScale(frac, 1)
		-- цвет шкалы под оружие: у руки кракена заряд фиолетовый, как и струя
		fill.BackgroundColor3 = (frac < 0.15) and Color3.fromRGB(210, 60, 40) or v.light
		-- ⚠️ ПУСТОЙ ЗАПАС ГОВОРИТ, ЧТО С НИМ ДЕЛАТЬ.
		-- Огнемёт заправляют у бака, рука кракена копится сама — совет «заправь у
		-- бака» на ней отправлял бы игрока делать невозможное.
		fuelText.Text = (have <= 0)
			and (v.refuelable and "ПУСТО — заправь у бака на плоту"
				or "ПУСТО — заряд копится сам")
			or ("Заряд %d%%  ·  %d сек"):format(
				math.floor(frac * 100 + 0.5), math.floor(frac * Defs.BURN_TIME))
	end

	-- ⚠️ ОПУЩЕННАЯ РУКА ДЕРЖИТСЯ ВСЁ ВРЕМЯ, ПОКА ОРУЖИЕ В РУКАХ.
	-- Боевая поза по-прежнему только на струе, но выходим мы в неё не из
	-- роблоксовской «рука вперёд», а из своей опущенной.
	local firing = myTool and myTool:GetAttribute("Firing") == true
	local char = player.Character
	if char and scanned ~= char then collectMotors(char) end

	local speed = firing and 3.5 or 3
	poseK = poseK + ((firing and 1 or 0) - poseK) * math.clamp(dt * speed, 0, 1)
	-- убирать оружие даём чуть медленнее, чем доставать: рывка не видно
	holdK = holdK + ((myTool and 1 or 0) - holdK) * math.clamp(dt * (myTool and 6 or 4), 0, 1)

	if next(motors) then
		if holdK > 0.01 then
			applyPose(holdK, poseK, os.clock())
		elseif lastK > 0.01 then
			relaxPose()
			lastK = 0
		end
	end
end)

-- Физический риг читает цель на шаге физики, а не при отрисовке — повторяем
-- последним значением, иначе решатель берёт то, что осталось от аниматора.
RunService.Stepped:Connect(function()
	if physicalRig and holdK > 0.01 and next(motors) then
		applyPose(holdK, poseK, os.clock())
	end
end)

player.CharacterAdded:Connect(function()
	-- holdK тоже с нуля: новый персонаж выходит с пустыми руками, и поза должна
	-- наезжать заново, а не остаться от прошлого тела
	motors, scanned, poseK, lastK, holdK, holding = {}, nil, 0, 0, 0, false
end)

fireEvent.OnClientEvent:Connect(function(action, a)
	if not _G.Notify then return end
	if action == "empty" then
		_G.Notify({ type = "warn", icon = "🔥", title = "Бак пуст",
			body = "Заправь огнемёт от бака на плоту" })
	elseif action == "full" then
		_G.Notify({ type = "info", icon = "🔥", title = "Бак полон" })
	elseif action == "nofuel" then
		_G.Notify({ type = "warn", icon = "⛽", title = "Нечем заправлять",
			body = "Нет топлива ни в канистре, ни в баке" })
	elseif action == "refueled" then
		_G.Notify({ type = "info", icon = "⛽", title = "Огнемёт заправлен",
			body = ("Залито %d мл"):format(a or 0) })
	end
end)

print("[Огнемёт/клиент] загружен: ЛКМ — струя, шкала топлива над хотбаром")
