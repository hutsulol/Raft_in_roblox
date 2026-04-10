-- RecruitmentSystem.client.lua
-- Shows a recruitment UI when the player presses E near a downed pirate.
-- The UI displays a success chance bar and two buttons: Recruit / Keep.
-- "Recruit" launches a bouncing-ball minigame; "Keep" kills the pirate.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local recruitEvent = ReplicatedStorage:WaitForChild("RecruitPirate")

-- ═══════════════════════════════════════════════════════════════════════
-- State
-- ═══════════════════════════════════════════════════════════════════════
local currentPirate = nil
local uiOpen = false
local minigameRunning = false

-- ═══════════════════════════════════════════════════════════════════════
-- UI construction
-- ═══════════════════════════════════════════════════════════════════════

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RecruitmentGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ─── Hint label (shows when aiming at a downed pirate) ───────────────
local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "HintLabel"
hintLabel.Size = UDim2.new(0, 250, 0, 36)
hintLabel.Position = UDim2.new(0.5, -125, 0.65, 0)
hintLabel.BackgroundTransparency = 1
hintLabel.Text = "[E] Recruit"
hintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
hintLabel.TextStrokeTransparency = 0.4
hintLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
hintLabel.TextScaled = true
hintLabel.Font = Enum.Font.GothamBold
hintLabel.Visible = false
hintLabel.Parent = screenGui

-- ─── Main panel ──────────────────────────────────────────────────────
local panel = Instance.new("Frame")
panel.Name = "RecruitPanel"
panel.Size = UDim2.new(0, 360, 0, 210)
panel.Position = UDim2.new(0.5, -180, 0.5, -105)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local panelStroke = Instance.new("UIStroke")
panelStroke.Thickness = 2
panelStroke.Color = Color3.fromRGB(180, 160, 100)
panelStroke.Parent = panel

-- Title
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 36)
title.Position = UDim2.new(0, 0, 0, 8)
title.BackgroundTransparency = 1
title.Text = "Recruit Pirate?"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.Parent = panel

-- ─── Chance bar / minigame track ─────────────────────────────────────
local TRACK_HEIGHT = 44
local BALL_SIZE = 32

local trackBg = Instance.new("Frame")
trackBg.Name = "Track"
trackBg.Size = UDim2.new(0.88, 0, 0, TRACK_HEIGHT)
trackBg.Position = UDim2.new(0.06, 0, 0, 52)
trackBg.BackgroundColor3 = Color3.fromRGB(220, 220, 220) -- white zone
trackBg.BorderSizePixel = 0
trackBg.ClipsDescendants = true
trackBg.Parent = panel

Instance.new("UICorner", trackBg).CornerRadius = UDim.new(0, 8)

local trackStroke = Instance.new("UIStroke")
trackStroke.Thickness = 2
trackStroke.Color = Color3.fromRGB(60, 60, 60)
trackStroke.Parent = trackBg

-- Green zone (left portion)
local greenZone = Instance.new("Frame")
greenZone.Name = "GreenZone"
greenZone.Size = UDim2.new(0.7, 0, 1, 0)
greenZone.BackgroundColor3 = Color3.fromRGB(70, 190, 70)
greenZone.BorderSizePixel = 0
greenZone.Parent = trackBg

Instance.new("UICorner", greenZone).CornerRadius = UDim.new(0, 8)

-- Divider line
local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.Size = UDim2.new(0, 2, 1, 0)
divider.Position = UDim2.new(0.7, -1, 0, 0)
divider.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
divider.BorderSizePixel = 0
divider.ZIndex = 2
divider.Parent = trackBg

-- Chance text
local chanceLabel = Instance.new("TextLabel")
chanceLabel.Size = UDim2.new(1, 0, 1, 0)
chanceLabel.BackgroundTransparency = 1
chanceLabel.Text = "70%"
chanceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
chanceLabel.TextScaled = true
chanceLabel.Font = Enum.Font.GothamBold
chanceLabel.TextStrokeTransparency = 0.4
chanceLabel.ZIndex = 3
chanceLabel.Parent = trackBg

-- Ball (red circle, hidden until minigame starts)
local ball = Instance.new("Frame")
ball.Name = "Ball"
ball.Size = UDim2.new(0, BALL_SIZE, 0, BALL_SIZE)
ball.Position = UDim2.new(0, 0, 0.5, -BALL_SIZE / 2)
ball.BackgroundColor3 = Color3.fromRGB(210, 40, 40)
ball.BorderSizePixel = 0
ball.Visible = false
ball.ZIndex = 4
ball.Parent = trackBg

Instance.new("UICorner", ball).CornerRadius = UDim.new(0.5, 0)

local ballStroke = Instance.new("UIStroke")
ballStroke.Thickness = 2
ballStroke.Color = Color3.fromRGB(140, 20, 20)
ballStroke.Parent = ball

-- ─── Buttons ─────────────────────────────────────────────────────────
local function makeButton(name, text, color, posX)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0.4, 0, 0, 42)
	btn.Position = UDim2.new(posX, 0, 0, 110)
	btn.BackgroundColor3 = color
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextScaled = true
	btn.Font = Enum.Font.GothamBold
	btn.BorderSizePixel = 0
	btn.Parent = panel
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
	return btn
end

local recruitBtn = makeButton("RecruitBtn", "Recruit", Color3.fromRGB(60, 160, 60), 0.06)
local keepBtn = makeButton("KeepBtn", "Keep", Color3.fromRGB(180, 50, 50), 0.54)

-- ─── Result label ────────────────────────────────────────────────────
local resultLabel = Instance.new("TextLabel")
resultLabel.Name = "ResultLabel"
resultLabel.Size = UDim2.new(1, 0, 0, 36)
resultLabel.Position = UDim2.new(0, 0, 0, 165)
resultLabel.BackgroundTransparency = 1
resultLabel.Text = ""
resultLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
resultLabel.TextScaled = true
resultLabel.Font = Enum.Font.GothamBold
resultLabel.TextStrokeTransparency = 0.4
resultLabel.Parent = panel

-- ─── Recruited notification (top of screen, temporary) ───────────────
local function showNotification(text, color)
	local notif = Instance.new("TextLabel")
	notif.Size = UDim2.new(0, 300, 0, 50)
	notif.Position = UDim2.new(0.5, -150, 0, -60)
	notif.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	notif.BackgroundTransparency = 0.2
	notif.Text = text
	notif.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	notif.TextScaled = true
	notif.Font = Enum.Font.GothamBold
	notif.TextStrokeTransparency = 0.5
	notif.BorderSizePixel = 0
	notif.Parent = screenGui
	Instance.new("UICorner", notif).CornerRadius = UDim.new(0, 10)

	-- Slide in
	TweenService:Create(notif, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -150, 0, 20),
	}):Play()

	-- Fade out after 2.5s
	task.delay(2.5, function()
		local fadeOut = TweenService:Create(notif, TweenInfo.new(0.5), {
			Position = UDim2.new(0.5, -150, 0, -60),
			BackgroundTransparency = 1,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			notif:Destroy()
		end)
	end)
end

-- ═══════════════════════════════════════════════════════════════════════
-- Helpers
-- ═══════════════════════════════════════════════════════════════════════

local function closeUI()
	panel.Visible = false
	hintLabel.Visible = false
	ball.Visible = false
	recruitBtn.Visible = true
	keepBtn.Visible = true
	chanceLabel.Visible = true
	resultLabel.Text = ""
	uiOpen = false
	minigameRunning = false
	currentPirate = nil
end

local function findDownedPirateNearby()
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local playerPos = hrp.Position

	local closest, closestDist = nil, 15
	for _, child in workspace:GetChildren() do
		if child:IsA("Model")
			and child:GetAttribute("Downed")
			and not child:GetAttribute("Claimed")
		then
			local pHRP = child:FindFirstChild("HumanoidRootPart")
				or child:FindFirstChild("Torso")
				or child:FindFirstChildWhichIsA("BasePart", true)
			if pHRP then
				local d = (playerPos - pHRP.Position).Magnitude
				if d < closestDist then
					closest = child
					closestDist = d
				end
			end
		end
	end
	return closest
end

-- Check if the player is looking roughly toward the pirate
local function isLookingAtPirate(pirate)
	local char = player.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local pHRP = pirate:FindFirstChild("HumanoidRootPart")
		or pirate:FindFirstChild("Torso")
		or pirate:FindFirstChildWhichIsA("BasePart", true)
	if not pHRP then return false end

	local look = camera.CFrame.LookVector
	local toTarget = (pHRP.Position - camera.CFrame.Position).Unit
	return look:Dot(toTarget) > 0.5 -- roughly within ±60° cone
end

-- ═══════════════════════════════════════════════════════════════════════
-- Ball physics minigame
-- ═══════════════════════════════════════════════════════════════════════

local function runMinigame(chance)
	minigameRunning = true
	recruitBtn.Visible = false
	keepBtn.Visible = false
	chanceLabel.Visible = false
	resultLabel.Text = ""
	ball.Visible = true

	local trackWidth = trackBg.AbsoluteSize.X - BALL_SIZE
	if trackWidth <= 0 then trackWidth = 300 end

	-- 1-D physics: ball bounces between x=0 and x=1
	local x = 0
	local velocity = math.random(250, 450) / 100 -- 2.5 – 4.5 units/s
	local damping = 0.6   -- speed retained per bounce
	local friction = 0.4  -- deceleration per second
	local stopThreshold = 0.02

	ball.Position = UDim2.new(0, 0, 0.5, -BALL_SIZE / 2)

	local startTime = tick()
	local MAX_TIME = 10

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not minigameRunning then
			if conn then conn:Disconnect() end
			return
		end

		-- Friction
		if velocity > 0 then
			velocity = math.max(0, velocity - friction * dt)
		else
			velocity = math.min(0, velocity + friction * dt)
		end

		-- Move
		x = x + velocity * dt

		-- Bounce off walls
		if x > 1 then
			x = 2 - x
			velocity = -velocity * damping
		elseif x < 0 then
			x = -x
			velocity = -velocity * damping
		end

		x = math.clamp(x, 0, 1)

		-- Update visual
		ball.Position = UDim2.new(0, x * trackWidth, 0.5, -BALL_SIZE / 2)

		-- Check if ball has stopped
		if math.abs(velocity) < stopThreshold or (tick() - startTime) > MAX_TIME then
			conn:Disconnect()

			local successZone = (chance or 70) / 100
			local success = x <= successZone

			if success then
				resultLabel.Text = "SUCCESS! Pirate Recruited!"
				resultLabel.TextColor3 = Color3.fromRGB(80, 255, 80)
				ball.BackgroundColor3 = Color3.fromRGB(80, 255, 80)
				if currentPirate then
					recruitEvent:FireServer("recruit", currentPirate)
				end
			else
				resultLabel.Text = "FAILED..."
				resultLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
				if currentPirate then
					recruitEvent:FireServer("fail", currentPirate)
				end
			end

			task.delay(2.5, function()
				closeUI()
			end)
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════
-- Button handlers
-- ═══════════════════════════════════════════════════════════════════════

recruitBtn.MouseButton1Click:Connect(function()
	if not currentPirate or minigameRunning then return end
	local chance = currentPirate:GetAttribute("RecruitChance") or 70
	runMinigame(chance)
end)

keepBtn.MouseButton1Click:Connect(function()
	if not currentPirate or minigameRunning then return end
	recruitEvent:FireServer("keep", currentPirate)
	closeUI()
end)

-- ═══════════════════════════════════════════════════════════════════════
-- E key interaction
-- ═══════════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.E then return end

	if uiOpen and not minigameRunning then
		closeUI()
		return
	end

	if uiOpen then return end

	local pirate = findDownedPirateNearby()
	if pirate and isLookingAtPirate(pirate) then
		currentPirate = pirate
		uiOpen = true

		local chance = pirate:GetAttribute("RecruitChance") or 70
		greenZone.Size = UDim2.new(chance / 100, 0, 1, 0)
		divider.Position = UDim2.new(chance / 100, -1, 0, 0)
		chanceLabel.Text = tostring(chance) .. "%"

		ball.Visible = false
		ball.BackgroundColor3 = Color3.fromRGB(210, 40, 40)
		recruitBtn.Visible = true
		keepBtn.Visible = true
		chanceLabel.Visible = true
		resultLabel.Text = ""
		panel.Visible = true
	end
end)

-- ═══════════════════════════════════════════════════════════════════════
-- Hint label + proximity validation loop
-- ═══════════════════════════════════════════════════════════════════════

RunService.RenderStepped:Connect(function()
	-- Show "[E] Recruit" hint when looking at a downed pirate nearby
	if not uiOpen then
		local pirate = findDownedPirateNearby()
		if pirate and isLookingAtPirate(pirate) then
			hintLabel.Visible = true
		else
			hintLabel.Visible = false
		end
	else
		hintLabel.Visible = false
	end

	-- Close UI if pirate destroyed or player moved too far
	if uiOpen and not minigameRunning and currentPirate then
		if not currentPirate.Parent then
			closeUI()
			return
		end
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			local pHRP = currentPirate:FindFirstChild("HumanoidRootPart")
				or currentPirate:FindFirstChild("Torso")
				or currentPirate:FindFirstChildWhichIsA("BasePart", true)
			if pHRP and (char.HumanoidRootPart.Position - pHRP.Position).Magnitude > 20 then
				closeUI()
			end
		end
	end
end)

-- ═══════════════════════════════════════════════════════════════════════
-- Server notifications
-- ═══════════════════════════════════════════════════════════════════════

recruitEvent.OnClientEvent:Connect(function(action, data)
	if action == "recruited" then
		showNotification("Pirate Recruited!  (Total: " .. tostring(data) .. ")", Color3.fromRGB(80, 255, 80))
	elseif action == "failed" then
		showNotification("Recruitment Failed", Color3.fromRGB(255, 100, 100))
	end
end)
