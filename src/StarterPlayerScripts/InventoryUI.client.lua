local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)


local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate")
local inventoryCraftEvent = ReplicatedStorage:WaitForChild("InventoryCraft")

-- Русские подписи ресурсов. Ключи (Log, Iron_Ingot…) служебные и остаются
-- английскими — в UI показываем перевод из общего словаря.
local ResourceNamesRu = require(ReplicatedStorage:WaitForChild("ResourceNamesRu"))
-- Подписи предметов на языке игрока (русский + автоперевод Roblox)
local ItemNamesRu = require(ReplicatedStorage:WaitForChild("ItemNamesRu"))
-- Экипировка: слоты и что во что надевается — общее с сервером
local EquipmentDefs = require(ReplicatedStorage:WaitForChild("EquipmentDefs"))
local equipmentRemote = ReplicatedStorage:WaitForChild("EquipmentAction")
-- Прочность тулов: пороги цвета и имена атрибутов — общие с сервером
local ToolDurability = require(ReplicatedStorage:WaitForChild("ToolDurability"))

-- Seed-as-Tool flow was retired — seeds now live in the leaf bag
-- container (see SeedBagSystem.server.lua) and never appear as a
-- main-inventory stack. Empty whitelist + nil event keep any stale
-- click-on-seed handlers below as harmless no-ops.
local equipSeedEvent = nil
local SEED_RESOURCE_SET = {}

-- Food-as-Tool flow. Clicking a Banana / Coconut / Pineapple slot
-- in the inventory tells the server to spawn the matching Tool in
-- the player's hand (and decrement the stack by 1). A second click
-- while the Tool is held eats it for hunger + HP; an unequip
-- without eating refunds the resource. Server lives in
-- ServerScriptService/FoodSystem.server.lua.
local equipFoodEvent = ReplicatedStorage:FindFirstChild("EquipFoodAsTool")
if not equipFoodEvent then
	equipFoodEvent = ReplicatedStorage:WaitForChild("EquipFoodAsTool", 5)
end

-- Any "<fish>_Cooked" key (produced by the campfire) is edible like a
-- fruit, so the metatable returns true for them without needing a
-- per-fish entry when a new fish is adapted.
local FOOD_RESOURCE_SET = setmetatable({
	Banana    = true,
	Coconut   = true,
	Pineapple = true,
	Blue_Fish = true,
	Carp_Fish = true,
	Foil_Fish = true,
	Jelly_Fish = true,
	Legendary_Fish = true,
	Seabass_Fish = true,
	Tilapia_Fish = true,
	Meat = true,
	Chicken_drumstick = true,   -- окорочок: жарится в жареное мясо
	-- Овощи с грядки. Печёные подхватывает правило "_Cooked" ниже.
	Potato = true,
	Beet = true,
}, {
	__index = function(_, k)
		if type(k) == "string" and #k > 7 and k:sub(-7) == "_Cooked" then
			return true
		end
		return nil
	end,
})

-- Bush-seed-as-Tool flow. Riding on the same BushAction RemoteEvent
-- HungerSystem already exposes for berry-bush placement avoids
-- depending on a new server script being added to Studio. Clicking
-- a Pineapple_Bush_Seed inventory slot fires
-- BushAction("equipBushSeed", resourceName) and the server spawns
-- the matching placement Tool in the player's hand (refund-on-
-- unequip-without-place is handled server-side).
local bushActionEvent = ReplicatedStorage:FindFirstChild("BushAction")
if not bushActionEvent then
	bushActionEvent = ReplicatedStorage:WaitForChild("BushAction", 5)
end

local BUSH_SEED_RESOURCE_SET = {
	Pineapple_Bush_Seed = true,
}

-- Материалы плавильни (Raft_smelter): кликом по слоту берутся В РУКИ тем же
-- механизмом, что еда — сервер (SmelterSystem) снимает 1 со стака и выдаёт Tool
-- с атрибутом MaterialResource; снятие с рук возвращает единицу в стак.
local equipMaterialEvent = ReplicatedStorage:FindFirstChild("EquipMaterialAsTool")
if not equipMaterialEvent then
	equipMaterialEvent = ReplicatedStorage:WaitForChild("EquipMaterialAsTool", 5)
end
local MATERIAL_RESOURCE_SET = {
	Iron_Ore = true,
	Seaweed  = true,
}

local LOG_ICON = "rbxassetid://116178347748793"
local PLASTIC_ICON = "rbxassetid://132919988751848"
local STONE_ICON = "rbxassetid://96450657403376"
local IRON_ORE_ICON = "rbxassetid://78456892304314"
local IRON_INGOT_ICON = "rbxassetid://72890243946368"
-- Leaves / Sand / Clay / Wet_Brick / Dry_Brick had asset ids that were
-- updated in WorkbenchUI but never propagated here, so the inventory's
-- crafting panel kept rendering the old artwork while every other UI
-- (workbench, furnace, mining highlight, resource pull) showed the
-- new one. Synced to the WorkbenchUI ids below.
local LEAVES_ICON = "rbxassetid://96691360298069"
local COMPOST_ICON = "rbxassetid://78760258555926"

local PLANK_ICON = "rbxassetid://118108820731466"
local ROPE_ICON = "rbxassetid://78492721752628"
local SAND_ICON = "rbxassetid://92407877736322"
local CLAY_ICON = "rbxassetid://129473903672183"
local WET_BRICK_ICON = "rbxassetid://139059474647090"
local DRY_BRICK_ICON = "rbxassetid://97609326528615"
local BAG_EMPTY_ICON = "rbxassetid://89398456198664"
local BAG_WITH_CLAY_ICON = "rbxassetid://126238050436106"
local BAG_WITH_SAND_ICON = "rbxassetid://77748685223141"
local GLASS_ICON = "rbxassetid://85347221722445"
local GLASS_PANEL_ICON = "rbxassetid://79199838395462"

local BLUE_FISH_ICON = "rbxassetid://79355503342560"
local BLUE_FISH_COOKED_ICON = "rbxassetid://91351143221536"
local CARP_FISH_ICON = "rbxassetid://122400137030638"
local CARP_FISH_COOKED_ICON = "rbxassetid://125349706938591"
local FISH_BONES_ICON = "rbxassetid://118274743954023"
local FOIL_FISH_ICON = "rbxassetid://86978570169083"
local JELLY_FISH_ICON = "rbxassetid://139713210103014"
local LEGENDARY_FISH_ICON = "rbxassetid://109844816428837"
local LEGENDARY_FISH_COOKED_ICON = "rbxassetid://100932404198778"
local SEABASS_FISH_ICON = "rbxassetid://112734818459787"
local TILAPIA_FISH_ICON = "rbxassetid://102206483084738"
local TILAPIA_FISH_COOKED_ICON = "rbxassetid://127252371837787"
local MEAT_ICON = "rbxassetid://140237721809215"
local MEAT_COOKED_ICON = "rbxassetid://110578314998395"
-- Овощи с грядки. У печёных СВОИ иконки, а не перекрашенные сырые.
local POTATO_ICON = "rbxassetid://114389346130909"
local POTATO_COOKED_ICON = "rbxassetid://125234740324443"
local BEET_ICON = "rbxassetid://80108091374305"
local BEET_COOKED_ICON = "rbxassetid://135727750826934"
-- Шерсть с фермы (FarmSystem). ⚠️ КАРТИНКИ ПОКА НЕТ — id впишет владелец; пустая строка = без иконки.
local WOOL_ICON = ""

local RESOURCE_ICONS = {
	Log = LOG_ICON,
	Plastic = PLASTIC_ICON,
	Stone = STONE_ICON,
	Iron_Ore = IRON_ORE_ICON,
	Iron_Ingot = IRON_INGOT_ICON,
	Plank = PLANK_ICON,
	Leaves = LEAVES_ICON,
	Compost = COMPOST_ICON,
	Wool = WOOL_ICON,
	Rope = ROPE_ICON,
	Sand = SAND_ICON,
	Clay = CLAY_ICON,
	Wet_Brick = WET_BRICK_ICON,
	Dry_Brick = DRY_BRICK_ICON,
	bag_with_clay_2 = BAG_WITH_CLAY_ICON,
	bag_with_sand_2 = BAG_WITH_SAND_ICON,
	glass = GLASS_ICON,
	glass_panel = GLASS_PANEL_ICON,
	Blue_Fish = BLUE_FISH_ICON,
	Carp_Fish = CARP_FISH_ICON,
	Fish_Bones = FISH_BONES_ICON,
	Foil_Fish = FOIL_FISH_ICON,
	Jelly_Fish = JELLY_FISH_ICON,
	Legendary_Fish = LEGENDARY_FISH_ICON,
	Seabass_Fish = SEABASS_FISH_ICON,
	Tilapia_Fish = TILAPIA_FISH_ICON,
	Meat = MEAT_ICON,
	Potato = POTATO_ICON,
	Beet = BEET_ICON,
	Potato_Cooked = POTATO_COOKED_ICON,
	Beet_Cooked = BEET_COOKED_ICON,
	-- Cooked fish variants need EXPLICIT keys here: rebuildSlotData
	-- iterates RESOURCE_ICONS by its real keys to build resource
	-- slots, and a metatable __index isn't iterable. Reuse the raw
	-- fish icon for now (swap to a cooked-fish icon later).
	Blue_Fish_Cooked      = BLUE_FISH_COOKED_ICON,
	Carp_Fish_Cooked      = CARP_FISH_COOKED_ICON,
	Foil_Fish_Cooked      = FOIL_FISH_ICON,
	Jelly_Fish_Cooked     = JELLY_FISH_ICON,
	Legendary_Fish_Cooked = LEGENDARY_FISH_COOKED_ICON,
	Seabass_Fish_Cooked   = SEABASS_FISH_ICON,
	Tilapia_Fish_Cooked   = TILAPIA_FISH_COOKED_ICON,
	Meat_Cooked           = MEAT_COOKED_ICON,
	-- Fruits dropped from trees (Banana/Coconut) and the new
	-- hand-harvested Pineapple, plus the matching seeds the player
	-- can replant.
	Banana          = "rbxassetid://95041000167181",
	Banana_Seed     = "rbxassetid://73140419103065",
	Coconut         = "rbxassetid://120321968340866",
	Coconut_Seed    = "rbxassetid://138995623166184",
	Pineapple       = "rbxassetid://93324727574975",
	Pineapple_Seed  = "rbxassetid://128520746024640",
	-- Bush seed (harvested from a Pineapple bush). Stored in the
	-- regular inventory; equipping it spawns a placement Tool that
	-- drives CupPurifier's ghost just like the berry bush.
	Pineapple_Bush_Seed = "rbxassetid://128520746024640",
	-- ЭКИПИРОВКА. ⚠️ Запись обязана быть ЗДЕСЬ: слоты инвентаря строятся обходом
	-- ИМЕННО этой таблицы (см. rebuildSlotData), и предмета, которого в ней нет,
	-- в инвентаре просто не появится — сколько бы его ни лежало на сервере.
	DivingMask = "rbxassetid://79806920407397",
	-- Гвозди: куются из хлама (см. InventoryCrafting, выход 3 шт.)
	Nail = "rbxassetid://82878494424821",
	-- Мусор с моря: до этой записи ресурс копился на сервере, но в сетке
	-- инвентаря был НЕВИДИМ (слоты строятся обходом именно этой таблицы)
	Rubbish = "rbxassetid://134054228230432",
	-- Плавильня: водоросли — сырьё, клей — продукт их переплавки
	Seaweed = "rbxassetid://135792112167502",
	Glue    = "rbxassetid://130539720764714",
}

-- Cooked fish ("<fish>_Cooked") reuse their raw fish's icon so a newly
-- adapted fish needs no extra entry here.
setmetatable(RESOURCE_ICONS, {
	__index = function(t, k)
		if type(k) == "string" and #k > 7 and k:sub(-7) == "_Cooked" then
			return rawget(t, k:sub(1, #k - 7))
		end
		return nil
	end,
})

local TOOL_ICONS = {
	["Hammer"] = "rbxassetid://86264127232874",
	["Pick-Axe"] = "rbxassetid://102411845666126",
	["Cup"] = "rbxassetid://99673504095026",
	["Destitalor"] = "rbxassetid://90221080738714",
	["Furnace"] = "rbxassetid://111493193184870",
	["bush"] = "rbxassetid://93957489757544",

	["Machete"] = "rbxassetid://92926554091794",
	["Wood_Knife"] = "rbxassetid://110032041583533",
	["WorkBench"] = "rbxassetid://116083064101694",
	["Bed"] = "rbxassetid://97461315404202",
	["Garden"] = "rbxassetid://137766871451752",
	["Bed_T"] = "rbxassetid://137766871451752",
	["Paddle"] = "rbxassetid://93358108538106",
	["Sawmill"] = "rbxassetid://75858978626954",
	["Shovel"] = "rbxassetid://123765089142597",
	["Hook"] = "rbxassetid://110032041583533",
	["Axe"] = "rbxassetid://110032041583533",
	-- Stone_Axe inherits the Pick-Axe icon as a placeholder until a
	-- dedicated axe asset lands; the equipped Tool's TextureId
	-- override on line 775 takes precedence in the hotbar anyway.
	["Stone_Axe"] = "rbxassetid://112306255674133",
	["Fire_Axe"] = "rbxassetid://71159823302777",
	["Flamethrower"] = "rbxassetid://115269318677272",
	["[GRAPES]"] = "rbxassetid://137478230275649",
	["Grapes"] = "rbxassetid://137478230275649",
	["FishingRod"] = "rbxassetid://105180666555503",
	["Injector"] = "rbxassetid://81132472504693",
	["EmptyCapsule"] = "rbxassetid://116714708119585",
	["FullCapsule"] = "rbxassetid://132749498016835",
	["Phone"] = "rbxassetid://123703470055474",
	["Anchor_part"] = "rbxassetid://120414328052740",
	["bag_empty_2"] = BAG_EMPTY_ICON,
	["Sand Bag"]    = "rbxassetid://107012847180882",
	["Plastic_canister"] = "rbxassetid://131765057486498",
	-- Seed-as-Tool variants. The Tool templates the user authored
	-- carry these names; the icons mirror the matching seed resource
	-- so they read the same as the inventory stack form.
	["Palm_seed"]           = "rbxassetid://138995623166184",
	["Banana_Seed"]         = "rbxassetid://73140419103065",
	["Pineapple_seed"]      = "rbxassetid://128520746024640",
	-- Bush-seed Tool variant — same art as the tree seed; the suffix
	-- differentiates "plant a bush on a Garden" from "plant a tree
	-- sapling on Bed_T". Without this entry the slot fell back to
	-- LOG_ICON when the Tool was rebuilt into a slot.
	["Pineapple_Bush_Seed"] = "rbxassetid://128520746024640",
	-- Food Tools that the player can temporarily equip from the
	-- main-inventory resource stack. Same icons as the resource
	-- form so the hotbar slot stays visually consistent.
	["Banana"]         = "rbxassetid://95041000167181",
	["Coconut"]        = "rbxassetid://120321968340866",
	["Pineapple"]      = "rbxassetid://93324727574975",
	-- Постройки-заглушки в руках: без записи слот брал LOG_ICON
	["Boat_3x"]           = "rbxassetid://84900623714454",
	["Raft_grill"]        = "rbxassetid://86941334995718",
	["Raft_grill_barrel"] = "rbxassetid://92828269363847",
	["Raft_smelter"]      = "rbxassetid://111493193184870",
}

-- Sand Bag fill stages — one table per resource the bag can hold.
-- Mirrors SandBagUI.client.lua's STAGES_BY_CONTENT exactly so the
-- hotbar icon always matches the inspector. Empty (pct = 0) is the
-- same image across types so picking either table is fine for an
-- empty bag.
local BAG_STAGES_BY_CONTENT = {
	Sand = {
		{ pct =   0, image = "rbxassetid://107012847180882" },
		{ pct =  10, image = "rbxassetid://87535824644391"  },
		{ pct =  30, image = "rbxassetid://102984915310557" },
		{ pct =  50, image = "rbxassetid://132918131694676" },
		{ pct =  70, image = "rbxassetid://135545427179049" },
		{ pct = 100, image = "rbxassetid://76170913773356"  },
	},
	Clay = {
		{ pct =   0, image = "rbxassetid://107012847180882" },
		{ pct =  10, image = "rbxassetid://137121316772176" },
		{ pct =  30, image = "rbxassetid://94079996711573"  },
		{ pct =  50, image = "rbxassetid://71260002598684"  },
		{ pct =  70, image = "rbxassetid://85470636629483"  },
		{ pct = 100, image = "rbxassetid://115968010442225" },
	},
}

local function isSandBagTool(tool)
	if not tool or not tool:IsA("Tool") then return false end
	local a = tool.Name:lower():gsub("[_%s]", "")
	return a == "sandbag"
end

local function getSandBagIcon(tool)
	if not tool then return nil end
	local fill    = tool:GetAttribute("SandFill")    or 0
	local content = tool:GetAttribute("BagContent")
	local stages  = BAG_STAGES_BY_CONTENT[content] or BAG_STAGES_BY_CONTENT.Sand
	for i = #stages, 1, -1 do
		if fill >= stages[i].pct then
			return stages[i].image
		end
	end
	return stages[1].image
end

-- Forward-declared so the SandFill listener (created early) can reach
-- the in-place icon swapper (defined later, because it has to read
-- `slotData` and `hotbarGui` which haven't been declared yet at this
-- point in the file).
local refreshSandBagIconInPlace

-- Tools we've already wired a SandFill listener on, so we don't stack
-- N connections on the same instance across rebuilds.
local sandBagHooked = {}
local function ensureSandBagHook(tool)
	if not tool or sandBagHooked[tool] then return end
	if not isSandBagTool(tool) then return end
	sandBagHooked[tool] = true
	local function onChange()
		-- Don't trigger a full slot rebuild — that destroys the icon
		-- and creates a new one, which leaves a one-frame gap. Stack
		-- the new texture on top of the old icon, wait a render, then
		-- drop the underlying one. The two stages line up exactly, so
		-- the only thing that visually changes is the sand level (or
		-- the resource type, on a Sand ↔ Clay swap).
		if refreshSandBagIconInPlace then
			refreshSandBagIconInPlace(tool)
		end
	end
	-- Both attributes can change the icon: SandFill drives the stage,
	-- BagContent drives which texture family (sand vs clay) we sample
	-- from. Re-render on either.
	tool:GetAttributeChangedSignal("SandFill"):Connect(onChange)
	tool:GetAttributeChangedSignal("BagContent"):Connect(onChange)
	tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(game) then
			sandBagHooked[tool] = nil
		end
	end)
end

-- Forward-declared so functions above line 1585 (quickTransfer,
-- drag-drop handlers, etc.) can reference it via the same upvalue
-- that gets assigned later. Without this, those call sites resolve
-- against a nil global and throw 'attempt to call a nil value'.
local syncSlotLayoutToServer

-- ИКОНКА С САМОЙ МОДЕЛИ, когда своей картинки для предмета ещё нет. Берём то, что
-- уже лежит в ReplicatedStorage: у Tool это TextureId, у аксессуара — текстура его
-- Handle. Лучше узнаваемая картинка вещи, чем пустой квадрат в слоте.
local iconFromModelCache = {}
local function resolveItemIcon(itemName)
	if iconFromModelCache[itemName] ~= nil then return iconFromModelCache[itemName] end
	local found = ""
	local template = ReplicatedStorage:FindFirstChild(itemName)
		or ReplicatedStorage:FindFirstChild(itemName, true)
	if template then
		if template:IsA("Tool") and template.TextureId ~= "" then
			found = template.TextureId
		else
			local handle = template:FindFirstChild("Handle")
				or template:FindFirstChildWhichIsA("MeshPart", true)
			if handle and handle:IsA("MeshPart") and handle.TextureID ~= "" then
				found = handle.TextureID
			else
				-- старые аксессуары носят текстуру не на детали, а на SpecialMesh
				local mesh = template:FindFirstChildWhichIsA("SpecialMesh", true)
				if mesh and mesh.TextureId ~= "" then found = mesh.TextureId end
			end
		end
	end
	iconFromModelCache[itemName] = found
	return found
end

-- Exposed so the mercenary backpack UI can reuse the same icons.
_G.GetItemIcon = function(itemName)
	if not itemName then return "" end
	local icon = RESOURCE_ICONS[itemName] or TOOL_ICONS[itemName] or ""
	if icon == "" then icon = resolveItemIcon(itemName) end
	return icon
end

local inventory = {Log = 0, Plastic = 0, Stone = 0, Iron_Ore = 0, Iron_Ingot = 0, Leaves = 0}
local recipes = {}
local selectedRecipe = nil
local selectedCategory = nil
local detailOverlay = nil
local categoryOverlay = nil
-- ⚠️ Экипировки здесь НЕТ намеренно. Сначала она была вкладкой, и это оказалось
-- ошибкой: слоты открывались поверх инвентаря, то есть ровно тогда, когда вещь
-- перетаскивать было уже неоткуда. Четыре слота живут прямо в панели инвентаря,
-- справа от сетки (см. buildEquipmentColumn) — как в RAFT.
-- DecorPack — вкладка пака декора: видна только владельцу (атрибут DecorPack_Default)
local CATEGORIES = {"Tools", "Technology", "Decor", "Misc", "Resources", "DecorPack"}
-- Ключ категории приходит с сервера в рецепте (recipe.category) и по нему идёт
-- фильтрация, поэтому переводим ТОЛЬКО подпись, а сам ключ оставляем английским.
local CATEGORY_RU = {
	Tools      = "Инструменты",
	Technology = "Технологии",
	Decor      = "Декор",
	DecorPack  = "Пак: Дефолт",
	Misc       = "Разное",
	Resources  = "Ресурсы",
}
local function catLabel(cat) return CATEGORY_RU[cat] or cat end
-- Наружу — для подсказок квестов: они ведут игрока по вкладкам и должны называть
-- их так же, как написано на самой вкладке. Иначе в баннере всплывает английский
-- ключ («Открой вкладку крафта «Misc»»), которого в интерфейсе уже нет.
_G.CraftCategoryLabel = catLabel

-- ⚠️ ОБЪЯВЛЕНО ЗДЕСЬ, А ЗАПОЛНЯЕТСЯ НИЖЕ: индексы слотов экипировки нужны
-- перетаскиванию (findSlotUnderMouse/endDrag), а оно стоит ВЫШЕ самой панели.
-- В Lua local виден только ниже своего объявления — снизу эти имена оказались бы
-- глобальными и nil.
local EQUIP_SLOT_BASE = 200   -- свои индексы, чтобы не пересечься с 1..28
local equipSlotFrames = {}    -- [индекс] = кнопка слота
local isOpen = false
local screenGui = nil
local hotbarGui = nil

-- Палитра «Океан» из редизайна (спека: панель #54A7EC→#3A7FD0, рамка #1C4F8F,
-- слот #A9D6F7, золото #FFD95A/#F5B73C, цена #4CD964/#FF6B5A). Ключи прежние —
-- вся логика перекрашивается через эту таблицу.
local COLORS = {
	panelTop = Color3.fromHex("54A7EC"),    -- верх градиента панели
	panelBg = Color3.fromHex("3A7FD0"),     -- низ градиента панели
	panelBorder = Color3.fromHex("1C4F8F"),
	-- Слоты — песочная спека: занятый FBD9A4→F2C57E / B5762B; пустой 35% / 7A4310 50%;
	-- заблокированный rgba(70,40,12,0.45) + полосы; выбранный — золото F5C95C.
	slotTop = Color3.fromHex("FBD9A4"),
	slotBottom = Color3.fromHex("F2C57E"),
	slotFrame = Color3.fromHex("B5762B"),
	slotEmptyFrame = Color3.fromHex("7A4310"),
	slotLockedBg = Color3.fromRGB(70, 40, 12),
	slotSelected = Color3.fromHex("2E86E8"), -- выбранный в руку — ярко-синяя рамка/свечение
	titleText = Color3.fromRGB(255, 255, 255),
	lightText = Color3.fromRGB(255, 255, 255),
	craftPanelBg = Color3.fromHex("3A7FD0"),
	craftItemBg = Color3.fromHex("2F6CB8"),
	craftItemHover = Color3.fromHex("4E92DC"),
	affordable = Color3.fromHex("4CD964"),
	notAffordable = Color3.fromHex("FF6B5A"),
	hotbarBg = Color3.fromHex("3A7FD0"),
	separator = Color3.fromHex("1C4F8F"),
	equipped = Color3.fromHex("F5B73C"),    -- активный слот/вкладка — золото
	goldFrame = Color3.fromHex("B07A14"),
}
-- Пустой слот — заливка 35% прозрачности (по споке); занятый — 0.
local SLOT_EMPTY_TRANSPARENCY = 0.35

-- Две палитры слотов: СЕТКА ИНВЕНТАРЯ — синяя (под панель «Океан»), ХОТБАР —
-- песочная спека с прозрачностью (лёгкий вид «без подложки», не выделяется).
local SLOT_STYLE_GRID = {
	top = Color3.fromHex("BCE0F9"),
	bottom = Color3.fromHex("A9D6F7"),
	frame = Color3.fromHex("1C4F8F"),
	emptyFrame = Color3.fromHex("1C4F8F"),
	filledT = 0,    -- занятый — плотный
	emptyT = 0.35,  -- пустой — 35%
}
local SLOT_STYLE_HOTBAR = {
	top = Color3.fromHex("BCE0F9"),    -- голубой, как сетка инвентаря
	bottom = Color3.fromHex("A9D6F7"),
	frame = Color3.fromHex("1C4F8F"),
	emptyFrame = Color3.fromHex("1C4F8F"),
	filledT = 0.25, -- лёгкая прозрачность даже у занятых (бар не выделяется)
	emptyT = 0.5,
}

-- Базовая отделка слота под палитру pal: градиент (SlotGrad), скругление 12,
-- рамка 3 и скрытый слой диагональных полос (LockStripes) для заблокированного.
-- Полосы — тёмный слой с UIGradient 45°, где прозрачность чередуется 0/1.
local function styleSlotBase(slot, pal)
	slot.BackgroundColor3 = Color3.new(1, 1, 1) -- белый под градиент (он умножается)
	slot.BorderSizePixel = 0

	local grad = Instance.new("UIGradient")
	grad.Name = "SlotGrad"
	grad.Color = ColorSequence.new(pal.top, pal.bottom)
	grad.Rotation = 90
	grad.Parent = slot

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = slot

	local stroke = Instance.new("UIStroke")
	stroke.Color = pal.emptyFrame
	stroke.Thickness = 3
	stroke.Transparency = 0.5
	stroke.Parent = slot

	local stripes = Instance.new("Frame")
	stripes.Name = "LockStripes"
	stripes.Size = UDim2.fromScale(1, 1)
	stripes.BackgroundColor3 = Color3.fromRGB(36, 20, 6)
	stripes.BackgroundTransparency = 0.45
	stripes.BorderSizePixel = 0
	stripes.Visible = false
	stripes.Parent = slot

	local stripesCorner = Instance.new("UICorner")
	stripesCorner.CornerRadius = UDim.new(0, 12)
	stripesCorner.Parent = stripes

	local sg = Instance.new("UIGradient")
	sg.Rotation = 45
	-- 4 тёмных полосы через прозрачные промежутки. ЛИМИТ NumberSequence — 20
	-- keypoints (21 валил NumberSequence.new ошибкой, обрывая сборку слотов).
	local keypoints = {}
	for k = 0, 3 do
		local a = k * 0.25
		table.insert(keypoints, NumberSequenceKeypoint.new(a, 1))
		table.insert(keypoints, NumberSequenceKeypoint.new(a + 0.124, 1))
		table.insert(keypoints, NumberSequenceKeypoint.new(a + 0.125, 0))
		table.insert(keypoints, NumberSequenceKeypoint.new(a + 0.249, 0))
	end
	table.insert(keypoints, NumberSequenceKeypoint.new(1, 0))
	sg.Transparency = NumberSequence.new(keypoints) -- 17 точек
	sg.Parent = stripes
end

-- Применить состояние слота по споке (в палитре pal): locked → тёмный с полосами;
-- selected → золотая рамка; иначе занятый/пустой (свои прозрачность и рамка).
local function applySlotState(slot, hasItem, selected, locked, pal)
	pal = pal or SLOT_STYLE_GRID
	local stroke = slot:FindFirstChildWhichIsA("UIStroke")
	local grad = slot:FindFirstChild("SlotGrad")
	local stripes = slot:FindFirstChild("LockStripes")
	if locked then
		if grad then grad.Enabled = false end
		slot.BackgroundColor3 = COLORS.slotLockedBg
		slot.BackgroundTransparency = 0.55 -- rgba(...,0.45)
		if stripes then stripes.Visible = true end
		if stroke then
			stroke.Color = COLORS.slotEmptyFrame
			stroke.Thickness = 3
			stroke.Transparency = 0.6
		end
		return
	end
	if grad then grad.Enabled = true end
	slot.BackgroundColor3 = Color3.new(1, 1, 1)
	slot.BackgroundTransparency = hasItem and pal.filledT or pal.emptyT
	if stripes then stripes.Visible = false end
	if stroke then
		if selected then
			stroke.Color = COLORS.slotSelected
			stroke.Thickness = 4
			stroke.Transparency = 0
		elseif hasItem then
			stroke.Color = pal.frame
			stroke.Thickness = 3
			stroke.Transparency = 0
		else
			stroke.Color = pal.emptyFrame
			stroke.Thickness = 3
			stroke.Transparency = 0.5
		end
	end
end

local HOTBAR_SLOTS = 8
local GRID_SLOTS = 20
local TOTAL_SLOTS = HOTBAR_SLOTS + GRID_SLOTS
local SLOT_SIZE = 80
local SLOT_PAD = 8

--[[ ⚠️ У ХОТБАРА СВОЙ РАЗМЕР СЛОТА, А НЕ ОБЩИЙ С СЕТКОЙ.
     SLOT_SIZE выше задаёт клетку и в ряду быстрых слотов, и в окне инвентаря
     (там из него считаются gridWidth/gridHeight). Увеличить его «ради хотбара»
     значило бы заодно раздуть само окно рюкзака.
     Поэтому у ряда своя пара чисел: клетка чуть крупнее и отступ от низа
     побольше — панель заметнее и не липнет к краю экрана. ]]
local HOTBAR_SLOT_SIZE = 86
local HOTBAR_BOTTOM    = 28
local COLS = 5
local BASE_UNLOCKED_SLOTS = HOTBAR_SLOTS + 5 -- hotbar + first grid row until Strength unlocks more

-- ── Responsive UI scaling ─────────────────────────────────────────────
-- The inventory / hotbar / crafting UI is laid out in pixel offsets at a
-- reference resolution. On smaller screens (phones, vertical windows,
-- studio emulator) we attach a `UIScale` that shrinks everything so the
-- combined block + hotbar always fit. On large screens we never scale
-- above 1.0 so the UI doesn't grow absurdly large on 4K monitors.
local UI_REF_WIDTH  = 1280   -- combined UI (craft + inventory) is ~700 wide
local UI_REF_HEIGHT = 720    -- hotbar + inventory panel comfortably fit
local UI_MIN_SCALE  = 0.45
local UI_MAX_SCALE  = 1.0

local function computeUIScale()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(UI_REF_WIDTH, UI_REF_HEIGHT)
	local s = math.min(vp.X / UI_REF_WIDTH, vp.Y / UI_REF_HEIGHT)
	return math.clamp(s, UI_MIN_SCALE, UI_MAX_SCALE)
end

-- Every ScreenGui that holds part of the inventory UI should be
-- registered here so the scale stays in sync when the viewport resizes.
local scaledGuis = setmetatable({}, { __mode = "k" })

--[[ ⚠️ ЗДЕСЬ МАСШТАБ НАМЕРЕННО НЕ ПРИМЕНЯЕТСЯ, И ЭТО НЕ ОШИБКА.
     UIScale на ScreenGui не действует — это слой, а не GuiObject. Я попробовал
     чинить «по-честному»: вешать масштаб на детей слоя. Инвентарь от этого
     развалился — окно крафта и окно рюкзака лежат в одном слое РЯДОМ и стояли
     вплотную; каждое сжалось вокруг своего якоря, и между ними появилась щель.
     Склеены они соседством, а не общим контейнером, поэтому масштабировать их
     можно только ВМЕСТЕ — то есть завернув в один Frame, чего эта функция не
     делает и делать не должна.
     Оставляем как было: число считается, но ни на что не влияет. Тем, кому
     масштаб действительно нужен (панель быстрых слотов), он выдаётся отдельно —
     прямо на их собственный Frame, см. hotbar ниже. ]]
local function attachResponsiveScale(gui)
	if not gui then return end
	local scaleObj = gui:FindFirstChildOfClass("UIScale")
	if not scaleObj then
		scaleObj = Instance.new("UIScale")
		scaleObj.Parent = gui
	end
	scaleObj.Scale = computeUIScale()
	scaledGuis[gui] = { scaleObj }
end

_G.AttachInventoryUIScale = attachResponsiveScale

do
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local s = computeUIScale()
			for gui, objs in pairs(scaledGuis) do
				if gui and gui.Parent and type(objs) == "table" then
					for _, scaleObj in ipairs(objs) do
						if scaleObj.Parent then scaleObj.Scale = s end
					end
				end
			end
		end)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local newCam = workspace.CurrentCamera
		if newCam then
			newCam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				local s = computeUIScale()
				for gui, objs in pairs(scaledGuis) do
					if gui and gui.Parent and type(objs) == "table" then
						for _, scaleObj in ipairs(objs) do
							if scaleObj.Parent then scaleObj.Scale = s end
						end
					end
				end
			end)
		end
	end)
end

-- How many total slots (hotbar + grid) the player currently has unlocked.
-- Driven by `Characteristics.UnlockedInventorySlots` which is computed from
-- the player's Strength stat by Strength.server.lua. Defaults to the
-- base 13 so the UI is usable before the value replicates.
local unlockedSlots = BASE_UNLOCKED_SLOTS

-- Populated while the inventory window is built. Each entry is a
-- { button = TextButton, stroke = UIStroke } record for the grid slot
-- at `HOTBAR_SLOTS + i`. Used by applyUnlockedSlots() to repaint the
-- locked / unlocked visuals whenever the unlocked-count changes.
local gridSlotVisuals = {}
local lockedOverlayLabel = nil

local function isSlotLocked(globalIdx)
	return globalIdx > unlockedSlots
end

-- Highest grid slot index (global) that writes are allowed to touch.
-- Used to clamp `findEmptySlot` / distribution ranges so that new items
-- never land in a locked slot.
local function maxWritableSlot()
	return math.min(TOTAL_SLOTS, unlockedSlots)
end

-- Repaints every grid slot for the current `unlockedSlots` count and
-- positions the big "NEED STRENGTH" overlay over the locked region.
-- Called whenever `Characteristics.UnlockedInventorySlots` changes and
-- once after the inventory UI is built.
local function applyUnlockedSlots()
	if #gridSlotVisuals == 0 then return end

	for i, rec in ipairs(gridSlotVisuals) do
		local globalIdx = HOTBAR_SLOTS + i
		local locked    = globalIdx > unlockedSlots
		if rec.button then
			-- hasItem уточнит ближайший renderAllSlots
			applySlotState(rec.button, false, false, locked, SLOT_STYLE_GRID)
			rec.button.AutoButtonColor = false
			rec.button.Active          = not locked
		end
	end

	if lockedOverlayLabel then
		-- Only span rows whose slots are ALL locked. A row that's still
		-- partially usable keeps its normal per-slot dimming instead of
		-- being covered by the banner (otherwise the banner would
		-- obscure the slots the player can still interact with).
		--
		-- The banner is only shown while the player is still at the
		-- base unlock count (Strength 0). The instant they upgrade
		-- Strength to level 2 and earn their first extra slot, the
		-- banner disappears for good — by then they already know how
		-- to get more slots and the reminder becomes visual noise.
		local unlockedGrid      = math.max(unlockedSlots - HOTBAR_SLOTS, 0)
		local firstFullLockRow  = math.ceil(unlockedGrid / COLS)
		local totalRows         = math.ceil(GRID_SLOTS / COLS)
		local atBaseUnlock      = unlockedSlots <= BASE_UNLOCKED_SLOTS

		-- ⚠️ ТЕПЕРЬ ВИСИТ, ПОКА ЕСТЬ ЗАКРЫТЫЙ РЯД: в ней не загадка «нужна сила»,
		-- а сколько силы осталось до следующей ячейки — полезно на любом уровне
		local _ = atBaseUnlock
		if firstFullLockRow < totalRows then
			local rows = totalRows - firstFullLockRow
			local y = SLOT_PAD + firstFullLockRow * (SLOT_SIZE + SLOT_PAD)
			local h = rows * (SLOT_SIZE + SLOT_PAD) - SLOT_PAD
			lockedOverlayLabel.Position = UDim2.new(0, SLOT_PAD, 0, y)
			lockedOverlayLabel.Size     = UDim2.new(1, -SLOT_PAD * 2, 0, h)
			lockedOverlayLabel.Visible  = true
		else
			lockedOverlayLabel.Visible = false
		end
	end
end

-- ─── Unified Slot Data ───
-- Slots 1..8 = hotbar, slots 9..28 = inventory grid
local slotData = {}
_G.InventorySlotData = slotData
local slotsInitialized = false

-- Overlay-then-remove icon swap for a Sand Bag tool whose SandFill
-- attribute changed. Sequence:
--   1. SandFill changes → schedule the swap with task.delay so the
--      texture has a generous moment to finish decoding into the GPU
--      cache before we put it on screen.
--   2. After the delay, clone the existing ItemIcon, point the clone
--      at the new stage texture and parent it ON TOP of the old one.
--   3. Wait ~3 render frames (well past any decode hiccup), then
--      destroy the underlying icon and rename / re-Z the clone so it
--      becomes the new canonical ItemIcon.
-- The two stages line up exactly (same anchor / size / position), so
-- the only thing the player visually sees change is the sand level.
local SWAP_DELAY_SEC   = 0.1   -- delay between attribute change and overlay
local POST_OVERLAY_GAP = 0.10  -- delay between overlay and old-icon removal

refreshSandBagIconInPlace = function(tool)
	if not tool or not hotbarGui then return end
	local bar = hotbarGui:FindFirstChild("Hotbar")
	if not bar then return end

	for i = 1, HOTBAR_SLOTS do
		local data = slotData[i]
		if data and data.type == "tool" and data.toolInst == tool then
			local slot = bar:FindFirstChild("HotbarSlot_" .. i)
			if not slot then return end
			local oldIcon = slot:FindFirstChild("ItemIcon")
			if not oldIcon or not oldIcon:IsA("ImageLabel") then return end

			local nextImage = getSandBagIcon(tool)
			if not nextImage or nextImage == oldIcon.Image then return end

			task.delay(SWAP_DELAY_SEC, function()
				-- Re-check between the delay and the swap: the slot, the
				-- icon or the tool itself might be gone by now.
				if not oldIcon or not oldIcon.Parent then return end
				if not slot or not slot.Parent then return end
				if data ~= slotData[i] or data.toolInst ~= tool then return end

				local stillNext = getSandBagIcon(tool)
				if not stillNext or stillNext == oldIcon.Image then return end

				local origZ    = oldIcon.ZIndex
				local newIcon  = oldIcon:Clone()
				newIcon.Name   = "ItemIcon_swap"
				newIcon.Image = stillNext
				newIcon.ZIndex = origZ + 1
				newIcon.Parent = slot

				task.delay(POST_OVERLAY_GAP, function()
					if oldIcon and oldIcon.Parent then oldIcon:Destroy() end
					if newIcon and newIcon.Parent then
						newIcon.Name   = "ItemIcon"
						newIcon.ZIndex = origZ
					end
				end)
			end)
			return
		end
	end
end

-- ─── Drag ───
local dragState = {
	active = false,
	sourceSlot = nil,
	data = nil,
	ghost = nil,
	ghostGui = nil,
	didDrag = false,
	startPos = nil,
	splitMode = false, -- right-click: move only 1 item
}
local DRAG_THRESHOLD = 5

-- ─── Tooltip ───
local tooltipGui = nil
local tooltipLabel = nil

-- ПОДПИСЬ ПРЕДМЕТА — НА ЯЗЫКЕ ИГРОКА. Здесь стояла таблица английских названий
-- («Wood Knife», «Workbench»), и в подсказке игрок видел служебный ключ на чужом
-- языке. Теперь названия берутся из общего словаря ItemNamesRu, а он прогоняет
-- готовую строку через переводчик Roblox: русский по умолчанию, другие языки —
-- если у опыта включён автоперевод.
local function nameFromRecipes(key)
	for _, recipe in ipairs(recipes or {}) do
		if recipe.name == key and recipe.displayName and recipe.displayName ~= "" then
			return recipe.displayName
		end
	end
	return nil
end

local function getDisplayName(data)
	if not data then return nil end
	-- Blood capsules carry a per-NPC-type label in data.displayName
	-- (e.g. "Pirate Blood", "Infected Military Blood") so the tooltip shows
	-- the differentiated name instead of the generic "FullCapsule".
	if data.displayName and data.displayName ~= "" then
		return ItemNamesRu.localize(data.displayName)
	end
	local key = data.name or data.toolName
	if not key then return nil end
	-- рецепты держат свои русские подписи — берём их, если словарь ключа не знает
	local name = ItemNamesRu.lookup(key) or nameFromRecipes(key) or ItemNamesRu.pretty(key)
	return ItemNamesRu.localize(name)
end

-- Shared with the chest / mercenary backpack UIs so their hover
-- tooltips use the same dictionary as the main inventory.
_G.GetItemDisplayName = function(name)
	if typeof(name) ~= "string" or name == "" then return nil end
	local pretty = ItemNamesRu.lookup(name) or nameFromRecipes(name) or ItemNamesRu.pretty(name)
	return ItemNamesRu.localize(pretty)
end

local function ensureTooltipGui()
	if tooltipGui and tooltipGui.Parent then return end
	tooltipGui = Instance.new("ScreenGui")
	tooltipGui.Name = "InventoryTooltip"
	tooltipGui.ResetOnSpawn = false
	tooltipGui.IgnoreGuiInset = true
	tooltipGui.DisplayOrder = 200
	tooltipGui.Enabled = false
	tooltipGui.Parent = playerGui

	tooltipLabel = Instance.new("TextLabel")
	tooltipLabel.Name = "Label"
	tooltipLabel.AutomaticSize = Enum.AutomaticSize.XY
	tooltipLabel.Size = UDim2.new(0, 0, 0, 0)
	tooltipLabel.BackgroundColor3 = COLORS.panelBorder
	tooltipLabel.BackgroundTransparency = 0.05
	tooltipLabel.BorderSizePixel = 0
	tooltipLabel.TextColor3 = Color3.new(1, 1, 1)
	tooltipLabel.Font = Enum.Font.GothamBold
	tooltipLabel.TextSize = 14
	tooltipLabel.Text = ""
	tooltipLabel.Parent = tooltipGui

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = tooltipLabel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = tooltipLabel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex("0F2C52")
	stroke.Thickness = 2
	stroke.Parent = tooltipLabel
end

local function hideTooltip()
	if tooltipGui then tooltipGui.Enabled = false end
end

-- Short-lived popup used when the player tries to drop an item into a
-- locked inventory slot. Lives in its own ScreenGui so it doesn't mess
-- with the regular hover tooltip, and auto-destroys after fading out.
local function showLockedDropMessage(mousePos)
	local gui = Instance.new("ScreenGui")
	gui.Name = "LockedSlotPopup"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 250
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundColor3 = Color3.fromRGB(40, 15, 15)
	label.BackgroundTransparency = 0.1
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(255, 220, 180)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Text = "Ячейка закрыта, повышай силу"
	label.Parent = gui

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft   = UDim.new(0, 10)
	pad.PaddingRight  = UDim.new(0, 10)
	pad.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(180, 90, 90)
	stroke.Thickness = 1.5
	stroke.Parent = label

	-- Position near the mouse; flip below if it would overflow the top.
	label.Position = UDim2.fromOffset(mousePos.X + 14, mousePos.Y - 34)
	task.defer(function()
		if label.AbsolutePosition.Y < 4 then
			label.Position = UDim2.fromOffset(mousePos.X + 14, mousePos.Y + 18)
		end
	end)

	task.delay(0.9, function()
		if not gui.Parent then return end
		local t = TweenService:Create(
			label,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1, TextTransparency = 1 }
		)
		stroke.Enabled = false
		t:Play()
		t.Completed:Connect(function()
			gui:Destroy()
		end)
	end)
end

local function updateTooltipPosition(mousePos)
	if not tooltipGui or not tooltipGui.Enabled or not tooltipLabel then return end
	local x = mousePos.X + 14
	local y = mousePos.Y - tooltipLabel.AbsoluteSize.Y - 10
	if y < 4 then y = mousePos.Y + 18 end
	tooltipLabel.Position = UDim2.fromOffset(x, y)
end

-- Returns true when another full-screen overlay is on top of the
-- inventory (phone menu, shop, etc.) and hotbar hover tooltips
-- would visually bleed through. PhoneMenu publishes _G.PhoneScreenGui
-- which flips .Enabled on open/close, so checking that is enough for
-- the current UI set; future overlays can hook the same handshake.
local function isHoverBlockingOverlayOpen()
	local phone = _G.PhoneScreenGui
	if phone and phone:IsA("ScreenGui") and phone.Enabled then
		return true
	end
	-- ⚠️ РЕЖИМ СТРОЙКИ — ТАКОЙ ЖЕ ПЕРЕКРЫВАЮЩИЙ СЛОЙ, КАК ТЕЛЕФОН.
	-- Он гасит весь HUD, включая хотбар. Если курсор в этот момент стоял над
	-- слотом, MouseLeave не придёт НИКОГДА — гуй исчез, — и подсказка остаётся
	-- висеть и ездить за курсором уже после выхода из стройки. Ровно тот случай,
	-- ради которого строкой ниже сделано самоизлечение, просто про стройку тогда
	-- ещё не знали.
	local build = _G.BuildingScreenGui
	if build and build:IsA("ScreenGui") and build.Parent then
		return true
	end
	return false
end

local function showTooltipForSlot(slotIndex)
	-- Don't show while the phone (or any future overlay) is covering
	-- the playfield — the cursor may still technically be over a
	-- hotbar slot, but the tooltip would render on top of the overlay.
	if isHoverBlockingOverlayOpen() then
		hideTooltip()
		return
	end
	local data = slotData[slotIndex]
	local name = getDisplayName(data)
	if not name then
		hideTooltip()
		return
	end
	-- переносимые постройки (RaftRelocate): у них иконка, подпись при наведении не нужна
	local key = data and (data.name or data.toolName)
	if key == "OilBarrel_SCENE" or key == "Monolit_Aquamen" or key == "Raft_repair_station" then
		hideTooltip()
		return
	end
	if dragState.active then
		hideTooltip()
		return
	end
	-- Don't show tooltip while crafting overlays cover the inventory
	if categoryOverlay or detailOverlay then
		hideTooltip()
		return
	end
	ensureTooltipGui()
	tooltipLabel.Text = name
	tooltipGui.Enabled = true
	updateTooltipPosition(UserInputService:GetMouseLocation())
end

-- ─── Helpers ───

-- Часть рецептов стоит ещё и освобождённых жителей. Они лежат не в инвентаре, а
-- в атрибуте игрока (его ведёт VillagersCurrency), поэтому проверяются отдельно.
local VILLAGER_ICON = "rbxassetid://107784608579591"

local function villagersHave()
	return player:GetAttribute("Villagers") or 0
end

-- Часть рецептов съедает ЦЕЛЫЙ ПРЕДМЕТ из рюкзака (огнемёт — канистру, вместе
-- с её остатком топлива). Такой предмет не ресурс, в inventory его нет — ищем
-- сам Tool и в руках, и в рюкзаке.
local function findCostTool(name)
	for _, where in ipairs({ player.Character, player:FindFirstChildOfClass("Backpack") }) do
		if where then
			for _, t in ipairs(where:GetChildren()) do
				if t:IsA("Tool") and t.Name == name then return t end
			end
		end
	end
	return nil
end

--[[ ⚠️ У АДМИНА ХВАТАЕТ НА ВСЁ.
     Кнопка «Создать» гаснет по этой функции, и без исключения тестировщик не
     может нажать её вовсе — а сервер уже умеет собирать админу бесплатно
     (InventoryCrafting, freeCraft). Правило одно и то же и живёт в общем
     конфиге: разойдутся — кнопка будет либо мёртвой, либо обещающей то, чего
     сервер не сделает.
     Считаем ОДИН раз: в течение сессии оно не меняется, а звать его на каждую
     перерисовку списка рецептов — лишний GetRankInGroup по сети. ]]
local isCraftAdmin = false
do
	local ok, cfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig", 5))
	end)
	if ok and cfg and typeof(cfg.isAdmin) == "function" then
		local ok2, res = pcall(cfg.isAdmin, player)
		isCraftAdmin = ok2 and res == true
	end
end

local function canAfford(recipe)
	if not recipe or not recipe.costs then return false end
	if isCraftAdmin then return true end
	for item, amount in recipe.costs do
		if (inventory[item] or 0) < amount then return false end
	end
	if recipe.villagers and villagersHave() < recipe.villagers then return false end
	if recipe.toolCost and not findCostTool(recipe.toolCost.tool) then return false end
	return true
end

-- Tools that opt out of the per-instance one-tool-per-slot rule and
-- instead get visually stacked by NPC-type via mergeBloodCapsules().
-- Each member of this set must carry a "BloodType" attribute set by
-- the recruitment server when the capsule is created.
local STACKABLE_TOOL_NAMES = { FullCapsule = true }
local BLOOD_STACK_SIZE = 12

local function getToolList()
	local tools = {}
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character
	if backpack then
		for _, t in backpack:GetChildren() do
			-- Stackable tools are handled separately; excluding them
			-- here prevents the standard "one Tool, one slot" path
			-- from allocating a fresh slot per blood capsule.
			if t:IsA("Tool") and not STACKABLE_TOOL_NAMES[t.Name] then
				table.insert(tools, t)
			end
		end
	end
	if char then
		for _, t in char:GetChildren() do
			if t:IsA("Tool") and not STACKABLE_TOOL_NAMES[t.Name] then
				table.insert(tools, t)
			end
		end
	end
	return tools
end

-- Returns every blood capsule the player currently holds, regardless of
-- whether the tool is in Backpack or equipped to the character.
local function getBloodCapsules()
	local out = {}
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character
	if backpack then
		for _, t in backpack:GetChildren() do
			if t:IsA("Tool") and t.Name == "FullCapsule" then
				table.insert(out, t)
			end
		end
	end
	if char then
		for _, t in char:GetChildren() do
			if t:IsA("Tool") and t.Name == "FullCapsule" then
				table.insert(out, t)
			end
		end
	end
	return out
end

local function findEmptySlot(startIdx, endIdx)
	for i = startIdx, endIdx do
		if not slotData[i] then return i end
	end
	return nil
end

-- Count how many "food Tool" instances of `toolName` the player owns
-- right now (Backpack + Character). Used to fold the in-hand /
-- standing-by Tool into the resource slot's displayed total — the
-- player sees a single banana / coconut / pineapple slot whose count
-- reflects "things you own", regardless of whether one of them is
-- currently in your hand as a Tool or sitting in inv as a stack.
local function countFoodToolsForName(toolName)
	if not FOOD_RESOURCE_SET[toolName] then return 0 end
	local total = 0
	local function gather(container)
		if not container then return end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child.Name == toolName and child:GetAttribute("FoodResource") == toolName then
				total = total + 1
			end
		end
	end
	gather(player.Character)
	gather(player:FindFirstChild("Backpack"))
	return total
end

-- True if `tool` is one of those "borrowed from stack" food Tools we
-- promoted via EquipFoodAsTool. They live shadowed by the resource
-- slot, so the Tool-placement pass in rebuildSlotData skips them.
local function isFoodTool(tool)
	return tool
		and tool:IsA("Tool")
		and FOOD_RESOURCE_SET[tool.Name]
		and tool:GetAttribute("FoodResource") == tool.Name
end

-- Same shadow-by-resource-slot trick for bush seeds. The Tool is
-- spawned by HungerSystem.equipBushSeed and carries
-- BushSeedResource = <resource name> so we know it's the stack-
-- borrowed variant and not, say, a Pineapple_Seed tree seed that
-- happens to share part of its name.
local function countBushSeedToolsForName(resName)
	if not BUSH_SEED_RESOURCE_SET[resName] then return 0 end
	local total = 0
	local function gather(container)
		if not container then return end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child.Name == resName
				and child:GetAttribute("BushSeedResource") == resName then
				total = total + 1
			end
		end
	end
	gather(player.Character)
	gather(player:FindFirstChild("Backpack"))
	return total
end

local function isBushSeedTool(tool)
	return tool
		and tool:IsA("Tool")
		and BUSH_SEED_RESOURCE_SET[tool.Name]
		and tool:GetAttribute("BushSeedResource") == tool.Name
end

-- Тот же трюк «тень ресурса» для материалов плавильни (EquipMaterialAsTool):
-- руда/водоросли в руке не занимают отдельный слот-тул, а считаются в свой
-- ресурсный слот.
local function isMaterialTool(tool)
	return tool
		and tool:IsA("Tool")
		and MATERIAL_RESOURCE_SET[tool.Name]
		and tool:GetAttribute("MaterialResource") == tool.Name
end

local function countMaterialToolsForName(resName)
	if not MATERIAL_RESOURCE_SET[resName] then return 0 end
	local total = 0
	local function gather(container)
		if not container then return end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child.Name == resName
				and child:GetAttribute("MaterialResource") == resName then
				total = total + 1
			end
		end
	end
	gather(player.Character)
	gather(player:FindFirstChild("Backpack"))
	return total
end

local function findItemSlot(itemType, itemName)
	for i = 1, TOTAL_SLOTS do
		if slotData[i] and slotData[i].type == itemType and slotData[i].name == itemName then
			return i
		end
	end
	return nil
end

local MAX_STACK = 30

-- Update resource slots: preserve existing layout, only add/remove the difference
local function distributeResource(name, totalCount, icon)
	-- Find all existing slots with this resource
	local existingSlots = {}
	local currentTotal = 0
	for i = 1, TOTAL_SLOTS do
		if slotData[i] and slotData[i].type == "resource" and slotData[i].name == name then
			table.insert(existingSlots, i)
			currentTotal = currentTotal + slotData[i].count
		end
	end

	local diff = totalCount - currentTotal

	if diff == 0 then return end

	if diff > 0 then
		local added = 0

		-- Priority: if there's a pending target slot (merc backpack drag),
		-- place items there first before falling back to default logic.
		local pending = _G.PendingTargetSlot
		if pending and pending.name == name then
			local tgt = pending.slot
			_G.PendingTargetSlot = nil
			if tgt and tgt >= 1 and tgt <= TOTAL_SLOTS and not isSlotLocked(tgt) then
				local dst = slotData[tgt]
				if dst and dst.type == "resource" and dst.name == name then
					local space = MAX_STACK - dst.count
					if space > 0 then
						local toAdd = math.min(diff - added, space)
						dst.count = dst.count + toAdd
						added = added + toAdd
					end
				elseif not dst then
					local amount = math.min(diff - added, MAX_STACK)
					slotData[tgt] = {type = "resource", name = name, count = amount, icon = icon}
					added = added + amount
				end
			end
		end

		-- Fill existing non-full slots (last ones first for natural stacking)
		for j = #existingSlots, 1, -1 do
			if added >= diff then break end
			local idx = existingSlots[j]
			local space = MAX_STACK - slotData[idx].count
			if space > 0 then
				local toAdd = math.min(diff - added, space)
				slotData[idx].count = slotData[idx].count + toAdd
				added = added + toAdd
			end
		end

		-- Still need more? Create new slots
		while added < diff do
			local empty = findEmptySlot(1, HOTBAR_SLOTS) or findEmptySlot(HOTBAR_SLOTS + 1, maxWritableSlot())
			if not empty then break end
			local amount = math.min(diff - added, MAX_STACK)
			slotData[empty] = {type = "resource", name = name, count = amount, icon = icon}
			added = added + amount
		end
	else
		-- Removing items: take from last slots first
		local toRemove = -diff
		for j = #existingSlots, 1, -1 do
			local idx = existingSlots[j]
			if toRemove >= slotData[idx].count then
				toRemove = toRemove - slotData[idx].count
				slotData[idx] = nil
			else
				slotData[idx].count = slotData[idx].count - toRemove
				toRemove = 0
			end
			if toRemove <= 0 then break end
		end
	end
end

local function updateResourceSlots(name, count, icon)
	if count > 0 then
		distributeResource(name, count, icon)
	else
		for i = 1, TOTAL_SLOTS do
			if slotData[i] and slotData[i].type == "resource" and slotData[i].name == name then
				slotData[i] = nil
			end
		end
	end
end

-- Group all FullCapsule tool instances by BloodType and lay them out
-- into stacks of up to BLOOD_STACK_SIZE per inventory slot. Pirate
-- and Infected Military blood land in different slots even though they share
-- the same Tool.Name, because the slot is keyed off BloodType.
local function mergeBloodCapsules()
	local capsules = getBloodCapsules()

	-- Drop any existing blood-stack slots; we rebuild them fresh each
	-- pass to keep the layout in sync with what's actually in Backpack.
	for i = 1, TOTAL_SLOTS do
		local d = slotData[i]
		if d and d.type == "tool" and d.toolName == "FullCapsule" then
			slotData[i] = nil
		end
	end

	if #capsules == 0 then return end

	-- Bucket by BloodType so each NPC type produces a distinct stack.
	-- Untagged legacy capsules collapse into "" so they still display.
	local groups = {}
	local order  = {}
	for _, t in capsules do
		local bt = t:GetAttribute("BloodType") or ""
		if not groups[bt] then
			groups[bt] = { tools = {}, label = t:GetAttribute("BloodLabel") }
			table.insert(order, bt)
		end
		table.insert(groups[bt].tools, t)
		if not groups[bt].label then
			groups[bt].label = t:GetAttribute("BloodLabel")
		end
	end

	local FALLBACK_ICON = "rbxassetid://132749498016835"

	for _, bt in order do
		local g = groups[bt]
		local label = g.label
			or (bt ~= "" and (bt .. " Blood"))
			or "Blood"
		local i = 1
		while i <= #g.tools do
			local stackTools = {}
			for j = 1, BLOOD_STACK_SIZE do
				local t = g.tools[i]
				if not t then break end
				table.insert(stackTools, t)
				i = i + 1
			end

			local target = findEmptySlot(1, HOTBAR_SLOTS)
				or findEmptySlot(HOTBAR_SLOTS + 1, maxWritableSlot())
			if not target then break end

			local primary = stackTools[1]
			local extras  = {}
			for k = 2, #stackTools do extras[k - 1] = stackTools[k] end

			local icon = (primary.TextureId ~= "" and primary.TextureId) or FALLBACK_ICON

			slotData[target] = {
				type        = "tool",
				name        = "FullCapsule",
				toolName    = "FullCapsule",
				toolInst    = primary,
				extraInsts  = extras,
				icon        = icon,
				count       = #stackTools,
				displayName = label,
				bloodType   = bt,
			}
		end
	end
end

local function rebuildSlotData()
	local tools = getToolList()

	if not slotsInitialized then
		for i = 1, TOTAL_SLOTS do slotData[i] = nil end

		for resName, resIcon in RESOURCE_ICONS do
			local count = inventory[resName] or 0
			-- Food + bush-seed Tools that are currently in the player's
			-- hand or Backpack count towards the resource slot's total
			-- so the player sees a single "Pineapple_Bush_Seed x10"
			-- entry even when one of those 10 is held as a Tool.
			count = count + countFoodToolsForName(resName)
			count = count + countBushSeedToolsForName(resName)
			count = count + countMaterialToolsForName(resName)
			if count > 0 then
				-- пустая иконка в таблице = «взять с модели» (см. resolveItemIcon)
				distributeResource(resName, count,
					(resIcon ~= "" and resIcon) or resolveItemIcon(resName))
			end
		end

		-- Tools never stack: each Tool Instance gets its own slot so
		-- duplicates (e.g. two Machetes) occupy separate cells. The
		-- Tool reference is stored so rebuildSlotData can match a
		-- slot back to the same instance on subsequent refreshes.
		-- Food + bush-seed Tools are skipped here because the resource
		-- slot above already owns their visual representation.
		local slot = 2
		for _, tool in tools do
			if not isFoodTool(tool) and not isBushSeedTool(tool) and not isMaterialTool(tool) then
				while slot <= HOTBAR_SLOTS and slotData[slot] do
					slot = slot + 1
				end
				if slot > HOTBAR_SLOTS then break end
				-- без своей картинки — пусто: renderSlot нарисует саму модель тула (не бревно)
				local toolIcon = TOOL_ICONS[tool.Name] or (tool.TextureId ~= "" and tool.TextureId) or ""
				ensureSandBagHook(tool)
				slotData[slot] = {
					type = "tool",
					name = tool.Name,
					toolName = tool.Name,
					toolInst = tool,
					icon = toolIcon,
					count = 1,
				}
				slot = slot + 1
			end
		end

		-- First pass: still run the blood-stack merge so capsules
		-- present at boot collapse into 12-per-slot stacks like every
		-- subsequent refresh.
		mergeBloodCapsules()
		slotsInitialized = true
		return
	end

	-- Update all resources. Food + bush-seed resources include any
	-- in-hand / Backpack Tool counterpart so the slot count reflects
	-- "things you own" regardless of whether one of them is currently
	-- equipped — see countFoodToolsForName / countBushSeedToolsForName.
	for resName, resIcon in RESOURCE_ICONS do
		local count = inventory[resName] or 0
		count = count + countFoodToolsForName(resName)
		count = count + countBushSeedToolsForName(resName)
		count = count + countMaterialToolsForName(resName)
		updateResourceSlots(resName, count, resIcon)
	end

	-- Tools don't stack; each Tool Instance claims its own slot. Match
	-- surviving instances to their existing slot; re-bind slots whose
	-- instance ref went stale (e.g. after a layout restore from the
	-- server saved state, which only carries the tool name) to any
	-- unclaimed same-name tool; drop orphan slots.
	local currentSet = {}
	for _, tool in tools do currentSet[tool] = true end

	local claimed = {}
	for i = 1, TOTAL_SLOTS do
		local entry = slotData[i]
		if entry and entry.type == "tool" then
			if FOOD_RESOURCE_SET[entry.toolName] or BUSH_SEED_RESOURCE_SET[entry.toolName] then
				-- Food / bush-seed Tools no longer claim slots — the
				-- resource slot handles their visual via the count*Tools
				-- helpers. Drop any leftover entry from before this
				-- consolidation.
				slotData[i] = nil
			else
				local inst = entry.toolInst
				if inst and currentSet[inst] and not claimed[inst] then
					claimed[inst] = true
					entry.count = 1
				else
					local name = entry.toolName or entry.name
					local bound
					for _, t in tools do
						if not claimed[t] and t.Name == name then
							bound = t
							break
						end
					end
					if bound then
						entry.toolInst = bound
						entry.count = 1
						claimed[bound] = true
					else
						slotData[i] = nil
					end
				end
			end
		end
	end

	-- Any Tool instances not yet bound to a slot get a fresh one —
	-- honouring _G.PendingTargetSlot so a chest → inventory drag lands
	-- where the user released the drag. Food + bush-seed Tools are
	-- shadowed by their resource slot (count*ToolsForName above), so
	-- we skip claiming a slot for them entirely.
	for _, tool in tools do
		if not claimed[tool] and not isFoodTool(tool) and not isBushSeedTool(tool)
			and not isMaterialTool(tool) then
			local target
			local pending = _G.PendingTargetSlot
			if pending and pending.name == tool.Name then
				local tgt = pending.slot
				if tgt and tgt >= 1 and tgt <= TOTAL_SLOTS
					and not isSlotLocked(tgt) and not slotData[tgt] then
					target = tgt
					_G.PendingTargetSlot = nil
				end
			end
			target = target or findEmptySlot(1, HOTBAR_SLOTS) or findEmptySlot(HOTBAR_SLOTS + 1, maxWritableSlot())
			if target then
				-- без своей картинки — пусто: renderSlot нарисует саму модель тула (не бревно)
				local toolIcon = TOOL_ICONS[tool.Name] or (tool.TextureId ~= "" and tool.TextureId) or ""
				ensureSandBagHook(tool)
				slotData[target] = {
					type = "tool",
					name = tool.Name,
					toolName = tool.Name,
					toolInst = tool,
					icon = toolIcon,
					count = 1,
				}
				claimed[tool] = true
			end
		end
	end

	-- Blood capsules are routed through their own stacking pass so
	-- they collapse by BloodType into 12-per-slot stacks. Run last so
	-- it sees the latest Backpack state and never collides with the
	-- one-Tool-one-slot binding loop above.
	mergeBloodCapsules()
end

-- ─── Rendering ───

-- ⚠️ НОМЕР СЛОТА ПЕРЕЖИВАЕТ ПЕРЕРИСОВКУ.
-- Всё содержимое слота (иконка, счётчик, полоска прочности) сносится и рисуется
-- заново на каждом обновлении. Номер клавиши — не содержимое, он принадлежит
-- самому слоту и не меняется никогда, поэтому создаётся один раз при сборке
-- хотбара и в эту чистку не попадает. Без исключения он исчезал бы при первом же
-- взятии предмета.
local SLOT_NUMBER_NAME = "SlotNumber"

local function clearSlotUI(slot)
	-- готовые кадры моделей (ModelIcon.take) — обратно на полку, а не в мусор
	require(ReplicatedStorage:WaitForChild("ModelIcon")).reclaim(slot)
	for _, child in slot:GetChildren() do
		-- ⚠️ Frame сносим ТОЛЬКО по имени: у слота есть свои Frame'ы отделки
		-- (полоски блокировки), и снести их значит испортить сам слот.
		if child.Name ~= SLOT_NUMBER_NAME
			and (child:IsA("ImageLabel") or (child:IsA("TextLabel") and child.Name ~= "")
				or (child:IsA("Frame") and child.Name == "DurabilityBar")
				or (child:IsA("ViewportFrame") and child.Name == "ModelIcon")) then   -- иконка-модель декора
			child:Destroy()
		end
	end
end

local function renderSlot(slot, data)
	--[[ ⚠️ ИКОНКУ-МОДЕЛЬ НЕ ПЕРЕРИСОВЫВАЕМ НА КАЖДОМ ОБНОВЛЕНИИ. Хотбар
	     обновляется при любом взятии предмета в руку; новая рамка ViewportFrame
	     несколько кадров пустая — иконка рыбацкого места мигала, когда брали
	     грядку. Если в слоте уже нарисована та же модель — оставляем её. ]]
	local srcTpl = nil
	if data and data.type == "tool" and data.toolInst then
		local pv = data.toolInst:GetAttribute("PreviewModel")
		if type(pv) == "string" and pv ~= "" then
			srcTpl = require(ReplicatedStorage:WaitForChild("AssetFind")).find(pv)
		elseif (data.icon or "") == "" then
			srcTpl = require(ReplicatedStorage:WaitForChild("AssetFind")).find(data.toolInst.Name) or data.toolInst
		end
	elseif data and data.type == "resource" and (data.icon or "") == "" and type(data.name) == "string" then
		srcTpl = require(ReplicatedStorage:WaitForChild("AssetFind")).find(data.name)
	end
	local kept = slot:FindFirstChild("ModelIcon")
	if kept and kept:IsA("ViewportFrame") and srcTpl and kept:GetAttribute("IconSrc") == srcTpl:GetFullName() then
		kept.Parent = nil   -- переживёт чистку слота
	else
		kept = nil
	end
	local function drawIcon(src)
		if kept then kept.Parent = slot; local k = kept; kept = nil; return k end
		-- готовый кадр со скрытой полки (прогрет заранее), а не новая рамка:
		-- новая несколько секунд рисует модель на глазах (рыбацкое место)
		local vp = require(ReplicatedStorage:WaitForChild("ModelIcon")).take(slot, src)
		if vp then vp:SetAttribute("IconSrc", src:GetFullName()) end
		return vp
	end
	clearSlotUI(slot)
	if not data then return end

	-- Sand Bag tools swap their hotbar icon based on the SandFill
	-- attribute so the slot art mirrors the inspection panel's current
	-- bag stage. Falls through to the static icon if the tool ref is
	-- gone (e.g. mid-respawn before rebuildSlotData rebinds it).
	local iconAsset = data.icon or ""
	if data.type == "tool" and data.toolInst and isSandBagTool(data.toolInst) then
		iconAsset = getSandBagIcon(data.toolInst) or iconAsset
	end

	local img = Instance.new("ImageLabel")
	img.Name = "ItemIcon"
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Size = UDim2.new(0.7, 0, 0.7, 0)
	img.Position = UDim2.new(0.5, 0, 0.5, 0)
	img.BackgroundTransparency = 1
	img.Image = iconAsset
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = 2
	img.Parent = slot
	-- декор: у тула-заготовки картинки нет, крафт пишет ему атрибут PreviewModel —
	-- рисуем саму модель (ModelIcon), как в меню крафта и в молотке
	local previewName = data.type == "tool" and data.toolInst and data.toolInst:GetAttribute("PreviewModel")
	-- тул без картинки вовсе (сеткомёт: модель от автора, TextureId пуст) — рисуем
	-- его самого, а не пустой квадрат
	if iconAsset == "" and data.type == "tool" and data.toolInst and not (type(previewName) == "string" and previewName ~= "") then
		-- ⚠️ СНАЧАЛА ОДНОИМЁННАЯ МОДЕЛЬ ИЗ ReplicatedStorage: у тула-заготовки
		-- (пугало и прочее «поставить на плот») в руках лишь невидимая ручка,
		-- и слот был пустым. Нет модели — рисуем сам тул (сеткомёт).
		local src = require(ReplicatedStorage:WaitForChild("AssetFind")).find(data.toolInst.Name) or data.toolInst
		local drawn = drawIcon(src)
		if drawn then
			drawn.ZIndex = 2
			drawn.Size = UDim2.new(0.8, 0, 0.8, 0)
		end
	end
	-- ресурс без картинки (клешня краба): рисуем одноимённую модель из ReplicatedStorage
	if iconAsset == "" and data.type == "resource" and type(data.name) == "string" then
		local tpl = require(ReplicatedStorage:WaitForChild("AssetFind")).find(data.name)
		local drawn = tpl and drawIcon(tpl)
		if drawn then
			drawn.ZIndex = 2
			drawn.Size = UDim2.new(0.8, 0, 0.8, 0)
		end
	end
	if type(previewName) == "string" and previewName ~= "" then
		local tpl = require(ReplicatedStorage:WaitForChild("AssetFind")).find(previewName)
		local drawn = tpl and drawIcon(tpl)
		if drawn then
			drawn.ZIndex = 2
			drawn.Size = UDim2.new(0.8, 0, 0.8, 0)
			drawn.Position = UDim2.new(0.5, 0, 0.5, 0)
			drawn.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Image = ""
		end
	end

	if data.count and data.count > 1 then
		local count = Instance.new("TextLabel")
		count.Name = "ItemCount"
		count.Size = UDim2.new(0, 25, 0, 16)
		count.Position = UDim2.new(1, -27, 1, -18)
		count.BackgroundTransparency = 1
		count.Text = tostring(data.count)
		count.TextColor3 = COLORS.lightText
		count.TextStrokeTransparency = 0.3
		count.TextStrokeColor3 = Color3.new(0, 0, 0)
		count.Font = Enum.Font.GothamBold
		count.TextSize = 13
		count.TextXAlignment = Enum.TextXAlignment.Right
		count.ZIndex = 3
		count.Parent = slot
	end

	-- ПРОЧНОСТЬ — полоска под иконкой. Без цифр: цвет и есть значение (зелёный →
	-- жёлтый → оранжевый → красный). Значение читается прямо из атрибутов тула,
	-- они реплицируются с сервера сами, ремоут для этого не нужен.
	if data.type == "tool" and data.toolInst then
		local frac = ToolDurability.fractionOf(data.toolInst)
		if frac then
			local bar = Instance.new("Frame")
			bar.Name = "DurabilityBar"
			bar.AnchorPoint = Vector2.new(0.5, 1)
			bar.Position = UDim2.new(0.5, 0, 1, -5)
			bar.Size = UDim2.new(0.72, 0, 0, 5)
			bar.BackgroundColor3 = Color3.fromRGB(32, 22, 12)
			bar.BackgroundTransparency = 0.2
			bar.BorderSizePixel = 0
			bar.ZIndex = 4
			bar.Parent = slot

			local barCorner = Instance.new("UICorner")
			barCorner.CornerRadius = UDim.new(1, 0)
			barCorner.Parent = bar

			local fill = Instance.new("Frame")
			fill.Name = "Fill"
			fill.Size = UDim2.new(frac, 0, 1, 0)
			fill.BackgroundColor3 = ToolDurability.colorFor(frac)
			fill.BorderSizePixel = 0
			fill.ZIndex = 5
			fill.Parent = bar

			local fillCorner = Instance.new("UICorner")
			fillCorner.CornerRadius = UDim.new(1, 0)
			fillCorner.Parent = fill
		end
	end
end

-- ЖИВОЕ ОБНОВЛЕНИЕ ШКАЛ. Полную перерисовку слотов на каждый удар гонять нельзя
-- (она пересоздаёт иконки и рвёт перетаскивание), поэтому существующим полоскам
-- просто правим длину и цвет. 28 слотов — стоимость незаметная.
local function refreshDurabilityBars()
	local function apply(slot, data)
		local bar = slot and slot:FindFirstChild("DurabilityBar")
		if not bar then return end
		local fill = bar:FindFirstChild("Fill")
		if not fill then return end
		local frac = (data and data.type == "tool") and ToolDurability.fractionOf(data.toolInst) or nil
		if not frac then
			bar:Destroy()   -- тул уехал из слота: полоска не должна пережить его
			return
		end
		fill.Size = UDim2.new(frac, 0, 1, 0)
		fill.BackgroundColor3 = ToolDurability.colorFor(frac)
	end

	if hotbarGui then
		local bar = hotbarGui:FindFirstChild("Hotbar")
		if bar then
			for i = 1, HOTBAR_SLOTS do
				apply(bar:FindFirstChild("HotbarSlot_" .. i), slotData[i])
			end
		end
	end
	if screenGui and screenGui.Enabled then
		local grid = screenGui:FindFirstChild("InventoryGrid", true)
		if grid then
			for i = 1, GRID_SLOTS do
				apply(grid:FindFirstChild("Slot_" .. i), slotData[HOTBAR_SLOTS + i])
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(0.15)
		local ok, err = pcall(refreshDurabilityBars)
		if not ok then warn("[Прочность] обновление шкал: " .. tostring(err)) end
	end
end)

function renderAllSlots()
	local char = player.Character

	-- Render hotbar (slots 1-8)
	if hotbarGui then
		local bar = hotbarGui:FindFirstChild("Hotbar")
		if bar then
			for i = 1, HOTBAR_SLOTS do
				local slot = bar:FindFirstChild("HotbarSlot_" .. i)
				if slot then
					renderSlot(slot, slotData[i])
					local data = slotData[i]
					-- «Выбран» = соответствующий Tool сейчас В РУКЕ. Совпадение по
					-- ИНСТАНСУ, не по имени (иначе два EmptyCapsule светились бы оба);
					-- фолбэк на имя — когда toolInst устарел после save/restore.
					local selected = false
					if data and data.type == "tool" and char then
						local inst = data.toolInst
						if inst and inst:IsA("Tool") and inst.Parent == char then
							selected = true
						elseif not inst then
							for _, t in char:GetChildren() do
								if t:IsA("Tool") and t.Name == data.toolName then selected = true break end
							end
						end
					elseif data and data.type == "resource" and data.name and FOOD_RESOURCE_SET[data.name] and char then
						-- Еда в руке подсвечивает слот ресурса так же, как инструмент.
						for _, t in char:GetChildren() do
							if t:IsA("Tool") and t.Name == data.name and t:GetAttribute("FoodResource") == data.name then
								selected = true
								break
							end
						end
					elseif data and data.type == "resource" and data.name and BUSH_SEED_RESOURCE_SET[data.name] and char then
						for _, t in char:GetChildren() do
							if t:IsA("Tool") and t.Name == data.name and t:GetAttribute("BushSeedResource") == data.name then
								selected = true
								break
							end
						end
					end
					applySlotState(slot, data ~= nil, selected, false, SLOT_STYLE_HOTBAR)
					-- мягкое свечение за выбранным слотом
					local glow = bar:FindFirstChild("HotbarGlow_" .. i)
					if glow then
						glow.BackgroundTransparency = selected and 0.72 or 1
					end
				end
			end
		end
	end

	-- Render inventory grid (slots 9-28)
	if screenGui then
		local grid = screenGui:FindFirstChild("InventoryGrid", true)
		if grid then
			for i = 1, GRID_SLOTS do
				local slot = grid:FindFirstChild("Slot_" .. i)
				if slot then
					local globalIdx = HOTBAR_SLOTS + i
					renderSlot(slot, slotData[globalIdx])
					-- стиль по споке: заблокирован/пустой/занятый (синяя палитра сетки)
					applySlotState(slot, slotData[globalIdx] ~= nil, false, isSlotLocked(globalIdx), SLOT_STYLE_GRID)
				end
			end
		end

		-- Sum resource counts from slotData (what's actually in visible slots)
		-- instead of raw inventory values, so the counter matches the UI.
		local function countResourceInSlots(resName)
			local total = 0
			for i = 1, TOTAL_SLOTS do
				local d = slotData[i]
				if d and d.type == "resource" and d.name == resName then
					total = total + (d.count or 0)
				end
			end
			return total
		end
		-- баланс пиратской валюты в шапке (счётчики дерева/листвы убраны)
		local bal = screenGui:FindFirstChild("PirateBalanceCount", true)
		if bal then bal.Text = "БАЛАНС: " .. tostring(player:GetAttribute("Pirate") or 0) end
	end
end

-- ─── Drag & Drop ───

local function beginDragPending(slotIndex, data, mousePos, isSplit)
	if not data then return end
	-- Never start a drag while the phone (or any other full-screen
	-- overlay) is on top — the hotbar's MouseButton1Down still fires
	-- because the phone's backdrop Frames don't sink pointer events,
	-- but the ghost visual would bleed over the overlay.
	if isHoverBlockingOverlayOpen() then return end
	dragState.sourceSlot = slotIndex
	dragState.data = data
	dragState.startPos = mousePos
	dragState.active = false
	dragState.didDrag = false
	dragState.splitMode = isSplit or false
end

local function activateDrag(mousePos)
	if dragState.active then return end
	dragState.active = true
	dragState.didDrag = true
	hideTooltip()

	local data = dragState.data
	local ghostGui = Instance.new("ScreenGui")
	ghostGui.Name = "DragGhost"
	ghostGui.DisplayOrder = 100
	ghostGui.IgnoreGuiInset = true
	ghostGui.Parent = playerGui

	local ghost = Instance.new("ImageLabel")
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Size = UDim2.new(0, SLOT_SIZE - 8, 0, SLOT_SIZE - 8)
	ghost.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y)
	ghost.BackgroundTransparency = 1
	ghost.Image = data.icon or ""
	ghost.ScaleType = Enum.ScaleType.Fit
	ghost.ImageTransparency = 0.3
	ghost.Parent = ghostGui

	local displayCount = (dragState.splitMode and 1) or (data.count)
	if displayCount and displayCount > 0 then
		local cl = Instance.new("TextLabel")
		cl.Size = UDim2.new(0, 25, 0, 16)
		cl.Position = UDim2.new(1, -25, 1, -16)
		cl.BackgroundTransparency = 1
		cl.Text = tostring(displayCount)
		cl.TextColor3 = COLORS.lightText
		cl.TextStrokeTransparency = 0.3
		cl.TextStrokeColor3 = Color3.new(0, 0, 0)
		cl.Font = Enum.Font.GothamBold
		cl.TextSize = 13
		cl.TextXAlignment = Enum.TextXAlignment.Right
		cl.Parent = ghost
	end

	dragState.ghost = ghost
	dragState.ghostGui = ghostGui
end

local function updateDragPosition(mousePos)
	if dragState.startPos and not dragState.active and dragState.data then
		local dx = mousePos.X - dragState.startPos.X
		local dy = mousePos.Y - dragState.startPos.Y
		if math.sqrt(dx * dx + dy * dy) >= DRAG_THRESHOLD then
			activateDrag(mousePos)
		end
	end
	if dragState.active and dragState.ghost then
		dragState.ghost.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y)
	end
end

local function findSlotUnderMouse(mousePos)
	-- GetMouseLocation() includes the GUI inset, AbsolutePosition does not
	local inset = GuiService:GetGuiInset()
	local mx = mousePos.X
	local my = mousePos.Y - inset.Y
	-- Check hotbar slots (1-8)
	if hotbarGui then
		local bar = hotbarGui:FindFirstChild("Hotbar")
		if bar then
			for i = 1, HOTBAR_SLOTS do
				local slot = bar:FindFirstChild("HotbarSlot_" .. i)
				if slot then
					local p = slot.AbsolutePosition
					local s = slot.AbsoluteSize
					if mx >= p.X and mx <= p.X + s.X and my >= p.Y and my <= p.Y + s.Y then
						return i
					end
				end
			end
		end
	end

	-- Check inventory grid slots (9-28)
	if screenGui then
		local grid = screenGui:FindFirstChild("InventoryGrid", true)
		if grid then
			for i = 1, GRID_SLOTS do
				local slot = grid:FindFirstChild("Slot_" .. i)
				if slot then
					local p = slot.AbsolutePosition
					local s = slot.AbsoluteSize
					if mx >= p.X and mx <= p.X + s.X and my >= p.Y and my <= p.Y + s.Y then
						return HOTBAR_SLOTS + i
					end
				end
			end
		end
	end

	-- Слоты экипировки (индексы 200+). Они живут в оверлее «Экипировка» и есть на
	-- экране только когда он открыт — отсюда проверка на живой Parent.
	for index, frame in pairs(equipSlotFrames) do
		if frame and frame.Parent then
			local p = frame.AbsolutePosition
			local s = frame.AbsoluteSize
			if mx >= p.X and mx <= p.X + s.X and my >= p.Y and my <= p.Y + s.Y then
				return index
			end
		end
	end

	return nil
end

local function cancelDrag()
	if dragState.ghostGui then dragState.ghostGui:Destroy() end
	dragState.active = false
	dragState.sourceSlot = nil
	dragState.data = nil
	dragState.ghost = nil
	dragState.ghostGui = nil
	dragState.startPos = nil
end

-- Exposed so other client scripts (e.g. the chest UI) can ask which
-- inventory slot the mouse is currently over - same hit-test the
-- inventory's own drag-drop uses, including the GUI inset correction.
_G.FindInventorySlotUnderMouse = findSlotUnderMouse

-- ПЕРЕНЁС СЛОТ — ПРЕДМЕТ УХОДИТ ИЗ РУК.
--
-- Работает и для обычных инструментов, и для «спрятанных» за стаком тулов
-- (еда, семена куста — они не занимают свой слот, а подмешиваются в счётчик).
-- Правило одно для всех: раз игрок переложил слот, держать его содержимое в
-- руке нелогично, а у еды это ещё и выглядело рассинхроном — стак уехал, кусок
-- остался в руке и его можно было съесть.
--
-- Снимаем, а не удаляем: у еды FoodSystem по возврату в рюкзак сам вернёт
-- единицу в стак (refundFood по AncestryChanged), обычный инструмент просто
-- ложится обратно в рюкзак.
local function unequipShadowedTool(data)
	if not data then return end
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local held
	if data.type == "tool" then
		-- По инстансу, если он известен: два одинаковых по имени тула не
		-- должны снимать друг друга.
		if data.toolInst and data.toolInst:IsA("Tool") and data.toolInst.Parent == char then
			held = true
		elseif data.toolName then
			for _, t in ipairs(char:GetChildren()) do
				if t:IsA("Tool") and t.Name == data.toolName then held = true break end
			end
		end
	elseif data.type == "resource" and data.name then
		if FOOD_RESOURCE_SET[data.name] or BUSH_SEED_RESOURCE_SET[data.name] then
			for _, t in ipairs(char:GetChildren()) do
				if t:IsA("Tool") and t.Name == data.name then held = true break end
			end
		end
	end

	if held then humanoid:UnequipTools() end
end

local function endDrag(mousePos)
	if not dragState.active then
		cancelDrag()
		return
	end

	local targetSlot = findSlotUnderMouse(mousePos)
	local srcSlot = dragState.sourceSlot
	local isSplit = dragState.splitMode

	-- СЛОТ ЭКИПИРОВКИ. Проверяем ДО всего остального: индексы у него свои (200+),
	-- и обычная логика приняла бы их за заблокированную ячейку сетки.
	-- Сам предмет не двигаем — сервер снимет его из инвентаря и вернёт обновление.
	if targetSlot and targetSlot > EQUIP_SLOT_BASE then
		local srcData = slotData[srcSlot]
		local itemName = srcData and (srcData.name or srcData.toolName)
		if itemName and EquipmentDefs.isEquippable(itemName) then
			equipmentRemote:FireServer("equip", itemName)
		end
		cancelDrag()
		dragState.didDrag = true
		renderAllSlots()
		return
	end

	-- ИСТОЧНИК — СЛОТ ЭКИПИРОВКИ. Вещь снимается, сервер сам кладёт её в
	-- свободную ячейку. Отпустили на том же слоте — ничего не делаем.
	if srcSlot and srcSlot > EQUIP_SLOT_BASE then
		if targetSlot ~= srcSlot and dragState.data and dragState.data.equipKey then
			equipmentRemote:FireServer("unequip", dragState.data.equipKey)
		end
		cancelDrag()
		dragState.didDrag = true
		renderAllSlots()
		return
	end

	-- Drops onto locked grid slots are cancelled outright: nothing moves,
	-- nothing is dropped into the world, and we flash a "Slot blocked"
	-- popup at the drop point. We short-circuit here so the drag simply
	-- snaps back to the source slot on the next render.
	if targetSlot and isSlotLocked(targetSlot) then
		showLockedDropMessage(mousePos)
		cancelDrag()
		dragState.didDrag = true
		renderAllSlots()
		return
	end

	if targetSlot and targetSlot ~= srcSlot then
		local srcData = slotData[srcSlot]
		local dstData = slotData[targetSlot]

		-- ПЕРЕТАЩИЛ СЛОТ С ЕДОЙ — СНИМАЕМ ЕЁ С РУК.
		--
		-- Экипированная еда не занимает свой слот: она «подмешана» в счётчик
		-- стака (см. isFoodTool и rebuildSlotData). Из-за этого после
		-- перетаскивания кусок оставался в руках, хотя игрок уже перенёс стак
		-- в другое место — слот под курсором пуст, а еда всё ещё в руке, и её
		-- можно съесть. Выглядит как рассинхрон, даже когда счётчик верный.
		--
		-- Снимаем тул, а не удаляем: FoodSystem по возврату в рюкзак сам
		-- вернёт единицу в стак (refundFood по AncestryChanged).
		unequipShadowedTool(srcData)
		unequipShadowedTool(dstData)

		if isSplit and srcData and srcData.type == "resource" and srcData.count and srcData.count > 1 then
			-- Right-click split: move exactly 1 to target
			if dstData and dstData.type == "resource" and dstData.name == srcData.name then
				if dstData.count < MAX_STACK then
					dstData.count = dstData.count + 1
					srcData.count = srcData.count - 1
				end
			elseif not dstData then
				slotData[targetSlot] = {
					type = srcData.type,
					name = srcData.name,
					count = 1,
					icon = srcData.icon,
				}
				srcData.count = srcData.count - 1
			end
		elseif srcData and dstData
			and srcData.type == "resource" and dstData.type == "resource"
			and srcData.name == dstData.name then
			-- Left-click same resource: stack them (up to MAX_STACK)
			local space = MAX_STACK - dstData.count
			if space > 0 then
				local toMove = math.min(srcData.count, space)
				dstData.count = dstData.count + toMove
				srcData.count = srcData.count - toMove
				if srcData.count <= 0 then
					slotData[srcSlot] = nil
				end
			else
				-- Target full: swap
				slotData[targetSlot] = srcData
				slotData[srcSlot] = dstData
			end
		else
			-- Different items or tools: swap
			slotData[targetSlot] = srcData
			slotData[srcSlot] = dstData
		end
	elseif not targetSlot and srcSlot then
		-- Dropped outside any slot. If a chest/container is open and the
		-- release was inside one of its slots, push the stack in there
		-- instead of dumping to the world. Tools go via "tool" kind so
		-- the server moves Tool Instances; resources still go as counts.
		if _G.ActiveContainer and typeof(_G.ContainerTryDrop) == "function" then
			local data = slotData[srcSlot]
			-- Стак уезжает в сундук — держать кусок в руке тем более незачем.
			unequipShadowedTool(data)
			if data and data.type == "resource"
				and _G.ContainerTryDrop(mousePos, data.name, data.count, "resource")
			then
				local dropCount = isSplit and 1 or data.count
				if dropCount >= data.count then
					slotData[srcSlot] = nil
				else
					data.count = data.count - dropCount
				end
				cancelDrag()
				dragState.didDrag = true
				renderAllSlots()
				syncSlotLayoutToServer()
				return
			end
			if data and data.type == "tool"
				and _G.ContainerTryDrop(mousePos, data.toolName, data.count or 1, "tool")
			then
				-- Backpack.ChildRemoved will trigger updateUI and clear
				-- the slot; we just stop the world-drop fallback here.
				cancelDrag()
				dragState.didDrag = true
				renderAllSlots()
				syncSlotLayoutToServer()
				return
			end
		end

		local srcData = slotData[srcSlot]
		if srcData then
			local dropEvt = ReplicatedStorage:FindFirstChild("DropItem")
			if dropEvt then
				-- Raycast from mouse to find drop position in the world
				local cam = workspace.CurrentCamera
				local mPos = UserInputService:GetMouseLocation()
				local ray = cam:ViewportPointToRay(mPos.X, mPos.Y)
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				local char = player.Character
				if char then rayParams.FilterDescendantsInstances = {char} end
				local result = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
				local dropPos = result and result.Position or nil

				if srcData.type == "resource" then
					local dropCount = isSplit and 1 or srcData.count
					if dropCount >= srcData.count then
						slotData[srcSlot] = nil
					else
						srcData.count = srcData.count - dropCount
					end
					dropEvt:FireServer(srcData.name, dropCount, dropPos)
				elseif srcData.type == "tool" then
					slotData[srcSlot] = nil
					dropEvt:FireServer(srcData.toolName, 1, dropPos)
				end
			end
		end
	end

	cancelDrag()
	dragState.didDrag = true
	renderAllSlots()
	syncSlotLayoutToServer()
end

-- ─── Quick-transfer: Shift+click moves item between hotbar and grid ───
-- If a chest/container UI is open, shift-clicking an inventory slot
-- pushes the stack into the container instead. We drain the clicked
-- slot locally before the server call so the specific slot the user
-- aimed at is the one that empties — otherwise distributeResource
-- picks the last slot with that item and the wrong one clears.
local function quickTransfer(slotIndex)
	local data = slotData[slotIndex]
	if not data then return end

	-- Shift-перенос — то же самое перемещение слота, что и перетаскивание,
	-- просто без мыши. Значит и еду с рук снимать надо так же: иначе стак
	-- уезжал в рюкзак, а кусок оставался в руке.
	unequipShadowedTool(data)

	if _G.ActiveContainer and data.type == "resource"
		and typeof(_G.ContainerTransferFromPlayer) == "function" then
		local name = data.name
		local amount = data.count
		slotData[slotIndex] = nil
		renderAllSlots()
		_G.ContainerTransferFromPlayer(name, amount, "resource")
		return
	end

	if _G.ActiveContainer and data.type == "tool"
		and typeof(_G.ContainerTransferFromPlayer) == "function" then
		-- Tools live in Backpack, not slotData. The server moves the
		-- Tool Instances out; Backpack.ChildRemoved then clears the
		-- local slot via updateUI. Don't pre-drain here.
		_G.ContainerTransferFromPlayer(data.toolName, data.count or 1, "tool")
		return
	end

	local isHotbar = slotIndex >= 1 and slotIndex <= HOTBAR_SLOTS
	local targetStart, targetEnd

	if isHotbar then
		-- From hotbar → inventory grid
		if not isOpen then return end -- grid must be open
		targetStart = HOTBAR_SLOTS + 1
		targetEnd = maxWritableSlot()
	else
		-- From inventory grid → hotbar
		targetStart = 1
		targetEnd = HOTBAR_SLOTS
	end

	-- For resources, try to stack first with same item in target area
	if data.type == "resource" then
		local remaining = data.count
		-- Stack into existing slots of same type
		for i = targetStart, targetEnd do
			if remaining <= 0 then break end
			if slotData[i] and slotData[i].type == "resource" and slotData[i].name == data.name then
				local space = MAX_STACK - slotData[i].count
				if space > 0 then
					local toMove = math.min(remaining, space)
					slotData[i].count = slotData[i].count + toMove
					remaining = remaining - toMove
				end
			end
		end
		-- Put rest into empty slots
		while remaining > 0 do
			local empty = findEmptySlot(targetStart, targetEnd)
			if not empty then break end
			local amount = math.min(remaining, MAX_STACK)
			slotData[empty] = {type = data.type, name = data.name, count = amount, icon = data.icon}
			remaining = remaining - amount
		end
		-- Update source
		if remaining <= 0 then
			slotData[slotIndex] = nil
		else
			slotData[slotIndex].count = remaining
		end
	else
		-- Tools: just swap to first empty slot in target area
		local empty = findEmptySlot(targetStart, targetEnd)
		if empty then
			slotData[empty] = data
			slotData[slotIndex] = nil
		end
	end

	renderAllSlots()
	syncSlotLayoutToServer()
end

-- ─── Reward roll: claim a won tool into a specific hotbar slot ───
-- Bumps whatever occupies `slotIndex` into the inventory grid, then routes the next
-- incoming Tool named `toolName` to that slot (via _G.PendingTargetSlot). Returns
-- false if the slot couldn't be freed (no grid room) — the caller then lets the
-- won tool fall back to a free slot / drop.
_G.RewardClaimToSlot = function(toolName, slotIndex)
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > HOTBAR_SLOTS then return false end
	local data = slotData[slotIndex]
	if data then
		if data.type == "resource" then
			local remaining = data.count
			for i = HOTBAR_SLOTS + 1, maxWritableSlot() do
				if remaining <= 0 then break end
				if slotData[i] and slotData[i].type == "resource" and slotData[i].name == data.name then
					local space = MAX_STACK - slotData[i].count
					if space > 0 then
						local m = math.min(remaining, space)
						slotData[i].count = slotData[i].count + m
						remaining = remaining - m
					end
				end
			end
			while remaining > 0 do
				local e = findEmptySlot(HOTBAR_SLOTS + 1, maxWritableSlot())
				if not e then break end
				local a = math.min(remaining, MAX_STACK)
				slotData[e] = { type = "resource", name = data.name, count = a, icon = data.icon }
				remaining = remaining - a
			end
			if remaining > 0 then
				-- Инвентарь полностью забит (в сетке нет места для вытесняемого
				-- стака) — сбрасываем несместившийся остаток ресурса в мир. Его
				-- можно подобрать, а слот освобождается под приз. Раньше здесь
				-- был `return false` → приз (пушка) падал на землю мимо слота.
				local dropEvt = ReplicatedStorage:FindFirstChild("DropItem")
				if dropEvt then dropEvt:FireServer(data.name, remaining, nil) end
			end
			slotData[slotIndex] = nil
		else
			local e = findEmptySlot(HOTBAR_SLOTS + 1, maxWritableSlot())
			if e then
				-- есть место в сетке — просто сдвигаем предмет слота туда
				slotData[e] = data
			else
				-- сетка тоже забита — вытесняем предмет выбранного слота в мир
				-- (его можно подобрать), освобождая ячейку под приз. Раньше:
				-- `return false` → приз падал на землю мимо слота.
				local dropEvt = ReplicatedStorage:FindFirstChild("DropItem")
				if dropEvt then dropEvt:FireServer(data.toolName or data.name, 1, nil) end
			end
			slotData[slotIndex] = nil
		end
	end
	_G.PendingTargetSlot = { name = toolName, slot = slotIndex }
	renderAllSlots()
	syncSlotLayoutToServer()
	return true
end

-- ─── Equip ───

-- Toggle / switch tool by instance. Clicking a slot routes here with
-- the exact Tool instance held in `slotData[i].toolInst`, so two slots
-- holding same-named Tools (e.g. two Sand Bags) each get their own
-- specific Tool — clicking slot 4 never equips slot 3's instance.
--
-- Behaviour:
--   * the same instance is already in hand → unequip
--   * another Tool is in hand (or nothing)  → equip this one (Roblox
--                                              auto-unequips the prior
--                                              tool so it's a one-click
--                                              swap, not a two-step)
local function equipToolInstance(tool)
	-- ⚠️ НА ПУЛЕМЁТЕ / ПУШКЕ (атрибут OnTurret) предметы не берём: руки заняты
	if player:GetAttribute("OnTurret") then return end
	if not tool or not tool:IsA("Tool") or not tool.Parent then return end
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	if tool.Parent == char then
		humanoid:UnequipTools()
		return
	end

	humanoid:EquipTool(tool)
end

-- Name-based fallback for callers that don't have a specific instance
-- (legacy hotbar keys, debug code). Same toggle rule, but picks the
-- first matching Tool in the backpack.
local function equipToolByName(toolName)
	-- ⚠️ НА ПУЛЕМЁТЕ / ПУШКЕ (атрибут OnTurret) предметы не берём: руки заняты
	if player:GetAttribute("OnTurret") then return end
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	for _, t in char:GetChildren() do
		if t:IsA("Tool") and t.Name == toolName then
			humanoid:UnequipTools()
			return
		end
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, t in backpack:GetChildren() do
			if t:IsA("Tool") and t.Name == toolName then
				humanoid:EquipTool(t)
				return
			end
		end
	end
end

-- ─── UI Update ───

local rebuildCraftList

local function closeDetailOverlay()
	if detailOverlay then
		detailOverlay:Destroy()
		detailOverlay = nil
	end
	selectedRecipe = nil
end

local function closeCategoryOverlay()
	closeDetailOverlay()
	if categoryOverlay then
		categoryOverlay:Destroy()
		categoryOverlay = nil
	end
	selectedCategory = nil
	if screenGui then
		local tabFrame = screenGui:FindFirstChild("CategoryTabs", true)
		if tabFrame then
			for _, tab in tabFrame:GetChildren() do
				if tab:IsA("TextButton") then
					tab.BackgroundColor3 = COLORS.craftItemBg
					tab.TextColor3 = COLORS.titleText
					local s = tab:FindFirstChildWhichIsA("UIStroke")
					if s then s.Color = COLORS.panelBorder end -- снять золотую рамку активной
				end
			end
		end
	end
end

-- ─── Экипировка ───────────────────────────────────────────────────
-- Четыре слота под надеваемые вещи. Что надето — в атрибутах игрока
-- (EquipmentDefs), они реплицируются сами, поэтому панель просто читает их и
-- слушает изменения: своего состояния она не держит и разъехаться с сервером не может.
--
-- Индексы слотов начинаются с EQUIP_SLOT_BASE (объявлен выше по файлу, рядом с
-- категориями): по ним работает перетаскивание — см. findSlotUnderMouse/endDrag.
local function refreshEquipmentSlots()
	for i, slot in ipairs(EquipmentDefs.SLOTS) do
		local frame = equipSlotFrames[EQUIP_SLOT_BASE + i]
		if frame and frame.Parent then
			local item = EquipmentDefs.worn(player, slot.key)
			local icon = frame:FindFirstChild("ItemIcon")
			local hint = frame:FindFirstChild("SlotHint")
			if icon then icon.Image = item and _G.GetItemIcon(item) or "" end
			if hint then hint.Text = item and (ItemNamesRu.display(item) or item) or slot.ru end
			applySlotState(frame, item ~= nil, false, false, SLOT_STYLE_GRID)

			-- ШКАЛА ЗАРЯДА МАСКИ. Заряд живёт на игроке (атрибут MaskCharge), а не
			-- на вещи, и тратится только под водой — без этой полоски его падение
			-- было вообще не видно, пока маска внезапно не ломалась на лице.
			local old = frame:FindFirstChild("DurabilityBar")
			if old then old:Destroy() end
			if item == EquipmentDefs.MASK.item then
				local frac = math.clamp(
					(player:GetAttribute(EquipmentDefs.MASK.attr) or EquipmentDefs.MASK.charge)
						/ EquipmentDefs.MASK.charge, 0, 1)

				local bar = Instance.new("Frame")
				bar.Name = "DurabilityBar"
				bar.AnchorPoint = Vector2.new(0.5, 1)
				bar.Position = UDim2.new(0.5, 0, 1, -16)   -- над подписью слота
				bar.Size = UDim2.new(0.72, 0, 0, 5)
				bar.BackgroundColor3 = Color3.fromRGB(32, 22, 12)
				bar.BackgroundTransparency = 0.2
				bar.BorderSizePixel = 0
				bar.ZIndex = 4
				bar.Parent = frame
				local bc = Instance.new("UICorner")
				bc.CornerRadius = UDim.new(1, 0)
				bc.Parent = bar

				local fill = Instance.new("Frame")
				fill.Size = UDim2.new(frac, 0, 1, 0)
				fill.BackgroundColor3 = ToolDurability.colorFor(frac)
				fill.BorderSizePixel = 0
				fill.ZIndex = 5
				fill.Parent = bar
				local fc = Instance.new("UICorner")
				fc.CornerRadius = UDim.new(1, 0)
				fc.Parent = fill
			end
		end
	end
end


-- КОЛОНКА ЭКИПИРОВКИ В САМОЙ ПАНЕЛИ ИНВЕНТАРЯ, справа от сетки.
-- Так вещь можно тащить из ячейки прямо в слот: и то и другое на экране
-- одновременно. Отдельной вкладкой это не работало в принципе — слоты
-- открывались ПОВЕРХ инвентаря, и тащить становилось неоткуда.
local function buildEquipmentColumn(parent, x, y, slotSize, pad)
	equipSlotFrames = {}

	local title = Instance.new("TextLabel")
	title.Name = "EquipTitle"
	title.Position = UDim2.new(0, x, 0, y - 20)
	title.Size = UDim2.fromOffset(slotSize + 40, 18)
	title.BackgroundTransparency = 1
	title.Text = "Экипировка"
	title.TextColor3 = COLORS.titleText
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.TextStrokeTransparency = 0.6
	title.Parent = parent

	for i, slotDef in ipairs(EquipmentDefs.SLOTS) do
		local slot = Instance.new("TextButton")
		slot.Name = "EquipSlot_" .. slotDef.key
		slot.Size = UDim2.fromOffset(slotSize, slotSize)
		slot.Position = UDim2.new(0, x, 0, y + (i - 1) * (slotSize + pad))
		slot.Text = ""
		slot.AutoButtonColor = false
		slot.Parent = parent
		styleSlotBase(slot, SLOT_STYLE_GRID)

		local icon = Instance.new("ImageLabel")
		icon.Name = "ItemIcon"
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(0.72, 0.72)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 2
		icon.Parent = slot

		-- Подпись слота живёт ВНУТРИ кнопки: снаружи она перекрывала бы соседнюю
		-- ячейку сетки и ловила бы курсор мимо слота.
		local caption = Instance.new("TextLabel")
		caption.Name = "SlotHint"
		caption.AnchorPoint = Vector2.new(0.5, 1)
		caption.Position = UDim2.new(0.5, 0, 1, -2)
		caption.Size = UDim2.new(1, -6, 0, 12)
		caption.BackgroundTransparency = 1
		caption.Text = slotDef.ru
		caption.TextColor3 = COLORS.titleText
		caption.Font = Enum.Font.GothamBold
		caption.TextSize = 11
		caption.TextStrokeColor3 = Color3.new(0, 0, 0)
		caption.TextStrokeTransparency = 0.5
		caption.TextScaled = false
		caption.ZIndex = 3
		caption.Parent = slot

		-- Клик по слоту — снять. Перетаскивать вещь ОБРАТНО в инвентарь не нужно:
		-- она и так вернётся в свободную ячейку, а если места нет — упадёт под ноги.
		-- Перетаскивание ИЗ слота: потянул маску в сетку или хотбар — снялась.
		-- Без этого слот отвечал только на клик, и на телефоне, где драг — жест
		-- по умолчанию, казалось, что «маска не тянется».
		slot.MouseButton1Down:Connect(function()
			local item = EquipmentDefs.worn(player, slotDef.key)
			if not item then return end
			dragState.didDrag = false
			local icon = slot:FindFirstChild("ItemIcon")
			beginDragPending(EQUIP_SLOT_BASE + i, {
				type = "resource", name = item, count = 1,
				icon = icon and icon.Image or "", equipKey = slotDef.key,
			}, UserInputService:GetMouseLocation(), false)
		end)

		slot.MouseButton1Click:Connect(function()
			if dragState.didDrag then
				dragState.didDrag = false
				return
			end
			if EquipmentDefs.worn(player, slotDef.key) then
				equipmentRemote:FireServer("unequip", slotDef.key)
			end
		end)

		equipSlotFrames[EQUIP_SLOT_BASE + i] = slot
	end

	refreshEquipmentSlots()
end

-- Слоты перерисовываются от атрибутов игрока — сервер меняет их, панель узнаёт сама.
for _, slotDef in ipairs(EquipmentDefs.SLOTS) do
	player:GetAttributeChangedSignal(EquipmentDefs.attr(slotDef.key)):Connect(refreshEquipmentSlots)
end
-- заряд маски тикает под водой — шкала в слоте обновляется по нему же
player:GetAttributeChangedSignal(EquipmentDefs.MASK.attr):Connect(refreshEquipmentSlots)

--[[ ⚠️ ОБЪЯВЛЕНО ЗАРАНЕЕ: тело closeUI ниже по файлу, а крестик накладки зовёт
     его отсюда. Без этой строки имя внутри разрешилось бы как ГЛОБАЛЬНОЕ, то
     есть nil, и кнопка молча не закрывала бы меню — ровно та беда, которую она
     призвана лечить. ]]
local closeUI

local function openCategoryOverlay(cat)
	if not screenGui then return end
	local centerPanel = screenGui:FindFirstChild("CenterPanel")
	if not centerPanel then return end

	closeDetailOverlay()
	if categoryOverlay then
		categoryOverlay:Destroy()
		categoryOverlay = nil
	end
	selectedCategory = cat

	categoryOverlay = Instance.new("Frame")
	categoryOverlay.Name = "CategoryOverlay"
	categoryOverlay.Size = centerPanel.Size
	categoryOverlay.Position = centerPanel.Position
	categoryOverlay.BackgroundColor3 = Color3.new(1, 1, 1) -- белый под градиент
	categoryOverlay.BorderSizePixel = 0
	categoryOverlay.ZIndex = 15
	categoryOverlay.Active = true
	categoryOverlay.Parent = screenGui

	-- ⚠️ ЗАГЛУШКА КЛИКОВ.
	-- Frame ввод не держит: он рисуется поверх, а клики проходят насквозь к тому,
	-- что осталось разложенным под ним. Кнопка забирает ввод всегда — ею и глушим.
	-- ZIndex как у самого оверлея: ниже его содержимого (16..19), но выше низа.
	local catBlocker = Instance.new("TextButton")
	catBlocker.Name = "ClickBlocker"
	catBlocker.Size = UDim2.fromScale(1, 1)
	catBlocker.BackgroundTransparency = 1
	catBlocker.Text = ""
	catBlocker.AutoButtonColor = false
	catBlocker.ZIndex = 15
	catBlocker.Parent = categoryOverlay

	--[[ ⚠️ КРЕСТИК ЕСТЬ И ЗДЕСЬ: ВЫЙТИ ИЗ МЕНЮ МОЖНО ВСЕГДА.
	     Кнопка закрытия живёт в самой панели инвентаря, а эта накладка рисуется
	     ПОВЕРХ неё — и крестик пропадал, стоило открыть категорию крафта. Выйти
	     оставалось только через «Назад», да и то в два шага; на тесте это назвали
	     первым, что мешает.
	     Кнопка своя, но действие то же самое (closeUI), и вид повторяет исходную:
	     две белые перекладины на красном квадрате, потому что символ ✕ в этом
	     шрифте не рисуется. ZIndex выше содержимого накладки — иначе список
	     рецептов перекрыл бы её. ]]
	local overlayClose = Instance.new("TextButton")
	overlayClose.Name = "OverlayClose"
	overlayClose.Size = UDim2.new(0, 30, 0, 30)
	overlayClose.Position = UDim2.new(1, -36, 0, 8)
	overlayClose.BackgroundColor3 = COLORS.notAffordable
	overlayClose.Text = ""
	overlayClose.BorderSizePixel = 0
	overlayClose.AutoButtonColor = true
	overlayClose.ZIndex = 22
	overlayClose.Parent = categoryOverlay

	local overlayCloseCorner = Instance.new("UICorner")
	overlayCloseCorner.CornerRadius = UDim.new(0, 10)
	overlayCloseCorner.Parent = overlayClose

	local overlayCloseStroke = Instance.new("UIStroke")
	overlayCloseStroke.Color = Color3.fromHex("8A2A12")
	overlayCloseStroke.Thickness = 3
	overlayCloseStroke.Parent = overlayClose

	for _, rot in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(16, 4)
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		bar.BorderSizePixel = 0
		bar.Rotation = rot
		bar.ZIndex = 23
		local barCorner = Instance.new("UICorner")
		barCorner.CornerRadius = UDim.new(1, 0)
		barCorner.Parent = bar
		bar.Parent = overlayClose
	end

	overlayClose.MouseButton1Click:Connect(function()
		if closeUI then closeUI() end
	end)

	local overlayGradient = Instance.new("UIGradient")
	overlayGradient.Color = ColorSequence.new(COLORS.panelTop, COLORS.panelBg)
	overlayGradient.Rotation = 90
	overlayGradient.Parent = categoryOverlay

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = categoryOverlay

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.panelBorder
	stroke.Thickness = 4
	stroke.Parent = categoryOverlay

	local backBtn = Instance.new("TextButton")
	backBtn.Size = UDim2.new(0, 72, 0, 30)
	backBtn.Position = UDim2.new(0, 12, 0, 9)
	backBtn.BackgroundColor3 = COLORS.panelBorder
	backBtn.Text = "< Назад"
	backBtn.TextColor3 = COLORS.titleText
	backBtn.Font = Enum.Font.GothamBlack
	backBtn.TextSize = 13
	backBtn.BorderSizePixel = 0
	backBtn.ZIndex = 16
	backBtn.Parent = categoryOverlay

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 10)
	backCorner.Parent = backBtn

	backBtn.MouseButton1Click:Connect(closeCategoryOverlay)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -110, 0, 30)
	title.Position = UDim2.new(0, 96, 0, 9)
	title.BackgroundTransparency = 1
	title.Text = catLabel(cat)
	title.TextColor3 = COLORS.titleText
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.TextStrokeTransparency = 0.6
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 16
	title.Parent = categoryOverlay

	local craftList = Instance.new("ScrollingFrame")
	craftList.Name = "CraftList"
	craftList.Size = UDim2.new(1, -20, 1, -60)
	craftList.Position = UDim2.new(0, 10, 0, 50)
	craftList.BackgroundTransparency = 1
	craftList.BorderSizePixel = 0
	craftList.ScrollBarThickness = 6
	-- Matches the detail-overlay scroll bar; darker than the tan panel
	-- so it stands out against the wooden background.
	craftList.ScrollBarImageColor3 = COLORS.panelBorder
	craftList.CanvasSize = UDim2.new(0, 0, 0, 0)
	craftList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	craftList.ZIndex = 17
	craftList.Parent = categoryOverlay

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 5)
	listLayout.Parent = craftList

	rebuildCraftList()
end

local function openDetailOverlay(recipe)
	closeDetailOverlay()
	selectedRecipe = recipe
	if not screenGui then return end

	local centerPanel = screenGui:FindFirstChild("CenterPanel")
	if not centerPanel then return end

	-- Create overlay same size/position as center panel
	detailOverlay = Instance.new("Frame")
	detailOverlay.Name = "DetailOverlay"
	detailOverlay.Size = centerPanel.Size
	detailOverlay.Position = centerPanel.Position
	detailOverlay.BackgroundColor3 = Color3.new(1, 1, 1) -- белый под градиент
	detailOverlay.BorderSizePixel = 0
	detailOverlay.ZIndex = 20
	detailOverlay.Active = true
	-- Чей рецепт открыт — читается снаружи (подсказки квестов). Без этого им
	-- приходилось бы гадать по тексту кнопки, а он локализуемый.
	detailOverlay:SetAttribute("RecipeName", recipe.name)
	detailOverlay.Parent = screenGui

	-- ⚠️ ЗАГЛУШКА КЛИКОВ — см. такую же у categoryOverlay.
	-- Список рецептов остаётся разложенным ПОД карточкой, его строки живые. Одного
	-- Active на Frame не хватило: нажатие по пустому месту карточки всё равно
	-- доходило до строки под ней и открывало чужой рецепт. Кнопка ввод забирает
	-- всегда — этим и глушим. ZIndex как у самой карточки: ниже её содержимого (21+),
	-- но выше всего, что лежит под ней (15..19).
	local detailBlocker = Instance.new("TextButton")
	detailBlocker.Name = "ClickBlocker"
	detailBlocker.Size = UDim2.fromScale(1, 1)
	detailBlocker.BackgroundTransparency = 1
	detailBlocker.Text = ""
	detailBlocker.AutoButtonColor = false
	detailBlocker.ZIndex = 20
	detailBlocker.Parent = detailOverlay

	local detailGradient = Instance.new("UIGradient")
	detailGradient.Color = ColorSequence.new(COLORS.panelTop, COLORS.panelBg)
	detailGradient.Rotation = 90
	detailGradient.Parent = detailOverlay

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = detailOverlay

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.panelBorder
	stroke.Thickness = 4
	stroke.Parent = detailOverlay

	-- Back button
	local backBtn = Instance.new("TextButton")
	backBtn.Size = UDim2.new(0, 84, 0, 34)
	backBtn.Position = UDim2.new(0, 12, 0, 10)
	backBtn.BackgroundColor3 = COLORS.panelBorder
	backBtn.Text = "< Назад"
	backBtn.TextColor3 = COLORS.titleText
	backBtn.Font = Enum.Font.GothamBlack
	backBtn.TextSize = 16
	backBtn.BorderSizePixel = 0
	backBtn.ZIndex = 21
	backBtn.Parent = detailOverlay

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 10)
	backCorner.Parent = backBtn

	backBtn.MouseButton1Click:Connect(closeDetailOverlay)

	-- Item name
	local itemTitle = Instance.new("TextLabel")
	itemTitle.Size = UDim2.new(1, -24, 0, 44)
	itemTitle.Position = UDim2.new(0, 12, 0, 54)
	itemTitle.BackgroundTransparency = 1
	itemTitle.Text = recipe.displayName or recipe.name
	itemTitle.TextColor3 = COLORS.titleText
	itemTitle.Font = Enum.Font.GothamBlack
	itemTitle.TextSize = 30
	itemTitle.TextStrokeColor3 = Color3.new(0, 0, 0)
	itemTitle.TextStrokeTransparency = 0.6
	itemTitle.TextXAlignment = Enum.TextXAlignment.Left
	itemTitle.ZIndex = 21
	itemTitle.Parent = detailOverlay

	-- Icon — enlarged so the crafted item is clearly legible.
	local iconFrame = Instance.new("ImageLabel")
	iconFrame.Size = UDim2.new(0, 110, 0, 110)
	iconFrame.Position = UDim2.new(0, 20, 0, 118)
	iconFrame.BackgroundTransparency = 1
	-- у рецепта может не быть своей картинки — тогда берём её с модели предмета
	iconFrame.Image = (recipe.icon ~= "" and recipe.icon) or _G.GetItemIcon(recipe.name)
	iconFrame.ScaleType = Enum.ScaleType.Fit
	iconFrame.ZIndex = 21
	iconFrame.Parent = detailOverlay
	-- декор: иконка-модель (ModelIcon), как в списке и в молотке
	if type(recipe.preview) == "string" and recipe.preview ~= "" then
		local tpl = require(ReplicatedStorage:WaitForChild("AssetFind")).find(recipe.preview)
		local drawn = tpl and require(ReplicatedStorage:WaitForChild("ModelIcon")).render(iconFrame, tpl)
		if drawn then
			drawn.ZIndex = 22
			iconFrame.Image = ""
		end
	end

	-- Description — sits to the right of the icon, vertical extent
	-- matches the icon's height so wrapped text has room to breathe.
	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -160, 0, 110)
	descLabel.Position = UDim2.new(0, 145, 0, 118)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = recipe.description or ""
	descLabel.TextColor3 = COLORS.titleText
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 20
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextWrapped = true
	descLabel.ZIndex = 21
	descLabel.Parent = detailOverlay

	-- Materials section
	local matTitle = Instance.new("TextLabel")
	matTitle.Size = UDim2.new(1, -24, 0, 30)
	matTitle.Position = UDim2.new(0, 12, 0, 240)
	matTitle.BackgroundTransparency = 1
	matTitle.Text = "Материалы:"
	matTitle.TextColor3 = COLORS.titleText
	matTitle.Font = Enum.Font.GothamBold
	matTitle.TextSize = 22
	matTitle.TextXAlignment = Enum.TextXAlignment.Left
	matTitle.ZIndex = 21
	matTitle.Parent = detailOverlay

	-- Material items — in a ScrollingFrame so recipes with many
	-- ingredients don't slide under the Craft button. The frame spans
	-- from just below the "Materials:" header to just above the craft
	-- button (which sits at bottom -68, height 54).
	local matScroll = Instance.new("ScrollingFrame")
	matScroll.Name = "MaterialsScroll"
	matScroll.Size = UDim2.new(1, -34, 1, -348)
	matScroll.Position = UDim2.new(0, 17, 0, 274)
	matScroll.BackgroundTransparency = 1
	matScroll.BorderSizePixel = 0
	matScroll.ScrollBarThickness = 6
	matScroll.ScrollBarImageColor3 = COLORS.panelBorder
	matScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	matScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	matScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	matScroll.ZIndex = 21
	matScroll.ClipsDescendants = true
	matScroll.Parent = detailOverlay

	local matLayout = Instance.new("UIListLayout")
	matLayout.FillDirection = Enum.FillDirection.Vertical
	matLayout.SortOrder = Enum.SortOrder.LayoutOrder
	matLayout.Padding = UDim.new(0, 6)
	matLayout.Parent = matScroll

	-- Small right-side padding so rows don't sit under the scroll bar.
	local matPadding = Instance.new("UIPadding")
	matPadding.PaddingRight = UDim.new(0, 8)
	matPadding.Parent = matScroll

	local matOrder = 0
	for item, amount in recipe.costs do
		matOrder = matOrder + 1
		local matRow = Instance.new("Frame")
		matRow.Size = UDim2.new(1, 0, 0, 48)
		matRow.LayoutOrder = matOrder
		matRow.BackgroundColor3 = COLORS.craftItemBg
		matRow.BorderSizePixel = 0
		matRow.ZIndex = 21
		matRow.Parent = matScroll

		local matCorner = Instance.new("UICorner")
		matCorner.CornerRadius = UDim.new(0, 6)
		matCorner.Parent = matRow

		local matIcon = Instance.new("ImageLabel")
		matIcon.Size = UDim2.new(0, 36, 0, 36)
		matIcon.Position = UDim2.new(0, 8, 0.5, -18)
		matIcon.BackgroundTransparency = 1
		matIcon.Image = RESOURCE_ICONS[item] or ""
		matIcon.ScaleType = Enum.ScaleType.Fit
		matIcon.ZIndex = 22
		matIcon.Parent = matRow

		local have = inventory[item] or 0
		local matLabel = Instance.new("TextLabel")
		matLabel.Name = "MatLabel_" .. item
		matLabel.Size = UDim2.new(1, -60, 1, 0)
		matLabel.Position = UDim2.new(0, 52, 0, 0)
		matLabel.BackgroundTransparency = 1
		matLabel.Text = ResourceNamesRu(item) .. ": " .. have .. " / " .. amount
		matLabel.TextColor3 = have >= amount and COLORS.affordable or COLORS.notAffordable
		matLabel.Font = Enum.Font.GothamBold
		matLabel.TextSize = 20
		matLabel.TextXAlignment = Enum.TextXAlignment.Left
		matLabel.ZIndex = 22
		matLabel.Parent = matRow
		matRow:SetAttribute("ItemName", item)
		matRow:SetAttribute("ItemAmount", amount)
	end

	-- Предмет-ингредиент (канистра у огнемёта) — такой же строкой, как материалы.
	-- Без неё игрок видел только дерево с мусором и не понимал, почему кнопка
	-- серая: канистра требовалась молча.
	if recipe.toolCost then
		matOrder = matOrder + 1
		local have = findCostTool(recipe.toolCost.tool)

		local row = Instance.new("Frame")
		row.Name = "MatRow_Tool"
		row.Size = UDim2.new(1, 0, 0, 48)
		row.LayoutOrder = matOrder
		row.BackgroundColor3 = COLORS.craftItemBg
		row.BorderSizePixel = 0
		row.ZIndex = 21
		row.Parent = matScroll

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = row

		local ico = Instance.new("ImageLabel")
		ico.Size = UDim2.new(0, 36, 0, 36)
		ico.Position = UDim2.new(0, 8, 0.5, -18)
		ico.BackgroundTransparency = 1
		ico.Image = recipe.toolCost.icon or ""
		ico.ScaleType = Enum.ScaleType.Fit
		ico.ZIndex = 22
		ico.Parent = row

		-- если предмет несёт заряд (топливо канистры), сразу показываем, сколько
		-- его перейдёт в результат — это главное, что игроку тут важно знать
		local text = (recipe.toolCost.label or recipe.toolCost.tool) .. ": " .. (have and "1 / 1" or "0 / 1")
		if have and recipe.toolCost.from then
			local fill = have:GetAttribute(recipe.toolCost.from) or 0
			local cap = have:GetAttribute("OilCapacity") or 3000
			text = text .. (" (заряд %d%%)"):format(math.floor(fill / math.max(cap, 1) * 100 + 0.5))
		end

		local lbl = Instance.new("TextLabel")
		lbl.Name = "MatLabel_Tool"
		lbl.Size = UDim2.new(1, -60, 1, 0)
		lbl.Position = UDim2.new(0, 52, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = text
		lbl.TextColor3 = have and COLORS.affordable or COLORS.notAffordable
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 20
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.ZIndex = 22
		lbl.Parent = row
	end

	-- Жители — такой же строкой, как материалы, но берутся из атрибута игрока
	if recipe.villagers and recipe.villagers > 0 then
		matOrder = matOrder + 1
		local row = Instance.new("Frame")
		row.Name = "MatRow_Villagers"
		row.Size = UDim2.new(1, 0, 0, 48)
		row.LayoutOrder = matOrder
		row.BackgroundColor3 = COLORS.craftItemBg
		row.BorderSizePixel = 0
		row.ZIndex = 21
		row.Parent = matScroll

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = row

		local ico = Instance.new("ImageLabel")
		ico.Size = UDim2.new(0, 36, 0, 36)
		ico.Position = UDim2.new(0, 8, 0.5, -18)
		ico.BackgroundTransparency = 1
		ico.Image = VILLAGER_ICON
		ico.ScaleType = Enum.ScaleType.Fit
		ico.ZIndex = 22
		ico.Parent = row

		local have = villagersHave()
		local lbl = Instance.new("TextLabel")
		lbl.Name = "MatLabel_Villagers"
		lbl.Size = UDim2.new(1, -60, 1, 0)
		lbl.Position = UDim2.new(0, 52, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = "Жители: " .. have .. " / " .. recipe.villagers
		lbl.TextColor3 = have >= recipe.villagers and COLORS.affordable or COLORS.notAffordable
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 20
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.ZIndex = 22
		lbl.Parent = row
	end

	-- Craft button at bottom — зелёная по прототипу (серая, если не хватает)
	local craftBtn = Instance.new("TextButton")
	craftBtn.Name = "DetailCraftButton"
	craftBtn.Size = UDim2.new(1, -34, 0, 54)
	craftBtn.Position = UDim2.new(0, 17, 1, -68)
	craftBtn.BackgroundColor3 = canAfford(recipe) and COLORS.affordable or Color3.fromRGB(150, 160, 175)
	craftBtn.Text = "Создать " .. (recipe.displayName or recipe.name)
	craftBtn.TextColor3 = Color3.new(1, 1, 1)
	craftBtn.Font = Enum.Font.GothamBlack
	craftBtn.TextSize = 22
	craftBtn.TextStrokeColor3 = Color3.new(0, 0, 0)
	craftBtn.TextStrokeTransparency = 0.6
	craftBtn.BorderSizePixel = 0
	craftBtn.ZIndex = 21
	craftBtn.Parent = detailOverlay

	local craftCorner = Instance.new("UICorner")
	craftCorner.CornerRadius = UDim.new(0, 12)
	craftCorner.Parent = craftBtn

	local craftBtnStroke = Instance.new("UIStroke")
	craftBtnStroke.Name = "CraftStroke"
	craftBtnStroke.Color = canAfford(recipe) and Color3.fromHex("1E5C24") or Color3.fromRGB(100, 110, 122)
	craftBtnStroke.Thickness = 3
	craftBtnStroke.Parent = craftBtn

	craftBtn.MouseButton1Click:Connect(function()
		if canAfford(recipe) then
			inventoryCraftEvent:FireServer("craft", recipe.name)
		end
	end)
end

function rebuildCraftList()
	if not screenGui then return end
	if not selectedCategory then return end
	local craftList = screenGui:FindFirstChild("CraftList", true)
	if not craftList then return end

	-- Clear existing items (готовые иконки-модели сначала возвращаем в пул ModelIcon)
	require(ReplicatedStorage:WaitForChild("ModelIcon")).reclaim(craftList)
	for _, child in craftList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	-- Filter recipes by selected category
	--[[ ПОРЯДОК В КАТЕГОРИИ — ПО СПИСКУ, А НЕ ПО ТОМУ, КАК РЕЦЕПТЫ ЛЕЖАТ НА
	     СЕРВЕРЕ. Сервер шлёт их в порядке объявления, топор дописывается на
	     клиенте в конец — вместе это давало случайный на вид список. Здесь
	     явный порядок для каждой вкладки; чего в списке нет, встаёт после
	     перечисленного в серверном порядке. Новый рецепт — одна строка сюда. ]]
	local CATEGORY_ORDER = {
		Technology = {
			"Destitalor", "Garden", "Raft_scarecrow", "Raft_grill", "Bed", "Raft_anchor", "DivingMask",
			"Raft_grill_barrel", "Raft_smelter", "Boat_3x",
		},
		Tools = { "Hammer", "Machete", "Stone_Axe", "Paddle", "Flamethrower", "Pirate_Net_Launcher" },
		Decor = { "Raft_chair", "Raft_chair_leaf", "Raft_table_leaves" },
	}
	local rank = {}
	for i, n in ipairs(CATEGORY_ORDER[selectedCategory] or {}) do rank[n] = i end
	local filtered = {}
	for i, recipe in ipairs(recipes) do
		if recipe.category == selectedCategory then
			filtered[#filtered + 1] = { r = recipe, i = i }
		end
	end
	table.sort(filtered, function(a, b)
		local ra, rb = rank[a.r.name] or math.huge, rank[b.r.name] or math.huge
		if ra ~= rb then return ra < rb end
		return a.i < b.i
	end)

	local idx = 0
	for _, entry in ipairs(filtered) do
		local recipe = entry.r
		do
			idx = idx + 1

			-- Строка рецепта по прототипу: [иконо-бокс] Имя + пилюля цены, справа Craft.
			local btn = Instance.new("TextButton")
			btn.Name = "Recipe_" .. recipe.name
			btn.Size = UDim2.new(1, 0, 0, 90)
			btn.BackgroundColor3 = COLORS.craftItemHover
			btn.Text = ""
			btn.BorderSizePixel = 0
			btn.LayoutOrder = idx
			btn.AutoButtonColor = false
			btn.ZIndex = 17
			btn.Parent = craftList
			btn:SetAttribute("RecipeName", recipe.name)

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 12)
			btnCorner.Parent = btn

			local btnStroke = Instance.new("UIStroke")
			btnStroke.Color = COLORS.panelBorder
			btnStroke.Thickness = 2
			btnStroke.Parent = btn

			-- иконка в светлом слот-боксе
			local iconBox = Instance.new("Frame")
			iconBox.Size = UDim2.new(0, 64, 0, 64)
			iconBox.Position = UDim2.new(0, 12, 0.5, -32)
			iconBox.BackgroundColor3 = Color3.fromHex("A9D6F7")
			iconBox.BorderSizePixel = 0
			iconBox.ZIndex = 18
			iconBox.Parent = btn

			local iconBoxCorner = Instance.new("UICorner")
			iconBoxCorner.CornerRadius = UDim.new(0, 10)
			iconBoxCorner.Parent = iconBox

			local iconBoxStroke = Instance.new("UIStroke")
			iconBoxStroke.Color = COLORS.panelBorder
			iconBoxStroke.Thickness = 2
			iconBoxStroke.Parent = iconBox

			local icon = Instance.new("ImageLabel")
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Size = UDim2.new(0.8, 0, 0.8, 0)
			icon.Position = UDim2.new(0.5, 0, 0.5, 0)
			icon.BackgroundTransparency = 1
			icon.ScaleType = Enum.ScaleType.Fit
			icon.ZIndex = 19
			icon.Parent = iconBox
			icon.Image = (recipe.icon ~= "" and recipe.icon) or _G.GetItemIcon(recipe.name)
			-- ⚠️ ИКОНКА-МОДЕЛЬ ДЛЯ ДЕКОРА: у мебели картинок нет, рисуем саму модель
			-- тем же ModelIcon, что и молоток (один ракурс и свет на всю игру).
			-- require по месту: файл у предела 200 локалей.
			if type(recipe.preview) == "string" and recipe.preview ~= "" then
				local tpl = require(ReplicatedStorage:WaitForChild("AssetFind")).find(recipe.preview)
				local drawn = tpl and require(ReplicatedStorage:WaitForChild("ModelIcon")).take(iconBox, tpl)   -- готовая из пула
				if drawn then
					drawn.ZIndex = 19
					icon.Visible = false
				end
			end

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -220, 0, 26)
			nameLabel.Position = UDim2.new(0, 90, 0, 16)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = recipe.displayName or recipe.name
			nameLabel.TextColor3 = COLORS.titleText
			nameLabel.Font = Enum.Font.GothamBlack
			nameLabel.TextSize = 18
			nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
			nameLabel.TextStrokeTransparency = 0.6
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.ZIndex = 18
			nameLabel.Parent = btn

			-- ⚠️ ЦЕНА НАКАПЛИВАЕТСЯ, А НЕ ПЕРЕЗАПИСЫВАЕТСЯ.
			-- Здесь стояло присваивание, и у рецептов с двумя материалами в пилюле
			-- оставался только последний по порядку pairs — у огнемёта было видно
			-- либо «2 Брёвна», либо «3 Мусор», и цена выглядела вдвое дешевле.
			-- ⚠️ ЦЕНА — ИКОНКАМИ, А НЕ СЛОВАМИ (владелец): «3 Дерево + 1 Верёвка»
			-- стало рядом картинок ресурса с числом. Жители и инструмент остаются
			-- текстом: у них нет иконки ресурса. Порядок — как в costs.
			local costText = ""
			if recipe.villagers and recipe.villagers > 0 then
				costText = "+ " .. recipe.villagers .. " жит."
			end
			if recipe.toolCost then
				costText = costText .. (costText ~= "" and " " or "") .. "+ " .. (recipe.toolCost.label or recipe.toolCost.tool)
			end

			-- пилюля цены: зелёная если хватает, красная если нет
			local pill = Instance.new("Frame")
			pill.Name = "CostPill"
			pill.Position = UDim2.new(0, 90, 0, 48)
			pill.Size = UDim2.new(0, 0, 0, 24)
			pill.AutomaticSize = Enum.AutomaticSize.X
			-- ⚠️ ПИЛЮЛЯ БЕЗ ЗАЛИВКИ (владелец): хватает или нет — показывает цвет числа
			-- у каждой иконки, а не общая красно-зелёная плашка.
			pill.BackgroundTransparency = 1
			pill.BorderSizePixel = 0
			pill.ZIndex = 18
			pill.Parent = btn

			local pillCorner = Instance.new("UICorner")
			pillCorner.CornerRadius = UDim.new(1, 0)
			pillCorner.Parent = pill

			local pillPad = Instance.new("UIPadding")
			pillPad.PaddingLeft = UDim.new(0, 10)
			pillPad.PaddingRight = UDim.new(0, 10)
			pillPad.Parent = pill

			local pillList = Instance.new("UIListLayout")
			pillList.FillDirection = Enum.FillDirection.Horizontal
			pillList.VerticalAlignment = Enum.VerticalAlignment.Center
			pillList.SortOrder = Enum.SortOrder.LayoutOrder
			pillList.Padding = UDim.new(0, 6)
			pillList.Parent = pill
			local order = 0
			for item, amount in recipe.costs do
				order += 1
				local ico = Instance.new("ImageLabel")
				ico.Size = UDim2.fromOffset(20, 20)
				ico.BackgroundTransparency = 1
				ico.ScaleType = Enum.ScaleType.Fit
				ico.Image = _G.GetItemIcon(item)
				ico.LayoutOrder = order * 2 - 1
				ico.ZIndex = 19
				ico.Parent = pill
				local num = Instance.new("TextLabel")
				num.AutomaticSize = Enum.AutomaticSize.X
				num.Size = UDim2.new(0, 0, 1, 0)
				num.BackgroundTransparency = 1
				num.Text = "×" .. amount
				num.TextColor3 = ((inventory[item] or 0) >= amount or isCraftAdmin) and COLORS.affordable or COLORS.notAffordable
				num.Font = Enum.Font.GothamBold
				num.TextSize = 13
				num.TextStrokeColor3 = Color3.new(0, 0, 0)
				num.TextStrokeTransparency = 0.4
				num.TextSize = 14
				num.LayoutOrder = order * 2
				num.ZIndex = 19
				num.Parent = pill
			end
			local pillText = Instance.new("TextLabel")
			pillText.AutomaticSize = Enum.AutomaticSize.X
			pillText.Size = UDim2.new(0, 0, 1, 0)
			pillText.BackgroundTransparency = 1
			pillText.Visible = costText ~= ""
			pillText.LayoutOrder = 1000
			pillText.Text = costText
			pillText.TextColor3 = Color3.new(1, 1, 1)
			pillText.Font = Enum.Font.GothamBold
			pillText.TextSize = 13
			pillText.TextStrokeColor3 = Color3.new(0, 0, 0)
			pillText.TextStrokeTransparency = 0.7
			pillText.ZIndex = 19
			pillText.Parent = pill

			-- кнопка Craft в строке: зелёная/серая по доступности
			local rowCraft = Instance.new("TextButton")
			rowCraft.Name = "RowCraftBtn"
			rowCraft.AnchorPoint = Vector2.new(1, 0.5)
			rowCraft.Position = UDim2.new(1, -14, 0.5, 0)
			rowCraft.Size = UDim2.new(0, 96, 0, 44)
			rowCraft.BackgroundColor3 = canAfford(recipe) and COLORS.affordable or Color3.fromRGB(150, 160, 175)
			rowCraft.Text = "Создать"
			rowCraft.TextColor3 = Color3.new(1, 1, 1)
			rowCraft.Font = Enum.Font.GothamBlack
			rowCraft.TextSize = 18
			rowCraft.TextStrokeColor3 = Color3.new(0, 0, 0)
			rowCraft.TextStrokeTransparency = 0.6
			rowCraft.BorderSizePixel = 0
			rowCraft.AutoButtonColor = true
			rowCraft.ZIndex = 19
			rowCraft.Parent = btn

			local rowCraftCorner = Instance.new("UICorner")
			rowCraftCorner.CornerRadius = UDim.new(0, 12)
			rowCraftCorner.Parent = rowCraft

			local rowCraftStroke = Instance.new("UIStroke")
			rowCraftStroke.Color = Color3.fromHex("1E5C24")
			rowCraftStroke.Thickness = 3
			rowCraftStroke.Parent = rowCraft

			rowCraft.MouseButton1Click:Connect(function()
				if canAfford(recipe) then
					inventoryCraftEvent:FireServer("craft", recipe.name)
				end
			end)

			btn.MouseEnter:Connect(function()
				btn.BackgroundColor3 = Color3.fromHex("5C9FE8")
			end)
			btn.MouseLeave:Connect(function()
				btn.BackgroundColor3 = COLORS.craftItemHover
			end)
			btn.MouseButton1Click:Connect(function()
				openDetailOverlay(recipe)
			end)
		end
	end
end

local function updateCategoryTabs()
	if not screenGui then return end
	local tabFrame = screenGui:FindFirstChild("CategoryTabs", true)
	if not tabFrame then return end
	for _, tab in tabFrame:GetChildren() do
		if tab:IsA("TextButton") then
			local cat = tab:GetAttribute("Category")
			local color
			local stroke = tab:FindFirstChildWhichIsA("UIStroke")
			if cat == selectedCategory then
				-- активная вкладка — всегда золотая (спека)
				tab.BackgroundColor3 = COLORS.equipped
				if stroke then stroke.Color = COLORS.goldFrame end
				color = COLORS.lightText
			else
				tab.BackgroundColor3 = COLORS.craftItemBg
				if stroke then stroke.Color = COLORS.panelBorder end
				color = COLORS.titleText
			end
			tab.TextColor3 = color
			local label = tab:FindFirstChild("Label")
			if label then
				label.TextColor3 = color
			end
		end
	end
end

local function updateCraftPanel()
	if not screenGui then return end

	-- Обновить пилюли цены и кнопки Craft в списке (зелёные/красные/серые)
	local craftList = screenGui:FindFirstChild("CraftList", true)
	if craftList then
		for _, btn in craftList:GetChildren() do
			if btn:IsA("TextButton") then
				local rName = btn:GetAttribute("RecipeName")
				for _, r in recipes do
					if r.name == rName then
						local ok = canAfford(r)
						local pill = btn:FindFirstChild("CostPill")
						if pill then
							pill.BackgroundColor3 = ok and COLORS.affordable or COLORS.notAffordable
						end
						local rowCraft = btn:FindFirstChild("RowCraftBtn")
						if rowCraft then
							rowCraft.BackgroundColor3 = ok and COLORS.affordable or Color3.fromRGB(150, 160, 175)
							local s = rowCraft:FindFirstChildWhichIsA("UIStroke")
							if s then
								s.Color = ok and Color3.fromHex("1E5C24") or Color3.fromRGB(100, 110, 122)
							end
						end
					end
				end
			end
		end
	end

	-- Update detail overlay craft button if open
	if detailOverlay and selectedRecipe then
		local craftBtn = detailOverlay:FindFirstChild("DetailCraftButton")
		if craftBtn then
			local ok = canAfford(selectedRecipe)
			craftBtn.BackgroundColor3 = ok and COLORS.affordable or Color3.fromRGB(150, 160, 175)
			local s = craftBtn:FindFirstChild("CraftStroke")
			if s then
				s.Color = ok and Color3.fromHex("1E5C24") or Color3.fromRGB(100, 110, 122)
			end
		end

		-- Refresh the "Log: have / need" material rows so a just-
		-- completed craft immediately reflects the drained inventory.
		local matScroll = detailOverlay:FindFirstChild("MaterialsScroll")
		if matScroll then
			for _, row in matScroll:GetChildren() do
				local item = row:GetAttribute("ItemName")
				local amount = row:GetAttribute("ItemAmount")
				if item and amount then
					local label = row:FindFirstChild("MatLabel_" .. item)
					if label then
						local have = inventory[item] or 0
						label.Text = item .. ": " .. have .. " / " .. amount
						label.TextColor3 = have >= amount and COLORS.affordable or COLORS.notAffordable
					end
				end
			end
		end
	end
end

-- ─── Slot layout sync to server ───
local slotLayoutEvent = ReplicatedStorage:FindFirstChild("SlotLayoutSync")

function syncSlotLayoutToServer()
	if not slotLayoutEvent then
		slotLayoutEvent = ReplicatedStorage:FindFirstChild("SlotLayoutSync")
	end
	if not slotLayoutEvent then return end

	-- Build a serializable copy of slotData (no userdata)
	local layout = {}
	for i = 1, TOTAL_SLOTS do
		if slotData[i] then
			layout[tostring(i)] = {
				type = slotData[i].type,
				name = slotData[i].name,
				count = slotData[i].count,
				icon = slotData[i].icon,
				toolName = slotData[i].toolName,
			}
		end
	end
	slotLayoutEvent:FireServer(layout)
end

local function updateUI()
	rebuildSlotData()
	renderAllSlots()
	updateCraftPanel()
	syncSlotLayoutToServer()
end

-- ─── Close ───

function closeUI(isRebuild)
	closeDetailOverlay()
	if categoryOverlay then
		categoryOverlay:Destroy()
		categoryOverlay = nil
	end
	if screenGui then
		-- готовые иконки-модели — обратно в пул (ModelIcon), иначе сгорят вместе с меню
		require(ReplicatedStorage:WaitForChild("ModelIcon")).reclaim(screenGui)
		screenGui:Destroy()
		screenGui = nil
	end
	-- Drop stale grid slot refs; buildUI() re-populates them next open.
	table.clear(gridSlotVisuals)
	lockedOverlayLabel = nil
	hideTooltip()
	isOpen = false
	selectedRecipe = nil
	selectedCategory = nil
	if hotbarGui then hotbarGui.DisplayOrder = 5 end
	-- Also close the mercenary backpack / container panels if they
	-- were open, but NOT during a rebuild (recipe refresh) — only on
	-- a real close.
	if not isRebuild then
		if _G.CloseMercInventory then _G.CloseMercInventory() end
		if _G.CloseContainer then _G.CloseContainer() end
	end
end

-- Expose a force-close hook so other scripts (e.g. the phone menu) can
-- dismiss the inventory when they take over the screen.
_G.CloseInventory = function()
	if isOpen then closeUI() end
end

-- ─── Build Hotbar ───

local function buildHotbar()
	if hotbarGui then hotbarGui:Destroy() end

	hotbarGui = Instance.new("ScreenGui")
	hotbarGui.Name = "HotbarGui"
	hotbarGui.ResetOnSpawn = false
	hotbarGui.IgnoreGuiInset = true -- единая система координат с инвентарём
	hotbarGui.DisplayOrder = 5
	hotbarGui.Parent = playerGui
	attachResponsiveScale(hotbarGui)
	--[[ ⚠️ ХОТБАР ПОГАСИЛИ (молоток: стройка гасит весь HUD) — КАДРЫ-МОДЕЛИ НА ПОЛКУ.
	     Выключенный ViewportFrame не рисуется, а после включения строит модель
	     заново: иконки фермы и дома фермера первые секунды стояли пустыми. Пока
	     хотбар выключен, его кадры живут на тёплой полке ModelIcon (она не гаснет),
	     при включении слоты берут их оттуда же — готовыми. ]]
	do
		local hb = hotbarGui
		hb:GetPropertyChangedSignal("Enabled"):Connect(function()
			if hb.Enabled then
				if renderAllSlots then pcall(renderAllSlots) end
			else
				require(ReplicatedStorage:WaitForChild("ModelIcon")).reclaim(hb)
			end
		end)
	end

	-- «Без подложки»: контейнер прозрачный, виден только ряд слотов.
	local barWidth = HOTBAR_SLOTS * (HOTBAR_SLOT_SIZE + SLOT_PAD) + SLOT_PAD
	local bar = Instance.new("Frame")
	bar.Name = "Hotbar"
	bar.Size = UDim2.new(0, barWidth, 0, HOTBAR_SLOT_SIZE + SLOT_PAD * 2)
	bar.Position = UDim2.new(0.5, -barWidth / 2, 1,
		-(HOTBAR_SLOT_SIZE + SLOT_PAD * 2) - HOTBAR_BOTTOM)
	--[[ ⚠️ ВЕРНУЛ КАК БЫЛО: ЯКОРЬ В ВЕРХНЕМ ЛЕВОМ УГЛУ, СДВИГ НА ПОЛШИРИНЫ.
	     Я пробовал перевесить панель на нижний центр и дать ей свой UIScale —
	     хотбар от этого разъехался: слоты сжались и уехали. Вёрстка ряда
	     считает от левого края (позиции слотов, свечение, подписи номеров), и
	     смена системы отсчёта ломает её целиком.
	     Масштабирования у ряда слотов больше нет вовсе — как и было до правок. ]]
	bar.BackgroundTransparency = 1
	bar.Parent = hotbarGui

	for i = 1, HOTBAR_SLOTS do
		-- мягкое свечение за выбранным слотом (включает renderAllSlots)
		local glow = Instance.new("Frame")
		glow.Name = "HotbarGlow_" .. i
		glow.Size = UDim2.new(0, HOTBAR_SLOT_SIZE + 12, 0, HOTBAR_SLOT_SIZE + 12)
		glow.Position = UDim2.new(0, SLOT_PAD + (i - 1) * (HOTBAR_SLOT_SIZE + SLOT_PAD) - 6, 0, SLOT_PAD - 6)
		glow.BackgroundColor3 = COLORS.slotSelected
		glow.BackgroundTransparency = 1
		glow.BorderSizePixel = 0
		glow.ZIndex = 0
		glow.Parent = bar

		local glowCorner = Instance.new("UICorner")
		glowCorner.CornerRadius = UDim.new(0, 16)
		glowCorner.Parent = glow

		local slot = Instance.new("TextButton")
		slot.Name = "HotbarSlot_" .. i
		slot.Size = UDim2.new(0, HOTBAR_SLOT_SIZE, 0, HOTBAR_SLOT_SIZE)
		slot.Position = UDim2.new(0, SLOT_PAD + (i - 1) * (HOTBAR_SLOT_SIZE + SLOT_PAD), 0, SLOT_PAD)
		slot.BackgroundTransparency = SLOT_STYLE_HOTBAR.emptyT
		slot.Text = ""
		slot.AutoButtonColor = false
		slot.Parent = bar
		styleSlotBase(slot, SLOT_STYLE_HOTBAR)

		-- ⚠️ НОМЕР КЛАВИШИ — ТОЛЬКО ТАМ, ГДЕ ЕСТЬ КЛАВИАТУРА.
		-- Цифра значит «нажми эту клавишу, чтобы взять предмет». На телефоне
		-- нажимать нечего, и цифра в углу превращается в украшение, которое
		-- отъедает место у иконки. Признак тот же, что у всего HUD (HudScale).
		-- Стиль повторяет счётчик количества в правом нижнем углу: тот же шрифт,
		-- цвет и обводка — цифры не должны выглядеть как два разных элемента.
		if not require(ReplicatedStorage:WaitForChild("HudScale")).isPhone() then
			local num = Instance.new("TextLabel")
			num.Name = SLOT_NUMBER_NAME
			num.Size = UDim2.new(0, 18, 0, 16)
			num.Position = UDim2.new(0, 5, 0, 3)
			num.BackgroundTransparency = 1
			num.Text = tostring(i)
			num.TextColor3 = COLORS.lightText
			num.TextStrokeTransparency = 0.3
			num.TextStrokeColor3 = Color3.new(0, 0, 0)
			num.Font = Enum.Font.GothamBold
			num.TextSize = 13
			num.TextXAlignment = Enum.TextXAlignment.Left
			num.ZIndex = 3
			num.Parent = slot
		end

		local slotIndex = i

		slot.MouseEnter:Connect(function()
			showTooltipForSlot(slotIndex)
		end)
		slot.MouseLeave:Connect(function()
			hideTooltip()
		end)

		slot.MouseButton1Down:Connect(function()
			if isHoverBlockingOverlayOpen() then return end
			local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shiftHeld then
				quickTransfer(slotIndex)
				dragState.didDrag = true
				return
			end
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[slotIndex]
			if data then
				beginDragPending(slotIndex, data, mousePos, false)
			end
		end)

		slot.MouseButton2Down:Connect(function()
			if isHoverBlockingOverlayOpen() then return end
			local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shiftHeld then
				quickTransfer(slotIndex)
				dragState.didDrag = true
				return
			end
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[slotIndex]
			if data and data.type == "resource" and data.count and data.count > 1 then
				beginDragPending(slotIndex, data, mousePos, true)
			end
		end)

		slot.MouseButton1Click:Connect(function()
			if dragState.didDrag then
				dragState.didDrag = false
				return
			end
			if isHoverBlockingOverlayOpen() then return end
			local data = slotData[slotIndex]
			-- Экипировка (маска): ТАП по слоту надевает, без перетаскивания и без
			-- Shift — на телефоне ни того, ни другого нет. Снять — тапом по слоту
			-- экипировки, как и раньше.
			if data and data.type == "resource" and data.name and EquipmentDefs.isEquippable(data.name) then
				equipmentRemote:FireServer("equip", data.name)
			elseif data and data.type == "tool" then
				if data.toolInst then
					equipToolInstance(data.toolInst)
				else
					equipToolByName(data.toolName)
				end
				task.wait(0.1)
				renderAllSlots()
			elseif data and data.type == "resource" and data.name and BUSH_SEED_RESOURCE_SET[data.name] and bushActionEvent then
				-- Bush-seed resource (Pineapple_Bush_Seed). Toggle:
				-- holding the matching Tool already → UnequipTools (the
				-- server's AncestryChanged hook refunds 1 to the stack);
				-- otherwise ask the server to spawn one. Same pattern
				-- as the food path so the count never doubles up.
				local char2     = player.Character
				local humanoid2 = char2 and char2:FindFirstChildOfClass("Humanoid")
				local heldBushSeed = nil
				if char2 then
					for _, t in char2:GetChildren() do
						if t:IsA("Tool") and t.Name == data.name
							and t:GetAttribute("BushSeedResource") == data.name then
							heldBushSeed = t
							break
						end
					end
				end
				if heldBushSeed and humanoid2 then
					humanoid2:UnequipTools()
				else
					bushActionEvent:FireServer("equipBushSeed", data.name)
				end
			elseif data and data.type == "resource" and data.name and SEED_RESOURCE_SET[data.name] and equipSeedEvent then
				-- Seed resource: ask the server to spawn a matching
				-- Tool in the character's hand and decrement the stack.
				-- Server handles the refund if the Tool is unequipped
				-- without being used.
				equipSeedEvent:FireServer(data.name)
			elseif data and data.type == "resource" and data.name and FOOD_RESOURCE_SET[data.name] and equipFoodEvent then
				-- Food resource (Banana / Coconut / Pineapple): same
				-- pattern as seeds — server clones a Tool into the
				-- player's hand, decrements the stack by 1, refunds
				-- if the Tool is unequipped without being eaten.
				-- The Tool itself doesn't claim a slot; the resource
				-- slot's displayed count includes the in-hand Tool so
				-- visually the slot just stays where it was.
				--
				-- Toggle behaviour: if the same food Tool is already
				-- in hand, clicking the slot again unequips it (which
				-- routes through the server's AncestryChanged refund
				-- hook back to the resource stack).
				local char     = player.Character
				local humanoid = char and char:FindFirstChildOfClass("Humanoid")
				local heldFoodTool = nil
				if char then
					for _, t in char:GetChildren() do
						if t:IsA("Tool") and t.Name == data.name and t:GetAttribute("FoodResource") == data.name then
							heldFoodTool = t
							break
						end
					end
				end
				if heldFoodTool and humanoid then
					humanoid:UnequipTools()
				else
					equipFoodEvent:FireServer(data.name)
				end
			elseif data and data.type == "resource" and data.name
				and MATERIAL_RESOURCE_SET[data.name] and equipMaterialEvent then
				-- Материал плавильни (руда/водоросли): тот же тогл, что у еды.
				local charM     = player.Character
				local humanoidM = charM and charM:FindFirstChildOfClass("Humanoid")
				local heldMat = nil
				if charM then
					for _, t in charM:GetChildren() do
						if t:IsA("Tool") and t:GetAttribute("MaterialResource") == data.name then
							heldMat = t
							break
						end
					end
				end
				if heldMat and humanoidM then
					humanoidM:UnequipTools()
				else
					equipMaterialEvent:FireServer(data.name)
				end
			end
		end)
	end

	-- ─── Mana / health / hunger / thirst bars ──────────────────────────
	-- All four stat bars live together in StarterPlayerScripts/
	-- UIManager.client.lua. Nothing to build from here.
end

-- ─── Build Inventory UI ───

local function buildUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "InventoryGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true -- центрируем по всему экрану, а не под топбаром
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui
	attachResponsiveScale(screenGui)

	--[[ Тап по свободному месту закрывает инвентарь — как настройки и квесты.
	     Прозрачная кнопка на весь экран, первым ребёнком: панели ложатся поверх
	     и касание до неё не доходит. Хотбар (DisplayOrder 15), сундук и рюкзак
	     наёмника (31) живут в своих ScreenGui выше этого (10) — их она не
	     перекрывает. Activated срабатывает только на нажатие И отпускание по
	     самой кнопке, поэтому перетаскивание предмета из слота в мир
	     (отпустили мимо панели) инвентарь не закрывает. ]]
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	-- Кнопка вчетверо больше экрана и центрирована — страховка на случай, если
	-- масштаб инвентаря когда-нибудь начнёт применяться к детям ScreenGui:
	-- ужатый fromScale(1, 1) накрыл бы лишь угол, и тап по краю не закрывал бы.
	backdrop.AnchorPoint = Vector2.new(0.5, 0.5)
	backdrop.Position = UDim2.fromScale(0.5, 0.5)
	backdrop.Size = UDim2.fromScale(4, 4)
	backdrop.BackgroundTransparency = 1
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.ZIndex = 0
	backdrop.Parent = screenGui
	-- Обычные фреймы панелей клик не поглощают — он доходит до подложки. Поэтому
	-- закрываемся только если и нажатие, и отпускание были мимо всех панелей
	-- этого ScreenGui (та же защита, что у карты, см. MapMenu).
	local pressAt = nil
	local function insideAnyPanel(pos)
		if not pos then return false end
		local inset = GuiService:GetGuiInset()
		local x, y = pos.X, pos.Y - inset.Y
		for _, child in ipairs(screenGui:GetChildren()) do
			if child ~= backdrop and child:IsA("GuiObject") and child.Visible then
				local p, s = child.AbsolutePosition, child.AbsoluteSize
				if x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then
					return true
				end
			end
		end
		return false
	end
	backdrop.MouseButton1Down:Connect(function()
		pressAt = UserInputService:GetMouseLocation()
	end)
	backdrop.Activated:Connect(function()
		local down = pressAt
		pressAt = nil
		if dragState.active then return end
		if insideAnyPanel(down) or insideAnyPanel(UserInputService:GetMouseLocation()) then return end
		closeUI()
	end)

	local gridWidth = COLS * (SLOT_SIZE + SLOT_PAD) + SLOT_PAD
	local gridHeight = 4 * (SLOT_SIZE + SLOT_PAD) + SLOT_PAD
	-- Колонка экипировки стоит СПРАВА от сетки, в той же панели: четыре слота
	-- ровно под четыре ряда сетки. Панель на неё расширяется.
	local EQUIP_GAP = 14
	local equipColWidth = SLOT_SIZE
	local panelWidth = gridWidth + 40 + EQUIP_GAP + equipColWidth
	local panelHeight = gridHeight + 80

	-- Center the combined block (CraftPanel on the left + CenterPanel)
	-- horizontally on screen.
	local craftPanelWidth = 180
	local craftGap = 12
	local combinedWidth = craftPanelWidth + craftGap + panelWidth
	local centerPanelLeft = -combinedWidth / 2 + craftPanelWidth + craftGap

	local centerPanel = Instance.new("Frame")
	centerPanel.Name = "CenterPanel"
	centerPanel.Size = UDim2.new(0, panelWidth, 0, panelHeight)
	centerPanel.Position = UDim2.new(0.5, centerPanelLeft, 0.5, -panelHeight / 2)
	centerPanel.BackgroundColor3 = Color3.new(1, 1, 1) -- белый под градиент (он умножается)
	centerPanel.BorderSizePixel = 0
	centerPanel.Parent = screenGui

	local centerGradient = Instance.new("UIGradient")
	centerGradient.Color = ColorSequence.new(COLORS.panelTop, COLORS.panelBg)
	centerGradient.Rotation = 90
	centerGradient.Parent = centerPanel

	local centerCorner = Instance.new("UICorner")
	centerCorner.CornerRadius = UDim.new(0, 18)
	centerCorner.Parent = centerPanel

	local centerStroke = Instance.new("UIStroke")
	centerStroke.Color = COLORS.panelBorder
	centerStroke.Thickness = 4
	centerStroke.Parent = centerPanel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, 14, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "Инвентарь"
	title.TextColor3 = COLORS.titleText
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.TextStrokeTransparency = 0.6
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = centerPanel

	-- Валюты в шапке — тёмно-синие пилюли (иконка + число), как в прототипе.
	-- Имена "LogCount"/"PlasticCount" сохранены — их обновляет renderAllSlots.
	local function headerChip(name, icon, rightOffset)
		local chip = Instance.new("Frame")
		chip.Name = name .. "Chip"
		chip.AnchorPoint = Vector2.new(1, 0)
		chip.Position = UDim2.new(1, rightOffset, 0, 10)
		chip.Size = UDim2.new(0, 66, 0, 26)
		chip.BackgroundColor3 = COLORS.panelBorder
		chip.BorderSizePixel = 0
		chip.Parent = centerPanel
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(1, 0)
		cc.Parent = chip
		local ic = Instance.new("ImageLabel")
		ic.Size = UDim2.new(0, 18, 0, 18)
		ic.Position = UDim2.new(0, 5, 0, 4)
		ic.BackgroundTransparency = 1
		ic.Image = icon
		ic.ScaleType = Enum.ScaleType.Fit
		ic.Parent = chip
		local ct = Instance.new("TextLabel")
		ct.Name = name .. "Count"
		ct.Size = UDim2.new(1, -30, 1, 0)
		ct.Position = UDim2.new(0, 27, 0, 0)
		ct.BackgroundTransparency = 1
		ct.Text = "0" -- updated by renderAllSlots from slotData
		ct.TextColor3 = COLORS.lightText
		ct.Font = Enum.Font.GothamBold
		ct.TextSize = 14
		ct.TextXAlignment = Enum.TextXAlignment.Left
		ct.Parent = chip
	end
	-- Баланс пиратской валюты (вместо счётчиков дерева/листвы): логотип валюты из лобби,
	-- затем «БАЛАНС:» и число. Читаем атрибут игрока "Pirate" (PirateCurrency.server).
	local PIRATE_ICON = "rbxassetid://93617165412571"
	local balanceChip = Instance.new("Frame")
	balanceChip.Name = "PirateBalanceChip"
	balanceChip.AnchorPoint = Vector2.new(1, 0)
	balanceChip.Position = UDim2.new(1, -52, 0, 10) -- левее: не под кнопкой закрытия ✕
	balanceChip.AutomaticSize = Enum.AutomaticSize.X
	balanceChip.Size = UDim2.new(0, 0, 0, 28)
	balanceChip.BackgroundColor3 = COLORS.panelBorder
	balanceChip.BorderSizePixel = 0
	balanceChip.Parent = centerPanel
	do
		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(1, 0); cc.Parent = balanceChip
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 12); pad.Parent = balanceChip
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 6); layout.Parent = balanceChip
		local ic = Instance.new("ImageLabel")
		ic.Size = UDim2.new(0, 20, 0, 20); ic.BackgroundTransparency = 1
		ic.Image = PIRATE_ICON; ic.ScaleType = Enum.ScaleType.Fit; ic.LayoutOrder = 1; ic.Parent = balanceChip
		local ct = Instance.new("TextLabel")
		ct.Name = "PirateBalanceCount"
		ct.AutomaticSize = Enum.AutomaticSize.X
		ct.Size = UDim2.new(0, 0, 1, 0)
		ct.BackgroundTransparency = 1
		ct.Text = "БАЛАНС: 0"
		ct.TextColor3 = COLORS.lightText
		ct.Font = Enum.Font.GothamBold
		ct.TextSize = 15
		ct.LayoutOrder = 2
		ct.Parent = balanceChip
		local function refreshBalance()
			if ct.Parent then ct.Text = "БАЛАНС: " .. tostring(player:GetAttribute("Pirate") or 0) end
		end
		player:GetAttributeChangedSignal("Pirate"):Connect(refreshBalance)
		refreshBalance()
	end
	-- Inventory grid (these are slots 9-28)
	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "InventoryGrid"
	gridFrame.Size = UDim2.new(0, gridWidth, 0, gridHeight)
	-- Сетка прижата ВЛЕВО, а не отцентрована: справа теперь колонка экипировки,
	-- и по центру сетка наезжала бы на неё.
	gridFrame.Position = UDim2.new(0, 20, 0, 52)
	gridFrame.BackgroundTransparency = 1
	gridFrame.Parent = centerPanel

	-- Четыре слота экипировки: голова, торс, штаны, ноги. Первый ряд выровнен по
	-- первому ряду сетки, поэтому к SLOT_PAD прибавляемся так же, как ячейки внутри.
	buildEquipmentColumn(centerPanel, 20 + gridWidth + EQUIP_GAP, 52 + SLOT_PAD,
		SLOT_SIZE, SLOT_PAD)

	-- Clear any stale refs from a previous rebuild.
	table.clear(gridSlotVisuals)

	for i = 1, GRID_SLOTS do
		local row = math.floor((i - 1) / COLS)
		local col = (i - 1) % COLS

		local slot = Instance.new("TextButton")
		slot.Name = "Slot_" .. i
		slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		slot.Position = UDim2.new(0, SLOT_PAD + col * (SLOT_SIZE + SLOT_PAD), 0, SLOT_PAD + row * (SLOT_SIZE + SLOT_PAD))
		slot.BackgroundTransparency = SLOT_STYLE_GRID.emptyT
		slot.Text = ""
		slot.AutoButtonColor = false
		slot.Parent = gridFrame
		styleSlotBase(slot, SLOT_STYLE_GRID)

		gridSlotVisuals[i] = { button = slot }

		local globalIdx = HOTBAR_SLOTS + i

		slot.MouseEnter:Connect(function()
			if isSlotLocked(globalIdx) then return end
			showTooltipForSlot(globalIdx)
		end)
		slot.MouseLeave:Connect(function()
			hideTooltip()
		end)

		slot.MouseButton1Down:Connect(function()
			if isSlotLocked(globalIdx) then return end
			local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shiftHeld then
				quickTransfer(globalIdx)
				dragState.didDrag = true
				return
			end
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[globalIdx]
			if data then
				beginDragPending(globalIdx, data, mousePos, false)
			end
		end)

		slot.MouseButton2Down:Connect(function()
			if isSlotLocked(globalIdx) then return end
			local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shiftHeld then
				quickTransfer(globalIdx)
				dragState.didDrag = true
				return
			end
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[globalIdx]
			if data and data.type == "resource" and data.count and data.count > 1 then
				beginDragPending(globalIdx, data, mousePos, true)
			end
		end)
	end

	-- "NEED STRENGTH" над заблокированной частью сетки — красная пилюля по центру
	-- области (как в прототипе). applyUnlockedSlots() позиционирует/прячет контейнер.
	lockedOverlayLabel = Instance.new("Frame")
	lockedOverlayLabel.Name = "LockedOverlay"
	lockedOverlayLabel.BackgroundTransparency = 1
	lockedOverlayLabel.ZIndex = 10
	lockedOverlayLabel.Parent = gridFrame

	local needPill = Instance.new("Frame")
	needPill.Name = "Pill"
	needPill.AnchorPoint = Vector2.new(0.5, 0.5)
	needPill.Position = UDim2.fromScale(0.5, 0.5)
	needPill.AutomaticSize = Enum.AutomaticSize.XY
	needPill.BackgroundColor3 = COLORS.notAffordable
	needPill.BorderSizePixel = 0
	needPill.ZIndex = 11
	needPill.Parent = lockedOverlayLabel

	local needCorner = Instance.new("UICorner")
	needCorner.CornerRadius = UDim.new(1, 0)
	needCorner.Parent = needPill

	local needStroke = Instance.new("UIStroke")
	needStroke.Color = Color3.fromHex("8A2A12")
	needStroke.Thickness = 3
	needStroke.Parent = needPill

	local needPad = Instance.new("UIPadding")
	needPad.PaddingLeft = UDim.new(0, 16)
	needPad.PaddingRight = UDim.new(0, 16)
	needPad.PaddingTop = UDim.new(0, 7)
	needPad.PaddingBottom = UDim.new(0, 7)
	needPad.Parent = needPill

	local needText = Instance.new("TextLabel")
	needText.AutomaticSize = Enum.AutomaticSize.XY
	needText.Size = UDim2.new(0, 0, 0, 0)
	needText.BackgroundTransparency = 1
	needText.Text = "НУЖНА СИЛА"
	needText.LayoutOrder = 1
	needText.Font = Enum.Font.GothamBlack
	needText.TextSize = 16
	needText.TextColor3 = Color3.new(1, 1, 1)
	needText.TextStrokeColor3 = Color3.new(0, 0, 0)
	needText.TextStrokeTransparency = 0.6
	needText.ZIndex = 12
	needText.Parent = needPill

	-- вторая строка — сколько силы осталось до следующей ячейки. Ячейка
	-- открывается на каждом чётном уровне силы (Strength.server: +1 за 2 уровня),
	-- порог уровня растёт ×2 — с чётного уровня до ячейки два уровня.
	do
		local list = Instance.new("UIListLayout")
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 1)
		list.Parent = needPill
		local amount = Instance.new("TextLabel")
		amount.AutomaticSize = Enum.AutomaticSize.XY
		amount.BackgroundTransparency = 1
		amount.Font = Enum.Font.GothamBold
		amount.TextSize = 13
		amount.TextColor3 = Color3.fromRGB(255, 225, 215)
		amount.TextStrokeColor3 = Color3.new(0, 0, 0)
		amount.TextStrokeTransparency = 0.6
		amount.LayoutOrder = 2
		amount.ZIndex = 12
		amount.Text = ""
		amount.Parent = needPill

		task.spawn(function()
			local folder = player:WaitForChild("Characteristics", 30)
			if not folder then return end
			local lvlV = folder:WaitForChild("Strength", 30)
			local xpV = folder:WaitForChild("StrengthXP", 30)
			local reqV = folder:WaitForChild("StrengthXPRequired", 30)
			if not (lvlV and xpV and reqV) then return end
			local function refreshNeed()
				local lvl, xp, req = lvlV.Value, xpV.Value, reqV.Value
				if req <= 0 then amount.Text = "" return end
				local left = req - xp
				if lvl % 2 == 0 then left += req * 2 end
				amount.Text = ("осталось: %d"):format(math.max(0, math.ceil(left)))
			end
			refreshNeed()
			lvlV:GetPropertyChangedSignal("Value"):Connect(refreshNeed)
			xpV:GetPropertyChangedSignal("Value"):Connect(refreshNeed)
			reqV:GetPropertyChangedSignal("Value"):Connect(refreshNeed)
		end)
	end

	applyUnlockedSlots()

	-- ─── Left Crafting Panel (vertical category list) ───
	-- `craftPanelWidth`, `craftGap`, and `combinedWidth` are defined above
	-- when computing `centerPanelLeft`.
	local craftPanel = Instance.new("Frame")
	craftPanel.Name = "CraftPanel"
	craftPanel.Size = UDim2.new(0, craftPanelWidth, 0, panelHeight)
	craftPanel.Position = UDim2.new(0.5, -combinedWidth / 2, 0.5, -panelHeight / 2)
	craftPanel.BackgroundColor3 = Color3.new(1, 1, 1) -- белый под градиент
	craftPanel.BorderSizePixel = 0
	craftPanel.Parent = screenGui

	local craftGradient = Instance.new("UIGradient")
	craftGradient.Color = ColorSequence.new(COLORS.panelTop, COLORS.panelBg)
	craftGradient.Rotation = 90
	craftGradient.Parent = craftPanel

	local craftCorner = Instance.new("UICorner")
	craftCorner.CornerRadius = UDim.new(0, 18)
	craftCorner.Parent = craftPanel

	local craftStroke = Instance.new("UIStroke")
	craftStroke.Color = COLORS.panelBorder
	craftStroke.Thickness = 4
	craftStroke.Parent = craftPanel

	local craftTitle = Instance.new("TextLabel")
	craftTitle.Size = UDim2.new(1, -15, 0, 28)
	craftTitle.Position = UDim2.new(0, 0, 0, 8)
	craftTitle.BackgroundTransparency = 1
	craftTitle.Text = "Крафт"
	craftTitle.TextColor3 = COLORS.titleText
	craftTitle.Font = Enum.Font.GothamBlack
	craftTitle.TextSize = 19
	craftTitle.TextStrokeColor3 = Color3.new(0, 0, 0)
	craftTitle.TextStrokeTransparency = 0.6
	craftTitle.TextXAlignment = Enum.TextXAlignment.Center
	craftTitle.Parent = craftPanel

	-- Vertical category tabs
	local tabFrame = Instance.new("Frame")
	tabFrame.Name = "CategoryTabs"
	tabFrame.Size = UDim2.new(1, -20, 1, -55)
	tabFrame.Position = UDim2.new(0, 10, 0, 48)
	tabFrame.BackgroundTransparency = 1
	tabFrame.Parent = craftPanel

	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Vertical
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Padding = UDim.new(0, 8)
	tabsLayout.Parent = tabFrame

	for i, cat in CATEGORIES do
		local tab = Instance.new("TextButton")
		tab.Name = "Tab_" .. cat
		-- ⚠️ ВКЛАДКИ ДЕЛЯТ ВЫСОТУ ПОРОВНУ, А НЕ ПО 76 ПИКСЕЛЕЙ: пятая вкладка
		-- («Декор») с фиксированной высотой вылезала за панель.
		tab.Size = UDim2.new(1, 0, 1 / #CATEGORIES, -8)
		tab.LayoutOrder = i
		tab.BackgroundColor3 = COLORS.craftItemBg
		tab.TextColor3 = COLORS.titleText
		tab.Text = ""
		tab.Font = Enum.Font.GothamMedium
		tab.TextSize = 14
		tab.BorderSizePixel = 0
		tab.AutoButtonColor = false
		tab.Parent = tabFrame
		tab:SetAttribute("Category", cat)
		--[[ ВКЛАДКА ПАКА — ТОЛЬКО У ВЛАДЕЛЬЦА. Пака нет — её не видно, остальные
		     делят высоту между собой; купил — появилась сразу, без перезахода. ]]
		if cat == "DecorPack" then
			local function packVis()
				tab.Visible = player:GetAttribute("DecorPack_Default") == true
				local n = 0
				for _, t in ipairs(tabFrame:GetChildren()) do
					if t:IsA("TextButton") and t.Visible then n += 1 end
				end
				for _, t in ipairs(tabFrame:GetChildren()) do
					if t:IsA("TextButton") then t.Size = UDim2.new(1, 0, 1 / math.max(n, 1), -8) end
				end
			end
			packVis()
			player:GetAttributeChangedSignal("DecorPack_Default"):Connect(packVis)
		end

		-- Centered text label (category icons were removed on user request).
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, -20, 1, 0)
		label.Position = UDim2.new(0, 10, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = catLabel(cat)
		label.TextColor3 = COLORS.titleText
		label.Font = Enum.Font.GothamBlack
		label.TextSize = 17
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0.6
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Parent = tab

		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = UDim.new(0, 12)
		tabCorner.Parent = tab

		local tabStroke = Instance.new("UIStroke")
		tabStroke.Color = COLORS.panelBorder
		tabStroke.Thickness = 3
		tabStroke.Parent = tab

		tab.MouseEnter:Connect(function()
			if selectedCategory ~= cat then
				tab.BackgroundColor3 = COLORS.craftItemHover
			end
		end)
		tab.MouseLeave:Connect(function()
			if selectedCategory ~= cat then
				tab.BackgroundColor3 = COLORS.craftItemBg
			end
		end)

		tab.MouseButton1Click:Connect(function()
			openCategoryOverlay(cat)
			updateCategoryTabs()
		end)
	end

	-- Close button — красная скруглённая кнопка (как в прототипе)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -36, 0, 8)
	closeBtn.BackgroundColor3 = COLORS.notAffordable
	closeBtn.Text = ""
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = true
	closeBtn.Parent = centerPanel

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 10)
	closeBtnCorner.Parent = closeBtn

	local closeBtnStroke = Instance.new("UIStroke")
	closeBtnStroke.Color = Color3.fromHex("8A2A12")
	closeBtnStroke.Thickness = 3
	closeBtnStroke.Parent = closeBtn

	-- White "X" drawn from two bars (the ✕ glyph doesn't render in this font)
	for _, rot in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(16, 4)
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		bar.BorderSizePixel = 0
		bar.Rotation = rot
		local barCorner = Instance.new("UICorner")
		barCorner.CornerRadius = UDim.new(1, 0)
		barCorner.Parent = bar
		bar.Parent = closeBtn
	end

	closeBtn.MouseButton1Click:Connect(closeUI)

	-- Raise hotbar above inventory
	if hotbarGui then hotbarGui.DisplayOrder = 15 end

	updateUI()
end

-- Пока игрок не подобрал рюкзак (Workspace.BackPack, атрибут HasBackpack от
-- BackpackPickup.server.lua) — инвентарь не открывается. Закрытие не гейтим.
local function hasBackpack()
	return player:GetAttribute("HasBackpack") == true
end

local function toggleInventory()
	if isOpen then
		closeUI()
	else
		if not hasBackpack() then return end
		-- магазин торговца стоит на том же месте экрана — закрываем его
		if _G.CloseMerchantShop then pcall(_G.CloseMerchantShop) end
		isOpen = true
		inventoryCraftEvent:FireServer("requestRecipes")
		buildUI()
	end
end

-- Expose an open hook so other scripts (e.g. the mercenary backpack
-- UI) can force the main inventory open alongside their own UI.
_G.OpenInventory = function()
	if not hasBackpack() then return end
	if not isOpen then
		isOpen = true
		inventoryCraftEvent:FireServer("requestRecipes")
		buildUI()
	end
end
_G.IsInventoryOpen = function() return isOpen end

-- Expose slot hit-testing so external UIs (merc backpack drag) can find
-- which player-inventory slot the mouse is over.
_G.FindSlotUnderMouse = function(mousePos)
	return findSlotUnderMouse(mousePos)
end

-- Queue a preferred target slot for the next distributeResource call.
-- Used by the merc backpack drag so items land where the user drops them.
_G.PendingTargetSlot = nil

-- ─── Input ───

local numberKeys = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if GamepadInput.isKey(input, Enum.KeyCode.E) then
		-- Hard guard: if the player is currently holding the Phone tool the
		-- inventory must NEVER toggle on E, even if PhoneMenu's
		-- `_G.SuppressInventoryToggle` hook hasn't caught up yet. We check
		-- the live character directly so the two UIs can't race.
		local char = player.Character
		local equipped = char and char:FindFirstChildOfClass("Tool")
		if equipped and (equipped.Name == "Phone" or equipped.Name == "leaf bag" or equipped.Name == "Sand Bag") then
			-- Phone owns its own E binding (close phone UI). Leaf bag
			-- owns its own E binding too (open seed picker via
			-- SeedBagUI.client.lua) — letting the regular inventory
			-- toggle on top of it would cover the picker.
			-- ⚠️ КРУЖКИ (CupState) ЗДЕСЬ БОЛЬШЕ НЕТ: E с кружкой когда-то поливал
			-- грядку, теперь полив — кликом, а исключение просто не давало открыть
			-- инвентарь с кружкой в руках.
			return
		end
		-- Defer the toggle decision until the end of the current
		-- resumption cycle. Roblox does not guarantee InputBegan handler
		-- order between scripts, so DropItem.client.lua's E handler may
		-- run either before or after this one. By deferring, we're
		-- guaranteed that any pickup-in-the-same-frame has already
		-- stamped `_G.LastPickupTime` by the time we re-check — and we
		-- can reject the toggle cleanly without fighting over ordering.
		task.defer(function()
			if (os.clock() - (_G.LastPickupTime or 0)) < 0.2 then
				return
			end
			if _G.SuppressInventoryToggle then
				return
			end
			-- Re-check the Phone guard: the player could have equipped
			-- the Phone between the original press and this deferred
			-- evaluation (unlikely, but cheap to verify).
			local char2 = player.Character
			local equipped2 = char2 and char2:FindFirstChildOfClass("Tool")
			if equipped2 and (equipped2.Name == "Phone" or equipped2.Name == "leaf bag" or equipped2.Name == "Sand Bag") then
				return
			end
			toggleInventory()
		end)
	end
	-- геймпад: L1/R1 дают номер соседнего занятого слота (GamepadAdapter)
	local slotNum = numberKeys[input.KeyCode]
		or (typeof(_G.GamepadHotbarStep) == "function" and _G.GamepadHotbarStep(input.KeyCode))
	if slotNum then
		-- Don't swap to a hotbar tool while the phone (or any other
		-- full-screen overlay) is on top — the player is interacting
		-- with the overlay, not trying to switch tools. Prevents
		-- pressing "1..8" from unequipping the phone and revealing
		-- a hotbar item behind the open menu.
		if isHoverBlockingOverlayOpen() or player:GetAttribute("OnTurret") then
			return
		end
		local data = slotData[slotNum]
		-- тап по маске в хотбаре тоже надевает её (телефон: ни драга, ни Shift)
		if data and data.type == "resource" and data.name and EquipmentDefs.isEquippable(data.name) then
			equipmentRemote:FireServer("equip", data.name)
		elseif data and data.type == "tool" then
			if data.toolInst then
				equipToolInstance(data.toolInst)
			else
				equipToolByName(data.toolName)
			end
			task.wait(0.1)
			renderAllSlots()
		elseif data and data.type == "resource" and data.name and BUSH_SEED_RESOURCE_SET[data.name] and bushActionEvent then
			-- Number-key on a bush-seed slot: same toggle as the slot-
			-- click branch above. Pressing the slot's hotkey while the
			-- seed is in hand unequips it (refund via AncestryChanged);
			-- otherwise asks the server for a new Tool.
			local char3     = player.Character
			local humanoid3 = char3 and char3:FindFirstChildOfClass("Humanoid")
			local heldBushSeed = nil
			if char3 then
				for _, t in char3:GetChildren() do
					if t:IsA("Tool") and t.Name == data.name
						and t:GetAttribute("BushSeedResource") == data.name then
						heldBushSeed = t
						break
					end
				end
			end
			if heldBushSeed and humanoid3 then
				humanoid3:UnequipTools()
			else
				bushActionEvent:FireServer("equipBushSeed", data.name)
			end
		elseif data and data.type == "resource" and data.name and SEED_RESOURCE_SET[data.name] and equipSeedEvent then
			-- Number-key on a seed-resource slot equips it as a Tool
			-- via the server bridge. Same path as the slot-click
			-- handler above.
			equipSeedEvent:FireServer(data.name)
		elseif data and data.type == "resource" and data.name and FOOD_RESOURCE_SET[data.name] and equipFoodEvent then
			-- Number-key on a food-resource slot toggles the food Tool
			-- in hand: equip if nothing held of this kind, unequip
			-- (refund via the server's AncestryChanged hook) if the
			-- player is already holding one. Mirrors the slot-click
			-- handler above so 1-8 and mouse-click behave the same.
			local char     = player.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			local heldFoodTool = nil
			if char then
				for _, t in char:GetChildren() do
					if t:IsA("Tool") and t.Name == data.name and t:GetAttribute("FoodResource") == data.name then
						heldFoodTool = t
						break
					end
				end
			end
			if heldFoodTool and humanoid then
				humanoid:UnequipTools()
			else
				equipFoodEvent:FireServer(data.name)
			end
		elseif data and data.type == "resource" and data.name
			and MATERIAL_RESOURCE_SET[data.name] and equipMaterialEvent then
			-- Хоткей на слоте материала плавильни: тот же тогл, что кликом.
			local charM     = player.Character
			local humanoidM = charM and charM:FindFirstChildOfClass("Humanoid")
			local heldMat = nil
			if charM then
				for _, t in charM:GetChildren() do
					if t:IsA("Tool") and t:GetAttribute("MaterialResource") == data.name then
						heldMat = t
						break
					end
				end
			end
			if heldMat and humanoidM then
				humanoidM:UnequipTools()
			else
				equipMaterialEvent:FireServer(data.name)
			end
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		if dragState.startPos then
			updateDragPosition(UserInputService:GetMouseLocation())
		end
		if tooltipGui and tooltipGui.Enabled then
			-- Self-heal: if an overlay opened after the tooltip was
			-- already showing (MouseLeave never fired because the
			-- cursor stayed inside the slot's rect), drop the
			-- tooltip on the next mouse move so it doesn't linger
			-- on top of the phone / shop / etc.
			if isHoverBlockingOverlayOpen() then
				hideTooltip()
			else
				updateTooltipPosition(UserInputService:GetMouseLocation())
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.Touch then
		if dragState.active or dragState.startPos then
			endDrag(UserInputService:GetMouseLocation())
		end
	end
end)

-- ─── Events ───

inventoryEvent.OnClientEvent:Connect(function(inv)
	inventory = inv
	updateUI()
end)

inventoryCraftEvent.OnClientEvent:Connect(function(action, data, inv)
	if action == "recipes" then
		recipes = data
		--[[ ⚠️ ИКОНКИ-МОДЕЛИ ГРЕЕМ ЗАРАНЕЕ, А НЕ ПРИ ОТКРЫТИИ МЕНЮ.
		     Декор и пак рисуются самой моделью (ModelIcon). Её меши и текстуры
		     начинали качаться, только когда ViewportFrame появлялся в меню, —
		     игрок открывал крафт и видел пустые ячейки. Как только сервер прислал
		     рецепты, по одному прогреваем шаблоны всех превью в фоне: к моменту
		     открытия меню всё уже в кэше. (Всё внутри обработчика — файл у
		     предела 200 локалей.) ]]
		do   -- рецепты приходят заново (новый день открывает новые) — греем только новые имена
			_G.CraftIconsSeen = _G.CraftIconsSeen or {}
			task.spawn(function()
				local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))
				local ContentProvider = game:GetService("ContentProvider")
				local seen = _G.CraftIconsSeen
				local warmed = 0
				for _, r in ipairs(type(data) == "table" and data or {}) do
					local name = type(r) == "table" and r.preview
					if type(name) == "string" and name ~= "" and not seen[name] then
						seen[name] = true
						local tpl = AssetFind.find(name)
						if tpl then
							pcall(function() ContentProvider:PreloadAsync({ tpl }) end)
							-- и сразу рисуем в пуле: меню возьмёт уже отрисованную рамку
							require(ReplicatedStorage:WaitForChild("ModelIcon")).warm(tpl)
							task.wait(0.05)   -- по одному, без просадки кадров
							warmed = warmed + 1
						end
					end
				end
				--[[ ⚠️ И КАРТИНКИ РЕЦЕПТОВ. Огнемёт в крафте — картинка, а не модель, и
				     в общий прогрев (AssetPreload) она не попадала: тот берёт имена из
				     справочников, а огнемёта там нет — его иконка всплывала, когда до
				     неё долистаешь. Берём ровно то, что нарисует меню: картинку рецепта
				     (или GetItemIcon по имени) и картинки материалов. ]]
				local imgs = {}
				local function addImg(id)
					if type(id) == "string" and id ~= "" then table.insert(imgs, id) end
				end
				for _, r in ipairs(type(data) == "table" and data or {}) do
					if type(r) == "table" then
						addImg((r.icon ~= "" and r.icon) or (typeof(_G.GetItemIcon) == "function" and _G.GetItemIcon(r.name)))
						for item in pairs(type(r.costs) == "table" and r.costs or {}) do
							if typeof(_G.GetItemIcon) == "function" then addImg(_G.GetItemIcon(item)) end
						end
					end
				end
				local imgN = require(ReplicatedStorage:WaitForChild("ModelIcon")).warmImages(imgs)
				if imgN > 0 then print(("[Крафт/иконки] картинок рецептов нарисовано скрыто: %d"):format(imgN)) end
				if warmed > 0 then print(("[Крафт/иконки] заготовлено заранее: %d"):format(warmed)) end
			end)
		end
		-- ⚠️ КИРКА УБРАНА ИЗ КРАФТА (по решению геймдизайна, система жива).
		-- Она дописывалась В СПИСОК ПРЯМО ЗДЕСЬ, на клиенте, мимо серверного
		-- перечня рецептов — поэтому убрать её из InventoryCrafting было мало бы:
		-- клиент вернул бы карточку обратно. Возвращать — записью в recipes на
		-- сервере, эта вставка больше не нужна.
		-- Inject Stone_Axe recipe if not present (StoneAxeSystem
		-- handles crafting via its own InventoryCraft listener; the
		-- recipe metadata only needs to reach the menu so the player
		-- can SEE + click the entry).
		local hasStoneAxe = false
		for _, r in recipes do
			if r.name == "Stone_Axe" then hasStoneAxe = true break end
		end
		if not hasStoneAxe then
			table.insert(recipes, {
				name = "Stone_Axe",
				displayName = "Каменный топор",
				icon = "rbxassetid://112306255674133",
				costs = {Log = 1, Stone = 3, Rope = 1},
				craftType = "tool",
				category = "Tools",
				description = "Топор с каменным лезвием: рубит пальмы и банановые деревья на островах, даёт брёвна.",
			})
		end
		if inv then inventory = inv end
		if isOpen then
			closeUI(true)
			isOpen = true
			buildUI()
		end
	elseif action == "denied" then
		-- сервер отказал уже после клика (например, не хватило жителей)
		if _G.Notify then
			_G.Notify({ type = "warn", icon = "🔒", title = "Не собрать",
				body = tostring(data or "Не хватает ресурсов") })
		end

	elseif action == "success" then
		local msgGui = Instance.new("ScreenGui")
		msgGui.DisplayOrder = 20
		msgGui.Parent = playerGui

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0, 250, 0, 40)
		label.Position = UDim2.new(0.5, -125, 0.3, 0)
		label.BackgroundTransparency = 1
		label.Text = "Готово!"
		label.TextColor3 = Color3.fromRGB(100, 255, 100)
		label.TextStrokeTransparency = 0.3
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 28
		label.Parent = msgGui

		local tween = TweenService:Create(label, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, -125, 0.25, 0),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function() msgGui:Destroy() end)
	end
end)

--[[ ⚠️ РЕЦЕПТЫ — СРАЗУ ПОСЛЕ ЗАХОДА, А НЕ ПРИ ПЕРВОМ ОТКРЫТИИ МЕНЮ.
     Список рецептов клиент спрашивал только в toggleInventory — значит, и
     заготовка иконок-моделей (ModelIcon.warm в обработчике "recipes") стартовала
     в ту же секунду, когда игрок уже смотрел на меню: иконки грузились на глазах.
     Спрашиваем заранее; при закрытом меню обработчик ничего не перестраивает. ]]
-- сразу: модели-иконки должны успеть нарисоваться под шторкой загрузки (ModelIcon)
task.defer(function()
	inventoryCraftEvent:FireServer("requestRecipes")
end)

-- ─── Init ───
-- Defer the initial UI build off the critical boot path. The
-- hotbar / grid render is not needed until the character actually
-- spawns and Roblox lets the player interact — running these
-- inline added ~1 s to perceived load on the destination place.
-- task.spawn yields the current thread immediately so the rest of
-- the script's module-level code can finish; the UI builds on the
-- next resume.
task.spawn(function()
	rebuildSlotData()
	buildHotbar()
	renderAllSlots()
end)

-- Track the replicated `Characteristics.UnlockedInventorySlots` value
-- (written by Strength.server.lua based on the player's Strength stat)
-- and repaint the grid whenever it changes.
task.spawn(function()
	local folder = player:WaitForChild("Characteristics")
	local value  = folder:WaitForChild("UnlockedInventorySlots")

	local function refresh()
		unlockedSlots = math.clamp(value.Value, BASE_UNLOCKED_SLOTS, TOTAL_SLOTS)
		applyUnlockedSlots()
	end

	refresh()
	value:GetPropertyChangedSignal("Value"):Connect(refresh)
end)

local backpack = player:WaitForChild("Backpack")
backpack.ChildAdded:Connect(function() task.wait(0.1) updateUI() end)
backpack.ChildRemoved:Connect(function() task.wait(0.1) updateUI() end)

player.CharacterAdded:Connect(function(char)
	-- Reconnect to new Backpack after respawn
	local newBackpack = player:WaitForChild("Backpack")
	newBackpack.ChildAdded:Connect(function() task.wait(0.1) updateUI() end)
	newBackpack.ChildRemoved:Connect(function() task.wait(0.1) updateUI() end)

	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then task.wait(0.1) updateUI() end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then task.wait(0.1) updateUI() end
	end)

	-- ⚠️ ПЕРЕСОБРАТЬ СЛОТЫ СРАЗУ ПОСЛЕ РЕСПАВНА.
	-- Выше мы только ПОДПИСАЛИСЬ на новый рюкзак, но сами ничего не обновили.
	-- Если после возрождения в рюкзаке ничего не менялось, обновление не
	-- приходило вовсе — и в хотбаре оставались иконки, привязанные к тулам
	-- уничтоженного персонажа: слот выглядит занятым, а нажатие ничего не даёт.
	task.wait(0.2) -- рюкзаку нужен кадр, чтобы наполниться после респавна
	updateUI()
end)

if player.Character then
	player.Character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then task.wait(0.1) updateUI() end
	end)
	player.Character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then task.wait(0.1) updateUI() end
	end)
end

-- ─── Listen for saved slot layout restore from server ───
task.spawn(function()
	if not slotLayoutEvent then
		slotLayoutEvent = ReplicatedStorage:WaitForChild("SlotLayoutSync", 10)
	end
	if slotLayoutEvent then
		slotLayoutEvent.OnClientEvent:Connect(function(action, savedLayout)
			if action == "restore" and typeof(savedLayout) == "table" then
				-- Apply saved slot positions
				for i = 1, TOTAL_SLOTS do
					slotData[i] = nil
				end
				for slotStr, itemData in savedLayout do
					local slotNum = tonumber(slotStr)
					if slotNum and slotNum >= 1 and slotNum <= TOTAL_SLOTS and typeof(itemData) == "table" then
						slotData[slotNum] = {
							type = itemData.type,
							name = itemData.name,
							count = itemData.count,
							icon = itemData.icon,
							toolName = itemData.toolName,
						}
					end
				end
				slotsInitialized = true
				renderAllSlots()
				print("[InventoryUI] Restored saved slot layout")
			end
		end)
	end
end)

-- ─── Periodic sync: keep server layout up to date at all times ───
task.spawn(function()
	while true do
		task.wait(0.2)
		syncSlotLayoutToServer()
	end
end)

-- ─── Кнопка-рюкзак (появляется после подбора рюкзака) ───
-- Иконка слева по центру экрана; клик/тап открывает инвентарь (на телефоне это
-- единственный способ — клавиши E там нет). Сам арт уже содержит бейдж «E».
-- Подпись «Инвентарь» авто-переводится Roblox на язык игрока (AutoLocalize).

--[[ ⚠️ МОДУЛЬ МАСШТАБА БЕРЁМ ЗДЕСЬ, ДО ПЕРВОГО ЖЕ ОБРАЩЕНИЯ.
     Ниже по файлу есть свой require внутри другого блока — на кнопку рюкзака он
     не распространяется. Я этого не заметил и позвал Hud.text() выше по тексту:
     переменная была ещё nil, скрипт падал прямо здесь, и кнопка инвентаря не
     создавалась вовсе — рюкзак подбирался, а иконка не появлялась. ]]
local Hud = require(game:GetService("ReplicatedStorage"):WaitForChild("HudScale"))

local backpackBtnGui = Instance.new("ScreenGui")
backpackBtnGui.Name = "BackpackButton"
backpackBtnGui.ResetOnSpawn = false
backpackBtnGui.IgnoreGuiInset = true
backpackBtnGui.DisplayOrder = 8
backpackBtnGui.Enabled = player:GetAttribute("HasBackpack") == true
backpackBtnGui.Parent = playerGui

local bpHolder = Instance.new("Frame")
bpHolder.AnchorPoint = Vector2.new(0, 0.5)
--[[ ⚠️ ЛЕВЫЙ ОТСТУП ТОЖЕ МАСШТАБИРУЕТСЯ, И ВОТ ПОЧЕМУ ЭТО ВАЖНО.
     Здесь стояло сырое 12. UIScale на холдере жмёт его РАЗМЕР, но не собственную
     позицию: иконка ужималась, а отступ слева оставался компьютерным — рюкзак
     выбивался из столбика вправо на семь пикселей. Соседи считают отступ через
     gap() (Квесты — gap(19), Настройки — gap(12)), и из-за этого подпись
     «Инвентарь» заезжала на иконку «Карты» справа. Ровно это и видно на
     скриншоте.
     Число то же, что у Настроек, — они стоят в одном столбике. ]]
bpHolder.Position = UDim2.new(0, Hud.gap(12), 0.5, 0)
bpHolder.Size = UDim2.fromOffset(92, 102)
bpHolder.BackgroundTransparency = 1
bpHolder.Parent = backpackBtnGui

local bpButton = Instance.new("ImageButton")
bpButton.Name = "OpenInventory"
bpButton.AnchorPoint = Vector2.new(0.5, 0)
bpButton.Position = UDim2.new(0.5, 0, 0, 0)
bpButton.Size = UDim2.fromOffset(76, 76)
bpButton.BackgroundTransparency = 1
-- ⚠️ ДВЕ КАРТИНКИ: С БИНДОМ И БЕЗ.
-- На кнопке нарисована клавиша (E), и на телефоне это вранье — клавиатуры у него
-- нет. Рисовать значок клавиши поверх иконки кодом нельзя: он вшит в саму
-- картинку, поэтому под телефон отдельный ассет, без клавиши.
bpButton.Image = require(ReplicatedStorage:WaitForChild("HudScale")).isPhone()
	and "rbxassetid://134805336581319"    -- телефон: без клавиши
	or  "rbxassetid://128180761798479"    -- клавиатура: с «E»
bpButton.ScaleType = Enum.ScaleType.Fit
bpButton.Parent = bpHolder

local bpScale = Instance.new("UIScale")
bpScale.Parent = bpButton
bpButton.MouseEnter:Connect(function() bpScale.Scale = 1.07 end)
bpButton.MouseLeave:Connect(function() bpScale.Scale = 1 end)

local bpLabel = Instance.new("TextLabel")
bpLabel.AnchorPoint = Vector2.new(0.5, 0.5)
--[[ ⚠️ ПИКСЕЛИ, А НЕ ДОЛЯ ВЫСОТЫ.
     Долей (0.92) я это уже пробовал, и на компьютере подпись уехала вниз: у
     «Инвентаря» родитель — холдер 92×102, а не сама кнопка 76×76, и 92% от
     холдера это на два десятка пикселей ниже нужного. Доля тут вообще
     обманчива: у двух подписей разные родители.
     Число 70 — авторское, оно и было верным для кнопки.

     ⚠️ И ВОТ ЗДЕСЬ ЧИСЛА ИДУТ СЫРЫМИ, БЕЗ px(). Холдер целиком сжат UIScale
     (ниже по файлу, applyScaleLive), а UIScale уже умножает ВСЁ внутри себя.
     Пропустив число ещё и через px(), я применял масштаб ДВАЖДЫ: 70 → 43 → 26,
     и подпись «Инвентарь» вставала не под рюкзаком, а поперёк него, вдвое
     мельче «Квестов» рядом. Внутри отмасштабированного холдера верстают в
     компьютерных пикселях — телефон досчитает сам. ]]
bpLabel.Position = UDim2.new(0.5, 0, 0, 70)
--[[ ⚠️ НА ТЕЛЕФОНЕ КОРОБКА ПОДПИСИ УЖЕ — ПО ИКОНКЕ, А НЕ ПО ХОЛДЕРУ.
     Холдер шире своей иконки (92 против 76), и подпись во всю его ширину на
     компьютере просто висит с запасом. На телефоне же весь столбик уезжает
     влево, промежуток между колонками сжимается сильнее иконок — и этот запас
     упирается в «Карту» справа. Сужаем до ширины иконки, как у соседей
     (у них коробка ровно иконка + 6). Компьютера правка не касается. ]]
bpLabel.Size = Hud.isPhone() and UDim2.new(0, 76 + 6, 0, 20) or UDim2.new(1, 6, 0, 20)
bpLabel.TextScaled = true
--[[ ⚠️ ПОТОЛОК КЕГЛЯ ЗДЕСЬ ЛОКАЛЬНЫЙ, А СРАВНИВАТЬ ЕГО НАДО С ЭКРАННЫМ.
     У соседей по столбику (Квесты, Магазин, Карта) потолок задан как
     Hud.text(16) — это уже ЭКРАННЫЕ пиксели, их UIScale не трогает. Внутри
     холдера то же число означает ЛОКАЛЬНЫЕ, и UIScale делает из шестнадцати
     около десяти: подпись рюкзака выходила на пятую часть мельче соседних —
     заметно, хотя стоит рядом.
     Делим на масштаб холдера, чтобы на экране получился тот же кегль. На
     компьютере масштаб равен единице, и число остаётся прежним. ]]
Instance.new("UITextSizeConstraint", bpLabel).MaxTextSize =
	math.floor(Hud.text(16) / math.max(Hud.iconFactor(), 0.1) + 0.5)
bpLabel.ZIndex = 2
bpLabel.BackgroundTransparency = 1
bpLabel.Text = "Инвентарь"
bpLabel.AutoLocalize = true
bpLabel.Font = Enum.Font.GothamBold
bpLabel.TextSize = 16   -- внутри UIScale-холдера числа сырые, см. выше
bpLabel.TextColor3 = Color3.new(1, 1, 1)
bpLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
bpLabel.TextStrokeTransparency = 0.3
bpLabel.Parent = bpHolder

bpButton.Activated:Connect(toggleInventory)

-- ⚠️ НА ТЕЛЕФОНЕ СЖИМАЕМ ВЕСЬ ХОЛДЕР ЦЕЛИКОМ.
-- Размеры тут в пикселях и подбирались на мониторе; на узком экране рюкзак с
-- подписью занимал непропорционально много и налезал на соседей. Здесь удобнее
-- один UIScale на holder, а не пересчёт каждого числа: внутренняя вёрстка (кнопка,
-- подпись, наезд подписи на низ рюкзака) остаётся ровно такой же.
-- UIScale именно на bpHolder, а НЕ на bpButton: у кнопки свой UIScale занят
-- наведением (bpScale выше), второй бы с ним спорил.
-- applyScaleLive — чтобы поворот телефона из портрета в ландшафт пересчитывался.
-- iconFactor, а не factor: рюкзак — кнопка того же столбика, что Квесты, Карта и
-- Настройки, и сжиматься должна тем же множителем (см. HudScale.iconFactor).
do
	local Hud = require(ReplicatedStorage:WaitForChild("HudScale"))
	Hud.applyScaleLive(bpHolder, Hud.iconFactor)
end

player:GetAttributeChangedSignal("HasBackpack"):Connect(function()
	backpackBtnGui.Enabled = player:GetAttribute("HasBackpack") == true
end)

-- Жители — такая же цена, как материалы, только приходят атрибутом: без этой
-- подписки список крафта не перекрашивался бы, пока меню открыто.
player:GetAttributeChangedSignal("Villagers"):Connect(function()
	if isOpen and rebuildCraftList then rebuildCraftList() end
end)

--[[ ═══ ПУЛЕМЁТ / ПУШКА: ХОТБАР УЕЗЖАЕТ ВНИЗ (ROBLOX-10) ═══
     TurretClient и CannonControl ставят игроку атрибут OnTurret. Пока он стоит:
     предмет из рук убирается, взять новый нельзя (ни цифрой, ни тапом — см.
     equipToolInstance / equipToolByName), а панель быстрого выбора плавно уезжает
     за низ экрана. Сошли с турели — панель возвращается на своё место.
     Своё место берём в момент ухода: вёрстка хотбара может его менять. ]]
do
	local SLIDE = 260   -- на сколько пикселей вниз уезжает панель
	local homePos, tween = nil, nil
	local function slide(down)
		local bar = hotbarGui and hotbarGui:FindFirstChild("Hotbar")
		if not bar then return end
		if tween then tween:Cancel() tween = nil end
		if down then
			if not homePos then homePos = bar.Position end
			tween = TweenService:Create(bar, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = homePos + UDim2.fromOffset(0, SLIDE) })
		elseif homePos then
			tween = TweenService:Create(bar, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = homePos })
			homePos = nil
		else
			return
		end
		tween:Play()
	end
	local function dropTool()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then hum:UnequipTools() end
	end
	player:GetAttributeChangedSignal("OnTurret"):Connect(function()
		local on = player:GetAttribute("OnTurret") == true
		if on then dropTool() end
		slide(on)
	end)
	-- предмет попал в руки в обход хотбара (другие скрипты) — тоже убираем
	local function watchChar(char)
		char.ChildAdded:Connect(function(c)
			if c:IsA("Tool") and player:GetAttribute("OnTurret") then
				task.defer(dropTool)
			end
		end)
	end
	if player.Character then watchChar(player.Character) end
	player.CharacterAdded:Connect(function(char)
		player:SetAttribute("OnTurret", false)   -- умер на турели — блок снимаем
		watchChar(char)
	end)
end
