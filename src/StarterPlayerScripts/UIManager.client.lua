local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	HUD ЛЕВОГО НИЖНЕГО УГЛА — вариант 5b из хендоффа (README.md + Roblox HUD.dc.html).

	Сверху вниз, колонка 280 px, зазор 9:
	    1. монеты        — иконка + число, золотое, с тысячным разделителем
	    2. сила          — иконка + «{сила} · {удар}», белое
	    3. сытость|жажда — две капсулы по половине ширины, бейджи наезжают слева
	    4. здоровье      — капсула во всю ширину, число по центру
	    (+) воздух       — появляется только у ныряльщика, тем же языком форм

	⚠️ ЖИТЕЛЕЙ ЗДЕСЬ БОЛЬШЕ НЕТ.
	Счётчик жителей жил отдельным скриптом и просился в этот же столбик через
	_G.MakeStatSlot — оттого и ездил то выше, то ниже. По ТЗ его убрали совсем,
	вместе с самой ручкой: наружу HUD теперь ничего не отдаёт, и вставить в него
	чужую строку мимо этого файла нельзя.

	⚠️ РАДИАЛЬНОГО ГРАДИЕНТА В ROBLOX НЕТ.
	В макете бейджи залиты радиальным градиентом. UIGradient умеет только
	линейный, поэтому бейдж собирается как круг с вертикальным градиентом от
	светлого к тёмному плюс обводка — на глаз это тот же объём. Тени «хардовые»
	(смещённый вниз дубль без размытия), как и просит ТЗ.

	⚠️ UIScale НЕ РАБОТАЕТ НА ScreenGui.
	Прошлая версия вешала масштаб прямо на ScreenGui, и он не применялся вовсе —
	адаптация была на бумаге. Масштаб живёт на корневом Frame и учитывает две
	вещи разом: узкое окно (эталон 1400×720) и телефон (HudScale).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local StarterGui        = game:GetService("StarterGui")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--[[ ⚠️ ШТАТНУЮ ПОЛОСУ ЗДОРОВЬЯ ROBLOX ГАСИМ: У НАС СВОЯ.
     Движок сам рисует зелёную полоску вверху экрана, когда у игрока падает
     здоровье. Своя полоса здоровья стоит в этой же колонке слева внизу, и две
     шкалы одного и того же читаются как ошибка: игрок ищет, чем они отличаются.
     ⚠️ ПОВТОРЯЕМ ПОПЫТКУ: в первые кадры ядро интерфейса может быть ещё не
     готово, и один вызов молча ничего не сделает — тогда полоска вернётся при
     первом же уроне. Несколько дешёвых попыток закрывают этот отрезок. ]]
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then break end
		task.wait(0.5)
	end
end)

local Hud = require(ReplicatedStorage:WaitForChild("HudScale"))

-- ─── ИКОНКИ ───
-- ⚠️ ЭМОДЗИ — ЗАГЛУШКИ, КАК И В МАКЕТЕ. Своя картинка есть только у монеты.
-- Появятся остальные — вписать сюда id, и код менять не придётся: пустая строка
-- означает «рисуем эмодзи», непустая — ImageLabel того же размера.
local ICON = {
	coin      = { image = "rbxassetid://93617165412571",  glyph = "🪙" },
	hunger    = { image = "rbxassetid://85208348940307",  glyph = "🍖" },
	thirst    = { image = "rbxassetid://107900227969593", glyph = "💧" },
	health    = { image = "rbxassetid://96378076686911",  glyph = "❤" },
	radiation = { image = "rbxassetid://127337495800958", glyph = "☢" },
	-- ⚠️ ЭТИ ЧЕТЫРЕ БЕЗ КАРТИНОК, И ЭТО НЕ ЗАБЫТО.
	-- Пустая строка = рисуем эмодзи того же размера, как в макете. Появится
	-- картинка — вписать id сюда, больше нигде править не нужно.
	-- ⚠️ У СИЛЫ ЭМОДЗИ ОСТАВЛЕНО НАМЕРЕННО.
	-- Картинка 90254067320544 была вписана и убрана обратно: в бейдже 23 пикселя,
	-- и рисунок в нём читался хуже, чем 💪. Захочешь вернуть — id вот он,
	-- но сперва посмотри на него в самом бейдже, а не в макете.
	strength  = { image = "", glyph = "💪" },
	air       = { image = "rbxassetid://107034803089809", glyph = "🫧" },
	poison    = { image = "", glyph = "🤢" },
	cold      = { image = "", glyph = "🤧" },
}

-- ─── ПАЛИТРА (Design Tokens из ТЗ) ───
local C = {
	textStroke = Color3.fromHex("14261A"),
	gold       = Color3.fromHex("FFE14D"),
	white      = Color3.new(1, 1, 1),
}

-- Схема одной полоски: трек, обводка, две точки градиента заливки, тень бейджа
-- и градиент самого бейджа. Всё из раздела Design Tokens, менять только здесь.
local SCHEME = {
	hunger = { track = "8A5C0E", line = "A86A10", fillA = "FFD95E", fillB = "F0A828",
		shadow = "7D4E0A", badgeA = "FFD98A", badgeB = "D1881A" },
	thirst = { track = "0E477D", line = "1560A8", fillA = "7CD0FF", fillB = "2890E0",
		shadow = "0E477D", badgeA = "A8DCFF", badgeB = "1E7FD0" },
	health = { track = "701414", line = "9E1F1F", fillA = "FF7561", fillB = "D92F2F",
		shadow = "701414", badgeA = "FF9E8A", badgeB = "CC2828" },
	sick   = { track = "3A5E0C", line = "4D7D12", fillA = "B8E858", fillB = "7AB828",
		shadow = "3A5E0C", badgeA = "D0F088", badgeB = "6AA81E" },
	air    = { track = "0E477D", line = "1560A8", fillA = "A8DCFF", fillB = "38A0F0",
		shadow = "0E477D", badgeA = "CDEBFF", badgeB = "2890E0" },
	--[[ Сила — фиолетовая: рядом уже стоят жёлтая сытость, синяя вода и красное
	     здоровье, и пятый оттенок тех же тонов не различался бы на бегу. ]]
	strength = { track = "3B1E6E", line = "552A9E", fillA = "C79BFF", fillB = "8B4DE0",
		shadow = "3B1E6E", badgeA = "D9BBFF", badgeB = "7A3ACC" },
}
local function hex(h) return Color3.fromHex(h) end

-- ─── РАЗМЕРЫ (макет 400×300, колонка 280) ───
--[[ ⚠️ ДЛИНУ ПОЛОС ЗАДАЁТ ШИРИНА ВСЕЙ КОЛОНКИ, А НЕ КАЖДАЯ ПОЛОСА ОТДЕЛЬНО.
     Сытость и жажда занимают по половине строки, здоровье — всю: правится одно
     число, и все три растут согласованно, вместе с бейджами и цифрами внутри.
     280 было взято из макета 400×300; на экране полосы читались короткими
     огрызками. 360 — та же колонка, но длиной в две трети её же высоты столбика
     кнопок, так что левый угол по-прежнему не съедает поле зрения.
     Телефона это тоже касается: там колонка сжимается своим множителем, и
     удлинение доезжает в той же пропорции. ]]
local COL_W       = 360
--[[ Отступы колонки от угла экрана. Держим их здесь: по этим же числам
     считается, сколько места остаётся до панели быстрых слотов. ]]
local LEFT_PAD    = 16
local BOTTOM_PAD  = 16
local ROW_GAP     = 9
local NUM_SIZE    = 34    -- кегль крупных цифр
local NUM_STROKE  = 3
local ICON_BIG    = 36    -- иконки строк монет и силы
local BADGE_SMALL = 38    -- бейджи сытости и жажды
local BADGE_BIG   = 46    -- бейдж здоровья
local OVER_SMALL  = 12    -- насколько бейдж наезжает на капсулу
local OVER_BIG    = 14
local BAR_SMALL   = 22    -- высота капсул сытости и жажды
local BAR_BIG     = 28    -- высота капсулы здоровья
local SHADOW_DROP = 3     -- «хард-шэдоу»: смещение вниз без размытия
local FILL_INSET  = 2     -- заливка утоплена в трек
local TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

-- ─── ScreenGui и корень ───
local screenGui = new("ScreenGui", {
	Name = "UIManager", DisplayOrder = 15, IgnoreGuiInset = true, ResetOnSpawn = false,
}, playerGui)

local root = new("Frame", {
	Name = "HudColumn",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, LEFT_PAD, 1, -BOTTOM_PAD),   -- 16/16, как было до правок
	Size = UDim2.fromOffset(COL_W, 10),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
}, screenGui)

new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, ROW_GAP),
}, root)

-- ⚠️ ДВА МНОЖИТЕЛЯ В ОДНОМ UIScale, А НЕ ДВА UIScale.
-- Второй UIScale на том же объекте просто затрёт первый. Узкое окно и телефон —
-- разные причины сжатия, и учитывать надо обе сразу: на телефоне в ландшафте
-- окно широкое, но пальцем всё равно тыкать, а на узком мониторе телефона нет.
local REF_W, REF_H = 1400, 720
local MIN_SCALE = 0.35
--[[ ⚠️ У ТЕЛЕФОНА СВОЙ ПОЛ, И ОН НЕ 0.35.
     0.35 задумывался как аварийный предел для совсем узкого окна, но в него
     упирался КАЖДЫЙ телефон — «100 / 100» выходило высотой в несколько пикселей.
     Ниже 0.62 цифры статусов перестают читаться. ]]
local MIN_PHONE_SCALE = 0.62
local hudScale = new("UIScale", { Scale = 1 }, root)

--[[ ⚠️ ОБЪЯВЛЕНА ЗАРАНЕЕ: ТЕЛО НИЖЕ, А ЗОВЁМ ОТСЮДА.
     recomputeScale стоит выше по файлу, чем relayoutColumn. Напиши мы там просто
     имя — Lua разрешил бы его как ГЛОБАЛЬНУЮ переменную, то есть nil, и вызов
     молча не случался бы: колонка перестала бы расходиться с хотбаром при
     изменении размера окна, и понять это по коду было бы нечем. ]]
local relayoutColumn
--[[ Множитель «сколько влезает в окно» без учёта хотбара. Итоговый Scale
     колонки считает relayoutColumn: он может ужать её ещё немного. ]]
local baseScale = 1

local function recomputeScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(REF_W, REF_H)
	local fit = math.min(vp.X / REF_W, vp.Y / REF_H)
	--[[ ⚠️ НА iconFactor() ЗДЕСЬ УМНОЖАТЬ НЕЛЬЗЯ — ВЫСОТА СЧИТАЛАСЬ ДВАЖДЫ.
	     Внутри iconFactor сидит та же самая доля высоты экрана, что уже учтена в
	     fit. Перемножение давало около 0.27, колонка ложилась на пол клампа, и
	     здоровье с жаждой превращались в нечитаемые полоски.
	     Телефону хватает fit и своего пола: он и так считает от 720. ]]
	local phone = Hud.isPhone()
	baseScale = math.clamp(math.min(fit, 1), phone and MIN_PHONE_SCALE or MIN_SCALE, 1)
	-- окно изменилось — заново решаем, как разойтись с хотбаром
	if relayoutColumn then relayoutColumn() end   -- на первом вызове тела ещё нет
end

--[[ ⚠️ КОЛОНКУ НЕ ПОДНИМАЕМ ВОВСЕ — ТОЛЬКО СУЖАЕМ.
     Панель быстрых слотов стоит внизу по центру, колонка — в левом нижнем углу;
     на широком экране они не встречаются, на узком накладываются.
     Разойтись можно двумя способами: сузить колонку или увести её выше слотов.
     Подъём я пробовал дважды — сначала как основной способ, потом как запасной,
     на случай «сузили до предела, а всё равно мешает». Оба раза колонка
     наезжала на столбик кнопок Квесты/Магазин/Инвентарь/Настройки: одно
     наложение просто менялось на другое, заметное сильнее — цифры статусов
     ложились прямо на подпись «Настройки».
     Вверху места нет, и притворяться, что оно есть, бессмысленно. Остаётся
     сужение: колонка всегда стоит внизу, а на узком окне занимает меньше.
     Аварийный MIN_SCALE её и подстрахует — он для того и заведён.
     Границу хотбара спрашиваем у него самого (AbsolutePosition), а не считаем по
     формуле: число слотов зависит от прокачки, а сама панель масштабируется —
     любая вычисленная копия его геометрии разошлась бы с правдой. ]]
local HOTBAR_GAP = 12

-- ⚠️ Отступы (LEFT_PAD/BOTTOM_PAD) объявлены рядом с COL_W: по ним же считается
-- свободное место до слотов, и разъехаться этим числам нельзя.
local scaleNow = nil

--[[ Левый край слотов в экранных координатах — единственное, что нам нужно.
     ⚠️ ВЫСОТУ КОЛОНКИ НЕ ТРОГАЕМ ВООБЩЕ.
     Я двигал её тремя разными способами — поднимал над слотами, менял отступ
     снизу, равнял по низу слотов — и каждый раз мимо: то выше кнопок, то ниже
     хотбара. Вертикаль в этом HUD была настроена до меня и претензий не
     вызывала; наложение было ГОРИЗОНТАЛЬНЫМ, и лечить его надо шириной.
     Поэтому здесь остаётся ровно один вопрос: где начинаются слоты. ]]
local function hotbarEdge()
	local gui = playerGui:FindFirstChild("HotbarGui")
	local bar = gui and gui:FindFirstChild("Hotbar")
	if bar and bar:IsA("GuiObject") and bar.AbsoluteSize.X > 0 then
		return bar.AbsolutePosition.X
	end
	return nil
end

function relayoutColumn()
	local left = hotbarEdge()
	local scale = baseScale

	if left then
		-- какой множитель нужен, чтобы колонка кончалась до слотов
		local cap = (left - LEFT_PAD - HOTBAR_GAP) / COL_W
		-- ограничение только сужает: на крошечном окне база и так меньше
		scale = math.clamp(math.min(cap, baseScale), MIN_SCALE, baseScale)
	end

	if scale ~= scaleNow then
		scaleNow = scale
		hudScale.Scale = scale
	end
end

--[[ Хотбар пересоздают целиком (старый ScreenGui уничтожается), поэтому не
     подписываемся на его свойства — переживём пересоздание простым опросом.
     Стоит он два поиска по имени и сравнение; позицию трогаем, только когда
     она реально меняется. ]]
task.spawn(function()
	while true do
		task.wait(0.5)
		pcall(relayoutColumn)
	end
end)

local function hookCamera(cam)
	if not cam then return end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(recomputeScale)
	recomputeScale()
end
hookCamera(workspace.CurrentCamera)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	hookCamera(workspace.CurrentCamera)
end)

-- ─── СТРОИТЕЛИ ───

-- Иконка: картинка, если id задан, иначе эмодзи того же размера.
local function makeIcon(parent, spec, size, order)
	if spec.image ~= "" then
		return new("ImageLabel", {
			LayoutOrder = order, Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1, Image = spec.image,
			ScaleType = Enum.ScaleType.Fit,
		}, parent)
	end
	return new("TextLabel", {
		LayoutOrder = order, Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1, Text = spec.glyph,
		TextSize = math.floor(size * 0.86), Font = Enum.Font.GothamBlack,
		TextColor3 = C.white,
	}, parent)
end

-- Крупное число с толстой тёмной обводкой — общий вид цифр монет и силы.
local function makeNumber(parent, color, order)
	local lbl = new("TextLabel", {
		LayoutOrder = order, AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, NUM_SIZE + 6), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack, TextSize = NUM_SIZE, TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "0",
	}, parent)
	new("UIStroke", { Thickness = NUM_STROKE, Color = C.textStroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, lbl)
	return lbl
end

-- Строка «иконка + число».
local function makeStatRow(order, iconSpec, color)
	local row = new("Frame", {
		LayoutOrder = order, Size = UDim2.new(1, 0, 0, ICON_BIG + 6),
		BackgroundTransparency = 1,
	}, root)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
	}, row)
	makeIcon(row, iconSpec, ICON_BIG, 1)
	return makeNumber(row, color, 2)
end

--[[ Полоска: круглый бейдж слева, наезжающий на капсулу.

	Возвращает таблицу с ручками, чтобы цвета можно было перекрасить на лету:
	болезнь меняет ВСЮ схему блока здоровья, а не только иконку.
]]
local function makeBar(parent, order, width, barH, badgeH, overlap, iconSpec, scheme, withText)
	local holder = new("Frame", {
		LayoutOrder = order, Size = width, BackgroundTransparency = 1,
	}, parent)

	-- трек начинается за бейджем: бейдж наезжает на него слева
	local left = badgeH - overlap

	local shadow = new("Frame", {
		Name = "TrackShadow",
		Position = UDim2.new(0, left, 0.5, -barH / 2 + SHADOW_DROP),
		Size = UDim2.new(1, -left, 0, barH),
		BackgroundColor3 = hex(scheme.shadow), BorderSizePixel = 0, ZIndex = 1,
	}, holder)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, shadow)

	local track = new("Frame", {
		Name = "Track",
		Position = UDim2.new(0, left, 0.5, -barH / 2),
		Size = UDim2.new(1, -left, 0, barH),
		BackgroundColor3 = hex(scheme.track), BorderSizePixel = 0, ZIndex = 2,
		ClipsDescendants = true,
	}, holder)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
	local trackLine = new("UIStroke", { Thickness = 3, Color = hex(scheme.line) }, track)

	local fill = new("Frame", {
		Name = "Fill",
		Position = UDim2.new(0, FILL_INSET, 0, FILL_INSET),
		Size = UDim2.new(1, -FILL_INSET * 2, 1, -FILL_INSET * 2),
		BackgroundColor3 = hex(scheme.fillA), BorderSizePixel = 0, ZIndex = 3,
	}, track)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
	local fillGrad = new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(hex(scheme.fillA), hex(scheme.fillB)),
	}, fill)

	-- глянец: белая капсула по верхней кромке заливки
	local gloss = new("Frame", {
		Name = "Gloss",
		Position = UDim2.new(0, 10, 0, 3), Size = UDim2.new(1, -20, 0, barH >= 28 and 7 or 6),
		BackgroundColor3 = C.white, BackgroundTransparency = 0.55,
		BorderSizePixel = 0, ZIndex = 4,
	}, fill)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, gloss)

	local text
	if withText then
		text = new("TextLabel", {
			Name = "Value", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = C.white,
			Text = "", ZIndex = 6,
		}, track)
		new("UIStroke", { Thickness = 2, Color = hex(scheme.line) }, text)
	end

	-- бейдж поверх всего
	local badgeShadow = new("Frame", {
		Name = "BadgeShadow",
		Position = UDim2.new(0, 0, 0.5, -badgeH / 2 + SHADOW_DROP),
		Size = UDim2.fromOffset(badgeH, badgeH),
		BackgroundColor3 = hex(scheme.shadow), BorderSizePixel = 0, ZIndex = 5,
	}, holder)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, badgeShadow)

	local badge = new("Frame", {
		Name = "Badge",
		Position = UDim2.new(0, 0, 0.5, -badgeH / 2),
		Size = UDim2.fromOffset(badgeH, badgeH),
		BackgroundColor3 = hex(scheme.badgeA), BorderSizePixel = 0, ZIndex = 6,
	}, holder)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
	local badgeGrad = new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(hex(scheme.badgeA), hex(scheme.badgeB)),
	}, badge)
	local badgeLine = new("UIStroke", { Thickness = 3, Color = hex(scheme.line) }, badge)

	local icon = makeIcon(badge, iconSpec, math.floor(badgeH * 0.62), 1)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 7

	local handle = {
		holder = holder, track = track, fill = fill, text = text, badge = badge,
	}

	function handle.setRatio(ratio, animate)
		local r = math.clamp(ratio or 0, 0, 1)
		local goal = UDim2.new(r, -FILL_INSET * 2 * r, 1, -FILL_INSET * 2)
		if animate == false then fill.Size = goal
		else TweenService:Create(fill, TWEEN, { Size = goal }):Play() end
		-- пустая полоска не должна показывать кружок заливки
		fill.Visible = r > 0.001
	end

	-- Перекрасить блок целиком: болезнь меняет и трек, и обводку, и бейдж.
	function handle.setScheme(s)
		track.BackgroundColor3 = hex(s.track)
		trackLine.Color = hex(s.line)
		shadow.BackgroundColor3 = hex(s.shadow)
		badgeShadow.BackgroundColor3 = hex(s.shadow)
		badgeLine.Color = hex(s.line)
		fill.BackgroundColor3 = hex(s.fillA)
		fillGrad.Color = ColorSequence.new(hex(s.fillA), hex(s.fillB))
		badgeGrad.Color = ColorSequence.new(hex(s.badgeA), hex(s.badgeB))
		if text then
			local st = text:FindFirstChildOfClass("UIStroke")
			if st then st.Color = hex(s.line) end
		end
	end

	function handle.setIcon(spec)
		local old = icon
		icon = makeIcon(badge, spec, math.floor(badgeH * 0.62), 1)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 7
		old:Destroy()
	end

	return handle
end

-- ─── 1. МОНЕТЫ ───
local coinLbl = makeStatRow(1, ICON.coin, C.gold)

-- Пробел между тысячами, как в ТЗ (1 250).
-- ⚠️ ПРОБЕЛ ОБЫЧНЫЙ, А НЕ НЕРАЗРЫВНЫЙ.
-- Приём «перевернуть → разбить по три → перевернуть обратно» работает ПОБАЙТНО.
-- Неразрывный пробел в UTF-8 занимает два байта, и второй разворот менял их
-- местами — на экране вместо числа появлялся мусор. Однобайтовый пробел
-- переворот переживает, а переносить строку здесь всё равно негде.
--
-- ⚠️ ОГРОМНЫЕ ЧИСЛА СОКРАЩАЕМ, А НЕ РАЗБИВАЕМ ПРОБЕЛАМИ.
-- В сейве баланс может оказаться каким угодно — в логе уже попадался
-- -9223372036854775808. tostring на таком выдаёт «5.623774502285287e+119», и
-- разбивка по три превращала это в кашу через полэкрана (её и было видно на
-- скриншоте). От миллиона показываем короткую форму: 1.2M, 3.4B, 5.6T.
local SUFFIX = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" } }

local function groupThousands(n)
	local v = tonumber(n) or 0
	if v ~= v or v == math.huge or v == -math.huge then return "0" end   -- NaN и бесконечности
	v = math.floor(v)
	if v < 0 then v = 0 end                                              -- отрицательного баланса не бывает

	for _, s in ipairs(SUFFIX) do
		if v >= s[1] then
			return ("%.1f%s"):format(v / s[1], s[2])
		end
	end

	local str = tostring(v)
	local out = str:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^%s+", ""))
end

-- Короткий «поп» при изменении: число должно замечаться, но не прыгать.
local coinPop = new("UIScale", { Scale = 1 }, coinLbl)
local function refreshCoins()
	coinLbl.Text = groupThousands(player:GetAttribute("Pirate") or 0)
	coinPop.Scale = 1.15
	TweenService:Create(coinPop, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
end
player:GetAttributeChangedSignal("Pirate"):Connect(refreshCoins)
refreshCoins()

--[[ ─── 2. СИЛА ───
     ⚠️ ПОЛОСА, А НЕ ДВЕ ЦИФРЫ ЧЕРЕЗ ТОЧКУ.
     Здесь стояло «0 · 1»: слева очки силы, справа урон за клик. Ни одна из
     цифр не говорила, откуда она берётся и сколько до следующей — сила
     выглядела украшением. Теперь у неё уровень и опыт за удары, а значит и
     показывать её надо как всё остальное, что копится: полосой того же вида,
     что здоровье, с числом уровня по центру.
     Ряд собран той же makeBar с withText — отдельной вёрстки для силы нет
     намеренно: две похожие полосы, собранные по-разному, расходятся при первой
     же правке стиля. ]]
local strengthRow = new("Frame", {
	LayoutOrder = 2, Size = UDim2.new(1, 0, 0, BADGE_SMALL + SHADOW_DROP),
	BackgroundTransparency = 1,
}, root)
local strengthBar = makeBar(strengthRow, 1, UDim2.fromScale(1, 1), BAR_SMALL, BADGE_SMALL,
	OVER_SMALL, ICON.strength, SCHEME.strength, true)

task.spawn(function()
	local folder = player:WaitForChild("Characteristics", 30)
	if not folder then
		warn("[HUD] нет папки Characteristics — сила не показывается")
		return
	end
	local level    = folder:WaitForChild("Strength", 15)
	local xp       = folder:WaitForChild("StrengthXP", 15)
	local required = folder:WaitForChild("StrengthXPRequired", 15)
	local maxLevel = folder:WaitForChild("StrengthMax", 15)
	local hitPower = folder:WaitForChild("HitPower", 15)
	if not (level and xp and required) then return end

	local function refresh()
		local need = required.Value
		--[[ На максимуме порога больше нет (сервер шлёт ноль), и делить не на
		     что: полосу держим полной — копить действительно некуда. ]]
		local ratio = (need > 0) and (xp.Value / need) or 1
		strengthBar.setRatio(math.clamp(ratio, 0, 1))
		if strengthBar.text then
			local cap = maxLevel and maxLevel.Value or 0
			local txt
			if cap > 0 and level.Value >= cap then
				txt = ("Ур. %d · макс"):format(level.Value)
			else
				txt = ("Ур. %d"):format(level.Value)
			end
			--[[ ⚠️ МНОЖИТЕЛЬ УДАРА ПОКАЗЫВАЕМ ЗДЕСЬ ЖЕ.
			     Раньше урон за клик стоял в HUD вторым числом («0 · 1»), и вместе
			     со старой строкой он исчез. Но именно он — главная награда за
			     уровни: на пятом клик бьёт дважды, и не сказать об этом значит
			     подарить прибавку, которую игрок не заметит. Пишем только когда
			     есть что писать: на единице приписка была бы шумом. ]]
			local hp = hitPower and hitPower.Value or 1
			if hp > 1 then txt = txt .. (" ×%d"):format(hp) end
			strengthBar.text.Text = txt
		end
	end

	for _, v in ipairs({ level, xp, required, hitPower }) do
		if v then v:GetPropertyChangedSignal("Value"):Connect(refresh) end
	end
	refresh()
end)

-- ─── 3. СЫТОСТЬ + ЖАЖДА (одна строка, две половины) ───
local pairRow = new("Frame", {
	LayoutOrder = 3, Size = UDim2.new(1, 0, 0, BADGE_SMALL + SHADOW_DROP),
	BackgroundTransparency = 1,
}, root)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10),
}, pairRow)

local HALF = UDim2.new(0.5, -5, 1, 0)
local hungerBar = makeBar(pairRow, 1, HALF, BAR_SMALL, BADGE_SMALL, OVER_SMALL,
	ICON.hunger, SCHEME.hunger, false)
local thirstBar = makeBar(pairRow, 2, HALF, BAR_SMALL, BADGE_SMALL, OVER_SMALL,
	ICON.thirst, SCHEME.thirst, false)

task.spawn(function()
	local hungerEvent = ReplicatedStorage:WaitForChild("HungerUpdate", 30)
	local thirstEvent = ReplicatedStorage:WaitForChild("ThirstUpdate", 30)
	if hungerEvent then
		hungerEvent.OnClientEvent:Connect(function(v, max)
			hungerBar.setRatio((tonumber(v) or 0) / math.max(1, tonumber(max) or 100))
		end)
	end
	if thirstEvent then
		thirstEvent.OnClientEvent:Connect(function(v, max)
			thirstBar.setRatio((tonumber(v) or 0) / math.max(1, tonumber(max) or 100))
		end)
	end
end)
hungerBar.setRatio(1, false)
thirstBar.setRatio(1, false)

-- ─── 4. ЗДОРОВЬЕ (+ болезнь) ───
local healthRow = new("Frame", {
	LayoutOrder = 4, Size = UDim2.new(1, 0, 0, BADGE_BIG + SHADOW_DROP),
	BackgroundTransparency = 1,
}, root)
local healthBar = makeBar(healthRow, 1, UDim2.fromScale(1, 1), BAR_BIG, BADGE_BIG,
	OVER_BIG, ICON.health, SCHEME.health, true)

-- ⚠️ БОЛЕЗНЬ — ЭТО СОСТОЯНИЕ ВСЕГО БЛОКА, А НЕ ЗНАЧОК СБОКУ.
-- В макете отдельного слота нет: само сердце становится иконкой болезни, а
-- полоска перекрашивается в зелёное. Так больной виден боковым зрением, не
-- вчитываясь. Пока источник один — радиация (ToxicWater ставит RadiationSick);
-- появятся отравление и простуда — дописать сюда по строке.
local DISEASES = {
	{ attr = "RadiationSick", icon = ICON.radiation,
		title = "Лучевая болезнь", body = "Головная боль, голод растёт быстрее" },
	{ attr = "Poisoned", icon = ICON.poison,
		title = "Отравление", body = "Здоровье убывает, пока не пройдёт" },
	{ attr = "ColdSick", icon = ICON.cold,
		title = "Простуда", body = "Силы меньше, удар слабее" },
}

-- ─── ПОДСКАЗКА О БОЛЕЗНИ ───
-- ⚠️ ВИСИТ НА БЕЙДЖЕ ЗДОРОВЬЯ, А НЕ ОТДЕЛЬНЫМ ЗНАЧКОМ.
-- Раньше у радиации был свой значок рядом с HUD и своя подсказка при наводке —
-- то есть об одном и том же говорили в двух местах. Болезнь теперь встроена в
-- сердце, туда же переехало и объяснение: навёл на сердце — прочитал, чем болен.
-- Здоров — подсказки нет вовсе, наводить не на что.
local tipHolder = new("Frame", {
	Name = "DiseaseTip", AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, BADGE_BIG + 10, 0, -8),
	Size = UDim2.fromOffset(230, 56), BackgroundColor3 = Color3.fromHex("14261A"),
	BackgroundTransparency = 0.08, BorderSizePixel = 0, Visible = false, ZIndex = 20,
}, healthRow)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, tipHolder)
new("UIStroke", { Thickness = 2, Color = Color3.fromHex("4D7D12") }, tipHolder)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
	PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
}, tipHolder)

local tipTitle = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = Color3.fromHex("B8E858"),
	TextXAlignment = Enum.TextXAlignment.Left, Text = "", ZIndex = 21,
}, tipHolder)
local tipBody = new("TextLabel", {
	Position = UDim2.new(0, 0, 0, 21), Size = UDim2.new(1, 0, 0, 22),
	BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13,
	TextColor3 = Color3.fromRGB(214, 226, 208), TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	Text = "", ZIndex = 21,
}, tipHolder)

-- ⚠️ НАВОДКУ ЛОВИТ ПРОЗРАЧНАЯ КНОПКА ПОВЕРХ БЕЙДЖА.
-- У Frame нет MouseEnter/MouseLeave — они есть только у GuiButton. Кнопка
-- нарисована ничем и стоит ровно по бейджу; на телефоне тап по ней тоже
-- показывает подсказку, а следующий тап где угодно её убирает.
local hoverBtn = new("TextButton", {
	Name = "HealthHover", Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
	Position = UDim2.new(0, 0, 0.5, -BADGE_BIG / 2),
	Size = UDim2.fromOffset(BADGE_BIG, BADGE_BIG), ZIndex = 19,
}, healthRow)

local sickNow = nil

local function showTip(on)
	tipHolder.Visible = on and sickNow ~= nil
end
hoverBtn.MouseEnter:Connect(function() showTip(true) end)
hoverBtn.MouseLeave:Connect(function() showTip(false) end)
hoverBtn.Activated:Connect(function() showTip(not tipHolder.Visible) end)

local function refreshDisease()
	local found = nil
	for _, d in ipairs(DISEASES) do
		if player:GetAttribute(d.attr) == true then found = d break end
	end
	if found == sickNow then return end
	sickNow = found
	if found then
		healthBar.setScheme(SCHEME.sick)
		healthBar.setIcon(found.icon)
		tipTitle.Text = found.title or "Болезнь"
		tipBody.Text = found.body or ""
	else
		healthBar.setScheme(SCHEME.health)
		healthBar.setIcon(ICON.health)
		tipHolder.Visible = false   -- выздоровел с открытой подсказкой
	end
end
for _, d in ipairs(DISEASES) do
	player:GetAttributeChangedSignal(d.attr):Connect(refreshDisease)
end
refreshDisease()

local function bindHealth(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end
	local function refresh()
		local max = math.max(1, hum.MaxHealth)
		healthBar.setRatio(hum.Health / max)
		if healthBar.text then
			healthBar.text.Text = ("%d / %d"):format(math.floor(hum.Health + 0.5), math.floor(max))
		end
	end
	hum:GetPropertyChangedSignal("Health"):Connect(refresh)
	hum:GetPropertyChangedSignal("MaxHealth"):Connect(refresh)
	refresh()
end
if player.Character then task.spawn(bindHealth, player.Character) end
player.CharacterAdded:Connect(bindHealth)

-- ─── (+) ВОЗДУХ — только под водой у ныряльщика ───
-- Строки нет в макете, но система жива: без неё ныряльщик остаётся без шкалы
-- воздуха. Тот же язык форм, показывается только когда нужна.
local airRow = new("Frame", {
	LayoutOrder = 0,   -- над монетами: это временная, срочная шкала
	Size = UDim2.new(1, 0, 0, BADGE_SMALL + SHADOW_DROP),
	BackgroundTransparency = 1, Visible = false,
}, root)
local airBar = makeBar(airRow, 1, UDim2.fromScale(1, 1), BAR_SMALL, BADGE_SMALL,
	OVER_SMALL, ICON.air, SCHEME.air, true)

task.spawn(function()
	local folder = player:WaitForChild("Characteristics", 30)
	if not folder then return end
	local cur = folder:WaitForChild("AirCurrent", 15)
	local max = folder:WaitForChild("AirMax", 15)
	if not (cur and max) then return end
	local function refresh()
		local top = math.max(1, max.Value)
		airBar.setRatio(cur.Value / top)
		if airBar.text then
			airBar.text.Text = ("%d / %d"):format(math.floor(cur.Value + 0.5), math.floor(top))
		end
	end
	cur:GetPropertyChangedSignal("Value"):Connect(refresh)
	max:GetPropertyChangedSignal("Value"):Connect(refresh)
	refresh()
end)

local function refreshAirVisible()
	airRow.Visible = player:GetAttribute("DiverAirActive") == true
end
player:GetAttributeChangedSignal("DiverAirActive"):Connect(refreshAirVisible)
refreshAirVisible()

print("[HUD] собран по хендоффу 5b: монеты, сила, сытость|жажда, здоровье (жителей нет)")
