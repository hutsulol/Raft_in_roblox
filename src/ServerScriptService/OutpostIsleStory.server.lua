--[[
	ОСТРОВ-АВАНПОСТ — СЦЕНАРИЙ.

	Второй сюжетный остров, через день после стартового. Ведёт всю сцену:

	  1. поднимает остров по курсу плота и шлёт клиентам катсцену
	     (OutpostIsleCutscene.client) — после неё игрок думает вслух и тихо
	     начинает играть музыка;
	  2. выдаёт «Зачистить остров» и считает убитых из гарнизона;
	  3. ДЕРЖИТ зачистку, пока не выжжено поле вируса: цепочка квестов между
	     этими двумя событиями успевает провести игрока через огнемёт;
	  4. когда поле выжжено — отпускает зачистку. Дальше штатно: баннер
	     «остров зачищен» (IslandClearSystem) и повстанцы (RebelIsland);
	  5. выводит к игроку одного повстанца, тот подходит и заводит разговор,
	     а вместе с разговором приходит последний квест — освободить ещё три
	     острова.

	⚠️ ЗАЧИСТКУ ДЕРЖИМ ФЛАГОМ НА ОСТРОВЕ, А НЕ СВОЕЙ КОПИЕЙ ПОДСЧЁТА.
	Живых врагов считает IslandClearSystem, и второй счётчик рядом с ним разошёлся
	бы с первым при первой же правке. Мы лишь ставим острову ClearHold и снимаем
	его, когда поле выжжено; решение «зачищен» остаётся за той системой.

	⚠️ ДЕНЬ ЖИВЁТ РОВНО ОДНУ СЕССИЮ СЕРВЕРА.
	ReplicatedStorage.DayCount создаётся со значением 1 при каждом старте и никуда
	не сохраняется — как и у стартового острова, это «третий день ЭТОГО сервера».
]]

local Lighting          = game:GetService("Lighting")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local FlameDefs = require(ReplicatedStorage:WaitForChild("FlamethrowerDefs"))

local LOG = "[Аванпост]"

local ISLAND_NAME = "OutpostIsle_SCENE"

-- ⚠️ ЧЕРЕЗ ДЕНЬ ПОСЛЕ СТАРТОВОГО, А НЕ «НА ТРЕТИЙ ДЕНЬ ВООБЩЕ».
-- Стартовый поднимается на второй день (STORY_DAY в StartIsleStory), этот —
-- следующим. Меняешь тот — меняй и этот, иначе два острова придут в один день.
local STORY_DAY      = 3
local STORY_FRACTION = 0.35   -- доля дня; чуть позже стартового, чтоб не в упор

-- Дальше стартового: остров крупнее и должен сперва побыть силуэтом.
local DIST_MIN, DIST_MAX = 620, 720

local FIRST_QUEST = "outpost_clear"
local LAST_QUEST  = "outpost_islands"
local BURN_QUEST  = "outpost_burn"

-- Катсцена идёт ~7 секунд, потом мысль. Квест поверх мысли — два окна разом.
local QUEST_DELAY = 14

--[[ ⚠️ КАТСЦЕНА ИГРАЕТ НЕ В МОМЕНТ ПОДЪЁМА, А КОГДА ОСТРОВ УЖЕ БЛИЗКО.
     Поднимается он далеко — так и задумано, сперва это силуэт на горизонте. Но
     показывать пролёт сразу нечего: камера улетала к пятнышку в семистах студах,
     и «остров побольше» приходилось принимать на веру. Ждём, пока плот подойдёт
     на эту дистанцию, и только тогда шлём сцену — тогда в кадре и правда остров.
     Квест идёт следом за ней, а не за подъёмом: до катсцены игрок про остров ещё
     не знает. ]]
local CUTSCENE_DIST = 420

-- Пауза чужим островам: короткая на подходе (обновляется каждый опрос, поэтому
-- сама рассосётся, если сцена не сыграет) и полдня после подъёма. Полдня — это
-- 190 секунд: день в DayNightCircle длится 380.
local HOLD_HALF_DAY = 190
local HOLD_RUNUP    = 30

local POLL = 1

-- Кому засчитывать убитого и сожжённое поле: ближе этого к событию — твоё.
local CREDIT_RANGE = 90

-- Красная трава на грядках. Имя то же, что на террасе и верфи.
local CROP_PREFIX = "Virus_crop_sm"

--[[ ⚠️ ПОДАРОК МЕХАНИКА: ПЕРВЫЕ ПОЛБАКА.
     Собранный огнемёт приходит ПУСТЫМ, а топливо в игре добывают отдельно — с
     катеров и из бочек. Отправить игрока жечь поле пустым баком значит поставить
     ему задачу, которую нечем выполнить, поэтому первую заправку дарит механик,
     он же объясняет, где брать дальше.
     Заливаем ВСЕГДА, как только огнемёт появился на руках, даже если игрок
     собрал его раньше срока, — иначе тот, кто опередил сценарий, остался бы без
     подарка и без объяснения. Отмечаем атрибутом на игроке: подарок один. ]]
local FUEL_GIFT     = 500          -- мл
local FUEL_DIALOG   = "MechanicFuelGift"
local ATTR_FUEL_GIFT = "OutpostFuelGiven"
-- ⚠️ ВТОРАЯ ЗАЩЁЛКА, ОТДЕЛЬНО ОТ ПОДАРКА.
-- Раньше выдача задания «Выжечь заразу» висела на той же отметке, что и
-- топливо: атрибут ставился ДО проверки острова, и собравший огнемёт до его
-- появления сжигал подарок вхолостую — квест не выдавался, а второй попытки
-- цикл уже не делал. Теперь топливо и задание отмечаются порознь.
local ATTR_BURN_OPEN = "OutpostBurnOpened"

-- ── встреча с повстанцем ──
local REBEL_MODEL   = "Rebel_Kai"   -- ⚠️ то же имя стоит в DialogueDefs.OutpostRebelTalk
local REBEL_DIALOG  = "OutpostRebelTalk"
local MEET_DELAY    = 9        -- после зачистки: дать доиграть баннеру и катсцене
local MEET_AHEAD    = 22       -- за сколько студов перед игроком он выходит
local MEET_STOP     = 6.5      -- на каком расстоянии останавливается и заговаривает
local MEET_SPEED    = 9
local MEET_TIMEOUT  = 25       -- не дошёл — заговаривает с места, а не молчит вечно
local MEET_NEAR     = 110      -- в каком радиусе от центра суши ищем, к кому выходить

-- Клиентам: «остров поднялся» (катсцена + музыка) и «зачищен» (музыку гасим).
local sceneEvent = ReplicatedStorage:FindFirstChild("OutpostIsleEvent")
if not sceneEvent then
	sceneEvent = Instance.new("RemoteEvent")
	sceneEvent.Name = "OutpostIsleEvent"
	sceneEvent.Parent = ReplicatedStorage
end

-- ⚠️ ЧЕТВЁРТАЯ КОПИЯ ЭТОЙ ФУНКЦИИ В ПРОЕКТЕ, И ЭТО НОРМА.
-- Общего модуля времени нет: cycleTime в DayNightCircle — файловая локальная, а
-- наружу отдаются только DayCount и Lighting.ClockTime. Ровно так же считают
-- долю дня StartIsleStory, WaveDirector и PiratePatrolBoat.
local function dayProgress()
	local t = Lighting.ClockTime
	if t >= 6 and t < 18 then return (t - 6) / 12 end
	return nil   -- ночь: доли дня не существует
end

-- Центр СУШИ: по нему целится камера катсцены. Функцию считает сценарий
-- стартового острова и отдаёт наружу — тайлы рельефа у обоих островов зовутся
-- одинаково (island_terrain_r*c*), и вторая копия разошлась бы с первой.
local function landCenter(island)
	if typeof(_G.StartIsleLandCenter) == "function" then
		local ok, pos = pcall(_G.StartIsleLandCenter, island)
		if ok and typeof(pos) == "Vector3" then return pos end
	end
	return island:GetPivot().Position
end

local islandModel = nil
local sceneStarted = false
local holdReleased = false
local cropTotal = 0
local metPlayer = false     -- встреча уже игралась
local armCutscene           -- объявлена ниже: её зовёт подъём острова
--[[ ⚠️ ВСТРЕЧА РАЗРЕШАЕТСЯ ФЛАГОМ, А ВЫХОДИТ ПОВСТАНЕЦ — ПО МЕСТУ.
     Это два разных вопроса, и раньше они были свалены в один. «Можно ли» решает
     сюжет: остров зачищен и поле выжжено. «Куда выйти» решает положение игрока:
     повстанец выходит НА ОСТРОВ, к тому, кто на нём стоит. Тестовая кнопка
     звала выход напрямую и обходила оба условия — повстанец вышел на плот
     посреди океана в первый день. Теперь кнопка лишь взводит флаг, а выход всё
     равно случится там, где ему место. ]]
local meetArmed = false

-- ── кому засчитать ──
local function nearestPlayer(pos, range)
	local best, bestDist
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - pos).Magnitude
			if d <= (range or CREDIT_RANGE) and (not bestDist or d < bestDist) then
				best, bestDist = plr, d
			end
		end
	end
	return best
end

local function credit(player, eventType, amount)
	if not (player and player.Parent) then return end
	if typeof(_G.OnQuestEvent) ~= "function" then return end
	pcall(_G.OnQuestEvent, player, eventType, amount or 1)
end

-- ── квесты ──
-- ⚠️ ОТКРЫВАЕМ КВЕСТ ЯВНО, А НЕ ЖДЁМ ЦЕПОЧКИ.
-- Первое звено и последнее не следуют за предыдущим квестом: одно выдаёт
-- появление острова, другое — разговор с повстанцем. Оба помечены gated, то есть
-- без этого вызова их не существует.
local function openQuest(player, questId)
	if not (player and player.Parent) then return end
	if typeof(_G.TrackQuest) ~= "function" then
		warn(LOG .. " _G.TrackQuest не найден — квест " .. questId .. " не выдан")
		return
	end
	-- ⚠️ ПРОЙДЕННОЕ ВТОРОЙ РАЗ НЕ ОТКРЫВАЕМ.
	-- Квесты помечены permanent: закрытые лежат в permanentlyCompleted и второй
	-- раз не закроются. Открой такой — и у игрока навсегда повиснет карточка,
	-- которую нечем закрыть. Ровно так же осторожничает стартовый остров.
	local state = typeof(_G.GetQuestState) == "function" and _G.GetQuestState(player) or nil
	if state and state.permanentlyCompleted and state.permanentlyCompleted[questId] then
		return
	end
	pcall(_G.TrackQuest, player, questId)
end

local function burnGoal()
	-- ⚠️ ЧИСЛО БЕРЁМ ИЗ КАТАЛОГА, А НЕ ДЕРЖИМ СВОЁ.
	-- Удержание зачистки должно сниматься ровно тогда, когда закрывается квест
	-- «Выжечь заразу». Две копии числа разъехались бы при первой же правке
	-- баланса, и остров либо зачищался раньше квеста, либо не зачищался вовсе.
	local catalog = _G.QuestCatalog
	local def = catalog and catalog.get and catalog.get(BURN_QUEST)
	local obj = def and def.objectives and def.objectives[1]
	return (obj and obj.goal) or 12
end

-- ── поле вируса ──
local function crops(island)
	local list = {}
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:sub(1, #CROP_PREFIX) == CROP_PREFIX
			and not d:GetAttribute("Burnt") then
			table.insert(list, d)
		end
	end
	return list
end

-- ── огнемёт и заправка ──
local function heldFlamethrower(player)
	local char = player.Character
	for _, where in ipairs({ char, player:FindFirstChildOfClass("Backpack") }) do
		if where then
			for _, t in ipairs(where:GetChildren()) do
				if t:IsA("Tool") and t.Name == FlameDefs.TOOL_NAME then return t end
			end
		end
	end
	return nil
end

--[[ ⚠️ ЛЬЁМ АТРИБУТОМ, А НЕ ЧЕРЕЗ _G.RefuelFlamethrower.
     Штатная заправка ЗАБИРАЕТ топливо у игрока — из канистры в руках или из
     бака на плоту. Здесь наоборот: механик даёт своё. Позови мы штатную, у
     игрока молча опустела бы канистра, а «подарок» оказался бы его же нефтью. ]]
local function giveFuel(player)
	local tool = heldFlamethrower(player)
	if not tool then return false end

	local cap  = tool:GetAttribute(FlameDefs.ATTR_CAP) or FlameDefs.CAPACITY
	local have = tool:GetAttribute(FlameDefs.ATTR_FUEL) or 0
	tool:SetAttribute(FlameDefs.ATTR_FUEL, math.min(cap, have + FUEL_GIFT))

	if typeof(_G.StartDialogue) == "function" then
		pcall(_G.StartDialogue, player, FUEL_DIALOG)
	end
	print((LOG .. " %s: механик залил %d мл (было %d)")
		:format(player.Name, FUEL_GIFT, math.floor(have)))
	return true
end

-- ── гарнизон ──
-- Смерть каждого — зачёт «Зачистить остров». Считаем по Humanoid.Died, а не по
-- исчезновению модели: труп остаётся лежать, и по исчезновению зачёт пришёл бы
-- через минуты, уже после того, как игрок ушёл с острова.
local watched = {}

local function watchEnemy(npc)
	if watched[npc] then return end
	local hum = npc:FindFirstChildWhichIsA("Humanoid", true)
	if not hum then return end
	watched[npc] = true
	hum.Died:Once(function()
		local root = npc:FindFirstChild("HumanoidRootPart", true)
		local pos = root and root.Position or npc:GetPivot().Position
		local killer = nearestPlayer(pos)
		--[[ ⚠️ ЗАЧЁТ НЕ ДОЛЖЕН ПРОПАДАТЬ ИЗ-ЗА ТОГО, ЧТО РЯДОМ НИКОГО.
		     Пират может свалиться с вышки, утонуть, сгореть от чужого огня или
		     умереть, пока игрок отбежал. Гарнизон при этом кончился, а зачёт
		     не прошёл — и квест повисает навсегда: убивать больше некого.
		     Шаг общий (shared в каталоге), поэтому засчитать его достаточно
		     кому угодно из компании: раздачу остальным сделает QuestState. ]]
		if not killer then
			killer = Players:GetPlayers()[1]
			if killer then
				warn(LOG .. " " .. npc.Name .. " убит вдали от игроков — зачёт отдан "
					.. killer.Name .. " (шаг общий, дойдёт до всех)")
			end
		end
		if killer then
			credit(killer, "killed:OutpostPirate", 1)
			print(LOG .. " " .. npc.Name .. " убит, зачёт " .. killer.Name)
		else
			-- Некому засчитать — не молчим: это ровно тот случай, когда квест
			-- потом «не закрывается сам по себе», и без строчки в логе искать
			-- причину пришлось бы наугад.
			warn(LOG .. " " .. npc.Name .. " убит, но рядом никого — зачёт некому")
		end
	end)
end

-- ⚠️ НА ПОПОЛНЕНИЕ ПАПКИ ПОДПИСЫВАЕМСЯ ОДИН РАЗ, А НЕ КАЖДЫЙ ПРОХОД.
-- Дозор зовёт эту функцию раз в секунду. Без защёлки каждый проход вешал бы ещё
-- одну подписку на ChildAdded, и к концу боя один убитый засчитывался бы
-- десятки раз — квест «убей двоих» закрылся бы от первого же трупа.
local hooked = {}

local function watchGarrison(island)
	local enemies = island:FindFirstChild("Enemies")
	if not enemies then return false end
	for _, npc in ipairs(enemies:GetChildren()) do
		if npc:IsA("Model") then watchEnemy(npc) end
	end
	if not hooked[enemies] then
		hooked[enemies] = true
		enemies.ChildAdded:Connect(function(npc)
			if npc:IsA("Model") then
				task.wait(0.2)   -- Humanoid попадает в модель не первым же кадром
				watchEnemy(npc)
			end
		end)
	end
	return true
end

-- ── встреча с повстанцем ──
local function findTemplate(name)
	for _, where in ipairs({ ReplicatedStorage, Workspace }) do
		local m = where:FindFirstChild(name)
		if m and m:IsA("Model") then return m end
	end
	-- вглубь ищем только вторым заходом: в Workspace лежат уже вышедшие
	-- повстанцы острова, и брать шаблоном живого человека нельзя
	local m = ReplicatedStorage:FindFirstChild(name, true)
	return (m and m:IsA("Model")) and m or nil
end

-- Земля под точкой. Возвращает nil, если под ней ничего нет: для выхода
-- повстанца это важнее самой высоты — см. spotFor.
local function groundAt(pos, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local hit = Workspace:Raycast(pos + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), params)
	return hit and hit.Position.Y or nil
end

--[[ ⚠️ ПЕРЕД ИГРОКОМ — НО ТОЛЬКО ЕСЛИ ТАМ ЗЕМЛЯ.
     «Двадцать студов по взгляду» звучит просто, пока игрок не смотрит в море:
     тогда повстанец выходит из воды в двух шагах от берега. Луч под точку
     отвечает, есть ли там опора; если нет — отходим от игрока В СТОРОНУ СУШИ,
     на неё-то он точно вышел. ]]
local function spotFor(hrp, island, ignore)
	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = (flat.Magnitude > 0.01) and flat.Unit or Vector3.new(0, 0, -1)

	local ahead = hrp.Position + flat * MEET_AHEAD
	local y = groundAt(ahead, ignore)
	if y then return Vector3.new(ahead.X, y, ahead.Z) end

	local center = landCenter(island)
	local toLand = Vector3.new(center.X - hrp.Position.X, 0, center.Z - hrp.Position.Z)
	toLand = (toLand.Magnitude > 1) and toLand.Unit or flat
	local inland = hrp.Position + toLand * MEET_AHEAD
	y = groundAt(inland, ignore) or hrp.Position.Y
	return Vector3.new(inland.X, y, inland.Z)
end

-- Один повстанец выходит перед игроком и подходит к нему. Ни боя, ни целей:
-- он свой, и вся его задача — дойти и заговорить.
local function meetPlayer(player, island)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local tpl = findTemplate(REBEL_MODEL)
	if not tpl then
		warn(LOG .. " модели «" .. REBEL_MODEL .. "» нет — встречу играть некому")
		return false
	end

	local m = tpl:Clone()
	m.Name = REBEL_MODEL
	--[[ ⚠️ В КОРЕНЬ Workspace, А НЕ ВНУТРЬ ОСТРОВА, И ЭТО ВАЖНО ДВАЖДЫ.
	     Портрет в окне диалога ищет модель ПРЯМЫМ ребёнком Workspace
	     (DialogueUI.npcPortrait) и внутрь острова не заглядывает — из папки он
	     говорил бы безликим кружком. А клиентский аниматор водит одиночек в
	     Workspace по атрибуту CrewAnim: без него встречный стоял бы столбом. ]]
	m:SetAttribute("CrewAnim", true)
	m:SetAttribute("Friendly", true)   -- свой: ни огнемёт, ни ИИ его не трогают

	-- родные скрипты модели глушим: позу считает клиент по атрибуту Clip
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BaseScript") then d.Disabled = true end
	end

	local spot = spotFor(hrp, island, { char, m })
	m.Parent = Workspace
	m:PivotTo(CFrame.lookAt(
		Vector3.new(spot.X, spot.Y + 3, spot.Z),
		Vector3.new(hrp.Position.X, spot.Y + 3, hrp.Position.Z)))

	local hum = m:FindFirstChildWhichIsA("Humanoid", true)
	local root = (hum and hum.RootPart) or m:FindFirstChild("HumanoidRootPart", true)
	if not (hum and root) then
		warn(LOG .. " у модели повстанца нет Humanoid — встреча отменена")
		m:Destroy()
		return false
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.WalkSpeed = MEET_SPEED

	local function setClip(name, once)
		if once then
			m:SetAttribute("ClipOnce", name)
			m:SetAttribute("ClipOnceT", Workspace:GetServerTimeNow())
		else
			m:SetAttribute("Clip", name)
			m:SetAttribute("ClipT", Workspace:GetServerTimeNow())
		end
	end

	task.spawn(function()
		-- окликнул и пошёл навстречу
		setClip("RebelHail", true)
		task.wait(0.9)
		setClip("RebelWalk")

		local t0 = os.clock()
		while m.Parent and hum.Health > 0 do
			local target = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not target then break end
			local gap = (target.Position - root.Position).Magnitude
			if gap <= MEET_STOP or os.clock() - t0 > MEET_TIMEOUT then break end
			hum:MoveTo(target.Position)
			task.wait(0.35)
		end

		-- дошёл: остановиться, повернуться к игроку и заговорить
		local target = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if target then
			hum:MoveTo(root.Position)
			local to = Vector3.new(target.Position.X - root.Position.X, 0,
				target.Position.Z - root.Position.Z)
			if to.Magnitude > 0.5 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + to.Unit)
			end
		end
		setClip("RebelTalk")

		if typeof(_G.StartDialogue) == "function" then
			pcall(_G.StartDialogue, player, REBEL_DIALOG)
		end
		-- Квест приходит вместе с разговором, как и во всей игре: цепочка квестов
		-- шлёт мысль и карточку одним пакетом. Ждать конца диалога нечем — сигнала
		-- «дочитал» у DialogueService нет вовсе.
		task.wait(1.5)
		openQuest(player, LAST_QUEST)

		-- дальше он просто стоит рядом: разговор окончен, но человек не исчезает
		task.wait(14)
		if m.Parent then setClip("RebelIdle") end
	end)

	return true
end

-- ⚠️ ЛУЧ ПОД НОГИ, А НЕ РАССТОЯНИЕ ДО ЦЕНТРА.
-- По расстоянию «на острове» оказывался и плот, подошедший к берегу вплотную, —
-- а повстанцу нужно выйти к человеку, который стоит на земле. Луч отвечает на
-- единственный честный вопрос: на чём игрок стоит.
local function standsOnIsland(player, island)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { island }
	local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -14, 0), params)
	return hit ~= nil
end

local function tryMeet(island)
	if metPlayer or not meetArmed then return end
	-- ⚠️ ВЫХОДИМ К ТОМУ, КТО СТОИТ НА ОСТРОВЕ, И НИ К КОМУ БОЛЬШЕ.
	-- Никого на берегу — просто ждём: повстанец не бегает по океану за плотом.
	local center = landCenter(island)
	local player = nearestPlayer(center, MEET_NEAR)
	if not (player and standsOnIsland(player, island)) then return end
	metPlayer = true
	print((LOG .. " повстанец выходит к %s"):format(player.Name))
	if not meetPlayer(player, island) then
		metPlayer = false   -- не вышло — попробуем на следующем проходе
	end
end

--[[ ── ОЖИДАНИЕ СБЛИЖЕНИЯ ──
     Центр плота спрашиваем у ShipCombat (_G.GetRaftCenter) — там он считается по
     всем деталям плота, а PrimaryPart у него гуляет по мере пристроек. Запасной
     путь через PrimaryPart оставлен на случай, если ShipCombat ещё не поднялся:
     без него сторож молчал бы вечно и катсцена не сыграла бы вовсе. ]]
local cutscenePlayed = false

function armCutscene(target)
	task.spawn(function()
		while islandModel and islandModel.Parent and not cutscenePlayed do
			local raft = Workspace:FindFirstChild("Raft")
			local center = (typeof(_G.GetRaftCenter) == "function" and _G.GetRaftCenter())
				or (raft and raft.PrimaryPart and raft.PrimaryPart.Position)
			if center then
				local flat = Vector3.new(center.X - target.X, 0, center.Z - target.Z)
				if flat.Magnitude <= CUTSCENE_DIST then
					cutscenePlayed = true
					print((LOG .. " плот подошёл на %.0f студов — играем катсцену")
						:format(flat.Magnitude))
					sceneEvent:FireAllClients("found", target)
					task.delay(QUEST_DELAY, function()
						for _, plr in ipairs(Players:GetPlayers()) do
							openQuest(plr, FIRST_QUEST)
						end
					end)
					return
				end
			end
			task.wait(1)
		end
	end)
end

-- ── подъём острова ──
-- ⚠️ ЗАЩЁЛКА ОДНА НА ОБА ВХОДА — РАСПИСАНИЕ И КНОПКУ В НАСТРОЙКАХ.
-- Ставим ДО подъёма: неудачная попытка не должна повторяться каждые две секунды.
local function raiseIsland(opts)
	if sceneStarted then return false, "сцена уже запускалась" end
	sceneStarted = true

	-- ⚠️ ПО КНОПКЕ ПОДНИМАЕМ БЛИЖЕ, ЧЕМ ПО РАСПИСАНИЮ.
	-- Штатные семьсот студов — это минуты полторы хода до того, как сыграет
	-- катсцена. Для проверки сцены столько ждать незачем, но и вплотную ставить
	-- нельзя: остров должен успеть подойти, иначе катсцена по сближению не
	-- проверяется вовсе.
	local dmin, dmax = DIST_MIN, DIST_MAX
	if opts and opts.test then dmin, dmax = CUTSCENE_DIST + 40, CUTSCENE_DIST + 80 end

	if typeof(_G.SpawnIsland) ~= "function" then
		warn(LOG .. " _G.SpawnIsland не найден — WorldEventSpawner не загрузился?")
		return false
	end
	local ok, why = _G.SpawnIsland({
		name = ISLAND_NAME,
		straight = true,
		distMin = dmin,
		distMax = dmax,
	})
	if not ok then
		warn(LOG .. " не поднялся: " .. tostring(why))
		return false
	end

	islandModel = Workspace:FindFirstChild(ISLAND_NAME)
	if not islandModel then
		warn(LOG .. " поднялся, но модели в Workspace нет — некуда целить катсцену")
		return false
	end

	islandModel:SetAttribute("KeepAlive", true)
	-- Держим зачистку: пока поле вируса не выжжено, «остров зачищен» — неправда.
	islandModel:SetAttribute("ClearHold", true)
	cropTotal = #crops(islandModel)

	if typeof(_G.HoldIslandSpawns) == "function" then
		_G.HoldIslandSpawns(HOLD_HALF_DAY)
	end

	-- ⚠️ ФЛАГ СЦЕНЫ ПОДНИМАЕМ, ТОЛЬКО КОГДА ОСТРОВ УЖЕ СТОИТ В МИРЕ.
	-- По нему меню квестов решает, показывать ли карточки этой сцены. Подними
	-- его раньше — и сервер, где остров не всплыл, всю сессию показывал бы
	-- задания про остров, которого нет.
	Workspace:SetAttribute("OutpostIsleScene", true)

	local target = landCenter(islandModel)
	print((LOG .. " поднят по курсу, центр суши %.0f %.0f %.0f, кустов вируса %d")
		:format(target.X, target.Y, target.Z, cropTotal))

	armCutscene(target)
	return true
end

--[[ ── ОСТРОВ ИЗ СЕЙВА ──
     Флаг OutpostIsleScene приезжает из сейва раньше самого острова. Сцена уже
     была — не поднимаем второй остров и не повторяем катсцену, а принимаем
     восстановленный: держим зачистку полем, пока оно не выжжено, и разрешаем
     встречу с повстанцем, если остров уже зачищен. Нет острова — поднимаем по
     расписанию, как обычно. ]]
-- сюжет пройден хотя бы у одного игрока (квест outpost_burn закрыт навсегда)
local function storyDone()
	if typeof(_G.GetQuestState) ~= "function" then return false end
	for _, plr in ipairs(Players:GetPlayers()) do
		local ok, st = pcall(_G.GetQuestState, plr)
		if ok and type(st) == "table" and st.permanentlyCompleted and st.permanentlyCompleted["outpost_burn"] then
			return true
		end
	end
	return false
end

local function adoptSavedIsland()
	if sceneStarted or Workspace:GetAttribute("OutpostIsleScene") ~= true then return false end
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
				print(LOG .. " остров из сейва не пришёл, но сюжет пройден — не поднимаем")
				return
			end
			warn(LOG .. " флаг сцены из сейва есть, а острова нет — поднимаем по расписанию")
			sceneStarted = false
			raiseIsland()
			return
		end
		islandModel = m
		cutscenePlayed = true
		m:SetAttribute("KeepAlive", true)
		if m:GetAttribute("Cleared") then
			holdReleased = true
			meetArmed = true
		else
			cropTotal = #crops(m)
			if cropTotal > 0 then m:SetAttribute("ClearHold", true) end
		end
		print(LOG .. " остров из сейва принят — катсцена не повторяется")
	end)
	return true
end

-- ── расписание ──
task.spawn(function()
	local dayValue = ReplicatedStorage:WaitForChild("DayCount", 30)
	if not dayValue then
		warn(LOG .. " нет ReplicatedStorage.DayCount — расписание не работает")
		return
	end

	while true do
		task.wait(2)
		if adoptSavedIsland() then continue end
		if sceneStarted then break end
		if storyDone() then
			sceneStarted = true
			print(LOG .. " сюжет уже пройден в этом сейве — остров по расписанию не поднимаем")
			break
		end
		local p = dayProgress()
		if p and dayValue.Value >= STORY_DAY then
			if typeof(_G.HoldIslandSpawns) == "function" then
				_G.HoldIslandSpawns(HOLD_RUNUP)
			end
			if p >= STORY_FRACTION then
				raiseIsland()
			end
		end
	end
end)

-- ── дозор по острову ──
task.spawn(function()
	while true do
		task.wait(POLL)
		local island = islandModel
		if island and island.Parent then
			watchGarrison(island)

			-- встреча разрешена, но игрок ещё не на берегу — ждём его здесь
			if meetArmed and not metPlayer then tryMeet(island) end


			if not holdReleased then
				local left = #crops(island)
				local burnt = math.max(0, cropTotal - left)
				if cropTotal > 0 and burnt >= burnGoal() then
					holdReleased = true
					island:SetAttribute("ClearHold", nil)
					print((LOG .. " поле выжжено (%d из %d) — зачистка разблокирована")
						:format(burnt, cropTotal))
				end
			end
		elseif island then
			islandModel = nil
			Workspace:SetAttribute("OutpostIsleScene", nil)
		end
	end
end)

--[[ ── ЗАПРАВКА ОТ МЕХАНИКА ──
     ⚠️ СЛЕДИМ ЗА ОГНЕМЁТОМ ВСЕГДА, А НЕ ТОЛЬКО ПОКА СТОИТ ОСТРОВ.
     Сперва проверка жила в дозоре по острову — и тот, кто собрал огнемёт раньше
     сцены, не получал ни топлива, ни объяснения, откуда его брать. А это ровно
     тот случай, ради которого подарок и задуман.
     Задание жечь при этом выдаём только при живом острове: без него жечь нечего.

     Крафт засчитываем здесь же. Если игрок собрал огнемёт до того, как открылся
     квест «Огнемёт», событие crafted:Flamethrower ушло в пустоту (QuestState
     принимает прогресс только по ВЫДАННОМУ квесту), и квест повис бы
     выполненным, но не закрытым. ]]
task.spawn(function()
	while true do
		task.wait(2)
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Parent and heldFlamethrower(plr) then
				if not plr:GetAttribute(ATTR_FUEL_GIFT) then
					plr:SetAttribute(ATTR_FUEL_GIFT, true)
					giveFuel(plr)
					credit(plr, "crafted:Flamethrower", 1)
				end
				-- Задание жечь — только при живом острове, и ЖДЁМ его столько, сколько
				-- нужно: огнемёт могли собрать за день-два до того, как остров всплывёт.
				if islandModel and islandModel.Parent and not plr:GetAttribute(ATTR_BURN_OPEN) then
					plr:SetAttribute(ATTR_BURN_OPEN, true)
					-- пауза, чтобы карточка квеста не легла поверх реплики механика
					task.delay(2, function()
						if plr.Parent then openQuest(plr, BURN_QUEST) end
					end)
				end
			end
		end
	end
end)

--[[ ── ПОМОЩЬ МЕХАНИКА С ОГНЕМЁТОМ ──
     ⚠️ БЕЗ ЭТОГО ЗАДАНИЕ «СКРАФТИ ОГНЕМЁТ» — ТУПИК.
     Рецепт (InventoryCrafting): 2 бревна, 3 МУСОРА и пластиковая канистра.
     Бревна приходят наградой за зачистку, канистра собирается из пластика с
     верёвкой, а мусор взять негде: своего источника у него нет, он выпадает
     только из бочек одним видом из семи. Игрок доходил до карточки «Скрафти
     огнемёт 0/1» и упирался в стену — собирать было не из чего, и никто даже
     не говорил, где искать.
     Поэтому в момент, когда задание открылось, вмешивается механик: объясняет
     сборку и добивает РОВНО НЕДОСТАЧУ. Собрал всё сам — подарка нет, остаётся
     объяснение.
     ⚠️ ЭТО ЕДИНСТВЕННЫЙ ИСТОЧНИК МУСОРА ПО СЮЖЕТУ. Раньше три мусора
     выдавались заранее, вместе с топором (MechanicIntro), — и приходили за
     несколько дней до того, как игрок узнавал, зачем они. Оттуда их убрали:
     если здесь перестать добивать недостачу, задание снова станет тупиком.
     Если механик ещё спит — сперва мысль «пора его растолкать», а помощь придёт
     сразу после пробуждения: спящий НПС ничего объяснять не может. ]]
local FLAMER_QUEST    = "outpost_flamer"
local HELP_DIALOG     = "MechanicFlamerHelp"   -- с подарком
local HINT_DIALOG     = "MechanicFlamerHint"   -- всё есть, только объяснение
local CAN_DIALOG      = "MechanicFlamerCan"    -- материалы есть, канистры нет
local WAKE_DIALOG     = "OutpostWakeMechanicThought"
local ATTR_HELP       = "OutpostFlamerHelped"
local ATTR_WAKE_HINT  = "OutpostFlamerWakeHint"
-- ⚠️ ЧИСЛА ТЕ ЖЕ, ЧТО В РЕЦЕПТЕ. Разъедутся — механик добьёт не то, и квест
-- снова встанет. Канистру не трогаем: она собирается из обычного пластика.
local FLAMER_MATS = {
	{ name = "Rubbish", need = 3 },
	{ name = "Log",     need = 2 },
}

-- ⚠️ ОДНОГО s.active МАЛО: ТАМ ЛЕЖАТ ВСЕ СЮЖЕТНЫЕ КВЕСТЫ СРАЗУ.
-- ensureStoryActiveEntries засевает записи всему сюжету при входе в игру, ещё до
-- того, как игрок о квесте узнал. Признак «квест ВЫДАН» у gated-квестов — это
-- s.unlocked (см. sceneQuestOpen/questVisible в QuestState). Без этой проверки
-- механик отдавал бы мусор и объяснял рецепт в первую минуту первого дня.
local function questActive(player, questId)
	if typeof(_G.GetQuestState) ~= "function" then return false end
	local st = _G.GetQuestState(player)
	if not (st and st.active and st.active[questId]) then return false end
	if (st.unlocked or {})[questId] ~= true then return false end
	if st.permanentlyCompleted and st.permanentlyCompleted[questId] then return false end
	if st.pendingRewards and st.pendingRewards[questId] then return false end
	return true
end

local function mechanicAwake()
	-- атрибут ставит EngineerSystem в момент подъёма (там же от него считается
	-- квест про водолаза); пока его нет — механик спит у ремонтного стола
	return Workspace:GetAttribute("EngineerWokeDay") ~= nil
end

-- ⚠️ КАНИСТРУ СЧИТАЕМ ОТДЕЛЬНО ОТ МАТЕРИАЛОВ.
-- Она не ресурс, а Tool (InventoryCrafting: craftType = "tool"), в инвентаре
-- ресурсов её нет и добить её через _G.AddResourceToInventory нельзя. Но без
-- неё огнемёт не собрать, и механик не должен говорить «у тебя всё есть».
local function hasCanister(player)
	for _, where in ipairs({ player.Character, player:FindFirstChildOfClass("Backpack") }) do
		if where then
			for _, t in ipairs(where:GetChildren()) do
				if t:IsA("Tool") and t.Name == "Plastic_canister" then return true end
			end
		end
	end
	return false
end

local function flamerHelp(player)
	local inv = typeof(_G.GetInventory) == "function" and _G.GetInventory(player) or nil
	local given = 0
	if inv and typeof(_G.AddResourceToInventory) == "function" then
		for _, m in ipairs(FLAMER_MATS) do
			local have = tonumber(inv[m.name]) or 0
			if have < m.need then
				_G.AddResourceToInventory(player, m.name, m.need - have)
				given += m.need - have
			end
		end
	end
	if _G.StartDialogue then
		--[[ ⚠️ КАНИСТРА ВАЖНЕЕ ПОДАРКА, И ПОРЯДОК ВЕТОК ТЕПЕРЬ ИМЕННО ТАКОЙ.
		     Раньше первой стояла ветка подарка, и это работало, пока три мусора
		     выдавал механик при знакомстве: недостачи обычно не было, и до
		     ветки про канистру дело доходило.
		     Мусор оттуда убрали — теперь недостача есть почти всегда, ветка
		     подарка забирала бы разговор себе, а про канистру игрок не услышал
		     бы ни слова: в тексте подарка её нет. И упирался бы в неё молча.
		     Поэтому сперва смотрим, есть ли канистра: без неё огнёмет не
		     собрать никакими материалами. Материалы при этом всё равно уже
		     добраны выше — подарок молчаливый, но не потерянный. ]]
		local key = HINT_DIALOG
		if not hasCanister(player) then
			key = CAN_DIALOG
		elseif given > 0 then
			key = HELP_DIALOG
		end
		_G.StartDialogue(player, key)
	end
	print((LOG .. " %s: механик помог с огнемётом (добрано %d)"):format(player.Name, given))
end

task.spawn(function()
	while true do
		task.wait(3)
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Parent and not plr:GetAttribute(ATTR_HELP) and questActive(plr, FLAMER_QUEST) then
				if mechanicAwake() then
					plr:SetAttribute(ATTR_HELP, true)
					-- пауза: задание только что легло на экран карточкой, поверх неё
					-- окно диалога читалось бы как два окна разом
					task.delay(4, function()
						if plr.Parent then flamerHelp(plr) end
					end)
				elseif not plr:GetAttribute(ATTR_WAKE_HINT) then
					plr:SetAttribute(ATTR_WAKE_HINT, true)
					task.delay(4, function()
						if plr.Parent and _G.StartDialogue then _G.StartDialogue(plr, WAKE_DIALOG) end
					end)
				end
			end
		end
	end
end)

-- Вошёл, когда остров уже стоит: катсцену не повторяем (она про момент
-- появления), но квест выдаём — иначе игрок видит остров и не понимает, зачем.
Players.PlayerAdded:Connect(function(player)
	task.delay(20, function()
		-- ⚠️ ТОЛЬКО ЕСЛИ КАТСЦЕНА УЖЕ СЫГРАЛА. Пока остров — точка на горизонте,
		-- задание «перебей гарнизон» вошедшему читается как издевательство.
		if cutscenePlayed and islandModel and islandModel.Parent and player.Parent then
			openQuest(player, FIRST_QUEST)
		end
	end)
end)

-- ── зачистка ──
--[[ ⚠️ ВСТАЁМ В ЦЕПОЧКУ, А НЕ ЗАМЕНЯЕМ ОБРАБОТЧИК.
     _G.OnIslandCleared слушают ещё карта и повстанцы. Голое присваивание
     выбросило бы чужой обработчик, и кто именно останется, решал бы порядок
     загрузки скриптов — а он в Roblox не определён. ]]
local prevCleared = _G.OnIslandCleared
_G.OnIslandCleared = function(island)
	if typeof(prevCleared) == "function" then
		local ok, err = pcall(prevCleared, island)
		if not ok then warn(LOG .. " предыдущий обработчик зачистки: " .. tostring(err)) end
	end
	if typeof(island) ~= "Instance" then return end

	if island == islandModel then
		-- свой остров: музыку гасим и разрешаем встречу. Пауза — чтобы повстанец
		-- вышел ПОСЛЕ баннера и катсцены зачистки, а не поверх них.
		sceneEvent:FireAllClients("cleared")
		task.delay(MEET_DELAY, function()
			meetArmed = true
			-- строка в логе не украшение: «повстанец вышел слишком рано» ищется
			-- именно по ней — видно, когда и после чего встреча стала возможна
			print(LOG .. " остров объявлен зачищенным — встреча разрешена")
			if islandModel and islandModel.Parent then tryMeet(islandModel) end
		end)
		return
	end

	-- ЧУЖОЙ остров — это уже задание повстанца «освободить архипелаг».
	-- Засчитываем всем, кто был рядом: остров берут вместе, и зачёт одному
	-- означал бы, что напарник до конца квеста не дойдёт никогда.
	local center = island:GetPivot().Position
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - center).Magnitude <= 600 then
			credit(plr, "cleared:Island", 1)
		end
	end
end

-- ТЕСТ: поднять сцену прямо сейчас, не дожидаясь третьего дня. Зовёт кнопка в
-- настройках (SettingsMenuActions, действие outpostNow).
_G.OutpostIsleNow = function()
	if sceneStarted then
		return false, "сцена уже запускалась в этой сессии"
	end
	return raiseIsland({ test = true })
end

--[[ ТЕСТ: промотать остров — снять гарнизон и поджечь поле.
     ⚠️ КНОПКА ДЕЛАЕТ РАБОТУ ИГРОКА, А НЕ ОБХОДИТ ПОРЯДОК СЦЕНЫ.
     Две прошлые версии обходили: первая выводила повстанца напрямую (он вышел
     на плот в первый день), вторая снимала удержание зачистки (он вышел, едва
     игрок ступил на берег, — до боя и до огня). И то и другое ломало ровно то,
     ради чего сцена написана: порядок.
     Здесь кнопка ничего не отменяет. Она убивает тех, кого игрок убил бы сам, и
     поджигает то, что он поджёг бы огнемётом; дальше всё идёт своим ходом —
     кусты догорают, удержание снимается по их числу, IslandClearSystem
     объявляет зачистку, и только тогда выходит повстанец. ]]
_G.OutpostMeetNow = function(player)
	if not (islandModel and islandModel.Parent) then
		return false, "остров ещё не поднят"
	end
	--[[ ⚠️ ПРОМОТКА РАБОТАЕТ, ТОЛЬКО ПОКА ТЫ САМ НА ОСТРОВЕ.
	     Нажатая с плота, она делала бой и пожар за версту от игрока: зачёты
	     квестам не проходили (их получает тот, кто рядом), и к берегу игрок
	     подходил с квестом «Перебей гарнизон 0/2» и уже вышедшим навстречу
	     повстанцем. Выглядит это как сломанный порядок, хотя порядок соблюдён —
	     просто всё случилось без него. Проще не пускать кнопку издалека. ]]
	if not (player and standsOnIsland(player, islandModel)) then
		return false, "сойди на остров — промотка считает зачёты по тому, кто рядом"
	end

	local killed = 0
	local enemies = islandModel:FindFirstChild("Enemies")
	if enemies then
		for _, npc in ipairs(enemies:GetChildren()) do
			local hum = npc:FindFirstChildWhichIsA("Humanoid", true)
			if hum and hum.Health > 0 then
				hum.Health = 0
				killed += 1
			end
		end
	end

	-- ⚠️ ПОДЖИГАЕМ ЧУЖИМ ВХОДОМ, А НЕ СВОИМ ПОДСЧЁТОМ СГОРЕВШЕГО.
	-- Пожар, зачёт квеста и исчезновение куста ведёт TerraceIsland. Сожги мы
	-- поле «своими руками», тест проверял бы не ту дорогу, по которой пойдёт
	-- игрок, — а именно её и надо проверять.
	local lit = 0
	local field = crops(islandModel)
	if #field > 0 and typeof(_G.TerraceIgniteAt) == "function" then
		local sum = Vector3.zero
		for _, c in ipairs(field) do sum += c.Position end
		lit = _G.TerraceIgniteAt(sum / #field, 90, player) or 0
	end

	return true, ("снято %d, подожжено кустов %d — дальше по сценарию")
		:format(killed, lit)
end

print(LOG .. " сценарий готов: подъём на " .. STORY_DAY .. "-й день, зачистка держится до огня")
