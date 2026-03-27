local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local pullEvent = ReplicatedStorage:WaitForChild("PullResource")

local MAX_PULL_DISTANCE = 100
local currentTarget = nil
local isPulling = false

local function getResourceUnderMouse()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {player.Character}

	local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_PULL_DISTANCE, params)
	if not result or not result.Instance then
		return nil
	end

	local hit = result.Instance
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end

	if not model:FindFirstChild("DriftForce", true) then
		return nil
	end

	return model
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local target = getResourceUnderMouse()
		if target then
			currentTarget = target
			isPulling = true
			pullEvent:FireServer(target, true)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isPulling and currentTarget then
			pullEvent:FireServer(currentTarget, false)
			currentTarget = nil
			isPulling = false
		end
	end
end)
