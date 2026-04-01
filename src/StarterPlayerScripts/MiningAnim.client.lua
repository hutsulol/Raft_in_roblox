-- MiningAnim.client.lua
-- Plays the mining animation when hitting rocks with Pick-Axe

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mineRockEvent = ReplicatedStorage:WaitForChild("MineRock")

-- ─── Find animation from ReplicatedStorage ───
-- Search "Mining Rock" model for any Animation or KeyframeSequence
local function findMiningAnimation()
	-- Try direct Animation objects first
	for _, name in {"Mining Rock", "MiningRock"} do
		local obj = ReplicatedStorage:FindFirstChild(name)
		if not obj then continue end

		-- If it's an Animation directly
		if obj:IsA("Animation") then
			return obj
		end

		-- Search inside for Animation
		local anim = obj:FindFirstChildWhichIsA("Animation", true)
		if anim then return anim end

		-- Search for KeyframeSequence (needs to be wrapped in Animation)
		local kfs = obj:FindFirstChildWhichIsA("KeyframeSequence", true)
		if kfs then
			-- Create an Animation instance pointing to this asset
			-- The KeyframeSequence's asset ID can be used
			local animObj = Instance.new("Animation")
			-- Try to get the animation ID from the model's asset
			if obj:IsA("Model") or obj:IsA("Folder") then
				-- Look for any child with AnimationId property
				for _, desc in obj:GetDescendants() do
					if desc:IsA("Animation") then
						return desc
					end
					-- Check if any StringValue stores the animation ID
					if desc:IsA("StringValue") and desc.Value:find("rbxassetid") then
						animObj.AnimationId = desc.Value
						return animObj
					end
				end
			end
		end
	end

	return nil
end

local miningAnim = findMiningAnimation()
local animTrack = nil

-- ─── Load animation on character ───
local function setupCharacter(char)
	animTrack = nil
	local humanoid = char:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	if not miningAnim then return end

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

-- ─── Play on mine events ───
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
