local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- GrillFoodPlace.client.lua
-- ЕДА НА РЕШЁТКУ МАНГАЛА ИЗ РУК, с предпросмотром — как при обычной стройке.
--
--   * В руках сырая рыба/мясо, курсор на мангале → на свободном месте решётки
--     появляется зелёный призрак того самого куска. ЛКМ — положить.
--   * На решётке есть готовое, курсор на мангале → подсказка «ЛКМ — забрать».
--     Клик забирает кусок И сразу берёт его в руки, чтобы съесть.
--
-- Почему клик ловим здесь, а не ClickDetector'ом на мангале: ClickDetector НЕ
-- срабатывает, пока экипирован Tool. С мясом в руках по мангалу нельзя было
-- кликнуть вообще — ради этого весь скрипт и нужен.

local Players              = game:GetService("Players")
local ReplicatedStorage     = game:GetService("ReplicatedStorage")
-- посадка еды на решётку считается тем же модулем, что и на сервере
local GrillFit = require(ReplicatedStorage:WaitForChild("GrillFit"))
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))
local RunService            = game:GetService("RunService")
local SoundService          = game:GetService("SoundService")
local ContextActionService  = game:GetService("ContextActionService")

local player    = Players.LocalPlayer
local mouse     = player:GetMouse()
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))
local camera    = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

-- Маркер загрузки: если этой строки нет в консоли, скрипт не доехал до плейса
-- (или упал ещё раньше) — и искать причину надо там, а не в логике ниже.
print("[Мангал/клиент] загружен")

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction", 10)
if not cupActionEvent then
	warn("[Мангал/клиент] нет ремоута CupAction — установка еды на мангал работать не будет")
	return
end
-- ⚠️ С ТАЙМАУТОМ, А НЕ БЕСКОНЕЧНО.
-- Голый WaitForChild здесь блокировал ВЕСЬ скрипт: если ремоут почему-то не
-- создался, выполнение не доходило даже до подключения к RenderStepped — не было
-- ни призрака, ни статус-бара, ни диагностики, и выглядело это как «ничего не
-- работает» без единой строчки в консоли. Ремоут нужен только для того, чтобы
-- взять готовое в руки; без него остальное обязано работать.
local equipFoodEvent = ReplicatedStorage:WaitForChild("EquipFoodAsTool", 10)
if not equipFoodEvent then
	warn("[Мангал/клиент] нет ремоута EquipFoodAsTool — готовое не будет автоматически "
		.. "попадать в руки, остальное работает")
end

-- Инвентарь игрока: тот же поток, что кормит InventoryUI. Нужен, чтобы не
-- предлагать подбросить бревно, когда брёвен нет.
local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate", 10)
local myInventory = {}
local gotInventory = false
if inventoryEvent then
	inventoryEvent.OnClientEvent:Connect(function(inv)
		myInventory = inv or {}
		gotInventory = true
	end)
end
-- nil = «ещё не знаем». До первого пакета инвентаря молчим: считать пустой
-- стартовый стол за «брёвен нет» нельзя — подсказка была бы спрятана у игрока,
-- у которого брёвна есть, просто пакет ещё не пришёл.
local function logCount()
	if not gotInventory then return nil end
	return tonumber(myInventory.Log) or 0
end

-- Диагностика: печатает, на чём именно обрывается цепочка «еда в руках →
-- курсор на решётке → призрак → клик». Выключить, когда механика устоится.
local GRILL_DEBUG = true
local lastDebug = ""
local function dbg(msg)
	if not GRILL_DEBUG or msg == lastDebug then return end
	lastDebug = msg
	print("[Мангал/клиент] " .. msg)
end

local GRILL_NAME  = "Raft_grill"
-- ДВА ВАРИАНТА МАНГАЛА (= VARIANTS в GrillSystem): обычный и бочка. У бочки своя
-- решётка и вчетверо больше мест — имена и числа берём по имени модели.
local VARIANTS = {
	Raft_grill        = { grate = "raft_grill_grate",        slots = 2 },
	Raft_grill_barrel = { grate = "raft_grill_barrel_grate", slots = 4 },
}
local GRATE_NAME  = "raft_grill_grate"   -- запасной вариант, если модель не опознана
local GRATE_SLOTS = 2

local function variantOf(grill)
	return (grill and VARIANTS[grill.Name]) or VARIANTS[GRILL_NAME]
end
local function grateNameOf(grill) return variantOf(grill).grate end
local function slotsOf(grill) return variantOf(grill).slots end
local RAY_DIST    = 250
local REACH       = 14     -- = GrillSystem.CLICK_RANGE

local ghost, ghostSlotCF
local ghostFitted = false   -- масштаб под слот уже применён к текущему призраку
local hoverGrill, hoverCooked, hoverLit, hoverSlot

-- ─── Что в руках ──────────────────────────────────────────────────
-- Ключ ресурса лежит в атрибуте FoodResource — его вешает FoodSystem, когда
-- превращает стак в Tool. Сырое = "<Тип>_Fish", "Meat" или овощ с грядки.
-- ⚠️ СПИСОК ДЕРЖАТЬ РАВНЫМ isRawFood в GrillSystem: сервер овощи принимал, а
-- клиент про них не знал — с картошкой в руках наводка молча не срабатывала,
-- призрака не было, и клик уходил в рот вместо решётки.
local RAW_VEG = { Potato = true, Beet = true }
local function isRawFood(name)
	if type(name) ~= "string" then return false end
	if name == "Meat" or name == "Chicken_drumstick" then return true end
	if RAW_VEG[name] then return true end
	return #name > 5 and name:sub(-5) == "_Fish"
end

local function heldRawFood()
	local char = player.Character
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	if not tool then return nil end
	local key = tool:GetAttribute("FoodResource")
	if not isRawFood(key) then return nil end
	return tool, key
end

-- ─── Мангал под курсором ──────────────────────────────────────────
local function grillUnderMouse()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- ⚠️ СПИСОК СОБИРАЕМ БЕЗ ДЫР.
	-- Было { ghost, player.Character }. Пока призрака нет — а его нет всегда до
	-- первого наведения — первым элементом оказывался nil, и массив получался
	-- дырявым: фильтр исключений фактически пустел. Луч упирался в МОДЕЛЬ ЕДЫ
	-- В РУКАХ (она занимает пол-экрана перед камерой), мангал не находился
	-- никогда, а значит не было ни призрака, ни статус-бара, ни доклада «целюсь
	-- в решётку» — и клик уходил в Tool.Activated, то есть в рот.
	-- С пустыми руками загораживать было нечем, поэтому там всё «работало».
	local ignore = {}
	if player.Character then table.insert(ignore, player.Character) end
	if ghost then table.insert(ignore, ghost) end
	params.FilterDescendantsInstances = ignore

	local res = workspace:Raycast(ray.Origin, ray.Direction * RAY_DIST, params)
	if not res or not res.Instance then return nil end

	-- Ищем модель мангала вверх по предкам. Имя сверяем БЕЗ учёта регистра и
	-- дополнительно требуем внутри решётку: модель могли переименовать или
	-- склонировать с суффиксом, и жёсткое сравнение с "Raft_grill" тогда
	-- молча ничего не находило бы. Рекурсивный поиск решётки безопасен,
	-- потому что запускается только для моделей со словом "grill" в имени.
	-- Заодно запоминаем, не попали ли ПРЯМО в лежащий кусок: это самый честный
	-- ответ на вопрос «на что смотрит игрок», точнее любых расстояний до центров
	-- мест. Работает, когда кусок торчит за габариты решётки — а он торчит.
	local hitFood
	local inst = res.Instance
	while inst and inst ~= workspace do
		if inst.Name == "GrillFood" then hitFood = inst end
		if inst:IsA("Model") and inst.Name:lower():find("grill", 1, true) then
			if inst:FindFirstChild(grateNameOf(inst), true) then
				return inst, res.Position, hitFood
			end
		end
		inst = inst.Parent
	end
	return nil
end

local function inReach(grill)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	-- ⚠️ РАССТОЯНИЕ МЕРЯЕМ ДО ДЕТАЛИ, А НЕ ДО Model:GetPivot().
	-- WorldPivot модели фиксируется в момент установки и НЕ едет следом за
	-- деталями, которые тащит физика плота. Плот уплывает — пивот остаётся на
	-- месте в океане, и мангал прямо под носом уже через полминуты считался
	-- «далёким»: наведение не срабатывало, доклад «целюсь в решётку» на сервер
	-- не уходил, и клик спокойно уезжал в Tool.Activated, то есть в рот.
	-- Позиция BasePart всегда актуальна — сервер (playerNearGrill) так и считает.
	local ref = grill:FindFirstChild(grateNameOf(grill), true)
		or grill:FindFirstChildWhichIsA("BasePart", true)
	if not ref then return false end
	return (hrp.Position - ref.Position).Magnitude <= REACH + 4
end

-- ─── Места на решётке ─────────────────────────────────────────────
-- Повтор slotCF с сервера: решётка и её размер реплицируются, так что клиент
-- считает те же две точки и призрак ложится ровно туда, куда встанет кусок.
local function slotCF(grate, index, count)
	local cf, size = grate.CFrame, grate.Size
	local alongX = size.X >= size.Z
	local span = alongX and size.X or size.Z
	local n = count or GRATE_SLOTS
	local t = (n > 1) and ((index - 0.5) / n - 0.5) or 0
	local off = t * span * 0.88
	local local_ = alongX and Vector3.new(off, size.Y * 0.5, 0)
		or Vector3.new(0, size.Y * 0.5, off)
	return cf * CFrame.new(local_)
end

-- ⚠️ ПОЗИЦИЮ БЕРЁМ У ДЕТАЛИ, А НЕ У Model:GetPivot().
-- Кусок приварен к решётке и едет вместе с плотом, а WorldPivot модели остаётся
-- там, где кусок положили. Через полминоты плавания расстояние до места на
-- решётке становилось огромным, место считалось ПУСТЫМ — и вместо «забрать
-- готовое» клиент предлагал положить новое. Ровно это и ощущалось как
-- «неправильный хитбокс мяса».
local function foodPos(f)
	if f:IsA("BasePart") then return f.Position end
	local p = f.PrimaryPart or f:FindFirstChildWhichIsA("BasePart", true)
	return p and p.Position or nil
end

-- Раскладка решётки: что лежит на каждом месте. Занятость считаем по реальным
-- кускам GrillFood в модели, а не по своему счётчику — сервер единственный
-- источник правды, и после чужого клика клиент не разъедется.
local function grateInfo(grill)
	local grate = grill:FindFirstChild(grateNameOf(grill), true)
	if not grate or not grate:IsA("BasePart") then return nil end
	local slots = slotsOf(grill)

	local foods = {}
	for _, c in ipairs(grill:GetChildren()) do
		if c.Name == "GrillFood" then table.insert(foods, c) end
	end

	-- ГОРИТ ЛИ МАНГАЛ — по атрибуту от сервера.
	-- Раньше искали внутри модели включённый Fire. Своих Fire/Smoke в модели
	-- больше нет, а новый огонь собран на ParticleEmitter — проверка навсегда
	-- давала «холодно»: над горящим костром висело «Разожги огонь», и еду
	-- положить было нельзя. Запасной перебор оставлен для старых мангалов,
	-- поставленных до появления атрибута.
	local lit = grill:GetAttribute("Lit")
	if lit == nil then
		lit = false
		for _, d in ipairs(grill:GetDescendants()) do
			if (d:IsA("Fire") or d:IsA("ParticleEmitter")) and d.Enabled then
				lit = true
				break
			end
		end
	end

	local occ = {}   -- [место] = модель еды либо nil
	-- радиус «это место занято» — половина шага между местами
	local reach = math.max(grate.Size.X, grate.Size.Z) * 0.88 / slots * 0.5
	for i = 1, slots do
		local pos = slotCF(grate, i, slots).Position
		for _, f in ipairs(foods) do
			local p = foodPos(f)
			if p and (p - pos).Magnitude < reach then occ[i] = f break end
		end
	end

	return grate, occ, lit, slots
end

-- ТОЧКА ПРИЦЕЛА НА ПЛОСКОСТИ РЕШЁТКИ.
-- Луч попадает в ВЕРХ хитбокса, а он на HITBOX_HEIGHT выше решётки. Под косым
-- углом камеры это смещает точку вбок на пару студов, и выбранное место
-- «уезжало» от того, куда игрок реально целится. Поэтому пересекаем луч не с
-- геометрией, а с плоскостью самой решётки.
local function aimPointOnGrate(grate, fallback)
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local n = grate.CFrame.UpVector
	local denom = ray.Direction:Dot(n)
	if math.abs(denom) < 1e-4 then return fallback end
	local p0 = (grate.CFrame * CFrame.new(0, grate.Size.Y * 0.5, 0)).Position
	local t = (p0 - ray.Origin):Dot(n) / denom
	if t < 0 then return fallback end
	return ray.Origin + ray.Direction * t
end

-- МЕСТО, НА КОТОРОЕ СМОТРИТ ИГРОК. Раньше кусок клался в первое свободное, и
-- выбрать сторону решётки было нельзя. Теперь берём место, ближайшее к точке
-- прицела, — куда навёл, туда и ляжет.
local function slotUnderPoint(grate, hitPos, slots)
	slots = slots or GRATE_SLOTS
	local best, bestD
	for i = 1, slots do
		local d = (slotCF(grate, i, slots).Position - hitPos).Magnitude
		if not bestD or d < bestD then best, bestD = i, d end
	end
	return best
end

-- ─── Призрак ──────────────────────────────────────────────────────
local function destroyGhost()
	if ghost then ghost:Destroy() ghost = nil end
	ghostSlotCF = nil
end

-- Имена 3D-шаблонов еды в ReplicatedStorage (= FOOD_TEMPLATES в GrillSystem).
local FOOD_TEMPLATES = {
	Blue_Fish      = "Blue Fish",
	Carp_Fish      = "Carp Fish",
	Foil_Fish      = "Foil Fish",
	Jelly_Fish     = "Jelly Fish",
	Legendary_Fish = "Legendary Fish",
	Seabass_Fish   = "Seabass Fish",
	Tilapia_Fish   = "Tilapia Fish",
	Meat           = "Meat",
	Chicken_drumstick = "Chicken_drumstick",
}

-- ПРИЗРАК СТРОИМ В ТРИ ПОПЫТКИ, чтобы предпросмотр был ВСЕГДА.
-- Раньше был только первый способ, и если он срывался (например, у детали
-- Archivable = false — тогда Clone() возвращает nil), призрак просто не
-- появлялся, и игрок не понимал, куда вообще ляжет кусок.
--   1) клон содержимого тула — точная копия того, что в руках;
--   2) шаблон из ReplicatedStorage — то, что реально положит сервер;
--   3) простой зелёный блок — хуже видно, что кладём, но ВИДНО КУДА.
local function ghostFromTool(tool, holder)
	for _, c in ipairs(tool:GetChildren()) do
		if c:IsA("BasePart") or c:IsA("Model") then
			-- Archivable правим локально: на клиенте это не реплицируется,
			-- зато Clone() перестаёт возвращать nil.
			if not c.Archivable then c.Archivable = true end
			local clone = c:Clone()
			if clone then clone.Parent = holder end
		end
	end
	return #holder:GetChildren() > 0
end

local function ghostFromTemplate(key, holder)
	local name = FOOD_TEMPLATES[key] or key
	local t = AssetFind.find(name)
	if not t then
		local lower = name:lower()
		for _, d in ipairs(ReplicatedStorage:GetChildren()) do
			if d.Name:lower() == lower and (d:IsA("Model") or d:IsA("BasePart")) then
				t = d
				break
			end
		end
	end
	if not t then return false end
	if not t.Archivable then t.Archivable = true end
	local clone = t:Clone()
	if not clone then return false end
	clone.Parent = holder
	return true
end

local function ghostFallback(holder)
	local box = Instance.new("Part")
	box.Size = Vector3.new(2.4, 0.8, 2.4)
	box.Shape = Enum.PartType.Block
	box.Parent = holder
	return true
end

local function createGhost(tool, key)
	destroyGhost()

	local holder = Instance.new("Model")
	holder.Name = "GrillFoodGhost"
	local ok = ghostFromTool(tool, holder)
	if not ok then
		dbg("призрак: клон из тула не вышел, беру шаблон")
		ok = ghostFromTemplate(key, holder)
	end
	if not ok then
		dbg("призрак: шаблона нет, рисую блок-заглушку")
		ok = ghostFallback(holder)
	end
	if not ok then holder:Destroy() return end

	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = 0.5
			d.CanCollide = false
			d.Anchored = true
			d.Massless = true
			d.Color = Color3.fromRGB(80, 255, 80)
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") then
			d:Destroy()
		elseif d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
			d:Destroy()
		elseif d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Smoke") then
			d.Enabled = false
		end
	end
	local bb = holder:GetBoundingBox()
	holder.WorldPivot = CFrame.new(bb.Position)
	holder.Parent = workspace
	ghost = holder
	ghostFitted = false     -- масштаб под слот применим, когда узнаем сам мангал
end

-- ⚠️ ПРИЗРАК УЖИМАЕТСЯ ТАК ЖЕ, КАК ЛЯЖЕТ ЕДА.
-- Раньше он показывал кусок в авторском размере, а сервер клал ужатый под слот —
-- на предпросмотре было одно, по факту другое. Расчёт теперь общий (GrillFit),
-- и применяем его к призраку ровно один раз: масштаб абсолютный, повторный вызов
-- ужимал бы уже ужатое.
local function fitGhostTo(grill, grate)
	if not ghost or ghostFitted or not grate then return end
	ghostFitted = true
	local _, s = ghost:GetBoundingBox()
	local k = GrillFit.scaleFor(s, GrillFit.slotWidth(grate.Size, slotsOf(grill)))
	if k < 1 then
		pcall(function() ghost:ScaleTo(ghost:GetScale() * k) end)
	end
end

local function setGhostColor(ok)
	if not ghost then return end
	local c = ok and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
	for _, d in ipairs(ghost:GetDescendants()) do
		if d:IsA("BasePart") then d.Color = c end
	end
end

-- ─── Статус-бар над хотбаром ──────────────────────────────────────
-- Пишет, на что игрок смотрит: сырое жарится, готовое можно забрать, огня нет.
-- Место выбрано над инвентарём — там взгляд игрока и так во время готовки.
local hintGui = Instance.new("ScreenGui")
hintGui.Name = "GrillFoodHint"
hintGui.ResetOnSpawn = false
hintGui.DisplayOrder = 8
hintGui.Enabled = false
hintGui.Parent = playerGui

local hintLabel = Instance.new("TextLabel")
hintLabel.AnchorPoint = Vector2.new(0.5, 1)
-- Прижат к самому хотбару: подпись к инвентарю, а не отдельная плашка на экране.
hintLabel.Position = UDim2.new(0.5, 0, 1, -76)
hintLabel.Size = UDim2.fromOffset(340, 26)
hintLabel.BackgroundTransparency = 1 -- без подложки, только текст
hintLabel.Font = Enum.Font.GothamBold
hintLabel.TextSize = 17
hintLabel.Text = ""
hintLabel.Parent = hintGui

-- ⚠️ Подсказка уступает диалогу: пока собеседник говорит, она поднимается
-- над его окном. Правило одно на всю игру — см. ReplicatedStorage/HudDock.
local HudDock = require(game:GetService("ReplicatedStorage"):WaitForChild("HudDock"))
HudDock.keepAbove(hintLabel, 12)

-- ЧЁРНАЯ ОБВОДКА ПО БУКВАМ — теперь это ровно то, что нужно.
-- Подложки нет, и текст ложится прямо на пламя и доски; без контура он бы там
-- терялся. Режим Contextual (по умолчанию) обводит сами глифы — раньше это
-- мешало, потому что обводка была цветная и слипалась с текстом того же
-- оттенка. Чёрный контур на светлом тексте, наоборот, и есть читаемость.
local hintStroke = Instance.new("UIStroke")
hintStroke.Thickness = 2.5
hintStroke.Color = Color3.fromRGB(0, 0, 0)
hintStroke.Transparency = 0.15
hintStroke.Parent = hintLabel

-- Состояние передаём цветом САМОГО ТЕКСТА: рамки больше нет.
local COLOR_RAW    = Color3.fromRGB(255, 185, 110)
local COLOR_READY  = Color3.fromRGB(150, 255, 150)
local COLOR_PLAIN  = Color3.fromRGB(255, 235, 190)

local function setHint(text, color)
	if not text then hintGui.Enabled = false return end
	hintLabel.Text = text
	hintLabel.TextColor3 = color or COLOR_PLAIN
	hintGui.Enabled = true
end

-- ─── Доклад серверу «целюсь в мангал» ─────────────────────────────
-- Пока курсор на решётке, FoodSystem не должен давать съесть то, что в руках:
-- клик там означает «положить жарить». Клиент отменить активацию тула не может,
-- поэтому просто отмечается на сервере, а запрет стоит там (см. _G.IsAimingAtGrill).
-- Отметка протухает за 1.5 с — обновляем чаще, но не каждый кадр, чтобы не
-- забивать канал.
local AIM_REFRESH = 0.4
local lastAimSent, lastAimGrill = 0, nil

local function reportAim(grill)
	local now = os.clock()
	if grill == lastAimGrill and now - lastAimSent < AIM_REFRESH then return end
	lastAimGrill, lastAimSent = grill, now
	cupActionEvent:FireServer("grillAim", grill)
end

-- ─── Каждый кадр ──────────────────────────────────────────────────
-- Объявлено заранее: сама функция ниже (ей нужны hoverGrill/ghost), а звать её
-- надо отсюда.
local setClickBound

RunService.RenderStepped:Connect(function()
	local tool, heldKey = heldRawFood()
	local grill, hitPos, hitFood = grillUnderMouse()
	hoverGrill, hoverCooked, hoverSlot = nil, false, nil

	-- ВНЕ МАНГАЛА НЕТ НИЧЕГО: ни призрака, ни статус-бара, ни перехвата клика,
	-- и запрет на еду с сервера тоже снимается — иначе рядом с грилем игрок
	-- вообще не смог бы поесть.
	local function idle()
		destroyGhost()
		setHint(nil)
		hoverLit = false
		setClickBound(false)
		reportAim(nil)
	end

	if not grill then
		idle()
		dbg("курсор не на мангале" .. (tool and " (еда в руках есть)" or " (еды в руках нет)"))
		return
	end
	if not inReach(grill) then idle() dbg("мангал далеко") return end

	local grate, occ, lit, slots = grateInfo(grill)
	if not grate then idle() dbg("нет решётки '" .. grateNameOf(grill) .. "' в модели") return end
	slots = slots or GRATE_SLOTS

	-- Если луч попал ПРЯМО в кусок — работаем с его местом, а не с ближайшим к
	-- точке прицела: кусок торчит за габариты решётки, и по расстоянию до центра
	-- он нередко «принадлежал» соседнему месту.
	local foodSlot
	if hitFood then
		for i = 1, slots do
			if occ[i] == hitFood then foodSlot = i break end
		end
	end
	local slot = foodSlot or slotUnderPoint(grate, aimPointOnGrate(grate, hitPos), slots)

	-- Когда ткнули в кусок, но сопоставить его с местом не вышло, шлём nil:
	-- сервер тогда заберёт всё готовое. Это лучше, чем назвать НЕ ТО место и
	-- снять чужой кусок.
	hoverGrill, hoverLit = grill, lit
	hoverSlot = hitFood and foodSlot or slot
	-- Отмечаемся ДО любых ранних выходов: пока курсор на мангале, еду в руках
	-- есть нельзя, даже если призрака построить не удалось.
	reportAim(grill)

	-- ── На выбранном месте уже что-то лежит: показываем его состояние ──
	-- Кусок под лучом главнее раскладки по местам: если игрок ткнул в мясо,
	-- значит он имеет в виду именно его, даже если по геометрии оно съехало.
	local here = hitFood or occ[slot]
	if here then
		destroyGhost()
		local cooked = here:GetAttribute("Cooked") and true or false
		hoverCooked = cooked
		if cooked then
			setHint("Готово — ЛКМ забрать", COLOR_READY)
		else
			setHint(lit and "Сырое — жарится" or "Сырое — огонь погас", COLOR_RAW)
		end
		setClickBound(true)
		dbg(cooked and "навёл на готовое" or "навёл на сырое")
		return
	end

	-- ── Место свободно: предпросмотр установки ──
	if not tool then
		destroyGhost()
		setHint(nil)
		setClickBound(false)
		dbg("в руках нет сырой еды (нужен атрибут FoodResource: *_Fish или Meat)")
		return
	end

	if not ghost then createGhost(tool, heldKey) end
	if not ghost then
		setHint(nil)
		setClickBound(false)
		dbg("не удалось построить призрак из тула в руках")
		return
	end

	-- ужимаем под слот ДО расчёта подъёма: высота после ужатия другая
	fitGhostTo(hoverGrill, grate)
	local _, gsize = ghost:GetBoundingBox()
	ghostSlotCF = slotCF(grate, slot, slots) * CFrame.new(0, gsize.Y * 0.5, 0)
	ghost:PivotTo(ghostSlotCF)
	-- Красный призрак = мангал не горит. Сервер сырое в холодный мангал не
	-- примет, и без этой подсказки клик выглядел бы просто сломанным.
	setGhostColor(lit)
	-- клавишу не называем: на мобильной версии её нет, кнопку рисует ProximityPrompt
	setHint(lit and "ЛКМ — положить на решётку" or "Разожги огонь — подкинь бревно",
		lit and COLOR_READY or COLOR_RAW)
	setClickBound(true)
	dbg(lit and ("готов к установке на место " .. slot) or "мангал не горит")
end)

-- ─── Клик ─────────────────────────────────────────────────────────
-- ПЕРЕХВАТЫВАЕМ ЛКМ РАНЬШЕ ТУЛА, а не слушаем mouse.Button1Down.
-- Пока еда экипирована, клик — это Tool.Activated, то есть «съесть». Обычный
-- слушатель мыши не отменяет активацию: игрок целился в решётку, а мясо
-- отправлялось в рот. ContextActionService с приоритетом выше тулового
-- (Default = 2000) съедает нажатие до того, как его увидит Tool.
--
-- Привязку держим ТОЛЬКО пока курсор реально на мангале: иначе игрок вообще
-- не смог бы поесть, стоя рядом с грилем.
local CLICK_ACTION = "GrillFoodClick"
local clickBound = false
local lastClickAt = 0

-- Само действие. Возвращает true, если клик обработан (тогда его надо съесть).
-- Дебаунс нужен потому, что клик может прийти ДВАЖДЫ: из привязки CAS и из
-- запасного mouse.Button1Down (см. ниже).
local function doGrillClick()
	if not hoverGrill then return false end
	local now = os.clock()
	if now - lastClickAt < 0.25 then return true end

	if hoverCooked then
		lastClickAt = now
		-- Забираем ИМЕННО тот кусок, на который навели, а не всё готовое разом.
		cupActionEvent:FireServer("grillTake", hoverGrill, hoverSlot)
		dbg("клик: забираю готовое с места " .. tostring(hoverSlot))
		return true
	end

	-- Холодный мангал сырое не примет — гасим клик, но еду не тратим.
	if ghost and not hoverLit then
		lastClickAt = now
		dbg("клик: мангал не горит, ставить нечего")
		return true
	end

	if ghost and ghostSlotCF and heldRawFood() then
		lastClickAt = now
		cupActionEvent:FireServer("grillPutHeld", hoverGrill, hoverSlot)
		destroyGhost()
		local folder = (SoundService:FindFirstChild("Building") or SoundService:FindFirstChild("Building", true))
		local snd = folder and folder:FindFirstChild("Place_Block")
		if snd then snd:Play() end
		dbg("клик: кладу на решётку")
		return true
	end

	return false
end

local function onGrillClick(_, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if doGrillClick() then return Enum.ContextActionResult.Sink end
	return Enum.ContextActionResult.Pass
end

-- ЗАПАСНОЙ ПУТЬ. Перехват через CAS отвечает за то, чтобы клик не дошёл до
-- Tool.Activated (иначе мясо съедалось бы вместо установки), но полагаться
-- только на него нельзя: если привязка почему-то не получит нажатие, механика
-- просто не работала бы — ровно то, что и наблюдалось. Button1Down приходит в
-- любом случае, а дебаунс не даёт сработать дважды.
-- Гонку «съел или положил» на сервере разбирает флаг Consumed.
GamepadInput.onPrimary(mouse, function()
	doGrillClick()
end)

function setClickBound(on)
	if on == clickBound then return end
	clickBound = on
	if on then
		ContextActionService:BindActionAtPriority(
			CLICK_ACTION, onGrillClick, false,
			Enum.ContextActionPriority.High.Value + 1,
			Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	else
		ContextActionService:UnbindAction(CLICK_ACTION)
	end
end

-- ─── «Подбросить бревно» только когда бревно есть ─────────────────
--
-- Сервер держит подсказку включённой, пока в мангале меньше MAX_LOGS — он не
-- знает, у кого из игроков есть брёвна. Игрок с пустым инвентарём видел
-- «Подбросить бревно», жал E, и НИЧЕГО не происходило: addLog молча выходит,
-- если Log = 0. Гасим подсказку локально: prompt.Enabled, выставленный на
-- клиенте, не реплицируется, поэтому другим игрокам она остаётся видна.
--
-- Итоговое значение считаем КАЖДЫЙ раз из двух источников:
--   • WantEnabled — желание сервера (в мангале есть место под бревно);
--   • есть ли бревно лично у нас.
-- Раньше клиент только ГАСИЛ подсказку и никогда не возвращал: сервер
-- переписывает Enabled лишь при смене числа брёвен в мангале, а игрок приносил
-- дрова, ничего в мангале не меняя, — и подсказка не появлялась уже никогда.
local PROMPT_POLL = 0.3
task.spawn(function()
	while true do
		task.wait(PROMPT_POLL)
		local n = logCount()
		if n then -- до первого пакета инвентаря не вмешиваемся
			local raft = workspace:FindFirstChild("Raft")
			for _, m in ipairs(raft and raft:GetChildren() or {}) do
				if m:IsA("Model") and m.Name:lower():find("grill", 1, true) then
					for _, d in ipairs(m:GetDescendants()) do
						if d:IsA("ProximityPrompt") then
							--[[ ⚠️ БЕЗ БРЁВЕН ПОДСКАЗКУ НЕ ПРЯЧЕМ, А ПЕРЕИМЕНОВЫВАЕМ.
							     Спрятанная подсказка читалась как «мангал сломался»:
							     дрова прогорели, кнопка исчезла, и игрок не понимал,
							     что делать. Теперь она остаётся на месте, а текст
							     говорит, чего не хватает; нажатие без брёвен сервер
							     и так отбивает уведомлением «Нет брёвен». ]]
							local want = d:GetAttribute("WantEnabled")
							local shouldBe = (want ~= false)
							if d.Enabled ~= shouldBe then d.Enabled = shouldBe end
							local text = (n > 0) and "Подбросить бревно" or "Нужно бревно"
							if d.ActionText ~= text then d.ActionText = text end
						end
					end
				end
			end
		end
	end
end)

cupActionEvent.OnClientEvent:Connect(function(action, key)
	-- Сервер забрал готовое и говорит, что именно: берём это в руки тем же
	-- путём, что и обычная экипировка еды из инвентаря.
	if action == "grillTook" and type(key) == "string" and equipFoodEvent then
		equipFoodEvent:FireServer(key)
	end
end)
