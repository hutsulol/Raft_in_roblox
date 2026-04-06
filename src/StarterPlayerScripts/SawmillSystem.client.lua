local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

local sawmillActionEvent = ReplicatedStorage:WaitForChild("SawmillAction")

-- Constants (must match server)
local SLIDE_TIME = 5
local SAW_TIME = 1.5
local OUTPUT_TIME = 3

local HEXAGON_SPIN_SPEED = math.rad(360)

-- Track spinning sawmills
local spinningSawmills = {}
local spinAngles = {}

-- Track active belt animations (client-side visual only)
local activeAnimations = {}

-- Billboard state
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

local function getSpinMotors(sawmill)
	local motors = {}
	for _, desc in sawmill:GetDescendants() do
		if desc:IsA("Motor6D") and desc.Name == "SpinMotor" then
			table.insert(motors, desc)
		end
	end
	return motors
end

local function getSawmillParts(sawmill)
	local parts = { hexagonPlacer = nil, hexagonClaimer = nil, sawBlade = nil }
	for _, child in sawmill:GetDescendants() do
		if child.Name == "Hexagon_placer" then parts.hexagonPlacer = child end
		if child.Name == "Hexagon_claimer" then parts.hexagonClaimer = child end
		if child.Name == "SawBlade" then parts.sawBlade = child end
	end
	return parts
end

local function getPartPosition(part)
	if part:IsA("Model") then return part:GetPivot().Position end
	return part.CFrame.Position
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

-- ─── Create a local-only visual clone (no physics, no replication) ───
local function createVisualClone(templateName)
	local template = ReplicatedStorage:FindFirstChild(templateName)
	if not template then return nil end

	local clone = template:Clone()
	if clone:IsA("Model") and not clone.PrimaryPart then
		local first = clone:FindFirstChildWhichIsA("BasePart")
		if first then clone.PrimaryPart = first end
	end

	-- Make completely non-physical
	if clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CanQuery = false
	end
	for _, p in clone:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
		end
	end

	clone.Parent = workspace
	return clone
end

-- ─── Start belt animation for a sawmill (client-side visuals only) ───
local function startBeltAnimation(sawmill)
	local parts = getSawmillParts(sawmill)
	if not parts.hexagonPlacer or not parts.sawBlade or not parts.hexagonClaimer then return end

	local startTime = tick()

	-- Create log visual
	local logClone = createVisualClone("Log")

	local anim = {
		sawmill = sawmill,
		parts = parts,
		startTime = startTime,
		logClone = logClone,
		plankClone = nil,
		phase = "log", -- "log", "sawing", "plank", "done"
	}

	activeAnimations[sawmill] = anim
end

-- ─── Update each frame ───
RunService.RenderStepped:Connect(function(dt)
	-- Spin motors for active sawmills
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
			motor.Transform = CFrame.Angles(0, angle, 0)
		end
	end

	-- Update belt animations
	for sawmill, anim in activeAnimations do
		if not sawmill or not sawmill.Parent then
			-- Clean up
			if anim.logClone and anim.logClone.Parent then anim.logClone:Destroy() end
			if anim.plankClone and anim.plankClone.Parent then anim.plankClone:Destroy() end
			activeAnimations[sawmill] = nil
			continue
		end

		local elapsed = tick() - anim.startTime
		local parts = anim.parts

		-- Validate parts still exist
		if not parts.hexagonPlacer or not parts.hexagonPlacer.Parent then
			activeAnimations[sawmill] = nil
			continue
		end

		-- Read current world positions of sawmill parts (they move with raft)
		local placerPos = getPartPosition(parts.hexagonPlacer) + Vector3.new(0, 1.5, 0)
		local sawBladePos = getPartPosition(parts.sawBlade) + Vector3.new(0, 1.5, 0)
		local claimerPos = getPartPosition(parts.hexagonClaimer) + Vector3.new(0, 1.5, 0)

		-- Belt direction for orientation
		local beltDir = (claimerPos - placerPos)
		beltDir = Vector3.new(beltDir.X, 0, beltDir.Z)
		if beltDir.Magnitude < 0.01 then beltDir = Vector3.new(1, 0, 0) end
		beltDir = beltDir.Unit

		-- Orientation: face along belt, tip 90° on X to lie flat
		local orientCF = CFrame.lookAt(Vector3.zero, beltDir) * CFrame.Angles(math.rad(90), 0, 0)

		if elapsed < SLIDE_TIME then
			-- Phase 1: Log slides from placer to saw blade
			local t = elapsed / SLIDE_TIME
			local pos = placerPos:Lerp(sawBladePos, t)
			if anim.logClone and anim.logClone.Parent then
				anim.logClone:PivotTo(orientCF + pos)
			end

		elseif elapsed < SLIDE_TIME + SAW_TIME then
			-- Phase 2: Sawing - destroy log
			if anim.logClone and anim.logClone.Parent then
				anim.logClone:Destroy()
				anim.logClone = nil
			end

			-- Create plank visual if not yet
			if not anim.plankClone then
				anim.plankClone = createVisualClone("plank")
			end
			-- Keep plank at saw blade during sawing
			if anim.plankClone and anim.plankClone.Parent then
				anim.plankClone:PivotTo(orientCF + sawBladePos)
			end

		elseif elapsed < SLIDE_TIME + SAW_TIME + OUTPUT_TIME then
			-- Phase 3: Plank slides from saw blade to claimer
			if anim.logClone and anim.logClone.Parent then
				anim.logClone:Destroy()
				anim.logClone = nil
			end
			if not anim.plankClone then
				anim.plankClone = createVisualClone("plank")
			end

			local plankElapsed = elapsed - SLIDE_TIME - SAW_TIME
			local t = plankElapsed / OUTPUT_TIME
			local pos = sawBladePos:Lerp(claimerPos, t)
			if anim.plankClone and anim.plankClone.Parent then
				anim.plankClone:PivotTo(orientCF + pos)
			end

		else
			-- Done: clean up client visuals (server spawns the real DroppedItem)
			if anim.logClone and anim.logClone.Parent then anim.logClone:Destroy() end
			if anim.plankClone and anim.plankClone.Parent then anim.plankClone:Destroy() end
			activeAnimations[sawmill] = nil
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

-- ─── Listen for server events ───
sawmillActionEvent.OnClientEvent:Connect(function(action, sawmill)
	if action == "startProcessing" then
		if sawmill and sawmill.Parent then
			spinningSawmills[sawmill] = true
			spinAngles[sawmill] = 0
			startBeltAnimation(sawmill)
		end
	elseif action == "stopProcessing" then
		if sawmill then
			spinningSawmills[sawmill] = nil
			spinAngles[sawmill] = nil
			local motors = getSpinMotors(sawmill)
			for _, motor in motors do
				motor.Transform = CFrame.new()
			end
			-- Clean up animation if still active
			if activeAnimations[sawmill] then
				local anim = activeAnimations[sawmill]
				if anim.logClone and anim.logClone.Parent then anim.logClone:Destroy() end
				if anim.plankClone and anim.plankClone.Parent then anim.plankClone:Destroy() end
				activeAnimations[sawmill] = nil
			end
		end
	end
end)
