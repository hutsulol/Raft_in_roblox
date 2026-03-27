local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local collectEvent = ReplicatedStorage:WaitForChild("CollectResource")
local collectNotify = ReplicatedStorage:WaitForChild("CollectNotify")

local currentHighlight = nil
local currentTarget = nil
local progressBillboards = {}

local function getPlankUnderMouse()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {player.Character}

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	if not result or not result.Instance then
		return nil
	end

	local hit = result.Instance
	if not CollectionService:HasTag(hit, "Plank") then
		return nil
	end

	return hit
end

local function clearHighlight()
	if currentHighlight then
		currentHighlight:Destroy()
		currentHighlight = nil
	end
	currentTarget = nil
end

local function getOrCreateProgressUI(part)
	if progressBillboards[part] then
		return progressBillboards[part]
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(4, 0, 0.5, 0)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = part
	billboard.Parent = playerGui

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bg.BackgroundTransparency = 0.3
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	fill.BackgroundTransparency = 0.1
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.3, 0)
	fillCorner.Parent = fill

	progressBillboards[part] = billboard
	return billboard
end

local function updateProgress(part, clicks, maxClicks)
	local billboard = getOrCreateProgressUI(part)
	local bg = billboard:FindFirstChildWhichIsA("Frame")
	local fill = bg:FindFirstChild("Fill")

	local ratio = clicks / maxClicks
	TweenService:Create(fill, TweenInfo.new(0.15), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
end

local function removeProgress(part)
	if progressBillboards[part] then
		progressBillboards[part]:Destroy()
		progressBillboards[part] = nil
	end
end

local function showCollectedPopup()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 200, 0, 50)
	label.Position = UDim2.new(0.5, -100, 0.4, 0)
	label.BackgroundTransparency = 1
	label.Text = "+1 🪵"
	label.TextColor3 = Color3.fromRGB(255, 220, 100)
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = screenGui

	local tweenUp = TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -100, 0.3, 0),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tweenUp:Play()
	tweenUp.Completed:Connect(function()
		screenGui:Destroy()
	end)
end

collectNotify.OnClientEvent:Connect(function(action, part, clicks, maxClicks)
	if action == "progress" then
		updateProgress(part, clicks, maxClicks)
	elseif action == "collected" then
		removeProgress(part)
		clearHighlight()
		showCollectedPopup()
	end
end)

RunService.RenderStepped:Connect(function()
	local plank = getPlankUnderMouse()

	if plank == currentTarget then
		return
	end

	clearHighlight()

	if plank then
		currentTarget = plank
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.new(1, 1, 1)
		highlight.FillTransparency = 0.5
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.OutlineTransparency = 0
		highlight.Parent = plank
		currentHighlight = highlight
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if currentTarget then
			collectEvent:FireServer(currentTarget)
		end
	end
end)
