local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Create vignette UI with a single radial image
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WaterVignette"
screenGui.DisplayOrder = 100
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Radial vignette using rbxassetid (standard radial gradient vignette)
local vignette = Instance.new("ImageLabel")
vignette.Name = "Vignette"
vignette.AnchorPoint = Vector2.new(0.5, 0.5)
vignette.Position = UDim2.new(0.5, 0, 0.5, 0)
vignette.Size = UDim2.new(1, 0, 1, 0)
vignette.BackgroundTransparency = 1
vignette.Image = "rbxassetid://330427473" -- standard radial vignette texture
vignette.ImageColor3 = Color3.fromRGB(15, 40, 10) -- dark toxic green
vignette.ImageTransparency = 1
vignette.ScaleType = Enum.ScaleType.Stretch
vignette.Parent = screenGui

-- Listen for vignette updates from server
local currentIntensity = 0
local targetIntensity = 0

local vignetteEvent = rs:WaitForChild("WaterVignette")
vignetteEvent.OnClientEvent:Connect(function(intensity)
	targetIntensity = intensity
end)

-- Smooth interpolation loop
RunService.Heartbeat:Connect(function(dt)
	currentIntensity = currentIntensity + (targetIntensity - currentIntensity) * math.min(1, dt * 3)

	-- At max intensity, image should be clearly visible (transparency ~0.15)
	vignette.ImageTransparency = 1 - (currentIntensity * 0.85)
end)
