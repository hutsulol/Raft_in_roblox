local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

local sawmillActionEvent = ReplicatedStorage:WaitForChild("SawmillAction")

-- Track which sawmills are currently spinning
local spinningSawmills = {}

-- Track cumulative rotation angle per sawmill
local spinAngles = {}

local HEXAGON_SPIN_SPEED = math.rad(360)

-- Billboard for "Drop a log here" hint
local activeBillboard = nil
local billboardSawmill = nil

local function findSawmillFromPart(part)
	local current = part
	while current and current ~= workspace do
		if current:GetAttribute("IsSawmill") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Find all Motor6D joints named "SpinMotor" inside the sawmill
local function getSpinMotors(sawmill)
	local motors = {}
	for _, desc in sawmill:GetDescendants() do
		if desc:IsA("Motor6D") and desc.Name == "SpinMotor" then
			table.insert(motors, desc)
		end
	end
	return motors
end

local function clearBillboard()
	if activeBillboard then
		activeBillboard:Destroy()
		activeBillboard = nil
	end
	billboardSawmill = nil
end

local function showBillboard(part, text, subText, sawmill)
	clearBillboard()

	local adornee = part
	if part:IsA("Model") then
		adornee = part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart")
	end
	if not adornee then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(5, 0, 1.2, 0)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 20
	billboard.Adornee = adornee
	billboard.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.5, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 220, 100)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboard

	if subText then
		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.new(1, 0, 0.4, 0)
		sub.Position = UDim2.new(0, 0, 0.55, 0)
		sub.BackgroundTransparency = 1
		sub.Text = subText
		sub.TextColor3 = Color3.fromRGB(220, 220, 220)
		sub.TextStrokeTransparency = 0.4
		sub.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		sub.Font = Enum.Font.Gotham
		sub.TextScaled = true
		sub.Parent = billboard
	end

	activeBillboard = billboard
	billboardSawmill = sawmill
end

-- ─── Update each frame ───
RunService.RenderStepped:Connect(function(dt)
	-- Spin motors for active sawmills (safe: doesn't fight physics)
	for sawmill, _ in spinningSawmills do
		if not sawmill or not sawmill.Parent then
			spinningSawmills[sawmill] = nil
			spinAngles[sawmill] = nil
			continue
		end

		spinAngles[sawmill] = (spinAngles[sawmill] or 0) + HEXAGON_SPIN_SPEED * dt

		local angle = spinAngles[sawmill]
		local motors = getSpinMotors(sawmill)
		for _, motor in motors do
			-- Rotate forward (around the roller's axle axis)
			motor.Transform = CFrame.Angles(angle, 0, 0)
		end
	end

	-- Hover detection for billboard hints
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		params.FilterDescendantsInstances = {player.Character}
	end

	local result = workspace:Raycast(ray.Origin, ray.Direction * 50, params)
	local sawmill = nil
	if result and result.Instance then
		sawmill = findSawmillFromPart(result.Instance)
	end

	if sawmill ~= billboardSawmill then
		clearBillboard()

		if sawmill then
			local state = sawmill:GetAttribute("SawmillState") or "idle"

			local placerPart = nil
			for _, desc in sawmill:GetDescendants() do
				if desc.Name == "Hexagon_placer" then
					placerPart = desc
					break
				end
			end

			local adornee = placerPart or sawmill

			if state == "idle" then
				showBillboard(adornee, "Drop a Log here", "Sawmill", sawmill)
			elseif state == "processing" then
				showBillboard(adornee, "Processing...", "Sawmill", sawmill)
			end
		end
	end
end)

-- ─── Listen for server animation events ───
sawmillActionEvent.OnClientEvent:Connect(function(action, sawmill)
	if action == "startProcessing" then
		if sawmill and sawmill.Parent then
			spinningSawmills[sawmill] = true
			spinAngles[sawmill] = 0
		end
	elseif action == "stopProcessing" then
		if sawmill then
			spinningSawmills[sawmill] = nil
			spinAngles[sawmill] = nil
			-- Reset motors to default
			local motors = getSpinMotors(sawmill)
			for _, motor in motors do
				motor.Transform = CFrame.new()
			end
		end
	end
end)
