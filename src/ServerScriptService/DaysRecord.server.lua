--------------------------------------------------------------------
-- DaysRecord.server.lua (океан)
-- РЕКОРД ВЫЖИВАНИЯ: сколько дней игрок продержался в лучшем заходе.
-- Показывает его лобби — табличка над головой; здесь только запись.
--
-- ⚠️ ФИКСИРУЕМ В МОМЕНТ НАСТУПЛЕНИЯ ДНЯ, А НЕ В КОНЦЕ ЗАХОДА.
-- Записывать по окончании игры нечем и негде: заход кончается вылетом,
-- закрытием клиента или смертью, и «конец» на сервере часто не наступает
-- вовсе. Поэтому рекорд обновляется ровно тогда, когда DayCount вырос:
-- дожил до дня N — число N уже твоё, что бы дальше ни случилось.
--
-- ⚠️ РЕКОРД НЕ УМЕНЬШАЕТСЯ НИКОГДА.
-- И в атрибут, и в базу пишется только через math.max. Иначе следующий же
-- заход на один день затирал бы прошлые тридцать, а параллельная запись из
-- лобби (тот же ключ PirateProgress_v1) могла бы откатить число.
--
-- Данные: DataStore Config.DATASTORE_NAME, ключ player_<UserId>,
-- поле data.daysRecord. Тот же ключ ведёт PirateProgression.server.lua —
-- он правит свои поля, мы своё, UpdateAsync их не путает.
--------------------------------------------------------------------

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig"))

local LOG_TAG = "[Рекорд]"

local store
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if not ok then
		warn(LOG_TAG .. " база недоступна: " .. tostring(err))
	end
end

--[[ ⚠️ СЧИТАЕМ СВОИ ДНИ, А НЕ ВОЗРАСТ СЕРВЕРА.
     DayCount при каждом старте сервера равен единице и никуда не сохраняется
     (DayNightCircle) — то есть «День 46» означает, что ЭТОТ СЕРВЕР крутится
     шесть с половиной часов, а не что игрок столько прожил. Раньше вошедшему
     засчитывался текущий день целиком: зашёл в чужую или в свою же давно
     запущенную игру — и в рекорде 46 дней, которых не было.
     Теперь запоминаем день входа и засчитываем прожитое ЗДЕСЬ:
       рекорд = текущий день - день входа + 1.
     На свежем сервере день входа равен единице, и формула даёт ровно номер
     дня — то есть для честного захода ничего не изменилось. ]]
local joinDay = {}   -- [player] = DayCount в момент входа
local runBase = {}   -- [player] = дни ЭТОГО ЖЕ забега, принесённые из своего сейва

local function currentDay()
	local dc = ReplicatedStorage:FindFirstChild("DayCount")
	return math.max(1, math.floor(tonumber(dc and dc.Value) or 1))
end

--[[ ⚠️ ПЕРЕМОТАННЫЕ СУТКИ РЕКОРДОМ НЕ СЧИТАЮТСЯ.
     Админская кнопка «ночь сейчас» (SettingsMenuActions → _G.StartNightNow)
     выбрасывает весь остаток дня: сутки схлопываются со 500 секунд до ста
     двадцати, а со спящим в кровати — до шести. За полчаса тестов набегает
     полсотни «дней». Нажали кнопку — DayNightCircle помечает счётчик, и с этого
     момента сервер рекордов не пишет: уже заработанное остаётся, новое не
     начисляется. Кнопка при этом на месте, тестировать ночь по-прежнему можно. ]]
local function dayCheated()
	local dc = ReplicatedStorage:FindFirstChild("DayCount")
	return dc ~= nil and dc:GetAttribute("Skipped") == true
end

-- дней в ЭТОМ забеге: принесённое из своего сейва + прожитое на этом сервере
local function survivedBy(player, day)
	local base = joinDay[player]
	if not base then return 0 end
	local carried = math.max(1, math.floor(tonumber(runBase[player]) or 1))
	return carried + (day - base)
end

local function recordOf(player)
	return math.max(0, math.floor(tonumber(player:GetAttribute(Config.DAYS_RECORD_ATTR)) or 0))
end

-- запись в базу: только вверх, с ретраями (рекорд терять обиднее всего)
local writing = {} -- [player] = true, чтобы не слать два UpdateAsync разом
local function persist(player, value)
	if not store or writing[player] then return end
	writing[player] = true
	task.spawn(function()
		local userId = player.UserId
		local ok, err
		for attempt = 1, 3 do
			ok, err = pcall(function()
				store:UpdateAsync(Config.KEY_PREFIX .. userId, function(old)
					old = type(old) == "table" and old or {}
					old.daysRecord = math.max(math.floor(tonumber(old.daysRecord) or 0), value)
					return old
				end)
			end)
			if ok then break end
			task.wait(attempt * 2)
		end
		if ok then
			print(("%s %s: рекорд %d дн. записан"):format(LOG_TAG, player.Name, value))
		else
			warn(("%s %s: не удалось записать рекорд %d — %s")
				:format(LOG_TAG, player.Name, value, tostring(err)))
		end
		writing[player] = nil
	end)
end

-- поднять рекорд игрока до days, если это действительно рекорд
local function bump(player, days)
	days = math.floor(tonumber(days) or 0)
	if days <= 0 then return end
	if dayCheated() then return end   -- сутки перемотали вручную: это не рекорд
	if days <= recordOf(player) then return end
	player:SetAttribute(Config.DAYS_RECORD_ATTR, days)
	persist(player, days)
end

-- День входа: до него прожитое не наше. Ставим и на уже вошедших — скрипт
-- мог перезапуститься позже, чем зашёл первый игрок.
Players.PlayerAdded:Connect(function(player)
	joinDay[player] = currentDay()
end)
for _, player in ipairs(Players:GetPlayers()) do
	joinDay[player] = currentDay()
end

Players.PlayerRemoving:Connect(function(player)
	writing[player] = nil
	joinDay[player] = nil
	runBase[player] = nil
end)

--[[ ⚠️ ЗАБЕГ ЖИВЁТ В СЕЙВЕ ПЛОТА, А НЕ В СЕССИИ СЕРВЕРА.
     DayCount при каждом старте равен единице, поэтому без этих двух функций
     возвращение к своему сохранению начинало бы счёт дней заново: сохранился на
     двенадцатом дне, вернулся — и снова первый. Базу ставит RaftSaveSystem при
     загрузке и ТОЛЬКО владельцу сейва: гость на чужом плоту считает свои дни с
     нуля, чужие сорок к нему не переезжают. ]]
_G.SetRunDaysBase = function(player, days)
	days = math.floor(tonumber(days) or 0)
	if days <= 0 then return end
	runBase[player] = days
end

-- Загрузчик сейва перематывает DayCount на сохранённый день: точка отсчёта
-- владельца сдвигается туда же, иначе перемотка засчиталась бы как прожитые дни
_G.SetRunDaysJoin = function(player, day)
	day = math.floor(tonumber(day) or 0)
	if day >= 1 then joinDay[player] = day end
end

_G.GetRunDays = function(player)
	return survivedBy(player, currentDay())
end

--[[ ⚠️ СЧЁТЧИК ДНЕЙ БЕРЁМ ЧУЖОЙ, СВОЙ НЕ ЗАВОДИМ.
     ReplicatedStorage.DayCount ведёт DayNightCircle.server.lua — он один
     знает, когда день сменился. Второй счётчик неизбежно разъехался бы с
     первым, и рекорд считался бы не по тем дням, что видит игрок. ]]
task.spawn(function()
	local dayCount = ReplicatedStorage:WaitForChild("DayCount", 60)
	if not dayCount then
		warn(LOG_TAG .. " нет DayCount — рекорд выживания считать нечем")
		return
	end

	local function sweep()
		local day = math.floor(tonumber(dayCount.Value) or 0)
		for _, player in ipairs(Players:GetPlayers()) do
			bump(player, survivedBy(player, day))
		end
	end

	dayCount.Changed:Connect(sweep)

	-- Вошедшему засчитываем ТЕКУЩИЙ день как первый свой, а не как сорок шестой.
	Players.PlayerAdded:Connect(function(player)
		-- прогресс приезжает не мгновенно (PirateProgression грузит его из
		-- базы) — иначе сравнивать было бы не с чем и рекорд обнулился бы
		task.delay(10, function()
			if player.Parent then bump(player, survivedBy(player, currentDay())) end
		end)
	end)

	sweep()
	print(LOG_TAG .. " слежу за DayCount")
end)
