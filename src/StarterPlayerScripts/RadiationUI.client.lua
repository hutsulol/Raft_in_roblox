local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── UI Setup ───
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RadiationUI"
screenGui.DisplayOrder = 16
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Radiation icon (positioned above the three stat bars)
local icon = Instance.new("ImageLabel")
icon.Name = "RadiationIcon"
icon.AnchorPoint = Vector2.new(0, 1)
icon.Position = UDim2.new(0, 16, 1, -188)
icon.Size = UDim2.new(0, 36, 0, 36)
icon.BackgroundColor3 = Color3.fromRGB(60, 40, 20)
icon.BackgroundTransparency = 0.3
icon.Image = "rbxassetid://97523366830633"
icon.ScaleType = Enum.ScaleType.Stretch
icon.Visible = false
icon.Parent = screenGui

icon.ClipsDescendants = true

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = icon

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(90, 60, 30)
stroke.Thickness = 2
stroke.Parent = icon

-- ─── Cooldown overlay (grows top→bottom as radiation expires) ───
local cooldownOverlay = Instance.new("Frame")
cooldownOverlay.Name = "CooldownOverlay"
cooldownOverlay.AnchorPoint = Vector2.new(0, 0)
cooldownOverlay.Position = UDim2.new(0, 0, 0, 0)
cooldownOverlay.Size = UDim2.new(1, 0, 0, 0) -- starts hidden
cooldownOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
cooldownOverlay.BackgroundTransparency = 0.5
cooldownOverlay.BorderSizePixel = 0
cooldownOverlay.ZIndex = 2
cooldownOverlay.Parent = icon

-- ─── Tooltip (hover description) ───
-- Parented to screenGui (not icon) to avoid ClipsDescendants clipping
local tooltip = Instance.new("Frame")
tooltip.Name = "Tooltip"
tooltip.AnchorPoint = Vector2.new(0, 1)
tooltip.Position = UDim2.new(0, 16 + 36 + 8, 1, -188)
tooltip.Size = UDim2.new(0, 200, 0, 60)
tooltip.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
tooltip.BackgroundTransparency = 0.15
tooltip.Visible = false
tooltip.Parent = screenGui

local tooltipCorner = Instance.new("UICorner")
tooltipCorner.CornerRadius = UDim.new(0, 6)
tooltipCorner.Parent = tooltip

local tooltipStroke = Instance.new("UIStroke")
tooltipStroke.Color = Color3.fromRGB(120, 80, 30)
tooltipStroke.Thickness = 1.5
tooltipStroke.Parent = tooltip

local tooltipTitle = Instance.new("TextLabel")
tooltipTitle.Size = UDim2.new(1, -12, 0, 20)
tooltipTitle.Position = UDim2.new(0, 6, 0, 4)
tooltipTitle.BackgroundTransparency = 1
tooltipTitle.Text = "Radiation Sickness"
tooltipTitle.TextColor3 = Color3.fromRGB(255, 100, 100)
tooltipTitle.TextSize = 14
tooltipTitle.Font = Enum.Font.GothamBold
tooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
tooltipTitle.Parent = tooltip

local tooltipBody = Instance.new("TextLabel")
tooltipBody.Size = UDim2.new(1, -12, 0, 32)
tooltipBody.Position = UDim2.new(0, 6, 0, 24)
tooltipBody.BackgroundTransparency = 1
tooltipBody.Text = "Headache, increased hunger drain"
tooltipBody.TextColor3 = Color3.fromRGB(200, 200, 200)
tooltipBody.TextSize = 12
tooltipBody.Font = Enum.Font.Gotham
tooltipBody.TextXAlignment = Enum.TextXAlignment.Left
tooltipBody.TextWrapped = true
tooltipBody.Parent = tooltip

icon.MouseEnter:Connect(function()
	if icon.Visible then
		tooltip.Visible = true
	end
end)

icon.MouseLeave:Connect(function()
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

-- ─── Radiation timer tracking ───
local RADIATION_DURATION = 60
local radiationStartTime = 0

local radiationEvent = game:GetService("ReplicatedStorage"):WaitForChild("RadiationUpdate", 10)

if radiationEvent then
	radiationEvent.OnClientEvent:Connect(function(active, remaining, duration)
		if active then
			RADIATION_DURATION = duration or 60
			radiationStartTime = tick() - (RADIATION_DURATION - (remaining or RADIATION_DURATION))
		end
	end)
end

-- ─── Watch the RadiationSick attribute directly ───
local function onRadiationChanged()
	local sick = player:GetAttribute("RadiationSick") == true
	icon.Visible = sick
	colorCorrection.Enabled = sick
	blur.Enabled = sick

	if sick then
		-- If we don't have a start time yet, assume just started
		if radiationStartTime == 0 then
			radiationStartTime = tick()
		end
		cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
	else
		colorCorrection.Saturation = 0
		colorCorrection.Contrast = 0
		colorCorrection.TintColor = Color3.fromRGB(255, 255, 255)
		blur.Size = 0
		cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
		radiationStartTime = 0
	end
end

-- Connect to attribute changes
player:GetAttributeChangedSignal("RadiationSick"):Connect(onRadiationChanged)

-- Check initial state
onRadiationChanged()

-- ─── Headache pulsing effect + cooldown overlay while sick ───
game:GetService("RunService").Heartbeat:Connect(function()
	if not icon.Visible then return end

	local pulse = math.sin(tick() * 3) * 0.5 + 0.5
	colorCorrection.Saturation = -0.4 - pulse * 0.2
	colorCorrection.Contrast = 0.1 + pulse * 0.15
	colorCorrection.TintColor = Color3.fromRGB(
		255,
		math.floor(230 - pulse * 40),
		math.floor(220 - pulse * 50)
	)
	blur.Size = 3 + pulse * 4

	-- Update cooldown overlay (grows from top to bottom)
	local elapsed = tick() - radiationStartTime
	local progress = math.clamp(elapsed / RADIATION_DURATION, 0, 1)
	cooldownOverlay.Size = UDim2.new(1, 0, progress, 0)
end)
