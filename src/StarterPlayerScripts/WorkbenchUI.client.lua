local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local craftEvent = ReplicatedStorage:WaitForChild("CraftItem")
local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate")
local openWorkbenchEvent = ReplicatedStorage:WaitForChild("OpenWorkbench")

local LOG_ICON = "rbxassetid://95176887036839"
local COST_ICONS = {
	Log = LOG_ICON,
	Stone = "rbxassetid://96450657403376",
	Plastic = "rbxassetid://132919988751848",
	Iron_Ore = "rbxassetid://78456892304314",
	Iron_Ingot = "rbxassetid://72890243946368",
	Plank = "rbxassetid://118108820731466",
	Leaves = "rbxassetid://96691360298069",
	Rope = "rbxassetid://78492721752628",
}

local CATEGORY_ORDER = {"All", "Tools", "Storage", "Structures", "Equipment", "Decor"}
local RECIPES = {
	{ name = "Wood_Knife", displayName = "Wood Knife", icon = "rbxassetid://95176887036839", costs = {Log = 2}, category = "Tools", description = "Lightweight starter weapon for close combat." },
	{ name = "Bed", displayName = "Bed", icon = "rbxassetid://85069521486600", costs = {Log = 2}, category = "Structures", description = "Respawn point and place to rest." },
	{ name = "Furnace", displayName = "Furnace", icon = "rbxassetid://117760352651529", costs = {Stone = 10, Log = 5}, category = "Structures", description = "Smelt ore into useful materials." },
	{ name = "Sawmill", displayName = "Sawmill", icon = "rbxassetid://75858978626954", costs = {Log = 1}, category = "Structures", description = "Process logs into planks." },
	{ name = "SmallContainer", displayName = "Small Container", icon = "rbxassetid://86632287242518", costs = {Log = 1}, category = "Storage", description = "Compact storage for starter resources." },
	{ name = "PlasticContainer", displayName = "Plastic Container", icon = "rbxassetid://98308527317479", costs = {Plastic = 5}, category = "Storage", description = "A large container for storing items." },
	{ name = "Anchor_part", displayName = "Anchor", icon = "rbxassetid://120414328052740", costs = {Log = 1}, category = "Equipment", description = "Stops raft drift when deployed." },
}

local inventory = {Log = 0, Stone = 0, Plastic = 0}
local screenGui, recipesGrid, detailsPanel, searchBox, qtyLabel, craftButton, logCountLabel
local selectedRecipe = RECIPES[1]
local selectedCategory = "All"
local craftAmount = 1
local isOpen = false

local THEME = {
	panel = Color3.fromRGB(191, 153, 108),
	panelDark = Color3.fromRGB(168, 131, 92),
	panelLight = Color3.fromRGB(214, 183, 141),
	card = Color3.fromRGB(207, 172, 128),
	text = Color3.fromRGB(64, 45, 30),
	accent = Color3.fromRGB(132, 93, 56),
	danger = Color3.fromRGB(188, 73, 73),
	ok = Color3.fromRGB(66, 150, 74),
}

local function computeUIScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local s = math.min(vp.X / 1280, vp.Y / 720)
	return math.clamp(s, 0.7, 1)
end

local function affordableTimes(recipe)
	local maxCount = math.huge
	for item, amount in recipe.costs do
		maxCount = math.min(maxCount, math.floor((inventory[item] or 0) / amount))
	end
	return maxCount == math.huge and 0 or maxCount
end

local function filteredRecipes()
	local query = searchBox and string.lower(searchBox.Text or "") or ""
	local out = {}
	for _, r in ipairs(RECIPES) do
		local categoryOk = selectedCategory == "All" or r.category == selectedCategory
		local queryOk = query == "" or string.find(string.lower(r.displayName), query, 1, true)
		if categoryOk and queryOk then
			table.insert(out, r)
		end
	end
	return out
end

local function closeUI()
	if screenGui then screenGui:Destroy() end
	screenGui = nil
	isOpen = false
end

local function buildCostLine(parent, item, need, have)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundColor3 = Color3.fromRGB(239, 224, 196)
	row.Parent = parent
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0, 20, 0, 20)
	icon.Position = UDim2.new(0, 8, 0.5, -10)
	icon.BackgroundTransparency = 1
	icon.Image = COST_ICONS[item] or LOG_ICON
	icon.Parent = row

	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, -36, 1, 0)
	text.Position = UDim2.new(0, 32, 0, 0)
	text.BackgroundTransparency = 1
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.Text = string.format("%s %d/%d", item, math.min(have, need), need)
	text.TextColor3 = have >= need and THEME.ok or THEME.danger
	text.Parent = row
end

local function refreshDetails()
	if not detailsPanel or not selectedRecipe then return end
	local maxCraft = affordableTimes(selectedRecipe)
	if craftAmount > math.max(1, maxCraft) then craftAmount = math.max(1, maxCraft) end
	qtyLabel.Text = tostring(craftAmount)

	detailsPanel.Title.Text = selectedRecipe.displayName
	detailsPanel.Icon.Image = selectedRecipe.icon
	detailsPanel.Desc.Text = selectedRecipe.description or ""
	for _, c in ipairs(detailsPanel.Costs:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end

	for item, amount in selectedRecipe.costs do
		buildCostLine(detailsPanel.Costs, item, amount * craftAmount, inventory[item] or 0)
	end

	local canCraft = maxCraft > 0
	craftButton.BackgroundColor3 = canCraft and THEME.accent or Color3.fromRGB(150, 150, 150)
	craftButton.AutoButtonColor = canCraft
	craftButton.Text = canCraft and ("Craft x" .. craftAmount) or "Not enough resources"
end

local function refreshGrid()
	if not recipesGrid then return end
	for _, c in ipairs(recipesGrid:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
	for _, recipe in ipairs(filteredRecipes()) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 136, 0, 172)
		btn.BackgroundColor3 = THEME.card
		btn.Text = ""
		btn.Parent = recipesGrid
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(0, 80, 0, 80)
		icon.Position = UDim2.new(0.5, -40, 0, 10)
		icon.BackgroundTransparency = 1
		icon.Image = recipe.icon
		icon.Parent = btn

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -12, 0, 38)
		name.Position = UDim2.new(0, 6, 0, 94)
		name.BackgroundTransparency = 1
		name.TextWrapped = true
		name.TextScaled = true
		name.Font = Enum.Font.Gotham
		name.TextColor3 = THEME.text
		name.Text = recipe.displayName
		name.Parent = btn

		local affordable = affordableTimes(recipe) > 0
		local cost = Instance.new("TextLabel")
		cost.Size = UDim2.new(1, -10, 0, 24)
		cost.Position = UDim2.new(0, 5, 1, -28)
		cost.BackgroundTransparency = 1
		cost.TextScaled = true
		cost.Font = Enum.Font.GothamBold
		cost.TextColor3 = affordable and THEME.ok or THEME.danger
		local firstItem, firstAmt = next(recipe.costs)
		cost.Text = string.format("%d %s", firstAmt, firstItem)
		cost.Parent = btn

		btn.MouseButton1Click:Connect(function()
			selectedRecipe = recipe
			craftAmount = 1
			refreshGrid()
			refreshDetails()
		end)

		if selectedRecipe == recipe then
			local st = Instance.new("UIStroke")
			st.Thickness = 3
			st.Color = Color3.fromRGB(255, 255, 255)
			st.Parent = btn
		end
	end
end

local function buildUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "WorkbenchGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = computeUIScale()
	uiScale.Parent = screenGui

	local main = Instance.new("Frame")
	main.Size = UDim2.new(0, 820, 0, 500)
	main.Position = UDim2.new(0.5, -410, 0.5, -250)
	main.BackgroundColor3 = THEME.panelLight
	main.Parent = screenGui
	Instance.new("UICorner", main).CornerRadius = UDim.new(0, 16)
	Instance.new("UIStroke", main).Color = THEME.accent

	local top = Instance.new("Frame", main)
	top.Size = UDim2.new(1, -24, 0, 42)
	top.Position = UDim2.new(0, 12, 0, 10)
	top.BackgroundTransparency = 1
	local icon = Instance.new("ImageLabel", top)
	icon.Size = UDim2.new(0, 28, 0, 28)
	icon.BackgroundTransparency = 1
	icon.Image = LOG_ICON
	icon.Position = UDim2.new(0, 0, 0.5, -14)
	logCountLabel = Instance.new("TextLabel", top)
	logCountLabel.Size = UDim2.new(0, 150, 1, 0)
	logCountLabel.Position = UDim2.new(0, 34, 0, 0)
	logCountLabel.BackgroundTransparency = 1
	logCountLabel.TextXAlignment = Enum.TextXAlignment.Left
	logCountLabel.TextScaled = true
	logCountLabel.Font = Enum.Font.GothamBold
	logCountLabel.TextColor3 = Color3.fromRGB(74, 55, 38)

	local closeBtn = Instance.new("TextButton", main)
	closeBtn.Size = UDim2.new(0, 42, 0, 42)
	closeBtn.Position = UDim2.new(1, -54, 0, 10)
	closeBtn.Text = "✕"
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.BackgroundColor3 = THEME.accent
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 10)
	closeBtn.MouseButton1Click:Connect(closeUI)

	local left = Instance.new("Frame", main)
	left.Size = UDim2.new(0, 170, 1, -78)
	left.Position = UDim2.new(0, 14, 0, 62)
	left.BackgroundColor3 = THEME.panel
	Instance.new("UICorner", left).CornerRadius = UDim.new(0, 10)

	local list = Instance.new("UIListLayout", left)
	list.Padding = UDim.new(0, 6)
	for _, c in ipairs(CATEGORY_ORDER) do
		local b = Instance.new("TextButton", left)
		b.Size = UDim2.new(1, -12, 0, 52)
		b.Position = UDim2.new(0, 6, 0, 0)
		b.Text = c
		b.Font = Enum.Font.GothamBold
		b.TextScaled = false
		b.TextSize = 30
		b.BackgroundColor3 = THEME.panelLight
		b.TextColor3 = THEME.text
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 9)
		b.MouseButton1Click:Connect(function()
			selectedCategory = c
			refreshGrid()
		end)
	end

	searchBox = Instance.new("TextBox", left)
	searchBox.PlaceholderText = "Search..."
	searchBox.Text = ""
	searchBox.Size = UDim2.new(1, -12, 0, 42)
	searchBox.TextScaled = false
	searchBox.TextSize = 28
	searchBox.Font = Enum.Font.Gotham
	searchBox.BackgroundColor3 = THEME.panelLight
	searchBox.TextColor3 = THEME.text
	Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 8)
	searchBox:GetPropertyChangedSignal("Text"):Connect(refreshGrid)

	local center = Instance.new("Frame", main)
	center.Size = UDim2.new(0, 470, 1, -78)
	center.Position = UDim2.new(0, 194, 0, 62)
	center.BackgroundColor3 = THEME.panel
	Instance.new("UICorner", center).CornerRadius = UDim.new(0, 10)

	recipesGrid = Instance.new("Frame", center)
	recipesGrid.Size = UDim2.new(1, -16, 1, -16)
	recipesGrid.Position = UDim2.new(0, 8, 0, 8)
	recipesGrid.BackgroundTransparency = 1
	local grid = Instance.new("UIGridLayout", recipesGrid)
	grid.CellSize = UDim2.new(0, 136, 0, 172)
	grid.CellPadding = UDim2.new(0, 8, 0, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder

	local right = Instance.new("Frame", main)
	right.Size = UDim2.new(0, 248, 1, -78)
	right.Position = UDim2.new(1, -262, 0, 62)
	right.BackgroundColor3 = THEME.panel
	Instance.new("UICorner", right).CornerRadius = UDim.new(0, 10)
	detailsPanel = right

	local title = Instance.new("TextLabel", right)
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 0, 38)
	title.Position = UDim2.new(0, 8, 0, 8)
	title.BackgroundTransparency = 1
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = THEME.text

	local dIcon = Instance.new("ImageLabel", right)
	dIcon.Name = "Icon"
	dIcon.Size = UDim2.new(0, 130, 0, 130)
	dIcon.Position = UDim2.new(0.5, -65, 0, 50)
	dIcon.BackgroundTransparency = 1

	local dDesc = Instance.new("TextLabel", right)
	dDesc.Name = "Desc"
	dDesc.Size = UDim2.new(1, -20, 0, 70)
	dDesc.Position = UDim2.new(0, 10, 0, 188)
	dDesc.BackgroundTransparency = 1
	dDesc.TextWrapped = true
	dDesc.TextYAlignment = Enum.TextYAlignment.Top
	dDesc.TextXAlignment = Enum.TextXAlignment.Left
	dDesc.Font = Enum.Font.Gotham
	dDesc.TextScaled = true
	dDesc.TextColor3 = THEME.text

	local costs = Instance.new("Frame", right)
	costs.Name = "Costs"
	costs.Size = UDim2.new(1, -20, 0, 112)
	costs.Position = UDim2.new(0, 10, 0, 262)
	costs.BackgroundTransparency = 1
	local costsLayout = Instance.new("UIListLayout", costs)
	costsLayout.Padding = UDim.new(0, 6)

	local minus = Instance.new("TextButton", right)
	minus.Size = UDim2.new(0, 44, 0, 40)
	minus.Position = UDim2.new(0, 10, 1, -96)
	minus.Text = "-"
	minus.TextScaled = true
	minus.Font = Enum.Font.GothamBold
	minus.BackgroundColor3 = THEME.panelLight
	Instance.new("UICorner", minus).CornerRadius = UDim.new(0, 8)

	qtyLabel = Instance.new("TextLabel", right)
	qtyLabel.Size = UDim2.new(0, 96, 0, 40)
	qtyLabel.Position = UDim2.new(0, 62, 1, -96)
	qtyLabel.BackgroundColor3 = THEME.panelLight
	qtyLabel.TextScaled = true
	qtyLabel.Font = Enum.Font.GothamBold
	qtyLabel.TextColor3 = THEME.text
	Instance.new("UICorner", qtyLabel).CornerRadius = UDim.new(0, 8)

	local plus = Instance.new("TextButton", right)
	plus.Size = UDim2.new(0, 44, 0, 40)
	plus.Position = UDim2.new(0, 166, 1, -96)
	plus.Text = "+"
	plus.TextScaled = true
	plus.Font = Enum.Font.GothamBold
	plus.BackgroundColor3 = THEME.panelLight
	Instance.new("UICorner", plus).CornerRadius = UDim.new(0, 8)

	craftButton = Instance.new("TextButton", right)
	craftButton.Size = UDim2.new(1, -20, 0, 44)
	craftButton.Position = UDim2.new(0, 10, 1, -48)
	craftButton.TextScaled = true
	craftButton.Font = Enum.Font.GothamBold
	craftButton.TextColor3 = Color3.new(1, 1, 1)
	Instance.new("UICorner", craftButton).CornerRadius = UDim.new(0, 8)

	minus.MouseButton1Click:Connect(function() craftAmount = math.max(1, craftAmount - 1); refreshDetails() end)
	plus.MouseButton1Click:Connect(function() craftAmount = craftAmount + 1; refreshDetails() end)
	craftButton.MouseButton1Click:Connect(function()
		if not selectedRecipe then return end
		local maxCraft = affordableTimes(selectedRecipe)
		local count = math.min(craftAmount, maxCraft)
		if count <= 0 then return end
		for _ = 1, count do
			craftEvent:FireServer(selectedRecipe.name)
		end
	end)

	refreshGrid()
	refreshDetails()
end

local function refreshAll()
	if not screenGui then return end
	logCountLabel.Text = tostring(inventory.Log or 0)
	refreshGrid()
	refreshDetails()
end

openWorkbenchEvent.OnClientEvent:Connect(function()
	if isOpen then return end
	isOpen = true
	buildUI()
	refreshAll()
end)

inventoryEvent.OnClientEvent:Connect(function(newInv)
	if typeof(newInv) == "table" then
		inventory = newInv
		refreshAll()
	end
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.E and isOpen then
		closeUI()
	end
end)

local function refreshScale()
	if not screenGui then return end
	local s = computeUIScale()
	local uiScale = screenGui:FindFirstChildOfClass("UIScale")
	if uiScale then uiScale.Scale = s end
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(refreshScale)
local cam = workspace.CurrentCamera
if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale) end
