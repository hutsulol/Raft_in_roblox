-- MercenaryCommand.client.lua
-- Provides a hover-over control menu for spawned mercenaries and a
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
local hoveredMerc = nil          -- model currently under cursor
local activeBillboard = nil      -- BillboardGui shown on hover
local isPlacingLocation = false  -- true while in placement mode
local placingMercName = nil      -- which mercenary we're placing for
local previewCircle = nil        -- green circle Part
local renderConn = nil           -- RenderStepped connection
local inputConn = nil            -- InputBegan connection for click
local cancelConn = nil           -- InputBegan connection for cancel

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
	return model
		and model:GetAttribute("OwnerUserId") == player.UserId
end

local function hasFishingRod(model)
	local weapon = model:GetAttribute("EquippedWeapon")
	return weapon == "FishingRod"
end

-- ── Billboard (hover menu) ─────────────────────────────────────────────

local function destroyBillboard()
	if activeBillboard then
		activeBillboard:Destroy()
		activeBillboard = nil
	end
end

local function createBillboard(model)
	destroyBillboard()

	local hrp = model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChild("Head")
	if not hrp then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "MercCommandMenu"
	bb.Adornee = hrp
	bb.Size = UDim2.new(0, 180, 0, 50)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.ResetOnSpawn = false
	bb.Parent = playerGui

	local btn = Instance.new("TextButton")
	btn.Name = "SetLocationBtn"
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.BackgroundColor3 = Color3.fromRGB(50, 140, 80)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Text = "Set Fishing Location"
	btn.Font = Enum.Font.GothamBold
	btn.TextScaled = true
	btn.BorderSizePixel = 0
	btn.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = btn

	btn.MouseButton1Click:Connect(function()
		local mercName = model:GetAttribute("MercName")
		if mercName then
			destroyBillboard()
			hoveredMerc = nil
			startPlacementMode(mercName)
		end
	end)

	activeBillboard = bb
end

-- ── Preview circle ──────────────────────────────────────────────────────

local CIRCLE_DIAMETER = 6
local CIRCLE_COLOR_VALID = Color3.fromRGB(80, 200, 80)

local function createPreviewCircle()
	if previewCircle then previewCircle:Destroy() end

	local part = Instance.new("Part")
	part.Name = "FishingLocationPreview"
	part.Shape = Enum.PartType.Cylinder
	-- Cylinder axis is along X; rotate so flat face is horizontal
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
	-- Cylinder: rotate 90 degrees around Z so the flat faces point up/down
	previewCircle.CFrame = CFrame.new(worldPos) * CFrame.Angles(0, 0, math.rad(90))
end

-- ── Placement hint UI ───────────────────────────────────────────────────

local hintGui = nil

local function showHint()
	if hintGui then return end

	hintGui = Instance.new("ScreenGui")
	hintGui.Name = "FishingLocationHint"
	hintGui.ResetOnSpawn = false
	hintGui.DisplayOrder = 30
	hintGui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 350, 0, 36)
	label.Position = UDim2.new(0.5, -175, 1, -100)
	label.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = "Click to set fishing location  |  Right-click / Esc to cancel"
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

-- ── Raycast to world surface ────────────────────────────────────────────

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false

local function raycastFromMouse()
	-- Exclude the preview circle and the player's character
	local filterList = {}
	if previewCircle then table.insert(filterList, previewCircle) end
	if player.Character then table.insert(filterList, player.Character) end
	rayParams.FilterDescendantsInstances = filterList

	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
	if result then
		return result.Position
	end

	-- Fallback: intersect with y = water level (approximate sea level at y=0)
	local waterY = 0
	local denom = ray.Direction.Y
	if math.abs(denom) < 0.001 then return nil end
	local t = (waterY - ray.Origin.Y) / denom
	if t < 0 then return nil end
	return ray.Origin + ray.Direction * t
end

-- ── Placement mode ──────────────────────────────────────────────────────

local function stopPlacementMode()
	isPlacingLocation = false
	placingMercName = nil
	destroyPreviewCircle()
	hideHint()

	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	if inputConn then
		inputConn:Disconnect()
		inputConn = nil
	end
	if cancelConn then
		cancelConn:Disconnect()
		cancelConn = nil
	end
end

function startPlacementMode(mercName)
	if isPlacingLocation then stopPlacementMode() end

	isPlacingLocation = true
	placingMercName = mercName

	createPreviewCircle()
	showHint()

	-- Move circle every frame
	renderConn = RunService.RenderStepped:Connect(function()
		if not isPlacingLocation or not previewCircle then return end

		local hitPos = raycastFromMouse()
		if hitPos then
			moveCircleTo(hitPos + Vector3.new(0, 0.1, 0))
			previewCircle.Transparency = 0.4
		else
			previewCircle.Transparency = 1
		end
	end)

	-- Left-click to confirm
	inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local hitPos = raycastFromMouse()
		if not hitPos then return end

		commandEvent:FireServer("setFishingLocation", placingMercName, hitPos)
		stopPlacementMode()
	end)

	-- Right-click or Escape to cancel
	cancelConn = UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			stopPlacementMode()
		elseif input.KeyCode == Enum.KeyCode.Escape then
			stopPlacementMode()
		end
	end)
end

-- ── Hover detection (runs every frame) ──────────────────────────────────

RunService.RenderStepped:Connect(function()
	-- Don't show hover menu while in placement mode
	if isPlacingLocation then return end

	local target = mouse.Target
	if not target then
		if hoveredMerc then
			hoveredMerc = nil
			destroyBillboard()
		end
		return
	end

	local mercModel = getAncestorWithTag(target, "SpawnedMercenary")

	if mercModel and isOwnedMercenary(mercModel) and hasFishingRod(mercModel) then
		if mercModel ~= hoveredMerc then
			hoveredMerc = mercModel
			createBillboard(mercModel)
		end
	else
		if hoveredMerc then
			hoveredMerc = nil
			destroyBillboard()
		end
	end
end)
