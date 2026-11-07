-- PirateProgression.server.lua
-- Персистентность валюты «Pirate» и прокачки пушек. До этого скрипта
-- баланс Pirate жил только как атрибут игрока и терялся при выходе.
-- База общая с лобби (см. WeaponUpgradeConfig.lua): лобби продаёт
-- улучшения и пишет в тот же DataStore, игра начисляет валюту и
-- применяет множители урона.
--
-- Загрузка: PlayerAdded -> GetAsync -> атрибуты Pirate + WUpg_<id>.
-- Сейв: PlayerRemoving + автосейв каждые 120с + BindToClose (UpdateAsync;
-- звёзды прокачки мержатся через max — прокачка никогда не откатывается).

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig"))

local AUTOSAVE_INTERVAL = 120
local LOG_TAG = "[PirateProgression]"

local store
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if not ok then
		warn(LOG_TAG .. " DataStore недоступен: " .. tostring(err))
	end
end

local loaded   = {} -- [player] = true после применения данных (без этого не сейвим)
local baseline = {} -- [player] = баланс В БАЗЕ на момент загрузки (для дельта-сейва)
local saving   = {} -- [player] = true, пока идёт запись (сейвы не перекрываются)

local function keyFor(userId)
	return Config.KEY_PREFIX .. userId
end

--[[ ═══ КАПИТАНЫ — НАВСЕГДА НА АККАУНТЕ (общая база с лобби) ═══
     data.captains = { [defId] = true } в том же ключе PirateProgress_v1. Пишут
     обе стороны: лобби — при клейме героя в ежедневке (там же играет попап
     «Новый персонаж»), океан — при любой выдаче (таверна, сюжет, настройки:
     SurvivorService._G.GrantSurvivor). При входе в океан все капитаны аккаунта
     молча встают в команду (SurvivorService._G.SyncAccountCaptains).
     Запись — отдельный UpdateAsync только этого поля: баланс и прочее не трогаем. ]]
_G.SaveCaptain = function(player, defId)
	if not store or type(defId) ~= "string" then return end
	task.spawn(function()
		for attempt = 1, 3 do
			local ok, err = pcall(function()
				store:UpdateAsync(keyFor(player.UserId), function(old)
					old = type(old) == "table" and old or {}
					local caps = type(old.captains) == "table" and old.captains or {}
					if caps[defId] then return nil end   -- уже записан — ничего не пишем
					caps[defId] = true
					old.captains = caps
					return old
				end)
			end)
			if ok then return end
			warn(LOG_TAG .. " капитан " .. defId .. " не записан (" .. tostring(err) .. "), повтор " .. attempt)
			task.wait(attempt * 2)
		end
	end)
end

--[[ ⚠️ ОБЪЯВЛЕНО ЗАРАНЕЕ: тело ниже, а зовёт его applyData — она выше по файлу.
     Без этой строки имя внутри applyData разрешилось бы как ГЛОБАЛЬНОЕ, то есть
     nil, и сторож баланса молча не подключался бы ни к одному игроку. ]]
local watchBalance

--[[ ПРЕДМЕТЫ ЕЖЕДНЕВКИ ЛОББИ (Config.DAILY_V2 в лобби, поле data.dailyItems).
     Атрибут DailyItem_<id> ставим на все — пусть видят будущие системы.
     Выдаём то, что в океане уже есть:
       hero_rose       → Капитан Роза в команду (SurvivorService), раз за забег
       raft_decor_pack → пак декора «Дефолт» (DecorPacks: те самые 11 предметов)
       hero_coldcap    → Cold Cap в команду (SurvivorDefs.coldcap), раз за забег
     В океане пока НЕТ: backpack_lvl2 (у игрока нет уровней рюкзака — слоты
     растут от Силы; BackPack_lvl2 есть только у наёмников). ]]
local DAILY_ITEM_IDS = { "hero_rose", "backpack_lvl2", "raft_decor_pack", "hero_coldcap" }

local function waitAttr(player, attr, timeout)
	local t0 = os.clock()
	while player.Parent and not player:GetAttribute(attr) and os.clock() - t0 < timeout do
		task.wait(0.5)
	end
	return player.Parent ~= nil
end

local function grantDailyItems(player, items, captains)
	for _, id in ipairs(DAILY_ITEM_IDS) do
		player:SetAttribute("DailyItem_" .. id, items[id] == true or nil)
	end
	if items.raft_decor_pack == true then
		task.spawn(function()
			if not waitAttr(player, "DecorPacksLoaded", 20) then return end
			if player:GetAttribute("DecorPack_Default") then return end
			if typeof(_G.GrantDecorPack) == "function" then
				local ok, why = pcall(_G.GrantDecorPack, player, "Default")
				print(("%s %s: пак декора из ежедневки → %s"):format(LOG_TAG, player.Name, tostring(ok and why)))
			end
		end)
	end
	local owned = {}
	for id, v in pairs(type(captains) == "table" and captains or {}) do
		if v == true and type(id) == "string" then owned[id] = true end
	end
	if items.hero_rose == true then owned.rose = true end
	if items.hero_coldcap == true then owned.coldcap = true end
	do
		task.spawn(function()
			-- команда приезжает из сейва плота и заменяет текущую — ждём её
			if not waitAttr(player, "RaftSaveApplied", 60) then return end
			-- команда сохраняется только у хозяина плота; гостю не выдаём
			if typeof(_G.IsRaftOwner) == "function" and not _G.IsRaftOwner(player) then return end
			if typeof(_G.SyncAccountCaptains) ~= "function" then
				warn(LOG_TAG .. " _G.SyncAccountCaptains нет — капитаны аккаунта не выданы")
				return
			end
			local ok, err = pcall(_G.SyncAccountCaptains, player, owned)
			if not ok then warn(LOG_TAG .. " капитаны аккаунта: " .. tostring(err)) end
		end)
	end
end

local function applyData(player, data)
	-- Идемпотентность: повторное применение (дубликат скрипта в place,
	-- гонка PlayerAdded/GetPlayers, повторный loadPlayer) не должно
	-- прибавлять базу второй раз.
	if loaded[player] then return end
	data = type(data) == "table" and data or {}
	-- Монеты, заработанные до завершения загрузки, не теряем — прибавляем.
	-- ВАЖНО: берём счётчик реально начисленного за сессию (PirateCurrency),
	-- а НЕ текущее значение атрибута. Атрибут мог уже содержать баланс из
	-- базы (его выставил второй загрузчик — например, дубликат этого скрипта
	-- или лобби-сервис), и прибавление атрибута удваивало баланс каждую
	-- сессию: дельта-сейв затем записывал «+база» в DataStore.
	local earnedBeforeLoad = (_G.GetSessionEarnedPirate and _G.GetSessionEarnedPirate(player)) or 0
	baseline[player] = tonumber(data.pirate) or 0
	player:SetAttribute(Config.BALANCE_ATTR, baseline[player] + earnedBeforeLoad)

	local upgrades = type(data.upgrades) == "table" and data.upgrades or {}
	for _, w in ipairs(Config.Weapons) do
		local stars = math.clamp(math.floor(tonumber(upgrades[w.id]) or 0), 0, Config.maxLevelsFor(w))
		player:SetAttribute(Config.ATTR_PREFIX .. w.id, stars)
	end

	-- Классы (тот же ключ, покупаются в лобби). Игра только ЧИТАЕТ уровни
	-- и выбранный класс — эффекты (дайвер и т.д.) смотрят на эти атрибуты.
	-- savePlayer правит old.pirate/old.upgrades по месту, поле old.class не
	-- трогает, так что покупки лобби не затираются.
	local rawClass = type(data.class) == "table" and data.class or {}
	local rawLevels = type(rawClass.levels) == "table" and rawClass.levels or {}
	if Config.Classes then
		for _, c in ipairs(Config.Classes) do
			local lvl = math.clamp(math.floor(tonumber(rawLevels[c.id]) or 0), 0, Config.MAX_CLASS_LEVEL)
			player:SetAttribute(Config.CLASS_LEVEL_PREFIX .. c.id, lvl)
		end
		local selected = rawClass.selected
		if type(selected) ~= "string" or not Config.ClassById[selected]
			or (math.floor(tonumber(rawLevels[selected]) or 0)) < 1 then
			selected = ""
		end
		player:SetAttribute(Config.CLASS_SELECTED_ATTR, selected)
	end

	-- Разблокировки пушек (покупаются в лобби, тот же ключ). Игра только ЧИТАЕТ их:
	-- рулетка (RewardRoll) не выдаёт заблокированные пушки, пока разблокировка не куплена.
	-- savePlayer правит только old.pirate/old.upgrades, поле old.unlocks не трогает —
	-- значит покупки из лобби не затираются сейвом игры.
	local rawUnlocks = type(data.unlocks) == "table" and data.unlocks or {}
	if Config.Unlocks then
		for _, u in ipairs(Config.Unlocks) do
			player:SetAttribute(Config.UNLOCK_ATTR_PREFIX .. u.id, rawUnlocks[u.id] and 1 or 0)
		end
	end

	-- Рекорд выживания: игра его и пишет (DaysRecord.server.lua), но
	-- поднять в атрибут надо здесь — иначе зашедшему в середине захода не с
	-- чем сравнивать, и он бы «побил» свой же рекорд числом поменьше.
	player:SetAttribute(Config.DAYS_RECORD_ATTR,
		math.max(0, math.floor(tonumber(data.daysRecord) or 0)))

	-- Предметы из ежедневки лобби (тот же ключ, data.dailyItems; пишет только лобби,
	-- savePlayer это поле не трогает). Здесь — внутри applyData, чтобы
	-- идемпотентность loaded[player] не дала выдать дважды за вход.
	grantDailyItems(player, type(data.dailyItems) == "table" and data.dailyItems or {}, data.captains)

	loaded[player] = true
	watchBalance(player)
end

local function loadPlayer(player)
	if not store then
		applyData(player, nil)
		return
	end
	local ok, data
	for attempt = 1, 3 do
		ok, data = pcall(function()
			return store:GetAsync(keyFor(player.UserId))
		end)
		if ok then break end
		warn(LOG_TAG .. " не удалось загрузить " .. player.Name
			.. " (попытка " .. attempt .. "): " .. tostring(data))
		task.wait(2 ^ attempt)
		if not player.Parent then return end
	end
	if not ok then
		-- ВАЖНО: не применяем данные и не помечаем loaded — иначе
		-- автосейв затрёт реальный баланс в базе session-заработком.
		-- Пробуем снова в фоне, пока игрок на сервере.
		task.delay(30, function()
			if player.Parent and not loaded[player] then
				loadPlayer(player)
			end
		end)
		return
	end
	if player.Parent then
		applyData(player, data)
		print(string.format("%s %s загружен: %d Pirate", LOG_TAG, player.Name,
			player:GetAttribute(Config.BALANCE_ATTR) or 0))
	end
end

--[[ ⚠️ СТОРОЖ БАЛАНСА: ЛОВИТ УДВОЕНИЕ В МОМЕНТ, КОГДА ОНО ПРОИСХОДИТ.
     Баланс в любой момент обязан быть равен арифметике: «база из DataStore +
     заработано за сессию − потрачено за сессию». Всё, что не сходится, записано
     в атрибут мимо _G.AddPirate/_G.SpendPirate — то есть чужой рукой.
     Это уже случалось: монеты удваивались каждый вход, потому что базу применял
     ВТОРОЙ загрузчик (старая копия скрипта, живущая в самом place-файле, —
     Rojo такие не удаляет из-за $ignoreUnknownInstances), а дельта-сейв затем
     закреплял удвоение в базе.
     Поэтому здесь не только защита, но и диагностика: в лог уходит и ожидаемое
     число, и фактическое, и разница. Если разница в точности равна базе — виноват
     второй загрузчик, и искать его надо в ServerScriptService самого места, а не
     в репозитории.
     Вверх откатываем: созданные из воздуха деньги ломают экономику всем. Вниз —
     принимаем как новую точку отсчёта: вернуть игроку списанное мимо ручек мы не
     можем, а бесконечно ругаться в лог бессмысленно. ]]
local fixing = {}   -- [player] = true, пока чиним сами (свой же сигнал игнорируем)

local function expectedBalance(player)
	local earned = (_G.GetSessionEarnedPirate and _G.GetSessionEarnedPirate(player)) or 0
	local spent  = (_G.GetSessionSpentPirate  and _G.GetSessionSpentPirate(player))  or 0
	return (baseline[player] or 0) + earned - spent
end

function watchBalance(player)
	player:GetAttributeChangedSignal(Config.BALANCE_ATTR):Connect(function()
		if not loaded[player] or fixing[player] then return end

		local actual = player:GetAttribute(Config.BALANCE_ATTR) or 0
		local expect = expectedBalance(player)
		if actual == expect then return end

		if actual > expect then
			warn(string.format(
				"%s ЧУЖАЯ ЗАПИСЬ БАЛАНСА у %s: стало %d, ожидалось %d (разница %d, база %d). "
				.. "Если разница равна базе — в place живёт второй загрузчик, ищи дубликат скрипта.",
				LOG_TAG, player.Name, actual, expect, actual - expect, baseline[player] or 0))
			fixing[player] = true
			player:SetAttribute(Config.BALANCE_ATTR, expect)
			fixing[player] = false
		else
			warn(string.format("%s баланс %s уменьшили мимо SpendPirate: %d вместо %d — принимаю как новую точку отсчёта",
				LOG_TAG, player.Name, actual, expect))
			-- сдвигаем базу ровно на разницу: после этого арифметика снова сходится
			baseline[player] = (baseline[player] or 0) - (expect - actual)
		end
	end)
end

--[[ ⚠️ ПЛЮС ОПРОС, А НЕ ТОЛЬКО ПОДПИСКА НА ИЗМЕНЕНИЕ.
     Сторож выше слышит только те записи, что случились ПОСЛЕ его подключения.
     Чужая запись в окне «данные пришли — сторож подписался» проходит мимо него:
     сигнала он уже не увидит, а значение так и останется на экране до самого
     сохранения. Дешёвый опрос закрывает это окно и заодно ловит источники,
     которые почему-то не поднимают сигнал.
     Пять секунд — компромисс: чужая цифра не успевает пожить на экране, а
     стоимость проверки это одно сравнение на игрока. ]]
task.spawn(function()
	while true do
		task.wait(5)
		for _, player in ipairs(Players:GetPlayers()) do
			if loaded[player] and not fixing[player] then
				local actual = player:GetAttribute(Config.BALANCE_ATTR) or 0
				local expect = expectedBalance(player)
				if actual > expect then
					warn(string.format(
						"%s опрос поймал чужую запись у %s: %d вместо %d (разница %d) — возвращаю",
						LOG_TAG, player.Name, actual, expect, actual - expect))
					fixing[player] = true
					player:SetAttribute(Config.BALANCE_ATTR, expect)
					fixing[player] = false
				end
			end
		end
	end
end)

--[[ Баланс выставлен вручную (админская кнопка «Баланс» в настройках): это не
     чужая запись, а осознанное действие. Принимаем число как новую базу. ]]
_G.AcceptPirateBalance = function(player)
	if not loaded[player] then return end
	baseline[player] = player:GetAttribute(Config.BALANCE_ATTR) or 0
	if _G.ResetPirateSessionCounters then _G.ResetPirateSessionCounters(player) end
end

local function savePlayer(player, attempts)
	if not store or not loaded[player] then return end

	-- сейвы одного игрока не перекрываются (двойное применение дельты)
	local waited = 0
	while saving[player] and waited < 5 do
		task.wait(0.1)
		waited += 0.1
	end
	if saving[player] then return end
	saving[player] = true

	--[[ ⚠️ В БАЗУ УХОДИТ ЗАРАБОТАННОЕ, А НЕ РАЗНИЦА С АТРИБУТОМ.
	     Здесь стояло delta = attr − baseline, и это оказалось дырой размером во
	     весь баланс. Атрибут может записать кто угодно — старая копия скрипта в
	     самом place-файле, чужой сервис, эксплойт. Стоило кому-то положить туда
	     «база + база», и дельта становилась равна базе: сохранение честно
	     удваивало деньги в DataStore. Ровно это и повторилось: 800 тысяч стали
	     1.6 миллиона.
	     Сторож по изменению атрибута такие записи ловит, но только те, что
	     случились ПОСЛЕ его подписки: запись в окне между загрузкой и подпиской
	     он не видит, а сохранение — уже видит.
	     Поэтому источник правды теперь не атрибут, а счётчики самой валюты:
	     сколько реально начислено и потрачено через _G.AddPirate/_G.SpendPirate.
	     Чужая запись в атрибут больше не попадает в базу НИКАК, независимо от
	     того, кто и когда её сделал. ]]
	local earned = (_G.GetSessionEarnedPirate and _G.GetSessionEarnedPirate(player)) or 0
	local spent  = (_G.GetSessionSpentPirate  and _G.GetSessionSpentPirate(player))  or 0
	local delta = earned - spent

	local pirate = (baseline[player] or 0) + delta
	local shown = player:GetAttribute(Config.BALANCE_ATTR) or 0
	if shown ~= pirate then
		--[[ Расхождение = кто-то писал в атрибут мимо ручек. Пишем в лог обе
		     цифры и приводим экран к тому, что уйдёт в базу: игрок должен видеть
		     свой настоящий баланс, а не чужую подпись. ]]
		warn(string.format(
			"%s баланс %s разошёлся: на экране %d, по счётчикам %d (база %d, заработано %d, потрачено %d)",
			LOG_TAG, player.Name, shown, pirate, baseline[player] or 0, earned, spent))
		player:SetAttribute(Config.BALANCE_ATTR, pirate)
	end
	local upgrades = {}
	for _, w in ipairs(Config.Weapons) do
		upgrades[w.id] = player:GetAttribute(Config.ATTR_PREFIX .. w.id) or 0
	end

	--[[ ⚠️ МЕТКА ЗАПИСИ: ПОВТОР НЕ ДОЛЖЕН ПРИБАВИТЬ ДЕЛЬТУ ВТОРОЙ РАЗ.
	     Ниже стоит цикл повторов на случай сетевого сбоя. Но pcall падает и тогда,
	     когда запрос ушёл, база его применила, а ответ не вернулся: следующая
	     попытка прибавила бы ту же дельту ещё раз — и баланс вырос бы вдвое, без
	     всяких дубликатов скриптов.
	     Метка уникальна для КОНКРЕТНОЙ записи (не для сессии): база помнит
	     последнюю применённую, и повтор с той же меткой не делает ничего. ]]
	local writeTag = string.format("%d:%d:%d", player.UserId, os.time(), math.floor(delta))

	--[[ ⚠️ ЗАПИСЬ ПЕРЕПРИМЕНЯЕТ ИТОГ СЕССИИ, А НЕ ПРИБАВЛЯЕТ ОЧЕРЕДНУЮ ДЕЛЬТУ.
	     Прибавление нельзя защитить в принципе: сколько ни ставь замков внутри
	     скрипта, они локальны для ЭТОГО экземпляра. А удваивают баланс ровно те
	     случаи, когда пишет кто-то ещё:
	       • старая копия скрипта, живущая в самом place ($ignoreUnknownInstances
	         оставляет её при синхронизации, и у неё свои таблицы и свои замки);
	       • повтор после «неудачного» pcall, когда база запись всё же применила;
	       • параллельный автосейв другого экземпляра.
	     Поэтому в базе хранится не только сумма, но и ИТОГ ТЕКУЩЕЙ СЕССИИ вместе
	     с её ключом. Повторная запись вычитает прежде записанный итог и кладёт
	     новый — сколько бы раз она ни случилась, результат один и тот же.
	     Ключ сессии — сервер плюс игрок: JobId одинаков у всех экземпляров на
	     этом сервере, значит вторая копия попадёт в ту же запись и ПЕРЕЗАПИШЕТ
	     её, а не прибавит к ней. ]]
	local sessionKey = ("%s:%d"):format(game.JobId ~= "" and game.JobId or "studio", player.UserId)

	local ok, err
	for attempt = 1, (attempts or 1) do
		ok, err = pcall(function()
			store:UpdateAsync(keyFor(player.UserId), function(old)
				old = type(old) == "table" and old or {}
				local base = tonumber(old.pirate) or 0
				-- сколько эта же сессия уже записала (0, если сессия другая)
				local applied = (old.session == sessionKey) and (tonumber(old.sessionDelta) or 0) or 0
				old.pirate = math.max(0, math.floor(base - applied + delta))
				old.session = sessionKey
				old.sessionDelta = delta
				old.lastWrite = writeTag
				local ups = type(old.upgrades) == "table" and old.upgrades or {}
				for id, stars in pairs(upgrades) do
					-- прокачка никогда не откатывается
					ups[id] = math.max(math.floor(tonumber(ups[id]) or 0), stars)
				end
				old.upgrades = ups
				old.savedAt = os.time()
				return old
			end)
		end)
		if ok then break end
		if attempt < (attempts or 1) then task.wait(attempt * 2) end
	end

	if ok then
		print(string.format("%s %s сохранён: база %d + итог сессии %d",
			LOG_TAG, player.Name, baseline[player] or 0, delta))
		--[[ ⚠️ СЧЁТЧИКИ И БАЗУ НЕ ТРОГАЕМ, И ЭТО ОБЯЗАТЕЛЬНО.
		     Запись выше не прибавляет дельту, а переприменяет ИТОГ сессии.
		     Сбрось мы счётчики — следующий автосейв пришёл бы с итогом ноль,
		     вычел прежде записанный и отнял у игрока весь заработок сессии.
		     База остаётся той, что пришла из DataStore при входе: от неё
		     считается ожидаемый баланс, и она не должна ползти. ]]
	else
		warn(LOG_TAG .. " не удалось сохранить " .. player.Name .. ": " .. tostring(err))
	end
	saving[player] = nil
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadPlayer, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	savePlayer(player, 3)
	loaded[player] = nil
	baseline[player] = nil
	fixing[player] = nil
	saving[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(savePlayer, player, 1)
		end
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePlayer(player, 2)
	end
end)
