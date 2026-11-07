local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	МАГАЗИН СТРАНСТВУЮЩЕГО ТОРГОВЦА — окно (хендофф design_handoff_roblox_ocean_ui,
	«Магазин торговца.dc.html», тема «Океан»).

	⚠️ РАЗМЕР И КРЕСТИК — КАК У ИНВЕНТАРЯ. Блок «панель торговца слева + панель
	предложений справа» повторяет блок «крафт 180 + зазор 12 + окно 582×440»
	из InventoryUI, красный ✕ 30×30 — в том же углу (1,−36, 0,8) той же панели.
	Открыл одно, закрыл, открыл другое — окно на том же месте и того же размера.

	⚠️ АДАПТАЦИЯ: весь блок лежит в одном контейнере с UIScale — на низком экране
	(телефон) он ужимается целиком, чтобы влезть по высоте и ширине, и
	пересчитывается при повороте. Больше 1 не растёт.

	Сервер — MerchantShop.server (цены, остатки, «торговец ещё здесь»).
	Закрытие: ✕, Esc / B, клик мимо окна, уход торговца.
]]
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shopFn    = ReplicatedStorage:WaitForChild("MerchantShop")
local shopEvt   = ReplicatedStorage:WaitForChild("MerchantEvent")

-- ═══════════ стиль «Океан» (README хендоффа) ═══════════
local C = {
	top = Color3.fromHex("54A7EC"), bottom = Color3.fromHex("3A7FD0"), border = Color3.fromHex("1C4F8F"),
	tab = Color3.fromHex("2E6BB4"), tabText = Color3.fromHex("CFE6FA"), row = Color3.fromHex("6FB5EE"),
	slot = Color3.fromHex("A9D6F7"), slot2 = Color3.fromHex("8FC3EC"), light = Color3.fromHex("A9D6F7"),
	gold1 = Color3.fromHex("FFD95A"), gold2 = Color3.fromHex("F5B73C"), goldEdge = Color3.fromHex("B07A14"),
	feat1 = Color3.fromHex("FFE38A"), feat2 = Color3.fromHex("F7C24E"), featText = Color3.fromHex("7A4F06"),
	green1 = Color3.fromHex("5EE07A"), green2 = Color3.fromHex("34B84E"), greenEdge = Color3.fromHex("1F7A33"),
	off = Color3.fromHex("8AA6C2"), offEdge = Color3.fromHex("5D7D9E"), offText = Color3.fromHex("E3EDF6"),
	offGold = Color3.fromHex("C9A45A"), offGoldEdge = Color3.fromHex("9A7A32"), offGoldText = Color3.fromHex("FFF6DC"),
	red = Color3.fromHex("FF6B5A"), redEdge = Color3.fromHex("8A2A12"), badge = Color3.fromHex("E84A3A"), badgeEdge = Color3.fromHex("A82E2E"),
	price = Color3.fromHex("FFD95A"), white = Color3.new(1, 1, 1),
}
local RARITY = {
	common   = { ru = "Обычный",   frame = Color3.fromHex("E3EBF3"), badge = Color3.fromHex("7B8A99") },
	uncommon = { ru = "Необычный", frame = Color3.fromHex("5FE07A"), badge = Color3.fromHex("34B84E") },
	rare     = { ru = "Редкий",    frame = Color3.fromHex("54A7EC"), badge = Color3.fromHex("1C4F8F") },
	epic     = { ru = "Эпик",      frame = Color3.fromHex("B07EF0"), badge = Color3.fromHex("9B5FE0") },
	legend   = { ru = "Легенда",   frame = Color3.fromHex("F5A93C"), badge = Color3.fromHex("E8902A") },
}
local CHEST_ICON = "rbxassetid://79673240977178"
local COIN_ICON  = "rbxassetid://93617165412571"
local FONT = Enum.Font.GothamBlack
local FONT_B = Enum.Font.GothamBold

-- геометрия инвентаря (InventoryUI.buildUI): 5×(80+8)+8 = 448, +40+14+80 = 582; 4×88+8+80 = 440
local SIDE_W, GAP, MAIN_W, H = 180, 12, 582, 440
local TOTAL_W = SIDE_W + GAP + MAIN_W

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(p, r) return new("UICorner", { CornerRadius = r and UDim.new(0, r) or UDim.new(0.5, 0) }, p) end
local function stroke(p, color, th, contextual)
	return new("UIStroke", { Color = color, Thickness = th,
		ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border }, p)
end
local function grad(p, a, b) return new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = 90 }, p) end
local function label(p, props)
	props.BackgroundTransparency = 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or C.white
	local l = new("TextLabel", props, p)
	if props.TextColor3 == C.white then
		new("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.7, Thickness = 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	end
	return l
end
local function fmtTime(sec)
	sec = math.max(0, math.floor(sec))
	return ("%d:%02d"):format(sec // 60, sec % 60)
end

-- ═══════════ каркас ═══════════
local gui = new("ScreenGui", { Name = "MerchantShopGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 10, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
gui:SetAttribute("ModalUI", true)   -- ModalUIUnlocker отпускает курсор

local backdrop = new("TextButton", { Name = "Backdrop", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(4, 4), BackgroundTransparency = 1,
	Text = "", AutoButtonColor = false, ZIndex = 0 }, gui)

-- контейнер-кнопка: клики по окну не проходят к подложке (иначе закрылось бы)
local root = new("ImageButton", { Name = "Root", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(TOTAL_W, H),
	BackgroundTransparency = 1, AutoButtonColor = false, Image = "" }, gui)
local rootScale = new("UIScale", {}, root)

local function fitScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	return math.clamp(math.min((vp.Y - 24) / H, (vp.X - 24) / TOTAL_W), 0.3, 1)
end

-- ── левая панель: торговец ──
local side = new("Frame", { Name = "Merchant", Size = UDim2.fromOffset(SIDE_W, H), BackgroundColor3 = C.white,
	BorderSizePixel = 0 }, root)
grad(side, C.top, C.bottom); corner(side, 18); stroke(side, C.border, 4)
new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, side)
new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center }, side)
label(side, { Size = UDim2.new(1, 0, 0, 26), Text = "Торговец", TextSize = 19, LayoutOrder = 1 })
local portrait = new("Frame", { Size = UDim2.new(1, 0, 0, 110), BackgroundColor3 = C.slot, LayoutOrder = 2 }, side)
corner(portrait, 14); stroke(portrait, C.border, 3)
-- ⚠️ ЗАГЛУШКА ПОРТРЕТА: модели торговца в игре пока нет (в хендоффе — плейсхолдер)
new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(84, 84), BackgroundTransparency = 1, Image = CHEST_ICON, ScaleType = Enum.ScaleType.Fit }, portrait)

local timerBox = new("Frame", { Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = C.border, LayoutOrder = 3 }, side)
corner(timerBox, 12)
label(timerBox, { Position = UDim2.fromOffset(0, 7), Size = UDim2.new(1, 0, 0, 14), Text = "УПЛЫВЁТ ЧЕРЕЗ",
	TextSize = 12, TextColor3 = C.light })
local timerText = label(timerBox, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 28),
	Text = "5:00", TextSize = 24, TextColor3 = C.price })

local TABS = { { key = "all", ru = "Все" }, { key = "tools", ru = "Инструменты" }, { key = "res", ru = "Ресурсы" }, { key = "rare", ru = "Редкое" } }
local activeTab = "all"
local tabButtons = {}

-- ── правая панель: предложения ──
local main = new("Frame", { Name = "Offers", Position = UDim2.fromOffset(SIDE_W + GAP, 0),
	Size = UDim2.fromOffset(MAIN_W, H), BackgroundColor3 = C.white, BorderSizePixel = 0 }, root)
grad(main, C.top, C.bottom); corner(main, 18); stroke(main, C.border, 4)
-- заголовок — как «Инвентарь» (14, 8, кегль 22)
label(main, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -200, 0, 30), Text = "Предложения",
	TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })

-- баланс — пилюля левее крестика
local balance = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -46, 0, 10),
	Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.tab }, main)
corner(balance); stroke(balance, C.border, 2)
new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 10) }, balance)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5),
	VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, balance)
new("ImageLabel", { Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, Image = COIN_ICON, LayoutOrder = 1 }, balance)
local balanceText = label(balance, { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X,
	Text = "0", TextSize = 14, LayoutOrder = 2 })

-- ✕ — ровно как у инвентаря (InventoryUI: 30×30, (1,−36, 0,8), FF6B5A, обводка 8A2A12)
local closeBtn = new("TextButton", { Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -36, 0, 8),
	BackgroundColor3 = C.red, Text = "", BorderSizePixel = 0, AutoButtonColor = true }, main)
corner(closeBtn, 10); stroke(closeBtn, C.redEdge, 3)
for _, rot in ipairs({ 45, -45 }) do
	local bar = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 4), BackgroundColor3 = C.white, BorderSizePixel = 0, Rotation = rot }, closeBtn)
	corner(bar)
end

local list = new("ScrollingFrame", { Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -24, 1, -56),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollBarImageColor3 = C.border,
	AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y }, main)
new("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 6),
	PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 10) }, list)
new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)

--[[ РЕЖИМ «ТОЛЬКО ПОДАРОК» (хендофф design_handoff_merchant_gift). Если у
     торговца ровно одно предложение и это бесплатный подарок (isGift, цена 0) —
     вместо строки «Купить · 0» вся панель занята карточкой GiftCard, а в
     сайдбаре одна золотая вкладка «Подарок». ]]
local GiftCard = require(ReplicatedStorage:WaitForChild("GiftCard"))
local giftHost = new("Frame", { Name = "GiftHost", Position = UDim2.fromOffset(12, 62), Size = UDim2.new(1, -24, 1, -74),
	BackgroundTransparency = 1 }, main)
local giftCard = GiftCard.new(giftHost)
-- ⚠️ золото — на подложке: UIGradient красит и текст своего объекта, и белое
-- «Подарок» на золотой кнопке становилось золотым — вкладка выглядела пустой
local giftTab = new("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = C.white, LayoutOrder = 4, Visible = false }, side)
corner(giftTab, 12); stroke(giftTab, C.goldEdge, 3); grad(giftTab, C.gold1, C.gold2)
label(new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, giftTab),
	{ Size = UDim2.fromScale(1, 1), Text = "Подарок", TextSize = 16 })

local function giftOnly(st)
	local offers = st and st.offers or {}
	return #offers == 1 and offers[1].isGift == true and (offers[1].price or 0) == 0
end

-- ═══════════ состояние ═══════════
local data = nil         -- последнее состояние с сервера
local isOpen = false
local buying = false

local function coins() return player:GetAttribute("Pirate") or 0 end

local function iconInto(slot, offer)
	local img = ""
	if offer.icon == "chest" then img = CHEST_ICON
	elseif offer.item and typeof(_G.GetItemIcon) == "function" then img = _G.GetItemIcon(offer.item) or "" end
	if img ~= "" then
		new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.78), BackgroundTransparency = 1, Image = img, ScaleType = Enum.ScaleType.Fit }, slot)
		return
	end
	-- инструмент или предмет без картинки — рисуем саму модель
	local ok, AssetFind = pcall(function() return require(ReplicatedStorage:WaitForChild("AssetFind")) end)
	local ok2, ModelIcon = pcall(function() return require(ReplicatedStorage:WaitForChild("ModelIcon")) end)
	local tpl = ok and AssetFind.find(offer.model or offer.tool or offer.item or "")
	if tpl and ok2 then
		local vp = ModelIcon.take(slot, tpl)   -- готовый кадр с полки (прогрет AssetPreload)
		if vp then vp.Size = UDim2.fromScale(0.85, 0.85) end
	end
end

local function buyButton(parent, offer, featured)
	local resOk = offer.resOk ~= false
	local canBuy = offer.left > 0 and coins() >= offer.price and resOk
	local text = offer.left <= 0 and "Продано" or ((coins() < offer.price or not resOk) and "Мало" or "Купить")
	local b = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(featured and 104 or 96, featured and 44 or 40), Text = "", AutoButtonColor = false,
		BackgroundColor3 = C.white }, parent)
	corner(b, 12)
	if canBuy then
		grad(b, C.green1, C.green2); stroke(b, C.greenEdge, 3)
	else
		b.BackgroundColor3 = featured and C.offGold or C.off
		stroke(b, featured and C.offGoldEdge or C.offEdge, 3)
	end
	-- «3D»: тёмная полоска у низа
	local shade = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.82, BorderSizePixel = 0 }, b)
	corner(shade, 12)
	local t = label(b, { Size = UDim2.fromScale(1, 1), Text = text, TextSize = featured and 16 or 15,
		TextColor3 = canBuy and C.white or (featured and C.offGoldText or C.offText) })
	if canBuy then
		b.MouseButton1Down:Connect(function() t.Position = UDim2.fromOffset(0, 2) end)
		b.MouseButton1Up:Connect(function() t.Position = UDim2.new() end)
		b.MouseLeave:Connect(function() t.Position = UDim2.new() end)
		b.Activated:Connect(function()
			if buying then return end
			buying = true
			local ok, res = pcall(function() return shopFn:InvokeServer("buy", offer.id) end)
			buying = false
			if ok and type(res) == "table" then
				if res.state then data = res.state end
				if not res.ok and typeof(_G.NotifyLocal) == "function" then pcall(_G.NotifyLocal, res.why) end
			end
			if isOpen then task.defer(function() _G.MerchantShopRefresh() end) end
		end)
	end
end

local function pricePill(parent, price, order)
	local pill = new("Frame", { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.tab, LayoutOrder = order }, parent)
	corner(pill); stroke(pill, C.border, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 8) }, pill)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, pill)
	new("ImageLabel", { Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = COIN_ICON, LayoutOrder = 1 }, pill)
	label(pill, { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, Text = tostring(price),
		TextSize = 13, TextColor3 = C.price, LayoutOrder = 2 })
end

-- цена ресурсами (пак фермера): иконка ресурса + число, красное — если не хватает
local function costPills(parent, offer, order)
	for i, c in ipairs(offer.costs or {}) do
		local pill = new("Frame", { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.tab, LayoutOrder = order + i }, parent)
		corner(pill); stroke(pill, C.border, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 8) }, pill)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
			VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, pill)
		local img = typeof(_G.GetItemIcon) == "function" and _G.GetItemIcon(c.id) or ""
		new("ImageLabel", { Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = img or "", LayoutOrder = 1 }, pill)
		label(pill, { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, Text = tostring(c.n),
			TextSize = 13, TextColor3 = offer.resOk == false and Color3.fromRGB(255, 120, 110) or C.price, LayoutOrder = 2 })
	end
end

local function featuredCard(offer, order)
	local card = new("Frame", { Size = UDim2.new(1, 0, 0, 100), BackgroundColor3 = C.white, LayoutOrder = order }, list)
	grad(card, C.feat1, C.feat2); corner(card, 16); stroke(card, C.goldEdge, 4)
	-- бейдж «ОСОБОЕ −N%» на верхней кромке
	if offer.oldPrice and offer.oldPrice > offer.price then
		local pct = math.floor((1 - offer.price / offer.oldPrice) * 100 + 0.5)
		local badge = new("Frame", { Position = UDim2.fromOffset(14, -13), Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.badge, ZIndex = 3 }, card)
		corner(badge); stroke(badge, C.badgeEdge, 3)
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, badge)
		label(badge, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
			Text = ("ОСОБОЕ −%d%%"):format(pct), TextSize = 12, ZIndex = 4 })
	end
	local icon = new("Frame", { Position = UDim2.fromOffset(14, 12), Size = UDim2.fromOffset(76, 76),
		BackgroundColor3 = Color3.fromHex("FFF3C9") }, card)
	corner(icon, 14); stroke(icon, C.goldEdge, 3)
	iconInto(icon, offer)
	local nameL = label(card, { Position = UDim2.fromOffset(102, 12), Size = UDim2.new(1, -230, 0, 24), Text = offer.name,
		TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left })
	nameL:FindFirstChildOfClass("UIStroke").Color = Color3.fromRGB(120, 70, 0)
	-- у пака фермера описание длинное — в две строки, мельче; у сундука — одной строкой
	local wrap = offer.showcase == true
	label(card, { Position = UDim2.fromOffset(102, 36), Size = UDim2.new(1, -230, 0, wrap and 28 or 18), Text = offer.desc or "",
		TextSize = wrap and 12 or 13, Font = FONT_B, TextColor3 = C.featText, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = wrap,
		TextTruncate = wrap and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd })
	local rowP = new("Frame", { Position = UDim2.fromOffset(102, wrap and 66 or 60), Size = UDim2.new(1, -230, 0, 24), BackgroundTransparency = 1 }, card)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, rowP)
	if offer.oldPrice then
		label(rowP, { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, RichText = true,
			Text = ("<s>%d</s>"):format(offer.oldPrice), TextSize = 14, TextColor3 = Color3.fromHex("9A6A1A"), LayoutOrder = 1 })
	end
	new("ImageLabel", { Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, Image = COIN_ICON, LayoutOrder = 2 }, rowP)
	label(rowP, { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Text = tostring(offer.price),
		TextSize = 18, LayoutOrder = 3 })
	label(rowP, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X,
		Text = "· осталось " .. offer.left, TextSize = 12, Font = FONT_B, TextColor3 = C.featText, LayoutOrder = 10 })
	costPills(rowP, offer, 3)   -- цена ресурсами (пак фермера)
	buyButton(card, offer, true)
end

local function offerRow(offer, order)
	local r = RARITY[offer.rarity] or RARITY.common
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 76), BackgroundColor3 = C.row, LayoutOrder = order }, list)
	corner(row, 14); stroke(row, C.tab, 3)
	local icon = new("Frame", { Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = C.white }, row)
	grad(icon, C.slot, C.slot2); corner(icon, 12); stroke(icon, r.frame, 3)
	iconInto(icon, offer)
	local top = new("Frame", { Position = UDim2.fromOffset(80, 12), Size = UDim2.new(1, -200, 0, 24), BackgroundTransparency = 1 }, row)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, top)
	label(top, { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Text = offer.name,
		TextSize = 17, LayoutOrder = 1 })
	local rb = new("Frame", { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = r.badge, LayoutOrder = 2 }, top)
	corner(rb)
	new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, rb)
	label(rb, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Text = r.ru, TextSize = 11 })
	local bottom = new("Frame", { Position = UDim2.fromOffset(80, 42), Size = UDim2.new(1, -200, 0, 24), BackgroundTransparency = 1 }, row)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, bottom)
	pricePill(bottom, offer.price, 1)
	costPills(bottom, offer, 1)
	label(bottom, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X,
		Text = "осталось " .. offer.left, TextSize = 12, Font = FONT_B, TextColor3 = C.border, LayoutOrder = 10 })
	buyButton(row, offer, false)
end

local function paintTabs()
	for key, b in pairs(tabButtons) do
		local active = key == activeTab
		local st = b:FindFirstChildOfClass("UIStroke")
		local g = b:FindFirstChildOfClass("UIGradient")
		if active then
			-- сплошное золото, без UIGradient: градиент красит и текст кнопки —
			-- белое «Все» становилось золотым на золотом, вкладка казалась пустой
			if g then g:Destroy() end
			b.BackgroundColor3 = C.gold2
			st.Color = C.goldEdge
			b.TextColor3 = C.white
		else
			if g then g:Destroy() end
			b.BackgroundColor3 = C.tab
			st.Color = C.border
			b.TextColor3 = C.tabText
		end
	end
end

local function render()
	pcall(function() require(ReplicatedStorage:WaitForChild("ModelIcon")).reclaim(list) end)   -- кадры моделей — на полку
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	balanceText.Text = tostring(coins())
	if not data then return end
	local gift = giftOnly(data)
	list.Visible = not gift
	giftTab.Visible = gift
	for _, b in pairs(tabButtons) do b.Visible = not gift end
	if gift then
		local o = data.offers[1]
		giftCard:Set({ id = o.id, name = o.name, desc = o.desc, image = o.image, model = o.model, tool = o.tool,
			claimed = (o.left or 0) <= 0 }, function()
			if buying then return end
			buying = true
			local ok, res = pcall(function() return shopFn:InvokeServer("buy", o.id) end)
			buying = false
			if ok and type(res) == "table" then
				if res.state then data = res.state end
				if res.ok then
					giftCard:SetClaimed(true)
				elseif typeof(_G.NotifyLocal) == "function" then
					pcall(_G.NotifyLocal, res.why)
				end
			end
			if isOpen then task.defer(function() _G.MerchantShopRefresh() end) end
		end)
		return
	end
	giftCard:Hide()
	local order = 0
	for _, o in ipairs(data.offers or {}) do
		local show = activeTab == "all" or o.category == activeTab
		if o.featured or o.showcase then show = activeTab == "all" or activeTab == "rare" end
		if show then
			order += 1
			if o.featured or o.showcase then featuredCard(o, order) else offerRow(o, order) end
		end
	end
	if order == 0 then
		label(list, { Size = UDim2.new(1, 0, 0, 40), Text = data.present and "В этой вкладке пусто" or "Торговца сейчас нет",
			TextSize = 16, TextColor3 = C.tabText, LayoutOrder = 1 })
	end
	paintTabs()
end
_G.MerchantShopRefresh = function() render() end

for i, t in ipairs(TABS) do
	local b = new("TextButton", { Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = C.tab, Text = t.ru,
		Font = FONT, TextSize = 16, TextColor3 = C.tabText, AutoButtonColor = true, LayoutOrder = 3 + i }, side)
	corner(b, 12); stroke(b, C.border, 3)
	tabButtons[t.key] = b
	b.Activated:Connect(function() activeTab = t.key; render() end)
end

-- ═══════════ открыть / закрыть ═══════════
local function close()
	if not isOpen then return end
	isOpen = false
	gui.Enabled = false
end

local function open()
	local ok, st = pcall(function() return shopFn:InvokeServer("state") end)
	if not ok or type(st) ~= "table" then warn("[Торговец] сервер не ответил") return end
	data = st
	-- другие окна на этом месте закрываем
	if typeof(_G.CloseInventory) == "function" then pcall(_G.CloseInventory) end
	activeTab = "all"
	isOpen = true
	gui.Enabled = true
	render()
	local s = fitScale()
	rootScale.Scale = s * 0.9
	TweenService:Create(rootScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = s }):Play()
end
_G.OpenMerchantShop = open
_G.CloseMerchantShop = close
_G.IsMerchantShopOpen = function() return isOpen end

closeBtn.MouseButton1Click:Connect(close)
backdrop.Activated:Connect(close)
UserInputService.InputBegan:Connect(function(input, processed)
	if not isOpen then return end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then close() end
end)
local cam = workspace.CurrentCamera
if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() if isOpen then rootScale.Scale = fitScale() end end) end
player:GetAttributeChangedSignal("Pirate"):Connect(function() if isOpen and not buying then render() end end)

-- таймер
task.spawn(function()
	while true do
		task.wait(0.25)
		if isOpen and data then
			local left = (data.departAt or 0) - workspace:GetServerTimeNow()
			timerText.Text = data.present and fmtTime(left) or "—"
			if data.present and left <= 0 then close() end
		end
	end
end)

-- ═══════════ баннер «Торговец приплыл!» ═══════════
local bannerGui = new("ScreenGui", { Name = "MerchantBanner", ResetOnSpawn = false, DisplayOrder = 20, Enabled = true }, playerGui)
local banner = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -120),
	Size = UDim2.fromOffset(0, 78), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.white, Visible = false }, bannerGui)
grad(banner, C.top, C.bottom); corner(banner, 18); stroke(banner, C.border, 4)
new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 22) }, banner)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14),
	VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, banner)
local bp = new("Frame", { Size = UDim2.fromOffset(58, 58), BackgroundColor3 = C.slot, LayoutOrder = 1 }, banner)
corner(bp); stroke(bp, C.border, 3)
new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(40, 40),
	BackgroundTransparency = 1, Image = CHEST_ICON }, bp)
local btxt = new("Frame", { Size = UDim2.fromOffset(0, 50), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = 2 }, banner)
new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, btxt)
label(btxt, { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, Text = "Торговец приплыл!", TextSize = 21, LayoutOrder = 1 })
local bsub = label(btxt, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, RichText = true,
	Text = "", TextSize = 14, Font = FONT_B, TextColor3 = C.tabText, LayoutOrder = 2 })

local function showBanner(departAt)
	bsub.Text = ('Уникальные товары · уплывёт через <font color="#FFD95A">%s</font>'):format(fmtTime(departAt - workspace:GetServerTimeNow()))
	banner.Visible = true
	banner.Position = UDim2.new(0.5, 0, 0, -120)
	TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 24) }):Play()
	task.delay(4, function()
		local t = TweenService:Create(banner, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -120) })
		t:Play()
		t.Completed:Once(function() banner.Visible = false end)
	end)
end

shopEvt.OnClientEvent:Connect(function(kind, arg)
	if kind == "arrive" then
		showBanner(arg)
		if isOpen then open() end
	elseif kind == "leave" then
		if data then data.present = false end
		close()
	elseif kind == "open" then
		open()
	end
end)

print("[Торговец/клиент] окно магазина готово")
