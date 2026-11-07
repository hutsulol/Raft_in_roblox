--[[
	КАРТОЧКА «ПОДАРОК ТОРГОВЦА» (хендофф design_handoff_merchant_gift).
	Когда у торговца ровно одно предложение и это бесплатный подарок, окно
	(MerchantShopUI) вместо строки «Купить · 0» показывает её на всю панель:
	красная лента сверху, крупный рендер на вращающихся лучах, название,
	описание, большая зелёная «Забрать бесплатно» → «Получено», «Только 1 раз».

	local card = GiftCard.new(host)        -- host = Frame под шапкой «Предложения»
	card:Set(offer, onClaim)               -- offer: id, name, desc, image | model, claimed
	card:SetClaimed(true)
	card:Hide()

	⚠️ Отличия от исходника хендоффа: лента лежит не в самой карточке, а рядом
	(у карточки UIListLayout — он уложил бы ленту строкой в стопку), а без
	картинки (image) в слоте рисуется 3D-модель подарка (ModelIcon).
]]

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

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do i[k] = v end
	i.Parent = parent
	return i
end
local function corner(p, r) new("UICorner", { CornerRadius = UDim.new(0, r) }, p) end
local function stroke(p, col, t, mode)
	return new("UIStroke", { Color = col, Thickness = t, ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round }, p)
end
local function grad(p, a, b) return new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = 90 }, p) end

local GiftCard = {}
GiftCard.__index = GiftCard

function GiftCard.new(parent)
	local self = setmetatable({}, GiftCard)

	local wrap = new("Frame", { Name = "GiftCardHost", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, parent)
	self.wrap = wrap

	-- карточка = вся площадь
	local card = new("Frame", { Name = "GiftCard", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true }, wrap)
	corner(card, 18); stroke(card, C.goldBorder, 4); grad(card, C.goldTop, C.goldBot)
	new("UIPadding", { PaddingTop = UDim.new(0, 22), PaddingBottom = UDim.new(0, 16), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, card)
	new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, card)
	self.card = card

	-- лента на верхней кромке
	local ribbon = new("TextLabel", { Name = "Ribbon", Text = "ПОДАРОК ТОРГОВЦА", FontFace = FONT, TextSize = 13, TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = C.red, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), ZIndex = 5 }, wrap)
	corner(ribbon, 13); stroke(ribbon, C.redBorder, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, ribbon)

	-- сцена: лучи + слот рендера, растягивается на остаток высоты
	local stage = new("Frame", { Name = "Stage", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 120), LayoutOrder = 1 }, card)
	new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }, stage)
	self.rays = new("ImageLabel", { BackgroundTransparency = 1, Image = Assets.Rays, ImageColor3 = Color3.new(1, 1, 1),
		ImageTransparency = 0.25, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(300, 300), ZIndex = 1 }, stage)
	-- слот 210×150, но не выше сцены (на низком окне)
	local slot = new("Frame", { Name = "Slot", BackgroundColor3 = C.slot, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 210, 1, -6), ZIndex = 2 }, stage)
	new("UISizeConstraint", { MaxSize = Vector2.new(210, 150) }, slot)
	corner(slot, 18); stroke(slot, C.goldBorder, 4)
	self.slot = slot

	-- текст
	self.title = new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextSize = 28, TextColor3 = Color3.new(1, 1, 1),
		AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), LayoutOrder = 2 }, card)
	stroke(self.title, C.brown, 3, Enum.ApplyStrokeMode.Contextual)
	self.desc = new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextSize = 14, TextColor3 = C.brown, TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(0, 420, 0, 0), LayoutOrder = 3 }, card)

	-- кнопка + белое внешнее кольцо.
	-- ⚠️ ГРАДИЕНТ — НА ПОДЛОЖКЕ, А НЕ НА КНОПКЕ: UIGradient красит и текст своего
	-- объекта, и белая надпись становилась зелёной, сливалась с фоном.
	local btn = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
		Size = UDim2.fromOffset(320, 52), LayoutOrder = 4 }, card)
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 1 }, btn)
	corner(fill, 14)
	self.btnStroke = stroke(fill, C.greenBorder, 3)
	self.btnGrad = grad(fill, C.greenTop, C.greenBot)
	self.btnLabel = new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "Забрать бесплатно",
		FontFace = FONT, TextSize = 21, TextColor3 = Color3.new(1, 1, 1), ZIndex = 2 }, btn)
	stroke(self.btnLabel, Color3.new(0, 0, 0), 1.5, Enum.ApplyStrokeMode.Contextual).Transparency = 0.7
	local ring = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 6, 1, 6), Position = UDim2.fromOffset(-3, -3), ZIndex = 0 }, btn)
	corner(ring, 17); self.ring = stroke(ring, Color3.new(1, 1, 1), 3)
	self.btn = btn

	new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextSize = 12, TextColor3 = C.brown, Text = "Только 1 раз",
		AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), LayoutOrder = 5 }, card)

	btn.Activated:Connect(function()
		if self.claimed or self.busy or not self.onClaim then return end
		self.busy = true
		pcall(self.onClaim)
		self.busy = false
	end)
	return self
end

-- рендер подарка: картинка из offer.image, иначе 3D-модель (ModelIcon)
function GiftCard:_icon(offer)
	pcall(function() require(ReplicatedStorage:WaitForChild("ModelIcon")).reclaim(self.slot) end)
	for _, c in ipairs(self.slot:GetChildren()) do
		if c:IsA("ImageLabel") or c:IsA("ViewportFrame") then c:Destroy() end
	end
	if type(offer.image) == "string" and offer.image ~= "" then
		new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -16, 1, -16), Position = UDim2.fromOffset(8, 8),
			Image = offer.image, ScaleType = Enum.ScaleType.Fit, ZIndex = 3 }, self.slot)
		return
	end
	local ok, AssetFind = pcall(function() return require(ReplicatedStorage:WaitForChild("AssetFind")) end)
	local ok2, ModelIcon = pcall(function() return require(ReplicatedStorage:WaitForChild("ModelIcon")) end)
	local tpl = ok and AssetFind.find(offer.model or offer.tool or "")
	if tpl and ok2 then
		local vp = ModelIcon.take(self.slot, tpl)   -- готовый кадр с полки (AssetPreload)
		if vp then
			vp.Size = UDim2.new(1, -16, 1, -16)
			vp.ZIndex = 3
		end
	end
end

function GiftCard:Set(offer, onClaim)
	self.title.Text = offer.name or ""
	self.desc.Text = offer.desc or offer.description or ""
	if self.shownId ~= offer.id then   -- модель не перерисовываем на каждом обновлении окна
		self.shownId = offer.id
		self:_icon(offer)
	end
	self.onClaim = onClaim
	self:SetClaimed(offer.claimed == true)
	self.wrap.Visible = true
	if not self.conn then
		local t0 = os.clock()
		self.conn = RunService.RenderStepped:Connect(function()
			self.rays.Rotation = ((os.clock() - t0) / 12 * 360) % 360   -- оборот за 12 с
		end)
	end
end

function GiftCard:SetClaimed(v)
	self.claimed = v
	self.btnLabel.Text = v and "Получено" or "Забрать бесплатно"
	self.btnLabel.TextColor3 = v and C.doneText or Color3.new(1, 1, 1)
	self.btnGrad.Color = v and ColorSequence.new(C.doneBg, C.doneBg) or ColorSequence.new(C.greenTop, C.greenBot)
	self.btnStroke.Color = v and C.doneBorder or C.greenBorder
	self.ring.Transparency = v and 1 or 0
end

function GiftCard:Hide()
	self.wrap.Visible = false
	if self.conn then self.conn:Disconnect(); self.conn = nil end
end

return GiftCard
