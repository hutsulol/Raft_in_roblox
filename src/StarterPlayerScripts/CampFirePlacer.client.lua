-- CampFirePlacer.client.lua
-- Ghost preview + click-to-place for the FireCamp tool. Mirrors
-- FurnacePlacer: hold the crafted "FireCamp" placeable tool, aim at
-- the raft, R to rotate, click to confirm. Placement is handed off
-- to CampFireSystem.server.lua via the shared CupAction event.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")

local player    = Players.LocalPlayer
local mouse     = player:GetMouse()
local camera    = workspace.CurrentCamera

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

local placing = false
local ghost = nil
local lastGhostValid = false
local lastGhostRaftOffset = nil
local rotationAngle = 0

local function createGhost()
	if ghost then ghost:Destroy() end
	local template = ReplicatedStorage:FindFirstChild("FireCamp")
	if not template then return end

	ghost = template:Clone()
	ghost.Name = "FireCampGhost"

	if not ghost.PrimaryPart then
		local bbCF = ghost:GetBoundingBox()
		ghost.WorldPivot = CFrame.new(bbCF.Position)
	end

	for _, d in ghost:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 0.5
			d.CanCollide = false
			d.Anchored = true
			d.Color = Color3.fromRGB(80, 255, 80)
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("ParticleEmitter") or d:IsA("Smoke") or d:IsA("Fire") then
			d.Enabled = false
		elseif d:IsA("Light") then
			d.Enabled = false
		end
	end
	ghost.Parent = workspace
end

local function destroyGhost()
	if ghost then ghost:Destroy() ghost = nil end
	lastGhostValid = false
	lastGhostRaftOffset = nil
end

local function setGhostColor(valid)
	lastGhostValid = valid
	local color = valid and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
	if ghost then
		for _, p in ghost:GetDescendants() do
			if p:IsA("BasePart") then p.Color = color end
		end
	end
end

local PLACED_NAMES = {
	WorkBench = true, Purifier = true, Garden = true, Bed_T = true,
	Bed = true, Destitalor = true, bush = true, Furnace = true,
	Sawmill = true, FireCamp = true,
}

local function isPlacementBlocked(placeCF, ghostSize)
	local raft = workspace:FindFirstChild("Raft")
	if not raft then return true end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {ghost, player.Character}

	local parts = workspace:GetPartBoundsInBox(placeCF, ghostSize * 0.7, overlapParams)
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
	if not raft or not raft.PrimaryPart then setGhostColor(false) return end

	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {ghost, player.Character}

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)
	if not result or not result.Instance then setGhostColor(false) return end
	if not result.Instance:IsDescendantOf(raft) then setGhostColor(false) return end

	local hitPos = result.Position
	local _, ghostSize = ghost:GetBoundingBox()
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local placeCF = CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z)
		* CFrame.Angles(0, restYaw + rotationAngle, 0)

	ghost:PivotTo(placeCF)
	lastGhostRaftOffset = raft.PrimaryPart.CFrame:ToObjectSpace(placeCF)

	setGhostColor(not isPlacementBlocked(placeCF, ghostSize))
end

local function onToolEquipped(tool)
	if tool.Name == "FireCamp" then
		placing = true
		rotationAngle = 0
		createGhost()
	end
end

local function onToolUnequipped(tool)
	if tool.Name == "FireCamp" then
		placing = false
		destroyGhost()
	end
end

local function setupCharacter(char)
	if not char then return end
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then onToolEquipped(child) end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then onToolUnequipped(child) end
	end)
	for _, child in char:GetChildren() do
		if child:IsA("Tool") and child.Name == "FireCamp" then
			onToolEquipped(child)
			break
		end
	end
end

if player.Character then setupCharacter(player.Character) end
player.CharacterAdded:Connect(setupCharacter)

RunService.RenderStepped:Connect(function()
	if placing and ghost then updateGhost() end
end)

UserInputService.InputBegan:Connect(function(input)
	if UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.R and placing then
		rotationAngle = rotationAngle + math.rad(90)
	end
end)

mouse.Button1Down:Connect(function()
	if not placing or not ghost then return end
	if not lastGhostValid or not lastGhostRaftOffset then return end

	cupActionEvent:FireServer("placeCampFire", lastGhostRaftOffset)
	local folder = SoundService:FindFirstChild("Building")
	local snd = folder and folder:FindFirstChild("Place_Block")
	if snd then snd:Play() end
	destroyGhost()
	placing = false
end)
