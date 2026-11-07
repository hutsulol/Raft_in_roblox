--[[
	Хватает ли ресурсов на крафт — для пошаговых подсказок квестов.

	⚠️ МАТЕРИАЛ ПРОВЕРЯЕМ ПЕРВЫМ, ДО ВСЯКОГО ИНВЕНТАРЯ.
	Подсказка ведёт игрока по шагам: открой рюкзак → вкладка → скрафти. Если при
	этом не смотреть на запасы, человек послушно доходит до кнопки крафта и только
	там узнаёт, что брёвен нет, — и идёт их вылавливать, потеряв весь путь. Причём
	узнаёт он это сам, потому что кольцо подсказки всё ещё показывает на кнопку,
	которая ничего не делает.

	Правило: пока материала не хватает, шаг ровно один — «иди добудь», с числом
	«сколько есть из сколько надо», чтобы был виден прогресс.

		local Cost = require(ReplicatedStorage.QuestHintCost)
		local short = Cost.shortfall({ Log = 5, Leaves = 3 })
		if short then return nil, short, true end

	Возвращает nil, когда всего хватает.
]]

local QuestHintCost = {}

-- Считаем по тем же клиентским данным слотов, что рисует инвентарь: отдельного
-- ремоута «сколько у меня дерева» в проекте нет, а слоты и так у клиента.
function QuestHintCost.have(resource)
	local slotData = _G.InventorySlotData
	local total = 0
	if type(slotData) == "table" then
		for _, d in pairs(slotData) do
			if type(d) == "table" and d.type == "resource" and d.name == resource then
				total += tonumber(d.count) or 0
			end
		end
	end
	return total
end

-- Текст под каждый ресурс: не просто «нужно ещё», а ГДЕ ЕГО ВЗЯТЬ. Без этого
-- подсказка обрывается на полуслове — самый частый вопрос новичка именно такой.
local TEXT = {
	Log     = "Нужно дерево: %d из %d — вылавливай брёвна из океана",
	Leaves  = "Нужно листвы: %d из %d — вылавливай листву из океана",
	Plastic = "Нужно пластика: %d из %d — вылавливай канистры из океана",
	Rope    = "Нужно верёвки: %d из %d — плети из листвы в инвентаре",
	Stone   = "Нужно камня: %d из %d — добудь киркой на острове",
	Compost = "Нужно компоста: %d из %d — вылавливай компост из океана",
}

-- Порядок фиксирован: pairs по таблице цен выдал бы ресурсы как придётся, и
-- подсказка прыгала бы между «нужно дерево» и «нужно листвы» на каждом кадре.
local ORDER = { "Log", "Compost", "Leaves", "Plastic", "Rope", "Stone" }

--[[ costs — таблица вида { Log = 5, Leaves = 3 }.
     Возвращает текст про ПЕРВЫЙ недостающий ресурс либо nil, если всего хватает.
     Первый, а не все сразу: строка едет в узкий баннер, а добывать всё равно
     придётся по очереди. ]]
-- Ключ ПЕРВОГО недостающего ресурса (тем же порядком, что shortfall) — подсказкам,
-- которые подсвечивают этот ресурс в океане. nil, если всего хватает.
function QuestHintCost.shortfallRes(costs)
	local seen = {}
	for _, res in ipairs(ORDER) do
		local need = costs[res]
		if need then
			seen[res] = true
			if QuestHintCost.have(res) < need then return res end
		end
	end
	for res, need in pairs(costs) do
		if not seen[res] and QuestHintCost.have(res) < need then return res end
	end
	return nil
end

function QuestHintCost.shortfall(costs)
	local seen = {}
	for _, res in ipairs(ORDER) do
		local need = costs[res]
		if need then
			seen[res] = true
			local have = QuestHintCost.have(res)
			if have < need then
				return (TEXT[res] or ("Нужно %s: %%d из %%d"):format(res)):format(have, need)
			end
		end
	end
	-- ресурс, которого нет в ORDER: без своей строки, но молчать о нехватке хуже
	for res, need in pairs(costs) do
		if not seen[res] then
			local have = QuestHintCost.have(res)
			if have < need then
				return ("Нужно ещё: %s %d из %d"):format(res, have, need)
			end
		end
	end
	return nil
end

return QuestHintCost
