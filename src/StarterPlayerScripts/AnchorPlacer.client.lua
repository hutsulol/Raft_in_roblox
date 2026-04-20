-- AnchorPlacer.client.lua
-- Click-to-place flow for the Anchor_part tool. Crafted at the
-- workbench (1 Log) and consumed on placement.
--
-- The ghost only ever shows on a *legal* placement cell — that is,
-- a free grid cell directly adjacent to an existing raft tile. We
-- enumerate the legal cells each frame and pick the one nearest to
-- where the cursor is hitting, so the preview never teleports to
-- wherever the mouse points (e.g. open water, sky, the player).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()
local camera = workspace.CurrentCamera

local placeBlockEvent  = ReplicatedStorage:WaitForChild("PlaceBlock")
local raftPartTemplate = ReplicatedStorage:WaitForChild("Raft_part")

local TOOL_NAME       = "Anchor_part"
local TEMPLATE_NAME   = "Anchor_part"
local PREVIEW_VALID   = Color3.fromRGB(80, 200, 80)
local PREVIEW_INVALID = Color3.fromRGB(200, 80, 80)
local MAX_PLACE_RANGE = 80   -- studs from the player to the candidate cell

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

local ghost   = nil
local placing = false
local lastGX, lastGZ
local lastValid = false

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

-- Walk the raft's children and collect the grid coordinates of every
-- existing floor tile (initial + player-built). Same scan as
-- BuildingSystem.client.lua / .server.lua so the placement rules line
-- up exactly.
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

-- Build the set of cells that are adjacent to (but not occupied by) a
-- raft tile — i.e. every legal anchor placement.
local function listLegalCells(occupied)
	local out = {}
	for _, cell in pairs(occupied) do
		local neighbours = {
			{x = cell.x + 1, z = cell.z},
			{x = cell.x - 1, z = cell.z},
			{x = cell.x,     z = cell.z + 1},
			{x = cell.x,     z = cell.z - 1},
		}
		for _, n in neighbours do
			local key = n.x .. "_" .. n.z
			if not occupied[key] and not out[key] then
				out[key] = n
			end
		end
	end
	return out
end

-- Convert grid coords to world CFrame using the same rest-yaw maths
-- the server uses, so the preview lines up exactly with the placement.
local function gridToWorldCF(raft, gx, gz)
	local primary = raft.PrimaryPart
	local restCF = primary:GetAttribute("RestCFrame") or primary.CFrame
	local restYaw = primary:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
	local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(gx * GRID_SIZE, 0, gz * GRID_SIZE))
	local localOffset = restCF:VectorToObjectSpace(worldOffset)
	return primary.CFrame * CFrame.new(localOffset) * getTileRotationCorrection(raft)
end

local function colourGhost(valid)
	lastValid = valid
	if not ghost then return end
	local c = valid and PREVIEW_VALID or PREVIEW_INVALID
	for _, p in ghost:GetDescendants() do
		if p:IsA("BasePart") then p.Color = c end
	end
end

local function setGhostVisible(visible)
	if not ghost then return end
	for _, p in ghost:GetDescendants() do
		if p:IsA("BasePart") then
			p.LocalTransparencyModifier = visible and 0 or 1
			p.Transparency = visible and 0.5 or 1
		end
	end
end

local function createGhost()
	if ghost then ghost:Destroy() end
	local template = findTemplate()
	if not template then
		warn("[AnchorPlacer] template Anchor_part not found in ReplicatedStorage")
		return
	end
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
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.Transparency = 0.5
		elseif p:IsA("Script") or p:IsA("LocalScript") then
			p:Destroy()
		end
	end
	if ghost:IsA("BasePart") then
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.CanQuery = false
		ghost.CanTouch = false
		ghost.Massless = true
		ghost.Transparency = 0.5
	end
	-- Park well below the world so it doesn't flash at origin before
	-- updateGhost moves it to a legal cell on the next frame.
	if ghost:IsA("Model") then
		ghost:PivotTo(CFrame.new(0, -10000, 0))
	else
		ghost.CFrame = CFrame.new(0, -10000, 0)
	end
	ghost.Parent = workspace
	colourGhost(true)
end

local function destroyGhost()
	if ghost then ghost:Destroy(); ghost = nil end
	lastValid = false
	lastGX, lastGZ = nil, nil
end

-- Return the legal cell whose world position is closest to the
-- cursor's projection on the raft plane. Hides the ghost if there
-- aren't any (raft is gone, every neighbour somehow occupied) or the
-- nearest cell is too far from the player to reach.
local function pickCellUnderCursor(raft, occupied)
	local primary = raft.PrimaryPart
	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local origin, direction = unitRay.Origin, unitRay.Direction
	local cursorPlanePos
	if math.abs(direction.Y) < 1e-4 then
		-- Looking horizontally — fall back to the player's position.
		cursorPlanePos = primary.Position
	else
		local t = (primary.Position.Y - origin.Y) / direction.Y
		if t < 0 or t > 600 then
			cursorPlanePos = primary.Position
		else
			cursorPlanePos = origin + direction * t
		end
	end

	local legal = listLegalCells(occupied)
	local best, bestCF, bestDist = nil, nil, math.huge
	for _, cell in pairs(legal) do
		local cf = gridToWorldCF(raft, cell.x, cell.z)
		local d = (cf.Position - cursorPlanePos).Magnitude
		if d < bestDist then
			bestDist = d
			best = cell
			bestCF = cf
		end
	end
	return best, bestCF
end

local function updateGhost()
	if not ghost then return end
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then
		setGhostVisible(false)
		lastValid, lastGX, lastGZ = false, nil, nil
		return
	end

	local occupied = getFloorOffsetMap()
	local cell, worldCF = pickCellUnderCursor(raft, occupied)
	if not cell or not worldCF then
		setGhostVisible(false)
		lastValid, lastGX, lastGZ = false, nil, nil
		return
	end

	-- Out-of-reach cells get the red preview but stay invisible —
	-- the player will pan toward the raft to see it.
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local inRange = hrp and (hrp.Position - worldCF.Position).Magnitude <= MAX_PLACE_RANGE

	setGhostVisible(true)
	if ghost:IsA("Model") then
		ghost:PivotTo(worldCF)
	elseif ghost:IsA("BasePart") then
		ghost.CFrame = worldCF
	end
	lastGX, lastGZ = cell.x, cell.z
	colourGhost(inRange)
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
