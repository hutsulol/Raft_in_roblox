-- SmallContainerSystem.server.lua
-- Places the Small Container on the raft. Mirrors ThirstSystem's
-- 'placeWorkbench' handler exactly — only the tool name, template
-- lookup, and action string differ.

local rs = game:GetService("ReplicatedStorage")

local cupActionEvent = rs:WaitForChild("CupAction")

local function findTemplate()
	local folder = rs:FindFirstChild("Containers_Player")
	local tmpl = folder and folder:FindFirstChild("Container_empty")
	if not tmpl then
		tmpl = rs:FindFirstChild("Container_empty", true)
	end
	return tmpl
end

cupActionEvent.OnServerEvent:Connect(function(player, action, target)
	if action ~= "placeSmallContainer" then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "SmallContainer" then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end

	if typeof(target) ~= "CFrame" then return end

	local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

	local template = findTemplate()
	if not template then return end

	local container = template:Clone()
	container.Name = "SmallContainer"

	-- Reset WorldPivot to bounding box center with no rotation (match client ghost)
	if container:IsA("Model") then
		local bbCF = container:GetBoundingBox()
		container.WorldPivot = CFrame.new(bbCF.Position)
	end

	container:PivotTo(worldCF)
	container.Parent = raft

	-- Weld to raft
	for _, part in container:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = raft.PrimaryPart
			weld.Parent = part
		end
	end

	-- Remove tool from player
	tool:Destroy()
end)
