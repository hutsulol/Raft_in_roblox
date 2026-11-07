--[[
	КВЕСТ ПРО ВОДОЛАЗА — когда его выдавать.

	Через два дня после того, как игрок растолкал механика, водолаз всё ещё лежит
	у своего монолита. Игрок «думает вслух» (диалог DiverThought) и получает на
	трекер квест onboarding_diver: починить монолит.

	⚠️ УСЛОВИЙ ТРИ, И КАЖДОЕ ОТМЕНЯЕТ ВЫДАЧУ.
	  • механик разбужен — от этого дня идёт отсчёт (EngineerSystem пишет день в
	    атрибут Workspace, чтобы нам не лезть в его код);
	  • прошло два дня;
	  • монолит ЕЩЁ НЕ починен — иначе совет «оживи водолаза» придёт человеку,
	    который его уже оживил.

	⚠️ ПРОВЕРЯЕМ РЕДКО И ОДИН РАЗ ЗА СЕССИЮ.
	Это не боевая логика: раз в пять секунд более чем достаточно, а выдав квест,
	watcher замолкает навсегда.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local QUEST_ID = "onboarding_diver"
local DAYS_AFTER = 2

local dayCount = ReplicatedStorage:WaitForChild("DayCount", 30)
local questEvent = ReplicatedStorage:WaitForChild("QuestState", 30)

-- Состояние монолита спрашиваем у его же системы — она это уже наружу отдаёт.
local function monolithRepaired()
	return typeof(_G.IsMonolithRepaired) == "function" and _G.IsMonolithRepaired() == true
end

task.spawn(function()
	if not (dayCount and questEvent) then return end
	while true do
		task.wait(5)

		local woke = Workspace:GetAttribute("EngineerWokeDay")
		if woke and dayCount.Value - woke >= DAYS_AFTER and not monolithRepaired() then
			for _, player in ipairs(Players:GetPlayers()) do
				if not player:GetAttribute("DiverQuestGiven") then
					player:SetAttribute("DiverQuestGiven", true)
					if _G.StartDialogue then
						pcall(_G.StartDialogue, player, "DiverThought")
					end
					-- ⚠️ ТРЕКЕР СТАВИМ СЕРВЕРНОЙ РУЧКОЙ, А НЕ ЧЕРЕЗ RemoteEvent.
					-- Действие "track" у QuestState приходит ОТ клиента; послать
					-- его же клиенту значит ничего не сделать — он такого не ждёт.
					if _G.TrackQuest then pcall(_G.TrackQuest, player, QUEST_ID) end
				end
			end
			-- выдали всем, кто был онлайн: дальше следим только за новыми
		end
	end
end)

print("[Квест/водолаз] следит: через " .. DAYS_AFTER .. " дня после механика, если монолит цел не починен")
