-- Клиент, внутри модуля окна торговца.
-- Если у торговца ровно одно предложение и оно бесплатное (price == 0, isGift == true),
-- вместо списка строк показываем одну большую карточку подарка на всю панель.
--
-- local GiftCard = require(script.GiftCard)
-- local card = GiftCard.new(offersPanel)   -- offersPanel = Frame под шапкой «Предложения»
-- card:Set(offer, function() MerchantBuy:InvokeServer(offer.id) end)
-- card:SetClaimed(true)                     -- после успешного ответа сервера

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Assets = require(ReplicatedStorage:WaitForChild("MerchantGiftAssets"))

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local C = {
	goldTop = Color3.fromHex("FFE38A"), goldBot = Color3.fromHex("F7C24E"), goldBorder = Color3.fromHex("B07A14"),
	slot = Color3.fromHex("FFF3C9"), brown = Color3.fromHex("7A4F06"),
	red = Color3.fromHex("E84A3A"), redBorder = Color3.fromHex("A82E2E"),
	greenTop = Color3.fromHex("6FF08A"), greenBot = Color3.fromHex("34B84E"), greenBorder = Color3.fromHex("1F7A33"),
	doneBg = Color3.fromHex("C9A45A"), doneBorder = Color3.fromHex("9A7A32"), doneText = Color3.fromHex("FFF6DC"),
}

local function new(class, props, parent) local i = Instance.new(class); for k, v in pairs(props) do i[k] = v end; i.Parent = parent; return i end
local function corner(p, r) new("UICorner", { CornerRadius = UDim.new(0, r) }, p) end
local function stroke(p, col, t, mode) return new("UIStroke", { Color = col, Thickness = t, ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Round }, p) end
local function grad(p, a, b) return new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = 90 }, p) end

local GiftCard = {}
GiftCard.__index = GiftCard

function GiftCard.new(parent: GuiObject)
	local self = setmetatable({}, GiftCard)

	-- карточка = весь parent
	local card = new("Frame", { Name = "GiftCard", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), Visible = false }, parent)
	corner(card, 18); stroke(card, C.goldBorder, 4); grad(card, C.goldTop, C.goldBot)
	new("UIPadding", { PaddingTop = UDim.new(0, 22), PaddingBottom = UDim.new(0, 18), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, card)
	self.card = card

	-- лента на верхней кромке
	local ribbon = new("TextLabel", { Text = "ПОДАРОК ТОРГОВЦА", FontFace = FONT, TextSize = 13, TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = C.red, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, -22),
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), ZIndex = 5 }, card)
	corner(ribbon, 12); stroke(ribbon, C.redBorder, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, ribbon)

	local list = new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, card)
	_ = list

	-- сцена: лучи + слот рендера (растягивается на остаток высоты через UIFlexItem)
	local stage = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 170), LayoutOrder = 1, ClipsDescendants = false }, card)
	new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }, stage)
	self.rays = new("ImageLabel", { BackgroundTransparency = 1, Image = Assets.Rays, ImageTransparency = 0.25, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 300), ZIndex = 1 }, stage)
	local slot = new("Frame", { BackgroundColor3 = C.slot, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(210, 150), ZIndex = 2 }, stage)
	corner(slot, 18); stroke(slot, C.goldBorder, 4)
	self.icon = new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -16, 1, -16), Position = UDim2.fromOffset(8, 8),
		ScaleType = Enum.ScaleType.Fit, ZIndex = 3 }, slot)

	-- текст
	self.title = new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextSize = 28, TextColor3 = Color3.new(1, 1, 1),
		AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), LayoutOrder = 2 }, card)
	stroke(self.title, C.brown, 3, Enum.ApplyStrokeMode.Contextual)
	self.desc = new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextSize = 14, TextColor3 = C.brown, TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(0, 420, 0, 0), LayoutOrder = 3 }, card)

	-- кнопка
	local btn = new("TextButton", { Text = "Забрать бесплатно", FontFace = FONT, TextSize = 21, TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(320, 52), LayoutOrder = 4 }, card)
	corner(btn, 14)
	self.btnStroke = stroke(btn, C.greenBorder, 3)
	self.btnGrad = grad(btn, C.greenTop, C.greenBot)
	stroke(btn, Color3.new(0, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual).Transparency = 0.7
	-- белое внешнее кольцо
	local ring = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 6, 1, 6), Position = UDim2.fromOffset(-3, -3), ZIndex = 0 }, btn)
	corner(ring, 17); self.ring = stroke(ring, Color3.new(1, 1, 1), 3)
	self.btn = btn

	new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextSize = 12, TextColor3 = C.brown, Text = "Только 1 раз",
		AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), LayoutOrder = 5 }, card)

	btn.Activated:Connect(function()
		if self.claimed or not self.onClaim then return end
		self.onClaim()
	end)
	return self
end

function GiftCard:Set(offer, onClaim)
	self.title.Text = offer.name
	self.desc.Text = offer.description or ""
	self.icon.Image = offer.image or ""
	self.onClaim = onClaim
	self:SetClaimed(offer.claimed == true)
	self.card.Visible = true
	if self.conn then self.conn:Disconnect() end
	local t0 = os.clock()
	self.conn = RunService.RenderStepped:Connect(function()
		self.rays.Rotation = ((os.clock() - t0) / 12 * 360) % 360
	end)
end

function GiftCard:SetClaimed(v: boolean)
	self.claimed = v
	self.btn.Text = v and "Получено" or "Забрать бесплатно"
	self.btn.TextColor3 = v and C.doneText or Color3.new(1, 1, 1)
	self.btnGrad.Color = v and ColorSequence.new(C.doneBg, C.doneBg) or ColorSequence.new(C.greenTop, C.greenBot)
	self.btnStroke.Color = v and C.doneBorder or C.greenBorder
	self.ring.Transparency = v and 1 or 0
end

function GiftCard:Hide()
	self.card.Visible = false
	if self.conn then self.conn:Disconnect(); self.conn = nil end
end

return GiftCard
