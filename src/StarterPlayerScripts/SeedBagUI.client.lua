-- SeedBagUI.client.lua
-- "Leaf bag" Tool interaction. While the bag is in hand, pressing E
-- opens the seed picker; if the player is also next to a watered
-- Bed_Garden_For_Tree, the picker's "Plant" button is enabled and
-- planting consumes one seed from the bag.
--
-- Layout matches the user-supplied design pass:
--   ┌────────────────────────────────────────────────────────────┐
--   │ [🌱] Seed Bag                            [5/8]   [×]       │
--   │      Choose what to plant                                  │
--   │ ┌────────┬────────┬────────┬────────┐  ┌─────────────────┐ │
--   │ │ slot 1 │ slot 2 │ slot 3 │ slot 4 │  │   selected      │ │
--   │ ├────────┼────────┼────────┼────────┤  │   detail panel  │ │
--   │ │ slot 5 │ slot 6 │ slot 7 │ slot 8 │  │   + Plant       │ │
--   │ └────────┴────────┴────────┴────────┘  └─────────────────┘ │
--   │   Tip: Click a seed to select it, then click "Plant".      │
--   └────────────────────────────────────────────────────────────┘
--
-- Selection flow:
--   1. E → server "open" → "show" reply with the 8-slot snapshot.
--   2. Click a filled card → select it (paper-light background +
--      dark stroke, detail panel populates).
--   3. Click "Plant" → server "plant" with the selected slot index.
--      Server consumes one seed + drives growTree, then echoes back
--      "close" so we hide the panel.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local seedBagEvent = ReplicatedStorage:WaitForChild("SeedBagAction")
local pickupEvent  = ReplicatedStorage:WaitForChild("PickupDroppedItem")

local BAG_TOOL_NAME = "leaf bag"
local SLOT_COUNT    = 8
local GRID_COLS     = 4
local GRID_ROWS     = 2

-- Seed display metadata. growsInto / growsTime drive the right-side
-- detail panel; keep in sync with TREE_STAGES + TREE_STAGE_INTERVAL
-- in GardenSystem.server.lua (palm seeds run all four stages, the
-- other two freeze at the seedling).
local SEED_META = {
	Banana_Seed = {
		display    = "Banana Seed",
		icon       = "rbxassetid://73140419103065",
		growsInto  = "Banana Sprout",
		growsTime  = "10 seconds",
	},
	Coconut_Seed = {
		display    = "Coconut Seed",
		icon       = "rbxassetid://138995623166184",
		growsInto  = "Palm Tree",
		growsTime  = "40 seconds",
	},
	Pineapple_Seed = {
		display    = "Pineapple Seed",
		icon       = "rbxassetid://128520746024640",
		growsInto  = "Pineapple Sprout",
		growsTime  = "10 seconds",
	},
}

local BAG_ICON = "rbxassetid://89398456198664"

-- ─── Wood palette (matches the rest of the in-world UIs) ────────────
local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_WOOD_DARK    = Color3.fromRGB( 91,  58,  34)
local COLOR_WOOD_MID     = Color3.fromRGB(138, 106,  68)
local COLOR_WOOD_BASE    = Color3.fromRGB(176, 138,  92)
local COLOR_PAPER        = Color3.fromRGB(218, 199, 160)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(238, 222, 188)
local COLOR_GREEN_OK     = Color3.fromRGB( 96, 148,  72)
local COLOR_GREEN_DIM    = Color3.fromRGB(118, 132, 104)

-- ─── State ────────────────────────────────────────────────────────
local currentBed       = nil   -- Model server told us to plant on (nil = view-only)
local currentTool      = nil
local currentSelection = nil   -- slot index 1..SLOT_COUNT, or nil
local currentSnapshot  = {}    -- mirror of the server snapshot

-- ─── Hint label ───────────────────────────────────────────────────
local hintGui = Instance.new("ScreenGui")
hintGui.Name           = "SeedBagHint"
hintGui.ResetOnSpawn   = false
hintGui.IgnoreGuiInset = true
hintGui.DisplayOrder   = 46
hintGui.Parent         = playerGui

local hintLabel = Instance.new("TextLabel")
hintLabel.AnchorPoint            = Vector2.new(0.5, 1)
hintLabel.Position               = UDim2.new(0.5, 0, 0.78, 0)
hintLabel.Size                   = UDim2.new(0, 280, 0, 36)
hintLabel.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
hintLabel.BackgroundTransparency = 0.4
hintLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
hintLabel.Font                   = Enum.Font.GothamBold
hintLabel.TextSize               = 18
hintLabel.Text                   = "[E] Open Seed Bag"
hintLabel.Visible                = false
hintLabel.Parent                 = hintGui
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent       = hintLabel
end

-- ─── Pickup error toast ───────────────────────────────────────────
local toastLabel = Instance.new("TextLabel")
toastLabel.AnchorPoint            = Vector2.new(0.5, 0.5)
toastLabel.Position               = UDim2.new(0.5, 0, 0.42, 0)
toastLabel.Size                   = UDim2.new(0, 360, 0, 44)
toastLabel.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
toastLabel.BackgroundTransparency = 0.35
toastLabel.TextColor3             = Color3.fromRGB(255, 220, 120)
toastLabel.TextStrokeTransparency = 0.5
toastLabel.Font                   = Enum.Font.GothamBold
toastLabel.TextSize               = 18
toastLabel.Visible                = false
toastLabel.Parent                 = hintGui
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent       = toastLabel
end

local toastJob = 0
local function showToast(text)
	toastLabel.Text    = text
	toastLabel.Visible = true
	toastJob = toastJob + 1
	local myJob = toastJob
	task.delay(2, function()
		if myJob == toastJob then
			toastLabel.Visible = false
		end
	end)
end

pickupEvent.OnClientEvent:Connect(function(action)
	if action == "needSeedBag" then
		showToast("You need a Leaf Bag to carry seeds.")
	elseif action == "seedBagFull" then
		showToast("Your Leaf Bag is full.")
	end
end)

-- ─── Picker UI ────────────────────────────────────────────────────
local pickerGui = Instance.new("ScreenGui")
pickerGui.Name           = "SeedBagPicker"
pickerGui.ResetOnSpawn   = false
pickerGui.IgnoreGuiInset = true
pickerGui.DisplayOrder   = 95
pickerGui.Enabled        = false
pickerGui.Parent         = playerGui

local backdrop = Instance.new("TextButton")
backdrop.Size                   = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
backdrop.BackgroundTransparency = 0.55
backdrop.BorderSizePixel        = 0
backdrop.AutoButtonColor        = false
backdrop.Text                   = ""
backdrop.Parent                 = pickerGui

local panel = Instance.new("Frame")
panel.AnchorPoint     = Vector2.new(0.5, 0.5)
panel.Position        = UDim2.fromScale(0.5, 0.5)
panel.Size            = UDim2.fromOffset(960, 600)
panel.BackgroundColor3 = COLOR_WOOD_BASE
panel.BorderSizePixel = 0
panel.Parent          = pickerGui
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 22)
	c.Parent       = panel
	local s = Instance.new("UIStroke")
	s.Color     = COLOR_WOOD_DARKEST
	s.Thickness = 3
	s.Parent    = panel
end

-- ── Header strip ─────────────────────────────────────────────────
local header = Instance.new("Frame")
header.Size               = UDim2.new(1, -32, 0, 90)
header.Position           = UDim2.new(0, 16, 0, 16)
header.BackgroundColor3   = COLOR_WOOD_MID
header.BorderSizePixel    = 0
header.Parent             = panel
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent       = header
end

local bagIcon = Instance.new("ImageLabel")
bagIcon.Size                   = UDim2.fromOffset(64, 64)
bagIcon.Position               = UDim2.new(0, 12, 0.5, -32)
bagIcon.BackgroundColor3       = COLOR_PAPER
bagIcon.BackgroundTransparency = 0
bagIcon.Image                  = BAG_ICON
bagIcon.ScaleType              = Enum.ScaleType.Fit
bagIcon.Parent                 = header
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent       = bagIcon
end

local titleLabel = Instance.new("TextLabel")
titleLabel.AnchorPoint        = Vector2.new(0, 0.5)
titleLabel.Position           = UDim2.new(0, 88, 0.5, -16)
titleLabel.Size               = UDim2.new(1, -260, 0, 28)
titleLabel.BackgroundTransparency = 1
titleLabel.Text               = "Seed Bag"
titleLabel.TextColor3         = COLOR_PAPER_LIGHT
titleLabel.TextXAlignment     = Enum.TextXAlignment.Left
titleLabel.TextYAlignment     = Enum.TextYAlignment.Center
titleLabel.Font               = Enum.Font.GothamBold
titleLabel.TextSize           = 24
titleLabel.Parent             = header

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.AnchorPoint            = Vector2.new(0, 0.5)
subtitleLabel.Position               = UDim2.new(0, 88, 0.5, 16)
subtitleLabel.Size                   = UDim2.new(1, -260, 0, 24)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text                   = "Choose what to plant"
subtitleLabel.TextColor3             = COLOR_PAPER_LIGHT
subtitleLabel.TextXAlignment         = Enum.TextXAlignment.Left
subtitleLabel.TextYAlignment         = Enum.TextYAlignment.Center
subtitleLabel.TextTransparency       = 0.2
subtitleLabel.Font                   = Enum.Font.Gotham
subtitleLabel.TextSize               = 18
subtitleLabel.Parent                 = header

local counterFrame = Instance.new("Frame")
counterFrame.AnchorPoint        = Vector2.new(1, 0.5)
counterFrame.Position           = UDim2.new(1, -76, 0.5, 0)
counterFrame.Size               = UDim2.fromOffset(100, 44)
counterFrame.BackgroundColor3   = COLOR_WOOD_BASE
counterFrame.BorderSizePixel    = 0
counterFrame.Parent             = header
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent       = counterFrame
end

local counterLabel = Instance.new("TextLabel")
counterLabel.Size               = UDim2.fromScale(1, 1)
counterLabel.BackgroundTransparency = 1
counterLabel.Text               = "0 / " .. SLOT_COUNT
counterLabel.TextColor3         = COLOR_PAPER_LIGHT
counterLabel.Font               = Enum.Font.GothamBold
counterLabel.TextSize           = 22
counterLabel.Parent             = counterFrame

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint            = Vector2.new(1, 0.5)
closeBtn.Position               = UDim2.new(1, -16, 0.5, 0)
closeBtn.Size                   = UDim2.fromOffset(44, 44)
closeBtn.BackgroundColor3       = COLOR_WOOD_DARK
closeBtn.Text                   = "×"
closeBtn.TextColor3             = COLOR_PAPER_LIGHT
closeBtn.Font                   = Enum.Font.GothamBold
closeBtn.TextSize               = 26
closeBtn.AutoButtonColor        = false
closeBtn.Parent                 = header
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent       = closeBtn
end

-- ── Grid (left side) ────────────────────────────────────────────
local GRID_LEFT   = 16
local GRID_TOP    = 130
local DETAIL_W    = 260
local CARD_GAP    = 12
local DETAIL_GAP  = 18
local GRID_BOTTOM = 60

local gridFrame = Instance.new("Frame")
gridFrame.Position           = UDim2.new(0, GRID_LEFT, 0, GRID_TOP)
gridFrame.Size               = UDim2.new(1, -GRID_LEFT - DETAIL_W - DETAIL_GAP - GRID_LEFT, 1, -GRID_TOP - GRID_BOTTOM)
gridFrame.BackgroundTransparency = 1
gridFrame.Parent             = panel

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellPadding   = UDim2.fromOffset(CARD_GAP, CARD_GAP)
gridLayout.CellSize      = UDim2.fromScale(1 / GRID_COLS, 1 / GRID_ROWS)
gridLayout.FillDirection = Enum.FillDirection.Horizontal
gridLayout.SortOrder     = Enum.SortOrder.LayoutOrder
gridLayout.StartCorner   = Enum.StartCorner.TopLeft
gridLayout.Parent        = gridFrame

-- AbsoluteCellSize honours CellPadding; subtract a slice so cards
-- don't overlap.
local gridPadding = Instance.new("UIPadding")
gridPadding.Parent = gridFrame

-- ── Slot card factory ───────────────────────────────────────────
local slots = {}
for i = 1, SLOT_COUNT do
	local card = Instance.new("TextButton")
	card.Name             = "Slot_" .. i
	card.LayoutOrder      = i
	card.BackgroundColor3 = COLOR_PAPER
	card.AutoButtonColor  = false
	card.Text             = ""
	card.Parent           = gridFrame

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 12)
	cardCorner.Parent       = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color       = COLOR_WOOD_DARK
	cardStroke.Thickness   = 2
	cardStroke.Transparency = 0.4
	cardStroke.Parent      = card

	local icon = Instance.new("ImageLabel")
	icon.AnchorPoint            = Vector2.new(0.5, 0)
	icon.Position               = UDim2.new(0.5, 0, 0, 18)
	icon.Size                   = UDim2.new(1, -32, 0, 96)
	icon.BackgroundTransparency = 1
	icon.ScaleType              = Enum.ScaleType.Fit
	icon.Image                  = ""
	icon.Parent                 = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.AnchorPoint            = Vector2.new(0.5, 1)
	nameLabel.Position               = UDim2.new(0.5, 0, 1, -34)
	nameLabel.Size                   = UDim2.new(1, -16, 0, 22)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text                   = ""
	nameLabel.TextColor3             = COLOR_WOOD_DARKEST
	nameLabel.Font                   = Enum.Font.GothamSemibold
	nameLabel.TextSize               = 18
	nameLabel.Parent                 = card

	-- "xN" badge bottom-center.
	local badge = Instance.new("Frame")
	badge.AnchorPoint            = Vector2.new(0.5, 1)
	badge.Position               = UDim2.new(0.5, 0, 1, -8)
	badge.Size                   = UDim2.fromOffset(48, 22)
	badge.BackgroundColor3       = COLOR_WOOD_BASE
	badge.BorderSizePixel        = 0
	badge.Visible                = false
	badge.Parent                 = card
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent       = badge
	end
	local badgeLabel = Instance.new("TextLabel")
	badgeLabel.Size                   = UDim2.fromScale(1, 1)
	badgeLabel.BackgroundTransparency = 1
	badgeLabel.Text                   = ""
	badgeLabel.TextColor3             = COLOR_PAPER_LIGHT
	badgeLabel.Font                   = Enum.Font.GothamBold
	badgeLabel.TextSize               = 14
	badgeLabel.Parent                 = badge

	-- Empty-state placeholder: a faint sprout icon when no seed.
	local emptyIcon = Instance.new("ImageLabel")
	emptyIcon.AnchorPoint            = Vector2.new(0.5, 0.5)
	emptyIcon.Position               = UDim2.fromScale(0.5, 0.5)
	emptyIcon.Size                   = UDim2.new(0, 56, 0, 56)
	emptyIcon.BackgroundTransparency = 1
	emptyIcon.ImageTransparency      = 0.7
	emptyIcon.Image                  = ""
	emptyIcon.ScaleType              = Enum.ScaleType.Fit
	emptyIcon.Parent                 = card

	slots[i] = {
		button     = card,
		icon       = icon,
		name       = nameLabel,
		badge      = badge,
		badgeLabel = badgeLabel,
		emptyIcon  = emptyIcon,
		stroke     = cardStroke,
		seed       = nil,
		count      = 0,
	}
end

-- ── Detail panel (right side) ────────────────────────────────────
local detail = Instance.new("Frame")
detail.AnchorPoint            = Vector2.new(1, 0)
detail.Position               = UDim2.new(1, -GRID_LEFT, 0, GRID_TOP)
detail.Size                   = UDim2.new(0, DETAIL_W, 1, -GRID_TOP - GRID_BOTTOM)
detail.BackgroundColor3       = COLOR_PAPER
detail.BorderSizePixel        = 0
detail.Parent                 = panel
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent       = detail
	local s = Instance.new("UIStroke")
	s.Color     = COLOR_WOOD_DARK
	s.Thickness = 2
	s.Transparency = 0.3
	s.Parent    = detail
end

local detailIcon = Instance.new("ImageLabel")
detailIcon.AnchorPoint            = Vector2.new(0.5, 0)
detailIcon.Position               = UDim2.new(0.5, 0, 0, 18)
detailIcon.Size                   = UDim2.new(1, -32, 0, 150)
detailIcon.BackgroundTransparency = 1
detailIcon.ScaleType              = Enum.ScaleType.Fit
detailIcon.Image                  = ""
detailIcon.Parent                 = detail

local detailName = Instance.new("TextLabel")
detailName.AnchorPoint            = Vector2.new(0.5, 0)
detailName.Position               = UDim2.new(0.5, 0, 0, 180)
detailName.Size                   = UDim2.new(1, -32, 0, 28)
detailName.BackgroundTransparency = 1
detailName.Text                   = "Select a seed"
detailName.TextColor3             = COLOR_WOOD_DARKEST
detailName.Font                   = Enum.Font.GothamBold
detailName.TextSize               = 20
detailName.Parent                 = detail

local infoBox = Instance.new("Frame")
infoBox.AnchorPoint        = Vector2.new(0.5, 0)
infoBox.Position           = UDim2.new(0.5, 0, 0, 220)
infoBox.Size               = UDim2.new(1, -32, 0, 78)
infoBox.BackgroundColor3   = COLOR_PAPER_LIGHT
infoBox.BorderSizePixel    = 0
infoBox.Parent             = detail
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent       = infoBox
end

local infoGrowsLabel = Instance.new("TextLabel")
infoGrowsLabel.Position               = UDim2.new(0, 12, 0, 8)
infoGrowsLabel.Size                   = UDim2.new(1, -24, 0, 22)
infoGrowsLabel.BackgroundTransparency = 1
infoGrowsLabel.Text                   = ""
infoGrowsLabel.TextColor3             = COLOR_WOOD_DARKEST
infoGrowsLabel.TextXAlignment         = Enum.TextXAlignment.Left
infoGrowsLabel.Font                   = Enum.Font.Gotham
infoGrowsLabel.TextSize               = 16
infoGrowsLabel.Parent                 = infoBox

local infoTimeLabel = Instance.new("TextLabel")
infoTimeLabel.Position               = UDim2.new(0, 12, 0, 36)
infoTimeLabel.Size                   = UDim2.new(1, -24, 0, 22)
infoTimeLabel.BackgroundTransparency = 1
infoTimeLabel.Text                   = ""
infoTimeLabel.TextColor3             = COLOR_WOOD_DARKEST
infoTimeLabel.TextXAlignment         = Enum.TextXAlignment.Left
infoTimeLabel.Font                   = Enum.Font.Gotham
infoTimeLabel.TextSize               = 16
infoTimeLabel.Parent                 = infoBox

local plantBtn = Instance.new("TextButton")
plantBtn.AnchorPoint            = Vector2.new(0.5, 1)
plantBtn.Position               = UDim2.new(0.5, 0, 1, -18)
plantBtn.Size                   = UDim2.new(1, -32, 0, 50)
plantBtn.BackgroundColor3       = COLOR_GREEN_DIM
plantBtn.Text                   = "Plant"
plantBtn.TextColor3             = Color3.fromRGB(245, 245, 240)
plantBtn.Font                   = Enum.Font.GothamBold
plantBtn.TextSize               = 22
plantBtn.AutoButtonColor        = false
plantBtn.Active                 = false
plantBtn.Parent                 = detail
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 12)
	c.Parent       = plantBtn
end

local tipLabel = Instance.new("TextLabel")
tipLabel.AnchorPoint            = Vector2.new(0.5, 1)
tipLabel.Position               = UDim2.new(0.5, 0, 1, -22)
tipLabel.Size                   = UDim2.new(1, -64, 0, 22)
tipLabel.BackgroundTransparency = 1
tipLabel.Text                   = "Tip: Click a seed to select it, then click \"Plant\"."
tipLabel.TextColor3             = COLOR_PAPER_LIGHT
tipLabel.Font                   = Enum.Font.GothamItalic
tipLabel.TextSize               = 16
tipLabel.TextTransparency       = 0.15
tipLabel.Parent                 = panel

-- ─── UI helpers ───────────────────────────────────────────────────
local function clearSelectionVisual()
	for _, s in ipairs(slots) do
		s.stroke.Color       = COLOR_WOOD_DARK
		s.stroke.Thickness   = 2
		s.stroke.Transparency = 0.4
		s.button.BackgroundColor3 = s.seed and COLOR_PAPER or COLOR_PAPER:Lerp(COLOR_WOOD_BASE, 0.35)
	end
end

local function paintDetail()
	if currentSelection and slots[currentSelection] and slots[currentSelection].seed then
		local seedName = slots[currentSelection].seed
		local meta = SEED_META[seedName] or {
			display = seedName,
			icon = "",
			growsInto = "Unknown",
			growsTime = "—",
		}
		detailIcon.Image      = meta.icon
		detailName.Text       = meta.display
		infoGrowsLabel.Text   = "Grows into: " .. meta.growsInto
		infoTimeLabel.Text    = "Time: " .. meta.growsTime
		infoBox.Visible       = true
		plantBtn.Active       = currentBed ~= nil
		plantBtn.BackgroundColor3 = currentBed and COLOR_GREEN_OK or COLOR_GREEN_DIM
		plantBtn.Text         = currentBed and "Plant" or "Stand next to a watered bed"
	else
		detailIcon.Image      = ""
		detailName.Text       = "Select a seed"
		infoGrowsLabel.Text   = ""
		infoTimeLabel.Text    = ""
		infoBox.Visible       = false
		plantBtn.Active       = false
		plantBtn.BackgroundColor3 = COLOR_GREEN_DIM
		plantBtn.Text         = "Plant"
	end
end

local function selectSlot(idx)
	if not slots[idx] or not slots[idx].seed then return end
	currentSelection = idx
	clearSelectionVisual()
	local s = slots[idx]
	s.button.BackgroundColor3 = COLOR_PAPER_LIGHT
	s.stroke.Color            = COLOR_WOOD_DARKEST
	s.stroke.Thickness        = 3
	s.stroke.Transparency     = 0
	paintDetail()
end

local function paintSlots(snapshot)
	currentSnapshot = snapshot or {}
	local filled = 0
	for i = 1, SLOT_COUNT do
		local s = slots[i]
		local entry = currentSnapshot[i]
		if entry and entry.name and entry.name ~= "" and (entry.count or 0) > 0 then
			local meta = SEED_META[entry.name] or { display = entry.name, icon = "" }
			s.seed                = entry.name
			s.count               = entry.count
			s.icon.Image          = meta.icon
			s.icon.Visible        = true
			s.name.Text           = meta.display
			s.name.Visible        = true
			s.badge.Visible       = true
			s.badgeLabel.Text     = "x" .. tostring(entry.count)
			s.emptyIcon.Visible   = false
			s.button.BackgroundColor3 = COLOR_PAPER
			filled = filled + 1
		else
			s.seed                = nil
			s.count               = 0
			s.icon.Image          = ""
			s.icon.Visible        = false
			s.name.Text           = ""
			s.name.Visible        = false
			s.badge.Visible       = false
			s.emptyIcon.Visible   = false
			s.button.BackgroundColor3 = COLOR_PAPER:Lerp(COLOR_WOOD_BASE, 0.35)
		end
	end
	counterLabel.Text = filled .. " / " .. SLOT_COUNT

	if currentSelection and slots[currentSelection] and not slots[currentSelection].seed then
		currentSelection = nil
	end
	clearSelectionVisual()
	if currentSelection then
		selectSlot(currentSelection)
	else
		paintDetail()
	end
end

local function closePicker()
	pickerGui.Enabled = false
	currentSelection  = nil
	currentBed        = nil
	currentSnapshot   = {}
	paintDetail()
end

-- ── Slot click handlers ─────────────────────────────────────────
for i, s in ipairs(slots) do
	s.button.MouseButton1Click:Connect(function()
		if not s.seed then return end
		selectSlot(i)
	end)
end

plantBtn.MouseButton1Click:Connect(function()
	if not plantBtn.Active then return end
	if not currentBed or not currentBed.Parent then return end
	if not currentSelection then return end
	if not slots[currentSelection] or not slots[currentSelection].seed then return end
	seedBagEvent:FireServer("plant", currentBed, currentSelection)
end)

closeBtn.MouseButton1Click:Connect(closePicker)
backdrop.MouseButton1Click:Connect(closePicker)

-- ─── Server → client events ───────────────────────────────────────
seedBagEvent.OnClientEvent:Connect(function(action, bed, snapshot)
	if action == "show" then
		currentBed = bed
		paintSlots(snapshot)
		pickerGui.Enabled = true
	elseif action == "close" then
		closePicker()
	end
end)

-- ─── E-key dispatch + hint ───────────────────────────────────────
local function findBedNearby()
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local raft = workspace:FindFirstChild("Raft")
	if not raft then return nil end
	local playerPos = hrp.Position
	local best, bestDist = nil, 15
	for _, m in raft:GetChildren() do
		if m:IsA("Model")
			and m:GetAttribute("IsBedGardenForTree")
			and m:GetAttribute("IsWatered")
			and not m:GetAttribute("GrowthStage")
		then
			local d = (playerPos - m:GetPivot().Position).Magnitude
			if d < bestDist then
				best, bestDist = m, d
			end
		end
	end
	return best
end

local function refreshHint()
	if pickerGui.Enabled then
		hintLabel.Visible = false
		return
	end
	if not currentTool or currentTool.Name ~= BAG_TOOL_NAME or not currentTool.Parent then
		hintLabel.Visible = false
		return
	end
	local bed = findBedNearby()
	hintLabel.Text    = bed and "[E] Plant from Seed Bag" or "[E] Open Seed Bag"
	hintLabel.Visible = true
end

RunService.Heartbeat:Connect(refreshHint)

UserInputService.InputBegan:Connect(function(input, processed)
	if UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.Escape and pickerGui.Enabled then
		closePicker()
		return
	end
	if input.KeyCode ~= Enum.KeyCode.E then return end
	-- Diagnostic trail. Each return is annotated so the Studio Output
	-- reveals which guard tripped when the bag won't open on E.
	if pickerGui.Enabled then
		print("[SeedBagUI] E ignored: picker already open")
		return
	end
	if processed then
		print("[SeedBagUI] E ignored: gameProcessed=true (another GUI consumed it)")
		return
	end
	if not currentTool then
		print("[SeedBagUI] E ignored: currentTool=nil (nothing equipped on the character)")
		return
	end
	if currentTool.Name ~= BAG_TOOL_NAME then
		print(("[SeedBagUI] E ignored: equipped tool is %q, expected %q"):format(currentTool.Name, BAG_TOOL_NAME))
		return
	end
	print(("[SeedBagUI] Firing open — bed=%s"):format(tostring(findBedNearby())))
	seedBagEvent:FireServer("open", findBedNearby())
end)

-- ─── Tool equip tracking ─────────────────────────────────────────
local function setupCharacter(char)
	if not char then return end
	currentTool = char:FindFirstChildWhichIsA("Tool")
	if currentTool then
		print(("[SeedBagUI] setupCharacter: initial tool=%q"):format(currentTool.Name))
	end
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			currentTool = child
			print(("[SeedBagUI] ChildAdded: equipped %q"):format(child.Name))
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if child == currentTool then
			print(("[SeedBagUI] ChildRemoved: unequipped %q"):format(child.Name))
			currentTool = nil
		end
	end)
end

if player.Character then setupCharacter(player.Character) end
player.CharacterAdded:Connect(setupCharacter)
