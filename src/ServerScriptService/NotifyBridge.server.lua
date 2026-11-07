--[[
	УВЕДОМЛЕНИЯ С СЕРВЕРА.

	⚠️ _G У СЕРВЕРА И КЛИЕНТА РАЗНЫЕ.
	Карточки уведомлений рисует NotificationCenter.client и кладёт себя в
	_G.Notify — но это _G КЛИЕНТА. Серверные системы, которые её «вызывали»
	(AmmoCaseSystem), молча не показывали ничего: на сервере такой функции нет.
	Здесь мост — RemoteEvent и одноимённая ручка, чтобы вызов с сервера выглядел
	так же просто, как с клиента.

	    _G.NotifyPlayer(player, { type = "warn", icon = "🪵",
	                              title = "Нет брёвен", body = "…" })
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local event = ReplicatedStorage:FindFirstChild("NotifyPlayer")
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "NotifyPlayer"
	event.Parent = ReplicatedStorage
end

_G.NotifyPlayer = function(player, opts)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	if type(opts) ~= "table" then return end
	event:FireClient(player, opts)
end

print("[NotifyBridge] готов (_G.NotifyPlayer с сервера)")
