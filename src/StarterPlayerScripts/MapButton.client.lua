--[[
	КНОПКА КАРТЫ — справа от «Квестов», в один ряд с ними.

	⚠️ ГЕОМЕТРИЯ ОДИН-В-ОДИН С QuestEntryButton: тот же размер иконки (78),
	та же вертикаль (центр экрана − 128), та же подпись (GothamBold 16, внутри
	кнопки, наезжает на низ иконки). Меняешь там — меняй и здесь, иначе кнопки
	разъедутся по высоте и подписи будут разного кегля.

	Иконка меняется по дню: свёрнутая карта до OPEN_FROM_DAY, раскрытая — после.
	День приходит из ReplicatedStorage.DayCount (его ведёт DayNightCircle), так
	что переключение работает и при заходе в середине забега, и на смене дня.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ICON_LOCKED = "rbxassetid://140433394148738"   -- свёрнутая карта (пока не открыта)
-- ⚠️ ДВЕ КАРТИНКИ: С БИНДОМ И БЕЗ.
-- На кнопке нарисована клавиша (M), и на телефоне это вранье — клавиатуры у него
-- нет. Значок клавиши вшит в саму картинку, поэтому под телефон отдельный ассет.
-- Заменяется ТОЛЬКО открытая карта: свёрнутая — другое состояние, свой рисунок.
local ICON_OPEN = (require(game:GetService("ReplicatedStorage"):WaitForChild("HudScale")).isPhone())
	and "rbxassetid://70444773611719"     -- телефон: без клавиши
	or  "rbxassetid://116555452678480"    -- клавиатура: с «M»

-- ⚠️ ПОКА ТЕСТИРУЕМ — карта открыта с первого дня. Вернуть замок до пятого дня:
-- поставить 5 (и заодно REQUIRE_DAY = 5 в MapItem.client.lua, чтобы M тоже был
-- закрыт — иначе кнопка закрыта, а клавиша работает).
local OPEN_FROM_DAY = 1

-- числа кнопки квестов, от которых мы отстраиваемся.
-- ⚠️ ЧЕРЕЗ HudScale, И РОВНО ТЕМИ ЖЕ ВЫЗОВАМИ, ЧТО В QuestEntryButton.
-- Эта кнопка встаёт вплотную к кнопке квестов, отсчитываясь от её чисел. Сожми одну
-- и не сожми другую — они наедут друг на друга. Коэффициент общий, в HudScale.
local Hud = require(game:GetService("ReplicatedStorage"):WaitForChild("HudScale"))
-- Шаг по вертикали — step(), как у кнопки квестов: столбик должен сохранять
-- пропорцию, иначе кнопки наедут друг на друга (см. HudScale.step).
-- Горизонтальный зазор между Квестами и Картой — это воздух, его режем сильнее.
local QUEST_X, QUEST_SIZE, QUEST_Y = Hud.gap(19), Hud.px(78), -Hud.step(128)
local GAP  = Hud.gap(10)
local SIZE = QUEST_SIZE

-- ⚠️ КАРТА СТОИТ В ОДИН РЯД С РЮКЗАКОМ, А НЕ «НА ШАГ НИЖЕ МАГАЗИНА».
-- Сначала я опустил её на произвольную высоту одной кнопки — она повисла между
-- строками. Потом прицелился в центр иконки рюкзака числом — и всё равно вышло
-- мимо, потому что считать надо было не смещение, а систему отсчёта: у окна
-- карты стоял IgnoreGuiInset = false (см. выше), у рюкзака — true. Теперь обе
-- меряют от одного верха, и число ниже наконец значит то, что написано.
-- Правая колонка должна читаться строками вместе с левой:
--     Квесты | Магазин
--     Рюкзак | Карта
-- Поэтому целимся не в «шаг», а в ЦЕНТР ИКОНКИ РЮКЗАКА. Он НЕ на середине
-- экрана: холдер 92×102 стоит серединой по центру, а сама кнопка 76×76 прижата к
-- его ВЕРХУ (bpHolder/bpButton в InventoryUI) — значит центр иконки выше середины
-- ровно на (102−76)/2 пикселей. Держать эти два числа равными тамошним.
local BACKPACK_HOLDER_H, BACKPACK_ICON_H = 102, 76
local ROW2_Y = -Hud.step((BACKPACK_HOLDER_H - BACKPACK_ICON_H) / 2)

local gui = Instance.new("ScreenGui")
gui.Name = "MapButtonGui"
gui.ResetOnSpawn = false
-- ⚠️ ИНСЕТ ИГНОРИРУЕМ — КАК РЮКЗАК, С КОТОРЫМ МЫ В ОДНОМ РЯДУ.
-- Было false, и карта упорно висела ниже рюкзака, сколько ни правь смещение.
-- Причина не в числах: при false отсчёт идёт от НИЖНЕЙ кромки топбара Roblox, а
-- у рюкзака (BackpackButton) стоит true — от настоящего верха экрана. Середина
-- экрана у двух окон получается разная, на половину топбара (~18 пикселей), и
-- одинаковое смещение даёт разную высоту. Ровняться надо в одной системе
-- отсчёта, а не подгонять число под чужую.
gui.IgnoreGuiInset = true
gui.DisplayOrder = 90
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local button = Instance.new("ImageButton")
button.Name = "MapButton"
button.AnchorPoint = Vector2.new(0, 0.5)
button.Position = UDim2.new(0, QUEST_X + QUEST_SIZE + GAP, 0.5, ROW2_Y)
button.Size = UDim2.fromOffset(SIZE, SIZE)
button.BackgroundTransparency = 1
button.BorderSizePixel = 0
button.AutoButtonColor = false
button.Image = ICON_OPEN
button.ScaleType = Enum.ScaleType.Fit   -- Fit, а не Stretch: иконка не плющится
button.Parent = gui

local scale = Instance.new("UIScale")
scale.Parent = button

-- подпись — копия «Квестов»: тот же шрифт, кегль и посадка внутри кнопки
local label = Instance.new("TextLabel")
label.Name = "CaptionLabel"
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.new(0.5, 0, 1, -6)
label.Size = UDim2.new(1, Hud.px(6), 0, Hud.px(20))
label.TextScaled = true
Instance.new("UITextSizeConstraint", label).MaxTextSize = Hud.text(16)
--[[ ⚠️ ПОДПИСЬ НЕ ДОЛЖНА БЫТЬ ШИРЕ ШАГА МЕЖДУ КНОПКАМИ.
     120 пикселей задумывались под монитор, где иконки крупные и стоят просторно.
     На телефоне иконка ужимается сильно (px), а зазор между колонками — ещё
     сильнее (gap, это воздух), и подпись оказывалась заметно шире собственной
     кнопки: «Квесты» налезали на «Магазин», «Инвентарь» на «Карту».
     Привязываем ширину к самой кнопке и разрешаем шрифту ужиматься: слово
     останется целым, а за свою колонку не вылезет. ]]
label.BackgroundTransparency = 1
label.BorderSizePixel = 0
label.Font = Enum.Font.GothamBold
label.TextSize = Hud.text(16)
label.Text = "Карта"
label.AutoLocalize = true
label.TextColor3 = Color3.new(1, 1, 1)
label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
label.TextStrokeTransparency = 0.3
label.ZIndex = 4
label.Parent = button

local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
button.MouseEnter:Connect(function()
	TweenService:Create(scale, HOVER, { Scale = 1.05 }):Play()
end)
button.MouseLeave:Connect(function()
	TweenService:Create(scale, HOVER, { Scale = 1 }):Play()
end)

-- ── состояние по дню ──
local unlocked = true

local function currentDay()
	local dc = ReplicatedStorage:FindFirstChild("DayCount")
	return (dc and tonumber(dc.Value)) or 1
end

local function refresh()
	unlocked = currentDay() >= OPEN_FROM_DAY
	button.Image = unlocked and ICON_OPEN or ICON_LOCKED
	-- закрытая приглушена: видно, что она есть, но ещё не работает
	button.ImageTransparency = unlocked and 0 or 0.25
	label.TextTransparency = unlocked and 0 or 0.35
end

task.spawn(function()
	local dc = ReplicatedStorage:WaitForChild("DayCount", 30)
	refresh()
	if dc then dc.Changed:Connect(refresh) end
end)
refresh()

button.Activated:Connect(function()
	if not unlocked then
		-- лёгкий отказ: качнуть иконку, чтобы клик не выглядел «не нажалось»
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 0.92 }):Play()
		task.delay(0.08, function()
			TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
		end)
		return
	end
	if typeof(_G.OpenMapMenu) == "function" then
		pcall(_G.OpenMapMenu)
	end
end)

-- ── прячемся под полноэкранными меню, как это делают «Квесты» ──
local function isOverlayOpen()
	for _, key in ipairs({ "PhoneScreenGui", "QuestMenuScreenGui", "BuildingScreenGui",
		"MapMenuScreenGui" }) do
		local g = _G[key]
		if g and g:IsA("ScreenGui") and g.Enabled then return true end
	end
	return false
end

RunService.Heartbeat:Connect(function()
	gui.Enabled = not isOverlayOpen()
end)
