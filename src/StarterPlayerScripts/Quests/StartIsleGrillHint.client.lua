local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ПОШАГОВАЯ ПОДСКАЗКА КВЕСТА «МЯСО НА УГЛЯХ» (startisle_meat).

	Кнопка «?» на HUD-трекере ведёт весь путь от пустых рук до готового куска:
	  1. материалы            → баннер «дерева/камня столько-то из стольких»
	  2. собрать мангал       → Tab_Technology → Recipe_Raft_grill → кнопка «Создать»
	  3. взять в руки и поставить на плот
	  4. разжечь бревном      → баннер «подойди и нажми E»
	  5. положить мясо на решётку
	  6. дождаться и забрать готовое

	⚠️ ПОДСКАЗЫВАЕМ ОБЫЧНЫЙ МАНГАЛ, А НЕ БОЧКУ.
	Рецептов два: Raft_grill (6 брёвен + 4 камня) и Raft_grill_barrel — вчетверо
	больше решётка и жарит быстрее. Бочка дороже по смыслу и открывается позже, а
	квест идёт сразу после первой охоты: ведём к простому деревянному мангалу.
	Но если бочка у игрока УЖЕ стоит — она тоже годится, шаги про постройку
	пропускаются (см. findGrill: ищем оба имени).

	⚠️ ШАГ ВЫЧИСЛЯЕТСЯ ИЗ СОСТОЯНИЯ МИРА, А НЕ СЧИТАЕТСЯ КЛИКАМИ.
	Мангал мог стоять на плоту с прошлой сессии, гореть с прошлого бревна, а мясо
	уже лежать на решётке. Каждый кадр смотрим на факты, поэтому подсказка
	подхватывает игрока с любого места.

	Сделано по образцу RaftQuestHint: то же кольцо, тот же баннер, те же имена
	элементов интерфейса. Пятая копия этого каркаса — но и пятый квест со своими
	шагами; сводить их в общий модуль имеет смысл, когда совпадут ещё и шаги.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local GuiService        = game:GetService("GuiService")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local QUEST_ID = "startisle_meat"
local GOLD = Color3.fromRGB(255, 210, 58)
local RING_PAD = 9

-- Обычный деревянный мангал. Держать в синхроне с рецептом:
-- InventoryCrafting.server.lua, Raft_grill, costs = {Log = 6, Stone = 4}.
local GRILL      = "Raft_grill"
local GRILL_LOGS = 6
local GRILL_STONE = 4
-- Бочку в постройку не ведём, но уже поставленную принимаем.
local GRILL_NAMES = { Raft_grill = true, Raft_grill_barrel = true }
-- Розжиг: одно бревно в топку (GrillSystem, ProximityPrompt «Подбросить бревно»).
local FIRE_LOGS = 1

-- Подсчёт запасов — общий модуль подсказок (QuestHintCost), своей копии не заводим.
local Cost = require(ReplicatedStorage:WaitForChild("QuestHintCost"))

local enabled, questVisible = false, false
local hideHint   -- тело ниже, после сборки интерфейса

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
		-- гасим по факту «квеста нет», а не по своему флагу: он мог соврать
		if not questVisible and hideHint then hideHint() end
	end)
end

-- ─── кольцо и баннер ───
local gui = Instance.new("ScreenGui")
gui.Name = "StartIsleGrillHintGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 120
gui.Enabled = false
gui.Parent = playerGui

local ring = Instance.new("Frame")
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
-- на телефоне баннер сжимается целиком, как у остальных подсказок
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
	ring.Size = UDim2.fromOffset(size.X + RING_PAD * 2, size.Y + RING_PAD * 2)
	-- инсет топбара обязателен: gui с IgnoreGuiInset меряет от настоящего верха
	-- экрана, а AbsolutePosition — от нижнего края топбара (см. RaftQuestHint)
	local inset = GuiService:GetGuiInset()
	ring.Position = UDim2.fromOffset(
		pos.X + size.X * 0.5 + inset.X,
		pos.Y + size.Y * 0.5 + inset.Y)
	ring.Visible = true
	return true
end

-- ─── состояние мира ───
local function findGrill()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and GRILL_NAMES[d.Name] then return d end
	end
	return nil
end

local function toolNamed(pred)
	for _, where in ipairs({ player.Character, player:FindFirstChildOfClass("Backpack") }) do
		if where then
			for _, t in ipairs(where:GetChildren()) do
				if t:IsA("Tool") and pred(t.Name) then return t end
			end
		end
	end
	return nil
end

local function holdingName(pred)
	local char = player.Character
	if not char then return nil end
	local t = char:FindFirstChildWhichIsA("Tool")
	if t and pred(t.Name) then return t end
	return nil
end

local function isGrillName(n) return GRILL_NAMES[n] == true end
local function isMeatName(n) return n == "Meat" end

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

local function backpackButton()
	local g = playerGui:FindFirstChild("BackpackButton")
	return g and g:FindFirstChild("OpenInventory", true)
end

-- Что лежит на решётке. Кусок приваривают к решётке моделью с атрибутом
-- ResourceType; готовность помечается атрибутом Cooked (см. GrillSystem и
-- _G.CookFoodModel в CampFireSystem).
local function foodOnGrate(grill)
	local raw, done = nil, nil
	for _, d in ipairs(grill:GetDescendants()) do
		local res = d:GetAttribute("ResourceType")
		if res then
			if d:GetAttribute("Cooked") then done = d else raw = d end
		end
	end
	return raw, done
end

-- ─── шаг ───
-- Возвращает: цель под кольцо, текст баннера.
local function step()
	local grill = findGrill()

	-- ── мангала на плоту нет: ведём к постройке ──
	if not grill then
		if not toolNamed(isGrillName) then
			-- ⚠️ МАТЕРИАЛ ПРОВЕРЯЕМ ПЕРВЫМ, ДО ВСЯКОГО ИНВЕНТАРЯ.
			-- Иначе игрока сперва гонят открыть рюкзак и найти вкладку — и только
			-- там он узнаёт, что камня нет. Тот же порядок, что у молотка и грядки.
			local logs, stone = Cost.have("Log"), Cost.have("Stone")
			if logs < GRILL_LOGS or stone < GRILL_STONE then
				return nil, ("На мангал нужно: дерево %d/%d, камень %d/%d")
					:format(logs, GRILL_LOGS, stone, GRILL_STONE)
			end

			local invGui = playerGui:FindFirstChild("InventoryGui")
			if not (invGui and invGui.Enabled) then
				return backpackButton(), "Открой инвентарь"
			end
			-- открыта карточка рецепта — цель в ней, а не в списке под оверлеем
			local detail = invGui:FindFirstChild("DetailOverlay", true)
			if detail and detail:GetAttribute("RecipeName") == GRILL then
				return detail:FindFirstChild("DetailCraftButton", true) or detail,
					"Собери мангал — 6 брёвен и 4 камня"
			end
			if not detail then
				local recipe = invGui:FindFirstChild("Recipe_" .. GRILL, true)
				if recipe then
					return recipe:FindFirstChild("RowCraftBtn", true) or recipe,
						"Собери мангал — 6 брёвен и 4 камня"
				end
			end
			return invGui:FindFirstChild("Tab_Technology", true), "Вкладка «Технологии»"
		end

		if not holdingName(isGrillName) then
			return hotbarSlotWith(GRILL), "Возьми мангал в руки"
		end
		return nil, "Кликни по плоту — там встанет мангал"
	end

	-- ── мангал стоит: разжечь ──
	if grill:GetAttribute("Lit") ~= true then
		local logs = Cost.have("Log")
		if logs < FIRE_LOGS then
			return nil, "Для розжига нужно бревно — вылови его из океана"
		end
		return nil, "Подойди к мангалу и нажми E — подбрось бревно"
	end

	-- ── горит: положить мясо ──
	local raw, done = foodOnGrate(grill)
	if done then
		return nil, "Готово — кликни по мангалу и забери мясо"
	end
	if raw then
		return nil, "Жарится… не давай огню погаснуть"
	end

	if Cost.have("Meat") < 1 and not holdingName(isMeatName) then
		return nil, "Мяса нет — добудь его на острове"
	end
	if not holdingName(isMeatName) then
		return hotbarSlotWith("Meat"), "Возьми мясо в руки"
	end
	return nil, "Наведись на решётку и кликни — мясо ляжет на угли"
end

RunService.RenderStepped:Connect(function()
	if not enabled then return end
	local target, text = step()
	local shown = pointAt(target)
	-- цель прокручена за край списка — стрелка SCROLL и «пролистай» (RaftQuestHint)
	if typeof(_G.QuestScrollHint) == "function" then
		local scrollText = _G.QuestScrollHint(script, (target and not shown) and target or nil)
		if scrollText then text, shown = scrollText, true end
	end
	-- цель есть, но спрятана (HUD погашен стройкой) — совет выполнить нельзя, молчим
	banner.Visible = text ~= nil and (target == nil or shown)
	if text then banner.Text = text end
end)

function hideHint()
	enabled = false
	gui.Enabled = false
	ring.Visible = false
	banner.Visible = false
	if typeof(_G.QuestScrollHint) == "function" then _G.QuestScrollHint(script, nil) end
end

_G.StartIsleGrillHintSetEnabled = function(on)
	if not on or not questVisible then
		hideHint()
		return
	end
	enabled = true
	gui.Enabled = true
end

_G.StartIsleGrillHintEnabled = function() return enabled end

print("[StartIsleGrillHint] подсказка «Мясо на углях» готова («?» на трекере)")
