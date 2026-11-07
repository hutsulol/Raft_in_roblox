--[[
	НЕФТЕВЫШКА: постановка на остров и два рабочих.

	Ставится молотком на плитки суши (Island_terrain_*), после чего живёт сама:
	бурильщик качает нефть и выставляет полные канистры, носильщик уносит их к
	баку и выливает — в этот момент игроку капает доход.

	⚠️ ПРОВЕРЯЕМ ВОДУ, А НЕ ТОЛЬКО ИМЯ ПЛИТКИ.
	Часть плиток острова уходит под воду, и по имени они не отличаются никак.
	Поэтому под каждым углом будущего настила бьём луч вниз: попал в воду или
	настил оказался к ней ближе WATER_CLEAR — ставить нельзя.

	⚠️ АНИМАЦИИ БЕЗ ПУБЛИКАЦИИ. Клипы из набора лежат в FBX и не опубликованы, а
	в этом плейсе чужие анимации и так не грузятся. Играем ближайшие из
	PirateCrewClips через атрибут Clip — позу считает клиент (см. OilRigDefs).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local PlaceCheckMod = nil
pcall(function() PlaceCheckMod = require(ReplicatedStorage:WaitForChild("PlaceCheck", 10)) end)
local Lighting          = game:GetService("Lighting")
local PhysicsService    = game:GetService("PhysicsService")

local Defs = require(ReplicatedStorage:WaitForChild("OilRigDefs"))
local HouseDefs = require(ReplicatedStorage:WaitForChild("HouseDefs"))
local SignFace = require(ReplicatedStorage:WaitForChild("SignFace"))
local OilCanister = require(ReplicatedStorage:WaitForChild("OilCanister"))
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

local LOG = "[Вышка]"

-- Цена постройки вышки. ⚠️ ТА ЖЕ ЦИФРА В МЕНЮ МОЛОТКА
-- (StarterPlayerScripts/BuildingSystem.client.lua, пункт «Нефтевышка»): клиент
-- её рисует, списывает сервер здесь. Меняешь — меняй в обоих местах.
local RIG_COST_RES = "Log"
local RIG_COST = 12
local placeEvent = ReplicatedStorage:FindFirstChild("OilRigPlace")
if not placeEvent then
	placeEvent = Instance.new("RemoteEvent")
	placeEvent.Name = "OilRigPlace"
	placeEvent.Parent = ReplicatedStorage
end

-- ═══════════ проверка места ═══════════

local waterRay = RaycastParams.new()
waterRay.IgnoreWater = false
waterRay.FilterType = Enum.RaycastFilterType.Exclude

local function isTerrainTile(inst)
	return inst and inst:IsA("BasePart")
		and inst.Name:sub(1, #Defs.TILE_PREFIX) == Defs.TILE_PREFIX
end

-- ⚠️ ГРУНТ ПОД ВЫШКОЙ ДОЛЖЕН БЫТЬ РОВНЫМ, А МЕСТО — ПУСТЫМ.
-- Проверять только «не вода» мало: на склоне холма вышка встаёт враспор, а на
-- камнях и пальмах — сквозь них. Поэтому три условия: суша, разброс высот под
-- опорами не больше FLAT_TOL и в габарите постройки ничего постороннего.
-- ⚠️ ДОПУСКИ НАРОЧНО МЯГКИЕ.
-- Плитки острова бугристые, и строгие 3.5 студа не давали поставить вышку
-- нигде: пляж «недостаточно ровный» на каждом шагу. 6 студов — это заметный
-- уклон, но сваи его берут (README: они уходят на 1.30 м вниз).
local FLAT_TOL = 6

-- ⚠️ ГАБАРИТ ПРОВЕРЯЕМ НЕ ВО ВСЮ ВЫСОТУ.
-- Ферма 10 метров и почти пустая; если мерить всю высоту, любая пальма рядом
-- «занимает место», хотя вышке она не мешает. Проверяем только нижний ярус —
-- настил и то, что реально упрётся в постройку.
local CHECK_HEIGHT = 10

-- что считается «землёй» и не мешает: сами плитки острова и морское дно
local function isGround(inst)
	local n = inst.Name
	return n:sub(1, #Defs.TILE_PREFIX) == Defs.TILE_PREFIX
		or n:sub(1, 13) == "Island_seabed"
end

local function spotOK(cf, size, ignore, flatTol)
	-- ⚠️ ДОПУСК ПО УКЛОНУ — ПАРАМЕТРОМ. Вышке и дому хватает FLAT_TOL, ферме с
	-- жёсткой оградой нужен строже (FarmDefs.FLAT_TOL); проверка при этом одна.
	flatTol = tonumber(flatTol) or FLAT_TOL
	waterRay.FilterDescendantsInstances = ignore or {}
	local half = size * 0.5
	local corners = {
		Vector3.new(-half.X, 0, -half.Z), Vector3.new(half.X, 0, -half.Z),
		Vector3.new(-half.X, 0, half.Z),  Vector3.new(half.X, 0, half.Z),
		Vector3.zero,
	}
	local onLand, lowest, highest = 0, math.huge, -math.huge
	for _, c in ipairs(corners) do
		local from = cf:PointToWorldSpace(c) + Vector3.new(0, 40, 0)
		local hit = Workspace:Raycast(from, Vector3.new(0, -120, 0), waterRay)
		if not hit then return false, "под опорой пусто" end
		if hit.Material == Enum.Material.Water then
			-- проверкой пользуется и дом (см. _G.OilRigSpotOK), поэтому без «вышки»
			return false, "угол постройки в воде"
		end
		if cf.Position.Y - hit.Position.Y < -Defs.WATER_CLEAR then
			return false, "настил ниже грунта"
		end
		if isTerrainTile(hit.Instance) then onLand += 1 end
		lowest = math.min(lowest, hit.Position.Y)
		highest = math.max(highest, hit.Position.Y)
	end
	if onLand < 3 then return false, "нужна суша острова" end
	if highest - lowest > flatTol then return false, "нужна ровная площадка" end

	--[[ ⚠️ ИГРОК ВНУТРИ ПОСТРОЙКИ — ОТКАЗ. Персонаж исключён из проверки занятости
	     (иначе он мешал бы сам себе у самого призрака), и дом ставился прямо
	     сквозь игрока: тот оказывался в стене и погибал (владелец). Проверяем
	     всех живых по горизонтали внутри габарита с небольшим запасом. ]]
	for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local l = cf:PointToObjectSpace(hrp.Position)
			if math.abs(l.X) <= half.X + 1.5 and math.abs(l.Z) <= half.Z + 1.5
				and l.Y > -6 and l.Y < size.Y + 6 then
				local mine = ignore and table.find(ignore, plr.Character) ~= nil
				return false, mine and "ты стоишь на месте постройки" or ("на месте постройки стоит " .. plr.Name)
			end
		end
	end

	-- ⚠️ ГАБАРИТ ПРОВЕРЯЕМ ВЫШЕ ЗЕМЛИ.
	-- Коробку поднимаем на полвысоты и чуть ужимаем: иначе в неё всегда попадает
	-- сам грунт, и «занято» показывалось бы всегда.
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	params.MaxParts = 40
	local h = math.min(size.Y, CHECK_HEIGHT)
	local boxCF = cf * CFrame.new(0, h * 0.5 + 1, 0)
	for _, part in ipairs(Workspace:GetPartBoundsInBox(boxCF,
		Vector3.new(size.X * 0.8, h, size.Z * 0.8), params)) do
		-- трава, ракушки и мелкие камни местом не считаются: см. Defs.isDecor
		if not isGround(part) and not Defs.isDecor(part) then
			-- игроку — русское имя предмета (PlaceCheck), а не имя модели из Workspace
			local owner = part:FindFirstAncestorWhichIsA("Model") or part
			local ru = PlaceCheckMod and PlaceCheckMod.displayName(owner.Name) or owner.Name
			if ru == owner.Name or ru == part.Name then
				ru = PlaceCheckMod and PlaceCheckMod.displayName(part.Name) or part.Name
				if ru == part.Name then ru = "другой предмет" end
			end
			return false, "место занято: " .. ru
		end
	end
	return true
end

-- ⚠️ УБИРАЕМ ТОЛЬКО ОТДЕЛЬНЫЕ МЕЛКИЕ ДЕТАЛИ, А НЕ ВСЁ, ЧТО ПРОШЛО КАК ДЕКОР.
-- В паках островов пропы СКЛЕЕНЫ в батчи: «320 пропов в 20 мешей» (README).
-- Значит Rocks_024 — это одна деталь на россыпь камней по всему острову, и её
-- габарит накрывает пол-острова. Ставить она не мешает (isDecor пропускает её по
-- имени), но снести её значит стереть камни везде разом. Поэтому здесь условие
-- строже: только то, что и правда мелкое.
local function clearDecor(cf, size)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	params.MaxParts = 300
	local h = math.min(size.Y, CHECK_HEIGHT)
	local boxCF = cf * CFrame.new(0, h * 0.5, 0)
	local removed = 0
	for _, part in ipairs(Workspace:GetPartBoundsInBox(boxCF,
		Vector3.new(size.X * 0.85, h, size.Z * 0.85), params)) do
		local s = part.Size
		local small = math.max(s.X, s.Y, s.Z) <= Defs.DECOR_MAX
		if not isGround(part) and small and Defs.isDecor(part) then
			part:Destroy()
			removed += 1
		end
	end
	return removed
end

_G.OilRigClearDecor = function(cf, size) return clearDecor(cf, size) end

_G.OilRigSpotOK = function(cf, size, ignore, flatTol) return spotOK(cf, size, ignore, flatTol) end

-- ═══════════ сборка станции ═══════════

local function findTemplate(name)
	for _, where in ipairs({ ReplicatedStorage, Workspace }) do
		-- в хранилище ищем по имени, а не по месту: шаблоны разложены по папкам (см. AssetFind)
		local m = (where == ReplicatedStorage and AssetFind.find(name)) or where:FindFirstChild(name)
		if m then return m end
	end
	return nil
end

-- ⚠️ ЗАПАСНЫЕ ТОЧКИ ИЗ README, ЕСЛИ МАРКЕРА В МОДЕЛИ НЕТ.
-- Числа там даны в осях модели (Blender): x вправо, y вперёд, z вверх. Правило
-- перевода из ROBLOX_INTEGRATION.md: Blender (x, y, z) → Roblox (x, z, −y).
local FALLBACK = {
	wp_drill = Vector3.new(-8.52, 1.95, -3.24),
	wp_can   = Vector3.new(-3.60, 1.95, -4.80),
	wp_tank  = Vector3.new(11.10, 1.95,  2.52),
	wp_rest  = Vector3.new( 2.70, 1.95, -6.60),
	fx_spray = Vector3.new(-8.70, 3.75,  0.00),
	fx_pour  = Vector3.new(11.10, 5.46,  1.14),
}

-- Канистра, которую носит рабочий. Имён у неё исторически два.
local CAN_NAMES = { "Raft_jerrycan_plastic", "Plastic_canister", "Jerrycan", "Canister" }

local function findCanister()
	for _, n in ipairs(CAN_NAMES) do
		local m = findTemplate(n)
		if m then return m end
	end
	return nil
end

local canWarned = false
local function warnCanOnce()
	if canWarned then return end
	canWarned = true
	warn(LOG .. " не нашёл модель канистры (" .. table.concat(CAN_NAMES, ", ")
		.. ") — носильщику нечего таскать")
end

local function markerCF(station, name)
	local m = station:FindFirstChild(name, true)
	if m and m:IsA("BasePart") then return m.CFrame end
	if m and m:IsA("Attachment") then return m.WorldCFrame end
	local off = FALLBACK[name]
	if off then
		-- маркера нет — считаем от пивота станции по числам из инструкции
		return station:GetPivot() * CFrame.new(off)
	end
	return nil
end

-- Маркеры — оранжевые кубики, в игре их видеть не должны. Позиции забираем и
-- гасим сами кубики (не удаляем: пригодятся, если захочешь подвинуть точки).
-- ⚠️ home_* СЮДА ЖЕ. Ночные точки — такие же служебные кубики, и настоящими
-- деталями постройки они не являются.
local function hideMarkers(station)
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name:sub(1, 3) == "wp_" or d.Name:sub(1, 3) == "fx_"
			or d.Name:sub(1, 5) == "home_") then
			d.Transparency = 1
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

local function oilFx(station)
	local sprayCF = markerCF(station, Defs.FX.spray)
	if not sprayCF then return nil end
	local host = station:FindFirstChild(Defs.FX.spray, true)

	-- ФОНТАН. Флипбук 8×8 из набора; если разметка в плейсе не заработает
	-- (так уже бывало со взрывом кислоты), капли всё равно летят — просто
	-- одним кадром.
	local jet = Instance.new("ParticleEmitter")
	jet.Name = "OilJet"
	jet.Texture = Defs.TEX_SPRAY
	jet.Enabled = false
	jet.Rate = 12
	jet.Lifetime = NumberRange.new(0.6, 0.9)
	jet.Speed = NumberRange.new(6, 10)
	jet.SpreadAngle = Vector2.new(8, 8)
	jet.EmissionDirection = Enum.NormalId.Top
	jet.Acceleration = Vector3.new(0, -60, 0)   -- капли обязаны падать обратно
	jet.Size = NumberSequence.new(2.2, 1.2)
	jet.Transparency = NumberSequence.new(0.05, 1)
	jet.LightInfluence = 1
	pcall(function()
		jet.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8
		jet.FlipbookMode = Enum.ParticleFlipbookMode.Loop
		jet.FlipbookFramerate = NumberRange.new(26, 30)
	end)
	jet.Parent = host

	local drops = Instance.new("ParticleEmitter")
	drops.Name = "OilDrops"
	drops.Texture = Defs.TEX_DROP
	drops.Enabled = false
	drops.Rate = 30
	drops.Lifetime = NumberRange.new(0.5, 1)
	drops.Speed = NumberRange.new(5, 12)
	drops.SpreadAngle = Vector2.new(35, 35)
	drops.EmissionDirection = Enum.NormalId.Top
	drops.Acceleration = Vector3.new(0, -60, 0)
	drops.Size = NumberSequence.new(0.35, 0.15)
	drops.Transparency = NumberSequence.new(0.1, 1)
	drops.LightInfluence = 1
	drops.Parent = host

	return { jet = jet, drops = drops }
end

-- ⚠️ СЧЁТЧИК РАСТЁТ ВО ВРЕМЯ РОЗЛИВА, А НЕ ВСПЫХИВАЕТ ИТОГОМ.
-- Как при рубке дерева: цифра появляется над точкой и быстро набегает, пока
-- идёт заливка. Итог тот же, но видно, что нефть льётся именно сейчас.
local function mlPopup(cf, amount, duration)
	local host = Instance.new("Part")
	host.Name = "OilGain"
	host.Anchored = true; host.CanCollide = false; host.CanQuery = false
	host.CanTouch = false; host.CastShadow = false; host.Transparency = 1
	host.Size = Vector3.one
	host.CFrame = cf
	host.Parent = Workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(150, 46)
	bb.StudsOffset = Vector3.new(0, 1.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 220
	bb.Parent = host

	local row = Instance.new("Frame")
	row.Size = UDim2.fromScale(1, 1)
	row.BackgroundTransparency = 1
	row.Parent = bb
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = row

	-- порядок и цвета как у «+N бревно» при рубке: сперва цифра, следом иконка
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(104, 32)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 26
	label.TextColor3 = Color3.fromRGB(255, 220, 100)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.5
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.Text = "+0 мл"
	label.LayoutOrder = 1
	label.Parent = row

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.fromOffset(30, 30)
	icon.BackgroundTransparency = 1
	icon.Image = Defs.TEX_DROP
	icon.ScaleType = Enum.ScaleType.Fit
	icon.LayoutOrder = 2
	icon.Parent = row

	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration and host.Parent do
			local k = (os.clock() - t0) / duration
			label.Text = ("+%d мл"):format(math.floor(amount * k + 0.5))
			task.wait(0.05)
		end
		label.Text = ("+%d мл"):format(amount)
		-- всплывает и тает
		for i = 1, 12 do
			if not host.Parent then return end
			bb.StudsOffset = Vector3.new(0, 1.5 + i * 0.12, 0)
			label.TextTransparency = i / 12
			label.TextStrokeTransparency = 0.5 + i / 24
			icon.ImageTransparency = i / 12
			task.wait(0.05)
		end
		host:Destroy()
	end)
end

-- ⚠️ НЕФТЬ ИДЁТ В ТУ ЖЕ БОЧКУ НА ПЛОТУ, ЧТО И ИЗ КАНИСТРЫ.
-- Ищем её штатным OilCanister.findTank и пишем тот же атрибут OilStored — значит
-- экран на бочке, шкала и заправка огнемёта увидят прибавку сразу, без отдельного
-- склада «нефти с вышки». Своя копия поиска тут была бы вторым источником правды.
local function addOilToTank(ml)
	local tank = OilCanister.findTank(Workspace)
	if not tank then
		warn(LOG .. " бочка на плоту не найдена — миллилитры девать некуда")
		return false
	end
	local have = OilCanister.tankStored(tank)
	tank:SetAttribute(OilCanister.TANK_ATTR,
		math.min(OilCanister.TANK_CAPACITY, have + ml))
	return true
end

-- ═══════════ вывеска ═══════════

local function infoBoard(station)
	local part
	for _, name in ipairs(Defs.INFO_NAMES) do
		local p = station:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then part = p break end
	end
	if not part then
		warn(LOG .. " деталь вывески (" .. table.concat(Defs.INFO_NAMES, ", ")
			.. ") в модели не найдена — писать текст некуда")
		return
	end

	local old = part:FindFirstChild("OilInfo")
	if old then old:Destroy() end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "OilInfo"
	-- лицевую сторону выбираем общим правилом: Front подходит не всегда, а при
	-- повороте вышки надпись оказывалась бы с изнанки
	gui.Face = SignFace.of(part, station)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0        -- ночью надпись должна читаться так же
	gui.Parent = part

	local pad = Instance.new("Frame")
	pad.Size = UDim2.fromScale(1, 1)
	pad.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	pad.BackgroundTransparency = 0.15
	pad.BorderSizePixel = 0
	pad.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = pad
	local inset = Instance.new("UIPadding")
	inset.PaddingTop = UDim.new(0.12, 0)
	inset.PaddingBottom = UDim.new(0.12, 0)
	inset.PaddingLeft = UDim.new(0.06, 0)
	inset.PaddingRight = UDim.new(0.06, 0)
	inset.Parent = pad

	local rows = Instance.new("UIListLayout")
	rows.FillDirection = Enum.FillDirection.Vertical
	rows.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rows.VerticalAlignment = Enum.VerticalAlignment.Center
	rows.Padding = UDim.new(0.05, 0)
	rows.Parent = pad

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.45)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(245, 246, 250)
	title.LayoutOrder = 1
	title.Parent = pad

	local rate = Instance.new("TextLabel")
	rate.Size = UDim2.fromScale(1, 0.38)
	rate.BackgroundTransparency = 1
	rate.Font = Enum.Font.GothamBold
	rate.TextScaled = true
	rate.TextColor3 = Color3.fromRGB(255, 220, 100)   -- цвет нефти, как у попапа
	rate.LayoutOrder = 2
	rate.Parent = pad

	-- Уровень живёт в атрибуте станции: будущая система улучшений просто пишет
	-- туда число, а вывеска перерисуется сама.
	-- ⚠️ ПУСТАЯ ВЫШКА ГОВОРИТ ОБ ЭТОМ ВСЛУХ.
	-- Без нефтяника она молча стоит, и понять почему нельзя ниоткуда: рабочих не
	-- видно, нефть не капает. Вывеска — единственное место, где игрок это увидит.
	local function redraw()
		local lvl = station:GetAttribute(Defs.LEVEL_ATTR) or Defs.LEVEL
		title.Text = ("%s - ур. %d"):format(Defs.INFO_TITLE, lvl)
		local crew, power = 0, 0
		if typeof(_G.HouseOilCrew) == "function" then crew, power = _G.HouseOilCrew() end
		if crew <= 0 then
			rate.Text = "Нужны жители: поселите\nнефтяника в доме"
			rate.TextColor3 = Color3.fromRGB(255, 122, 106)
		else
			rate.Text = ("Добыча - %dмл/день"):format(Defs.mlPerDay() * power)
			rate.TextColor3 = Color3.fromRGB(255, 220, 100)
		end
	end
	station:GetAttributeChangedSignal(Defs.LEVEL_ATTR):Connect(redraw)
	-- бригада меняется в меню дома, а не здесь: просто перечитываем раз в секунду
	task.spawn(function()
		while station.Parent do
			task.wait(1)
			redraw()
		end
	end)
	if station:GetAttribute(Defs.LEVEL_ATTR) == nil then
		station:SetAttribute(Defs.LEVEL_ATTR, Defs.LEVEL)
	end
	redraw()
end

-- ═══════════ рабочие ═══════════

local function setClip(model, name, once)
	if once then
		model:SetAttribute("ClipOnce", name)
		model:SetAttribute("ClipOnceT", Workspace:GetServerTimeNow())
	else
		model:SetAttribute("Clip", name)
		model:SetAttribute("ClipT", Workspace:GetServerTimeNow())
	end
end

local function prepWorker(model, cf)
	-- ⚠️ КОРПУС ОБЯЗАН СТАЛКИВАТЬСЯ, ИНАЧЕ РАБОЧИЙ ПРОВАЛИВАЕТСЯ.
	-- Прошлый заход снял коллизию со ВСЕХ деталей, чтобы носильщик не втыкался в
	-- трубы, — и бурильщик тут же провалился сквозь настил: стоять ему стало не
	-- на чем. Настил обязан держать, а мешающую обвязку разводим отдельно, через
	-- NoCollisionConstraint (см. passThrough ниже).
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = (d.Name == "HumanoidRootPart")
		elseif d:IsA("BaseScript") then
			d.Disabled = true   -- родной Animate перебил бы наши клипы
		end
	end
	pcall(function() model:PivotTo(cf) end)
	model:SetAttribute("CrewAnim", true)   -- клиентский проигрыватель поз
	model:SetAttribute("Friendly", true)

	local hum = model:FindFirstChildWhichIsA("Humanoid", true)
	if hum then
		hum.WalkSpeed = 9
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	return hum
end

-- ⚠️ СКВОЗЬ ВСЁ — ДА, СКВОЗЬ ПОЛ — НЕТ.
-- Рабочие втыкались в трубы, будку, леера, друг в друга и в игрока. Перечислять
-- препятствия поимённо (как было, через NoCollisionConstraint на детей станции)
-- бесполезно: любой камень, пальма или новая деталь модели снова их застопорят.
-- Поэтому переворачиваем правило — рабочий не сталкивается НИ С ЧЕМ, кроме того,
-- по чему ходит. Пол помечаем отдельной группой: настил вышки и плитки острова.
local SOLID = { oilrig_foundation = true }

local GROUP_WORKER = "OilWorker"
local GROUP_FLOOR  = "OilFloor"
-- ⚠️ ФЕРМА СКВОЗНАЯ ТОЛЬКО ДЛЯ РАБОЧИХ.
-- oilrig_derrick — решётка из тонких раскосов. Игрок об неё опирается как об
-- обычную деталь, это правильно. А рабочие ходят по своим точкам напрямик и
-- застревали между раскосами, останавливая смену, — им она мешать не должна.
-- Одной группы CanCollide тут мало: свойство одно на всех, а нужно разное
-- поведение для разных участников. Отсюда отдельная группа фермы.
local GROUP_OPEN   = "OilOpen"
local OPEN_PARTS   = { oilrig_derrick = true }

local groupsReady = nil
local function ensureGroups()
	if groupsReady ~= nil then return groupsReady end
	-- регистрация падает, если группа уже есть — это нормальный исход
	pcall(function() PhysicsService:RegisterCollisionGroup(GROUP_WORKER) end)
	pcall(function() PhysicsService:RegisterCollisionGroup(GROUP_FLOOR) end)

	local ok = pcall(function()
		PhysicsService:CollisionGroupSetCollidable(GROUP_WORKER, "Default", false)
	end)
	-- «Raft» и «FloatingResource» заводит BoatMovement; если он ещё не отработал,
	-- этих групп нет — не беда, к острову они и не относятся
	for _, other in ipairs({ "Raft", "FloatingResource" }) do
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(GROUP_WORKER, other, false)
		end)
	end
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(GROUP_WORKER, GROUP_WORKER, false)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(GROUP_WORKER, GROUP_FLOOR, true)
	end)

	-- ⚠️ ФЕРМА ДЕРЖИТ ИГРОКА, НО НЕ РАБОЧИХ.
	-- Игроку раскосы — нормальная преграда, он по вышке лазает и должен об неё
	-- опираться. А рабочие ходят по своим точкам напролом, и застревание в
	-- решётке останавливало смену. Поэтому отключаем ей столкновение ТОЛЬКО с
	-- группой рабочих; со всем остальным, включая Default (это и есть игрок),
	-- она сталкивается как обычная деталь.
	pcall(function() PhysicsService:RegisterCollisionGroup(GROUP_OPEN) end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(GROUP_OPEN, GROUP_WORKER, false)
	end)
	groupsReady = ok
	if not ok then
		warn(LOG .. " группы столкновений недоступны — рабочие останутся обычными")
	end
	return groupsReady
end

local floorRay = RaycastParams.new()
floorRay.IgnoreWater = false
floorRay.FilterType = Enum.RaycastFilterType.Exclude

-- ⚠️ ПОЛ ПОМЕЧАЕМ ДО ТОГО, КАК СНИМЕМ СТОЛКНОВЕНИЯ.
-- Если рабочий уже «призрак», а под ним ничего не помечено, он проваливается
-- сквозь остров в океан. Поэтому сначала метим и СЧИТАЕМ, и только при удаче
-- переводим рабочих в свою группу.
-- ⚠️ ПОМЕЧЕННЫЙ ПОЛ ДОЛЖЕН ПОКРЫВАТЬ ВЕСЬ ПУТЬ, А НЕ ТОЛЬКО ВЫШКУ.
-- Рабочий не сталкивается ни с чем, кроме группы OilFloor. Одна непомеченная
-- плитка на дороге к дому — и он проваливается сквозь остров в океан. Поэтому
-- метка выставляется не только под станцией, но и вдоль маршрута.
local function tagTilesNear(pos, radius, skip)
	local tagged = 0
	local near = OverlapParams.new()
	near.FilterType = Enum.RaycastFilterType.Exclude
	near.FilterDescendantsInstances = skip or {}
	near.MaxParts = 500
	for _, d in ipairs(Workspace:GetPartBoundsInRadius(pos, radius, near)) do
		if d.Name:sub(1, #Defs.TILE_PREFIX) == Defs.TILE_PREFIX then
			if d.CollisionGroup ~= GROUP_FLOOR then
				pcall(function() d.CollisionGroup = GROUP_FLOOR end)
			end
			tagged += 1
		end
	end
	return tagged
end

-- Полоса вдоль отрезка: идём шагами и метим вокруг каждого.
local function tagRoute(fromPos, toPos, skip)
	local span = toPos - fromPos
	local steps = math.clamp(math.ceil(span.Magnitude / 20), 1, 40)
	local tagged = 0
	for i = 0, steps do
		tagged += tagTilesNear(fromPos + span * (i / steps), 30, skip)
	end
	return tagged
end

local function tagFloor(station, points, crew)
	local tagged = 0
	local function tag(part)
		if part and part:IsA("BasePart") and part.CollisionGroup ~= GROUP_FLOOR then
			if pcall(function() part.CollisionGroup = GROUP_FLOOR end) then
				tagged += 1
			end
		elseif part and part.CollisionGroup == GROUP_FLOOR then
			tagged += 1
		end
	end

	-- настил самой вышки
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") and SOLID[d.Name] then tag(d) end
	end

	-- и ажурная ферма — в свою сквозную группу, чтобы в ней не застревали
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") and OPEN_PARTS[d.Name] then
			pcall(function() d.CollisionGroup = GROUP_OPEN end)
		end
	end

	-- и грунт под каждой точкой маршрута: по нему рабочие тоже ходят
	floorRay.FilterDescendantsInstances = { crew }
	for _, cf in ipairs(points) do
		if cf then
			local hit = Workspace:Raycast(cf.Position + Vector3.new(0, 8, 0),
				Vector3.new(0, -50, 0), floorRay)
			if hit and hit.Instance and hit.Instance:IsA("BasePart") then
				tag(hit.Instance)
			end
		end
	end

	-- ⚠️ ЗАПАС ПО ПЛИТКАМ ВОКРУГ.
	-- Луч ловит только то, что ровно под точкой, а рабочий по дороге срезает угол
	-- и может ступить на соседнюю плитку. Одна непомеченная плитка на пути = дыра
	-- в острове, поэтому метим все, до которых он в принципе дойдёт.
	local _, size = station:GetBoundingBox()
	local reach = math.max(size.X, size.Z) * 0.5 + 40
	tagged += tagTilesNear(station:GetPivot().Position, reach, { crew })
	return tagged
end

local function ghostWorker(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			pcall(function() d.CollisionGroup = GROUP_WORKER end)
		end
	end
end

-- ⚠️ ТЕ ЖЕ ГРУППЫ — ДЛЯ ФЕРМЫ. Фермер ходит так же, как рабочие вышки: сквозь
-- всё, кроме помеченного пола. Вторая копия групп и пометки разъехалась бы.
_G.OilRigWorkerTools = {
	ensureGroups = ensureGroups,
	ghostWorker  = ghostWorker,
	tagTilesNear = tagTilesNear,
	tagRoute     = tagRoute,
	FLOOR_GROUP  = GROUP_FLOOR,
	tagPart = function(part)
		if part and part:IsA("BasePart") and part.CollisionGroup ~= GROUP_FLOOR then
			return pcall(function() part.CollisionGroup = GROUP_FLOOR end)
		end
		return part ~= nil
	end,
}

-- Запасной путь, если группы недоступны: старая поимённая развязка с обвязкой
-- станции. Хуже, но лучше, чем застрявший в трубе рабочий.
local function passThrough(model, station)
	local host = model:FindFirstChild("HumanoidRootPart", true)
	if not host then return end
	for _, part in ipairs(station:GetChildren()) do
		if part:IsA("BasePart") and not SOLID[part.Name] then
			local ncc = Instance.new("NoCollisionConstraint")
			ncc.Part0 = host
			ncc.Part1 = part
			ncc.Parent = host
		end
	end
end

-- Реквизит в руку: бур и канистра вешаются на Right Arm своим Motor6D
-- (README, раздел 5). Инструмент лежит внутри самой модели рабочего.
local function holdInHand(model, part, c0)
	local arm = model:FindFirstChild("Right Arm", true)
	if not (arm and part) then return nil end
	for _, j in ipairs(arm:GetChildren()) do
		if j:IsA("Motor6D") and j.Name == "PropGrip" then j:Destroy() end
	end
	part.Anchored = false
	part.CanCollide = false
	part.Massless = true
	part.CFrame = arm.CFrame * c0

	local motor = Instance.new("Motor6D")
	motor.Name = "PropGrip"
	motor.Part0 = arm
	motor.Part1 = part
	motor.C0 = c0
	motor.Parent = arm
	return motor
end

local function toolPart(model)
	local tool = model:FindFirstChild(Defs.TOOL, true)
	if not tool then return nil end
	if tool:IsA("BasePart") then return tool end
	local h = tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart", true)
	return h
end

-- ═══════════ жизнь станции ═══════════

local function runStation(station, owner)
	local drillCF = markerCF(station, Defs.WP.drill)
	local canCF   = markerCF(station, Defs.WP.can)
	local tankCF  = markerCF(station, Defs.WP.tank)
	local restCF  = markerCF(station, Defs.WP.rest)
	local pourCF  = markerCF(station, Defs.FX.pour)
	local sprayCF = markerCF(station, Defs.FX.spray)
	if not (drillCF and canCF and tankCF and restCF) then
		warn(LOG .. " в модели нет маркеров wp_* — рабочим негде встать")
		return
	end
	-- ⚠️ ОТЧЁТ О НАЙДЕННОМ. «Работа не началась» может значить и «нет рабочих»,
	-- и «нет точек» — по этой строке видно, что именно.
	print(("%s точки: бур %s, канистра %s, бак %s, отдых %s")
		:format(LOG,
			station:FindFirstChild(Defs.WP.drill, true) and "маркер" or "из README",
			station:FindFirstChild(Defs.WP.can, true) and "маркер" or "из README",
			station:FindFirstChild(Defs.WP.tank, true) and "маркер" or "из README",
			station:FindFirstChild(Defs.WP.rest, true) and "маркер" or "из README"))

	local fx = oilFx(station)
	infoBoard(station)

	-- ⚠️ ШАБЛОНОВ МОЖЕТ БЫТЬ ДВА, А НЕ ОДИН.
	-- Рабочие в наборе лежат готовой парой OilMan_1 / OilMan_2, и общего
	-- «OilMan» в мире может не быть вовсе — первый заход искал только его и
	-- молча оставался без рабочих. Берём каждого своего, а общий — как запасной.
	local base = findTemplate(Defs.WORKER)
	local tplDrill  = findTemplate(Defs.WORKER .. "_1") or base
	local tplHauler = findTemplate(Defs.WORKER .. "_2") or base
	if not (tplDrill and tplHauler) then
		warn(LOG .. " не нашёл моделей рабочих (" .. Defs.WORKER .. ", "
			.. Defs.WORKER .. "_1, " .. Defs.WORKER .. "_2) в ReplicatedStorage/Workspace")
		return
	end

	local crew = Instance.new("Folder")
	crew.Name = "Rebels"   -- та же папка, что анимирует клиентский проигрыватель
	crew.Parent = station

	-- БУРИЛЬЩИК: стоит на месте, качает, выставляет канистры
	local driller = tplDrill:Clone()
	driller.Name = "OilMan_1"
	driller.Parent = crew
	local dHum = prepWorker(driller, drillCF)
	holdInHand(driller, toolPart(driller), Defs.GRIP_DRILL)

	-- НОСИЛЬЩИК: ждёт, забирает, несёт, льёт
	local hauler = tplHauler:Clone()
	hauler.Name = "OilMan_2"
	hauler.Parent = crew
	local hHum = prepWorker(hauler, restCF)

	-- ⚠️ ПОРЯДОК ВАЖЕН: СНАЧАЛА ПОЛ, ПОТОМ ПРИЗРАКИ.
	-- Наоборот — и рабочие успевают провалиться сквозь остров ещё до того, как
	-- под ними что-то помечено.
	local home1CF = markerCF(station, Defs.WP.home1)
	local home2CF = markerCF(station, Defs.WP.home2)
	local floors = 0
	if ensureGroups() then
		floors = tagFloor(station, { drillCF, canCF, tankCF, restCF, home1CF, home2CF }, crew)
	end
	if floors > 0 then
		ghostWorker(driller)
		ghostWorker(hauler)
		print(("%s рабочие проходят сквозь препятствия (опор помечено: %d)")
			:format(LOG, floors))
	else
		-- пола не нашли — оставляем их обычными, иначе улетят под остров
		if ensureGroups() then
			warn(LOG .. " под маршрутом не нашлось опор — рабочие остались твёрдыми")
		end
		passThrough(driller, station)
		passThrough(hauler, station)
	end

	-- ⚠️ ОТЧЁТ ПО ОБОИМ. «У второго анимации не переделаны» может значить и
	-- «клипы не дошли», и «его вообще не анимируют»: по этой строке видно, есть
	-- ли у каждого Humanoid и суставы, за которые его берёт проигрыватель поз.
	for _, m in ipairs({ driller, hauler }) do
		local joints = 0
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("Motor6D") then joints += 1 end
		end
		print(("%s %s: Humanoid=%s, Motor6D=%d, папка=%s"):format(
			LOG, m.Name,
			tostring(m:FindFirstChildWhichIsA("Humanoid", true) ~= nil),
			joints, m.Parent and m.Parent.Name or "нет"))
	end
	local hTool = toolPart(hauler)
	if hTool then hTool:Destroy() end   -- бур ему не нужен, он таскает канистры

	-- ⚠️ КАНИСТРА У НОСИЛЬЩИКА СВОЯ И НАВСЕГДА.
	-- Первый заход плодил клоны канистры на wp_can и уничтожал после розлива —
	-- лишняя возня: канистру вложили прямо в модель OilMan_2, она уже в руке.
	-- Считаем не предметы, а ГОТОВЫЕ ПОРЦИИ: бурильщик их накачивает,
	-- носильщик уносит. Ровно та же очередь, только без мусора в мире.
	local ready = 0

	local function alive()
		return station.Parent and dHum and hHum
			and dHum.Health > 0 and hHum.Health > 0
	end

	-- канистру из модели носильщика вешаем в правую руку один раз
	do
		local can = nil
		for _, name in ipairs(CAN_NAMES) do
			local found = hauler:FindFirstChild(name, true)
			if found then can = found break end
		end
		local part = can and (can:IsA("BasePart") and can
			or can:FindFirstChildWhichIsA("BasePart", true))
		if part then
			for _, d in ipairs((can:IsA("Model") and can or part):GetDescendants()) do
				if d:IsA("BasePart") then d.Anchored = false; d.Massless = true; d.CanCollide = false end
			end
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			holdInHand(hauler, part, Defs.GRIP_CAN)
		end
	end

	-- ═══ СМЕНА: работают днём, на ночь уходят домой ═══

	local away, busy = false, false

	-- ⚠️ БЕЗ НЕФТЯНИКА ВЫШКА НЕ РАБОТАЕТ ВООБЩЕ.
	-- Рабочие на настиле — это видимое следствие того, что кому-то из жильцов
	-- дома назначена профессия «Нефтяник». Нет дома, нет жителей или никто не
	-- нефтяник — на вышке никого и нет. Пустая вышка с крутящимся буром выглядела
	-- бы так, будто жители ей и не нужны.
	local function crewHired()
		if typeof(_G.HouseOilCrew) ~= "function" then return true end   -- дома ещё нет в игре
		local count = _G.HouseOilCrew()
		return count > 0
	end

	-- ⚠️ ОТДАЧА БРИГАДЫ УМНОЖАЕТ ТЕМП, А НЕ ТОЛЬКО ЦИФРУ НА ВЫВЕСКЕ.
	-- Вывеска считает добычу как базовую × эту силу. Если сюда её не подставить,
	-- надпись обещала бы одно, а в бочку капало другое.
	local function crewPower()
		if typeof(_G.HouseOilCrew) ~= "function" then return 1 end
		local count, power = _G.HouseOilCrew()
		if count <= 0 then return 0 end
		return power
	end

	-- ⚠️ КОНЕЦ СМЕНЫ — НЕ ЗАКАТ.
	-- Работают с 6:30 до 23:00, то есть первые пять часов темноты ещё на местах,
	-- а после полуночи и до полседьмого — спят. Окно проходит через полночь,
	-- поэтому «вне смены» это НЕ просто «раньше начала и позже конца».
	local function offShift()
		if not crewHired() then return true end   -- некому работать — смены нет
		local t = Lighting.ClockTime
		return t >= Defs.WORK_END or t < Defs.WORK_START
	end

	-- ⚠️ УВОЛЕННЫЙ УХОДИТ В ТУ ЖЕ СЕКУНДУ, А НЕ ЖДЁТ КОНЦА СМЕНЫ.
	-- Раньше вышка знала только «нефтяников больше нуля» и при увольнении одного
	-- из двоих продолжала работать обоими: тела не были связаны с жителями.
	-- Теперь каждое тело прописано за конкретным жителем (HouseBindWorker), и
	-- вопрос задаётся про НЕГО.
	-- [модель] = "sit" | "bed": чем безработный занят прямо сейчас
	local fired = {}

	-- ⚠️ ЧАСЫ БЕЗ ОГЛЯДКИ НА ШТАТ.
	-- offShift() отвечает «нет» ещё и когда нефтяников не осталось вовсе, и по
	-- нему нельзя понять, ночь на дворе или просто некому работать. Уволенным
	-- нужны именно часы: днём стул, ночью кровать.
	local function nightNow()
		local t = Lighting.ClockTime
		return t >= Defs.WORK_END or t < Defs.WORK_START
	end

	--[[ ⚠️ ОБЪЯВЛЕНЫ ЗАРАНЕЕ. Функции ниже (releaseIdle и соседние) зовут beds,
	     walkTo, setPropsHidden, tuckIn, а те объявлялись дальше по тексту: в Lua
	     такое имя внутри замыкания — глобал, то есть nil, и при первом же
	     отдыхе рабочего вышка падала. Объявляем имена здесь, определения ниже
	     только присваивают. ]]
	local beds, walkTo, setPropsHidden, tuckIn
	local function releaseIdle(model, hum)
		local hrp = model:FindFirstChild("HumanoidRootPart", true)
		if hrp then hrp.Anchored = false end
		hum.PlatformStand = false
		if beds[model] then
			beds[model].release()
			beds[model] = nil
		end
		if _G.HouseReleaseSeat then pcall(_G.HouseReleaseSeat, model) end
	end

	local function sendHomeIdle(model, hum)
		local want = nightNow() and "bed" or "sit"
		if fired[model] == want then return end
		-- сменилось время суток: встаём и перебираемся на другое место
		if fired[model] then releaseIdle(model, hum) end
		fired[model] = want

		local spot = _G.HouseIdleSpot and _G.HouseIdleSpot(model, want)
		setPropsHidden(model, true)         -- уволен — инструмент из рук долой
		setClip(model, HouseDefs.CLIPS.walk)
		if not spot then
			-- дома нет: просто уводим с поста, чтобы не изображал работу
			if restCF then walkTo(model, hum, restCF, 20) end
			setClip(model, Defs.CLIPS.rest)
			return
		end
		if spot.door then walkTo(model, hum, spot.door, 30) end
		if spot.kind == "bed" then
			tuckIn(model, hum, spot)
			return
		end
		walkTo(model, hum, spot.cf, 15)
		local hrp = model:FindFirstChild("HumanoidRootPart", true)
		if hrp then
			hum.PlatformStand = true
			hrp.Anchored = true
			hrp.CFrame = spot.cf
		end
		setClip(model, HouseDefs.CLIPS.sit)
	end

	local function backToDuty(model, hum, postCF)
		if not fired[model] then return end
		fired[model] = nil
		releaseIdle(model, hum)
		setPropsHidden(model, false)
		setClip(model, HouseDefs.CLIPS.walk)
		task.spawn(function() walkTo(model, hum, postCF, 30) end)
	end

	-- ⚠️ ПРИДЯ НА ПОСТ, БУРИЛЬЩИК РАЗВОРАЧИВАЕТСЯ К УСТЬЮ.
	-- Куда он смотрит после прихода, решает направление последнего шага, а не
	-- пост: утром он приходил от дверей дома и вставал бурить спиной к скважине.
	-- Разворачиваем его на fx_spray — туда же, куда бьёт фонтан и куда считается
	-- посадка бура.
	local function faceSpray(model)
		if not sprayCF then return end
		local hrp = model:FindFirstChild("HumanoidRootPart", true)
		if not hrp then return end
		local to = sprayCF.Position - hrp.Position
		to = Vector3.new(to.X, 0, to.Z)
		if to.Magnitude < 0.5 then return end
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + to.Unit)
	end

	-- ⚠️ ЦЕЛЬ ПОДТВЕРЖДАЕМ, ПОКА ИДЁТ.
	-- Humanoid:MoveTo забывает точку через 8 секунд и рабочий встаёт на полпути —
	-- на длинном пути до дома это видно сразу. Повторяем команду и следим за
	-- дистанцией по горизонтали: по высоте настил и точка не совпадают.
	walkTo = function(model, hum, cf, limit)
		local hrp = model:FindFirstChild("HumanoidRootPart", true)
		if not hrp then return end
		local t0 = os.clock()
		while os.clock() - t0 < (limit or 14) do
			local d = hrp.Position - cf.Position
			if Vector3.new(d.X, 0, d.Z).Magnitude < 3.5 then return end
			hum:MoveTo(cf.Position)
			task.wait(0.25)
		end
	end

	-- Ночёвка без дома: маршрут home_1 → home_2, НА ПЕРВОЙ ТОЧКЕ НЕ
	-- ОСТАНАВЛИВАЮТСЯ — она проходная, просто задаёт дорогу в обход постройки.
	local function walkToMarkers(model, hum, sideways)
		setClip(model, HouseDefs.CLIPS.walk)
		if home1CF then walkTo(model, hum, home1CF) end
		if home2CF then
			-- второго сдвигаем вбок, иначе оба встают в одну точку и толкаются
			walkTo(model, hum, home2CF * CFrame.new(sideways or 0, 0, 0))
		end
		setClip(model, Defs.CLIPS.rest)
	end

	-- ⚠️ СПЯЩЕГО ДЕРЖИМ АНКОРОМ, А НЕ ФИЗИКОЙ.
	-- Humanoid выпрямляет лежащего обратно в стойку, а несущий его настил ещё и
	-- толкает. PlatformStand снимает выпрямление, Anchored — всё остальное; ровно
	-- этот порядок описан в House/README.md.
	beds = {}   -- [модель] = выданная кровать, чтобы утром её вернуть

	-- ⚠️ РЕКВИЗИТ НА ВРЕМЯ СНА ПРЯЧЕМ, А НЕ СНИМАЕМ.
	-- Бур и канистра приварены Motor6D «PropGrip» к правой руке; отцепить их —
	-- значит уронить на пол и потом искать. Достаточно сделать невидимыми: спящий
	-- с буром наперевес выглядел так, будто уснул за работой.
	-- Исходную прозрачность помним в атрибуте: у бура есть полупрозрачные детали,
	-- и вернуть им ноль было бы неверно.
	-- ⚠️ ПРЯЧЕМ ВЕСЬ ПРЕДМЕТ, А НЕ ДЕТАЛЬ ПОД ЗАХВАТОМ.
	-- Захват приварен к ОДНОЙ детали: у бура это невидимая рукоять внутри Tool, у
	-- канистры — корпус внутри модели. Пряча только её, мы прятали пустоту, а
	-- шнек и канистра оставались висеть в руке. Поднимаемся к владельцу предмета
	-- (Tool или Model) и гасим всё внутри.
	-- ⚠️ НО НЕ ВЫШЕ САМОГО РАБОЧЕГО. Если деталь лежит прямо в модели NPC, его
	-- «владелец» — это он сам, и мы погасили бы человека целиком. Такую цепочку
	-- обрываем по наличию Humanoid.
	local function propScope(part)
		local p = part.Parent
		if p and (p:IsA("Tool") or p:IsA("Model"))
			and not p:FindFirstChildWhichIsA("Humanoid", true) then
			return p
		end
		return part
	end

	setPropsHidden = function(model, hidden)
		local arm = model:FindFirstChild("Right Arm", true)
		if not arm then return end
		for _, j in ipairs(arm:GetChildren()) do
			if j:IsA("Motor6D") and j.Name == "PropGrip" and j.Part1 then
				local scope = propScope(j.Part1)
				local list = { scope }
				for _, d in ipairs(scope:GetDescendants()) do table.insert(list, d) end
				for _, d in ipairs(list) do
					if d:IsA("BasePart") then
						if d:GetAttribute("Tr0") == nil then
							d:SetAttribute("Tr0", d.Transparency)
						end
						d.Transparency = hidden and 1 or (d:GetAttribute("Tr0") or 0)
					elseif d:IsA("Decal") or d:IsA("Texture") then
						d.Transparency = hidden and 1 or 0
					end
				end
			end
		end
	end

	-- ⚠️ МАРШРУТ ДОМОЙ — ЧЕРЕЗ ДВЕРЬ, И ДО КРОВАТИ ТОЖЕ ИДЁМ НОГАМИ.
	-- Раньше от двери человека телепортировало прямо в постель: он доходил до
	-- крыльца и мгновенно оказывался лежащим. Теперь вышка → дверь → кровать, и
	-- только у самой кровати включается укладывание.
	tuckIn = function(model, hum, claim)
		setClip(model, HouseDefs.CLIPS.walk)
		if claim.door then walkTo(model, hum, claim.door, 25) end
		if claim.bed then walkTo(model, hum, claim.bed, 12) end

		local hrp = model:FindFirstChild("HumanoidRootPart", true)
		if not hrp then return end
		hum.PlatformStand = true
		hrp.Anchored = true
		hrp.CFrame = claim.bed
		setPropsHidden(model, true)     -- спят без инструмента в руках
		setClip(model, HouseDefs.CLIPS.enter, true)
		task.wait(1.33)                       -- длительность SleepEnter из clips.json
		setClip(model, HouseDefs.CLIPS.sleep)
		beds[model] = claim
	end

	local function getUp(model, hum)
		local claim = beds[model]
		local hrp = model:FindFirstChild("HumanoidRootPart", true)
		if claim and hrp then
			setClip(model, HouseDefs.CLIPS.exit, true)
			task.wait(1.53)                   -- длительность SleepExit
			hrp.Anchored = false
			hum.PlatformStand = false
			setPropsHidden(model, false)   -- встал — снова с инструментом
			claim.release()
			beds[model] = nil
		end
	end

	local function goHome()
		away = true
		if fx then fx.jet.Enabled = false; fx.drops.Enabled = false end

		-- ⚠️ КРОВАТЬ ПРОСИМ ДО ВЫХОДА, А НЕ ПО ПРИХОДЕ.
		-- Иначе оба дойдут до двери и только там выяснят, что дом один и мест нет.
		local dClaim = _G.HouseClaimBed and _G.HouseClaimBed(station:GetPivot().Position, driller)
		local hClaim = _G.HouseClaimBed and _G.HouseClaimBed(station:GetPivot().Position, hauler)

		-- дорога до дома должна быть под ногами твёрдой: рабочие проходят сквозь
		-- всё, кроме помеченных плиток
		local claim = dClaim or hClaim
		if claim and claim.house then
			tagRoute(station:GetPivot().Position, claim.house:GetPivot().Position, { crew })
		end

		-- запоминаем дверь: утром бригада выходит именно из неё
		if claim and claim.door then beds.lastDoor = claim.door end

		if dClaim or hClaim then
			-- второй выходит чуть позже: так они не идут ноздря в ноздрю
			task.spawn(function()
				if dClaim then tuckIn(driller, dHum, dClaim)
				else walkToMarkers(driller, dHum, -1.6) end
			end)
			task.wait(1.2)
			if hClaim then tuckIn(hauler, hHum, hClaim)
			else walkToMarkers(hauler, hHum, 1.6) end
			-- в доме они и остаются: спящих видно, прятать нечего
			return
		end

		if not (home1CF or home2CF) then
			warn(LOG .. " нет ни дома, ни маркеров home_1/home_2 — рабочие останутся на местах")
		else
			task.spawn(function() walkToMarkers(driller, dHum, -1.6) end)
			task.wait(1.2)
			walkToMarkers(hauler, hHum, 1.6)
			task.wait(2)   -- постояли у дома
		end
		crew.Parent = nil   -- ночевать под открытым небом незачем: убираем до утра
	end

	-- ⚠️ УТРОМ ВЫХОДЯТ ИЗ ДВЕРЕЙ И ИДУТ НА МЕСТА, А НЕ ВОЗНИКАЮТ НА ПОСТАХ.
	-- Раньше их просто ставило на wp_drill и wp_rest: смена начиналась тем, что
	-- двое появлялись из воздуха посреди вышки. Если дом есть — стартуют от его
	-- двери и доходят пешком; дома нет — как раньше, иначе стартовать неоткуда.
	local function backToWork()
		-- сперва поднять с кроватей, потом уже возвращать на места
		task.spawn(function() getUp(driller, dHum) end)
		getUp(hauler, hHum)

		crew.Parent = station
		local doorCF = beds.lastDoor
		if doorCF then
			pcall(function() driller:PivotTo(doorCF * CFrame.new(-1.6, 0, 0)) end)
			pcall(function() hauler:PivotTo(doorCF * CFrame.new(1.6, 0, 0)) end)
			setClip(driller, HouseDefs.CLIPS.walk)
			setClip(hauler, HouseDefs.CLIPS.walk)
			away = false          -- снимаем раньше: иначе рабочие циклы стоят, пока идут
			task.spawn(function()
				walkTo(driller, dHum, drillCF, 30)
				faceSpray(driller)      -- пришёл — повернулся к скважине
			end)
			task.spawn(function() walkTo(hauler, hHum, restCF, 30) end)
			return
		end

		-- ставим ровно на рабочие места, а не туда, где застало утро
		pcall(function() driller:PivotTo(drillCF) end)
		pcall(function() hauler:PivotTo(restCF) end)
		faceSpray(driller)
		setClip(driller, Defs.CLIPS.drill)
		setClip(hauler, Defs.CLIPS.rest)
		away = false
	end

	-- Смотритель смены. Ждёт, пока носильщик закончит текущую ходку: обрывать её
	-- на полпути незачем, она всего десяток секунд.
	-- ⚠️ ПРОПИСКУ ПОВТОРЯЕМ, А НЕ ДЕЛАЕМ ОДИН РАЗ.
	-- Порядок в игре обычный: сперва вышка, потом дом, потом жители. На запуске
	-- станции прописывать НЕ К КОМУ — жителей ещё нет, — а тело без прописки я
	-- считал работающим. Из-за этого увольнение вообще ни на что не влияло.
	-- Поэтому пробуем каждую секунду, пока не привяжется.
	local function ensureBound(model)
		if model:GetAttribute("ResidentId") then return end
		if _G.HouseBindWorker then pcall(_G.HouseBindWorker, model) end
	end

	-- Личный надзор за увольнением: раз в секунду спрашиваем про каждого.
	task.spawn(function()
		while station.Parent do
			task.wait(1)
			ensureBound(driller)
			ensureBound(hauler)
			-- ⚠️ ПРО УВОЛЕННЫХ СПРАШИВАЕМ И В НЕРАБОЧЕЕ ВРЕМЯ.
			-- Раньше проверка стояла под «not away», а away поднимается в том
			-- числе когда нефтяников не осталось СОВСЕМ. Уволив обоих, игрок
			-- получал вечную ночь для них: смена не начиналась, проверка не шла,
			-- и оба спали в кроватях круглые сутки.
			if alive() and _G.HouseWorkerEmployed then
				for _, e in ipairs({ { driller, dHum, drillCF }, { hauler, hHum, restCF } }) do
					local model, hum, post = e[1], e[2], e[3]
					if _G.HouseWorkerEmployed(model) then
						backToDuty(model, hum, post)
					else
						task.spawn(function() sendHomeIdle(model, hum) end)
					end
				end
			end
		end
	end)

	task.spawn(function()
		if offShift() then crew.Parent = nil; away = true end
		while station.Parent do
			if not away and offShift() then
				-- ⚠️ ЖДЁМ КОНЦА ХОДКИ СЕКУНДЫ, А НЕ ДЕСЯТКИ.
				-- busy снимает поток носильщика, и если он умрёт посреди ходки,
				-- флаг останется поднятым навсегда — смена не кончится никогда.
				-- Но и щедрое ожидание вредно: НОЧНОЙ ЧАС ИДЁТ 10 РЕАЛЬНЫХ СЕКУНД
				-- (120 с на 12 часов), поэтому прежние 20 секунд запаса означали
				-- ДВА ИГРОВЫХ ЧАСА — бригада уходила спать в час ночи вместо 23:00.
				-- Четырёх хватает, чтобы дать долить начатое: сам розлив 2.3 с.
				local waited = 0
				while busy and station.Parent and waited < 4 do
					task.wait(0.25)
					waited += 0.25
				end
				if busy then
					warn(LOG .. " носильщик завис в ходке — увожу бригаду домой принудительно")
					busy = false
				end
				if station.Parent and alive() then
					print(("%s конец смены (%.1f) — уходят домой"):format(LOG, Lighting.ClockTime))
					goHome()
				end
			elseif away and not offShift() then
				if alive() then
					print(("%s начало смены (%.1f) — на рабочие места"):format(LOG, Lighting.ClockTime))
					backToWork()
				end
			end
			task.wait(1)
		end
		-- станции больше нет: спрятанная на ночь бригада иначе останется висеть
		-- в никуда припаркованной моделью
		if crew.Parent == nil then crew:Destroy() end
	end)

	-- Ждём отрезок работы, но просыпаемся сразу, если объявили конец смены.
	local function workWait(seconds)
		local left = seconds
		while left > 0 and alive() and not away do
			local step = math.min(0.5, left)
			task.wait(step)
			left -= step
		end
		return alive() and not away
	end

	-- БУРИТ: качает нефть, пока есть куда
	task.spawn(function()
		while alive() do
			if fired[driller] then
				task.wait(1)          -- бурильщик уволен: скважина стоит
			elseif away then
				if fx then fx.jet.Enabled = false; fx.drops.Enabled = false end
				task.wait(1)
			elseif ready >= Defs.MAX_QUEUE then
				setClip(driller, Defs.CLIPS.wait)
				if fx then fx.jet.Enabled = false; fx.drops.Enabled = false end
				task.wait(1)
			else
				setClip(driller, Defs.CLIPS.drill)
				if fx then fx.jet.Enabled = true; fx.drops.Enabled = true end
				if workWait(Defs.DRILL_TIME / math.max(0.25, crewPower())) then ready += 1 end
			end
		end
	end)

	-- НОСИТ И ЛЬЁТ: ждёт порцию, идёт к устью, несёт к баку, опрокидывает
	task.spawn(function()
		while alive() do
			if away or fired[hauler] then
				task.wait(1)          -- носильщика уволили: некому носить
			elseif ready <= 0 then
				-- ⚠️ ЖДЁТ ДОЛГО И С ОТДЕЛЬНЫМ КЛИПОМ. Ходка теперь редкая, и на
				-- таком сроке обычный простой читается как зависший манекен.
				setClip(hauler, Defs.CLIPS.rest)
				hHum:MoveTo(restCF.Position)
				task.wait(2)
			else
				ready -= 1
				busy = true   -- смотритель смены дождётся конца ходки

				-- к устью за нефтью
				setClip(hauler, Defs.CLIPS.carry)
				hHum:MoveTo(canCF.Position)
				task.wait(1.6)
				setClip(hauler, Defs.CLIPS.pick, true)
				task.wait(1)

				-- к баку
				setClip(hauler, Defs.CLIPS.carry)
				hHum:MoveTo(tankCF.Position)
				task.wait(2.5)

				-- разворачиваемся к воронке: льют лицом к бочке, а не спиной
				local hHrp = hauler:FindFirstChild("HumanoidRootPart", true)
				if hHrp and pourCF then
					local to = Vector3.new(pourCF.Position.X - hHrp.Position.X, 0,
						pourCF.Position.Z - hHrp.Position.Z)
					if to.Magnitude > 0.5 then
						hHrp.CFrame = CFrame.lookAt(hHrp.Position, hHrp.Position + to.Unit)
					end
				end

				-- сколько нефти даст эта ходка — решаем ДО розлива: цифра над
				-- воронкой должна набегать именно к этому числу
				local ml = math.random(Defs.ML_MIN, Defs.ML_MAX)
				if pourCF then mlPopup(pourCF, ml, 1.3) end

				setClip(hauler, Defs.CLIPS.pour, true)
				task.wait(Defs.POUR_AT)
				-- ⚠️ ДОХОД РОВНО В МОМЕНТ ОПРОКИДЫВАНИЯ, как в README: раньше —
				-- и игрок видит монеты до того, как нефть полилась.
				--[[ ⚠️ ДОХОД КОПИТСЯ И ВЫДАЁТСЯ РАЗ В ИГРОВОЙ ЧАС (PassiveIncome).
				     Владелец: «каждый час отображай прибыль и только каждый час
				     начисляй». Пока модуля нет — как раньше, сразу. ]]
				if owner and owner.Parent and typeof(_G.PassiveIncomeAdd) == "function" then
					_G.PassiveIncomeAdd(owner, Defs.COINS_PER_CAN, ml)
				else
					if owner and owner.Parent and _G.AddPirate then
						pcall(_G.AddPirate, owner, Defs.COINS_PER_CAN)
					end
					addOilToTank(ml)
				end
				task.wait(1.4)   -- дольём и пойдём обратно

				-- назад на свою точку и отдых до следующей порции
				setClip(hauler, Defs.CLIPS.carry)
				hHum:MoveTo(restCF.Position)
				task.wait(2)
				busy = false   -- ходка закончена, теперь можно и домой
				setClip(hauler, Defs.CLIPS.rest)
				workWait(Defs.REST_TIME)
			end
		end
	end)

	print(("%s станция запущена: бурильщик и носильщик на местах"):format(LOG))
end

-- ═══════════ постановка ═══════════

local built = {}   -- поставленные станции

-- Дом спрашивает: есть ли вообще вышка? От этого зависит, назначать ли новому
-- жителю профессию «Нефтяник» самому.
_G.OilRigCount = function()
	local n = 0
	for _, s in ipairs(built) do
		if s.Parent then n += 1 end
	end
	return n
end

-- ⚠️ ФЕРМУ РАЗВЯЗЫВАЕМ И У УЖЕ СТОЯЩИХ ВЫШЕК.
-- Группа назначается при постройке, а вышка могла быть поставлена до этой
-- правки — тогда рабочие продолжали бы застревать в раскосах до перестройки.
-- Проходим по тем, что уже в мире, и по новым моделям в Workspace.
local function openDerrick(station)
	if not ensureGroups() then return end
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") and OPEN_PARTS[d.Name] then
			pcall(function() d.CollisionGroup = GROUP_OPEN end)
		end
	end
end

for _, m in ipairs(Workspace:GetChildren()) do
	if m:IsA("Model") and m.Name == Defs.STATION then openDerrick(m) end
end
Workspace.ChildAdded:Connect(function(inst)
	if inst:IsA("Model") and inst.Name == Defs.STATION then
		task.defer(function()
			if inst.Parent then openDerrick(inst) end
		end)
	end
end)

-- Остров под точкой: по центру суши (атрибут LandCenter), не по пивоту
local function islandAt(pos)
	local best, bestD
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("MapIsland") then
			local c = m:GetAttribute("LandCenter")
			if typeof(c) ~= "Vector3" then c = m:GetPivot().Position end
			local r = tonumber(m:GetAttribute("LandRadius")) or 300
			local d = (Vector3.new(c.X, 0, c.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
			if d <= r + 80 and (not bestD or d < bestD) then best, bestD = m, d end
		end
	end
	return best
end
-- Остров ещё под пиратами? Живой Humanoid в папке Enemies и остров не зачищен
local function islandHostile(island)
	if not island or island:GetAttribute("Cleared") then return false end
	local enemies = island:FindFirstChild("Enemies")
	if not enemies then return false end
	for _, npc in ipairs(enemies:GetChildren()) do
		local hum = npc:IsA("Model") and npc:FindFirstChildWhichIsA("Humanoid", true)
		if hum and hum.Health > 0 then return true end
	end
	return false
end
placeEvent.OnServerEvent:Connect(function(player, cf)
	if typeof(cf) ~= "CFrame" then return end
	local tpl = findTemplate(Defs.STATION)
	if not tpl then
		warn(LOG .. " шаблон «" .. Defs.STATION .. "» не найден")
		return
	end

	-- рядом с игроком: чужие клики с другого конца карты не принимаем
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - cf.Position).Magnitude > 80 then return end

	local _, size = tpl:GetBoundingBox()
	local ok, why = spotOK(cf, size, { char })
	if not ok then
		placeEvent:FireClient(player, "denied", why)
		return
	end
	-- строить можно только на освобождённом острове (владелец: сначала пираты)
	do
		local isle = islandAt(cf.Position)
		-- ⚠️ АДМИН СТРОИТ И НА ЧУЖОМ ОСТРОВЕ. Признак админа — атрибут DevLogs
		-- (его ставит DevLogFlag: Studio, ADMIN_USER_IDS, владелец плейса).
		local admin = player:GetAttribute("DevLogs") == true
		if isle and islandHostile(isle) and not admin then
			placeEvent:FireClient(player, "denied", "Сначала освободи остров от пиратов")
			return
		end
	end

	--[[ ⚠️ ВЫШКА ТОЖЕ СТОИТ ДЕНЕГ — РАНЬШЕ БЫЛА БЕСПЛАТНОЙ.
	     Меню молотка показывало «12 Log», но сервер цену не проверял и не списывал.
	     Для экономики это была худшая дыра из всех: вышка не расходник, а источник
	     дохода — бесплатная означала бесконечную нефть за пару кликов.
	     Число обязано совпадать с пунктом меню в BuildingSystem.client.lua. ]]
	local inv = (typeof(_G.GetInventory) == "function" and _G.GetInventory(player)) or {}
	-- админ строит бесплатно (флаг DevLogs ставит сервер: DevLogFlag)
	local freeBuild = player:GetAttribute("DevLogs") == true
	if not freeBuild and (inv[RIG_COST_RES] or 0) < RIG_COST then
		placeEvent:FireClient(player, "denied",
			string.format("нужно %d брёвен, есть %d", RIG_COST, inv[RIG_COST_RES] or 0))
		return
	end
	if not freeBuild and typeof(_G.RemoveResourceFromInventory) == "function" then
		_G.RemoveResourceFromInventory(player, RIG_COST_RES, RIG_COST)
		-- показать списание игроку — отдельный вызов, само по себе оно молчит
		if typeof(_G.SendInventory) == "function" then _G.SendInventory(player) end
	end

	local station = tpl:Clone()
	station.Name = Defs.STATION
	pcall(function() station:PivotTo(cf) end)
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	hideMarkers(station)
	-- трава и камешки под настилом иначе лезли бы сквозь него
	clearDecor(cf, size)
	station.Parent = Workspace
	do local isle = islandAt(cf.Position); if isle then isle:SetAttribute("KeepAlive", true) end end

	table.insert(built, station)
	placeEvent:FireClient(player, "placed")
	runStation(station, player)
end)

-- СЕЙВ: вышки. Экспорт — положения, восстановление — новая вышка на том же месте.
_G.OilRigExport = function()
	local out = {}
	for _, st in ipairs(built) do
		if st.Parent then table.insert(out, { cf = st:GetPivot() }) end
	end
	return out
end
_G.OilRigRestore = function(cf, player)
	local tpl = findTemplate(Defs.STATION)
	if not tpl then return nil end
	local station = tpl:Clone()
	station.Name = Defs.STATION
	pcall(function() station:PivotTo(cf) end)
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	hideMarkers(station)
	station.Parent = Workspace
	table.insert(built, station)
	runStation(station, player)
	print(LOG .. " восстановлена из сейва")
	return station
end

print(LOG .. " готова: ставится молотком на сушу острова, рабочие качают нефть")
