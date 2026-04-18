local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CONTAINER_SIZE = Vector3.new(3, 2.2, 2)

local actionEvent = ReplicatedStorage:FindFirstChild("SmallContainerAction")
if not actionEvent then
	actionEvent = Instance.new("RemoteEvent")
	actionEvent.Name = "SmallContainerAction"
	actionEvent.Parent = ReplicatedStorage
end

local function buildContainerModel()
	local template = ReplicatedStorage:FindFirstChild("SmallContainer")
	if template and template:IsA("Model") then
		return template:Clone()
	end

	local model = Instance.new("Model")
	model.Name = "SmallContainer"

	local body = Instance.new("Part")
	body.Name = "Handle"
	body.Size = CONTAINER_SIZE
	body.Material = Enum.Material.Wood
	body.Color = Color3.fromRGB(120, 80, 50)
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model
	model.PrimaryPart = body

	return model
end

actionEvent.OnServerEvent:Connect(function(player, action, target)
	if action ~= "placeContainer" then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "SmallContainer" then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end
	if typeof(target) ~= "CFrame" then return end

	local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

	local container = buildContainerModel()

	for _, desc in container:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end

	if container:IsA("Model") then
		local bbCF = container:GetBoundingBox()
		container.WorldPivot = CFrame.new(bbCF.Position)
		container:PivotTo(worldCF)
	end

	container.Parent = raft

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
