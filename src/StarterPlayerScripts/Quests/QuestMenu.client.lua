local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- QuestMenu.client.lua
-- Меню квестов — 1:1 по дизайну "Quest Menu Roblox.dc.html": ОДИН список без вкладок.
--   • тёмно-синяя панель 720px с чёрной рамкой 4px, в правом верхнем углу —
--     ОБЩИЙ крестик закрытия из UITheme (свой X поверх угла больше не рисуем);
--   • шапка с ТОЧЕЧНЫМ ПАТТЕРНОМ (кружки, как в эталоне): жёлтый бейдж «!»,
--     заголовок + подзаголовок, пилюля «Active: N»;
--   • золотая полоса-разделитель с градиентом;
--   • СКРОЛЛ-список карточек; скроллбар как в эталоне: плоский синий бегунок
--     (#2a7fd4) на тёмном жёлобе с чёрной кромкой слева;
--   • карточка: круглая аватарка (кольцо-акцент → чёрное кольцо → градиентный круг,
--     место под портрет NPC) + плашка типа, название, описание, награды (у РЕДКИХ —
--     пульсирующий фиолетовый ореол + ★), кнопка действия;
--   • отслеживаемая: белая рамка с пульсом + качающаяся золотая ★ (starWiggle);
--   • подвал-подсказка.
-- Данные — QuestState RemoteEvent; глаголы: track / untrack / claimReward /
-- startChallenge / getState. Старые вкладочные скрипты монтируются в скрытые
-- страницы-заглушки (совместимость), игрок видит только новый список.
--
-- Public API: _G.OpenQuestMenu() / _G.CloseQuestMenu(), ESC закрывает, J — тумблер.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
--[[ ⚠️ ОБЩИЙ КРЕСТИК ЗАКРЫТИЯ — ОБЪЯВЛЯЕМ ЗДЕСЬ, В ШАПКЕ ФАЙЛА.
     Сначала этот require стоял внизу, рядом с HudScale, — а кнопка собирается
     в функции ВЫШЕ него. Локальная переменная, объявленная позже тела функции,
     для неё не существует: обращение уходит в глобальную область, получает nil,
     и всё меню квестов падало на построении панели. ]]
local UITheme           = require(game:GetService("ReplicatedStorage"):WaitForChild("UITheme"))
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SCREENGUI_DISPLAY_ORDER = 110

-- ── палитра (из дизайна) ──
local C_PANEL      = Color3.fromRGB(14, 31, 48)    -- #0e1f30
local C_HEADER     = Color3.fromRGB(26, 58, 88)    -- #1a3a58
local C_DARK       = Color3.fromRGB(10, 24, 38)    -- #0a1826
local C_CARD       = Color3.fromRGB(18, 41, 61)    -- #12293d
local C_BLACK      = Color3.new(0, 0, 0)
local C_WHITE      = Color3.new(1, 1, 1)
local C_GOLD       = Color3.fromRGB(255, 210, 58)  -- #ffd23a
local C_GOLD_LIGHT = Color3.fromRGB(255, 215, 111) -- #ffd76f
local C_GOLD_DARK  = Color3.fromRGB(201, 150, 42)  -- #c9962a
local C_GOLD_TEXT  = Color3.fromRGB(61, 42, 5)     -- #3d2a05
local C_SUB        = Color3.fromRGB(127, 168, 201) -- #7fa8c9
local C_MUTED      = Color3.fromRGB(90, 122, 150)  -- #5a7a96
local C_ORANGE     = Color3.fromRGB(226, 87, 31)   -- #e2571f
local C_ORANGE_HOV = Color3.fromRGB(240, 106, 48)  -- #f06a30
local C_GREEN      = Color3.fromRGB(53, 180, 53)   -- #35b435
local C_GREEN_TXT  = Color3.fromRGB(53, 212, 53)   -- #35d435
local C_BLUE       = Color3.fromRGB(42, 127, 212)  -- #2a7fd4
local C_RARE       = Color3.fromRGB(200, 143, 232) -- #c88fe8
local C_RARE_SLOT  = Color3.fromRGB(42, 29, 61)    -- #2a1d3d
local C_RARE_GLOW1 = Color3.fromRGB(122, 63, 176)  -- #7a3fb0
local C_RARE_GLOW2 = Color3.fromRGB(154, 95, 208)  -- #9a5fd0
-- ⚠️ GothamBlack, А НЕ FredokaOne.
-- В хендоффе дисплейным шрифтом стоял FredokaOne (замена эталонному M PLUS
-- Rounded), и это работало, пока тексты меню были английскими. У FredokaOne НЕТ
-- КИРИЛЛИЦЫ: русские заголовки он не рисует, Roblox молча подставляет дефолтное
-- тонкое начертание — рядом с телом карточки на GothamBold это читалось как
-- «шрифт не тот». Тот же выбор и по той же причине сделан в TrackerCard.
local FONT  = Enum.Font.GothamBlack
local FONTB = Enum.Font.GothamBold

-- акценты карточки по типу квеста
local KIND_STYLE = {
	story     = { name = "STORY",     accent = Color3.fromRGB(42, 127, 212), dim = Color3.fromRGB(29, 66, 102), bright = Color3.fromRGB(127, 192, 255) },
	daily     = { name = "QUEST",     accent = Color3.fromRGB(47, 155, 58),  dim = Color3.fromRGB(29, 74, 38),  bright = Color3.fromRGB(127, 224, 122) },
	challenge = { name = "CHALLENGE", accent = Color3.fromRGB(201, 58, 58),  dim = Color3.fromRGB(74, 29, 29),  bright = Color3.fromRGB(240, 122, 106) },
}

-- ── ПОРТРЕТ И НИК ИГРОКА ──
-- ⚠️ ПОРТРЕТ ТЯНЕТСЯ ОДИН РАЗ НА ВЕСЬ СЕАНС.
-- GetUserThumbnailAsync — сетевой вызов, и дёргать его на каждую карточку значит
-- ждать сеть при каждой перерисовке списка. Тянем однажды, а карточки, которые
-- успели построиться раньше ответа, догоняем через faceSlots.
local playerHeadshot = nil
local faceSlots = {}     -- карточки, ждущие портрет

task.spawn(function()
	local ok, url = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId,
			Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if not ok or not url then return end
	playerHeadshot = url
	for _, slot in ipairs(faceSlots) do
		if slot.image.Parent then
			slot.image.Image = url
			slot.glyph.Visible = false
		end
	end
end)

-- Ник для плашки. DisplayName ближе к тому, как игрок себя зовёт; если его нет
-- (старые аккаунты) — обычное имя. Длинный обрезаем: плашка растёт по тексту и
-- иначе уедет за карточку.
local function playerTag()
	local n = player.DisplayName
	if not n or n == "" then n = player.Name end
	if utf8.len(n) and utf8.len(n) > 14 then
		n = n:sub(1, utf8.offset(n, 15) - 1) .. "…"
	end
	return n:upper()
end

-- какие награды РЕДКИЕ/ЭПИЧЕСКИЕ (фиолетовый пульсирующий ореол + ★):
--   1) reward.rare = true в каталоге квестов (QuestCatalog) — главный способ;
--   2) имя из таблицы ниже;
--   3) любой предмет (kind == "item") — сундуки и т.п. редкие по умолчанию.
local RARE_REWARD_NAMES = {}
local function isRareReward(reward)
	if not reward then return false end
	if reward.rare == true then return true end
	if RARE_REWARD_NAMES[reward.name] then return true end
	return reward.kind == "item"
end

-- ── геометрия ──
local PANEL_W  = 720
local HEADER_H = 84
local BAND_H   = 12
local LIST_H   = 400
local FOOTER_H = 40
local PANEL_H  = HEADER_H + BAND_H + LIST_H + FOOTER_H
local CARD_H   = 150
local SCROLLBAR_W = 16

--[[ ⚠️ ОПИСАНИЕ КВЕСТА В НЕСКОЛЬКО СТРОК, А НЕ В ОДНУ С МНОГОТОЧИЕМ.
     Строка была одна и обрывалась на середине: «Собери молоток и…» — прочитать
     задание было нельзя вообще, а именно за ним игрок и открывает меню.
     Даём до трёх строк и растим карточку ровно на столько, сколько текст занял.
     Больше трёх не пускаем сознательно: список должен листаться, а не
     превращаться в стену текста; всё, что длиннее, по-прежнему подрезается. ]]
local BODY_LINE_H  = 19   -- высота строки описания при TextSize 16
local BODY_MAX_LINES = 3
local BODY_TOP     = 30   -- отступ описания от верха контента

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
-- обводка ТЕКСТА (Contextual). Для рамок коробок — borderStroke, иначе UIStroke на
-- текстовых элементах обводит буквы, а не рамку.
local function stroke(inst, color, thickness)
	return new("UIStroke", { Color = color, Thickness = thickness }, inst)
end
local function borderStroke(inst, color, thickness)
	return new("UIStroke", {
		Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
end

-- ── состояние ──
local screenGui, panel, backdrop, listFrame, countLabel, panelScale
local isOpen = false
local closeQuestMenu -- forward-decl: buildCard (выше по файлу) закрывает меню на Claim
local lastQuests = {}
local liveTweens = {}
local questStateEvent

local function addLoop(tween)
	table.insert(liveTweens, tween)
	tween:Play()
end
local function stopLoops()
	for _, t in ipairs(liveTweens) do pcall(function() t:Cancel() end) end
	table.clear(liveTweens)
	-- список перерисовывается на каждый снимок: старые карточки уничтожены, и
	-- ссылки на их портреты копились бы без конца
	table.clear(faceSlots)
end

-- ── карточка квеста ──
local function buildCard(q, order)
	local ks = KIND_STYLE[q.kind] or KIND_STYLE.daily
	local tracked = q.tracked == true

	local card = new("Frame", {
		LayoutOrder = order, Size = UDim2.new(1, -4, 0, CARD_H),
		BackgroundColor3 = C_CARD, BorderSizePixel = 0,
	}, listFrame)
	local cardStroke = borderStroke(card, tracked and C_WHITE or C_BLACK, 3)
	if tracked then -- selPulse: белая рамка «дышит»
		addLoop(TweenService:Create(cardStroke,
			TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Thickness = 5, Transparency = 0.35 }))
	end

	-- звезда отслеживания над углом (starWiggle)
	if tracked then
		local star = new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 12, 0, -16),
			Size = UDim2.fromOffset(38, 38), BackgroundTransparency = 1,
			Font = FONT, Text = "★", TextSize = 34, TextColor3 = C_GOLD,
			Rotation = -10, ZIndex = 3,
		}, card)
		stroke(star, C_BLACK, 2)
		local starScale = new("UIScale", { Scale = 1 }, star)
		addLoop(TweenService:Create(star,
			TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Rotation = 4 }))
		addLoop(TweenService:Create(starScale,
			TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.12 }))
	end

	-- ── аватарка: три вложенных круга (акцент-кольцо → чёрное кольцо → градиентный круг),
	-- рамки НЕ рисуются поверх друг друга, кольцо-акцент всегда видно, как в эталоне ──
	local ring = new("Frame", {
		Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(78, 78),
		BackgroundColor3 = ks.accent, BorderSizePixel = 0,
	}, card)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	local blackRing = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(72, 72), BackgroundColor3 = C_BLACK, BorderSizePixel = 0,
	}, ring)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, blackRing)
	local avatar = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(66, 66), BackgroundColor3 = ks.dim, BorderSizePixel = 0,
	}, blackRing)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, avatar)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(ks.dim, C_DARK) }, avatar)
	-- ⚠️ ЗАКАЗЧИК КВЕСТА — САМ ИГРОК.
	-- Круг был зарезервирован под портрет NPC, и стояла глиф-заглушка «☻». Но
	-- задачи здесь никто не выдаёт: игрок ставит их себе сам. Поэтому в круге его
	-- собственный портрет, тот же самый, что в окне диалогов, а на плашке вместо
	-- служебного «STORY» — его ник.
	local face = new("ImageLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Image = playerHeadshot or "", ScaleType = Enum.ScaleType.Crop,
	}, avatar)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, face)
	-- портрет приходит с сервера Roblox и может опоздать: пока его нет, в круге
	-- остаётся прежний глиф, а не пустая дыра
	local placeholder = new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Font = FONT, Text = "☻", TextSize = 36, TextColor3 = ks.bright,
		Visible = playerHeadshot == nil,
	}, avatar)
	table.insert(faceSlots, { image = face, glyph = placeholder })

	-- плашка с ником, перекрывает низ кольца
	local badge = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(16 + 39, 16 + 78 - 11),
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20),
		BackgroundColor3 = ks.accent, Font = FONT, TextSize = 12,
		TextColor3 = C_WHITE, Text = " " .. playerTag() .. " ", ZIndex = 2,
	}, card)
	borderStroke(badge, C_BLACK, 2)

	-- ── контент ──
	local BTN_COL = 210
	local content = new("Frame", {
		Position = UDim2.fromOffset(108, 16), Size = UDim2.new(1, -108 - BTN_COL, 1, -28),
		BackgroundTransparency = 1,
	}, card)
	local titleLbl = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1,
		Font = FONT, TextSize = 24, TextColor3 = C_WHITE,
		TextXAlignment = Enum.TextXAlignment.Left, Text = q.title or q.id or "",
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, content)
	stroke(titleLbl, C_BLACK, 1.5)
	--[[ Высоту описания меряем ПОСЛЕ отрисовки, по факту: ширина колонки зависит
	     от ширины панели и полосы прокрутки, и считать её числом здесь значило бы
	     завести ещё одну копию вёрстки, которая разъедется при первой правке. ]]
	local bodyLbl = new("TextLabel", {
		Position = UDim2.fromOffset(0, BODY_TOP), Size = UDim2.new(1, 0, 0, BODY_LINE_H),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		BackgroundTransparency = 1, Font = FONTB, TextSize = 16, TextColor3 = C_SUB,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, Text = q.body or "",
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, content)
	-- потолок: три строки, дальше подрезаем многоточием
	new("UISizeConstraint", {
		MaxSize = Vector2.new(math.huge, BODY_LINE_H * BODY_MAX_LINES),
	}, bodyLbl)

	-- ряд наград съезжает вниз ровно на добавленные строки
	local rewardsY = 60
	local rewardShift = 0
	new("TextLabel", {
		Position = UDim2.fromOffset(0, rewardsY + 17), Size = UDim2.fromOffset(72, 16),
		BackgroundTransparency = 1, Font = FONT, TextSize = 13, TextColor3 = C_MUTED,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "НАГРАДА",
	}, content)
	if q.reward and q.reward.count then
		local rare = isRareReward(q.reward)
		if rare then
			-- диагностика: видно в Output, что редкость ДОШЛА до клиента
			print("[QuestMenu] rare reward:", q.id, q.reward.name)
			-- АУРА за слотом (halo из эталона: 0 0 16px) — «дышит» размером и яркостью
			local aura = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(82 + 25, rewardsY + 25),
				Size = UDim2.fromOffset(60, 60), BackgroundColor3 = C_RARE_GLOW2,
				BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 1,
			}, content)
			new("UICorner", { CornerRadius = UDim.new(0, 8) }, aura)
			addLoop(TweenService:Create(aura,
				TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundTransparency = 0.15, Size = UDim2.fromOffset(68, 68) }))
		end
		local slot = new("Frame", {
			Position = UDim2.fromOffset(82, rewardsY), Size = UDim2.fromOffset(50, 50),
			BackgroundColor3 = rare and C_RARE_SLOT or C_DARK, BorderSizePixel = 0,
			ZIndex = 2,
		}, content)
		local slotStroke = borderStroke(slot, rare and C_RARE_GLOW2 or C_BLACK, 2)
		if rare then -- rareGlow: яркая пульсирующая рамка поверх ауры
			addLoop(TweenService:Create(slotStroke,
				TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Color = C_RARE, Thickness = 4 }))
		end
		-- иконка НАГРАДЫ приоритетнее иконки квеста (у сундуков в каталоге своя картинка)
		local rewardIcon = (q.reward.icon and q.reward.icon ~= "" and q.reward.icon) or q.icon
		if rewardIcon and rewardIcon ~= "" then
			new("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1,
				Image = rewardIcon, ScaleType = Enum.ScaleType.Fit,
			}, slot)
		else
			new("TextLabel", {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
				Font = FONT, Text = "🎁", TextSize = 22, TextColor3 = rare and C_RARE or C_SUB,
			}, slot)
		end
		local cnt = new("TextLabel", {
			AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 7, 1, 7),
			AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 17),
			BackgroundColor3 = C_GOLD, Font = FONT, TextSize = 12, TextColor3 = C_GOLD_TEXT,
			Text = " x" .. tostring(q.reward.count) .. " ", ZIndex = 2,
		}, slot)
		borderStroke(cnt, C_BLACK, 2)
		if rare then
			local rs = new("TextLabel", {
				Position = UDim2.new(0, -8, 0, -9), Size = UDim2.fromOffset(16, 16),
				BackgroundTransparency = 1, Font = FONT, Text = "★",
				TextSize = 15, TextColor3 = C_RARE, ZIndex = 3,
			}, slot)
			stroke(rs, C_BLACK, 1.5)
		end
	end

	-- ── кнопка действия ──
	local label, bg, fg, border, action
	if q.rewardPending then
		label, bg, fg, border, action = "Забрать награду", C_GOLD, C_GOLD_TEXT, C_BLACK, "claimReward"
	elseif q.completed then
		label, bg, fg, border, action = "Выполнено", C_DARK, C_MUTED, C_BLACK, nil
	elseif tracked then
		label, bg, fg, border, action = "✓ Отслеживается", C_DARK, C_GREEN_TXT, C_GREEN, "untrack"
	elseif q.kind == "challenge" and not q.startedAt then
		label, bg, fg, border, action = "Начать", C_BLUE, C_WHITE, C_BLACK, "startChallenge"
	else
		label, bg, fg, border, action = "Отслеживать", C_GREEN, C_WHITE, C_BLACK, "track"
	end
	local btn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(180, 52), BackgroundColor3 = bg,
		Font = FONT, TextSize = 18, TextColor3 = fg, Text = label,
		AutoButtonColor = action ~= nil,
	}, card)
	borderStroke(btn, border, 3)
	if action then
		btn.MouseButton1Click:Connect(function()
			if questStateEvent then questStateEvent:FireServer(action, q.id) end
			-- Claim запускает анимацию выдачи (RewardReveal) поверх экрана — закрываем
			-- меню, чтобы reveal не проигрывался ВНУТРИ открытой панели квестов.
			if action == "claimReward" and closeQuestMenu then closeQuestMenu() end
		end)
	end

	--[[ ⚠️ ПОДГОНЯЕМ КАРТОЧКУ ПОД ТЕКСТ ПОСЛЕ ОТРИСОВКИ, А НЕ СЧИТАЕМ ЗАРАНЕЕ.
	     Сколько строк займёт описание, зависит от ширины колонки, а она — от
	     ширины панели и полосы прокрутки. Считать это числом здесь значило бы
	     держать вторую копию вёрстки, которая разъедется при первой же правке.
	     Поэтому спрашиваем у самой надписи, сколько она заняла, и на столько же
	     опускаем ряд наград и растим карточку.
	     Двигаем ВСЁ, что лежит ниже наград, и на РАЗНИЦУ с прошлым разом: иначе
	     повторный пересчёт (смена языка, перестройка списка) сдвинул бы элементы
	     второй раз. ]]
	local grownBy = 0
	local function fitToBody()
		local extra = math.max(0, bodyLbl.AbsoluteSize.Y - BODY_LINE_H)
		local delta = extra - grownBy
		if delta == 0 then return end
		for _, ch in ipairs(content:GetChildren()) do
			if ch:IsA("GuiObject") and ch ~= bodyLbl
				and ch.Position.Y.Offset >= rewardsY + grownBy then
				ch.Position = ch.Position + UDim2.fromOffset(0, delta)
			end
		end
		grownBy = extra
		card.Size = UDim2.new(1, -4, 0, CARD_H + extra)
	end
	bodyLbl:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToBody)
	fitToBody()

	return card
end

local function rebuildList()
	if not listFrame then return end
	stopLoops()
	for _, c in ipairs(listFrame:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local active = 0
	for i, q in ipairs(lastQuests) do
		buildCard(q, i)
		if not q.completed then active += 1 end
	end
	if countLabel then countLabel.Text = " Активно: " .. active .. " " end
end

-- ── сборка панели ──
local function buildPanel(parent)
	panel = new("Frame", {
		Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(PANEL_W, PANEL_H),
		BackgroundColor3 = C_PANEL, BorderSizePixel = 0, ZIndex = 2,
	}, parent)
	borderStroke(panel, C_BLACK, 4)
	panelScale = new("UIScale", { Scale = 1 }, panel)

	-- шапка
	local header = new("Frame", {
		Size = UDim2.new(1, 0, 0, HEADER_H), BackgroundColor3 = C_HEADER,
		BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 3,
	}, panel)
	-- точечный паттерн эталона («кружки»): сетка полупрозрачных белых точек 30×30
	for row = 0, 2 do
		for col = 0, math.floor(PANEL_W / 30) do
			local dot = new("Frame", {
				Position = UDim2.fromOffset(9 + col * 30, 9 + row * 30),
				Size = UDim2.fromOffset(7, 7), BackgroundColor3 = C_WHITE,
				BackgroundTransparency = 0.93, BorderSizePixel = 0, ZIndex = 3,
			}, header)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
		end
	end
	local bang = new("TextLabel", {
		Position = UDim2.fromOffset(20, 15), Size = UDim2.fromOffset(54, 54),
		BackgroundColor3 = C_GOLD, Font = FONT, TextSize = 32, TextColor3 = C_GOLD_TEXT,
		Text = "!", ZIndex = 4,
	}, header)
	borderStroke(bang, C_BLACK, 3)
	local titleL = new("TextLabel", {
		Position = UDim2.fromOffset(88, 10), Size = UDim2.fromOffset(300, 38),
		BackgroundTransparency = 1, Font = FONT, TextSize = 34, TextColor3 = C_WHITE,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "Квесты", ZIndex = 4,
	}, header)
	stroke(titleL, C_BLACK, 2)
	new("TextLabel", {
		Position = UDim2.fromOffset(88, 50), Size = UDim2.fromOffset(360, 20),
		BackgroundTransparency = 1, Font = FONTB, TextSize = 15, TextColor3 = C_SUB,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Выполняй задания и получай награды", ZIndex = 4,
	}, header)
	countLabel = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -84, 0.5, 0),
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 34),
		BackgroundColor3 = C_DARK, Font = FONT, TextSize = 16, TextColor3 = C_GOLD,
		Text = " Активно: 0 ", ZIndex = 4,
	}, header)
	borderStroke(countLabel, C_BLACK, 2)

	-- золотая полоса
	local band = new("Frame", {
		Position = UDim2.fromOffset(0, HEADER_H), Size = UDim2.new(1, 0, 0, BAND_H),
		BackgroundColor3 = C_BLACK, BorderSizePixel = 0, ZIndex = 3,
	}, panel)
	local bandCore = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = C_GOLD, BorderSizePixel = 0, ZIndex = 4,
	}, band)
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C_GOLD_LIGHT),
			ColorSequenceKeypoint.new(0.4, C_GOLD),
			ColorSequenceKeypoint.new(1, C_GOLD_DARK),
		}),
	}, bandCore)

	-- жёлоб скроллбара, как в эталоне: тёмный, с чёрной кромкой слева (рисуем ПОД списком)
	local trackGutter = new("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, HEADER_H + BAND_H),
		Size = UDim2.fromOffset(SCROLLBAR_W, LIST_H), BackgroundColor3 = C_DARK,
		BorderSizePixel = 0, ZIndex = 2,
	}, panel)
	new("Frame", {
		Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = C_BLACK, BorderSizePixel = 0, ZIndex = 3,
	}, trackGutter)

	-- скролл-список; бегунок — ПЛОСКИЙ прямоугольник (все три сегмента = middle-текстура)
	listFrame = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, HEADER_H + BAND_H), Size = UDim2.new(1, 0, 0, LIST_H),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = SCROLLBAR_W, ScrollBarImageColor3 = C_BLUE,
		ScrollBarImageTransparency = 0,
		TopImage    = "rbxasset://textures/ui/Scroll/scroll-middle.png",
		MidImage    = "rbxasset://textures/ui/Scroll/scroll-middle.png",
		BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
		VerticalScrollBarInset = Enum.ScrollBarInset.Always,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 20), PaddingBottom = UDim.new(0, 16),
		PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 14),
	}, listFrame)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 18),
	}, listFrame)

	-- подвал
	local footer = new("Frame", {
		Position = UDim2.fromOffset(0, HEADER_H + BAND_H + LIST_H),
		Size = UDim2.new(1, 0, 0, FOOTER_H), BackgroundColor3 = C_DARK,
		BorderSizePixel = 0, ZIndex = 3,
	}, panel)
	new("Frame", {
		Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = C_BLACK, BorderSizePixel = 0, ZIndex = 4,
	}, footer)
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Font = FONTB, TextSize = 14, TextColor3 = C_MUTED,
		Text = "Отслеживаемый квест показан на экране", ZIndex = 4,
	}, footer)

	--[[ ⚠️ КРЕСТИК БЕРЁМ ИЗ UITheme, А НЕ РИСУЕМ СВОЙ.
	     Игрок видит кнопку закрытия во всех меню океана как один и тот же элемент
	     управления, поэтому разнобой в ней читается как небрежность. Эталоном
	     владелец назвал инвентарь, и UITheme.closeButton — это ровно его крестик.
	     Здесь стояла своя копия: картинка 62 px, которая росла на наведении, —
	     из-за неё меню квестов выглядело чужим рядом с остальными.
	     Размер сюда НЕ передаём и передать нельзя: он живёт в UITheme.CLOSE_SIZE,
	     иначе меню снова разъедутся, ровно так это и вышло в прошлый раз.
	     Посадку тоже не передаём — умолчание модуля повторяет инвентарь. ]]
	local close = UITheme.closeButton({ parent = panel, zIndex = 6 })
	close.MouseButton1Click:Connect(function()
		if typeof(_G.CloseQuestMenu) == "function" then _G.CloseQuestMenu() end
	end)

	return panel
end

local function buildBackdrop(parent)
	backdrop = new("TextButton", {
		Name = "Backdrop", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C_BLACK, BackgroundTransparency = 0.55,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 1,
	}, parent)
	backdrop.MouseButton1Click:Connect(function()
		if typeof(_G.CloseQuestMenu) == "function" then _G.CloseQuestMenu() end
	end)
	return backdrop
end

local function ensureScreenGui()
	if screenGui and screenGui.Parent then return screenGui end
	screenGui = new("ScreenGui", {
		Name = "QuestMenuGui", ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = SCREENGUI_DISPLAY_ORDER, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, playerGui)

	buildBackdrop(screenGui)
	buildPanel(screenGui)

	-- совместимость: старые вкладочные скрипты монтируются в скрытые заглушки
	local legacy = new("Folder", { Name = "LegacyPages" }, screenGui)
	local pages = {}
	for _, id in ipairs({ "quests", "story", "challenges", "history" }) do
		pages[id] = new("Frame", {
			Name = "Page_" .. id, Size = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1, Visible = false,
		}, legacy)
	end
	_G.QuestMenuContentPages = pages
	_G.QuestMenuScreenGui = screenGui

	return screenGui
end

-- ── открытие/закрытие ──
local OPEN_INFO  = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- ⚠️ МОБИЛЬНЫЙ МАСШТАБ ВСТРАИВАЕМ В АНИМАЦИЮ, А НЕ ПОВЕРХ НЕЁ.
-- Панель 720px на телефоне занимала почти весь экран. Но просто выставить UIScale
-- нельзя: этот же UIScale уже занят анимацией открытия (0.94 → 1) и закрытия.
-- Второй UIScale на том же объекте с ним бы спорил, а сброс в 1 в конце анимации
-- стёр бы наш масштаб. Поэтому единица «раскрытого» состояния — это теперь не 1, а
-- коэффициент HudScale, и все три числа считаются от него.
local Hud = require(game:GetService("ReplicatedStorage"):WaitForChild("HudScale"))

--[[ ⚠️ МЕНЮ УЖИМАЕТСЯ И ПОД РАЗМЕР ОКНА, А НЕ ТОЛЬКО ПОД ТЕЛЕФОН.
     Hud.factor() отвечает на вопрос «это телефон?» и на компьютере всегда равен
     единице. Но панель 720×PANEL_H не влезает и в маленькое окно Studio: у неё
     обрезался верх с крестиком, а список уезжал за нижнюю кромку — выйти можно
     было только по Esc.
     Считаем, сколько панель занимает от окна, и берём меньший из двух
     множителей: телефонный и «чтобы влезло». Запас по краям — чтобы панель не
     упиралась в самые границы экрана.
     Ниже 0.45 не опускаемся: дальше текст в карточках нечитаем, и правильнее
     показать панель с прокруткой, чем нечитаемую целиком. ]]
local FIT_PAD = 48
local FIT_MIN = 0.45

--[[ ⚠️ КВЕСТАМ ОБЩЕГО ТЕЛЕФОННОГО МНОЖИТЕЛЯ МАЛОВАТО.
     Hud.factor() = 0.55 подобран под панели, где содержимое крупное. У
     квестов внутри карточка с текстом задания, наградой и кнопкой слежения,
     и на этом множителе окно выглядит меньше, чем ему нужно.
     Поднимаем только ЗДЕСЬ: общий множитель трогать нельзя, по нему живут
     остальные меню. Ограничение «чтобы влезло» ниже никуда не делось и
     по-прежнему главнее — окно не вылезет за экран. ]]
local PHONE_BUMP = 1.35

--[[ ⚠️ ПОТОЛОК ВЫШЕ ЕДИНИЦЫ — БЕЗ ЭТОГО ПРОШЛАЯ ПРАВКА НЕ ДАЛА НИЧЕГО.
     Единица — это «как нарисовано», 720×536 пикселей макета. И в fit, и в
     clamp стояла именно она, то есть окно физически не могло стать больше
     макета: сколько ни поднимай телефонный множитель, минимум брал единицу.
     Ровно поэтому «сделай побольше» дважды не сработало.
     Теперь окно тянется, пока помещается в экран с полями FIT_PAD, но не
     больше PANEL_MAX: у карточек фиксированный кегль, и на большом экране
     раздутое окно выглядит уже не солидно, а неаккуратно. ]]
-- ⚠️ НА КОМПЬЮТЕРЕ НЕ УВЕЛИЧИВАЕМ. 1.35 растил меню на большом мониторе до
-- тысячи пикселей в ширину (владелец: «слишком здоровое, в студии меньше»).
-- Эталонный размер 720×536 — и есть правильный; ужиматься на малом экране
-- меню по-прежнему может, расти — нет.
local PANEL_MAX = 1.0

local function fitFactor()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local fit = math.min(vp.X / (PANEL_W + FIT_PAD), vp.Y / (PANEL_H + FIT_PAD))
	return math.clamp(math.min(Hud.factor() * PHONE_BUMP, fit), FIT_MIN, PANEL_MAX)
end

local function openQuestMenu()
	local gui = ensureScreenGui()
	if isOpen then return end
	isOpen = true
	rebuildList()
	if questStateEvent then questStateEvent:FireServer("getState") end
	gui.Enabled = true
	backdrop.BackgroundTransparency = 1
	local full = fitFactor()
	panelScale.Scale = 0.94 * full
	TweenService:Create(backdrop, OPEN_INFO, { BackgroundTransparency = 0.55 }):Play()
	TweenService:Create(panelScale, OPEN_INFO, { Scale = full }):Play()
end

function closeQuestMenu()
	if not screenGui or not isOpen then return end
	isOpen = false
	TweenService:Create(backdrop, CLOSE_INFO, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(panelScale, CLOSE_INFO, { Scale = 0.96 * fitFactor() }):Play()
	task.delay(CLOSE_INFO.Time + 0.02, function()
		if not isOpen and screenGui then screenGui.Enabled = false end
	end)
end

--[[ Окно изменили при открытом меню (свернули Studio, повернули телефон) —
     пересчитываем сразу: иначе панель останется в прежнем масштабе и вылезет
     за экран ровно тогда, когда игрок на неё смотрит. ]]
do
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if isOpen and panelScale then panelScale.Scale = fitFactor() end
		end)
	end
end

_G.OpenQuestMenu  = openQuestMenu
_G.CloseQuestMenu = closeQuestMenu

ensureScreenGui()

-- ── данные: живой снапшот QuestState ──
task.spawn(function()
	local deadline = os.clock() + 30
	while os.clock() < deadline do
		local evt = ReplicatedStorage:FindFirstChild("QuestState")
		if evt and evt:IsA("RemoteEvent") then
			questStateEvent = evt
			break
		end
		task.wait(0.1)
	end
	if not questStateEvent then
		warn("[QuestMenu] QuestState RemoteEvent missing; список пуст")
		return
	end
	questStateEvent.OnClientEvent:Connect(function(action, payload)
		if action ~= "state" or type(payload) ~= "table" then return end
		lastQuests = payload.quests or {}
		if isOpen then rebuildList() end
	end)
	questStateEvent:FireServer("getState")
end)

-- ── ESC / J ──
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape and isOpen then
		closeQuestMenu()
	elseif input.KeyCode == Enum.KeyCode.J then
		if isOpen then
			closeQuestMenu()
		else
			for _, key in ipairs({ "PhoneScreenGui", "BuildingScreenGui" }) do
				local gui = _G[key]
				if gui and gui:IsA("ScreenGui") and gui.Enabled then
					return
				end
			end
			openQuestMenu()
		end
	end
end)
