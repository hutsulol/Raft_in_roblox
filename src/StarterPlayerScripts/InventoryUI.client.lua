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
local PLASTIC_ICON = "rbxassetid://132919988751848"
local STONE_ICON = "rbxassetid://134781813180973"
local IRON_ORE_ICON = "rbxassetid://73676755288746"
local IRON_INGOT_ICON = "rbxassetid://72890243946368"
local LEAVES_ICON = "rbxassetid://78493803156432"

local PLANK_ICON = "rbxassetid://118108820731466"
local ROPE_ICON = "rbxassetid://78492721752628"
local SAND_ICON = "rbxassetid://96142393982330"
local CLAY_ICON = "rbxassetid://70464196671282"
local WET_BRICK_ICON = "rbxassetid://77999856849195"
local DRY_BRICK_ICON = "rbxassetid://129896663405682"

local BLUE_FISH_ICON = "rbxassetid://95052485461834"
local CARP_FISH_ICON = "rbxassetid://122853256629696"
local FISH_BONES_ICON = "rbxassetid://118274743954023"
local FOIL_FISH_ICON = "rbxassetid://86978570169083"
local JELLY_FISH_ICON = "rbxassetid://139713210103014"
local LEGENDARY_FISH_ICON = "rbxassetid://73775072217611"
local SEABASS_FISH_ICON = "rbxassetid://112734818459787"
local TILAPIA_FISH_ICON = "rbxassetid://128104970819877"

local RESOURCE_ICONS = {
	Log = LOG_ICON,
	Plastic = PLASTIC_ICON,
	Stone = STONE_ICON,
	Iron_Ore = IRON_ORE_ICON,
	Iron_Ingot = IRON_INGOT_ICON,
	Plank = PLANK_ICON,
	Leaves = LEAVES_ICON,
	Rope = ROPE_ICON,
	Sand = SAND_ICON,
	Clay = CLAY_ICON,
	Wet_Brick = WET_BRICK_ICON,
	Dry_Brick = DRY_BRICK_ICON,
	Blue_Fish = BLUE_FISH_ICON,
	Carp_Fish = CARP_FISH_ICON,
	Fish_Bones = FISH_BONES_ICON,
	Foil_Fish = FOIL_FISH_ICON,
	Jelly_Fish = JELLY_FISH_ICON,
	Legendary_Fish = LEGENDARY_FISH_ICON,
	Seabass_Fish = SEABASS_FISH_ICON,
	Tilapia_Fish = TILAPIA_FISH_ICON,
}

local TOOL_ICONS = {
	["Hammer"] = "rbxassetid://96978301002259",
	["Pick-Axe"] = "rbxassetid://89809613033816",
	["Cup"] = "rbxassetid://99673504095026",
	["Destitalor"] = "rbxassetid://90221080738714",
	["Furnace"] = "rbxassetid://117760352651529",
	["bush"] = "rbxassetid://100755665041729",
	["Wooden_Spear"] = "rbxassetid://110032041583533",
	["Machete"] = "rbxassetid://114406082138691",
	["Wood_Knife"] = "rbxassetid://110032041583533",
	["WorkBench"] = "rbxassetid://104306543647624",
	["Bed"] = "rbxassetid://85069521486600",
	["Garden"] = "rbxassetid://77159786623285",
	["Paddle"] = "rbxassetid://93358108538106",
	["Sawmill"] = "rbxassetid://75858978626954",
	["Shovel"] = "rbxassetid://91548954831391",
	["Hook"] = "rbxassetid://110032041583533",
	["Axe"] = "rbxassetid://110032041583533",
	["[GRAPES]"] = "rbxassetid://137478230275649",
	["Grapes"] = "rbxassetid://137478230275649",
}

-- ── Item rarity ────────────────────────────────────────────────────────
-- Each rarity has its own inventory-slot background frame. Items not
-- listed in ITEM_RARITY default to "common".
local RARITY_FRAMES = {
	common = "rbxassetid://134988922333958",
	rare = "rbxassetid://79767754854530",
	super_rare = "rbxassetid://97396474395148",
}

local ITEM_RARITY = {
	FishingRod = "rare",
}

local function getItemRarity(itemName)
	return (itemName and ITEM_RARITY[itemName]) or "common"
end

_G.GetItemRarity = getItemRarity
_G.GetRarityFrameAsset = function(rarity)
	return RARITY_FRAMES[rarity] or RARITY_FRAMES.common
end

-- Exposed so the mercenary backpack UI can reuse the same icons.
_G.GetItemIcon = function(itemName)
	if not itemName then return "" end
	return RESOURCE_ICONS[itemName] or TOOL_ICONS[itemName] or ""
end

local inventory = {Log = 0, Plastic = 0, Stone = 0, Iron_Ore = 0, Iron_Ingot = 0, Leaves = 0}
local recipes = {}
local selectedRecipe = nil
local selectedCategory = nil
local detailOverlay = nil
local categoryOverlay = nil
local CATEGORIES = {"Tools", "Technology", "Misc", "Resources"}
local CATEGORY_ICONS = {
	Tools = "rbxassetid://134299753320707",
	Technology = "rbxassetid://105024067653272",
	Misc = "rbxassetid://122082071100473",
	Resources = "rbxassetid://122082071100473",
}
local isOpen = false
local screenGui = nil
local hotbarGui = nil

-- Palette mirrors the Phone menu (dark navy + cyan accents).
local COLORS = {
	panelBg = Color3.fromRGB(10, 25, 55),
	panelBorder = Color3.fromRGB(80, 180, 255),
	slotBg = Color3.fromRGB(15, 35, 70),
	slotBorder = Color3.fromRGB(80, 180, 255),
	titleText = Color3.fromRGB(220, 240, 255),
	lightText = Color3.fromRGB(220, 240, 255),
	craftPanelBg = Color3.fromRGB(10, 25, 55),
	craftItemBg = Color3.fromRGB(15, 35, 70),
	craftItemHover = Color3.fromRGB(30, 60, 110),
	affordable = Color3.fromRGB(70, 180, 120),
	notAffordable = Color3.fromRGB(200, 80, 80),
	hotbarBg = Color3.fromRGB(10, 25, 55),
	separator = Color3.fromRGB(80, 180, 255),
	equipped = Color3.fromRGB(120, 210, 255),
}

local HOTBAR_SLOTS = 8
local GRID_SLOTS = 20
local TOTAL_SLOTS = HOTBAR_SLOTS + GRID_SLOTS
local SLOT_SIZE = 140
local SLOT_PAD = 14
local COLS = 5
local BASE_UNLOCKED_SLOTS = HOTBAR_SLOTS + 5 -- hotbar + first grid row until Strength unlocks more

-- How many total slots (hotbar + grid) the player currently has unlocked.
-- Driven by `Characteristics.UnlockedInventorySlots` which is computed from
-- the player's Strength stat by Strength.server.lua. Defaults to the
-- base 13 so the UI is usable before the value replicates.
local unlockedSlots = BASE_UNLOCKED_SLOTS

-- Populated while the inventory window is built. Each entry is a
-- { button = TextButton, stroke = UIStroke } record for the grid slot
-- at `HOTBAR_SLOTS + i`. Used by applyUnlockedSlots() to repaint the
-- locked / unlocked visuals whenever the unlocked-count changes.
local gridSlotVisuals = {}
local lockedOverlayLabel = nil

local function isSlotLocked(globalIdx)
	return globalIdx > unlockedSlots
end

-- Highest grid slot index (global) that writes are allowed to touch.
-- Used to clamp `findEmptySlot` / distribution ranges so that new items
-- never land in a locked slot.
local function maxWritableSlot()
	return math.min(TOTAL_SLOTS, unlockedSlots)
end

-- Repaints every grid slot for the current `unlockedSlots` count and
-- positions the big "NEED STRENGTH" overlay over the locked region.
-- Called whenever `Characteristics.UnlockedInventorySlots` changes and
-- once after the inventory UI is built.
local function applyUnlockedSlots()
	if #gridSlotVisuals == 0 then return end

	for i, rec in ipairs(gridSlotVisuals) do
		local globalIdx = HOTBAR_SLOTS + i
		local locked    = globalIdx > unlockedSlots
		if rec.button then
			rec.button.BackgroundTransparency = locked and 0.55 or 0.05
			rec.button.AutoButtonColor        = false
			rec.button.Active                 = not locked
		end
		if rec.stroke then
			rec.stroke.Transparency = locked and 0.7 or 0
		end
	end

	if lockedOverlayLabel then
		-- Only span rows whose slots are ALL locked. A row that's still
		-- partially usable keeps its normal per-slot dimming instead of
		-- being covered by the banner (otherwise the banner would
		-- obscure the slots the player can still interact with).
		--
		-- The banner is only shown while the player is still at the
		-- base unlock count (Strength 0). The instant they upgrade
		-- Strength to level 2 and earn their first extra slot, the
		-- banner disappears for good — by then they already know how
		-- to get more slots and the reminder becomes visual noise.
		local unlockedGrid      = math.max(unlockedSlots - HOTBAR_SLOTS, 0)
		local firstFullLockRow  = math.ceil(unlockedGrid / COLS)
		local totalRows         = math.ceil(GRID_SLOTS / COLS)
		local atBaseUnlock      = unlockedSlots <= BASE_UNLOCKED_SLOTS

		if atBaseUnlock and firstFullLockRow < totalRows then
			local rows = totalRows - firstFullLockRow
			local y = SLOT_PAD + firstFullLockRow * (SLOT_SIZE + SLOT_PAD)
			local h = rows * (SLOT_SIZE + SLOT_PAD) - SLOT_PAD
			lockedOverlayLabel.Position = UDim2.new(0, SLOT_PAD, 0, y)
			lockedOverlayLabel.Size     = UDim2.new(1, -SLOT_PAD * 2, 0, h)
			lockedOverlayLabel.Visible  = true
		else
			lockedOverlayLabel.Visible = false
		end
	end
end

-- ─── Unified Slot Data ───
-- Slots 1..8 = hotbar, slots 9..28 = inventory grid
local slotData = {}
_G.InventorySlotData = slotData
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

-- ─── Tooltip ───
local tooltipGui = nil
local tooltipLabel = nil

local DISPLAY_NAMES = {
	Iron_Ore = "Iron Ore",
	Iron_Ingot = "Iron Ingot",
	Wet_Brick = "Wet Brick",
	Dry_Brick = "Dry Brick",
	["Pick-Axe"] = "Pick-Axe",
	WorkBench = "Workbench",
	Wooden_Spear = "Wooden Spear",
	Wood_Knife = "Wood Knife",
}

local function getDisplayName(data)
	if not data then return nil end
	local key = data.name or data.toolName
	if not key then return nil end
	if DISPLAY_NAMES[key] then return DISPLAY_NAMES[key] end
	return (key:gsub("_", " "))
end

local function ensureTooltipGui()
	if tooltipGui and tooltipGui.Parent then return end
	tooltipGui = Instance.new("ScreenGui")
	tooltipGui.Name = "InventoryTooltip"
	tooltipGui.ResetOnSpawn = false
	tooltipGui.IgnoreGuiInset = true
	tooltipGui.DisplayOrder = 200
	tooltipGui.Enabled = false
	tooltipGui.Parent = playerGui

	tooltipLabel = Instance.new("TextLabel")
	tooltipLabel.Name = "Label"
	tooltipLabel.AutomaticSize = Enum.AutomaticSize.XY
	tooltipLabel.Size = UDim2.new(0, 0, 0, 0)
	tooltipLabel.BackgroundColor3 = COLORS.panelBg
	tooltipLabel.BackgroundTransparency = 0.1
	tooltipLabel.BorderSizePixel = 0
	tooltipLabel.TextColor3 = COLORS.titleText
	tooltipLabel.Font = Enum.Font.GothamMedium
	tooltipLabel.TextSize = 14
	tooltipLabel.Text = ""
	tooltipLabel.Parent = tooltipGui

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = tooltipLabel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = tooltipLabel

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.panelBorder
	stroke.Thickness = 1
	stroke.Parent = tooltipLabel
end

local function hideTooltip()
	if tooltipGui then tooltipGui.Enabled = false end
end

-- Short-lived popup used when the player tries to drop an item into a
-- locked inventory slot. Lives in its own ScreenGui so it doesn't mess
-- with the regular hover tooltip, and auto-destroys after fading out.
local function showLockedDropMessage(mousePos)
	local gui = Instance.new("ScreenGui")
	gui.Name = "LockedSlotPopup"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 250
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundColor3 = Color3.fromRGB(40, 15, 15)
	label.BackgroundTransparency = 0.1
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(255, 220, 180)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Text = "Slot blocked, upgrade your strength"
	label.Parent = gui

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft   = UDim.new(0, 10)
	pad.PaddingRight  = UDim.new(0, 10)
	pad.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(180, 90, 90)
	stroke.Thickness = 1.5
	stroke.Parent = label

	-- Position near the mouse; flip below if it would overflow the top.
	label.Position = UDim2.fromOffset(mousePos.X + 14, mousePos.Y - 34)
	task.defer(function()
		if label.AbsolutePosition.Y < 4 then
			label.Position = UDim2.fromOffset(mousePos.X + 14, mousePos.Y + 18)
		end
	end)

	task.delay(0.9, function()
		if not gui.Parent then return end
		local t = TweenService:Create(
			label,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1, TextTransparency = 1 }
		)
		stroke.Enabled = false
		t:Play()
		t.Completed:Connect(function()
			gui:Destroy()
		end)
	end)
end

local function updateTooltipPosition(mousePos)
	if not tooltipGui or not tooltipGui.Enabled or not tooltipLabel then return end
	local x = mousePos.X + 14
	local y = mousePos.Y - tooltipLabel.AbsoluteSize.Y - 10
	if y < 4 then y = mousePos.Y + 18 end
	tooltipLabel.Position = UDim2.fromOffset(x, y)
end

local function showTooltipForSlot(slotIndex)
	local data = slotData[slotIndex]
	local name = getDisplayName(data)
	if not name then
		hideTooltip()
		return
	end
	if dragState.active then
		hideTooltip()
		return
	end
	-- Don't show tooltip while crafting overlays cover the inventory
	if categoryOverlay or detailOverlay then
		hideTooltip()
		return
	end
	ensureTooltipGui()
	tooltipLabel.Text = name
	tooltipGui.Enabled = true
	updateTooltipPosition(UserInputService:GetMouseLocation())
end

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

-- Update resource slots: preserve existing layout, only add/remove the difference
local function distributeResource(name, totalCount, icon)
	-- Find all existing slots with this resource
	local existingSlots = {}
	local currentTotal = 0
	for i = 1, TOTAL_SLOTS do
		if slotData[i] and slotData[i].type == "resource" and slotData[i].name == name then
			table.insert(existingSlots, i)
			currentTotal = currentTotal + slotData[i].count
		end
	end

	local diff = totalCount - currentTotal

	if diff == 0 then return end

	if diff > 0 then
		-- Adding items: fill last non-full slot first, then create new slots
		local added = 0
		-- Try to add to existing slots that aren't full (last ones first for natural stacking)
		for j = #existingSlots, 1, -1 do
			local idx = existingSlots[j]
			local space = MAX_STACK - slotData[idx].count
			if space > 0 then
				local toAdd = math.min(diff - added, space)
				slotData[idx].count = slotData[idx].count + toAdd
				added = added + toAdd
				if added >= diff then break end
			end
		end

		-- Still need more? Create new slots
		while added < diff do
			local empty = findEmptySlot(1, HOTBAR_SLOTS) or findEmptySlot(HOTBAR_SLOTS + 1, maxWritableSlot())
			if not empty then break end
			local amount = math.min(diff - added, MAX_STACK)
			slotData[empty] = {type = "resource", name = name, count = amount, icon = icon}
			added = added + amount
		end
	else
		-- Removing items: take from last slots first
		local toRemove = -diff
		for j = #existingSlots, 1, -1 do
			local idx = existingSlots[j]
			if toRemove >= slotData[idx].count then
				toRemove = toRemove - slotData[idx].count
				slotData[idx] = nil
			else
				slotData[idx].count = slotData[idx].count - toRemove
				toRemove = 0
			end
			if toRemove <= 0 then break end
		end
	end
end

local function updateResourceSlots(name, count, icon)
	if count > 0 then
		distributeResource(name, count, icon)
	else
		for i = 1, TOTAL_SLOTS do
			if slotData[i] and slotData[i].type == "resource" and slotData[i].name == name then
				slotData[i] = nil
			end
		end
	end
end

local function rebuildSlotData()
	local tools = getToolList()

	if not slotsInitialized then
		for i = 1, TOTAL_SLOTS do slotData[i] = nil end

		for resName, resIcon in RESOURCE_ICONS do
			local count = inventory[resName] or 0
			if count > 0 then
				distributeResource(resName, count, resIcon)
			end
		end

		-- Count duplicate tools for stacking
		local toolCounts = {}
		for _, tool in tools do
			toolCounts[tool.Name] = (toolCounts[tool.Name] or 0) + 1
		end

		local slot = 2
		local addedTools = {}
		for _, tool in tools do
			if not addedTools[tool.Name] then
				addedTools[tool.Name] = true
				while slot <= HOTBAR_SLOTS and slotData[slot] do
					slot = slot + 1
				end
				if slot > HOTBAR_SLOTS then break end
				local toolIcon = TOOL_ICONS[tool.Name] or (tool.TextureId ~= "" and tool.TextureId) or LOG_ICON
				slotData[slot] = {type = "tool", name = tool.Name, toolName = tool.Name, icon = toolIcon, count = toolCounts[tool.Name]}
				slot = slot + 1
			end
		end

		slotsInitialized = true
		return
	end

	-- Update all resources
	for resName, resIcon in RESOURCE_ICONS do
		updateResourceSlots(resName, inventory[resName] or 0, resIcon)
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

	-- Add new tools (count duplicates for stacking)
	local toolCounts = {}
	for _, tool in tools do
		toolCounts[tool.Name] = (toolCounts[tool.Name] or 0) + 1
	end

	for _, tool in tools do
		local existing = findItemSlot("tool", tool.Name)
		if existing then
			-- Update count for stackable tools
			slotData[existing].count = toolCounts[tool.Name]
		else
			local toolIcon = TOOL_ICONS[tool.Name] or (tool.TextureId ~= "" and tool.TextureId) or LOG_ICON
			local entry = {type = "tool", name = tool.Name, toolName = tool.Name, icon = toolIcon, count = toolCounts[tool.Name]}
			local empty = findEmptySlot(1, HOTBAR_SLOTS) or findEmptySlot(HOTBAR_SLOTS + 1, maxWritableSlot())
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

	-- Rarity background fills the slot; item icon sits on top of it.
	local rarityFrame = Instance.new("ImageLabel")
	rarityFrame.Name = "RarityFrame"
	rarityFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	rarityFrame.Size = UDim2.new(1, 0, 1, 0)
	rarityFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	rarityFrame.BackgroundTransparency = 1
	rarityFrame.Image = RARITY_FRAMES[getItemRarity(data.name)] or RARITY_FRAMES.common
	rarityFrame.ScaleType = Enum.ScaleType.Stretch
	rarityFrame.ZIndex = 1
	rarityFrame.Parent = slot

	local img = Instance.new("ImageLabel")
	img.Name = "ItemIcon"
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Size = UDim2.new(0.7, 0, 0.7, 0)
	img.Position = UDim2.new(0.5, 0, 0.5, 0)
	img.BackgroundTransparency = 1
	img.Image = data.icon or ""
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = 2
	img.Parent = slot

	if data.count and data.count > 1 then
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
		count.ZIndex = 3
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

		local lc = screenGui:FindFirstChild("LogCount", true)
		if lc then lc.Text = tostring(inventory.Log or 0) end
		local pc = screenGui:FindFirstChild("PlasticCount", true)
		if pc then pc.Text = tostring(inventory.Plastic or 0) end
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
	hideTooltip()

	local data = dragState.data
	local ghostGui = Instance.new("ScreenGui")
	ghostGui.Name = "DragGhost"
	ghostGui.DisplayOrder = 100
	ghostGui.IgnoreGuiInset = true
	ghostGui.Parent = playerGui

	local ghost = Instance.new("ImageLabel")
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Size = UDim2.new(0, SLOT_SIZE - 8, 0, SLOT_SIZE - 8)
	ghost.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y)
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
		dragState.ghost.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y)
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

	-- Drops onto locked grid slots are cancelled outright: nothing moves,
	-- nothing is dropped into the world, and we flash a "Slot blocked"
	-- popup at the drop point. We short-circuit here so the drag simply
	-- snaps back to the source slot on the next render.
	if targetSlot and isSlotLocked(targetSlot) then
		showLockedDropMessage(mousePos)
		cancelDrag()
		dragState.didDrag = true
		renderAllSlots()
		return
	end

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
	elseif not targetSlot and srcSlot then
		-- Dropped outside any slot: drop item into the world
		local srcData = slotData[srcSlot]
		if srcData then
			local dropEvt = ReplicatedStorage:FindFirstChild("DropItem")
			if dropEvt then
				-- Raycast from mouse to find drop position in the world
				local cam = workspace.CurrentCamera
				local mPos = UserInputService:GetMouseLocation()
				local ray = cam:ViewportPointToRay(mPos.X, mPos.Y)
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				local char = player.Character
				if char then rayParams.FilterDescendantsInstances = {char} end
				local result = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
				local dropPos = result and result.Position or nil

				if srcData.type == "resource" then
					local dropCount = isSplit and 1 or srcData.count
					if dropCount >= srcData.count then
						slotData[srcSlot] = nil
					else
						srcData.count = srcData.count - dropCount
					end
					dropEvt:FireServer(srcData.name, dropCount, dropPos)
				elseif srcData.type == "tool" then
					slotData[srcSlot] = nil
					dropEvt:FireServer(srcData.toolName, 1, dropPos)
				end
			end
		end
	end

	cancelDrag()
	dragState.didDrag = true
	renderAllSlots()
end

-- ─── Quick-transfer: Shift+click moves item between hotbar and grid ───
local function quickTransfer(slotIndex)
	local data = slotData[slotIndex]
	if not data then return end

	local isHotbar = slotIndex >= 1 and slotIndex <= HOTBAR_SLOTS
	local targetStart, targetEnd

	if isHotbar then
		-- From hotbar → inventory grid
		if not isOpen then return end -- grid must be open
		targetStart = HOTBAR_SLOTS + 1
		targetEnd = maxWritableSlot()
	else
		-- From inventory grid → hotbar
		targetStart = 1
		targetEnd = HOTBAR_SLOTS
	end

	-- For resources, try to stack first with same item in target area
	if data.type == "resource" then
		local remaining = data.count
		-- Stack into existing slots of same type
		for i = targetStart, targetEnd do
			if remaining <= 0 then break end
			if slotData[i] and slotData[i].type == "resource" and slotData[i].name == data.name then
				local space = MAX_STACK - slotData[i].count
				if space > 0 then
					local toMove = math.min(remaining, space)
					slotData[i].count = slotData[i].count + toMove
					remaining = remaining - toMove
				end
			end
		end
		-- Put rest into empty slots
		while remaining > 0 do
			local empty = findEmptySlot(targetStart, targetEnd)
			if not empty then break end
			local amount = math.min(remaining, MAX_STACK)
			slotData[empty] = {type = data.type, name = data.name, count = amount, icon = data.icon}
			remaining = remaining - amount
		end
		-- Update source
		if remaining <= 0 then
			slotData[slotIndex] = nil
		else
			slotData[slotIndex].count = remaining
		end
	else
		-- Tools: just swap to first empty slot in target area
		local empty = findEmptySlot(targetStart, targetEnd)
		if empty then
			slotData[empty] = data
			slotData[slotIndex] = nil
		end
	end

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

local rebuildCraftList

local function closeDetailOverlay()
	if detailOverlay then
		detailOverlay:Destroy()
		detailOverlay = nil
	end
	selectedRecipe = nil
end

local function closeCategoryOverlay()
	closeDetailOverlay()
	if categoryOverlay then
		categoryOverlay:Destroy()
		categoryOverlay = nil
	end
	selectedCategory = nil
	if screenGui then
		local tabFrame = screenGui:FindFirstChild("CategoryTabs", true)
		if tabFrame then
			for _, tab in tabFrame:GetChildren() do
				if tab:IsA("TextButton") then
					tab.BackgroundColor3 = COLORS.craftItemBg
					tab.TextColor3 = COLORS.titleText
				end
			end
		end
	end
end

local function openCategoryOverlay(cat)
	if not screenGui then return end
	local centerPanel = screenGui:FindFirstChild("CenterPanel")
	if not centerPanel then return end

	closeDetailOverlay()
	if categoryOverlay then
		categoryOverlay:Destroy()
		categoryOverlay = nil
	end
	selectedCategory = cat

	categoryOverlay = Instance.new("Frame")
	categoryOverlay.Name = "CategoryOverlay"
	categoryOverlay.Size = centerPanel.Size
	categoryOverlay.Position = centerPanel.Position
	categoryOverlay.BackgroundColor3 = COLORS.panelBg
	categoryOverlay.BorderSizePixel = 0
	categoryOverlay.ZIndex = 15
	categoryOverlay.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = categoryOverlay

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.panelBorder
	stroke.Thickness = 3
	stroke.Parent = categoryOverlay

	local backBtn = Instance.new("TextButton")
	backBtn.Size = UDim2.new(0, 100, 0, 46)
	backBtn.Position = UDim2.new(0, 18, 0, 14)
	backBtn.BackgroundColor3 = COLORS.craftItemBg
	backBtn.Text = "< Back"
	backBtn.TextColor3 = COLORS.titleText
	backBtn.Font = Enum.Font.GothamBold
	backBtn.TextSize = 22
	backBtn.BorderSizePixel = 0
	backBtn.ZIndex = 16
	backBtn.Parent = categoryOverlay

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 6)
	backCorner.Parent = backBtn

	backBtn.MouseButton1Click:Connect(closeCategoryOverlay)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -150, 0, 50)
	title.Position = UDim2.new(0, 134, 0, 14)
	title.BackgroundTransparency = 1
	title.Text = cat
	title.TextColor3 = COLORS.titleText
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 36
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 16
	title.Parent = categoryOverlay

	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -50, 0, 3)
	sep.Position = UDim2.new(0, 25, 0, 70)
	sep.BackgroundColor3 = COLORS.separator
	sep.BorderSizePixel = 0
	sep.ZIndex = 16
	sep.Parent = categoryOverlay

	local craftList = Instance.new("ScrollingFrame")
	craftList.Name = "CraftList"
	craftList.Size = UDim2.new(1, -36, 1, -100)
	craftList.Position = UDim2.new(0, 18, 0, 88)
	craftList.BackgroundTransparency = 1
	craftList.BorderSizePixel = 0
	craftList.ScrollBarThickness = 10
	craftList.CanvasSize = UDim2.new(0, 0, 0, 0)
	craftList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	craftList.ZIndex = 17
	craftList.Parent = categoryOverlay

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 10)
	listLayout.Parent = craftList

	rebuildCraftList()
end

local function openDetailOverlay(recipe)
	closeDetailOverlay()
	selectedRecipe = recipe
	if not screenGui then return end

	local centerPanel = screenGui:FindFirstChild("CenterPanel")
	if not centerPanel then return end

	-- Create overlay same size/position as center panel
	detailOverlay = Instance.new("Frame")
	detailOverlay.Name = "DetailOverlay"
	detailOverlay.Size = centerPanel.Size
	detailOverlay.Position = centerPanel.Position
	detailOverlay.BackgroundColor3 = COLORS.panelBg
	detailOverlay.BorderSizePixel = 0
	detailOverlay.ZIndex = 20
	detailOverlay.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = detailOverlay

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.panelBorder
	stroke.Thickness = 3
	stroke.Parent = detailOverlay

	-- Back button
	local backBtn = Instance.new("TextButton")
	backBtn.Size = UDim2.new(0, 60, 0, 28)
	backBtn.Position = UDim2.new(0, 10, 0, 8)
	backBtn.BackgroundColor3 = COLORS.craftItemBg
	backBtn.Text = "< Back"
	backBtn.TextColor3 = COLORS.titleText
	backBtn.Font = Enum.Font.GothamBold
	backBtn.TextSize = 13
	backBtn.BorderSizePixel = 0
	backBtn.ZIndex = 21
	backBtn.Parent = detailOverlay

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 6)
	backCorner.Parent = backBtn

	backBtn.MouseButton1Click:Connect(closeDetailOverlay)

	-- Item name
	local itemTitle = Instance.new("TextLabel")
	itemTitle.Size = UDim2.new(1, -20, 0, 30)
	itemTitle.Position = UDim2.new(0, 10, 0, 45)
	itemTitle.BackgroundTransparency = 1
	itemTitle.Text = recipe.displayName or recipe.name
	itemTitle.TextColor3 = COLORS.titleText
	itemTitle.Font = Enum.Font.GothamBold
	itemTitle.TextSize = 22
	itemTitle.TextXAlignment = Enum.TextXAlignment.Left
	itemTitle.ZIndex = 21
	itemTitle.Parent = detailOverlay

	-- Separator
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -20, 0, 2)
	sep.Position = UDim2.new(0, 10, 0, 80)
	sep.BackgroundColor3 = COLORS.separator
	sep.BorderSizePixel = 0
	sep.ZIndex = 21
	sep.Parent = detailOverlay

	-- Icon
	local iconFrame = Instance.new("ImageLabel")
	iconFrame.Size = UDim2.new(0, 64, 0, 64)
	iconFrame.Position = UDim2.new(0, 20, 0, 95)
	iconFrame.BackgroundTransparency = 1
	iconFrame.Image = recipe.icon or ""
	iconFrame.ScaleType = Enum.ScaleType.Fit
	iconFrame.ZIndex = 21
	iconFrame.Parent = detailOverlay

	-- Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -110, 0, 70)
	descLabel.Position = UDim2.new(0, 95, 0, 95)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = recipe.description or ""
	descLabel.TextColor3 = COLORS.titleText
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 13
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextWrapped = true
	descLabel.ZIndex = 21
	descLabel.Parent = detailOverlay

	-- Materials section
	local matTitle = Instance.new("TextLabel")
	matTitle.Size = UDim2.new(1, -20, 0, 22)
	matTitle.Position = UDim2.new(0, 10, 0, 175)
	matTitle.BackgroundTransparency = 1
	matTitle.Text = "Materials:"
	matTitle.TextColor3 = COLORS.titleText
	matTitle.Font = Enum.Font.GothamBold
	matTitle.TextSize = 14
	matTitle.TextXAlignment = Enum.TextXAlignment.Left
	matTitle.ZIndex = 21
	matTitle.Parent = detailOverlay

	-- Material items
	local matY = 200
	for item, amount in recipe.costs do
		local matRow = Instance.new("Frame")
		matRow.Size = UDim2.new(1, -30, 0, 30)
		matRow.Position = UDim2.new(0, 15, 0, matY)
		matRow.BackgroundColor3 = COLORS.craftItemBg
		matRow.BorderSizePixel = 0
		matRow.ZIndex = 21
		matRow.Parent = detailOverlay

		local matCorner = Instance.new("UICorner")
		matCorner.CornerRadius = UDim.new(0, 5)
		matCorner.Parent = matRow

		local matIcon = Instance.new("ImageLabel")
		matIcon.Size = UDim2.new(0, 22, 0, 22)
		matIcon.Position = UDim2.new(0, 6, 0.5, -11)
		matIcon.BackgroundTransparency = 1
		matIcon.Image = RESOURCE_ICONS[item] or ""
		matIcon.ScaleType = Enum.ScaleType.Fit
		matIcon.ZIndex = 22
		matIcon.Parent = matRow

		local have = inventory[item] or 0
		local matLabel = Instance.new("TextLabel")
		matLabel.Size = UDim2.new(1, -40, 1, 0)
		matLabel.Position = UDim2.new(0, 34, 0, 0)
		matLabel.BackgroundTransparency = 1
		matLabel.Text = item .. ": " .. have .. " / " .. amount
		matLabel.TextColor3 = have >= amount and COLORS.affordable or COLORS.notAffordable
		matLabel.Font = Enum.Font.GothamBold
		matLabel.TextSize = 13
		matLabel.TextXAlignment = Enum.TextXAlignment.Left
		matLabel.ZIndex = 22
		matLabel.Parent = matRow

		matY = matY + 36
	end

	-- Craft button at bottom
	local craftBtn = Instance.new("TextButton")
	craftBtn.Name = "DetailCraftButton"
	craftBtn.Size = UDim2.new(1, -30, 0, 38)
	craftBtn.Position = UDim2.new(0, 15, 1, -50)
	craftBtn.BackgroundColor3 = canAfford(recipe) and COLORS.affordable or Color3.fromRGB(120, 120, 120)
	craftBtn.Text = "Craft " .. (recipe.displayName or recipe.name)
	craftBtn.TextColor3 = Color3.new(1, 1, 1)
	craftBtn.Font = Enum.Font.GothamBold
	craftBtn.TextSize = 16
	craftBtn.BorderSizePixel = 0
	craftBtn.ZIndex = 21
	craftBtn.Parent = detailOverlay

	local craftCorner = Instance.new("UICorner")
	craftCorner.CornerRadius = UDim.new(0, 8)
	craftCorner.Parent = craftBtn

	craftBtn.MouseButton1Click:Connect(function()
		if canAfford(recipe) then
			inventoryCraftEvent:FireServer("craft", recipe.name)
		end
	end)
end

function rebuildCraftList()
	if not screenGui then return end
	if not selectedCategory then return end
	local craftList = screenGui:FindFirstChild("CraftList", true)
	if not craftList then return end

	-- Clear existing items
	for _, child in craftList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	-- Filter recipes by selected category
	local idx = 0
	for _, recipe in recipes do
		if recipe.category == selectedCategory then
			idx = idx + 1

			local btn = Instance.new("TextButton")
			btn.Name = "Recipe_" .. recipe.name
			btn.Size = UDim2.new(1, 0, 0, 80)
			btn.BackgroundColor3 = COLORS.craftItemBg
			btn.Text = ""
			btn.BorderSizePixel = 0
			btn.LayoutOrder = idx
			btn.AutoButtonColor = false
			btn.ZIndex = 17
			btn.Parent = craftList
			btn:SetAttribute("RecipeName", recipe.name)

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 8)
			btnCorner.Parent = btn

			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.new(0, 56, 0, 56)
			icon.Position = UDim2.new(0, 12, 0.5, -28)
			icon.BackgroundTransparency = 1
			icon.Image = recipe.icon or ""
			icon.ScaleType = Enum.ScaleType.Fit
			icon.ZIndex = 18
			icon.Parent = btn

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -90, 0, 32)
			nameLabel.Position = UDim2.new(0, 80, 0, 8)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = recipe.displayName or recipe.name
			nameLabel.TextColor3 = COLORS.titleText
			nameLabel.Font = Enum.Font.Gotham
			nameLabel.TextSize = 22
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.ZIndex = 18
			nameLabel.Parent = btn

			local costText = ""
			for item, amount in recipe.costs do
				costText = amount .. " " .. item
			end

			local costLabel = Instance.new("TextLabel")
			costLabel.Name = "CostLabel"
			costLabel.Size = UDim2.new(1, -90, 0, 26)
			costLabel.Position = UDim2.new(0, 80, 0, 42)
			costLabel.BackgroundTransparency = 1
			costLabel.Text = costText
			costLabel.TextColor3 = canAfford(recipe) and COLORS.affordable or COLORS.notAffordable
			costLabel.Font = Enum.Font.Gotham
			costLabel.TextSize = 18
			costLabel.TextXAlignment = Enum.TextXAlignment.Left
			costLabel.ZIndex = 18
			costLabel.Parent = btn

			btn.MouseEnter:Connect(function()
				btn.BackgroundColor3 = COLORS.craftItemHover
			end)
			btn.MouseLeave:Connect(function()
				btn.BackgroundColor3 = COLORS.craftItemBg
			end)
			btn.MouseButton1Click:Connect(function()
				openDetailOverlay(recipe)
			end)
		end
	end
end

local function updateCategoryTabs()
	if not screenGui then return end
	local tabFrame = screenGui:FindFirstChild("CategoryTabs", true)
	if not tabFrame then return end
	for _, tab in tabFrame:GetChildren() do
		if tab:IsA("TextButton") then
			local cat = tab:GetAttribute("Category")
			local color
			if cat == selectedCategory then
				tab.BackgroundColor3 = COLORS.panelBg
				color = COLORS.lightText
			else
				tab.BackgroundColor3 = COLORS.craftItemBg
				color = COLORS.titleText
			end
			tab.TextColor3 = color
			local label = tab:FindFirstChild("Label")
			if label then
				label.TextColor3 = color
			end
		end
	end
end

local function updateCraftPanel()
	if not screenGui then return end

	-- Update cost colors in the list
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
					end
				end
			end
		end
	end

	-- Update detail overlay craft button if open
	if detailOverlay and selectedRecipe then
		local craftBtn = detailOverlay:FindFirstChild("DetailCraftButton")
		if craftBtn then
			craftBtn.BackgroundColor3 = canAfford(selectedRecipe) and COLORS.affordable or Color3.fromRGB(120, 120, 120)
		end
	end
end

-- ─── Slot layout sync to server ───
local slotLayoutEvent = ReplicatedStorage:FindFirstChild("SlotLayoutSync")

local function syncSlotLayoutToServer()
	if not slotLayoutEvent then
		slotLayoutEvent = ReplicatedStorage:FindFirstChild("SlotLayoutSync")
	end
	if not slotLayoutEvent then return end

	-- Build a serializable copy of slotData (no userdata)
	local layout = {}
	for i = 1, TOTAL_SLOTS do
		if slotData[i] then
			layout[tostring(i)] = {
				type = slotData[i].type,
				name = slotData[i].name,
				count = slotData[i].count,
				icon = slotData[i].icon,
				toolName = slotData[i].toolName,
			}
		end
	end
	slotLayoutEvent:FireServer(layout)
end

local function updateUI()
	rebuildSlotData()
	renderAllSlots()
	updateCraftPanel()
	syncSlotLayoutToServer()
end

-- ─── Close ───

local function closeUI()
	closeDetailOverlay()
	if categoryOverlay then
		categoryOverlay:Destroy()
		categoryOverlay = nil
	end
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	-- Drop stale grid slot refs; buildUI() re-populates them next open.
	table.clear(gridSlotVisuals)
	lockedOverlayLabel = nil
	hideTooltip()
	isOpen = false
	selectedRecipe = nil
	selectedCategory = nil
	if hotbarGui then hotbarGui.DisplayOrder = 5 end
end

-- Expose a force-close hook so other scripts (e.g. the phone menu) can
-- dismiss the inventory when they take over the screen.
_G.CloseInventory = function()
	if isOpen then closeUI() end
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

		slot.MouseEnter:Connect(function()
			showTooltipForSlot(slotIndex)
		end)
		slot.MouseLeave:Connect(function()
			hideTooltip()
		end)

		slot.MouseButton1Down:Connect(function()
			local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shiftHeld then
				quickTransfer(slotIndex)
				dragState.didDrag = true
				return
			end
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[slotIndex]
			if data then
				beginDragPending(slotIndex, data, mousePos, false)
			end
		end)

		slot.MouseButton2Down:Connect(function()
			local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shiftHeld then
				quickTransfer(slotIndex)
				dragState.didDrag = true
				return
			end
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

	-- ─── Mana bar ──────────────────────────────────────────────────────
	-- Lives in its own script at StarterPlayerScripts/ManaUI/ManaUI.client.lua
	-- (it builds its own ScreenGui; nothing to do from here).
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
	local panelWidth = gridWidth + 60
	local panelHeight = gridHeight + 110

	-- Center the combined block (CraftPanel on the left + CenterPanel)
	-- horizontally on screen.
	local craftPanelWidth = 340
	local craftGap = 20
	local combinedWidth = craftPanelWidth + craftGap + panelWidth
	local centerPanelLeft = -combinedWidth / 2 + craftPanelWidth + craftGap

	local centerPanel = Instance.new("Frame")
	centerPanel.Name = "CenterPanel"
	centerPanel.Size = UDim2.new(0, panelWidth, 0, panelHeight)
	centerPanel.Position = UDim2.new(0.5, centerPanelLeft, 0.5, -panelHeight / 2)
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
	title.Size = UDim2.new(1, -120, 0, 50)
	title.Position = UDim2.new(0, 16, 0, 12)
	title.BackgroundTransparency = 1
	title.Text = "Inventory"
	title.TextColor3 = COLORS.titleText
	title.Font = Enum.Font.GothamBold
	title.TextSize = 36
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = centerPanel

	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -50, 0, 3)
	sep.Position = UDim2.new(0, 25, 0, 70)
	sep.BackgroundColor3 = COLORS.separator
	sep.BorderSizePixel = 0
	sep.Parent = centerPanel

	-- Log counter
	local logIcon = Instance.new("ImageLabel")
	logIcon.Size = UDim2.new(0, 32, 0, 32)
	logIcon.Position = UDim2.new(1, -210, 0, 20)
	logIcon.BackgroundTransparency = 1
	logIcon.Image = LOG_ICON
	logIcon.ScaleType = Enum.ScaleType.Fit
	logIcon.Parent = centerPanel

	local logCount = Instance.new("TextLabel")
	logCount.Name = "LogCount"
	logCount.Size = UDim2.new(0, 50, 0, 32)
	logCount.Position = UDim2.new(1, -174, 0, 20)
	logCount.BackgroundTransparency = 1
	logCount.Text = tostring(inventory.Log or 0)
	logCount.TextColor3 = COLORS.titleText
	logCount.Font = Enum.Font.GothamBold
	logCount.TextSize = 22
	logCount.TextXAlignment = Enum.TextXAlignment.Left
	logCount.Parent = centerPanel

	-- Plastic counter
	local plasticIcon = Instance.new("ImageLabel")
	plasticIcon.Size = UDim2.new(0, 32, 0, 32)
	plasticIcon.Position = UDim2.new(1, -110, 0, 20)
	plasticIcon.BackgroundTransparency = 1
	plasticIcon.Image = PLASTIC_ICON
	plasticIcon.ScaleType = Enum.ScaleType.Fit
	plasticIcon.Parent = centerPanel

	local plasticCount = Instance.new("TextLabel")
	plasticCount.Name = "PlasticCount"
	plasticCount.Size = UDim2.new(0, 50, 0, 32)
	plasticCount.Position = UDim2.new(1, -74, 0, 20)
	plasticCount.BackgroundTransparency = 1
	plasticCount.Text = tostring(inventory.Plastic or 0)
	plasticCount.TextColor3 = COLORS.titleText
	plasticCount.Font = Enum.Font.GothamBold
	plasticCount.TextSize = 22
	-- Inventory grid (these are slots 9-28)
	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "InventoryGrid"
	gridFrame.Size = UDim2.new(0, gridWidth, 0, gridHeight)
	gridFrame.Position = UDim2.new(0.5, -gridWidth / 2, 0, 85)
	gridFrame.BackgroundTransparency = 1
	gridFrame.Parent = centerPanel

	-- Clear any stale refs from a previous rebuild.
	table.clear(gridSlotVisuals)

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

		gridSlotVisuals[i] = { button = slot, stroke = slotStroke }

		local globalIdx = HOTBAR_SLOTS + i

		slot.MouseEnter:Connect(function()
			if isSlotLocked(globalIdx) then return end
			showTooltipForSlot(globalIdx)
		end)
		slot.MouseLeave:Connect(function()
			hideTooltip()
		end)

		slot.MouseButton1Down:Connect(function()
			if isSlotLocked(globalIdx) then return end
			local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shiftHeld then
				quickTransfer(globalIdx)
				dragState.didDrag = true
				return
			end
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[globalIdx]
			if data then
				beginDragPending(globalIdx, data, mousePos, false)
			end
		end)

		slot.MouseButton2Down:Connect(function()
			if isSlotLocked(globalIdx) then return end
			local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shiftHeld then
				quickTransfer(globalIdx)
				dragState.didDrag = true
				return
			end
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[globalIdx]
			if data and data.type == "resource" and data.count and data.count > 1 then
				beginDragPending(globalIdx, data, mousePos, true)
			end
		end)
	end

	-- Big "NEED STRENGTH" overlay that covers the locked portion of the
	-- grid. applyUnlockedSlots() repositions/hides it based on the
	-- current unlocked-count.
	lockedOverlayLabel = Instance.new("TextLabel")
	lockedOverlayLabel.Name = "LockedOverlay"
	lockedOverlayLabel.BackgroundTransparency = 1
	lockedOverlayLabel.Text = "NEED STRENGTH"
	lockedOverlayLabel.Font = Enum.Font.GothamBold
	lockedOverlayLabel.TextScaled = true
	lockedOverlayLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	lockedOverlayLabel.TextTransparency = 0.25
	lockedOverlayLabel.TextStrokeTransparency = 0.4
	lockedOverlayLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	lockedOverlayLabel.ZIndex = 10
	lockedOverlayLabel.Parent = gridFrame

	applyUnlockedSlots()

	-- ─── Left Crafting Panel (vertical category list) ───
	-- `craftPanelWidth`, `craftGap`, and `combinedWidth` are defined above
	-- when computing `centerPanelLeft`.
	local craftPanel = Instance.new("Frame")
	craftPanel.Name = "CraftPanel"
	craftPanel.Size = UDim2.new(0, craftPanelWidth, 0, panelHeight)
	craftPanel.Position = UDim2.new(0.5, -combinedWidth / 2, 0.5, -panelHeight / 2)
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
	craftTitle.Size = UDim2.new(1, -25, 0, 50)
	craftTitle.Position = UDim2.new(0, 18, 0, 14)
	craftTitle.BackgroundTransparency = 1
	craftTitle.Text = "Crafting"
	craftTitle.TextColor3 = COLORS.titleText
	craftTitle.Font = Enum.Font.GothamMedium
	craftTitle.TextSize = 32
	craftTitle.TextXAlignment = Enum.TextXAlignment.Left
	craftTitle.Parent = craftPanel

	local craftSep = Instance.new("Frame")
	craftSep.Size = UDim2.new(1, -36, 0, 3)
	craftSep.Position = UDim2.new(0, 18, 0, 70)
	craftSep.BackgroundColor3 = COLORS.panelBorder
	craftSep.BorderSizePixel = 0
	craftSep.Parent = craftPanel

	-- Vertical category tabs
	local tabFrame = Instance.new("Frame")
	tabFrame.Name = "CategoryTabs"
	tabFrame.Size = UDim2.new(1, -36, 1, -100)
	tabFrame.Position = UDim2.new(0, 18, 0, 88)
	tabFrame.BackgroundTransparency = 1
	tabFrame.Parent = craftPanel

	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Vertical
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Padding = UDim.new(0, 14)
	tabsLayout.Parent = tabFrame

	for i, cat in CATEGORIES do
		local tab = Instance.new("TextButton")
		tab.Name = "Tab_" .. cat
		tab.Size = UDim2.new(1, 0, 0, 68)
		tab.LayoutOrder = i
		tab.BackgroundColor3 = COLORS.craftItemBg
		tab.TextColor3 = COLORS.titleText
		tab.Text = ""
		tab.Font = Enum.Font.GothamMedium
		tab.TextSize = 22
		tab.BorderSizePixel = 0
		tab.AutoButtonColor = false
		tab.Parent = tabFrame
		tab:SetAttribute("Category", cat)

		-- Icon on the left
		local iconId = CATEGORY_ICONS[cat]
		if iconId then
			local icon = Instance.new("ImageLabel")
			icon.Name = "Icon"
			icon.Size = UDim2.new(0, 44, 0, 44)
			icon.Position = UDim2.new(0, 14, 0.5, -22)
			icon.BackgroundTransparency = 1
			icon.Image = iconId
			icon.ScaleType = Enum.ScaleType.Fit
			icon.Parent = tab
		end

		-- Text label to the right of the icon
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, -76, 1, 0)
		label.Position = UDim2.new(0, 68, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = cat
		label.TextColor3 = COLORS.titleText
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 22
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = tab

		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = UDim.new(0, 6)
		tabCorner.Parent = tab

		local tabStroke = Instance.new("UIStroke")
		tabStroke.Color = COLORS.panelBorder
		tabStroke.Thickness = 1
		tabStroke.Parent = tab

		tab.MouseEnter:Connect(function()
			if selectedCategory ~= cat then
				tab.BackgroundColor3 = COLORS.craftItemHover
			end
		end)
		tab.MouseLeave:Connect(function()
			if selectedCategory ~= cat then
				tab.BackgroundColor3 = COLORS.craftItemBg
			end
		end)

		tab.MouseButton1Click:Connect(function()
			openCategoryOverlay(cat)
			updateCategoryTabs()
		end)
	end

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 46, 0, 46)
	closeBtn.Position = UDim2.new(1, -58, 0, 14)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 26
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

-- Expose an open hook so other scripts (e.g. the mercenary backpack
-- UI) can force the main inventory open alongside their own UI.
_G.OpenInventory = function()
	if not isOpen then
		isOpen = true
		inventoryCraftEvent:FireServer("requestRecipes")
		buildUI()
	end
end
_G.IsInventoryOpen = function() return isOpen end

-- ─── Input ───

local numberKeys = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E then
		-- Hard guard: if the player is currently holding the Phone tool the
		-- inventory must NEVER toggle on E, even if PhoneMenu's
		-- `_G.SuppressInventoryToggle` hook hasn't caught up yet. We check
		-- the live character directly so the two UIs can't race.
		local char = player.Character
		local equipped = char and char:FindFirstChildOfClass("Tool")
		if equipped and equipped.Name == "Phone" then
			return
		end
		-- Defer the toggle decision until the end of the current
		-- resumption cycle. Roblox does not guarantee InputBegan handler
		-- order between scripts, so DropItem.client.lua's E handler may
		-- run either before or after this one. By deferring, we're
		-- guaranteed that any pickup-in-the-same-frame has already
		-- stamped `_G.LastPickupTime` by the time we re-check — and we
		-- can reject the toggle cleanly without fighting over ordering.
		task.defer(function()
			if (os.clock() - (_G.LastPickupTime or 0)) < 0.2 then
				return
			end
			if _G.SuppressInventoryToggle then
				return
			end
			-- Re-check the Phone guard: the player could have equipped
			-- the Phone between the original press and this deferred
			-- evaluation (unlikely, but cheap to verify).
			local char2 = player.Character
			local equipped2 = char2 and char2:FindFirstChildOfClass("Tool")
			if equipped2 and equipped2.Name == "Phone" then
				return
			end
			toggleInventory()
		end)
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
		if tooltipGui and tooltipGui.Enabled then
			updateTooltipPosition(UserInputService:GetMouseLocation())
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
		-- Inject Pick-Axe recipe if not present (server file may not sync)
		local hasPickAxe = false
		for _, r in recipes do
			if r.name == "Pick-Axe" then hasPickAxe = true break end
		end
		if not hasPickAxe then
			table.insert(recipes, {
				name = "Pick-Axe",
				displayName = "Pick-Axe",
				icon = "rbxassetid://89809613033816",
				costs = {Log = 2},
				craftType = "tool",
				category = "Tools",
				description = "A pickaxe for mining rocks on islands to collect stone.",
			})
		end
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

-- Track the replicated `Characteristics.UnlockedInventorySlots` value
-- (written by Strength.server.lua based on the player's Strength stat)
-- and repaint the grid whenever it changes.
task.spawn(function()
	local folder = player:WaitForChild("Characteristics")
	local value  = folder:WaitForChild("UnlockedInventorySlots")

	local function refresh()
		unlockedSlots = math.clamp(value.Value, BASE_UNLOCKED_SLOTS, TOTAL_SLOTS)
		applyUnlockedSlots()
	end

	refresh()
	value:GetPropertyChangedSignal("Value"):Connect(refresh)
end)

local backpack = player:WaitForChild("Backpack")
backpack.ChildAdded:Connect(function() task.wait(0.1) updateUI() end)
backpack.ChildRemoved:Connect(function() task.wait(0.1) updateUI() end)

player.CharacterAdded:Connect(function(char)
	-- Reconnect to new Backpack after respawn
	local newBackpack = player:WaitForChild("Backpack")
	newBackpack.ChildAdded:Connect(function() task.wait(0.1) updateUI() end)
	newBackpack.ChildRemoved:Connect(function() task.wait(0.1) updateUI() end)

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

-- ─── Listen for saved slot layout restore from server ───
task.spawn(function()
	if not slotLayoutEvent then
		slotLayoutEvent = ReplicatedStorage:WaitForChild("SlotLayoutSync", 10)
	end
	if slotLayoutEvent then
		slotLayoutEvent.OnClientEvent:Connect(function(action, savedLayout)
			if action == "restore" and typeof(savedLayout) == "table" then
				-- Apply saved slot positions
				for i = 1, TOTAL_SLOTS do
					slotData[i] = nil
				end
				for slotStr, itemData in savedLayout do
					local slotNum = tonumber(slotStr)
					if slotNum and slotNum >= 1 and slotNum <= TOTAL_SLOTS and typeof(itemData) == "table" then
						slotData[slotNum] = {
							type = itemData.type,
							name = itemData.name,
							count = itemData.count,
							icon = itemData.icon,
							toolName = itemData.toolName,
						}
					end
				end
				slotsInitialized = true
				renderAllSlots()
				print("[InventoryUI] Restored saved slot layout")
			end
		end)
	end
end)
