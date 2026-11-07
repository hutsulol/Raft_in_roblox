--[[
	СТАРТОВЫЙ ОСТРОВ — СЦЕНАРИЙ.

	Ведёт начало сцены — от «на горизонте что-то есть» до высадки на берег:

	  1. второй день, 30% дня — поднимает остров строго по курсу плота;
	  2. шлёт клиентам катсцену (StartIsleCutscene.client), после неё игрок
	     думает вслух про найденную землю;
	  3. выдаёт квест «Земля по курсу» и следит, когда игрок реально СТУПИТ на
	     остров.

	Дальше ведёт сама цепочка квестов (CHAIN в QuestState): корова → мясо на
	углях → весло. Мысли между звеньями шлёт она же (CHAIN_THOUGHT) — здесь их
	дублировать нельзя, окно диалога одно и вторая реплика затрёт первую.

	⚠️ ДЕНЬ ЖИВЁТ РОВНО ОДНУ СЕССИЮ СЕРВЕРА.
	ReplicatedStorage.DayCount создаётся со значением 1 при каждом старте и нигде
	не сохраняется. То есть это «второй день ЭТОГО сервера», а не второй день
	прогресса игрока: перезашёл в новый сервер — сцена сыграет заново примерно
	через десять минут. Иначе и быть не может, пока день не попал в сейв.
]]

local Lighting          = game:GetService("Lighting")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local ISLAND_NAME = "StartIsle_SCENE"

local STORY_DAY      = 2      -- на какой день поднимаем
local STORY_FRACTION = 0.30   -- в какой момент дня (0 — рассвет, 1 — закат)

-- ⚠️ БЛИЖЕ, ЧЕМ ШТАТНЫЕ ОСТРОВА, И СТРОГО ПО КУРСУ.
-- Обычные встают за 1700–1900 студов в случайном секторе впереди — «еле видно
-- на горизонте». Плот идёт по прямой и сам никуда не сворачивает (руля в игре
-- нет), так что случайный сектор означал бы «квест на удачу». 520–620 студов по
-- носу — это минута с небольшим хода: остров успевает побыть точкой на
-- горизонте и всё-таки приходит сам.
local DIST_MIN, DIST_MAX = 520, 620

local SCOUT_QUEST = "startisle_scout"

--[[ ⚠️ КАТСЦЕНА НЕ СРАЗУ, А ЧЕРЕЗ ПАУЗУ ПОСЛЕ ПОДЪЁМА ОСТРОВА.
     Она запускалась в тот же кадр, что и появление острова, — и камера
     показывала пустой горизонт: модель у клиента ещё не прогрузилась. «Земля!»
     звучало раньше самой земли.
     Сервер ставит остров мгновенно, а клиенту нужно время скачать и отрисовать
     модель, и сколько именно — зависит от связи. Десять секунд, о которых
     просил владелец, покрывают этот разброс с запасом и заодно дают плоту
     подойти ближе, так что остров в кадре крупнее. ]]
local CUTSCENE_DELAY = 10

-- Через сколько после появления острова выдавать первый квест: катсцена идёт
-- 8 секунд, потом мысль. Квест поверх мысли — это два окна разом.
-- ⚠️ Отсчёт от ПОДЪЁМА, а не от катсцены, поэтому пауза перед ней входит сюда
-- же: подвинешь одну — подвинь и другую, иначе квест придёт во время сцены.
local QUEST_DELAY = CUTSCENE_DELAY + 13

local POLL = 1        -- как часто проверяем, не сошёл ли кто на берег
local FOOT_RAY = 14   -- насколько глубоко щупаем под ногами

-- ⚠️ РЯДОМ СО СТАРТОВЫМ ОСТРОВОМ ЧУЖИХ БЫТЬ НЕ ДОЛЖНО.
-- Таймер островов в WorldEventSpawner крутится сам по себе и о сцене не знает:
-- он ронял случайный остров в ту же минуту, и игрок видел на горизонте два
-- сразу — с квестом «сойди на остров» и без единого намёка, на какой именно.
-- Просим паузу: короткую на подходе ко второму дню (обновляется каждый опрос,
-- поэтому сама рассосётся, если сцена почему-то не сыграет) и полдня после.
-- Полдня — это 190 секунд: день в DayNightCircle длится 380. Число там
-- файловое, наружу не отдано; при смене длины дня поправить и здесь.
local HOLD_HALF_DAY = 190
local HOLD_RUNUP    = 30

-- Клиентам: «поднялся остров, вот его точка».
local foundEvent = Instance.new("RemoteEvent")
foundEvent.Name = "StartIsleFound"
foundEvent.Parent = ReplicatedStorage

-- ⚠️ ТРЕТЬЯ КОПИЯ ЭТОЙ ФУНКЦИИ В ПРОЕКТЕ, И ЭТО НОРМА.
-- Общего модуля времени нет: cycleTime в DayNightCircle — файловая локальная, а
-- наружу отдаются только DayCount и Lighting.ClockTime. Ровно так же считают
-- долю дня WaveDirector и PiratePatrolBoat — требовать здесь нечего.
local function dayProgress()
	local t = Lighting.ClockTime
	if t >= 6 and t < 18 then return (t - 6) / 12 end
	return nil   -- ночь: доли дня не существует
end

-- Центр СУШИ острова: по нему целится камера катсцены. Считаем по тайлам
-- рельефа, а не по габариту модели — у неё есть плита дна 2048×2048, и центр по
-- ней уехал бы под воду и в сторону.
local LAND_PREFIX = "island_terrain"

local function landCenter(island)
	local lo, hi
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:lower():sub(1, #LAND_PREFIX) == LAND_PREFIX then
			local half = d.Size * 0.5
			local a, b = d.Position - half, d.Position + half
			lo = lo and Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z)) or a
			hi = hi and Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z)) or b
		end
	end
	if not lo then return island:GetPivot().Position end
	return (lo + hi) * 0.5
end

-- Наружу: тем же центром суши пользуется население острова, когда точки коровы
-- в модели не оказалось (StartIsle.server.lua). Считать его во второй раз в
-- соседнем файле незачем — расхождение двух копий тут же увело бы корову в воду.
_G.StartIsleLandCenter = landCenter

local islandModel = nil       -- поднятый остров, пока он жив
local sceneStarted = false    -- сцена уже запускалась в этой сессии
local sceneClock = 0          -- os.clock() момента подъёма острова
local holdExpired = false     -- держать остров перестали по таймауту

-- Сколько максимум держим остров от сноса, если сценой не занимаются.
local SCENE_HOLD_MAX = 15 * 60
local reached = {}            -- [player] = true, засчитан сход на берег
-- ⚠️ ОЧЕРЕДЬ ЗАЧЁТОВ ХРАНИМ ПО UserId, А НЕ ПО ОБЪЕКТУ ИГРОКА, И НЕ ЧИСТИМ НА
-- ВЫХОДЕ. Отложенный зачёт может ждать открытия квеста минутами — ровно тот
-- случай, когда игрок успевает выйти и вернуться. По объекту Player запись
-- потерялась бы (после перезахода это уже другой объект), а второй коровы на
-- острове нет: зачёт пропал бы навсегда вместе с остатком цепочки.
local pending = {}            -- [userId] = { [questId] = eventType }
local lastCredit = {}         -- [userId] = os.clock() последнего выданного зачёта

-- ⚠️ ПАУЗА МЕЖДУ ДВУМЯ ЗАЧЁТАМИ ОДНОМУ ИГРОКУ, И ОНА НЕ МАЛЕНЬКАЯ.
-- Закрытие квеста тянет за собой мысль вслух, а окно диалога одно и само не
-- перелистывается: реплики печатаются посимвольно и ждут КЛИКА (DialogueUI).
-- Второй зачёт, пришедший, пока игрок читает, стирает недочитанное и начинает
-- заново с первой строки следующей мысли. Двенадцати секунд хватает прочесть
-- две строки и кликнуть; на обычном ходу игры между высадкой и убитой коровой
-- проходит куда больше.
local CREDIT_GAP = 12

-- ── ОТЛОЖЕННЫЙ ЗАЧЁТ ──
-- ⚠️ СОБЫТИЕ, ПРИШЕДШЕЕ РАНЬШЕ КВЕСТА, ПРОПАДАЕТ БЕССЛЕДНО.
-- QuestState принимает прогресс только по ВЫДАННОМУ квесту (isIssued): у
-- gated-квеста должен стоять unlocked, иначе событие молча выбрасывается — без
-- ошибки и без строчки в логе. Для этой сцены порядок событий не гарантирован
-- ничем: корову видно с воды, и её вполне убивают из пушки ДО того, как игрок
-- сошёл на берег и тем открыл охоту. Событие бы пропало, а второй коровы нет —
-- цепочка вставала бы намертво до конца сессии.
-- Поэтому незачтённое не выбрасываем, а кладём в очередь и пробуем снова.
local function questUnlocked(player, questId)
	if typeof(_G.GetQuestState) ~= "function" then return false end
	-- ⚠️ ВЫШЕДШЕГО НЕ СПРАШИВАЕМ. _G.GetQuestState на незагруженном игроке идёт в
	-- DataStore и ЖДЁТ; за время ожидания игрок мог выйти, и QuestState у себя
	-- уже прибрал его запись — наш запрос воскресил бы её навсегда. Проверку
	-- держим ЗДЕСЬ, вплотную к вызову, а не только на входе в проход дозора:
	-- между ними как раз и происходит ожидание.
	if not player.Parent then return false end
	local s = _G.GetQuestState(player)
	if not s then return false end
	if s.permanentlyCompleted and s.permanentlyCompleted[questId] then return true end
	return s.unlocked and s.unlocked[questId] == true
end

local function tryCredit(player, questId, eventType)
	if not questUnlocked(player, questId) then return false end
	if typeof(_G.OnQuestEvent) ~= "function" then return false end
	pcall(_G.OnQuestEvent, player, eventType, 1)
	lastCredit[player.UserId] = os.clock()
	return true
end

-- Наружу: этим же путём засчитывает убийство коровы StartIsle.server.lua.
_G.StartIsleCredit = function(player, questId, eventType)
	if not (player and typeof(questId) == "string" and typeof(eventType) == "string") then return end
	local id = player.UserId
	-- ⚠️ ПАУЗУ СОБЛЮДАЕМ И ЗДЕСЬ, А НЕ ТОЛЬКО В РАЗБОРЕ ОЧЕРЕДИ.
	-- Иначе игрок, сошедший на берег и тут же добивший корову, получал вторую
	-- мысль поверх первой: прямой зачёт шёл мимо паузы, которая для того и есть.
	if os.clock() - (lastCredit[id] or 0) >= CREDIT_GAP
		and tryCredit(player, questId, eventType) then
		return
	end
	pending[id] = pending[id] or {}
	pending[id][questId] = eventType
	print(("[Стартовый остров] %s: «%s» ещё не выдан — зачёт %s отложен")
		:format(player.Name, questId, eventType))
end

-- ── выдача первого квеста ──
-- gated-квест до этого момента не существует для игрока вовсе: он не показан и
-- не копит прогресс (см. isIssued в QuestState). _G.TrackQuest и открывает его,
-- и ставит на трекер.
local function giveScoutQuest(player)
	if typeof(_G.TrackQuest) ~= "function" then return end
	local state = typeof(_G.GetQuestState) == "function" and _G.GetQuestState(player) or nil
	if state and state.permanentlyCompleted and state.permanentlyCompleted[SCOUT_QUEST] then
		return   -- уже проходил в этой сессии
	end
	pcall(_G.TrackQuest, player, SCOUT_QUEST)
end

-- ── сход на берег ──
-- ⚠️ ЛУЧ ПОД НОГИ, А НЕ РАССТОЯНИЕ ДО ЦЕНТРА.
-- По расстоянию квест закрывался бы с плота, подошедшего к берегу вплотную, —
-- а задача именно СОЙТИ. Луч под ноги отвечает на единственный честный вопрос:
-- на чём игрок стоит.
local function standsOnIsland(player, island)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { island }
	local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -FOOT_RAY, 0), params)
	return hit ~= nil
end

local function creditReached(player)
	if reached[player] then return end
	reached[player] = true
	print(("[Стартовый остров] %s сошёл на берег — «Земля по курсу» закрыта"):format(player.Name))
	-- Вошедшему в уже идущую сцену квест могли ещё не выдать (выдача отложена на
	-- 20 секунд после входа), а сойти на берег он успевает за пять. Через
	-- очередь это не потеря, а отсрочка.
	giveScoutQuest(player)
	_G.StartIsleCredit(player, SCOUT_QUEST, "reached:StartIsle")
end

-- ⚠️ ОСТРОВ ДЕРЖИМ, ПОКА ОН ЕЩЁ НУЖЕН, А НЕ «ДО ПЕРВОГО ШАГА НА БЕРЕГ».
-- Сначала флаг снимался прямо в момент зачёта схода. Тем же событием цепочка
-- открывает охоту, а вся охота стоит на этом острове: плот идёт дальше со
-- скоростью 8 студов в секунду, и через две с половиной минуты отсечка сносила
-- остров вместе с живой коровой — и вместе с игроком, который на нём стоял.
-- Условие пересчитываем каждый тик, разбор — у updateKeepAlive ниже.
local function cowAlive()
	if not (islandModel and islandModel.Parent) then return false end
	local animals = islandModel:FindFirstChild("Animals")
	local cow = animals and animals:FindFirstChild("Cow_Cow_1")
	local hum = cow and cow:FindFirstChildWhichIsA("Humanoid")
	return hum ~= nil and hum.Health > 0
end

-- Мясо, упавшее с туши, лежит внутри модели острова (см. spawnDrops в
-- AnimalLife). Пока оно там — охота не доведена до конца.
local function meatOnIsland()
	if not (islandModel and islandModel.Parent) then return false end
	for _, d in ipairs(islandModel:GetChildren()) do
		if d.Name == "Meat" then return true end
	end
	return false
end

local function updateKeepAlive()
	if not (islandModel and islandModel.Parent) then return end

	-- ⚠️ ПРИЧИН ДЕРЖАТЬ ОСТРОВ ЧЕТЫРЕ, И ПЕРВАЯ ВАЖНЕЕ ВСЕХ.
	-- Сперва условие было «корова жива или на берегу кто-то стоит» — и оно
	-- рассыпалось ровно на том пути, ради которого делалась очередь зачётов:
	-- корову убивают с плота ДО высадки, она мертва, на берегу никого — остров
	-- тут же переставал держаться и через две с половиной минуты сносился вместе
	-- с невыполненной «Землёй по курсу» и с мясом, которое лежит внутри него.
	local keep = false
	if not next(reached) then
		keep = true          -- ещё никто не сходил на берег: цель первого квеста
	elseif cowAlive() or meatOnIsland() then
		keep = true          -- охота не закончена: и зверь, и добыча живут здесь
	else
		for _, plr in ipairs(Players:GetPlayers()) do
			if standsOnIsland(plr, islandModel) then keep = true break end
		end
	end

	-- ⚠️ НО НЕ ВЕЧНО.
	-- Если сцену просто проигнорировали — корова жива, на берег никто не вышел —
	-- условие выше держало бы остров до конца сессии: 78 тысяч треугольников у
	-- каждого клиента и один из шести слотов спавнера занят навсегда. Через
	-- четверть часа отпускаем: за это время сцену либо прошли, либо не собирались.
	if keep and os.clock() - sceneClock > SCENE_HOLD_MAX then
		keep = false
		if not holdExpired then
			holdExpired = true
			print("[Стартовый остров] прошло 15 минут, сценой не заинтересовались — отпускаем остров")
		end
	end

	if islandModel:GetAttribute("KeepAlive") ~= keep then
		islandModel:SetAttribute("KeepAlive", keep)
		if not keep and not holdExpired then
			print("[Стартовый остров] сцена отыграна — остров больше не держим")
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	reached[player] = nil
	-- pending и lastCredit НЕ трогаем: они по UserId и ждут возвращения игрока
end)

-- Разбор очереди отложенных зачётов: по одному за раз и не чаще CREDIT_GAP —
-- иначе две мысли подряд затрут друг друга в единственном окне диалога.
local function flushPending(player)
	local queue = pending[player.UserId]
	if not queue then return end
	if os.clock() - (lastCredit[player.UserId] or 0) < CREDIT_GAP then return end

	for questId, eventType in pairs(queue) do
		-- «Землю по курсу» открываем мы сами, и попытка могла провалиться из-за
		-- ещё не загруженного состояния квестов — пробуем снова. Остальные звенья
		-- открывает цепочка по закрытию предыдущего, тут нам делать нечего.
		if questId == SCOUT_QUEST then giveScoutQuest(player) end
		if tryCredit(player, questId, eventType) then
			queue[questId] = nil
			print(("[Стартовый остров] %s: отложенный зачёт %s засчитан")
				:format(player.Name, eventType))
			return   -- по одному за проход
		end
	end
end

-- Вошёл, когда остров уже стоит: катсцену не повторяем (она про момент
-- появления), но квест выдаём — иначе игрок видит остров и не понимает, зачем.
Players.PlayerAdded:Connect(function(player)
	task.delay(20, function()
		if islandModel and islandModel.Parent and player.Parent then
			giveScoutQuest(player)
		end
	end)
end)

-- ── подъём острова ──
-- ⚠️ ЗАЩЁЛКА ОДНА НА ОБА ВХОДА — И РАСПИСАНИЕ, И КНОПКУ.
-- Раньше «сцена сыграла» знал только поток расписания, своей локальной
-- переменной. Тестовая кнопка поднимала остров мимо неё — и ровно тот случай,
-- ради которого кнопка сделана («не дожидаясь второго дня»), гарантированно
-- давал ВТОРОЙ подъём через десять минут: два клона в Workspace, две коровы,
-- вторая катсцена поверх уже пройденной сцены и повторная выдача квеста.
-- Ставим ДО подъёма: неудачная попытка не должна повторяться каждые две
-- секунды — если модели нет, об этом сказано в логе один раз, и хватит.
local function raiseIsland()
	if sceneStarted then return false, "сцена уже запускалась" end
	sceneStarted = true

	if typeof(_G.SpawnIsland) ~= "function" then
		warn("[Стартовый остров] _G.SpawnIsland не найден — WorldEventSpawner не загрузился?")
		return false
	end
	local ok, why = _G.SpawnIsland({
		name = ISLAND_NAME,
		straight = true,
		distMin = DIST_MIN,
		distMax = DIST_MAX,
	})
	if not ok then
		warn("[Стартовый остров] не поднялся: " .. tostring(why))
		return false
	end

	islandModel = Workspace:FindFirstChild(ISLAND_NAME)
	if not islandModel then
		warn("[Стартовый остров] поднялся, но модели в Workspace нет — некуда целить катсцену")
		return false
	end
	-- пока квест не закрыт, остров не сносим (см. отсечку в WorldEventSpawner)
	islandModel:SetAttribute("KeepAlive", true)
	sceneClock = os.clock()

	-- полдня без чужих островов: пусть этот побудет единственным на горизонте
	if typeof(_G.HoldIslandSpawns) == "function" then
		_G.HoldIslandSpawns(HOLD_HALF_DAY)
	end

	-- ⚠️ ФЛАГ СЦЕНЫ ПОДНИМАЕМ ТОЛЬКО КОГДА ОСТРОВ УЖЕ СТОИТ В МИРЕ.
	-- Сначала он ставился в начале функции, до вызова спавнера, — и все три
	-- неудачных выхода выше оставляли его поднятым. Сервер, где остров так и не
	-- всплыл (модели нет в ReplicatedStorage, плот не собран), всю сессию
	-- утверждал бы, что сцена идёт: меню квестов пускало бы её карточки рядом с
	-- онбордингом, а самих целей в мире нет. Флаг живёт одну сессию сервера и из
	-- прошлого забега не переносится — в отличие от сохранённых квестов.
	Workspace:SetAttribute("StartIsleScene", true)

	local target = landCenter(islandModel)
	print(("[Стартовый остров] поднят по курсу, центр суши %.0f %.0f %.0f")
		:format(target.X, target.Y, target.Z))

	--[[ ⚠️ ЦЕЛЬ ПЕРЕСЧИТЫВАЕМ В МОМЕНТ ЗАПУСКА, А НЕ СЕЙЧАС.
	     За десять секунд остров никуда не денется, но снестись — может: его
	     мог убрать тот же спавнер, если что-то пойдёт не так. Считать по
	     мёртвой модели значит навести камеру в пустоту. Нет модели — сцену
	     просто не запускаем. ]]
	task.delay(CUTSCENE_DELAY, function()
		if not (islandModel and islandModel.Parent) then
			warn("[Стартовый остров] к моменту катсцены модели уже нет — сцену пропускаем")
			return
		end
		foundEvent:FireAllClients(landCenter(islandModel))
		print(("[Стартовый остров] катсцена запущена через %d с после подъёма")
			:format(CUTSCENE_DELAY))
	end)
	task.delay(QUEST_DELAY, function()
		for _, plr in ipairs(Players:GetPlayers()) do
			giveScoutQuest(plr)
		end
	end)
	return true
end

--[[ ── ОСТРОВ ИЗ СЕЙВА ──
     Флаг StartIsleScene приезжает из сейва (RaftSaveSystem, wsFlags), сам
     остров — чуть позже, из мировых данных. Раз сцена уже была, поднимать
     остров и играть катсцену второй раз нельзя: принимаем восстановленный.
     Если остров так и не появился (старый сейв без него) — поднимаем по
     расписанию, как обычно. ]]
-- сюжет пройден хотя бы у одного игрока (квест startisle_cow закрыт навсегда)
local function storyDone()
	if typeof(_G.GetQuestState) ~= "function" then return false end
	for _, plr in ipairs(Players:GetPlayers()) do
		local ok, st = pcall(_G.GetQuestState, plr)
		if ok and type(st) == "table" and st.permanentlyCompleted and st.permanentlyCompleted["startisle_cow"] then
			return true
		end
	end
	return false
end

local function adoptSavedIsland()
	if sceneStarted or Workspace:GetAttribute("StartIsleScene") ~= true then return false end
	sceneStarted = true
	task.spawn(function()
		local m
		for _ = 1, 80 do
			m = Workspace:FindFirstChild(ISLAND_NAME)
			if m then break end
			task.wait(0.5)
		end
		if not m then
			-- острова в сейве нет: если сюжет уже пройден, поднимать его заново
			-- незачем; если нет — поднимаем по расписанию, как обычно
			if storyDone() then
				print("[Стартовый остров] остров из сейва не пришёл, но сюжет пройден — не поднимаем")
				return
			end
			warn("[Стартовый остров] флаг сцены из сейва есть, а острова нет — поднимаем по расписанию")
			sceneStarted = false
			raiseIsland()
			return
		end
		islandModel = m
		sceneClock = os.clock()
		m:SetAttribute("KeepAlive", true)
		print("[Стартовый остров] остров из сейва принят — катсцена не повторяется")
	end)
	return true
end

-- ── расписание ──
-- ⚠️ СРАВНИВАЕМ ЧЕРЕЗ >=, А НЕ ЧЕРЕЗ ==, И ЗАЩЁЛКИВАЕМ ДО ВЫЗОВА.
-- ClockTime двигается шагами по 0.25 секунды (SUN_STEP в DayNightCircle — так
-- гасят мерцание теней), поэтому ровно 0.30 не наступит никогда. А защёлка до
-- вызова нужна, чтобы неудачная попытка не повторялась каждые две секунды.
task.spawn(function()
	local dayValue = ReplicatedStorage:WaitForChild("DayCount", 30)
	if not dayValue then
		warn("[Стартовый остров] нет ReplicatedStorage.DayCount — расписание не работает")
		return
	end

	while true do
		task.wait(2)
		if adoptSavedIsland() then continue end
		if sceneStarted then break end
		if storyDone() then
			sceneStarted = true
			print("[Стартовый остров] сюжет уже пройден в этом сейве — остров по расписанию не поднимаем")
			break
		end
		local p = dayProgress()
		if p and dayValue.Value >= STORY_DAY then
			-- ⚠️ ПАУЗУ ДЕРЖИМ УЖЕ НА ПОДХОДЕ, А НЕ ТОЛЬКО ПОСЛЕ ПОДЪЁМА.
			-- Случайный остров, всплывший за минуту ДО сцены, испортит её так же,
			-- как всплывший через минуту после: катсцена наведётся на свой, а на
			-- горизонте будет стоять чужой. Просьба короткая и обновляется каждый
			-- опрос — если сцена не сыграет (ночь, нет модели), пауза сама лопнет
			-- через полминуты и таймер вернётся к обычной работе.
			if typeof(_G.HoldIslandSpawns) == "function" then
				_G.HoldIslandSpawns(HOLD_RUNUP)
			end
			if p >= STORY_FRACTION then
				raiseIsland()   -- защёлку ставит он сам, одну на расписание и кнопку
			end
		end
	end
end)

-- ── наблюдение за игроками ──
-- ⚠️ РАБОТУ ПО ИГРОКУ ВЕДЁМ В ОТДЕЛЬНОМ ПОТОКЕ, А НЕ В ТЕЛЕ ЦИКЛА.
-- Проверка «выдан ли квест» читает состояние квестов, а оно на только что
-- вошедшем игроке ещё грузится из DataStore — и это ЖДУЩИЙ вызов. В теле цикла
-- он останавливал бы весь дозор: пока грузится один, у остальных не проверяется
-- ни сход на берег, ни очередь. Флаг busy не даёт накопить хвост из потоков,
-- если загрузка затянулась.
local busy = {}

task.spawn(function()
	while true do
		task.wait(POLL)
		updateKeepAlive()
		for _, plr in ipairs(Players:GetPlayers()) do
			-- вышедшего не трогаем: запрос его состояния воскресил бы запись,
			-- которую QuestState только что убрал у себя
			if plr.Parent and not busy[plr] then
				busy[plr] = true
				task.spawn(function()
					-- под pcall: упавший проход не должен оставить busy взведённым
					-- навсегда — игрок выпал бы из дозора до конца сессии
					local ok, err = pcall(function()
						if islandModel and islandModel.Parent and not reached[plr] then
							if standsOnIsland(plr, islandModel) then
								creditReached(plr)
							end
						end
						flushPending(plr)
					end)
					busy[plr] = nil
					if not ok then warn("[Стартовый остров] дозор: " .. tostring(err)) end
				end)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
end)

-- ТЕСТ: поднять сцену прямо сейчас, не дожидаясь второго дня. Зовёт кнопка в
-- настройках (SettingsMenuActions, действие startIsleNow).
_G.StartIsleNow = function()
	if sceneStarted then
		return false, "сцена уже запускалась в этой сессии"
	end
	return raiseIsland()
end
