local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

local sawmillActionEvent = ReplicatedStorage:WaitForChild("SawmillAction")

-- Track which sawmills are currently spinning
local spinningSawmills = {}

-- Track billboard UIs
local activeBillboards = {}

local HEXAGON_SPIN_SPEED = math.rad(360)

-- ─── Find sawmill from a hit part ───
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

-- ─── Get all hexagons and saw blade for spinning ───
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

-- ─── Billboard prompt management ───
local function clearAllBillboards()
	for sm, bb in activeBillboards do
		if bb and bb.Parent then bb:Destroy() end
	end
	activeBillboards = {}
end

local function showBillboard(adornee, text, subText, sawmill)
	if activeBillboards[sawmill] then
		activeBillboards[sawmill]:Destroy()
		activeBillboards[sawmill] = nil
	end

	local part = adornee
	if adornee:IsA("Model") then
		part = adornee.PrimaryPart or adornee:FindFirstChildWhichIsA("BasePart")
	end
	if not part then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(5, 0, 1.2, 0)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 20
	billboard.Adornee = part
	billboard.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.5, 0)
	label.Position = UDim2.new(0, 0, 0, 0)
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

	activeBillboards[sawmill] = billboard
end

-- ─── Determine which side of sawmill the player is looking at ───
local hoveredSawmill = nil
local hoveredSide = nil -- "placer" or "claimer"

local function detectSawmillHover()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		params.FilterDescendantsInstances = {player.Character}
	end

	local result = workspace:Raycast(ray.Origin, ray.Direction * 50, params)
	if not result or not result.Instance then
		return nil, nil
	end

	local sawmill = findSawmillFromPart(result.Instance)
	if not sawmill then return nil, nil end

	-- Find placer and claimer positions
	local placerPart, claimerPart
	for _, desc in sawmill:GetDescendants() do
		if desc.Name == "Hexagon_placer" then placerPart = desc end
		if desc.Name == "Hexagon_claimer" then claimerPart = desc end
	end

	if not placerPart and not claimerPart then
		return sawmill, nil
	end

	-- Determine which is closer to the hit point
	local hitPos = result.Position
	local side = nil

	local placerDist = math.huge
	local claimerDist = math.huge

	if placerPart then
		local pPos = placerPart:IsA("Model") and placerPart:GetPivot().Position or placerPart.CFrame.Position
		placerDist = (hitPos - pPos).Magnitude
	end
	if claimerPart then
		local cPos = claimerPart:IsA("Model") and claimerPart:GetPivot().Position or claimerPart.CFrame.Position
		claimerDist = (hitPos - cPos).Magnitude
	end

	if placerDist < claimerDist then
		side = "placer"
	else
		side = "claimer"
	end

	return sawmill, side
end

-- ─── Update hover state and billboards each frame ───
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

	-- Update hover detection
	local sawmill, side = detectSawmillHover()

	if sawmill ~= hoveredSawmill or side ~= hoveredSide then
		-- Clear old billboards
		clearAllBillboards()
		_G.SuppressInventoryToggle = false

		hoveredSawmill = sawmill
		hoveredSide = side

		if sawmill and side then
			local state = sawmill:GetAttribute("SawmillState") or "idle"
			_G.SuppressInventoryToggle = true

			-- Find the part to attach billboard to
			local adornee = sawmill
			for _, desc in sawmill:GetDescendants() do
				if side == "placer" and desc.Name == "Hexagon_placer" then
					adornee = desc
					break
				elseif side == "claimer" and desc.Name == "Hexagon_claimer" then
					adornee = desc
					break
				end
			end

			if side == "placer" then
				if state == "idle" then
					showBillboard(adornee, "Press E to load wood", "Sawmill", sawmill)
				elseif state == "processing" then
					showBillboard(adornee, "Processing...", "Sawmill", sawmill)
				elseif state == "ready" then
					showBillboard(adornee, "Planks ready!", "Collect from other side", sawmill)
				end
			elseif side == "claimer" then
				if state == "ready" then
					local planks = sawmill:GetAttribute("PlanksReady") or 0
					showBillboard(adornee, "Press E to collect", "Plank x" .. planks, sawmill)
				elseif state == "processing" then
					showBillboard(adornee, "Processing...", "Sawmill", sawmill)
				elseif state == "idle" then
					showBillboard(adornee, "Load wood first", "Use the other side", sawmill)
				end
			end
		end
	end
end)

-- ─── E key interaction ───
UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode ~= Enum.KeyCode.E then return end

	-- Don't check 'processed' here - our own billboard GUI causes it to be true
	if not hoveredSawmill or not hoveredSide then return end
	if not hoveredSawmill.Parent then return end

	local state = hoveredSawmill:GetAttribute("SawmillState") or "idle"

	if hoveredSide == "placer" and state == "idle" then
		sawmillActionEvent:FireServer("loadLog", hoveredSawmill)
	elseif hoveredSide == "claimer" and state == "ready" then
		sawmillActionEvent:FireServer("claimPlanks", hoveredSawmill)
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
