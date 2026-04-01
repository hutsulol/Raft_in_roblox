-- MiningHighlight.client.lua
-- Yellow outline highlight for Rock + Iron_Ore, floating popup on break
-- Fires MineRock for rocks (Mineable attr), MineOre for iron ore (MineableOre attr)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local mineRockEvent = ReplicatedStorage:WaitForChild("MineRock")
local mineOreEvent = ReplicatedStorage:WaitForChild("MineOre")

-- ─── Resource Icons ───
local RESOURCE_ICONS = {
	Stone = "rbxassetid://134781813180973",
	Iron_Ore = "rbxassetid://73676755288746",
}

-- ─── Mining feedback UI ───
local feedbackGui = Instance.new("ScreenGui")
feedbackGui.Name = "OreMiningFeedback"
feedbackGui.DisplayOrder = 52
feedbackGui.IgnoreGuiInset = true
feedbackGui.Parent = playerGui

local feedbackLabel = Instance.new("TextLabel")
feedbackLabel.Name = "OreFeedback"
feedbackLabel.AnchorPoint = Vector2.new(0.5, 0.5)
feedbackLabel.Position = UDim2.new(0.5, 0, 0.4, 0)
feedbackLabel.Size = UDim2.new(0, 250, 0, 36)
feedbackLabel.BackgroundTransparency = 1
feedbackLabel.Text = ""
feedbackLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
feedbackLabel.TextSize = 22
feedbackLabel.Font = Enum.Font.GothamBold
feedbackLabel.TextStrokeTransparency = 0.5
feedbackLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
feedbackLabel.Visible = false
feedbackLabel.Parent = feedbackGui

-- ─── State ───
local currentHighlight = nil
local highlightedPart = nil
local highlightedOreType = nil -- "Rock" or "Iron_Ore"
local pickAxeEquipped = false
local lastMinedPosition = nil
local oreMiningCooldown = false

-- ─── Check if Pick-Axe is equipped ───
local function isPickAxeEquipped()
	local char = player.Character
	if not char then return false end
	for _, child in char:GetChildren() do
		if child:IsA("Tool") and child.Name == "Pick-Axe" then
			return true
		end
	end
	return false
end

-- ─── Find mineable part under mouse ───
local function getMineableUnderMouse()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		params.FilterDescendantsInstances = {player.Character}
	end

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	if not result or not result.Instance then return nil, nil end

	local hit = result.Instance

	-- Check hit part
	if hit:IsA("BasePart") then
		if hit:GetAttribute("Mineable") then
			return hit, "Rock"
		elseif hit:GetAttribute("MineableOre") then
			return hit, hit:GetAttribute("OreType") or "Iron_Ore"
		end
	end

	-- Check parent
	local parent = hit.Parent
	if parent and parent:IsA("BasePart") then
		if parent:GetAttribute("Mineable") then
			return parent, "Rock"
		elseif parent:GetAttribute("MineableOre") then
			return parent, parent:GetAttribute("OreType") or "Iron_Ore"
		end
	end

	return nil, nil
end

-- ─── Highlight management ───
local function clearHighlight()
	if currentHighlight then
		currentHighlight:Destroy()
		currentHighlight = nil
	end
	highlightedPart = nil
	highlightedOreType = nil
end

local function setHighlight(part, oreType)
	if highlightedPart == part then return end
	clearHighlight()

	local hl = Instance.new("Highlight")
	hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(255, 200, 50)
	hl.OutlineTransparency = 0
	hl.Adornee = part
	hl.Parent = playerGui
	currentHighlight = hl
	highlightedPart = part
	highlightedOreType = oreType
end

-- ─── Floating popup ───
local function showMinedPopup(worldPos, oreType, amount)
	local screenPos, onScreen = camera:WorldToScreenPoint(worldPos)
	if not onScreen then return end

	local rewardType = oreType
	if oreType == "Rock" then rewardType = "Stone" end
	local iconId = RESOURCE_ICONS[rewardType] or RESOURCE_ICONS.Stone

	local gui = Instance.new("ScreenGui")
	gui.Parent = playerGui

	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, 120, 0, 50)
	container.Position = UDim2.new(0, screenPos.X - 60, 0, screenPos.Y - 25)
	container.BackgroundTransparency = 1
	container.Parent = gui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 50, 1, 0)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = "+" .. tostring(amount)
	label.TextColor3 = Color3.fromRGB(255, 220, 100)
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = container

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0, 40, 0, 40)
	icon.Position = UDim2.new(0, 55, 0.5, -20)
	icon.BackgroundTransparency = 1
	icon.Image = iconId
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = container

	local startY = screenPos.Y - 25
	local tweenUp = TweenService:Create(container, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, screenPos.X - 60, 0, startY - 50),
	})
	local tweenFadeText = TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	local tweenFadeIcon = TweenService:Create(icon, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		ImageTransparency = 1,
	})
	tweenUp:Play()
	tweenFadeText:Play()
	tweenFadeIcon:Play()
	tweenUp.Completed:Connect(function()
		gui:Destroy()
	end)
end

-- ─── Track tool equip ───
local function setupCharacter(char)
	if not char then return end

	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == "Pick-Axe" then
			pickAxeEquipped = true
		end
	end)

	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child.Name == "Pick-Axe" then
			pickAxeEquipped = false
			clearHighlight()
		end
	end)

	for _, child in char:GetChildren() do
		if child:IsA("Tool") and child.Name == "Pick-Axe" then
			pickAxeEquipped = true
			break
		end
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

-- ─── Frame update: highlight mineable under cursor ───
RunService.RenderStepped:Connect(function()
	if not pickAxeEquipped then
		if currentHighlight then clearHighlight() end
		return
	end

	local part, oreType = getMineableUnderMouse()
	if part then
		setHighlight(part, oreType)
		lastMinedPosition = part.Position
	else
		clearHighlight()
	end
end)

-- ─── Click to mine Iron_Ore (Rocks are handled by PickAxeClient) ───
mouse.Button1Down:Connect(function()
	if not pickAxeEquipped then return end
	if oreMiningCooldown then return end
	if not highlightedPart then return end
	if highlightedOreType == "Rock" then return end -- PickAxeClient handles rocks

	oreMiningCooldown = true

	-- Play mining animation
	local chr = player.Character
	if chr then
		local humanoid = chr:FindFirstChildWhichIsA("Humanoid")
		local tool = chr:FindFirstChild("Pick-Axe")
		if humanoid and tool then
			local anim = tool:FindFirstChildWhichIsA("Animation", true)
			if anim then
				local track = humanoid:LoadAnimation(anim)
				track:Play()
			end
		end
	end

	mineOreEvent:FireServer(highlightedPart)

	task.delay(0.5, function()
		oreMiningCooldown = false
	end)
end)

-- ─── Server feedback from MineOre ───
mineOreEvent.OnClientEvent:Connect(function(action, value, oreType)
	if action == "destroyed" then
		local oType = oreType or "Iron_Ore"
		if lastMinedPosition then
			showMinedPopup(lastMinedPosition, oType, value)
			lastMinedPosition = nil
		end
		-- Show "+1 Iron Ore" text feedback
		feedbackLabel.Text = "+" .. value .. " Iron Ore"
		feedbackLabel.Visible = true
		feedbackLabel.TextTransparency = 0
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

-- ─── Server feedback from MineRock (for rock destroyed popup) ───
mineRockEvent.OnClientEvent:Connect(function(action, value)
	if action == "destroyed" then
		if lastMinedPosition then
			showMinedPopup(lastMinedPosition, "Rock", value)
			lastMinedPosition = nil
		end
	end
end)
