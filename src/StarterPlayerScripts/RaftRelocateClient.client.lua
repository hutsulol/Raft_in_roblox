local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- RaftRelocateClient.client.lua
-- Клиент переноса тотема водолазов и ремонтной станции. Схема — как у пушек
-- (WeaponPickup + CanonPlacer), а не отдельная своя:
--   1) подошёл к объекту → в углу экрана кнопка: цена сверху, «Перенести» снизу;
--   2) клик → сервер списывает пиратов, объект уходит с плота, в инвентаре
--      появляется предмет;
--   3) достал предмет → зелёный призрак под курсором, R — поворот,
--      ЛКМ — поставить.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")

local player    = Players.LocalPlayer
local mouse     = player:GetMouse()
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))
local camera    = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

local evt = ReplicatedStorage:WaitForChild("RaftRelocate")

--[[ ⚠️ ПОСТАНОВКА НА ТЕЛЕФОНЕ ИДЁТ ЧЕРЕЗ ОБЩИЙ МОДУЛЬ.
     Перенос целится той же единственной строкой, что и все остальные ставилки, —
     лучом из курсора. Курсора на телефоне нет, поэтому там прицел даёт тап, а
     подтверждает кнопка. Вся механика лежит в TouchPlace, здесь только три точки
     подключения: луч, начало сеанса и конец. На компьютере модуль не делает
     ничего. ]]
--[[ ⚠️ МЕХАНИКУ БЕРЁМ ИЗ HudScale, А ЖДЁМ — С ТАЙМАУТОМ. ДВЕ ЛОВУШКИ РАЗОМ.
     Первая: WaitForChild без второго аргумента ждёт ВЕЧНО, и не доехавший
     модуль остановил бы ВЕСЬ этот скрипт — предмет в руках есть, а поставить
     нельзя ничем и нигде, причём молча.
     Вторая, из-за которой правка и не работала на телефоне: НОВЫЙ файл до
     запущенной сессии Rojo доезжает не всегда. Правки существующих файлов
     синкаются, а новый инстанс появляется в плейсе только после
     переподключения — и ставилки честно откатывались на мышь, то есть на то
     самое поведение, от которого уходили.
     Поэтому спрашиваем сначала HudScale: он в плейсе давно и синкается штатно,
     а вся механика постановки живёт теперь в нём (HudScale.Place). Отдельный
     TouchPlace остаётся запасным именем — кто его нашёл, получит то же самое.
     Не нашли ни того, ни другого — работаем по-старому, мышью. ]]
-- касание без мыши = телефон. Считаем сами: запрет ставить пальцем не
-- должен зависеть от того, поднялся ли общий модуль
local IS_TOUCH = game:GetService("UserInputService").TouchEnabled
	and not game:GetService("UserInputService").MouseEnabled

local TouchPlace do
	local rs = game:GetService("ReplicatedStorage")
	local function grab(name, field)
		local mod = rs:FindFirstChild(name) or rs:WaitForChild(name, 5)
		if not mod then return nil end
		local ok, res = pcall(require, mod)
		if not ok then return nil end
		if field then res = (type(res) == "table") and res[field] or nil end
		return (type(res) == "table") and res or nil
	end

	TouchPlace = grab("HudScale", "Place") or grab("TouchPlace") or {
		isPhone = function() return false end,
		ray = function(m)
			local cam = workspace.CurrentCamera
			if not (cam and m) then return nil end
			return cam:ViewportPointToRay(m.X, m.Y)
		end,
		setHit = function() end,
		begin  = function() end,
		finish = function() end,
		active = function() return false end,
	}
	if not TouchPlace.begin or TouchPlace.isPhone() == nil then
		warn("[Установка] механика постановки не найдена — ставим по-старому, мышью")
	end
end

local PICKUP_RADIUS = 13
local COIN_ICON     = "rbxassetid://93617165412571"

local catalog = {}          -- [имяМодели] = { price, label }
local nearModel, nearSpec   -- объект под кнопкой подбора
local ghost, ghostOffset, ghostValid, rotation = nil, nil, false, 0
local heldKey               -- имя предмета в руках (он же имя модели)

-- объявлены заранее: их зовёт createGhost, а определены они ниже по файлу
local onPlaceClick, rotatePlacement

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

-- ══════════ Кнопка подбора: цена сверху, действие снизу ══════════
local gui = new("ScreenGui", {
	Name = "RaftRelocateButton", ResetOnSpawn = false, DisplayOrder = 12, Enabled = false,
}, playerGui)
local holder = new("Frame", {
	Position = UDim2.new(0.18, 0, 0.1, 0), Size = UDim2.fromOffset(150, 116),
	BackgroundTransparency = 1,
}, gui)

local priceRow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.fromOffset(148, 22), BackgroundTransparency = 1, ZIndex = 3,
}, holder)
local coin = new("ImageLabel", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0.5, -4, 0.5, 0),
	Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, Image = COIN_ICON, ZIndex = 3,
}, priceRow)
local priceLbl = new("TextLabel", {
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, 2, 0.5, 0),
	Size = UDim2.fromOffset(70, 20), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.fromRGB(255, 210, 58),
	TextXAlignment = Enum.TextXAlignment.Left, Text = "0", ZIndex = 3,
}, priceRow)

--[[ КНОПКА — КАК У ФАКЕЛА: картинка объекта (иконка из каталога сервера),
     под ней подпись «Перенести» с чёрной обводкой. Раньше была тёмная плашка с
     названием текстом — выбивалась из соседних кнопок HUD. ]]
local btn = new("ImageButton", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24),
	Size = UDim2.fromOffset(84, 84), BackgroundTransparency = 1, Image = "",
	ScaleType = Enum.ScaleType.Fit, ZIndex = 2,
}, holder)
local btnScale = new("UIScale", {}, btn)
btn.MouseEnter:Connect(function() btnScale.Scale = 1.1 end)
btn.MouseLeave:Connect(function() btnScale.Scale = 1 end)
-- название оставлено невидимым: оно нужно ниже по коду, а показывает объект иконка
local nameLbl = new("TextLabel", { Visible = false, Text = "" }, btn)
local actionLbl = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24 + 84 * 0.86),
	Size = UDim2.fromOffset(118, 20), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack, TextScaled = true, TextColor3 = Color3.new(1, 1, 1),
	Text = "Перенести", ZIndex = 3,
}, holder)
new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2.5 }, actionLbl)

-- на телефоне — как кнопка факела: справа от столбика кнопок и мельче
do
	local UIS = game:GetService("UserInputService")
	if UIS.TouchEnabled and not UIS.MouseEnabled then
		holder.Position = UDim2.new(0, 214, 0, 140)
		new("UIScale", { Scale = 0.65 }, holder)
	end
end

-- ══════════ Призрак установки ══════════
local function destroyGhost()
	--[[ ⚠️ СЕАНС ЗАКРЫВАЕМ ТОЛЬКО ВМЕСТЕ С НАСТОЯЩИМ ПРИЗРАКОМ.
	     Дозор ниже зовёт createGhost КАЖДЫЙ КАДР, пока призрак не построится
	     (объект приезжает в ReplicatedStorage не мгновенно), а createGhost
	     начинается с этой функции. Закрывай она сеанс безусловно — кнопки
	     телефона гасли и зажигались по шестьдесят раз в секунду, а точка тапа
	     стиралась раньше, чем игрок успевал нажать «ПОСТАВИТЬ».
	     Нет призрака — нечего и закрывать. ]]
	if ghost then
		ghost:Destroy()
		ghost = nil
		TouchPlace.finish()
	end
	ghostOffset, ghostValid, rotation = nil, false, 0
end

-- Найти то, что игрок несёт: сам объект лежит в ReplicatedStorage.RelocateStash
-- (сервер кладёт его туда именно ради призрака). Если по какой-то причине его
-- там нет — берём одноимённый шаблон.
local function findCarried(key)
	local folder = ReplicatedStorage:FindFirstChild("RelocateStash")
	if folder then
		local exact = folder:FindFirstChild(key)
		if exact then return exact end
		for _, c in ipairs(folder:GetChildren()) do
			if c.Name:lower() == key:lower() then return c end
		end
		-- склад на одного игрока: если там ровно один объект, это он
		local kids = folder:GetChildren()
		if #kids == 1 then return kids[1] end
	end
	local t = ReplicatedStorage:FindFirstChild(key)
	if t then return t end
	for _, c in ipairs(ReplicatedStorage:GetChildren()) do
		if c.Name:lower() == key:lower() then return c end
	end
	return nil
end

local function createGhost(key)
	destroyGhost()
	local template = findCarried(key)
	if not template then
		--[[ ⚠️ БЕЗ ПРИЗРАКА СТАВИТЬ ВСЁ РАВНО НАДО — И НА ТЕЛЕФОНЕ ТОЖЕ.
		     Шаблона для предпросмотра может не оказаться, и файл к этому готов:
		     точка установки считается независимо от призрака, иначе игрок платит
		     за перенос и остаётся с предметом в руках.
		     Значит и сеанс установки обязан начаться: иначе на телефоне не будет
		     ни прицела, ни кнопки «ПОСТАВИТЬ» — то есть поставить нельзя вообще,
		     хотя до правки тап хоть как-то срабатывал. Начинаем сеанс без
		     исключения призрака: исключать нечего, его нет. ]]
		-- только если сеанса ещё нет: дозор зовёт нас каждый кадр, а begin
		-- сбрасывает выбранную точку — она стиралась бы, не успев пригодиться
		if not TouchPlace.active() then
			TouchPlace.begin({
				confirm = function() if onPlaceClick then onPlaceClick() end end,
				rotate  = function() if rotatePlacement then rotatePlacement() end end,
			})
		end
		return
	end

	ghost = template:Clone()
	ghost.Name = "RelocateGhost"
	for _, d in ipairs(ghost:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = 0.5
			d.CanCollide = false
			d.Anchored = true
			d.Color = Color3.fromRGB(80, 255, 80)
			d.Material = Enum.Material.SmoothPlastic
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("ProximityPrompt") or d:IsA("ClickDetector")
			or d:IsA("BillboardGui") or d:IsA("SurfaceGui")
			or d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") then
			d:Destroy()
		end
	end
	if ghost:IsA("Model") and not ghost.PrimaryPart then
		local bb = ghost:GetBoundingBox()
		ghost.WorldPivot = CFrame.new(bb.Position)
	end
	ghost.Parent = workspace
	--[[ ⚠️ ПОМЕЧАЕМ ПРИЗРАК, ЧТОБЫ ЕГО НЕ ПРИНЯЛИ ЗА ПОСТРОЙКУ.
	     Призрак — полная копия модели, с тем же именем. Чужие системы ищут свои
	     объекты именно по имени и находили его: подсказка плавильни начиналась,
	     когда печь ещё в руках, а не на плоту. Метка стоит копейки и снимает
	     целый класс таких путаниц. ]]
	ghost:SetAttribute("PlacementGhost", true)

	--[[ ⚠️ СЕАНС УСТАНОВКИ НАЧИНАЕМ ЗДЕСЬ, А НЕ В ОБРАБОТЧИКЕ ЭКИПИРОВКИ.
	     Призрак строится ровно тогда, когда предмет переноса оказался в руках, —
	     каким бы из переносимых объектов он ни был. Одна точка на все, и новый
	     переносимый объект получит телефонную схему даром.
	     Подтверждение и поворот определены ниже по файлу, поэтому зовём их через
	     обёртки: к моменту нажатия кнопки они уже на месте. ]]
	TouchPlace.begin({
		confirm = function() if onPlaceClick then onPlaceClick() end end,
		rotate  = function() if rotatePlacement then rotatePlacement() end end,
		-- призрак заслоняет палубу: без этого тап упирался бы в него самого
		ignore  = function() return ghost end,
	})
end

local function setGhostColor(valid)
	ghostValid = valid
	local c = valid and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
	if ghost then
		for _, p in ipairs(ghost:GetDescendants()) do
			if p:IsA("BasePart") then p.Color = c end
		end
	end
	--[[ ⚠️ ЦВЕТ ДЕТАЛЕЙ НА ТЕКСТУРНОЙ МОДЕЛИ НЕ ВИДЕН — НУЖНА ПОДСВЕТКА.
	     Выше мы красим сами детали, и на однотонных примитивах этого хватает. Но
	     мангал, бочка, плавильня и грядка — меши со своей текстурой: заданный
	     цвет по ним почти не читается, и призрак выглядел обычным предметом. У
	     очистителя подсветка была, у остальных нет — отсюда и «подсвечивается
	     только он».
	     Highlight поверх всей модели красит силуэт независимо от текстуры и
	     работает одинаково у всех. Создаём при первом обращении: призрак
	     пересоздаётся, и держать ссылку негде. ]]
	if ghost then
		local hl = ghost:FindFirstChild("GhostHighlight")
		if not hl then
			hl = Instance.new("Highlight")
			hl.Name = "GhostHighlight"
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Adornee = ghost
			hl.Parent = ghost
		end
		local hlColor = valid and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
		hl.FillColor = hlColor
		hl.OutlineColor = hlColor
		hl.FillTransparency = 0.15
		hl.OutlineTransparency = 0
	end
end

-- Цель установки считается НЕЗАВИСИМО от призрака: если модель для превью не
-- нашлась, поставить предмет всё равно нужно — иначе игрок платит за перенос и
-- остаётся с предметом, который некуда деть.
local function updateGhost()
	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then
		ghostOffset = nil
		if ghost then setGhostColor(false) end
		return
	end
	-- Луч прицела: на компьютере из курсора, на телефоне — в точку тапа (TouchPlace)
	local unitRay = TouchPlace.ray(mouse)
	if not unitRay then
		-- телефон, места ещё не выбрали: целить некуда, как при промахе луча
		ghostOffset = nil
		if ghost then setGhostColor(false) end
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ghost, player.Character }

	local res = workspace:Raycast(unitRay.Origin, unitRay.Direction * 250, params)
	if not res or not res.Instance or not res.Instance:IsDescendantOf(raft) then
		ghostOffset = nil
		if ghost then setGhostColor(false) end
		return
	end

	local lift = 0
	if ghost then
		local _, size = ghost:GetBoundingBox()
		lift = size.Y * 0.5
	end
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local cf = CFrame.new(res.Position.X, res.Position.Y + lift, res.Position.Z)
		* CFrame.Angles(0, restYaw + rotation, 0)
	if ghost then
		ghost:PivotTo(cf)
		setGhostColor(true)
	end
	ghostOffset = raft.PrimaryPart.CFrame:ToObjectSpace(cf)
	ghostValid = true
end

-- ══════════ Что держим в руках ══════════
local function heldRelocateTool()
	local char = player.Character
	if not char then return nil end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if tool and catalog[tool.Name] then return tool end
	return nil
end

-- ⚠️ КНОПКА ПЕРЕНОСА ПОЯВЛЯЕТСЯ ТОЛЬКО С МОЛОТКОМ В РУКАХ.
-- Раньше она всплывала над каждым переносимым объектом, стоило подойти: пройти
-- мимо ремонтной станции с пустыми руками было нельзя, не получив пол-экрана
-- подсказки. Перенос — это стройка, а стройка в игре делается молотком, так что
-- условие то же, что и на постановку клетки пола.
local HAMMER = "Hammer"
local function holdingHammer()
	local char = player.Character
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	return tool ~= nil and tool.Name == HAMMER
end

-- ══════════ Поиск ближайшего переносимого объекта ══════════
local function findNear()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local raft = workspace:FindFirstChild("Raft")
	if not hrp or not raft then return nil, nil end

	local best, bestSpec, bestD
	for _, child in ipairs(raft:GetChildren()) do
		if child:IsA("Model") then
			local spec = catalog[child.Name]
			if not spec then
				for key, s in pairs(catalog) do
					if child.Name:lower() == key:lower() then spec = s break end
				end
			end
			if spec then
				local p = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart", true)
				if p then
					local d = (p.Position - hrp.Position).Magnitude
					if d <= PICKUP_RADIUS and (not bestD or d < bestD) then
						best, bestSpec, bestD = child, spec, d
					end
				end
			end
		end
	end
	return best, bestSpec
end

local function pirateBalance()
	-- клиентская копия баланса, если её кто-то публикует; иначе не блокируем —
	-- сервер всё равно проверит и вернёт «denied»
	local v = player:GetAttribute("Pirate") or player:GetAttribute("Pirates")
	return tonumber(v)
end

RunService.Heartbeat:Connect(function()
	-- Пока держим предмет — кнопку подбора не показываем, ведём призрак.
	local tool = heldRelocateTool()
	if tool then
		gui.Enabled = false
		-- Призрак пробуем построить, пока не вышло: объект приезжает в
		-- ReplicatedStorage не мгновенно после подбора.
		if not ghost then createGhost(tool.Name) end
		updateGhost()
		heldKey = tool.Name
		return
	end
	if ghost then destroyGhost() end
	-- предмета в руках нет — сеанса быть не должно даже если призрака так и не
	-- построили (destroyGhost закрывает его только вместе с призраком)
	if TouchPlace.active() then TouchPlace.finish() end
	ghostOffset, ghostValid = nil, false
	heldKey = nil

	-- Без молотка переносить нечего — и подсказывать не о чем.
	if not holdingHammer() then
		nearModel, nearSpec = nil, nil
		gui.Enabled = false
		return
	end

	local m, spec = findNear()
	nearModel, nearSpec = m, spec
	if not m then gui.Enabled = false return end

	nameLbl.Text = spec.label or m.Name
	btn.Image = spec.icon or ""
	-- после отказа причина висит над кнопкой (см. «denied»), ценой её не затираем
	if os.clock() < (priceLbl:GetAttribute("DeniedUntil") or 0) then gui.Enabled = true return end
	local have = pirateBalance()
	if have and have < spec.price then
		priceLbl.Text = "не хватает"
		priceLbl.TextColor3 = Color3.fromRGB(255, 110, 110)
	else
		priceLbl.Text = tostring(spec.price)
		priceLbl.TextColor3 = Color3.fromRGB(255, 210, 58)
	end
	gui.Enabled = true
end)

btn.Activated:Connect(function()
	if not nearModel then return end
	evt:FireServer("pickup", nearModel)
end)

-- поворот на четверть — общий для клавиши R и для экранной кнопки на телефоне
function rotatePlacement()
	rotation = rotation + math.rad(90)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not ghost then return end
	if GamepadInput.isKey(input, Enum.KeyCode.R) then
		rotatePlacement()
	end
end)

-- Подтверждение постановки. Тело общее: на компьютере его зовёт ЛКМ, на
-- телефоне — кнопка «ПОСТАВИТЬ».
function onPlaceClick()
	-- Ставим по вычисленной цели, а не по наличию призрака.
	if not heldRelocateTool() or not ghostValid or not ghostOffset then return end
	evt:FireServer("place", ghostOffset)
	local folder = (SoundService:FindFirstChild("Building") or SoundService:FindFirstChild("Building", true))
	local snd = folder and folder:FindFirstChild("Place_Block")
	if snd then snd:Play() end
end

--[[ ⚠️ НА ТЕЛЕФОНЕ ТАП НЕ СТАВИТ — ОН ВЫБИРАЕТ МЕСТО.
     Roblox превращает касание экрана в тот же Button1Down, поэтому раньше первый
     же тап мгновенно ставил объект по координатам ПРЕДЫДУЩЕГО касания: игрок
     ещё целился, а тотем уже стоял не там. Пока идёт сеанс установки, тап отдаём
     модулю (он двигает прицел), а ставит кнопка «ПОСТАВИТЬ». ]]
GamepadInput.onPrimary(mouse, function()
	--[[ ⚠️ ПАЛЕЦ НЕ СТАВИТ НИКОГДА, ПОКА ВИСИТ ПРИЗРАК.
	     Здесь стояла проверка через модуль (isPhone и active). Она верна по
	     смыслу, но зависит от того, что модуль поднялся и сеанс открылся, — а
	     если хоть одно не сложилось, тап снова ставил предмет. Игрок крутит
	     камеру пальцем, и КАЖДЫЙ поворот превращался в постройку.
	     Поэтому спрашиваем СВОЁ состояние: висит призрак — значит идёт установка,
	     и палец в ней только целится. Ставит кнопка, она зовёт onPlaceClick
	     напрямую и мимо этой проверки. Хуже возможного исхода нет: не поднялся
	     модуль — предмет не поставится, но и не встанет туда, куда не целились. ]]
	if IS_TOUCH and ghost then return end
	onPlaceClick()
end)

evt.OnClientEvent:Connect(function(action, a)
	if action == "catalog" then
		catalog = a or {}
	elseif action == "placed" then
		destroyGhost()
	elseif action == "denied" then
		--[[ ⚠️ ПРИЧИНУ ОТКАЗА ДЕРЖИМ НА ЭКРАНЕ. Раньше она писалась в строку цены,
		     а покадровый цикл тут же затирал её ценой — отказ («Сначала почини
		     монолит») не было видно ни кадра, и казалось, что кнопка не работает.
		     Теперь строка держится 3 с, и дублируется уведомлением. ]]
		priceLbl.Text = "нельзя"   -- полная причина — в уведомлении (строка узкая)
		priceLbl.TextColor3 = Color3.fromRGB(255, 110, 110)
		priceLbl:SetAttribute("DeniedUntil", os.clock() + 3)
		if typeof(_G.Notify) == "function" then
			pcall(_G.Notify, { type = "warn", icon = "no", title = "Перенос", body = tostring(a) })
		end
	end
end)

evt:FireServer("catalog")
