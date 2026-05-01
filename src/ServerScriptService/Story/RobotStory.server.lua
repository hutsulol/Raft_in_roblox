-- RobotStory.server.lua
-- Server-side handler for the Robot NPC storyline.
-- Tracks quest completion per player and grants rewards (Phone tool).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local storyEvent = Instance.new("RemoteEvent")
storyEvent.Name = "StoryAction"
storyEvent.Parent = ReplicatedStorage

storyEvent.OnServerEvent:Connect(function(player, action)
	if action ~= "claimRobotPhone" then return end

	-- Prevent double-claim
	if player:GetAttribute("RobotQuest1Done") then return end

	-- Distance check: player must be near the Robot
	local raft = workspace:FindFirstChild("Raft")
	local robot = raft and raft:FindFirstChild("Robot")
	if robot then
		local char = player.Character
		if not char or not char:FindFirstChild("HumanoidRootPart") then return end
		local robotPart = robot:IsA("Model")
			and (robot.PrimaryPart or robot:FindFirstChildWhichIsA("BasePart", true))
			or robot
		if robotPart and (char.HumanoidRootPart.Position - robotPart.Position).Magnitude > 20 then
			return
		end
	end

	-- Mark quest done (attribute replicates to client automatically)
	player:SetAttribute("RobotQuest1Done", true)

	-- Give the player a Phone tool (same logic as InventoryCrafting)
	local template = ReplicatedStorage:FindFirstChild("Phone")
	if not template then
		template = ReplicatedStorage:FindFirstChild("Phone", true)
	end
	if not template then return end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	local cloned = template:Clone()
	local tool

	if cloned:IsA("Tool") then
		tool = cloned
		if not tool:FindFirstChild("Handle") then
			local first = tool:FindFirstChildWhichIsA("BasePart", true)
			if first then first.Name = "Handle" end
		end
	else
		tool = Instance.new("Tool")
		tool.Name = "Phone"
		tool.CanBeDropped = false

		if cloned:IsA("Model") then
			local handle = cloned:FindFirstChild("Handle")
				or cloned:FindFirstChildWhichIsA("BasePart", true)
			for _, child in cloned:GetChildren() do
				child.Parent = tool
			end
			if handle and handle.Name ~= "Handle" then
				handle.Name = "Handle"
			end
		elseif cloned:IsA("BasePart") then
			cloned.Name = "Handle"
			cloned.Parent = tool
		end
		cloned:Destroy()
	end

	if tool.TextureId == "" then
		tool.TextureId = "rbxassetid://123703470055474"
	end

	tool.Parent = backpack
	storyEvent:FireClient(player, "phoneClaimed")
end)
