-- RewardReveal.client.lua
-- Анимация выдачи нового редкого предмета — по хендоффу design_handoff_reward_reveal,
-- в размерах и НА МЕСТЕ рулетки (RewardRoll.client): панель у ВЕРХА экрана, предмет ~150px.
-- Сценарий: предмет впрыгивает с отскоком (scale 0→~1.18→1, поворот −18°→0°), выскакивает
-- золотая звезда, снизу всплывают название и статус («НОВОЕ!» золотым / «ДУБЛИКАТ»
-- фиолетовым), всё висит до t=2.8s и уходит ЧИСТЫМ ФЕЙДОМ: только прозрачность 0→100%
-- линейно (0.9s), БЕЗ каких-либо сдвигов/уменьшений — блок стоит на месте и растворяется.
--
-- Триггеры:
--   • RemoteEvent ReplicatedStorage.RewardReveal (создаёт EventBootstrap.server):
--     FireClient(plr, { name = "ИМЯ", icon = "rbxassetid://...", duplicate = false })
--   • _G.ShowRewardReveal(данные) — для клиентских систем.
--   • Несколько наград подряд — очередь: следующая после исчезновения предыдущей.
--
-- ТЕСТ: кнопка «🎁 Тест» справа (TEST_BUTTON ниже) — чередует НОВОЕ!/ДУБЛИКАТ.
-- Когда проверишь — поставь TEST_BUTTON = false.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

-- заглушка на время загрузки иконки награды (незагруженная картинка = пустое место)

local TEST_BUTTON = false -- выключено к бета-тесту: reveal теперь запускает сервер
                          -- (награда онбординг-квеста в QuestState.claimReward)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── палитра/шрифты/ассеты ──
local GOLD   = Color3.fromRGB(255, 210, 58)  -- #ffd23a — звезда и «НОВОЕ!»
local PURPLE = Color3.fromRGB(200, 106, 232) -- #c86ae8 — «ДУБЛИКАТ»

--[[ ⚠️ РЕДКОСТЬ ВМЕСТО «НОВОЕ!», КОГДА ЕЁ ПЕРЕДАЛИ.
     Строка статуса знала ровно два состояния: новое и дубликат. Для предметов
     это бедно: получая револьвер, игрок должен видеть, что именно ему выпало,
     а «НОВОЕ!» одинаково для щепки и для оружия.
     Ключи — как их пишет человек («Редкое»), а не служебными словами: их же
     передаёт сервер, и разбираться в rare/epic посреди русского текста незачем.
     Цвета обычные для жанра: серый — обычное, голубой — редкое, фиолетовый —
     эпическое, золотой — легендарное. ]]
local RARITY = {
	["Обычное"]      = Color3.fromRGB(206, 214, 224),
	["Редкое"]       = Color3.fromRGB(76, 214, 108),   -- зелёный: синий сливался с океаном
	["Эпическое"]    = PURPLE,
	["Легендарное"]  = GOLD,
}
local ITEM_GLYPH_COLOR = Color3.fromRGB(232, 240, 248) -- #e8f0f8 — глиф-заглушка
local FONT = Enum.Font.GothamBlack -- кириллица; для латиницы хендофф предлагал LuckiestGuy

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

-- ── UI: панель у верха экрана, геометрия как у рулетки ──
local screen = new("ScreenGui", {
	Name = "RewardReveal", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 150,
}, playerGui)

-- обычный Frame: финальный фейд тушит КАЖДЫЙ элемент отдельным твином — надёжно везде
-- (CanvasGroup.GroupTransparency на части клиентов молча не применялся — картинка
-- пропадала без перехода)
local block = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), -- у верха, как рулетка
	Size = UDim2.fromOffset(340, 260), BackgroundTransparency = 1,
	Visible = false, Active = false,
}, screen)

-- ⚠️ НА ТЕЛЕФОНЕ ПАНЕЛЬ СЖИМАЕТСЯ ЦЕЛИКОМ.
-- Все её размеры (340×260, приз 150×150, кегли подписей) подбирались под монитор.
-- Внутреннюю вёрстку это не трогает — один UIScale на корень. applyScaleLive, а не
-- applyScale: поворот телефона из портрета в ландшафт пересчитывается сам.
--
--[[ ⚠️ НО МНОЖИТЕЛЬ ЗДЕСЬ КАРТОЧНЫЙ, А НЕ ПАНЕЛЬНЫЙ.
     Вызов шёл без второго аргумента, то есть брал factor() по умолчанию — 0.55,
     придуманный для МЕНЮ во весь экран. На телефоне он ещё умножается на долю
     высоты, и выходило около 0.4: награда — то, ради чего игрок и лез в рюкзак
     или сдавал квест, — показывалась вдвое с лишним мельче, чем на мониторе.
     Владелец сказал ровно это: «награда с рюкзака и с квестов не такая по
     размерам, как на ПК».
     Меню и награда — разные задачи. Меню занимает весь экран, и жать его надо;
     награда живёт две секунды по центру сверху, её надо УСПЕТЬ РАЗГЛЯДЕТЬ.
     cardFactor держит её вровень с компьютером (на низком экране опускается до
     0.85), и на компьютере равен единице — десктоп не задет. ]]
do
	local Hud = require(game:GetService("ReplicatedStorage"):WaitForChild("HudScale"))
	Hud.applyScaleLive(block, Hud.cardFactor)
end

--[[ Звук выдачи награды — свой ассет (ItemDropSoundEffectShort), выбран владельцем.
     ⚠️ ЧУЖОЙ АССЕТ МОЖЕТ НЕ ЗАИГРАТЬ, И ЭТО НЕ ПОЛОМКА КОДА.
     Раньше здесь стоял встроенный в клиент rbxasset:// — он не грузится по сети и
     не зависит от прав. Загружаемый ассет надёжен ровно настолько, насколько он
     доступен этому опыту: если он не принадлежит владельцу игры и не роздан,
     в логе будет «User is not authorized to access Asset», и вместо звука
     наступит тишина. Проверять надо в самой игре, а не в Studio у автора ассета.
     Встроенный звук оставлен рядом: вернуть — заменить одну строку. ]]
local REWARD_SOUND = "rbxassetid://117945572498547"
-- запасной, встроенный: "rbxasset://sounds/electronicpingshort.wav"
local sfx = Instance.new("Sound")
sfx.Name = "RewardRevealSound"
sfx.SoundId = REWARD_SOUND
sfx.Volume = 0.55
sfx.Parent = screen
-- держатель предмета (150px, как приз рулетки): на нём скейл-отскок и поворот −18°→0°
local itemHolder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 95),
	Size = UDim2.fromOffset(150, 150), BackgroundTransparency = 1, Rotation = -18,
	ZIndex = 3, Active = false,
}, block)
local itemScale = new("UIScale", { Scale = 0 }, itemHolder)

local itemImg = new("ImageLabel", { -- иконка предмета (если передана)
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 3, Active = false,
}, itemHolder)
local itemGlyph = new("TextLabel", { -- глиф-заглушка как в эталоне (⚔)
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = FONT,
	Text = "⚔", TextSize = 85, TextColor3 = ITEM_GLYPH_COLOR, Visible = false, ZIndex = 3, Active = false,
}, itemHolder)

--[[ Золотая звезда под предметом.
     ⚠️ ПО ЦЕНТРУ, А НЕ ПО ЧИСЛУ ПИКСЕЛЕЙ ОТ ЛЕВОГО КРАЯ.
     Здесь стояло `UDim2.new(0, 115, ...)` — сто пятнадцать пикселей от левого
     края блока шириной 340. То есть звезда сидела на 55 пикселей левее середины
     и, в отличие от предмета, названия и статуса (все они центрированы долей
     0.5), при любом масштабе съезжала влево от общей оси. На узком экране это
     видно сразу: столбик ровный, а звезда сбоку.
     Доля вместо пикселей ставит её ровно под предметом и держит там при любой
     ширине блока — той же меркой, что и остальные три строки.
     ⚠️ Опущена ниже эталонных 139: на 150-пиксельном предмете звезда висела
     вровень с его серединой и читалась как часть картинки, а не как отметка. ]]
local star = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 168),
	Size = UDim2.fromOffset(28, 28), BackgroundTransparency = 1, Font = FONT,
	Text = "★", TextSize = 24, TextColor3 = GOLD, ZIndex = 4, Active = false,
}, block)
local starStroke = new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5 }, star)
local starScale = new("UIScale", { Scale = 0 }, star)

-- название: на месте подписи рулетки (y=192), с обводкой и падающей тенью
local NAME_Y = 192
local nameShadow = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, NAME_Y + 3),
	Size = UDim2.new(0, 340, 0, 32), BackgroundTransparency = 1, Font = FONT,
	Text = "", TextSize = 26, TextColor3 = Color3.new(0, 0, 0), TextTransparency = 1,
	ZIndex = 3, Active = false,
}, block)
local nameLbl = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, NAME_Y),
	Size = UDim2.new(0, 340, 0, 32), BackgroundTransparency = 1, Font = FONT,
	Text = "", TextSize = 26, TextColor3 = Color3.new(1, 1, 1), TextTransparency = 1,
	ZIndex = 3, Active = false,
}, block)
local nameStroke = new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 1 }, nameLbl)

-- статус: на месте строки шанса рулетки (y=224)
local STATUS_Y = 224
local statusShadow = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, STATUS_Y + 2),
	Size = UDim2.new(0, 340, 0, 28), BackgroundTransparency = 1, Font = FONT,
	Text = "", TextSize = 22, TextColor3 = Color3.new(0, 0, 0), TextTransparency = 1,
	ZIndex = 3, Active = false,
}, block)
local statusLbl = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, STATUS_Y),
	Size = UDim2.new(0, 340, 0, 28), BackgroundTransparency = 1, Font = FONT,
	Text = "", TextSize = 22, TextColor3 = GOLD, TextTransparency = 1,
	ZIndex = 3, Active = false,
}, block)
local statusStroke = new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5, Transparency = 1 }, statusLbl)

-- ── тайминги ──
local function tw(inst, ti, props) TweenService:Create(inst, ti, props):Play() end
local BACK_OUT     = TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BACK_OUT_04  = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local QUAD_OUT_04  = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- уход: ЧИСТЫЙ линейный фейд прозрачностью, без сдвигов и уменьшений
local OUT_TIME     = 0.5 -- секунды перехода в конце
local LINEAR_OUT   = TweenInfo.new(OUT_TIME, Enum.EasingStyle.Linear)

-- один показ (блокирующий — очередь ждёт)
local function playReveal(data)
	-- Звук в самом начале, вместе с появлением: награда должна ЗВЯКНУТЬ в тот
	-- момент, когда предмет выпрыгивает, а не под конец, когда всё уже прочитано.
	-- Перезапуск с нуля — на случай, если наград прилетело несколько подряд.
	sfx.TimePosition = 0
	pcall(function() sfx:Play() end)

	-- контент
	local dup = data.duplicate == true
	nameLbl.Text = data.name or "ПРЕДМЕТ"
	nameShadow.Text = nameLbl.Text

	-- редкость важнее «НОВОЕ!»: она и есть содержательный статус предмета
	local rarity = typeof(data.rarity) == "string" and data.rarity ~= "" and data.rarity or nil
	if rarity then
		statusLbl.Text = string.upper(rarity)
		statusLbl.TextColor3 = RARITY[rarity] or GOLD
	else
		statusLbl.Text = dup and "ДУБЛИКАТ" or "НОВОЕ!"
		statusLbl.TextColor3 = dup and PURPLE or GOLD
	end
	statusShadow.Text = statusLbl.Text
	if data.icon and data.icon ~= "" then
		itemImg.Image = data.icon
		itemImg.Visible = true; itemGlyph.Visible = false
	else
		itemGlyph.Text = data.glyph or "⚔"
		itemGlyph.Visible = true; itemImg.Visible = false
	end

	-- сброс стартовых состояний (в т.ч. после фейда предыдущего показа)
	itemScale.Scale = 0
	itemHolder.Rotation = -18
	itemImg.ImageTransparency = 0
	itemGlyph.TextTransparency = 0
	-- Золотая звезда — ТОЛЬКО для явного data.star (напр. редкий предмет). У ресурсных
	-- наград (камни/дерево из квеста) её быть не должно — прячем.
	star.Visible = data.star == true
	starScale.Scale = 0
	star.TextTransparency = 0
	starStroke.Transparency = 0
	for _, l in ipairs({ nameLbl, nameShadow, statusLbl, statusShadow }) do l.TextTransparency = 1 end
	nameStroke.Transparency = 1
	statusStroke.Transparency = 1
	nameLbl.Position = UDim2.new(0.5, 0, 0, NAME_Y + 10)      -- всплытие снизу
	nameShadow.Position = UDim2.new(0.5, 0, 0, NAME_Y + 13)
	statusLbl.Position = UDim2.new(0.5, 0, 0, STATUS_Y + 10)
	statusShadow.Position = UDim2.new(0.5, 0, 0, STATUS_Y + 12)
	block.Visible = true

	-- t=0.05 — предмет: scale 0→1 (Back Out даёт отскок) + поворот −18°→0°
	task.wait(0.05)
	tw(itemScale, BACK_OUT, { Scale = 1 })
	tw(itemHolder, BACK_OUT, { Rotation = 0 })

	-- t=0.35 — звезда и название
	task.wait(0.30)
	tw(starScale, BACK_OUT_04, { Scale = 1 })
	tw(nameLbl, QUAD_OUT_04, { TextTransparency = 0, Position = UDim2.new(0.5, 0, 0, NAME_Y) })
	tw(nameShadow, QUAD_OUT_04, { TextTransparency = 0.45, Position = UDim2.new(0.5, 0, 0, NAME_Y + 3) })
	tw(nameStroke, QUAD_OUT_04, { Transparency = 0 })

	-- t=0.50 — статус
	task.wait(0.15)
	tw(statusLbl, QUAD_OUT_04, { TextTransparency = 0, Position = UDim2.new(0.5, 0, 0, STATUS_Y) })
	tw(statusShadow, QUAD_OUT_04, { TextTransparency = 0.45, Position = UDim2.new(0.5, 0, 0, STATUS_Y + 2) })
	tw(statusStroke, QUAD_OUT_04, { Transparency = 0 })

	-- удержание до t=2.8, затем уход: ТОЛЬКО прозрачность 0→100% линейно — блок стоит
	-- на месте; каждый элемент тускнеет своим твином (надёжнее, чем GroupTransparency)
	task.wait(2.30)
	tw(itemImg, LINEAR_OUT, { ImageTransparency = 1 })
	tw(itemGlyph, LINEAR_OUT, { TextTransparency = 1 })
	tw(star, LINEAR_OUT, { TextTransparency = 1 })
	tw(starStroke, LINEAR_OUT, { Transparency = 1 })
	for _, l in ipairs({ nameLbl, nameShadow, statusLbl, statusShadow }) do
		tw(l, LINEAR_OUT, { TextTransparency = 1 })
	end
	tw(nameStroke, LINEAR_OUT, { Transparency = 1 })
	tw(statusStroke, LINEAR_OUT, { Transparency = 1 })
	task.wait(OUT_TIME + 0.05)
	block.Visible = false
end

-- ── очередь: следующая награда после исчезновения предыдущей ──
local queue = {}
local draining = false
local function enqueue(data)
	if type(data) ~= "table" then return end
	table.insert(queue, data)
	if draining then return end
	draining = true
	task.spawn(function()
		while #queue > 0 do
			playReveal(table.remove(queue, 1))
		end
		draining = false
	end)
end

-- триггеры: серверный RemoteEvent + локальный хук для клиентских систем
_G.ShowRewardReveal = enqueue
task.spawn(function()
	local ev = ReplicatedStorage:WaitForChild("RewardReveal", 30)
	if ev and ev:IsA("RemoteEvent") then
		ev.OnClientEvent:Connect(enqueue)
	end
end)

-- ── тестовая кнопка (чередует НОВОЕ! / ДУБЛИКАТ) ──
if TEST_BUTTON then
	local btn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.78, 0),
		Size = UDim2.fromOffset(150, 40), BackgroundColor3 = Color3.fromRGB(14, 31, 48),
		Text = "🎁 ТЕСТ", Font = FONT, TextSize = 16, TextColor3 = Color3.fromRGB(127, 168, 201),
		AutoButtonColor = true,
	}, screen)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, btn)
	new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, btn)
	local flip = false
	btn.MouseButton1Click:Connect(function()
		flip = not flip
		enqueue({ name = "АБОРДАЖНАЯ САБЛЯ", duplicate = flip })
	end)
end
