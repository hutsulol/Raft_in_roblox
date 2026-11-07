--[[
	СЕТКОМЁТ — серверный вход (Bootstrap.server пакета NetCapture_Import).
	Модули — ReplicatedStorage/NetCapture (Rojo), модели — там же в Assets
	(кладёт владелец в Studio: Sheep, FlightNet, WrappedNet, Pirate_Net_Launcher).
	Овца не спавнится сама: _G.NetCaptureSpawn(pos) — ноги овцы на поверхность.
	Кнопка админа «Овца для сеткомёта» ставит её перед игроком.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local pack = ReplicatedStorage:WaitForChild("NetCapture")
-- ремоут пакет ждёт готовым — создаём, если в Studio его не положили
if not pack:FindFirstChild("Remote") then
	local r = Instance.new("RemoteEvent")
	r.Name = "Remote"
	r.Parent = pack
end
local service = require(pack.Server).start()

_G.NetCaptureSpawn = function(pos)
	if typeof(pos) ~= "Vector3" then return false, "нет точки" end
	local assets = pack:FindFirstChild("Assets")
	if not (assets and assets:FindFirstChild("Sheep")) then
		return false, "нет модели ReplicatedStorage.NetCapture.Assets.Sheep"
	end
	local ok, err = pcall(service.spawn, pos)
	if not ok then return false, tostring(err) end
	return true
end
print("[Сеткомёт] готов: модули NetCapture, овца — по _G.NetCaptureSpawn")
