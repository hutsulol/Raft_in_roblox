local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))
local camera = workspace.CurrentCamera

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")
local bushActionEvent = ReplicatedStorage:WaitForChild("BushAction")
local gardenActionEvent = ReplicatedStorage:WaitForChild("GardenAction")
local sawmillActionEvent = ReplicatedStorage:WaitForChild("SawmillAction")

--[[ ⚠️ ПОСТАНОВКА НА ТЕЛЕФОНЕ ИДЁТ ЧЕРЕЗ ОБЩИЙ МОДУЛЬ.
     Этот файл ставит СЕМЬ предметов — очиститель, куст, верстак, грядку,
     древесную грядку, кровать и лесопилку, — и все они целятся одной строкой:
     лучом из курсора. Курсора на телефоне нет, поэтому там прицел даёт тап, а
     подтверждает кнопка. Вся эта механика лежит в TouchPlace, здесь только три
     точки подключения: луч, начало сеанса и конец. На компьютере модуль не
     делает ничего. ]]
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

-- ─── State ───
-- объявлены заранее: их зовёт createGhost, а определены они ниже по файлу
local onPlaceClick, rotatePlacement

local ghost = nil
local currentTool = nil
local placingPurifier = false
local placingBush = false
local placingWorkbench = false
local placingGarden = false
local placingBedGardenForTree = false
local placingBed = false
local placingSawmill = false
-- Seed-tool-in-hand planting (Banana_Seed / Palm_seed / etc.) — the
-- player can click a watered Bed_T to drop the seedling
-- there. No ghost is needed; we use the mouse target instead.
local placingSeed = false
local currentSeedTool = nil
local lastGhostValid = false
local lastGhostCF = nil
local lastGhostRaftOffset = nil -- CFrame offset relative to raft
local ghostTemplateRotation = CFrame.new() -- template model rotation (identity for most)
local lastTargetGarden = nil -- garden bed reference for bush placement
local rotationAngle = 0 -- radians, incremented by R key

-- ─── Hint UI ───
local playerGui = player:WaitForChild("PlayerGui")
local hintGui = Instance.new("ScreenGui")
hintGui.Name = "CupHint"
hintGui.ResetOnSpawn = false   -- иначе Roblox удаляет окно при смерти, а скрипт живёт дальше с мёртвым объектом
hintGui.DisplayOrder = 50
hintGui.IgnoreGuiInset = true
hintGui.Parent = playerGui

local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "HintText"
hintLabel.AnchorPoint = Vector2.new(0.5, 1)
hintLabel.Position = UDim2.new(0.5, 0, 0.85, 0)
--[[ ⚠️ ПОДЛОЖКА РАСТЁТ ПО ТЕКСТУ, А НЕ ДЕРЖИТ 300 ПИКСЕЛЕЙ.
     Ширина была прибита гвоздями, а строка «Кликни по плоту, чтобы поставить
     грядку | [R] Поворот» при кегле 18 занимает под четыреста пикселей — текст
     торчал за края чёрной плашки с обеих сторон. На мониторе это выглядело
     небрежно, на телефоне — сломано.
     Растём по содержимому и упираемся в ширину экрана: длинная подсказка
     переносится на вторую строку вместо того, чтобы уезжать за край. ]]
hintLabel.Size = UDim2.new(0, 0, 0, 40)
hintLabel.AutomaticSize = Enum.AutomaticSize.XY
hintLabel.TextWrapped = true
hintLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
hintLabel.BackgroundTransparency = 0.4
hintLabel.Text = ""
hintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
hintLabel.TextSize = 18
hintLabel.Font = Enum.Font.GothamBold
hintLabel.Visible = false
hintLabel.Parent = hintGui

-- ⚠️ Подсказка уступает диалогу: пока собеседник говорит, она поднимается
-- над его окном. Правило одно на всю игру — см. ReplicatedStorage/HudDock.
local HudDock = require(game:GetService("ReplicatedStorage"):WaitForChild("HudDock"))
-- Второй аргумент-препятствие — ряд «Выпить/Вылить»: на низком экране он
-- стоял ровно там же, где подсказка, и текст ложился на кнопки. Ряд создаётся
-- ниже по файлу, поэтому вызов отложен до его появления (см. cupBtnRow).

-- воздух по бокам: без него текст упирается прямо в край плашки
local hintPad = Instance.new("UIPadding")
hintPad.PaddingLeft = UDim.new(0, 14)
hintPad.PaddingRight = UDim.new(0, 14)
hintPad.PaddingTop = UDim.new(0, 6)
hintPad.PaddingBottom = UDim.new(0, 6)
hintPad.Parent = hintLabel

local hintCap = Instance.new("UISizeConstraint")
hintCap.MinSize = Vector2.new(0, 40)
hintCap.Parent = hintLabel
do
	local function fitHint()
		local cam = workspace.CurrentCamera
		local w = (cam and cam.ViewportSize.X > 0) and cam.ViewportSize.X or 1280
		hintCap.MaxSize = Vector2.new(math.max(w - 40, 220), math.huge)
	end
	fitHint()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitHint)
	end
end

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 8)
hintCorner.Parent = hintLabel

--[[ ⚠️ ТЕКСТ ПОДСКАЗКИ РАЗНЫЙ У МЫШИ И У ПАЛЬЦА, И ЭТО НЕ КОСМЕТИКА.
     На телефоне тап больше НЕ ставит предмет — он выбирает место, а ставит
     кнопка (см. TouchPlace). Оставь здесь «Кликни по плоту, чтобы поставить» —
     и подсказка учила бы ровно тому, что не работает. Клавиша R там тоже
     недоступна, вместо неё круглая кнопка со стрелкой. ]]
local function placeHint(what)
	if TouchPlace.isPhone() then
		return ("Тапни, куда поставить %s, потом нажми молоток. Кнопка рядом — поворот"):format(what)
	end
	return ("Кликни по плоту, чтобы поставить %s | [R] Поворот"):format(what)
end

-- ⚠️ ЗДЕСЬ БЫЛА ВРЕМЕННАЯ СТРОКА СОСТОЯНИЯ (модуль/сеанс/окно/кнопка).
-- Она писалась поверх кадра на телефоне, пока мы разбирались, где рвётся
-- постановка с пальца. Постановка работает — строка убрана: игроку она
-- показывала отладку прямо в игре и налезала на подсказку.

-- ─── Кнопки кружки над хотбаром ───
-- «Выпить» и «Вылить» — единственные действия кружки, у которых нет цели в мире:
-- их не на что навести, поэтому клавиш им мало (на телефоне их нет), а клик по
-- пустому месту был бы угадайкой. Кнопки нажимаются и мышью, и пальцем.
local cupBtnGui = Instance.new("ScreenGui")
cupBtnGui.Name = "CupActions"
cupBtnGui.ResetOnSpawn = false
cupBtnGui.IgnoreGuiInset = true
cupBtnGui.DisplayOrder = 16   -- над хотбаром (15), под инвентарём
cupBtnGui.Enabled = false
cupBtnGui.Parent = playerGui

local cupBtnRow = Instance.new("Frame")
cupBtnRow.AnchorPoint = Vector2.new(0.5, 1)
cupBtnRow.Position = UDim2.new(0.5, 0, 1, -112)   -- над полосой хотбара
cupBtnRow.Size = UDim2.fromOffset(10, 40)
cupBtnRow.AutomaticSize = Enum.AutomaticSize.X
cupBtnRow.BackgroundTransparency = 1
cupBtnRow.Parent = cupBtnGui
HudDock.keepAbove(hintLabel, 12, cupBtnRow)

local cupBtnLayout = Instance.new("UIListLayout")
cupBtnLayout.FillDirection = Enum.FillDirection.Horizontal
cupBtnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
cupBtnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
cupBtnLayout.SortOrder = Enum.SortOrder.LayoutOrder
cupBtnLayout.Padding = UDim.new(0, 10)
cupBtnLayout.Parent = cupBtnRow

local function makeCupButton(order, text, colour, onClick)
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.AutomaticSize = Enum.AutomaticSize.X
	b.Size = UDim2.fromOffset(0, 38)
	b.BackgroundColor3 = colour
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 17
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.AutoButtonColor = true
	b.Visible = false
	b.Parent = cupBtnRow

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = b

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = b

	-- ⚠️ Border: по умолчанию ApplyStrokeMode обводит БУКВЫ, и надпись превращается
	-- в кашу. Рамка нужна вокруг кнопки.
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b

	b.Activated:Connect(onClick)
	return b
end

local drinkBtn = makeCupButton(1, "Выпить воду", Color3.fromRGB(58, 150, 220), function()
	if not currentTool then return end
	if currentTool:GetAttribute("CupState") ~= "fresh" then return end
	cupActionEvent:FireServer("drink")
end)

local dumpBtn = makeCupButton(2, "Вылить воду", Color3.fromRGB(150, 160, 175), function()
	if not currentTool then return end
	local st = currentTool:GetAttribute("CupState")
	if st ~= "salty" and st ~= "fresh" then return end
	cupActionEvent:FireServer("dumpWater")
end)

local function updateCupButtons()
	local st = currentTool and currentTool:GetAttribute("CupState")
	drinkBtn.Visible = (st == "fresh")
	dumpBtn.Visible  = (st == "salty" or st == "fresh")
	cupBtnGui.Enabled = drinkBtn.Visible or dumpBtn.Visible
end

--[[ ⚠️ ПРИ ОТКРЫТОМ ДИАЛОГЕ КНОПКИ УХОДЯТ ВЫШЕ.
     Окно диалога (DialogueUI) само встаёт вплотную над хотбаром — ровно туда
     же, где стоят «Выпить/Вылить», и накрывало их собой.
     Меряем НЕ фиксированную высоту диалога, а верх его колонки: она растёт по
     длине реплики и по числу вариантов ответа, поэтому любое заранее вписанное
     число разъехалось бы на первой же длинной фразе.
     ⚠️ РАНЬШЕ ЗДЕСЬ БЫЛ СВОЙ ЗАМЕР col.AbsolutePosition.Y — и кнопки уезжали
     на сотню пикселей выше окна: у колонки с AutomaticSize и UIScale эта
     координата врёт (см. HudDock и DialogueUI.VisualTop). Теперь ряд ведёт
     тот же HudDock, что и подсказки: верх окна считает сам диалог, зазор и
     системы координат учтены в одном месте. Родная позиция ряда (1, -112) —
     это его же место над хотбаром, когда диалога нет. ]]
HudDock.keepAbove(cupBtnRow, 10)
HudDock.registerObstacle(cupBtnRow)   -- остальные подсказки встают над этим рядом

local function updateHint()
	updateCupButtons()
	if not currentTool then
		hintLabel.Visible = false
		return
	end

	-- Bush placement hint
	if placingBush then
		hintLabel.Text = TouchPlace.isPhone()
			and "Тапни по грядке, потом нажми молоток"
			or "Кликни по грядке, чтобы посадить куст | [R] Поворот"
		hintLabel.Visible = true
		return
	end

	-- Garden placement hint
	if placingGarden then
		hintLabel.Text = placeHint("грядку")
		hintLabel.Visible = true
		return
	end

	if placingBedGardenForTree then
		hintLabel.Text = placeHint("грядку под дерево")
		hintLabel.Visible = true
		return
	end

	-- Placement hints
	if placingPurifier then
		hintLabel.Text = placeHint("очиститель")
		hintLabel.Visible = true
		return
	end

	if placingWorkbench then
		hintLabel.Text = placeHint("верстак")
		hintLabel.Visible = true
		return
	end

	if placingBed then
		hintLabel.Text = placeHint("лежанку")
		hintLabel.Visible = true
		return
	end

	if placingSawmill then
		hintLabel.Text = placeHint("пилораму")
		hintLabel.Visible = true
		return
	end

	-- Grape tool hint
	if currentTool.Name == "[GRAPES]" or currentTool.Name == "Grapes" then
		hintLabel.Text = "Кликни, чтобы съесть виноград"
		hintLabel.Visible = true
		return
	end

	-- Seed-tool hint: appears whenever a *_seed / *_Seed Tool is
	-- equipped, regardless of whether the player is currently aiming
	-- at a watered bed. Matches the user's expectation that the
	-- prompt is visible while the seed is in hand.
	if placingSeed then
		hintLabel.Text = "Кликни по политой грядке под дерево, чтобы посадить"
		hintLabel.Visible = true
		return
	end

	local cupState = currentTool:GetAttribute("CupState")
	if cupState == "empty" then
		hintLabel.Text = "Кликни по воде, чтобы зачерпнуть"
		hintLabel.Visible = true
	elseif cupState == "salty" then
		hintLabel.Text = "Кликни по очистителю, чтобы залить"
		hintLabel.Visible = true
	elseif cupState == "fresh" then
		hintLabel.Text = "Кликни по грядке, чтобы полить"
		hintLabel.Visible = true
	else
		hintLabel.Visible = false
	end
end

-- ─── Ghost Preview for Placement ───
local function createGhost(templateName)
	if ghost then ghost:Destroy() end
	-- Try a flat lookup first, then a recursive search so templates
	-- nested in organisation folders (Trees_Grow, etc.) still resolve.
	-- Fall back to a case-insensitive sweep so any spelling drift
	-- (PineApple leaves / Pineapple leaves / PineApple Leaves, …)
	-- still finds the asset instead of silently returning nil.
	local name = templateName or "Destitalor"
	local template = ReplicatedStorage:FindFirstChild(name)
		or ReplicatedStorage:FindFirstChild(name, true)
	if not template then
		local lowerTarget = name:lower()
		for _, desc in ReplicatedStorage:GetDescendants() do
			if (desc:IsA("Model") or desc:IsA("BasePart"))
				and desc.Name:lower() == lowerTarget then
				template = desc
				break
			end
		end
	end
	if not template then
		warn(("[CupPurifier] ghost template %q not found in ReplicatedStorage"):format(name))
		return
	end

	ghost = template:Clone()
	ghost.Name = "PlacementGhost"

	-- ⚠️ ГРЯДКУ ВЫПРЯМЛЯЕМ ПРЯМО В ПРИЗРАКЕ.
	-- Модель приезжает из FBX с собственным поворотом, и PivotTo его сохраняет:
	-- призрак показывал ящик, стоящий на ребро, — ровно то же, что потом
	-- вставало на плот. Сервер при установке всё равно приводит грядку к «лежит
	-- плашмя, поворот только вокруг вертикали», поэтому и превью обязано
	-- показывать именно это, иначе оно врёт.
	if templateName == "Raft_planter" then
		-- В призраке — ТОЛЬКО ЯЩИК Base. Если в шаблоне ещё лежат стадии
		-- (политая база, ростки, урожай — сервер не успел вычистить или в
		-- плейсе дубликат шаблона), предпросмотр показывал их все стопкой.
		local base = ghost:FindFirstChild("Base", true)
		if base and base:IsA("BasePart") then
			for _, p in ipairs(ghost:GetDescendants()) do
				if p:IsA("BasePart") and p ~= base then p:Destroy() end
			end
		end
		for _, p in ghost:GetDescendants() do
			if p:IsA("BasePart") then
				p.CFrame = CFrame.new(p.Position)
			end
		end
		if ghost:IsA("Model") and ghost.PrimaryPart then
			ghost.WorldPivot = ghost.PrimaryPart.CFrame
		end
	end

	-- Reset WorldPivot to bounding box center with identity rotation
	local bbCF, bbSize = ghost:GetBoundingBox()
	ghost.WorldPivot = CFrame.new(bbCF.Position)

	-- Store the template's original rotation so we can apply it during placement
	-- (bush template needs this to stay upright; others have identity rotation)
	if templateName == "bush" then
		ghostTemplateRotation = bbCF.Rotation
	else
		ghostTemplateRotation = CFrame.new()
	end

	for _, part in ghost:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = 0.5
			part.CanCollide = false
			part.Anchored = true
			part.Color = Color3.fromRGB(80, 255, 80)
		end
		-- Remove scripts from ghost
		if part:IsA("Script") or part:IsA("LocalScript") then
			part:Destroy()
		end
	end

	-- Highlight overlay — drives the green/red valid/invalid feedback
	-- in a way that survives MeshParts whose visible look comes from a
	-- TextureID, not BasePart.Color. The per-part Color tint above
	-- still lights up solid-colour primitives like the berry-bush
	-- parts; this Highlight covers the textured pineapple-bush mesh.
	local highlight = Instance.new("Highlight")
	highlight.Name                = "GhostHighlight"
	highlight.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor           = Color3.fromRGB(80, 255, 80)
	highlight.FillTransparency    = 0.15
	highlight.OutlineColor        = Color3.fromRGB(80, 255, 80)
	highlight.OutlineTransparency = 0
	highlight.Adornee             = ghost
	highlight.Parent              = ghost

	ghost.Parent = workspace
	--[[ ⚠️ ПОМЕЧАЕМ ПРИЗРАК, ЧТОБЫ ЕГО НЕ ПРИНЯЛИ ЗА ПОСТРОЙКУ.
	     Призрак — полная копия модели, с тем же именем. Чужие системы ищут свои
	     объекты именно по имени и находили его: подсказка плавильни начиналась,
	     когда печь ещё в руках, а не на плоту. Метка стоит копейки и снимает
	     целый класс таких путаниц. ]]
	ghost:SetAttribute("PlacementGhost", true)

	--[[ ⚠️ СЕАНС УСТАНОВКИ НАЧИНАЕМ ЗДЕСЬ, А НЕ В СЕМИ ВЕТКАХ ЭКИПИРОВКИ.
	     Призрак создаётся ровно в тот момент, когда игрок взял ставящийся
	     предмет, — какой бы из семи это ни был. Одна точка вместо семи, и
	     новый предмет получит телефонную схему даром.
	     Функции подтверждения и поворота определены ниже по файлу, поэтому
	     зовём их через обёртки: к моменту нажатия они уже на месте. ]]
	TouchPlace.begin({
		confirm = function() if onPlaceClick then onPlaceClick() end end,
		rotate  = function() if rotatePlacement then rotatePlacement() end end,
		-- призрак заслоняет палубу: без этого тап упирался бы в него самого
		ignore  = function() return ghost end,
	})
end

local function destroyGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	lastGhostValid = false
	lastGhostCF = nil
	lastGhostRaftOffset = nil
	lastTargetGarden = nil
	-- сеанс установки закончился: убрать кнопки телефона и забыть точку тапа
	TouchPlace.finish()
end

local function setGhostColor(valid)
	lastGhostValid = valid
	local color = valid and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
	if not ghost then return end

	-- Per-part BasePart.Color tint — works on plain-colour primitives
	-- (berry bush parts); no-op on textured MeshParts where the
	-- Highlight below picks up the slack.
	--[[ ⚠️ ГАСИМ И МАТЕРИАЛ, А НЕ ТОЛЬКО ЦВЕТ.
	     У грядки и верстака поверхность текстурная: заливка цветом по ней почти
	     не читается, и призрак выглядел обычным деревянным — «подсветки нет».
	     Гладкий пластик отдаёт цвет честно, а призраку фактура и не нужна. ]]
	for _, part in ghost:GetDescendants() do
		if part:IsA("BasePart") then
			part.Color = color
			part.Material = Enum.Material.SmoothPlastic
		end
	end

	-- Single Highlight on the model — paints the whole silhouette of
	-- the bush with a clean fill + outline, instead of the busy
	-- per-part SelectionBox look the previous iteration produced.
	-- Self-heal if the original createGhost-time Highlight isn't
	-- present so the feedback still arrives.
	local highlight = ghost:FindFirstChild("GhostHighlight")
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name      = "GhostHighlight"
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Adornee   = ghost
		highlight.Parent    = ghost
	end
	highlight.FillColor           = color
	highlight.OutlineColor        = color
	highlight.FillTransparency    = 0.15
	highlight.OutlineTransparency = 0

	-- Tidy up any SelectionBox leftovers from the previous approach
	-- so a hot-reload of this script doesn't leave the busy box look
	-- baked into an existing ghost.
	for _, desc in ghost:GetDescendants() do
		if desc:IsA("SelectionBox") and desc.Name == "GhostSelectionBox" then
			desc:Destroy()
		end
	end
end

-- ─── Find garden bed from hit instance ───
-- Bushes only plant on the small flat Garden, never on the tree-sized
-- Bed_T (which also carries IsGarden=true so the watering pipeline
-- can be shared). Skip past tree beds so the ghost can't snap to them.
local function findGardenBed(instance)
	local current = instance
	while current and current ~= workspace do
		if current:GetAttribute("IsGarden") and not current:GetAttribute("IsBedGardenForTree") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- ─── Check if garden already has a bush ───
local function gardenHasBush(garden)
	for _, child in garden:GetChildren() do
		if child:GetAttribute("IsBush") then
			return true
		end
	end
	return false
end

-- ─── Check if placement spot is blocked by existing objects ───
local function isPlacementBlocked(placeCF, ghostSize)
	local raft = workspace:FindFirstChild("Raft")
	if not raft then return true end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {ghost, player.Character}

	-- Shrink the check box to avoid false positives at edges
	local checkSize = ghostSize * 0.7

	local parts = workspace:GetPartBoundsInBox(placeCF, checkSize, overlapParams)

	-- Known placed object names to check against
	--[[ ⚠️ ИМЕНА ЗДЕСЬ — ИМЕНА МОДЕЛЕЙ В МИРЕ, А НЕ ТУЛОВ, И СПИСОК ОТСТАЛ.
	     Проверка занятости была, но не находила почти ничего: грядка давно
	     ставится моделью Raft_planter, кровать — Raft_bed_leaf, а монолита,
	     ремонтной станции, плавильни, мангала, костра и печи в списке не было
	     вовсе. Что не названо — то не «занято», поэтому грядка спокойно вставала
	     внутрь монолита: подсветка оставалась зелёной, и сервер получал согласие
	     клиента.
	     Добавляя новую постройку, впиши сюда ИМЯ ЕЁ МОДЕЛИ — иначе рядом с ней
	     можно будет строить внахлёст. ]]
	local placedObjectNames = {
		-- старые имена: часть моделей ещё встречается в сохранениях
		WorkBench = true, Purifier = true, Garden = true, Bed_T = true,
		Bed = true, Destitalor = true, bush = true, Sawmill = true,
		-- нынешние модели построек плота
		Raft_planter = true, Raft_bed_leaf = true, Raft_smelter = true, Raft_scarecrow = true,
		Raft_chair = true, Raft_chair_leaf = true, Raft_table_leaves = true,   -- декор (DecorPlace)
		Raft_grill = true, Raft_grill_barrel = true, FireCamp = true,
		Furnace = true,
		-- переносимые: их тоже нельзя перекрывать
		Monolit_Aquamen = true, Raft_repair_station = true,
	}

	for _, part in parts do
		if part:IsDescendantOf(raft) then
			-- Walk up to find parent model
			local current = part
			while current and current ~= raft do
				if current:IsA("Model") and placedObjectNames[current.Name] then
					return true
				end
				current = current.Parent
			end
		end
	end

	return false
end

-- ─── Update ghost position each frame ───
local function updateGhost()
	if not ghost then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then
		setGhostColor(false)
		return
	end

	-- Луч прицела: на компьютере из курсора, на телефоне — в точку тапа (TouchPlace)
	local unitRay = TouchPlace.ray(mouse)
	if not unitRay then
		-- телефон, места ещё не выбрали: показывать призрак негде
		setGhostColor(false)
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {ghost, player.Character}

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)

	if not result or not result.Instance then
		setGhostColor(false)
		return
	end

	if placingBush then
		-- Bush: only valid on garden beds
		local garden = findGardenBed(result.Instance)
		if garden and not gardenHasBush(garden) then
			-- Snap to top center of garden bed. PivotTo lands the bush's
			-- pivot (= bbox centre, set in createGhost) on the supplied
			-- CFrame, so raise the Y by half the ghost's height to put
			-- the bbox BOTTOM on the bed's top surface — otherwise the
			-- bush sinks halfway into the dirt (visible on the textured
			-- pineapple-bush mesh; the berry bush's authored pivot
			-- happens to sit lower so it always looked fine).
			local gardenCF, gardenSize = garden:GetBoundingBox()
			local ghostSize = ghost:GetExtentsSize()
			local topY = gardenCF.Position.Y + gardenSize.Y / 2
			local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0

			local placeCF = CFrame.new(gardenCF.Position.X, topY + ghostSize.Y / 2, gardenCF.Position.Z) * CFrame.Angles(0, restYaw + rotationAngle, 0) * ghostTemplateRotation
			ghost:PivotTo(placeCF)
			lastGhostCF = placeCF
			lastGhostRaftOffset = raft.PrimaryPart.CFrame:ToObjectSpace(placeCF)
			lastTargetGarden = garden
			setGhostColor(true)
		else
			-- Not on a valid garden bed — show red ghost at cursor
			lastTargetGarden = nil
			local hitPos = result.Position
			local ghostSize = ghost:GetExtentsSize()
			local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
			ghost:PivotTo(CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z) * CFrame.Angles(0, restYaw + rotationAngle, 0) * ghostTemplateRotation)
			setGhostColor(false)
		end
	else
		-- Other placeables: place on raft surface
		local hitOnRaft = result.Instance:IsDescendantOf(raft)

		if hitOnRaft then
			local hitPos = result.Position
			local ghostSize = ghost:GetExtentsSize()
			local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0

			local placeCF = CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z) * CFrame.Angles(0, restYaw + rotationAngle, 0) * ghostTemplateRotation
			ghost:PivotTo(placeCF)

			-- ⚠️ ГРЯДКА: ВЫРАВНИВАЕМ ПОСЛЕ PivotTo, А НЕ ДО.
			-- Выпрямления шаблона и клона оказалось мало — поворот возвращался
			-- уже здесь, через пивот. Сервер при установке приводит грядку к
			-- «лежит плашмя, поворот только вокруг вертикали», и превью обязано
			-- показывать ровно это, иначе оно врёт про результат.
			--
			-- Заодно чинится и высота: подъём считается как половина
			-- ghostSize.Y, а у наклонённого ящика в Y попадала ШИРИНА (3.9
			-- вместо 1.2) — грядка вставала в воздухе выше палубы.
			if placingGarden then
				local parts = {}
				for _, p in ghost:GetDescendants() do
					if p:IsA("BasePart") then table.insert(parts, p) end
				end
				-- Только если ящик — ОДНА деталь. Так и должно быть после
				-- раскладки ассетов; если деталей больше, значит раскладка не
				-- отработала, и сводить их в один CFrame нельзя — модель
				-- схлопнется в точку.
				if #parts == 1 then
					local yaw = restYaw + rotationAngle
					local box = parts[1]
					box.CFrame = CFrame.new(box.Position) * CFrame.Angles(0, yaw, 0)
					-- Подъём считаем по УЖЕ выпрямленному ящику.
					box.CFrame = CFrame.new(hitPos.X, hitPos.Y + box.Size.Y / 2, hitPos.Z)
						* CFrame.Angles(0, yaw, 0)
					placeCF = box.CFrame
				end
			end

			lastGhostCF = placeCF
			lastGhostRaftOffset = raft.PrimaryPart.CFrame:ToObjectSpace(placeCF)

			-- Check for overlap with existing objects
			if isPlacementBlocked(placeCF, ghostSize) then
				setGhostColor(false)
			else
				setGhostColor(true)
			end
		else
			-- Cursor is not on the raft — show red ghost at cursor position
			local hitPos = result.Position
			local ghostSize = ghost:GetExtentsSize()
			local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
			ghost:PivotTo(CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z) * CFrame.Angles(0, restYaw + rotationAngle, 0))
			setGhostColor(false)
		end
	end
end

-- ─── Detect which purifier model was clicked ───
local function findPurifier(instance)
	local current = instance
	while current and current ~= workspace do
		if current.Name == "Purifier" and current:GetAttribute("WaterType") ~= nil then
			return current
		end
		current = current.Parent
	end
	-- Also check inside Raft
	local raft = workspace:FindFirstChild("Raft")
	if raft then
		local current2 = instance
		while current2 and current2 ~= raft do
			if current2.Name == "Purifier" and current2:GetAttribute("WaterType") ~= nil then
				return current2
			end
			current2 = current2.Parent
		end
	end
	return nil
end

-- ─── Tool Equip/Unequip Detection ───
local function onToolEquipped(tool)
	currentTool = tool
	rotationAngle = 0

	if tool.Name == "Destitalor" then
		placingPurifier = true
		placingBush = false
		placingWorkbench = false
		placingGarden = false
		placingBed = false
		createGhost("Destitalor")
	elseif tool.Name == "bush" or tool.Name == "Bush" then
		placingBush = true
		placingPurifier = false
		placingWorkbench = false
		placingGarden = false
		placingBed = false
		createGhost("bush")
	elseif tool.Name == "Pineapple_Bush_Seed" then
		-- Pineapple bush seed (the inventory-routed variant created
		-- by BushSeedSystem). Same ghost-preview flow as the berry
		-- bush; the Tool is consumed on placement and refunds the
		-- resource if unequipped without being used.
		placingBush = true
		placingPurifier = false
		placingWorkbench = false
		placingGarden = false
		placingBed = false
		createGhost("PineApple leaves")
	elseif tool.Name == "WorkBench" then
		placingWorkbench = true
		placingPurifier = false
		placingBush = false
		placingGarden = false
		placingBed = false
		createGhost("WorkBench")
	elseif tool.Name == "Garden" then
		placingGarden = true
		placingPurifier = false
		placingBush = false
		placingWorkbench = false
		placingBed = false
		placingBedGardenForTree = false
		-- Призрак строится по НОВОЙ модели грядки: старая Garden заменена
		-- на Raft_planter, поведение даёт PlanterService.
		createGhost("Raft_planter")
	elseif tool.Name == "Bed_T" then
		placingBedGardenForTree = true
		placingGarden = false
		placingPurifier = false
		placingBush = false
		placingWorkbench = false
		placingBed = false
		placingSawmill = false
		createGhost("Bed_T")
	elseif tool.Name == "Bed" then
		placingBed = true
		placingPurifier = false
		placingBush = false
		placingWorkbench = false
		placingGarden = false
		placingBedGardenForTree = false
		placingSawmill = false
		-- ⚠️ ПРИЗРАК СТРОИМ ИЗ ТОЙ ЖЕ МОДЕЛИ, ЧТО СТАВИТ СЕРВЕР.
		-- Тул называется "Bed" по-прежнему, а модель сменилась на Raft_bed_leaf
		-- (BedCrafting). Пока здесь стояло имя тула, предпросмотр показывал старую
		-- кровать — и не только выглядел не тем: у старой другая высота, поэтому и
		-- место под установку считалось не то.
		createGhost("Raft_bed_leaf")
	elseif tool.Name == "Sawmill" then
		placingSawmill = true
		placingPurifier = false
		placingBush = false
		placingWorkbench = false
		placingGarden = false
		placingBedGardenForTree = false
		placingBed = false
		createGhost("Sawmill")
	else
		placingPurifier = false
		placingBush = false
		placingWorkbench = false
		placingGarden = false
		placingBedGardenForTree = false
		placingBed = false
		placingSawmill = false
		placingSeed = false
		currentSeedTool = nil
		destroyGhost()
	end

	updateHint()
	-- Listen for CupState changes to update hint
	tool:GetAttributeChangedSignal("CupState"):Connect(function()
		if currentTool == tool then
			updateHint()
		end
	end)
end

local function onToolUnequipped()
	currentTool = nil
	placingPurifier = false
	placingBush = false
	placingWorkbench = false
	placingGarden = false
	placingBedGardenForTree = false
	placingBed = false
	placingSawmill = false
	placingSeed = false
	currentSeedTool = nil
	destroyGhost()
	updateHint()
end

local function setupCharacter(char)
	if not char then return end

	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			onToolEquipped(child)
		end
	end)

	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child == currentTool then
			onToolUnequipped()
		end
	end)

	for _, child in char:GetChildren() do
		if child:IsA("Tool") then
			onToolEquipped(child)
			break
		end
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

-- ─── Update ghost every frame ───
RunService.RenderStepped:Connect(function()
	if (placingPurifier or placingBush or placingWorkbench or placingGarden or placingBedGardenForTree or placingBed or placingSawmill) and ghost then
		updateGhost()
	end
end)

-- ─── R key to rotate placement ───
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if UserInputService:GetFocusedTextBox() then return end
	if GamepadInput.isKey(input, Enum.KeyCode.R) and (placingPurifier or placingWorkbench or placingGarden or placingBedGardenForTree or placingBed or placingBush or placingSawmill) then
		rotatePlacement()
	end
end)

-- поворот на четверть — общий для клавиши R и для экранной кнопки на телефоне
function rotatePlacement()
	rotationAngle = rotationAngle + math.rad(90)
end

-- Определена ниже по файлу, но нужна уже в обработчике клика.
local isCursorOverWater

-- ─── Клик мышью / подтверждение постановки ───
-- Тело общее: на компьютере его зовёт ЛКМ, на телефоне — кнопка «ПОСТАВИТЬ».
function onPlaceClick()
	if not currentTool then return end

	local function playPlaceSound()
		local folder = (SoundService:FindFirstChild("Building") or SoundService:FindFirstChild("Building", true))
		local snd = folder and folder:FindFirstChild("Place_Block")
		if snd then snd:Play() end
	end

	-- Purifier placement
	if placingPurifier and ghost then
		if not lastGhostValid or not lastGhostRaftOffset then return end
		cupActionEvent:FireServer("placePurifier", lastGhostRaftOffset)
		playPlaceSound()
		destroyGhost()
		placingPurifier = false
		return
	end

	-- Bush placement (on garden bed)
	if placingBush and ghost then
		if not lastGhostValid or not lastTargetGarden then return end
		bushActionEvent:FireServer("placeBush", lastTargetGarden)
		playPlaceSound()
		destroyGhost()
		placingBush = false
		return
	end

	-- Workbench placement
	if placingWorkbench and ghost then
		if not lastGhostValid or not lastGhostRaftOffset then return end
		cupActionEvent:FireServer("placeWorkbench", lastGhostRaftOffset)
		playPlaceSound()
		destroyGhost()
		placingWorkbench = false
		return
	end

	-- Garden placement
	if placingGarden and ghost then
		if not lastGhostValid or not lastGhostRaftOffset then return end
		gardenActionEvent:FireServer("placePlanter", lastGhostRaftOffset)
		playPlaceSound()
		destroyGhost()
		placingGarden = false
		return
	end

	-- Tree garden bed placement (bigger variant)
	if placingBedGardenForTree and ghost then
		if not lastGhostValid or not lastGhostRaftOffset then return end
		gardenActionEvent:FireServer("placeBedGardenForTree", lastGhostRaftOffset)
		playPlaceSound()
		destroyGhost()
		placingBedGardenForTree = false
		return
	end

	-- Bed placement
	if placingBed and ghost then
		if not lastGhostValid or not lastGhostRaftOffset then return end
		cupActionEvent:FireServer("placeBed", lastGhostRaftOffset)
		playPlaceSound()
		destroyGhost()
		placingBed = false
		return
	end

	-- Sawmill placement
	if placingSawmill and ghost then
		if not lastGhostValid or not lastGhostRaftOffset then return end
		sawmillActionEvent:FireServer("placeSawmill", lastGhostRaftOffset)
		playPlaceSound()
		destroyGhost()
		placingSawmill = false
		return
	end

	-- Seed-tool planting: raycast from mouse to find a watered tree
	-- garden bed under the cursor and ask the server to plant a
	-- seedling on it. Server destroys the Tool + drives the growth
	-- stages (palm seeds → 4-stage growth; everything else stops at
	-- the seedling).
	if placingSeed and currentSeedTool then
		local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character }
		local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)
		if not result then return end

		-- Walk up to the bed Model (the ray hits one of its parts).
		local target = result.Instance
		while target and target ~= workspace do
			if target:IsA("Model") and target:GetAttribute("IsBedGardenForTree") then break end
			target = target.Parent
		end
		if not target or not target:IsA("Model") or not target:GetAttribute("IsBedGardenForTree") then return end
		if not target:GetAttribute("IsWatered") then return end
		if target:GetAttribute("GrowthStage") then return end

		gardenActionEvent:FireServer("plantSeedTool", target)
		playPlaceSound()
		return
	end

	-- Grape eating
	if currentTool.Name == "[GRAPES]" or currentTool.Name == "Grapes" then
		bushActionEvent:FireServer("eatGrape")
		return
	end

	-- Cup click interactions (purifier fill/collect)
	local cupState = currentTool:GetAttribute("CupState")
	if cupState == nil then return end

	local target = mouse.Target
	local purifier = target and findPurifier(target)

	-- ⚠️ ВСЯ КРУЖКА — НА ОДНОМ ЛКМ.
	-- Раньше набор воды висел на Q, а глоток случался от любого клика. На телефоне
	-- клавиши Q нет вовсе, то есть набрать воду было нельзя в принципе; глоток же
	-- срабатывал случайно — щёлкнул по плоту с полной кружкой и выпил. Теперь
	-- КЛИК = «применить кружку к тому, на что смотрю»: по воде — зачерпнуть, по
	-- очистителю — залить или набрать готовую. Питьё и слив переехали на кнопки
	-- над хотбаром (они одинаково нажимаются мышью и пальцем).
	if cupState == "empty" then
		if purifier then
			local waterType = purifier:GetAttribute("WaterType")
			local waterLevel = purifier:GetAttribute("WaterLevel") or 0
			if waterType == "fresh" and waterLevel > 0 then
				cupActionEvent:FireServer("collectWater", target)
			end
		elseif isCursorOverWater() then
			cupActionEvent:FireServer("scoopSaltwater")
		end
	elseif cupState == "salty" then
		if purifier then
			cupActionEvent:FireServer("fillPurifier", target)
		end
	end
	-- cupState == "fresh": клик ничего не делает сам по себе. Полив грядки идёт
	-- через её собственный клик (PlanterInteract), глоток — через кнопку.
end

--[[ ⚠️ НА ТЕЛЕФОНЕ ТАП НЕ СТАВИТ — ОН ВЫБИРАЕТ МЕСТО.
     Roblox превращает касание экрана в тот же Button1Down, поэтому раньше первый
     же тап мгновенно ставил предмет по координатам ПРЕДЫДУЩЕГО касания: игрок
     целился, а вещь уже стояла не там. Пока идёт сеанс установки, тап отдаём
     модулю (он двигает прицел), а ставит кнопка «ПОСТАВИТЬ».
     Условие именно про сеанс, а не про телефон вообще: с кружкой в руках сеанса
     нет, и все её действия — набрать, вылить, залить очиститель — тап выполняет
     как прежде. ]]
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

-- ─── Check if cursor is hovering over water ───
-- (объявлена выше — обработчик клика зовёт её раньше этого места в файле)
function isCursorOverWater()
	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}
	if player.Character then table.insert(filterList, player.Character) end
	if ghost then table.insert(filterList, ghost) end
	params.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)

	if not result then return false end -- nothing hit (sky) = not water
	if result.Instance:IsA("Terrain") then return true end

	-- Check if we hit something that's NOT the raft or a purifier
	local raft = workspace:FindFirstChild("Raft")
	if raft and result.Instance:IsDescendantOf(raft) then return false end
	if findPurifier(result.Instance) then return false end

	-- Hit a floating resource or other object — not water
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildWhichIsA("Humanoid") then return false end

	return true
end

-- (findGardenAtCursor убрана вместе с клавишей E: поиск грядки под курсором теперь
-- живёт в PlanterInteract, который и обрабатывает клик по ней.)

-- ⚠️ КЛАВИШ Q И E У КРУЖКИ БОЛЬШЕ НЕТ.
-- Q набирала воду и сливала её, E поливала грядку. На телефоне ни той, ни другой
-- не существует — половина механики была недоступна с телефона вовсе, а игрок за
-- ПК и игрок с телефона играли в разные игры. Всё переехало на то, что работает
-- одинаково: набор и заливка — клик по цели (см. обработчик выше), полив — клик
-- по самой грядке (PlanterInteract), питьё и слив — кнопки над хотбаром (ниже).