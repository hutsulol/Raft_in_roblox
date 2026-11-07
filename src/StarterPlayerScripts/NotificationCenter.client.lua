local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- NotificationCenter.client.lua  (Фаза 1 редизайна — см. GameDesign/UIRedesign_Plan.md)
-- Уведомления в новом стиле: карточки по типу (info/unlock/success/reward/warn) с
-- иконо-боксом + тайтлом + подзаголовком. Выезжают сбоку (справа), копятся стопкой
-- по центру высоты экрана, сами исчезают. Собрано через дизайн-модуль UITheme.
--
-- API:  _G.Notify({ title = "...", body = "...", type = "info", icon = "👥", duration = 4.5 })
--       icon принимает и ИМЯ из справочника ниже: icon = "backpack" / "ok" / "no" / "warn".
--   type: info(синий) | unlock(фиолет) | success(зелёный) | reward(золото) | warn(красный)
-- Тест: клавиша N показывает три демо-уведомления.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CARD_WIDTH  = 340
local CARD_HEIGHT = 70
local DEFAULT_DURATION = 4.5

--[[ ⚠️ ИКОНКА ПО ТИПУ — ЧТОБЫ КВАДРАТ НЕ ПУСТОВАЛ НИКОГДА.
     Вызывающему не обязательно думать об иконке: тип уведомления уже говорит,
     что произошло. Получил, открыл, добился — галочка; не вышло, сломалось,
     предупреждение — крестик. Своя иконка (icon = "backpack" или эмодзи)
     по-прежнему перебивает этот выбор. ]]
local DEFAULT_ICON = {
	info    = "ok",
	unlock  = "ok",
	success = "ok",
	reward  = "ok",
	warn    = "no",
	error   = "no",
	fail    = "no",
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NotificationCenter"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 40
screenGui.Parent = playerGui

-- Контейнер: правый край, по центру высоты; карточки выезжают справа и центрируются.
-- Контейнер: правый верхний угол (ниже счётчика «Жители»); карточки выезжают справа.
local container = Instance.new("Frame")
container.Name = "Stack"
container.AnchorPoint = Vector2.new(1, 0)
container.Position = UDim2.new(1, -16, 0, 70)
container.Size = UDim2.new(0, CARD_WIDTH, 1, -90)
container.BackgroundTransparency = 1
container.Parent = screenGui

-- ⚠️ НА ТЕЛЕФОНЕ УВЕДОМЛЕНИЯ СЖИМАЕМ ЦЕЛИКОМ, одним UIScale на контейнер.
-- CARD_WIDTH = 340 подбиралась на мониторе; на телефоне карточка занимала треть
-- экрана. Масштаб на контейнере, а не на карточках: они создаются и удаляются на
-- ходу. Тот же приём, что у карточек добычи (InventoryNotify).
do
	--[[ ⚠️ toastFactor, А НЕ noticeFactor И НЕ factor().
	     Панельный множитель 0.55 придуман для меню во весь экран — с ним
	     уведомление было вдвое мельче нужного. Общий «карточный» noticeFactor
	     оказался другой крайностью: он поднят под жёлтые подсказки квестов, и
	     карточка в углу выросла до трети ширины телефона — владелец сказал, что
	     она «затемняет экран».
	     У уведомления своя ручка: см. toastFactor в HudScale. На компьютере она
	     равна единице, десктоп не задет. ]]
	local Hud = require(game:GetService("ReplicatedStorage"):WaitForChild("HudScale"))
	Hud.applyScaleLive(container, Hud.toastFactor)
end

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 10)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.VerticalAlignment = Enum.VerticalAlignment.Top
layout.Parent = container

local order = 0

-- Построить и показать одну карточку.
--[[ ⚠️ ИМЕНОВАННЫЕ ИКОНКИ — ЧТОБЫ КАРТИНКИ НЕ РАЗЪЕХАЛИСЬ ПО ФАЙЛАМ.
     В уведомлении есть место под иконку, но заполнить его можно было только
     эмодзи: поле image до iconBox не доходило вовсе, и квадрат оставался
     пустым — как у «Новое: Рюкзак».
     Теперь у иконок есть имена. Вызывающий пишет icon = "backpack", а какой это
     ассет — знает только этот список: понадобится заменить картинку, правится
     одна строка, а не десяток мест вызова.
     Эмодзи по-прежнему работают: строка, которой нет в списке, идёт как символ,
     и старые вызовы вроде icon = "👥" ничего не замечают.

     ⚠️ У РЮКЗАКА БЕРЁМ ВЕРСИЮ БЕЗ КЛАВИШИ.
     Иконок рюкзака две: с нарисованной «E» — для кнопки на компьютере, и чистая
     — для телефона. В уведомлении кейкап не к месту на любом устройстве: это
     картинка предмета, а не подсказка, какую кнопку жать. ]]
--[[ У каждой записи есть и картинка, и символ. Символ — не украшение: он стоит в
     квадрате, пока картинка едет, и остаётся насовсем, если она не приедет
     (нет прав у опыта, модерация, сеть). Пустого места в уведомлении не будет
     ни при каких обстоятельствах. ]]
local ICONS = {
	--[[ ⚠️ У РЮКЗАКА ТОЛЬКО ЭМОДЗИ — ЭТО РЕШЕНИЕ ВЛАДЕЛЬЦА, А НЕ НЕДОДЕЛКА.
	     Картинка кнопки рюкзака в маленьком квадрате уведомления читалась хуже
	     символа и путалась с ним самим. Id остаётся здесь на случай, если
	     появится отдельная иконка предмета: rbxassetid://134805336581319. ]]
	backpack = { glyph = "🎒" },
	ok       = { image = "rbxassetid://94594933411873",  glyph = "✅" },
	no       = { image = "rbxassetid://112916552750460", glyph = "❌" },
	warn     = { image = "rbxassetid://112916552750460", glyph = "⚠️" },
	-- бревно: эмодзи 🪵 в шрифте Roblox нет (в квадрате был пустой прямоугольник)
	log      = { image = "rbxassetid://116178347748793", glyph = "🌲" },
}

local function resolveIcon(name, fallbackGlyph)
	local known = type(name) == "string" and ICONS[name] or nil
	if known then return known.image, known.glyph or fallbackGlyph end
	-- не имя из справочника — значит сам символ (или пусто → запасной)
	return nil, (type(name) == "string" and name ~= "" and name) or fallbackGlyph
end

--[[ ⚠️ ЗВУК УВЕДОМЛЕНИЯ — С КУЛДАУНОМ, А НЕ НА КАЖДУЮ КАРТОЧКУ.
     Уведомления часто приходят пачкой: зачистка острова открывает сразу
     несколько, и восемь одинаковых звонков подряд — это не сигнал, а треск.
     Пять секунд: первая карточка пачки звучит, остальные приходят молча.
     ⚠️ Звук живёт в SoundService, а не на карточке: карточка исчезает через
     несколько секунд и унесла бы звук с собой на середине. ]]
local NOTIFY_SOUND_ID = "rbxassetid://108594337091000"
local NOTIFY_SOUND_COOLDOWN = 5

local notifySound = Instance.new("Sound")
notifySound.Name = "NotificationSound"
notifySound.SoundId = NOTIFY_SOUND_ID
notifySound.Volume = 0.5
notifySound.Parent = game:GetService("SoundService")

local lastNotifySoundAt = -math.huge

local function playNotifySound()
	if os.clock() - lastNotifySoundAt < NOTIFY_SOUND_COOLDOWN then return end
	lastNotifySoundAt = os.clock()
	-- с нуля: подряд идущие пачки не должны обрывать друг друга на середине
	notifySound.TimePosition = 0
	pcall(function() notifySound:Play() end)
end

local function pushCard(opts)
	opts = opts or {}
	local nType = opts.type or "info"
	playNotifySound()
	local colors = UITheme.Notif[nType] or UITheme.Notif.info
	order += 1

	-- Слот держит место в стопке; карточка внутри выезжает справа.
	local slot = Instance.new("Frame")
	slot.Name = "Slot"
	slot.BackgroundTransparency = 1
	slot.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
	slot.LayoutOrder = order
	slot.Parent = container

	local card = UITheme.panel({
		color = colors,
		corner = 14,
		stroke = 4,
		size = UDim2.new(1, 0, 1, 0),
		position = UDim2.new(1.15, 0, 0, 0), -- старт за правым краем слота (= за экраном)
		parent = slot,
	})

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = card

	-- иконо-бокс слева — точный светлый slot-тон палитры
	--[[ ⚠️ ТИП ПОДСТАВЛЯЕТСЯ ИМЕНЕМ, А НЕ ЗАПАСНЫМ СИМВОЛОМ.
	     DEFAULT_ICON хранит имена из справочника («ok», «no»), поэтому его надо
	     отдавать первым аргументом — на разбор. Передай я его как запасной
	     символ, в квадрате буквально написалось бы «ok». ]]
	local pic, glyph = resolveIcon(opts.icon or opts.image or DEFAULT_ICON[nType], "ℹ️")
	UITheme.iconBox({
		image = pic,
		icon = glyph,
		fill = Color3.fromHex(colors.slot or colors.top),
		stroke = Color3.fromHex(colors.frame),
		corner = 10,
		size = UDim2.fromOffset(CARD_HEIGHT - 16, CARD_HEIGHT - 16),
		anchorPoint = Vector2.new(0, 0.5),
		position = UDim2.new(0, 0, 0.5, 0),
		zindex = 2,
		parent = card,
	})

	-- колонка текста справа от иконки
	local textCol = Instance.new("Frame")
	textCol.BackgroundTransparency = 1
	textCol.AnchorPoint = Vector2.new(1, 0.5)
	textCol.Position = UDim2.new(1, 0, 0.5, 0)
	textCol.Size = UDim2.new(1, -(CARD_HEIGHT - 16) - 10, 1, 0)
	textCol.ZIndex = 2
	textCol.Parent = card

	local colLayout = Instance.new("UIListLayout")
	colLayout.SortOrder = Enum.SortOrder.LayoutOrder
	colLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	colLayout.Padding = UDim.new(0, 1)
	colLayout.Parent = textCol

	if opts.title and opts.title ~= "" then
		local title = UITheme.label({
			text = opts.title, font = UITheme.FONT_TITLE, textSize = 17,
			size = UDim2.new(1, 0, 0, 0), parent = textCol, zindex = 2, layoutOrder = 1,
		})
		title.AutomaticSize = Enum.AutomaticSize.Y
	end
	if opts.body and opts.body ~= "" then
		local body = UITheme.label({
			text = opts.body, font = UITheme.FONT_BODY, textSize = 14,
			textColor = Color3.fromRGB(235, 240, 245),
			size = UDim2.new(1, 0, 0, 0), parent = textCol, zindex = 2, layoutOrder = 2,
		})
		body.AutomaticSize = Enum.AutomaticSize.Y
	end

	-- выезд справа
	TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 0, 0, 0) }):Play()

	-- авто-исчезание (уезжает вправо)
	task.delay(opts.duration or DEFAULT_DURATION, function()
		if not card.Parent then return end
		local out = TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(1.15, 0, 0, 0) })
		out:Play()
		out.Completed:Once(function()
			if slot.Parent then slot:Destroy() end
		end)
	end)
end

_G.Notify = pushCard

-- ⚠️ СЕРВЕРУ НУЖЕН СВОЙ ВХОД: _G У НЕГО ДРУГОЙ.
-- _G.Notify живёт только здесь, на клиенте, и серверные системы, которые её
-- «вызывали» (AmmoCaseSystem, например), на деле не показывали ничего. Мост:
-- сервер шлёт по RemoteEvent, а рисуем всё той же карточкой.
local notifyEvent = ReplicatedStorage:FindFirstChild("NotifyPlayer")
if not notifyEvent then
	notifyEvent = ReplicatedStorage:WaitForChild("NotifyPlayer", 30)
end
if notifyEvent then
	notifyEvent.OnClientEvent:Connect(function(opts)
		if type(opts) == "table" then pushCard(opts) end
	end)
end

-- (Тестовая демонстрация по клавише N убрана: N теперь открывает меню квестов
-- — демо-уведомления «Жителей +5 / Древний монолит / Остров исследован» всплывали
-- одновременно с меню. Реальные уведомления идут через _G.Notify.)