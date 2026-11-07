-- RaftHealthHUD.client.lua
-- Top-centre raft health bar (reads the Raft's HP / MaxHP attributes, which the
-- server replicates) + a "raft destroyed" game-over screen.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local raft = workspace:WaitForChild("Raft")
local HudStyle = require(ReplicatedStorage:WaitForChild("HudStyle"))

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local sg = new("ScreenGui", { Name = "RaftHealthHUD", ResetOnSpawn = false, IgnoreGuiInset = true }, playerGui)

-- ── bar (top-centre, ВЫШЕ — сразу под баннером дня) ──
local holder = HudStyle.panel({
	parent = sg, size = UDim2.fromOffset(322, 34),
	position = UDim2.new(0.5, 0, 0, 62), anchor = Vector2.new(0.5, 0), radius = 12,
})
holder.ZIndex = 1

-- тёмная «яма» под полосой
local track = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -12, 1, -12), BackgroundColor3 = HudStyle.TRACK_BG, BorderSizePixel = 0, ZIndex = 2,
	ClipsDescendants = true,
}, holder)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, track)
new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 1.5, Transparency = 0.3 }, track)

-- заливка HP с вертикальным градиентом + верхний блик
local fill = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
	Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(56, 182, 66), BorderSizePixel = 0, ZIndex = 3,
}, track)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, fill)
local fillGrad = new("UIGradient", { Rotation = 90 }, fill)
local fillGloss = new("Frame", {
	Position = UDim2.fromOffset(4, 3), Size = UDim2.new(1, -8, 0, 5), BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.62, BorderSizePixel = 0, ZIndex = 4,
}, fill)
new("UICorner", { CornerRadius = UDim.new(0, 3) }, fillGloss)

local label = HudStyle.label({
	parent = track, text = "Плот", size = UDim2.fromScale(1, 1),
	font = Enum.Font.GothamBlack, textSize = 16, color = Color3.fromRGB(255, 255, 255),
	strokeT = 0.25, zIndex = 6,
})

local TweenService = game:GetService("TweenService")
local function update()
	local hp = raft:GetAttribute("HP") or 0
	local maxHP = math.max(raft:GetAttribute("MaxHP") or 1, 1)
	local frac = math.clamp(hp / maxHP, 0, 1)

	-- Плашку показываем ТОЛЬКО когда плот повреждён: при целом плоте она просто
	-- занимала место сверху. Прячем весь блок, а не одну заливку, иначе на экране
	-- осталась бы пустая рамка. Сравнение с запасом: HP хранится числом с плавающей
	-- точкой (постройка добавляет дробные значения), и строгое hp < maxHP давало бы
	-- «мигание» плашки на полном плоту.
	holder.Visible = frac < 0.999

	fill.Visible = frac > 0
	TweenService:Create(fill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(frac, 0, 1, 0) }):Play()
	local a, b, c = HudStyle.hpColors(frac)
	fill.BackgroundColor3 = b
	fillGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, a),
		ColorSequenceKeypoint.new(0.5, b),
		ColorSequenceKeypoint.new(1, c),
	})
	label.Text = "Плот  " .. math.floor(hp) .. " / " .. math.floor(maxHP)
end
raft:GetAttributeChangedSignal("HP"):Connect(update)
raft:GetAttributeChangedSignal("MaxHP"):Connect(update)
update()

-- ── game over screen: «Плот пошёл ко дну» ──
-- Интеграция макета Sunken Ship Menu (Sunken Ship Menu Roblox.dc.html) 1:1:
-- тёмный океанский фон с виньеткой и всплывающими пузырьками, заголовок,
-- зелёная градиентная кнопка «Возродиться командой» с ценником, синяя
-- «Выйти в лобби», тост снизу. Анимации:
--   • возрождение (RaftRevived): контент растворяется с зумом, экран
--     заливает светлая «вспышка всплытия» (2s), затем ВЕСЬ блок гаснет
--     по прозрачности (CanvasGroup.GroupTransparency) и уничтожается;
--   • уход в лобби: контент «остаётся на глубине» — улетает вверх с
--     ускорением и растворяется, через ~1s клиент шлёт "lobby" серверу.
local MarketplaceService = game:GetService("MarketplaceService")

local ev        = ReplicatedStorage:WaitForChild("RaftDestroyed")
local revivedEv = ReplicatedStorage:WaitForChild("RaftRevived")
local actionEv  = ReplicatedStorage:WaitForChild("RaftGameOverAction")

-- палитра макета
local S = {
	bgTop     = Color3.fromHex("0d2b45"),
	bgMid     = Color3.fromHex("071c30"),
	bgBot     = Color3.fromHex("02090f"),
	flashTop  = Color3.fromHex("bfeaff"),
	flashMid  = Color3.fromHex("5db6e6"),
	flashBot  = Color3.fromHex("1d6ea8"),
	bubble    = Color3.fromRGB(140, 200, 235),
	white     = Color3.fromHex("ffffff"),
	subText   = Color3.fromHex("7fa8c9"),
	caption   = Color3.fromHex("6f97b8"),
	greenTop  = Color3.fromHex("45cc45"),
	greenMid  = Color3.fromHex("2fa32f"),
	greenBot  = Color3.fromHex("1f7d1f"),
	blueTop   = Color3.fromHex("2c4d68"),
	blueMid   = Color3.fromHex("1d3750"),
	blueBot   = Color3.fromHex("132638"),
	lobbyText = Color3.fromHex("cfe3f2"),
	gold      = Color3.fromHex("ffd23a"),
	black     = Color3.fromHex("000000"),
}
-- M PLUS Rounded 1c (900) из макета: FredokaOne ближе по форме, но в нём
-- нет кириллицы (русский текст упал бы в фолбэк-шрифт) — берём GothamBlack,
-- самый жирный шрифт с кириллицей, тот же, что в остальных меню игры.
local FONT = Enum.Font.GothamBlack

-- пузырьки макета: { left%, длительность s, размер px, задержка s }
local BUBBLE_SEEDS = {
	{ 6, 14, 9, 0 }, { 16, 10, 12, 3 }, { 27, 18, 8, 6 }, { 38, 12, 14, 1.5 },
	{ 52, 16, 10, 4.5 }, { 63, 11, 13, 2 }, { 74, 17, 9, 5.5 }, { 85, 13, 12, 0.8 },
	{ 93, 19, 8, 3.8 }, { 45, 20, 7, 7 },
}

local function brighten(c, k)
	return Color3.new(math.min(c.R * k, 1), math.min(c.G * k, 1), math.min(c.B * k, 1))
end

local function vGradient(parent, top, mid, bot)
	return new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, top),
			ColorSequenceKeypoint.new(0.55, mid),
			ColorSequenceKeypoint.new(1, bot),
		}),
	}, parent)
end

-- текст: чёрная обводка (UIStroke) + жёсткая тень-клон вниз, как text-shadow макета
local function fancyText(parent, p)
	local main = new("TextLabel", {
		BackgroundTransparency = 1, Font = FONT, Text = p.text, TextSize = p.textSize,
		TextColor3 = p.color, Size = p.size, Position = p.pos,
		AnchorPoint = p.anchor or Vector2.new(0, 0),
		TextXAlignment = p.xAlign or Enum.TextXAlignment.Center,
		ZIndex = p.zIndex or 5,
	})
	if p.strokeT and p.strokeT > 0 then
		new("UIStroke", {
			Color = S.black, Thickness = p.strokeT,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}, main)
	end
	local sh
	if p.shadowY and p.shadowY > 0 then
		sh = main:Clone()
		sh.TextColor3 = S.black
		sh.Position = p.pos + UDim2.fromOffset(0, p.shadowY)
		sh.ZIndex = main.ZIndex - 1
		local st = sh:FindFirstChildOfClass("UIStroke")
		if st then st.Color = S.black end
		sh.Parent = parent
	end
	main.Parent = parent
	return main, sh
end

-- кнопка макета: вертикальный градиент, рамка 4px чёрная, жёсткая тень 0/6px,
-- hover — осветление градиента, нажатие — сдвиг вниз на 3px (тень укорачивается)
local function gradientButton(parent, p)
	local shadow = new("Frame", {
		Size = UDim2.fromOffset(p.w, p.h), Position = p.pos + UDim2.fromOffset(0, 6),
		AnchorPoint = p.anchor or Vector2.new(0, 0),
		BackgroundColor3 = S.black, BackgroundTransparency = 0.45, BorderSizePixel = 0,
		ZIndex = (p.zIndex or 5) - 1,
	}, parent)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(p.w, p.h), Position = p.pos,
		AnchorPoint = p.anchor or Vector2.new(0, 0),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
		Text = "", AutoButtonColor = false, ZIndex = p.zIndex or 5,
	}, parent)
	local grad = vGradient(btn, p.top, p.mid, p.bot)
	new("UIStroke", { Color = S.black, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, btn)

	local normal = grad.Color
	local hovered = ColorSequence.new({
		ColorSequenceKeypoint.new(0, brighten(p.top, p.hoverK or 1.12)),
		ColorSequenceKeypoint.new(0.55, brighten(p.mid, p.hoverK or 1.12)),
		ColorSequenceKeypoint.new(1, brighten(p.bot, p.hoverK or 1.12)),
	})
	btn.MouseEnter:Connect(function()
		if btn.Active then grad.Color = hovered end
	end)
	btn.MouseLeave:Connect(function()
		grad.Color = normal
		btn.Position = p.pos
	end)
	btn.MouseButton1Down:Connect(function()
		if btn.Active then btn.Position = p.pos + UDim2.fromOffset(0, 3) end
	end)
	btn.MouseButton1Up:Connect(function()
		btn.Position = p.pos
	end)
	return btn, shadow
end

-- боковое затемнение (приближение radial-виньетки макета)
local function addVignette(parent)
	local function edge(size, pos, anchor, rotation, fromEdge)
		local f = new("Frame", {
			Size = size, Position = pos, AnchorPoint = anchor,
			BackgroundColor3 = S.black, BorderSizePixel = 0, ZIndex = 2,
		}, parent)
		local t0 = fromEdge and 0.45 or 1
		local t1 = fromEdge and 1 or 0.45
		new("UIGradient", {
			Rotation = rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, t0),
				NumberSequenceKeypoint.new(1, t1),
			}),
		}, f)
		return f
	end
	edge(UDim2.new(1, 0, 0.28, 0), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), 90, true)    -- верх
	edge(UDim2.new(1, 0, 0.34, 0), UDim2.new(0, 0, 1, 0), Vector2.new(0, 1), 90, false)   -- низ
	edge(UDim2.new(0.22, 0, 1, 0), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), 0, true)     -- лево
	edge(UDim2.new(0.22, 0, 1, 0), UDim2.new(1, 0, 0, 0), Vector2.new(1, 0), 0, false)    -- право
end

-- всплывающий пузырёк: цикл подъёма с плавным появлением/затуханием
-- (keyframes bubbleUp макета: opacity 0 → 0.5 → 0.5 → 0)
local function runBubble(b, stroke, leftPct, dur, delay)
	task.spawn(function()
		task.wait(delay)
		local TI = TweenInfo.new
		while b.Parent do
			b.Position = UDim2.new(leftPct / 100, 0, 1, 30)
			b.BackgroundTransparency = 1
			stroke.Transparency = 1
			TweenService:Create(b, TI(dur, Enum.EasingStyle.Linear), {
				Position = UDim2.new(leftPct / 100, 0, 0.22, 30),
			}):Play()
			TweenService:Create(b, TI(dur * 0.12, Enum.EasingStyle.Linear), { BackgroundTransparency = 0.94 }):Play()
			TweenService:Create(stroke, TI(dur * 0.12, Enum.EasingStyle.Linear), { Transparency = 0.72 }):Play()
			task.wait(dur * 0.88)
			if not b.Parent then break end
			TweenService:Create(b, TI(dur * 0.12, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(stroke, TI(dur * 0.12, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
			task.wait(dur * 0.12)
		end
	end)
end

local current -- активный экран: { gui, root, content, contentScale, flash, reviveBtn, lobbyBtn, showToast, anim }

-- возрождение: вспышка всплытия → плавный уход всего блока в прозрачность
revivedEv.OnClientEvent:Connect(function()
	local c = current
	if not c or not c.gui.Parent then return end
	if c.anim == "revive" then return end
	c.anim = "revive"
	c.reviveBtn.Active = false
	c.lobbyBtn.Active = false

	TweenService:Create(c.contentScale, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = 1.15 }):Play()
	TweenService:Create(c.content, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ GroupTransparency = 1 }):Play()
	TweenService:Create(c.flash, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ BackgroundTransparency = 0 }):Play()

	-- пик вспышки (экран полностью голубой) → плавное «всплытие»: весь блок
	-- медленно уходит в прозрачность, открывая уже возрождённую команду
	task.delay(2.05, function()
		if c.gui.Parent then
			local fade = TweenService:Create(c.root, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
				{ GroupTransparency = 1 })
			fade.Completed:Connect(function()
				c.gui:Destroy()
			end)
			fade:Play()
		end
		if current == c then current = nil end
	end)
end)

ev.OnClientEvent:Connect(function(timeout, productId)
	productId = tonumber(productId) or 0
	if current and current.gui then current.gui:Destroy() end

	local gui = new("ScreenGui", {
		Name = "RaftGameOverGui", ResetOnSpawn = false, IgnoreGuiInset = true,
		-- ВАЖНО: Sibling, иначе (при Global) тексты кнопок с ZIndex выше вспышки
		-- рисуются поверх неё и не гаснут вместе с CanvasGroup контента
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 200, Parent = playerGui,
	})
	if _G.AttachInventoryUIScale then
		_G.AttachInventoryUIScale(gui)
	end

	-- корневая CanvasGroup: финальный уход в прозрачность гасит ВЕСЬ блок разом
	local root = new("CanvasGroup", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		GroupTransparency = 1, BorderSizePixel = 0,
	}, gui)

	-- фон: глубина океана (radial-градиент макета ~ вертикальный переход)
	local bg = new("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, ZIndex = 1,
	}, root)
	vGradient(bg, S.bgTop, S.bgMid, S.bgBot)

	addVignette(root)

	-- пузырьки
	local bubbles = new("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		ClipsDescendants = true, ZIndex = 3,
	}, root)
	for _, seed in ipairs(BUBBLE_SEEDS) do
		local leftPct, dur, size, delay = seed[1], seed[2], seed[3], seed[4]
		local b = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(leftPct / 100, 0, 1, 30),
			Size = UDim2.fromOffset(size, size), BackgroundColor3 = S.bubble,
			BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3,
		}, bubbles)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
		local st = new("UIStroke", { Color = S.bubble, Thickness = 2, Transparency = 1 }, b)
		runBubble(b, st, leftPct, dur, delay)
	end

	-- контент: своя CanvasGroup — «sink» уводит его вверх, «revive» растворяет
	local CONTENT_W, CONTENT_H = 480, 292
	local BTN_W = 420
	local content = new("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CONTENT_W, CONTENT_H), BackgroundTransparency = 1,
		BorderSizePixel = 0, ZIndex = 4,
	}, root)
	local contentScale = new("UIScale", { Scale = 1 }, content)

	fancyText(content, {
		text = "Плот пошёл ко дну", textSize = 46, color = S.white,
		size = UDim2.new(1, 0, 0, 52), pos = UDim2.fromOffset(0, 0),
		strokeT = 3, shadowY = 4, zIndex = 6,
	})
	fancyText(content, {
		text = "Что дальше, капитан?", textSize = 20, color = S.subText,
		size = UDim2.new(1, 0, 0, 26), pos = UDim2.fromOffset(0, 60),
		shadowY = 2, zIndex = 6,
	})

	-- ── «Возродиться командой» (зелёная, за Robux) ──
	local REVIVE_Y = 124
	local reviveBtn = gradientButton(content, {
		w = BTN_W, h = 62, pos = UDim2.new(0.5, 0, 0, REVIVE_Y), anchor = Vector2.new(0.5, 0),
		top = S.greenTop, mid = S.greenMid, bot = S.greenBot, hoverK = 1.1, zIndex = 6,
	})
	fancyText(reviveBtn, {
		text = "Возродиться командой", textSize = 22, color = S.white,
		size = UDim2.new(1, -140, 1, 0), pos = UDim2.fromOffset(22, 0),
		xAlign = Enum.TextXAlignment.Left, strokeT = 1.5, shadowY = 2, zIndex = 8,
	})
	-- ценник: тёмная вставка с рамкой, шестигранник + цена золотом
	local chip = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(96, 38), BackgroundColor3 = S.black,
		BackgroundTransparency = 0.65, BorderSizePixel = 0, ZIndex = 8,
	}, reviveBtn)
	new("UIStroke", { Color = S.black, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, chip)
	-- «монетка»: юникод-шестигранник ⬡ в шрифтах Roblox не рендерится (тофу),
	-- поэтому рисуем золотой ромб — повёрнутый квадрат с чёрной обводкой
	local coin = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 13, 0.5, 0),
		Size = UDim2.fromOffset(13, 13), Rotation = 45,
		BackgroundColor3 = S.gold, BorderSizePixel = 0, ZIndex = 9,
	}, chip)
	new("UIStroke", { Color = S.black, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, coin)
	local priceLabel = new("TextLabel", {
		BackgroundTransparency = 1, Font = FONT, Text = "…", TextSize = 20,
		TextColor3 = S.gold, AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 36, 0.5, 0), Size = UDim2.new(1, -44, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9,
	}, chip)

	fancyText(content, {
		text = "Полное ХП плота, вся команда снова в строю", textSize = 14, color = S.caption,
		size = UDim2.new(1, 0, 0, 18), pos = UDim2.fromOffset(0, REVIVE_Y + 62 + 10),
		shadowY = 2, zIndex = 6,
	})

	-- ── «Выйти в лобби» (синяя) ──
	local LOBBY_Y = REVIVE_Y + 62 + 10 + 18 + 18
	local lobbyBtn = gradientButton(content, {
		w = BTN_W, h = 54, pos = UDim2.new(0.5, 0, 0, LOBBY_Y), anchor = Vector2.new(0.5, 0),
		top = S.blueTop, mid = S.blueMid, bot = S.blueBot, hoverK = 1.15, zIndex = 6,
	})
	fancyText(lobbyBtn, {
		text = "Выйти в лобби", textSize = 20, color = S.lobbyText,
		size = UDim2.fromScale(1, 1), pos = UDim2.fromOffset(0, 0),
		strokeT = 1.5, shadowY = 2, zIndex = 8,
	})

	-- вспышка всплытия (над контентом, как в макете) — заливает экран при возрождении
	local flash = new("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6,
	}, root)
	vGradient(flash, S.flashTop, S.flashMid, S.flashBot)

	-- тост снизу (виден и поверх анимаций)
	local toast = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.92, 0),
		AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = S.black, BackgroundTransparency = 0.5, BorderSizePixel = 0,
		Font = FONT, TextSize = 14, TextColor3 = S.gold, Text = "",
		Visible = false, ZIndex = 7,
	}, root)
	new("UIStroke", { Color = S.gold, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, toast)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7),
		PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
	}, toast)

	local c = {
		gui = gui, root = root, content = content, contentScale = contentScale,
		flash = flash, reviveBtn = reviveBtn, lobbyBtn = lobbyBtn, anim = nil,
	}
	local toastToken = 0
	function c.showToast(msg)
		toastToken += 1
		local tok = toastToken
		toast.Text = msg
		toast.Visible = true
		task.delay(2.2, function()
			if toastToken == tok and toast.Parent then toast.Visible = false end
		end)
	end
	current = c

	-- цена девпродукта в ценник (и для текста тоста)
	local priceValue
	if productId > 0 then
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
			end)
			if ok and info and info.PriceInRobux and priceLabel.Parent then
				priceValue = info.PriceInRobux
				priceLabel.Text = tostring(priceValue)
			end
		end)
	else
		priceLabel.Text = "0" -- Studio-режим: продукт не задан, возрождение бесплатное
	end

	local reviveCooldown = 0
	reviveBtn.Activated:Connect(function()
		if c.anim or os.clock() < reviveCooldown then return end
		reviveCooldown = os.clock() + 2 -- не спамим окно покупки
		if priceValue then
			c.showToast(("Покупка: возрождение команды за %d Robux…"):format(priceValue))
		else
			c.showToast("Покупка: возрождение команды…")
		end
		actionEv:FireServer("revive")
	end)

	-- уход в лобби: контент улетает вверх с ускорением и растворяется;
	-- через ~1s (анимация ещё идёт) просим сервер телепортировать
	lobbyBtn.Activated:Connect(function()
		if c.anim then return end
		c.anim = "sink"
		reviveBtn.Active = false
		lobbyBtn.Active = false
		TweenService:Create(content, TweenInfo.new(1.8, Enum.EasingStyle.Cubic, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, -0.7, 0) }):Play()
		TweenService:Create(content, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ GroupTransparency = 1 }):Play()
		task.delay(1.0, function()
			actionEv:FireServer("lobby")
		end)
	end)

	-- ОТКАЗ СЕРВЕРА. Экран уже улетел вверх и растворился — без этого игрок
	-- оставался перед пустым экраном и решал, что кнопка сломана. Возвращаем
	-- блок на место и пишем причину.
	actionEv.OnClientEvent:Connect(function(reason)
		if current ~= c then return end
		if reason == "lobbyFailed" then
			c.anim = nil
			reviveBtn.Active = true
			lobbyBtn.Active = true
			TweenService:Create(content, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0.5, 0, 0.5, 0), GroupTransparency = 0 }):Play()
			c.showToast("Лобби недоступно — не удалось телепортировать")
		elseif reason == "reviveUnavailable" then
			c.showToast("Возрождение пока недоступно")
		end
	end)

	-- появление всего блока
	TweenService:Create(root, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = 0 }):Play()
end)
