-- WorldEventSpawner.server.lua
-- The floating world events that drift past the sailing raft, the way islands appear in
-- "Raft": always in the 180° arc AHEAD of the bow, far out toward the horizon.
--   • Islands (Island_1/2/3) — far away ("barely in view"), every ISLAND_INTERVAL_MIN..MAX, kept
--     at their OWN authored height (Y taken from the model), cleared by IslandClearSystem
--     once the raft reaches them.
--   • Radiation_event — loot cisterns, closer in, spawned every few minutes; they slowly
--     drift along a fixed ocean current, independent of the raft.
-- Replaces the old IslaldsSpawn.server.lua (which spawned in a full 360° circle and wrongly
-- lifted islands up to the water line). The raft's bow direction comes from BoatMovement's
-- RestYaw attribute; the raft centre from _G.GetRaftCenter (ShipCombat).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

-- Шаблоны островов ищем ПО ИМЕНИ во всех папках: ReplicatedStorage давно
-- разложен по папкам, а прямой FindFirstChild на это отвечает молчаливым nil.
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

-- ─── Config ───
-- Islands
-- byBounds = true — остров ставится ПО ГАБАРИТАМ, а не по пивоту.
-- Высота при этом остаётся АВТОРСКОЙ: какая у модели в ReplicatedStorage, такая и в
-- океане. Меняется только горизонталь. Нужно это потому, что у импортированной
-- FBX-сцены (TropicIsland_SCENE) пивот лежит в стороне от геометрии, и PivotTo
-- уносил остров непонятно куда. Старые Island_1..3 ставятся по-прежнему, по пивоту.
local ISLAND_TEMPLATES = {
	{ name = "Island_1" },
	{ name = "Island_2" },
	{ name = "Island_3" },
	{ name = "TropicIsland_SCENE", byBounds = true },
	-- Пиратский лагерь: население (гарнизон, пленные, животные) расставляет
	-- PirateIsland.server.lua по маркерам Pt_* внутри самой модели.
	{ name = "PirateIsland_SCENE", byBounds = true },
	-- Остров-терраса: двухуровневый, ферма с полем вируса наверху. Гарнизон и
	-- взрывоопасный самогонный аппарат — TerraceIsland.server.lua.
	{ name = "TerraceIsle_SCENE", byBounds = true },
	-- ⚠️ ОСТРОВ БЕЗ СТРОКИ ЗДЕСЬ НЕ ПОДНИМЕТСЯ ВОВСЕ.
	-- Список — белый: _G.SpawnIsland по имени ищет запись в нём, а не модель в
	-- ReplicatedStorage. Забыть строку значит получить «нет такого острова в
	-- списке» на кнопке, при том что модель на месте.
	-- Верфь и малый остров: гарнизон, маршруты и клетку ведёт IslandCrews.server.lua.
	{ name = "ShipIsle_SCENE",  byBounds = true },
	{ name = "SmallIsle_SCENE", byBounds = true },
	-- Скальный остров: пальма и корова, всё остальное — камни и трава.
	-- Дерево уже приходит МОДЕЛЬЮ «Coconut tree», то есть топор понимает его без
	-- обёртки; корову ставит StartIsle.server.lua по точке CowSpawner.
	{ name = "RockIsle_SCENE", byBounds = true },
	-- СТАРТОВЫЙ ОСТРОВ: сюжетный, поднимается не по таймеру, а по расписанию —
	-- второй день, 30% дня (StartIsleStory.server.lua). Ни пиратов, ни построек:
	-- дерево, шесть куртин бамбука и корова, которую расставляет
	-- StartIsle.server.lua. Строка нужна всё равно — список белый.
	-- names — запасные имена модели. Импортёр Studio называет сцену по файлу
	-- (StartIsle_SCENE.fbx), но папку набора зовут просто StartIsle, и модель
	-- часто переименовывают под неё. Клон в любом случае получит имя из name —
	-- по нему остров ищут StartIsle.server.lua и сценарий.
	{ name = "StartIsle_SCENE", names = { "StartIsle_SCENE", "StartIsle" },
		byBounds = true, story = true },
	-- ОСТРОВ-АВАНПОСТ: второй сюжетный. Поднимается через день после стартового
	-- (OutpostIsleStory.server.lua), гарнизон из двух пиратов на КПП ставит
	-- IslandCrews, поле вируса жжётся кодом TerraceIsland.
	{ name = "OutpostIsle_SCENE", names = { "OutpostIsle_SCENE", "OutpostIsle" },
		byBounds = true, story = true },
	--[[ ОСТРОВ ФЕРМЕРОВ (пакет Farmers_Island_Transfer): двухъярусный, с рекой,
	     водопадом и теплицами. Гарнизон — НАШИ пираты по площадкам
	     Gameplay/Spawns, ставит IslandCrews (владелец: чужой NPC-рантайм не
	     подключаем, поведение как на прошлых островах).
	     ⚠️ manual — в случайную выдачу пока не идёт: только кнопка админа.
	     ⚠️ killScripts — родной Runtime пакета сносим ДО того, как клон попадёт в
	     мир: его серверную часть (спавн жителей, ИИ охраны/мутанта/учёных/
	     работников) поднимает IslandCrews из НАШИХ копий модулей
	     (ReplicatedStorage/FarmersIsland), без пиратов. Сундуки пакета лут не
	     выдают — их серверную часть тоже поднимает IslandCrews (лут наш).
	     Клиентские позы мутанта и свечение сундуков рисует НАШ
	     StarterPlayerScripts/FarmersIslandClient — родные MutantClient/ChestClient
	     сносим, иначе эффект шёл бы дважды. Воду и инструменты включаем: в
	     экспорте они выключены до INSTALL, а INSTALL мы не запускаем. ]]
	{ name = "Farmers_Game_Water", names = { "Farmers_Game_Water", "Farmers_Island" },
		byBounds = true, manual = true,
		killScripts = { Runtime = true, MutantClient = true, ChestClient = true },
		enableScripts = { PortableWaterClient = true, ToolsClient = true } },
	--[[ ОСТРОВ КРАБОВ (пакет ServerStorage.CrabIsland_Transfer, не ReplicatedStorage):
	     шаблон и уровень воды тестового плейса отдаёт CrabIsland.server. Высоту
	     сдвигаем так, чтобы вода тестового плейса совпала с нашей (WaterY):
	     пляж и мелководье, по которым ходят крабы, остаются на своих местах.
	     Крабов по маркерам CrabTransferSpawns ставит тот же CrabIsland.server. ]]
	{ name = "Crab_Rock_Island", byBounds = true, manual = true,
		findTemplate = function() return typeof(_G.CrabIslandTemplate) == "function" and _G.CrabIslandTemplate() or nil end,
		waterLine = function() return typeof(_G.CrabIslandWaterLine) == "function" and _G.CrabIslandWaterLine() or nil end },
	-- ПЕСЧАНАЯ ОТМЕЛЬ (пакет SandyShoal_Transfer): 1 краб и 1 сундук ставит
	-- CrabIsland.server; родные спавнеры пакета сносим, чтобы не было вторых
	-- ЗАБЫТЫЙ КРАТЕР (Crater_Island): 3 краба и 2 сундука ставит CrabIsland.server,
	-- двух пиратов-сторожей с саблями — IslandCrews; родные спавнеры сносим
	{ name = "Crater_Island", names = { "Crater_Island", "Crater", "Forgotten_Crater_Island" },
		byBounds = true, manual = true,
		killScripts = { CraterCrabSpawner = true, ChestSpawner = true },
		findTemplate = function() return typeof(_G.CraterIslandTemplate) == "function" and _G.CraterIslandTemplate() or nil end,
		waterLine = function() return typeof(_G.CraterIslandWaterLine) == "function" and _G.CraterIslandWaterLine() or nil end },
	{ name = "Sandy_Shoal_Island", byBounds = true, manual = true,
		killScripts = { ChestSpawner = true, ShoalCrabSpawner = true },
		findTemplate = function() return typeof(_G.ShoalIslandTemplate) == "function" and _G.ShoalIslandTemplate() or nil end,
		waterLine = function() return typeof(_G.ShoalIslandWaterLine) == "function" and _G.ShoalIslandWaterLine() or nil end },
}
-- Дистанция для кнопки «(тест)» в настройках: остров должен быть виден сразу и
-- достижим за полминуты хода, а не «еле заметен на горизонте».
-- ⚠️ У byBounds-островов это расстояние ДО БЕРЕГА, а не до центра: радиус острова
-- прибавляется отдельно, иначе большой остров встаёт вплотную к плоту.
local TEST_DIST_MIN, TEST_DIST_MAX = 320, 380
-- Интервал между островами (после первого): СЛУЧАЙНО 300–400с — острова идут часто.
local ISLAND_INTERVAL_MIN = 300
local ISLAND_INTERVAL_MAX = 400
-- ПЕРВЫЙ остров — рано: случайно в первые 1–2 минуты, чтобы игрок сразу увидел
-- цель на горизонте, а не ждал полного интервала.
local FIRST_ISLAND_MIN    = 60
local FIRST_ISLAND_MAX    = 120
local ISLAND_DIST_MIN     = 1700   -- spawn distance from the raft centre …
local ISLAND_DIST_MAX     = 1900   -- … ~1800 → "barely in view" on the horizon
local ISLAND_DESPAWN_DIST = 1200   -- once BEHIND the raft and farther than this → removed
local ISLAND_HARD_CULL    = 3500   -- removed at this range regardless of direction (e.g. raft turned away)

-- Radiation loot cisterns
local RAD_TEMPLATE        = "Radiation_event"
-- Та же логика, что у островов: держим старую частоту В СУТКАХ (примерно раз в
-- 2-4.5 дня), а не в секундах — иначе редкое лут-событие стало бы ежедневным.
local RAD_INTERVAL_MIN    = 1.9 * (380 + 120) -- ~950с
local RAD_INTERVAL_MAX    = 4.6 * (380 + 120) -- ~2300с
local RAD_DIST_MIN        = 850    -- closer than islands …
local RAD_DIST_MAX        = 950    -- … ~900, but still far from the raft
local RAD_DRIFT_DIR       = Vector3.new(1, 0, 0.35) -- fixed "ocean current" (normalised below)
local RAD_DRIFT_SPEED     = 4      -- studs/s the cisterns drift along the current
local RAD_DESPAWN_DIST    = 2200   -- removed once farther than this from the raft

-- Shared
local FRONT_ARC           = math.rad(90) -- ± this from the bow → a 180° arc ahead
local STARTUP_DELAY       = 5      -- let the raft + BoatMovement settle before the first spawn

RAD_DRIFT_DIR = (RAD_DRIFT_DIR.Magnitude > 0) and RAD_DRIFT_DIR.Unit or Vector3.new(1, 0, 0)

-- ─── Raft helpers ───
local function getRaft()
	local raft = Workspace:FindFirstChild("Raft")
	if raft and raft.PrimaryPart then return raft end
	return nil
end

local function getRaftCenter(raft)
	if _G.GetRaftCenter then
		local c = _G.GetRaftCenter()
		if c then return c end
	end
	return raft.PrimaryPart.Position
end

-- The raft's bow direction (horizontal). BoatMovement writes RestYaw every heartbeat; the
-- horizontal projection of the bow at yaw Y is always (-sin Y, 0, -cos Y).
local function getRaftFront(raft)
	local yaw = raft.PrimaryPart:GetAttribute("RestYaw")
	if yaw then
		return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	end
	local lv = raft.PrimaryPart.CFrame.LookVector
	local flat = Vector3.new(lv.X, 0, lv.Z)
	return (flat.Magnitude > 0.01) and flat.Unit or Vector3.new(0, 0, -1)
end

-- Rotate a horizontal vector around the Y axis by `angle` radians.
local function rotateY(dir, angle)
	local c, s = math.cos(angle), math.sin(angle)
	return Vector3.new(dir.X * c + dir.Z * s, 0, -dir.X * s + dir.Z * c)
end

-- horizontal distance between two world points
local function flatDist(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- A spawn CFrame in the 180° arc ahead of the raft, `distMin..distMax` out, keeping the
-- template's OWN authored Y so the model lands at its real height (not lifted to the water).
-- straight = строго по курсу (кнопка «(тест)»): искать остров по всей полусфере,
-- когда ты его только что вызвал, — занятие на любителя.
--[[ SEED МИРА. Все розыгрыши островов (какой, где, как повёрнут) идут из одного
     генератора с seed. Seed уникален на сейв (время × 1000 + случайное число),
     хранится в сейве вместе с числом уже сделанных розыгрышей: после загрузки
     генератор переводится в то же состояние, и следующие острова выйдут теми
     же, что вышли бы без перезахода. Уже поднятые острова при этом
     восстанавливаются по сохранённым позициям, seed нужен для будущих. ]]
local worldSeed = os.time() * 1000 + math.random(0, 999)
local rngStep = 0
-- каждый розыгрыш — свой генератор от (seed, номер): состояние не зависит от
-- того, целое или дробное брали раньше, и после загрузки продолжается с номера
local function drawRng() rngStep += 1 return Random.new(worldSeed * 131 + rngStep) end
local function nextNum() return drawRng():NextNumber() end
local function nextInt(a, b) return drawRng():NextInteger(a, b) end
_G.GetWorldSeed = function() return { seed = worldSeed, step = rngStep } end
_G.SetWorldSeed = function(seed, step)
	seed = tonumber(seed); if not seed then return end
	worldSeed = math.floor(seed)
	rngStep = math.max(0, math.floor(tonumber(step) or 0))
	print(("[WorldEventSpawner] seed мира из сейва: %d, розыгрышей пропущено %d"):format(worldSeed, rngStep))
end

local function pickSpawnCFrame(raft, template, distMin, distMax, straight)
	local center = getRaftCenter(raft)
	local front  = getRaftFront(raft)
	local angle  = straight and 0 or (nextNum() * 2 - 1) * FRONT_ARC   -- [-90°, +90°] off the bow
	local dir    = rotateY(front, angle)
	local dist   = distMin + nextNum() * (distMax - distMin)
	local modelY = template:GetPivot().Position.Y               -- the model's real height
	local pos    = Vector3.new(center.X + dir.X * dist, modelY, center.Z + dir.Z * dist)
	return CFrame.new(pos) * CFrame.Angles(0, nextNum() * math.pi * 2, 0) -- random facing
end

-- ГАБАРИТ СУШИ, БЕЗ ПЛИТЫ ДНА.
--
-- ⚠️ Полный габарит модели тут врёт вдвое больше километра: у TropicIsland_SCENE
-- Island_seabed — плита 2048×2048 студов, и по ней радиус выходил 1024. Остров
-- отодвигало за горизонт (его просто не было видно), а ResourceSpawner переставал
-- ронять ресурсы в радиусе километра вокруг. Меряем по тайлам суши.
local LAND_PREFIX = "island_terrain"

local function landInfo(model)
	local lo, hi
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:lower():sub(1, #LAND_PREFIX) == LAND_PREFIX then
			local half = d.Size * 0.5
			local a, b = d.Position - half, d.Position + half
			lo = lo and Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z)) or a
			hi = hi and Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z)) or b
		end
	end
	if not lo then
		-- тайлов суши не нашлось — работаем по всей модели, как раньше
		local cf, size = model:GetBoundingBox()
		return cf.Position, size
	end
	return (lo + hi) * 0.5, hi - lo
end

-- ПОСТАНОВКА ПО СУШЕ. Двигаем остров ТОЛЬКО ПО ГОРИЗОНТАЛИ; высота остаётся ровно
-- такой, какая у модели в ReplicatedStorage — ничего не пересчитываем.
--
-- ⚠️ Почему не обычный PivotTo: он ставит на точку ПИВОТ, а у импортированной
-- FBX-сцены пивот лежит в стороне от геометрии — остров уезжал непонятно куда.
-- Здесь целевой точке соответствует центр СУШИ, а его Y берётся у шаблона как есть,
-- поэтому авторская высота сохраняется точно.
local function placeIslandByBounds(island, template, raft, distMin, distMax, straight)
	local tLandCenter, tLandSize = landInfo(template)
	local radius = math.max(tLandSize.X, tLandSize.Z) * 0.5

	local center = getRaftCenter(raft)
	local front  = getRaftFront(raft)
	local angle  = straight and 0 or (nextNum() * 2 - 1) * FRONT_ARC
	local dir    = rotateY(front, angle)
	-- дистанция считается ДО БЕРЕГА: центр отодвигается на радиус суши
	local dist   = distMin + nextNum() * (distMax - distMin) + radius

	-- Y — АВТОРСКИЙ, как лежит в ReplicatedStorage
	local target = Vector3.new(center.X + dir.X * dist, tLandCenter.Y, center.Z + dir.Z * dist)

	-- Пивот клона приводим к центру суши — тогда PivotTo и поворот работают
	-- предсказуемо, от геометрии, а не от авторской точки неизвестно где.
	local cLandCenter = landInfo(island)
	island.WorldPivot = CFrame.new(cLandCenter)
	island:PivotTo(CFrame.new(target) * CFrame.Angles(0, nextNum() * math.pi * 2, 0))

	return radius, dist, tLandSize
end

-- ─── Islands ───
-- Each entry: { model = Model, center = Vector3, radius = number }. Islands are anchored and
-- never move after spawn, so centre/radius are cached once.
local islands = {}

--[[ ⚠️ СЛУЧАЙНЫЕ ОСТРОВА ЖДУТ, ПОКА ВЫЙДУТ ОБА СЮЖЕТНЫХ.
     Таймер этих островов не знал о сюжете вообще: первый случайный всплывал
     через 60–120 секунд после старта сервера, то есть на ПЕРВОМ дне (день длится
     380 секунд). Игрок ещё не видел ни стартового острова, ни аванпаста, а на
     горизонте уже стоит чужая земля — и непонятно, куда его вообще ведут.
     Сюжетные из случайной выдачи и раньше исключались, но это решало только
     «не тот остров», а не «слишком рано».
     Ворота простые: пока не поднялся АВАНПОСТ (он же второй сюжетный, третий
     день), случайных не даём вовсе. Стартовый выходит на второй день, аванпост
     на третий — значит первые два острова в игре гарантированно сюжетные и
     именно в этом порядке.
     ⚠️ Считаем по факту подъёма, а не по номеру дня: расписание сцены могут
     сдвинуть, а зависимость «сначала сюжет, потом остальное» должна пережить
     любую такую правку. ]]
local storyRaised = {}
local STORY_GATE  = "OutpostIsle_SCENE"

-- Publish live island footprints for other systems. ResourceSpawner reads _G.IslandPositions
-- to avoid dropping resources on top of an island (this was the old spawner's contract).
local function publishIslandPositions()
	local list = {}
	for _, e in ipairs(islands) do
		if e.model.Parent then
			table.insert(list, { center = e.center, radius = e.radius })
		end
	end
	_G.IslandPositions = list
end
publishIslandPositions() -- start as an empty list, never nil

-- opts:
--   name     — поднять КОНКРЕТНЫЙ остров, а не случайный;
--   test     — поставить ближе и строго по курсу, чтобы дойти за полминуты;
--   straight — строго по курсу, но со своей дистанцией (сюжетный остров);
--   distMin/distMax — своя дистанция ДО БЕРЕГА вместо штатной «еле видно».
local function spawnIsland(raft, opts)
	opts = opts or {}
	local spec
	if opts.name then
		for _, s in ipairs(ISLAND_TEMPLATES) do
			if s.name == opts.name then spec = s break end
		end
		if not spec then return nil, "нет такого острова в списке: " .. tostring(opts.name) end
	else
		-- ⚠️ СЮЖЕТНЫЕ ОСТРОВА В СЛУЧАЙНУЮ ВЫДАЧУ НЕ ПОПАДАЮТ.
		-- Стартовый остров обязан прийти ровно в свой момент (второй день, 30%
		-- дня), а не когда таймеру вздумается: если он всплывёт в первый день,
		-- катсцена «мы нашли землю» сыграет посреди обучения, а расписание потом
		-- поднимет его второй раз.
		local pool = {}
		for _, s in ipairs(ISLAND_TEMPLATES) do
			if not s.story and not s.manual then table.insert(pool, s) end
		end
		spec = pool[nextInt(1, #pool)]
	end
	-- по имени во всех папках, а не только среди прямых детей: модели давно
	-- разложены по папкам, и FindFirstChild молча возвращал nil (см. AssetFind)
	local template = (spec.findTemplate and spec.findTemplate())
		or AssetFind.find(table.unpack(spec.names or { spec.name }))
		or ReplicatedStorage:FindFirstChild(spec.name)
	if not template then
		warn("[WorldEventSpawner] island template not in ReplicatedStorage: " .. spec.name)
		return nil, "нет модели " .. spec.name .. " в ReplicatedStorage"
	end

	-- Прошлый тестовый остров убираем: у островов 72 тысячи треугольников на штуку,
	-- и десяток накликанных подряд посадит клиент. Так же ведут себя кнопки катеров.
	if opts.test then
		for i = #islands, 1, -1 do
			local e = islands[i]
			if e.model:GetAttribute("TestSpawn") then
				e.model:Destroy()
				table.remove(islands, i)
			end
		end
	end

	local island = template:Clone()
	-- ⚠️ ИМЯ КЛОНА — ВСЕГДА ИЗ СПИСКА, А НЕ ИЗ ШАБЛОНА.
	-- Шаблон мог найтись по запасному имени (см. names выше), а весь остальной
	-- код ищет остров в Workspace ровно по name: население, сценарий, тэггер
	-- деревьев. Для островов без запасных имён это ничего не меняет.
	island.Name = spec.name
	-- Anchor the static geometry, but leave the Enemies folder mobile so the island's
	-- pirates/infected can still walk and be killed (IslandClearSystem needs them live).
	local enemies = island:FindFirstChild("Enemies")
	--[[ ВОССТАНОВЛЕНИЕ ИЗ СЕЙВА: зачищенный остров поднимаем БЕЗ гарнизона —
	     папку врагов сносим до того, как остров попадёт в мир, иначе
	     IslandClearSystem вооружит его заново, а игрок получит вторую зачистку
	     и вторую награду. Атрибут Cleared читают карта и заселение. ]]
	if opts.cleared then
		if enemies then enemies:Destroy(); enemies = nil end
		island:SetAttribute("Cleared", true)
	end
	if type(opts.attrs) == "table" then
		for k, v in pairs(opts.attrs) do pcall(function() island:SetAttribute(k, v) end) end
	end
	if opts.keepAlive then island:SetAttribute("KeepAlive", true) end
	if spec.story then island:SetAttribute("StoryIsland", true) end
	if spec.killScripts or spec.enableScripts then
		for _, d in ipairs(island:GetDescendants()) do
			if d:IsA("LuaSourceContainer") then
				if spec.killScripts and spec.killScripts[d.Name] then
					d:Destroy()
				elseif spec.enableScripts and spec.enableScripts[d.Name] and d:IsA("BaseScript") then
					d.Enabled = true
				end
			end
		end
	end
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") and not (enemies and d:IsDescendantOf(enemies)) then
			d.Anchored = true
		end
	end

	local dMin = opts.distMin or (opts.test and TEST_DIST_MIN or ISLAND_DIST_MIN)
	local dMax = opts.distMax or (opts.test and TEST_DIST_MAX or ISLAND_DIST_MAX)
	-- строго по курсу — и на кнопке «(тест)», и у сюжетного острова: искать его
	-- по всей полусфере после катсцены «вон она, земля» было бы издевательством
	local straight = opts.test or opts.straight or false
	if typeof(opts.cframe) == "CFrame" then
		-- сейв: ставим ровно туда, где остров стоял (пивот модели)
		island:PivotTo(opts.cframe)
	elseif spec.byBounds then
		local radius, dist, size = placeIslandByBounds(island, template, raft, dMin, dMax, straight)
		-- Диагностика: размер СУШИ (а не всей модели с плитой дна), куда встал и на
		-- какой высоте. Высота должна совпадать с той, что у шаблона в
		-- ReplicatedStorage, — по этой строке это видно сразу.
		local landCenter = landInfo(island)
		print(("[Остров] %s: суша %.0f×%.0f, радиус %.0f, до берега %.0f, центр %.0f, высота %.1f"):format(
			spec.name, size.X, size.Z, radius, dist - radius, dist, landCenter.Y))
	else
		island:PivotTo(pickSpawnCFrame(raft, template, dMin, dMax, straight))
	end
	-- вода шаблона → наша вода (остров крабов пришёл из плейса со своим океаном)
	if spec.waterLine and typeof(opts.cframe) ~= "CFrame" then
		local line, waterY = spec.waterLine(), workspace:GetAttribute("WaterY")
		if type(line) == "number" and type(waterY) == "number" then
			island:PivotTo(island:GetPivot() + Vector3.new(0, waterY - line, 0))
		end
	end
	-- ⚠️ ПИВОТЫ ДЕТАЛЕЙ ОБНУЛЯЕМ, НО ТОЛЬКО ПОСЛЕ ПОСТАНОВКИ.
	-- У импортированных сцен PivotOffset деталей приходит произвольным, и всё,
	-- что считает GetPivot() по отдельной детали (маркеры, точки построек,
	-- диагностика), получает смещённый ответ. Обнуление саму деталь НЕ двигает —
	-- меняется только точка отсчёта.
	-- Порядок важен: у модели без PrimaryPart пивот берётся от детей, и сделай мы
	-- это ДО PivotTo, остров уехал бы не туда.
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") and d.PivotOffset ~= CFrame.identity then
			d.PivotOffset = CFrame.identity
		end
	end

	if opts.test then island:SetAttribute("TestSpawn", true) end
	-- ⚠️ ПОМЕТКА ДЛЯ КАРТЫ. MapSystem узнаёт острова по папке Enemies, а у мирных
	-- островов (TropicIsland_SCENE) врагов нет — и на карте их не было. Атрибут
	-- говорит карте «это остров» независимо от гарнизона.
	island:SetAttribute("MapIsland", true)
	island.Parent = Workspace -- direct child of Workspace → IslandClearSystem's ChildAdded picks it up

	-- След острова — по СУШЕ, а не по пивоту и не по полному габариту: по нему
	-- ResourceSpawner решает, куда не ронять ресурсы, и отсечка считает, уплыл ли
	-- остров назад. С кривым пивотом импортированной сцены промахивалось первое,
	-- а с плитой дна 2048×2048 второе запрещало ресурсы на километр вокруг.
	local footCenter, footSize
	if spec.byBounds then
		footCenter, footSize = landInfo(island)
	else
		local cf, size = island:GetBoundingBox()
		footCenter, footSize = cf.Position, size
	end
	table.insert(islands, {
		model  = island,
		center = footCenter,
		radius = math.max(footSize.X, footSize.Z) * 0.5,
	})
	-- сюжетный поднялся — запоминаем: от этого зависит, можно ли уже давать
	-- случайные (см. STORY_GATE ниже)
	-- центр суши атрибутом: пивот FBX-сцены лежит в стороне от геометрии, а по
	-- центру суши меряют расстояние постройки, сейв и запрет на удаление
	island:SetAttribute("LandCenter", footCenter)
	island:SetAttribute("LandRadius", math.max(footSize.X, footSize.Z) * 0.5)
	if spec.story then storyRaised[spec.name] = true end
	publishIslandPositions()
	return island
end

-- ── ПАУЗА СЛУЧАЙНОГО СПАВНА ──
-- Момент, до которого таймер островов молчит. Просить паузу может кто угодно,
-- кому важно, чтобы рядом с его островом какое-то время не всплывало чужих:
-- сейчас это сценарий стартового острова (StartIsleStory).
local islandHoldUntil = 0

-- Продлить паузу. Именно ПРОДЛИТЬ, а не переустановить: две просьбы подряд не
-- должны укорачивать друг друга — берём ту, что дальше.
_G.HoldIslandSpawns = function(seconds)
	if type(seconds) ~= "number" or seconds <= 0 then return end
	islandHoldUntil = math.max(islandHoldUntil, os.clock() + seconds)
end

-- Кнопка «(тест)» в настройках. Возвращает (успех, причина) — как у катеров.
_G.SpawnIsland = function(opts)
	local raft = getRaft()
	if not raft then return false, "плот ещё не собран" end
	local island, why = spawnIsland(raft, opts)
	return island ~= nil, why, island
end

-- список поднятых островов для сейва (сюжетные не пишем: у них свой сценарий)
_G.ListMapIslands = function()
	local out = {}
	for _, e in ipairs(islands) do
		local m = e.model
		-- тестовый остров (админ-панель) в сейв идёт, только если игрок его освоил:
		-- постройка (KeepAlive), зачистка или отметка на карте. Иначе дом остаётся
		-- висеть над водой без острова
		local testOK = not m:GetAttribute("TestSpawn")
			or m:GetAttribute("KeepAlive") or m:GetAttribute("Cleared") or m:GetAttribute("MapSeen")
		-- сюжетные острова тоже в списке: без них после загрузки сценарий поднимал
		-- остров заново и повторял катсцену (сценарий принимает остров из сейва сам)
		if m.Parent and testOK then
			table.insert(out, e.model)
		end
	end
	return out
end

-- ─── Radiation cisterns ───
local cisterns = {} -- array of active radiation models

local function spawnRadiation(raft)
	local template = ReplicatedStorage:FindFirstChild(RAD_TEMPLATE)
	if not template then
		warn("[WorldEventSpawner] radiation template not in ReplicatedStorage: " .. RAD_TEMPLATE)
		return
	end
	local cistern = template:Clone()
	-- Anchor everything so we can drift it cleanly by CFrame (no physics fighting the move).
	for _, d in ipairs(cistern:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	cistern:PivotTo(pickSpawnCFrame(raft, template, RAD_DIST_MIN, RAD_DIST_MAX))
	cistern.Parent = Workspace
	table.insert(cisterns, cistern)
end

-- ─── Spawn loops ───
task.spawn(function() -- islands
	-- первый остров — в окне 2–3 мин; дальше штатный интервал
	task.wait(FIRST_ISLAND_MIN + math.random() * (FIRST_ISLAND_MAX - FIRST_ISLAND_MIN))
	while true do
		-- ⚠️ ПОКА ДЕРЖИТ ПАУЗА — НЕ СПАВНИМ ВООБЩЕ.
		-- Таймер живёт своей жизнью и о сюжете не знает: сценарий поднимал
		-- стартовый остров, а таймер в ту же минуту ронял рядом второй, случайный.
		-- Игрок видел два острова разом и не понимал, на какой ему велят сойти.
		-- Паузу просит тот, кому она нужна (_G.HoldIslandSpawns), — здесь мы
		-- только ждём. Спавн случится сразу, как пауза кончится: это и есть
		-- «не раньше чем через столько-то».
		if not storyRaised[STORY_GATE] then
			--[[ Сюжет ещё не дошёл до аванпаста — чужой земли на горизонте быть
			     не должно (см. STORY_GATE). Ждём дёшево: одна проверка таблицы
			     раз в пять секунд, и так только первые два дня. ]]
			task.wait(5)
		elseif os.clock() < islandHoldUntil then
			task.wait(1)
		else
			local raft = getRaft()
			-- ⚠️ ЛИМИТА НА ЧИСЛО ОСТРОВОВ НЕТ (владелец: «убери лимит вообще»).
			-- Захваченные и сюжетные живут вечно, временные позади плота сносит
			-- сторож ниже — переполнения не будет.
			if raft then
				spawnIsland(raft)
			end
			task.wait(ISLAND_INTERVAL_MIN + math.random() * (ISLAND_INTERVAL_MAX - ISLAND_INTERVAL_MIN))
		end
	end
end)

task.spawn(function() -- radiation cisterns
	task.wait(STARTUP_DELAY)
	while true do
		task.wait(RAD_INTERVAL_MIN + math.random() * (RAD_INTERVAL_MAX - RAD_INTERVAL_MIN))
		local raft = getRaft()
		if raft then spawnRadiation(raft) end
	end
end)

-- ─── Per-frame maintenance: drift cisterns, cull anything left behind ───
RunService.Heartbeat:Connect(function(dt)
	local raft = getRaft()
	if not raft then return end
	local center = getRaftCenter(raft)
	local front  = getRaftFront(raft)

	-- radiation: drift along the current, then cull when it's far from the raft
	if #cisterns > 0 then
		local step = RAD_DRIFT_DIR * (RAD_DRIFT_SPEED * dt) -- Y component is 0 → keeps its height
		for i = #cisterns, 1, -1 do
			local m = cisterns[i]
			if not m or not m.Parent then
				table.remove(cisterns, i)
			else
				m:PivotTo(m:GetPivot() + step)
				if flatDist(m:GetPivot().Position, center) > RAD_DESPAWN_DIST then
					m:Destroy()
					table.remove(cisterns, i)
				end
			end
		end
	end

	-- islands: remove those the raft has sailed past (behind + far), or any left way out of range
	local changed = false
	for i = #islands, 1, -1 do
		local e = islands[i]
		if not e.model.Parent then
			table.remove(islands, i)
			changed = true
		else
			local rel = Vector3.new(e.center.X - center.X, 0, e.center.Z - center.Z)
			local behind = rel:Dot(front) < 0
			-- ⚠️ ОСТРОВ С KeepAlive НЕ СНОСИМ.
			-- На сюжетном острове висит незакрытый квест: снести его, пока игрок
			-- до него не дошёл, значит оставить квест невыполнимым навсегда — плот
			-- назад не разворачивается. Флаг снимает тот, кто его поставил
			-- (StartIsleStory), когда цель засчитана.
			-- освобождённый игроком остров — его собственность на карте, не сносим
			if e.model:GetAttribute("KeepAlive") or e.model:GetAttribute("Cleared") then
				-- ничего не делаем: живёт, пока флаг не снимут
			elseif (behind and rel.Magnitude > ISLAND_DESPAWN_DIST) or rel.Magnitude > ISLAND_HARD_CULL then
				print(("[Остров] %s снесён: %s, %.0f студов от плота"):format(e.model.Name, behind and "позади" or "слишком далеко", rel.Magnitude))
				e.model:Destroy()
				table.remove(islands, i)
				changed = true
			end
		end
	end
	if changed then publishIslandPositions() end
end)
