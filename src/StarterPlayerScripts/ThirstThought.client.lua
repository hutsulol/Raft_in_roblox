--[[
	МЫСЛИ ПРИ ПЕРВОЙ ЖАЖДЕ.

	Жажда упала ниже 20% ВПЕРВЫЕ ЗА СЕССИЮ → игрок «думает вслух» (диалог
	ThirstThought от своего лица, см. DialogueDefs) и HUD-трекер переключается
	на онбординг-квест очистителя воды (onboarding_purifier) — если тот ещё не
	выполнен. Повторные падения жажды молчат: мысль одна на сессию.

	Данные берём с готовых каналов:
	  • ThirstUpdate (ThirstSystem) шлёт клиенту (значение, максимум);
	  • QuestState снапшоты говорят, закрыт ли квест очистителя;
	  • переключение трекера — штатное действие "track" у QuestState.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local THRESHOLD = 0.2   -- доля от максимума жажды

local thirstEvent = ReplicatedStorage:WaitForChild("ThirstUpdate")

-- ── состояние квеста очистителя из снапшотов ──
local questStateEvent = ReplicatedStorage:WaitForChild("QuestState", 30)
local purifierDone = false   -- закрыт или награда ждёт — трекать больше нечего

local purifierSeen = false   -- квест хоть раз приходил в снапшоте

if questStateEvent then
	questStateEvent.OnClientEvent:Connect(function(action, payload)
		if action ~= "state" or type(payload) ~= "table" then return end
		local found = false
		for _, q in ipairs(payload.quests or {}) do
			if q.id == "onboarding_purifier" then
				found = true
				purifierSeen = true
				if (q.completed == true) or (q.rewardPending == true) then
					purifierDone = true
				end
			end
		end
		-- ⚠️ ФЛАГ НЕ ОТКАТЫВАЕТСЯ.
		-- Закрытый и заклеймленный квест снапшот из списка выкидывает. Пока
		-- purifierDone пересчитывался с нуля на каждом снапшоте, он тут же
		-- возвращался в false — и мысль о жажде приходила снова человеку, у
		-- которого очиститель давно стоит. Пропал из списка после того, как в нём
		-- был, — значит закрыт.
		if purifierSeen and not found then purifierDone = true end
	end)
end

-- ── триггер ──
local fired = false   -- одна мысль на сессию

thirstEvent.OnClientEvent:Connect(function(value, max)
	if fired then return end
	if type(value) ~= "number" or type(max) ~= "number" or max <= 0 then return end
	if value / max > THRESHOLD then return end

	-- ⚠️ КВЕСТ УЖЕ ЗАКРЫТ — МОЛЧИМ СОВСЕМ.
	-- Раньше проверка стояла только перед трекингом, и человек с готовым
	-- очистителем всё равно выслушивал «надо срочно что-то пить, соберу
	-- очиститель». Очиститель мог быть построен и по другому поводу — например,
	-- после подсказки при установке грядки (PlanterService).
	if purifierDone then
		fired = true
		return
	end
	fired = true

	if _G.StartLocalDialogue then
		_G.StartLocalDialogue("ThirstThought")
	end

	if questStateEvent then
		questStateEvent:FireServer("track", "onboarding_purifier")
	end
end)
