local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local craftEvent = ReplicatedStorage:WaitForChild("CraftItem")
local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate")

local WORKBENCH_RANGE = 15
local HOLD_TIME = 0.5

local inventory = {Log = 0}
local recipes = {}
local selectedRecipe = nil
local isOpen = false
local holdStart = nil
local screenGui = nil

local LOG_ICON = "rbxassetid://110032041583533"

local function findWorkBench()
	for _, v in workspace:GetDescendants() do
		if v:IsA("Model") and v.Name == "WorkBench" then
			return v
		end
	end
	return nil
end

local function getWorkBenchPos()
	local wb = findWorkBench()
	if not wb then return nil end
	if wb.PrimaryPart then
		return wb.PrimaryPart.Position
	end
	local part = wb:FindFirstChildWhichIsA("BasePart", true)
	if part then
		return part.Position
	end
	return nil
end

local function isNearWorkbench()
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return false end
	local wbPos = getWorkBenchPos()
	if not wbPos then return false end
	return (char.HumanoidRootPart.Position - wbPos).Magnitude <= WORKBENCH_RANGE
end

local function canAfford(recipe)
	if not recipe or not recipe.costs then return false end
	for item, amount in recipe.costs do
		if (inventory[item] or 0) < amount then
			return false
		end
	end
	return true
end

local function closeUI()
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	isOpen = false
	selectedRecipe = nil
end

local function updateUI()
	if not screenGui then return end

	local logCount = screenGui:FindFirstChild("LogCount", true)
	if logCount then
		logCount.Text = tostring(inventory.Log or 0)
	end

	local recipeList = screenGui:FindFirstChild("RecipeList", true)
	if recipeList then
		for _, btn in recipeList:GetChildren() do
			if btn:IsA("TextButton") and btn:GetAttribute("RecipeName") then
				local rName = btn:GetAttribute("RecipeName")
				for _, r in recipes do
					if r.name == rName then
						local costLabel = btn:FindFirstChild("CostLabel", true)
						if costLabel then
							local affordable = canAfford(r)
							costLabel.TextColor3 = affordable and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 80, 80)
						end
					end
				end
			end
		end
	end

	local detailPanel = screenGui:FindFirstChild("DetailPanel", true)
	if detailPanel then
		if selectedRecipe then
			detailPanel.Visible = true
			local titleLabel = detailPanel:FindFirstChild("DetailTitle")
			if titleLabel then
				titleLabel.Text = selectedRecipe.displayName or selectedRecipe.name
			end
			local detailIcon = detailPanel:FindFirstChild("DetailIcon")
			if detailIcon then
				detailIcon.Image = selectedRecipe.icon or ""
			end
			local costDetail = detailPanel:FindFirstChild("CostDetail")
			if costDetail then
				local txt = ""
				for item, amount in selectedRecipe.costs do
					txt = txt .. tostring(amount) .. " " .. item
				end
				costDetail.Text = txt
			end
			local craftBtn = detailPanel:FindFirstChild("CraftButton")
			if craftBtn then
				local affordable = canAfford(selectedRecipe)
				craftBtn.BackgroundColor3 = affordable and Color3.fromRGB(60, 140, 60) or Color3.fromRGB(100, 100, 100)
			end
		else
			detailPanel.Visible = false
		end
	end
end

local function selectRecipe(recipe)
	selectedRecipe = recipe
	updateUI()
end

local function buildUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "WorkbenchGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.new(0, 700, 0, 450)
	main.Position = UDim2.new(0.5, -350, 0.5, -225)
	main.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
	main.BorderSizePixel = 0
	main.Parent = screenGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 12)
	mainCorner.Parent = main

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Color3.fromRGB(80, 80, 90)
	mainStroke.Thickness = 2
	mainStroke.Parent = main

	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 50)
	topBar.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	topBar.BorderSizePixel = 0
	topBar.Parent = main

	local topCorner = Instance.new("UICorner")
	topCorner.CornerRadius = UDim.new(0, 12)
	topCorner.Parent = topBar

	local topFix = Instance.new("Frame")
	topFix.Size = UDim2.new(1, 0, 0, 12)
	topFix.Position = UDim2.new(0, 0, 1, -12)
	topFix.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	topFix.BorderSizePixel = 0
	topFix.Parent = topBar

	local logIcon = Instance.new("ImageLabel")
	logIcon.Size = UDim2.new(0, 30, 0, 30)
	logIcon.Position = UDim2.new(0, 15, 0.5, -15)
	logIcon.BackgroundTransparency = 1
	logIcon.Image = LOG_ICON
	logIcon.ScaleType = Enum.ScaleType.Fit
	logIcon.Parent = topBar

	local logCount = Instance.new("TextLabel")
	logCount.Name = "LogCount"
	logCount.Size = UDim2.new(0, 50, 0, 30)
	logCount.Position = UDim2.new(0, 50, 0.5, -15)
	logCount.BackgroundTransparency = 1
	logCount.Text = tostring(inventory.Log or 0)
	logCount.TextColor3 = Color3.new(1, 1, 1)
	logCount.TextScaled = true
	logCount.Font = Enum.Font.GothamBold
	logCount.TextXAlignment = Enum.TextXAlignment.Left
	logCount.Parent = topBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -45, 0.5, -20)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = topBar

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 8)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(closeUI)

	local leftPanel = Instance.new("Frame")
	leftPanel.Name = "LeftPanel"
	leftPanel.Size = UDim2.new(0, 420, 0, 380)
	leftPanel.Position = UDim2.new(0, 15, 0, 60)
	leftPanel.BackgroundColor3 = Color3.fromRGB(55, 55, 60)
	leftPanel.BorderSizePixel = 0
	leftPanel.Parent = main

	local leftCorner = Instance.new("UICorner")
	leftCorner.CornerRadius = UDim.new(0, 8)
	leftCorner.Parent = leftPanel

	local sectionTitle = Instance.new("TextLabel")
	sectionTitle.Size = UDim2.new(1, -20, 0, 30)
	sectionTitle.Position = UDim2.new(0, 10, 0, 5)
	sectionTitle.BackgroundTransparency = 1
	sectionTitle.Text = "Crafting - Level 1"
	sectionTitle.TextColor3 = Color3.new(1, 1, 1)
	sectionTitle.TextScaled = true
	sectionTitle.Font = Enum.Font.GothamBold
	sectionTitle.TextXAlignment = Enum.TextXAlignment.Left
	sectionTitle.Parent = leftPanel

	local recipeList = Instance.new("Frame")
	recipeList.Name = "RecipeList"
	recipeList.Size = UDim2.new(1, -20, 1, -45)
	recipeList.Position = UDim2.new(0, 10, 0, 40)
	recipeList.BackgroundTransparency = 1
	recipeList.Parent = leftPanel

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 120, 0, 130)
	grid.CellPadding = UDim2.new(0, 10, 0, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = recipeList

	for i, recipe in recipes do
		local btn = Instance.new("TextButton")
		btn.Name = "Recipe_" .. recipe.name
		btn.BackgroundColor3 = Color3.fromRGB(70, 70, 75)
		btn.Text = ""
		btn.BorderSizePixel = 0
		btn.LayoutOrder = i
		btn.AutoButtonColor = true
		btn.Parent = recipeList
		btn:SetAttribute("RecipeName", recipe.name)

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = Color3.fromRGB(90, 90, 100)
		btnStroke.Thickness = 1
		btnStroke.Parent = btn

		local iconFrame = Instance.new("ImageLabel")
		iconFrame.Name = "Icon"
		iconFrame.Size = UDim2.new(0, 60, 0, 60)
		iconFrame.Position = UDim2.new(0.5, -30, 0, 10)
		iconFrame.BackgroundTransparency = 1
		iconFrame.Image = recipe.icon or ""
		iconFrame.ScaleType = Enum.ScaleType.Fit
		iconFrame.Parent = btn

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(1, -10, 0, 20)
		nameLabel.Position = UDim2.new(0, 5, 0, 72)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = recipe.displayName or recipe.name
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.Gotham
		nameLabel.Parent = btn

		local costText = ""
		for _, amount in recipe.costs do
			costText = costText .. tostring(amount)
		end

		local costIcon = Instance.new("ImageLabel")
		costIcon.Size = UDim2.new(0, 20, 0, 20)
		costIcon.Position = UDim2.new(0, 8, 1, -28)
		costIcon.BackgroundTransparency = 1
		costIcon.Image = LOG_ICON
		costIcon.ScaleType = Enum.ScaleType.Fit
		costIcon.Parent = btn

		local costLabel = Instance.new("TextLabel")
		costLabel.Name = "CostLabel"
		costLabel.Size = UDim2.new(0, 30, 0, 20)
		costLabel.Position = UDim2.new(0, 30, 1, -28)
		costLabel.BackgroundTransparency = 1
		costLabel.Text = costText
		costLabel.TextScaled = true
		costLabel.Font = Enum.Font.GothamBold
		costLabel.TextXAlignment = Enum.TextXAlignment.Left
		costLabel.Parent = btn

		btn.MouseButton1Click:Connect(function()
			selectRecipe(recipe)
		end)
	end

	local detailPanel = Instance.new("Frame")
	detailPanel.Name = "DetailPanel"
	detailPanel.Size = UDim2.new(0, 240, 0, 380)
	detailPanel.Position = UDim2.new(0, 445, 0, 60)
	detailPanel.BackgroundColor3 = Color3.fromRGB(55, 55, 60)
	detailPanel.BorderSizePixel = 0
	detailPanel.Visible = false
	detailPanel.Parent = main

	local detailCorner = Instance.new("UICorner")
	detailCorner.CornerRadius = UDim.new(0, 8)
	detailCorner.Parent = detailPanel

	local detailTitle = Instance.new("TextLabel")
	detailTitle.Name = "DetailTitle"
	detailTitle.Size = UDim2.new(1, -20, 0, 35)
	detailTitle.Position = UDim2.new(0, 10, 0, 10)
	detailTitle.BackgroundTransparency = 1
	detailTitle.Text = ""
	detailTitle.TextColor3 = Color3.new(1, 1, 1)
	detailTitle.TextScaled = true
	detailTitle.Font = Enum.Font.GothamBold
	detailTitle.TextWrapped = true
	detailTitle.Parent = detailPanel

	local detailIcon = Instance.new("ImageLabel")
	detailIcon.Name = "DetailIcon"
	detailIcon.Size = UDim2.new(0, 120, 0, 120)
	detailIcon.Position = UDim2.new(0.5, -60, 0, 55)
	detailIcon.BackgroundTransparency = 1
	detailIcon.Image = ""
	detailIcon.ScaleType = Enum.ScaleType.Fit
	detailIcon.Parent = detailPanel

	local costDetailIcon = Instance.new("ImageLabel")
	costDetailIcon.Size = UDim2.new(0, 25, 0, 25)
	costDetailIcon.Position = UDim2.new(0.5, -30, 0, 200)
	costDetailIcon.BackgroundTransparency = 1
	costDetailIcon.Image = LOG_ICON
	costDetailIcon.ScaleType = Enum.ScaleType.Fit
	costDetailIcon.Parent = detailPanel

	local costDetail = Instance.new("TextLabel")
	costDetail.Name = "CostDetail"
	costDetail.Size = UDim2.new(0, 60, 0, 25)
	costDetail.Position = UDim2.new(0.5, 0, 0, 200)
	costDetail.BackgroundTransparency = 1
	costDetail.Text = ""
	costDetail.TextColor3 = Color3.fromRGB(255, 220, 100)
	costDetail.TextScaled = true
	costDetail.Font = Enum.Font.GothamBold
	costDetail.TextXAlignment = Enum.TextXAlignment.Left
	costDetail.Parent = detailPanel

	local craftBtn = Instance.new("TextButton")
	craftBtn.Name = "CraftButton"
	craftBtn.Size = UDim2.new(0, 160, 0, 45)
	craftBtn.Position = UDim2.new(0.5, -80, 1, -65)
	craftBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 60)
	craftBtn.Text = "Craft"
	craftBtn.TextColor3 = Color3.new(1, 1, 1)
	craftBtn.TextScaled = true
	craftBtn.Font = Enum.Font.GothamBold
	craftBtn.BorderSizePixel = 0
	craftBtn.Parent = detailPanel

	local craftBtnCorner = Instance.new("UICorner")
	craftBtnCorner.CornerRadius = UDim.new(0, 8)
	craftBtnCorner.Parent = craftBtn

	craftBtn.MouseButton1Click:Connect(function()
		if selectedRecipe and canAfford(selectedRecipe) then
			craftEvent:FireServer("craft", selectedRecipe.name)
		end
	end)

	updateUI()
end

local function openUI()
	if isOpen then return end
	if not isNearWorkbench() then return end
	isOpen = true
	craftEvent:FireServer("requestRecipes")
	buildUI()
end

inventoryEvent.OnClientEvent:Connect(function(inv)
	inventory = inv
	updateUI()
end)

craftEvent.OnClientEvent:Connect(function(action, data, inv)
	if action == "recipes" then
		recipes = data
		if inv then
			inventory = inv
		end
		if isOpen then
			closeUI()
			isOpen = true
			buildUI()
		end
	elseif action == "success" then
		local successGui = Instance.new("ScreenGui")
		successGui.Parent = playerGui

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0, 300, 0, 50)
		label.Position = UDim2.new(0.5, -150, 0.3, 0)
		label.BackgroundTransparency = 1
		label.Text = "Crafted!"
		label.TextColor3 = Color3.fromRGB(100, 255, 100)
		label.TextStrokeTransparency = 0.5
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Parent = successGui

		local tween = TweenService:Create(label, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, -150, 0.25, 0),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			successGui:Destroy()
		end)
	end
end)

local holdingE = false
local hoveringWorkbench = false
local promptBillboard = nil

local function isMouseOnWorkbench()
	local camera = workspace.CurrentCamera
	local mouse = player:GetMouse()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {player.Character}

	local result = workspace:Raycast(ray.Origin, ray.Direction * 50, params)
	if not result or not result.Instance then return false end

	local hit = result.Instance
	local wb = findWorkBench()
	if not wb then return false end

	if hit:IsDescendantOf(wb) or hit == wb then
		return true
	end

	return false
end

local function showPrompt()
	if promptBillboard then return end

	local wb = findWorkBench()
	if not wb then return end

	local adornee = wb.PrimaryPart or wb:FindFirstChildWhichIsA("BasePart", true)
	if not adornee then return end

	promptBillboard = Instance.new("BillboardGui")
	promptBillboard.Size = UDim2.new(6, 0, 1.5, 0)
	promptBillboard.StudsOffset = Vector3.new(0, 4, 0)
	promptBillboard.AlwaysOnTop = true
	promptBillboard.Adornee = adornee
	promptBillboard.Parent = playerGui

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	bg.BackgroundTransparency = 0.2
	bg.BorderSizePixel = 0
	bg.Parent = promptBillboard

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0.2, 0)
	bgCorner.Parent = bg

	local eKey = Instance.new("TextLabel")
	eKey.Size = UDim2.new(0.15, 0, 0.6, 0)
	eKey.Position = UDim2.new(0.15, 0, 0.2, 0)
	eKey.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
	eKey.Text = "E"
	eKey.TextColor3 = Color3.new(1, 1, 1)
	eKey.TextScaled = true
	eKey.Font = Enum.Font.GothamBold
	eKey.BorderSizePixel = 0
	eKey.Parent = bg

	local eCorner = Instance.new("UICorner")
	eCorner.CornerRadius = UDim.new(0.2, 0)
	eCorner.Parent = eKey

	local eStroke = Instance.new("UIStroke")
	eStroke.Color = Color3.fromRGB(120, 120, 130)
	eStroke.Thickness = 1
	eStroke.Parent = eKey

	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.new(0.5, 0, 0.6, 0)
	txt.Position = UDim2.new(0.35, 0, 0.2, 0)
	txt.BackgroundTransparency = 1
	txt.Text = "Craft"
	txt.TextColor3 = Color3.new(1, 1, 1)
	txt.TextScaled = true
	txt.Font = Enum.Font.GothamBold
	txt.TextXAlignment = Enum.TextXAlignment.Left
	txt.Parent = bg
end

local function hidePrompt()
	if promptBillboard then
		promptBillboard:Destroy()
		promptBillboard = nil
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.E then
		if isOpen then
			closeUI()
			return
		end
		if not hoveringWorkbench then return end
		if not isNearWorkbench() then return end
		holdingE = true
		holdStart = tick()

		task.spawn(function()
			while holdingE do
				task.wait(0.05)
				if holdingE and tick() - holdStart >= HOLD_TIME then
					openUI()
					holdingE = false
					hidePrompt()
					break
				end
			end
		end)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.E then
		holdingE = false
	end
end)

RunService.RenderStepped:Connect(function()
	local onWB = isMouseOnWorkbench()
	local near = isNearWorkbench()

	if onWB and near and not isOpen then
		hoveringWorkbench = true
		showPrompt()
	else
		hoveringWorkbench = false
		hidePrompt()
	end

	if isOpen and not near then
		closeUI()
	end
end)
