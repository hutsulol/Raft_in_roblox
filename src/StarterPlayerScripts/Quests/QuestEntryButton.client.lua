-- QuestEntryButton.client.lua
-- Left-side HUD button that opens the Quest menu. Builds incrementally
-- across A1 → A10 so each commit is testable on its own.
--
-- A1 scope: folder + script + ScreenGui host. Nothing rendered yet.
-- The ScreenGui sits at DisplayOrder 90 — below the phone menu (200)
-- so the phone UI overlaps us when it opens, and below the quest
-- tracker card (Phase H, DisplayOrder 5..something) doesn't matter
-- here. IgnoreGuiInset = false so the button respects Roblox's
-- top-bar inset just like the onboarding tooltip does.
--
-- Public API exposed across A1 → A10 (final shape):
--   _G.SetQuestBadgeCount(n)   -- A7: bumps the red-dot count
--   _G.OpenQuestMenu()         -- A8: stub-warns until Phase B lands
--   J keypress                 -- A10: also fires _G.OpenQuestMenu()

local Players = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SCREENGUI_DISPLAY_ORDER = 90

-- ─── Wood/paper palette (matches the Onboarding tooltip + the
-- design mockup so the entire quest UI reads as one set) ──────────────
local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_WOOD_DARK    = Color3.fromRGB( 91,  58,  34)
local COLOR_WOOD_MID     = Color3.fromRGB(138, 106,  68)
local COLOR_WOOD_BASE    = Color3.fromRGB(176, 138,  92)
local COLOR_PAPER        = Color3.fromRGB(233, 217, 184)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(243, 230, 204)

local BTN_SIZE      = 56
local BTN_RADIUS    = 12
-- Anchored to the LEFT EDGE, vertically centred. Centring along the
-- mid-Y keeps us clear of the Roblox top-bar (chat / menu / Roblox
-- icon at the top-left) and the player stat bars (HP / hunger / XP
-- pinned at the bottom-left in this game's HUD), regardless of
-- viewport height — the button always sits in the empty slab of
-- screen between them. 16-px X margin matches the inventory tooltip
-- gap so the left HUD reads consistently.
local BTN_MARGIN_X  = 16
local BTN_ANCHOR_Y  = 0.5   -- scale; mid-screen vertically

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QuestEntryGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = SCREENGUI_DISPLAY_ORDER
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ─── Button frame (A2) ──────────────────────────────────────────────
-- Wood-base TextButton acts as the click-target + outer chrome. The
-- icon glyph (A3) and badge (A7) parent into this. Position is set in
-- A4; for now we place it at (16, 96) so it's visible during testing
-- without colliding with the Roblox top-bar.
local button = Instance.new("TextButton")
button.Name = "QuestButton"
-- Left-anchor + scale-Y mid so the button always parks in the empty
-- slab between the Roblox top-bar and the player stat HUD regardless
-- of viewport height. AnchorPoint (0, 0.5) means Y position 0.5 puts
-- the button's centre exactly on the screen's midline.
button.AnchorPoint = Vector2.new(0, 0.5)
button.Position = UDim2.new(0, BTN_MARGIN_X, BTN_ANCHOR_Y, 0)
button.Size = UDim2.fromOffset(BTN_SIZE, BTN_SIZE)
button.BackgroundColor3 = COLOR_PAPER
button.BorderSizePixel = 0
button.AutoButtonColor = false
button.Text = ""
button.ZIndex = 1
button.Parent = screenGui

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, BTN_RADIUS)
btnCorner.Parent = button

local btnStroke = Instance.new("UIStroke")
btnStroke.Color = COLOR_WOOD_DARK
btnStroke.Thickness = 2
btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
btnStroke.Parent = button

-- Inner highlight (mockup's ::before trick): 1 px white-18% inset
-- stroke 2 px from the outer border so the button feels raised.
local highlight = Instance.new("Frame")
highlight.Name = "InnerHighlight"
highlight.AnchorPoint = Vector2.new(0.5, 0.5)
highlight.Position = UDim2.fromScale(0.5, 0.5)
highlight.Size = UDim2.new(1, -4, 1, -4)
highlight.BackgroundTransparency = 1
highlight.BorderSizePixel = 0
highlight.ZIndex = 2
highlight.Parent = button
local hCorner = Instance.new("UICorner")
hCorner.CornerRadius = UDim.new(0, BTN_RADIUS - 2)
hCorner.Parent = highlight
local hStroke = Instance.new("UIStroke")
hStroke.Color = Color3.fromRGB(255, 255, 255)
hStroke.Thickness = 1
hStroke.Transparency = 0.82
hStroke.Parent = highlight

-- ─── Quest icon (A3) ────────────────────────────────────────────────
-- Asset supplied by the user. Inset 8 px on every side so the artwork
-- breathes inside the wood frame and the inner highlight stroke stays
-- visible around it.
local QUEST_ICON_ASSET = "rbxassetid://121862782555497"
local ICON_INSET = 8

local icon = Instance.new("ImageLabel")
icon.Name = "QuestIcon"
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.5, 0.5)
icon.Size = UDim2.new(1, -ICON_INSET * 2, 1, -ICON_INSET * 2)
icon.BackgroundTransparency = 1
icon.BorderSizePixel = 0
icon.Image = QUEST_ICON_ASSET
icon.ScaleType = Enum.ScaleType.Fit
icon.ImageColor3 = Color3.new(1, 1, 1)
icon.ZIndex = 3
icon.Parent = button

-- ─── Hover / pressed / state animation (A5 + A6) ─────────────────────
-- UIScale on the button drives the size animation; tweening Size on a
-- TextButton with offset coords would also work but UIScale composes
-- cleaner with the Position offset added in A6.
local TweenService = game:GetService("TweenService")

local btnScale = Instance.new("UIScale")
btnScale.Scale = 1
btnScale.Parent = button

local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function setHover(isHover)
	-- Brighten the paper fill toward paper-light + scale up slightly
	-- so the button reads as a clear interactive element on hover.
	TweenService:Create(button, HOVER_INFO, {
		BackgroundColor3 = isHover and COLOR_PAPER_LIGHT or COLOR_PAPER,
	}):Play()
	TweenService:Create(btnScale, HOVER_INFO, {
		Scale = isHover and 1.03 or 1.0,
	}):Play()
end

button.MouseEnter:Connect(function()
	setHover(true)
end)
button.MouseLeave:Connect(function()
	setHover(false)
end)

-- A6: pressed state. Scale to 0.96 + nudge the button 1 px down so
-- it reads as physically depressed (the same trick the mockup's
-- .btn:active uses with translateY(2px)). MouseButton1Up restores
-- the resting state — including a stale press-leave fallback for
-- the case where the mouse leaves the button while held down.
local restingPosition = button.Position
local pressedPosition = restingPosition + UDim2.fromOffset(0, 1)
local PRESS_INFO = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function setPressed(isPressed)
	TweenService:Create(btnScale, PRESS_INFO, {
		Scale = isPressed and 0.96 or 1.03, -- 1.03 because we're still inside the hover
	}):Play()
	TweenService:Create(button, PRESS_INFO, {
		Position = isPressed and pressedPosition or restingPosition,
	}):Play()
end

button.MouseButton1Down:Connect(function()
	setPressed(true)
end)
button.MouseButton1Up:Connect(function()
	setPressed(false)
end)
-- If the player drags off the button while still holding the mouse
-- down, MouseButton1Up never fires here — MouseLeave does. Reset.
button.MouseLeave:Connect(function()
	setPressed(false)
end)
