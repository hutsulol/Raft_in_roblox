-- FurnaceUI.client.lua
-- Furnace UI with drag-and-drop from inventory to furnace slots.
-- Inventory displays in stacks of 30 max. Fuel burns 1 every 5s.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local furnaceEvent = ReplicatedStorage:WaitForChild("FurnaceAction")
local openFurnaceEvent = ReplicatedStorage:WaitForChild("OpenFurnace")
local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate")

-- ─── Icons ───
local RESOURCE_ICONS = {
	Log = "rbxassetid://110032041583533",
	Plastic = "rbxassetid://88529166446482",
	Stone = "rbxassetid://134781813180973",
	Iron_Ore = "rbxassetid://73676755288746",
	Iron_Ingot = "rbxassetid://72890243946368",
}

local MAX_STACK = 30

-- ─── State ───
local isOpen = false
local screenGui = nil
local inventory = {}

local oreType = nil
local fuelCount = 0
local smelting = false
local outputReady = false
local outputType = nil
local smeltStartTime = 0
local smeltDuration = 20

-- Drag state
local dragging = false
local dragItem = nil -- {name, count}
local dragIcon = nil -- floating ImageLabel

-- UI refs
local oreSlot, fuelSlot, outputSlot, arrowFill, statusLabel, fuelCountLabel
local smeltBtn, invGrid

-- ─── Colors ───
local SLOT_BG = Color3.fromRGB(60, 60, 65)
local SLOT_FILLED = Color3.fromRGB(70, 105, 70)
local SLOT_OUTPUT = Color3.fromRGB(120, 100, 50)
local PANEL_BG = Color3.fromRGB(45, 45, 50)
local ARROW_BG = Color3.fromRGB(80, 80, 85)
local ARROW_FILL_COLOR = Color3.fromRGB(220, 140, 40)
local INV_BG = Color3.fromRGB(55, 55, 60)

local function closeUI()
	if screenGui then screenGui:Destroy(); screenGui = nil end
	isOpen = false
	dragging = false
	dragItem = nil
	if dragIcon then dragIcon:Destroy(); dragIcon = nil end
end

-- ─── Drag helpers ───
local dragCount = 0

local function startDrag(itemName, count)
	if dragging then return end
	dragging = true
	dragItem = itemName
	dragCount = count or 1

	dragIcon = Instance.new("ImageLabel")
	dragIcon.Size = UDim2.new(0, 44, 0, 44)
	dragIcon.BackgroundTransparency = 1
	dragIcon.Image = RESOURCE_ICONS[itemName] or ""
	dragIcon.ScaleType = Enum.ScaleType.Fit
	dragIcon.ZIndex = 100
	dragIcon.Parent = screenGui

	local mouse = player:GetMouse()
	dragIcon.Position = UDim2.new(0, mouse.X - 22, 0, mouse.Y - 22)
end

local function cancelDrag()
	dragging = false
	dragItem = nil
	if dragIcon then dragIcon:Destroy(); dragIcon = nil end
end

-- Check if mouse is over a GuiObject
local function isMouseOver(guiObj)
	if not guiObj then return false end
	local mouse = player:GetMouse()
	local pos = guiObj.AbsolutePosition
	local size = guiObj.AbsoluteSize
	return mouse.X >= pos.X and mouse.X <= pos.X + size.X
		and mouse.Y >= pos.Y and mouse.Y <= pos.Y + size.Y
end

-- ─── Build inventory grid (stacked at 30 max) ───
local function rebuildInventory()
	if not invGrid then return end
	for _, child in invGrid:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end

	-- Build stacks: split items into MAX_STACK slots
	local stacks = {}
	local order = {}
	for name, count in inventory do
		if count > 0 and typeof(count) == "number" then
			table.insert(order, name)
		end
	end
	table.sort(order)

	for _, name in order do
		local remaining = inventory[name]
		while remaining > 0 do
			local stackSize = math.min(remaining, MAX_STACK)
			table.insert(stacks, {name = name, count = stackSize})
			remaining = remaining - stackSize
		end
	end

	for i, stack in stacks do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 64, 0, 64)
		btn.BackgroundColor3 = Color3.fromRGB(70, 70, 75)
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.AutoButtonColor = true
		btn.LayoutOrder = i
		btn.Parent = invGrid

		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(100, 100, 110)
		s.Thickness = 1
		s.Parent = btn

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(0, 40, 0, 40)
		icon.Position = UDim2.new(0.5, -20, 0, 2)
		icon.BackgroundTransparency = 1
		icon.Image = RESOURCE_ICONS[stack.name] or ""
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = btn

		local countLbl = Instance.new("TextLabel")
		countLbl.Size = UDim2.new(1, -4, 0, 14)
		countLbl.Position = UDim2.new(0, 2, 1, -16)
		countLbl.BackgroundTransparency = 1
		countLbl.Text = tostring(stack.count)
		countLbl.TextColor3 = Color3.fromRGB(220, 220, 220)
		countLbl.TextScaled = true
		countLbl.Font = Enum.Font.GothamBold
		countLbl.Parent = btn

		-- Start drag on mousedown (allowed during smelting for adding fuel)
		btn.MouseButton1Down:Connect(function()
			if outputReady then return end
			startDrag(stack.name, stack.count)
		end)
	end
end

-- ─── Update UI state ───
local function updateSlots()
	if not screenGui then return end

	-- Ore slot
	if oreSlot then
		local icon = oreSlot:FindFirstChild("SlotIcon")
		local label = oreSlot:FindFirstChild("SlotLabel")
		if oreType then
			if icon then icon.Image = RESOURCE_ICONS[oreType] or ""; icon.ImageTransparency = 0 end
			if label then label.Text = oreType:gsub("_", " "); label.Visible = true end
			oreSlot.BackgroundColor3 = SLOT_FILLED
		else
			if icon then icon.Image = ""; icon.ImageTransparency = 1 end
			if label then label.Visible = false end
			oreSlot.BackgroundColor3 = SLOT_BG
		end
	end

	-- Fuel slot
	if fuelSlot then
		local icon = fuelSlot:FindFirstChild("SlotIcon")
		local label = fuelSlot:FindFirstChild("SlotLabel")
		if fuelCount > 0 then
			if icon then icon.Image = RESOURCE_ICONS.Log; icon.ImageTransparency = 0 end
			if label then label.Text = "x" .. fuelCount; label.Visible = true end
			fuelSlot.BackgroundColor3 = SLOT_FILLED
		else
			if icon then icon.Image = ""; icon.ImageTransparency = 1 end
			if label then label.Visible = false end
			fuelSlot.BackgroundColor3 = SLOT_BG
		end
	end

	-- Fuel counter
	if fuelCountLabel then
		if fuelCount > 0 then
			fuelCountLabel.Text = fuelCount .. " wood"
			fuelCountLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		else
			fuelCountLabel.Text = ""
		end
	end

	-- Output slot
	if outputSlot then
		local icon = outputSlot:FindFirstChild("SlotIcon")
		local label = outputSlot:FindFirstChild("SlotLabel")
		if outputReady then
			local outIcon = RESOURCE_ICONS[outputType] or RESOURCE_ICONS.Iron_Ingot
			if icon then icon.Image = outIcon; icon.ImageTransparency = 0 end
			if label then label.Text = "Take"; label.Visible = true end
			outputSlot.BackgroundColor3 = SLOT_OUTPUT
		else
			if icon then icon.Image = ""; icon.ImageTransparency = 1 end
			if label then label.Visible = false end
			outputSlot.BackgroundColor3 = SLOT_BG
		end
	end

	-- Smelt button
	if smeltBtn then
		if smelting then
			smeltBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
			smeltBtn.Text = "Smelting..."
		elseif outputReady then
			smeltBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
			smeltBtn.Text = "Done"
		elseif oreType and fuelCount > 0 then
			smeltBtn.BackgroundColor3 = Color3.fromRGB(200, 120, 30)
			smeltBtn.Text = "Smelt"
		else
			smeltBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
			smeltBtn.Text = "Smelt"
		end
	end

	-- Status
	if statusLabel and not smelting then
		if outputReady then
			statusLabel.Text = "Done! Click output to collect"
			statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		elseif oreType and fuelCount > 0 then
			statusLabel.Text = "Ready - press Smelt"
			statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		elseif not oreType and fuelCount == 0 then
			statusLabel.Text = "Drag items from inventory into slots"
			statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		elseif not oreType then
			statusLabel.Text = "Drag ore into the ore slot"
			statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		else
			statusLabel.Text = "Drag wood into the fuel slot"
			statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		end
	end

	rebuildInventory()
end

-- ─── Create a slot ───
local function createSlot(parent, pos, size)
	local slot = Instance.new("TextButton")
	slot.Size = size
	slot.Position = pos
	slot.BackgroundColor3 = SLOT_BG
	slot.BorderSizePixel = 0
	slot.Text = ""
	slot.AutoButtonColor = false
	slot.Parent = parent

	Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 8)
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(90, 90, 100)
	s.Thickness = 2
	s.Parent = slot

	local icon = Instance.new("ImageLabel")
	icon.Name = "SlotIcon"
	icon.Size = UDim2.new(0, 44, 0, 44)
	icon.Position = UDim2.new(0.5, -22, 0, 4)
	icon.BackgroundTransparency = 1
	icon.Image = ""
	icon.ImageTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = slot

	local label = Instance.new("TextLabel")
	label.Name = "SlotLabel"
	label.Size = UDim2.new(1, -6, 0, 14)
	label.Position = UDim2.new(0, 3, 1, -18)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.Visible = false
	label.TextColor3 = Color3.fromRGB(180, 180, 180)
	label.TextScaled = true
	label.Font = Enum.Font.Gotham
	label.Parent = slot

	return slot
end

local function buildUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "FurnaceGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 60
	screenGui.Parent = playerGui

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.new(0, 460, 0, 420)
	main.Position = UDim2.new(0.5, -230, 0.5, -210)
	main.BackgroundColor3 = PANEL_BG
	main.BorderSizePixel = 0
	main.Parent = screenGui
	Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
	local ms = Instance.new("UIStroke"); ms.Color = Color3.fromRGB(80, 80, 90); ms.Thickness = 2; ms.Parent = main

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 42)
	titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	titleBar.BorderSizePixel = 0
	titleBar.Parent = main
	Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)
	local fix = Instance.new("Frame"); fix.Size = UDim2.new(1, 0, 0, 12); fix.Position = UDim2.new(0, 0, 1, -12)
	fix.BackgroundColor3 = Color3.fromRGB(35, 35, 40); fix.BorderSizePixel = 0; fix.Parent = titleBar

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -60, 1, 0); titleLbl.Position = UDim2.new(0, 15, 0, 0)
	titleLbl.BackgroundTransparency = 1; titleLbl.Text = "Furnace"; titleLbl.TextColor3 = Color3.new(1, 1, 1)
	titleLbl.TextScaled = true; titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 32, 0, 32); closeBtn.Position = UDim2.new(1, -38, 0.5, -16)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50); closeBtn.Text = "X"; closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.TextScaled = true; closeBtn.Font = Enum.Font.GothamBold; closeBtn.BorderSizePixel = 0; closeBtn.Parent = titleBar
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
	closeBtn.MouseButton1Click:Connect(closeUI)

	-- ═══ Furnace area ═══
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -24, 0, 170)
	content.Position = UDim2.new(0, 12, 0, 48)
	content.BackgroundTransparency = 1
	content.Parent = main

	-- Ore slot
	oreSlot = createSlot(content, UDim2.new(0, 0, 0, 0), UDim2.new(0, 80, 0, 70))
	-- Click loaded ore to return to inventory
	oreSlot.MouseButton1Click:Connect(function()
		if smelting or outputReady then return end
		if oreType then furnaceEvent:FireServer("removeOre") end
	end)

	local oreTitle = Instance.new("TextLabel")
	oreTitle.Size = UDim2.new(0, 80, 0, 12); oreTitle.Position = UDim2.new(0, 0, 0, 72)
	oreTitle.BackgroundTransparency = 1; oreTitle.Text = "Ore"; oreTitle.TextColor3 = Color3.fromRGB(140, 140, 140)
	oreTitle.TextScaled = true; oreTitle.Font = Enum.Font.Gotham; oreTitle.Parent = content

	-- Fuel slot
	fuelSlot = createSlot(content, UDim2.new(0, 0, 0, 92), UDim2.new(0, 80, 0, 70))
	-- Click fuel to remove 1 back to inventory
	fuelSlot.MouseButton1Click:Connect(function()
		if smelting or outputReady then return end
		if fuelCount > 0 then furnaceEvent:FireServer("removeFuel") end
	end)

	local fuelTitle = Instance.new("TextLabel")
	fuelTitle.Size = UDim2.new(0, 80, 0, 12); fuelTitle.Position = UDim2.new(0, 0, 0, 164)
	fuelTitle.BackgroundTransparency = 1; fuelTitle.Text = "Fuel"; fuelTitle.TextColor3 = Color3.fromRGB(140, 140, 140)
	fuelTitle.TextScaled = true; fuelTitle.Font = Enum.Font.Gotham; fuelTitle.Parent = content

	-- Fuel counter
	fuelCountLabel = Instance.new("TextLabel")
	fuelCountLabel.Size = UDim2.new(0, 80, 0, 14); fuelCountLabel.Position = UDim2.new(0, 85, 0, 130)
	fuelCountLabel.BackgroundTransparency = 1; fuelCountLabel.Text = ""
	fuelCountLabel.TextColor3 = Color3.fromRGB(150, 150, 150); fuelCountLabel.TextScaled = true
	fuelCountLabel.Font = Enum.Font.GothamBold; fuelCountLabel.TextXAlignment = Enum.TextXAlignment.Left
	fuelCountLabel.Parent = content

	-- Arrow
	local arrowBg = Instance.new("Frame")
	arrowBg.Size = UDim2.new(0, 110, 0, 36); arrowBg.Position = UDim2.new(0, 105, 0, 30)
	arrowBg.BackgroundColor3 = ARROW_BG; arrowBg.BorderSizePixel = 0; arrowBg.ClipsDescendants = true; arrowBg.Parent = content
	Instance.new("UICorner", arrowBg).CornerRadius = UDim.new(0, 6)

	arrowFill = Instance.new("Frame")
	arrowFill.Size = UDim2.new(0, 0, 1, 0); arrowFill.BackgroundColor3 = ARROW_FILL_COLOR
	arrowFill.BorderSizePixel = 0; arrowFill.Parent = arrowBg
	Instance.new("UICorner", arrowFill).CornerRadius = UDim.new(0, 6)

	local arrowLbl = Instance.new("TextLabel")
	arrowLbl.Size = UDim2.new(1, 0, 1, 0); arrowLbl.BackgroundTransparency = 1; arrowLbl.Text = ">>>"
	arrowLbl.TextColor3 = Color3.fromRGB(220, 220, 220); arrowLbl.TextScaled = true
	arrowLbl.Font = Enum.Font.GothamBold; arrowLbl.ZIndex = 2; arrowLbl.Parent = arrowBg

	-- Smelt button
	smeltBtn = Instance.new("TextButton")
	smeltBtn.Size = UDim2.new(0, 110, 0, 32); smeltBtn.Position = UDim2.new(0, 105, 0, 74)
	smeltBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100); smeltBtn.Text = "Smelt"
	smeltBtn.TextColor3 = Color3.new(1, 1, 1); smeltBtn.TextScaled = true; smeltBtn.Font = Enum.Font.GothamBold
	smeltBtn.BorderSizePixel = 0; smeltBtn.Parent = content
	Instance.new("UICorner", smeltBtn).CornerRadius = UDim.new(0, 8)
	smeltBtn.MouseButton1Click:Connect(function()
		if smelting or outputReady then return end
		if not oreType or fuelCount <= 0 then return end
		furnaceEvent:FireServer("startSmelt")
	end)

	-- Output slot
	outputSlot = createSlot(content, UDim2.new(0, 240, 0, 15), UDim2.new(0, 110, 0, 70))
	outputSlot.MouseButton1Click:Connect(function()
		if outputReady then furnaceEvent:FireServer("collectOutput") end
	end)

	local outTitle = Instance.new("TextLabel")
	outTitle.Size = UDim2.new(0, 110, 0, 12); outTitle.Position = UDim2.new(0, 240, 0, 87)
	outTitle.BackgroundTransparency = 1; outTitle.Text = "Output"; outTitle.TextColor3 = Color3.fromRGB(140, 140, 140)
	outTitle.TextScaled = true; outTitle.Font = Enum.Font.Gotham; outTitle.Parent = content

	-- ═══ Status ═══
	statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -24, 0, 18); statusLabel.Position = UDim2.new(0, 12, 0, 220)
	statusLabel.BackgroundTransparency = 1; statusLabel.Text = "Drag items from inventory into slots"
	statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150); statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.GothamBold; statusLabel.Parent = main

	-- ═══ Inventory section ═══
	local invTitle = Instance.new("TextLabel")
	invTitle.Size = UDim2.new(1, -24, 0, 18); invTitle.Position = UDim2.new(0, 12, 0, 244)
	invTitle.BackgroundTransparency = 1; invTitle.Text = "Inventory"; invTitle.TextColor3 = Color3.fromRGB(200, 200, 200)
	invTitle.TextScaled = true; invTitle.Font = Enum.Font.GothamBold; invTitle.TextXAlignment = Enum.TextXAlignment.Left
	invTitle.Parent = main

	local invFrame = Instance.new("ScrollingFrame")
	invFrame.Size = UDim2.new(1, -24, 0, 148); invFrame.Position = UDim2.new(0, 12, 0, 264)
	invFrame.BackgroundColor3 = INV_BG; invFrame.BorderSizePixel = 0; invFrame.ClipsDescendants = true
	invFrame.ScrollBarThickness = 6; invFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	invFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	invFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	invFrame.Parent = main
	Instance.new("UICorner", invFrame).CornerRadius = UDim.new(0, 8)

	invGrid = Instance.new("Frame")
	invGrid.Size = UDim2.new(1, -12, 0, 0); invGrid.Position = UDim2.new(0, 6, 0, 4)
	invGrid.BackgroundTransparency = 1; invGrid.AutomaticSize = Enum.AutomaticSize.Y
	invGrid.Parent = invFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 64, 0, 64)
	gridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = invGrid

	updateSlots()
end

-- ─── Open ───
local function openUI(furnaceModel, state)
	if isOpen then closeUI() end
	isOpen = true

	if state then
		oreType = state.oreType; fuelCount = state.fuelCount or 0
		smelting = state.smelting or false; outputReady = state.outputReady or false
		outputType = state.outputType
	else
		oreType = nil; fuelCount = 0; smelting = false; outputReady = false; outputType = nil
	end

	buildUI()
	furnaceEvent:FireServer("getState")
end

-- ─── Events ───
openFurnaceEvent.OnClientEvent:Connect(function(furnaceModel, state)
	openUI(furnaceModel, state)
end)

furnaceEvent.OnClientEvent:Connect(function(action, data, extra1, extra2)
	if action == "stateUpdate" then
		if data then
			oreType = data.oreType; fuelCount = data.fuelCount or 0
			smelting = data.smelting or false; outputReady = data.outputReady or false
			outputType = data.outputType
		end
		updateSlots()

	elseif action == "smeltStart" then
		smelting = true; smeltDuration = data or 20; smeltStartTime = tick()
		updateSlots()

	elseif action == "fuelBurn" then
		fuelCount = data or 0
		updateSlots()

	elseif action == "smeltDone" then
		if data then
			oreType = data.oreType; fuelCount = data.fuelCount or 0
			smelting = data.smelting or false; outputReady = data.outputReady or false
			outputType = data.outputType
		else
			smelting = false; outputReady = true; oreType = nil; fuelCount = 0
		end
		if arrowFill then arrowFill.Size = UDim2.new(1, 0, 1, 0) end
		updateSlots()

	elseif action == "smeltFailed" then
		smelting = false; oreType = nil; fuelCount = 0; outputReady = false
		if arrowFill then arrowFill.Size = UDim2.new(0, 0, 1, 0) end
		updateSlots()
		if statusLabel then
			statusLabel.Text = "Smelting failed! Ran out of fuel"
			statusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		end

	elseif action == "smeltError" then
		if statusLabel then
			statusLabel.Text = data or "Cannot smelt this item"
			statusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		end

	elseif action == "fullState" then
		if data then
			oreType = data.oreType; fuelCount = data.fuelCount or 0
			smelting = data.smelting or false; outputReady = data.outputReady or false
			outputType = data.outputType
		end
		if smelting and extra1 and extra2 then
			smeltDuration = extra2; smeltStartTime = tick() - extra1
		end
		updateSlots()
	end
end)

inventoryEvent.OnClientEvent:Connect(function(inv)
	inventory = inv
	if isOpen then updateSlots() end
end)

-- ─── Drag: follow mouse ───
RunService.RenderStepped:Connect(function()
	-- Progress bar
	if isOpen and smelting and arrowFill then
		local elapsed = tick() - smeltStartTime
		local progress = math.clamp(elapsed / smeltDuration, 0, 1)
		arrowFill.Size = UDim2.new(progress, 0, 1, 0)
		if statusLabel then
			local remaining = math.max(0, math.ceil(smeltDuration - elapsed))
			statusLabel.Text = "Smelting... " .. remaining .. "s | Fuel: " .. fuelCount
			statusLabel.TextColor3 = fuelCount <= 1 and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 200, 80)
		end
	end

	-- Move drag icon
	if dragging and dragIcon then
		local mouse = player:GetMouse()
		dragIcon.Position = UDim2.new(0, mouse.X - 22, 0, mouse.Y - 22)

		-- Highlight slot under cursor
		if oreSlot then
			local oreStroke = oreSlot:FindFirstChildWhichIsA("UIStroke")
			if oreStroke then
				if isMouseOver(oreSlot) and not oreType then
					oreStroke.Color = Color3.fromRGB(100, 255, 100); oreStroke.Thickness = 3
				else
					oreStroke.Color = Color3.fromRGB(90, 90, 100); oreStroke.Thickness = 2
				end
			end
		end
		if fuelSlot then
			local fuelStroke = fuelSlot:FindFirstChildWhichIsA("UIStroke")
			if fuelStroke then
				if isMouseOver(fuelSlot) then
					fuelStroke.Color = Color3.fromRGB(100, 255, 100); fuelStroke.Thickness = 3
				else
					fuelStroke.Color = Color3.fromRGB(90, 90, 100); fuelStroke.Thickness = 2
				end
			end
		end
	end
end)

-- ─── Drop: mouse release ───
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if not dragging or not dragItem then return end

	if isOpen and not outputReady then
		-- Drop on ore slot (not during smelting)
		if oreSlot and isMouseOver(oreSlot) and not oreType and not smelting then
			furnaceEvent:FireServer("loadOre", dragItem)
		-- Drop on fuel slot (allowed during smelting to add more fuel)
		elseif fuelSlot and isMouseOver(fuelSlot) then
			furnaceEvent:FireServer("loadFuel", dragItem, dragCount)
		end
	end

	cancelDrag()
end)
