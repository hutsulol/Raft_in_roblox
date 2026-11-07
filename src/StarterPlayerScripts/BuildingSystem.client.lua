print, warn = (function() local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы; БЕЗ local: файл на пределе 200 локалей
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))
local camera = workspace.CurrentCamera

local placeBlockEvent = ReplicatedStorage:WaitForChild("PlaceBlock")
local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate")

-- ⚠️ ШАБЛОНЫ ИЩЕМ ПО ИМЕНИ, А НЕ ПО МЕСТУ.
-- Здесь стоял WaitForChild("Raft_part"), и когда модели разложили по папкам
-- (Buildings_Raft/Floor), он стал ждать вечно: скрипт молча вис на этой строке,
-- молоток в руках — а меню стройки не открывалось, и в логе ни слова.
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))
-- Иконки этого меню рисуются самой моделью — см. ModelIcon.
local ModelIcon = require(ReplicatedStorage:WaitForChild("ModelIcon"))
local raftPartTemplate = AssetFind.wait(20, "Raft_part")
if not raftPartTemplate then
	warn("[BuildingSystem/клиент] в ReplicatedStorage нет модели Raft_part "
		.. "(искал во всех папках) — стройка выключена")
	return
end
-- ⚠️ ПЕЧАТАЕМ, ЧТО ИМЕННО НАШЛОСЬ.
-- Шаблоны ищутся по имени во всех папках, и одноимённая деталь внутри чужой
-- модели однажды подменила настил связкой брёвен — в меню и в призраке. По имени
-- этого не видно, по полному пути видно сразу.
print(("[Стройка/клиент] шаблон пола: %s"):format(raftPartTemplate:GetFullName()))

-- Русские подписи ресурсов для ценников (ключи остаются английскими)
local ResourceNamesRu = require(ReplicatedStorage:WaitForChild("ResourceNamesRu"))
-- УКРЕПЛЕНИЕ ПОЛА: цена и правила общие с сервером
local RaftReinforce = require(ReplicatedStorage:WaitForChild("RaftReinforce"))
-- Имена и поворот сети — из общего модуля, а не своей копией: разъехавшиеся копии
-- дали бы призрак от одной модели, а постройку от другой (см. RaftNetFit).
--
-- ⚠️ ЭТОТ ФАЙЛ УПЁРСЯ В ПРЕДЕЛ LUAU НА ЛОКАЛЬНЫЕ ПЕРЕМЕННЫЕ (200 на область).
-- Две лишние строки `local` наверху — и скрипт перестаёт КОМПИЛИРОВАТЬСЯ целиком:
--   BuildingSystem:2744: Out of local registers ... exceeded limit 200
-- Снаружи это выглядит как «меню молотка не открывается вовсе», без единой другой
-- строчки в логе. Поэтому модуль разворачиваем в блоке do..end: внутри него
-- временная переменная регистр верхнего уровня не занимает.
local netTemplate, NET_ROT_FIX
do
	local NetFit = require(ReplicatedStorage:WaitForChild("RaftNetFit"))
	netTemplate = AssetFind.find(table.unpack(NetFit.TEMPLATE_NAMES))
	NET_ROT_FIX = NetFit.rotFix(netTemplate)
end
-- Поправка меряется по тому же шаблону тем же кодом, что на сервере, — разойтись
-- превью с постановкой больше не может по устройству (RaftNetFit).

-- Смещение ЦЕНТРА модели относительно её ПИВОТА (в осях пивота).
-- У Raft_part пивот сидит НЕ в центре тайла (сдвинут ~2 студа), у Net_Part — ровно
-- в центре. Клетка считается «под пивот доски», поэтому сеть, поставленная по тому
-- же CFrame, уезжала на величину этого смещения. Приводим обе к ЦЕНТРУ клетки.
local function pivotCenterDelta(template, scale)
	if not template or not template:IsA("Model") then return Vector3.zero end
	local ok, delta = pcall(function()
		local bbCF = template:GetBoundingBox()
		return template:GetPivot():ToObjectSpace(bbCF).Position
	end)
	return ok and (delta * (scale or 1)) or Vector3.zero
end
-- ШАБЛОН ПО НЕСКОЛЬКИМ ИМЁНАМ. Модели плота переименовывались (стена стала
-- raft_wall вместо wall_model_wood), и жёсткое имя молча давало nil — превью
-- подставляло запасной шаблон, из-за чего вместо стены показывалась плита пола.
local findTemplateNamed = AssetFind.find

-- ВРЕМЕННО: сверка высоты стены между превью и постановкой (см. печать ниже).
local WALL_DEBUG = true
local lastWallDebug = 0

local beamTemplate = AssetFind.find("beam")
local wallPanelTemplate = findTemplateNamed("raft_wall", "Raft_wall", "wall_model_wood")
local wallArchTemplate = findTemplateNamed("raft_wall_arch", "Raft_wall_arch", "wall_model_wood_arch")
-- Варианты стен и общая просадка по высоте — в общем модуле: те же числа читают
-- сервер и загрузка сейва (см. RaftWallDefs).
local WallDefs = require(ReplicatedStorage:WaitForChild("RaftWallDefs"))
local doorTemplate = findTemplateNamed("raft_door", "Raft_door", "Door_Wood")

-- Deck grid spacing in studs. НОВЫЙ ПЛОТ: Raft_part ровно 10x2.3x10, масштаб 1,
-- origin без поворотов, пивот в центре тайла. HARDCODED on purpose: measuring it
-- at runtime raced with raft replication on the client and desynced the preview
-- from the actual placement. Keep EQUAL to the server copy
-- (BuildingSystem.server.server.lua); update both if you rebuild the raft.
local GRID_SIZE = 10

-- Шаблон Raft_part теперь сразу размером с клетку — масштабировать нечего.
-- Держать равным серверной копии.
local TILE_SCALE = 1
-- Балки остались от старого плота (решётка 9.8428) — дотягиваем до новой
-- клетки: 1.26 * 10 / 9.8428 ≈ 1.28. Walls are NOT scaled.
local BEAM_SCALE = 1.28

-- Пивот доски масштабируется вместе с тайлом, у сети масштаб не меняем (она уже
-- нужного размера). ДЕРЖАТЬ РАВНЫМ серверной копии.
local RAFT_PIVOT_DELTA = pivotCenterDelta(raftPartTemplate, TILE_SCALE)
local NET_PIVOT_DELTA  = pivotCenterDelta(netTemplate, 1)

-- worldCF — CFrame ПИВОТА доски для клетки. Возвращает CFrame пивота СЕТИ так,
-- чтобы её центр встал ровно в центр той же клетки (и без наклона 90°).
local function netCFFromRaftCF(worldCF)
	-- ⚠️ ДВЕ РАЗНЫЕ ПОПРАВКИ, И НУЖНЫ ОБЕ.
	--   1) поворот: гасим поворот пивота модели (см. RaftNetFit);
	--   2) центрирование: пивот сидит НЕ в центре геометрии (у Raft_collector
	--      PivotOffset Position = 0, -1.302, 0), поэтому PivotTo по клетке уводит
	--      сеть по вертикали — она вставала заметно ниже настила.
	-- Один раз я убрал вторую вместе с первой, и сеть провалилась под палубу.
	-- Считаем как у доски: берём ЦЕНТР клетки и от него отступаем на смещение пивота.
	local centerPos = (worldCF * CFrame.new(RAFT_PIVOT_DELTA)).Position
	local rot = (worldCF * NET_ROT_FIX).Rotation
	return CFrame.new(centerPos) * rot * CFrame.new(-NET_PIVOT_DELTA)
end

-- ВЫСОТЫ МЕРЯЕМ САМИ, атрибут — только запасной вариант.
-- Раньше было наоборот: клиент верил атрибуту PanelHeight на шаблоне пола,
-- который пишет сервер. Атрибут переживает сохранение плейса, поэтому после
-- смены модели стены он оставался от СТАРОЙ — превью висело выше, чем стена
-- реально вставала. Меряем ту же модель, что и сервер, — расхождение исключено.
-- Замер общий с сервером и загрузкой сейва (RaftWallDefs.heightOf): он считает
-- ТОЛЬКО собственную геометрию шаблона, без вложенных моделей. Из-за них превью
-- и вставало выше постановки — подробности там же, у функции.
local measureHeight = WallDefs.heightOf

local BEAM_HEIGHT = raftPartTemplate:GetAttribute("BeamHeight") or 0
local BEAM_INSET = raftPartTemplate:GetAttribute("BeamInset") or 0
-- ⚠️ ВЫСОТУ МЕРЯЕМ ПРИ ПЕРВОМ ПОКАЗЕ ПРЕВЬЮ, А НЕ НА СТАРТЕ СКРИПТА.
-- Замер на старте — это замер в самый неудачный момент: модели ещё едут по сети,
-- а сервер в это же время разбирает шаблоны (выносит вложенные стены из raft_wall).
-- Клиент успевал измерить недособранное дерево, получал ЧУЖУЮ высоту и всю сессию
-- рисовал призрак выше, чем стена реально встаёт. Формулы при этом совпадали
-- построчно с серверными, поэтому расхождение и не находилось глазами.
-- К моменту первого превью игрок уже взял молоток и открыл меню: всё на месте.
-- Кэшируем только удачный замер, нулевой не запоминаем.
local heightCache = {}
local function wallHeight(template)
	if not template then return 0 end
	local h = heightCache[template]
	if h then return h end
	h = measureHeight(template)
	if h > 0 then heightCache[template] = h end
	return h
end
-- Fallback measurements if attributes not set yet
if BEAM_HEIGHT == 0 and beamTemplate then
	if beamTemplate:IsA("Model") then
		local size = beamTemplate:GetExtentsSize()
		BEAM_HEIGHT = size.Y
		BEAM_INSET = math.max(size.X, size.Z) / 2
	elseif beamTemplate:IsA("BasePart") then
		BEAM_HEIGHT = beamTemplate.Size.Y
		BEAM_INSET = math.max(beamTemplate.Size.X, beamTemplate.Size.Z) / 2
	end
end

-- ⚠️ НОВЫЕ СТЕНЫ ДОБАВЛЯЮТСЯ СТРОКОЙ В ЭТУ ТАБЛИЦУ, А НЕ КОПИЕЙ ВЕТКИ.
-- Стена, окно и полустена стоят на ребре клетки по одной и той же геометрии и
-- различаются ровно моделью и высотой. У «Стены» и «Проёма» ветки свои — им
-- нужны отдельные ключи (дверь ищет проём) и событие квеста, — а у остальных
-- вариантов различий нет вовсе, и четвёртая копия одинакового кода была бы
-- четвёртым местом, где потом забудут поправить.
-- Шаблоны и высоты вариантов стен собираем из общего списка: сам список, цены и
-- просадка живут в RaftWallDefs, чтобы сервер, превью и загрузка сейва считали
-- одно и то же. Новая стена добавляется строкой ТАМ, а не здесь.
-- высоту здесь НЕ считаем: её берёт wallHeight в момент показа превью
local EDGE_WALLS = {}
for kind, def in pairs(WallDefs.EdgeWalls) do
	EDGE_WALLS[kind] = { template = WallDefs.findModel(ReplicatedStorage, def.names) }
end

local PREVIEW_COLOR_VALID = Color3.fromRGB(80, 200, 80)
local PREVIEW_COLOR_INVALID = Color3.fromRGB(200, 80, 80)

local LOG_ICON = "rbxassetid://110032041583533"
local FLOOR_ICON = "rbxassetid://114819085093343"
local WALL_ICON = "rbxassetid://103259353018381"
local BEAM_ICON = "rbxassetid://128953076654373"
local ARCH_ICON = "rbxassetid://90064054384398"

-- Beam/wall X-axis correction (pivot offset in template)
local BEAM_X_OFFSET = 1

-- Fine-tune for the FLOOR tile only (studs, raft-local X/Z), on top of the
-- auto-measured grid + phase. The grid already lines one axis up; nudge the
-- other here until the tile sits flush with the deck. Must stay identical to the
-- server copy. Updates live on save — flip sign or move to the other axis as needed.
local FLOOR_FINE_X = 0
local FLOOR_FINE_Z = 0

-- Прозрачность заливки подсветки укрепляемой доски
local REINFORCE_FILL = 0.55

-- Building items organized by category
local categories = {
	{
		name = "Floors",
		icon = FLOOR_ICON,
		-- УКРЕПЛЕНИЕ: не новый тайл, а замена меша и текстуры у уже стоящей доски
		-- (цель наоборот — клетка, которая ЗАНЯТА полом). Своей плитки у него нет:
		-- это режим плитки пола — значок ⬆ в её углу (см. _G.BuildFloorPick).
		reinforce = {id = "reinforce", name = "Укреплённый пол", icon = FLOOR_ICON,
			cost = RaftReinforce.COST, costType = RaftReinforce.COST_TYPE, buildType = "reinforce"},
		items = {
			-- ⚠️ ЦЕНА ИЗ ТРЁХ РЕСУРСОВ. Поля cost/costType остаются ради всего, что
			-- читает цену по-старому, и в них лежит ГЛАВНЫЙ ресурс; полная цена — в
			-- costs, и она обязана совпадать с RAFT_COSTS на сервере.
			{id = "raft", name = "Raft Floor", icon = FLOOR_ICON, cost = 2, costType = "Log",
				costs = { Log = 2, Plastic = 2, Rope = 1 }, buildType = "raft"},
			-- сеть: тот же тайл пола, но из верёвки (Rope крафтится из 4 листвы)
			{id = "net", name = "Сеть", icon = FLOOR_ICON, cost = 2, costType = "Rope", buildType = "net"},
			-- ПОЛ ВТОРОГО ЭТАЖА: кладётся на четыре БОЛЬШИЕ стены над клеткой пола.
			-- Правила, цена и геометрия — RaftUpperFloor (их же читает сервер).
			-- ⚠️ require по месту: файл у предела 200 локалей.
			{id = "floor_upper", name = "Пол 2 этажа", icon = FLOOR_ICON,
				cost = require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).COSTS.Log, costType = "Log",
				costs = require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).COSTS, buildType = "floor_upper"},
			-- ЛЕСТНИЦА на второй этаж: на любую клетку пола, R — повернуть (RaftStairs).
			-- ⚠️ require по месту: файл у предела 200 локалей.
			{id = "stairs", name = "Лестница", icon = FLOOR_ICON,
				cost = require(ReplicatedStorage:WaitForChild("RaftStairs")).COSTS.Log, costType = "Log",
				costs = require(ReplicatedStorage:WaitForChild("RaftStairs")).COSTS, buildType = "stairs"},
		},
	},
	{
		-- ⚠️ ОТДЕЛЬНАЯ КАТЕГОРИЯ ДЛЯ ОСТРОВА.
		-- Всё остальное в молотке строится по клеткам плота, а вышка и дом
		-- ставятся на свободный рельеф суши. Общего у них только меню: выбор
		-- пункта включает режим, а сам призрак и проверку места ведёт
		-- OilRigPlace — сеточная логика к рельефу неприменима, и смешивать их
		-- нельзя.
		name = "Остров",
		icon = LOG_ICON,
		items = {
			{id = "oilrig", name = "Нефтевышка", icon = LOG_ICON,
				cost = 12, costType = "Log", buildType = "oilrig"},
			{id = "house", name = "Дом", icon = LOG_ICON,
				cost = 20, costType = "Log", buildType = "house"},
			-- ферма: цена из FarmDefs (там же её читает сервер FarmSystem).
			-- ⚠️ require прямо здесь, а не в local наверху: файл у предела 200 локалей.
			{id = "farm", name = "Ферма", icon = LOG_ICON,
				cost = require(ReplicatedStorage:WaitForChild("FarmDefs")).COST,
				costType = require(ReplicatedStorage:WaitForChild("FarmDefs")).COST_TYPE, buildType = "farm"},
		},
	},
	{
		name = "Walls",
		icon = LOG_ICON,
		items = {
			-- Балок больше нет: стены ставятся прямо на край клетки пола, с любой
			-- из 4 сторон. Раньше требовалось сперва выставить два столба, и без
			-- них стена не ставилась вообще.
			{id = "wall_panel", name = "Стена", icon = WALL_ICON, cost = 3, costType = "Log", buildType = "wall_panel"},
			-- Иконки пока общие со стеной: своих картинок у окна и полустены нет. Как
			-- появятся — меняется только icon, остальное к нему не привязано.
			{id = "wall_window", name = "Окно", icon = WALL_ICON, cost = 3, costType = "Log", buildType = "wall_window"},
			{id = "wall_half", name = "Полустена", icon = WALL_ICON, cost = 2, costType = "Log", buildType = "wall_half"},
			-- ⚠️ ЕДИНСТВЕННАЯ ПОСТРОЙКА ИЗ ДВУХ РЕСУРСОВ.
			-- Поля cost/costType остаются ради всего, что читает цену по-старому
			-- (проверки ниже, сервер, подсказки), а costs — полная цена. Держать
			-- их согласованными: в cost идёт ГЛАВНЫЙ ресурс.
			{id = "wall_leaf", name = "Листва", icon = WALL_ICON, cost = 2, costType = "Log",
				costs = { Log = 2, Leaves = 4 }, buildType = "wall_leaf"},
			{id = "wall_leaf_half", name = "Ограда", icon = WALL_ICON, cost = 2, costType = "Log",
				costs = { Log = 2, Leaves = 2 }, buildType = "wall_leaf_half"},
			-- ⚠️ ПРОЁМ И ДВЕРЬ УБРАНЫ ТОЛЬКО ИЗ МЕНЮ.
			-- Ветки установки, ключи и восстановление из сейва оставлены на месте:
			-- у кого они уже стоят на плоту — те никуда не денутся, а вернуть
			-- постройку в меню будет одной строкой. Дверь без проёма всё равно не
			-- ставится, так что убирать их порознь нельзя.
		},
	},
}

-- ПРИЧАЛ С ЛОДКОЙ (Boat_3x). Не пункт меню молотка, а отдельный тул: взял в руки —
-- включился тот же режим стройки, но с единственной постройкой и без меню.
-- Ставится центром в СРЕДНЮЮ из трёх клеток, R разворачивает вдоль другой оси.
local DOCK_TOOL = "Boat_3x"
local DOCK_ITEM = {
	id = "dock3", name = "Причал с лодкой", buildType = "dock3",
	cost = 0, costType = "Log",
}
-- Поворот на ЧЕТЫРЕ стороны: 0/1/2/3 → 0°/90°/180°/270°. Двух мало — при 0° и 180°
-- клетки те же, но причал развёрнут другой стороной (где лодка, где столб).
local dockRot = 0
local showDockHint   -- определяется ниже, вызывается из closeBuildMode выше по файлу

-- ═══════════ ЗВУК УКРЕПЛЕНИЯ ═══════════
-- Варианты и номер выбранного лежат в RaftReinforce (SOUND_VARIANTS + SOUND_PICK),
-- здесь — воспроизведение и перебор.
-- ⚠️ СЕКЦИЯ СТОИТ ЗДЕСЬ, А НЕ РЯДОМ С ОСТАЛЬНЫМИ ЗВУКАМИ ВНИЗУ ФАЙЛА: в Lua
-- local function видна только НИЖЕ своего объявления, а playVariant зовёт панель
-- переключателя внутри buildUI. Снизу имя ушло бы в глобальные и было бы nil.
local reinforcePick = RaftReinforce.SOUND_PICK

-- Готовый Sound для варианта. Существующий звук КЛОНИРУЕМ: иначе правка тона и
-- громкости осталась бы на оригинале и испортила его во всей остальной игре.
-- Экземпляры КЭШИРУЕМ и переигрываем: создавать Sound на каждый клик — это лишняя
-- загрузка ассета перед стартом, то есть ещё немного задержки на ровном месте.
local variantCache = {}

local function variantSound(i)
	local cached = variantCache[i]
	if cached and cached.Parent then return cached end

	local v = RaftReinforce.SOUND_VARIANTS[i]
	if not v then return nil end
	local s
	if v.sound then
		local src = SoundService:FindFirstChild(v.sound, true)
		if not (src and src:IsA("Sound")) then return nil end
		s = src:Clone()
	elseif v.id then
		s = Instance.new("Sound")
		s.SoundId = v.id
	else
		return nil
	end
	s.Name = "ReinforceVariant" .. i
	s.Volume = v.volume or RaftReinforce.SOUND_VOLUME
	s.PlaybackSpeed = v.pitch or 1
	s.Parent = SoundService
	variantCache[i] = s
	return s
end

-- Играет вариант по номеру. Возвращает false, если такого звука в игре нет, —
-- чтобы перебор не выглядел «кнопка не работает».
local function playVariant(i)
	local v = RaftReinforce.SOUND_VARIANTS[i]
	if not v then return false end
	local s = variantSound(i)
	if not s then
		warn(("[Укрепление] вариант %d (%s) не найден: нет звука %s")
			:format(i, v.label, v.sound or v.id or "?"))
		return false
	end
	local start = v.start or 0
	-- ⚠️ TimePosition ставим ПОСЛЕ Play: до старта движок его сбрасывает, и обрезка
	-- тишины в начале файла просто не срабатывала.
	s.TimePosition = start
	s:Play()
	s.TimePosition = start
	return true
end

-- Объявлено заранее: тело ниже, после getRaft, а звать надо уже отсюда.
local keepFooting

local function playReinforceSound()
	-- ⚠️ ВЗМАХ МОЛОТКОМ ВЕШАЕМ СЮДА, А НЕ НА СЕМЬ ВЕТОК КЛИКА.
	-- Эта функция и playPlaceSound — единственные две точки, через которые
	-- проходит КАЖДАЯ удавшаяся установка: клетка, сеть, док, балка, стена, арка,
	-- дверь. Разложить вызов по веткам значило бы семь мест, где о нём забудут.
	if _G.PlayHammerSwing then _G.PlayHammerSwing() end
	keepFooting()
	if playVariant(reinforcePick) then return end
	-- выбранный вариант не завёлся — падаем на первый, но громко об этом сообщаем
	playVariant(1)
end

-- Заранее создаём звук выбранного варианта, чтобы ПЕРВЫЙ клик не ждал загрузку.
task.spawn(function() variantSound(reinforcePick) end)

-- Подпись на панели переключателя; обновляется и с кнопок, и с клавиши M.
local reinforceSoundLabel = nil

local function pickLabelText()
	local n = #RaftReinforce.SOUND_VARIANTS
	local v = RaftReinforce.SOUND_VARIANTS[reinforcePick]
	return ("♪  Звук %d/%d  ·  %s"):format(reinforcePick, n, v and v.label or "?")
end

-- Единственная точка смены варианта: и подпись, и лог, и проигрывание — здесь,
-- чтобы кнопки и клавиша не разъезжались.
local function setReinforcePick(i)
	local n = #RaftReinforce.SOUND_VARIANTS
	reinforcePick = ((i - 1) % n) + 1
	local v = RaftReinforce.SOUND_VARIANTS[reinforcePick]
	if reinforceSoundLabel and reinforceSoundLabel.Parent then
		reinforceSoundLabel.Text = pickLabelText()
	end
	print(("[Укрепление] звук %d/%d — %s  (вписать в RaftReinforce.SOUND_PICK)")
		:format(reinforcePick, n, v and v.label or "?"))
	playVariant(reinforcePick)
end

local function bindSoundCycle()
	ContextActionService:BindAction("ReinforceSoundCycle", function(_, state)
		if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
		setReinforcePick(reinforcePick + 1)
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.M)
end

local isBuilding = false
local dockMode = false
local selectedCategory = 1
local selectedItem = nil
local buildingUI = nil
local previewPart = nil
local inventory = { Log = 0 }
local renderConnection = nil
local hammerWatchConnection = nil

inventoryEvent.OnClientEvent:Connect(function(inv)
	inventory = inv
end)

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

-- ─── Фаза решётки ───
-- Определена ДО getFloorOffsets, потому что нужна ему. Мерит дробный сдвиг
-- реальных досок относительно PrimaryPart. ЛЮБАЯ доска, не только «без GridX»,
-- и нормализация в [0, gridSize) — держать РАВНЫМ серверной копии: иначе решётка
-- превью уезжает на полклетки или на целую клетку от серверной.
local function getGridPhase(raft, gridSize)
	local primary = raft and raft.PrimaryPart
	if not primary then return 0, 0 end
	local restYaw = primary:GetAttribute("RestYaw")
	if not restYaw then
		local _, yaw = primary.CFrame:ToEulerAnglesYXZ()
		restYaw = yaw
	end
	local flatCF = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0)

	-- ГОЛОСОВАНИЕ БОЛЬШИНСТВОМ — держать РАВНЫМ серверной копии getGridPhase:
	-- по «первой попавшейся» доске сервер и клиент могли взять разные доски
	-- (кривой тайл из прошлых сессий, другой порядок детей) и получить разную
	-- фазу — доска ставилась со сдвигом относительно призрака.
	local counts, reps = {}, {}
	for _, child in raft:GetChildren() do
		if child.Name == "Raft_part" then
			local pos
			if child:IsA("Model") then
				-- живая геометрия, а не WorldPivot (см. getFloorOffsets)
				local pp = child.PrimaryPart
				if pp then
					pos = pp.Position
				else
					--[[ ⚠️ НЕ ПО ГАБАРИТНОМУ БОКСУ. У сети в модели есть деталь, уводящая
					     бокс на ~90 студов вперёд: клетка сети «числилась» на девять
					     клеток дальше, а её настоящая клетка выглядела свободной —
					     туда ставилась вторая сеть или пол. Берём деталь полотна
					     (raft_collector), иначе самую крупную деталь, и только потом бокс. ]]
					local anchor = nil
					local bestVol = -1
					for _, d in ipairs(child:GetDescendants()) do
						if d:IsA("BasePart") then
							if d.Name:lower() == "raft_collector" then anchor = d break end
							local vol = d.Size.X * d.Size.Y * d.Size.Z
							if vol > bestVol then anchor, bestVol = d, vol end
						end
					end
					if anchor then
						pos = anchor.Position
					else
						local ok, bb = pcall(function() return child:GetBoundingBox() end)
						pos = ok and bb.Position or nil
					end
				end
			elseif child:IsA("BasePart") then
				pos = child.Position
			end
			if pos then
				local lp = flatCF:PointToObjectSpace(pos)
				local function canon(v)
					local p = (v - math.round(v / gridSize) * gridSize) % gridSize
					if p > gridSize / 2 then p -= gridSize end
					return p
				end
				local px, pz = canon(lp.X), canon(lp.Z)
				local key = (math.round(px * 4) % (gridSize * 4)) .. "_"
					.. (math.round(pz * 4) % (gridSize * 4))
				counts[key] = (counts[key] or 0) + 1
				reps[key] = reps[key] or { px, pz }
			end
		end
	end
	local bestKey, bestN
	for k, n in pairs(counts) do
		if not bestN or n > bestN then bestKey, bestN = k, n end
	end
	if bestKey then return reps[bestKey][1], reps[bestKey][2] end
	return 0, 0
end

local function getFloorOffsets()
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return {} end

	local offsets = {}
	local seen = {}
	local primary = raft.PrimaryPart

	-- Use a yaw-only CFrame for grid coordinate detection, matching the
	-- placement system (which uses restYaw). Using primary.CFrame directly
	-- would include pitch/roll that can mix world-Y into local X/Z and
	-- collapse multiple tiles to the same grid coordinate.
	local restYaw = primary:GetAttribute("RestYaw")
	if not restYaw then
		local _, yaw, _ = primary.CFrame:ToEulerAnglesYXZ()
		restYaw = yaw
	end
	-- ФАЗА ОБЯЗАТЕЛЬНА, как в серверной копии: без неё координаты клеток здесь
	-- считались в другой решётке, чем на сервере.
	local phaseX, phaseZ = getGridPhase(raft, GRID_SIZE)
	local flatCF = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0) * CFrame.new(phaseX, 0, phaseZ)

	-- КООРДИНАТА — ПО ФАКТИЧЕСКОМУ МЕСТУ, как в серверной копии: скопированные в
	-- Studio тайлы приносят чужие GridX/GridZ, и по атрибутам весь пол
	-- схлопывался в одну клетку. (Держать равным серверной getFloorOffsets.)
	for _, child in raft:GetChildren() do
		local isTile = child:GetAttribute("BuildType") == "raft"
			or child.Name == "Raft_part" or child.Name == "Net_Part" or child == primary
		if isTile then
			-- ⚠️ ПОЗИЦИЯ ТАЙЛА — ТОЛЬКО ПО ЖИВОЙ ГЕОМЕТРИИ.
			--
			-- Здесь стоял child:GetPivot().Position. У модели БЕЗ PrimaryPart
			-- это WorldPivot — фиксированный мировой CFrame, который НЕ едет
			-- следом за деталями, когда плот плывёт. Такие тайлы уползали по
			-- решётке на клетку в секунду: (1,4) → (1,5) → (1,6)… — и соседняя
			-- с ними клетка оставалась «без соседа», то есть строить рядом было
			-- нельзя. Именно так ломалось место возле монолита.
			--
			-- У модели С PrimaryPart GetPivot возвращает его CFrame, поэтому
			-- первая ветка полностью повторяет прежнее поведение — меняется
			-- только судьба сломанных тайлов.
			-- (Держать равным серверной копии.)
			local pos
			if child:IsA("Model") then
				local pp = child.PrimaryPart
				if pp then
					pos = pp.Position
				else
					--[[ ⚠️ НЕ ПО ГАБАРИТНОМУ БОКСУ. У сети в модели есть деталь, уводящая
					     бокс на ~90 студов вперёд: клетка сети «числилась» на девять
					     клеток дальше, а её настоящая клетка выглядела свободной —
					     туда ставилась вторая сеть или пол. Берём деталь полотна
					     (raft_collector), иначе самую крупную деталь, и только потом бокс. ]]
					local anchor = nil
					local bestVol = -1
					for _, d in ipairs(child:GetDescendants()) do
						if d:IsA("BasePart") then
							if d.Name:lower() == "raft_collector" then anchor = d break end
							local vol = d.Size.X * d.Size.Y * d.Size.Z
							if vol > bestVol then anchor, bestVol = d, vol end
						end
					end
					if anchor then
						pos = anchor.Position
					else
						local ok, bb = pcall(function() return child:GetBoundingBox() end)
						pos = ok and bb.Position or nil
					end
				end
			elseif child:IsA("BasePart") then
				pos = child.Position
			end
			-- ПРИЧАЛ ЗАНИМАЕТ НЕСКОЛЬКО КЛЕТОК, берём их из АТРИБУТОВ (держать равным
			-- серверной копии): пивот Boat_3x — центр габаритов, куда входят ещё
			-- лодка, столб и канат, и по позиции клетка считалась бы мимо.
			local dockSteps = child:GetAttribute("DockSteps")
			if dockSteps then
				local bx = child:GetAttribute("GridX") or 0
				local bz = child:GetAttribute("GridZ") or 0
				local sx = child:GetAttribute("DockDX") or 0
				local sz = child:GetAttribute("DockDZ") or 1
				for i = 0, dockSteps do
					local cx, cz = bx + sx * i, bz + sz * i
					local key = cx .. "_" .. cz
					if not seen[key] then
						seen[key] = true
						table.insert(offsets, { x = cx, z = cz })
					end
				end
			elseif pos then
				local localPos = flatCF:PointToObjectSpace(pos)
				local gridX = math.round(localPos.X / GRID_SIZE)
				local gridZ = math.round(localPos.Z / GRID_SIZE)
				local key = gridX .. "_" .. gridZ
				if not seen[key] then
					seen[key] = true
					table.insert(offsets, { x = gridX, z = gridZ })
				end
			end
		end
	end

	if not seen["0_0"] then
		table.insert(offsets, {x = 0, z = 0})
	end

	return offsets
end

-- ТАЙЛ ПОД КУРСОРОМ — ПРЯМЫМ РЕЙКАСТОМ, а не через решётку.
--
-- ⚠️ Через решётку это уже пробовали, и часть плота не отзывалась вообще:
-- у стартовых досок GridX/GridZ бывают чужими (копии из Studio), а у моделей без
-- PrimaryPart центр габаритов уезжает — так не работали центр плота и место возле
-- монолита. Рейкаст попадает ровно в ту доску, на которую смотрит игрок, и никакой
-- арифметики клеток для этого не нужно.
local reinforceRayParams = RaycastParams.new()
reinforceRayParams.FilterType = Enum.RaycastFilterType.Include
reinforceRayParams.IgnoreWater = true

local function tileFromMouse(allowUpper)   -- allowUpper: лестнице годится и пол 2 этажа
	local raft = getRaft()
	if not raft then return nil end
	reinforceRayParams.FilterDescendantsInstances = { raft }
	-- ⚠️ ЦЕЛИМСЯ ПО ЗАПОМНЕННОМУ ТАПУ, А НЕ ПО «ГДЕ МЫШЬ».
	-- На телефоне «мышь» встаёт в точку последнего касания, а последним касанием
	-- бывает нажатие на кнопку «Построить» — прицел срывался на неё. _G.BuildAim
	-- хранит последний тап ПО МИРУ. Читаем прямо здесь, без функции-обёртки: файл
	-- упёрся в предел Luau на локальные переменные, и даже две коротких `local
	-- function` наверху ломают компиляцию всего меню.
	local ray = camera:ScreenPointToRay(
		(_G.BuildAim and _G.BuildAim.x) or mouse.X,
		(_G.BuildAim and _G.BuildAim.y) or mouse.Y)
	local res = workspace:Raycast(ray.Origin, ray.Direction * 2000, reinforceRayParams)
	if not (res and res.Instance) then return nil end

	-- поднимаемся от попавшей детали до ПРЯМОГО ребёнка плота — это и есть тайл
	local node = res.Instance
	while node and node.Parent and node.Parent ~= raft do
		node = node.Parent
	end
	if not (node and node.Parent == raft) then return nil end
	if not (RaftReinforce.isFloorTile(node) or (allowUpper and (node.Name == "Raft_floor_upper"
		or node:GetAttribute("BuildType") == "floor_upper"))) then return nil end
	return node
end

-- Подсветка доски под курсором: зелёная — можно укрепить, красная — нельзя
-- (не хватает ресурса или доска уже укреплена). Highlight адорнится к любой модели
-- и детали, поэтому ничего не надо считать по геометрии.
local reinforceHighlight = nil

local function setReinforceHighlight(tile, valid)
	if not tile then
		if reinforceHighlight then
			reinforceHighlight.Adornee = nil
			reinforceHighlight.Enabled = false
		end
		return
	end
	if not reinforceHighlight then
		reinforceHighlight = Instance.new("Highlight")
		reinforceHighlight.Name = "ReinforceHighlight"
		reinforceHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
		reinforceHighlight.FillTransparency = REINFORCE_FILL
		reinforceHighlight.OutlineTransparency = 0
		reinforceHighlight.Parent = workspace
	end
	local color = valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID
	reinforceHighlight.Adornee = tile
	reinforceHighlight.Enabled = true
	reinforceHighlight.FillColor = color
	reinforceHighlight.OutlineColor = color
end

-- ПОВОРОТ КЛЕТКИ — как у БОЛЬШИНСТВА досок палубы: конвенция пивота модели
-- берётся с живых досок, одиночные ручные развороты отсекаются голосованием.
-- (Держать равным серверной копии getTileRotationCorrection.)
local function getTileRotationCorrection(raft)
	local primary = raft.PrimaryPart
	if not primary then return CFrame.new() end
	local counts, reps = {}, {}
	for _, child in raft:GetChildren() do
		if child.Name == "Raft_part" and child ~= primary then
			local tileCF
			if child:IsA("Model") then
				tileCF = child:GetPivot()
			elseif child:IsA("BasePart") then
				tileCF = child.CFrame
			end
			if tileCF then
				local rot = primary.CFrame:ToObjectSpace(tileCF).Rotation
				local xv, yv = rot.XVector, rot.YVector
				local key = string.format("%d,%d,%d|%d,%d,%d",
					math.round(xv.X * 10), math.round(xv.Y * 10), math.round(xv.Z * 10),
					math.round(yv.X * 10), math.round(yv.Y * 10), math.round(yv.Z * 10))
				counts[key] = (counts[key] or 0) + 1
				reps[key] = reps[key] or rot
			end
		end
	end
	local bestKey, bestN
	for k, n in pairs(counts) do
		if not bestN or n > bestN then bestKey, bestN = k, n end
	end
	return bestKey and reps[bestKey] or CFrame.new()
end

-- ВЫСОТА ЦЕНТРА ГАБАРИТОВ доски палубы над пивотом PrimaryPart, голосованием.
-- Геометрия к геометрии — конвенции пивотов шаблона и досок сокращаются.
-- (Держать равным серверной копии deckCenterRestY.)
local function deckCenterRestY(raft)
	local primary = raft.PrimaryPart
	if not primary then return 0 end
	local restCF = primary:GetAttribute("RestCFrame") or primary.CFrame
	local restRot = restCF - restCF.Position
	local counts, reps = {}, {}
	for _, child in raft:GetChildren() do
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

-- Snap the grid origin onto the real tile lattice (mirrors the server). Returns
-- the deck's fractional offset so the preview lines up with the existing tiles
-- and with where the server actually places the build.
-- (getGridPhase определена выше, до getFloorOffsets)

local function isFloorOccupied(offsets, gx, gz)
	for _, o in offsets do
		if o.x == gx and o.z == gz then return true end
	end
	return false
end

local function isFloorAdjacent(offsets, gx, gz)
	for _, o in offsets do
		if (math.abs(o.x - gx) == 1 and o.z == gz) or (math.abs(o.z - gz) == 1 and o.x == gx) then
			return true
		end
	end
	return false
end

-- Диагностика невозможной клетки: печатает целевую клетку, все известные клетки
-- пола и результаты проверок. Нужна, чтобы понять, почему рядом с монолитом
-- пол не ставится: скорее всего клетка ПОД монолитом не попадает в список пола,
-- и тогда у цели просто нет соседа. Выключить, когда разберёмся.
-- ⚠️ ВЫКЛЮЧЕНО: печатало на КАЖДОМ кадре наведения, по сотне строк за секунду.
-- Из-за этого настоящие сообщения (в том числе про засчитанные квесты) тонули в
-- потоке. Включать точечно, когда снова будет вопрос «почему не ставится пол».
local FLOOR_DEBUG = false
local lastFloorDebug = ""
local function floorDebug(gx, gz, offsets, adjacent, canAfford)
	if not FLOOR_DEBUG or adjacent then return end
	local cells = {}
	for _, o in offsets do table.insert(cells, ("(%d,%d)"):format(o.x, o.z)) end
	table.sort(cells)
	local msg = ("[Стройка] клетка (%d,%d): сосед=%s деньги=%s | пол: %s")
		:format(gx, gz, tostring(adjacent), tostring(canAfford), table.concat(cells, " "))
	if msg == lastFloorDebug then return end
	lastFloorDebug = msg
	print(msg)
end

local function cornerHasFloor(offsets, cx, cz)
	return isFloorOccupied(offsets, cx - 0.5, cz - 0.5)
		or isFloorOccupied(offsets, cx + 0.5, cz - 0.5)
		or isFloorOccupied(offsets, cx - 0.5, cz + 0.5)
		or isFloorOccupied(offsets, cx + 0.5, cz + 0.5)
end

local function computeBeamInset(offsets, cx, cz)
	local insetX, insetZ = 0, 0

	local hasPlusX = isFloorOccupied(offsets, cx + 0.5, cz - 0.5) or isFloorOccupied(offsets, cx + 0.5, cz + 0.5)
	local hasMinusX = isFloorOccupied(offsets, cx - 0.5, cz - 0.5) or isFloorOccupied(offsets, cx - 0.5, cz + 0.5)

	if hasMinusX and not hasPlusX then
		insetX = -BEAM_INSET
	elseif hasPlusX and not hasMinusX then
		insetX = BEAM_INSET
	end

	local hasPlusZ = isFloorOccupied(offsets, cx - 0.5, cz + 0.5) or isFloorOccupied(offsets, cx + 0.5, cz + 0.5)
	local hasMinusZ = isFloorOccupied(offsets, cx - 0.5, cz - 0.5) or isFloorOccupied(offsets, cx + 0.5, cz - 0.5)

	if hasMinusZ and not hasPlusZ then
		insetZ = -BEAM_INSET
	elseif hasPlusZ and not hasMinusZ then
		insetZ = BEAM_INSET
	end

	return insetX, insetZ
end

local function makeBeamKey(cx, cz)
	return string.format("%.1f_%.1f", cx, cz)
end

local function makeSpanKey(cx1, cz1, cx2, cz2)
	if cx1 > cx2 or (cx1 == cx2 and cz1 > cz2) then
		cx1, cz1, cx2, cz2 = cx2, cz2, cx1, cz1
	end
	return string.format("%.1f_%.1f_%.1f_%.1f", cx1, cz1, cx2, cz2)
end

local function makeWallPanelKey(cx1, cz1, cx2, cz2)
	return "wp_" .. makeSpanKey(cx1, cz1, cx2, cz2)
end

local function makeWallArchKey(cx1, cz1, cx2, cz2)
	return "wa_" .. makeSpanKey(cx1, cz1, cx2, cz2)
end

local function makeDoorKey(cx1, cz1, cx2, cz2)
	return "dr_" .. makeSpanKey(cx1, cz1, cx2, cz2)
end

local function getBeamKeys()
	local raft = getRaft()
	if not raft then return {} end
	local keys = {}
	for _, child in raft:GetChildren() do
		local bk = child:GetAttribute("BeamKey")
		if bk then keys[bk] = true end
	end
	return keys
end

local function getWallSpanKeys()
	local raft = getRaft()
	if not raft then return {} end
	local keys = {}
	for _, child in raft:GetChildren() do
		local sk = child:GetAttribute("WallSpanKey")
		if sk then keys[sk] = true end
	end
	return keys
end

local function getWallPanelKeys()
	local raft = getRaft()
	if not raft then return {} end
	local keys = {}
	for _, child in raft:GetChildren() do
		local wk = child:GetAttribute("WallPanelKey")
		if wk then keys[wk] = true end
	end
	return keys
end

local function getWallArchKeys()
	local raft = getRaft()
	if not raft then return {} end
	local keys = {}
	for _, child in raft:GetChildren() do
		local wk = child:GetAttribute("WallArchKey")
		if wk then keys[wk] = true end
	end
	return keys
end

local function getDoorKeys()
	local raft = getRaft()
	if not raft then return {} end
	local keys = {}
	for _, child in raft:GetChildren() do
		local dk = child:GetAttribute("DoorKey")
		if dk then keys[dk] = true end
	end
	return keys
end

-- ===================== Coordinate conversion =====================

-- Both raycastToRaftPlane and localToWorld use RestYaw/RestCFrame so the
-- cursor → grid → world round-trip is consistent, giving stable grid coords
-- regardless of current wave-induced pitch/roll. localToWorld returns the
-- restYaw for rotation so beams/walls face the right direction.
--
-- Cursor projection works in two stages:
--   1. Direct workspace raycast against the raft itself. When the cursor
--      is over an existing deck part, this gives us the exact world point
--      under the pointer with zero parallax.
--   2. Plane fallback for when the cursor is over water (extending the
--      raft). The plane is placed at the TOP of the PrimaryPart's world-Y
--      bounding box, not at its centre. The PrimaryPart is a sideways log
--      whose centre Y sits well below the walkable deck surface, so using
--      the raw centre causes an oblique camera to parallax-skew the cursor
--      hit away from the camera — a strip of cells in front of the player
--      would project backward onto the existing raft and hide the preview.
local raftRaycastParams = RaycastParams.new()
raftRaycastParams.FilterType = Enum.RaycastFilterType.Include
raftRaycastParams.IgnoreWater = true

-- Высота последнего попадания луча из камеры в плот — измеренная отметка палубы.
local lastDeckHitY = nil

local function raycastToRaftPlane()
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return nil end

	local cf = raft.PrimaryPart.CFrame
	local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or cf
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0

	-- ⚠️ ЦЕЛИМСЯ ПО ЗАПОМНЕННОМУ ТАПУ, А НЕ ПО «ГДЕ МЫШЬ».
	-- На телефоне «мышь» встаёт в точку последнего касания, а последним касанием
	-- бывает нажатие на кнопку «Построить» — прицел срывался на неё. _G.BuildAim
	-- хранит последний тап ПО МИРУ. Читаем прямо здесь, без функции-обёртки: файл
	-- упёрся в предел Luau на локальные переменные, и даже две коротких `local
	-- function` наверху ломают компиляцию всего меню.
	local ray = camera:ScreenPointToRay(
		(_G.BuildAim and _G.BuildAim.x) or mouse.X,
		(_G.BuildAim and _G.BuildAim.y) or mouse.Y)

	local hitWorld = nil

	-- Stage 1: direct raycast against the raft.
	raftRaycastParams.FilterDescendantsInstances = {raft}
	local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, raftRaycastParams)
	-- ⚠️ ВТОРОЙ ЭТАЖ: луч сверху упёрся в его пол — стены ставим на этот пол.
	-- Через _G, а не local: файл упёрся в предел Luau на локальные переменные.
	_G.BuildHitUpper = (result and result.Normal.Y > 0.5)
		and require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).modelOf(raft, result.Instance) or nil
	if result then
		hitWorld = result.Position
	else
		-- Stage 2: plane fallback at the top of the PrimaryPart. Use the
		-- rest rotation so the plane Y doesn't wobble with waves.
		local size = raft.PrimaryPart.Size
		local restRotCF = restCF - restCF.Position
		local topOffset = -math.huge
		for xi = -1, 1, 2 do
			for yi = -1, 1, 2 do
				for zi = -1, 1, 2 do
					local corner = restRotCF * Vector3.new(xi * size.X / 2, yi * size.Y / 2, zi * size.Z / 2)
					if corner.Y > topOffset then
						topOffset = corner.Y
					end
				end
			end
		end
		local stableY = restCF.Position.Y + topOffset

		local denom = ray.Direction.Y
		if math.abs(denom) < 0.001 then return nil end
		local t = (stableY - ray.Origin.Y) / denom
		if t < 0 then return nil end
		hitWorld = ray.Origin + ray.Direction * t
	end

	-- ⚠️ ЗАПОМИНАЕМ ВЫСОТУ ПОПАДАНИЯ — ЭТО ЕДИНСТВЕННАЯ ИЗМЕРЕННАЯ ОТМЕТКА ПАЛУБЫ.
	-- Луч из камеры упирается ровно в ту поверхность, на которую смотрит игрок и
	-- по которой он ходит. Всё остальное — вычисления по габаритам и смещениям,
	-- и они уже трижды промахнулись. Держим её для сверки в логе.
	lastDeckHitY = hitWorld.Y

	-- Convert the world hit into the raft's yaw-aligned local frame. Only
	-- X and Z matter for grid snapping — the plane frame is rotated around
	-- the world Y axis, so the local XZ is independent of the frame's Y.
	local flatCF = CFrame.new(cf.Position.X, hitWorld.Y, cf.Position.Z) * CFrame.Angles(0, restYaw, 0)
	return flatCF:PointToObjectSpace(hitWorld)
end

-- Returns the world position for a local stud offset on the raft AND the
-- restYaw for rotating beams/walls/doors to face raft-forward.
local function localToWorld(studX, studZ)
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return Vector3.zero, 0 end
	local primaryCF = raft.PrimaryPart.CFrame
	local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or primaryCF
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
	local phaseX, phaseZ = getGridPhase(raft, GRID_SIZE)
	local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(studX + phaseX, 0, studZ + phaseZ))
	local localOffset = restCF:VectorToObjectSpace(worldOffset)
	return (primaryCF * CFrame.new(localOffset)).Position, restYaw
end

-- ===================== Floor grid =====================

local function getFloorGridFromMouse()
	local localHit = raycastToRaftPlane()
	if not localHit then return nil, nil, nil end

	local raft = getRaft()
	local primaryCF = raft.PrimaryPart.CFrame
	local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or primaryCF
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
	local phaseX, phaseZ = getGridPhase(raft, GRID_SIZE)
	local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(
		math.round(localHit.X / GRID_SIZE) * GRID_SIZE + phaseX + FLOOR_FINE_X, 0,
		math.round(localHit.Z / GRID_SIZE) * GRID_SIZE + phaseZ + FLOOR_FINE_Z
		)) + Vector3.new(0, deckCenterRestY(raft), 0) -- на уровень ЦЕНТРОВ геометрии досок
	local localOffset = restCF:VectorToObjectSpace(worldOffset)

	local gx = math.round(localHit.X / GRID_SIZE)
	local gz = math.round(localHit.Z / GRID_SIZE)
	-- клетка = центр геометрии; пивот отводим на его смещение от центра
	local worldCF = primaryCF * CFrame.new(localOffset)
		* getTileRotationCorrection(raft) * CFrame.new(-RAFT_PIVOT_DELTA)

	return gx, gz, worldCF
end

-- ===================== Опора стены =====================
-- РЕБРО КЛЕТКИ вместо пары балок. Пара углов (cx1,cz1)-(cx2,cz2) — это и есть
-- ребро; она одинакова с обеих сторон, поэтому остаётся канонным адресом стены
-- (формат сохранений не меняется). Раньше по этим углам ещё требовались
-- ПОСТАВЛЕННЫЕ БАЛКИ, и без них стену было не построить. Теперь достаточно,
-- чтобы к ребру примыкала хотя бы одна клетка пола.
local function edgeHasFloor(offsets, cx1, cz1, cx2, cz2)
	local midX, midZ = (cx1 + cx2) / 2, (cz1 + cz2) / 2
	local a1x, a1z, a2x, a2z
	if cx1 == cx2 then           -- ребро вдоль Z → соседи слева и справа
		a1x, a1z = midX - 0.5, midZ
		a2x, a2z = midX + 0.5, midZ
	else                          -- ребро вдоль X → соседи спереди и сзади
		a1x, a1z = midX, midZ - 0.5
		a2x, a2z = midX, midZ + 0.5
	end
	return isFloorOccupied(offsets, a1x, a1z) or isFloorOccupied(offsets, a2x, a2z)
end

-- Верх настила относительно пивота PrimaryPart: стена стоит НА полу, а не в
-- его середине. Без этой поправки на новом плоту стены тонули в палубе.
-- ⚠️ ВЫСОТУ НАСТИЛА БЕРЁМ ПРЯМО В МИРОВЫХ КООРДИНАТАХ.
-- Раньше она считалась смещением ОТНОСИТЕЛЬНО пивота плота, и по дороге делала
-- круг: PointToObjectSpace брал вектор в ТЕКУЩИХ осях плота, а
-- VectorToWorldSpace разворачивал его через оси ПОКОЯ. Пока плот стоит ровно,
-- это одно и то же; стоит ему качнуться — и вертикаль набирает вклад от
-- горизонтальных смещений досок, тем больший, чем дальше доска от центра.
-- Верх настила уезжал на метры, а вместе с ним и призрак стены.
-- Для вертикали этот круг не нужен вовсе: мировая Y верхней грани доски — это
-- и есть высота палубы. Оси покоя нужны только горизонтальной сетке.
--
-- Мода (самое частое значение), а не первая попавшаяся доска: доски бывают
-- разной толщины, и «первая» задавала бы высоту лотереей — порядок детей у
-- сервера и у клиента свой. Тем же голосованием и по той же причине считается
-- фаза сетки (getGridPhase).
-- ДЕРЖАТЬ РАВНЫМ серверной копии deckTopWorldY.
-- ⚠️ ВЫСОТУ НАСТИЛА ЛУЧШЕ ВСЕГО ИЗМЕРИТЬ, А НЕ ВЫВЕСТИ.
-- Через габариты досок она вычислялась трижды по-разному и трижды мимо: у
-- Raft_part габаритная коробка выше самого настила (внутри есть и поплавок, и
-- служебные детали), и «верх коробки» оказывался на пять стад выше палубы —
-- ровно на столько призрак и висел. Луч сверху вниз попадает в НАСТОЯЩУЮ
-- поверхность, по которой ходит игрок, и никакой моделью его не обмануть.
-- Светим только по доскам пола: иначе луч поймал бы бочку или станцию ремонта,
-- и стена встала бы им на крышу.
-- ДЕРЖАТЬ РАВНЫМ серверной копии deckTopAt.
local deckRayParams = RaycastParams.new()
deckRayParams.FilterType = Enum.RaycastFilterType.Include

local function deckTopAt(raft, x, z)
	local prim = raft and raft.PrimaryPart
	if not prim then return nil end
	local tiles = {}
	for _, c in ipairs(raft:GetChildren()) do
		if c.Name == "Raft_part" then table.insert(tiles, c) end
	end
	if #tiles == 0 then return nil end
	deckRayParams.FilterDescendantsInstances = tiles
	local from = Vector3.new(x, prim.Position.Y + 60, z)
	local hit = workspace:Raycast(from, Vector3.new(0, -160, 0), deckRayParams)
	return hit and hit.Position.Y or nil
end

-- ⚠️ СВЕТИМ В СЕРЕДИНЫ КЛЕТОК, А НЕ В РЕБРО, И БЕРЁМ САМОЕ НИЗКОЕ ПОПАДАНИЕ.
-- Стена встаёт на ребро клетки — а на рёбрах у доски как раз стоят столбы и
-- перила. Луч в середину ребра попадал в их макушку и объявлял палубу на 3.4
-- стада выше, чем она есть: ровно настолько стена и висела над полом.
-- Настоящий настил находится в СЕРЕДИНЕ клетки, где ничего не торчит. Берём обе
-- клетки, примыкающие к ребру, и из попаданий выбираем НИЖНЕЕ: столб всегда выше
-- пола, значит минимум — это и есть пол.
-- ДЕРЖАТЬ РАВНЫМ серверной копии deckTopForEdge.
-- Точек по клетке несколько: одна могла попасть в тот же столб или в щель между
-- досками, и тогда замер терялся целиком, а с ним и вся правка.
local SAMPLE_SPREAD = 0.28   -- доля клетки, на которую разносим пробы

-- ⚠️ ПОСЛЕДНИЙ УДАЧНЫЙ ЗАМЕР ХРАНИМ.
-- Запасным путём была мода по габаритам досок, а она даёт ровно то самое
-- неверное число (на 3.4 стада выше палубы) — то есть при первом же промахе
-- призрак снова взлетал. Палуба у плота одна на всю площадь, поэтому прошлый
-- удачный замер — куда более честная замена, чем заведомо кривой расчёт.
local lastDeckTop = nil

local function deckTopForEdge(raft, cx1, cz1, cx2, cz2)
	if not raft then return nil end
	local midX, midZ = (cx1 + cx2) / 2, (cz1 + cz2) / 2
	local cells
	if cz1 == cz2 then           -- ребро вдоль X: клетки сверху и снизу по Z
		cells = { { midX, cz1 - 0.5 }, { midX, cz1 + 0.5 } }
	else                          -- ребро вдоль Z: клетки слева и справа по X
		cells = { { cx1 - 0.5, midZ }, { cx1 + 0.5, midZ } }
	end

	local best
	for _, c in ipairs(cells) do
		for _, d in ipairs({ {0, 0}, {SAMPLE_SPREAD, 0}, {-SAMPLE_SPREAD, 0},
			{0, SAMPLE_SPREAD}, {0, -SAMPLE_SPREAD} }) do
			local wp = localToWorld((c[1] + d[1]) * GRID_SIZE, (c[2] + d[2]) * GRID_SIZE)
			local y = deckTopAt(raft, wp.X, wp.Z)
			if y and (not best or y < best) then best = y end
		end
	end
	if best then lastDeckTop = best end
	return best or lastDeckTop
end

-- Запасной путь, когда луч не во что упереться (клетка на самом краю, доски ещё
-- не приехали): мода по верхним граням досок. Хуже луча, но лучше пустоты.
local function deckTopWorldY(raft)
	local counts, reps = {}, {}
	for _, child in ipairs(raft:GetChildren()) do
		if child.Name == "Raft_part" and child ~= raft.PrimaryPart then
			local pos, size
			if child:IsA("Model") then
				local ok, c, s = pcall(function()
					local a, b = child:GetBoundingBox()
					return a, b
				end)
				if ok and c and s then pos, size = c.Position, s end
			elseif child:IsA("BasePart") then
				pos, size = child.Position, child.Size
			end
			if pos and size then
				local top = pos.Y + size.Y * 0.5
				local key = math.round(top * 4)   -- корзина 0.25 стада
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
	-- досок нет вовсе (пустой плот) — падаем на сам пивот
	return raft.PrimaryPart and raft.PrimaryPart.Position.Y or 0
end

-- ===================== Beam corner (не используется: балки убраны) =====================

local function getBeamCornerFromMouse()
	local localHit = raycastToRaftPlane()
	if not localHit then return nil, nil, nil end

	local gridX = localHit.X / GRID_SIZE
	local gridZ = localHit.Z / GRID_SIZE
	local cx = math.floor(gridX) + 0.5
	local cz = math.floor(gridZ) + 0.5

	local offsets = getFloorOffsets()
	local insetX, insetZ = computeBeamInset(offsets, cx, cz)
	local studX = cx * GRID_SIZE + insetX + BEAM_X_OFFSET
	local studZ = cz * GRID_SIZE + insetZ

	local worldPos, restYaw = localToWorld(studX, studZ)
	worldPos = worldPos + Vector3.new(0, BEAM_HEIGHT * BEAM_SCALE / 2, 0)
	local worldCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw, 0)

	return cx, cz, worldCF
end

-- ===================== Wall panel between beams =====================

local function getWallPanelFromMouse()
	local localHit = raycastToRaftPlane()
	if not localHit then return nil end

	local gx = math.round(localHit.X / GRID_SIZE)
	local gz = math.round(localHit.Z / GRID_SIZE)

	local cellCenterX = gx * GRID_SIZE
	local cellCenterZ = gz * GRID_SIZE
	local dx = localHit.X - cellCenterX
	local dz = localHit.Z - cellCenterZ

	local side
	if math.abs(dx) > math.abs(dz) then
		side = (dx > 0) and 3 or 2
	else
		side = (dz > 0) and 0 or 1
	end

	local cx1, cz1, cx2, cz2
	if side == 0 then
		cx1, cz1 = gx - 0.5, gz + 0.5
		cx2, cz2 = gx + 0.5, gz + 0.5
	elseif side == 1 then
		cx1, cz1 = gx - 0.5, gz - 0.5
		cx2, cz2 = gx + 0.5, gz - 0.5
	elseif side == 2 then
		cx1, cz1 = gx - 0.5, gz - 0.5
		cx2, cz2 = gx - 0.5, gz + 0.5
	elseif side == 3 then
		cx1, cz1 = gx + 0.5, gz - 0.5
		cx2, cz2 = gx + 0.5, gz + 0.5
	end

	-- Без балок: середина ребра прямо по сетке, без отступов под столбы.
	local midStudX = (cx1 + cx2) / 2 * GRID_SIZE
	local midStudZ = (cz1 + cz2) / 2 * GRID_SIZE

	local raft = getRaft()
	local worldPos, restYaw = localToWorld(midStudX, midStudZ)
	-- ⚠️ ВЫСОТУ ЗАДАЁМ АБСОЛЮТНО, А НЕ ПРИБАВКОЙ.
	-- localToWorld отвечает только за горизонталь; его Y — это уровень пивота
	-- плота, к делу не относящийся. Ставим центр стены прямо от мировой высоты
	-- настила, тогда её низ ложится ровно на доски.
	-- Прицел на полу второго этажа — стена встаёт на него (level 2).
	local upTop = raft and _G.BuildHitUpper and require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).edgeTop(raft, cx1, cz1, cx2, cz2) or nil
	local deckTop = upTop or (raft and (deckTopForEdge(raft, cx1, cz1, cx2, cz2) or deckTopWorldY(raft))) or worldPos.Y
	worldPos = Vector3.new(worldPos.X,
		deckTop + wallHeight(wallPanelTemplate) / 2 - WallDefs.SINK, worldPos.Z)

	local sideAngle = (side == 2 or side == 3) and math.rad(90) or 0
	local worldCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)

	-- ВРЕМЕННАЯ ДИАГНОСТИКА расхождения превью и постановки: печатаем раз в
	-- секунду, из чего клиент сложил высоту. Сервер печатает то же при
	-- постановке — сравнив две строки, видно, какое именно число врёт.
	if WALL_DEBUG and os.clock() - lastWallDebug > 1 then
		lastWallDebug = os.clock()
		-- ⚠️ ПЕЧАТАЕМ И ТО, ГДЕ ПРИЗРАК РЕАЛЬНО НАРИСОВАЛСЯ.
		-- Расчётное итогY и видимая высота — РАЗНЫЕ вещи: PivotTo ставит ПИВОТ, а
		-- геометрия сидит относительно него так, как её сохранил автор модели.
		-- Расчёт у клиента и сервера тут посчитан одинаковым построчно, значит
		-- врёт либо число, либо отрисовка, и без этой пары их не различить.
		local ghostY = 0
		if previewPart then

			if previewPart:IsA("Model") then
				local ok, bb = pcall(function() return previewPart:GetBoundingBox() end)
				if ok and bb then ghostY = bb.Position.Y end
			elseif previewPart:IsA("BasePart") then
				ghostY = previewPart.Position.Y
			end
		end
		-- ⚠️ ПЕЧАТАЕМ И КЛЕТКУ С МИРОВЫМ X/Z.
		-- По прошлому логу видно, что итогY совпадает с тем, где призрак реально
		-- нарисован, — значит спорить о высоте больше не о чем и остаётся ГДЕ. На
		-- сервер уходит не позиция, а НОМЕР КЛЕТКИ, и он считает координаты сам:
		-- разойтись они могут только здесь. Сервер печатает те же поля.
		-- ⚠️ ГЛАВНАЯ ПАРА ЧИСЕЛ — «лучПоМыши» И «низСтены».
		-- Первое измерено: это поверхность, в которую упёрся луч из камеры, то
		-- есть палуба под курсором. Второе — куда встанет низ стены. Если между
		-- ними зазор, спорить больше не о чем: настолько стена и висит.
		local prim = raft and raft.PrimaryPart
		local hitY = lastDeckHitY or 0
		local bottomY = worldPos.Y - wallHeight(wallPanelTemplate) / 2
		print(("[Стена/клиент] высотаПанели=%.2f верхНастила=%.2f лучПоМыши=%.2f "
			.. "низСтены=%.2f зазор=%.2f | плот=(%.1f, %.1f, %.1f) стена=(%.1f, %.1f) "
			.. "клетка=(%.1f,%.1f)-(%.1f,%.1f) центрПризрака=%.2f")
			:format(wallHeight(wallPanelTemplate), deckTop, hitY,
				bottomY, bottomY - hitY,
				prim and prim.Position.X or 0, prim and prim.Position.Y or 0,
				prim and prim.Position.Z or 0,
				worldPos.X, worldPos.Z, cx1, cz1, cx2, cz2, ghostY))
	end

	return cx1, cz1, cx2, cz2, side, worldCF, upTop and 2 or 1
end

-- ===================== Wall arch / Door (same beam-pair geometry) =====================

-- Shared computation: pick the cell side under the cursor and return both
-- the beam-pair coords AND the world position for an object of `height`
-- centered between those two beams.
local function getBeamPairFromMouse(height)
	local localHit = raycastToRaftPlane()
	if not localHit then return nil end

	local gx = math.round(localHit.X / GRID_SIZE)
	local gz = math.round(localHit.Z / GRID_SIZE)

	local cellCenterX = gx * GRID_SIZE
	local cellCenterZ = gz * GRID_SIZE
	local dx = localHit.X - cellCenterX
	local dz = localHit.Z - cellCenterZ

	local side
	if math.abs(dx) > math.abs(dz) then
		side = (dx > 0) and 3 or 2
	else
		side = (dz > 0) and 0 or 1
	end

	local cx1, cz1, cx2, cz2
	if side == 0 then
		cx1, cz1 = gx - 0.5, gz + 0.5
		cx2, cz2 = gx + 0.5, gz + 0.5
	elseif side == 1 then
		cx1, cz1 = gx - 0.5, gz - 0.5
		cx2, cz2 = gx + 0.5, gz - 0.5
	elseif side == 2 then
		cx1, cz1 = gx - 0.5, gz - 0.5
		cx2, cz2 = gx - 0.5, gz + 0.5
	elseif side == 3 then
		cx1, cz1 = gx + 0.5, gz - 0.5
		cx2, cz2 = gx + 0.5, gz + 0.5
	end

	-- Без балок: середина ребра прямо по сетке, без отступов под столбы.
	local midStudX = (cx1 + cx2) / 2 * GRID_SIZE
	local midStudZ = (cz1 + cz2) / 2 * GRID_SIZE

	local raft = getRaft()
	local worldPos, restYaw = localToWorld(midStudX, midStudZ)
	-- высоту задаём абсолютно, от мировой отметки настила (см. getWallPanelFromMouse)
	local upTop = raft and _G.BuildHitUpper and require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).edgeTop(raft, cx1, cz1, cx2, cz2) or nil
	local deckTop = upTop or (raft and (deckTopForEdge(raft, cx1, cz1, cx2, cz2) or deckTopWorldY(raft))) or worldPos.Y
	worldPos = Vector3.new(worldPos.X, deckTop + height / 2 - WallDefs.SINK, worldPos.Z)

	local sideAngle = (side == 2 or side == 3) and math.rad(90) or 0
	local worldCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)

	return cx1, cz1, cx2, cz2, side, worldCF, upTop and 2 or 1
end

local function getWallArchFromMouse()
	return getBeamPairFromMouse(wallHeight(wallArchTemplate))
end

local function getEdgeWallFromMouse(buildType)
	local edge = EDGE_WALLS[buildType]
	return getBeamPairFromMouse(edge and wallHeight(edge.template) or 0)
end

local function getDoorFromMouse()
	return getBeamPairFromMouse(wallHeight(doorTemplate))
end

-- ===================== Preview helpers =====================

--[[ Клетка воды перед рыбацким местом (FishingSpotGrid): рыбак забрасывает туда
     удочку, пол и сеть там сервер не строит. Призрак над ней сразу красный, а клик
     не уходит — иначе отказ приходил уведомлением, спрятанным за меню молотка.
     Через _G, а не локалью: у файла почти исчерпан лимит в 200 локалей. ]]
do
	local Grid = require(ReplicatedStorage:WaitForChild("FishingSpotGrid"))
	_G.BuildFishFrontBlocked = function()
		local raft = workspace:FindFirstChild("Raft")
		if not (previewPart and previewPart.Parent and raft) then return false end
		local cf = previewPart:IsA("Model") and previewPart:GetBoundingBox() or previewPart.CFrame
		if Grid.frontReserved(raft, cf.Position) then return true end
		-- полоса яхты торговца: стоит у борта / идёт / отходит — там не строим
		-- (та же геометрия, что _G.MerchantYachtBlocks на сервере)
		local y = workspace:FindFirstChild("MerchantYacht")
		local dock, out = y and y:GetAttribute("DockRel"), y and y:GetAttribute("OutRel")
		if typeof(dock) == "CFrame" and typeof(out) == "Vector3" and not y:GetAttribute("Stranded") and raft.PrimaryPart then
			local p = raft.PrimaryPart
			local flat = CFrame.new(p.Position) * CFrame.Angles(0, p:GetAttribute("RestYaw") or 0, 0)
			local rel = flat:PointToObjectSpace(cf.Position) - dock.Position
			local along = rel.X * out.X + rel.Z * out.Z
			local side = math.abs(rel.X * out.Z - rel.Z * out.X)
			if along >= -(14.9 + 4) and along <= (y:GetAttribute("ApproachDist") or 140) and side <= 14 / 2 + 4 then
				return true
			end
		end
		return false
	end
end

local function setPreviewAppearance(color)
	if not previewPart then return end
	local function applyToPart(part)
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 0.5
		part.Color = color
	end
	if previewPart:IsA("Model") then
		for _, desc in previewPart:GetDescendants() do
			if desc:IsA("BasePart") then applyToPart(desc) end
		end
	elseif previewPart:IsA("BasePart") then
		applyToPart(previewPart)
	end
	-- Highlight поверх: у MeshPart с текстурой (сеть — как раз такая) свойство
	-- Color НЕ виден, текстура его перекрывает, и превью оставалось белым. Заливка
	-- Highlight красит любую геометрию, поэтому зелёный/красный виден всегда.
	local hl = previewPart:FindFirstChildOfClass("Highlight")
	if not hl then
		hl = Instance.new("Highlight")
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.FillTransparency = 0.45
		hl.OutlineTransparency = 0
		hl.Parent = previewPart
		hl.Adornee = previewPart
	end
	hl.FillColor = color
	hl.OutlineColor = color
end

local function hidePreview()
	if not previewPart then return end
	if previewPart:IsA("Model") then
		for _, desc in previewPart:GetDescendants() do
			if desc:IsA("BasePart") then desc.Transparency = 1 end
		end
	elseif previewPart:IsA("BasePart") then
		previewPart.Transparency = 1
	end
end

local function movePreview(cf)
	if not previewPart then return end
	if previewPart:IsA("Model") then
		previewPart:PivotTo(cf)
	elseif previewPart:IsA("BasePart") then
		previewPart.CFrame = cf
	end
end

-- Для стен cf задаёт, где должен оказаться ЦЕНТР геометрии, а не пивот — иначе
-- призрак висит там, куда автор модели поставил пивот. Подробности у
-- RaftWallDefs.pivotForCentre. Считаем по самому призраку: это и есть тот
-- экземпляр, который двигаем.
local function movePreviewCentred(cf)
	if not previewPart then return end
	movePreview(WallDefs.pivotForCentre(previewPart, cf))
end

local function getTemplateForItem(item)
	if not item then return raftPartTemplate end
	if item.buildType == "dock3" then
		return AssetFind.find(DOCK_TOOL) or raftPartTemplate
	end
	if item.buildType == "net" then return netTemplate or raftPartTemplate end
	if item.buildType == "floor_upper" then return require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).template() or raftPartTemplate end
	if item.buildType == "stairs" then return AssetFind.find(require(ReplicatedStorage:WaitForChild("RaftStairs")).NAME) or raftPartTemplate end
	if item.buildType == "beam" then return beamTemplate or raftPartTemplate end
	if item.buildType == "wall_panel" then return wallPanelTemplate or raftPartTemplate end
	if item.buildType == "wall_arch" then return wallArchTemplate or raftPartTemplate end
	local edge = EDGE_WALLS[item.buildType]
	if edge then return edge.template or raftPartTemplate end
	if item.buildType == "door" then return doorTemplate or raftPartTemplate end
	return raftPartTemplate
end

-- ⚠️ ДЛЯ ИКОНКИ ЗАПАСНОЙ ШАБЛОН НЕ ГОДИТСЯ.
-- getTemplateForItem подставляет доску пола, когда своей модели нет: призраку
-- это нужно (лучше показать хоть что-то под курсором), а иконке — вредно, там
-- доска пола означала бы «ставится доска пола». Нет модели — пусть заглушкой
-- будет обычная плашка.
local function iconTemplateFor(item)
	if not item then return nil end
	if item.buildType == "raft" then return raftPartTemplate end
	-- укреплённая доска собирается в фоне при старте (см. прогрев иконок в конце файла)
	if item.buildType == "reinforce" then return _G.ReinforceIconTemplate or raftPartTemplate end
	if item.buildType == "dock3" then return AssetFind.find(DOCK_TOOL) end
	if item.buildType == "net" then return netTemplate end
	if item.buildType == "floor_upper" then return require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).template() end
	if item.buildType == "stairs" then return AssetFind.find(require(ReplicatedStorage:WaitForChild("RaftStairs")).NAME) end
	if item.buildType == "beam" then return beamTemplate end
	if item.buildType == "wall_panel" then return wallPanelTemplate end
	if item.buildType == "wall_arch" then return wallArchTemplate end
	if item.buildType == "door" then return doorTemplate end
	-- островные постройки: иконка — сама модель, как у всего остального в меню.
	-- Имена берём из тех же Defs, что читает призрак (OilRigPlace) и сервер;
	-- require по месту, а не в local наверху: файл у предела 200 локалей.
	if item.buildType == "oilrig" then
		return AssetFind.find(require(ReplicatedStorage:WaitForChild("OilRigDefs")).STATION)
	end
	if item.buildType == "house" then
		return AssetFind.find(require(ReplicatedStorage:WaitForChild("HouseDefs")).MODEL)
	end
	if item.buildType == "farm" then
		return AssetFind.find(require(ReplicatedStorage:WaitForChild("FarmDefs")).MODEL,
			require(ReplicatedStorage:WaitForChild("FarmDefs")).MODEL_ALT)
	end
	local edge = EDGE_WALLS[item.buildType]
	return edge and edge.template or nil
end

local function createPreview()
	if previewPart then previewPart:Destroy() end
	local template = getTemplateForItem(selectedItem)
	previewPart = template:Clone()
	previewPart.Name = "BuildPreview"
	-- СНИМАЕМ текстуры с КЛОНА (оригинал в ReplicatedStorage не трогаем): у MeshPart
	-- свойство Color перекрывается TextureID и полностью игнорируется при наличии
	-- SurfaceAppearance — из-за этого превью сети оставалось «деревянным», без
	-- зелёной/красной заливки. Голый меш красится нормально.
	for _, d in previewPart:GetDescendants() do
		if d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") then
			d:Destroy()
		elseif d:IsA("MeshPart") then
			d.TextureID = ""
			d.Material = Enum.Material.SmoothPlastic
		end
	end
	if previewPart:IsA("MeshPart") then
		previewPart.TextureID = ""
		previewPart.Material = Enum.Material.SmoothPlastic
	end
	-- Причал: пивот авторской модели перекошен (крен −21°), и PivotTo таскал бы
	-- призрак вместе с этим перекосом. Тот же приём, что на сервере при установке.
	-- ЛЕСТНИЦА: рампу (невидимый подъём) в призраке не показываем вовсе
	if previewPart:IsA("Model") and selectedItem and selectedItem.buildType == "stairs" then
		for _, d in previewPart:GetDescendants() do
			if d:IsA("BasePart") and d.Name == require(ReplicatedStorage:WaitForChild("RaftStairs")).RAMP then d:Destroy() end
		end
		require(ReplicatedStorage:WaitForChild("RaftStairs")).prepare(previewPart)
	end
	if previewPart:IsA("Model") and selectedItem and selectedItem.buildType == "dock3" then
		local bcf = previewPart:GetBoundingBox()
		previewPart.WorldPivot = CFrame.new(bcf.Position)
	end
	if previewPart:IsA("Model") and selectedItem then
		-- ScaleTo не трогаем при масштабе 1 (см. серверную копию): абсолютный
		-- масштаб раздувал клон до авторского размера шаблона.
		if selectedItem.buildType == "raft" then
			if TILE_SCALE ~= 1 then previewPart:ScaleTo(TILE_SCALE) end
		elseif selectedItem.buildType == "beam" then
			previewPart:ScaleTo(BEAM_SCALE)
		end
	end
	setPreviewAppearance(PREVIEW_COLOR_VALID)
	previewPart.Parent = workspace
end

local function destroyPreview()
	if previewPart then
		previewPart:Destroy()
		previewPart = nil
	end
	-- ⚠️ ПОДСВЕТКА УКРЕПЛЕНИЯ — ТОЖЕ ЧАСТЬ ПРЕВЬЮ.
	-- Гасила её только своя ветка покадрового цикла, а при смене постройки эта
	-- ветка просто переставала выполняться — и зелёная (или красная) заливка
	-- оставалась висеть на доске, пока игрок строил стену или сеть. Снимать её
	-- надо там же, где сносится призрак: это единственное место, через которое
	-- проходит ЛЮБАЯ смена выбора — и предмет, и категория, и выход из режима.
	setReinforceHighlight(nil)
end

-- ⚠️ НА ВРЕМЯ СТРОЙКИ ГАСИМ ВЕСЬ ИНТЕРФЕЙС, А НЕ СПИСОК ИЗБРАННЫХ.
-- Раньше здесь был перечень из двух имён, и каждый новый элемент HUD приходилось
-- в него дописывать — а про это забывали. Режим стройки монопольный: панель
-- занимает место хотбара, и всё остальное на экране только мешает целиться.
-- Поэтому выключаем ВСЕ ScreenGui игрока, кроме своих, и запоминаем ровно те,
-- что были включены — чтобы вернуть в точности прежнее состояние, а не «всё
-- подряд включить».
-- ⚠️ КВЕСТОВЫЕ ПОДСКАЗКИ ГАСИТЬ НЕЛЬЗЯ.
-- Они как раз и говорят «возьми молоток и поставь клетку» — то есть исчезали
-- ровно в тот момент, когда игрок им подчинился. Задание пропадало с экрана
-- посреди выполнения, и новичок оставался без единого указания, что делать
-- дальше. Трекер и баннеры остаются видны наравне с самой панелью стройки.
local OWN_GUIS = {
	BuildingGui = true, DockHint = true,
	QuestTrackerGui = true,          -- карточка активного квеста и «?»
	RaftHintGui = true,              -- пошаговые подсказки квестов
	BedHintGui = true,
	BeetHintGui = true,
	PurifierQuestHint = true,
	-- ⚠️ ЭКРАННОЕ УПРАВЛЕНИЕ ГАСИТЬ НЕЛЬЗЯ.
	-- Джойстик и кнопка прыжка на телефоне живут в PlayerGui обычным ScreenGui, и
	-- «выключаем всё, кроме своего» выключало их тоже: в режиме стройки игрок
	-- переставал ходить и прыгать. Имена разные в разных версиях PlayerModule,
	-- поэтому перечислены оба.
	TouchGui = true,
	ControlGui = true,
}

-- ⚠️ ЭТИ ГАСИМ, НО НЕ ВОЗВРАЩАЕМ.
-- Всплывающие подсказки живут ровно пока курсор над чем-то. Спрячь мы их вместе
-- с остальным HUD и верни на выходе — вернулась бы подсказка от наведения,
-- случившегося минуту назад: она повисала у курсора и ездила за ним. Их дело
-- показать себя заново, когда игрок снова на что-то наведётся.
local TRANSIENT_GUIS = { InventoryTooltip = true, LockedSlotPopup = true }

local hiddenGuis = {}

local function setWorldHudHidden(hidden)
	if hidden then
		table.clear(hiddenGuis)
		for _, gui in ipairs(playerGui:GetChildren()) do
			-- KeepEnabled — полки-кэши иконок (ModelIcon, портреты): выключенный
			-- ViewportFrame остывает и потом рисует модель заново, на глазах
			if gui:IsA("ScreenGui") and gui.Enabled and not OWN_GUIS[gui.Name] and not gui:GetAttribute("KeepEnabled") then
				if not TRANSIENT_GUIS[gui.Name] then hiddenGuis[gui] = true end
				gui.Enabled = false
			end
		end
	else
		for gui in pairs(hiddenGuis) do
			if gui.Parent then gui.Enabled = true end
		end
		table.clear(hiddenGuis)
	end
end

local function closeBuildMode()
	isBuilding = false
	_G.BuildSelectedItem = nil   -- вышка тоже гаснет вместе с режимом стройки
	dockMode = false
	ContextActionService:UnbindAction("DockRotate")
	ContextActionService:UnbindAction("ReinforceSoundCycle")
	-- вернуть цифры хотбару и Q/E остальным: пока меню закрыто, они не наши
	ContextActionService:UnbindAction("BuildPickItem")
	ContextActionService:UnbindAction("BuildPickCategory")
	showDockHint(false)
	setWorldHudHidden(false)
	destroyPreview()   -- он же снимает подсветку укрепления
	if buildingUI then
		ModelIcon.reclaim(buildingUI)   -- готовые иконки-модели — обратно на скрытую полку
		buildingUI:Destroy()
		buildingUI = nil
	end
	_G.BuildingScreenGui = nil
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

-- ===================== UI =====================
-- Меню строительства по хендоффу «Build Menu Roblox.dc.html» (README рядом с
-- ним). Одна полоса по низу экрана НА МЕСТЕ ХОТБАРА — они никогда не видны
-- вместе. Слева рельс категорий, по центру плитки построек, справа выход и
-- запасы, сверху над плитками — название наведённой постройки, снизу хоткеи.
--
-- ⚠️ ПОДПИСЕЙ ПОД ПЛИТКАМИ НЕТ — ЭТО НЕ ЭКОНОМИЯ, А СМЫСЛ ПЕРЕДЕЛКИ.
-- Прежние карточки с именем под каждой занимали 150 пикселей высоты и лезли на
-- пол-экрана. Имя нужно ровно одно — той постройки, на которую сейчас смотрят;
-- оно и выводится строкой над панелью.

-- Токены дизайна: держать равными хендоффу, менять только здесь.
local UI_BLUE       = Color3.fromHex("2f8fd6")   -- панели и таблетки
local UI_BLUE_DARK  = Color3.fromHex("1f6ba8")   -- их жёсткая тень
local UI_TILE       = Color3.fromHex("4aa3e0")   -- плитка
local UI_SLOT       = Color3.fromHex("a9d8f2")   -- окно иконки
local UI_SLOT_ON    = Color3.fromHex("cfe9f8")   -- оно же у выбранной
local UI_GOLD_TOP   = Color3.fromHex("ffd96a")
local UI_GOLD       = Color3.fromHex("f0b41e")
local UI_GOLD_DARK  = Color3.fromHex("b8830b")
local UI_ON_GOLD    = Color3.fromHex("5a3d00")   -- текст по золоту
local UI_WHITE      = Color3.new(1, 1, 1)
local UI_TEXT_SOFT  = Color3.fromHex("dff1fb")
local UI_KEY_TEXT   = Color3.fromHex("eaf7ff")
local UI_RED_TOP    = Color3.fromHex("ff8f74")
local UI_RED        = Color3.fromHex("ef4a3a")
local UI_RED_BOT    = Color3.fromHex("c9291f")
local UI_RED_DARK   = Color3.fromHex("8f1d16")
local UI_TOAST      = Color3.fromHex("ffd23a")

-- ⚠️ ПЛИТКА КРУПНЕЕ ХЕНДОФФА (74 → 92) НАМЕРЕННО.
-- Иконка здесь не эмодзи, а ViewportFrame с настоящей моделью, и он рисуется
-- ровно в свои экранные пиксели, без сглаживания. На 74 пикселях пять стен
-- превращались в мыло, а различаются они как раз мелкой геометрией. 92 держит
-- иконку того же размера, что была в прежних карточках.
local TILE      = 92
local TILE_GAP  = 7
local TILE_PAD  = 8      -- поля синей панели вокруг плиток
local MAX_TILES = 6      -- больше — уезжает в прокрутку
local COST_H    = 20     -- полоса цены по нижней кромке окна иконки

local CAT_W, CAT_H, CAT_GAP = 118, 34, 6
-- ⚠️ ПРАВЫЙ СТОЛБЕЦ РОВНО В ВЫСОТУ ПАНЕЛИ.
-- Выход и три чипа запасов раньше набирали свою высоту сами, столбец выходил
-- выше панели, и кнопка торчала над ней — читалось как случайно приклеенная.
-- Считаем размер строки от панели: четыре строки с тремя зазорами дают ровно её
-- высоту, и столбец встаёт с панелью вровень и сверху, и снизу.
local SIDE_W    = 104
local SIDE_GAP  = 4
local SIDE_ROWS = 4      -- выход + три ресурса

--[[ ⚠️ ПЕРЕКЛЮЧАТЕЛЬ «ОБЫЧНЫЙ / УКРЕПЛЁННЫЙ ПОЛ». Укрепление было отдельной
     плиткой рядом с полом, и их путали. Теперь это режим той же плитки: значок
     ⬆ в её углу включает «укреплять», плитка показывает укреплённую доску и
     подсвечивается. Любой выбор пола (клик, цифра, смена категории) идёт через
     эту функцию — режим не теряется. _G, а не local: файл у предела 200. ]]
_G.BuildFloorPick = function(item)
	if item and item.buildType == "raft" and _G.BuildFloorReinforce and categories[1].reinforce then
		return categories[1].reinforce
	end
	return item
end

-- Короткая подсказка по типу постройки: у предметов своего описания нет, а
-- строка над панелью без него была бы просто дублем названия.
local BUILD_HINTS = {
	raft        = "Клетка пола: с неё растёт плот",
	net         = "Ловит ресурсы, что плывут мимо",
	reinforce   = "Укрепляет уже стоящую доску",
	floor_upper = "Кладётся на 4 большие стены над клеткой пола",
	stairs      = "На любую клетку пола · R — повернуть",
	beam        = "Опора под второй ярус",
	wall_panel  = "Глухая стена по краю клетки",
	wall_window = "Стена с окном: пропускает свет",
	wall_half   = "Низкая стена, не закрывает обзор",
	wall_leaf   = "Листва: маскирует плот",
	wall_leaf_half = "Ограда: не даёт упасть за борт",
	wall_arch   = "Проём под дверь",
	door        = "Дверь в проём",
	dock3       = "Причал с лодкой на три клетки",
}

-- Скругление и жёсткая тень «0 Npx 0» из хендоффа. В Roblox такой тени нет,
-- поэтому кладём под элемент вторую плашку со сдвигом вниз. Именно СЕСТРУ, а не
-- ребёнка: ребёнок в Roblox всегда рисуется поверх родителя, и тень закрыла бы
-- сам элемент.
local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function shadowUnder(inst, depth, color, r)
	local sh = Instance.new("Frame")
	sh.Name = "Shadow"
	sh.AnchorPoint = inst.AnchorPoint
	sh.Position = inst.Position + UDim2.fromOffset(0, depth)
	sh.Size = inst.Size
	sh.BackgroundColor3 = color
	sh.BorderSizePixel = 0
	sh.ZIndex = inst.ZIndex - 1
	sh.Parent = inst.Parent
	corner(sh, r)
	return sh
end

local function goldGradient(inst)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(UI_GOLD_TOP, UI_GOLD)
	g.Parent = inst
	return g
end

local function label(parent, text, font, size, color)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text
	t.Font = font
	t.TextSize = size
	t.TextColor3 = color
	t.Parent = parent
	return t
end

-- ⚠️ ЦЕНА — ТАБЛИЦА, ДАЖЕ КОГДА РЕСУРС ОДИН.
-- У листвы цена из двух ресурсов, у остальных из одного. Разводить два разных
-- способа читать цену — верный путь забыть один из них при следующей правке,
-- поэтому у всех она приводится к одному виду: {Ресурс = сколько}.
local function costsOf(item)
	if item.costs then return item.costs end
	return { [item.costType] = item.cost }
end

-- Хватает ли на постройку ВСЕГО, что она стоит. Проверка одна на весь файл:
-- призрак красится по ней же, что и плитка в меню, — иначе меню говорило бы
-- «можно», а призрак краснел.
local function affordable(item)
	if not item then return false end
	-- админ строит бесплатно (сервер: BuildingSystem.server, флаг DevLogs)
	if player:GetAttribute("DevLogs") == true then return true end
	for res, need in pairs(costsOf(item)) do
		if (inventory[res] or 0) < need then return false end
	end
	return true
end

-- Иконка ресурса берётся из общего реестра инвентаря: там же, откуда её берут
-- слоты рюкзака и крафт, — иначе одно и то же дерево выглядело бы в двух местах
-- по-разному.
local function resourceIcon(res)
	if _G.GetItemIcon then
		local ok, id = pcall(_G.GetItemIcon, res)
		if ok and id and id ~= "" then return id end
	end
	return ""
end

-- ⚠️ ВЫБОР — ОДНА ФУНКЦИЯ НА МЫШЬ И КЛАВИАТУРУ.
-- Клик по плитке и цифра должны делать РОВНО одно и то же: сменить предмет,
-- пересобрать меню и переставить призрак. Две копии этого порядка неизбежно
-- разъедутся — забудут destroyPreview, и старый призрак останется висеть.
local buildUI   -- объявлено заранее: функции ниже зовут его, а тело следом
local function pickItem(item)
	item = _G.BuildFloorPick(item)
	if not item or (selectedItem and selectedItem.id == item.id) then return end
	selectedItem = item
	_G.BuildSelectedItem = item   -- наружу: вышку ведёт свой скрипт (OilRigPlace)
	destroyPreview()
	buildUI()
	createPreview()
end

local function pickCategory(index)
	local n = #categories
	if n == 0 then return end
	index = ((index - 1) % n) + 1      -- по кругу: с последней снова на первую
	if index == selectedCategory then return end
	selectedCategory = index
	selectedItem = _G.BuildFloorPick(categories[index].items[1])
	_G.BuildSelectedItem = selectedItem
	destroyPreview()
	buildUI()
	createPreview()
end

-- Тост наверху экрана: единственное, что не влезло в нижнюю полосу, потому что
-- сообщать он должен и тогда, когда игрок смотрит в мир, а не в меню.
local toastLabel, toastThread
local function flashToast(text, color, seconds)
	if not toastLabel then return end
	toastLabel.Parent.Visible = true
	toastLabel.Parent.BackgroundColor3 = color or UI_BLUE
	toastLabel.Text = text
	if toastThread then task.cancel(toastThread) end
	toastThread = task.delay(seconds or 1.8, function()
		if toastLabel and toastLabel.Parent then toastLabel.Parent.Visible = false end
		toastThread = nil
	end)
end

-- наружу: отказы постановки дома и вышки (OilRigPlace) пишутся этим же тостом
-- прямо в меню молотка, а не стопкой уведомлений сбоку
_G.BuildToast = flashToast

function buildUI()
	-- меню уже было на экране — это пересборка (клик по плитке, категории), а не
	-- открытие: анимацию появления тогда не играем (см. конец функции)
	local reopening = buildingUI ~= nil
	if buildingUI then ModelIcon.reclaim(buildingUI) buildingUI:Destroy() end   -- иконки — на полку (ModelIcon)

	-- Телефон определяем один раз на всю сборку меню: от этого зависят и метки
	-- клавиш у рельса, и строка хоткеев, и кнопка постановки.
	local onTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

	buildingUI = Instance.new("ScreenGui")
	buildingUI.Name = "BuildingGui"
	buildingUI.ResetOnSpawn = false
	buildingUI.DisplayOrder = 20
	-- ⚠️ IgnoreGuiInset: полоса прижата к самому низу экрана, к месту хотбара.
	-- Без него Roblox отсчитывал бы низ от нижней границы своей рамки.
	buildingUI.IgnoreGuiInset = true
	buildingUI.Parent = playerGui

	-- ⚠️ РАЗМЕР — РОВНО КАК У ХОТБАРА, НО ТОЛЬКО НА ТЕЛЕФОНЕ.
	-- Полоса стройки встаёт на место хотбара, значит и мельчать на узком экране
	-- должна с ним заодно. Свой коэффициент здесь завёл бы третью систему масштаба
	-- (после HudScale и инвентарного) — и они бы разошлись на первом же экране
	-- нестандартной ширины. Инвентарь отдаёт свою наружу (_G.AttachInventoryUIScale)
	-- и сам же пересчитывает её при смене размера окна, так что подписываемся.
	--
	-- ⚠️ НО НЕ НА КОМПЬЮТЕРЕ. Инвентарный масштаб считается от РАЗМЕРА ОКНА
	-- (эталон 1280x720) и в окне пониже жмёт всё подряд. Меню стройки до этого
	-- жило в честных пикселях и не сжималось никогда — подписав его на общий
	-- масштаб, я уменьшил его и на компьютере, хотя просили уменьшить на телефоне.
	if onTouch and _G.AttachInventoryUIScale then _G.AttachInventoryUIScale(buildingUI) end

	-- Наружу: иконка квестов и прочие, у кого есть свой слушатель, прячутся сами.
	_G.BuildingScreenGui = buildingUI

	local cat = categories[selectedCategory]
	local items = cat.items
	-- ⚠️ НА ТЕЛЕФОНЕ В РЯД ВЛЕЗАЕТ ТРИ, А НЕ ШЕСТЬ.
	-- Шесть плиток плюс рельс категорий плюс столбец запасов — полоса вылезала за
	-- края экрана: слева срезало категории, справа кнопку. И даже когда влезало,
	-- под джойстик места не оставалось. Остальные постройки уезжают в прокрутку,
	-- она тут и так есть.
	local maxTiles = onTouch and 3 or MAX_TILES
	local shownTiles = math.min(#items, maxTiles)
	local tilesW = shownTiles * TILE + (shownTiles - 1) * TILE_GAP
	local panelW, panelH = tilesW + TILE_PAD * 2, TILE + TILE_PAD * 2

	-- ── корневая полоса: всё по низу, по центру ──
	local root = Instance.new("Frame")
	root.Name = "BuildBar"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -18)
	root.Size = UDim2.fromOffset(0, 0)
	root.AutomaticSize = Enum.AutomaticSize.XY
	root.BackgroundTransparency = 1
	root.Parent = buildingUI

	local rootCol = Instance.new("UIListLayout")
	rootCol.FillDirection = Enum.FillDirection.Vertical
	rootCol.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rootCol.Padding = UDim.new(0, 10)
	rootCol.SortOrder = Enum.SortOrder.LayoutOrder
	rootCol.Parent = root

	-- ⚠️ НА ТЕЛЕФОНЕ ПОЛОСА ЧУТЬ КРУПНЕЕ ХОТБАРА.
	-- Общий масштаб она берёт от инвентаря (см. AttachInventoryUIScale выше) — так
	-- обе живут одной системой и не расходятся. Но в стройке плитки — цель для
	-- пальца, а не просто картинки, поэтому сверху ещё небольшой множитель. Он
	-- ИМЕННО ЗДЕСЬ, на содержимом, а не в общей системе: трогать общий коэффициент
	-- значило бы раздуть заодно и хотбар, и рюкзак.
	if onTouch then
		local bigger = Instance.new("UIScale")
		bigger.Scale = 1.18
		bigger.Parent = root
	end

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.LayoutOrder = 1
	row.Size = UDim2.fromOffset(0, 0)
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.BackgroundTransparency = 1
	row.Parent = root

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row

	-- ── 1. рельс категорий ──
	local rail = Instance.new("Frame")
	rail.Name = "Categories"
	rail.LayoutOrder = 1
	rail.Size = UDim2.fromOffset(CAT_W, #categories * (CAT_H + CAT_GAP) - CAT_GAP + 4)
	rail.BackgroundTransparency = 1
	rail.Parent = row

	for i, catData in categories do
		local isActive = (i == selectedCategory)
		local btn = Instance.new("TextButton")
		btn.Name = "Cat_" .. catData.name
		btn.Size = UDim2.fromOffset(CAT_W, CAT_H)
		btn.Position = UDim2.fromOffset(0, (i - 1) * (CAT_H + CAT_GAP))
		btn.BackgroundColor3 = isActive and UI_WHITE or UI_BLUE
		btn.BorderSizePixel = 0
		btn.Text = catData.name
		btn.Font = Enum.Font.GothamBlack
		btn.TextSize = 14
		btn.TextColor3 = isActive and UI_ON_GOLD or UI_WHITE
		btn.AutoButtonColor = false
		btn.ZIndex = 2
		btn.Parent = rail
		corner(btn, 10)
		if isActive then goldGradient(btn) end
		shadowUnder(btn, 3, isActive and UI_GOLD_DARK or UI_BLUE_DARK, 10)

		btn.MouseButton1Click:Connect(function() pickCategory(i) end)
	end

	-- ⚠️ Q И E ПОДПИСАНЫ У САМОГО РЕЛЬСА.
	-- У плиток номер клавиши стоит прямо на плитке, а категории листаются Q и E —
	-- и об этом нельзя было догадаться ниоткуда, кроме строки хоткеев внизу. Метки
	-- ставим над рельсом и под ним: сверху Q (вверх по списку), снизу E (вниз).
	-- ⚠️ НА ТЕЛЕФОНЕ ЭТИХ МЕТОК НЕТ: клавиш там нет, а буквы над таблетками только
	-- сбивали с толку — их негде нажать. Категории переключаются тапом по самим
	-- таблеткам (см. привязку Q/E в startBuildMode, она там тоже отключена).
	for _, meta in ipairs(onTouch and {} or { { key = "Q", y = -18 }, { key = "E", y = rail.Size.Y.Offset - 4 } }) do
		local pill = Instance.new("Frame")
		pill.Name = "Key" .. meta.key
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.new(0.5, 0, 0, meta.y)
		pill.Size = UDim2.fromOffset(22, 16)
		pill.BackgroundColor3 = UI_BLUE_DARK
		pill.BackgroundTransparency = 0.15
		pill.BorderSizePixel = 0
		pill.ZIndex = 3
		pill.Parent = rail
		corner(pill, 5)

		local t = label(pill, meta.key, Enum.Font.GothamBlack, 11, UI_WHITE)
		t.Size = UDim2.fromScale(1, 1)
		t.ZIndex = 4
	end

	-- ── 2. центр: подсказка над панелью и сама панель с плитками ──
	local centre = Instance.new("Frame")
	centre.Name = "Centre"
	centre.LayoutOrder = 2
	centre.Size = UDim2.fromOffset(panelW, panelH)
	centre.BackgroundTransparency = 1
	centre.Parent = row

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromOffset(panelW, panelH)
	panel.BackgroundColor3 = UI_BLUE
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Parent = centre
	corner(panel, 14)
	shadowUnder(panel, 4, UI_BLUE_DARK, 14)

	-- ⚠️ ПЛИТКИ В ПРОКРУТКЕ, А НЕ В РЯДУ.
	-- Панель держит ровно шесть плиток шириной; всё, что не влезло, уезжает вбок.
	-- Иначе панель на десяти постройках растянулась бы во весь экран и накрыла
	-- прицел — а нам её ширину ещё делить с рельсом категорий и запасами.
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "Tiles"
	strip.Position = UDim2.fromOffset(TILE_PAD, TILE_PAD)
	strip.Size = UDim2.fromOffset(tilesW, TILE)
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.CanvasSize = UDim2.fromOffset(#items * TILE + (#items - 1) * TILE_GAP, 0)
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	-- ⚠️ ПОЛОСКА ПРОКРУТКИ ВИДНА ВСЕГДА, А НЕ ТОЛЬКО КОГДА ЕСТЬ ЧТО ЛИСТАТЬ.
	-- Раньше она появлялась лишь при переполнении, и о самой возможности листать
	-- узнать было неоткуда: плитки просто обрывались краем панели, будто их столько
	-- и есть. Постоянная полоска — единственный намёк, что список длиннее.
	strip.ScrollBarThickness = 6
	strip.ScrollBarImageColor3 = UI_SLOT
	strip.ScrollBarImageTransparency = 0.15
	strip.ZIndex = 3
	strip.Parent = panel
	--[[ ⚠️ КОЛЕСО МЫШИ ЛИСТАЕТ ПОЛОСУ ВБОК.
	     ScrollingFrame по оси X колесом Roblox не крутит вовсе — колесо у него
	     только вертикальное. Стены не влезали в шесть плиток, а долистать было
	     нечем, кроме тонкой полоски («не могу листать роликом»). Один шаг
	     колеса — одна плитка. Через _G, а не local: файл у предела Luau на
	     локальные переменные (см. предупреждение у netTemplate). ]]
	_G.BuildStripWheel = function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
		if not strip.Parent then return end
		local maxX = math.max(0, strip.AbsoluteCanvasSize.X - strip.AbsoluteSize.X)
		local x = strip.CanvasPosition.X - input.Position.Z * (TILE + TILE_GAP)
		strip.CanvasPosition = Vector2.new(math.clamp(x, 0, maxX), 0)
	end
	strip.InputChanged:Connect(_G.BuildStripWheel)

	local hoverName, hoverHint   -- заполняются ниже, но нужны обработчикам плиток

	for i, rawItem in items do
		-- плитка пола в режиме «укреплять» показывает укреплённую доску
		local item = _G.BuildFloorPick(rawItem)
		local isActive = (selectedItem and selectedItem.id == item.id)
		local price = costsOf(item)
		local enough, lacking = true, nil
		for res, need in pairs(price) do
			if (inventory[res] or 0) < need and player:GetAttribute("DevLogs") ~= true then
				enough = false
				lacking = lacking or res
			end
		end

		local tile = Instance.new("TextButton")
		tile.Name = "Item_" .. item.id
		tile.Size = UDim2.fromOffset(TILE, TILE)
		tile.Position = UDim2.fromOffset((i - 1) * (TILE + TILE_GAP), 0)
		tile.BackgroundColor3 = isActive and UI_WHITE or UI_TILE
		tile.BorderSizePixel = 0
		tile.Text = ""
		tile.AutoButtonColor = false
		tile.ZIndex = 4
		tile.Parent = strip
		tile.InputChanged:Connect(_G.BuildStripWheel)   -- колесо над плиткой тоже листает
		corner(tile, 10)
		if isActive then goldGradient(tile) end
		shadowUnder(tile, 3, isActive and UI_GOLD_DARK or UI_BLUE_DARK, 10)

		-- окно иконки
		local slot = Instance.new("Frame")
		slot.Name = "Slot"
		slot.Position = UDim2.fromOffset(5, 5)
		slot.Size = UDim2.fromOffset(TILE - 10, TILE - 10)
		slot.BackgroundColor3 = isActive and UI_SLOT_ON or UI_SLOT
		slot.BorderSizePixel = 0
		slot.ClipsDescendants = true
		slot.ZIndex = 5
		slot.Parent = tile
		corner(slot, 8)

		-- ⚠️ ИКОНКА — САМА МОДЕЛЬ.
		-- Пять стен различаются ровно геометрией; рисованная иконка у всех одна, и
		-- выбрать по ней нельзя. Шаблон берём отдельной функцией: запасной из
		-- getTemplateForItem (доска пола, когда своей модели нет) означал бы
		-- «ставится доска пола».
		-- готовая рамка со скрытой полки (ModelIcon.take): нарисована заранее, не грузится на глазах
		local drawn = ModelIcon.take(slot, iconTemplateFor(item))
		if drawn then
			drawn.ZIndex = 6
			-- полоса цены закрывает низ окна: приподнимаем модель над ней
			drawn.Size = UDim2.new(1, 0, 1, -COST_H)
			drawn.Position = UDim2.fromScale(0.5, 0)
			drawn.AnchorPoint = Vector2.new(0.5, 0)
		else
			local img = Instance.new("ImageLabel")
			img.AnchorPoint = Vector2.new(0.5, 0)
			img.Position = UDim2.fromScale(0.5, 0.04)
			img.Size = UDim2.new(0.86, 0, 1, -COST_H - 6)
			img.BackgroundTransparency = 1
			img.ScaleType = Enum.ScaleType.Fit
			img.Image = item.icon
			img.ZIndex = 6
			img.Parent = slot
		end

		-- цена оверлеем по нижней кромке окна
		local costBar = Instance.new("Frame")
		costBar.Name = "Cost"
		costBar.AnchorPoint = Vector2.new(0, 1)
		costBar.Position = UDim2.fromScale(0, 1)
		costBar.Size = UDim2.new(1, 0, 0, COST_H)
		costBar.BackgroundColor3 = isActive and UI_GOLD_TOP or UI_BLUE_DARK
		costBar.BackgroundTransparency = isActive and 0.1 or 0.15
		costBar.BorderSizePixel = 0
		costBar.ZIndex = 7
		costBar.Parent = slot

		-- ⚠️ НОМЕР КЛАВИШИ ПРЯМО НА ПЛИТКЕ.
		-- Без него о цифрах не догадаться: строка хоткеев внизу говорит «1–6», но
		-- какая цифра к какой постройке — видно только здесь. Ставим в угол, где
		-- он не спорит ни с моделью, ни с ценой.
		if i <= 9 then
			local keyBadge = Instance.new("Frame")
			keyBadge.Name = "Key"
			keyBadge.Position = UDim2.fromOffset(2, 2)
			keyBadge.Size = UDim2.fromOffset(18, 18)
			keyBadge.BackgroundColor3 = isActive and UI_GOLD_DARK or UI_BLUE_DARK
			keyBadge.BackgroundTransparency = 0.15
			keyBadge.BorderSizePixel = 0
			keyBadge.ZIndex = 9
			keyBadge.Parent = tile
			corner(keyBadge, 6)

			local keyNum = label(keyBadge, tostring(i), Enum.Font.GothamBlack, 11, UI_WHITE)
			keyNum.Size = UDim2.fromScale(1, 1)
			keyNum.ZIndex = 10
		end

		-- ⚠️ ЦЕНА ИКОНКАМИ, А НЕ СЛОВАМИ: СНАЧАЛА РЕСУРС, ПОТОМ ЧИСЛО.
		-- «2 Дерево» занимало всю ширину плитки, а на двух ресурсах не влезло бы
		-- вовсе. Иконка узнаётся быстрее слова и не зависит от длины названия:
		-- «Верёвка» и «Листва» рядом уже не помещались.
		local costRow = Instance.new("UIListLayout")
		costRow.FillDirection = Enum.FillDirection.Horizontal
		costRow.HorizontalAlignment = Enum.HorizontalAlignment.Center
		costRow.VerticalAlignment = Enum.VerticalAlignment.Center
		costRow.Padding = UDim.new(0, 3)
		costRow.SortOrder = Enum.SortOrder.LayoutOrder
		costRow.Parent = costBar

		-- порядок фиксируем: pairs по таблице выдаёт ресурсы как придётся, и
		-- цена прыгала бы местами при каждой пересборке меню
		local order = { "Log", "Rope", "Leaves", "Stone", "Iron_Ore" }
		local seq, seen = {}, {}
		for _, res in ipairs(order) do
			if price[res] then table.insert(seq, res); seen[res] = true end
		end
		for res in pairs(price) do
			if not seen[res] then table.insert(seq, res) end
		end

		for n, res in ipairs(seq) do
			local need = price[res]
			local have = (inventory[res] or 0) >= need

			local pic = Instance.new("ImageLabel")
			pic.Name = "Res_" .. res
			pic.LayoutOrder = n * 2 - 1
			pic.Size = UDim2.fromOffset(COST_H - 6, COST_H - 6)
			pic.BackgroundTransparency = 1
			pic.ScaleType = Enum.ScaleType.Fit
			pic.Image = resourceIcon(res)
			pic.ZIndex = 8
			pic.Parent = costBar

			local num = label(costBar, tostring(need), Enum.Font.GothamBlack, 12,
				isActive and UI_ON_GOLD or (have and UI_WHITE or UI_RED_TOP))
			num.LayoutOrder = n * 2
			num.AutomaticSize = Enum.AutomaticSize.X
			num.Size = UDim2.fromOffset(0, COST_H)
			num.ZIndex = 8
		end

		tile.MouseEnter:Connect(function()
			if hoverName then
				hoverName.Text = item.name
				hoverHint.Text = BUILD_HINTS[item.buildType] or ""
			end
		end)
		tile.MouseLeave:Connect(function()
			if hoverName and selectedItem then
				hoverName.Text = selectedItem.name
				hoverHint.Text = BUILD_HINTS[selectedItem.buildType] or ""
			end
		end)
		--[[ ── ПЕРЕКЛЮЧАТЕЛЬ «УКРЕПИТЬ» — ЧАСТЬ ПЛИТКИ ПОЛА ──
		     Полоска во всю ширину сверху внутри самой плитки, окно иконки под ней:
		     одна кнопка, а не две. Без текста — режим видно по цвету: выключено —
		     тёмная полоска с белой стрелкой, включено — оранжевая, и плитка
		     обведена оранжевым (иконка при этом — укреплённая доска). ]]
		if rawItem.buildType == "raft" and cat.reinforce then
			local on = item ~= rawItem
			local ORANGE = Color3.fromRGB(255, 150, 40)
			local BAND_H = 18
			-- окно иконки уступает место полоске
			slot.Position = UDim2.fromOffset(5, 5 + BAND_H + 3)
			slot.Size = UDim2.fromOffset(TILE - 10, TILE - 10 - BAND_H - 3)
			if on then
				local glow = Instance.new("UIStroke")
				glow.Color = ORANGE
				glow.Thickness = 3
				glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				glow.Parent = tile
			end
			local band = Instance.new("TextButton")
			band.Name = "ReinforceToggle"
			band.Position = UDim2.fromOffset(5, 5)
			band.Size = UDim2.fromOffset(TILE - 10, BAND_H)
			band.BackgroundColor3 = on and ORANGE or (isActive and UI_SLOT_ON or UI_SLOT)
			band.BorderSizePixel = 0
			band.AutoButtonColor = true
			band.Font = Enum.Font.GothamBlack
			band.Text = "⬆"
			band.TextSize = 14
			band.TextColor3 = on and UI_WHITE or UI_BLUE_DARK
			band.ZIndex = 8
			band.Parent = tile
			corner(band, 6)
			band.MouseEnter:Connect(function()
				if hoverName then
					hoverName.Text = on and "Обычный пол" or "Укрепить пол"
					hoverHint.Text = on and "Вернуть постройку новых клеток" or "Укрепляет уже стоящую доску"
				end
			end)
			band.MouseButton1Click:Connect(function()
				_G.BuildFloorReinforce = not _G.BuildFloorReinforce
				-- переключили — сразу выбираем пол в новом режиме
				selectedItem = nil
				pickItem(rawItem)
			end)
		end

		tile.MouseButton1Click:Connect(function()
			pickItem(item)
			-- ⚠️ ТОСТ ПОСЛЕ ПЕРЕСБОРКИ, А НЕ ДО НЕЁ.
			-- buildUI сносит меню целиком и создаёт заново, вместе с самим тостом:
			-- сказанное раньше исчезло бы в тот же кадр.
			if not enough then
				flashToast("Не хватает: " .. ResourceNamesRu(lacking or item.costType))
			end
		end)
	end

	-- подсказка над панелью: имя наведённой постройки и строка про неё
	local tip = Instance.new("Frame")
	tip.Name = "Tooltip"
	tip.AnchorPoint = Vector2.new(0.5, 1)
	tip.Position = UDim2.new(0.5, 0, 0, -8)
	tip.Size = UDim2.fromOffset(0, 0)
	tip.AutomaticSize = Enum.AutomaticSize.XY
	tip.BackgroundTransparency = 1
	tip.ZIndex = 4
	tip.Parent = centre

	local tipCol = Instance.new("UIListLayout")
	tipCol.FillDirection = Enum.FillDirection.Vertical
	tipCol.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tipCol.Padding = UDim.new(0, 3)
	tipCol.SortOrder = Enum.SortOrder.LayoutOrder
	tipCol.Parent = tip

	local namePill = Instance.new("Frame")
	namePill.LayoutOrder = 1
	namePill.Size = UDim2.fromOffset(0, 26)
	namePill.AutomaticSize = Enum.AutomaticSize.X
	namePill.BackgroundColor3 = UI_BLUE
	namePill.BorderSizePixel = 0
	namePill.ZIndex = 5
	namePill.Parent = tip
	corner(namePill, 8)

	local namePad = Instance.new("UIPadding")
	namePad.PaddingLeft = UDim.new(0, 14)
	namePad.PaddingRight = UDim.new(0, 14)
	namePad.Parent = namePill

	hoverName = label(namePill, selectedItem and selectedItem.name or "",
		Enum.Font.GothamBlack, 15, UI_WHITE)
	hoverName.AutomaticSize = Enum.AutomaticSize.X
	hoverName.Size = UDim2.fromScale(0, 1)
	hoverName.ZIndex = 6

	hoverHint = label(tip,
		selectedItem and (BUILD_HINTS[selectedItem.buildType] or "") or "",
		Enum.Font.Gotham, 13, UI_TEXT_SOFT)
	hoverHint.LayoutOrder = 2
	hoverHint.AutomaticSize = Enum.AutomaticSize.XY
	hoverHint.Size = UDim2.fromOffset(0, 0)
	hoverHint.TextStrokeColor3 = Color3.new(0, 0, 0)
	hoverHint.TextStrokeTransparency = 0.55
	hoverHint.ZIndex = 5

	-- ── 3. правый столбец: выход и запасы ──
	local right = Instance.new("Frame")
	right.Name = "Side"
	right.LayoutOrder = 3
	right.Size = UDim2.fromOffset(SIDE_W, panelH)
	right.BackgroundTransparency = 1
	right.Parent = row

	-- строка столбца = высота панели, поделённая на четыре с зазорами
	local sideRowH = (panelH - (SIDE_ROWS - 1) * SIDE_GAP) / SIDE_ROWS

	local exitBtn = Instance.new("TextButton")
	exitBtn.Name = "Exit"
	exitBtn.Size = UDim2.fromOffset(SIDE_W, sideRowH)
	exitBtn.BackgroundColor3 = UI_WHITE
	exitBtn.BorderSizePixel = 0
	-- ⚠️ ПОДПИСЬ — ОТДЕЛЬНЫМ ЛЕЙБЛОМ, А НЕ ТЕКСТОМ КНОПКИ.
	-- UIGradient красит не только фон, но и ТЕКСТ своего объекта: белые буквы
	-- умножались на красный градиент и сливались с кнопкой. Дочерний лейбл
	-- градиенту не подчиняется — буквы остаются белыми.
	-- Знака-крестика нет намеренно: U+2715 из набора дингбатов, в шрифтах Roblox
	-- его нет, на экране был пустой прямоугольник.
	exitBtn.Text = ""
	exitBtn.AutoButtonColor = false
	exitBtn.ZIndex = 2
	exitBtn.Parent = right
	corner(exitBtn, 10)
	shadowUnder(exitBtn, 3, UI_RED_DARK, 10)

	local exitGrad = Instance.new("UIGradient")
	exitGrad.Rotation = 90
	exitGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UI_RED_TOP),
		ColorSequenceKeypoint.new(0.52, UI_RED),
		ColorSequenceKeypoint.new(1, UI_RED_BOT),
	})
	exitGrad.Parent = exitBtn

	-- ⚠️ БЕЛОЙ ОБВОДКИ ИЗ ХЕНДОФФА ЗДЕСЬ НЕТ.
	-- Три пикселя рамки прибавляются СНАРУЖИ и делают кнопку заметно крупнее
	-- чипов запасов под ней — столбик перестаёт читаться одной колонкой. Красный
	-- градиент и без обводки выделяет её среди синего.
	local exitText = label(exitBtn, "Выйти", Enum.Font.GothamBlack, 13, UI_WHITE)
	exitText.Size = UDim2.fromScale(1, 1)
	exitText.TextStrokeColor3 = Color3.new(0, 0, 0)
	exitText.TextStrokeTransparency = 0.55
	exitText.ZIndex = 3

	exitBtn.MouseButton1Click:Connect(function()
		-- ⚠️ УБИРАЕМ МОЛОТОК, А НЕ ПРЯЧЕМ МЕНЮ.
		-- Режим стройки держится тем, что тул в руках: спрячь мы только панель,
		-- игрок остался бы в режиме с призраком под курсором и без выхода.
		local char = player.Character
		local tool = char and char:FindFirstChildWhichIsA("Tool")
		if tool then tool.Parent = player:FindFirstChildOfClass("Backpack") end
	end)

	local RES_ORDER = { "Log", "Rope", "Leaves" }
	for i, resName in ipairs(RES_ORDER) do
		local chip = Instance.new("Frame")
		chip.Name = "Stock_" .. resName
		chip.Size = UDim2.fromOffset(SIDE_W, sideRowH)
		chip.Position = UDim2.fromOffset(0, i * (sideRowH + SIDE_GAP))
		chip.BackgroundColor3 = UI_BLUE
		chip.BorderSizePixel = 0
		chip.ZIndex = 2
		chip.Parent = right
		corner(chip, 10)
		shadowUnder(chip, 3, UI_BLUE_DARK, 10)

		local txt = label(chip,
			("%s  %d"):format(ResourceNamesRu(resName), inventory[resName] or 0),
			Enum.Font.GothamBlack, 12, UI_WHITE)
		txt.Size = UDim2.fromScale(1, 1)
		txt.ZIndex = 3
	end

	-- ── 4. под полосой: на компьютере строка хоткеев, на телефоне кнопка «Построить» ──
	--
	-- ⚠️ ЭТО ОДНО И ТО ЖЕ МЕСТО, А НЕ ДВА РАЗНЫХ ЭЛЕМЕНТА.
	-- Строка «1–9 — выбрать · Q/E — категория · ЛКМ — построить» на телефоне
	-- бесполезна целиком: там нет ни цифр, ни Q/E, ни ЛКМ. Значит её место свободно —
	-- туда и встаёт кнопка постановки, крупная и под большой палец. Городить ей
	-- отдельный угол не нужно, а панель не растёт в высоту.
	-- ⚠️ КНОПКА ПОСТАНОВКИ — СПРАВА ОТ ПОЛОСЫ, А НЕ ПОД НЕЙ.
	-- Под полосой она попадала под большой палец только в самом низу экрана, и там
	-- же её задевали случайно. Справа, вровень с панелью, — там палец и так лежит
	-- в ландшафте, а до полосы с постройками он не дотягивается.
	-- ⚠️ КНОПКА ЛЕЖИТ В СВОЁМ ДЕРЖАТЕЛЕ, А НЕ ПРЯМО В СПИСКЕ.
	-- shadowUnder кладёт тень СОСЕДОМ (у Sibling-ZIndex дочерняя рисовалась бы
	-- поверх). Внутри контейнера с UIListLayout этот сосед становится ОТДЕЛЬНОЙ
	-- строкой списка — именно так панель и «разлетелась на две части»: сверху висела
	-- голая золотая тень. Держатель делает тень внутренним делом кнопки.
	if onTouch then
		-- ⚠️ КНОПКА ВНЕ ПОЛОСЫ. Она стояла в общем ряду и растягивала его ещё на свою
		-- ширину — полоса переставала влезать в экран. Здесь она сама по себе: прижата
		-- к правому краю экрана и поднята над полосой, поэтому ширина ряда от неё
		-- больше не зависит вовсе. Место выбрано подальше от джойстика (он внизу) и
		-- от кнопки прыжка (правый нижний угол).
		local buildSlot = Instance.new("Frame")
		buildSlot.Name = "BuildSlot"
		-- Выше кнопки прыжка и правее полосы: обе штатные кнопки внизу справа, эта —
		-- над ними, чтобы большой палец доставал, но не путал их между собой.
		buildSlot.AnchorPoint = Vector2.new(1, 1)
		--[[ ⚠️ ПОДНЯТА НАД ПРЕЖНИМ МЕСТОМ (было -232).
		     Кнопка стояла впритык над штатной «прыжок», и большой палец задевал
		     то одну, то другую: они одного размера, круглые и в одном углу.
		     Полста пикселей воздуха разводят их настолько, чтобы промах перестал
		     быть обычным делом, и при этом кнопка остаётся в зоне большого
		     пальца — выше неё уже неудобно тянуться. ]]
		-- ⚠️ Место отмечено владельцем на скриншоте телефона: не в самом углу, а
		-- левее и ниже, над «прыжком» и с воздухом от правого края.
		buildSlot.Position = UDim2.new(1, -184, 1, -190)
		buildSlot.Size = UDim2.fromOffset(132, 132)
		buildSlot.BackgroundTransparency = 1
		buildSlot.Parent = buildingUI

		-- ⚠️ КРУГЛАЯ, В СТИЛЕ ШТАТНОЙ КНОПКИ ПРЫЖКА.
		-- Она стоит рядом с ней и в той же роли — «действие большим пальцем», —
		-- поэтому и форма та же: круг, полупрозрачная заливка, светлая обводка.
		-- Своя картинка есть, поэтому фон и обводка-заглушка не рисуются: остаётся
		-- только она. Меняешь картинку — меняй здесь, остальное подстроится само.
		local BUILD_ICON = "rbxassetid://116668456372183"
		-- непрозрачность 75%: ImageTransparency — это ПРОЗРАЧНОСТЬ, поэтому 1 - 0.75
		local BUILD_ALPHA = 0.25

		local build = Instance.new("ImageButton")
		build.Name = "BuildNow"
		build.Size = UDim2.fromScale(1, 1)
		build.BackgroundColor3 = Color3.new(0, 0, 0)
		build.BackgroundTransparency = (BUILD_ICON ~= "") and 1 or 0.35
		build.BorderSizePixel = 0
		build.AutoButtonColor = false
		build.Image = BUILD_ICON
		build.ImageTransparency = BUILD_ALPHA
		build.ScaleType = Enum.ScaleType.Fit
		build.ZIndex = 2
		build.Parent = buildSlot
		-- круг: скругление в половину стороны
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = build

		if BUILD_ICON == "" then
			-- пока картинки нет: обводка и слово, как у прыжка — без цветного пятна,
			-- чтобы заглушка не спорила со стилем и её не забыли заменить
			local ring = Instance.new("UIStroke")
			ring.Thickness = 3
			ring.Color = Color3.new(1, 1, 1)
			ring.Transparency = 0.25
			ring.Parent = build

			local buildText = label(build, "СТРОИТЬ", Enum.Font.GothamBlack, 15, Color3.new(1, 1, 1))
			buildText.Size = UDim2.fromScale(1, 1)
			buildText.ZIndex = 3
		end

		-- ⚠️ Activated, А НЕ MouseButton1Click.
		-- Первое приходит и от касания, и от мыши; второе на телефоне не срабатывает
		-- вовсе — ровно та же ловушка, из-за которой не работала добыча тапом.
		build.Activated:Connect(function()
			if _G.BuildPlaceNow then _G.BuildPlaceNow() end
		end)
	end

	local keys = Instance.new("Frame")
	keys.Name = "Hotkeys"
	keys.LayoutOrder = 3
	keys.Size = UDim2.fromOffset(0, 24)
	keys.AutomaticSize = Enum.AutomaticSize.X
	keys.BackgroundColor3 = UI_BLUE
	keys.BackgroundTransparency = 0.15
	keys.BorderSizePixel = 0
	keys.Visible = not onTouch   -- на телефоне подсказка про клавиши бессмысленна
	keys.Parent = root
	corner(keys, 12)

	local keysPad = Instance.new("UIPadding")
	keysPad.PaddingLeft = UDim.new(0, 14)
	keysPad.PaddingRight = UDim.new(0, 14)
	keysPad.Parent = keys

	local keysText = label(keys,
		"1–9 — выбрать   ·   Q / E — категория   ·   ЛКМ — построить"
			.. "   ·   Убери молоток или «Выйти»",
		Enum.Font.GothamBold, 12, UI_KEY_TEXT)
	keysText.AutomaticSize = Enum.AutomaticSize.X
	keysText.Size = UDim2.fromScale(0, 1)

	-- ── тост ──
	local toastBox = Instance.new("Frame")
	toastBox.Name = "Toast"
	toastBox.AnchorPoint = Vector2.new(0.5, 0)
	toastBox.Position = UDim2.new(0.5, 0, 0, 24)
	toastBox.Size = UDim2.fromOffset(0, 28)
	toastBox.AutomaticSize = Enum.AutomaticSize.X
	toastBox.BackgroundColor3 = UI_BLUE
	toastBox.BorderSizePixel = 0
	toastBox.Visible = false
	toastBox.Parent = buildingUI
	corner(toastBox, 8)

	local toastPad = Instance.new("UIPadding")
	toastPad.PaddingLeft = UDim.new(0, 16)
	toastPad.PaddingRight = UDim.new(0, 16)
	toastPad.Parent = toastBox

	toastLabel = label(toastBox, "", Enum.Font.GothamBlack, 13, UI_TOAST)
	toastLabel.AutomaticSize = Enum.AutomaticSize.X
	toastLabel.Size = UDim2.fromScale(0, 1)

	-- ── появление: подъём снизу, как в хендоффе ──
	-- ⚠️ ТОЛЬКО ПРИ ОТКРЫТИИ МОЛОТКА. Меню пересобирается на любой клик (плитка,
	-- категория, укрепление), и подъём игрался каждый раз — «всё UI дёргается».
	if not reopening then
		root.Position = UDim2.new(0.5, 0, 1, 4)
		TweenService:Create(root, TweenInfo.new(0.28, Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 1, -18) }):Play()
	end

	-- ПЕРЕКЛЮЧАТЕЛЬ ЗВУКА УКРЕПЛЕНИЯ: стрелки листают варианты, клик по подписи
	-- проигрывает текущий. Показываем только при выбранном укреплённом поле.
	if selectedItem and selectedItem.buildType == "reinforce" then
		local sndPanel = Instance.new("Frame")
		sndPanel.Name = "ReinforceSoundPicker"
		sndPanel.AnchorPoint = Vector2.new(0, 1)
		sndPanel.Position = UDim2.new(0, 12, 1, -12)
		sndPanel.AutomaticSize = Enum.AutomaticSize.XY
		sndPanel.BackgroundColor3 = UI_BLUE
		sndPanel.BackgroundTransparency = 0.15
		sndPanel.BorderSizePixel = 0
		sndPanel.Parent = buildingUI
		corner(sndPanel, 10)

		local sndPad = Instance.new("UIPadding")
		sndPad.PaddingLeft = UDim.new(0, 10)
		sndPad.PaddingRight = UDim.new(0, 10)
		sndPad.PaddingTop = UDim.new(0, 4)
		sndPad.PaddingBottom = UDim.new(0, 4)
		sndPad.Parent = sndPanel

		local sndRow = Instance.new("UIListLayout")
		sndRow.FillDirection = Enum.FillDirection.Horizontal
		sndRow.VerticalAlignment = Enum.VerticalAlignment.Center
		sndRow.Padding = UDim.new(0, 8)
		sndRow.SortOrder = Enum.SortOrder.LayoutOrder
		sndRow.Parent = sndPanel

		local function arrow(text, order, delta)
			local b = Instance.new("TextButton")
			b.Size = UDim2.fromOffset(26, 26)
			b.LayoutOrder = order
			b.BackgroundColor3 = UI_BLUE_DARK
			b.BorderSizePixel = 0
			b.Text = text
			b.TextColor3 = UI_WHITE
			b.Font = Enum.Font.GothamBlack
			b.TextSize = 18
			b.Parent = sndPanel
			corner(b, 13)
			b.MouseButton1Click:Connect(function()
				setReinforcePick(reinforcePick + delta)
			end)
			return b
		end

		arrow("‹", 1, -1)

		local sndLabel = Instance.new("TextButton")
		sndLabel.AutomaticSize = Enum.AutomaticSize.X
		sndLabel.Size = UDim2.fromOffset(0, 26)
		sndLabel.LayoutOrder = 2
		sndLabel.BackgroundTransparency = 1
		sndLabel.Text = pickLabelText()
		sndLabel.TextColor3 = UI_KEY_TEXT
		sndLabel.Font = Enum.Font.GothamBold
		sndLabel.TextSize = 14
		sndLabel.Parent = sndPanel
		sndLabel.MouseButton1Click:Connect(function()
			setReinforcePick(reinforcePick)   -- переиграть текущий
		end)
		reinforceSoundLabel = sndLabel

		arrow("›", 3, 1)
	else
		reinforceSoundLabel = nil
	end

end

-- ===================== Причал =====================

-- Подсказка по управлению: без неё игрок просто не знает, что причал крутится.
local dockHintGui = nil
function showDockHint(on) -- forward-declared выше
	if not on then
		if dockHintGui then dockHintGui.Enabled = false end
		return
	end
	if not dockHintGui then
		dockHintGui = Instance.new("ScreenGui")
		dockHintGui.Name = "DockHint"
		dockHintGui.ResetOnSpawn = false
		dockHintGui.IgnoreGuiInset = true
		dockHintGui.Parent = player:WaitForChild("PlayerGui")

		local box = Instance.new("Frame")
		box.AnchorPoint = Vector2.new(0.5, 1)
		box.Position = UDim2.new(0.5, 0, 1, -128)
		box.Size = UDim2.fromOffset(0, 32)
		box.AutomaticSize = Enum.AutomaticSize.X
		box.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
		box.BackgroundTransparency = 0.25
		box.BorderSizePixel = 0
		box.Parent = dockHintGui
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = box
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 14)
		pad.PaddingRight = UDim.new(0, 14)
		pad.Parent = box

		local txt = Instance.new("TextLabel")
		txt.AutomaticSize = Enum.AutomaticSize.X
		txt.Size = UDim2.new(0, 0, 1, 0)
		txt.BackgroundTransparency = 1
		txt.Font = Enum.Font.GothamBold
		txt.TextSize = 14
		txt.TextColor3 = Color3.fromRGB(235, 240, 245)
		txt.Text = "ЛКМ — поставить причал  ·  R — повернуть"
		txt.Parent = box
	end
	dockHintGui.Enabled = true
end

-- ВЕРХ НАСТИЛА ПЛОТА (держать равным серверной копии). Берём именно доску пола:
-- у Raft_part внутри бывают балки, а BuildType="raft" носит и якорь с рамой — по
-- ним причал взлетал вверх на несколько студов.
-- Возвращает верх доски пола И её толщину (Size.Y) — она нужна для выравнивания
-- по высоте: доска пола 2.3, а настил причала 2.099.
local function raftDeckTopY(raft)
	-- МАКСИМУМ, а не «первая попавшаяся доска»: здесь стояла первая, на сервере —
	-- максимум, и из-за одного этого превью висело не на той высоте, что постройка.
	local best, bestH
	for _, child in raft:GetChildren() do
		if child.Name == "Raft_part" then
			local floor = child:IsA("BasePart") and child
				or child:FindFirstChild("raft_floor", true)
				or child:FindFirstChildWhichIsA("BasePart", true)
			if floor and floor:IsA("BasePart") then
				local top = floor.Position.Y + floor.Size.Y / 2
				if not best or top > best then best, bestH = top, floor.Size.Y end
			end
		end
	end
	return best, bestH
end

-- Опорные величины причала (держать равным серверной копии): высота настила и
-- горизонтальный сдвиг до СЕРЕДИНЫ между настилами. Центр габаритов как точка
-- привязки не годится — лодка, столб и канат тянут его в сторону, и причал вставал
-- «от края», а не от клетки под курсором.
-- СДВИГ ПРИЧАЛА ОТНОСИТЕЛЬНО КЛЕТКИ (студы). Настил у Boat_3x вдоль оси 4.922 при
-- клетке 10, поэтому привязка = ширина настила − четверть клетки = 2.422. Считается
-- от модели, а не вбито числом. Держать равным серверной копии.
local DOCK_SHIFT_FINE   = 0
local DOCK_SHIFT_ACROSS = 0
local function dockAlongShift(deckW)
	return -((deckW or GRID_SIZE / 2) - GRID_SIZE / 4) + DOCK_SHIFT_FINE
end

local function dockMetrics(model)
	local bcf, bsize = model:GetBoundingBox()
	local l = model:FindFirstChild("Dock_deck_L", true)
	local r = model:FindFirstChild("Dock_deck_R", true)
	local deckTop = bsize.Y / 2
	local ax, az, dx, dz, steps = 0, 0, 0, 1, 2

	if l and l:IsA("BasePart") then
		deckTop = (l.Position.Y + l.Size.Y / 2) - bcf.Position.Y
		ax = l.Position.X - bcf.Position.X
		az = l.Position.Z - bcf.Position.Z
	end
	if l and r and l:IsA("BasePart") and r:IsA("BasePart") then
		local v = r.Position - l.Position
		local flat = Vector3.new(v.X, 0, v.Z)
		if flat.Magnitude > 1 then
			if math.abs(flat.X) >= math.abs(flat.Z) then
				dx, dz = (flat.X > 0) and 1 or -1, 0
			else
				dx, dz = 0, (flat.Z > 0) and 1 or -1
			end
			steps = math.max(1, math.round(flat.Magnitude / GRID_SIZE))
		end
	end

	-- габарит настила вдоль оси причала (проекцией граней) и его толщина
	local deckW, deckH
	if l and l:IsA("BasePart") then
		local axis, cf, s = Vector3.new(dx, 0, dz), l.CFrame, l.Size
		deckW = math.abs(cf.RightVector:Dot(axis)) * s.X
			+ math.abs(cf.UpVector:Dot(axis)) * s.Y
			+ math.abs(cf.LookVector:Dot(axis)) * s.Z
		deckH = s.Y
	end
	return deckTop, ax, az, dx, dz, steps, deckW, deckH
end

local function dockStep(dx, dz, rot)
	if rot == 1 then return dz, -dx end
	if rot == 2 then return -dx, -dz end
	if rot == 3 then return -dz, dx end
	return dx, dz
end

-- Мировой CFrame причала. Считается ТОЧНО так же, как на сервере: если формулы
-- разойдутся, призрак будет стоять не там, куда встанет постройка.
-- РОВНО, по курсу плота, настилом вровень с полом. Поправку getTileRotationCorrection
-- применять НЕЛЬЗЯ: она описывает развёрнутый на 90° пивот доски пола, а детали
-- причала лежат ровно — от неё он вставал на попа.
-- Клетки причала: под курсором — клетка НАСТИЛА Dock_deck_L, остальные уходят вдоль
-- его оси.
-- ⚠️ ОБЪЯВЛЕНО ПОСЛЕ dockMetrics/dockStep НАМЕРЕННО: в Lua local function видна
-- только ниже своего объявления, и когда dockCells стояла выше них, имена уходили
-- в глобальную область и оказывались nil — вся проверка падала с ошибкой, отчего
-- причал не краснел над полом и не ставился по ЛКМ.
local function dockCells(gx, gz, rot)
	local template = AssetFind.find(DOCK_TOOL)
	if not template then return { { gx, gz } } end
	local _, _, _, dx, dz, steps = dockMetrics(template)
	local sx, sz = dockStep(dx, dz, rot)
	local cells = {}
	for i = 0, steps do
		table.insert(cells, { gx + sx * i, gz + sz * i })
	end
	return cells
end

local function dockWorldCF(gx, gz, rot)
	local raft = getRaft()
	local prim = raft and raft.PrimaryPart
	if not prim then return nil end
	local template = AssetFind.find(DOCK_TOOL)
	if not template then return nil end

	local restCF = prim:GetAttribute("RestCFrame") or prim.CFrame
	local restYaw = prim:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
	local phaseX, phaseZ = getGridPhase(raft, GRID_SIZE)
	local worldOffset = restFlat:VectorToWorldSpace(
		Vector3.new(gx * GRID_SIZE + phaseX + FLOOR_FINE_X, 0, gz * GRID_SIZE + phaseZ + FLOOR_FINE_Z))
	local pos = (prim.CFrame * CFrame.new(restCF:VectorToObjectSpace(worldOffset))).Position

	local deckTop, ax, az, dx, dz, _, deckW, deckH = dockMetrics(template)
	local top, floorH = raftDeckTopY(raft)
	-- верх настила вровень с полом, минус половина разницы толщин досок (2.3 и 2.099)
	local lift = (deckH and floorH) and -(floorH - deckH) / 2 or 0
	local y = top and (top - deckTop + lift) or pos.Y
	-- сдвиг привязки поворачивается вместе с моделью, поэтому идёт ПОСЛЕ поворота
	local along = dockAlongShift(deckW)
	local shiftX = dx * along + dz * DOCK_SHIFT_ACROSS
	local shiftZ = dz * along + dx * DOCK_SHIFT_ACROSS
	return CFrame.new(pos.X, y, pos.Z) * CFrame.Angles(0, restYaw + rot * math.rad(90), 0)
		* CFrame.new(-ax + shiftX, 0, -az + shiftZ)
end

-- свободны ли все три клетки и примыкает ли хоть одна к полу
local function dockPlacementOk(gx, gz, rot)
	local offsets = getFloorOffsets()
	local touches = false
	for _, c in ipairs(dockCells(gx, gz, rot)) do
		if isFloorOccupied(offsets, c[1], c[2]) then return false end
		if isFloorAdjacent(offsets, c[1], c[2]) then touches = true end
	end
	return touches
end

-- ===================== Build Mode =====================

local function startBuildMode(dockOnly)
	if isBuilding then return end
	isBuilding = true
	dockMode = dockOnly == true
	-- ⚠️ HUD ПРЯЧЕМ ТОЛЬКО У МОЛОТКА: там панель стройки встаёт на место хотбара.
	-- У причала панели нет — только призрак и строка «ЛКМ / R», — и спрятанный
	-- HUD выглядел как пропавший инвентарь: ни хотбара, ни иконок, ни кнопок.
	if not dockMode then
		setWorldHudHidden(true) -- весь HUD уходит: панель стройки занимает его место
	end

	if dockMode then
		-- постройка одна, меню категорий не нужно
		selectedItem = DOCK_ITEM
		-- ПОВОРОТ ЧЕРЕЗ ContextActionService, а не через общий InputBegan: там
		-- клавиша могла быть уже съедена другим GUI (processed = true), и причал
		-- не разворачивался вообще.
		ContextActionService:BindAction("DockRotate", function(_, state)
			if state == Enum.UserInputState.Begin then
				dockRot = (dockRot + 1) % 4
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonY)   -- геймпад: Y = повернуть
		showDockHint(true)
	else
		selectedCategory = 1
		selectedItem = _G.BuildFloorPick(categories[1].items[1])
		_G.BuildSelectedItem = selectedItem
		buildUI()

		-- ⚠️ ЦИФРЫ ПЕРЕХВАТЫВАЕМ (Sink), А НЕ ПРОПУСКАЕМ.
		-- Те же клавиши переключают предметы в хотбаре, а он на время стройки
		-- скрыт: пропусти мы нажатие дальше — игрок жал бы «3», чтобы выбрать
		-- стену, и молча получал в руки факел, вываливаясь из режима. Пока меню
		-- открыто, цифры принадлежат ему.
		local DIGITS = {
			[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
			[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
			[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
		}
		ContextActionService:BindAction("BuildPickItem", function(_, state, input)
			if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
			local n = DIGITS[input.KeyCode]
			local list = categories[selectedCategory] and categories[selectedCategory].items
			-- ВРЕМЕННО: видно, дошло ли нажатие и есть ли такая плитка
			print(("[Стройка/клавиши] цифра=%s постройка=%s"):format(
				tostring(n), (n and list and list[n]) and list[n].name or "нет"))
			if n and list and list[n] then pickItem(list[n]) end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three,
			Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six,
			Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine)

		-- Q и E листают категории по кругу. Через ContextActionService по той же
		-- причине, что и поворот причала: общий InputBegan отдал бы клавишу
		-- первому, кто её съест.
		-- ⚠️ НА ТЕЛЕФОНЕ КЛАВИШ НЕТ — И ПРИВЯЗКИ ТОЖЕ.
		-- Категории там переключают тапом по самим таблеткам «Floors / Остров /
		-- Walls», а буквы Q и E над ними и под ними только сбивали с толку: их
		-- негде нажать. Заодно не занимаем клавиши на устройствах с клавиатурой И
		-- касанием — там ветка ниже всё равно отработает.
		if not (UserInputService.TouchEnabled and not UserInputService.MouseEnabled) then
		ContextActionService:BindAction("BuildPickCategory", function(_, state, input)
			if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
			pickCategory(selectedCategory + ((input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX) and 1 or -1))
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonX)   -- геймпад: B/X = категория
		end
	end

	createPreview()
	bindSoundCycle()   -- M: перебор вариантов звука укрепления (см. RaftReinforce)

	renderConnection = RunService.RenderStepped:Connect(function()
		if not isBuilding or not previewPart or not selectedItem then return end

		-- островные постройки ведёт свой скрипт: сеточный призрак им только мешал бы
		if selectedItem.buildType == "oilrig" or selectedItem.buildType == "house" then
			hidePreview()
			return
		end

		if selectedItem.buildType == "dock3" then
			local gx, gz = getFloorGridFromMouse()
			if not gx then hidePreview(); return end
			local cf = dockWorldCF(gx, gz, dockRot)
			if not cf then hidePreview(); return end
			movePreview(cf)
			setPreviewAppearance(dockPlacementOk(gx, gz, dockRot)
				and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)

		elseif selectedItem.buildType == "raft" or selectedItem.buildType == "net" then
			local gx, gz, worldCF = getFloorGridFromMouse()
			if not gx then hidePreview(); return end

			local offsets = getFloorOffsets()
			if isFloorOccupied(offsets, gx, gz) then hidePreview(); return end

			-- сеть занимает ту же клетку, но её пивот в центре, а не смещён как у доски
			if selectedItem.buildType == "net" then worldCF = netCFFromRaftCF(worldCF) end
			movePreview(worldCF)
			local canAfford = affordable(selectedItem)
			local adjacent = isFloorAdjacent(offsets, gx, gz)
			local valid = adjacent and canAfford and not _G.BuildFishFrontBlocked()
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)
			floorDebug(gx, gz, offsets, adjacent, canAfford)


		elseif selectedItem.buildType == "floor_upper" then
			-- Целимся в плоскость ВЕРХА СТЕН, а не в палубу (см. RaftUpperFloor):
			-- призрак есть только над клеткой, где собрана четвёрка больших стен.
			local raft = getRaft()
			if not (raft and raft.PrimaryPart) then hidePreview(); return end
			local offsets = getFloorOffsets()
			local gx, gz, cf = require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).cellFromRay(raft,
				camera:ScreenPointToRay((_G.BuildAim and _G.BuildAim.x) or mouse.X, (_G.BuildAim and _G.BuildAim.y) or mouse.Y),
				function(x, z) return isFloorOccupied(offsets, x, z) end,
				WallDefs.heightOf(previewPart))
			if not gx then hidePreview(); return end
			movePreviewCentred(cf)
			local valid = affordable(selectedItem) and not require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).findAt(raft, gx, gz)
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)

		elseif selectedItem.buildType == "stairs" then
			-- на любую стоящую клетку пола: центр клетки, низ на настил, R — поворот
			local raft = getRaft()
			local tile = tileFromMouse(true)
			if not (raft and raft.PrimaryPart and tile) then hidePreview(); return end
			local cf = require(ReplicatedStorage:WaitForChild("RaftStairs")).placeCF(raft, tile, _G.BuildStairsRot or 0, previewPart)
			if not cf then hidePreview(); return end
			movePreview(cf)
			local valid = affordable(selectedItem)
				and require(ReplicatedStorage:WaitForChild("PlaceCheck")).blocked(previewPart, raft) == nil
				and not require(ReplicatedStorage:WaitForChild("FarmPropRules")).onFarmFootprint(raft, cf.Position)
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)

		elseif selectedItem.buildType == "reinforce" then
			-- ЦЕЛЬ НАОБОРОТ: не пустая клетка, а УЖЕ СТОЯЩАЯ доска. Поэтому и показываем
			-- не призрак новой постройки, а подсветку самой доски — она точно ложится
			-- по её геометрии, без совпадающих плоскостей и мерцания.
			hidePreview()
			local tile = tileFromMouse()
			if not tile then setReinforceHighlight(nil); return end

			local canAfford = affordable(selectedItem)
			setReinforceHighlight(tile, canAfford and not RaftReinforce.isReinforced(tile))

		elseif selectedItem.buildType == "beam" then
			local cx, cz, worldCF = getBeamCornerFromMouse()
			if not cx then hidePreview(); return end

			movePreview(worldCF)
			local offsets = getFloorOffsets()
			local hasFloor = cornerHasFloor(offsets, cx, cz)
			local beamKey = makeBeamKey(cx, cz)
			local alreadyPlaced = getBeamKeys()[beamKey]
			local canAfford = affordable(selectedItem)
			local valid = hasFloor and not alreadyPlaced and canAfford
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)

		elseif selectedItem.buildType == "wall_panel" then
			local cx1, cz1, cx2, cz2, side, worldCF, level = getWallPanelFromMouse()
			if not cx1 then hidePreview(); return end

			movePreviewCentred(worldCF)
			-- Балок больше нет: достаточно, чтобы к ребру примыкал пол.
			local hasFloor = level == 2 or edgeHasFloor(getFloorOffsets(), cx1, cz1, cx2, cz2)
			local spanKey = require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).key(makeSpanKey(cx1, cz1, cx2, cz2), level)
			local spanOccupied = getWallSpanKeys()[spanKey]
			local canAfford = affordable(selectedItem)
			-- на клетках фермы и дома фермера — забор и стены дома: стену не ставить (FarmPropRules)
			local valid = hasFloor and not spanOccupied and canAfford and not (level ~= 2 and require(ReplicatedStorage:WaitForChild("FarmPropRules")).onFarmFootprint(getRaft(), worldCF.Position))
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)

		elseif selectedItem.buildType == "wall_arch" then
			local cx1, cz1, cx2, cz2, side, worldCF, level = getWallArchFromMouse()
			if not cx1 then hidePreview(); return end

			movePreviewCentred(worldCF)
			-- Балок больше нет: достаточно, чтобы к ребру примыкал пол.
			local hasFloor = level == 2 or edgeHasFloor(getFloorOffsets(), cx1, cz1, cx2, cz2)
			local spanKey = require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).key(makeSpanKey(cx1, cz1, cx2, cz2), level)
			local spanOccupied = getWallSpanKeys()[spanKey]
			local canAfford = affordable(selectedItem)
			-- на клетках фермы и дома фермера — забор и стены дома: стену не ставить (FarmPropRules)
			local valid = hasFloor and not spanOccupied and canAfford and not (level ~= 2 and require(ReplicatedStorage:WaitForChild("FarmPropRules")).onFarmFootprint(getRaft(), worldCF.Position))
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)

		elseif EDGE_WALLS[selectedItem.buildType] then
			-- ⚠️ ТЕ ЖЕ КЛЮЧИ ПРОЛЁТА, ЧТО У СТЕНЫ И ПРОЁМА.
			-- Ребро клетки занимает ЧТО-ТО ОДНО: окно, ограда, глухая стена или
			-- проём. Заведи им свой набор ключей — и на одном ребре встали бы две
			-- постройки внахлёст, а сносить их пришлось бы поодиночке.
			local cx1, cz1, cx2, cz2, side, worldCF, level = getEdgeWallFromMouse(selectedItem.buildType)
			if not cx1 then hidePreview(); return end

			movePreviewCentred(worldCF)
			local hasFloor = level == 2 or edgeHasFloor(getFloorOffsets(), cx1, cz1, cx2, cz2)
			local spanKey = require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).key(makeSpanKey(cx1, cz1, cx2, cz2), level)
			local spanOccupied = getWallSpanKeys()[spanKey]
			local canAfford = affordable(selectedItem)
			-- на клетках фермы и дома фермера — забор и стены дома: стену не ставить (FarmPropRules)
			local valid = hasFloor and not spanOccupied and canAfford and not (level ~= 2 and require(ReplicatedStorage:WaitForChild("FarmPropRules")).onFarmFootprint(getRaft(), worldCF.Position))
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)

		elseif selectedItem.buildType == "door" then
			local cx1, cz1, cx2, cz2, side, worldCF, level = getDoorFromMouse()
			if not cx1 then hidePreview(); return end

			movePreviewCentred(worldCF)
			local hasArch = getWallArchKeys()[require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).key(makeWallArchKey(cx1, cz1, cx2, cz2), level)]
			local doorExists = getDoorKeys()[require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).key(makeDoorKey(cx1, cz1, cx2, cz2), level)]
			local canAfford = affordable(selectedItem)
			local valid = hasArch and not doorExists and canAfford and not (level ~= 2 and require(ReplicatedStorage:WaitForChild("FarmPropRules")).onFarmFootprint(getRaft(), worldCF.Position))
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)
		end
	end)
end

-- Режим стройки включают ДВА тула: молоток (полное меню) и причал (одна постройка).
-- Возвращает имя тула или nil.
local function equippedBuildTool(character)
	if not character then return nil end
	local tool = character:FindFirstChildWhichIsA("Tool")
	if not tool then return nil end
	if tool.Name == "Hammer" or tool.Name == DOCK_TOOL then return tool.Name end
	return nil
end

-- ─── Wind warning UI ─────────────────────────────────────────────────────────
-- When wind is active we block the building GUI entirely and instead show a
-- warning label just above the hotbar. The hotbar lives at the bottom-centre
-- of the screen (see InventoryUI.client.lua); these offsets match its top
-- edge so the warning sits 10px above it.
local HOTBAR_TOP_OFFSET = -82    -- -(SLOT_SIZE + SLOT_PAD*2) - 10 from InventoryUI
local WARNING_GAP = 10           -- vertical gap above the hotbar
local WARNING_HEIGHT = 36

local windWarningGui = nil
local windWarningLabel = nil

local function ensureWindWarningGui()
	if windWarningGui and windWarningGui.Parent then return end

	windWarningGui = Instance.new("ScreenGui")
	windWarningGui.Name = "BuildWindWarning"
	windWarningGui.ResetOnSpawn = false
	windWarningGui.DisplayOrder = 25 -- above hotbar (5) and build UI (20)
	windWarningGui.IgnoreGuiInset = true
	windWarningGui.Enabled = false
	windWarningGui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Name = "Warning"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, HOTBAR_TOP_OFFSET - WARNING_GAP)
	label.Size = UDim2.new(0, 460, 0, WARNING_HEIGHT)
	label.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.Text = "Строить во время ветра опасно"
	label.TextColor3 = Color3.fromRGB(255, 200, 120)
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.Parent = windWarningGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(180, 120, 60)
	stroke.Thickness = 1.5
	stroke.Parent = label

	windWarningLabel = label
end

local function showWindWarning()
	ensureWindWarningGui()
	windWarningGui.Enabled = true
end

local function hideWindWarning()
	if windWarningGui then
		windWarningGui.Enabled = false
	end
end

-- ─── Wind state tracking ─────────────────────────────────────────────────────
local function isWindActive()
	return player:GetAttribute("WindActive") == true
end

local function syncBuildMode(character)
	local toolName = equippedBuildTool(character)
	local equipped = toolName ~= nil
	local wantDock = toolName == DOCK_TOOL
	local windActive = isWindActive()

	-- сменили молоток на причал (или наоборот) без выхода из режима — пересобираем
	if isBuilding and equipped and wantDock ~= dockMode then
		closeBuildMode()
	end

	if equipped and windActive then
		-- Hammer out during wind: block the build UI, show warning.
		if isBuilding then closeBuildMode() end
		showWindWarning()
	elseif equipped and not windActive then
		-- Safe to build.
		hideWindWarning()
		if not isBuilding then startBuildMode(wantDock) end
	else
		-- Hammer not equipped: nothing to show.
		hideWindWarning()
		if isBuilding then closeBuildMode() end
	end
end

-- Re-sync whenever wind turns on/off so the warning appears/disappears
-- without the player having to re-equip the hammer.
player:GetAttributeChangedSignal("WindActive"):Connect(function()
	syncBuildMode(player.Character)
end)

local function onCharacterAdded(character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and (child.Name == "Hammer" or child.Name == DOCK_TOOL) then
			syncBuildMode(character)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and (child.Name == "Hammer" or child.Name == DOCK_TOOL) then
			syncBuildMode(character)
		end
	end)

	-- Some inventory flows re-parent tools in a way that can miss ChildAdded/Removed
	-- transitions, so we keep a lightweight heartbeat sync as a safety net.
	if hammerWatchConnection then
		hammerWatchConnection:Disconnect()
	end
	hammerWatchConnection = RunService.Heartbeat:Connect(function()
		syncBuildMode(character)
	end)

	syncBuildMode(character)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if hammerWatchConnection then
				hammerWatchConnection:Disconnect()
				hammerWatchConnection = nil
			end
			closeBuildMode()
			hideWindWarning()
		end
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

-- Click to place
-- ⚠️ УДЕРЖАНИЕ НА ПАЛУБЕ — ОБЩЕЕ, В МОДУЛЕ RaftShake.
-- Здесь лежала своя копия, пока сборку плота перестраивала только стройка. Потом
-- выяснилось, что ровно так же трясут очиститель, грядка, печь, костёр и кровать —
-- и игрока утаскивало у каждой из них. Копии по системам разъехались бы, поэтому
-- код один, а зовут его двое: сервер после каждой перестройки (всем клиентам сразу)
-- и стройка вот здесь — она знает о постройке на кадр раньше ответа сервера.
function keepFooting()
	if _G.KeepRaftFooting then _G.KeepRaftFooting() end
end

local function playPlaceSound()
	-- взмах молотком — см. комментарий у playReinforceSound
	if _G.PlayHammerSwing then _G.PlayHammerSwing() end
	keepFooting()
	-- ⚠️ ЗВУК ИЩЕМ И ВГЛУБЬ, А НЕ ПРЯМЫМ РЕБЁНКОМ.
	-- Ровно та же ловушка, что была с моделями в ReplicatedStorage: стоило
	-- разложить звуки по папкам — и звук в игре пропал ВЕСЬ разом, молча, без
	-- единой строки в логе. Уцелел только тот, что ничего не ищет, а создаётся в
	-- коде со встроенным rbxasset://. Такой же второй аргумент true стоит теперь
	-- у всех поисков звука в проекте.
	local folder = (SoundService:FindFirstChild("Building") or SoundService:FindFirstChild("Building", true))
	local snd = folder and folder:FindFirstChild("Place_Block")
	if snd then snd:Play() end
end

-- ⚠️ САМА ПОСТАНОВКА ВЫНЕСЕНА В _G, А НЕ ЛЕЖИТ В ОБРАБОТЧИКЕ.
-- Её зовут двое: ЛКМ на компьютере (ниже) и кнопка «Построить» на телефоне (она
-- живёт внутри buildUI). Держать две копии этой лестницы из десяти веток нельзя —
-- разъедутся на первой же новой постройке.
-- Через _G, а не через локальную функцию, НАМЕРЕННО: файл упёрся в предел Luau на
-- локальные переменные, и лишняя `local` наверху ломает компиляцию всего меню
-- (см. предупреждение у netTemplate).
_G.BuildPlaceNow = function()
	if not isBuilding or not selectedItem then return end

	if selectedItem.buildType == "dock3" then
		local gx, gz = getFloorGridFromMouse()
		if not gx then return end
		if not dockPlacementOk(gx, gz, dockRot) then return end
		placeBlockEvent:FireServer("dock3", gx, gz, dockRot)
		playPlaceSound()

	elseif selectedItem.buildType == "raft" or selectedItem.buildType == "net" then
		local gx, gz, _ = getFloorGridFromMouse()
		if not gx then return end

		local offsets = getFloorOffsets()
		if isFloorOccupied(offsets, gx, gz) then return end
		if not isFloorAdjacent(offsets, gx, gz) then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end
		if _G.BuildFishFrontBlocked() then return end   -- вода перед рыбаком: призрак уже красный

		placeBlockEvent:FireServer(selectedItem.buildType, gx, gz) -- "raft" или "net"
		playPlaceSound()


	elseif selectedItem.buildType == "floor_upper" then
		local raft = getRaft()
		if not (raft and raft.PrimaryPart) then return end
		local offsets = getFloorOffsets()
		local gx, gz = require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).cellFromRay(raft,
			camera:ScreenPointToRay((_G.BuildAim and _G.BuildAim.x) or mouse.X, (_G.BuildAim and _G.BuildAim.y) or mouse.Y),
			function(x, z) return isFloorOccupied(offsets, x, z) end,
			previewPart and WallDefs.heightOf(previewPart) or 1)
		if not gx then return end
		if require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).findAt(raft, gx, gz) or not affordable(selectedItem) then return end
		placeBlockEvent:FireServer("floor_upper", gx, gz)
		playPlaceSound()

	elseif selectedItem.buildType == "stairs" then
		-- клетку шлём самим тайлом (как укрепление): сервер считает позу по нему
		local tile = tileFromMouse(true)
		if not tile or not affordable(selectedItem) then return end
		placeBlockEvent:FireServer("stairs", tile, _G.BuildStairsRot or 0)
		playPlaceSound()

	elseif selectedItem.buildType == "reinforce" then
		-- Отправляем САМУ ДОСКУ, а не координаты клетки: сервер тогда укрепляет ровно
		-- то, что подсвечено, и ему не нужно повторять вычисление клетки (на котором
		-- центр плота и место у монолита как раз и ломались).
		local tile = tileFromMouse()
		if not tile or RaftReinforce.isReinforced(tile) then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("reinforce", tile)
		playReinforceSound()   -- металл, а не стук доски

	elseif selectedItem.buildType == "beam" then
		local cx, cz, _ = getBeamCornerFromMouse()
		if not cx then return end

		local offsets = getFloorOffsets()
		if not cornerHasFloor(offsets, cx, cz) then return end
		if getBeamKeys()[makeBeamKey(cx, cz)] then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("beam", cx, cz)
		playPlaceSound()

	elseif selectedItem.buildType == "wall_panel" then
		local cx1, cz1, cx2, cz2, side, _, level = getWallPanelFromMouse()
		if not cx1 then return end

		-- Балок больше нет: нужен только примыкающий пол.
		if level ~= 2 and not edgeHasFloor(getFloorOffsets(), cx1, cz1, cx2, cz2) then return end
		if getWallSpanKeys()[require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).key(makeSpanKey(cx1, cz1, cx2, cz2), level)] then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("wall_panel", cx1, cz1, cx2, cz2, level)
		playPlaceSound()

	elseif selectedItem.buildType == "wall_arch" then
		local cx1, cz1, cx2, cz2, side, _, level = getWallArchFromMouse()
		if not cx1 then return end

		-- Балок больше нет: нужен только примыкающий пол.
		if level ~= 2 and not edgeHasFloor(getFloorOffsets(), cx1, cz1, cx2, cz2) then return end
		if getWallSpanKeys()[require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).key(makeSpanKey(cx1, cz1, cx2, cz2), level)] then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("wall_arch", cx1, cz1, cx2, cz2, level)
		playPlaceSound()

	elseif EDGE_WALLS[selectedItem.buildType] then
		local cx1, cz1, cx2, cz2, side, _, level = getEdgeWallFromMouse(selectedItem.buildType)
		if not cx1 then return end

		if level ~= 2 and not edgeHasFloor(getFloorOffsets(), cx1, cz1, cx2, cz2) then return end
		if getWallSpanKeys()[require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).key(makeSpanKey(cx1, cz1, cx2, cz2), level)] then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer(selectedItem.buildType, cx1, cz1, cx2, cz2, level)
		playPlaceSound()

	elseif selectedItem.buildType == "door" then
		local cx1, cz1, cx2, cz2, side, _, level = getDoorFromMouse()
		if not cx1 then return end

		if not getWallArchKeys()[require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).key(makeWallArchKey(cx1, cz1, cx2, cz2), level)] then return end
		if getDoorKeys()[require(ReplicatedStorage:WaitForChild("RaftUpperFloor")).key(makeDoorKey(cx1, cz1, cx2, cz2), level)] then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("door", cx1, cz1, cx2, cz2, level)
		playPlaceSound()
	end
end

-- ⚠️ НА ТЕЛЕФОНЕ ТАП НЕ СТРОИТ. СТРОИТ КНОПКА.
-- Тап и так наводит призрак: «мышь» на телефоне встаёт в точку касания, и призрак
-- переезжает туда сам. Если этим же тапом ещё и ставить, то любое касание экрана —
-- случайная постройка, а со стенами это особенно больно: их край не видно, пока не
-- прицелишься. Поэтому тап = прицел, а постановка — отдельной кнопкой «Построить»
-- в панели (см. buildUI). Два действия, но второе по крупной кнопке, а не «попади
-- ещё раз в ту же точку».
-- На компьютере всё как было: ЛКМ ставит сразу, кнопки там нет.
UserInputService.InputBegan:Connect(function(input, processed)
	-- ТАП ПО МИРУ = ПРИЦЕЛ. Запоминаем точку и НЕ строим: строит кнопка.
	-- processed = false означает «мимо интерфейса», то есть игрок ткнул в мир, а не
	-- в панель. Нажатие на саму кнопку сюда не попадает и прицел не сбивает.
	if input.UserInputType == Enum.UserInputType.Touch and not processed then
		_G.BuildAim = { x = input.Position.X, y = input.Position.Y }
		return
	end
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	-- на компьютере целимся мышью, а не сохранённой точкой
	_G.BuildAim = nil
	_G.BuildPlaceNow()
end)

placeBlockEvent.OnClientEvent:Connect(function() end)

-- R ПОВОРАЧИВАЕТ ЛЕСТНИЦУ на четверть (состояние в _G: файл у предела локалей)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.R and isBuilding and selectedItem and selectedItem.buildType == "stairs" then
		_G.BuildStairsRot = ((_G.BuildStairsRot or 0) + 1) % 4
	end
end)

--[[ ⚠️ ИКОНКИ МОЛОТКА РИСУЕМ ЗАРАНЕЕ. Модели построек впервые рисовались в
     момент, когда игрок открывал меню, и иконки проявлялись у него на глазах.
     Сразу после загрузки кладём каждую на скрытую полку ModelIcon (полный
     размер, за краем экрана) — меню берёт уже готовые рамки (take) и отдаёт их
     обратно перед закрытием (reclaim). Без новых local: файл у предела 200. ]]
task.spawn(function()
	task.wait(1)
	-- образец укреплённой доски для иконки: клон пола + тот же рецепт, что на сервере
	pcall(function()
		local sample = raftPartTemplate:Clone()
		RaftReinforce.apply(sample)
		_G.ReinforceIconTemplate = sample
	end)
	if categories[1].reinforce then ModelIcon.warm(iconTemplateFor(categories[1].reinforce)) end
	local n = 0
	for _, cat in ipairs(categories) do
		for _, item in ipairs(cat.items or {}) do
			local ok, tpl = pcall(iconTemplateFor, item)
			if ok and tpl then
				ModelIcon.warm(tpl)
				n += 1
				task.wait(0.03)   -- по одной, без просадки кадров
			end
		end
	end
	print(("[Стройка/клиент] иконки молотка нарисованы скрыто: %d"):format(n))
end)
