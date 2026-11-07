--[[
	DayNightCycle.server.lua
	Controls the day/night cycle and replicates the current day number to clients.
	Day = 380s, Night = 120s (боевые значения беты; полный цикл 500s).
	ClockTime: Day = 6→18, Night = 18→6
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DAY_DURATION = 380   -- seconds (день укорочен на 2 мин: было 500)
local NIGHT_DURATION = 120 -- seconds
local FULL_CYCLE = DAY_DURATION + NIGHT_DURATION
local DISABLE_NIGHT = false -- nights (and their waves) are ON
local SLEEP_SPEED_MULT = 20 -- night passes 20x faster when sleeping

-- Day ClockTime range: 6 (sunrise) → 18 (sunset)
-- Night ClockTime range: 18 (sunset) → 6 (sunrise, next day)
local DAY_START = 6
local DAY_END = 18

-- Track day count
local dayCount = Instance.new("IntValue")
dayCount.Name = "DayCount"
dayCount.Value = 1
dayCount.Parent = game:GetService("ReplicatedStorage")

-- Track sleeping players count
local sleepingCount = Instance.new("IntValue")
sleepingCount.Name = "SleepingPlayers"
sleepingCount.Value = 0
sleepingCount.Parent = game:GetService("ReplicatedStorage")

-- Lighting presets
local function applyDayLighting(t)
	-- t goes 0→1 during daytime
	Lighting.Ambient = Color3.fromRGB(
		math.floor(120 + t * 50 - math.abs(t - 0.5) * 100),
		math.floor(120 + t * 50 - math.abs(t - 0.5) * 100),
		math.floor(130 + t * 40 - math.abs(t - 0.5) * 80)
	)
	Lighting.Brightness = 1.5 + (1 - math.abs(t - 0.5) * 2) * 0.5
	Lighting.OutdoorAmbient = Color3.fromRGB(
		math.floor(100 + t * 55 - math.abs(t - 0.5) * 110),
		math.floor(100 + t * 55 - math.abs(t - 0.5) * 110),
		math.floor(110 + t * 45 - math.abs(t - 0.5) * 90)
	)
end

local function applyNightLighting(t)
	-- t goes 0→1 during nighttime
	-- ЯРКАЯ ЛУННАЯ ночь: холодно-синий тон сохраняется, но всё отлично читается.
	-- Ambient — главный рычаг видимости объектов (не зависит от положения солнца/луны),
	-- поэтому крутим его высоко. Раньше к полуночи была почти чернота.
	local darkFactor = 1 - math.abs(t - 0.5) * 2 -- peaks at 0.5 (midnight)
	Lighting.Ambient = Color3.fromRGB(
		math.floor(138 - darkFactor * 12),
		math.floor(144 - darkFactor * 12),
		math.floor(170 - darkFactor * 12)
	)
	-- Brightness с ПОЛОМ: даже в полночь не ниже ~1.5 (это свет луны на сцену)
	Lighting.Brightness = 1.7 - darkFactor * 0.2
	Lighting.OutdoorAmbient = Color3.fromRGB(
		math.floor(128 - darkFactor * 10),
		math.floor(134 - darkFactor * 10),
		math.floor(160 - darkFactor * 10)
	)
end

local cycleTime = 0

-- ТЕСТ: перемотать сутки прямо к началу ночи. Дёргает кнопка в настройках
-- (SettingsMenuActions, действие "startNight") — только для админов и Studio.
-- Ждать 380 секунд дня, чтобы проверить ночную волну, невозможно.
_G.StartNightNow = function()
	if DISABLE_NIGHT then return false, "ночи выключены (DISABLE_NIGHT)" end
	if cycleTime >= DAY_DURATION then
		return false, "уже ночь"
	end
	cycleTime = DAY_DURATION
	--[[ ⚠️ ПОМЕТКА ДЛЯ РЕКОРДА ВЫЖИВАНИЯ.
	     Кнопка выбрасывает весь остаток дня: сутки схлопываются со 500 секунд до
	     ста двадцати, а со спящим в кровати — до шести. Полсотни «дней» набиваются
	     за полчаса, и рекорд выживания на таком сервере ничего не значит. Отличить
	     тестовый прогон от игры больше нечем, поэтому помечаем счётчик: DaysRecord
	     видит пометку и перестаёт писать рекорды до перезапуска сервера. Уже
	     заработанное не трогается. ]]
	dayCount:SetAttribute("Skipped", true)
	print("[DayNight] ночь запущена вручную (тест) — рекорды выживания на этом сервере больше не пишутся")
	return true
end

-- ⚠️ СОЛНЦЕ ДВИГАЕМ НЕ КАЖДЫЙ КАДР — ОТ ЭТОГО МЕРЦАЮТ ТЕНИ.
-- ClockTime писался каждый Heartbeat, то есть направление солнца менялось по
-- шестьдесят раз в секунду на микроскопическую величину. Теневая карта на каждое
-- такое изменение пересчитывается заново, и на слабом устройстве (телефон) это
-- видно как дрожь и мигание краёв теней — «неплавно».
-- Считаем время по-прежнему каждый кадр (иначе поплывёт длина суток), а В МИР
-- отдаём его порциями. Шаг подобран так, чтобы сдвиг солнца за одну порцию был
-- незаметен: сутки идут 380 секунд на 12 часов, то есть 0.03 часа в секунду —
-- за четверть секунды это меньше сотой доли часа.
local SUN_STEP = 0.25   -- секунд между обновлениями освещения
local sunAccum = 0

RunService.Heartbeat:Connect(function(dt)
	-- Speed up night 20x when any player is sleeping
	local isNight = cycleTime >= DAY_DURATION
	if isNight and sleepingCount.Value > 0 then
		cycleTime = cycleTime + dt * (SLEEP_SPEED_MULT - 1) -- -1 because dt itself is already added
	end
	cycleTime = cycleTime + dt

	-- ⚠️ СЧЁТ ВРЕМЕНИ ВЫШЕ, ПРИМЕНЕНИЕ НИЖЕ — И ПЕРЕВОД СУТОК ТОЖЕ ВЫШЕ.
	-- Ровно поэтому throttle стоит здесь, а не вокруг всей функции: смена дня
	-- должна происходить в свой момент, а не с точностью до четверти секунды.
	sunAccum = sunAccum + dt
	local applyNow = sunAccum >= SUN_STEP
	if applyNow then sunAccum = 0 end

	-- Check for day rollover (when night is disabled the "cycle" is just the day)
	local cycleLen = DISABLE_NIGHT and DAY_DURATION or FULL_CYCLE
	if cycleTime >= cycleLen then
		cycleTime = cycleTime - cycleLen
		dayCount.Value = dayCount.Value + 1
	end

	if not applyNow then return end   -- время посчитано, свет обновим в свою порцию

	-- опорная точка для плавной ночи на клиенте (DayNightSmooth.client): где сейчас
	-- сутки, в какой момент и с какой скоростью идут — клиент досчитывает каждый кадр
	Lighting:SetAttribute("CycleTime", cycleTime)
	Lighting:SetAttribute("CycleAt", workspace:GetServerTimeNow())
	Lighting:SetAttribute("CycleRate", (cycleTime >= DAY_DURATION and sleepingCount.Value > 0) and SLEEP_SPEED_MULT or 1)

	if cycleTime < DAY_DURATION then
		-- Daytime
		local t = cycleTime / DAY_DURATION -- 0→1
		Lighting.ClockTime = DAY_START + t * (DAY_END - DAY_START)
		applyDayLighting(t)
	else
		-- Nighttime
		local nightElapsed = cycleTime - DAY_DURATION
		local t = nightElapsed / NIGHT_DURATION -- 0→1
		-- ClockTime goes 18→24→6 (wraps around midnight)
		local clockHour = DAY_END + t * 12
		if clockHour >= 24 then
			clockHour = clockHour - 24
		end
		Lighting.ClockTime = clockHour
		applyNightLighting(t)
	end
end)
-- СЕЙВ: час суток, чтобы загрузка не начиналась всегда с утра
_G.GetDayClock = function() return cycleTime end
-- СЕЙВ: номер дня. Раньше после загрузки всегда шёл «День 1», хотя в сейве
-- был третий: счётчик жил только в памяти сервера
_G.GetDayCount = function() return dayCount.Value end
_G.SetDayCount = function(n)
	n = math.floor(tonumber(n) or 0)
	if n >= 1 and n ~= dayCount.Value then dayCount.Value = n end
end
_G.SetDayClock = function(t)
	t = tonumber(t); if not t then return end
	cycleTime = math.clamp(t, 0, FULL_CYCLE - 0.01)
end
