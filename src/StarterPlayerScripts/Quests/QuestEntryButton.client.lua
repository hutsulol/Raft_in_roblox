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

-- ─── Wood-darkest is reused for the hover label pill (A10) — every
-- other wood/paper colour the original chrome used was deleted along
-- with the chrome itself when we switched to the bare icon asset.
local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(243, 230, 204)

-- The icon asset already ships its own wood-frame + paper background,
-- so the click-target is a plain ImageButton — no UICorner / UIStroke
-- / paper fill / inner highlight on our side. Larger than the original
-- 56-px chrome'd version so the baked-in frame reads at HUD distance.
local BTN_SIZE      = 78
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

-- ─── Quest entry button (just the icon) ─────────────────────────────
-- The supplied asset is a self-contained icon (wood frame + scroll +
-- emerald are baked in), so we render it as a plain ImageButton with
-- no surrounding chrome. Hover / press feel comes from UIScale + Y
-- offset only — there's no fill colour to brighten anymore.
local QUEST_ICON_ASSET = "rbxassetid://121862782555497"

local button = Instance.new("ImageButton")
button.Name = "QuestButton"
button.AnchorPoint = Vector2.new(0, 0.5)
button.Position = UDim2.new(0, BTN_MARGIN_X, BTN_ANCHOR_Y, 0)
button.Size = UDim2.fromOffset(BTN_SIZE, BTN_SIZE)
button.BackgroundTransparency = 1
button.BorderSizePixel = 0
button.AutoButtonColor = false
button.Image = QUEST_ICON_ASSET
button.ScaleType = Enum.ScaleType.Fit
button.ZIndex = 1
button.Parent = screenGui

-- ─── Hover / pressed state animation (A5 + A6) ──────────────────────
-- UIScale drives the bounce; UIScale composes cleanly with the
-- Position offset added in the press path so the two states don't
-- fight over the same property.
local TweenService = game:GetService("TweenService")

local btnScale = Instance.new("UIScale")
btnScale.Scale = 1
btnScale.Parent = button

local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function setHover(isHover)
	-- Hover scales up slightly so the button reads as interactive.
	-- No more "brighten fill" tween — there's no fill anymore now
	-- that the wood frame moved into the asset itself.
	TweenService:Create(btnScale, HOVER_INFO, {
		Scale = isHover and 1.05 or 1.0,
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

-- ─── Notification badge (A7) ────────────────────────────────────────
-- Red dot in the top-right of the button, with an optional count
-- label inside it for >1 claimable rewards. Driven by the global
-- _G.SetQuestBadgeCount(n) setter so the Phase C server flow can
-- bump it without reaching into this file. n=0 hides the badge.
local BADGE_SIZE  = 18
local BADGE_INSET = 4
local COLOR_BADGE_FILL    = Color3.fromRGB(220,  72,  62)
local COLOR_BADGE_OUTLINE = Color3.fromRGB(140,  36,  30)

local badge = Instance.new("Frame")
badge.Name = "Badge"
badge.AnchorPoint = Vector2.new(1, 0)
badge.Position = UDim2.new(1, BADGE_INSET, 0, -BADGE_INSET)
badge.Size = UDim2.fromOffset(BADGE_SIZE, BADGE_SIZE)
badge.BackgroundColor3 = COLOR_BADGE_FILL
badge.BorderSizePixel = 0
badge.Visible = false
badge.ZIndex = 5
badge.Parent = button
local badgeCorner = Instance.new("UICorner")
badgeCorner.CornerRadius = UDim.new(1, 0)
badgeCorner.Parent = badge
local badgeStroke = Instance.new("UIStroke")
badgeStroke.Color = COLOR_BADGE_OUTLINE
badgeStroke.Thickness = 1.5
badgeStroke.Parent = badge

local badgeLabel = Instance.new("TextLabel")
badgeLabel.Name = "Count"
badgeLabel.Size = UDim2.fromScale(1, 1)
badgeLabel.BackgroundTransparency = 1
badgeLabel.BorderSizePixel = 0
badgeLabel.Font = Enum.Font.GothamBold
badgeLabel.TextSize = 11
badgeLabel.TextColor3 = Color3.fromRGB(255, 245, 230)
badgeLabel.TextXAlignment = Enum.TextXAlignment.Center
badgeLabel.TextYAlignment = Enum.TextYAlignment.Center
badgeLabel.Text = ""
badgeLabel.ZIndex = 6
badgeLabel.Parent = badge

-- Public API: callers update the badge by count. 0 = hide. 1 = empty
-- red dot (no number). 2..9 = digit. 10+ = "9+".
_G.SetQuestBadgeCount = function(n)
	n = tonumber(n) or 0
	if n <= 0 then
		badge.Visible = false
		badgeLabel.Text = ""
		return
	end
	badge.Visible = true
	if n <= 1 then
		badgeLabel.Text = ""
	elseif n < 10 then
		badgeLabel.Text = tostring(n)
	else
		badgeLabel.Text = "9+"
	end
end

-- ─── Click: open the quest menu (A8) ────────────────────────────────
-- Phase B installs _G.OpenQuestMenu; until then we warn-stub so the
-- click is wired up + reviewable in advance and the integration is a
-- one-liner when the menu lands. The keybind in A10 routes through
-- the same opener for parity.
local function openQuestMenu()
	if typeof(_G.OpenQuestMenu) == "function" then
		_G.OpenQuestMenu()
	else
		warn("[QuestEntryButton] _G.OpenQuestMenu is not yet defined — Phase B lands the menu")
	end
end

button.MouseButton1Click:Connect(openQuestMenu)

-- ─── Hide while the phone menu is open (A9) ─────────────────────────
-- The phone covers most of the screen and has its own quest log
-- inside it; leaving the entry button on top of the phone UI would
-- read as a stray duplicate. PhoneMenu.client.lua publishes the
-- ScreenGui at _G.PhoneScreenGui and toggles .Enabled on open/close
-- (same handshake the inventory tooltip uses). Listen for that
-- changed event so we sync within a frame of the phone state.
local RunService = game:GetService("RunService")

local function isOverlayOpen()
	-- Phone menu hides us because it's a full-screen overlay with
	-- its own quest log inside; quest menu hides us because it's
	-- the destination this button leads to (no point in showing
	-- the entry once the menu is open); the building UI hides us
	-- because its category strip lives at the bottom-left and the
	-- entry would overlap it (T9). Each publishes its ScreenGui to
	-- _G so we can listen on the same handshake.
	for _, key in ipairs({ "PhoneScreenGui", "QuestMenuScreenGui", "BuildingScreenGui" }) do
		local gui = _G[key]
		if gui and gui:IsA("ScreenGui") and gui.Enabled then
			return true
		end
	end
	return false
end

local function syncVisibility()
	screenGui.Enabled = not isOverlayOpen()
end

-- Both PhoneScreenGui (PhoneMenu builds it lazily on first open) and
-- QuestMenuScreenGui (QuestMenu builds it lazily too) may not exist
-- yet when this script first runs. Poll briefly until each appears,
-- then bind to its Enabled-changed signal so we react immediately
-- without further polling.
local function bindGuiHandshake(globalKey)
	task.spawn(function()
		local deadline = os.clock() + 30
		while os.clock() < deadline do
			local gui = _G[globalKey]
			if gui and gui:IsA("ScreenGui") then
				gui:GetPropertyChangedSignal("Enabled"):Connect(syncVisibility)
				syncVisibility()
				return
			end
			task.wait(0.5)
		end
	end)
end

bindGuiHandshake("PhoneScreenGui")
bindGuiHandshake("QuestMenuScreenGui")

-- Heartbeat fallback catches the case where _G.PhoneScreenGui /
-- QuestMenuScreenGui swap reference at runtime (re-spawn, hot
-- reload, etc.) or where the polling deadline expires before the
-- gui has been built (game shipped without one of the menus).
RunService.Heartbeat:Connect(syncVisibility)

syncVisibility()

-- ─── Hover tooltip + J hotkey (A10) ─────────────────────────────────
-- Small "Quests (J)" label that pops next to the button on hover so
-- new players know what the icon does + that there's a keyboard
-- shortcut. The J key opens the menu via the same opener used by
-- click — gameProcessed-aware so typing 'j' in chat doesn't trip it.
local UserInputService = game:GetService("UserInputService")

local TOOLTIP_LABEL_TEXT = "Quests (J)"
local TOOLTIP_GAP_X      = 10  -- distance from the button's right edge

local labelGui = Instance.new("Frame")
labelGui.Name = "HoverLabel"
labelGui.AnchorPoint = Vector2.new(0, 0.5)
labelGui.Position = UDim2.new(1, TOOLTIP_GAP_X, 0.5, 0)
labelGui.AutomaticSize = Enum.AutomaticSize.XY
labelGui.BackgroundColor3 = COLOR_WOOD_DARKEST
labelGui.BackgroundTransparency = 0.15
labelGui.BorderSizePixel = 0
labelGui.Visible = false
labelGui.ZIndex = 4
labelGui.Parent = button
local lblCorner = Instance.new("UICorner")
lblCorner.CornerRadius = UDim.new(0, 6)
lblCorner.Parent = labelGui
local lblPad = Instance.new("UIPadding")
lblPad.PaddingTop    = UDim.new(0, 4)
lblPad.PaddingBottom = UDim.new(0, 4)
lblPad.PaddingLeft   = UDim.new(0, 8)
lblPad.PaddingRight  = UDim.new(0, 8)
lblPad.Parent = labelGui

local labelText = Instance.new("TextLabel")
labelText.BackgroundTransparency = 1
labelText.BorderSizePixel = 0
labelText.AutomaticSize = Enum.AutomaticSize.XY
labelText.Font = Enum.Font.GothamBold
labelText.TextSize = 12
labelText.TextColor3 = COLOR_PAPER_LIGHT
labelText.Text = TOOLTIP_LABEL_TEXT
labelText.ZIndex = 5
labelText.Parent = labelGui

button.MouseEnter:Connect(function()
	labelGui.Visible = true
end)
button.MouseLeave:Connect(function()
	labelGui.Visible = false
end)

-- J keybind. Skip when the input was already consumed (chat, text
-- box) and when the entry button is hidden — typically because the
-- phone menu has its own menu open and J shouldn't ALSO open the
-- quest UI on top.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode ~= Enum.KeyCode.J then return end
	if not screenGui.Enabled then return end
	openQuestMenu()
end)
