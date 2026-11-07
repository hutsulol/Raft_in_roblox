--[[
	ДОМ: постановка на остров и две кровати для жителей.

	Ставится молотком на сушу, как нефтевышка, и дальше живёт сам: топится очаг,
	горит фонарь, а рабочие с вышки приходят сюда спать (см. OilRigSystem — он
	спрашивает свободную кровать через _G.HouseClaimBed).

	⚠️ ПРОВЕРКУ МЕСТА НЕ ДУБЛИРУЕМ.
	Ровно те же три условия — суша, ровно, свободно — уже написаны в
	OilRigSystem и выставлены как _G.OilRigSpotOK. Своя копия допусков
	разъехалась бы с оригиналом при первой правке, а игрок увидел бы, что призрак
	зелёный у дома и красный у вышки на одном и том же пятачке.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Defs      = require(ReplicatedStorage:WaitForChild("HouseDefs"))
local Flame     = require(ReplicatedStorage:WaitForChild("FlamethrowerDefs"))
local SignFace  = require(ReplicatedStorage:WaitForChild("SignFace"))
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

local LOG = "[Дом]"

-- Цена постройки дома. ⚠️ ТА ЖЕ ЦИФРА СТОИТ В МЕНЮ МОЛОТКА
-- (StarterPlayerScripts/BuildingSystem.client.lua, пункт дома): клиент её только
-- рисует, а списывает сервер здесь. Меняешь — меняй в обоих местах.
local HOUSE_COST_RES = "Log"
local HOUSE_COST = 20
local placeEvent = ReplicatedStorage:FindFirstChild("HousePlace")
if not placeEvent then
	placeEvent = Instance.new("RemoteEvent")
	placeEvent.Name = "HousePlace"
	placeEvent.Parent = ReplicatedStorage
end

local function findTemplate(name)
	-- в хранилище — по имени, а не по месту: модели разложены по папкам (см. AssetFind)
	local m = AssetFind.find(name)
	if m then return m end
	m = Workspace:FindFirstChild(name)
	if m then return m end
	return nil
end

local function markerCF(house, name)
	local m = house:FindFirstChild(name, true)
	if m and m:IsA("BasePart") then return m.CFrame end
	if m and m:IsA("Attachment") then return m.WorldCFrame end
	local off = Defs.FALLBACK[name]
	if off then return house:GetPivot() * CFrame.new(off) end
	return nil
end

-- Маркеры — оранжевые кубики, в игре их видеть не должны (README: «в финале
-- удаляются»). Не удаляем сами: пригодятся, если захочешь подвинуть точки.
local function hideMarkers(house)
	for _, d in ipairs(house:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name:sub(1, 3) == "wp_" or d.Name:sub(1, 3) == "fx_") then
			d.Transparency = 1
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

-- ═══════════ очаг и фонарь ═══════════

local function hearthFx(house)
	local host = house:FindFirstChild(Defs.FX.hearth, true)
	if not host or not host:IsA("BasePart") then return end

	local fire = Instance.new("ParticleEmitter")
	fire.Name = "HearthFire"
	fire.Texture = Flame.flameTexture()
	fire.Rate = 14
	fire.Lifetime = NumberRange.new(0.5, 0.9)
	fire.Speed = NumberRange.new(1.4, 2.6)
	fire.SpreadAngle = Vector2.new(12, 12)
	fire.EmissionDirection = Enum.NormalId.Top
	fire.Size = NumberSequence.new(1.1, 0.25)
	fire.Transparency = NumberSequence.new(0.15, 1)
	fire.LightEmission = 1
	fire.LightInfluence = 0
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 190, 90), Color3.fromRGB(220, 90, 40))
	fire.Parent = host

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "HearthSmoke"
	smoke.Texture = Flame.smokeTexture()
	smoke.Rate = 4
	smoke.Lifetime = NumberRange.new(1.4, 2.2)
	smoke.Speed = NumberRange.new(1, 1.8)
	smoke.SpreadAngle = Vector2.new(10, 10)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Size = NumberSequence.new(0.6, 2.2)
	smoke.Transparency = NumberSequence.new(0.6, 1)
	smoke.LightInfluence = 1
	smoke.Parent = host

	local light = Instance.new("PointLight")
	light.Name = "HearthLight"
	light.Color = Color3.fromRGB(255, 150, 70)
	light.Brightness = 1.6
	light.Range = 14
	light.Shadows = false
	light.Parent = host
end

local function lampFx(house)
	local host = house:FindFirstChild(Defs.FX.lamp, true)
	if not host or not host:IsA("BasePart") then return end
	local light = Instance.new("PointLight")
	light.Name = "LampLight"
	light.Color = Color3.fromRGB(255, 214, 150)
	light.Brightness = 0.9
	light.Range = 11
	light.Shadows = false
	light.Parent = host
end

-- ═══════════ поза на кровати ═══════════

-- ⚠️ УГОЛ БЕРЁМ ИЗ ГЕОМЕТРИИ КРОВАТИ, А НЕ ИЗ ПОВОРОТА МАРКЕРА.
-- Дом ставится в любую из четырёх сторон, и константный доворот (BED_TURN) верен
-- ровно для одной из них — отсюда и спящие поперёк матраса. Сама кровать про
-- себя всё знает: её длинная горизонтальная сторона и есть направление
-- «голова-ноги», а маркер по README сдвинут от центра К ИЗГОЛОВЬЮ — значит
-- вектор от центра кровати к маркеру показывает, где голова. Всё это считается
-- в мировых координатах и потому верно при любом повороте дома.
local BED_PARTS = { [Defs.WP.bedA] = "house_bed_a", [Defs.WP.bedB] = "house_bed_b" }

-- Модель жителя по номеру строки на табличке — нужна портрету. Пишет её сюда
-- сама система, когда житель получает тело; пока тела нет, вернётся nil и в
-- кружке останется инициал.
local residentModels = {}      -- [дом] = { [номер] = Model }
function residentModel(house, i)
	local byHouse = residentModels[house]
	local m = byHouse and byHouse[i]
	return (m and m.Parent) and m or nil
end

_G.HouseBindResidentModel = function(house, index, model)
	residentModels[house] = residentModels[house] or {}
	residentModels[house][index] = model
end

local function lieCF(house, markerName)
	local cf = markerCF(house, markerName)
	if not cf then return nil end

	local bed = house:FindFirstChild(BED_PARTS[markerName] or "", true)
	if not (bed and bed:IsA("BasePart")) then
		-- кровати как отдельной детали нет — остаётся довериться маркеру
		return cf * Defs.BED_TURN
	end

	local toHead = cf.Position - bed.Position
	toHead = Vector3.new(toHead.X, 0, toHead.Z)
	if toHead.Magnitude < 0.15 then
		-- маркер ровно по центру: берём длинную горизонтальную сторону кровати
		local s = bed.Size
		local axis = (s.X >= s.Z) and bed.CFrame.RightVector or bed.CFrame.LookVector
		toHead = Vector3.new(axis.X, 0, axis.Z)
	end
	if toHead.Magnitude < 0.01 then return cf * Defs.BED_TURN end
	toHead = toHead.Unit

	-- ⚠️ ЛИЦОМ К НОГАМ, А НЕ К ИЗГОЛОВЬЮ.
	-- Тело кладёт поворот торса назад (клип House_Sleep), и голова уезжает ПРОТИВ
	-- направления взгляда. Значит смотреть корень должен в сторону ног, тогда
	-- голова ляжет на подушку.
	return CFrame.lookAt(cf.Position, cf.Position - toHead)
end

-- ═══════════ табличка с жителями ═══════════

-- ⚠️ ЖИТЕЛИ ЖИВУТ В АТРИБУТАХ ДОМА, А НЕ В ТЕКСТЕ НАДПИСИ.
-- Табличку рисует сервер, а окно «Управление» открывает клиент — и оба должны
-- читать одно и то же. Разбирать текст с надписи обратно в данные было бы вторым
-- источником правды, который разъедется при первой правке вёрстки.
local function writeResidents(house, list)
	house:SetAttribute("ResidentCount", #list)
	for i = 1, Defs.CAPACITY do
		local r = list[i]
		house:SetAttribute("Res" .. i .. "Name",  r and r.name or nil)
		house:SetAttribute("Res" .. i .. "Role",  r and Defs.jobById(r.job).name or nil)
		house:SetAttribute("Res" .. i .. "Stars", r and r.stars or nil)
	end
end

local function infoBoard(house)
	local part
	for _, name in ipairs(Defs.INFO_NAMES) do
		local p = house:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then part = p break end
	end
	if not part then
		warn(LOG .. " деталь таблички (" .. table.concat(Defs.INFO_NAMES, ", ")
			.. ") в модели не найдена — жителей показывать негде")
		return
	end

	local old = part:FindFirstChild("HouseInfo")
	if old then old:Destroy() end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "HouseInfo"
	gui.Face = SignFace.of(part, house)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Active = true            -- иначе кнопка на поверхности не нажимается
	gui.Parent = part

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Defs.UI.BACK
	back.BorderSizePixel = 0
	back.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10); pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = back

	local col = Instance.new("UIListLayout")
	col.FillDirection = Enum.FillDirection.Vertical
	col.SortOrder = Enum.SortOrder.LayoutOrder
	col.HorizontalAlignment = Enum.HorizontalAlignment.Center
	col.Padding = UDim.new(0, 6)
	col.Parent = back

	-- ⚠️ НА ТАБЛИЧКЕ НЕТ КНОПКИ — ТОЛЬКО ЖИТЕЛИ.
	-- Кнопка на SurfaceGui в мире нажимается только при прямой видимости детали, а
	-- табличка висит над крышей: попасть по ней курсором нельзя в принципе. Меню
	-- открывает ProximityPrompt у двери, значит место кнопки лучше отдать самим
	-- жителям — они и есть то, ради чего на табличку смотрят.
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.LayoutOrder = 1
	rows.BackgroundTransparency = 1
	rows.Size = UDim2.fromScale(1, 1)      -- вся площадь таблички
	rows.Parent = back
	local rowsCol = Instance.new("UIListLayout")
	rowsCol.FillDirection = Enum.FillDirection.Vertical
	rowsCol.SortOrder = Enum.SortOrder.LayoutOrder
	rowsCol.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowsCol.VerticalAlignment = Enum.VerticalAlignment.Center
	rowsCol.Padding = UDim.new(0, 6)
	rowsCol.Parent = rows

	-- ⚠️ ВЫСОТА СТРОКИ СЧИТАЕТСЯ ОТ ЧИСЛА ЖИТЕЛЕЙ, А НЕ ЗАДАНА ЧИСЛОМ.
	-- Двое занимают табличку пополам, трое — по трети; при фиксированных 56 px
	-- один житель болтался бы в пустоте, а четвёртый не влез бы вовсе.
	local function rowHeight(count)
		return 1 / math.max(count, 1)
	end

	local function row(order, count, name, role, stars, model)
		local rank = Defs.RANKS[math.clamp(stars or 1, 1, 3)]

		local frame = Instance.new("Frame")
		frame.LayoutOrder = order
		-- высота — доля таблички; отступ между строками вычитаем из своей доли
		frame.Size = UDim2.new(1, 0, rowHeight(count), -6)
		frame.BackgroundColor3 = Defs.UI.ROW
		frame.BorderSizePixel = 0
		frame.Parent = rows
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = frame
		local s = Instance.new("UIStroke"); s.Thickness = 2
		s.Color = Color3.fromRGB(8, 14, 22); s.Parent = frame

		-- ⚠️ В КРУЖКЕ ЛИЦО, А НЕ БУКВА.
		-- Картинки у этих NPC нет — они собраны из мешей, — поэтому берём их
		-- НАСТОЯЩУЮ голову во ViewportFrame. Тот же приём, что у портретов NPC в
		-- окне диалогов. Модели нет (житель ещё не вышел из дома) — остаётся
		-- инициал, чтобы строка не зияла пустотой.
		local dot = Instance.new("Frame")
		dot.Name = "Face"
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 8, 0.5, 0)
		dot.Size = UDim2.new(0, 0, 0.72, 0)
		dot.SizeConstraint = Enum.SizeConstraint.RelativeYY
		dot.BackgroundColor3 = rank.ring
		dot.BorderSizePixel = 0
		dot.ClipsDescendants = true
		dot.Parent = frame
		local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = dot

		local head = model and (model:FindFirstChild("Head", true))
		if head and head:IsA("BasePart") then
			local vp = Instance.new("ViewportFrame")
			vp.Size = UDim2.fromScale(1, 1)
			vp.BackgroundTransparency = 1
			vp.Parent = dot
			local clone = head:Clone()
			clone.Anchored = true
			clone.Parent = vp
			-- голову тянем вместе с её лицом и аксессуарами, иначе выйдет болванка
			for _, extra in ipairs(head:GetChildren()) do
				if extra:IsA("Decal") or extra:IsA("SpecialMesh") then
					local e = extra:Clone(); e.Parent = clone
				end
			end
			local cam = Instance.new("Camera")
			cam.CFrame = CFrame.lookAt(
				clone.Position + clone.CFrame.LookVector * 2.1 + Vector3.new(0, 0.15, 0),
				clone.Position)
			cam.Parent = vp
			vp.CurrentCamera = cam
		else
			local letter = Instance.new("TextLabel")
			letter.Size = UDim2.fromScale(1, 1)
			letter.BackgroundTransparency = 1
			letter.Font = Enum.Font.GothamBlack
			letter.TextScaled = true
			letter.TextColor3 = Color3.fromRGB(30, 24, 12)
			letter.Text = name:sub(1, utf8.offset(name, 2) - 1)
			letter.Parent = dot
		end

		local title = Instance.new("TextLabel")
		title.AnchorPoint = Vector2.new(0, 0)
		title.Position = UDim2.new(0, 58, 0, 8)
		title.Size = UDim2.new(1, -160, 0, 22)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.TextSize = 18
		title.TextColor3 = Defs.UI.TITLE
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = ("%s %s"):format(name, string.rep("★", math.clamp(stars or 1, 1, 3)))
		title.Parent = frame

		local sub = Instance.new("TextLabel")
		sub.Position = UDim2.new(0, 58, 0, 30)
		sub.Size = UDim2.new(1, -160, 0, 18)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.GothamBold
		sub.TextSize = 15
		sub.TextColor3 = Defs.UI.ROLE
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.Text = role or Defs.ROLE_OIL
		sub.Parent = frame

		local badge = Instance.new("TextLabel")
		badge.AnchorPoint = Vector2.new(1, 0.5)
		badge.Position = UDim2.new(1, -8, 0.5, 0)
		badge.Size = UDim2.fromOffset(92, 26)
		badge.BackgroundColor3 = rank.bg
		badge.BorderSizePixel = 0
		badge.Font = Enum.Font.GothamBold
		badge.TextSize = 14
		badge.TextColor3 = rank.fg
		badge.Text = rank.label
		badge.Parent = frame
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = badge
	end

	local function redraw()
		for _, child in ipairs(rows:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		local count = house:GetAttribute("ResidentCount") or 0
		local shown = math.max(count, 1)
		for i = 1, Defs.CAPACITY do
			local name = house:GetAttribute("Res" .. i .. "Name")
			if name then
				row(i, shown, name,
					house:GetAttribute("Res" .. i .. "Role"),
					house:GetAttribute("Res" .. i .. "Stars"),
					residentModel and residentModel(house, i) or nil)
			end
		end
		if count == 0 then
			local empty = Instance.new("TextLabel")
			empty.LayoutOrder = 1
			empty.Size = UDim2.new(1, 0, 0, 56)
			empty.BackgroundTransparency = 1
			empty.Font = Enum.Font.GothamBold
			empty.TextSize = 17
			empty.TextColor3 = Defs.UI.EMPTY
			empty.Text = ("Свободно мест: %d"):format(Defs.CAPACITY)
			empty.Parent = rows
		end
	end

	house:GetAttributeChangedSignal("ResidentCount"):Connect(redraw)
	redraw()

	-- ⚠️ ОТКРЫВАЕТ ПОДСКАЗКА, А НЕ КНОПКА НА ПОВЕРХНОСТИ.
	-- Клик по SurfaceGui в мире работает через раз: нужен и Active, и чистая
	-- линия взгляда до детали, а табличка висит над крышей — попасть по ней
	-- курсором с земли нельзя вовсе. В хендофе меню и открывается по
	-- ProximityPrompt, поэтому вешаем его на ДВЕРЬ: игрок к ней и подходит.
	-- Жёлтая кнопка остаётся как указатель «здесь есть что открыть».
	local door = house:FindFirstChild("house_door", true)
		or house:FindFirstChild(Defs.WP.door, true) or part
	if door:IsA("BasePart") then
		local old2 = door:FindFirstChild("HouseManagePrompt")
		if old2 then old2:Destroy() end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "HouseManagePrompt"
		prompt.ActionText = "Управление"
		prompt.ObjectText = Defs.NAME_RU
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 16
		prompt.RequiresLineOfSight = false   -- дверь притоплена в стену, луч в неё не всегда доходит
		prompt.Parent = door
	end
end

-- ═══════════ учёт кроватей ═══════════

-- ⚠️ КРОВАТЬ ВЫДАЁТСЯ ОДНА НА ОДНОГО.
-- Двое рабочих приходят одновременно, и без пометки «занято» оба лягут на одну
-- кровать — тела совпадут точь-в-точь, потому что позу задаёт маркер.
local houses = {}   -- { model, beds = { [маркер] = занявший }, residents = {…} }

local function registerHouse(model)
	local h = {
		model = model,
		level = model:GetAttribute("HouseLevel") or Defs.LEVEL,
		capacity = model:GetAttribute("HouseCapacity") or Defs.CAPACITY,
		beds = { [Defs.WP.bedA] = false, [Defs.WP.bedB] = false },
		residents = {},          -- список { id, name, type, age, years, stars, job }
	}
	table.insert(houses, h)
	writeResidents(model, h.residents)
	infoBoard(model)
	return h
end

-- ⚠️ ЖИТЕЛЬ — ЭТО ДАННЫЕ, А НЕ НПС НА ВЫШКЕ.
-- Заселяет его игрок кнопкой «Добавить жителя», платя одним жителем из общего
-- населения. Рабочие на вышке — лишь ВИДИМОЕ следствие того, что кому-то из
-- жильцов назначена профессия «Нефтяник»: нет дома или нет нефтяника — вышка
-- стоит. Поэтому список живёт здесь, а не собирается из моделей рабочих.
local nameCursor, residentId = 0, 0

local function rollName()
	nameCursor += 1
	return Defs.NAMES[(nameCursor - 1) % #Defs.NAMES + 1]
end

local function makeResident()
	residentId += 1
	local ageKey = Defs.AGE_ORDER[math.random(1, #Defs.AGE_ORDER)]
	local age = Defs.AGES[ageKey]
	return {
		id = residentId,
		name = rollName(),
		type = Defs.TYPE_ORDER[math.random(1, #Defs.TYPE_ORDER)],
		age = ageKey,
		years = math.random(age.from, age.to),
		-- ⚠️ ЗВЁЗДЫ ПОКА ВСЕГДА ОДНА, см. HouseDefs.STARS_DEFAULT
		stars = Defs.STARS_DEFAULT,
		job = "none",
	}
end

-- Ближайший дом со свободной кроватью. Возвращает точку у двери, позу на
-- кровати и функцию, которой кровать освобождают.
_G.HouseClaimBed = function(fromPos, taker)
	local best, bestBed, bestDist = nil, nil, math.huge
	for i = #houses, 1, -1 do
		local h = houses[i]
		if not h.model.Parent then
			table.remove(houses, i)
		else
			local d = (h.model:GetPivot().Position - fromPos).Magnitude
			if d < bestDist then
				for name, busy in pairs(h.beds) do
					if not busy then
						best, bestBed, bestDist = h, name, d
						break
					end
				end
			end
		end
	end
	if not best then return nil end

	best.beds[bestBed] = taker or true
	local bedCF = lieCF(best.model, bestBed)
	if not bedCF then
		best.beds[bestBed] = false
		return nil
	end
	return {
		house = best.model,
		door  = markerCF(best.model, Defs.WP.door),
		bed   = bedCF,
		release = function()
			best.beds[bestBed] = false
		end,
	}
end

-- ═══════════ одежда по профессии ═══════════

-- ⚠️ ПУСТОЙ ID = «АССЕТА ЕЩЁ НЕТ», А НЕ «РАЗДЕТЬ».
-- Здесь было наоборот: пустая строка означала «сделать одежду прозрачной». Но в
-- таблице JOB_OUTFIT пусты ВСЕ профессии, включая нефтяника, — а у моделей
-- рабочих своя одежда внутри, и она и есть рабочая роба. Выходило, что любой
-- житель при найме мгновенно терял её и стоял в стандартном виде, а сменить
-- профессию ничего не меняло: раздевание было одинаковым для всех.
-- Теперь правило другое:
--   • есть id в таблице  → надеваем его;
--   • id пустой, но работа есть → возвращаем РОДНУЮ одежду модели;
--   • работы нет ("none", уволен) → раздеваем.
-- Родной вид запоминаем один раз, ДО первой переодевки, иначе восстанавливать
-- будет нечего.
-- Касается и Shirt/Pants (классические слои), и отдельных деталей одежды у
-- импортированных моделей: у них «роба» — меши, а не текстура на теле.
local CLOTH_HINTS = { "shirt", "pants", "cloth", "vest", "coat", "apron", "uniform", "robe", "jacket" }

local function looksLikeCloth(part)
	local n = part.Name:lower()
	for _, h in ipairs(CLOTH_HINTS) do
		if n:find(h) then return true end
	end
	return false
end

local function rememberOriginalOutfit(model)
	if model:GetAttribute("OutfitSaved") then return end
	model:SetAttribute("OutfitSaved", true)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Shirt") then
			d:SetAttribute("OrigTemplate", d.ShirtTemplate)
		elseif d:IsA("Pants") then
			d:SetAttribute("OrigTemplate", d.PantsTemplate)
		elseif d:IsA("Decal") and d.Name:lower() == "face" then
			-- лицо запоминаем вместе с одеждой: вернуть рабочее лицо после найма
			-- иначе будет нечем
			d:SetAttribute("OrigTexture", d.Texture)
		elseif d:IsA("BasePart") and looksLikeCloth(d) then
			d:SetAttribute("OrigTransparency", d.Transparency)
		end
	end
end

--[[ ⚠️ ПОЛ БЕРЁМ У МОДЕЛИ, А НЕ У ЗАПИСИ ЖИТЕЛЯ.
     В записи его нет (см. makeResident), а одежда обязана совпасть с телом,
     которое стоит в мире. Атрибут Sex сильнее имени: имя модели может быть
     каким угодно, а атрибут ставится осознанно. ]]
local warnedNoSex = {}
local function sexOf(model)
	local attr = model:GetAttribute("Sex")
	if typeof(attr) == "string" then
		return attr:lower() == "female" and "female" or "male"
	end
	local n = model.Name:lower()
	for _, hint in ipairs(Defs.FEMALE_HINTS) do
		if n:find(hint, 1, true) then return "female" end
	end
	if not warnedNoSex[model.Name] then
		warnedNoSex[model.Name] = true
		warn(("[Дом] у модели «%s» не указан пол — одеваю как мужчину."
			.. " Поставь ей атрибут Sex = \"female\" или допиши имя в HouseDefs.FEMALE_HINTS")
			:format(model.Name))
	end
	return "male"
end

_G.HouseApplyOutfit = function(model, jobId)
	if typeof(model) ~= "Instance" then return end
	rememberOriginalOutfit(model)

	local job = jobId or "none"
	local kit = Defs.JOB_OUTFIT[job] or Defs.JOB_OUTFIT.none
	local bare = (job == "none")   -- у безработного своя, гражданская одежда
	--[[ ⚠️ УВОЛЕННЫЙ ПЕРЕОДЕВАЕТСЯ, А НЕ РАЗДЕВАЕТСЯ.
	     Раньше здесь одежда просто гасилась: рабочая роба исчезала, а взамен не
	     появлялось ничего, и уволенный житель ходил в стандартном теле. Теперь у
	     «без работы» есть свой комплект — рубашка, штаны и лицо. Меши робы при
	     этом всё равно прячем: они принадлежат работе, а не человеку. ]]
	local civil = bare and Defs.OUTFIT_NONE[sexOf(model)] or nil

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Shirt") then
			if kit.shirt ~= "" then
				d.ShirtTemplate = kit.shirt
			elseif civil then
				d.ShirtTemplate = civil.shirt
			else
				d.ShirtTemplate = d:GetAttribute("OrigTemplate") or ""
			end
		elseif d:IsA("Pants") then
			if kit.pants ~= "" then
				d.PantsTemplate = kit.pants
			elseif civil then
				d.PantsTemplate = civil.pants
			else
				d.PantsTemplate = d:GetAttribute("OrigTemplate") or ""
			end
		elseif d:IsA("Decal") and d.Name:lower() == "face" then
			d.Texture = civil and civil.face or (d:GetAttribute("OrigTexture") or d.Texture)
		elseif d:IsA("BasePart") and looksLikeCloth(d) then
			d.LocalTransparencyModifier = 0
			d.Transparency = bare and 1 or (d:GetAttribute("OrigTransparency") or 0)
		end
	end
	model:SetAttribute("Outfit", job)
end

-- ═══════════ меню управления ═══════════

local menuEvent = ReplicatedStorage:FindFirstChild("HouseMenu")
if not menuEvent then
	menuEvent = Instance.new("RemoteEvent")
	menuEvent.Name = "HouseMenu"
	menuEvent.Parent = ReplicatedStorage
end

local function houseOf(model)
	for _, h in ipairs(houses) do
		if h.model == model then return h end
	end
	return nil
end

-- ⚠️ ОТКРЫТЫЕ ПРОФЕССИИ ВЕДЁТ СЕРВЕР.
-- На старте открыты только «Без работы» и «Нефтяник» — остальные под замком до
-- прогресса. Клиент этот список только рисует; проверка назначения всё равно
-- здесь, иначе профессию можно было бы выдать в обход замка.
local unlockedJobs = {}
for _, job in ipairs(Defs.JOBS) do
	if job.unlocked then unlockedJobs[job.id] = true end
end

_G.HouseUnlockJob = function(id)
	if Defs.jobById(id).id == id then unlockedJobs[id] = true end
end

local function payload(h, player)
	local list = {}
	for _, r in ipairs(h.residents) do
		table.insert(list, {
			id = r.id, name = r.name, type = r.type, age = r.age,
			years = r.years, stars = r.stars, job = r.job,
			eff = Defs.efficiency(r, h.level),
			-- фермер: какая ферма за ним (имя рисует карточка и строка списка)
			farm = r.farm,
			farmName = (r.farm and typeof(_G.FarmNameOf) == "function") and _G.FarmNameOf(r.farm) or nil,
		})
	end
	local unlocked = {}
	for id in pairs(unlockedJobs) do table.insert(unlocked, id) end
	return {
		houseName = Defs.NAME_RU,
		level = h.level,
		capacity = h.capacity,
		residents = list,
		population = (player and player:GetAttribute("Villagers")) or 0,
		unlocked = unlocked,
	}
end

-- ⚠️ ПРОФЕССИЯ ВЫБИРАЕТСЯ САМА, ЕСЛИ ЕЙ ЕСТЬ ГДЕ РАБОТАТЬ.
-- Заказчик: «работа сама выбирается, если есть нефтевышка и дом с жителями».
-- Заселять жителя и потом отдельно ходить назначать его — лишний шаг: если
-- вышка стоит, а житель без дела, ставим его нефтяником сразу. Ручное
-- назначение это не ломает: раз выбранная профессия больше не перебивается.
local function autoAssign(h)
	local rigExists = typeof(_G.OilRigCount) == "function" and _G.OilRigCount() > 0
	if not rigExists then return end
	for _, r in ipairs(h.residents) do
		if r.job == "none" and not r.jobChosenByPlayer then
			r.job = "oil"
		end
	end
end

-- ⚠️ СВЯЗЬ «ЖИТЕЛЬ ↔ ТЕЛО» ЖИВЁТ ЗДЕСЬ.
-- Вышка клонирует свою пару рабочих и про жителей ничего не знает — поэтому
-- увольнение конкретного человека её не касалось: нефтяников оставалось больше
-- нуля, и оба продолжали работать. Регистрируем тела за жителями, и дальше
-- вышка спрашивает про КАЖДОГО: он ещё нефтяник?
_G.HouseBindWorker = function(model)
	if typeof(model) ~= "Instance" then return nil end
	for _, h in ipairs(houses) do
		if h.model.Parent then
			-- уже привязан — второй раз не занимаем
			for _, r in ipairs(h.residents) do
				if r.model == model then return r.id end
			end
			for i, r in ipairs(h.residents) do
				if r.job == "oil" and not (r.model and r.model.Parent) then
					r.model = model
					model:SetAttribute("ResidentId", r.id)
					model:SetAttribute("ResidentName", r.name)
					pcall(_G.HouseApplyOutfit, model, r.job)
					writeResidents(h.model, h.residents)
					_G.HouseBindResidentModel(h.model, i, model)
					return r.id
				end
			end
		end
	end
	return nil
end

-- Работает ли ещё этот конкретный рабочий. Тело без прописки считаем занятым:
-- иначе вышка, построенная до появления дома, встала бы на пустом месте.
-- ⚠️ БЕЗ ПРОПИСКИ СЧИТАЕМ РАБОТАЮЩИМ ТОЛЬКО ПОКА ЖИТЕЛЕЙ ВООБЩЕ НЕТ.
-- Иначе выходило так: тело не привязалось (жителей ещё не завели), «работает»
-- по умолчанию — и увольнение не действовало ни на кого. Как только в домах
-- появились нефтяники, непривязанное тело считается лишним и уходит.
_G.HouseWorkerEmployed = function(model)
	local id = typeof(model) == "Instance" and model:GetAttribute("ResidentId")
	if not id then
		local anyOil = false
		for _, h in ipairs(houses) do
			for _, r in ipairs(h.residents) do
				if r.job == "oil" then anyOil = true end
			end
		end
		return not anyOil
	end
	for _, h in ipairs(houses) do
		for _, r in ipairs(h.residents) do
			if r.id == id then return r.job == "oil" end
		end
	end
	return false   -- прописки больше нет: выселили
end

-- Освободить стул за этим телом: без этого место остаётся «занятым» навсегда.
_G.HouseReleaseSeat = function(model)
	for _, h in ipairs(houses) do
		if h.seats then
			for seat, taker in pairs(h.seats) do
				if taker == model then h.seats[seat] = nil end
			end
		end
	end
end

-- ⚠️ ДНЁМ СИДЯТ, НОЧЬЮ СПЯТ — И ТОЛЬКО ПОТОМ «ЕСЛИ ЗАНЯТО».
-- Заказчик: «один должен сидеть на стуле если это день и спать если ночь, не оба
-- должны спать днём». Значит время решает ПЕРВЫМ, а нехватка мест — вторым:
-- днём идём за стулом и ложимся, только если стульев не хватило; ночью наоборот.
_G.HouseIdleSpot = function(model, prefer)
	prefer = prefer or "sit"
	local id = typeof(model) == "Instance" and model:GetAttribute("ResidentId")

	local function seatIn(h)
		h.seats = h.seats or {}
		for _, seat in ipairs({ Defs.WP.sitA, Defs.WP.sitB }) do
			local taker = h.seats[seat]
			if not taker or taker == model or not taker.Parent then
				local cf = markerCF(h.model, seat)
				if cf then
					h.seats[seat] = model
					return { kind = "sit", cf = cf,
						door = markerCF(h.model, Defs.WP.door) }
				end
			end
		end
		return nil
	end

	local function bedIn(h)
		local claim = _G.HouseClaimBed(h.model:GetPivot().Position, model)
		if claim then claim.kind = "bed" end
		return claim
	end

	for _, h in ipairs(houses) do
		if h.model.Parent then
			local mine = nil
			for _, r in ipairs(h.residents) do
				if r.id == id then mine = r end
			end
			if mine or not id then
				local first  = (prefer == "bed") and bedIn or seatIn
				local second = (prefer == "bed") and seatIn or bedIn
				local spot = first(h) or second(h)
				if spot then return spot end
			end
		end
	end
	return nil
end

-- Сколько нефтяников и с какой суммарной отдачей: по этому вышка решает,
-- работать ли ей вообще.
_G.HouseOilCrew = function()
	local count, power = 0, 0
	for _, h in ipairs(houses) do
		if h.model.Parent then
			for _, r in ipairs(h.residents) do
				if r.job == "oil" then
					count += 1
					power += Defs.efficiency(r, h.level)
				end
			end
		end
	end
	return count, power
end

local function pushAll(h)
	autoAssign(h)
	writeResidents(h.model, h.residents)
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("HouseMenuOpen") then
			menuEvent:FireClient(p, "data", payload(h, p))
		end
	end
end

-- ═══════════ ФЕРМА ═══════════
-- (ниже pushAll: Lua без хойстинга, и HouseSetFarm зовёт его)
-- Ферма спрашивает, кто её фермер, и привязывает к нему тело — тем же путём,
-- что вышка (атрибуты ResidentId/ResidentName, одежда, портрет на табличке).
_G.HouseFarmers = function()
	local out = {}
	for _, h in ipairs(houses) do
		if h.model.Parent then
			for i, r in ipairs(h.residents) do
				if r.job == "farmer" then
					table.insert(out, { id = r.id, name = r.name, farm = r.farm, house = h.model, index = i,
						eff = Defs.efficiency(r, h.level), model = r.model })
				end
			end
		end
	end
	return out
end

-- Ферма исчезла (снесли/не восстановилась) — житель остаётся без работы;
-- ферма нашлась/сменилась — запоминаем её id.
_G.HouseSetFarm = function(residentId, farmId)
	for _, h in ipairs(houses) do
		for _, r in ipairs(h.residents) do
			if r.id == residentId then
				if farmId then
					r.farm = farmId
				else
					r.farm = nil
					if r.job == "farmer" then
						r.job = "none"
						if r.model then pcall(_G.HouseApplyOutfit, r.model, "none") end
					end
				end
				pushAll(h)
				return true
			end
		end
	end
	return false
end

_G.HouseBindFarmer = function(model, residentId)
	if typeof(model) ~= "Instance" then return nil end
	for _, h in ipairs(houses) do
		if h.model.Parent then
			for i, r in ipairs(h.residents) do
				if r.id == residentId and r.job == "farmer" then
					r.model = model
					model:SetAttribute("ResidentId", r.id)
					model:SetAttribute("ResidentName", r.name)
					pcall(_G.HouseApplyOutfit, model, r.job)
					writeResidents(h.model, h.residents)
					_G.HouseBindResidentModel(h.model, i, model)
					return r.id
				end
			end
		end
	end
	return nil
end

menuEvent.OnServerEvent:Connect(function(player, action, model, arg1, arg2)
	if action == "close" then
		player:SetAttribute("HouseMenuOpen", false)
		return
	end
	if typeof(model) ~= "Instance" then return end
	local h = houseOf(model)
	if not h then return end

	-- рядом с домом: чужие клики с другого конца карты не принимаем
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - model:GetPivot().Position).Magnitude > 90 then return end

	if action == "open" then
		player:SetAttribute("HouseMenuOpen", true)
		autoAssign(h)
		menuEvent:FireClient(player, "data", payload(h, player))

	elseif action == "add" then
		if #h.residents >= h.capacity then
			menuEvent:FireClient(player, "toast", "В доме нет свободных мест")
			return
		end
		local have = player:GetAttribute("Villagers") or 0
		if have < 1 then
			menuEvent:FireClient(player, "toast", "Не хватает жителей")
			return
		end
		if typeof(_G.SpendVillagers) == "function" then
			local ok = _G.SpendVillagers(player, 1)
			if ok == false then
				menuEvent:FireClient(player, "toast", "Не хватает жителей")
				return
			end
		end
		local res = makeResident()
		table.insert(h.residents, res)
		pushAll(h)
		menuEvent:FireClient(player, "toast", ("%s заселился"):format(res.name))
		menuEvent:FireClient(player, "select", res.id)

	elseif action == "evict" then
		for i, r in ipairs(h.residents) do
			if r.id == arg1 then
				table.remove(h.residents, i)
				-- ⚠️ УВОЛЕННЫЙ ПЕРЕОДЕВАЕТСЯ ОБРАТНО.
				-- Он больше не нефтяник, и роба на нём читалась бы как «всё ещё
				-- работает». "none" в таблице одежды и есть стандартный вид.
				if r.model then pcall(_G.HouseApplyOutfit, r.model, "none") end
				if r.job == "farmer" and typeof(_G.FarmRelease) == "function" then pcall(_G.FarmRelease, r.id) end
				pushAll(h)
				if typeof(_G.AddVillagers) == "function" then
					pcall(_G.AddVillagers, player, 1)
				end
				menuEvent:FireClient(player, "toast", ("%s выселен"):format(r.name))
				return
			end
		end

	elseif action == "job" then
		local job = Defs.jobById(arg2)
		if job.id ~= arg2 then return end
		if not unlockedJobs[job.id] then
			menuEvent:FireClient(player, "toast",
				("Профессия «%s» пока заблокирована"):format(job.name))
			return
		end
		for _, r in ipairs(h.residents) do
			if r.id == arg1 then
				--[[ ⚠️ ФЕРМЕР ПРИВЯЗЫВАЕТСЯ К СВОБОДНОЙ ФЕРМЕ, ИНАЧЕ ПРОФЕССИЯ НЕ ВЫДАЁТСЯ.
				     Одна ферма — один житель; ферму выбирает FarmSystem (ближайшую к
				     дому свободную). Нет свободной — игроку называется причина, а
				     прежняя профессия остаётся. Уход с фермы освобождает её сразу. ]]
				if job.id == "farmer" then
					if r.job ~= "farmer" or not r.farm then
						if typeof(_G.FarmAssign) ~= "function" then
							menuEvent:FireClient(player, "toast", "Фермы ещё не готовы, попробуй через секунду")
							return
						end
						local fid, why = _G.FarmAssign(r.id, model:GetPivot().Position)
						if not fid then
							menuEvent:FireClient(player, "toast", why or "Нет свободной фермы")
							return
						end
						r.farm = fid
					end
				elseif r.job == "farmer" then
					if typeof(_G.FarmRelease) == "function" then pcall(_G.FarmRelease, r.id) end
					r.farm = nil
				end
				r.job = job.id
				r.jobChosenByPlayer = true   -- автовыбор больше не перебьёт
				if r.model then pcall(_G.HouseApplyOutfit, r.model, job.id) end
				pushAll(h)
				local where = (r.farm and typeof(_G.FarmNameOf) == "function")
					and (" (" .. _G.FarmNameOf(r.farm) .. ")") or ""
				menuEvent:FireClient(player, "toast",
					("%s теперь %s%s"):format(r.name, job.name, where))
				return
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	player:SetAttribute("HouseMenuOpen", false)
end)

-- ═══════════ постановка ═══════════

local function spotOK(cf, size, ignore)
	-- проверку ведёт вышка; пока её скрипт не загрузился, пропускаем только
	-- очевидно безопасное — иначе первый же клик после старта прошёл бы без
	-- проверок вообще
	if type(_G.OilRigSpotOK) ~= "function" then
		return false, "проверка места ещё не готова, попробуй через секунду"
	end
	return _G.OilRigSpotOK(cf, size, ignore)
end

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
	local tpl = findTemplate(Defs.MODEL)
	if not tpl then
		warn(LOG .. " шаблон «" .. Defs.MODEL .. "» не найден в ReplicatedStorage/Workspace")
		placeEvent:FireClient(player, "denied", "модель дома не найдена")
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

	--[[ ⚠️ ДОМ НАКОНЕЦ СТОИТ ДЕНЕГ, А НЕ ТОЛЬКО ОБЕЩАЕТ.
	     Меню молотка показывало «20 Log» (BuildingSystem.client.lua, HOUSE_ITEM),
	     но сервер цену не проверял и не списывал: дом ставился бесплатно и в любом
	     количестве. Для экономики это дыра в самом низу — дом даёт рабочих на
	     нефтевышку, то есть бесплатно множит доход.
	     Цена берётся отсюда и обязана совпадать с числом в клиентском меню:
	     разойдутся — игрок увидит одно, а спишется другое. ]]
	local inv = (typeof(_G.GetInventory) == "function" and _G.GetInventory(player)) or {}
	-- админ строит бесплатно (флаг DevLogs ставит сервер: DevLogFlag)
	local freeBuild = player:GetAttribute("DevLogs") == true
	if not freeBuild and (inv[HOUSE_COST_RES] or 0) < HOUSE_COST then
		placeEvent:FireClient(player, "denied",
			string.format("нужно %d брёвен, есть %d", HOUSE_COST, inv[HOUSE_COST_RES] or 0))
		return
	end
	if not freeBuild and typeof(_G.RemoveResourceFromInventory) == "function" then
		_G.RemoveResourceFromInventory(player, HOUSE_COST_RES, HOUSE_COST)
		-- ⚠️ Списание само по себе клиенту ничего не шлёт: RemoveResourceFromInventory
		-- правит серверную таблицу, а показать это игроку — дело SendInventory.
		-- Без этой строки брёвна уходят молча, и число на экране остаётся прежним.
		if typeof(_G.SendInventory) == "function" then _G.SendInventory(player) end
	end

	local house = tpl:Clone()
	house.Name = Defs.MODEL
	pcall(function() house:PivotTo(cf) end)
	for _, d in ipairs(house:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	hideMarkers(house)
	-- трава и камешки под цоколем убираются тем же правилом, что у вышки
	if typeof(_G.OilRigClearDecor) == "function" then
		pcall(_G.OilRigClearDecor, cf, size)
	end
	house.Parent = Workspace
	do local isle = islandAt(cf.Position); if isle then isle:SetAttribute("KeepAlive", true) end end

	hearthFx(house)
	lampFx(house)
	registerHouse(house)

	placeEvent:FireClient(player, "placed")
	print(LOG .. " построен, кроватей свободно: 2")
end)

-- Дом мог быть выставлен в плейсе руками — подхватываем и такой, иначе рабочие
-- будут ночевать под открытым небом рядом с готовым домом.
for _, d in ipairs(Workspace:GetChildren()) do
	if d:IsA("Model") and d.Name == Defs.MODEL then
		hideMarkers(d)
		hearthFx(d)
		lampFx(d)
		registerHouse(d)
		print(LOG .. " найден уже стоящий дом в Workspace")
	end
end

--[[ СЕЙВ: дома с жителями. Экспорт отдаёт положение и список жителей,
     восстановление ставит дом заново и возвращает жителей в него. ]]
_G.HouseExport = function()
	local out = {}
	for _, h in ipairs(houses) do
		if h.model.Parent then
			local res = {}
			for _, r in ipairs(h.residents) do
				table.insert(res, { id = r.id, name = r.name, type = r.type, age = r.age, years = r.years, stars = r.stars, job = r.job, farm = r.farm })
			end
			table.insert(out, { cf = h.model:GetPivot(), level = h.level, capacity = h.capacity, residents = res })
		end
	end
	return out
end
_G.HouseRestore = function(cf, rec)
	local tpl = findTemplate(Defs.MODEL)
	if not tpl then return nil end
	local house = tpl:Clone()
	house.Name = Defs.MODEL
	pcall(function() house:PivotTo(cf) end)
	for _, d in ipairs(house:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	hideMarkers(house)
	if rec and rec.level then house:SetAttribute("HouseLevel", rec.level) end
	if rec and rec.capacity then house:SetAttribute("HouseCapacity", rec.capacity) end
	house.Parent = Workspace
	hearthFx(house)
	lampFx(house)
	local h = registerHouse(house)
	if rec and type(rec.residents) == "table" then
		for _, r in ipairs(rec.residents) do
			if type(r) == "table" and type(r.name) == "string" then
				local id = tonumber(r.id) or 0
				if id > residentId then residentId = id end
				table.insert(h.residents, { id = id, name = r.name, type = r.type, age = r.age, years = r.years, stars = r.stars, job = r.job or "none",
					farm = (r.job == "farmer") and tonumber(r.farm) or nil, jobChosenByPlayer = (r.job or "none") ~= "none" or nil })
			end
		end
		pushAll(h)
	end
	print(("%s восстановлен из сейва: жителей %d"):format(LOG, #h.residents))
	return house
end

print(LOG .. " готов: ставится молотком на сушу острова, в нём спят жители")
