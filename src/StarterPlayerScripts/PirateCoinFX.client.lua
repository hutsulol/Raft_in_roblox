-- PirateCoinFX.client.lua
-- Feedback when pirate coins reach the player (server fires PirateCoinCollected
-- once per coin). Instead of a popup over the head per coin, we show ONE
-- screen-space tally slightly left + above the crosshair that SUMS rapid
-- pickups into a single growing "+N" and fades out once they stop.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ev = ReplicatedStorage:WaitForChild("PirateCoinCollected")

local COIN_ICON = "rbxassetid://93617165412571"
local OFFSET_X  = 110    -- px right of screen centre
local OFFSET_Y  = -35    -- px above screen centre (a bit lower than before)
local HOLD      = 0.9    -- seconds with no new coins before it fades
local FADE      = 0.4    -- fade-out duration

local sg = Instance.new("ScreenGui")
sg.Name = "PirateCoinTally"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.Parent = playerGui

local holder = Instance.new("Frame")
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Position = UDim2.new(0.5, OFFSET_X, 0.5, OFFSET_Y)
holder.Size = UDim2.fromOffset(130, 40)
holder.BackgroundTransparency = 1
holder.Visible = false
holder.Parent = sg

local scale = Instance.new("UIScale")
scale.Scale = 1
scale.Parent = holder

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 4)
layout.Parent = holder

local icon = Instance.new("ImageLabel")
icon.BackgroundTransparency = 1
icon.Image = COIN_ICON
icon.Size = UDim2.fromOffset(30, 30)
icon.LayoutOrder = 1
icon.Parent = holder

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBlack
label.TextSize = 30
label.TextColor3 = Color3.fromRGB(255, 213, 90)
label.TextStrokeColor3 = Color3.fromRGB(90, 55, 0)
label.TextStrokeTransparency = 0
label.Text = "+0"
label.Size = UDim2.fromOffset(78, 34)
label.TextXAlignment = Enum.TextXAlignment.Left
label.LayoutOrder = 2
label.Parent = holder

local function setAlpha(a)
	icon.ImageTransparency = a
	label.TextTransparency = a
	label.TextStrokeTransparency = a
end

local total = 0
local idle = 0

ev.OnClientEvent:Connect(function(amount)
	total += (amount or 1)
	label.Text = "+" .. total
	holder.Visible = true
	setAlpha(0)
	scale.Scale = 1.3 -- little pop each time it ticks up
	idle = 0
end)

RunService.RenderStepped:Connect(function(dt)
	if not holder.Visible then return end
	if scale.Scale > 1 then
		scale.Scale = math.max(1, scale.Scale - 2.5 * dt)
	end
	idle += dt
	if idle > HOLD then
		local a = math.min((idle - HOLD) / FADE, 1)
		setAlpha(a)
		if a >= 1 then
			holder.Visible = false
			total = 0
			label.Text = "+0"
		end
	end
end)
