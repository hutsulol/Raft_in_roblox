-- PaddleController.client.lua
-- Detects when the player uses the Paddle tool and sends the paddle
-- direction to the server so the raft can be steered.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local paddleEvent = ReplicatedStorage:WaitForChild("PaddleAction")

local COOLDOWN = 1.0 -- seconds between paddle strokes
local lastPaddleTime = 0
local currentTool = nil
local isPaddling = false

-- Paddle animation: briefly tilt the paddle on use
local function playPaddleEffect()
	-- Visual feedback handled by server/animation; this is just input
end

local function onActivated()
	if not currentTool or currentTool.Name ~= "Paddle" then return end

	local now = tick()
	if now - lastPaddleTime < COOLDOWN then return end
	lastPaddleTime = now

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end

	-- Raycast from mouse to find where the player is pointing
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local raftPos = raft.PrimaryPart.Position

	-- Intersect ray with the horizontal plane at raft height
	local planeY = raftPos.Y
	local denom = unitRay.Direction.Y
	if math.abs(denom) < 0.001 then return end

	local t = (planeY - unitRay.Origin.Y) / denom
	if t < 0 then return end

	local hitPoint = unitRay.Origin + unitRay.Direction * t

	-- Direction from raft center to where the player clicked (horizontal)
	local direction = Vector3.new(hitPoint.X - raftPos.X, 0, hitPoint.Z - raftPos.Z)
	if direction.Magnitude < 1 then return end
	direction = direction.Unit

	paddleEvent:FireServer(direction)
end

local function setupTool(tool)
	if tool.Name ~= "Paddle" then return end
	currentTool = tool
	tool.Activated:Connect(onActivated)
end

local function onCharacter(char)
	if not char then return end

	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			setupTool(child)
		end
	end)

	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child == currentTool then
			currentTool = nil
		end
	end)

	for _, child in char:GetChildren() do
		if child:IsA("Tool") then
			setupTool(child)
		end
	end
end

if player.Character then onCharacter(player.Character) end
player.CharacterAdded:Connect(onCharacter)
