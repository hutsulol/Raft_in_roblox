--[[
	ДОМ НА ДВУХ ЖИТЕЛЕЙ — общие числа для сервера и клиента.

	Всё, кроме кода, взято из House/README.md. Точки замерены там же скриптом
	render_sleep.py: он кладёт позированного R6 на каждую кровать и печатает, где
	оказались голова и ступни. Читаем мы их из самой модели, а не из этих чисел;
	здесь только запасные значения на случай, если маркеры удалили.
]]

local House = {}

House.MODEL = "House_home"     -- модель постройки
House.ROOF  = "house_roof"     -- крыша отдельным мешем: её прячут при входе

-- ⚠️ СТАВИТСЯ НА СУШУ ОСТРОВА, ТЕМИ ЖЕ ПРАВИЛАМИ, ЧТО ВЫШКА.
-- Проверку места не дублируем — она уже написана в OilRigSystem и выставлена
-- наружу как _G.OilRigSpotOK. Два одинаковых набора допусков разъехались бы
-- при первой же правке.
House.TILE_PREFIX = "Island_terrain"
House.SINK = 0.4    -- на столько цоколь утапливаем в грунт

House.WP = {
	bedA = "wp_bed_a",   -- HumanoidRootPart спящего на кровати A
	bedB = "wp_bed_b",   -- то же для кровати B
	sitA = "wp_sit_a",   -- место у стола, ближнее к северу
	sitB = "wp_sit_b",
	door = "wp_door",    -- точка снаружи двери: начало и конец маршрутов
}
House.FX = {
	hearth = "fx_hearth",   -- огонь в очаге
	lamp   = "fx_lamp",     -- подвесной фонарь
}

-- Запасные позиции (студы, от пивота модели). Метры README × 3, оси
-- пересчитаны из блендеровских в роблоксовские: (x, z, −y).
House.FALLBACK = {
	wp_bed_a  = Vector3.new(-3.75, 3.36, -3.36),
	wp_bed_b  = Vector3.new( 3.75, 3.36, -3.36),
	wp_sit_a  = Vector3.new( 2.40, 2.73,  1.80),
	wp_sit_b  = Vector3.new( 2.40, 2.73,  5.40),
	wp_door   = Vector3.new( 0.00, 1.65,  8.70),
	fx_hearth = Vector3.new(-5.67, 1.89,  3.15),
	fx_lamp   = Vector3.new( 0.30, 6.15,  1.35),
}

-- ⚠️ ГОЛОВОЙ К ПОДУШКЕ — ОДНО ЧИСЛО.
-- У R6 тело заваливается поворотом RootJoint (клип трогает «Torso»), и голова
-- уезжает НАЗАД от направления взгляда. Значит на кровать рабочего надо ставить
-- спиной к изголовью. Если после сборки он лежит головой в ноги — разворот на
-- 180° правится здесь и только здесь.
House.BED_TURN = CFrame.Angles(0, math.pi, 0)

-- Клипы сна. R6-анимации из FBX Roblox не импортирует вовсе (House/README.md,
-- раздел 4), поэтому пять клипов из набора играть неоткуда — свои написаны
-- таблицей в PirateCrewClips, блок «ДОМ». Длительности взяты из clips.json,
-- чтобы движение совпадало с задуманным.
House.CLIPS = {
	enter = "House_SleepEnter",   -- 1.33 с, присел на край и завалился
	sleep = "House_Sleep",        -- 6.67 с, луп: дышит
	exit  = "House_SleepExit",    -- 1.53 с, поднялся
	walk  = "Oil_Carry",          -- ходьба: та же, что у носильщика
	sit   = "House_Sit",          -- безработный сидит на стуле
}

-- ── ТАБЛИЧКА С ЖИТЕЛЯМИ ──
-- Деталь заказчик добавил под именем InfoPart; принимаем и соседние написания,
-- чтобы не ловить опечатку.
House.INFO_NAMES = { "InfoPart", "infopart", "info_part", "InfoPanel", "infopanel" }
House.MAX_RESIDENTS = 2      -- кроватей в доме ровно две

-- Имена жителей. Берутся по кругу, но каждому запоминаются в атрибут — значит
-- в доме имя не поменяется, пока жив сам рабочий.
House.NAMES = {
	"Борис", "Марта", "Захар", "Ника", "Тимур", "Клава", "Савелий", "Рита",
	"Гриша", "Люда", "Пётр", "Зоя",
}
House.ROLE_OIL = "Нефтяник"
House.ROLE_FARM = "Фермер"

-- ⚠️ ЗВЁЗДЫ И ЗВАНИЕ — ОДНО И ТО ЖЕ ЧИСЛО.
-- Звание выводится из звёзд, а не хранится отдельно: два поля разошлись бы, и на
-- табличке появился бы «Мастер ★».
House.RANKS = {
	[1] = { label = "Новичок",  bg = Color3.fromRGB( 74,  90, 108),
	        fg = Color3.fromRGB(255, 255, 255), ring = Color3.fromRGB(120, 130, 140) },
	[2] = { label = "Работяга", bg = Color3.fromRGB( 40, 106, 176),
	        fg = Color3.fromRGB(255, 255, 255), ring = Color3.fromRGB(150, 110,  62) },
	[3] = { label = "Мастер",   bg = Color3.fromRGB(242, 194,  48),
	        fg = Color3.fromRGB( 26,  26,  26), ring = Color3.fromRGB(232, 185,  58) },
}

House.UI = {
	BACK   = Color3.fromRGB( 16,  26,  38),
	ROW    = Color3.fromRGB( 22,  40,  61),
	TITLE  = Color3.fromRGB(255, 255, 255),
	ROLE   = Color3.fromRGB(214, 176,  58),
	STAR   = Color3.fromRGB(255, 210,  58),
	BUTTON = Color3.fromRGB(242, 194,  48),   -- жёлтая «Управление»
	BTN_FG = Color3.fromRGB( 26,  26,  26),
	EMPTY  = Color3.fromRGB(120, 136, 152),
}

-- ── МЕНЮ УПРАВЛЕНИЯ ДОМОМ (хендоф House Menu) ──

House.NAME_RU  = "Дом на острове"
House.LEVEL    = 2      -- уровень дома по умолчанию (Tweaks прототипа)
House.CAPACITY = 2      -- мест; +1 за уровень улучшения
House.COMFORT_PER_LEVEL = 0.05   -- +5% к эффективности за уровень

-- ⚠️ ЗВЁЗДЫ ПОКА ВСЕГДА ОДНА.
-- Заказчик: «у жителей есть звёзды, все 1-звёздочные пока». Механика ранга уже
-- есть везде, растить их будет отдельная система — менять надо ЭТО число, а не
-- разбросанные единицы по коду.
House.STARS_DEFAULT = 1
House.STAR_BONUS = 0.10   -- +10% к выработке за звезду сверх первой

-- Типы жителей: чип справа в списке и бонус в карточке.
House.TYPES = {
	worker  = { label = "Работяга", color = Color3.fromRGB(159, 208, 238),
	            bonus = "+15% к добыче" },
	craft   = { label = "Мастер",   color = Color3.fromRGB(255, 210,  58),
	            bonus = "+25% к скорости строительства" },
	fighter = { label = "Боец",     color = Color3.fromRGB(255, 157, 143),
	            bonus = "+3 к защите острова на посту стражника" },
}
House.TYPE_ORDER = { "worker", "craft", "fighter" }

-- Возраст: базовая эффективность и подпись в чипе.
House.AGES = {
	child = { label = "Ребёнок", eff = 0.50, from = 8,  to = 15 },
	adult = { label = "Взрослый", eff = 1.00, from = 19, to = 52 },
	old   = { label = "Старик",  eff = 0.70, from = 58, to = 74 },
}
House.AGE_ORDER = { "child", "adult", "old" }

-- Профессии. unlocked = открыта с самого начала; остальные под замком до
-- прогресса (сервер шлёт список открытых).
House.JOBS = {
	{ id = "none",    name = "Без работы", effect = "отдыхает",
	  color = Color3.fromRGB(140, 156, 172), unlocked = true },
	{ id = "fisher",  name = "Рыбак",      effect = "+еда",
	  color = Color3.fromRGB( 96, 178, 214) },
	{ id = "lumber",  name = "Лесоруб",    effect = "+дерево",
	  color = Color3.fromRGB(146, 104,  58) },
	{ id = "miner",   name = "Рудокоп",    effect = "+железо",
	  color = Color3.fromRGB(150, 158, 170) },
	{ id = "oil",     name = "Нефтяник",   effect = "+нефть",
	  color = Color3.fromRGB( 40,  40,  40), unlocked = true },
	{ id = "guard",   name = "Стражник",   effect = "+защита острова",
	  color = Color3.fromRGB(214,  92,  82) },
	{ id = "builder", name = "Строитель",  effect = "быстрее стройка",
	  color = Color3.fromRGB( 96, 200, 120) },
	-- ФЕРМЕР: работает на построенной ферме (Farm_Island_Build), одна ферма — один
	-- житель. Назначение проверяет FarmSystem (_G.FarmAssign): нет свободной
	-- фермы — профессия не выдаётся, игроку называется причина.
	{ id = "farmer",  name = "Фермер",     effect = "+шерсть, +пираты",
	  color = Color3.fromRGB(226, 214, 168), unlocked = true },
}

function House.jobById(id)
	for _, j in ipairs(House.JOBS) do
		if j.id == id then return j end
	end
	return House.JOBS[1]
end

-- ⚠️ ЭФФЕКТИВНОСТЬ СЧИТАЕТСЯ ОДНОЙ ФУНКЦИЕЙ НА ДВОИХ.
-- Её показывает карточка жителя и по ней же сервер умножает выработку. Две копии
-- формулы разошлись бы, и в карточке было бы одно число, а в бочке другое.
function House.efficiency(res, level)
	local age = House.AGES[res.age] or House.AGES.adult
	local comfort = 1 + (level or House.LEVEL) * House.COMFORT_PER_LEVEL
	local stars = 1 + ((res.stars or 1) - 1) * House.STAR_BONUS
	return age.eff * comfort * stars
end

-- ── ОДЕЖДА ПО ПРОФЕССИИ ──
-- ⚠️ ID ПОКА ПУСТЫЕ — ЭТО НЕ ЗАБЫТО, А ТАК И ЗАДУМАНО.
-- Заказчик добавит их позже. До тех пор пустая строка означает «ассета нет —
-- оставить РОДНУЮ одежду модели»: у рабочих она уже нарисована внутри и служит
-- робой. Раздевается только безработный ("none", уволенный) — по нему и видно,
-- что человек больше не при деле. Разбор — в HouseSystem.HouseApplyOutfit.
--[[ ⚠️ ОДЕЖДА БЕЗРАБОТНОГО — ЕДИНСТВЕННАЯ, ЧТО У НАС ЕСТЬ ПОМИМО РОБЫ.
     Рабочая роба нарисована внутри самих моделей рабочих, а вот уволенный
     оставался буквально голым: старое правило просто гасило одежду и ничего
     не надевало взамен. Эти ассеты прислал владелец — по комплекту на
     женскую и мужскую модель, вместе с лицом.
     ⚠️ Лицо меняется вместе с одеждой: рабочее лицо у моделей своё, и
     оставить его на уволенном значит получить нефтяника в гражданском. ]]
House.OUTFIT_NONE = {
	female = {
		shirt = "rbxassetid://106204522334036",
		pants = "rbxassetid://96515615034207",
		face  = "rbxassetid://129631101629551",
	},
	male = {
		shirt = "rbxassetid://120863901373859",
		pants = "rbxassetid://136820414192564",
		face  = "rbxassetid://93484748874240",
	},
}

--[[ ⚠️ ПОЛ ЖИТЕЛЯ В ДАННЫХ НЕ ХРАНИТСЯ — ОПРЕДЕЛЯЕМ ПО МОДЕЛИ.
     В таблице жителя есть имя, возраст, тип и профессия, а пола нет вовсе, и
     придумывать его на сервере нельзя: одежда должна совпасть с телом, которое
     стоит в мире.
     Порядок такой: сперва атрибут Sex на модели («female»/«male») — его можно
     проставить в Studio одним кликом и это самый надёжный путь; если атрибута
     нет, смотрим на ИМЯ модели по списку ниже; если и там пусто — считаем
     мужчиной и один раз пишем в лог имя модели, чтобы было видно, что именно
     дописать в список. ]]
House.FEMALE_HINTS = { "female", "girl", "woman", "lady", "_f", "дев", "жен" }

House.JOB_OUTFIT = {
	none    = { shirt = "", pants = "" },
	oil     = { shirt = "", pants = "" },
	fisher  = { shirt = "", pants = "" },
	lumber  = { shirt = "", pants = "" },
	miner   = { shirt = "", pants = "" },
	guard   = { shirt = "", pants = "" },
	builder = { shirt = "", pants = "" },
	farmer  = { shirt = "", pants = "" },
}

House.UI2 = {
	PANEL     = Color3.fromRGB( 18,  40,  60),   -- #12283c
	HEAD_TOP  = Color3.fromRGB( 27,  58,  89),   -- #1b3a59
	HEAD_BOT  = Color3.fromRGB( 20,  45,  68),   -- #142d44
	LOCKED    = Color3.fromRGB( 21,  42,  62),   -- #152a3e
	MUTED     = Color3.fromRGB(127, 168, 201),   -- #7fa8c9
	MUTED2    = Color3.fromRGB(111, 151, 184),   -- #6f97b8
	GOLD      = Color3.fromRGB(255, 210,  58),
	GREEN     = Color3.fromRGB( 69, 204,  69),
	GREEN_MID = Color3.fromRGB( 47, 163,  47),
	RED_TOP   = Color3.fromRGB(217,  69,  63),
	RED_BOT   = Color3.fromRGB(168,  48,  43),
	BLUE_TOP  = Color3.fromRGB( 44,  77, 104),
	BLUE_BOT  = Color3.fromRGB( 19,  38,  56),
	STEEL     = Color3.fromRGB(143, 165, 181),   -- замок
}

-- Цена в молотке. Совпадает с пунктом меню в BuildingSystem.
House.COST      = 20
House.COST_TYPE = "Log"

return House
