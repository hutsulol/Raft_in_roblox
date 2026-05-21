-- TeleportLoadingScreen.client.lua (destination side)
-- Mirrors src/Lobby/TeleportLoadingScreen.client.lua but lives in
-- ReplicatedFirst of the Ocean place. Roblox runs ReplicatedFirst's
-- LocalScripts BEFORE any other client script and gives them a
-- chance to dismiss the default loading screen + draw their own.
--
-- Effect from the player's POV when arriving from a queue teleport:
--   1. Lobby SetTeleportGui paints the pirate-raft background
--      during the outbound handshake.
--   2. The moment the place file starts loading, this script kicks
--      in — RemoveDefaultLoadingScreen kills the stock Roblox
--      logo/spinner, our ScreenGui takes over with the same art +
--      "Loading" label + progress bar.
--   3. game:IsLoaded() resolves → we tween the bar to 100 %, hold
--      briefly, then destroy the GUI so the player drops into the
--      world.

local Players          = game:GetService("Players")
local ReplicatedFirst  = game:GetService("ReplicatedFirst")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")

local LOADING_BG_ASSET = "rbxassetid://111898515497348"

-- Hide Roblox's default loading screen as soon as we can.
pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── Build the ScreenGui ────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "DestinationLoadingScreen"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder   = 1000
screenGui.Parent         = playerGui

local bg = Instance.new("ImageLabel")
bg.Name                  = "Background"
bg.Size                  = UDim2.fromScale(1, 1)
bg.Position              = UDim2.fromScale(0, 0)
bg.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
bg.BackgroundTransparency = 0
bg.Image                 = LOADING_BG_ASSET
bg.ScaleType             = Enum.ScaleType.Crop
bg.Parent                = screenGui

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

-- ── Fake progress while the place loads ────────────────────────
-- Tween toward 95 % over ~5 s so the bar reads "almost done"
-- without overshooting "done" before IsLoaded resolves.
local approachTween = TweenService:Create(
	barFill,
	TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
	{ Size = UDim2.new(0.95, 0, 1, 0) }
)
approachTween:Play()

-- Once Roblox tells us the place is loaded, finish the bar and
-- dismiss the screen.
task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	-- Snap the bar to 100 % so the player sees the fill complete.
	approachTween:Cancel()
	local finishTween = TweenService:Create(
		barFill,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(1, 0, 1, 0) }
	)
	finishTween:Play()
	finishTween.Completed:Wait()
	-- Brief beat so the "complete" frame is visible, then fade out.
	task.wait(0.2)
	local fadeOut = TweenService:Create(
		screenGui,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{}
	)
	-- ScreenGui doesn't tween cleanly, so just fade each child by
	-- bumping their Transparency / TextTransparency manually.
	local fadeChildren = {}
	for _, desc in screenGui:GetDescendants() do
		if desc:IsA("ImageLabel") or desc:IsA("Frame") then
			table.insert(fadeChildren, { obj = desc, prop = "BackgroundTransparency" })
			if desc:IsA("ImageLabel") then
				table.insert(fadeChildren, { obj = desc, prop = "ImageTransparency" })
			end
		elseif desc:IsA("TextLabel") then
			table.insert(fadeChildren, { obj = desc, prop = "TextTransparency" })
			table.insert(fadeChildren, { obj = desc, prop = "TextStrokeTransparency" })
		end
	end
	local fadeStart = os.clock()
	while os.clock() - fadeStart < 0.4 do
		local t = (os.clock() - fadeStart) / 0.4
		for _, e in fadeChildren do
			pcall(function()
				e.obj[e.prop] = math.min(1, t)
			end)
		end
		RunService.RenderStepped:Wait()
	end
	screenGui:Destroy()
end)
