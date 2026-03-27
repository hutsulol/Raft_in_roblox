local CollectionService = game:GetService("CollectionService")
local rs = game:GetService("ReplicatedStorage")

local CLICKS_TO_COLLECT = 5
local LIFETIME = 120
local FLOAT_Y = 1.5

local collectEvent = rs:FindFirstChild("CollectResource")
if not collectEvent then
	collectEvent = Instance.new("RemoteEvent")
	collectEvent.Name = "CollectResource"
	collectEvent.Parent = rs
end

local collectNotify = rs:FindFirstChild("CollectNotify")
if not collectNotify then
	collectNotify = Instance.new("RemoteEvent")
	collectNotify.Name = "CollectNotify"
	collectNotify.Parent = rs
end

local clickCounts = {}

local function getBoat()
	for _, v in pairs(workspace:GetChildren()) do
		if v:IsA("Model") and v.PrimaryPart then
			if not CollectionService:HasTag(v, "Resource") then
				return v
			end
		end
	end
end

local function getResourceFromPart(part)
	if CollectionService:HasTag(part, "Resource") then
		return part
	end

	local model = part:FindFirstAncestorOfClass("Model")
	if model and CollectionService:HasTag(model, "Resource") then
		return model
	end

	return nil
end

collectEvent.OnServerEvent:Connect(function(player, targetPart)
	if typeof(targetPart) ~= "Instance" then return end
	if not targetPart:IsDescendantOf(workspace) then return end

	local resource = getResourceFromPart(targetPart)
	if not resource then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local resourcePos
	if resource:IsA("Model") then
		resourcePos = resource:GetPivot().Position
	else
		resourcePos = resource.Position
	end

	local dist = (char.HumanoidRootPart.Position - resourcePos).Magnitude
	if dist > 50 then return end

	if not clickCounts[resource] then
		clickCounts[resource] = {}
	end

	if not clickCounts[resource][player] then
		clickCounts[resource][player] = 0
	end

	clickCounts[resource][player] = clickCounts[resource][player] + 1
	local clicks = clickCounts[resource][player]

	collectNotify:FireClient(player, "progress", resource, clicks, CLICKS_TO_COLLECT)

	if clicks >= CLICKS_TO_COLLECT then
		clickCounts[resource] = nil
		collectNotify:FireClient(player, "collected", resource)
		resource:Destroy()
	end
end)

local RunService = game:GetService("RunService")

RunService.Heartbeat:Connect(function()
	for _, resource in CollectionService:GetTagged("Resource") do
		if not resource:IsDescendantOf(workspace) then continue end

		local root
		if resource:IsA("Model") then
			root = resource.PrimaryPart
		elseif resource:IsA("BasePart") then
			root = resource
		end
		if not root then continue end

		local lv = root:FindFirstChild("FloatVelocity")
		if not lv then continue end

		local diff = FLOAT_Y - root.Position.Y
		lv.VectorVelocity = Vector3.new(0, diff * 5, 0)
	end
end)

while true do
	task.wait(3)

	local boat = getBoat()
	if not boat then continue end

	local root = boat.PrimaryPart

	local spawnPos =
		root.Position
		+ root.CFrame.LookVector * math.random(160, 240)
		+ Vector3.new(math.random(-60, 60), FLOAT_Y, math.random(-60, 60))

	local clone = rs:FindFirstChild("Log"):Clone()

	if not clone.PrimaryPart then
		local first = clone:FindFirstChildWhichIsA("BasePart", true)
		if first then
			clone.PrimaryPart = first
		end
	end

	clone:PivotTo(CFrame.new(spawnPos))
	clone.Parent = workspace

	local cRoot = clone.PrimaryPart
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			if part ~= cRoot then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = cRoot
				weld.Part1 = part
				weld.Parent = cRoot
			end
		end
	end

	local att = Instance.new("Attachment")
	att.Parent = cRoot

	local floatVelocity = Instance.new("LinearVelocity")
	floatVelocity.Name = "FloatVelocity"
	floatVelocity.Attachment0 = att
	floatVelocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	floatVelocity.MaxAxesForce = Vector3.new(0, 10000, 0)
	floatVelocity.VectorVelocity = Vector3.new(0, 0, 0)
	floatVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	floatVelocity.Parent = cRoot

	CollectionService:AddTag(clone, "Resource")

	task.delay(LIFETIME, function()
		if clone and clone.Parent then
			clickCounts[clone] = nil
			clone:Destroy()
		end
	end)
end
