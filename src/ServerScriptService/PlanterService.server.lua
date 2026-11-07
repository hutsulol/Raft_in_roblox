-- PlanterService.server.lua
-- ГРЯДКА: посадка, полив, рост, сбор.
--
-- ⚠️ СОСТОЯНИЕ — ЭТО ДАННЫЕ, ВИЗУАЛ — ПРОИЗВОДНАЯ.
-- Старая грядка хранила состояние «в том, что сейчас видно»: все варианты
-- лежали в мире, лишние прятались через Transparency. Так больше не делаем —
-- невидимая деталь всё равно существует, реплицируется и ловит лучи
-- (Transparency НЕ выключает CanCollide/CanQuery/CanTouch), а запросить такое
-- состояние или сохранить его в DataStore нельзя.
--
-- Здесь наоборот: у каждой грядки есть таблица состояния, а мир трогается
-- ТОЛЬКО в момент фактической смены стадии или полива.
--
-- ⚠️ ОДИН ЦИКЛ НА ВСЕ ГРЯДКИ. Никаких скриптов внутри самой грядки: сто грядок
-- — это сто строк в таблице, а не сто корутин while wait().
--
-- Раскладка, которую ждёт этот сервис:
--   ReplicatedStorage/
--       CropDefs                    (ModuleScript)
--       PlanterBases/ Dry, Watered  (MeshPart)
--       Crops/ Potato/ Sprout, Young, Ripe
--              Beet/   Sprout, Young, Ripe
--   Шаблон грядки: ReplicatedStorage/Raft_planter (Model с Base внутри)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlaceCheck = require(game:GetService("ReplicatedStorage"):WaitForChild("PlaceCheck"))   -- «место занято» — общая проверка

local LOG_TAG = "[Planter]"

local TEMPLATE_NAME = "Raft_planter"
local BASE_NAME     = "Base"
local CROP_NAME     = "Crop"
local TICK          = 1     -- шаг цикла роста, секунды
local WATER_DRY     = 90    -- через сколько политая грядка высыхает
local REACH         = 14

local Defs = require(ReplicatedStorage:WaitForChild("CropDefs"))
local RaftShake = require(ReplicatedStorage:WaitForChild("RaftShake"))

-- ═══════════════════════════════════════════════════════════════════
-- РАСКЛАДКА АССЕТОВ ИЗ FBX
-- ═══════════════════════════════════════════════════════════════════
-- FBX импортируется ОДНОЙ моделью со всеми восемью мешами внутри: две земли и
-- шесть стадий роста. Если оставить её как есть, то и призрак при постройке, и
-- поставленная грядка показывают ВСЁ сразу — заросли поверх пустого ящика.
--
-- Разложить это руками — ровно та работа, которую описывал бриф (папки
-- PlanterBases/Crops + разовый скрипт для Offset). Делаем её кодом, один раз при
-- старте сервера: FBX уже содержит правильное взаимное расположение мешей, а
-- значит смещения можно посчитать прямо из него, ничего не вымеряя.
--
-- Операция ИДЕМПОТЕНТНА: если папки уже собраны, второй раз ничего не трогаем.
local STAGE_ALIASES = { sprout = "Sprout", young = "Young", ripe = "Ripe" }


-- ⚠️ ИЩЕМ МЯГКО: рекурсивно и без учёта регистра.
-- Строгий FindFirstChild промахивался, если модель лежит в папке или названа
-- другим регистром (raft_planter). Симптом был обманчивый: призрак при
-- постройке ПОЯВЛЯЛСЯ — его ищет клиент, а там поиск как раз мягкий, — но
-- раскладка ассетов и сама установка молча не срабатывали. Один и тот же
-- способ поиска на клиенте и на сервере снимает целый класс таких расхождений.
local function findTemplate(name)
	local hit = ReplicatedStorage:FindFirstChild(name)
		or ReplicatedStorage:FindFirstChild(name, true)
	if hit then return hit end
	local lower = name:lower()
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d.Name:lower() == lower and (d:IsA("Model") or d:IsA("BasePart")) then
			return d
		end
	end
	return nil
end

local function bootstrapAssets()
	if ReplicatedStorage:FindFirstChild("PlanterBases") then return end

	local model = findTemplate(TEMPLATE_NAME)
	if not model then
		warn(LOG_TAG .. " нет модели " .. TEMPLATE_NAME .. " в ReplicatedStorage "
			.. "(искал рекурсивно и без учёта регистра) — грядки работать не будут")
		return
	end
	print(("%s шаблон найден: %s"):format(LOG_TAG, model:GetFullName()))

	-- Собираем меши по именам из FBX. Сверяем в нижнем регистре и по вхождению:
	-- импортёр может изменить регистр или добавить суффикс.
	local dry, watered
	local stages = {}  -- [культура][стадия] = MeshPart
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") then
			local n = d.Name:lower()
			if n:find("watered", 1, true) then
				watered = d
			elseif n:find("dry", 1, true) then
				dry = d
			else
				for cropName in pairs(Defs) do
					if n:find(cropName:lower(), 1, true) then
						for alias, stage in pairs(STAGE_ALIASES) do
							if n:find(alias, 1, true) then
								stages[cropName] = stages[cropName] or {}
								stages[cropName][stage] = d
							end
						end
					end
				end
			end
		end
	end

	if not dry then
		warn(LOG_TAG .. " в модели грядки не нашлась земля (меш со словом 'dry') — "
			.. "раскладка отменена")
		return
	end

	local bases = Instance.new("Folder")
	bases.Name = "PlanterBases"
	bases.Parent = ReplicatedStorage

	local cropsRoot = Instance.new("Folder")
	cropsRoot.Name = "Crops"
	cropsRoot.Parent = ReplicatedStorage

	-- Смещение считаем ОТ БАЗЫ и кладём в саму заготовку. У MeshPart пивот в
	-- центре bbox, а bbox у базы и у стадий разные — без этого растение уехало
	-- бы по высоте. У Watered смещение выйдет нулевым: геометрия совпадает с
	-- Dry, и это заодно проверка, что всё посчиталось верно.
	local function extract(part, name, parent)
		local copy = part:Clone()
		copy.Name = name
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		local off = Instance.new("CFrameValue")
		off.Name = "Offset"
		off.Value = dry.CFrame:ToObjectSpace(part.CFrame)
		off.Parent = copy
		copy.Parent = parent
		return copy
	end

	extract(dry, "Dry", bases)
	if watered then
		extract(watered, "Watered", bases)
	else
		warn(LOG_TAG .. " нет меша политой земли — полив не будет менять вид")
	end

	local made = {}
	for cropName, byStage in pairs(stages) do
		local folder = Instance.new("Folder")
		folder.Name = cropName
		folder.Parent = cropsRoot
		local names = {}
		for stage, part in pairs(byStage) do
			extract(part, stage, folder)
			table.insert(names, stage)
		end
		table.insert(made, ("%s (%s)"):format(cropName, table.concat(names, ", ")))
	end

	-- ⚠️ ЧИСТИМ ШАБЛОН. Всё лишнее из модели убираем, оставляем ОДНУ деталь —
	-- ящик с сухой землёй, названный Base. Именно её увидит призрак и именно
	-- она встанет на плот; урожай добавляется отдельным мешем по состоянию.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= dry then d:Destroy() end
	end
	dry.Name = BASE_NAME
	dry.Anchored = true
	dry.CanCollide = true

	-- ⚠️ ПОВОРОТ ОПРЕДЕЛЯЕМ ПО ГЕОМЕТРИИ, А НЕ КОНСТАНТОЙ.
	--
	-- В брифе сказано: «z = 0 — низ ящика», то есть FBX собран с осью Z вверх, а
	-- у Roblox вверх смотрит Y. Импортёр это не выправляет, и грядка встаёт на
	-- ребро, как стенка. Жёсткая константа поворота тут не годится: угадать
	-- сторону вслепую нельзя, а ошибка в знаке даёт тот же вертикальный ящик.
	--
	-- Зато форму знаем точно: грядка — ПЛОСКИЙ ящик, у неё ровно одна тонкая
	-- ось, и это высота. Находим её и ставим деталь так, чтобы эта ось смотрела
	-- в мировой Y.
	--
	-- ⚠️ ПОВОРОТ ЗАДАЁМ АБСОЛЮТНО, А НЕ ДОМНОЖАЕМ.
	-- Прошлая версия смотрела только на Size и домножала поворот на текущий.
	-- Size у этой модели — 3.92 × 1.21 × 3.92, то есть меш ПЛОСКИЙ в собственных
	-- осях, и проверка честно отвечала «поворот не нужен». А на ребро его ставил
	-- поворот САМОЙ ДЕТАЛИ, доставшийся от импортёра, — его-то и надо обнулить.
	-- Поэтому здесь присваивание: что бы ни принёс импорт, деталь встаёт ровно.
	local sz = dry.Size
	local rot = CFrame.new()          -- тонкая ось уже Y — просто выпрямляем
	local why = "тонкая ось Y"
	if sz.Z <= sz.X and sz.Z <= sz.Y then
		rot = CFrame.Angles(-math.pi / 2, 0, 0)   -- тонкая ось Z → кладём Z в Y
		why = "тонкая ось Z"
	elseif sz.X <= sz.Y and sz.X <= sz.Z then
		rot = CFrame.Angles(0, 0, math.pi / 2)    -- тонкая ось X → кладём X в Y
		why = "тонкая ось X"
	end
	dry.CFrame = CFrame.new(dry.Position) * rot

	print(("%s габарит базы %.2f × %.2f × %.2f (%s) → выпрямлена")
		:format(LOG_TAG, sz.X, sz.Y, sz.Z, why))

	-- Урожай доворачивается сам: его позиция считается как base.CFrame * Offset,
	-- то есть ОТНОСИТЕЛЬНО базы. Смещения посчитаны выше, до поворота, и от него
	-- не зависят — растения повернутся вместе с ящиком.

	if model:IsA("Model") then
		model.PrimaryPart = dry
		model.WorldPivot = dry.CFrame
	end

	print(("%s ассеты разложены: базы Dry%s, культуры — %s. Шаблон очищен до Base.")
		:format(LOG_TAG, watered and "+Watered" or "", table.concat(made, "; ")))
end

bootstrapAssets()

local gardenActionEvent = ReplicatedStorage:WaitForChild("GardenAction")

-- [Model] = state
local planters = {}

-- ─── Поиск ассетов ───
-- Ругаемся ОДИН раз на каждый недостающий узел: без ассетов система обязана
-- молчать и не мешать, а не сыпать в лог каждую секунду.
local warned = {}
local function warnOnce(key, msg)
	if warned[key] then return end
	warned[key] = true
	warn(LOG_TAG .. " " .. msg)
end

local function baseTemplate(watered)
	local folder = ReplicatedStorage:FindFirstChild("PlanterBases")
	if not folder then
		warnOnce("bases", "нет папки ReplicatedStorage/PlanterBases (Dry, Watered) — "
			.. "земля не будет меняться при поливе")
		return nil
	end
	local name = watered and "Watered" or "Dry"
	local t = folder:FindFirstChild(name)
	if not t then
		warnOnce("base_" .. name, "нет меша PlanterBases/" .. name)
	end
	return t
end

local function cropTemplate(cropName, stageName)
	local root = ReplicatedStorage:FindFirstChild("Crops")
	if not root then
		warnOnce("crops", "нет папки ReplicatedStorage/Crops — растения не появятся")
		return nil
	end
	local folder = root:FindFirstChild(cropName)
	if not folder then
		warnOnce("crop_" .. cropName, "нет папки Crops/" .. cropName)
		return nil
	end
	local t = folder:FindFirstChild(stageName)
	if not t then
		warnOnce("stage_" .. cropName .. stageName,
			("нет меша Crops/%s/%s"):format(cropName, stageName))
	end
	return t
end

-- ─── Стадия роста ───
-- Считаем так, чтобы спелость наступала РОВНО в growSeconds, а не на двух
-- третях: при трёх стадиях граница последней — ровно 100% времени.
local function stageOf(st)
	local def = Defs[st.crop]
	if not def then return 0 end
	local t = st.grownSeconds / def.growSeconds
	local n = #def.stages
	return math.clamp(math.floor(t * (n - 1)) + 1, 1, n)
end

local function isRipe(st)
	local def = st.crop and Defs[st.crop]
	return def ~= nil and stageOf(st) >= #def.stages
end

-- ─── Визуал ───
local function findBase(planter)
	return planter:FindFirstChild(BASE_NAME)
		or planter:FindFirstChildWhichIsA("MeshPart")
		or planter:FindFirstChildWhichIsA("BasePart")
end

-- Земля: сухая ↔ политая. Геометрия у обоих мешей одинаковая, отличается только
-- развёртка, поэтому подменяем МЕШ, а не текстуру.
-- Объявлена ниже, но нужна уже здесь: смена меша базы (сухая ↔ политая) — тоже
-- вмешательство в сборку плота и тоже даёт рывок.
local withRaftVelocityKept

local function applyBase(planter, watered)
	local base = findBase(planter)
	local src = baseTemplate(watered)
	if not base or not src then return end

	withRaftVelocityKept(function()
		-- ApplyMesh переносит и меш, и текстуру одним вызовом. Если версия движка
		-- его не поддерживает, падаем на прямую подмену полей.
		local ok = pcall(function() base:ApplyMesh(src) end)
		if not ok then
			pcall(function()
				base.MeshId = src.MeshId
				base.TextureID = src.TextureID
			end)
		end
	end)
end

-- Урожай: в любой момент времени НЕ БОЛЬШЕ ОДНОГО меша.
-- ⚠️ ПОДМЕНА ДЕТАЛИ НЕ ДОЛЖНА ТОЛКАТЬ ПЛОТ.
-- Грядка приварена к плоту, а плот — единая физическая сборка. Удалить деталь и
-- поставить новую значит на кадр изменить массу и центр сборки: физика отвечает
-- рывком, и игрока на палубе сдвигает вперёд «по инерции». Снимаем скорость до
-- подмены и возвращаем после — сборка продолжает плыть ровно так же, как плыла.
function withRaftVelocityKept(fn)
	local raft = workspace:FindFirstChild("Raft")
	local root = raft and raft.PrimaryPart
	if not root then return fn() end
	local lin = root.AssemblyLinearVelocity
	local ang = root.AssemblyAngularVelocity
	fn()
	root.AssemblyLinearVelocity = lin
	root.AssemblyAngularVelocity = ang
	-- ⚠️ ПЛОТУ СКОРОСТЬ ВЕРНУЛИ, А ИГРОКУ — НЕТ.
	-- Персонаж — отдельная сборка, и принадлежит она СВОЕМУ клиенту: серверная
	-- запись в его HumanoidRootPart тут же перебивается репликацией с него. Место
	-- на палубе может удержать только владелец, поэтому просим его об этом.
	RaftShake.notify()
end

-- ⚠️ ДЕТАЛЬ РАСТЕНИЯ СОЗДАЁТСЯ ОДИН РАЗ И ЖИВЁТ ВЕЧНО.
-- Раньше каждая смена вида — посадка, каждая стадия роста, сбор — УДАЛЯЛА деталь
-- и создавала новую. Грядка приварена к плоту, а плот единая физическая сборка:
-- убрать из неё деталь и вернуть другую значит перестроить сборку, и стоящего
-- рядом игрока подтакливает. Сохранения скорости на это не хватает — оно спасает
-- от потери импульса, а не от самой перестройки.
-- Поэтому деталь теперь не трогаем совсем:
--   • вид меняем ApplyMesh — меш и текстура заменяются НА МЕСТЕ;
--   • положение правим через C0 сварки — обычный Weld двигает деталь, не разрывая
--     сборку (WeldConstraint так не умеет, поэтому он и заменён);
--   • «пусто» — это Transparency = 1, а не удаление.
local function applyCropRaw(planter, cropName, stageIndex)
	local base = findBase(planter)
	if not base then return end
	local crop = planter:FindFirstChild(CROP_NAME)

	if not cropName then
		if crop then crop.Transparency = 1 end
		return
	end

	local def = Defs[cropName]
	if not def then return end
	local template = cropTemplate(cropName, def.stages[stageIndex])
	if not template then return end

	local weld
	if crop then
		-- ApplyMesh переносит меш, текстуру и размер прямо в живую деталь
		pcall(function() crop:ApplyMesh(template) end)
		weld = crop:FindFirstChildOfClass("Weld")
	else
		crop = template:Clone()
		crop.Name = CROP_NAME
		-- Растение НЕ анкорим по той же причине, что и базу: анкер внутри сборки
		-- плота заморозил бы плот. Приваривать его к базе тоже надо — иначе
		-- незаякоренный меш просто упадёт в воду.
		crop.Anchored = false
		crop.Massless = true
		-- Растение — ДЕКОР. Коллизию и взаимодействие держит база, иначе сквозь
		-- ботву нельзя было бы пройти, а промпт ловился бы через раз.
		crop.CanCollide = false
		crop.CanQuery = false
		crop.CanTouch = false
		crop.Parent = planter

		weld = Instance.new("Weld")
		weld.Part0, weld.Part1 = base, crop
		weld.Parent = crop
	end
	crop.Transparency = 0

	-- ⚠️ ВЫРАВНИВАНИЕ ЧЕРЕЗ Offset, А НЕ ПРОСТЫМ РАВЕНСТВОМ CFrame.
	-- У MeshPart пивот в центре bbox, а у базы и у стадий bbox разные —
	-- одинаковый CFrame увёл бы растение по высоте. Смещение считается один раз
	-- на импортированной модели и лежит в самой заготовке (CFrameValue "Offset").
	local offsetCF = CFrame.new()
	local offset = template:FindFirstChild("Offset")
	if offset and offset:IsA("CFrameValue") then
		offsetCF = offset.Value
	else
		warnOnce("offset_" .. cropName,
			("у меша Crops/%s нет CFrameValue 'Offset' — растение встанет по "
			.. "центру базы и может уехать по высоте (см. разовый скрипт в брифе)")
			:format(cropName))
	end
	-- C0 и есть «где деталь относительно базы»: правка не разрывает сварку.
	if weld then
		weld.C0 = offsetCF
	else
		crop.CFrame = base.CFrame * offsetCF
	end
end

-- Скорость плота всё равно придерживаем: смена меша базы (сухая ↔ политая) меняет
-- геометрию столкновений под ногами, и без этого игрока по-прежнему сносило бы.
local function applyCrop(planter, cropName, stageIndex)
	withRaftVelocityKept(function()
		applyCropRaw(planter, cropName, stageIndex)
	end)
end

-- ─── Состояние наружу ───
-- ⚠️ ProximityPrompt УБРАН СОВСЕМ.
-- Кнопка «E» над грядкой не работает на телефоне и дублировала то, что и так
-- видно по модели. Вместо неё клиент (PlanterInteract.client) сам смотрит на
-- грядку, пишет статус над хотбаром и ловит нажатие — и клик мышью, и тап
-- пальцем, и клавишу E.
--
-- Клиенту нужно знать состояние, поэтому публикуем его АТРИБУТАМИ: они
-- реплицируются сами, без единого лишнего ремоута, и их видно в Explorer при
-- отладке.
local function publishState(planter, st)
	planter:SetAttribute("Watered", st.watered)
	planter:SetAttribute("Crop", st.crop)
	planter:SetAttribute("GrownSeconds", st.grownSeconds)   -- в сейв: рост не теряется
	planter:SetAttribute("Ripe", st.crop ~= nil and isRipe(st))
end

-- ─── Регистрация грядки ───
local function register(planter)
	if planters[planter] then return end
	local base = findBase(planter)
	if not base then
		warnOnce("nobase", "в грядке нет детали базы — взаимодействовать не с чем: "
			.. planter:GetFullName())
		return
	end
	-- ⚠️ БАЗУ НЕ АНКОРИМ.
	-- В брифе у базы стоит Anchored = true — это верно для отдельно стоящей
	-- грядки, но НЕ для приваренной к плоту: заякоренная деталь внутри сборки
	-- замораживает ВСЮ сборку, и плот переставал плыть сразу после установки
	-- грядки. Держит её сварка, поставленная при размещении.
	base.CanCollide = true
	base.Massless = true

	-- Старый ProximityPrompt из шаблона или из прошлых версий сносим: теперь
	-- взаимодействие целиком на клиенте.
	local oldPrompt = base:FindFirstChildOfClass("ProximityPrompt")
	if oldPrompt then oldPrompt:Destroy() end

	local st = {
		watered      = false,
		crop         = nil,
		grownSeconds = 0,
		lastTick     = os.time(),
		shownStage   = 0,
		shownWatered = nil,
		wateredAt    = nil,
	}
	--[[ СЕЙВ: грядка из сейва приходит с атрибутами Crop/Watered/GrownSeconds —
	     поднимаем из них состояние, иначе посадка и рост терялись при загрузке. ]]
	do
		local savedCrop = planter:GetAttribute("Crop")
		if type(savedCrop) == "string" and savedCrop ~= "" then
			st.crop = savedCrop
			st.watered = planter:GetAttribute("Watered") == true
			st.grownSeconds = tonumber(planter:GetAttribute("GrownSeconds")) or 0
			st.lastTick = os.time()
		end
	end
	planters[planter] = st

	applyBase(planter, false)
	st.shownWatered = false
	publishState(planter, st)

	planter.AncestryChanged:Connect(function()
		if not planter.Parent then planters[planter] = nil end
	end)

	print(("%s грядка готова: %s"):format(LOG_TAG, planter:GetFullName()))
end

-- ─── Действия игрока ───
-- ⚠️ ПОРЯДОК: СНАЧАЛА ПОЛИТЬ, ПОТОМ САЖАТЬ.
-- Раньше посадка стояла первой, и семя уходило в сухую землю: росток появлялся,
-- но не рос, пока грядку не польёшь, — выглядело как сломанная грядка.
-- Теперь в сухую посадить нельзя вовсе.
--
-- Ровно один порядок состояний: сухо → полито → посажено → растёт → спелое.
-- ⚠️ КЛИК ДЕЛАЕТ ТО, ЗА ЧЕМ ПРИШЛИ, А НЕ «СЛЕДУЮЩЕЕ ПО СПИСКУ».
-- Действие тут одно на все состояния, и раньше сервер сам решал, что означает
-- нажатие. Пока игрок смотрит на грядку — это честно. Но подсказка квеста могла
-- звать «полей грядку», а грядка к тому моменту уже была полита — и клик, который
-- игрок считал поливом, МОЛЧА сажал свёклу. Со стороны: «поливаю второй раз, а у
-- меня оттуда свёкла и семечко потрачено».
-- Поэтому клиент присылает НАМЕРЕНИЕ (он видит те же атрибуты и рисует по ним
-- подсказку), а сервер сверяет его с настоящим состоянием и делает только то,
-- что просили. Не совпало — не делаем ничего: подсказка на экране обновляется
-- каждый кадр, игрок увидит правду и нажмёт ещё раз.
-- intent = nil означает «решай сам», как раньше: старый клиент не ломается.
local function intentAllows(intent, what)
	return intent == nil or intent == what
end

function PlanterInteract(planter, player, intent)
	local st = planters[planter]
	if not st then return end

	-- 1. Спелое — собираем.
	if st.crop and isRipe(st) then
		if not intentAllows(intent, "harvest") then return end
		local def = Defs[st.crop]
		st.crop, st.grownSeconds, st.shownStage = nil, 0, 0
		-- СБОР СРАЗУ СУШИТ ЗЕМЛЮ. Пока растение стояло, полив держался сам (см.
		-- цикл роста); как только урожай сняли, грядка возвращается в исходное
		-- состояние и снова просит воды под следующую посадку.
		st.watered = false
		st.wateredAt = nil
		applyCrop(planter, nil)
		if _G.AddResourceToInventory then
			_G.AddResourceToInventory(player, def.seed, def.yield, nil)
		end
		if _G.SendInventory then _G.SendInventory(player) end
		publishState(planter, st)
		print(("%s %s собрал %s x%d"):format(LOG_TAG, player.Name, def.seed, def.yield))
		return
	end

	-- 2. Сухо — поливаем. Работает и до посадки, и после (высохшую грядку
	--    надо полить снова, иначе рост стоит).
	if not st.watered then
		if not intentAllows(intent, "water") then return end
		local char = player.Character
		local tool = char and char:FindFirstChildWhichIsA("Tool")
		if not tool or tool:GetAttribute("CupState") ~= "fresh" then
			if _G.Notify then
				_G.Notify({ type = "warn", icon = "💧", title = "Нужна вода",
					body = "Набери чистую воду в кружку" })
			end
			return
		end
		-- через общую ручку: имя сосуда собирается из его же базы, иначе бутылка
		-- после полива превращалась бы в кружку (см. ThirstSystem.setCupState)
		if _G.SetCupState then
			_G.SetCupState(tool, "empty")
		else
			tool:SetAttribute("CupState", "empty")
		end

		st.watered = true
		st.wateredAt = os.time()
		st.lastTick = os.time()
		publishState(planter, st)
		-- Полив был ЕДИНСТВЕННЫМ действием без строки в логе, а разбирать по логу
		-- приходилось именно его: «полил или нет» из вывода было не понять вовсе.
		-- ⚠️ ПОЛИВ ЗАКРЫВАЕТ ТУ ЖЕ ЦЕЛЬ, ЧТО И ГЛОТОК.
		-- Квест про очиститель открывается именно поливом (грядка стоит, лить
		-- нечем), и требовать после этого ВЫПИТЬ воду — значит извести ровно то, за
		-- чем игрок и ходил. Событие общее: purifier:used шлёт и ThirstSystem по
		-- глотку, и мы по поливу (см. QuestCatalog, onboarding_purifier).
		if _G.OnQuestEvent then
			pcall(_G.OnQuestEvent, player, "purifier:used", 1)
		end

		print(("%s %s полил грядку"):format(LOG_TAG, player.Name))
		return
	end

	-- 3. Полито и пусто — сажаем.
	if not st.crop then
		if not intentAllows(intent, "plant") then return end
		local char = player.Character
		local held = char and char:FindFirstChildWhichIsA("Tool")
		local heldKey = held and held:GetAttribute("FoodResource")

		-- СНАЧАЛА СМОТРИМ В РУКИ. На телефоне игрок достаёт картошку и тапает по
		-- грядке — сажаться должно именно то, что он держит, а не первое
		-- попавшееся из инвентаря.
		local pick
		for name, def in pairs(Defs) do
			if def.seed == heldKey then pick = name break end
		end

		if pick then
			-- Тул «одолжен» из стака, поэтому вернуть его в инвентарь нельзя:
			-- помечаем съеденным, иначе FoodSystem вернёт единицу обратно и
			-- посадка выйдет бесплатной.
			held:SetAttribute("Consumed", true)
			held:Destroy()
		else
			-- ⚠️ САМИ ИЗ РЮКЗАКА НИЧЕГО НЕ БЕРЁМ. ЭТО И БЫЛ БАГ «СВЁКЛА ИЗ НИОТКУДА».
			-- Здесь стоял перебор инвентаря: нашлась свёкла или картошка — сажаем её
			-- и списываем. Снаружи это выглядело так: игрок полил грядку, ткнул в неё
			-- ЕЩЁ РАЗ (полить второй раз, как ему кажется), а грядка молча съела
			-- свёклу из рюкзака и вырастила росток. Ни выбора, ни подтверждения.
			-- Хуже того, культура выбиралась перебором pairs, порядок которого не
			-- определён: с картошкой И свёклой в рюкзаке сажалось то одно, то другое.
			-- Посадка — намеренное действие: что игрок ДЕРЖИТ, то и сажает.
			if _G.Notify then
				_G.Notify({ type = "warn", icon = "🌱", title = "Возьми семя в руки",
					body = "Достань из рюкзака картофель или свёклу и нажми по грядке" })
			end
			return
		end
		if _G.SendInventory then _G.SendInventory(player) end

		st.crop = pick
		st.grownSeconds = 0
		st.lastTick = os.time()
		st.shownStage = 0
		publishState(planter, st)

		-- Квест «Свой огород» слушает посадку по НАЗВАНИЮ КУЛЬТУРЫ, чтобы картофель
		-- не закрывал задание про свёклу. Событие шлём отсюда: старая ветка в
		-- GardenSystem осталась за древесными грядками и про Raft_planter не знает —
		-- из-за этого квест на свёклу не закрывался вовсе.
		if _G.OnQuestEvent then
			pcall(_G.OnQuestEvent, player, "planted:" .. pick, 1)
		end

		print(("%s %s посадил %s"):format(LOG_TAG, player.Name, pick))
		return
	end

	-- 4. Растёт и полито — делать нечего, статус на экране это уже говорит.
end

-- Клиент шлёт сюда и клик, и тап, и E — все три пути одинаковые.
gardenActionEvent.OnServerEvent:Connect(function(player, action, target, intent)
	if action ~= "planterAct" then return end
	if typeof(target) ~= "Instance" then return end
	-- намерение — подсказка от клиента, а не приказ: сервер всё равно сверяет его
	-- с настоящим состоянием грядки. Мусор от подделанного клиента просто не
	-- совпадёт ни с одной веткой, и не произойдёт ничего.
	if intent ~= nil and typeof(intent) ~= "string" then intent = nil end
	local st = planters[target]
	if not st then return end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local base = findBase(target)
	if not hrp or not base then return end
	if (hrp.Position - base.Position).Magnitude > REACH then return end

	PlanterInteract(target, player, intent)
end)

-- ─── Цикл роста ───
task.spawn(function()
	while true do
		task.wait(TICK)
		local now = os.time()

		for planter, st in pairs(planters) do
			if not planter.Parent then
				planters[planter] = nil
			else
				-- ⚠️ РОСТ КОПИМ, А НЕ СЧИТАЕМ ОТ ВРЕМЕНИ ПОСАДКИ.
				-- Время идёт только пока грядка полита, поэтому «прошло N секунд
				-- с посадки» ответа не даёт. Накопленное значение корректно
				-- переживает и простой, и сохранение в DataStore.
				if st.watered and st.crop then
					st.grownSeconds = st.grownSeconds + (now - st.lastTick)
				end
				st.lastTick = now

				-- ВЫСЫХАЕТ ТОЛЬКО ПУСТАЯ ГРЯДКА.
				--
				-- Пока в земле что-то растёт, полив держится сам: иначе игрок
				-- посадил, отошёл на минуту — и вернулся к сухой грядке с
				-- остановившимся ростом, которую надо поливать заново. Возни
				-- много, смысла ноль: растение и так требует времени.
				--
				-- Таймер остаётся для случая «полил и не посадил»: политая
				-- пустая земля через WATER_DRY снова просит воды.
				if not st.crop
					and st.watered and st.wateredAt
					and now - st.wateredAt >= WATER_DRY
				then
					st.watered = false
					st.wateredAt = nil
				end

				-- МИР ТРОГАЕМ ТОЛЬКО ПРИ ФАКТИЧЕСКОЙ СМЕНЕ СОСТОЯНИЯ.
				if st.watered ~= st.shownWatered then
					st.shownWatered = st.watered
					applyBase(planter, st.watered)
				end

				local s = st.crop and stageOf(st) or 0
				if s ~= st.shownStage then
					st.shownStage = s
					applyCrop(planter, st.crop, s)
				end

				publishState(planter, st)
			end
		end
	end
end)

-- ─── Подхват грядок в мире ───
local function isPlanter(inst)
	return inst:IsA("Model")
		and (inst.Name == TEMPLATE_NAME or inst:GetAttribute("IsPlanter"))
end

for _, d in ipairs(workspace:GetDescendants()) do
	if isPlanter(d) then register(d) end
end
workspace.DescendantAdded:Connect(function(d)
	if isPlanter(d) then
		task.defer(function()
			if d.Parent then register(d) end
		end)
	end
end)

-- ─── ГРЯДКА ПОСТАВЛЕНА → А ЧЕМ ЕЁ ПОЛИВАТЬ? ───
-- Грядка не растёт без полива, а поливают из кружки ПРЕСНОЙ водой — значит нужен
-- очиститель. Если его на плоту ещё нет, подсказываем прямо здесь, а не ждём,
-- пока игрок упрётся в «Нужна вода» у грядки или пока его застигнет жажда.
--
-- ⚠️ СМОТРИМ НА ПЛОТ, А НЕ НА КВЕСТ ИГРОКА.
-- В сетевой игре очиститель мог поставить кто угодно: спрашивать «выполнил ли
-- ЭТОТ игрок квест про воду» значило бы выдать задание второму игроку на плоту,
-- где очиститель давно стоит. Поставленный очиститель ThirstSystem переименовывает
-- в "Purifier" — по этому имени его и ищем.
local function purifierOnRaft()
	local raft = workspace:FindFirstChild("Raft")
	if not raft then return false end
	for _, d in ipairs(raft:GetDescendants()) do
		if d.Name == "Purifier" or d.Name:find("Destitalor") then return true end
	end
	return false
end

local function onPlanterPlaced(player)
	if purifierOnRaft() then return end
	-- одна подсказка на игрока за сессию: грядок он поставит много
	if player:GetAttribute("FreshWaterHintGiven") then return end
	player:SetAttribute("FreshWaterHintGiven", true)

	if _G.StartDialogue then
		pcall(_G.StartDialogue, player, "FreshWaterThought")
	end
	-- Квест про воду уже есть в каталоге — открываем его, а не заводим новый.
	-- Если игрок его уже закрыл, TrackQuest ничего не активирует: снапшот прячет
	-- выполненные, и лишнего задания не появится.
	if _G.TrackQuest then
		pcall(_G.TrackQuest, player, "onboarding_purifier")
	end
end

-- ─── Установка на плот ───
-- Тем же действием и тем же тулом, что и старая грядка: клиентский призрак,
-- поворот на R и приварка к плоту уже написаны и менять их незачем — меняется
-- только модель и то, что она умеет.
gardenActionEvent.OnServerEvent:Connect(function(player, action, target)
	if action ~= "placePlanter" then return end

	local char = player.Character
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Garden" then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end
	if typeof(target) ~= "CFrame" then return end

	local template = ReplicatedStorage:FindFirstChild(TEMPLATE_NAME)
		or ReplicatedStorage:FindFirstChild(TEMPLATE_NAME, true)
	if not template then
		warn(LOG_TAG .. " шаблона " .. TEMPLATE_NAME .. " нет в ReplicatedStorage — "
			.. "грядку не поставить")
		return
	end

	local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)
	local placed = template:Clone()
	placed.Name = TEMPLATE_NAME
	placed:SetAttribute("IsPlanter", true)
	placed:SetAttribute("PlacedBy", player.UserId)
	for _, d in ipairs(placed:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
	end

	if placed:IsA("Model") and not placed.PrimaryPart then
		local bb = placed:GetBoundingBox()
		placed.WorldPivot = CFrame.new(bb.Position)
	end
	placed:PivotTo(worldCF)
	if PlaceCheck.refuseIfBlocked(placed, raft, player) then return end   -- в предмет ставить нельзя
	placed.Parent = raft

	-- ⚠️ ОРИЕНТАЦИЮ ЗАДАЁМ ЯВНО, А НЕ НАДЕЕМСЯ НА ПИВОТ.
	--
	-- Шаблон я выпрямил, но поставленная грядка всё равно вставала на ребро:
	-- поворот возвращался по дороге. Путь длинный — призрак на клиенте берёт
	-- поворот из bounding box, домножает на курс плота, отдаёт CFrame в
	-- пространстве плота, сервер разворачивает его обратно и кладёт через
	-- PivotTo, — и на каждом шаге есть где потерять или задвоить поворот.
	--
	-- Гоняться за этим по всей цепочке смысла нет: требование простое и
	-- окончательное — грядка ЛЕЖИТ ПЛАШМЯ на палубе и может быть повёрнута
	-- только вокруг вертикали. Здесь мы это и записываем, отбрасывая наклон и
	-- крен целиком.
	local placedBase = findBase(placed)
	if placedBase then
		local _, yaw = worldCF:ToEulerAnglesYXZ()
		local before = placedBase.CFrame
		placedBase.CFrame = CFrame.new(before.Position) * CFrame.Angles(0, yaw, 0)
		local bx, by, bz = before:ToEulerAnglesYXZ()
		print(("%s поставлена: было (%.0f°, %.0f°, %.0f°) → стало (0°, %.0f°, 0°)")
			:format(LOG_TAG, math.deg(bx), math.deg(by), math.deg(bz), math.deg(yaw)))
	end

	-- Приварка к плоту — как у остальных построек: якорь внутри сборки плота
	-- заморозил бы плот целиком.
	local primary = raft.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity
	local parts = {}
	for _, d in ipairs(placed:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	if placed:IsA("BasePart") then table.insert(parts, placed) end
	for _, p in ipairs(parts) do p.Anchored = true end
	for _, p in ipairs(parts) do
		p.Massless = true
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = primary, p
		w.Parent = p
	end
	for _, p in ipairs(parts) do p.Anchored = false end
	primary.AssemblyLinearVelocity = linVel
	primary.AssemblyAngularVelocity = angVel
	RaftShake.notify()

	tool:Destroy()
	if _G.SendInventory then _G.SendInventory(player) end
	register(placed)
	onPlanterPlaced(player)
end)

--[[ ЧАЙКА СЪЕЛА ПОСАДКУ (SeagullAI). Растение пропадает на любой стадии, игроку
     ничего не достаётся. Полив не трогаем: грядка остаётся политой, если была, —
     наказание и так в потерянном урожае. Возвращает true, если было что есть. ]]
_G.PlanterEatCrop = function(planter)
	local st = planters[planter]
	if not (st and st.crop) then return false end
	local eaten = st.crop
	st.crop, st.grownSeconds, st.shownStage = nil, 0, 0
	applyCrop(planter, nil)
	publishState(planter, st)
	print(("%s чайка съела посадку: %s"):format(LOG_TAG, tostring(eaten)))
	return true
end

print(LOG_TAG .. " ready (данные → визуал, один цикл на все грядки)")
