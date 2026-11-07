--[[
	ЭКИПАЖ ПЛОТА: капитан может высадить игрока.

	Если пошёл в море со случайными людьми из лобби и кто-то нарочно умирает,
	сжигая общие жизни, капитан (владелец плота) высаживает его через настройки.
	Высаженный уезжает в лобби своей среды; если телепорт невозможен (Studio,
	лобби не определено) — отключается от сервера с объяснением.

	⚠️ ПРАВО — ТОЛЬКО У КАПИТАНА (и у админов плейса). Кто капитан, знает
	RaftSaveSystem (_G.IsRaftOwner): он приезжает в данных телепорта. Клиенту
	признак отдаём атрибутом игрока RaftOwner — по нему меню решает, рисовать ли
	карточку. Проверка права всё равно здесь: атрибут клиент подделать не может,
	а запрос — может.
	⚠️ ВЫСАЖЕННЫЙ НЕ ВОЗВРАЩАЕТСЯ В ЭТОТ ЗАБЕГ: его UserId запоминается до конца
	жизни сервера, повторный заход отправляет обратно в лобби.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LOG = "[Экипаж]"
local KICK_COOLDOWN = 3

local remote = ReplicatedStorage:FindFirstChild("RaftCrewAction")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "RaftCrewAction"
	remote.Parent = ReplicatedStorage
end

local banned = {}      -- [UserId] = true: высажен в этом забеге
local lastKick = {}

local function isCaptain(player)
	if typeof(_G.IsRaftOwner) == "function" and _G.IsRaftOwner(player) then return true end
	return player:GetAttribute("DevLogs") == true   -- админ плейса
end

local function sendAway(target, why)
	local ok = false
	if typeof(_G.TeleportPlayersToLobby) == "function" then
		local good, res = pcall(_G.TeleportPlayersToLobby, { target })
		ok = good and res == true
	end
	if not ok then
		pcall(function() target:Kick(why) end)
	else
		-- телепорт может занять секунды: если игрок всё ещё здесь, отключаем
		task.delay(8, function()
			if target.Parent then pcall(function() target:Kick(why) end) end
		end)
	end
end

remote.OnServerEvent:Connect(function(player, what, userId)
	if what ~= "kick" then return end
	if not isCaptain(player) then
		warn(("%s %s пытался высадить игрока, не будучи капитаном"):format(LOG, player.Name))
		return
	end
	local now = os.clock()
	if lastKick[player] and now - lastKick[player] < KICK_COOLDOWN then return end
	lastKick[player] = now

	local target = Players:GetPlayerByUserId(tonumber(userId) or 0)
	if not target or target == player then return end
	-- капитана высадить нельзя, даже админу: плот и сейв — его
	if typeof(_G.IsRaftOwner) == "function" and _G.IsRaftOwner(target) then
		remote:FireClient(player, "toast", "Капитана высадить нельзя")
		return
	end
	banned[target.UserId] = true
	print(("%s %s высадил %s"):format(LOG, player.Name, target.Name))
	remote:FireClient(player, "toast", target.Name .. " высажен с плота")
	if typeof(_G.NotifyPlayer) == "function" then
		pcall(_G.NotifyPlayer, target, { type = "warn", icon = "no", title = "Вас высадили",
			body = "Капитан плота отправил вас в лобби" })
	end
	task.delay(1.2, function()
		if target.Parent then sendAway(target, "Капитан высадил вас с плота") end
	end)
end)

local function refresh(player)
	player:SetAttribute("RaftOwner", isCaptain(player) or nil)
end

Players.PlayerAdded:Connect(function(player)
	if banned[player.UserId] then
		task.delay(2, function()
			if player.Parent then sendAway(player, "Вы были высажены с этого плота") end
		end)
		return
	end
	-- владелец становится известен чуть позже входа (данные телепорта читает сейв)
	task.spawn(function()
		for _ = 1, 20 do
			if not player.Parent then return end
			refresh(player)
			task.wait(1)
		end
	end)
end)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		for _ = 1, 20 do
			if not p.Parent then return end
			refresh(p)
			task.wait(1)
		end
	end)
end
Players.PlayerRemoving:Connect(function(player) lastKick[player] = nil end)

print(LOG .. " готов: капитан высаживает игроков через настройки (RaftCrewAction)")
