local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- SettingsMenu.client.lua
-- Меню настроек 1-в-1 по хендоффу "Settings Menu Roblox.dc.html":
-- тёмно-синяя панель (#0e1f30, чёрная рамка 4px), шапка с точечным паттерном и
-- иконо-боксом ⚙, три карточки:
--   1) «Громкость океана» — слайдер 0..100% (правит SeaAmbience через _G.OceanVolumeScale);
--   2) «Баланс» — ввод числа + кнопки −/+100 (сервер ставит атрибут "Pirate");
--   3) «Выдать ресурс» — выпадающий список (Дерево/Пластик/Листья/Факел/Патроны) +
--      количество + «Получить» (Патроны = пополнить запас на всех пушках).
-- Открывается кнопкой «Настройки» (_G.OpenSettingsMenu). Закрытие: ✕ / фон / Esc.

local Players           = game:GetService("Players")
-- общая тема: отсюда берётся кнопка закрытия, одинаковая во всех меню океана
local UITheme = require(game:GetService("ReplicatedStorage"):WaitForChild("UITheme"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote    = ReplicatedStorage:WaitForChild("SettingsAction")

--[[ ⚠️ ОБЫЧНОМУ ИГРОКУ ЗДЕСЬ ТОЛЬКО ГРОМКОСТЬ.
     Всё остальное в этом меню — служебное: выдать ресурсы, накинуть баланс,
     убить, перемотать день, поднять остров, запустить катсцену. Сервер их и
     раньше не выполнял никому, кроме админов (см. isAdmin в
     SettingsMenuActions), но кнопки видели ВСЕ — и меню читалось как «в игре
     есть читы, просто не работают». Нерабочая кнопка хуже отсутствующей: она
     обещает то, чего нет, и на бета-тесте про неё спрашивает каждый второй.
     ⚠️ ПРАВИЛО ОБЯЗАНО СОВПАДАТЬ С СЕРВЕРНЫМ, иначе кнопка будет видна и
     мертва (или наоборот — админ останется без неё). Поэтому три источника,
     те же самые: список из конфига, владелец плейса и Studio. Владелец
     ГРУППОВОГО плейса проверяется рангом: у группы CreatorId — это id самой
     группы, и сравнение с UserId не совпадёт никогда. ]]
local isAdmin = false
do
	local RunService = game:GetService("RunService")
	if RunService:IsStudio() then
		isAdmin = true
	else
		local ok, cfg = pcall(function()
			return require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig", 5))
		end)
		local list = (ok and cfg and cfg.ADMIN_USER_IDS) or {}
		if table.find(list, player.UserId) then
			isAdmin = true
		elseif game.CreatorType == Enum.CreatorType.User then
			isAdmin = player.UserId == game.CreatorId
		elseif game.CreatorType == Enum.CreatorType.Group then
			local okRank, rank = pcall(function()
				return player:GetRankInGroup(game.CreatorId)
			end)
			isAdmin = (okRank and rank == 255) or false
		end
	end
end

-- ── палитра хендоффа ──
local PANEL   = Color3.fromHex("0e1f30")
local HEADER  = Color3.fromHex("1a3a58")
local CARD    = Color3.fromHex("12293d")
local WELL    = Color3.fromHex("0a1826")
local BLUE    = Color3.fromHex("2a7fd4")
local KNOB    = Color3.fromHex("4a90dc")
local CYAN    = Color3.fromHex("4ac9e2")
local GOLD    = Color3.fromHex("ffd23a")
local GREEN   = Color3.fromHex("35b435")
local RED     = Color3.fromHex("c93a3a")
local ORANGE  = Color3.fromHex("e2571f")
local SUBT    = Color3.fromHex("7fa8c9")
local ROWHOV  = Color3.fromHex("1d4266")
local WHITE   = Color3.new(1, 1, 1)
local BLACK   = Color3.new(0, 0, 0)
local FONT    = Enum.Font.GothamBlack -- кириллица (M PLUS Rounded нет в Roblox)
local FONT_B  = Enum.Font.GothamBold

-- ── ресурсы выдачи (иконки — реальные ассеты игры) ──
local RESOURCES = {
	{ key = "Log",     name = "Дерево",  icon = "rbxassetid://116178347748793" },
	{ key = "Plastic", name = "Пластик", icon = "rbxassetid://132919988751848" },
	{ key = "Leaves",  name = "Листья",  icon = "rbxassetid://96691360298069" },
	{ key = "Stone",   name = "Камень",  icon = "rbxassetid://96450657403376" },
	{ key = "Rubbish", name = "Мусор",   icon = "rbxassetid://134054228230432" },
	{ key = "Seaweed", name = "Водоросли", icon = "rbxassetid://135792112167502" },
	{ key = "Iron_Ore", name = "Железная руда", icon = "rbxassetid://78456892304314" },
	-- Овощи: их же и сажают на грядке (посадил 1 — собрал 3)
	{ key = "Potato",  name = "Картофель", icon = "rbxassetid://114389346130909" },
	{ key = "Beet",    name = "Свёкла",    icon = "rbxassetid://80108091374305" },
	-- сырая еда для проверки мангала (жарится и на костре, и на гриле)
	{ key = "Blue_Fish",    name = "Синяя рыба",   icon = "rbxassetid://79355503342560" },
	{ key = "Carp_Fish",    name = "Карп",         icon = "rbxassetid://122400137030638" },
	{ key = "Tilapia_Fish", name = "Тилапия",      icon = "rbxassetid://102206483084738" },
	{ key = "Meat",         name = "Мясо",         icon = "rbxassetid://140237721809215" },
	{ key = "Torch",   name = "Факел",   icon = "rbxassetid://131695611244502", cap = 5 },
	{ key = "Ammo",    name = "Патроны — на все пушки", icon = "rbxassetid://109564189076821" },
	{ key = "Cannon",        name = "Пушка",    icon = "rbxassetid://118236242385241", cap = 3 },
	{ key = "Deffender",     name = "ПВО",      icon = "rbxassetid://86928740553428",  cap = 3 },
	{ key = "Pulemet_lvl_1", name = "Пулемёт",     icon = "rbxassetid://106277044945645", cap = 3 },
	{ key = "Pulemet_lvl_2", name = "Пулемёт II",  icon = "rbxassetid://79105833790080", cap = 3 },
	{ key = "Revolver",   name = "Револьвер", icon = "rbxassetid://133241956272699", cap = 3 },
	{ key = "Pirate_Gun", name = "Пират Ган", icon = "rbxassetid://92804972080593",  cap = 3 },
}

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function stroke(inst, color, th)
	return new("UIStroke", { Color = color or BLACK, Thickness = th or 3 }, inst)
end

-- ══════════ каркас ══════════
local screen = new("ScreenGui", {
	Name = "SettingsMenu", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 120, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local backdrop = new("TextButton", {
	Text = "", AutoButtonColor = false, Modal = true,
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.45,
}, screen)

-- ⚠️ ВЫСОТА ПАНЕЛИ ФИКСИРОВАННАЯ, КАРТОЧКИ — В СКРОЛЛЕ. Карточек набралось
-- столько, что панель «во весь рост» (1068) уже не влезала в экран и UIScale
-- ужимал её в нечитаемое. Теперь тело панели — ScrollingFrame: новые карточки
-- просто удлиняют канвас, высоту панели больше трогать не нужно.
--[[ ⚠️ ВЫСОТА ПАНЕЛИ ЗАВИСИТ ОТ ТОГО, КОМУ ОНА ПОКАЗАНА.
     У обычного игрока в меню ровно одна карточка. Панель в 720 пикселей была
     бы пустой коробкой с полоской громкости наверху — по ней сразу видно, что
     что-то спрятали. ]]
local PANEL_W, PANEL_H = 620, isAdmin and 720 or 244
local panel = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(PANEL_W, PANEL_H), BackgroundColor3 = PANEL, BorderSizePixel = 0, ZIndex = 2,
}, screen)
stroke(panel, BLACK, 4)
local uiScale = new("UIScale", {}, panel)
local function fitScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	-- поля по 40 с каждой стороны; считаем от размеров панели, чтобы новая
	-- карточка не вылезала за экран на маленьких мониторах.
	-- ⚠️ НА ТЕЛЕФОНЕ ПОЛЯ НАМНОГО ШИРЕ.
	-- Расчёт и так подгонял панель под экран, но «влезает» и «удобно» — разные вещи:
	-- при полях по 40 панель занимала телефон целиком, до краёв. Просим больше
	-- воздуха — панель садится процентов на семьдесят экрана, и видно, что за ней
	-- игра, а не только меню.
	local pad = require(game:GetService("ReplicatedStorage"):WaitForChild("HudScale"))
		.isPhone() and 260 or 80
	uiScale.Scale = math.clamp(math.min(vp.X / (PANEL_W + pad), vp.Y / (PANEL_H + pad)), 0.4, 1)
end
fitScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale)
end

-- ── шапка с точечным паттерном ──
local header = new("Frame", {
	Size = UDim2.new(1, 0, 0, 84), BackgroundColor3 = HEADER, BorderSizePixel = 0,
	ClipsDescendants = true, ZIndex = 3,
}, panel)
do -- сетка полупрозрачных точек 30×30 (как в меню квестов)
	for gy = 0, math.ceil(84 / 30) do
		for gx = 0, math.ceil(PANEL_W / 30) do
			local dot = new("Frame", {
				Position = UDim2.fromOffset(gx * 30 + 8, gy * 30 + 8), Size = UDim2.fromOffset(7, 7),
				BackgroundColor3 = WHITE, BackgroundTransparency = 0.94, BorderSizePixel = 0, ZIndex = 3,
			}, header)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
		end
	end
end
new("Frame", { -- нижняя чёрная линия шапки
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 4,
}, header)

local hIcon = new("TextLabel", {
	Position = UDim2.fromOffset(20, 13), Size = UDim2.fromOffset(54, 54),
	BackgroundColor3 = BLUE, BorderSizePixel = 0, Font = FONT, Text = "⚙",
	TextSize = 28, TextColor3 = WHITE, TextStrokeColor3 = BLACK, TextStrokeTransparency = 0, ZIndex = 5,
}, header)
stroke(hIcon, BLACK, 3)

new("TextLabel", {
	Position = UDim2.fromOffset(88, 14), Size = UDim2.fromOffset(400, 36),
	BackgroundTransparency = 1, Font = FONT, Text = "Настройки", TextSize = 30,
	TextColor3 = WHITE, TextStrokeColor3 = BLACK, TextStrokeTransparency = 0,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5,
}, header)
new("TextLabel", {
	Position = UDim2.fromOffset(88, 50), Size = UDim2.fromOffset(400, 18),
	BackgroundTransparency = 1, Font = FONT_B, TextSize = 14,
	-- подпись честная: обычному игроку перечислять то, чего он не увидит, незачем
	Text = isAdmin and "Звук, баланс, выдача ресурсов и тесты" or "Громкость окружения",
	TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5,
}, header)

--[[ ── ГДЕ МЫ И КАКАЯ ЭТО СБОРКА ──
     Мелкой строкой в углу шапки: «v1_po» — версия и код среды, где вторая
     буква отличает океан от лобби (см. BuildInfo.tag). Открытым текстом
     «ПРОД · океан» здесь больше не пишем: своим эта метка понятна, чужим
     не сообщает ни числа плейсов, ни того, какой из них боевой.
     ⚠️ ПОД КРЕСТИКОМ НЕ ПИШЕМ, И ОТСТУПА ПО ВЫСОТЕ ОКАЗАЛОСЬ МАЛО.
     Кнопка закрытия налезает на правый ВЕРХНИЙ угол панели. Строка стояла у
     нижнего края шапки и формально в квадрат не попадала, но упиралась в него
     вплотную — читалось как «версия под крестиком». Сдвигаем её ЛЕВЕЕ кнопки
     (58 пикселей ширины плюс воздух), а не только ниже.
     Строку считает общий модуль: тот же текст понадобится и в других меню, а
     две копии разъехались бы при первом же новом плейсе. ]]
do
	local ok, BuildInfo = pcall(function()
		return require(ReplicatedStorage:WaitForChild("BuildInfo", 10))
	end)
	if ok and BuildInfo then
		local label = BuildInfo.label()
		new("TextLabel", {
			AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -76, 1, -8),
			Size = UDim2.fromOffset(320, 18), BackgroundTransparency = 1,
			Font = FONT_B, Text = label, TextSize = 13,
			TextColor3 = WHITE, TextTransparency = 0.25,
			TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5,
		}, header)
		-- ⚠️ И В ЛОГ ТОЖЕ, А НЕ ТОЛЬКО НА ЭКРАН.
		-- Строка в углу отвечает на вопрос «где я», но НЕ отвечает на «доехал ли
		-- вообще новый код»: если у игрока крутится старая сборка, там и подписи
		-- никакой нет — и понять это по пустому углу нельзя. В консоли (F9)
		-- строчка либо есть, либо её нет, и это уже ответ.
		print("[Сборка] " .. label)
	else
		warn("[SettingsMenu] BuildInfo не загрузился — версию и окружение не показать")
	end
end

-- ── закрыть ──
--[[ ⚠️ КРЕСТИК ОДИН НА ВСЕ МЕНЮ ОКЕАНА, ЭТАЛОНОМ ВЛАДЕЛЕЦ НАЗВАЛ ИНВЕНТАРЬ.
     Кнопки закрытия разъехались по меню: здесь стоял свой вариант — большая
     картинка-ассет, которая ещё и подрастала под курсором, в инвентаре
     маленькая красная кнопка, где-то буква X шрифтом. Игрок читает их как один
     и тот же элемент управления, и разнобой выглядит небрежностью.
     Поэтому кнопку целиком собирает UITheme.closeButton — там же и размер
     (UITheme.CLOSE_SIZE). Он намеренно не параметризован: дай меню передавать
     свой — и через месяц крестики разойдутся снова, ровно так это и вышло в
     прошлый раз. Нужен другой размер — правится в модуле, одним числом.
     Посадку не передаём НАМЕРЕННО: умолчание модуля (правый верхний угол с
     отступом от кромок) и есть инвентарное, а прежняя посадка здесь была ровно
     такой же.
     ZIndex оставлен прежний: шапка панели и её чёрная линия рисуются на 3–5,
     ниже шестёрки кнопка ушла бы под них. ]]
local closeBtn = UITheme.closeButton({ parent = panel, zIndex = 6 })

-- ── тело панели: скролл под шапкой ──
local BODY_TOP = 88   -- шапка 84 + её чёрная линия
local body = new("ScrollingFrame", {
	Position = UDim2.fromOffset(0, BODY_TOP), Size = UDim2.new(1, 0, 1, -BODY_TOP),
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 8, ScrollBarImageColor3 = KNOB, ScrollBarImageTransparency = 0.15,
	VerticalScrollBarInset = Enum.ScrollBarInset.None,
	ElasticBehavior = Enum.ElasticBehavior.Never,
}, panel)

-- ── карточка-заготовка ──
-- y — по-прежнему «дизайнерская» координата от верха ПАНЕЛИ (как раньше), в
-- координаты скролла её переводит сама заготовка; канвас дотягивается сам.
--[[ ⚠️ СЛУЖЕБНЫЕ КАРТОЧКИ ОБЫЧНОМУ ИГРОКУ НЕ СОЗДАЮТСЯ ВООБЩЕ.
     Не «прячутся» — именно не создаются: спрятанная кнопка живёт в дереве, и
     до неё дотягивается кто угодно с exploit-ом. Карточка без родителя не
     рисуется и не принимает нажатий, а весь код ниже продолжает собирать её
     содержимое как обычно — ни одной проверки в двадцати местах.
     Первая карточка — громкость океана, она общая для всех. ]]
local cardsMade   = 0
local bodyCanvasH = 0
local function card(y, h)
	cardsMade += 1
	local host = (cardsMade == 1) and body or (isAdmin and body or nil)

	local c = new("Frame", {
		Position = UDim2.fromOffset(18, y - BODY_TOP), Size = UDim2.new(1, -36, 0, h),
		BackgroundColor3 = CARD, BorderSizePixel = 0, ZIndex = 3,
	}, host)
	stroke(c, BLACK, 3)

	-- канвас тянется только под то, что действительно видно
	if host then
		local bottom = y - BODY_TOP + h + 18
		if bottom > bodyCanvasH then
			bodyCanvasH = bottom
			body.CanvasSize = UDim2.fromOffset(0, bodyCanvasH)
		end
	end
	return c
end
-- иконо-бокс 44×44 в строке карточки
local function iconWell(parent, glyph, color)
	local w = new("TextLabel", {
		Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = WELL, BorderSizePixel = 0, Font = FONT, Text = glyph,
		TextSize = 22, TextColor3 = color, TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.3, ZIndex = 4,
	}, parent)
	stroke(w, BLACK, 2)
	return w
end
local function cardTitle(parent, text)
	return new("TextLabel", {
		Position = UDim2.fromOffset(68, 14), Size = UDim2.fromOffset(280, 44),
		BackgroundTransparency = 1, Font = FONT, Text = text, TextSize = 18,
		TextColor3 = WHITE, TextStrokeColor3 = BLACK, TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
	}, parent)
end

-- ══════════ карточка 1: громкость океана ══════════
local card1 = card(104, 104)
iconWell(card1, "≈", CYAN)
cardTitle(card1, "Громкость океана")

local volChip = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 21),
	Size = UDim2.fromOffset(64, 30), BackgroundColor3 = WELL, BorderSizePixel = 0,
	Font = FONT, Text = "100%", TextSize = 16, TextColor3 = GOLD,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, ZIndex = 4,
}, card1)
stroke(volChip, BLACK, 2)

-- слайдер: дорожка + заливка + ползунок
local sliderZone = new("TextButton", {
	Position = UDim2.fromOffset(16, 66), Size = UDim2.new(1, -32, 0, 26),
	BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 4,
}, card1)
local track = new("Frame", {
	Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 14),
	BackgroundColor3 = WELL, BorderSizePixel = 0, ZIndex = 4, ClipsDescendants = true,
}, sliderZone)
stroke(track, BLACK, 2)
local fill = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("2a9fc4"), BorderSizePixel = 0, ZIndex = 5,
}, track)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("6fd4e8")),
		ColorSequenceKeypoint.new(0.5, Color3.fromHex("2a9fc4")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("17708f")),
	}),
}, fill)
local knob = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.fromOffset(22, 26), BackgroundColor3 = KNOB, BorderSizePixel = 0, ZIndex = 6,
}, sliderZone)
stroke(knob, BLACK, 3)

local volume = math.floor(((_G.OceanVolumeScale or 1) * 100) + 0.5)
local function applyVolume(pct)
	volume = math.clamp(math.floor(pct + 0.5), 0, 100)
	volChip.Text = volume .. "%"
	fill.Size = UDim2.new(volume / 100, 0, 1, 0)
	knob.Position = UDim2.new(volume / 100, 0, 0, 0)
	_G.OceanVolumeScale = volume / 100 -- читает SeaAmbience
end
applyVolume(volume)

local sliderDrag = false
local function volFromInput(pos)
	local rel = (pos.X - sliderZone.AbsolutePosition.X) / math.max(sliderZone.AbsoluteSize.X, 1)
	applyVolume(math.clamp(rel, 0, 1) * 100)
end
sliderZone.InputBegan:Connect(function(input)
	if GamepadInput.isPrimary(input) then
		sliderDrag = true
		volFromInput(input.Position)
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if sliderDrag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		volFromInput(input.Position)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if GamepadInput.isPrimary(input) then
		sliderDrag = false
	end
end)

-- ══════════ карточка 2: баланс ══════════
local card2 = card(224, 72)
iconWell(card2, "⚙", GOLD)
cardTitle(card2, "Баланс")

local balBox -- forward (нужен кнопкам −/+)
local function sendBalance(v)
	v = math.clamp(math.floor(tonumber(v) or 0), 0, 1e9)
	remote:FireServer("setBalance", v)
end
local function makeBalBtn(xOff, text, color)
	local b = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, xOff, 0, 16),
		Size = UDim2.fromOffset(40, 40), BackgroundColor3 = color, BorderSizePixel = 0,
		Font = FONT, Text = text, TextSize = 20, TextColor3 = WHITE,
		TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
	}, card2)
	stroke(b, BLACK, 3)
	return b
end
local minusBtn = makeBalBtn(-176, "−", RED)
balBox = new("TextBox", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -62, 0, 16),
	Size = UDim2.fromOffset(110, 40), BackgroundColor3 = WELL, BorderSizePixel = 0,
	Font = FONT, Text = tostring(player:GetAttribute("Pirate") or 0), TextSize = 18,
	TextColor3 = GOLD, ClearTextOnFocus = false, ZIndex = 4,
}, card2)
stroke(balBox, BLACK, 3)
local plusBtn = makeBalBtn(-16, "+", GREEN)

local function curBalance() return player:GetAttribute("Pirate") or 0 end
minusBtn.Activated:Connect(function() sendBalance(math.max(0, curBalance() - 100)) end)
plusBtn.Activated:Connect(function() sendBalance(curBalance() + 100) end)
balBox.FocusLost:Connect(function(entered)
	local digits = balBox.Text:gsub("%D", "")
	if digits == "" then balBox.Text = tostring(curBalance()) return end
	if entered then sendBalance(digits) else balBox.Text = tostring(curBalance()) end
end)
player:GetAttributeChangedSignal("Pirate"):Connect(function()
	if not balBox:IsFocused() then balBox.Text = tostring(curBalance()) end
end)

-- ══════════ карточка 3: выдать ресурс ══════════
local card3 = card(312, 122)
-- ZIndexBehavior у этого ScreenGui = Sibling: глубина считается ПО РОДИТЕЛЯМ, и
-- при равном ZIndex выигрывает тот, кто создан позже. Карточка «Убить плот» идёт
-- следующей, поэтому она накрывала выпадающий список ресурсов, сколько бы ZIndex
-- ни стоял у самого списка. Поднимаем всю карточку выше соседних.
card3.ZIndex = 8
iconWell(card3, "▣", Color3.fromHex("e8b06a"))
cardTitle(card3, "Выдать ресурс")

local selected = 1
local dropOpen = false

-- кнопка-дропдаун
local dropBtn = new("TextButton", {
	Position = UDim2.fromOffset(16, 64), Size = UDim2.new(1, -240, 0, 46),
	BackgroundColor3 = WELL, BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 4,
}, card3)
stroke(dropBtn, BLACK, 3)
local selIcon = new("ImageLabel", {
	Position = UDim2.fromOffset(10, 11), Size = UDim2.fromOffset(24, 24),
	BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ZIndex = 5,
}, dropBtn)
selIcon.Image = RESOURCES[1].icon
local selName = new("TextLabel", {
	Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -70, 1, 0),
	BackgroundTransparency = 1, Font = FONT, Text = RESOURCES[1].name, TextSize = 15,
	TextColor3 = WHITE, TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5,
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5,
}, dropBtn)
local dropArrow = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0),
	Size = UDim2.fromOffset(18, 46), BackgroundTransparency = 1, Font = FONT,
	Text = "▼", TextSize = 13, TextColor3 = SUBT, ZIndex = 5,
}, dropBtn)

-- выпадающий список (поверх всего): СКРОЛЛ — видно 3 строки, остальные листаются,
-- чтобы список не вылезал за панель и все предметы были досягаемы
local DROP_VISIBLE_ROWS = 3
local dropList = new("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 50),
	Size = UDim2.new(1, 0, 0, math.min(#RESOURCES, DROP_VISIBLE_ROWS) * 40 + 2),
	CanvasSize = UDim2.fromOffset(0, #RESOURCES * 40),
	BackgroundColor3 = WELL, BorderSizePixel = 0, Visible = false, ZIndex = 10,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 6, ScrollBarImageColor3 = KNOB, ScrollBarImageTransparency = 0.15,
	VerticalScrollBarInset = Enum.ScrollBarInset.None,
	ElasticBehavior = Enum.ElasticBehavior.Never,
}, dropBtn)
stroke(dropList, BLACK, 3)

local function setSelected(i)
	selected = i
	selIcon.Image = RESOURCES[i].icon
	selName.Text = RESOURCES[i].name
	for j, row in ipairs(dropList:GetChildren()) do
		if row:IsA("TextButton") then
			row.BackgroundColor3 = (row.LayoutOrder == selected) and CARD or WELL
		end
	end
end
local function setDropOpen(open)
	dropOpen = open
	dropList.Visible = open
	dropArrow.Text = open and "▲" or "▼"
end
dropBtn.Activated:Connect(function() setDropOpen(not dropOpen) end)

for i, r in ipairs(RESOURCES) do
	local row = new("TextButton", {
		Position = UDim2.fromOffset(0, (i - 1) * 40), Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = (i == 1) and CARD or WELL, BorderSizePixel = 0,
		Text = "", AutoButtonColor = false, LayoutOrder = i, ZIndex = 11,
	}, dropList)
	new("Frame", { -- разделитель
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 12,
	}, row)
	new("ImageLabel", {
		Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(23, 23),
		Image = r.icon, BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit, ZIndex = 12,
	}, row)
	new("TextLabel", {
		Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -50, 1, 0),
		BackgroundTransparency = 1, Font = FONT, Text = r.name, TextSize = 14,
		TextColor3 = WHITE, TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12,
	}, row)
	row.MouseEnter:Connect(function() row.BackgroundColor3 = ROWHOV end)
	row.MouseLeave:Connect(function()
		row.BackgroundColor3 = (i == selected) and CARD or WELL
	end)
	row.Activated:Connect(function()
		setSelected(i)
		setDropOpen(false)
	end)
end

-- количество
local amountBox = new("TextBox", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -146, 0, 64),
	Size = UDim2.fromOffset(90, 46), BackgroundColor3 = WELL, BorderSizePixel = 0,
	Font = FONT, Text = "10", TextSize = 18, TextColor3 = GOLD, ClearTextOnFocus = false, ZIndex = 4,
}, card3)
stroke(amountBox, BLACK, 3)
amountBox.FocusLost:Connect(function()
	local digits = amountBox.Text:gsub("%D", "")
	amountBox.Text = (digits == "") and "10" or digits
end)

-- «Получить»
local grantBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 64),
	Size = UDim2.fromOffset(122, 46), BackgroundColor3 = GREEN, BorderSizePixel = 0,
	Font = FONT, Text = "Получить", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, card3)
stroke(grantBtn, BLACK, 3)

-- тост «Выдано: …» (зелёная рамка, под карточкой 3)
local toast = new("TextLabel", {
	Position = UDim2.fromOffset(18, PANEL_H - 14), Size = UDim2.new(1, -36, 0, 30),
	BackgroundColor3 = WELL, BorderSizePixel = 0, Visible = false,
	-- ЧИТАЕМОСТЬ: без чёрной обводки (жирный шрифт + обводка сливались в кашу на тёмном
	-- фоне), светлее зелёный и Bold вместо Black
	Font = Enum.Font.GothamBold, Text = "", TextSize = 15, TextColor3 = Color3.fromHex("7fe07a"),
	TextStrokeTransparency = 1, ZIndex = 20,
}, panel)
-- рамка вокруг БОКСА тоста, а не букв: UIStroke на текстовом объекте по умолчанию
-- (Contextual) обводит сами глифы — это и выглядело как «обводка» текста
new("UIStroke", { Color = GREEN, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, toast)
local toastToken = 0
local function showToast(text)
	toastToken += 1
	local my = toastToken
	toast.Text = text
	toast.Visible = true
	task.delay(2.2, function()
		if toastToken == my then toast.Visible = false end
	end)
end

grantBtn.Activated:Connect(function()
	local r = RESOURCES[selected]
	local n = math.clamp(tonumber(amountBox.Text) or 10, 1, 999)
	remote:FireServer("grant", r.key, n)
	if r.key == "Ammo" then
		showToast("Патроны пополнены на всех пушках")
	else
		showToast("Выдано: " .. r.name .. " x" .. (r.cap and math.min(n, r.cap) or n))
	end
end)

-- ══════════ карточка 4: убить плот (тест экрана game over) ══════════
local card4 = card(450, 72)
iconWell(card4, "☠", RED)
cardTitle(card4, "Убить плот (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(320, 18),
	BackgroundTransparency = 1, Font = FONT_B, Text = "Экран «Плот пошёл ко дну» и анимации",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, card4)

local killBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = RED, BorderSizePixel = 0,
	Font = FONT, Text = "Убить", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, card4)
stroke(killBtn, BLACK, 3)
killBtn.Activated:Connect(function()
	remote:FireServer("killRaft")
	-- закрываем настройки, чтобы поверх сразу показался экран game over
	screen.Enabled = false
end)

-- ══════════ карточка 5: начать ночь (тест ночной волны) ══════════
local card5 = card(538, 72)
iconWell(card5, "☾", BLUE)
cardTitle(card5, "Начать ночь (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(320, 18),
	BackgroundTransparency = 1, Font = FONT_B, Text = "Перемотать до заката; слева — номер дня (пусто = текущий)",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, card5)

-- Номер дня: «начать ночь 7-го дня» ради проверки поздних волн. Пусто —
-- день не трогаем, только перематываем к закату.
local nightDayBox = new("TextBox", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -146, 0, 14),
	Size = UDim2.fromOffset(64, 44), BackgroundColor3 = WELL, BorderSizePixel = 0,
	Font = FONT, Text = "", PlaceholderText = "день", TextSize = 18, TextColor3 = GOLD,
	ClearTextOnFocus = false, ZIndex = 4,
}, card5)
stroke(nightDayBox, BLACK, 3)
nightDayBox.FocusLost:Connect(function()
	nightDayBox.Text = nightDayBox.Text:gsub("%D", "")
end)

local nightBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = BLUE, BorderSizePixel = 0,
	Font = FONT, Text = "Ночь", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, card5)
stroke(nightBtn, BLACK, 3)
nightBtn.Activated:Connect(function()
	local day = tonumber(nightDayBox.Text)
	remote:FireServer("startNight", day and math.clamp(day, 1, 999) or nil)
	-- закрываем меню: закат и волну надо видеть, а не панель поверх них
	screen.Enabled = false
end)

-- ══════════ карточка 6: сохранить плот ══════════
-- Переехало сюда с постоянной кнопки в правом верхнем углу экрана: она висела
-- поверх игры всё время и мешала, а нажимают её редко. Автосейв при выходе и по
-- таймеру работает отдельно и от этой кнопки не зависит.
local saveEvent = ReplicatedStorage:WaitForChild("ManualRaftSave")

local card6 = card(626, 72)
iconWell(card6, "💾", GREEN)
cardTitle(card6, "Сохранить плот")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(320, 18),
	BackgroundTransparency = 1, Font = FONT_B, Text = "Записать текущий плот в слот",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, card6)

local saveBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GREEN, BorderSizePixel = 0,
	Font = FONT, Text = "Сохранить", TextSize = 15, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, card6)
stroke(saveBtn, BLACK, 3)

local saveBusy = false
saveBtn.Activated:Connect(function()
	if saveBusy then return end
	saveBusy = true
	saveBtn.Text = "Сохранение…"
	saveBtn.BackgroundColor3 = Color3.fromHex("b8b8b8")
	saveEvent:FireServer()
end)

saveEvent.OnClientEvent:Connect(function(ok, err)
	saveBusy = false
	saveBtn.Text = ok and "Сохранено ✓" or tostring(err or "Ошибка")
	saveBtn.BackgroundColor3 = ok and GREEN or RED
	-- Меню могут закрыть сразу после нажатия, поэтому возврат в исходный вид
	-- делаем по таймеру, а не по закрытию: иначе кнопка осталась бы «Сохранено»
	-- до следующего клика.
	task.delay(1.4, function()
		if saveBusy then return end
		saveBtn.Text = "Сохранить"
		saveBtn.BackgroundColor3 = GREEN
	end)
end)

-- ══════════ карточка 7: патрульный катер (тест экипажа) ══════════
local card7 = card(714, 72)
iconWell(card7, "⚓", RED)
cardTitle(card7, "Катер патруля (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(320, 18),
	BackgroundTransparency = 1, Font = FONT_B, Text = "Катер с экипажем прямо перед носом плота",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, card7)

local patrolBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = RED, BorderSizePixel = 0,
	Font = FONT, Text = "Выслать", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, card7)
stroke(patrolBtn, BLACK, 3)
patrolBtn.Activated:Connect(function()
	remote:FireServer("spawnPatrol")
	-- катер выходит за 600 студов от плота: панель поверх экрана только мешает
	screen.Enabled = false
end)

-- ══════════ карточка 8: грузовой катер (тест обыска) ══════════
local card8 = card(802, 72)
iconWell(card8, "📦", GREEN)
cardTitle(card8, "Грузовой катер (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(320, 18),
	BackgroundTransparency = 1, Font = FONT_B, Text = "Один охранник, палуба груза под обыск",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, card8)

local cargoBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GREEN, BorderSizePixel = 0,
	Font = FONT, Text = "Выслать", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, card8)
stroke(cargoBtn, BLACK, 3)
cargoBtn.Activated:Connect(function()
	remote:FireServer("spawnCargo")
	screen.Enabled = false
end)

-- ══════════ карточка 9: тропический остров (тест) ══════════
local card9 = card(890, 72)
iconWell(card9, "🏝️", GREEN)
cardTitle(card9, "Тропический остров (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B, Text = "По курсу плота, ближе обычного — чтобы дойти",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, card9)

local islandBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GREEN, BorderSizePixel = 0,
	Font = FONT, Text = "Поднять", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, card9)
stroke(islandBtn, BLACK, 3)
islandBtn.Activated:Connect(function()
	remote:FireServer("spawnIsland")
	-- остров встаёт по курсу: панель поверх экрана только мешает его увидеть
	screen.Enabled = false
end)

-- ══════════ карточка 10: пиратский остров (тест) ══════════
local card10 = card(978, 72)
iconWell(card10, "🏴‍☠️", RED)
cardTitle(card10, "Пиратский остров (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B, Text = "Лагерь с гарнизоном, пленными и живностью",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, card10)

local pirateIslandBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = RED, BorderSizePixel = 0,
	Font = FONT, Text = "Поднять", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, card10)
stroke(pirateIslandBtn, BLACK, 3)
pirateIslandBtn.Activated:Connect(function()
	remote:FireServer("spawnPirateIsland")
	screen.Enabled = false
end)

-- ══════════ карточка: туман шторма (тест) ══════════
-- ⚠️ ЗОВЁМ НАПРЯМУЮ, БЕЗ СЕРВЕРА. Туман рисует клиентский WaveTelegraph, и эта
-- панель — тоже клиент: гонять запрос на сервер и обратно незачем.
local cardFog = card(1066, 72)
iconWell(cardFog, "🌫️", CYAN)
cardTitle(cardFog, "Туман шторма (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B, Text = "Поднимает стену тумана с молниями на 45 секунд",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardFog)

local fogBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = CYAN, BorderSizePixel = 0,
	Font = FONT, Text = "Поднять", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardFog)
stroke(fogBtn, BLACK, 3)
fogBtn.Activated:Connect(function()
	if typeof(_G.TestStormFog) == "function" then
		pcall(_G.TestStormFog, 45)
	else
		warn("[SettingsMenu] _G.TestStormFog не найден (WaveTelegraph не загружен?)")
	end
	screen.Enabled = false   -- туман встаёт по курсу: панель только мешает смотреть
end)

-- ══════════ карточка 11: остров-терраса (тест) ══════════
local cardT = card(1154, 72)
iconWell(cardT, "🌋", ORANGE)
cardTitle(cardT, "Остров-терраса (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B, Text = "Ферма с полем вируса; куб и бочки взрываются",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardT)

local terraceBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = ORANGE, BorderSizePixel = 0,
	Font = FONT, Text = "Поднять", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardT)
stroke(terraceBtn, BLACK, 3)
terraceBtn.Activated:Connect(function()
	remote:FireServer("spawnTerraceIsle")
	screen.Enabled = false
end)

-- ══════════ карточка 12: рыбацкая лодка (тест) ══════════
local card11 = card(1242, 72)
iconWell(card11, "🎣", CYAN)
cardTitle(card11, "Рыбацкая лодка (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B, Text = "Проходит мимо плота; в сети улов — можно забрать",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, card11)

local skiffBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GREEN, BorderSizePixel = 0,
	Font = FONT, Text = "Выслать", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, card11)
stroke(skiffBtn, BLACK, 3)
skiffBtn.Activated:Connect(function()
	remote:FireServer("spawnSkiff")
	screen.Enabled = false
end)

-- ══════════ карточка 13: остров-верфь (тест) ══════════
local cardShip = card(1330, 72)
iconWell(cardShip, "⚓", ORANGE)
cardTitle(cardShip, "Остров-верфь (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Недостроенный корпус, четверо рабочих, две грядки вируса",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardShip)

local shipBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = ORANGE, BorderSizePixel = 0,
	Font = FONT, Text = "Поднять", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardShip)
stroke(shipBtn, BLACK, 3)
shipBtn.Activated:Connect(function()
	remote:FireServer("spawnShipIsle")
	screen.Enabled = false
end)

-- ══════════ карточка 14: малый остров (тест) ══════════
local cardSmall = card(1418, 72)
iconWell(cardSmall, "🏝️", ORANGE)
cardTitle(cardSmall, "Малый остров (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Хижина, грядка, двое пиратов в обходе, ребёнок в клетке",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardSmall)

local smallBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = ORANGE, BorderSizePixel = 0,
	Font = FONT, Text = "Поднять", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardSmall)
stroke(smallBtn, BLACK, 3)
smallBtn.Activated:Connect(function()
	remote:FireServer("spawnSmallIsle")
	screen.Enabled = false
end)

-- ══════════ карточка 15: осьминог (тест) ══════════
local cardOcto = card(1506, 72)
iconWell(cardOcto, "🐙", ORANGE)
cardTitle(cardOcto, "Осьминог (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Всплывает рядом с плотом; сто ударов, иначе уходит",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardOcto)

local octoBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = ORANGE, BorderSizePixel = 0,
	Font = FONT, Text = "Поднять", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardOcto)
stroke(octoBtn, BLACK, 3)
octoBtn.Activated:Connect(function()
	remote:FireServer("spawnOctopus")
	-- всплывает рядом с плотом: панель поверх экрана мешает его увидеть
	screen.Enabled = false
end)

-- ══════════ карточка 16: стартовый остров (тест) ══════════
-- Штатно эта сцена играет на второй день на 30% дня — ждать её ради проверки
-- катсцены и трёх квестов бессмысленно. Кнопка запускает ровно ту же цепочку.
local cardStart = card(1594, 72)
iconWell(cardStart, "🌴", GREEN)
cardTitle(cardStart, "Стартовый остров (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Катсцена, мысли, корова и цепочка из трёх квестов",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardStart)

local startBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GREEN, BorderSizePixel = 0,
	Font = FONT, Text = "Начать", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardStart)
stroke(startBtn, BLACK, 3)
startBtn.Activated:Connect(function()
	remote:FireServer("startIsleNow")
	-- катсцена забирает камеру: панель поверх экрана закрыла бы всю сцену
	screen.Enabled = false
end)

-- ══════════ карточка: остров-аванпост (тест сцены) ══════════
local cardOutpost = card(1770, 72)
iconWell(cardOutpost, "🏕️", GREEN)
cardTitle(cardOutpost, "Остров-аванпост (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Катсцена, двое на КПП, огнемёт и поле вируса",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardOutpost)

local outpostBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GREEN, BorderSizePixel = 0,
	Font = FONT, Text = "Начать", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardOutpost)
stroke(outpostBtn, BLACK, 3)
outpostBtn.Activated:Connect(function()
	remote:FireServer("outpostNow")
	-- катсцена забирает камеру: панель поверх экрана закрыла бы всю сцену
	screen.Enabled = false
end)

-- ══════════ карточка: встреча с повстанцем (тест концовки) ══════════
-- Отдельной кнопкой, потому что до разговора в обычной игре идти долго: снять
-- двоих, собрать огнемёт, выжечь поле. Кнопка снимает удержание зачистки и
-- сразу выводит повстанца — проверять реплики и последний квест можно подряд.
local cardRebel = card(1858, 72)
iconWell(cardRebel, "🤝", CYAN)
cardTitle(cardRebel, "Промотать остров (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Снимает гарнизон и жжёт поле — дальше всё по сценарию",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardRebel)

local rebelBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = CYAN, BorderSizePixel = 0,
	Font = FONT, Text = "Позвать", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardRebel)
stroke(rebelBtn, BLACK, 3)
rebelBtn.Activated:Connect(function()
	remote:FireServer("outpostMeet")
	-- он выходит перед игроком и идёт к нему: смотреть надо на остров, а не в меню
	screen.Enabled = false
end)

-- ══════════ карточка: остров фермеров (тест) ══════════
local cardFarm = card(1946, 72)
iconWell(cardFarm, "🌾", GREEN)
cardTitle(cardFarm, "Остров фермеров (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Два яруса, река и теплицы; 15 пиратов по площадкам",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardFarm)
local farmBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GREEN, BorderSizePixel = 0,
	Font = FONT, Text = "Поднять", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardFarm)
stroke(farmBtn, BLACK, 3)
farmBtn.Activated:Connect(function()
	remote:FireServer("spawnFarmersIsle")
	screen.Enabled = false
end)

-- ══════════ карточка: овца для сеткомёта (тест) ══════════
local cardNet = card(2034, 72)
iconWell(cardNet, "🐑", GREEN)
cardTitle(cardNet, "Овца для сеткомёта (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Ставит овцу перед игроком: стреляй сетью, неси, выпускай",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardNet)
local netBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GREEN, BorderSizePixel = 0,
	Font = FONT, Text = "Поставить", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardNet)
stroke(netBtn, BLACK, 3)
netBtn.Activated:Connect(function()
	remote:FireServer("spawnNetSheep")
	screen.Enabled = false
end)

-- ══════════ карточка: лодочник с наградой (тест) ══════════
local cardCourier = card(2122, 72)
iconWell(cardCourier, "🚣", GOLD)
cardTitle(cardCourier, "Лодочник с наградой (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Догоняет плот, несёт ящик, «Награда с рейдов»",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardCourier)
local courierBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GOLD, BorderSizePixel = 0,
	Font = FONT, Text = "Вызвать", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardCourier)
stroke(courierBtn, BLACK, 3)
courierBtn.Activated:Connect(function()
	remote:FireServer("raidCourier")
	screen.Enabled = false
end)

-- ══════════ карточка: остров крабов (тест) ══════════
local cardCrab = card(2210, 72)
iconWell(cardCrab, "🦀", RED)
cardTitle(cardCrab, "Остров крабов (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Остров по курсу, 4 краба, тестовая сабля в рюкзак",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardCrab)
local crabBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = RED, BorderSizePixel = 0,
	Font = FONT, Text = "Поднять", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardCrab)
stroke(crabBtn, BLACK, 3)
crabBtn.Activated:Connect(function()
	remote:FireServer("spawnCrabIsle")
	screen.Enabled = false
end)

-- ══════════ карточка: песчаная отмель (тест) ══════════
local cardShoal = card(2298, 72)
iconWell(cardShoal, "🏝", GOLD)
cardTitle(cardShoal, "Песчаная отмель (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Остров по курсу: один краб и один сундук",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardShoal)
local shoalBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GOLD, BorderSizePixel = 0,
	Font = FONT, Text = "Поднять", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardShoal)
stroke(shoalBtn, BLACK, 3)
shoalBtn.Activated:Connect(function()
	remote:FireServer("spawnShoalIsle")
	screen.Enabled = false
end)

-- ══════════ карточка: магазин торговца (тест) ══════════
local cardMerchant = card(2386, 72)
iconWell(cardMerchant, "🛒", GOLD)
cardTitle(cardMerchant, "Магазин торговца (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Торговец приплывает на 5 минут и открывает окно",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardMerchant)
local merchantBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GOLD, BorderSizePixel = 0,
	Font = FONT, Text = "Открыть", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardMerchant)
stroke(merchantBtn, BLACK, 3)
merchantBtn.Activated:Connect(function()
	remote:FireServer("spawnMerchant")
	screen.Enabled = false
end)

-- ══════════ карточка: блок фермы 2×2 (тест) ══════════
local cardFarm = card(2474, 72)
iconWell(cardFarm, "🌱", GREEN)
cardTitle(cardFarm, "Ферма 2×2 (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Выдаёт блок фермы: навестись на пол плота, нужно 2×2",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardFarm)
local farmBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GOLD, BorderSizePixel = 0,
	Font = FONT, Text = "Выдать", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardFarm)
stroke(farmBtn, BLACK, 3)
farmBtn.Activated:Connect(function()
	remote:FireServer("giveFarmBlock")
	screen.Enabled = false
end)

-- ══════════ карточка: дом фермера (тест) ══════════
local cardHut = card(2562, 72)
iconWell(cardHut, "🏠", GREEN)
cardTitle(cardHut, "Дом фермера (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Ставится вплотную к ферме 2×2, в нём живёт фермер",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardHut)
local hutBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GOLD, BorderSizePixel = 0,
	Font = FONT, Text = "Выдать", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardHut)
stroke(hutBtn, BLACK, 3)
hutBtn.Activated:Connect(function()
	remote:FireServer("giveFarmerHut")
	screen.Enabled = false
end)

-- ══════════ карточка: забытый кратер (тест) ══════════
local cardCrater = card(2650, 72)
iconWell(cardCrater, "🌋", GOLD)
cardTitle(cardCrater, "Забытый кратер (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Остров по курсу: 2 пирата-сторожа, 3 краба, 2 сундука",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardCrater)
local craterBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GOLD, BorderSizePixel = 0,
	Font = FONT, Text = "Создать", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardCrater)
stroke(craterBtn, BLACK, 3)
craterBtn.Activated:Connect(function()
	remote:FireServer("spawnCraterIsle")
	screen.Enabled = false
end)

-- ══════════ карточка: пак декора «Дефолт» (тест) ══════════
local cardDecorPack = card(2738, 72)
iconWell(cardDecorPack, "🎁", GOLD)
cardTitle(cardDecorPack, "Пак декора «Дефолт»")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Открывает вкладку «Пак: Дефолт» в крафте: 11 предметов",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardDecorPack)
local decorPackBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GOLD, BorderSizePixel = 0,
	Font = FONT, Text = "Получить", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardDecorPack)
stroke(decorPackBtn, BLACK, 3)
decorPackBtn.Activated:Connect(function()
	remote:FireServer("grantDecorPack")
	screen.Enabled = false
end)

-- ══════════ карточка: яхта торговца (тест) ══════════
-- do-блок: в файле почти 200 локалей, новые карточки не плодят их на верхнем уровне
do
	local cardYacht = card(2826, 72)
	iconWell(cardYacht, "⛵", GOLD)
	cardTitle(cardYacht, "Яхта торговца (тест)")
	new("TextLabel", {
		Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
		BackgroundTransparency = 1, Font = FONT_B,
		Text = "Яхта подходит к борту плота, E у прилавка — магазин",
		TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
	}, cardYacht)
	local btn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GOLD, BorderSizePixel = 0,
		Font = FONT, Text = "Вызвать", TextSize = 16, TextColor3 = WHITE,
		TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
	}, cardYacht)
	stroke(btn, BLACK, 3)
	btn.Activated:Connect(function()
		remote:FireServer("spawnMerchantYacht")
		screen.Enabled = false
	end)
end

-- ══════════ карточка: выживший в команду (тест) ══════════
do
	local cardSurv = card(2914, 72)
	iconWell(cardSurv, "👥", GOLD)
	cardTitle(cardSurv, "Выживший (тест)")
	new("TextLabel", {
		Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(200, 18),
		BackgroundTransparency = 1, Font = FONT_B,
		Text = "Роза 5★ · Билли 3★ · Cold Cap 5★",
		TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
	}, cardSurv)
	local btn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GOLD, BorderSizePixel = 0,
		Font = FONT, Text = "Добавить", TextSize = 16, TextColor3 = WHITE,
		TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
	}, cardSurv)
	btn.Text = "Роза"
	btn.Size = UDim2.fromOffset(96, 44)
	stroke(btn, BLACK, 3)
	btn.Activated:Connect(function()
		remote:FireServer("grantSurvivor", "rose")
	end)
	local btnP = btn:Clone()
	btnP.Position = UDim2.new(1, -120, 0, 14)
	btnP.Text = "Пират"
	btnP.Parent = cardSurv
	btnP.Activated:Connect(function()
		remote:FireServer("grantSurvivor", "pirate")
	end)
	local btnC = btn:Clone()
	btnP.Position = UDim2.new(1, -120, 0, 14)
	btnC.Position = UDim2.new(1, -224, 0, 14)
	btnC.Text = "Cold Cap"
	btnC.BackgroundColor3 = Color3.fromHex("38CFFF")
	btnC.Parent = cardSurv
	btnC.Activated:Connect(function()
		remote:FireServer("grantSurvivor", "coldcap")
	end)
end

-- ══════════ карточка: рыбацкое место (тест) ══════════
do
	local cardFish = card(3002, 72)
	iconWell(cardFish, "🎣", GOLD)
	cardTitle(cardFish, "Рыбацкое место (тест)")
	new("TextLabel", {
		Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
		BackgroundTransparency = 1, Font = FONT_B,
		Text = "Ставится на плот; работает рыбак или выживший",
		TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
	}, cardFish)
	local btn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GOLD, BorderSizePixel = 0,
		Font = FONT, Text = "Получить", TextSize = 16, TextColor3 = WHITE,
		TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
	}, cardFish)
	stroke(btn, BLACK, 3)
	btn.Activated:Connect(function()
		remote:FireServer("giveFishingSpot")
		screen.Enabled = false
	end)
end

-- ══════════ карточки: таверна (создание жителей) ══════════
do
	local c = card(3090, 72)
	iconWell(c, "🏛", GOLD)
	cardTitle(c, "Таверна (тест)")
	new("TextLabel", {
		Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
		BackgroundTransparency = 1, Font = FONT_B,
		Text = "Дом создания жителей 2×2, ставится на пол плота",
		TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
	}, c)
	local btn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GOLD, BorderSizePixel = 0,
		Font = FONT, Text = "Получить", TextSize = 16, TextColor3 = WHITE,
		TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
	}, c)
	stroke(btn, BLACK, 3)
	btn.Activated:Connect(function()
		remote:FireServer("giveIslandHall")
		screen.Enabled = false
	end)
end

do
	local c = card(3178, 72)
	iconWell(c, "⏩", GOLD)
	cardTitle(c, "Подготовка жителя (тест)")
	new("TextLabel", {
		Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
		BackgroundTransparency = 1, Font = FONT_B,
		Text = "Таверна сразу готова выдать жителя",
		TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
	}, c)
	local btn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GOLD, BorderSizePixel = 0,
		Font = FONT, Text = "Пропустить", TextSize = 16, TextColor3 = WHITE,
		TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
	}, c)
	stroke(btn, BLACK, 3)
	btn.Activated:Connect(function()
		remote:FireServer("skipRecruit")
	end)
end

-- ══════════ карточка: сюжет торговца — перемотка к визиту ══════════
do
	local c = card(3266, 72)
	iconWell(c, "⏭", GOLD)
	cardTitle(c, "Сюжет: к торговцу (тест)")
	new("TextLabel", {
		Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
		BackgroundTransparency = 1, Font = FONT_B,
		Text = "День и вечер следующего визита торговца",
		TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
	}, c)
	local btn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(122, 44), BackgroundColor3 = GOLD, BorderSizePixel = 0,
		Font = FONT, Text = "Перемотать", TextSize = 16, TextColor3 = WHITE,
		TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
	}, c)
	stroke(btn, BLACK, 3)
	btn.Activated:Connect(function()
		remote:FireServer("skipToMerchant")
		screen.Enabled = false
	end)
end

-- ══════════ карточка 17: удар магмы (тест эффектов) ══════════
-- Этим бьёт огненный корабль. Ждать его волну ради того, чтобы посмотреть на
-- осколки и огонь, бессмысленно — кнопка роняет такой же снаряд на игрока.
local cardMagma = card(1682, 72)
iconWell(cardMagma, "🌋", RED)
cardTitle(cardMagma, "Удар магмы (тест)")
new("TextLabel", {
	Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(340, 18),
	BackgroundTransparency = 1, Font = FONT_B,
	Text = "Шар падает сверху: осколки, столб огня и лужа",
	TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, cardMagma)

local magmaBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(122, 44), BackgroundColor3 = RED, BorderSizePixel = 0,
	Font = FONT, Text = "Сбросить", TextSize = 16, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.5, AutoButtonColor = true, ZIndex = 4,
}, cardMagma)
stroke(magmaBtn, BLACK, 3)
magmaBtn.Activated:Connect(function()
	remote:FireServer("magmaTest")
	-- панель закрываем: снаряд падает секунды две, и смотреть надо на плот,
	-- а не в меню — иначе весь удар пройдёт за спиной у настроек
	screen.Enabled = false
end)

-- ══════════ ЭКИПАЖ ПЛОТА: капитан высаживает игрока ══════════
--[[ ⚠️ КАРТОЧКА ВИДНА КАПИТАНУ, А НЕ ТОЛЬКО АДМИНУ. Остальные карточки прячет
     card() — они админские. Эта собирается отдельно и появляется у того, кому
     сервер (RaftCrew) выставил атрибут RaftOwner, и только когда на плоту есть
     кто-то ещё. Право высадки всё равно проверяет сервер.
     У обычного игрока панель низкая (одна карточка) — подращиваем её под
     список, иначе карточка пряталась бы под прокруткой. ]]
do
	local crewRemote = ReplicatedStorage:WaitForChild("RaftCrewAction", 15)
	local BASE_H = PANEL_H
	local crewY = isAdmin and (3266 + 72 + 16) or 224   -- ниже последней админской карточки
	local crew = new("Frame", {
		Position = UDim2.fromOffset(18, crewY - BODY_TOP), Size = UDim2.new(1, -36, 0, 72),
		BackgroundColor3 = CARD, BorderSizePixel = 0, ZIndex = 3, Visible = false,
	}, body)
	stroke(crew, BLACK, 3)
	iconWell(crew, "⚓", GOLD)
	cardTitle(crew, "Экипаж плота")
	new("TextLabel", {
		Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(420, 18),
		BackgroundTransparency = 1, Font = FONT_B, Text = "Ты лидер группы. Высаженный уедет в лобби и не вернётся в этот забег",
		TextSize = 12, TextColor3 = SUBT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
	}, crew)
	local rows = new("Frame", {
		Position = UDim2.fromOffset(14, 70), Size = UDim2.new(1, -28, 0, 0),
		BackgroundTransparency = 1, ZIndex = 4,
	}, crew)

	--[[ ⚠️ СПИСОК ВСЕГО ЭКИПАЖА, И КАРТОЧКА ВИДНА ЛИДЕРУ ВСЕГДА.
	     Раньше карточка появлялась, только когда на плоту кто-то есть кроме
	     капитана, и перечисляла одних «других» — лидер не видел, что механика
	     вообще существует. Теперь первым идёт он сам с пометкой «Капитан (ты)»,
	     дальше все участники с кнопкой «Высадить»; один на плоту — строка
	     «Кроме тебя на плоту никого нет». Лидер группы = владелец плота
	     (raftOwnerId из данных телепорта лобби, см. RaftCrew / RaftSaveSystem). ]]
	local armed = {}   -- [UserId] = до какого момента кнопка в режиме «Точно?»
	local function rebuild()
		for _, c in ipairs(rows:GetChildren()) do c:Destroy() end
		local others = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= player then table.insert(others, plr) end
		end
		local show = crewRemote ~= nil and player:GetAttribute("RaftOwner") == true
		crew.Visible = show
		local lines = 1 + math.max(#others, 1)   -- «Капитан (ты)» + участники (или «никого нет»)
		local h = 72 + lines * 46 + 8
		crew.Size = UDim2.new(1, -36, 0, h)
		if show then
			-- первая строка — сам лидер
			local me = new("Frame", {
				Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 40),
				BackgroundColor3 = WELL, BorderSizePixel = 0, ZIndex = 4,
			}, rows)
			stroke(me, BLACK, 2)
			new("TextLabel", {
				Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -150, 1, 0),
				BackgroundTransparency = 1, Font = FONT, TextSize = 15, TextColor3 = WHITE,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				Text = player.DisplayName .. "  @" .. player.Name, ZIndex = 5,
			}, me)
			new("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(124, 30), BackgroundTransparency = 1, Font = FONT, TextSize = 14,
				TextColor3 = GOLD, Text = "⚓ Капитан (ты)", TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5,
			}, me)
			if #others == 0 then
				new("TextLabel", {
					Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -24, 0, 40),
					BackgroundTransparency = 1, Font = FONT_B, TextSize = 14, TextColor3 = SUBT,
					TextXAlignment = Enum.TextXAlignment.Left, Text = "Кроме тебя на плоту никого нет", ZIndex = 5,
				}, rows)
			end
			for idx, plr in ipairs(others) do
				local i = idx + 1
				local row = new("Frame", {
					Position = UDim2.fromOffset(0, (i - 1) * 46), Size = UDim2.new(1, 0, 0, 40),
					BackgroundColor3 = WELL, BorderSizePixel = 0, ZIndex = 4,
				}, rows)
				stroke(row, BLACK, 2)
				new("TextLabel", {
					Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -150, 1, 0),
					BackgroundTransparency = 1, Font = FONT, TextSize = 15, TextColor3 = WHITE,
					TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
					Text = plr.DisplayName .. "  @" .. plr.Name, ZIndex = 5,
				}, row)
				local btn = new("TextButton", {
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0),
					Size = UDim2.fromOffset(124, 30), BackgroundColor3 = RED, BorderSizePixel = 0,
					Font = FONT, TextSize = 14, TextColor3 = WHITE, Text = "Высадить",
					AutoButtonColor = true, ZIndex = 5,
				}, row)
				stroke(btn, BLACK, 2)
				btn.Activated:Connect(function()
					-- ⚠️ ДВА НАЖАТИЯ: первое взводит, второе высаживает. Промах по
					-- кнопке в списке — слишком дорогая ошибка для одного клика.
					if (armed[plr.UserId] or 0) > os.clock() then
						armed[plr.UserId] = nil
						crewRemote:FireServer("kick", plr.UserId)
					else
						armed[plr.UserId] = os.clock() + 3
						btn.Text = "Точно?"
						task.delay(3, function()
							if btn.Parent and (armed[plr.UserId] or 0) <= os.clock() then btn.Text = "Высадить" end
						end)
					end
				end)
			end
		end
		-- канвас и высота панели
		local bottom = show and (crewY - BODY_TOP + h + 18) or 0
		body.CanvasSize = UDim2.fromOffset(0, math.max(bodyCanvasH, bottom))
		if not isAdmin then
			PANEL_H = show and math.min(BASE_H + h + 16, 560) or BASE_H
			panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
			fitScale()
		end
	end

	Players.PlayerAdded:Connect(rebuild)
	Players.PlayerRemoving:Connect(function() task.defer(rebuild) end)
	player:GetAttributeChangedSignal("RaftOwner"):Connect(rebuild)
	rebuild()
	if crewRemote then
		crewRemote.OnClientEvent:Connect(function(kind, text)
			if kind == "toast" then showToast(tostring(text)) end
		end)
	end
end

-- ══════════ открытие / закрытие ══════════
local function setOpen(open)
	screen.Enabled = open
	if open then
		balBox.Text = tostring(curBalance())
		setDropOpen(false)
		body.CanvasPosition = Vector2.zero   -- каждый раз открываемся с верха списка
	end
end
_G.OpenSettingsMenu = function() setOpen(true) end
closeBtn.Activated:Connect(function() setOpen(false) end)
backdrop.Activated:Connect(function()
	if dropOpen then setDropOpen(false) else setOpen(false) end
end)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape and screen.Enabled then setOpen(false) end
end)

print("[SettingsMenu] ready")
