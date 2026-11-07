local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	СБОРЩИК РЕСУРСОВ (сеть) — где брать модель, как её звать и как класть.

	⚠️ ИМЯ ШАБЛОНА И ИМЯ ПОСТАВЛЕННОЙ КЛЕТКИ — РАЗНЫЕ ВЕЩИ.
	Модель меняют время от времени (была Net_Part, стала Raft_collector). А имя
	«Net_Part» у УЖЕ ПОСТАВЛЕННОЙ клетки — внутренний договор, по которому её узнают
	восемь систем: отцепление плота, укрепление, пиявки, разбор топором, прочность,
	приварка, ловля ресурсов и сама стройка. Переименуешь клон вместе с шаблоном —
	всё это молча отвалится, заодно перестанут читаться старые сейвы.

	⚠️ ПОВОРОТ ИЗМЕРЯЕМ, А НЕ ПРОПИСЫВАЕМ КОНСТАНТОЙ.
	Раньше поправка лежала числом сразу в ТРЁХ файлах, с припиской «править во всех
	трёх копиях». Пока модель не менялась, это работало. Стоило заменить её на
	Raft_collector — сеть встала на ребро, потому что у новой модели свой поворот от
	импортёра, а константа осталась от старой. Тот же приём, что у грядки
	(PlanterService): смотрим на габарит и кладём ТОНКУЮ ОСЬ в Y. Следующая замена
	модели переживётся сама, и держать три копии в синхроне больше не надо.
]]

local RaftNetFit = {}

-- Имена шаблона по предпочтению: сначала новая модель, потом старая — чтобы плейс,
-- где новую ещё не положили, продолжал работать.
RaftNetFit.TEMPLATE_NAMES = { "Raft_collector", "Net_Part" }

-- Как зовётся ПОСТАВЛЕННАЯ клетка. Не трогать: см. предупреждение выше.
RaftNetFit.PLACED_NAME = "Net_Part"

-- ⚠️ ПОВОРОТ — ЯВНЫЕ ЧИСЛА, А НЕ АВТОЗАМЕР.
-- Сначала здесь стоял подбор поворота по габариту (как у грядки в PlanterService).
-- На этой модели он не сработал: ОБА габарита — и в осях пивота, и в осях мира —
-- намерились плоскими (10.00 × 2.16 × 10.00), то есть по замеру крутить нечего, а
-- на плоту сеть всё равно вставала на ребро. Значит поворот приходит не из
-- габарита, и подбирать его по числам бессмысленно: ставим то, что видно глазами.
-- Замер остался только в печати — он информация, а не решение.
--
-- Крутить надо ЭТИ РУЧКИ, по одной за раз. Порядок применения — снизу вверх по
-- этому списку, и он важен (см. сборку в rotFix):
--   TILT_AXIS/TILT_DEG — класть плашмя. Первый заход был по X, правильной оказалась Z.
--   SPIN_DEG — разворот вокруг ВЕРТИКАЛИ КЛЕТКИ. Подобран, работает: не трогать без
--              нужды. Менять его, чтобы «довернуть», уже пробовали — модель при этом
--              снова встаёт на ребро, потому что этот поворот идёт ПОВЕРХ наклона.
--   ROLL_DEG — доворот в СОБСТВЕННЫХ осях модели. Вот эту и крутить, когда лежит
--              правильно, но смотрит не туда: она вертит модель на месте и на то,
--              как она лежит, не влияет. Ушло не в ту сторону — смени знак.
--   OWN2_AXIS/OWN2_DEG — второй доворот в собственных осях. Пробовали Y — модель
--              снова встала на ребро, значит после наклона своя Y лежит горизонтально.
--              Осталась Z, она сейчас и стоит.
--
-- ⚠️ ПОДБИРАТЬ ЭТО ГЛАЗАМИ ЧЕРЕЗ ЛОГ — ДОРОГО. По одному повороту за запуск ушло
-- четыре круга. Поэтому в режиме стройки на сеть повешена клавиша R: она крутит
-- призрак живьём и печатает накопленный угол. Дожал глазами — перенеси число сюда,
-- в OWN2_DEG, и R больше не нужна (см. _G.NetDevSpin в BuildingSystem.client).
-- ⚠️ СВОИХ ПОВОРОТОВ У СЕТИ НЕТ. ОНА СТАВИТСЯ РОВНО КАК ДОСКА ПОЛА.
-- Здесь долго подбирались углы — наклон, разворот, довороты по своим осям, — и
-- каждый следующий портил предыдущий. Разгадка оказалась в самой модели: у
-- Raft_collector в PivotOffset прописан поворот (90, 0, 0) и сдвиг по Y, то есть
-- автор УЖЕ привёл её к той же конвенции пивота, что у Raft_part. Модель приходит
-- ориентированной правильно, и любая наша поправка сверху её ломала.
--
-- Осталась ровно одна поправка, и она ВЫВОДИТСЯ, а не подбирается.
-- PivotOffset Orientation = (90, 0, 0) значит: пивот повёрнут на +90° по X
-- относительно деталей. PivotTo(cf) ставит по этому CFrame ПИВОТ, поэтому детали
-- оказываются повёрнуты на −90° по X относительно cf — и сеть стоит стеной.
-- Гасится это домножением СПРАВА на +90° по X: тогда пивот встаёт наклонённым, а
-- детали — ровно по клетке.
--   PivotOffset изменят на (0,0,0) → поставь здесь 0.
--   Появится ещё какой-то поворот в PivotOffset → его и компенсируй, с обратным знаком.
--
-- Почему -90, а не +90: оба кладут сеть плашмя, но +90 разворачивал её полотном
-- ВНИЗ. Разница ровно 180° по той же оси, поэтому знак и решает, куда смотрит сеть.
local PIVOT_FIX_X_DEG = -90

-- Два разных габарита, и путать их не надо:
--   GetBoundingBox() меряет в осях ПИВОТА — геометрию ОТНОСИТЕЛЬНО пивота;
--   GetExtentsSize() меряет по осям МИРА — как модель лежит в хранилище.
-- Оба намерили 10.00 × 2.16 × 10.00, и на этом я решил, что пивот ровный, — а он
-- повёрнут на 90° по X, просто это записано в PivotOffset, которого не видит ни
-- один из двух замеров. Мораль: ориентацию модели по габаритам не узнать вовсе,
-- смотреть надо PivotOffset в Studio.
local function sizesOf(template)
	if template:IsA("Model") then
		local _, local_ = template:GetBoundingBox()
		return local_, template:GetExtentsSize()
	elseif template:IsA("BasePart") then
		return template.Size, template.Size
	end
	return nil, nil
end

local cached, cachedFor = nil, nil

--[[ Поправка поворота для этого шаблона. Считается один раз на шаблон. ]]
function RaftNetFit.rotFix(template)
	if not template then return CFrame.identity end
	if cachedFor == template and cached then return cached end

	-- Печатаем габариты просто чтобы их было видно: пригодятся, если модель заменят
	-- и что-то не сойдётся. Решения они не принимают — см. предупреждение выше.
	local locSize, worldSize = sizesOf(template)
	if locSize and worldSize then
		print(("[Сборщик] %s: в осях пивота %.2f × %.2f × %.2f | в осях мира %.2f × %.2f × %.2f "
			.. "| гасим поворот пивота: +%d° по X")
			:format(template.Name, locSize.X, locSize.Y, locSize.Z,
				worldSize.X, worldSize.Y, worldSize.Z, PIVOT_FIX_X_DEG))
	end

	cached = CFrame.Angles(math.rad(PIVOT_FIX_X_DEG), 0, 0)
	cachedFor = template
	return cached
end

--[[ ⚠️ ВЕРХ ПАЛУБЫ — ОДНА ФУНКЦИЯ НА КЛИЕНТ И СЕРВЕР.
     Раньше эта мера жила только в BuildingSystem на сервере, а клиентским
     призракам приходилось угадывать высоту от пивота плота. Из-за этого
     лебёдка якоря вставала выше, чем показывал призрак: одна сторона мерила
     настил, другая — корпус.
     Считаем по САМОМУ ЧАСТОМУ верху досок, а не по среднему и не по первой
     попавшейся: на плоту бывают доски, приподнятые постройками, и среднее
     уехало бы за ними. Корзина в четверть студа гасит дрожание физики.
     Запасной ответ — уровень PrimaryPart: он заведомо не тот, зато не nil, и
     постройка не улетит в ноль координат. ]]
function RaftNetFit.deckTopY(raft)
	if not raft then return 0 end
	local counts, reps = {}, {}
	for _, child in ipairs(raft:GetChildren()) do
		if child.Name == "Raft_part" and child ~= raft.PrimaryPart then
			local pos, size
			if child:IsA("Model") then
				local ok, c, sz = pcall(function()
					local a, b = child:GetBoundingBox()
					return a, b
				end)
				if ok and c and sz then pos, size = c.Position, sz end
			elseif child:IsA("BasePart") then
				pos, size = child.Position, child.Size
			end
			if pos and size then
				local top = pos.Y + size.Y * 0.5
				local key = math.round(top * 4)   -- корзина 0.25 студа
				counts[key] = (counts[key] or 0) + 1
				reps[key] = reps[key] or top
			end
		end
	end
	local bestKey, bestN
	for k, n in pairs(counts) do
		if not bestN or n > bestN then bestKey, bestN = k, n end
	end
	if bestKey then return reps[bestKey] end
	return raft.PrimaryPart and raft.PrimaryPart.Position.Y or 0
end

--[[ ⚠️ ВЫСОТА ЦЕНТРА ДОСКИ НАД ПИВОТОМ ПЛОТА — ТА САМАЯ, БЕЗ КОТОРОЙ
     ПОСТРОЙКА ВСТАЁТ НЕ НА СВОЙ УРОВЕНЬ.
     Пол и сеть прибавляют её к смещению клетки (см. deckCenterRestY в
     BuildingSystem, обе копии), а установка якоря — исторически нет: у него
     вертикаль оставалась на уровне PrimaryPart, то есть корпуса. Отсюда и
     «ставится выше, чем надо».
     Голосование, а не среднее: доски, приподнятые постройками, утянули бы
     среднее за собой. Корзина в четверть студа гасит дрожание на волне.
     Замер идёт в осях ПОКОЯ (RestCFrame), поэтому крен от волн в него не
     попадает. ]]
function RaftNetFit.deckCenterRestY(raft)
	local primary = raft and raft.PrimaryPart
	if not primary then return 0 end
	local restCF = primary:GetAttribute("RestCFrame") or primary.CFrame
	local restRot = restCF - restCF.Position
	local counts, reps = {}, {}
	for _, child in ipairs(raft:GetChildren()) do
		if child.Name == "Raft_part" and child ~= primary then
			local centerPos
			if child:IsA("Model") then
				local ok, bb = pcall(function() return child:GetBoundingBox() end)
				centerPos = ok and bb.Position or nil
			elseif child:IsA("BasePart") then
				centerPos = child.Position
			end
			if centerPos then
				local rel = primary.CFrame:PointToObjectSpace(centerPos)
				local y = restRot:VectorToWorldSpace(rel).Y
				local key = math.round(y * 4)
				counts[key] = (counts[key] or 0) + 1
				reps[key] = reps[key] or y
			end
		end
	end
	local bestKey, bestN
	for k, n in pairs(counts) do
		if not bestN or n > bestN then bestKey, bestN = k, n end
	end
	return bestKey and reps[bestKey] or 0
end

return RaftNetFit
