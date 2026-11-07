--!strict
-- Raft HUD design tokens (generated from tokens.json). Source of truth for all reward-ad UI colors/sizes.
local Theme = {}

Theme.Color = {
	["panel"] = Color3.fromHex("#171c26"), -- alpha 0.85 → BackgroundTransparency = 0.15 -- Фон карточек и подсказок поверх 3D-мира (≈85% непрозрачности, как плашка «Топливный бак»).
	["panel-solid"] = Color3.fromHex("#171c26"), -- Непрозрачная версия panel — для превью и мест без мира за спиной.
	["panel-raised"] = Color3.fromHex("#2a3140"), -- Ячейка ресурса и вторичная кнопка внутри panel.
	["outline"] = Color3.fromHex("#1b1f27"), -- Обводка иконок и текстовый stroke (UIStroke 2–3px), как у подписей «Квесты», «Магазин».
	["trim"] = Color3.fromHex("#d9b25a"), -- Золотая рамка world-space табличек над NPC (как у текущей «Награда с рейдов»). Рамка, не фон под текстом.
	["ink"] = Color3.fromHex("#ffffff"), -- Весь текст HUD. На panel — 17:1.
	["ink-muted"] = Color3.fromHex("#b8c2d1"), -- Вторичный текст на panel: «Не сейчас», подзаголовок.
	["watch"] = Color3.fromHex("#198233"), -- Кнопка «Смотреть ▶». Белый текст — 4.9:1.
	["watch-light"] = Color3.fromHex("#36c45a"), -- Верхний блик кнопки watch и кольцо-пульс готового предложения.
	["reward"] = Color3.fromHex("#ffc23d"), -- Количество награды (+20), золотые акценты. Только на panel/outline, не как фон под белым текстом.
	["lack"] = Color3.fromHex("#ff5a5f"), -- Число недостающего («не хватает 5») на panel — 5.9:1.
	["quest-red"] = Color3.fromHex("#e5262e"), -- Бейдж «!» на иконках — повторяем цвет бейджа квестов.
	["health"] = Color3.fromHex("#e8323c"), -- Полоса здоровья. В предложениях не используем.
	["water"] = Color3.fromHex("#2f8cf0"), -- Полоса воды; иконка-капля.
	["hunger"] = Color3.fromHex("#f5a524"), -- Полоса голода.
	["level"] = Color3.fromHex("#7a3fe0"), -- Полоса уровня; премиальные бейджи.
	["wood"] = Color3.fromHex("#9a6236"), -- Иконки бревна и доски — тело.
	["wood-light"] = Color3.fromHex("#d39a5e"), -- Иконки дерева — торцы и блики.
	["metal"] = Color3.fromHex("#aeb9c7"), -- Иконка слитка.
	["metal-light"] = Color3.fromHex("#e6edf5"), -- Грань слитка, блик.
	["fuel"] = Color3.fromHex("#d8453b"), -- Канистра топлива. Красная, чтобы читалась на тёмной ячейке (чёрная капля с бака сливается с panel-raised).
	["rope"] = Color3.fromHex("#d9b36c"), -- Иконка верёвки/волокна.
	["sea"] = Color3.fromHex("#2c7fd0"), -- Фон превью — океан из игры.
	["sky"] = Color3.fromHex("#9fd6ff"), -- Фон превью — небо.
	["timer-track"] = Color3.fromHex("#ffffff"), -- alpha 0.20 → BackgroundTransparency = 0.80 -- Дорожка 12-секундного таймера карточки.
}

Theme.Transparency = { panel = 0.15, ["timer-track"] = 0.8 }

Theme.Space = { s1 = 4, s2 = 8, s3 = 12, s4 = 16 }
Theme.Radius = { sm = 8, md = 12, lg = 16 } -- UICorner px
Theme.Stroke = { outline = 2, trim = 3, icon = 3 } -- UIStroke thickness

-- Font: Builder Sans (Heavy/Bold) — closest to the Nunito 800–900 used in mockups
Theme.Font = {
	Title = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Heavy),
	Body = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
}
Theme.TextSize = { title = 18, amount = 16, button = 16, label = 14, caption = 12 }

Theme.Chip = { md = 52, sm = 36, narrow = 42, iconScale = 0.72 }

return Theme
