local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	КНОПКА «МАГАЗИН» в левом столбике HUD.

	Стоит на бывшем месте карты — верхняя строка правой колонки, вплотную к
	«Квестам»; сама карта опустилась на строку ниже (см. ROW_STEP в MapButton).

	⚠️ ЧИСЛА БЕРУТСЯ ОТ КНОПКИ КВЕСТОВ, И ТЕМИ ЖЕ ВЫЗОВАМИ HudScale.
	Кнопки столбика отсчитываются друг от друга. Сожми одну другим множителем —
	и они наедут: на телефоне это уже случалось. Поэтому здесь ровно те же
	gap/px/step, что в QuestEntryButton и MapButton, и менять их нужно всем разом.

	⚠️ ОТКРЫВАТЬ ПОКА НЕЧЕГО.
	Магазина в океане нет: ни окна, ни ремоута — я искал по обоим проектам.
	Кнопка ищет `_G.OpenShop` и зовёт его, если появится; пока его нет — говорит
	об этом игроку одной карточкой вместо того, чтобы молча ничего не делать.
	Когда окно магазина появится, ему достаточно объявить `_G.OpenShop` — здесь
	править ничего не придётся.

	⚠️ ТЕКСТ КАРТОЧКИ ЗАВИСИТ ОТ ЧУЖОГО ПРОЕКТА.
	Он называет место, где пушки покупаются на самом деле, а место это живёт в
	лобби (Lobby/WeaponUpgradeUI, меню «Арсенал»). Переедет покупка ещё раз —
	править надо и здесь, иначе подсказка снова начнёт врать.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Hud = require(ReplicatedStorage:WaitForChild("HudScale"))

-- те же числа, что у «Квестов» и «Карты»
local QUEST_X, QUEST_SIZE, QUEST_Y = Hud.gap(19), Hud.px(78), -Hud.step(128)
local GAP  = Hud.gap(10)
local SIZE = QUEST_SIZE

local SHOP_ICON = "rbxassetid://102918660786025"

local gui = Instance.new("ScreenGui")
gui.Name = "ShopButtonGui"
gui.ResetOnSpawn = false
-- ⚠️ false, как было: флаг действует и на компьютере, где раскладка выверена
-- (подробный разбор — в QuestEntryButton).
gui.IgnoreGuiInset = false
gui.DisplayOrder = 90
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local button = Instance.new("ImageButton")
button.Name = "ShopButton"
button.AnchorPoint = Vector2.new(0, 0.5)
button.Position = UDim2.new(0, QUEST_X + QUEST_SIZE + GAP, 0.5, QUEST_Y)
button.Size = UDim2.fromOffset(SIZE, SIZE)
button.BackgroundTransparency = 1
button.BorderSizePixel = 0
button.AutoButtonColor = false
button.Image = SHOP_ICON
button.ScaleType = Enum.ScaleType.Fit   -- Fit, а не Stretch: иконка не плющится
button.Parent = gui

local scale = Instance.new("UIScale")
scale.Parent = button

-- подпись — копия «Карты»: тот же шрифт, кегль и посадка внутри кнопки
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
label.Text = "Магазин"
label.AutoLocalize = true
label.TextColor3 = Color3.new(1, 1, 1)
label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
label.TextStrokeTransparency = 0.3
label.ZIndex = 4
label.Parent = button

local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
button.MouseEnter:Connect(function()
	TweenService:Create(scale, HOVER, { Scale = 1.07 }):Play()
end)
button.MouseLeave:Connect(function()
	TweenService:Create(scale, HOVER, { Scale = 1 }):Play()
end)

button.Activated:Connect(function()
	if typeof(_G.OpenShop) == "function" then
		local ok, err = pcall(_G.OpenShop)
		if ok then return end
		warn("[Магазин] окно упало при открытии: " .. tostring(err))
	end
	if typeof(_G.Notify) == "function" then
		pcall(_G.Notify, {
			type = "info",
			icon = "🛒",
			title = "Магазин",
			--[[ ⚠️ ПРО ЛОББИ ЗДЕСЬ БОЛЬШЕ НЕ ПИШЕМ.
			     Раньше строка обещала «открывается в лобби», и это перестало быть
			     правдой: меню «Магазин» в лобби владелец закрыл, кнопка там будет
			     отвечать за другое, а покупка пушек переехала в арсенал. Отправлять
			     игрока в лобби за магазином, которого там нет, — худший вид подсказки:
			     он выйдет из рейса ради пустого экрана. ]]
			body = "Пока закрыт. Пушки покупаются в лобби, в меню «Арсенал».",
		})
	end
end)

-- ── прячемся под полноэкранными меню, ровно как «Квесты» и «Карта» ──
-- Список окон держать ОДИНАКОВЫМ с MapButton: разъедутся — одна кнопка столбика
-- останется висеть поверх открытого меню, и это сразу видно.
local function isOverlayOpen()
	for _, key in ipairs({ "PhoneScreenGui", "QuestMenuScreenGui", "BuildingScreenGui",
		"MapMenuScreenGui" }) do
		local g = _G[key]
		if g and g:IsA("ScreenGui") and g.Enabled then return true end
	end
	return false
end

game:GetService("RunService").Heartbeat:Connect(function()
	gui.Enabled = not isOverlayOpen()
end)

print("[Магазин] кнопка готова (на месте карты, карта — строкой ниже)")
