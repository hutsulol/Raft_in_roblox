local rs = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DRIFT_SPEED = 10
local PULL_SPEED = 30

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

local resources = {}
local pullTargets = {}

local function getBoat()
	for _, v in pairs(workspace:GetChildren()) do
		if v:IsA("Model") and v.PrimaryPart and v.Name == "Boat" then
			return v
		end
	end
end

local function spawnResource()
	if #templates == 0 then return end

	local boat = getBoat()
	if not boat then return end

	local root = boat.PrimaryPart
	local spawnPos =
		root.Position
		+ root.CFrame.LookVector * math.random(80, 120)
		+ Vector3.new(math.random(-30, 30), 0, math.random(-30, 30))

	local template = templates[math.random(1, #templates)]
	local clone = template:Clone()

	if not clone.PrimaryPart then
		local first = clone:FindFirstChildWhichIsA("BasePart", true)
		if not first then
			clone:Destroy()
			return
		end
		clone.PrimaryPart = first
	end

	clone:PivotTo(CFrame.new(spawnPos))

	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	clone.Parent = workspace

	local cRoot = clone.PrimaryPart

	local att = Instance.new("Attachment")
	att.Parent = cRoot

	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = 2000
	lv.VectorVelocity = Vector3.zero
	lv.Parent = cRoot

	local av = Instance.new("AngularVelocity")
	av.Attachment0 = att
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.MaxTorque = 2000
	av.AngularVelocity = Vector3.zero
	av.Parent = cRoot

	table.insert(resources, {
		model = clone,
		root = cRoot,
		lv = lv,
		av = av,
		spawnTime = tick(),
	})
end

pullEvent.OnServerEvent:Connect(function(player, targetModel, pulling)
	if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then return end
	if not targetModel:IsDescendantOf(workspace) then return end

	local found = false
	for _, data in resources do
		if data.model == targetModel then
			found = true
			break
		end
	end
	if not found then return end

	if pulling then
		pullTargets[targetModel] = player
	elseif pullTargets[targetModel] == player then
		pullTargets[targetModel] = nil
	end
end)

task.spawn(function()
	while true do
		task.wait(3)
		if #resources < 15 then
			spawnResource()
		end
	end
end)

RunService.Heartbeat:Connect(function()
	local boat = getBoat()
	if not boat then return end

	local boatPos = boat.PrimaryPart.Position

	for i = #resources, 1, -1 do
		local data = resources[i]

		if not data.root or not data.root.Parent then
			table.remove(resources, i)
			continue
		end

		if tick() - data.spawnTime > 30 then
			pullTargets[data.model] = nil
			data.model:Destroy()
			table.remove(resources, i)
			continue
		end

		local pos = data.root.Position
		local target = boatPos
		local speed = DRIFT_SPEED

		local puller = pullTargets[data.model]
		if puller and puller.Character and puller.Character:FindFirstChild("HumanoidRootPart") then
			target = puller.Character.HumanoidRootPart.Position
			speed = PULL_SPEED
		end

		local dir = target - pos

		if dir.Magnitude < 5 then
			pullTargets[data.model] = nil
			data.model:Destroy()
			table.remove(resources, i)
			continue
		end

		dir = dir.Unit

		local drift = Vector3.new(
			math.sin(os.clock() + pos.X),
			0,
			math.cos(os.clock() + pos.Z)
		) * 2

		data.lv.VectorVelocity = dir * speed + drift
		data.av.AngularVelocity = Vector3.new(0, 1, 0)
	end
end)
