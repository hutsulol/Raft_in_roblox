local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

-- ─── State ───
local ghost = nil         -- ghost preview model for purifier placement
local currentTool = nil   -- currently equipped tool
local placingPurifier = false

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
end

local function updateGhost()
	if not ghost then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then
		for _, part in ghost:GetDescendants() do
			if part:IsA("BasePart") then
				part.Color = Color3.fromRGB(255, 80, 80)
			end
		end
		return
	end

	-- Raycast from mouse
	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {ghost, player.Character}

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)

	if result then
		local hitPos = result.Position
		-- Snap to raft surface level
		local raftY = raft.PrimaryPart.Position.Y
		local _, raftYaw, _ = raft.PrimaryPart.CFrame:ToEulerAnglesYXZ()

		-- Get ghost size for Y offset
		local ghostSize = ghost:GetExtentsSize()
		local placeCF = CFrame.new(hitPos.X, raftY + ghostSize.Y / 2, hitPos.Z) * CFrame.Angles(0, raftYaw, 0)
		ghost:PivotTo(placeCF)

		-- Check if close enough to raft
		local dist = (hitPos - raft.PrimaryPart.Position).Magnitude
		local valid = dist < 30
		local color = valid and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
		for _, part in ghost:GetDescendants() do
			if part:IsA("BasePart") then
				part.Color = color
			end
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
	return nil
end

-- ─── Check if clicking on water (not on raft or other solid object) ───
local function isClickOnWater(hitInstance)
	if not hitInstance then return true end
	if hitInstance:IsA("Terrain") then return true end

	-- Check if it's part of the raft
	local raft = workspace:FindFirstChild("Raft")
	if raft and hitInstance:IsDescendantOf(raft) then return false end

	-- Check if it's a purifier
	if findPurifier(hitInstance) then return false end

	-- Check if it's a player character
	local char = player.Character
	if char and hitInstance:IsDescendantOf(char) then return false end

	-- If it's part of a pirate or other model, not water
	local model = hitInstance:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildWhichIsA("Humanoid") then return false end

	return true
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
end

local function onToolUnequipped()
	currentTool = nil
	placingPurifier = false
	destroyGhost()
end

-- Watch character's children for tool equip/unequip
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

	-- Check if already has a tool equipped
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

-- ─── Mouse Click Handler ───
mouse.Button1Down:Connect(function()
	if not currentTool then return end

	-- Purifier placement
	if placingPurifier and ghost then
		local raft = workspace:FindFirstChild("Raft")
		if not raft or not raft.PrimaryPart then return end

		local placeCF = ghost:GetPivot()
		local dist = (placeCF.Position - raft.PrimaryPart.Position).Magnitude
		if dist > 30 then return end

		cupActionEvent:FireServer("placePurifier", placeCF)
		destroyGhost()
		placingPurifier = false
		return
	end

	-- Cup interactions
	local cupState = currentTool:GetAttribute("CupState")
	if cupState == nil then return end -- not a cup

	local target = mouse.Target
	local purifier = target and findPurifier(target)

	if cupState == "empty" then
		if purifier then
			-- Collect fresh water from purifier
			local waterType = purifier:GetAttribute("WaterType")
			local waterLevel = purifier:GetAttribute("WaterLevel") or 0
			if waterType == "fresh" and waterLevel > 0 then
				cupActionEvent:FireServer("collectWater", target)
			end
		elseif isClickOnWater(target) then
			-- Scoop saltwater
			cupActionEvent:FireServer("scoopSaltwater")
		end
	elseif cupState == "salty" then
		if purifier then
			-- Pour saltwater into purifier
			cupActionEvent:FireServer("fillPurifier", target)
		end
	elseif cupState == "fresh" then
		-- Drink fresh water
		cupActionEvent:FireServer("drink")
	end
end)
