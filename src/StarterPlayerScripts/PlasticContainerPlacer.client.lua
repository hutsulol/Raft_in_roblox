-- PlasticContainerPlacer.client.lua
-- Ghost preview + placement click for the PlasticContainer tool.
-- Exact same flow as SmallContainerPlacer, only the tool name,
-- template lookup, and server action differ.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

local TEMPLATE_NAME = "plastic_container"
local TOOL_NAME = "PlasticContainer"
local ACTION_NAME = "placePlasticContainer"

local ghost = nil
local placing = false
local currentTool = nil
local lastGhostValid = false
local lastGhostRaftOffset = nil
local rotationAngle = 0
local ghostTemplateRotation = CFrame.new()

local function findTemplate()
	local folder = ReplicatedStorage:FindFirstChild("Containers_Player")
	local tmpl = folder and folder:FindFirstChild(TEMPLATE_NAME)
	if not tmpl then
		tmpl = ReplicatedStorage:FindFirstChild(TEMPLATE_NAME, true)
	end
	return tmpl
end

local function createGhost()
	if ghost then ghost:Destroy() end
	local template = findTemplate()
	if not template then return end

	ghost = template:Clone()
	ghost.Name = "PlasticContainerGhost"

	local bbCF = ghost:GetBoundingBox()
	ghost.WorldPivot = CFrame.new(bbCF.Position)
	ghostTemplateRotation = CFrame.new()

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

local PLACED_NAMES = {
	WorkBench = true, Purifier = true, Garden = true,
	Bed_T = true,
	Bed = true, Destitalor = true, bush = true,
	Furnace = true, Sawmill = true,
	SmallContainer = true, PlasticContainer = true,
}

local function isPlacementBlocked(placeCF, ghostSize)
	local raft = workspace:FindFirstChild("Raft")
	if not raft then return true end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { ghost, player.Character }

	local checkSize = ghostSize * 0.7
	local parts = workspace:GetPartBoundsInBox(placeCF, checkSize, overlapParams)

	for _, part in parts do
		if part:IsDescendantOf(raft) then
			local current = part
			while current and current ~= raft do
				if current:IsA("Model") and PLACED_NAMES[current.Name] then
					return true
				end
				current = current.Parent
			end
		end
	end
	return false
end

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
	params.FilterDescendantsInstances = { ghost, player.Character }

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)
	if not result or not result.Instance then
		setGhostColor(false)
		return
	end

	local hitOnRaft = result.Instance:IsDescendantOf(raft)
	local hitPos = result.Position
	local ghostSize = ghost:GetExtentsSize()
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local placeCF = CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z)
		* CFrame.Angles(0, restYaw + rotationAngle, 0)
		* ghostTemplateRotation

	ghost:PivotTo(placeCF)

	if hitOnRaft then
		lastGhostRaftOffset = raft.PrimaryPart.CFrame:ToObjectSpace(placeCF)
		local blocked = isPlacementBlocked(placeCF, ghostSize)
		setGhostColor(not blocked)
	else
		setGhostColor(false)
	end
end

local function onToolEquipped(tool)
	currentTool = tool
	if tool.Name == TOOL_NAME then
		placing = true
		rotationAngle = 0
		createGhost()
	end
end

local function onToolUnequipped(tool)
	if tool and tool.Name == TOOL_NAME then
		placing = false
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
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			onToolEquipped(child)
			break
		end
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

RunService.RenderStepped:Connect(function()
	if placing and ghost then
		updateGhost()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.R and placing then
		rotationAngle = rotationAngle + math.rad(90)
	end
end)

mouse.Button1Down:Connect(function()
	if not placing or not ghost then return end
	if not lastGhostValid or not lastGhostRaftOffset then return end

	cupActionEvent:FireServer(ACTION_NAME, lastGhostRaftOffset)

	local folder = SoundService:FindFirstChild("Building")
	local snd = folder and folder:FindFirstChild("Place_Block")
	if snd then snd:Play() end

	destroyGhost()
	placing = false
end)
