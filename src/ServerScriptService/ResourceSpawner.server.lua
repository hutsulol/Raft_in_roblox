local rs = game:GetService("ReplicatedStorage")

local templates = {}
for _, name in {"Log", "Wooden Barrel"} do
	local model = rs:FindFirstChild(name)
	if model then
		table.insert(templates, model)
	end
end

local pullEvent = Instance.new("RemoteEvent")
pullEvent.Name = "PullResource"
pullEvent.Parent = rs

local function getBoat()
	for _, v in pairs(workspace:GetChildren()) do
		if v:IsA("Model") and v.PrimaryPart then
			if v.Name == "Boat" then
				return v
			end
		end
	end
end

while true do
	task.wait(3)

	local boat = getBoat()
	if not boat then continue end
	if #templates == 0 then continue end

	local root = boat.PrimaryPart

	local spawnPos =
		root.Position
		+ root.CFrame.LookVector * math.random(80, 120)
		+ Vector3.new(math.random(-30, 30), 0, math.random(-30, 30))

	local template = templates[math.random(1, #templates)]
	local clone = template:Clone()

	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	if not clone.PrimaryPart then
		for _, part in clone:GetDescendants() do
			if part:IsA("BasePart") then
				clone.PrimaryPart = part
				break
			end
		end
	end

	clone.Parent = workspace
	clone:PivotTo(CFrame.new(spawnPos))
end
