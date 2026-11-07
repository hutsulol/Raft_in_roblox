local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ПОШАГОВАЯ ПОДСКАЗКА КВЕСТА «СВОЙ ОГОРОД» (onboarding_beet).

	Кнопка «?» на HUD-трекере ведёт по шагам:
	  1. открыть инвентарь              → кнопка-рюкзак
	  2. вкладка «Технологии» → грядка  → Tab_Technology → Recipe_Garden → создать
	  3. взять грядку и поставить       → слот хотбара с грядкой
	  4. полить грядку                  → подсветка грядки в мире
	  5. посадить свёклу                → подсветка грядки в мире

	Сделано по образцу BedQuestHint: те же кольцо, баннер, подсветка мира.

	⚠️ ШАГ ВЫЧИСЛЯЕТСЯ ИЗ МИРА, А НЕ СЧИТАЕТСЯ КЛИКАМИ.
	Грядка могла быть скрафчена заранее, полита кем-то другим, а инвентарь игрок
	открывает сам. Каждый кадр смотрим на факты: есть ли грядка в мире, полита ли
	она, что в ней растёт.
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

local QUEST_ID = "onboarding_beet"

-- Цена грядки. Держать в синхроне с источником: InventoryCrafting.server.lua,
-- рецепт "Garden", costs = {Log = 4, Compost = 3}.
local GARDEN_COSTS = { Log = 4, Compost = 3 }
local GOLD = Color3.fromRGB(255, 210, 58)
local RING_PAD = 9   -- поле между целью и рамкой подсказки
-- Имена из InventoryCrafting.server.lua (рецепт) и PlanterService.server.lua
-- (модель грядки). При их правке подсказка молча перестанет находить цель,
-- поэтому они собраны здесь.
local GARDEN_ITEM   = "Garden"
local PLANTER_NAME  = "Raft_planter"

local enabled, questVisible = false, false

--[[ Подсветка недостающего ресурса в океане — чужая, из TrackerCard (зелёный
     контур со стрелкой), как у подсказки плота. Помним, что зажгли сами, и
     гасим при смене шага или выключении. ]]
local litRes, glowWant = nil, nil
local function setGlow(resType, on)
	if resType == "Log" then
		if typeof(_G.LogsGlowSetEnabled) == "function" then _G.LogsGlowSetEnabled(on) end
	elseif typeof(_G.ResourceGlowSetEnabled) == "function" then
		_G.ResourceGlowSetEnabled(resType, on)
	end
end
local function wantGlow(resType)
	if resType == litRes then return end
	if litRes then setGlow(litRes, false) litRes = nil end
	if not resType then return end
	if resType == "Log" and typeof(_G.LogsGlowEnabled) == "function" and _G.LogsGlowEnabled() then return end
	setGlow(resType, true)
	litRes = resType
end

-- ⚠️ ГАШЕНИЕ — ОДНА ФУНКЦИЯ НА ВСЕ СЛУЧАИ, А НЕ ГОЛОЕ `enabled = false`.
-- Цикл отрисовки на снятом флаге перестаёт ОБНОВЛЯТЬ баннер, но не убирает его:
-- закрыв квест, игрок остаётся с намертво застывшей строкой на экране. Объявлена
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
				questVisible = not ((q.completed == true) or (q.rewardPending == true))
			end
		end
		if not found then questVisible = false end
		-- Гасим по факту «квеста нет», а не по флагу enabled: флаг мог быть сброшен
		-- мимо гашения, и тогда убрать баннер было бы уже некому. Вызов идемпотентен.
		if not questVisible and hideHint then hideHint() end
	end)
end

-- ─── кольцо, баннер, подсветка мира ───
local gui = Instance.new("ScreenGui")
gui.Name = "BeetHintGui"
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
local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = ring
local rs = Instance.new("UIStroke"); rs.Thickness = 4; rs.Color = GOLD; rs.Parent = ring
local ringScale = Instance.new("UIScale"); ringScale.Parent = ring
TweenService:Create(ringScale,
	TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Scale = 1.12 }):Play()

local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 92)
banner.Size = UDim2.fromOffset(10, 38)
banner.AutomaticSize = Enum.AutomaticSize.X
banner.BackgroundColor3 = Color3.new(0, 0, 0)
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
local bs = Instance.new("UIStroke"); bs.Thickness = 2; bs.Color = GOLD
bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; bs.Parent = banner
local bp = Instance.new("UIPadding")
bp.PaddingLeft = UDim.new(0, 16); bp.PaddingRight = UDim.new(0, 16); bp.Parent = banner

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
	-- Рамка обводит саму цель, а подъём считается с поправкой на инсет топбара:
	-- AbsolutePosition меряется от его нижнего края, а этот gui — от верха экрана.
	ring.Size = UDim2.fromOffset(size.X + RING_PAD * 2, size.Y + RING_PAD * 2)
	local inset = GuiService:GetGuiInset()
	ring.Position = UDim2.fromOffset(
		pos.X + size.X * 0.5 + inset.X,
		pos.Y + size.Y * 0.5 + inset.Y)
	ring.Visible = true
	return true
end

-- ─── поиск элементов интерфейса ───
local function findIn(root, name)
	return root and root:FindFirstChild(name, true) or nil
end

local function backpackButton()
	local g = playerGui:FindFirstChild("BackpackButton")
	return g and g:FindFirstChild("OpenInventory", true)
end

local function inventoryOpen()
	local g = playerGui:FindFirstChild("InventoryGui")
	return (g and g.Enabled == true), g
end

local function hotbarSlotWith(itemName)
	local hg = playerGui:FindFirstChild("HotbarGui")
	local bar = hg and hg:FindFirstChild("Hotbar")
	if not bar then return nil end
	local data = _G.InventorySlotData
	if type(data) == "table" then
		for i = 1, 8 do
			local slot = data[i]
			local n = type(slot) == "table" and (slot.name or slot.toolName)
			if n == itemName then return bar:FindFirstChild("HotbarSlot_" .. i) end
		end
	end
	return nil
end

-- ─── состояние мира ───
local function hasGardenItem()
	for _, where in ipairs({ player.Character, player:FindFirstChildOfClass("Backpack") }) do
		if where then
			for _, t in ipairs(where:GetChildren()) do
				if t:IsA("Tool") and t.Name == GARDEN_ITEM then return true end
			end
		end
	end
	return false
end

-- Грядка в мире. Признаки те же, что у сервера (PlanterService.isPlanter) и у
-- PlanterInteract: имя модели или атрибут IsPlanter.
-- Из нескольких берём БЛИЖАЙШУЮ к игроку: подсвечивать грядку на другом конце
-- плота, когда рядом стоит своя, — значит вести не туда.
local function nearestPlanter()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local best, bestDist
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and (d.Name == PLANTER_NAME or d:GetAttribute("IsPlanter")) then
			if not hrp then return d end
			local base = d:FindFirstChild("Base") or d:FindFirstChildWhichIsA("BasePart", true)
			local dist = base and (hrp.Position - base.Position).Magnitude or math.huge
			if not bestDist or dist < bestDist then best, bestDist = d, dist end
		end
	end
	return best
end

-- ⚠️ ГРЯДКИ ИЩЕМ НЕ КАЖДЫЙ КАДР.
-- Обход всего Workspace на RenderStepped — это десятки тысяч объектов 60 раз в
-- секунду. Список меняется только когда игрок ставит грядку, так что кэша на
-- полсекунды хватает с запасом.
local RESCAN_STEP = 0.5
local cachedPlanter, cachedAt = nil, 0
local function planter()
	local now = os.clock()
	if not cachedPlanter or not cachedPlanter.Parent or (now - cachedAt) > RESCAN_STEP then
		cachedPlanter, cachedAt = nearestPlanter(), now
	end
	return cachedPlanter
end

-- ─── шаг ───
local function step()
	local bed = planter()

	if not bed then
		-- грядки в мире нет: либо крафтим, либо ставим из рюкзака
		if hasGardenItem() then
			return hotbarSlotWith(GARDEN_ITEM), "Возьми грядку и поставь на плот", nil
		end
		-- ⚠️ МАТЕРИАЛ ПРОВЕРЯЕМ ПЕРВЫМ, ДО ВСЯКОГО ИНВЕНТАРЯ (см. QuestHintCost).
		-- Иначе игрока ведут открыть рюкзак и найти вкладку — и только у кнопки
		-- крафта он узнаёт, что брёвен нет. Тот же порядок, что у подсказки плота.
		local short = Cost.shortfall(GARDEN_COSTS)
		if short then
			glowWant = Cost.shortfallRes and Cost.shortfallRes(GARDEN_COSTS) or nil
			return nil, short, nil
		end

		local invOpen, invGui = inventoryOpen()
		if not invOpen then
			return backpackButton(), "Открой инвентарь", nil
		end
		-- Открыта карточка рецепта — цель в ней, а не в списке под ней: список
		-- остаётся разложенным, и кольцо село бы на невидимую строку.
		local detail = findIn(invGui, "DetailOverlay")
		if detail and detail:GetAttribute("RecipeName") == GARDEN_ITEM then
			return findIn(detail, "DetailCraftButton") or detail,
				"Скрафти грядку — 4 бревна и 3 компоста", nil
		end
		if not detail then
			local recipe = findIn(invGui, "Recipe_" .. GARDEN_ITEM)
			if recipe then
				return findIn(recipe, "RowCraftBtn") or recipe,
					"Скрафти грядку — 4 бревна и 3 компоста", nil
			end
		end
		return findIn(invGui, "Tab_Technology"), "Вкладка «Технологии»", nil
	end

	-- грядка стоит: дальше всё происходит в мире, кольцу целиться не во что
	if bed:GetAttribute("Watered") ~= true then
		return nil, "Полей грядку — набери воду в кружку и кликни по грядке", bed
	end
	if not bed:GetAttribute("Crop") then
		return nil, "Возьми свёклу в руки и кликни по грядке", bed
	end
	-- уже что-то растёт (например, картофель): свёкле нужна своя грядка
	if bed:GetAttribute("Crop") ~= "Beet" then
		return nil, "Тут занято — поставь ещё одну грядку под свёклу", bed
	end
	return nil, nil, nil
end

RunService.RenderStepped:Connect(function()
	if not enabled then return end
	glowWant = nil
	local target, text, world = step()
	wantGlow(glowWant)
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
	wantGlow(nil)
	gui.Enabled = false
	ring.Visible = false
	banner.Visible = false
	worldGlow.Enabled = false
	if typeof(_G.QuestScrollHint) == "function" then _G.QuestScrollHint(script, nil) end
end

_G.BeetHintSetEnabled = function(on)
	-- Включаемся только пока квест живой: иначе «?» зажигал бы кольцо в пустоту.
	if not on or not questVisible then
		hideHint()
		return
	end
	enabled = true
	gui.Enabled = true
end

_G.BeetHintEnabled = function() return enabled end

print("[BeetHint] пошаговая подсказка огорода готова («?» на трекере)")
