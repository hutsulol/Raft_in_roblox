--[[
	DayNightCycle.server.lua
	Controls the day/night cycle and replicates the current day number to clients.
	Day = 1 minute, Night = 2 minutes.
	ClockTime: Day = 6→18, Night = 18→6
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DAY_DURATION = 60   -- seconds (real time)
local NIGHT_DURATION = 120 -- seconds (real time)
local FULL_CYCLE = DAY_DURATION + NIGHT_DURATION
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
	local darkFactor = 1 - math.abs(t - 0.5) * 2 -- peaks at 0.5 (midnight)
	Lighting.Ambient = Color3.fromRGB(
		math.floor(40 - darkFactor * 20),
		math.floor(40 - darkFactor * 20),
		math.floor(60 - darkFactor * 20)
	)
	Lighting.Brightness = 0.5 - darkFactor * 0.3
	Lighting.OutdoorAmbient = Color3.fromRGB(
		math.floor(30 - darkFactor * 15),
		math.floor(30 - darkFactor * 15),
		math.floor(50 - darkFactor * 15)
	)
end

local cycleTime = 0

RunService.Heartbeat:Connect(function(dt)
	-- Speed up night 20x when any player is sleeping
	local isNight = cycleTime >= DAY_DURATION
	if isNight and sleepingCount.Value > 0 then
		cycleTime = cycleTime + dt * (SLEEP_SPEED_MULT - 1) -- -1 because dt itself is already added
	end
	cycleTime = cycleTime + dt

	-- Check for day rollover
	if cycleTime >= FULL_CYCLE then
		cycleTime = cycleTime - FULL_CYCLE
		dayCount.Value = dayCount.Value + 1
	end

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
