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

local function getSpinParts(sawmill)
	local hexagons = {}
	local sawBlade = nil
	for _, desc in sawmill:GetDescendants() do
		if desc.Name == "Hexagon" and desc:IsA("BasePart") then
			table.insert(hexagons, desc)
		elseif desc.Name == "SawBlade" and desc:IsA("BasePart") then
			sawBlade = desc
		end
	end
	return hexagons, sawBlade
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
	-- Spin hexagons and saw blades for active sawmills
	for sawmill, _ in spinningSawmills do
		if not sawmill or not sawmill.Parent then
			spinningSawmills[sawmill] = nil
			continue
		end

		local hexagons, sawBlade = getSpinParts(sawmill)
		for _, hex in hexagons do
			hex.CFrame = hex.CFrame * CFrame.Angles(HEXAGON_SPIN_SPEED * dt, 0, 0)
		end
		if sawBlade then
			sawBlade.CFrame = sawBlade.CFrame * CFrame.Angles(HEXAGON_SPIN_SPEED * dt, 0, 0)
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

			-- Find placer part for billboard
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
		end
	elseif action == "stopProcessing" then
		if sawmill then
			spinningSawmills[sawmill] = nil
		end
	end
end)
