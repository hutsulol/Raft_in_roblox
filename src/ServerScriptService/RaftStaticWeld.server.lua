-- RaftStaticWeld.server.lua
-- СТРАХОВОЧНЫЙ ПРИВАР ДЕКОРА К ПЛОТУ.
--
-- BoatMovement снимает якорь со ВСЕХ деталей плота (иначе заякоренная деталь
-- в сборке замораживает плот целиком), но приваривает их не он — это делает
-- каждая система установки у себя. Объекты, расставленные в Studio руками
-- (тотем водолазов, ремонтная станция, декор), держались сварками, лежавшими
-- в самой модели плота. При замене модели плота эти сварки исчезли — и объекты
-- остались физическими телами, стоящими на палубе «сами по себе»: их сносит,
-- они проваливаются и уезжают.
--
-- Здесь мы один раз после старта находим всё, что лежит в плоту и НИ К ЧЕМУ не
-- прикреплено, и приваривем к PrimaryPart. Проверка идёт по физической сборке
-- (AssemblyRootPart), а не по наличию сварок, поэтому уже закреплённое любым
-- способом второй раз не трогаем.
--
-- НЕ привариваем:
--   • NPC (модели с Humanoid) — дайвер, механик, наёмники должны ходить;
--   • детали, которыми двигает Motor6D — створки дверей, анимированные части;
--   • всё с атрибутом NoRaftWeld — ручное исключение.

local Players = game:GetService("Players")

local LOG_TAG = "[RaftStaticWeld]"

local raft = workspace:WaitForChild("Raft")
local t0 = os.clock()
while not raft.PrimaryPart and os.clock() - t0 < 30 do task.wait(0.2) end
local primary = raft.PrimaryPart
if not primary then
	warn(LOG_TAG .. " у плота нет PrimaryPart — привар декора пропущен")
	return
end

-- Деталь ведёт Motor6D (створка двери и т.п.) — жёсткая сварка её заклинит.
local function drivenByMotor(part)
	for _, d in ipairs(raft:GetDescendants()) do
		if d:IsA("Motor6D") and (d.Part1 == part or d.Part0 == part) then
			return true
		end
	end
	return false
end

local function hasHumanoid(model)
	return model:IsA("Model") and model:FindFirstChildWhichIsA("Humanoid", true) ~= nil
end

-- Клетка пола? Их держим по особым правилам (см. ниже).
local FLOOR_NAMES = { Raft_part = true, Net_Part = true }
local function isFloorTile(child)
	return FLOOR_NAMES[child.Name] or child:GetAttribute("BuildType") == "raft"
end

-- У детали уже есть ПРЯМАЯ сварка с корнем плота?
local function hasDirectWeld(part)
	for _, d in ipairs(part:GetChildren()) do
		if d:IsA("WeldConstraint")
			and ((d.Part0 == primary and d.Part1 == part) or (d.Part1 == primary and d.Part0 == part)) then
			return true
		end
	end
	return false
end

local function weldChild(child)
	if child == primary then return 0 end
	if child:GetAttribute("NoRaftWeld") then return 0 end
	if hasHumanoid(child) then return 0 end

	local parts = {}
	if child:IsA("BasePart") then
		parts[1] = child
	else
		for _, d in ipairs(child:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(parts, d) end
		end
	end
	if #parts == 0 then return 0 end

	-- ═══ ПОЛ — ЗВЕЗДОЙ, А НЕ ЦЕПОЧКОЙ ═══
	-- Клетки пола, расставленные в Studio, могут быть сварены ДРУГ С ДРУГОМ, а
	-- к корню плота вести только через соседей. Тогда снос одной клетки топором
	-- рвёт цепочку, и всё, что держалось «дальше по ней», отваливается физически
	-- — игрок ломает одну доску и теряет полплота. Поэтому каждой клетке пола
	-- ПРИНУДИТЕЛЬНО добавляем прямую сварку с PrimaryPart: тогда любая клетка
	-- держится сама за корень и снос соседа ей безразличен.
	-- (Игрок строит именно так — weldToRaft в BuildingSystem варит к PrimaryPart.)
	local floor = isFloorTile(child)

	if not floor then
		-- Постройки: трогаем только те, что вообще ни к чему не прикреплены.
		local rootAsm = primary.AssemblyRootPart or primary
		for _, p in ipairs(parts) do
			if p.AssemblyRootPart == rootAsm then return 0 end
		end
	end

	local welded = 0
	for _, p in ipairs(parts) do
		-- ⚠️ Метку смотрим и НА ОТДЕЛЬНОЙ ДЕТАЛИ, не только на модели целиком.
		-- У лебёдки якоря рама обязана быть приварена, а груз на тросе — свободен;
		-- пропускать всю модель ради одной детали значило бы оставить раму
		-- болтаться. Раньше проверка была только на уровне ребёнка, и якорь
		-- приваривался к плоту через секунду после постановки — он переставал
		-- опускаться вовсе.
		if p:GetAttribute("NoRaftWeld") then
			-- деталь помечена как подвижная — не трогаем
		elseif not p.Anchored and not drivenByMotor(p) and not hasDirectWeld(p) then
			local w = Instance.new("WeldConstraint")
			w.Name = "RaftStaticWeld"
			w.Part0, w.Part1 = primary, p
			w.Parent = p
			welded += 1
		end
	end
	if welded > 0 then
		print(("%s %s к плоту: %s (деталей: %d)")
			:format(LOG_TAG, floor and "пол закреплён напрямую" or "приварено", child.Name, welded))
	end
	return welded
end

--[[ ⚠️ ПРИВАРКА ПО ТРЕБОВАНИЮ — ДЛЯ ЗАГРУЗКИ СЕЙВА.
     RaftSaveSystem переносит плот заякоренным и через 0.15 с отпускает якоря,
     а наша стартовая проверка идёт на третьей секунде. Между ними стол
     механика и тотем — свободные тела на плоту, который уже поплыл: их
     заваливало набок, и сварка потом фиксировала лежачую позу («после
     загрузки постройки перевёрнуты»). Загрузчик зовёт эту ручку в том же
     кадре, что снимает якоря, — физика между ними не успевает. ]]
_G.RaftStaticWeldNow = function(why)
	local total = 0
	for _, child in ipairs(raft:GetChildren()) do
		total += weldChild(child)
	end
	print(("%s приварка по требованию (%s): деталей %d"):format(LOG_TAG, tostring(why), total))
	return total
end

-- Ждём, пока физика соберёт сборки: сразу после старта AssemblyRootPart ещё
-- не разрешён, и проверка «уже прикреплено» давала бы ложные срабатывания.
task.spawn(function()
	task.wait(3)
	local total = 0
	for _, child in ipairs(raft:GetChildren()) do
		total += weldChild(child)
	end
	print(("%s стартовая проверка: приварено деталей %d"):format(LOG_TAG, total))

	-- Позже добавленные модели (загрузка сейва, скрипты) — с той же проверкой:
	-- если их приварила своя система установки, мы промолчим.
	raft.ChildAdded:Connect(function(child)
		task.delay(1, function()
			if child.Parent == raft then weldChild(child) end
		end)
	end)
end)

print(LOG_TAG .. " loaded")
