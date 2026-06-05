local rs = game:GetService("ReplicatedStorage")

local cupActionEvent = rs:WaitForChild("CupAction")

local TEMPLATE_NAME = "Cannon"
local TOOL_NAME = "Cannon"
local ACTION_NAME = "placeCannon"

cupActionEvent.OnServerEvent:Connect(function(player, action, target)
	if action ~= ACTION_NAME then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= TOOL_NAME then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end
	if typeof(target) ~= "CFrame" then return end

	local template = rs:FindFirstChild(TEMPLATE_NAME)
	if not template then return end

	local cannon = template:Clone()
	cannon.Name = "Cannon"

	if cannon:IsA("Model") then
		local bbCF = cannon:GetBoundingBox()
		cannon.WorldPivot = CFrame.new(bbCF.Position)
	end

	cannon:PivotTo(raft.PrimaryPart.CFrame:ToWorldSpace(target))

	for _, part in cannon:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	cannon:SetAttribute("RaftLocalCF", target)
	cannon:SetAttribute("Loaded", false)

	cannon.Parent = raft

	tool:Destroy()
end)
