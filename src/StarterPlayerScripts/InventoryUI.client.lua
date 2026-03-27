local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate")
local inventoryCraftEvent = ReplicatedStorage:WaitForChild("InventoryCraft")

local LOG_ICON = "rbxassetid://110032041583533"

local inventory = {Log = 0}
local recipes = {}
local selectedRecipe = nil
local isOpen = false
local screenGui = nil
local hotbarGui = nil

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
	equipped = Color3.fromRGB(200, 170, 100),
}

local HOTBAR_SLOTS = 8
local GRID_SLOTS = 20
local TOTAL_SLOTS = HOTBAR_SLOTS + GRID_SLOTS
local SLOT_SIZE = 60
local SLOT_PAD = 6
local COLS = 5

-- ─── Unified Slot Data ───
-- Slots 1..8 = hotbar, slots 9..28 = inventory grid
local slotData = {}
local slotsInitialized = false

-- ─── Drag ───
local dragState = {
	active = false,
	sourceSlot = nil,
	data = nil,
	ghost = nil,
	ghostGui = nil,
	didDrag = false,
	startPos = nil,
	splitMode = false, -- right-click: move only 1 item
}
local DRAG_THRESHOLD = 5

-- ─── Helpers ───

local function canAfford(recipe)
	if not recipe or not recipe.costs then return false end
	for item, amount in recipe.costs do
		if (inventory[item] or 0) < amount then return false end
	end
	return true
end

local function getToolList()
	local tools = {}
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character
	if backpack then
		for _, t in backpack:GetChildren() do
			if t:IsA("Tool") then table.insert(tools, t) end
		end
	end
	if char then
		for _, t in char:GetChildren() do
			if t:IsA("Tool") then table.insert(tools, t) end
		end
	end
	return tools
end

local function findEmptySlot(startIdx, endIdx)
	for i = startIdx, endIdx do
		if not slotData[i] then return i end
	end
	return nil
end

local function findItemSlot(itemType, itemName)
	for i = 1, TOTAL_SLOTS do
		if slotData[i] and slotData[i].type == itemType and slotData[i].name == itemName then
			return i
		end
	end
	return nil
end

local MAX_STACK = 30

-- Distribute logs across slots respecting MAX_STACK
local function distributeResource(name, totalCount, icon)
	-- Find all existing slots with this resource
	local existingSlots = {}
	for i = 1, TOTAL_SLOTS do
		if slotData[i] and slotData[i].type == "resource" and slotData[i].name == name then
			table.insert(existingSlots, i)
		end
	end

	local remaining = totalCount

	-- Fill existing slots first
	for _, idx in existingSlots do
		if remaining <= 0 then
			slotData[idx] = nil
		else
			local amount = math.min(remaining, MAX_STACK)
			slotData[idx].count = amount
			remaining = remaining - amount
		end
	end

	-- If there's still remaining, create new slots
	while remaining > 0 do
		local empty = findEmptySlot(1, HOTBAR_SLOTS) or findEmptySlot(HOTBAR_SLOTS + 1, TOTAL_SLOTS)
		if not empty then break end -- inventory full
		local amount = math.min(remaining, MAX_STACK)
		slotData[empty] = {type = "resource", name = name, count = amount, icon = icon}
		remaining = remaining - amount
	end
end

local function rebuildSlotData()
	local tools = getToolList()
	local logCount = inventory.Log or 0

	if not slotsInitialized then
		for i = 1, TOTAL_SLOTS do slotData[i] = nil end

		if logCount > 0 then
			distributeResource("Log", logCount, LOG_ICON)
		end

		local slot = 2
		for _, tool in tools do
			if slot > HOTBAR_SLOTS then break end
			-- Skip if slot already taken by resource
			if slotData[slot] then
				slot = slot + 1
			end
			if slot > HOTBAR_SLOTS then break end
			local toolIcon = (tool.TextureId ~= "" and tool.TextureId) or LOG_ICON
			slotData[slot] = {type = "tool", name = tool.Name, toolName = tool.Name, icon = toolIcon}
			slot = slot + 1
		end

		slotsInitialized = true
		return
	end

	-- Update logs: distribute total across existing + new slots
	if logCount > 0 then
		distributeResource("Log", logCount, LOG_ICON)
	else
		-- Remove all log slots
		for i = 1, TOTAL_SLOTS do
			if slotData[i] and slotData[i].type == "resource" and slotData[i].name == "Log" then
				slotData[i] = nil
			end
		end
	end

	-- Remove tools that no longer exist
	local currentTools = {}
	for _, tool in tools do currentTools[tool.Name] = tool end

	for i = 1, TOTAL_SLOTS do
		if slotData[i] and slotData[i].type == "tool" then
			if not currentTools[slotData[i].toolName] then
				slotData[i] = nil
			end
		end
	end

	-- Add new tools
	for _, tool in tools do
		if not findItemSlot("tool", tool.Name) then
			local toolIcon = (tool.TextureId ~= "" and tool.TextureId) or LOG_ICON
			local entry = {type = "tool", name = tool.Name, toolName = tool.Name, icon = toolIcon}
			local empty = findEmptySlot(1, HOTBAR_SLOTS) or findEmptySlot(HOTBAR_SLOTS + 1, TOTAL_SLOTS)
			if empty then slotData[empty] = entry end
		end
	end
end

-- ─── Rendering ───

local function clearSlotUI(slot)
	for _, child in slot:GetChildren() do
		if child:IsA("ImageLabel") or (child:IsA("TextLabel") and child.Name ~= "") then
			child:Destroy()
		end
	end
end

local function renderSlot(slot, data)
	clearSlotUI(slot)
	if not data then return end

	local img = Instance.new("ImageLabel")
	img.Name = "ItemIcon"
	img.Size = UDim2.new(0.7, 0, 0.7, 0)
	img.Position = UDim2.new(0.15, 0, 0.05, 0)
	img.BackgroundTransparency = 1
	img.Image = data.icon or ""
	img.ScaleType = Enum.ScaleType.Fit
	img.Parent = slot

	if data.count and data.count > 0 then
		local count = Instance.new("TextLabel")
		count.Name = "ItemCount"
		count.Size = UDim2.new(0, 25, 0, 16)
		count.Position = UDim2.new(1, -27, 1, -18)
		count.BackgroundTransparency = 1
		count.Text = tostring(data.count)
		count.TextColor3 = COLORS.lightText
		count.TextStrokeTransparency = 0.3
		count.TextStrokeColor3 = Color3.new(0, 0, 0)
		count.Font = Enum.Font.GothamBold
		count.TextSize = 13
		count.TextXAlignment = Enum.TextXAlignment.Right
		count.Parent = slot
	end
end

function renderAllSlots()
	local char = player.Character

	-- Render hotbar (slots 1-8)
	if hotbarGui then
		local bar = hotbarGui:FindFirstChild("Hotbar")
		if bar then
			for i = 1, HOTBAR_SLOTS do
				local slot = bar:FindFirstChild("HotbarSlot_" .. i)
				if slot then
					renderSlot(slot, slotData[i])
					local data = slotData[i]
					if data and data.type == "tool" and char then
						local isEquipped = false
						for _, t in char:GetChildren() do
							if t:IsA("Tool") and t.Name == data.toolName then isEquipped = true break end
						end
						slot.BackgroundColor3 = isEquipped and COLORS.equipped or COLORS.slotBg
					else
						slot.BackgroundColor3 = COLORS.slotBg
					end
				end
			end
		end
	end

	-- Render inventory grid (slots 9-28)
	if screenGui then
		local grid = screenGui:FindFirstChild("InventoryGrid", true)
		if grid then
			for i = 1, GRID_SLOTS do
				local slot = grid:FindFirstChild("Slot_" .. i)
				if slot then
					renderSlot(slot, slotData[HOTBAR_SLOTS + i])
				end
			end
		end

		local resCount = screenGui:FindFirstChild("ResCount", true)
		if resCount then
			resCount.Text = tostring(inventory.Log or 0)
		end
	end
end

-- ─── Drag & Drop ───

local function beginDragPending(slotIndex, data, mousePos, isSplit)
	if not data then return end
	dragState.sourceSlot = slotIndex
	dragState.data = data
	dragState.startPos = mousePos
	dragState.active = false
	dragState.didDrag = false
	dragState.splitMode = isSplit or false
end

local function activateDrag(mousePos)
	if dragState.active then return end
	dragState.active = true
	dragState.didDrag = true

	local data = dragState.data
	local ghostGui = Instance.new("ScreenGui")
	ghostGui.Name = "DragGhost"
	ghostGui.DisplayOrder = 100
	ghostGui.IgnoreGuiInset = true
	ghostGui.Parent = playerGui

	local ghost = Instance.new("ImageLabel")
	ghost.Size = UDim2.new(0, SLOT_SIZE - 8, 0, SLOT_SIZE - 8)
	ghost.Position = UDim2.new(0, mousePos.X - (SLOT_SIZE - 8) / 2, 0, mousePos.Y - (SLOT_SIZE - 8) / 2)
	ghost.BackgroundTransparency = 1
	ghost.Image = data.icon or ""
	ghost.ScaleType = Enum.ScaleType.Fit
	ghost.ImageTransparency = 0.3
	ghost.Parent = ghostGui

	local displayCount = (dragState.splitMode and 1) or (data.count)
	if displayCount and displayCount > 0 then
		local cl = Instance.new("TextLabel")
		cl.Size = UDim2.new(0, 25, 0, 16)
		cl.Position = UDim2.new(1, -25, 1, -16)
		cl.BackgroundTransparency = 1
		cl.Text = tostring(displayCount)
		cl.TextColor3 = COLORS.lightText
		cl.TextStrokeTransparency = 0.3
		cl.TextStrokeColor3 = Color3.new(0, 0, 0)
		cl.Font = Enum.Font.GothamBold
		cl.TextSize = 13
		cl.TextXAlignment = Enum.TextXAlignment.Right
		cl.Parent = ghost
	end

	dragState.ghost = ghost
	dragState.ghostGui = ghostGui
end

local function updateDragPosition(mousePos)
	if dragState.startPos and not dragState.active and dragState.data then
		local dx = mousePos.X - dragState.startPos.X
		local dy = mousePos.Y - dragState.startPos.Y
		if math.sqrt(dx * dx + dy * dy) >= DRAG_THRESHOLD then
			activateDrag(mousePos)
		end
	end
	if dragState.active and dragState.ghost then
		dragState.ghost.Position = UDim2.new(0, mousePos.X - (SLOT_SIZE - 8) / 2, 0, mousePos.Y - (SLOT_SIZE - 8) / 2)
	end
end

local function findSlotUnderMouse(mousePos)
	-- GetMouseLocation() includes the GUI inset, AbsolutePosition does not
	local inset = GuiService:GetGuiInset()
	local mx = mousePos.X
	local my = mousePos.Y - inset.Y

	-- Check hotbar slots (1-8)
	if hotbarGui then
		local bar = hotbarGui:FindFirstChild("Hotbar")
		if bar then
			for i = 1, HOTBAR_SLOTS do
				local slot = bar:FindFirstChild("HotbarSlot_" .. i)
				if slot then
					local p = slot.AbsolutePosition
					local s = slot.AbsoluteSize
					if mx >= p.X and mx <= p.X + s.X and my >= p.Y and my <= p.Y + s.Y then
						return i
					end
				end
			end
		end
	end

	-- Check inventory grid slots (9-28)
	if screenGui then
		local grid = screenGui:FindFirstChild("InventoryGrid", true)
		if grid then
			for i = 1, GRID_SLOTS do
				local slot = grid:FindFirstChild("Slot_" .. i)
				if slot then
					local p = slot.AbsolutePosition
					local s = slot.AbsoluteSize
					if mx >= p.X and mx <= p.X + s.X and my >= p.Y and my <= p.Y + s.Y then
						return HOTBAR_SLOTS + i
					end
				end
			end
		end
	end

	return nil
end

local function cancelDrag()
	if dragState.ghostGui then dragState.ghostGui:Destroy() end
	dragState.active = false
	dragState.sourceSlot = nil
	dragState.data = nil
	dragState.ghost = nil
	dragState.ghostGui = nil
	dragState.startPos = nil
end

local function endDrag(mousePos)
	if not dragState.active then
		cancelDrag()
		return
	end

	local targetSlot = findSlotUnderMouse(mousePos)
	local srcSlot = dragState.sourceSlot
	local isSplit = dragState.splitMode

	if targetSlot and targetSlot ~= srcSlot then
		local srcData = slotData[srcSlot]
		local dstData = slotData[targetSlot]

		if isSplit and srcData and srcData.type == "resource" and srcData.count and srcData.count > 1 then
			-- Right-click split: move exactly 1 to target
			if dstData and dstData.type == "resource" and dstData.name == srcData.name then
				if dstData.count < MAX_STACK then
					dstData.count = dstData.count + 1
					srcData.count = srcData.count - 1
				end
			elseif not dstData then
				slotData[targetSlot] = {
					type = srcData.type,
					name = srcData.name,
					count = 1,
					icon = srcData.icon,
				}
				srcData.count = srcData.count - 1
			end
		elseif srcData and dstData
			and srcData.type == "resource" and dstData.type == "resource"
			and srcData.name == dstData.name then
			-- Left-click same resource: stack them (up to MAX_STACK)
			local space = MAX_STACK - dstData.count
			if space > 0 then
				local toMove = math.min(srcData.count, space)
				dstData.count = dstData.count + toMove
				srcData.count = srcData.count - toMove
				if srcData.count <= 0 then
					slotData[srcSlot] = nil
				end
			else
				-- Target full: swap
				slotData[targetSlot] = srcData
				slotData[srcSlot] = dstData
			end
		else
			-- Different items or tools: swap
			slotData[targetSlot] = srcData
			slotData[srcSlot] = dstData
		end
	end

	cancelDrag()
	dragState.didDrag = true
	renderAllSlots()
end

-- ─── Equip ───

local function equipToolByName(toolName)
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	for _, t in char:GetChildren() do
		if t:IsA("Tool") and t.Name == toolName then
			humanoid:UnequipTools()
			return
		end
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, t in backpack:GetChildren() do
			if t:IsA("Tool") and t.Name == toolName then
				humanoid:EquipTool(t)
				return
			end
		end
	end
end

-- ─── UI Update ───

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
	rebuildSlotData()
	renderAllSlots()
	updateCraftPanel()
end

-- ─── Close ───

local function closeUI()
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	isOpen = false
	selectedRecipe = nil
	if hotbarGui then hotbarGui.DisplayOrder = 5 end
end

-- ─── Build Hotbar ───

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
		local slot = Instance.new("TextButton")
		slot.Name = "HotbarSlot_" .. i
		slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		slot.Position = UDim2.new(0, SLOT_PAD + (i - 1) * (SLOT_SIZE + SLOT_PAD), 0, SLOT_PAD)
		slot.BackgroundColor3 = COLORS.slotBg
		slot.BackgroundTransparency = 0.1
		slot.BorderSizePixel = 0
		slot.Text = ""
		slot.AutoButtonColor = false
		slot.Parent = bar

		local slotCorner = Instance.new("UICorner")
		slotCorner.CornerRadius = UDim.new(0, 6)
		slotCorner.Parent = slot

		local slotStroke = Instance.new("UIStroke")
		slotStroke.Color = COLORS.slotBorder
		slotStroke.Thickness = 1.5
		slotStroke.Parent = slot

		local slotIndex = i

		slot.MouseButton1Down:Connect(function()
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[slotIndex]
			if data then
				beginDragPending(slotIndex, data, mousePos, false)
			end
		end)

		slot.MouseButton2Down:Connect(function()
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[slotIndex]
			if data and data.type == "resource" and data.count and data.count > 1 then
				beginDragPending(slotIndex, data, mousePos, true)
			end
		end)

		slot.MouseButton1Click:Connect(function()
			if dragState.didDrag then
				dragState.didDrag = false
				return
			end
			local data = slotData[slotIndex]
			if data and data.type == "tool" then
				equipToolByName(data.toolName)
				task.wait(0.1)
				renderAllSlots()
			end
		end)
	end
end

-- ─── Build Inventory UI ───

local function buildUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "InventoryGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui

	local gridWidth = COLS * (SLOT_SIZE + SLOT_PAD) + SLOT_PAD
	local gridHeight = 4 * (SLOT_SIZE + SLOT_PAD) + SLOT_PAD
	local panelWidth = gridWidth + 30
	local panelHeight = gridHeight + 70

	local centerPanel = Instance.new("Frame")
	centerPanel.Name = "CenterPanel"
	centerPanel.Size = UDim2.new(0, panelWidth, 0, panelHeight)
	centerPanel.Position = UDim2.new(0.5, -panelWidth / 2, 0.5, -panelHeight / 2 - 50)
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

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, 10, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "Inventory"
	title.TextColor3 = COLORS.titleText
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = centerPanel

	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -30, 0, 2)
	sep.Position = UDim2.new(0, 15, 0, 42)
	sep.BackgroundColor3 = COLORS.separator
	sep.BorderSizePixel = 0
	sep.Parent = centerPanel

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

	-- Inventory grid (these are slots 9-28)
	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "InventoryGrid"
	gridFrame.Size = UDim2.new(0, gridWidth, 0, gridHeight)
	gridFrame.Position = UDim2.new(0.5, -gridWidth / 2, 0, 52)
	gridFrame.BackgroundTransparency = 1
	gridFrame.Parent = centerPanel

	for i = 1, GRID_SLOTS do
		local row = math.floor((i - 1) / COLS)
		local col = (i - 1) % COLS

		local slot = Instance.new("TextButton")
		slot.Name = "Slot_" .. i
		slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		slot.Position = UDim2.new(0, SLOT_PAD + col * (SLOT_SIZE + SLOT_PAD), 0, SLOT_PAD + row * (SLOT_SIZE + SLOT_PAD))
		slot.BackgroundColor3 = COLORS.slotBg
		slot.BackgroundTransparency = 0.05
		slot.BorderSizePixel = 0
		slot.Text = ""
		slot.AutoButtonColor = false
		slot.Parent = gridFrame

		local slotCorner = Instance.new("UICorner")
		slotCorner.CornerRadius = UDim.new(0, 5)
		slotCorner.Parent = slot

		local slotStroke = Instance.new("UIStroke")
		slotStroke.Color = COLORS.slotBorder
		slotStroke.Thickness = 1.5
		slotStroke.Parent = slot

		local globalIdx = HOTBAR_SLOTS + i

		slot.MouseButton1Down:Connect(function()
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[globalIdx]
			if data then
				beginDragPending(globalIdx, data, mousePos, false)
			end
		end)

		slot.MouseButton2Down:Connect(function()
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[globalIdx]
			if data and data.type == "resource" and data.count and data.count > 1 then
				beginDragPending(globalIdx, data, mousePos, true)
			end
		end)
	end

	-- ─── Left Crafting Panel ───
	local craftPanelWidth = 200
	local craftPanel = Instance.new("Frame")
	craftPanel.Name = "CraftPanel"
	craftPanel.Size = UDim2.new(0, craftPanelWidth, 0, panelHeight)
	craftPanel.Position = UDim2.new(0.5, -panelWidth / 2 - craftPanelWidth - 10, 0.5, -panelHeight / 2 - 50)
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

	local craftSep = Instance.new("Frame")
	craftSep.Size = UDim2.new(1, -20, 0, 2)
	craftSep.Position = UDim2.new(0, 10, 0, 38)
	craftSep.BackgroundColor3 = COLORS.panelBorder
	craftSep.BorderSizePixel = 0
	craftSep.Parent = craftPanel

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

	for idx, recipe in recipes do
		local btn = Instance.new("TextButton")
		btn.Name = "Recipe_" .. recipe.name
		btn.Size = UDim2.new(1, 0, 0, 45)
		btn.BackgroundColor3 = COLORS.craftItemBg
		btn.Text = ""
		btn.BorderSizePixel = 0
		btn.LayoutOrder = idx
		btn.AutoButtonColor = false
		btn.Parent = craftList
		btn:SetAttribute("RecipeName", recipe.name)

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn

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

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(0, 32, 0, 32)
		icon.Position = UDim2.new(0, 6, 0.5, -16)
		icon.BackgroundTransparency = 1
		icon.Image = recipe.icon or ""
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = btn

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

	-- Close button
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

	-- Raise hotbar above inventory
	if hotbarGui then hotbarGui.DisplayOrder = 15 end

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

local numberKeys = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E then
		toggleInventory()
	end
	local slotNum = numberKeys[input.KeyCode]
	if slotNum then
		local data = slotData[slotNum]
		if data and data.type == "tool" then
			equipToolByName(data.toolName)
			task.wait(0.1)
			renderAllSlots()
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		if dragState.startPos then
			updateDragPosition(UserInputService:GetMouseLocation())
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.Touch then
		if dragState.active or dragState.startPos then
			endDrag(UserInputService:GetMouseLocation())
		end
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
		if inv then inventory = inv end
		if isOpen then
			closeUI()
			isOpen = true
			buildUI()
		end
	elseif action == "success" then
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
		tween.Completed:Connect(function() msgGui:Destroy() end)
	end
end)

-- ─── Init ───
rebuildSlotData()
buildHotbar()
renderAllSlots()

local backpack = player:WaitForChild("Backpack")
backpack.ChildAdded:Connect(function() task.wait(0.1) updateUI() end)
backpack.ChildRemoved:Connect(function() task.wait(0.1) updateUI() end)

player.CharacterAdded:Connect(function(char)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then task.wait(0.1) updateUI() end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then task.wait(0.1) updateUI() end
	end)
end)

if player.Character then
	player.Character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then task.wait(0.1) updateUI() end
	end)
	player.Character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then task.wait(0.1) updateUI() end
	end)
end
