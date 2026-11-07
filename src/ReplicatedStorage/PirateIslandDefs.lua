--[[
	ПИРАТСКИЙ ОСТРОВ — состав населения.

	Всё, что зависит от дизайна (кто где стоит, чем вооружён, какое лицо носит),
	собрано здесь. Логика расстановки — в PirateIsland.server.lua.

	Точки берутся из САМОЙ МОДЕЛИ: маркеры Pt_* приезжают внутри острова, поэтому
	где бы он ни всплыл, места спавна уже на своих местах (см. README острова).
	  • Pt_<пост>   — 14 постов гарнизона
	  • Pt_Cap_*    — 5 пленных
	  • Pt_Cow_1, Pt_Hen_1…3 — животные
]]

local PirateIslandDefs = {}

PirateIslandDefs.ISLAND_NAME = "PirateIsland_SCENE"
PirateIslandDefs.MARKER_PREFIX = "pt_"
PirateIslandDefs.ENEMIES_FOLDER = "Enemies"   -- имя ждёт IslandClearSystem

-- ── ГАРНИЗОН ──
-- Пост (имя маркера без Pt_) → модель пирата. Восемь типов на четырнадцать постов:
-- офицеры по одному, рядовые повторяются.
PirateIslandDefs.POST_CREW = {
	Captain       = "Pirate_Captain",     -- у флага
	Quarter       = "Pirate_Quarter",     -- обход костра
	Cook          = "Pirate_Deckhand",    -- мешает в котле
	Fire_Sit      = "Pirate_Powder",
	Table         = "Pirate_Swab",
	Smoker        = "Pirate_Cutthroat",   -- точит клинок
	Crop_Tender   = "Pirate_Deckhand",    -- работяга на плантации
	Crop_Still    = "Pirate_Powder",
	Crop_Guard    = "Pirate_Cutthroat",
	Gate          = "Pirate_Bosun",       -- ворота
	Jetty         = "Pirate_Swab",        -- причал
	Tower_Landing = "Pirate_Gunner",      -- вышка у высадки
	Tower_North   = "Pirate_Gunner",      -- северная вышка
	Roamer        = "Pirate_Cutthroat",
}

-- Оружие и урон по типу. «Сабля сильная / выше среднего / слабая» из ТЗ — это
-- ровно поле damage; kind нужен, чтобы отличить ближний бой от стрельбы.
PirateIslandDefs.CREW = {
	Pirate_Captain   = { kind = "melee",  weapon = "Sabre", damage = 35, ru = "капитан" },
	Pirate_Quarter   = { kind = "melee",  weapon = "Sabre", damage = 28, ru = "квартирмейстер" },
	Pirate_Cutthroat = { kind = "melee",  weapon = "Sabre", damage = 20, ru = "головорез" },
	Pirate_Deckhand  = { kind = "melee",  weapon = "Sabre", damage = 10, ru = "палубный" },
	Pirate_Powder    = { kind = "melee",  weapon = "Sabre", damage = 10, ru = "пороховой" },
	Pirate_Gunner    = { kind = "ranged", weapon = "Revolver", damage = 15, ru = "канонир" },
	Pirate_Bosun     = { kind = "ranged", weapon = "Revolver", damage = 15, ru = "боцман" },
	Pirate_Swab      = { kind = "ranged", weapon = "Revolver", damage = 15, ru = "юнга" },
}

-- ── ПЛЕННЫЕ: ОДНА СЕМЬЯ ЦЕЛИКОМ ──
-- В клетке сидит СЕМЬЯ, а не случайные люди: отец, мать и ребёнок. Семья
-- выбирается при спавне острова одна из трёх — так пленные каждый раз разные, но
-- всегда родня друг другу.
PirateIslandDefs.FAMILIES = {
	{ id = "Farmer", ru = "фермеры" },
	{ id = "Fisher", ru = "рыбаки" },
	{ id = "Town",   ru = "горожане" },
}

-- Роль → префикс модели (Prisoner_<семья>_<роль>) и набор лиц.
PirateIslandDefs.FAMILY_ROLES = {
	{ role = "Father", face = "dad" },
	{ role = "Mother", face = "mom" },
	{ role = "Child",  face = "kid" },
}

-- Точки Pt_Cap_* в порядке заселения: сначала большая клетка, потом малая и столб.
-- Семья из трёх человек занимает первые три; лишние точки остаются пустыми — это
-- нормально, лучше пустой угол, чем чужой человек в семейной клетке.
PirateIslandDefs.PRISONER_POINTS = { "Cap_A", "Cap_B", "Cap_C", "Cap_D", "Cap_Post" }

-- ЛИЦА ПО НАСТРОЕНИЮ. Ключ — кто (мама/папа/ребёнок), дальше три состояния из ТЗ:
--   sad      — в плену
--   surprise — освобождение
--   happy    — выходят из клетки
PirateIslandDefs.FACES = {
	mom = {
		sad      = "rbxassetid://73018486991401",
		surprise = "rbxassetid://110871404755841",
		happy    = "rbxassetid://116096193265667",
	},
	dad = {
		sad      = "rbxassetid://127963088624695",
		surprise = "rbxassetid://109449149811540",
		happy    = "rbxassetid://89457811123003",
	},
	kid = {
		sad      = "rbxassetid://125476039903025",
		surprise = "rbxassetid://82094486633423",
		happy    = "rbxassetid://89122983273187",
	},
}

-- ── ЖИВОТНЫЕ ──
-- ⚠️ НОВЫЕ РИГИ (переделка): модели «Cow» и «Chicken» — семь/шесть отдельных
-- MeshPart на Motor6D, как штатный R6, БЕЗ костей и скиннинга. Собирают их
-- CowRig / ChickenRig при спавне, клипы играют CowAnimator / ChickenAnimator
-- прямо в Motor6D.Transform (публикация не нужна). Старая пара скинованных
-- мешей с AnimalClips выведена из игры вместе со всей её ориентационной
-- эквилибристикой (StandCF / NoseFlip): эти стоят ровно и смотрят по -Z.
-- mustHave — деталь-паспорт: в ReplicatedStorage может валяться и СТАРАЯ модель
-- с тем же именем, шаблон опознаём по детали, которая есть только у новой.
PirateIslandDefs.ANIMALS = {
	Cow_1 = { model = "Cow", rig = "Cow", mustHave = "Torso", graze = 5.5 * 3,
		hp = 30, ru = "КОРОВА", barUp = 3.4 },   -- было 60: владелец просил бить корову вдвое больнее — любой урон теперь весит вдвое
	Hen_1 = { model = "Chicken", rig = "Chicken", mustHave = "chicken_torso",
		graze = 6.5 * 3, hp = 12, ru = "КУРИЦА", barUp = 2.2 },
	Hen_2 = { model = "Chicken", rig = "Chicken", mustHave = "chicken_torso",
		graze = 6.5 * 3, hp = 12, ru = "КУРИЦА", barUp = 2.2 },
	Hen_3 = { model = "Chicken", rig = "Chicken", mustHave = "chicken_torso",
		graze = 6.5 * 3, hp = 12, ru = "КУРИЦА", barUp = 2.2 },
}

-- Начальники гарнизона: над ними звезда, пока они целы (см. attachBossStar) —
-- игрок с порога видит, кто на острове главный.
PirateIslandDefs.BOSS = { Pirate_Captain = true, Pirate_Quarter = true }

-- ⚠️ ОСТРОВА, КОТОРЫЕ ВЕДЁТ ЭТОТ ИИ. Раньше имя было одно (ISLAND_NAME), и
-- гарнизон второго острова просто не двигался: боевой скрипт и клиентский
-- проигрыватель поз искали строго «PirateIsland_SCENE». Добавляешь остров с
-- гарнизоном — добавь сюда имя его модели.
PirateIslandDefs.ISLAND_NAMES = {
	[PirateIslandDefs.ISLAND_NAME] = true,
	TerraceIsle_SCENE = true,
	-- стартовый остров: врагов нет, но корова там пасётся и её надо анимировать
	StartIsle_SCENE = true,
	-- верфь и малый остров: гарнизон им расставляет IslandCrews.server.lua
	ShipIsle_SCENE  = true,
	SmallIsle_SCENE = true,
	-- забытый кратер: сторожа ставит IslandCrews
	Crater_Island = true, Crater = true, Forgotten_Crater_Island = true,
}

-- ⚠️ ОСТРОВ УЗНАЁМ ПО СОДЕРЖИМОМУ, А НЕ ПО ИМЕНИ В СПИСКЕ.
-- Список выше — исторический, и он УЖЕ дважды подводил: населения на острове
-- прибавлялось, а строчку сюда дописать забывали. На верфи и малом острове
-- IslandCrews расставлял полноценный гарнизон, но ИИ и аниматор обходили
-- острова по этому списку — пираты стояли столбами и не реагировали ни на что,
-- ровно как до того стояла корова стартового острова.
-- Признак настоящий и простой: у острова есть папка с теми, кого надо водить.
-- Те же папки перечисляет клиентский аниматор, и по папке Enemies острова
-- регистрируют у себя IslandClearSystem и MapSystem — то есть это уже принятый
-- в проекте способ опознать остров. Имя оставлено как запасной путь: папку
-- могут завести позже, чем случится первый обход.
local CREW_FOLDERS = { "Enemies", "Prisoners", "Animals", "Rebels" }

function PirateIslandDefs.isCrewIsland(inst)
	if not (inst and inst:IsA("Model")) then return false end
	if PirateIslandDefs.ISLAND_NAMES[inst.Name] then return true end
	for _, folder in ipairs(CREW_FOLDERS) do
		if inst:FindFirstChild(folder) then return true end
	end
	return false
end

-- ── АНИМАЦИИ ──
-- ⚠️ ЭТО ИМЕНА КЛИПОВ ИЗ ServerStorage.PirateCrewClips, А НЕ ID АССЕТОВ.
-- Они играются напрямую через Motor6D.Transform (см. ServerStorage.CrewClips), и
-- публиковать их не нужно — ровно поэтому анимации экипажа катеров работают в
-- неопубликованном плейсе, а стандартные R6 по AnimationId там молча не грузились.
PirateIslandDefs.ANIM = {
	-- run у сабельника — SabreChase: беговой цикл MeleeRun с занесённой саблей
	-- (собирается в хвосте PirateCrewClips; там же его _Lean-собрат)
	melee  = { idle = "MeleeIdle",  walk = "MeleeWalk",  run = "SabreChase", attack = "SabreSwing" },
	ranged = { idle = "PistolIdle", walk = "PistolWalk", run = "PistolWalk", attack = "RevolverShoot" },
}

-- Чем занят пират НА СВОЁМ ПОСТУ, пока никого не видит. Нет записи — играет
-- обычный простой своего оружия.
PirateIslandDefs.POST_IDLE = {
	Captain       = "OfficerIdle",
	Quarter       = "Smoke",
	Cook          = "CookStir",
	Fire_Sit      = "SitFire",
	Table         = "Drink",
	Smoker        = "Whetstone",
	Crop_Tender   = "WorkKneel",
	Crop_Still    = "WorkKneel",
	Gate          = "LeanPost",
	Jetty         = "LeanCrate",
	Tower_Landing = "Binoculars",
	Tower_North   = "Scan",
	Roamer        = "Stretch",
}

-- ── ОБХОД ПОСТА ──
-- Пираты этих постов не стоят столбами, а прохаживаются вокруг своей точки:
-- значение — радиус обхода в студах. Дошёл до случайной точки — постоял со
-- своим пост-идлом, пошёл к следующей. Остальные (кок у котла, капитан,
-- вышки...) несут службу на месте. Слух, шкала подозрения и бой обход не
-- трогают: любой сигнал снимает пирата с прогулки штатными ветками ИИ.
PirateIslandDefs.POST_WANDER = {
	Roamer     = 26,   -- обходчик: самый широкий круг
	Crop_Guard = 12,   -- патруль грядок
	Jetty      = 10,   -- прохаживается по пристани
	Gate       = 7,    -- топчется у ворот
	Quarter    = 9,    -- квартирмейстер с трубкой прогуливается у штаба
}

-- Пленные: связанные руки — это поза покоя, а не наложение, поэтому все три клипа
-- построены на ней и ни один не берёт пиратский простой.
PirateIslandDefs.PRISONER_ANIM = {
	idle     = "Bound",
	struggle = "Struggle",
	freed    = "Freed",
}

-- ── АНИМАЦИИ ЖИВОТНЫХ ──
-- Id-ассетов нет намеренно: в неопубликованном плейсе они не грузятся
-- (serverplaceid=0). Клипы лежат таблицами в ReplicatedStorage (CowClips и
-- Clips внутри ChickenAnimator) и играются напрямую в Motor6D.Transform.
-- Интеллект (AnimalLife) оперирует АБСТРАКТНЫМИ состояниями Idle/Walk/Run/Eat/
-- React, а в конкретный клип рига их переводит карта clips ниже — у коровы и
-- курицы наборы разные.

-- ── ПОВЕДЕНИЕ ЖИВОТНЫХ ── (числа из ТЗ острова, метры переведены в студы ×3)
PirateIslandDefs.ANIMAL_LIFE = {
	Cow = {
		-- скорость под темп клипов ходьбы, а не «сколько успеет»: корова
		-- на 14 студах в секунду скользила, как на коньках
		walkSpeed = 2, runSpeed = 6.5,
		scare = 3 * 3,        -- ближе этого пугается (реакция React)
		flee  = 9 * 3,        -- на сколько отбегает, если игрок не отошёл
		eatMin = 4, eatMax = 8,      -- сколько пасётся на одном месте
		idleMin = 1.5, idleMax = 3,
		-- ShockRun не-луповый и по задумке кончается ПЕРВОЙ позой Run — испуг
		-- переходит в галоп без шва
		clips = { Idle = "IdleGraze", Eat = "IdleGraze", Walk = "Walk",
			Run = "Run", React = "ShockRun" },
		reactLen = 1.40,      -- длина ShockRun: на неё встаёт таймер испуга
		-- КОРОВА НЕ УБЕГАЕТ — БОДАЕТ: после испуга разгоняется прямо в игрока и
		-- бьёт рогами (рывок ShockRun в момент удара). Убегают только куры.
		charge = true,
		chargeSpeed = 9,      -- разгон быстрее выпасного галопа
		hitDamage = 10,
		hitRange = 3.2,       -- дистанция удара рогами
		chargeTime = 6,       -- не догнала за столько секунд — остыла
		-- ⚠️ МЯСО — ГЛАВНОЕ, ЧТО ПАДАЕТ С КОРОВЫ.
		-- Раньше падала одна шкура, и охота ничего не давала: Cow_Hide в
		-- InventoryManager.RESOURCE_NAMES не значится, инвентарь её молча
		-- выбрасывает. Meat зарегистрирован везде — от инвентаря до мангала, —
		-- и на нём держится квест «пожарь мясо».
		drops = { Meat = 2, Cow_Hide = 1 },   -- что падает с туши
	},
	-- ОВЦА ФЕРМЫ: живёт не на острове, а в модели фермы (FarmSystem ведёт её
	-- сам, AnimalLife её не трогает — папка не «Animals»). Здесь только карта
	-- клипов для клиентского проигрывателя; сами клипы — SheepClips.
	Sheep = {
		clips = { Idle = "Idle", Walk = "Walk", Run = "Walk", Graze = "Graze", Eat = "Eat",
			Drink = "Drink", Rest = "Rest", Look = "Look", Shear = "ShearIdle", React = "Startled" },
		reactLen = 0.9,
	},
	Chicken = {
		walkSpeed = 2, runSpeed = 5.5,
		scare = 4 * 3,
		flee  = 6 * 3,
		eatMin = 1.5, eatMax = 3.5,  -- клюёт часто и коротко
		idleMin = 0.8, idleMax = 2,
		-- бегство — Panic (шок-бег с хлопающими крыльями), реакция — Jump
		-- (подпрыг с четырьмя взмахами)
		clips = { Idle = "IdlePeck", Eat = "IdlePeck", Walk = "Walk",
			Run = "Panic", React = "Jump" },
		reactLen = 1.05,      -- длина Jump
		drops = { Chicken_drumstick = 1, Chicken_feather = 2 },
	},
}

-- ── БОЙ ──
PirateIslandDefs.COMBAT = {
	aggro       = 90,    -- дальше этого NPC игрока не замечает
	rangedFire  = 60,    -- стрелок открывает огонь с этой дистанции
	rangedKeep  = 28,    -- ближе не подходит: его дело — стрелять
	meleeReach  = 5,     -- сабля достаёт вплотную
	hearRadius  = 55,    -- с какого расстояния слышен выстрел; нарочно небольшой,
	                     -- чтобы весь остров не бежал из-за одного хлопка с краю
	hearCheck   = 10,    -- сколько секунд пират помнит звук и осматривает место
	-- КРИК: обнаруживший игрока пират поднимает соседей в этом радиусе (студы)
	-- каждые shoutEvery секунд; те сразу в бою и знают, где игрок. Радиус
	-- меньше слуха выстрела нарочно: крик слышен ближе, чем хлопок револьвера.
	shoutRadius = 45,
	shoutEvery  = 2,
	shotCd      = 1.3,   -- секунд между выстрелами
	swingCd     = 1.1,   -- секунд между взмахами
	leash       = 120,   -- дальше от поста не гонится, возвращается
	-- ⚠️ ВТОРОЙ ПОРОГ, БЕЗ НЕГО ПИРАТ ДЁРГАЕТСЯ НА ГРАНИЦЕ.
	-- Возврат домой прекращается не там же, где начался, а заметно ближе к
	-- посту: иначе шаг туда-сюда через один порог переключал «гонюсь / иду
	-- домой» каждый тик, и пират топтался, будто упёрся в стену.
	leashBack   = 65,    -- до этого расстояния идёт домой, не отвлекаясь
	tick        = 0.2,

	-- слежка и память (сама шкала — в IslandClearSystem, здесь только пороги ИИ)
	investigateAt = 0.5,  -- полшкалы: идёт проверить место, где мелькнул игрок
	forgetAfter   = 6,    -- секунд без прямой видимости → идёт к последней точке
	giveUp        = 14,   -- секунд без видимости → остывает и возвращается на пост
}

function PirateIslandDefs.postName(markerName)
	local n = markerName:match("^[Pp][Tt]_(.+)$")
	return n
end

return PirateIslandDefs
