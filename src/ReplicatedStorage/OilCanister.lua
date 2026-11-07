--[[
	ПЛАСТИКОВАЯ КАНИСТРА — общий модуль для сервера и клиента.

	В канистру наливают нефть из бочек. Объём ограничен: сколько влезло, столько и
	унёс. Уровень живёт в атрибутах самого Tool (OilFill / OilCapacity) — атрибуты
	реплицируются на клиент сами, отдельный ремоут для шкалы не нужен.

	ОТКУДА НАЛИВАТЬ. Источник опознаётся по атрибуту OilSource = true на модели или
	детали, либо по имени из SOURCE_NAMES. Запас источника — атрибут OilLeft
	(нет атрибута = бесконечный источник). Так бочку можно поставить в Studio и
	пометить галочкой, не трогая код.
]]

local OilCanister = {}

OilCanister.TOOL_NAME = "Plastic_canister"
OilCanister.ICON      = "rbxassetid://131765057486498"

OilCanister.ATTR_FILL = "OilFill"
OilCanister.ATTR_CAP  = "OilCapacity"

-- ВСЁ В МИЛЛИЛИТРАХ. Канистра — 3 литра, бочка с катера — 600–900 мл, то есть
-- одна бочка даёт 20–30% канистры, как и задумано.
OilCanister.CAPACITY  = 3000
OilCanister.POUR_RATE = 400    -- мл в секунду, пока игрок держит кнопку
OilCanister.POUR_TICK = 0.1    -- шаг долива: чаще незачем, шкала и так плавная

-- ── источник нефти ──
OilCanister.SOURCE_ATTR      = "OilSource"   -- пометка на модели/детали в Studio
OilCanister.SOURCE_LEFT_ATTR = "OilLeft"     -- остаток в мл; проставляется сам
OilCanister.SOURCE_ML_MIN = 600
OilCanister.SOURCE_ML_MAX = 900

-- КАНИСТРЫ С ТОПЛИВОМ НА КАТЕРАХ — из них наливают. Cargo_Fuel — реальная деталь
-- грузового катера (см. PiratePatrolBoat), остальные имена на вырост.
OilCanister.SOURCE_NAMES = {
	"Cargo_Fuel", "Fuel_Canister", "Canister_Fuel", "Fuel_Barrel", "Barrel_Fuel",
}
OilCanister.PROMPT_TEXT   = "Наливать"
OilCanister.PROMPT_OBJECT = "Канистра с топливом"
OilCanister.REACH         = 12    -- студов до ёмкости

-- ── БАК НА ПЛОТУ (OilBarrel_SCENE) — в него ЗАЛИВАЮТ ──
-- Игрок подходит к воронке и переливает в бак то, что набрал в канистру.
-- Объём бака в мл; на экране он показывается в литрах.
OilCanister.TANK_NAMES    = { "OilBarrel_SCENE", "Oil_Barrel_SCENE", "OilTank" }
OilCanister.TANK_FUNNEL   = { "Oil_funnel" }    -- деталь, к которой подходят
OilCanister.TANK_SCREEN   = { "Oil_screen" }    -- деталь с SurfaceGui и цифрой
OilCanister.TANK_ATTR     = "OilStored"         -- сколько мл сейчас в баке
-- ⚠️ 100 литров на время тестов огнемёта (было 50). Экран показывает объём сам,
-- по этому же числу, так что цифра на баке не разойдётся с настоящей.
OilCanister.TANK_CAPACITY = 100000
OilCanister.TANK_PROMPT   = "Заливать"
OilCanister.TANK_OBJECT   = "Топливный бак"

-- «1.8 л» / «750 мл» — литры для крупных объёмов, миллилитры для мелких.
function OilCanister.formatVolume(ml)
	ml = math.max(0, math.floor(tonumber(ml) or 0))
	if ml >= 1000 then
		return ("%.1f л"):format(ml / 1000)
	end
	return ("%d мл"):format(ml)
end

-- Число для экрана бака: «0», «1.8», «12.4», «50». Дробная часть отбрасывается у
-- круглых значений, иначе на маленьком экране копятся лишние символы.
function OilCanister.formatLitres(ml)
	local litres = math.max(0, tonumber(ml) or 0) / 1000
	if math.abs(litres - math.floor(litres + 0.5)) < 0.05 then
		return ("%d"):format(math.floor(litres + 0.5))
	end
	return ("%.1f"):format(litres)
end

--[[ ⚠️ НАЙДЕННЫЙ БАК ЗАПОМИНАЕТСЯ, И ЭТО НЕ МИКРООПТИМИЗАЦИЯ.
     FindFirstChild(name, true) — РЕКУРСИВНЫЙ обход всего Workspace, а в нём
     десятки тысяч инстансов: один плот с сотнями тайлов-моделей, острова, декор.
     Эту функцию зовёт снимок карты — раз в секунду на каждого игрока с открытой
     картой, — и пока бак не поставлен, промахиваются все ТРИ имени подряд, то
     есть три полных обхода мира в секунду на игрока. На сервере, который тем же
     кадром считает физику плота, это ровно та причина, по которой плот идёт
     рывками и «телепортируется».
     Отрицательный ответ НЕ кэшируем: бак могут поставить в любой момент, и «нет»
     осталось бы навсегда. Кэш проверяется на Parent — сняли бак, ищем заново. ]]
local tankCache = nil
function OilCanister.findTank(root)
	root = root or workspace
	if tankCache and tankCache.Parent and tankCache:IsDescendantOf(root) then
		return tankCache
	end
	tankCache = nil
	for _, name in ipairs(OilCanister.TANK_NAMES) do
		local m = root:FindFirstChild(name, true)
		if m then
			tankCache = m
			return m
		end
	end
	return nil
end

function OilCanister.findTankPart(tank, names)
	if not tank then return nil end
	for _, name in ipairs(names) do
		local p = tank:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then return p end
	end
	return nil
end

function OilCanister.tankStored(tank)
	local v = tank and tank:GetAttribute(OilCanister.TANK_ATTR)
	return (type(v) == "number") and math.max(0, v) or 0
end

-- ── шкала наполненности (статус-бар над хотбаром) ──
OilCanister.BAR_LABEL   = "Заполнено:"
OilCanister.BAR_EMPTY   = Color3.fromRGB(120, 124, 130)   -- серый — весь объём
OilCanister.BAR_FILLED  = Color3.fromRGB( 76, 200,  84)   -- зелёный — сколько налито

function OilCanister.isCanister(tool)
	return tool ~= nil and tool:IsA("Tool") and tool.Name == OilCanister.TOOL_NAME
end

function OilCanister.isSource(inst)
	if not inst then return false end
	if inst:GetAttribute(OilCanister.SOURCE_ATTR) then return true end
	local name = inst.Name
	for _, n in ipairs(OilCanister.SOURCE_NAMES) do
		if name == n then return true end
	end
	return false
end

-- Доля наполненности 0..1 или nil, если это не канистра.
function OilCanister.fractionOf(tool)
	if not OilCanister.isCanister(tool) then return nil end
	local cap = tool:GetAttribute(OilCanister.ATTR_CAP)
	if type(cap) ~= "number" or cap <= 0 then cap = OilCanister.CAPACITY end
	local fill = tool:GetAttribute(OilCanister.ATTR_FILL)
	if type(fill) ~= "number" then fill = 0 end
	return math.clamp(fill / cap, 0, 1)
end

return OilCanister
