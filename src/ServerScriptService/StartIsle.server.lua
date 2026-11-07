--[[
	СТАРТОВЫЙ ОСТРОВ — НАСЕЛЕНИЕ И ДОБЫЧА.

	Сам остров поднимает WorldEventSpawner по расписанию из StartIsleStory. Этот
	скрипт принимает уже вставшую модель и доводит её до играбельного вида:

	  • оборачивает дерево и шесть куртин бамбука в модели, которые понимает
	    топор (StoneAxe рубит МОДЕЛИ по имени, а из FBX они приходят голыми
	    мешами — ровно та же беда была на тропическом острове, см. TropicIsland);
	  • ставит корову на точку CowSpawner и сторожит её смерть, чтобы засчитать
	    квест охоты.

	⚠️ ЗВЕРЯ СТАВИТ ЧУЖОЙ СПАВНЕР (_G.SpawnIslandAnimals), А НЕ КОПИЯ ЗДЕСЬ.
	В постановке коровы три неочевидных требования подряд: риг собирается по
	АВТОРСКОЙ позе до любых перемещений, якорь вешается ТОЛЬКО на корень, и
	CanQuery деталям нужно вернуть руками — иначе конус топора зверя не находит.
	Вторая копия этого кода разъехалась бы с первой на первой же правке.
]]

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")

--[[ ⚠️ ЭТОТ СКРИПТ ВЕДЁТ УЖЕ ДВА ОСТРОВА, А НЕ ОДИН.
     Скальный остров устроен так же, как стартовый: дерево и корова, никаких
     пиратов и построек. Заводить под него второй такой же файл — значит
     развести две копии постановки коровы, а в ней три неочевидных требования
     подряд (авторская поза рига, якорь только на корень, CanQuery руками) —
     копии разъедутся на первой же правке.
     Имя в логах осталось «Стартовый остров»: печатать разное для двух островов
     не за чем, а искать по одному тегу удобнее. ]]
local ISLAND_NAMES = {
	StartIsle_SCENE = true,
	RockIsle_SCENE  = true,
}

-- Точка коровы. Первое имя — из набора острова (пустой невидимый парт, добавлен
-- в Studio руками), остальные — на случай, если её заведут как обычный маркер
-- Pt_*, как на других островах.
local COW_MARK_NAMES = { "CowSpawner", "Pt_Cow_1", "Pt_Cow" }

-- ⚠️ РАДИУС ВЫПАСА МЕНЬШЕ, ЧЕМ У ПИРАТСКОГО ЛАГЕРЯ.
-- В Defs.ANIMALS у коровы 16.5 студов — это под большой остров. Здесь суша ≈31
-- студ в поперечнике, и с тем радиусом корова уходила бы в бамбук и в воду.
local GRAZE_RADIUS = 12

-- ⚠️ ЗА УБИЙСТВО КОРОВЫ ЗАСЧИТЫВАЕМ БЕЗ ОГРАНИЧЕНИЯ ПО ДАЛЬНОСТИ.
-- У пиратов радиус 80 студов — там врагов много и надо понять, кто чей. Здесь
-- корова одна, она сюжетная, и второй не будет. Сначала стоял лимит в 200
-- студов: остров всплывает за 520–620 и подходит минуту с лишним, так что
-- выстрел с плота в первые полминуты не засчитывался НИКОМУ — а зверь уже мёртв,
-- и квест охоты становился невыполним до конца сессии. Игроки на плоту всё
-- равно все рядом; ошибиться адресатом тут почти невозможно, а цена ошибки —
-- сломанная цепочка.
local KILL_CREDIT_RANGE = math.huge

-- Порода по имени меша → имя модели-обёртки. «bamboo» стоит первым: у обеих
-- пород в имени есть «real», и общее слово не должно перехватывать частное.
local WRAP_SPECIES = {
	{ word = "bamboo",    model = "Bamboo" },
	{ word = "tree_real", model = "Tree" },
}

local function speciesFor(name)
	local n = name:lower()
	for _, s in ipairs(WRAP_SPECIES) do
		if n:find(s.word, 1, true) then return s.model end
	end
	return nil
end

-- Оборачиваем каждый ствол в модель нужного имени. Геометрия не двигается:
-- деталь просто меняет родителя, а дальше её штатно помечает тэггер StoneAxe.
local function wrapChoppables(island)
	local made = 0
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") then
			local species = speciesFor(d.Name)
			-- уже обёрнутое не трогаем: setup может пройти дважды
			local parentIsWrap = d.Parent and d.Parent:IsA("Model") and speciesFor(d.Parent.Name)
			if species and not parentIsWrap then
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

-- ⚠️ ТОЧКА КОРОВЫ ПЕРЕЖИВЁТ НЕ ВСЯКУЮ ПЕРЕСБОРКУ ОСТРОВА.
-- CowSpawner добавлен в модель РУКАМИ в Studio, генератор сцены его не создаёт.
-- Переимпортировали StartIsle_SCENE.fbx поверх старой модели — и точка исчезла
-- вместе с ней, о чём прямо предупреждает README набора. Оставлять из-за этого
-- остров без коровы нельзя: на ней держатся два квеста из трёх. Нет точки —
-- ставим свою в центре суши; корова там же и пасётся, просто не на тропе.
local function makeFallbackMarker(island)
	local center = typeof(_G.StartIsleLandCenter) == "function"
		and _G.StartIsleLandCenter(island)
		or island:GetPivot().Position

	local p = Instance.new("Part")
	p.Name = "CowSpawner_auto"
	p.Size = Vector3.new(1, 1, 1)
	p.Anchored = true
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	-- высота роли не играет: постановщик всё равно опускает зверя лучом на грунт
	p.Position = center
	p.Parent = island
	return p
end

local function findCowMarker(island)
	for _, name in ipairs(COW_MARK_NAMES) do
		local m = island:FindFirstChild(name, true)
		if m and m:IsA("BasePart") then return m end
	end
	warn(("[Стартовый остров] в модели нет точки коровы (искал %s) — ставлю в центр суши")
		:format(table.concat(COW_MARK_NAMES, ", ")))
	return makeFallbackMarker(island)
end

-- Ближайший игрок к туше. Возвращает nil, если рядом никого — тогда засчитывать
-- некому и мы честно об этом пишем, вместо того чтобы выдать квест наугад.
local function closestPlayer(pos)
	local best, bestD
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - pos).Magnitude
			if d <= KILL_CREDIT_RANGE and (not bestD or d < bestD) then
				best, bestD = plr, d
			end
		end
	end
	return best, bestD
end

-- ⚠️ СМЕРТЬ ЛОВИМ ПО HealthChanged, А НЕ ТОЛЬКО ПО Died.
-- У животных стейт-машина гуманоида выключена (EvaluateStateMachine = false —
-- зверя ведёт код, а не физика Roblox), и на такую сигнал Died приходит не
-- всегда. HealthChanged срабатывает от любого урона, поэтому он основной, а
-- Died оставлен вторым поводом. Защёлка не даёт засчитать квест дважды.
local function watchCowDeath(cow)
	local hum = cow:FindFirstChildWhichIsA("Humanoid")
	if not hum then return end

	local credited = false
	local function onDead()
		if credited then return end
		if hum.Health > 0 then return end

		local pos = (cow.PrimaryPart and cow.PrimaryPart.Position) or cow:GetPivot().Position
		local killer, dist = closestPlayer(pos)
		if not killer then
			-- ⚠️ ЗАЩЁЛКУ НЕ СТАВИМ: засчитывать было НЕКОМУ, а не «уже засчитано».
			-- Иначе единственный шанс сгорал бы впустую.
			warn("[Стартовый остров] корова убита, но в сервере нет ни одного игрока с персонажем")
			return
		end
		credited = true
		print(("[Стартовый остров] корову убил %s (%.0f студов)"):format(killer.Name, dist or -1))
		-- ⚠️ НЕ НАПРЯМУЮ В _G.OnQuestEvent, А ЧЕРЕЗ ОЧЕРЕДЬ СЦЕНАРИЯ.
		-- Квест охоты открывается только после схода на берег, а корову видно с
		-- воды — её вполне убивают из пушки ещё с плота. Прямое событие в этот
		-- момент QuestState молча выбрасывает (квест не выдан), второй коровы на
		-- острове нет, и цепочка вставала бы намертво. Очередь придержит зачёт до
		-- выдачи квеста (см. _G.StartIsleCredit).
		if typeof(_G.StartIsleCredit) == "function" then
			_G.StartIsleCredit(killer, "startisle_cow", "kill:Cow")
		elseif typeof(_G.OnQuestEvent) == "function" then
			pcall(_G.OnQuestEvent, killer, "kill:Cow", 1)
		end
	end

	hum.HealthChanged:Connect(function(hp)
		if hp <= 0 then onDead() end
	end)
	hum.Died:Connect(onDead)
	if hum.Health <= 0 then onDead() end
end

local function setup(island)
	if island:GetAttribute("StartIsleReady") then return end
	island:SetAttribute("StartIsleReady", true)

	local wrapped = wrapChoppables(island)

	local marker = findCowMarker(island)
	local placed = 0
	if marker then
		-- маркер — служебная точка, а не декорация: гасим и убираем из лучей
		marker.Transparency = 1
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.Anchored = true

		if typeof(_G.SpawnIslandAnimals) == "function" then
			placed = _G.SpawnIslandAnimals(island, { Cow_1 = marker }) or 0
		else
			warn("[Стартовый остров] _G.SpawnIslandAnimals не найден (PirateIsland не загрузился?) — коровы нет")
		end

		local animals = island:FindFirstChild("Animals")
		local cow = animals and animals:FindFirstChild("Cow_Cow_1")
		if cow then
			cow:SetAttribute("GrazeRadius", GRAZE_RADIUS)
			watchCowDeath(cow)
		else
			warn("[Стартовый остров] корова не встала — квест охоты будет невыполним")
		end
	end

	print(("[Стартовый остров] готов: обёрнуто под топор %d, коров поставлено %d")
		:format(wrapped, placed))
end

Workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and ISLAND_NAMES[child.Name] then
		task.defer(setup, child)
	end
end)

for _, child in ipairs(Workspace:GetChildren()) do
	if child:IsA("Model") and ISLAND_NAMES[child.Name] then
		task.defer(setup, child)
	end
end
