local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- SettingsButton.client.lua
-- Кнопка «Настройки» в левом столбике HUD, ПОД иконкой инвентаря. Стиль 1-в-1 с
-- кнопкой инвентаря (InventoryUI): иконка 76px + подпись GothamBold 16 с обводкой,
-- наезжает на низ иконки. Клик → _G.OpenSettingsMenu(), когда меню появится
-- (пока меню нет — печатает заглушку в Output).

local Players = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SETTINGS_ICON = "rbxassetid://79587250133011"

local gui = Instance.new("ScreenGui")
gui.Name = "SettingsButton"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 8
gui.Parent = playerGui

-- столбик слева: Квесты (выше центра) → Инвентарь (центр, bpHolder 92x102) → Настройки (ниже)
-- ⚠️ ШАГ ВНИЗ ТОЖЕ МАСШТАБИРУЕТСЯ, А НЕ ТОЛЬКО РАЗМЕР.
-- Сожми иконку и оставь отступ 82 — кнопка уедет от инвентаря и столбик развалится.
-- Коэффициент общий на весь HUD, живёт в HudScale (см. QuestEntryButton, MapButton).
local Hud = require(game:GetService("ReplicatedStorage"):WaitForChild("HudScale"))

local holder = Instance.new("Frame")
holder.AnchorPoint = Vector2.new(0, 0.5)
-- шаг вниз — step(), как у остальных в столбике (см. HudScale.step)
holder.Position = UDim2.new(0, Hud.gap(12), 0.5, Hud.step(82))
holder.Size = UDim2.fromOffset(92, 102)
holder.BackgroundTransparency = 1
holder.Parent = gui

local btn = Instance.new("ImageButton")
btn.Name = "OpenSettings"
btn.AnchorPoint = Vector2.new(0.5, 0)
btn.Position = UDim2.new(0.5, 0, 0, 0)
btn.Size = UDim2.fromOffset(76, 76)
btn.BackgroundTransparency = 1
btn.Image = SETTINGS_ICON
btn.ScaleType = Enum.ScaleType.Fit
btn.Parent = holder

local scale = Instance.new("UIScale")
scale.Parent = btn
btn.MouseEnter:Connect(function() scale.Scale = 1.07 end)
btn.MouseLeave:Connect(function() scale.Scale = 1 end)

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0.5)
--[[ ⚠️ ПИКСЕЛИ, А НЕ ДОЛЯ ВЫСОТЫ.
     Долей (0.92) я это уже пробовал, и на компьютере подпись уехала вниз: у
     «Инвентаря» родитель — холдер 92×102, а не сама кнопка 76×76, и 92% от
     холдера это на два десятка пикселей ниже нужного. Доля тут вообще
     обманчива: у двух подписей разные родители.
     Число 70 — авторское, оно и было верным для кнопки.

     ⚠️ И ВОТ ЗДЕСЬ ЧИСЛА ИДУТ СЫРЫМИ, БЕЗ px(). Это не оплошность, а
     единственный верный вариант: холдер целиком сжат UIScale (внизу файла,
     applyScaleLive), а UIScale уже умножает ВСЁ внутри себя. Пропустив число
     ещё и через px(), я применял масштаб ДВАЖДЫ: 70 → 43 → 26, и подпись
     оказывалась не под иконкой, а на её середине, вдвое мельче соседних. На
     экране это читалось как «иконки налезли друг на друга».
     Внутри отмасштабированного холдера верстают в компьютерных пикселях —
     телефон досчитает сам. ]]
label.Position = UDim2.new(0.5, 0, 0, 70)
label.Size = UDim2.new(1, 6, 0, 20)
label.TextScaled = true
-- потолок кегля здесь ЛОКАЛЬНЫЙ, а у соседей по столбику — экранный: делим на
-- масштаб холдера, иначе подпись выходит мельче соседних (см. InventoryUI)
Instance.new("UITextSizeConstraint", label).MaxTextSize =
	math.floor(Hud.text(16) / math.max(Hud.iconFactor(), 0.1) + 0.5)
label.ZIndex = 2
label.BackgroundTransparency = 1
label.Text = "Настройки"
label.AutoLocalize = true
label.Font = Enum.Font.GothamBold
label.TextSize = 16   -- внутри UIScale-холдера числа сырые, см. выше
label.TextColor3 = Color3.new(1, 1, 1)
label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
label.TextStrokeTransparency = 0.3
label.Parent = holder

-- Сам холдер сжимаем целиком, одним UIScale — как у рюкзака (InventoryUI): так
-- внутренняя вёрстка (иконка, подпись, её наезд на низ) остаётся прежней. UIScale
-- вешаем на holder, а НЕ на btn: у кнопки свой занят наведением.
-- iconFactor, а не factor: этот холдер — кнопка в том же столбике, что Квесты и
-- Карта, и должен сжиматься тем же множителем, что их иконки (см. HudScale).
Hud.applyScaleLive(holder, Hud.iconFactor)

btn.Activated:Connect(function()
	if typeof(_G.OpenSettingsMenu) == "function" then
		_G.OpenSettingsMenu()
	else
		print("[SettingsButton] меню настроек ещё не подключено (_G.OpenSettingsMenu)")
	end
end)
