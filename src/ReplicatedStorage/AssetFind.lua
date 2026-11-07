local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	Поиск шаблона в ReplicatedStorage по имени — ГДЕ БЫ ОН НИ ЛЕЖАЛ.

	⚠️ FindFirstChild("Имя") ЗАВИСИТ ОТ РАСКЛАДКИ ПАПОК, А ОНА МЕНЯЕТСЯ.
	Модели в хранилище время от времени раскладывают по папкам (Buildings_Raft/
	Floor, Walls, Survival_parts) — и каждый такой разбор ломает всё, что искало
	шаблон прямым ребёнком.

	Хуже всего это выглядит у WaitForChild: скрипт не падает с ошибкой, а МОЛЧА
	ВИСИТ на первой строке. Так пропала вся стройка — молоток в руках, а меню не
	открывается, и в логе при этом ни слова. Отсюда правило: шаблон ищем по
	имени, а не по месту.

		local AssetFind = require(ReplicatedStorage.AssetFind)
		local tpl = AssetFind.find("Raft_part")          -- сразу, может вернуть nil
		local tpl = AssetFind.wait(20, "Raft_part")      -- подождать репликации

	Скрипты и модули этим искать НЕ надо: они лежат в корне намеренно, и там их
	место — часть договорённости, а не случайность.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetFind = {}

-- Ищем именно ассет, а не что попало с тем же именем: рядом с моделью нередко
-- лежит одноимённый скрипт или ObjectValue, и он бы выиграл поиск.
local function isAsset(inst)
	return inst:IsA("Model") or inst:IsA("BasePart") or inst:IsA("Tool")
end

-- ⚠️ ШАБЛОН НЕ ЛЕЖИТ ВНУТРИ ДРУГОЙ МОДЕЛИ.
-- Рекурсивный поиск возвращает ПЕРВОЕ совпадение по дереву, а имя может
-- встретиться и внутри чужой модели: у настила плота, например, есть деталь с
-- тем же именем внутри укреплённой доски. Тогда «полом» становился кусок другой
-- постройки — в меню и в призраке появлялась связка брёвен вместо настила.
-- Настоящий шаблон лежит в папках (Buildings_Raft/Floor), а не в чужой модели,
-- поэтому такие кандидаты предпочитаем, и лишь если их нет — берём что нашлось.
local function insideAnotherModel(inst)
	local node = inst.Parent
	while node and node ~= ReplicatedStorage do
		if node:IsA("Model") then return true end
		node = node.Parent
	end
	return false
end

-- Глубина от корня хранилища: у прямого ребёнка 0, внутри одной папки 1 и так далее.
local function depthOf(inst)
	local d, node = 0, inst.Parent
	while node and node ~= ReplicatedStorage do
		d += 1
		node = node.Parent
	end
	return d
end

-- ⚠️ ТЁЗОК В ХРАНИЛИЩЕ БОЛЬШЕ ОДНОГО — БЕРЁМ САМОГО БЛИЗКОГО К КОРНЮ.
-- Порядок GetDescendants — не договор, а как легло дерево, и «первое совпадение»
-- на тёзках означает «повезёт или нет». Так в океане вместо привычной листвы
-- начала спавниться островная: обе модели зовутся leaves, и перебор дошёл до
-- островной первой.
-- Прежний код смотрел ТОЛЬКО прямых детей, поэтому промахнуться не мог вовсе.
-- Естественное продолжение этого правила, когда ассеты разложили по папкам, —
-- «чем ближе к корню, тем вероятнее это тот самый шаблон»: рабочие модели уехали
-- из корня на один уровень, в свою папку, а чужие тёзки лежат глубоко, внутри
-- сцен и наборов. При равной глубине берём первого попавшегося, но об этом
-- ГРОМКО сообщаем: разобрать такое по имени уже нельзя, надо переименовывать.
local warnedAmbiguous = {}
local function deepFind(name, ok)
	local best, bestDepth, ties = nil, math.huge, 0
	local fallback
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d.Name == name and ok(d) then
			if insideAnotherModel(d) then
				fallback = fallback or d
			else
				local depth = depthOf(d)
				if depth < bestDepth then
					best, bestDepth, ties = d, depth, 1
				elseif depth == bestDepth then
					ties += 1
				end
			end
		end
	end
	if ties > 1 and not warnedAmbiguous[name] then
		warnedAmbiguous[name] = true
		warn(("[AssetFind] «%s» в хранилище встречается %d раза на одной глубине — "
			.. "выбран %s. Разобрать по имени нельзя, переименуй лишние.")
			:format(name, ties, best:GetFullName()))
	end
	return best or fallback
end

local function lookup(names, ok)
	--[[ ⚠️ ШАБЛОН С ТЕГОМ PreferredTemplate ВЫИГРЫВАЕТ У ТЁЗОК. Новые версии
	     построек (уровни апгрейда: Raft_fishing_spot, Raft_farmer_hut) приезжают
	     из Rojo, а в плейсе могут лежать старые модели с тем же именем — и на
	     той же глубине. Тег стоит на новых шаблонах, по нему и берём. ]]
	local tagged = game:GetService("CollectionService"):GetTagged("PreferredTemplate")
	for _, n in ipairs(names) do
		for _, t in ipairs(tagged) do
			if t.Name == n and t:IsDescendantOf(ReplicatedStorage) and ok(t) then return t end
		end
	end
	-- сперва корень: там лежит большинство, и это самый дешёвый путь
	for _, n in ipairs(names) do
		local t = ReplicatedStorage:FindFirstChild(n)
		if t and ok(t) then return t end
	end
	for _, n in ipairs(names) do
		local t = deepFind(n, ok)
		if t then return t end
	end
	-- и напоследок без учёта регистра: модели приезжают то raft_wall, то Raft_wall.
	-- Тот же порядок предпочтения, что выше: ближе к корню — вероятнее нужное.
	local want = {}
	for _, n in ipairs(names) do want[n:lower()] = true end
	local best, bestDepth = nil, math.huge
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if want[d.Name:lower()] and ok(d) then
			local depth = depthOf(d)
			if depth < bestDepth then best, bestDepth = d, depth end
		end
	end
	return best
end

--[[ Имена перечисляются по предпочтению: первое найденное и берём. ]]
function AssetFind.find(...)
	return lookup({ ... }, isAsset)
end

--[[ То же, но с ожиданием: на клиенте ассет может ещё не приехать.
     Возвращает nil по истечении срока — в отличие от WaitForChild, который
     будет ждать вечно и утащит за собой весь скрипт. ]]
function AssetFind.wait(timeout, ...)
	local names = { ... }
	local deadline = os.clock() + (timeout or 0)
	while true do
		local t = lookup(names, isAsset)
		if t then return t end
		if os.clock() >= deadline then return nil end
		task.wait(0.1)
	end
end

--[[ ⚠️ НЕ ВСЁ, ЧТО ЛОМАЕТСЯ ОТ ПАПОК, — МОДЕЛЬ.
     По папкам раскладывают и звуки, и анимации, а find их не отдаст: он нарочно
     отсеивает всё, кроме Model/BasePart/Tool, чтобы вместо модели не подсунуть
     одноимённый скрипт. Из-за этого анимация питья и звук поломки инструмента
     оставались на прямом FindFirstChild и ждали своей очереди сломаться.

         local anim = AssetFind.findClass("Animation", "R6 Drinking Animation")
         local snd  = AssetFind.findClass("Sound", "Wood Break")
]]
function AssetFind.findClass(className, ...)
	local ok = function(inst) return inst:IsA(className) end
	return lookup({ ... }, ok)
end

--[[ ⚠️ ШАБЛОН МОЖЕТ НАЗЫВАТЬСЯ С ХВОСТОМ, А ВНУТРИ НЕГО ЛЕЖИТ ТЁЗКА.
     Турели ПВО хранятся как «Deffender_1», «Deffender_2», а ищут их по «Deffender»,
     и раньше это работало от обратного: точный поиск по прямым детям НЕ находил
     ничего, и в дело шёл перебор по префиксу, который и возвращал модель.

     После перевода на find всё сломалось хитро: внутри «Deffender_1» есть ДЕТАЛЬ
     ровно с именем «Deffender» — крепление, жёсткий корень турели (AADefense,
     BASE_NAME). Точного совпадения верхним уровнем нет, поэтому find отдавал её
     запасной веткой «взять что нашлось», перебор по префиксу уже не выполнялся, и
     клонировалась ОДНА деталь: габарит неверный, велдов к плоту ноль, турель не
     собиралась вовсе. Ошибки при этом никакой.

     Поэтому здесь кандидаты ВНУТРИ чужих моделей не берём ни при каких условиях —
     шаблон постройки не может лежать внутри другой постройки. Заодно перебор по
     префиксу идёт по всему хранилищу, а не по прямым детям: сам этот перебор был
     ровно такой же миной, просто до неё ещё не дошли.

         AssetFind.findPrefix("Deffender")   -- вернёт модель Deffender_1 ]]
function AssetFind.findPrefix(...)
	local names = { ... }
	local all = ReplicatedStorage:GetDescendants()

	-- сперва точное имя: «Torch» не должен превратиться в «Torch_broken»
	for _, n in ipairs(names) do
		for _, d in ipairs(all) do
			if d.Name == n and isAsset(d) and not insideAnotherModel(d) then return d end
		end
	end
	for _, n in ipairs(names) do
		for _, d in ipairs(all) do
			if isAsset(d) and not insideAnotherModel(d) and d.Name:sub(1, #n) == n then
				return d
			end
		end
	end
	return nil
end

--[[ Все кандидаты с таким именем — для диагностики, когда «нашлось не то». ]]
function AssetFind.candidates(name)
	local out = {}
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d.Name == name and isAsset(d) then table.insert(out, d) end
	end
	return out
end

--[[ ⚠️ ТЁЗКИ РАЗВОДЯТСЯ СОСЕДСТВОМ, А НЕ ИМЕНЕМ.
     Имя «leaves» в хранилище носят и океанская листва, и островная. Ни глубина,
     ни порядок обхода их не различают: лежат обе одинаково, просто в разных
     папках. Различает их ОКРУЖЕНИЕ — океанские ресурсы разложены вместе, рядом с
     бревном, а островные вместе со своим островом.
     Поэтому берём заведомо правильного соседа (бревно резолвится верно — брёвна
     из океана приплывают те самые) и ищем тёзку В ЕГО ЖЕ ПАПКЕ. Это не зависит
     от того, как именно разложены папки: переложат всю пачку — переложится и
     эталон, правило продолжит работать.

         local anchor = AssetFind.find("Log")
         local tpl = AssetFind.findNear(anchor, "leaves")
]]
function AssetFind.findNear(reference, ...)
	local names = { ... }
	local folder = reference and reference.Parent
	if folder then
		for _, n in ipairs(names) do
			local sibling = folder:FindFirstChild(n)
			if sibling and isAsset(sibling) then return sibling end
		end
	end
	-- эталона нет или соседа рядом с ним не оказалось — обычный поиск
	return lookup(names, isAsset)
end

--[[ findClass с ожиданием — на случай, когда ассет ещё не приехал к клиенту. ]]
function AssetFind.waitClass(timeout, className, ...)
	local names = { ... }
	local ok = function(inst) return inst:IsA(className) end
	local deadline = os.clock() + (timeout or 0)
	while true do
		local t = lookup(names, ok)
		if t then return t end
		if os.clock() >= deadline then return nil end
		task.wait(0.1)
	end
end

return AssetFind
