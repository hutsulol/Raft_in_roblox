-- SandBagUI.client.lua
-- "Sand Bag" Tool interaction. Holding the bag and pressing E opens
-- a wood-palette inspection panel that shows the current bag visual,
-- a numeric fill % and a progress bar.
--
-- The bag visual stacks six prerendered textures, one per fill stage
-- (0, 10, 30, 50, 70, 100 %). The "current" stage texture sits on the
-- bottom, the "next" stage texture sits on top inside a bottom-anchored
-- ClipsDescendants frame whose height grows from 0 to the bag's full
-- height as fill rises from the current stage to the next — so the new
-- sand level smoothly washes upward. Stage transitions are tweened.
--
-- Pickup error toasts ("You need a Sand Bag", "Your Sand Bag is
-- full") are routed through PickupDroppedItem so the message reaches
-- the player when DropItem rejects a ground pickup.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local sandBagEvent = ReplicatedStorage:WaitForChild("SandBagAction")
local pickupEvent  = ReplicatedStorage:WaitForChild("PickupDroppedItem")

local BAG_TOOL_NAME       = "Sand Bag"
local EMPTY_BAG_ASSET     = "rbxassetid://107012847180882"

-- Ordered stages: each entry is { pct, image }. The renderer picks the
-- highest stage whose pct is <= the current fill as the base layer,
-- and the next stage above as the overlay (clipped from the bottom).
local FILL_STAGES = {
	{ pct =   0, image = "rbxassetid://107012847180882" },
	{ pct =  10, image = "rbxassetid://87535824644391"  },
	{ pct =  30, image = "rbxassetid://102984915310557" },
	{ pct =  50, image = "rbxassetid://132918131694676" },
	{ pct =  70, image = "rbxassetid://135545427179049" },
	{ pct = 100, image = "rbxassetid://76170913773356"  },
}

-- Stage textures + close art are preloaded from
-- ReplicatedFirst/AssetPreload.client.lua during the loading screen,
-- so they're already in ContentProvider's cache by the time any of
-- this UI is built.

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

-- Close button image (same wood-X asset used by the quests panel).
local CLOSE_BTN_ASSET = "rbxassetid://76127527205295"

-- ── Body: left bag visual, right info panel ─────────────────
-- The body now fills the whole panel (the title-bar header was removed
-- on the user's request — Sand label + a small inline close button at
-- the top of the info column do all the framing work it was doing).
local body = Instance.new("Frame")
body.Size               = UDim2.new(1, -28, 1, -28)
body.Position           = UDim2.new(0, 14, 0, 14)
body.BackgroundTransparency = 1
body.Parent             = panel

-- Left bag visual area.
local bagArea = Instance.new("Frame")
bagArea.AnchorPoint            = Vector2.new(0, 0.5)
bagArea.Position               = UDim2.new(0, 0, 0.5, 0)
bagArea.Size                   = UDim2.new(0.45, 0, 1, 0)
bagArea.BackgroundTransparency = 1
bagArea.Parent                 = body

-- Bag visual: anchor frame that keeps the aspect ratio fixed and holds
-- the layered stage textures.
local bagImage = Instance.new("Frame")
bagImage.AnchorPoint            = Vector2.new(0.5, 0.5)
bagImage.Position               = UDim2.fromScale(0.5, 0.5)
bagImage.Size                   = UDim2.fromScale(1, 1)
bagImage.BackgroundTransparency = 1
bagImage.Parent                 = bagArea
do
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 832 / 1015  -- matches the supplied empty_bag art
	ar.Parent      = bagImage
end

-- Base layer: the texture at the current fill stage. Full size, fills
-- the bag frame.
local baseImage = Instance.new("ImageLabel")
baseImage.AnchorPoint            = Vector2.new(0.5, 0.5)
baseImage.Position               = UDim2.fromScale(0.5, 0.5)
baseImage.Size                   = UDim2.fromScale(1, 1)
baseImage.BackgroundTransparency = 1
baseImage.Image                  = EMPTY_BAG_ASSET
baseImage.ScaleType              = Enum.ScaleType.Fit
baseImage.ZIndex                 = 1
baseImage.Parent                 = bagImage

-- Overlay clip: anchored to the bag's bottom, grows upward as fill
-- progresses between two stages. ClipsDescendants reveals the overlay
-- image as a horizontal band that rises from the bottom.
local overlayClip = Instance.new("Frame")
overlayClip.AnchorPoint            = Vector2.new(0.5, 1)
overlayClip.Position               = UDim2.new(0.5, 0, 1, 0)
overlayClip.Size                   = UDim2.new(1, 0, 0, 0)  -- height set at runtime
overlayClip.BackgroundTransparency = 1
overlayClip.ClipsDescendants       = true
overlayClip.ZIndex                 = 2
overlayClip.Parent                 = bagImage

-- Overlay layer: the texture at the next fill stage. Sized in pixels
-- to match the bag's full visual area so the texture doesn't squish as
-- the clip frame's height changes — only the visible window grows.
local overlayImage = Instance.new("ImageLabel")
overlayImage.AnchorPoint            = Vector2.new(0.5, 1)
overlayImage.Position               = UDim2.new(0.5, 0, 1, 0)
overlayImage.Size                   = UDim2.fromScale(1, 1)
overlayImage.BackgroundTransparency = 1
overlayImage.Image                  = EMPTY_BAG_ASSET
overlayImage.ScaleType              = Enum.ScaleType.Fit
overlayImage.Parent                 = overlayClip

local function refitOverlay()
	local w = bagImage.AbsoluteSize.X
	local h = bagImage.AbsoluteSize.Y
	if w <= 0 or h <= 0 then return end
	overlayImage.Size = UDim2.fromOffset(w, h)
end
bagImage:GetPropertyChangedSignal("AbsoluteSize"):Connect(refitOverlay)
task.defer(refitOverlay)

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
sandName.Size                   = UDim2.new(0.78, 0, 0.16, 0)
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

-- Inline close button (top-right of the info column, next to "Sand").
-- Uses the same wood-X art as the quests panel so the close affordance
-- is consistent across every menu.
local closeBtn = Instance.new("ImageButton")
closeBtn.AnchorPoint            = Vector2.new(1, 0)
closeBtn.Position               = UDim2.new(1, 0, 0.03, 0)
closeBtn.Size                   = UDim2.new(0.13, 0, 0.13, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.BorderSizePixel        = 0
closeBtn.AutoButtonColor        = false
closeBtn.Image                  = CLOSE_BTN_ASSET
closeBtn.ScaleType              = Enum.ScaleType.Fit
closeBtn.Parent                 = infoPanel
do
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent      = closeBtn
end
closeBtn.MouseEnter:Connect(function() closeBtn.ImageTransparency = 0.15 end)
closeBtn.MouseLeave:Connect(function() closeBtn.ImageTransparency = 0    end)

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
-- The bag never blends mid-range. At fill X the base layer is the
-- largest stage S with S.pct ≤ X (so 60 % shows the 50 % texture, not
-- a partial 70 %). When the fill crosses a stage threshold upward, an
-- overlay of the new stage's texture rises from the bottom over the
-- previous stage — that's the only animation. Once the overlay
-- completes the base swaps to the new stage and the overlay collapses
-- back to zero, ready for the next threshold cross.
local function stageIndexForPct(pct)
	pct = math.clamp(pct, 0, 100)
	for i = #FILL_STAGES, 1, -1 do
		if pct >= FILL_STAGES[i].pct then return i end
	end
	return 1
end

local function renderStageFlat(idx)
	-- Collapse the overlay FIRST so it can't render with a stale image
	-- during the same tick. Without this, finishing an animation
	-- briefly showed the *next* stage's texture between the image swap
	-- and the clip shrink — visible to the user as a one-frame flash
	-- of e.g. the 30 % bag when settling on the 10 % stage.
	overlayClip.Size   = UDim2.new(1, 0, 0, 0)
	baseImage.Image    = FILL_STAGES[idx].image
	-- Park the overlay on the same texture as the base. The "next stage"
	-- image is assigned inside `animateRevealStage` right before the
	-- reveal tween starts, never preloaded here.
	overlayImage.Image = FILL_STAGES[idx].image
end

local lastStageIdx   = 1   -- texture stage currently rendered
local hasPainted     = false
local stageAnimJob   = 0   -- cancellation token for stage transitions

-- Animate one threshold cross: keep `fromIdx` as the base, slide the
-- `toIdx` texture in from the bottom by growing `overlayClip` from 0 to
-- 1, then settle on `toIdx`. Yields until the tween finishes so the
-- caller can chain multiple crosses sequentially.
local function animateRevealStage(fromIdx, toIdx, jobId)
	if stageAnimJob ~= jobId then return end
	baseImage.Image    = FILL_STAGES[fromIdx].image
	overlayImage.Image = FILL_STAGES[toIdx].image
	overlayClip.Size   = UDim2.new(1, 0, 0, 0)

	local driver = Instance.new("NumberValue")
	driver.Value = 0
	local conn = driver:GetPropertyChangedSignal("Value"):Connect(function()
		if stageAnimJob ~= jobId then return end
		overlayClip.Size = UDim2.new(1, 0, driver.Value, 0)
	end)
	local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tw = TweenService:Create(driver, info, { Value = 1 })

	local done = Instance.new("BindableEvent")
	tw.Completed:Connect(function()
		conn:Disconnect()
		driver:Destroy()
		if stageAnimJob == jobId then
			renderStageFlat(toIdx)
		end
		done:Fire()
	end)
	tw:Play()
	done.Event:Wait()
	done:Destroy()
end

local function paintFill(fill, max)
	fill = tonumber(fill) or 0
	max  = tonumber(max)  or 100
	local pct = math.clamp((fill / max) * 100, 0, 100)

	-- All three numeric widgets snap together to the new value so the
	-- count label, the percent label and the progress bar never drift
	-- out of sync. The texture stage is the only thing that animates.
	countLabel.Text   = string.format("%d / %d",
		math.floor(fill + 0.5), math.floor(max + 0.5))
	percentLabel.Text = string.format("%d%%", math.floor(pct + 0.5))
	barFill.Size      = UDim2.new(pct / 100, 0, 1, 0)

	local newStage = stageIndexForPct(pct)

	if not hasPainted then
		renderStageFlat(newStage)
		lastStageIdx = newStage
		hasPainted   = true
		return
	end

	if newStage == lastStageIdx then
		-- Same stage bracket — texture stays put.
		return
	end

	if newStage < lastStageIdx then
		-- Going down (sand spent / bag emptied somehow): snap.
		stageAnimJob = stageAnimJob + 1
		renderStageFlat(newStage)
		lastStageIdx = newStage
		return
	end

	-- Going up. Collapse any number of skipped stages into a single
	-- reveal — if the player jumped from 10 % straight to 100 %, just
	-- one animation plays (10 % base, 100 % overlay rising from the
	-- bottom), not five sequential ones.
	stageAnimJob = stageAnimJob + 1
	local jobId   = stageAnimJob
	local fromIdx = lastStageIdx
	local toIdx   = newStage
	task.spawn(function()
		if stageAnimJob ~= jobId then return end
		animateRevealStage(fromIdx, toIdx, jobId)
		if stageAnimJob ~= jobId then return end
		lastStageIdx = toIdx
	end)
end
renderStageFlat(1)
percentLabel.Text = "0%"
barFill.Size      = UDim2.new(0, 0, 1, 0)
countLabel.Text   = "0 / 100"

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
