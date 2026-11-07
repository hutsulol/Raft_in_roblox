local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ПОШАГОВАЯ ПОДСКАЗКА КВЕСТА «РАСШИРЕНИЕ ПЛОТА» (onboarding_raft).

	Кнопка «?» на HUD-трекере ведёт по шагам:
	  1. открыть инвентарь                → кнопка-рюкзак
	  2. вкладка «Инструменты» → молоток  → Tab_Tools → Recipe_Hammer → RowCraftBtn
	  3. набрать листву и свить верёвку   → Tab_Resources → Recipe_Rope → RowCraftBtn
	  4. выловить пластик                 → подсветка канистр в океане
	  5. взять молоток в руки             → слот хотбара с молотком
	  6. поставить клетку пола            → баннер «кликни по краю плота»

	Сделано по образцу BedQuestHint: те же кольцо, баннер и имена элементов.

	⚠️ ШАГ ВЫЧИСЛЯЕТСЯ ИЗ СОСТОЯНИЯ, А НЕ СЧИТАЕТСЯ КЛИКАМИ.
	Молоток мог лежать в рюкзаке заранее, игрок мог открыть инвентарь сам. Каждый
	кадр смотрим на факты: есть ли молоток, в руках ли он, открыт ли инвентарь.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local GuiService        = game:GetService("GuiService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local QUEST_ID = "onboarding_raft"
local GOLD = Color3.fromRGB(255, 210, 58)
local HAMMER = "Hammer"
local RING_PAD = 9   -- поле между целью и рамкой подсказки

--[[ ⚠️ КЛЕТКА ПОЛА ПОДОРОЖАЛА, И КВЕСТ ВМЕСТЕ С НЕЙ.
     Раньше она стоила два бревна и весь квест сводился к «слови брёвна —
     скрафти молоток — поставь клетку». Теперь в цене ещё пластик и верёвка
     (RAFT_COSTS в BuildingSystem.server.server.lua).
     Верёвка — отдельная беда: в океане она не плавает, её вьют из листвы в
     инвентаре, во вкладке «Ресурсы». Новичок, который до сих пор только
     вылавливал брёвна, этот шаг не находит вовсе — поэтому подсказка ведёт
     до самой кнопки крафта, как вела к молотку.
     Держать в синхроне с источниками:
       молоток     — InventoryCrafting.server.lua, costs = {Log = 4}
       верёвка     — InventoryCrafting.server.lua, costs = {Leaves = 4}
       клетка пола — BuildingSystem.server.server.lua, RAFT_COSTS ]]
local HAMMER_LOG_COST    = 4
local FLOOR_LOG_COST     = 2
local FLOOR_PLASTIC_COST = 2
local FLOOR_ROPE_COST    = 1
local ROPE               = "Rope"
local ROPE_LEAVES_COST   = 4

-- Подсчёт запасов и текст «сколько есть из сколько надо» — общий на все подсказки
-- квестов (QuestHintCost). Здесь была своя копия; после того как то же самое
-- понадобилось грядке, верстаку и кровати, копий стало бы четыре.
local Cost = require(ReplicatedStorage:WaitForChild("QuestHintCost"))
local function logCount()
	return Cost.have("Log")
end

--[[ Подсветка в океане — ЧУЖАЯ, из TrackerCard: там она уже сделана зелёным
     контуром со стрелкой, как в первом квесте. Своей копии не заводим.
     ⚠️ У БРЁВЕН СВОЯ РУЧКА, И ЭТО НЕ ДУБЛИРОВАНИЕ. LogsGlowSetEnabled ведёт
     заодно тумблер «?» и его ауру на трекере первого квеста; остальные
     ресурсы такого хвоста не имеют и ходят через общий ResourceGlow. ]]
local function logsGlow(on)
	if typeof(_G.LogsGlowSetEnabled) == "function" then
		_G.LogsGlowSetEnabled(on)
	end
end
local function resGlow(resType, on)
	if typeof(_G.ResourceGlowSetEnabled) == "function" then
		_G.ResourceGlowSetEnabled(resType, on)
	end
end
local function logsGlowOn()
	return typeof(_G.LogsGlowEnabled) == "function" and _G.LogsGlowEnabled() == true
end

local enabled, questVisible = false, false

-- ⚠️ ГАШЕНИЕ ПОДСКАЗКИ — ОДНА ФУНКЦИЯ НА ВСЕ СЛУЧАИ.
-- Здесь стояло голое `enabled = false`, и это выглядело как «квест не засчитался»:
-- цикл отрисовки перестаёт ОБНОВЛЯТЬ баннер, но не убирает его — на экране
-- навсегда застывала последняя строка («Кликни по краю плота»), хотя квест давно
-- закрыт. Объявлена заранее, тело — после сборки интерфейса.
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
		-- ⚠️ ГАСИМ ПО ФАКТУ «КВЕСТА НЕТ», А НЕ «ПОДСКАЗКА СЧИТАЕТСЯ ВКЛЮЧЁННОЙ».
		-- Условие `enabled and ...` доверяло флагу, а именно он и врал: стоило
		-- сбросить его мимо гашения — и баннер оставался на экране навсегда, потому
		-- что убрать его было уже некому. hideHint идемпотентна, лишний вызов ничего
		-- не стоит.
		if not questVisible and hideHint then hideHint() end
	end)
end

-- ─── кольцо и баннер ───
local gui = Instance.new("ScreenGui")
gui.Name = "RaftHintGui"
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

-- ⚠️ НА ТЕЛЕФОНЕ ПОДСКАЗКУ СЖИМАЕМ ЦЕЛИКОМ.
-- Ширина у баннера автоматическая, а высота и кегль — в пикселях под монитор: на
-- телефоне строка растягивалась почти во весь экран и перекрывала трекер квеста и
-- кнопки слева. Один UIScale на сам баннер: внутри у него ничего, кроме текста, и
-- своего UIScale (как у кнопок с наведением) здесь нет — спорить не с чем.
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
	-- ⚠️ КОЛЬЦО ОБВОДИТ ЦЕЛЬ, А НЕ ОПИСЫВАЕТ ВОКРУГ НЕЁ ОКРУЖНОСТЬ.
	-- Было max(ширина, высота) в обе стороны: у широкой кнопки — вкладки, «Создать» —
	-- выходил круг размером с её ширину, он накрывал соседние строки и читался как
	-- промах. Теперь рамка повторяет габариты цели с полем RING_PAD.
	ring.Size = UDim2.fromOffset(size.X + RING_PAD * 2, size.Y + RING_PAD * 2)
	-- ⚠️ ДОБАВЛЯЕМ ИНСЕТ ТОПБАРА — БЕЗ НЕГО КОЛЬЦО УЕЗЖАЕТ ВВЕРХ.
	-- AbsolutePosition отсчитывается от нижнего края топбара, а наш gui с
	-- IgnoreGuiInset = true меряет от настоящего верха экрана. Разница ровно в
	-- высоту топбара, и кольцо садилось на соседнюю кнопку выше нужной: на «Квесты»
	-- вместо «Инвентаря», хотя баннер просил открыть инвентарь.
	local inset = GuiService:GetGuiInset()
	ring.Position = UDim2.fromOffset(
		pos.X + size.X * 0.5 + inset.X,
		pos.Y + size.Y * 0.5 + inset.Y)
	ring.Visible = true
	return true
end

-- ─── состояние мира ───
local function hasHammer()
	for _, where in ipairs({ player.Character, player:FindFirstChildOfClass("Backpack") }) do
		if where then
			for _, t in ipairs(where:GetChildren()) do
				if t:IsA("Tool") and t.Name == HAMMER then return true end
			end
		end
	end
	return false
end

local function holdingHammer()
	local char = player.Character
	if not char then return false end
	local t = char:FindFirstChildWhichIsA("Tool")
	return t ~= nil and t.Name == HAMMER
end

local function backpackButton()
	local g = playerGui:FindFirstChild("BackpackButton")
	return g and g:FindFirstChild("OpenInventory", true)
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

-- step() возвращает: цель под кольцо, текст баннера, нужна ли подсветка брёвен.
local function step()
	if not hasHammer() then
		-- ⚠️ МАТЕРИАЛ ПРОВЕРЯЕМ ПЕРВЫМ, ДО ВСЯКОГО ИНВЕНТАРЯ.
		-- Иначе игрока сперва гонят открыть рюкзак и найти вкладку — и только там
		-- он узнаёт, что брёвен нет, и идёт их ловить. Тот же порядок, что у
		-- подсказки очистителя с пластиком.
		local have = logCount()
		if have < HAMMER_LOG_COST then
			return nil, ("Нужно дерево: %d из %d — вылавливай брёвна из океана")
				:format(have, HAMMER_LOG_COST), "Log"
		end

		local invGui = playerGui:FindFirstChild("InventoryGui")
		if not (invGui and invGui.Enabled) then
			return backpackButton(), "Открой инвентарь"
		end
		-- ⚠️ ОТКРЫТА КАРТОЧКА РЕЦЕПТА — ЦЕЛЬ В НЕЙ, А НЕ В СПИСКЕ ПОД НЕЙ.
		-- Список рецептов остаётся разложенным под оверлеем, у его RowCraftBtn живые
		-- координаты — и кольцо садилось на невидимую кнопку посреди карточки.
		local detail = invGui:FindFirstChild("DetailOverlay", true)
		if detail and detail:GetAttribute("RecipeName") == HAMMER then
			return detail:FindFirstChild("DetailCraftButton", true) or detail,
				"Скрафти молоток — 4 бревна"
		end
		if not detail then
			local recipe = invGui:FindFirstChild("Recipe_" .. HAMMER, true)
			if recipe then
				return recipe:FindFirstChild("RowCraftBtn", true) or recipe,
					"Скрафти молоток — 4 бревна"
			end
		end
		return invGui:FindFirstChild("Tab_Tools", true), "Вкладка «Инструменты»"
	end

	--[[ Молоток есть — теперь материалы на саму клетку. Проверяем ДО того, как
	     звать брать молоток в руки: с нехваткой клик по плоту просто ничего не
	     сделает, и игрок будет тыкать в край, не понимая почему.
	     Порядок — дерево, верёвка, пластик: первым идёт то, что игрок уже умеет
	     добывать, последним — то, за чем надо плыть. ]]
	local have = logCount()
	if have < FLOOR_LOG_COST then
		return nil, ("Нужно дерево на клетку: %d из %d — вылавливай брёвна из океана")
			:format(have, FLOOR_LOG_COST), "Log"
	end

	-- ── верёвка: её не выловить, её вьют из листвы ──
	if Cost.have(ROPE) < FLOOR_ROPE_COST then
		local leaves = Cost.have("Leaves")
		if leaves < ROPE_LEAVES_COST then
			return nil, ("Нужна листва на верёвку: %d из %d — вылавливай её из океана")
				:format(leaves, ROPE_LEAVES_COST), "Leaves"
		end
		local invGui = playerGui:FindFirstChild("InventoryGui")
		if not (invGui and invGui.Enabled) then
			return backpackButton(), "Открой инвентарь"
		end
		-- та же развилка, что у молотка: открытая карточка рецепта важнее списка
		local detail = invGui:FindFirstChild("DetailOverlay", true)
		if detail and detail:GetAttribute("RecipeName") == ROPE then
			return detail:FindFirstChild("DetailCraftButton", true) or detail,
				("Свей верёвку — %d листвы"):format(ROPE_LEAVES_COST)
		end
		if not detail then
			local recipe = invGui:FindFirstChild("Recipe_" .. ROPE, true)
			if recipe then
				return recipe:FindFirstChild("RowCraftBtn", true) or recipe,
					("Свей верёвку — %d листвы"):format(ROPE_LEAVES_COST)
			end
		end
		return invGui:FindFirstChild("Tab_Resources", true), "Вкладка «Ресурсы»"
	end

	-- ── пластик: канистры плавают там же, где брёвна ──
	local plastic = Cost.have("Plastic")
	if plastic < FLOOR_PLASTIC_COST then
		return nil, ("Нужен пластик: %d из %d — вылавливай канистры из океана")
			:format(plastic, FLOOR_PLASTIC_COST), "Plastic"
	end

	if not holdingHammer() then
		return hotbarSlotWith(HAMMER), "Возьми молоток в руки"
	end

	-- молоток в руках: дальше подсказывает сам режим стройки
	return nil, "Кликни по краю плота — там встанет новая клетка"
end

--[[ Подсветку зажигаем и гасим ТОЛЬКО по своему шагу, и только ту, что зажгли
     сами: игрок мог включить брёвна вручную кнопкой «?» на первом квесте.
     Помним ИМЯ ресурса, а не булев флаг: шагов теперь три (брёвна, листва,
     пластик), и при переходе между ними надо погасить прежний, иначе океан
     светился бы весь сразу. ]]
local litRes = nil
local function setGlow(resType, on)
	if resType == "Log" then logsGlow(on) else resGlow(resType, on) end
end
local function wantGlow(resType)
	if resType == litRes then return end
	if litRes then
		setGlow(litRes, false)
		litRes = nil
	end
	if not resType then return end
	-- брёвна мог зажечь сам игрок — тогда не трогаем их и не считаем своими
	if resType == "Log" and logsGlowOn() then return end
	setGlow(resType, true)
	litRes = resType
end

--[[ ═══ «SCROLL»: ЦЕЛЬ УЕХАЛА ЗА КРАЙ СПИСКА — ПОКАЗЫВАЕМ, КУДА ЛИСТАТЬ ═══
     Общая для ВСЕХ подсказок квестов (плот, кровать, грядка, мангал, ящик,
     очиститель): _G.QuestScrollHint(владелец, цель) — если цель лежит в
     прокручиваемом списке, но за его краем, показывает стрелку и возвращает
     текст для баннера («Пролистай список вверх/вниз»); иначе nil. Подсказка
     без цели зовёт с nil — её стрелка гаснет.
     ⚠️ СТРЕЛКА — СНАРУЖИ ОКНА, СПРАВА ОТ НЕГО, а не внутри списка: внутри она
     читалась как «нажми сюда». Над ней надпись SCROLL. Картинка смотрит ВВЕРХ,
     вниз — поворот на 180°; толчки в сторону прокрутки и лёгкое пошатывание. ]]
do
	local SCROLL_ARROW_IMG = "rbxassetid://96835238652957"
	local sgui = Instance.new("ScreenGui")
	sgui.Name = "QuestScrollHintGui"
	sgui.ResetOnSpawn = false
	sgui.IgnoreGuiInset = true
	sgui.DisplayOrder = 600   -- поверх окон меню
	sgui.Parent = playerGui
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = UDim2.fromOffset(84, 96)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = sgui
	local arrow = Instance.new("ImageLabel")
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.new(0.5, 0, 0.5, 10)
	arrow.Size = UDim2.fromOffset(58, 58)
	arrow.BackgroundTransparency = 1
	arrow.Image = SCROLL_ARROW_IMG
	arrow.ScaleType = Enum.ScaleType.Fit
	arrow.Parent = holder
	local word = Instance.new("TextLabel")
	word.AnchorPoint = Vector2.new(0.5, 0.5)
	word.Size = UDim2.fromOffset(110, 26)
	word.BackgroundTransparency = 1
	word.Font = Enum.Font.GothamBlack
	word.TextSize = 20
	word.Text = "SCROLL"
	word.TextColor3 = GOLD
	word.TextStrokeColor3 = Color3.fromHex("0D2A4F")
	word.TextStrokeTransparency = 0
	word.Parent = holder
	task.spawn(function() pcall(function() game:GetService("ContentProvider"):PreloadAsync({ arrow }) end) end)

	-- цель в прокручиваемом списке, но за его краем? → список и сторона (-1 вверх, 1 вниз)
	local function scrolledAway(inst)
		if not (inst and inst:IsA("GuiObject")) then return nil end
		local node = inst.Parent
		while node and not node:IsA("LayerCollector") do
			if node:IsA("ScrollingFrame") then
				local p, sz = node.AbsolutePosition, node.AbsoluteSize
				local top, bottom = inst.AbsolutePosition.Y, inst.AbsolutePosition.Y + inst.AbsoluteSize.Y
				if bottom > p.Y + sz.Y + 2 then return node, 1 end
				if top < p.Y - 2 then return node, -1 end
				return nil
			end
			node = node.Parent
		end
		return nil
	end
	-- окно, в котором лежит список: самый верхний кадр под ScreenGui
	local function windowOf(inst)
		local node, last = inst, inst
		while node and not node:IsA("LayerCollector") do
			if node:IsA("GuiObject") and node.Visible and node.AbsoluteSize.X > 40 then last = node end
			node = node.Parent
		end
		return last
	end

	local owners = {}   -- [владелец] = { sf, dir }
	_G.QuestScrollHint = function(owner, target)
		local sf, dir = nil, nil
		if target then sf, dir = scrolledAway(target) end
		if sf and onScreen(sf) then
			owners[owner] = { sf = sf, dir = dir }
			return (dir > 0) and "Пролистай список вниз" or "Пролистай список вверх"
		end
		owners[owner] = nil
		return nil
	end

	RunService.RenderStepped:Connect(function()
		local cur = nil
		for owner, st in pairs(owners) do
			if st.sf.Parent and onScreen(st.sf) then cur = st break end
			owners[owner] = nil
		end
		holder.Visible = cur ~= nil
		if not cur then return end
		local inset = GuiService:GetGuiInset()
		local p, sz = cur.sf.AbsolutePosition, cur.sf.AbsoluteSize
		local win = windowOf(cur.sf)
		local wp, ws = win.AbsolutePosition, win.AbsoluteSize
		local t = os.clock()
		local dir = cur.dir
		-- справа от окна, на высоте того края списка, куда листать
		local x = wp.X + ws.X + 54
		local y = (dir > 0) and (p.Y + sz.Y - 50) or (p.Y + 50)
		holder.Position = UDim2.fromOffset(x + inset.X, y + inset.Y)
		-- надпись — со стороны «от» стрелки, стрелка толкается в сторону прокрутки
		word.Position = UDim2.new(0.5, 0, 0.5, (dir > 0) and -34 or 46)
		arrow.Position = UDim2.new(0.5, 0, 0.5, ((dir > 0) and 10 or -6) + math.abs(math.sin(t * 5)) * 8 * dir)
		arrow.Rotation = ((dir > 0) and 180 or 0) + math.sin(t * 3.2) * 9
	end)
end

RunService.RenderStepped:Connect(function()
	if not enabled then return end
	local target, text, glowRes = step()
	local shown = pointAt(target)
	local scrollText = _G.QuestScrollHint(script, (target and not shown) and target or nil)
	if scrollText then text, shown = scrollText, true end
	-- цель есть, но спрятана (HUD погашен стройкой) — совет выполнить нельзя, молчим
	banner.Visible = text ~= nil and (target == nil or shown)
	if text then banner.Text = text end
	wantGlow(glowRes)
end)

-- тело объявленной выше hideHint: убрать с экрана всё, что подсказка рисует
function hideHint()
	enabled = false
	gui.Enabled = false
	ring.Visible = false
	banner.Visible = false
	_G.QuestScrollHint(script, nil)
	wantGlow(nil)
end

_G.RaftHintSetEnabled = function(on)
	if not on or not questVisible then
		hideHint()
		return
	end
	enabled = true
	gui.Enabled = true
end

_G.RaftHintEnabled = function() return enabled end

print("[RaftHint] подсказка расширения плота готова («?» на трекере)")
