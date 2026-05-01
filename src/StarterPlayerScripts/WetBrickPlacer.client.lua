-- WetBrickPlacer.client.lua
-- Handles ghost preview and placement when Wet_Brick tool is equipped

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local wetBrickAction = ReplicatedStorage:WaitForChild("WetBrickAction")

local BRICK_SIZE = Vector3.new(3, 1.4, 2)

-- ─── State ───
local placing = false
local ghost = nil
local lastGhostValid = false
local lastGhostRaftOffset = nil
local rotationAngle = 0

-- ─── Ghost ───
local function createGhost()
	if ghost then ghost:Destroy() end

	local template = ReplicatedStorage:FindFirstChild("Wet_Brick")
	if template then
		ghost = template:Clone()
		ghost.Name = "WetBrickGhost"
		if ghost:IsA("Model") then
			local bbCF = ghost:GetBoundingBox()
			ghost.WorldPivot = CFrame.new(bbCF.Position)
		end
	else
		-- Fallback simple part model
		ghost = Instance.new("Model")
		ghost.Name = "WetBrickGhost"
		local part = Instance.new("Part")
		part.Name = "Handle"
		part.Size = BRICK_SIZE
		part.Material = Enum.Material.Sand
		part.Color = Color3.fromRGB(96, 70, 50)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = true
		part.CanCollide = false
		part.Parent = ghost
		ghost.PrimaryPart = part
	end

	for _, part in ghost:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = 0.5
			part.CanCollide = false
			part.Anchored = true
			part.Color = Color3.fromRGB(80, 255, 80)
		end
		if part:IsA("Script") or part:IsA("LocalScript") then
			part:Destroy()
		end
		if part:IsA("ProximityPrompt") then
			part:Destroy()
		end
	end
	ghost.Parent = workspace
end

local function destroyGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	lastGhostValid = false
	lastGhostRaftOffset = nil
end

local function setGhostColor(valid)
	lastGhostValid = valid
	local color = valid and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
	if ghost then
		for _, part in ghost:GetDescendants() do
			if part:IsA("BasePart") then
				part.Color = color
			end
		end
	end
end

-- ─── Check overlap with placed objects ───
-- Full set of placeable model names — kept in sync across every
-- placer so any placeable blocks any other from overlapping it.
local PLACED_OBJECT_NAMES = {
	WorkBench       = true,
	Purifier        = true,
	Garden          = true,
	Bed             = true,
	Destitalor      = true,
	bush            = true,
	Furnace         = true,
	Sawmill         = true,
	SmallContainer  = true,
	PlasticContainer = true,
	Wet_Brick       = true,
	Dry_Brick       = true,
	Anchor_part     = true,
}

local function isInsidePlaceable(instance)
	local current = instance
	while current and current.Parent do
		if current:IsA("Model") and PLACED_OBJECT_NAMES[current.Name] then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function isPlacementBlocked(placeCF, ghostSize)
	local raft = workspace:FindFirstChild("Raft")
	if not raft then return true end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {ghost, player.Character}

	local checkSize = ghostSize * 0.7
	local parts = workspace:GetPartBoundsInBox(placeCF, checkSize, overlapParams)

	for _, part in parts do
		if part:IsDescendantOf(raft) then
			local current = part
			while current and current ~= raft do
				if current:IsA("Model") and PLACED_OBJECT_NAMES[current.Name] then
					return true
				end
				current = current.Parent
			end
		end
	end
	return false
end

-- ─── Update ghost position ───
local function updateGhost()
	if not ghost then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then
		setGhostColor(false)
		return
	end

	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {ghost, player.Character}

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)

	if not result or not result.Instance then
		setGhostColor(false)
		return
	end

	local hitOnRaft = result.Instance:IsDescendantOf(raft)
	-- Reject hits on top of an already-placed object so the brick
	-- can't stack on a container / purifier / workbench.
	local hitOnPlaceable = isInsidePlaceable(result.Instance)
	if not hitOnRaft or hitOnPlaceable then
		setGhostColor(false)
		return
	end

	local hitPos = result.Position
	local _, ghostSize = ghost:GetBoundingBox()
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local placeCF = CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z) * CFrame.Angles(0, restYaw + rotationAngle, 0)

	ghost:PivotTo(placeCF)

	lastGhostRaftOffset = raft.PrimaryPart.CFrame:ToObjectSpace(placeCF)

	local blocked = isPlacementBlocked(placeCF, ghostSize)
	setGhostColor(not blocked)
end

-- ─── Tool equip ───
local function onToolEquipped(tool)
	if tool.Name == "Wet_Brick" then
		placing = true
		rotationAngle = 0
		createGhost()
	end
end

local function onToolUnequipped(tool)
	if tool.Name == "Wet_Brick" then
		placing = false
		destroyGhost()
	end
end

local function setupCharacter(char)
	if not char then return end

	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			onToolEquipped(child)
		end
	end)

	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			onToolUnequipped(child)
		end
	end)

	for _, child in char:GetChildren() do
		if child:IsA("Tool") and child.Name == "Wet_Brick" then
			onToolEquipped(child)
			break
		end
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

-- ─── Frame update ───
RunService.RenderStepped:Connect(function()
	if placing and ghost then
		updateGhost()
	end
end)

-- ─── R key to rotate ───
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.R and placing then
		rotationAngle = rotationAngle + math.rad(90)
	end
end)

-- ─── Click to place ───
mouse.Button1Down:Connect(function()
	if not placing or not ghost then return end
	if not lastGhostValid or not lastGhostRaftOffset then return end

	wetBrickAction:FireServer("placeWetBrick", lastGhostRaftOffset)
	local folder = SoundService:FindFirstChild("Building")
	local snd = folder and folder:FindFirstChild("Place_Block")
	if snd then snd:Play() end
	destroyGhost()
	placing = false
end)
