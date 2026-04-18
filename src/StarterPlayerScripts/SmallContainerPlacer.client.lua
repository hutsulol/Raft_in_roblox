-- SmallContainerPlacer.client.lua
-- Ghost preview + placement click for the SmallContainer tool.
-- Copy of FurnacePlacer.client.lua with the template and action name
-- swapped so the container follows the exact same placement flow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

local placing = false
local ghost = nil
local lastGhostValid = false
local lastGhostRaftOffset = nil
local currentTool = nil
local rotationAngle = 0

local function getContainerTemplate()
	local folder = ReplicatedStorage:FindFirstChild("Containers_Player")
	local tmpl = folder and folder:FindFirstChild("Container_empty")
	if not tmpl then
		tmpl = ReplicatedStorage:FindFirstChild("Container_empty", true)
	end
	return tmpl
end

local function createGhost()
	if ghost then ghost:Destroy() end

	local template = getContainerTemplate()
	if not template then return end

	local archivable = template.Archivable
	template.Archivable = true
	ghost = template:Clone()
	template.Archivable = archivable
	ghost.Name = "SmallContainerGhost"

	if ghost:IsA("Model") then
		if not ghost.PrimaryPart then
			local first = ghost:FindFirstChildWhichIsA("BasePart", true)
			if first then ghost.PrimaryPart = first end
		end
		local bbCF = ghost:GetBoundingBox()
		ghost.WorldPivot = CFrame.new(bbCF.Position)
	end

	-- Strip anything that could couple the ghost to the raft: scripts,
	-- legacy welds / motors / attachments / constraints (the template may
	-- ship with pre-welded sub-parts or BodyMovers that would yank raft
	-- parts around the moment the ghost clones into workspace).
	for _, desc in ghost:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		elseif desc:IsA("Weld") or desc:IsA("Motor6D") or desc:IsA("Snap")
			or desc:IsA("WeldConstraint") or desc:IsA("RopeConstraint")
			or desc:IsA("Constraint") or desc:IsA("BodyMover") then
			desc:Destroy()
		elseif desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.Massless = true
			desc.Transparency = 0.5
			desc.Color = Color3.fromRGB(80, 255, 80)
			-- Smooth all surfaces so Roblox's legacy auto-welding can't
			-- stick the ghost to anything it clips through on the raft.
			desc.TopSurface = Enum.SurfaceType.Smooth
			desc.BottomSurface = Enum.SurfaceType.Smooth
			desc.FrontSurface = Enum.SurfaceType.Smooth
			desc.BackSurface = Enum.SurfaceType.Smooth
			desc.LeftSurface = Enum.SurfaceType.Smooth
			desc.RightSurface = Enum.SurfaceType.Smooth
		end
	end

	-- Park the ghost far underground before parenting so the first frame
	-- can never overlap the raft. updateGhost repositions it the moment
	-- the mouse produces a valid raycast.
	if ghost:IsA("Model") then
		ghost:PivotTo(CFrame.new(0, -10000, 0))
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
	Bed = true, Destitalor = true, bush = true,
	Furnace = true, Sawmill = true, SmallContainer = true,
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

	if not result.Instance:IsDescendantOf(raft) then
		setGhostColor(false)
		return
	end

	local hitPos = result.Position
	local _, ghostSize = ghost:GetBoundingBox()
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local placeCF = CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z)
		* CFrame.Angles(0, restYaw + rotationAngle, 0)

	ghost:PivotTo(placeCF)

	lastGhostRaftOffset = raft.PrimaryPart.CFrame:ToObjectSpace(placeCF)

	local blocked = isPlacementBlocked(placeCF, ghostSize)
	setGhostColor(not blocked)
end

local function onToolEquipped(tool)
	currentTool = tool
	if tool.Name == "SmallContainer" then
		placing = true
		rotationAngle = 0
		createGhost()
	end
end

local function onToolUnequipped(tool)
	if tool.Name == "SmallContainer" then
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
		if child:IsA("Tool") and child.Name == "SmallContainer" then
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
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.R and placing then
		rotationAngle = rotationAngle + math.rad(90)
	end
end)

mouse.Button1Down:Connect(function()
	if not placing or not ghost then return end
	if not lastGhostValid or not lastGhostRaftOffset then return end

	cupActionEvent:FireServer("placeSmallContainer", lastGhostRaftOffset)

	local folder = SoundService:FindFirstChild("Building")
	local snd = folder and folder:FindFirstChild("Place_Block")
	if snd then snd:Play() end

	destroyGhost()
	placing = false
end)
