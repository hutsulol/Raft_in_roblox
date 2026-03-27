local rs = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local model = script.Parent
local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")

local att = Instance.new("Attachment", root)

local lv = Instance.new("LinearVelocity")
lv.Attachment0 = att
lv.RelativeTo = Enum.ActuatorRelativeTo.World
lv.MaxForce = 2000
lv.VectorVelocity = Vector3.zero
lv.Parent = root

local av = Instance.new("AngularVelocity")
av.Attachment0 = att
av.RelativeTo = Enum.ActuatorRelativeTo.World
av.MaxTorque = 2000
av.AngularVelocity = Vector3.zero
av.Parent = root

local DRIFT_SPEED = 10
local PULL_SPEED = 30
local pullEvent = rs:WaitForChild("PullResource")

local pullingPlayer = nil

pullEvent.OnServerEvent:Connect(function(player, targetModel, pulling)
	if targetModel ~= model then return end
	if pulling then
		pullingPlayer = player
	else
		if pullingPlayer == player then
			pullingPlayer = nil
		end
	end
end)

local function getBoat()
	for _, v in pairs(workspace:GetChildren()) do
		if v:IsA("Model") and v.PrimaryPart then
			if v.Name == "Boat" then
				return v
			end
		end
	end
end

RunService.Heartbeat:Connect(function()
	local boat = getBoat()
	if not boat then return end

	local target = boat.PrimaryPart.Position
	local speed = DRIFT_SPEED

	if pullingPlayer and pullingPlayer.Character and pullingPlayer.Character:FindFirstChild("HumanoidRootPart") then
		target = pullingPlayer.Character.HumanoidRootPart.Position
		speed = PULL_SPEED
	end

	local pos = root.Position
	local dir = target - pos

	if dir.Magnitude < 5 then
		model:Destroy()
		return
	end

	dir = dir.Unit

	local drift = Vector3.new(
		math.sin(os.clock() + pos.X),
		0,
		math.cos(os.clock() + pos.Z)
	) * 2

	lv.VectorVelocity = dir * speed + drift
	av.AngularVelocity = Vector3.new(0, 1, 0)
end)
