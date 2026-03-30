local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Create vignette UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WaterVignette"
screenGui.DisplayOrder = 100
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Four edge frames to create vignette effect
local edges = {}
local edgeConfigs = {
	{anchor = Vector2.new(0, 0), pos = UDim2.new(0, 0, 0, 0), size = UDim2.new(1, 0, 0.25, 0)},      -- top
	{anchor = Vector2.new(0, 1), pos = UDim2.new(0, 0, 1, 0), size = UDim2.new(1, 0, 0.25, 0)},      -- bottom
	{anchor = Vector2.new(0, 0), pos = UDim2.new(0, 0, 0, 0), size = UDim2.new(0.2, 0, 1, 0)},       -- left
	{anchor = Vector2.new(1, 0), pos = UDim2.new(1, 0, 0, 0), size = UDim2.new(0.2, 0, 1, 0)},       -- right
}

-- Gradient directions for each edge (fading inward)
local gradientConfigs = {
	{rotation = 180},  -- top: fade from top down
	{rotation = 0},    -- bottom: fade from bottom up
	{rotation = 90},   -- left: fade from left to right
	{rotation = -90},  -- right: fade from right to left
}

for i, config in edgeConfigs do
	local frame = Instance.new("Frame")
	frame.Name = "VignetteEdge" .. i
	frame.AnchorPoint = config.anchor
	frame.Position = config.pos
	frame.Size = config.size
	frame.BackgroundColor3 = Color3.new(0, 0.15, 0) -- dark green tint for toxic water
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Rotation = gradientConfigs[i].rotation
	gradient.Parent = frame

	table.insert(edges, frame)
end

-- Listen for vignette updates from server
local currentIntensity = 0
local targetIntensity = 0

local vignetteEvent = rs:WaitForChild("WaterVignette")
vignetteEvent.OnClientEvent:Connect(function(intensity)
	targetIntensity = intensity
end)

-- Smooth interpolation loop
game:GetService("RunService").Heartbeat:Connect(function(dt)
	-- Lerp toward target for smooth transition
	currentIntensity = currentIntensity + (targetIntensity - currentIntensity) * math.min(1, dt * 3)

	-- Map intensity to transparency (1 = fully transparent, 0 = fully visible)
	-- At max intensity (1.0), edges should be quite visible (~0.3 transparency)
	local transparency = 1 - (currentIntensity * 0.7)

	for _, edge in edges do
		edge.BackgroundTransparency = transparency
	end
end)
