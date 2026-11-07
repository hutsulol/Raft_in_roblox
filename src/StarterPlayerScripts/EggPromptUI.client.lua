-- EggPromptUI.client.lua
-- Fully CLIENT-SIDE "Открыть яйцо" prompt for the (separate) Workspace.pedestal.
-- Nothing is added to the pedestal on the server: the SurfaceGui lives on a
-- CLIENT-LOCAL part, so the raft/streaming system never sees or tags it — it
-- can't make the pedestal glow or disappear. Shows within range; E (PC) or a
-- tap (mobile) opens the menu. Just a GUI.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))
local player = Players.LocalPlayer

local RANGE = 10
local FORWARD, HEIGHT = 2.6, 1.4 -- where the prompt sits relative to the pedestal
local FACE_LEFT = true           -- face out the pedestal's left side (set false for its front)
local E_ICON = ""    -- optional rbxassetid for the E key image
local COIN_ICON = "" -- optional rbxassetid for the coin image

-- palette (matches the reference background + key)
local PANEL_TOP = Color3.fromHex("3a86d4")
local PANEL_MID = Color3.fromHex("1c5fa6")
local PANEL_BOT = Color3.fromHex("103f7d")
local PANEL_EDGE = Color3.fromHex("bfe3fb")
local KEY_TOP = Color3.fromHex("eef7ff")
local KEY_BOT = Color3.fromHex("a9d6f7")
local KEY_DARK = Color3.fromHex("12539a")
local WHITE = Color3.fromHex("ffffff")
local COIN_TOP = Color3.fromHex("ffd95a")
local COIN_BOT = Color3.fromHex("f5b73c")
local COIN_EDGE = Color3.fromHex("b07a14")
local FONT = Enum.Font.GothamBlack

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(i, r) new("UICorner", { CornerRadius = UDim.new(0, r) }, i) end
local function stroke(i, c, t) new("UIStroke", { Color = c, Thickness = t }, i) end
local function grad3(i, a, b, c)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.6, b), ColorSequenceKeypoint.new(1, c),
	}) }, i)
end

local pedestal = workspace:WaitForChild("pedestal")
local pedPart = (pedestal:IsA("BasePart") and pedestal) or pedestal.PrimaryPart or pedestal:FindFirstChildWhichIsA("BasePart", true)
while not pedPart do
	task.wait(0.2)
	pedPart = pedestal:FindFirstChildWhichIsA("BasePart", true)
end

local function openEgg()
	if _G.OpenEggMenu then _G.OpenEggMenu() end
end

-- ── client-local surface (NOT replicated → no raft tags, no streaming) ──
local surfacePart = Instance.new("Part")
surfacePart.Name = "EggPromptSurface"
surfacePart.Anchored = true
surfacePart.CanCollide = false
surfacePart.CanQuery = false
surfacePart.CastShadow = false
surfacePart.Transparency = 1
surfacePart.Size = Vector3.new(4.6, 1.6, 0.2)
surfacePart.Parent = workspace

local sg = new("SurfaceGui", {
	Name = "EggPrompt", Face = Enum.NormalId.Front,
	SizingMode = Enum.SurfaceGuiSizingMode.FixedSize, CanvasSize = Vector2.new(460, 160),
	LightInfluence = 0, AlwaysOnTop = false, Enabled = false,
}, surfacePart)

-- panel is a button so a tap / click also opens the egg (mobile)
local panel = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = WHITE,
	Size = UDim2.fromScale(1, 1) }, sg)
corner(panel, 30)
stroke(panel, PANEL_EDGE, 4)
grad3(panel, PANEL_TOP, PANEL_MID, PANEL_BOT)
local hi = new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.6,
	Size = UDim2.new(1, -24, 0, 6), Position = UDim2.new(0, 12, 0, 7) }, panel)
corner(hi, 4)
new("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 22) }, panel)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 18),
	HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder }, panel)

local keyBox = new("Frame", { BackgroundColor3 = WHITE, Size = UDim2.fromOffset(118, 118), LayoutOrder = 1 }, panel)
corner(keyBox, 24)
if E_ICON ~= "" then
	new("ImageLabel", { BackgroundTransparency = 1, Image = E_ICON, ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1, 1) }, keyBox)
else
	stroke(keyBox, KEY_DARK, 7)
	grad3(keyBox, KEY_TOP, Color3.fromHex("c9e6fb"), KEY_BOT)
	local keyHi = new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.45,
		Size = UDim2.new(1, -20, 0, 8), Position = UDim2.new(0, 10, 0, 8) }, keyBox)
	corner(keyHi, 4)
	new("TextLabel", { Text = "E", Font = FONT, TextSize = 70, TextColor3 = KEY_DARK,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, keyBox)
end

local col = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(258, 120), LayoutOrder = 2 }, panel)
new("TextLabel", { Text = "Открыть яйцо", Font = FONT, TextSize = 32, TextColor3 = WHITE,
	BackgroundTransparency = 1, TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0.6,
	Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left }, col)
local costRow = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44),
	Position = UDim2.new(0, 0, 0, 60) }, col)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
	VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, costRow)
local coin = new("Frame", { BackgroundColor3 = WHITE, Size = UDim2.fromOffset(38, 38), LayoutOrder = 1 }, costRow)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, coin)
if COIN_ICON ~= "" then
	new("ImageLabel", { BackgroundTransparency = 1, Image = COIN_ICON, ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1, 1) }, coin)
else
	stroke(coin, COIN_EDGE, 3)
	new("UIGradient", { Color = ColorSequence.new(COIN_TOP, COIN_BOT), Rotation = 90 }, coin)
	new("TextLabel", { Text = "$", Font = FONT, TextSize = 20, TextColor3 = COIN_EDGE,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, coin)
end
new("TextLabel", { Text = "35", Font = FONT, TextSize = 34, TextColor3 = WHITE, BackgroundTransparency = 1,
	TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0.6,
	Size = UDim2.fromOffset(64, 40), LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Left }, costRow)

panel.MouseButton1Click:Connect(openEgg)

-- ── keep the surface in front of the pedestal (rides the raft) + show in range ──
local inRange = false
RunService.RenderStepped:Connect(function()
	if not pedPart.Parent then return end
	local pedCF = pedPart.CFrame
	local fwd = FACE_LEFT and -pedCF.RightVector or pedCF.LookVector
	fwd = Vector3.new(fwd.X, 0, fwd.Z)
	if fwd.Magnitude < 0.01 then fwd = Vector3.new(0, 0, -1) end
	fwd = fwd.Unit
	local pos = pedPart.Position + fwd * FORWARD + Vector3.new(0, HEIGHT, 0)
	surfacePart.CFrame = CFrame.lookAt(pos, pos + fwd)

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	inRange = hrp ~= nil and (hrp.Position - pedPart.Position).Magnitude <= RANGE
	sg.Enabled = inRange
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if GamepadInput.isKey(input, Enum.KeyCode.E) and inRange then openEgg() end
end)
