-- LobbyClient.client.lua
-- Handles lobby UI: create group, join, waiting screen, leave button.
-- Place this in StarterPlayerScripts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Only run in the lobby place, NOT in the ocean sub-place
local OCEAN_PLACE_ID = 128626393517258
if game.PlaceId == OCEAN_PLACE_ID then return end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local lobbyEvent = ReplicatedStorage:WaitForChild("LobbyEvent")

-- ─── State ───
local currentPad = nil
local inLobby = false
local screenGui = nil
local selectedMaxPlayers = 5
local continueGui = nil -- separate GUI for the continue prompt

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
local function showCreateUI(pad, isSavePad)
	closeUI()
	currentPad = pad
	selectedMaxPlayers = 5

	local headerTitle = isSavePad and "Return to Saved Game" or "Create Group"
	local subtitleText = "Number of group members"
	local headerColor = isSavePad and Color3.fromRGB(180, 120, 40) or HEADER_COLOR

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
	header.BackgroundColor3 = headerColor
	header.BorderSizePixel = 0
	header.Parent = main
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)
	-- Fix bottom corners
	local fix = Instance.new("Frame")
	fix.Size = UDim2.new(1, 0, 0, 12)
	fix.Position = UDim2.new(0, 0, 1, -12)
	fix.BackgroundColor3 = headerColor
	fix.BorderSizePixel = 0
	fix.Parent = header

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, 0, 1, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = headerTitle
	titleLbl.TextColor3 = TEXT_COLOR
	titleLbl.TextScaled = true
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.Parent = header

	-- Subtitle
	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -20, 0, 30)
	subtitle.Position = UDim2.new(0, 10, 0, 70)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = subtitleText
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

-- ─── Continue Save Prompt (shown automatically on join) ───
local function closeContinueUI()
	if continueGui then
		continueGui:Destroy()
		continueGui = nil
	end
end

local function showContinuePrompt()
	closeContinueUI()

	continueGui = Instance.new("ScreenGui")
	continueGui.Name = "ContinuePromptGui"
	continueGui.ResetOnSpawn = false
	continueGui.DisplayOrder = 80
	continueGui.Parent = playerGui

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.new(0, 520, 0, 320)
	main.Position = UDim2.new(0.5, -260, 0.5, -160)
	main.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
	main.BorderSizePixel = 0
	main.Parent = continueGui
	Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)

	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 65)
	header.BackgroundColor3 = HEADER_COLOR
	header.BorderSizePixel = 0
	header.Parent = main
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)
	local fix = Instance.new("Frame")
	fix.Size = UDim2.new(1, 0, 0, 14)
	fix.Position = UDim2.new(0, 0, 1, -14)
	fix.BackgroundColor3 = HEADER_COLOR
	fix.BorderSizePixel = 0
	fix.Parent = header

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -20, 1, 0)
	titleLbl.Position = UDim2.new(0, 10, 0, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "Continue?"
	titleLbl.TextColor3 = TEXT_COLOR
	titleLbl.TextScaled = true
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.Parent = header

	-- Message
	local msgLbl = Instance.new("TextLabel")
	msgLbl.Size = UDim2.new(1, -40, 0, 100)
	msgLbl.Position = UDim2.new(0, 20, 0, 80)
	msgLbl.BackgroundTransparency = 1
	msgLbl.Text = "Your previous server was disconnected, but your raft was saved. Do you want to continue where you left off?"
	msgLbl.TextColor3 = Color3.fromRGB(220, 220, 220)
	msgLbl.TextScaled = true
	msgLbl.Font = Enum.Font.Gotham
	msgLbl.TextWrapped = true
	msgLbl.Parent = main

	-- No button (red, left)
	local noBtn = Instance.new("TextButton")
	noBtn.Size = UDim2.new(0, 190, 0, 65)
	noBtn.Position = UDim2.new(0.5, -200, 0, 210)
	noBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	noBtn.Text = "No"
	noBtn.TextColor3 = TEXT_COLOR
	noBtn.TextScaled = true
	noBtn.Font = Enum.Font.GothamBold
	noBtn.BorderSizePixel = 0
	noBtn.Parent = main
	Instance.new("UICorner", noBtn).CornerRadius = UDim.new(0, 10)

	noBtn.MouseButton1Click:Connect(function()
		lobbyEvent:FireServer("declineSave")
		closeContinueUI()
	end)

	-- Yes button (green, right)
	local yesBtn = Instance.new("TextButton")
	yesBtn.Size = UDim2.new(0, 190, 0, 65)
	yesBtn.Position = UDim2.new(0.5, 10, 0, 210)
	yesBtn.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	yesBtn.Text = "Yes"
	yesBtn.TextColor3 = TEXT_COLOR
	yesBtn.TextScaled = true
	yesBtn.Font = Enum.Font.GothamBold
	yesBtn.BorderSizePixel = 0
	yesBtn.Parent = main
	Instance.new("UICorner", yesBtn).CornerRadius = UDim.new(0, 10)

	yesBtn.MouseButton1Click:Connect(function()
		yesBtn.Text = "Teleporting..."
		noBtn.Visible = false
		lobbyEvent:FireServer("continueSave")
	end)
end

-- ─── Events ───
lobbyEvent.OnClientEvent:Connect(function(action, pad, data)
	if action == "saveFound" then
		-- Server detected a saved raft on join — show continue prompt
		showContinuePrompt()

	elseif action == "touchedPad" then
		-- Touched a pad, request its state
		lobbyEvent:FireServer("requestPadState", pad)

	elseif action == "noSaveData" then
		-- Player tried to create on save pad but has no save
		closeUI()
		local noSaveGui = Instance.new("ScreenGui")
		noSaveGui.Name = "NoSaveGui"
		noSaveGui.ResetOnSpawn = false
		noSaveGui.DisplayOrder = 75
		noSaveGui.Parent = playerGui

		local main = Instance.new("Frame")
		main.Size = UDim2.new(0, 400, 0, 180)
		main.Position = UDim2.new(0.5, -200, 0.5, -90)
		main.BackgroundColor3 = BG_COLOR
		main.BorderSizePixel = 0
		main.Parent = noSaveGui
		Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

		local msgLbl = Instance.new("TextLabel")
		msgLbl.Size = UDim2.new(1, -30, 0, 60)
		msgLbl.Position = UDim2.new(0, 15, 0, 20)
		msgLbl.BackgroundTransparency = 1
		msgLbl.Text = "You don't have a saved game yet.\nPlay a round first to create a save!"
		msgLbl.TextColor3 = Color3.fromRGB(255, 200, 100)
		msgLbl.TextScaled = true
		msgLbl.TextWrapped = true
		msgLbl.Font = Enum.Font.GothamBold
		msgLbl.Parent = main

		local okBtn = Instance.new("TextButton")
		okBtn.Size = UDim2.new(0, 140, 0, 50)
		okBtn.Position = UDim2.new(0.5, -70, 0, 100)
		okBtn.BackgroundColor3 = HEADER_COLOR
		okBtn.Text = "OK"
		okBtn.TextColor3 = TEXT_COLOR
		okBtn.TextScaled = true
		okBtn.Font = Enum.Font.GothamBold
		okBtn.BorderSizePixel = 0
		okBtn.Parent = main
		Instance.new("UICorner", okBtn).CornerRadius = UDim.new(0, 10)

		okBtn.MouseButton1Click:Connect(function()
			noSaveGui:Destroy()
		end)

	elseif action == "padState" then
		-- Got pad state back
		local state = data
		if state.active then
			showJoinUI(pad, state)
		else
			showCreateUI(pad, state.isSavePad)
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
		closeContinueUI()
	end
end)
