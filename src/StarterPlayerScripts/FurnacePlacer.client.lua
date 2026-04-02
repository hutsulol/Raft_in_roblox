-- FurnacePlacer.client.lua
-- Handles ghost preview and placement when Furnace tool is equipped

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

-- ─── State ───
local placingFurnace = false
local ghost = nil
local lastGhostValid = false
local lastGhostRaftOffset = nil
local currentTool = nil
local rotationAngle = 0 -- radians, incremented by R key

-- ─── Ghost ───
local function createGhost()
	if ghost then ghost:Destroy() end
	local template = ReplicatedStorage:FindFirstChild("Furnace")
	if not template then return end

	ghost = template:Clone()
	ghost.Name = "FurnaceGhost"

	local bbCF = ghost:GetBoundingBox()
	ghost.WorldPivot = CFrame.new(bbCF.Position)

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
local function isPlacementBlocked(placeCF, ghostSize)
	local raft = workspace:FindFirstChild("Raft")
	if not raft then return true end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {ghost, player.Character}

	local checkSize = ghostSize * 0.7
	local parts = workspace:GetPartBoundsInBox(placeCF, checkSize, overlapParams)

	local placedObjectNames = {
		WorkBench = true, Purifier = true, Garden = true,
		Bed = true, Destitalor = true, bush = true, Furnace = true,
	}

	for _, part in parts do
		if part:IsDescendantOf(raft) then
			local current = part
			while current and current ~= raft do
				if current:IsA("Model") and placedObjectNames[current.Name] then
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

	-- Check if hit is on the raft
	local hitOnRaft = result.Instance:IsDescendantOf(raft)
	if not hitOnRaft then
		setGhostColor(false)
		return
	end

	-- Position ghost on top of hit surface with rotation
	local hitPos = result.Position
	local _, ghostSize = ghost:GetBoundingBox()
	local placeCF = CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z) * CFrame.Angles(0, rotationAngle, 0)

	ghost:PivotTo(placeCF)

	-- Calculate raft-local offset for server
	local raftOffset = raft.PrimaryPart.CFrame:ToObjectSpace(placeCF)
	lastGhostRaftOffset = raftOffset

	-- Check if blocked
	local blocked = isPlacementBlocked(placeCF, ghostSize)
	setGhostColor(not blocked)
end

-- ─── Tool equip ───
local function onToolEquipped(tool)
	currentTool = tool
	if tool.Name == "Furnace" then
		placingFurnace = true
		rotationAngle = 0
		createGhost()
	end
end

local function onToolUnequipped(tool)
	if tool.Name == "Furnace" then
		placingFurnace = false
		destroyGhost()
	end
	if currentTool == tool then
		currentTool = nil
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
		if child:IsA("Tool") and child.Name == "Furnace" then
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
	if placingFurnace and ghost then
		updateGhost()
	end
end)

-- ─── R key to rotate ───
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.R and placingFurnace then
		rotationAngle = rotationAngle + math.rad(90)
	end
end)

-- ─── Click to place ───
mouse.Button1Down:Connect(function()
	if not placingFurnace or not ghost then return end
	if not lastGhostValid or not lastGhostRaftOffset then return end

	cupActionEvent:FireServer("placeFurnace", lastGhostRaftOffset)
	destroyGhost()
	placingFurnace = false
end)
