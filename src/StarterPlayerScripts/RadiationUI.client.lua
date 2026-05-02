local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── Shared status icon slot coordination ───
-- See WindUI.client.lua for the full description. Whichever status icon
-- claims a slot first occupies the leftmost position; later ones sit to
-- its right. When the leftmost icon is released the others shift left.
local SLOTS = _G.StatusIconSlots
if not SLOTS then
	SLOTS = {
		order = {},
		hooks = {},
	}
	_G.StatusIconSlots = SLOTS
end

local function takeSlot(name)
	for _, entry in ipairs(SLOTS.order) do
		if entry.name == name then return end
	end
	table.insert(SLOTS.order, {name = name})
end

local function releaseSlot(name)
	for i, entry in ipairs(SLOTS.order) do
		if entry.name == name then
			table.remove(SLOTS.order, i)
			return
		end
	end
end

local function getSlotIndex(name)
	for i, entry in ipairs(SLOTS.order) do
		if entry.name == name then return i - 1 end
	end
	return -1
end

local function notifyAll()
	for _, fn in ipairs(SLOTS.hooks) do
		pcall(fn)
	end
end

local BASE_X = 16
-- Sits 10 px above the mana bar's top edge. The mana container in
-- UIManager is anchored to the screen bottom at y=-102 with height
-- 36, so its top is at screen_bottom - 138. We want the icon's
-- bottom (anchor 0,1) at screen_bottom - 148 → 10 px gap above
-- the bar.
local BASE_Y_OFFSET = -148
local SLOT_STRIDE = 44 -- 36px icon + 8px gap

-- ─── UI Setup ───
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RadiationUI"
screenGui.DisplayOrder = 16
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Mirror UIManager's HUD scale so the radiation icon shrinks in
-- lockstep with the mana / hunger / health bars. Without this the
-- bars scale down on narrow viewports while the icon stays at its
-- full -188 offset — the icon then floats far above the (scaled)
-- mana bar instead of sitting just above it. Constants must stay in
-- sync with UIManager.HUD_REF_WIDTH / HUD_REF_HEIGHT / clamps.
local HUD_REF_WIDTH  = 1400
local HUD_REF_HEIGHT = 720
local HUD_MIN_SCALE  = 0.35
local HUD_MAX_SCALE  = 1.0

local hudScale = Instance.new("UIScale")
hudScale.Parent = screenGui

local function recomputeScale()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(HUD_REF_WIDTH, HUD_REF_HEIGHT)
	local s = math.min(vp.X / HUD_REF_WIDTH, vp.Y / HUD_REF_HEIGHT)
	hudScale.Scale = math.clamp(s, HUD_MIN_SCALE, HUD_MAX_SCALE)
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

-- Radiation icon (positioned above the three stat bars)
local icon = Instance.new("ImageLabel")
icon.Name = "RadiationIcon"
icon.AnchorPoint = Vector2.new(0, 1)
icon.Position = UDim2.new(0, BASE_X, 1, BASE_Y_OFFSET)
icon.Size = UDim2.new(0, 36, 0, 36)
icon.BackgroundColor3 = Color3.fromRGB(60, 40, 20)
icon.BackgroundTransparency = 0.3
icon.Image = "rbxassetid://97523366830633"
icon.ScaleType = Enum.ScaleType.Stretch
icon.Visible = false
icon.Parent = screenGui

icon.ClipsDescendants = true

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = icon

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(90, 60, 30)
stroke.Thickness = 2
stroke.Parent = icon

-- ─── Cooldown overlay (grows top→bottom as radiation expires) ───
local cooldownOverlay = Instance.new("Frame")
cooldownOverlay.Name = "CooldownOverlay"
cooldownOverlay.AnchorPoint = Vector2.new(0, 0)
cooldownOverlay.Position = UDim2.new(0, 0, 0, 0)
cooldownOverlay.Size = UDim2.new(1, 0, 0, 0) -- starts hidden
cooldownOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
cooldownOverlay.BackgroundTransparency = 0.5
cooldownOverlay.BorderSizePixel = 0
cooldownOverlay.ZIndex = 2
cooldownOverlay.Parent = icon

-- ─── Tooltip (hover description) ───
-- Parented to screenGui (not icon) to avoid ClipsDescendants clipping
local tooltip = Instance.new("Frame")
tooltip.Name = "Tooltip"
tooltip.AnchorPoint = Vector2.new(0, 1)
tooltip.Position = UDim2.new(0, BASE_X + 36 + 8, 1, BASE_Y_OFFSET)
tooltip.Size = UDim2.new(0, 200, 0, 60)
tooltip.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
tooltip.BackgroundTransparency = 0.15
tooltip.Visible = false
tooltip.Parent = screenGui

local tooltipCorner = Instance.new("UICorner")
tooltipCorner.CornerRadius = UDim.new(0, 6)
tooltipCorner.Parent = tooltip

local tooltipStroke = Instance.new("UIStroke")
tooltipStroke.Color = Color3.fromRGB(120, 80, 30)
tooltipStroke.Thickness = 1.5
tooltipStroke.Parent = tooltip

local tooltipTitle = Instance.new("TextLabel")
tooltipTitle.Size = UDim2.new(1, -12, 0, 20)
tooltipTitle.Position = UDim2.new(0, 6, 0, 4)
tooltipTitle.BackgroundTransparency = 1
tooltipTitle.Text = "Radiation Sickness"
tooltipTitle.TextColor3 = Color3.fromRGB(255, 100, 100)
tooltipTitle.TextSize = 14
tooltipTitle.Font = Enum.Font.GothamBold
tooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
tooltipTitle.Parent = tooltip

local tooltipBody = Instance.new("TextLabel")
tooltipBody.Size = UDim2.new(1, -12, 0, 32)
tooltipBody.Position = UDim2.new(0, 6, 0, 24)
tooltipBody.BackgroundTransparency = 1
tooltipBody.Text = "Headache, increased hunger drain"
tooltipBody.TextColor3 = Color3.fromRGB(200, 200, 200)
tooltipBody.TextSize = 12
tooltipBody.Font = Enum.Font.Gotham
tooltipBody.TextXAlignment = Enum.TextXAlignment.Left
tooltipBody.TextWrapped = true
tooltipBody.Parent = tooltip

icon.MouseEnter:Connect(function()
	if icon.Visible then
		tooltip.Visible = true
	end
end)

icon.MouseLeave:Connect(function()
	tooltip.Visible = false
end)

-- ─── Headache Visual Effect ───
local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Name = "RadiationCC"
colorCorrection.Enabled = false
colorCorrection.Parent = Lighting

local blur = Instance.new("BlurEffect")
blur.Name = "RadiationBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

-- ─── Radiation timer tracking ───
local RADIATION_DURATION = 60
local radiationStartTime = 0

local radiationEvent = game:GetService("ReplicatedStorage"):WaitForChild("RadiationUpdate", 10)

if radiationEvent then
	radiationEvent.OnClientEvent:Connect(function(active, remaining, duration)
		if active then
			RADIATION_DURATION = duration or 60
			radiationStartTime = tick() - (RADIATION_DURATION - (remaining or RADIATION_DURATION))
		end
	end)
end

-- ─── Position refresh (slot-aware) ───
local function refreshPosition()
	local slot = getSlotIndex("radiation")
	if slot < 0 then
		icon.Visible = false
		tooltip.Visible = false
		return
	end
	icon.Visible = true
	local x = BASE_X + slot * SLOT_STRIDE
	icon.Position = UDim2.new(0, x, 1, BASE_Y_OFFSET)
	tooltip.Position = UDim2.new(0, x + 36 + 8, 1, BASE_Y_OFFSET)
end

table.insert(SLOTS.hooks, refreshPosition)

-- ─── Watch the RadiationSick attribute directly ───
local function onRadiationChanged()
	local sick = player:GetAttribute("RadiationSick") == true
	colorCorrection.Enabled = sick
	blur.Enabled = sick

	if sick then
		-- If we don't have a start time yet, assume just started
		if radiationStartTime == 0 then
			radiationStartTime = tick()
		end
		cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
		takeSlot("radiation")
	else
		colorCorrection.Saturation = 0
		colorCorrection.Contrast = 0
		colorCorrection.TintColor = Color3.fromRGB(255, 255, 255)
		blur.Size = 0
		cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
		radiationStartTime = 0
		releaseSlot("radiation")
	end

	notifyAll()
end

-- Connect to attribute changes
player:GetAttributeChangedSignal("RadiationSick"):Connect(onRadiationChanged)

-- Check initial state
onRadiationChanged()

-- ─── Headache pulsing effect + cooldown overlay while sick ───
game:GetService("RunService").Heartbeat:Connect(function()
	if not icon.Visible then return end

	local pulse = math.sin(tick() * 3) * 0.5 + 0.5
	colorCorrection.Saturation = -0.4 - pulse * 0.2
	colorCorrection.Contrast = 0.1 + pulse * 0.15
	colorCorrection.TintColor = Color3.fromRGB(
		255,
		math.floor(230 - pulse * 40),
		math.floor(220 - pulse * 50)
	)
	blur.Size = 3 + pulse * 4

	-- Update cooldown overlay (grows from top to bottom)
	local elapsed = tick() - radiationStartTime
	local progress = math.clamp(elapsed / RADIATION_DURATION, 0, 1)
	cooldownOverlay.Size = UDim2.new(1, 0, progress, 0)
end)
