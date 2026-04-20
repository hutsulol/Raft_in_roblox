-- AnchorBuildSystem.client.lua
-- Standalone placement flow for the Anchor_part tool. Runs its own
-- ScreenGui, preview part, RenderStepped and click handler so it
-- can't conflict with BuildingSystem.client.lua's hammer state.
--
-- Uses the same grid math as the hammer (RestCFrame / rest-yaw,
-- nearest adjacent cell) so the anchor lands on the same integer
-- grid the raft tiles use; preview renders green when the chosen
-- cell is legal and red otherwise.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()
local camera = workspace.CurrentCamera

local placeBlockEvent = ReplicatedStorage:WaitForChild("PlaceBlock")
local raftPartTemplate = ReplicatedStorage:WaitForChild("Raft_part")
local anchorTemplate   = ReplicatedStorage:FindFirstChild("Anchor_part")
	or ReplicatedStorage:FindFirstChild("Anchor_part", true)

local TOOL_NAME        = "Anchor_part"
local PREVIEW_VALID    = Color3.fromRGB(80, 200, 80)
local PREVIEW_INVALID  = Color3.fromRGB(200, 80, 80)
local MAX_PLACE_RANGE  = 80   -- studs from player to candidate cell
local MAX_MOUSE_RAY    = 600

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

local previewPart
local placing       = false
local renderConn
local lastGX, lastGZ
local lastValid     = false

local function getRaft()
	return workspace:FindFirstChild("Raft")
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

-- Same grid scan BuildingSystem.client.lua uses: attribute-tagged
-- tiles plus any initial Raft_part reprojected onto the rest-yaw
-- plane so wave tilt doesn't shift the grid.
local function getFloorOffsetMap()
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return {} end

	local seen = {}
	local primary = raft.PrimaryPart
	local restYaw = primary:GetAttribute("RestYaw")
	if not restYaw then
		local _, yaw, _ = primary.CFrame:ToEulerAnglesYXZ()
		restYaw = yaw
	end
	local flatCF = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0)

	local function add(gx, gz)
		seen[gx .. "_" .. gz] = {x = gx, z = gz}
	end

	for _, child in raft:GetChildren() do
		local gx = child:GetAttribute("GridX")
		local gz = child:GetAttribute("GridZ")
		if gx and gz and child:GetAttribute("BuildType") == "raft" then
			add(gx, gz)
		elseif child.Name == "Raft_part" or child == primary then
			local pos
			if child:IsA("Model") then
				pos = child:GetPivot().Position
			elseif child:IsA("BasePart") then
				pos = child.Position
			end
			if pos then
				local localPos = flatCF:PointToObjectSpace(pos)
				add(math.round(localPos.X / GRID_SIZE), math.round(localPos.Z / GRID_SIZE))
			end
		end
	end
	if not seen["0_0"] then add(0, 0) end
	return seen
end

local function isOccupied(map, gx, gz)
	return map[gx .. "_" .. gz] ~= nil
end

local function isAdjacent(map, gx, gz)
	for _, cell in pairs(map) do
		if (math.abs(cell.x - gx) == 1 and cell.z == gz)
			or (math.abs(cell.z - gz) == 1 and cell.x == gx) then
			return true
		end
	end
	return false
end

-- Anchor_part's PrimaryPart sits 2 studs to the right of the model's
-- visible centre (the A-frame opening pushes it off), so PivotTo
-- parks the body 2 studs right of the grid cell. Shift the target
-- CFrame 2 studs to the left along its own X axis so the visible
-- anchor ends up on the cell instead.
local ANCHOR_PIVOT_COMPENSATION = CFrame.new(-2, 0, 0)

local function gridToWorldCF(raft, gx, gz)
	local primary = raft.PrimaryPart
	local restCF  = primary:GetAttribute("RestCFrame") or primary.CFrame
	local restYaw = primary:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
	local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(gx * GRID_SIZE, 0, gz * GRID_SIZE))
	local localOffset = restCF:VectorToObjectSpace(worldOffset)
	return primary.CFrame * CFrame.new(localOffset) * getTileRotationCorrection(raft) * ANCHOR_PIVOT_COMPENSATION
end

-- Cursor → grid coord. Project mouse ray onto the raft plane, then
-- convert to integer grid. Returns nil outside a valid range.
local function getFloorGridFromMouse()
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return nil end
	local primary = raft.PrimaryPart

	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local origin, direction = unitRay.Origin, unitRay.Direction
	if math.abs(direction.Y) < 1e-4 then return nil end
	local t = (primary.Position.Y - origin.Y) / direction.Y
	if t <= 0 or t > MAX_MOUSE_RAY then return nil end
	local hit = origin + direction * t

	local restYaw = primary:GetAttribute("RestYaw")
	if not restYaw then
		local _, yaw, _ = primary.CFrame:ToEulerAnglesYXZ()
		restYaw = yaw
	end
	local restFlat = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0)
	local localHit = restFlat:PointToObjectSpace(hit)
	local gx = math.round(localHit.X / GRID_SIZE)
	local gz = math.round(localHit.Z / GRID_SIZE)
	return gx, gz
end

local function colourPreview(valid)
	lastValid = valid
	if not previewPart then return end
	local c = valid and PREVIEW_VALID or PREVIEW_INVALID
	if previewPart:IsA("Model") then
		for _, d in previewPart:GetDescendants() do
			if d:IsA("BasePart") then d.Color = c end
		end
	elseif previewPart:IsA("BasePart") then
		previewPart.Color = c
	end
end

local function applyPreviewAppearance()
	if not previewPart then return end
	local function prep(p)
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.Transparency = 0.5
	end
	if previewPart:IsA("Model") then
		for _, d in previewPart:GetDescendants() do
			if d:IsA("BasePart") then prep(d) end
		end
	elseif previewPart:IsA("BasePart") then
		prep(previewPart)
	end
end

local function createPreview()
	if previewPart then previewPart:Destroy() end
	if not anchorTemplate then
		warn("[AnchorBuildSystem] Anchor_part missing in ReplicatedStorage")
		return
	end
	previewPart = anchorTemplate:Clone()
	previewPart.Name = "AnchorPreview"
	-- Strip any baked scripts so they can't run on the ghost.
	for _, d in previewPart:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
	end
	applyPreviewAppearance()
	-- Park offscreen until the first RenderStepped tick places it on
	-- a legal cell.
	if previewPart:IsA("Model") then
		previewPart:PivotTo(CFrame.new(0, -10000, 0))
	elseif previewPart:IsA("BasePart") then
		previewPart.CFrame = CFrame.new(0, -10000, 0)
	end
	previewPart.Parent = workspace
end

local function destroyPreview()
	if previewPart then previewPart:Destroy(); previewPart = nil end
	lastValid = false
	lastGX, lastGZ = nil, nil
end

local function movePreviewToCell(raft, gx, gz)
	local worldCF = gridToWorldCF(raft, gx, gz)
	if previewPart:IsA("Model") then
		previewPart:PivotTo(worldCF)
	elseif previewPart:IsA("BasePart") then
		previewPart.CFrame = worldCF
	end
end

local function updatePreview()
	if not previewPart then return end
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then
		lastValid, lastGX, lastGZ = false, nil, nil
		return
	end

	local gx, gz = getFloorGridFromMouse()
	if not gx then
		-- Fall back to the legal cell closest to the player so the
		-- ghost doesn't teleport to weird spots when the cursor is
		-- over sky / open ocean.
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			lastValid, lastGX, lastGZ = false, nil, nil
			return
		end
		local primary = raft.PrimaryPart
		local restYaw = primary:GetAttribute("RestYaw")
		if not restYaw then
			local _, yaw, _ = primary.CFrame:ToEulerAnglesYXZ()
			restYaw = yaw
		end
		local restFlat = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0)
		local localHrp = restFlat:PointToObjectSpace(hrp.Position)
		gx = math.round(localHrp.X / GRID_SIZE)
		gz = math.round(localHrp.Z / GRID_SIZE)
	end

	local map = getFloorOffsetMap()
	local valid = not isOccupied(map, gx, gz) and isAdjacent(map, gx, gz)
	movePreviewToCell(raft, gx, gz)
	lastGX, lastGZ = gx, gz

	if not valid then
		colourPreview(false)
		return
	end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local worldCF = gridToWorldCF(raft, gx, gz)
		if (hrp.Position - worldCF.Position).Magnitude > MAX_PLACE_RANGE then
			colourPreview(false)
			return
		end
	end

	colourPreview(true)
end

local function startBuildMode()
	if placing then return end
	placing = true
	createPreview()
	renderConn = RunService.RenderStepped:Connect(updatePreview)
end

local function closeBuildMode()
	placing = false
	if renderConn then renderConn:Disconnect(); renderConn = nil end
	destroyPreview()
end

local function onToolEquipped(tool)
	if tool.Name ~= TOOL_NAME then return end
	startBuildMode()
end

local function onToolUnequipped(tool)
	if tool and tool.Name ~= TOOL_NAME then return end
	closeBuildMode()
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
	char.AncestryChanged:Connect(function(_, parent)
		if not parent then closeBuildMode() end
	end)
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

local function playPlaceSound()
	local folder = SoundService:FindFirstChild("Building")
	local snd = folder and folder:FindFirstChild("Place_Block")
	if snd then snd:Play() end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if not placing then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if not lastValid or not lastGX or not lastGZ then return end

	placeBlockEvent:FireServer("anchor", lastGX, lastGZ)
	playPlaceSound()
	closeBuildMode()
end)
