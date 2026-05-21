-- TeleportLoadingScreen.client.lua
-- Replaces Roblox's default teleport loading wheel with a branded
-- screen the player sees the moment a queue countdown teleport
-- fires: the pirate-raft background art + "Loading" label + a
-- progress bar that fills as the destination place loads.
--
-- TeleportService:SetTeleportGui takes a ScreenGui and shows it for
-- the entire teleport flow (leaving the lobby + landing on the
-- destination's loading phase), so the queue-countdown teleport
-- never reverts to the stock Roblox loader.

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local TweenService    = game:GetService("TweenService")

-- This loader applies to teleports leaving the lobby. The
-- destination place runs its own client startup; the gui registered
-- below stays attached through the destination's load phase, so we
-- don't need to set it up again there.
local OCEAN_PLACE_ID = 77272676169005
if game.PlaceId == OCEAN_PLACE_ID then return end

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local LOADING_BG_ASSET = "rbxassetid://111898515497348"

-- ── Build the GUI hierarchy ─────────────────────────────────────
-- The ScreenGui is NOT parented to PlayerGui — SetTeleportGui hands
-- it to TeleportService, which manages its lifetime.
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "TeleportLoadingScreen"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder   = 100

local bg = Instance.new("ImageLabel")
bg.Name                  = "Background"
bg.Size                  = UDim2.fromScale(1, 1)
bg.Position              = UDim2.fromScale(0, 0)
bg.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
bg.BackgroundTransparency = 0
bg.Image                 = LOADING_BG_ASSET
bg.ScaleType             = Enum.ScaleType.Crop
bg.Parent                = screenGui

-- "Loading" text near the bottom, just above the progress bar.
local loadingLabel = Instance.new("TextLabel")
loadingLabel.Name                = "LoadingLabel"
loadingLabel.AnchorPoint         = Vector2.new(0.5, 0.5)
loadingLabel.Position            = UDim2.new(0.5, 0, 0.85, 0)
loadingLabel.Size                = UDim2.new(0.5, 0, 0.08, 0)
loadingLabel.BackgroundTransparency = 1
loadingLabel.Text                = "Loading"
loadingLabel.TextColor3          = Color3.new(1, 1, 1)
loadingLabel.TextStrokeColor3    = Color3.new(0, 0, 0)
loadingLabel.TextStrokeTransparency = 0.4
loadingLabel.Font                = Enum.Font.GothamBold
loadingLabel.TextScaled          = true
loadingLabel.Parent              = screenGui
do
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 56
	sc.MinTextSize = 24
	sc.Parent      = loadingLabel
end

-- Progress bar background — pill-shaped, sits centred horizontally
-- below the Loading label.
local barBg = Instance.new("Frame")
barBg.Name             = "BarBg"
barBg.AnchorPoint      = Vector2.new(0.5, 0.5)
barBg.Position         = UDim2.new(0.5, 0, 0.93, 0)
barBg.Size             = UDim2.new(0.5, 0, 0.04, 0)
barBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
barBg.BorderSizePixel  = 0
barBg.Parent           = screenGui
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent       = barBg
	local sc = Instance.new("UISizeConstraint")
	sc.MinSize = Vector2.new(400, 20)
	sc.MaxSize = Vector2.new(900, 40)
	sc.Parent  = barBg
end

-- Fill — animated below.
local barFill = Instance.new("Frame")
barFill.Name             = "BarFill"
barFill.AnchorPoint      = Vector2.new(0, 0.5)
barFill.Position         = UDim2.new(0, 0, 0.5, 0)
barFill.Size             = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(127, 200, 50)
barFill.BorderSizePixel  = 0
barFill.Parent           = barBg
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent       = barFill
end

-- ── Fake progress tween ────────────────────────────────────────
-- Roblox doesn't expose a real percentage during the teleport →
-- destination-load handshake, so we tween linearly toward 95 % over
-- ~5 seconds and let it idle there until the destination place
-- finishes loading and the gui is dismissed by the engine. Looks
-- much better than a snapping 0→100 jump and never overshoots
-- "done" before the player is actually in-game.
local tween = TweenService:Create(
	barFill,
	TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
	{ Size = UDim2.new(0.95, 0, 1, 0) }
)
tween:Play()

-- ── Hand the GUI to TeleportService ────────────────────────────
local ok, err = pcall(function()
	TeleportService:SetTeleportGui(screenGui)
end)
if not ok then
	warn("[TeleportLoadingScreen] SetTeleportGui failed: " .. tostring(err))
end
