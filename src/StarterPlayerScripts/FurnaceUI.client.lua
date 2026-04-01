-- FurnaceUI.client.lua
-- Furnace smelting UI: ore picker (top-left), fuel slot with counter (bottom-left),
-- progress arrow (center), output (right). Supports multiple ore types.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local furnaceEvent = ReplicatedStorage:WaitForChild("FurnaceAction")
local openFurnaceEvent = ReplicatedStorage:WaitForChild("OpenFurnace")
local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate")

-- ─── Icons ───
local LOG_ICON = "rbxassetid://110032041583533"
local IRON_ORE_ICON = "rbxassetid://73676755288746"
local IRON_INGOT_ICON = "rbxassetid://72890243946368"

-- Smeltable ores (expandable)
local SMELTABLE_ORES = {
	{ name = "Iron_Ore", displayName = "Iron Ore", icon = IRON_ORE_ICON, outputIcon = IRON_INGOT_ICON, outputName = "Iron Ingot" },
}

local FUEL_NEEDED = 4

-- ─── State ───
local isOpen = false
local screenGui = nil
local currentFurnace = nil
local inventory = {}

local oreType = nil -- loaded ore type string
local fuelCount = 0
local smelting = false
local outputReady = false
local outputType = nil
local smeltStartTime = 0
local smeltDuration = 20

-- UI refs
local oreSlot, fuelSlot, outputSlot, arrowFill, statusLabel, fuelCountLabel, smeltBtn

-- ─── Colors ───
local SLOT_BG = Color3.fromRGB(60, 60, 65)
local SLOT_FILLED = Color3.fromRGB(80, 120, 80)
local SLOT_OUTPUT = Color3.fromRGB(120, 100, 60)
local PANEL_BG = Color3.fromRGB(45, 45, 50)
local ARROW_BG = Color3.fromRGB(80, 80, 85)
local ARROW_FILL_COLOR = Color3.fromRGB(220, 140, 40)

-- ─── Helpers ───
local function getOreInfo(name)
	for _, ore in SMELTABLE_ORES do
		if ore.name == name then return ore end
	end
	return nil
end

local function closeUI()
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	isOpen = false
	currentFurnace = nil
end

local function updateSlots()
	if not screenGui then return end

	-- ── Ore slot ──
	if oreSlot then
		local icon = oreSlot:FindFirstChild("SlotIcon")
		local label = oreSlot:FindFirstChild("SlotLabel")
		if oreType then
			local info = getOreInfo(oreType)
			if icon then icon.Image = info and info.icon or IRON_ORE_ICON; icon.ImageTransparency = 0 end
			if label then label.Text = info and info.displayName or oreType end
			oreSlot.BackgroundColor3 = SLOT_FILLED
		else
			if icon then icon.Image = IRON_ORE_ICON; icon.ImageTransparency = 0.5 end
			if label then label.Text = "Click to load" end
			oreSlot.BackgroundColor3 = SLOT_BG
		end
	end

	-- ── Fuel slot ──
	if fuelSlot then
		local icon = fuelSlot:FindFirstChild("SlotIcon")
		local label = fuelSlot:FindFirstChild("SlotLabel")
		if fuelCount > 0 then
			if icon then icon.Image = LOG_ICON; icon.ImageTransparency = 0 end
			if label then label.Text = "Wood" end
			fuelSlot.BackgroundColor3 = SLOT_FILLED
		else
			if icon then icon.Image = LOG_ICON; icon.ImageTransparency = 0.5 end
			if label then label.Text = "Click to add" end
			fuelSlot.BackgroundColor3 = SLOT_BG
		end
	end

	-- ── Fuel counter ──
	if fuelCountLabel then
		fuelCountLabel.Text = fuelCount .. " / " .. FUEL_NEEDED
		if fuelCount >= FUEL_NEEDED then
			fuelCountLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		else
			fuelCountLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
		end
	end

	-- ── Output slot ──
	if outputSlot then
		local icon = outputSlot:FindFirstChild("SlotIcon")
		local label = outputSlot:FindFirstChild("SlotLabel")
		if outputReady then
			local outInfo = outputType and getOreInfo(outputType)
			-- For output, show the result icon
			if icon then icon.Image = IRON_INGOT_ICON; icon.ImageTransparency = 0 end
			if label then label.Text = "Click to collect" end
			outputSlot.BackgroundColor3 = SLOT_OUTPUT
		else
			if icon then icon.Image = IRON_INGOT_ICON; icon.ImageTransparency = 0.7 end
			if label then label.Text = "" end
			outputSlot.BackgroundColor3 = SLOT_BG
		end
	end

	-- ── Smelt button ──
	if smeltBtn then
		if smelting then
			smeltBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
			smeltBtn.Text = "Smelting..."
		elseif outputReady then
			smeltBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
			smeltBtn.Text = "Done"
		elseif oreType and fuelCount >= FUEL_NEEDED then
			smeltBtn.BackgroundColor3 = Color3.fromRGB(200, 120, 30)
			smeltBtn.Text = "Smelt"
		else
			smeltBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
			smeltBtn.Text = "Smelt"
		end
	end

	-- ── Status ──
	if statusLabel and not smelting then
		if outputReady then
			statusLabel.Text = "Done! Collect output"
			statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		elseif oreType and fuelCount >= FUEL_NEEDED then
			statusLabel.Text = "Ready - press Smelt!"
			statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		elseif not oreType and fuelCount < FUEL_NEEDED then
			statusLabel.Text = "Load ore and " .. (FUEL_NEEDED - fuelCount) .. " more wood"
			statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		elseif not oreType then
			statusLabel.Text = "Load ore"
			statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		else
			statusLabel.Text = "Add " .. (FUEL_NEEDED - fuelCount) .. " more wood"
			statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		end
	end
end

-- ─── Ore Picker Popup ───
local orePicker = nil

local function closeOrePicker()
	if orePicker then
		orePicker:Destroy()
		orePicker = nil
	end
end

local function showOrePicker(parentFrame)
	closeOrePicker()

	-- Find ores the player has
	local available = {}
	for _, ore in SMELTABLE_ORES do
		if (inventory[ore.name] or 0) > 0 then
			table.insert(available, ore)
		end
	end

	if #available == 0 then
		-- No ores available - flash status
		if statusLabel then
			statusLabel.Text = "No smeltable ores in inventory!"
			statusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		end
		return
	end

	-- If only one type, load it directly
	if #available == 1 then
		furnaceEvent:FireServer("loadOre", available[1].name)
		return
	end

	-- Show picker
	orePicker = Instance.new("Frame")
	orePicker.Name = "OrePicker"
	orePicker.Size = UDim2.new(0, 200, 0, #available * 45 + 10)
	orePicker.Position = UDim2.new(0, 95, 0, 0)
	orePicker.BackgroundColor3 = Color3.fromRGB(55, 55, 60)
	orePicker.BorderSizePixel = 0
	orePicker.ZIndex = 10
	orePicker.Parent = parentFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = orePicker

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 120, 130)
	stroke.Thickness = 1
	stroke.Parent = orePicker

	for i, ore in available do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -10, 0, 38)
		btn.Position = UDim2.new(0, 5, 0, 5 + (i - 1) * 45)
		btn.BackgroundColor3 = Color3.fromRGB(70, 70, 75)
		btn.Text = ""
		btn.BorderSizePixel = 0
		btn.ZIndex = 11
		btn.Parent = orePicker

		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 6)
		bc.Parent = btn

		local ic = Instance.new("ImageLabel")
		ic.Size = UDim2.new(0, 30, 0, 30)
		ic.Position = UDim2.new(0, 4, 0.5, -15)
		ic.BackgroundTransparency = 1
		ic.Image = ore.icon
		ic.ScaleType = Enum.ScaleType.Fit
		ic.ZIndex = 12
		ic.Parent = btn

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -75, 1, 0)
		lbl.Position = UDim2.new(0, 38, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = ore.displayName
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextScaled = true
		lbl.Font = Enum.Font.Gotham
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.ZIndex = 12
		lbl.Parent = btn

		local countLbl = Instance.new("TextLabel")
		countLbl.Size = UDim2.new(0, 30, 1, 0)
		countLbl.Position = UDim2.new(1, -35, 0, 0)
		countLbl.BackgroundTransparency = 1
		countLbl.Text = "x" .. tostring(inventory[ore.name] or 0)
		countLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
		countLbl.TextScaled = true
		countLbl.Font = Enum.Font.GothamBold
		countLbl.ZIndex = 12
		countLbl.Parent = btn

		btn.MouseButton1Click:Connect(function()
			furnaceEvent:FireServer("loadOre", ore.name)
			closeOrePicker()
		end)
	end
end

-- ─── Create a slot ───
local function createSlot(parent, pos, size, iconId)
	local slot = Instance.new("TextButton")
	slot.Size = size
	slot.Position = pos
	slot.BackgroundColor3 = SLOT_BG
	slot.BorderSizePixel = 0
	slot.Text = ""
	slot.AutoButtonColor = true
	slot.Parent = parent

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = slot

	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(90, 90, 100)
	s.Thickness = 2
	s.Parent = slot

	local icon = Instance.new("ImageLabel")
	icon.Name = "SlotIcon"
	icon.Size = UDim2.new(0, 50, 0, 50)
	icon.Position = UDim2.new(0.5, -25, 0, 5)
	icon.BackgroundTransparency = 1
	icon.Image = iconId
	icon.ImageTransparency = 0.5
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = slot

	local label = Instance.new("TextLabel")
	label.Name = "SlotLabel"
	label.Size = UDim2.new(1, -6, 0, 16)
	label.Position = UDim2.new(0, 3, 1, -20)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = Color3.fromRGB(200, 200, 200)
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

	-- Main panel
	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.new(0, 440, 0, 320)
	main.Position = UDim2.new(0.5, -220, 0.5, -160)
	main.BackgroundColor3 = PANEL_BG
	main.BorderSizePixel = 0
	main.Parent = screenGui

	Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
	local ms = Instance.new("UIStroke")
	ms.Color = Color3.fromRGB(80, 80, 90)
	ms.Thickness = 2
	ms.Parent = main

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 44)
	titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	titleBar.BorderSizePixel = 0
	titleBar.Parent = main
	Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

	local titleFix = Instance.new("Frame")
	titleFix.Size = UDim2.new(1, 0, 0, 12)
	titleFix.Position = UDim2.new(0, 0, 1, -12)
	titleFix.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	titleFix.BorderSizePixel = 0
	titleFix.Parent = titleBar

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -60, 1, 0)
	titleLabel.Position = UDim2.new(0, 15, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Furnace"
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 34, 0, 34)
	closeBtn.Position = UDim2.new(1, -40, 0.5, -17)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = titleBar
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
	closeBtn.MouseButton1Click:Connect(closeUI)

	-- Content area
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -30, 0, 210)
	content.Position = UDim2.new(0, 15, 0, 55)
	content.BackgroundTransparency = 1
	content.Parent = main

	-- ═══ ORE SLOT (top-left) ═══
	oreSlot = createSlot(content, UDim2.new(0, 0, 0, 0), UDim2.new(0, 90, 0, 80), IRON_ORE_ICON)
	oreSlot.MouseButton1Click:Connect(function()
		if smelting or outputReady then return end
		if oreType then
			-- Remove loaded ore back to inventory
			furnaceEvent:FireServer("removeOre")
		else
			closeOrePicker()
			showOrePicker(content)
		end
	end)

	local oreTitle = Instance.new("TextLabel")
	oreTitle.Size = UDim2.new(0, 90, 0, 14)
	oreTitle.Position = UDim2.new(0, 0, 0, 82)
	oreTitle.BackgroundTransparency = 1
	oreTitle.Text = "Ore (click to load)"
	oreTitle.TextColor3 = Color3.fromRGB(150, 150, 150)
	oreTitle.TextScaled = true
	oreTitle.Font = Enum.Font.Gotham
	oreTitle.Parent = content

	-- ═══ FUEL SLOT (bottom-left) ═══
	fuelSlot = createSlot(content, UDim2.new(0, 0, 0, 108), UDim2.new(0, 90, 0, 80), LOG_ICON)
	fuelSlot.MouseButton1Click:Connect(function()
		if smelting or outputReady then return end
		if fuelCount >= FUEL_NEEDED then return end
		furnaceEvent:FireServer("loadFuel")
		closeOrePicker()
	end)

	-- Fuel remove button (right-click style - small minus button)
	local fuelRemoveBtn = Instance.new("TextButton")
	fuelRemoveBtn.Size = UDim2.new(0, 22, 0, 22)
	fuelRemoveBtn.Position = UDim2.new(1, -24, 0, 2)
	fuelRemoveBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	fuelRemoveBtn.Text = "-"
	fuelRemoveBtn.TextColor3 = Color3.new(1, 1, 1)
	fuelRemoveBtn.TextScaled = true
	fuelRemoveBtn.Font = Enum.Font.GothamBold
	fuelRemoveBtn.BorderSizePixel = 0
	fuelRemoveBtn.ZIndex = 3
	fuelRemoveBtn.Parent = fuelSlot
	Instance.new("UICorner", fuelRemoveBtn).CornerRadius = UDim.new(0, 6)

	fuelRemoveBtn.MouseButton1Click:Connect(function()
		if smelting or outputReady then return end
		if fuelCount <= 0 then return end
		furnaceEvent:FireServer("removeFuel")
	end)

	-- Fuel counter
	fuelCountLabel = Instance.new("TextLabel")
	fuelCountLabel.Size = UDim2.new(0, 90, 0, 18)
	fuelCountLabel.Position = UDim2.new(0, 0, 0, 190)
	fuelCountLabel.BackgroundTransparency = 1
	fuelCountLabel.Text = "0 / " .. FUEL_NEEDED
	fuelCountLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
	fuelCountLabel.TextScaled = true
	fuelCountLabel.Font = Enum.Font.GothamBold
	fuelCountLabel.Parent = content

	local fuelTitle = Instance.new("TextLabel")
	fuelTitle.Size = UDim2.new(0, 90, 0, 14)
	fuelTitle.Position = UDim2.new(0, 0, 0, 96)
	fuelTitle.BackgroundTransparency = 1
	fuelTitle.Text = "Fuel (click to add)"
	fuelTitle.TextColor3 = Color3.fromRGB(150, 150, 150)
	fuelTitle.TextScaled = true
	fuelTitle.Font = Enum.Font.Gotham
	fuelTitle.Parent = content

	-- ═══ ARROW (center) ═══
	local arrowBg = Instance.new("Frame")
	arrowBg.Size = UDim2.new(0, 120, 0, 40)
	arrowBg.Position = UDim2.new(0, 115, 0.5, -20)
	arrowBg.BackgroundColor3 = ARROW_BG
	arrowBg.BorderSizePixel = 0
	arrowBg.ClipsDescendants = true
	arrowBg.Parent = content
	Instance.new("UICorner", arrowBg).CornerRadius = UDim.new(0, 6)

	arrowFill = Instance.new("Frame")
	arrowFill.Size = UDim2.new(0, 0, 1, 0)
	arrowFill.BackgroundColor3 = ARROW_FILL_COLOR
	arrowFill.BorderSizePixel = 0
	arrowFill.Parent = arrowBg
	Instance.new("UICorner", arrowFill).CornerRadius = UDim.new(0, 6)

	local arrowLabel = Instance.new("TextLabel")
	arrowLabel.Size = UDim2.new(1, 0, 1, 0)
	arrowLabel.BackgroundTransparency = 1
	arrowLabel.Text = ">>>"
	arrowLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	arrowLabel.TextScaled = true
	arrowLabel.Font = Enum.Font.GothamBold
	arrowLabel.ZIndex = 2
	arrowLabel.Parent = arrowBg

	-- ═══ SMELT BUTTON ═══
	smeltBtn = Instance.new("TextButton")
	smeltBtn.Name = "SmeltBtn"
	smeltBtn.Size = UDim2.new(0, 120, 0, 34)
	smeltBtn.Position = UDim2.new(0, 115, 0.5, 28)
	smeltBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	smeltBtn.Text = "Smelt"
	smeltBtn.TextColor3 = Color3.new(1, 1, 1)
	smeltBtn.TextScaled = true
	smeltBtn.Font = Enum.Font.GothamBold
	smeltBtn.BorderSizePixel = 0
	smeltBtn.Parent = content
	Instance.new("UICorner", smeltBtn).CornerRadius = UDim.new(0, 8)

	smeltBtn.MouseButton1Click:Connect(function()
		if smelting or outputReady then return end
		if not oreType or fuelCount < FUEL_NEEDED then return end
		furnaceEvent:FireServer("startSmelt")
		closeOrePicker()
	end)

	-- ═══ OUTPUT SLOT (right) ═══
	outputSlot = createSlot(content, UDim2.new(0, 260, 0.5, -40), UDim2.new(0, 120, 0, 80), IRON_INGOT_ICON)
	outputSlot.MouseButton1Click:Connect(function()
		if not outputReady then return end
		furnaceEvent:FireServer("collectOutput")
	end)

	local outTitle = Instance.new("TextLabel")
	outTitle.Size = UDim2.new(0, 120, 0, 14)
	outTitle.Position = UDim2.new(0, 260, 0.5, 42)
	outTitle.BackgroundTransparency = 1
	outTitle.Text = "Output"
	outTitle.TextColor3 = Color3.fromRGB(150, 150, 150)
	outTitle.TextScaled = true
	outTitle.Font = Enum.Font.Gotham
	outTitle.Parent = content

	-- ═══ STATUS ═══
	statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -30, 0, 22)
	statusLabel.Position = UDim2.new(0, 15, 1, -32)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Load ore and fuel"
	statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.Parent = main

	updateSlots()
end

-- ─── Open furnace UI ───
local function openUI(furnaceModel, state)
	if isOpen then closeUI() end
	currentFurnace = furnaceModel
	isOpen = true

	if state then
		oreType = state.oreType
		fuelCount = state.fuelCount or 0
		smelting = state.smelting or false
		outputReady = state.outputReady or false
		outputType = state.outputType
	else
		oreType = nil
		fuelCount = 0
		smelting = false
		outputReady = false
		outputType = nil
	end

	buildUI()
	furnaceEvent:FireServer("getState", currentFurnace)
end

-- ─── Events ───
openFurnaceEvent.OnClientEvent:Connect(function(furnaceModel, state)
	openUI(furnaceModel, state)
end)

furnaceEvent.OnClientEvent:Connect(function(action, data, extra1, extra2)
	if action == "stateUpdate" then
		if data then
			oreType = data.oreType
			fuelCount = data.fuelCount or 0
			smelting = data.smelting or false
			outputReady = data.outputReady or false
			outputType = data.outputType
		end
		updateSlots()

	elseif action == "smeltStart" then
		smelting = true
		smeltDuration = data or 20
		smeltStartTime = tick()
		updateSlots()

	elseif action == "smeltDone" then
		if data then
			oreType = data.oreType
			fuelCount = data.fuelCount or 0
			smelting = data.smelting or false
			outputReady = data.outputReady or false
			outputType = data.outputType
		else
			smelting = false
			outputReady = true
			oreType = nil
			fuelCount = 0
		end
		if arrowFill then
			arrowFill.Size = UDim2.new(1, 0, 1, 0)
		end
		updateSlots()

	elseif action == "fullState" then
		if data then
			oreType = data.oreType
			fuelCount = data.fuelCount or 0
			smelting = data.smelting or false
			outputReady = data.outputReady or false
			outputType = data.outputType
		end
		if smelting and extra1 and extra2 then
			smeltDuration = extra2
			smeltStartTime = tick() - extra1
		end
		updateSlots()
	end
end)

inventoryEvent.OnClientEvent:Connect(function(inv)
	inventory = inv
	updateSlots()
end)

-- ─── Progress bar ───
RunService.RenderStepped:Connect(function()
	if not isOpen or not smelting or not arrowFill then return end

	local elapsed = tick() - smeltStartTime
	local progress = math.clamp(elapsed / smeltDuration, 0, 1)
	arrowFill.Size = UDim2.new(progress, 0, 1, 0)

	if statusLabel then
		local remaining = math.max(0, math.ceil(smeltDuration - elapsed))
		statusLabel.Text = "Smelting... " .. remaining .. "s"
		statusLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
	end
end)
