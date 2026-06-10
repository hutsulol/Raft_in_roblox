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
	Plastic = "rbxassetid://132919988751848",
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
local outputAmount = 0
local smeltStartTime = 0
local smeltDuration = 20

-- Drag state
local dragging = false
local dragItem = nil -- item name string
local dragIcon = nil -- floating ImageLabel
local dragSource = nil -- "inventory", "ore", "fuel", "output"

-- UI refs
local oreSlot, fuelSlot, outputSlot, arrowFill, statusLabel, fuelCountLabel
local invGrid

-- ─── Colors ───
local SLOT_BG = Color3.fromHex("A9D6F7")
local SLOT_FILLED = Color3.fromHex("3F9E3F")
local SLOT_OUTPUT = Color3.fromHex("B07A14")
local PANEL_BG = Color3.fromHex("3A7FD0")
local ARROW_BG = Color3.fromHex("1C4F8F")
local ARROW_FILL_COLOR = Color3.fromRGB(220, 140, 40)
local INV_BG = Color3.fromHex("2F6CB8")

local function closeUI()
	if screenGui then screenGui:Destroy(); screenGui = nil end
	isOpen = false
	dragging = false
	dragItem = nil
	dragSource = nil
	if dragIcon then dragIcon:Destroy(); dragIcon = nil end
end

-- ─── Drag helpers ───
local dragCount = 0

local function startDrag(itemName, count, source)
	if dragging then return end
	dragging = true
	dragItem = itemName
	dragCount = count or 1
	dragSource = source or "inventory"

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
	dragSource = nil
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
		btn.BackgroundColor3 = Color3.fromHex("A9D6F7")
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.AutoButtonColor = true
		btn.LayoutOrder = i
		btn.Parent = invGrid

		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromHex("1C4F8F")
		s.Thickness = 2
		s.Parent = btn

		-- Button is 64 tall with a 14px count label at the bottom (y=48-62),
		-- so the icon is centered within the 48px area above the label.
		local icon = Instance.new("ImageLabel")
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Size = UDim2.new(0, 40, 0, 40)
		icon.Position = UDim2.new(0.5, 0, 0, 24)
		icon.BackgroundTransparency = 1
		icon.Image = RESOURCE_ICONS[stack.name] or ""
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = btn

		local countLbl = Instance.new("TextLabel")
		countLbl.Size = UDim2.new(1, -4, 0, 14)
		countLbl.Position = UDim2.new(0, 2, 1, -16)
		countLbl.BackgroundTransparency = 1
		countLbl.Text = tostring(stack.count)
		countLbl.TextColor3 = Color3.new(1, 1, 1)
		countLbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		countLbl.TextStrokeTransparency = 0.3
		countLbl.TextScaled = true
		countLbl.Font = Enum.Font.GothamBold
		countLbl.Parent = btn

		-- Quick-transfer helper for this stack
		local function quickTransfer()
			if stack.name == "Log" then
				furnaceEvent:FireServer("loadFuel", "Log", stack.count)
			elseif not oreType and not smelting then
				furnaceEvent:FireServer("loadOre", stack.name)
			end
		end

		-- LMB: drag or Shift quick-transfer
		btn.MouseButton1Down:Connect(function()
			if outputReady then return end
			local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shiftHeld then
				quickTransfer()
			else
				startDrag(stack.name, stack.count)
			end
		end)

		-- RMB+Shift: same quick-transfer
		btn.MouseButton2Down:Connect(function()
			if outputReady then return end
			local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shiftHeld then
				quickTransfer()
			end
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
		if outputReady and outputAmount > 0 then
			local outIcon = RESOURCE_ICONS[outputType] or RESOURCE_ICONS.Iron_Ingot
			if icon then icon.Image = outIcon; icon.ImageTransparency = 0 end
			if label then label.Text = "x" .. outputAmount; label.Visible = true end
			outputSlot.BackgroundColor3 = SLOT_OUTPUT
		else
			if icon then icon.Image = ""; icon.ImageTransparency = 1 end
			if label then label.Visible = false end
			outputSlot.BackgroundColor3 = SLOT_BG
		end
	end

	-- Status (only show during smelting, handled in RenderStepped)
	if statusLabel and not smelting then
		statusLabel.Text = ""
	end

	-- Reset arrow when not smelting (except when output is ready - keep it full)
	if arrowFill and not smelting then
		if outputReady then
			arrowFill.Size = UDim2.new(1, 0, 1, 0)
		else
			arrowFill.Size = UDim2.new(0, 0, 1, 0)
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
	s.Color = Color3.fromHex("1C4F8F")
	s.Thickness = 2
	s.Parent = slot

	-- Slots are 70 tall with a 14px label at the bottom (y=52-66), so the
	-- icon is centered within the 52px area above the label.
	local icon = Instance.new("ImageLabel")
	icon.Name = "SlotIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Size = UDim2.new(0, 44, 0, 44)
	icon.Position = UDim2.new(0.5, 0, 0, 26)
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
	label.TextColor3 = Color3.fromRGB(222, 236, 250)
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
	local ms = Instance.new("UIStroke"); ms.Color = Color3.fromHex("1C4F8F"); ms.Thickness = 4; ms.Parent = main

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 42)
	titleBar.BackgroundColor3 = Color3.fromHex("1C4F8F")
	titleBar.BorderSizePixel = 0
	titleBar.Parent = main
	Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)
	local fix = Instance.new("Frame"); fix.Size = UDim2.new(1, 0, 0, 12); fix.Position = UDim2.new(0, 0, 1, -12)
	fix.BackgroundColor3 = Color3.fromHex("1C4F8F"); fix.BorderSizePixel = 0; fix.Parent = titleBar

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -60, 1, 0); titleLbl.Position = UDim2.new(0, 15, 0, 0)
	titleLbl.BackgroundTransparency = 1; titleLbl.Text = "Furnace"; titleLbl.TextColor3 = Color3.new(1, 1, 1)
	titleLbl.TextScaled = true; titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 32, 0, 32); closeBtn.Position = UDim2.new(1, -38, 0.5, -16)
	closeBtn.BackgroundColor3 = Color3.fromHex("FF6B5A"); closeBtn.Text = "X"; closeBtn.TextColor3 = Color3.new(1, 1, 1)
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
	oreSlot.MouseButton1Down:Connect(function()
		if not oreType then return end
		local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		if shiftHeld then
			furnaceEvent:FireServer("removeOre") -- cancels smelting if active
		else
			startDrag(oreType, 1, "ore")
		end
	end)

	local oreTitle = Instance.new("TextLabel")
	oreTitle.Size = UDim2.new(0, 80, 0, 12); oreTitle.Position = UDim2.new(0, 0, 0, 72)
	oreTitle.BackgroundTransparency = 1; oreTitle.Text = "Ore"; oreTitle.TextColor3 = Color3.fromRGB(214, 230, 247)
	oreTitle.TextScaled = true; oreTitle.Font = Enum.Font.Gotham; oreTitle.Parent = content

	-- Fuel slot
	fuelSlot = createSlot(content, UDim2.new(0, 0, 0, 92), UDim2.new(0, 80, 0, 70))
	fuelSlot.MouseButton1Down:Connect(function()
		if fuelCount <= 0 or smelting then return end
		local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		if shiftHeld then
			furnaceEvent:FireServer("removeFuel") -- all
		else
			startDrag("Log", fuelCount, "fuel")
		end
	end)

	local fuelTitle = Instance.new("TextLabel")
	fuelTitle.Size = UDim2.new(0, 80, 0, 12); fuelTitle.Position = UDim2.new(0, 0, 0, 164)
	fuelTitle.BackgroundTransparency = 1; fuelTitle.Text = "Fuel"; fuelTitle.TextColor3 = Color3.fromRGB(214, 230, 247)
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

	-- Output slot
	outputSlot = createSlot(content, UDim2.new(0, 240, 0, 15), UDim2.new(0, 110, 0, 70))
	outputSlot.MouseButton1Down:Connect(function()
		if not outputReady or outputAmount <= 0 then return end
		local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		if shiftHeld then
			furnaceEvent:FireServer("collectOutput") -- all
		else
			startDrag(outputType or "Iron_Ingot", outputAmount, "output")
		end
	end)

	local outTitle = Instance.new("TextLabel")
	outTitle.Size = UDim2.new(0, 110, 0, 12); outTitle.Position = UDim2.new(0, 240, 0, 87)
	outTitle.BackgroundTransparency = 1; outTitle.Text = "Output"; outTitle.TextColor3 = Color3.fromRGB(214, 230, 247)
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
		outputType = state.outputType; outputAmount = state.outputAmount or 0
	else
		oreType = nil; fuelCount = 0; smelting = false; outputReady = false; outputType = nil; outputAmount = 0
	end

	buildUI()
	furnaceEvent:FireServer("getState")
end

-- ─── Events ───
openFurnaceEvent.OnClientEvent:Connect(function(furnaceModel, state)
	openUI(furnaceModel, state)
end)

-- E / Escape closes the furnace UI. Same guard pattern as the chest
-- and workbench: block InventoryUI's deferred E toggle while we tear
-- down, then clear the flag after 0.25 s so later E presses work
-- normally.
UserInputService.InputBegan:Connect(function(input)
	if not isOpen then return end
	if input.KeyCode ~= Enum.KeyCode.E
		and input.KeyCode ~= Enum.KeyCode.Escape then
		return
	end
	_G.SuppressInventoryToggle = true
	closeUI()
	task.delay(0.25, function()
		_G.SuppressInventoryToggle = false
	end)
end)

furnaceEvent.OnClientEvent:Connect(function(action, data, extra1, extra2)
	if action == "stateUpdate" then
		if data then
			oreType = data.oreType; fuelCount = data.fuelCount or 0
			smelting = data.smelting or false; outputReady = data.outputReady or false
			outputType = data.outputType; outputAmount = data.outputAmount or 0
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
			outputType = data.outputType; outputAmount = data.outputAmount or 0
		else
			smelting = false; outputReady = true; oreType = nil; fuelCount = 0
		end
		if arrowFill then arrowFill.Size = UDim2.new(1, 0, 1, 0) end
		updateSlots()

	elseif action == "smeltFailed" then
		smelting = false; oreType = nil; fuelCount = 0; outputReady = false; outputAmount = 0
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
			outputType = data.outputType; outputAmount = data.outputAmount or 0
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
			statusLabel.Text = "Smelting... " .. remaining .. "s"
			statusLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
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
	if not isOpen then cancelDrag(); return end

	if dragSource == "inventory" then
		-- Dropping FROM inventory INTO furnace slots
		-- Drop on ore slot (not during smelting, slot must be empty)
		if oreSlot and isMouseOver(oreSlot) and not oreType and not smelting then
			furnaceEvent:FireServer("loadOre", dragItem)
		-- Drop on fuel slot (allowed during smelting to add more fuel)
		elseif fuelSlot and isMouseOver(fuelSlot) then
			furnaceEvent:FireServer("loadFuel", dragItem, dragCount)
		end
	else
		-- Dropping FROM furnace slot — if not dropped back onto a furnace slot, return to inventory
		local onFurnaceSlot = (oreSlot and isMouseOver(oreSlot))
			or (fuelSlot and isMouseOver(fuelSlot))
			or (outputSlot and isMouseOver(outputSlot))

		if not onFurnaceSlot then
			-- Return items to inventory
			if dragSource == "ore" and oreType then
				furnaceEvent:FireServer("removeOre") -- cancels smelting if active
			elseif dragSource == "fuel" and fuelCount > 0 and not smelting then
				furnaceEvent:FireServer("removeFuel") -- removes all
			elseif dragSource == "output" and outputReady then
				furnaceEvent:FireServer("collectOutput") -- collects all
			end
		end
	end

	cancelDrag()
end)

-- ─── Right-click: take 1 item | Shift+Right-click: take all items ───
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- Escape key closes the furnace UI (needed in first-person where cursor is locked)
	if input.KeyCode == Enum.KeyCode.Escape and isOpen then
		closeUI()
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
	if not isOpen then return end

	local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)

	-- Ore slot (always 1 item, removes ore and cancels smelting if active)
	if oreSlot and isMouseOver(oreSlot) and oreType then
		furnaceEvent:FireServer("removeOre")
		return
	end

	-- Fuel slot
	if fuelSlot and isMouseOver(fuelSlot) and fuelCount > 0 and not smelting then
		if shiftHeld then
			furnaceEvent:FireServer("removeFuel") -- all (no count = all)
		else
			furnaceEvent:FireServer("removeFuel", 1) -- just 1
		end
		return
	end

	-- Output slot
	if outputSlot and isMouseOver(outputSlot) and outputReady and outputAmount > 0 then
		if shiftHeld then
			furnaceEvent:FireServer("collectOutput") -- all
		else
			furnaceEvent:FireServer("collectOutput", 1) -- just 1
		end
		return
	end
end)
