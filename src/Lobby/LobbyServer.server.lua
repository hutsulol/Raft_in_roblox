-- LobbyServer.server.lua
-- Manages lobby pads: creation, joining, countdown, and teleport to ocean mode.
-- Place this in ServerScriptService.
-- Expects 3 parts in workspace named "LobbyPad_1", "LobbyPad_2", "LobbyPad_3"

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local RaftShared = require(ReplicatedStorage:WaitForChild("RaftSaveShared"))

local OCEAN_PLACE_ID = 77272676169005

-- Only run in the lobby place, NOT in the ocean sub-place
if game.PlaceId == OCEAN_PLACE_ID then return end

local raftStore = nil
local storeOk, storeErr = pcall(function()
	raftStore = DataStoreService:GetDataStore("RaftSaveData_v1")
end)
if storeOk then
	print("[Lobby] DataStore connected OK")
else
	warn("[Lobby] DataStore failed: " .. tostring(storeErr))
end

-- Track which players chose to load their save
local playerLoadSave = {} -- [player] = true/false
local MAX_GROUP_SIZE = 5
local COUNTDOWN_TIME = 15
--[[ ⚠️ НЕПОЛНАЯ ПАТИ НЕ УЛЕТАЕТ. ЖДЁМ, ПОКА НАБЕРЁТСЯ.
     Я было пустил отсчёт с момента создания и отправлял тех, кто успел, — но
     это отправляло игрока одного в пати на двоих, чего он не заказывал.
     Теперь отсчёт запускается ТОЛЬКО когда состав собран, а до тех пор на
     табло висит Waiting.

     Пати на одного — тот же случай «состав собран», просто собирается сразу. ]]
local FULL_TIME = 3    -- секунд от полного состава до вылета
local PAD_RANGE = 20 -- how far a player can be from pad before auto-removed

-- ─── RemoteEvents ───
local lobbyEvent = Instance.new("RemoteEvent")
lobbyEvent.Name = "LobbyEvent"
lobbyEvent.Parent = ReplicatedStorage

-- ─── Зоны телепорта ───
-- Лобби переделали: вместо трёх плоских падов LobbyPad_* теперь четыре модели
-- TeleportZone*, у каждой свой борт, табло и точка сбора.
--
-- ⚠️ «ПАДОМ» ДЛЯ ОСТАЛЬНОГО КОДА ОСТАЁТСЯ ДЕТАЛЬ, А НЕ МОДЕЛЬ.
-- Ниже всё построено на BasePart: pad.Position, pad.Touched, атрибуты дебаунса.
-- Подменить его Моделью — значит переписать половину файла ради одной строки
-- поиска. Поэтому от модели зоны берём ОДНУ деталь-триггер, а саму модель
-- держим рядом в zoneOf — она нужна только чтобы найти табло.
--
-- ⚠️ ИМЯ ДЕТАЛИ-ТРИГГЕРА ИЩЕМ С ЗАПАСОМ. Сборка в Studio живая: сегодня объём
-- зовётся ZoneContainer, завтра его переименуют. Поэтому идём по списку
-- кандидатов, а если ни один не подошёл — берём первую попавшуюся деталь и
-- ГРОМКО сообщаем, какую именно: молчащая зона отлаживается часами.
local ZONE_PREFIX = "TeleportZone"
local TRIGGER_NAMES = { "ZoneContainer", "LobbyPos", "Trigger", "Pad" }

local zoneOf = {}   -- [pad] = модель зоны

local function triggerPart(zone)
	for _, name in TRIGGER_NAMES do
		local part = zone:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then return part, name end
	end
	local any = zone:FindFirstChildWhichIsA("BasePart", true)
	return any, any and "первая попавшаяся деталь" or nil
end

local function findLobbyPads()
	local zones = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and d.Name:sub(1, #ZONE_PREFIX) == ZONE_PREFIX then
			table.insert(zones, d)
		end
	end
	table.sort(zones, function(a, b) return a.Name < b.Name end)

	local pads = {}
	for _, zone in zones do
		local part, how = triggerPart(zone)
		if part then
			zoneOf[part] = zone
			table.insert(pads, part)
			print(("[Lobby] зона %s: триггер %s (%s)"):format(zone.Name, part.Name, how))
		else
			warn(("[Lobby] в зоне %s нет ни одной детали — она не сработает"):format(zone.Name))
		end
	end
	return pads
end

local lobbyPads = findLobbyPads()
if #lobbyPads == 0 then
	warn(("[Lobby] в Workspace нет моделей %s* — вставать некуда"):format(ZONE_PREFIX))
end

-- Падов-сейвов больше нет: загрузка идёт кнопкой в меню лобби, а не отдельной
-- зоной. Таблицу оставляем пустой, чтобы не потрошить ветки ниже.
local savePads = {}

-- ─── Lobby State ───
-- Each pad can hold one lobby
local lobbies = {} -- [pad] = {owner, maxPlayers, players = {player}, countdown, countdownThread, active}

local function initLobby(pad)
	lobbies[pad] = {
		owner = nil,
		maxPlayers = 0,
		players = {},
		countdown = 0,
		countdownThread = nil,
		active = false, -- lobby has been created
		teleporting = false,
	}
end

for _, pad in lobbyPads do
	initLobby(pad)
end

-- ─── Табло над зоной ───
-- ⚠️ ТАБЛО У ЗОНЫ УЖЕ ЕСТЬ — СВОЁ, СВЁРСТАННОЕ В STUDIO.
-- Раньше скрипт сносил чужое и лепил своё; с новыми зонами так нельзя: там
-- BillboardGui с готовыми PlayerCount и StateLabel, и переписать его кодом
-- значит выкинуть работу художника. Ищем существующее, и только если его нет —
-- собираем запасное сами.
local function findLabels(pad)
	local zone = zoneOf[pad] or pad
	local bb = zone:FindFirstChildWhichIsA("BillboardGui", true)
	if not bb then return nil end
	local count = bb:FindFirstChild("PlayerCount", true) or bb:FindFirstChild("CountLabel", true)
	local state = bb:FindFirstChild("StateLabel", true) or bb:FindFirstChild("StatusLabel", true)
	if count and state then return bb, state, count end
	return nil
end

-- ⚠️ ТЕКСТ ТАБЛО В ПОКОЕ — АВТОРСКИЙ, ЕГО НЕ СОЧИНЯЕМ.
-- Я подставил сюда русские строки, и на них слетел шрифт: у подписи в Studio
-- выбран фонт без кириллицы, движок молча заменяет его на запасной. Поэтому
-- в покое возвращаем ровно ту строку, которая была свёрстана, а свои пишем
-- только для состояний, которых в вёрстке нет (отсчёт, загрузка).
local defaultText = {}
local function remember(label)
	if label and defaultText[label] == nil then defaultText[label] = label.Text end
end

-- ⚠️ БОРТИКИ ЗОНЫ: ПРОХОДИМЫ, ПОКА ИДЁТ НАБОР, И ЗАКРЫТЫ НА ОТСЧЁТЕ.
-- Смысл в том, чтобы на старте никто не выскочил и не влез в последний момент.
-- Держать их закрытыми ВСЁ время нельзя: тогда в зону не войти и набора не
-- будет вовсе. Состояние не хранится отдельно, а считается из лобби (см.
-- updateBillboard) — иначе оно рано или поздно разойдётся с реальностью.
local bordersCache = {}
local function borderParts(pad)
	if bordersCache[pad] then return bordersCache[pad] end
	local zone = zoneOf[pad]
	local root = zone and (zone:FindFirstChild("Border", true) or zone)
	local parts = {}
	if root then
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then table.insert(parts, d) end
		end
		if root:IsA("BasePart") then table.insert(parts, root) end
	end
	bordersCache[pad] = parts
	return parts
end

local sealedNow = {}
local function setSealed(pad, sealed)
	if sealedNow[pad] == sealed then return end   -- каждый кадр трогать физику незачем
	sealedNow[pad] = sealed
	local parts = borderParts(pad)
	for _, part in parts do
		part.CanCollide = sealed
	end
	-- Диагностика: если борт всё равно проходим, первым делом надо знать, СКОЛЬКО
	-- деталей нашлось. Ноль означает, что "Border" лежит не там, где его ищут.
	print(("[Lobby] %s: борт %s (деталей %d)"):format(
		zoneOf[pad] and zoneOf[pad].Name or pad.Name,
		sealed and "ЗАКРЫТ" or "открыт", #parts))
end

local function createBillboard(pad)
	if findLabels(pad) then return end   -- своё табло на месте, не трогаем

	local existing = pad:FindFirstChild("LobbyBillboard")
	if existing then existing:Destroy() end

	local bb = Instance.new("BillboardGui")
	bb.Name = "LobbyBillboard"
	bb.Size = UDim2.new(0, 120, 0, 50)
	bb.StudsOffset = Vector3.new(0, 5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 80
	bb.Parent = pad

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, 0, 0.5, 0)
	statusLabel.Position = UDim2.new(0, 0, 0, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Waiting..."
	statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	statusLabel.TextStrokeTransparency = 0.3
	statusLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextScaled = true
	statusLabel.Parent = bb

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "CountLabel"
	countLabel.Size = UDim2.new(1, 0, 0.5, 0)
	countLabel.Position = UDim2.new(0, 0, 0.5, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "0/5"
	countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	countLabel.TextStrokeTransparency = 0.3
	countLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextScaled = true
	countLabel.Parent = bb

	return bb
end

local function updateBillboard(pad)
	local lobby = lobbies[pad]
	if not lobby then return end
	local _, statusLabel, countLabel = findLabels(pad)
	if not statusLabel or not countLabel then return end
	remember(statusLabel)
	remember(countLabel)

	--[[ ⚠️ ТАБЛО ПЕРЕВЁРСТАНО: СВЕРХУ СЧЁТ, СНИЗУ ВРЕМЯ.
	     Раньше в нижней строке был текст состояния («Waiting for players…»),
	     теперь там секунды. Пишем только цифры — они одинаково выглядят в любом
	     шрифте, а слова на кириллице ломали фонт вёрстки (уже проходили).
	     Пока отсчёта нет, возвращаем ровно то, что нарисовано в Studio: это и
	     есть заявленное время ожидания, и придумывать своё число незачем. ]]
	if not lobby.active then
		statusLabel.Text = defaultText[statusLabel]
		countLabel.Text = defaultText[countLabel]
	else
		countLabel.Text = #lobby.players .. "/" .. lobby.maxPlayers
		local full = #lobby.players >= lobby.maxPlayers

		--[[ ⚠️ ПОКА ПАТИ НЕ СОБРАНА — «Waiting», А НЕ ТИКАЮЩИЕ СЕКУНДЫ.
		     Секунды на неполном лобби читаются как «сейчас улетим», хотя игра
		     ещё ждёт людей, и игрок не понимает, чего он ждёт.

		     Сам таймер при этом ИДЁТ: без него пати, которую никто не дособрал,
		     висела бы вечно — этим мы уже обжигались. Просто не показываем его,
		     пока есть куда ждать. Последние секунды всё же показываем: вылет
		     без всякого предупреждения выглядит сбоем.  ]]
		local WARN_AT = 5
		if lobby.teleporting then
			statusLabel.Text = "0s"
		elseif full or (lobby.countdown > 0 and lobby.countdown <= WARN_AT) then
			statusLabel.Text = lobby.countdown .. "s"
		else
			statusLabel.Text = "Waiting"
		end
	end

	-- Замок едет вместе с табло: updateBillboard уже зовётся на КАЖДОЙ смене
	-- состояния лобби, и отдельный вызов setSealed рано или поздно забыли бы
	-- в одной из веток — например при отмене телепорта.
	-- ⚠️ ЗАКРЫВАЕМ СРАЗУ, КАК ЛОББИ СОЗДАНО, а не на отсчёте.
	-- Сначала я запирал зону только на countdown, чтобы к набору можно было
	-- подойти. По факту важнее другое: состав пати фиксируется в момент выбора
	-- размера, и выйти из зоны после этого нельзя.
	setSealed(pad, lobby.active)

	-- ⚠️ СВОБОДНА ЗОНА ИЛИ НЕТ — ОТДАЁМ АТРИБУТОМ.
	-- Клиенту это нужно, чтобы вести к ней стрелку, а гонять ради одного
	-- логического значения свой ремоут незачем: атрибуты реплицируются сами и
	-- переживают доезд игрока позже события.
	local zone = zoneOf[pad]
	if zone then zone:SetAttribute("Free", not lobby.active) end
end

-- Create billboards for all pads
for _, pad in lobbyPads do
	createBillboard(pad)
	updateBillboard(pad)
end

-- ─── Helpers ───
local function findPadForPlayer(player)
	for _, pad in lobbyPads do
		local lobby = lobbies[pad]
		if lobby then
			for _, p in lobby.players do
				if p == player then return pad end
			end
		end
	end
	return nil
end

local function isPlayerInAnyLobby(player)
	return findPadForPlayer(player) ~= nil
end

local function getNearestPad(player)
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local closest, closestDist = nil, math.huge
	for _, pad in lobbyPads do
		local dist = (hrp.Position - pad.Position).Magnitude
		if dist < closestDist then
			closest = pad
			closestDist = dist
		end
	end
	if closestDist <= PAD_RANGE then
		return closest
	end
	return nil
end

--[[ ⚠️ ПРОВЕРЯЕМ ОБЪЁМ ЗОНЫ, А НЕ РАССТОЯНИЕ ДО ТОЧКИ.
     Зоны прямоугольные и разного размера: любой радиус будет либо выпускать
     игрока за борт, либо держать в пати того, кто уже ушёл. Считаем попадание
     в коробку самой детали-триггера, с небольшим запасом — на толщину тела и
     на то, что персонаж стоит НА зоне, а не в ней. ]]
--[[ ⚠️ ЗАПАС ПО ВЫСОТЕ БОЛЬШОЙ, И ЭТО НЕ НЕБРЕЖНОСТЬ.
     Где стоит коробка триггера относительно пола, знает только тот, кто её
     ставил: её могли утопить в землю или поднять над ней. Игрок всегда стоит
     НА полу, поэтому по вертикали промахнуться легко, а по горизонтали — нет.
     Тесная проверка выкидывала бы из пати того, кто спокойно стоит в зоне.
     Числа те же, что и в клиентской проверке (LobbyMainUI): граница должна
     совпадать, иначе клиент закроет окно, а сервер решит, что игрок на месте. ]]
local ZONE_MARGIN_XZ = 6
local ZONE_MARGIN_Y  = 30

local function isInsideZone(player, pad)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and pad and pad.Parent) then return false end
	local rel = pad.CFrame:PointToObjectSpace(hrp.Position)
	local half = pad.Size * 0.5
	return math.abs(rel.X) <= half.X + ZONE_MARGIN_XZ
		and math.abs(rel.Y) <= half.Y + ZONE_MARGIN_Y
		and math.abs(rel.Z) <= half.Z + ZONE_MARGIN_XZ
end

local function broadcastLobbyState(pad)
	local lobby = lobbies[pad]
	if not lobby then return end

	local playerNames = {}
	for _, p in lobby.players do
		table.insert(playerNames, p.Name)
	end

	local state = {
		active = lobby.active,
		maxPlayers = lobby.maxPlayers,
		playerCount = #lobby.players,
		playerNames = playerNames,
		countdown = lobby.countdown,
		ownerName = lobby.owner and lobby.owner.Name or nil,
		teleporting = lobby.teleporting,
		isSavePad = savePads[pad] or false,
	}

	-- Send to all players in the lobby
	for _, p in lobby.players do
		lobbyEvent:FireClient(p, "lobbyState", pad, state)
	end

	updateBillboard(pad)
end

local function removePlayerFromLobby(player, pad)
	local lobby = lobbies[pad]
	if not lobby then return end

	local idx = table.find(lobby.players, player)
	if not idx then return end
	table.remove(lobby.players, idx)

	lobbyEvent:FireClient(player, "leftLobby")

	-- If owner left, disband
	if player == lobby.owner then
		-- Notify remaining players
		for _, p in lobby.players do
			lobbyEvent:FireClient(p, "leftLobby")
		end
		initLobby(pad)
		if lobby.countdownThread then
			task.cancel(lobby.countdownThread)
		end
	end

	broadcastLobbyState(pad)
	updateBillboard(pad)
end

-- ─── Access mode + active slot of a raft owner ───
-- Приоритет — атрибуты игрока (их ставит SaveMenuService мгновенно,
-- всегда актуальны). Если игрок не открывал меню сохранений — читаем
-- базу один раз (кэш на сессию). Объявлено ДО startCountdown, чтобы
-- телепорт-замыкание захватило локаль, а не nil-глобал.
local ownerInfoCache = {} -- [userId] = { access, activeSlot } (только фолбэк из базы)
local function getOwnerInfo(owner)
	-- owner — объект Player (владелец лобби)
	local attrAccess = owner:GetAttribute(RaftShared.ATTR_ACCESS)
	local attrSlot = owner:GetAttribute(RaftShared.ATTR_SLOT)
	if attrAccess ~= nil then
		return {
			access = (attrAccess == RaftShared.ACCESS_FRIENDS) and RaftShared.ACCESS_FRIENDS or RaftShared.ACCESS_EVERYONE,
			activeSlot = math.clamp(math.floor(tonumber(attrSlot) or 1), 1, RaftShared.MAX_SLOTS),
		}
	end

	local userId = owner.UserId
	if ownerInfoCache[userId] then return ownerInfoCache[userId] end
	local info = { access = RaftShared.ACCESS_EVERYONE, activeSlot = 1 }
	if raftStore then
		local ok, raw = pcall(function()
			return raftStore:GetAsync(RaftShared.indexKey(userId))
		end)
		if ok and type(raw) == "table" then
			local idx = RaftShared.normalizeIndex(raw)
			info.access = idx.access
			info.activeSlot = idx.activeSlot
		end
	end
	ownerInfoCache[userId] = info
	return info
end

-- дружит ли owner с игроком (для доступа "только друзья")
local function isFriendOfOwner(owner, joiner)
	if owner.UserId == joiner.UserId then return true end
	local ok, res = pcall(function()
		return owner:IsFriendsWith(joiner.UserId)
	end)
	return ok and res == true
end

local function startCountdown(pad, seconds)
	local lobby = lobbies[pad]
	if not lobby or lobby.teleporting then return end

	-- Cancel existing countdown
	if lobby.countdownThread then
		task.cancel(lobby.countdownThread)
		lobby.countdownThread = nil
	end

	lobby.countdown = seconds or COUNTDOWN_TIME
	broadcastLobbyState(pad)

	lobby.countdownThread = task.spawn(function()
		while lobby.countdown > 0 and lobby.active and not lobby.teleporting do
			task.wait(1)
			lobby.countdown = lobby.countdown - 1
			broadcastLobbyState(pad)
		end

		if lobby.active and not lobby.teleporting and #lobby.players > 0 then
			-- Teleport all players
			lobby.teleporting = true
			broadcastLobbyState(pad)

			-- режим доступа + активный слот владельца (из меню сохранений)
			local ownerInfo = getOwnerInfo(lobby.owner)

			-- доступ "только друзья": на момент запуска отсеиваем тех, кто
			-- перестал (или не был) другом владельца — например, вошёл в
			-- лобби до переключения владельца на "друзья"
			local playersToTeleport = {}
			for _, p in lobby.players do
				if ownerInfo.access ~= RaftShared.ACCESS_FRIENDS or isFriendOfOwner(lobby.owner, p) then
					table.insert(playersToTeleport, p)
				else
					lobbyEvent:FireClient(p, "notFriend")
					lobbyEvent:FireClient(p, "leftLobby")
				end
			end

			if #playersToTeleport == 0 then
				lobby.teleporting = false
				lobby.countdown = 0
				broadcastLobbyState(pad)
				return
			end

			local success, err = pcall(function()
				local teleportOptions = Instance.new("TeleportOptions")

				local teleportData = {}

				-- Always pass the lobby owner so only they get raft saves
				teleportData.raftOwnerId = lobby.owner.UserId
				teleportData.accessMode = ownerInfo.access
				teleportData.saveSlot = ownerInfo.activeSlot

				if savePads[pad] and lobby.owner then
					-- Save pad: load the lobby owner's saved raft for everyone
					teleportData.loadSave = true
					teleportData.saveOwnerId = lobby.owner.UserId
				else
					-- Normal pad: check if any player wants to load their save
					local anyLoadSave = false
					for _, p in playersToTeleport do
						if playerLoadSave[p] then
							anyLoadSave = true
							break
						end
					end
					teleportData.loadSave = anyLoadSave
				end

				teleportOptions:SetTeleportData(teleportData)

				-- ⚠️ СВОЙ СЕРВЕР КАЖДОЙ ГРУППЕ, А НЕ ТОЛЬКО «ТОЛЬКО ДРУЗЬЯМ».
				--
				-- Раньше резерв включался лишь для ACCESS_FRIENDS, а «всем»
				-- уезжало обычным TeleportAsync — и матчмейкинг Roblox сажал
				-- новую группу в УЖЕ ЗАПУЩЕННЫЙ сервер к чужому плоту. Игрок
				-- создавал новую игру и попадал в чужую партию.
				--
				-- Состав группы здесь набирается ЛОББИ (пады, кнопка «Войти»),
				-- а не матчмейкингом Roblox, поэтому подселение посторонних не
				-- нужно ни в одном режиме доступа. ACCESS_EVERYONE означает
				-- «ко мне можно проситься в лобби», а не «Roblox волен подсадить
				-- кого угодно в мой океан».
				--
				-- Для «только друзей» остаётся fail-closed: не выдался приватный
				-- сервер — роняем телепорт, а не сливаем приватность молча.
				-- Для «всех» приватность не на кону, поэтому при отказе
				-- (например, ReserveServer недоступен в Studio) громко ругаемся,
				-- но игрока пускаем — иначе тестировать станет нечем.
				if ownerInfo.access == RaftShared.ACCESS_FRIENDS then
					teleportOptions.ReservedServerAccessCode =
						TeleportService:ReserveServer(OCEAN_PLACE_ID)
				else
					local ok, code = pcall(function()
						return TeleportService:ReserveServer(OCEAN_PLACE_ID)
					end)
					if ok and code then
						teleportOptions.ReservedServerAccessCode = code
					else
						warn("[Lobby] ReserveServer не дал сервер (" .. tostring(code)
							.. ") — группа уедет в общий матчмейкинг и может попасть "
							.. "к чужому плоту")
					end
				end

				TeleportService:TeleportAsync(OCEAN_PLACE_ID, playersToTeleport, teleportOptions)
			end)

			if not success then
				warn("Teleport failed: " .. tostring(err))
				lobby.teleporting = false
				lobby.countdown = 0
				for _, p in lobby.players do
					lobbyEvent:FireClient(p, "teleportFailed", tostring(err))
				end
				broadcastLobbyState(pad)
			end
		end
	end)
end

-- ─── Check if player has a saved raft ───
local function checkPlayerSave(player)
	if not raftStore then
		warn("[Lobby] No DataStore, skipping save check for " .. player.Name)
		return false
	end
	local userId = player.UserId

	-- любой занятый слот в индексе = сейв есть; возвращаем активный слот
	local okIdx, rawIdx = pcall(function()
		return raftStore:GetAsync(RaftShared.indexKey(userId))
	end)
	if okIdx and type(rawIdx) == "table" then
		local idx = RaftShared.normalizeIndex(rawIdx)
		for i = 1, RaftShared.MAX_SLOTS do
			if idx.slots[i] then
				print("[Lobby] FOUND save (индекс) for " .. player.Name .. ", активный слот " .. idx.activeSlot)
				return true, idx.activeSlot
			end
		end
	end

	-- совместимость: старый сейв под слотом 1 без записи в индексе
	local success, data = pcall(function()
		return raftStore:GetAsync(RaftShared.slotKey(userId, 1))
	end)
	if success and type(data) == "table" and data.raft then
		print("[Lobby] FOUND legacy save for " .. player.Name)
		return true, 1
	elseif not success then
		warn("[Lobby] DataStore read error: " .. tostring(data))
	else
		print("[Lobby] No save found for " .. player.Name)
	end
	return false, nil
end

-- ─── Auto-check save on join ───
-- СТАРЫЙ авто-промпт «Continue?» ОТКЛЮЧЁН: загрузка сохранений теперь
-- идёт через меню «МОЙ ПЛОТ» на падах SaveGame (SaveMenuService),
-- поэтому «saveFound» больше не шлём, чтобы не всплывало старое окно.
local function checkAndNotifyPlayer(player)
	-- намеренно ничего не делаем (см. комментарий выше)
end

Players.PlayerAdded:Connect(function(player)
	print("[Lobby] PlayerAdded: " .. player.Name)
	checkAndNotifyPlayer(player)
end)

-- Also check for players already in game (in case script loads late)
for _, player in Players:GetPlayers() do
	print("[Lobby] Existing player found: " .. player.Name)
	checkAndNotifyPlayer(player)
end

-- ─── Events ───
lobbyEvent.OnServerEvent:Connect(function(player, action, data, data2)
	if action == "continueSave" then
		-- Player chose "Yes" — teleport them solo to their saved raft
		playerLoadSave[player] = true
		task.spawn(function()
			local info = getOwnerInfo(player)
			local success, err = pcall(function()
				local teleportOptions = Instance.new("TeleportOptions")
				teleportOptions:SetTeleportData({
					loadSave = true,
					raftOwnerId = player.UserId,
					saveSlot = info.activeSlot,
					accessMode = info.access,
					-- Размер комнаты для замка на стороне океана (RoomLock):
					-- «продолжить» — всегда в одиночку.
					playerCount = 1,
				})
				-- Свой сервер и на «продолжить»: иначе игрок со своим сейвом
				-- приезжал бы в чужой уже запущенный океан (см. подробный
				-- разбор у группового телепорта выше).
				if info.access == RaftShared.ACCESS_FRIENDS then
					teleportOptions.ReservedServerAccessCode = TeleportService:ReserveServer(OCEAN_PLACE_ID)
				else
					local ok, code = pcall(function()
						return TeleportService:ReserveServer(OCEAN_PLACE_ID)
					end)
					if ok and code then
						teleportOptions.ReservedServerAccessCode = code
					else
						warn("[Lobby] ReserveServer не дал сервер (" .. tostring(code)
							.. ") — продолжение уедет в общий матчмейкинг")
					end
				end
				TeleportService:TeleportAsync(OCEAN_PLACE_ID, {player}, teleportOptions)
			end)
			if not success then
				warn("Continue teleport failed: " .. tostring(err))
				lobbyEvent:FireClient(player, "teleportFailed", tostring(err))
			end
		end)
		return

	elseif action == "declineSave" then
		-- Player chose "No" — just dismiss, they can use pads normally
		playerLoadSave[player] = false
		return

	elseif action == "requestPadState" then
		-- Player stepped on a pad, send current state
		local pad = data
		if not pad or not lobbies[pad] then return end
		local lobby = lobbies[pad]

		local playerNames = {}
		for _, p in lobby.players do
			table.insert(playerNames, p.Name)
		end

		local state = {
			active = lobby.active,
			maxPlayers = lobby.maxPlayers,
			playerCount = #lobby.players,
			playerNames = playerNames,
			countdown = lobby.countdown,
			ownerName = lobby.owner and lobby.owner.Name or nil,
			teleporting = lobby.teleporting,
			isSavePad = savePads[pad] or false,
		}
		lobbyEvent:FireClient(player, "padState", pad, state)

	elseif action == "createLobby" then
		-- data = pad, data2 = maxPlayers
		local pad = data
		local maxPlayers = data2
		if not pad or not lobbies[pad] then return end
		if isPlayerInAnyLobby(player) then return end

		local lobby = lobbies[pad]
		if lobby.active then return end -- already created
		-- ⚠️ Создать пати можно только СТОЯ в зоне: клиент шлёт pad сам, и без
		-- этой проверки игру можно было бы запустить с другого конца лобби.
		if not isInsideZone(player, pad) then
			lobbyEvent:FireClient(player, "leftLobby")
			return
		end

		-- If this is a save pad, verify player has save data
		if savePads[pad] then
			local hasSave = checkPlayerSave(player)
			if not hasSave then
				lobbyEvent:FireClient(player, "noSaveData")
				return
			end
		end

		if typeof(maxPlayers) ~= "number" then return end
		maxPlayers = math.clamp(math.floor(maxPlayers), 1, MAX_GROUP_SIZE)

		lobby.active = true
		lobby.owner = player
		lobby.maxPlayers = maxPlayers
		lobby.players = {player}
		lobby.teleporting = false

		lobbyEvent:FireClient(player, "joinedLobby", pad)
		broadcastLobbyState(pad)

		-- Пати на одного собрана в момент создания — сразу короткий отсчёт.
		-- Остальные ждут игроков, отсчёт начнётся при заполнении.
		if maxPlayers == 1 then
			startCountdown(pad, FULL_TIME)
		end

	elseif action == "joinLobby" then
		local pad = data
		if not pad or not lobbies[pad] then return end
		if isPlayerInAnyLobby(player) then return end

		local lobby = lobbies[pad]
		if not lobby.active then return end
		if #lobby.players >= lobby.maxPlayers then return end
		if lobby.teleporting then return end

		-- доступ "только друзья": пускаем в лобби владельца лишь его друзей
		if lobby.owner and getOwnerInfo(lobby.owner).access == RaftShared.ACCESS_FRIENDS then
			if not isFriendOfOwner(lobby.owner, player) then
				lobbyEvent:FireClient(player, "notFriend")
				return
			end
		end

		if not isInsideZone(player, pad) then
			lobbyEvent:FireClient(player, "leftLobby")
			return
		end
		table.insert(lobby.players, player)
		lobbyEvent:FireClient(player, "joinedLobby", pad)
		broadcastLobbyState(pad)

		-- Набрались раньше срока — не тянем остаток ожидания, стартуем коротко.
		if #lobby.players >= lobby.maxPlayers then
			startCountdown(pad, FULL_TIME)
		end

	elseif action == "goToZone" then
		-- ⚠️ ИГРАТЬ ВЕДЁТ В ЗОНУ, А НЕ ОТКРЫВАЕТ ОКНО НАПРЯМУЮ.
		-- Пати создаётся в конкретной зоне (createLobby ждёт pad), поэтому
		-- сперва ставим игрока в свободную, и уже оттуда идёт обычный путь —
		-- тот же, что и когда игрок пришёл в зону ногами.
		if isPlayerInAnyLobby(player) then return end
		local char = player.Character
		if not (char and char:FindFirstChild("HumanoidRootPart")) then return end

		local free
		for _, pad in lobbyPads do
			local lobby = lobbies[pad]
			if lobby and not lobby.active then free = pad break end
		end
		if not free then
			lobbyEvent:FireClient(player, "noFreeZone")
			return
		end

		--[[ ⚠️ ВЫСАЖИВАЕМ НА ПОЛ ЗОНЫ, А НЕ НА ВЕРХ ЕЁ ОБЪЁМА.
		     ZoneContainer — это коробка во всю зону, и она высокая. Я считал от
		     ВЕРХНЕЙ грани, поэтому игрока ставило над зоной, а не внутрь неё.
		     Пол — нижняя грань той же коробки; от неё и отмеряем рост
		     персонажа. Если в зоне есть своя точка (Target/LobbyPos), она
		     плоская, и низ с верхом у неё почти совпадают — формула та же. ]]
		local zone = zoneOf[free]
		local spot = zone and (zone:FindFirstChild("Target", true)
			or zone:FindFirstChild("LobbyPos", true))
		local base = (spot and spot:IsA("BasePart")) and spot or free
		local floor = base.Position.Y - base.Size.Y / 2
		char:PivotTo(CFrame.new(Vector3.new(base.Position.X, floor + 3.5, base.Position.Z)))

		-- ⚠️ Touched после телепорта не гарантирован: персонаж может встать уже
		-- внутри детали, не коснувшись её. Поэтому окно открываем сами — тем же
		-- сообщением, что шлёт касание.
		lobbyEvent:FireClient(player, "touchedPad", free)

	elseif action == "leaveLobby" then
		local pad = findPadForPlayer(player)
		if pad then
			removePlayerFromLobby(player, pad)
		end
	end
end)

-- ─── Touch detection: show UI when stepping on pad ───
for _, pad in lobbyPads do
	pad.Touched:Connect(function(hit)
		local char = hit.Parent
		if not char then return end
		local player = Players:GetPlayerFromCharacter(char)
		if not player then return end

		-- Don't fire if already in a lobby
		if isPlayerInAnyLobby(player) then return end

		-- Debounce per player
		local key = "TouchDebounce_" .. player.UserId
		if pad:GetAttribute(key) then return end
		pad:SetAttribute(key, true)
		task.delay(1, function()
			if pad then pad:SetAttribute(key, nil) end
		end)

		lobbyEvent:FireClient(player, "touchedPad", pad)
	end)
end

--[[ ⚠️ ВЫШЕЛ ИЗ ЗОНЫ — ВЫШЕЛ ИЗ ПАТИ.
     Без этого можно было встать в зону, дождаться окна, отойти и спокойно
     бегать по лобби, пока идёт отсчёт: место в пати занято, а игрока там нет.
     Проверяем дважды в секунду — чаще незачем, реже игрок успеет уйти далеко.
     На телепорте не трогаем: состав уже зафиксирован, и выдёргивать из него
     в последний момент нельзя. ]]
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, pad in lobbyPads do
			local lobby = lobbies[pad]
			if lobby and lobby.active and not lobby.teleporting then
				-- копия списка: removePlayerFromLobby меняет его на ходу
				local inside = {}
				for _, p in lobby.players do table.insert(inside, p) end
				for _, p in inside do
					if not isInsideZone(p, pad) then
						removePlayerFromLobby(p, pad)
					end
				end
			end
		end
	end
end)

-- ─── Cleanup on player leaving ───
Players.PlayerRemoving:Connect(function(player)
	playerLoadSave[player] = nil
	local pad = findPadForPlayer(player)
	if pad then
		removePlayerFromLobby(player, pad)
	end
end)
