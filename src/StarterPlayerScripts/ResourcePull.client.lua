local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local pullEvent = ReplicatedStorage:WaitForChild("PullResource")

local currentTarget = nil
local isPulling = false

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

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local target = getPlankUnderMouse()
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
