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

local BTN_SIZE   = 56
local BTN_RADIUS = 12

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
button.AnchorPoint = Vector2.new(0, 0)
button.Position = UDim2.fromOffset(16, 96)
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
