-- AnchorPlacer.client.lua
-- Ghost preview + click-to-place flow for the Anchor_part tool. Mirrors
-- BuildingSystem.client.lua's raft-tile placement (adjacent grid cell,
-- next to the existing raft, on the water) but uses the equipped
-- Anchor_part tool instead of the Hammer's category menu.
--
-- Crafted at the workbench for 1 Log; one tool == one placement —
-- BuildingSystem.server.lua destroys the tool when the anchor lands.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")

local player  = Players.LocalPlayer
local mouse   = player:GetMouse()
local camera  = workspace.CurrentCamera

local placeBlockEvent = ReplicatedStorage:WaitForChild("PlaceBlock")
local raftPartTemplate = ReplicatedStorage:WaitForChild("Raft_part")

local TOOL_NAME      = "Anchor_part"
local TEMPLATE_NAME  = "Anchor_part"
local PREVIEW_VALID  = Color3.fromRGB(80, 200, 80)
local PREVIEW_INVALID = Color3.fromRGB(200, 80, 80)

local GRID_SIZE = raftPartTemplate:GetAttribute("GridSize")
if not GRID_SIZE then
	if raftPartTemplate:IsA("Model") then
		local size = raftPartTemplate:GetExtentsSize()
		GRID_SIZE = math.max(size.X, size.Z)
	elseif raftPartTemplate:IsA("BasePart") then
		GRID_SIZE = math.max(raftPartTemplate.Size.X, raftPartTemplate.Size.Z)
	else
		GRID_SIZE = 6
	end
end

local ghost     = nil
local placing   = false
local lastValid = false
local lastGX, lastGZ

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

local function findTemplate()
	local t = ReplicatedStorage:FindFirstChild(TEMPLATE_NAME)
	if not t then t = ReplicatedStorage:FindFirstChild(TEMPLATE_NAME, true) end
	return t
end

local function getTileRotationCorrection(raft)
	local primary = raft.PrimaryPart
	if not primary then return CFrame.new() end
	for _, child in raft:GetChildren() do
		if child.Name == "Raft_part" and child ~= primary then
			local tileCF
			if child:IsA("Model") then
				tileCF = child:GetPivot()
			elseif child:IsA("BasePart") then
				tileCF = child.CFrame
			end
			if tileCF then
				return primary.CFrame:ToObjectSpace(tileCF).Rotation
			end
		end
	end
	return CFrame.new()
end

-- Same scan as BuildingSystem.client.lua's getFloorOffsets — collects
-- both player-built tiles (GridX/GridZ attributes) and initial Raft_part
-- tiles, projected onto the rest-yaw plane so wave tilt doesn't shift
-- the grid.
local function getFloorOffsets()
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return {} end

	local offsets = {}
	local seen = {}
	local primary = raft.PrimaryPart

	local restYaw = primary:GetAttribute("RestYaw")
	if not restYaw then
		local _, yaw, _ = primary.CFrame:ToEulerAnglesYXZ()
		restYaw = yaw
	end
	local flatCF = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0)

	for _, child in raft:GetChildren() do
		local gx = child:GetAttribute("GridX")
		local gz = child:GetAttribute("GridZ")
		if gx and gz and child:GetAttribute("BuildType") == "raft" then
			local key = gx .. "_" .. gz
			if not seen[key] then
				seen[key] = true
				table.insert(offsets, {x = gx, z = gz})
			end
		elseif child.Name == "Raft_part" or child == primary then
			local pos
			if child:IsA("Model") then
				pos = child:GetPivot().Position
			elseif child:IsA("BasePart") then
				pos = child.Position
			end
			if pos then
				local localPos = flatCF:PointToObjectSpace(pos)
				local gridX = math.round(localPos.X / GRID_SIZE)
				local gridZ = math.round(localPos.Z / GRID_SIZE)
				local key = gridX .. "_" .. gridZ
				if not seen[key] then
					seen[key] = true
					table.insert(offsets, {x = gridX, z = gridZ})
				end
			end
		end
	end
	if not seen["0_0"] then
		table.insert(offsets, {x = 0, z = 0})
	end
	return offsets
end

local function isFloorOccupied(offsets, gx, gz)
	for _, o in offsets do
		if o.x == gx and o.z == gz then return true end
	end
	return false
end

local function isFloorAdjacent(offsets, gx, gz)
	for _, o in offsets do
		if (math.abs(o.x - gx) == 1 and o.z == gz)
			or (math.abs(o.z - gz) == 1 and o.x == gx) then
			return true
		end
	end
	return false
end

-- Cursor → grid coordinate + world CFrame for the cell. Raycasts
-- against the water plane through the raft's rest-yaw, matching the
-- hammer's getFloorGridFromMouse so the preview lands where the
-- player expects.
local function getFloorGridFromMouse()
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return nil end
	local primary = raft.PrimaryPart
	local restYaw = primary:GetAttribute("RestYaw")
	if not restYaw then
		local _, yaw, _ = primary.CFrame:ToEulerAnglesYXZ()
		restYaw = yaw
	end
	local restFlat = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0)

	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	-- Plane intersect: y = primary.Position.Y
	local origin = unitRay.Origin
	local direction = unitRay.Direction
	if math.abs(direction.Y) < 1e-4 then return nil end
	local t = (primary.Position.Y - origin.Y) / direction.Y
	if t <= 0 or t > 600 then return nil end
	local hit = origin + direction * t

	local localHit = restFlat:PointToObjectSpace(hit)
	local gx = math.round(localHit.X / GRID_SIZE)
	local gz = math.round(localHit.Z / GRID_SIZE)

	local restCF = primary:GetAttribute("RestCFrame") or primary.CFrame
	local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(gx * GRID_SIZE, 0, gz * GRID_SIZE))
	local localOffset = restCF:VectorToObjectSpace(worldOffset)
	local worldCF = primary.CFrame * CFrame.new(localOffset) * getTileRotationCorrection(raft)
	return gx, gz, worldCF
end

local function colourGhost(valid)
	lastValid = valid
	if not ghost then return end
	local c = valid and PREVIEW_VALID or PREVIEW_INVALID
	for _, p in ghost:GetDescendants() do
		if p:IsA("BasePart") then
			p.Color = c
		end
	end
end

local function createGhost()
	if ghost then ghost:Destroy() end
	local template = findTemplate()
	if not template then return end
	ghost = template:Clone()
	ghost.Name = "AnchorGhost"
	if ghost:IsA("Model") then
		local bb = ghost:GetBoundingBox()
		ghost.WorldPivot = CFrame.new(bb.Position)
	end
	for _, p in ghost:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.Transparency = 0.5
		elseif p:IsA("Script") or p:IsA("LocalScript") then
			p:Destroy()
		end
	end
	if ghost:IsA("BasePart") then
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.Transparency = 0.5
	end
	ghost.Parent = workspace
	colourGhost(false)
end

local function destroyGhost()
	if ghost then ghost:Destroy(); ghost = nil end
	lastValid = false
	lastGX, lastGZ = nil, nil
end

local function updateGhost()
	if not ghost then return end
	local gx, gz, worldCF = getFloorGridFromMouse()
	if not gx then colourGhost(false); return end

	local offsets = getFloorOffsets()
	local valid = (not isFloorOccupied(offsets, gx, gz))
		and isFloorAdjacent(offsets, gx, gz)

	if ghost:IsA("Model") then
		ghost:PivotTo(worldCF)
	elseif ghost:IsA("BasePart") then
		ghost.CFrame = worldCF
	end

	lastGX, lastGZ = gx, gz
	colourGhost(valid)
end

local function onToolEquipped(tool)
	if tool.Name ~= TOOL_NAME then return end
	placing = true
	createGhost()
end

local function onToolUnequipped(tool)
	if tool and tool.Name ~= TOOL_NAME then return end
	placing = false
	destroyGhost()
end

local function setupCharacter(char)
	if not char then return end
	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then onToolEquipped(c) end
	end)
	char.ChildRemoved:Connect(function(c)
		if c:IsA("Tool") then onToolUnequipped(c) end
	end)
	for _, c in char:GetChildren() do
		if c:IsA("Tool") and c.Name == TOOL_NAME then
			onToolEquipped(c)
			break
		end
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

RunService.RenderStepped:Connect(function()
	if placing and ghost then updateGhost() end
end)

mouse.Button1Down:Connect(function()
	if not placing or not ghost then return end
	if not lastValid or not lastGX or not lastGZ then return end

	placeBlockEvent:FireServer("anchor", lastGX, lastGZ)

	local folder = SoundService:FindFirstChild("Building")
	local snd = folder and folder:FindFirstChild("Place_Block")
	if snd then snd:Play() end

	destroyGhost()
	placing = false
end)
