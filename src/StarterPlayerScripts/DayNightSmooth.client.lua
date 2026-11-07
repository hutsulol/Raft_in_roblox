--[[
	ПЛАВНАЯ ЛУНА НОЧЬЮ (клиент).

	Сервер (DayNightCircle) двигает время порциями раз в 0,25 с — чтобы на
	телефонах не мерцали тени солнца. Днём шаг крошечный, а ночь втрое быстрее
	(12 часов за 120 с): порция — это прыжок луны на ~0,4°, да ещё по сети
	доезжает неровно. Луна ехала рывками.

	Ночью клиент сам досчитывает ClockTime КАЖДЫЙ КАДР от опорной точки сервера
	(атрибуты Lighting: CycleTime, CycleAt, CycleRate). Пишем в RenderStepped —
	после того как пришла репликация и до отрисовки, так что серверная порция
	на экран не попадает. Днём не вмешиваемся: там порции и задуманы.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local DAY = 380     -- = DayNightCircle.DAY_DURATION
local NIGHT = 120   -- = DayNightCircle.NIGHT_DURATION

RunService.RenderStepped:Connect(function()
	local base, at = Lighting:GetAttribute("CycleTime"), Lighting:GetAttribute("CycleAt")
	if type(base) ~= "number" or type(at) ~= "number" then return end
	local rate = Lighting:GetAttribute("CycleRate") or 1
	-- вперёд не дальше секунды: пропала связь — не убегаем от сервера
	local cycle = base + math.clamp(workspace:GetServerTimeNow() - at, 0, 1) * rate
	if cycle < DAY or cycle >= DAY + NIGHT then return end
	local hour = 18 + (cycle - DAY) / NIGHT * 12
	if hour >= 24 then hour -= 24 end
	Lighting.ClockTime = hour
end)
