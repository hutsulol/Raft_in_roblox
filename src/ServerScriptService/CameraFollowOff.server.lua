--[[
	КАМЕРА НЕ ДОВОРАЧИВАЕТСЯ ЗА НАПРАВЛЕНИЕМ ДВИЖЕНИЯ.

	⚠️ ЭТО НЕ НАШ КОД, А РЕЖИМ КАМЕРЫ ROBLOX.
	Жалоба: «камера наводится не туда, куда смотрит игрок, а просто вперёд — куда
	плот курсирует, туда её и переводит». Это дословное описание режима Follow:
	штатная камера доворачивается за направлением движения персонажа. А плот плывёт
	непрерывно, то есть персонаж «движется вперёд» всегда — камеру и тянет вперёд,
	стоит её отпустить. В Classic такого доворота нет: куда повернул, туда и смотрит.

	⚠️ СТАВИТСЯ ТОЛЬКО С СЕРВЕРА. ЭТО И БЫЛО ОШИБКОЙ ПРОШЛОГО ЗАХОДА.
	Сначала то же самое стояло в LocalScript — и не работало вовсе, без единого
	признака в логе: DevTouchCameraMode/DevComputerCameraMode относятся к свойствам
	игрока, которые клиент менять не вправе. Запись проходит молча и ничего не даёт.

	Компьютерный режим тоже приводим к Classic: там вариант Follow в настройках
	Roblox не предлагается, но UserChoice оставляет форточку, а поведение должно быть
	одинаковым на всех устройствах.
]]

local Players = game:GetService("Players")

local function apply(player)
	local ok, err = pcall(function()
		player.DevTouchCameraMode    = Enum.DevTouchCameraMovementMode.Classic
		player.DevComputerCameraMode = Enum.DevComputerCameraMovementMode.Classic
	end)
	if not ok then
		warn(("[Камера] %s: не удалось выключить доворот за движением: %s")
			:format(player.Name, tostring(err)))
	end
end

Players.PlayerAdded:Connect(apply)
for _, p in ipairs(Players:GetPlayers()) do apply(p) end

print("[Камера] доворот за направлением движения выключен (режим Classic, с сервера)")
