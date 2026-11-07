local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	СТРАХОВКА КАМЕРЫ ПОСЛЕ РЕСПАВНА.

	Сценарий бага: игрок умирает во время катсцены (туман первого дня, зачистка
	острова — любой скрипт, взявший камеру в Scriptable). Катсцена доигрывает и
	возвращает CameraType=Custom, но CameraSubject к этому моменту указывает на
	СТАРЫЙ, уничтоженный Humanoid — Custom-камере не за кем следить, и она
	замирает на месте смерти, к новому персонажу не приходит.

	Катсцены возвращают subject и сами (см. WaveTelegraph, IslandClearedEffect) —
	этот скрипт общая страховка на «или что-то другое»: после респавна ждём,
	когда камера окажется в Custom, и если её subject не от текущего персонажа —
	возвращаем. Scriptable НЕ трогаем: это чьё-то осознанное управление
	(катсцена ещё идёт, турель, прицел) — дождёмся, пока отпустит.
]]

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

player.CharacterAdded:Connect(function(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end

	-- до 60 секунд с шагом 0.25: длинная катсцена может держать камеру долго
	for _ = 1, 240 do
		task.wait(0.25)
		if not char.Parent or hum.Health <= 0 then return end   -- умер снова — заход повторится
		local cam = Workspace.CurrentCamera
		if cam and cam.CameraType == Enum.CameraType.Custom then
			local subj = cam.CameraSubject
			if subj and (subj == hum or subj:IsDescendantOf(char)) then
				return   -- камера уже на новом персонаже, всё штатно
			end
			cam.CameraSubject = hum
			print("[CameraRespawnFix] камера вернулась к персонажу после респавна")
			return
		end
	end
end)
