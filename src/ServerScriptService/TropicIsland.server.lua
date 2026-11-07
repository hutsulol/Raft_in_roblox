--[[
	ТРОПИЧЕСКИЙ ОСТРОВ — приёмка после спавна.

	Сам спавн живёт в WorldEventSpawner вместе с остальными островами: там уже есть
	дуга по курсу плота, дистанция «на горизонте», отсечка уплывших и публикация
	следа для ResourceSpawner. Заводить второй спавнер значило бы дублировать всё это.

	Здесь — то, что нужно ИМЕННО этому острову, по TROPIC_ISLAND_BRIEF.md:

	  • ГАРНИЗОН. 13 маркеров Pt_* внутри модели несут данные постов АТРИБУТАМИ
	    (тип пирата, оружие, клипы, сектор, патруль). Бриф прямо говорит: никто не
	    спавнит сам, момент выбирает остров, а разбор атрибутов делает
	    IslandGarrison.fromIsland(model). Модуля в этом проекте пока нет — он
	    остался в сборке острова, — поэтому вызов сделан НЕОБЯЗАТЕЛЬНЫМ: появится
	    модуль в ReplicatedStorage, гарнизон поедет сам, без правок здесь.

	  • РУДА. Узлы Ore_iron_* подхватывает MiningMechanic (там же список островов).
	    Ore_copper_* пока не трогаем: ресурса «медь» в игре нет вообще, и выдавать
	    за неё нечего.

	  • МАРКЕРЫ Pt_* — служебные точки, а не декорация: их надо спрятать и убрать из
	    физики, иначе игрок увидит на пляже дюжину кубов и будет об них спотыкаться.

	  • ДЕРЕВЬЯ. Система рубки (StoneAxe) работает с МОДЕЛЯМИ по имени породы:
	    «Palm Tree» / «Banana Tree». На этом острове деревья приехали отдельными
	    мешами внутри сцены, поэтому каждое оборачивается в модель нужного имени —
	    дальше штатный тэггер сам проставит Choppable и запас ударов, и рубка,
	    выпадение брёвен, семян и фруктов заработают без единой правки в StoneAxe.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local ISLAND_NAME   = "TropicIsland_SCENE"
local MARKER_PREFIX = "pt_"          -- сравнение идёт в нижнем регистре
local GARRISON_MODULE = "IslandGarrison"

local warnedNoGarrison = false

-- Маркеры постов: невидимы, без коллизии и без рейкастов. CanQuery = false важен
-- отдельно — иначе они ловили бы курсор стройки и клики по руде рядом.
local function hideMarkers(island)
	local n = 0
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:lower():sub(1, #MARKER_PREFIX) == MARKER_PREFIX then
			d.Transparency = 1
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = true
			n += 1
		end
	end
	return n
end

-- ── деревья ──
-- Порода определяется по имени меша. «tree» стоит последним: это общее слово, и
-- пальма с бананом должны опознаться раньше него.
local TREE_SPECIES = {
	{ word = "banana", model = "Banana Tree" },
	{ word = "palm",   model = "Palm Tree" },
	{ word = "tree",   model = "Palm Tree" },
}

local function speciesFor(name)
	local n = name:lower()
	for _, s in ipairs(TREE_SPECIES) do
		if n:find(s.word, 1, true) then return s.model end
	end
	return nil
end

-- Оборачиваем каждый ствол в модель нужного имени. Геометрия при этом не двигается:
-- деталь просто меняет родителя. Дальше её подхватывает штатный тэггер StoneAxe.
local function wrapTrees(island)
	local made = 0
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") then
			local species = speciesFor(d.Name)
			-- уже обёрнутое не трогаем: setup может пройти дважды
			local parentIsTree = d.Parent and d.Parent:IsA("Model") and speciesFor(d.Parent.Name)
			if species and not parentIsTree then
				local wrap = Instance.new("Model")
				wrap.Name = species
				wrap.Parent = d.Parent
				d.Parent = wrap
				wrap.PrimaryPart = d
				made += 1
			end
		end
	end
	return made
end

-- Гарнизон, если модуль подвезли. Ошибку внутри чужого модуля ловим: остров должен
-- встать в океан в любом случае, даже если гарнизон сломан.
local function spawnGarrison(island)
	local mod = ReplicatedStorage:FindFirstChild(GARRISON_MODULE)
	if not mod or not mod:IsA("ModuleScript") then
		if not warnedNoGarrison then
			warnedNoGarrison = true
			warn(("[Тропик] модуля %s нет в ReplicatedStorage — остров встал без гарнизона")
				:format(GARRISON_MODULE))
		end
		return false
	end
	local ok, garrison = pcall(require, mod)
	if not ok or type(garrison) ~= "table" or type(garrison.fromIsland) ~= "function" then
		warn(("[Тропик] %s не отдал fromIsland — гарнизон пропущен"):format(GARRISON_MODULE))
		return false
	end
	local spawned, err = pcall(garrison.fromIsland, island)
	if not spawned then
		warn("[Тропик] гарнизон упал: " .. tostring(err))
		return false
	end
	return true
end

local function setup(island)
	if island:GetAttribute("TropicReady") then return end
	island:SetAttribute("TropicReady", true)

	local markers = hideMarkers(island)
	local trees = wrapTrees(island)
	local garrison = spawnGarrison(island)

	local ore = 0
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:lower():sub(1, 4) == "ore_" then ore += 1 end
	end

	print(("[Тропик] остров готов: постов %d, деревьев %d, рудных узлов %d, гарнизон %s")
		:format(markers, trees, ore, garrison and "выставлен" or "нет"))

	if trees == 0 then
		-- Ноль почти наверняка значит, что деревья сварены в общий меш декорации
		-- (Scenery_*). Внутри сваренного меша отдельное дерево не найти и не срубить —
		-- лечится только в сборке острова: добавить породы в NEVER_MERGE и пересобрать.
		warn("[Тропик] отдельных деревьев не найдено — похоже, они сварены в Scenery_*; "
			.. "рубить нечего, пока их не выведут из склейки")
	end
end

Workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and child.Name == ISLAND_NAME then
		task.defer(setup, child)
	end
end)

for _, child in ipairs(Workspace:GetChildren()) do
	if child:IsA("Model") and child.Name == ISLAND_NAME then
		setup(child)
	end
end
