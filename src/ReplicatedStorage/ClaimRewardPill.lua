--[[
	Плашка «НАГРАДА · (подарок) · Забрать награду ›» над окном реплики
	(design_handoff_claim_reward).

	local pill = Pill.new(plate, scaleFn)   -- plate = Frame окна реплики
	pill:Show(function() ... end)           -- колбэк по нажатию (до анимации ухода)
	pill:Hide()                             -- спрятать без нажатия
	pill:IsShown()

	⚠️ Плашка живёт НЕ внутри plate, а отдельным хостом в той же ScreenGui и
	каждый кадр встаёт над левым верхним углом plate: у окна реплики свой
	UIListLayout — ребёнка он бы просто уложил в стопку под текстом.
	scaleFn() — текущий масштаб окна (UIScale диалога), чтобы плашка росла с ним.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Assets = require(ReplicatedStorage:WaitForChild("ClaimRewardAssets"))

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local GLASS = Color3.fromRGB(30, 30, 32)
local BLUE = Color3.fromHex("7CC4FF")
local GOLD = Color3.fromHex("FFD95A")
local GLOW = Color3.fromHex("FFC83A")
local LIFT = -14   -- зазор над окном
local PAD_X = 14  -- по левому краю текста реплики (UIPadding окна)

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do i[k] = v end
	i.Parent = parent
	return i
end

local Pill = {}
Pill.__index = Pill

function Pill.new(dialogFrame, scaleFn)
	local self = setmetatable({}, Pill)
	self.target = dialogFrame
	self.scaleFn = scaleFn

	local screen = dialogFrame:FindFirstAncestorWhichIsA("LayerCollector")
	self.host = new("Frame", { Name = "ClaimRewardHost", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0),
		Visible = false, ZIndex = 20 }, screen)
	self.hostScale = new("UIScale", {}, self.host)

	local anchor = new("Frame", { Name = "ClaimRewardPill", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, PAD_X, 0, LIFT), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
		ZIndex = 20 }, self.host)
	self.scale = new("UIScale", {}, anchor)

	local btn = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = GLASS, BackgroundTransparency = 0.38,
		AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), ZIndex = 20 }, anchor)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, btn)
	new("UIPadding", { PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 24), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, btn)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder }, btn)
	self.btn = btn

	-- «НАГРАДА» (разрядку имитируем пробелами)
	new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, Text = "Н А Г Р А Д А", TextSize = 13, TextColor3 = BLUE,
		AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), LayoutOrder = 1, ZIndex = 21 }, btn)

	-- круг 60 px: тёмный, золотая обводка, свечение, подарок, искры
	local circle = new("Frame", { BackgroundColor3 = Color3.fromRGB(20, 24, 30), BackgroundTransparency = 0.15, Size = UDim2.fromOffset(60, 60),
		LayoutOrder = 2, ClipsDescendants = false, ZIndex = 21 }, btn)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, circle)
	self.ring = new("UIStroke", { Color = GOLD, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, circle)
	self.glow = new("ImageLabel", { BackgroundTransparency = 1, Image = Assets.GlowSoft, ImageColor3 = GLOW, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(60, 60), ZIndex = 22 }, circle)
	self.gift = new("ImageLabel", { BackgroundTransparency = 1, Image = Assets.Gift, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(38, 38), ZIndex = 23 }, circle)
	self.sparks = {}
	for i, p in ipairs({ { 0.08, 0.10 }, { 0.92, 0.18 }, { 0.88, 0.88 }, { 0.12, 0.84 } }) do
		self.sparks[i] = new("ImageLabel", { BackgroundTransparency = 1, Image = Assets.Sparkle, ImageColor3 = Color3.fromHex("FFF3A8"),
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(p[1], p[2]), Size = UDim2.fromOffset(9, 9), ZIndex = 24 }, circle)
	end

	new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, Text = "Забрать награду", TextSize = 20, TextColor3 = Color3.new(1, 1, 1),
		AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), LayoutOrder = 3, ZIndex = 21 }, btn)
	-- стрелку двигаем внутри рамки: Position прямого ребёнка UIListLayout игнорирует
	local arrowBox = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 28), LayoutOrder = 4, ZIndex = 21 }, btn)
	self.arrow = new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, Text = "›", TextSize = 28, TextColor3 = GOLD,
		Size = UDim2.fromOffset(16, 28), ZIndex = 21 }, arrowBox)

	self.anchor = anchor
	btn.MouseEnter:Connect(function() if self.cb then btn.BackgroundTransparency = 0.25 end end)
	btn.MouseLeave:Connect(function() if self.cb then btn.BackgroundTransparency = 0.38 end end)
	btn.Activated:Connect(function()
		if not self.cb then return end
		local cb = self.cb
		self.cb = nil
		cb()
		self:Hide()
	end)

	-- картинки прогреваем заранее: иначе в первый показ круг пустой секунду
	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync({ self.glow, self.gift, self.sparks[1] }) end)
	end)
	return self
end

-- встать над окном реплики. ⚠️ AbsolutePosition отсчитан от низа топбара даже в
-- ScreenGui с IgnoreGuiInset, а позиция внутри неё — от верха экрана: +инсет
function Pill:_follow()
	local t = self.target
	local p = t.AbsolutePosition + Vector2.new(0, GuiService:GetGuiInset().Y)
	self.host.Position = UDim2.fromOffset(p.X, p.Y)
	self.hostScale.Scale = self.scaleFn and self.scaleFn() or 1
end

function Pill:_loop()
	if self.conn then self.conn:Disconnect() end
	local t0 = os.clock()
	self.conn = RunService.RenderStepped:Connect(function()
		self:_follow()
		local t = os.clock() - t0
		local k = 0.5 - 0.5 * math.cos(t / 1.6 * math.pi * 2)              -- пульс 1.6 c
		local s = 60 * (0.85 + 0.27 * k)
		self.glow.Size = UDim2.fromOffset(s, s)
		self.glow.ImageTransparency = 0.55 * (1 - k)
		self.ring.Thickness = 3 + 1.5 * k
		local b = math.sin(t / 1.2 * math.pi * 2)                           -- подарок 1.2 c
		self.gift.Rotation = b * 7.5
		self.gift.Position = UDim2.new(0.5, 0, 0.5, -3 * math.max(b, 0))
		for i, sp in ipairs(self.sparks) do
			local q = 0.5 - 0.5 * math.cos((t + i * 0.4) / 1.6 * math.pi * 2)
			sp.Size = UDim2.fromOffset(9 * (0.3 + 0.7 * q), 9 * (0.3 + 0.7 * q))
			sp.ImageTransparency = 1 - q
		end
		self.arrow.Position = UDim2.fromOffset(4 * (0.5 - 0.5 * math.cos(t / 0.9 * math.pi * 2)), 0)
	end)
end

function Pill:IsShown()
	return self.cb ~= nil
end

function Pill:Show(onClaim)
	self.cb = onClaim
	self.token = (self.token or 0) + 1
	self:_follow()
	self.host.Visible = true
	self.scale.Scale = 1
	self.btn.BackgroundTransparency = 1
	self.anchor.Position = UDim2.new(0, PAD_X, 0, LIFT + 8)
	TweenService:Create(self.btn, TweenInfo.new(0.25), { BackgroundTransparency = 0.38 }):Play()
	TweenService:Create(self.anchor, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = UDim2.new(0, PAD_X, 0, LIFT) }):Play()
	self:_loop()
end

function Pill:Hide()
	if not self.host.Visible then return end
	self.cb = nil
	local token = self.token
	local tw = TweenService:Create(self.scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
	tw:Play()
	tw.Completed:Once(function()
		if token ~= self.token then return end   -- за это время показали заново
		self.host.Visible = false
		if self.conn then self.conn:Disconnect(); self.conn = nil end
	end)
end

return Pill
