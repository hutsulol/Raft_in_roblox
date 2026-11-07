--[[
	ФЕРМА: постановка молотком, один фермер из дома, четыре овцы, шерсть.

	Ставится на сушу острова теми же правилами, что вышка и дом (_G.OilRigSpotOK),
	дальше живёт сама: овцы гуляют по загону, едят из кормушки, пьют из поилки,
	ночью спят в хлеве; фермер (житель дома с профессией «Фермер») носит сено и
	воду, чистит подстилку, подзывает готовую овцу, стрижёт её и относит шерсть на
	склад. Игрок пополняет сено (листвой) и воду (кружкой), забирает шерсть со
	склада, а в 23:00 получает дневной доход в пиратах.

	⚠️ ВСЁ РЕШАЕТ СЕРВЕР. Запасы, потребности, резервы и выдача шерсти живут в
	таблице farm; клиент только играет позы по атрибутам Clip/ClipOnce (Motor6D.
	Transform с сервера не реплицируется — см. PirateIslandAnim.client).

	⚠️ ОДИН NPC — ОДНА ЗАДАЧА. Задача резервирует овцу, точку и порцию ресурса;
	при отмене резерв снимается, а груз в руках возвращается на склад (или
	остаётся связкой на площадке) — он не исчезает и не удваивается.

	⚠️ ТОЧКИ СЧИТАЮТСЯ ОТ ГЕОМЕТРИИ МОДЕЛИ (FarmDefs.frame): маркеров wp_* в
	Farm_Island_Build нет, а модель могла быть импортирована в любом масштабе.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local TweenService      = game:GetService("TweenService")

local Defs      = require(ReplicatedStorage:WaitForChild("FarmDefs"))
local HouseDefs = require(ReplicatedStorage:WaitForChild("HouseDefs"))
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))
local ResourceNamesRu = require(ReplicatedStorage:WaitForChild("ResourceNamesRu"))
local SheepRig  = require(ReplicatedStorage:WaitForChild("SheepRig"))

local LOG = "[Ферма]"

local placeEvent = ReplicatedStorage:FindFirstChild("FarmPlace")
if not placeEvent then
	placeEvent = Instance.new("RemoteEvent")
	placeEvent.Name = "FarmPlace"
	placeEvent.Parent = ReplicatedStorage
end

-- ═══════════ общее ═══════════

local function findTemplate(name)
	return AssetFind.find(name) or Workspace:FindFirstChild(name)
end

local function clock() return Lighting.ClockTime end

local function nightNow()
	local t = clock()
	return t >= Defs.WORK_END or t < Defs.WORK_START
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

--[[ ⚠️ ДЕТАЛЬ ПО ИМЕНИ, А НЕ ПЕРВЫЙ ПОПАВШИЙСЯ ИНСТАНС. Импортёр Studio
     заворачивает каждый MeshPart в Model-узел с тем же именем (или с
     суффиксом _Node): FindFirstChild(name, true) отдавал узел, и обращение к
     Transparency падало («Transparency is not a valid member of Model»).
     Берём первый BasePart с таким именем; нет — первую деталь внутри
     одноимённой модели. ]]
local function findPart(root, name)
	local lname = name:lower()
	local fallback
	for _, d in ipairs(root:GetDescendants()) do
		local n = d.Name:lower()
		if n == lname or n == lname .. "_node" then
			if d:IsA("BasePart") then return d end
			if d:IsA("Model") and not fallback then fallback = d:FindFirstChildWhichIsA("BasePart", true) end
		end
	end
	return fallback
end

local function setClip(model, key, once)
	local name = Defs.CLIPS[key] or key
	if once then
		model:SetAttribute("ClipOnce", name)
		model:SetAttribute("ClipOnceT", Workspace:GetServerTimeNow())
	else
		if model:GetAttribute("Clip") ~= name then model:SetAttribute("Clip", name) end
	end
end

local function faceTo(model, pos)
	local hrp = model:FindFirstChild("HumanoidRootPart", true)
	if not hrp then return end
	local d = flat(pos - hrp.Position)
	if d.Magnitude < 0.3 then return end
	hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + d.Unit)
end

-- Остров под точкой и его гарнизон — как у дома/вышки
local function islandAt(pos)
	local best, bestD
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("MapIsland") then
			local c = m:GetAttribute("LandCenter")
			if typeof(c) ~= "Vector3" then c = m:GetPivot().Position end
			local r = tonumber(m:GetAttribute("LandRadius")) or 300
			local d = (flat(c) - flat(pos)).Magnitude
			if d <= r + 80 and (not bestD or d < bestD) then best, bestD = m, d end
		end
	end
	return best
end

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

-- ═══════════ реестр ферм ═══════════

local farms = {}      -- список записей фермы
local nextId = 1

local function farmById(id)
	for _, f in ipairs(farms) do
		if f.id == id and f.model.Parent then return f end
	end
	return nil
end

_G.FarmNameOf = function(id)
	return ("Ферма %d"):format(tonumber(id) or 0)
end

_G.FarmCount = function()
	local n = 0
	for _, f in ipairs(farms) do if f.model.Parent then n += 1 end end
	return n
end

-- Авторская модель из Farm_Props_Pack в масштабе фермы. Масштаб импорта
-- комплекта неизвестен, поэтому меряем: высота габарита клона / авторская
-- высота в метрах = студов на метр у комплекта; приводим к масштабу фермы.
-- Все детали свариваются к PrimaryPart, пивот — центр габарита (под хват).
-- nil — модели нет, вызывающий ставит заглушку.
local function authoredProp(farm, key)
	local spec = Defs.PROP_MODELS[key]
	local tpl = spec and findTemplate(spec.name)
	if not tpl then return nil end
	local m = tpl:Clone()
	if m:IsA("BasePart") then
		local wrap = Instance.new("Model"); wrap.Name = spec.name
		m.Parent = wrap; wrap.PrimaryPart = m
		m = wrap
	end
	-- метки хвата (Grip) приезжают пустыми моделями — убираем, чтобы не мешали габариту
	for _, d in ipairs(m:GetChildren()) do
		if d:IsA("Model") and #d:GetChildren() == 0 then d:Destroy() end
	end
	local primary = m:FindFirstChild(spec.primary, true)
	if not (primary and primary:IsA("BasePart")) then primary = m:FindFirstChildWhichIsA("BasePart", true) end
	if not primary then m:Destroy(); return nil end
	m.PrimaryPart = primary
	if Defs.PROP_AUTOSCALE then
		local _, size = m:GetBoundingBox()
		local packScale = size.Y / spec.height
		if packScale > 0.05 then
			local k = farm.fr.scale / packScale
			if math.abs(k - 1) > 0.02 then pcall(function() m:ScaleTo(k) end) end
		end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			if d ~= primary then
				local w = Instance.new("WeldConstraint"); w.Part0 = primary; w.Part1 = d; w.Parent = primary
			end
		end
	end
	local bcf = m:GetBoundingBox()
	m.WorldPivot = bcf
	return m
end

-- ═══════════ реквизит ═══════════

local function mkPart(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end

-- Простые модели предметов: ведро, грабли, ножницы, связка сена, связка шерсти.
-- Всё — из деталей, в стиле «крашеной палитры» фермы; PrimaryPart — рукоять.
local PROPS = {}

PROPS.bucket = function(s)
	local m = Instance.new("Model"); m.Name = "Farm_Bucket"
	local body = mkPart({ Name = "Handle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 1.1, 1.1) * s,
		Color = Color3.fromRGB(120, 126, 134), Material = Enum.Material.Metal }, m)
	body.CFrame = CFrame.Angles(0, 0, math.rad(90))
	local water = mkPart({ Name = "Water", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.95, 0.95) * s,
		Color = Color3.fromRGB(96, 170, 220), Material = Enum.Material.Glass, Transparency = 1 }, m)
	water.CFrame = body.CFrame * CFrame.new(0.5 * s, 0, 0)
	local w = Instance.new("WeldConstraint"); w.Part0 = body; w.Part1 = water; w.Parent = body
	m.PrimaryPart = body
	return m
end

PROPS.rake = function(s)
	local m = Instance.new("Model"); m.Name = "Farm_Rake"
	local handle = mkPart({ Name = "Handle", Size = Vector3.new(0.22, 0.22, 4.4) * s,
		Color = Color3.fromRGB(150, 110, 70), Material = Enum.Material.Wood }, m)
	local head = mkPart({ Name = "Head", Size = Vector3.new(1.7, 0.18, 0.5) * s,
		Color = Color3.fromRGB(110, 112, 118), Material = Enum.Material.Metal }, m)
	head.CFrame = handle.CFrame * CFrame.new(0, 0, -2.3 * s)
	local w = Instance.new("WeldConstraint"); w.Part0 = handle; w.Part1 = head; w.Parent = handle
	m.PrimaryPart = handle
	return m
end

PROPS.shears = function(s)
	local m = Instance.new("Model"); m.Name = "Farm_Shears"
	local a = mkPart({ Name = "Handle", Size = Vector3.new(0.14, 0.14, 1.5) * s,
		Color = Color3.fromRGB(190, 194, 200), Material = Enum.Material.Metal }, m)
	local b = mkPart({ Name = "Blade", Size = Vector3.new(0.14, 0.14, 1.5) * s,
		Color = Color3.fromRGB(190, 194, 200), Material = Enum.Material.Metal }, m)
	a.CFrame = CFrame.Angles(0, math.rad(8), 0)
	b.CFrame = CFrame.Angles(0, math.rad(-8), 0)
	local w = Instance.new("WeldConstraint"); w.Part0 = a; w.Part1 = b; w.Parent = a
	m.PrimaryPart = a
	return m
end

-- ⚠️ ЗАГЛУШКИ НИЖЕ — ЗАПАСНОЙ ПУТЬ. Сначала пробуем авторскую модель из
-- Farm_Props_Pack (см. FarmDefs.PROP_MODELS); farm передаётся вторым аргументом.
PROPS.hayStub = function(s)
	local m = Instance.new("Model"); m.Name = "Farm_HayBundle"
	local p = mkPart({ Name = "Handle", Size = Vector3.new(1.6, 1.0, 1.4) * s,
		Color = Color3.fromRGB(214, 184, 96), Material = Enum.Material.Fabric }, m)
	m.PrimaryPart = p
	return m
end

PROPS.hay = function(s, farm)
	return (farm and authoredProp(farm, "hay")) or PROPS.hayStub(s)
end

PROPS.waste = function(s, farm)
	local m = PROPS.hay(s, farm); m.Name = "Farm_Waste"
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Color = Color3.fromRGB(128, 104, 62) end
	end
	return m
end

PROPS.woolStub = function(s)
	local m = Instance.new("Model"); m.Name = "Farm_WoolBundle"
	local p = mkPart({ Name = "Handle", Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.5, 1.5) * s,
		Color = Color3.fromRGB(240, 236, 220), Material = Enum.Material.Fabric }, m)
	m.PrimaryPart = p
	return m
end

-- в руках — корзина с шерстью, на площадке стрижки — связка
PROPS.wool = function(s, farm)
	return (farm and authoredProp(farm, "woolCarry")) or PROPS.woolStub(s)
end
PROPS.woolDrop = function(s, farm)
	return (farm and authoredProp(farm, "woolDrop")) or PROPS.woolStub(s)
end

-- ═══════════ фермер: тело и реквизит в руке ═══════════

local function prepWorker(model, cf)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = (d.Name == "HumanoidRootPart")
		elseif d:IsA("BaseScript") then
			d.Disabled = true   -- родной Animate перебил бы наши клипы
		end
	end
	pcall(function() model:PivotTo(cf) end)
	model:SetAttribute("CrewAnim", true)
	model:SetAttribute("Friendly", true)
	local hum = model:FindFirstChildWhichIsA("Humanoid", true)
	if hum then
		hum.WalkSpeed = 9
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	return hum
end

-- вышка вкладывает в шаблон рабочего свой бур — фермеру он ни к чему
local function dropForeignTools(model)
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("Tool") then d:Destroy() end
	end
	for _, name in ipairs({ "Oil_Tool", "Raft_jerrycan_plastic", "Plastic_canister", "Jerrycan", "Canister" }) do
		local x = model:FindFirstChild(name, true)
		if x then x:Destroy() end
	end
end

local function holdProp(model, prop, grip)
	local arm = model:FindFirstChild("Right Arm", true)
	if not (arm and prop and prop.PrimaryPart) then return nil end
	for _, j in ipairs(arm:GetChildren()) do
		if j:IsA("Motor6D") and j.Name == "PropGrip" then j:Destroy() end
	end
	for _, d in ipairs(prop:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = false; d.Massless = true; d.CanCollide = false end
	end
	prop:PivotTo(arm.CFrame * grip)
	prop.Parent = model
	local motor = Instance.new("Motor6D")
	motor.Name = "PropGrip"
	motor.Part0 = arm
	motor.Part1 = prop.PrimaryPart
	-- C0 — фактическое смещение до PrimaryPart: у авторских моделей пивот
	-- (центр габарита) и PrimaryPart не совпадают
	motor.C0 = arm.CFrame:Inverse() * prop.PrimaryPart.CFrame
	motor.Parent = arm
	return motor
end

-- на ночь без дома фермер уходит за ворота и «исчезает»: прячем детали и
-- держим на месте; модель остаётся в мире, иначе оборвался бы поток задач
local function hideWorker(model, hidden)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:GetAttribute("Tr0") == nil then d:SetAttribute("Tr0", d.Transparency) end
			d.Transparency = hidden and 1 or (d:GetAttribute("Tr0") or 0)
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = hidden and 1 or 0
		end
	end
	local hrp = model:FindFirstChild("HumanoidRootPart", true)
	if hrp then hrp.Anchored = hidden end
end

local function dropProp(model)
	local arm = model:FindFirstChild("Right Arm", true)
	if not arm then return end
	for _, j in ipairs(arm:GetChildren()) do
		if j:IsA("Motor6D") and j.Name == "PropGrip" then
			local held = j.Part1 and j.Part1.Parent
			j:Destroy()
			if held and held ~= model and held:IsA("Model") then held:Destroy() end
		end
	end
end

-- ═══════════ земля и пол ═══════════

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = true

local function groundList(farm)
	if farm.groundList then return farm.groundList end
	local list = {}
	for _, name in ipairs(Defs.FLOOR_PARTS) do
		local p = farm.model:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then table.insert(list, p) end
	end
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:sub(1, #Defs.TILE_PREFIX) == Defs.TILE_PREFIX
			and (d.Position - farm.model:GetPivot().Position).Magnitude < 260 then
			table.insert(list, d)
		end
	end
	farm.groundList = list
	return list
end

local function groundY(farm, pos)
	groundParams.FilterDescendantsInstances = groundList(farm)
	local hit = Workspace:Raycast(pos + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), groundParams)
	return hit and hit.Position.Y or nil
end

-- ═══════════ двери ═══════════

local function setupDoors(farm)
	farm.doors = {}
	for _, d in ipairs(Defs.DOORS) do
		local part = findPart(farm.model, d.part)
		if part then
			local off = Vector3.new(d.hinge[1], 0, -d.hinge[2]) * farm.fr.scale
			local hinge = part.Position + farm.fr.rot:VectorToWorldSpace(off)
			farm.doors[d.part] = {
				part = part, base = part.CFrame, hinge = hinge,
				openDeg = d.openDeg, closeDeg = d.closeDeg, deg = 0, closed = (d.openDeg ~= 0),
			}
			-- авторская поза: у створок хлева открыто (0), у ворот закрыто (0)
			farm.doors[d.part].closed = (d.closeDeg == 0)
		end
	end
end

local function doorCF(door, deg)
	local pivot = CFrame.new(door.hinge)
	return pivot * CFrame.Angles(0, math.rad(deg), 0) * (pivot:Inverse() * door.base)
end

local function swingDoor(door, deg, animate)
	door.deg = deg
	if not animate then
		door.part.CFrame = doorCF(door, deg)
		return
	end
	local from = door.part.CFrame
	local to = doorCF(door, deg)
	local t0 = os.clock()
	while os.clock() - t0 < Defs.DOOR_SWING_SEC and door.part.Parent do
		local k = (os.clock() - t0) / Defs.DOOR_SWING_SEC
		k = 1 - (1 - k) * (1 - k)
		door.part.CFrame = from:Lerp(to, k)
		task.wait()
	end
	if door.part.Parent then door.part.CFrame = to end
end

local function barnDoorwayBusy(farm)
	for _, sh in ipairs(farm.sheep) do
		local root = sh.model.PrimaryPart
		if root then
			local x, y = Defs.toLocal(farm.fr, root.Position)
			if Defs.inDoorway(x, y) then return true end
		end
	end
	local w = farm.worker and farm.worker:FindFirstChild("HumanoidRootPart", true)
	if w then
		local x, y = Defs.toLocal(farm.fr, w.Position)
		if Defs.inDoorway(x, y) then return true end
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local x, y = Defs.toLocal(farm.fr, hrp.Position)
			if Defs.inDoorway(x, y) then return true end
		end
	end
	return false
end

-- Створки хлева: открыть/закрыть (обе). Закрыть нельзя, пока проём занят.
local function setBarn(farm, closed, animate)
	if closed and barnDoorwayBusy(farm) then return false end
	for _, name in ipairs({ "Barn_Door_Left", "Barn_Door_Right" }) do
		local door = farm.doors[name]
		if door then
			door.closed = closed
			task.spawn(swingDoor, door, closed and door.closeDeg or door.openDeg, animate)
		end
	end
	farm.barnClosed = closed
	return true
end

-- Игрок тоже может дёрнуть ворота/двери: та же проверка проёма
local function doorPrompt(farm, name, label)
	local door = farm.doors[name]
	if not door then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FarmDoorPrompt"
	prompt.ActionText = label
	prompt.ObjectText = Defs.NAME_RU
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = door.part
	prompt.Triggered:Connect(function()
		if name == "Gate" then
			door.closed = not door.closed
			task.spawn(swingDoor, door, door.closed and door.closeDeg or door.openDeg, true)
		else
			if not setBarn(farm, not farm.barnClosed, true) then
				prompt.ActionText = "Проём занят"
				task.delay(1.5, function() prompt.ActionText = label end)
			end
		end
	end)
end

-- ═══════════ вывеска и склады ═══════════

local function statusText(farm)
	local who = farm.farmerName and ("Фермер: " .. farm.farmerName) or "Нет фермера: назначь в доме"
	local stock = ("Сено %d · Вода %d · Шерсть %d/%d"):format(
		math.floor(farm.hay + 0.5), math.floor(farm.water + 0.5), farm.wool, Defs.WOOL_CAP)
	local ready = 0
	for _, sh in ipairs(farm.sheep) do if sh.wool >= 100 then ready += 1 end end
	local herd = (#farm.sheep > 0) and ("Овец: %d, готово к стрижке: %d"):format(#farm.sheep, ready)
		or (farm.sheepWhy or "Овец нет: модели «Sheep» нет в ReplicatedStorage")
	return who, stock, herd, farm.status or ""
end

local function infoBoard(farm)
	local cf = Defs.pointCF(farm.fr, "sign")
	if not cf then return end
	--[[ ⚠️ ТАБЛИЧКА В МИРЕ, КАК У ДОМА, А НЕ BillboardGui.
	     Billboard подгоняет размер под расстояние и вблизи разрастался на
	     пол-экрана (владелец: «статичный, не адаптирующийся под дистанцию»).
	     Дом рисует SurfaceGui на детали — делаем ту же доску над коньком хлева:
	     размер в студах, текст на поверхности, лицом к воротам. ]]
	local s = farm.fr.scale
	local host = mkPart({ Name = "FarmSign", Size = Vector3.new(10 * s / 3, 3.2 * s / 3, 0.25),
		Color = Color3.fromRGB(18, 20, 26), Material = Enum.Material.Wood, CanQuery = false }, farm.model)
	-- лицевая грань Front (−Z детали) при повороте фермы смотрит к воротам
	-- ⚠️ без доворота: с разворотом на 180° доска стояла тылом к воротам (владелец)
	host.CFrame = CFrame.new(cf.Position) * farm.fr.rot
	local gui = Instance.new("SurfaceGui")
	gui.Name = "FarmInfo"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = host
	local pad = Instance.new("Frame")
	pad.Size = UDim2.fromScale(1, 1)
	pad.BackgroundColor3 = Defs.UI.BACK
	pad.BackgroundTransparency = 0.15
	pad.BorderSizePixel = 0
	pad.Parent = gui
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 10); corner.Parent = pad
	local inset = Instance.new("UIPadding")
	inset.PaddingTop = UDim.new(0.06, 0); inset.PaddingBottom = UDim.new(0.06, 0)
	inset.PaddingLeft = UDim.new(0.04, 0); inset.PaddingRight = UDim.new(0.04, 0)
	inset.Parent = pad
	local col = Instance.new("UIListLayout")
	col.FillDirection = Enum.FillDirection.Vertical
	col.HorizontalAlignment = Enum.HorizontalAlignment.Center
	col.VerticalAlignment = Enum.VerticalAlignment.Center
	col.Padding = UDim.new(0.02, 0)
	col.Parent = pad
	local labels = {}
	for i = 1, 4 do
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, 0, i == 1 and 0.3 or 0.2, 0)
		l.BackgroundTransparency = 1
		l.Font = i == 1 and Enum.Font.GothamBold or Enum.Font.Gotham
		l.TextScaled = true
		l.TextColor3 = i == 1 and Defs.UI.TITLE or Defs.UI.WOOL
		l.LayoutOrder = i
		l.Parent = pad
		labels[i] = l
	end
	farm.redraw = function()
		if not host.Parent then return end
		local who, stock, herd, st = statusText(farm)
		labels[1].Text = ("%s · %s"):format(_G.FarmNameOf(farm.id), who)
		labels[1].TextColor3 = farm.farmerName and Defs.UI.TITLE or Defs.UI.WARN
		labels[2].Text = stock
		labels[3].Text = herd
		labels[4].Text = st
		labels[4].TextColor3 = (farm.statusBad and Defs.UI.WARN) or Defs.UI.OK
	end
	farm.redraw()
end

local function setStatus(farm, text, bad)
	farm.status, farm.statusBad = text, bad
	farm.model:SetAttribute("FarmStatus", text)
	if farm.redraw then farm.redraw() end
end

local function notify(player, opts)
	if typeof(_G.NotifyPlayer) == "function" then pcall(_G.NotifyPlayer, player, opts) end
end

-- Бочка воды и ящик шерсти ставятся скриптом (в модели их нет); подсказки
-- пополнения и выдачи — на них и на тюках сена.
-- Авторская модель по имени (Model или деталь): клон, низ габарита — на grndY,
-- поворот как у фермы. nil — модели нет, ставим заглушку.
-- Стационарный проп (бочка/ящик) на точку: низ габарита на gy, поворот фермы.
-- nil — модели нет, ставим заглушку.
local function placeAuthored(farm, key, pos, gy)
	local m = authoredProp(farm, key)
	if not m then return nil end
	local _, size = m:GetBoundingBox()
	m:PivotTo(CFrame.new(pos.X, gy + size.Y * 0.5, pos.Z) * farm.fr.rot)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.CanCollide = true; d.CanQuery = true end
	end
	m.Parent = farm.model
	return m
end

-- Встроенная в модель подмодель (Farm_WaterBarrel / Farm_WoolCrate): ищем по
-- имени внутри фермы. Нашли — рабочая точка фермера считается ОТ НЕЁ: на метр
-- к центру двора, лицом к предмету (fr.override перекрывает таблицу POINTS).
local function embeddedModel(farm, name, storePoint)
	local m = farm.model:FindFirstChild(name, true)
	if not (m and m:IsA("Model")) then return nil end
	local cf, size = m:GetBoundingBox()
	-- пивот подмодели — в центр её габарита: авторский пивот съезжал в сторону
	-- (владелец), и всё, что считало от GetPivot, промахивалось
	pcall(function() m.WorldPivot = cf end)
	local centre = Defs.toWorld(farm.fr, 0, -1.0, 0)     -- центр двора
	local to = flat(centre - cf.Position)
	if to.Magnitude < 0.1 then to = farm.fr.rot.LookVector end
	-- подход вплотную: полширины предмета плюс полметра, но не дальше 2.2 м от центра
	local reach = math.min(math.max(size.X, size.Z) * 0.5 + 0.5 * farm.fr.scale, 2.2 * farm.fr.scale)
	local stand = cf.Position + to.Unit * reach
	local gy = groundY(farm, stand) or stand.Y
	farm.fr.override = farm.fr.override or {}
	farm.fr.override[storePoint] = CFrame.lookAt(Vector3.new(stand.X, gy, stand.Z),
		Vector3.new(cf.Position.X, gy, cf.Position.Z))
	return m, cf, size
end

local function setupStores(farm)
	local s = farm.fr.scale
	-- бочка
	local bcf = Defs.pointCF(farm.fr, "water_barrel")
	local embBarrel, ebCF, ebSize = embeddedModel(farm, Defs.WATER_BARREL_MODEL, "water_store")
	if embBarrel then bcf = CFrame.new(ebCF.Position) end
	if bcf then
		local gy = groundY(farm, bcf.Position) or bcf.Position.Y
		local authored = embBarrel or placeAuthored(farm, "barrel", bcf.Position, gy)
		local barrel = authored and (authored.PrimaryPart or authored:FindFirstChildWhichIsA("BasePart", true))
		if authored then
			-- поверхность воды: уровень и радиус от запаса (FarmDefs.WATER_LEVEL).
			-- В новой модели деталь может называться Water_Surface2 — берём по префиксу
			local surf
			for _, d in ipairs(authored:GetDescendants()) do
				if d:IsA("BasePart") and d.Name:sub(1, 13) == "Water_Surface" then surf = d break end
			end
			if surf then
				surf.CanCollide = false; surf.CanTouch = false; surf.CanQuery = false
				local wcf, wsize = authored:GetBoundingBox()
				if embBarrel then wcf, wsize = ebCF, ebSize end
				farm.waterSurface = { part = surf, bottomY = wcf.Position.Y - wsize.Y * 0.5,
					x = wcf.Position.X, z = wcf.Position.Z }
			end
		end
		if not barrel then
			barrel = mkPart({ Name = "Farm_WaterBarrel", Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.05, 0.95, 0.95) * s, Color = Color3.fromRGB(122, 90, 58),
				Material = Enum.Material.Wood, CanCollide = true, CanQuery = true }, farm.model)
			barrel.CFrame = CFrame.new(bcf.Position.X, gy + 0.525 * s, bcf.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Залить воду из кружки"
		prompt.ObjectText = "Запас воды"
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = barrel
		prompt.Triggered:Connect(function(player)
			local char = player.Character
			local tool = char and char:FindFirstChildWhichIsA("Tool")
			local charges = tool and tonumber(tool:GetAttribute("CupCharges")) or 0
			if not tool or charges <= 0 or tool:GetAttribute("CupState") == "empty" then
				notify(player, { type = "warn", icon = "no", title = "Нужна вода",
					body = "Возьми в руки полную кружку или бутылку" })
				return
			end
			if farm.water >= Defs.WATER_STORE_CAP then
				notify(player, { type = "warn", icon = "no", title = "Бочка полна", body = "Запас воды заполнен" })
				return
			end
			charges -= 1
			tool:SetAttribute("CupCharges", charges)
			if charges <= 0 and typeof(_G.SetCupState) == "function" then pcall(_G.SetCupState, tool, "empty") end
			farm.water = math.min(Defs.WATER_STORE_CAP, farm.water + Defs.WATER_PER_CUP)
			farm.redraw()
		end)
	end
	-- тюки сена: подсказка на самих тюках
	local bales = findPart(farm.model, "Hay_Bales")
	if bales then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = ("Положить листву (+%d сена)"):format(Defs.HAY_PER_ITEM)
		prompt.ObjectText = "Запас сена"
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = bales
		prompt.Triggered:Connect(function(player)
			if farm.hay >= Defs.HAY_STORE_CAP then
				notify(player, { type = "warn", icon = "no", title = "Сеновал полон", body = "Запас сена заполнен" })
				return
			end
			local inv = (typeof(_G.GetInventory) == "function" and _G.GetInventory(player)) or {}
			if (inv[Defs.HAY_ITEM] or 0) < 1 then
				notify(player, { type = "warn", icon = "no", title = "Нужна листва",
					body = "Сено делается из листвы: 1 листва → " .. Defs.HAY_PER_ITEM .. " сена" })
				return
			end
			if typeof(_G.RemoveResourceFromInventory) == "function" then
				_G.RemoveResourceFromInventory(player, Defs.HAY_ITEM, 1)
				if typeof(_G.SendInventory) == "function" then _G.SendInventory(player) end
			end
			farm.hay = math.min(Defs.HAY_STORE_CAP, farm.hay + Defs.HAY_PER_ITEM)
			farm.redraw()
		end)
	end
	-- ящик шерсти
	local ccf = Defs.pointCF(farm.fr, "wool_crate")
	local embCrate, ecCF, ecSize = embeddedModel(farm, Defs.WOOL_CRATE_MODEL, "wool_store")
	if embCrate then ccf = CFrame.new(ecCF.Position) end
	if ccf then
		local gy = groundY(farm, ccf.Position) or ccf.Position.Y
		local authored = embCrate or placeAuthored(farm, "crate", ccf.Position, gy)
		local crate = authored and (authored.PrimaryPart or authored:FindFirstChildWhichIsA("BasePart", true))
		local crateTop
		if crate then
			local _, size = authored:GetBoundingBox()
			if embCrate then size = ecSize; gy = ecCF.Position.Y - ecSize.Y * 0.5 end
			crateTop = gy + size.Y
			-- связки в ящике — индикатор заполнения (FarmDefs.CRATE_BUNDLE_AT):
			-- все детали со словом wool по алфавиту (Wool_Bundle_01 → 02 → 03)
			farm.woolBundles = {}
			for _, b in ipairs(authored:GetDescendants()) do
				if b:IsA("BasePart") and b.Name:lower():find("wool", 1, true) then table.insert(farm.woolBundles, b) end
			end
			table.sort(farm.woolBundles, function(a, b) return a.Name < b.Name end)
			if #farm.woolBundles == 0 then farm.woolBundles = nil end
		else
			crate = mkPart({ Name = "Farm_WoolCrate", Size = Vector3.new(1.3, 0.9, 1.3) * s,
				Color = Color3.fromRGB(150, 116, 74), Material = Enum.Material.WoodPlanks, CanCollide = true, CanQuery = true }, farm.model)
			crate.CFrame = CFrame.new(ccf.Position.X, gy + 0.45 * s, ccf.Position.Z) * farm.fr.rot
			crateTop = gy + 0.9 * s
		end
		local pile = mkPart({ Name = "WoolPile", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.1, 1.1) * s,
			Color = Color3.fromRGB(240, 236, 220), Material = Enum.Material.Fabric, Transparency = 1 }, farm.model)
		pile.CFrame = CFrame.new(ccf.Position.X, crateTop + 0.15 * s, ccf.Position.Z)
		farm.woolPile = pile
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Забрать шерсть"
		prompt.ObjectText = "Склад шерсти"
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = crate
		farm.woolPrompt = prompt
		prompt.Triggered:Connect(function(player)
			if farm.wool <= 0 then
				notify(player, { type = "warn", icon = "no", title = "Склад пуст", body = "Шерсти пока нет" })
				return
			end
			local n = farm.wool
			local ok, res = pcall(_G.AddResourceToInventory, player, Defs.WOOL_ITEM, n)
			if ok and res ~= false then
				farm.wool = 0
				pile.Transparency = 1
				prompt.ActionText = "Забрать шерсть"
				if typeof(_G.OnQuestResource) == "function" then pcall(_G.OnQuestResource, player, Defs.WOOL_ITEM, n) end
				notify(player, { type = "success", icon = "ok", title = "Шерсть забрана",
					body = ("+%d %s"):format(n, ResourceNamesRu[Defs.WOOL_ITEM] or Defs.WOOL_ITEM) })
				farm.redraw()
			else
				notify(player, { type = "warn", icon = "no", title = "Нет места", body = "Освободи инвентарь" })
			end
		end)
	end
end

local function refreshWoolPile(farm)
	if farm.woolBundles then
		-- связки: наполняются по порядку, пустеют с конца; пусто — все прозрачны
		local k = farm.wool / Defs.WOOL_CAP
		local n = #farm.woolBundles
		for i, b in ipairs(farm.woolBundles) do
			local at = Defs.CRATE_BUNDLE_AT[i] or ((i - 1) / n + 0.001)
			if b.Parent then b.Transparency = (farm.wool > 0 and k >= at) and 0 or 1 end
		end
		if farm.woolPile then farm.woolPile.Transparency = 1 end
	elseif farm.woolPile then
		farm.woolPile.Transparency = (farm.wool > 0) and 0 or 1
		local k = 0.6 + 0.6 * math.clamp(farm.wool / Defs.WOOL_CAP, 0, 1)
		farm.woolPile.Size = Vector3.new(1.1, 1.1, 1.1) * farm.fr.scale * k
	end
	if farm.woolPrompt then
		farm.woolPrompt.ActionText = (farm.wool > 0) and ("Забрать шерсть (%d)"):format(farm.wool) or "Забрать шерсть"
	end
end

-- уровень воды в поилке и сено в кормушке — видимые детали модели
local function refreshVisuals(farm)
	-- поилка: своя поверхность воды внутри модели фермы (не бочки!)
	local troughSurf = findPart(farm.model, "Trough_Water_Surface")
	if not troughSurf then
		for _, d in ipairs(farm.model:GetChildren()) do
			if d:IsA("BasePart") and d.Name == "Water_Surface" then troughSurf = d break end
		end
	end
	if troughSurf then
		troughSurf.Transparency = (farm.trough > 0.5) and 0 or 1
	end
	-- бочка: уровень воды от запаса
	local ws = farm.waterSurface
	if ws and ws.part.Parent then
		local L = Defs.WATER_LEVEL
		local s = farm.fr.scale
		if farm.water <= 0.5 then
			ws.part.Transparency = 1
		else
			local k = math.clamp(farm.water / Defs.WATER_STORE_CAP, 0, 1)
			local y = L.minY + (L.maxY - L.minY) * k
			local r = L.minR + (L.maxR - L.minR) * k
			ws.part.Transparency = 0
			ws.part.Size = Vector3.new(2 * r * s, L.thick * s, 2 * r * s)
			ws.part.CFrame = CFrame.new(ws.x, ws.bottomY + y * s + L.thick * s * 0.5, ws.z) * farm.fr.rot
		end
	end
	local feed = findPart(farm.model, "Hay_Feed")
	if feed then
		feed.Transparency = (farm.feeder > 0.5) and 0 or 1
	end
	refreshWoolPile(farm)
end

-- ═══════════ овцы ═══════════

-- Шерсть — ВСЕ детали со словом Wool (BodyWool, HeadWool, TailWool у нового
-- рига; одна Wool у старого): стрижка прячет их все, отрастание масштабирует.
local function woolLook(sh)
	if not sh.woolParts or not next(sh.woolParts) then return end
	local look = (sh.wool >= 85) and Defs.WOOL_LOOK.full or (sh.wool >= 35) and Defs.WOOL_LOOK.grow or Defs.WOOL_LOOK.short
	if sh.look == look then return end
	sh.look = look
	for part, size0 in pairs(sh.woolParts) do
		if part.Parent then
			part.Transparency = look.visible and 0 or 1
			if look.visible and look.scale ~= 1 then part.Size = size0 * look.scale end
		end
	end
end

local function sheepClip(sh, state)
	if sh.model:GetAttribute("Clip") ~= state then sh.model:SetAttribute("Clip", state) end
end

local function sheepReact(sh)
	sh.model:SetAttribute("ClipOnce", "React")
	sh.model:SetAttribute("ClipOnceT", Workspace:GetServerTimeNow())
end

local function spawnSheep(farm, saved)
	--[[ ⚠️ ШАБЛОН ОВЦЫ ИЩЕМ ШИРОКО. Точное имя «Sheep» могло не совпасть: модель
	     в Studio назвали sheep, Sheep_Rig, Farm_Sheep, положили в папку или
	     внутрь другой модели. Сначала точные имена (любой регистр), потом любая
	     Model в ReplicatedStorage, в имени которой есть «sheep», кроме самой
	     фермы, её маркеров Spawn_Sheep и комплекта пропов. Что взяли — в Output. ]]
	local tpl = findTemplate(Defs.SHEEP) or findTemplate("Sheep_Rig") or findTemplate("SheepRig") or findTemplate("Farm_Sheep")
	if not tpl then
		local best, bestDepth = nil, math.huge
		for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
			if d:IsA("Model") and d.Name:lower():find("sheep", 1, true)
				and not d.Name:lower():find("farm_", 1, true) and not d.Name:lower():find("spawn", 1, true)
				and not d:FindFirstAncestor(Defs.MODEL) and not d:FindFirstAncestor(Defs.MODEL_ALT) then
				local depth, node = 0, d.Parent
				while node and node ~= ReplicatedStorage do depth += 1; node = node.Parent end
				if depth < bestDepth then best, bestDepth = d, depth end
			end
		end
		tpl = best
	end
	--[[ ⚠️ ОВЦЫ ВНУТРИ МОДЕЛИ ФЕРМЫ. Владелец положил четырёх овец прямо в
	     Farm_Build_Island_Sheep, отдельного шаблона в ReplicatedStorage нет.
	     Такие модели (в имени «sheep», не маркеры спавна, есть детали) берём
	     живыми на месте: собираем риг, переносим в папку зверей. Первая из них
	     служит и шаблоном для недостающих до четырёх. ]]
	local embedded = {}
	for _, d in ipairs(farm.model:GetDescendants()) do
		if d:IsA("Model") and d.Name:lower():find("sheep", 1, true)
			and not d.Name:lower():find("spawn", 1, true) and not d.Name:lower():find("facing", 1, true)
			and d.Name:lower() ~= "sheep_spawns" and d ~= farm.model
			and not d:FindFirstAncestorWhichIsA("Model"):GetAttribute("FarmSheep") then
			local n = 0
			for _, p in ipairs(d:GetDescendants()) do if p:IsA("BasePart") then n += 1 end end
			if n >= 3 then table.insert(embedded, d) end
		end
	end
	-- вложенные внутрь другой овцы не считаем дважды
	for i = #embedded, 1, -1 do
		for j, other in ipairs(embedded) do
			if j ~= i and embedded[i]:IsDescendantOf(other) then table.remove(embedded, i) break end
		end
	end
	if #embedded > 0 then
		table.sort(embedded, function(a, b) return a.Name < b.Name end)
		tpl = tpl or embedded[1]
		print(("%s овцы в самой модели фермы: %d"):format(LOG, #embedded))
	end
	farm.sheep = {}
	if not tpl then
		if not farm.warnedSheep then
			farm.warnedSheep = true
			local seen = {}
			for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
				if d.Name:lower():find("sheep", 1, true) then
					table.insert(seen, d:GetFullName() .. " (" .. d.ClassName .. ")")
				end
			end
			warn(LOG .. " модель овцы не найдена в ReplicatedStorage. Похожие по имени: "
				.. ((#seen > 0) and table.concat(seen, "; ") or "ничего"))
		end
		return
	end
	print(("%s шаблон овцы: %s (%s, деталей %d)"):format(LOG, tpl:GetFullName(), tpl.ClassName,
		(function() local n = 0 for _, d in ipairs(tpl:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end return n end)()))
	--[[ ТОЧКИ СПАВНА. Новая модель несёт маркеры Spawn_Sheep_01…04 (кубики,
	     прячем) с дочерним Facing: направление — от маркера к Facing по
	     горизонтали; Facing потерялся при импорте — берём −LookVector кубика
	     (его локальный +Z и есть блендеровский −Y, куда смотрит овца). Маркеров
	     нет вовсе (старая модель) — прячем статичных овец и встаём на их места,
	     а если и их нет — запасные числа из spawn_points.json. ]]
	local spots, faces = {}, {}
	for i = 1, 4 do
		local marker = farm.model:FindFirstChild(("%s%02d"):format(Defs.SPAWN_PREFIX, i), true)
		local part = marker and (marker:IsA("BasePart") and marker or marker:FindFirstChildWhichIsA("BasePart", true))
		if part then
			part.Transparency = 1; part.CanCollide = false; part.CanQuery = false; part.CanTouch = false
			spots[i] = part.Position
			local facing = farm.model:FindFirstChild(("%s%02d"):format(Defs.FACING_PREFIX, i), true)
			local fpos = facing and (facing:IsA("BasePart") and facing.Position
				or facing:IsA("Model") and facing:GetPivot().Position or nil)
			local dir = fpos and flat(fpos - part.Position) or nil
			if not dir or dir.Magnitude < 0.02 then dir = -flat(part.CFrame.LookVector) end
			faces[i] = (dir.Magnitude > 0.01) and dir.Unit or nil
		end
	end
	if not spots[1] then
		for _, d in ipairs(farm.model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:sub(1, #Defs.STATIC_SHEEP_PREFIX) == Defs.STATIC_SHEEP_PREFIX then
				d.Transparency = 1
				d.CanCollide = false
				d.CanQuery = false
				table.insert(spots, d.Position)
			end
		end
	end
	if not spots[1] then
		for i, sp in ipairs(Defs.SHEEP_SPAWNS) do
			spots[i] = Defs.toWorld(farm.fr, sp[1], sp[2], 0)
			faces[i] = farm.fr.rot:VectorToWorldSpace(Vector3.new(math.sin(sp[3]), 0, math.cos(sp[3])))
		end
	end
	for i = 1, 4 do
		local inPlace = embedded[i] ~= nil
		local m = inPlace and embedded[i] or tpl:Clone()
		m.Name = "Sheep_" .. i
		local ok, err = pcall(SheepRig.setup, m)
		if not ok then
			warn(LOG .. " риг овцы не собрался: " .. tostring(err))
			farm.sheepWhy = "Риг овцы не собрался: см. Output"
			m:Destroy()
			break
		end
		local pos = spots[i]
		if inPlace then
			-- стоит там, куда её поставили; смотрит туда, куда собран корень
			pos = m:GetPivot().Position
			local lv = flat(m.PrimaryPart and m.PrimaryPart.CFrame.LookVector or Vector3.new(0, 0, -1))
			if lv.Magnitude > 0.01 then faces[i] = lv.Unit end
		end
		if not pos then
			local x, y = Defs.randomYard()
			pos = Defs.toWorld(farm.fr, x, y, 0)
		end
		local gy = groundY(farm, pos) or pos.Y
		local foot = m:GetAttribute("FootOffset") or 1
		local at = Vector3.new(pos.X, gy + foot, pos.Z)
		local face = faces[i]
		if face then
			m:PivotTo(CFrame.lookAt(at, at + face))
		else
			m:PivotTo(CFrame.new(at) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
		end
		m:SetAttribute("SpawnId", ("Sheep_%02d"):format(i))
		m:SetAttribute("FarmId", farm.id)
		m:SetAttribute("AnimalRig", "Sheep")
		m:SetAttribute("Friendly", true)
		m:SetAttribute("FarmSheep", true)
		m:SetAttribute("AnimalId", i)
		m.Parent = farm.crew
		local rec = saved and saved[i] or {}
		local woolParts = SheepRig.woolParts(m)
		local sh = {
			model = m, id = i, foot = foot,
			hunger = tonumber(rec.hunger) or 80, thirst = tonumber(rec.thirst) or 80,
			stress = tonumber(rec.stress) or 0, wool = tonumber(rec.wool) or Defs.SHEEP_START_WOOL,
			mode = "idle", timer = 1 + math.random() * 2, busy = false, defer = 0,
			woolParts = woolParts, look = nil,
		}
		table.insert(farm.sheep, sh)
		sheepClip(sh, "Idle")
		woolLook(sh)
	end
	local first = farm.sheep[1] and farm.sheep[1].model
	local joints = {}
	if first then
		for _, d in ipairs(first:GetDescendants()) do if d:IsA("Motor6D") then table.insert(joints, d.Name) end end
	end
	print(("%s овец на ферме %d: %d | риг %s | суставы: %s"):format(LOG, farm.id, #farm.sheep,
		first and (first:GetAttribute("RigAuthored") and "авторский" or "собран из деталей") or "-",
		(#joints > 0) and table.concat(joints, ", ") or "нет"))
end

-- мировая позиция точки двора (метры) на земле
local function yardPos(farm, x, y)
	local p = Defs.toWorld(farm.fr, x, y, 0)
	local gy = groundY(farm, p) or p.Y
	return Vector3.new(p.X, gy, p.Z)
end

local function sheepPos(sh) return sh.model.PrimaryPart and sh.model.PrimaryPart.Position or Vector3.zero end

-- свободное место у кормушки/поилки
local function freeSlot(farm, prefix, sh)
	for i = 1, 2 do
		local name = prefix .. i
		local taken = farm.slots[name]
		if not taken or taken == sh or not taken.model.Parent then
			return name
		end
	end
	return nil
end

local function releaseSlots(farm, sh)
	for name, taker in pairs(farm.slots) do
		if taker == sh then farm.slots[name] = nil end
	end
end

-- Задать цель движения: мировая точка и режим прибытия
local function goTo(sh, worldPos, mode, arrive)
	sh.target = worldPos
	sh.arrive = arrive or 0.8
	sh.mode = mode
	sheepClip(sh, "Walk")
end

local TURN_RATE = 3.2

-- один шаг движения; возвращает true по прибытии
local function moveStep(farm, sh, dt, speed)
	local root = sh.model.PrimaryPart
	if not (root and sh.target) then return true end
	local pos = root.Position
	local to = flat(sh.target - pos)
	local dist = to.Magnitude
	if dist <= sh.arrive then return true end
	local want = to.Unit
	local look = flat(root.CFrame.LookVector)
	look = (look.Magnitude > 0.01) and look.Unit or want
	-- плавный разворот
	local cross = look:Cross(want).Y
	local dot = math.clamp(look:Dot(want), -1, 1)
	local ang = math.acos(dot)
	local step = math.min(ang, TURN_RATE * dt)
	local dir = look
	if ang > 0.001 then
		dir = (CFrame.Angles(0, (cross >= 0) and step or -step, 0):VectorToWorldSpace(look)).Unit
	end
	local adv = math.min(speed * dt, dist)
	-- идёт вперёд только когда развернулась хотя бы наполовину
	if ang > math.rad(70) then adv = adv * 0.25 end
	local nextPos = pos + dir * adv
	local lx, ly = Defs.toLocal(farm.fr, nextPos)
	if not Defs.walkable(lx, ly) then
		-- скользим вдоль препятствия: пробуем только X, только Z
		local tryX = Vector3.new(nextPos.X, pos.Y, pos.Z)
		local tryZ = Vector3.new(pos.X, pos.Y, nextPos.Z)
		local ax, ay = Defs.toLocal(farm.fr, tryX)
		local bx, by = Defs.toLocal(farm.fr, tryZ)
		if Defs.walkable(ax, ay) then nextPos = tryX
		elseif Defs.walkable(bx, by) then nextPos = tryZ
		else
			sh.blocked = (sh.blocked or 0) + dt
			-- упёрлась: ноги не перебирает (владелец: «ходят на месте»)
			sheepClip(sh, "Idle")
			return false
		end
	end
	sh.blocked = 0
	-- клип ходьбы — только когда реально идёт; на развороте стоит
	sheepClip(sh, (adv > speed * dt * 0.4) and "Walk" or "Idle")
	local gy = groundY(farm, nextPos) or (pos.Y - sh.foot)
	root.CFrame = CFrame.lookAt(Vector3.new(nextPos.X, gy + sh.foot, nextPos.Z),
		Vector3.new(nextPos.X, gy + sh.foot, nextPos.Z) + dir)
	return false
end

-- мягкий доворот к точке (стоя)
local function turnTo(sh, worldPos, dt)
	local root = sh.model.PrimaryPart
	if not root then return end
	local want = flat(worldPos - root.Position)
	if want.Magnitude < 0.3 then return end
	want = want.Unit
	local look = flat(root.CFrame.LookVector).Unit
	local cross = look:Cross(want).Y
	local ang = math.acos(math.clamp(look:Dot(want), -1, 1))
	if ang < 0.02 then return end
	local step = math.min(ang, TURN_RATE * dt)
	local dir = (CFrame.Angles(0, (cross >= 0) and step or -step, 0):VectorToWorldSpace(look)).Unit
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
end

local function nearestPlayerDist(pos)
	local best = math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp then best = math.min(best, (hrp.Position - pos).Magnitude) end
	end
	return best
end

local function growthRate(farm, sh)
	if sh.hunger < Defs.NEED_STOP or sh.thirst < Defs.NEED_STOP then return 0 end
	local k = 1
	if farm.clean < Defs.CLEAN_PLAN then k *= 0.75 end
	if sh.stress > 60 then k *= 0.5 end
	return k
end

local function pickWander(farm, sh)
	local x, y = Defs.randomYard()
	return yardPos(farm, x, y)
end

-- свободный лежак в хлеве
local function restSlot(farm, sh)
	for i = 1, 4 do
		local name = "rest_" .. i
		local taken = farm.slots[name]
		if not taken or taken == sh or not taken.model.Parent then return name end
	end
	return "rest_1"
end

local function stepSheep(farm, sh, dt)
	local root = sh.model.PrimaryPart
	if not root then return end
	local pos = root.Position

	-- потребности, стресс, шерсть
	sh.hunger = math.max(0, sh.hunger - Defs.NEED_DECAY * dt)
	sh.thirst = math.max(0, sh.thirst - Defs.NEED_DECAY * dt)
	local pd = nearestPlayerDist(pos)
	if pd < Defs.STRESS_NEAR and sh.mode ~= "shear" then
		sh.stress = math.min(100, sh.stress + Defs.STRESS_UP * dt)
	else
		sh.stress = math.max(0, sh.stress - Defs.STRESS_DOWN * dt)
	end
	if sh.wool < 100 then
		sh.wool = math.min(100, sh.wool + (100 / Defs.WOOL_FULL_SEC) * growthRate(farm, sh) * dt)
		woolLook(sh)
		-- момент готовности: очередь стрижки — по старшинству, а не по близости
		if sh.wool >= 100 then sh.readyAt = os.clock() end
	end
	sh.defer = math.max(0, sh.defer - dt)
	sh.timer -= dt

	-- испуг: игрок вплотную и стресс высокий — шаг назад (в пределах загона)
	if not sh.busy and pd < Defs.STRESS_NEAR * 0.6 and sh.stress > 70 and (sh.startleCd or 0) <= 0 then
		sh.startleCd = 6
		sheepReact(sh)
		local back = pos - flat(root.CFrame.LookVector).Unit * 2.5
		local lx, ly = Defs.toLocal(farm.fr, back)
		if Defs.walkable(lx, ly) then
			goTo(sh, back, "wander", 0.6)
		end
		sh.timer = 1
		return
	end
	sh.startleCd = math.max(0, (sh.startleCd or 0) - dt)

	local m = sh.mode
	if m == "idle" or m == "graze" then
		sheepClip(sh, m == "graze" and "Graze" or "Idle")
		if sh.timer > 0 then return end
		if farm.sheepIn and not sh.busy then
			-- ночь: в хлев (через проём), если ещё не там
			local lx, ly = Defs.toLocal(farm.fr, pos)
			if Defs.inBarn(lx, ly) then
				local slot = restSlot(farm, sh)
				farm.slots[slot] = sh
				local p = Defs.POINTS[slot]
				goTo(sh, yardPos(farm, p[1], p[2]), "toRest", 0.5)
				return
			elseif not farm.barnClosed then
				local p = Defs.POINTS.barn_out
				goTo(sh, yardPos(farm, p[1], p[2]), "toBarnDoor", 0.9)
				return
			end
		end
		if sh.hunger < Defs.NEED_SEEK and farm.feeder > 0 then
			local slot = freeSlot(farm, "feeder_eat_", sh)
			if slot then
				farm.slots[slot] = sh
				local p = Defs.POINTS[slot]
				goTo(sh, yardPos(farm, p[1], p[2]), "toEat", 0.5)
				return
			end
		end
		if sh.thirst < Defs.NEED_SEEK and farm.trough > 0 and not farm.barnClosed then
			local slot = freeSlot(farm, "trough_drink_", sh)
			if slot then
				farm.slots[slot] = sh
				local p = Defs.POINTS[slot]
				goTo(sh, yardPos(farm, p[1], p[2]), "toDrink", 0.5)
				return
			end
		end
		local r = math.random()
		if r < 0.4 then
			goTo(sh, pickWander(farm, sh), "wander", 0.8)
		elseif r < 0.75 then
			sh.mode = "graze"; sh.timer = 4 + math.random() * 5
		elseif r < 0.87 and not farm.sheepIn then
			-- прилегла отдохнуть прямо во дворе (владелец: «иногда лежат»)
			sh.mode = "rest"; sh.dayRest = true; sh.timer = 15 + math.random() * 15
		else
			sh.mode = "idle"; sh.timer = 1.5 + math.random() * 3
		end

	elseif m == "wander" then
		if moveStep(farm, sh, dt, Defs.SHEEP_WALK) or (sh.blocked or 0) > 0.6 then
			sh.mode = "idle"; sh.timer = 1 + math.random() * 2
			sh.blocked = 0
		end

	elseif m == "toEat" or m == "toDrink" or m == "toRest" or m == "toBarn" or m == "toBarnDoor" or m == "toSpot" then
		local speed = (m == "toSpot") and Defs.SHEEP_FOLLOW or Defs.SHEEP_WALK
		local arrived = moveStep(farm, sh, dt, speed)
		if (sh.blocked or 0) > 2.5 then
			sh.blocked = 0
			releaseSlots(farm, sh)
			sh.mode = "idle"; sh.timer = 1
			return
		end
		if not arrived then return end
		if m == "toEat" then
			local p = Defs.POINTS[freeSlot(farm, "feeder_eat_", sh) or "feeder_eat_1"]
			sh.face = yardPos(farm, p[4], p[5])
			sh.mode = "eat"; sh.timer = Defs.BITE_SEC
		elseif m == "toDrink" then
			local p = Defs.POINTS[freeSlot(farm, "trough_drink_", sh) or "trough_drink_1"]
			sh.face = yardPos(farm, p[4], p[5])
			sh.mode = "drink"; sh.timer = Defs.BITE_SEC
		elseif m == "toBarnDoor" then
			local p = Defs.POINTS.barn_in
			goTo(sh, yardPos(farm, p[1], p[2]), "toBarn", 0.7)
		elseif m == "toBarn" then
			local slot = restSlot(farm, sh)
			farm.slots[slot] = sh
			local p = Defs.POINTS[slot]
			goTo(sh, yardPos(farm, p[1], p[2]), "toRest", 0.5)
		elseif m == "toRest" then
			sh.mode = "rest"; sh.timer = 5
		elseif m == "toSpot" then
			sh.mode = "atSpot"
		end

	elseif m == "eat" or m == "drink" then
		if sh.face then turnTo(sh, sh.face, dt) end
		sheepClip(sh, m == "eat" and "Eat" or "Drink")
		if sh.timer > 0 then return end
		sh.timer = Defs.BITE_SEC
		if m == "eat" then
			if farm.feeder >= Defs.EAT_PORTION and sh.hunger < 92 then
				farm.feeder -= Defs.EAT_PORTION
				sh.hunger = math.min(100, sh.hunger + Defs.EAT_PORTION * Defs.NEED_PER_UNIT)
				refreshVisuals(farm)
				return
			end
		else
			if farm.trough >= Defs.EAT_PORTION and sh.thirst < 92 then
				farm.trough -= Defs.EAT_PORTION
				sh.thirst = math.min(100, sh.thirst + Defs.EAT_PORTION * Defs.NEED_PER_UNIT)
				refreshVisuals(farm)
				return
			end
		end
		releaseSlots(farm, sh)
		sh.mode = "idle"; sh.timer = 1 + math.random() * 2

	elseif m == "rest" then
		sheepClip(sh, "Rest")
		-- дневной отдых во дворе: полежала и встала на месте
		if sh.dayRest then
			if sh.timer <= 0 or farm.sheepIn or sh.busy then
				sh.dayRest = nil
				sh.mode = "idle"; sh.timer = 1
			end
			return
		end
		-- ночью лежит; сильная жажда/голод поднимает её, если двери открыты
		if not farm.sheepIn and sh.timer <= 0 then
			releaseSlots(farm, sh)
			local p = Defs.POINTS.barn_out
			goTo(sh, yardPos(farm, p[1], p[2]), "wander", 0.8)
		elseif farm.sheepIn and not farm.barnClosed and sh.timer <= 0
			and (sh.thirst < Defs.NEED_STOP or sh.hunger < Defs.NEED_STOP) then
			releaseSlots(farm, sh)
			sh.mode = "idle"; sh.timer = 0
		end

	elseif m == "follow" then
		local w = farm.worker and farm.worker:FindFirstChild("HumanoidRootPart", true)
		if not w then sh.mode = "idle"; sh.timer = 1; return end
		local behind = w.Position - flat(w.CFrame.LookVector).Unit * Defs.FOLLOW_GAP
		local d = (flat(behind - pos)).Magnitude
		if d > 1.2 then
			sh.target = behind; sh.arrive = 1.0
			sheepClip(sh, "Walk")
			moveStep(farm, sh, dt, Defs.SHEEP_FOLLOW)
		else
			sheepClip(sh, "Idle")
			turnTo(sh, w.Position, dt)
		end

	elseif m == "look" then
		sheepClip(sh, "Look")
		if sh.face then turnTo(sh, sh.face, dt) end
		if sh.timer <= 0 then sh.mode = "idle"; sh.timer = 0.5 end

	elseif m == "atSpot" then
		sheepClip(sh, "Idle")
		if sh.face then turnTo(sh, sh.face, dt) end

	elseif m == "shear" then
		sheepClip(sh, "Shear")
		if sh.face then turnTo(sh, sh.face, dt) end
	end
end

-- ═══════════ фермер: движение и клипы ═══════════

-- ⚠️ ЦЕЛЬ ПОДТВЕРЖДАЕМ, ПОКА ИДЁТ: Humanoid:MoveTo забывает точку через 8 с.
-- Возвращает true, если дошёл; false — таймаут (нет пути) или задача отменена.
local function walkTo(farm, cf, limit, carrying)
	local model, hum = farm.worker, farm.workerHum
	if not (model and hum) then return false end
	local hrp = model:FindFirstChild("HumanoidRootPart", true)
	if not hrp then return false end
	setClip(model, carrying and "CarryWalk" or "Walk")
	local t0 = os.clock()
	local target = cf.Position
	while os.clock() - t0 < (limit or 20) do
		if farm.abort or not model.Parent or hum.Health <= 0 then return false end
		local d = flat(hrp.Position - target)
		if d.Magnitude < 2.2 then
			hum:MoveTo(hrp.Position)
			-- встал куда просили, лицом куда просили
			local look = cf.LookVector
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat(look).Unit)
			return true
		end
		hum:MoveTo(target)
		task.wait(0.25)
	end
	return false
end

-- разовый клип и ожидание его длины (с досрочным выходом при отмене)
local function act(farm, key, seconds)
	local model = farm.worker
	if not model then return false end
	setClip(model, key, true)
	local left = seconds or Defs.CLIP_LEN[key] or 1
	while left > 0 do
		if farm.abort or not model.Parent then return false end
		local s = math.min(0.1, left)
		task.wait(s)
		left -= s
	end
	return true
end

local function wait_(farm, seconds)
	local left = seconds
	while left > 0 do
		if farm.abort or not (farm.worker and farm.worker.Parent) then return false end
		local s = math.min(0.25, left)
		task.wait(s)
		left -= s
	end
	return true
end

-- взять предмет в руку (клип подбора, захват на GRAB_AT)
local function pickUp(farm, kind)
	local model = farm.worker
	if not model then return false end
	setClip(model, "PickUp", true)
	if not wait_(farm, Defs.GRAB_AT) then return false end
	local prop = PROPS[kind](farm.fr.scale * 0.9, farm)
	--[[ ⚠️ АВТОРСКИЙ ПРОП НЕВИДИМ — ЗНАЧИТ, РАЗМЕР НЕ ТОТ. Владелец: «не вижу
	     сена в руках». Меряем габарит: меньше 0.5 студа или больше 9 — это не
	     связка в руке, а точка или дом; берём заглушку и пишем в Output, что
	     именно взяли и какого размера. ]]
	do
		local _, psize = prop:GetBoundingBox()
		local big = math.max(psize.X, psize.Y, psize.Z)
		local n = 0
		for _, d in ipairs(prop:GetDescendants()) do if d:IsA("BasePart") then n += 1; d.Transparency = 0 end end
		if big < 0.5 or big > 9 or n == 0 then
			warn(("%s %d: проп «%s» %s: габарит %.2f×%.2f×%.2f, деталей %d — беру заглушку")
				:format(LOG, farm.id, kind, prop.Name, psize.X, psize.Y, psize.Z, n))
			prop:Destroy()
			prop = (kind == "hay" or kind == "waste") and PROPS.hayStub(farm.fr.scale * 0.9)
				or (kind == "wool") and PROPS.woolStub(farm.fr.scale * 0.9)
				or PROPS[kind](farm.fr.scale * 0.9, nil)
		else
			print(("%s %d: в руки %s → %s (%.1f×%.1f×%.1f, деталей %d)"):format(LOG, farm.id, kind, prop.Name, psize.X, psize.Y, psize.Z, n))
		end
	end
	local grip = Defs.GRIP[kind] or Defs.GRIP.hay
	if kind == "wool" and prop.Name == Defs.PROP_MODELS.woolCarry.name then
		-- корзина висит под кистью: верх ручки у ладони
		local _, size = prop:GetBoundingBox()
		grip = Defs.GRIP.basket * CFrame.new(0, -size.Y * 0.5, 0)
	end
	holdProp(model, prop, grip)
	farm.held = kind
	if not wait_(farm, Defs.CLIP_LEN.PickUp - Defs.GRAB_AT) then return false end
	setClip(model, "CarryIdle")
	return true
end

local function putDown(farm)
	local model = farm.worker
	if not model then return false end
	setClip(model, "PutDown", true)
	wait_(farm, Defs.RELEASE_AT)
	dropProp(model)
	farm.held = nil
	wait_(farm, Defs.CLIP_LEN.PutDown - Defs.RELEASE_AT)
	setClip(model, "Idle")
	return true
end

-- ═══════════ фермер: задачи ═══════════

local function sheepSide(farm, sh)
	local root = sh.model.PrimaryPart
	local w = farm.worker and farm.worker:FindFirstChild("HumanoidRootPart", true)
	if not root then return nil end
	local gap = 2.4 * math.max(1, farm.fr.scale / 3)
	local right = root.CFrame * CFrame.new(gap, 0, 0)
	local left = root.CFrame * CFrame.new(-gap, 0, 0)
	local pick = right
	if w and (w.Position - left.Position).Magnitude < (w.Position - right.Position).Magnitude then pick = left end
	local lx, ly = Defs.toLocal(farm.fr, pick.Position)
	if not Defs.walkable(lx, ly) then pick = (pick == right) and left or right end
	return CFrame.lookAt(pick.Position, root.Position)
end

local function deferTask(farm, key, why)
	farm.deferred[key] = os.clock() + Defs.RETRY_DELAY
	setStatus(farm, why, true)
	warn(("%s %d: %s — отложено на %d с"):format(LOG, farm.id, why, Defs.RETRY_DELAY))
end

local function isDeferred(farm, key)
	return (farm.deferred[key] or 0) > os.clock()
end

-- возврат груза при отмене: он не исчезает и не удваивается
local function returnCarry(farm)
	local c = farm.carry
	if c then
		if c.kind == "hay" then farm.hay = math.min(Defs.HAY_STORE_CAP, farm.hay + c.amount)
		elseif c.kind == "water" then farm.water = math.min(Defs.WATER_STORE_CAP, farm.water + c.amount)
		elseif c.kind == "wool" then farm.woolWaiting += c.amount end
		farm.carry = nil
	end
	if farm.worker then dropProp(farm.worker) end
	farm.held = nil
	if farm.woolWaiting > 0 and not farm.woolProp then
		local cf = Defs.pointCF(farm.fr, "wool_drop")
		if cf then
			local gy = groundY(farm, cf.Position) or cf.Position.Y
			local prop = PROPS.woolDrop(farm.fr.scale * 0.9, farm)
			local _, psize = prop:GetBoundingBox()
			prop:PivotTo(CFrame.new(cf.Position.X, gy + psize.Y * 0.5, cf.Position.Z) * farm.fr.rot)
			prop.Parent = farm.model
			farm.woolProp = prop
		end
	end
	refreshVisuals(farm)
end

-- ── ВОДА: ведро от бочки к поилке и обратно ──
local function taskWater(farm)
	local need = Defs.TROUGH_CAP - farm.trough
	local take = math.min(Defs.BUCKET_CAP, need, farm.water)
	if take <= 0.5 then return false, "Нет воды в запасе: залей бочку кружкой" end
	if not walkTo(farm, Defs.pointCF(farm.fr, "water_store"), 25) then return false, "Нет пути к бочке" end
	if not pickUp(farm, "bucket") then return false end
	farm.water -= take
	farm.carry = { kind = "water", amount = take }
	local bucket = farm.worker:FindFirstChild("Farm_Bucket", true)
	local wpart = bucket and bucket:FindFirstChild("Water")
	if wpart then wpart.Transparency = 0.2 end
	farm.redraw()
	if not walkTo(farm, Defs.pointCF(farm.fr, "trough_pour"), 25, true) then return false, "Нет пути к поилке" end
	setClip(farm.worker, "PourWater", true)
	if not wait_(farm, Defs.POUR_AT) then return false end
	-- льётся: вода уходит из ведра в поилку ровно один раз
	farm.trough = math.min(Defs.TROUGH_CAP, farm.trough + farm.carry.amount)
	farm.carry = nil
	if wpart then wpart.Transparency = 1 end
	refreshVisuals(farm)
	if not wait_(farm, Defs.CLIP_LEN.PourWater - Defs.POUR_AT) then return false end
	if not walkTo(farm, Defs.pointCF(farm.fr, "water_store"), 25, true) then return false end
	putDown(farm)
	return true
end

-- ── КОРМ: связка сена от тюков к кормушке ──
local function taskFeed(farm)
	local need = Defs.FEEDER_CAP - farm.feeder
	local take = math.min(Defs.HAY_PER_TRIP, need, farm.hay)
	if take <= 0.5 then return false, "Нет сена в запасе: положи листву на тюки" end
	if not walkTo(farm, Defs.pointCF(farm.fr, "hay_store"), 25) then return false, "Нет пути к тюкам" end
	if not pickUp(farm, "hay") then return false end
	farm.hay -= take
	farm.carry = { kind = "hay", amount = take }
	farm.redraw()
	if not walkTo(farm, Defs.pointCF(farm.fr, "feeder_fill"), 25, true) then return false, "Нет пути к кормушке" end
	setClip(farm.worker, "PlaceHay", true)
	if not wait_(farm, 0.6) then return false end
	dropProp(farm.worker); farm.held = nil
	farm.feeder = math.min(Defs.FEEDER_CAP, farm.feeder + farm.carry.amount)
	farm.carry = nil
	refreshVisuals(farm)
	wait_(farm, Defs.CLIP_LEN.PlaceHay - 0.6)
	setClip(farm.worker, "Idle")
	return true
end

-- открыть створки хлева, стоя перед ними
local function openBarn(farm)
	if not farm.barnClosed then return true end
	if not walkTo(farm, Defs.pointCF(farm.fr, "barn_out"), 25, farm.held ~= nil) then return false, "Нет пути к хлеву" end
	act(farm, "OperateDoor")
	setBarn(farm, false, true)
	wait_(farm, Defs.DOOR_SWING_SEC)
	return true
end

-- ── ПОДСТИЛКА: грабли, уборка, вынос, свежее сено ──
local function taskClean(farm)
	if farm.hay < Defs.BEDDING_HAY then return false, "Нет сена на подстилку" end
	if not walkTo(farm, Defs.pointCF(farm.fr, "hay_store"), 25) then return false, "Нет пути к тюкам" end
	if not pickUp(farm, "rake") then return false end
	local ok, why = openBarn(farm)
	if not ok then return false, why end
	if not walkTo(farm, Defs.pointCF(farm.fr, "barn_clean"), 25, true) then return false, "Нет пути в хлев" end
	setClip(farm.worker, "RakeLoop")
	if not wait_(farm, Defs.CLEAN_SEC) then return false end
	-- грязную подстилку — на руки и наружу
	dropProp(farm.worker)
	holdProp(farm.worker, PROPS.waste(farm.fr.scale * 0.9, farm), Defs.GRIP.hay)
	farm.held = "waste"
	if not walkTo(farm, Defs.pointCF(farm.fr, "waste_dump"), 25, true) then return false end
	putDown(farm)
	-- свежее сено
	if not walkTo(farm, Defs.pointCF(farm.fr, "hay_store"), 25) then return false end
	if not pickUp(farm, "hay") then return false end
	local take = math.min(Defs.BEDDING_HAY, farm.hay)
	farm.hay -= take
	farm.carry = { kind = "hay", amount = take }
	if not walkTo(farm, Defs.pointCF(farm.fr, "barn_clean"), 25, true) then return false end
	setClip(farm.worker, "PlaceHay", true)
	if not wait_(farm, 0.6) then return false end
	dropProp(farm.worker); farm.held = nil
	farm.carry = nil
	farm.clean = 100
	wait_(farm, Defs.CLIP_LEN.PlaceHay - 0.6)
	setClip(farm.worker, "Idle")
	return true
end

-- ── ШЕРСТЬ: связку с площадки на склад ──
local function taskCollectWool(farm)
	if farm.wool + farm.woolWaiting > Defs.WOOL_CAP then return false, "Склад шерсти полон: забери шерсть" end
	local dropCF = Defs.pointCF(farm.fr, "wool_drop")
	if not dropCF or not walkTo(farm, CFrame.new(dropCF.Position), 25) then return false, "Нет пути к площадке" end
	if not pickUp(farm, "wool") then return false end
	if farm.woolProp then farm.woolProp:Destroy(); farm.woolProp = nil end
	farm.carry = { kind = "wool", amount = farm.woolWaiting }
	farm.woolWaiting = 0
	if not walkTo(farm, Defs.pointCF(farm.fr, "wool_store"), 25, true) then return false, "Нет пути к складу" end
	setClip(farm.worker, "PutDown", true)
	wait_(farm, Defs.RELEASE_AT)
	dropProp(farm.worker); farm.held = nil
	farm.wool = math.min(Defs.WOOL_CAP, farm.wool + farm.carry.amount)
	farm.carry = nil
	refreshVisuals(farm)
	farm.redraw()
	wait_(farm, Defs.CLIP_LEN.PutDown - Defs.RELEASE_AT)
	setClip(farm.worker, "Idle")
	return true
end

-- ── УСПОКОИТЬ: подойти сбоку, погладить ──
local function taskCalm(farm, sh)
	sh.busy = true
	releaseSlots(farm, sh)
	sh.mode = "look"; sh.timer = 30
	local whrp = farm.worker and farm.worker:FindFirstChild("HumanoidRootPart", true)
	if not whrp then sh.busy = false; sh.mode = "idle"; sh.timer = 1; return false end
	sh.face = whrp.Position
	local side = sheepSide(farm, sh)
	if not side or not walkTo(farm, side, 20) then
		sh.busy = false; sh.mode = "idle"; sh.timer = 1
		return false, "Нет пути к овце"
	end
	faceTo(farm.worker, sheepPos(sh))
	sh.face = whrp.Position
	act(farm, "CalmAnimal")
	sh.stress = math.max(0, sh.stress - Defs.CALM_STRESS)
	sh.busy = false
	sh.mode = "idle"; sh.timer = 2
	return true
end

-- подозвать овцу: она поворачивается, подходит и идёт следом. false — не отозвалась.
local function callSheep(farm, sh)
	sh.dayRest = nil
	sh.mode = "look"; sh.timer = 30
	local whrp = farm.worker and farm.worker:FindFirstChild("HumanoidRootPart", true)
	sh.face = whrp and whrp.Position or sh.face
	act(farm, "CallAnimal")
	sh.mode = "follow"
	return true
end

-- ждать, пока овца держится рядом; при отставании — стоп и повторный зов
local function leadTo(farm, sh, cf)
	local model, hum = farm.worker, farm.workerHum
	local hrp = model:FindFirstChild("HumanoidRootPart", true)
	local t0 = os.clock()
	local calls = 0
	setClip(model, "Walk")
	local speed0 = hum.WalkSpeed
	hum.WalkSpeed = 4.2      -- ведёт шагом: овца идёт 3 студа/с
	local function done(v) hum.WalkSpeed = speed0 return v end
	while os.clock() - t0 < 45 do
		if farm.abort or not model.Parent then return false end
		local d = flat(hrp.Position - cf.Position).Magnitude
		if d < 2.2 then
			hum:MoveTo(hrp.Position)
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat(cf.LookVector).Unit)
			return done(true)
		end
		local gap = (flat(sheepPos(sh) - hrp.Position)).Magnitude
		if gap > Defs.LOST_GAP then
			hum:MoveTo(hrp.Position)
			calls += 1
			if calls > 2 then return done(false) end
			faceTo(model, sheepPos(sh))
			callSheep(farm, sh)
			setClip(model, "Walk")
		else
			hum:MoveTo(cf.Position)
		end
		task.wait(0.25)
	end
	return done(false)
end

-- ── СТРИЖКА ──
local function taskShear(farm, sh)
	sh.busy = true
	releaseSlots(farm, sh)
	farm.shearBusy = true
	local function fail(why)
		sh.busy = false
		sh.mode = "idle"; sh.timer = 1
		farm.shearBusy = false
		sh.fails = (sh.fails or 0) + 1
		if sh.fails >= 2 then sh.defer = Defs.RETRY_DELAY; sh.fails = 0 end
		return false, why
	end
	local side = sheepSide(farm, sh)
	if not side or not walkTo(farm, side, 20) then return fail("Нет пути к овце") end
	faceTo(farm.worker, sheepPos(sh))
	callSheep(farm, sh)
	local spotW = Defs.pointCF(farm.fr, "shear_worker")
	local spotS = Defs.pointCF(farm.fr, "shear_sheep")
	if not leadTo(farm, sh, spotW) then return fail("Овца не идёт за фермером") end
	-- овца — на своё место, фермер ждёт
	local sp = Defs.POINTS.shear_sheep
	sh.face = yardPos(farm, sp[4], sp[5])
	goTo(sh, yardPos(farm, sp[1], sp[2]), "toSpot", 0.6)
	setClip(farm.worker, "Idle")
	local t0 = os.clock()
	while sh.mode ~= "atSpot" do
		if farm.abort or os.clock() - t0 > 25 then return fail("Овца не встала на место") end
		task.wait(0.2)
	end
	faceTo(farm.worker, sheepPos(sh))
	sh.mode = "shear"
	-- ножницы в руку и работа
	holdProp(farm.worker, PROPS.shears(farm.fr.scale * 0.9), Defs.GRIP.shears)
	farm.held = "shears"
	if not act(farm, "ShearEnter") then return fail() end
	setClip(farm.worker, "ShearLoop")
	local loops = math.max(1, math.floor((Defs.SHEAR_SEC - Defs.CLIP_LEN.ShearEnter - Defs.CLIP_LEN.ShearExit) / Defs.CLIP_LEN.ShearLoop + 0.5))
	if not wait_(farm, loops * Defs.CLIP_LEN.ShearLoop) then return fail() end
	-- ⚠️ ВЫДАЧА — ОДНА ЛОГИЧЕСКАЯ ОПЕРАЦИЯ И РОВНО ОДИН РАЗ: пометка, сброс роста,
	-- связка на площадке. Повторные события клиента сюда не ведут вовсе.
	if sh.wool >= 100 and not sh.shearedToken then
		sh.shearedToken = true
		sh.wool = 0
		sh.readyAt = nil
		woolLook(sh)
		farm.woolWaiting += Defs.WOOL_PER_SHEAR
		farm.shearedTotal = (farm.shearedTotal or 0) + 1
		local cf = Defs.pointCF(farm.fr, "wool_drop")
		if cf and not farm.woolProp then
			local gy = groundY(farm, cf.Position) or cf.Position.Y
			local prop = PROPS.woolDrop(farm.fr.scale * 0.9, farm)
			local _, psize = prop:GetBoundingBox()
			prop:PivotTo(CFrame.new(cf.Position.X, gy + psize.Y * 0.5, cf.Position.Z) * farm.fr.rot)
			prop.Parent = farm.model
			farm.woolProp = prop
		end
		sh.shearedToken = nil
	end
	act(farm, "ShearExit")
	dropProp(farm.worker); farm.held = nil
	setClip(farm.worker, "Idle")
	sheepReact(sh)
	sh.busy = false
	sh.fails = 0
	sh.mode = "idle"; sh.timer = 4
	farm.shearBusy = false
	farm.redraw()
	return true
end

-- ── ВЕЧЕР: завести овец в хлев ──
local function taskHerdIn(farm)
	local ok, why = openBarn(farm)
	if not ok then return false, why end
	farm.sheepIn = true
	-- каждую подзываем от двери; идут сами через проём по одной
	local outside = {}
	for _, sh in ipairs(farm.sheep) do
		local lx, ly = Defs.toLocal(farm.fr, sheepPos(sh))
		if not Defs.inBarn(lx, ly) then table.insert(outside, sh) end
	end
	if not walkTo(farm, Defs.pointCF(farm.fr, "barn_out"), 25) then return false, "Нет пути к хлеву" end
	for _, sh in ipairs(outside) do
		if farm.abort then return false end
		if not sh.busy then
			faceTo(farm.worker, sheepPos(sh))
			act(farm, "CallAnimal")
			releaseSlots(farm, sh)
			sh.mode = "idle"; sh.timer = 0   -- решение «ночь → в хлев» примет сама
		end
	end
	-- ждём, пока все войдут (или сдаёмся через 60 с — дверь остаётся открытой)
	local t0 = os.clock()
	setClip(farm.worker, "Idle")
	while os.clock() - t0 < 60 do
		if farm.abort then return false end
		local left = 0
		for _, sh in ipairs(farm.sheep) do
			local lx, ly = Defs.toLocal(farm.fr, sheepPos(sh))
			if not Defs.inBarn(lx, ly) then left += 1 end
		end
		if left == 0 then break end
		task.wait(0.5)
	end
	-- закрыть можно только при пустом проёме
	local t1 = os.clock()
	while os.clock() - t1 < 20 do
		if farm.abort then return false end
		if setBarn(farm, true, true) then
			act(farm, "OperateDoor")
			return true
		end
		task.wait(0.5)
	end
	return false, "Проём хлева занят — дверь не закрыта"
end

-- ── УТРО: выпустить ──
local function taskLetOut(farm)
	farm.sheepIn = false
	local ok, why = openBarn(farm)
	if not ok then return false, why end
	for _, sh in ipairs(farm.sheep) do
		if sh.mode == "rest" then sh.timer = math.random() * 3 end
	end
	-- отойти в сторону
	walkTo(farm, Defs.pointCF(farm.fr, "worker_rest"), 20)
	return true
end

local function taskInspect(farm)
	local cands = {}
	for _, sh in ipairs(farm.sheep) do if not sh.busy then table.insert(cands, sh) end end
	if #cands == 0 then return false end
	local sh = cands[math.random(#cands)]
	local side = sheepSide(farm, sh)
	if not side or not walkTo(farm, side, 20) then return false end
	faceTo(farm.worker, sheepPos(sh))
	act(farm, "InspectAnimal")
	return true
end

-- ═══ выбор задачи по приоритету (ТЗ, раздел 4) ═══
local function pickTask(farm)
	local t = clock()
	local hour = t
	if farm.carry then return { key = "carry" } end

	local troughLow = farm.trough <= Defs.TROUGH_CAP * Defs.REFILL_AT
	local feederLow = farm.feeder <= Defs.FEEDER_CAP * Defs.REFILL_AT
	if troughLow and farm.water > 0.5 and not isDeferred(farm, "water") then return { key = "water" } end
	if feederLow and farm.hay > 0.5 and not isDeferred(farm, "feed") then return { key = "feed" } end

	-- вечер/утро
	local eveningWindow = hour >= Defs.SHEEP_IN_HOUR or hour < Defs.WORK_START
	if #farm.sheep > 0 then
		if eveningWindow and not farm.sheepIn and not isDeferred(farm, "herdIn") then return { key = "herdIn" } end
		if not eveningWindow and farm.sheepIn and hour >= Defs.SHEEP_OUT_HOUR and not isDeferred(farm, "letOut") then return { key = "letOut" } end
		-- ночью кому-то очень нужно к поилке — открыть дверь
		if farm.sheepIn and farm.barnClosed then
			for _, sh in ipairs(farm.sheep) do
				if sh.thirst < Defs.NEED_STOP or sh.hunger < Defs.NEED_STOP then return { key = "openBarn" } end
			end
		end
	end

	if farm.woolWaiting > 0 and farm.wool + farm.woolWaiting <= Defs.WOOL_CAP and not isDeferred(farm, "collect") then
		return { key = "collect" }
	end
	if farm.clean < Defs.CLEAN_URGENT and farm.hay >= Defs.BEDDING_HAY and not isDeferred(farm, "clean") then return { key = "clean" } end

	-- стрижка: самая давно готовая овца
	if not eveningWindow and not farm.shearBusy and farm.woolWaiting == 0 then
		local best
		for _, sh in ipairs(farm.sheep) do
			if sh.wool >= 100 and sh.defer <= 0 and not sh.busy and sh.mode ~= "rest" then
				if not best or (sh.readyAt or 0) < (best.readyAt or 0) then best = sh end
			end
		end
		if best then
			if farm.wool + Defs.WOOL_PER_SHEAR > Defs.WOOL_CAP then
				setStatus(farm, "Склад шерсти полон: забери шерсть, стрижка ждёт", true)
			elseif best.hunger < Defs.SHEAR_NEED_MIN or best.thirst < Defs.SHEAR_NEED_MIN then
				-- голодную не стригут: сперва еда/вода (плановое пополнение ниже)
				setStatus(farm, "Овца готова, но голодна — сначала корм и вода", false)
			elseif best.stress > Defs.SHEAR_STRESS_MAX then
				return { key = "calm", sheep = best }
			else
				return { key = "shear", sheep = best }
			end
		end
	end

	-- планово
	if farm.trough <= Defs.TROUGH_CAP * Defs.PLAN_AT and farm.water > 0.5 and not isDeferred(farm, "water") then return { key = "water" } end
	if farm.feeder <= Defs.FEEDER_CAP * Defs.PLAN_AT and farm.hay > 0.5 and not isDeferred(farm, "feed") then return { key = "feed" } end
	if farm.clean < Defs.CLEAN_PLAN and farm.hay >= Defs.BEDDING_HAY and not isDeferred(farm, "clean") then return { key = "clean" } end

	-- причины простоя
	if troughLow and farm.water <= 0.5 then setStatus(farm, "Нет воды в запасе: залей бочку кружкой", true)
	elseif feederLow and farm.hay <= 0.5 then setStatus(farm, "Нет сена в запасе: положи листву на тюки", true)
	elseif farm.clean < Defs.CLEAN_URGENT and farm.hay < Defs.BEDDING_HAY then setStatus(farm, "Нет сена на подстилку", true)
	end
	return { key = "idle" }
end

local TASK_TIMEOUT = 120   -- секунд на одну задачу фермера, дальше сторож обрывает

local TASK_TEXT = {
	water = "Носит воду", feed = "Носит сено", clean = "Убирает подстилку", collect = "Несёт шерсть на склад",
	shear = "Стрижёт овцу", calm = "Успокаивает овцу", herdIn = "Заводит овец в хлев", letOut = "Выпускает овец",
	openBarn = "Открывает хлев", idle = "Присматривает за стадом", carry = "Возвращает груз",
}

local function runTask(farm, t)
	local ok, why
	if t.key == "carry" then
		-- недоставленный груз после прерывания: вернуть на склад
		returnCarry(farm)
		ok = true
	elseif t.key == "water" then ok, why = taskWater(farm)
	elseif t.key == "feed" then ok, why = taskFeed(farm)
	elseif t.key == "clean" then ok, why = taskClean(farm)
	elseif t.key == "collect" then ok, why = taskCollectWool(farm)
	elseif t.key == "shear" then ok, why = taskShear(farm, t.sheep)
	elseif t.key == "calm" then ok, why = taskCalm(farm, t.sheep)
	elseif t.key == "herdIn" then ok, why = taskHerdIn(farm)
	elseif t.key == "letOut" then ok, why = taskLetOut(farm)
	elseif t.key == "openBarn" then ok, why = openBarn(farm)
	else
		-- присмотреть и подождать на своей точке
		if #farm.sheep > 0 and math.random() < 0.35 then taskInspect(farm) end
		walkTo(farm, Defs.pointCF(farm.fr, "worker_rest"), 20)
		setClip(farm.worker, "Idle")
		wait_(farm, 3)
		ok = true
	end
	if not ok and not farm.abort then
		if why then
			if t.key == "shear" or t.key == "calm" then
				setStatus(farm, why, true)
			else
				deferTask(farm, t.key, why)
			end
		end
		returnCarry(farm)
	end
	return ok
end

-- ═══════════ фермер: смена и жизнь ═══════════

local function farmerRecord(farm)
	if typeof(_G.HouseFarmers) ~= "function" then return nil end
	for _, r in ipairs(_G.HouseFarmers()) do
		if r.farm == farm.id then return r end
	end
	return nil
end

local function despawnWorker(farm, reason)
	farm.abort = true
	returnCarry(farm)
	for _, sh in ipairs(farm.sheep) do
		if sh.busy then sh.busy = false; sh.mode = "idle"; sh.timer = 1 end
	end
	farm.shearBusy = false
	if farm.worker then
		if _G.HouseReleaseSeat then pcall(_G.HouseReleaseSeat, farm.worker) end
		if farm.bed then pcall(farm.bed.release); farm.bed = nil end
		farm.worker:Destroy()
	end
	farm.worker, farm.workerHum, farm.farmerName, farm.farmerId = nil, nil, nil, nil
	farm.away = false
	setStatus(farm, reason or "", reason ~= nil)
	farm.redraw()
end

local function spawnWorker(farm, rec)
	local tpl = findTemplate(Defs.WORKER) or findTemplate(Defs.WORKER .. "_2") or findTemplate(Defs.WORKER .. "_1")
	if not tpl then
		warn(LOG .. " шаблон рабочего " .. Defs.WORKER .. " не найден — фермеру негде взять тело")
		return false
	end
	local model = tpl:Clone()
	model.Name = "Farmer"
	dropForeignTools(model)
	model.Parent = farm.crew
	local start = Defs.pointCF(farm.fr, "gate_out") or CFrame.new(farm.model:GetPivot().Position)
	local hum = prepWorker(model, start)
	if not hum then
		warn(LOG .. " у шаблона рабочего нет Humanoid")
		model:Destroy()
		return false
	end
	-- сквозь ограду и постройки, но по помеченному полу — как рабочие вышки
	local tools = _G.OilRigWorkerTools
	if tools and tools.ensureGroups() then
		local tagged = 0
		for _, name in ipairs(Defs.FLOOR_PARTS) do
			local p = farm.model:FindFirstChild(name, true)
			if p and tools.tagPart(p) then tagged += 1 end
		end
		local _, size = farm.model:GetBoundingBox()
		tagged += tools.tagTilesNear(farm.model:GetPivot().Position, math.max(size.X, size.Z) * 0.5 + 40, { farm.crew })
		if tagged > 0 then tools.ghostWorker(model) end
	end
	farm.worker, farm.workerHum = model, hum
	farm.farmerName, farm.farmerId = rec.name, rec.id
	farm.abort = false
	farm.deferred = {}
	if typeof(_G.HouseBindFarmer) == "function" then pcall(_G.HouseBindFarmer, model, rec.id) end
	hum.Died:Connect(function()
		task.delay(2, function() if farm.worker == model then despawnWorker(farm) end end)
	end)
	setClip(model, "Idle")
	farm.redraw()

	-- поток задач
	task.spawn(function()
		while farm.worker == model and model.Parent and farm.model.Parent do
			if nightNow() then
				-- конец смены: в дом (кровать), нет дома — за ворота и исчезнуть до утра
				if not farm.away then
					farm.away = true
					returnCarry(farm)
					setStatus(farm, "Смена окончена: фермер отдыхает", false)
					local claim = _G.HouseClaimBed and _G.HouseClaimBed(farm.model:GetPivot().Position, model)
					if claim then
						if _G.OilRigWorkerTools then pcall(_G.OilRigWorkerTools.tagRoute, farm.model:GetPivot().Position, claim.house:GetPivot().Position, { farm.crew }) end
						farm.bed = claim
						farm.lastDoor = claim.door
						if claim.door then walkTo(farm, claim.door, 30) end
						if claim.bed then walkTo(farm, claim.bed, 12) end
						local hrp = model:FindFirstChild("HumanoidRootPart", true)
						if hrp then
							hum.PlatformStand = true
							hrp.Anchored = true
							hrp.CFrame = claim.bed
						end
						setClip(model, "SleepEnter", true)
						wait_(farm, 1.33)
						setClip(model, "Sleep")
					else
						walkTo(farm, Defs.pointCF(farm.fr, "gate_out"), 25)
						hideWorker(model, true)
						farm.hidden = true
					end
				end
				task.wait(1)
			else
				if farm.away then
					farm.away = false
					if farm.bed then
						setClip(model, "SleepExit", true)
						wait_(farm, 1.53)
						local hrp = model:FindFirstChild("HumanoidRootPart", true)
						if hrp then hrp.Anchored = false end
						hum.PlatformStand = false
						pcall(farm.bed.release)
						farm.bed = nil
					elseif farm.hidden then
						hideWorker(model, false)
						farm.hidden = false
					end
					setStatus(farm, "Начало смены", false)
				end
				local t = pickTask(farm)
				farm.task = t
				if t.key ~= "idle" then setStatus(farm, TASK_TEXT[t.key] or t.key, false) end
				--[[ ⚠️ СТОРОЖ: задача не может идти дольше TASK_TIMEOUT. Фермер однажды
				     замер на «носит воду» навсегда (владелец: «должен быть занят
				     всегда»). Задача крутится в своём потоке; не уложилась — обрываем
				     через abort, возвращаем груз и берём следующую. ]]
				local done, okRun, errRun = false, true, nil
				local t0 = os.clock()
				task.spawn(function()
					okRun, errRun = pcall(runTask, farm, t)
					done = true
				end)
				while not done do
					task.wait(0.5)
					if farm.worker ~= model or not model.Parent then break end
					if os.clock() - t0 > TASK_TIMEOUT then
						warn(("%s %d: задача «%s» висит %d с — обрываю"):format(LOG, farm.id, tostring(t.key), TASK_TIMEOUT))
						farm.abort = true
						local w0 = os.clock()
						while not done and os.clock() - w0 < 3 do task.wait(0.25) end
						if farm.worker == model then farm.abort = false end
						returnCarry(farm)
						setStatus(farm, "Задача сорвалась: " .. tostring(TASK_TEXT[t.key] or t.key), true)
						break
					end
				end
				if done and not okRun then warn(LOG .. " задача " .. tostring(t.key) .. " упала: " .. tostring(errRun)); returnCarry(farm) end
				farm.task = nil
				task.wait(0.3)
			end
		end
	end)
	print(("%s %d: фермер %s вышел на работу"):format(LOG, farm.id, rec.name))
	return true
end

-- ═══════════ жизнь фермы ═══════════

local function tickFarm(farm, dt)
	if not farm.model.Parent then return end
	for i = #farm.sheep, 1, -1 do
		local sh = farm.sheep[i]
		if not sh.model.Parent then
			table.remove(farm.sheep, i)
		else
			local ok, err = pcall(stepSheep, farm, sh, dt)
			if not ok then warn(LOG .. " овца " .. sh.id .. ": " .. tostring(err)) end
		end
	end
	farm.clean = math.max(0, farm.clean - Defs.CLEAN_DECAY * dt)
end

local function runFarm(farm)
	-- физика овец — каждый кадр
	farm.hbConn = game:GetService("RunService").Heartbeat:Connect(function(dt)
		if not farm.model.Parent then
			farm.hbConn:Disconnect()
			return
		end
		tickFarm(farm, math.min(dt, 0.1))
	end)

	-- раз в секунду: фермер из дома, доход, вывеска
	task.spawn(function()
		local lastPaidDay = farm.paidDay
		while farm.model.Parent do
			task.wait(1)
			local rec = farmerRecord(farm)
			if rec and not farm.worker then
				spawnWorker(farm, rec)
			elseif not rec and farm.worker then
				despawnWorker(farm, "Фермер уволен: назначь нового в доме")
			elseif rec and farm.worker and rec.id ~= farm.farmerId then
				despawnWorker(farm)
			end
			-- ⚠️ ДОХОД РОВНО РАЗ В ДЕНЬ, В 23:00, И ТОЛЬКО С ФЕРМЕРОМ.
			local day = typeof(_G.GetDayCount) == "function" and _G.GetDayCount() or 0
			if rec and clock() >= Defs.PAY_HOUR and clock() < Defs.PAY_HOUR + 0.9 and lastPaidDay ~= day then
				lastPaidDay = day
				farm.paidDay = day
				local owner = farm.owner
				if owner and owner.Parent and typeof(_G.AddPirate) == "function" then
					if typeof(_G.PassiveIncomeAdd) == "function" then
						_G.PassiveIncomeAdd(owner, Defs.DAILY_PIRATES, 0)   -- выдастся на границе часа
					else
						pcall(_G.AddPirate, owner, Defs.DAILY_PIRATES)
					end
					notify(owner, { type = "success", icon = "coin", title = _G.FarmNameOf(farm.id),
						body = ("Дневной доход: +%d пиратов"):format(Defs.DAILY_PIRATES) })
					print(("%s %d: выплачено %d пиратов игроку %s"):format(LOG, farm.id, Defs.DAILY_PIRATES, owner.Name))
				end
			end
			if farm.redraw then farm.redraw() end
		end
		despawnWorker(farm)
		for _, sh in ipairs(farm.sheep) do sh.model:Destroy() end
	end)
end

local function registerFarm(model, owner, rec)
	local fr = Defs.frame(model)
	local farm = {
		model = model, owner = owner, id = (rec and tonumber(rec.id)) or nextId, fr = fr,
		hay = (rec and tonumber(rec.hay)) or Defs.HAY_START,
		water = (rec and tonumber(rec.water)) or Defs.WATER_START,
		wool = (rec and tonumber(rec.wool)) or 0,
		feeder = (rec and tonumber(rec.feeder)) or Defs.FEEDER_CAP * 0.5,
		trough = (rec and tonumber(rec.trough)) or Defs.TROUGH_CAP * 0.5,
		clean = (rec and tonumber(rec.clean)) or 100,
		woolWaiting = (rec and tonumber(rec.woolWaiting)) or 0,
		sheep = {}, slots = {}, deferred = {}, carry = nil, sheepIn = false, barnClosed = false,
		paidDay = rec and tonumber(rec.paidDay) or nil,
	}
	if farm.id >= nextId then nextId = farm.id + 1 end
	farm.crew = Instance.new("Folder")
	farm.crew.Name = "Rebels"    -- эту папку анимирует клиентский проигрыватель поз
	farm.crew.Parent = model
	model:SetAttribute("FarmId", farm.id)
	--[[ ⚠️ КАЖДЫЙ ШАГ СБОРКИ — В pcall. Ошибка в одном (например, в разборе
	     новой модели) раньше роняла всю регистрацию: ферма стояла в мире, но в
	     реестре её не было, и дом отвечал «сначала построй ферму» (владелец). ]]
	local function step(name, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then warn(("%s %d: шаг «%s» упал: %s"):format(LOG, farm.id, name, tostring(err))) end
	end
	step("двери", setupDoors, farm)
	step("ворота", doorPrompt, farm, "Gate", "Ворота")
	step("дверь хлева", doorPrompt, farm, "Barn_Door_Left", "Дверь хлева")
	step("вывеска", infoBoard, farm)
	step("склады", setupStores, farm)
	step("овцы", spawnSheep, farm, rec and rec.sheep)
	step("визуал", refreshVisuals, farm)
	farm.redraw = farm.redraw or function() end
	farm.doors = farm.doors or {}
	-- ночью восстановленная ферма: овцы сразу в хлеве, дверь закрыта
	if nightNow() or clock() >= Defs.SHEEP_IN_HOUR then
		farm.sheepIn = true
		for i, sh in ipairs(farm.sheep) do
			local slot = "rest_" .. i
			farm.slots[slot] = sh
			local p = Defs.POINTS[slot]
			local pos = yardPos(farm, p[1], p[2])
			sh.model:PivotTo(CFrame.new(pos.X, pos.Y + sh.foot, pos.Z))
			sh.mode = "rest"; sh.timer = 5
		end
		setBarn(farm, true, false)
	end
	table.insert(farms, farm)
	print(("%s %d: масштаб %.2f, точек %d, дверей %d"):format(LOG, farm.id, fr.scale,
		(function() local n = 0 for _ in pairs(Defs.POINTS) do n += 1 end return n end)(),
		(function() local n = 0 for _ in pairs(farm.doors) do n += 1 end return n end)()))
	runFarm(farm)
	return farm
end

-- ═══════════ назначение фермера ═══════════

-- Свободная ферма, ближайшая к дому. nil + причина, если нет.
_G.FarmAssign = function(residentId, fromPos)
	local taken = {}
	if typeof(_G.HouseFarmers) == "function" then
		for _, r in ipairs(_G.HouseFarmers()) do
			if r.farm and r.id ~= residentId then taken[r.farm] = true end
		end
	end
	local best, bestD, any = nil, math.huge, false
	for _, f in ipairs(farms) do
		if f.model.Parent then
			any = true
			if not taken[f.id] then
				local d = fromPos and (f.model:GetPivot().Position - fromPos).Magnitude or 0
				if d < bestD then best, bestD = f, d end
			end
		end
	end
	if not any then return nil, "Сначала построй ферму молотком" end
	if not best then return nil, "Все фермы заняты: одна ферма — один фермер" end
	return best.id
end

_G.FarmRelease = function(residentId)
	for _, f in ipairs(farms) do
		if f.farmerId == residentId then
			despawnWorker(f, "Фермер ушёл: назначь нового в доме")
		end
	end
end

-- После загрузки: у каждого фермера ферма должна существовать и быть одна на
-- жителя. Ферма исчезла — житель без работы; двое на одну — второй без работы.
_G.FarmReconcile = function()
	if typeof(_G.HouseFarmers) ~= "function" then return end
	local seen = {}
	for _, r in ipairs(_G.HouseFarmers()) do
		local f = r.farm and farmById(r.farm)
		if not f then
			local fid = _G.FarmAssign(r.id, r.house and r.house:GetPivot().Position)
			if fid then
				_G.HouseSetFarm(r.id, fid)
				seen[fid] = r.id
			else
				warn(("%s фермер %s остался без фермы — снимаю профессию"):format(LOG, r.name))
				_G.HouseSetFarm(r.id, nil)
			end
		elseif seen[f.id] and seen[f.id] ~= r.id then
			warn(("%s на ферму %d претендуют двое — %s без работы"):format(LOG, f.id, r.name))
			_G.HouseSetFarm(r.id, nil)
		else
			seen[f.id] = r.id
		end
	end
end

-- ═══════════ постановка ═══════════

placeEvent.OnServerEvent:Connect(function(player, cf)
	if typeof(cf) ~= "CFrame" then return end
	local tpl = (findTemplate(Defs.MODEL) or findTemplate(Defs.MODEL_ALT))
	if not tpl then
		warn(LOG .. " шаблон «" .. Defs.MODEL .. "» не найден в ReplicatedStorage/Workspace")
		placeEvent:FireClient(player, "denied", "модель фермы не найдена")
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - cf.Position).Magnitude > 80 then return end
	if type(_G.OilRigSpotOK) ~= "function" then
		placeEvent:FireClient(player, "denied", "проверка места ещё не готова, попробуй через секунду")
		return
	end
	-- вся площадь фермы, включая ограду и фонари — это габарит модели целиком
	local _, size = tpl:GetBoundingBox()
	local ok, why = _G.OilRigSpotOK(cf, size, { char }, Defs.FLAT_TOL)
	if not ok then
		placeEvent:FireClient(player, "denied", why)
		return
	end
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
	local inv = (typeof(_G.GetInventory) == "function" and _G.GetInventory(player)) or {}
	-- админ строит бесплатно (флаг DevLogs ставит сервер: DevLogFlag)
	local freeBuild = player:GetAttribute("DevLogs") == true
	if not freeBuild and (inv[Defs.COST_TYPE] or 0) < Defs.COST then
		placeEvent:FireClient(player, "denied",
			string.format("нужно %d брёвен, есть %d", Defs.COST, inv[Defs.COST_TYPE] or 0))
		return
	end
	if not freeBuild and typeof(_G.RemoveResourceFromInventory) == "function" then
		_G.RemoveResourceFromInventory(player, Defs.COST_TYPE, Defs.COST)
		if typeof(_G.SendInventory) == "function" then _G.SendInventory(player) end
	end

	local model = tpl:Clone()
	model.Name = Defs.MODEL
	pcall(function() model:PivotTo(cf) end)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	if typeof(_G.OilRigClearDecor) == "function" then pcall(_G.OilRigClearDecor, cf, size) end
	model.Parent = Workspace
	do local isle = islandAt(cf.Position); if isle then isle:SetAttribute("KeepAlive", true) end end
	local farm = registerFarm(model, player, nil)
	placeEvent:FireClient(player, "placed")
	print(("%s построена (№%d), сено %d, вода %d"):format(LOG, farm.id, farm.hay, farm.water))
end)

-- ═══════════ сейв ═══════════

_G.FarmExport = function()
	local out = {}
	for _, f in ipairs(farms) do
		if f.model.Parent then
			local sheep = {}
			for _, sh in ipairs(f.sheep) do
				table.insert(sheep, { wool = sh.wool, hunger = sh.hunger, thirst = sh.thirst, stress = sh.stress })
			end
			-- груз в руках и связка на площадке — обратно в учёт: после загрузки
			-- временных резервов нет
			local hay, water, waiting = f.hay, f.water, f.woolWaiting
			if f.carry then
				if f.carry.kind == "hay" then hay += f.carry.amount
				elseif f.carry.kind == "water" then water += f.carry.amount
				elseif f.carry.kind == "wool" then waiting += f.carry.amount end
			end
			table.insert(out, { cf = f.model:GetPivot(), id = f.id, hay = hay, water = water, wool = f.wool,
				feeder = f.feeder, trough = f.trough, clean = f.clean, woolWaiting = waiting, sheep = sheep, paidDay = f.paidDay })
		end
	end
	return out
end

_G.FarmRestore = function(cf, rec, player)
	local tpl = (findTemplate(Defs.MODEL) or findTemplate(Defs.MODEL_ALT))
	if not tpl then return nil end
	local model = tpl:Clone()
	model.Name = Defs.MODEL
	pcall(function() model:PivotTo(cf) end)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	model.Parent = Workspace
	local farm = registerFarm(model, player, rec)
	print(("%s восстановлена из сейва: №%d, шерсти на складе %d"):format(LOG, farm.id, farm.wool))
	return model
end

-- ферма могла стоять в плейсе руками
for _, d in ipairs(Workspace:GetChildren()) do
	if d:IsA("Model") and (d.Name == Defs.MODEL or d.Name == Defs.MODEL_ALT) then
		registerFarm(d, nil, nil)
		print(LOG .. " найдена уже стоящая ферма в Workspace")
	end
end

print(LOG .. " готова: ставится молотком на сушу острова; фермер назначается в доме")
