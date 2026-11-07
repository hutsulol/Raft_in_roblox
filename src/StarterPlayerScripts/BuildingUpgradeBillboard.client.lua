--[[
	ТАБЛИЧКА УЛУЧШЕНИЯ над постройкой плота (хендофф design_handoff_building_upgrade,
	тема «Океан»): золотая плашка с названием → стеклянная табличка «УР N», «×2» и
	кнопка «молоток + цена». Нажатие сразу покупает следующий уровень, отдельного
	окна нет. Во время сборки вместо кнопки — полоса прогресса, на максимуме кнопки
	нет, а значок уровня золотой.

	Постройки — по тегу BuildingLevels.TAG (ставит BuildingUpgradeServer).
	Баланс — атрибут игрока Pirate. Покупку проверяет и списывает сервер.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local L = require(ReplicatedStorage:WaitForChild("BuildingLevels"))
local remote = ReplicatedStorage:WaitForChild("UpgradeBuilding")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HAMMER_ICON = "rbxassetid://86264127232874"   -- молоток инвентаря
local COIN_ICON = "rbxassetid://75648362153758"     -- монета pirate

local C = {
	outline = Color3.fromHex("0D2A4F"), glassTop = Color3.fromHex("1F4F8F"), glassBot = Color3.fromHex("143A6B"), glassStroke = Color3.fromHex("A9D6F7"),
	blueTop = Color3.fromHex("54A7EC"), blueBot = Color3.fromHex("3A7FD0"), blueBorder = Color3.fromHex("1C4F8F"), blueFlat = Color3.fromHex("2E6BB4"),
	greenTop = Color3.fromHex("6FF08A"), greenBot = Color3.fromHex("34B84E"), greenBorder = Color3.fromHex("1F7A33"),
	goldTop = Color3.fromHex("FFE38A"), goldBot = Color3.fromHex("F5B73C"), goldBorder = Color3.fromHex("B07A14"),
	gold = Color3.fromHex("FFD95A"), red = Color3.fromHex("FF8A7E"), badge = Color3.fromHex("E84A3A"), track = Color3.fromHex("143A6B"),
}
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)

local function new(class, props, parent) local i = Instance.new(class); for k, v in pairs(props) do i[k] = v end; i.Parent = parent; return i end
local function corner(p, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, p) end
local function border(p, color, t) return new("UIStroke", { Color = color, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p) end
local function grad(p, a, b) return new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = 90 }, p) end
local function text(p, size, color, strokeT, order)
	local t = new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextSize = size, TextColor3 = color,
		AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), LayoutOrder = order or 0 }, p)
	if strokeT then new("UIStroke", { Color = C.outline, Thickness = strokeT, LineJoinMode = Enum.LineJoinMode.Round }, t) end
	return t
end
local function hlist(p, pad) return new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, pad), SortOrder = Enum.SortOrder.LayoutOrder }, p) end

local CANVAS = Vector2.new(260, 100)   -- холст вёрстки, px (размеры хендоффа)
local PLATE_W = 224                    -- ширина стеклянной таблички, px (как с кнопкой «1 500»)
local STUDS_PER_PX = 0.03              -- 260 px → 7,8 студа в мире

local function pirate() return tonumber(player:GetAttribute("Pirate")) or 0 end

-- высота над точкой посадки: верх самой высокой детали всех уровней
local function heightAbove(model, anchor)
	local top = 6
	for _, p in ipairs(L.pieces(model)) do
		local rel = anchor.CFrame:PointToObjectSpace(p.Position)
		top = math.max(top, rel.Y + p.Size.Y * 0.5)
	end
	return top
end

local function build(model)
	-- модель могла приехать раньше своих деталей: точку посадки ждём
	local anchor = model.PrimaryPart or model:WaitForChild("AssemblyOrigin", 10) or model:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then
		warn("[Улучшение/клиент] нет точки посадки у " .. model:GetFullName() .. " — табличку не повесить")
		return
	end
	print(("[Улучшение/клиент] табличка над %s (уровень %s)"):format(model:GetFullName(), tostring(model:GetAttribute("Level"))))

	--[[ ⚠️ РАЗМЕР В СТУДАХ, А НЕ В ПИКСЕЛЯХ: табличка — вещь в мире, издалека
	     мельче, вблизи крупнее, и не «плавает» по размеру вместе с камерой.
	     Вёрстка — в пикселях холста CANVAS, холст подгоняется под билборд UIScale.
	     Active = true — иначе кнопки внутри BillboardGui не получают клики. ]]
	local uiScale = (L.KINDS[model.Name] and L.KINDS[model.Name].uiScale) or 1   -- таверна большая — табличка крупнее
	-- не поверх всего: через стены (сидишь в таверне, хижине) табличка не видна
	local bb = new("BillboardGui", { Name = "UpgradeBillboard", Adornee = anchor, AlwaysOnTop = false, LightInfluence = 0,
		Active = true, Size = UDim2.fromScale(CANVAS.X * STUDS_PER_PX * uiScale, CANVAS.Y * STUDS_PER_PX * uiScale),
		StudsOffsetWorldSpace = Vector3.new(0, heightAbove(model, anchor) + 2.5, 0),
		MaxDistance = 120, ResetOnSpawn = false }, playerGui)

	local canvas = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y) }, bb)
	local fit = new("UIScale", {}, canvas)
	local col = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, canvas)
	new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, -9), SortOrder = Enum.SortOrder.LayoutOrder }, col)

	-- название: золотая плашка, наклон −2°
	local nameTag = new("Frame", { AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), Rotation = -2, LayoutOrder = 1, ZIndex = 3, BackgroundColor3 = Color3.new(1, 1, 1) }, col)
	corner(nameTag, 12); border(nameTag, C.outline, 3); grad(nameTag, C.goldTop, C.goldBot)
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 5) }, nameTag)
	local nameLabel = text(nameTag, 17, Color3.new(1, 1, 1), 2.5); nameLabel.ZIndex = 3

	-- стеклянная табличка
	-- ширина постоянная: без кнопки (максимум) табличка не сжимается, уровень и множитель растягиваются
	local plate = new("Frame", { AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromOffset(PLATE_W, 0), LayoutOrder = 2, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.15 }, col)
	corner(plate, 16); grad(plate, C.glassTop, C.glassBot)
	new("UIStroke", { Color = C.glassStroke, Thickness = 3, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, plate)
	new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }, plate)
	local plateList = hlist(plate, 6)
	plateList.HorizontalAlignment = Enum.HorizontalAlignment.Center

	-- уровень
	local lvlBox = new("Frame", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(40, 40), LayoutOrder = 1, BackgroundColor3 = Color3.new(1, 1, 1) }, plate)
	corner(lvlBox, 11); local lvlStroke = border(lvlBox, C.blueBorder, 3); local lvlGrad = grad(lvlBox, C.blueTop, C.blueBot)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, lvlBox)
	hlist(lvlBox, 3).HorizontalAlignment = Enum.HorizontalAlignment.Center
	local lvlCap = text(lvlBox, 10, Color3.fromHex("CFE6FA"), nil, 1); lvlCap.Text = "УР"
	local lvlNum = text(lvlBox, 20, Color3.new(1, 1, 1), 1.5, 2)

	-- множитель прибыли
	local mult = text(plate, 24, C.gold, 3, 2)

	-- кнопка: молоток + монета + цена
	local btn = new("TextButton", { Text = "", AutoButtonColor = false, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), LayoutOrder = 3, BackgroundColor3 = Color3.new(1, 1, 1) }, plate)
	corner(btn, 11); local btnStroke = border(btn, C.greenBorder, 3); local btnGrad = grad(btn, C.greenTop, C.greenBot)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 10) }, btn); hlist(btn, 6)
	new("ImageLabel", { BackgroundTransparency = 1, Image = HAMMER_ICON, Size = UDim2.fromOffset(24, 24), LayoutOrder = 1, ScaleType = Enum.ScaleType.Fit }, btn)
	new("ImageLabel", { BackgroundTransparency = 1, Image = COIN_ICON, Size = UDim2.fromOffset(15, 15), LayoutOrder = 2, ScaleType = Enum.ScaleType.Fit }, btn)
	local cost = text(btn, 15, Color3.new(1, 1, 1), 1.5, 3)
	local bang = new("TextLabel", { Text = "!", FontFace = FONT, TextSize = 10, TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = C.badge,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(16, 16), ZIndex = 4 }, btn)
	corner(bang, 8); border(bang, Color3.new(1, 1, 1), 2)

	-- прогресс сборки
	local prog = new("Frame", { Size = UDim2.fromOffset(96, 40), LayoutOrder = 3, BackgroundColor3 = C.track, ClipsDescendants = true, Visible = false }, plate)
	corner(prog, 11); border(prog, C.outline, 3)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, prog); grad(fill, C.goldTop, C.goldBot)
	local pct = new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), ZIndex = 2 }, prog)
	new("UIStroke", { Color = C.outline, Thickness = 2 }, pct)

	-- указатель вниз: повёрнутый квадрат цвета низа таблички
	--[[ Повёрнутые рамки ClipsDescendants не обрезает — ромб торчал целиком и
	     залезал на кнопку. Поэтому он лежит ПОД табличкой (ZIndex 0) центром ровно
	     на её нижней кромке: верхняя половина спрятана, видна нижняя — треугольник.
	     Отступ списка −9 поднимает холдер на 9 px, отсюда 9 сверху. ]]
	local pointerHolder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(18, 19), LayoutOrder = 3, ZIndex = 0 }, col)
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 9), Size = UDim2.fromOffset(13, 13),
		Rotation = 45, BackgroundColor3 = C.glassBot, BorderSizePixel = 0, ZIndex = 0 }, pointerHolder)

	local lastLook = nil
	local function refresh()
		local lvl = model:GetAttribute("Level") or 0
		local building = model:GetAttribute("Building") == true
		local isMax = lvl >= L.MAX
		local price = L.Costs[lvl] or 0
		local enough = not isMax and pirate() >= price

		nameLabel.Text = model:GetAttribute("BuildingName") or model.Name
		lvlNum.Text = tostring(lvl)
		mult.Text = L.formatMult(L.Mults[lvl] or 1)
		if isMax then
			lvlGrad.Color = ColorSequence.new(C.goldTop, C.goldBot); lvlStroke.Color = C.goldBorder
			lvlCap.TextColor3 = C.outline   -- светлое «УР» на золоте не читалось
		else
			lvlGrad.Color = ColorSequence.new(C.blueTop, C.blueBot); lvlStroke.Color = C.blueBorder
			lvlCap.TextColor3 = Color3.fromHex("CFE6FA")
		end
		-- без кнопки элементы заполняют всю ширину, с кнопкой — по местам: уровень, множитель, кнопка
		plateList.HorizontalFlex = (isMax and not building) and Enum.UIFlexAlignment.Fill or Enum.UIFlexAlignment.SpaceBetween
		btn.Visible = not isMax and not building
		prog.Visible = building
		if btn.Visible then
			cost.Text = L.formatNum(price)
			bang.Visible = enough
			btnGrad.Color = enough and ColorSequence.new(C.greenTop, C.greenBot) or ColorSequence.new(C.blueFlat, C.blueFlat)
			btnStroke.Color = enough and C.greenBorder or C.blueBorder
			cost.TextColor3 = enough and Color3.new(1, 1, 1) or C.red
		end
		--[[ ⚠️ ПЕРЕРИСОВКА. Билборд с AutomaticSize/UIListLayout не перестраивался
		     после смены видимости: «100%» висело, пока по табличке не кликнешь.
		     Дёргаем Enabled на кадр — движок пересобирает раскладку. Только если он
		     включён: выключенным его держит окно «Команда» (SurvivorsUI). ]]
		-- только когда сменился вид (кнопка/прогресс/уровень), а не на каждое изменение баланса
		local look = tostring(lvl) .. tostring(btn.Visible) .. tostring(prog.Visible)
		if bb.Enabled and look ~= lastLook then
			lastLook = look
			bb.Enabled = false
			task.defer(function() if bb.Parent then bb.Enabled = true end end)
		end
	end

	btn.Activated:Connect(function()
		if not bang.Visible then return end   -- не хватает — нажатие игнорируем
		remote:FireServer(model)
		local s = new("UIScale", {}, btn)
		TweenService:Create(s, TweenInfo.new(0.08), { Scale = 0.92 }):Play()
		task.delay(0.08, function()
			TweenService:Create(s, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			task.delay(0.2, function() s:Destroy() end)
		end)
	end)

	local hb = RunService.Heartbeat:Connect(function()
		fit.Scale = math.max(bb.AbsoluteSize.X, 1) / CANVAS.X
		if prog.Visible then
			local t0 = model:GetAttribute("BuildStart") or workspace:GetServerTimeNow()
			local dur = tonumber(model:GetAttribute("BuildDuration")) or 0
			-- 100% — только когда сервер закончил (Building снят): до того максимум 99%
			local p = dur > 0 and math.clamp((workspace:GetServerTimeNow() - t0) / dur, 0, 0.99) or 0
			fill.Size = UDim2.fromScale(p, 1)
			pct.Text = math.floor(p * 100) .. "%"
		end
	end)

	local conns = { hb }
	for _, a in ipairs({ "Level", "Building", "BuildingName" }) do
		table.insert(conns, model:GetAttributeChangedSignal(a):Connect(refresh))
	end
	table.insert(conns, player:GetAttributeChangedSignal("Pirate"):Connect(refresh))
	local function drop()
		for _, c in ipairs(conns) do c:Disconnect() end
		bb:Destroy()
	end
	table.insert(conns, model.AncestryChanged:Connect(function(_, parent) if not parent then drop() end end))
	table.insert(conns, CollectionService:GetInstanceRemovedSignal(L.TAG):Connect(function(m) if m == model then drop() end end))
	refresh()
end

for _, m in ipairs(CollectionService:GetTagged(L.TAG)) do task.spawn(build, m) end
CollectionService:GetInstanceAddedSignal(L.TAG):Connect(build)
