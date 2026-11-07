--[[
	КАРТА АРХИПЕЛАГА — серверная часть.

	Держит реестр островов, снимает с них туман по мере приближения плота и
	обслуживает рейсы. Клиент только рисует: цену рейса, владельца и туман
	решает сервер (хендоф, раздел «Серверная архитектура»).

	⚠️ ОСТРОВА НЕ ЗАВОДЯТСЯ РУКАМИ.
	Они уже есть в мире, и IslandClearSystem узнаёт их по папке Enemies внутри
	модели. Берём тот же признак — иначе появился бы второй список островов,
	который начал бы расходиться с настоящим при первой же правке уровня.

	⚠️ ТУМАН СНИМАЕТ ДИСТАНЦИЯ, А НЕ КНОПКА.
	Так прямо сказано в хендофе: «Плыть к нему через карту НЕЛЬЗЯ… разведка =
	игрок сам подплывает». Поэтому здесь только замер расстояния до плота.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Map = require(ReplicatedStorage:WaitForChild("MapDefs"))
local OilCanister = require(ReplicatedStorage:WaitForChild("OilCanister"))

local LOG = "[Карта]"
local ENEMIES_FOLDER = "Enemies"
local DISCOVER_DIST = 420      -- студов до острова, чтобы снять туман

local dataEvent = ReplicatedStorage:FindFirstChild("MapData")
if not dataEvent then
	dataEvent = Instance.new("RemoteEvent")
	dataEvent.Name = "MapData"
	dataEvent.Parent = ReplicatedStorage
end

local sailEvent = ReplicatedStorage:FindFirstChild("MapSail")
if not sailEvent then
	sailEvent = Instance.new("RemoteEvent")
	sailEvent.Name = "MapSail"
	sailEvent.Parent = ReplicatedStorage
end

-- Экран перемещения: сервер говорит клиентам «закрывай мир» и «готово».
-- Слушает его StarterPlayerScripts/TeleportScreen.client.lua.
local teleportEvent = ReplicatedStorage:FindFirstChild("MapTeleport")
if not teleportEvent then
	teleportEvent = Instance.new("RemoteEvent")
	teleportEvent.Name = "MapTeleport"
	teleportEvent.Parent = ReplicatedStorage
end

-- ═══════════ реестр ═══════════

local islands = {}    -- [id] = { id, model, pos, type, size, defense, owned, seen }
local nextId = 0

-- Тип и размер: если левельдизайнер проставил атрибуты — верим им, иначе
-- угадываем по имени и габариту. Атрибут всегда сильнее догадки.
local function guessType(model)
	local attr = model:GetAttribute("MapType")
	if attr and Map.TYPES[attr] then return attr end
	local n = model.Name:lower()
	if n:find("oil") or n:find("нефт") then return "oil" end
	if n:find("iron") or n:find("ore") or n:find("rock") or n:find("snow") then return "iron" end
	return "forest"
end

local function guessSize(model)
	local attr = model:GetAttribute("MapSize")
	if attr and Map.SIZE_PX[attr] then return attr end
	local ok, _, size = pcall(function() return model:GetBoundingBox() end)
	local span = ok and size and math.max(size.X, size.Z) or 200
	if span < 180 then return "small" end
	if span < 340 then return "medium" end
	return "large"
end

--[[ ═══════════ имена островов для игрока ═══════════
     Модели зовутся TropicIsland_SCENE / Island_2 — это имена ассетов, не
     острова. Игроку показываем русское имя: «Остров Черепахи», «Ржавая коса».
     Имя выбирается случайно по типу острова, один раз, и пишется в атрибут
     MapName на модели — так оно не меняется между снимками, а левельдизайнер
     может задать своё прямо в Studio (атрибут сильнее генератора). Ту же
     строку читает шторка телепорта. ]]
local ISLAND_NAMES = {
	forest = {
		"Остров Черепахи", "Пальмовый берег", "Кокосовый остров", "Зелёная лагуна",
		"Тихая бухта", "Остров Попугаев", "Солнечная коса", "Остров Крабов",
		"Банановый мыс", "Остров Ракушек", "Песчаный рай", "Остров Чаек",
	},
	iron = {
		"Ржавая коса", "Каменный зуб", "Серый утёс", "Остров Скал",
		"Железный мыс", "Холодный камень", "Остров Ветров", "Гремучая скала",
		"Острый риф", "Туманный пик",
	},
	oil = {
		"Чёрная лагуна", "Смоляной берег", "Дымный остров", "Мазутная коса",
		"Остров Копоти", "Тёмная бухта", "Остров Вышек", "Горелый мыс",
	},
}

local usedNames = {}
local function displayName(model, kind)
	local own = model:GetAttribute("MapName")
	if type(own) == "string" and own ~= "" then
		usedNames[own] = true
		return own
	end
	local pool = ISLAND_NAMES[kind] or ISLAND_NAMES.forest
	-- Сначала пробуем незанятое имя, чтобы два острова рядом не звались одинаково;
	-- если весь список разобран — берём любое.
	local free = {}
	for _, n in ipairs(pool) do
		if not usedNames[n] then table.insert(free, n) end
	end
	local pick = (#free > 0) and free[math.random(#free)] or pool[math.random(#pool)]
	usedNames[pick] = true
	model:SetAttribute("MapName", pick)
	return pick
end

local function addIsland(model)
	for _, isle in pairs(islands) do
		if isle.model == model then return end
	end
	nextId += 1
	local kind = guessType(model)
	local size = guessSize(model)
	islands[nextId] = {
		id = nextId,
		name = displayName(model, kind),
		model = model,
		pos = model:GetPivot().Position,
		type = kind,
		size = size,
		-- защита числом, шаг 6 (хендоф, раздел «Баланс»)
		defense = model:GetAttribute("MapDefense")
			or ({ small = 6, medium = 12, large = 18 })[size],
		owned = model:GetAttribute("Cleared") == true,
		seen = model:GetAttribute("MapSeen") == true,   -- из сейва
		attack = nil,
	}
end

--[[ ⚠️ ОСТРОВ — НЕ ТОЛЬКО ТОТ, У КОГО ЕСТЬ ВРАГИ.
     Раньше признаком была папка Enemies, и мирный TropicIsland_SCENE (врагов
     нет по сценарию) на карту не попадал вовсе. Теперь три признака, любого
     достаточно: атрибут MapIsland (его ставит WorldEventSpawner на каждый
     поднятый остров), папка Enemies (острова, положенные в плейс руками) и
     имя по шаблону "<...>_SCENE" / "Island_N" — на случай, если остров
     появился в обход спавнера. ]]
local function looksLikeIsland(inst)
	if not inst:IsA("Model") then return false end
	if inst:GetAttribute("MapIsland") then return true end
	if inst:FindFirstChild(ENEMIES_FOLDER) then return true end
	local n = inst.Name
	-- TropicIsland_SCENE, TerraceIsle_SCENE, SmallIsle_SCENE, Island_1 …
	return n:match("Isl[ea]n?d?[_%w]*_SCENE$") ~= nil
		or n:match("^Island_%d+$") ~= nil
end

local function scan(inst)
	if looksLikeIsland(inst) then addIsland(inst) end
end
for _, child in ipairs(Workspace:GetChildren()) do scan(child) end
Workspace.ChildAdded:Connect(function(child)
	task.delay(1, function()
		if child.Parent then scan(child) end
	end)
	-- Папка Enemies может прийти позже самой модели — тогда первый scan
	-- промахивается, а второго шанса раньше не было.
	if child:IsA("Model") then
		local conn
		conn = child.ChildAdded:Connect(function(sub)
			if sub.Name == ENEMIES_FOLDER and child.Parent then
				conn:Disconnect()
				scan(child)
			end
		end)
		task.delay(30, function() if conn then conn:Disconnect() end end)
	end
end)

-- Захваченный игроком остров становится «вашим»: тот же хук, что и у катсцены.
local prevCleared = _G.OnIslandCleared
_G.OnIslandCleared = function(model)
	for _, isle in pairs(islands) do
		if isle.model == model then
			isle.owned = true
			isle.seen = true
			model:SetAttribute("Cleared", true)   -- в сейв уходит атрибут
			model:SetAttribute("MapSeen", true)
		end
	end
	if prevCleared then pcall(prevCleared, model) end
end

-- ═══════════ доход и ресурсы ═══════════

local function sourcesOf(isle)
	return Map.SOURCES_BY_SIZE[isle.size] or 1
end

local function incomeOf(isle)
	if not isle.owned then return 0 end
	return sourcesOf(isle) * Map.INCOME_PER_SOURCE
end

--[[ ⚠️ РЕЙС ТРЕБУЕТ ПРИЧАЛА С ЛОДКОЙ, И ПРОВЕРЯТЬ ЕГО НАДО КАЖДЫЙ РАЗ.
     Скрафтить причал мало — его ещё надо ПОСТАВИТЬ на плот, а поставленный
     можно и сломать (RaftDemolish). Поэтому «есть предмет в рюкзаке» не
     годится как признак: спрашиваем сам плот, стоит ли на нём причал прямо
     сейчас.
     Признак — атрибут DockSpan: его ставит установка причала
     (BuildingSystem.server.server.lua) и больше никто. Имя модели проверяем
     вторым шансом: причал, положенный в плейс руками, атрибута не имеет.
     ⚠️ Не кэшировать. Между открытием карты и нажатием «Плыть сюда» причал
     может исчезнуть — тем же напарником, который его разобрал. ]]
--[[ ⚠️ СМОТРИМ ДЕТЕЙ ПЛОТА, А НЕ ВСЕХ ПОТОМКОВ.
     Первая версия звала GetDescendants — и это было прямой ошибкой: у плота
     тысячи потомков (каждая доска пола — модель со своими деталями и брёвнами),
     а снимок карты собирается раз в секунду на каждого игрока с открытой картой.
     Такой обход раз в секунду на сервере, который сам же считает физику плота,
     даёт ровно то, на что жаловались: плот идёт рывками и «телепортируется».
     Причал ставится ПРЯМЫМ ребёнком плота (BuildingSystem: dock.Parent = raft),
     поэтому детей достаточно.
     Найденный причал запоминаем — пока он жив, обхода нет вовсе. Отрицательный
     ответ НЕ кэшируем: причал могут построить в любой момент, и «нет» осталось
     бы навсегда. ]]
local dockCache = nil
local function raftDock()
	if dockCache and dockCache.Parent then return dockCache end
	dockCache = nil
	local raft = Workspace:FindFirstChild("Raft")
	if not raft then return nil end
	for _, d in ipairs(raft:GetChildren()) do
		if d:IsA("Model") and (d:GetAttribute("DockSpan") ~= nil or d.Name == "Boat_3x") then
			dockCache = d
			return d
		end
	end
	return nil
end

local function raftPos()
	local raft = Workspace:FindFirstChild("Raft") or Workspace:FindFirstChild("Raft_Part", true)
	if raft then
		local ok, cf = pcall(function() return raft:GetPivot() end)
		if ok then return cf.Position end
		if raft:IsA("BasePart") then return raft.Position end
	end
	-- плота нет — берём игрока, чтобы карта хотя бы не была пустой
	local p = Players:GetPlayers()[1]
	local hrp = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position or Vector3.zero
end

local function oilStored()
	local tank = OilCanister.findTank(Workspace)
	return tank and OilCanister.tankStored(tank) or 0
end

-- Жители — валюта игрока: атрибут «Villagers», его ведёт VillagersCurrency и по
-- нему же рисует счётчик в HUD. Второго источника заводить не надо.
local function population(player)
	if player then return player:GetAttribute("Villagers") or 0 end
	local first = Players:GetPlayers()[1]
	return first and (first:GetAttribute("Villagers") or 0) or 0
end

-- ═══════════ снимок для клиента ═══════════

local MOOR_KEEP = 600   -- студов: дальше этого швартовка забывается

local function mooredNow(rp)
	local id = _G.MapMooredIsland
	local isle = id and islands[id]
	if not isle then return nil end
	local d = Vector2.new(isle.pos.X - rp.X, isle.pos.Z - rp.Z).Magnitude
	if d > MOOR_KEEP then
		_G.MapMooredIsland = nil
		return nil
	end
	return id
end

-- Насколько далеко от кромки острова всплываем. Меньше сотни — плот встаёт
-- вплотную к берегу и цепляется геометрией; больше двухсот — игрок не понимает,
-- доплыл он или нет.
local ARRIVE_GAP = 140

--[[ ⚠️ РАДИУС МЕРЯЕМ ПО ГАБАРИТУ, А НЕ ОДНИМ ЧИСЛОМ НА ВСЕХ.
     Острова разного размера: общая константа оставила бы мелкие в километре, а
     крупные — внутри берега.
     GetBoundingBox стоит дорого, а снимок собирается раз в секунду, поэтому
     результат запоминаем на самом острове: геометрия у него не меняется. ]]
local function islandRadius(isle)
	if isle.radius then return isle.radius end
	local ok, _, size = pcall(function()
		local cf, sz = isle.model:GetBoundingBox()
		return cf, sz
	end)
	isle.radius = (ok and size) and math.max(size.X, size.Z) * 0.5 or 120
	return isle.radius
end

--[[ ⚠️ К ОСТРОВУ, У КОТОРОГО УЖЕ СТОИШЬ, ПЛЫТЬ НЕКУДА.
     Рейс ставит плот в ARRIVE_GAP от кромки. Если плот и так ближе этого, рейс
     не сдвинул бы его вообще — а нефть списал бы и шторку показал. Со стороны
     это чистый обман: заплатил и ничего не произошло.
     Запас в полсотни студов нужен, чтобы рейс не превращался в подтягивание на
     несколько метров, за которое всё равно берут полную цену. ]]
local NEAR_SLACK = 50
local function tooClose(isle, rp)
	local d = Vector2.new(isle.pos.X - rp.X, isle.pos.Z - rp.Z).Magnitude
	return d <= islandRadius(isle) + ARRIVE_GAP + NEAR_SLACK
end

local function snapshot(player)
	local rp = raftPos()
	local list, oilIncome, totalIncome = {}, 0, 0
	for _, isle in pairs(islands) do
		if isle.model.Parent then
			isle.pos = isle.model:GetPivot().Position
			if not isle.seen and (isle.pos - rp).Magnitude <= DISCOVER_DIST then
				isle.seen = true
				if isle.model.Parent then isle.model:SetAttribute("MapSeen", true) end
			end
			local income = incomeOf(isle)
			totalIncome += income
			if isle.type == "oil" then oilIncome += income end
			table.insert(list, {
				id = isle.id,
				name = isle.name,
				x = isle.pos.X, z = isle.pos.Z,
				type = isle.type,
				size = isle.size,
				defense = isle.defense,
				owned = isle.owned,
				seen = isle.seen,
				-- плот уже стоит у этого острова: кнопка рейса не нужна
				near = tooClose(isle, rp),
				attack = isle.attack,
				income = income,
				sources = sourcesOf(isle),
			})
		end
	end
	return {
		islands = list,
		raft = { x = rp.X, z = rp.Z },
		oil = oilStored() / Map.OIL_UNIT_ML,   -- в литрах, как и цена рейса
		oilPerDay = oilIncome * Map.DAY_MULT,
		profitPerDay = totalIncome * Map.DAY_MULT,
		population = population(player),
		--[[ ⚠️ ШВАРТОВКА СНИМАЕТСЯ САМА, КОГДА ПЛОТ УНЕСЛО.
		     Плот не стоит у берега: после рейса стоп снимается, и течение уносит его
		     дальше со скоростью восемь студов в секунду. Держать пометку «пришвартован»
		     вечно значит навсегда спрятать кнопку «Плыть сюда» у того острова, от
		     которого игрок давно уплыл. Шестьсот студов — это чуть больше минуты хода
		     и заведомо дальше радиуса любого острова. ]]
		mooredTo = mooredNow(rp),
		-- карточка острова прячет кнопку рейса, пока причала нет
		hasDock = raftDock() ~= nil,
	}
end

-- ⚠️ ФЛАГ «КАРТА ОТКРЫТА» СТАВИТ СЕРВЕР, А НЕ КЛИЕНТ.
-- Атрибут, выставленный на клиенте, на сервер не реплицируется вовсе — поэтому
-- клиент про открытие сообщает этим же событием, а флаг пишем здесь.
dataEvent.OnServerEvent:Connect(function(player, open)
	player:SetAttribute("MapOpen", open ~= false)
	dataEvent:FireClient(player, snapshot(player))
end)

-- ⚠️ ПУШИМ РАЗ В СЕКУНДУ, А НЕ КАЖДЫЙ КАДР.
-- Карта — не боевой интерфейс: туман, доход и остаток нефти меняются медленно, а
-- лишний трафик на открытой карте у всех игроков стоит дороже точности.
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			-- снимок собираем только если карта у кого-то открыта: обход островов
			-- вхолостую раз в секунду не нужен никому
			if player:GetAttribute("MapOpen") then
				dataEvent:FireClient(player, snapshot(player))
			end
		end
	end
end)

-- ═══════════ рейс ═══════════

--[[ ⚠️ РЕЙС — ЭТО ТЕЛЕПОРТ ПОД ШТОРКОЙ, А НЕ ПЛАВАНИЕ.
     Вести плот через полтора километра открытой воды нечем: BoatMovement
     держит один курс и не умеет цели, а гнать его скриптом полминуты значит
     держать игрока в пустом океане и молиться, чтобы по дороге ничего не
     столкнулось. Поэтому плот переставляется мгновенно, а момент подмены
     закрыт полноэкранной анимацией (TeleportScreen.client.lua).
     Порядок жёсткий и завязан на тайминги шторки:
       0.0  сказали клиентам «закрывай», встали на месте (SailHold);
       1.4  шторка уже непрозрачна — переставляем плот и всех, кто на нём;
       2.2  сказали «готово», сняли стоп.
     Меняешь COVER_TIME — меняй и время входа шторки, иначе игрок увидит
     подмену собственными глазами. ]]
local COVER_TIME  = 1.4    -- пока шторка набирает непрозрачность
-- ⚠️ Пауза после переноса: догрузить стриминг И дать физике успокоиться.
-- Детали отпускаются из-под якоря через 0.15 с, поэтому меньше этого ставить
-- нельзя: стоп снимется раньше, чем плот снова станет физическим телом.
local SETTLE_TIME = 0.8
-- Кого считаем «на плоту»: плот вместе с постройками укладывается в сотню
-- студов, дальше начинается океан. По высоте берём с запасом на мачты и прыжок.
local RIDE_RADIUS = 90
local RIDE_HEIGHT = 45

local function raftModel()
	return Workspace:FindFirstChild("Raft")
end


--[[ ⚠️ ПЕРЕНОСИМ ПЛОТ ВМЕСТЕ С ЛЮДЬМИ, И ЭТО НЕ ПЕРЕСТРАХОВКА.
     Игроки на плоту не приварены — они просто стоят на досках. PivotTo уносит
     плот, а персонажи остаются висеть над водой в старой точке и падают в
     океан. Поэтому запоминаем всех, кто рядом, и двигаем их той же дельтой.
     ⚠️ Скорость снимаем и возвращаем руками: PivotTo не трогает
     AssemblyLinearVelocity, и плот приехал бы на новое место с ходом в старую
     сторону — фактически с рывком вбок сразу после появления. ]]
--[[ ⚠️ КТО ИМЕННО ЕДЕТ. Плот в игре один, но игроки не обязаны на нём стоять:
     один ушёл зачищать остров, другой в это время жмёт «Плыть сюда». Уехавший
     плот не должен утаскивать островного за собой, а островной не должен
     полторы секунды смотреть в чёрный экран, ничего при этом не переживая.
     Поэтому и шторка, и перенос считают пассажиров одним и тем же правилом. ]]
local function ridersOf(pivotPos)
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = hrp.Position - pivotPos
			if Vector2.new(d.X, d.Z).Magnitude <= RIDE_RADIUS
				and math.abs(d.Y) <= RIDE_HEIGHT then
				table.insert(list, { player = plr, hrp = hrp })
			end
		end
	end
	return list
end

-- targetXZ — Vector3: берём из него X и Z, высоту держит BoatMovement.
-- faceDir — куда должен смотреть нос; nil оставляет разворот как был.
local function teleportRaft(targetXZ, faceDir)
	local raft = raftModel()
	local primary = raft and raft.PrimaryPart
	if not (raft and primary) then return false end

	local pivot = raft:GetPivot()
	-- высоту и разворот не трогаем: за уровень воды отвечает AlignPosition в
	-- BoatMovement, а курс — его же lockedYaw
	--[[ ⚠️ РАЗВОРАЧИВАЕМ САМУ МОДЕЛЬ, А НЕ ТОЛЬКО КУРС.
	     Курс держит BoatMovement, и одного его хватило бы: alignOrientation
	     довернул бы плот сам. Но доворот занял бы несколько кадров уже ПОСЛЕ
	     снятия шторки — игрок увидел бы, как плот разворачивается сам собой.
	     Поэтому модель ставится сразу в нужный разворот, а курс задаётся тем же
	     направлением: физике нечего исправлять.
	     Разворот считаем как поворот вокруг Y от текущего носа к нужному, а не
	     строим CFrame.lookAt: у плота свой крен и дифферент, и lookAt их сбросил
	     бы, положив модель ровно — на воде это видно сразу. ]]
	local keepRot = pivot - pivot.Position
	if faceDir then
		local look = pivot.LookVector
		local yawNow = math.atan2(-look.X, -look.Z)
		local yawWant = math.atan2(-faceDir.X, -faceDir.Z)
		keepRot = CFrame.Angles(0, yawWant - yawNow, 0) * keepRot
	end
	local target = CFrame.new(targetXZ.X, pivot.Position.Y, targetXZ.Z) * keepRot
	local delta = target * pivot:Inverse()

	local riders = ridersOf(pivot.Position)

	--[[ ⚠️ ПЕРЕНОСИМ ПОД ЯКОРЕМ. Это не перестраховка, а тот же приём, которым
	     переносит плот загрузка сейва (RaftSaveSystem.pivotRaftSafely).
	     PivotTo по модели пишет CFrame каждой детали, а их у плота тысячи, и
	     все они СВОБОДНЫ: решатель получает всю сборку разом в новой точке и
	     доразбирается с ней уже на месте — это длинный кадр и рывок ровно в
	     момент прибытия. Заякоренная сборка переносится без физики вовсе.
	     Отпускаем через полтора десятка сотых: столько нужно, чтобы физика
	     увидела новое положение и не дёрнула плот обратно. Отпускаем ровно те
	     детали, что были свободны, — приваренный декор и якорь трогать нельзя. ]]
	local lin = primary.AssemblyLinearVelocity
	local ang = primary.AssemblyAngularVelocity

	local wasFree = {}
	for _, d in ipairs(raft:GetDescendants()) do
		if d:IsA("BasePart") and not d.Anchored then
			wasFree[#wasFree + 1] = d
			d.Anchored = true
		end
	end

	raft:PivotTo(target)

	task.delay(0.15, function()
		for _, d in ipairs(wasFree) do
			if d.Parent then d.Anchored = false end
		end
		if primary.Parent then
			primary.AssemblyLinearVelocity = lin
			primary.AssemblyAngularVelocity = ang
		end
	end)

	for _, r in ipairs(riders) do
		r.hrp.CFrame = delta * r.hrp.CFrame
	end
	return true
end

local voyaging = false

-- local: глобальная функция здесь никому не нужна, а имя startVoyage слишком
-- общее, чтобы висеть в _G рядом с чужими хуками
local function startVoyage(isle)
	if voyaging then return end
	local raft = raftModel()
	if not raft then return end
	voyaging = true

	-- ⚠️ ШТОРКА — ВСЕМ ПАССАЖИРАМ, А НЕ ТОЛЬКО НАЖАВШЕМУ: уезжает плот целиком,
	-- и соседа по палубе, которому ничего не показали, просто выбросило бы в
	-- другую точку океана посреди кадра.
	-- model — имя ассета (TropicIsland_SCENE…): по нему шторка выбирает картинку
	-- острова; icon — явный выбор картинки атрибутом MapIcon на модели, если задан.
	local info = {
		island = isle.id, name = isle.name, kind = isle.type,
		model = isle.model.Name, icon = isle.model:GetAttribute("MapIcon"),
	}
	for _, r in ipairs(ridersOf(raft:GetPivot().Position)) do
		teleportEvent:FireClient(r.player, "start", info)
	end
	raft:SetAttribute("SailHold", true)

	task.delay(COVER_TIME, function()
		local rp = raftPos()
		local from = Vector3.new(rp.X, 0, rp.Z)
		local to = Vector3.new(isle.pos.X, 0, isle.pos.Z)
		local dir = to - from
		-- плот всплывает со СТОРОНЫ, с которой шёл: так остров оказывается перед
		-- носом, а не за спиной, и игрок сразу видит, куда приплыл
		dir = (dir.Magnitude > 1) and dir.Unit or Vector3.new(0, 0, 1)
		local spot = to - dir * (islandRadius(isle) + ARRIVE_GAP)
		-- нос — на остров: плот всплывает в стороне от берега, и смотреть он
		-- должен туда, куда игрок плыл, а не туда, откуда его унесло течением
		teleportRaft(spot, dir)
		if typeof(_G.SetRaftCourse) == "function" then
			pcall(_G.SetRaftCourse, dir, true)
		end

		task.delay(SETTLE_TIME, function()
			local r = raftModel()
			if r then r:SetAttribute("SailHold", nil) end
			-- «готово» шлём всем: тот, кто уже дома, шторки не видел, и лишнее
			-- событие ему безвредно, а вот пассажир, у которого перед этим
			-- сменился персонаж, иначе остался бы в темноте до аварийного таймера
			teleportEvent:FireAllClients("done")
			voyaging = false
			for _, plr in ipairs(Players:GetPlayers()) do
				dataEvent:FireClient(plr, snapshot(plr))
			end
		end)
	end)
end

-- ⚠️ ЦЕНУ СЧИТАЕТ СЕРВЕР ПО ТОЙ ЖЕ ФОРМУЛЕ, ЧТО РИСУЕТ КНОПКА.
-- Клиент присылает только id острова: приняв его цену, мы бы отдали управление
-- балансом клиенту.
sailEvent.OnServerEvent:Connect(function(player, id)
	local isle = islands[tonumber(id) or -1]
	if not isle or not isle.model.Parent then return end
	if not isle.seen then
		sailEvent:FireClient(player, "denied", "Остров не изучен — добраться можно только вручную")
		return
	end

	local rp = raftPos()
	-- в студах: формула больше не зависит от масштаба карты
	local cost = Map.sailCost(isle.pos.X - rp.X, isle.pos.Z - rp.Z)

	-- ⚠️ cost — в литрах (так рисует кнопка), бак — в миллилитрах. Сравниваем и
	-- списываем в мл, иначе рейс стоит 4 мл и бак «не худеет».
	local costMl = cost * Map.OIL_UNIT_ML
	local tank = OilCanister.findTank(Workspace)
	local haveMl = tank and OilCanister.tankStored(tank) or 0
	if haveMl < costMl then
		sailEvent:FireClient(player, "denied", ("Нужно %d л нефти, есть %s"):format(
			cost, OilCanister.formatVolume(haveMl)))
		return
	end
	-- ⚠️ ПРОВЕРЯЕМ ПЛОТ ДО СПИСАНИЯ. Нет плота — нет и рейса, а нефть уже ушла бы:
	-- вернуть её потом некому, бак общий и его мог опустошить кто-то ещё.
	if not raftModel() then
		sailEvent:FireClient(player, "denied", "Плот не найден")
		return
	end
	if voyaging then
		sailEvent:FireClient(player, "denied", "Плот уже в пути")
		return
	end
	if not raftDock() then
		sailEvent:FireClient(player, "denied",
			"Нужен причал с лодкой: скрафти его и поставь на плот")
		return
	end
	if tooClose(isle, rp) then
		sailEvent:FireClient(player, "denied", "Плот и так у этого острова")
		return
	end
	tank:SetAttribute(OilCanister.TANK_ATTR, math.max(0, OilCanister.tankStored(tank) - costMl))

	_G.MapMooredIsland = isle.id
	sailEvent:FireClient(player, "sailing", isle.id, cost)
	dataEvent:FireClient(player, snapshot(player))
	startVoyage(isle)
end)

Players.PlayerRemoving:Connect(function(player)
	player:SetAttribute("MapOpen", false)
end)

print(LOG .. (" готова: островов в реестре %d"):format(nextId))
