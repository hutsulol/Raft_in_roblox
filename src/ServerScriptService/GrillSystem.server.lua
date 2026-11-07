-- GrillSystem.server.lua
-- МАНГАЛ (Raft_grill): топливо, горение и готовка еды на решётке.
--
-- Шаблон Raft_grill в ReplicatedStorage:
--   Raft_grill (Model)
--     ├─ raft_grill (MeshPart)      -- чаша
--     │    └─ Fire (BasePart, прозрачная)
--     │         └─ Fire (Fire)      -- само пламя
--     └─ raft_grill_grate (MeshPart) -- решётка, НА НЕЁ кладётся еда
--
-- Жизненный цикл:
--   * Поставлен → пламя выключено, решётка пустая.
--   * E → подбросить бревно. Пламя загорается, яркость и время горения
--     растут с числом брёвен; таймер общий, как у костра.
--   * Таймер истёк → пламя гаснет, готовка останавливается (прогресс
--     недожаренного куска сохраняется до следующего огня).
--   * Клик по мангалу → положить сырую еду из инвентаря на решётку
--     (максимум GRATE_SLOTS штук) либо забрать готовую.
--
-- Готовка использует ту же визуальную логику, что костёр: смену
-- raw/cooked декалей и текстур делает _G.CookFoodModel из
-- CampFireSystem, чтобы правила прожарки жили в одном месте.

local Players           = game:GetService("Players")
local rs                = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local CollectionService  = game:GetService("CollectionService")
local PlaceCheck = require(game:GetService("ReplicatedStorage"):WaitForChild("PlaceCheck"))   -- «место занято» — общая проверка

-- посадка еды на решётку считается общим модулем: тем же, что рисует призрак
local GrillFit = require(rs:WaitForChild("GrillFit"))
local RaftShake = require(rs:WaitForChild("RaftShake"))
local AssetFind = require(rs:WaitForChild("AssetFind"))

local cupActionEvent = rs:WaitForChild("CupAction")
-- ══════════════════════════════════════════════════════════════════
-- ЭФФЕКТ ГОРЯЩЕГО МАНГАЛА
-- ══════════════════════════════════════════════════════════════════
-- Пламя-флипбук, дым, искры, свечение углей и живой свет — по хендоффу
-- «Эффект горящего гриля».
--
-- ⚠️ ЖИВЁТ ПРЯМО ЗДЕСЬ, А НЕ В ОТДЕЛЬНОМ МОДУЛЕ.
-- Сначала это был ModuleScript рядом. Он не доехал до плейса, require его не
-- нашёл, и мангал остался без огня — а до правки с таймаутом ещё и вовсе
-- переставал ставиться, потому что WaitForChild вешал весь скрипт. Отдельный
-- файл здесь ничего не давал, кроме лишней точки отказа при синхронизации.
--
-- ⚠️ ВСЕ РАЗМЕРЫ И ВЫСОТЫ — ДОЛИ ОТ ГАБАРИТА ДЕТАЛИ ЧАШИ. Модули плота
-- импортируются в разном масштабе, и абсолютные значения в студах разъехались
-- бы с моделью.
local FX = {}

local RunService = game:GetService("RunService")
-- (сервис нужен только для мерцания света, см. ниже)


-- ── ассеты ──
--
-- ⚠️ ЕСЛИ ЭФФЕКТА НЕ ВИДНО — ПЕРВЫМ ДЕЛОМ ПОСТАВЬ ЗДЕСЬ true.
-- Тогда возьмутся встроенные в движок текстуры частиц: они гарантированно
-- грузятся и не зависят ни от прав на ассет, ни от модерации. Появился огонь —
-- значит дело было в загруженных картинках (частая причина: в ID попала
-- Decal-обёртка, а не само изображение), и чинить надо их, а не код.
local USE_BUILTIN_TEXTURES = false

local TEX_FLAME_FLIPBOOK = "rbxassetid://140408648514726"
local TEX_SMOKE          = "rbxassetid://119823157069030"
local TEX_EMBER          = "rbxassetid://89297532235809"
local TEX_GLOW           = "rbxassetid://139060183767447"
-- Огонь одним кадром, если флипбук почему-то не подойдёт:
-- local TEX_FLAME_SINGLE = "rbxassetid://103422128170220"

if USE_BUILTIN_TEXTURES then
	TEX_FLAME_FLIPBOOK = "rbxasset://textures/particles/fire_main.dds"
	TEX_SMOKE          = "rbxasset://textures/particles/smoke_main.dds"
	TEX_EMBER          = "rbxasset://textures/particles/sparkles_main.dds"
end

-- ── геометрия (доли от высоты детали, снизу) ──
local H_COAL_SURFACE = 0.24  -- поверхность углей: свечение
local H_FIRE_ROOT    = 0.29  -- верх горки углей: пламя, искры, дым, свет
local FIRE_ZONE_FRAC = 0.55  -- ширина зоны огня от ширины детали
-- Эффект по хендоффу выходил вдвое-втрое крупнее мангала: пламя било выше
-- стоек и перекрывало решётку. Делим ВСЕ стадии разом, а не каждую кривую
-- по отдельности, — так пропорции эффекта остаются теми же.
local SIZE_DIVIDER   = 2.5
local MIN_ZONE       = 0.5   -- студов: ниже этого пламя физически не разглядеть

-- Деталь-якорь внутри чаши. Если она есть в модели, эффект вешаем на НЕЁ:
-- автор поставил её ровно туда, где должен быть огонь, а вычисленная нами
-- точка «доля от габарита» уезжала к самому полу.
local FIRE_PART_NAME = "Fire"

local ROOT_NAME = "FireRoot"
local GLOW_NAME = "CoalGlow"

-- ── свет ──
local LIGHT_COLOR      = Color3.fromRGB(255, 140, 55)
local LIGHT_BRIGHTNESS = 2.5
local LIGHT_RANGE_MULT = 1.4  -- от наибольшего габарита детали

local function lockToPart(p)
	p.LockedToPart = true
end

local function seq(...)
	local keys = {}
	for _, kv in ipairs({ ... }) do
		table.insert(keys, NumberSequenceKeypoint.new(kv[1], kv[2]))
	end
	return NumberSequence.new(keys)
end

-- ─── Пламя ───
local function buildFire(root, zone)
	local p = Instance.new("ParticleEmitter")
	p.Name = "Fire"
	p.Texture = TEX_FLAME_FLIPBOOK
	p.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	p.FlipbookFramerate = NumberRange.new(20, 20)
	p.FlipbookMode = Enum.ParticleFlipbookMode.Loop
	-- САМОЕ ВАЖНОЕ ИЗ МЕЛОЧЕЙ: без случайного стартового кадра все языки пламени
	-- проигрывают анимацию синхронно, и костёр пульсирует целиком.
	p.FlipbookStartRandom = true
	-- Пламя обязано стоять вертикально, поэтому не FacingCamera.
	p.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	p.Rate = 14
	p.Lifetime = NumberRange.new(0.40, 0.65)
	p.Speed = NumberRange.new(0.6, 1.1)
	p.SpreadAngle = Vector2.new(6, 6)
	p.Acceleration = Vector3.new(0, 2, 0)
	p.Size = seq({0, zone * 0.55}, {0.35, zone * 0.85}, {1, zone * 0.15})
	p.Transparency = seq({0, 0.15}, {0.6, 0.05}, {1, 1})
	p.LightEmission = 1
	p.LightInfluence = 0 -- огонь светит сам, а не освещается
	p.ZOffset = 0.05
	-- Флипбук только у своей текстуры: у встроенной сетки кадров нет, и с
	-- Grid4x4 движок нарезал бы её на 16 кусочков.
	if USE_BUILTIN_TEXTURES then
		p.FlipbookLayout = Enum.ParticleFlipbookLayout.None
		p.Color = ColorSequence.new(Color3.fromRGB(255, 205, 120), Color3.fromRGB(255, 95, 25))
	end
	lockToPart(p)
	p.Enabled = false
	p.Parent = root
	return p
end

-- ─── Дым ───
local function buildSmoke(root, zone)
	local p = Instance.new("ParticleEmitter")
	p.Name = "Smoke"
	p.Texture = TEX_SMOKE
	p.Orientation = Enum.ParticleOrientation.FacingCamera
	p.Rate = 5
	p.Lifetime = NumberRange.new(1.8, 2.8)
	p.Speed = NumberRange.new(0.8, 1.3)
	p.SpreadAngle = Vector2.new(10, 10)
	p.Acceleration = Vector3.new(0.4, 1.6, 0) -- лёгкий снос ветром
	p.RotSpeed = NumberRange.new(-40, 40)
	p.Size = seq({0, zone * 0.35}, {1, zone * 1.6})
	p.Transparency = seq({0, 1}, {0.25, 0.55}, {1, 1})
	p.Color = ColorSequence.new(Color3.fromRGB(90, 88, 84), Color3.fromRGB(150, 150, 150))
	p.LightEmission = 0
	p.LightInfluence = 1 -- дым должен ловить свет от огня
	lockToPart(p)
	p.Enabled = false
	p.Parent = root
	return p
end

-- ─── Искры ───
local function buildEmbers(root, zone)
	local p = Instance.new("ParticleEmitter")
	p.Name = "Embers"
	p.Texture = TEX_EMBER
	p.Rate = 7
	p.Lifetime = NumberRange.new(1.0, 2.0)
	p.Speed = NumberRange.new(1.6, 3.0)
	p.SpreadAngle = Vector2.new(28, 28)
	p.Acceleration = Vector3.new(0, 3.2, 0)
	p.Drag = 1.6 -- искры затухают, а не улетают ракетой
	p.Size = seq({0, zone * 0.05}, {1, zone * 0.015})
	p.Transparency = seq({0, 0}, {0.7, 0.2}, {1, 1})
	p.Color = ColorSequence.new(Color3.fromRGB(255, 190, 110), Color3.fromRGB(200, 60, 20))
	p.LightEmission = 1
	lockToPart(p)
	p.Enabled = false
	p.Parent = root
	return p
end

-- ─── Свечение углей ───
-- Тонкая невидимая плашка с Decal сверху. Дешевле любого эмиттера, а именно она
-- даёт ощущение, что угли раскалены изнутри.
local function buildGlow(bowl, zone, height)
	local existing = bowl.Parent:FindFirstChild(GLOW_NAME)
	if existing then existing:Destroy() end

	local plate = Instance.new("Part")
	plate.Name = GLOW_NAME
	plate.Size = Vector3.new(zone, 0.05, zone)
	plate.Transparency = 1
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.Massless = true
	plate.Anchored = true
	plate.CFrame = bowl.CFrame * CFrame.new(0, -height * 0.5 + height * H_COAL_SURFACE, 0)
	plate.Parent = bowl.Parent

	local decal = Instance.new("Decal")
	decal.Texture = TEX_GLOW
	decal.Face = Enum.NormalId.Top
	decal.Transparency = 1
	decal.Parent = plate

	-- Приваривать НАДО: плашка едет вместе с мангалом по волнам, а якорь в
	-- сборке плота заморозил бы плот целиком.
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = bowl, plate
	weld.Parent = plate
	plate.Anchored = false

	return plate, decal
end

-- ─── Звук горения ───
-- Берём ЕГО ЖЕ, что у костра, а не хардкодим ID: звук лежит авторски внутри
-- шаблона FireCamp, и если его там поменяют, мангал зазвучит так же сам.
-- Ищем зацикленный Sound, пропуская одноразовый «Drop Log» (тот же разбор по
-- имени, что и в CampFireSystem).
local BURN_SOUND_NAME = "GrillBurnSound"
local campBurnSoundId, campBurnVolume

local function findCampfireBurnSound()
	if campBurnSoundId ~= nil then return campBurnSoundId, campBurnVolume end
	campBurnSoundId, campBurnVolume = "", 0.5
	local tpl = AssetFind.find("FireCamp")
	if not tpl then
		warn("[Grill/FX] шаблона FireCamp нет в ReplicatedStorage — звук горения "
			.. "взять неоткуда")
		return campBurnSoundId, campBurnVolume
	end
	for _, d in ipairs(tpl:GetDescendants()) do
		if d:IsA("Sound") and d.Name ~= "Drop Log" and d.SoundId ~= "" then
			campBurnSoundId = d.SoundId
			campBurnVolume = (d.Volume > 0) and d.Volume or 0.5
			print(("[Grill/FX] звук горения взят у костра: %s (%s)")
				:format(d.Name, d.SoundId))
			return campBurnSoundId, campBurnVolume
		end
	end
	warn("[Grill/FX] в шаблоне FireCamp не нашлось зацикленного звука горения")
	return campBurnSoundId, campBurnVolume
end

local function buildBurnSound(root)
	local id, vol = findCampfireBurnSound()
	if id == "" then return nil end
	local old = root:FindFirstChild(BURN_SOUND_NAME)
	if old then old:Destroy() end
	local s = Instance.new("Sound")
	s.Name = BURN_SOUND_NAME
	s.SoundId = id
	s.Volume = vol
	s.Looped = true
	s.RollOffMaxDistance = 80
	s.Parent = root
	return s
end

-- ─── Сборка ───
-- bowl — деталь чаши мангала (raft_grill). Возвращает таблицу с ссылками,
-- которую потом отдают в FX.setLit.
-- opts (необязательные, для вариантов мангала):
--   div     — во сколько раз дополнительно уменьшить пламя (бочка: огонёк мизерный)
--   minZone — свой нижний предел размера зоны (иначе общий MIN_ZONE)
function FX.build(bowl, opts)
	if not (bowl and bowl:IsA("BasePart")) then return nil end
	opts = opts or {}

	local size = bowl.Size
	local height = size.Y
	local zone = math.max(size.X, size.Z) * FIRE_ZONE_FRAC

	-- ⚠️ НИЖНИЙ ПРЕДЕЛ РАЗМЕРА ПЛАМЕНИ.
	-- Все размеры эффекта — доли габарита чаши, и это правильно: модули плота
	-- импортируются в разном масштабе. Но у исходного FBX габарит 0.78 × 0.60 ×
	-- 0.654 «в единицах модели», и если меш приехал в этом же масштабе, зона
	-- огня выходит меньше половины студа — частицы формально рождаются, но на
	-- экране их не видно совсем. Свет при этом виден, потому что его дальность
	-- считается иначе. Ровно так эффект и выглядел «только светом».
	zone = zone / SIZE_DIVIDER / (opts.div or 1)

	local minZone = opts.minZone or MIN_ZONE
	if zone < minZone then
		warn(("[Grill/FX] чаша слишком мелкая (%.2f × %.2f × %.2f студов) — "
			.. "зона огня %.2f поднята до %.2f, иначе частиц не видно")
			:format(size.X, size.Y, size.Z, zone, minZone))
		zone = minZone
	end

	-- ⚠️ КОРЕНЬ ЭФФЕКТА — АВТОРСКАЯ ДЕТАЛЬ "Fire", ЕСЛИ ОНА ЕСТЬ.
	-- Своя точка считалась как доля от габарита чаши, и на этой модели уезжала
	-- к самому полу: пламя било из палубы, а не из углей. Внутри чаши уже лежит
	-- прозрачная деталь Fire, поставленная руками ровно туда, где должен быть
	-- огонь, — она и есть правильный якорь. Свою деталь строим только как
	-- запасной вариант, если авторской нет.
	local root = bowl:FindFirstChild(FIRE_PART_NAME)
	if root and not root:IsA("BasePart") then root = nil end
	local ownRoot = false

	if root then
		-- Чужую деталь не переименовываем и не двигаем: она уже там, где надо.
		-- Только чистим свои прошлые эмиттеры, чтобы при повторной сборке они
		-- не копились.
		for _, d in ipairs(root:GetChildren()) do
			if d:IsA("ParticleEmitter") or d:IsA("PointLight") then d:Destroy() end
		end
		print(("[Grill/FX] якорь: авторская деталь %s, зона огня %.2f студа")
			:format(root:GetFullName(), zone))
	else
		ownRoot = true
		local old = bowl.Parent:FindFirstChild(ROOT_NAME)
		if old then old:Destroy() end

		-- ЭМИТТЕРЫ НА ДЕТАЛИ, А НЕ НА ATTACHMENT: во всём проекте частицы
		-- вешаются на BasePart (см. MuzzleFX), и этот вариант проверен.
		root = Instance.new("Part")
		root.Name = ROOT_NAME
		root.Size = Vector3.new(0.2, 0.2, 0.2)
		root.Transparency = 1
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
		root.Massless = true
		root.Anchored = true
		root.CFrame = bowl.CFrame * CFrame.new(0, -height * 0.5 + height * H_FIRE_ROOT, 0)
		root.Parent = bowl.Parent

		-- Сварка, а не якорь: заякоренная деталь внутри сборки плота заморозила
		-- бы плот целиком.
		local rootWeld = Instance.new("WeldConstraint")
		rootWeld.Part0, rootWeld.Part1 = bowl, root
		rootWeld.Parent = root
		root.Anchored = false

		warn(("[Grill/FX] детали '%s' в чаше нет — эффект собран на своей точке, "
			.. "огонь может идти не из углей"):format(FIRE_PART_NAME))
	end

	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Brightness = LIGHT_BRIGHTNESS
	light.Range = math.max(size.X, size.Y, size.Z) * LIGHT_RANGE_MULT
	light.Shadows = true
	light.Enabled = false
	light.Parent = root

	local plate, decal = buildGlow(bowl, zone, height)

	local fx = {
		root   = root,
		fire   = buildFire(root, zone),
		smoke  = buildSmoke(root, zone),
		embers = buildEmbers(root, zone),
		light  = light,
		plate  = plate,
		glow   = decal,
		zone   = zone,
		ownRoot = ownRoot,
		burnSound = buildBurnSound(root),
	}

	-- МЕРЦАНИЕ — ПЛАВНЫЙ ШУМ, А НЕ РАНДОМ КАЖДЫЙ КАДР: случайное значение на
	-- каждом кадре читается как стробоскоп, а не как живой огонь.
	local t = 0
	fx.flicker = RunService.Heartbeat:Connect(function(dt)
		if not light.Parent then
			fx.flicker:Disconnect()
			return
		end
		if not light.Enabled then return end
		t += dt
		local base = LIGHT_BRIGHTNESS * (fx.intensity or 1)
		light.Brightness = base + 0.35 * (math.noise(t * 2.2) + 0.5 * math.noise(t * 5.7))
	end)

	return fx
end

-- ─── Включение ───
-- Гасим Enabled, а НЕ удаляем эмиттеры: уже отрождённые частицы дожгут свой
-- Lifetime, и костёр потухнет плавно, а не исчезнет кадром.
-- intensity — множитель от числа брёвен: больше дров, крупнее пламя и ярче свет.
function FX.setLit(fx, lit, intensity)
	if not fx then return end
	intensity = intensity or 1
	fx.intensity = intensity

	local n = 0
	for _, p in ipairs(fx.root:GetChildren()) do
		if p:IsA("ParticleEmitter") then
			p.Enabled = lit
			n += 1
		end
	end
	fx.light.Enabled = lit
	if fx.glow then fx.glow.Transparency = lit and 0 or 1 end

	-- Звук горения — тот же, что у костра. Заводим и глушим вместе с огнём.
	if fx.burnSound then
		if lit and not fx.burnSound.IsPlaying then
			fx.burnSound:Play()
		elseif not lit and fx.burnSound.IsPlaying then
			fx.burnSound:Stop()
		end
	end

	-- Печатаем ОДИН раз при зажигании: если эмиттеров 0 — эффект не собрался,
	-- если 3, а на экране пусто — не грузятся текстуры (проверь права на ассеты
	-- и что ID именно картинок, а не Decal-обёрток).
	if lit and not fx.reported then
		fx.reported = true
		print(("[Grill/FX] зажжён: эмиттеров %d | пламя=%s дым=%s искры=%s")
			:format(n, fx.fire.Texture, fx.smoke.Texture, fx.embers.Texture))
	end

	if lit then
		-- Крупнее пламя и шире свечение при большем костре. Форму кривой не
		-- трогаем — только масштаб, иначе пламя теряет силуэт.
		local z = fx.zone * intensity
		fx.fire.Size = seq({0, z * 0.55}, {0.35, z * 0.85}, {1, z * 0.15})
		fx.smoke.Size = seq({0, z * 0.35}, {1, z * 1.6})
		fx.light.Range = fx.light.Range -- дальность оставляем от габарита детали
	end
end

function FX.destroy(fx)
	if not fx then return end
	if fx.flicker then fx.flicker:Disconnect() end
	if fx.plate then fx.plate:Destroy() end
	if not fx.root then return end
	if fx.ownRoot then
		-- Деталь наша — сносим целиком.
		fx.root:Destroy()
	else
		-- Корень авторский (деталь Fire из модели): сносим ТОЛЬКО то, что
		-- добавили сами, иначе вместе с эффектом удалили бы кусок модели.
		for _, d in ipairs(fx.root:GetChildren()) do
			if d:IsA("ParticleEmitter") or d:IsA("PointLight")
				or (d:IsA("Sound") and d.Name == BURN_SOUND_NAME) then
				d:Destroy()
			end
		end
	end
end

local LOG_TAG = "[Grill]"

-- ─── Настройки ────────────────────────────────────────────────────
-- ── ВАРИАНТЫ МАНГАЛА ──
-- Их два, и логика у них одна: меняются только имена деталей модели, число мест
-- на решётке и темп готовки. Бочка (Raft_grill_barrel) больше и быстрее; у неё
-- ещё и угли меняют текстуру, когда горит огонь.
local VARIANTS = {
	Raft_grill = {
		bowl = "raft_grill", grate = "raft_grill_grate",
		slots = 2, cookMult = 1,
	},
	Raft_grill_barrel = {
		bowl = "raft_grill_barrel", grate = "raft_grill_barrel_grate",
		slots = 4, cookMult = 0.6,          -- больше места, готовит быстрее
		coals = "raft_grill_barrel_coals",  -- угли: холодные / раскалённые
		coalsCold = "rbxassetid://82459811744189",
		coalsHot  = "rbxassetid://80889317613439",
		-- ⚠️ ОГОНЬ СТРОИМ НА УГЛЯХ, А НЕ НА КОРПУСЕ. Размер и точка эффекта —
		-- доли габарита детали-основания: у бочки корпус огромный, поэтому
		-- пламя било вбок и во весь экран. Угли — ровно та деталь, из центра
		-- которой должен идти огонёк, и он тут мизерный.
		fireHost = "raft_grill_barrel_coals",
		fireDiv = 3.2, fireMinZone = 0.18,
	},
}

local MODEL_NAME  = "Raft_grill"          -- вариант по умолчанию (совместимость)
local BOWL_NAME   = "raft_grill"
local GRATE_NAME  = "raft_grill_grate"

local function variantOf(model)
	return VARIANTS[model.Name] or VARIANTS[MODEL_NAME]
end

local MAX_LOGS        = 4
local LOG_BASE_TIME   = 25    -- сек горения от одного свежего бревна
local MAX_BONUS       = 12    -- добавка, если подбросить в догорающий
local BONUS_THRESHOLD = 20    -- остаток меньше этого → пропорциональный бонус
local TICK            = 0.5   -- шаг таймера горения
local PROMPT_RANGE    = 12
local ADD_COOLDOWN    = 0.2   -- минимум между брёвнами (защита от зажатой E)

-- ЗВУК ЖАРКИ. Отдельного ассета шипения в проекте нет, поэтому по умолчанию
-- берём звук пламени самого мангала и ускоряем его — ускоренный треск на слух
-- читается как шипение на решётке. Если положить в модель Sound с именем
-- COOK_SOUND_NAME или прописать сюда свой ассет — возьмётся он.
local COOK_SOUND_ID    = ""          -- ← свой ассет шипения, если появится
local COOK_SOUND_NAME  = "CookSound"
local COOK_SOUND_SPEED = 1.7         -- во сколько раз ускоряем треск пламени
local COOK_SOUND_VOL   = 0.45

-- Невидимый блок над решёткой, по которому курсор попадает в мангал (см.
-- setupGrill). Без него луч проходит между прутьями решётки.
local HITBOX_NAME   = "GrillHitbox"
local HITBOX_HEIGHT = 3.5     -- высота: накрывает и решётку, и лежащую на ней еду
local HITBOX_PAD    = 1.05    -- чуть шире решётки, чтобы край не «проваливался»

local GRATE_SLOTS     = 2     -- сколько единиц еды влезает на решётку
local COOK_TIME       = 12    -- сек до готовности одной штуки
local MEAT_COOK_MULT  = 2     -- мясо жарится вдвое дольше рыбы
local VEG_COOK_MULT   = 1.5   -- овощи между рыбой и мясом
local COOK_POLL       = 0.5   -- шаг проверки готовности
local CLICK_RANGE     = 14    -- дистанция клика по мангалу

-- Пламя при 1 бревне; каждое следующее даёт +GROWTH_PER_LOG к масштабу.
local GROWTH_PER_LOG   = 0.35
-- ⚠️ ЗАПАСНОЙ ПУТЬ для мангалов, у которых внутри модели ЕЩЁ ЕСТЬ авторские
-- Fire/Smoke. В текущей модели их вырезали (стакались с новым эффектом), так что
-- эти ветки просто не находят объектов и молчат. LEGACY_ в имени — чтобы не
-- перекрывать LIGHT_COLOR нового эффекта выше.
local FIRE_SIZE_BASE   = 5
local FIRE_HEAT_BASE   = 9
local LIGHT_BRIGHT_BASE = 1.2
local LIGHT_RANGE_BASE  = 10
local LEGACY_LIGHT_COLOR = Color3.fromRGB(255, 170, 40)

-- Ключи сырой еды в инвентаре: "<Тип>_Fish" и "Meat" (как в FoodSystem).
local RAW_VEG = { Potato = true, Beet = true }
local function isRawFood(name)
	if type(name) ~= "string" then return false end
	if name == "Meat" or name == "Chicken_drumstick" then return true end
	if RAW_VEG[name] then return true end
	return #name > 5 and name:sub(-5) == "_Fish"
end

-- Имена 3D-шаблонов для ключей инвентаря (как в DropItem).
local FOOD_TEMPLATES = {
	Blue_Fish      = "Blue Fish",
	Carp_Fish      = "Carp Fish",
	Foil_Fish      = "Foil Fish",
	Jelly_Fish     = "Jelly Fish",
	Legendary_Fish = "Legendary Fish",
	Seabass_Fish   = "Seabass Fish",
	Tilapia_Fish   = "Tilapia Fish",
	Meat           = "Meat",
	Chicken_drumstick = "Chicken_drumstick",
	-- Овощи авторски названы с префиксом Raft_, а ключ ресурса — без него.
	-- Держать равным FOOD_MODEL_NAMES в FoodSystem.
	Potato         = "Raft_potato",
	Beet           = "Raft_beet",
}

local states = {}  -- [model] = state

-- ─── Поиск шаблона еды (top-level, затем рекурсивно, затем ServerStorage) ──
local function findTemplate(name)
	if type(name) ~= "string" or name == "" then return nil end
	local t = rs:FindFirstChild(name)
	if not t then
		local lower = name:lower()
		for _, d in ipairs(rs:GetDescendants()) do
			if d.Name:lower() == lower and (d:IsA("Model") or d:IsA("BasePart")) then
				t = d
				break
			end
		end
	end
	if not t then
		local folder = ServerStorage:FindFirstChild("Resourses")
		if folder then t = folder:FindFirstChild(name, true) end
	end
	return t
end

-- ─── Визуал пламени ───────────────────────────────────────────────
local function applyVisuals(state)
	local logs = state.logsAdded
	local lit = logs >= 1
	local scale = lit and (1 + GROWTH_PER_LOG * (logs - 1)) or 0

	if state.fire then
		state.fire.Enabled = lit
		if lit then
			state.fire.Size = FIRE_SIZE_BASE * scale
			state.fire.Heat = FIRE_HEAT_BASE * scale
		end
	end
	if state.light then
		state.light.Enabled = lit
		state.light.Color = LEGACY_LIGHT_COLOR
		if lit then
			state.light.Brightness = LIGHT_BRIGHT_BASE * scale
			state.light.Range = LIGHT_RANGE_BASE * scale
		end
	end
	if state.smoke then
		state.smoke.Enabled = lit
	end
	-- Угли бочки: холодные / раскалённые (авторские текстуры варианта)
	if state.coals and state.variant then
		local want = lit and state.variant.coalsHot or state.variant.coalsCold
		if want and state.coals.TextureID ~= want then
			state.coals.TextureID = want
		end
	end
	-- Собственный эффект мангала: флипбук-пламя, дым, искры, угли и живой свет.
	-- Авторские Fire/Smoke выше остались как запасной вариант — если модель уже
	-- несёт их в себе, они просто работают параллельно и ничего не ломают.
	FX.setLit(state.fx, lit, scale)

	-- ГОРИТ ЛИ МАНГАЛ — ОТДЕЛЬНЫМ АТРИБУТОМ.
	-- Клиент раньше узнавал это, ища внутри модели включённый Fire. Своих
	-- Fire/Smoke в модели больше нет (их вырезали, они стакались с новым
	-- эффектом), а новый огонь собран на ParticleEmitter — и клиент навсегда
	-- считал мангал холодным: писал «Разожги огонь» над горящим костром и не
	-- давал класть еду. Атрибут не зависит от того, чем именно нарисован огонь.
	state.model:SetAttribute("Lit", lit)
	if state.sound then
		if lit and not state.sound.IsPlaying then
			state.sound.Looped = true
			state.sound:Play()
		elseif not lit and state.sound.IsPlaying then
			state.sound:Stop()
		end
	end
	if state.prompt then
		-- Мангал набит — подсказку просто ПРЯЧЕМ, а не показываем «Полный».
		-- Статус, на который нельзя нажать, только висел над решёткой и мешал
		-- смотреть на еду; отсутствие подсказки само по себе значит «больше не
		-- влезет».
		state.prompt.ActionText = "Подбросить бревно"
		local want = logs < MAX_LOGS
		state.prompt.Enabled = want
		-- ЖЕЛАНИЕ СЕРВЕРА ОТДЕЛЬНЫМ АТРИБУТОМ.
		-- Клиент гасит подсказку у себя, когда у игрока нет брёвен, и ему надо
		-- знать, можно ли её вернуть. Без этого клиентское Enabled = false
		-- залипало навсегда: сервер переписывает Enabled только при СМЕНЕ числа
		-- брёвен, а игрок принёс дрова, ничего в мангале не поменяв.
		state.prompt:SetAttribute("WantEnabled", want)
	end
end

-- ─── Таймер горения ───────────────────────────────────────────────
local function ensureBurnLoop(state)
	if state.burning then return end
	state.burning = true
	task.spawn(function()
		while state.remaining > 0 and state.model.Parent do
			task.wait(TICK)
			state.remaining = state.remaining - TICK
			-- Брёвна догорают по одному: пламя видимо слабеет к концу.
			local perLog = state.remaining / math.max(1, LOG_BASE_TIME)
			local shouldHave = math.clamp(math.ceil(perLog), 0, state.logsAdded)
			if shouldHave ~= state.logsAdded then
				state.logsAdded = shouldHave
				applyVisuals(state)
			end
		end
		state.remaining = 0
		state.logsAdded = 0
		state.burning = false
		applyVisuals(state)
		print(LOG_TAG .. " прогорел: " .. state.model:GetFullName())
	end)
end

local function isLit(state)
	return state.logsAdded >= 1 and state.remaining > 0
end

local function addLog(state, player)
	if state.logsAdded >= MAX_LOGS then
		if _G.NotifyPlayer then
			_G.NotifyPlayer(player, { type = "info", icon = "🔥", title = "Полный мангал",
				body = "Больше дров не влезет" })
		end
		return
	end
	local now = os.clock()
	if now - (state.lastAddAt or 0) < ADD_COOLDOWN then return end

	-- ⚠️ ОТКАЗ ГОВОРИТ О СЕБЕ ВСЛУХ.
	-- Раньше про отсутствие дров узнавал только серверный лог: игрок жал E,
	-- подсказка на месте, и ничего не происходило.
	local inv = _G.GetInventory and _G.GetInventory(player) or {}
	local before = tonumber(inv.Log) or 0
	if before < 1 then
		print(("%s %s: брёвен нет — подбрасывать нечего"):format(LOG_TAG, player.Name))
		if _G.NotifyPlayer then
			_G.NotifyPlayer(player, { type = "warn", icon = "log", title = "Нет брёвен",
				body = "Чтобы разжечь мангал, нужно бревно" })
		end
		return
	end
	state.lastAddAt = now

	if _G.RemoveResourceFromInventory then
		_G.RemoveResourceFromInventory(player, "Log", 1)
	else
		inv.Log = (inv.Log or 0) - 1
	end
	if _G.SendInventory then _G.SendInventory(player) end
	-- Списание проверяем ЯВНО: если RemoveResourceFromInventory промолчит, дрова
	-- станут бесконечными, и заметить это по одному лишь горящему огню нельзя.
	local after = tonumber((_G.GetInventory and _G.GetInventory(player) or {}).Log) or 0
	if after >= before then
		warn(("%s бревно НЕ списалось у %s (было %d, стало %d)")
			:format(LOG_TAG, player.Name, before, after))
	end

	-- Свежий огонь горит базовое время; добавка в догорающий даёт до +50%,
	-- чтобы бревно «в последний момент» не пропадало впустую.
	local contribution = LOG_BASE_TIME
	if state.remaining > 0 then
		contribution = LOG_BASE_TIME
			+ MAX_BONUS * math.clamp((BONUS_THRESHOLD - state.remaining) / BONUS_THRESHOLD, 0, 1)
	end
	state.remaining = state.remaining + contribution
	state.logsAdded = state.logsAdded + 1
	applyVisuals(state)
	ensureBurnLoop(state)
end

local function slotCount(state)
	return (state.variant and state.variant.slots) or GRATE_SLOTS
end

-- ─── Решётка: места под еду ───────────────────────────────────────
-- Куски раскладываются вдоль длинной горизонтальной оси решётки, поровну на всю
-- её длину: у обычного мангала мест два, у бочки четыре — формула общая.
local function slotCF(state, index)
	local grate = state.grate
	local cf, size = grate.CFrame, grate.Size
	local alongX = size.X >= size.Z
	local span = alongX and size.X or size.Z
	local n = slotCount(state)
	-- центры n равных отрезков в пределах 88% длины решётки
	local t = (n > 1) and ((index - 0.5) / n - 0.5) or 0
	local off = t * span * 0.88
	local local_ = alongX and Vector3.new(off, size.Y * 0.5, 0)
		or Vector3.new(0, size.Y * 0.5, off)
	return cf * CFrame.new(local_)
end

local function freeSlot(state)
	for i = 1, slotCount(state) do
		local it = state.slots[i]
		if not it or not it.model.Parent then
			state.slots[i] = nil
			return i
		end
	end
	return nil
end

-- ПОЛОЖИТЬ КУСОК НА РЕШЁТКУ. Откуда он взялся — из инвентаря или из рук —
-- этой функции безразлично: она только строит модель и приваривает её к
-- решётке. Списание ресурса делает вызывающий, ДО вызова.
-- Возвращает номер занятого места или nil.
local function slotFree(state, i)
	if i < 1 or i > slotCount(state) then return false end
	local it = state.slots[i]
	if it and not it.model.Parent then state.slots[i] = nil return true end
	return it == nil
end

-- wantSlot — место, выбранное игроком курсором. Если оно занято или не задано,
-- берём первое свободное: молча отказывать нельзя, игрок уже кликнул.
local function placeFoodOnGrate(state, pick, wantSlot)
	local slot = (wantSlot and slotFree(state, wantSlot)) and wantSlot or freeSlot(state)
	if not slot then return nil end

	local template = findTemplate(FOOD_TEMPLATES[pick] or pick)
	if not template then
		warn(LOG_TAG .. " нет 3D-шаблона для " .. pick .. " — на решётку положить нечего")
		return nil
	end

	local food = template:Clone()
	food.Name = "GrillFood"
	food:SetAttribute("ResourceType", pick)
	food:SetAttribute("ResourceAmount", 1)
	-- Авторские скрипты рыбы (трепыхание) на решётке не нужны, а тег
	-- DroppedItem снимаем — иначе кусок подберут как лежащий на палубе
	-- предмет ИЛИ его пожарит цикл готовки костра.
	for _, d in food:GetDescendants() do
		if d:IsA("BaseScript") then d:Destroy() end
	end
	if CollectionService:HasTag(food, "DroppedItem") then
		CollectionService:RemoveTag(food, "DroppedItem")
	end

	-- ПРИНУДИТЕЛЬНО СЫРОЙ ВИД. Шаблоны рыб авторские, и у части из них по
	-- умолчанию видна ЖАРЕНАЯ декаль: кусок попадал на решётку уже
	-- подрумяненным, и отличить готовое от сырого было нельзя. Правила смены
	-- текстур берём у FoodSystem — там же, где обратная операция.
	if _G.SetFoodVisualCooked then
		pcall(_G.SetFoodVisualCooked, food, false)
	end
	food:SetAttribute("Cooked", nil)

	-- ── РАЗМЕР И ПОЗА КУСКА НА РЕШЁТКЕ ──
	-- Модели еды авторские и приезжают «как есть»: свёкла стоит вертикально и
	-- размером с полрешётки. Правила общие, чтобы не подкручивать каждый овощ:
	--   1) выше, чем шире → кладём НАБОК (еда на решётке лежит, а не стоит);
	--   2) не влезает в своё место → ужимаем до размера места.
	local slots = slotCount(state)
	local grate = state.grate
	local slotWidth = GrillFit.slotWidth(grate.Size, slots)

	if food:IsA("Model") and not food.PrimaryPart then
		local bb = food:GetBoundingBox()
		food.WorldPivot = CFrame.new(bb.Position)
	end

	local function sizeOf()
		if food:IsA("Model") then
			local _, s = food:GetBoundingBox()
			return s
		end
		return food.Size
	end

	local s0 = sizeOf()
	local lay = GrillFit.laysDown(s0)
	-- ⚠️ РАСЧЁТ ОБЩИЙ С ПРИЗРАКОМ (GrillFit).
	-- Здесь стояла своя формула, бравшая максимум из всех трёх сторон: длинный
	-- кусок ужимался так, будто должен лечь в слот целиком поперёк, и на решётку
	-- попадала крошка. Теперь меряется только та сторона, что реально встаёт
	-- поперёк слота, и та же цифра показывается на предпросмотре.
	local k = GrillFit.scaleFor(s0, slotWidth)
	if k < 1 then
		if food:IsA("Model") then
			-- ⚠️ ScaleTo ЗАДАЁТ МАСШТАБ АБСОЛЮТНО, от авторского размера модели, а
			-- не умножает текущий. У шаблона свёклы масштаб уже был уменьшен, и
			-- ScaleTo(k) раздувал её до неба — в прямом смысле: подъём считается
			-- от габарита, и гигантский кусок улетал вверх. Множим сами.
			pcall(function()
				local cur = food:GetScale()
				food:ScaleTo(cur * k)
			end)
		else
			food.Size = food.Size * k
		end
	end

	-- Ставим на место, приподняв на половину итоговой высоты.
	-- ⚠️ ПОРЯДОК: сперва подъём в системе РЕШЁТКИ, потом поворот на месте. Если
	-- умножать наоборот, смещение уходит по повёрнутой оси — кусок улетает вбок.
	-- После поворота на 90° вокруг X вертикальным становится локальный Z, поэтому
	-- и высоту берём по нему.
	local s1 = sizeOf()
	local lift = (lay and s1.Z or s1.Y) * 0.5
	local target = slotCF(state, slot) * CFrame.new(0, lift, 0)
	if lay then target = target * CFrame.Angles(math.rad(-90), 0, 0) end
	if food:IsA("Model") then
		food:PivotTo(target)
	elseif food:IsA("BasePart") then
		food.CFrame = target
	end
	food.Parent = state.model

	-- БЕЗ МАССЫ И БЕЗ КОЛЛИЗИЙ: масса скачком меняет AssemblyMass, а её
	-- BoatMovement компенсирует силой раз в кадр — плот от этого проседает.
	-- Держит еду сварка с решёткой, а не трение.
	local parts = {}
	if food:IsA("BasePart") then parts[1] = food end
	for _, d in food:GetDescendants() do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	for _, p in ipairs(parts) do
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		local w = Instance.new("WeldConstraint")
		w.Name = "GrillFoodWeld"
		w.Part0, w.Part1 = state.grate, p
		w.Parent = p
	end

	state.slots[slot] = { model = food, cooked = 0, resType = pick }
	print(("%s положено на решётку: %s (место %d)"):format(LOG_TAG, pick, slot))
	return slot
end


-- Забрать всё готовое с решётки. Второе возвращаемое значение — ключ последнего
-- забранного куска: клиент по нему сразу берёт еду в руки, чтобы её можно было
-- съесть, не открывая инвентарь.
-- onlySlot — забрать только то место, на которое игрок навёл курсор. Без него
-- (клик по мангалу с пустыми руками) забираем всё готовое разом, как раньше.
local function takeCooked(state, player, onlySlot)
	local taken, lastKey = 0, nil
	for i = 1, slotCount(state) do
		local it = state.slots[i]
		if onlySlot and i ~= onlySlot then
			it = nil
		end
		if it and it.model.Parent and it.model:GetAttribute("Cooked") then
			local resType = it.model:GetAttribute("ResourceType") or (it.resType .. "_Cooked")
			local pos
			if it.model:IsA("Model") then
				local ok, cf = pcall(function() return it.model:GetPivot() end)
				pos = ok and cf.Position or nil
			elseif it.model:IsA("BasePart") then
				pos = it.model.Position
			end
			if _G.AddResourceToInventory then
				_G.AddResourceToInventory(player, resType, 1, pos)
			end
			-- ⚠️ СОБЫТИЕ ГОТОВКИ ШЛЁМ ОТСЮДА, А НЕ ИЗ ЦИКЛА ГОТОВНОСТИ.
			-- Кусок дожаривается в опросе выше, но там нет ИГРОКА: в слоте лежат
			-- только модель, счётчик и вид ресурса. Кому засчитывать — известно
			-- ровно здесь, когда его снимают с решётки. Имя очищаем от «_Cooked»,
			-- чтобы квест писался про продукт («cooked:Meat»), а не про его
			-- жареную разновидность.
			local base = resType:gsub("_Cooked$", "")
			if typeof(_G.OnQuestEvent) == "function" then
				pcall(_G.OnQuestEvent, player, "cooked:" .. base, 1)
			end
			it.model:Destroy()
			state.slots[i] = nil
			taken = taken + 1
			lastKey = resType
		end
	end
	if taken > 0 then
		print(("%s забрано готового: %d"):format(LOG_TAG, taken))
	end
	return taken, lastKey
end

-- ─── Готовка ──────────────────────────────────────────────────────
-- cookMult варианта: у бочки он меньше единицы — она жарит быстрее.
local function cookNeeded(resType, state)
	local base = COOK_TIME * ((state and state.variant and state.variant.cookMult) or 1)
	if resType == "Meat" or resType == "Chicken_drumstick" then base = base * MEAT_COOK_MULT
	elseif RAW_VEG[resType] then base = base * VEG_COOK_MULT end
	return base
end

task.spawn(function()
	while true do
		task.wait(COOK_POLL)
		for model, state in pairs(states) do
			if not model.Parent then
				states[model] = nil
			else
				local cooking = 0
				if isLit(state) then
					for i = 1, slotCount(state) do
						local it = state.slots[i]
						if it and it.model.Parent and not it.model:GetAttribute("Cooked") then
							cooking = cooking + 1
							it.cooked = it.cooked + COOK_POLL
							if it.cooked >= cookNeeded(it.resType, state) then
								-- Смену raw/cooked текстур делает костёр: правила
								-- прожарки живут в одном месте (_G.CookFoodModel).
								if _G.CookFoodModel then
									pcall(_G.CookFoodModel, it.model)
								else
									it.model:SetAttribute("Cooked", true)
									local rt = it.model:GetAttribute("ResourceType")
									if rt == "Chicken_drumstick" then
										it.model:SetAttribute("ResourceType", "Meat_Cooked")
									elseif type(rt) == "string" and rt:sub(-7) ~= "_Cooked" then
										it.model:SetAttribute("ResourceType", rt .. "_Cooked")
									end
								end
								print(("%s готово: %s"):format(LOG_TAG, tostring(it.resType)))
							end
						elseif it and not it.model.Parent then
							state.slots[i] = nil
						end
					end
				end

				-- Шипение — ровно пока на решётке есть НЕДОжаренный кусок и горит
				-- огонь. Готовое перестаёт шипеть само, даже если игрок его не забрал.
				local cs = state.cookSound
				if cs and cs.SoundId ~= "" then
					if cooking > 0 and not cs.IsPlaying then
						cs:Play()
					elseif cooking == 0 and cs.IsPlaying then
						cs:Stop()
					end
				end
			end
		end
	end
end)

-- ─── Настройка поставленного мангала ──────────────────────────────
local function setupGrill(model)
	if states[model] then return end

	-- Мангал В РУКАХ — это ещё не поставленный мангал. Модель внутри тула зовётся
	-- так же, и сканер по имени принимал её за установленную: сыпал warn'ом «нет
	-- решётки» каждый раз, когда игрок доставал предмет.
	if model:FindFirstAncestorWhichIsA("Tool")
		or (model.Parent and Players:GetPlayerFromCharacter(model.Parent)) then
		return
	end

	local variant = variantOf(model)
	local bowl = model:FindFirstChild(variant.bowl, true) or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	local grate = model:FindFirstChild(variant.grate, true)
	if not grate or not grate:IsA("BasePart") then
		warn(LOG_TAG .. " нет решётки '" .. variant.grate .. "' в " .. model:GetFullName()
			.. " — еду ставить некуда")
		return
	end

	local fire, light, smoke, sound
	for _, d in model:GetDescendants() do
		if not fire and d:IsA("Fire") then fire = d
		elseif not light and d:IsA("Light") then light = d
		elseif not smoke and d:IsA("Smoke") then smoke = d
		-- CookSound пропускаем: иначе при повторной настройке уже стоящего
		-- мангала звук жарки приняли бы за звук пламени и зациклили сами на себя.
		elseif not sound and d:IsA("Sound") and d.Name ~= COOK_SOUND_NAME then sound = d end
	end

	-- Света в шаблоне нет — добавляем в деталь пламени, иначе горящий
	-- мангал ночью не подсвечивает палубу.
	if not light then
		local host = (fire and fire.Parent and fire.Parent:IsA("BasePart") and fire.Parent) or bowl
		if host then
			light = Instance.new("PointLight")
			light.Name = "GrillLight"
			light.Color = LIGHT_COLOR
			light.Enabled = false
			light.Parent = host
		end
	end

	local state = {
		model = model, bowl = bowl, grate = grate, variant = variant,
		fire = fire, light = light, smoke = smoke, sound = sound,
		logsAdded = 0, remaining = 0, burning = false, lastAddAt = 0,
		slots = {},
	}
	states[model] = state

	-- Угли бочки: холодная текстура / раскалённая, переключает applyVisuals.
	if variant.coals then
		local coals = model:FindFirstChild(variant.coals, true)
		if coals and coals:IsA("MeshPart") then state.coals = coals end
	end

	-- Огонь строим на ЧАШЕ (у бочки — на углях, см. fireHost варианта): все
	-- высоты и размеры эффекта — доли габарита этой детали.
	local fireHost = bowl
	if variant.fireHost then
		local h = model:FindFirstChild(variant.fireHost, true)
		if h and h:IsA("BasePart") then fireHost = h end
	end
	local okFX, fxOrErr = pcall(FX.build, fireHost,
		{ div = variant.fireDiv, minZone = variant.fireMinZone })
	if okFX then
		state.fx = fxOrErr
	else
		warn(LOG_TAG .. " огонь не построился: " .. tostring(fxOrErr))
	end
	if not state.fx then
		warn(LOG_TAG .. " не нашлась деталь чаши — огня не будет: " .. model:GetFullName())
	end

	-- Звук жарки создаём ЗАРАНЕЕ, а не в момент готовки: Instance.new("Sound")
	-- по месту тянет за собой репликацию и загрузку ассета, и шипение начиналось
	-- бы с заметным опозданием (та же грабля была со звуками пиявки).
	local cookHost = grate
	local cs = cookHost:FindFirstChild(COOK_SOUND_NAME)
	if not (cs and cs:IsA("Sound")) then
		cs = Instance.new("Sound")
		cs.Name = COOK_SOUND_NAME
		cs.Parent = cookHost
	end
	cs.Looped = true
	cs.Volume = COOK_SOUND_VOL
	if COOK_SOUND_ID ~= "" then
		cs.SoundId = COOK_SOUND_ID
	elseif sound and sound.SoundId ~= "" then
		cs.SoundId = sound.SoundId
		cs.PlaybackSpeed = COOK_SOUND_SPEED
	end
	state.cookSound = cs

	-- ХИТБОКС НАД РЕШЁТКОЙ.
	-- Решётка — это редкая сетка из прутьев, и луч курсора проходит СКВОЗЬ неё
	-- между ними: игроку приходилось выцеливать конкретный прутик, чтобы
	-- положить или забрать еду. Кладём поверх невидимый блок на всю площадь
	-- решётки — по нему луч попадает всегда. Невидимый, без коллизии, без массы:
	-- ни ходьбу, ни физику плота он не трогает, а курсор видит.
	local hb = grate:FindFirstChild(HITBOX_NAME)
	if not (hb and hb:IsA("BasePart")) then
		hb = Instance.new("Part")
		hb.Name = HITBOX_NAME
		hb.Parent = grate
	end
	hb.Size = Vector3.new(
		grate.Size.X * HITBOX_PAD,
		HITBOX_HEIGHT,
		grate.Size.Z * HITBOX_PAD)
	hb.CFrame = grate.CFrame * CFrame.new(0, HITBOX_HEIGHT * 0.5, 0)
	hb.Transparency = 1
	hb.CanCollide = false
	hb.CanTouch = false
	hb.CanQuery = true      -- ради него всё и затевалось: луч курсора его видит
	hb.Massless = true
	hb.Anchored = true
	local hbWeld = hb:FindFirstChildOfClass("WeldConstraint")
	if not hbWeld then
		hbWeld = Instance.new("WeldConstraint")
		hbWeld.Parent = hb
	end
	hbWeld.Part0, hbWeld.Part1 = grate, hb
	hb.Anchored = false
	state.hitbox = hb

	-- E — топливо.
	local anchor = bowl or grate
	local prompt = anchor:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = anchor
	end
	prompt.ActionText            = "Подбросить бревно"
	prompt.ObjectText            = "Костровая жаровня"
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.HoldDuration          = 0
	prompt.MaxActivationDistance = PROMPT_RANGE
	prompt.RequiresLineOfSight   = false
	prompt.Enabled               = true
	prompt.Triggered:Connect(function(player) addLog(state, player) end)
	state.prompt = prompt

	-- КЛИК — еда. Вешаем на чашу И на решётку, чтобы работало попадание
	-- по любой части мангала. ClickDetector, а не подсказка: по просьбе
	-- «игрок просто нажимает на гриль».
	local function hookClick(part)
		if not (part and part:IsA("BasePart")) then return end
		local cd = part:FindFirstChildOfClass("ClickDetector")
		if not cd then
			cd = Instance.new("ClickDetector")
			cd.Parent = part
		end
		cd.MaxActivationDistance = CLICK_RANGE
		cd.MouseClick:Connect(function(player)
			-- сначала пробуем забрать готовое, иначе кладём новое
			-- Клик ПУСТЫМИ РУКАМИ только забирает готовое.
			-- Раньше он ещё и клал на решётку первое попавшееся сырое из
			-- инвентаря — а «первое попавшееся» из хеш-таблицы это буквально
			-- случайный выбор: игрок хотел пожарить мясо, а уезжала рыба.
			-- Что жарить, теперь решает сам игрок — берёт нужное в руки и
			-- кладёт по курсору (grillPutHeld).
			takeCooked(state, player)
		end)
	end
	hookClick(grate)
	hookClick(bowl)

	applyVisuals(state)

	model.AncestryChanged:Connect(function()
		if not model.Parent then
			-- Отписываем мерцание света: без этого Heartbeat-цикл эффекта
			-- пережил бы удалённый мангал.
			FX.destroy(states[model] and states[model].fx)
			states[model] = nil
		end
	end)

	print(("%s готов: %s"):format(LOG_TAG, model:GetFullName()))
end

-- ─── Еда ИЗ РУК: положить на решётку / снять готовое ───────────────
--
-- Отдельный путь от ClickDetector потому, что ClickDetector НЕ срабатывает,
-- пока у игрока экипирован Tool: с мясом в руках по мангалу просто нельзя
-- кликнуть. Здесь клик ловит клиент (GrillFoodPlace.client) своим лучом и
-- присылает сюда модель мангала.
local function grillStateFor(inst)
	if typeof(inst) ~= "Instance" then return nil end
	local m = inst
	while m and m ~= workspace do
		if states[m] then return states[m] end
		m = m.Parent
	end
	return nil
end

local function playerNearGrill(player, state)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	return (hrp.Position - state.grate.Position).Magnitude <= CLICK_RANGE
end

-- ── «ИГРОК ЦЕЛИТСЯ В РЕШЁТКУ» ──
--
-- Клик с едой в руках — это Tool.Activated, то есть «съесть». Перехватить его
-- на клиенте нельзя: активация тула идёт мимо пользовательских привязок ввода,
-- и попытка «съесть нажатие» через ContextActionService не работала — еда
-- отправлялась в рот вместо решётки.
--
-- Поэтому запрет живёт на сервере, там же, где и само поедание: клиент, пока
-- курсор на мангале, отмечается здесь, а FoodSystem перед укусом спрашивает
-- _G.IsAimingAtGrill и молча пропускает активацию.
--
-- Отметка ПРОТУХАЕТ (AIM_TTL) и перепроверяется по расстоянию: если клиент
-- перестанет слать обновления или соврёт, игрок не останется без возможности
-- поесть навсегда.
local AIM_TTL = 1.5
local aiming = {}  -- [player] = { grill = Model, at = os.clock() }

_G.IsAimingAtGrill = function(player)
	local a = aiming[player]
	if not a then return false end
	if os.clock() - a.at > AIM_TTL then return false end
	local state = states[a.grill]
	if not state or not state.model.Parent then return false end
	return playerNearGrill(player, state)
end

Players.PlayerRemoving:Connect(function(player) aiming[player] = nil end)

cupActionEvent.OnServerEvent:Connect(function(player, action, target, slotArg)
	local wantSlot = tonumber(slotArg)
	if wantSlot then wantSlot = math.floor(wantSlot) end

	if action == "grillAim" then
		local state = grillStateFor(target)
		if state and playerNearGrill(player, state) then
			aiming[player] = { grill = state.model, at = os.clock() }
		else
			aiming[player] = nil
		end
		return

	elseif action == "grillPutHeld" then
		local state = grillStateFor(target)
		if not state then
			print(("%s grillPutHeld: мангал не опознан (%s)"):format(LOG_TAG, tostring(target)))
			return
		end
		if not playerNearGrill(player, state) then
			print(LOG_TAG .. " grillPutHeld: далеко от мангала")
			return
		end
		if not isLit(state) then
			print(LOG_TAG .. " grillPutHeld: мангал не горит")
			return
		end

		local char = player.Character
		local tool = char and char:FindFirstChildWhichIsA("Tool")
		local key = tool and tool:GetAttribute("FoodResource")
		if not isRawFood(key) then
			print(("%s grillPutHeld: в руках не сырая еда (%s)"):format(LOG_TAG, tostring(key)))
			return
		end
		-- Съесть успели раньше, чем положить: клик — это ещё и Tool.Activated,
		-- и кто из них дойдёт до сервера первым, не гарантировано. Флаг ставит
		-- тот, кто выиграл гонку; проигравший должен отступить, иначе кусок
		-- либо задвоится, либо исчезнет.
		if tool:GetAttribute("Consumed") then return end
		if not placeFoodOnGrate(state, key, wantSlot) then return end

		-- «Consumed» гасит возврат в стак: FoodSystem.refundFood при снятии
		-- нескушанного тула вернул бы кусок в инвентарь, и еда задвоилась бы —
		-- одна на решётке, одна в рюкзаке.
		tool:SetAttribute("Consumed", true)
		tool:Destroy()
		if _G.SendInventory then _G.SendInventory(player) end
		return

	elseif action == "grillTake" then
		local state = grillStateFor(target)
		if not state or not playerNearGrill(player, state) then return end
		local taken, key = takeCooked(state, player, wantSlot)
		if taken > 0 and key then
			-- Клиент сам возьмёт кусок в руки: у FoodSystem экипировка идёт
			-- через свой RemoteEvent, и дублировать её логику здесь незачем.
			cupActionEvent:FireClient(player, "grillTook", key)
		end
		return
	end

	if action ~= "placeGrill" then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	-- ставим ТОТ вариант, что в руках: обычный мангал или бочку
	if not tool or not VARIANTS[tool.Name] then return end
	local modelName = tool.Name

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end
	if typeof(target) ~= "CFrame" then return end

	local template = AssetFind.find(modelName)
	if not template then
		warn(LOG_TAG .. " нет шаблона ReplicatedStorage." .. modelName)
		return
	end

	local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

	local model = template:Clone()
	model.Name = modelName
	for _, d in model:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
	end
	if model:IsA("Model") and not model.PrimaryPart then
		local bb = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(bb.Position)
	end
	model:PivotTo(worldCF)
	if PlaceCheck.refuseIfBlocked(model, raft, player) then return end   -- в предмет ставить нельзя
	model.Parent = raft

	-- Тот же приём, что у костра и печи: варим при выключенной физике,
	-- потом возвращаем скорость плоту, чтобы он не терял ход.
	local primary = raft.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then p.Anchored = true end
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = p
			weld.Part1 = primary
			weld.Parent = p
		end
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then p.Anchored = false end
	end
	primary.AssemblyLinearVelocity  = linVel
	primary.AssemblyAngularVelocity = angVel
	-- игрока на палубе сервером не удержать — просим его клиент (RaftShake)
	RaftShake.notify()

	setupGrill(model)
	tool:Destroy()
end)

-- ─── Подхватить мангалы, уже стоящие в мире ───────────────────────
for _, child in workspace:GetDescendants() do
	if child:IsA("Model") and VARIANTS[child.Name] then
		setupGrill(child)
	end
end
workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") and VARIANTS[inst.Name] then
		task.defer(function()
			if inst.Parent then setupGrill(inst) end
		end)
	end
end)

print(LOG_TAG .. " loaded")

-- СЕЙВ: что лежит на решётке и насколько прожарено. Мангал сам восстанавливается
-- как постройка плота, еда на нём — отсюда.
_G.GrillExport = function()
	local raft = workspace:FindFirstChild("Raft")
	local pp = raft and raft.PrimaryPart
	if not pp then return {} end
	local out = {}
	for model, state in pairs(states) do
		if model.Parent then
			local items = {}
			for i = 1, slotCount(state) do
				local it = state.slots[i]
				if it and it.model and it.model.Parent then
					table.insert(items, { slot = i, pick = it.resType, cooked = it.cooked })
				end
			end
			if #items > 0 then
				local rel = pp.CFrame:PointToObjectSpace(model:GetPivot().Position)
				table.insert(out, { x = rel.X, y = rel.Y, z = rel.Z, items = items })
			end
		end
	end
	return out
end
_G.GrillRestore = function(rec)
	local raft = workspace:FindFirstChild("Raft")
	local pp = raft and raft.PrimaryPart
	if not (pp and type(rec) == "table") then return 0 end
	local want = pp.CFrame:PointToWorldSpace(Vector3.new(rec.x or 0, rec.y or 0, rec.z or 0))
	local best, bestD
	for model, state in pairs(states) do
		if model.Parent then
			local d = (model:GetPivot().Position - want).Magnitude
			if d < 6 and (not bestD or d < bestD) then best, bestD = state, d end
		end
	end
	if not best then return 0 end
	local n = 0
	for _, it in ipairs(rec.items or {}) do
		local slot = placeFoodOnGrate(best, it.pick, it.slot)
		if slot and best.slots[slot] then
			best.slots[slot].cooked = tonumber(it.cooked) or 0
			n += 1
		end
	end
	return n
end
