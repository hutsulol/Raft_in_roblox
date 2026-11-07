-- PiratePatrolBoat.server.lua
-- ПИРАТСКИЕ КАТЕРА: патрульный (угроза) и грузовой (награда).
--
-- Машинерия у обоих одна — риг, слежка, автомат состояний, ход; различаются только
-- спецификации в TYPES: шаблоны, геометрия корпуса, посты, оружие и повадки.
--   Patrol  три пирата с автоматами, цепляется за плот и курсирует вокруг него.
--   Cargo   один охранник с пистолетом, полная палуба груза. НЕ гоняется: подходит,
--           глушит мотор и стоит под обыск — по движущейся заякоренной палубе игрок
--           ходить не может, его стряхнёт за борт. Каждый груз обыскивается своим
--           ProximityPrompt и исчезает.
--
-- Расписание: раз в двое суток, в 40% дня (до грозового тумана волны, он встаёт на
-- 0.6 дня). Первые пять дней приходят только одиночки — грузовой; патрульный с тремя
-- пиратами добавляется в ротацию с шестого дня.
--
-- Катер появляется В СЕКТОРЕ ПЕРЕД ПЛОТОМ (как острова в WorldEventSpawner). Дальше
-- фазы хода:
--   APPROACH  единственная цель — дойти до плота. Курс пересчитывается каждый кадр,
--             так что уплывающий плот катер ведёт на упреждение и не теряет.
--   ESCORT    экипаж кого-то заметил или по нему открыли огонь → катер цепляется:
--             курсирует ВОКРУГ плота по кругу радиуса passOffset, который едет
--             вместе с плотом. Плот всё время на траверзе, то есть под секторами
--             экипажа. Далеко отойти он уже не может.
--   LEAVE     прошёл мимо незамеченным / потерял цель на AGGRO_FORGET / выбит
--             экипаж / вышло ESCORT_MAX → уходит за горизонт и удаляется.
-- На катере ТРИ пирата на своих постах, у каждого свой сектор наблюдения, своя
-- задержка реакции и своя цепочка анимаций:
--
--   Bow      бак, левый борт    105° вперёд,     120 м  IdleLook → Suspicious → Spotted1 → Shoot1 стоя
--   Cockpit  сидит на ящике      95° левая раков., 90 м  IdleSit → StandUp → Suspicious → Spotted3 → Shoot2 с колена
--   Roof     крыша у прожектора 100° правый борт, 130 м  IdleLook → Suspicious → Spotted2 → Shoot1 стоя
--
-- Состояния: WATCH → SUSPECT → REACT → MOVE → FIRE → RETURN → WATCH.
-- Кто первым увидел — поднимает остальных, но каждый отрабатывает СВОЮ задержку
-- (крыша 0с, бак 0.55с, кокпит 1.35с), поэтому вскидываются они вразнобой.
--
-- ── ТРИГГЕРНЫЕ ТОЧКИ ──
-- Берутся ИЗ САМОЙ МОДЕЛИ катера — меши-маркеры Pt_* из PirateBoat_SCENE:
--   Pt_Spawn_Bow / Pt_Spawn_Roof      где стоят наблюдатели (пивот = место ног)
--   Pt_Spawn_Cockpit                  где сидит подвахтенный
--   Pt_Stand_Cockpit                  куда он встаёт с ящика
--   Pt_Fire_<пост>_Port / _Stbd       огневые точки на левый и правый борт
--   Pt_Fire_Roof                      крыша стреляет с места
-- Маркеры читаются один раз при спавне и удаляются с копии (в мире они не нужны).
-- Направления взгляда и секторы берутся из crew.json — числа ниже в POSTS.
-- Если какого-то маркера нет, пост встаёт по координатам из crew.json, так что
-- катер без точек тоже работает.
--
-- ── АНИМАЦИЯ ──
-- Клипы НЕ грузятся ассетами: Roblox не импортирует R6-анимацию из FBX, а публиковать
-- 14 KeyframeSequence руками ради трёх NPC — лишний шаг. Поза берётся прямо из
-- ServerStorage.PirateCrewClips (те же Motor6D-трансформы, из которых BuildAnimations
-- собирает KeyframeSequence) и раскладывается по костям вручную:
--   Torso = HRP * C0 * поза * C1⁻¹,  конечность = Torso * C0 * поза * C1⁻¹
-- Это ровно то, что делает аниматор Roblox, но без ассетов и без Humanoid.Animate.
-- Поэтому весь риг ЗАЯКОРЕН: CFrame каждой части мы ставим сами.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")
local Lighting          = game:GetService("Lighting")
local Workspace         = game:GetService("Workspace")

-- ═══════════════════════ конфиг ═══════════════════════
local RaiderCombat = require(game.ReplicatedStorage:WaitForChild("RaiderCombat"))
local DEBUG       = true    -- печатать, что нашлось и куда встал катер
local DEBUG_ZONES = false   -- true → видимые маркеры постов/секторов/огневых точек

-- Имена шаблонов. Пусто = автопоиск по списку кандидатов ниже.
local PIRATE_TEMPLATE = ""  -- напр. "Pirate" — если автопоиск возьмёт не ту модель
local BOAT_TEMPLATE   = ""

local FRONT_MARKER = "Front" -- деталь-указатель носа внутри модели катера
local LIGHT_NAMES  = { "Searchlight", "Boat_searchlight" }

-- спавн
local MAX_ACTIVE   = 1      -- на каждый ТИП катера
local SPAWN_DIST   = 300    -- студов от плота: уже виден, но ещё не вплотную
local TEST_SPAWN_DIST = 150 -- кнопка в настройках: сразу в зоне наблюдения экипажа

-- ── расписание появления ──
-- Катер приходит РАЗ В ДВОЕ СУТОК и всегда в 40% дня: светло, и грозовой туман
-- волны встаёт только на 0.6 дня (FOG_AT в WaveDirector) — то есть встреча целиком
-- укладывается в светлое время, до тумана.
-- До шестого дня выходят только ОДИНОЧНЫЕ катера (грузовой с одним охранником);
-- с шестого в ротацию добавляется патрульный с тремя пиратами.
-- ⚠️ ПЕРВЫЙ КАТЕР — НА ВТОРОЙ ДЕНЬ.
-- Раньше отсчёт шёл от первого ((day-1) % 2), и катер приходил в самый первый
-- день, когда у игрока нет ещё ни оружия, ни понимания, что происходит. Со
-- второго: день на обжиться, потом первая встреча — и с неё же первый ящик с
-- пушками, потому что ночные волны до пятого дня выключены.
local SPAWN_FIRST_DAY       = 2
local SPAWN_EVERY_DAYS      = 2
local SPAWN_AT_DAY_FRACTION = 0.40
local PATROL_FROM_DAY       = 6
local PATROL_CHANCE         = 0.5   -- доля выходов патрульного, начиная с этого дня
local FRONT_ARC    = math.rad(75)  -- ± от носа плота → появляется впереди
local PASS_OFFSET  = 40     -- на сколько студов проходит мимо плота (но не ближе
                            -- радиуса плота + PASS_CLEAR, чтобы не задеть постройки)
local PASS_CLEAR   = 18     -- было 70/35 — катер «боялся» плота и висел в сотнях студов

-- таран плота: катер кинематический (позиция пишется CFrame'ом), физика удар не
-- посчитает — столкновение считается вручную в Boat:update
local HULL_HALF            = 14    -- полукорпус катера для габарита столкновения
local IMPACT_COOLDOWN      = 4     -- секунд между засчитанными ударами
local IMPACT_DMG_PER_SPEED = 1.1   -- урон плоту за каждый студ/с скорости удара
local DESPAWN_DIST = 520
local RUN_TIMEOUT  = 600    -- страховка: катер живёт не дольше этого

-- ход (скорости — у каждого типа свои, см. TYPES)
local TURN_RATE  = math.rad(32)   -- радиан/с: катер не разворачивается на месте, но
                                  -- и не должен наматывать круги вокруг станции

-- преследование
local AGGRO_SHOT_RANGE = 300 -- на кого вскидываются, когда по экипажу попали (было 600: стреляли с горизонта)
-- ⚠️ ДАЛЬНОСТЬ ПОСТОВ УРЕЗАНА ВДВОЕ (владелец: «слишком далеко стреляют»).
-- range в таблицах постов — авторские числа в метрах модели, они умножаются на
-- масштаб катера и выходили в сотни студов. Одна ручка на все посты, а не
-- правка каждой строки: сектора и «подозрение» масштабируются вместе с ней.
local RANGE_MULT = 0.5
local AGGRO_FORGET     = 25  -- секунд без цели → отваливает и уходит
local ESCORT_MAX       = 240 -- дольше этого у борта не висит, даже если бой идёт
local LIGHT_RPS  = 0.18     -- оборотов прожектора в секунду

-- экипаж (HP и дроп — у каждого типа свои, см. TYPES)
local WALK_SPEED     = 8    -- студов/с при переходе на огневую точку
local BLEND          = 0.18 -- секунд на переход между клипами
local LOSE_TARGET    = 3.0  -- потерял цель на столько секунд → возвращается на пост
-- Темп подобран под БЛИЗКИЙ проход (70 студов вместо прежних 150): на такой
-- дистанции разброс почти не мажет, и прежние очереди по 6 патронов с паузой в
-- секунду снимали бы игроку сотню HP за пару секунд.
local BURST_MIN, BURST_MAX = 2, 4
local SHOT_PERIOD    = 0.13
local BURST_PAUSE_MIN, BURST_PAUSE_MAX = 1.6, 3.2
local SHOT_DAMAGE    = 3
local SPREAD_BASE    = math.rad(1.4)   -- разброс у ствола (визуальный, для трассы)
local SPREAD_PER_100 = math.rad(0.9)   -- + на каждые 100 студов дистанции
local SCAN_PERIOD    = 0.2  -- как часто пират ищет цель (не каждый кадр)
-- Попадание считаем НЕ по разбросу луча, а по шансу при чистой линии огня: луч с
-- разбросом на дистанции в сотню студов цеплялся за край плота, и урон не доходил
-- вообще. Луч остался только для трассы и вспышки.
local HIT_FALLOFF    = 300  -- студов, на которых шанс падает до минимума (было 500)
local HIT_MAX        = 0.75
local HIT_MIN        = 0.15
local GIB_SPEED      = 30   -- с какой силой труп отбрасывает пулей
local GIB_UP         = 12

-- слежка: та же механика, что у островных пиратов в IslandClearSystem,
-- но шкала набирается ВДВОЕ быстрее (у них TRACK_FILL_TIME = 2.5)
local TRACK_TICK      = 0.2
local TRACK_FILL_TIME = 1.25
local TRACK_DECAY     = 0.05  -- за тик, если цель пропала из виду
local RESEAT_DELAY    = 3     -- сек, после которых кокпитный меняет борт на спокойной вахте

-- брошенный катер: экипаж выбит → встал и через это время тонет
local DERELICT_SINK = 80
local SINK_TIME     = 9     -- секунд на само погружение
local SINK_DEPTH    = 45    -- на сколько студов уходит под воду перед удалением

-- геометрия импорта (boat.json). Смещение от пивота корпуса до «настоящего» начала
-- координат катера: ватерлиния, диаметральная плоскость, миделевое сечение.
local DEFAULT_SCALE  = 3    -- 1 м = 3 студа (импорт World Scale ×3)

-- ═══════════════════════ добыча с грузового ═══════════════════════
-- Ключи — реальные ресурсы инвентаря (RESOURCE_NAMES в InventoryManager);
-- "Ammo" и "Pirate" идут своими путями, как в BarrelSystem.
local CARGO_LOOT = {
	Cargo_Crate_A  = { { "Log", 6, 10 }, { "Plank", 2, 4 } },
	Cargo_Crate_B  = { { "Plank", 3, 6 }, { "Iron_Ore", 2, 4 } },
	Cargo_Crate_C  = { { "Stone", 5, 9 }, { "Iron_Ingot", 1, 2 } },
	Cargo_Barrel_A = { { "Plastic", 4, 8 }, { "Iron_Ore", 2, 4 } },
	Cargo_Barrel_B = { { "Ammo", 1, 1 }, { "Iron_Ingot", 1, 2 } },   -- «порох» = патроны
	Cargo_Sacks    = { { "Meat", 1, 3 }, { "Potato", 2, 4 } },
	-- Cargo_Fuel из добычи УБРАН: теперь это канистра с топливом, из которой
	-- наливают свою (OilCanisterSystem). Обыск уничтожал деталь, а она должна
	-- стоять, пока топливо в ней не кончится.
	Cargo_Rope     = { { "Rope", 3, 7 }, { "Pirate", 1, 3 } },
}
-- Клипы IdleSit/SitDown/StandUp сами опускают торс на 1.35 студа (пират садится на
-- ящик, а не на Seat), поэтому точку посадки паркуем чуть ниже крышки ящика.
local SEAT_DROP_M    = 0.18

-- ═══════════════════════ посты (crew.json / cargo.json, метры) ═══════════════════════
-- stand/fire/seat: {x, y, z} в осях BLENDER (нос +Y, верх +Z) — переводятся ниже.
-- face: {fx, fy} — горизонтальное направление взгляда в тех же осях.
local PATROL_POSTS = {
	{
		name = "Bow", ru = "бак",
		stand = { -0.50, 2.35, 0.98 }, face = { 0, 1 },
		patrol = { { -0.50, 1.85, 0.95 }, { -0.50, 3.05, 1.04 } },
		fire = { { -0.62, 2.75, 1.01 }, { 0.58, 2.60, 1.00 } },
		fireFace = { { 0.80, 0.60 }, { 0.86, 0.51 } },
		halfAngle = 105, range = 120, react = 0.55, suspect = 1.5,
		idle = "IdleLook", spotted = "Spotted1", shoot = "Shoot1", hold = "IdleAim",
		mSpawn = "Pt_Spawn_Bow", mPort = "Pt_Fire_Bow_Port", mStbd = "Pt_Fire_Bow_Stbd",
	},
	{
		name = "Cockpit", ru = "кокпит",
		stand = { -0.72, -2.95, 0.32 }, face = { -0.35, -0.94 },
		fire = { { -1.02, -2.10, 0.32 }, { 1.06, -2.05, 0.32 } },
		fireFace = { { -1.0, -0.12 }, { 1.0, -0.08 } },
		halfAngle = 95, range = 90, react = 1.35, suspect = 0.9,
		idle = "IdleSit", spotted = "Spotted3", shoot = "Shoot2", hold = "IdleCrouch",
		seat = { -0.68, -3.24, 0.96 }, seatFace = { -0.30, -0.95 },
		-- единственный пост, который зеркалится на другой борт: он подвахтенный и
		-- должен сидеть с той стороны, откуда идёт угроза
		canMirror = true,
		mSpawn = "Pt_Stand_Cockpit", mSeat = "Pt_Spawn_Cockpit",
		mPort = "Pt_Fire_Cockpit_Port", mStbd = "Pt_Fire_Cockpit_Stbd",
	},
	{
		name = "Roof", ru = "крыша рубки",
		stand = { 0.44, 0.14, 2.14 }, face = { 0.94, 0.34 },
		fire = { { 0.44, 0.14, 2.14 }, { 0.44, 0.14, 2.14 } },
		fireFace = { { 0.94, 0.34 }, { 0.94, 0.34 } },
		halfAngle = 100, range = 130, react = 0.0, suspect = 1.6,
		idle = "IdleLook", spotted = "Spotted2", shoot = "Shoot1", hold = "IdleAim",
		mSpawn = "Pt_Spawn_Roof", mPort = "Pt_Fire_Roof", mStbd = "Pt_Fire_Roof",
	},
}

-- Грузовой: ОДИН охранник (cargo.json). Сектор шире, чем у любого поста
-- патрульного, потому что он один, — но это НЕ круг: к одинокому охраннику можно
-- подойти сзади, и в этом смысл грузового как более лёгкой цели.
local CARGO_POSTS = {
	{
		name = "Guard", ru = "охранник",
		stand = { -0.02, -1.05, 0.647 }, face = { 0, 1 },
		fire = { { -0.62, -1.15, 0.644 }, { 0.66, -1.15, 0.644 } },
		fireFace = { { -0.96, 0.28 }, { 0.96, 0.28 } },
		halfAngle = 150, range = 85, react = 0.0, suspect = 1.4,
		idle = "PistolIdle", spotted = "PistolSpotted", shoot = "PistolShoot", hold = "PistolAim",
		-- у пистолетного набора свои имена общих клипов
		clips = { Walk = "PistolWalk", Run = "PistolWalk", Suspicious = "PistolSuspicious" },
		mSpawn = "Pt_Spawn_Guard", mPort = "Pt_Fire_Port", mStbd = "Pt_Fire_Stbd",
	},
}

-- ═══════════════════════ типы катеров ═══════════════════════
-- Машинерия (риг, слежка, автомат состояний, ход) у обоих одна; различаются
-- шаблоны, геометрия корпуса, посты, оружие и повадки.
local RAIDER_L0_POSTS = {
 {name="Bow",ru="носовой стрелок",stand={0,2.6,1.23},face={0,1},
 fire={{-.65,2.5,1.23},{.65,2.5,1.23}},fireFace={{-1,0},{1,0}},
 halfAngle=150,range=100,react=.15,suspect=.6,idle="IdleLook",spotted="Spotted1",shoot="Shoot1",hold="IdleAim",
 mSpawn="Pt_Spawn_Bow",mPort="Pt_Fire_Bow_Port",mStbd="Pt_Fire_Bow_Stbd"},
 {name="Stern",ru="кормовой стрелок",stand={0,-1.7,1.05},face={0,-1},
 fire={{-.65,-1.7,1.05},{.65,-1.7,1.05}},fireFace={{-1,0},{1,0}},
 halfAngle=150,range=100,react=.45,suspect=.7,idle="IdleLook",spotted="Spotted2",shoot="Shoot1",hold="IdleAim",
 mSpawn="Pt_Spawn_Stern",mPort="Pt_Fire_Stern_Port",mStbd="Pt_Fire_Stern_Stbd"},
}

local TYPES = {
 RaiderL0 = {
  id="RaiderL0",ru="пиратский L0",boatNames={"PirateRaiderL0"},
  crewNames={"Marine_Riffleman","Marine_Sergant","RaiderMarineR6"},
  weaponNames={"Riffle_Hero","Rifle_pcash","RaiderRifle"},posts=RAIDER_L0_POSTS,
  lenM=10,hullToOrigin=Vector3.zero,gripPitch=-78,fidelity=Enum.CollisionFidelity.Hull,
  speed=14,chase=21,orbit=11,hp=120,drop=2,hunts=true,ownHullBlocks=true,
 },
	Patrol = {
		id = "Patrol", ru = "патрульный",
		boatNames = { "PirateBoat_SCENE", "Pirate_boat", "PiratePatrolBoat", "Patrol_boat" },
		crewNames = { "PirateR6", "Pirate_crew", "Pirate_patrol", "Pirate", "Pirate lvl1", "Pirate_2", "Corsair" },
		weaponNames = { "Rifle_pcash", "PirateRifle" },
		posts = PATROL_POSTS,
		lenM = 10.151,                                  -- габарит корпуса по длине
		hullToOrigin = Vector3.new(0, -1.476, -0.345),  -- метры, оси Roblox
		gripPitch = -78,
		fidelity = Enum.CollisionFidelity.Hull,
		speed = 12, chase = 20, orbit = 9,
		hp = 120, drop = 2,
		hunts = true,                                   -- цепляется за плот и висит у борта
	},
	Cargo = {
		id = "Cargo", ru = "грузовой",
		boatNames = { "CargoBoat_SCENE", "CargoBoat", "Cargo_boat", "CargoBoat_scene" },
		crewNames = { "Security Guard", "Security_Guard", "SecurityGuard", "Guard" },
		weaponNames = { "Pistol_pcash", "Pistol" },
		posts = CARGO_POSTS,
		lenM = 6.4,
		hullToOrigin = Vector3.new(0, -1.197, -0.300),
		gripPitch = -70,
		-- по грузовому ХОДЯТ (обыскивают груз), поэтому корпусу нужна честная
		-- коллизия, а не выпуклая оболочка: с Hull палуба проваливается
		fidelity = Enum.CollisionFidelity.PreciseConvexDecomposition,
		speed = 9, chase = 14, orbit = 7,
		hp = 100, drop = 3,
		hunts = false,      -- не гоняется: подходит, глушит мотор и стоит под обыск
		linger = 240,       -- сколько стоит рядом с плотом, прежде чем уйти
		loot = CARGO_LOOT,
	},
}

-- ═══════════════════════ ЭКИПАЖ: КТО НА КАКОМ ПОСТУ ═══════════════════════
-- Имена — модели в ReplicatedStorage. Ключ — имя поста (см. PATROL_POSTS/CARGO_POSTS).
-- Список вместо строки = выбор случайного при спавне.
local MARINES = {
 RaiderL0 = {Bow="Marine_Sergant",Stern="Marine_Riffleman"},
	Patrol = {
		Bow     = "Marine_Sergant",     -- старший, впереди на баке
		Cockpit = "Marine_Private",
		Roof    = "Marine_Riffleman",
	},
	Cargo = {
		Guard = { "Marine_Private", "Marine_Corporal" },   -- один из двух
	},
}

-- Чем вооружён каждый. Оружие обычно уже лежит Tool'ом внутри самой модели (его
-- забирает Pirate.new вместе с авторским хватом); эта таблица — на случай, если
-- Tool'а в модели нет, и заодно из неё берётся звук выстрела.
local MARINE_WEAPON = {
	Marine_Corporal  = "Hero_Revolver",
	Marine_Private   = "Hero_Revolver",
	Marine_Riffleman = "Riffle_Hero",
	Marine_Sergant   = "Riffle_Hero",
	Marine_Officer   = "Riffle_Hero",
}

-- Револьвер звучит не как винтовка: одиночный тяжёлый хлопок против сухого треска.
local WEAPON_SOUND = {
	Hero_Revolver = "pistolShot",
	Riffle_Hero   = "mgShot",
}
local DEFAULT_SHOT_SOUND = "mgShot"

local function marineFor(specId, postName)
	local roster = MARINES[specId]
	local entry = roster and roster[postName]
	if type(entry) == "table" then return entry[math.random(#entry)] end
	return entry
end

local BODY = { "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local IS_BODY = { Torso = true, Head = true, ["Left Arm"] = true, ["Right Arm"] = true,
	["Left Leg"] = true, ["Right Leg"] = true }

-- ═══════════════════════ общее ═══════════════════════
local warned = {}
local function warnOnce(key, msg)
	if warned[key] then return end
	warned[key] = true
	warn("[Патруль] " .. msg)
end

local function dbg(...)
	if DEBUG then print("[Патруль]", ...) end
end

-- Метры в осях Blender (нос +Y, верх +Z) → студы в осях Roblox (нос −Z, верх +Y).
local function bl(v, s)
	return Vector3.new(v[1] * s, v[3] * s, -v[2] * s)
end

local function bdir(f)
	local d = Vector3.new(f[1], 0, -f[2])
	return (d.Magnitude > 1e-4) and d.Unit or Vector3.new(0, 0, -1)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function lerpDir(a, b, t)
	local v = a:Lerp(b, t)
	return (v.Magnitude > 1e-3) and v.Unit or b
end

local function rotateY(dir, angle)
	local c, s = math.cos(angle), math.sin(angle)
	return Vector3.new(dir.X * c + dir.Z * s, 0, -dir.X * s + dir.Z * c)
end

-- рекурсивный поиск по точному имени (регистр не важен)
local function findByName(root, name)
	local want = name:lower()
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name:lower() == want and (d:IsA("Model") or d:IsA("BasePart")) then
			return d
		end
	end
	return nil
end

-- Найденное кешируем: ReplicatedStorage в этом проекте большой, а перебирать его
-- заново на каждый спавн незачем. Промахи НЕ кешируем — модель могут доложить позже.
local templateCache = {}
local function findTemplate(forced, names, what, roots)
	local cached = templateCache[what]
	if cached and cached.Parent then return cached end
	roots = roots or { ReplicatedStorage, ServerStorage }
	local function take(inst)
		templateCache[what] = inst
		return inst
	end
	if forced and forced ~= "" then
		for _, r in ipairs(roots) do
			local f = findByName(r, forced)
			if f then return take(f) end
		end
		warnOnce("forced_" .. what, ("шаблон «%s» (%s) не найден — пробую автопоиск"):format(forced, what))
	end
	for _, n in ipairs(names) do
		for _, r in ipairs(roots) do
			local f = findByName(r, n)
			if f then return take(f) end
		end
	end
	return nil
end

-- Катер ищем ещё и в Workspace: 3D Importer кладёт модель именно туда. Найденный в
-- мире шаблон переносим в ReplicatedStorage — иначе он так и будет стоять на воде.
local function findBoatTemplate(spec)
	local key = "катер_" .. spec.id
	local tpl = findTemplate(BOAT_TEMPLATE, spec.boatNames, key)
	if tpl then return tpl end
	tpl = findTemplate(BOAT_TEMPLATE, spec.boatNames, key, { Workspace })
	if tpl then
		tpl.Parent = ReplicatedStorage
		dbg(("шаблон катера «%s» перенесён из Workspace в ReplicatedStorage"):format(tpl.Name))
	end
	return tpl
end

-- Экипаж 3D-импортом тоже часто оказывается в Workspace — забираем оттуда так же.
local function findCrewTemplate(spec)
	local key = "экипаж_" .. spec.id
	local tpl = findTemplate(PIRATE_TEMPLATE, spec.crewNames, key)
	if tpl then return tpl end
	tpl = findTemplate(PIRATE_TEMPLATE, spec.crewNames, key, { Workspace })
	if tpl then
		tpl.Parent = ReplicatedStorage
		dbg(("модель экипажа «%s» перенесена из Workspace в ReplicatedStorage"):format(tpl.Name))
	end
	return tpl
end

-- самая крупная деталь модели
local function biggestPart(inst)
	if inst:IsA("BasePart") then return inst end
	local best, bestV = nil, -1
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > bestV then best, bestV = d, v end
		end
	end
	return best
end

local function raftModel()
	local raft = Workspace:FindFirstChild("Raft")
	return (raft and raft.PrimaryPart) and raft or nil
end

local function raftCenter(raft)
	if _G.GetRaftCenter then
		local c = _G.GetRaftCenter()
		if c then return c end
	end
	return raft.PrimaryPart.Position
end

-- курс плота: BoatMovement пишет RestYaw каждый кадр
local function raftFront(raft)
	local yaw = raft.PrimaryPart:GetAttribute("RestYaw")
	if yaw then return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw)) end
	local lv = flat(raft.PrimaryPart.CFrame.LookVector)
	return (lv.Magnitude > 0.01) and lv.Unit or Vector3.new(0, 0, -1)
end

local function waterSurfaceAt(x, z, fallbackY, ignore)
	local params = RaycastParams.new()
	params.IgnoreWater = false
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local res = Workspace:Raycast(Vector3.new(x, fallbackY + 120, z), Vector3.new(0, -600, 0), params)
	if res and res.Material == Enum.Material.Water then return res.Position.Y end
	return fallbackY
end

-- ═══════════════════════ клипы ═══════════════════════
-- PirateCrewClips хранит по 12 чисел на сустав: позиция + матрица поворота построчно.
local CLIPS = nil
do
	local mod = ReplicatedStorage:FindFirstChild("PirateCrewClips") or ServerStorage:FindFirstChild("PirateCrewClips")
	if not mod then
		-- ограниченное ожидание: Rojo мог ещё не досинхронить. Вешать весь скрипт на
		-- бесконечный WaitForChild нельзя — он молча не запустится вообще.
		local t0 = os.clock()
		while not mod and os.clock() - t0 < 10 do
			task.wait(0.25)
			mod = ReplicatedStorage:FindFirstChild("PirateCrewClips") or ServerStorage:FindFirstChild("PirateCrewClips")
		end
	end
	if mod and mod:IsA("ModuleScript") then
		local ok, data = pcall(require, mod)
		if ok and type(data) == "table" and type(data.clips) == "table" then
			CLIPS = {}
			local n = 0
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
				n += 1
			end
			dbg(("клипов загружено: %d"):format(n))
		else
			warnOnce("clips_bad", "ServerStorage.PirateCrewClips не отдал данные — экипаж будет без анимации")
		end
	else
		warnOnce("clips_missing", "ServerStorage.PirateCrewClips не найден — экипаж будет без анимации")
	end
end

local function sampleClip(clip, t)
	local keys = clip.keys
	local last = keys[#keys]
	if clip.loop and clip.length > 0 then
		t = t % clip.length
	elseif t >= last.t then
		return last.p
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
	local alpha = (span > 1e-5) and ((t - a.t) / span) or 0
	local out = {}
	for joint, cf in pairs(a.p) do
		out[joint] = cf:Lerp(b.p[joint] or cf, alpha)
	end
	return out
end

-- ═══════════════════════ риг: ручная FK-раскладка R6 ═══════════════════════
local Rig = {}
Rig.__index = Rig

function Rig.new(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local torso = model:FindFirstChild("Torso")
	if not hrp or not torso then return nil end

	local self = setmetatable({ model = model, hrp = hrp, torso = torso,
		joints = {}, extras = {} }, Rig)

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			self.joints[d.Part1.Name] = { part = d.Part1, c0 = d.C0, c1i = d.C1:Inverse() }
		end
	end
	if not self.joints["Torso"] then return nil end -- не R6 → раскладывать нечего

	-- всё, что не кость (шляпа, бандана, оружие): запоминаем смещение относительно
	-- БЛИЖАЙШЕЙ кости в исходной позе — дальше едет вместе с ней
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= hrp and not IS_BODY[d.Name] then
			local host, hostD = nil, math.huge
			for name in pairs(IS_BODY) do
				local part = (name == "Torso") and torso or (self.joints[name] and self.joints[name].part)
				if part then
					local dist = (part.Position - d.Position).Magnitude
					if dist < hostD then host, hostD = name, dist end
				end
			end
			if host then
				local hp = (host == "Torso") and torso or self.joints[host].part
				table.insert(self.extras, { part = d, host = host, offset = hp.CFrame:ToObjectSpace(d.CFrame) })
			end
		end
	end
	return self
end

-- pose: { Torso = CFrame, Head = CFrame, ... } — Motor6D-трансформы из клипа
function Rig:apply(rootCF, pose)
	pose = pose or {}
	local cfs = { HumanoidRootPart = rootCF }
	self.hrp.CFrame = rootCF

	local jt = self.joints["Torso"]
	local torsoCF = rootCF * jt.c0 * (pose["Torso"] or CFrame.identity) * jt.c1i
	self.torso.CFrame = torsoCF
	cfs["Torso"] = torsoCF

	for _, name in ipairs(BODY) do
		local j = self.joints[name]
		if j then
			local cf = torsoCF * j.c0 * (pose[name] or CFrame.identity) * j.c1i
			j.part.CFrame = cf
			cfs[name] = cf
		end
	end

	for _, e in ipairs(self.extras) do
		local base = cfs[e.host]
		if base and e.part.Parent then e.part.CFrame = base * e.offset end
	end
end

function Rig:partCF(name)
	if name == "Torso" then return self.torso.CFrame end
	local j = self.joints[name]
	return j and j.part.CFrame or self.hrp.CFrame
end

-- ═══════════════════════ пират ═══════════════════════
local Pirate = {}
Pirate.__index = Pirate

function Pirate.new(boat, post, template, rifleTemplate, shotSound)
	local spec = boat.spec
	local model = template:Clone()
	model.Name = "Pirate_" .. post.name
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()  -- родные Animate/Zombie/Combat не должны просыпаться
		end
	end

	-- Оружие может лежать в модели готовым Tool (так собран Security Guard). Сам Tool
	-- нам не нужен — он подбирается касанием и исчез бы у охранника из рук, — но его
	-- Grip забираем обязательно: это и есть настроенный автором хват.
	local gripCF = nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Tool") then
			local handle = d:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				gripCF = d.Grip
				handle.Name = "Weapon"
				handle.Parent = model
				for _, t in ipairs(handle:GetDescendants()) do
					if t:IsA("TouchTransmitter") or t.ClassName == "TouchInterest" then t:Destroy() end
				end
			end
			d:Destroy()
		end
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		hum = Instance.new("Humanoid")
		hum.Parent = model
	end
	hum.MaxHealth = spec.hp
	hum.Health = spec.hp
	hum.BreakJointsOnDeath = false
	hum.EvaluateStateMachine = false   -- своя физика Humanoid'а нам только мешает
	hum.AutoRotate = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false) end)

	-- всё заякорено: позы мы ставим руками, физика тут лишняя
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end

	-- Ствол в правую руку. Если он уже приехал в модели (Tool выше), внешний шаблон
	-- не нужен — иначе клонируем его из ReplicatedStorage.
	if rifleTemplate and not model:FindFirstChild("Weapon") then
		local rifle = rifleTemplate:Clone()
		if rifle:IsA("Model") then
			local p = biggestPart(rifle)
			if p then
				p.Parent = model
				rifle:Destroy()
				rifle = p
			end
		end
		if rifle:IsA("BasePart") then
			rifle.Name = "Weapon"
			rifle.Parent = model
		end
	end
	local weapon = model:FindFirstChild("Weapon")
	if weapon and weapon:IsA("BasePart") then
		weapon.Anchored = true
		weapon.CanCollide = false
		weapon.CanQuery = false
		weapon.Massless = true
	end

	local self = setmetatable({}, Pirate)
	self.boat = boat
	self.post = post
	self.model = model
	self.hum = hum
	self.dead = false
	self.shotSound = shotSound or DEFAULT_SHOT_SOUND   -- револьвер и винтовка звучат по-разному

	model.Parent = boat.folder
	self.rig = Rig.new(model)
	if not self.rig then
		warnOnce("not_r6", ("модель «%s» не R6 (нет Torso/Motor6D) — пират будет без анимации"):format(template.Name))
	elseif weapon and weapon:IsA("BasePart") and self.rig.joints["Right Arm"] then
		for i = #self.rig.extras, 1, -1 do
			if self.rig.extras[i].part == weapon or self.rig.extras[i].part:IsDescendantOf(weapon) then table.remove(self.rig.extras, i) end
		end
		local offset
		if gripCF then
			-- Оружие пришло готовым Tool → повторяем то, как его держит сам Roblox:
			--   Handle = RightArm * RightGripAttachment * Grip⁻¹
			-- Своё смещение тут нельзя: в кадре ладони есть доворот на −90° по Y, и
			-- без него ствол лежит боком — ровно на те 90°, что были видны.
			local arm = self.rig.joints["Right Arm"].part
			local att = arm:FindFirstChild("RightGripAttachment")
			local attCF = (att and att:IsA("Attachment") and att.CFrame)
				or (CFrame.new(0, -1, 0) * CFrame.Angles(0, -math.pi / 2, 0))
			offset = attCF * gripCF:Inverse()
		else
			-- голый меш без Tool (Rifle_pcash) — хват из RifleTool: рукоятка в ладонь
			offset = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(spec.gripPitch), 0, 0)
		end
		table.insert(self.rig.extras, { part = weapon, host = "Right Arm", offset = offset })
  for _,detail in ipairs(weapon:GetDescendants()) do
   if detail:IsA("BasePart") then
    table.insert(self.rig.extras,{part=detail,host="Right Arm",offset=offset*weapon.CFrame:ToObjectSpace(detail.CFrame)})
   end
  end
	end

	-- стартуем на посту (кокпитный — сидя)
	self.mirror = false
	self.localPos  = post.seatV or post.standV
	self.localFace = post.seatFaceV or post.faceV
	self.state = "WATCH"
	self.timer = 0
	self.patrolT = math.random() * 4
	self.scanAt = math.random() * TRACK_TICK
	self.target = nil
	self.lostFor = 0
	self.stood = (post.seatV == nil)
	self.track = 0        -- шкала слежки 0..1
	self.hpMode = false   -- бар переключился в здоровье (обнаружил или ранен)
	self.slot = 1
	self:play(post.idle)
	self:setupHealth()
	return self
end

-- ЗЕРКАЛИМ ТОЛЬКО ВЗГЛЯД, НЕ ПОЗИЦИЮ.
-- Палуба катера несимметрична: по левому борту ящик, по правому бочка. Любая
-- «отзеркаленная» точка — это выдуманное место, которого в модели нет: точка
-- сидения уезжала в воздух над правым бортом, а точка «куда встать» — внутрь
-- бочки, где пират и застревал навсегда, считая, что дошёл. Безопасны только
-- авторские маркеры Pt_*, поэтому позиции берутся как есть, а на нужный борт
-- разворачивается корпус и вместе с ним сектор наблюдения. Огневые точки уже
-- заданы с обоих бортов отдельными маркерами — их зеркалить и не требуется.
function Pirate:mp(dir)
	if not self.mirror or not dir then return dir end
	return Vector3.new(-dir.X, dir.Y, dir.Z)
end
function Pirate:standAt()    return self.post.standV end
function Pirate:seatAt()     return self.post.seatV end
function Pirate:faceAt()     return self:mp(self.post.faceV) end
function Pirate:seatFaceAt() return self:mp(self.post.seatFaceV) end

function Pirate:setupHealth()
	local ok, EnemyHealthBar = pcall(function()
		return require(ReplicatedStorage:WaitForChild("EnemyHealthBar", 5))
	end)
	if ok and EnemyHealthBar then
		-- Голову ищем рекурсивно и с запасными вариантами: у морпехов рига могут быть
		-- вложены в подмодель, и прежний плоский FindFirstChild молча возвращал nil —
		-- бар тогда не создавался вовсе, а в логах было пусто.
		local head = self.model:FindFirstChild("Head", true)
			or self.model:FindFirstChild("Torso", true)
			or self.model:FindFirstChildWhichIsA("BasePart")
		if head then
			local hb = EnemyHealthBar.new({
				name = self.boat.spec.id == "Cargo" and "ОХРАННИК" or "ПИРАТ",
				maxHp = self.hum.MaxHealth, cur = self.hum.Health, difficulty = 1, surface = true,   -- в мире, как у всех пиратов: экранный бар у RaiderL0 вдали раздувался
			})
			hb.attach(head, 2.4, "PirateHP")
			-- HP видно СРАЗУ — как у пловцов (SwimmingPirate) и островной живности.
			-- Раньше бар стартовал скрытым и включался только когда матрос уже взял
			-- игрока в свой сектор наблюдения; при заходе с кормы или сбоку над
			-- головой не было ничего — отсюда «у матросов нет UI хп».
			-- Шкала слежки никуда не делась: она ПОДМЕНЯЕТ бар (глаз вместо цифр),
			-- пока матрос нас нащупывает, и снова уступает место HP, если потерял.
			hb.setVisible(true)
			self.bar = hb
			self.hum.HealthChanged:Connect(function()
				if self.hpMode or (self.track or 0) <= 0.02 then
					hb.setHP(self.hum.Health, self.hum.MaxHealth)
				end
			end)
		else
			warnOnce("no_head", ("у модели «%s» не нашлось части для HP-бара"):format(self.model.Name))
		end
	else
		warnOnce("no_hpbar", "EnemyHealthBar не загрузился — экипаж будет без HP-бара")
	end
	-- Died при выключенном EvaluateStateMachine не срабатывает — ловим ноль здоровья.
	-- Просадка здоровья — это ещё и сигнал «по нам стреляют»: катер цепляется за плот
	-- даже если стрелка никто не видел в своём секторе.
	local lastHp = self.hum.Health
	self.hum.HealthChanged:Connect(function(h)
		if h <= 0 then
			self:die()
		elseif h < lastHp - 0.01 then
			self:reveal()          -- ранен = позиция раскрыта, бар переходит в HP
			self.boat:onAttacked()
		end
		lastHp = h
	end)
end

-- обнаружил игрока или получил пулю: бар из режима слежки навсегда в режим здоровья
function Pirate:reveal()
	if self.hpMode then return end
	self.hpMode = true
	self.track = 1
	if self.bar then
		self.bar.setVisible(true)
		self.bar.setHP(self.hum.Health, self.hum.MaxHealth)
	end
end

function Pirate:die()
	if self.dead then return end
	self.dead = true
	local pos = self.rig and self.rig:partCF("Torso").Position or self.model:GetPivot().Position

	-- монеты и направление отброса — от ближайшего игрока (атрибуции урона в проекте нет)
	local best, bestD = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - pos).Magnitude
			if d < bestD then best, bestD = plr, d end
		end
	end

	-- ОТБРОС ПО ИНЕРЦИИ ПУЛИ, как у зомби: труп летит ОТ стрелка, а не падает на
	-- месте. Суставы не рвём — отбрасывает целое тело.
	local away = Vector3.new(math.random(-10, 10) / 10, 0, math.random(-10, 10) / 10)
	local bhrp = best and best.Character and best.Character:FindFirstChild("HumanoidRootPart")
	if bhrp then
		local d = flat(pos - bhrp.Position)
		if d.Magnitude > 0.1 then away = d.Unit end
	end
	away = (away.Magnitude > 0.1) and away.Unit or Vector3.new(0, 0, 1)

	for _, d in ipairs(self.model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.Massless = false
			local spread = Vector3.new(math.random(-25, 25) / 100, math.random(0, 20) / 100,
				math.random(-25, 25) / 100)
			d.AssemblyLinearVelocity = (away + spread).Unit * GIB_SPEED + Vector3.new(0, GIB_UP, 0)
			d.AssemblyAngularVelocity = Vector3.new(math.random(-12, 12), math.random(-12, 12),
				math.random(-12, 12))
		end
	end
	local bar = self.model:FindFirstChild("PirateHP", true)
	if bar then bar:Destroy() end

	if _G.SpawnPirateCoins and best then _G.SpawnPirateCoins(pos, best, self.boat.spec.drop) end
	Debris:AddItem(self.model, 6)
	dbg(("пост %s убит"):format(self.post.name))
end

-- ── анимация ──
-- Имя общего клипа для этого поста. У пистолетного набора свои Walk/Suspicious и
-- нет отдельного бега — post.clips подменяет их, всё остальное берётся как есть.
function Pirate:anim(key)
	local map = self.post.clips
	return (map and map[key]) or key
end

-- force = внешняя реакция (огнемёт), её нельзя перебивать обычной логикой поста.
-- ⚠️ БЕЗ ЭТОГО ЗАМКА РЕАКЦИЯ НЕ ВИДНА ВООБЩЕ: update поста зовёт play каждый тик
-- и возвращает свой idle через кадр после того, как морпех загорелся.
function Pirate:play(name, fade, force)
	if not force and (self.reactUntil or 0) > os.clock() then return end
	if self.clipName == name then return end
	if CLIPS and CLIPS[name] then
		self.blendFrom = self.pose
		self.blendT = 0
		self.blendFor = fade or BLEND
		self.clipName = name
		self.clip = CLIPS[name]
		self.clipT = 0
	end
end

function Pirate:clipDone()
	return (not self.clip) or self.clip.loop or self.clipT >= self.clip.length
end

function Pirate:stepAnim(dt)
	if not self.clip then return end
	self.clipT += dt
	local pose = sampleClip(self.clip, self.clipT)
	if self.blendFrom then
		self.blendT += dt
		local fade = self.blendFor or BLEND
		if self.blendT >= fade then
			self.blendFrom = nil
		else
			local a = math.clamp(self.blendT / fade, 0, 1)
			local mixed = {}
			for joint, cf in pairs(pose) do
				mixed[joint] = (self.blendFrom[joint] or CFrame.identity):Lerp(cf, a)
			end
			pose = mixed
		end
	end
	self.pose = pose
end

-- ── движение по палубе (всё в системе координат катера) ──
function Pirate:moveTo(dt, goalPos, goalFace)
	local step = WALK_SPEED * dt
	local d = goalPos - self.localPos
	local arrived = true
	if d.Magnitude > step then
		self.localPos += d.Unit * step
		arrived = false
	else
		self.localPos = goalPos
	end
	local f = self.localFace:Lerp(goalFace, math.min(1, dt * 6))
	self.localFace = (f.Magnitude > 1e-3) and f.Unit or goalFace
	return arrived
end

function Pirate:worldCF()
	local origin = self.boat.originCF
	-- localPos — место ног; HumanoidRootPart у R6 на 3 студа выше
	local pos = origin:PointToWorldSpace(self.localPos + Vector3.new(0, 3, 0))
	local look = origin:VectorToWorldSpace(self.localFace)
	if look.Magnitude < 1e-3 then look = origin.LookVector end
	return CFrame.lookAt(pos, pos + look)
end

-- Сектор принадлежит ПОСТУ, а не телу: пират может отвернуться на маршруте или
-- довернуться на цель, но зона наблюдения от этого не должна ездить.
function Pirate:postCF()
	local origin = self.boat.originCF
	local at = origin:PointToWorldSpace(self:standAt() + Vector3.new(0, 1.5, 0))
	local look = origin:VectorToWorldSpace(self:faceAt())
	return CFrame.lookAt(at, at + look)
end

-- ── поиск цели ──
-- Высота из проверки выброшена намеренно: плот всегда на воде, а пират может стоять
-- на крыше — честный 3D-угол давал бы ложные промахи вблизи.
local function inSector(fromCF, pos, halfDeg, range)
	local to = flat(pos - fromCF.Position)
	if to.Magnitude < 0.5 or to.Magnitude > range then return false end
	local fwd = flat(fromCF.LookVector)
	if fwd.Magnitude < 1e-3 then return false end
	local dot = math.clamp(fwd.Unit:Dot(to.Unit), -1, 1)
	return math.deg(math.acos(dot)) <= halfDeg
end

function Pirate:hasLOS(fromPos, hrp)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- катер и сам игрок из проверки исключены: между ними должна быть только вода
	params.FilterDescendantsInstances = { self.boat.spec.ownHullBlocks and self.model or self.boat.folder, hrp.Parent }
	params.IgnoreWater = true
	return Workspace:Raycast(fromPos, hrp.Position - fromPos, params) == nil
end

function Pirate:findTarget()
	local post = self.post
	local cf = self:postCF()
	local eye = cf.Position
	local best, bestD = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hum and hum.Health > 0 and inSector(cf, hrp.Position, post.halfAngle, post.rangeStuds) then
			local d = (hrp.Position - cf.Position).Magnitude
			if d < bestD and self:hasLOS(eye, hrp) then
				best, bestD = hrp, d
			end
		end
	end
	return best
end

function Pirate:targetAlive()
	local hrp = self.target
	if not hrp or not hrp.Parent then return false end
	local hum = hrp.Parent:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

-- какая из двух огневых точек смотрит на цель: левый борт или правый.
-- Пират не должен стрелять сквозь рубку. Гистерезис в 6 студов обязателен: катер
-- ходит вокруг плота, цель постоянно пересекает диаметральную плоскость, и без него
-- пират бегал бы от борта к борту, ни разу не дойдя до состояния «стреляю».
function Pirate:fireSlot()
	if not self.target then return self.slot or 1 end
	local rel = self.boat.originCF:PointToObjectSpace(self.target.Position)
	if rel.X > 6 then
		self.slot = 2
	elseif rel.X < -6 then
		self.slot = 1
	end
	return self.slot or 1
end

-- ── стрельба ──

-- Keep the R6 body stable; aim the rifle and both hands as one unit.
function Pirate:applyRaiderPose()
 local r=self.rig;local root=self:worldCF();r:apply(root,{})
 local torso=r.torso.CFrame
 local ready=self.target and self.target.Parent
 local recoil=math.exp(-math.max(0,os.clock()-(self.lastShotAt or -100))*24)*.12
 local pos=torso:PointToWorldSpace(Vector3.new(.55,.35,-1.05+recoil))
 local toward=ready and self.target.Position or (pos+root.LookVector*20-Vector3.new(0,5,0))
 local gun=CFrame.lookAt(pos,toward)
 local weapon=self.model:FindFirstChild('Weapon')
 if weapon then
  if not self.weaponPieces then
   self.weaponPieces={}
   for _,e in ipairs(r.extras) do if e.part==weapon or e.part:IsDescendantOf(weapon) then
    table.insert(self.weaponPieces,{part=e.part,offset=weapon.CFrame:ToObjectSpace(e.part.CFrame)})
   end end
  end
  for _,p in ipairs(self.weaponPieces)do p.part.CFrame=gun*p.offset end
  local barrel=weapon:FindFirstChild('Barrel')
  self.muzzlePosition=barrel and (barrel.CFrame* CFrame.new(0,0,-barrel.Size.Z/2)).Position or (gun*CFrame.new(0,0,-1.8)).Position
 end
 for _,side in ipairs({-1,1})do
  local name=side==1 and 'Right Arm' or 'Left Arm';local j=r.joints[name]
  if j then
   local shoulder=torso:PointToWorldSpace(Vector3.new(side*1.45,.65,0))
   local hand=gun:PointToWorldSpace(side==1 and Vector3.new(0,-.3,.4) or Vector3.new(-.1,-.15,-.9))
   local axis=(hand-shoulder).Unit
   j.part.CFrame=CFrame.lookAt(shoulder+axis*j.part.Size.Y/2,hand+axis)*CFrame.Angles(math.pi/2,0,0)
   for _,e in ipairs(r.extras)do if e.host==name and e.part~=weapon and not (weapon and e.part:IsDescendantOf(weapon))then e.part.CFrame=j.part.CFrame*e.offset end end
  end
 end
end

function Pirate:shoot()
 if self.boat.spec.id=="RaiderL0" and self.rig then self:applyRaiderPose() end
	local hrp = self.target
	if not hrp or not hrp.Parent then return end
	local arm = self.rig and self.rig:partCF("Right Arm") or self.model:GetPivot()
	local toTarget = hrp.Position - arm.Position
	if toTarget.Magnitude < 1 then return end
	local origin = self.muzzlePosition or (arm.Position + flat(toTarget).Unit * 1.6 + Vector3.new(0, 0.4, 0))
 if self.boat.spec.ownHullBlocks and not self:hasLOS(origin,hrp) then return end
 self.lastShotAt=os.clock()
 self.model:SetAttribute("ShotsFired",(self.model:GetAttribute("ShotsFired") or 0)+1)
	local to = hrp.Position - origin
	local dist = to.Magnitude
	if dist < 1 then return end

	-- разброс растёт с дистанцией: издалека они мажут, вблизи — нет
	local spread = SPREAD_BASE + SPREAD_PER_100 * (dist / 100)
	local dir = to.Unit
	local right = dir:Cross(Vector3.new(0, 1, 0))
	right = (right.Magnitude > 1e-3) and right.Unit or Vector3.new(1, 0, 0)
	local up = right:Cross(dir).Unit
	dir = (dir
		+ right * math.tan((math.random() - 0.5) * 2 * spread)
		+ up * math.tan((math.random() - 0.5) * 2 * spread)).Unit

	pcall(function()
		require(ReplicatedStorage:WaitForChild("MuzzleFX", 2)).burst(origin, dir, { scale = 0.3, smoke = false })
	end)
	pcall(function()
		require(ReplicatedStorage:WaitForChild("CombatSounds", 2))
			.play(self.shotSound or DEFAULT_SHOT_SOUND, origin)
	end)

	-- Урон: сначала ЧИСТАЯ линия огня (луч без разброса, мимо катера и мимо самой
	-- цели), потом бросок на попадание. Раньше урон считался по лучу С РАЗБРОСОМ, и
	-- на сотне студов он почти всегда цеплял край плота вместо игрока — попаданий
	-- не было вообще.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.boat.spec.ownHullBlocks and self.model or self.boat.folder, hrp.Parent }
	params.IgnoreWater = true
	if Workspace:Raycast(origin, to, params) then return end -- за укрытием

	local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	if hrp.Parent:FindFirstChildOfClass("ForceField") then return end
	if math.random() >= math.clamp(1 - dist / HIT_FALLOFF, HIT_MIN, HIT_MAX) then return end

	hum:TakeDamage(SHOT_DAMAGE)
	if not self.boat.hitOnce then
		self.boat.hitOnce = true
		dbg(("урон прошёл: %d по %s с %.0f студов"):format(SHOT_DAMAGE, hrp.Parent.Name, dist))
	end
end

-- Очередь и анимация СИНХРОНИЗИРОВАНЫ по клипу: Shoot1/Shoot2 — это ровно один
-- цикл отдачи (0.40 и 0.53 с), поэтому выстрел приходится на начало каждого цикла,
-- а между очередями крутится hold (IdleAim/IdleCrouch), а не бесконечная отдача.
-- Раньше клип стрельбы играл всегда, а выстрелы шли своим таймером 0.13 с — звук,
-- вспышка и движение рук расходились.
function Pirate:stepFire(dt)
	local period = (self.clip and self.clip.loop and self.clipName == self.post.shoot)
		and self.clip.length or SHOT_PERIOD
	self.shotClock = (self.shotClock or 0) - dt
	if (self.burstLeft or 0) > 0 then
		self:play(self.post.shoot, 0.05)   -- короткий переход: клип всего 0.4 с
		if self.shotClock <= 0 then
			self.burstLeft -= 1
			self:shoot()
			-- пауза ставится ПОСЛЕ последнего патрона очереди, иначе между очередями
			-- оставался бы один цикл отдачи вместо нормального перерыва
			self.shotClock = (self.burstLeft > 0) and period
				or (BURST_PAUSE_MIN + math.random() * (BURST_PAUSE_MAX - BURST_PAUSE_MIN))
		end
	else
		self:play(self.post.hold, 0.12)    -- пауза между очередями — не дёргает руками
		if self.shotClock <= 0 then
			self.burstLeft = math.random(BURST_MIN, BURST_MAX)
			self.shotClock = 0.08          -- клип уже стартовал — первый выстрел почти сразу
		end
	end
end

-- Направление НА ЦЕЛЬ в системе координат катера.
-- Раньше здесь стоял ограничитель «не выкручиваться дальше ±70° от авторского
-- направления огневой точки». Он был ошибкой: в crew.json ОБА направления огня
-- смотрят вперёд-вправо, поэтому для цели слева угол выходил ~143°, ограничитель
-- срабатывал — и пират стрелял, не оборачиваясь к игроку. Пираты якорные, корпус
-- ставим мы сами, разворачиваться им ничего не мешает.
function Pirate:faceTarget(fallback)
	local t = self.target
	if not t or not t.Parent then return fallback end
	local rel = flat(self.boat.originCF:PointToObjectSpace(t.Position) - self.localPos)
	return (rel.Magnitude > 1e-3) and rel.Unit or fallback
end

-- плавный доворот корпуса на месте (когда никуда не идём)
function Pirate:turnTo(dt, dir, rate)
	if not dir or dir.Magnitude < 1e-3 then return end
	local f = self.localFace:Lerp(dir.Unit, math.min(1, dt * (rate or 6)))
	self.localFace = (f.Magnitude > 1e-3) and f.Unit or dir.Unit
end

-- ── слежка ──
-- Та же механика, что у островных пиратов (IslandClearSystem): шкала копится, пока
-- цель в секторе и на прямой видимости, ближе — быстрее; пропала — остывает. Время
-- полного заполнения ВДВОЕ меньше островного (1.25 с против 2.5).
function Pirate:tickTrack(dt)
	self.scanAt -= dt
	if self.scanAt > 0 then return end
	self.scanAt = TRACK_TICK

	local seen = self:findTarget()
	if seen then
		local d = (seen.Position - self:postCF().Position).Magnitude
		local prox = 1 - math.min(d / self.post.rangeStuds, 1) * 0.6
		self.track = math.clamp(self.track + TRACK_TICK / TRACK_FILL_TIME * prox, 0, 1)
		self.trackSeen = seen
		if self.target == nil then self.target = seen end
	else
		self.track = math.clamp(self.track - TRACK_DECAY, 0, 1)
		if self.track <= 0.02 then self.trackSeen = nil end
	end
	if self.bar and not self.hpMode then
		-- Бар над матросом виден всегда. Пока идёт «нащупывание» — на его месте
		-- жёлтая шкала с глазом, отпустил цель — возвращаем полосу здоровья.
		if self.track > 0.02 then
			self.bar.setTracking(self.track)
		else
			self.bar.setHP(self.hum.Health, self.hum.MaxHealth)
		end
		self.bar.setVisible(true)
	end
end

-- на какой борт разворачивать пост: туда, где противник
function Pirate:mirrorTo(target)
	if not self.post.canMirror or not target then return end
	self.mirror = self.boat.originCF:PointToObjectSpace(target.Position).X >= 0
end

-- Спокойная вахта: если противник давно с другого борта, подвахтенный
-- разворачивается на ящике в ту сторону, а не сидит к нему спиной. Корпус доводит
-- обычный moveTo в WATCH, поэтому тут достаточно переставить флаг борта.
function Pirate:maybeReseat(dt)
	local post = self.post
	local want = self.boat.threatSide
	if not (post.canMirror and post.seatV and want) or (want >= 0) == self.mirror then
		self.reseatFor = 0
		return
	end
	self.reseatFor = (self.reseatFor or 0) + dt
	if self.reseatFor > RESEAT_DELAY then
		self.reseatFor = 0
		self.mirror = (want >= 0)
		dbg(("кокпит развернулся на %s борт"):format(self.mirror and "правый" or "левый"))
	end
end

-- ── автомат состояний ──
function Pirate:update(dt)
	if self.dead then return end
	if self.boat.spec.id=="RaiderL0" and RaiderCombat.crewSupport(self,dt) then return end
	if self.boat.spec.id=="RaiderL0" and not self.model:GetAttribute("OnFire") then
		local shell=RaiderCombat.threat(self)
		if shell then
			if self.model:GetAttribute("CombatPriority")~="CANNONBALL" then self.interceptSavedTarget=self.target end
			self.target=shell;self.model:SetAttribute("CombatPriority","CANNONBALL")
			self:turnTo(dt,self.boat.originCF:VectorToObjectSpace(shell.Position-self:worldCF().Position),10)
			self:applyRaiderPose();self.interceptClock=(self.interceptClock or .18)-dt
			if self.interceptClock<=0 then self.interceptClock=.16;RaiderCombat.fireAtShell(self,shell) end
			return
		elseif self.model:GetAttribute("CombatPriority")=="CANNONBALL" then
			self.target=self.interceptSavedTarget;self.interceptSavedTarget=nil;self.interceptClock=.18
			self.model:SetAttribute("CombatPriority","PLAYER")
		end
	end
	local post = self.post
	self.timer += dt

	-- ⚠️ ГОРЯЩИЙ ОГЛУШЁН, НО НЕ ЗАМОРОЖЕН.
	-- Пропускаем ТОЛЬКО принятие решений: цель, стрельбу, ходьбу — клипы паники
	-- ему ставит FlamethrowerSystem. А хвост функции (шаг анимации и постановка
	-- модели на катер) обязан отработать: первый заход выходил из update целиком,
	-- и охранник вставал столбом без анимации, будто заякоренный.
	if self.model:GetAttribute("OnFire") then
		-- решений не принимаем

	elseif self.state == "WATCH" then
		self:tickTrack(dt)
		if self.track > 0.02 and self.trackSeen then
			-- шкала пошла вверх → всматривается; сидящий сперва встанет
			self.target = self.trackSeen
			self:mirrorTo(self.target)
			self.selfSpotted = true
			self.state = "SUSPECT"
			self.timer = post.react     -- увидел сам, чужую задержку не ждёт
		elseif post.patrolV then
			-- Бак ходит вдоль борта туда-сюда. Шаг «идёт/стоит» берём из производной
			-- синуса, а не из расстояния до цели: цель уползает медленнее шага, и по
			-- расстоянию он бы всегда считался стоящим и ездил бы в позе покоя.
			self.patrolT += dt * 0.25
			local ph = self.patrolT * math.pi * 2
			local goal = post.patrolV[1]:Lerp(post.patrolV[2], (math.sin(ph) + 1) * 0.5)
			local vel = math.cos(ph)
			local moving = math.abs(vel) > 0.25
			local axis = post.patrolV[2] - post.patrolV[1]
			axis = (axis.Magnitude > 1e-3) and axis.Unit or post.faceV
			-- идёт лицом по ходу, на разворотах смотрит по сектору поста
			self:moveTo(dt, goal, moving and ((vel > 0) and axis or -axis) or post.faceV)
			self:play(moving and self:anim("Walk") or post.idle)
		else
			self:moveTo(dt, self:seatAt() or self:standAt(), self:seatFaceAt() or self:faceAt())
			self:play(post.idle)
			self:maybeReseat(dt)
		end

	elseif self.state == "SUSPECT" then
		-- Своя слежка продолжает набираться и здесь: всматривание длится ровно
		-- столько, сколько шкала идёт до конца, а не фиксированную паузу.
		if self.selfSpotted then self:tickTrack(dt) end
		if self.timer < post.react then
			-- поднят по тревоге чужим постом: отрабатывает свою задержку реакции,
			-- поэтому экипаж вскидывается вразнобой, а не синхронно
		elseif post.seatV and not self.stood then
			-- сидящий сперва встаёт, иначе всматривался бы сидя на ящике
			if self.clipName ~= self:anim("StandUp") then
				self.standFrom = self.localPos
				self:play(self:anim("StandUp"))
			elseif self:clipDone() then
				self.stood = true
				self.localPos = self:standAt()
				self.localFace = self:faceAt()
				self.timer = post.react
				self:play(self:anim("Suspicious"))
			else
				-- корпус переезжает с ящика на настил ЗА ВРЕМЯ клипа: иначе он вставал
				-- бы сидя на месте и телепортировался на палубу в последнем кадре
				local a = math.clamp(self.clipT / self.clip.length, 0, 1)
				self.localPos = self.standFrom:Lerp(self:standAt(), a)
				self.localFace = lerpDir(self.localFace, self:faceAt(), math.min(1, dt * 5))
			end
		else
			self:play(self:anim("Suspicious"))   -- ладонь козырьком, всматривается
			self:turnTo(dt, self:faceTarget(nil), 3)  -- всматривается ИМЕННО в цель
			local ready = self.selfSpotted and (self.track >= 1)
				or (not self.selfSpotted and self.timer >= post.react + post.suspect)
			if ready and self.target then
				-- ЗАМЕТИЛ: общий сбор — весь катер работает по этой цели
				self:reveal()
				self.boat:alert(self.target, self)
				-- Шок-клип — РЕДКИЙ АКЦЕНТ: не чаще раза в 3 минуты на пирата.
				-- Каждое повторное «заметил» в той же стычке проигрывало его
				-- заново — 5-6 шоков подряд читались как припадок. Повтор — без
				-- спектакля, сразу к делу.
				local nowClk = os.clock()
				if nowClk - (self.spottedShownAt or -1e9) >= 180 then
					self.spottedShownAt = nowClk
					self:play(post.spotted, 0.06)
					self.state = "REACT"
				else
					self.state = "MOVE"
				end
				self.timer = 0
			elseif self.selfSpotted and self.track <= 0.02 then
				self.target = nil       -- показалось: возвращается на пост
				self.selfSpotted = false
				self.state = "RETURN"
			end
		end

	elseif self.state == "REACT" then
		-- шок: клип сам разворачивает и вскидывает, корпус доводим на цель
		self:turnTo(dt, self:faceTarget(nil), 5)
		if self:clipDone() or self.timer > 1.4 then
			self.state = "MOVE"
			self.timer = 0
		end

	elseif self.state == "MOVE" or self.state == "FIRE" then
		self:updateCombat(dt)

	elseif self.state == "RETURN" then
		-- Возвращаемся всегда на «стоячую» точку поста; кокпитный уже с неё сядет.
		-- Признак «на ногах» ровно один — stood. Раньше их было два (stood и sitting),
		-- и рассогласование их значений заставляло RETURN пропустить посадку: пират
		-- оставался стоять, но считался сидящим, и больше уже не вставал.
		if not self:moveTo(dt, self:standAt(), self:faceAt()) then
			self:play(self:anim("Walk"))
		elseif post.seatV and self.stood then
			if self.clipName ~= self:anim("SitDown") then
				self.standFrom = self.localPos
				self:play(self:anim("SitDown"))
			elseif self:clipDone() then
				self.stood = false
				self.localPos = self:seatAt()
				self.localFace = self:seatFaceAt()
				self.state = "WATCH"
				self.timer = 0
				self:play(post.idle)
			else
				local a = math.clamp(self.clipT / self.clip.length, 0, 1)
				self.localPos = self.standFrom:Lerp(self:seatAt(), a)
				self.localFace = lerpDir(self.localFace, self:seatFaceAt(), math.min(1, dt * 5))
			end
		else
			self.state = "WATCH"
			self.timer = 0
		end
	end

	self:stepAnim(dt)
	if self.rig then
		if self.boat.spec.id=="RaiderL0" then self:applyRaiderPose() else self.rig:apply(self:worldCF(), self.pose) end
	else
		self.model:PivotTo(self:worldCF())
	end
end

function Pirate:updateCombat(dt)
	local post = self.post
	if not self:targetAlive() then self.target = nil end

	if self.state == "MOVE" then
		if not self.target then
			self.state = "RETURN"
			return
		end
		local slot = self:fireSlot()
		local goal = post.fireV[slot]
		local step = goal - self.localPos
		-- на бегу смотрит по ходу (клип Run — бег вперёд), придя — на цель
		local face = (step.Magnitude > 0.4) and step.Unit or self:faceTarget(post.fireFaceV[slot])
		local arrived = self:moveTo(dt, goal, face)
		self:play(arrived and post.hold or self:anim("Run"))
		if arrived and self.timer > 0.35 then
			self.state = "FIRE"
			self.timer = 0
			self.burstLeft = 0
			self.shotClock = 0.25
		end
		return
	end

	-- FIRE: расширенный сектор, чтобы не «моргать» между FIRE и RETURN на краю
	local hrp = self.target
	local cf = self:postCF()
	local live = hrp and inSector(cf, hrp.Position, post.halfAngle + 25, post.rangeStuds * 1.2)
		and self:hasLOS(cf.Position, hrp)
	if live then
		self.lostFor = 0
		local slot = self:fireSlot()
		self:moveTo(dt, post.fireV[slot], self:faceTarget(post.fireFaceV[slot]))
		self:stepFire(dt)   -- клипом стрельбы/паузы управляет он сам, иначе бы спорили
	else
		self.lostFor += dt
		self:play(post.hold)
		self.burstLeft = 0
		if self.lostFor > LOSE_TARGET then
			self.target = nil
			self.state = "RETURN"
			self.timer = 0
		end
	end
end

-- ═══════════════════════ добыча груза ═══════════════════════
-- Каждый груз — отдельный меш, поэтому обыск идёт по одному месту: сработал промпт
-- → выдали содержимое → меш исчез с палубы. Ресурсы кладём тем же путём, что бочка
-- (BarrelSystem): патроны и монеты идут своими каналами.
local CARGO_RU = {
	Cargo_Crate_A = "ящик", Cargo_Crate_B = "ящик", Cargo_Crate_C = "ящик",
	Cargo_Barrel_A = "бочка", Cargo_Barrel_B = "бочка",
	Cargo_Sacks = "мешки", Cargo_Fuel = "канистры", Cargo_Rope = "бухта троса",
}

local function giveLoot(player, key, amount, atPos)
	if key == "Pirate" then
		if _G.AddPirate then
			_G.AddPirate(player, amount)
		else
			player:SetAttribute("Pirate", (player:GetAttribute("Pirate") or 0) + amount)
		end
		return ("%d Пиратов"):format(amount)
	elseif key == "Ammo" then
		if _G.RefillReserveAmmo then
			_G.RefillReserveAmmo(player)
			return "патроны пополнены"
		end
		key, amount = "Iron_Ingot", 1   -- нечем пополнять — не теряем награду молча
	end
	if _G.AddResourceToInventory then
		_G.AddResourceToInventory(player, key, amount, atPos)
	end
	return ("%d %s"):format(amount, key)
end

local function setupCargo(folder, loot)
	local left = 0
	for _, part in ipairs(folder:GetDescendants()) do
		local entries = part:IsA("BasePart") and loot[part.Name]
		if entries then
			left += 1
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Обыскать"
			prompt.ObjectText = CARGO_RU[part.Name] or "груз"
			prompt.HoldDuration = 0.8
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = part
			-- груз должен ловить промпт даже сквозь ящики рядом, но не толкать игрока
			part.CanCollide = false
			part.CanQuery = true
			prompt.Triggered:Connect(function(plr)
				if not part.Parent then return end
				local pos = part.Position
				local got = {}
				for _, e in ipairs(entries) do
					table.insert(got, giveLoot(plr, e[1], math.random(e[2], e[3]), pos))
				end
				if _G.SendInventory then _G.SendInventory(plr) end
				dbg(("%s обыскал %s: %s"):format(plr.Name, part.Name, table.concat(got, ", ")))
				part:Destroy()
			end)
		end
	end
	return left
end

-- ═══════════════════════ катер ═══════════════════════
local Boat = {}
Boat.__index = Boat

local activeBoats = {}

-- Точки из модели (Pt_*). Пивот маркера — ровно точка, поэтому берём Position.
local function readMarkers(model, post, origin0, scale)
	local used = {}
	local function pt(name)
		if not name then return nil end
		local m = model:FindFirstChild(name, true)
		if not m or not m:IsA("BasePart") then return nil end
		used[m] = true
		return origin0:PointToObjectSpace(m.Position)
	end

	local stand = pt(post.mSpawn)
	if stand then
		if post.patrolV then
			-- маршрут держим относительно точки из модели, размах — авторский
			local d1 = post.patrolV[1] - post.standV
			local d2 = post.patrolV[2] - post.standV
			post.patrolV = { stand + d1, stand + d2 }
		end
		post.standV = stand
	end

	local seat = pt(post.mSeat)
	if seat then
		post.seatV = seat - Vector3.new(0, SEAT_DROP_M * scale, 0)
	end

	local port, stbd = pt(post.mPort), pt(post.mStbd)
	if port then post.fireV[1] = port end
	if stbd then post.fireV[2] = stbd end

	return used
end

function Boat.new(spec, spawnPos, waterY, heading)
	local boatTpl = findBoatTemplate(spec)
	if not boatTpl then
		warnOnce("no_boat_" .. spec.id, ("модель катера (%s) не найдена: ожидаю %s в ReplicatedStorage")
			:format(spec.ru, table.concat(spec.boatNames, " / ")))
		return nil
	end
	local pirateTpl = findCrewTemplate(spec)
	if not pirateTpl then
		warnOnce("no_crew_" .. spec.id, ("модель экипажа (%s) не найдена: ожидаю %s")
			:format(spec.ru, table.concat(spec.crewNames, " / ")))
	end
	local rifleTpl = findTemplate("", spec.weaponNames, "оружие_" .. spec.id)

	local self = setmetatable({}, Boat)
	self.spec = spec

	local folder = Instance.new("Model")
	folder.Name = spec.id == "RaiderL0" and "PirateRaiderBoat" or ((spec.id == "Cargo") and "PirateCargoBoat" or "PiratePatrolBoat")
 folder:SetAttribute("BoatType",spec.id)
 folder:SetAttribute("Hostile",true)
	self.folder = folder

	local src = boatTpl:Clone()
	if src:IsA("BasePart") then
		local wrap = Instance.new("Model")
		wrap.Name = "Boat"
		src.Name = "Hull"
		src.Parent = wrap
		src = wrap
	end
	src.Name = "Boat"
	src.Parent = folder

	local hull = (spec.id == "RaiderL0" and src.PrimaryPart) or src:FindFirstChild("Hull", true) or biggestPart(src)
	if not hull or not hull:IsA("BasePart") then
		warnOnce("no_hull", "в модели катера нет детали Hull")
		folder:Destroy()
		return nil
	end
	folder.PrimaryPart = hull

	-- масштаб импорта берём из габарита корпуса, а не на веру
	local maxDim = math.max(hull.Size.X, hull.Size.Y, hull.Size.Z)
	local scale = maxDim / spec.lenM
	if scale < 0.5 or scale > 12 then scale = DEFAULT_SCALE end
	-- Масштаб импорта должен быть ×3 у ОБОИХ катеров, иначе они не соотносятся ни
	-- между собой, ни с экипажем: R6 остаётся ростом 5 студов независимо от того,
	-- насколько крупным приехал корпус.
	if math.abs(scale - DEFAULT_SCALE) > 0.6 then
		warnOnce("scale_" .. spec.id, ("%s импортирован в масштабе ×%.2f вместо ×%d: корпус %d студов вместо %d. Переимпортируй FBX с World Scale ×3, иначе экипаж будет не по размеру катера")
			:format(spec.ru, scale, DEFAULT_SCALE, math.floor(maxDim), math.floor(spec.lenM * DEFAULT_SCALE)))
	end
	self.scale = scale

	-- то же, что делает FixImported: якоря, коллизии, скрытые маркеры
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			-- корпус твёрдый у всех катеров: рейдер проходил плот насквозь, а должен упереться и толкнуть
			d.CanCollide = (d == hull)
			if d.Name:sub(1, 3) == "Pt_" then
				d.Transparency = 1
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	if hull:IsA("MeshPart") then
		-- Box (по умолчанию) — это кирпич во всю длину катера. Грузовому мало и Hull:
		-- по нему ходит игрок, и выпуклая оболочка съедает палубу.
		pcall(function() hull.CollisionFidelity = spec.fidelity end)
	end

	-- начало координат катера: ватерлиния и диаметральная плоскость
	local origin0 = hull.CFrame * CFrame.new(spec.hullToOrigin * scale)

	-- НОС. Предполагать, что нос лежит по локальной -Z корпуса, нельзя: у
	-- импортированного меша ось может оказаться любой, и тогда катер идёт лагом.
	-- Деталь Front внутри модели показывает нос — доворачиваем систему координат
	-- так, чтобы он совпал с LookVector. Заодно это выправляет и направления
	-- взглядов постов, они заданы в той же системе.
	local bow, how = nil, nil
	local front = src:FindFirstChild(FRONT_MARKER, true)
	if front and front:IsA("BasePart") then
		local d = flat(origin0:PointToObjectSpace(front.Position))
		if d.Magnitude > 0.5 then
			bow, how = d.Unit, "детали Front"
		end
		front:Destroy()
	end
	if not bow then
		-- Front есть не у всех моделей. Огневые точки левого и правого борта дают ту
		-- же информацию: вектор между ними — это траверз, а нос = вверх × траверз.
		local pPort = src:FindFirstChild(spec.posts[1].mPort, true)
		local pStbd = src:FindFirstChild(spec.posts[1].mStbd, true)
		if pPort and pStbd and pPort ~= pStbd then
			local sb = flat(origin0:PointToObjectSpace(pStbd.Position)
				- origin0:PointToObjectSpace(pPort.Position))
			if sb.Magnitude > 0.5 then
				sb = sb.Unit
				bow, how = Vector3.new(sb.Z, 0, -sb.X), "огневым точкам"
			end
		end
	end
	if bow then
		-- ищем поворот R вокруг Y, при котором R * (0,0,-1) == bow
		local yaw = math.atan2(-bow.X, -bow.Z)
		origin0 = origin0 * CFrame.Angles(0, yaw, 0)
		dbg(("нос по %s: доворот %.0f°"):format(how, math.deg(yaw)))
	else
		warnOnce("no_front_" .. spec.id,
			("нос катера (%s) определить нечем — считаю по локальной -Z корпуса"):format(spec.ru))
	end

	-- посты: сперва числа из crew.json, потом — точки из модели, если они есть
	local markerParts = {}
	self.posts = {}
	local fromMarkers = 0
	for _, srcPost in ipairs(spec.posts) do
		local p = {}
		for k, v in pairs(srcPost) do p[k] = v end
		p.standV     = bl(srcPost.stand, scale)
		p.faceV      = bdir(srcPost.face)
		p.fireV      = { bl(srcPost.fire[1], scale), bl(srcPost.fire[2], scale) }
		p.fireFaceV  = { bdir(srcPost.fireFace[1]), bdir(srcPost.fireFace[2]) }
		p.rangeStuds = srcPost.range * scale * RANGE_MULT
		if srcPost.patrol then
			p.patrolV = { bl(srcPost.patrol[1], scale), bl(srcPost.patrol[2], scale) }
		end
		if srcPost.seat then
			p.seatV = bl(srcPost.seat, scale) - Vector3.new(0, SEAT_DROP_M * scale, 0)
			p.seatFaceV = bdir(srcPost.seatFace)
		end
		local used = readMarkers(folder, p, origin0, scale)
		for m in pairs(used) do
			markerParts[m] = true
			fromMarkers += 1
		end
		table.insert(self.posts, p)
	end

	-- прожектор: отдельная деталь, крутится на тумбе
	local light = nil
	for _, n in ipairs(LIGHT_NAMES) do
		light = src:FindFirstChild(n, true)
		if light and light:IsA("BasePart") then break end
		light = nil
	end
	self.light = light
	if light then
		local beam = Instance.new("SpotLight")
		beam.Angle = 42
		beam.Brightness = 4
		beam.Range = 90
		beam.Color = Color3.fromRGB(255, 245, 205)
		beam.Face = Enum.NormalId.Front
		beam.Parent = light
		self.beam = beam
		self.lightRel = origin0:ToObjectSpace(light.CFrame)
	end

	-- маркеры отработали: в мире они больше не нужны
	for m in pairs(markerParts) do m:Destroy() end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:sub(1, 3) == "Pt_" then d:Destroy() end
	end

	-- груз: по промпту на каждое место
	if spec.loot then
		self.cargoLeft = setupCargo(folder, spec.loot)
	end

	-- смещения всех деталей относительно origin запоминаем один раз
	self.parts = {}
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and d ~= light then
			table.insert(self.parts, { part = d, rel = origin0:ToObjectSpace(d.CFrame) })
		end
	end

	local pos = Vector3.new(spawnPos.X, waterY, spawnPos.Z)
	self.originCF = CFrame.lookAt(pos, pos + heading)
	self.waterY = waterY
	self.heading = heading
	self.t = math.random() * 10
	self.age = 0
	self.spin = 0
	self.phase = "APPROACH"
	self.side = (math.random() < 0.5) and 1 or -1
	self.aggro = false
	self.aggroAt = 0
	self.escortFor = 0
	self.orbit = 0

	folder.Parent = Workspace

	-- ЭКИПАЖ. У каждого поста свой морпех (см. MARINES) и своё оружие. Если модели
	-- морпеха нет — встаёт прежний экипаж катера, чтобы катер не вышел пустым.
	self.crew = {}
	for _, post in ipairs(self.posts) do
		local marine = marineFor(spec.id, post.name)
		local tpl = pirateTpl
		local weapon = rifleTpl
		local sound = DEFAULT_SHOT_SOUND

		if marine then
			local found = findTemplate("", { marine }, "морпех_" .. marine)
			if found then
				tpl = found
				local weaponName = MARINE_WEAPON[marine]
				if weaponName then
					sound = WEAPON_SOUND[weaponName] or DEFAULT_SHOT_SOUND
					weapon = findTemplate("", { weaponName }, "оружие_" .. weaponName) or rifleTpl
				end
			else
				warnOnce("no_marine_" .. marine,
					("модель «%s» не найдена в ReplicatedStorage — на пост %s встал прежний экипаж")
						:format(marine, post.name))
			end
		end

		if tpl then
			local ok, pirate = pcall(Pirate.new, self, post, tpl, weapon, sound)
			if ok and pirate then
				pirate.crewName = marine or tpl.Name   -- для сводки в логе
				table.insert(self.crew, pirate)
			else
				warnOnce("crew_fail", "не удалось поставить экипаж на пост " .. post.name .. ": " .. tostring(pirate))
			end
		end
	end

	if spec.id=="RaiderL0" then RaiderCombat.register(self) end
	if DEBUG_ZONES then self:buildZones() end
	self:place(0)
	local roster = {}
	for _, p in ipairs(self.crew) do
		table.insert(roster, ("%s:%s"):format(p.post.name, p.crewName or "?"))
	end
	dbg(("%s: масштаб ×%.2f, точек из модели %d, экипаж %d (%s), груза %d, катер %s"):format(
		spec.ru, scale, fromMarkers, #self.crew,
		#roster > 0 and table.concat(roster, ", ") or "—",
		self.cargoLeft or 0, boatTpl.Name))
	return self
end

-- видимые маркеры постов и секторов (DEBUG_ZONES)
function Boat:buildZones()
	local zones = Instance.new("Folder")
	zones.Name = "Zones"
	zones.Parent = self.folder
	local function marker(name, localCF, size, colour)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Color = colour
		p.Material = Enum.Material.Neon
		p.Transparency = 0.6
		p.Parent = zones
		table.insert(self.parts, { part = p, rel = localCF })
		return p
	end
	for _, post in ipairs(self.posts) do
		local cf = CFrame.lookAt(post.standV, post.standV + post.faceV)
		local watch = marker("Watch_" .. post.name, cf, Vector3.new(1, 0.2, 1), Color3.fromRGB(90, 200, 255))
		watch:SetAttribute("HalfAngleDeg", post.halfAngle)
		watch:SetAttribute("RangeStuds", post.rangeStuds)
		for i = 1, 2 do
			local sign = (i == 1) and 1 or -1
			local edge = cf * CFrame.Angles(0, math.rad(-sign * post.halfAngle), 0)
			marker(("Sector_%s_%d"):format(post.name, i),
				edge * CFrame.new(0, 0, -post.rangeStuds * 0.25),
				Vector3.new(0.3, 0.3, post.rangeStuds * 0.5), Color3.fromRGB(90, 200, 255))
			marker(("Fire_%s_%d"):format(post.name, i),
				CFrame.lookAt(post.fireV[i], post.fireV[i] + post.fireFaceV[i]),
				Vector3.new(2, 0.2, 2), Color3.fromRGB(255, 120, 90))
		end
		if post.seatV then
			marker("Sit_" .. post.name, CFrame.new(post.seatV),
				Vector3.new(2, 0.2, 2), Color3.fromRGB(255, 220, 90))
		end
	end
end

-- Катер «зацепился»: с этого момента он не проходит мимо, а идёт к плоту и висит
-- у борта, пока экипаж жив и видит кого-то (или пока не выйдет ESCORT_MAX).
function Boat:engage(why)
	self.aggroAt = self.age
	if self.aggro then return end
	self.aggro = true
	-- Грузовой не гоняется: он торговец, а не боевая единица. Охранник стреляет, но
	-- сам катер курс не меняет — иначе с него нельзя было бы снять груз.
	if self.spec.hunts then self.phase = "ESCORT" end
	-- Встаём на орбиту с той точки, где уже находимся, и обходим плот в ту сторону,
	-- куда уже идём: иначе первым же манёвром катер разворачивался бы на 180°.
	local raft = raftModel()
	if raft then
		local rel = flat(self.originCF.Position) - flat(raftCenter(raft))
		if rel.Magnitude > 1 then
			self.orbit = math.atan2(rel.Z, rel.X)
			local tang = Vector3.new(-math.sin(self.orbit), 0, math.cos(self.orbit))
			self.side = (self.heading:Dot(tang) >= 0) and 1 or -1
		end
	end
	dbg("катер пошёл на сближение: " .. why)
end

-- кто-то увидел цель → поднимаем всех, но каждый со своей задержкой
function Boat:alert(target, from)
	local raised = false
	for _, p in ipairs(self.crew) do
		if not p.dead and p.state == "WATCH" then
			p.target = target
			p.timer = 0
			p.lostFor = 0
			p.selfSpotted = false   -- поднят по тревоге: идёт по своей задержке реакции
			p:mirrorTo(target)
			-- reveal() тут НЕ вызываем: свою шкалу слежки он ещё не набрал, и бар над
			-- ним должен оставаться шкалой, пока он не разглядит игрока сам
			p.state = "SUSPECT"
			raised = true
		end
	end
	self:engage(from and ("цель заметил пост " .. from.post.name) or "цель обнаружена")
	if raised and from then dbg(("цель заметил пост %s"):format(from.post.name)) end
end

-- по экипажу попали. Стрелка может быть вне любого сектора (сзади, сверху) — всё
-- равно вскидываем всех на ближайшего игрока: по катеру ведут огонь.
function Boat:onAttacked()
	local pos = self.originCF.Position
	local best, bestD = nil, AGGRO_SHOT_RANGE
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hum and hum.Health > 0 then
			local d = (hrp.Position - pos).Magnitude
			if d < bestD then best, bestD = hrp, d end
		end
	end
	if best then
		self:alert(best, nil)
	else
		self:engage("по экипажу стреляют")
	end
end

function Boat:place(dt)
	local origin = self.originCF
 self.moveParts=self.moveParts or {};self.moveFrames=self.moveFrames or {}
 table.clear(self.moveParts);table.clear(self.moveFrames)
 for _,e in ipairs(self.parts) do if e.part.Parent and not e.detached then table.insert(self.moveParts,e.part);table.insert(self.moveFrames,origin*e.rel) end end
 Workspace:BulkMoveTo(self.moveParts,self.moveFrames,Enum.BulkMoveMode.FireCFrameChanged)
 -- метка времени этой позы: клиент (BoatRide) по ней плавно интерполирует ход
 self.folder:SetAttribute("PlaceT",Workspace:GetServerTimeNow())
	if self.light and self.light.Parent then
		self.spin += dt * LIGHT_RPS * math.pi * 2
		self.light.CFrame = origin * self.lightRel * CFrame.Angles(0, self.spin, 0)
		if self.beam then
			local h = Lighting.ClockTime
			self.beam.Enabled = (h < 6.5 or h > 17.5)
		end
	end
end

-- ═══ ОБХОД ОСТРОВОВ ═══
-- Катер рулит только желаемым курсом, самих островов он не «видит» — и заплывал
-- прямо в сушу, как только остров вставал между ним и плотом. След островов
-- (центр + радиус по суше) публикует WorldEventSpawner в _G.IslandPositions —
-- тот же, по которому ResourceSpawner не роняет ресурсы на сушу.
local AVOID_CLEAR = 45    -- запас до берега: корпус, волна, погрешность следа
local AVOID_AHEAD = 220   -- насколько вперёд смотрим по курсу

local function avoidIslands(pos, wantDir)
	local list = _G.IslandPositions
	if not list or #list == 0 then return wantDir end

	for _, isl in ipairs(list) do
		local margin = (isl.radius or 0) + AVOID_CLEAR
		local toC = flat(isl.center - pos)
		local d = toC.Magnitude
		if d < margin then
			-- УЖЕ В ЗАПРЕТНОМ КРУГЕ (заплыл) — строго наружу, никаких компромиссов
			return (d > 1e-3) and (-toC.Unit) or wantDir
		end
		-- курс режет круг впереди? (проекция центра на курс в пределах взгляда,
		-- боковое отклонение меньше запретного радиуса)
		local forward = toC:Dot(wantDir)
		if forward > 0 and forward < math.min(d, AVOID_AHEAD + margin) then
			local lateral = (toC - wantDir * forward).Magnitude
			if lateral < margin then
				-- уводим на касательную к кругу с той стороны, куда уже смещены:
				-- cross.Y >= 0 — центр слева по курсу, значит обходим справа
				local side = (wantDir:Cross(toC).Y >= 0) and -1 or 1
				local tangent = math.asin(math.clamp(margin / d, 0, 1))
				return rotateY(toC.Unit, side * tangent).Unit
			end
		end
	end
	return wantDir
end

-- доворот к нужному курсу с ограничением по скорости поворота
function Boat:steer(wantDir, dt)
	if not wantDir or wantDir.Magnitude < 1e-3 then return end
	wantDir = flat(wantDir)
	if wantDir.Magnitude < 1e-3 then return end
	wantDir = wantDir.Unit
	-- обход островов применяется К ЛЮБОМУ курсу: и погоне, и эскорту, и уходу
	local hull = self.folder and self.folder.PrimaryPart
	if hull then
		wantDir = avoidIslands(hull.Position, wantDir)
	end
	local cur = self.heading
	local ang = math.acos(math.clamp(cur:Dot(wantDir), -1, 1))
	local maxTurn = TURN_RATE * dt
	if ang <= maxTurn then
		self.heading = wantDir
	else
		-- ЗНАК ВАЖЕН: rotateY(v, a) — это поворот на +a вокруг Y, а cross.Y > 0
		-- означает, что цель левее. Со знаком наоборот катер доворачивал длинной
		-- дорогой через 270° и на полном ходу уносился на сотни студов от плота.
		local sign = (cur:Cross(wantDir).Y >= 0) and 1 or -1
		self.heading = rotateY(cur, sign * maxTurn).Unit
	end
end

-- проходим близко, но не впритирку: у большого плота свой габарит
local function passOffset()
	local raftRad = (_G.GetRaftRadius and _G.GetRaftRadius()) or 20
	return math.max(PASS_OFFSET, raftRad + PASS_CLEAR)
end

function Boat:aliveCrew()
	local n = 0
	for _, p in ipairs(self.crew) do
		if not p.dead and not p.fall then n += 1 end
	end
	return n
end

function Boat:update(dt)
	self.age += dt
	self.t += dt

	local raft = raftModel()
	if not raft then return false end
	local center = raftCenter(raft)

	local flatPos = flat(self.originCF.Position)
	local flatCtr = flat(center)
	local toRaft = flatCtr - flatPos
	local dist = toRaft.Magnitude

	-- Курс и скорость плота меряем сами: он то идёт под парусом, то стоит на якоре,
	-- и «висеть у борта» — это держать ЕГО скорость, а не свою.
	if self.lastCtr then
		local v = (flatCtr - self.lastCtr) / math.max(dt, 1e-3)
		self.raftVel = self.raftVel and self.raftVel:Lerp(v, math.min(1, dt * 2)) or v
	end
	self.lastCtr = flatCtr
	-- скорость плота ограничиваем своей: удержать более быстрый плот всё равно нельзя
	local raftVel = self.raftVel or Vector3.zero
	local topSpeed = self.spec.speed
	if raftVel.Magnitude > topSpeed then raftVel = raftVel.Unit * topSpeed end

	-- ── сторона, с которой сейчас противник: по ней кокпитный выбирает борт ──
	self.sideScan = (self.sideScan or 0) - dt
	if self.sideScan <= 0 then
		self.sideScan = 0.35
		local ref = nil
		for _, p in ipairs(self.crew) do
			if not p.dead and p.target and p.target.Parent then
				ref = p.target.Position
				break
			end
		end
		ref = ref or center       -- цели нет — ориентируемся на сам плот
		local relX = self.originCF:PointToObjectSpace(ref).X
		if math.abs(relX) > 8 then self.threatSide = relX end -- мёртвая зона от дрожания
	end

	-- ── экипаж выбит: катер брошен ──
	if self.phase ~= "DERELICT" and #self.crew > 0 and self:aliveCrew() == 0 then
		self.phase = "DERELICT"
		self.derelictAt = self.age
		self.aggro = false
		self.driftSpeed = topSpeed
		dbg(("экипаж выбит — катер брошен, затонет через %d с"):format(DERELICT_SINK))

		-- ⚠️ ЯЩИК С ОРУЖИЕМ ВЫПАДАЕТ И С КАТЕРА, А НЕ ТОЛЬКО С НОЧНОГО КОРАБЛЯ.
		-- Ночной ящик рождается из УНИЧТОЖЕННОГО корабля волны, а корабли идут
		-- лишь с третьей волновой ночи — до неё игроку не с чего получить пушки
		-- вовсе. Грузовой катер приходит раньше и как раз возит груз, поэтому
		-- ящик отдаёт он. Номер ночи берём текущим днём: RewardCrate по нему
		-- решает, насколько щедрым быть.
		-- ⚠️ ОДИН ЯЩИК НА КАТЕР: метка на папке катера, второй раз не выдаём
		if _G.EjectRewardCrate and not (self.folder and self.folder:GetAttribute("CrateGiven")) then
			if self.folder then self.folder:SetAttribute("CrateGiven", true) end
			local dc = ReplicatedStorage:FindFirstChild("DayCount")
			-- откуда вылетает: из самого катера, а не из центра плота
			local from = self.originCF and self.originCF.Position
			if from then
				pcall(_G.EjectRewardCrate, from, (dc and dc.Value) or 1, nil)
			end
		end
	end

	-- ── стоит ли ещё держаться за плот ──
	if self.aggro then
		local seeing = false
		for _, p in ipairs(self.crew) do
			if not p.dead and p.target then
				seeing = true
				break
			end
		end
		if seeing then self.aggroAt = self.age end
		local why = nil
		if self.age - self.aggroAt > AGGRO_FORGET then
			why = "цель потеряна"
		elseif self.escortFor > ESCORT_MAX then
			why = "отвязался по времени"
		end
		if why then
			self.aggro = false
			if self.spec.hunts then self.phase = "LEAVE" end
			dbg("катер уходит: " .. why)
		end
	end
	-- ЗДЕСЬ БЫЛА тревога «игрок ближе 90 студов — замечаем без секторов». Она
	-- обходила и слежку, и проверку видимости: катер курсирует в ~70 студах, то есть
	-- срабатывала сразу и всегда. Игрока замечают ТОЛЬКО через сектор поста, прямую
	-- видимость и заполнение шкалы слежки (либо когда по экипажу открыли огонь).

	local speed = topSpeed
	if self.phase == "DERELICT" then
		-- Гасит ход и стоит: по нему можно полазить и забрать припасы. Корпус остаётся
		-- твёрдым, руля никто не держит — курс не меняется.
		self.driftSpeed = math.max(0, (self.driftSpeed or topSpeed) - 3 * dt)
		speed = self.driftSpeed

	elseif self.phase == "MOORED" then
		-- ГРУЗОВОЙ ПОДОШЁЛ И ЗАГЛУШИЛ МОТОР.
		-- ⚠️ ДВА РАЗНЫХ ПОВЕДЕНИЯ, И ГРАНИЦА МЕЖДУ НИМИ — ЖИВОЙ ЭКИПАЖ.
		-- Пока охрана жива, катер держится рядом с плотом: плот дрейфует, и
		-- «встал намертво» означало, что через полминуты он оставался за кормой,
		-- а его пират переставал доставать до игрока. Экипаж выбит — катер
		-- замирает по-настоящему: только тогда по палубе можно ходить, движущаяся
		-- заякоренная палуба игрока просто стряхнёт за борт.
		if self:aliveCrew() > 0 then
			local off = self.moorOffset
			if not off then
				off = flatPos - flatCtr          -- запомнили место относительно плота
				self.moorOffset = off
			end
			local d = (flatCtr + off) - flatPos
			if d.Magnitude > 2 then
				self:steer(d, dt)
				speed = math.min(topSpeed, d.Magnitude * 0.9)
			else
				speed = 0
			end
			self.driftSpeed = speed
		else
			self.driftSpeed = math.max(0, (self.driftSpeed or topSpeed) - 4 * dt)
			speed = self.driftSpeed
		end
		if self.age - (self.mooredAt or self.age) > (self.spec.linger or 240) then
			self.phase = "LEAVE"
			dbg("грузовой снялся и уходит")
		end

	elseif self.phase == "ESCORT" then
		-- КУРСИРУЕТ ВОКРУГ ПЛОТА: станция ползёт по окружности радиуса passOffset,
		-- а сама окружность едет вместе с плотом. Катер всё время держит плот на
		-- траверзе — то есть бортом, как раз под секторы экипажа. Направление обхода
		-- выбрано при сближении, чтобы не разворачиваться на 180° сразу по приходе.
		self.escortFor += dt
		local off = passOffset()
		local orbitSpeed = self.spec.orbit
		self.orbit += (orbitSpeed / math.max(off, 1)) * self.side * dt
		local radial  = Vector3.new(math.cos(self.orbit), 0, math.sin(self.orbit))
		local tangent = Vector3.new(-math.sin(self.orbit), 0, math.cos(self.orbit)) * self.side
		local station = flatCtr + radial * off
		local d = station - flatPos
		local gap = d.Magnitude
		-- курс станции = обход по кругу + снос вместе с плотом
		local cruise = tangent * orbitSpeed + raftVel
		local base = (cruise.Magnitude > 0.5) and cruise.Unit or tangent
		-- Чем ближе к станции, тем больше курс задаёт обход, а не «лечу в точку».
		-- Без этого катер влетал в станцию поперёк и уходил в перелёт на сотню студов.
		local w = math.clamp(gap / 60, 0, 1)
		local wantDir = (gap > 1) and (d.Unit * w + base * (1 - w)) or base
		if wantDir.Magnitude < 0.05 then wantDir = base end
		self:steer(wantDir, dt)
		speed = math.clamp(cruise.Magnitude + gap * 0.4, 2, self.spec.chase)

	elseif self.phase == "APPROACH" then
		-- Цель одна: дойти до плота. Курс пересчитывается каждый кадр, поэтому плот
		-- не «убежит» — катер ведёт на упреждение, пока не окажется рядом.
		local off = passOffset()
		local across = rotateY(raftFront(raft), math.pi / 2)
		self:steer((flatCtr + across * (off * self.side)) - flatPos, dt)
		-- Приход засчитываем ВПЛОТНУЮ. Прежняя проверка «dist < off*3 и нос уже в
		-- сторону» глушила мотор за пару сотен студов — со стороны катер «боялся»
		-- плота. Теперь грузовой встаёт бортом у самого плота, а патруль
		-- засчитывает проход только реально рядом.
		local raftRad = (_G.GetRaftRadius and _G.GetRaftRadius()) or 20
		if dist < raftRad + HULL_HALF + 8
			or (dist < off * 1.3 and toRaft.Unit:Dot(self.heading) < -0.2) then
			if self.spec.hunts then
				self.phase = "LEAVE"
			else
				self.phase = "MOORED"   -- грузовой глушит мотор и встаёт под обыск
				self.mooredAt = self.age
				self.driftSpeed = speed
				dbg("грузовой подошёл и заглушил мотор")
			end
		end

	else -- LEAVE: идёт прямо и уходит за горизонт
		self:steer(self.heading, dt)
	end

	-- ═══ ТАРАН ПЛОТА ═══
	-- Корпус вошёл в габарит плота на сходящемся курсе → плоту урон по силе
	-- удара (скорость × множитель), деревянный «бум», и мотор глохнет: грузовой
	-- остаётся швартованным, боевой сбрасывает ход и доворачивает своим ИИ.
	if speed > 3
		and (self.phase == "APPROACH" or self.phase == "ESCORT" or self.phase == "LEAVE") then
		local raftRad = (_G.GetRaftRadius and _G.GetRaftRadius()) or 20
		if dist < raftRad + HULL_HALF and dist > 1
			and toRaft.Unit:Dot(self.heading) > 0.25
			and self.age - (self.lastImpact or -1e9) > IMPACT_COOLDOWN then
			self.lastImpact = self.age
			local dmg = math.max(3, math.floor(speed * IMPACT_DMG_PER_SPEED))
			if _G.DamageRaft then _G.DamageRaft(dmg) end
			pcall(function()
				require(game:GetService("ReplicatedStorage"):WaitForChild("CombatSounds", 2))
					.play("hit", self.originCF.Position)
			end)
			dbg(("таран плота: скорость %.1f студ/с → урон %d"):format(speed, dmg))
			if self.spec.hunts then
				speed = 2
			else
				self.phase = "MOORED"
				self.mooredAt = self.age
				self.driftSpeed = 0
				speed = 0
			end
		end
	end

	local floodDepth,floodRoll,floodPitch,speedFactor=RaiderCombat.flood(self,dt)
 speed*=speedFactor
 self.currentSpeed=speed
 local newPos = flatPos + self.heading * (speed * dt)

	-- волна: вертикальная качка, крен и небольшой дифферент — чисто визуально
	local heave = math.sin(self.t * 1.15) * 0.9 + math.sin(self.t * 0.47) * 0.5
	local roll  = math.rad(math.sin(self.t * 0.83) * 3.2)
	local pitch = math.rad(math.sin(self.t * 1.31) * 1.4)

	-- брошенный катер: постояв DERELICT_SINK секунд, кренится и уходит под воду
	local sunk = 0
	if self.phase == "DERELICT" then
		local t = self.age - (self.derelictAt or self.age) - DERELICT_SINK
		if t > 0 then
			local k = math.min(t / SINK_TIME, 1)
			sunk = k * SINK_DEPTH
			roll += math.rad(22) * k
			pitch += math.rad(9) * k
		end
	end

	local p = Vector3.new(newPos.X, self.waterY + heave - sunk - floodDepth, newPos.Z)
	self.originCF = CFrame.lookAt(p, p + self.heading) * CFrame.Angles(pitch+floodPitch, 0, roll+floodRoll)
	if floodDepth>24 then return false end

	self:place(dt)
	for _, pirate in ipairs(self.crew) do
		pirate:update(dt)
	end

	-- Брошенный катер живёт по своему таймеру: ни расстояние до плота, ни общая
	-- страховка его не трогают — иначе он мог бы исчезнуть под игроком, который
	-- пришёл забирать припасы.
	if self.phase == "DERELICT" then
		return sunk < SINK_DEPTH
	end
	-- Игрок стоит на палубе (обыскивает груз) — катер под ним не исчезает, чем бы
	-- ни закончилось дело с дистанцией до плота.
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - self.originCF.Position).Magnitude < 60 then
			return true
		end
	end
	-- Остальные убираем, только когда катер УЖЕ уходит: пока он идёт к плоту или
	-- висит у борта, таймеры его съедать не должны.
	if self.age > RUN_TIMEOUT then return false end
	if self.phase == "LEAVE" and dist > DESPAWN_DIST then return false end
	if not self.aggro and dist > DESPAWN_DIST * 1.6 then return false end
	return true
end

function Boat:destroy()
	self.folder:Destroy()
end

-- ═══════════════════════ спавн ═══════════════════════
-- opts.test — режим кнопки: катер выходит РОВНО ПЕРЕД НОСОМ плота и близко, чтобы
-- экипаж было видно сразу, а не через полминуты хода с горизонта.
local function countOfType(spec)
	local n = 0
	for _, b in ipairs(activeBoats) do
		if b.spec == spec then n += 1 end
	end
	return n
end

local function spawnBoat(spec, opts)
	opts = opts or {}
	local raft = raftModel()
	if not raft then return nil, "плот ещё не готов" end
	if countOfType(spec) >= MAX_ACTIVE then
		if not opts.test then return nil, spec.ru .. " уже в море" end
		-- по кнопке всегда должен приходить НОВЫЙ катер, иначе второй тест подряд
		-- молча ничего не делает
		for i = #activeBoats, 1, -1 do
			if activeBoats[i].spec == spec then
				activeBoats[i]:destroy()
				table.remove(activeBoats, i)
			end
		end
	end

	local dist = opts.test and TEST_SPAWN_DIST or SPAWN_DIST
	local center = raftCenter(raft)
	-- тест — строго по носу плота; штатный спавн — в случайной точке переднего сектора
	local dir = opts.test and raftFront(raft)
		or rotateY(raftFront(raft), (math.random() * 2 - 1) * FRONT_ARC)

	-- спавним над чистой водой (мимо островов), как остальные морские события
	local spawnXZ = center + dir * dist
	local ok, WaterSpawn = pcall(function()
		return require(ReplicatedStorage:WaitForChild("WaterSpawn", 3))
	end)
	if ok and WaterSpawn then
		local p = WaterSpawn.pick(center, dir, dist, center.Y + 90, { raft })
		if p then spawnXZ = p end
	end

	local waterY = waterSurfaceAt(spawnXZ.X, spawnXZ.Z, center.Y, { raft })
	local heading = flat(center - spawnXZ)
	heading = (heading.Magnitude > 1e-3) and heading.Unit or Vector3.new(0, 0, -1)

	local boat = Boat.new(spec, spawnXZ, waterY, heading)
	if not boat then return nil, "нет модели катера (" .. spec.ru .. ")" end
	table.insert(activeBoats, boat)
	dbg(("%s вышел в %d студах %s"):format(spec.ru, dist,
		opts.test and "по носу (тест)" or "от плота"))
	return boat
end

-- кнопки «(тест)» в настройках
local function patrolSpec()
 return findBoatTemplate(TYPES.RaiderL0) and TYPES.RaiderL0 or TYPES.Patrol
end
_G.SpawnPirateRaiderL0 = function(opts)
 local boat,why=spawnBoat(TYPES.RaiderL0,opts)
 return boat~=nil,why
end
_G.SpawnPatrolBoat = function(opts)
 local boat, why = spawnBoat(patrolSpec(), opts)
	return boat ~= nil, why
end
_G.SpawnCargoBoat = function(opts)
	local boat, why = spawnBoat(TYPES.Cargo, opts)
	return boat ~= nil, why
end

-- 0→1 по ходу дня (ClockTime 6→18), nil ночью. Та же формула, что у WaveDirector:
-- расписание катеров и время подъёма тумана должны считаться одинаково.
local function dayProgress()
	local t = Lighting.ClockTime
	if t >= 6 and t < 18 then return (t - 6) / 12 end
	return nil
end

-- РАСПИСАНИЕ: раз в двое суток, в 40% дня. Привязка к номеру дня, а не к таймеру,
-- нужна, чтобы первая встреча случилась гарантированно в первый же день и до
-- тумана, а не «когда-нибудь через 2-8 минут после старта сервера».
task.spawn(function()
	local dayValue = ReplicatedStorage:WaitForChild("DayCount", 20)
	if not dayValue then
		warnOnce("no_daycount", "ReplicatedStorage.DayCount не найден (DayNightCircle не загружен?) — расписание катеров работать не будет")
		return
	end
	local lastDay = 0
	while true do
		task.wait(2)
		local day = dayValue.Value
		local p = dayProgress()
		if p and day ~= lastDay and day >= SPAWN_FIRST_DAY
			and (day - SPAWN_FIRST_DAY) % SPAWN_EVERY_DAYS == 0
			and p >= SPAWN_AT_DAY_FRACTION and raftModel() then
			lastDay = day   -- попытка на этот день засчитана в любом случае
			-- три пирата — только с шестого дня; до него море пустует одиночками
			local spec = TYPES.Cargo
			if day >= PATROL_FROM_DAY and math.random() < PATROL_CHANCE then
				spec = patrolSpec()
			end
			local boat, why = spawnBoat(spec)
			dbg(("расписание: день %d, %.0f%% дня → %s%s"):format(
				day, p * 100, spec.ru, boat and "" or (" не вышел (" .. tostring(why) .. ")")))
		end
	end
end)

RunService.Heartbeat:Connect(function(dt)
	for i = #activeBoats, 1, -1 do
		local boat = activeBoats[i]
		local ok, alive = pcall(boat.update, boat, math.min(dt, 0.1))
		if not ok then
			warnOnce("update_err", "ошибка хода катера: " .. tostring(alive))
			alive = false
		end
		if not alive then
			boat:destroy()
			table.remove(activeBoats, i)
			dbg("катер ушёл")
		end
	end
end)

-- РЕАКЦИЯ ЭКИПАЖА НА ВНЕШНЕЕ СОБЫТИЕ (сейчас — огнемёт).
-- Экипаж катера анимируется своим проигрывателем, а не атрибутами Clip, как
-- гарнизон острова: чтобы огнемёт мог заставить их шарахнуться, отдаём наружу
-- один вход. Клип берётся из тех же PirateCrewClips, поэтому имена общие.
_G.PirateBoatReact = function(model, clipName, loopLike)
	if typeof(model) ~= "Instance" or typeof(clipName) ~= "string" then return false end
	for _, boat in ipairs(activeBoats) do
		for _, pirate in ipairs(boat.crew or {}) do
			if pirate.model == model then
				if pirate.dead then return false end
				-- держим клип за собой на его длину: лупы (горение) держим чуть
				-- дольше, чем период перевыдачи, чтобы не было провалов в idle
				local clip = CLIPS and CLIPS[clipName]
				local hold = clip and (clip.loop and 0.9 or clip.length) or 1
				pirate.reactUntil = os.clock() + hold
				pirate:play(clipName, 0.1, true)
				return true
			end
		end
	end
	return false
end

-- ПРЫЖОК ЗА БОРТ.
-- Горящему на катере бежать некуда — воды вокруг сколько угодно, но она за
-- бортом. Он сигает в море сам: снимаем его с довольствия катера (иначе тот
-- продолжит ставить модель на палубу каждый кадр), отдаём тело физике и толкаем
-- по дуге в сторону от борта. Дальше им занимается SwimmingPirate.
_G.PirateBoatOverboard = function(model)
	if typeof(model) ~= "Instance" then return false end
	for _, boat in ipairs(activeBoats) do
		for i, pirate in ipairs(boat.crew or {}) do
			if pirate.model == model then
				if pirate.dead then return false end
				-- Из экипажа он выходит, а значит Pirate:update (и с ним слежка) больше
				-- не крутится: переводим бар в режим здоровья прямо сейчас, иначе он
				-- застынет на шкале слежки навсегда.
				pirate:reveal()
				table.remove(boat.crew, i)     -- катер больше им не управляет

				local hum = model:FindFirstChildWhichIsA("Humanoid", true)
				local hrp = (hum and hum.RootPart) or model:FindFirstChild("HumanoidRootPart", true)
				if not (hum and hrp) then return false end

				-- Прочь от катера: наружу по борту и вверх. Сторону берём по знаку
				-- его места относительно оси корпуса — так он сигает через
				-- ближний борт, а не сквозь надстройку.
				local relX = boat.originCF and boat.originCF:PointToObjectSpace(hrp.Position).X or 1
				local away = (boat.originCF and boat.originCF.RightVector or hrp.CFrame.RightVector)
					* ((relX >= 0) and 1 or -1)

				-- пометка для клиентского проигрывателя поз: он анимирует одиночек
				-- вне острова только по ней (см. PirateIslandAnim)
				model:SetAttribute("CrewAnim", true)
				model:SetAttribute("Clip", "Fire_Shake")
				model:SetAttribute("ClipT", Workspace:GetServerTimeNow())

				model.Parent = Workspace
				for _, d in ipairs(model:GetDescendants()) do
					-- парт HP-борда заякорен намеренно: его ставит клиент над головой,
					-- сорванный с якоря он просто улетит вместе с прыжком
					if d:IsA("BasePart") and d.Name ~= "PirateHP" then
						d.Anchored = false
						d.CanCollide = (d == hrp)
					end
				end
				hum.PlatformStand = false
				hrp.AssemblyLinearVelocity = away * 26 + Vector3.new(0, 34, 0)

				if _G.SwimBoarderFrom then
					task.defer(_G.SwimBoarderFrom, model)
				end
				dbg("горящий охранник прыгнул за борт")
				return true
			end
		end
	end
	return false
end

print("[Патруль] PiratePatrolBoat готов")
