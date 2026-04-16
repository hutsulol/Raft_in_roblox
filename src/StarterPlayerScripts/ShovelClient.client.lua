-- ShovelClient.client.lua
-- Client-side Shovel tool: highlights Sand/Clay parts, handles click-to-dig

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local digDirtEvent = ReplicatedStorage:WaitForChild("DigDirt")

-- ─── State ───
local shovelEquipped = false
local currentTool = nil
local highlightedPart = nil
local highlightBox = nil
local diggingCooldown = false

-- ─── Hint UI ───
local playerGui = player:WaitForChild("PlayerGui")
local hintGui = Instance.new("ScreenGui")
hintGui.Name = "ShovelHint"
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

-- ─── Dig feedback notification ───
local feedbackLabel = Instance.new("TextLabel")
feedbackLabel.Name = "DigFeedback"
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

-- ─── Highlight box ───
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
	highlightedPart = nil
end

-- ─── Find diggable part from raycast target ───
local function findDiggable(instance)
	if not instance then return nil end
	if instance:IsA("BasePart") and instance:GetAttribute("Diggable") then
		return instance
	end
	local parent = instance.Parent
	if parent and parent:IsA("BasePart") and parent:GetAttribute("Diggable") then
		return parent
	end
	return nil
end

-- ─── Play dig animation if available ───
local function playDigAnimation()
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then return end

	if currentTool then
		local anim = currentTool:FindFirstChildWhichIsA("Animation", true)
		if anim then
			local track = humanoid:LoadAnimation(anim)
			track:Play()
		end
	end
end

-- ─── Update highlight each frame ───
local function updateHighlight()
	if not shovelEquipped then
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
		local part = findDiggable(result.Instance)
		if part then
			highlightedPart = part
			if highlightBox then
				highlightBox.Adornee = part
			end
			hintLabel.Text = "Click to dig " .. (part:GetAttribute("DigType") or "dirt")
			hintLabel.Visible = true
			return
		end
	end

	clearHighlight()
	hintLabel.Text = "Aim at sand or clay to dig"
	hintLabel.Visible = true
end

-- ─── Tool equip detection ───
local function onToolEquipped(tool)
	if tool.Name == "Shovel" then
		shovelEquipped = true
		currentTool = tool
		createHighlight()
		hintLabel.Visible = true
	end
end

local function onToolUnequipped(tool)
	if tool.Name == "Shovel" then
		shovelEquipped = false
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

	for _, child in char:GetChildren() do
		if child:IsA("Tool") and child.Name == "Shovel" then
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
	if shovelEquipped then
		updateHighlight()
	end
end)

-- ─── Click to dig ───
mouse.Button1Down:Connect(function()
	if not shovelEquipped then return end
	if diggingCooldown then return end
	if not highlightedPart then return end

	diggingCooldown = true
	playDigAnimation()

	digDirtEvent:FireServer(highlightedPart)

	task.delay(0.5, function()
		diggingCooldown = false
	end)
end)

-- ─── Server feedback ───
digDirtEvent.OnClientEvent:Connect(function(action, value, digType)
	if action == "destroyed" then
		feedbackLabel.Text = "+" .. value .. " " .. (digType or "Sand")
		feedbackLabel.Visible = true
		feedbackLabel.TextTransparency = 0
		clearHighlight()

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
		feedbackLabel.Text = "Digging... (" .. value .. " hits left)"
		feedbackLabel.Visible = true
		feedbackLabel.TextTransparency = 0

		task.spawn(function()
			task.wait(0.8)
			if feedbackLabel.Text:find("Digging") then
				feedbackLabel.Visible = false
			end
		end)
	end
end)
