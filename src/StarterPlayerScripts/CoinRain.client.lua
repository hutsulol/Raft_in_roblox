local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local COIN_IMAGE = ""
local MIN_COINS = 12
local MAX_COINS = 40
local SPAWN_WINDOW = 0.7
local FALL_MIN = 1.2
local FALL_MAX = 2.2

local gui = Instance.new("ScreenGui")
gui.Name = "CoinRain"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 500
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function baseCoinSize()
	local vy = (camera and camera.ViewportSize.Y) or 720
	return math.clamp(math.floor(vy * 0.06), 26, 64)
end

local function makeCoin(sizePx)
	local coin
	if COIN_IMAGE ~= "" then
		coin = Instance.new("ImageLabel")
		coin.Image = COIN_IMAGE
		coin.BackgroundTransparency = 1
		coin.ScaleType = Enum.ScaleType.Fit
	else
		coin = Instance.new("Frame")
		coin.BackgroundColor3 = Color3.fromRGB(30, 27, 34)

		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(74, 69, 82)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 18, 24)),
		})
		grad.Parent = coin

		local rim = Instance.new("UIStroke")
		rim.Thickness = math.max(2, math.floor(sizePx * 0.08))
		rim.Color = Color3.fromRGB(216, 178, 94)
		rim.Parent = coin

		local circle = Instance.new("UICorner")
		circle.CornerRadius = UDim.new(1, 0)
		circle.Parent = coin

		local mark = Instance.new("TextLabel")
		mark.Name = "Mark"
		mark.Size = UDim2.fromScale(1, 1)
		mark.BackgroundTransparency = 1
		mark.Text = "P"
		mark.Font = Enum.Font.GothamBold
		mark.TextScaled = true
		mark.TextColor3 = Color3.fromRGB(222, 62, 62)
		mark.Parent = coin

		local markPad = Instance.new("UIPadding")
		local pd = UDim.new(0, math.floor(sizePx * 0.2))
		markPad.PaddingTop = pd
		markPad.PaddingBottom = pd
		markPad.PaddingLeft = pd
		markPad.PaddingRight = pd
		markPad.Parent = mark
	end

	coin.AnchorPoint = Vector2.new(0.5, 0.5)
	coin.Size = UDim2.fromOffset(sizePx, sizePx)
	coin.BorderSizePixel = 0
	return coin
end

local function fadeCoin(coin, seconds)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Linear)
	if coin:IsA("ImageLabel") then
		TweenService:Create(coin, info, { ImageTransparency = 1 }):Play()
	else
		TweenService:Create(coin, info, { BackgroundTransparency = 1 }):Play()
		for _, ch in coin:GetDescendants() do
			if ch:IsA("UIStroke") then
				TweenService:Create(ch, info, { Transparency = 1 }):Play()
			elseif ch:IsA("TextLabel") then
				TweenService:Create(ch, info, { TextTransparency = 1 }):Play()
			end
		end
	end
end

local function dropOne()
	local sizePx = math.floor(baseCoinSize() * (0.75 + math.random() * 0.6))
	local coin = makeCoin(sizePx)

	local startX = 0.04 + math.random() * 0.92
	local endX = math.clamp(startX + (math.random() - 0.5) * 0.14, 0.02, 0.98)
	local dur = FALL_MIN + math.random() * (FALL_MAX - FALL_MIN)
	local spin = (math.random() < 0.5 and -1 or 1) * (60 + math.random() * 220)

	coin.Position = UDim2.new(startX, 0, -0.12, 0)
	coin.Rotation = math.random(-40, 40)
	coin.Parent = gui

	TweenService:Create(
		coin,
		TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(endX, 0, 1.14, 0), Rotation = coin.Rotation + spin }
	):Play()

	task.delay(dur * 0.72, function()
		if coin.Parent then
			fadeCoin(coin, dur * 0.28)
		end
	end)

	task.delay(dur + 0.2, function()
		if coin.Parent then coin:Destroy() end
	end)
end

local function playCoinRain(count)
	count = math.clamp(math.floor(tonumber(count) or MIN_COINS), MIN_COINS, MAX_COINS)
	for i = 1, count do
		task.delay((i - 1) / count * SPAWN_WINDOW, dropOne)
	end
end

_G.PlayCoinRain = playCoinRain

local event = ReplicatedStorage:WaitForChild("CoinRain", 15)
if event then
	event.OnClientEvent:Connect(function(count)
		playCoinRain(count)
	end)
end
