--[[
	СЮЖЕТ ТОРГОВЦА — как игра постепенно открывает жителей и постройки.

	  День 3, ~70% дня: приплывает торговец. Речь «вижу тебя впервые» → лавка с
	    одним товаром — ПОДАРОК, рыбацкое место (одно на плот).
	    → квест «Подарок торговца»: поставь рыбацкое место.
	  Место встало → каждому игроку на плоту случайный житель (пока только Роза),
	    попап «Новый персонаж!», мысль «мой первый житель», у всех открывается
	    «Команда» → квест «Первый житель»: назначь его рыбаком (подсказки —
	    TeamQuestHint.client).
	  Рыбак назначен → торговец уплывает, мысль «наш первый житель рыбачит».
	  Следующий день, ~70%: торговец с ФЕРМОЙ (2 участка + домик, только ресурсы).
	    Не купили — приплывает с фермой каждый день, пока не купят.
	    Купили → квест «Своя ферма»; места мало — мысль «расширь плот».
	    Домик встал → мысль «работать некому… где взять рабочего?».
	  День после покупки фермы, ~70%: торговец с ТАВЕРНОЙ. Не купили — каждый день.
	    Купили → квест «Таверна». Встала → мысль про жителей; сюжет закончен.

	Визитами правит этот файл (MerchantShop: _G.MerchantStoryActive отключает
	старое расписание, _G.MerchantStoryOffers даёт ассортимент визита,
	_G.MerchantStoryOnBuy сообщает о покупке). События построек приходят через
	_G.MerchantStoryEvent(name, player) из FishingSpotPlace / FarmBlockPlace /
	SurvivorService. Речь торговца перед лавкой — Workspace.MerchantTalk
	(MerchantYachtClient). Этап хранится в СЕЙВЕ ПЛОТА (RaftSaveSystem: extras.
	merchantStory), как номер дня: новая игра — сюжет с начала, продолжение
	забега — с того же этапа.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local D = require(ReplicatedStorage:WaitForChild("SurvivorDefs"))
local LOG = "[Сюжет торговца]"

local FIRST_DAY = 3          -- первый визит
local VISIT_AT = 0.70        -- доля светлого дня (6:00…18:00) — вечер
local STAY_GIFT = 900        -- подарок: торговец ждёт, пока рыбак не начнёт работать
local STAY_SALE = 300        -- ферма / таверна

_G.MerchantStoryActive = true


-- этапы: intro → fishing → fisher → farm → tavern → done (+ флаги построек)
local st = { stage = "intro", nextDay = FIRST_DAY, farmBuilt = false, tavernBuilt = false }
local loaded = false

-- сохраняет сейв плота (RaftSaveSystem берёт _G.MerchantStoryExport при автосейве)
local function save() end

local function day()
	local v = ReplicatedStorage:FindFirstChild("DayCount")
	return v and v.Value or 1
end

local function everyone(fn)
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(fn, p) end
end
local function thought(key)
	everyone(function(p) if typeof(_G.StartDialogue) == "function" then _G.StartDialogue(p, key) end end)
end
local function quest(id, title)
	everyone(function(p)
		if typeof(_G.TrackQuest) == "function" then
			local ok, res = pcall(_G.TrackQuest, p, id)
			if not (ok and res) then warn(("%s квест %s не встал на трекер у %s: %s"):format(LOG, id, p.Name, tostring(res))) end
		end
		if typeof(_G.NotifyPlayer) == "function" then
			_G.NotifyPlayer(p, { type = "info", icon = "📜", title = "Новый квест: " .. title, body = "Смотри трекер слева" })
		end
	end)
end

-- пустой тул «поставь на плот» (как выдача из настроек)
local function giveTool(player, name)
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.CanBeDropped = false
	tool:SetAttribute("PreviewModel", name)
	local handle = Instance.new("Part")
	handle.Name = "Handle"; handle.Size = Vector3.one; handle.Transparency = 1
	handle.CanCollide = false; handle.Massless = true; handle.Parent = tool
	if typeof(_G.GiveToolOrDrop) == "function" then _G.GiveToolOrDrop(player, tool)
	else tool.Parent = player:FindFirstChildOfClass("Backpack") end
	return true
end

-- ═══ товар визита (MerchantShop.pickOffers) ═══
local visitNo = 0
local OFFERS = {
	fishing = {
		key = "MerchantFishingGift",
		offer = { id = "story_fishing", name = "Рыбацкое место", desc = "Подарок торговца. Рыбак ловит рыбу и продаёт улов",
			rarity = "rare", category = "rare", price = 0, stock = 1, model = "Raft_fishing_spot", showcase = true,
			isGift = true,   -- окно торговца: большая карточка «Подарок торговца» (GiftCard)
			give = function(p) return giveTool(p, "Raft_fishing_spot") end,
			canBuy = function() return st.stage == "intro", "Подарок уже забрали" end },
	},
	farm = {
		key = "MerchantFarmOffer",
		offer = { id = "story_farm", name = "Ферма", desc = "Два участка земли и домик фермера",
			rarity = "epic", category = "rare", price = 0, stock = 1, model = "Raft_farmer_hut", showcase = true,
			costs = { { "Compost", 24 }, { "Log", 48 }, { "Leaves", 12 } },
			give = function(p)
				if typeof(_G.GiveFarmBlock) ~= "function" or typeof(_G.GiveFarmerHut) ~= "function" then return false end
				return _G.GiveFarmBlock(p) and _G.GiveFarmBlock(p) and _G.GiveFarmerHut(p)
			end,
			canBuy = function() return st.stage == "farm", "Ферму уже купили" end },
	},
	tavern = {
		key = "MerchantTavernOffer",
		offer = { id = "story_tavern", name = "Таверна", desc = "Мастера у алтаря собирают новых жителей",
			rarity = "legendary", category = "rare", price = 0, stock = 1, model = "IslandHall", showcase = true,
			give = function(p) return typeof(_G.GiveIslandHall) == "function" and _G.GiveIslandHall(p) end,
			canBuy = function() return st.stage == "tavern", "Таверну уже купили" end },
	},
}
local function visitKind()
	if st.stage == "intro" or st.stage == "fishing" or st.stage == "fisher_wait" or st.stage == "fisher" then return "fishing" end
	if st.stage == "farm" then return "farm" end
	if st.stage == "tavern" then return "tavern" end
	return nil
end
local visitOffered = nil   -- с чем торговец приплыл В ЭТОТ визит ("fishing"/"farm"/"tavern")
_G.MerchantStoryOffers = function()
	local kind = visitKind()
	local o = kind and OFFERS[kind]
	visitOffered = o and kind or nil
	visitNo += 1
	workspace:SetAttribute("MerchantTalk", o and o.key or nil)
	workspace:SetAttribute("MerchantTalkVisit", visitNo)
	return o and { o.offer } or {}
end

-- ═══ свободное место под ферму: 2 участка + домик = 12 клеток пола ═══
local function freeTiles()
	local raft = workspace:FindFirstChild("Raft")
	if not (raft and raft.PrimaryPart) then return 0 end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { raft.PrimaryPart }
	local n = 0
	for _, child in ipairs(raft:GetChildren()) do
		if child.Name == "Raft_part" or child:GetAttribute("BuildType") == "raft" then
			local cf, size = child:GetBoundingBox()
			local box = CFrame.new(cf.Position + Vector3.new(0, size.Y * 0.5 + 2, 0))
			local busy = false
			for _, part in ipairs(workspace:GetPartBoundsInBox(box, Vector3.new(6, 3, 6), params)) do
				local top = part
				while top and top.Parent ~= raft do top = top.Parent end
				if top and top ~= child and top.Name ~= "Raft_part" and top:GetAttribute("BuildType") ~= "raft"
					and not top:FindFirstChildWhichIsA("Humanoid", true) then
					busy = true
					break
				end
			end
			if not busy then n += 1 end
		end
	end
	return n
end

-- ═══ покупки ═══
_G.MerchantStoryOnBuy = function(player, offer)
	if offer.id == "story_fishing" and st.stage == "intro" then
		st.stage = "fishing"; save()
		print(LOG .. " подарок забрал " .. player.Name)
		quest("story_fishing_place", "Подарок торговца")
	elseif offer.id == "story_farm" and st.stage == "farm" then
		st.stage = "tavern"; st.nextDay = day() + 1; save()
		print(LOG .. " ферму купил " .. player.Name .. ", таверна — на день " .. st.nextDay)
		task.wait(1)
		local free = freeTiles()
		if free < 12 then
			thought("RaftTooSmallThought")
			everyone(function(p)
				if typeof(_G.NotifyPlayer) == "function" then
					_G.NotifyPlayer(p, { type = "warn", icon = "warn", title = "Мало места для фермы",
						body = ("Свободных клеток %d из 12 — расширь плот молотком"):format(free) })
				end
			end)
			task.wait(10)
		else
			thought("FarmBoughtThought")
		end
		quest("story_farm_build", "Своя ферма")
		task.wait(8)
		if typeof(_G.MerchantDepart) == "function" then _G.MerchantDepart() end
	elseif offer.id == "story_tavern" and st.stage == "tavern" then
		st.stage = "tavern_build"; save()
		print(LOG .. " таверну купил " .. player.Name)
		quest("story_tavern_build", "Таверна")
		task.wait(8)
		if typeof(_G.MerchantDepart) == "function" then _G.MerchantDepart() end
	end
end

-- первый житель всегда Рыбак — «друг торговца» (SurvivorDefs.fisherman)
local function pickResident()
	return D.CATALOG.fisherman and "fisherman" or "rose"
end

-- ═══ «Забрать награду» в диалоге торговца: житель-рыбак ═══
local residentClaimed = {}   -- [UserId] = true: забрал жителя-рыбака (за сервер)

--[[ ⚠️ СЦЕНА «НУЖЕН ЖИТЕЛЬ» — ЧЕРЕЗ ОДНУ ДВЕРЬ. Её запускают четыре места
     (установка станции, вход игрока, загрузка сейва, повтор раз в 30 с), и два
     запуска могли прийти с разницей в пару секунд: игрок быстро прокликал первый,
     забрал жителя — и тут же получал ту же речь заново. Теперь: забрал — больше
     никогда; показывали меньше 25 с назад — не повторяем. ]]
local needsShownAt = {}   -- [UserId] = os.clock() последнего показа
local function showNeedsResident(p)
	-- ⚠️ ПО ЭТАПУ СЮЖЕТА, А НЕ ПО ОТКРЫТОЙ «КОМАНДЕ»: у игрока с капитанами
	-- аккаунта «Команда» открыта сразу, а рыбака от торговца он ещё не получал —
	-- по старой проверке сцена не показывалась бы, и сюжет вставал
	local storyGaveResident = ({ fisher = true, farm = true, tavern = true, tavern_build = true, done = true })[st.stage]
	if residentClaimed[p.UserId] or storyGaveResident then return end
	if needsShownAt[p.UserId] and os.clock() - needsShownAt[p.UserId] < 25 then return end
	if typeof(_G.StartDialogue) ~= "function" then return end
	needsShownAt[p.UserId] = os.clock()
	_G.StartDialogue(p, "FishingSpotNeedsResident")
end

--[[ ⚠️ СЦЕНУ «НУЖЕН ЖИТЕЛЬ» ПОВТОРЯЕМ, ПОКА ЖИТЕЛЯ НЕ ЗАБРАЛИ. Окно диалога одно, и
     катсцена острова или мысль в ту же секунду затирала её — игрок оставался без
     кнопки «Забрать награду», без жителя и без «Команды». Раз в 30 с всем, кто
     ещё не забрал, — снова. ]]
task.spawn(function()
	while true do
		task.wait(30)
		if st.stage == "fisher_wait" or st.stage == "fisher" then
			for _, p in ipairs(Players:GetPlayers()) do
				showNeedsResident(p)
			end
		end
	end
end)

_G.OnDialogueClaim = function(player, key, claim)
	if key ~= "FishingSpotNeedsResident" or claim ~= "resident" then return false, "не та награда" end
	-- «fishing» тоже: сцену видели, станция стоит, а этап мог не успеть сдвинуться
	if st.stage ~= "fishing" and st.stage ~= "fisher_wait" and st.stage ~= "fisher" then
		return false, "этап сюжета " .. tostring(st.stage)
	end
	local def = pickResident()
	player:SetAttribute("TeamUnlocked", true)
	if typeof(_G.GrantSurvivor) == "function" then
		local ok, why = _G.GrantSurvivor(player, def)
		if not ok then
			-- уже в команде (старое сохранение): попап «Новый персонаж!» всё равно играем
			print(LOG, player.Name, "житель уже есть:", why)
			local ev = ReplicatedStorage:FindFirstChild("SurvivorUnlocked")
			if ev then ev:FireClient(player, def) end
		end
	end
	if st.stage == "fishing" or st.stage == "fisher_wait" then st.stage = "fisher"; save() end
	residentClaimed[player.UserId] = true
	print(LOG .. " " .. player.Name .. " забрал жителя " .. def)
	task.spawn(function()
		task.wait(6)   -- попап «Новый персонаж!» доиграл
		if player.Parent and typeof(_G.StartDialogue) == "function" then _G.StartDialogue(player, "FirstResidentThought") end
		task.wait(7)
		if player.Parent then
			local ok, res = pcall(_G.TrackQuest, player, "story_assign_fisher")
			if not (ok and res) then warn(LOG .. " квест story_assign_fisher не встал на трекер: " .. tostring(res)) end
			if typeof(_G.NotifyPlayer) == "function" then
				_G.NotifyPlayer(player, { type = "info", icon = "📜", title = "Новый квест: Первый житель", body = "Открой «Команду» и назначь жителя рыбаком" })
			end
		end
	end)
	return true   -- DialogueService: выдано, повторно не выдавать
end

-- ═══ постройки и назначения ═══

_G.MerchantStoryEvent = function(name, player)
	if name == "placed:FishingSpot" and st.stage == "fishing" then
		--[[ Станция встала ПУСТОЙ: рыбака нет. Игрок замечает пустоту, торговец
		     «вспоминает», что нужен житель, и дарит своего друга-рыбака — кнопкой
		     «Забрать награду» в самом диалоге (_G.OnDialogueClaim ниже). ]]
		st.stage = "fisher_wait"; save()
		print(LOG .. " рыбацкое место встало пустым — сцена «нужен житель»")
		task.wait(2.5)
		everyone(showNeedsResident)
	elseif name == "assigned:Fisher" and st.stage == "fisher" then
		st.stage = "farm"; st.nextDay = day() + 1; save()
		print(LOG .. " рыбак назначен, ферма — на день " .. st.nextDay)
		thought("FisherWorkingThought")
		task.wait(4)
		if typeof(_G.MerchantDepart) == "function" then _G.MerchantDepart() end
	elseif name == "built:FarmerHut" and not st.farmBuilt and (st.stage == "tavern" or st.stage == "tavern_build") then
		st.farmBuilt = true; save()
		task.wait(3)
		if st.stage == "tavern" then thought("NoWorkerThought") end
	elseif name == "built:IslandHall" and st.stage == "tavern_build" then
		st.stage = "done"; st.tavernBuilt = true; save()
		task.wait(2)
		thought("TavernThought")
		print(LOG .. " сюжет закончен: таверна на плоту")
	end
end

-- «Команда» открыта с этапа, где выдан бесплатный житель (и дальше)
local TEAM_OPEN = { fisher = true, farm = true, tavern = true, tavern_build = true, done = true }
--[[ ⚠️ ИЛИ УЖЕ ЕСТЬ КТО-ТО В КОМАНДЕ. Капитаны теперь навсегда на аккаунте
     (PirateProgress_v1.captains) и при входе встают в команду: такой игрок
     запускает игру не первый раз — кнопка «Команда» нужна ему сразу, а не
     с третьего дня, когда торговец выдаёт рыбака. Раньше этап сюжета
     перезаписывал атрибут и закрывал кнопку при каждой загрузке. ]]
local function gateTeam(p)
	local hasCrew = typeof(_G.SurvivorCrewSize) == "function" and _G.SurvivorCrewSize(p) > 0
	p:SetAttribute("TeamUnlocked", TEAM_OPEN[st.stage] == true or hasCrew)
end

-- ═══ этап сюжета: в сейве плота ═══
-- вернуть квест / сцену того этапа, на котором забег остановился
local function resumeStage()
	everyone(gateTeam)
	if st.stage == "fishing" then quest("story_fishing_place", "Подарок торговца")
	elseif st.stage == "fisher_wait" then
		task.delay(15, function() everyone(showNeedsResident) end)
	elseif st.stage == "fisher" then quest("story_assign_fisher", "Первый житель") end
end

_G.MerchantStoryExport = function() return table.clone(st) end
_G.MerchantStoryRestore = function(data)
	if type(data) ~= "table" or type(data.stage) ~= "string" then return end
	for k, v in pairs(data) do st[k] = v end
	print(("%s этап из сейва плота: «%s», следующий визит — день %d"):format(LOG, st.stage, st.nextDay))
	resumeStage()
end

-- новая игра: сюжет с начала (сейв, если есть, подменит этап при загрузке плота)
task.spawn(function()
	while #Players:GetPlayers() == 0 do task.wait(0.5) end
	loaded = true
	everyone(gateTeam)
	print(("%s этап «%s», следующий визит — день %d"):format(LOG, st.stage, st.nextDay))
end)

-- новичок посреди сюжета: тот же квест на трекере
Players.PlayerAdded:Connect(function(p)
	while not loaded do task.wait(0.5) end
	gateTeam(p)
	task.wait(12)
	if st.stage == "fishing" then pcall(_G.TrackQuest, p, "story_fishing_place")
	elseif st.stage == "fisher_wait" then showNeedsResident(p)
	elseif st.stage == "fisher" then pcall(_G.TrackQuest, p, "story_assign_fisher") end
end)

-- ═══ расписание визитов ═══
task.spawn(function()
	local wasPresent = false
	while true do
		task.wait(3)
		if loaded then
			local present = typeof(_G.MerchantPresent) == "function" and _G.MerchantPresent()
			-- визит закончился, а сделки не было: завтра снова (подарок — тоже)
			if wasPresent and not present then
				local offeredNow = visitOffered
				visitOffered = nil
				local kind = visitKind()
				if kind == "farm" or kind == "tavern" or st.stage == "intro" then
					st.nextDay = day() + 1; save()
					print(LOG .. " торговец уплыл без сделки — следующий визит на день " .. st.nextDay)
					--[[ на прощание: «ничего страшного, завтра приплыву с тем же» — только
					     если он В ЭТОТ РАЗ привёз ферму (таверну) и её не купили. Смотреть
					     на текущий этап нельзя: в день подарка этап уже «farm» (рыбака
					     назначили), и торговец прощался словами про нехватку ресурсов. ]]
					if offeredNow == "farm" and kind == "farm" then thought("MerchantFarmMissed")
					elseif offeredNow == "tavern" and kind == "tavern" then thought("MerchantTavernMissed") end
				end
			end
			wasPresent = present
			local t = Lighting.ClockTime
			local p = (t >= 6 and t < 18) and (t - 6) / 12 or nil
			local kind = visitKind()
			local wantVisit = (st.stage == "intro" or st.stage == "farm" or st.stage == "tavern") and kind ~= nil
			if wantVisit and not present and day() >= st.nextDay and p and p >= VISIT_AT then
				local ok, why = _G.MerchantArrive(kind == "fishing" and STAY_GIFT or STAY_SALE)
				print(("%s день %d: торговец с «%s» → %s"):format(LOG, day(), kind, ok and "плывёт" or ("нет: " .. tostring(why))))
				if ok then wasPresent = true else st.nextDay = day() + 1 end
			end
		end
	end
end)

-- настройки (тест): перемотать сутки к следующему визиту — день визита, 70% светлого дня
_G.MerchantStorySkipToVisit = function()
	local kind = visitKind()
	if not kind then return false, "сюжет закончен" end
	if typeof(_G.SetDayCount) ~= "function" or typeof(_G.SetDayClock) ~= "function" then return false, "нет DayNightCircle" end
	local target = math.max(day(), st.nextDay)
	_G.SetDayCount(target)
	_G.SetDayClock(380 * VISIT_AT + 1)   -- светлая часть суток — 380 с (DayNightCircle)
	local dc = ReplicatedStorage:FindFirstChild("DayCount")
	if dc then dc:SetAttribute("Skipped", true) end   -- рекорд выживания на этом сервере не пишется
	print(("%s перемотка: день %d, вечер — торговец с «%s»"):format(LOG, target, kind))
	return true, target, kind
end

-- настройки (тест): вызвать торговца по сюжету прямо сейчас
_G.MerchantStoryVisitNow = function()
	local kind = visitKind()
	if not kind then return false, "сюжет закончен" end
	return _G.MerchantForceArrive(kind == "fishing" and STAY_GIFT or STAY_SALE)
end

print(LOG .. " готово: день 3 — подарок, дальше ферма и таверна")
