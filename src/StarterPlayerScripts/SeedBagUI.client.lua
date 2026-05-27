-- SeedBagUI.client.lua
-- "Leaf bag" Tool interaction. While the bag is in hand, pressing E
-- opens the seed picker; if the player is also next to a watered
-- Bed_T, the picker's "Plant" button is enabled and
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
local SLOT_COUNT    = 6
local GRID_COLS     = 3
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

-- Soft match: lowercase + strip spaces / underscores so a "Leaf Bag"
-- or "leafbag" rename from the user doesn't break the picker. Has
-- to live up here so refreshHint / InputBegan / setupCharacter
-- (defined later in the script) all see it as a local upvalue and
-- not a (nil) global.
local function isBagTool(tool)
	if not tool or not tool:IsA("Tool") then return false end
	local name = tool.Name:lower():gsub("[_%s]", "")
	return name == BAG_TOOL_NAME:lower():gsub("[_%s]", "")
end

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

-- Invisible Modal GuiButton — Roblox's camera script releases the
-- mouse cursor (Default behaviour, free to move) whenever ANY visible
-- Modal button exists in PlayerGui. ModalUIUnlocker does the same
-- trick for WorkbenchGui / InventoryGui / etc.; we attach our own
-- here so the seed picker doesn't have to live on that whitelist.
local modalUnlock = Instance.new("TextButton")
modalUnlock.Name                 = "__ModalUnlock"
modalUnlock.Modal                = true
modalUnlock.Active               = true
modalUnlock.BackgroundTransparency = 1
modalUnlock.TextTransparency     = 1
modalUnlock.Text                 = ""
modalUnlock.AutoButtonColor      = false
modalUnlock.Size                 = UDim2.fromOffset(1, 1)
modalUnlock.Position             = UDim2.fromOffset(0, 0)
modalUnlock.ZIndex               = 1
modalUnlock.Parent               = pickerGui

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
-- Scale to ~65% of the viewport so the panel reads well on both
-- laptop screens and 4K monitors. UISizeConstraint clamps to a
-- sensible min/max — keeps slot cards legible on small screens and
-- prevents the panel from sprawling on a 4K display.
panel.Size            = UDim2.fromScale(0.55, 0.65)
panel.BackgroundColor3 = COLOR_WOOD_BASE
panel.BorderSizePixel = 0
panel.Parent          = pickerGui

do
	local sc = Instance.new("UISizeConstraint")
	sc.MinSize = Vector2.new(560, 360)
	sc.MaxSize = Vector2.new(820, 540)
	sc.Parent  = panel

	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 820 / 540   -- maintain the design's ratio
	ar.DominantAxis = Enum.DominantAxis.Width
	ar.Parent = panel

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 18)
	c.Parent       = panel
	local s = Instance.new("UIStroke")
	s.Color     = COLOR_WOOD_DARKEST
	s.Thickness = 3
	s.Parent    = panel
end

-- ── Header strip ─────────────────────────────────────────────────
local header = Instance.new("Frame")
header.Size               = UDim2.new(1, -28, 0, 80)
header.Position           = UDim2.new(0, 14, 0, 14)
header.BackgroundColor3   = COLOR_WOOD_MID
header.BorderSizePixel    = 0
header.Parent             = panel
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent       = header
end

local bagIcon = Instance.new("ImageLabel")
bagIcon.Size                   = UDim2.fromOffset(56, 56)
bagIcon.Position               = UDim2.new(0, 10, 0.5, -28)
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
titleLabel.TextScaled         = true
titleLabel.Parent             = header
do
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 24
	sc.MinTextSize = 12
	sc.Parent      = titleLabel
end

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.AnchorPoint            = Vector2.new(0, 0.5)
subtitleLabel.Position               = UDim2.new(0, 88, 0.5, 16)
subtitleLabel.Size                   = UDim2.new(1, -260, 0, 22)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text                   = "Choose what to plant"
subtitleLabel.TextColor3             = COLOR_PAPER_LIGHT
subtitleLabel.TextXAlignment         = Enum.TextXAlignment.Left
subtitleLabel.TextYAlignment         = Enum.TextYAlignment.Center
subtitleLabel.TextTransparency       = 0.2
subtitleLabel.Font                   = Enum.Font.Gotham
subtitleLabel.TextScaled             = true
subtitleLabel.Parent                 = header
do
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 18
	sc.MinTextSize = 10
	sc.Parent      = subtitleLabel
end

local counterFrame = Instance.new("Frame")
counterFrame.AnchorPoint        = Vector2.new(1, 0.5)
counterFrame.Position           = UDim2.new(1, -64, 0.5, 0)
counterFrame.Size               = UDim2.fromOffset(80, 38)
counterFrame.BackgroundColor3   = COLOR_WOOD_BASE
counterFrame.BorderSizePixel    = 0
counterFrame.Parent             = header
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent       = counterFrame
end

local counterLabel = Instance.new("TextLabel")
counterLabel.Size               = UDim2.new(1, -16, 1, -8)
counterLabel.Position           = UDim2.new(0, 8, 0, 4)
counterLabel.BackgroundTransparency = 1
counterLabel.Text               = "0 / " .. SLOT_COUNT
counterLabel.TextColor3         = COLOR_PAPER_LIGHT
counterLabel.Font               = Enum.Font.GothamBold
counterLabel.TextScaled         = true
counterLabel.Parent             = counterFrame
do
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 22
	sc.MinTextSize = 10
	sc.Parent      = counterLabel
end

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint            = Vector2.new(1, 0.5)
closeBtn.Position               = UDim2.new(1, -12, 0.5, 0)
closeBtn.Size                   = UDim2.fromOffset(38, 38)
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
local GRID_LEFT   = 14
local GRID_TOP    = 110
local DETAIL_W    = 220
local CARD_GAP    = 10
local DETAIL_GAP  = 14
local GRID_BOTTOM = 44

local gridFrame = Instance.new("Frame")
gridFrame.Position           = UDim2.new(0, GRID_LEFT, 0, GRID_TOP)
gridFrame.Size               = UDim2.new(1, -GRID_LEFT - DETAIL_W - DETAIL_GAP - GRID_LEFT, 1, -GRID_TOP - GRID_BOTTOM)
gridFrame.BackgroundTransparency = 1
gridFrame.Parent             = panel

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellPadding   = UDim2.fromOffset(CARD_GAP, CARD_GAP)
-- CellSize is recomputed on every AbsoluteSize change below — Scale-
-- based sizing didn't account for CellPadding and overflowed the
-- grid frame, spilling slot cards out the bottom.
gridLayout.CellSize      = UDim2.fromOffset(80, 80)
gridLayout.FillDirection = Enum.FillDirection.Horizontal
gridLayout.SortOrder     = Enum.SortOrder.LayoutOrder
gridLayout.StartCorner   = Enum.StartCorner.TopLeft
gridLayout.Parent        = gridFrame

local function refitGridCells()
	local w = gridFrame.AbsoluteSize.X
	local h = gridFrame.AbsoluteSize.Y
	if w <= 0 or h <= 0 then return end
	-- Subtract the gaps between cells, then divide by the count.
	local cellW = math.floor((w - (GRID_COLS - 1) * CARD_GAP) / GRID_COLS)
	local cellH = math.floor((h - (GRID_ROWS - 1) * CARD_GAP) / GRID_ROWS)
	if cellW <= 0 or cellH <= 0 then return end
	gridLayout.CellSize = UDim2.fromOffset(cellW, cellH)
end

gridFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(refitGridCells)
task.defer(refitGridCells)

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
	icon.AnchorPoint            = Vector2.new(0.5, 0.5)
	icon.Position               = UDim2.fromScale(0.5, 0.5)
	-- Without the name label below, the icon owns the whole card —
	-- 85% of each axis so the rounded corners still read clearly.
	icon.Size                   = UDim2.new(0.85, 0, 0.85, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType              = Enum.ScaleType.Fit
	icon.Image                  = ""
	icon.Parent                 = card

	-- "xN" badge bottom-center, sized as a fraction of the card so
	-- the chip stays proportional at every panel scale.
	local badge = Instance.new("Frame")
	badge.AnchorPoint            = Vector2.new(0.5, 1)
	badge.Position               = UDim2.new(0.5, 0, 0.97, 0)
	badge.Size                   = UDim2.new(0.45, 0, 0.16, 0)
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
	badgeLabel.TextScaled             = true
	badgeLabel.Parent                 = badge
	do
		local sc = Instance.new("UITextSizeConstraint")
		sc.MaxTextSize = 14
		sc.MinTextSize = 8
		sc.Parent      = badgeLabel
	end

	-- Empty-state placeholder: a faint sprout icon when no seed.
	-- Scale-sized so it tracks the card's current size.
	local emptyIcon = Instance.new("ImageLabel")
	emptyIcon.AnchorPoint            = Vector2.new(0.5, 0.5)
	emptyIcon.Position               = UDim2.fromScale(0.5, 0.5)
	emptyIcon.Size                   = UDim2.new(0.45, 0, 0.45, 0)
	emptyIcon.BackgroundTransparency = 1
	emptyIcon.ImageTransparency      = 0.7
	emptyIcon.Image                  = ""
	emptyIcon.ScaleType              = Enum.ScaleType.Fit
	emptyIcon.Parent                 = card

	slots[i] = {
		button     = card,
		icon       = icon,
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

-- Scale-based layout — every element below uses Scale Y so the
-- panel re-tiles cleanly when the outer UISizeConstraint clamps the
-- panel to a different absolute height. The info-box rows + hint
-- line were removed per user feedback; the detail panel is now
-- icon → name → Plant button, top to bottom.
local detailIcon = Instance.new("ImageLabel")
detailIcon.AnchorPoint            = Vector2.new(0.5, 0)
detailIcon.Position               = UDim2.new(0.5, 0, 0.05, 0)
detailIcon.Size                   = UDim2.new(0.8, 0, 0.55, 0)
detailIcon.BackgroundTransparency = 1
detailIcon.ScaleType              = Enum.ScaleType.Fit
detailIcon.Image                  = ""
detailIcon.Parent                 = detail

local detailName = Instance.new("TextLabel")
detailName.AnchorPoint            = Vector2.new(0.5, 0)
detailName.Position               = UDim2.new(0.5, 0, 0.65, 0)
detailName.Size                   = UDim2.new(0.9, 0, 0.13, 0)
detailName.BackgroundTransparency = 1
detailName.Text                   = "Select a seed"
detailName.TextColor3             = COLOR_WOOD_DARKEST
detailName.Font                   = Enum.Font.GothamBold
detailName.TextScaled             = true
detailName.Parent                 = detail
do
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 20
	sc.MinTextSize = 10
	sc.Parent      = detailName
end

-- Info-box ("Grows into" / "Time") + plantHint removed per user
-- feedback — the detail panel now shows only the icon, name, and
-- the Plant button. Anything else lived as text spilling over the
-- button when the icon got tall.

local plantBtn = Instance.new("TextButton")
plantBtn.AnchorPoint            = Vector2.new(0.5, 1)
plantBtn.Position               = UDim2.new(0.5, 0, 0.95, 0)
plantBtn.Size                   = UDim2.new(0.9, 0, 0.18, 0)
plantBtn.BackgroundColor3       = COLOR_GREEN_OK
plantBtn.Text                   = "Plant"
plantBtn.TextColor3             = Color3.fromRGB(245, 245, 240)
plantBtn.Font                   = Enum.Font.GothamBold
plantBtn.TextScaled             = true
plantBtn.AutoButtonColor        = false
plantBtn.Active                 = false
plantBtn.Parent                 = detail
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 12)
	c.Parent       = plantBtn
	-- Scale-text but cap so the label doesn't blow up on a tiny string.
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 22
	sc.MinTextSize = 10
	sc.Parent      = plantBtn
end

-- plantHint removed — user asked for no auxiliary text under the
-- seed name in the detail panel. The Plant button's BackgroundColor
-- + Active state alone signals whether the player can plant right
-- now (bright green = plantable, dim green = need to step up to a
-- watered bed first).

local tipLabel = Instance.new("TextLabel")
tipLabel.AnchorPoint            = Vector2.new(0.5, 1)
tipLabel.Position               = UDim2.new(0.5, 0, 1, -22)
tipLabel.Size                   = UDim2.new(1, -64, 0, 22)
tipLabel.BackgroundTransparency = 1
tipLabel.Text                   = "Tip: Click a seed to select it, then click \"Plant\"."
tipLabel.TextColor3             = COLOR_PAPER_LIGHT
tipLabel.Font                   = Enum.Font.Gotham
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
		local meta = SEED_META[seedName] or { display = seedName, icon = "" }
		detailIcon.Image          = meta.icon
		detailName.Text           = meta.display
		plantBtn.Visible          = true
		plantBtn.Text             = "Plant"
		-- Plant hands the seed Tool to the player; they aim and place
		-- themselves. No bed-proximity check anymore — the button is
		-- live as soon as a seed slot is selected.
		plantBtn.Active           = true
		plantBtn.BackgroundColor3 = COLOR_GREEN_OK
	else
		detailIcon.Image          = ""
		detailName.Text           = "Select a seed"
		plantBtn.Visible          = true
		plantBtn.Text             = "Plant"
		plantBtn.Active           = false
		plantBtn.BackgroundColor3 = COLOR_GREEN_DIM
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
	if not currentSelection then return end
	if not slots[currentSelection] or not slots[currentSelection].seed then return end
	-- Pass currentBed verbatim — server ignores it for the new
	-- equip-to-hand flow but keeping the arg slot avoids changing the
	-- shared RemoteEvent signature.
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
	if not currentTool or not currentTool.Parent or not isBagTool(currentTool) then
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
	-- E also closes the picker if it's already open — symmetrical with
	-- Escape, and matches "press the same key to toggle" muscle memory.
	if pickerGui.Enabled then
		closePicker()
		return
	end
	-- Diagnostic trail. Each return is annotated so the Studio Output
	-- reveals which guard tripped when the bag won't open on E.
	if processed then
		print("[SeedBagUI] E ignored: gameProcessed=true (another GUI consumed it)")
		return
	end
	if not currentTool then
		print("[SeedBagUI] E ignored: currentTool=nil (nothing equipped on the character)")
		return
	end
	if not isBagTool(currentTool) then
		print(("[SeedBagUI] E ignored: equipped tool is %q, expected %q"):format(currentTool.Name, BAG_TOOL_NAME))
		return
	end
	print(("[SeedBagUI] Firing open — bed=%s"):format(tostring(findBedNearby())))
	seedBagEvent:FireServer("open", findBedNearby())
end)

-- ─── Tool equip tracking ─────────────────────────────────────────
-- isBagTool moved up the file (above refreshHint / InputBegan /
-- setupCharacter) — Lua locals declared after a function definition
-- aren't visible inside that function's body, so the previous
-- ordering had every isBagTool call resolve to a nil global and
-- silently error on each Heartbeat / E press.

local function setupCharacter(char)
	if not char then return end
	currentTool = char:FindFirstChildWhichIsA("Tool")
	if currentTool then
		print(("[SeedBagUI] setupCharacter: initial tool=%q (isBag=%s)"):format(currentTool.Name, tostring(isBagTool(currentTool))))
	end
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			currentTool = child
			print(("[SeedBagUI] ChildAdded: equipped %q (isBag=%s)"):format(child.Name, tostring(isBagTool(child))))
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

print("[SeedBagUI] script loaded — listening on E. BAG_TOOL_NAME=" .. BAG_TOOL_NAME)
