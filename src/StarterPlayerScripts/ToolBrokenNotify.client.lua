-- Уведомление о сломавшемся инструменте. Сервер (ToolDurabilitySystem) шлёт имя
-- тула, когда прочность дошла до нуля и тул исчез из рук.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local brokenEvent = ReplicatedStorage:WaitForChild("ToolBroken")

-- Русские названия берём из общего словаря инвентаря, чтобы в карточке было
-- «Каменный топор», а не «Stone_Axe».
local function displayName(name)
	if _G.GetItemDisplayName then
		local pretty = _G.GetItemDisplayName(name)
		if pretty then return pretty end
	end
	return (tostring(name):gsub("_", " "))
end

brokenEvent.OnClientEvent:Connect(function(toolName)
	if not _G.Notify then return end   -- NotificationCenter ещё не поднялся
	_G.Notify({
		type = "warn",
		icon = "🛠️",
		title = "Инструмент сломался",
		body = displayName(toolName) .. " износился и рассыпался",
	})
end)
