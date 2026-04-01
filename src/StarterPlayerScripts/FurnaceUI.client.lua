-- FurnaceUI.client.lua
-- Furnace smelting UI: ore slot (top-left), fuel slot (bottom-left), arrow (center), output (right)

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
local IRON_ORE_ICON = "rbxassetid://73676755288746"
local LOG_ICON = "rbxassetid://110032041583533"
local IRON_INGOT_ICON = "rbxassetid://72890243946368"
local FIRE_ICON = "rbxassetid://110032041583533" -- fuel indicator uses log icon

-- ─── State ───
local isOpen = false
local screenGui = nil
local currentFurnace = nil
local inventory = {Iron_Ore = 0, Log = 0, Iron_Ingot = 0}

local oreLoaded = false
local fuelLoaded = false
local smelting = false
local outputReady = false
local smeltStartTime = 0
local smeltDuration = 20

-- UI references
local oreSlot, fuelSlot, outputSlot, arrowFill, arrowBg, statusLabel

-- ─── Colors ───
local SLOT_BG = Color3.fromRGB(60, 60, 65)
local SLOT_FILLED = Color3.fromRGB(80, 120, 80)
local SLOT_OUTPUT = Color3.fromRGB(120, 100, 60)
local PANEL_BG = Color3.fromRGB(45, 45, 50)
local ARROW_BG = Color3.fromRGB(80, 80, 85)
local ARROW_FILL = Color3.fromRGB(220, 140, 40)

local function closeUI()
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	isOpen = false
	currentFurnace = nil
	oreSlot = nil
	fuelSlot = nil
	outputSlot = nil
	arrowFill = nil
	statusLabel = nil
end

local function updateSlots()
	if not screenGui then return end

	-- Ore slot
	if oreSlot then
		local icon = oreSlot:FindFirstChild("SlotIcon")
		local label = oreSlot:FindFirstChild("SlotLabel")
		if oreLoaded then
			if icon then icon.Image = IRON_ORE_ICON; icon.ImageTransparency = 0 end
			if label then label.Text = "Iron Ore" end
			oreSlot.BackgroundColor3 = SLOT_FILLED
		else
			if icon then icon.Image = IRON_ORE_ICON; icon.ImageTransparency = 0.6 end
			if label then label.Text = (inventory.Iron_Ore or 0) > 0 and "Click to load" or "No ore" end
			oreSlot.BackgroundColor3 = SLOT_BG
		end
	end

	-- Fuel slot
	if fuelSlot then
		local icon = fuelSlot:FindFirstChild("SlotIcon")
		local label = fuelSlot:FindFirstChild("SlotLabel")
		if fuelLoaded then
			if icon then icon.Image = LOG_ICON; icon.ImageTransparency = 0 end
			if label then label.Text = "Wood" end
			fuelSlot.BackgroundColor3 = SLOT_FILLED
		else
			if icon then icon.Image = LOG_ICON; icon.ImageTransparency = 0.6 end
			if label then label.Text = (inventory.Log or 0) > 0 and "Click to load" or "No fuel" end
			fuelSlot.BackgroundColor3 = SLOT_BG
		end
	end

	-- Output slot
	if outputSlot then
		local icon = outputSlot:FindFirstChild("SlotIcon")
		local label = outputSlot:FindFirstChild("SlotLabel")
		if outputReady then
			if icon then icon.Image = IRON_INGOT_ICON; icon.ImageTransparency = 0 end
			if label then label.Text = "Click to collect" end
			outputSlot.BackgroundColor3 = SLOT_OUTPUT
		else
			if icon then icon.Image = IRON_INGOT_ICON; icon.ImageTransparency = 0.7 end
			if label then label.Text = "" end
			outputSlot.BackgroundColor3 = SLOT_BG
		end
	end

	-- Status
	if statusLabel then
		if smelting then
			statusLabel.Text = "Smelting..."
			statusLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
		elseif outputReady then
			statusLabel.Text = "Done! Collect output"
			statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		elseif oreLoaded and fuelLoaded then
			statusLabel.Text = "Ready to smelt"
			statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		else
			statusLabel.Text = "Load ore and fuel"
			statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		end
	end
end

local function createSlot(parent, pos, size, iconId)
	local slot = Instance.new("TextButton")
	slot.Size = size
	slot.Position = pos
	slot.BackgroundColor3 = SLOT_BG
	slot.BorderSizePixel = 0
	slot.Text = ""
	slot.AutoButtonColor = true
	slot.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = slot

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 90, 100)
	stroke.Thickness = 2
	stroke.Parent = slot

	local icon = Instance.new("ImageLabel")
	icon.Name = "SlotIcon"
	icon.Size = UDim2.new(0, 50, 0, 50)
	icon.Position = UDim2.new(0.5, -25, 0, 8)
	icon.BackgroundTransparency = 1
	icon.Image = iconId
	icon.ImageTransparency = 0.6
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = slot

	local label = Instance.new("TextLabel")
	label.Name = "SlotLabel"
	label.Size = UDim2.new(1, -8, 0, 18)
	label.Position = UDim2.new(0, 4, 1, -22)
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
	main.Size = UDim2.new(0, 420, 0, 300)
	main.Position = UDim2.new(0.5, -210, 0.5, -150)
	main.BackgroundColor3 = PANEL_BG
	main.BorderSizePixel = 0
	main.Parent = screenGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 12)
	mainCorner.Parent = main

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Color3.fromRGB(80, 80, 90)
	mainStroke.Thickness = 2
	mainStroke.Parent = main

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 44)
	titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	titleBar.BorderSizePixel = 0
	titleBar.Parent = main

	local titleCorner = Instance.new("UICorner")
	titleCorner.CornerRadius = UDim.new(0, 12)
	titleCorner.Parent = titleBar

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

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 8)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(closeUI)

	-- Content area
	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, -30, 0, 200)
	content.Position = UDim2.new(0, 15, 0, 55)
	content.BackgroundTransparency = 1
	content.Parent = main

	-- ═══ ORE SLOT (top-left) ═══
	oreSlot = createSlot(content, UDim2.new(0, 0, 0, 0), UDim2.new(0, 90, 0, 90), IRON_ORE_ICON)
	oreSlot.MouseButton1Click:Connect(function()
		if smelting or outputReady then return end
		if oreLoaded then return end
		furnaceEvent:FireServer("loadOre", currentFurnace)
	end)

	-- Ore label
	local oreTitle = Instance.new("TextLabel")
	oreTitle.Size = UDim2.new(0, 90, 0, 16)
	oreTitle.Position = UDim2.new(0, 0, 0, 92)
	oreTitle.BackgroundTransparency = 1
	oreTitle.Text = "Iron Ore"
	oreTitle.TextColor3 = Color3.fromRGB(180, 180, 180)
	oreTitle.TextScaled = true
	oreTitle.Font = Enum.Font.Gotham
	oreTitle.Parent = content

	-- ═══ FUEL SLOT (bottom-left) ═══
	fuelSlot = createSlot(content, UDim2.new(0, 0, 0, 112), UDim2.new(0, 90, 0, 90), LOG_ICON)
	fuelSlot.MouseButton1Click:Connect(function()
		if smelting or outputReady then return end
		if fuelLoaded then return end
		furnaceEvent:FireServer("loadFuel", currentFurnace)
	end)

	-- Fuel label
	local fuelTitle = Instance.new("TextLabel")
	fuelTitle.Size = UDim2.new(0, 90, 0, 16)
	fuelTitle.Position = UDim2.new(0, 0, 1, -16)
	fuelTitle.BackgroundTransparency = 1
	fuelTitle.Text = "Fuel (Wood)"
	fuelTitle.TextColor3 = Color3.fromRGB(180, 180, 180)
	fuelTitle.TextScaled = true
	fuelTitle.Font = Enum.Font.Gotham
	fuelTitle.Parent = content

	-- ═══ ARROW (center) ═══
	arrowBg = Instance.new("Frame")
	arrowBg.Size = UDim2.new(0, 120, 0, 40)
	arrowBg.Position = UDim2.new(0, 110, 0.5, -20)
	arrowBg.BackgroundColor3 = ARROW_BG
	arrowBg.BorderSizePixel = 0
	arrowBg.Parent = content

	local arrowCorner = Instance.new("UICorner")
	arrowCorner.CornerRadius = UDim.new(0, 6)
	arrowCorner.Parent = arrowBg

	arrowFill = Instance.new("Frame")
	arrowFill.Size = UDim2.new(0, 0, 1, 0)
	arrowFill.BackgroundColor3 = ARROW_FILL
	arrowFill.BorderSizePixel = 0
	arrowFill.Parent = arrowBg

	local arrowFillCorner = Instance.new("UICorner")
	arrowFillCorner.CornerRadius = UDim.new(0, 6)
	arrowFillCorner.Parent = arrowFill

	-- Arrow text
	local arrowLabel = Instance.new("TextLabel")
	arrowLabel.Size = UDim2.new(1, 0, 1, 0)
	arrowLabel.BackgroundTransparency = 1
	arrowLabel.Text = ">>>"
	arrowLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	arrowLabel.TextScaled = true
	arrowLabel.Font = Enum.Font.GothamBold
	arrowLabel.ZIndex = 2
	arrowLabel.Parent = arrowBg

	-- ═══ OUTPUT SLOT (right) ═══
	outputSlot = createSlot(content, UDim2.new(0, 250, 0.5, -45), UDim2.new(0, 120, 0, 90), IRON_INGOT_ICON)
	outputSlot.MouseButton1Click:Connect(function()
		if not outputReady then return end
		furnaceEvent:FireServer("collectOutput", currentFurnace)
	end)

	-- Output label
	local outTitle = Instance.new("TextLabel")
	outTitle.Size = UDim2.new(0, 120, 0, 16)
	outTitle.Position = UDim2.new(0, 250, 0.5, 47)
	outTitle.BackgroundTransparency = 1
	outTitle.Text = "Iron Ingot"
	outTitle.TextColor3 = Color3.fromRGB(180, 180, 180)
	outTitle.TextScaled = true
	outTitle.Font = Enum.Font.Gotham
	outTitle.Parent = content

	-- ═══ STATUS LABEL ═══
	statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -30, 0, 24)
	statusLabel.Position = UDim2.new(0, 15, 1, -35)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Load ore and fuel"
	statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.Parent = main

	-- ═══ SMELT BUTTON ═══
	local smeltBtn = Instance.new("TextButton")
	smeltBtn.Name = "SmeltBtn"
	smeltBtn.Size = UDim2.new(0, 120, 0, 34)
	smeltBtn.Position = UDim2.new(0, 110, 0, 155)
	smeltBtn.BackgroundColor3 = Color3.fromRGB(200, 120, 30)
	smeltBtn.Text = "Smelt"
	smeltBtn.TextColor3 = Color3.new(1, 1, 1)
	smeltBtn.TextScaled = true
	smeltBtn.Font = Enum.Font.GothamBold
	smeltBtn.BorderSizePixel = 0
	smeltBtn.Parent = content

	local smeltCorner = Instance.new("UICorner")
	smeltCorner.CornerRadius = UDim.new(0, 8)
	smeltCorner.Parent = smeltBtn

	smeltBtn.MouseButton1Click:Connect(function()
		if smelting or outputReady then return end
		if not oreLoaded or not fuelLoaded then return end
		furnaceEvent:FireServer("startSmelt", currentFurnace)
	end)

	updateSlots()
end

-- ─── Open furnace UI ───
local function openUI(furnaceModel, state)
	if isOpen then closeUI() end

	currentFurnace = furnaceModel
	isOpen = true

	-- Restore state from server
	if state then
		oreLoaded = state.oreLoaded or false
		fuelLoaded = state.fuelLoaded or false
		smelting = state.smelting or false
		outputReady = state.outputReady or false
	else
		oreLoaded = false
		fuelLoaded = false
		smelting = false
		outputReady = false
	end

	buildUI()

	-- Request full state from server
	furnaceEvent:FireServer("getState", currentFurnace)
end

-- ─── Events ───
openFurnaceEvent.OnClientEvent:Connect(function(furnaceModel, state)
	openUI(furnaceModel, state)
end)

furnaceEvent.OnClientEvent:Connect(function(action, data, extra1, extra2)
	if action == "stateUpdate" then
		if data then
			oreLoaded = data.oreLoaded or false
			fuelLoaded = data.fuelLoaded or false
			smelting = data.smelting or false
			outputReady = data.outputReady or false
		end
		updateSlots()

	elseif action == "smeltStart" then
		smelting = true
		smeltDuration = data or 20
		smeltStartTime = tick()
		updateSlots()

	elseif action == "smeltDone" then
		smelting = false
		outputReady = true
		oreLoaded = false
		fuelLoaded = false
		if arrowFill then
			arrowFill.Size = UDim2.new(1, 0, 1, 0)
		end
		updateSlots()

	elseif action == "fullState" then
		-- data = state, extra1 = elapsed, extra2 = totalTime
		if data then
			oreLoaded = data.oreLoaded or false
			fuelLoaded = data.fuelLoaded or false
			smelting = data.smelting or false
			outputReady = data.outputReady or false
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

-- ─── Progress bar update ───
RunService.RenderStepped:Connect(function()
	if not isOpen or not smelting or not arrowFill then return end

	local elapsed = tick() - smeltStartTime
	local progress = math.clamp(elapsed / smeltDuration, 0, 1)
	arrowFill.Size = UDim2.new(progress, 0, 1, 0)

	if statusLabel then
		local remaining = math.max(0, math.ceil(smeltDuration - elapsed))
		statusLabel.Text = "Smelting... " .. remaining .. "s"
	end
end)
