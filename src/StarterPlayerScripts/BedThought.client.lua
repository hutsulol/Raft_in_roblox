--[[
	МЫСЛИ ПРИ ПЕРВОЙ НОЧИ.

	Стемнело ВПЕРВЫЕ ЗА СЕССИЮ → игрок «думает вслух» (диалог BedThought от
	своего лица, см. DialogueDefs) и HUD-трекер переключается на квест ночлега
	(onboarding_bed) — если тот ещё не закрыт. Повторные ночи молчат: мысль одна
	на сессию.

	Сделано по образцу ThirstThought.client — те же каналы, тот же порядок.

	⚠️ НОЧЬ ЛОВИМ ПО ПЕРЕХОДУ, А НЕ ПО «ТЁМНО ЛИ СЕЙЧАС».
	ClockTime меняется каждый кадр, и проверка «сейчас ночь» срабатывала бы сотни
	раз подряд. Нужен именно момент, когда день сменился ночью — как это делает
	DayNight.client. Заодно это отсекает случай, когда игрок зашёл уже ночью:
	перехода не было, мысль подождёт до следующего заката.

	⚠️ ЕСЛИ КРОВАТЬ УЖЕ ЕСТЬ — МОЛЧИМ.
	Совет «нужна кровать» человеку, который на ней спит, читается как поломка.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting          = game:GetService("Lighting")

local QUEST_ID = "onboarding_bed"

-- День 6→18, ночь 18→6 — те же числа, что у всего проекта (DayNightCircle).
local DAY_START, DAY_END = 6, 18
local function isNight()
	local t = Lighting.ClockTime
	return t >= DAY_END or t < DAY_START
end

-- ── состояние квеста из снапшотов ──
local questStateEvent = ReplicatedStorage:WaitForChild("QuestState", 30)
local bedDone = false   -- закрыт или награда ждёт — трекать больше нечего

if questStateEvent then
	questStateEvent.OnClientEvent:Connect(function(action, payload)
		if action ~= "state" or type(payload) ~= "table" then return end
		for _, q in ipairs(payload.quests or {}) do
			if q.id == QUEST_ID then
				bedDone = (q.completed == true) or (q.rewardPending == true)
			end
		end
	end)
end

-- ── уже спим? ──
-- Кровать лежит в Workspace обычной моделью (BedCrafting ставит её туда), так
-- что достаточно посмотреть, есть ли она вообще.
local function hasBed()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == "Bed" and (d:IsA("Model") or d:IsA("BasePart")) then return true end
	end
	return false
end

-- ── триггер ──
local fired = false          -- одна мысль на сессию
local wasNight = isNight()   -- состояние на момент захода: переход ловим от него

Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
	if fired then return end
	local night = isNight()
	if night == wasNight then return end
	wasNight = night
	if not night then return end        -- рассвет нас не интересует

	if bedDone or hasBed() then
		fired = true                    -- кровать есть: подсказывать нечего
		return
	end
	fired = true

	if _G.StartLocalDialogue then
		_G.StartLocalDialogue("BedThought")
	end

	if questStateEvent then
		questStateEvent:FireServer("track", QUEST_ID)
	end
end)
