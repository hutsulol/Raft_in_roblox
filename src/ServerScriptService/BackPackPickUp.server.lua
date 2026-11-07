-- BackpackPickup.server.lua
-- Подбор рюкзака-туториала (модель Workspace.BackPack).
--
-- На самый крупный парт модели вешается ProximityPrompt: на ПК это кнопка «E»,
-- на телефоне — кнопка-прикосновение (нативное поведение промпта). По триггеру
-- игроку ставится атрибут HasBackpack (его читает InventoryUI — до подбора
-- инвентарь не открывается) и клиенту летит RemoteEvent BackpackPickup
-- (звук + уведомление + локальное скрытие модели — BackpackPickup.client.lua).
--
-- Подбор ПЕРСОНАЛЬНЫЙ: модель остаётся в мире для остальных игроков (каждый
-- подбирает свой рюкзак), у подобравшего она прячется на клиенте. Если модели
-- на карте нет вовсе (например, лобби) — атрибут выдаётся всем сразу, чтобы
-- гейт не заблокировал инвентарь там, где механика не нужна.
--
-- При подборе игроку ВЫДАЮТСЯ стартовые предметы: револьвер и факел из
-- ReplicatedStorage — свои экземпляры КАЖДОМУ, кто подобрал (в мультиплеере не
-- общие). Револьвер показывается той же анимацией, что и награда за квест.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local AssetFind         = require(ReplicatedStorage:WaitForChild("AssetFind"))

local MODEL_NAME = "BackPack"
local ATTR       = "HasBackpack"

--[[ ⚠️ РЮКЗАК НА ПЛОТУ ОДИН, И ВЕЩИ ИЗ НЕГО ВЫДАЮТСЯ ОДИН РАЗ.
     Гейт стоял на атрибуте ИГРОКА: подобрал — получил револьвер и факел. Атрибут
     живёт в сессии, а восстанавливается только из сейва, поэтому каждый зашедший
     друг (и любой, чей сейв не подтянулся) подбирал рюкзак заново и получал ещё
     один комплект. Пять «друзей» по очереди — пять револьверов из воздуха.
     Теперь «разобран ли рюкзак» — свойство САМОГО ПЛОТА, а не игрока: мировой
     атрибут, который переживает вход и выход любого из игроков.
     Гейт инвентаря при этом остаётся у каждого своим: рюкзак уже вскрыт — значит
     инвентарь открыт всем на этом плоту, иначе зашедший вторым не смог бы им
     пользоваться вообще. ]]
local WORLD_TAKEN = "BackpackTaken"

--[[ ⚠️ КОМПЛЕКТ — КАЖДОМУ ИГРОКУ ПО ОДНОМУ РАЗУ, А НЕ ОДИН НА ПЛОТ.
     Флаг «рюкзак разобран» на весь плот закрыл дубли, но вместе с ними оставил
     без оружия второго игрока: хост подобрал — друг получил пустоту. Теперь на
     плоту хранится СПИСОК тех, кто уже получил комплект (UserId через запятую),
     и он сохраняется вместе с плотом (RaftSaveSystem, backpackTakenBy). Повторный
     подбор, перезаход и загрузка сейва второй комплект не дают; новый игрок на
     этом плоту получает свой. ]]
local TAKEN_BY = "BackpackTakenBy"
local function hasTaken(userId)
	local list = Workspace:GetAttribute(TAKEN_BY)
	if type(list) ~= "string" then return false end
	for id in list:gmatch("%d+") do
		if tonumber(id) == userId then return true end
	end
	return false
end
local function markTaken(userId)
	local list = Workspace:GetAttribute(TAKEN_BY)
	list = (type(list) == "string" and list ~= "") and (list .. "," .. userId) or tostring(userId)
	Workspace:SetAttribute(TAKEN_BY, list)
end

local pickupEvent = ReplicatedStorage:FindFirstChild("BackpackPickup")
if not pickupEvent then
	pickupEvent = Instance.new("RemoteEvent")
	pickupEvent.Name = "BackpackPickup"
	pickupEvent.Parent = ReplicatedStorage
end

-- Модель рюкзака — РЕКУРСИВНЫЙ поиск сразу (FindFirstChild с true ищет в глубину).
-- Раньше тут стоял Workspace:WaitForChild(имя, 10): он ждёт ТОЛЬКО прямого ребёнка
-- Workspace, и когда рюкзак переехал внутрь другой модели (например, приварен в
-- составе плота), скрипт выжигал весь таймаут впустую — кнопка «E» появлялась с
-- опозданием в несколько секунд. Теперь модель находится мгновенно, где бы ни лежала.
local function findBackpackModel()
	for _ = 1, 40 do -- до ~10с на случай, если модель реплицируется с задержкой
		local m = Workspace:FindFirstChild(MODEL_NAME, true)
		if m then return m end
		task.wait(0.25)
	end
	return nil
end

-- Самый крупный парт модели — носитель промпта. Парт "BillboardGui" не
-- подходит: он прозрачный и качается вверх-вниз (Gui22Bob).
local function findPromptPart(model)
	if model:IsA("BasePart") then return model end
	local best, bestVolume = nil, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "BillboardGui" then
			local s = d.Size
			local v = s.X * s.Y * s.Z
			if v > bestVolume then
				best, bestVolume = d, v
			end
		end
	end
	return best
end

-- Тихая выдача (без звука/уведомления) — для карт без рюкзака.
local function grantSilently(player)
	if not player:GetAttribute(ATTR) then
		player:SetAttribute(ATTR, true)
	end
end

-- ── стартовые оружия, выдаваемые ПРИ ПОДБОРЕ рюкзака ──
-- Тулы лежат прямыми детьми ReplicatedStorage (перенесены из Studio). Имена ищем
-- списком: у части инструментов в плейсе разные написания. КАЖДЫЙ подобравший
-- получает СВОИ клоны (не общие).
--[[ ⚠️ В РЮКЗАКЕ ТОЛЬКО РЕВОЛЬВЕР И ФАКЕЛ — ПО ПРЯМОМУ УКАЗАНИЮ ВЛАДЕЛЬЦА.
     Раньше сюда же входил PirateGun, а ниже отдельной ручкой выдавалась бутылка
     для воды. Оба убраны.
     ⚠️ ПОСЛЕДСТВИЕ, О КОТОРОМ НАДО ЗНАТЬ: сосуд для воды больше НЕ приходит
     ниоткуда — бутылка выдавалась только здесь, рецепта крафта у неё нет.
     Пока сосуд не выдаётся другим способом, набрать воду будет нечем. ]]
local GUNS = { { "Revolver" }, { "Torch" } }

-- Что показать в анимации выдачи (RewardReveal). Ключ — первое имя из GUNS.
local REVEAL = {
	Revolver = {
		name = "РЕВОЛЬВЕР",
		rarity = "Редкое",
		icon = "rbxassetid://133241956272699",   -- та же иконка, что вешает WeaponIcons
		star = true,
	},
}

local function findGunTool(names)
	for _, nm in ipairs(names) do
		local t = AssetFind.find(nm)
		if t and t:IsA("Tool") then return t end
	end
	return nil
end

local function giveStarterGuns(player)
	for _, names in ipairs(GUNS) do
		local src = findGunTool(names)
		if src then
			local tool = src:Clone()
			if _G.GiveToolOrDrop then
				_G.GiveToolOrDrop(player, tool) -- в хотбар/инвентарь (или дроп, если места нет)
			else
				local bp = player:FindFirstChildOfClass("Backpack")
				if bp then tool.Parent = bp else tool:Destroy() end
			end

			--[[ ⚠️ ТА ЖЕ АНИМАЦИЯ, ЧТО У НАГРАДЫ ЗА КВЕСТ, А НЕ СВОЯ ПОХОЖАЯ.
			     Предмет из рюкзака игрок получает так же неожиданно, как награду,
			     и показывать это надо одинаково: иначе в игре заводятся два
			     «праздничных» окна, которые расходятся при первой же правке
			     одного из них. Событие RewardReveal для того и общее. ]]
			local reveal = REVEAL[names[1]]
			if reveal then
				local ev = ReplicatedStorage:FindFirstChild("RewardReveal")
				if ev then
					ev:FireClient(player, reveal)
				else
					warn("[BackpackPickup] события RewardReveal нет — анимацию выдачи не показать")
				end
			end
		else
			warn(("[BackpackPickup] Tool '%s' не найден прямым ребёнком ReplicatedStorage — не выдан")
				:format(names[1]))
		end
	end

	--[[ ⚠️ БУТЫЛКУ ЗДЕСЬ БОЛЬШЕ НЕ ВЫДАЁМ.
	     Вызов _G.GiveWaterBottle убран по указанию владельца: в рюкзаке остаются
	     только револьвер и факел. Сама система бутылки (WaterBottleSystem) на
	     месте и по-прежнему умеет её выдавать — если сосуд понадобится вернуть
	     или выдать иначе (крафт, награда), достаточно позвать ту же функцию. ]]

	if _G.SendInventory then _G.SendInventory(player) end -- обновить хотбар/инвентарь у клиента
end

-- ── крепление рюкзака к плоту: СВАРКА, БЕЗ ЯКОРЯ ──
-- Автор приварил рюкзак к плоту вручную в Studio — эту сварку уважаем и НЕ трогаем.
-- Якорить нельзя: заякоренный рюкзак, сваренный с плотом, останавливал ВСЮ сборку —
-- плот стоял на месте, а игрока сносило инерцией в воду. Скрипт лишь страхует:
--   • парты — «призраки» (Massless + без коллизий): не давят на буйность и не
--     толкают доски; промпту «Подобрать» коллизии не нужны (работает по дистанции);
--   • все парты модели свариваются с корнем (root), чтобы ничего не отвалилось;
--   • ДОБАВЛЯЕТСЯ страховочная сварка корня к PrimaryPart плота: если авторская
--     сварка держится за доску, которую rebuildRaft пересоздаст, страховка к
--     PrimaryPart (он пересборку переживает) не даст рюкзаку упасть;
--   • якоря снимаются ТОЛЬКО после того, как страховочная сварка встала.
local function secureBackpackOnRaft(model, root)
	local parts = {}
	local function ghost(p)
		p.Massless = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		parts[#parts + 1] = p
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then ghost(d) end
	end
	if model:IsA("BasePart") then ghost(model) end
	if root == nil or #parts == 0 then return end

	task.spawn(function()
		-- плот может ещё собираться при спавне — ждём его PrimaryPart
		local prim
		for _ = 1, 60 do
			local raft = Workspace:FindFirstChild("Raft")
			prim = raft and raft.PrimaryPart
			if prim then break end
			task.wait(0.5)
		end
		if not prim then return end -- плота нет (другая карта) — оставляем как авторски задано

		-- собрать рюкзак в одно целое вокруг корня (авторские сварки не трогаем)
		for _, p in ipairs(parts) do
			if p ~= root then
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = p
				w.Parent = root
			end
		end
		-- страховочная сварка к PrimaryPart плота
		local w = Instance.new("WeldConstraint")
		w.Name = "BackpackSafetyWeld"
		w.Part0 = root
		w.Part1 = prim
		w.Parent = root
		-- теперь плоту ничего не мешает плыть, а рюкзак держат сварки
		for _, p in ipairs(parts) do p.Anchored = false end
	end)
end

local model = findBackpackModel()
local promptPart = model and findPromptPart(model)

if promptPart == nil then
	for _, player in ipairs(Players:GetPlayers()) do
		grantSilently(player)
	end
	Players.PlayerAdded:Connect(grantSilently)
	return
end

-- ПРОМПТ — ПЕРВЫМ ДЕЛОМ, до любых манипуляций с физикой: так кнопка «E» попадает
-- в самый первый снапшот репликации и готова к взаимодействию прямо со старта
local prompt = Instance.new("ProximityPrompt")
prompt.Name = "BackpackPrompt"
prompt.ActionText = "Подобрать"
prompt.ObjectText = "Рюкзак"
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.MaxActivationDistance = 9
prompt.RequiresLineOfSight = false
prompt.HoldDuration = 0
prompt.Parent = promptPart

-- закрепить рюкзак: авторская сварка + страховочная сварка к PrimaryPart, без якорей
secureBackpackOnRaft(model, promptPart)

prompt.Triggered:Connect(function(player)
	--[[ Инвентарь открываем подобравшему в любом случае: даже если вещи уже
	     разобрал кто-то другой, рюкзак у него на плоту всё равно есть. ]]
	local firstHere = player:GetAttribute(ATTR) ~= true
	player:SetAttribute(ATTR, true)

	--[[ ⚠️ ВЕЩИ — ТОЛЬКО ПЕРВОМУ, И ПРОВЕРКА ИДЁТ ПО ПЛОТУ.
	     Второй заход того же игрока, вход друга, потерянный сейв — всё это
	     прежде давало новый комплект. Мировой флаг закрывает их разом. ]]
	if hasTaken(player.UserId) then
		if firstHere then pickupEvent:FireClient(player) end
		print(("[Рюкзак] %s: свой комплект на этом плоту уже получал — вещи не выдаём")
			:format(player.Name))
		return
	end
	markTaken(player.UserId)
	Workspace:SetAttribute(WORLD_TAKEN, true)   -- прежний флаг «рюкзак вскрыт» (читают сейв и клиент)

	giveStarterGuns(player) -- каждый игрок получает свои револьвер и факел, один раз
	pickupEvent:FireClient(player)
	print(("[Рюкзак] %s разобрал рюкзак — вещи выданы"):format(player.Name))
end)