-- LobbyClient.client.lua
-- Handles lobby UI: create group, join, waiting screen, leave button.
-- Place this in StarterPlayerScripts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local lobbyEvent = ReplicatedStorage:WaitForChild("LobbyEvent")

-- ─── State ───
local currentPad = nil
local inLobby = false
local screenGui = nil
local selectedMaxPlayers = 5
local hasSaveData = nil -- nil = unknown, true/false after check
local saveChecked = false

-- ─── Colors ───
local BG_COLOR = Color3.fromRGB(50, 50, 55)
local HEADER_COLOR = Color3.fromRGB(50, 110, 220)
local SLOT_COLOR = Color3.fromRGB(70, 70, 75)
local SLOT_SELECTED = Color3.fromRGB(50, 110, 220)
local CREATE_COLOR = Color3.fromRGB(80, 200, 80)
local LEAVE_COLOR = Color3.fromRGB(200, 60, 60)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)

-- ─── Close UI ───
local function closeUI()
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
end

-- ─── Create Group Selection UI ───
local function showCreateUI(pad)
	closeUI()
	currentPad = pad
	selectedMaxPlayers = 5

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LobbyCreateGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 70
	screenGui.Parent = playerGui

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.new(0, 480, 0, 320)
	main.Position = UDim2.new(0.5, -240, 0.5, -160)
	main.BackgroundColor3 = BG_COLOR
	main.BorderSizePixel = 0
	main.Parent = screenGui
	Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundColor3 = HEADER_COLOR
	header.BorderSizePixel = 0
	header.Parent = main
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)
	-- Fix bottom corners
	local fix = Instance.new("Frame")
	fix.Size = UDim2.new(1, 0, 0, 12)
	fix.Position = UDim2.new(0, 0, 1, -12)
	fix.BackgroundColor3 = HEADER_COLOR
	fix.BorderSizePixel = 0
	fix.Parent = header

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, 0, 1, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "Create Group"
	titleLbl.TextColor3 = TEXT_COLOR
	titleLbl.TextScaled = true
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.Parent = header

	-- Subtitle
	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -20, 0, 30)
	subtitle.Position = UDim2.new(0, 10, 0, 70)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Number of group members"
	subtitle.TextColor3 = Color3.fromRGB(200, 200, 200)
	subtitle.TextScaled = true
	subtitle.Font = Enum.Font.GothamBold
	subtitle.Parent = main

	-- Number buttons (1-5)
	local btnSize = 70
	local btnPad = 12
	local totalWidth = 5 * btnSize + 4 * btnPad
	local startX = (480 - totalWidth) / 2
	local numberBtns = {}

	for i = 1, 5 do
		local btn = Instance.new("TextButton")
		btn.Name = "Num_" .. i
		btn.Size = UDim2.new(0, btnSize, 0, btnSize)
		btn.Position = UDim2.new(0, startX + (i - 1) * (btnSize + btnPad), 0, 110)
		btn.BackgroundColor3 = i == selectedMaxPlayers and SLOT_SELECTED or SLOT_COLOR
		btn.Text = tostring(i)
		btn.TextColor3 = TEXT_COLOR
		btn.TextScaled = true
		btn.Font = Enum.Font.GothamBold
		btn.BorderSizePixel = 0
		btn.Parent = main
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)

		numberBtns[i] = btn

		btn.MouseButton1Click:Connect(function()
			selectedMaxPlayers = i
			for j = 1, 5 do
				numberBtns[j].BackgroundColor3 = j == i and SLOT_SELECTED or SLOT_COLOR
			end
		end)
	end

	-- Create button
	local createBtn = Instance.new("TextButton")
	createBtn.Size = UDim2.new(0, 200, 0, 60)
	createBtn.Position = UDim2.new(0.5, -100, 0, 210)
	createBtn.BackgroundColor3 = CREATE_COLOR
	createBtn.Text = "Create"
	createBtn.TextColor3 = TEXT_COLOR
	createBtn.TextScaled = true
	createBtn.Font = Enum.Font.GothamBold
	createBtn.BorderSizePixel = 0
	createBtn.Parent = main
	Instance.new("UICorner", createBtn).CornerRadius = UDim.new(0, 10)

	createBtn.MouseButton1Click:Connect(function()
		lobbyEvent:FireServer("createLobby", pad, selectedMaxPlayers)
	end)

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -44, 0, 8)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = TEXT_COLOR
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 5
	closeBtn.Parent = main
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

	closeBtn.MouseButton1Click:Connect(function()
		closeUI()
		currentPad = nil
	end)
end

-- ─── Waiting / In-Lobby UI ───
local function showLobbyUI(pad, state)
	closeUI()
	currentPad = pad

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LobbyWaitGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 70
	screenGui.Parent = playerGui

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.new(0, 420, 0, 300)
	main.Position = UDim2.new(0.5, -210, 0.5, -150)
	main.BackgroundColor3 = BG_COLOR
	main.BorderSizePixel = 0
	main.Parent = screenGui
	Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 50)
	header.BackgroundColor3 = HEADER_COLOR
	header.BorderSizePixel = 0
	header.Parent = main
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)
	local fix = Instance.new("Frame")
	fix.Size = UDim2.new(1, 0, 0, 12)
	fix.Position = UDim2.new(0, 0, 1, -12)
	fix.BackgroundColor3 = HEADER_COLOR
	fix.BorderSizePixel = 0
	fix.Parent = header

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, 0, 1, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "Lobby"
	titleLbl.TextColor3 = TEXT_COLOR
	titleLbl.TextScaled = true
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.Parent = header

	-- Player count
	local countLbl = Instance.new("TextLabel")
	countLbl.Name = "CountLabel"
	countLbl.Size = UDim2.new(1, -20, 0, 50)
	countLbl.Position = UDim2.new(0, 10, 0, 60)
	countLbl.BackgroundTransparency = 1
	countLbl.Text = (state.playerCount or 0) .. "/" .. (state.maxPlayers or 5)
	countLbl.TextColor3 = TEXT_COLOR
	countLbl.TextScaled = true
	countLbl.Font = Enum.Font.GothamBold
	countLbl.Parent = main

	-- Status text
	local statusLbl = Instance.new("TextLabel")
	statusLbl.Name = "StatusLabel"
	statusLbl.Size = UDim2.new(1, -20, 0, 30)
	statusLbl.Position = UDim2.new(0, 10, 0, 115)
	statusLbl.BackgroundTransparency = 1
	statusLbl.Font = Enum.Font.GothamBold
	statusLbl.TextScaled = true
	statusLbl.Parent = main

	if state.teleporting then
		statusLbl.Text = "Teleporting..."
		statusLbl.TextColor3 = Color3.fromRGB(100, 255, 100)
	elseif state.countdown and state.countdown > 0 then
		statusLbl.Text = "Starting in " .. state.countdown
		statusLbl.TextColor3 = Color3.fromRGB(255, 200, 80)
	else
		statusLbl.Text = "Waiting for players..."
		statusLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
	end

	-- Player list
	local listFrame = Instance.new("Frame")
	listFrame.Size = UDim2.new(1, -30, 0, 70)
	listFrame.Position = UDim2.new(0, 15, 0, 150)
	listFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	listFrame.BorderSizePixel = 0
	listFrame.Parent = main
	Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 8)

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.Padding = UDim.new(0, 2)
	listLayout.Parent = listFrame

	local listPad = Instance.new("UIPadding")
	listPad.PaddingLeft = UDim.new(0, 8)
	listPad.PaddingTop = UDim.new(0, 4)
	listPad.Parent = listFrame

	if state.playerNames then
		for _, name in state.playerNames do
			local pLbl = Instance.new("TextLabel")
			pLbl.Size = UDim2.new(1, -16, 0, 18)
			pLbl.BackgroundTransparency = 1
			pLbl.Text = name
			pLbl.TextColor3 = Color3.fromRGB(180, 220, 255)
			pLbl.Font = Enum.Font.Gotham
			pLbl.TextSize = 14
			pLbl.TextXAlignment = Enum.TextXAlignment.Left
			pLbl.Parent = listFrame
		end
	end

	-- Leave button
	local leaveBtn = Instance.new("TextButton")
	leaveBtn.Size = UDim2.new(0, 160, 0, 45)
	leaveBtn.Position = UDim2.new(0.5, -80, 1, -55)
	leaveBtn.BackgroundColor3 = LEAVE_COLOR
	leaveBtn.Text = "Leave"
	leaveBtn.TextColor3 = TEXT_COLOR
	leaveBtn.TextScaled = true
	leaveBtn.Font = Enum.Font.GothamBold
	leaveBtn.BorderSizePixel = 0
	leaveBtn.Parent = main
	Instance.new("UICorner", leaveBtn).CornerRadius = UDim.new(0, 10)

	leaveBtn.MouseButton1Click:Connect(function()
		lobbyEvent:FireServer("leaveLobby")
	end)
end

-- ─── Join prompt for pads with active lobbies ───
local function showJoinUI(pad, state)
	closeUI()
	currentPad = pad

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LobbyJoinGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 70
	screenGui.Parent = playerGui

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.new(0, 380, 0, 220)
	main.Position = UDim2.new(0.5, -190, 0.5, -110)
	main.BackgroundColor3 = BG_COLOR
	main.BorderSizePixel = 0
	main.Parent = screenGui
	Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 50)
	header.BackgroundColor3 = HEADER_COLOR
	header.BorderSizePixel = 0
	header.Parent = main
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)
	local fix = Instance.new("Frame")
	fix.Size = UDim2.new(1, 0, 0, 12)
	fix.Position = UDim2.new(0, 0, 1, -12)
	fix.BackgroundColor3 = HEADER_COLOR
	fix.BorderSizePixel = 0
	fix.Parent = header

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, 0, 1, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "Join Lobby"
	titleLbl.TextColor3 = TEXT_COLOR
	titleLbl.TextScaled = true
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.Parent = header

	-- Info
	local infoLbl = Instance.new("TextLabel")
	infoLbl.Size = UDim2.new(1, -20, 0, 40)
	infoLbl.Position = UDim2.new(0, 10, 0, 60)
	infoLbl.BackgroundTransparency = 1
	infoLbl.Text = "Players: " .. (state.playerCount or 0) .. "/" .. (state.maxPlayers or 5)
		.. "\nOwner: " .. (state.ownerName or "—")
	infoLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
	infoLbl.TextScaled = true
	infoLbl.Font = Enum.Font.Gotham
	infoLbl.Parent = main

	local full = (state.playerCount or 0) >= (state.maxPlayers or 5)

	-- Join button
	local joinBtn = Instance.new("TextButton")
	joinBtn.Size = UDim2.new(0, 160, 0, 50)
	joinBtn.Position = UDim2.new(0.5, -80, 0, 120)
	joinBtn.BackgroundColor3 = full and Color3.fromRGB(100, 100, 100) or CREATE_COLOR
	joinBtn.Text = full and "Full" or "Join"
	joinBtn.TextColor3 = TEXT_COLOR
	joinBtn.TextScaled = true
	joinBtn.Font = Enum.Font.GothamBold
	joinBtn.BorderSizePixel = 0
	joinBtn.Parent = main
	Instance.new("UICorner", joinBtn).CornerRadius = UDim.new(0, 10)

	if not full then
		joinBtn.MouseButton1Click:Connect(function()
			lobbyEvent:FireServer("joinLobby", pad)
		end)
	end

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -44, 0, 4)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = TEXT_COLOR
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 5
	closeBtn.Parent = main
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

	closeBtn.MouseButton1Click:Connect(function()
		closeUI()
		currentPad = nil
	end)
end

-- ─── Continue Save Prompt ───
local function showContinueUI(pad)
	closeUI()
	currentPad = pad

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LobbyContinueGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 70
	screenGui.Parent = playerGui

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.new(0, 460, 0, 260)
	main.Position = UDim2.new(0.5, -230, 0.5, -130)
	main.BackgroundColor3 = BG_COLOR
	main.BorderSizePixel = 0
	main.Parent = screenGui
	Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 55)
	header.BackgroundColor3 = HEADER_COLOR
	header.BorderSizePixel = 0
	header.Parent = main
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)
	local fix = Instance.new("Frame")
	fix.Size = UDim2.new(1, 0, 0, 12)
	fix.Position = UDim2.new(0, 0, 1, -12)
	fix.BackgroundColor3 = HEADER_COLOR
	fix.BorderSizePixel = 0
	fix.Parent = header

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, 0, 1, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "Saved Raft Found"
	titleLbl.TextColor3 = TEXT_COLOR
	titleLbl.TextScaled = true
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.Parent = header

	-- Message
	local msgLbl = Instance.new("TextLabel")
	msgLbl.Size = UDim2.new(1, -30, 0, 60)
	msgLbl.Position = UDim2.new(0, 15, 0, 65)
	msgLbl.BackgroundTransparency = 1
	msgLbl.Text = "Your previous raft was saved.\nDo you want to continue where you left off?"
	msgLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
	msgLbl.TextScaled = true
	msgLbl.Font = Enum.Font.Gotham
	msgLbl.TextWrapped = true
	msgLbl.Parent = main

	-- Continue button
	local continueBtn = Instance.new("TextButton")
	continueBtn.Size = UDim2.new(0, 180, 0, 50)
	continueBtn.Position = UDim2.new(0.5, -190, 0, 145)
	continueBtn.BackgroundColor3 = CREATE_COLOR
	continueBtn.Text = "Continue"
	continueBtn.TextColor3 = TEXT_COLOR
	continueBtn.TextScaled = true
	continueBtn.Font = Enum.Font.GothamBold
	continueBtn.BorderSizePixel = 0
	continueBtn.Parent = main
	Instance.new("UICorner", continueBtn).CornerRadius = UDim.new(0, 10)

	continueBtn.MouseButton1Click:Connect(function()
		lobbyEvent:FireServer("chooseContinue", true)
		showCreateUI(pad)
	end)

	-- New Game button
	local newBtn = Instance.new("TextButton")
	newBtn.Size = UDim2.new(0, 180, 0, 50)
	newBtn.Position = UDim2.new(0.5, 10, 0, 145)
	newBtn.BackgroundColor3 = SLOT_COLOR
	newBtn.Text = "New Game"
	newBtn.TextColor3 = TEXT_COLOR
	newBtn.TextScaled = true
	newBtn.Font = Enum.Font.GothamBold
	newBtn.BorderSizePixel = 0
	newBtn.Parent = main
	Instance.new("UICorner", newBtn).CornerRadius = UDim.new(0, 10)

	newBtn.MouseButton1Click:Connect(function()
		lobbyEvent:FireServer("chooseContinue", false)
		showCreateUI(pad)
	end)

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -44, 0, 8)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = TEXT_COLOR
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 5
	closeBtn.Parent = main
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

	closeBtn.MouseButton1Click:Connect(function()
		closeUI()
		currentPad = nil
	end)
end

-- Pending pad waiting for save check result
local pendingPad = nil

-- ─── Events ───
lobbyEvent.OnClientEvent:Connect(function(action, pad, data)
	if action == "touchedPad" then
		-- Touched a pad, request its state
		lobbyEvent:FireServer("requestPadState", pad)

	elseif action == "padState" then
		-- Got pad state back
		local state = data
		if state.active then
			-- Lobby exists — show join UI
			showJoinUI(pad, state)
		else
			-- No lobby — check if player has a save first
			if not saveChecked then
				pendingPad = pad
				lobbyEvent:FireServer("checkSave")
			elseif hasSaveData then
				showContinueUI(pad)
			else
				showCreateUI(pad)
			end
		end

	elseif action == "saveStatus" then
		-- Response from save check
		hasSaveData = pad -- pad arg is actually the boolean
		saveChecked = true
		if pendingPad then
			local p = pendingPad
			pendingPad = nil
			if hasSaveData then
				showContinueUI(p)
			else
				showCreateUI(p)
			end
		end

	elseif action == "joinedLobby" then
		inLobby = true
		currentPad = pad
		-- Will receive lobbyState next

	elseif action == "lobbyState" then
		local state = data
		if inLobby then
			showLobbyUI(pad, state)
		end

	elseif action == "leftLobby" then
		inLobby = false
		currentPad = nil
		closeUI()

	elseif action == "teleportFailed" then
		-- pad is actually the error string here
		inLobby = false
		closeUI()
	end
end)
