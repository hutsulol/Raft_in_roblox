local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Create vignette UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DamageVignette"
screenGui.DisplayOrder = 100
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local vignette = Instance.new("ImageLabel")
vignette.Name = "Vignette"
vignette.AnchorPoint = Vector2.new(0.5, 0.5)
vignette.Position = UDim2.new(0.5, 0, 0.5, 0)
vignette.Size = UDim2.new(1, 0, 1, 0)
vignette.BackgroundTransparency = 1
vignette.Image = "rbxassetid://116745772667617"
vignette.ImageTransparency = 1
vignette.ScaleType = Enum.ScaleType.Stretch
vignette.Parent = screenGui

-- Track current opacity for smooth transitions
local currentTransparency = 1
local targetTransparency = 1

local function onCharacterAdded(char)
	local hum = char:WaitForChild("Humanoid")

	hum.HealthChanged:Connect(function(newHealth)
		local ratio = newHealth / hum.MaxHealth
		-- Full health = fully transparent (1), no health = fully visible (0)
		targetTransparency = ratio
	end)

	-- Initialize
	targetTransparency = hum.Health / hum.MaxHealth
end

local char = player.Character
if char then
	task.spawn(onCharacterAdded, char)
end
player.CharacterAdded:Connect(function(newChar)
	currentTransparency = 1
	targetTransparency = 1
	onCharacterAdded(newChar)
end)

-- Smooth interpolation loop
RunService.Heartbeat:Connect(function(dt)
	currentTransparency = currentTransparency + (targetTransparency - currentTransparency) * math.min(1, dt * 5)
	vignette.ImageTransparency = currentTransparency
end)
