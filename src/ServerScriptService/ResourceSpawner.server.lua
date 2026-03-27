local CollectionService = game:GetService("CollectionService")
local rs = game:GetService("ReplicatedStorage")

local collectEvent = rs:FindFirstChild("CollectResource")
if not collectEvent then
	collectEvent = Instance.new("RemoteEvent")
	collectEvent.Name = "CollectResource"
	collectEvent.Parent = rs
end

local function getBoat()
	for _, v in pairs(workspace:GetChildren()) do
		if v:IsA("Model") and v.PrimaryPart then
			return v
		end
	end
end

collectEvent.OnServerEvent:Connect(function(player, targetPart)
	if typeof(targetPart) ~= "Instance" or not targetPart:IsA("BasePart") then return end
	if not targetPart:IsDescendantOf(workspace) then return end
	if not CollectionService:HasTag(targetPart, "Plank") then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local dist = (char.HumanoidRootPart.Position - targetPart.Position).Magnitude
	if dist > 50 then return end

	targetPart:Destroy()
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
