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
local spinningSawmills = {} -- [sawmill] = true

-- Track billboard UIs
local activeBillboards = {} -- [sawmill] = billboardGui

local HEXAGON_SPIN_SPEED = math.rad(360) -- radians per second
local SAW_SPIN_SPEED = math.rad(720)

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

-- ─── Find specific part inside sawmill ───
local function findPartInSawmill(sawmill, partName)
	for _, desc in sawmill:GetDescendants() do
		if desc.Name == partName then
			return desc
		end
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
local function clearBillboard(sawmill)
	if activeBillboards[sawmill] then
		activeBillboards[sawmill]:Destroy()
		activeBillboards[sawmill] = nil
	end
end

local function showBillboard(adornee, text, subText)
	-- Find which sawmill this adornee belongs to
	local sawmill = findSawmillFromPart(adornee)
	if sawmill then clearBillboard(sawmill) end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(5, 0, 1.2, 0)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 20
	if adornee:IsA("BasePart") then
		billboard.Adornee = adornee
	elseif adornee:IsA("Model") then
		billboard.Adornee = adornee.PrimaryPart or adornee:FindFirstChildWhichIsA("BasePart")
	end
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

	if sawmill then
		activeBillboards[sawmill] = billboard
	end

	return billboard
end

-- ─── Track what the mouse is hovering over ───
local hoveredSawmill = nil
local hoveredPart = nil -- "placer" or "claimer"
local hoveredPartInstance = nil

local function getHoveredSawmillPart()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		params.FilterDescendantsInstances = {player.Character}
	end

	local result = workspace:Raycast(ray.Origin, ray.Direction * 30, params)
	if not result or not result.Instance then
		return nil, nil, nil
	end

	local hit = result.Instance

	-- Check if we hit a Hexagon_placer or Hexagon_claimer, or are inside a sawmill
	local sawmill = findSawmillFromPart(hit)
	if not sawmill then return nil, nil, nil end

	-- Check which interactive part we're near
	local placer = findPartInSawmill(sawmill, "Hexagon_placer")
	local claimer = findPartInSawmill(sawmill, "Hexagon_claimer")

	-- Check if hit is inside placer or claimer
	local current = hit
	while current and current ~= sawmill do
		if current == placer or current.Name == "Hexagon_placer" then
			return sawmill, "placer", placer
		elseif current == claimer or current.Name == "Hexagon_claimer" then
			return sawmill, "claimer", claimer
		end
		current = current.Parent
	end

	-- If we hit the sawmill but not a specific part, check proximity to placer/claimer
	if placer then
		local placerPos = placer:IsA("Model") and placer:GetPivot().Position or placer.CFrame.Position
		if (result.Position - placerPos).Magnitude < 5 then
			return sawmill, "placer", placer
		end
	end
	if claimer then
		local claimerPos = claimer:IsA("Model") and claimer:GetPivot().Position or claimer.CFrame.Position
		if (result.Position - claimerPos).Magnitude < 5 then
			return sawmill, "claimer", claimer
		end
	end

	return sawmill, nil, nil
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
	local sawmill, partType, partInstance = getHoveredSawmillPart()

	if sawmill ~= hoveredSawmill or partType ~= hoveredPart then
		-- Clear old billboard
		if hoveredSawmill then
			clearBillboard(hoveredSawmill)
		end
		_G.SuppressInventoryToggle = false

		hoveredSawmill = sawmill
		hoveredPart = partType
		hoveredPartInstance = partInstance

		if sawmill and partType and partInstance then
			local state = sawmill:GetAttribute("SawmillState") or "idle"
			_G.SuppressInventoryToggle = true

			if partType == "placer" then
				if state == "idle" then
					showBillboard(partInstance, "Press E to load wood", "Sawmill")
				elseif state == "processing" then
					showBillboard(partInstance, "Processing...", "Sawmill")
				elseif state == "ready" then
					showBillboard(partInstance, "Planks ready!", "Collect from other side")
				end
			elseif partType == "claimer" then
				if state == "ready" then
					local planks = sawmill:GetAttribute("PlanksReady") or 0
					showBillboard(partInstance, "Press E to collect", "Plank x" .. planks)
				elseif state == "processing" then
					showBillboard(partInstance, "Processing...", "Sawmill")
				elseif state == "idle" then
					showBillboard(partInstance, "Load wood first", "Use the other side")
				end
			end
		end
	end
end)

-- ─── E key interaction ───
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.E then return end

	if not hoveredSawmill or not hoveredPart or not hoveredPartInstance then return end

	local state = hoveredSawmill:GetAttribute("SawmillState") or "idle"

	if hoveredPart == "placer" and state == "idle" then
		-- Load a log
		sawmillActionEvent:FireServer("loadLog", hoveredPartInstance)
	elseif hoveredPart == "claimer" and state == "ready" then
		-- Claim planks
		sawmillActionEvent:FireServer("claimPlanks", hoveredPartInstance)
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
