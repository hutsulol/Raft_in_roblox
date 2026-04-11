-- HoloOpenAnimation.lua
-- ModuleScript — Solo-Leveling / sci-fi HUD style opening animation.
--
-- Plays a holographic glitch-in animation on an existing Frame that
-- already contains these two children:
--
--   LoadBar  : Frame      — the progress-bar fill (its Size is tweened)
--   LoadText : TextLabel  — the "LOAD..." / "SYSTEM READY" caption
--
-- The animation is split into distinct phases:
--
--   1. Glitch        — random jitter + transparency flicker (~0.18s)
--   2. RGB shift     — fake color-channel misalignment
--   3. Appear        — UIScale 0.7→1 and transparency 1→0
--   4. Loading       — bar fills, text swaps to "SYSTEM READY"
--   5. Final flicker — short flash + subtle idle pulse
--
-- The loading sequence runs in parallel with phases 1–3 so the bar is
-- visibly filling *while* the UI glitches in, reaching 100% right as the
-- clean appearance tween settles.
--
-- Usage:
--   local HoloOpen = require(script.Parent.HoloOpenAnimation)
--   local stopPulse = HoloOpen.PlayOpenAnimation(myFrame)
--   -- later, when the menu closes:
--   stopPulse()

local TweenService = game:GetService("TweenService")

local HoloOpenAnimation = {}

-- ─── Tunables ──────────────────────────────────────────────────────────────

local GLITCH_DURATION   = 0.18
local GLITCH_STEP       = 0.025
local GLITCH_OFFSET_MAX = 6

local RGB_SHIFT_STEPS = 6
local RGB_SHIFT_STEP  = 0.025

local APPEAR_DURATION   = 0.35
local APPEAR_FROM_SCALE = 0.7

local LOAD_DURATION = 0.75

local FINAL_FLICKER_COUNT = 3
local FINAL_FLICKER_STEP  = 0.04

local PULSE_PERIOD    = 2.4
local PULSE_AMPLITUDE = 0.012

local SCAN_DURATION = 0.9

-- Red / blue channel tint used for the brief RGB-misalignment phase.
local RED_CH = Color3.fromRGB(255, 64, 96)
local BLU_CH = Color3.fromRGB(64, 160, 255)

-- ─── Small helpers ─────────────────────────────────────────────────────────

local function jitter(range)
	return (math.random() * 2 - 1) * range
end

local function playTween(instance, info, goal)
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end

local function waitTween(t)
	if t.PlaybackState ~= Enum.PlaybackState.Completed then
		t.Completed:Wait()
	end
end

-- A UIScale is a layout modifier, not a rendered UI element — we only
-- add one if the caller didn't already, so we still "only animate
-- existing UI". It gives us a non-destructive scale handle.
local function ensureUIScale(frame)
	local scale = frame:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "HoloUIScale"
		scale.Parent = frame
	end
	return scale
end

-- ─── Phase 1: glitch jitter ────────────────────────────────────────────────

local function runGlitchPhase(frame, loadBar, loadText, origPos)
	local elapsed = 0
	while elapsed < GLITCH_DURATION do
		frame.Position = origPos + UDim2.fromOffset(
			math.floor(jitter(GLITCH_OFFSET_MAX)),
			math.floor(jitter(GLITCH_OFFSET_MAX))
		)
		-- Each child gets its own random roll so the glitch feels
		-- desynced, like a broken hologram feed.
		frame.BackgroundTransparency   = 0.25 + math.random() * 0.55
		loadBar.BackgroundTransparency = 0.25 + math.random() * 0.55
		loadText.TextTransparency      = 0.25 + math.random() * 0.55
		task.wait(GLITCH_STEP)
		elapsed += GLITCH_STEP
	end
	frame.Position = origPos
end

-- ─── Phase 2: RGB channel shift ────────────────────────────────────────────

local function runRgbShiftPhase(frame, loadText)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	local origStroke = stroke and stroke.Color or nil
	local origText   = loadText.TextColor3

	for i = 1, RGB_SHIFT_STEPS do
		local odd = (i % 2) == 1
		if stroke then
			stroke.Color = odd and RED_CH or BLU_CH
		end
		loadText.TextColor3 = odd and BLU_CH or RED_CH
		-- Slight jitter so the channels desync in time as well.
		task.wait(RGB_SHIFT_STEP + math.random() * 0.015)
	end

	if stroke then stroke.Color = origStroke end
	loadText.TextColor3 = origText
end

-- ─── Phase 3: clean appear (scale + fade) ──────────────────────────────────

local function runAppearPhase(frame, loadBar, loadText, uiScale, origFrameTransp, origBarTransp, origTextTransp)
	local info = TweenInfo.new(
		APPEAR_DURATION,
		Enum.EasingStyle.Quint,
		Enum.EasingDirection.Out
	)
	playTween(uiScale, info, { Scale = 1 })
	playTween(frame,   info, { BackgroundTransparency = origFrameTransp })
	playTween(loadBar, info, { BackgroundTransparency = origBarTransp })
	local last = playTween(loadText, info, { TextTransparency = origTextTransp })
	waitTween(last)
end

-- ─── Phase 4: loading sequence ─────────────────────────────────────────────

local function runLoadingSequence(loadBar, loadText, origBarSize)
	loadText.Text = "LOAD..."
	loadBar.Size = UDim2.new(
		0, 0,
		origBarSize.Y.Scale, origBarSize.Y.Offset
	)

	local info = TweenInfo.new(LOAD_DURATION, Enum.EasingStyle.Linear)
	local t = playTween(loadBar, info, { Size = origBarSize })
	waitTween(t)

	loadText.Text = "SYSTEM READY"
end

-- ─── Phase 5: final flicker ────────────────────────────────────────────────

local function runFinalFlicker(frame, loadText, origFrameTransp, origTextTransp)
	for _ = 1, FINAL_FLICKER_COUNT do
		frame.BackgroundTransparency = math.min(origFrameTransp + 0.45, 1)
		loadText.TextTransparency    = math.min(origTextTransp + 0.45, 1)
		task.wait(FINAL_FLICKER_STEP)
		frame.BackgroundTransparency = origFrameTransp
		loadText.TextTransparency    = origTextTransp
		task.wait(FINAL_FLICKER_STEP)
	end
end

-- ─── Bonus: scan line + idle pulse ─────────────────────────────────────────

-- If the caller already placed a "ScanLine" Frame inside the main frame,
-- sweep it top→bottom during the opening animation. Otherwise silently
-- skip — we never create the scan line ourselves.
local function runScanLine(frame)
	local line = frame:FindFirstChild("ScanLine")
	if not line or not line:IsA("GuiObject") then return end

	line.Visible = true
	line.Position = UDim2.new(0, 0, 0, 0)
	local info = TweenInfo.new(SCAN_DURATION, Enum.EasingStyle.Linear)
	local t = playTween(line, info, { Position = UDim2.new(0, 0, 1, 0) })
	task.spawn(function()
		waitTween(t)
		line.Visible = false
	end)
end

-- Subtle "idle" pulse on the UIScale — runs on its own coroutine until
-- the returned stop function is invoked.
local function startPulse(uiScale)
	local alive = true
	task.spawn(function()
		local t0 = os.clock()
		while alive do
			local phase = (os.clock() - t0) / PULSE_PERIOD
			uiScale.Scale = 1 + math.sin(phase * math.pi * 2) * PULSE_AMPLITUDE
			task.wait(1 / 30)
		end
		uiScale.Scale = 1
	end)
	return function() alive = false end
end

-- ─── Public API ────────────────────────────────────────────────────────────

function HoloOpenAnimation.PlayOpenAnimation(frame)
	assert(typeof(frame) == "Instance" and frame:IsA("GuiObject"),
		"PlayOpenAnimation expects a GuiObject frame")

	local loadBar  = frame:FindFirstChild("LoadBar")
	local loadText = frame:FindFirstChild("LoadText")
	assert(loadBar  and loadBar:IsA("GuiObject"),  "frame.LoadBar Frame is required")
	assert(loadText and loadText:IsA("TextLabel"), "frame.LoadText TextLabel is required")

	-- Snapshot resting values so we can tween back to them cleanly.
	local origPos         = frame.Position
	local origFrameTransp = frame.BackgroundTransparency
	local origBarTransp   = loadBar.BackgroundTransparency
	local origTextTransp  = loadText.TextTransparency
	local origBarSize     = loadBar.Size

	local uiScale = ensureUIScale(frame)

	-- Initial hidden / scaled-down state.
	uiScale.Scale = APPEAR_FROM_SCALE
	frame.BackgroundTransparency   = 1
	loadBar.BackgroundTransparency = 1
	loadText.TextTransparency      = 1
	frame.Visible = true

	-- Kick off the loading fill + optional scan line in parallel so the
	-- bar is visibly filling *while* the glitch and appear phases run.
	runScanLine(frame)
	local loadingDone = false
	task.spawn(function()
		runLoadingSequence(loadBar, loadText, origBarSize)
		loadingDone = true
	end)

	-- Phases 1 → 2 → 3, sequenced on the main thread.
	runGlitchPhase(frame, loadBar, loadText, origPos)
	runRgbShiftPhase(frame, loadText)
	runAppearPhase(frame, loadBar, loadText, uiScale,
		origFrameTransp, origBarTransp, origTextTransp)

	-- Let the loading bar finish before we celebrate.
	while not loadingDone do
		task.wait()
	end

	-- Final flicker + settle to pristine values.
	runFinalFlicker(frame, loadText, origFrameTransp, origTextTransp)

	frame.Position                 = origPos
	frame.BackgroundTransparency   = origFrameTransp
	loadBar.BackgroundTransparency = origBarTransp
	loadText.TextTransparency      = origTextTransp
	loadBar.Size                   = origBarSize
	uiScale.Scale                  = 1

	-- Return a stop handle for the idle pulse so callers can end it
	-- when they close the menu.
	return startPulse(uiScale)
end

return HoloOpenAnimation
