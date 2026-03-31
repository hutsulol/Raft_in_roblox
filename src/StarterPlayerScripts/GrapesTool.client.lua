local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local eatGrapes = ReplicatedStorage:WaitForChild("EatGrapes")

local function setupTool(tool)
	if tool.Name ~= "[GRAPES]" then return end

	tool.Activated:Connect(function()
		tool.GripForward = Vector3.new(-0.97, 1.02e-005, -0.243)
		tool.GripPos = Vector3.new(-0.2, 0, -1.23)
		tool.GripRight = Vector3.new(0.197, 0.581, -0.79)
		tool.GripUp = Vector3.new(-0.141, 0.814, 0.563)

		eatGrapes:FireServer()

		task.wait(1.2)

		if tool and tool.Parent then
			tool:Destroy()
		end
	end)
end

local character = player.Character or player.CharacterAdded:Wait()

character.ChildAdded:Connect(function(child)
	if child:IsA("Tool") then
		setupTool(child)
	end
end)

player.CharacterAdded:Connect(function(char)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			setupTool(child)
		end
	end)
end)

local backpack = player:WaitForChild("Backpack")
backpack.ChildAdded:Connect(function(child)
	if child:IsA("Tool") then
		setupTool(child)
	end
end)

for _, tool in ipairs(backpack:GetChildren()) do
	if tool:IsA("Tool") then
		setupTool(tool)
	end
end
