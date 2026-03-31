local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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
clipFrame.Size = UDim2.new(1, 0, 1, 0)
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

iconBg.MouseEnter:Connect(function()
	if radiationActive then
		tooltip.Visible = true
	end
end)

iconBg.MouseLeave:Connect(function()
	tooltip.Visible = false
end)

-- ─── Headache Visual Effect ───
local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Name = "RadiationCC"
colorCorrection.Enabled = false
colorCorrection.Parent = Lighting

local blur = Instance.new("BlurEffect")
blur.Name = "RadiationBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

-- ─── Listen for radiation updates from server ───
-- Use GetAttributeChangedSignal as backup detection
local radiationEvent = ReplicatedStorage:FindFirstChild("RadiationUpdate")

local function onRadiationUpdate(active, remaining, duration)
	radiationActive = active
	timeRemaining = remaining or 0
	totalDuration = duration or 60

	if active then
		container.Visible = true
		colorCorrection.Enabled = true
		blur.Enabled = true
	else
		container.Visible = false
		tooltip.Visible = false
		colorCorrection.Enabled = false
		colorCorrection.Saturation = 0
		colorCorrection.Contrast = 0
		colorCorrection.TintColor = Color3.fromRGB(255, 255, 255)
		blur.Enabled = false
		blur.Size = 0
	end
end

-- Connect immediately if event exists, otherwise wait for it
if radiationEvent then
	radiationEvent.OnClientEvent:Connect(onRadiationUpdate)
else
	task.spawn(function()
		radiationEvent = ReplicatedStorage:WaitForChild("RadiationUpdate")
		radiationEvent.OnClientEvent:Connect(onRadiationUpdate)
	end)
end

-- Also watch the player attribute as a backup trigger
player:GetAttributeChangedSignal("RadiationSick"):Connect(function()
	local sick = player:GetAttribute("RadiationSick")
	if sick and not radiationActive then
		onRadiationUpdate(true, 60, 60)
	elseif not sick and radiationActive then
		onRadiationUpdate(false, 0, 60)
	end
end)

-- ─── Frame update: icon timer + headache + confused movement ───
-- Use BindToRenderStep at priority AFTER default controls (200+)
-- so our humanoid:Move() overrides the PlayerModule's movement
RunService:BindToRenderStep("RadiationEffects", Enum.RenderPriority.Camera.Value - 1, function()
	if not radiationActive then return end

	local camera = workspace.CurrentCamera

	-- Update clip frame to show remaining portion
	local ratio = math.clamp(timeRemaining / totalDuration, 0, 1)
	clipFrame.Size = UDim2.new(1, 0, ratio, 0)

	-- Headache visual
	local pulse = math.sin(tick() * 3) * 0.5 + 0.5
	colorCorrection.Saturation = -0.4 - pulse * 0.2
	colorCorrection.Contrast = 0.1 + pulse * 0.15
	colorCorrection.TintColor = Color3.fromRGB(
		255,
		math.floor(230 - pulse * 40),
		math.floor(220 - pulse * 50)
	)
	blur.Size = 3 + pulse * 4

	-- Camera wobble
	if camera then
		local wobbleX = math.sin(tick() * 2.3) * 0.012
		local wobbleY = math.cos(tick() * 1.7) * 0.008
		local wobbleZ = math.sin(tick() * 3.1) * 0.006
		camera.CFrame = camera.CFrame * CFrame.Angles(wobbleX, wobbleY, wobbleZ)
	end

	-- Confused movement: override AFTER default controls
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then return end

	-- Read which keys are currently held and apply reversed directions
	local moveDir = Vector3.new(0, 0, 0)
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		moveDir = moveDir + Vector3.new(0, 0, 1) -- backward
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		moveDir = moveDir + Vector3.new(0, 0, -1) -- forward
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		moveDir = moveDir + Vector3.new(1, 0, 0) -- right
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		moveDir = moveDir + Vector3.new(-1, 0, 0) -- left
	end

	if moveDir.Magnitude > 0 then
		moveDir = moveDir.Unit
	end

	humanoid:Move(moveDir, true)
end)
