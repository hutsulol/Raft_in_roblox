-- QuestCatalog.server.lua
-- Static, read-only catalog of every quest in the game. Built up
-- across C1 → C5 (this file) and read by QuestState.server.lua
-- (lands in C6). Published on _G.QuestCatalog so the rest of the
-- server can iterate it without re-requiring a module.
--
-- C1 (this commit): empty scaffold + shape comment. The actual quest
-- entries land in C2 (story #1), C3 (story #2), C4 (4 dailies), and
-- C5 (4 timed challenges).
--
-- Quest entry shape (every entry must conform):
--   {
--     id        = "string",                     -- unique key (DataStore-stable)
--     kind      = "story" | "daily" | "challenge",
--     title     = "string",                     -- shown on the quest card
--     body      = "string",                     -- one-line description
--     icon      = "rbxassetid://...",           -- card icon
--     objectives = {                            -- 1+ entries; multi only for story
--         { eventType = "resource:Log", goal = 10, label = "Chop logs" },
--         ...
--     },
--     reward    = { kind = "resource"|"item", name = "Log", count = 10 },
--     durationSec = 30,                          -- challenges only; nil otherwise
--     permanent = true,                          -- when true, completion sticks
--                                                -- across rerolls (story + craft
--                                                -- gates use this); see C4 for
--                                                -- the workbench dedup case.
--   }

local catalog = {}

-- ═══ БЕТА-ТЕСТ: в игре ТОЛЬКО онбординг-квест ═══
-- Сюжет, ежедневные и испытания временно не регистрируются (блок if ниже).
-- Для возврата всего каталога поставь false.
local BETA_ONLY_ONBOARDING = true

-- C2 onward writes into `catalog` via the helpers below. Doing it
-- through helpers (instead of inline table construction) gives us a
-- single place to validate shape if/when a quest is mistyped.

--[[ ⚠️ ШАГ С ПОМЕТКОЙ shared ЗАСЧИТЫВАЕТСЯ ВСЕЙ КОМПАНИИ, А НЕ ОДНОМУ.
     Ставится там и только там, где цель существует в ЕДИНСТВЕННОМ экземпляре на
     весь плот: гарнизон аванпоста, корова стартового острова, монолит,
     очиститель, поле заразы, сам плот. Без этого выходил тупик: пиратов двое,
     одного убил хозяин, второго друг — у каждого 1 из 2, а убивать больше
     некого, гарнизон кончился.
     НЕ ставится на крафт и на сбор ресурсов: они личные и лежат в рюкзаке. Друг
     скрафтил кружку — квест закрылся бы у обоих, а пить второму не из чего.
     Раздачу делает QuestState.onQuestEvent, там же и оговорки. ]]
local function addQuest(entry)
	assert(type(entry.id) == "string" and entry.id ~= "", "quest id required")
	assert(catalog[entry.id] == nil, "duplicate quest id: " .. entry.id)
	assert(type(entry.objectives) == "table" and #entry.objectives > 0,
		"quest " .. entry.id .. " needs at least one objective")
	catalog[entry.id] = entry
end

-- ─── ОНБОРДИНГ-квест #0 — First Timber (самый первый) ───────────────
-- Обучающий квест: выловить 3 бревна из океана. Пока он не закрыт,
-- QuestState показывает в списке ТОЛЬКО его и принудительно держит его
-- отслеживаемым (см. buildSnapshot). Кнопка «?» на HUD-трекере включает
-- подсветку брёвен в океане (TrackerCard.client).
addQuest({
	id    = "onboarding_logs",
	kind  = "story",
	title = "Первое дерево",
	body  = "Выловите 3 бревна из океана.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "resource:Log", goal = 3, label = "Собери брёвна" },
	},
	-- награда 3 камня; иконка уходит и в меню квестов, и в RewardReveal при выдаче
	reward = { kind = "resource", name = "Stone", count = 3, icon = "rbxassetid://96450657403376" },
	permanent = true,
})

-- ─── ОНБОРДИНГ-квест #0.5 — Расширение плота ────────────────────────
-- Приходит сразу после «Первой древесины»: игрок только что натаскал брёвен, и
-- первое, на что их тратят, — своя площадь. Мысль «что-то тут тесно» и
-- уведомление о новом квесте шлёт QuestState в момент закрытия предыдущего.
--
-- ⚠️ ДВЕ ЦЕЛИ, ПОТОМУ ЧТО ШАГА ДВА И ВТОРОЙ БЕЗ ПЕРВОГО НЕВОЗМОЖЕН.
-- Клетку пола ставят ТОЛЬКО молотком; без него игрок будет ходить по плоту и
-- искать, куда нажать. Событие built:RaftFloor шлёт BuildingSystem там же, где
-- клетка приваривается к плоту.
addQuest({
	id    = "onboarding_raft",
	kind  = "story",
	title = "Расширение плота",
	body  = "На плоту стало тесно. Собери молоток и пристрой новую клетку пола.",
	icon  = "rbxassetid://86264127232874",   -- иконка молотка из крафта
	objectives = {
		{ eventType = "crafted:Hammer",   goal = 1, label = "Скрафти молоток" },
		{ eventType = "built:RaftFloor",  goal = 1, label = "Поставь новую клетку плота", shared = true },
	},
	-- ⚠️ НАГРАДА — СВЁКЛА, И ЭТО НЕ УКРАШЕНИЕ.
	-- Ею открывается следующий квест: посадить её на грядку. Семян свёклы в
	-- начале игры взять негде, так что без этой награды задание было бы
	-- невыполнимым. Меняешь награду — меняй и следующий квест.
	reward = { kind = "resource", name = "Beet", count = 2, icon = "rbxassetid://80108091374305" },
	permanent = true,
	gated = true,   -- открывается по закрытию «Первой древесины»
})

-- ─── ОНБОРДИНГ-квест #0.6 — Свой огород ─────────────────────────────
-- Приходит следом за расширением плота: игрок получил свёклу в награду и теперь
-- узнаёт, что её можно не съесть, а посадить.
-- Событие planted:Beet шлёт GardenSystem в момент посадки — по имени семени,
-- чтобы картофель не закрывал задание про свёклу.
addQuest({
	id    = "onboarding_beet",
	kind  = "story",
	title = "Свой огород",
	body  = "Свёклу можно не есть, а посадить. Вылови из океана компост, скрафти грядку (4 дерева и 3 компоста), поставь её и посади свёклу.",
	icon  = "rbxassetid://80108091374305",
	objectives = {
		-- Метка КОРОТКАЯ: она едет на HUD-трекер, а там строка обрезается многоточием
		-- («Посади свёклу на…»). Куда сажать, объясняет подсказка по «?».
		{ eventType = "planted:Beet", goal = 1, label = "Посади свёклу", shared = true },
	},
	reward = { kind = "resource", name = "Leaves", count = 8, icon = "rbxassetid://96691360298069" },
	permanent = true,
	gated = true,   -- открывается по закрытию «Расширения плота»
})

-- ─── Квест «Место для вещей» — по первому переполнению рюкзака ───────
-- Открывает StorageQuestWatcher.server.lua: InventoryManager помечает игрока
-- атрибутом InventoryFullOnce, когда рюкзак впервые забит (или что-то в него
-- уже не влезло), сторож даёт мысль StorageThought и выдаёт этот квест.
addQuest({
	id    = "storage_box",
	kind  = "story",
	title = "Место для вещей",
	body  = "В рюкзаке нет места. Скрафти малый контейнер (вкладка «Разное», 6 дерева), поставь его на плот и переложи в него лишнее.",
	icon  = "rbxassetid://86632287242518",   -- иконка малого контейнера из крафта
	objectives = {
		{ eventType = "crafted:SmallContainer", goal = 1, label = "Скрафти малый контейнер" },
		-- шлёт SmallContainerSystem при постановке (placeSmallContainer)
		{ eventType = "placed:SmallContainer",  goal = 1, label = "Поставь контейнер на плот", shared = true },
		-- шлёт SmallContainerSystem при укладке предмета (put)
		{ eventType = "stored:Container",       goal = 1, label = "Положи в него предмет", shared = true },
	},
	reward = { kind = "resource", name = "Plastic", count = 4, icon = "rbxassetid://132919988751848" },
	permanent = true,
	gated = true,   -- открывается по первому переполнению рюкзака
})

-- ─── ОНБОРДИНГ-квест #1 — Fresh Water (второй) ──────────────────────
-- Обучающий квест про воду: скрафтить Кружку (Cup, Misc, 2 пластика) и
-- Очиститель воды (Destitalor, Technology, 4 пластика) в инвентарном
-- крафте, затем залить в установленный очиститель морскую воду.
-- Появляется в списке ПОСЛЕ закрытия First Timber (см. buildSnapshot в
-- QuestState.server.lua) и автоматически отслеживается, пока игрок не
-- трекает что-то другое. Кнопка «?» на HUD-трекере включает пошаговую
-- подсказку с подсветкой UI (PurifierQuestHint.client.lua): кнопка
-- инвентаря → вкладка категории → строка рецепта → установка/заливка.
-- Событие purifier:filled шлёт ThirstSystem.server.lua (fillPurifier).
addQuest({
	id    = "onboarding_purifier",
	kind  = "story",
	title = "Пресная вода",
	body  = "Скрафти кружку и очиститель, залей морскую воду — и пусти её в дело.",
	icon  = "rbxassetid://90221080738714",
	-- ПОСЛЕДНЯЯ ЦЕЛЬ — ГЛОТОК, а не заливка. Смысл цепочки в том, чтобы утолить
	-- жажду, а между заливкой очистителя и глотком ещё два действия: дождаться
	-- очистки и набрать воду в кружку. Раньше квест закрывался на заливке, и
	-- награда выдавалась игроку с полным очистителем и пустой шкалой жажды.
	-- Событие purifier:drank шлёт ThirstSystem.server.lua (action "drink").
	objectives = {
		{ eventType = "crafted:Cup",        goal = 1, label = "Скрафти кружку" },
		{ eventType = "crafted:Destitalor", goal = 1, label = "Скрафти очиститель воды" },
		{ eventType = "purifier:filled",    goal = 1, label = "Залей морскую воду в очиститель", shared = true },
		-- ⚠️ ПОСЛЕДНЯЯ ЦЕЛЬ ЗАКРЫВАЕТСЯ И ГЛОТКОМ, И ПОЛИВОМ.
		-- Раньше здесь стоял только глоток, и в связке с огородом выходила
		-- путаница: очиститель открывает ПОЛИВ грядки (поливать нечем), а квест
		-- при этом требовал воду ВЫПИТЬ — то есть извести ровно то, за чем игрок
		-- и пришёл. Событие purifier:used шлют оба места: ThirstSystem по глотку и
		-- PlanterService по поливу. Что игроку нужнее сейчас — решает подсказка
		-- (PurifierQuestHint), она смотрит, стоит ли на плоту сухая грядка.
		{ eventType = "purifier:used",      goal = 1, label = "Выпей воду или полей грядку", shared = true },
	},
	-- возврат потраченного пластика (2 на кружку + 4 на очиститель)
	reward = { kind = "resource", name = "Plastic", count = 6, icon = "rbxassetid://132919988751848" },
	permanent = true,
	-- ⚠️ ПОЯВЛЯЕТСЯ ПО ЖАЖДЕ, А НЕ СРАЗУ ПОСЛЕ ПЕРВОГО КВЕСТА.
	-- Открывает ThirstThought.client, когда шкала впервые падает ниже 20%: там же
	-- игрок думает «во рту пересохло». До этого совет крафтить очиститель
	-- беспричинен — пить ещё не хочется.
	gated = true,
})

-- ─── ОНБОРДИНГ-квест #2 — Ночлег ────────────────────────────────────
-- Появляется, когда игрока застала первая ночь: BedThought.client играет
-- мысль «нужна кровать» и переключает трекер сюда.
--
-- ⚠️ БЫЛО ДВЕ ЦЕЛИ, СТАЛА ОДНА.
-- Кровать крафтилась не в инвентаре, а в меню верстака, и только если верстак
-- уже стоял на плоту в 15 студах: без первого шага второй был физически
-- недоступен, поэтому верстак и был отдельной целью. Станцию убрали, кровать
-- переехала в обычный крафт (InventoryCrafting) — и первая цель превратилась бы
-- в задание собрать предмет, которого больше нет в списке. Осталась кровать.
--
-- Событие crafted:Bed шлёт теперь общий хук крафта InventoryCrafting.server.lua,
-- а не собственный обработчик кровати: своего у неё больше нет.
addQuest({
	id    = "onboarding_bed",
	kind  = "story",
	title = "Ночлег",
	body  = "На голых досках ночь не пережить. Собери лежанку: 5 брёвен и 3 листвы.",
	icon  = "rbxassetid://97461315404202",   -- иконка лежанки из инвентаря
	objectives = {
		{ eventType = "crafted:Bed", goal = 1, label = "Скрафти лежанку" },
	},
	-- возврат части потраченного на кровать
	reward = { kind = "resource", name = "Log", count = 5, icon = "rbxassetid://116178347748793" },
	permanent = true,
	-- ⚠️ ПОЯВЛЯЕТСЯ ПО СОБЫТИЮ, А НЕ СРАЗУ.
	-- До первой ночи игрок про ночлег и не думает; список квестов, забитый
	-- заданиями на будущее, читается как «всё уже открыто».
	gated = true,
})

-- ─── ОНБОРДИНГ-квест #3 — Водолаз ───────────────────────────────────
-- Появляется через два дня после того, как игрок растолкал механика, и только
-- если монолит ещё не починен: DiverQuestWatcher.server следит за обоими
-- условиями и сам ставит квест на трекер.
--
-- ⚠️ ЦЕЛЬ ОДНА, И ОНА НЕ «ПОДОЙДИ», А «ПОЧИНИ».
-- Разбудить водолаза можно ровно одним способом — восстановить его монолит
-- (MonolithRepair). Событие monolith:repaired шлётся оттуда же, где списываются
-- брёвна с листьями, чтобы засчитывалось именно завершение, а не подход к окну.
-- Кнопка «?» на трекере подсвечивает сам монолит (DiverQuestHint.client).
addQuest({
	id    = "onboarding_diver",
	kind  = "story",
	title = "Водолаз",
	body  = "Он лежит у монолита и не встаёт. Почини монолит — и водолаз придёт в себя.",
	icon  = "rbxassetid://90221080738714",
	objectives = {
		{ eventType = "monolith:repaired", goal = 1, label = "Почини монолит водолаза", shared = true },
	},
	reward = { kind = "resource", name = "Plastic", count = 8, icon = "rbxassetid://132919988751848" },
	permanent = true,
	-- открывает DiverQuestWatcher: два дня после механика и монолит ещё цел
	gated = true,
})

-- ─── СТАРТОВЫЙ ОСТРОВ — цепочка из трёх ─────────────────────────────
-- Поднимается на второй день, на 30% дня (StartIsleStory.server.lua): катсцена,
-- мысль «земля!», и сразу первый квест. Дальше звенья открывает CHAIN.
--
-- ⚠️ ЭТИ ТРИ ЖИВУТ ВЫШЕ BETA_ONLY_ONBOARDING НАМЕРЕННО.
-- Всё, что ниже флага, в бете не регистрируется вовсе — а сцена с островом идёт
-- сразу за онбордингом и должна работать именно в бете.
addQuest({
	id    = "startisle_scout",
	kind  = "story",
	title = "Земля по курсу",
	body  = "На горизонте показался остров. Дойди до него и сойди на берег.",
	icon  = "rbxassetid://96691360298069",   -- листва: зелень = суша
	objectives = {
		-- шлёт StartIsleStory.server.lua, когда игрок реально стоит НА острове
		-- (луч под ноги, а не расстояние до центра: с плота рядом не считается)
		{ eventType = "reached:StartIsle", goal = 1, label = "Сойди на остров" },
	},
	reward = { kind = "resource", name = "Log", count = 4, icon = "rbxassetid://116178347748793" },
	permanent = true,
	-- открывает StartIsleStory сразу после катсцены: до появления острова квест
	-- «дойди до острова» читался бы как издевательство
	gated = true,
})

addQuest({
	id    = "startisle_cow",
	kind  = "story",
	title = "Дикая корова",
	body  = "На острове пасётся корова. Добудь её и подбери мясо с туши.",
	icon  = "rbxassetid://140237721809215",   -- сырое мясо из инвентаря
	-- ⚠️ ДВЕ ЦЕЛИ: УБИТЬ И ПОДОБРАТЬ.
	-- С одной только смертью квест закрывался в момент удара, и следом играла
	-- мысль «мясо есть» — при том что мясо в эту секунду лежало на траве, а у
	-- игрока в руках был топор. Подбор — отдельный шаг: с туши падает кусок,
	-- светится, игрок его поднимает, и вот тогда мясо действительно есть.
	objectives = {
		-- шлёт StartIsle.server.lua по смерти коровы острова
		{ eventType = "kill:Cow",      goal = 1, label = "Убей корову", shared = true },
		-- шлёт подбор дропа с туши (AnimalLife.server.lua, ProximityPrompt)
		{ eventType = "resource:Meat", goal = 1, label = "Подбери мясо", shared = true },
	},
	reward = { kind = "resource", name = "Leaves", count = 6, icon = "rbxassetid://96691360298069" },
	permanent = true,
	gated = true,
})

addQuest({
	id    = "startisle_meat",
	kind  = "story",
	title = "Мясо на углях",
	body  = "Сырое мясо есть нельзя. Собери мангал, разожги его бревном и пожарь кусок.",
	icon  = "rbxassetid://110578314998395",   -- жареное мясо
	objectives = {
		-- шлёт GrillSystem.server.lua в момент, когда игрок СНИМАЕТ готовое
		-- с решётки: только там известно, кому засчитывать
		{ eventType = "cooked:Meat", goal = 1, label = "Пожарь мясо на мангале", shared = true },
	},
	reward = { kind = "resource", name = "Stone", count = 6, icon = "rbxassetid://96450657403376" },
	permanent = true,
	gated = true,
})

-- ⚠️ ЧЕТВЁРТОЕ ЗВЕНО ВЫДАЁТСЯ НЕ ВСЕГДА.
-- Если весло у игрока уже есть, задание «сделай весло» бессмысленно: событие
-- crafted:Paddle второй раз не придёт, и квест повис бы 1/1 навсегда. Поэтому
-- звено помечено в SKIP_IF_ALREADY_DONE (QuestState): при выдаче цепочка смотрит
-- на рюкзак и, если весло там, тихо пропускает квест целиком.
addQuest({
	id    = "startisle_paddle",
	kind  = "story",
	title = "Чем грести",
	body  = "Плот сам от берега не отойдёт. Собери весло — им плот можно править и разгонять.",
	icon  = "rbxassetid://93358108538106",   -- иконка весла из крафта
	objectives = {
		-- общий хук крафта: crafted:<имя рецепта> шлёт InventoryCrafting
		{ eventType = "crafted:Paddle", goal = 1, label = "Скрафти весло" },
	},
	-- возврат пластика: весло стоит 1 бревно и 3 пластика
	reward = { kind = "resource", name = "Plastic", count = 4, icon = "rbxassetid://132919988751848" },
	permanent = true,
	gated = true,
})

-- ─── ОСТРОВ-АВАНПОСТ — цепочка из четырёх ───────────────────────────
-- Поднимается через день после стартового (OutpostIsleStory.server.lua):
-- катсцена, мысль «тут кто-то есть», и сразу зачистка. Дальше звенья открывает
-- CHAIN, а последнее выдаёт сам повстанец при встрече — до разговора его не
-- существует.
--
-- ⚠️ ЭТИ ЧЕТЫРЕ, КАК И СТАРТОВЫЕ, ЖИВУТ ВЫШЕ BETA_ONLY_ONBOARDING.
-- Всё, что ниже флага, в бете не регистрируется вовсе, а сцена аванпоста идёт
-- сразу за стартовым островом и должна работать именно в бете.
addQuest({
	id    = "outpost_clear",
	kind  = "story",
	title = "Зачистить остров",
	body  = "Остров держат пираты: стрелок на левой вышке и охранник на правой. Перебей обоих.",
	icon  = "rbxassetid://92926554091794",   -- мачете
	objectives = {
		-- шлёт OutpostIsleStory.server.lua по смерти каждого из гарнизона: свой
		-- счётчик, а не общий pirate:kill, иначе квест закрыли бы пираты с катера
		{ eventType = "killed:OutpostPirate", goal = 2, label = "Перебей гарнизон", shared = true },
	},
	-- древесина под огнемёт: следующее звено просит два бревна
	reward = { kind = "resource", name = "Log", count = 6, icon = "rbxassetid://116178347748793" },
	permanent = true,
	gated = true,
})

addQuest({
	id    = "outpost_flamer",
	kind  = "story",
	title = "Огнемёт",
	body  = "Красная трава за частоколом — это зараза, и рубить её бесполезно. Собери огнемёт: 2 бревна, 3 мусора и пластиковая канистра.",
	icon  = "rbxassetid://115269318677272",   -- иконка огнемёта из крафта
	objectives = {
		-- общий хук крафта: crafted:<имя рецепта> шлёт InventoryCrafting
		{ eventType = "crafted:Flamethrower", goal = 1, label = "Скрафти огнемёт" },
	},
	reward = { kind = "resource", name = "Stone", count = 8, icon = "rbxassetid://96450657403376" },
	permanent = true,
	gated = true,
})

addQuest({
	id    = "outpost_burn",
	kind  = "story",
	title = "Выжечь заразу",
	body  = "Пройди грядки огнём. Пламя переходит с куста на куст — поджигать каждый вручную не нужно.",
	icon  = "rbxassetid://131695611244502",   -- факел
	objectives = {
		-- ⚠️ ЦЕЛЬ МЕНЬШЕ, ЧЕМ КУСТОВ НА ПОЛЕ (их двадцать), И ЭТО НАМЕРЕННО.
		-- Пожар ползёт сам, но пара кустов на отшибе может не заняться вовсе —
		-- при цели «все двадцать» квест повис бы на 18/20 навсегда. Это же число
		-- сценарий острова читает ОТСЮДА (BURN_GOAL в OutpostIsleStory), чтобы
		-- снять удержание зачистки ровно тогда же, когда закрывается квест.
		{ eventType = "burned:VirusCrop", goal = 12, label = "Сожги заражённые грядки", shared = true },
	},
	reward = { kind = "resource", name = "Plastic", count = 6, icon = "rbxassetid://132919988751848" },
	permanent = true,
	gated = true,
})

addQuest({
	id    = "outpost_islands",
	kind  = "story",
	title = "Освободить архипелаг",
	body  = "Повстанцы вернутся на острова, если их освободить. Зачисти ещё три — тогда откроются мастерские островов и лодки между ними.",
	icon  = "rbxassetid://96691360298069",   -- листва: зелень = суша
	objectives = {
		-- шлёт OutpostIsleStory.server.lua, когда IslandClearSystem объявляет
		-- зачищенным ЛЮБОЙ следующий остров
		{ eventType = "cleared:Island", goal = 3, label = "Зачисти острова", shared = true },
	},
	reward = { kind = "resource", name = "Log", count = 12, icon = "rbxassetid://116178347748793" },
	permanent = true,
	-- открывает не CHAIN, а разговор с повстанцем: до встречи задания нет
	gated = true,
})

-- ═══ СЮЖЕТ ТОРГОВЦА (MerchantStory.server) ═══════════════════════════
-- Все четыре — по событию (gated): квест ставит на трекер сам сюжет, у всех
-- игроков на плоту сразу. Цели общие (shared): сделал один — засчитано всем.

-- Подарок торговца на 3-й день: поставить рыбацкое место
addQuest({
	id    = "story_fishing_place",
	kind  = "story",
	title = "Подарок торговца",
	body  = "Торговец подарил рыбацкое место. Поставь его на клетку пола у края плота — впереди нужна вода.",
	icon  = "rbxassetid://97461315404202",
	objectives = {
		{ eventType = "placed:FishingSpot", goal = 1, label = "Поставь рыбацкое место", shared = true },
	},
	reward = { kind = "resource", name = "Log", count = 5, icon = "rbxassetid://116178347748793" },
	permanent = true,
	gated = true,
})

-- Первый житель: назначить его рыбаком (подсказки — TeamQuestHint.client)
addQuest({
	id    = "story_assign_fisher",
	kind  = "story",
	title = "Первый житель",
	body  = "Открой «Команду», выбери жителя и поставь его работать на рыбацкое место.",
	icon  = "rbxassetid://97461315404202",
	objectives = {
		{ eventType = "assigned:Fisher", goal = 1, label = "Назначь жителя рыбаком", shared = true },
	},
	reward = { kind = "resource", name = "Leaves", count = 6, icon = "rbxassetid://116178347748793" },
	permanent = true,
	gated = true,
})

-- Ферма от торговца: два участка и домик фермера
addQuest({
	id    = "story_farm_build",
	kind  = "story",
	title = "Своя ферма",
	body  = "Поставь два участка фермы (2×2 клетки пола), а вплотную к ним — домик фермера.",
	icon  = "rbxassetid://97461315404202",
	objectives = {
		{ eventType = "built:FarmBlock", goal = 2, label = "Поставь участки фермы", shared = true },
		{ eventType = "built:FarmerHut", goal = 1, label = "Поставь домик фермера", shared = true },
	},
	reward = { kind = "resource", name = "Compost", count = 6, icon = "rbxassetid://116178347748793" },
	permanent = true,
	gated = true,
})

-- Таверна: здесь собирают новых жителей
addQuest({
	id    = "story_tavern_build",
	kind  = "story",
	title = "Таверна",
	body  = "Поставь таверну на 2×2 клетки пола. Её мастера будут собирать новых жителей.",
	icon  = "rbxassetid://97461315404202",
	objectives = {
		{ eventType = "built:IslandHall", goal = 1, label = "Поставь таверну", shared = true },
	},
	reward = { kind = "resource", name = "Log", count = 8, icon = "rbxassetid://116178347748793" },
	permanent = true,
	gated = true,
})

if not BETA_ONLY_ONBOARDING then

-- ─── Story quest #1 — Lost in the Woods (C2) ───────────────────────
-- Early-game story arc: the player chops the path open, scavenges
-- the trash for raft mats, and crafts their first workbench. Three
-- objectives matching the user's reference design. Reward is a
-- single Woodcutter's Chest. Permanent so it never re-rolls.
addQuest({
	id    = "lostInTheWoods",
	kind  = "story",
	title = "Lost in the Woods",
	body  = "The path is blocked. Clear the way and find your way forward.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "resource:Log",       goal = 10, label = "Chop down trees" },
		{ eventType = "resource:Plastic",   goal = 15, label = "Collect pieces of trash" },
		{ eventType = "crafted:WorkBench",  goal = 1,  label = "Build a workbench" },
	},
	reward    = {
		kind  = "item",
		name  = "WoodcutterChest",
		label = "Woodcutter's Chest",
		icon  = "rbxassetid://82337855669175",
		count = 1,
		rare  = true, -- ЭПИЧЕСКАЯ награда: в меню квестов слот светится фиолетовым (QuestMenu)
	},
	permanent = true,
})

-- ─── Story quest #2 — Stranded Survivor (C3, placeholder) ──────────
-- Second story arc, focused on raft expansion + survival mechanics.
-- Final reward + balance numbers are provisional; the user can fine-
-- tune after testing. Same permanent contract as story #1 — never
-- re-rolls, never duplicates.
addQuest({
	id    = "strandedSurvivor",
	kind  = "story",
	title = "Stranded Survivor",
	body  = "The sea won't feed itself. Build out the raft and stockpile.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "crafted:WorkBench",  goal = 1,  label = "Craft a workbench" },
		{ eventType = "crafted:WallPanel",  goal = 4,  label = "Build wall panels" },
		{ eventType = "resource:Log",       goal = 50, label = "Stockpile logs" },
	},
	reward    = {
		kind  = "item",
		name  = "SurvivorChest",
		label = "Survivor's Chest",
		icon  = "rbxassetid://82337855669175",
		count = 1,
		rare  = true, -- ЭПИЧЕСКАЯ награда: в меню квестов слот светится фиолетовым (QuestMenu)
	},
	permanent = true,
})

-- ─── Daily quest pool (C4) ──────────────────────────────────────────
-- 6 candidates; the daily-roll logic in C7 will randomly pick 4 each
-- day from this pool, filtered against the player's permanentlyCompleted
-- set so already-crafted single-use objectives (workbench) don't
-- re-appear.
--
-- Single-objective quests by design — multi-step quests live in the
-- story arc instead. Numbers are tuned for ~5–10 minutes of casual
-- play each, so a player who logs in once a day can plausibly clear
-- all 4 in one session.
addQuest({
	id    = "daily_logs",
	kind  = "daily",
	title = "Fallen Branches",
	body  = "Chop down 10 logs.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "resource:Log", goal = 10, label = "Chop logs" },
	},
	reward = { kind = "resource", name = "Log", count = 10 },
})

addQuest({
	id    = "daily_plastic",
	kind  = "daily",
	title = "Plastic Patrol",
	body  = "Fish 8 plastic canisters out of the sea.",
	icon  = "rbxassetid://82407088576684",
	objectives = {
		{ eventType = "resource:Plastic", goal = 8, label = "Collect plastic" },
	},
	reward = { kind = "resource", name = "Plastic", count = 8 },
})

addQuest({
	id    = "daily_leaves",
	kind  = "daily",
	title = "Green Harvest",
	body  = "Gather 12 bunches of leaves.",
	icon  = "rbxassetid://137638372265731",
	objectives = {
		{ eventType = "resource:Leaves", goal = 12, label = "Gather leaves" },
	},
	reward = { kind = "resource", name = "Leaves", count = 6 },
})

addQuest({
	id    = "daily_stones",
	kind  = "daily",
	title = "Stone Cold",
	body  = "Mine 6 stones from floating rocks.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "resource:Stone", goal = 6, label = "Mine stones" },
	},
	-- rare = true — ДЕМО эпического свечения в меню квестов (влияет только на вид слота).
	-- Убери флаг или перенеси на нужный квест, когда проверишь.
	reward = { kind = "resource", name = "Stone", count = 6, rare = true },
})

addQuest({
	id    = "daily_craft_workbench",
	kind  = "daily",
	title = "First Workshop",
	body  = "Craft your very first workbench.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "crafted:WorkBench", goal = 1, label = "Craft workbench" },
	},
	reward = { kind = "resource", name = "Log", count = 15 },
	-- Single-use: once a player has crafted a workbench, this quest
	-- is filtered out of every future daily roll. Other crafting-
	-- gate dailies follow the same pattern.
	permanent = true,
})

addQuest({
	id    = "daily_plant_berries",
	kind  = "daily",
	title = "Sunny Garden",
	body  = "Plant 5 berry bushes.",
	icon  = "rbxassetid://98928050466796",
	objectives = {
		{ eventType = "planted:BerryBush", goal = 5, label = "Plant berry bushes" },
	},
	reward = { kind = "resource", name = "Leaves", count = 10 },
})

-- ─── Timed challenges (C5) ──────────────────────────────────────────
-- Player presses "Start" on the card, which kicks off a timer; the
-- challenge auto-shows in the upper-right tracker (Phase H) and the
-- card flips to a live countdown. If the goal isn't hit before the
-- timer expires the quest disappears with no reward and the player
-- has to wait for the next day's pool. Phase F drives the timer +
-- expiry server-side; this catalog just declares durations + goals.
addQuest({
	id    = "challenge_logs_30s",
	kind  = "challenge",
	title = "Speed Chopper",
	body  = "Chop 10 logs before time runs out.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "resource:Log", goal = 10, label = "Chop logs" },
	},
	reward      = { kind = "resource", name = "Log", count = 25 },
	durationSec = 30,
})

addQuest({
	id    = "challenge_pirate_kills_30s",
	kind  = "challenge",
	title = "Quick Draw",
	body  = "Defeat 3 hostile pirates before time runs out.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "pirate:kill", goal = 3, label = "Defeat hostile pirates" },
	},
	reward      = { kind = "resource", name = "Plastic", count = 15 },
	durationSec = 30,
})

addQuest({
	id    = "challenge_stones_45s",
	kind  = "challenge",
	title = "Quarry Sprint",
	body  = "Mine 5 stones in 45 seconds.",
	icon  = "rbxassetid://121862782555497",
	objectives = {
		{ eventType = "resource:Stone", goal = 5, label = "Mine stones" },
	},
	reward      = { kind = "resource", name = "Stone", count = 12 },
	durationSec = 45,
})

addQuest({
	id    = "challenge_plastic_60s",
	kind  = "challenge",
	title = "Reef Cleanup",
	body  = "Fish 8 plastic canisters in 60 seconds.",
	icon  = "rbxassetid://82407088576684",
	objectives = {
		{ eventType = "resource:Plastic", goal = 8, label = "Collect plastic" },
	},
	reward      = { kind = "resource", name = "Plastic", count = 20 },
	durationSec = 60,
})

end -- BETA_ONLY_ONBOARDING

-- ─── Filtered views (helper queries used by QuestState in C6+) ───────
-- Returned tables are fresh copies so callers can mutate freely.

local function getByKind(kind)
	local out = {}
	for _, q in pairs(catalog) do
		if q.kind == kind then table.insert(out, q) end
	end
	return out
end

-- ─── Publish ────────────────────────────────────────────────────────

_G.QuestCatalog = {
	get        = function(id) return catalog[id] end,
	all        = function() return catalog end,
	getByKind  = getByKind,
	addQuest   = addQuest,   -- re-exported in case future flows want to register dynamically
}