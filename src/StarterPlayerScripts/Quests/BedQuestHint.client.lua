local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ПОШАГОВАЯ ПОДСКАЗКА КВЕСТА «НОЧЛЕГ» (onboarding_bed).

	Включается кнопкой «?» на HUD-трекере (TrackerCard) через
	_G.BedHintSetEnabled(on); состояние отдаёт _G.BedHintEnabled().
	Сделано по образцу PurifierQuestHint — те же кольцо и баннер, те же имена
	UI-элементов.

	Шаги ровно те, из которых состоит крафт:
	  1. хватает ли материала         → баннер «сколько есть из скольких»
	  2. открыть инвентарь            → кнопка-рюкзак
	  3. вкладка «Технологии»         → Tab_Technology
	  4. скрафтить кровать            → Recipe_Bed → RowCraftBtn

	⚠️ ШАГ ВЫЧИСЛЯЕТСЯ ИЗ МИРА, А НЕ СЧИТАЕТСЯ КЛИКАМИ.
	Игрок может открыть инвентарь сам, выйти и зайти.
	Счётчик шагов на кликах в любом из этих случаев показывал бы не то, что
	происходит. Поэтому каждый кадр смотрим на факты: есть ли верстак в мире,
	открыт ли инвентарь, какая вкладка активна — и подсвечиваем то, что нужно
	СЕЙЧАС.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local GuiService        = game:GetService("GuiService")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Cost = require(ReplicatedStorage:WaitForChild("QuestHintCost"))

-- Цена. Держать в синхроне с источником:
--   кровать — InventoryCrafting.server.lua, рецепт "Bed", costs = {Log = 5, Leaves = 3}
local BED_COSTS = { Log = 5, Leaves = 3 }

local QUEST_ID = "onboarding_bed"
local GOLD = Color3.fromRGB(255, 210, 58)
local RING_PAD = 9   -- поле между целью и рамкой подсказки
local WORKBENCH_RANGE = 15   -- держать в синхроне с BedCrafting.server.lua

-- ─── состояние квеста из снапшотов ───
local enabled = false
local questVisible = false
local bedDone = false

-- ⚠️ ГАШЕНИЕ — ОДНА ФУНКЦИЯ, А НЕ ГОЛОЕ `enabled = false`.
-- Снятый флаг только останавливает ОБНОВЛЕНИЕ баннера, но не убирает его: после
-- закрытия квеста на экране навсегда застывала последняя подсказка. Объявлена
-- заранее, тело — после сборки интерфейса.
local hideHint

local questStateEvent = ReplicatedStorage:WaitForChild("QuestState", 30)
if questStateEvent then
	questStateEvent.OnClientEvent:Connect(function(action, payload)
		if action ~= "state" or type(payload) ~= "table" then return end
		local found = false
		for _, q in ipairs(payload.quests or {}) do
			if q.id == QUEST_ID then
				found = true
				local closed = (q.completed == true) or (q.rewardPending == true)
				questVisible = not closed
				bedDone = false
				for _, o in ipairs(q.objectives or {}) do
					if o.eventType == "crafted:Bed" then
						bedDone = (o.progress or 0) >= (o.goal or 1)
					end
				end
				if closed then bedDone = true end
			end
		end
		if not found then questVisible = false end
		-- Гасим по факту «квеста нет», а не по флагу enabled: флаг мог быть сброшен
		-- мимо гашения, и тогда убрать баннер было бы уже некому. Вызов идемпотентен.
		if not questVisible and hideHint then
			hideHint()   -- квест закрылся — подсказка убирается с экрана
		end
	end)
end

-- ─── кольцо и баннер ───
local gui = Instance.new("ScreenGui")
gui.Name = "BedHintGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 120
gui.Enabled = false
gui.Parent = playerGui

local ring = Instance.new("Frame")
ring.Name = "Ring"
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.BackgroundTransparency = 1
ring.Visible = false
ring.Parent = gui
local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(1, 0)
ringCorner.Parent = ring
local ringStroke = Instance.new("UIStroke")
ringStroke.Thickness = 4
ringStroke.Color = GOLD
ringStroke.Parent = ring

local ringScale = Instance.new("UIScale")
ringScale.Parent = ring
local pulse = TweenService:Create(ringScale,
	TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Scale = 1.12 })
pulse:Play()

local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 92)
banner.Size = UDim2.fromOffset(10, 38)
banner.AutomaticSize = Enum.AutomaticSize.X
banner.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
banner.BackgroundTransparency = 0.35
banner.BorderSizePixel = 0
banner.Font = Enum.Font.GothamBlack
banner.TextSize = 16
banner.TextColor3 = GOLD
banner.Text = ""
banner.Visible = false
banner.Parent = gui

-- на телефоне подсказка перекрывала трекер и кнопки слева — сжимаем целиком,
-- как в RaftQuestHint (там же объяснение, почему одним UIScale)
do
	local Hud = require(ReplicatedStorage:WaitForChild("HudScale"))
	-- ⚠️ noticeFactor: подсказку игрок читает на ходу, ужимать её панельным
	-- множителем меню (0.55) значило делать её вдвое мельче нужного.
	Hud.applyScaleLive(banner, Hud.noticeFactor)
	--[[ ⚠️ ШИРИНУ ОГРАНИЧИВАЕМ ОТДЕЛЬНО ОТ СЖАТИЯ.
	     UIScale уменьшает подсказку целиком и помогает только телефону. На
	     компьютере в окне поменьше строка остаётся полноразмерной, а растёт она
	     по тексту (AutomaticSize) — и длинная подсказка доезжает до карточки
	     квеста слева, ложась поверх её полосы прогресса. Здесь ей задаётся
	     потолок ширины по свободному месту, а при совсем узком окне она
	     переезжает под карточку. ]]
	Hud.fitCenterBanner(banner, banner.Position.Y.Offset)
end
local bannerStroke = Instance.new("UIStroke")
bannerStroke.Thickness = 2
bannerStroke.Color = GOLD
-- ⚠️ Border, А НЕ ЗНАЧЕНИЕ ПО УМОЛЧАНИЮ.
-- ApplyStrokeMode по умолчанию Contextual, а на текстовом объекте это значит
-- «обводить БУКВЫ». Золотые буквы в золотой обводке сливались в кашу — рамку мы
-- хотели вокруг плашки. У остальных подсказок так и стоит.
bannerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
bannerStroke.Parent = banner
local bannerPad = Instance.new("UIPadding")
bannerPad.PaddingLeft = UDim.new(0, 16)
bannerPad.PaddingRight = UDim.new(0, 16)
bannerPad.Parent = banner

local worldGlow = Instance.new("Highlight")
worldGlow.FillColor = GOLD
worldGlow.FillTransparency = 0.75
worldGlow.OutlineColor = GOLD
worldGlow.OutlineTransparency = 0
worldGlow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
worldGlow.Enabled = false
worldGlow.Parent = gui

--[[ ⚠️ ЦЕЛЬ ДОЛЖНА БЫТЬ ВИДНА, А НЕ ПРОСТО ИМЕТЬ РАЗМЕР.
     В режиме стройки BuildingSystem гасит HUD (ScreenGui.Enabled = false),
     но у кнопок внутри AbsoluteSize и AbsolutePosition остаются прежними.
     Кольцо садилось на пустое место, где раньше была кнопка рюкзака, —
     «круг от квестов перебивается в меню строительства». Проверяем всю
     цепочку: кнопка видима, все родители видимы, ScreenGui включён. ]]
-- ⚠️ И НЕ УЕХАЛА ЗА КРАЙ ПРОКРУТКИ: кнопка «Создать» в списке рецептов, прокрученном
-- вниз, остаётся с живыми координатами — кольцо висело поверх шапки меню. Цель
-- должна целиком лежать в каждом обрезающем родителе (ScrollingFrame, ClipsDescendants).
local function onScreen(inst)
	local node = inst
	local lo = inst:IsA("GuiObject") and inst.AbsolutePosition
	local hi = lo and lo + inst.AbsoluteSize
	while node and not node:IsA("LayerCollector") do
		if node:IsA("GuiObject") then
			if not node.Visible then return false end
			if lo and node ~= inst and (node.ClipsDescendants or node:IsA("ScrollingFrame")) then
				local p, s = node.AbsolutePosition, node.AbsoluteSize
				if lo.X < p.X - 2 or lo.Y < p.Y - 2 or hi.X > p.X + s.X + 2 or hi.Y > p.Y + s.Y + 2 then return false end
			end
		end
		node = node.Parent
	end
	return node ~= nil and node.Enabled and node:IsDescendantOf(playerGui)
end

-- возвращает true, если кольцо показано
local function pointAt(inst)
	if not (inst and inst:IsA("GuiObject") and inst.AbsoluteSize.Y > 0 and onScreen(inst)) then
		ring.Visible = false
		return false
	end	local pos, size = inst.AbsolutePosition, inst.AbsoluteSize
	-- ⚠️ КОЛЬЦО ОБВОДИТ ЦЕЛЬ, А НЕ ОПИСЫВАЕТ ВОКРУГ НЕЁ ОКРУЖНОСТЬ.
	-- Было max(ширина, высота) в обе стороны: у широкой кнопки — вкладки, «Создать» —
	-- выходил круг размером с её ширину, он накрывал соседние строки и читался как
	-- промах. Теперь рамка повторяет габариты цели с полем RING_PAD.
	ring.Size = UDim2.fromOffset(size.X + RING_PAD * 2, size.Y + RING_PAD * 2)
	-- ⚠️ ДОБАВЛЯЕМ ИНСЕТ ТОПБАРА — БЕЗ НЕГО КОЛЬЦО УЕЗЖАЕТ ВВЕРХ.
	-- AbsolutePosition отсчитывается от нижнего края топбара, а наш gui с
	-- IgnoreGuiInset = true меряет от настоящего верха экрана. Разница ровно в
	-- высоту топбара, и кольцо садилось на соседнюю кнопку выше нужной.
	local inset = GuiService:GetGuiInset()
	ring.Position = UDim2.fromOffset(
		pos.X + size.X * 0.5 + inset.X,
		pos.Y + size.Y * 0.5 + inset.Y)
	ring.Visible = true
	return true
end

-- ─── поиск элементов интерфейса ───
-- Имена — из InventoryUI.client.lua и WorckbenchUI.client.lua; при их правке
-- подсказка молча перестанет находить цель, поэтому имена собраны здесь.
local function backpackButton()
	local g = playerGui:FindFirstChild("BackpackButton")
	return g and g:FindFirstChild("OpenInventory", true)
end

local function inventoryOpen()
	local g = playerGui:FindFirstChild("InventoryGui")
	return g and g.Enabled == true, g
end

local function findIn(root, name)
	return root and root:FindFirstChild(name, true) or nil
end

local function hotbarSlotWith(itemName)
	local hg = playerGui:FindFirstChild("HotbarGui")
	local bar = hg and hg:FindFirstChild("Hotbar")
	if not bar then return nil end
	local data = _G.InventorySlotData
	if type(data) == "table" then
		for i = 1, 8 do
			local slot = data[i]
			local n = type(slot) == "table" and (slot.name or slot.item or slot.tool)
			if n == itemName then return bar:FindFirstChild("HotbarSlot_" .. i) end
		end
	end
	return nil
end

-- ─── шаг ───
-- ⚠️ ВЕРСТАКА В ЭТОЙ ПОДСКАЗКЕ БОЛЬШЕ НЕТ.
-- Раньше шагов было пять: собрать верстак, поставить его на плот, подойти,
-- открыть по E и уже в его меню найти кровать. Станцию убрали, кровать
-- переехала в обычный крафт — и четыре шага из пяти вели бы игрока к предмету,
-- которого нет в списке. Осталась та же дорога, что у любого рецепта:
-- материалы → рюкзак → вкладка → карточка.
local function step()
	if bedDone then return nil, nil, nil end

	-- ⚠️ МАТЕРИАЛ ПРОВЕРЯЕМ ПЕРВЫМ, ДО ВСЯКОГО ИНВЕНТАРЯ (см. QuestHintCost).
	-- Иначе игрока ведут открыть рюкзак и найти вкладку — и только у кнопки
	-- крафта он узнаёт, что листвы нет.
	local short = Cost.shortfall(BED_COSTS)
	if short then return nil, short, nil end

	local invOpen, invGui = inventoryOpen()
	if not invOpen then
		return backpackButton(), "Открой инвентарь", nil
	end

	-- ⚠️ ОТКРЫТА КАРТОЧКА РЕЦЕПТА — ЦЕЛЬ В НЕЙ, А НЕ В СПИСКЕ ПОД НЕЙ.
	-- Список остаётся разложенным под оверлеем, у его RowCraftBtn живые
	-- координаты — кольцо садилось на невидимую кнопку посреди карточки.
	local detail = findIn(invGui, "DetailOverlay")
	if detail and detail:GetAttribute("RecipeName") == "Bed" then
		return findIn(detail, "DetailCraftButton") or detail,
			"Скрафти лежанку — 5 брёвен и 3 листвы", nil
	end
	if not detail then
		local recipe = findIn(invGui, "Recipe_Bed")
		if recipe then
			return findIn(recipe, "RowCraftBtn") or recipe,
				"Скрафти лежанку — 5 брёвен и 3 листвы", nil
		end
	end
	return findIn(invGui, "Tab_Technology"), "Вкладка «Технологии»", nil
end

RunService.RenderStepped:Connect(function()
	if not enabled then return end
	local target, text, world = step()
	local shown = pointAt(target)
	-- цель прокручена за край списка — стрелка SCROLL и «пролистай» (RaftQuestHint)
	if typeof(_G.QuestScrollHint) == "function" then
		local scrollText = _G.QuestScrollHint(script, (target and not shown) and target or nil)
		if scrollText then text, shown = scrollText, true end
	end
	-- цель есть, но спрятана (HUD погашен стройкой) — совет выполнить нельзя, молчим
	banner.Visible = text ~= nil and (target == nil or shown)
	if text then banner.Text = text end
	worldGlow.Adornee = world
	worldGlow.Enabled = world ~= nil
end)

-- ─── ручки для кнопки «?» ───
-- тело объявленной выше hideHint
function hideHint()
	enabled = false
	gui.Enabled = false
	ring.Visible = false
	banner.Visible = false
	worldGlow.Enabled = false
	if typeof(_G.QuestScrollHint) == "function" then _G.QuestScrollHint(script, nil) end
end

_G.BedHintSetEnabled = function(on)
	-- ⚠️ ВКЛЮЧАЕМСЯ ТОЛЬКО ПОКА КВЕСТ ЖИВОЙ.
	-- Иначе «?» на закрытом квесте зажигал бы кольцо в пустоту.
	if not on or not questVisible then
		hideHint()
		return
	end
	enabled = true
	gui.Enabled = true
end

_G.BedHintEnabled = function() return enabled end

print("[BedHint] пошаговая подсказка ночлега готова («?» на трекере)")
