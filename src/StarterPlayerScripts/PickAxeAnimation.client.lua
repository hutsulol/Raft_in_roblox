-- PickAxeAnimation.client.lua
-- Plays mining animation on Pick-Axe tool activation (click)
-- Also stops any conflicting rig animations from the tool

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local MINING_ANIM_ID = "rbxassetid://10027239454"

local miningAnim = Instance.new("Animation")
miningAnim.AnimationId = MINING_ANIM_ID

local animTrack = nil
local currentPickAxe = nil

local function loadAnimation(humanoid)
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
		animTrack.Priority = Enum.AnimationPriority.Action
	end
end

local function stopRigAnimations(humanoid)
	-- Stop all playing animation tracks except ours
	for _, track in humanoid:GetPlayingAnimationTracks() do
		if track ~= animTrack then
			local animId = ""
			pcall(function() animId = track.Animation.AnimationId end)
			-- Don't stop core animations (walk, idle, jump)
			if animId ~= "" and animId ~= MINING_ANIM_ID then
				track:Stop()
			end
		end
	end
end

local function onToolEquipped(tool)
	if tool.Name ~= "Pick-Axe" then return end
	currentPickAxe = tool

	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then return end

	-- Load our mining animation
	loadAnimation(humanoid)

	-- When tool is activated (clicked), play mining animation
	tool.Activated:Connect(function()
		if animTrack then
			animTrack:Play()
		end
	end)
end

local function onToolUnequipped(tool)
	if tool.Name ~= "Pick-Axe" then return end
	currentPickAxe = nil
	if animTrack then
		animTrack:Stop()
		animTrack = nil
	end
end

local function setupCharacter(char)
	if not char then return end

	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			onToolEquipped(child)
		end
	end)

	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			onToolUnequipped(child)
		end
	end)

	-- Check already equipped
	for _, child in char:GetChildren() do
		if child:IsA("Tool") and child.Name == "Pick-Axe" then
			onToolEquipped(child)
			break
		end
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)
