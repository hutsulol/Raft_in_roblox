-- LobbyServer.server.lua
-- Manages lobby pads: creation, joining, countdown, and teleport to ocean mode.
-- Place this in ServerScriptService.
-- Expects 3 parts in workspace named "LobbyPad_1", "LobbyPad_2", "LobbyPad_3"

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OCEAN_PLACE_ID = 110406724367282
local MAX_GROUP_SIZE = 5
local COUNTDOWN_TIME = 15
local PAD_RANGE = 20 -- how far a player can be from pad before auto-removed

-- ─── RemoteEvents ───
local lobbyEvent = Instance.new("RemoteEvent")
lobbyEvent.Name = "LobbyEvent"
lobbyEvent.Parent = ReplicatedStorage

-- ─── Find pads ───
local function findLobbyPads()
	local pads = {}
	for i = 1, 3 do
		local pad = workspace:FindFirstChild("LobbyPad_" .. i)
		if pad then
			table.insert(pads, pad)
		end
	end
	return pads
end

local lobbyPads = findLobbyPads()

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

-- ─── Billboard GUI above each pad ───
local function createBillboard(pad)
	local existing = pad:FindFirstChild("LobbyBillboard")
	if existing then existing:Destroy() end

	local bb = Instance.new("BillboardGui")
	bb.Name = "LobbyBillboard"
	bb.Size = UDim2.new(0, 300, 0, 120)
	bb.StudsOffset = Vector3.new(0, 8, 0)
	bb.AlwaysOnTop = true
	bb.Parent = pad

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, 0, 0.5, 0)
	statusLabel.Position = UDim2.new(0, 0, 0, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Waiting for players..."
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
	local bb = pad:FindFirstChild("LobbyBillboard")
	if not bb then return end

	local statusLabel = bb:FindFirstChild("StatusLabel")
	local countLabel = bb:FindFirstChild("CountLabel")
	if not statusLabel or not countLabel then return end

	if not lobby.active then
		statusLabel.Text = "Waiting for players..."
		countLabel.Text = "0/" .. MAX_GROUP_SIZE
	elseif lobby.countdown > 0 then
		statusLabel.Text = "Starting in " .. lobby.countdown
		countLabel.Text = #lobby.players .. "/" .. lobby.maxPlayers
	else
		statusLabel.Text = "Waiting for players..."
		countLabel.Text = #lobby.players .. "/" .. lobby.maxPlayers
	end
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

local function startCountdown(pad)
	local lobby = lobbies[pad]
	if not lobby or lobby.teleporting then return end

	-- Cancel existing countdown
	if lobby.countdownThread then
		task.cancel(lobby.countdownThread)
		lobby.countdownThread = nil
	end

	lobby.countdown = COUNTDOWN_TIME
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

			local playersToTeleport = {}
			for _, p in lobby.players do
				table.insert(playersToTeleport, p)
			end

			local success, err = pcall(function()
				if #playersToTeleport == 1 then
					TeleportService:Teleport(OCEAN_PLACE_ID, playersToTeleport[1])
				else
					TeleportService:TeleportPartyAsync(OCEAN_PLACE_ID, playersToTeleport)
				end
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

-- ─── Events ───
lobbyEvent.OnServerEvent:Connect(function(player, action, data, data2)
	if action == "requestPadState" then
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

		if typeof(maxPlayers) ~= "number" then return end
		maxPlayers = math.clamp(math.floor(maxPlayers), 1, MAX_GROUP_SIZE)

		lobby.active = true
		lobby.owner = player
		lobby.maxPlayers = maxPlayers
		lobby.players = {player}
		lobby.teleporting = false

		lobbyEvent:FireClient(player, "joinedLobby", pad)
		broadcastLobbyState(pad)

		-- If solo (1 player), start countdown immediately
		if maxPlayers == 1 then
			startCountdown(pad)
		end

	elseif action == "joinLobby" then
		local pad = data
		if not pad or not lobbies[pad] then return end
		if isPlayerInAnyLobby(player) then return end

		local lobby = lobbies[pad]
		if not lobby.active then return end
		if #lobby.players >= lobby.maxPlayers then return end
		if lobby.teleporting then return end

		table.insert(lobby.players, player)
		lobbyEvent:FireClient(player, "joinedLobby", pad)
		broadcastLobbyState(pad)

		-- Start countdown when full
		if #lobby.players >= lobby.maxPlayers then
			startCountdown(pad)
		end

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

-- ─── Cleanup on player leaving ───
Players.PlayerRemoving:Connect(function(player)
	local pad = findPadForPlayer(player)
	if pad then
		removePlayerFromLobby(player, pad)
	end
end)
