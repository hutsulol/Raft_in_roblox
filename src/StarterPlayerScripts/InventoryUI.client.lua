local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate")
local inventoryCraftEvent = ReplicatedStorage:WaitForChild("InventoryCraft")

local LOG_ICON = "rbxassetid://110032041583533"

local inventory = {Log = 0}
local recipes = {}
local selectedRecipe = nil
local isOpen = false
local screenGui = nil
local hotbarGui = nil

-- Colors matching RAFT style (brown/tan theme)
local COLORS = {
	panelBg = Color3.fromRGB(139, 109, 63),
	panelBorder = Color3.fromRGB(100, 75, 40),
	slotBg = Color3.fromRGB(175, 145, 95),
	slotBorder = Color3.fromRGB(120, 90, 50),
	titleText = Color3.fromRGB(50, 35, 15),
	lightText = Color3.fromRGB(255, 245, 220),
	craftPanelBg = Color3.fromRGB(220, 205, 175),
	craftItemBg = Color3.fromRGB(200, 180, 140),
	craftItemHover = Color3.fromRGB(180, 160, 120),
	affordable = Color3.fromRGB(60, 160, 60),
	notAffordable = Color3.fromRGB(160, 60, 60),
	hotbarBg = Color3.fromRGB(139, 109, 63),
	separator = Color3.fromRGB(200, 185, 150),
}

local INVENTORY_SLOTS = 20 -- 5 columns x 4 rows
local HOTBAR_SLOTS = 8
local SLOT_SIZE = 60
local SLOT_PAD = 6
local COLS = 5

-- ─── Helpers ───

local function canAfford(recipe)
	if not recipe or not recipe.costs then return false end
	for item, amount in recipe.costs do
		if (inventory[item] or 0) < amount then
			return false
		end
	end
	return true
end

local function getItemIcon(itemName)
	if itemName == "Log" then
		return LOG_ICON
	end
	return ""
end

-- ─── Hotbar (always visible) ───

local function buildHotbar()
	if hotbarGui then hotbarGui:Destroy() end

	hotbarGui = Instance.new("ScreenGui")
	hotbarGui.Name = "HotbarGui"
	hotbarGui.ResetOnSpawn = false
	hotbarGui.DisplayOrder = 5
	hotbarGui.Parent = playerGui

	local barWidth = HOTBAR_SLOTS * (SLOT_SIZE + SLOT_PAD) + SLOT_PAD
	local bar = Instance.new("Frame")
	bar.Name = "Hotbar"
	bar.Size = UDim2.new(0, barWidth, 0, SLOT_SIZE + SLOT_PAD * 2)
	bar.Position = UDim2.new(0.5, -barWidth / 2, 1, -(SLOT_SIZE + SLOT_PAD * 2) - 10)
	bar.BackgroundColor3 = COLORS.hotbarBg
	bar.BackgroundTransparency = 0.15
	bar.BorderSizePixel = 0
	bar.Parent = hotbarGui

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 8)
	barCorner.Parent = bar

	local barStroke = Instance.new("UIStroke")
	barStroke.Color = COLORS.panelBorder
	barStroke.Thickness = 2
	barStroke.Parent = bar

	for i = 1, HOTBAR_SLOTS do
		local slot = Instance.new("Frame")
		slot.Name = "HotbarSlot_" .. i
		slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		slot.Position = UDim2.new(0, SLOT_PAD + (i - 1) * (SLOT_SIZE + SLOT_PAD), 0, SLOT_PAD)
		slot.BackgroundColor3 = COLORS.slotBg
		slot.BackgroundTransparency = 0.1
		slot.BorderSizePixel = 0
		slot.Parent = bar

		local slotCorner = Instance.new("UICorner")
		slotCorner.CornerRadius = UDim.new(0, 6)
		slotCorner.Parent = slot

		local slotStroke = Instance.new("UIStroke")
		slotStroke.Color = COLORS.slotBorder
		slotStroke.Thickness = 1.5
		slotStroke.Parent = slot
	end
end

local function updateHotbar()
	if not hotbarGui then return end
	local bar = hotbarGui:FindFirstChild("Hotbar")
	if not bar then return end

	-- Show Log in first hotbar slot if we have any
	local slot1 = bar:FindFirstChild("HotbarSlot_1")
	if slot1 then
		local existing = slot1:FindFirstChild("ItemIcon")
		local existingCount = slot1:FindFirstChild("ItemCount")
		if existing then existing:Destroy() end
		if existingCount then existingCount:Destroy() end

		if (inventory.Log or 0) > 0 then
			local icon = Instance.new("ImageLabel")
			icon.Name = "ItemIcon"
			icon.Size = UDim2.new(0.8, 0, 0.8, 0)
			icon.Position = UDim2.new(0.1, 0, 0.1, 0)
			icon.BackgroundTransparency = 1
			icon.Image = LOG_ICON
			icon.ScaleType = Enum.ScaleType.Fit
			icon.Parent = slot1

			local count = Instance.new("TextLabel")
			count.Name = "ItemCount"
			count.Size = UDim2.new(0, 25, 0, 18)
			count.Position = UDim2.new(1, -27, 1, -20)
			count.BackgroundTransparency = 1
			count.Text = tostring(inventory.Log)
			count.TextColor3 = COLORS.lightText
			count.TextStrokeTransparency = 0.3
			count.TextStrokeColor3 = Color3.new(0, 0, 0)
			count.Font = Enum.Font.GothamBold
			count.TextSize = 14
			count.TextXAlignment = Enum.TextXAlignment.Right
			count.Parent = slot1
		end
	end
end

-- ─── Inventory UI ───

local function closeUI()
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	isOpen = false
	selectedRecipe = nil
end

local function updateInventoryGrid()
	if not screenGui then return end
	local grid = screenGui:FindFirstChild("InventoryGrid", true)
	if not grid then return end

	-- Clear all slot contents
	for i = 1, INVENTORY_SLOTS do
		local slot = grid:FindFirstChild("Slot_" .. i)
		if slot then
			local ic = slot:FindFirstChild("ItemIcon")
			local ct = slot:FindFirstChild("ItemCount")
			if ic then ic:Destroy() end
			if ct then ct:Destroy() end
		end
	end

	-- Fill slots with inventory items
	local slotIndex = 1
	for itemName, amount in inventory do
		if amount > 0 and slotIndex <= INVENTORY_SLOTS then
			local slot = grid:FindFirstChild("Slot_" .. slotIndex)
			if slot then
				local icon = Instance.new("ImageLabel")
				icon.Name = "ItemIcon"
				icon.Size = UDim2.new(0.75, 0, 0.75, 0)
				icon.Position = UDim2.new(0.125, 0, 0.05, 0)
				icon.BackgroundTransparency = 1
				icon.Image = getItemIcon(itemName)
				icon.ScaleType = Enum.ScaleType.Fit
				icon.Parent = slot

				local count = Instance.new("TextLabel")
				count.Name = "ItemCount"
				count.Size = UDim2.new(1, -4, 0, 16)
				count.Position = UDim2.new(0, 2, 1, -18)
				count.BackgroundTransparency = 1
				count.Text = tostring(amount)
				count.TextColor3 = COLORS.lightText
				count.TextStrokeTransparency = 0.3
				count.TextStrokeColor3 = Color3.new(0, 0, 0)
				count.Font = Enum.Font.GothamBold
				count.TextSize = 13
				count.TextXAlignment = Enum.TextXAlignment.Right
				count.Parent = slot
			end
			slotIndex = slotIndex + 1
		end
	end
end

local function updateCraftPanel()
	if not screenGui then return end
	local craftList = screenGui:FindFirstChild("CraftList", true)
	if craftList then
		for _, btn in craftList:GetChildren() do
			if btn:IsA("TextButton") then
				local rName = btn:GetAttribute("RecipeName")
				for _, r in recipes do
					if r.name == rName then
						local costLabel = btn:FindFirstChild("CostLabel")
						if costLabel then
							costLabel.TextColor3 = canAfford(r) and COLORS.affordable or COLORS.notAffordable
						end
						local sel = btn:FindFirstChild("SelectHighlight")
						if sel then
							sel.Visible = (selectedRecipe and selectedRecipe.name == rName)
						end
					end
				end
			end
		end
	end

	-- Update craft button
	local craftBtn = screenGui:FindFirstChild("CraftButton", true)
	if craftBtn then
		if selectedRecipe then
			craftBtn.Visible = true
			craftBtn.BackgroundColor3 = canAfford(selectedRecipe) and COLORS.affordable or Color3.fromRGB(120, 120, 120)
			craftBtn.Text = "Craft " .. (selectedRecipe.displayName or selectedRecipe.name)
		else
			craftBtn.Visible = false
		end
	end

	-- Update cost detail
	local costDetail = screenGui:FindFirstChild("CraftCostDetail", true)
	if costDetail then
		if selectedRecipe then
			local txt = ""
			for item, amount in selectedRecipe.costs do
				txt = txt .. amount .. " " .. item .. "  "
			end
			costDetail.Text = txt
			costDetail.Visible = true
		else
			costDetail.Visible = false
		end
	end
end

local function updateUI()
	updateInventoryGrid()
	updateCraftPanel()
	updateHotbar()
end

local function buildUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "InventoryGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui

	-- ─── Center Inventory Panel ───
	local gridWidth = COLS * (SLOT_SIZE + SLOT_PAD) + SLOT_PAD
	local gridHeight = 4 * (SLOT_SIZE + SLOT_PAD) + SLOT_PAD
	local panelWidth = gridWidth + 30
	local panelHeight = gridHeight + 70

	local centerPanel = Instance.new("Frame")
	centerPanel.Name = "CenterPanel"
	centerPanel.Size = UDim2.new(0, panelWidth, 0, panelHeight)
	centerPanel.Position = UDim2.new(0.5, -panelWidth / 2, 0.5, -panelHeight / 2 - 20)
	centerPanel.BackgroundColor3 = COLORS.panelBg
	centerPanel.BorderSizePixel = 0
	centerPanel.Parent = screenGui

	local centerCorner = Instance.new("UICorner")
	centerCorner.CornerRadius = UDim.new(0, 10)
	centerCorner.Parent = centerPanel

	local centerStroke = Instance.new("UIStroke")
	centerStroke.Color = COLORS.panelBorder
	centerStroke.Thickness = 3
	centerStroke.Parent = centerPanel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -20, 0, 30)
	title.Position = UDim2.new(0, 10, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "Inventory"
	title.TextColor3 = COLORS.titleText
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.Parent = centerPanel

	-- Separator line under title
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -30, 0, 2)
	sep.Position = UDim2.new(0, 15, 0, 42)
	sep.BackgroundColor3 = COLORS.separator
	sep.BorderSizePixel = 0
	sep.Parent = centerPanel

	-- Resource display (top right of panel)
	local resIcon = Instance.new("ImageLabel")
	resIcon.Size = UDim2.new(0, 22, 0, 22)
	resIcon.Position = UDim2.new(1, -75, 0, 12)
	resIcon.BackgroundTransparency = 1
	resIcon.Image = LOG_ICON
	resIcon.ScaleType = Enum.ScaleType.Fit
	resIcon.Parent = centerPanel

	local resCount = Instance.new("TextLabel")
	resCount.Name = "ResCount"
	resCount.Size = UDim2.new(0, 40, 0, 22)
	resCount.Position = UDim2.new(1, -50, 0, 12)
	resCount.BackgroundTransparency = 1
	resCount.Text = tostring(inventory.Log or 0)
	resCount.TextColor3 = COLORS.titleText
	resCount.Font = Enum.Font.GothamBold
	resCount.TextSize = 16
	resCount.TextXAlignment = Enum.TextXAlignment.Left
	resCount.Parent = centerPanel

	-- Inventory grid
	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "InventoryGrid"
	gridFrame.Size = UDim2.new(0, gridWidth, 0, gridHeight)
	gridFrame.Position = UDim2.new(0.5, -gridWidth / 2, 0, 52)
	gridFrame.BackgroundTransparency = 1
	gridFrame.Parent = centerPanel

	for i = 1, INVENTORY_SLOTS do
		local row = math.floor((i - 1) / COLS)
		local col = (i - 1) % COLS

		local slot = Instance.new("Frame")
		slot.Name = "Slot_" .. i
		slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		slot.Position = UDim2.new(0, SLOT_PAD + col * (SLOT_SIZE + SLOT_PAD), 0, SLOT_PAD + row * (SLOT_SIZE + SLOT_PAD))
		slot.BackgroundColor3 = COLORS.slotBg
		slot.BackgroundTransparency = 0.05
		slot.BorderSizePixel = 0
		slot.Parent = gridFrame

		local slotCorner = Instance.new("UICorner")
		slotCorner.CornerRadius = UDim.new(0, 5)
		slotCorner.Parent = slot

		local slotStroke = Instance.new("UIStroke")
		slotStroke.Color = COLORS.slotBorder
		slotStroke.Thickness = 1.5
		slotStroke.Parent = slot
	end

	-- ─── Left Crafting Panel ───
	local craftPanelHeight = panelHeight
	local craftPanelWidth = 200

	local craftPanel = Instance.new("Frame")
	craftPanel.Name = "CraftPanel"
	craftPanel.Size = UDim2.new(0, craftPanelWidth, 0, craftPanelHeight)
	craftPanel.Position = UDim2.new(0.5, -panelWidth / 2 - craftPanelWidth - 10, 0.5, -panelHeight / 2 - 20)
	craftPanel.BackgroundColor3 = COLORS.craftPanelBg
	craftPanel.BorderSizePixel = 0
	craftPanel.Parent = screenGui

	local craftCorner = Instance.new("UICorner")
	craftCorner.CornerRadius = UDim.new(0, 10)
	craftCorner.Parent = craftPanel

	local craftStroke = Instance.new("UIStroke")
	craftStroke.Color = COLORS.panelBorder
	craftStroke.Thickness = 2
	craftStroke.Parent = craftPanel

	-- Craft title
	local craftTitle = Instance.new("TextLabel")
	craftTitle.Size = UDim2.new(1, -15, 0, 28)
	craftTitle.Position = UDim2.new(0, 10, 0, 8)
	craftTitle.BackgroundTransparency = 1
	craftTitle.Text = "Crafting"
	craftTitle.TextColor3 = COLORS.titleText
	craftTitle.Font = Enum.Font.GothamBold
	craftTitle.TextSize = 18
	craftTitle.TextXAlignment = Enum.TextXAlignment.Left
	craftTitle.Parent = craftPanel

	-- Separator
	local craftSep = Instance.new("Frame")
	craftSep.Size = UDim2.new(1, -20, 0, 2)
	craftSep.Position = UDim2.new(0, 10, 0, 38)
	craftSep.BackgroundColor3 = COLORS.panelBorder
	craftSep.BorderSizePixel = 0
	craftSep.Parent = craftPanel

	-- Recipe list
	local craftList = Instance.new("Frame")
	craftList.Name = "CraftList"
	craftList.Size = UDim2.new(1, -16, 1, -100)
	craftList.Position = UDim2.new(0, 8, 0, 48)
	craftList.BackgroundTransparency = 1
	craftList.Parent = craftPanel

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 5)
	listLayout.Parent = craftList

	for i, recipe in recipes do
		local btn = Instance.new("TextButton")
		btn.Name = "Recipe_" .. recipe.name
		btn.Size = UDim2.new(1, 0, 0, 45)
		btn.BackgroundColor3 = COLORS.craftItemBg
		btn.Text = ""
		btn.BorderSizePixel = 0
		btn.LayoutOrder = i
		btn.AutoButtonColor = false
		btn.Parent = craftList
		btn:SetAttribute("RecipeName", recipe.name)

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn

		-- Selection highlight
		local selHighlight = Instance.new("Frame")
		selHighlight.Name = "SelectHighlight"
		selHighlight.Size = UDim2.new(1, 0, 1, 0)
		selHighlight.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
		selHighlight.BackgroundTransparency = 0.7
		selHighlight.BorderSizePixel = 0
		selHighlight.Visible = false
		selHighlight.ZIndex = 2
		selHighlight.Parent = btn

		local selCorner = Instance.new("UICorner")
		selCorner.CornerRadius = UDim.new(0, 6)
		selCorner.Parent = selHighlight

		-- Icon
		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(0, 32, 0, 32)
		icon.Position = UDim2.new(0, 6, 0.5, -16)
		icon.BackgroundTransparency = 1
		icon.Image = recipe.icon or ""
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = btn

		-- Name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -50, 0, 20)
		nameLabel.Position = UDim2.new(0, 44, 0, 3)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = recipe.displayName or recipe.name
		nameLabel.TextColor3 = COLORS.titleText
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 13
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = btn

		-- Cost
		local costText = ""
		for item, amount in recipe.costs do
			costText = amount .. " " .. item
		end

		local costLabel = Instance.new("TextLabel")
		costLabel.Name = "CostLabel"
		costLabel.Size = UDim2.new(1, -50, 0, 16)
		costLabel.Position = UDim2.new(0, 44, 0, 24)
		costLabel.BackgroundTransparency = 1
		costLabel.Text = costText
		costLabel.Font = Enum.Font.Gotham
		costLabel.TextSize = 11
		costLabel.TextXAlignment = Enum.TextXAlignment.Left
		costLabel.Parent = btn

		btn.MouseEnter:Connect(function()
			if not (selectedRecipe and selectedRecipe.name == recipe.name) then
				btn.BackgroundColor3 = COLORS.craftItemHover
			end
		end)

		btn.MouseLeave:Connect(function()
			btn.BackgroundColor3 = COLORS.craftItemBg
		end)

		btn.MouseButton1Click:Connect(function()
			selectedRecipe = recipe
			updateCraftPanel()
		end)
	end

	-- Cost detail for selected recipe
	local costDetail = Instance.new("TextLabel")
	costDetail.Name = "CraftCostDetail"
	costDetail.Size = UDim2.new(1, -16, 0, 18)
	costDetail.Position = UDim2.new(0, 8, 1, -50)
	costDetail.BackgroundTransparency = 1
	costDetail.Text = ""
	costDetail.TextColor3 = COLORS.titleText
	costDetail.Font = Enum.Font.Gotham
	costDetail.TextSize = 12
	costDetail.TextXAlignment = Enum.TextXAlignment.Left
	costDetail.Visible = false
	costDetail.Parent = craftPanel

	-- Craft button
	local craftBtn = Instance.new("TextButton")
	craftBtn.Name = "CraftButton"
	craftBtn.Size = UDim2.new(1, -16, 0, 34)
	craftBtn.Position = UDim2.new(0, 8, 1, -42)
	craftBtn.BackgroundColor3 = COLORS.affordable
	craftBtn.Text = "Craft"
	craftBtn.TextColor3 = Color3.new(1, 1, 1)
	craftBtn.Font = Enum.Font.GothamBold
	craftBtn.TextSize = 15
	craftBtn.BorderSizePixel = 0
	craftBtn.Visible = false
	craftBtn.Parent = craftPanel

	local craftBtnCorner = Instance.new("UICorner")
	craftBtnCorner.CornerRadius = UDim.new(0, 6)
	craftBtnCorner.Parent = craftBtn

	craftBtn.MouseButton1Click:Connect(function()
		if selectedRecipe and canAfford(selectedRecipe) then
			inventoryCraftEvent:FireServer("craft", selectedRecipe.name)
		end
	end)

	-- ─── Close button (top-right of center panel) ───
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 28, 0, 28)
	closeBtn.Position = UDim2.new(1, -32, 0, 6)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = centerPanel

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 6)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(closeUI)

	-- Update with current data
	updateUI()
end

local function toggleInventory()
	if isOpen then
		closeUI()
	else
		isOpen = true
		inventoryCraftEvent:FireServer("requestRecipes")
		buildUI()
	end
end

-- ─── Input ───

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E then
		toggleInventory()
	end
end)

-- ─── Events ───

inventoryEvent.OnClientEvent:Connect(function(inv)
	inventory = inv
	updateUI()
end)

inventoryCraftEvent.OnClientEvent:Connect(function(action, data, inv)
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
		-- Flash "Crafted!" message
		local msgGui = Instance.new("ScreenGui")
		msgGui.DisplayOrder = 20
		msgGui.Parent = playerGui

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0, 250, 0, 40)
		label.Position = UDim2.new(0.5, -125, 0.3, 0)
		label.BackgroundTransparency = 1
		label.Text = "Crafted!"
		label.TextColor3 = Color3.fromRGB(100, 255, 100)
		label.TextStrokeTransparency = 0.3
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 28
		label.Parent = msgGui

		local tween = TweenService:Create(label, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, -125, 0.25, 0),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			msgGui:Destroy()
		end)
	end
end)

-- ─── Init ───
buildHotbar()
updateHotbar()
