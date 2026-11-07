--[[
	ОГНЕМЁТ — общие числа для сервера и клиента.

	Топливо считается в МИЛЛИЛИТРАХ, как и во всей топливной механике
	(см. OilCanister): бак огнемёта равен канистре — 3 литра. Так «заряд
	канистры переходит к заряду огнемёта» при крафте буквально, один в один,
	и заправка с плота считается той же меркой.

	100% бака = 25 секунд непрерывной струи, отсюда и расход.
]]

local Flamethrower = {}

Flamethrower.TOOL_NAME = "Flamethrower"
Flamethrower.MUZZLE    = "hero_flamethrower_muzzle"   -- откуда бьёт струя
Flamethrower.TANK      = "hero_flamethrower_tank"

-- ── бак ──
Flamethrower.ATTR_FUEL = "FuelFill"
Flamethrower.ATTR_CAP  = "FuelCapacity"
Flamethrower.CAPACITY  = 3000              -- мл, ровно как канистра
Flamethrower.BURN_TIME = 25                -- секунд полного бака
Flamethrower.BURN_RATE = 3000 / 25         -- 120 мл/с

-- ── стрельба ──
Flamethrower.MIN_BURST = 0.5   -- короче не бывает: нажал — полсекунды жжёт
Flamethrower.COOLDOWN  = 1.0   -- пауза ПОСЛЕ струи, прежде чем можно снова
Flamethrower.RANGE     = 24    -- студов до кончика струи
Flamethrower.CONE_DEG  = 16    -- полураствор конуса
Flamethrower.TICK      = 0.12  -- как часто струя проверяет, кого задела

-- ── урон ──
Flamethrower.DPS        = 16   -- прямое попадание струи
Flamethrower.BURN_DPS   = 7    -- пока горит сам
Flamethrower.IGNITE_SEC = 6    -- сколько горит враг, если не потушится
Flamethrower.SHAKE_AT   = 0.6  -- доля времени, после которой начинает сбивать

-- ── ЗАГРУЗИ ТЕКСТУРЫ И ВПИШИ ID ──
-- Исходники нарисованы и лежат в test. Струя собрана СЛОЯМИ, поэтому текстур
-- несколько: одним спрайтом огонь выглядит мёртвым, сколько его ни тряси.
--   flame_A/B/C — три разных языка (тело струи, разные силуэты)
--   puff        — катящийся клуб: без него конец струи выглядит обрубленным
--   smoke       — тёмный хвост
--   ember       — искры
--   flip        — флипбук 4×4, 16 кадров мерцания одного языка
-- Пусто = встроенные текстуры Roblox: эффект работает и без загрузки, просто
-- проще на вид.
Flamethrower.TEX_FLAME_A = "rbxassetid://135025882798610"
Flamethrower.TEX_FLAME_B = "rbxassetid://112550608910565"
Flamethrower.TEX_FLAME_C = "rbxassetid://82523181218620"
Flamethrower.TEX_PUFF    = "rbxassetid://108666823220242"
Flamethrower.TEX_SMOKE   = "rbxassetid://96124232115483"
Flamethrower.TEX_EMBER   = "rbxassetid://137255716432468"

-- ⚠️ ФЛИПБУК — ЕДИНСТВЕННЫЙ СЛОЙ, КОТОРЫЙ МОЖЕТ ПОДВЕСТИ.
-- ParticleEmitter.FlipbookLayout в этом плейсе уже вёл себя непредсказуемо: со
-- взрывом кислоты кадры молча не рисовались, и листать их пришлось вручную.
-- Здесь два исхода. Либо флипбук работает и в струе мерцает анимированный язык,
-- либо Roblox проигнорирует разметку — и тогда в огне полетит ВЕСЬ ЛИСТ 4×4
-- разом, сеткой из шестнадцати огоньков. Увидел сетку — ставь false, остальные
-- слои от этого не зависят.
Flamethrower.TEX_FLIP     = "rbxassetid://76532459022142"
Flamethrower.USE_FLIPBOOK = true

local function pick(id, fallback)
	return (id and id ~= "") and id or fallback
end

local FALLBACK_FLAME = "rbxasset://textures/particles/fire_main.dds"
local FALLBACK_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- Три языка для тела струи. Не загружены — все три превращаются во встроенный
-- огонь, слои остаются, просто силуэт у них один.
function Flamethrower.flameTextures()
	return {
		pick(Flamethrower.TEX_FLAME_A, FALLBACK_FLAME),
		pick(Flamethrower.TEX_FLAME_B, FALLBACK_FLAME),
		pick(Flamethrower.TEX_FLAME_C, FALLBACK_FLAME),
	}
end

function Flamethrower.flameTexture()
	return Flamethrower.flameTextures()[1]
end

function Flamethrower.puffTexture()
	return pick(Flamethrower.TEX_PUFF, FALLBACK_FLAME)
end

function Flamethrower.smokeTexture()
	return pick(Flamethrower.TEX_SMOKE, FALLBACK_SMOKE)
end

function Flamethrower.emberTexture()
	return pick(Flamethrower.TEX_EMBER, "rbxasset://textures/particles/sparkles_main.dds")
end

function Flamethrower.flipbook()
	if not Flamethrower.USE_FLIPBOOK or Flamethrower.TEX_FLIP == "" then return nil end
	return Flamethrower.TEX_FLIP
end

-- ── ВТОРОЕ ОРУЖИЕ НА ТОМ ЖЕ ДВИЖКЕ: РУКА КРАКЕНА ──
-- ⚠️ ЭТО НЕ КОПИЯ ОГНЕМЁТА, А ВАРИАНТ.
-- Струя, конус, поджиг, паника горящих, тушение в воде — всё совпадает дословно;
-- отличаются числа и цвет. Поэтому вместо второй системы здесь таблица
-- вариантов, а сервер и клиент берут из неё то, чем стреляет ИМЕННО ЭТОТ
-- инструмент. Третье такое оружие добавляется строкой, а не файлом.
Flamethrower.KRAKEN_NAME = "Kraken_Gun"

Flamethrower.VARIANTS = {
	[Flamethrower.TOOL_NAME] = {
		tool     = Flamethrower.TOOL_NAME,
		muzzle   = Flamethrower.MUZZLE,
		capacity = Flamethrower.CAPACITY,
		burnRate = Flamethrower.BURN_RATE,
		dps      = Flamethrower.DPS,
		burnDps  = Flamethrower.BURN_DPS,
		hot      = Color3.fromRGB(255, 200,  90),
		cool     = Color3.fromRGB(220,  70,  20),
		light    = Color3.fromRGB(255, 150,  60),
		refuelable = true,     -- заправляется из бака на плоту
		regenRate  = 0,        -- сам не копится
		breakable  = true,
		ink   = false,
		glow  = 1,
		-- огонь шипит: щелчок на низкой скорости даёт ровный гул пламени
		sndJet  = { id = "rbxasset://sounds/snap.mp3", speed = 0.28, volume = 0.65 },
		sndBurn = { id = "rbxasset://sounds/snap.mp3", speed = 0.35, volume = 0.50 },
	},
	[Flamethrower.KRAKEN_NAME] = {
		tool     = Flamethrower.KRAKEN_NAME,
		-- струя выходит из детали Effects внутри инструмента — она и есть дуло
		muzzle   = "Effects",
		capacity = Flamethrower.CAPACITY,
		burnRate = Flamethrower.BURN_RATE,   -- держит ровно столько же, 25 секунд
		dps      = Flamethrower.DPS * 2,     -- вдвое сильнее огнемёта
		burnDps  = Flamethrower.BURN_DPS * 2,
		hot      = Color3.fromRGB(226, 160, 255),
		cool     = Color3.fromRGB( 92,  16, 190),
		light    = Color3.fromRGB(170,  70, 255),
		-- ⚠️ НЕ ЗАПРАВЛЯЕТСЯ, А КОПИТСЯ САМ.
		-- Полный запас — те же 25 секунд стрельбы, но восстанавливается он ВТРОЕ
		-- дольше, чем тратится: 75 секунд от нуля до полного. Отсюда и скорость.
		refuelable = false,
		regenRate  = Flamethrower.CAPACITY / (Flamethrower.BURN_TIME * 3),
		breakable  = false,    -- рука кракена не изнашивается
		-- ⚠️ ЭТО ЧЕРНИЛА, А НЕ ОГОНЬ.
		-- Свои текстуры (кляксы со щупальцами, потёки на жертве), цвет в них уже
		-- запечён, и светимость низкая: чернила не горят, а блестят.
		ink   = true,
		glow  = 0.25,
		-- ⚠️ ЧЕРНИЛА НЕ ШИПЯТ, А ХЛЮПАЮТ.
		-- Огненный щелчок на выбросе чернил звучал как костёр из щупальца. Берём
		-- встроенные водяные звуки: гребок под водой на пониженной скорости даёт
		-- густой выброс, удар о воду — влажное капанье на жертве. Оба лежат в
		-- rbxasset и грузятся всегда, в отличие от загруженных в этот плейс.
		sndJet  = { id = "rbxasset://sounds/action_swim.mp3",  speed = 0.62, volume = 0.75 },
		sndBurn = { id = "rbxasset://sounds/impact_water.mp3", speed = 0.55, volume = 0.55 },
	},
}

-- ── ТЕКСТУРЫ ЧЕРНИЛ (нарисованы, лежат в test/kraken_ink) ──
-- ⚠️ ЦВЕТ ЗАПЕЧЁН В САМИ СПРАЙТЫ, ПОЭТОМУ ТОНИРОВКИ У НИХ НЕТ.
-- Тёмно-индиговое ядро → пурпур → голубое свечение по краю, как окрашена сама
-- модель оружия. ParticleEmitter.Color — один множитель на весь спрайт, таким
-- переходом он не управляет: покрасив им пламя, получишь сиреневый дым, а не
-- чернила. Значит у этих эмиттеров Color обязан остаться БЕЛЫМ (variant.tint).
-- Пусто = пока не загружено, работает на текстурах огня.
Flamethrower.TEX_INK_A     = "rbxassetid://140111332533949"   -- Kraken_ink_A
Flamethrower.TEX_INK_B     = "rbxassetid://118077217184933"   -- Kraken_ink_B
Flamethrower.TEX_INK_C     = "rbxassetid://87643425728980"    -- Kraken_ink_C
Flamethrower.TEX_INK_PUFF  = "rbxassetid://104823668249396"   -- Kraken_ink_puff
Flamethrower.TEX_INK_WISP  = "rbxassetid://107339175184218"   -- вместо дыма
Flamethrower.TEX_INK_DROP  = "rbxassetid://99927005344260"    -- вместо искр
Flamethrower.TEX_INK_CLING = "rbxassetid://79150149129788"    -- налипло на жертве
Flamethrower.TEX_INK_FLIP  = "rbxassetid://83217901752108"    -- флипбук 4×4

-- Текстуры по варианту: чернильные, если они загружены, иначе огненные.
function Flamethrower.bodyTextures(v)
	if not (v and v.ink) then return Flamethrower.flameTextures() end
	local f = Flamethrower.flameTextures()
	return {
		pick(Flamethrower.TEX_INK_A, f[1]),
		pick(Flamethrower.TEX_INK_B, f[2]),
		pick(Flamethrower.TEX_INK_C, f[3]),
	}
end

function Flamethrower.puffFor(v)
	if v and v.ink then return pick(Flamethrower.TEX_INK_PUFF, Flamethrower.puffTexture()) end
	return Flamethrower.puffTexture()
end

function Flamethrower.smokeFor(v)
	if v and v.ink then return pick(Flamethrower.TEX_INK_WISP, Flamethrower.smokeTexture()) end
	return Flamethrower.smokeTexture()
end

function Flamethrower.emberFor(v)
	if v and v.ink then return pick(Flamethrower.TEX_INK_DROP, Flamethrower.emberTexture()) end
	return Flamethrower.emberTexture()
end

-- Что налипает на подожжённого: у огня это те же языки, у чернил — потёки.
function Flamethrower.clingFor(v)
	if v and v.ink then
		return pick(Flamethrower.TEX_INK_CLING, Flamethrower.bodyTextures(v)[1])
	end
	return Flamethrower.flameTextures()[1]
end

function Flamethrower.flipFor(v)
	if v and v.ink then
		if Flamethrower.TEX_INK_FLIP == "" then return nil end
		return Flamethrower.TEX_INK_FLIP
	end
	return Flamethrower.flipbook()
end

-- Чем красить эмиттер. У чернил цвет уже в текстуре — отдаём белый.
local WHITE = ColorSequence.new(Color3.new(1, 1, 1))
function Flamethrower.tintFor(v, hot, cool)
	if v and v.ink then return WHITE end
	return ColorSequence.new(hot, cool)
end

-- Чем стреляет этот инструмент. nil — значит это вообще не наше оружие.
function Flamethrower.variant(tool)
	if not (tool and tool:IsA("Tool")) then return nil end
	return Flamethrower.VARIANTS[tool.Name]
end

function Flamethrower.variantByName(name)
	return Flamethrower.VARIANTS[name]
end

-- ── клипы реакций (см. PirateCrewClips) ──
Flamethrower.SHOCK_CLIPS = { "Fire_Shock1", "Fire_Shock2" }
Flamethrower.BURN_CLIP   = "Fire_Burn"
Flamethrower.SHAKE_CLIP  = "Fire_Shake"

-- ── кто считается врагом ──
-- Огонь не разбирает своих и чужих по совести, поэтому список явный. Проверка
-- идёт по началу имени модели: Pirate_Bosun_Gate, Marine_Private, Infected_… —
-- все они начинаются с этих корней.
Flamethrower.ENEMY_PREFIXES = {
	"Pirate", "Marine", "Infected", "Zombie", "Enemy", "Corsair", "Raider", "Boss",
	-- живность острова: струя жжёт и её — иначе квест «убей корову» огнемётом
	-- не закрыть (владелец: «огнемёт не наносит урона корове»)
	"Cow", "Chicken", "Hen",
}
-- А это — свои, их не поджигаем, даже если имя случайно совпадёт с корнем выше.
Flamethrower.FRIENDLY_NAMES = {
	Rebel = true,   -- повстанцы на зачищенном острове — свои
	Villager = true, Women_Villager = true, Prisoner = true, Diver = true,
	GhostDiver = true, Engineer = true, Mechanic = true, Chef = true,
	Merc = true, Mercenary = true, Worker = true, Sailor = true,
}

return Flamethrower
