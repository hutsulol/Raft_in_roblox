local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ПОДСКАЗКА КВЕСТА «ВОДОЛАЗ» (onboarding_diver).

	Кнопка «?» на HUD-трекере подсвечивает САМ МОНОЛИТ — золотым контуром сквозь
	стены, как подсвечиваются брёвна у первого онбординг-квеста. Больше ничего
	показывать и не надо: цель одна, и она стоит на плоту, её просто надо найти
	глазами.

	Ручки те же, что у остальных подсказок: _G.DiverHintSetEnabled / _G.DiverHintEnabled.

	⚠️ ПОДСВЕЧИВАЕМ МОДЕЛЬ, А НЕ ДЕТАЛЬ.
	Монолит собран из нескольких частей; Highlight на одной обвёл бы её кусок, и
	читалось бы это как подсветка случайной доски.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local QUEST_ID = "onboarding_diver"
local GOLD = Color3.fromRGB(255, 210, 58)

local enabled = false
local questVisible = false

local questStateEvent = ReplicatedStorage:WaitForChild("QuestState", 30)

local glow = Instance.new("Highlight")
glow.Name = "DiverHintGlow"
glow.FillColor = GOLD
glow.FillTransparency = 0.75
glow.OutlineColor = GOLD
glow.OutlineTransparency = 0
glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop   -- видно сквозь стены и издалека
glow.Enabled = false
glow.Parent = Workspace

-- ⚠️ ИЩЕМ КАЖДЫЙ РАЗ, А НЕ ОДИН.
-- Монолит появляется в мире не сразу (его ставит своя система), и найденный
-- однажды может быть заменён при перезагрузке плота.
local function findMonolith()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name:sub(1, 8) == "Monolit_" then return d end
	end
	return nil
end

local function apply()
	if not enabled then
		glow.Enabled = false
		glow.Adornee = nil
		return
	end
	local m = findMonolith()
	glow.Adornee = m
	glow.Enabled = m ~= nil
end

if questStateEvent then
	questStateEvent.OnClientEvent:Connect(function(action, payload)
		if action ~= "state" or type(payload) ~= "table" then return end
		local found = false
		for _, q in ipairs(payload.quests or {}) do
			if q.id == QUEST_ID then
				found = true
				questVisible = not ((q.completed == true) or (q.rewardPending == true))
			end
		end
		if not found then questVisible = false end
		if enabled and not questVisible then
			enabled = false      -- квест закрыт: подсветка гаснет сама
			apply()
		end
	end)
end

_G.DiverHintSetEnabled = function(on)
	if on and not questVisible then
		enabled = false
		apply()
		return
	end
	enabled = on and true or false
	apply()
end

_G.DiverHintEnabled = function() return enabled end

-- монолит могли поставить уже после включения подсказки
Workspace.DescendantAdded:Connect(function(inst)
	if enabled and inst:IsA("Model") and inst.Name:sub(1, 8) == "Monolit_" then
		task.defer(apply)
	end
end)

print("[DiverHint] подсказка водолаза готова («?» подсвечивает монолит)")
