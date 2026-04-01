-- MiningAnimation.client.lua
-- Plays the "Mining Rock" animation from ReplicatedStorage when mining rocks

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local mineRockEvent = ReplicatedStorage:WaitForChild("MineRock")

-- Find the Animation object inside "Mining Rock"
local miningRockFolder = ReplicatedStorage:WaitForChild("Mining Rock", 10)
local miningAnim = nil

if miningRockFolder then
	-- Look for Animation object inside
	miningAnim = miningRockFolder:FindFirstChildWhichIsA("Animation", true)
	if not miningAnim then
		-- Maybe it's an AnimationClip or the folder itself is an Animation
		if miningRockFolder:IsA("Animation") then
			miningAnim = miningRockFolder
		end
	end
end

if not miningAnim then
	-- Try alternate names
	local alt = ReplicatedStorage:FindFirstChild("MiningRock")
	if alt then
		if alt:IsA("Animation") then
			miningAnim = alt
		else
			miningAnim = alt:FindFirstChildWhichIsA("Animation", true)
		end
	end
end

local animTrack = nil

-- ─── Load animation when character spawns ───
local function setupCharacter(char)
	animTrack = nil
	local humanoid = char:WaitForChild("Humanoid", 10)
	if not humanoid or not miningAnim then return end

	local animator = humanoid:FindFirstChildWhichIsA("Animator")
	if animator then
		animTrack = animator:LoadAnimation(miningAnim)
	else
		animTrack = humanoid:LoadAnimation(miningAnim)
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

-- ─── Play animation on mine event ───
mineRockEvent.OnClientEvent:Connect(function(action, value)
	if action == "hit" or action == "destroyed" then
		-- Check if Pick-Axe is equipped
		local currentChar = player.Character
		if not currentChar then return end
		local tool = currentChar:FindFirstChildWhichIsA("Tool")
		if not tool or tool.Name ~= "Pick-Axe" then return end

		if animTrack then
			animTrack:Play()
		end
	end
end)
