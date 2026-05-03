-- UIManager.client.lua
-- Consolidated bottom-left status HUD: mana (top), hunger+water
-- (middle) and health (bottom). This file absorbs what used to live in
-- HealthUI.client.lua, HungerUI.client.lua and ManaUI/ManaUI.client.lua.
--
-- Why one file?
--   * shared palette / layout constants stay in one place,
--   * one ScreenGui means one UIScale driving all three bars, so they
--     shrink in lockstep with the rest of the inventory UI instead of
--     drifting when the viewport changes.
--
-- The HUD uses its own responsive scaling (HUD_REF_WIDTH = 1400) which
-- is a touch more aggressive than the inventory's (1280). That extra
-- shrink keeps the 286-wide stack clear of the centred hotbar on
-- narrow windows — otherwise the hotbar drifts left far enough to
-- overlap the bars at medium resolutions (~1000–1200 px wide).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui        = game:GetService("StarterGui")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Hide the default Roblox health bar (was in the old HealthUI).
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

-- ─── Layout constants ───────────────────────────────────────────────────
-- Container is 10% wider than before (260 → 286). Each slot is 36 tall
-- with a 6 px gap above → 42 px pitch. Bottoms: HP -18, hunger -60, mana
-- -102 px from the screen bottom.
local CONTAINER_W   = 286
local CONTAINER_H   = 36
local LEFT_X        = 14
local SLOT_PITCH    = 42
local ICON_SIZE     = 36

-- Bars: single-bar (HP / mana) spans from icon to the right margin
-- (40..282, w=242). Half-bars (hunger / thirst) each 101 wide with 4 px
-- gaps everywhere: icon 0..36, bar 40..141, bar 145..246, icon 250..286.
local FULL_BAR_X    = 40
local FULL_BAR_W    = 242
local FULL_BAR_H    = 26

local HUNGER_BAR_X  = 40
local THIRST_BAR_X  = 145
local HALF_BAR_W    = 101
local HALF_BAR_H    = 26
local RIGHT_ICON_X  = 250

local MANA_ICON_ASSET = "rbxassetid://131647230431306"

-- Shared palette (matches inventory theme).
local COLOR_ICON_BG   = Color3.fromRGB(10, 25, 55)
local COLOR_BAR_BG    = Color3.fromRGB(15, 35, 70)
local COLOR_ICON_TEXT = Color3.fromRGB(220, 240, 255)
local COLOR_MANA_TEXT = Color3.fromRGB(220, 240, 255)

-- Bar fill colours.
local FILL_MANA        = Color3.fromRGB(80, 160, 255)
local FILL_HUNGER_HI   = Color3.fromRGB(200, 150, 50)
local FILL_HUNGER_MID  = Color3.fromRGB(220, 170, 50)
local FILL_HUNGER_LOW  = Color3.fromRGB(200, 50, 50)
local FILL_THIRST_HI   = Color3.fromRGB(60, 150, 220)
local FILL_THIRST_MID  = Color3.fromRGB(220, 170, 50)
local FILL_THIRST_LOW  = Color3.fromRGB(200, 50, 50)
local FILL_HEALTH_HI   = Color3.fromRGB(210, 60, 70)
local FILL_HEALTH_MID  = Color3.fromRGB(220, 120, 60)
local FILL_HEALTH_LOW  = Color3.fromRGB(170, 40, 50)

-- Outline = a darker shade of the bar's fill colour, per user spec:
--   HP        → dark red,
--   hunger    → brown,
--   water     → brown,
--   mana      → dark blue.
-- Icons intentionally have no UIStroke.
local OUTLINE_HEALTH = Color3.fromRGB(70, 18, 24)
local OUTLINE_HUNGER = Color3.fromRGB(70, 45, 18)
local OUTLINE_THIRST = Color3.fromRGB(70, 45, 18)
local OUTLINE_MANA   = Color3.fromRGB(20, 55, 110)

local TWEEN_TIME = 0.25

-- ─── ScreenGui + responsive UIScale ─────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "UIManager"
screenGui.DisplayOrder = 15
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Own UIScale. Slightly more aggressive than the inventory's (ref width
-- 1400 vs 1280) so the HUD always clears the centred hotbar.
local HUD_REF_WIDTH  = 1400
local HUD_REF_HEIGHT = 720
local HUD_MIN_SCALE  = 0.35
local HUD_MAX_SCALE  = 1.0

local uiScale = Instance.new("UIScale")
uiScale.Parent = screenGui

local function recomputeScale()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(HUD_REF_WIDTH, HUD_REF_HEIGHT)
	local s = math.min(vp.X / HUD_REF_WIDTH, vp.Y / HUD_REF_HEIGHT)
	uiScale.Scale = math.clamp(s, HUD_MIN_SCALE, HUD_MAX_SCALE)
end
recomputeScale()

local function hookCamera(cam)
	if not cam then return end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(recomputeScale)
end
hookCamera(workspace.CurrentCamera)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	hookCamera(workspace.CurrentCamera)
	recomputeScale()
end)

-- Also register with the inventory's scale map so that if that system
-- ever rescales globally we follow along. Our local UIScale will get
-- its .Scale overwritten on viewport changes; both code paths converge
-- on the same value, so no conflict.
task.spawn(function()
	local deadline = os.clock() + 5
	while not _G.AttachInventoryUIScale and os.clock() < deadline do
		task.wait()
	end
	if _G.AttachInventoryUIScale then
		-- Inventory's attach will no-op since we already have a UIScale;
		-- but registering ensures it keeps the reference in its weak map.
		_G.AttachInventoryUIScale(screenGui)
	end
	-- After inventory registration, recompute with *our* ref width so the
	-- more aggressive scale wins.
	recomputeScale()
end)

-- ─── Builder helpers ────────────────────────────────────────────────────
local function makeContainer(name, bottomOffset)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0, 1)
	f.Position = UDim2.new(0, LEFT_X, 1, bottomOffset)
	f.Size = UDim2.new(0, CONTAINER_W, 0, CONTAINER_H)
	f.BackgroundTransparency = 1
	f.Parent = screenGui
	return f
end

-- Icon badge: circular dark-navy disc. No UIStroke — icons are bare
-- per the user spec (only the bars get outlines).
local function makeIconBadge(parent, x, opts)
	local bg = Instance.new("Frame")
	bg.Name = opts.name or "IconBg"
	bg.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
	bg.Position = UDim2.new(0, x, 0, 0)
	bg.BackgroundColor3 = COLOR_ICON_BG
	bg.BorderSizePixel = 0
	bg.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = bg

	if opts.image then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Image = opts.image
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromOffset(28, 28)
		img.Parent = bg
	else
		local txt = Instance.new("TextLabel")
		txt.Name = "Icon"
		txt.Size = UDim2.new(1, 0, 1, 0)
		txt.BackgroundTransparency = 1
		txt.Text = opts.text or ""
		txt.TextSize = 20
		txt.Font = Enum.Font.GothamBold
		txt.TextColor3 = COLOR_ICON_TEXT
		txt.Parent = bg
	end

	return bg
end

local function makeBarBg(parent, x, w, outlineColor)
	local bg = Instance.new("Frame")
	bg.Name = "BarBg"
	bg.AnchorPoint = Vector2.new(0, 0.5)
	bg.Position = UDim2.new(0, x, 0.5, 0)
	bg.Size = UDim2.new(0, w, 0, FULL_BAR_H)
	bg.BackgroundColor3 = COLOR_BAR_BG
	bg.BorderSizePixel = 0
	bg.ClipsDescendants = false
	bg.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = bg

	local stroke = Instance.new("UIStroke")
	stroke.Color = outlineColor
	stroke.Thickness = 2
	stroke.Parent = bg

	return bg
end

local function makeFill(parent, color, anchorRight)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	if anchorRight then
		fill.AnchorPoint = Vector2.new(1, 0)
		fill.Position = UDim2.new(1, 0, 0, 0)
	else
		fill.AnchorPoint = Vector2.new(0, 0)
		fill.Position = UDim2.new(0, 0, 0, 0)
	end
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = fill

	return fill
end

-- ─── Mana (top slot) ────────────────────────────────────────────────────
local manaContainer = makeContainer("ManaContainer", -102)
makeIconBadge(manaContainer, 0, { name = "IconBg", image = MANA_ICON_ASSET })
local manaBarBg = makeBarBg(manaContainer, FULL_BAR_X, FULL_BAR_W, OUTLINE_MANA)
local manaFill  = makeFill(manaBarBg, FILL_MANA, false)
manaFill.ZIndex = 1

local manaText = Instance.new("TextLabel")
manaText.Name = "ManaText"
manaText.BackgroundTransparency = 1
manaText.Font = Enum.Font.GothamBold
manaText.TextSize = 16
manaText.TextColor3 = COLOR_MANA_TEXT
manaText.TextStrokeTransparency = 0.25
manaText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
manaText.AnchorPoint = Vector2.new(0.5, 0.5)
manaText.Position = UDim2.fromScale(0.5, 0.5)
manaText.Size = UDim2.fromOffset(80, 20)
manaText.Text = "0"
manaText.ZIndex = 2
manaText.Parent = manaBarBg

local function updateMana(current, max, animate)
	local ratio = 0
	if max > 0 then ratio = math.clamp(current / max, 0, 1) end
	local fillGoal = UDim2.fromScale(ratio, 1)
	local textGoal = UDim2.fromScale(ratio / 2, 0.5)

	manaText.Text = tostring(current)

	if animate then
		local info = TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(manaFill, info, { Size = fillGoal }):Play()
		TweenService:Create(manaText, info, { Position = textGoal }):Play()
	else
		manaFill.Size = fillGoal
		manaText.Position = textGoal
	end
end

task.spawn(function()
	local folder  = player:WaitForChild("Characteristics")
	local current = folder:WaitForChild("ManaCurrent")
	local max     = folder:WaitForChild("ManaMax")

	updateMana(current.Value, max.Value, false)

	local function refresh()
		updateMana(current.Value, max.Value, true)
	end
	current:GetPropertyChangedSignal("Value"):Connect(refresh)
	max:GetPropertyChangedSignal("Value"):Connect(refresh)
end)

-- ─── Hunger + Thirst (middle slot) ──────────────────────────────────────
local hungerContainer = makeContainer("HungerContainer", -60)
makeIconBadge(hungerContainer, 0, { name = "HungerIconBg", text = "\u{1F356}" })  -- 🍖
local hungerBarBg = makeBarBg(hungerContainer, HUNGER_BAR_X, HALF_BAR_W, OUTLINE_HUNGER)
local hungerFill  = makeFill(hungerBarBg, FILL_HUNGER_HI, false)

local thirstBarBg = makeBarBg(hungerContainer, THIRST_BAR_X, HALF_BAR_W, OUTLINE_THIRST)
-- Water fill is mirrored: anchored to right edge and grows leftward so
-- full water = right-aligned full bar, 0% = collapsed against right.
local thirstFill  = makeFill(thirstBarBg, FILL_THIRST_HI, true)
makeIconBadge(hungerContainer, RIGHT_ICON_X, { name = "ThirstIconBg", text = "\u{1F4A7}" })  -- 💧

local function colorFor(ratio, hi, mid, low)
	if ratio > 0.5 then return hi end
	if ratio > 0.25 then return mid end
	return low
end

local function updateHunger(hunger, max)
	local ratio = math.clamp(hunger / max, 0, 1)
	TweenService:Create(hungerFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
		Size = UDim2.new(ratio, 0, 1, 0),
	}):Play()
	TweenService:Create(hungerFill, TweenInfo.new(0.3), {
		BackgroundColor3 = colorFor(ratio, FILL_HUNGER_HI, FILL_HUNGER_MID, FILL_HUNGER_LOW),
	}):Play()
end

local function updateThirst(thirst, max)
	local ratio = math.clamp(thirst / max, 0, 1)
	TweenService:Create(thirstFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
		Size = UDim2.new(ratio, 0, 1, 0),
	}):Play()
	TweenService:Create(thirstFill, TweenInfo.new(0.3), {
		BackgroundColor3 = colorFor(ratio, FILL_THIRST_HI, FILL_THIRST_MID, FILL_THIRST_LOW),
	}):Play()
end

do
	local hungerEvent = ReplicatedStorage:WaitForChild("HungerUpdate")
	local thirstEvent = ReplicatedStorage:WaitForChild("ThirstUpdate")
	hungerEvent.OnClientEvent:Connect(updateHunger)
	thirstEvent.OnClientEvent:Connect(updateThirst)
end

-- ─── Health (bottom slot) ───────────────────────────────────────────────
local healthContainer = makeContainer("HealthContainer", -18)
makeIconBadge(healthContainer, 0, { name = "IconBg", text = "\u{2764}" })
local healthBarBg = makeBarBg(healthContainer, FULL_BAR_X, FULL_BAR_W, OUTLINE_HEALTH)
local healthFill  = makeFill(healthBarBg, FILL_HEALTH_HI, false)

local function updateHealth(health, maxHealth)
	local ratio = math.clamp(health / maxHealth, 0, 1)
	TweenService:Create(healthFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
		Size = UDim2.new(ratio, 0, 1, 0),
	}):Play()
	TweenService:Create(healthFill, TweenInfo.new(0.3), {
		BackgroundColor3 = colorFor(ratio, FILL_HEALTH_HI, FILL_HEALTH_MID, FILL_HEALTH_LOW),
	}):Play()
end

local function onCharacterAdded(char)
	local hum = char:WaitForChild("Humanoid")
	updateHealth(hum.Health, hum.MaxHealth)
	hum.HealthChanged:Connect(function(newHealth)
		updateHealth(newHealth, hum.MaxHealth)
	end)
end

if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
player.CharacterAdded:Connect(function(newChar)
	-- Reset to full on respawn so the bar doesn't briefly show stale state.
	healthFill.Size = UDim2.new(1, 0, 1, 0)
	healthFill.BackgroundColor3 = FILL_HEALTH_HI
	onCharacterAdded(newChar)
end)
