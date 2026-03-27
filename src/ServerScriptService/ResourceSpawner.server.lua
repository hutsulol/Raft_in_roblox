local CollectionService = game:GetService("CollectionService")
local rs = game:GetService("ReplicatedStorage")

local PULL_SPEED = 30

local pullEvent = rs:FindFirstChild("PullResource")
if not pullEvent then
	pullEvent = Instance.new("RemoteEvent")
	pullEvent.Name = "PullResource"
	pullEvent.Parent = rs
end

local pullTargets = {}

local function getBoat()
	for _, v in pairs(workspace:GetChildren()) do
		if v:IsA("Model") and v.PrimaryPart then
			return v
		end
	end
end

pullEvent.OnServerEvent:Connect(function(player, targetPart, pulling)
	if typeof(targetPart) ~= "Instance" or not targetPart:IsA("BasePart") then return end
	if not targetPart:IsDescendantOf(workspace) then return end
	if not CollectionService:HasTag(targetPart, "Plank") then return end

	if pulling then
		pullTargets[targetPart] = player

		local att = targetPart:FindFirstChildWhichIsA("Attachment")
		if not att then
			att = Instance.new("Attachment")
			att.Parent = targetPart
		end

		local lv = targetPart:FindFirstChild("PullVelocity")
		if not lv then
			lv = Instance.new("LinearVelocity")
			lv.Name = "PullVelocity"
			lv.Attachment0 = att
			lv.RelativeTo = Enum.ActuatorRelativeTo.World
			lv.MaxForce = 2000
			lv.VectorVelocity = Vector3.zero
			lv.Parent = targetPart
		end
	else
		if pullTargets[targetPart] == player then
			pullTargets[targetPart] = nil
			local lv = targetPart:FindFirstChild("PullVelocity")
			if lv then lv:Destroy() end
		end
	end
end)

game:GetService("RunService").Heartbeat:Connect(function()
	for part, player in pairs(pullTargets) do
		if not part or not part.Parent then
			pullTargets[part] = nil
			continue
		end

		if not player or not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
			pullTargets[part] = nil
			local lv = part:FindFirstChild("PullVelocity")
			if lv then lv:Destroy() end
			continue
		end

		local target = player.Character.HumanoidRootPart.Position
		local dir = target - part.Position

		if dir.Magnitude < 5 then
			pullTargets[part] = nil
			part:Destroy()
			continue
		end

		local lv = part:FindFirstChild("PullVelocity")
		if lv then
			lv.VectorVelocity = dir.Unit * PULL_SPEED
		end
	end
end)

while true do
	task.wait(3)

	local boat = getBoat()
	if not boat then continue end

	local root = boat.PrimaryPart

	local spawnPos =
		root.Position
		+ root.CFrame.LookVector * math.random(80, 120)
		+ Vector3.new(math.random(-30, 30), 0, math.random(-30, 30))

	local part = Instance.new("Part")
	part.Size = Vector3.new(4, 2, 8)
	part.Color = Color3.fromRGB(139, 90, 43)
	part.Material = Enum.Material.Wood
	part.Anchored = false
	part.Position = spawnPos
	part.Parent = workspace
	CollectionService:AddTag(part, "Plank")
end
