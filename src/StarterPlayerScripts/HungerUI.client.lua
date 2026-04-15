-- HungerUI.client.lua
-- Combined hunger + water HUD bar shown in the middle slot of the
-- bottom-left stack. Hunger takes the LEFT half (icon on the far
-- left, fills left→right like a normal progress bar so it depletes
-- right→left); water takes the RIGHT half (icon on the far right,
-- mirrored so it fills right→left and depletes left→right). Both
-- halves are driven by their own replicated update events
-- (HungerUpdate / ThirstUpdate) — ThirstUI used to own its own
-- ScreenGui but has been folded into this script so the two bars
-- visually share a single slot in the HUD stack.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local hungerEvent = ReplicatedStorage:WaitForChild("HungerUpdate")
local thirstEvent = ReplicatedStorage:WaitForChild("ThirstUpdate")

-- ─── Create UI ───
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HungerUI"
screenGui.DisplayOrder = 15
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Share the inventory's responsive UIScale so this HUD shrinks on
-- phones / narrow screens instead of overflowing next to the hotbar.
task.spawn(function()
	local deadline = os.clock() + 5
	while not _G.AttachInventoryUIScale and os.clock() < deadline do
		task.wait()
	end
	if _G.AttachInventoryUIScale then
		_G.AttachInventoryUIScale(screenGui)
	end
end)

-- Container — middle slot of the left HUD stack.
local container = Instance.new("Frame")
container.Name = "HungerContainer"
container.AnchorPoint = Vector2.new(0, 1)
container.Position = UDim2.new(0, 12, 1, -118)
container.Size = UDim2.new(0, 200, 0, 28)
container.BackgroundTransparency = 1
container.Parent = screenGui

-- ─── Helpers ─────────────────────────────────────────────────────────────
-- Circular brown icon badge with an emoji glyph inside. Matches the
-- existing HealthUI / former ThirstUI icon style so all three slots
-- in the stack line up visually.
local function buildIconBg(name, x, emoji)
	local iconBg = Instance.new("Frame")
	iconBg.Name = name
	iconBg.Size = UDim2.new(0, 28, 0, 28)
	iconBg.Position = UDim2.new(0, x, 0, 0)
	iconBg.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	iconBg.BorderSizePixel = 0
	iconBg.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = iconBg

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 40, 20)
	stroke.Thickness = 1.5
	stroke.Parent = iconBg

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(1, 0, 1, 0)
	icon.BackgroundTransparency = 1
	icon.Text = emoji
	icon.TextSize = 16
	icon.Font = Enum.Font.GothamBold
	icon.TextColor3 = Color3.fromRGB(255, 255, 255)
	icon.Parent = iconBg
end

-- Half-width tan bar background. The x offset is the pixel position
-- of the bar's left edge inside the container.
local function buildBarBg(name, x)
	local bg = Instance.new("Frame")
	bg.Name = name
	bg.AnchorPoint = Vector2.new(0, 0.5)
	bg.Position = UDim2.new(0, x, 0.5, 0)
	bg.Size = UDim2.new(0, 66, 0, 20)
	bg.BackgroundColor3 = Color3.fromRGB(160, 130, 85)
	bg.BorderSizePixel = 0
	bg.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = bg

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 60, 30)
	stroke.Thickness = 2
	stroke.Parent = bg
	return bg
end

-- ─── Layout ──────────────────────────────────────────────────────────────
-- Container is 200px wide. Pixels used left-to-right:
--   [0..28]   hunger icon
--   [32..98]  hunger bar       (66 wide)
--   [102..168] water bar       (66 wide)
--   [172..200] water icon
-- Gaps of 4px between icon and its bar and between the two bars.
buildIconBg("HungerIconBg", 0, "\u{1F356}")  -- 🍖
local hungerBg = buildBarBg("HungerBarBg", 32)

local hungerFill = Instance.new("Frame")
hungerFill.Name = "Fill"
hungerFill.AnchorPoint = Vector2.new(0, 0)
hungerFill.Position = UDim2.new(0, 0, 0, 0)
hungerFill.Size = UDim2.new(1, 0, 1, 0)
hungerFill.BackgroundColor3 = Color3.fromRGB(200, 150, 50)
hungerFill.BorderSizePixel = 0
hungerFill.Parent = hungerBg

local hungerFillCorner = Instance.new("UICorner")
hungerFillCorner.CornerRadius = UDim.new(0, 4)
hungerFillCorner.Parent = hungerFill

local thirstBg = buildBarBg("ThirstBarBg", 102)

-- Water fill is mirrored: anchored to the RIGHT edge of the track and
-- grows leftward. At 100% water the fill covers the whole right half;
-- at 50% water the left edge of the fill sits over the center of the
-- right half; at 0% the fill collapses to the right edge.
local thirstFill = Instance.new("Frame")
thirstFill.Name = "Fill"
thirstFill.AnchorPoint = Vector2.new(1, 0)
thirstFill.Position = UDim2.new(1, 0, 0, 0)
thirstFill.Size = UDim2.new(1, 0, 1, 0)
thirstFill.BackgroundColor3 = Color3.fromRGB(60, 150, 220)
thirstFill.BorderSizePixel = 0
thirstFill.Parent = thirstBg

local thirstFillCorner = Instance.new("UICorner")
thirstFillCorner.CornerRadius = UDim.new(0, 4)
thirstFillCorner.Parent = thirstFill

buildIconBg("ThirstIconBg", 172, "\u{1F4A7}")  -- 💧

-- ─── Update handlers ────────────────────────────────────────────────────
local function updateHunger(hunger, max)
	local ratio = math.clamp(hunger / max, 0, 1)

	TweenService:Create(hungerFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()

	local color
	if ratio > 0.5 then
		color = Color3.fromRGB(200, 150, 50)
	elseif ratio > 0.25 then
		color = Color3.fromRGB(220, 170, 50)
	else
		color = Color3.fromRGB(200, 50, 50)
	end

	TweenService:Create(hungerFill, TweenInfo.new(0.3), {
		BackgroundColor3 = color
	}):Play()
end

local function updateThirst(thirst, max)
	local ratio = math.clamp(thirst / max, 0, 1)

	TweenService:Create(thirstFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()

	local color
	if ratio > 0.5 then
		color = Color3.fromRGB(60, 150, 220)
	elseif ratio > 0.25 then
		color = Color3.fromRGB(220, 170, 50)
	else
		color = Color3.fromRGB(200, 50, 50)
	end

	TweenService:Create(thirstFill, TweenInfo.new(0.3), {
		BackgroundColor3 = color
	}):Play()
end

hungerEvent.OnClientEvent:Connect(function(hunger, max)
	updateHunger(hunger, max)
end)

thirstEvent.OnClientEvent:Connect(function(thirst, max)
	updateThirst(thirst, max)
end)
