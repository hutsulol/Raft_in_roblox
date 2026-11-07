# HANDOFF: Экран смерти — жизни команды и экстра-жизнь за Robux (Roblox)

## Overview
Автоматическая сцена после смерти игрока. У команды 3 жизни. Смерть тратит одну: ряд сердец, одно ломается, сцена уходит сама, игрок возрождается. Когда сгорает последняя — сцена остаётся и предлагает купить экстра-жизнь за Robux: «Купить» → анимация оживления и возврат в игру; «Нет» → чёрный лоадинг «Возвращаемся в лобби…».

Прототип: `Экран смерти.dc.html`. Пропсы: `livesBefore` (1–3), `price` (Robux). Демо-кнопки: смерть 3→2, 2→1, последняя 1→0 + Robux, оживление, лобби, ПК/телефон (с зонами джойстика и прыжка).

Референс движения — `Предупреждения.dc.html` (анимация «болезни»): та же упругая кривая `cubic-bezier(0.34,1.56,0.64,1)` = **Enum.EasingStyle.Back / Out**, тот же уход со сжатием.

## Ограничения соблюдены
Только сдвиг, масштаб, поворот, прозрачность, цвет. Тени — смещённая копия (0/+2..3 px). Градиенты линейные двухцветные. Без blur/filter/mask. Частицы — круги и квадраты (≤ 12). Размеры — в px референса 1586×820; `UIScale = ViewportSize.Y / 820` (на 812×375 → 0.457, минимум 0.45).

## Логика (сервер)
```
onDeath(player):
  lives -= 1
  if lives > 0: show(DEATH, livesBefore = lives+1)   -- уходит сама за 4.0 с, respawn на плоту
  else:         show(DEATH_OFFER)                    -- ждёт выбора
onBuy:   MarketplaceService:PromptProductPurchase(player, EXTRA_LIFE_ID)
         ProcessReceipt → lives = 1, show(REVIVE), respawn
onDecline / prompt закрыт без покупки: show(LOBBY), TeleportService в лобби
```
Клиенту летит один RemoteEvent `{scene = "death"|"revive"|"lobby", livesBefore, price}`.

## Элементы (ScreenGui, IgnoreGuiInset, DisplayOrder выше HUD)

| Элемент | Размер / позиция (ref px) | Стиль |
|---|---|---|
| Затемнение | fromScale(1,1), ZIndex 1 | `#0B1A2A`, Transparency 0.4 |
| Красная виньетка (смерть) | 4 полосы: верх/низ h 22%, лево/право w 14% | UIGradient `#E5484D` α0.55 → α0; пульс α 0.45↔1, 0.9 с |
| Зелёный отблеск (оживление) | fromScale(1,1) | `#7AE04D`, α 0 → 0.28 (30%) → 0 за 0.9 с, старт 0.2 с |
| Полоса ХП (HUD) | left 1.8%, bottom 5%, w 21%, h 28; бейдж 46 | бейдж `#E5484D` (мёртв — `#3A3F4A`), обводка 3 `#9E1F1F`; трек `#701414`, заливка `#FF7561→#D92F2F` |
| Сердце в бейдже | 27×23 | см. «Сердце» |
| Ряд жизней | 3 сердца 120×102, gap 32, центр y 44% | целое `#E5484D`; пустое: контур `#3A3F4A`, заливка `#0F1D2C` |
| Заголовок | шрифт 80 (offer — 75), под сердцами, gap 18 | белый, тень 0/+3 `#14261A` |
| Подпись | шрифт 34 | белый, тень 0/+2 |
| Кнопка «Купить ◈ N» | шрифт 36; padding 16×36; radius 18; gap 24 до второй | `#7AE04D→#48B428`, обводка 3 `#14261A`, тень 0/+5 `#2A6E14`; бейдж цены `#14261A` radius 12, ромб-иконка Robux белый |
| Кнопка «Нет, в лобби» | шрифт 30; padding 15×33 | `#4A5578→#323A54`, тень `#1B2035` |
| Лобби-лоадинг | fromScale(1,1), ZIndex 5 | фон `#050607`; текст рукописный 70 (PermanentMarker), белая лодка 90, «Забег завершён» 30 α0.7 |

Шрифт — **FredokaOne** (`Enum.Font.FredokaOne`), подписи можно GothamBold.

### Сердце (размер S)
Квадрат S/2, rotate 45°, позиция (0.25S, 0.2S); два круга Ø S/2 в (0.073S, 0.023S) и (0.427S, 0.023S). Обводка — та же тройка `#14261A`, scale 1.16 вокруг (50%, 55%), под основной. Блик — круг 0.15S в (0.2S, 0.14S), белый α0.6.
- Трещины: 3 тёмных прямоугольника 0.06S×0.22S: (0.47S,0.12S) rot 18°; (0.5S,0.32S) rot −24°; (0.46S,0.48S) rot 14°; появляются по очереди через 50 мс.
- Пустое: тройка `#3A3F4A` scale 1.16 + тройка `#0F1D2C` сверху.
- Roblox: предпочтительно 3 ImageLabel (целое / треснувшее / контур), либо Frame + UICorner.

## Тайминг

### Смерть (есть жизни) — 4.0 с, уходит сама
| Время | Что | Кривая |
|---|---|---|
| 0–0.45 | затемнение α → 0.4; виньетка пульсирует | Quad Out |
| 0.05–0.15 | трещины на сердце в бейдже HUD | линейно |
| 0.15–0.65 | сердце вырывается из бейджа: 30% → y −0.8S, rot −10°, scale 1.2; 100% → (+0.6S, −9S), rot 28°, scale 0.5, α 0 | Quad In |
| 0.12–0.72 | 6 осколков из бейджа (18–26 px), углы −75…75°, сдвиг 5×размер, rot 280°, α → 0 | Quad Out |
| 0.3–0.7 | бейдж `#E5484D` → `#3A3F4A` | Quad |
| 0.5 / 0.58 / 0.66 | пустые контуры всплывают снизу (+2em → 0); красные сердца: scale 3 → 0.92 (55%) → 1.06 (75%) → 1 | **Back Out** |
| 1.05–1.15 | трещины на ломающемся сердце (индекс = livesAfter) | линейно |
| 1.1–1.7 | ломается: scale 1.22 rot −7° (35%) → 0.9 rot 5° (65%) → 0.6 α 0; под ним остаётся контур | Quad In |
| 1.35–2.05 | 10 осколков (24–42 px) | Quad Out |
| 1.15–1.85 | заголовок «Осталось жизней: N» — Back Out из scale 3 | Back Out |
| 1.7–2.2 | подпись «Команда потеряла одну жизнь» / «Последняя жизнь команды — берегите её» | Quad Out |
| 1.3 → | целые сердца пульсируют scale 1↔1.05, 1 с | Sine |
| 3.4–3.9 | контент: scale → 0.55, α → 0 | Quad In |
| 3.5–4.0 | затемнение α → 0; Destroy | Quad In |

### Смерть (жизни кончились) — остаётся до выбора
То же до 1.85 с, кроме: все три контура пустые, ломается последнее. Заголовок «ЖИЗНИ КОМАНДЫ КОНЧИЛИСЬ» (1.15 с), подпись «Купить экстра-жизнь за Robux и продолжить забег?» (1.7 с), кнопки всплывают снизу 2.0–2.5 с, «Купить» пульсирует scale 1↔1.04 с 2.5 с (1.2 с цикл). Выхода нет.

### Оживление — 3.7 с
| Время | Что | Кривая |
|---|---|---|
| 0–0.3 | затемнение α → 0.4 | Quad Out |
| 0.2–1.1 | зелёный отблеск α 0 → 0.28 → 0 | Quad Out |
| 0.1–0.9 | большое сердце (130): scale 0.3 rot −20° → 1.3 rot 6° (50%) → 0.95 (70%) → 1 | Back Out |
| 0.45–1.35 | 12 искр (`#7AE04D` / `#FFD54A` / `#FFF`, 26–45 px): вылет 7×размер, scale → 0.2, α → 0 | Quad Out |
| 0.5–1.1 | сердце в бейдже HUD возвращается (тот же Back Out), бейдж снова `#E5484D` | Back Out |
| 0.8–1.8 | полоса ХП 0% → 100% | Back Out |
| 0.6–1.3 | «ВЫ ЖИВЫ!» (`#7AE04D`, 90) — Back Out | Back Out |
| 0.9–3.1 | сердце «бьётся»: scale 1 → 1.18 (15%) → 1 (30%) → 1.12 (45%) → 1; 2 удара по 1.1 с | Sine |
| 1.2–1.7 | подпись «Экстра-жизнь активирована. Забег продолжается» | Quad Out |
| 3.1–3.6 | всё сжимается (0.55) и тает; затемнение → 0; Destroy | Quad In |

### Лобби — не уходит
0–0.5 чёрный фон α → 1; 0.3 / 0.45 / 0.6 — текст «Возвращаемся в лобби…», лодка, «Забег завершён» всплывают снизу. Точки бегут 1→2→3 каждые 450 мс. Лодка качается ±8 px, ±2°, 2.4 с. Остаётся до телепорта.

## Тексты
- «Осталось жизней: {N}»; «Команда потеряла одну жизнь»; «Последняя жизнь команды — берегите её».
- «ЖИЗНИ КОМАНДЫ КОНЧИЛИСЬ»; «Купить экстра-жизнь за Robux и продолжить забег?»; кнопки «Купить ◈ {price}» / «Нет, в лобби».
- «ВЫ ЖИВЫ!»; «Экстра-жизнь активирована. Забег продолжается».
- «Возвращаемся в лобби…»; «Забег завершён».

## Цвета
`#E5484D` сердце/виньетка · `#3A3F4A` контур пустого · `#0F1D2C` заливка пустого · `#14261A` обводки/тени · `#0B1A2A` затемнение · `#7AE04D→#48B428` зелёный (кнопка, «ВЫ ЖИВЫ!», отблеск) · `#2A6E14` тень зелёного · `#4A5578→#323A54` серая кнопка · `#FFD54A` искры · `#9E1F1F`/`#701414` полоса ХП · `#050607` лобби.

## Телефон 812×375
UIScale 0.457. Ряд сердец и кнопки — в центре 30–70% ширины; джойстик (Ø ~130 px слева-снизу) и прыжок (Ø ~90 px справа-снизу) не пересекаются. Кнопки — минимум 44 px высоты после масштаба (при 0.457 → задать min-height через UISizeConstraint).

## Скелет Luau
```lua
local TS, MPS = game:GetService("TweenService"), game:GetService("MarketplaceService")
local BACK = TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local function tw(o, t, p, style, dir, delay)
	local tween = TS:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out, 0, false, delay or 0), p); tween:Play(); return tween
end
local function drop(obj, delay) -- scale 3 → 1, Back Out
	local s = obj:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", obj); s.Scale = 3; obj.Visible = true
	task.delay(delay, function() TS:Create(s, BACK, {Scale = 1}):Play() end)
end
local function shrinkOut(obj, delay)
	local s = obj:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", obj)
	tw(s, 0.5, {Scale = 0.55}, Enum.EasingStyle.Quad, Enum.EasingDirection.In, delay)
	for _, d in ipairs(obj:GetDescendants()) do
		if d:IsA("GuiObject") then tw(d, 0.5, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In, delay) end
		if d:IsA("TextLabel") then tw(d, 0.5, {TextTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In, delay) end
	end
end

local function playDeath(gui, livesBefore, price, onBuy, onDecline)
	local livesAfter = livesBefore - 1
	local offer = livesAfter == 0
	tw(gui.Dim, 0.45, {BackgroundTransparency = 0.4})
	-- HUD: сердце вырывается
	task.delay(0.15, function()
		local h = gui.HUD.Badge.Heart
		tw(h, 0.15, {Position = h.Position - UDim2.fromScale(0, 0.35), Rotation = -10})
		task.delay(0.15, function()
			tw(h, 0.35, {Position = h.Position + UDim2.fromScale(0.25, -4), Rotation = 28}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			for _, p in ipairs(h:GetDescendants()) do if p:IsA("GuiObject") then tw(p, 0.35, {BackgroundTransparency = 1}) end end
		end)
	end)
	tw(gui.HUD.Badge, 0.4, {BackgroundColor3 = Color3.fromHex("3A3F4A")}, nil, nil, 0.3)
	-- ряд жизней
	for i = 1, 3 do
		local slot = gui.Center.Lives["Heart" .. i]
		slot.Outline.Visible = true
		slot.Red.Visible = i <= livesBefore
		if i <= livesBefore then drop(slot.Red, 0.5 + (i - 1) * 0.08) end
		if i == livesBefore then -- ломается
			task.delay(1.05, function() slot.Red.Cracks.Visible = true end)
			task.delay(1.1, function()
				local s = slot.Red:FindFirstChildOfClass("UIScale")
				tw(s, 0.2, {Scale = 1.22}); tw(slot.Red, 0.2, {Rotation = -7})
				task.delay(0.2, function()
					tw(s, 0.4, {Scale = 0.6}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					for _, p in ipairs(slot.Red:GetDescendants()) do if p:IsA("GuiObject") then tw(p, 0.4, {BackgroundTransparency = 1}) end end
					-- + 10 осколков из slot.Shards (Frame'ы 24–42 px): Position вверх на 5×size, Rotation +280, Transparency → 1, 0.7 с
				end)
			end)
		end
	end
	gui.Center.Title.Text = offer and "ЖИЗНИ КОМАНДЫ КОНЧИЛИСЬ" or ("Осталось жизней: " .. livesAfter)
	drop(gui.Center.Title, 1.15)
	gui.Center.Caption.Text = offer and "Купить экстра-жизнь за Robux и продолжить забег?" or (livesAfter == 1 and "Последняя жизнь команды — берегите её" or "Команда потеряла одну жизнь")
	tw(gui.Center.Caption, 0.5, {Position = gui.Center.Caption.Position, TextTransparency = 0}, nil, nil, 1.7)
	if offer then
		gui.Center.Buttons.Visible = true
		gui.Center.Buttons.Buy.Price.Text = tostring(price)
		gui.Center.Buttons.Buy.Activated:Once(onBuy)
		gui.Center.Buttons.Decline.Activated:Once(onDecline)
		-- пульс кнопки Buy: UIScale 1 ↔ 1.04, 1.2 с, с 2.5 с
	else
		task.delay(3.4, function() shrinkOut(gui.Center, 0) end)
		tw(gui.Dim, 0.5, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 3.5)
		task.delay(4.0, function() gui:Destroy() end)
	end
end

local function playRevive(gui)
	tw(gui.Dim, 0.3, {BackgroundTransparency = 0.4})
	tw(gui.Flash, 0.27, {BackgroundTransparency = 0.72}, nil, nil, 0.2)
	tw(gui.Flash, 0.63, {BackgroundTransparency = 1}, nil, nil, 0.47)
	local big = gui.Center.BigHeart
	local s = Instance.new("UIScale", big); s.Scale = 0.3; big.Rotation = -20; big.Visible = true
	task.delay(0.1, function()
		TS:Create(s, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		tw(big, 0.8, {Rotation = 0}, Enum.EasingStyle.Back)
	end)
	-- 0.45 с: 12 искр (#7AE04D/#FFD54A/#FFF) вылет 7×size, Scale → 0.2, Transparency → 1, 0.9 с
	tw(gui.HUD.Badge, 0.4, {BackgroundColor3 = Color3.fromHex("E5484D")}, nil, nil, 0.5)
	tw(gui.HUD.Bar.Fill, 1.0, {Size = UDim2.fromScale(1, 1)}, Enum.EasingStyle.Back, nil, 0.8)
	drop(gui.Center.Title, 0.6) -- «ВЫ ЖИВЫ!»
	-- 0.9–3.1: сердцебиение Scale 1→1.18→1→1.12→1, 2 цикла по 1.1 с
	task.delay(3.1, function() shrinkOut(gui.Center, 0) end)
	tw(gui.Dim, 0.5, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 3.1)
	task.delay(3.7, function() gui:Destroy() end)
end

-- Покупка
local function onBuy(player) MPS:PromptProductPurchase(player, EXTRA_LIFE_PRODUCT_ID) end
-- Сервер: MPS.ProcessReceipt → выдать жизнь, послать клиенту scene = "revive"; при отмене — scene = "lobby" + TeleportService
```

## Files
- `Экран смерти.dc.html` — прототип (keyframes `ds*` в шапке, тайминги в `renderVals()` и `go()`).
- `Предупреждения.dc.html` — референс движения.
- `Roblox HUD.dc.html` — референс полосы ХП.
