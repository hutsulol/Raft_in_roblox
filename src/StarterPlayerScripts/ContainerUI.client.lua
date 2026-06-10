-- ContainerUI.client.lua
-- Chest UI for the Small Container. The chest slots behave like six
-- extra inventory cells:
--   * Drag an inventory stack onto a slot → lands in that exact slot.
--   * Drag a chest stack onto the player inventory → goes into inventory.
--   * Shift+LMB on a chest slot → instant move to player inventory.
--   * Shift+LMB on an inventory slot while the chest is open → push in.
-- Panel anchors to the left of the inventory CenterPanel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local containerAction = ReplicatedStorage:WaitForChild("ContainerAction")
local openContainer = ReplicatedStorage:WaitForChild("OpenContainer")

-- Chest slot count is read from the container's SlotCount attribute at
-- open time, so both the 6-slot SmallContainer and the 9-slot
-- PlasticContainer share this UI. The module-level copy is only a
-- default; openContainerUI overwrites it before any slot-iterating
-- helper runs.
local CONTAINER_SLOTS = 6

-- Палитра «Океан» из редизайна (как инвентарь).
local INV_COLORS = {
	panelTop = Color3.fromHex("54A7EC"),
	panelBg = Color3.fromHex("3A7FD0"),
	panelBorder = Color3.fromHex("1C4F8F"),
	slotTop = Color3.fromHex("BCE0F9"),
	slotBg = Color3.fromHex("A9D6F7"),
	slotBorder = Color3.fromHex("1C4F8F"),
	separator = Color3.fromHex("1C4F8F"),
	titleText = Color3.fromRGB(255, 255, 255),
	lightText = Color3.fromRGB(255, 255, 255),
	closeBg = Color3.fromHex("FF6B5A"),
}

local activeGui = nil
local activeContainer = nil
local conns = {}
local slotFrames = {}  -- [i] = TextButton for slot i; used by hit-tests

-- Tools crafted via InventoryCrafting set their TextureId at craft time;
-- the shared icon map doesn't always list them (e.g. Phone). Fall back
-- to the Tool's own TextureId inside StoredTools so the slot still shows
-- an icon for any tool, not just the ones hard-coded in TOOL_ICONS.
local function resolveItemIcon(container, itemName)
	local iconAsset = (_G.GetItemIcon and _G.GetItemIcon(itemName)) or ""
	if iconAsset ~= "" then return iconAsset end
	if not container then return "" end
	local storage = container:FindFirstChild("StoredTools")
	if not storage then return "" end
	for _, t in storage:GetChildren() do
		if t:IsA("Tool") and t.Name == itemName and t.TextureId ~= "" then
			return t.TextureId
		end
	end
	return ""
end

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

local function mouseOverFrame(frame, mx, my)
	if not frame or not frame.Parent then return false end
	-- UserInputService:GetMouseLocation() includes the GUI inset
	-- (topbar), but AbsolutePosition does not. Subtract the inset Y so
	-- the mouse coords line up with the rendered cell - same correction
	-- InventoryUI.findSlotUnderMouse applies.
	local inset = GuiService:GetGuiInset()
	local pos = frame.AbsolutePosition
	local size = frame.AbsoluteSize
	local adjY = my - inset.Y
	return mx >= pos.X and mx <= pos.X + size.X
		and adjY >= pos.Y and adjY <= pos.Y + size.Y
end

local function chestSlotUnderMouse(mx, my)
	for i = 1, CONTAINER_SLOTS do
		local f = slotFrames[i]
		if f and mouseOverFrame(f, mx, my) then
			return i
		end
	end
	return nil
end

local function closeContainer()
	disconnectAll()
	if activeGui then
		activeGui:Destroy()
		activeGui = nil
	end
	activeContainer = nil
	_G.ActiveContainer = nil
	table.clear(slotFrames)
end

_G.CloseContainer = closeContainer

local function openContainerUI(container)
	if not container or not container.Parent then return end
	closeContainer()

	activeContainer = container
	_G.ActiveContainer = container

	CONTAINER_SLOTS = container:GetAttribute("SlotCount") or 6

	if _G.OpenInventory then
		_G.OpenInventory()
	end
	local playerPanel = waitForInventoryPanel(1)

	-- Hide the crafting panel while the chest is open (same pattern the
	-- merc backpack uses).
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
			if child.Name == "CraftPanel" then child.Visible = false end
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
	panel.BackgroundColor3 = Color3.new(1, 1, 1) -- белый под градиент (он умножается)
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local panelGrad = Instance.new("UIGradient")
	panelGrad.Rotation = 90
	panelGrad.Color = ColorSequence.new(INV_COLORS.panelTop, INV_COLORS.panelBg)
	panelGrad.Parent = panel

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

	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
	local stroke = Instance.new("UIStroke")
	stroke.Color = INV_COLORS.panelBorder
	stroke.Thickness = 4
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, PAD, 0, 8)
	title.BackgroundTransparency = 1
	title.TextColor3 = INV_COLORS.titleText
	title.Text = "Container"
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.TextStrokeTransparency = 0.6
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -PAD * 2, 0, 2)
	sep.Position = UDim2.new(0, PAD, 0, 42)
	sep.BackgroundColor3 = INV_COLORS.separator
	sep.BorderSizePixel = 0
	sep.Parent = panel

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(30, 30)
	closeBtn.Position = UDim2.new(1, -36, 0, 8)
	closeBtn.BackgroundColor3 = INV_COLORS.closeBg
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Text = "✕"
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextSize = 16
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = panel
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 10)
	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Color3.fromHex("8A2A12")
	closeStroke.Thickness = 3
	closeStroke.Parent = closeBtn
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
	hint.Text = "Drag or Shift+Click to move items between chest and inventory."
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.Parent = panel

	-- Explicit slot positions — direct children of the panel. Identical
	-- layout pattern to the merc backpack; avoids any layout-container
	-- offset that could drift AbsolutePosition away from the rendered
	-- cell.
	local slotVisuals = {}
	for i = 1, CONTAINER_SLOTS do
		local col = (i - 1) % COLS
		local row = math.floor((i - 1) / COLS)
		local x = PAD + col * (SLOT_SIZE + SLOT_PAD)
		local y = GRID_Y + row * (SLOT_SIZE + SLOT_PAD)

		local btn = Instance.new("TextButton")
		btn.Name = "Slot" .. i
		btn.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
		btn.Position = UDim2.new(0, x, 0, y)
		btn.BackgroundColor3 = Color3.new(1, 1, 1) -- белый под градиент
		btn.BackgroundTransparency = 0.1
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = false
		btn.Text = ""
		btn.Active = true
		btn.Parent = panel

		local slotGrad = Instance.new("UIGradient")
		slotGrad.Rotation = 90
		slotGrad.Color = ColorSequence.new(INV_COLORS.slotTop, INV_COLORS.slotBg)
		slotGrad.Parent = btn

		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
		local bs = Instance.new("UIStroke")
		bs.Color = INV_COLORS.slotBorder
		bs.Thickness = 3
		bs.Parent = btn

		local iconLbl = Instance.new("ImageLabel")
		iconLbl.Name = "ItemIcon"
		iconLbl.AnchorPoint = Vector2.new(0.5, 0.5)
		iconLbl.Size = UDim2.new(0.7, 0, 0.7, 0)
		iconLbl.Position = UDim2.new(0.5, 0, 0.5, 0)
		iconLbl.BackgroundTransparency = 1
		iconLbl.ScaleType = Enum.ScaleType.Fit
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
		countLbl.Parent = btn

		slotFrames[i] = btn
		slotVisuals[i] = { button = btn, iconLbl = iconLbl, countLbl = countLbl }
	end

	-- Hover tooltip — mirrors the inventory's behaviour (name shown
	-- above the cursor, follows the mouse, hides while dragging).
	local tooltipGui = Instance.new("ScreenGui")
	tooltipGui.Name = "ContainerTooltip"
	tooltipGui.ResetOnSpawn = false
	tooltipGui.IgnoreGuiInset = true
	tooltipGui.DisplayOrder = 201
	tooltipGui.Enabled = false
	tooltipGui.Parent = playerGui
	table.insert(conns, { Disconnect = function() tooltipGui:Destroy() end })

	local tooltipLabel = Instance.new("TextLabel")
	tooltipLabel.Name = "Label"
	tooltipLabel.AutomaticSize = Enum.AutomaticSize.XY
	tooltipLabel.Size = UDim2.new(0, 0, 0, 0)
	tooltipLabel.BackgroundColor3 = INV_COLORS.panelBorder
	tooltipLabel.BackgroundTransparency = 0.05
	tooltipLabel.BorderSizePixel = 0
	tooltipLabel.TextColor3 = Color3.new(1, 1, 1)
	tooltipLabel.Font = Enum.Font.GothamBold
	tooltipLabel.TextSize = 14
	tooltipLabel.Text = ""
	tooltipLabel.Parent = tooltipGui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = tooltipLabel
	Instance.new("UICorner", tooltipLabel).CornerRadius = UDim.new(0, 8)
	local tstroke = Instance.new("UIStroke")
	tstroke.Color = Color3.fromHex("0F2C52")
	tstroke.Thickness = 2
	tstroke.Parent = tooltipLabel

	local function updateTooltipPos(mousePos)
		if not tooltipGui.Enabled then return end
		local x = mousePos.X + 14
		local y = mousePos.Y - tooltipLabel.AbsoluteSize.Y - 10
		if y < 4 then y = mousePos.Y + 18 end
		tooltipLabel.Position = UDim2.fromOffset(x, y)
	end

	local function hideTooltip()
		tooltipGui.Enabled = false
	end

	local function showTooltipForSlot(i)
		local name = activeContainer and activeContainer:GetAttribute("Slot" .. i .. "_Name")
		local count = activeContainer and (activeContainer:GetAttribute("Slot" .. i .. "_Count") or 0)
		if typeof(name) ~= "string" or name == "" or count <= 0 then
			hideTooltip()
			return
		end
		local display = _G.GetItemDisplayName and _G.GetItemDisplayName(name)
		if not display or display == "" then
			hideTooltip()
			return
		end
		tooltipLabel.Text = display
		tooltipGui.Enabled = true
		updateTooltipPos(UserInputService:GetMouseLocation())
	end

	local function refreshSlots()
		if not activeContainer or not activeContainer.Parent then
			closeContainer()
			return
		end
		for i = 1, CONTAINER_SLOTS do
			local s = slotVisuals[i]
			if not s then continue end
			local name = activeContainer:GetAttribute("Slot" .. i .. "_Name")
			local count = activeContainer:GetAttribute("Slot" .. i .. "_Count") or 0

			if typeof(name) == "string" and name ~= "" and count > 0 then
				s.iconLbl.Image = resolveItemIcon(activeContainer, name)
				s.countLbl.Text = count > 1 and tostring(count) or ""
			else
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

	-- ── Chest-slot interactions ───────────────────────────────────────
	-- Each slot supports three gestures:
	--   1. Shift + LMB  → instant take
	--   2. Drag (LMB down, mouse move past threshold, LMB up):
	--        • Release over player inventory CenterPanel → take
	--        • Release over another chest slot → swap (take then put)
	--        • Release elsewhere → cancel
	--   3. Plain click (no drag, no shift) → does nothing, so players
	--      can't accidentally drain the chest with a single click.

	local DRAG_THRESHOLD = 6
	local drag = {
		active = false,
		moved = false,
		slotIndex = nil,
		startX = 0,
		startY = 0,
		ghostGui = nil,
	}

	local function destroyDragGhost()
		if drag.ghostGui then
			drag.ghostGui:Destroy()
			drag.ghostGui = nil
		end
	end

	local function slotHas(i)
		local name = activeContainer:GetAttribute("Slot" .. i .. "_Name")
		local count = activeContainer:GetAttribute("Slot" .. i .. "_Count") or 0
		return typeof(name) == "string" and name ~= "" and count > 0, name, count
	end

	local function createDragGhost(i, mx, my)
		destroyDragGhost()
		local has, itemName, count = slotHas(i)
		if not has then return end

		local ghostGui = Instance.new("ScreenGui")
		ghostGui.Name = "ContainerDragGhost"
		ghostGui.ResetOnSpawn = false
		ghostGui.DisplayOrder = 50
		ghostGui.IgnoreGuiInset = true
		ghostGui.Parent = playerGui

		local ghost = Instance.new("Frame")
		ghost.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
		ghost.Position = UDim2.fromOffset(mx - SLOT_SIZE / 2, my - SLOT_SIZE / 2)
		ghost.BackgroundTransparency = 1
		ghost.BorderSizePixel = 0
		ghost.Parent = ghostGui

		local iconAsset = resolveItemIcon(activeContainer, itemName)

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
			gCount.TextColor3 = INV_COLORS.lightText
			gCount.Font = Enum.Font.GothamBold
			gCount.TextSize = 13
			gCount.TextXAlignment = Enum.TextXAlignment.Right
			gCount.TextStrokeTransparency = 0.3
			gCount.TextStrokeColor3 = Color3.new(0, 0, 0)
			gCount.Text = tostring(count)
			gCount.ZIndex = 3
			gCount.Parent = ghost
		end

		drag.ghostGui = ghostGui
	end

	local function resetDrag()
		destroyDragGhost()
		drag.active = false
		drag.moved = false
		drag.slotIndex = nil
	end

	local function mouseOverPlayerInventory(mx, my)
		local pp = findPlayerInventoryPanel()
		if not pp or not pp.Parent then return false end
		local inset = GuiService:GetGuiInset()
		local pos = pp.AbsolutePosition
		local size = pp.AbsoluteSize
		local adjY = my - inset.Y
		return mx >= pos.X and mx <= pos.X + size.X
			and adjY >= pos.Y and adjY <= pos.Y + size.Y
	end

	for i = 1, CONTAINER_SLOTS do
		local btn = slotFrames[i]
		btn.MouseEnter:Connect(function()
			if drag.active then return end
			showTooltipForSlot(i)
		end)
		btn.MouseLeave:Connect(function()
			hideTooltip()
		end)
		btn.MouseButton1Down:Connect(function()
			local has = slotHas(i)
			if not has then return end
			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shift then
				containerAction:FireServer("take", activeContainer, i)
				return
			end
			local m = UserInputService:GetMouseLocation()
			drag.active = true
			drag.moved = false
			drag.slotIndex = i
			drag.startX = m.X
			drag.startY = m.Y
			hideTooltip()
		end)
	end

	table.insert(conns, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local m = UserInputService:GetMouseLocation()
		if tooltipGui.Enabled then
			updateTooltipPos(m)
		end
		if not drag.active then return end
		if not drag.moved then
			local dx = m.X - drag.startX
			local dy = m.Y - drag.startY
			if dx * dx + dy * dy >= DRAG_THRESHOLD * DRAG_THRESHOLD then
				drag.moved = true
				createDragGhost(drag.slotIndex, m.X, m.Y)
			end
		end
		if drag.ghostGui then
			local ghost = drag.ghostGui:FindFirstChildOfClass("Frame")
			if ghost then
				ghost.Position = UDim2.fromOffset(m.X - SLOT_SIZE / 2, m.Y - SLOT_SIZE / 2)
			end
		end
	end))

	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		if not drag.active then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local srcSlot = drag.slotIndex
		local moved = drag.moved
		resetDrag()
		if not srcSlot or not moved then return end

		local m = UserInputService:GetMouseLocation()

		-- Release on another chest slot → take-then-put swap via server
		local destSlot = chestSlotUnderMouse(m.X, m.Y)
		if destSlot and destSlot ~= srcSlot then
			containerAction:FireServer("move", activeContainer, srcSlot, destSlot)
			return
		end

		-- Release over player inventory OR hotbar → take. The hotbar is
		-- a separate ScreenGui so mouseOverPlayerInventory alone misses
		-- it; fall back to any slot the mouse is over (hotbar slots
		-- 1..HOTBAR_SLOTS count as valid drop targets too).
		local targetInvSlot = nil
		if typeof(_G.FindInventorySlotUnderMouse) == "function" then
			targetInvSlot = _G.FindInventorySlotUnderMouse(m)
		end
		if mouseOverPlayerInventory(m.X, m.Y) or targetInvSlot then
			local srcName = activeContainer:GetAttribute("Slot" .. srcSlot .. "_Name")
			if targetInvSlot and typeof(srcName) == "string" and srcName ~= "" then
				_G.PendingTargetSlot = { name = srcName, slot = targetInvSlot }
			end
			containerAction:FireServer("take", activeContainer, srcSlot)
		end
	end))
end

openContainer.OnClientEvent:Connect(function(container)
	if typeof(container) ~= "Instance" then return end
	openContainerUI(container)
end)

-- E / Escape close the chest + inventory together. We set
-- SuppressInventoryToggle before closing so InventoryUI's own
-- task.defer'd E toggle (which can't know we're closing in the
-- same frame) doesn't race us and flip the inventory back open.
-- The flag is cleared after a short delay so a subsequent E press
-- can re-open the inventory normally.
UserInputService.InputBegan:Connect(function(input)
	if not activeGui then return end
	if input.KeyCode ~= Enum.KeyCode.E
		and input.KeyCode ~= Enum.KeyCode.Escape then
		return
	end
	_G.SuppressInventoryToggle = true
	if _G.CloseInventory then _G.CloseInventory() end
	closeContainer()
	task.delay(0.25, function()
		_G.SuppressInventoryToggle = false
	end)
end)

-- Shift-click a player inventory/hotbar slot while chest is open →
-- push that stack in. InventoryUI.quickTransfer calls this hook.
-- kind = "resource" (default) or "tool" so the server knows whether
-- to drain the resource inv or move Tool instances out of Backpack.
_G.ContainerTransferFromPlayer = function(itemName, count, kind)
	if not activeContainer then return false end
	if typeof(itemName) ~= "string" or itemName == "" then return false end
	containerAction:FireServer("put", activeContainer, nil, itemName, count or 1, kind or "resource")
	return true
end

-- Called by InventoryUI.endDrag: if the mouse release is over one of
-- this chest's slots, fire 'put' targeting that exact slot.
_G.ContainerTryDrop = function(mousePos, itemName, count, kind)
	if not activeContainer or not activeGui then return false end
	if typeof(itemName) ~= "string" or itemName == "" then return false end
	local i = chestSlotUnderMouse(mousePos.X, mousePos.Y)
	if not i then return false end
	containerAction:FireServer("put", activeContainer, i, itemName, count or 1, kind or "resource")
	return true
end
