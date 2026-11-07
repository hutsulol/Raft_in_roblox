--[[
	ФЕРМА (один фермер, четыре овцы, шерсть) — общие числа для сервера и клиента.

	Модель — Farm_Island_Build: импорт Greenroof_Farm.fbx (test/GreenroofFarm).
	В модели НЕТ маркеров wp_*: все рабочие точки считаются от геометрии самой
	модели. Числа ниже — МЕТРЫ Blender'а, сняты с Greenroof_Farm.blend скриптом
	(farm_bounds.json), оси блендеровские: x вправо, y вглубь (к хлеву), z вверх.
	Перевод в Roblox: (x, y, z) → (x, z, −y), масштаб импорта берём у самой
	модели (FarmDefs.frame), поэтому числа переживают любой Scale при импорте.

	⚠️ СТАВИТСЯ НА СУШУ ОСТРОВА ТЕМИ ЖЕ ПРАВИЛАМИ, ЧТО ВЫШКА И ДОМ (_G.OilRigSpotOK),
	но с более строгим допуском по уклону: ограда — жёсткий меш, и на уклоне
	в 6 студов посты с одной стороны висели бы в воздухе, с другой — тонули.
]]

local Farm = {}

-- Новая ферма (test/GreenroofFarm_SheepSpawns): бочка и ящик шерсти уже внутри,
-- вместо статичных овец — маркеры Spawn_Sheep_01…04. В Studio модель названа
-- Farm_Build_Island_Sheep, в FBX корень — Farm_Island_Build: ищем оба имени.
Farm.MODEL     = "Farm_Build_Island_Sheep"
Farm.MODEL_ALT = "Farm_Island_Build"
Farm.SPAWN_PREFIX = "Spawn_Sheep_"     -- маркеры спавна овец (кубики: прячем)
Farm.FACING_PREFIX = "Facing_Sheep_"
Farm.NAME_RU = "Ферма"
Farm.WORKER  = "OilMan"         -- шаблон жителя (тот же, что у вышки: OilMan / OilMan_1 / OilMan_2)
Farm.SHEEP   = "Sheep"          -- риг овцы: 7 MeshPart (Torso, Wool, Head, LegFL…), см. test/GreenroofFarm/export_sheep.py
Farm.STATIC_SHEEP_PREFIX = "Sheep_"   -- статичные овцы старой модели: прячем, когда есть риг
-- Запасные точки спавна (spawn_points.json, метры Blender, поворот вокруг z):
-- берутся, если маркеров в модели нет
Farm.SHEEP_SPAWNS = {
	{ -1.0045, -0.7482, -0.4 }, { 0.8258, -1.2551, 0.75 },
	{ 1.6342, -2.2451, -0.75 }, { -1.5585, -2.2109, 2.5 },
}
-- ⚠️ БОЧКА ВОДЫ И ЯЩИК ШЕРСТИ — НЕОБЯЗАТЕЛЬНЫЕ МОДЕЛИ. В Farm_Island_Build их
-- нет; положи в ReplicatedStorage Model/MeshPart с такими именами — сервер
-- поставит их на точки water_barrel / wool_crate (низом на грунт). Нет — стоят
-- простые детали-заглушки.
Farm.WATER_BARREL_MODEL = "Farm_WaterBarrel"
Farm.WOOL_CRATE_MODEL   = "Farm_WoolCrate"
-- Комплект Farm_Props_Pack (test/FarmStorageProps/HANDOFF_FARM_PROPS.md): шесть
-- подмоделей. height — авторская высота габарита в МЕТРАХ (из GLB): по ней
-- считается масштаб импорта комплекта, чтобы проп встал в масштаб фермы.
-- primary — какую деталь делать PrimaryPart (к ней варится остальное).
Farm.PROP_MODELS = {
	barrel    = { name = "Farm_WaterBarrel", height = 1.175, primary = "Barrel_Body" },
	crate     = { name = "Farm_WoolCrate",   height = 1.225, primary = "Crate_Frame" },
	hay       = { name = "Farm_HayBundle",   height = 0.31,  primary = "Hay_Bundle_Core" },
	woolCarry = { name = "Farm_Basket_Wool", height = 0.672, primary = "Basket_Full_Body" },
	woolDrop  = { name = "Farm_WoolBundle",  height = 0.415, primary = "Carry_Wool" },
	basket    = { name = "Farm_Basket_Empty", height = 0.672, primary = "Basket_Empty_Body" },
}
-- уровень воды в бочке (метры от её дна, из хендофа): пусто → поверхность скрыта
Farm.WATER_LEVEL = { minY = 0.20, minR = 0.37, maxY = 0.962, maxR = 0.42, thick = 0.025 }
-- ⚠️ РАЗМЕР ПРОПОВ — КАК В STUDIO. Автоподгонка к масштабу фермы по авторской
-- высоте раздувала модели, потому что владелец уже выставил им размер руками
-- (в Studio нормальные, в игре огромные). Включать только если комплект
-- импортирован «как есть» и не масштабировался.
Farm.PROP_AUTOSCALE = false
-- пороги видимости трёх связок в ящике (доля от WOOL_CAP)
Farm.CRATE_BUNDLE_AT = { 0.001, 0.34, 0.67 }

-- ⚠️ ЦЕНА ВРЕМЕННАЯ, по аналогии с домом (20) и вышкой (12): ферма больше и
-- даёт доход. Меняется здесь и только здесь — меню молотка и сервер читают отсюда.
Farm.COST      = 30
Farm.COST_TYPE = "Log"

Farm.TILE_PREFIX = "Island_terrain"
-- ⚠️ ФЕРМА СТОИТ ВЫШЕ ТОЧКИ ПРИЦЕЛА, А НЕ ТОНЕТ. Низ габарита модели — это низ
-- плиты грунта, и с посадкой 0.9 ограда уходила в остров по колено (владелец:
-- «слишком низко»). Отрицательная посадка = подъём над точкой прицела; одна
-- ручка на призрак и сервер.
Farm.SINK     = -0.3   -- студов: минус — выше грунта, плюс — глубже
Farm.FLAT_TOL = 3      -- разброс высот под углами (студы); у вышки 6, у ограды нельзя

-- Пассивный доход: пираты владельцу раз в игровой день в 23:00, если фермер назначен
Farm.DAILY_PIRATES = 100
Farm.PAY_HOUR      = 23

-- смена фермера: как у вышки (OilRigDefs.WORK_START/END)
Farm.WORK_START = 6.5
Farm.WORK_END   = 23
Farm.SHEEP_OUT_HOUR = 6.5     -- утром выпускает
Farm.SHEEP_IN_HOUR  = 17.5    -- вечером заводит (ещё светло: ночной час идёт 10 с)

-- ── ЗАПАСЫ И ЁМКОСТИ (ТЗ, раздел 7) ──
Farm.FEEDER_CAP   = 18   -- кормушка, единиц корма
Farm.HAY_PER_TRIP = 6    -- переносит за подход
Farm.TROUGH_CAP   = 16   -- поилка, единиц воды
Farm.BUCKET_CAP   = 8    -- ведро
Farm.WOOL_CAP     = 16   -- склад шерсти
Farm.HAY_STORE_CAP   = 40
Farm.WATER_STORE_CAP = 40
Farm.HAY_START   = 24    -- стартовый запас при постройке
Farm.WATER_START = 24
Farm.BEDDING_HAY = 2     -- расход сена на обновление подстилки

-- пополнение запасов игроком
Farm.HAY_ITEM      = "Leaves"   -- 1 листва → HAY_PER_ITEM сена
Farm.HAY_PER_ITEM  = 3
Farm.WATER_PER_CUP = 4          -- один заряд кружки/бутылки → единиц воды

-- ── ПРОИЗВОДСТВО ──
Farm.WOOL_FULL_SEC   = 12 * 60   -- полное отрастание при хорошем уходе
Farm.WOOL_PER_SHEAR  = 2
Farm.SHEAR_SEC       = 8         -- вся стрижка: enter + 3 × loop + exit
Farm.CALM_SEC        = 4
Farm.CALM_STRESS     = 25
Farm.CLEAN_SEC       = 12
Farm.WOOL_ITEM       = "Wool"

-- пороги (ТЗ, разделы 3, 6, 7)
Farm.REFILL_AT      = 0.25   -- поилка/кормушка ≤ 25% → срочно
Farm.PLAN_AT        = 0.50   -- ≤ 50% → планово
Farm.CLEAN_URGENT   = 30
Farm.CLEAN_PLAN     = 50
Farm.SHEAR_NEED_MIN = 40     -- сытость и вода не ниже
Farm.SHEAR_STRESS_MAX = 30
Farm.CALM_AT        = 45     -- стресс выше → сперва успокоить
Farm.NEED_SEEK      = 45     -- ниже — овца ищет корм/воду
Farm.NEED_STOP      = 20     -- ниже — шерсть не растёт
Farm.RETRY_DELAY    = 30     -- отложить задачу (нет пути / овца не идёт)

-- ── ОВЦЫ ──
-- Потребление ≈ 3 единицы корма и 3 воды на овцу за игровой день (12 мин):
-- один укус/глоток восстанавливает NEED_PER_UNIT очков и тратит EAT_PORTION.
Farm.NEED_DECAY     = 55 / 240        -- очков в секунду: со 100 до 45 за ~4 минуты
Farm.EAT_PORTION    = 0.25            -- единиц из кормушки за укус
Farm.NEED_PER_UNIT  = 55              -- очков сытости за единицу корма
Farm.BITE_SEC       = 2.5
Farm.STRESS_NEAR    = 2.5 * 3         -- игрок ближе (студы) — стресс растёт
Farm.STRESS_UP      = 8               -- в секунду рядом с игроком
Farm.STRESS_DOWN    = 1.5             -- в секунду в покое
Farm.CLEAN_DECAY    = 50 / 720        -- чистота: одно обновление в день
Farm.SHEEP_WALK     = 2.2             -- студов в секунду (под темп клипа)
Farm.SHEEP_FOLLOW   = 3.0
Farm.FOLLOW_GAP     = 4.5             -- держится за фермером на таком расстоянии
Farm.LOST_GAP       = 14              -- отстала — фермер ждёт и зовёт снова

-- Внешний вид шерсти: деталь Wool масштабируется/прячется
-- ⚠️ ШЕРСТЬ НЕ МАСШТАБИРУЕМ. У авторского рига шерсть — десяток деталей
-- (BodyWool, HeadWool, TailWool…), и уменьшение каждой вокруг своего центра
-- давало «шерсть меньше, чем на самом деле» с щелями. Две формы: острижена
-- (шерсть скрыта) и с шерстью (как в модели). Овца рождается с шерстью.
Farm.WOOL_LOOK = {
	short = { scale = 1.0, visible = false },  -- только что остригли
	grow  = { scale = 1.0, visible = true  },  -- отрастает (> 35%)
	full  = { scale = 1.0, visible = true  },  -- полная (> 85%)
}
Farm.SHEEP_START_WOOL = 60   -- с шерстью, но до стрижки ещё расти

-- ── КЛИПЫ ФЕРМЕРА (R6, таблицы в PirateCrewClips / FarmerClips) ──
-- Часть переиспользована из готового набора (Walk, Run, CarryCrate, RebelBeckon,
-- Oil_PickCan), остальные написаны в FarmerClips.lua.
Farm.CLIPS = {
	HoeEnter = "Farm_HoeEnter",
	HoeLoop = "Farm_HoeLoop",
	HoeExit = "Farm_HoeExit",
	WalkHoe = "Farm_WalkHoe",
	HayShoulderWalk = "Farm_HayShoulderWalk",
	HayShoulderIdle = "Farm_HayShoulderIdle",
	BucketsWalk = "Farm_BucketsWalk",
	BucketsIdle = "Farm_BucketsIdle",
	HeavyCarryWalk = "Farm_HeavyCarryWalk",
	Sow = "Farm_SowLoop",
	Water = "Farm_WaterLoop",
	Pluck = "Farm_Pluck",
	FeedHand = "Farm_FeedHand",
	Scoop = "Farm_Scoop",
	Herd = "Farm_Herd",
	Shoo = "Farm_Shoo",
	CatchSheep = "Farm_CatchSheep",
	CarrySheep = "Farm_CarrySheep",
	Wave = "Farm_Wave",
	Talk = "Farm_TalkLoop",
	Point = "Farm_Point",
	Shrug = "Farm_Shrug",
	Nod = "Farm_Nod",
	ThumbUp = "Farm_ThumbUp",
	IdleLook = "Farm_IdleLook",
	WipeBrow = "Farm_WipeBrow",
	StretchBack = "Farm_StretchBack",
	LeanTool = "Farm_LeanTool",

	Idle        = "Oil_Wait",
	Walk        = "Walk",
	Jog         = "Run",
	CarryIdle   = "Farm_CarryIdle",
	CarryWalk   = "Farm_CarryWalk",
	PickUp      = "Oil_PickCan",
	PutDown     = "Farm_PutDown",
	OperateDoor = "Farm_Door",
	PlaceHay    = "Farm_PlaceHay",
	PourWater   = "Farm_Pour",
	RakeLoop    = "Farm_Rake",
	CallAnimal  = "RebelBeckon",
	CalmAnimal  = "Farm_Calm",
	ShearEnter  = "Farm_ShearEnter",
	ShearLoop   = "Farm_ShearLoop",
	ShearExit   = "Farm_ShearExit",
	InspectAnimal = "Farm_Inspect",
	Sleep       = "House_Sleep",
	SleepEnter  = "House_SleepEnter",
	SleepExit   = "House_SleepExit",
}
-- длительности разовых клипов: на них ждёт сервер (совпадают с FarmerClips)
Farm.CLIP_LEN = {
	HoeEnter = 0.8,
	HoeExit = 0.8,
	Pluck = 1.4,
	FeedHand = 2.2,
	Scoop = 1.6,
	Shoo = 1,
	CatchSheep = 1.5,
	Wave = 1.6,
	Point = 1.4,
	Shrug = 1.2,
	Nod = 0.8,
	ThumbUp = 1.2,
	IdleLook = 3,
	WipeBrow = 2,
	StretchBack = 2.4,

	PickUp = 1.0, PutDown = 1.1, OperateDoor = 1.2, PlaceHay = 2.4, PourWater = 2.6,
	CallAnimal = 1.6, CalmAnimal = 3.6, ShearEnter = 1.2, ShearLoop = 2.0, ShearExit = 1.2,
	InspectAnimal = 2.0,
}
Farm.HOE_HIT_AT = 0.7
Farm.PLUCK_AT = 0.8
Farm.SCOOP_AT = 0.9
Farm.POUR_AT   = 1.0   -- момент, с которого льётся вода внутри Farm_Pour
Farm.GRAB_AT   = 0.55  -- момент захвата внутри Oil_PickCan
Farm.RELEASE_AT = 0.6  -- момент отпускания внутри Farm_PutDown

-- Хват реквизита в правой руке (как Defs.GRIP_* у вышки): CFrame относительно Right Arm
Farm.GRIP = {
	hoe = CFrame.new(0, -0.9, -0.2) * CFrame.Angles(math.rad(-70), 0, 0),
	watering = CFrame.new(0, -1.1, -0.3),
	seedbag = CFrame.new(0, -1.0, -0.2),

	bucket = CFrame.new(0, -1.15, 0),
	rake   = CFrame.new(0, -0.9, -0.3) * CFrame.Angles(math.rad(-60), 0, 0),
	shears = CFrame.new(0, -1.05, -0.2) * CFrame.Angles(math.rad(-90), 0, 0),
	hay    = CFrame.new(0, -1.05, -0.55),
	wool   = CFrame.new(0, -1.0, -0.55),
	-- корзина с шерстью: одной рукой за верх ручки, висит под кистью
	basket = CFrame.new(0, -1.0, 0.1),
}

-- ── КЛИПЫ ОВЦЫ (SheepClips) — абстрактные состояния → клипы рига ──
Farm.SHEEP_CLIPS = {
	Idle = "Idle", Walk = "Walk", Graze = "Graze", Eat = "Eat", Drink = "Drink",
	Rest = "Rest", Look = "Look", Shear = "ShearIdle", Startled = "Startled",
	Run = "Walk", React = "Startled",
}
Farm.SHEEP_REACT_LEN = 0.9

-- ── ГЕОМЕТРИЯ ФЕРМЫ (метры Blender, см. шапку) ──
-- Опорная деталь для начала координат и масштаба: Ground_Surface — плита 9.4 × 8.84 м
-- с центром в (0, 0, 0.0175). Запасные — на случай, если её вырезали.
Farm.ORIGIN_REFS = {
	{ part = "Ground_Surface", size = 9.4,  centre = { 0, 0, 0.0175 } },
	{ part = "Ground_Turf",    size = 9.4,  centre = { 0, -0.01, -0.12 } },
	{ part = "Barn_Floor",     size = 2.84, centre = { 1.6, 2.28, 0.28 } },
}
Farm.BBOX_X_M   = 9.4     -- ширина всей модели по x в метрах (запасной масштаб)
Farm.BBOX_CENTRE_Z_M = 1.34

-- Рабочие точки: { x, y, z, faceX, faceY } — где стоять и куда смотреть
-- (направление взгляда задаётся точкой в тех же осях). z = 0 — уровень плиты.
Farm.POINTS = {
	-- запас сена — тюки справа у ограды
	hay_store    = { 2.55, 0.45, 0, 3.3, 0.45 },
	-- запас воды — бочка у левой ограды (ставится скриптом, в модели её нет)
	-- бочка встроена в модель справа у тюков (3.28, −1.14); фермер подходит с
	-- запада. Если бочка в модели найдена, точка пересчитывается от неё
	-- (FarmSystem, fr.override), эти числа — запасные
	water_store  = { 2.25, -1.14, 0, 3.3, -1.14 },
	water_barrel = { 3.28, -1.14, 0 },
	-- кормушка: фермер кладёт со стороны двора, овцы едят там же по бокам
	feeder_fill  = { -2.25, 1.25, 0, -2.25, 2.1 },
	feeder_eat_1 = { -2.85, 1.3, 0, -2.85, 2.1 },
	feeder_eat_2 = { -1.65, 1.3, 0, -1.65, 2.1 },
	-- поилка: фермер льёт с северного торца, овцы пьют с восточного борта
	trough_pour  = { -3.17, -0.45, 0, -3.17, -1.5 },
	trough_drink_1 = { -2.3, -1.8, 0, -3.2, -1.8 },
	trough_drink_2 = { -2.3, -1.15, 0, -3.2, -1.15 },
	-- хлев
	barn_out     = { 1.6, -0.5, 0, 1.6, 1.0 },     -- перед дверью снаружи
	barn_in      = { 1.6, 1.4, 0, 1.6, 2.5 },      -- сразу за дверью
	barn_clean   = { 1.6, 2.2, 0.3, 1.6, 3.2 },    -- уборка подстилки (стоит на сене)
	waste_dump   = { 3.55, 2.4, 0, 3.9, 2.4 },     -- куда уносит грязную подстилку
	rest_1 = { 0.85, 1.6, 0.3 }, rest_2 = { 2.35, 1.6, 0.3 },
	rest_3 = { 0.85, 3.0, 0.3 }, rest_4 = { 2.35, 3.0, 0.3 },
	-- стрижка: овца стоит справа перед оградой, фермер сбоку
	shear_sheep  = { 2.6, -2.2, 0, 2.6, -3.5 },
	shear_worker = { 3.35, -2.2, 0, 2.6, -2.2 },
	wool_drop    = { 2.6, -2.95, 0 },
	-- склад продукции — ящик у правого фонаря, фермер подходит слева
	-- ящик встроен слева между поилкой и навесом (−2.58, 0.24); подход с востока
	wool_store   = { -1.55, 0.24, 0, -2.6, 0.24 },
	wool_crate   = { -2.58, 0.24, 0 },
	-- отдых/ожидание фермера и вывеска у ворот
	worker_rest  = { -1.0, -2.9, 0, 0, -3.5 },
	-- вывеска: над коньком хлева (крыша до 2.92 м), а не внутри двора
	sign         = { 1.6, 2.3, 3.9 },
	gate_out     = { 0, -4.3, 0, 0, -3.5 },
}

-- Двор: где гуляют овцы (прямоугольник x1,y1,x2,y2) и что в нём занято
Farm.YARD = { -3.5, -3.1, 3.5, 1.4 }
Farm.YARD_BLOCKED = {
	{ -3.9, 1.5, -0.7, 4.0 },     -- навес с кормушкой
	{ -3.7, -2.2, -2.7, -0.8 },   -- поилка
	{ 0.0, 0.5, 3.2, 4.0 },       -- хлев
	{ 2.7, -0.3, 3.9, 1.2 },      -- тюки
	{ 2.1, -3.5, 3.9, -1.6 },     -- площадка стрижки
	{ 2.6, -1.8, 3.95, -0.5 },    -- бочка
	{ -3.65, -0.5, -1.6, 0.95 },  -- ящик шерсти
}
Farm.BARN = { 0.35, 1.0, 2.85, 3.5 }    -- внутренность хлева
-- Куда овца может ступить вообще (следуя за фермером, на стрижку): вся площадка
-- внутри ограды минус твёрдые объекты; в хлев — только через проём.
Farm.OUTER  = { -3.7, -3.3, 3.7, 3.9 }
Farm.SOLIDS = {
	{ 0.06, 0.64, 3.14, 3.92 },    -- хлев (стены)
	{ -3.6, 1.7, -1.3, 2.6 },      -- кормушка
	{ -3.6, -2.15, -2.75, -0.85 }, -- поилка
	{ 2.85, -0.15, 3.7, 1.05 },    -- тюки
	{ 2.7, -1.72, 3.9, -0.56 },    -- бочка
	{ -3.55, -0.4, -1.7, 0.85 },   -- ящик шерсти
}

-- Двери: деталь, петля (метры от ЦЕНТРА детали в осях Blender x/y), угол закрытия
-- и открытия (градусы вокруг вертикали; авторская поза = openDeg).
-- Створки хлева в модели распахнуты наружу на 120°, ворота — закрыты.
Farm.DOORS = {
	{ part = "Barn_Door_Left",  hinge = {  0.15, 0.259 }, openDeg = 0, closeDeg = 120  },
	{ part = "Barn_Door_Right", hinge = { -0.15, 0.259 }, openDeg = 0, closeDeg = -120 },
	{ part = "Gate",            hinge = { -0.775, 0.0  }, openDeg = -90, closeDeg = 0  },
}
Farm.DOOR_SWING_SEC = 0.9
-- Проём хлева (метры): дверь не закрывается, пока в нём кто-то есть
Farm.BARN_DOORWAY = { 0.8, -0.35, 2.4, 0.95 }

-- детали, по которым ходит фермер (группа пола OilFloor) — всё остальное для
-- него сквозное, как у рабочих вышки
Farm.FLOOR_PARTS = { "Ground_Surface", "Ground_Turf", "Barn_Floor", "Interior_Hay_Bedding", "Path_Stones", "Barn_Foundation" }

-- Вывеска
Farm.UI = {
	BACK  = Color3.fromRGB(18, 20, 26),
	TITLE = Color3.fromRGB(245, 246, 250),
	OK    = Color3.fromRGB(180, 230, 140),
	WARN  = Color3.fromRGB(255, 122, 106),
	WOOL  = Color3.fromRGB(240, 236, 220),
}

-- ═══════════ геометрия: из метров Blender в мир ═══════════

-- Масштаб и начало координат модели по опорной детали. Возвращает
-- { origin = CFrame (поворот модели, позиция точки (0,0,0) Blender), scale = студов в метре }.
function Farm.frame(model)
	local rot, origin, scale
	for _, ref in ipairs(Farm.ORIGIN_REFS) do
		local p = model:FindFirstChild(ref.part, true)
		-- импортёр оборачивает MeshPart в одноимённый Model-узел: берём деталь внутри
		if p and p:IsA("Model") then p = p:FindFirstChildWhichIsA("BasePart", true) end
		if p and p:IsA("BasePart") then
			rot = p.CFrame.Rotation
			scale = p.Size.X / ref.size
			local c = ref.centre
			origin = p.Position - rot:VectorToWorldSpace(Vector3.new(c[1], c[3], -c[2]) * scale)
			break
		end
	end
	if not origin then
		-- опорной детали нет: считаем от габарита всей модели
		local cf, size = model:GetBoundingBox()
		rot = cf.Rotation
		scale = size.X / Farm.BBOX_X_M
		origin = cf.Position - rot:VectorToWorldSpace(Vector3.new(0, Farm.BBOX_CENTRE_Z_M * scale, 0))
	end
	return { origin = CFrame.new(origin) * rot, scale = scale, rot = rot }
end

-- Blender (x, y, z) метры → мировая точка
function Farm.toWorld(fr, x, y, z)
	return fr.origin:PointToWorldSpace(Vector3.new(x, z or 0, -y) * fr.scale)
end

-- Рабочая точка по имени: CFrame (позиция + куда смотреть), nil если нет
function Farm.pointCF(fr, name)
	-- точка, пересчитанная от реальной детали модели (бочка/ящик), важнее таблицы
	if fr.override and fr.override[name] then return fr.override[name] end
	local p = Farm.POINTS[name]
	if not p then return nil end
	local pos = Farm.toWorld(fr, p[1], p[2], p[3] or 0)
	if p[4] then
		local look = Farm.toWorld(fr, p[4], p[5], p[3] or 0)
		local d = look - pos
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude > 0.01 then return CFrame.lookAt(pos, pos + d.Unit) end
	end
	return CFrame.new(pos)
end

-- Мировая точка → метры Blender (x, y) относительно фермы
function Farm.toLocal(fr, pos)
	local l = fr.origin:PointToObjectSpace(pos) / fr.scale
	return l.X, -l.Z
end

local function inRect(r, x, y)
	return x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4]
end

function Farm.inYard(x, y)
	if not inRect(Farm.YARD, x, y) then return false end
	for _, b in ipairs(Farm.YARD_BLOCKED) do
		if inRect(b, x, y) then return false end
	end
	return true
end

function Farm.inBarn(x, y)
	return inRect(Farm.BARN, x, y)
end

function Farm.inDoorway(x, y)
	return inRect(Farm.BARN_DOORWAY, x, y)
end

function Farm.walkable(x, y)
	if inRect(Farm.BARN, x, y) or inRect(Farm.BARN_DOORWAY, x, y) then return true end
	if not inRect(Farm.OUTER, x, y) then return false end
	for _, b in ipairs(Farm.SOLIDS) do
		if inRect(b, x, y) then return false end
	end
	return true
end

-- случайная точка двора (метры)
function Farm.randomYard()
	local r = Farm.YARD
	for _ = 1, 40 do
		local x = r[1] + math.random() * (r[3] - r[1])
		local y = r[2] + math.random() * (r[4] - r[2])
		if Farm.inYard(x, y) then return x, y end
	end
	return 0, -1.5
end

return Farm
