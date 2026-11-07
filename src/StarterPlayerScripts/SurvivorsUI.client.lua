local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	УПРАВЛЕНИЕ ВЫЖИВШИМИ — окно (хендофф design_handoff_survivors,
	«Управление выжившими.dc.html», тема «Океан»). Сервер — SurvivorService.

	A. Список: сайдбар «Команда» (сколько выживших, зарплаты в день, фильтры) +
	   окно «Выжившие» со строками. Строка кликабельна целиком → страница B.
	B. Страница выжившего: слева предпросмотр, здоровье, настроение, бонусы;
	   справа «Место работы» (здания плота с превью), «Зарплата», показатели,
	   «Сохранить» / «Выгнать» (с подтверждением).

	ПРЕДПРОСМОТР — отдельный ViewportFrame в окошке «сцены»: своя камера, копия
	модели внутри. Камеру игрока окно не трогает, поэтому за меню остаётся
	обычный экран игры (приглушённый затемнением). Лицо персонажа — SurfaceGui,
	в ViewportFrame оно не рисуется, поэтому поверх кадра лежит 2D-копия лица и
	каждый кадр перепроецируется под текущий поворот (прячется, когда персонаж
	отвернулся). Модель дышит и моргает (RoseStudio: Signature Idle + мимика),
	мышью/пальцем её можно крутить.

	Портреты в строках списка маленькие: там ViewportFrame с копией модели, а
	лицо дорисовано поверх 2D-копией того же SurfaceGui (проекция грани лица) —
	и оно моргает той же RoseStudio.Expression.

	Превью здания в карточке — ViewportFrame с самим зданием с плота (ModelIcon).
	Плюс: мимика у выживших, которые работают на плоту (атрибут SurvivorFace).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local GuiService        = game:GetService("GuiService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local D         = require(ReplicatedStorage:WaitForChild("SurvivorDefs"))
local rf        = ReplicatedStorage:WaitForChild("SurvivorsRF")
local changedEv = ReplicatedStorage:WaitForChild("SurvivorsChanged")

local Rose do
	local ok, mod = pcall(function() return require(ReplicatedStorage:WaitForChild("RoseStudio", 10)) end)
	Rose = ok and mod or nil
end
local ModelIcon do
	local ok, mod = pcall(function() return require(ReplicatedStorage:WaitForChild("ModelIcon", 10)) end)
	ModelIcon = ok and mod or nil
end

-- ═══════════ тема «Океан» (README хендоффа) ═══════════
local hex = Color3.fromHex
local C = {
	top = hex("54A7EC"), bottom = hex("3A7FD0"), border = hex("1C4F8F"),
	block = hex("6FB5EE"), blockEdge = hex("2E6BB4"), dark = hex("1C4F8F"), darkRow = hex("2E6BB4"), darkRowEdge = hex("143A6B"),
	idle = hex("2E6BB4"), idleEdge = hex("1C4F8F"), idleText = hex("CFE6FA"), hover = hex("3776C2"),
	caption = hex("A9D6F7"), rowHover = hex("7CBFF2"),
	gold1 = hex("FFD95A"), gold2 = hex("F5B73C"), goldEdge = hex("B07A14"), goldText = hex("6B4A08"), goldText2 = hex("7A4F06"),
	goldPreview = hex("FFF3C9"), value = hex("FFD95A"),
	green1 = hex("5EE07A"), green2 = hex("34B84E"), greenEdge = hex("1F7A33"),
	red1 = hex("FF7A6A"), red2 = hex("E84A3A"), redEdge = hex("A82E2E"),
	busy = hex("5D7D9E"), busyEdge = hex("45627F"), busyPreview = hex("8AA6C2"), busyText = hex("E3EDF6"), busyText2 = hex("C9D6E3"),
	hp = hex("E84A3A"), track = hex("143A6B"), white = Color3.new(1, 1, 1),
}
local COIN_ICON = "rbxassetid://93617165412571"
local FONT, FONT_B = Enum.Font.GothamBlack, Enum.Font.GothamBold

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(p, r) return new("UICorner", { CornerRadius = r and UDim.new(0, r) or UDim.new(0.5, 0) }, p) end
local function stroke(p, color, th) return new("UIStroke", { Color = color, Thickness = th, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p) end
local function grad(p, a, b) return new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = 90 }, p) end
local function label(p, props)
	props.BackgroundTransparency = 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or C.white
	local l = new("TextLabel", props, p)
	if props.TextColor3 == C.white or props.TextColor3 == C.value then
		new("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.7, Thickness = 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	end
	return l
end
--[[ ⚠️ ПОДПИСЬ ГРАДИЕНТНОЙ КНОПКИ — ОТДЕЛЬНЫМ ЛЕЙБЛОМ. UIGradient красит не
     только фон, но и ТЕКСТ своего объекта: белые буквы умножались на зелёный /
     красный / золотой и сливались с кнопкой («Сохранить» и «Выгнать» были
     пустыми). Дочерний лейбл градиенту не подчиняется. ]]
local function caption(btn, text, size, color)
	btn.Text = ""
	return label(btn, { Size = UDim2.fromScale(1, 1), Text = text, TextSize = size, TextColor3 = color or C.white,
		ZIndex = btn.ZIndex + 1 })
end

-- «3D»: тёмная полоска у низа кнопки
local function shade(b, r)
	local s = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.82, BorderSizePixel = 0, ZIndex = b.ZIndex }, b)
	corner(s, r or 10)
end
local function coin(parent, size, order)
	return new("ImageLabel", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Image = COIN_ICON,
		LayoutOrder = order or 0 }, parent)
end
local function hlist(parent, gap, props)
	props = props or {}
	props.BackgroundTransparency = 1
	local f = new("Frame", props, parent)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, gap),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, f)
	return f
end
local function pill(parent, bg, edge, text, size, color, order)
	local f = new("Frame", { Size = UDim2.fromOffset(0, size + 8), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = bg, LayoutOrder = order or 0 }, parent)
	corner(f)
	if edge then stroke(f, edge, 2) end
	new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, f)
	label(f, { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = text, TextSize = size,
		TextColor3 = color or C.white })
	return f
end
local function bar(parent, props, value, color, track)
	local t = new("Frame", props, parent)
	t.BackgroundColor3 = track or C.dark
	t.BorderSizePixel = 0
	corner(t)
	local fill = new("Frame", { Size = UDim2.fromScale(math.clamp(value, 0, 1), 1), BackgroundColor3 = color,
		BorderSizePixel = 0 }, t)
	corner(fill)
	return t, fill
end
local function notify(text, kind)
	if typeof(_G.Notify) == "function" then
		pcall(_G.Notify, { type = kind or "warn", icon = kind == "success" and "ok" or "no", title = "Команда", body = text })
	end
end

-- ═══════════ окно ═══════════
--[[ ⚠️ ПОРЯДОК 91 — НАД ВСЕМИ КНОПКАМИ HUD. Было 12: затемнение накрывало
     только кнопки ниже (Настройки 8, Рюкзак 8), а Квесты/Магазин/Карта (90)
     оставались яркими поверх — выглядело случайно. Теперь гасится весь HUD,
     а светлой остаётся только сама кнопка «Команда» (SurvivorsButtonGui, 92). ]]
local gui = new("ScreenGui", { Name = "SurvivorsGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 91, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
gui:SetAttribute("ModalUI", true)   -- ModalUIUnlocker отпускает курсор

-- затемнение на оба экрана: за меню виден обычный экран игрока, только приглушённый
local dimFull = new("TextButton", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, ZIndex = 0 }, gui)

local root = new("Frame", { Name = "Root", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	BackgroundTransparency = 1 }, gui)
local rootScale = new("UIScale", {}, root)

local state = nil        -- последнее состояние с сервера
local view = "list"      -- "list" | "detail"
local filter = "Все"
local selUid = nil
local draftSalary = {}   -- [uid] = черновик зарплаты до «Сохранить»
local isOpen = false
local shownView = nil    -- какой экран показан: анимация появления — только при смене
local render             -- объявлена ниже

local function fit(w, h)
	root.Size = UDim2.fromOffset(w, h)
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	rootScale.Scale = math.clamp(math.min((vp.Y - 30) / h, (vp.X - 30) / w), 0.35, 1)
end

local function window(parent, w, h, x)
	local f = new("Frame", { Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(w, h), BackgroundColor3 = C.white,
		BorderSizePixel = 0 }, parent)
	grad(f, C.top, C.bottom); corner(f, 18); stroke(f, C.border, 4)
	return f
end

local function closeButton(parent, onClick)
	local b = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(34, 34), BackgroundColor3 = C.white, Text = "", AutoButtonColor = true, ZIndex = 3 }, parent)
	grad(b, C.red1, C.red2); corner(b, 10); stroke(b, C.redEdge, 3); shade(b)
	for _, rot in ipairs({ 45, -45 }) do
		local x = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromOffset(16, 4), BackgroundColor3 = C.white, BorderSizePixel = 0, Rotation = rot, ZIndex = 4 }, b)
		corner(x)
	end
	b.Activated:Connect(onClick)
	return b
end

local function balancePill(parent)
	local f = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -62, 0, 20),
		Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.idle, ZIndex = 3 }, parent)
	corner(f); stroke(f, C.idleEdge, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 12) }, f)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, f)
	coin(f, 20, 1)
	label(f, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2,
		Text = tostring(player:GetAttribute("Pirate") or (state and state.coins) or 0), TextSize = 14 })
end

-- ═══════════ портрет: ViewportFrame + 2D-лицо поверх ═══════════
local portraits = {}   -- живые оверлеи лиц для моргания: { canvas = Frame }
-- моргание 2D-лиц в иконках (рыбак, Cold Cap): { set = function(lid), nextBlink, blinkStart }
local faceBlinks = {}
local parkPortraits    -- ниже (кэш портретов)

local function portrait(parent, def)
	local tpl = def and D.find(def.model)
	if not (tpl and tpl:IsA("Model")) then
		label(parent, { Size = UDim2.fromScale(1, 1), Text = "?", TextSize = 26 })
		return
	end
	local head = tpl:FindFirstChild("Head")
	local face = head and def.face and head:FindFirstChild(def.face)
	-- светлее, чем было: тёмные костюмы (рыбак, Cold Cap) в иконке 60 px сливались с фоном
	local vp = new("ViewportFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		LightDirection = Vector3.new(-0.3, -0.8, -1), Ambient = Color3.fromRGB(205, 205, 212),
		LightColor = Color3.fromRGB(255, 252, 244) }, parent)
	local okClone, clone = pcall(function() return tpl:Clone() end)
	if not okClone or not clone then return end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("SurfaceGui") or d:IsA("BillboardGui") or d:IsA("ProximityPrompt") then d:Destroy() end
	end
	clone.Parent = vp
	local h = clone:FindFirstChild("Head")
	if not h then return end
	-- ⚠️ HD-лицо Cold Cap — SurfaceGui, а во ViewportFrame они не рисуются (и выше
	-- удалены). Decal face у модели — та же картинка V7, только скрытая: показываем
	local FOV = 26
	local look = h.CFrame.LookVector
	local target = h.Position + Vector3.new(0, 0.45, 0)
	local dist = 1.35 / math.tan(math.rad(FOV / 2))
	local camCF = CFrame.lookAt(target + look * dist + Vector3.new(0, 0.15, 0), target)
	local cam = new("Camera", { FieldOfView = FOV, CFrame = camCF }, vp)
	vp.CurrentCamera = cam
	--[[ ⚠️ ЛИЦО-НАКЛЕЙКУ (рыбак, Cold Cap) РИСУЕМ 2D ПОВЕРХ 3D-КАДРА.
	     ViewportFrame рисует 3D в разрешении крошечной иконки — наклейка лица там
	     мылилась. Кладём ту же текстуру картинкой поверх, а 3D-наклейку прячем.
	     ⚠️ КВАДРАТ ПО МЕШУ ГОЛОВЫ, А НЕ ПО ДЕТАЛИ. Голова R6 — деталь 2×1×1, но рисует
	     её меш Head ×1.25: он почти кубик 1.25×1.25, и наклейка натянута на ЕГО
	     перед. Первая версия брала грань детали 2×1 — лицо растягивалось вширь и
	     сплющивалось, глаза «съезжали». ]]
	if not face then
		local dec = h:FindFirstChild("face")
		local tex = (dec and dec:IsA("Decal")) and dec.Texture or ""
		if tex ~= "" then
			dec.Transparency = 1
			local mesh = h:FindFirstChildOfClass("SpecialMesh")
			local k = (mesh and mesh.MeshType == Enum.MeshType.Head) and mesh.Scale.Y or 1.25
			local side = h.Size.Y * k                       -- сторона квадрата лица
			local half, depth = side / 2, side / 2          -- перед меша — на полстороны от центра
			local carrier = clone:FindFirstChild("HDFaceCarrier")
			local tanH0 = math.tan(math.rad(FOV / 2))
			local xs, ys = {}, {}
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					-- у Cold Cap лицо стоит на своей детали HDFaceCarrier — её прямоугольник точнее всего
					local pt = carrier and (carrier.CFrame * CFrame.new(sx * carrier.Size.X / 2, sy * carrier.Size.Y / 2, 0)).Position
						or (h.CFrame * CFrame.new(sx * half, sy * half, -depth)).Position
					local p3 = camCF:PointToObjectSpace(pt)
					table.insert(xs, 0.5 + (p3.X / -p3.Z) / tanH0 * 0.5)
					table.insert(ys, 0.5 - (p3.Y / -p3.Z) / tanH0 * 0.5)
				end
			end
			local x0, x1 = math.min(table.unpack(xs)), math.max(table.unpack(xs))
			local y0, y1 = math.min(table.unpack(ys)), math.max(table.unpack(ys))
			local z = parent.ZIndex + 1
			local holder = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(x0, y0),
				Size = UDim2.fromScale(x1 - x0, y1 - y0), ZIndex = z }, parent)
			if carrier then
				--[[ Cold Cap: картинка V7 — три полосы (брови 0–500, глаза 500–690, рот
				     690–1280 из 1280), как в его HDFaceSync. Моргание — поджатие полосы
				     глаз к середине, теми же долями век. ]]
				local function slice(y, h)
					local crop = new("Frame", { BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = z,
						Position = UDim2.fromScale(0, y / 1280), Size = UDim2.fromScale(1, h / 1280) }, holder)
					new("ImageLabel", { BackgroundTransparency = 1, Image = tex, ZIndex = z,
						Position = UDim2.fromScale(0, -y / h), Size = UDim2.fromScale(1, 1280 / h) }, crop)
					return crop
				end
				slice(0, 500)
				local eyes = slice(500, 190)
				slice(690, 590)
				table.insert(faceBlinks, { set = function(lid)
					local open = ({ [0] = 1, [1] = 0.65, [2] = 0.2, [3] = 0.025 })[lid] or 1
					eyes.Size = UDim2.fromScale(1, 190 / 1280 * open)
					eyes.Position = UDim2.fromScale(0, (500 + 95 * (1 - open)) / 1280)
				end })
			else
				-- рыбак: кадры век Idle_0..Idle_3 из его FaceTextures
				local img = new("ImageLabel", { BackgroundTransparency = 1, Image = tex, Size = UDim2.fromScale(1, 1), ZIndex = z }, holder)
				local ft = tpl:FindFirstChild("FaceTextures")
				local frames = {}
				for lid = 0, 3 do
					local v = ft and ft:FindFirstChild("Idle_" .. lid)
					frames[lid] = (v and v:IsA("StringValue") and v.Value ~= "") and v.Value or nil
				end
				if frames[0] then
					img.Image = frames[0]
					table.insert(faceBlinks, { set = function(lid) img.Image = frames[lid] or frames[0] end })
				end
			end
		end
	end

	-- лицо: проекция грани лица на квадрат портрета (в долях — размер рамки не важен)
	if face and face:IsA("SurfaceGui") then
		local ad = face.Adornee or head
		local relCF = tpl:GetPivot():ToObjectSpace(ad.CFrame)
		local adCF = clone:GetPivot() * relCF
		local size = ad.Size
		local tanH = math.tan(math.rad(FOV / 2))
		local function proj(pt)
			local p = camCF:PointToObjectSpace(pt)
			local depth = -p.Z
			return 0.5 + (p.X / depth) / tanH * 0.5, 0.5 - (p.Y / depth) / tanH * 0.5
		end
		local xs, ys = {}, {}
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				local x, y = proj((adCF * CFrame.new(sx * size.X / 2, sy * size.Y / 2, -size.Z / 2)).Position)
				table.insert(xs, x); table.insert(ys, y)
			end
		end
		local x0, x1 = math.min(table.unpack(xs)), math.max(table.unpack(xs))
		local y0, y1 = math.min(table.unpack(ys)), math.max(table.unpack(ys))
		local holder = new("Frame", { Position = UDim2.fromScale(x0, y0), Size = UDim2.fromScale(x1 - x0, y1 - y0),
			BackgroundTransparency = 1, ClipsDescendants = false, ZIndex = parent.ZIndex + 1 }, parent)
		local canvasSize = face.CanvasSize
		local canvas = new("Frame", { Size = UDim2.fromOffset(canvasSize.X, canvasSize.Y), BackgroundTransparency = 1,
			ZIndex = holder.ZIndex }, holder)
		local sc = new("UIScale", {}, canvas)
		for _, c in ipairs(face:GetChildren()) do
			if c:IsA("GuiObject") then
				local cc = c:Clone()
				cc.Parent = canvas
				for _, g in ipairs(cc:GetDescendants()) do
					if g:IsA("GuiObject") then g.ZIndex = holder.ZIndex + 1 end
				end
				cc.ZIndex = holder.ZIndex + 1
			end
		end
		local function rescale()
			if holder.AbsoluteSize.X > 0 then sc.Scale = holder.AbsoluteSize.X / canvasSize.X / (rootScale.Scale > 0 and rootScale.Scale or 1) end
		end
		holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
		task.defer(rescale)
		table.insert(portraits, { canvas = canvas, seed = math.random() * 10 })
	end
end

--[[ ⚠️ ПОРТРЕТ СОБИРАЕТСЯ ОДИН РАЗ И ЗАРАНЕЕ. ViewportFrame с сотней деталей
     дорисовывается по кускам — сначала было видно только 2D-глаза, потом тело.
     Поэтому портрет каждого персонажа строится при старте на скрытой полке
     (почти целиком за краем экрана — движок его честно дорисует), а список
     только переносит готовый кадр к себе и перед перерисовкой отдаёт обратно. ]]
local portraitShelf = new("ScreenGui", { Name = "SurvivorPortraitShelf", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = -60 }, playerGui)
portraitShelf:SetAttribute("KeepEnabled", true)   -- кэш кадров: стройка его не гасит
local portraitCache = {}   -- [defId] = Frame 60×60
local function parkPortrait(pc)
	pc.Parent = portraitShelf
	pc.Position = UDim2.fromOffset(-56, -56)   -- на экране — уголок 4 px под кнопкой меню Roblox
	pc.Size = UDim2.fromOffset(60, 60)
end
local function getPortrait(defId)
	local pc = portraitCache[defId]
	if pc and pc.Parent then return pc end
	pc = new("Frame", { Name = "Portrait_" .. defId, BackgroundTransparency = 1, ZIndex = 2 }, portraitShelf)
	parkPortrait(pc)
	portrait(pc, D.CATALOG[defId])
	portraitCache[defId] = pc
	return pc
end
parkPortraits = function()
	for _, pc in pairs(portraitCache) do
		if pc.Parent and pc.Parent ~= portraitShelf then parkPortrait(pc) end
	end
end
task.spawn(function()
	for defId, def in pairs(D.CATALOG) do
		for _ = 1, 40 do
			if D.find(def.model) then break end
			task.wait(0.5)
		end
		if D.find(def.model) then getPortrait(defId) end
	end
	--[[ Живое превью — копия модели в мире (ниже), и при первом открытии меню её
	     меши, текстуры и SurfaceAppearance костюма скачивались на глазах: персонаж
	     появлялся по частям. Тянем все ассеты моделей в память заранее, фоном —
	     как иконки инвентаря (AssetPreload). ]]
	local list = {}
	for _, def in pairs(D.CATALOG) do
		local tpl = D.find(def.model)
		if tpl then table.insert(list, tpl) end
	end
	local t0 = os.clock()
	pcall(function() game:GetService("ContentProvider"):PreloadAsync(list) end)
	print(("[Выжившие/клиент] модели превью прогружены заранее: %d за %.1f с"):format(#list, os.clock() - t0))
	--[[ ⚠️ СКАЧАТЬ — МАЛО, НАДО ЕЩЁ И НАРИСОВАТЬ. PreloadAsync кладёт файлы в
	     память, но меш и текстура попадают в видеокарту только при первой
	     отрисовке: страница Розы открывалась, и аксессуары доезжали на глазах, а
	     лица в иконках при первом моргании были пустыми (кадр век рисовался
	     впервые). Поэтому каждую модель капитана рисуем на тёплой полке ModelIcon
	     (ViewportFrame под шторкой, полка не гаснет), а все картинки лиц —
	     кадры FaceTextures, картинки SurfaceGui/Decal, HD-лицо V7 и атлас Cold Cap —
	     там же 2D (ModelIcon.warmImages). ]]
	if ModelIcon then
		local ids, seen = {}, {}
		local function add(id)
			if type(id) == "string" and id ~= "" and not seen[id] then seen[id] = true; table.insert(ids, id) end
		end
		add("rbxassetid://79705652476370")    -- Cold Cap: лицо V7
		add("rbxassetid://103054870643875")   -- Cold Cap: атлас эмоций
		for _, tpl in ipairs(list) do
			pcall(ModelIcon.warm, tpl)
			for _, d in ipairs(tpl:GetDescendants()) do
				if d:IsA("StringValue") and d.Parent and d.Parent.Name == "FaceTextures" then add(d.Value)
				elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then add(d.Image)
				elseif d:IsA("Decal") or d:IsA("Texture") then add(d.Texture) end
			end
		end
		local okW, n = pcall(ModelIcon.warmImages, ids)
		print(("[Выжившие/клиент] капитаны нарисованы заранее: моделей %d, картинок лиц %s"):format(#list, tostring(okW and n or "?")))
	end
end)

-- ═══════════ предпросмотр: живая мини-сцена в мире перед камерой ═══════════
--[[ ⚠️ ПОЧЕМУ НЕ ViewportFrame. В модели ~100 деталей (костюм Rose Couture,
     аксессуары) и 94 сварки. ViewportFrame за кадр дорисовывает лишь часть
     изменившихся деталей: портрет «догружался» по кускам, а живая поза шла на
     5–10 FPS — как её ни двигай (суставами или BulkMoveTo).
     Поэтому превью — настоящая 3D-сцена: уменьшенная копия персонажа (×0.05)
     стоит в мире примерно в метре перед камерой игрока, ровно там, где на
     экране окошко «сцены», а за ней — задник с нарисованной сценой (SurfaceGui).
     В мире всё рисуется на полной частоте, суставы работают как в демо
     (Motor6D.C0 + RoseStudio), лицо — родной SurfaceGui, без 2D-накладки.
     Камеру игрока НЕ трогаем: за меню остаётся его экран. Окошко в панели —
     дыра (панель собрана кусками вокруг), остальной экран притемнён кусками
     вокруг окошка. Пересчёт — каждый кадр сразу после камеры (BindToRenderStep). ]]
local preview = nil   -- { def, model, clone, root, motors, face, backdrop, scene, t, centerOff, H }
--[[ ═══ MENUPOSE COLD CAP — ПЕРЕНОС 1:1 ИЗ ЕГО CorsairAnimator ═══
     Ветка mode=='MenuPose' из handoff_coldcap/scripts/CorsairAnimator.luau вместе с
     преобразованием jointBasis: поза задаётся в «человеческих» осях и переводится
     в оси сустава R6 — Transform = B · поза · B⁻¹. Пишем в Motor6D.Transform
     (как исходник), C0 не трогаем. Демо-управление корнем (root.CFrame от точки
     старта) НЕ переносим: в MenuPose корень всё равно стоит в origin, а место
     в кадре задаёт само превью.
     Корпус развёрнут и наклонён, левая рука поднята вперёд, правая ниже и
     отведена, ноги разведены — и непрерывное дыхание/покачивание. ]]
local CORSAIR_JOINTS = { "RootJoint", "Neck", "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" }
local CORSAIR_BASIS = {
	["RootJoint"] = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	["Neck"] = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	["Left Shoulder"] = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	["Right Shoulder"] = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	["Left Hip"] = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	["Right Hip"] = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
}
local function corsairAng(x, y, z) return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z)) end
local function corsairMenuPose(t)
	local out = {}
	local breath = math.sin(t * 1.85)
	local shift = math.sin(t * .8)
	local gesture = math.sin(t * 1.05)
	out[1] = CFrame.new(.08 * shift, .07 * breath, 0) * corsairAng(-4 + 2 * breath, -18 + 4 * shift, -4 + 2 * shift)
	out[2] = corsairAng(-5 + 3 * breath, 14 + 8 * math.sin(t * .48), 3 - 2 * shift)
	out[3] = corsairAng(72 + 9 * gesture, -18 + 5 * math.sin(t * .7), -32 + 4 * breath)
	out[4] = corsairAng(18 + 5 * math.sin(t * 1.85 + .8), 12, 10 + 3 * breath)
	out[5] = CFrame.new(-.12 - .08 * shift, -.07 * breath, -.12) * corsairAng(5 - 2 * breath, -10 - 2 * shift, -5 - 2 * shift)
	out[6] = CFrame.new(.12 - .08 * shift, -.07 * breath, .12) * corsairAng(-3 - 2 * breath, 8 - 2 * shift, 5 - 2 * shift)
	return out
end

local DIORAMA_SCALE = 0.05
--[[ КАДР «ПО КОЛЕНО, ЧУТЬ СВЕРХУ» (выбрал владелец): в окошке — от шляпы до
     колен, это верхние ~82% роста (колено R6 — около 0.18 высоты от пят). ]]
local FRAME_SPAN    = 0.82   -- какая доля роста видна в окошке
local FRAME_PAD     = 1.10   -- запас над шляпой и под коленями
local FRAME_LIFT    = (1 - FRAME_SPAN) / 2   -- центр кадра выше центра фигуры на эту долю роста
local TILT          = math.rad(-12)   -- «камера чуть выше»: фигура слегка откинута назад

-- затемнение вокруг окошка (в списке — сплошное dimFull)
local dimParts = {}
for i = 1, 4 do
	dimParts[i] = new("Frame", { Name = "DimAround" .. i, BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = dimFull.BackgroundTransparency, BorderSizePixel = 0, Visible = false, ZIndex = 0 }, gui)
	-- клик мимо окна — назад к списку, как у сплошного затемнения
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 0 }, dimParts[i])
	hit.Activated:Connect(function() if _G.SurvivorsBack then _G.SurvivorsBack() end end)
end

local function portraitBackdrop(scene)
	local sky = new("Frame", { Name = "PortraitBackdrop", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 1 }, scene)
	corner(sky, 14)
	grad(sky, hex("467DA6"), hex("B9D5D4"))
	local function layer(x, y, w, h, color, alpha)
		return new("Frame", { Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h),
			BackgroundColor3 = hex(color), BackgroundTransparency = alpha or 0,
			BorderSizePixel = 0, ZIndex = 1 }, sky)
	end
	local sun = layer(.74, .12, .15, .13, "FFE7AA", .15); corner(sun)
	for _, cloud in ipairs({{.06,.22,.31},{.61,.30,.27},{.22,.13,.20}}) do
		local c = layer(cloud[1], cloud[2], cloud[3], .025, "E0E9DE", .55); corner(c)
	end
	local sea = layer(0, .52, 1, .48, "FFFFFF")
	grad(sea, hex("548D9C"), hex("214961"))
	for i = 1, 7 do
		layer((i * .19) % .8, .54 + i * .029, .12 + (i % 3) * .07, .003, "B4D7D0", .55)
	end
	local deck = layer(0, .82, 1, .18, "FFFFFF")
	grad(deck, hex("755D53"), hex("3E3540"))
	for i = 1, 5 do layer(0, .82 + i * .035, 1, .004, "302D39", .35) end
	for _, x in ipairs({.06, .91}) do
		layer(x, .65, .025, .19, "55464A")
		layer(x - .014, .64, .053, .017, "D6B16A")
	end
	layer(0, .70, 1, .018, "76604E")
end


--[[ ⚠️ ДИОРАМА — ЭТО МИР, А НЕ GUI. Всё, что рисуется «поверх всего»
     (BillboardGui с AlwaysOnTop: попап улова, стрелки над брёвнами; Highlight с
     AlwaysOnTop: обводка ресурсов), ложилось прямо на персонажа в окне.
     Пока превью открыто, такие штуки выключаем (и новые тоже), потом включаем. ]]
local overlays = { hidden = {}, conns = {}, active = false }
function overlays.hideOne(d)
	if overlays.hidden[d] then return end
	local top = (d:IsA("BillboardGui") and d.AlwaysOnTop)
		or (d:IsA("Highlight") and d.DepthMode == Enum.HighlightDepthMode.AlwaysOnTop)
	if top and d.Enabled then
		overlays.hidden[d] = true
		d.Enabled = false
	end
end
function overlays.start()
	if overlays.active then return end
	overlays.active = true
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	for _, root in ipairs({ workspace, pg }) do
		for _, d in ipairs(root:GetDescendants()) do overlays.hideOne(d) end
		table.insert(overlays.conns, root.DescendantAdded:Connect(function(d)
			task.defer(function() if overlays.active and d.Parent then overlays.hideOne(d) end end)
		end))
	end
end
function overlays.stop()
	if not overlays.active then return end
	overlays.active = false
	for _, c in ipairs(overlays.conns) do c:Disconnect() end
	overlays.conns = {}
	for d in pairs(overlays.hidden) do
		if d.Parent then d.Enabled = true end
	end
	overlays.hidden = {}
end

local function stopPreview()
	overlays.stop()
	if not preview then return end
	pcall(function() RunService:UnbindFromRenderStep("SurvivorPreview") end)
	if preview.model then preview.model:Destroy() end
	preview = nil
	for _, d in ipairs(dimParts) do d.Visible = false end
end

local updatePreview   -- ниже

local function startPreview(def, scene)
	-- перерисовка той же страницы (зарплата ±): сцена живёт дальше, меняется окошко
	if preview and preview.def == def and preview.model.Parent then
		preview.scene = scene
		return true
	end
	stopPreview()
	overlays.start()
	local tpl = def and D.find(def.model)
	if not (tpl and tpl:IsA("Model")) then return false end
	local okClone, clone = pcall(function() return tpl:Clone() end)
	if not (okClone and clone) then return false end
	--[[ ⚠️ COLD CAP: РЕКВИЗИТ РАБОЧИХ СЦЕН — ВОН ДО ВСЕГО ОСТАЛЬНОГО.
	     WorkProps/WorkScene (кожура, сапоги, ящики…) скрыты, но входят в габарит
	     модели: камера отъезжала по нему, и герой стоял дальше остальных. А
	     незакреплённый реквизит при первом открытии падал и утаскивал кадр. ]]
	if def.hdFace then
		for _, n in ipairs({ "WorkProps", "WorkScene" }) do
			local f = clone:FindFirstChild(n)
			if f then f:Destroy() end
		end
	end
	-- скрипты, нужные и в превью (HD-лицо Cold Cap): включаем, остальные удаляются ниже
	local keepPreview = def.keepScripts and { HDFaceSync = def.keepScripts.HDFaceSync } or {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BaseScript") and keepPreview[d.Name] then
			d.Enabled = true
			d:SetAttribute("PreviewKeep", true)
		end
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BaseScript") and d:GetAttribute("PreviewKeep") then continue end
		-- ⚠️ классическая одежда (Shirt/Pants рыбака) рисуется только при Humanoid:
		-- у таких моделей его оставляем, только прячем имя и полоску здоровья
		if d:IsA("Humanoid") and (def.faceTextures or def.hdFace) then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		elseif d:IsA("BaseScript") or d:IsA("BillboardGui") or d:IsA("ProximityPrompt")
			or d:IsA("Humanoid") or d:IsA("HumanoidDescription") then
			d:Destroy()
		end
	end
	local root = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
	if not root then clone:Destroy() return false end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = d == root
			d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
			d.CastShadow = false; d.Massless = true
		end
	end
	pcall(function() clone:ScaleTo(DIORAMA_SCALE) end)
	--[[ ⚠️ ШЛЯПУ САЖАЕМ НА ГОЛОВУ ЗАНОВО ПОСЛЕ УМЕНЬШЕНИЯ. ScaleTo не масштабирует
	     крепление аксессуара (сварку Humanoid'а): у копии ×0.05 шляпа оставалась
	     на «взрослом» смещении и улетала на ~10 ростов головы вверх — из кадра
	     (диагностика: Handle на 11.5 при голове на 1.5). У рыбака сварки нет
	     вовсе — шляпа падала. Берём позу шляпы относительно головы из шаблона,
	     уменьшаем, ставим и привариваем заново. ]]
	local cHead, tHead = clone:FindFirstChild("Head"), tpl:FindFirstChild("Head")
	local hatSeats = {}   -- { handle, rel } — повторить после входа в мир (Humanoid может приварить своё)
	for _, acc in ipairs(clone:GetChildren()) do
		local handle = acc:IsA("Accessory") and acc:FindFirstChild("Handle")
		local tAcc = tpl:FindFirstChild(acc.Name)
		local tHandle = tAcc and tAcc:FindFirstChild("Handle")
		if cHead and tHead and handle and handle:IsA("BasePart") and tHandle and tHandle:IsA("BasePart") then
			for _, d in ipairs(clone:GetDescendants()) do
				if (d:IsA("JointInstance") or d:IsA("WeldConstraint")) and (d.Part0 == handle or d.Part1 == handle) then d:Destroy() end
			end
			local rel = tHead.CFrame:ToObjectSpace(tHandle.CFrame)
			handle.CFrame = cHead.CFrame * CFrame.new(rel.Position * DIORAMA_SCALE) * rel.Rotation
			new("WeldConstraint", { Part0 = handle, Part1 = cHead }, handle)
			table.insert(hatSeats, { handle, rel })
		end
	end
	local motors = {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Motor6D") then motors[d] = d.C0 end
	end
	local cf, size = clone:GetBoundingBox()
	--[[ ⚠️ COLD CAP: КАДР ПО РОСТУ ТЕЛА, А НЕ ПО ГАБАРИТУ С ШЛЯПОЙ. У него высокая
	     треуголка (2.2 стада над головой), и по габариту модели он выходил выше
	     Розы — камера отъезжала, а надбавка ×1.2 для обычного R6 (ниже) отодвигала
	     ещё дальше: стоял заметно дальше остальных. Берём рост от подошв до макушки
	     + полголовы на шляпу; надбавку ему не даём (menuPose). ]]
	local bodyH
	if def.menuPose then
		local headP = clone:FindFirstChild("Head")
		local legs = { clone:FindFirstChild("Left Leg"), clone:FindFirstChild("Right Leg") }
		if headP and legs[1] and legs[2] then
			local top = root.CFrame:PointToObjectSpace(headP.Position).Y + headP.Size.Y / 2
			local bottom = math.huge
			for _, l in ipairs(legs) do
				bottom = math.min(bottom, root.CFrame:PointToObjectSpace(l.Position).Y - l.Size.Y / 2)
			end
			bodyH = (top - bottom) + headP.Size.Y * 0.5
		end
	end

	local model = new("Model", { Name = "SurvivorPreviewScene" })
	clone.Parent = model
	-- задник: та же нарисованная сцена, что раньше была в окошке, но в мире
	local backdrop = new("Part", { Name = "Backdrop", Anchored = true, CanCollide = false, CanQuery = false,
		CanTouch = false, CastShadow = false, Transparency = 1, Size = Vector3.new(0.1, 0.1, 0.001) }, model)
	local sg = new("SurfaceGui", { Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(272, 320), LightInfluence = 0, Adornee = backdrop }, backdrop)
	portraitBackdrop(sg)
	new("PointLight", { Brightness = 2, Range = size.Y * 3, Color = Color3.fromRGB(255, 244, 228) }, root)
	model.Parent = workspace
	task.defer(function()
		for _, seat in ipairs(hatSeats) do
			local handle, rel = seat[1], seat[2]
			for _, d in ipairs(clone:GetDescendants()) do
				if (d:IsA("JointInstance") or d:IsA("WeldConstraint")) and (d.Part0 == handle or d.Part1 == handle) then d:Destroy() end
			end
			if handle.Parent and cHead.Parent then
				handle.CFrame = cHead.CFrame * CFrame.new(rel.Position * DIORAMA_SCALE) * rel.Rotation
				new("WeldConstraint", { Part0 = handle, Part1 = cHead }, handle)
			end
		end
	end)

	-- Cold Cap: тело — MenuPose, лицо — Idle (разные состояния). Ставим ОДИН раз при
	-- открытии: время позы считается от ActionStartedAt, сброс каждый кадр её бы замораживал
	if def.menuPose == "Corsair" then
		clone:SetAttribute("ActionStartedAt", workspace:GetServerTimeNow())
		clone:SetAttribute("Action", "MenuPose")
		local cf2 = clone:FindFirstChild("CharacterFace")
		if cf2 and cf2:IsA("ModuleScript") then
			pcall(function() require(cf2).Set(clone, "Idle") end)
		end
	end
	local head = clone:FindFirstChild("Head")
	local p0
	preview = { def = def, model = model, clone = clone, root = root, motors = motors, scene = scene, t = 0,
		face = head and def.face and head:FindFirstChild(def.face) or nil, backdrop = backdrop,
		centerOff = root.CFrame:ToObjectSpace(cf), H = bodyH or size.Y, W = math.max(size.X, size.Z), parts = {} }
	p0 = preview
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then table.insert(preview.parts, d) end
	end
	for _, d in ipairs(dimParts) do d.Visible = true end
	-- разовая диагностика превью: где детали и чем скрыты (рука/шляпа рыбака пропадали)
	task.delay(1.5, function()
		if preview ~= p0 then return end
		local lines = {}
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				local rel = root.CFrame:PointToObjectSpace(d.Position) / DIORAMA_SCALE
				table.insert(lines, ("%s[T%.2f L%.2f %s] (%.1f, %.1f, %.1f)"):format(d.Name, d.Transparency,
					d.LocalTransparencyModifier, d:IsDescendantOf(workspace) and "мир" or "НЕ В МИРЕ", rel.X, rel.Y, rel.Z))
			end
		end
		print("[Выжившие/превью] " .. def.name .. ": " .. table.concat(lines, " | "))
	end)
	RunService:BindToRenderStep("SurvivorPreview", Enum.RenderPriority.Camera.Value + 1, function(dt)
		updatePreview(dt)
	end)
	return true
end

function updatePreview(dt)
	local p = preview
	if not p then return end
	if not (p.model.Parent and p.scene.Parent) then stopPreview() return end
	p.t += dt
	-- поза и мимика (RoseStudio): Signature Idle, в середине — подмигивание.
	-- Клипы RoseStudio — под её «свой» R6 (retarget); обычный R6 (рыбак) стоит
	-- в покое, лицо ему ведёт FishermanFaceAnimator
	--[[ Клипы RoseStudio записаны под её «свой» R6: у суставов нет стандартных
	     поворотов C0. Обычному R6 (рыбак) ту же позу даём пересчётом в оси его
	     сустава: R⁻¹ · поза · R, где R — поворот C0 (у R6 он равен повороту C1). ]]
	if p.def.menuPose == "Corsair" then
		-- ⚠️ ОДИН КОНТРОЛЛЕР ПОЗЫ: Animate/клипы удалены (скрипты вычищены выше, Animator
		-- у копии ничего не играет), C0 не трогаем — только Transform, как исходник
		local t = math.max(0, workspace:GetServerTimeNow() - (p.clone:GetAttribute("ActionStartedAt") or 0))
		local blend = math.clamp(t / .45, 0, 1)
		blend = blend * blend * (3 - 2 * blend)
		local pose = corsairMenuPose(t)
		for i, name in ipairs(CORSAIR_JOINTS) do
			local j = p.corsairJoints and p.corsairJoints[i]
			if not j then
				p.corsairJoints = p.corsairJoints or {}
				j = p.clone:FindFirstChild(name, true)
				p.corsairJoints[i] = j
			end
			if j and j:IsA("Motor6D") then
				local q = CFrame.identity:Lerp(pose[i], blend)
				q = CFrame.new(q.Position * DIORAMA_SCALE) * q.Rotation   -- смещения — в масштабе копии
				local B = CORSAIR_BASIS[name]
				j.Transform = B * q * B:Inverse()
			end
		end
	elseif p.def.profile then
		-- свой процедурный idle персонажа (CharacterPoses: профиль "Pirate" и т.п.)
		p.poser = p.poser or require(ReplicatedStorage:WaitForChild("CharacterPoses")).new(p.def.profile)
		local deltas = p.poser:Step(p.clone, p.t)
		for motor, base in pairs(p.motors) do
			local d = deltas[motor.Name]
			if d then
				d = CFrame.new(d.Position * DIORAMA_SCALE) * d.Rotation   -- смещения — в масштабе копии
				motor.C0 = CFrame.new(base.Position) * d * base.Rotation
			end
		end
	elseif Rose then
		local clip = Rose.Clips[1]
		local t = p.t % clip[2]
		local poses = Rose.Pose(clip[1], t)
		local k = math.min(1, dt * 12)
		for motor, base in pairs(p.motors) do
			local pose = poses[motor.Name]
			if pose then
				-- смещения позы — в масштабе уменьшенной модели
				pose = CFrame.new(pose.Position * DIORAMA_SCALE) * pose.Rotation
				if not p.def.retarget then
					local R = base.Rotation
					pose = R:Inverse() * pose * R
				end
				motor.C0 = motor.C0:Lerp(base * pose, k)
			end
		end
		if p.face then
			local emotion = (t > 4.8 and t < 6.2) and "Wink" or clip[3]
			pcall(Rose.Expression, p.face, emotion, p.t, false)
		end
	end

	-- место на экране — окошко сцены
	local cam = workspace.CurrentCamera
	local vp = cam.ViewportSize
	--[[ ⚠️ AbsolutePosition ОТСЧИТЫВАЕТСЯ ОТ НИЖНЕЙ КРОМКИ ВЕРХНЕЙ ПАНЕЛИ ROBLOX —
	     даже у ScreenGui с IgnoreGuiInset, — а камера считает от верха экрана.
	     Без поправки Роза и задник уезжали вверх на высоту панели: шляпа
	     обрезана, снизу в окошке виден мир. ]]
	local inset = GuiService:GetGuiInset()
	local sPos, sSize = p.scene.AbsolutePosition + inset, p.scene.AbsoluteSize
	if sSize.Y < 4 or vp.Y < 4 then return end
	local tanH = math.tan(math.rad(cam.FieldOfView / 2))
	local dist = p.H * FRAME_SPAN * FRAME_PAD * vp.Y / (sSize.Y * 2 * tanH)
	-- и по ширине: шляпа с полями и сабля должны влезать с запасом
	dist = math.max(dist, p.W * 1.15 * vp.Y / (sSize.X * 2 * tanH))
	-- рыбак (обычный R6) в кадре выходил крупнее Розы: шляпа и рука задевали край
	-- окошка, и отсечение ниже прятало их целиком — отодвигаем
	if not p.def.retarget and not p.def.menuPose then dist = dist * 1.2 end
	local pps = vp.Y / (2 * dist * tanH)
	local cx, cy = sPos.X + sSize.X / 2, sPos.Y + sSize.Y / 2
	local ox, oy = (cx - vp.X / 2) / pps, -(cy - vp.Y / 2) / pps
	local camCF = cam.CFrame
	--[[ ⚠️ ЛИЦОМ К САМОЙ КАМЕРЕ, А НЕ К ПЛОСКОСТИ ЭКРАНА. Окошко сбоку от центра
	     экрана: поверни её «параллельно камере» — и из-за перспективы видно
	     наискосок, сбоку. Смотрит прямо на точку камеры, «верх» — как у камеры,
	     и чуть откинута назад — «камера выше». ]]
	local pos = (camCF * CFrame.new(ox, oy, -dist)).Position
	-- центр окошка — между шляпой и коленями: середина фигуры чуть ниже его
	local center = CFrame.lookAt(pos, camCF.Position, camCF.UpVector) * CFrame.Angles(-TILT, 0, 0)
		* CFrame.new(0, -p.H * FRAME_LIFT, 0)
	p.root.CFrame = center * p.centerOff:Inverse()
	-- задник: ровно во всё окошко, чуть дальше модели
	local db = dist + p.H * 0.9
	local k = db / dist
	local winH = sSize.Y * 2 * db * tanH / vp.Y
	local winW = winH * sSize.X / sSize.Y
	--[[ ⚠️ ЗАДНИК — ПАРАЛЛЕЛЬНО ЭКРАНУ И ПОЧТИ БЕЗ ЗАПАСА. Он в мире, обрезать его
	     нечем: всё, что шире окошка, закрывает только рамка панели (14 px), а
	     дальше вылезало за меню. Параллельный экрану прямоугольник проецируется
	     ровно в окошко; 3% запаса прячутся под рамкой. ]]
	p.backdrop.Size = Vector3.new(winW * 1.03, winH * 1.03, 0.001)
	local bpos = (camCF * CFrame.new(ox * k, oy * k, -db)).Position
	p.backdrop.CFrame = CFrame.new(bpos) * camCF.Rotation * CFrame.Angles(0, math.pi, 0)   -- лицевой гранью к камере

	local x0, y0, x1, y1 = sPos.X, sPos.Y, sPos.X + sSize.X, sPos.Y + sSize.Y

	--[[ ⚠️ ОТСЕЧЕНИЕ ПО ОКОШКУ. Сцена — в мире, и обрезать её по рамке нечем:
	     всё, что вышло за окошко дальше, чем закрывает рамка панели (~14 px),
	     торчало за меню (взмах сабли, поля шляпы). Каждый кадр проецируем
	     углы каждой детали на экран; деталь, которая высовывается за край
	     сильнее рамки, прячем. Ниже окошка — не прячем: там вся панель
	     (здоровье, бонусы), она закрывает ноги целиком. ]]
	local tol = 12 * (rootScale.Scale > 0 and rootScale.Scale or 1)
	local tanW = tanH * vp.X / vp.Y
	local panelBottom = y1 + 300 * (rootScale.Scale > 0 and rootScale.Scale or 1)
	-- рыбак (обычный R6): кадр отодвинут с запасом, отсечение ему не нужно —
	-- у него оно прятало шляпу и руку целиком
	local cullOn = p.def.retarget == true
	for _, part in ipairs(p.parts) do
		local pcf, half = part.CFrame, part.Size / 2
		local out = false
		if not cullOn then
			part.LocalTransparencyModifier = 0
			continue
		end
		for _, c in ipairs({ Vector3.new(1, 1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, -1, 1), Vector3.new(1, 1, -1),
			Vector3.new(-1, -1, 1), Vector3.new(-1, 1, -1), Vector3.new(1, -1, -1), Vector3.new(-1, -1, -1) }) do
			local q = camCF:PointToObjectSpace(pcf:PointToWorldSpace(half * c))
			local depth = -q.Z
			if depth <= 0.01 then out = true break end
			local sx = vp.X / 2 + (q.X / depth) / tanW * vp.X / 2
			local sy = vp.Y / 2 - (q.Y / depth) / tanH * vp.Y / 2
			if sx < x0 - tol or sx > x1 + tol or sy < y0 - tol or sy > panelBottom then out = true break end
		end
		part.LocalTransparencyModifier = out and 1 or 0
	end

	-- затемнение вокруг окошка
	dimParts[1].Position = UDim2.fromOffset(0, 0); dimParts[1].Size = UDim2.new(1, 0, 0, y0)
	dimParts[2].Position = UDim2.fromOffset(0, y1); dimParts[2].Size = UDim2.new(1, 0, 1, -y1)
	dimParts[3].Position = UDim2.fromOffset(0, y0); dimParts[3].Size = UDim2.fromOffset(x0, y1 - y0)
	dimParts[4].Position = UDim2.fromOffset(x1, y0); dimParts[4].Size = UDim2.new(1, -x1, 0, y1 - y0)
end

-- ═══════════ данные ═══════════
local function fetch()
	local ok, st = pcall(function() return rf:InvokeServer("state") end)
	if ok and type(st) == "table" then state = st end
end

local function call(action, a1, a2)
	local ok, res = pcall(function() return rf:InvokeServer(action, a1, a2) end)
	if not ok or type(res) ~= "table" then notify("Сервер не ответил") return false end
	if res.state then state = res.state end
	if not res.ok and res.why then notify(res.why) end
	return res.ok == true
end

local function survivorBy(uid)
	for _, s in ipairs(state and state.survivors or {}) do
		if s.uid == uid then return s end
	end
	return nil
end

-- ═══════════ A. СПИСОК ═══════════
local FILTERS = { "Все", "Работают", "Отдыхают", "Недовольны" }

local function buildList()
	local W1, W2, H, GAP = 230, 600, 560, 16
	fit(W1 + GAP + W2, H)

	-- сайдбар
	local side = window(root, W1, H, 0)
	new("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14) }, side)
	new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, side)
	label(side, { Size = UDim2.new(1, 0, 0, 26), Text = "Команда", TextSize = 19, LayoutOrder = 1 })
	local total = 0
	for _, s in ipairs(state.survivors) do total += s.salary end
	for i, info in ipairs({ { "ВЫЖИВШИХ", ("%d / %d"):format(#state.survivors, state.max) }, { "ЗАРПЛАТЫ / ДЕНЬ", tostring(total), true } }) do
		local box = new("Frame", { Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = C.dark, LayoutOrder = 1 + i }, side)
		corner(box, 12)
		label(box, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 14), Text = info[1], TextSize = 12,
			TextColor3 = C.caption })
		local row = hlist(box, 6, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24),
			Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X })
		if info[3] then coin(row, 20, 1) end
		label(row, { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Text = info[2],
			TextSize = info[3] and 22 or 24, TextColor3 = C.value, LayoutOrder = 2 })
	end
	local fl = new("Frame", { Size = UDim2.new(1, 0, 0, 4 * 44 + 3 * 10), BackgroundTransparency = 1, LayoutOrder = 5 }, side)
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, fl)
	for i, name in ipairs(FILTERS) do
		local active = name == filter
		local b = new("TextButton", { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = active and C.white or C.idle,
			Text = name, Font = FONT, TextSize = 16, TextColor3 = active and C.white or C.idleText, AutoButtonColor = not active,
			LayoutOrder = i }, fl)
		corner(b, 12); stroke(b, active and C.goldEdge or C.idleEdge, 3); shade(b, 12)
		if active then grad(b, C.gold1, C.gold2); caption(b, name, 16) end
		b.Activated:Connect(function() filter = name; render() end)
	end

	-- окно списка
	local main = window(root, W2, H, W1 + GAP)
	label(main, { Position = UDim2.fromOffset(16, 16), Size = UDim2.new(1, -220, 0, 34), Text = "Выжившие", TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left })
	balancePill(main)
	closeButton(main, function() _G.CloseSurvivors() end)
	local scroll = new("ScrollingFrame", { Position = UDim2.fromOffset(16, 64), Size = UDim2.new(1, -32, 1, -80),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollBarImageColor3 = C.border,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, main)
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 9) }, scroll)

	local n = 0
	for _, s in ipairs(state.survivors) do
		local working = s.buildingId ~= nil
		local show = filter == "Все" or (filter == "Работают" and working) or (filter == "Отдыхают" and not working)
			or (filter == "Недовольны" and s.mood < 35)
		if show then
			n += 1
			local def = D.CATALOG[s.def]
			local lc = D.levelColor(s.level)
			-- имя SurvivorRow ищет TeamQuestHint (подсказка «Первый житель»)
			local row = new("TextButton", { Name = "SurvivorRow", Size = UDim2.new(1, 0, 0, 86), BackgroundColor3 = C.block, Text = "",
				AutoButtonColor = false, LayoutOrder = n }, scroll)
			corner(row, 14); stroke(row, C.blockEdge, 3)
			row.MouseEnter:Connect(function() row.BackgroundColor3 = C.rowHover end)
			row.MouseLeave:Connect(function() row.BackgroundColor3 = C.block end)
			local pf = new("Frame", { Position = UDim2.fromOffset(14, 13), Size = UDim2.fromOffset(60, 60),
				BackgroundColor3 = C.caption, ClipsDescendants = true, ZIndex = 2 }, row)
			corner(pf, 12); stroke(pf, lc, 3)
			local pc = getPortrait(s.def)   -- готовый, с полки
			pc.Parent = pf
			pc.Position = UDim2.new()
			pc.Size = UDim2.fromScale(1, 1)
			local top = hlist(row, 8, { Position = UDim2.fromOffset(88, 12), Size = UDim2.new(1, -250, 0, 24) })
			label(top, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Text = s.name, TextSize = 17, LayoutOrder = 1 })
			pill(top, lc, nil, "Ур. " .. s.level, 11, C.white, 2)
			local low = hlist(row, 8, { Position = UDim2.fromOffset(88, 44), Size = UDim2.new(1, -250, 0, 24) })
			pill(low, C.idle, C.idleEdge, s.job, 12, C.white, 1)
			local b1 = s.bonuses[1]
			if b1 then
				local bp = pill(low, C.white, C.goldEdge, b1.value .. " " .. (b1.label:match("^(%S+)") or ""):lower(), 11, C.goldText, 2)
				grad(bp, C.gold1, C.gold2)
			end
			local sp = new("Frame", { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = C.idle, LayoutOrder = 3 }, low)
			corner(sp); stroke(sp, C.idleEdge, 2)
			new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 10) }, sp)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5),
				VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, sp)
			coin(sp, 16, 1)
			label(sp, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Text = s.salary .. " / день",
				TextSize = 12, TextColor3 = C.value, LayoutOrder = 2 })
			-- настроение из строки списка убрано: в карточке выжившего оно есть,
			-- а здесь только занимало место. Само настроение считается как считалось
			-- (D.mood → скорость работы), просто не показывается в списке.
			local go = new("TextLabel", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(34, 34), BackgroundColor3 = C.white, Text = "›", Font = FONT, TextSize = 20,
				TextColor3 = C.white }, row)
			grad(go, C.gold1, C.gold2); corner(go, 10); stroke(go, C.goldEdge, 3); caption(go, "›", 20)
			row.Activated:Connect(function()
				selUid = s.uid
				view = "detail"
				render()
			end)
		end
	end
	if n == 0 then
		label(scroll, { Size = UDim2.new(1, 0, 0, 40), Text = #state.survivors == 0 and "В команде пока никого нет"
			or "В этом фильтре пусто", TextSize = 16, TextColor3 = C.idleText })
	end
end

-- ═══════════ подтверждение «Выгнать» ═══════════
local function confirmFire(s)
	local modal = new("TextButton", { Name = "Confirm", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4, Text = "", AutoButtonColor = false, ZIndex = 50 }, gui)
	local box = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 170), BackgroundColor3 = C.white, ZIndex = 51 }, modal)
	grad(box, C.top, C.bottom); corner(box, 18); stroke(box, C.border, 4)
	new("UIScale", { Scale = rootScale.Scale }, box)
	label(box, { Position = UDim2.fromOffset(16, 18), Size = UDim2.new(1, -32, 0, 28), Text = "Выгнать " .. s.name .. "?",
		TextSize = 19, ZIndex = 52 })
	label(box, { Position = UDim2.fromOffset(16, 50), Size = UDim2.new(1, -32, 0, 36), TextWrapped = true,
		Text = "Капитан уйдёт из команды насовсем, место в здании освободится", TextSize = 13, TextColor3 = C.dark, ZIndex = 52 })
	local function btn(text, x, w, c1, c2, edge, fn)
		local b = new("TextButton", { Position = UDim2.fromOffset(x, 106), Size = UDim2.fromOffset(w, 46), BackgroundColor3 = C.white,
			Text = text, Font = FONT, TextSize = 16, TextColor3 = C.white, ZIndex = 52 }, box)
		grad(b, c1, c2); corner(b, 12); stroke(b, edge, 3); shade(b, 12); caption(b, text, 16)
		b.Activated:Connect(fn)
	end
	btn("Отмена", 16, 166, C.idle, C.idle, C.idleEdge, function() modal:Destroy() end)
	btn("Выгнать", 198, 166, C.red1, C.red2, C.redEdge, function()
		modal:Destroy()
		if call("fire", s.uid) then
			notify(s.name .. " покинул команду", "success")
			view = "list"
			selUid = nil
			render()
		end
	end)
	modal.Activated:Connect(function() modal:Destroy() end)
end

-- ═══════════ B. СТРАНИЦА ВЫЖИВШЕГО ═══════════

local function buildDetail(s)
	local def = D.CATALOG[s.def]
	local lc = D.levelColor(s.level)
	local salary = draftSalary[s.uid] or s.salary
	local resting = s.buildingId == nil
	local mood = D.mood(def, salary, resting)

	-- высота правого окна зависит от числа зданий (сетка в 3 колонки)
	local buildings = state.buildings or {}
	local rows = math.max(1, math.ceil(#buildings / 3))
	local CARD_H = 196
	local jobH = 12 + 22 + 10 + rows * CARD_H + (rows - 1) * 8 + (resting and 0 or 44) + 14 + 6
	local rightH = 16 + 34 + 14 + jobH + 14 + 108 + 14 + 56 + 14 + 50 + 16
	local H = math.max(640, rightH)
	local WL, WR, GAP = 300, 560, 16
	fit(WL + GAP + WR, H)

	-- ── левое окно: собрано из кусков вокруг окошка сцены — в окошке видна
	--    мини-сцена в мире (см. «предпросмотр») ──
	local SCENE_Y, SCENE_H, PAD = 60, 320, 14
	local left = new("Frame", { Size = UDim2.fromOffset(WL, H), BackgroundTransparency = 1 }, root)
	corner(left, 18); stroke(left, C.border, 4)
	local function piece(x, y, w, h, round)
		local pc = new("Frame", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = C.white,
			BorderSizePixel = 0 }, left)
		grad(pc, C.top:Lerp(C.bottom, y / H), C.top:Lerp(C.bottom, (y + h) / H))
		if round then corner(pc, 18) end
	end
	piece(0, 0, WL, SCENE_Y, true); piece(0, 20, WL, SCENE_Y - 20)
	piece(0, SCENE_Y + SCENE_H, WL, H - SCENE_Y - SCENE_H, true); piece(0, SCENE_Y + SCENE_H, WL, 20)
	piece(0, SCENE_Y, PAD, SCENE_H); piece(WL - PAD, SCENE_Y, PAD, SCENE_H)
	-- шапка
	local back = new("TextButton", { Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = C.idle,
		Text = "‹", Font = FONT, TextSize = 22, TextColor3 = C.white, ZIndex = 3 }, left)
	corner(back, 10); stroke(back, C.idleEdge, 3); shade(back)
	back.Activated:Connect(function() view = "list"; render() end)
	label(left, { Position = UDim2.fromOffset(58, 14), Size = UDim2.new(1, -72, 0, 34), Text = s.name, TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	-- окошко сцены: свой кадр с камерой, модель рисуется внутри него
	local scene = new("Frame", { Position = UDim2.fromOffset(PAD, SCENE_Y), Size = UDim2.fromOffset(WL - PAD * 2, SCENE_H),
		BackgroundTransparency = 1, ZIndex = 2 }, left)
	stroke(scene, lc, 3)
	local lvl = pill(scene, lc, Color3.new(1, 1, 1), "Ур. " .. s.level, 12, C.white)
	lvl.Position = UDim2.fromOffset(10, 10); lvl.ZIndex = 3
	if not startPreview(def, scene) then
		-- сцены нет в мире — хотя бы портрет
		local fallback = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.idle, ZIndex = 2 }, scene)
		portrait(fallback, def)
	end

	-- здоровье / настроение
	local yStats = SCENE_Y + SCENE_H + 12
	for i, info in ipairs({ { "ЗДОРОВЬЕ", s.hp / 100, C.hp }, { "НАСТРОЕНИЕ", mood / 100, D.moodColor(mood) } }) do
		local box = new("Frame", { Position = UDim2.fromOffset(PAD + (i - 1) * 140, yStats), Size = UDim2.fromOffset(132, 50),
			BackgroundColor3 = C.dark, ZIndex = 3 }, left)
		corner(box, 12)
		label(box, { Position = UDim2.fromOffset(10, 7), Size = UDim2.new(1, -20, 0, 14), Text = info[1], TextSize = 11,
			TextColor3 = C.caption, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
		local t = bar(box, { Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 0, 10), ZIndex = 4 }, info[2], info[3], C.track)
		t.ZIndex = 4
		for _, c in ipairs(t:GetChildren()) do if c:IsA("GuiObject") then c.ZIndex = 4 end end
	end
	-- бонусы капитана
	local yB = yStats + 62
	local bonus = new("Frame", { Position = UDim2.fromOffset(PAD, yB), Size = UDim2.new(1, -PAD * 2, 0, H - yB - PAD),
		BackgroundColor3 = C.dark, ZIndex = 3 }, left)
	corner(bonus, 14)
	new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, bonus)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, bonus)
	label(bonus, { Size = UDim2.new(1, 0, 0, 14), Text = "БОНУСЫ КАПИТАНА", TextSize = 12, TextColor3 = C.caption,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	for i, b in ipairs(s.bonuses) do
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = C.darkRow, LayoutOrder = i, ZIndex = 4 }, bonus)
		corner(row, 10); stroke(row, C.darkRowEdge, 2)
		local circle = new("TextLabel", { Position = UDim2.fromOffset(8, 7), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = C.white,
			Text = b.sign, Font = FONT, TextSize = 13, TextColor3 = C.goldText, ZIndex = 5 }, row)
		grad(circle, C.gold1, C.gold2); corner(circle); stroke(circle, C.goldEdge, 2); caption(circle, b.sign, 13, C.goldText)
		label(row, { Position = UDim2.fromOffset(48, 4), Size = UDim2.new(1, -130, 0, 20), Text = b.value, TextSize = 15,
			TextColor3 = C.value, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 })
		label(row, { Position = UDim2.fromOffset(48, 23), Size = UDim2.new(1, -130, 0, 16), Text = b.label, TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
		local tag = pill(row, D.tagColor(b.type), nil, b.type, 10, C.white)
		tag.AnchorPoint = Vector2.new(1, 0.5); tag.Position = UDim2.new(1, -8, 0.5, 0); tag.ZIndex = 5
	end

	-- ── правое окно: управление ──
	local right = window(root, WR, H, WL + GAP)
	label(right, { Position = UDim2.fromOffset(16, 16), Size = UDim2.new(1, -220, 0, 34), Text = "Управление", TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left })
	balancePill(right)
	closeButton(right, function() view = "list"; render() end)

	local inner = WR - 32
	local y = 16 + 34 + 14
	-- Место работы
	local job = new("Frame", { Position = UDim2.fromOffset(16, y), Size = UDim2.fromOffset(inner, jobH), BackgroundColor3 = C.block }, right)
	corner(job, 14); stroke(job, C.blockEdge, 3)
	local jobHint = resting and "сейчас отдыхает — выберите здание" or ("сейчас: " .. s.job)
	local th = hlist(job, 8, { Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -28, 0, 22) })
	label(th, { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Text = "Место работы", TextSize = 16, LayoutOrder = 1 })
	label(th, { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Text = jobHint, TextSize = 12,
		TextColor3 = C.dark, LayoutOrder = 2 })
	local gridY = 12 + 22 + 10
	local colW = (inner - 28 - 16) / 3
	if #buildings == 0 then
		label(job, { Position = UDim2.fromOffset(14, gridY + 40), Size = UDim2.new(1, -28, 0, 60), TextWrapped = true,
			Text = "На плоту пока нет зданий с рабочими местами.\nПострой ферму — дом фермера рядом с участком земли.",
			TextSize = 14, TextColor3 = C.dark })
	end
	for i, b in ipairs(buildings) do
		local col, rowI = (i - 1) % 3, math.floor((i - 1) / 3)
		local here = s.buildingId == b.id
		local full = not here and b.used >= b.cap
		local card = new("TextButton", { Name = "BuildingCard_" .. tostring(b.kind),   -- имя ищет TeamQuestHint
			Position = UDim2.fromOffset(14 + col * (colW + 8), gridY + rowI * (CARD_H + 8)),
			Size = UDim2.fromOffset(colW, CARD_H), BackgroundColor3 = here and C.white or (full and C.busy or C.idle),
			Text = "", AutoButtonColor = false, BackgroundTransparency = full and 0.2 or 0 }, job)
		corner(card, 12); stroke(card, here and C.goldEdge or (full and C.busyEdge or C.idleEdge), 3)
		if here then grad(card, C.gold1, C.gold2) end
		if not here then shade(card, 12) end
		local prev = new("Frame", { Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 0, 124),
			BackgroundColor3 = here and C.goldPreview or (full and C.busyPreview or C.caption), ClipsDescendants = true }, card)
		corner(prev, 9); stroke(prev, here and C.goldEdge or (full and C.busyEdge or C.idleEdge), 2)
		-- превью: само здание с плота
		if ModelIcon and typeof(b.hut) == "Instance" and b.hut.Parent then
			local vp = ModelIcon.render(prev, b.hut)
			if vp then
				vp.Size = UDim2.fromScale(0.94, 0.94)
				-- общий ракурс ModelIcon смотрел на дом фермера сзади: облетаем на 180°
				local cam = vp.CurrentCamera
				local m = vp:FindFirstChildWhichIsA("Model") or vp:FindFirstChildWhichIsA("BasePart")
				if cam and m and b.kind == "farm" then
					local center = m:IsA("Model") and m:GetBoundingBox().Position or m.Position
					local pivot = CFrame.new(center)
					cam.CFrame = pivot * CFrame.Angles(0, math.pi, 0) * pivot:ToObjectSpace(cam.CFrame)
				end
			end
		end
		if here or full then
			local tag = pill(prev, here and C.greenEdge or C.hp, nil, here and "ЗДЕСЬ" or "ЗАНЯТО", 10, C.white)
			tag.AnchorPoint = Vector2.new(1, 0); tag.Position = UDim2.new(1, -4, 0, 4); tag.ZIndex = 3
		end
		label(card, { Position = UDim2.fromOffset(8, 136), Size = UDim2.new(1, -16, 0, 16), Text = b.name, TextSize = 13,
			TextColor3 = full and C.busyText or C.white, TextXAlignment = Enum.TextXAlignment.Left })
		label(card, { Position = UDim2.fromOffset(8, 156), Size = UDim2.new(0.62, -8, 0, 14), Text = b.place, TextSize = 11,
			TextColor3 = here and C.goldText2 or (full and C.busyText2 or C.caption), TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd })
		label(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 156), Size = UDim2.new(0.38, 0, 0, 14),
			Text = ("%d / %d мест"):format(b.used, b.cap), TextSize = 11,
			TextColor3 = here and C.goldText or (full and C.busyText or C.value), TextXAlignment = Enum.TextXAlignment.Right })
		local seats = new("Frame", { Position = UDim2.fromOffset(8, 176), Size = UDim2.new(1, -16, 0, 6), BackgroundTransparency = 1 }, card)
		local sw = 1 / b.cap
		for k = 1, b.cap do
			local taken = k <= b.used
			local seat = new("Frame", { Position = UDim2.new((k - 1) * sw, k > 1 and 2 or 0, 0, 0),
				Size = UDim2.new(sw, k > 1 and -3 or -1, 1, 0),
				BackgroundColor3 = taken and (here and C.greenEdge or C.value) or C.track, BorderSizePixel = 0 }, seats)
			corner(seat)
		end
		if not full and not here then
			card.MouseEnter:Connect(function() card.BackgroundColor3 = C.hover end)
			card.MouseLeave:Connect(function() card.BackgroundColor3 = C.idle end)
			card.Activated:Connect(function()
				local sc = new("UIScale", { Scale = 0.96 }, card)
				TweenService:Create(sc, TweenInfo.new(0.12), { Scale = 1 }):Play()
				if call("assign", s.uid, b.id) then
					notify(("%s теперь работает: %s"):format(s.name, b.name), "success")
					render()
				end
			end)
		end
	end
	if not resting then
		local rest = new("TextButton", { Position = UDim2.fromOffset(14, gridY + rows * CARD_H + (rows - 1) * 8 + 10),
			Size = UDim2.fromOffset(200, 34), BackgroundColor3 = C.idle, Text = "Снять с работы (отдых)", Font = FONT, TextSize = 13,
			TextColor3 = C.idleText, AutoButtonColor = true }, job)
		corner(rest, 12); stroke(rest, C.idleEdge, 3); shade(rest, 12)
		rest.Activated:Connect(function()
			if call("assign", s.uid, nil) then render() end
		end)
	end
	y += jobH + 14

	-- Зарплата (черновик до «Сохранить»)
	local sal = new("Frame", { Position = UDim2.fromOffset(16, y), Size = UDim2.fromOffset(inner, 108), BackgroundColor3 = C.block }, right)
	corner(sal, 14); stroke(sal, C.blockEdge, 3)
	local sh = hlist(sal, 8, { Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -28, 0, 22) })
	label(sh, { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Text = "Зарплата", TextSize = 16, LayoutOrder = 1 })
	label(sh, { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Text = "чем выше, тем лучше настроение и скорость работы",
		TextSize = 12, TextColor3 = C.dark, LayoutOrder = 2 })
	local function stepBtn(text, x, delta)
		local b = new("TextButton", { Position = UDim2.fromOffset(x, 46), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = C.idle,
			Text = text, Font = FONT, TextSize = 24, TextColor3 = C.white }, sal)
		corner(b, 12); stroke(b, C.idleEdge, 3); shade(b, 12)
		b.Activated:Connect(function()
			draftSalary[s.uid] = math.clamp(salary + delta, 0, D.SALARY_MAX)
			render()
		end)
	end
	stepBtn("−", 14, -D.SALARY_STEP)
	stepBtn("+", inner - 14 - 44, D.SALARY_STEP)
	local mid = hlist(sal, 7, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X })
	coin(mid, 22, 1)
	label(mid, { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Text = tostring(salary), TextSize = 24,
		TextColor3 = C.value, LayoutOrder = 2 })
	label(mid, { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Text = "/ день", TextSize = 14, LayoutOrder = 3 })
	local sb = bar(sal, { Position = UDim2.fromOffset(14 + 44 + 12, 80), Size = UDim2.new(1, -(14 + 44 + 12) * 2, 0, 12) },
		salary / D.SALARY_MAX, C.gold1)
	grad(sb:FindFirstChildOfClass("Frame"), C.gold1, C.gold2)
	y += 108 + 14

	-- показатели
	local stats = {
		{ "СКОРОСТЬ", resting and "—" or (D.speed(mood) .. "%") },
		{ "НАСТРОЕНИЕ", mood .. "%" },
		{ "ОПЫТ", tostring(s.xp) },
	}
	local sw3 = (inner - 16) / 3
	for i, st in ipairs(stats) do
		local box = new("Frame", { Position = UDim2.fromOffset(16 + (i - 1) * (sw3 + 8), y), Size = UDim2.fromOffset(sw3, 56),
			BackgroundColor3 = C.dark }, right)
		corner(box, 12)
		label(box, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 14), Text = st[1], TextSize = 11, TextColor3 = C.caption })
		label(box, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 24), Text = st[2], TextSize = 18 })
	end
	y += 56 + 14

	-- действия
	local save = new("TextButton", { Position = UDim2.fromOffset(16, H - 16 - 50), Size = UDim2.fromOffset(inner - 10 - 140, 50),
		BackgroundColor3 = C.white, Text = "Сохранить", Font = FONT, TextSize = 16, TextColor3 = C.white }, right)
	grad(save, C.green1, C.green2); corner(save, 12); stroke(save, C.greenEdge, 3); shade(save, 12); caption(save, "Сохранить", 16)
	save.Activated:Connect(function()
		local v = draftSalary[s.uid]
		if v and v ~= s.salary then
			if not call("save", s.uid, v) then return end
		end
		draftSalary[s.uid] = nil
		view = "list"
		render()
	end)
	local fire = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, H - 16 - 50),
		Size = UDim2.fromOffset(140, 50), BackgroundColor3 = C.white, Text = "Выгнать", Font = FONT, TextSize = 16, TextColor3 = C.white }, right)
	grad(fire, C.red1, C.red2); corner(fire, 12); stroke(fire, C.redEdge, 3); shade(fire, 12); caption(fire, "Выгнать", 16)
	fire.Activated:Connect(function() confirmFire(s) end)
end

-- ═══════════ отрисовка ═══════════
function render()
	parkPortraits()   -- готовые портреты — обратно на полку, не под снос
	for _, c in ipairs(root:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	if not state then stopPreview() return end
	local s = view == "detail" and survivorBy(selUid) or nil
	if view == "detail" and not s then view = "list" end
	dimFull.Visible = view ~= "detail"   -- на странице выжившего — затемнение вокруг окошка
	if view == "detail" then
		buildDetail(s)
	else
		stopPreview()
		buildList()
	end
	-- появление: сдвиг по X (README: ±24 px за 0.2 с) — ТОЛЬКО при смене экрана.
	-- Перерисовка на клик (зарплата, фильтр) не должна дёргать окно.
	local key = view .. ":" .. tostring(view == "detail" and selUid or "")
	if key ~= shownView then
		shownView = key
		root.Position = UDim2.new(0.5, view == "detail" and 24 or -24, 0.5, 0)
		TweenService:Create(root, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromScale(0.5, 0.5) }):Play()
	end
end

local function open()
	if isOpen then return end
	fetch()
	if not state then notify("Сервер не ответил") return end
	if typeof(_G.CloseInventory) == "function" then pcall(_G.CloseInventory) end
	if typeof(_G.CloseMerchantShop) == "function" then pcall(_G.CloseMerchantShop) end
	isOpen = true
	view, filter, selUid = "list", "Все", nil
	table.clear(draftSalary)
	gui.Enabled = true
	render()
end

local function close()
	if not isOpen then return end
	isOpen = false
	shownView = nil
	stopPreview()
	gui.Enabled = false
	parkPortraits()
	for _, c in ipairs(root:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
end
_G.SurvivorsBack = function() if isOpen and view == "detail" then view = "list"; render() end end
_G.OpenSurvivors = open
_G.CloseSurvivors = close
_G.IsSurvivorsOpen = function() return isOpen end

-- клик мимо окна: со страницы выжившего — назад к списку, из списка — закрыть
dimFull.Activated:Connect(function()
	if view == "detail" then view = "list"; render() else close() end
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not isOpen then return end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
		if gui:FindFirstChild("Confirm") then gui.Confirm:Destroy() return end
		if view == "detail" then view = "list"; render() else close() end
	end
end)
changedEv.OnClientEvent:Connect(function()
	if isOpen then fetch() render() end
end)
player:GetAttributeChangedSignal("Pirate"):Connect(function()
	if isOpen and view == "list" then render() end
end)
local cam0 = workspace.CurrentCamera
if cam0 then cam0:GetPropertyChangedSignal("ViewportSize"):Connect(function() if isOpen then render() end end) end
player.CharacterAdded:Connect(function() if isOpen then close() end end)

-- ═══════════ кадр: превью, моргание портретов, лица работников ═══════════
local faceT = 0
RunService.RenderStepped:Connect(function(dt)
	faceT += dt
	if not Rose then return end
	if isOpen then
		for _, p in ipairs(portraits) do
			if p.canvas.Parent then pcall(Rose.Expression, p.canvas, "Confident", faceT + p.seed, false) end
		end
		-- рыбак и Cold Cap в иконках: моргание раз в 2.8–5.5 с, те же доли век, что в игре
		for _, b in ipairs(faceBlinks) do
			b.nextBlink = b.nextBlink or (faceT + math.random() * 3 + 1)
			local lid = 0
			if faceT >= b.nextBlink then
				local d = faceT - b.nextBlink
				if d < .045 then lid = 1 elseif d < .08 then lid = 2 elseif d < .15 then lid = 3
				elseif d < .19 then lid = 2 elseif d < .24 then lid = 1
				else b.nextBlink = faceT + 2.8 + math.random() * 2.7 end
			end
			if b.lid ~= lid then b.lid = lid; pcall(b.set, lid) end
		end
	end
end)
-- лица выживших, которые работают на плоту (атрибут SurvivorFace ставит ферма)
task.spawn(function()
	while true do
		task.wait(1 / 20)
		if Rose then
			for _, m in ipairs(workspace:GetChildren()) do
				if m:IsA("Model") and m:GetAttribute("SurvivorFace") then
					local head = m:FindFirstChild("Head")
					local face = head and head:FindFirstChildOfClass("SurfaceGui")
					if face and face:FindFirstChild("Eye1") then
						local talking = m:GetAttribute("Activity") == "ГОВОРИТ"
						-- спит (рыбак ночью — FishingSleeping, фермер — Activity) — глаза закрыты
						local asleep = m:GetAttribute("FishingSleeping") == true or m:GetAttribute("Activity") == "СПИТ"
						pcall(Rose.Expression, face, asleep and "Sleep" or "Confident", faceT, talking and not asleep)
					end
				end
			end
		end
	end
end)

-- ═══════════ кнопка «Команда» в HUD ═══════════
--[[ Правая колонка, третья строка — рядом с «Настройками» (Квесты | Магазин,
     Рюкзак | Карта, Настройки | Команда). Те же числа HudScale, что у соседей. ]]
do
	local Hud = require(ReplicatedStorage:WaitForChild("HudScale"))
	local QUEST_X, QUEST_SIZE = Hud.gap(19), Hud.px(78)
	local GAP = Hud.gap(10)
	-- 92: выше окна «Команда» (91) — кнопка не гаснет под его затемнением
	local hud = new("ScreenGui", { Name = "SurvivorsButtonGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 92 }, playerGui)
	local btn = new("TextButton", { Name = "SurvivorsButton", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, QUEST_X + QUEST_SIZE + GAP, 0.5, Hud.step(82) - Hud.step(13)),
		Size = UDim2.fromOffset(QUEST_SIZE, QUEST_SIZE), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, hud)
	-- иконка-картинка, как у соседей («Настройки», «Карта»): без плашки, подпись поверх низа
	new("ImageLabel", { Name = "Icon", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Image = "rbxassetid://81369102419048", ScaleType = Enum.ScaleType.Fit }, btn)
	-- подпись — как у «Карты»/«Настроек»: белая, с чёрной обводкой TextStroke
	local cap = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, Hud.px(6), 0, Hud.px(20)), BackgroundTransparency = 1, Text = "Команда", TextScaled = true,
		Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1), TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.3, ZIndex = 4 }, btn)
	new("UITextSizeConstraint", { MaxTextSize = Hud.text(16) }, cap)
	--[[ ⚠️ ВЫСОТА — ФОРМУЛОЙ, ПО КОТОРОЙ СТОИТ ИКОНКА «НАСТРОЕК» (SettingsButton):
	     холдер 92×102 центром на 0.5 экрана + step(82), сжат UIScale(iconFactor)
	     вокруг центра; иконка 76 прижата к его верху → её центр выше центра
	     холдера на (102−76)/2 × iconFactor. Замер AbsolutePosition не годится:
	     на наведении UIScale «Настроек» дёргал сигнал, и «Команда» прыгала.
	     −1: подпись встаёт ровно на уровень подписи «Настроек». ]]
	local function align()
		btn.Position = UDim2.new(0, QUEST_X + QUEST_SIZE + GAP, 0.5, Hud.step(82) - 13 * Hud.iconFactor() - 1)
	end
	align()
	if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(align) end
	local sc = new("UIScale", {}, btn)
	btn.MouseEnter:Connect(function() TweenService:Create(sc, TweenInfo.new(0.12), { Scale = 1.07 }):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(sc, TweenInfo.new(0.12), { Scale = 1 }):Play() end)
	btn.Activated:Connect(function() if isOpen then close() else open() end end)
	-- кнопка появляется с первым жителем (SurvivorService: атрибут TeamUnlocked)
	local function gate() btn.Visible = player:GetAttribute("TeamUnlocked") == true end
	gate()
	player:GetAttributeChangedSignal("TeamUnlocked"):Connect(gate)
end

print("[Выжившие/клиент] окно готово: кнопка «Команда», превью камерой на сцене в Workspace")
