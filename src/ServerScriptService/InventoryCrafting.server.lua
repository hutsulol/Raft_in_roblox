local rs = game:GetService("ReplicatedStorage")

-- Русские подписи ресурсов и предметов: нужны в отказах крафта — «не хватает
-- Rubbish» игроку ничего не говорит, в рюкзаке у него «Мусор».
local ResourceNamesRu = require(rs:WaitForChild("ResourceNamesRu"))
local ItemNamesRu     = require(rs:WaitForChild("ItemNamesRu"))
-- правило «кто админ» общее с меню настроек: лежит в конфиге, а не копией здесь
local Config          = require(rs:WaitForChild("WeaponUpgradeConfig"))

local inventoryCraftEvent = rs:FindFirstChild("InventoryCraft")
if not inventoryCraftEvent then
	inventoryCraftEvent = Instance.new("RemoteEvent")
	inventoryCraftEvent.Name = "InventoryCraft"
	inventoryCraftEvent.Parent = rs
end

local recipes = {
	-- ВЕРСТАК УБРАН ИЗ КРАФТА вместе со всей своей станцией: крафтить предмет,
	-- который открывает второе окно крафта, стало нечем и незачем. Его рецепты
	-- переехали сюда ниже, старое меню — в archive/workbench/.
	{
		name = "Raft_smelter",
		displayName = "Плавильня",
		icon = "rbxassetid://111493193184870",
		--[[ ⚠️ ЦЕНА СТАНЦИИ СРЕДНЕЙ ИГРЫ, А НЕ ПЕРВЫХ МИНУТ.
		     Камень в этой игре — самый узкий ресурс: кирка нигде не выдаётся и не
		     крафтится, поэтому камень идёт только наградами за квесты (3 + 6 + 8 за
		     всю цепочку), ящиками дайвера (~0.9/мин) и бочками. Шесть камней — это
		     примерно награда за один квест, то есть плавильня ставится после того,
		     как игрок прошёл стартовый остров, и не раньше. Десять брёвен на фоне
		     8.5 бревна в минуту с моря — минута работы, они здесь для формы, а не
		     для гейта.
		     Дороже делать нельзя: плавильня — единственный источник слитков, а на
		     слитках висит улучшение дайверов (12 штук за ветку). Заприте её камнем
		     сильнее — и ветка дайверов станет недостижимой. ]]
		costs = {Log = 10, Stone = 6},
		craftType = "placeable",
		category = "Technology",
		description = "Плавильня. Топится брёвнами (E), плавит руду в слитки и водоросли в клей — сырьё ставится с рук наводкой.",
	},
	{
		--[[ ПУГАЛО: приманка для чаек (SeagullAI). Пока на нём есть свободное место
		     — две руки и шляпа, — чайки садятся на него, а грядки не трогают.
		     Цена ранней игры: пугало нужно ровно тогда, когда появилась первая
		     грядка, то есть до камня и железа. Солома — листва, перекладина и
		     шест — брёвна, обвязка — верёвка.
		     Иконки своей пока нет: пустая строка = общий реестр (_G.GetItemIcon). ]]
		name = "Raft_scarecrow",
		displayName = "Пугало",
		icon = "",
		-- иконка — сама модель пугала (ModelIcon), как у мебели
		preview = "Raft_scarecrow",
		costs = {Log = 4, Leaves = 6, Rope = 1},
		craftType = "placeable",
		category = "Technology",
		description = "Пугало: чайки садятся на него и не клюют грядки, пока на руках и шляпе есть место.",
	},
	--[[ ФЕРМА НА ПЛОТУ: предметы загона. Ставятся DecorPlace ТОЛЬКО на грядку
	     блока фермы (FarmPropRules). Цена — ранняя игра, ровня пугалу: корыто
	     долблёное из брёвен и стянуто верёвкой, ящик больше и крепче. ]]
	{
		name = "Raft_farm_trough", displayName = "Корыто", icon = "", preview = "Raft_farm_trough",
		costs = {Log = 6, Rope = 1}, craftType = "placeable", category = "Technology",
		description = "Водопойка для овец. Ставится только на грядку фермы; наливай воду кружкой (ПКМ). Без воды овцы дают вдвое меньше.",
	},
	{
		name = "Raft_wool_bin", displayName = "Ящик для шерсти", icon = "", preview = "Raft_wool_bin",
		costs = {Log = 8, Rope = 2}, craftType = "placeable", category = "Technology",
		description = "Сюда фермер складывает состриженную шерсть. Ставится только на грядку фермы.",
	},
	--[[ ПАК ДЕКОРА «ДЕФОЛТ» (модели в ReplicatedStorage.RaftDecor_all): вкладка
	     «Пак: Дефолт» видна и крафтится только у владельца пака — атрибут
	     игрока DecorPack_Default (DecorPacks.server, кнопка админа). Ставятся
	     DecorPlace, как стулья. Цены — ранняя игра: дерево, листва, пластик. ]]
	{
		name = "RaftDecor_bunting", displayName = "Гирлянда", icon = "", preview = "RaftDecor_bunting",
		costs = {Leaves = 3, Rope = 1}, craftType = "placeable", category = "DecorPack", requires = "DecorPack_Default",
		description = "Гирлянда из семи флажков — ровно на одну клетку.",
	},
	{
		name = "RaftDecor_can_flower", displayName = "Цветок в банке", icon = "", preview = "RaftDecor_can_flower",
		costs = {Plastic = 1, Leaves = 2}, craftType = "placeable", category = "DecorPack", requires = "DecorPack_Default",
		description = "Ромашка в консервной банке. На пол или на стол.",
	},
	{
		name = "RaftDecor_deckchair", displayName = "Шезлонг", icon = "", preview = "RaftDecor_deckchair",
		costs = {Log = 4, Rope = 1}, craftType = "placeable", category = "DecorPack", requires = "DecorPack_Default",
		description = "Шезлонг с полосатой тканью — можно сесть.",
	},
	{
		name = "RaftDecor_lantern", displayName = "Фонарь", icon = "", preview = "RaftDecor_lantern",
		costs = {Plastic = 2, Rope = 1}, craftType = "placeable", category = "DecorPack", requires = "DecorPack_Default",
		description = "Керосиновая лампа, светит тёплым светом.",
	},
	{
		name = "RaftDecor_lifebuoy", displayName = "Спасательный круг", icon = "", preview = "RaftDecor_lifebuoy",
		costs = {Plastic = 3, Rope = 1}, craftType = "placeable", category = "DecorPack", requires = "DecorPack_Default",
		description = "Спасательный круг с леером.",
	},
	{
		name = "RaftDecor_rug", displayName = "Коврик", icon = "", preview = "RaftDecor_rug",
		costs = {Leaves = 6}, craftType = "placeable", category = "DecorPack", requires = "DecorPack_Default",
		description = "Овальный плетёный коврик.",
	},
	{
		name = "RaftDecor_shelf", displayName = "Полка", icon = "", preview = "RaftDecor_shelf",
		costs = {Log = 3, Plastic = 1}, craftType = "placeable", category = "DecorPack", requires = "DecorPack_Default",
		description = "Полка с бутылками, банкой и свечой.",
	},
	{
		name = "RaftDecor_sign", displayName = "Указатель", icon = "", preview = "RaftDecor_sign",
		costs = {Log = 3}, craftType = "placeable", category = "DecorPack", requires = "DecorPack_Default",
		description = "Указатель с тремя стрелками.",
	},
	{
		name = "RaftDecor_spool_table", displayName = "Стол-катушка", icon = "", preview = "RaftDecor_spool_table",
		costs = {Log = 5, Rope = 1}, craftType = "placeable", category = "DecorPack", requires = "DecorPack_Default",
		description = "Стол из кабельной катушки.",
	},
	{
		name = "RaftDecor_stool", displayName = "Табурет", icon = "", preview = "RaftDecor_stool",
		costs = {Log = 2}, craftType = "placeable", category = "DecorPack", requires = "DecorPack_Default",
		description = "Табурет из спила на трёх ножках — можно сесть.",
	},
	{
		name = "RaftDecor_wheel", displayName = "Штурвал", icon = "", preview = "RaftDecor_wheel",
		costs = {Log = 4, Rope = 1}, craftType = "placeable", category = "DecorPack", requires = "DecorPack_Default",
		description = "Штурвал для украшения.",
	},
	--[[ ДЕКОР: вкладка «Декор». preview — имя модели: иконка в меню рисуется
	     самой моделью (ModelIcon), как в молотке; картинок у мебели нет.
	     Ставятся DecorPlace (призрак, поворот, проверка места), сохраняются с
	     плотом, ломаются топором. ]]
	{
		name = "Raft_chair", displayName = "Стул", icon = "", preview = "Raft_chair",
		costs = {Log = 4}, craftType = "placeable", category = "Decor",
		description = "Деревянный стул. Просто чтобы было где посидеть.",
	},
	{
		name = "Raft_chair_leaf", displayName = "Стул с листвой", icon = "", preview = "Raft_chair_leaf",
		costs = {Log = 3, Leaves = 3}, craftType = "placeable", category = "Decor",
		description = "Стул с сиденьем из листвы.",
	},
	{
		name = "Raft_table_leaves", displayName = "Стол с листвой", icon = "", preview = "Raft_table_leaves",
		costs = {Log = 6, Leaves = 4}, craftType = "placeable", category = "Decor",
		description = "Стол, накрытый листвой. Центр любой палубы.",
	},
	{
		name = "Raft_grill_barrel",
		displayName = "Мангал-бочка",
		icon = "rbxassetid://92828269363847",
		--[[ ⚠️ БОЧКА ДОРОЖЕ ОБЫЧНОГО МАНГАЛА (6 Log + 4 Stone) И ТРЕБУЕТ ЖЕЛЕЗА.
		     Она строго лучше: вчетверо больше мест на решётке и время готовки 0.6 от
		     обычного. За одно бревно она обесценивала и мангал, и весь квест «Мясо на
		     углях», который этот мангал требует.
		     Слиток здесь не для дороговизны, а чтобы порядок построек читался:
		     мангал → плавильня → бочка. Заодно это ВТОРОЙ сток железа во всей игре —
		     до сих пор слитки тратились только на улучшение дайверов, и §13.7 прямо
		     называет железо тупиковым ресурсом.
		     Один слиток, а не два: руду добывают киркой, которой у игрока может не
		     быть вовсе, и остаются грузы пиратских катеров — редкий, но рабочий путь. ]]
		costs = {Log = 10, Stone = 4, Iron_Ingot = 1},
		craftType = "placeable",
		category = "Technology",
		description = "Мангал-бочка: вчетверо больше места на решётке и жарит быстрее обычного мангала.",
	},
	{
		name = "Raft_grill",
		displayName = "Костровая жаровня",
		icon = "rbxassetid://86941334995718",
		-- дороже костра: даёт готовку на две порции сразу и не гаснет так быстро
		costs = {Log = 6, Stone = 4},
		craftType = "placeable",
		category = "Technology",
		description = "Костровая жаровня. Поставь на плот, подбрасывай брёвна на E — и нажимай по ней, чтобы положить на решётку до двух порций еды.",
	},
	{
		-- Причал с лодкой: по размеру равен ТРЁМ клеткам пола и встаёт вместо них.
		-- Ставится не через призрак CupPurifier, а режимом стройки (BuildingSystem):
		-- взял в руки — та же сетка, что у молотка, R разворачивает.
		name = "Boat_3x",
		displayName = "Причал с лодкой",
		icon = "rbxassetid://84900623714454",
		--[[ ⚠️ САМАЯ КРУПНАЯ ПОСТРОЙКА НА ПЛОТУ — И ЦЕНА ПОД СТАТЬ.
		     Причал занимает ТРИ клетки пола, то есть заменяет собой кусок плота
		     размером с половину стартового. Двадцать четыре бревна — это около трёх
		     минут сбора с моря, четыре верёвки — ещё шестнадцать листьев (листва идёт
		     вдвое медленнее дерева). Вместе выходит вечер работы, и это правильно:
		     причал не нужен для выживания и не завязан ни на один квест.
		     Гвоздей в цене нет намеренно: хлам падает только из бочек, и любая вещь
		     на нём превращается в лотерею. ]]
		costs = {Log = 24, Rope = 4},
		-- Кроме материалов — освобождённые жители: причал не построить в одиночку.
		-- Это отдельное поле, а не строка в costs: жители живут не в инвентаре, а
		-- в атрибуте игрока, и списывает их VillagersCurrency.
		-- ⚠️ Пять оставлены как есть, хотя сейчас это слабый гейт: жители не
		-- сохраняются между заходами и на старте их выдают двадцать. Поднимать
		-- число бессмысленно, пока не сделано сохранение — стартовый запас всё
		-- равно перекроет любую цену.
		villagers = 5,
		craftType = "placeable",
		category = "Technology",
		description = "Причал с лодкой на три клетки. Возьми в руки, наведись на пустое место у края плота и нажми ЛКМ. R — развернуть.",
	},
	{
		-- ОГНЕМЁТ. Собирается ИЗ КАНИСТРЫ: она уходит в конструкцию целиком,
		-- вместе с остатком топлива — сколько было налито, столько и станет
		-- зарядом (баки одного объёма, 3 литра, см. FlamethrowerDefs).
		name = "Flamethrower",
		displayName = "Огнемёт",
		-- Своя иконка огнемёта. Раньше здесь стояла временная, от канистры, и меню
		-- крафта показывало канистру вместо оружия.
		-- ⚠️ ВТОРАЯ КОПИЯ ЕСТЬ В InventoryUI.client.lua, TOOL_ICONS["Flamethrower"]:
		-- эта иконка — для карточки РЕЦЕПТА, та — для слота с готовым тулом в руках
		-- и в хотбаре. Меняешь одну — меняй обе, иначе в крафте будет одно, а в
		-- рюкзаке другое. Ниже в toolCost.icon канистра остаётся: она там по делу,
		-- это изображение платы за крафт.
		icon = "rbxassetid://115269318677272",
		costs = {Log = 2, Rubbish = 3},
		-- Канистра — часть цены: уходит из инвентаря целиком, а её остаток
		-- топлива становится зарядом огнемёта (см. обработку toolCost ниже).
		toolCost = {
			tool = "Plastic_canister",
			label = "Пластиковая канистра",
			icon = "rbxassetid://131765057486498",
			from = "OilFill", to = "FuelFill",
		},
		craftType = "tool",
		category = "Tools",
		description = "Огнемёт из канистры. Держи ЛКМ — бьёт струёй огня; полный бак горит 25 секунд. Заправляется от бака на плоту. Под водой не работает.",
	},
	{
		name = "Hammer",
		displayName = "Молоток",
		icon = "rbxassetid://86264127232874",
		costs = {Log = 4}, -- баланс §13.6 (было {Log=1})
		craftType = "tool",
		category = "Tools",
		description = "Нужно, чтобы строить и расширять плот новыми клетками пола.",
	},
	{
		--[[ СЕТКОМЁТ (пакет NetCapture): ловит овцу сетью, её можно унести и
		     выпустить на новом месте. Шаблон Tool — ReplicatedStorage/NetCapture/
		     Assets/Pirate_Net_Launcher (кладёт владелец), иконка — сама модель. ]]
		name = "Pirate_Net_Launcher",
		displayName = "Сеткомёт",
		icon = "", preview = "Pirate_Net_Launcher",
		costs = {Log = 6, Rope = 3, Iron_Ingot = 1},
		craftType = "tool",
		category = "Tools",
		description = "Стреляет сетью: пойманную овцу можно поднять (E) и выпустить (F) на новом месте.",
	},
	{
		name = "Machete",
		displayName = "Мачете",
		icon = "rbxassetid://92926554091794",
		costs = {Log = 3, Rope = 1}, -- баланс §13.6 (было {Log=1})
		craftType = "tool",
		category = "Tools",
		description = "Острый клинок для ближнего боя.",
	},
	{
		name = "Cup",
		displayName = "Кружка",
		icon = "rbxassetid://99673504095026",
		costs = {Plastic = 2},
		craftType = "tool",
		initAttributes = {CupState = "empty"},
		category = "Misc",
		description = "Кружка, чтобы набрать океанской воды. Набери, очисти и выпей, чтобы утолить жажду.",
	},
	{
		name = "Plastic_canister",
		displayName = "Пластиковая канистра",
		icon = "rbxassetid://131765057486498",
		costs = {Plastic = 6, Rope = 1},
		craftType = "tool",
		-- Пустая канистра на 3 литра: уровень живёт в атрибутах тула (см. OilCanister)
		initAttributes = {OilFill = 0, OilCapacity = 3000},
		category = "Misc",
		description = "Канистра на 3 литра. Наливается из бочек с топливом на катерах — одной бочки хватает примерно на четверть.",
	},
	{
		name = "DivingMask",
		displayName = "Маска для ныряния",
		icon = "rbxassetid://79806920407397",
		-- Стекло и ремешок: пластик — материал всей снаряги (кружка, канистра,
		-- очиститель), верёвка одна, потому что две забирали восемь листьев —
		-- дороже, чем стоит продлённое дыхание.
		costs = {Plastic = 6, Rope = 1},
		-- Не тул: надеваемая вещь лежит в инвентаре ресурсом по одной штуке и
		-- надевается перетаскиванием в слот экипировки (см. EquipmentDefs).
		craftType = "resource",
		category = "Technology",
		description = "Маска для ныряния. Перетащи её в слот экипировки на голову, чтобы надеть.",
	},
	{
		name = "Destitalor",
		displayName = "Очиститель воды",
		icon = "rbxassetid://90221080738714",
		costs = {Plastic = 4},
		craftType = "tool",
		category = "Technology",
		description = "Превращает солёную воду в питьевую. Поставь на плот, чтобы пользоваться.",
	},
	{
		-- Имя тула осталось "Garden": на него завязаны призрак, поворот на R и
		-- вся цепочка установки. Сама модель теперь новая (Raft_planter), а
		-- поведение даёт PlanterService — см. placePlanter.
		name = "Garden",
		displayName = "Грядка",
		icon = "rbxassetid://137766871451752",
		costs = {Log = 4, Compost = 3},   -- компост выуживается из океана
		craftType = "placeable",
		category = "Technology",
		description = "Грядка под овощи: 4 дерева и 3 компоста из океана. Посади картофель или свёклу, поливай — и собери втрое больше.",
	},
	-- ── ПЕРЕЕХАЛО С ВЕРСТАКА ──
	-- Верстак как отдельная станция убран: он был вторым местом, где что-то
	-- крафтится, со своим меню, своим сервером и своим списком рецептов — и
	-- половину игры игрок таскал в рюкзаке предмет, чтобы поставить его на плот и
	-- открыть по нему второе такое же окно. Всё, что там было нужного, живёт
	-- теперь здесь, по тем же ценам. Старая станция — в archive/workbench/.
	{
		--[[ ⚠️ МОДЕЛЬ ЯКОРЯ ЗАМЕНЕНА НА ЛЕБЁДКУ Raft_anchor.
		     Имя рецепта — это И имя тула в руках, И имя модели, которую ищет
		     установка (BuildingSystem, ветка anchor). Меняя одно, меняешь всё
		     сразу, поэтому старое имя Anchor_part осталось только запасным путём
		     в установке: не найдётся новая модель — встанет прежняя.
		     Цену не трогаю: якорь и раньше стоил столько, а лебёдка — та же вещь
		     в новом виде, а не новая ступень прогресса. ]]
		name = "Raft_anchor",
		displayName = "Якорь",
		icon = "rbxassetid://120414328052740",
		costs = {Log = 5, Stone = 2},
		craftType = "placeable",
		category = "Technology",
		description = "Якорь. Опусти его на цепи — и плот перестанет сносить течением.",
	},
	{
		-- ⚠️ КРОВАТЬ РАНЬШЕ КРАФТИЛАСЬ НЕ ЗДЕСЬ И НЕ ТАК.
		-- У неё был свой обработчик в BedCrafting со своей проверкой цены и
		-- требованием стоять в 15 студах от верстака. Верстака больше нет, значит
		-- и требования нет; выдача идёт общей веткой placeable — она делает ровно
		-- тот же тул-заготовку, что делал тот обработчик руками.
		name = "Bed",
		displayName = "Лежанка",
		icon = "rbxassetid://97461315404202",
		costs = {Log = 5, Leaves = 3},   -- баланс §13.6, цена не менялась
		craftType = "placeable",
		category = "Technology",
		description = "Лежанка: поставь на плот, чтобы переждать ночь и просыпаться здесь.",
	},
	{
		name = "SmallContainer",
		displayName = "Малый контейнер",
		icon = "rbxassetid://86632287242518",
		costs = {Log = 6},
		craftType = "placeable",
		category = "Misc",
		description = "Небольшой контейнер: сложить лишнее, чтобы не занимало рюкзак.",
	},
	{
		name = "PlasticContainer",
		displayName = "Пластиковый контейнер",
		icon = "rbxassetid://98308527317479",
		costs = {Plastic = 5},
		craftType = "placeable",
		category = "Misc",
		description = "Большой контейнер: места вдвое больше, чем в деревянном.",
	},
	{
		name = "Paddle",
		displayName = "Весло",
		icon = "rbxassetid://93358108538106",
		costs = {Log = 1, Plastic = 3},
		craftType = "tool",
		category = "Tools",
		description = "Весло, чтобы править плотом и разгонять его. Кликай туда, куда хочешь плыть.",
	},
	{
		name = "Rope",
		displayName = "Верёвка",
		icon = "rbxassetid://78492721752628",
		costs = {Leaves = 4},
		craftType = "resource",
		category = "Resources",
		description = "Крепкая верёвка, свитая из листьев. Нужна для продвинутого снаряжения.",
	},
	{
		name = "Nail",
		displayName = "Гвозди",
		icon = "rbxassetid://82878494424821",
		costs = {Rubbish = 3},   -- хлам, выловленный из моря
		craftType = "resource",
		yield = 3,               -- из трёх хлама — три гвоздя
		category = "Resources",
		description = "Три гвоздя, перекованные из мусора. Пригодятся для построек.",
	},
	{
		name = "FishingRod",
		displayName = "Удочка",
		icon = "rbxassetid://105180666555503",
		costs = {Log = 3, Rope = 2},
		craftType = "tool",
		category = "Tools",
		description = "Заброс в океан: ловит рыбу на еду.",
		day = 4,   -- открывается на 4-й игровой день
	},
}

-- ⚠️ ИЗ КРАФТА УБРАНЫ НАМЕРЕННО (по решению геймдизайна, сами системы живы):
-- мешки (bag_empty_2, leaf bag, Sand Bag), костёр (FireCamp), грядка под дерево
-- (Bed_T), виноградный куст (bush), Phone, Injector, EmptyCapsule,
-- лопата (Shovel), кирка (Pick-Axe), сырой кирпич (Wet_Brick). Возвращать —
-- записью в recipes, обработчик ниже менять не нужно.

-- ═══════════ РЕЦЕПТЫ ПО ДНЯМ ═══════════
-- ⚠️ ОДНО ПОЛЕ НА РЕЦЕПТ, БЕЗ ОТДЕЛЬНОЙ ТАБЛИЦЫ РАСПИСАНИЯ.
-- День открытия — это свойство самого рецепта, а не список где-то сбоку: иначе
-- при добавлении предмета про расписание забудут, и он либо появится сразу, либо
-- потеряется. Нет поля day — значит доступен с первого дня, как и было.
--
-- Список фильтруется НА СЕРВЕРЕ: клиенту незачем знать про рецепты, которые он
-- пока не может собрать, а проверка при самом крафте ниже страхует от подделки
-- запроса.
local function currentDay()
	local dc = rs:FindFirstChild("DayCount")
	return (dc and tonumber(dc.Value)) or 1
end

local function recipeUnlocked(recipe, day)
	return (tonumber(recipe.day) or 1) <= (day or currentDay())
end

local function recipesForDay(day)
	local out = {}
	for _, r in ipairs(recipes) do
		if recipeUnlocked(r, day) then table.insert(out, r) end
	end
	return out
end

-- ── УВЕДОМЛЕНИЕ О НОВОМ РЕЦЕПТЕ ──
-- Открывшийся предмет нужно ЗАМЕТИТЬ: молча появившаяся строка в списке из
-- полутора десятков рецептов не видна никому. Шлём карточку в момент смены дня —
-- и заодно пересылаем клиенту обновлённый список, иначе он покажет старый до
-- следующего открытия инвентаря.
local Players = game:GetService("Players")

local function announceUnlocked(day)
	local fresh = {}
	for _, r in ipairs(recipes) do
		if (tonumber(r.day) or 1) == day then table.insert(fresh, r) end
	end
	if #fresh == 0 then return end

	for _, player in ipairs(Players:GetPlayers()) do
		local inv = _G.GetInventory and _G.GetInventory(player) or {Log = 0}
		inventoryCraftEvent:FireClient(player, "recipes", recipesForDay(day), inv)
		for _, r in ipairs(fresh) do
			if _G.NotifyPlayer then
				_G.NotifyPlayer(player, {
					type = "info", icon = "🛠️",
					title = "Новый чертёж: " .. (r.displayName or r.name),
					body = r.description,
				})
			end
		end
	end
	print(("[Крафт] день %d: открыто рецептов — %d"):format(day, #fresh))
end

task.spawn(function()
	local dc = rs:WaitForChild("DayCount", 30)
	if not dc then
		warn("[Крафт] нет DayCount — рецепты по дням открываться не будут")
		return
	end
	dc.Changed:Connect(function(value)
		announceUnlocked(tonumber(value) or 1)
	end)
end)

inventoryCraftEvent.OnServerEvent:Connect(function(player, action, data)
	if action == "requestRecipes" then
		local inv = _G.GetInventory and _G.GetInventory(player) or {Log = 0}
		inventoryCraftEvent:FireClient(player, "recipes", recipesForDay(currentDay()), inv)
		return
	end

	if action ~= "craft" then return end
	if typeof(data) ~= "string" then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local recipe = nil
	for _, r in recipes do
		if r.name == data then
			recipe = r
			break
		end
	end
	if not recipe then return end
	-- ⚠️ ДЕНЬ ПРОВЕРЯЕМ И ЗДЕСЬ, А НЕ ТОЛЬКО ПРИ ВЫДАЧЕ СПИСКА.
	-- Список — это подсказка клиенту; запрос на крафт приходит от него же и
	-- подделывается одной строкой. Без этой проверки удочку можно было бы собрать
	-- в первый день, просто отправив её имя.
	-- рецепты пака — только владельцу (вкладку видит он один, но запрос подделывается)
	if recipe.requires and player:GetAttribute(recipe.requires) ~= true then
		warn(("[Крафт] %s: рецепт %s из пака, пака нет"):format(player.Name, recipe.name))
		return
	end
	if not recipeUnlocked(recipe) then
		warn(("[Крафт] %s: рецепт %s ещё не открыт (день %d)")
			:format(player.Name, recipe.name, currentDay()))
		return
	end

	local inv = _G.GetInventory and _G.GetInventory(player) or {}

	-- Sand / Clay don't live in the inventory — they're stashed in the
	-- Sand Bag tool. Treat bag units as if they were inventory units
	-- for both the affordability check and the actual deduction below.
	local function availableFor(item)
		local count = inv[item] or 0
		if (item == "Sand" or item == "Clay") and _G.GetBagUnitsFor then
			count = count + _G.GetBagUnitsFor(player, item)
		end
		return count
	end

	-- ⚠️ ОТКАЗ ДОЛЖЕН ГОВОРИТЬ, ЧЕГО НЕ ХВАТИЛО.
	-- Здесь стоял голый return: клиенту не уходило ничего, и нажатие на «Собрать»
	-- выглядело как сломанная кнопка. Особенно на огнемёте, где не хватает обычно
	-- мусора, а в списке видна цена только одного материала.
	--[[ ⚠️ АДМИНУ КРАФТ БЕСПЛАТНЫЙ — ЭТО ИНСТРУМЕНТ ТЕСТИРОВЩИКА.
	     Проверить рецепт, не собрав перед этим двадцать четыре бревна и четыре
	     верёвки, иначе невозможно: кнопка «Создать» просто не нажимается, и
	     любая правка цены превращается в получасовой фарм.
	     Бесплатность снимает ТОЛЬКО плату: место, соседство клеток и все прочие
	     проверки остаются — иначе тест перестал бы быть тестом.
	     ⚠️ Клиент знает то же правило (InventoryUI, canAfford) и по нему делает
	     кнопку активной. Разойдутся — кнопка снова станет мёртвой. ]]
	local freeCraft = false
	do
		local ok, res = pcall(Config.isAdmin, player)
		freeCraft = ok and res == true
	end

	if not freeCraft then
		for item, amount in recipe.costs do
			local have = availableFor(item)
			if have < amount then
				inventoryCraftEvent:FireClient(player, "denied",
					("Не хватает: %s (%d из %d)"):format(ResourceNamesRu(item), have, amount))
				return
			end
		end
	end

	-- ИНСТРУМЕНТ КАК ЧАСТЬ ЦЕНЫ (огнемёт собирают из канистры).
	-- Ищем и в руках, и в рюкзаке: доставать её ради крафта незачем. Сам предмет
	-- уничтожается ПОСЛЕ создания результата — чтобы при любой осечке ниже игрок
	-- не остался вообще без ничего.
	local costTool = nil
	if recipe.toolCost then
		local char2 = player.Character
		for _, where in ipairs({ char2, player:FindFirstChildOfClass("Backpack") }) do
			if where then
				for _, t in ipairs(where:GetChildren()) do
					if t:IsA("Tool") and t.Name == recipe.toolCost.tool then costTool = t break end
				end
			end
			if costTool then break end
		end
		-- админу канистра тоже не обязательна: есть — уйдёт в крафт вместе с
		-- остатком топлива, как у всех; нет — соберём с пустым баком
		if not costTool and not freeCraft then
			inventoryCraftEvent:FireClient(player, "denied",
				("Нужен предмет: %s"):format(recipe.toolCost.label
					or ItemNamesRu.display(recipe.toolCost.tool) or recipe.toolCost.tool))
			return
		end
	end

	-- ЖИТЕЛИ СПИСЫВАЮТСЯ ДО МАТЕРИАЛОВ.
	-- SpendVillagers сам проверяет и списывает одним действием; если их не
	-- хватило, выходим, НЕ тронув инвентарь — иначе брёвна бы пропали впустую.
	if not freeCraft and recipe.villagers and recipe.villagers > 0 then
		local ok = _G.SpendVillagers and _G.SpendVillagers(player, recipe.villagers)
		if not ok then
			inventoryCraftEvent:FireClient(player, "denied",
				("Нужно %d освобождённых жителей"):format(recipe.villagers))
			return
		end
	end

	if not freeCraft then
		for item, amount in recipe.costs do
			local remaining = amount
			if (item == "Sand" or item == "Clay") and _G.RemoveBagUnits then
				local fromBag = _G.RemoveBagUnits(player, item, remaining)
				remaining = remaining - fromBag
			end
			if remaining > 0 then
				if _G.RemoveResourceFromInventory then
					_G.RemoveResourceFromInventory(player, item, remaining)
				else
					inv[item] = (inv[item] or 0) - remaining
				end
			end
		end
	end

	-- Templates normally live directly under ReplicatedStorage, but a few
	-- (e.g. FishingRod) are packaged inside ReplicatedStorage.MainModule.
	-- Fall back to a recursive search so recipes don't need to know the path.
	local template = rs:FindFirstChild(recipe.name)
	if not template then
		template = rs:FindFirstChild(recipe.name, true)
	end

	if recipe.craftType == "tool" then
		local tool

		if template then
			local cloned = template:Clone()

			if cloned:IsA("Tool") then
				tool = cloned
				-- Ensure the tool has a Handle (required for Activated to fire)
				if not tool:FindFirstChild("Handle") then
					local firstPart = tool:FindFirstChildWhichIsA("BasePart", true)
					if firstPart then
						firstPart.Name = "Handle"
					end
				end
			else
				-- Wrap Model/BasePart in a Tool so it appears in Backpack
				tool = Instance.new("Tool")
				tool.Name = recipe.name
				tool.CanBeDropped = false

				-- Find or create a Handle part
				if cloned:IsA("Model") then
					-- кружка: ручка — сам корпус (CupBody), а не меш воды (CupVisuals прячет воду)
					local handle = cloned:FindFirstChild("Handle") or cloned:FindFirstChild("CupBody")
					if not handle then
						handle = cloned:FindFirstChildWhichIsA("BasePart", true)
					end
					-- Move all parts into the Tool
					for _, child in cloned:GetChildren() do
						child.Parent = tool
					end
					-- Ensure one part is named Handle
					if handle and handle.Name ~= "Handle" then
						handle.Name = "Handle"
					end
				elseif cloned:IsA("BasePart") then
					cloned.Name = "Handle"
					cloned.Parent = tool
				end

				cloned:Destroy()
			end
		else
			-- No template in ReplicatedStorage — build a minimal placeholder
			-- Tool so the item still appears in the backpack with its icon.
			tool = Instance.new("Tool")
			tool.Name = recipe.name
			tool.CanBeDropped = false
			local handle = Instance.new("Part")
			handle.Name = "Handle"
			handle.Size = Vector3.new(1, 1, 1)
			handle.Transparency = 1
			handle.Parent = tool
		end

		if tool then
			if recipe.initAttributes then
				for attr, val in recipe.initAttributes do
					tool:SetAttribute(attr, val)
				end
			end
			-- заряд съеденного предмета переезжает в результат (топливо канистры
			-- становится топливом огнемёта), и только теперь канистра исчезает
			if costTool then
				if recipe.toolCost.from and recipe.toolCost.to then
					tool:SetAttribute(recipe.toolCost.to,
						costTool:GetAttribute(recipe.toolCost.from) or 0)
				end
				costTool:Destroy()
			end
			if recipe.icon and tool.TextureId == "" then
				tool.TextureId = recipe.icon
			end
			if _G.GiveToolOrDrop then
				_G.GiveToolOrDrop(player, tool)
			else
				local backpack = player:FindFirstChild("Backpack")
				if backpack then tool.Parent = backpack end
			end
		end
	elseif recipe.craftType == "placeable" then
		-- Create a small placeholder tool (the full model is cloned on placement)
		local tool = Instance.new("Tool")
		tool.Name = recipe.name
		tool.CanBeDropped = false
		if recipe.icon then
			tool.TextureId = recipe.icon
		end
		-- декор без картинки: хотбар рисует модель по этому атрибуту (InventoryUI)
		if type(recipe.preview) == "string" and recipe.preview ~= "" then
			tool:SetAttribute("PreviewModel", recipe.preview)
		end

		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(1, 1, 1)
		handle.Transparency = 1
		handle.Parent = tool

		if _G.GiveToolOrDrop then
			_G.GiveToolOrDrop(player, tool)
		else
			local backpack = player:FindFirstChild("Backpack")
			if backpack then tool.Parent = backpack end
		end

	elseif recipe.craftType == "resource" then
		-- Route through AddResourceToInventory so full-inventory
		-- overflow spills to the ground instead of being silently stored.
		-- yield — сколько штук даёт один крафт (гвозди идут тройками).
		_G.AddResourceToInventory(player, recipe.name, recipe.yield or 1, nil)

	elseif recipe.craftType == "place" then
		if template then
			local clone = template:Clone()
			local raft = workspace:FindFirstChild("Raft")
			if raft and raft.PrimaryPart then
				local raftPos = raft.PrimaryPart.Position
				clone:PivotTo(CFrame.new(raftPos + Vector3.new(0, 5, 0)))
			else
				local hrp = char:FindFirstChild("HumanoidRootPart")
				clone:PivotTo(CFrame.new(hrp.Position + hrp.CFrame.LookVector * 5))
			end
			clone.Parent = workspace
		end
	end

	if _G.SendInventory then
		_G.SendInventory(player)
	end

	-- Quest hook (Phase I): credit any "crafted:<name>" objectives. We
	-- fire the recipe name verbatim so future quests that gate on a
	-- new recipe just need to add it to the catalog without touching
	-- this dispatch.
	if typeof(_G.OnQuestEvent) == "function" then
		pcall(_G.OnQuestEvent, player, "crafted:" .. recipe.name, 1)
	end

	inventoryCraftEvent:FireClient(player, "success", recipe.name)
end)