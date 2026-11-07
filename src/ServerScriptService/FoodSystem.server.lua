-- FoodSystem.server.lua
-- Lets the player "take fruit in hand" and eat it for hunger + HP.
-- Mirrors the seed-as-Tool pattern from SeedToolSystem (now retired):
-- the resource lives in the main inventory as a stack, clicking the
-- slot temporarily promotes one unit into a Tool, and an unconsumed
-- Tool returns to the stack on unequip.
--
-- Per-fruit hunger / HP values live in FOOD_DATA — extend that table
-- to add new consumables (cooked fish, jelly, etc.) without
-- touching the equip logic.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Подняты вместе со всей едой (было 15/25/20): фрукт подбирают на ходу, он
-- обязан остаться самой лёгкой едой — но не такой, чтобы его игнорировали.
local FOOD_DATA = {
	Banana    = { hunger = 20, hp = 6 },
	Coconut   = { hunger = 32, hp = 6, thirst = 25 },   -- кокосовая вода: и жажду тоже (владелец)
	Pineapple = { hunger = 26, hp = 6 },
	-- The user's Tool template is "PineApple" (capital A). Mirror
	-- the data here so the in-tool Script can look up by Tool.Name
	-- without a casing helper.
	PineApple = { hunger = 26, hp = 6 },
}

-- Cooked fish are an open-ended family: any inventory key ending in
-- "_Cooked" (produced by the campfire from a raw fish) is edible for
-- a flat ~35 % hunger. Keeping it a suffix rule means a newly adapted
-- fish needs zero changes here.
local COOKED_SUFFIX     = "_Cooked"
--[[ ⚠️ ЕДА СЫТНЕЕ, ЧЕМ БЫЛА, И У СТЕЙКА ЧИСЛО ЗАДАНО ПРЯМО.
     Шкала сытости — 100 (MAX_HUNGER в HungerSystem) и уходит она за световой
     день целиком. Прежние числа заставляли жевать по три-четыре порции подряд:
     жареная рыба 35, овощ 22, а сырое мясо и вовсе 10.5 — коровы хватало на
     полтора укуса, при том что за ней надо сходить на остров и убить её.
     Жареный стейк теперь ровно ПОЛОВИНА шкалы — так просил владелец. Число
     стоит числом, а не произведением: раньше оно выводилось из рыбы через
     множитель, и любая правка рыбы незаметно двигала стейк. Хочешь другую
     сытость мяса — правь эту строку, и только её. ]]
local COOKED_FISH_HUNGER = 40   -- было 35
local COOKED_FISH_HP     = 6    -- было 5
local COOKED_MEAT_HUNGER = 50   -- половина шкалы (MAX_HUNGER = 100)
local COOKED_MEAT_HP     = 8
--[[ ⚠️ СЫРОЕ ПОДНЯЛИ, НО РАЗРЫВ ОСТАВИЛИ БОЛЬШИМ.
     Пятая часть от жареного превращала сырьё в мусор: сырой стейк давал десять
     единиц из ста, и проще было выбросить. Треть — это уже «съедобно на
     крайний случай», и при этом костёр по-прежнему втрое выгоднее, то есть
     готовить смысл не пропал. ]]
local RAW_FISH_HUNGER_MULT = 0.35 -- было 0.2
local RAW_FISH_HP_MULT     = 0.35
local TILAPIA_RAW_TEXTURE_ID = "rbxassetid://711628404"
local TILAPIA_COOKED_TEXTURE_ID = "rbxassetid://121725790433759"
local LEGENDARY_RAW_TEXTURE_ID = "http://www.roblox.com/asset/?id=155812542"
local LEGENDARY_COOKED_TEXTURE_ID = "rbxassetid://138934138408588"
local LEGENDARY_RAW_TEXTURE_NUM = "155812542"
local LEGENDARY_COOKED_TEXTURE_NUM = "138934138408588"
local MEAT_RAW_TEXTURE_ID = "rbxassetid://96631156827637"
local MEAT_COOKED_TEXTURE_ID = "rbxassetid://81212406244264"
-- Картофель и свёкла делят одну пару текстур (см. CampFireSystem) — держать равным.
local VEG_RAW_TEXTURE_ID = "rbxassetid://80019572040251"
local VEG_COOKED_TEXTURE_ID = "rbxassetid://110431523187509"
-- Овощи сытнее сырой рыбы, но легче мяса; печёные дают полную норму.
-- Подняты вместе со всей едой (было 22/4): грядка — самая долгая цепочка в
-- игре (посадить, полить, дождаться), и её плод не должен уступать рыбе вдвое.
local VEG_HUNGER = 30
local VEG_HP     = 6
local VEG_RAW_MULT = 0.5 -- сырой овощ съедобен, и в отличие от мяса не противен

local function isCookedFish(name)
	return type(name) == "string"
		and #name > #COOKED_SUFFIX
		and name:sub(-#COOKED_SUFFIX) == COOKED_SUFFIX
end

local function isRawFish(name)
	if type(name) ~= "string" then return false end
	-- Raw fish inventory keys are authored as "<Type>_Fish".
	return #name > 5 and name:sub(-5) == "_Fish"
end

-- Окорочок (курица, чайка) — тоже сырое мясо: жарится в «Meat_Cooked»
-- (CampFireSystem.cookFish), сырым ест как мясо.
local function isRawMeat(name)
	return name == "Meat" or name == "Chicken_drumstick"
end

local function isCookedMeat(name)
	return name == "Meat_Cooked"
end

-- ОВОЩИ С ГРЯДКИ: картофель и свёкла, сырые и печёные.
-- Список явный, а не по суффиксу: "_Cooked" уже занят общим правилом жареной
-- рыбы, и без отдельной проверки печёный картофель считался бы рыбой.
local VEG_KEYS = {
	Potato = true, Beet = true,
	Potato_Cooked = true, Beet_Cooked = true,
}
local function isVeg(name)
	return type(name) == "string" and VEG_KEYS[name] == true
end

local function isAnyFish(name)
	return isRawFish(name) or isCookedFish(name)
end

local function isMeat(name)
	return isRawMeat(name) or isCookedMeat(name)
end

local function fishDecalState(inst)
	local n = inst.Name:lower():gsub("[%s_]+", "")
	if n:find("cooked", 1, true) then return "cooked" end
	if n:find("raw", 1, true) then return "raw" end
	return nil
end

local function applyFishVisualState(tool, wantCooked)
	for _, d in tool:GetDescendants() do
		if d:IsA("Decal") or d:IsA("Texture") then
			local state = fishDecalState(d)
			if state == "raw" then
				d.Transparency = wantCooked and 1 or 0
			elseif state == "cooked" then
				d.Transparency = wantCooked and 0 or 1
			end
		elseif d:IsA("SurfaceAppearance") and fishDecalState(d) == "raw" and wantCooked then
			d:Destroy()
		end
	end
end

local function applyFishMeshVisualState(tool, wantCooked)
	for _, d in tool:GetDescendants() do
		if d:IsA("MeshPart") then
			local tex = d.TextureID
			if type(tex) == "string" and tex:find(LEGENDARY_RAW_TEXTURE_NUM, 1, true) and wantCooked then
				d.TextureID = LEGENDARY_COOKED_TEXTURE_ID
			elseif type(tex) == "string" and tex:find(LEGENDARY_COOKED_TEXTURE_NUM, 1, true) and (not wantCooked) then
				d.TextureID = LEGENDARY_RAW_TEXTURE_ID
			elseif tex == VEG_RAW_TEXTURE_ID and wantCooked then
				d.TextureID = VEG_COOKED_TEXTURE_ID
			elseif tex == VEG_COOKED_TEXTURE_ID and (not wantCooked) then
				d.TextureID = VEG_RAW_TEXTURE_ID
			elseif tex == MEAT_RAW_TEXTURE_ID and wantCooked then
				d.TextureID = MEAT_COOKED_TEXTURE_ID
			elseif tex == MEAT_COOKED_TEXTURE_ID and (not wantCooked) then
				d.TextureID = MEAT_RAW_TEXTURE_ID
			end
		elseif d:IsA("SpecialMesh") then
			local tex = d.TextureId
			if type(tex) == "string" and tex:find(LEGENDARY_RAW_TEXTURE_NUM, 1, true) and wantCooked then
				d.TextureId = LEGENDARY_COOKED_TEXTURE_ID
			elseif type(tex) == "string" and tex:find(LEGENDARY_COOKED_TEXTURE_NUM, 1, true) and (not wantCooked) then
				d.TextureId = LEGENDARY_RAW_TEXTURE_ID
			end
		end
	end
end

-- Published for the in-Tool Script (src/Fruits/<Name> ( Tool )/Script).
-- The Script calls this on Tool.Activated to figure out how much
-- hunger / HP to grant, so the values stay in one place and a tuning
-- pass touches only this table.
_G.GetFoodData = function(name)
	if FOOD_DATA[name] then return FOOD_DATA[name] end
	-- ОВОЩИ. Проверяем ДО общего правила «_Cooked = жареная рыба»: иначе
	-- Potato_Cooked попал бы в рыбью ветку и дал рыбью сытость.
	if isVeg(name) then
		local cooked = name:sub(-#COOKED_SUFFIX) == COOKED_SUFFIX
		local mult = cooked and 1 or VEG_RAW_MULT
		return { hunger = VEG_HUNGER * mult, hp = VEG_HP * mult }
	end
	if isCookedMeat(name) then
		return { hunger = COOKED_MEAT_HUNGER, hp = COOKED_MEAT_HP }
	end
	if isRawMeat(name) then
		return {
			hunger = COOKED_MEAT_HUNGER * RAW_FISH_HUNGER_MULT,
			hp = COOKED_MEAT_HP * RAW_FISH_HP_MULT,
		}
	end
	if isCookedFish(name) then
		return { hunger = COOKED_FISH_HUNGER, hp = COOKED_FISH_HP }
	end
	if isRawFish(name) then
		return {
			hunger = COOKED_FISH_HUNGER * RAW_FISH_HUNGER_MULT,
			hp = COOKED_FISH_HP * RAW_FISH_HP_MULT,
		}
	end
	return nil
end

-- ПРИВЕСТИ ВИД ЕДЫ К СЫРОМУ / ЖАРЕНОМУ.
--
-- Нужно наружу, потому что мангал кладёт на решётку КЛОН ШАБЛОНА из
-- ReplicatedStorage, а шаблоны рыб авторские: у части из них по умолчанию
-- видна ЖАРЕНАЯ декаль. Сырая рыба попадала на решётку уже подрумяненной, и
-- понять, готова она или нет, было невозможно.
--
-- Правила «какая декаль/текстура за что отвечает» живут здесь же, где и
-- поедание, — второй копии в GrillSystem быть не должно (там уже так же
-- переиспользуется _G.CookFoodModel от костра).
_G.SetFoodVisualCooked = function(inst, wantCooked)
	if typeof(inst) ~= "Instance" then return end
	applyFishVisualState(inst, wantCooked and true or false)
	applyFishMeshVisualState(inst, wantCooked and true or false)
end

-- Shared eating animation. Anything held as a food Tool plays this
-- on Tool.Activated. User-authored templates that already ship with
-- an Animation child named "Eat" keep theirs; we only inject one
-- when the template is missing it (e.g. the Banana / Pineapple Tools
-- + the wrapped Coconut model).
-- ⚠️ АНИМАЦИЯ ДОЛЖНА ПРИНАДЛЕЖАТЬ ВЛАДЕЛЬЦУ ОПЫТА.
-- Roblox не даёт проигрывать чужие анимации: в логе это выглядит как
--   Failed to load animation ... The experience doesn't have access permission
-- и еда съедается молча, без движения. Этот ID — чужой, поэтому анимация еды
-- не работает ни у овощей, ни у рыбы с мясом.
-- Чинится НЕ кодом: залей свою анимацию поедания под тем же аккаунтом (или
-- группой), что и игра, и подставь её ID сюда.
local EAT_ANIMATION_ID = "rbxassetid://5973758927"

-- ⚠️ ИЩЕМ ПО КЛАССУ, А НЕ ПО ИМЕНИ.
-- Раньше и здесь, и в обработчике поедания стоял FindFirstChild("Eat"), который
-- возвращает ПЕРВОГО ребёнка с таким именем ЛЮБОГО класса. У авторских моделей
-- (овощи пришли одним мешем из FBX) рядом мог оказаться, например, звук с тем же
-- именем — тогда проверка `:IsA("Animation")` не проходила, и анимация просто
-- не игралась. Ошибки при этом никакой: еда съедалась молча, без движения.
local function findEatAnimation(tool)
	local named = nil
	for _, c in ipairs(tool:GetChildren()) do
		if c:IsA("Animation") then
			if c.Name == "Eat" then return c end
			named = named or c
		end
	end
	return named
end

--[[ ⚠️ ОВОЩИ, РЫБА И МЯСО БЕРУТ АНИМАЦИЮ У ФРУКТОВ.
     У авторских фруктов (Banana / Coconut / PineApple в ReplicatedStorage.Fruits)
     внутри тула лежит своя Animation "Eat", залитая владельцем опыта — она и
     играет. Овощи с грядки приходят голым мешем, и раньше им подставлялся
     EAT_ANIMATION_ID — чужой ассет, который Roblox молча не загружает. Поэтому
     банан ел с анимацией, а сырая картошка — без. Теперь ищем рабочую
     анимацию у любого фрукта и клонируем её; чужой ID остаётся последним
     запасным вариантом. ]]
local donorEatAnim = nil
local function findDonorEatAnimation()
	if donorEatAnim and donorEatAnim.Parent then return donorEatAnim end
	donorEatAnim = nil
	local fruits = ReplicatedStorage:FindFirstChild("Fruits")
	local roots = fruits and { fruits, ReplicatedStorage } or { ReplicatedStorage }
	for _, root in ipairs(roots) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Animation") and d.Name == "Eat" and d.AnimationId ~= ""
				and d.AnimationId ~= EAT_ANIMATION_ID then
				donorEatAnim = d
				return d
			end
		end
	end
	return nil
end

local function ensureEatAnimation(tool)
	local existing = findEatAnimation(tool)
	if existing then
		if existing.AnimationId == "" then
			local donor = findDonorEatAnimation()
			existing.AnimationId = donor and donor.AnimationId or EAT_ANIMATION_ID
		end
		return existing
	end
	local donor = findDonorEatAnimation()
	local anim = donor and donor:Clone() or Instance.new("Animation")
	-- Имя с запасом: если в модели уже есть НЕ-анимация по имени "Eat",
	-- одноимённый ребёнок только запутал бы поиск.
	anim.Name        = tool:FindFirstChild("Eat") and "EatAnim" or "Eat"
	if not donor then anim.AnimationId = EAT_ANIMATION_ID end
	anim.Parent      = tool
	return anim
end

local function loadEatTrack(humanoid, animator, eatAnim)
	if not eatAnim or not eatAnim:IsA("Animation") then return nil end
	-- Prefer Animator, but fall back to Humanoid:LoadAnimation for rigs
	-- where Animator hasn't replicated/initialized yet.
	if animator then
		local ok, t = pcall(function() return animator:LoadAnimation(eatAnim) end)
		if ok and t then return t end
	end
	if humanoid then
		local ok, t = pcall(function() return humanoid:LoadAnimation(eatAnim) end)
		if ok and t then return t end
	end
	return nil
end

local equipEvent = ReplicatedStorage:FindFirstChild("EquipFoodAsTool")
if not equipEvent then
	equipEvent = Instance.new("RemoteEvent")
	equipEvent.Name = "EquipFoodAsTool"
	equipEvent.Parent = ReplicatedStorage
end

while not _G.AddResourceToInventory or not _G.RemoveResourceFromInventory or not _G.GetInventory do
	task.wait(0.1)
end

-- ⚠️ КЛЮЧ РЕСУРСА ≠ ИМЯ 3D-МОДЕЛИ.
-- Овощи с грядки авторски названы Raft_potato / Raft_beet, а в инвентаре они
-- Potato / Beet. Поиск шёл строго по ключу, модель не находилась, и игрок
-- получал в руки ПУСТОЙ тул-заглушку с невидимым Handle — «свёкла в руках, а
-- модели нет».
--
-- Явная таблица нужна там, где имя расходится непредсказуемо; общее правило
-- "Raft_<ключ>" ниже подхватывает будущие овощи само, без правок здесь.
local FOOD_MODEL_NAMES = {
	Potato = "Raft_potato",
	Beet   = "Raft_beet",
}

local function findFoodTemplate(foodName)
	-- The user can author the template as either a Tool (already
	-- holdable) or a Model (we wrap it). Look top-level first, then
	-- recurse so a "Fruits" / "Trees_Grow" folder doesn't hide it.
	local function ok(inst)
		return inst and (inst:IsA("Tool") or inst:IsA("Model") or inst:IsA("BasePart"))
	end

	-- Печёный овощ берёт модель сырого: текстуру на «печёный» вид меняет
	-- applyFishMeshVisualState, отдельной модели для этого нет.
	local baseKey = foodName:gsub("_Cooked$", "")
	local aliases = {
		foodName,
		FOOD_MODEL_NAMES[foodName],
		FOOD_MODEL_NAMES[baseKey],
		"Raft_" .. baseKey:lower(),
	}
	for _, name in ipairs(aliases) do
		if name then
			local direct = ReplicatedStorage:FindFirstChild(name)
			if ok(direct) then return direct end
			local deep = ReplicatedStorage:FindFirstChild(name, true)
			if ok(deep) then return deep end
		end
	end

	local hit = ReplicatedStorage:FindFirstChild(foodName)
	if ok(hit) then return hit end
	hit = ReplicatedStorage:FindFirstChild(foodName, true)
	if ok(hit) then return hit end
	-- Case-insensitive fallback. The user's Pineapple Tool template
	-- is authored as "PineApple" (capital A) — FindFirstChild is
	-- case-sensitive, so a direct lookup misses it and we'd fall
	-- through to the invisible placeholder. Walk descendants once
	-- comparing lowercase names so any casing of the same word
	-- still resolves.
	local lower = foodName:lower()
	for _, child in ReplicatedStorage:GetDescendants() do
		if ok(child) and child.Name:lower() == lower then
			return child
		end
	end
	return nil
end

-- Prep a part so Roblox's Tool grip logic is happy with it: not
-- anchored, no collision against players, low mass so the rig isn't
-- dragged. Applied to every BasePart in the cloned template before
-- wrapping it in a Tool.
local function prepHoldablePart(part)
	if not part or not part:IsA("BasePart") then return end
	part.Anchored   = false
	part.CanCollide = false
	part.Massless   = true
end

-- Build a Tool around a Model / BasePart template. The Tool's Handle
-- is the Model's PrimaryPart (or its first BasePart). Every other
-- BasePart in the clone gets WeldConstrained to the Handle so the
-- whole shape follows the player's grip as one unit.
local function wrapModelAsTool(modelClone, foodName)
	local handle
	if modelClone:IsA("BasePart") then
		modelClone.Name = "Handle"
		handle = modelClone
		local tool = Instance.new("Tool")
		tool.Name = foodName
		prepHoldablePart(handle)
		handle.Parent = tool
		return tool
	end

	handle = modelClone.PrimaryPart or modelClone:FindFirstChildWhichIsA("BasePart", true)
	if not handle then
		modelClone:Destroy()
		return nil
	end
	handle.Name = "Handle"

	-- Capture every other BasePart so we can weld them post-hoc.
	local others = {}
	for _, desc in modelClone:GetDescendants() do
		if desc:IsA("BasePart") and desc ~= handle then
			table.insert(others, desc)
		end
	end

	local tool = Instance.new("Tool")
	tool.Name = foodName

	-- Move everything from the model into the Tool, preserving the
	-- relative positioning that the user authored.
	for _, child in modelClone:GetChildren() do
		child.Parent = tool
	end
	modelClone:Destroy()

	prepHoldablePart(handle)
	for _, part in others do
		prepHoldablePart(part)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = handle
	end

	return tool
end

-- Build an edible Tool for a cooked fish. There is no separate cooked
-- template — we reuse the raw fish model, strip its authored (wiggle)
-- scripts so it sits still in hand, and show the "cooked" decal.
local function makeCookedFishTool(foodName)
	local rawKey = foodName:sub(1, #foodName - #COOKED_SUFFIX)
	local template = findFoodTemplate(rawKey)
		or findFoodTemplate((rawKey:gsub("_", " ")))
	if not template then return nil end

	local tool
	if template:IsA("Tool") then
		tool = template:Clone()
		tool.Name = foodName
		for _, d in tool:GetDescendants() do prepHoldablePart(d) end
	else
		tool = wrapModelAsTool(template:Clone(), foodName)
	end
	if not tool then return nil end

	-- Kill the authored wiggle/flop logic so the held fish is static.
	for _, d in tool:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
	end

	-- Show cooked, hide raw. Names are normalized (trim + lowercase)
	-- because the raw decal is authored as " raw" with a leading space —
	-- an exact == "raw" left it visible and overlapping the cooked look.
	applyFishVisualState(tool, true)
	applyFishMeshVisualState(tool, true)
	for _, d in tool:GetDescendants() do
		if d:IsA("MeshPart") and d.TextureID == TILAPIA_RAW_TEXTURE_ID then
			-- Tilapia cooked visual is authored via MeshPart.TextureID
			-- rather than raw/cooked decals, so convert it explicitly
			-- for the held Tool variant.
			d.TextureID = TILAPIA_COOKED_TEXTURE_ID
		elseif d:IsA("MeshPart") and d.TextureID == LEGENDARY_RAW_TEXTURE_ID then
			d.TextureID = LEGENDARY_COOKED_TEXTURE_ID
		elseif d:IsA("SpecialMesh") and d.TextureId == LEGENDARY_RAW_TEXTURE_ID then
			d.TextureId = LEGENDARY_COOKED_TEXTURE_ID
		end
	end

	return tool
end

local function makeFoodTool(foodName)
	if isCookedFish(foodName) then
		local fishTool = makeCookedFishTool(foodName)
		if fishTool then return fishTool end
	end

	local template = findFoodTemplate(foodName)
	-- Raw fish inventory keys are snake_case (e.g. Tilapia_Fish), while
	-- the authored 3D templates live under ReplicatedStorage.Fish with
	-- spaces (e.g. "Tilapia Fish"). Mirror cooked-fish lookup so raw
	-- fish can be equipped with their real model instead of falling back
	-- to the invisible placeholder handle.
	if (not template) and isRawFish(foodName) then
		template = findFoodTemplate((foodName:gsub("_", " ")))
	end
	if template then
		if template:IsA("Tool") then
			local clone = template:Clone()
			clone.Name = foodName
			-- Defensive: a hand-authored Tool template might still
			-- have anchored / collidable parts that throw on equip.
			for _, desc in clone:GetDescendants() do
				prepHoldablePart(desc)
			end
			if isRawFish(foodName) then
				applyFishVisualState(clone, false)
				applyFishMeshVisualState(clone, false)
			end
			return clone
		else
			-- Model or BasePart → wrap into a Tool so the player can
			-- actually hold it. Failed wrap (no BasePart inside) falls
			-- through to the placeholder below.
			local tool = wrapModelAsTool(template:Clone(), foodName)
			if tool then
				if isRawFish(foodName) then
					applyFishVisualState(tool, false)
					applyFishMeshVisualState(tool, false)
				end
				return tool
			end
		end
	end
	-- Placeholder Tool — invisible Handle so the equip mechanic still
	-- works even when no model has been authored yet. The icon shows
	-- up correctly in the hotbar via TOOL_ICONS in InventoryUI.
	local tool = Instance.new("Tool")
	tool.Name = foodName
	local handle = Instance.new("Part")
	handle.Name         = "Handle"
	handle.Size         = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.CanCollide   = false
	handle.Massless     = true
	handle.Parent       = tool
	return tool
end

local function alreadyHoldingFood(player, foodName)
	local char     = player.Character
	local backpack = player:FindFirstChild("Backpack")
	for _, container in ipairs({ char, backpack }) do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child.Name == foodName and child:GetAttribute("FoodResource") == foodName then
					return true
				end
			end
		end
	end
	return false
end

local function refundFood(player, tool)
	if not tool or tool:GetAttribute("Refunded") or tool:GetAttribute("Consumed") then
		if tool then tool:Destroy() end
		return
	end
	tool:SetAttribute("Refunded", true)
	local foodName = tool:GetAttribute("FoodResource")
	if foodName and player and player.Parent then
		-- Refund should NEVER materialize as a world drop. Retry inventory
		-- fetch for swap races and guarantee direct table restore.
		local function tryRefund()
			if not (_G.GetInventory and player and player.Parent) then return false end
			local inv = _G.GetInventory(player)
			if not inv then return false end
			inv[foodName] = (inv[foodName] or 0) + 1
			if _G.SendInventory then _G.SendInventory(player) end
			return true
		end

		if not tryRefund() then
			task.spawn(function()
				for _ = 1, 60 do -- up to ~3s for profile/inventory handoff
					task.wait(0.05)
					if tryRefund() then return end
				end
				warn("[FoodSystem] refund failed after retries for " .. tostring(foodName))
			end)
		end
	end
	tool:Destroy()
end

local function refundHeldFoodTools(player)
	local inv = _G.GetInventory and _G.GetInventory(player)
	if not inv then return false end
	local refundedAny = false
	local char = player.Character
	local backpack = player:FindFirstChild("Backpack")
	for _, container in ipairs({ char, backpack }) do
		if container then
			for _, t in container:GetChildren() do
				if t:IsA("Tool")
					and t:GetAttribute("FoodResource")
					and not t:GetAttribute("Consumed")
					and not t:GetAttribute("Refunded") then
					local key = t:GetAttribute("FoodResource")
					inv[key] = (inv[key] or 0) + 1
					t:SetAttribute("Refunded", true)
					t:Destroy()
					refundedAny = true
				end
			end
		end
	end
	if refundedAny and _G.SendInventory then _G.SendInventory(player) end
	return true
end

equipEvent.OnServerEvent:Connect(function(player, foodName)
	if typeof(foodName) ~= "string" then return end
	-- Whitelist check only — the actual hunger / hp values live
	-- in the in-tool Script (fruits) or _G.GetFoodData (cooked fish).
	if not _G.GetFoodData(foodName) then return end

	local inv = _G.GetInventory(player)
	-- Deterministic swap: return any currently held food-tools BEFORE
	-- removing the newly requested one, so fast fish-to-fish switching
	-- can't bleed stack counts during ancestry/replication races.
	if not refundHeldFoodTools(player) then return end
	inv = _G.GetInventory(player)
	if not inv then return end
	if (inv[foodName] or 0) < 1 then return end

	if alreadyHoldingFood(player, foodName) then return end

	local char     = player.Character
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	_G.RemoveResourceFromInventory(player, foodName, 1)
	if _G.SendInventory then
		_G.SendInventory(player)
	end

	local tool = makeFoodTool(foodName)
	if not tool then return end

	-- Fish templates may ship with authored movement/flop scripts that
	-- should never run while the fish is a held food item.
	if isAnyFish(foodName) then
		for _, d in tool:GetDescendants() do
			if d:IsA("Script") or d:IsA("LocalScript") then
				d.Disabled = true
			end
		end
	end

	tool:SetAttribute("FoodResource", foodName)
	tool:SetAttribute("OwnerUserId", player.UserId)
	tool.CanBeDropped = false
	ensureEatAnimation(tool)

	tool.Parent = backpack

	-- Force-equip — drop whatever's currently held and put the fruit
	-- in the player's hand. Without this the new Tool just parks in
	-- Backpack and the player thinks the click did nothing.
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function() humanoid:UnequipTools() end)
		pcall(function() humanoid:EquipTool(tool) end)
	end

	-- Refund guard arms on first Equipped — the Backpack→Character
	-- shuffle EquipTool just performed otherwise looks like an
	-- unequip and triggers a false refund.
	tool.Equipped:Once(function()
		tool:SetAttribute("Ready", true)
	end)

	-- Fruits handle Tool.Activated via their own per-Tool Script. Cooked
	-- fish have no such script (we strip the authored one so it doesn't
	-- wiggle in hand), so eat them here: play the Eat animation + the
	-- authored "Eat" sound, then restore hunger and consume.
	-- Овощи едим тем же обработчиком, что рыбу и мясо: своего скрипта внутри
	-- тула у них нет (он есть только у авторских фруктов).
	if isAnyFish(foodName) or isMeat(foodName) or isVeg(foodName) then
		tool.Activated:Connect(function()
			if tool:GetAttribute("Consumed") then return end
			-- НЕ ЕДИМ, ЕСЛИ ЦЕЛИМСЯ В РЕШЁТКУ МАНГАЛА.
			-- Клик там означает «положить жарить», а не «съесть». Перехватить
			-- нажатие на клиенте нельзя — активация тула идёт мимо
			-- пользовательских привязок ввода, поэтому запрет стоит здесь, в том
			-- же месте, где происходит само поедание. Отметку ставит
			-- GrillSystem по докладу клиента, она протухает за 1.5 с и
			-- перепроверяется по расстоянию до мангала.
			if _G.IsAimingAtGrill and _G.IsAimingAtGrill(player) then return end
			tool:SetAttribute("Consumed", true)

			local data = _G.GetFoodData(foodName)
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local animator = hum and hum:FindFirstChildOfClass("Animator")
			if hum and not animator then
				animator = Instance.new("Animator")
				animator.Parent = hum
			end
			local hrp = char and char:FindFirstChild("HumanoidRootPart")

			-- Eating animation. Force non-looping so Stopped fires and we
			-- can hold the fish for exactly the clip's length.
			local track
			local eatAnim = findEatAnimation(tool)
			if eatAnim then
				track = loadEatTrack(hum, animator, eatAnim)
				if not track then
					-- Не молчим: раньше провал загрузки был неотличим от
					-- «анимации вообще нет», и причину приходилось искать
					-- в общем потоке ошибок Studio.
					warn(("[FoodSystem] анимация поедания не загрузилась (%s) — "
						.. "скорее всего ассет принадлежит не владельцу опыта")
						:format(eatAnim.AnimationId))
				end
				if track then
					-- Match the Banana/Coconut/PineApple in-tool scripts:
					-- Action priority ensures the eat pose drives the arm
					-- even while a Tool is equipped.
					track.Priority = Enum.AnimationPriority.Action
					track.Looped = false
					track:Play()
				end
			end

			-- Shared eating sound lives in ReplicatedStorage.Fish. The
			-- asset is named "Eating  Sound" (double space) — match on a
			-- normalized name / "eating" substring so spacing/casing don't
			-- matter. Parent it to the character (NOT the Handle) so it
			-- survives the tool being destroyed and plays to the end.
			local fishFolder = ReplicatedStorage:FindFirstChild("Fish")
			local eatSound
			if fishFolder then
				for _, c in fishFolder:GetChildren() do
					if c:IsA("Sound") then
						local n = (c.Name:gsub("%s+", "")):lower()
						if n == "eatingsound" or c.Name:lower():find("eating") then
							eatSound = c
							break
						end
					end
				end
			end
			if eatSound then
				-- Lag the bite sound ~0.4 s behind the animation start so
				-- it lands on the chomp, matching the fruit feel.
				task.delay(0.4, function()
					local s = eatSound:Clone()
					s.Parent = hrp or workspace
					s:Play()
					s.Ended:Once(function() s:Destroy() end)
					task.delay(8, function() if s and s.Parent then s:Destroy() end end)
				end)
			else
				warn("[FoodSystem] no Eating Sound under ReplicatedStorage.Fish")
			end

			-- Держим еду в руке, пока идёт клип, и только потом съедаем.
			--
			-- ⚠️ ЖДЁМ ТОЛЬКО ТУ АНИМАЦИЮ, КОТОРАЯ РЕАЛЬНО ПОШЛА.
			-- Здесь стояло ожидание track.Stopped с потолком в 5 секунд — и оно
			-- оборачивалось ровно этими пятью секундами, если ассет анимации
			-- недоступен опыту (см. EAT_ANIMATION_ID выше). LoadAnimation в таком
			-- случае НЕ падает: трек создаётся, Play() отрабатывает, а вот кадров у
			-- него нет — значит Stopped не наступает НИКОГДА. Снаружи это выглядело
			-- как «звук съел, а свёкла осталась в руке»: движения нет, предмет висит,
			-- повторный клик не делает ничего (Consumed уже стоит).
			-- Признак загрузившегося клипа — Length больше нуля: у несостоявшегося он
			-- так и остаётся нулём. Фрукты этой ловушки избежали лишь потому, что
			-- ждут фиксированную паузу и Stopped не слушают вовсе.
			local EAT_FALLBACK = 1.2   -- столько же по ощущению, сколько клип
			if track then
				-- Length появляется не в тот же кадр — даём ассету догрузиться.
				local spent = 0
				while track.Length <= 0 and spent < 0.5 do
					task.wait(0.05)
					spent += 0.05
				end

				if track.Length > 0 then
					local done = false
					track.Stopped:Once(function() done = true end)
					-- потолок по самому клипу, а не общий на все случаи жизни
					local cap, waited = track.Length + 0.5, 0
					while not done and waited < cap do
						task.wait(0.05)
						waited += 0.05
					end
				else
					warn(("[FoodSystem] анимация поедания не проигралась (%s): ассет "
						.. "недоступен опыту. Загрузи свою анимацию под аккаунтом "
						.. "владельца игры и подставь её ID в EAT_ANIMATION_ID.")
						:format(eatAnim and eatAnim.AnimationId or "?"))
					task.wait(EAT_FALLBACK)
				end
			else
				task.wait(EAT_FALLBACK)
			end

			if data and player and player.Parent then
				_G.RestoreHunger(player, data.hunger, data.hp)
				-- кокос: молоко внутри утоляет и жажду
				if data.thirst and typeof(_G.GetThirst) == "function" and typeof(_G.SetThirst) == "function" then
					local cur = _G.GetThirst(player)
					if cur then _G.SetThirst(player, cur + data.thirst) end
				end
			end
			tool:Destroy()
		end)
	end

	tool.AncestryChanged:Connect(function(_, newParent)
		if not tool:GetAttribute("Ready") then return end
		if tool:GetAttribute("Consumed") then return end
		if newParent == nil then
			task.defer(function() refundFood(player, tool) end)
		elseif newParent and newParent:IsA("Backpack") then
			task.defer(function() refundFood(player, tool) end)
		end
	end)
end)