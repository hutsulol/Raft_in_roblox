--[[
	ТАБЛИЧКА «НАГРАДА С РЕЙДА» НАД ЛОДОЧНИКОМ — билдер по макету
	raft-reward-ads/design/mockups/01-AdBillboard.png (раздел 5.3 хендоффа).

	Слоты: 1–2 обычных → разделитель → 1–2 премиум (золотая рамка, корона).
	Кнопки: «Бесплатно / Обычные · N» и «R$ цена / Всё · N».
	Состояния: full (рядом), claimed (бесплатное забрано: галочки на обычных,
	«Снова через m:ss», «R$ цена / Премиум · N»), compact (далеко, пилюля).
	Крестик ✕ во всех состояниях. Все цвета и размеры — из Theme.

	API:
	  local bb = AdBillboard.new(playerGui)
	  bb.onFree, bb.onBuy, bb.onClose = function() end, …
	  bb:setAdornee(head)
	  bb:setOffer({ free, premium, claimed, freeEnabled, buyKind, price, busy }, iconOf)
	  bb:setCooldown(secondsLeft or nil) ; bb:setMode("full"|"compact")
	  bb:setVisible(bool, animated) ; bb:destroy()
]]
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.RewardAds.Theme)
local Icons = require(ReplicatedStorage.RewardAds.ResourceIcons)

local C = Theme.Color
local GREY = Color3.fromRGB(120, 124, 132)
local WHITE = Color3.new(1, 1, 1)
local FREE_SUB = Color3.fromHex("#d7f5de")
local GOLD_SHINE = Color3.fromHex("#ffe29a")
local GOLD_SUB = Color3.fromHex("#5a3d00")
local ROBUX = "R$" -- плашка как в макете (глиф 0xE002 есть не во всех шрифтах)
local SLOT = Theme.Chip.md
local W, H = 340, 250 -- макет в пикселях
-- ⚠️ SurfaceGui, А НЕ BillboardGui: табличка — вывеска в мире. Невидимая
-- локальная деталь STUDS_W × STUDS_H висит над головой лодочника и
-- поворачивается к камере только по горизонтали; холст фиксированный W×H
-- пикселей (SizingMode.FixedSize) — вёрстка не зависит от дистанции.
local STUDS_W = 7
local STUDS_H = STUDS_W * H / W
local LIFT = 1.0 -- низ холста над центром головы, studs

local AdBillboard = {}
AdBillboard.__index = AdBillboard

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	-- Global ordering: content must draw above its parent's background.
	if o:IsA("GuiObject") and props.ZIndex == nil and parent and parent:IsA("GuiObject") then
		o.ZIndex = parent.ZIndex + 1
	end
	if parent then o.Parent = parent end
	return o
end
local function corner(p, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, p) end
local function stroke(p, color, th, mode)
	return new("UIStroke", { Color = color, Thickness = th,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border }, p)
end
local function text(p, props, noStroke)
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or C.ink
	props.FontFace = props.FontFace or Theme.Font.Title
	local l = new("TextLabel", props, p)
	if not noStroke then stroke(l, C.outline, Theme.Stroke.outline, Enum.ApplyStrokeMode.Contextual) end
	return l
end
local function list(p, dir, pad, extra)
	local props = { FillDirection = dir, Padding = UDim.new(0, pad), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center }
	for k, v in pairs(extra or {}) do props[k] = v end
	return new("UIListLayout", props, p)
end
local function fmtAmount(n)
	if n >= 1000 then return (("+%.1fK"):format(n / 1000):gsub("%.0K", "K")) end
	return "+" .. tostring(n)
end

-- ячейка ресурса 5.1; premium — золотая рамка 3 + внешняя 2 outline, корона
local function slot(parent, order, premium)
	local f = new("Frame", { Size = UDim2.fromOffset(SLOT, SLOT), BackgroundColor3 = C["panel-raised"],
		LayoutOrder = order, Visible = false }, parent)
	corner(f, Theme.Radius.sm)
	if premium then
		stroke(f, C.reward, Theme.Stroke.trim)
		-- внешняя тёмная обводка сразу за золотой
		local ring = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 6, 1, 6) }, f)
		corner(ring, Theme.Radius.sm + 3)
		stroke(ring, C.outline, Theme.Stroke.outline)
		-- золотое свечение в центре (~25%)
		local mid = C["panel-raised"]:Lerp(C.reward, 0.25)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C["panel-raised"]), ColorSequenceKeypoint.new(0.5, mid),
			ColorSequenceKeypoint.new(1, C["panel-raised"]) }) }, f)
	else
		stroke(f, C.outline, Theme.Stroke.outline)
	end
	local icon = new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromScale(Theme.Chip.iconScale, Theme.Chip.iconScale),
		ScaleType = Enum.ScaleType.Fit }, f)
	local amt = text(f, { Name = "Amount", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -2, 1, 3),
		Size = UDim2.fromOffset(SLOT, 16), TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 15, TextColor3 = C.reward })
	local s = { frame = f, icon = icon, amount = amt }
	if premium then
		s.crown = new("ImageLabel", { BackgroundTransparency = 1, Image = Icons.crown, Size = UDim2.fromOffset(22, 22),
			Position = UDim2.fromOffset(-9, -11), Rotation = -14, ZIndex = f.ZIndex + 3 }, f)
	else
		s.check = new("ImageLabel", { BackgroundTransparency = 1, Image = Icons.check, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromOffset(30, 30), Visible = false, ZIndex = f.ZIndex + 3 }, f)
	end
	return s
end

-- кнопка 5.3: фон, верхний блик, обводка, тень 4px, нажатие — сдвиг вниз 2px
local function button(parent, order)
	local holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.5, -4, 0, 52), LayoutOrder = order }, parent)
	local shadow = new("Frame", { BackgroundColor3 = C.outline, BackgroundTransparency = 0.35,
		Size = UDim2.new(1, 0, 1, -4), Position = UDim2.fromOffset(0, 4) }, holder)
	corner(shadow, Theme.Radius.md)
	local b = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.watch,
		Size = UDim2.new(1, 0, 1, -4), ZIndex = shadow.ZIndex + 1 }, holder)
	corner(b, Theme.Radius.md)
	stroke(b, C.outline, Theme.Stroke.outline)
	local shine = new("Frame", { Name = "Shine", BackgroundColor3 = C["watch-light"], BorderSizePixel = 0,
		Size = UDim2.new(1, -12, 0, 3), Position = UDim2.fromOffset(6, 2) }, b)
	corner(shine, 2)
	local content = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, b)
	list(content, Enum.FillDirection.Vertical, 0)
	local down = function() b.Position = UDim2.fromOffset(0, 2) end
	local up = function() b.Position = UDim2.new() end
	b.MouseButton1Down:Connect(down)
	b.MouseButton1Up:Connect(up)
	b.MouseLeave:Connect(up)
	return { holder = holder, button = b, shine = shine, content = content }
end

function AdBillboard.new(playerGui)
	local self = setmetatable({}, AdBillboard)
	self.mode = "full"
	self.cooldown = nil
	self.offer = nil

	-- носитель: локальная невидимая деталь (у сервера её нет)
	local part = new("Part", { Name = "RewardAdBoard", Size = Vector3.new(STUDS_W, STUDS_H, 0.05), Transparency = 1,
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }, workspace)
	self.part = part
	-- ⚠️ SurfaceGui В PlayerGui С Adornee: иначе кнопки не кликаются
	local gui = new("SurfaceGui", { Name = "RewardAdBillboard", Adornee = part, Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize, CanvasSize = Vector2.new(W, H),
		LightInfluence = 0, AlwaysOnTop = true, MaxDistance = 60, Active = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Global, ResetOnSpawn = false, Enabled = false,
		ClipsDescendants = false }, playerGui)
	self.gui = gui
	local root = new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	self.root = root
	-- вывеска следует за головой и разворачивается к камере (только yaw)
	self.follow = RunService.RenderStepped:Connect(function()
		local head = self.head
		if not (gui.Enabled and head and head.Parent) then return end
		local cam = workspace.CurrentCamera
		local c = head.Position + Vector3.new(0, LIFT + STUDS_H / 2, 0)
		local d = cam.CFrame.Position - c
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude < 1e-3 then d = -cam.CFrame.LookVector * Vector3.new(1, 0, 1) end
		if d.Magnitude < 1e-3 then return end
		part.CFrame = CFrame.lookAt(c, c + d.Unit)
	end)
	-- ⚠️ ОБЫЧНЫЙ Frame, НЕ CanvasGroup: в BillboardGui групповая прозрачность работает не везде
	self.canvas = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, root)

	-- ── полная табличка ──
	local full = new("Frame", { Name = "Full", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(320, 0), AutomaticSize = Enum.AutomaticSize.Y }, self.canvas)
	self.full = full
	local shadow = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.7,
		Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, 4), ZIndex = 0 }, full)
	corner(shadow, Theme.Radius.lg)
	local outer = new("Frame", { BackgroundColor3 = C.outline, Size = UDim2.fromScale(1, 1), ZIndex = 1 }, full)
	corner(outer, Theme.Radius.lg)
	stroke(outer, C.outline, Theme.Stroke.outline)
	local panel = new("Frame", { Name = "Panel", BackgroundColor3 = C.panel, BackgroundTransparency = Theme.Transparency.panel,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 2 }, full)
	corner(panel, Theme.Radius.lg)
	stroke(panel, C.trim, Theme.Stroke.trim)
	new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, panel)
	list(panel, Enum.FillDirection.Vertical, 12, { VerticalAlignment = Enum.VerticalAlignment.Top })
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		outer.Size = UDim2.fromOffset(panel.AbsoluteSize.X, panel.AbsoluteSize.Y)
		shadow.Size = outer.Size
	end)

	-- шапка (справа 20px под ✕)
	local head = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 40), LayoutOrder = 1 }, panel)
	self.chestIcon = new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(40, 40), Image = Icons.chest,
		ScaleType = Enum.ScaleType.Fit }, head)
	text(head, { Position = UDim2.fromOffset(50, 1), Size = UDim2.new(1, -50, 0, 22), Text = "Награда с рейда",
		TextSize = 18, TextColor3 = C.reward, TextXAlignment = Enum.TextXAlignment.Left })
	text(head, { Position = UDim2.fromOffset(50, 23), Size = UDim2.new(1, -50, 0, 15), Text = "Лодочник привезёт ещё раз",
		TextSize = 12, FontFace = Theme.Font.Body, TextColor3 = C["ink-muted"], TextXAlignment = Enum.TextXAlignment.Left }, true)

	-- слоты (с запасом сверху под короны)
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, SLOT + 4), LayoutOrder = 2 }, panel)
	list(row, Enum.FillDirection.Horizontal, 8)
	self.freeSlots = { slot(row, 1, false), slot(row, 2, false) }
	self.divider = new("Frame", { BackgroundColor3 = C.trim, BackgroundTransparency = 0.55, BorderSizePixel = 0,
		Size = UDim2.fromOffset(2, SLOT - 12), LayoutOrder = 3 }, row)
	corner(self.divider, 2)
	self.premiumSlots = { slot(row, 4, true), slot(row, 5, true) }

	-- кнопки
	local btns = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 3 }, panel)
	list(btns, Enum.FillDirection.Horizontal, 8)
	-- левая: «Бесплатно» / «Снова через»
	local fb = button(btns, 1)
	self.freeBtn = fb
	self.freeTop = text(fb.content, { Size = UDim2.new(1, 0, 0, 20), Text = "Бесплатно", TextSize = 18, LayoutOrder = 1 })
	self.freeSub = text(fb.content, { Size = UDim2.new(1, 0, 0, 14), Text = "", TextSize = 12,
		FontFace = Theme.Font.Body, TextColor3 = FREE_SUB, LayoutOrder = 2 }, true)
	fb.button.Activated:Connect(function()
		if self._freeActive and self.onFree then self.onFree() end
	end)
	-- правая: «R$ 49»
	local bb = button(btns, 2)
	self.buyBtn = bb
	bb.button.BackgroundColor3 = C.reward
	bb.shine.BackgroundColor3 = GOLD_SHINE
	local priceRow = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1 }, bb.content)
	list(priceRow, Enum.FillDirection.Horizontal, 5)
	local badge = new("Frame", { BackgroundColor3 = C.outline, Size = UDim2.fromOffset(22, 18), LayoutOrder = 1 }, priceRow)
	corner(badge, 5)
	text(badge, { Size = UDim2.fromScale(1, 1), Text = ROBUX, TextSize = 11, TextColor3 = C.reward,
		FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold) }, true)
	self.price = text(priceRow, { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Text = "…",
		TextSize = 18, TextColor3 = C.outline, LayoutOrder = 2 }, true)
	self.buySub = text(bb.content, { Size = UDim2.new(1, 0, 0, 14), Text = "", TextSize = 12,
		FontFace = Theme.Font.Body, TextColor3 = GOLD_SUB, LayoutOrder = 2 }, true)
	bb.button.Activated:Connect(function()
		if self._buyActive and self.onBuy then self.onBuy() end
	end)

	-- хвостик
	local tail = new("Frame", { BackgroundColor3 = C.trim, Size = UDim2.fromOffset(14, 14), Rotation = 45,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 1), ZIndex = 1 }, full)
	stroke(tail, C.outline, Theme.Stroke.outline)

	-- ── пилюля (далеко) ──
	local pill = new("TextButton", { Name = "Compact", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(0, 48), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.panel, BackgroundTransparency = Theme.Transparency.panel, Visible = false }, self.canvas)
	corner(pill, 999)
	stroke(pill, C.trim, Theme.Stroke.trim)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 8) }, pill)
	list(pill, Enum.FillDirection.Horizontal, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Left })
	local chestCircle = new("Frame", { BackgroundColor3 = C["panel-raised"], Size = UDim2.fromOffset(36, 36), LayoutOrder = 1 }, pill)
	corner(chestCircle, 999)
	stroke(chestCircle, C.outline, Theme.Stroke.outline)
	new("ImageLabel", { BackgroundTransparency = 1, Image = Icons.chest, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24, 24) }, chestCircle)
	local pf = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2 }, pill)
	list(pf, Enum.FillDirection.Horizontal, -8)
	self.pillFree = {}
	for i = 1, 2 do
		self.pillFree[i] = new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(30, 30), LayoutOrder = i,
			ScaleType = Enum.ScaleType.Fit }, pf)
	end
	local cap = new("Frame", { BackgroundColor3 = C.reward, BackgroundTransparency = 0.85, Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 3 }, pill)
	corner(cap, 999)
	stroke(cap, C.reward, Theme.Stroke.outline)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, cap)
	list(cap, Enum.FillDirection.Horizontal, -6)
	self.pillCap = cap
	self.pillPremium = {}
	for i = 1, 2 do
		self.pillPremium[i] = new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(26, 26), LayoutOrder = i,
			ScaleType = Enum.ScaleType.Fit }, cap)
	end
	self.pill = pill
	-- нажатие на пилюлю ничего не покупает (5.3)

	-- ── крестики ✕: у полной таблички и у пилюли ──
	local function closeBtn(parent, size, off)
		local close = new("Frame", { Name = "Close", BackgroundColor3 = C["panel-raised"], AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, off, 0, -off), Size = UDim2.fromOffset(size, size), ZIndex = 20 }, parent)
		corner(close, 999)
		stroke(close, C.trim, Theme.Stroke.trim)
		local ring = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 6, 1, 6), ZIndex = 20 }, close)
		corner(ring, 999)
		stroke(ring, C.outline, Theme.Stroke.outline)
		new("ImageLabel", { BackgroundTransparency = 1, Image = Icons.close, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(math.floor(size * 0.56), math.floor(size * 0.56)),
			ZIndex = 21 }, close)
		-- невидимая зона нажатия 48×48 для пальца
		local hit = new("TextButton", { Text = "", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(48, 48), ZIndex = 22 }, close)
		hit.MouseEnter:Connect(function() close.BackgroundColor3 = C.lack end)
		hit.MouseLeave:Connect(function() close.BackgroundColor3 = C["panel-raised"] end)
		hit.Activated:Connect(function() if self.onClose then self.onClose() end end)
	end
	closeBtn(full, 32, -2)
	closeBtn(pill, 26, -2)

	-- покачивание ±4px, 2.4 с
	self.bob = TweenService:Create(root, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromOffset(0, -4) })
	return self
end

function AdBillboard:setAdornee(head) self.head = head end

local function paintSlot(s, r, iconOf, done)
	s.frame.Visible = r ~= nil
	if not r then return end
	s.icon.Image = iconOf(r.id)
	s.amount.Text = fmtAmount(r.amount)
	s.icon.ImageColor3 = done and GREY or WHITE
	s.icon.ImageTransparency = done and 0.65 or 0
	s.amount.TextColor3 = done and C["ink-muted"] or C.reward
	if s.check then s.check.Visible = done end
end

-- offer: { free, premium, claimed, freeEnabled, buyKind, price, busy }
function AdBillboard:setOffer(o, iconOf)
	self.offer = o
	self._iconOf = iconOf
	local free, premium = o.free or {}, o.premium or {}
	local done = self:_claimed()
	for i = 1, 2 do
		paintSlot(self.freeSlots[i], free[i], iconOf, done)
		paintSlot(self.premiumSlots[i], premium[i], iconOf, false)
		self.pillFree[i].Visible = free[i] ~= nil
		if free[i] then
			self.pillFree[i].Image = iconOf(free[i].id)
			self.pillFree[i].ImageColor3 = done and GREY or WHITE
		end
		self.pillPremium[i].Visible = premium[i] ~= nil
		if premium[i] then self.pillPremium[i].Image = iconOf(premium[i].id) end
	end
	self.divider.Visible = #free > 0 and #premium > 0
	self.pillCap.Visible = #premium > 0

	-- правая кнопка: есть премиум и продукт
	local buy = o.buyKind ~= nil
	self.buyBtn.holder.Visible = buy
	self.freeBtn.holder.Size = buy and UDim2.new(0.5, -4, 0, 52) or UDim2.new(1, 0, 0, 52)
	if buy then
		self.price.Text = o.price and tostring(o.price) or "…"
		if o.buyKind == "all" then
			self.buySub.Text = ("Всё · %d"):format(#free + #premium)
		else
			self.buySub.Text = ("Премиум · %d"):format(#premium)
		end
	end
	self._buyActive = buy and o.price ~= nil and not o.busy
	self.buyBtn.button.BackgroundTransparency = self._buyActive and 0 or 0.25
	self:_paintFree()
end

function AdBillboard:_claimed()
	local o = self.offer
	return o ~= nil and (o.claimed or self.cooldown ~= nil)
end

function AdBillboard:_paintFree()
	local o = self.offer
	if not o then return end
	local claimed = self:_claimed()
	local fb = self.freeBtn
	fb.button.BackgroundColor3 = claimed and C["panel-raised"] or C.watch
	fb.shine.Visible = not claimed
	if claimed then
		self.freeTop.Text = self.cooldown and "Снова через" or "Забрано"
		self.freeTop.TextSize = 14
		self.freeTop.TextColor3 = C["ink-muted"]
		self.freeTop.FontFace = Theme.Font.Body
		local cd = self.cooldown
		self.freeSub.Text = cd and ("%d:%02d"):format(math.floor(cd / 60), math.floor(cd % 60)) or ""
		self.freeSub.TextSize = 16
		self.freeSub.FontFace = Theme.Font.Title
		self.freeSub.TextColor3 = C.ink
		self._freeActive = false
	else
		self.freeTop.Text = "Бесплатно"
		self.freeTop.TextSize = 18
		self.freeTop.TextColor3 = C.ink
		self.freeTop.FontFace = Theme.Font.Title
		self.freeSub.Text = ("Обычные · %d"):format(#(o.free or {}))
		self.freeSub.TextSize = 12
		self.freeSub.FontFace = Theme.Font.Body
		self.freeSub.TextColor3 = FREE_SUB
		self._freeActive = o.freeEnabled == true and not o.busy
	end
	-- нет обычных вовсе (или бесплатное недоступно) — левая кнопка не нужна
	local showFree = #(o.free or {}) > 0 and (claimed or o.freeEnabled)
	fb.holder.Visible = showFree
	if not showFree then self.buyBtn.holder.Size = UDim2.new(1, 0, 0, 52)
	else self.buyBtn.holder.Size = UDim2.new(0.5, -4, 0, 52) end
end

function AdBillboard:setCooldown(secondsLeft)
	local v = (secondsLeft and secondsLeft > 0) and secondsLeft or nil
	if (v == nil) == (self.cooldown == nil) and (v == nil or math.floor(v) == math.floor(self.cooldown)) then return end
	local was = self:_claimed()
	self.cooldown = v
	if was ~= self:_claimed() and self.offer and self._iconOf then
		self:setOffer(self.offer, self._iconOf) -- галочки на слотах появились/ушли
	else
		self:_paintFree()
	end
end

function AdBillboard:setMode(mode)
	if self.mode == mode then return end
	self.mode = mode
	self.full.Visible = mode ~= "compact"
	self.pill.Visible = mode == "compact"
	if mode == "compact" then self.bob:Pause() elseif self.gui.Enabled and self.bobOn then self.bob:Play() end
end

function AdBillboard:setBob(on)
	self.bobOn = on
	if not on then self.bob:Pause() self.root.Position = UDim2.new() end
end

function AdBillboard:setVisible(on, animated)
	if on then
		if not self.gui.Enabled then
			self.gui.Enabled = true
			self.canvas.Size = UDim2.fromScale(1, 1)
			self.canvas.Position = UDim2.new()
			if self.bobOn and self.mode ~= "compact" then self.bob:Play() end
		end
	elseif self.gui.Enabled then
		self.bob:Pause()
		if animated then
			-- 0.18 с: вверх 8px, scale 0.9
			local t = TweenService:Create(self.canvas, TweenInfo.new(0.18), {
				Position = UDim2.new(0.05, 0, 0.05, -8), Size = UDim2.fromScale(0.9, 0.9) })
			t:Play()
			t.Completed:Once(function() self.gui.Enabled = false end)
		else
			self.gui.Enabled = false
		end
	end
end

function AdBillboard:destroy()
	if self.bob then self.bob:Cancel() end
	if self.follow then self.follow:Disconnect() end
	self.gui:Destroy()
	self.part:Destroy()
end

return AdBillboard
