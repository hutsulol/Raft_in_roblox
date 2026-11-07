--[[
	ВЫЖИВШИЕ (КАПИТАНЫ) — общие данные для сервера (SurvivorService) и окна
	(SurvivorsUI). Хендофф design_handoff_survivors, «Управление выжившими».

	Каталог — кто вообще бывает в команде. Модель каждого живёт в Workspace
	(владелец ставит её туда в Studio вместе с портретной сценой): по ней
	работает предпросмотр в окне (камера встаёт перед моделью) и из неё же
	клонируется работник, когда выжившего назначают в здание.

	Здания — то, что реально стоит на плоту. Сейчас это ферма (дом фермера +
	участки): одно рабочее место. Новое здание — строка в BUILDINGS и ветка
	в SurvivorService.scanBuildings.
]]

local D = {}

D.MAX_CREW = 8
D.SALARY_STEP = 5
D.SALARY_MAX = 100

-- путь от Workspace: { папка, папка, модель }
D.CATALOG = {
	rose = {
		name = "Капитан Роза",
		level = 5,
		stars = 5,                -- редкость для попапа «Новый персонаж» (STAR_TIERS)
		head = "rbxassetid://79371295559556",   -- голова в попапе «Новый персонаж» (крутится)
		hp = 100,
		salary = 40,
		stage = { "Captains", "Rose" },                    -- папка со сценой портрета
		model = { "Captains", "Rose", "Captain Rose" },    -- сам персонаж
		-- свой R6: суставы без стандартных поворотов — клипы фермера пересчитываются
		-- на клиенте (CrewClips, атрибут RigRetarget)
		retarget = true,
		-- лицо — SurfaceGui RoseFace (мимика RoseStudio)
		face = "RoseFace",
		bonuses = {
			-- key/amount — то, что реально применяет сервер
			{ sign = "$", value = "+50%", label = "Прибыль фермы", type = "На работе", key = "farmIncome", amount = 0.5 },
			{ sign = "♥", value = "+10", label = "Настроение", type = "Пассивный", key = "mood", amount = 10 },
		},
	},
	--[[ РЫБАК — первый житель: его дарит торговец («мой друг рыбак»).
	     Модель — ReplicatedStorage.SurvivorFisherman (обычный R6, хендофф
	     Fisherman_Classic_V1). Лицо — Decal + папка FaceTextures, мимику ведёт
	     FishermanFace (сервер) / FishermanFaceAnimator (клиент). Сцены в Workspace
	     нет — превью «Команды» обходится без неё. ]]
	fisherman = {
		name = "Рыбак",
		level = 1,
		stars = 2,
		head = "rbxassetid://120573059186562",   -- иконка, крутится в попапе «Новый персонаж»
		hp = 100,
		salary = 15,
		model = { "@RS", "SurvivorFisherman" },
		faceTextures = true,
		bonuses = {
			{ sign = "$", value = "+25%", label = "Выручка за рыбу", type = "На работе", key = "fishIncome", amount = 0.25 },
		},
	},
	--[[ ПИРАТ — из таверны (IslandHallConfig.RESIDENTS) или кнопкой в настройках.
	     Модель — ReplicatedStorage.SurvivorPirate (обычный R6, хендофф
	     Pirate_Animations_V2: шляпа, одежда, ремень, кушак). Мимика — общая
	     (CharacterFace + FaceTextures модели), поза в «Команде» — профиль
	     "Pirate" (CharacterPoses): перенос веса и жест к полям шляпы. ]]
	pirate = {
		name = "Билли Шквал",
		level = 3,
		stars = 3,
		head = "rbxassetid://81673984292642",   -- иконка, крутится в попапе «Новый персонаж»
		hp = 100,
		salary = 25,
		model = { "@RS", "SurvivorPirate" },
		faceTextures = true,
		profile = "Pirate",
		bonuses = {
			{ sign = "$", value = "+30%", label = "Прибыль фермы", type = "На работе", key = "farmIncome", amount = 0.3 },
			{ sign = "$", value = "+15%", label = "Выручка за рыбу", type = "На работе", key = "fishIncome", amount = 0.15 },
		},
	},
	--[[ COLD CAP (Ghost_Corsair) — морозный герой, награда 7-го дня ежедневки
	     лобби (dailyItems.hero_coldcap) и кнопка в настройках. Хендофф handoff_coldcap:
	     модель ColdCap_CloudReady (R6), лицо — HD (HDFaceCarrier + HDFaceSync,
	     атлас эмоций по атрибуту FaceSpriteKey), аура и морозные следы — свои
	     клиентские скрипты. Модель кладётся в ReplicatedStorage (из Workspace
	     сервер переносит сам, см. SurvivorService).
	     ⚠️ ДЕМО-АНИМАТОР (CorsairAnimator) НА ПЛОТУ НЕ ЗАПУСКАЕМ: он держит корень
	     на якоре и каждый кадр ставит его относительно точки старта — работник
	     уезжал бы с плота в мир. Работнику оставлено только лицо (keepScripts). ]]
	coldcap = {
		name = "Cold Cap",
		level = 5,
		stars = 5,
		tier = 6,                 -- ультра-редкий (голубой) вид попапа, см. STAR_TIERS[6]
		head = "rbxassetid://99053455086582",   -- иконка, крутится в попапе «Новый персонаж»
		hp = 100,
		salary = 45,
		model = { "@RS", "Ghost_Corsair" },
		hdFace = true,
		menuPose = "Corsair",     -- поза в «Команде»: MenuPose из его CorsairAnimator (SurvivorsUI)
		-- что остаётся у работника на плоту: лицо и аура (её плоскость каждый кадр
		-- ставится за торсом — на плывущем плоту работает как есть). Следы —
		-- нет: FrostFootsteps считает шаги по движению в МИРЕ, и на плывущем
		-- плоту стоящий герой «шагал» бы без конца; следы работника рисует
		-- FishermanFaceAnimator относительно плота.
		keepScripts = { HDFaceSync = true, LegendaryMenuFX = true },
		bonuses = {
			{ sign = "$", value = "+40%", label = "Выручка за рыбу", type = "На работе", key = "fishIncome", amount = 0.4 },
			{ sign = "$", value = "+20%", label = "Прибыль фермы", type = "На работе", key = "farmIncome", amount = 0.2 },
			{ sign = "♥", value = "+10", label = "Настроение", type = "Пассивный", key = "mood", amount = 10 },
		},
	},
}

-- звёзды → вид попапа «Новый персонаж» (хендофф design_handoff_new_character):
-- цвет свечения, цвет имени, оборот лучей (с), встречные лучи, число искр
D.STAR_TIERS = {
	[1] = { name = "Обычный",     glow = Color3.fromHex("C9D2DC"), text = Color3.fromHex("E3EBF3"), spin = 10,  counter = false, sparkles = 2 },
	[2] = { name = "Необычный",   glow = Color3.fromHex("6CC0FF"), text = Color3.fromHex("8FD0FF"), spin = 9,   counter = false, sparkles = 3 },
	[3] = { name = "Редкий",      glow = Color3.fromHex("3F9BFF"), text = Color3.fromHex("5AAEFF"), spin = 7.5, counter = false, sparkles = 4 },
	[4] = { name = "Эпический",   glow = Color3.fromHex("B26CFF"), text = Color3.fromHex("C792FF"), spin = 6,   counter = true,  sparkles = 5 },
	[5] = { name = "Легендарный", glow = Color3.fromHex("FFC83A"), text = Color3.fromHex("FFD95A"), spin = 4,   counter = true,  sparkles = 6 },
	-- не число звёзд, а отдельный вид (def.tier): звёзд 5, свечение голубое, как баннер 7-го дня
	[6] = { name = "Ультра-редкий", glow = Color3.fromHex("38CFFF"), text = Color3.fromHex("A8F0FF"), spin = 3.5, counter = true,  sparkles = 7 },
}

-- виды зданий на плоту
D.BUILDINGS = {
	farm = { name = "Ферма", cap = 1 },
	fishing = { name = "Рыбацкое место", cap = 1 },   -- Raft_fishing_spot (RaftFishing)
}

-- ── формулы (прототип хендоффа, балансные заглушки) ──
function D.bonusAmount(def, key)
	local sum = 0
	for _, b in ipairs(def and def.bonuses or {}) do
		if b.key == key then sum += b.amount end
	end
	return sum
end

function D.mood(def, salary, resting)
	local m = salary * 1.1 + 15 + (resting and 20 or 0) + D.bonusAmount(def, "mood")
	return math.clamp(math.floor(m + 0.5), 10, 100)
end

function D.speed(mood)
	return math.floor(60 + mood * 0.6 + 0.5)
end

function D.xp(level)
	return level * 120
end

-- зарплата «в день» → ставка фермы «в час» (ферма платит раз в игровой час)
function D.wagePerHour(salaryPerDay)
	return math.ceil(salaryPerDay / 24)
end

-- ── цвета ──
local hex = Color3.fromHex
function D.levelColor(level)
	if level >= 8 then return hex("E8902A") end
	if level >= 6 then return hex("9B5FE0") end
	if level >= 4 then return hex("1C4F8F") end
	return hex("34B84E")
end

function D.moodColor(m)
	if m >= 65 then return hex("5EE07A") end
	if m >= 35 then return hex("FFD95A") end
	return hex("FF6B5E")
end

function D.tagColor(t)
	if t == "Пассивный" then return hex("34B84E") end
	if t == "Аура" then return hex("9B5FE0") end
	return hex("E8902A")
end

-- найти инстанс по пути от Workspace ("@RS" первым — от ReplicatedStorage)
function D.find(path)
	local node = workspace
	for i, name in ipairs(path or {}) do
		if i == 1 and name == "@RS" then
			node = game:GetService("ReplicatedStorage")
			continue
		end
		node = node and node:FindFirstChild(name)
	end
	return node
end

return D
