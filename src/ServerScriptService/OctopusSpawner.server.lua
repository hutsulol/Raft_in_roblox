--[[
	ОСЬМИНОГ — спавн в океане и счётчик ударов (серверная половина).

	Задача по OCTOPUS_BRIEF.md, раздел 2: «никто осьминога не создаёт». Здесь
	ровно это — цикл спавна, авторитетный счётчик ударов, таймер жизни и разбор
	за собой. Анимация щупалец и риг живут на КЛИЕНТЕ (OctopusRig/OctopusAnimator),
	и не по стилю, а по необходимости:

	⚠️ Bone.Transform НЕ РЕПЛИЦИРУЕТСЯ.
	Крути мы кости серверным скриптом — у игроков осьминог висел бы неподвижно в
	позе покоя. Обманчиво то, что в Play Solo всё выглядит правильно: сервер и
	клиент там один процесс. Поэтому сервер только СООБЩАЕТ состояние по
	OctopusEvent ("emerge" / "hit" / "break" / "submerge"), а двигает кости каждый
	клиент у себя.

	⚠️ КЛИК ПРИХОДИТ СРАЗУ НА СЕРВЕР.
	ClickDetector.MouseClick — серверное событие, клиенту ничего слать не надо, и
	подделать счётчик он не может.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Debris            = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

-- ═══════════ БАЛАНС ═══════════
-- ⚠️ РАСПИСАНИЕ ВЕДЁТСЯ ПО ДНЯМ, А НЕ ПО СЕКУНДАМ.
-- Осьминог — событие дня, а не фоновый ресурс: секундный цикл с шансом давал бы
-- то двоих подряд, то ни одного за вечер. Номер дня уже считает DayNightCircle и
-- кладёт в ReplicatedStorage.DayCount — берём его, чтобы не завести второй,
-- расходящийся счёт времени.
local FIRST_DAY        = 2    -- первый всплывает сам, без кнопки
local SPAWN_EVERY_DAYS = 2    -- и дальше раз в два дня

-- Сколько ударов держит. Первые дни игрок ещё без прокачанной силы, и сотня
-- ударов читалась как «не убивается вовсе».
local HITS_EARLY     = 25
local HITS_LATE      = 35
local EASY_UNTIL_DAY = 2      -- включительно

-- Монет с туши — столько же, сколько с пирата: он и есть добыча уровня пирата.
-- ⚠️ СКОЛЬКО ДАЛИ И СКОЛЬКО ПОКАЗАЛИ — РАЗНЫЕ ЧИСЛА.
-- На счёт идёт вся сумма отсюда, а на экране падает горстка монет (8–12, см.
-- CoinRainFX): шесть десятков картинок разом залили бы весь экран и читались бы
-- как помеха, а не как награда. Точное число всё равно в уведомлении.
local COINS_MIN, COINS_MAX = 60, 80

-- ⚠️ СРОК ЖИЗНИ СЧИТАН ПОД ДИСТАНЦИЮ СПАВНА, А НЕ ВЗЯТ КРУГЛЫМ ЧИСЛОМ.
-- Всплывает он за две сотни студов впереди, плот идёт 8 студов/с — только чтобы
-- подойти на дальность удара, нужно под тридцать секунд. С прежними двадцатью
-- пятью осьминог тонул ровно к тому моменту, когда по нему можно было ударить.
local LIFETIME      = 70      -- сек на поверхности; отсчёт с КОНЦА всплытия
-- Дистанции для «плот прошёл мимо»: осьминог не висит в кильватере до конца
-- срока, а уходит, когда плот его миновал. Считается только ПОСЛЕ сближения —
-- на старте он и так далеко.
local NEAR_ENOUGH   = 90
local GAVE_UP       = 160
local EMERGE_TIME   = 1.7     -- длительность клипа Emerge (OCTOPUS_SETUP.md)
local SUBMERGE_TIME = 2.0     -- длительность Submerge
-- Дальность удара и защита от автокликера здесь НЕ настраиваются: осьминог бьётся
-- общей обвязкой ресурсов, а у неё свои COLLECT_RANGE и порядок обработки клика
-- (ResourceSpawner). Разъехаться двум наборам чисел незачем.

-- Зазор до края плота, за которым осьминог считает, что его сейчас переедут, и
-- ныряет. Плот идёт 8 студов/с — при слишком большом зазоре он будет удирать,
-- едва всплыв, при слишком малом успеет войти в доски.
local RAFT_CLEAR = 8

-- ⚠️ МЕСТО ЗАДАЁМ В ОСЯХ ПЛОТА: ВПЕРЁД И В СТОРОНУ. И ОТДЕЛЬНО.
-- Расстояние с углом («в 30 студах, угол случайный») тут не работает: при
-- дальности клика в 60 студов почти любой угол оставляет боковой зазор меньше
-- радиуса, по которому осьминог ныряет, — и плот его сносит. Поперечный отступ
-- поэтому задаётся сам по себе и ОТСЧИТЫВАЕТСЯ ОТ ЭТОГО РАДИУСА: плот проходит
-- рядом и гарантированно мимо, а не по нему. Продольный отвечает за «впереди по
-- носу»: за кормой цель попросту не видно.
-- Дистанция взята та же, что у первых трёх ресурсов (ResourceSpawner,
-- CLOSE_AHEAD_MIN/MAX): плот идёт к нему сам, как к бревну, и осьминог успевает
-- показаться на горизонте, а не вырасти под боком.
local AHEAD_MIN, AHEAD_MAX = 170, 260  -- насколько впереди плота
local SIDE_MIN, SIDE_MAX   = 10, 30    -- насколько вбок СВЕРХ зоны ныряния

-- ⚠️ СВОЙ ГЕНЕРАТОР, А НЕ ОБЩИЙ math.random.
-- Общий поток в Luau стартует с одного и того же состояния, а место всплытия
-- считается первыми же бросками после запуска сервера — оттого осьминог
-- появлялся раз за разом в ОДНОЙ И ТОЙ ЖЕ точке. Random.new() без аргументов
-- берёт зерно у системы, и такой привязки к порядку вызовов у него нет.
local RNG = Random.new()

-- ⚠️ ЭТО ВЫСОТА ГОЛОВЫ, А НЕ ЦЕНТРА МОДЕЛИ.
-- Тушу ставим по голове (см. faceTarget), поэтому число отсчитывается от неё:
-- голова ~3 стада высотой, и при +1.2 над водой оказывалось всё тело целиком —
-- осьминог висел над волнами, а не плавал в них. Отрицательное = глубже.
-- Вертикальный ход всплытия тут ни при чём, он зашит в клип Emerge (стартует на
-- 4.6 стада ниже этой отметки), так что правится ровно посадка в воде.
local SPAWN_LIFT = -0.8

-- ⚠️ РАЗВОРАЧИВАЕМ ПО ГОЛОВЕ, А НЕ ПО ПИВОТУ МОДЕЛИ.
-- Пивот у импортированной модели выставлен по габаритной коробке и с осями самой
-- туши не совпадает — крутить по нему значит гадать (раньше здесь и стоял
-- случайный рыск). Оси головы известны, и морда у неё совпадает с LookVector.
-- Доворот поэтому нулевой; смещения глаз в OctopusRigData (eye_l/eye_r на
-- положительном Z) намекали на обратное, но у детали свой поворот от импортёра,
-- и на модели проверено: со 180° осьминог всплывал к плоту затылком. Это
-- единственная ручка — всплывёт снова спиной, менять надо ровно её.
local FACE_FIX = CFrame.identity

--[[ Что падает с осьминога. Держим таблицей: состав правится здесь и только здесь.

     ⚠️ МЯСА ЗДЕСЬ БОЛЬШЕ НЕТ — ПО ПРЯМОМУ УКАЗАНИЮ ВЛАДЕЛЬЦА.
     Стояло «Meat ×3»: осьминог — туша, мясо напрашивалось само. Но мясо в игре
     это еда с костра и мангала, у неё своя цепочка добычи, и осьминог в неё не
     входит.
     Атрибут ResourceType ниже по файлу при этом остаётся «Meat» — он отвечает
     только за звук удара и иконку разлома (бьём по туше, а не по бревну) и к
     выдаче отношения не имеет: настоящую добычу раздаёт эта таблица. ]]
local LOOT = {
	{ name = "Rope",  count = 2 },
}

-- ═══════════ ассеты ═══════════

-- ⚠️ ПАПКУ МОДУЛЕЙ ИЩЕМ ПО СОДЕРЖИМОМУ, А НЕ ПО ИМЕНИ.
-- В ReplicatedStorage запросто оказывается ВТОРОЙ ребёнок с именем «Octopus» —
-- сама модель из 3D Importer. WaitForChild("Octopus") с равным правом вернёт
-- любого из них, а порядок детей у сервера и у клиента свой. Отсюда и вышло
-- расхождение в логе: сервер поднялся, а у клиента «OctopusAnimator не
-- загрузился». Спрашиваем не имя, а содержимое.
local function findModules(timeout)
	local deadline = os.clock() + (timeout or 0)
	while true do
		for _, c in ipairs(ReplicatedStorage:GetChildren()) do
			if c:FindFirstChild("OctopusRig") and c:FindFirstChild("OctopusRigData") then
				return c
			end
		end
		if os.clock() >= deadline then return nil end
		task.wait(0.2)
	end
end

local modules = findModules(30)
if not modules then
	warn("[Осьминог] в ReplicatedStorage нет модулей рига (OctopusRig, OctopusRigData, "
		.. "OctopusAnimator) — спавнер выключен")
	return
end

-- ⚠️ МОДЕЛИ ОБЛОМКОВ НЕТ, И РАЗЛЁТА ТОЖЕ.
-- Пока осьминог был одним скиннутым мешем, на смерть подставлялась вторая,
-- заранее разрезанная модель. Жёсткий риг умеет разлетаться сам (Rig:breakApart
-- рвёт Motor6D), но смотрится это как поломка предмета, а не как убитый зверь —
-- см. dieWithAnimation ниже: смерть играется клипом BreakUp.
local Rig     = require(modules.OctopusRig)
local RigData = require(modules.OctopusRigData)

-- ⚠️ ШАБЛОН ПРОВЕРЯЕМ ПО ДЕТАЛЯМ, А НЕ ПО ИМЕНИ.
-- Прежний поиск брал первого попавшегося с именем «Octopus» — и брал им же
-- ПАПКУ МОДУЛЕЙ: клонировал три ModuleScript и падал на «missing part tent5_a».
-- Имя не значит ничего, значение имеет содержимое: в риге двадцать деталей с
-- известными именами, их и спрашиваем. Заодно так отсеивается старая, скиннутая
-- модель — она одна цельная и половинок щупалец в ней нет.
local function missingParts(inst)
	local miss = {}
	for name in pairs(RigData.Parts) do
		local p = inst:FindFirstChild(name, true)
		if not (p and p:IsA("BasePart")) then table.insert(miss, name) end
	end
	table.sort(miss)
	return miss
end

local function isOctopusName(inst)
	return inst.Name:lower():find("octo") ~= nil
end

-- ⚠️ ПОЛНОГО КОМПЛЕКТА НЕ ТРЕБУЕМ.
-- 3D Importer иногда не привозит мелочь: в первой сборке не приехал trinket —
-- цепочка толщиной 0.09 стада, — и осьминог из-за неё не спавнился вовсе. Риг
-- теперь собирается без недостающих деталей, значит и отбор должен отличать
-- «неполный осьминог» от «чужая модель», а не требовать все двадцать. Голова
-- обязательна: она корень скелета. Четверть допуска старую, скиннутую модель
-- отсекает с запасом — в ней не совпадает ни одно имя.
local MISSING_TOLERANCE = 5

local function isRigModel(inst)
	local head = inst:FindFirstChild(RigData.Root, true)
	if not (head and head:IsA("BasePart")) then return false end
	return #missingParts(inst) <= MISSING_TOLERANCE
end

local templateCache = nil

local function acceptTemplate(inst)
	templateCache = inst
	local miss = missingParts(inst)
	print(("[Осьминог] шаблон: %s (%s)"):format(inst:GetFullName(),
		(#miss == 0) and "все детали на месте"
			or ("без " .. table.concat(miss, ", "))))
	return templateCache
end

-- ⚠️ ШАБЛОН ЗАБИРАЕМ ИЗ WORKSPACE, ЕСЛИ ОН ТАМ.
-- Заказчик заливает модели прямо на карту. Клонировать надо из хранилища, иначе
-- «шаблон» остаётся плавать в мире и виден игрокам. Тот же приём, что у кровати
-- и бутылки.
local function findTemplate()
	if templateCache and templateCache.Parent then return templateCache end
	templateCache = nil

	-- штатное место по OCTOPUS_SETUP.md
	local m = modules:FindFirstChild("Model")
	if m and isRigModel(m) then return acceptTemplate(m) end

	for _, container in ipairs({ ReplicatedStorage, Workspace }) do
		for _, c in ipairs(container:GetChildren()) do
			if c ~= modules and isOctopusName(c) and isRigModel(c) then
				if container == Workspace then
					c.Parent = modules
					c.Name = "Model"
					print("[Осьминог] модель перенесена из Workspace в ReplicatedStorage/Octopus/Model")
				end
				return acceptTemplate(c)
			end
		end
	end
	return nil
end

-- Ругаемся один раз: попытка спавна идёт каждые 12 секунд, и пять одинаковых
-- строк в минуту только затирают то, из-за чего они появились.
local reportedNoTemplate = false
local function reportNoTemplate()
	if reportedNoTemplate then return end
	reportedNoTemplate = true
	warn("[Осьминог] модели рига нет. Класть сюда: ReplicatedStorage/Octopus/Model — "
		.. "это Model из Octopus.fbx (3D Importer, Scale 0.01). Имена деталей менять "
		.. "нельзя, риг находит их по ним: head, crown, collar, eye_l/r, "
		.. "tent0..6_a и _b, trinket.")
	local seen = {}
	for _, container in ipairs({ ReplicatedStorage, Workspace }) do
		for _, c in ipairs(container:GetChildren()) do
			if isOctopusName(c) then
				local miss = missingParts(c)
				local tail = (#miss == 0) and "все детали на месте"
					or ("нет %d деталей (%s%s)"):format(#miss,
						table.concat(miss, ", ", 1, math.min(#miss, 4)),
						(#miss > 4) and ", …" or "")
				table.insert(seen, ("%s.%s [%s] — %s")
					:format(container.Name, c.Name, c.ClassName, tail))
			end
		end
	end
	warn("[Осьминог] что нашлось по имени: "
		.. ((#seen > 0) and table.concat(seen, " | ") or "ничего"))
end

-- Канал «сервер → все клиенты». Создаём сами, если клиентская половина ещё не
-- положила его: спавнер должен работать и до того, как появится риг.
local event = ReplicatedStorage:FindFirstChild("OctopusEvent", true)
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "OctopusEvent"
	event.Parent = modules
end

-- ═══════════ спавн ═══════════
local alive = nil        -- сейчас в мире не больше одного осьминога
local everSpawned = false -- самого первого показываем с подсветкой и стрелкой

local function raftRoot()
	local raft = Workspace:FindFirstChild("Raft")
	return raft and raft.PrimaryPart or nil
end

-- Номер дня ведёт DayNightCircle. Пока он не поднялся, считаем, что первый.
local function currentDay()
	local d = ReplicatedStorage:FindFirstChild("DayCount")
	return (d and d.Value) or 1
end

local function maxHits()
	return (currentDay() <= EASY_UNTIL_DAY) and HITS_EARLY or HITS_LATE
end

-- Центр плота и радиус, внутри которого осьминог считает, что его сейчас
-- переедут. ОДНО определение «слишком близко» на весь файл: по нему и спавним,
-- и ныряем — иначе спавн раз за разом попадал бы в зону ныряния.
local function raftBox()
	local raft = Workspace:FindFirstChild("Raft")
	local prim = raft and raft.PrimaryPart
	if not prim then return nil, RAFT_CLEAR end
	local ok, cf, size = pcall(function()
		local c, s = raft:GetBoundingBox()
		return c, s
	end)
	local centre = (ok and cf) and cf.Position or prim.Position
	local reach = (ok and size)
		and (math.max(size.X, size.Z) * 0.5 + RAFT_CLEAR)
		or RAFT_CLEAR
	return centre, reach
end

local function pickSpot(root)
	-- ⚠️ ВПЕРЕДИ ПО КУРСУ, НО В СТОРОНЕ ОТ САМОГО КУРСА.
	-- Ресурсы мы выпускаем далеко впереди, чтобы плот сам к ним приплыл. Осьминог
	-- наоборот всплывает РЯДОМ и ждёт игрока: он живой и у него свой таймер. Но
	-- всплывать он должен там, куда игрок смотрит, — за кормой его попросту не
	-- видно, — и при этом там, где плот ПРОЙДЁТ МИМО, а не прямо по нему.
	local centre, reach = raftBox()
	local origin = centre or root.Position

	-- курс берём по скорости, как и при выпуске ресурсов; стоящий плот — по носу
	local vel = root.AssemblyLinearVelocity
	local fwd = Vector3.new(vel.X, 0, vel.Z)
	if fwd.Magnitude < 0.5 then
		local look = root.CFrame.LookVector
		fwd = Vector3.new(look.X, 0, look.Z)
	end
	fwd = (fwd.Magnitude > 0.1) and fwd.Unit or Vector3.zAxis
	local right = Vector3.new(-fwd.Z, 0, fwd.X)

	local ahead = RNG:NextNumber(AHEAD_MIN, AHEAD_MAX)
	local side = reach + RNG:NextNumber(SIDE_MIN, SIDE_MAX)
	if RNG:NextInteger(0, 1) == 0 then side = -side end   -- левый борт или правый

	local pos = origin + fwd * ahead + right * side
	-- поверхность воды берём по плоту: он на ней и плавает
	return Vector3.new(pos.X, root.Position.Y + SPAWN_LIFT, pos.Z)
end

-- Разворачивает тушу мордой к цели (к плоту). См. FACE_FIX в начале файла.
local function faceTarget(model, head, pos, target)
	-- цель приводим к высоте осьминога, иначе он завалится носом вниз
	local flat = Vector3.new(target.X, pos.Y, target.Z)
	if (flat - pos).Magnitude < 0.1 then flat = pos + Vector3.zAxis end
	local want = CFrame.lookAt(pos, flat) * FACE_FIX
	-- пивот сдвинут и повёрнут относительно головы — эту связку сохраняем
	model:PivotTo(want * head.CFrame:ToObjectSpace(model:GetPivot()))
end

local function giveLoot(player, pos)
	if not player then return end
	for _, item in ipairs(LOOT) do
		if _G.AddResourceToInventory then
			_G.AddResourceToInventory(player, item.name, item.count, nil)
		end
	end
	if _G.SendInventory then _G.SendInventory(player) end

	-- ⚠️ У ОСЬМИНОГА МОНЕТЫ СЫПЛЮТСЯ НА ЭКРАН, А НЕ ИЗ ТУШИ.
	-- С пиратов монеты вылетают деталями и притягиваются к убийце
	-- (_G.SpawnPirateCoins). С осьминогом это читалось плохо: он тонет далеко от
	-- плота и часто под водой — монеты уходили под поверхность и в мглу, и игрок
	-- не понимал, дали ему что-нибудь вообще. Экранный дождь виден при любой
	-- камере и с любого расстояния (CoinRainFX.client).
	-- Начисление от этого не меняется: монеты уже на счету, дождь — только показ.
	--
	-- ⚠️ И НАЧИСЛЯЕМ МОНЕТЫ САМИ. Это не мелочь: у пиратских монет счёт вёлся НЕ
	-- в момент выдачи, а в момент ПОДБОРА детали — каждая долетевшая монета
	-- прибавляла одну единицу (COIN_VALUE в ShipCombat). Замени разлёт на
	-- экранный дождь, не тронув начисление, — и осьминог перестал бы приносить
	-- деньги вовсе, притом молча: добыча в рюкзаке есть, монет нет.
	local coins = RNG:NextInteger(COINS_MIN, COINS_MAX)
	local rain = ReplicatedStorage:FindFirstChild("CoinRain")
	if rain and rain:IsA("RemoteEvent") then
		if _G.AddPirate then
			pcall(_G.AddPirate, player, coins)
		else
			player:SetAttribute("Pirate", (player:GetAttribute("Pirate") or 0) + coins)
		end
		rain:FireClient(player, coins)
	elseif _G.SpawnPirateCoins and pos then
		-- ремоута нет (EventBootstrap не отработал) — пусть будет хоть по-старому:
		-- там монеты и начислятся сами, при подборе
		_G.SpawnPirateCoins(pos + Vector3.new(0, 1.2, 0), player, coins)
	end

	if _G.NotifyPlayer then
		_G.NotifyPlayer(player, { type = "info", icon = "🐙",
			title = "Осьминог разбит", body = ("Добыча в рюкзаке, монет: %d"):format(coins) })
	end
end

-- ⚠️ СМЕРТЬ — ЭТО КЛИП, А НЕ РАЗЛЁТ ДЕТАЛЕЙ.
-- Rig:breakApart умеет разорвать суставы и раскидать двадцать кусков с золотом
-- вперемешку, и это было соблазнительно, раз риг «сам себе обломки». На экране
-- вышло хуже: туша исчезала, вместо неё сыпался щебень, и убийство читалось как
-- поломка предмета, а не как победа над зверем. Возвращаем то, ради чего клип
-- BreakUp и рисовали: содрогание, съехавшая корона, обвисшие щупальца — а потом
-- тело уходит под воду целиком. breakApart в модуле остаётся, просто не зовётся.
local BREAK_TIME = 0.85    -- длительность клипа BreakUp (OCTOPUS_SETUP.md)

local function dieWithAnimation(model)
	-- ⚠️ ГЛУШИМ ЗВУКИ ТУШИ, А НЕ УДАЛЯЕМ ИХ ИЗ МОДЕЛИ.
	-- Звук погружения лежит ВНУТРИ модели осьминога, в самом плейсе, — в коде его
	-- нет вовсе, поэтому «убрать строку» тут нечего. Останавливаем всё, что в туше
	-- звучит, в момент смерти: клип BreakUp и уход под воду проходят молча, а
	-- сама модель в ReplicatedStorage остаётся нетронутой.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Sound") then
			d.Playing = false
			d.Volume = 0
			pcall(function() d:Stop() end)
		end
	end

	task.delay(BREAK_TIME, function()
		if not model.Parent then return end
		-- добитая туша не остаётся плавать: уводим её вниз тем же клипом, что и
		-- у сбежавшего, и только после этого убираем
		event:FireAllClients("submerge", model)
		task.delay(SUBMERGE_TIME, function()
			if model.Parent then model:Destroy() end
		end)
	end)
end

-- Почему последняя попытка не удалась: кнопка в настройках должна отвечать тем
-- же, что лежит в логе, а не общим «модель не найдена» на все случаи.
local lastFailure = nil

local function spawnOctopus()
	local root = raftRoot()
	if not root then
		lastFailure = "нет плота в Workspace"
		return
	end
	local template = findTemplate()
	if not template then
		reportNoTemplate()
		lastFailure = "модели рига нет в ReplicatedStorage/Octopus/Model"
		return
	end

	local model = template:Clone()
	model.Name = "Octopus"

	-- ⚠️ СКЕЛЕТ СОБИРАЕТ СЕРВЕР, ДВИЖЕНИЕ ВЕДЁТ КЛИЕНТ.
	-- Rig.setup создаёт Motor6D по замерам из OctopusRigData. Сами суставы —
	-- инстансы, они реплицируются, и осьминог у всех собран одинаково. А вот
	-- Motor6D.Transform (собственно анимация) НЕ реплицируется, поэтому bind()
	-- здесь не зовём: кости крутит OctopusClient у каждого игрока свой.
	-- Заодно setup сам расставляет якоря: корень заанкорен, детали висят на нём
	-- невесомыми. Анкорить всё подряд, как раньше, нельзя — тогда суставы ничего
	-- не двигают, а при разбитии детали не разлетаются.
	local okRig, rig = pcall(Rig.setup, model)
	if not okRig then
		warn("[Осьминог] риг не собрался: " .. tostring(rig))
		lastFailure = "риг не собрался: " .. tostring(rig)
		model:Destroy()
		return
	end
	lastFailure = nil

	-- ⚠️ ВСПЛЫВАЕТ МОРДОЙ К ПЛОТУ, А НЕ КАК ВЫПАДЕТ.
	-- Случайный рыск давал спину к игроку чаще, чем морду: у туши одна интересная
	-- сторона, и показывать её — не украшение, а понятность цели.
	local spot = pickSpot(root)
	faceTarget(model, rig.head, spot, root.Position)
	-- Метка для чужих систем и для клиентского рига: это не зверь и не ресурс, а
	-- добываемая цель со своим счётчиком. (AnimalStabilizer её всё равно подхватит
	-- и сделает Massless — на заанкоренной модели это ничего не меняет.)
	model:SetAttribute("IsOctopus", true)

	model.Parent = Workspace
	alive = model

	-- ⚠️ БЬЁМ ЕГО ТЕМ ЖЕ СПОСОБОМ, ЧТО И БРЕВНО, А НЕ СВОИМ ClickDetector.
	-- Свой детектор давал курсор Roblox и никакого индикатора прочности: рядом с
	-- брёвнами это читалось как другой, чужой предмет. Тег "Resource" и пара
	-- атрибутов подключают осьминога ко ВСЕЙ готовой обвязке — наведение с
	-- подсветкой, полоса прочности над целью, урон с учётом силы игрока, тряска и
	-- всплеск в точке удара. Дублировать это второй раз незачем.
	local hits = maxHits()
	model:SetAttribute("ResourceMaxHP", hits)
	model:SetAttribute("ResourceHP", hits)
	-- Тип нужен обвязке для звука и иконки; настоящую добычу выдаёт OctopusKilled.
	model:SetAttribute("ResourceType", "Meat")
	model:SetAttribute("ResourceAmount", 1)
	-- ⚠️ ДО КОНЦА ВСПЛЫТИЯ КЛИКИ НЕ СЧИТАЮТСЯ.
	-- Визуал едет, а хитбокс стоит: деталь уже в конечной точке, хотя выглядит
	-- утопленной. Тег вешаем только после подъёма — до него бить не по чему.
	model:SetAttribute("OctopusClickable", false)

	-- ⚠️ ПРО УДАР УЗНАЁМ ПО ПРОСЕДАНИЮ ПРОЧНОСТИ, А НЕ ЛОВИМ КЛИК САМИ.
	-- Клик обрабатывает общая обвязка ресурсов; перехватывать его здесь значило бы
	-- держать вторую копию всей проверки (дистанция, сила, тип цели). А ResourceHP
	-- она меняет ровно на засчитанный удар — этого сигнала хватает, чтобы клиенты
	-- дёрнули вздрог. Заодно ловятся удары ЛЮБОГО игрока, а не только своего.
	model:GetAttributeChangedSignal("ResourceHP"):Connect(function()
		if model.Parent == nil then return end
		if (model:GetAttribute("ResourceHP") or 0) > 0 then
			event:FireAllClients("hit", model)
		end
	end)

	-- ⚠️ ТРЕТЬИМ АРГУМЕНТОМ — «ЭТОТ ПЕРВЫЙ».
	-- Незнакомую цель надо показать: клиент по этому флагу зажигает ту же зелёную
	-- подсветку со стрелкой, что ведёт к брёвнам в начале игры. Дальше осьминог
	-- уже знаком, и водить к нему за руку не надо.
	local first = not everSpawned
	everSpawned = true
	event:FireAllClients("emerge", model, first)

	local p = model:GetPivot().Position
	print(("[Осьминог] всплыл в %d студах от плота, Y=%.1f (вода %.1f), день %d — %d ударов до разбития")
		:format(math.floor((p - root.Position).Magnitude), p.Y, root.Position.Y,
			currentDay(), hits))

	-- Уход под воду — один путь на все поводы: вышло время, приплыл плот.
	-- Второй раз не запускается: OctopusClickable к тому моменту уже снят.
	local function submerge(why)
		if model.Parent == nil then return end
		if model:GetAttribute("OctopusClickable") ~= true then return end
		model:SetAttribute("OctopusClickable", false)
		-- снимаем тег: уходящего под воду бить уже нельзя
		CollectionService:RemoveTag(model, "Resource")
		event:FireAllClients("submerge", model)
		print("[Осьминог] уходит под воду: " .. why)
		task.delay(SUBMERGE_TIME, function()
			if model.Parent then model:Destroy() end
			if alive == model then alive = nil end
		end)
	end

	task.delay(EMERGE_TIME, function()
		if model.Parent == nil then return end
		model:SetAttribute("OctopusClickable", true)
		CollectionService:AddTag(model, "Resource")   -- теперь по нему можно бить

		-- ⚠️ ПЛОТ ПОДОШЁЛ — ОСЬМИНОГ НЫРЯЕТ, А НЕ ПРОХОДИТ СКВОЗЬ НЕГО.
		-- Он заанкорен и без коллизий (иначе давил бы на плот и ломал его ход), а
		-- плот идёт 8 студов/с — через пару секунд после всплытия он просто
		-- проезжал модель насквозь. Физику для этого включать нельзя: столкновение
		-- заанкоренной туши с плотом — это как раз то, от чего страдал бы ход. Так
		-- что смотрим расстояние сами и уводим его вниз, как по таймеру.
		task.spawn(function()
			local wasNear = false
			while model.Parent and model:GetAttribute("OctopusClickable") == true do
				local centre, reach = raftBox()
				if centre then
					local p = model:GetPivot().Position
					local dx, dz = p.X - centre.X, p.Z - centre.Z
					local d2 = dx * dx + dz * dz
					if d2 <= reach * reach then
						submerge("подошёл плот")
						return
					end
					-- ⚠️ «ПЛОТ УШЁЛ» ЗАСЧИТЫВАЕМ ТОЛЬКО ПОСЛЕ СБЛИЖЕНИЯ.
					-- Всплывает он за две сотни студов впереди, то есть на старте
					-- заведомо «далеко»: правило без этой памяти утопило бы его
					-- через четверть секунды после появления.
					if d2 <= NEAR_ENOUGH * NEAR_ENOUGH then wasNear = true end
					if wasNear and d2 > GAVE_UP * GAVE_UP then
						submerge("плот прошёл мимо")
						return
					end
				end
				task.wait(0.25)
			end
		end)

		-- ⚠️ ТАЙМЕР ЖИЗНИ СТАРТУЕТ ЗДЕСЬ, А НЕ ПРИ СПАВНЕ.
		-- Иначе всплытие съедало бы часть срока, и игрок получал меньше времени,
		-- чем написано в балансе.
		task.delay(LIFETIME, function()
			submerge("вышло время")
		end)
	end)
end

-- ⚠️ СМЕРТЬ ОСЬМИНОГА ОБРАБАТЫВАЕТ ОБЩАЯ ОБВЯЗКА РЕСУРСОВ, А ЗОВЁТ СЮДА.
-- Она умеет считать урон и рисовать полосу, но не знает про обломки и состав
-- добычи — это здесь. ResourceSpawner вызывает эту ручку вместо своей обычной
-- выдачи, когда у цели стоит IsOctopus.
_G.OctopusKilled = function(player, model)
	if typeof(model) ~= "Instance" then return end
	CollectionService:RemoveTag(model, "Resource")
	-- бить больше нельзя, и таймер ухода по времени сам себя отменит по этой метке
	model:SetAttribute("OctopusClickable", false)
	event:FireAllClients("break", model)
	giveLoot(player, model:GetPivot().Position)
	-- ⚠️ МОДЕЛЬ ЗДЕСЬ НЕ УНИЧТОЖАЕМ.
	-- Сначала должен доиграть клип смерти, и убирает тело dieWithAnimation.
	-- Поэтому ResourceSpawner для осьминога Destroy НЕ зовёт.
	dieWithAnimation(model)
	if alive == model then alive = nil end
end

-- Поднять осьминога сейчас — кнопка в настройках (SettingsMenuActions).
_G.SpawnOctopus = function()
	-- ⚠️ КНОПКА ЗАМЕНЯЕТ СТАРОГО, А НЕ ОТКАЗЫВАЕТ.
	-- Она тестовая: жмут её, чтобы посмотреть на нового — а «осьминог уже в воде»
	-- означало ждать четверть минуты или искать прежнего по горизонту. Сначала
	-- сообщаем клиентам, что этот уходит: иначе у них останется висеть указатель
	-- и запись рига на уже несуществующей модели.
	if alive and alive.Parent then
		event:FireAllClients("submerge", alive)
		alive:Destroy()
	end
	alive = nil
	lastFailure = nil
	local ok, err = pcall(spawnOctopus)
	if not ok then return false, tostring(err) end
	return (alive ~= nil), (alive == nil) and (lastFailure or "спавн не состоялся") or nil
end

-- ═══════════ расписание ═══════════
-- ⚠️ ЖДЁМ СМЕНЫ ДНЯ, А НЕ ТИКАЕМ СВОИМ ТАЙМЕРОМ.
-- Второй счёт времени рядом с DayNightCircle обязательно разъехался бы с ним:
-- ночь можно проспать в кровати и промотать (_G.StartNightNow), и «раз в двое
-- суток» по секундомеру перестало бы совпадать с тем, что видит игрок.
task.spawn(function()
	local day = ReplicatedStorage:WaitForChild("DayCount", 60)
	if not day then
		warn("[Осьминог] нет ReplicatedStorage.DayCount — расписание по дням не работает, "
			.. "остаётся только кнопка в настройках")
		return
	end

	local function consider(n)
		if n < FIRST_DAY then return end
		if (n - FIRST_DAY) % SPAWN_EVERY_DAYS ~= 0 then return end
		if alive and alive.Parent then return end
		alive = nil
		local ok, err = pcall(spawnOctopus)
		if not ok then warn("[Осьминог] спавн упал: " .. tostring(err)) end
	end

	day.Changed:Connect(consider)
	-- на случай, если сервер поднялся уже посреди подходящего дня
	consider(day.Value)
end)

print(("[Осьминог] спавнер готов: первый на %d-й день, дальше раз в %d дня; "
	.. "ударов %d (с %d-го дня %d), %d сек на поверхности")
	:format(FIRST_DAY, SPAWN_EVERY_DAYS, HITS_EARLY, EASY_UNTIL_DAY + 1, HITS_LATE, LIFETIME))
