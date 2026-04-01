-- MineRockAnim.client.lua
-- Plays mining animation (rbxassetid://10027239454) when hitting rocks

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mineRockEvent = ReplicatedStorage:WaitForChild("MineRock")

-- Create Animation with the known ID
local miningAnim = Instance.new("Animation")
miningAnim.AnimationId = "rbxassetid://10027239454"

local animTrack = nil

local function setupCharacter(char)
	animTrack = nil
	local humanoid = char:WaitForChild("Humanoid", 10)
	if not humanoid then return end

	local animator = humanoid:FindFirstChildWhichIsA("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(miningAnim)
	end)

	if ok and track then
		animTrack = track
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

mineRockEvent.OnClientEvent:Connect(function(action)
	if action ~= "hit" and action ~= "destroyed" then return end

	local currentChar = player.Character
	if not currentChar then return end
	local tool = currentChar:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Pick-Axe" then return end

	if animTrack then
		animTrack:Play()
	end
end)
