local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local collectEvent = ReplicatedStorage:WaitForChild("CollectResource")

local currentHighlight = nil
local currentTarget = nil

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
			clearHighlight()
		end
	end
end)
