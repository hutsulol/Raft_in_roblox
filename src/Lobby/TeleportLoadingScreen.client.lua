-- TeleportLoadingScreen.client.lua (lobby side)
-- Plays the iris-out transition that introduces a queue-countdown
-- teleport. Once the round timer hits zero the server fires
-- StartRoomTeleportPrepare and the client:
--
--   1. Grows a black circle from the centre of the screen until it
--      covers everything (Sine easing for a smooth, even motion).
--   2. Fades in a "Survive 100 Days" title behind/in the centre of
--      the black mask.
--   3. After a brief hold, Roblox actually starts TeleportAsync on
--      the server. We deliberately DO NOT call SetTeleportGui so
--      Roblox's own "Joining game" / place-card screen takes over
--      from here on — the player sees the standard transfer screen
--      between the lobby and the destination instead of a static
--      black overlay holding them hostage during the load.

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService  = game:GetService("TeleportService")

-- The script only runs while the player is in the lobby place; on
-- the destination the iris simply doesn't exist (Roblox's stock
-- loader is shown instead).
local OCEAN_PLACE_ID = 77272676169005
if game.PlaceId == OCEAN_PLACE_ID then return end

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TITLE_TEXT     = "Survive 100 Days"
local GROW_DURATION  = 0.3
local TITLE_FADE_IN  = 0.2
local LOG_TAG        = "[LobbyTeleportFX]"

-- ── Iris-out played on the lobby client BEFORE teleport ───────

local irisGui    -- single instance once it's been built.
local irisActive = false

local function buildTransferGui()
	-- The "end state" of the iris baked as a static ScreenGui:
	-- full-screen black backdrop + centred "Survive 100 Days".
	-- Handed to TeleportService:SetTeleportGui so Roblox shows
	-- THIS during the cross-place transfer instead of its stock
	-- "Joining server" chrome — the player sees one continuous
	-- iris→fullscreen-black transition instead of a hard cut to
	-- Roblox UI mid-handshake.
	local gui = Instance.new("ScreenGui")
	gui.Name           = "TeleportTransferScreen"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder   = 100

	local backdrop = Instance.new("Frame")
	backdrop.Name             = "Backdrop"
	backdrop.Size             = UDim2.fromScale(1, 1)
	backdrop.Position         = UDim2.fromScale(0, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BorderSizePixel  = 0
	backdrop.Parent           = gui

	local title = Instance.new("TextLabel")
	title.Name                = "Title"
	title.AnchorPoint         = Vector2.new(0.5, 0.5)
	title.Position            = UDim2.fromScale(0.5, 0.5)
	title.Size                = UDim2.new(0.8, 0, 0.12, 0)
	title.BackgroundTransparency = 1
	title.Text                = TITLE_TEXT
	title.TextColor3          = Color3.new(1, 1, 1)
	title.TextStrokeColor3    = Color3.new(0, 0, 0)
	title.TextStrokeTransparency = 0.4
	title.Font                = Enum.Font.GothamBold
	title.TextScaled          = true
	title.Parent              = gui
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 64
	sc.MinTextSize = 28
	sc.Parent      = title

	return gui
end

local function playIrisOut()
	-- If the iris is already on screen (or mid-grow), ignore extra
	-- triggers. The server can occasionally double-fire the prepare
	-- event during the lock→teleport hand-off, and destroying the
	-- live GUI to restart from a tiny circle looks exactly like a
	-- frame-stutter to the player.
	if irisActive then return end
	irisActive = true
	if irisGui then irisGui:Destroy() end

	-- Play ReplicatedStorage.Sounds.fear_sound at the same moment
	-- the iris starts growing so the audio cue rises in lockstep
	-- with the black circle covering the screen. Cloned so the
	-- template stays untouched; SoundService parent makes it a
	-- 2D / non-positional play that survives until natural
	-- completion (the iris itself only lives ~0.3 s; the teleport
	-- takes the player out before this Destroy ever needs to fire).
	pcall(function()
		local SoundService = game:GetService("SoundService")
		local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
		local template = soundsFolder and soundsFolder:FindFirstChild("fear_sound")
		if template and template:IsA("Sound") then
			local sound = template:Clone()
			sound.Parent = SoundService
			sound:Play()
			sound.Stopped:Once(function() sound:Destroy() end)
		else
			warn(LOG_TAG .. " ReplicatedStorage.Sounds.fear_sound missing — skipping audio")
		end
	end)


	irisGui = Instance.new("ScreenGui")
	irisGui.Name           = "TeleportIrisOut"
	irisGui.ResetOnSpawn   = false
	irisGui.IgnoreGuiInset = true
	irisGui.DisplayOrder   = 99
	irisGui.Parent         = playerGui

	-- Pre-stage the title invisibly so it's already in the layout
	-- when the iris hits the screen edges — avoids the awkward
	-- one-frame "text pops in after the mask snaps".
	local title = Instance.new("TextLabel")
	title.Name                = "Title"
	title.AnchorPoint         = Vector2.new(0.5, 0.5)
	title.Position            = UDim2.fromScale(0.5, 0.5)
	title.Size                = UDim2.new(0.8, 0, 0.12, 0)
	title.BackgroundTransparency = 1
	title.Text                = TITLE_TEXT
	title.TextColor3          = Color3.new(1, 1, 1)
	title.TextStrokeColor3    = Color3.new(0, 0, 0)
	title.TextStrokeTransparency = 1
	title.TextTransparency    = 1
	title.Font                = Enum.Font.GothamBold
	title.TextScaled          = true
	title.ZIndex              = 2
	title.Parent              = irisGui
	do
		local sc = Instance.new("UITextSizeConstraint")
		sc.MaxTextSize = 64
		sc.MinTextSize = 28
		sc.Parent      = title
	end

	-- Black circle: square Frame + UICorner(1,0) + AspectRatio 1.
	-- Start at a small positive Size so the AspectRatioConstraint
	-- has a non-degenerate base to lock onto; otherwise the first
	-- frame can render as a tiny rectangle before the constraint
	-- kicks in.
	local circle = Instance.new("Frame")
	circle.Name                 = "IrisCircle"
	circle.AnchorPoint          = Vector2.new(0.5, 0.5)
	circle.Position             = UDim2.fromScale(0.5, 0.5)
	circle.Size                 = UDim2.fromScale(0.02, 0.02)
	circle.BackgroundColor3     = Color3.fromRGB(0, 0, 0)
	circle.BorderSizePixel      = 0
	circle.ZIndex               = 1
	circle.Parent               = irisGui
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent       = circle
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio  = 1
		ar.DominantAxis = Enum.DominantAxis.Width
		ar.Parent       = circle
	end

	-- Grow to roughly 3x the screen so the diagonal is comfortably
	-- covered on every aspect ratio (16:9 needs ~1.15x of width,
	-- 21:9 ultrawide needs ~1.3x, 3x is safe everywhere).
	local growTween = TweenService:Create(
		circle,
		TweenInfo.new(GROW_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(3, 3) }
	)
	growTween:Play()

	-- Fade in the title once the mask reaches the screen edges. We
	-- start the title tween slightly BEFORE growTween completes so
	-- the text and the full-cover state arrive together.
	task.spawn(function()
		task.wait(GROW_DURATION * 0.65)
		TweenService:Create(
			title,
			TweenInfo.new(TITLE_FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextTransparency = 0, TextStrokeTransparency = 0.4 }
		):Play()
	end)
end

-- ── Register the transfer-state GUI immediately on boot ──────
-- TeleportService:SetTeleportGui takes a SNAPSHOT of the GUI at
-- call time and replays it during the cross-place transfer.
-- Registering it here at script load (not lazily on the prepare
-- event) means the snapshot is already in Roblox's hands the
-- moment the server fires TeleportAsync — no race window where
-- the player could see Roblox's stock "Joining server" chrome
-- because our SetTeleportGui hadn't landed yet.
pcall(function()
	local transferGui = buildTransferGui()
	TeleportService:SetTeleportGui(transferGui)
	transferGui:Destroy()  -- snapshot taken; the live tree can go
end)

-- ── Wait for the server-side RemoteEvent + bind ───────────────
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
