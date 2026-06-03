-- TeleportLoadingScreen.client.lua (destination side)
-- Lives in ReplicatedFirst of the Ocean place so Roblox runs it
-- before any other client script and we can dismiss the default
-- loading screen + draw our own.
--
-- The Ocean place has StreamingEnabled, which means:
--   * game.Loaded fires once the initial replication chunk is in,
--     not "when the entire map is downloaded" — so it tends to
--     fire much faster than on a non-streaming place.
--   * Workspace continues to stream parts in around the player
--     for several more seconds after Loaded. If we tear down the
--     overlay the moment Loaded fires, the player can land on
--     half-streamed geometry (and sometimes through it before the
--     ocean's collision rolls in).
--
-- So the dismiss waits on three things rather than just Loaded:
--   1. game:IsLoaded()
--   2. LocalPlayer.Character + HumanoidRootPart exist
--   3. workspace:RequestStreamAroundAsync(hrp.Position) returned —
--      the StreamingMinRadius around the player is guaranteed in
--      memory before we drop the curtain.
-- The whole post-load handoff runs as fast as those three resolve:
-- no artificial 5 s fake-progress, no hold, only a 0.2 s fade.

local Players          = game:GetService("Players")
local ReplicatedFirst  = game:GetService("ReplicatedFirst")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")

local LOADING_BG_ASSET = "rbxassetid://111898515497348"

-- Hide Roblox's default loading screen as soon as we can.
pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

-- ReplicatedFirst LocalScripts can start before LocalPlayer is
-- populated. Spin briefly until it is.
local player = Players.LocalPlayer
local waited = 0
while not player and waited < 5 do
	task.wait(0.05)
	waited += 0.05
	player = Players.LocalPlayer
end
if not player then
	warn("[DestLoadingScreen] LocalPlayer never resolved — aborting custom loader")
	return
end
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

-- ── Progress bar fake-fill ────────────────────────────────────
-- Run a short linear approach toward 85 % over 2.5 s — enough
-- visual motion to feel alive, short enough that StreamingEnabled
-- builds typically resolve before we'd otherwise overshoot.
local approachTween = TweenService:Create(
	barFill,
	TweenInfo.new(2.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
	{ Size = UDim2.new(0.85, 0, 1, 0) }
)
approachTween:Play()

-- ── Helpers for the StreamingEnabled-aware dismiss ────────────
local function waitForLoaded()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
end

local function waitForCharacter()
	local char = player.Character or player.CharacterAdded:Wait()
	-- HumanoidRootPart is replicated separately; on StreamingEnabled
	-- it can arrive a beat after the Model itself.
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		hrp = char:WaitForChild("HumanoidRootPart", 10)
	end
	return char, hrp
end

local function waitForStreamAround(hrp)
	-- RequestStreamAroundAsync forces the engine to stream the
	-- area around `position` and only returns when the
	-- StreamingMinRadius worth of content is resident. On a
	-- non-StreamingEnabled place this is a no-op that returns
	-- immediately.
	if not hrp then return end
	pcall(function()
		workspace:RequestStreamAroundAsync(hrp.Position)
	end)
end

local function fadeAndDestroy()
	approachTween:Cancel()
	local finishTween = TweenService:Create(
		barFill,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(1, 0, 1, 0) }
	)
	finishTween:Play()
	finishTween.Completed:Wait()

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
	local fadeDuration = 0.2
	local fadeStart = os.clock()
	while os.clock() - fadeStart < fadeDuration do
		local t = (os.clock() - fadeStart) / fadeDuration
		for _, e in fadeChildren do
			pcall(function()
				e.obj[e.prop] = math.min(1, t)
			end)
		end
		RunService.RenderStepped:Wait()
	end
	screenGui:Destroy()
end

task.spawn(function()
	waitForLoaded()
	local _char, hrp = waitForCharacter()
	waitForStreamAround(hrp)
	fadeAndDestroy()
end)
