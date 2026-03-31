local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local radiationEvent = ReplicatedStorage:WaitForChild("RadiationUpdate")

-- ─── State ───
local radiationActive = false
local timeRemaining = 0
local totalDuration = 60

-- ─── UI Setup ───
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RadiationUI"
screenGui.DisplayOrder = 16
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Main container (positioned above the three stat bars)
local container = Instance.new("Frame")
container.Name = "RadiationContainer"
container.AnchorPoint = Vector2.new(0, 1)
container.Position = UDim2.new(0, 16, 1, -188)
container.Size = UDim2.new(0, 36, 0, 36)
container.BackgroundTransparency = 1
container.Visible = false
container.Parent = screenGui

-- Background icon (dimmed, always visible when sick)
local iconBg = Instance.new("ImageLabel")
iconBg.Name = "IconBg"
iconBg.Size = UDim2.new(1, 0, 1, 0)
iconBg.BackgroundColor3 = Color3.fromRGB(60, 40, 20)
iconBg.BackgroundTransparency = 0.3
iconBg.Image = "rbxassetid://97523366830633"
iconBg.ImageTransparency = 0.7
iconBg.ScaleType = Enum.ScaleType.Stretch
iconBg.Parent = container

local iconBgCorner = Instance.new("UICorner")
iconBgCorner.CornerRadius = UDim.new(0, 6)
iconBgCorner.Parent = iconBg

local iconBgStroke = Instance.new("UIStroke")
iconBgStroke.Color = Color3.fromRGB(90, 60, 30)
iconBgStroke.Thickness = 2
iconBgStroke.Parent = iconBg

-- Clip container for the timer reveal (clips from top as time passes)
local clipFrame = Instance.new("Frame")
clipFrame.Name = "ClipFrame"
clipFrame.AnchorPoint = Vector2.new(0, 1)
clipFrame.Position = UDim2.new(0, 0, 1, 0)
clipFrame.Size = UDim2.new(1, 0, 1, 0) -- full height = full icon
clipFrame.BackgroundTransparency = 1
clipFrame.ClipDescendants = true
clipFrame.Parent = container

-- Foreground icon (bright, inside clip frame)
local iconFg = Instance.new("ImageLabel")
iconFg.Name = "IconFg"
iconFg.AnchorPoint = Vector2.new(0, 1)
iconFg.Position = UDim2.new(0, 0, 1, 0)
iconFg.Size = UDim2.new(1, 0, 1, 0)
iconFg.BackgroundTransparency = 1
iconFg.Image = "rbxassetid://97523366830633"
iconFg.ImageTransparency = 0
iconFg.ScaleType = Enum.ScaleType.Stretch
iconFg.Parent = clipFrame

-- ─── Tooltip (hover description) ───
local tooltip = Instance.new("Frame")
tooltip.Name = "Tooltip"
tooltip.AnchorPoint = Vector2.new(0, 1)
tooltip.Position = UDim2.new(1, 8, 0, 0)
tooltip.Size = UDim2.new(0, 180, 0, 90)
tooltip.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
tooltip.BackgroundTransparency = 0.15
tooltip.Visible = false
tooltip.Parent = container

local tooltipCorner = Instance.new("UICorner")
tooltipCorner.CornerRadius = UDim.new(0, 6)
tooltipCorner.Parent = tooltip

local tooltipStroke = Instance.new("UIStroke")
tooltipStroke.Color = Color3.fromRGB(120, 80, 30)
tooltipStroke.Thickness = 1.5
tooltipStroke.Parent = tooltip

local tooltipTitle = Instance.new("TextLabel")
tooltipTitle.Name = "Title"
tooltipTitle.Size = UDim2.new(1, -12, 0, 22)
tooltipTitle.Position = UDim2.new(0, 6, 0, 4)
tooltipTitle.BackgroundTransparency = 1
tooltipTitle.Text = "Radiation Sickness"
tooltipTitle.TextColor3 = Color3.fromRGB(255, 100, 100)
tooltipTitle.TextSize = 14
tooltipTitle.Font = Enum.Font.GothamBold
tooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
tooltipTitle.Parent = tooltip

local tooltipBody = Instance.new("TextLabel")
tooltipBody.Name = "Body"
tooltipBody.Size = UDim2.new(1, -12, 0, 60)
tooltipBody.Position = UDim2.new(0, 6, 0, 26)
tooltipBody.BackgroundTransparency = 1
tooltipBody.Text = "- Headache\n- Increased hunger\n- Fatigue (cannot deal damage)"
tooltipBody.TextColor3 = Color3.fromRGB(200, 200, 200)
tooltipBody.TextSize = 12
tooltipBody.Font = Enum.Font.Gotham
tooltipBody.TextXAlignment = Enum.TextXAlignment.Left
tooltipBody.TextYAlignment = Enum.TextYAlignment.Top
tooltipBody.TextWrapped = true
tooltipBody.Parent = tooltip

-- Hover detection
iconBg.MouseEnter:Connect(function()
	if radiationActive then
		tooltip.Visible = true
	end
end)

iconBg.MouseLeave:Connect(function()
	tooltip.Visible = false
end)

-- ─── Headache Visual Effect (ColorCorrection + blur) ───
local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Name = "RadiationCC"
colorCorrection.Brightness = 0
colorCorrection.Contrast = 0
colorCorrection.Saturation = 0
colorCorrection.TintColor = Color3.fromRGB(255, 255, 255)
colorCorrection.Enabled = false
colorCorrection.Parent = Lighting

local blur = Instance.new("BlurEffect")
blur.Name = "RadiationBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

-- ─── Confused Movement (swap WASD) ───
local movementConfused = false

local function enableConfusedMovement()
	if movementConfused then return end
	movementConfused = true

	-- Override WASD with swapped directions
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then return end

	ContextActionService:BindAction("RadiationMoveForward", function(_, state)
		if state == Enum.UserInputState.Begin then
			humanoid:Move(Vector3.new(0, 0, 1), true) -- backward
		elseif state == Enum.UserInputState.End then
			humanoid:Move(Vector3.new(0, 0, 0), true)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.W)

	ContextActionService:BindAction("RadiationMoveBackward", function(_, state)
		if state == Enum.UserInputState.Begin then
			humanoid:Move(Vector3.new(0, 0, -1), true) -- forward
		elseif state == Enum.UserInputState.End then
			humanoid:Move(Vector3.new(0, 0, 0), true)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.S)

	ContextActionService:BindAction("RadiationMoveLeft", function(_, state)
		if state == Enum.UserInputState.Begin then
			humanoid:Move(Vector3.new(1, 0, 0), true) -- right
		elseif state == Enum.UserInputState.End then
			humanoid:Move(Vector3.new(0, 0, 0), true)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.A)

	ContextActionService:BindAction("RadiationMoveRight", function(_, state)
		if state == Enum.UserInputState.Begin then
			humanoid:Move(Vector3.new(-1, 0, 0), true) -- left
		elseif state == Enum.UserInputState.End then
			humanoid:Move(Vector3.new(0, 0, 0), true)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.D)
end

local function disableConfusedMovement()
	if not movementConfused then return end
	movementConfused = false

	ContextActionService:UnbindAction("RadiationMoveForward")
	ContextActionService:UnbindAction("RadiationMoveBackward")
	ContextActionService:UnbindAction("RadiationMoveLeft")
	ContextActionService:UnbindAction("RadiationMoveRight")
end

-- ─── Enable/Disable radiation effects ───
local function enableEffects()
	colorCorrection.Enabled = true
	blur.Enabled = true
	enableConfusedMovement()
end

local function disableEffects()
	colorCorrection.Enabled = false
	colorCorrection.Brightness = 0
	colorCorrection.Contrast = 0
	colorCorrection.Saturation = 0
	colorCorrection.TintColor = Color3.fromRGB(255, 255, 255)
	blur.Enabled = false
	blur.Size = 0
	disableConfusedMovement()
end

-- ─── Listen for radiation updates from server ───
radiationEvent.OnClientEvent:Connect(function(active, remaining, duration)
	radiationActive = active
	timeRemaining = remaining or 0
	totalDuration = duration or 60

	if active then
		container.Visible = true
		enableEffects()
	else
		container.Visible = false
		tooltip.Visible = false
		disableEffects()
	end
end)

-- ─── Frame update: icon timer + headache effects ───
RunService.RenderStepped:Connect(function(dt)
	if not radiationActive then return end

	-- Update clip frame to show remaining portion (bottom-up reveal)
	local ratio = math.clamp(timeRemaining / totalDuration, 0, 1)
	clipFrame.Size = UDim2.new(1, 0, ratio, 0)

	-- Headache visual: pulsing color correction + blur
	local pulse = math.sin(tick() * 3) * 0.5 + 0.5 -- 0 to 1 pulsing
	colorCorrection.Saturation = -0.4 - pulse * 0.2
	colorCorrection.Contrast = 0.1 + pulse * 0.15
	colorCorrection.TintColor = Color3.fromRGB(
		255,
		math.floor(230 - pulse * 40),
		math.floor(220 - pulse * 50)
	)

	blur.Size = 3 + pulse * 4

	-- Camera wobble for headache feel
	local wobbleX = math.sin(tick() * 2.3) * 0.012
	local wobbleY = math.cos(tick() * 1.7) * 0.008
	local wobbleZ = math.sin(tick() * 3.1) * 0.006
	camera.CFrame = camera.CFrame * CFrame.Angles(wobbleX, wobbleY, wobbleZ)
end)

-- ─── Reset on respawn ───
player.CharacterAdded:Connect(function()
	if radiationActive then
		enableConfusedMovement()
	end
end)
