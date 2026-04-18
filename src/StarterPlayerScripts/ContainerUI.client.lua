-- ContainerUI.client.lua
-- Chest-style side panel for the placed Small Container. Mirrors the
-- mercenary backpack UI (StarterPlayerScripts/Mercenaries/
-- MercenaryCommand.client.lua) — same 3x2 slot layout, same anchoring
-- to the player inventory's CenterPanel. Click a container slot to
-- take the stack; shift-click a player hotbar slot to push it in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local containerAction = ReplicatedStorage:WaitForChild("ContainerAction")
local openContainer = ReplicatedStorage:WaitForChild("OpenContainer")

local CONTAINER_SLOTS = 6

local INV_COLORS = {
	panelBg = Color3.fromRGB(139, 109, 63),
	panelBorder = Color3.fromRGB(100, 75, 40),
	slotBg = Color3.fromRGB(182, 148, 101),
	slotBorder = Color3.fromRGB(100, 75, 40),
	separator = Color3.fromRGB(100, 75, 40),
	titleText = Color3.fromRGB(255, 250, 240),
	lightText = Color3.fromRGB(255, 250, 240),
	closeBg = Color3.fromRGB(170, 45, 45),
}

local activeGui = nil
local activeContainer = nil
local conns = {}

local function disconnectAll()
	for _, c in conns do
		if c.Disconnect then c:Disconnect() end
	end
	table.clear(conns)
end

local function findPlayerInventoryPanel()
	local invGui = playerGui:FindFirstChild("InventoryGui")
	if not invGui then return nil end
	return invGui:FindFirstChild("CenterPanel")
end

local function waitForInventoryPanel(timeout)
	local deadline = os.clock() + (timeout or 1)
	while os.clock() < deadline do
		local panel = findPlayerInventoryPanel()
		if panel then return panel end
		RunService.Heartbeat:Wait()
	end
	return findPlayerInventoryPanel()
end

local function closeContainer()
	disconnectAll()
	if activeGui then
		activeGui:Destroy()
		activeGui = nil
	end
	activeContainer = nil
	_G.ActiveContainer = nil
end

_G.CloseContainer = closeContainer

local function openContainerUI(container)
	if not container or not container.Parent then return end
	closeContainer()

	activeContainer = container
	_G.ActiveContainer = container

	if _G.OpenInventory then
		_G.OpenInventory()
	end
	local playerPanel = waitForInventoryPanel(1)

	-- Hide the crafting panel while the container UI is open so the two
	-- UIs don't compete for the left-side of the screen, and keep it
	-- hidden across any rebuild that happens while we stay open.
	local function hideCraftPanel()
		local ig = playerGui:FindFirstChild("InventoryGui")
		if not ig then return end
		local cp = ig:FindFirstChild("CraftPanel")
		if cp then cp.Visible = false end
	end
	hideCraftPanel()
	local invGui = playerGui:FindFirstChild("InventoryGui")
	if invGui then
		table.insert(conns, invGui.ChildAdded:Connect(function(child)
			if child.Name == "CraftPanel" then
				child.Visible = false
			end
		end))
	end
	table.insert(conns, playerGui.ChildAdded:Connect(function(child)
		if child.Name == "InventoryGui" then
			task.defer(hideCraftPanel)
			local conn
			conn = child.ChildAdded:Connect(function(c)
				if c.Name == "CraftPanel" then c.Visible = false end
			end)
			table.insert(conns, conn)
		end
	end))

	local gui = Instance.new("ScreenGui")
	gui.Name = "ContainerGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 31
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui
	activeGui = gui
	if _G.AttachInventoryUIScale then
		_G.AttachInventoryUIScale(gui)
	end

	local COLS = 3
	local ROWS = math.ceil(CONTAINER_SLOTS / COLS)
	local SLOT_SIZE = 80
	local SLOT_PAD = 8
	local GRID_Y = 52
	local FOOTER_H = 28
	local PAD = 10
	local panelW = PAD * 2 + COLS * SLOT_SIZE + (COLS - 1) * SLOT_PAD
	local panelH = GRID_Y + ROWS * (SLOT_SIZE + SLOT_PAD) + FOOTER_H

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromOffset(panelW, panelH)
	panel.BackgroundColor3 = INV_COLORS.panelBg
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local GAP = 8
	local function currentUIScale()
		local scaleObj = gui:FindFirstChildOfClass("UIScale")
		local s = scaleObj and scaleObj.Scale or 1
		if s <= 0 then s = 1 end
		return s
	end
	local function repositionPanel()
		local pp = findPlayerInventoryPanel()
		if pp and pp.Parent then
			local pos = pp.AbsolutePosition
			local size = pp.AbsoluteSize
			local s = currentUIScale()
			local xLocal = pos.X / s - panelW - GAP
			local yLocal = pos.Y / s + (size.Y / s - panelH) / 2
			panel.AnchorPoint = Vector2.new(0, 0)
			panel.Position = UDim2.fromOffset(math.max(xLocal, 4), yLocal)
		else
			panel.AnchorPoint = Vector2.new(0, 0.5)
			panel.Position = UDim2.new(0, 14, 0.5, 0)
		end
	end
	repositionPanel()
	if playerPanel then
		table.insert(conns, playerPanel:GetPropertyChangedSignal("AbsolutePosition"):Connect(repositionPanel))
		table.insert(conns, playerPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(repositionPanel))
	end
	local ownScale = gui:FindFirstChildOfClass("UIScale")
	if ownScale then
		table.insert(conns, ownScale:GetPropertyChangedSignal("Scale"):Connect(repositionPanel))
	end

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = INV_COLORS.panelBorder
	stroke.Thickness = 3
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, PAD, 0, 8)
	title.BackgroundTransparency = 1
	title.TextColor3 = INV_COLORS.titleText
	title.Text = "Container"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -PAD * 2, 0, 2)
	sep.Position = UDim2.new(0, PAD, 0, 42)
	sep.BackgroundColor3 = INV_COLORS.separator
	sep.BorderSizePixel = 0
	sep.Parent = panel

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(28, 28)
	closeBtn.Position = UDim2.new(1, -32, 0, 6)
	closeBtn.BackgroundColor3 = INV_COLORS.closeBg
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = panel
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 6)
	closeCorner.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		closeContainer()
		if _G.CloseInventory then _G.CloseInventory() end
	end)

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -PAD * 2, 0, FOOTER_H)
	hint.Position = UDim2.new(0, PAD, 1, -FOOTER_H - 2)
	hint.BackgroundTransparency = 1
	hint.TextColor3 = INV_COLORS.titleText
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.TextWrapped = true
	hint.Text = "Click a slot to take. Shift-click an inventory slot to put."
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.Parent = panel

	local slotButtons = {}
	for i = 1, CONTAINER_SLOTS do
		local col = (i - 1) % COLS
		local row = math.floor((i - 1) / COLS)
		local x = PAD + col * (SLOT_SIZE + SLOT_PAD)
		local y = GRID_Y + row * (SLOT_SIZE + SLOT_PAD)

		local btn = Instance.new("TextButton")
		btn.Name = "Slot" .. i
		btn.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
		btn.Position = UDim2.new(0, x, 0, y)
		btn.BackgroundColor3 = INV_COLORS.slotBg
		btn.BackgroundTransparency = 0.05
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = false
		btn.Text = ""
		btn.Parent = panel

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 5)
		btnCorner.Parent = btn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = INV_COLORS.slotBorder
		btnStroke.Thickness = 1.5
		btnStroke.Parent = btn

		local rarityFrame = Instance.new("ImageLabel")
		rarityFrame.Name = "RarityFrame"
		rarityFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		rarityFrame.Size = UDim2.new(1, 0, 1, 0)
		rarityFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
		rarityFrame.BackgroundTransparency = 1
		rarityFrame.ScaleType = Enum.ScaleType.Stretch
		rarityFrame.ZIndex = 1
		rarityFrame.Visible = false
		rarityFrame.Parent = btn

		local iconLbl = Instance.new("ImageLabel")
		iconLbl.Name = "ItemIcon"
		iconLbl.AnchorPoint = Vector2.new(0.5, 0.5)
		iconLbl.Size = UDim2.new(0.7, 0, 0.7, 0)
		iconLbl.Position = UDim2.new(0.5, 0, 0.5, 0)
		iconLbl.BackgroundTransparency = 1
		iconLbl.ScaleType = Enum.ScaleType.Fit
		iconLbl.ZIndex = 2
		iconLbl.Parent = btn

		local countLbl = Instance.new("TextLabel")
		countLbl.AnchorPoint = Vector2.new(1, 1)
		countLbl.Size = UDim2.new(0, 30, 0, 16)
		countLbl.Position = UDim2.new(1, -4, 1, -2)
		countLbl.BackgroundTransparency = 1
		countLbl.TextColor3 = INV_COLORS.lightText
		countLbl.Font = Enum.Font.GothamBold
		countLbl.TextSize = 13
		countLbl.TextXAlignment = Enum.TextXAlignment.Right
		countLbl.TextStrokeTransparency = 0.3
		countLbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		countLbl.Text = ""
		countLbl.ZIndex = 3
		countLbl.Parent = btn

		slotButtons[i] = {
			button = btn, iconLbl = iconLbl,
			rarityFrame = rarityFrame, countLbl = countLbl,
		}
	end

	local function refreshSlots()
		if not activeContainer or not activeContainer.Parent then
			closeContainer()
			return
		end
		for i = 1, CONTAINER_SLOTS do
			local s = slotButtons[i]
			local name = activeContainer:GetAttribute("Slot" .. i .. "_Name")
			local count = activeContainer:GetAttribute("Slot" .. i .. "_Count") or 0

			if typeof(name) == "string" and name ~= "" and count > 0 then
				local rarity = _G.GetItemRarity and _G.GetItemRarity(name) or nil
				local frameAsset = (_G.GetRarityFrameAsset and _G.GetRarityFrameAsset(rarity)) or ""
				local iconAsset = (_G.GetItemIcon and _G.GetItemIcon(name)) or ""
				if frameAsset ~= "" then
					s.rarityFrame.Image = frameAsset
					s.rarityFrame.Visible = true
				else
					s.rarityFrame.Visible = false
				end
				s.iconLbl.Image = iconAsset
				s.countLbl.Text = count > 1 and tostring(count) or ""
			else
				s.rarityFrame.Visible = false
				s.iconLbl.Image = ""
				s.countLbl.Text = ""
			end
		end
	end

	refreshSlots()
	table.insert(conns, activeContainer.AttributeChanged:Connect(refreshSlots))
	table.insert(conns, activeContainer.AncestryChanged:Connect(function(_, parent)
		if not parent then closeContainer() end
	end))

	for i, info in slotButtons do
		info.button.MouseButton1Click:Connect(function()
			if not activeContainer then return end
			local name = activeContainer:GetAttribute("Slot" .. i .. "_Name")
			local count = activeContainer:GetAttribute("Slot" .. i .. "_Count") or 0
			if typeof(name) ~= "string" or name == "" or count <= 0 then return end
			containerAction:FireServer("take", activeContainer, i)
		end)
	end
end

openContainer.OnClientEvent:Connect(function(container)
	if typeof(container) ~= "Instance" then return end
	openContainerUI(container)
end)

-- Close UI on Escape
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape and activeGui then
		closeContainer()
	end
end)

-- Shift-click a player inventory/hotbar slot while the container UI is
-- open → push that stack into the container.
_G.ContainerTransferFromPlayer = function(itemName, count)
	if not activeContainer then return false end
	if typeof(itemName) ~= "string" or itemName == "" then return false end
	containerAction:FireServer("put", activeContainer, nil, itemName, count or 1)
	return true
end
