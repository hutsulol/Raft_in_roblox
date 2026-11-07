--[[ ФЛАГ «ВИДИТ ЛОГИ». Клиентские print/warn в Roblox читает любой игрок (F9 →
     Client), а серверные — только те, у кого есть права на плейс. Чтобы
     внутренности системы не светились всем, каждый клиентский скрипт затеняет
     print/warn обёрткой, которая печатает только при атрибуте DevLogs у игрока.
     Атрибут ставим здесь: Studio, админы из WeaponUpgradeConfig.ADMIN_USER_IDS,
     владелец плейса (пользователь или владелец группы). ]]
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function adminList()
	local ok, cfg = pcall(function() return require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig", 5)) end)
	return (ok and cfg and cfg.ADMIN_USER_IDS) or {}
end

local function isPlaceOwner(player)
	if game.CreatorType == Enum.CreatorType.User then return player.UserId == game.CreatorId end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function() return player:GetRankInGroup(game.CreatorId) end)
		return ok and rank == 255
	end
	return false
end

local function mark(player)
	local dev = RunService:IsStudio() or table.find(adminList(), player.UserId) ~= nil or isPlaceOwner(player)
	player:SetAttribute("DevLogs", dev and true or nil)
	if dev then print("[DevLog] " .. player.Name .. " — клиентские логи включены (админ)") end
end

Players.PlayerAdded:Connect(mark)
for _, p in ipairs(Players:GetPlayers()) do mark(p) end
