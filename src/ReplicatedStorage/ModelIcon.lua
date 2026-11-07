--[[
	ИКОНКА — ЭТО САМА МОДЕЛЬ, А НЕ КАРТИНКА.

	ViewportFrame рисует настоящую модель прямо в интерфейсе. Для предметов,
	которые в игре уже есть, это лучше нарисованной иконки сразу по трём статьям:

	  • совпадение. Пять стен различаются как раз геометрией — на рисованных
	    иконках они выглядели одинаковыми плашками, и выбрать было невозможно;
	  • согласованность. Один ракурс и один свет на весь набор задаются здесь,
	    а не выдерживаются художником от иконки к иконке;
	  • обслуживание. Поменяли модель — иконка изменилась сама. Ни загрузки, ни
	    модерации, ни устаревших id по всему коду.

		local ModelIcon = require(ReplicatedStorage.ModelIcon)
		ModelIcon.render(iconBox, wallTemplate)

	Рисованные иконки остаются там, где модели нет вовсе: ресурсы, статусы,
	значки квестов.
]]

local ModelIcon = {}

-- ⚠️ ОДИН РАКУРС И ОДИН СВЕТ НА ВЕСЬ НАБОР.
-- В этом весь смысл затеи: согласованность держится числами здесь, а не
-- аккуратностью в сорока местах. Менять — только тут.
local VIEW_DIR = Vector3.new(-0.62, 0.42, -0.66).Unit  -- откуда смотрим на предмет
-- Угол узкий намеренно: на широком предмет «разъезжается» перспективой, ближний
-- край раздувается, и одинаковые вещи выглядят разными.
local FOV = 20
-- Запас до рамки. Держим маленьким: чем плотнее модель заполняет ViewportFrame,
-- тем больше пикселей ей достаётся — сглаживания здесь нет, и «воздух» по краям
-- оплачивается чёткостью самой вещи.
local PAD = 1.03
local LIGHT_DIR = Vector3.new(-0.35, -1, -0.55).Unit
local LIGHT_COLOR = Color3.fromRGB(255, 250, 238)
local AMBIENT = Color3.fromRGB(150, 150, 158)

-- ⚠️ КЛОН ЧИСТИМ ОТ ВСЕГО, ЧТО НЕ ГЕОМЕТРИЯ.
-- В шаблонах живут скрипты, звуки, подсказки и партиклы. В ViewportFrame они
-- либо бесполезны, либо вредны: скрипт в иконке запустится, звук зазвучит, а
-- ProximityPrompt покажет кнопку «нажми E» посреди меню.
local function stripToVisual(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") or d:IsA("Sound")
			or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")
			or d:IsA("ProximityPrompt") or d:IsA("ClickDetector")
			or d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("Highlight") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			-- в ViewportFrame физики нет вовсе, но заанкоренная деталь дешевле и
			-- гарантированно не уедет, если клон вдруг окажется в мире
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

-- ⚠️ ГАБАРИТ СЧИТАЕМ И ДЛЯ ТОГО, ЧТО НЕ Model И НЕ BasePart.
-- Половина предметов в хранилище — это Tool (молоток, огнемёт, кружка), а у
-- Tool нет ни GetBoundingBox, ни Size. Раньше такие просто не рисовались.
-- Считаем мировую габаритную коробку по деталям внутри — работает для чего
-- угодно, что вообще состоит из деталей.
local function boundsOf(inst)
	if inst:IsA("BasePart") then
		return inst.CFrame, inst.Size
	end
	if inst:IsA("Model") then
		local ok, cf, size = pcall(function()
			local c, s = inst:GetBoundingBox()
			return c, s
		end)
		if ok and cf and size then return cf, size end
	end

	local lo, hi
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, sz = d.CFrame, d.Size
			local ext = Vector3.new(
				math.abs(cf.RightVector.X) * sz.X + math.abs(cf.UpVector.X) * sz.Y
					+ math.abs(cf.LookVector.X) * sz.Z,
				math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y
					+ math.abs(cf.LookVector.Y) * sz.Z,
				math.abs(cf.RightVector.Z) * sz.X + math.abs(cf.UpVector.Z) * sz.Y
					+ math.abs(cf.LookVector.Z) * sz.Z) * 0.5
			local p = d.Position
			lo = lo and lo:Min(p - ext) or (p - ext)
			hi = hi and hi:Max(p + ext) or (p + ext)
		end
	end
	if not lo then return nil, nil end
	return CFrame.new((lo + hi) * 0.5), (hi - lo)
end

--[[ Рисует модель в переданном контейнере и возвращает ViewportFrame (или nil,
     если рисовать нечего). Старую иконку из контейнера НЕ убирает — это дело
     вызывающего: он знает, чем заменяет. ]]
function ModelIcon.render(parent, template)
	if not (parent and template) then return nil end

	local okClone, clone = pcall(function() return template:Clone() end)
	if not okClone or not clone then return nil end
	stripToVisual(clone)

	local cf, size = boundsOf(clone)
	if not cf or size.Magnitude < 1e-3 then
		clone:Destroy()
		return nil
	end

	local vp = Instance.new("ViewportFrame")
	vp.Name = "ModelIcon"
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.5)
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.LightDirection = LIGHT_DIR
	vp.LightColor = LIGHT_COLOR
	vp.Ambient = AMBIENT
	vp.Parent = parent

	clone.Parent = vp

	-- ⚠️ ДИСТАНЦИЮ СЧИТАЕМ ПО УГЛАМ ГАБАРИТА, А НЕ ПО ЕГО ДИАГОНАЛИ.
	-- Диагональ (габаритная сфера) — самый простой способ гарантировать, что
	-- предмет влезет, но у ПЛОСКИХ вещей она сильно больше того, что реально
	-- видно: стена занимала бы половину рамки и выглядела мелкой рядом с
	-- бочкой. Проецируем восемь углов на плоскость камеры и берём наибольший
	-- отступ от центра — тогда рамку заполняет ровно силуэт.
	local viewCF = CFrame.lookAt(cf.Position + VIEW_DIR, cf.Position)
	local half = size * 0.5
	local maxR = 0
	for sx = -1, 1, 2 do
		for sy = -1, 1, 2 do
			for sz = -1, 1, 2 do
				local corner = (cf * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position
				local p = viewCF:PointToObjectSpace(corner)
				maxR = math.max(maxR, math.sqrt(p.X * p.X + p.Y * p.Y))
			end
		end
	end

	local dist = (maxR * PAD) / math.tan(math.rad(FOV * 0.5))
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.CFrame = CFrame.lookAt(cf.Position + VIEW_DIR * dist, cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam

	return vp
end

--[[ ══════════ СКРЫТАЯ ПОЛКА ИКОНОК (клиент) ══════════
     ⚠️ КАК РАБОТАЕТ КЭШ. Скачать иконку заранее (PreloadAsync) мало: картинка и
     модель окончательно готовы, только когда их ХОТЯ БЫ РАЗ НАРИСОВАЛИ на экране.
     Поэтому первый заход в инвентарь показывал, как иконки «прогружаются», а
     второй — уже нет: в первый раз они и рисовались впервые.
     Значит, их надо нарисовать у игрока ДО первого открытия меню — скрыто:
       • пока висит шторка загрузки (DestinationLoadingScreen, DisplayOrder 10000)
         — в полный размер прямо под ней (9999): игрок видит шторку, а движок
         честно рисует каждую картинку и модель;
       • после шторки (и если шторки не было вовсе) — та же полка ужата до точки
         в пару пикселей с почти полной прозрачностью под кнопкой меню Roblox:
         её не видно, но она продолжает рисоваться, и кэш не остывает.
     Полку НЕ удаляем никогда: удалённую картинку движок со временем выгрузит.

     Иконки-модели крафта: warm() рисует модель на полке, take() отдаёт меню ЭТУ
     ЖЕ рамку (перенос, не клон), reclaim() перед очисткой меню возвращает её на
     полку. Один шаблон занят дважды — второй рисуется по-старому (render). ]]
local pool = {}        -- [template] = { ViewportFrame, ... } (готовых кадров может быть несколько)
local inUse = {}       -- [ViewportFrame] = true
local warmedImages = {} -- [id] = true

local CELL = 72
local shelfCount = 0
local function curtainUp()
	local RF = game:GetService("ReplicatedFirst")
	if RF:GetAttribute("CurtainLifting") then return false end
	local lp = game:GetService("Players").LocalPlayer
	local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
	return pg ~= nil and pg:FindFirstChild("DestinationLoadingScreen") ~= nil
end
ModelIcon.curtainUp = curtainUp

-- ⚠️ модуль грузится РАНЬШЕ шторки (его зовёт AssetPreload из ReplicatedFirst):
-- «шторки нет» в первые секунды значит «ещё не появилась», а не «уже ушла»
local startedAt = os.clock()
local sawCurtain = false
local function curtainGone()
	if curtainUp() then sawCurtain = true return false end
	return sawCurtain or os.clock() - startedAt > 5
end

local shelfGui = nil
local compact = false   -- полка ужата (шторки уже нет)
local function shelf()
	if shelfGui and shelfGui.Parent then return shelfGui end
	local lp = game:GetService("Players").LocalPlayer
	local pg = lp and (lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui", 10))
	if not pg then return nil end
	shelfGui = Instance.new("ScreenGui")
	shelfGui.Name = "IconWarmShelf"
	shelfGui.ResetOnSpawn = false
	shelfGui.IgnoreGuiInset = true
	shelfGui.DisplayOrder = 9999   -- под шторкой (10000); ужатая — уже неважно
	-- ⚠️ ПОЛКУ НЕ ГАСИТЬ: выключенный ViewportFrame не рисуется, и после включения
	-- кадр строится заново — весь кэш иконок остывал (режим стройки гасит HUD)
	shelfGui:SetAttribute("KeepEnabled", true)
	shelfGui.Parent = pg
	return shelfGui
end

-- место элемента на полке: под шторкой — сетка в полный размер, после — точка
local COMPACT_POS = UDim2.fromOffset(28, 18)   -- под кнопкой меню Roblox (CoreGui рисуется поверх)
local function place(obj)
	obj.AnchorPoint = Vector2.new(0, 0)
	obj.ZIndex = 1
	if compact and obj:IsA("ViewportFrame") then
		--[[ ⚠️ МОДЕЛЬ — В ПОЛНЫЙ РАЗМЕР, НО ЗА КРАЕМ ЭКРАНА. Ужатая в точку, она
		     рисовалась с самой грубой детализацией меша и текстуры, и в меню (64 px)
		     нужная догружалась на глазах: огнемёт, предметы пака. Поэтому рамка
		     прежнего размера, а на экране от неё уголок в 2 px под кнопкой меню
		     Roblox, почти прозрачный: движок рисует её целиком, игрок не видит. ]]
		obj.Size = UDim2.fromOffset(CELL - 8, CELL - 8)
		obj.Position = UDim2.fromOffset(-(CELL - 8) + 2, -(CELL - 8) + 2)
		obj.ImageTransparency = 0.98
	elseif compact then
		obj.Position = COMPACT_POS
		obj.Size = UDim2.fromOffset(3, 3)
		obj.ImageTransparency = 0.97   -- не 1: полностью прозрачное движок может не рисовать
	else
		local cam = workspace.CurrentCamera
		local cols = math.max(1, math.floor(((cam and cam.ViewportSize.X) or 800) / CELL))
		local i = shelfCount
		shelfCount += 1
		obj.Position = UDim2.fromOffset((i % cols) * CELL, math.floor(i / cols) % 10 * CELL)
		obj.Size = UDim2.fromOffset(CELL - 8, CELL - 8)
		obj.ImageTransparency = 0
	end
end

local function compactShelf()
	if compact then return end
	compact = true
	if shelfGui then
		for _, d in ipairs(shelfGui:GetChildren()) do
			if d:IsA("GuiObject") then place(d) end
		end
	end
end

-- картинки (rbxassetid) — нарисовать скрыто и держать
function ModelIcon.warmImages(ids)
	local gui = shelf()
	if not gui then return 0 end
	if curtainGone() then compactShelf() end
	local n = 0
	for _, id in ipairs(ids) do
		if type(id) == "string" and id ~= "" and not warmedImages[id] then
			warmedImages[id] = true
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Image = id
			place(img)
			img.Parent = gui
			n += 1
		end
	end
	return n
end

local function park(vp)
	inUse[vp] = nil
	local gui = shelf()
	if not gui then return end
	if curtainGone() then compactShelf() end
	place(vp)
	vp.Parent = gui
end

--[[ warm(template, count) — держать на полке count готовых кадров модели
     (по умолчанию 1). Несколько — когда одна вещь видна в двух местах сразу:
     рыбацкое место в окне торговца и тут же в хотбаре после выдачи — второй
     кадр иначе рисовался бы с нуля и пару секунд стоял пустым. ]]
local function alive(template)
	local list = pool[template] or {}
	for i = #list, 1, -1 do
		if not list[i].Parent then table.remove(list, i) end
	end
	pool[template] = list
	return list
end

function ModelIcon.warm(template, count)
	if not template then return end
	local list = alive(template)
	local gui = shelf()
	if not gui then return end
	for _ = #list + 1, math.max(1, count or 1) do
		local vp = ModelIcon.render(gui, template)
		if not vp then return end
		vp:SetAttribute("Pooled", true)
		table.insert(list, vp)
		park(vp)
	end
end

function ModelIcon.take(parent, template)
	if not (parent and template) then return nil end
	local list = alive(template)
	if #list == 0 then
		ModelIcon.warm(template)
		list = alive(template)
	end
	local vp = nil
	for _, v in ipairs(list) do
		if not inUse[v] then vp = v break end
	end
	if not vp then return ModelIcon.render(parent, template) end
	inUse[vp] = true
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.5)
	vp.Size = UDim2.fromScale(1, 1)
	vp.ImageTransparency = 0
	vp.Parent = parent
	return vp
end

--[[ ИКОНКИ-МОДЕЛИ ИНСТРУМЕНТОВ. У огнемёта, сеткомёта и прочих тулов без
     картинки инвентарь рисует модель (ModelIcon.render): одноимённую из
     ReplicatedStorage, иначе сам тул; у заготовок «поставить на плот» — модель
     из атрибута PreviewModel. Греем ровно её, как только тул попал к игроку, —
     до того, как он откроет инвентарь. Один раз на имя. ]]
local warmedNames = {}
local function warmTool(tool)
	if not (tool and tool:IsA("Tool")) then return end
	local preview = tool:GetAttribute("PreviewModel")
	local key = (type(preview) == "string" and preview ~= "") and preview or tool.Name
	if warmedNames[key] then return end
	warmedNames[key] = true
	task.spawn(function()
		local okF, AssetFind = pcall(function()
			return require(game:GetService("ReplicatedStorage"):WaitForChild("AssetFind", 5))
		end)
		local tpl = okF and AssetFind and AssetFind.find(key) or nil
		if not tpl and key == tool.Name then tpl = tool end
		if tpl then ModelIcon.warm(tpl) end
	end)
end
ModelIcon.warmTool = warmTool

if game:GetService("RunService"):IsClient() then
	local RF = game:GetService("ReplicatedFirst")
	task.spawn(function()
		local lp = game:GetService("Players").LocalPlayer
		if not lp then return end
		local function watch(container)
			if not container then return end
			for _, c in ipairs(container:GetChildren()) do warmTool(c) end
			container.ChildAdded:Connect(warmTool)
		end
		watch(lp:WaitForChild("Backpack", 30))
		lp.ChildAdded:Connect(function(c) if c:IsA("Backpack") then watch(c) end end)
		if lp.Character then watch(lp.Character) end
		lp.CharacterAdded:Connect(watch)
	end)
	-- шторка пошла гаснуть — ужимаем полку мгновенно, до начала затухания
	RF:GetAttributeChangedSignal("CurtainLifting"):Connect(function()
		if RF:GetAttribute("CurtainLifting") then compactShelf() end
	end)
	-- шторку убрали без сигнала (или её не было) — всё равно ужимаем
	task.spawn(function()
		while not compact do
			task.wait(0.25)
			if curtainGone() then compactShelf() end
		end
	end)
end

-- вернуть на полку все рамки из пула внутри container (звать ДО Destroy)
function ModelIcon.reclaim(container)
	if not container then return end
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("ViewportFrame") and d:GetAttribute("Pooled") then park(d) end
	end
end

return ModelIcon
