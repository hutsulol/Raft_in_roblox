-- FurnaceUI.client.lua
-- Furnace UI with inventory transfer. Click a slot to select it, then click
-- an inventory item to place it. Fuel burns visually during smelting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

local selectedSlot = nil -- "ore" or "fuel" or nil

-- UI refs
local oreSlot, fuelSlot, outputSlot, arrowFill, statusLabel, fuelCountLabel
local smeltBtn, invGrid, selectedIndicator

-- ─── Colors ───
local SLOT_BG = Color3.fromRGB(60, 60, 65)
local SLOT_FILLED = Color3.fromRGB(70, 105, 70)
local SLOT_OUTPUT = Color3.fromRGB(120, 100, 50)
local SLOT_SELECTED = Color3.fromRGB(90, 90, 45)
local PANEL_BG = Color3.fromRGB(45, 45, 50)
local ARROW_BG = Color3.fromRGB(80, 80, 85)
local ARROW_FILL_COLOR = Color3.fromRGB(220, 140, 40)
local INV_BG = Color3.fromRGB(55, 55, 60)

local function closeUI()
	if screenGui then screenGui:Destroy(); screenGui = nil end
	isOpen = false
	selectedSlot = nil
end

-- ─── Build inventory grid ───
local function rebuildInventory()
	if not invGrid then return end
	-- Clear existing
	for _, child in invGrid:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end

	-- Collect items with count > 0
	local items = {}
	for name, count in inventory do
		if count > 0 and typeof(count) == "number" then
			table.insert(items, {name = name, count = count})
		end
	end
	table.sort(items, function(a, b) return a.name < b.name end)

	for i, item in items do
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
		icon.Position = UDim2.new(0.5, -20, 0, 3)
		icon.BackgroundTransparency = 1
		icon.Image = RESOURCE_ICONS[item.name] or ""
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = btn

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -4, 0, 14)
		lbl.Position = UDim2.new(0, 2, 1, -16)
		lbl.BackgroundTransparency = 1
		lbl.Text = "x" .. item.count
		lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBold
		lbl.Parent = btn

		-- Tooltip-style name
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -4, 0, 10)
		nameLbl.Position = UDim2.new(0, 2, 0, 43)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = item.name:gsub("_", " ")
		nameLbl.TextColor3 = Color3.fromRGB(160, 160, 160)
		nameLbl.TextScaled = true
		nameLbl.Font = Enum.Font.Gotham
		nameLbl.Parent = btn

		btn.MouseButton1Click:Connect(function()
			if smelting or outputReady then return end
			if not selectedSlot then return end

			if selectedSlot == "ore" and not oreType then
				furnaceEvent:FireServer("loadOre", item.name)
			elseif selectedSlot == "fuel" then
				furnaceEvent:FireServer("loadFuel", item.name)
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
			if label then label.Text = oreType:gsub("_", " ") end
			oreSlot.BackgroundColor3 = SLOT_FILLED
		else
			if icon then icon.Image = ""; icon.ImageTransparency = 0.5 end
			if label then label.Text = "Empty" end
			oreSlot.BackgroundColor3 = (selectedSlot == "ore") and SLOT_SELECTED or SLOT_BG
		end
		-- Selection highlight
		local stroke = oreSlot:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Color = (selectedSlot == "ore") and Color3.fromRGB(255, 220, 80) or Color3.fromRGB(90, 90, 100)
			stroke.Thickness = (selectedSlot == "ore") and 3 or 2
		end
	end

	-- Fuel slot
	if fuelSlot then
		local icon = fuelSlot:FindFirstChild("SlotIcon")
		local label = fuelSlot:FindFirstChild("SlotLabel")
		if fuelCount > 0 then
			if icon then icon.Image = RESOURCE_ICONS.Log; icon.ImageTransparency = 0 end
			if label then label.Text = "Wood x" .. fuelCount end
			fuelSlot.BackgroundColor3 = SLOT_FILLED
		else
			if icon then icon.Image = ""; icon.ImageTransparency = 0.5 end
			if label then label.Text = "Empty" end
			fuelSlot.BackgroundColor3 = (selectedSlot == "fuel") and SLOT_SELECTED or SLOT_BG
		end
		local stroke = fuelSlot:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Color = (selectedSlot == "fuel") and Color3.fromRGB(255, 220, 80) or Color3.fromRGB(90, 90, 100)
			stroke.Thickness = (selectedSlot == "fuel") and 3 or 2
		end
	end

	-- Fuel counter
	if fuelCountLabel then
		fuelCountLabel.Text = fuelCount .. " wood loaded"
		fuelCountLabel.TextColor3 = fuelCount > 0 and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(150, 150, 150)
	end

	-- Output slot
	if outputSlot then
		local icon = outputSlot:FindFirstChild("SlotIcon")
		local label = outputSlot:FindFirstChild("SlotLabel")
		if outputReady then
			local outIcon = RESOURCE_ICONS[outputType] or RESOURCE_ICONS.Iron_Ingot
			if icon then icon.Image = outIcon; icon.ImageTransparency = 0 end
			if label then label.Text = "Click to take" end
			outputSlot.BackgroundColor3 = SLOT_OUTPUT
		else
			if icon then icon.Image = ""; icon.ImageTransparency = 0.7 end
			if label then label.Text = "" end
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
		elseif selectedSlot == "ore" then
			statusLabel.Text = "Select an item from inventory for ore slot"
			statusLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
		elseif selectedSlot == "fuel" then
			statusLabel.Text = "Select wood from inventory for fuel"
			statusLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
		elseif oreType and fuelCount > 0 then
			statusLabel.Text = "Ready! Press Smelt (may need more fuel)"
			statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		elseif not oreType then
			statusLabel.Text = "Click ore slot, then select item from inventory"
			statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		else
			statusLabel.Text = "Click fuel slot, then add wood from inventory"
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
	slot.AutoButtonColor = true
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
	icon.ImageTransparency = 0.5
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = slot

	local label = Instance.new("TextLabel")
	label.Name = "SlotLabel"
	label.Size = UDim2.new(1, -6, 0, 14)
	label.Position = UDim2.new(0, 3, 1, -18)
	label.BackgroundTransparency = 1
	label.Text = "Empty"
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
	oreSlot.MouseButton1Click:Connect(function()
		if smelting or outputReady then return end
		if oreType then
			-- Click loaded ore to remove it
			furnaceEvent:FireServer("removeOre")
			selectedSlot = nil
		else
			selectedSlot = (selectedSlot == "ore") and nil or "ore"
		end
		updateSlots()
	end)

	local oreTitle = Instance.new("TextLabel")
	oreTitle.Size = UDim2.new(0, 80, 0, 12); oreTitle.Position = UDim2.new(0, 0, 0, 72)
	oreTitle.BackgroundTransparency = 1; oreTitle.Text = "Ore"; oreTitle.TextColor3 = Color3.fromRGB(140, 140, 140)
	oreTitle.TextScaled = true; oreTitle.Font = Enum.Font.Gotham; oreTitle.Parent = content

	-- Fuel slot
	fuelSlot = createSlot(content, UDim2.new(0, 0, 0, 92), UDim2.new(0, 80, 0, 70))
	fuelSlot.MouseButton1Click:Connect(function()
		if smelting or outputReady then return end
		if fuelCount > 0 and selectedSlot ~= "fuel" then
			-- If clicking fuel slot when not selected, select it to add more
			selectedSlot = "fuel"
		elseif selectedSlot == "fuel" then
			selectedSlot = nil
		else
			selectedSlot = "fuel"
		end
		updateSlots()
	end)

	-- Fuel remove button
	local fuelRemoveBtn = Instance.new("TextButton")
	fuelRemoveBtn.Size = UDim2.new(0, 20, 0, 20); fuelRemoveBtn.Position = UDim2.new(1, -22, 0, 2)
	fuelRemoveBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60); fuelRemoveBtn.Text = "-"
	fuelRemoveBtn.TextColor3 = Color3.new(1, 1, 1); fuelRemoveBtn.TextScaled = true; fuelRemoveBtn.Font = Enum.Font.GothamBold
	fuelRemoveBtn.BorderSizePixel = 0; fuelRemoveBtn.ZIndex = 3; fuelRemoveBtn.Parent = fuelSlot
	Instance.new("UICorner", fuelRemoveBtn).CornerRadius = UDim.new(0, 5)
	fuelRemoveBtn.MouseButton1Click:Connect(function()
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
	fuelCountLabel.BackgroundTransparency = 1; fuelCountLabel.Text = "0 wood"
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
		selectedSlot = nil
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
	statusLabel.BackgroundTransparency = 1; statusLabel.Text = "Click ore slot, then select item from inventory"
	statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150); statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.GothamBold; statusLabel.Parent = main

	-- ═══ Inventory section ═══
	local invTitle = Instance.new("TextLabel")
	invTitle.Size = UDim2.new(1, -24, 0, 18); invTitle.Position = UDim2.new(0, 12, 0, 244)
	invTitle.BackgroundTransparency = 1; invTitle.Text = "Inventory"; invTitle.TextColor3 = Color3.fromRGB(200, 200, 200)
	invTitle.TextScaled = true; invTitle.Font = Enum.Font.GothamBold; invTitle.TextXAlignment = Enum.TextXAlignment.Left
	invTitle.Parent = main

	local invFrame = Instance.new("Frame")
	invFrame.Size = UDim2.new(1, -24, 0, 148); invFrame.Position = UDim2.new(0, 12, 0, 264)
	invFrame.BackgroundColor3 = INV_BG; invFrame.BorderSizePixel = 0; invFrame.ClipsDescendants = true; invFrame.Parent = main
	Instance.new("UICorner", invFrame).CornerRadius = UDim.new(0, 8)

	invGrid = Instance.new("Frame")
	invGrid.Size = UDim2.new(1, -12, 1, -8); invGrid.Position = UDim2.new(0, 6, 0, 4)
	invGrid.BackgroundTransparency = 1; invGrid.Parent = invFrame

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
	selectedSlot = nil

	if state then
		oreType = state.oreType
		fuelCount = state.fuelCount or 0
		smelting = state.smelting or false
		outputReady = state.outputReady or false
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
		selectedSlot = nil
		updateSlots()

	elseif action == "smeltStart" then
		smelting = true
		smeltDuration = data or 20
		smeltStartTime = tick()
		selectedSlot = nil
		updateSlots()

	elseif action == "fuelBurn" then
		-- data = remaining fuel count
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

-- ─── Progress bar ───
RunService.RenderStepped:Connect(function()
	if not isOpen or not smelting or not arrowFill then return end

	local elapsed = tick() - smeltStartTime
	local progress = math.clamp(elapsed / smeltDuration, 0, 1)
	arrowFill.Size = UDim2.new(progress, 0, 1, 0)

	if statusLabel then
		local remaining = math.max(0, math.ceil(smeltDuration - elapsed))
		statusLabel.Text = "Smelting... " .. remaining .. "s | Fuel: " .. fuelCount
		statusLabel.TextColor3 = fuelCount <= 1 and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 200, 80)
	end
end)
