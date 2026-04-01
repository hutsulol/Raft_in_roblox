-- PickAxeAnimInjector.server.lua
-- Adds mining Animation object to Pick-Axe tools so PickAxeClient can find and play it

local Players = game:GetService("Players")

local MINING_ANIM_ID = "rbxassetid://10027239454"

local function addAnimToTool(tool)
	if tool.Name ~= "Pick-Axe" then return end
	-- Don't add if already has one
	if tool:FindFirstChildWhichIsA("Animation") then return end

	local anim = Instance.new("Animation")
	anim.Name = "MiningAnimation"
	anim.AnimationId = MINING_ANIM_ID
	anim.Parent = tool
end

local function watchPlayer(player)
	-- Watch backpack
	local backpack = player:WaitForChild("Backpack", 30)
	if backpack then
		backpack.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then addAnimToTool(child) end
		end)
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") then addAnimToTool(child) end
		end
	end

	-- Watch character (tool is moved here when equipped)
	player.CharacterAdded:Connect(function(char)
		char.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then addAnimToTool(child) end
		end)
	end)

	if player.Character then
		player.Character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then addAnimToTool(child) end
		end)
		for _, child in player.Character:GetChildren() do
			if child:IsA("Tool") then addAnimToTool(child) end
		end
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(watchPlayer, p)
end
