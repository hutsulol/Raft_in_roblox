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
local hitPart = nil
local progressBillboards = {}

local function getResourceUnderMouse()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {player.Character}

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	if not result or not result.Instance then
		return nil, nil
	end

	local hit = result.Instance

	if CollectionService:HasTag(hit, "Resource") then
		return hit, hit
	end

	local model = hit:FindFirstAncestorOfClass("Model")
	if model and CollectionService:HasTag(model, "Resource") then
		return model, hit
	end

	return nil, nil
end

local function clearHighlight()
	if currentHighlight then
		currentHighlight:Destroy()
		currentHighlight = nil
	end
	currentTarget = nil
	hitPart = nil
end

local function getAdornee(resource)
	if resource:IsA("Model") and resource.PrimaryPart then
		return resource.PrimaryPart
	elseif resource:IsA("BasePart") then
		return resource
	end
	local first = resource:FindFirstChildWhichIsA("BasePart", true)
	return first or resource
end

local function getOrCreateProgressUI(resource)
	if progressBillboards[resource] then
		return progressBillboards[resource]
	end

	local adornee = getAdornee(resource)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(4, 0, 0.5, 0)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = adornee
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

	progressBillboards[resource] = billboard
	return billboard
end

local function updateProgress(resource, clicks, maxClicks)
	local billboard = getOrCreateProgressUI(resource)
	local bg = billboard:FindFirstChildWhichIsA("Frame")
	local fill = bg:FindFirstChild("Fill")

	local ratio = clicks / maxClicks
	TweenService:Create(fill, TweenInfo.new(0.15), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
end

local function removeProgress(resource)
	if progressBillboards[resource] then
		progressBillboards[resource]:Destroy()
		progressBillboards[resource] = nil
	end
end

local RESOURCE_ICONS = {
	Log = "rbxassetid://110032041583533",
	Plastic = "rbxassetid://110032041583533",
}

local function showCollectedPopup(worldPos, resType, resAmount)
	local screenPos, onScreen = camera:WorldToScreenPoint(worldPos)
	if not onScreen then return end

	local amount = resAmount or 1
	local iconId = RESOURCE_ICONS[resType or "Log"] or "rbxassetid://110032041583533"

	local screenGui = Instance.new("ScreenGui")
	screenGui.Parent = playerGui

	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, 120, 0, 50)
	container.Position = UDim2.new(0, screenPos.X - 60, 0, screenPos.Y - 25)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 50, 1, 0)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = "+ " .. tostring(amount)
	label.TextColor3 = Color3.fromRGB(255, 220, 100)
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = container

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0, 40, 0, 40)
	icon.Position = UDim2.new(0, 55, 0.5, -20)
	icon.BackgroundTransparency = 1
	icon.Image = iconId
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = container

	local startY = screenPos.Y - 25
	local tweenUp = TweenService:Create(container, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, screenPos.X - 60, 0, startY - 50),
	})
	local tweenFadeText = TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	local tweenFadeIcon = TweenService:Create(icon, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		ImageTransparency = 1,
	})
	tweenUp:Play()
	tweenFadeText:Play()
	tweenFadeIcon:Play()
	tweenUp.Completed:Connect(function()
		screenGui:Destroy()
	end)
end

local lastResourcePositions = {}

collectNotify.OnClientEvent:Connect(function(action, resource, arg3, arg4)
	if action == "progress" then
		-- arg3 = clicks, arg4 = maxClicks
		updateProgress(resource, arg3, arg4)
		local adornee = getAdornee(resource)
		if adornee and adornee:IsA("BasePart") then
			lastResourcePositions[resource] = adornee.Position
		end
	elseif action == "collected" then
		-- arg3 = resType, arg4 = resAmount
		local worldPos = lastResourcePositions[resource]
		if not worldPos then
			local adornee = getAdornee(resource)
			if adornee and adornee:IsA("BasePart") then
				worldPos = adornee.Position
			end
		end
		removeProgress(resource)
		clearHighlight()
		lastResourcePositions[resource] = nil
		if worldPos then
			showCollectedPopup(worldPos, arg3, arg4)
		end
	end
end)

RunService.RenderStepped:Connect(function()
	local resource, part = getResourceUnderMouse()

	if resource == currentTarget then
		return
	end

	clearHighlight()

	if resource then
		currentTarget = resource
		hitPart = part
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.new(1, 1, 1)
		highlight.FillTransparency = 0.5
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.OutlineTransparency = 0
		highlight.Parent = resource
		currentHighlight = highlight
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if currentTarget and hitPart then
			collectEvent:FireServer(hitPart)
		end
	end
end)
