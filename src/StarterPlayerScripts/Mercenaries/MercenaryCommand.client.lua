-- MercenaryCommand.client.lua
-- Provides an E-key interaction for spawned mercenaries and a
-- building-system-style placement UI for setting a fishing location.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local commandEvent = ReplicatedStorage:WaitForChild("MercenaryCommand")

-- ── State ───────────────────────────────────────────────────────────────
local targetMerc = nil           -- model currently under crosshair
local promptBillboard = nil      -- small "[E] Command" BillboardGui
local commandMenuGui = nil       -- full command menu ScreenGui
local commandMenuOpen = false
local isPlacingLocation = false  -- phase 1: pick raft spot
local isPlacingCast = false      -- phase 2: pick water cast spot
local placingMercName = nil
local pendingRaftPart = nil      -- saved from phase 1 for the server
local pendingRaftOffset = nil
local previewCircle = nil
local renderConn = nil
local inputConn = nil
local cancelConn = nil

local MAX_INTERACT_DISTANCE = 20

-- ── Helpers ─────────────────────────────────────────────────────────────

local function getAncestorWithTag(instance, tag)
	local current = instance
	while current and current ~= workspace do
		if CollectionService:HasTag(current, tag) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function isOwnedMercenary(model)
	return model and model:GetAttribute("OwnerUserId") == player.UserId
end

local function hasFishingRod(model)
	return model and model:GetAttribute("EquippedWeapon") == "FishingRod"
end

local function distanceToModel(model)
	local char = player.Character
	if not char then return math.huge end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return math.huge end
	local mercHrp = model:FindFirstChild("HumanoidRootPart")
	if not mercHrp then return math.huge end
	return (hrp.Position - mercHrp.Position).Magnitude
end

-- ── Prompt billboard ("[E] Command") ────────────────────────────────────

local function destroyPrompt()
	if promptBillboard then
		promptBillboard:Destroy()
		promptBillboard = nil
	end
end

local function createPrompt(model)
	destroyPrompt()

	local adornee = model:FindFirstChild("Head")
		or model:FindFirstChild("HumanoidRootPart")
	if not adornee then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "MercInteractPrompt"
	bb.Adornee = adornee
	bb.Size = UDim2.new(0, 120, 0, 36)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.ResetOnSpawn = false
	bb.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(255, 255, 0)
	label.Text = "[E] Command"
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.BorderSizePixel = 0
	label.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	promptBillboard = bb
end

-- ── Command menu (ScreenGui) ────────────────────────────────────────────

local function closeCommandMenu()
	if commandMenuGui then
		commandMenuGui:Destroy()
		commandMenuGui = nil
	end
	commandMenuOpen = false
	_G.SuppressInventoryToggle = false
end

local function openCommandMenu(model)
	closeCommandMenu()
	commandMenuOpen = true
	_G.SuppressInventoryToggle = true

	local mercName = model:GetAttribute("MercName")

	local gui = Instance.new("ScreenGui")
	gui.Name = "MercCommandMenu"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.Parent = playerGui

	-- Semi-transparent background to indicate menu mode
	local bg = Instance.new("Frame")
	bg.Name = "Backdrop"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BackgroundTransparency = 0.6
	bg.BorderSizePixel = 0
	bg.Parent = gui

	-- Central panel
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.new(0, 260, 0, 160)
	panel.Position = UDim2.new(0.5, -130, 0.5, -80)
	panel.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 36)
	title.Position = UDim2.new(0, 0, 0, 8)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "Mercenary Commands"
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = panel

	-- "Set Fishing Location" button (only shown if mercenary has a fishing rod)
	if hasFishingRod(model) then
		local btn = Instance.new("TextButton")
		btn.Name = "SetFishingBtn"
		btn.Size = UDim2.new(0.85, 0, 0, 42)
		btn.Position = UDim2.new(0.075, 0, 0, 52)
		btn.BackgroundColor3 = Color3.fromRGB(50, 140, 80)
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Text = "Set Fishing Location"
		btn.Font = Enum.Font.GothamBold
		btn.TextScaled = true
		btn.BorderSizePixel = 0
		btn.Parent = panel

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 8)
		btnCorner.Parent = btn

		btn.MouseButton1Click:Connect(function()
			closeCommandMenu()
			if mercName then
				startPlacementMode(mercName)
			end
		end)
	end

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0.85, 0, 0, 36)
	closeBtn.Position = UDim2.new(0.075, 0, 1, -46)
	closeBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Text = "Close"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextScaled = true
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = panel

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 8)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		closeCommandMenu()
	end)

	commandMenuGui = gui
end

-- ── Preview circle ──────────────────────────────────────────────────────

local CIRCLE_DIAMETER = 6
local CIRCLE_COLOR_VALID = Color3.fromRGB(80, 200, 80)
local CIRCLE_COLOR_INVALID = Color3.fromRGB(200, 80, 80)
local placementValid = false -- true when circle is on the raft

local function createPreviewCircle()
	if previewCircle then previewCircle:Destroy() end

	local part = Instance.new("Part")
	part.Name = "FishingLocationPreview"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.15, CIRCLE_DIAMETER, CIRCLE_DIAMETER)
	part.Anchored = true
	part.CanCollide = false
	part.Color = CIRCLE_COLOR_VALID
	part.Material = Enum.Material.Neon
	part.Transparency = 0.4
	part.CastShadow = false
	part.Parent = workspace

	previewCircle = part
end

local function destroyPreviewCircle()
	if previewCircle then
		previewCircle:Destroy()
		previewCircle = nil
	end
end

local function moveCircleTo(worldPos)
	if not previewCircle then return end
	previewCircle.CFrame = CFrame.new(worldPos) * CFrame.Angles(0, 0, math.rad(90))
end

-- ── Placement hint UI ───────────────────────────────────────────────────

local hintGui = nil

local function showHint(text)
	if hintGui then hintGui:Destroy(); hintGui = nil end

	hintGui = Instance.new("ScreenGui")
	hintGui.Name = "FishingLocationHint"
	hintGui.ResetOnSpawn = false
	hintGui.DisplayOrder = 30
	hintGui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 400, 0, 36)
	label.Position = UDim2.new(0.5, -200, 1, -100)
	label.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = text
	label.Font = Enum.Font.Gotham
	label.TextScaled = true
	label.BorderSizePixel = 0
	label.Parent = hintGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
end

local function hideHint()
	if hintGui then
		hintGui:Destroy()
		hintGui = nil
	end
end

-- ── Raycast (raft-only) ─────────────────────────────────────────────────

local raftRayParams = RaycastParams.new()
raftRayParams.FilterType = Enum.RaycastFilterType.Include
raftRayParams.IgnoreWater = true

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

-- Returns hitPosition, isOnRaft, hitPart, localOffset
local function raycastFromMouse()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)

	local raft = getRaft()
	if raft then
		-- Only accept hits on the raft itself
		raftRayParams.FilterDescendantsInstances = {raft}
		local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, raftRayParams)
		if result then
			local localOffset = result.Instance.CFrame:PointToObjectSpace(result.Position)
			return result.Position, true, result.Instance, localOffset
		end
	end

	-- Not on raft — still return a world position so the circle follows
	-- the cursor (shown in red), but mark it as invalid.
	local allParams = RaycastParams.new()
	allParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}
	if previewCircle then table.insert(filterList, previewCircle) end
	if player.Character then table.insert(filterList, player.Character) end
	allParams.FilterDescendantsInstances = filterList
	allParams.IgnoreWater = false

	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, allParams)
	if result then
		return result.Position, false, nil, nil
	end

	-- Plane fallback at y=0
	local denom = ray.Direction.Y
	if math.abs(denom) < 0.001 then return nil, false, nil, nil end
	local t = -ray.Origin.Y / denom
	if t < 0 then return nil, false, nil, nil end
	return ray.Origin + ray.Direction * t, false, nil, nil
end

-- ── Water raycast ────────────────────────────────────────────────────────

local waterRayParams = RaycastParams.new()
waterRayParams.FilterType = Enum.RaycastFilterType.Exclude
waterRayParams.IgnoreWater = false

-- Returns hitPosition, isOnWater
local function raycastWaterFromMouse()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)

	local filterList = {}
	if previewCircle then table.insert(filterList, previewCircle) end
	if player.Character then table.insert(filterList, player.Character) end
	-- Also exclude all SpawnedMercenary models
	for _, merc in CollectionService:GetTagged("SpawnedMercenary") do
		table.insert(filterList, merc)
	end
	waterRayParams.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, waterRayParams)
	if result then
		local isWater = result.Material == Enum.Material.Water
		return result.Position, isWater
	end

	return nil, false
end

-- ── Placement mode (shared cleanup) ─────────────────────────────────────

local function stopAllPlacement()
	isPlacingLocation = false
	isPlacingCast = false
	placingMercName = nil
	pendingRaftPart = nil
	pendingRaftOffset = nil
	placementValid = false
	destroyPreviewCircle()
	hideHint()
	_G.SuppressInventoryToggle = false

	if renderConn then renderConn:Disconnect(); renderConn = nil end
	if inputConn then inputConn:Disconnect(); inputConn = nil end
	if cancelConn then cancelConn:Disconnect(); cancelConn = nil end
end

-- ── Phase 2: pick water cast target ─────────────────────────────────────

local function startCastPlacementMode()
	-- Disconnect old connections from phase 1
	if renderConn then renderConn:Disconnect(); renderConn = nil end
	if inputConn then inputConn:Disconnect(); inputConn = nil end
	if cancelConn then cancelConn:Disconnect(); cancelConn = nil end

	isPlacingLocation = false
	isPlacingCast = true
	placementValid = false

	destroyPreviewCircle()
	createPreviewCircle()
	showHint("Click on the water to cast the fishing line  |  Esc to cancel")

	renderConn = RunService.RenderStepped:Connect(function()
		if not isPlacingCast or not previewCircle then return end

		local hitPos, isWater = raycastWaterFromMouse()
		if hitPos then
			moveCircleTo(hitPos + Vector3.new(0, 0.1, 0))
			previewCircle.Transparency = 0.4
			placementValid = isWater
			previewCircle.Color = isWater and Color3.fromRGB(80, 140, 220) or CIRCLE_COLOR_INVALID
		else
			previewCircle.Transparency = 1
			placementValid = false
		end
	end)

	inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not placementValid then return end

		local hitPos, isWater = raycastWaterFromMouse()
		if not hitPos or not isWater then return end

		-- Send both the raft location and the cast target to the server
		commandEvent:FireServer(
			"setFishingLocation", placingMercName,
			pendingRaftPart, pendingRaftOffset, hitPos
		)
		stopAllPlacement()
	end)

	cancelConn = UserInputService.InputBegan:Connect(function(input, _)
		if input.KeyCode == Enum.KeyCode.Escape then
			stopAllPlacement()
		end
	end)
end

-- ── Phase 1: pick raft spot ─────────────────────────────────────────────

function startPlacementMode(mercName)
	if isPlacingLocation or isPlacingCast then stopAllPlacement() end

	isPlacingLocation = true
	placingMercName = mercName
	placementValid = false
	_G.SuppressInventoryToggle = true

	createPreviewCircle()
	showHint("Click on the raft to set fishing location  |  Esc to cancel")

	renderConn = RunService.RenderStepped:Connect(function()
		if not isPlacingLocation or not previewCircle then return end

		local hitPos, onRaft = raycastFromMouse()
		if hitPos then
			moveCircleTo(hitPos + Vector3.new(0, 0.1, 0))
			previewCircle.Transparency = 0.4
			placementValid = onRaft
			previewCircle.Color = onRaft and CIRCLE_COLOR_VALID or CIRCLE_COLOR_INVALID
		else
			previewCircle.Transparency = 1
			placementValid = false
		end
	end)

	inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not placementValid then return end

		local hitPos, onRaft, hitPart, localOffset = raycastFromMouse()
		if not hitPos or not onRaft or not hitPart then return end

		-- Save raft data and transition to phase 2
		pendingRaftPart = hitPart
		pendingRaftOffset = localOffset
		startCastPlacementMode()
	end)

	cancelConn = UserInputService.InputBegan:Connect(function(input, _)
		if input.KeyCode == Enum.KeyCode.Escape then
			stopAllPlacement()
		end
	end)
end

-- ── Hover detection: show "[E] Command" prompt ──────────────────────────

RunService.RenderStepped:Connect(function()
	if isPlacingLocation or isPlacingCast or commandMenuOpen then
		if promptBillboard then destroyPrompt() end
		return
	end

	local target = mouse.Target
	local mercModel = target and getAncestorWithTag(target, "SpawnedMercenary")

	if mercModel
		and isOwnedMercenary(mercModel)
		and hasFishingRod(mercModel)
		and distanceToModel(mercModel) <= MAX_INTERACT_DISTANCE
	then
		if mercModel ~= targetMerc then
			targetMerc = mercModel
			createPrompt(mercModel)
		end
	else
		if targetMerc then
			targetMerc = nil
			destroyPrompt()
		end
	end
end)

-- ── E key interaction ───────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.E then return end

	-- Close the command menu if it's already open
	if commandMenuOpen then
		closeCommandMenu()
		return
	end

	-- Open command menu if looking at a mercenary
	if targetMerc and targetMerc.Parent then
		-- Suppress inventory toggle so it doesn't open at the same time
		_G.SuppressInventoryToggle = true
		openCommandMenu(targetMerc)
		destroyPrompt()
	end
end)
