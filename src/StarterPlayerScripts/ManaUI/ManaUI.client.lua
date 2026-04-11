-- ManaUI.client.lua
-- Mana bar HUD — a compact horizontal bar rendered above the LEFT
-- HALF of the inventory hotbar, showing the player's current mana
-- amount. Driven by the replicated Characteristics.ManaCurrent /
-- ManaMax IntValues written by Characteristics.server.lua.
--
-- Lives in its own ScreenGui so it is fully decoupled from
-- InventoryUI.client.lua — the only coupling left is the hotbar
-- layout constants below, which must stay in sync with InventoryUI's
-- `buildHotbar()` so the two pieces line up on screen.
--
-- The text label's X position is tweened in parallel with the fill
-- size so the number always sits over the center of the currently
-- filled portion of the bar and slides smoothly as mana changes.

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── Hotbar layout mirror ────────────────────────────────────────────────
-- These MUST match InventoryUI.client.lua's buildHotbar() so the mana
-- bar aligns with the left edge of the hotbar.
local HOTBAR_SLOTS         = 8
local SLOT_SIZE            = 60
local SLOT_PAD             = 6
local HOTBAR_BOTTOM_OFFSET = 10
local HOTBAR_WIDTH         = HOTBAR_SLOTS * (SLOT_SIZE + SLOT_PAD) + SLOT_PAD
local HOTBAR_HEIGHT        = SLOT_SIZE + SLOT_PAD * 2

-- ─── Mana bar layout ─────────────────────────────────────────────────────
local MANA_BAR_WIDTH    = HOTBAR_WIDTH / 2  -- half, covers the LEFT side
local MANA_BAR_HEIGHT   = 34
local MANA_BAR_GAP      = 6                 -- vertical gap above hotbar
local MANA_ICON_SIZE    = 26
local MANA_ICON_PAD     = 5                 -- left padding inside the bar
local MANA_TRACK_LEFT   = MANA_ICON_PAD + MANA_ICON_SIZE + 8
local MANA_TRACK_RIGHT  = 8
local MANA_TRACK_HEIGHT = 18
local MANA_TWEEN_TIME   = 0.25

local MANA_ICON_ASSET = "rbxassetid://131647230431306"

local COLOR_BAR_BG   = Color3.fromRGB(139, 109, 63)  -- hotbar wood
local COLOR_OUTLINE  = Color3.fromRGB(0, 0, 0)
local COLOR_TRACK_BG = Color3.fromRGB(28, 48, 80)
local COLOR_FILL     = Color3.fromRGB(80, 160, 255)
local COLOR_TEXT     = Color3.fromRGB(255, 255, 255)

-- ─── Build ScreenGui ─────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ManaUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 6  -- just above HotbarGui (5)
screenGui.Parent = playerGui

local manaBar = Instance.new("Frame")
manaBar.Name = "ManaBar"
manaBar.Size = UDim2.new(0, MANA_BAR_WIDTH, 0, MANA_BAR_HEIGHT)
-- Left edge aligned with the hotbar's left edge, vertically stacked
-- above the hotbar with a small gap.
manaBar.Position = UDim2.new(
	0.5, -HOTBAR_WIDTH / 2,
	1, -HOTBAR_HEIGHT - HOTBAR_BOTTOM_OFFSET - MANA_BAR_HEIGHT - MANA_BAR_GAP
)
manaBar.BackgroundColor3 = COLOR_BAR_BG
manaBar.BackgroundTransparency = 0.15
manaBar.BorderSizePixel = 0
manaBar.Parent = screenGui

local manaBarCorner = Instance.new("UICorner")
manaBarCorner.CornerRadius = UDim.new(0, 6)
manaBarCorner.Parent = manaBar

-- Single black outline (no inner stroke on the track).
local manaBarStroke = Instance.new("UIStroke")
manaBarStroke.Color = COLOR_OUTLINE
manaBarStroke.Thickness = 1.5
manaBarStroke.Parent = manaBar

local manaIcon = Instance.new("ImageLabel")
manaIcon.Name = "ManaIcon"
manaIcon.BackgroundTransparency = 1
manaIcon.Image = MANA_ICON_ASSET
manaIcon.Size = UDim2.fromOffset(MANA_ICON_SIZE, MANA_ICON_SIZE)
manaIcon.AnchorPoint = Vector2.new(0, 0.5)
manaIcon.Position = UDim2.new(0, MANA_ICON_PAD, 0.5, 0)
manaIcon.Parent = manaBar

local manaTrack = Instance.new("Frame")
manaTrack.Name = "ManaTrack"
manaTrack.AnchorPoint = Vector2.new(0, 0.5)
manaTrack.Position = UDim2.new(0, MANA_TRACK_LEFT, 0.5, 0)
manaTrack.Size = UDim2.new(1, -(MANA_TRACK_LEFT + MANA_TRACK_RIGHT), 0, MANA_TRACK_HEIGHT)
manaTrack.BackgroundColor3 = COLOR_TRACK_BG
manaTrack.BorderSizePixel = 0
-- Deliberately NOT clipping descendants so the mana text stays
-- readable when the fill is small enough that the centered label
-- would otherwise extend past the track's left edge.
manaTrack.ClipsDescendants = false
manaTrack.Parent = manaBar

local manaTrackCorner = Instance.new("UICorner")
manaTrackCorner.CornerRadius = UDim.new(0, 4)
manaTrackCorner.Parent = manaTrack

local manaFill = Instance.new("Frame")
manaFill.Name = "ManaFill"
manaFill.BackgroundColor3 = COLOR_FILL
manaFill.BorderSizePixel = 0
manaFill.Size = UDim2.fromScale(1, 1)
manaFill.ZIndex = 1
manaFill.Parent = manaTrack

local manaFillCorner = Instance.new("UICorner")
manaFillCorner.CornerRadius = UDim.new(0, 4)
manaFillCorner.Parent = manaFill

-- Text label sits on the track (not on the fill) and its X anchor
-- moves to sit over the middle of the filled portion.
local manaText = Instance.new("TextLabel")
manaText.Name = "ManaText"
manaText.BackgroundTransparency = 1
manaText.Font = Enum.Font.GothamBold
manaText.TextSize = 13
manaText.TextColor3 = COLOR_TEXT
manaText.TextStrokeTransparency = 0.25
manaText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
manaText.AnchorPoint = Vector2.new(0.5, 0.5)
manaText.Position = UDim2.fromScale(0.5, 0.5)
manaText.Size = UDim2.fromOffset(60, 16)
manaText.Text = "0"
manaText.ZIndex = 2
manaText.Parent = manaTrack

-- ─── Update logic ────────────────────────────────────────────────────────
local function updateManaDisplay(current, max, animate)
	local ratio = 0
	if max > 0 then
		ratio = math.clamp(current / max, 0, 1)
	end
	local fillGoal = UDim2.fromScale(ratio, 1)
	local textGoal = UDim2.fromScale(ratio / 2, 0.5)

	manaText.Text = tostring(current)

	if animate then
		local info = TweenInfo.new(
			MANA_TWEEN_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		)
		TweenService:Create(manaFill, info, { Size = fillGoal }):Play()
		TweenService:Create(manaText, info, { Position = textGoal }):Play()
	else
		manaFill.Size = fillGoal
		manaText.Position = textGoal
	end
end

-- Subscribe to the replicated Characteristics mana values. First call
-- paints the bar instantly (no tween); subsequent changes animate.
task.spawn(function()
	local folder  = player:WaitForChild("Characteristics")
	local current = folder:WaitForChild("ManaCurrent")
	local max     = folder:WaitForChild("ManaMax")

	updateManaDisplay(current.Value, max.Value, false)

	local function refresh()
		updateManaDisplay(current.Value, max.Value, true)
	end
	current:GetPropertyChangedSignal("Value"):Connect(refresh)
	max:GetPropertyChangedSignal("Value"):Connect(refresh)
end)
