local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	GUI ФЕРМЫ НА ПЛОТУ — хендофф farm-ui-design, «Вариант B · Яркий симулятор».

	  табличка на воротах (тег FarmSign) — SurfaceGui: доход, чистыми, овцы,
	      рабочие, зарплаты, сытость, вода, монеты в хранилище, «СОБРАТЬ»;
	  овца в зоне фермы (тег FarmSheep)  — уровень, доход/ч, сытость;
	  фермер (тег FarmWorker)            — занятие, зарплата, таймер;
	  корыто (тег FarmTrough)            — литры, на сколько хватит.

	⚠️ ВСЁ — SurfaceGui, ФИКСИРОВАННОГО РАЗМЕРА В МИРЕ. BillboardGui в пикселях
	держит один размер на экране: издалека табличка над овцой была больше самой
	овцы и закрывала полплота. Поэтому над овцой, фермером и корытом висит
	невидимая ЛОКАЛЬНАЯ доска (только у этого клиента), она каждый кадр встаёт
	над объектом и поворачивается к камере по горизонтали, а SurfaceGui рисуется
	на ней с постоянным PixelsPerStud — вблизи крупно, издалека мелко, как вывеска.

	⚠️ ВСЁ СЧИТАЕТ СЕРВЕР (RaftFarmService). Здесь только рисуем по атрибутам и
	перерисовываем по сигналам. GUI живут в PlayerGui с Adornee: так кнопка на
	табличке нажимается, а в мир не реплицируется ничего лишнего.
	⚠️ UIStroke у ПЛАШЕК — ApplyStrokeMode.Border: Contextual на фрейме без текста
	рамку не рисует (см. память проекта). Contextual — только у надписей.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local C = require(ReplicatedStorage:WaitForChild("RaftFarmConfig"))
local T, G = C.Theme, C.Gradients

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("FarmRemotes", 30)
local collectEvent = remotes and remotes:WaitForChild("CollectCoins", 10)

local FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Heavy)

-- ═══════════ компоненты (раздел 5 хендоффа) ═══════════

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function corner(parent, r)
	return new("UICorner", { CornerRadius = typeof(r) == "UDim" and r or UDim.new(0, r) }, parent)
end

local function border(parent, thick)
	return new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = T.Outline, Thickness = thick or 4 }, parent)
end

local function gradient(parent, g)
	return new("UIGradient", { Rotation = 90, Color = ColorSequence.new(g[1], g[2]) }, parent)
end

local function text(parent, props)
	local stroke = props.stroke
	props.stroke = nil
	local l = new("TextLabel", {
		BackgroundTransparency = 1, FontFace = FONT, TextColor3 = T.Text, TextScaled = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in pairs(props) do l[k] = v end
	if stroke ~= false then
		new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Color = T.Outline, Thickness = stroke or 3 }, l)
	end
	return l
end

-- фон: тень, градиент, обводка, внутренняя светлая рамка, блик сверху
local function panel(parent, pos, size, g, radius, shadowY)
	local holder = new("Frame", { BackgroundTransparency = 1, Position = pos, Size = size }, parent)
	local shadow = new("Frame", { BackgroundColor3 = T.Outline, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, shadowY or 6) }, holder)
	corner(shadow, radius)
	local body = new("Frame", { Name = "Body", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1) }, holder)
	corner(body, radius)
	local grad = g and gradient(body, g)
	border(body, 4)
	local rim = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8) }, body)
	corner(rim, math.max(4, radius - 4))
	new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.new(1, 1, 1), Transparency = 0.65, Thickness = 2 }, rim)
	return holder, body, grad
end

-- монета: жёлтый круг с чёрным контуром и бликом (картинки иконки пока нет)
local function coin(parent, px, pos)
	local c = new("Frame", { BackgroundColor3 = T.Gold, Size = UDim2.fromOffset(px, px), Position = pos or UDim2.new(),
		BorderSizePixel = 0 }, parent)
	corner(c, UDim.new(0.5, 0))
	border(c, math.max(2, math.floor(px / 16)))
	local blik = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.35, BorderSizePixel = 0,
		Size = UDim2.fromScale(0.28, 0.28), Position = UDim2.fromScale(0.22, 0.18) }, c)
	corner(blik, UDim.new(0.5, 0))
	local inner = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.56, 0.56), Position = UDim2.fromScale(0.22, 0.22) }, c)
	corner(inner, UDim.new(0.5, 0))
	new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.fromHex("C98A00"), Thickness = math.max(1, px / 24) }, inner)
	return c
end

local function icon(parent, glyph, px, pos)
	return text(parent, { Text = glyph, TextSize = px, Size = UDim2.fromOffset(px + 6, px + 6), Position = pos or UDim2.new(),
		TextXAlignment = Enum.TextXAlignment.Center, stroke = false })
end

-- полоса: дорожка + заливка (не короче 6 %, иначе ломается скругление)
local function bar(parent, pos, size, color, label)
	local track = new("Frame", { BackgroundColor3 = T.BarTrack, BorderSizePixel = 0, Position = pos, Size = size }, parent)
	corner(track, UDim.new(0.5, 0))
	border(track, 3)
	local fill = new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromScale(0.5, 1) }, track)
	corner(fill, UDim.new(0.5, 0))
	new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.55, BorderSizePixel = 0,
		Position = UDim2.new(0, 6, 0, 3), Size = UDim2.new(1, -12, 0, math.max(2, size.Y.Offset * 0.14)) }, fill)
	local lbl = label and text(track, { Text = "", TextSize = label, Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	return {
		set = function(pct, c)
			fill.Size = UDim2.fromScale(math.clamp(pct / 100, 0.06, 1), 1)
			if c then fill.BackgroundColor3 = c end
		end,
		label = lbl,
	}
end

local function sticker(parent, str, g, rot, pos, px)
	local s = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = pos, Size = UDim2.fromOffset(0, (px or 18) + 16),
		AutomaticSize = Enum.AutomaticSize.X, Rotation = rot or 10, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 8 }, parent)
	corner(s, 12)
	gradient(s, g)
	border(s, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, s)
	text(s, { Text = str, TextSize = px or 18, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 9 })
	return s
end

local function fmt(n)
	local s = tostring(math.floor(n + 0.5))
	local neg = s:sub(1, 1) == "-"
	if neg then s = s:sub(2) end
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
	return (neg and "−" or "") .. out
end

local function bounce(gui)
	local sc = gui:FindFirstChildOfClass("UIScale") or new("UIScale", {}, gui)
	TweenService:Create(sc, TweenInfo.new(0.075), { Scale = 1.15 }):Play()
	task.delay(0.075, function() TweenService:Create(sc, TweenInfo.new(0.075), { Scale = 1 }):Play() end)
end

-- ═══════════ доска над объектом (SurfaceGui вместо BillboardGui) ═══════════

local FLOAT_PPS = 80   -- пикселей GUI на студ: 300 px = 3.75 студа
local floatFolder = Instance.new("Folder")
floatFolder.Name = "FarmUIBoards"
floatFolder.Parent = workspace
local floaters = {}    -- [доска] = { adornee, up }

local function floatSurface(name, adornee, w, h, up, maxDist)
	local board = new("Part", {
		Name = name, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		Transparency = 1, Size = Vector3.new(w / FLOAT_PPS, h / FLOAT_PPS, 0.05),
		CFrame = adornee.CFrame + Vector3.new(0, up, 0),
	}, floatFolder)
	local gui = new("SurfaceGui", {
		Name = name, Adornee = board, Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = FLOAT_PPS, LightInfluence = 0, AlwaysOnTop = false, ResetOnSpawn = false,
		MaxDistance = maxDist or 80, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	floaters[board] = { adornee = adornee, up = up }
	return gui, board
end

-- доски — над объектом и лицом к камере (только поворот вокруг вертикали)
RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local camPos = cam.CFrame.Position
	for board, f in pairs(floaters) do
		if not (board.Parent and f.adornee.Parent) then
			floaters[board] = nil
		else
			local pos = f.adornee.Position + Vector3.new(0, f.up, 0)
			local look = Vector3.new(camPos.X - pos.X, 0, camPos.Z - pos.Z)
			if look.Magnitude > 0.05 then board.CFrame = CFrame.lookAt(pos, pos + look.Unit) end
		end
	end
end)

-- ═══════════ 6.1 ворота: SurfaceGui на табличке ═══════════

local gates = {}

local function buildGateFace(sign, hut, face)
	local gui = new("SurfaceGui", {
		Name = "FarmGate", Adornee = sign, Face = face, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 100, LightInfluence = 0, AlwaysOnTop = false, ResetOnSpawn = false, MaxDistance = 150,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	pcall(function() gui.Active = true end)
	local root = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)

	-- синяя панель
	local _, body = panel(root, UDim2.fromOffset(4, 44), UDim2.new(1, -8, 0, 500), G.Blue, 26, 6)
	-- лента-заголовок поверх панели
	local ribbon = panel(root, UDim2.new(0.5, -250, 0, 6), UDim2.fromOffset(500, 66), G.Red, 16, 5)
	ribbon.Rotation = -2
	ribbon.ZIndex = 5
	text(ribbon, { Text = "ОВЕЧЬЯ ФЕРМА", TextSize = 40, Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6, stroke = 4 })
	local badge = panel(root, UDim2.new(0.5, 200, 0, 0), UDim2.fromOffset(120, 44), G.Yellow, 22, 4)
	badge.Rotation = 4
	badge.ZIndex = 8   -- бейдж уровня поверх красной ленты (у неё 5)
	icon(badge, C.Icons.Star, 22, UDim2.fromOffset(8, 5))
	local lvl = text(badge, { Text = "УР. 1", TextSize = 22, Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -44, 1, 0) })

	local pad = 28
	local inner = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(pad, 40), Size = UDim2.new(1, -pad * 2, 1, -40 - pad) }, body)

	-- белая плашка дохода
	local _, plate = panel(inner, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 96), nil, 20, 5)
	coin(plate, 60, UDim2.fromOffset(18, 18))
	text(plate, { Text = "ДОХОД ФЕРМЫ", TextSize = 16, TextColor3 = T.TextDark, Position = UDim2.fromOffset(92, 12),
		Size = UDim2.fromOffset(260, 20), stroke = false })
	local income = text(plate, { Text = "+0 /ч", TextSize = 52, TextColor3 = T.Money, Position = UDim2.fromOffset(92, 32),
		Size = UDim2.fromOffset(330, 56), stroke = 4 })
	text(plate, { Text = "ЧИСТЫМИ", TextSize = 16, TextColor3 = T.TextDark, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 16), Size = UDim2.fromOffset(200, 20), TextXAlignment = Enum.TextXAlignment.Right, stroke = false })
	local net = text(plate, { Text = "+0 /ч", TextSize = 30, TextColor3 = T.Gold, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 40), Size = UDim2.fromOffset(200, 40), TextXAlignment = Enum.TextXAlignment.Right, stroke = 3 })

	-- три плитки
	local tiles = {}
	local tileW = (780 - 8 - pad * 2 - 24) / 3
	for i, spec in ipairs({ { "ОВЦЫ", G.Green, C.Icons.Sheep }, { "РАБОЧИЕ", G.Purple, C.Icons.Worker }, { "ЗАРПЛАТЫ", G.Red, C.Icons.Wage } }) do
		local _, tb = panel(inner, UDim2.fromOffset((i - 1) * (tileW + 12), 112), UDim2.fromOffset(tileW, 84), spec[2], 18, 5)
		icon(tb, spec[3], 40, UDim2.fromOffset(10, 18))
		text(tb, { Text = spec[1], TextSize = 14, Position = UDim2.fromOffset(62, 12), Size = UDim2.fromOffset(tileW - 70, 18), stroke = 2 })
		tiles[i] = text(tb, { Text = "0", TextSize = 30, Position = UDim2.fromOffset(62, 32), Size = UDim2.fromOffset(tileW - 70, 40), stroke = 3 })
	end

	-- две полосы
	local satBar = bar(inner, UDim2.fromOffset(0, 212), UDim2.new(1, 0, 0, 38), T.BarHunger, 18)
	local watBar = bar(inner, UDim2.fromOffset(0, 262), UDim2.new(1, 0, 0, 38), T.BarWater, 18)

	-- низ: предупреждение + монеты слева, «СОБРАТЬ» справа
	local warnLbl = text(inner, { Text = "", TextSize = 17, TextColor3 = T.Danger, Position = UDim2.fromOffset(0, 314),
		Size = UDim2.fromOffset(440, 22), stroke = 3, Visible = false })
	local counter = new("Frame", { BackgroundColor3 = T.BarTrack, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 342),
		Size = UDim2.fromOffset(250, 52) }, inner)
	corner(counter, UDim.new(0.5, 0))
	border(counter, 4)
	coin(counter, 38, UDim2.fromOffset(8, 7))
	local stored = text(counter, { Text = "0", TextSize = 30, TextColor3 = T.Gold, Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -64, 1, 0) })

	local btnHolder = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 330),
		Size = UDim2.fromOffset(230, 66) }, inner)
	local btnShadow = new("Frame", { BackgroundColor3 = T.Outline, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, 6) }, btnHolder)
	corner(btnShadow, 20)
	local btn = new("TextButton", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		Text = "", AutoButtonColor = false }, btnHolder)
	corner(btn, 20)
	gradient(btn, G.Green)
	border(btn, 4)
	text(btn, { Text = "СОБРАТЬ", TextSize = 28, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, stroke = 3 })
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.08), { Position = UDim2.fromOffset(0, 4) }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.08), { Position = UDim2.fromOffset(0, 0) }):Play()
	end)
	btn.MouseLeave:Connect(function() btn.Position = UDim2.fromOffset(0, 0) end)
	btn.Activated:Connect(function()
		if collectEvent then collectEvent:FireServer(hut) end
	end)

	local lastStored
	local function redraw()
		local a = function(k) return hut:GetAttribute(k) or 0 end
		lvl.Text = "УР. " .. a("Level")
		local inc, wages = a("IncomePerHour"), a("WagesPerHour")
		income.Text = "+" .. fmt(inc) .. " /ч"
		local n = inc - wages
		net.Text = (n >= 0 and "+" or "") .. fmt(n) .. " /ч"
		net.TextColor3 = n >= 0 and T.Gold or T.Danger
		tiles[1].Text = a("SheepCount") .. "/" .. a("SheepMax")
		tiles[2].Text = a("WorkerCount") .. "/" .. a("WorkerMax")
		tiles[3].Text = "−" .. fmt(wages) .. "/ч"
		local sat, wat = a("AvgSatiety"), a("WaterPercent")
		local hungry = a("SheepCount") > 0 and sat < C.HUNGRY_BELOW
		local noTrough = hut:GetAttribute("HasTrough") ~= true
		local thirsty = wat < C.THIRSTY_BELOW
		satBar.set(sat, hungry and T.BarDanger or T.BarHunger)
		satBar.label.Text = "СЫТОСТЬ ОВЕЦ " .. sat .. "%"
		watBar.set(wat, thirsty and T.BarDanger or T.BarWater)
		watBar.label.Text = noTrough and "НЕТ КОРЫТА" or ("ВОДА В КОРЫТЕ " .. wat .. "%")
		warnLbl.Visible = hungry or thirsty
		warnLbl.Text = (hungry and thirsty and "ОВЦЫ ГОЛОДНЫ И ХОТЯТ ПИТЬ! ДОХОД x0.5")
			or (hungry and "ОВЦЫ ГОЛОДНЫ! ДОХОД x0.5")
			or (noTrough and "НЕТ КОРЫТА! ДОХОД x0.5") or "КОРЫТО ПУСТЕЕТ! ДОХОД x0.5"
		local st = math.floor(a("StoredCoins"))
		stored.Text = fmt(st)
		if lastStored and st > lastStored then bounce(counter) end
		lastStored = st
	end
	redraw()
	return gui, hut.AttributeChanged:Connect(redraw)
end

-- табличка двусторонняя: видно и из загона, и снаружи
local function buildGate(sign)
	local link = sign:WaitForChild("Farm", 5)
	local hut = link and link.Value
	if not hut or gates[sign] then return end
	local g1, c1 = buildGateFace(sign, hut, Enum.NormalId.Front)
	local g2, c2 = buildGateFace(sign, hut, Enum.NormalId.Back)
	gates[sign] = { guis = { g1, g2 }, conns = { c1, c2 } }
end

-- ═══════════ 6.2 над овцой ═══════════

local sheepTags = {}

local function buildSheep(sheep)
	local root = sheep.PrimaryPart or sheep:WaitForChild("HumanoidRootPart", 5)
	if not root or sheepTags[sheep] then return end
	local gui, board = floatSurface("FarmSheepTag", root, 300, 150, 3.4, C.SHEEP_HIDE_DIST)
	local full = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	local title = text(full, { Text = "", RichText = true, TextSize = 20, Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center })
	local pillHolder = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 36),
		Size = UDim2.fromOffset(190, 64) }, full)
	local _, pill, pillGrad = panel(pillHolder, UDim2.new(), UDim2.fromScale(1, 1), G.Green, 32, 6)
	coin(pill, 44, UDim2.fromOffset(10, 10))
	local inc = text(pill, { Text = "", RichText = true, TextSize = 44, Position = UDim2.fromOffset(60, 0), Size = UDim2.new(1, -64, 1, 0), stroke = 4 })
	local x05 = sticker(pillHolder, "x0.5", G.Yellow, 12, UDim2.new(1, 14, 0, -18), 18)
	local sat = bar(full, UDim2.new(0.5, -100, 0, 112), UDim2.fromOffset(200, 22), T.BarHunger)


	local lastInc
	local function redraw()
		local level = sheep:GetAttribute("Level") or 1
		local s = sheep:GetAttribute("Satiety") or 0
		local i = sheep:GetAttribute("IncomePerHour") or 0
		local hungry = s < C.HUNGRY_BELOW
		title.Text = hungry and "ГОЛОДНА!" or ("ОВЦА <font color=\"#FFD21F\">УР." .. level .. "</font>")
		title.TextColor3 = hungry and T.Danger or T.Text
		title.Rotation = hungry and -3 or 0
		pillGrad.Color = ColorSequence.new((hungry and G.Red or G.Green)[1], (hungry and G.Red or G.Green)[2])
		inc.Text = "+" .. i .. "<font size=\"24\">/ч</font>"
		x05.Visible = hungry
		sat.set(s, hungry and T.BarDanger or T.BarHunger)
		if lastInc and i ~= lastInc then bounce(pillHolder) end
		lastInc = i
	end
	redraw()
	local conn = sheep.AttributeChanged:Connect(redraw)
	sheepTags[sheep] = { gui = gui, board = board, conn = conn }
end

-- ═══════════ 6.3 над фермером ═══════════

local workers = {}

--[[ ⚠️ КАРТОЧКА РАБОТНИКА — ОДНА СТРОКА. Раньше: аватар-глиф, имя, отдельная
     полоса «ЗАРПЛАТА», строка таймера — 350×210, закрывала полфермы. Теперь
     ~300×96: настоящая иконка головы капитана (SurvivorDefs.head) слева, имя и
     одна строка «занятие · ⏱ до выплаты» посередине, плашка зарплаты справа.
     Долг: карточка серая, в плашке — сумма долга красным, в строке — «[E] ВЫПЛАТИТЬ». ]]
local SurvivorDefsOk, SurvivorDefs = pcall(function() return require(ReplicatedStorage:WaitForChild("SurvivorDefs", 5)) end)
local function workerHeadImage(npc)
	local id = npc:GetAttribute("SurvivorWorker")
	local def = SurvivorDefsOk and SurvivorDefs and SurvivorDefs.CATALOG and type(id) == "string" and SurvivorDefs.CATALOG[id]
	return def and def.head or nil
end

local function buildWorker(npc)
	local head = npc:WaitForChild("Head", 5)
	if not head or workers[npc] then return end
	local gui, board = floatSurface("FarmWorkerTag", head, 300, 96, 2.2, 70)
	local holder, card, cardGrad = panel(gui, UDim2.fromOffset(4, 8), UDim2.new(1, -8, 1, -16), G.Purple, 20, 5)
	local avatar = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(56, 56) }, card)
	corner(avatar, 14)
	border(avatar, 3)
	local img = workerHeadImage(npc)
	if img then
		new("ImageLabel", { BackgroundTransparency = 1, Image = img, ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4) }, avatar)
	else
		icon(avatar, C.Icons.Worker, 38, UDim2.fromOffset(6, 6))
	end
	local role = text(card, { Text = "ФЕРМЕР", TextSize = 22, Position = UDim2.fromOffset(72, 8), Size = UDim2.new(1, -176, 0, 26),
		TextTruncate = Enum.TextTruncate.AtEnd, stroke = 3 })
	local info = text(card, { Text = "", TextSize = 14, TextColor3 = T.Money, Position = UDim2.fromOffset(72, 38),
		Size = UDim2.new(1, -176, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd, stroke = 2 })

	local wagePill = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(92, 34) }, card)
	corner(wagePill, UDim.new(0.5, 0))
	border(wagePill, 3)
	coin(wagePill, 22, UDim2.fromOffset(5, 6))
	local wage = text(wagePill, { Text = "25/ч", TextSize = 18, TextColor3 = T.Gold, Position = UDim2.fromOffset(31, 0), Size = UDim2.new(1, -34, 1, 0), stroke = 2 })
	local strike = sticker(holder, "БАСТУЕТ!", G.Red, 10, UDim2.new(1, 6, 0, -14), 14)

	local timeLeft = ""
	local function drawInfo()
		local striking = (npc:GetAttribute("Debt") or 0) > 0
		if striking then
			info.Text = "[E] ВЫПЛАТИТЬ ДОЛГ"
		else
			local act = npc:GetAttribute("Activity") or ""
			info.Text = (act ~= "" and (act .. "  ") or "") .. timeLeft
		end
		info.TextColor3 = striking and T.Danger or T.Money
	end
	local function redraw()
		local debt = npc:GetAttribute("Debt") or 0
		local striking = debt > 0
		cardGrad.Color = ColorSequence.new((striking and G.Gray or G.Purple)[1], (striking and G.Gray or G.Purple)[2])
		avatar.BackgroundColor3 = striking and T.StrikeAvatar or Color3.new(1, 1, 1)
		role.Text = npc:GetAttribute("Role") or "ФЕРМЕР"
		strike.Visible = striking
		wage.Text = striking and ("-" .. tostring(debt)) or ((npc:GetAttribute("WagePerHour") or 0) .. "/ч")
		wage.TextColor3 = striking and T.Danger or T.Gold
		drawInfo()
	end
	redraw()
	local conn = npc.AttributeChanged:Connect(redraw)
	workers[npc] = { gui = gui, board = board, conn = conn, npc = npc,
		setTime = function(str) timeLeft = str; drawInfo() end }
end

-- ═══════════ 6.4 над корытом ═══════════

local troughs = {}

local function buildTrough(model)
	if troughs[model] then return end
	local base = model.PrimaryPart
	if not base then
		local vol = -1
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Size.X * d.Size.Y * d.Size.Z > vol then base, vol = d, d.Size.X * d.Size.Y * d.Size.Z end
		end
	end
	if not base then return end
	local _, ext = model:GetBoundingBox()
	local gui, board = floatSurface("FarmTroughTag", base, 350, 190, ext.Y * 0.5 + 1.8, 70)
	local holder, card = panel(gui, UDim2.fromOffset(6, 14), UDim2.new(1, -12, 1, -26), G.Water, 24, 6)
	icon(card, C.Icons.Drop, 40, UDim2.fromOffset(12, 10))
	text(card, { Text = "КОРЫТО", TextSize = 28, Position = UDim2.fromOffset(66, 12), Size = UDim2.fromOffset(160, 40), stroke = 3 })
	local liters = text(card, { Text = "", RichText = true, TextSize = 26, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(140, 36), TextXAlignment = Enum.TextXAlignment.Right, stroke = 3 })
	local wbar = bar(card, UDim2.fromOffset(16, 62), UDim2.new(1, -32, 0, 40), T.BarWater)
	local foot = text(card, { Text = "", TextSize = 16, Position = UDim2.fromOffset(0, 112), Size = UDim2.new(1, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center, stroke = 2 })
	--[[ ПОДСКАЗКА «[ПКМ] НАЛИТЬ» — ряд по центру: плитка клавиши и надпись рядом,
	     а не друг на друге (раньше плитка «E» закрывала начало слова). Наливают
	     правой кнопкой (FarmTroughFill.client), на телефоне — тапом. ]]
	local key = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(0, 112),
		Size = UDim2.new(1, 0, 0, 30), Visible = false }, card)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, key)
	key.Position = UDim2.new(0.5, 0, 0, 112)
	local keyTile = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1 }, key)
	corner(keyTile, 8)
	border(keyTile, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, keyTile)
	local touch = game:GetService("UserInputService").TouchEnabled and not game:GetService("UserInputService").MouseEnabled
	text(keyTile, { Text = touch and "ТАП" or "ПКМ", TextSize = 18, TextColor3 = T.Outline, Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X, stroke = false })
	text(key, { Text = "НАЛИТЬ", TextSize = 18, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, stroke = 2 })
	local low = sticker(holder, "ДОЛЕЙ ВОДЫ!", G.Red, 10, UDim2.new(1, 8, 0, -18), 16)

	local function redraw()
		local w = model:GetAttribute("Water") or 0
		local max = model:GetAttribute("WaterMax") or 100
		local drain = model:GetAttribute("DrainPerMinute") or 0
		local pct = max > 0 and w / max * 100 or 0
		local isLow = pct < C.THIRSTY_BELOW
		liters.Text = ("<font color=\"#%s\">%d</font><font size=\"16\">/%d Л</font>"):format(isLow and "FF5A4A" or "FFFFFF", w, max)
		wbar.set(pct, isLow and T.BarDanger or T.BarWater)
		low.Visible = isLow
		key.Visible = isLow
		if isLow then
			foot.Text = ""   -- вместо строки — ряд «[ПКМ] НАЛИТЬ» (key)
		elseif drain > 0 then
			foot.Text = ("ХВАТИТ НА ~%d МИН"):format(math.floor(w / drain + 0.5))
		else
			foot.Text = "ОВЦЫ НЕ ПЬЮТ"
		end
	end
	redraw()
	local conn = model.AttributeChanged:Connect(redraw)
	troughs[model] = { gui = gui, board = board, low = low, conn = conn }
end

-- ═══════════ подключение по тегам ═══════════

local function track(tag, build, store)
	local function add(inst)
		task.spawn(function()
			local ok, err = pcall(build, inst)
			if not ok then warn("[Ферма/UI] " .. tag .. ": " .. tostring(err)) end
		end)
	end
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do add(inst) end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		local rec = store[inst]
		if rec then
			store[inst] = nil
			if rec.conn then rec.conn:Disconnect() end
			if rec.gui then rec.gui:Destroy() end
			if rec.board then rec.board:Destroy() end
			for _, c in ipairs(rec.conns or {}) do c:Disconnect() end
			for _, g in ipairs(rec.guis or {}) do g:Destroy() end
		end
	end)
end

track("FarmSign", buildGate, gates)
track("FarmSheep", buildSheep, sheepTags)
track("FarmWorker", buildWorker, workers)
track("FarmTrough", buildTrough, troughs)

-- один общий цикл: дистанция овец, таймер фермера, мигание наклейки, уборка
local acc, blink = 0, false
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.2 then return end
	acc = 0
	blink = not blink
	for sheep, rec in pairs(sheepTags) do
		if not sheep.Parent then
			sheepTags[sheep] = nil
			rec.conn:Disconnect()
			rec.gui:Destroy()
			rec.board:Destroy()
		end
	end
	local t = workspace:GetServerTimeNow()
	for npc, rec in pairs(workers) do
		if not npc.Parent then
			workers[npc] = nil
			rec.conn:Disconnect()
			rec.gui:Destroy()
			rec.board:Destroy()
		else
			local left = math.max(0, (npc:GetAttribute("NextPayAt") or t) - t)
			rec.setTime(("%s %d:%02d"):format(C.Icons.Clock, math.floor(left / 60), math.floor(left % 60)))
		end
	end
	for model, rec in pairs(troughs) do
		if not model.Parent then
			troughs[model] = nil
			rec.conn:Disconnect()
			rec.gui:Destroy()
			rec.board:Destroy()
		elseif rec.low.Visible then
			rec.low.BackgroundTransparency = blink and 0.3 or 0
		end
	end
	for sign, rec in pairs(gates) do
		if not sign.Parent then
			gates[sign] = nil
			for _, c in ipairs(rec.conns) do c:Disconnect() end
			for _, g in ipairs(rec.guis) do g:Destroy() end
		end
	end
end)

print("[Ферма/UI] готово: табличка ворот, овцы, фермер, корыто")
