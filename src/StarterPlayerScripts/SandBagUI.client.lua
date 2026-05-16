-- SandBagUI.client.lua
-- "Sand Bag" Tool interaction. Holding the bag and pressing E opens
-- a wood-palette inspection panel matching the user's design pass:
--
--   ┌──────────────────────────────────────────────────────────────┐
--   │ [🌿] Bag                                            [×]      │
--   ├──────────────────────────────────────────────────────────────┤
--   │                                                              │
--   │     ╔═══════════╗                  Sand                      │
--   │     ║  empty    ║         ┌───────────────────────────────┐  │
--   │     ║  bag art  ║         │  Fill Level                   │  │
--   │     ║  + sand   ║         │     N %                       │  │
--   │     ║  fill     ║         │  ▓▓▓▓░░░░░░░░░░░░░░░░         │  │
--   │     ╚═══════════╝         │  N / 100                      │  │
--   │                           └───────────────────────────────┘  │
--   │                                  [   Close   ]               │
--   └──────────────────────────────────────────────────────────────┘
--
-- The bag visual stacks two images:
--   * empty_bag (rbxassetid://100274201283741) — the leaf-bag art.
--   * mask (rbxassetid://124056134635393) — the tear-drop "inside"
--     of the bag, tinted sand-colour and clipped to a Frame whose
--     height tracks the bag's fill %. Anchored from the bottom so
--     the sand visibly "rises" as the bag fills.
--
-- Pickup error toasts ("You need a Sand Bag", "Your Sand Bag is
-- full") are routed through PickupDroppedItem so the message reaches
-- the player when DropItem rejects a ground pickup.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local sandBagEvent = ReplicatedStorage:WaitForChild("SandBagAction")
local pickupEvent  = ReplicatedStorage:WaitForChild("PickupDroppedItem")

local BAG_TOOL_NAME       = "Sand Bag"
local EMPTY_BAG_ASSET     = "rbxassetid://100274201283741"
local FILL_MASK_ASSET     = "rbxassetid://124056134635393"
local SAND_COLOR          = Color3.fromRGB(212, 178, 110)
local SAND_SHADOW_COLOR   = Color3.fromRGB(120,  96,  52)

-- Wood palette (matches every other in-world UI)
local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_WOOD_DARK    = Color3.fromRGB( 91,  58,  34)
local COLOR_WOOD_MID     = Color3.fromRGB(138, 106,  68)
local COLOR_WOOD_BASE    = Color3.fromRGB(176, 138,  92)
local COLOR_PAPER        = Color3.fromRGB(218, 199, 160)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(238, 222, 188)

local currentTool = nil

-- ── isBagTool soft matcher, mirroring the seed bag / leaf bag.
local function isBagTool(tool)
	if not tool or not tool:IsA("Tool") then return false end
	local a = tool.Name:lower():gsub("[_%s]", "")
	local b = BAG_TOOL_NAME:lower():gsub("[_%s]", "")
	return a == b
end

-- ─── Hint label ─────────────────────────────────────────────────
local hintGui = Instance.new("ScreenGui")
hintGui.Name           = "SandBagHint"
hintGui.ResetOnSpawn   = false
hintGui.IgnoreGuiInset = true
hintGui.DisplayOrder   = 47
hintGui.Parent         = playerGui

local hintLabel = Instance.new("TextLabel")
hintLabel.AnchorPoint            = Vector2.new(0.5, 1)
hintLabel.Position               = UDim2.new(0.5, 0, 0.78, 0)
hintLabel.Size                   = UDim2.new(0, 260, 0, 34)
hintLabel.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
hintLabel.BackgroundTransparency = 0.4
hintLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
hintLabel.Font                   = Enum.Font.GothamBold
hintLabel.TextSize               = 16
hintLabel.Text                   = "[E] Open Sand Bag"
hintLabel.Visible                = false
hintLabel.Parent                 = hintGui
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent       = hintLabel
end

-- ─── Pickup error toast ─────────────────────────────────────────
local toastLabel = Instance.new("TextLabel")
toastLabel.AnchorPoint            = Vector2.new(0.5, 0.5)
toastLabel.Position               = UDim2.new(0.5, 0, 0.42, 0)
toastLabel.Size                   = UDim2.new(0, 360, 0, 44)
toastLabel.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
toastLabel.BackgroundTransparency = 0.35
toastLabel.TextColor3             = Color3.fromRGB(255, 220, 120)
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
		if myJob == toastJob then toastLabel.Visible = false end
	end)
end

pickupEvent.OnClientEvent:Connect(function(action)
	if action == "needSandBag" then
		showToast("You need a Sand Bag to carry sand.")
	elseif action == "sandBagFull" then
		showToast("Your Sand Bag is full.")
	end
end)

-- ─── Inspection panel ───────────────────────────────────────────
local pickerGui = Instance.new("ScreenGui")
pickerGui.Name           = "SandBagPicker"
pickerGui.ResetOnSpawn   = false
pickerGui.IgnoreGuiInset = true
pickerGui.DisplayOrder   = 96
pickerGui.Enabled        = false
pickerGui.Parent         = playerGui

-- Invisible Modal button so the camera script releases the cursor
-- while the panel is visible (same trick the leaf bag UI uses).
do
	local btn = Instance.new("TextButton")
	btn.Name                 = "__ModalUnlock"
	btn.Modal                = true
	btn.Active               = true
	btn.BackgroundTransparency = 1
	btn.TextTransparency     = 1
	btn.Text                 = ""
	btn.AutoButtonColor      = false
	btn.Size                 = UDim2.fromOffset(1, 1)
	btn.ZIndex               = 1
	btn.Parent               = pickerGui
end

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
panel.Size            = UDim2.fromScale(0.55, 0.55)
panel.BackgroundColor3 = COLOR_WOOD_BASE
panel.BorderSizePixel = 0
panel.Parent          = pickerGui
do
	local sc = Instance.new("UISizeConstraint")
	sc.MinSize = Vector2.new(560, 340)
	sc.MaxSize = Vector2.new(820, 520)
	sc.Parent  = panel
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 820 / 520
	ar.Parent = panel
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 18)
	c.Parent       = panel
	local s = Instance.new("UIStroke")
	s.Color     = COLOR_WOOD_DARKEST
	s.Thickness = 3
	s.Parent    = panel
end

-- Header
local header = Instance.new("Frame")
header.Size               = UDim2.new(1, -28, 0, 70)
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
bagIcon.Size                   = UDim2.fromOffset(50, 50)
bagIcon.Position               = UDim2.new(0, 10, 0.5, -25)
bagIcon.BackgroundTransparency = 1
bagIcon.Image                  = EMPTY_BAG_ASSET
bagIcon.ScaleType              = Enum.ScaleType.Fit
bagIcon.Parent                 = header

local titleLabel = Instance.new("TextLabel")
titleLabel.AnchorPoint            = Vector2.new(0, 0.5)
titleLabel.Position               = UDim2.new(0, 70, 0.5, 0)
titleLabel.Size                   = UDim2.new(1, -130, 0.7, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text                   = "Bag"
titleLabel.TextColor3             = COLOR_WOOD_DARKEST
titleLabel.TextXAlignment         = Enum.TextXAlignment.Left
titleLabel.TextYAlignment         = Enum.TextYAlignment.Center
titleLabel.Font                   = Enum.Font.GothamBold
titleLabel.TextScaled             = true
titleLabel.Parent                 = header
do
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 26
	sc.MinTextSize = 14
	sc.Parent      = titleLabel
end

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint            = Vector2.new(1, 0.5)
closeBtn.Position               = UDim2.new(1, -10, 0.5, 0)
closeBtn.Size                   = UDim2.fromOffset(40, 40)
closeBtn.BackgroundColor3       = COLOR_WOOD_DARK
closeBtn.Text                   = "×"
closeBtn.TextColor3             = COLOR_PAPER_LIGHT
closeBtn.Font                   = Enum.Font.GothamBold
closeBtn.TextSize               = 24
closeBtn.AutoButtonColor        = false
closeBtn.Parent                 = header
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent       = closeBtn
end

-- ── Body: left bag visual, right info panel ─────────────────
local body = Instance.new("Frame")
body.Size               = UDim2.new(1, -28, 1, -100)
body.Position           = UDim2.new(0, 14, 0, 92)
body.BackgroundTransparency = 1
body.Parent             = panel

-- Left bag visual area.
local bagArea = Instance.new("Frame")
bagArea.AnchorPoint            = Vector2.new(0, 0.5)
bagArea.Position               = UDim2.new(0, 0, 0.5, 0)
bagArea.Size                   = UDim2.new(0.45, 0, 1, 0)
bagArea.BackgroundTransparency = 1
bagArea.Parent                 = body

local bagImage = Instance.new("ImageLabel")
bagImage.AnchorPoint            = Vector2.new(0.5, 0.5)
bagImage.Position               = UDim2.fromScale(0.5, 0.5)
bagImage.Size                   = UDim2.fromScale(1, 1)
bagImage.BackgroundTransparency = 1
bagImage.Image                  = EMPTY_BAG_ASSET
bagImage.ScaleType              = Enum.ScaleType.Fit
bagImage.Parent                 = bagArea
do
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 832 / 1015  -- matches the supplied empty_bag art
	ar.Parent      = bagImage
end

-- Fill mask frame — clips the sand-tinted mask to the bottom N % of
-- the bag's bounding box. AnchorPoint(0.5, 1) anchors the clip area
-- to the bag's BOTTOM so the sand visibly fills upward.
local fillClip = Instance.new("Frame")
fillClip.AnchorPoint            = Vector2.new(0.5, 1)
fillClip.Position               = UDim2.new(0.5, 0, 1, 0)
fillClip.Size                   = UDim2.new(1, 0, 0, 0)  -- height set at runtime
fillClip.BackgroundTransparency = 1
fillClip.ClipsDescendants       = true
fillClip.Parent                 = bagImage

-- The mask image, full-size, anchored to fillClip's bottom so its
-- bottom edge stays aligned with the bag's bottom as fillClip
-- changes height.
local fillMask = Instance.new("ImageLabel")
fillMask.AnchorPoint            = Vector2.new(0.5, 1)
fillMask.Position               = UDim2.new(0.5, 0, 1, 0)
fillMask.Size                   = UDim2.fromScale(1, 1)
fillMask.SizeConstraint         = Enum.SizeConstraint.RelativeXY
fillMask.BackgroundTransparency = 1
fillMask.Image                  = FILL_MASK_ASSET
fillMask.ImageColor3            = SAND_COLOR
fillMask.ScaleType              = Enum.ScaleType.Fit
fillMask.Parent                 = fillClip
-- The fillMask Size is in fillClip's RelativeXY space — that means
-- when fillClip's height shrinks, fillMask shrinks too. We want the
-- mask to stay at the BAG's full size so it doesn't squish. Override
-- by sizing the mask in offset pixels matched to bagImage on every
-- AbsoluteSize change.

local function refitFillMask()
	local w = bagImage.AbsoluteSize.X
	local h = bagImage.AbsoluteSize.Y
	if w <= 0 or h <= 0 then return end
	fillMask.Size = UDim2.fromOffset(w, h)
end
bagImage:GetPropertyChangedSignal("AbsoluteSize"):Connect(refitFillMask)
task.defer(refitFillMask)

-- Subtle shadow / depth tint underneath the fill — a second copy of
-- the mask, darker, offset down a hair so the sand reads as having
-- volume instead of being a flat tint.
local fillShadow = fillMask:Clone()
fillShadow.ImageColor3       = SAND_SHADOW_COLOR
fillShadow.ImageTransparency = 0.65
fillShadow.Position          = UDim2.new(0.5, 0, 1, 4)
fillShadow.ZIndex            = fillMask.ZIndex - 1
fillShadow.Parent            = fillClip

-- Right info panel.
local infoPanel = Instance.new("Frame")
infoPanel.AnchorPoint            = Vector2.new(1, 0.5)
infoPanel.Position               = UDim2.new(1, 0, 0.5, 0)
infoPanel.Size                   = UDim2.new(0.5, -14, 1, 0)
infoPanel.BackgroundTransparency = 1
infoPanel.Parent                 = body

local sandName = Instance.new("TextLabel")
sandName.AnchorPoint            = Vector2.new(0.5, 0)
sandName.Position               = UDim2.new(0.5, 0, 0.03, 0)
sandName.Size                   = UDim2.new(0.9, 0, 0.16, 0)
sandName.BackgroundTransparency = 1
sandName.Text                   = "Sand"
sandName.TextColor3             = COLOR_WOOD_DARKEST
sandName.Font                   = Enum.Font.GothamBold
sandName.TextScaled             = true
sandName.Parent                 = infoPanel
do
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 30
	sc.MinTextSize = 14
	sc.Parent      = sandName
end

local fillBox = Instance.new("Frame")
fillBox.AnchorPoint            = Vector2.new(0.5, 0)
fillBox.Position               = UDim2.new(0.5, 0, 0.22, 0)
fillBox.Size                   = UDim2.new(0.95, 0, 0.55, 0)
fillBox.BackgroundColor3       = COLOR_PAPER
fillBox.BackgroundTransparency = 0.15
fillBox.BorderSizePixel        = 0
fillBox.Parent                 = infoPanel
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent       = fillBox
end

local fillLevelLabel = Instance.new("TextLabel")
fillLevelLabel.AnchorPoint            = Vector2.new(0.5, 0)
fillLevelLabel.Position               = UDim2.new(0.5, 0, 0.08, 0)
fillLevelLabel.Size                   = UDim2.new(0.9, 0, 0.18, 0)
fillLevelLabel.BackgroundTransparency = 1
fillLevelLabel.Text                   = "Fill Level"
fillLevelLabel.TextColor3             = COLOR_WOOD_DARKEST
fillLevelLabel.Font                   = Enum.Font.GothamBold
fillLevelLabel.TextScaled             = true
fillLevelLabel.Parent                 = fillBox
do
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 18
	sc.MinTextSize = 10
	sc.Parent      = fillLevelLabel
end

local percentLabel = Instance.new("TextLabel")
percentLabel.AnchorPoint            = Vector2.new(0.5, 0)
percentLabel.Position               = UDim2.new(0.5, 0, 0.28, 0)
percentLabel.Size                   = UDim2.new(0.9, 0, 0.28, 0)
percentLabel.BackgroundTransparency = 1
percentLabel.Text                   = "0 %"
percentLabel.TextColor3             = COLOR_WOOD_DARKEST
percentLabel.Font                   = Enum.Font.GothamBold
percentLabel.TextScaled             = true
percentLabel.Parent                 = fillBox
do
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 40
	sc.MinTextSize = 18
	sc.Parent      = percentLabel
end

local barBg = Instance.new("Frame")
barBg.AnchorPoint            = Vector2.new(0.5, 0)
barBg.Position               = UDim2.new(0.5, 0, 0.62, 0)
barBg.Size                   = UDim2.new(0.85, 0, 0.13, 0)
barBg.BackgroundColor3       = COLOR_PAPER_LIGHT
barBg.BorderSizePixel        = 0
barBg.Parent                 = fillBox
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent       = barBg
end

local barFill = Instance.new("Frame")
barFill.AnchorPoint            = Vector2.new(0, 0.5)
barFill.Position               = UDim2.fromScale(0, 0.5)
barFill.Size                   = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3       = COLOR_WOOD_MID
barFill.BorderSizePixel        = 0
barFill.Parent                 = barBg
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent       = barFill
end

local countLabel = Instance.new("TextLabel")
countLabel.AnchorPoint            = Vector2.new(0.5, 0)
countLabel.Position               = UDim2.new(0.5, 0, 0.8, 0)
countLabel.Size                   = UDim2.new(0.9, 0, 0.16, 0)
countLabel.BackgroundTransparency = 1
countLabel.Text                   = "0 / 100"
countLabel.TextColor3             = COLOR_WOOD_DARKEST
countLabel.Font                   = Enum.Font.GothamSemibold
countLabel.TextScaled             = true
countLabel.Parent                 = fillBox
do
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 22
	sc.MinTextSize = 12
	sc.Parent      = countLabel
end

local closeBigBtn = Instance.new("TextButton")
closeBigBtn.AnchorPoint            = Vector2.new(0.5, 1)
closeBigBtn.Position               = UDim2.new(0.5, 0, 0.97, 0)
closeBigBtn.Size                   = UDim2.new(0.85, 0, 0.16, 0)
closeBigBtn.BackgroundColor3       = COLOR_WOOD_MID
closeBigBtn.Text                   = "Close"
closeBigBtn.TextColor3             = COLOR_PAPER_LIGHT
closeBigBtn.Font                   = Enum.Font.GothamBold
closeBigBtn.TextScaled             = true
closeBigBtn.AutoButtonColor        = false
closeBigBtn.Parent                 = infoPanel
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent       = closeBigBtn
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 22
	sc.MinTextSize = 12
	sc.Parent      = closeBigBtn
end

-- ── State + paint ───────────────────────────────────────────────
local function paintFill(fill, max)
	fill = tonumber(fill) or 0
	max  = tonumber(max)  or 100
	local pct = math.clamp(fill / max, 0, 1)
	percentLabel.Text  = string.format("%d%%", math.floor(pct * 100 + 0.5))
	countLabel.Text    = string.format("%d / %d", math.floor(fill + 0.5), math.floor(max + 0.5))
	barFill.Size       = UDim2.new(pct, 0, 1, 0)
	-- Drive the bag visual fill — fillClip's height = pct of bagImage.
	fillClip.Size      = UDim2.new(1, 0, pct, 0)
end
paintFill(0, 100)

local function closePicker()
	pickerGui.Enabled = false
end

closeBtn.MouseButton1Click:Connect(closePicker)
closeBigBtn.MouseButton1Click:Connect(closePicker)
backdrop.MouseButton1Click:Connect(closePicker)

sandBagEvent.OnClientEvent:Connect(function(action, fill, max)
	if action == "show" then
		paintFill(fill, max)
		pickerGui.Enabled = true
	elseif action == "close" then
		closePicker()
	end
end)

-- ── E-key dispatch + hint ────────────────────────────────────────
local function refreshHint()
	if pickerGui.Enabled then
		hintLabel.Visible = false
		return
	end
	if currentTool and isBagTool(currentTool) and currentTool.Parent then
		hintLabel.Visible = true
	else
		hintLabel.Visible = false
	end
end
RunService.Heartbeat:Connect(refreshHint)

UserInputService.InputBegan:Connect(function(input, processed)
	if UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.Escape and pickerGui.Enabled then
		closePicker()
		return
	end
	if input.KeyCode ~= Enum.KeyCode.E then return end
	if pickerGui.Enabled then
		closePicker()
		return
	end
	if processed then return end
	if not currentTool or not isBagTool(currentTool) then return end
	sandBagEvent:FireServer("open")
end)

-- ── Tool equip tracking ────────────────────────────────────────
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

print("[SandBagUI] script loaded — listening on E. BAG_TOOL_NAME=" .. BAG_TOOL_NAME)
