-- TeleportLoadingScreen.client.lua
-- Two-phase loader for queue-countdown teleports leaving the lobby:
--
--   1. Iris-out preview. When the room countdown hits zero, the
--      server fires StartRoomTeleportPrepare. We open a fullscreen
--      ScreenGui that grows a black circle from the centre of the
--      screen until it covers everything, then fades in a title
--      ("Survive 100 Days") so the player has an in-fiction beat
--      while the server is still about to call TeleportAsync.
--   2. SetTeleportGui handoff. A separate "end-state" ScreenGui
--      (already at fully-black + title) is registered with
--      TeleportService:SetTeleportGui so the moment Roblox actually
--      starts the teleport the visual is identical — no flicker
--      between the lobby iris and the engine's teleport screen.
--      The destination place's ReplicatedFirst loader matches the
--      same look, then plays the reverse iris-in once game.Loaded.

local Players          = game:GetService("Players")
local TeleportService  = game:GetService("TeleportService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- This loader applies to teleports leaving the lobby. The
-- destination place runs its own ReplicatedFirst-based loader; the
-- gui registered below stays attached through the destination's
-- own load phase as well.
local OCEAN_PLACE_ID = 77272676169005
if game.PlaceId == OCEAN_PLACE_ID then return end

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TITLE_TEXT = "Survive 100 Days"

-- ── Helpers ────────────────────────────────────────────────────

-- Build the title-card content (black background + centred title
-- text) into `screenGui`. Returns the title TextLabel so callers can
-- fade / tween it.
local function buildTitleCard(screenGui)
	local bg = Instance.new("Frame")
	bg.Name                  = "TitleBackdrop"
	bg.AnchorPoint           = Vector2.new(0.5, 0.5)
	bg.Position              = UDim2.fromScale(0.5, 0.5)
	bg.Size                  = UDim2.fromScale(1, 1)
	bg.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
	bg.BorderSizePixel       = 0
	bg.ZIndex                = 1
	bg.Parent                = screenGui

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
	title.ZIndex              = 2
	title.Parent              = bg
	do
		local sc = Instance.new("UITextSizeConstraint")
		sc.MaxTextSize = 64
		sc.MinTextSize = 28
		sc.Parent      = title
	end
	return title, bg
end

-- ── End-state GUI registered with TeleportService ──────────────
-- Already at the "iris finished, title visible" state. Roblox shows
-- it during the actual teleport so the transition from our lobby
-- iris into Roblox-managed teleport is invisible.
local endStateGui = Instance.new("ScreenGui")
endStateGui.Name           = "TeleportEndState"
endStateGui.ResetOnSpawn   = false
endStateGui.IgnoreGuiInset = true
endStateGui.DisplayOrder   = 100
buildTitleCard(endStateGui)
pcall(function() TeleportService:SetTeleportGui(endStateGui) end)

-- ── Iris-out played on the lobby client BEFORE teleport ──────
-- Server fires StartRoomTeleportPrepare the moment the countdown
-- ends; we react by growing a circular black mask from the centre.
local irisGui  -- single instance; killed on every new firing.
local function playIrisOut()
	if irisGui then irisGui:Destroy() end

	irisGui = Instance.new("ScreenGui")
	irisGui.Name           = "TeleportIrisOut"
	irisGui.ResetOnSpawn   = false
	irisGui.IgnoreGuiInset = true
	irisGui.DisplayOrder   = 99
	irisGui.Parent         = playerGui

	-- Black circle, square frame + UICorner radius 1 = perfect circle.
	-- Sized in scale so on any aspect ratio the final tween still
	-- comfortably covers screen corners.
	local circle = Instance.new("Frame")
	circle.Name                 = "IrisCircle"
	circle.AnchorPoint          = Vector2.new(0.5, 0.5)
	circle.Position             = UDim2.fromScale(0.5, 0.5)
	circle.Size                 = UDim2.fromScale(0, 0)
	circle.BackgroundColor3     = Color3.fromRGB(0, 0, 0)
	circle.BorderSizePixel      = 0
	circle.Parent               = irisGui
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent       = circle
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent      = circle
	end

	-- Grow the circle to ~2.5x the larger screen dimension so the
	-- diagonal is fully covered on every aspect ratio.
	local growTween = TweenService:Create(
		circle,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(2.5, 2.5) }
	)
	growTween:Play()

	-- Once the circle has filled the screen, fade in the title. The
	-- end-state SetTeleportGui will replace this gui as soon as
	-- Roblox starts the teleport, so the title persists visually
	-- straight through.
	task.spawn(function()
		growTween.Completed:Wait()
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
		title.TextTransparency    = 1
		title.Parent              = irisGui
		do
			local sc = Instance.new("UITextSizeConstraint")
			sc.MaxTextSize = 64
			sc.MinTextSize = 28
			sc.Parent      = title
		end
		TweenService:Create(
			title,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextTransparency = 0, TextStrokeTransparency = 0.5 }
		):Play()
	end)
end

local LOG_TAG = "[LobbyTeleportFX]"
local prepareEvent = ReplicatedStorage:WaitForChild("StartRoomTeleportPrepare", 10)
if prepareEvent then
	print(LOG_TAG .. " bound to StartRoomTeleportPrepare RemoteEvent")
	prepareEvent.OnClientEvent:Connect(function(payload)
		print(LOG_TAG .. " prepare event fired; playing iris-out")
		playIrisOut()
	end)
else
	warn(LOG_TAG .. " StartRoomTeleportPrepare never appeared in ReplicatedStorage — iris animation disabled")
end
