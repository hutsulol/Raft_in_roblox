local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- AssetPreload.client.lua
-- Lives in ReplicatedFirst, which runs BEFORE every other client script — its
-- yields happen during the default Roblox loading screen rather than after the
-- player spawns.
--
-- ДВА ЭШЕЛОНА:
--   1) СРАЗУ (пока висит загрузочный экран) — то, что игрок видит в первые
--      секунды: содержимое ПЛОТА, рюкзак-туториал, стадии мешка.
--   2) ФОНОМ во время игры, ПО ОЧЕРЕДИ с паузами — то, что понадобится позже:
--      иконки UI пушек (рулетка выпадает только ночью), модели построек,
--      шаблоны островов. Очередь именно последовательная: PreloadAsync на
--      большом пакете за раз даёт заметную просадку кадров, а по одному
--      пакету с паузой игрок ничего не замечает.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BG_PAUSE = 0.6 -- пауза между пакетами фоновой очереди

--===================== ЭШЕЛОН 1: загрузочный экран =====================

-- Иконки меню монолита дайвера — САМЫМ ПЕРВЫМ и в ОТДЕЛЬНОМ task.spawn, чтобы они
-- грузились параллельно, а не в хвосте общего списка ASSETS (после десятка текстур
-- мешка). Меню открывается уже в первую минуту, и раньше иконки всплывали, потому
-- что до конца очереди канал доходил не сразу. ID продублированы из
-- MonolithRepairUI (клиентский скрипт, require нельзя) — менять там → и здесь.
local MONOLITH_ICONS = {
	"rbxassetid://116178347748793", -- Дерево (Log)
	"rbxassetid://96691360298069",  -- Листва (Leaves)
	"rbxassetid://78760258555926",  -- Компост (Compost)
	"rbxassetid://96450657403376",  -- Камень (Stone)
	"rbxassetid://72890243946368",  -- Слиток (Iron_Ingot)
	"rbxassetid://132919988751848", -- Пластик (Plastic)
	"rbxassetid://82715612463476",  -- превью «Патроны»
	"rbxassetid://137747693080979", -- превью «Еда»
}
local ReplicatedFirst = game:GetService("ReplicatedFirst")

--[[ ⚠️ СВЯЗЬ С ЭКРАНОМ ЗАГРУЗКИ — ЧЕРЕЗ АТРИБУТЫ НА ReplicatedFirst.
     Раньше эти два скрипта не знали друг о друге вовсе: прогрев запускался в
     task.spawn и никем не ждался, а шторка гасла по трём условиям, ни одно из
     которых не про контент. Игрок выходил в мир на прозрачном плоту — меш, у
     которого не докачался MeshId, движок не рисует ВООБЩЕ.
     Почему атрибут, а не BindableEvent: порядок запуска двух LocalScript'ов
     движок не определяет. Атрибут — СОСТОЯНИЕ: экран сначала читает текущее
     значение и только потом ждёт изменения, поэтому сигнал, пришедший раньше
     подписки, не теряется. Событие в этом случае ушло бы в пустоту.
     Почему ReplicatedFirst: оба скрипта лежат прямо в нём, искать никого не
     надо, и новых файлов заводить не пришлось (Rojo не всегда доносит новые
     инстансы до уже подключённой сессии Studio).
     Кто читает: ReplicatedFirst/TeleportLoadingScreen.client.lua. ]]
local gateTotal, gateDone = 0, 0

local function gateAdd(n)
	gateTotal += n
	ReplicatedFirst:SetAttribute("WarmupTotal", gateTotal)
end

local function gateStep()
	gateDone += 1
	ReplicatedFirst:SetAttribute("WarmupDone", gateDone)
end

local function gateFinish(attr, label, t0)
	ReplicatedFirst:SetAttribute(attr, true)
	print(("[AssetPreload] %s: готово за %.1fс"):format(label, os.clock() - t0))
end

ReplicatedFirst:SetAttribute("WarmupTotal", 0)
ReplicatedFirst:SetAttribute("WarmupDone", 0)
ReplicatedFirst:SetAttribute("WarmupIconsDone", false)
ReplicatedFirst:SetAttribute("WarmupRaftDone", false)

--[[ ⚠️ ДУБЛИКАТЫ ID, И ИХ НЕ ИЗБЕЖАТЬ.
     Иконки HUD и кнопок лежат в LocalScript'ах StarterPlayerScripts, а мы — в
     ReplicatedFirst: require клиентского скрипта невозможен. Меняешь картинку
     там — поправь и здесь, иначе греться будет старая.
     Источники: UIManager (полоски и монеты), ShopButton, SettingsButton,
     MapButton, PickupHint, Quests/QuestEntryButton. ]]
local HUD_ICONS = {
	"rbxassetid://93617165412571",  -- монеты
	"rbxassetid://85208348940307",  -- сытость
	"rbxassetid://107900227969593", -- жажда
	"rbxassetid://96378076686911",  -- здоровье
	"rbxassetid://127337495800958", -- радиация
	"rbxassetid://107034803089809", -- воздух
	"rbxassetid://102918660786025", -- кнопка магазина
	"rbxassetid://79587250133011",  -- кнопка настроек
	"rbxassetid://140433394148738", -- карта: закрытая
	"rbxassetid://70444773611719",  -- карта: телефон
	"rbxassetid://116555452678480", -- карта: клавиатура
	"rbxassetid://89189791827999",  -- подсказка «E»
	"rbxassetid://119074861532109", -- кнопка квестов
	"rbxassetid://127581807351214", -- бейдж квестов
}

--[[ ⚠️ ИКОНКИ ИНВЕНТАРЯ НЕ ДУБЛИРУЕМ — ИХ ЗА СОТНЮ.
     Списки живут в InventoryUI (клиентский скрипт), скопировать их сюда значит
     обречь копию разъехаться на первой же замене арта. Поэтому берём КЛЮЧИ из
     модулей ReplicatedStorage, а id спрашиваем у самого инвентаря через
     _G.GetItemIcon. Он появляется позже нас — StarterPlayerScripts стартуют
     после ReplicatedFirst, — поэтому ждём его с коротким сроком и без него
     просто пропускаем пакет: у экрана загрузки всё равно свой потолок. ]]
local function inventoryIcons()
	local out, seen = {}, {}
	local deadline = os.clock() + 8
	while typeof(_G.GetItemIcon) ~= "function" and os.clock() < deadline do
		task.wait(0.1)
	end
	if typeof(_G.GetItemIcon) ~= "function" then
		warn("[AssetPreload] _G.GetItemIcon не появился — иконки инвентаря греть нечем")
		return out
	end

	local keys = {}
	local okRes, ResourceNames = pcall(function()
		return require(ReplicatedStorage:WaitForChild("ResourceNamesRu", 5))
	end)
	if okRes and type(ResourceNames) == "table" then
		for key in pairs(ResourceNames) do keys[#keys + 1] = key end
	end
	local okItems, ItemNames = pcall(function()
		return require(ReplicatedStorage:WaitForChild("ItemNamesRu", 5))
	end)
	if okItems and type(ItemNames) == "table" and type(ItemNames.TOOLS) == "table" then
		for key in pairs(ItemNames.TOOLS) do keys[#keys + 1] = key end
	end

	for _, key in ipairs(keys) do
		local ok, id = pcall(_G.GetItemIcon, key)
		if ok and type(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	return out
end

-- ПАКЕТ ИКОНОК: его ждёт экран загрузки. Всё мелкое, скачивается быстро, и
-- именно это игрок видит в первом же кадре после шторки.
task.spawn(function()
	local t0 = os.clock()
	local list = {}
	for _, id in ipairs(MONOLITH_ICONS) do list[#list + 1] = id end
	for _, id in ipairs(HUD_ICONS) do list[#list + 1] = id end

	local okTheme, UITheme = pcall(function()
		return require(ReplicatedStorage:WaitForChild("UITheme", 5))
	end)
	if okTheme and type(UITheme) == "table" and type(UITheme.Icons) == "table" then
		for _, id in pairs(UITheme.Icons) do
			if type(id) == "string" and id ~= "" then list[#list + 1] = id end
		end
	end

	for _, id in ipairs(inventoryIcons()) do list[#list + 1] = id end

	gateAdd(#list)
	pcall(function()
		ContentProvider:PreloadAsync(list, function() gateStep() end)
	end)
	--[[ ⚠️ СКАЧАТЬ МАЛО — НУЖНО ОДИН РАЗ НАРИСОВАТЬ. Иконки монолита и инвентаря
	     после PreloadAsync всё равно проявлялись на глазах: картинка попадает в
	     видеопамять, только когда её впервые рисуют. Рисуем все под шторкой
	     загрузки (ModelIcon.warmImages) — игрок их не видит, а к открытию меню
	     они уже готовы. ]]
	pcall(function()
		local mod = ReplicatedStorage:WaitForChild("ModelIcon", 5)
		if mod then
			local n = require(mod).warmImages(list)
			print(("[AssetPreload] иконки нарисованы скрыто (полка IconWarmShelf): %d"):format(n))
		end
	end)
	gateFinish("WarmupIconsDone", ("иконки (%d шт.)"):format(#list), t0)
end)

local ASSETS = {
	-- Sand Bag, sand-content stage textures.
	"rbxassetid://107012847180882",  -- 0 % (empty, shared with clay)
	"rbxassetid://87535824644391",   -- 10 % sand
	"rbxassetid://102984915310557",  -- 30 % sand
	"rbxassetid://132918131694676",  -- 50 % sand
	"rbxassetid://135545427179049",  -- 70 % sand
	"rbxassetid://76170913773356",   -- 100 % sand

	-- Sand Bag, clay-content stage textures.
	"rbxassetid://137121316772176",  -- 10 % clay
	"rbxassetid://94079996711573",   -- 30 % clay
	"rbxassetid://71260002598684",   -- 50 % clay
	"rbxassetid://85470636629483",   -- 70 % clay
	"rbxassetid://115968010442225",  -- 100 % clay

	-- Shared close-button art (used by QuestMenu + SandBagUI).
	"rbxassetid://76127527205295",
	-- (иконки монолита вынесены в отдельный параллельный спавн выше)
}

-- PreloadAsync is synchronous (yields), поэтому в фоне: иначе загрузочный экран
-- после телепорта растянулся бы на десяток скачиваний текстур.
task.spawn(function()
	pcall(function() ContentProvider:PreloadAsync(ASSETS) end)
end)

-- ждёт появления инстанса по имени (рекурсивно), не выжигая таймаут WaitForChild
local function awaitInstance(parent, name, seconds)
	local deadline = os.clock() + (seconds or 20)
	while os.clock() < deadline do
		local found = parent:FindFirstChild(name, true)
		if found then return found end
		task.wait(0.25)
	end
	return nil
end

-- Рюкзак-туториал: меш и текстуры должны быть тёплыми СО СТАРТА — иначе модель
-- «моргает» (мешпарт на миг всплывает без текстуры) и кажется, что «E» запаздывает.
task.spawn(function()
	pcall(function()
		local bp = awaitInstance(Workspace, "BackPack", 15)
		if bp then ContentProvider:PreloadAsync({ bp }) end
	end)
end)

--[[ ⚠️ СНАЧАЛА ШАБЛОНЫ ИЗ ХРАНИЛИЩА, ПОТОМ УЖЕ СОБРАННЫЙ ПЛОТ.
     Здесь стоял один PreloadAsync на workspace.Raft — и грел он НЕ ТОТ плот:
     сборка из сейва идёт на сервере ПОЗЖЕ, после сетевого чтения DataStore, а
     мы к этому моменту успевали пройтись по пустой палубе. Всё доклонированное
     после оставалось холодным, и игрок выходил на прозрачные доски: MeshPart с
     нескачанным мешем движок не рисует вовсе.
     У клона те же MeshId и TextureId, что у шаблона, поэтому шаблоны греем
     СРАЗУ, параллельно с ожиданием сервера — это чинит прозрачность даже когда
     сборка задержалась. Собранный плот догреваем вторым заходом, по отмашке
     workspace.RaftReady (её ставит RaftSaveSystem во всех исходах, включая
     аварийные). Оба шага отчитываются в общий счётчик прогресса. ]]
task.spawn(function()
	local t0 = os.clock()

	-- 1) шаблоны деталей плота: имена — те же, что клонирует RaftSaveSystem
	local tpls = {}
	local okFind, AssetFind = pcall(function()
		return require(ReplicatedStorage:WaitForChild("AssetFind", 10))
	end)
	if okFind and AssetFind then
		local function add(...)
			local t = AssetFind.wait(8, ...)
			if t then tpls[#tpls + 1] = t end
		end
		add("Raft_part")
		add("Wood_wall")
		add("beam")
		add("raft_wall", "Raft_wall", "wall_model_wood")
		add("raft_wall_arch", "Raft_wall_arch", "wall_model_wood_arch")
		add("raft_door", "Raft_door", "Door_Wood")
	end
	if #tpls > 0 then
		gateAdd(#tpls)
		pcall(function()
			ContentProvider:PreloadAsync(tpls, function() gateStep() end)
		end)
	end

	-- 2) укреплённая доска: меш и текстуру подменяют на каждый тайл уже в игре,
	--    ждать саму подмену нельзя, а сделать её мгновенной за два id — можно
	local okRe, Reinforce = pcall(function()
		return require(ReplicatedStorage:WaitForChild("RaftReinforce", 5))
	end)
	if okRe and type(Reinforce) == "table" then
		local ids = {}
		for _, key in ipairs({ "MESH", "TEXTURE" }) do
			local v = Reinforce[key]
			if type(v) == "string" and v ~= "" then ids[#ids + 1] = v end
		end
		if #ids > 0 then
			gateAdd(#ids)
			pcall(function()
				ContentProvider:PreloadAsync(ids, function() gateStep() end)
			end)
		end
	end

	-- 3) собранный плот — только после отмашки сервера, иначе греем пустую палубу
	local deadline = os.clock() + 14
	while not Workspace:GetAttribute("RaftReady") and os.clock() < deadline do
		task.wait(0.2)
	end
	local raft = Workspace:FindFirstChild("Raft")
	if raft then
		gateAdd(1)
		pcall(function()
			ContentProvider:PreloadAsync({ raft }, function() gateStep() end)
		end)
	end

	gateFinish("WarmupRaftDone", "плот", t0)
end)

-- ⚠️ ГРЯДКА: ГРЕЕМ ВСЕ ЕЁ ВИДЫ ЗАРАНЕЕ, А НЕ КОГДА ОНИ ПОНАДОБЯТСЯ.
-- Грядка не «перекрашивается», а МЕНЯЕТ МЕШ: сухая → политая, росток → всходы →
-- спелое, и у каждой культуры своя тройка (PlanterService раскладывает их в
-- ReplicatedStorage/PlanterBases и /Crops). Каждый такой меш игрок видит впервые
-- ровно в момент подмены — и на секунду получает серую болванку без текстуры
-- посреди действия: полил и смотришь, как грядка «догружается».
-- Прогреваем обе папки целиком: их немного, а платить за них лучше на загрузочном
-- экране, чем в кадре, где игрок ждёт отклика.
task.spawn(function()
	pcall(function()
		for _, folderName in ipairs({ "PlanterBases", "Crops" }) do
			local folder = ReplicatedStorage:FindFirstChild(folderName)
				or awaitInstance(ReplicatedStorage, folderName, 20)
			if folder then ContentProvider:PreloadAsync({ folder }) end
		end
		-- сам шаблон грядки: его ставят из рюкзака, и первый экземпляр иначе
		-- всплывает без текстуры прямо под курсором
		-- по имени, а не по месту: модели разложены по папкам (см. AssetFind)
		local tpl = ReplicatedStorage:FindFirstChild("Raft_planter")
			or ReplicatedStorage:FindFirstChild("Raft_planter", true)
		if tpl then ContentProvider:PreloadAsync({ tpl }) end
		print("[AssetPreload] грядки прогреты: базы, культуры, шаблон")
	end)
end)

--===================== ЭШЕЛОН 2: фоновая очередь =====================

-- job = { label, get() -> список инстансов/строк, draw = рисовать ли скрыто }
local jobs = {}
-- draw (необязательный) — функция, возвращающая МОДЕЛИ, которые после скачивания
-- надо ещё и нарисовать скрыто. Отдельно от get: качаем мы не модель целиком, а
-- только её визуальные части (см. пакет работников ниже).
local function addJob(label, get, draw)
	jobs[#jobs + 1] = { label = label, get = get, draw = draw }
end

--[[ СКАЧАТЬ — ЕЩЁ НЕ ЗНАЧИТ ГОТОВО. PreloadAsync кладёт ассет в память, но в
     ВИДЕОПАМЯТЬ меш и текстура попадают только когда их впервые нарисовали.
     Для иконок это уже решено полкой IconWarmShelf (ModelIcon.warmImages/warm):
     кадр рисуется скрыто — под шторкой загрузки в полный размер, после неё
     уголком в пару пикселей под кнопкой меню Roblox. Моделям нужно ровно то же,
     поэтому гоним их через ту же полку, а не изобретаем вторую. ]]
local function drawHidden(items)
	local mod = ReplicatedStorage:FindFirstChild("ModelIcon")
	if not mod then return 0 end
	local okReq, MI = pcall(require, mod)
	if not okReq or type(MI) ~= "table" then return 0 end
	local drawn, images = 0, {}
	for _, it in ipairs(items) do
		if typeof(it) == "Instance" and it:IsA("Model") then
			if pcall(MI.warm, it, it:GetAttribute("WarmCopies")) then drawn += 1 end
		elseif type(it) == "string" and it ~= "" then
			images[#images + 1] = it
		end
	end
	if #images > 0 then
		local okImg, cnt = pcall(MI.warmImages, images)
		if okImg and type(cnt) == "number" then drawn += cnt end
	end
	return drawn
end

-- 1) Иконки UI пушек: коллекция, рулетка наград (появляется ТОЛЬКО ночью, к
--    этому моменту всё уже должно быть в кэше), рамки редкости и звёзды.
addJob("иконки пушек", function()
	local mod = ReplicatedStorage:FindFirstChild("WeaponCollectionCatalog")
	if not mod then return nil end
	local ok, Catalog = pcall(require, mod)
	if not ok or type(Catalog) ~= "table" then return nil end
	local list = {}
	local function push(v) if type(v) == "string" and v ~= "" then list[#list + 1] = v end end
	push(Catalog.STAR_FULL)
	push(Catalog.STAR_HALF)
	for _, v in pairs(Catalog.RARITY_BG or {}) do push(v) end -- фоны редкости
	for _, w in ipairs(Catalog.Weapons or {}) do
		if type(w) == "table" then push(w.icon) end
	end
	return list
end)

--[[ 2) РАБОТНИКИ ПОСТРОЕК — ТОТ ЖЕ СЛУЧАЙ, ЧТО И ИКОНКИ, ТОЛЬКО ЗАМЕТНЕЕ.
     Фермер и рыбак появляются не на старте, а В СЕКУНДУ, когда игрок поставил
     здание: до неё их меши, текстуры и костюм никто не качал. На слабом канале
     работник выходит в мир ПУСТЫМ МЕСТОМ — MeshPart с нескачанным мешем движок
     не рисует вовсе, — и дальше проявляется по частям прямо на глазах.
     Поэтому качаем их заранее фоном и тут же рисуем скрыто на полке иконок.
     Почему фоном, а не на загрузочном экране: до первой постройки проходят
     минуты, а шторка и так висит около десяти секунд — платить ею за то, что
     понадобится нескоро, незачем.
     Выжившие сюда же: SurvivorsUI их только СКАЧИВАЕТ (PreloadAsync без
     отрисовки), а назначенный в здание капитан встаёт на место работника той же
     моделью — значит, ему нужен тот же прогрев. ]]
local workerModels = nil   -- считаем один раз: список нужен и качалке, и рисовалке
local function buildingWorkers()
	if workerModels then return workerModels end
	local list, seen = {}, {}
	local function push(inst)
		if typeof(inst) == "Instance" and inst:IsA("Model") and not seen[inst] then
			seen[inst] = true
			list[#list + 1] = inst
		end
	end

	-- ФЕРМЕР: имя шаблона — в RaftFarmConfig, сам он лежит не в корне хранилища,
	-- поэтому ищем через AssetFind (как это делает сама ферма).
	local okCfg, FarmCfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("RaftFarmConfig", 5))
	end)
	local okFind, AssetFind = pcall(function()
		return require(ReplicatedStorage:WaitForChild("AssetFind", 5))
	end)
	if okFind and AssetFind then
		local name = (okCfg and type(FarmCfg) == "table" and FarmCfg.FARMER) or "Farmer"
		push(AssetFind.find(name))
	end

	-- РЫБАК: имя шаблона — в FishingConfig, шаблон лежит прямо в ReplicatedStorage
	-- (RaftFishing берёт его тем же именем).
	local okFish, FishCfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("FishingConfig", 5))
	end)
	if okFish and type(FishCfg) == "table" then
		push(ReplicatedStorage:FindFirstChild(FishCfg.TemplateName or "Fisherman_R6"))
	end

	-- ВЫЖИВШИЕ: модели стоят в Workspace (портретная сцена), оттуда же клонируется
	-- работник при назначении капитана в здание.
	local okDefs, Defs = pcall(function()
		return require(ReplicatedStorage:WaitForChild("SurvivorDefs", 5))
	end)
	if okDefs and type(Defs) == "table" and type(Defs.CATALOG) == "table" then
		for _, def in pairs(Defs.CATALOG) do
			local okM, m = pcall(Defs.find, def.model)
			if okM then push(m) end
		end
	end

	workerModels = list
	return list
end

--[[ ⚠️ КАЧАЕМ НЕ МОДЕЛЬ ЦЕЛИКОМ, А ЕЁ ВИДИМЫЕ ЧАСТИ.
     PreloadAsync на Model берёт ВСЕ ссылки внутри, включая Sound. Недоступный
     звук (в Studio их полный Output: «User is not authorized to access Asset»)
     движок ретраит долго и всё это время держит занятым канал загрузки — ровно
     та беда, из-за которой выше отказались греть острова, и ровно та, от
     которой работники и становились невидимыми. Нам нужны меш, текстура и
     костюм — их и перечисляем поимённо. ]]
-- CharacterMesh здесь не для красоты: у R6 тело задаётся именно им, и без него
-- прогрелась бы одежда, а сам работник остался бы «болванкой».
local VISUAL = { "MeshPart", "SpecialMesh", "CharacterMesh", "Decal", "Texture",
	"SurfaceAppearance", "Shirt", "Pants", "ShirtGraphic" }

--[[ 3) ПОСТРОЙКИ-ПОДАРКИ И ЗДАНИЯ ПЛОТА: рыбацкое место, ферма, дом фермера,
     таверна. Их 3D-иконка нужна внезапно — в окне торговца (карточка подарка)
     и в хотбаре, когда тул выдан, — и новая рамка ViewportFrame рисовала модель
     на глазах пару секунд. Качаем и рисуем скрыто заранее, по ДВА готовых кадра:
     после «Забрать бесплатно» модель видна сразу и в окне, и в слоте хотбара. ]]
local BUILDING_ICONS = { "Raft_fishing_spot", "Raft_farm_block", "Raft_farmer_hut", "IslandHall" }
local buildingModels = nil
local function buildingTemplates()
	if buildingModels then return buildingModels end
	local okFind, AssetFind = pcall(function()
		return require(ReplicatedStorage:WaitForChild("AssetFind", 5))
	end)
	local list = {}
	for _, name in ipairs(BUILDING_ICONS) do
		local m = okFind and AssetFind and AssetFind.find(name)
		if typeof(m) == "Instance" and m:IsA("Model") then
			m:SetAttribute("WarmCopies", 2)   -- drawHidden → ModelIcon.warm(m, 2)
			list[#list + 1] = m
		end
	end
	buildingModels = list
	return list
end

addJob("постройки плота", function()
	local out = {}
	for _, m in ipairs(buildingTemplates()) do
		for _, d in ipairs(m:GetDescendants()) do
			for _, cls in ipairs(VISUAL) do
				if d:IsA(cls) then
					out[#out + 1] = d
					break
				end
			end
		end
	end
	return out
end, buildingTemplates)

addJob("работники построек", function()
	local out = {}
	for _, m in ipairs(buildingWorkers()) do
		for _, d in ipairs(m:GetDescendants()) do
			for _, cls in ipairs(VISUAL) do
				if d:IsA(cls) then
					out[#out + 1] = d
					break
				end
			end
		end
	end
	return out
end, buildingWorkers)

-- (иконки монолита переехали в ЭШЕЛОН 1 выше — загружаются на загрузочном экране,
--  гарантированно тёплые к первому открытию меню)

-- ⚠️ МОДЕЛИ ПОСТРОЕК И ОСТРОВА В ФОНЕ НЕ ПРЕЛОАДИМ — только мелкие иконки выше.
-- PreloadAsync на модель с мешами, где часть
-- ассетов недоступна (в Studio — «doesn't have access permission», в проде — чужие
-- ассеты), ДОЛГО ретраит каждую ссылку и забивает канал загрузки контента. Пока он
-- занят островом, меши рабочих фермы и иконки, грузящиеся в этот момент, не успевают
-- прогрузиться и висят НЕВИДИМЫМИ. Острова далеко и приближаются минутами — движок
-- сам подтянет их текстуры по мере входа в render distance, прелоад тут только вредит.

task.spawn(function()
	-- ждём, пока игрок реально войдёт в мир: во время загрузки канал занят
	-- первым эшелоном, и лезть туда с тяжёлыми островами нельзя
	local player = Players.LocalPlayer
	local deadline = os.clock() + 30
	while not (player and player.Character) and os.clock() < deadline do
		task.wait(0.5)
	end
	task.wait(3) -- даём миру устаканиться после спавна

	local warmed = 0
	for _, job in ipairs(jobs) do
		local ok, items = pcall(job.get)
		if ok and type(items) == "table" and #items > 0 then
			pcall(function() ContentProvider:PreloadAsync(items) end)
			warmed += #items
			if job.draw then
				local okD, models = pcall(job.draw)
				local drawn = (okD and type(models) == "table") and drawHidden(models) or 0
				print(("[AssetPreload] %s: скачано частей %d, нарисовано скрыто %d")
					:format(job.label, #items, drawn))
			end
		end
		task.wait(BG_PAUSE) -- пауза между пакетами — против просадок кадров
	end
	print(("[AssetPreload] фоновая прогрузка завершена, пакетов: %d, элементов: %d")
		:format(#jobs, warmed))
end)
