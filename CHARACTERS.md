# Персонажи и анимации без публикации — на примере коровы

Как в этом проекте устроен зверь с анимацией: от модели в Blender до качающегося
хвоста на острове. Всё ниже сверено с кодом; у каждого шага указан файл. Общие
правила про анимации (что реплицируется, что нет, чем анимировать игрока) лежат в
[ANIMATIONS.md](ANIMATIONS.md) — прочитай его первым.

---

## 0. Идея в трёх строках

1. **Модель — набор отдельных MeshPart**, по одной детали на «кость». Никаких
   скиннед-мешей и арматур: у скиннед-меша один коллайдер, который спорит с каждым
   суставом (прошлая корова этим болела).
2. **Суставы (Motor6D) собирает скрипт при спавне**, а не Studio. Риг идемпотентный:
   его можно звать на каждом клоне.
3. **Анимации — таблицы Lua** (CFrame на сустав на кадр), их крутит **клиентский**
   проигрыватель прямо в `Motor6D.Transform`. Публиковать ничего не нужно, поэтому
   всё работает и в неопубликованном плейсе, и у любого владельца.

Файлы коровы:

| Что | Где |
|---|---|
| Сборка рига | [CowRig.lua](src/ReplicatedStorage/CowRig.lua) |
| Клипы (данные) | [CowClips.lua](src/ReplicatedStorage/CowClips.lua) |
| Проигрыватель | [CowAnimator.lua](src/ReplicatedStorage/CowAnimator.lua) |
| Конфиг зверя | [PirateIslandDefs.lua](src/ReplicatedStorage/PirateIslandDefs.lua) (`ANIMALS`, `ANIMAL_LIFE`) |
| Спавн и сборка рига на сервере | [PirateIsland.server.lua](src/ServerScriptService/PirateIsland.server.lua) (`spawnAnimals`, `ANIMAL_RIGS`) |
| Поведение (что играть) | [AnimalLife.server.lua](src/ServerScriptService/AnimalLife.server.lua) |
| Проигрывание на клиенте | [PirateIslandAnim.client.lua](src/StarterPlayerScripts/PirateIslandAnim.client.lua) |

Второй такой же зверь — курица: [ChickenRig.lua](src/ReplicatedStorage/ChickenRig.lua),
[ChickenRigData.lua](src/ReplicatedStorage/ChickenRigData.lua),
[ChickenAnimator.lua](src/ReplicatedStorage/ChickenAnimator.lua). У неё точки суставов
заданы в студах (сгенерированы скриптом `chicken.py`), у коровы — долями от размера
детали. Оба способа рабочие, ниже разобран коровий.

---

## 1. Модель: Blender → Studio

### 1.1. Как резать

Одна деталь на сустав. У коровы семь: `Torso`, `Head`, `LegFL`, `LegFR`, `LegRL`,
`LegRR`, `Tail`. Дерево суставов:

```
HumanoidRootPart --RootJoint--> Torso
    Torso --Neck--------------> Head
    Torso --HipFL / HipFR-----> LegFL / LegFR
    Torso --HipRL / HipRR-----> LegRL / LegRR
    Torso --TailJoint---------> Tail
```

Требования к мешам:

- каждая деталь — отдельный объект в Blender со своим именем (имена станут именами
  MeshPart, по ним ищет риг);
- все детали стоят в **авторской стойке** (rest pose) в одном общем пространстве —
  риг снимает точки суставов с текущих позиций деталей;
- центр детали не важен: Roblox при импорте всё равно центрирует меш по его
  bounding box, поэтому точки суставов задаются **долями от Size** (см. 2.1);
- масштаб: корова импортирована со **Scale 0.01**. Это влияет на клипы (см. 3.2).

### 1.2. Импорт

Import 3D → одна модель. Результат должен быть `Model` с именем `Cow`, внутри
семь `MeshPart` с именами из дерева выше. Никаких костей, никакого `Humanoid` из
импорта (Humanoid сюда не нужен вовсе: зверя водит свой FSM, а не Humanoid).

Положить модель в `ReplicatedStorage` (можно во вложенную папку — спавнер ищет по
имени модели и обязательной детали, см. `findAnimalTemplate` в
[PirateIsland.server.lua](src/ServerScriptService/PirateIsland.server.lua)).

Шаблон **не** трогать руками после импорта: не переставлять детали, не менять
их размер. Риг строится по позе шаблона.

---

## 2. Риг: CowRig

### 2.1. Точки крепления

[CowRig.lua](src/ReplicatedStorage/CowRig.lua), таблица `ATTACH`: для каждой
детали три доли `{x, y, z}` от её `Size`, где сустав сидит относительно центра
детали. Например `LegFL = {0, 0.5, 0}` — сустав в верхней грани ноги; `Head`
— чуть ниже центра и ближе к торсу.

Доли берутся из `cow.json` — файла, который отдаёт пайплайн вместе с FBX
(расположение суставов в единицах модели, делённое на размеры деталей). Перегенерировал
меш — сверь доли с новым json, иначе ноги повиснут в воздухе.

Как это превращается в сустав (там же, `CowRig.setup`):

```lua
local at = part.CFrame * CFrame.new(part.Size.X * fx, part.Size.Y * fy, part.Size.Z * fz)
local m = Instance.new("Motor6D")
m.Part0 = torso
m.Part1 = part
m.C0 = torso.CFrame:Inverse() * at   -- точка сустава в осях торса
m.C1 = part.CFrame:Inverse() * at    -- та же точка в осях детали
```

`RootJoint` связывает невидимый `HumanoidRootPart` (создаётся скриптом, 0.9 от
торса) с торсом; `model.PrimaryPart` — именно корень.

### 2.2. Физика деталей

- `Torso`: `Anchored = false`, `CanCollide = true` — единственная тяжёлая деталь;
- всё остальное: `CanCollide = false`, `Massless = true` — невесомые конечности не
  разбалтывают шарнирную тушку.

### 2.3. Идемпотентность

`setup` сначала сносит все `Motor6D`/`Weld`/`WeldConstraint` в модели, потом строит
заново. Поэтому его можно звать на каждом клоне и повторно.

**Порядок при спавне** (см. `spawnAnimals`): клонировать шаблон → **сначала**
`CowRig.setup(npc)` → и только потом ставить модель на маркер (`PivotTo`). Наоборот
нельзя: риг снимает точки с текущей позы, и если детали уже переставлены, суставы
соберутся криво.

---

## 3. Клипы: CowClips

### 3.1. Формат

[CowClips.lua](src/ReplicatedStorage/CowClips.lua) — модуль, возвращающий таблицу:

```lua
return {
	["Walk"] = { fps = 30, loop = true, keys = {
		{ t = 0,       p = { Torso = {12 чисел}, Head = {12 чисел}, LegFL = {…}, … } },
		{ t = 0.03333, p = { … } },
		…
	} },
	["ShockRun"] = { fps = 30, loop = false, keys = { … } },
}
```

- `t` — секунды от начала клипа;
- `p` — поза: ключ — **имя детали** (не сустава), значение — 12 чисел
  `{px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22}`: сдвиг и матрица
  поворота относительно **позы покоя** этого сустава (это и есть `Motor6D.Transform`);
- `loop = true` — цикл (Walk, Run, IdleGraze), `false` — разовый (ShockRun, JumpFly).

У коровы шесть клипов: `Walk`, `Run`, `ShockRun`, `JumpFly`, `IdleGraze`, `IdleWalk`.

### 3.2. Единицы

Сдвиг хранится **в единицах рига**: 100 = 1 студ. Проигрыватель умножает на
`POS_SCALE = 0.01` ([CowAnimator.lua](src/ReplicatedStorage/CowAnimator.lua)), потому
что меш импортирован со Scale 0.01. Импортируешь новую модель в масштабе 1.0 —
ставь `POS_SCALE = 1.0`, иначе торс будет подпрыгивать на сантиметр вместо метра.

### 3.3. Откуда берутся числа

В Blender анимируется арматура **той же топологии** (кость на деталь). Экспортный
скрипт (в заголовке CowClips назван `BuildCowAnimations.luau`) на каждом кадре
берёт локальную трансформацию кости относительно rest pose и пишет её как 12 чисел
для соответствующей детали. Правила, без которых клип не ляжет на риг:

1. **Кость = деталь**, имена совпадают с MeshPart.
2. **Rest pose кости = стойка, в которой детали импортированы.** Transform считается
   от неё; если в Blender стойка одна, а в Studio другая, вся анимация уедет.
3. Трансформация **локальная** (относительно родительской кости), не мировая.
4. Частота 30 fps; проигрыватель интерполирует между ключами, так что можно и
   реже, если поза меняется плавно.
5. Оси: Roblox правосторонняя система, Y вверх; экспорт должен конвертировать из
   Blender (Z вверх). Проверка простая: клип `Walk` — ноги ходят вперёд-назад по
   оси Z детали, торс покачивается по Y.

Клипы **не** нужно публиковать, `Animation`-ассеты не участвуют. Заодно это значит,
что клип принадлежит проекту, а не аккаунту загрузившего.

---

## 4. Проигрыватель: CowAnimator

Интерфейс ([CowAnimator.lua](src/ReplicatedStorage/CowAnimator.lua)):

```lua
local anim = CowAnimator.new(motors)   -- motors: { Torso = Motor6D, Head = Motor6D, … }
anim:play("Walk", 0.12, 1.0)           -- клип, кроссфейд (с), скорость
anim:step(dt)                          -- каждый кадр (RenderStepped на клиенте)
anim.finished                          -- true, когда разовый клип доиграл
anim:stop()                            -- Transform → identity
```

Ключи словаря `motors` — те же имена деталей, что в `p` у клипов. Соответствие
имени детали имени сустава задано на клиенте
([PirateIslandAnim.client.lua](src/StarterPlayerScripts/PirateIslandAnim.client.lua),
`ANIMAL_MOTORS`):

```lua
Cow = { Torso = "RootJoint", Head = "Neck", LegFL = "HipFL", LegFR = "HipFR",
        LegRL = "HipRL", LegRR = "HipRR", Tail = "TailJoint" }
```

Кроссфейд: при смене клипа проигрыватель запоминает текущие `Transform` и за
`fadeTime` доводит их до нового клипа — без рывка. Разовый клип, дойдя до конца,
поднимает `finished`; клиентский адаптер по нему возвращает цикл.

---

## 5. Как это подключено в игре

### 5.1. Конфиг зверя

[PirateIslandDefs.lua](src/ReplicatedStorage/PirateIslandDefs.lua):

- `ANIMALS` — точки на острове (маркер `Pt_Cow_1` и т. д.): какую модель ставить,
  каким ригом собирать, какая деталь обязательна (`mustHave`), радиус выпаса.
- `ANIMAL_LIFE.Cow` — поведение: скорости, дистанции испуга, и главное —
  **карта состояний в клипы**:

```lua
clips = { Idle = "IdleGraze", Eat = "IdleGraze", Walk = "Walk", Run = "Run", React = "ShockRun" },
reactLen = 1.40,   -- длина разового клипа React: на неё встаёт таймер состояния
```

Сервер оперирует **абстрактными** состояниями (`Idle`, `Walk`, `React`), клиент
переводит их в имена клипов по этой карте. Так один FSM обслуживает и корову, и
курицу с разными наборами клипов.

### 5.2. Сервер: спавн и поведение

- `spawnAnimals` ([PirateIsland.server.lua](src/ServerScriptService/PirateIsland.server.lua)):
  клон → `ANIMAL_RIGS[cfg.rig].setup(npc)` → атрибуты `AnimalRig`, `GrazeRadius`,
  `HomeX/HomeZ` → постановка на маркер.
- [AnimalLife.server.lua](src/ServerScriptService/AnimalLife.server.lua) двигает
  тушу (`HumanoidRootPart` по рельефу) и **только ставит атрибуты**:
  - `Clip = "Walk"` — текущий цикл;
  - `ClipOnce = "React"`, `ClipOnceT = серверное время` — разовая реакция.

  Никаких `Transform` на сервере: они не реплицируются (см. ANIMATIONS.md).

### 5.3. Клиент: проигрывание

[PirateIslandAnim.client.lua](src/StarterPlayerScripts/PirateIslandAnim.client.lua)
следит за моделями с атрибутом `AnimalRig`, собирает словарь суставов по
`ANIMAL_MOTORS` (перепроверяя раз в секунду — суставы могут доехать по сети позже
модели), создаёт `CowAnimator` и каждый кадр:

- читает `Clip` → `anim:play(clipsMap[state])` как цикл;
- читает `ClipOnce` + `ClipOnceT` → играет разово, по `finished` возвращает цикл;
- мёртвых не анимирует.

---

## 6. Чек-лист: добавить нового зверя (например, свинью)

1. **Модель**: детали-«кости» с именами, авторская стойка, импорт в `Model`
   с именем `Pig`, положить в `ReplicatedStorage`.
2. **Риг**: скопировать `CowRig.lua` в `PigRig.lua`; заполнить `ATTACH` (доли из
   json пайплайна) и `JOINT_NAME`; имя корневой детали (`Torso`) поправить, если
   иное.
3. **Клипы**: экспортировать `PigClips.lua` в формате из п. 3.1; проверить
   масштаб (`POS_SCALE`).
4. **Проигрыватель**: скопировать `CowAnimator.lua` в `PigAnimator.lua`, заменить
   `require(... "CowClips")` и `POS_SCALE`. Логику не трогать.
5. **Defs**: в `ANIMALS` добавить точку с `model = "Pig", rig = "Pig", mustHave = "Torso"`;
   в `ANIMAL_LIFE.Pig` — скорости и `clips = { Idle = …, Walk = …, Run = …, React = … }`,
   `reactLen`. На остров положить маркер `Pt_Pig_1`.
6. **Сервер**: в `PirateIsland.server.lua` добавить `Pig = PigRig` в `ANIMAL_RIGS`.
7. **Клиент**: в `PirateIslandAnim.client.lua` добавить `Pig` в `ANIMAL_MOTORS`
   (деталь → сустав) и в `ANIMAL_PLAYER`.
8. **Проверка в живой игре, не только в Play Solo**: в Solo сервер и клиент — один
   процесс, и ошибка «сервер крутит Transform» там не видна.

Типовые поломки и их признаки:

| Признак | Причина |
|---|---|
| Зверь стоит столбом, в логе тихо | клиент не нашёл суставы: имена в `ANIMAL_MOTORS` не совпали с `JOINT_NAME` рига |
| Ноги висят рядом с телом | `ATTACH` не от этого меша (перегенерировали модель, не сверили json) |
| Торс прыгает на метры или еле шевелится | `POS_SCALE` не совпадает с масштабом импорта |
| Клип играет «в другую сторону» | экспорт не сконвертировал оси Blender → Roblox |
| Туша разлетается после разанкоривания | конечности не `Massless`/`CanCollide=false`, или суставы собраны после `PivotTo` |
| Реакция обрывается циклом | `reactLen` короче реального клипа: FSM вернул `Clip` раньше, чем клиент дождался `finished` |

---

## 7. Можно ли так сделать R15?

Коротко: **для НПС — да, тем же приёмом; для персонажа игрока — нет, там другой риг.**

### 7.1. НПС на R15

R15 — это те же 15 `MeshPart` на `Motor6D` (`Neck`, `Waist`, `LeftShoulder`,
`RightHip`, …), только суставы уже собраны Roblox (Rig Builder или импорт с
арматурой R15). Значит, можно:

- собрать риг Rig Builder'ом (или взять свою модель с теми же именами деталей и
  суставов), **`Humanoid` оставить** (даёт ходьбу, здоровье, ragdoll), но
  **выключить `Animate`** — иначе он каждый кадр перезаписывает `Transform` своими
  анимациями и будет спорить с нашим проигрывателем;
- экспортировать клипы в тот же формат `{ fps, loop, keys = { { t, p = { Деталь = 12 чисел } } } }`,
  где ключи `p` — имена деталей R15 (`LowerTorso`, `LeftUpperArm`, …), а
  `ANIMAL_MOTORS`-подобная карта переводит их в имена суставов (`Waist`, `LeftShoulder`…);
- проигрывать на клиенте так же, как корову. Пираты и экипаж уже живут именно так,
  только на R6: [CrewClips.lua](src/ReplicatedStorage/CrewClips.lua) и
  [PirateCrewClips.lua](src/ReplicatedStorage/PirateCrewClips.lua). Для R15
  меняются только имена суставов и число треков.

Ограничения: `Humanoid` в R15 сам двигает `HumanoidRootPart` и держит высоту
`HipHeight`; корневой сустав (`RootJoint`/`Root`) лучше не анимировать по
позиции, только остальные. И на сервере по-прежнему **ничего не крутить** — сервер
собирает и ставит атрибуты, клиенты играют.

### 7.2. Персонаж игрока

У персонажа игрока в этом проекте **нет ни одного `Motor6D`**: это новый
физический риг Roblox — `BallSocketConstraint` + `AnimationConstraint`, поза
задаётся целевым `Transform` у `AnimationConstraint` (см. ANIMATIONS.md, п. 0, и
[MapItem.client.lua](src/StarterPlayerScripts/MapItem.client.lua)). Клипы коровы
на него не лягут напрямую, потому что сустав другого класса.

Что для игрока работает:

- **поза кодом** — образец [HammerSwing.client.lua](src/StarterPlayerScripts/HammerSwing.client.lua);
- **опубликованная анимация** (`Animator:LoadAnimation`) — только если ассет
  принадлежит владельцу игры;
- таблицы клипов в принципе можно проиграть и в `AnimationConstraint.Transform`
  (та же идея: целевой CFrame сустава относительно покоя), но проигрыватель для
  этого придётся написать отдельно — `CowAnimator` пишет в `Motor6D.Transform`.

Итого: пайплайн «модель из деталей → скрипт собирает суставы → клипы таблицами →
клиент играет» переносится на R15-НПС почти без изменений, а для персонажа
игрока остаются позы кодом и опубликованные анимации.
