local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- DialogueUI.client.lua
-- ДИАЛОГОВОЕ ОКНО NPC по макету из design_handoff_dialogue_ui.
--
-- Окно по центру-снизу, НАД хотбаром: аватарка говорящего слева, тёмная плашка с
-- именем и репликой справа. Текст печатается посимвольно; клик во время печати
-- дописывает реплику целиком, клик после — переводит на следующую. Если игрок
-- завис — через 5 секунд текст начинает мигать. У реплики может быть награда
-- (плашка «ПОЛУЧЕНО» над окном) и варианты ответа с ветвлением.
--
-- Тексты и структура — в ReplicatedStorage.DialogueDefs (общие с сервером).
-- Награду выдаёт СЕРВЕР по своей копии данных; клиент только сообщает, до какой
-- реплики дошёл.
--
-- Шрифты: макет просит Russo One + Nunito. В Roblox они встроены не везде и не
-- гарантируют кириллицу, поэтому берём проектные GothamBlack/GothamBold — так же,
-- как в остальных меню (см. комментарий в SettingsMenu). Тени макета собраны
-- обводкой TextStroke: у Roblox нет CSS-теней, а обводка — его штатное средство.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local TextService       = game:GetService("TextService")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local player = Players.LocalPlayer
local Defs   = require(ReplicatedStorage:WaitForChild("DialogueDefs"))
local remote = ReplicatedStorage:WaitForChild("DialogueEvent")

-- ── токены макета ──
local ACCENT      = Color3.fromRGB(142, 205, 246)   -- #8ecdf6
local WHITE       = Color3.fromRGB(255, 255, 255)
local PLATE_BG    = Color3.fromRGB(40, 44, 50)
local SHADOW_BLUE = Color3.fromRGB(20, 60, 100)
local BTN_TOP     = Color3.fromRGB(122, 84, 48)     -- #7a5430
local BTN_BOT     = Color3.fromRGB(74, 48, 24)      -- #4a3018
local BTN_EDGE    = Color3.fromRGB(36, 22, 9)       -- #241609
local FONT_NAME   = Enum.Font.GothamBlack
local FONT_TEXT   = Enum.Font.GothamBold

-- ⚠️ РАЗМЕР КРУЖКА = РАЗРЕШЕНИЕ ПОРТРЕТА NPC. ViewportFrame рисуется ровно в
-- пикселях своей рамки, без сглаживания и без запаса: на 78 px голова выходила
-- ступенчатой. Аватар игрока этим не страдал — там картинка 150×150, которую
-- движок ужимает. Уменьшать это число обратно значит вернуть «лесенку».
local AVATAR    = 112
local GAP       = 14
local MAX_TEXT  = 472        -- 500 макета минус горизонтальные отступы плашки
local NAME_SIZE = 17
local TEXT_SIZE = 18
local TYPE_STEP = 0.03       -- 30 мс на символ
local BLINK_AT  = 5          -- через сколько секунд после допечатки мигать
-- Диалог стоит ВПРИТЫК над хотбаром. Верх хотбара: слоты 80 + поля 2×8 + 10 от
-- низа = 106 (при автоскейле инвентаря — ниже). 112 даёт пару пикселей зазора;
-- больше — и окно повисает «где-то над» инвентарём, на что уже жаловались.
local HOTBAR_CLEAR = 112

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function corner(inst, r)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, inst)
end

-- ── каркас ──
local gui = new("ScreenGui", {
	Name = "DialogueGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 40,
}, player:WaitForChild("PlayerGui"))

-- колонка: награда сверху, само окно снизу. Автоматический размер — чтобы плашка
-- всегда стояла ровно над окном, какой бы длинной ни оказалась реплика.
local column = new("Frame", {
	Name = "Column", BackgroundTransparency = 1, Visible = false,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -HOTBAR_CLEAR),
	Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
}, gui)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12),
}, column)

-- ⚠️ ОКНО ПОДГОНЯЕТСЯ ПОД ЭКРАН, А НЕ ЖИВЁТ В ПИКСЕЛЯХ МАКЕТА.
-- Всё здесь нарисовано числами: аватар 112, текст до 472, отступ от хотбара 112.
-- Это верно ровно для одной высоты окна — на маленьком экране диалог занимал
-- пол-обзора, на большом висел марочкой. Масштаб считаем от высоты вьюпорта и
-- этим же множителем двигаем отступ; ширину текста дополнительно режем по
-- ширине экрана, иначе на узком (телефон вертикально) плашка вылезает за края.
local uiScale = new("UIScale", { Scale = 1 }, column)

-- ⚠️ МАСШТАБ СЧИТАЕМ ПО ТОЙ ЖЕ ФОРМУЛЕ, ЧТО ИНВЕНТАРЬ.
-- Первый заход брал свою (vp.Y / 900, до 1.25) — и диалог начинал жить отдельной
-- жизнью от хотбара под ним: тот сжимается по min(vpX/1280, vpY/720) и никогда
-- не растёт выше 1.0. Два разных правила на два соседних блока — это и есть та
-- кривизна. Числа держим ровно как в InventoryUI.computeUIScale.
local BASE_W = 1280
local BASE_H = 720
local screenK = 1       -- текущий множитель
local textCap = MAX_TEXT

-- ⚠️ ОТСТУП ОТ НИЗА МЕРЯЕМ ПО ЖИВОМУ ХОТБАРУ, А НЕ ПО КОНСТАНТЕ.
-- 112 верны только при масштабе инвентаря 1.0. Умножать их на СВОЙ масштаб было
-- прямой ошибкой: на невысоком экране отступ ужимался, а хотбар оставался где
-- был, и окно налезало на слоты. Обе гуи с IgnoreGuiInset, координаты общие —
-- значит верх хотбара можно просто прочитать.
local function hotbarTop()
	local pg = player:FindFirstChild("PlayerGui")
	local hg = pg and pg:FindFirstChild("HotbarGui")
	local bar = hg and hg:FindFirstChild("Hotbar")
	if bar and bar:IsA("GuiObject") and bar.AbsoluteSize.Y > 0 then
		return bar.AbsolutePosition.Y
	end
	return nil
end

local BOTTOM_GAP = 6    -- зазор между окном и верхом слотов

-- ⚠️ ОКНО КРУПНЕЕ МАКЕТА НАРОЧНО.
-- Чистая формула инвентаря давала «слишком мелко»: инвентарь — сетка иконок, её
-- на весь экран не разгоняют, а реплику читают глазами. Тот же множитель, но с
-- запасом на четверть; потолок держим, иначе на 4K окно раздувается на треть
-- экрана.
local SIZE_BOOST = 1.25

local yOffset = -HOTBAR_CLEAR   -- текущее смещение от низа, подгоняется само

local function fitScreen()
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.Y < 1 then return end
	screenK = math.clamp(math.min(vp.X / BASE_W, vp.Y / BASE_H) * SIZE_BOOST, 0.7, 1.25)
	uiScale.Scale = screenK

	-- ⚠️ ШИРИНУ СЧИТАЕМ ЗА ВЫЧЕТОМ АВАТАРА.
	-- Раньше делили всю ширину экрана на масштаб и забывали про кружок слева —
	-- на узком экране плашка вылезала за край ровно на его ширину.
	textCap = math.min(MAX_TEXT,
		(vp.X * 0.92 - (AVATAR + GAP) * screenK) / screenK)
end

-- ⚠️ НИЗ ОКНА НЕ ВЫЧИСЛЯЕМ, А МЕРЯЕМ.
-- Предсказать его не выходит: у колонки AutomaticSize и UIScale на одном
-- объекте, и куда именно движок положит нижнюю грань, зависит от их порядка —
-- отсюда и «то налезает, то висит высоко». Поэтому читаем фактическую
-- AbsolutePosition готового окна и подтягиваем смещение на разницу. Ошибка
-- гасится за кадр-два и держится при любом содержимом реплики.
--[[ ⚠️ ВЕРХ ОКНА ДЛЯ ЧУЖИХ ПОДСКАЗОК СЧИТАЕМ, А НЕ МЕРЯЕМ.
     HudDock дважды пытался взять его из AbsolutePosition — колонки, потом её
     детей — и оба раза подсказка вставала на сотню пикселей выше плашки: у
     дерева с AutomaticSize и UIScale на одном фрейме координаты потомков
     отчитываются со сдвигом. Поэтому высоту содержимого складываем из наших же
     констант (аватар, отступы плашки, замер текста, ряд ответов, награда),
     умножаем на масштаб и отнимаем от низа, который известен точно — он
     привязан к хотбару. Результат публикуется атрибутом VisualTop на
     DialogueGui; HudDock читает его первым делом. ]]
local lineTextH = 0     -- высота текста реплики в пикселях макета, ставит playLine
local rewardPlateRef    -- плашка «Получено» создаётся ниже, ссылка проставляется там
local optionsRowRef     -- ряд ответов — тоже

local function contentHeight()
	local plateH = 10 + 9 + (NAME_SIZE + 4) + 4 + lineTextH
	if optionsRowRef and optionsRowRef.Visible then
		plateH += 4 + 6 + 30
	end
	local total = math.max(AVATAR, plateH)
	if rewardPlateRef and rewardPlateRef.Visible then
		total += 9 + 9 + 46 + 12
	end
	return total
end

local function anchorToHotbar()
	if not column.Visible then
		if gui:GetAttribute("VisualTop") ~= nil then gui:SetAttribute("VisualTop", nil) end
		return
	end
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.Y < 1 then return end

	local top = hotbarTop()
	local want = top and (top - BOTTOM_GAP) or (vp.Y - HOTBAR_CLEAR)
	gui:SetAttribute("VisualTop", want - contentHeight() * screenK)
	local bottom = column.AbsolutePosition.Y + column.AbsoluteSize.Y
	local err = bottom - want
	if math.abs(err) > 0.5 then
		yOffset -= err
		column.Position = UDim2.new(0.5, 0, 1, yOffset)
	end
end

RunService.RenderStepped:Connect(anchorToHotbar)

fitScreen()
task.spawn(function()
	local cam = Workspace.CurrentCamera
	while not cam do task.wait(0.2); cam = Workspace.CurrentCamera end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(fitScreen)
	-- хотбар строится своим скриптом и позже нас: ждём его и пересчитываем отступ
	for _ = 1, 40 do
		if hotbarTop() then break end
		task.wait(0.25)
	end
	fitScreen()
end)

-- ── плашка «ПОЛУЧЕНО» ──
local rewardPlate = new("Frame", {
	Name = "Rewards", LayoutOrder = 1, Visible = false,
	BackgroundColor3 = PLATE_BG, BackgroundTransparency = 0.45, BorderSizePixel = 0,
	Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
}, column)
corner(rewardPlate, 999)
rewardPlateRef = rewardPlate
local rewardScale = new("UIScale", { Scale = 1 }, rewardPlate)
new("UIPadding", {
	PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9),
	PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 24),
}, rewardPlate)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 18),
}, rewardPlate)
-- разрядка «П О Л У Ч Е Н О» из макета: letter-spacing у TextLabel нет, поэтому
-- расставляем пробелы сами
new("TextLabel", {
	Name = "Caption", LayoutOrder = 0, BackgroundTransparency = 1,
	Font = FONT_NAME, Text = "П О Л У Ч Е Н О", TextSize = 12,
	TextColor3 = ACCENT, TextTransparency = 0.05,
	Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X,
}, rewardPlate)

-- ── ряд: аватар + плашка реплики ──
local row = new("Frame", {
	Name = "Row", LayoutOrder = 2, BackgroundTransparency = 1,
	Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
}, column)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, GAP),
}, row)

local avatarHolder = new("Frame", {
	Name = "Avatar", LayoutOrder = 1, BackgroundColor3 = Color3.fromRGB(28, 34, 42),
	BorderSizePixel = 0, Size = UDim2.fromOffset(AVATAR, AVATAR), ClipsDescendants = true,
}, row)
corner(avatarHolder, 999)
new("UIStroke", { Color = WHITE, Thickness = 3, Transparency = 0.15 }, avatarHolder)

-- вся плашка реплики — кнопка: по макету клик по диалогу и дописывает, и листает
local plate = new("TextButton", {
	Name = "Plate", LayoutOrder = 2, AutoButtonColor = false, Text = "",
	BackgroundColor3 = PLATE_BG, BackgroundTransparency = 0.45, BorderSizePixel = 0,
	Size = UDim2.fromOffset(200, 0), AutomaticSize = Enum.AutomaticSize.Y,
}, row)
corner(plate, 12)
new("UIPadding", {
	PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 9),
	PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
}, plate)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4),
}, plate)

local nameLbl = new("TextLabel", {
	Name = "Speaker", LayoutOrder = 1, BackgroundTransparency = 1,
	Font = FONT_NAME, TextSize = NAME_SIZE, TextColor3 = ACCENT,
	TextStrokeColor3 = SHADOW_BLUE, TextStrokeTransparency = 0.45,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "",
	Size = UDim2.new(1, 0, 0, NAME_SIZE + 4),
}, plate)

local textLbl = new("TextLabel", {
	Name = "Line", LayoutOrder = 2, BackgroundTransparency = 1,
	Font = FONT_TEXT, TextSize = TEXT_SIZE, TextColor3 = WHITE,
	TextStrokeColor3 = SHADOW_BLUE, TextStrokeTransparency = 0.5,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true, Text = "",
	Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
}, plate)

local optionsRow = new("Frame", {
	Name = "Options", LayoutOrder = 3, BackgroundTransparency = 1, Visible = false,
	Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
}, plate)
optionsRowRef = optionsRow
local optionsScale = new("UIScale", { Scale = 1 }, optionsRow)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 10),
}, optionsRow)
new("UIPadding", { PaddingTop = UDim.new(0, 6) }, optionsRow)

-- ── аватарки ──
-- Портрет игрока — его собственный аватар. Портрет NPC — его НАСТОЯЩАЯ голова во
-- ViewportFrame: не нужно ничего загружать и он всегда совпадает с тем, кто стоит
-- на палубе.
local playerHeadshot = nil
task.spawn(function()
	local ok, url = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId,
			Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if ok then playerHeadshot = url end
end)

--[[ ⚠️ ПОРТРЕТ NPC СОБИРАЕМ ЗАРАНЕЕ И НИКОГДА НЕ ПРЯЧЕМ.
     ViewportFrame дорисовывает модель по кускам — и делает это заново всякий раз,
     когда рамка была скрыта (Visible = false или окно диалога закрыто). Поэтому
     и пересборка на каждой реплике, и простое «спрятать/показать» давали одно и
     то же: кружок торговца пустой, лицо появляется через миг.
     Теперь портрет строится, как только NPC появился в мире (prebuild ниже), и
     всё время живёт на «полке» — отдельной ScreenGui, почти целиком за краем
     экрана (4 px в углу под кнопкой меню Roblox): движок его честно рисует. В
     диалог переносится уже готовый кадр, а после — обратно на полку.
     Тот же приём — у портретов «Команды» (SurvivorsUI). ]]
local npcPortraits = {}   -- [Model] = Frame "NpcPortrait"
local portraitShelf = new("ScreenGui", { Name = "DialoguePortraitShelf", ResetOnSpawn = false,
	IgnoreGuiInset = true, DisplayOrder = -60 }, player:WaitForChild("PlayerGui"))
portraitShelf:SetAttribute("KeepEnabled", true)   -- кэш кадров: стройка его не гасит
local function parkPortrait(box)
	box.Parent = portraitShelf
	box.Size = UDim2.fromOffset(AVATAR, AVATAR)
	box.Position = UDim2.fromOffset(4 - AVATAR, 4 - AVATAR)
end

local function clearAvatar()
	for _, c in ipairs(avatarHolder:GetChildren()) do
		if c.Name == "NpcPortrait" then
			parkPortrait(c)
		elseif c:IsA("ImageLabel") or c:IsA("ViewportFrame") or c:IsA("TextLabel") or c.Name == "PortraitFace" then
			c:Destroy()
		end
	end
end

-- Мусор, которому в портрете делать нечего: свои скрипты продолжили бы работать,
-- подсказки и полоски здоровья полезли бы поверх лица, звуки — играть.
local function isPortraitJunk(d)
	return d:IsA("Script") or d:IsA("LocalScript")
		or d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("SurfaceGui")
		or d:IsA("ParticleEmitter") or d:IsA("Sound") or d:IsA("Beam") or d:IsA("Trail")
		or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles")
end

--[[ ⚠️ ЛИЦО ИЗ SurfaceGui ВО ViewportFrame НЕ РИСУЕТСЯ. У торговца (и других
     «нестандартных» NPC) лицо — SurfaceGui на отдельной детали (FaceCanvas →
     MerchantFace), а не декаль: в портрете его не было. Кладём копию такого GUI
     поверх портрета 2D-слоем ровно туда, куда в кадре проецируется грань детали
     (камера портрета известна: FOV, CFrame, кадр квадратный). ]]
local FACE_AXES = {
	[Enum.NormalId.Front]  = { n = Vector3.new(0, 0, -1), u = Vector3.xAxis, v = Vector3.yAxis },
	[Enum.NormalId.Back]   = { n = Vector3.new(0, 0, 1),  u = Vector3.xAxis, v = Vector3.yAxis },
	[Enum.NormalId.Right]  = { n = Vector3.new(1, 0, 0),  u = Vector3.zAxis, v = Vector3.yAxis },
	[Enum.NormalId.Left]   = { n = Vector3.new(-1, 0, 0), u = Vector3.zAxis, v = Vector3.yAxis },
	[Enum.NormalId.Top]    = { n = Vector3.new(0, 1, 0),  u = Vector3.xAxis, v = Vector3.zAxis },
	[Enum.NormalId.Bottom] = { n = Vector3.new(0, -1, 0), u = Vector3.xAxis, v = Vector3.zAxis },
}
local function relPath(root, inst)
	local names = {}
	while inst and inst ~= root do table.insert(names, 1, inst.Name); inst = inst.Parent end
	return inst == root and names or nil
end
local function byNames(root, names)
	local node = root
	for _, n in ipairs(names) do node = node and node:FindFirstChild(n) end
	return node
end
local function overlaySurfaceFaces(npc, clone, camCF, fov, holder)
	local t = math.tan(math.rad(fov) / 2)
	local npcHead = npc:FindFirstChild("Head", true)
	--[[ ⚠️ ТОЛЬКО ЛИЦО — SurfaceGui НА ГОЛОВЕ ИЛИ НА ДЕТАЛИ ВПЛОТНУЮ К НЕЙ.
	     Раньше копировались ВСЕ SurfaceGui модели. У Cold Cap это 36 панелей
	     HD-костюма и морозная аура (2×16 кадров на холсте 1024): они вылезали
	     за портрет, раздували окно диалога — оно уезжало за верх экрана, — а
	     аура висела картинкой в углу. ]]
	local function isFaceGui(src)
		if not (npcHead and npcHead:IsA("BasePart")) then return true end
		if src == npcHead or src:IsDescendantOf(npcHead) then return true end
		local far = (src.Position - npcHead.Position).Magnitude
		local big = math.max(src.Size.X, src.Size.Y, src.Size.Z)
		return far < 1.2 and big < 3
	end
	for _, sg in ipairs(npc:GetDescendants()) do
		local src0 = sg:IsA("SurfaceGui") and ((sg.Adornee and sg.Adornee:IsA("BasePart")) and sg.Adornee or sg.Parent)
		if sg:IsA("SurfaceGui") and sg.Enabled and src0 and src0:IsA("BasePart") and isFaceGui(src0) then
			local src = src0
			local path = src and src:IsA("BasePart") and relPath(npc, src)
			local part = path and byNames(clone, path)
			local ax = FACE_AXES[sg.Face]
			if part and part:IsA("BasePart") and ax then
				local h = part.Size * 0.5
				local center = part.CFrame * (ax.n * h)
				local u = part.CFrame:VectorToWorldSpace(ax.u * h)
				local v = part.CFrame:VectorToWorldSpace(ax.v * h)
				local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
				local visible = true
				for _, c in ipairs({ center + u + v, center - u + v, center + u - v, center - u - v }) do
					local l = camCF:PointToObjectSpace(c)
					if l.Z >= -0.01 then visible = false break end
					local sx = 0.5 + l.X / (-l.Z * t) * 0.5
					local sy = 0.5 - l.Y / (-l.Z * t) * 0.5
					minX, maxX = math.min(minX, sx), math.max(maxX, sx)
					minY, maxY = math.min(minY, sy), math.max(maxY, sy)
				end
				if visible and maxX > minX and maxY > minY then
					local canvas = sg.CanvasSize
					if sg.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud then
						local ext = (ax.u * part.Size).Magnitude
						local ext2 = (ax.v * part.Size).Magnitude
						canvas = Vector2.new(ext, ext2) * sg.PixelsPerStud
					end
					--[[ ⚠️ ХОЛСТ РАСТЯГИВАЕТСЯ НЕРАВНОМЕРНО. SurfaceGui с FixedSize кладёт
					     холст (у торговца 512×512) на грань детали целиком, а грань
					     неквадратная (1,8 × 0,95) — по X и Y масштаб разный. Равномерный
					     UIScale давал «лишь часть лица»: остальное уходило за рамку.
					     Поэтому переводим элементы в доли холста — они растягиваются
					     по рамке так же, как на самой голове. ]]
					local box = new("Frame", {
						Name = "PortraitFace", BackgroundTransparency = 1, ClipsDescendants = false, ZIndex = 3,
						Position = UDim2.fromScale(minX, minY), Size = UDim2.fromScale(maxX - minX, maxY - minY),
					}, holder)
					local function toScale(u, total)
						return u.Scale + (total > 0 and u.Offset / total or 0)
					end
					local mirror = {}   -- { источник, копия, верхний уровень? } — для живого лица
					local function copyAll()
						box:ClearAllChildren()
						table.clear(mirror)
						for _, child in ipairs(sg:GetChildren()) do
							local ok, c = pcall(function() return child:Clone() end)
							if ok and c then
								if c:IsA("GuiObject") then
									c.Position = UDim2.fromScale(toScale(c.Position.X, canvas.X), toScale(c.Position.Y, canvas.Y))
									c.Size = UDim2.fromScale(toScale(c.Size.X, canvas.X), toScale(c.Size.Y, canvas.Y))
									c.ZIndex = math.max(c.ZIndex, 3)
									table.insert(mirror, { child, c, true })
								end
								local sd, cd = child:GetDescendants(), c:GetDescendants()
								for i = 1, math.min(#sd, #cd) do
									if sd[i]:IsA("GuiObject") and cd[i]:IsA("GuiObject") then table.insert(mirror, { sd[i], cd[i], false }) end
								end
								c.Parent = box
							end
						end
					end
					copyAll()
					--[[ ⚠️ HD-ЛИЦО (Cold Cap) — ЖИВОЕ, А НЕ СНИМОК. Его рисует HDFaceSync
					     модели: полоса глаз поджимается (моргание), атлас переключает
					     эмоции. Разовая копия замирала — в диалоге он «просто смотрел».
					     Каждый кадр повторяем видимость, размеры и картинки за оригиналом;
					     поменялся состав (HDFaceSync достроил слои) — копируем заново. ]]
					if sg.Parent and sg.Parent.Name == "HDFaceCarrier" then
						local lastN = #sg:GetDescendants()
						local conn
						conn = RunService.RenderStepped:Connect(function()
							if not (box.Parent and sg.Parent) then conn:Disconnect() return end
							local n = #sg:GetDescendants()
							if n ~= lastN then lastN = n; copyAll() return end
							for _, m in ipairs(mirror) do
								local src, dst, top = m[1], m[2], m[3]
								if src.Parent then
									dst.Visible = src.Visible
									if not top then dst.Size = src.Size; dst.Position = src.Position end
									if src:IsA("ImageLabel") and dst:IsA("ImageLabel") then
										dst.Image = src.Image
										dst.ImageTransparency = src.ImageTransparency
									end
								end
							end
						end)
					end
				end
			end
		end
	end
end

-- имя прямого ребёнка Workspace или путь «Модель/Вложенная» (торговец сидит в
-- яхте: «MerchantYacht/Merchant»)
local function findNpc(modelName)
	local npc = nil
	-- диалог на лету (фермер) приносит саму модель, а не путь
	if typeof(modelName) == "Instance" and modelName:IsA("Model") and modelName:IsDescendantOf(Workspace) then
		npc = modelName
	elseif type(modelName) == "string" then
		npc = Workspace
		for part in string.gmatch(modelName, "[^/]+") do
			npc = npc and npc:FindFirstChild(part)
		end
		if npc == Workspace then npc = nil end
	end
	local head = npc and npc:FindFirstChild("Head", true)
	if not head or not head:IsA("BasePart") then return nil end
	return npc, head
end

-- готовый портрет NPC (на полке); nil — не вышло
local function buildPortrait(npc, head)
	local cached = npcPortraits[npc]
	if cached and cached.Parent then return cached end
	local box = new("Frame", { Name = "NpcPortrait", BackgroundTransparency = 1 }, portraitShelf)
	parkPortrait(box)
	local vp = new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(28, 34, 42),
		BackgroundTransparency = 0, BorderSizePixel = 0,
		-- Мягкий свет сбоку-сверху вместо плоской равномерной засветки: без него
		-- лицо выглядело картонкой одного цвета.
		Ambient = Color3.fromRGB(150, 152, 158),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -1, -0.7),
	}, box)
	corner(vp, 999)   -- как и у картинки: круг задаётся на самом элементе

	-- ⚠️ КЛОНИРУЕМ МОДЕЛЬ ЦЕЛИКОМ, а не отдельные детали.
	-- Одежда (Shirt/Pants), цвета тела (BodyColors) и CharacterMesh живут на самой
	-- модели рядом с Humanoid и применяются к телу через него. Когда сюда копировали
	-- только голову с торсом, всё это оставалось за бортом — скин не подтягивался, и
	-- торс выходил залитым одним цветом.
	local ok, clone = pcall(function() return npc:Clone() end)
	local headClone = ok and clone and clone:FindFirstChild("Head", true)
	if not headClone then
		if clone then clone:Destroy() end
		box:Destroy()
		return nil
	end

	for _, d in ipairs(clone:GetDescendants()) do
		if isPortraitJunk(d) then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end

	-- ГОЛОВА В НАЧАЛО КООРДИНАТ, остальное сохраняет положение относительно неё:
	-- портрет выходит ровным, даже если NPC сейчас лежит или стоит боком.
	-- delta считается ДО цикла — иначе она поехала бы вместе с головой.
	local delta = headClone.CFrame:Inverse()
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then d.CFrame = delta * d.CFrame end
	end

	-- WorldModel обязателен: без него ViewportFrame рисует голые детали, без одежды
	-- и без аксессуаров, собранных на аттачментах.
	local world = Instance.new("WorldModel")
	world.Name = "Portrait"
	clone.Parent = world
	world.Parent = vp

	-- КАДР СЧИТАЕТСЯ ОТ ВЫСОТЫ ГОЛОВЫ И УГЛА ОБЗОРА, а не подбирается на глаз: у R6
	-- и R15 головы разной величины. FRAME_HEIGHT — сколько «высот головы» влезает в
	-- кружок; чем меньше, тем крупнее лицо и тем больше пикселей ему достаётся.
	-- Раньше в кадр помещалось больше трёх высот, и лицо занимало треть кружка —
	-- половина и без того скромного разрешения уходила на пустоту вокруг.
	local FOV = 32
	local FRAME_HEIGHT = 1.9
	local hs = head.Size
	local dist = (hs.Y * FRAME_HEIGHT) / (2 * math.tan(math.rad(FOV) / 2))
	local eyeY = hs.Y * 0.10
	-- лицо детали смотрит вдоль -Z, поэтому камеру ставим со стороны -Z
	local cam = new("Camera", {
		CFrame = CFrame.lookAt(Vector3.new(0, eyeY + hs.Y * 0.05, -dist), Vector3.new(0, eyeY, 0)),
		FieldOfView = FOV,
	}, vp)
	vp.CurrentCamera = cam
	box.ClipsDescendants = true   -- оверлеи лица не вылезают за портрет
	overlaySurfaceFaces(npc, clone, cam.CFrame, FOV, box)
	npcPortraits[npc] = box
	-- NPC ушёл из мира (торговец уплыл) — портрет больше не нужен
	npc.AncestryChanged:Connect(function()
		if not npc:IsDescendantOf(game) and npcPortraits[npc] == box then
			npcPortraits[npc] = nil
			box:Destroy()
		end
	end)
	return box
end

local function npcPortrait(modelName)
	local npc, head = findNpc(modelName)
	if not npc then return false end
	local box = buildPortrait(npc, head)
	if not box then return false end
	box.Parent = avatarHolder
	box.Position = UDim2.new()
	box.Size = UDim2.fromScale(1, 1)
	return true
end

-- портреты всех NPC из диалогов — заранее, как только NPC есть в мире
-- (торговец приплывает на яхте: ловим его по пути из DialogueDefs)
task.spawn(function()
	local paths = {}
	for _, d in pairs(Defs.dialogues) do
		if type(d.npcModel) == "string" then paths[d.npcModel] = true end
	end
	while true do
		for path in pairs(paths) do
			local npc, head = findNpc(path)
			if npc and not npcPortraits[npc] then pcall(buildPortrait, npc, head) end
		end
		task.wait(2)
	end
end)

local function setAvatar(dialogue, who)
	clearAvatar()
	if who == "player" then
		local img = new("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			Image = playerHeadshot or "", ScaleType = Enum.ScaleType.Crop,
		}, avatarHolder)
		-- Скругление нужно НА САМОЙ картинке: UICorner держателя её не режет, а
		-- ClipsDescendants обрезает по прямоугольнику — углы аватара торчали из круга.
		corner(img, 999)
		return
	end
	if npcPortrait(dialogue.npcModel) then return end
	-- NPC не нашёлся — не оставляем пустой кружок
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = FONT_NAME,
		Text = string.sub(dialogue.npcName or "?", 1, 1), TextSize = 34, TextColor3 = ACCENT,
	}, avatarHolder)
end

-- ── награды ──
-- ИКОНКА НАГРАДЫ БЕЗ ЖЁСТКОГО ID. Прописывать её в диалоге не обязательно: сперва
-- берём то, что задано явно, потом словарь иконок инвентаря, а в конце — TextureId
-- самого тула. Последнее важно для тулов вроде Fire_Axe, которые собраны в Studio:
-- их картинка живёт на самом Tool, и дублировать её ещё и в диалоге незачем.
local function rewardIcon(r)
	if r.icon and r.icon ~= "" then return r.icon end
	local key = r.tool or r.resource
	if not key then return "" end
	if typeof(_G.GetItemIcon) == "function" then
		local fromInventory = _G.GetItemIcon(key)
		if fromInventory and fromInventory ~= "" then return fromInventory end
	end
	if r.tool then
		local template = ReplicatedStorage:FindFirstChild(r.tool)
			or ReplicatedStorage:FindFirstChild(r.tool, true)
		if template and template:IsA("Tool") and template.TextureId ~= "" then
			return template.TextureId
		end
	end
	return ""
end

local function clearRewards()
	for _, c in ipairs(rewardPlate:GetChildren()) do
		if c.Name == "Item" then c:Destroy() end
	end
	rewardPlate.Visible = false
end

local function showRewards(rewards)
	clearRewards()
	for i, r in ipairs(rewards) do
		local item = new("Frame", {
			Name = "Item", LayoutOrder = i, BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, 46), AutomaticSize = Enum.AutomaticSize.X,
		}, rewardPlate)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10),
		}, item)

		local iconBox = new("Frame", {
			LayoutOrder = 1, BackgroundColor3 = Color3.fromRGB(28, 34, 42), BorderSizePixel = 0,
			Size = UDim2.fromOffset(46, 46), ClipsDescendants = true,
		}, item)
		corner(iconBox, 999)
		new("UIStroke", { Color = ACCENT, Thickness = 3 }, iconBox)
		corner(new("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			Image = rewardIcon(r), ScaleType = Enum.ScaleType.Fit,
		}, iconBox), 999)

		new("TextLabel", {
			LayoutOrder = 2, BackgroundTransparency = 1, Font = FONT_NAME,
			Text = r.name or "", TextSize = 17, TextColor3 = WHITE,
			TextStrokeColor3 = SHADOW_BLUE, TextStrokeTransparency = 0.45,
			Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
		}, item)
	end

	-- пружинный «выброс» из макета: Back/Out — ближайший аналог overshoot-кривой
	rewardPlate.Visible = true
	rewardScale.Scale = 0.4
	TweenService:Create(rewardScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()
end

-- ── состояние диалога ──
local current       -- активный диалог (таблица из DialogueDefs)
local currentKey    -- его ключ (для сервера)
local lineIndex = 0
local typing    = false
local fullText  = ""
local typeToken = 0
local blinkTween = nil

local function stopBlink()
	if blinkTween then
		blinkTween:Cancel()
		blinkTween = nil
	end
	textLbl.TextTransparency = 0
end

local function startBlinkTimer(token)
	task.delay(BLINK_AT, function()
		if token ~= typeToken or typing or not column.Visible then return end
		if optionsRow.Visible then return end   -- у вопроса подсказка не нужна: там кнопки
		stopBlink()
		blinkTween = TweenService:Create(textLbl,
			TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ TextTransparency = 0.7 })
		blinkTween:Play()
	end)
end

-- корректная нарезка по символам: строки русские, побайтовый sub рвал бы буквы
local function subGraphemes(s, n)
	local o = utf8.offset(s, n + 1)
	return o and string.sub(s, 1, o - 1) or s
end

local advance   -- forward declaration
--[[ ⚠️ НАГРАДУ НЕЛЬЗЯ ПРОПУСТИТЬ. Пока на реплике висит «Забрать награду», диалог
     не листается, не закрывается и не сменяется другим — что бы ни случилось
     (клик по окну, допечатка, повторный запуск с сервера). Снимает только
     нажатие на саму плашку. ]]
local claimPending = false
local dialogueQueue = {}   -- ключи, которые ждут, пока закроется текущий диалог
local claimedKeys = {}   -- [ключ] = true: награду из этого диалога уже забрали — повтор не играем

local claimPill = require(ReplicatedStorage:WaitForChild("ClaimRewardPill")).new(plate, function() return uiScale.Scale end)

local function clearOptions()
	claimPill:Hide()
	optionsRow.Visible = false
	for _, c in ipairs(optionsRow:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
end

local function showOptions(options)
	clearOptions()
	--[[ «ЗАБРАТЬ НАГРАДУ» — стеклянная плашка над окном реплики (ClaimRewardPill,
	     design_handoff_claim_reward), а не кнопкой в строке вариантов: та была
	     незаметной и поднимала окно диалога. ]]
	for _, opt in ipairs(options) do
		if opt.claim then
			claimPending = true
			claimPill:Show(function()
				claimPending = false
				claimedKeys[currentKey] = true   -- эту речь с наградой больше не показываем
				for i = #dialogueQueue, 1, -1 do
					if dialogueQueue[i] == currentKey then table.remove(dialogueQueue, i) end
				end
				remote:FireServer("claim", currentKey, lineIndex, table.find(options, opt))
				clearOptions()
				advance(opt.next)
			end)
			return
		end
	end
	for i, opt in ipairs(options) do
		local btn = new("TextButton", {
			LayoutOrder = i, AutoButtonColor = false, BorderSizePixel = 0,
			BackgroundColor3 = BTN_TOP, Font = FONT_NAME, Text = opt.label or "…",
			TextSize = 15, TextColor3 = WHITE,
			Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X,
		}, optionsRow)
		corner(btn, 999)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18),
			PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 6),
		}, btn)
		new("UIGradient", {
			Rotation = 90, Color = ColorSequence.new(BTN_TOP, BTN_BOT),
		}, btn)
		new("UIStroke", { Color = BTN_EDGE, Thickness = 2 }, btn)
		btn.Activated:Connect(function()
			-- «Забрать награду»: выдачу решает сервер (DialogueService → _G.OnDialogueClaim)
			if opt.claim then remote:FireServer("claim", currentKey, lineIndex, i) end
			clearOptions()
			advance(opt.next)
		end)
	end
	optionsRow.Visible = true
	optionsScale.Scale = 0.5
	TweenService:Create(optionsScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()
end

local function finishLine()
	typing = false
	textLbl.Text = fullText
	local line = current and current.lines[lineIndex]
	if not line then return end
	if line.rewards then
		showRewards(line.rewards)
		remote:FireServer("reward", currentKey, lineIndex)   -- выдаёт сервер, не мы
	end
	if line.options then
		showOptions(line.options)
	else
		startBlinkTimer(typeToken)
	end
end

local startDialogue       -- ниже

local function closeDialogue()
	typeToken += 1
	typing = false
	stopBlink()
	clearOptions()
	clearRewards()
	column.Visible = false
	current, currentKey, lineIndex = nil, nil, 0
	-- следующий из очереди — после закрытия, а не поверх
	local nextKey = table.remove(dialogueQueue, 1)
	if nextKey then task.defer(startDialogue, nextKey) end
end

local function playLine(index)
	local line = current and current.lines[index]
	if not line then
		closeDialogue()
		return
	end
	lineIndex = index
	typeToken += 1
	local token = typeToken

	stopBlink()
	clearOptions()
	clearRewards()

	fullText = line.text or ""
	nameLbl.Text = Defs.speakerName(current, line, player.DisplayName)
	setAvatar(current, line.who)

	-- ширину плашки считаем ПО ПОЛНОМУ тексту заранее: если пускать AutomaticSize по
	-- ходу печати, окно дёргается и прыгает на каждой букве
	local measured = TextService:GetTextSize(fullText .. "▌", TEXT_SIZE, FONT_TEXT,
		Vector2.new(textCap, 1e6))
	local nameW = TextService:GetTextSize(nameLbl.Text, NAME_SIZE, FONT_NAME,
		Vector2.new(textCap, 1e6)).X
	plate.Size = UDim2.fromOffset(math.max(measured.X, nameW, 120) + 28, 0)
	lineTextH = measured.Y   -- для contentHeight: высота плашки известна заранее

	textLbl.Text = ""
	typing = true
	local total = utf8.len(fullText) or #fullText
	task.spawn(function()
		for i = 1, total do
			if token ~= typeToken then return end
			textLbl.Text = subGraphemes(fullText, i) .. "▌"
			task.wait(TYPE_STEP)
		end
		if token ~= typeToken then return end
		finishLine()
	end)
end

function advance(explicitNext)
	if claimPending then return end   -- сначала «Забрать награду»
	local line = current and current.lines[lineIndex]
	local nxt = explicitNext or (line and line.next) or (lineIndex + 1)
	if not current or not current.lines[nxt] then
		closeDialogue()
		return
	end
	playLine(nxt)
end

-- клик по окну: печатает мгновенно либо листает дальше
plate.Activated:Connect(function()
	if not column.Visible then return end
	if typing then
		typeToken += 1        -- обрываем печать…
		finishLine()          -- …и показываем реплику целиком
		return
	end
	if optionsRow.Visible then return end   -- у вопроса обязателен выбор ответа
	if claimPill:IsShown() then return end   -- награду забирают плашкой над окном
	advance(nil)
end)

-- ── запуск ──
--[[ ⚠️ ИДУЩИЙ ДИАЛОГ НЕ ПЕРЕБИВАЕМ. Один и тот же разговор запускают несколько
     мест сразу (сцену «нужен житель» — установка станции, вход игрока, загрузка
     сейва и повтор раз в 30 с), а мысли игрока (жажда, кровать, туман) — когда
     угодно. Каждый запуск начинал диалог с первой строки прямо посреди печати:
     реплика доходила до середины и стартовала заново. Теперь тот же ключ, пока
     он на экране, игнорируем, а другой ставим в очередь — он начнётся, когда
     игрок дочитает текущий. ]]
function startDialogue(key)
	local dialogue = Defs.dialogues[key]
	if not dialogue or not dialogue.lines[1] then return end
	if claimedKeys[key] then return end   -- запоздалый повтор сцены с уже забранной наградой
	if current then
		if key ~= currentKey and not table.find(dialogueQueue, key) then
			table.insert(dialogueQueue, key)
		end
		return
	end
	current, currentKey = dialogue, key
	-- хотбар пересобирается при респавне и может уехать: меряем отступ заново
	-- каждый раз, когда окно открывается
	fitScreen()
	column.Visible = true
	playLine(1)
end

-- с сервера (_G.StartDialogue → RemoteEvent)
local customN = 0
remote.OnClientEvent:Connect(function(action, key)
	-- диалог на лету (_G.StartCustomDialogue): регистрируем под своим ключом и
	-- показываем тем же окном, что и квестовые
	if action == "custom" and type(key) == "table" and type(key.lines) == "table" then
		customN += 1
		local id = "Custom:" .. customN
		Defs.dialogues[id] = { npcName = key.npcName, npcModel = key.npcModel, lines = key.lines }
		startDialogue(id)
		return
	end
	if action ~= "start" then return end
	startDialogue(key)
end)

-- с клиента: мысли игрока после катсцен и прочие локальные реплики без наград —
-- серверу о них знать незачем (см. WaveTelegraph: туман)
_G.StartLocalDialogue = startDialogue
-- какой диалог сейчас на экране (nil — окно закрыто): торговец открывает лавку,
-- только когда игрок дочитал его речь (MerchantYachtClient)
_G.DialogueCurrentKey = function() return currentKey end

print("[DialogueUI] ready")
