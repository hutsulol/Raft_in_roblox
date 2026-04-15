-- MercenaryCommand.client.lua
-- Provides an E-key interaction for spawned mercenaries and a
-- building-system-style placement UI for setting a fishing location.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local commandEvent = ReplicatedStorage:WaitForChild("MercenaryCommand")
local equipEvent = ReplicatedStorage:WaitForChild("MercenaryEquipment")

local MERC_INVENTORY_SLOTS = 6

-- ── State ───────────────────────────────────────────────────────────────
local targetMerc = nil           -- model currently under crosshair
local promptBillboard = nil      -- small "[E] Command" BillboardGui
local commandMenuGui = nil       -- full command menu ScreenGui
local commandMenuOpen = false
local isPlacingLocation = false  -- phase 1: pick raft spot
local isPlacingCast = false      -- phase 2: pick water cast spot
local placingMercName = nil
local pendingRaftPart = nil      -- saved from phase 1 for the server
local pendingRaftOffset = nil
local previewCircle = nil
local renderConn = nil
local inputConn = nil
local cancelConn = nil

local MAX_INTERACT_DISTANCE = 20

-- ── Helpers ─────────────────────────────────────────────────────────────

local function getAncestorWithTag(instance, tag)
	local current = instance
	while current and current ~= workspace do
		if CollectionService:HasTag(current, tag) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function isOwnedMercenary(model)
	return model and model:GetAttribute("OwnerUserId") == player.UserId
end

local function hasFishingRod(model)
	return model and model:GetAttribute("EquippedWeapon") == "FishingRod"
end

local function distanceToModel(model)
	local char = player.Character
	if not char then return math.huge end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return math.huge end
	local mercHrp = model:FindFirstChild("HumanoidRootPart")
	if not mercHrp then return math.huge end
	return (hrp.Position - mercHrp.Position).Magnitude
end

-- ── Prompt billboard ("[E] Command") ────────────────────────────────────

local function destroyPrompt()
	if promptBillboard then
		promptBillboard:Destroy()
		promptBillboard = nil
	end
end

local function createPrompt(model)
	destroyPrompt()

	local adornee = model:FindFirstChild("Head")
		or model:FindFirstChild("HumanoidRootPart")
	if not adornee then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "MercInteractPrompt"
	bb.Adornee = adornee
	bb.Size = UDim2.new(0, 120, 0, 36)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.ResetOnSpawn = false
	bb.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(255, 255, 0)
	label.Text = "[E] Command"
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.BorderSizePixel = 0
	label.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	promptBillboard = bb
end

-- ── Mercenary inventory UI (left-side panel) ────────────────────────────

-- Colours matched to the player inventory / phone menu theme
local INV_COLORS = {
	panelBg = Color3.fromRGB(10, 25, 55),
	panelBorder = Color3.fromRGB(80, 180, 255),
	slotBg = Color3.fromRGB(15, 35, 70),
	slotBorder = Color3.fromRGB(80, 180, 255),
	titleText = Color3.fromRGB(220, 240, 255),
	separator = Color3.fromRGB(80, 180, 255),
	closeBg = Color3.fromRGB(180, 60, 50),
}

local mercInvGui = nil
local mercInvConns = {}

local function closeMercInventory()
	if mercInvGui then
		mercInvGui:Destroy()
		mercInvGui = nil
	end
	for _, c in mercInvConns do
		if c and typeof(c) == "RBXScriptConnection" then c:Disconnect() end
	end
	mercInvConns = {}
	-- Clear any leftover drag ghost
	local ghost = playerGui:FindFirstChild("MercDragGhost")
	if ghost then ghost:Destroy() end
	-- Restore the player inventory's CraftPanel (hidden while the
	-- merc inventory was open).
	local invGui = playerGui:FindFirstChild("InventoryGui")
	local craftPanel = invGui and invGui:FindFirstChild("CraftPanel")
	if craftPanel then craftPanel.Visible = true end
end

-- ── Hit-test helpers for drag-and-drop ─────────────────────────────────
local function mouseOverFrame(frame, mx, my)
	if not frame or not frame.Parent then return false end
	local pos = frame.AbsolutePosition
	local size = frame.AbsoluteSize
	return mx >= pos.X and mx <= pos.X + size.X
		and my >= pos.Y and my <= pos.Y + size.Y
end

-- Locate the player inventory's main panel (created by InventoryUI.client.lua).
-- Returns nil if the inventory UI isn't currently open.
local function findPlayerInventoryPanel()
	local invGui = playerGui:FindFirstChild("InventoryGui")
	if not invGui then return nil end
	return invGui:FindFirstChild("CenterPanel")
end

-- Wait briefly for the InventoryGui to appear after _G.OpenInventory().
local function waitForInventoryPanel(timeout)
	local deadline = os.clock() + (timeout or 1)
	while os.clock() < deadline do
		local panel = findPlayerInventoryPanel()
		if panel then return panel end
		RunService.Heartbeat:Wait()
	end
	return findPlayerInventoryPanel()
end

local function openMercInventory(mercModel)
	closeMercInventory()

	local mercName = mercModel:GetAttribute("MercName")
	if not mercName then return end

	local mercFolder = player:FindFirstChild("Mercenaries")
	local mercEntry = mercFolder and mercFolder:FindFirstChild(mercName)
	if not mercEntry then return end

	-- Gate: only open if a backpack is equipped.
	local equippedBp = mercEntry:GetAttribute("EquippedBackpack")
	if typeof(equippedBp) ~= "string" or equippedBp == "" then return end

	-- Open the player's main inventory alongside the backpack.
	if _G.OpenInventory then
		_G.OpenInventory()
	end

	-- Wait (briefly) for the player inventory panel so we can anchor to it.
	local playerPanel = waitForInventoryPanel(1)

	-- Hide the crafting panel while the merc inventory is open so the
	-- two UIs don't compete for the left-side of the screen. Also listen
	-- for any later rebuild so it stays hidden.
	local function hideCraftPanel()
		local ig = playerGui:FindFirstChild("InventoryGui")
		if not ig then return end
		local cp = ig:FindFirstChild("CraftPanel")
		if cp then cp.Visible = false end
	end
	hideCraftPanel()
	local invGui = playerGui:FindFirstChild("InventoryGui")
	if invGui then
		table.insert(mercInvConns, invGui.ChildAdded:Connect(function(child)
			if child.Name == "CraftPanel" then
				child.Visible = false
			end
		end))
	end
	table.insert(mercInvConns, playerGui.ChildAdded:Connect(function(child)
		if child.Name == "InventoryGui" then
			-- Rebuild happened while merc inventory is open; hide craft panel
			-- once it materialises.
			task.defer(hideCraftPanel)
			local conn
			conn = child.ChildAdded:Connect(function(c)
				if c.Name == "CraftPanel" then c.Visible = false end
			end)
			table.insert(mercInvConns, conn)
		end
	end))

	local gui = Instance.new("ScreenGui")
	gui.Name = "MercInventory"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 31
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	-- Panel dimensions (3 cols × 2 rows), spacing mirrors InventoryUI
	local COLS = 3
	local ROWS = math.ceil(MERC_INVENTORY_SLOTS / COLS)
	local SLOT_SIZE = 60
	local SLOT_PAD = 6
	local GRID_Y = 52       -- matches InventoryUI.CenterPanel grid offset
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

	-- Position: directly to the left of the player's inventory CenterPanel.
	-- Fallback: 14px from screen left, vertically centred.
	local GAP = 8
	local function repositionPanel()
		local pp = findPlayerInventoryPanel()
		if pp and pp.Parent then
			local pos = pp.AbsolutePosition
			local size = pp.AbsoluteSize
			local x = pos.X - panelW - GAP
			local y = pos.Y + (size.Y - panelH) / 2
			panel.AnchorPoint = Vector2.new(0, 0)
			panel.Position = UDim2.fromOffset(math.max(x, 4), y)
		else
			panel.AnchorPoint = Vector2.new(0, 0.5)
			panel.Position = UDim2.new(0, 14, 0.5, 0)
		end
	end
	repositionPanel()
	if playerPanel then
		table.insert(mercInvConns, playerPanel:GetPropertyChangedSignal("AbsolutePosition"):Connect(repositionPanel))
		table.insert(mercInvConns, playerPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(repositionPanel))
	end

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = INV_COLORS.panelBorder
	stroke.Thickness = 3
	stroke.Parent = panel

	-- Header (title + separator, matching the player inventory style)
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, PAD, 0, 8)
	title.BackgroundTransparency = 1
	title.TextColor3 = INV_COLORS.titleText
	title.Text = "Backpack"
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

	-- Close (X) button matching the inventory's close button
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
		closeMercInventory()
		if _G.CloseInventory then
			_G.CloseInventory()
		end
	end)

	-- Footer hint (empty backpack or help text)
	local hintLabel = Instance.new("TextLabel")
	hintLabel.Size = UDim2.new(1, -PAD * 2, 0, FOOTER_H)
	hintLabel.Position = UDim2.new(0, PAD, 1, -FOOTER_H - 2)
	hintLabel.BackgroundTransparency = 1
	hintLabel.TextColor3 = INV_COLORS.titleText
	hintLabel.Font = Enum.Font.Gotham
	hintLabel.TextSize = 12
	hintLabel.TextWrapped = true
	hintLabel.Text = ""
	hintLabel.TextXAlignment = Enum.TextXAlignment.Center
	hintLabel.Parent = panel

	-- Slot buttons
	local slotButtons = {}
	for i = 1, MERC_INVENTORY_SLOTS do
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

		-- Rarity frame background (filled in on refresh)
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

		-- Item icon on top of the rarity frame
		local iconLbl = Instance.new("ImageLabel")
		iconLbl.Name = "ItemIcon"
		iconLbl.AnchorPoint = Vector2.new(0.5, 0.5)
		iconLbl.Size = UDim2.new(0.7, 0, 0.7, 0)
		iconLbl.Position = UDim2.new(0.5, 0, 0.5, 0)
		iconLbl.BackgroundTransparency = 1
		iconLbl.ScaleType = Enum.ScaleType.Fit
		iconLbl.ZIndex = 2
		iconLbl.Parent = btn

		-- Count label (bottom-right)
		local countLbl = Instance.new("TextLabel")
		countLbl.AnchorPoint = Vector2.new(1, 1)
		countLbl.Size = UDim2.new(0, 30, 0, 16)
		countLbl.Position = UDim2.new(1, -4, 1, -2)
		countLbl.BackgroundTransparency = 1
		countLbl.TextColor3 = INV_COLORS.titleText
		countLbl.Font = Enum.Font.GothamBold
		countLbl.TextSize = 14
		countLbl.TextXAlignment = Enum.TextXAlignment.Right
		countLbl.TextStrokeTransparency = 0.5
		countLbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		countLbl.Text = ""
		countLbl.ZIndex = 3
		countLbl.Parent = btn

		slotButtons[i] = { button = btn, iconLbl = iconLbl, rarityFrame = rarityFrame, countLbl = countLbl, slotIndex = i }
	end

	-- ── Drag-and-drop state ────────────────────────────────────────────
	-- Dragging a merc slot over the player inventory transfers the stack.
	-- A plain click (no movement) also transfers.
	local DRAG_THRESHOLD = 6
	local drag = {
		active = false,
		moved = false,
		slotIndex = nil,
		startX = 0,
		startY = 0,
		ghostGui = nil,
	}

	local function destroyGhost()
		if drag.ghostGui then
			drag.ghostGui:Destroy()
			drag.ghostGui = nil
		end
	end

	local function slotHasItem(i)
		local itemName = mercEntry:GetAttribute("Slot" .. i .. "_Name")
		local count = mercEntry:GetAttribute("Slot" .. i .. "_Count")
		return typeof(itemName) == "string" and itemName ~= ""
			and typeof(count) == "number" and count > 0, itemName, count
	end

	local function createGhost(i, mx, my)
		destroyGhost()
		local has, itemName, count = slotHasItem(i)
		if not has then return end

		local ghostGui = Instance.new("ScreenGui")
		ghostGui.Name = "MercDragGhost"
		ghostGui.ResetOnSpawn = false
		ghostGui.DisplayOrder = 50
		ghostGui.IgnoreGuiInset = true
		ghostGui.Parent = playerGui

		local ghost = Instance.new("Frame")
		ghost.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
		ghost.Position = UDim2.fromOffset(mx - SLOT_SIZE / 2, my - SLOT_SIZE / 2)
		ghost.BackgroundColor3 = INV_COLORS.slotBg
		ghost.BackgroundTransparency = 0.1
		ghost.BorderSizePixel = 0
		ghost.Parent = ghostGui

		local gCorner = Instance.new("UICorner")
		gCorner.CornerRadius = UDim.new(0, 5)
		gCorner.Parent = ghost

		local gStroke = Instance.new("UIStroke")
		gStroke.Color = INV_COLORS.slotBorder
		gStroke.Thickness = 2
		gStroke.Parent = ghost

		local rarity = (_G.GetItemRarity and _G.GetItemRarity(itemName)) or "common"
		local frameAsset = (_G.GetRarityFrameAsset and _G.GetRarityFrameAsset(rarity)) or ""
		local iconAsset = (_G.GetItemIcon and _G.GetItemIcon(itemName)) or ""

		if frameAsset ~= "" then
			local gFrame = Instance.new("ImageLabel")
			gFrame.AnchorPoint = Vector2.new(0.5, 0.5)
			gFrame.Size = UDim2.new(1, 0, 1, 0)
			gFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
			gFrame.BackgroundTransparency = 1
			gFrame.Image = frameAsset
			gFrame.ScaleType = Enum.ScaleType.Stretch
			gFrame.ZIndex = 1
			gFrame.Parent = ghost
		end

		local gIcon = Instance.new("ImageLabel")
		gIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		gIcon.Size = UDim2.new(0.7, 0, 0.7, 0)
		gIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
		gIcon.BackgroundTransparency = 1
		gIcon.Image = iconAsset
		gIcon.ScaleType = Enum.ScaleType.Fit
		gIcon.ZIndex = 2
		gIcon.Parent = ghost

		if count > 1 then
			local gCount = Instance.new("TextLabel")
			gCount.AnchorPoint = Vector2.new(1, 1)
			gCount.Size = UDim2.new(0, 30, 0, 16)
			gCount.Position = UDim2.new(1, -4, 1, -2)
			gCount.BackgroundTransparency = 1
			gCount.TextColor3 = INV_COLORS.titleText
			gCount.Font = Enum.Font.GothamBold
			gCount.TextSize = 14
			gCount.TextXAlignment = Enum.TextXAlignment.Right
			gCount.TextStrokeTransparency = 0.5
			gCount.TextStrokeColor3 = Color3.new(0, 0, 0)
			gCount.Text = tostring(count)
			gCount.ZIndex = 3
			gCount.Parent = ghost
		end

		drag.ghostGui = ghostGui
	end

	local function resetDrag()
		destroyGhost()
		drag.active = false
		drag.moved = false
		drag.slotIndex = nil
	end

	local function transferSlot(i)
		if not slotHasItem(i) then return end
		equipEvent:FireServer("takeItem", mercName, i)
	end

	for _, info in slotButtons do
		local i = info.slotIndex
		local btn = info.button
		btn.MouseButton1Down:Connect(function()
			if not slotHasItem(i) then return end
			local m = UserInputService:GetMouseLocation()
			drag.active = true
			drag.moved = false
			drag.slotIndex = i
			drag.startX = m.X
			drag.startY = m.Y
		end)
	end

	table.insert(mercInvConns, UserInputService.InputChanged:Connect(function(input)
		if not drag.active then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local mx, my = input.Position.X, input.Position.Y
		if not drag.moved then
			local dx = mx - drag.startX
			local dy = my - drag.startY
			if dx * dx + dy * dy >= DRAG_THRESHOLD * DRAG_THRESHOLD then
				drag.moved = true
				createGhost(drag.slotIndex, mx, my)
			end
		end
		if drag.moved and drag.ghostGui then
			local ghost = drag.ghostGui:FindFirstChildWhichIsA("Frame")
			if ghost then
				ghost.Position = UDim2.fromOffset(mx - SLOT_SIZE / 2, my - SLOT_SIZE / 2)
			end
		end
	end))

	table.insert(mercInvConns, UserInputService.InputEnded:Connect(function(input)
		if not drag.active then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local i = drag.slotIndex
		local wasDrag = drag.moved
		local mx, my = input.Position.X, input.Position.Y
		resetDrag()
		if not i then return end

		if not wasDrag then
			-- Treat as a click: transfer the stack.
			transferSlot(i)
			return
		end

		-- Drag: transfer only if released over the player inventory.
		local pp = findPlayerInventoryPanel()
		if pp and mouseOverFrame(pp, mx, my) then
			transferSlot(i)
		end
	end))

	local function refreshSlots()
		local hasBackpack = (mercEntry:GetAttribute("EquippedBackpack") or "") ~= ""
		hintLabel.Text = hasBackpack and "Click or drag to take" or "Equip a backpack first"

		for i = 1, MERC_INVENTORY_SLOTS do
			local slot = slotButtons[i]
			if slot then
				local itemName = mercEntry:GetAttribute("Slot" .. i .. "_Name")
				local count = mercEntry:GetAttribute("Slot" .. i .. "_Count")
				if typeof(itemName) == "string" and itemName ~= ""
					and typeof(count) == "number" and count > 0 then
					local rarity = (_G.GetItemRarity and _G.GetItemRarity(itemName)) or "common"
					local frameAsset = (_G.GetRarityFrameAsset and _G.GetRarityFrameAsset(rarity)) or ""
					local iconAsset = (_G.GetItemIcon and _G.GetItemIcon(itemName)) or ""
					slot.rarityFrame.Image = frameAsset
					slot.rarityFrame.Visible = frameAsset ~= ""
					slot.iconLbl.Image = iconAsset
					slot.countLbl.Text = count > 1 and tostring(count) or ""
					slot.button.BackgroundColor3 = INV_COLORS.slotBg
					slot.button.BackgroundTransparency = 0
				else
					slot.rarityFrame.Visible = false
					slot.rarityFrame.Image = ""
					slot.iconLbl.Image = ""
					slot.countLbl.Text = ""
					slot.button.BackgroundColor3 = INV_COLORS.slotBg
					slot.button.BackgroundTransparency = 0.4
				end
			end
		end
	end

	refreshSlots()

	-- Live-refresh when server updates attributes
	table.insert(mercInvConns, mercEntry.AttributeChanged:Connect(function()
		refreshSlots()
	end))
	-- Close if the mercenary entry is removed
	table.insert(mercInvConns, mercEntry.AncestryChanged:Connect(function()
		if not mercEntry:IsDescendantOf(player) then
			closeMercInventory()
		end
	end))

	mercInvGui = gui
end

-- ── Command menu (ScreenGui) ────────────────────────────────────────────

local function closeCommandMenu()
	if commandMenuGui then
		commandMenuGui:Destroy()
		commandMenuGui = nil
	end
	commandMenuOpen = false
	_G.SuppressInventoryToggle = false
end

local function openCommandMenu(model)
	closeCommandMenu()
	commandMenuOpen = true
	_G.SuppressInventoryToggle = true

	local mercName = model:GetAttribute("MercName")

	local gui = Instance.new("ScreenGui")
	gui.Name = "MercCommandMenu"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.Parent = playerGui

	-- Semi-transparent background to indicate menu mode
	local bg = Instance.new("Frame")
	bg.Name = "Backdrop"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BackgroundTransparency = 0.6
	bg.BorderSizePixel = 0
	bg.Parent = gui

	-- Central panel
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.new(0, 260, 0, 216)
	panel.Position = UDim2.new(0.5, -130, 0.5, -108)
	panel.BackgroundColor3 = INV_COLORS.panelBg
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = INV_COLORS.panelBorder
	panelStroke.Thickness = 2
	panelStroke.Parent = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 36)
	title.Position = UDim2.new(0, 0, 0, 8)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "Mercenary Commands"
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = panel

	-- "Set Fishing Location" button (only shown if mercenary has a fishing rod)
	if hasFishingRod(model) then
		local btn = Instance.new("TextButton")
		btn.Name = "SetFishingBtn"
		btn.Size = UDim2.new(0.85, 0, 0, 42)
		btn.Position = UDim2.new(0.075, 0, 0, 52)
		btn.BackgroundColor3 = Color3.fromRGB(50, 140, 80)
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Text = "Set Fishing Location"
		btn.Font = Enum.Font.GothamBold
		btn.TextScaled = true
		btn.BorderSizePixel = 0
		btn.Parent = panel

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 8)
		btnCorner.Parent = btn

		btn.MouseButton1Click:Connect(function()
			closeCommandMenu()
			if mercName then
				startPlacementMode(mercName)
			end
		end)
	end

	-- "Inventory" button (open the mercenary's 6-slot backpack inventory).
	-- Only enabled when the mercenary actually has a backpack equipped.
	local mercFolder = player:FindFirstChild("Mercenaries")
	local mercEntryCmd = mercFolder and mercFolder:FindFirstChild(mercName)
	local equippedBp = mercEntryCmd and mercEntryCmd:GetAttribute("EquippedBackpack") or ""
	local hasBackpack = typeof(equippedBp) == "string" and equippedBp ~= ""

	local invBtn = Instance.new("TextButton")
	invBtn.Name = "InventoryBtn"
	invBtn.Size = UDim2.new(0.85, 0, 0, 42)
	invBtn.Position = UDim2.new(0.075, 0, 0, 104)
	invBtn.BackgroundColor3 = hasBackpack
		and Color3.fromRGB(70, 90, 150)
		or Color3.fromRGB(70, 70, 80)
	invBtn.TextColor3 = hasBackpack
		and Color3.fromRGB(255, 255, 255)
		or Color3.fromRGB(170, 170, 180)
	invBtn.Text = hasBackpack and "Inventory" or "Inventory (no backpack)"
	invBtn.Font = Enum.Font.GothamBold
	invBtn.TextScaled = true
	invBtn.BorderSizePixel = 0
	invBtn.AutoButtonColor = hasBackpack
	invBtn.Active = hasBackpack
	invBtn.Parent = panel

	local invBtnCorner = Instance.new("UICorner")
	invBtnCorner.CornerRadius = UDim.new(0, 8)
	invBtnCorner.Parent = invBtn

	if hasBackpack then
		invBtn.MouseButton1Click:Connect(function()
			closeCommandMenu()
			openMercInventory(model)
		end)
	end

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0.85, 0, 0, 36)
	closeBtn.Position = UDim2.new(0.075, 0, 1, -46)
	closeBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Text = "Close"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextScaled = true
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = panel

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 8)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		closeCommandMenu()
	end)

	commandMenuGui = gui
end

-- ── Preview circle ──────────────────────────────────────────────────────

local CIRCLE_DIAMETER = 6
local CIRCLE_COLOR_VALID = Color3.fromRGB(80, 200, 80)
local CIRCLE_COLOR_INVALID = Color3.fromRGB(200, 80, 80)
local placementValid = false -- true when circle is on the raft

local function createPreviewCircle()
	if previewCircle then previewCircle:Destroy() end

	local part = Instance.new("Part")
	part.Name = "FishingLocationPreview"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.15, CIRCLE_DIAMETER, CIRCLE_DIAMETER)
	part.Anchored = true
	part.CanCollide = false
	part.Color = CIRCLE_COLOR_VALID
	part.Material = Enum.Material.Neon
	part.Transparency = 0.4
	part.CastShadow = false
	part.Parent = workspace

	previewCircle = part
end

local function destroyPreviewCircle()
	if previewCircle then
		previewCircle:Destroy()
		previewCircle = nil
	end
end

local function moveCircleTo(worldPos)
	if not previewCircle then return end
	previewCircle.CFrame = CFrame.new(worldPos) * CFrame.Angles(0, 0, math.rad(90))
end

-- ── Placement hint UI ───────────────────────────────────────────────────

local hintGui = nil

local function showHint(text)
	if hintGui then hintGui:Destroy(); hintGui = nil end

	hintGui = Instance.new("ScreenGui")
	hintGui.Name = "FishingLocationHint"
	hintGui.ResetOnSpawn = false
	hintGui.DisplayOrder = 30
	hintGui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 400, 0, 36)
	label.Position = UDim2.new(0.5, -200, 1, -100)
	label.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = text
	label.Font = Enum.Font.Gotham
	label.TextScaled = true
	label.BorderSizePixel = 0
	label.Parent = hintGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
end

local function hideHint()
	if hintGui then
		hintGui:Destroy()
		hintGui = nil
	end
end

-- ── Raycast (raft-only) ─────────────────────────────────────────────────

local raftRayParams = RaycastParams.new()
raftRayParams.FilterType = Enum.RaycastFilterType.Include
raftRayParams.IgnoreWater = true

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

-- Returns hitPosition, isOnRaft, hitPart, localOffset
local function raycastFromMouse()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)

	local raft = getRaft()
	if raft then
		-- Only accept hits on the raft itself
		raftRayParams.FilterDescendantsInstances = {raft}
		local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, raftRayParams)
		if result then
			local localOffset = result.Instance.CFrame:PointToObjectSpace(result.Position)
			return result.Position, true, result.Instance, localOffset
		end
	end

	-- Not on raft — still return a world position so the circle follows
	-- the cursor (shown in red), but mark it as invalid.
	local allParams = RaycastParams.new()
	allParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}
	if previewCircle then table.insert(filterList, previewCircle) end
	if player.Character then table.insert(filterList, player.Character) end
	allParams.FilterDescendantsInstances = filterList
	allParams.IgnoreWater = false

	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, allParams)
	if result then
		return result.Position, false, nil, nil
	end

	-- Plane fallback at y=0
	local denom = ray.Direction.Y
	if math.abs(denom) < 0.001 then return nil, false, nil, nil end
	local t = -ray.Origin.Y / denom
	if t < 0 then return nil, false, nil, nil end
	return ray.Origin + ray.Direction * t, false, nil, nil
end

-- ── Water raycast ────────────────────────────────────────────────────────

local waterRayParams = RaycastParams.new()
waterRayParams.FilterType = Enum.RaycastFilterType.Exclude
waterRayParams.IgnoreWater = false

-- Returns hitPosition, isOnWater
local function raycastWaterFromMouse()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)

	local filterList = {}
	if previewCircle then table.insert(filterList, previewCircle) end
	if player.Character then table.insert(filterList, player.Character) end
	-- Also exclude all SpawnedMercenary models
	for _, merc in CollectionService:GetTagged("SpawnedMercenary") do
		table.insert(filterList, merc)
	end
	waterRayParams.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, waterRayParams)
	if result then
		local isWater = result.Material == Enum.Material.Water
		return result.Position, isWater
	end

	return nil, false
end

-- ── Placement mode (shared cleanup) ─────────────────────────────────────

local function stopAllPlacement()
	isPlacingLocation = false
	isPlacingCast = false
	placingMercName = nil
	pendingRaftPart = nil
	pendingRaftOffset = nil
	placementValid = false
	destroyPreviewCircle()
	hideHint()
	_G.SuppressInventoryToggle = false

	if renderConn then renderConn:Disconnect(); renderConn = nil end
	if inputConn then inputConn:Disconnect(); inputConn = nil end
	if cancelConn then cancelConn:Disconnect(); cancelConn = nil end
end

-- ── Phase 2: pick water cast target ─────────────────────────────────────

local function startCastPlacementMode()
	-- Disconnect old connections from phase 1
	if renderConn then renderConn:Disconnect(); renderConn = nil end
	if inputConn then inputConn:Disconnect(); inputConn = nil end
	if cancelConn then cancelConn:Disconnect(); cancelConn = nil end

	isPlacingLocation = false
	isPlacingCast = true
	placementValid = false

	destroyPreviewCircle()
	createPreviewCircle()
	showHint("Click on the water to cast the fishing line  |  Esc to cancel")

	renderConn = RunService.RenderStepped:Connect(function()
		if not isPlacingCast or not previewCircle then return end

		local hitPos, isWater = raycastWaterFromMouse()
		if hitPos then
			moveCircleTo(hitPos + Vector3.new(0, 0.1, 0))
			previewCircle.Transparency = 0.4
			placementValid = isWater
			previewCircle.Color = isWater and Color3.fromRGB(80, 140, 220) or CIRCLE_COLOR_INVALID
		else
			previewCircle.Transparency = 1
			placementValid = false
		end
	end)

	inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not placementValid then return end

		local hitPos, isWater = raycastWaterFromMouse()
		if not hitPos or not isWater then return end

		-- Send both the raft location and the cast target to the server
		commandEvent:FireServer(
			"setFishingLocation", placingMercName,
			pendingRaftPart, pendingRaftOffset, hitPos
		)
		stopAllPlacement()
	end)

	cancelConn = UserInputService.InputBegan:Connect(function(input, _)
		if input.KeyCode == Enum.KeyCode.Escape then
			stopAllPlacement()
		end
	end)
end

-- ── Phase 1: pick raft spot ─────────────────────────────────────────────

function startPlacementMode(mercName)
	if isPlacingLocation or isPlacingCast then stopAllPlacement() end

	isPlacingLocation = true
	placingMercName = mercName
	placementValid = false
	_G.SuppressInventoryToggle = true

	createPreviewCircle()
	showHint("Click on the raft to set fishing location  |  Esc to cancel")

	renderConn = RunService.RenderStepped:Connect(function()
		if not isPlacingLocation or not previewCircle then return end

		local hitPos, onRaft = raycastFromMouse()
		if hitPos then
			moveCircleTo(hitPos + Vector3.new(0, 0.1, 0))
			previewCircle.Transparency = 0.4
			placementValid = onRaft
			previewCircle.Color = onRaft and CIRCLE_COLOR_VALID or CIRCLE_COLOR_INVALID
		else
			previewCircle.Transparency = 1
			placementValid = false
		end
	end)

	inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not placementValid then return end

		local hitPos, onRaft, hitPart, localOffset = raycastFromMouse()
		if not hitPos or not onRaft or not hitPart then return end

		-- Save raft data and transition to phase 2
		pendingRaftPart = hitPart
		pendingRaftOffset = localOffset
		startCastPlacementMode()
	end)

	cancelConn = UserInputService.InputBegan:Connect(function(input, _)
		if input.KeyCode == Enum.KeyCode.Escape then
			stopAllPlacement()
		end
	end)
end

-- ── Hover detection: show "[E] Command" prompt ──────────────────────────

RunService.RenderStepped:Connect(function()
	if isPlacingLocation or isPlacingCast or commandMenuOpen or mercInvGui then
		if promptBillboard then destroyPrompt() end
		return
	end

	local target = mouse.Target
	local mercModel = target and getAncestorWithTag(target, "SpawnedMercenary")

	if mercModel
		and isOwnedMercenary(mercModel)
		and distanceToModel(mercModel) <= MAX_INTERACT_DISTANCE
	then
		if mercModel ~= targetMerc then
			targetMerc = mercModel
			createPrompt(mercModel)
		end
	else
		if targetMerc then
			targetMerc = nil
			destroyPrompt()
		end
	end
end)

-- ── E key interaction ───────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.E then return end

	-- Close the command menu if it's already open
	if commandMenuOpen then
		closeCommandMenu()
		return
	end

	-- Close the mercenary inventory if it's open
	if mercInvGui then
		closeMercInventory()
		return
	end

	-- Open command menu if looking at a mercenary
	if targetMerc and targetMerc.Parent then
		-- Suppress inventory toggle so it doesn't open at the same time
		_G.SuppressInventoryToggle = true
		openCommandMenu(targetMerc)
		destroyPrompt()
	end
end)
