local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")
local bushActionEvent = ReplicatedStorage:WaitForChild("BushAction")
local gardenActionEvent = ReplicatedStorage:WaitForChild("GardenAction")

-- ─── State ───
local ghost = nil
local currentTool = nil
local placingPurifier = false
local placingBush = false
local placingWorkbench = false
local placingGarden = false
local placingBed = false
local lastGhostValid = false
local lastGhostCF = nil
local lastGhostRaftOffset = nil -- CFrame offset relative to raft
local ghostTemplateRotation = CFrame.new() -- template model rotation (identity for most)
local lastTargetGarden = nil -- garden bed reference for bush placement
local rotationAngle = 0 -- radians, incremented by R key

-- ─── Hint UI ───
local playerGui = player:WaitForChild("PlayerGui")
local hintGui = Instance.new("ScreenGui")
hintGui.Name = "CupHint"
hintGui.DisplayOrder = 50
hintGui.IgnoreGuiInset = true
hintGui.Parent = playerGui

local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "HintText"
hintLabel.AnchorPoint = Vector2.new(0.5, 1)
hintLabel.Position = UDim2.new(0.5, 0, 0.85, 0)
hintLabel.Size = UDim2.new(0, 300, 0, 40)
hintLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
hintLabel.BackgroundTransparency = 0.4
hintLabel.Text = ""
hintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
hintLabel.TextSize = 18
hintLabel.Font = Enum.Font.GothamBold
hintLabel.Visible = false
hintLabel.Parent = hintGui

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 8)
hintCorner.Parent = hintLabel

local function updateHint()
	if not currentTool then
		hintLabel.Visible = false
		return
	end

	-- Bush placement hint
	if placingBush then
		hintLabel.Text = "Click on garden bed to plant bush | [R] Rotate"
		hintLabel.Visible = true
		return
	end

	-- Garden placement hint
	if placingGarden then
		hintLabel.Text = "Click on raft to place garden bed | [R] Rotate"
		hintLabel.Visible = true
		return
	end

	-- Placement hints
	if placingPurifier then
		hintLabel.Text = "Click on raft to place purifier | [R] Rotate"
		hintLabel.Visible = true
		return
	end

	if placingWorkbench then
		hintLabel.Text = "Click on raft to place workbench | [R] Rotate"
		hintLabel.Visible = true
		return
	end

	if placingBed then
		hintLabel.Text = "Click on raft to place bed | [R] Rotate"
		hintLabel.Visible = true
		return
	end

	-- Grape tool hint
	if currentTool.Name == "[GRAPES]" or currentTool.Name == "Grapes" then
		hintLabel.Text = "Click to eat grapes"
		hintLabel.Visible = true
		return
	end

	local cupState = currentTool:GetAttribute("CupState")
	if cupState == "empty" then
		hintLabel.Text = "[Q] Fill with saltwater (aim at water)"
		hintLabel.Visible = true
	elseif cupState == "salty" then
		hintLabel.Text = "Click purifier to pour | [Q] Dump into ocean"
		hintLabel.Visible = true
	elseif cupState == "fresh" then
		hintLabel.Text = "Click to drink | [E] Water garden bed"
		hintLabel.Visible = true
	else
		hintLabel.Visible = false
	end
end

-- ─── Ghost Preview for Placement ───
local function createGhost(templateName)
	if ghost then ghost:Destroy() end
	local template = ReplicatedStorage:FindFirstChild(templateName or "Destitalor")
	if not template then return end

	ghost = template:Clone()
	ghost.Name = "PlacementGhost"

	-- Reset WorldPivot to bounding box center with identity rotation
	local bbCF, bbSize = ghost:GetBoundingBox()
	ghost.WorldPivot = CFrame.new(bbCF.Position)

	-- Store the template's original rotation so we can apply it during placement
	-- (bush template needs this to stay upright; others have identity rotation)
	if templateName == "bush" then
		ghostTemplateRotation = bbCF.Rotation
	else
		ghostTemplateRotation = CFrame.new()
	end

	for _, part in ghost:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = 0.5
			part.CanCollide = false
			part.Anchored = true
			part.Color = Color3.fromRGB(80, 255, 80)
		end
		-- Remove scripts from ghost
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
	lastGhostCF = nil
	lastGhostRaftOffset = nil
	lastTargetGarden = nil
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

-- ─── Find garden bed from hit instance ───
local function findGardenBed(instance)
	local current = instance
	while current and current ~= workspace do
		if current:GetAttribute("IsGarden") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- ─── Check if garden already has a bush ───
local function gardenHasBush(garden)
	for _, child in garden:GetChildren() do
		if child:GetAttribute("IsBush") then
			return true
		end
	end
	return false
end

-- ─── Check if placement spot is blocked by existing objects ───
local function isPlacementBlocked(placeCF, ghostSize)
	local raft = workspace:FindFirstChild("Raft")
	if not raft then return true end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {ghost, player.Character}

	-- Shrink the check box to avoid false positives at edges
	local checkSize = ghostSize * 0.7

	local parts = workspace:GetPartBoundsInBox(placeCF, checkSize, overlapParams)

	-- Known placed object names to check against
	local placedObjectNames = {
		WorkBench = true, Purifier = true, Garden = true,
		Bed = true, Destitalor = true, bush = true,
	}

	for _, part in parts do
		if part:IsDescendantOf(raft) then
			-- Walk up to find parent model
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

-- ─── Update ghost position each frame ───
local function updateGhost()
	if not ghost then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then
		setGhostColor(false)
		return
	end

	-- Raycast from mouse
	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {ghost, player.Character}

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)

	if not result or not result.Instance then
		setGhostColor(false)
		return
	end

	if placingBush then
		-- Bush: only valid on garden beds
		local garden = findGardenBed(result.Instance)
		if garden and not gardenHasBush(garden) then
			-- Snap to top center of garden bed
			local gardenCF, gardenSize = garden:GetBoundingBox()
			local ghostSize = ghost:GetExtentsSize()
			local topY = gardenCF.Position.Y + gardenSize.Y / 2
			local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0

			local placeCF = CFrame.new(gardenCF.Position.X, topY, gardenCF.Position.Z) * CFrame.Angles(0, restYaw + rotationAngle, 0) * ghostTemplateRotation
			ghost:PivotTo(placeCF)
			lastGhostCF = placeCF
			lastGhostRaftOffset = raft.PrimaryPart.CFrame:ToObjectSpace(placeCF)
			lastTargetGarden = garden
			setGhostColor(true)
		else
			-- Not on a valid garden bed — show red ghost at cursor
			lastTargetGarden = nil
			local hitPos = result.Position
			local ghostSize = ghost:GetExtentsSize()
			local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
			ghost:PivotTo(CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z) * CFrame.Angles(0, restYaw + rotationAngle, 0) * ghostTemplateRotation)
			setGhostColor(false)
		end
	else
		-- Other placeables: place on raft surface
		local hitOnRaft = result.Instance:IsDescendantOf(raft)

		if hitOnRaft then
			local hitPos = result.Position
			local ghostSize = ghost:GetExtentsSize()
			local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0

			local placeCF = CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z) * CFrame.Angles(0, restYaw + rotationAngle, 0) * ghostTemplateRotation
			ghost:PivotTo(placeCF)
			lastGhostCF = placeCF
			lastGhostRaftOffset = raft.PrimaryPart.CFrame:ToObjectSpace(placeCF)

			-- Check for overlap with existing objects
			if isPlacementBlocked(placeCF, ghostSize) then
				setGhostColor(false)
			else
				setGhostColor(true)
			end
		else
			-- Cursor is not on the raft — show red ghost at cursor position
			local hitPos = result.Position
			local ghostSize = ghost:GetExtentsSize()
			local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
			ghost:PivotTo(CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z) * CFrame.Angles(0, restYaw + rotationAngle, 0))
			setGhostColor(false)
		end
	end
end

-- ─── Detect which purifier model was clicked ───
local function findPurifier(instance)
	local current = instance
	while current and current ~= workspace do
		if current.Name == "Purifier" and current:GetAttribute("WaterType") ~= nil then
			return current
		end
		current = current.Parent
	end
	-- Also check inside Raft
	local raft = workspace:FindFirstChild("Raft")
	if raft then
		local current2 = instance
		while current2 and current2 ~= raft do
			if current2.Name == "Purifier" and current2:GetAttribute("WaterType") ~= nil then
				return current2
			end
			current2 = current2.Parent
		end
	end
	return nil
end

-- ─── Tool Equip/Unequip Detection ───
local function onToolEquipped(tool)
	currentTool = tool
	rotationAngle = 0

	if tool.Name == "Destitalor" then
		placingPurifier = true
		placingBush = false
		placingWorkbench = false
		placingGarden = false
		placingBed = false
		createGhost("Destitalor")
	elseif tool.Name == "bush" or tool.Name == "Bush" then
		placingBush = true
		placingPurifier = false
		placingWorkbench = false
		placingGarden = false
		placingBed = false
		createGhost("bush")
	elseif tool.Name == "WorkBench" then
		placingWorkbench = true
		placingPurifier = false
		placingBush = false
		placingGarden = false
		placingBed = false
		createGhost("WorkBench")
	elseif tool.Name == "Garden" then
		placingGarden = true
		placingPurifier = false
		placingBush = false
		placingWorkbench = false
		placingBed = false
		createGhost("Garden")
	elseif tool.Name == "Bed" then
		placingBed = true
		placingPurifier = false
		placingBush = false
		placingWorkbench = false
		placingGarden = false
		createGhost("Bed")
	else
		placingPurifier = false
		placingBush = false
		placingWorkbench = false
		placingGarden = false
		placingBed = false
		destroyGhost()
	end

	updateHint()
	-- Listen for CupState changes to update hint
	tool:GetAttributeChangedSignal("CupState"):Connect(function()
		if currentTool == tool then
			updateHint()
		end
	end)
end

local function onToolUnequipped()
	currentTool = nil
	placingPurifier = false
	placingBush = false
	placingWorkbench = false
	placingGarden = false
	placingBed = false
	destroyGhost()
	updateHint()
end

local function setupCharacter(char)
	if not char then return end

	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			onToolEquipped(child)
		end
	end)

	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child == currentTool then
			onToolUnequipped()
		end
	end)

	for _, child in char:GetChildren() do
		if child:IsA("Tool") then
			onToolEquipped(child)
			break
		end
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

-- ─── Update ghost every frame ───
RunService.RenderStepped:Connect(function()
	if (placingPurifier or placingBush or placingWorkbench or placingGarden or placingBed) and ghost then
		updateGhost()
	end
end)

-- ─── R key to rotate placement ───
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.R and (placingPurifier or placingWorkbench or placingGarden or placingBed or placingBush) then
		rotationAngle = rotationAngle + math.rad(90)
	end
end)

-- ─── Mouse Click Handler ───
mouse.Button1Down:Connect(function()
	if not currentTool then return end

	-- Purifier placement
	if placingPurifier and ghost then
		if not lastGhostValid or not lastGhostRaftOffset then return end
		cupActionEvent:FireServer("placePurifier", lastGhostRaftOffset)
		destroyGhost()
		placingPurifier = false
		return
	end

	-- Bush placement (on garden bed)
	if placingBush and ghost then
		if not lastGhostValid or not lastTargetGarden then return end
		bushActionEvent:FireServer("placeBush", lastTargetGarden)
		destroyGhost()
		placingBush = false
		return
	end

	-- Workbench placement
	if placingWorkbench and ghost then
		if not lastGhostValid or not lastGhostRaftOffset then return end
		cupActionEvent:FireServer("placeWorkbench", lastGhostRaftOffset)
		destroyGhost()
		placingWorkbench = false
		return
	end

	-- Garden placement
	if placingGarden and ghost then
		if not lastGhostValid or not lastGhostRaftOffset then return end
		gardenActionEvent:FireServer("placeGarden", lastGhostRaftOffset)
		destroyGhost()
		placingGarden = false
		return
	end

	-- Bed placement
	if placingBed and ghost then
		if not lastGhostValid or not lastGhostRaftOffset then return end
		cupActionEvent:FireServer("placeBed", lastGhostRaftOffset)
		destroyGhost()
		placingBed = false
		return
	end

	-- Grape eating
	if currentTool.Name == "[GRAPES]" or currentTool.Name == "Grapes" then
		bushActionEvent:FireServer("eatGrape")
		return
	end

	-- Cup click interactions (purifier fill/collect)
	local cupState = currentTool:GetAttribute("CupState")
	if cupState == nil then return end

	local target = mouse.Target
	local purifier = target and findPurifier(target)

	if cupState == "empty" then
		if purifier then
			local waterType = purifier:GetAttribute("WaterType")
			local waterLevel = purifier:GetAttribute("WaterLevel") or 0
			if waterType == "fresh" and waterLevel > 0 then
				cupActionEvent:FireServer("collectWater", target)
			end
		end
	elseif cupState == "salty" then
		if purifier then
			cupActionEvent:FireServer("fillPurifier", target)
		end
	elseif cupState == "fresh" then
		cupActionEvent:FireServer("drink")
	end
end)

-- ─── Check if cursor is hovering over water ───
local function isCursorOverWater()
	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}
	if player.Character then table.insert(filterList, player.Character) end
	if ghost then table.insert(filterList, ghost) end
	params.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)

	if not result then return false end -- nothing hit (sky) = not water
	if result.Instance:IsA("Terrain") then return true end

	-- Check if we hit something that's NOT the raft or a purifier
	local raft = workspace:FindFirstChild("Raft")
	if raft and result.Instance:IsDescendantOf(raft) then return false end
	if findPurifier(result.Instance) then return false end

	-- Hit a floating resource or other object — not water
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildWhichIsA("Humanoid") then return false end

	return true
end

-- ─── Find garden bed from raycast at cursor ───
local function findGardenAtCursor()
	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}
	if player.Character then table.insert(filterList, player.Character) end
	if ghost then table.insert(filterList, ghost) end
	params.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)
	if not result or not result.Instance then return nil end
	return findGardenBed(result.Instance)
end

-- ─── Q Key Handler (scoop saltwater from ocean, cursor must be over water) ───
-- ─── E Key Handler (water garden bed with fresh water cup) ───
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not currentTool then return end

	if input.KeyCode == Enum.KeyCode.Q then
		local cupState = currentTool:GetAttribute("CupState")
		if cupState == "empty" then
			if not isCursorOverWater() then return end
			cupActionEvent:FireServer("scoopSaltwater")
		elseif cupState == "salty" then
			cupActionEvent:FireServer("dumpWater")
		end

	elseif input.KeyCode == Enum.KeyCode.E then
		local cupState = currentTool:GetAttribute("CupState")
		if cupState ~= "fresh" then return end

		local garden = findGardenAtCursor()
		if not garden then return end
		if garden:GetAttribute("IsWatered") == true then return end

		gardenActionEvent:FireServer("waterGarden", garden)
	end
end)
