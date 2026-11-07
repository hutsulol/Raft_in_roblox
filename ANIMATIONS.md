# Анимации в этом проекте — инструкция для агентов

Читай это **до** того, как писать код движения. Почти всё здесь — след реальной поломки:
каждый абзац стоил нескольких заходов, которые «выглядели правильно» и не работали.

Всё, что ниже, проверено по коду: у каждого правила есть файл и строка. Если правило
расходится с кодом — верь коду и поправь этот файл.

---

## 0. Прочти хотя бы это

> **У персонажа игрока НЕТ ни одного `Motor6D`.** Это новый физический риг Roblox: части
> держит `BallSocketConstraint`, а поза задаётся **целевым `Transform`** у
> `AnimationConstraint`. Ни `C0`, ни `C1` у него нет.
> ([MapItem.client.lua:16](src/StarterPlayerScripts/MapItem.client.lua:16))

Любой код, начинающийся с `char:FindFirstChild("Right Shoulder")` или пишущий в `C0`
сустава руки, здесь мёртв. На этом уже было два захода подряд
([ResourcePull:483](src/StarterPlayerScripts/ResourcePull.client.client.lua:483)).

> **`Motor6D.Transform` и `Bone.Transform` НЕ реплицируются.** Сами суставы — инстансы, они
> реплицируются. Отсюда разделение: **сервер собирает суставы, клиент их крутит.**
> ([OctopusClient:5](src/StarterPlayerScripts/OctopusClient.client.lua:5),
> [PirateIslandAnim:5](src/StarterPlayerScripts/PirateIslandAnim.client.lua:5))
>
> В Play Solo всё выглядит правильно, потому что сервер и клиент там один процесс. В игре
> НПС стоят столбами, и **в логе тихо**.

---

## 1. Выбор способа

| Способ | Когда | Образец |
|---|---|---|
| **Поза кодом** | движение игрока: замах, удар, поза с предметом | [HammerSwing](src/StarterPlayerScripts/HammerSwing.client.lua) |
| **Клип таблицей** | НПС, экипаж, звери — циклы и удары | [CrewClips](src/ReplicatedStorage/CrewClips.lua) |
| **Опубликованная анимация** | только если клип точно принадлежит владельцу игры | [DockCaptainAnimator](src/ServerScriptService/DockCaptainAnimator.server.lua) |

Порядок предпочтения именно такой: опубликованные анимации здесь — **последний** выбор.

---

## 2. Почему опубликованные анимации в этом проекте ненадёжны

Две независимые причины, обе молчаливые.

**Права на ассет.** Roblox не даёт проигрывать чужие анимации:

```
Failed to load animation ...: User is not authorized to access Asset.
The experience doesn't have access permission to use asset id ...
```

Клип должен быть залит под аккаунтом (или группой) **владельца игры**. Чужой ID из тулбокса
не заработает никогда — **это не чинится кодом**
([FoodSystem:197](src/ServerScriptService/FoodSystem.server.lua:197),
[DiverSystem:1544](src/ServerScriptService/DiverSystem.server.lua:1544)).

**Неопубликованный плейс.** `AnimationId` гонит движок за ассетом на серверы Roblox, и при
`serverplaceid = 0` это молча не срабатывает. Ровно ради этого и появились клипы-таблицей
([CrewClips:6](src/ReplicatedStorage/CrewClips.lua:6)).

### Ловушка: `LoadAnimation` НЕ падает на недоступном ассете

Трек создаётся, `Play()` отрабатывает, ошибки нет — просто у трека нет кадров. Следствия:

* `track.Stopped` **не наступает никогда** → ожидание конца клипа виснет до своего потолка;
* `track.Length` **остаётся нулём** — вот надёжный признак.

```lua
-- Length появляется не в тот же кадр: клип ещё грузится с серверов Roblox
local spent = 0
while track.Length <= 0 and spent < 0.5 do
    task.wait(0.05); spent += 0.05
end
if track.Length > 0 then
    -- клип реально идёт: ждём Stopped, потолок по длине самого клипа
else
    warn("анимация не проигралась: ассет недоступен опыту")
    task.wait(FALLBACK)   -- фиксированная пауза вместо зависания
end
```

([FoodSystem:713](src/ServerScriptService/FoodSystem.server.lua:713);
то же у капитана причала — [DockCaptainAnimator:156](src/ServerScriptService/DockCaptainAnimator.server.lua:156),
там ждут длину 6 секунд, «пропущенный `Stopped` вешает цикл намертво».)

Снаружи ошибка выглядела так: звук съеденной свёклы играет, движения нет, предмет остаётся
в руке, повторный клик не делает ничего. В логе — ни строчки.

### Остальное про опубликованные клипы

| Правило | Где |
|---|---|
| `Priority` и `Looped` выставляй **руками сразу после загрузки** | [AxeClient:42](src/StarterPlayerScripts/AxeClient.client.lua:42) |
| `Priority = Action` — иначе поза не переборет тул в руках | [FoodSystem:670](src/ServerScriptService/FoodSystem.server.lua:670) |
| **`Looped` Roblox может молча сбросить** к запечённому в ассете значению, когда тот догрузится → переспрашивай | [DiverSystem:1670](src/ServerScriptService/DiverSystem.server.lua:1670) |
| **`AdjustSpeed` НЕ реплицируется.** Скорость уезжает только в момент `Play` | [EngineerSystem:617](src/ServerScriptService/EngineerSystem.server.lua:617) |
| Незацикленные клипы **грей заранее** с весом 0.001, плюс `PreloadAsync` | [EngineerSystem:223](src/ServerScriptService/EngineerSystem.server.lua:223), [DiverSystem:1631](src/ServerScriptService/DiverSystem.server.lua:1631) |
| `Animator` живёт на `Humanoid` и создаётся кодом; `Humanoid:LoadAnimation` — только запасной путь | [FoodSystem:240](src/ServerScriptService/FoodSystem.server.lua:240) |
| Объект `Animation` искать через `AssetFind.findClass("Animation", ...)`, а не `FindFirstChild` | `AssetFind.lua` |

Про `AdjustSpeed` подробнее — это была «разгадка телепорта»: сервер морозил трек скоростью
ноль, клиент об этом не знал, доигрывал клип до конца, и тело **ложилось обратно**. Держать
позу можно только реплицируемыми командами `Play`/`Stop`. Статичную позу заморозкой держать
всё-таки можно (так делает водолаз), но тогда её нельзя просто `Stop`-нуть — на замороженном
треке `Stop` может не сработать, и трек останется доминирующим, перекрывая ходьбу и прыжок.

### Клип грузится, длина есть, а тело не двигается

Значит **позы в клипе нулевые** — проблема самого ассета, а не кода. Проверяется так:

```lua
local ks = KeyframeSequenceProvider:GetKeyframeSequenceAsync(animId)
-- ⚠️ ОБХОДИТЬ РЕКУРСИВНО, через GetSubPoses:
-- у R6/R15 почти все суставы лежат во ВЛОЖЕННЫХ позах, и плоская проверка
-- ложно скажет «пусто».
```

([EngineerPush:35](src/StarterPlayerScripts/EngineerPush.client.lua:35))

### Персонажа игрока анимирует ЕГО клиент

Трек, запущенный **сервером** на `Animator` игрока, самому игроку не реплицируется — отсюда
«рука не двигалась». Локальный `Play` на своём персонаже Roblox реплицирует всем сам. Сервер
шлёт клиенту `AnimationId` ремоутом, а играет клиент
([EngineerPush:2](src/StarterPlayerScripts/EngineerPush.client.lua:2),
[EngineerSystem:576](src/ServerScriptService/EngineerSystem.server.lua:576)).

Для НПС — наоборот: их треки грузит и играет сервер.

---

## 3. Поза кодом — основной приём для игрока

### Рецепт

Один и тот же в пяти местах: молоток, рубка, огнемёт, карта, питьё.

**Шаг 1. Найти «сустав» по имени ДЕТАЛИ**, приняв все три вида сочленений — риги в проекте
разные:

```lua
local ARM_NAMES = { ["Right Arm"] = true, ["RightUpperArm"] = true }

for _, d in ipairs(char:GetDescendants()) do
    if d:IsA("AnimationConstraint") then
        local limb = d.Attachment1 and d.Attachment1.Parent and d.Attachment1.Parent.Name
        if limb and ARM_NAMES[limb] then physicalRig = true; return d end
    elseif d:IsA("Motor6D") then
        if d.Part1 and ARM_NAMES[d.Part1.Name] then return d end
    elseif d:IsA("Bone") then
        if ARM_NAMES[d.Name] then return d end
    end
end
```

Для руки хватает `Attachment1`. **Для головы — нет**: там надо смотреть оба конца
([DrinkPose:118](src/StarterPlayerScripts/DrinkPose.client.lua:118)).

**Шаг 2. Писать в `Transform`** — единственное поле, общее для всех трёх видов.

**Шаг 3. Писать ПОСЛЕ аниматора** — `BindToRenderStep` с приоритетом `Character + 1`.
Раньше — и аниматор затрёт позу в том же кадре.

**Шаг 4. Повторить в `Stepped`, если риг физический.** У него `Transform` — это *цель* для
решателя, и на шаге физики решатель берёт то, что осталось от аниматора, а не то, что ты
написал при отрисовке.

```lua
RunService:BindToRenderStep("HammerSwing",
    Enum.RenderPriority.Character.Value + 1, applySwing)

RunService.Stepped:Connect(function()
    if physicalRig then applySwing() end
end)
```

Флаг `physicalRig` ставится там же, где нашёлся `AnimationConstraint`
([HammerSwing:61](src/StarterPlayerScripts/HammerSwing.client.lua:61)). Расчёт выносится в
отдельную функцию — её зовут оба места.

### Знак поворота зависит не от оси, а от того, ОТ ЧЕГО он считается

Главный источник промахов «сделал вперёд — ушло назад».

* **Поворот ЗАМЕНЯЕТ позу** (`Transform = CFrame.Angles(...)`) — отсчёт от позы покоя, где
  рука вытянута вперёд по горизонтали. `+X` опускает вперёд-вниз (удар), `−X` поднимает.
* **Поворот КЛАДЁТСЯ ПОВЕРХ позы** (`Transform = CFrame.Angles(...) * base`) — отсчёт от
  текущей позы, а в позе с молотком рука уже поднята. Тот же `+X` задерёт её ещё выше;
  опускает `−X`.

В проекте живут оба случая с **противоположными знаками**, и это не опечатка:
[ResourcePull:502](src/StarterPlayerScripts/ResourcePull.client.client.lua:502) заменяет позу
и берёт `+110`, [HammerSwing:36](src/StarterPlayerScripts/HammerSwing.client.lua:36) кладёт
поверх и берёт `−90`.

### Оси руки

| Ось | Что делает |
|---|---|
| **X** | подъём / опускание |
| **Y** | ведёт вбок |
| **Z** | **прокрут руки вокруг себя** — рука стоит на месте, а предмет в кисти заметает дугу |

Прокрут вешай на **предплечье**, а не на плечо. `RightLowerArm` — это **локоть**: догибая
его, уводишь вперёд всё, что ниже локтя. Отдельной кисти у R6 нет.
([DrinkPose:39](src/StarterPlayerScripts/DrinkPose.client.lua:39))

Шкала сжатая: у физического рига `+25` по X — это уже рука вертикально вниз.

> ⚠️ **Знаки НЕ переносятся** между ригами и между скриптами. В репозитории есть прямо
> противоречащие друг другу таблицы поз для R6, а для головы `MapItem` и `DrinkPose` держат
> противоположные знаки. Не выводи общее правило — **сверяйся с рабочей таблицей того рига,
> с которым работаешь**.

### Множитель — СЛЕВА

```lua
armJoint.Transform = CFrame.Angles(math.rad(x), 0, 0) * base   -- правильно
```

Справа поворот шёл бы вокруг собственных, уже повёрнутых осей детали — то есть вокруг
предплечья, а не плеча: вместо замаха получается вращение предмета в кисти.

### Слепок базовой позы снимать ТОЛЬКО когда движения нет

```lua
if not swingStart then
    swingBase = armJoint.Transform
end
swingStart = os.clock()
```

Иначе накопление: следующий клик приходит посреди предыдущего движения и читает из
`Transform` **свой же повёрнутый кадр**. Каждый клик добавлял свои девяносто градусов, и
рука прокручивалась на полный оборот. Эта же строка бесплатно даёт «лимит»: отсчёт всегда от
одной снятой позы ([HammerSwing:117](src/StarterPlayerScripts/HammerSwing.client.lua:117)).

### Как заканчивать — зависит от стиля

Здесь легко ошибиться, потому что правила **противоположные**:

* **Клал поверх чужой позы** → просто перестань писать. Ни слепка, ни `identity`: поза
  принадлежит аниматору, он кладёт её каждый кадр, и любая запись подменит уже посчитанный
  им кадр ([HammerSwing:88](src/StarterPlayerScripts/HammerSwing.client.lua:88)).
* **Подменял позу целиком** → верни `CFrame.identity`, **ровно один раз**. Иначе останется
  последнее записанное значение и конечность застрянет
  ([ResourcePull:632](src/StarterPlayerScripts/ResourcePull.client.client.lua:632),
  `relaxPose` в [MapItem:236](src/StarterPlayerScripts/MapItem.client.lua:236)).

### Отсчёт по времени, а не твином

Повторный вызов сдвигает начало, и конечность не застревает на полпути прерванного твина.
Жмёшь чаще — движение чаще.

### Кривая скорости

Линейная скорость читается как механизм, а не как удар: вниз квадратичный разгон, обратно
сглаженный, замах короче возврата.

```lua
local function ease(f) return f * f * (3 - 2 * f) end

if t < DOWN_PART then
    local f = t / DOWN_PART
    x = SWING_X * f * f                  -- разгон в удар
else
    local g = (t - DOWN_PART) / (1 - DOWN_PART)
    x = SWING_X * (1 - ease(g))          -- плавный возврат
end
```

### Глушить штатный `Animate` — только на клиенте и НЕ одним разом

Он возвращается. Нужна серия попыток:

```lua
local animate = character:FindFirstChild("Animate")
if animate then animate.Disabled = sleeping end
task.spawn(function()
    for _ = 1, 10 do
        if character:GetAttribute("Sleeping") ~= true then return end
        stopAllTracks()
        task.wait(0.05)
    end
end)
```

Без этого лежащий игрок продолжал «бежать»: плот движется, `Humanoid` видит скорость и
крутит бег ([SleepPose:4](src/StarterPlayerScripts/SleepPose.client.lua:4)).

### Оговорка про `C0`

«Не трогать `C0`» относится к суставам **рига**. Свой `Motor6D` для предмета в руке проект
создаёт сам и пересчитывает его `C0` каждый кадр — это другой случай, не противоречие
([MapItem:231](src/StarterPlayerScripts/MapItem.client.lua:231)).

---

## 4. Клипы таблицей — для НПС и зверей

Поза лежит обычной таблицей и кладётся в `Motor6D.Transform` напрямую, теми же числами, из
которых `BuildAnimations` собирает `KeyframeSequence`. Публикация не нужна вовсе.

```lua
local CrewClips = require(ReplicatedStorage.CrewClips)
local anim = CrewClips.attach(model)   -- один раз на модель
anim:play("MeleeWalk")                 -- цикл
anim:once("SabreSwing")                -- событие, потом вернётся цикл
anim:overlay(clip, ARM_ONLY)           -- поверх ходьбы, только на эти суставы
anim:step(dt)                          -- каждый кадр
```

**Ключ в таблице ≠ имя сустава.** У экипажа ключ — имя **детали** (`Torso` двигает
`RootJoint`, `Head` — `Neck`), карта лежит в `MOTOR_OF`
([CrewClips:31](src/ReplicatedStorage/CrewClips.lua:31)). У курицы ключи — наоборот, имена
**суставов**. Общее правило: **сверяйся с картой, не угадывай**.

**Суставы доезжают ПОЗЖЕ привязки.** Сервер строит `Motor6D` при спавне, а клиентский
`attach()` успевает раньше, чем они доедут по репликации. Кэш с пустым списком раньше жил
вечно — «0 из 6» оставалось навсегда. Нужен перескан, троттлинг раз в секунду
([CrewClips:207](src/ReplicatedStorage/CrewClips.lua:207); то же для зверей —
[PirateIslandAnim:44](src/StarterPlayerScripts/PirateIslandAnim.client.lua:44)).

**Риг собирается ПО ТЕКУЩЕЙ ПОЗЕ** — `setup()` строго до перемещения модели. `C1` снимается
с фактического `CFrame` детали ([CowRig:21](src/ReplicatedStorage/CowRig.lua:21)).

**`C1` — с фактической позы, а не чистым переносом.** У импортированной головы поворот
запечён в `CFrame` детали (180° к торсу); чистые переносы приравнивали её поворот к
торсовому — **голова вставала задом наперёд**
([ChickenRig:94](src/ReplicatedStorage/ChickenRig.lua:94)).

**Единицы.** В коровьем ключе 12 чисел: первые три — смещение **в единицах рига**
(`100 = 1 студ`, `POS_SCALE`), остальные девять — матрица поворота как есть
([CowAnimator:21](src/ReplicatedStorage/CowAnimator.lua:21)).

**Оси импорта могут не совпасть со шпаргалкой.** У курицы `+Z` на крыле машет **вниз**, а не
вверх — в прыжке крылья уходили под тушку. Чинится в `toCFrame` (`WING_FLIP`, на оба крыла
сразу), **а не правкой клипов** ([ChickenAnimator:188](src/ReplicatedStorage/ChickenAnimator.lua:188)).

**Действие поверх ходьбы — overlay на подмножество суставов**, а не подмена позы: пират не
должен вставать столбом ради взмаха. На въезде и выезде накладка смешивается с базой, иначе
рука дёргается на стыке ([CrewClips:190](src/ReplicatedStorage/CrewClips.lua:190),
[PirateIslandAnim:201](src/StarterPlayerScripts/PirateIslandAnim.client.lua:201)).

**Если суставов нет — модуль молчит.** `step()` при пустом списке выходит без единого
`warn`. Диагностику ищи в логе привязки:

```
[CrewClips] Pirate_Bosun: привязано суставов 0 из 6. Motor6D в модели: НЕТ НИ ОДНОГО (риг не R6?)
```

### Откуда берутся сами клипы

**R6-анимации не импортируются из FBX** — этот путь только для R15 со скиннед-мешами, а 3D
Importer везёт одну геометрию. Клипы собираются `KeyframeSequence`-ами прямо в Studio через
[BuildAnimations.lua](src/ServerStorage/BuildAnimations.lua): `require` из командной строки →
`KeyframeSequence` в `ServerStorage.PirateCrewAnimations` → «Save to Roblox». Это
**ModuleScript**, а не Script: в `ServerScriptService` он молотил бы на каждом старте впустую.

> ⚠️ `BuildAnimations` читает `ServerStorage.PirateCrewClips`, а репозиторная копия таблицы
> лежит в `src/ReplicatedStorage/PirateCrewClips.lua`. **Экземпляра два** — правя один,
> проверь, тот ли ты правишь.

---

## 5. Свой риг: сборка `Motor6D` из голой модели

Пример — осьминог, [OctopusRig.lua](src/ReplicatedStorage/Octopus/OctopusRig.lua).

**Как `Motor6D` работает.** Он не «запоминает, где деталь стояла». Он решает

```
Part0.CFrame * C0  ==  Part1.CFrame * C1
```

**двигая `Part1`**. Отсюда главная ловушка:

> Задашь `C0` и `C1` **чистым переносом** — уравнение заставит обе части иметь **одинаковый
> поворот**. Детали слетаются в кучу под чужими углами.
> ([OctopusRig:130](src/ReplicatedStorage/Octopus/OctopusRig.lua:130))

Правильно: `C0` — из таблицы, **`C1` — замерить по живой модели**:

```lua
m.C0 = CFrame.new(j.c0 * scale)                     -- :157
m.C1 = childRest:ToObjectSpace(parentRest * m.C0)   -- :170
```

Остальное оттуда же:

* **позу покоя снимать ДО первого сустава** — снимок делает порядок сборки неважным ([:80](src/ReplicatedStorage/Octopus/OctopusRig.lua:80));
* **смещения домножать на измеренный масштаб импорта** — модель приезжает то крупнее, то мельче, и константа молча врёт ([:42](src/ReplicatedStorage/Octopus/OctopusRig.lua:42));
* **корень ставить по осям мира**, поворот головы прятать в `C1` — иначе «вверх» поедет вбок ([:107](src/ReplicatedStorage/Octopus/OctopusRig.lua:107));
* **обязателен только корень**, остальное — по наличию: `assert` на каждую часть убивал весь риг из-за одной мелочи в экспорте ([:56](src/ReplicatedStorage/Octopus/OctopusRig.lua:56));
* считай **дрейф замеров** и предупреждай: расходятся сильно — точка вращения не там ([:175](src/ReplicatedStorage/Octopus/OctopusRig.lua:175)).

**Внешнее движение — домножением и строго ПОСЛЕ `step()`**, потому что проигрыватель
перезаписывает `Transform` в том же кадре:

```lua
applySwell(rig, clock)   -- строго ПОСЛЕ step: он перезаписывает Transform
```

**Только жёсткие детали.** Ни масштабирования `Size`, ни скиннинга: ранняя версия сжимала
`Size` головы, изображая вмятину, — корона, воротник и глаза сидят на фиксированных
смещениях, поэтому остались на месте, и голова видимо отвалилась. Удар продаётся **хлыстом**,
а не деформацией. Аддитивный клип **обязан возвращаться в ноль на `t = 1`**, иначе слой
снимется скачком.

---

## 6. Сервер и НПС

**Сервер только называет клип, позу считает клиент.** Обмен идёт атрибутами:

| Атрибут | Смысл |
|---|---|
| `Clip` / `ClipT` | цикл; сервер пишет **только при смене имени** |
| `ClipOnce` / `ClipOnceT` | разовый; метка пишется **каждый раз** |
| `ClipOverlay` / `ClipOverlayT` | накладка |

Клиент ловит разовые и накладки **по смене метки**, а не по наличию атрибута
([PirateIslandAI:30](src/ServerScriptService/PirateIslandAI.server.lua:30),
[PirateIslandAnim:188](src/StarterPlayerScripts/PirateIslandAnim.client.lua:188)). Тот же
протокол используют звери, огнемёт, вышка и повстанцы.

**У моделей людей нет ни одного `Motor6D` — R6 собирается руками, на сервере**
([PirateIsland:187](src/ServerScriptService/PirateIsland.server.lua:187)). При этом:

* искать детали через `GetDescendants`, а не `FindFirstChild` по верхнему уровню — прошлая версия молча возвращала 0;
* если `Motor6D` уже есть — **выйти, ничего не трогая**;
* если `Torso` не нашёлся, это, скорее всего, **R15** — набор клипов R6 ему не подойдёт, и это частая причина «ничего не собралось»;
* **снести сварки между деталями тела**: `Motor6D` поверх сварки — заклиненная конечность.

**`Anchored` убивает позы.** Заякоренные части игнорируют `Motor6D` — «поэтому большая часть
рига стояла неподвижно». Якорь только на корне, всё остальное свободно
([SwimmingPirate:176](src/ServerScriptService/SwimmingPirate.server.lua:176)). Двигать такого
НПС — кинематически, присваиванием `hrp.CFrame` с обнулением скоростей.

`CanCollide` и `CanQuery` — **не универсальны**: зверю коллизия нужна (иначе игрок проходит
сквозь тушу), капитану причала `CanQuery` намеренно выключен. Смотри по месту.

**Суставы и замеры — по авторской позе клона, ДО перемещения корня.** Порядок: клонировать →
собрать риг → атрибуты и `Humanoid` → положить в папку → ставить на место.

**Нет `Animation` внутри модели — переключайся на табличные клипы, а не падай.** Раньше на
отсутствующем ключе Lua падал прямо в этом месте, поток абордажа умирал, и пират тонул
неуправляемым ([SwimmingPirate:465](src/ServerScriptService/SwimmingPirate.server.lua:465)).

**Труп надо распустить один раз.** Атрибут `Clip` остаётся на трупе с последнего тика ИИ, и
цикл ходьбы продолжал крутить суставы убитого
([PirateIslandAnim:170](src/StarterPlayerScripts/PirateIslandAnim.client.lua:170)).

---

## 7. Диагностика

Правило, выведенное дорогой ценой: **если движения не видно, догадаться о причине нельзя —
причин минимум пять, и снаружи они выглядят одинаково.** Печатай сразу:

* какой сустав нашёлся и нашёлся ли, и какого вида риг;
* сколько суставов привязалось из скольких;
* для опубликованных клипов — `AnimationId`, `Length` после `Play()`, и что `MISSING`.

Хорошие образцы из проекта:

```
[DiverSystem] movement tracks: walk=OK  jump=OK  swim=OK  revive=OK  throw=MISSING
[CrewClips] Pirate_Bosun: привязано суставов 0 из 6. Motor6D в модели: НЕТ НИ ОДНОГО (риг не R6?)
[CrewClips] суставы доехали (6 из 6) — анимация пошла
[Питьё] риг R15 | найдено: Head, RightHand, RightLowerArm, RightUpperArm | не найдено: —
```

---

## 8. Чек-лист

- [ ] Какого вида риг у цели — `AnimationConstraint`, `Motor6D` или `Bone`?
- [ ] Пишу в `Transform`, а не в `C0`?
- [ ] `BindToRenderStep` с приоритетом `Character + 1`, а не `RenderStepped`?
- [ ] Для физического рига повторяю в `Stepped`?
- [ ] Множитель поворота слева от базовой позы?
- [ ] Слепок базовой позы снимается только когда движения нет?
- [ ] Финал соответствует стилю: поверх — не пишу; заменял — вернул `identity` один раз?
- [ ] Клип опубликованный → проверил `Length > 0`, а не только `track ~= nil`?
- [ ] Держу позу только `Play`/`Stop`, без `AdjustSpeed`?
- [ ] Кручу суставы на клиенте, а собираю на сервере?
- [ ] Риг собран ДО перемещения модели?
- [ ] Есть строка в лог, по которой видно, что именно нашлось и загрузилось?
- [ ] `rojo build default.project.json -o <scratch>/build_check.rbxl` проходит?

Помни: `rojo build` **не проверяет синтаксис Luau** и не запускает код. Зелёная сборка
означает только то, что файлы разложились по местам.
