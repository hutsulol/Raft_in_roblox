-- VillagersHUD.client.lua
-- Счётчик валюты «жители» (Villagers). Читает атрибут игрока "Villagers" и
-- обновляется при его изменении (его ставит сервер — VillagersCurrency).
--
-- ⚠️ СТИЛЬ ВЗЯТ ИЗ ЛОББИ, из PirateBalanceHUD: иконка + крупное число
-- GothamBlack, белое с чёрной обводкой и жёсткой тенью на 3 px вниз, и
-- «набегание» числа при изменении. Правишь тут — посмотри и туда:
-- Lobby_Loongoliers/src/Lobby/PirateBalanceHUD.client.lua. Раньше это был
-- коричневый деревянный чип в правом верхнем углу — он спорил с плашкой дня.
--
-- ⚠️ ВЫСОТА. Строка стоит под «Настройками», но ВЫШЕ полос голода и жажды —
-- те прибиты к низу экрана, и на 188 px ниже центра счётчик на них наезжал.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Геометрия левого столбика (см. SettingsButton): холдер настроек стоит на
-- Position = (12, 0.5 + 82), Size = 92 × 102, иконки в нём центрованы по x = 58.
local ICON_IMG = "rbxassetid://107784608579591"
local ICON  = 44   -- пересчитывается ниже, после подключения HudScale
-- Ряд начинается ровно под ЛЕВЫМ КРАЕМ иконок столбика: холдер стоит на x = 12,
-- иконка в нём 76 из 92, значит её край на 12 + (92-76)/2 = 20. Центрировать по
-- оси иконок нельзя — строка растёт вправо и зрительно уезжает правее столбика.
-- ⚠️ СЧЁТЧИК — ЧАСТЬ НИЖНЕЙ СТОПКИ (сила, воздух, еда, вода, здоровье), А НЕ
-- ОТДЕЛЬНАЯ НАДПИСЬ ПОСРЕДИ ЭКРАНА.
-- Раньше он стоял от центра экрана и отсчитывался от подписи «Настройки», поэтому и
-- размер, и место были свои: на телефоне он уезжал на полосы и на хотбар и выглядел
-- вдвое крупнее всего вокруг.
-- Теперь геометрия взята у самой стопки (UIManager): якорь к НИЗУ экрана, тот же
-- левый отступ, тот же шаг между слотами и тот же размер иконки — счётчик просто
-- становится ещё одной её строкой, подложки у него по-прежнему нет.
-- ДЕРЖАТЬ РАВНЫМ UIManager: LEFT_X = 14, SLOT_PITCH = 42, иконки 28, кегль 20.
-- левый отступ и шаг теперь задаёт сама стопка (UIManager), здесь не нужны

local STACK_ICON      = 28
local STACK_TEXT_PX   = 20
-- ⚠️ СТРОКУ СОЗДАЁТ САМА СТОПКА, А НЕ МЫ.
-- Три захода мимо: счётчик позиционировался своими числами — то от центра экрана,
-- то от низа. Каждый раз он оказывался не там, и по очевидной причине: расстояние
-- от края экрана до стопки характеристик зависит от разрешения, а числа были
-- подобраны под один монитор. На телефоне счётчик попадал то в кнопки, то в хотбар.
-- Подгонять числа дальше бессмысленно — нужен ТОТ ЖЕ ЯКОРЬ, что у еды и воды.
-- Поэтому строку выдаёт UIManager своим же конструктором (_G.MakeStatSlot): она
-- приходит в его ScreenGui, с его левым отступом, шириной, высотой и его UIScale.
-- Своей геометрии у счётчика больше нет вовсе — есть только номер слота.
--
-- Слоты стопки, отсчёт от низа: здоровье -18, еда/вода -60, сила -102, кислород -144.
-- Кислород виден только под водой, поэтому его место и занимаем: над силой, ниже
-- кнопок столбика. Одно число — и оно из того же ряда, что у остальных слотов.
local SLOT_OFFSET = -144
ICON = STACK_ICON
local TEXT_PX = STACK_TEXT_PX

-- ⚠️ ЖДЁМ UIManager: он создаёт стопку и отдаёт конструктор наружу.
-- Порядок запуска клиентских скриптов Roblox не гарантирует, поэтому ждём с
-- ограничением — вешать на бесконечное ожидание нельзя, счётчик тогда не появится
-- вовсе и молча (этой ловушкой в проекте уже платили за WaitForChild).
local holder
do
	local deadline = os.clock() + 10
	while not _G.MakeStatSlot and os.clock() < deadline do task.wait(0.1) end
	if not _G.MakeStatSlot then
		warn("[Жители] UIManager не отдал _G.MakeStatSlot — счётчик показан не будет")
		return
	end
	holder = _G.MakeStatSlot("VillagersCounter", SLOT_OFFSET)
end
-- ширину задаёт содержимое: число бывает и трёхзначным
holder.AutomaticSize = Enum.AutomaticSize.X
holder.Size = UDim2.fromOffset(0, holder.Size.Y.Offset)

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = holder

-- значок жителей — как монета в лобби: сама картинка, без подложки и оправы
local icon = Instance.new("ImageLabel")
icon.Name = "Icon"
icon.BackgroundTransparency = 1
icon.Image = ICON_IMG
icon.ScaleType = Enum.ScaleType.Fit
icon.Size = UDim2.fromOffset(ICON, ICON)
icon.LayoutOrder = 1
icon.Parent = holder

local textHolder = Instance.new("Frame")
textHolder.Name = "AmountHolder"
textHolder.BackgroundTransparency = 1
textHolder.AutomaticSize = Enum.AutomaticSize.X
textHolder.Size = UDim2.fromOffset(0, holder.Size.Y.Offset)
textHolder.LayoutOrder = 2
textHolder.Parent = holder

local shadow = Instance.new("TextLabel")
shadow.Name = "AmountShadow"
shadow.BackgroundTransparency = 1
shadow.FontFace = Font.fromEnum(Enum.Font.GothamBlack)
-- в лобби 34, но там только цифры; со словом «Жители:» строка вылезала бы за
-- левый столбик, поэтому кегль чуть меньше
shadow.TextSize = TEXT_PX
shadow.TextColor3 = Color3.new(0, 0, 0)
shadow.TextXAlignment = Enum.TextXAlignment.Left
shadow.AutomaticSize = Enum.AutomaticSize.X
shadow.Size = UDim2.fromOffset(0, holder.Size.Y.Offset)
shadow.Position = UDim2.fromOffset(0, 3)
shadow.Parent = textHolder

local strokeSh = Instance.new("UIStroke")
strokeSh.Thickness = 2
strokeSh.Color = Color3.new(0, 0, 0)
strokeSh.Parent = shadow

local amount = shadow:Clone()
amount.Name = "Amount"
amount.TextColor3 = Color3.new(1, 1, 1)
amount.Position = UDim2.fromOffset(0, 0)
amount.Parent = textHolder

local function fmtNum(n)
	local s, out, count = tostring(n), "", 0
	for i = #s, 1, -1 do
		out = s:sub(i, i) .. out
		count += 1
		if count % 3 == 0 and i > 1 then out = " " .. out end
	end
	return out
end

-- «Набегание» числа при изменении. Длительность фиксированная — любая сумма
-- набегает за ANIM_TIME, сколько бы в ней ни было разрядов.
local ANIM_TIME = 0.35

local displayed, target = 0, 0
local animFrom, animT = 0, 0
local animConn
local gotFirstValue = false

local function setText(v)
	local text = "Жители: " .. fmtNum(math.floor(v + 0.5))
	amount.Text = text
	shadow.Text = text
end

local function applyValue(v, instant)
	target = v
	if instant then
		if animConn then animConn:Disconnect() animConn = nil end
		displayed = v
		setText(v)
		return
	end
	animFrom, animT = displayed, 0
	if animConn then return end
	animConn = RunService.Heartbeat:Connect(function(dt)
		animT = math.min(ANIM_TIME, animT + dt)
		local a = animT / ANIM_TIME
		a = 1 - (1 - a) * (1 - a)   -- ease-out
		displayed = animFrom + (target - animFrom) * a
		setText(displayed)
		if animT >= ANIM_TIME then
			displayed = target
			setText(displayed)
			animConn:Disconnect()
			animConn = nil
		end
	end)
end

player:GetAttributeChangedSignal("Villagers"):Connect(function()
	-- ПЕРВОЕ значение — загрузка из базы, а не заработок: показываем сразу,
	-- иначе на каждом заходе счётчик демонстративно набегал бы с нуля.
	applyValue(player:GetAttribute("Villagers") or 0, not gotFirstValue)
	gotFirstValue = true
end)

local initial = player:GetAttribute("Villagers")
if initial then
	gotFirstValue = true
	applyValue(initial, true)
else
	setText(0)
end

-- ⚠️ ШКАЛА СИЛЫ ЖИВЁТ НЕ ЗДЕСЬ, А В UIManager.
-- Собранная тут, она вставала со сдвигом относительно воды и еды: у этого файла
-- своя геометрия (отступ слева, размер иконки, ширина полосы), и совпасть с
-- нижним стеком она могла бы только подгонкой чисел на глаз. В UIManager она
-- строится теми же helper'ами, что вода, еда и жизнь, — и совпадает по
-- построению.

print("[Жители] HUD готов (стиль баланса пиратов из лобби)")
