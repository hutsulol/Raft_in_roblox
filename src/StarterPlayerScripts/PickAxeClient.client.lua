-- PickAxeClient.client.lua
-- Client-side Pick-Axe tool: highlights rocks, handles click-to-mine

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local mineRockEvent = ReplicatedStorage:WaitForChild("MineRock")

-- ─── State ───
local pickAxeEquipped = false
local currentTool = nil
local highlightedRock = nil
local highlightBox = nil
local miningCooldown = false

-- ─── Hint UI ───
local playerGui = player:WaitForChild("PlayerGui")
local hintGui = Instance.new("ScreenGui")
hintGui.Name = "PickAxeHint"
hintGui.DisplayOrder = 51
hintGui.IgnoreGuiInset = true
hintGui.Parent = playerGui

local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "HintText"
hintLabel.AnchorPoint = Vector2.new(0.5, 1)
hintLabel.Position = UDim2.new(0.5, 0, 0.8, 0)
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

-- ─── Mining feedback notification ───
local feedbackLabel = Instance.new("TextLabel")
feedbackLabel.Name = "MineFeedback"
feedbackLabel.AnchorPoint = Vector2.new(0.5, 0.5)
feedbackLabel.Position = UDim2.new(0.5, 0, 0.45, 0)
feedbackLabel.Size = UDim2.new(0, 250, 0, 36)
feedbackLabel.BackgroundTransparency = 1
feedbackLabel.Text = ""
feedbackLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
feedbackLabel.TextSize = 22
feedbackLabel.Font = Enum.Font.GothamBold
feedbackLabel.TextStrokeTransparency = 0.5
feedbackLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
feedbackLabel.Visible = false
feedbackLabel.Parent = hintGui

-- ─── Highlight box for rocks (yellow outline only) ───
local function createHighlight()
	if highlightBox then highlightBox:Destroy() end
	highlightBox = Instance.new("Highlight")
	highlightBox.FillTransparency = 1
	highlightBox.OutlineColor = Color3.fromRGB(255, 200, 50)
	highlightBox.OutlineTransparency = 0
	highlightBox.Parent = playerGui
end

local function clearHighlight()
	if highlightBox then
		highlightBox.Adornee = nil
	end
	highlightedRock = nil
end

-- ─── Find mineable rock from raycast target ───
local function findMineableRock(instance)
	if not instance then return nil end
	-- Check the part itself
	if instance:IsA("BasePart") and instance:GetAttribute("Mineable") then
		-- Skip Iron_Ore (handled by MiningHighlight)
		if instance:GetAttribute("MineableOre") then return nil end
		return instance
	end
	-- Check parent parts (in case mesh or decoration was hit)
	local parent = instance.Parent
	if parent and parent:IsA("BasePart") and parent:GetAttribute("Mineable") then
		if parent:GetAttribute("MineableOre") then return nil end
		return parent
	end
	return nil
end

-- ─── Play mining animation if available ───
local function playMineAnimation()
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then return end

	-- Look for animation in the tool
	if currentTool then
		local anim = currentTool:FindFirstChildWhichIsA("Animation", true)
		if anim then
			local track = humanoid:LoadAnimation(anim)
			track:Play()
			return
		end
	end
end

-- ─── Update highlight each frame ───
local function updateHighlight()
	if not pickAxeEquipped then
		clearHighlight()
		return
	end

	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}
	if player.Character then table.insert(filterList, player.Character) end
	params.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)

	if result and result.Instance then
		local rock = findMineableRock(result.Instance)
		if rock then
			highlightedRock = rock
			if highlightBox then
				highlightBox.Adornee = rock
			end
			hintLabel.Text = "Click to mine rock"
			hintLabel.Visible = true
			return
		end
	end

	clearHighlight()
	hintLabel.Text = "Aim at rocks on islands to mine"
	hintLabel.Visible = true
end

-- ─── Tool equip detection ───
local function onToolEquipped(tool)
	if tool.Name == "Pick-Axe" then
		pickAxeEquipped = true
		currentTool = tool
		createHighlight()
		hintLabel.Visible = true
	end
end

local function onToolUnequipped(tool)
	if tool.Name == "Pick-Axe" then
		pickAxeEquipped = false
		currentTool = nil
		clearHighlight()
		hintLabel.Visible = false
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

	-- Check already equipped
	for _, child in char:GetChildren() do
		if child:IsA("Tool") and child.Name == "Pick-Axe" then
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
	if pickAxeEquipped then
		updateHighlight()
	end
end)

-- ─── Click to mine ───
mouse.Button1Down:Connect(function()
	if not pickAxeEquipped then return end
	if miningCooldown then return end
	if not highlightedRock then return end

	miningCooldown = true
	playMineAnimation()
	mineRockEvent:FireServer(highlightedRock)

	task.delay(0.5, function()
		miningCooldown = false
	end)
end)

-- ─── Server feedback ───
mineRockEvent.OnClientEvent:Connect(function(action, value)
	if action == "destroyed" then
		feedbackLabel.Text = "+" .. value .. " Stone"
		feedbackLabel.Visible = true
		feedbackLabel.TextTransparency = 0
		clearHighlight()

		-- Play Rock_Crush sound
		local rockCrush = SoundService:FindFirstChild("Rock_Crush")
		if rockCrush and rockCrush:IsA("Sound") then
			local clone = rockCrush:Clone()
			clone.Parent = SoundService
			clone:Play()
			Debris:AddItem(clone, 5)
		end

		-- Fade out
		task.spawn(function()
			task.wait(1)
			for i = 0, 10 do
				feedbackLabel.TextTransparency = i / 10
				feedbackLabel.TextStrokeTransparency = 0.5 + (i / 10) * 0.5
				task.wait(0.05)
			end
			feedbackLabel.Visible = false
			feedbackLabel.TextTransparency = 0
			feedbackLabel.TextStrokeTransparency = 0.5
		end)
	elseif action == "hit" then
		feedbackLabel.Text = "Mining... (" .. value .. " hits left)"
		feedbackLabel.Visible = true
		feedbackLabel.TextTransparency = 0

		task.spawn(function()
			task.wait(0.8)
			if feedbackLabel.Text:find("Mining") then
				feedbackLabel.Visible = false
			end
		end)
	end
end)
