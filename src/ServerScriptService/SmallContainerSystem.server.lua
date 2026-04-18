-- SmallContainerSystem.server.lua
-- Placement for the Small Container crafted at the WorkBench.
-- Mirrors FurnaceCraft.server.lua's placement block byte-for-byte so
-- the container slots into the same raft/weld pattern the furnace uses.

local rs = game:GetService("ReplicatedStorage")

local cupActionEvent = rs:WaitForChild("CupAction")

local function getContainerTemplate()
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

	local template = getContainerTemplate()
	if not template then return end

	local archivable = template.Archivable
	template.Archivable = true
	local container = template:Clone()
	template.Archivable = archivable
	container.Name = "SmallContainer"

	-- Remove scripts from clone
	for _, desc in container:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end

	-- Position
	if container:IsA("Model") then
		if not container.PrimaryPart then
			local first = container:FindFirstChildWhichIsA("BasePart", true)
			if first then container.PrimaryPart = first end
		end
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

	tool:Destroy()
end)
