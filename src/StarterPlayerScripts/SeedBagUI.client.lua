-- SeedBagUI.client.lua
-- "Leaf bag" Tool interaction. When the player presses E with the bag
-- equipped while standing next to a watered Bed_Garden_For_Tree, the
-- server opens this picker UI listing every seed the player owns. They
-- click a slot to plant + close, or hit X / Esc to bail.
--
-- The "storage" framing in the design note is satisfied by the bag
-- being the entry point — the seeds themselves still live in the
-- player's main inventory (single source of truth, stacks survive
-- save/load via InventoryManager). If we later want a real per-bag
-- storage of 6 slots, the SeedBagAction protocol already has room for
-- a "deposit" / "withdraw" pair to be bolted on.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local seedBagEvent = ReplicatedStorage:WaitForChild("SeedBagAction")
local pickupEvent  = ReplicatedStorage:WaitForChild("PickupDroppedItem")

local BAG_TOOL_NAME = "leaf bag"
local DISPLAY_NAMES = {
	Banana_Seed    = "Banana Seed",
	Coconut_Seed   = "Coconut Seed",
	Pineapple_Seed = "Pineapple Seed",
}
local SEED_ICONS = {
	Banana_Seed    = "rbxassetid://73140419103065",
	Coconut_Seed   = "rbxassetid://138995623166184",
	Pineapple_Seed = "rbxassetid://128520746024640",
}

-- ─── Wood-palette constants (match the rest of the in-world UIs) ───
local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_WOOD_DARK    = Color3.fromRGB( 91,  58,  34)
local COLOR_WOOD_MID     = Color3.fromRGB(138, 106,  68)
local COLOR_WOOD_BASE    = Color3.fromRGB(176, 138,  92)
local COLOR_PAPER        = Color3.fromRGB(233, 217, 184)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(243, 230, 204)

-- ─── State ───
local currentBed       = nil   -- Model the server told us to plant on
local currentTool      = nil
local hintVisible      = false

-- ─── Hint label (matches the look of the FruitBushClient prompt) ───
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

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 8)
hintCorner.Parent       = hintLabel

-- ─── Picker UI ───
local pickerGui = Instance.new("ScreenGui")
pickerGui.Name           = "SeedBagPicker"
pickerGui.ResetOnSpawn   = false
pickerGui.IgnoreGuiInset = true
pickerGui.DisplayOrder   = 95
pickerGui.Enabled        = false
pickerGui.Parent         = playerGui

local backdrop = Instance.new("TextButton")
backdrop.Name                   = "Backdrop"
backdrop.Size                   = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
backdrop.BackgroundTransparency = 0.55
backdrop.BorderSizePixel        = 0
backdrop.AutoButtonColor        = false
backdrop.Text                   = ""
backdrop.Parent                 = pickerGui

local panel = Instance.new("Frame")
panel.AnchorPoint        = Vector2.new(0.5, 0.5)
panel.Position           = UDim2.fromScale(0.5, 0.5)
panel.Size               = UDim2.fromOffset(560, 220)
panel.BackgroundColor3   = COLOR_WOOD_BASE
panel.BorderSizePixel    = 0
panel.Parent             = pickerGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 18)
panelCorner.Parent       = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color     = COLOR_WOOD_DARKEST
panelStroke.Thickness = 3
panelStroke.Parent    = panel

local title = Instance.new("TextLabel")
title.AnchorPoint        = Vector2.new(0, 0)
title.Position           = UDim2.new(0, 18, 0, 14)
title.Size               = UDim2.new(1, -100, 0, 28)
title.BackgroundTransparency = 1
title.Text               = "Seed Bag — choose what to plant"
title.TextColor3         = COLOR_PAPER_LIGHT
title.TextXAlignment     = Enum.TextXAlignment.Left
title.Font               = Enum.Font.GothamBold
title.TextSize           = 18
title.Parent             = panel

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint       = Vector2.new(1, 0)
closeBtn.Position          = UDim2.new(1, -14, 0, 12)
closeBtn.Size              = UDim2.fromOffset(32, 32)
closeBtn.BackgroundColor3  = COLOR_WOOD_DARK
closeBtn.Text              = "×"
closeBtn.TextColor3        = COLOR_PAPER_LIGHT
closeBtn.Font              = Enum.Font.GothamBold
closeBtn.TextSize          = 20
closeBtn.Parent            = panel

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent       = closeBtn

local slotRow = Instance.new("Frame")
slotRow.AnchorPoint        = Vector2.new(0.5, 0)
slotRow.Position           = UDim2.new(0.5, 0, 0, 60)
slotRow.Size               = UDim2.new(1, -36, 0, 130)
slotRow.BackgroundTransparency = 1
slotRow.Parent             = panel

local slotLayout = Instance.new("UIListLayout")
slotLayout.FillDirection      = Enum.FillDirection.Horizontal
slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
slotLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
slotLayout.Padding            = UDim.new(0, 12)
slotLayout.SortOrder          = Enum.SortOrder.LayoutOrder
slotLayout.Parent             = slotRow

local SLOT_COUNT = 6  -- per user brief
local slots = {}

for i = 1, SLOT_COUNT do
	local slot = Instance.new("TextButton")
	slot.Name              = "Slot_" .. i
	slot.Size              = UDim2.fromOffset(80, 100)
	slot.BackgroundColor3  = COLOR_WOOD_MID
	slot.AutoButtonColor   = false
	slot.Text              = ""
	slot.LayoutOrder       = i
	slot.Parent            = slotRow

	local slotCorner = Instance.new("UICorner")
	slotCorner.CornerRadius = UDim.new(0, 10)
	slotCorner.Parent       = slot

	local slotStroke = Instance.new("UIStroke")
	slotStroke.Color       = COLOR_WOOD_DARK
	slotStroke.Thickness   = 2
	slotStroke.Parent      = slot

	local icon = Instance.new("ImageLabel")
	icon.Name                   = "Icon"
	icon.AnchorPoint            = Vector2.new(0.5, 0)
	icon.Position               = UDim2.new(0.5, 0, 0, 8)
	icon.Size                   = UDim2.fromOffset(56, 56)
	icon.BackgroundTransparency = 1
	icon.ScaleType              = Enum.ScaleType.Fit
	icon.Image                  = ""
	icon.Parent                 = slot

	local countLabel = Instance.new("TextLabel")
	countLabel.Name                   = "Count"
	countLabel.AnchorPoint            = Vector2.new(0.5, 1)
	countLabel.Position               = UDim2.new(0.5, 0, 1, -6)
	countLabel.Size                   = UDim2.new(1, -12, 0, 22)
	countLabel.BackgroundTransparency = 1
	countLabel.Text                   = ""
	countLabel.TextColor3             = COLOR_PAPER_LIGHT
	countLabel.Font                   = Enum.Font.GothamBold
	countLabel.TextSize               = 14
	countLabel.TextScaled             = false
	countLabel.Parent                 = slot

	slots[i] = { button = slot, icon = icon, count = countLabel, stroke = slotStroke, seed = nil }
end

-- ─── UI helpers ───
local function clearSlots()
	for _, s in ipairs(slots) do
		s.seed              = nil
		s.icon.Image        = ""
		s.count.Text        = ""
		s.button.BackgroundColor3 = COLOR_WOOD_MID
		s.stroke.Color      = COLOR_WOOD_DARK
		s.button.Active     = false
	end
end

local function paintSlots(seedList)
	clearSlots()
	-- Snapshot always returns SLOT_COUNT entries; empty ones carry
	-- name == "" / count == 0. We render filled slots with the paper
	-- background + icon, empty slots stay greyed out and unclickable.
	for i = 1, SLOT_COUNT do
		local entry = seedList and seedList[i]
		local s     = slots[i]
		if entry and entry.name and entry.name ~= "" and (entry.count or 0) > 0 then
			s.seed              = entry.name
			s.icon.Image        = SEED_ICONS[entry.name] or ""
			s.count.Text        = "x" .. tostring(entry.count) .. "  " .. (DISPLAY_NAMES[entry.name] or entry.name)
			s.button.BackgroundColor3 = COLOR_PAPER
			s.stroke.Color      = COLOR_WOOD_DARKEST
			s.button.Active     = true
		end
	end
end

local function closePicker()
	pickerGui.Enabled = false
	clearSlots()
end

-- Click handlers wire each slot once at build time. They no-op until
-- paintSlots assigns a seed. The server expects the slot INDEX (so it
-- can decrement the right Slot{i}_Count attribute on the bag), not
-- the seed name — multiple slots in the bag can hold the same seed
-- and we want to drain the specific one the player clicked.
for i, s in ipairs(slots) do
	s.button.MouseButton1Click:Connect(function()
		if not s.seed then return end
		if not currentBed or not currentBed.Parent then
			closePicker()
			return
		end
		seedBagEvent:FireServer("plant", currentBed, i)
	end)
end

closeBtn.MouseButton1Click:Connect(closePicker)
backdrop.MouseButton1Click:Connect(closePicker)

-- ─── Server → client events ───
seedBagEvent.OnClientEvent:Connect(function(action, bed, seedList)
	if action == "show" then
		currentBed = bed
		if typeof(seedList) ~= "table" or #seedList == 0 then
			-- No seeds at all — surface a quick toast in the title bar
			-- instead of opening an empty grid.
			title.Text = "Seed Bag — no seeds to plant"
			clearSlots()
		else
			title.Text = "Seed Bag — choose what to plant"
			paintSlots(seedList)
		end
		pickerGui.Enabled = true
	elseif action == "close" then
		closePicker()
	end
end)

-- ─── E-key dispatch + hint ───
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
	-- Hint is visible whenever the bag is equipped — pressing E opens
	-- the picker even when there isn't a watered bed within reach
	-- (the player just wants to inspect contents). When a bed IS in
	-- range the picker enables slot-clicks for planting.
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
	if pickerGui.Enabled then return end
	if processed then return end
	if not currentTool or currentTool.Name ~= BAG_TOOL_NAME then return end
	-- E always opens the bag while the bag is in hand — bed-nearby
	-- only affects whether the slot clicks actually plant something.
	-- We pass the nearest valid bed (if any) so the server can echo
	-- it back to us; nil simply means "viewing".
	seedBagEvent:FireServer("open", findBedNearby())
end)

-- ─── Pickup error toast ───
-- DropItem fires "needSeedBag" / "seedBagFull" when the player tries
-- to pick up a seed without a bag (or with full bags). We surface a
-- short centred toast so the cause is obvious instead of the seed
-- silently refusing to enter the inventory.
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

local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 8)
toastCorner.Parent       = toastLabel

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

-- ─── Tool equip tracking ───
local function setupCharacter(char)
	if not char then return end
	currentTool = char:FindFirstChildWhichIsA("Tool")
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then currentTool = child end
	end)
	char.ChildRemoved:Connect(function(child)
		if child == currentTool then currentTool = nil end
	end)
end

if player.Character then setupCharacter(player.Character) end
player.CharacterAdded:Connect(setupCharacter)
