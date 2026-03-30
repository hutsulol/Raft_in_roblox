local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

-- ─── State ───
local ghost = nil
local currentTool = nil
local placingPurifier = false
local lastGhostValid = false

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
	local cupState = currentTool:GetAttribute("CupState")
	if cupState == "empty" then
		hintLabel.Text = "[Q] Fill with saltwater (aim at water)"
		hintLabel.Visible = true
	elseif cupState == "salty" then
		hintLabel.Text = "Click purifier to pour | [Q] Dump into ocean"
		hintLabel.Visible = true
	elseif cupState == "fresh" then
		hintLabel.Text = "Click to drink fresh water"
		hintLabel.Visible = true
	else
		hintLabel.Visible = false
	end
end

-- ─── Ghost Preview for Purifier Placement ───
local function createGhost()
	if ghost then ghost:Destroy() end
	local template = ReplicatedStorage:FindFirstChild("Destitalor")
	if not template then return end

	ghost = template:Clone()
	ghost.Name = "PurifierGhost"
	for _, part in ghost:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = 0.5
			part.CanCollide = false
			part.Anchored = true
			part.Color = Color3.fromRGB(80, 255, 80)
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

local function updateGhost()
	if not ghost then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then
		setGhostColor(false)
		return
	end

	-- Raycast from mouse, only hit raft parts
	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {ghost, player.Character}

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)

	if result and result.Instance then
		-- Check if we hit a raft part (must be descendant of the Raft model)
		local hitOnRaft = result.Instance:IsDescendantOf(raft)

		if hitOnRaft then
			local hitPos = result.Position
			local hitNormal = result.Normal

			-- Place on top of the surface we hit
			local ghostSize = ghost:GetExtentsSize()
			local _, raftYaw, _ = raft.PrimaryPart.CFrame:ToEulerAnglesYXZ()

			-- Use the hit position + half ghost height above the surface
			local placeCF = CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z) * CFrame.Angles(0, raftYaw, 0)
			ghost:PivotTo(placeCF)
			setGhostColor(true)
		else
			-- Cursor is not on the raft — show red ghost at cursor position
			local hitPos = result.Position
			local ghostSize = ghost:GetExtentsSize()
			local _, raftYaw, _ = raft.PrimaryPart.CFrame:ToEulerAnglesYXZ()
			ghost:PivotTo(CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z) * CFrame.Angles(0, raftYaw, 0))
			setGhostColor(false)
		end
	else
		setGhostColor(false)
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

	if tool.Name == "Destitalor" then
		placingPurifier = true
		createGhost()
	else
		placingPurifier = false
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
	if placingPurifier and ghost then
		updateGhost()
	end
end)

-- ─── Mouse Click Handler (for purifier placement and cup→purifier interactions) ───
mouse.Button1Down:Connect(function()
	if not currentTool then return end

	-- Purifier placement
	if placingPurifier and ghost then
		if not lastGhostValid then return end -- can only place on raft

		local placeCF = ghost:GetPivot()
		cupActionEvent:FireServer("placePurifier", placeCF)
		destroyGhost()
		placingPurifier = false
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

-- ─── Q Key Handler (scoop saltwater from ocean, cursor must be over water) ───
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode ~= Enum.KeyCode.Q then return end
	if not currentTool then return end

	local cupState = currentTool:GetAttribute("CupState")

	if cupState == "empty" then
		if not isCursorOverWater() then return end
		cupActionEvent:FireServer("scoopSaltwater")
	elseif cupState == "salty" then
		cupActionEvent:FireServer("dumpWater")
	end
end)
