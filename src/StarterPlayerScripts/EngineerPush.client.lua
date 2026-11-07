local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- EngineerPush.client.lua
-- Анимация ТОЛЧКА у игрока (пробуждение механика). Играем ЛОКАЛЬНО: у персонажей
-- игроков анимациями управляет клиент-владелец — трек, запущенный СЕРВЕРОМ на
-- Animator игрока, самому игроку не реплицируется (поэтому «рука не двигалась»).
-- Локальный Play на своём персонаже Roblox реплицирует всем автоматически.
-- Сервер (EngineerSystem) шлёт сюда id анимации через RemoteEvent EngineerPush.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

task.spawn(function()
	local remote = ReplicatedStorage:WaitForChild("EngineerPush", 30)
	if not remote then return end
	remote.OnClientEvent:Connect(function(animId)
		if type(animId) ~= "string" or animId == "" then return end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = hum
		local anim = Instance.new("Animation")
		anim.AnimationId = animId
		local ok, tr = pcall(function() return animator:LoadAnimation(anim) end)
		if ok and tr then
			tr.Priority = Enum.AnimationPriority.Action
			tr:Play(0.05)
			task.delay(3, function()
				pcall(function() tr:Stop(0.2) end)
				anim:Destroy()
			end)
		end

		-- ДИАГНОСТИКА: заглядываем ВНУТРЬ клипа — есть ли в нём реальное движение.
		-- id может грузиться и иметь длину, но позы быть НУЛЕВЫМИ (identity) — тогда рука
		-- не двигается, и это проблема САМОГО АССЕТА (переопубликуй анимацию), а не кода.
		task.spawn(function()
			local ok2, ks = pcall(function()
				return game:GetService("KeyframeSequenceProvider"):GetKeyframeSequenceAsync(animId)
			end)
			if not ok2 then
				warn("[EngineerPush] клип НЕ ЗАГРУЗИЛСЯ: " .. tostring(ks) .. " (доступ/публикация)")
				return
			end
			local parts = {}
			local function walk(p)
				for _, s in ipairs(p:GetSubPoses()) do
					if s:IsA("Pose") then
						if s.CFrame ~= CFrame.new() then parts[s.Name] = true end
						walk(s)
					end
				end
			end
			for _, kf in ipairs(ks:GetKeyframes()) do
				for _, p in ipairs(kf:GetPoses()) do
					if p:IsA("Pose") then
						if p.CFrame ~= CFrame.new() then parts[p.Name] = true end
						walk(p)
					end
				end
			end
			local list = {}
			for n in pairs(parts) do list[#list + 1] = n end
			if #list == 0 then
				warn(("[EngineerPush] клип %s ПУСТОЙ (нет движения в позах) — переопубликуй "
					.. "анимацию толчка ИЛИ дай новый id"):format(animId))
			else
				print(("[EngineerPush] клип %s двигает: %s"):format(animId, table.concat(list, ", ")))
			end
		end)
	end)
end)
