--[[
	ФЕРМА НА ПЛОТУ — общие числа и оформление (сервер RaftFarmService, клиент RaftFarmUI).

	Ферма = дом фермера Raft_farmer_hut + связная группа блоков Raft_farm_block,
	к которой он пристроен. Внутри забора: корыто и кормушка (их ставит сервер),
	овцы, попавшие в зону, и фермер, который днём работает, ночью спит в доме.

	⚠️ ДЕНЬГИ СЧИТАЕТ ТОЛЬКО СЕРВЕР и пишет атрибутами (раздел 3 хендоффа
	farm-ui-design): клиент лишь рисует. Все «/ч» — за ИГРОВОЙ час, как у
	PassiveIncome (день 6→18 идёт 380 с, ночь 120 с).
]]

local C = {}

C.HUT    = "Raft_farmer_hut"
C.BLOCK  = "Raft_farm_block"
C.FARMER = "Farmer"          -- шаблон NPC в ReplicatedStorage

-- смена фермера (Lighting.ClockTime)
C.WORK_START = 6.5
C.WORK_END   = 19

-- ── экономика (за игровой час) ──
C.SHEEP_INCOME    = 37      -- монет с одной сытой овцы с водой
C.LEVEL_BONUS     = 0.25    -- +25 % за каждый уровень овцы сверх первого
C.SHEEP_PER_BLOCK = 3       -- сколько овец вмещает один блок 2×2
C.WAGE            = 25      -- зарплата фермера
C.WORKER_MAX      = 1

C.HUNGRY_BELOW  = 25        -- сытость < 25 % → доход овцы ×PENALTY
C.THIRSTY_BELOW = 20        -- вода в корыте < 20 % → доход ×PENALTY
C.PENALTY       = 0.5

C.SATIETY_DRAIN = 12        -- сколько сытости теряет овца за час
C.EAT_GAIN      = 45        -- сколько набирает за час, пока в кормушке есть сено
C.EAT_HAY       = 8         -- сколько сена съедает одна жующая овца за час
C.EAT_UNTIL     = 95        -- выше этого не ест
C.FEED_BY_HAND  = 15        -- фермер покормил с руки

-- ── вода: у каждой овцы своя жажда, пьёт она САМА из корыта ──
C.HYDRATION_DRAIN = 20      -- сколько «напоенности» теряет овца за игровой час
C.SEEK_WATER_BELOW = 60     -- ниже — идёт к корыту, если в нём есть вода
C.DRINK_GAIN = 50           -- один подход к корыту
C.DRINK_WATER = 6           -- литров выпивает за подход
C.GRAZE_GAIN = { grass = 40, cover = 20 }   -- сытость за час, пока пасётся на траве

C.FEEDER_MAX = 100          -- сено в кормушке
C.TROUGH_MAX = 100          -- литры в корыте
C.DRINK_PER_MIN = 1.5       -- литров в РЕАЛЬНУЮ минуту на овцу (для «хватит на ~N мин»)

-- ⚠️ корыто и кормушку ставит ИГРОК (их модели — постройки плота); сервер лишь
-- находит их в загоне по имени. Новое имя модели — впиши сюда.
C.TROUGH_NAMES = { Raft_trough = true, Raft_water_trough = true, Farm_Trough = true, Raft_farm_trough = true }
C.FEEDER_NAMES = { Raft_feeder = true, Raft_hay_feeder = true, Farm_Feeder = true, Raft_farm_feeder = true }

-- запас в доме, откуда фермер носит
C.STORE_HAY_MAX   = 60
C.STORE_WATER_MAX = 60
C.CARRY_HAY   = 25          -- охапка за ходку
C.CARRY_WATER = 25          -- два ведра за ходку
C.REFILL_BELOW = 60         -- фермер идёт пополнять, когда меньше 60 %

-- что игрок приносит сам
C.HAY_ITEM      = "Leaves"  -- 1 листва → HAY_PER_LEAF сена
C.HAY_PER_LEAF  = 10
C.WATER_PER_CUP = 10        -- один заряд кружки/бутылки → литров

-- ── движение фермера ──
C.WALK_SPEED  = 7
C.CARRY_SPEED = 5
C.COLLECT_DIST = 40         -- с какого расстояния работает «СОБРАТЬ»

-- ── оформление (хендофф, раздел 4) ──
local hex = Color3.fromHex
C.Theme = {
	Outline  = hex("000000"),
	Text     = hex("FFFFFF"),
	TextDark = hex("1B2A55"),
	Money    = hex("5CF03C"),
	Gold     = hex("FFD21F"),
	Danger   = hex("FF5A4A"),
	BarTrack = hex("0C2A70"),
	BarHunger = hex("FFA51F"),
	BarWater = hex("2EC8FF"),
	BarDanger = hex("FF4A3A"),
	WorkerDark = hex("3A1580"),
	StrikeRow  = hex("3B3F4D"),
	StrikeAvatar = hex("D7DAE3"),
}
C.Gradients = {
	Blue   = { hex("4FB0FF"), hex("1F63E0") },
	Water  = { hex("5FD0FF"), hex("1F7FE0") },
	Green  = { hex("7DF06A"), hex("22A83A") },
	Red    = { hex("FF8A7A"), hex("E0302A") },
	Purple = { hex("C98BFF"), hex("7A2FE0") },
	Gray   = { hex("A3A8B8"), hex("5D6275") },
	Yellow = { hex("FFE45C"), hex("FFB300") },
}
-- иконок-картинок пока нет: рисуем эмодзи (хендофф разрешает заглушки)
C.Icons = { Coin = "", Sheep = "🐑", Worker = "👒", Wage = "💵", Drop = "💧", Star = "⭐", Clock = "⏰" }

C.SHEEP_COMPACT_DIST = 35
C.SHEEP_HIDE_DIST    = 80

-- доход одной овцы за час
-- hydration — «напоенность» САМОЙ овцы (0..100), а не уровень корыта
function C.sheepIncome(level, satiety, hydration)
	local inc = C.SHEEP_INCOME * (1 + C.LEVEL_BONUS * math.max(0, (level or 1) - 1))
	if (satiety or 100) < C.HUNGRY_BELOW then inc = inc * C.PENALTY end
	if (hydration or 100) < C.THIRSTY_BELOW then inc = inc * C.PENALTY end
	return inc
end

return C
