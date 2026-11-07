local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ПОЗА СНА: глушим штатную анимацию, пока игрок лежит в кровати.

	⚠️ ЭТО ОБЯЗАНО ЖИТЬ НА КЛИЕНТЕ.
	Анимации персонажа проигрывает ЕГО клиент. Сервер их не видит вовсе:
	Animator:GetPlayingAnimationTracks() на сервере возвращает пусто, поэтому
	попытка остановить дорожки серверным кодом ничего не делала — лежащий игрок
	продолжал «бежать» (плот движется, Humanoid видит скорость и крутит бег).

	Сервер (BedCrafting) только ставит на персонажа атрибут Sleeping — он реплицируется,
	и дальше всё делает этот скрипт у себя:
	  • выключает скрипт Animate, чтобы новых дорожек не появлялось;
	  • останавливает те, что уже играют;
	  • при подъёме возвращает всё обратно.

	Дорожки гасим НЕ ОДИН РАЗ, а короткой серией: Animate мог запустить бег в том
	же кадре, когда пришёл флаг, и одиночная остановка его бы не застала.
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local function stopAllTracks(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end
end

local function apply(character, sleeping)
	local animate = character:FindFirstChild("Animate")
	if animate then animate.Disabled = sleeping end

	if not sleeping then return end
	-- полсекунды подчищаем: Animate мог успеть запустить дорожку до того, как
	-- отключение до него дошло
	task.spawn(function()
		for _ = 1, 10 do
			if character:GetAttribute("Sleeping") ~= true then return end
			stopAllTracks(character)
			task.wait(0.05)
		end
	end)
end

local function watch(character)
	apply(character, character:GetAttribute("Sleeping") == true)
	character:GetAttributeChangedSignal("Sleeping"):Connect(function()
		apply(character, character:GetAttribute("Sleeping") == true)
	end)
end

if player.Character then watch(player.Character) end
player.CharacterAdded:Connect(watch)

print("[Сон] поза готова: Animate глохнет, пока игрок в кровати")
