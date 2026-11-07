local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- PurifierQuestHint.client.lua
-- Пошаговая подсказка для второго онбординг-квеста «Fresh Water»
-- (onboarding_purifier): скрафть Кружку → скрафть Очиститель воды →
-- залей морскую воду. Включается/выключается кнопкой «?» на HUD-трекере
-- (TrackerCard.client.lua) через _G.PurifierHintSetEnabled(on);
-- текущее состояние отдаёт _G.PurifierHintEnabled().
--
-- Пока подсказка включена:
--   • золотое пульсирующее кольцо висит над UI-элементом, куда игроку
--     нужно нажать: кнопка-рюкзак (открыть инвентарь) → вкладка
--     категории крафта (Misc / Technology) → кнопка Craft у нужного
--     рецепта → слот хотбара с инструментом;
--   • баннер сверху экрана описывает текущий шаг (AutoLocalize, как у
--     подписи «Инвентарь» на кнопке-рюкзаке);
--   • если пластика не хватает — золотая подсветка плавающего пластика
--     в океане (как подсветка брёвен у First Timber);
--   • на шаге заливки подсвечивается установленный очиститель.
-- Сама гаснет, когда квест выполнен или пропал из снапшота QuestState.
--
-- Имена UI-элементов, на которые опирается поиск (InventoryUI.client.lua):
--   PlayerGui.BackpackButton → ImageButton "OpenInventory"
--   PlayerGui.InventoryGui   → "Tab_<категория>", "CategoryOverlay" →
--                              "Recipe_<имя>" → "RowCraftBtn"
--   PlayerGui.HotbarGui      → "HotbarSlot_<i>" (слоты 1..8 из
--                              _G.InventorySlotData)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local QUEST_ID = "onboarding_purifier"
local GOLD = Color3.fromRGB(255, 210, 58)

-- стоимость рецептов в пластике — для подсказки «не хватает пластика»
-- (держать в синхроне с InventoryCrafting.server.lua)
local CUP_PLASTIC_COST      = 2
local PURIFIER_PLASTIC_COST = 4

local function waitForQuestStateEvent(timeoutSec)
	local deadline = os.clock() + (timeoutSec or 30)
	while os.clock() < deadline do
		local evt = ReplicatedStorage:FindFirstChild("QuestState")
		if evt and evt:IsA("RemoteEvent") then
			return evt
		end
		task.wait(0.1)
	end
	return nil
end

-- ─── Состояние квеста из снапшотов QuestState ────────────────────────
local enabled      = false
local questVisible = false   -- квест в снапшоте и ещё не выполнен
local objProgress  = {}      -- [eventType] = { progress = N, goal = N }

-- ГЛОТОК ВОДЫ — настоящий финал обучения. Ловим его по шкале жажды: рост
-- значения бывает только от питья, само оно лишь убывает. Пока не выпил,
-- подсказка живёт даже после того, как цели квеста закрылись.
local hasDrunk   = false
local lastThirst = nil
task.spawn(function()
	local evt = ReplicatedStorage:WaitForChild("ThirstUpdate", 30)
	if not evt then return end
	evt.OnClientEvent:Connect(function(thirst)
		local v = tonumber(thirst)
		if not v then return end
		if lastThirst and v > lastThirst + 0.5 then hasDrunk = true end
		lastThirst = v
	end)
end)

-- ─── UI: баннер-инструкция (кольцо-подсветка живёт ВНУТРИ цели, см. attachRing) ──
local gui = Instance.new("ScreenGui")
gui.Name = "PurifierQuestHint"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 60     -- выше InventoryGui (10) и HotbarGui (15), ниже трекера (80)
gui.Enabled = false
gui.Parent = playerGui

--[[ ⚠️ ПЛАШКА РАСТЁТ ПО ТЕКСТУ, А НЕ ДЕРЖИТ 520 ПИКСЕЛЕЙ ВСЕГДА.
     Здесь стояла жёсткая ширина 520 при AutomaticSize только по высоте: короткая
     строка вроде «Нажми „Создать“» занимала ту же полосу, что и самая длинная
     подсказка цепочки. На мониторе это просто некрасиво, на телефоне — беда:
     520 пикселей при ширине экрана 852 съедали две трети кадра и накрывали
     половину меню крафта.
     Остальные подсказки (Bed/Beet/Raft/Grill) давно собраны иначе: ширина по
     тексту, потолок по свободному месту и общий множитель телефона. Этот файл
     писался отдельно и до сих пор жил по-своему — отсюда и «туториалы
     отличаются». Приводим к общему виду: те же размеры, тот же цвет, та же
     логика ширины. ]]
local banner = Instance.new("TextLabel")
banner.Name = "HintBanner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 92) -- как у остальных подсказок
banner.Size = UDim2.fromOffset(10, 38)     -- ширину задаёт текст
banner.AutomaticSize = Enum.AutomaticSize.X
banner.BackgroundColor3 = Color3.new(0, 0, 0)
banner.BackgroundTransparency = 0.35
banner.BorderSizePixel = 0
banner.Text = ""
banner.TextColor3 = GOLD
banner.Font = Enum.Font.GothamBlack
banner.TextSize = 16
banner.TextStrokeColor3 = Color3.new(0, 0, 0)
banner.TextStrokeTransparency = 0.4
banner.AutoLocalize = true
banner.Visible = false
banner.Active = false
banner.Parent = gui

do
	local Hud = require(ReplicatedStorage:WaitForChild("HudScale"))
	-- noticeFactor, а не панельный множитель: подсказку читают на ходу
	Hud.applyScaleLive(banner, Hud.noticeFactor)
	-- потолок ширины по свободному месту + перенос текста (см. HudScale)
	Hud.fitCenterBanner(banner, banner.Position.Y.Offset)
end

local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 10)
bannerCorner.Parent = banner

local bannerStroke = Instance.new("UIStroke")
bannerStroke.Color = GOLD
bannerStroke.Thickness = 2
-- ВАЖНО: у TextLabel режим Contextual (по умолчанию) обводит БУКВЫ, а не
-- рамку — текст превращался в жёлтую нечитаемую кашу. Border = рамка плашки.
bannerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
bannerStroke.Parent = banner

-- ─── Кольцо-подсветка ────────────────────────────────────────────────
-- Кольцо — РЕБЁНОК целевого элемента, а не оверлей в своём ScreenGui:
-- так оно наследует систему координат цели (инсет топбара, UIScale
-- инвентаря, DPI), едет вместе со скроллом списка и исчезает вместе с
-- целью. Прежний вариант через AbsolutePosition съезжал ровно на
-- величину инсета/скейла.
local RING_PAD = 6
local ringInst  = nil -- текущий Frame-кольцо (живёт внутри цели)
local ringTween = nil

local function destroyRing()
	if ringTween then ringTween:Cancel(); ringTween = nil end
	if ringInst then
		pcall(function() ringInst:Destroy() end)
		ringInst = nil
	end
end

local function attachRing(target)
	-- уже висит на этой цели и жив — ничего не делаем
	if ringInst and ringInst.Parent == target then return end
	destroyRing()

	local ring = Instance.new("Frame")
	ring.Name = "QuestHintRing"
	ring.Position = UDim2.new(0, -RING_PAD, 0, -RING_PAD)
	ring.Size = UDim2.new(1, RING_PAD * 2, 1, RING_PAD * 2)
	ring.BackgroundColor3 = GOLD
	ring.BackgroundTransparency = 0.92 -- едва заметная золотая заливка
	ring.BorderSizePixel = 0
	ring.ZIndex = 999   -- поверх содержимого цели (в инвентаре ZIndex ≤ 19)
	ring.Active = false -- клики проходят сквозь кольцо к элементу под ним

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 4
	stroke.Parent = ring

	ring.Parent = target
	ringInst = ring

	ringTween = TweenService:Create(stroke,
		TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Thickness = 7, Transparency = 0.35 })
	ringTween:Play()
end

local bannerPad = Instance.new("UIPadding")
bannerPad.PaddingTop = UDim.new(0, 10)
bannerPad.PaddingBottom = UDim.new(0, 10)
bannerPad.PaddingLeft = UDim.new(0, 16)
bannerPad.PaddingRight = UDim.new(0, 16)
bannerPad.Parent = banner

-- ─── Подсветка ПЛАСТИКА в океане (когда не хватает на крафт) ─────────
-- ⚠️ ПОДСВЕТКА ОБЩАЯ, ИЗ TrackerCard, А НЕ СВОЯ.
-- Здесь была отдельная копия: золотая заливка без стрелки. Рядом с брёвнами
-- первого квеста (зелёный контур + покачивающаяся стрелка) это читалось как два
-- разных механизма, а золото на воде под солнцем к тому же сливается с бликами —
-- ровно то, из-за чего подсветку брёвен и перекрасили. Теперь обе зовут одну
-- реализацию, разница только в типе ресурса.
local plasticGlowOn = false

local function setPlasticGlow(on)
	if plasticGlowOn == on then return end
	plasticGlowOn = on
	if typeof(_G.ResourceGlowSetEnabled) == "function" then
		_G.ResourceGlowSetEnabled("Plastic", on)
	end
end

-- ─── Подсветка установленного очистителя ─────────────────────────────
local purifierGlow -- Highlight (или nil)

local function setPurifierGlow(model)
	-- Parent-проверка: сервер при заливке пересобирает детей модели
	-- (swapPurifierModel) — если Highlight снесло, пересоздаём.
	if purifierGlow and (not purifierGlow.Parent or purifierGlow.Adornee ~= model) then
		purifierGlow:Destroy()
		purifierGlow = nil
	end
	if model and not purifierGlow then
		local hl = Instance.new("Highlight")
		hl.FillColor = GOLD
		hl.FillTransparency = 0.75
		hl.OutlineColor = GOLD
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = model
		hl.Parent = model
		purifierGlow = hl
	end
end

-- ─── Поисковые хелперы ───────────────────────────────────────────────

-- Установленный очиститель: ThirstSystem кладёт на плот Model "Purifier"
-- с атрибутами WaterType/WaterLevel (placePurifier).
-- Сухая грядка на плоту: цель для чистой воды, если она есть. Признак — тот же
-- атрибут Watered, по которому грядка меняет вид (PlanterService).
local function findDryPlanter()
	local raft = workspace:FindFirstChild("Raft")
	local where = raft and raft:GetChildren() or workspace:GetChildren()
	for _, child in ipairs(where) do
		if child.Name == "Raft_planter" and not child:GetAttribute("Watered") then
			return child
		end
	end
	return nil
end

local function findPlacedPurifier()
	local raft = workspace:FindFirstChild("Raft")
	if raft then
		for _, child in ipairs(raft:GetChildren()) do
			if child.Name == "Purifier" and child:GetAttribute("WaterType") ~= nil then
				return child
			end
		end
	end
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == "Purifier" and child:GetAttribute("WaterType") ~= nil then
			return child
		end
	end
	return nil
end

-- Кружка: инструмент с атрибутом CupState (после переименований это
-- может быть «Cup (Saltwater)» и т.п. — атрибут надёжнее имени).
-- Возвращает (tool, вРуках).
local function findCupTool()
	local char = player.Character
	if char then
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute("CupState") ~= nil then
				return t, true
			end
		end
	end
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, t in ipairs(backpack:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute("CupState") ~= nil then
				return t, false
			end
		end
	end
	return nil, false
end

local function isHoldingTool(name)
	local char = player.Character
	local tool = char and char:FindFirstChild(name)
	return tool ~= nil and tool:IsA("Tool")
end

-- Слот хотбара (1..8) с инструментом, подходящим под predicate(slotEntry).
-- Данные слотов публикует InventoryUI через _G.InventorySlotData.
local function hotbarSlotFor(predicate)
	local slotData = _G.InventorySlotData
	if type(slotData) ~= "table" then return nil end
	for i = 1, 8 do
		local d = slotData[i]
		if type(d) == "table" and d.type == "tool" and predicate(d) then
			local hotbarGui = playerGui:FindFirstChild("HotbarGui")
			if hotbarGui then
				return hotbarGui:FindFirstChild("HotbarSlot_" .. i, true)
			end
			return nil
		end
	end
	return nil
end

-- Сколько пластика у игрока (по клиентским данным слотов).
local function plasticCount()
	local slotData = _G.InventorySlotData
	local total = 0
	if type(slotData) == "table" then
		for _, d in pairs(slotData) do
			if type(d) == "table" and d.type == "resource" and d.name == "Plastic" then
				total += tonumber(d.count) or 0
			end
		end
	end
	return total
end

-- ─── Шаги ────────────────────────────────────────────────────────────
-- Каждый шаг возвращает таблицу:
--   text     — строка баннера;
--   target   — GuiObject под кольцо (или nil);
--   plastic  — true → подсветить пластик в океане;
--   purifier — Model установленного очистителя → подсветить его.

-- Общий сценарий «скрафти <рецепт>»: кнопка-рюкзак → вкладка категории →
-- строка рецепта → кнопка Craft.
local function craftStep(recipeName, category, cost, displayName)
	-- ПЛАСТИК ПРОВЕРЯЕМ ПЕРВЫМ. Раньше проверка стояла в самом конце: игрока
	-- сначала гнали открыть инвентарь, потом найти вкладку — и только там он
	-- узнавал, что материала нет, и шёл ловить пластик. Теперь недостача видна
	-- сразу, вместе с подсветкой пластика в океане.
	local have = plasticCount()
	if have < cost then
		return {
			text = ("Нужен пластик: %d из %d — вылавливай канистры из океана")
				:format(have, cost),
			plastic = true,
		}
	end

	local isOpen = typeof(_G.IsInventoryOpen) == "function" and _G.IsInventoryOpen()
	if not isOpen then
		local bpGui = playerGui:FindFirstChild("BackpackButton")
		local bpBtn = bpGui and bpGui:FindFirstChild("OpenInventory", true)
		return {
			text = ("Открой инвентарь, чтобы скрафтить: %s"):format(displayName),
			target = bpBtn,
		}
	end

	local invGui = playerGui:FindFirstChild("InventoryGui")
	if not invGui then
		-- инвентарь ещё строится — баннер без кольца, до следующего тика
		return { text = ("Открой инвентарь, чтобы скрафтить: %s"):format(displayName) }
	end

	--[[ ⚠️ ОТКРЫТА КАРТОЧКА РЕЦЕПТА — ЦЕЛЬ В НЕЙ, А НЕ В СПИСКЕ ПОД НЕЙ.
	     Список никуда не девается: он остаётся разложенным ПОД карточкой, и его
	     RowCraftBtn сохраняет живые координаты. Кольцо садилось на эту невидимую
	     кнопку — и на экране подсвечивался пустой прямоугольник в стороне, пока
	     настоящая кнопка «Создать» стояла нетронутой. Ровно это и видно на
	     скриншоте с кружкой.
	     Какой рецепт открыт, инвентарь сообщает атрибутом RecipeName на самом
	     оверлее — он и заведён для подсказок, чтобы не гадать по тексту кнопки
	     (текст локализуемый). Соседние подсказки (Bed/Beet/Raft) так и делают,
	     этот файл про атрибут просто не знал. ]]
	local detail = invGui:FindFirstChild("DetailOverlay", true)
	if detail and detail:GetAttribute("RecipeName") == recipeName then
		return {
			text = ("Нажми «Создать», чтобы сделать: %s"):format(displayName),
			target = detail:FindFirstChild("DetailCraftButton", true) or detail,
		}
	end

	local overlay = invGui:FindFirstChild("CategoryOverlay")
	local recipeBtn = overlay and overlay:FindFirstChild("Recipe_" .. recipeName, true)
	if not recipeBtn then
		local tab = invGui:FindFirstChild("Tab_" .. category, true)
		-- ⚠️ В ТЕКСТЕ — ПОДПИСЬ ВКЛАДКИ, А НЕ КЛЮЧ КАТЕГОРИИ.
		-- Ключ («Misc», «Technology») английский и живёт только в коде: в интерфейсе
		-- вкладка давно называется «Разное». Подсказка отправляла игрока искать
		-- надпись, которой на экране нет. Перевод берём у самого инвентаря, чтобы он
		-- не разъехался при переименовании.
		local label = category
		if typeof(_G.CraftCategoryLabel) == "function" then
			label = _G.CraftCategoryLabel(category)
		end
		return {
			text = ("Открой вкладку крафта «%s» слева"):format(label),
			target = tab,
		}
	end

	return {
		text = ("Нажми «Создать», чтобы сделать: %s"):format(displayName),
		target = recipeBtn:FindFirstChild("RowCraftBtn") or recipeBtn,
	}
end

-- Финальный шаг: поставить очиститель на плот и залить морскую воду.
local function fillStep()
	local purifier = findPlacedPurifier()
	if not purifier then
		if isHoldingTool("Destitalor") then
			return { text = "Кликни по плоту, чтобы поставить очиститель ([R] — поворот)" }
		end
		return {
			text = "Возьми очиститель в руки и поставь его на плот",
			target = hotbarSlotFor(function(d)
				return (d.toolInst and d.toolInst.Name == "Destitalor") or d.toolName == "Destitalor"
			end),
		}
	end

	local cupTool, inHand = findCupTool()
	if not cupTool then
		-- кружки нет (выброшена/потеряна) — вернуть игрока в крафт
		return craftStep("Cup", "Misc", CUP_PLASTIC_COST, "Cup")
	end

	if not inHand then
		return {
			text = "Возьми кружку из хотбара",
			target = hotbarSlotFor(function(d)
				return d.toolInst and d.toolInst:GetAttribute("CupState") ~= nil
			end),
			purifier = purifier,
		}
	end

	local state = cupTool:GetAttribute("CupState")
	if state == "salty" then
		return {
			text = "Кликни по очистителю, чтобы залить морскую воду",
			purifier = purifier,
		}
	elseif state == "fresh" then
		return {
			text = "Нажми «Выпить воду» над хотбаром",
			purifier = purifier,
		}
	end
	-- empty (и любое неожиданное состояние)
	return {
		text = "Кликни по океану, чтобы набрать воды",
		purifier = purifier,
	}
end

-- ФИНАЛ: довести игрока до глотка. Цели квеста закрываются на заливке воды в
-- очиститель, но сам смысл — утолить жажду, а до него ещё три действия:
-- дождаться очистки, набрать чистую воду в кружку, выпить. Без этого шага
-- подсказка гасла на полпути и новичок оставался с полным очистителем и
-- пустой шкалой жажды.
local function drinkStep()
	local purifier = findPlacedPurifier()
	if not purifier then
		return { text = "Поставь очиститель на плот" }
	end

	local cupTool, inHand = findCupTool()
	if not cupTool then
		return craftStep("Cup", "Misc", CUP_PLASTIC_COST, "Кружка")
	end
	if not inHand then
		return {
			text = "Возьми кружку из хотбара",
			target = hotbarSlotFor(function(d)
				return d.toolInst and d.toolInst:GetAttribute("CupState") ~= nil
			end),
			purifier = purifier,
		}
	end

	local state = cupTool:GetAttribute("CupState")
	if state == "fresh" then
		-- ⚠️ ЧИСТАЯ ВОДА НАБРАНА — И ВОТ ТУТ ВАЖНО, КУДА ЕЁ ВЕСТИ.
		-- Если на плоту стоит СУХАЯ грядка, гнать игрока пить — прямая путаница:
		-- он шёл за водой ДЛЯ ГРЯДКИ, а подсказка велит эту воду извести. Цель
		-- квеста закрывается и поливом тоже (purifier:used), так что ведём по
		-- обстановке: есть что полить — поливаем, нечего — пьём.
		local dry = findDryPlanter()
		if dry then
			return { text = "Кликни по грядке, чтобы полить", purifier = purifier }
		end
		-- Глоток — кнопкой над хотбаром (клик по миру теперь означает «примени
		-- кружку к цели», а не «выпей»).
		return { text = "Нажми «Выпить воду» над хотбаром", purifier = purifier }
	end
	if state == "salty" then
		return { text = "Кликни по очистителю, чтобы залить морскую воду", purifier = purifier }
	end

	-- кружка пуста: смотрим, что уже готово в очистителе
	local waterType = purifier:GetAttribute("WaterType")
	local waterLevel = tonumber(purifier:GetAttribute("WaterLevel")) or 0
	if waterType == "fresh" and waterLevel > 0 then
		return { text = "Вода очистилась — кликни по очистителю, чтобы набрать её в кружку", purifier = purifier }
	end
	if waterLevel > 0 then
		return { text = "Подожди, пока вода очистится", purifier = purifier }
	end
	return {
		text = "Кликни по океану, чтобы набрать воды",
		purifier = purifier,
	}
end

local function stepInfo()
	local function done(o) return o and o.progress >= o.goal end
	local cup  = objProgress["crafted:Cup"]
	local pur  = objProgress["crafted:Destitalor"]
	local fill = objProgress["purifier:filled"]

	-- Четвёртая цель — «пусти чистую воду в дело» (purifier:used): её закрывает и
	-- глоток, и полив грядки. Пока она открыта, подсказка ведёт дальше: дождись
	-- очистки → набери в кружку → полей или выпей (см. drinkStep).
	-- Старое имя purifier:drank читаем тоже: у сохранений, сделанных до правки,
	-- в прогрессе лежит именно оно, и без этого подсказка сочла бы цель пропавшей.
	local drank = objProgress["purifier:used"] or objProgress["purifier:drank"]

	if cup and not done(cup) then
		return craftStep("Cup", "Misc", CUP_PLASTIC_COST, "Кружка")
	elseif pur and not done(pur) then
		return craftStep("Destitalor", "Technology", PURIFIER_PLASTIC_COST, "Очиститель воды")
	elseif fill and not done(fill) then
		return fillStep()
	elseif drank and not done(drank) then
		return drinkStep()
	end
	-- Снапшот мог отстать (или у старого сейва четвёртой цели нет) — ведём до
	-- глотка по факту роста шкалы жажды.
	if not hasDrunk then return drinkStep() end
	return nil
end

-- ─── Включение/выключение ────────────────────────────────────────────
local function setEnabled(on)
	if on and not questVisible then on = false end
	if enabled == on then return end
	enabled = on
	gui.Enabled = on
	if not on then
		banner.Visible = false
		destroyRing()
		if typeof(_G.QuestScrollHint) == "function" then _G.QuestScrollHint(script, nil) end
		setPlasticGlow(false)
		setPurifierGlow(nil)
	end
end

_G.PurifierHintSetEnabled = setEnabled
_G.PurifierHintEnabled = function() return enabled end

-- ─── Снапшоты QuestState ─────────────────────────────────────────────
local questStateEvent = waitForQuestStateEvent(30)
if not questStateEvent then
	warn("[PurifierQuestHint] QuestState RemoteEvent missing; hint disabled")
	return
end

questStateEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "state" then return end
	if type(payload) ~= "table" then return end

	local q
	for _, item in ipairs(payload.quests or {}) do
		if item.id == QUEST_ID then q = item; break end
	end

	objProgress = {}
	if q and not q.completed and not q.rewardPending then
		questVisible = true
		for _, obj in ipairs(q.objectives or {}) do
			if type(obj) == "table" and type(obj.eventType) == "string" then
				objProgress[obj.eventType] = {
					progress = tonumber(obj.progress) or 0,
					goal     = math.max(1, tonumber(obj.goal) or 1),
				}
			end
		end
	elseif q and not hasDrunk then
		-- Квест ЗАСЧИТАН, но воду ещё не пили: цели закрываются на заливке,
		-- а обучение не закончено. Держим подсказку живой до глотка — иначе
		-- новичок остаётся с полным очистителем и пустой шкалой жажды.
		questVisible = true
	else
		-- квеста нет в списке / всё пройдено — гасим подсказку
		questVisible = false
		setEnabled(false)
	end
end)

-- ─── Живой цикл: пересчёт шага ───────────────────────────────────────
-- Кольцо перевешивается только при смене цели (attachRing) — внутри цели
-- оно позиционируется само, покадровая математика не нужна.
local EVAL_INTERVAL = 0.1 -- сек между пересчётами шага (поиски по UI не бесплатны)
local lastEval = 0

RunService.Heartbeat:Connect(function()
	if not enabled then return end

	local now = os.clock()
	if now - lastEval < EVAL_INTERVAL then return end
	lastEval = now

	local info = stepInfo()
	if not info then
		-- все цели закрыты (снапшот с rewardPending может чуть отставать)
		setEnabled(false)
		return
	end

	banner.Text = info.text or ""
	banner.Visible = banner.Text ~= ""
	setPlasticGlow(info.plastic == true)
	setPurifierGlow(info.purifier)

	local target = info.target
	if target and target:IsDescendantOf(playerGui) then
		attachRing(target)
	else
		destroyRing()
	end
	-- цель прокручена за край списка — стрелка SCROLL и «пролистай» (RaftQuestHint)
	if typeof(_G.QuestScrollHint) == "function" then
		local scrollText = _G.QuestScrollHint(script, (target and target:IsDescendantOf(playerGui)) and target or nil)
		if scrollText then
			banner.Text = scrollText
			banner.Visible = true
		end
	end
end)
