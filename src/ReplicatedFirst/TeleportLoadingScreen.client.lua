-- TeleportLoadingScreen.client.lua (destination side)
-- Matches the lobby's iris-out title-card so the player sees a
-- continuous "black screen + Survive 100 Days" from the moment the
-- lobby countdown ends until the destination place is fully loaded.
-- On game.Loaded we play the reverse iris-IN (black collapses from
-- the screen edges back to a centre point) and then destroy the
-- GUI so the world drops into view.

local Players          = game:GetService("Players")
local ReplicatedFirst  = game:GetService("ReplicatedFirst")
local TweenService     = game:GetService("TweenService")

local TITLE_TEXT = "Survive 100 Days"

local LOG_TAG = "[DestLoadingScreen]"
print(LOG_TAG .. " booted in ReplicatedFirst")

-- Hide Roblox's default loading screen as soon as we can.
pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

-- ReplicatedFirst LocalScripts can start before Players.LocalPlayer
-- is populated. Spin briefly until it is — without this guard the
-- next line errors and the whole script silently aborts.
local player = Players.LocalPlayer
local waited = 0
while not player and waited < 5 do
	task.wait(0.05)
	waited = waited + 0.05
	player = Players.LocalPlayer
end
if not player then
	warn(LOG_TAG .. " LocalPlayer never resolved — aborting custom loader")
	return
end
local playerGui = player:WaitForChild("PlayerGui")
print(LOG_TAG .. " building screen")

-- ── Build the title card ──────────────────────────────────────
-- Fully black backdrop + centred "Survive 100 Days" — identical
-- look to the iris's end state on the lobby side, so the visual
-- carries over without a flicker.
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "DestinationLoadingScreen"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder   = 1000
screenGui.Parent         = playerGui

local backdrop = Instance.new("Frame")
backdrop.Name             = "Backdrop"
backdrop.Size             = UDim2.fromScale(1, 1)
backdrop.Position         = UDim2.fromScale(0, 0)
backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
backdrop.BorderSizePixel  = 0
backdrop.ZIndex           = 1
backdrop.Parent           = screenGui

local title = Instance.new("TextLabel")
title.Name                = "Title"
title.AnchorPoint         = Vector2.new(0.5, 0.5)
title.Position            = UDim2.fromScale(0.5, 0.5)
title.Size                = UDim2.new(0.8, 0, 0.12, 0)
title.BackgroundTransparency = 1
title.Text                = TITLE_TEXT
title.TextColor3          = Color3.new(1, 1, 1)
title.TextStrokeColor3    = Color3.new(0, 0, 0)
title.TextStrokeTransparency = 0.5
title.Font                = Enum.Font.GothamBold
title.TextScaled          = true
title.ZIndex              = 3
title.Parent              = screenGui
do
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 64
	sc.MinTextSize = 28
	sc.Parent      = title
end

-- ── Iris-in dismiss on game.Loaded ────────────────────────────
task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	-- Fade the title out first so it doesn't get squeezed by the
	-- collapsing iris.
	TweenService:Create(
		title,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
	task.wait(0.18)

	-- Replace the solid black backdrop with a black circle the size
	-- of the screen's diagonal, then collapse it to a point. The
	-- "iris" effect: viewport opens from the centre outwards as the
	-- black shrinks.
	backdrop:Destroy()

	local circle = Instance.new("Frame")
	circle.Name                 = "IrisCircle"
	circle.AnchorPoint          = Vector2.new(0.5, 0.5)
	circle.Position             = UDim2.fromScale(0.5, 0.5)
	circle.Size                 = UDim2.fromScale(2.5, 2.5)
	circle.BackgroundColor3     = Color3.fromRGB(0, 0, 0)
	circle.BorderSizePixel      = 0
	circle.ZIndex               = 2
	circle.Parent               = screenGui
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent       = circle
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent      = circle
	end

	local collapse = TweenService:Create(
		circle,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = UDim2.fromScale(0, 0) }
	)
	collapse:Play()
	collapse.Completed:Wait()
	screenGui:Destroy()
end)
