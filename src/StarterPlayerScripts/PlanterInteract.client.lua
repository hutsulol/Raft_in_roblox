local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- PlanterInteract.client.lua
-- ГРЯДКА: статус при наводке + полив/посадка/сбор ОДНИМ кликом (или тапом).
--
-- ⚠️ ЗАМЕНА ProximityPrompt.
-- Кнопка «E» над грядкой не нажимается пальцем и вдобавок писала текстом то,
-- что и так видно по модели. Здесь то же решение, что уже работает у мангала
-- (GrillFoodPlace): луч из-под курсора, статус-строка над хотбаром и одно
-- действие на все способы ввода.
--
-- Навигация — это статус-строка:
--   сухая грядка            → «Полейте грядку водой»
--   политая, пустая         → «Посадите что-то в грядку»
--   растёт                  → «Подождите, картофель ещё не вырос»
--   спелое                  → «Плод вырос! Можно собирать»
--
-- Состояние читаем из АТРИБУТОВ грядки (Watered / Crop / Ripe) — сервер их
-- публикует, репликация бесплатная, лишних ремоутов нет.

local Players              = game:GetService("Players")
local ReplicatedStorage     = game:GetService("ReplicatedStorage")
local RunService            = game:GetService("RunService")
local UserInputService      = game:GetService("UserInputService")
local ContextActionService  = game:GetService("ContextActionService")

local player    = Players.LocalPlayer
local mouse     = player:GetMouse()
local camera    = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")
-- телефон это или нет — от этого зависит, откуда брать точку клика
local Hud       = require(ReplicatedStorage:WaitForChild("HudScale"))

local gardenActionEvent = ReplicatedStorage:WaitForChild("GardenAction", 10)
if not gardenActionEvent then
	warn("[Грядка/клиент] нет ремоута GardenAction — грядки работать не будут")
	return
end

local PLANTER_NAME = "Raft_planter"
local REACH        = 14
local RAY_DIST     = 250

local CROP_RU = { Potato = "картофель", Beet = "свёкла" }
local CROP_GROWN_RU = { Potato = "вырос", Beet = "выросла" }

local hoverPlanter

-- ─── Статус-строка над хотбаром ───
-- Один в один как у мангала: без подложки, только текст с чёрным контуром,
-- прижат к полосе инвентаря.
local gui = Instance.new("ScreenGui")
gui.Name = "PlanterHint"
gui.ResetOnSpawn = false
gui.DisplayOrder = 8
gui.Enabled = false
gui.Parent = playerGui

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 1)
-- «родная» позиция у самого низа: HudDock умеет только поднимать, и от
-- хотбара строка встанет ровно над слотами (владелец отметил место)
label.Position = UDim2.new(0.5, 0, 1, -4)
label.Size = UDim2.fromOffset(420, 26)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.TextSize = 17
label.Text = ""
label.Parent = gui

local stroke = Instance.new("UIStroke")
stroke.Thickness = 2.5
stroke.Color = Color3.new(0, 0, 0)
stroke.Transparency = 0.15

-- ⚠️ Высота не числом, а от хотбара: 76 пикселей на широком экране попадали
-- прямо в полосу слотов («подсказка слишком низко»). То же правило, что у
-- лопаты, кирки и остальных строк — ReplicatedStorage/HudDock.
local HudDock = require(game:GetService("ReplicatedStorage"):WaitForChild("HudDock"))
-- вплотную над хотбаром; открыт диалог — поднимается над ним (владелец: «при
-- диалоге вообще не вижу подсказки»)
--[[ ⚠️ И НАД ПОДСКАЗКОЙ КРУЖКИ. С пресной водой в руках CupPurifier держит
     свою строку «Кликни по грядке, чтобы полить» в том же месте над хотбаром
     (и над рядом «Выпить/Вылить»), и наша «Полейте грядку водой» ложилась прямо
     на неё — текст поверх текста. Обходим её как препятствие: она видна — мы
     встаём над ней. Общим препятствием (registerObstacle) её делать нельзя: ряд
     кнопок кружки тоже стоит над препятствиями, и они начали бы прыгать друг
     над другом. ]]
local cupHintGui = playerGui:WaitForChild("CupHint", 5)
HudDock.keepAbove(label, 6, cupHintGui and cupHintGui:WaitForChild("HintText", 5) or nil)
stroke.Parent = label

-- ─── Курсор-лейка ───
-- Тот же приём, что у топора при рубке (StoneAxeClient): mouse.Icon показал бы
-- ассет в его исходном размере — огромным, — поэтому системный курсор прячем и
-- ведём за мышью свою картинку заданного размера.
local CURSOR_WATER_ASSET = "rbxassetid://90418580631248"
-- Крупнее топора (40): лейка читается хуже — у неё тонкий носик и дужка, которые
-- на сорока пикселях сливались в пятно.
local CURSOR_WATER_SIZE  = 58

-- Отдельный ScreenGui с IgnoreGuiInset = false: так его (0, 0) совпадает с
-- mouse.X / mouse.Y точь-в-точь, и полоса сверху не сдвигает иконку.
local cursorGui = Instance.new("ScreenGui")
cursorGui.Name = "PlanterCursor"
cursorGui.DisplayOrder = 1000
cursorGui.IgnoreGuiInset = false
cursorGui.ResetOnSpawn = false
cursorGui.Parent = playerGui

local waterCursor = Instance.new("ImageLabel")
waterCursor.Name = "WaterIcon"
waterCursor.AnchorPoint = Vector2.new(0.5, 0.5)
waterCursor.Size = UDim2.fromOffset(CURSOR_WATER_SIZE, CURSOR_WATER_SIZE)
waterCursor.BackgroundTransparency = 1
waterCursor.Image = CURSOR_WATER_ASSET
waterCursor.ScaleType = Enum.ScaleType.Fit
waterCursor.Visible = false
waterCursor.ZIndex = 100
waterCursor.Parent = cursorGui

local waterCursorOn = false
local function showWaterCursor(show)
	waterCursor.Position = UDim2.fromOffset(mouse.X, mouse.Y)
	if show == waterCursorOn then return end
	waterCursorOn = show
	-- ⚠️ MouseIconEnabled ТРОГАЕМ ТОЛЬКО НА ПЕРЕКЛЮЧЕНИИ.
	-- Свойство общее на весь клиент, и его же дёргает курсор топора. Если писать
	-- в него каждый кадр, два скрипта начнут спорить: один прячет системный
	-- курсор, другой тут же возвращает — и курсор мигает. Пишем лишь тогда, когда
	-- состояние реально сменилось.
	UserInputService.MouseIconEnabled = not show
	waterCursor.Visible = show
end

local COLOR_NEED  = Color3.fromRGB(255, 185, 110) -- нужно что-то сделать
local COLOR_WAIT  = Color3.fromRGB(210, 220, 235) -- просто ждать
local COLOR_READY = Color3.fromRGB(150, 255, 150) -- можно собирать

local function setHint(text, color)
	if not text then gui.Enabled = false return end
	label.Text = text
	label.TextColor3 = color
	gui.Enabled = true
end

-- ─── Грядка под точкой экрана ───
--[[ ⚠️ ДВА СПОСОБА ОТСЧЁТА, И ПУТАТЬ ИХ НЕЛЬЗЯ.
     У курсора координаты ВИДОВЫЕ: полоса Roblox сверху из них уже вычтена.
     У касания — ЭКРАННЫЕ, вместе с этой полосой. Разница около сорока пикселей,
     и если мерить палец видовой меркой, луч уходит выше пальца — по маленькой
     грядке это гарантированный промах при внешне точном тапе. ]]
local function planterAtPoint(x, y, fromScreen)
	local ray = fromScreen and camera:ScreenPointToRay(x, y)
		or camera:ViewportPointToRay(x, y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Список без дыр: nil на первом месте обнуляет весь фильтр, и луч упирался
	-- бы в модель предмета в руках (на этом уже обжигались с мангалом).
	local ignore = {}
	if player.Character then table.insert(ignore, player.Character) end
	params.FilterDescendantsInstances = ignore

	local res = workspace:Raycast(ray.Origin, ray.Direction * RAY_DIST, params)
	if not res or not res.Instance then return nil end

	local inst = res.Instance
	while inst and inst ~= workspace do
		if inst:IsA("Model")
			and (inst.Name == PLANTER_NAME or inst:GetAttribute("IsPlanter")) then
			-- призрак установки носит то же имя, но грядкой ещё не является
			if inst:GetAttribute("PlacementGhost") then return nil end
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

-- Прежнее имя: грядка под курсором. Мышь отдаёт видовые координаты.
local function planterUnderMouse()
	return planterAtPoint(mouse.X, mouse.Y, false)
end

local function inReach(planter)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	-- Расстояние до ДЕТАЛИ, а не до Model:GetPivot(): пивот модели не едет
	-- вместе с плотом, и грядка под носом считалась бы далёкой.
	local base = planter:FindFirstChild("Base") or planter:FindFirstChildWhichIsA("BasePart", true)
	if not base then return false end
	return (hrp.Position - base.Position).Magnitude <= REACH
end

-- ─── Что писать ───
local function hintFor(planter)
	local watered = planter:GetAttribute("Watered")
	local crop    = planter:GetAttribute("Crop")
	local ripe    = planter:GetAttribute("Ripe")

	if crop and ripe then
		return "Плод вырос! Можно собирать", COLOR_READY
	end
	if not watered then
		return "Полейте грядку водой", COLOR_NEED
	end
	if not crop then
		return "Посадите что-то в грядку", COLOR_NEED
	end
	local name = CROP_RU[crop] or crop
	local grown = CROP_GROWN_RU[crop] or "вырос"
	return ("Подождите, %s ещё не %s"):format(name, grown), COLOR_WAIT
end

-- Что произойдёт по клику. Порядок ТОТ ЖЕ, что у сервера (PlanterInteract):
-- спелое собираем, сухое поливаем, пустое засаживаем. Держать одинаковым — из
-- этого порядка растёт и текст подсказки, и курсор, и намерение в запросе.
local function intentFor(planter)
	if planter:GetAttribute("Crop") and planter:GetAttribute("Ripe") then return "harvest" end
	if not planter:GetAttribute("Watered") then return "water" end
	if not planter:GetAttribute("Crop") then return "plant" end
	return nil   -- растёт: делать нечего
end

-- ─── Действие ───
-- Один путь на все способы ввода: клик мышью, тап пальцем и клавиша E шлют
-- ровно одно и то же. Сервер сам решает, что означает нажатие в текущем
-- состоянии — полить, посадить или собрать.
-- ДИАГНОСТИКА: почему клик по грядке «не сработал». Отказов ровно три, и снаружи
-- они выглядят одинаково — ничего не произошло. Печатаем не чаще раза в секунду,
-- чтобы не залить вывод. Убрать, когда вопрос закроется.
local ACT_DEBUG = true
local lastSaidAt = 0
local function sayOnce(msg)
	if not ACT_DEBUG then return end
	local now = os.clock()
	if now - lastSaidAt < 1 then return end
	lastSaidAt = now
	print("[Грядка] " .. msg)
end

local lastActAt = 0
local function act()
	if not hoverPlanter then
		sayOnce("клик мимо: под курсором грядки нет или до неё дальше "
			.. REACH .. " студов")
		return false
	end
	local now = os.clock()
	if now - lastActAt < 0.25 then
		sayOnce("клик проглочен дебаунсом (прошлое действие было < 0.25 с назад)")
		return true -- защита от двойного срабатывания
	end
	lastActAt = now
	-- ⚠️ ГОВОРИМ, ЗА ЧЕМ ПРИШЛИ. Сервер сверит намерение с настоящим состоянием и
	-- сделает только это. Иначе клик, который игрок считал поливом уже политой
	-- грядки, молча сажал семечко — см. PlanterService.PlanterInteract.
	local intent = intentFor(hoverPlanter)
	gardenActionEvent:FireServer("planterAct", hoverPlanter, intent)
	sayOnce(("действие отправлено: %s (намерение: %s)")
		:format(hoverPlanter:GetFullName(), intent or "—"))
	return true
end

-- Перехват ЛКМ раньше тула: с картошкой в руках клик — это Tool.Activated,
-- то есть «съесть». Тот же приём, что и у мангала.
local CLICK_ACTION = "PlanterClick"
local clickBound = false

local function onClick(_, inputState, inputObj)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	--[[ ⚠️ ПАЛЕЦ САМ НАЗЫВАЕТ ЦЕЛЬ, А КУРСОР ЕЁ НЕ ЗНАЕТ.
	     Вся эта система построена на «что под курсором»: каждый кадр из точки
	     мыши пускается луч, найденная грядка запоминается, и по ней потом
	     работает клик. На телефоне курсора нет вовсе — Mouse.X/Y там показывают
	     место ПОСЛЕДНЕГО касания, то есть куда угодно: на джойстик, на кнопку
	     камеры, на прошлый тап. Грядка под этой точкой не находилась, привязка
	     клика даже не включалась, и тап честно не делал ничего.
	     Касание же приносит свою точку с собой. Считаем цель прямо из неё — и
	     заодно чиним промах по вертикали: у касания координаты экранные, а не
	     видовые (см. planterAtPoint). ]]
	if inputObj and inputObj.UserInputType == Enum.UserInputType.Touch then
		local p = planterAtPoint(inputObj.Position.X, inputObj.Position.Y, true)
		if p and inReach(p) then
			hoverPlanter = p
			setHint(hintFor(p))
		else
			-- тап мимо: старую цель забываем, иначе сработает прошлая грядка
			hoverPlanter = nil
		end
	end

	if act() then return Enum.ContextActionResult.Sink end
	return Enum.ContextActionResult.Pass
end

local function setClickBound(on)
	--[[ ⚠️ НА ТЕЛЕФОНЕ ПРИВЯЗКА ЖИВЁТ ВСЕГДА.
	     Здесь она включалась только при наведении — а наведения на телефоне не
	     бывает (см. onClick). Получался замкнутый круг: пока не навёл — не
	     ловим тап, а навести нечем. Держим её постоянно: обработчик всё равно
	     возвращает Pass, когда тап пришёлся мимо грядки, и чужому вводу не
	     мешает. ]]
	if Hud.isPhone() then on = true end
	if on == clickBound then return end
	clickBound = on
	if on then
		ContextActionService:BindActionAtPriority(
			CLICK_ACTION, onClick, false,
			Enum.ContextActionPriority.High.Value + 1,
			Enum.UserInputType.MouseButton1,
			Enum.UserInputType.Touch)
	else
		ContextActionService:UnbindAction(CLICK_ACTION)
	end
end

-- ⚠️ ОДИН ВХОД, БЕЗ ЗАПАСНЫХ.
-- Здесь висели ещё два пути: mouse.Button1Down «на всякий случай» и клавиша E.
-- Дебаунс в act() спасал только от срабатываний в одном кадре, а клавиша и клик
-- разнесены во времени — сервер получал ДВА planterAct подряд и делал два шага
-- сразу: полил и тут же посадил. Со стороны это выглядело как «квест на свёклу
-- закрылся на поливе»: посадка проходила тем же нажатием, незаметно для игрока.
-- Привязка выше принимает и мышь, и палец — этого достаточно на обеих платформах.

-- ⚠️ ЛЕЙКА ПОКАЗЫВАЕТСЯ, ТОЛЬКО КОГДА ПОЛИВ ДЕЙСТВИТЕЛЬНО СЛУЧИТСЯ.
-- Курсор обещает действие, поэтому условия ровно те же, что проверяет сервер
-- (PlanterService.PlanterInteract): земля сухая И в руках сосуд с ЧИСТОЙ водой.
-- Иначе иконка звала бы поливать грядку пустой кружкой — клик не сделал бы
-- ничего, кроме сообщения «набери чистую воду».
local function wouldWater(planter)
	if planter:GetAttribute("Watered") then return false end
	-- спелое собирают, а не поливают: сбор идёт первым и у сервера
	if planter:GetAttribute("Crop") and planter:GetAttribute("Ripe") then return false end
	local char = player.Character
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	return tool ~= nil and tool:GetAttribute("CupState") == "fresh"
end

-- ─── Каждый кадр ───
RunService.RenderStepped:Connect(function()
	local planter = planterUnderMouse()
	if not planter or not inReach(planter) then
		hoverPlanter = nil
		setHint(nil)
		setClickBound(false)
		showWaterCursor(false)
		return
	end

	hoverPlanter = planter
	setHint(hintFor(planter))
	setClickBound(true)
	showWaterCursor(wouldWater(planter))
end)
