--[[
	ГАРНИЗОНЫ МАЛЫХ ОСТРОВОВ: верфь и малый остров.

	ЧТО ЗДЕСЬ:
	  • ГАРНИЗОН — пираты по маркерам Pt_* внутри модели. Кладутся в папку
	    Enemies, дальше их ведут те же системы, что и остальные острова:
	    IslandClearSystem (HP, полоски, смерть, зачистка) и PirateIslandAI (слух,
	    подозрение, бой, поводок).
	  • МАРШРУТЫ — каждый ходит своим кругом по точкам Pt_<имя>_WayN и
	    останавливается на каждой.
	  • ПЛЕННЫЕ — где они есть (малый остров): ребёнок в клетке, связанные руки,
	    выпускается штатным _G.FreePrisoners, когда гарнизон выбит.

	⚠️ ОДИН СКРИПТ НА ОБА ОСТРОВА, А НЕ ДВА ОДИНАКОВЫХ.
	Отличаются они только составом постов и наличием пленного — всё остальное
	(спавн, оружие по модели, маршрут, клетка) совпадает дословно. Третий остров
	такого рода добавляется строкой в ISLANDS, а не копией файла.

	⚠️ МАРШРУТ ВЕДЁМ ЧЕРЕЗ ТОЧКУ ДОМА, А НЕ СВОИМ MoveTo.
	PirateIslandAI в мирное время сам уводит пирата к HomeX/HomeZ и сам же
	переключает клипы ходьбы и простоя. Свой MoveTo рядом с ним — это два
	водителя на одну модель: они дёргают пирата в разные стороны, ровно как было с
	горящими NPC. Поэтому мы не ходим за пирата, а ПЕРЕСТАВЛЯЕМ ЕМУ ДОМ по
	точкам — и весь маршрут отрабатывает штатный ИИ, включая мгновенный отказ от
	прогулки, как только игрока заметили.

	⚠️ ВЗРЫВЫ И ПОЖАР ЗДЕСЬ НЕ ПОВТОРЯЮТСЯ.
	Бочки Virus_drum и красная трава Virus_crop_sm на этих островах те же, что на
	террасе, и обрабатывает их TerraceIsland.server.lua — ему добавлены имена.

	Числа постов — из garrison.json наборов (ShipIsle/README.md и
	SmallIsle/README.md, разделы «Гарнизон»).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Defs = require(ReplicatedStorage:WaitForChild("PirateIslandDefs"))

local LOG = "[Острова]"

-- ⚠️ ТИП БОЯ БЕРЁТСЯ ИЗ МОДЕЛИ, А НЕ ИЗ ПОСТА (Defs.CREW).
-- На террасе на этом уже обожглись: надсмотрщику прописали «ranged» при модели с
-- саблей, и он стрелял из клинка. Нужен стрелок — ставь стрелковую модель.
-- react — задержка реакции из README набора.
local ISLANDS = {
	ShipIsle_SCENE = {
		ru = "верфь",
		posts = {
			Shipwright = { crew = "Pirate_Deckhand",  react = 1.9, flees = true },
			Sawyer     = { crew = "Pirate_Cutthroat", react = 0.8 },
			Grower     = { crew = "Pirate_Deckhand",  react = 2.1, flees = true },
			Watch      = { crew = "Pirate_Bosun",     react = 0.0, boss = true },
		},
	},
	SmallIsle_SCENE = {
		ru = "малый остров",
		-- Двое на острове в 35 метров — это гарнизон: они никогда не дальше
		-- пятнадцати метров друг от друга и снять одного тихо нельзя.
		posts = {
			Watch  = { crew = "Pirate_Cutthroat", react = 0.0 },   -- мачете, длинный обход
			Keeper = { crew = "Pirate_Bosun",     react = 1.1, boss = true },  -- револьвер, короткий
		},
		-- Ребёнок в клетке за домом, лицом к двери хижины. Пленные идут ОТДЕЛЬНЫМ
		-- списком: всё, что читает posts, выдаёт оружие, и ребёнок оттуда вышел бы
		-- с мачете.
		prisoners = {
			Cap_Kid = { role = "Child", face = "kid", scale = 0.72 },
		},
	},
	--[[ ⚠️ ДВОЕ НА КПП, И ОБА НА ВЫШКАХ — ЭТО НЕ ЭКОНОМИЯ, А ЗАМЫСЕЛ ОСТРОВА.
	     Числа и роли — из OutpostIsle/garrison.json (пересчитывать руками нельзя,
	     они зависят от раскладки скал). Один смотрит в море, видит игрока первым
	     и поднимает тревогу; второй смотрит в сам проход. Отсюда разная задержка
	     реакции.
	     Модель решает, чем боец вооружён (Defs.CREW): нужен стрелок — ставим
	     стрелковую модель, а не переопределяем тип боя.

	     ⚠️ ОБА СО СТРЕЛКОВЫМ, И ЭТО ИСПРАВЛЕНИЕ, А НЕ ВКУСОВЩИНА.
	     На правой вышке стоял головорез с саблей (Pirate_Cutthroat, kind =
	     melee). С вышки саблей не достать никого: он попросту не мог причинить
	     игроку вреда — украшение, а не охрана. Ставим боцмана с револьвером:
	     стрелок, но не копия соседа — у канонира своя модель и своя роль
	     «поднял тревогу первым». ]]
	--[[ ЗАБЫТЫЙ КРАТЕР: двое СТОРОЖЕЙ с саблями на точках pirate_spawn_1/2
	     (папка Pirate). Маршрута нет — стоят на посту и стерегут сундуки. ]]
	Crater_Island = {
		ru = "кратер",
		posts = {
			Guard1 = { crew = "Pirate_Cutthroat", react = 0.6, markerName = "pirate_spawn_1" },
			Guard2 = { crew = "Pirate_Quarter",   react = 0.9, markerName = "pirate_spawn_2", boss = true },
		},
	},
	OutpostIsle_SCENE = {
		ru = "аванпост",
		posts = {
			Gate_Gunner = { crew = "Pirate_Gunner", react = 0.0, boss = true },
			Gate_Guard  = { crew = "Pirate_Bosun",  react = 0.9 },
		},
	},
	--[[ ОСТРОВ ФЕРМЕРОВ: посты не по маркерам Pt_*, а по ПЛОЩАДКАМ пакета —
	     Gameplay/Spawns/<Имя> с атрибутами Role и Route; маршрут — папка
	     Gameplay/Routes/<Route> с точками по атрибуту Order. Площадок 20:
	     12 Pirate, 3 Guard (конвой мутанта), 2 Scientist, 2 Worker, 1 Mutant.
	     Пиратов и охрану заселяем НАШИМИ пиратами (владелец), остальные площадки
	     пока пустые: мутанта, учёных и работников пакет вёл своим рантаймом, а
	     его мы не подключаем.
	     Модель по-прежнему решает, чем боец вооружён (Defs.CREW). Состав по
	     площадкам подбирается по кругу из списка roles[Role]. ]]
	Farmers_Game_Water = {
		ru = "остров фермеров",
		spawns = {
			roles = {
				Pirate = { "Pirate_Deckhand", "Pirate_Cutthroat", "Pirate_Gunner", "Pirate_Deckhand",
					"Pirate_Bosun", "Pirate_Cutthroat" },
				-- конвой мутанта: наши пираты, но вместо маршрута ходят за мутантом
				Guard  = { "Pirate_Quarter", "Pirate_Cutthroat", "Pirate_Bosun" },
			},
			escortRole = "Guard",
			react = 1.0,
			boss  = "Guard01",   -- квартирмейстер конвоя — реле тревоги
		},
		--[[ ОСТАЛЬНЫЕ 8 — РАНТАЙМ ПАКЕТА (ReplicatedStorage/FarmersIsland, наши
		     копии его модулей): трое охранников с дубинками сопровождают мутанта,
		     учёные лечат своих, работники поливают грядки и ждут освобождения.
		     Охрана и мутант помечены Hostile — зачистка считает их вместе с
		     нашими пиратами. ]]
		farmersRuntime = true,
		--[[ СТЕКЛО ТЕПЛИЦ: Material=Glass не рисует за собой полупрозрачные детали
		     (вода на острове — именно такие, клиентские). Меняем на пластик,
		     прозрачность и цвет те же. ]]
		glassToPlastic = "GH_Glass_",
	},
}

-- Сколько стоять на точке, прежде чем идти к следующей. Рабочий на посту должен
-- читаться работающим, а не марширующим по кругу.
local DWELL_MIN, DWELL_MAX = 6, 11

-- кратер: тот же гарнизон, как бы ни называлась модель острова
ISLANDS.Crater = ISLANDS.Crater_Island
ISLANDS.Forgotten_Crater_Island = ISLANDS.Crater_Island

local templateCache = {}
local function findTemplate(name)
	if templateCache[name] and templateCache[name].Parent then return templateCache[name] end
	local t = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:FindFirstChild(name, true)
	if t then templateCache[name] = t end
	return t
end

local warned = {}
local function warnOnce(key, text)
	if warned[key] then return end
	warned[key] = true
	warn(LOG .. " " .. text)
end

local function placeAt(model, marker)
	local _, size = model:GetBoundingBox()
	model:PivotTo(CFrame.new(marker.Position + Vector3.new(0, size.Y * 0.5, 0))
		* CFrame.Angles(0, math.atan2(-marker.CFrame.LookVector.X,
			-marker.CFrame.LookVector.Z), 0))
end

-- родной ИИ модели глушим: ведёт PirateIslandAI (иначе два водителя)
local function muteOwnScripts(npc)
	for _, d in ipairs(npc:GetDescendants()) do
		if d:IsA("Script") then
			local n = d.Name:lower()
			if n:find("zombie") or n:find("npcai") or n:find("combat")
				or n:find("chase") or n:find("attack") or n:find("ai") then
				d.Disabled = true
			end
		end
	end
end

-- Маршрут поста: сам пост и его точки Pt_<имя>_Way1..N по порядку.
local function routeOf(island, post, marker)
	local route = { marker.Position }
	local i = 1
	while true do
		local wp = island:FindFirstChild(("Pt_%s_Way%d"):format(post, i), true)
		if not (wp and wp:IsA("BasePart")) then break end
		table.insert(route, wp.Position)
		i += 1
	end
	return route
end

-- ⚠️ ПРОГУЛКА ИДЁТ ТОЛЬКО В МИРНОЕ ВРЕМЯ.
-- Пока пирата не заметили и он не горит, он обходит свои точки. Как только ИИ
-- поднял Detected, дом замирает на текущей точке: после боя пират вернётся
-- туда, а не к началу круга.
local function walkRoute(npc, route)
	if #route < 2 then return end
	local step = 1
	task.spawn(function()
		while npc.Parent do
			local hum = npc:FindFirstChildWhichIsA("Humanoid", true)
			if not hum or hum.Health <= 0 then return end

			local busy = npc:GetAttribute("Detected") == true
				or npc:GetAttribute("OnFire") == true
				or (npc:GetAttribute("Track") or 0) > 0
			if not busy then
				step = step % #route + 1
				local p = route[step]
				npc:SetAttribute("HomeX", p.X)
				npc:SetAttribute("HomeZ", p.Z)
			end
			task.wait(math.random(DWELL_MIN, DWELL_MAX))
		end
	end)
end

--[[ Посты с площадок пакета (см. Farmers_Game_Water выше): возвращает таблицу
     того же вида, что spec.posts, плюс маркеры и маршруты. ]]
local function postsFromSpawns(island, sp)
	local g = island:FindFirstChild("Gameplay")
	local folder = g and g:FindFirstChild("Spawns")
	local routes = g and g:FindFirstChild("Routes")
	if not folder then
		warnOnce(island.Name .. "_spawns", "нет папки Gameplay/Spawns на " .. island.Name)
		return {}
	end
	local posts, counters = {}, {}
	local list = folder:GetChildren()
	table.sort(list, function(a, b) return a.Name < b.Name end)
	for _, marker in ipairs(list) do
		if marker:IsA("BasePart") then
			local role = marker:GetAttribute("Role") or marker:GetAttribute("FarmersRole")
			local pool = sp.roles[role]
			if pool then
				counters[role] = (counters[role] or 0) + 1
				local route = { marker.Position }
				local rf = routes and routes:FindFirstChild(tostring(marker:GetAttribute("Route") or ""))
				if rf then
					local pts = {}
					for _, wp in ipairs(rf:GetChildren()) do
						if wp:IsA("BasePart") then table.insert(pts, wp) end
					end
					table.sort(pts, function(a, b)
						return (tonumber(a:GetAttribute("Order")) or 0) < (tonumber(b:GetAttribute("Order")) or 0)
					end)
					for _, wp in ipairs(pts) do
						if (wp.Position - marker.Position).Magnitude > 1 then table.insert(route, wp.Position) end
					end
				end
				local escort = (sp.escortRole == role) and (tonumber(marker:GetAttribute("EscortIndex")) or counters[role]) or nil
				posts[marker.Name] = {
					crew = pool[(counters[role] - 1) % #pool + 1],
					react = sp.react or 1.0,
					boss = (sp.boss == marker.Name) or nil,
					marker = marker, route = escort and { marker.Position } or route,
					escort = escort,
				}
			end
		end
	end
	return posts
end

--[[ КОНВОЙ МУТАНТА. Тем же приёмом, что маршрут: не водим пирата сами, а
     переставляем ему ДОМ — к мутанту, в свою точку треугольника вокруг него.
     Заметил игрока — штатный ИИ бросает дом и дерётся; мутант погиб — конвой
     остаётся стоять там, где он пал. ]]
local function escortMutant(npc, island, slot)
	local angle = (slot - 1) * math.pi * 2 / 3
	local off = Vector3.new(math.cos(angle) * 8, 0, math.sin(angle) * 8)
	task.spawn(function()
		local mutant
		while npc.Parent and island.Parent do
			local hum = npc:FindFirstChildWhichIsA("Humanoid", true)
			if not hum or hum.Health <= 0 then return end
			if not (mutant and mutant.Parent) then
				local g = island:FindFirstChild("Gameplay")
				local npcs = g and g:FindFirstChild("NPCs")
				if npcs then
					for _, m in ipairs(npcs:GetChildren()) do
						if m:GetAttribute("FarmersRole") == "Mutant" then mutant = m break end
					end
				end
			end
			local root = mutant and mutant:FindFirstChild("HumanoidRootPart")
			local mh = mutant and mutant:FindFirstChildOfClass("Humanoid")
			local busy = npc:GetAttribute("Detected") == true or npc:GetAttribute("OnFire") == true
				or (npc:GetAttribute("Track") or 0) > 0
			if root and mh and mh.Health > 0 and not busy then
				local p = root.Position + off
				npc:SetAttribute("HomeX", p.X)
				npc:SetAttribute("HomeZ", p.Z)
			end
			task.wait(1.2)
		end
	end)
end

local function spawnGarrison(island, spec)
	local enemies = island:FindFirstChild(Defs.ENEMIES_FOLDER)
	if not enemies then
		enemies = Instance.new("Folder")
		enemies.Name = Defs.ENEMIES_FOLDER
		enemies.Parent = island
	end

	local placed, routes = 0, 0
	local posts = spec.posts or (spec.spawns and postsFromSpawns(island, spec.spawns)) or {}
	for post, cfg in pairs(posts) do
		local marker = cfg.marker or (cfg.markerName and island:FindFirstChild(cfg.markerName, true))
			or island:FindFirstChild("Pt_" .. post, true)
		if not (marker and marker:IsA("BasePart")) then
			warnOnce(island.Name .. "_pt_" .. post,
				("нет маркера Pt_%s на %s — пост пуст"):format(post, island.Name))
		else
			local tpl = findTemplate(cfg.crew)
			if not tpl then
				warnOnce("crew_" .. cfg.crew,
					("модели «%s» нет в ReplicatedStorage — пост %s пуст"):format(cfg.crew, post))
			else
				local npc = tpl:Clone()
				npc.Name = cfg.crew .. "_" .. post

				local crew = Defs.CREW[cfg.crew] or { kind = "melee", damage = 10 }
				npc:SetAttribute("WeaponKind", crew.kind)
				npc:SetAttribute("MeleeDamage", (crew.kind == "melee") and crew.damage or nil)
				npc:SetAttribute("ShotDamage", (crew.kind == "ranged") and crew.damage or nil)
				npc:SetAttribute("IslandPost", post)
				npc:SetAttribute("HomeX", marker.Position.X)
				npc:SetAttribute("HomeZ", marker.Position.Z)
				npc:SetAttribute("WaterImmune", true)
				npc:SetAttribute("ReactDelay", cfg.react)
				if cfg.flees then npc:SetAttribute("Flees", true) end
				if cfg.boss then npc:SetAttribute("IslandBoss", true) end

				muteOwnScripts(npc)
				placeAt(npc, marker)
				npc.Parent = enemies

				local route = cfg.route or routeOf(island, post, marker)
				if cfg.escort then
					escortMutant(npc, island, cfg.escort)
				elseif #route > 1 then
					walkRoute(npc, route)
					routes += 1
				end
				placed += 1
			end
		end
	end
	return placed, routes
end

-- ── пленные ──
-- ⚠️ ПЛЕННЫЙ НЕ ВРАГ. Он лежит ВНЕ папки Enemies — иначе остров нельзя было бы
-- зачистить, а клетка открывается как раз по пустой Enemies.
local function spawnPrisoners(island, spec)
	if not spec.prisoners then return 0 end
	local folder = island:FindFirstChild("Prisoners")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Prisoners"
		folder.Parent = island
	end

	local family = Defs.FAMILIES[math.random(#Defs.FAMILIES)]
	island:SetAttribute("PrisonerFamily", family.id)

	local placed = 0
	for point, cfg in pairs(spec.prisoners) do
		local marker = island:FindFirstChild("Pt_" .. point, true)
		if marker and marker:IsA("BasePart") then
			local modelName = ("Prisoner_%s_%s"):format(family.id, cfg.role)
			local tpl = findTemplate(modelName)
			if not tpl then
				warnOnce("prisoner_" .. modelName,
					("модели «%s» нет в ReplicatedStorage — клетка пуста"):format(modelName))
			else
				local npc = tpl:Clone()
				npc.Name = modelName
				npc:SetAttribute("Prisoner", true)
				npc:SetAttribute("FaceSet", cfg.face)
				npc:SetAttribute("Freed", false)
				npc:SetAttribute("WaterImmune", true)
				local hum = npc:FindFirstChildWhichIsA("Humanoid", true)
				if hum then hum.WalkSpeed = 0 end   -- в клетке стоит на месте
				muteOwnScripts(npc)
				placeAt(npc, marker)
				npc.Parent = folder
				--[[ ⚠️ СУСТАВЫ И СТАРТОВАЯ ПОЗА — КАК У БОЛЬШОГО ОСТРОВА.
				     Здесь этого не было: ребёнок в клетке стоял без Motor6D, клипы
				     («связан», «освобождён», ходьба) некуда было класть — «анимации
				     не применялись никакие», а при освобождении модель без суставов
				     и без якоря просто рассыпалась и падала. Сборщик живёт в
				     PirateIsland и может подняться позже нас — ждём его. ]]
				task.spawn(function()
					local t0 = os.clock()
					while typeof(_G.EnsureR6Joints) ~= "function" and os.clock() - t0 < 15 do task.wait(0.25) end
					if not npc.Parent then return end
					if typeof(_G.EnsureR6Joints) == "function" then
						pcall(_G.EnsureR6Joints, npc)
					else
						warn(LOG .. " _G.EnsureR6Joints не появился — пленный останется без анимаций")
					end
					if _G.PirateIslandAnim then _G.PirateIslandAnim.loop(npc, "idle") end
				end)
				placed += 1			end
		end
	end
	return placed
end

-- ⚠️ КЛЕТКУ ОТКРЫВАЕТ ВЫБИТЫЙ ГАРНИЗОН, КЛЮЧА НЕТ.
-- Условие то же, что у зачистки (пустая папка Enemies), чтобы два правила не
-- разъехались. Само открытие, лица и выход наружу делает штатный
-- _G.FreePrisoners из PirateIsland — второй такой же код здесь не нужен.
local function watchGarrison(island)
	task.spawn(function()
		while island.Parent do
			task.wait(1)
			if island:GetAttribute("PrisonersFreed") then return end
			local enemies = island:FindFirstChild(Defs.ENEMIES_FOLDER)
			if enemies then
				local alive = 0
				for _, npc in ipairs(enemies:GetChildren()) do
					local hum = npc:IsA("Model") and npc:FindFirstChildWhichIsA("Humanoid", true)
					if hum and hum.Health > 0 then alive += 1 end
				end
				if alive == 0 and typeof(_G.FreePrisoners) == "function" then
					pcall(_G.FreePrisoners, island)
					return
				end
			end
		end
	end)
end

-- ═══════════ заселение ═══════════

local done = setmetatable({}, { __mode = "k" })

local function setupIsland(island)
	local spec = ISLANDS[island.Name]
	if not spec or done[island] then return end
	if island:GetAttribute("Cleared") then return end   -- из сейва, уже зачищен: гарнизона нет
	done[island] = true

	local crops, drums, ore = 0, 0, 0
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") then
			local n = d.Name
			if n:sub(1, 13) == "Virus_crop_sm" then crops += 1
			elseif n:sub(1, 10) == "Virus_drum" then drums += 1
			elseif n:sub(1, 4) == "Ore_" then ore += 1 end
		end
	end

	local placed, routes = spawnGarrison(island, spec)
	local caged = spawnPrisoners(island, spec)
	if caged > 0 then watchGarrison(island) end

	if spec.glassToPlastic then
		local n = 0
		for _, d in ipairs(island:GetDescendants()) do
			if d:IsA("BasePart") and d.Material == Enum.Material.Glass and d.Name:sub(1, #spec.glassToPlastic) == spec.glassToPlastic then
				d.Material = Enum.Material.SmoothPlastic
				n += 1
			end
		end
		print(("%s %s: стекло теплиц → пластик, деталей %d"):format(LOG, spec.ru, n))
	end
	if spec.farmersRuntime then
		task.spawn(function()
			local ok, err = pcall(function()
				local g = island:WaitForChild("Gameplay", 10)
				if not g then error("нет папки Gameplay") end
				local folder = ReplicatedStorage:WaitForChild("FarmersIsland", 10)
				--[[ СУНДУКИ ПАКЕТА: два случайных из десяти мест, открытие с
				     анимацией крышки — его код; ЛУТ — наш (пакет его не выдавал):
				     монеты и пара ресурсов, салют иконок как с кустов вируса. ]]
				local opened = g:FindFirstChild("ChestOpened")
				if not opened then
					opened = Instance.new("BindableEvent")
					opened.Name = "ChestOpened"
					opened.Parent = g
				end
				opened.Event:Connect(function(player, chest)
					if not (player and player.Parent) then return end
					local coins = math.random(40, 80)
					if _G.AddPirate then pcall(_G.AddPirate, player, coins) end
					local pool = { { "Log", 3 }, { "Plastic", 2 }, { "Rope", 1 }, { "Stone", 2 }, { "Iron_Ingot", 1 }, { "Leaves", 4 } }
					local got = {}
					for _ = 1, 2 do
						local pick = table.remove(pool, math.random(#pool))
						if _G.AddResourceToInventory then pcall(_G.AddResourceToInventory, player, pick[1], pick[2], nil) end
						table.insert(got, pick[1] .. " x" .. pick[2])
					end
					if _G.SendInventory then pcall(_G.SendInventory, player) end
					local body = chest and chest:FindFirstChild("Chest_Body", true)
					local ok, FX = pcall(function() return require(ReplicatedStorage:WaitForChild("LootBurstFX", 5)) end)
					if ok and FX and body then
						local icons = { "rbxassetid://93617165412571" }
						if typeof(_G.GetItemIcon) == "function" then
							for _, name in ipairs({ got[1]:match("^(%S+)"), got[2]:match("^(%S+)") }) do
								local id = _G.GetItemIcon(name)
								if type(id) == "string" and id ~= "" then table.insert(icons, id) end
							end
						end
						pcall(FX.play, body, icons, { heightOffset = 1.5 })
					end
					print(("%s %s: %s открыл сундук — %d монет, %s"):format(LOG, spec.ru, player.Name, coins, table.concat(got, ", ")))
				end)
				local chests = require(folder.ChestSpawner).Start(island, g)
				print(("%s %s: сундуки на местах %s"):format(LOG, spec.ru, table.concat(chests.chosen, ", ")))

				local roster = require(folder.NPCSpawner).Start(island, g)
				local service = require(folder.NPCController).Start(island, g)
				local mutants = 0
				for _, m in ipairs(roster.models) do
					if m:GetAttribute("FarmersRole") == "Mutant" and require(folder.MutantAI).Start(island, m) then mutants += 1 end
				end
				print(("%s %s: мутантов под нашим ИИ: %d"):format(LOG, spec.ru, mutants))
				local st = service.GetStatus()
				print(("%s %s: рантайм пакета поднят — жителей %d (%s)"):format(LOG, spec.ru, st.total,
					(function() local t = {} for k, v in pairs(st.counts) do table.insert(t, k .. "=" .. v) end return table.concat(t, ", ") end)()))
			end)
			if not ok then warn(("%s %s: рантайм пакета не поднялся: %s"):format(LOG, spec.ru, tostring(err))) end
		end)
	end

	print(("%s %s заселён: гарнизон %d (маршрутов %d), пленных %d, кустов вируса %d, бочек %d, руды %d")
		:format(LOG, spec.ru, placed, routes, caged, crops, drums, ore))
end

for _, m in ipairs(Workspace:GetChildren()) do
	if m:IsA("Model") then setupIsland(m) end
end

Workspace.ChildAdded:Connect(function(inst)
	if inst:IsA("Model") and ISLANDS[inst.Name] then
		task.defer(function()
			if inst.Parent then setupIsland(inst) end
		end)
	end
end)

print(LOG .. " готов: гарнизоны по маркерам Pt_*, маршруты по Pt_*_WayN, пленные в клетках")
