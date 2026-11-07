--[[
	ОСТРОВ КРАБОВ — связка пакета ServerStorage.CrabIsland_Transfer с игрой
	(хендофф «Передача острова крабов в основной плейс»).

	Пакет владелец кладёт в ServerStorage целиком (из Crab_Island_Test.rbxl):
	  Island/Crab_Rock_Island  — остров, внутри CrabTransferSpawns (4 маркера)
	  Units/Crab1..Crab4       — готовые крабы (риг, CrabClient, анимации)
	  Weapons/Тестовая сабля   — Tool для проверки боя
	  TestOnly/TestOcean       — вода тестового плейса (нужна только её высота)
	Скрипты ИИ — в Rojo: ServerScriptService/CrabGroupAI (+ CrabLife/CrabLoot/
	CrabDeath/CrabCombat), клиент — StarterPlayerScripts/CrabCombatFeedback и
	CrabSwordArm. ⚠️ Если их копии из пакета лежат в Studio рядом — удалить,
	иначе ИИ и звуки пойдут дважды.

	Что делает этот скрипт:
	  • отдаёт шаблон острова и уровень его воды менеджеру островов
	    (WorldEventSpawner: остров «Crab_Rock_Island», _G.SpawnIsland);
	  • когда остров появился в Workspace — ставит 4 краба по маркерам, каждому
	    ObjectValue CrabIsland = этот остров; остров снесли — крабы уходят с ним
	    (дропы клешней лежат в самом острове, в папке CrabDrops);
	  • урон основным оружием: у краба Humanoid-прокладка — топор, револьвер и
	    прочее бьют Humanoid, а ИИ краба живёт по атрибуту CrabHealth.
	    Сначала CrabLastAttacker = UserId ударившего, потом падает CrabHealth —
	    именно это запускает ответную атаку (хендофф, п.4);
	  • шаблон Crab_Claw в ReplicatedStorage — иконка клешни в инвентаре;
	  • _G.CrabIslandSpawn(player) — кнопка настроек: остров по курсу + сабля.
]]
local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")

local LOG = "[Крабы]"
local ISLAND_NAME = "Crab_Rock_Island"
local PROXY_HP = 1000

-- пакет ищем и в ServerStorage (по хендоффу), и в ReplicatedStorage (туда его и положили)
local function packNamed(name)
	return ServerStorage:FindFirstChild(name) or ReplicatedStorage:FindFirstChild(name)
end
local function pack() return packNamed("CrabIsland_Transfer") end
local function packPath(root, ...)
	local node = root
	for _, name in ipairs({ ... }) do
		node = node and node:FindFirstChild(name)
	end
	return node
end
local function packPart(...) return packPath(pack(), ...) end

--[[ ПЕСЧАНАЯ ОТМЕЛЬ (пакет SandyShoal_Transfer): один краб ShoalCrab на маркере
     CrabSpawns/Crab01 и ОДИН сундук на случайном из шести ChestSpawns (в пакете
     два — владелец просил один). Родные ChestSpawner / ShoalCrabSpawner внутри
     острова НЕ включаем (WorldEventSpawner их сносит): краба ведёт общий
     CrabGroupAI, сундук — этот скрипт, как у острова фермеров. ]]
local SHOAL_NAME = "Sandy_Shoal_Island"
local function shoalPack() return packNamed("SandyShoal_Transfer") end
_G.ShoalIslandTemplate = function() return packPath(shoalPack(), "Island", SHOAL_NAME) end
_G.ShoalIslandWaterLine = function()
	local t = _G.ShoalIslandTemplate()
	if not t then return nil end
	return t:GetPivot():PointToWorldSpace(Vector3.new(0, t:GetAttribute("WaterLevelLocal") or -0.75, 0)).Y
end

--[[ ЗАБЫТЫЙ КРАТЕР (Crater_Island из Placement_Validation): остров кладётся в
     ReplicatedStorage (или ServerStorage) целиком. Внутри: CrabSpawns (Crab01–03),
     ChestSpawns (Spot01–06) с моделью ChestTemplate, Pirate (pirate_spawn_1/2).
     Родные CraterCrabSpawner / ChestSpawner НЕ включаем (их сносит
     WorldEventSpawner): первому нужен пакет ForgottenCrater_Transfer, которого в
     игре нет. Крабов — трое разного размера — и два сундука ставит этот скрипт,
     пиратов-сторожей с саблями — IslandCrews. ]]
local CRATER_NAMES = { Crater_Island = true, Crater = true, Forgotten_Crater_Island = true }
local CRATER_CRABS = { { size = 0.7, hp = 40 }, { size = 0.9, hp = 60 }, { size = 1.1, hp = 90 } }
local CRATER_CHESTS = 2
local function craterTemplate()
	for name in pairs(CRATER_NAMES) do
		for _, root in ipairs({ ReplicatedStorage, ServerStorage }) do
			local t = root:FindFirstChild(name, true)
			if t and t:IsA("Model") and t:FindFirstChild("ChestSpawns", true) then return t end
		end
	end
	return nil
end
_G.CraterIslandTemplate = craterTemplate
_G.CraterIslandWaterLine = function()
	local t = craterTemplate()
	local w = t and t:GetAttribute("WaterLevelLocal")
	if type(w) ~= "number" then return nil end
	return t:GetPivot():PointToWorldSpace(Vector3.new(0, w, 0)).Y
end

_G.CrabIslandTemplate = function()
	return packPart("Island", ISLAND_NAME)
end

-- верх воды тестового плейса: по нему остров ставится на нашу воду
_G.CrabIslandWaterLine = function()
	local ocean = packPart("TestOnly", "TestOcean")
	if not ocean then return nil end
	if ocean:IsA("BasePart") then return ocean.Position.Y + ocean.Size.Y / 2 end
	local best
	for _, d in ipairs(ocean:GetDescendants()) do
		if d:IsA("BasePart") and (not best or d.Size.X * d.Size.Z > best.Size.X * best.Size.Z) then best = d end
	end
	return best and (best.Position.Y + best.Size.Y / 2) or nil
end

-- скрипты пакета выключены на хранение; исходное состояние — атрибут TransferEnabled
local function enableScripts(root)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BaseScript") then
			local want = d:GetAttribute("TransferEnabled")
			d.Enabled = (want == nil) and true or want == true
		end
	end
end

-- ═══════════ урон основным оружием → CrabHealth ═══════════
local function attackerOf(model, hum)
	local tag = hum:FindFirstChild("creator")
	local p = tag and tag:IsA("ObjectValue") and tag.Value
	if typeof(p) == "Instance" and p:IsA("Player") then return p end
	local id = model:GetAttribute("LastHitBy")
	return type(id) == "number" and Players:GetPlayerByUserId(id) or nil
end

local function bridgeHumanoid(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		hum = Instance.new("Humanoid")
		hum.Name = "CrabHitProxy"
		hum.Parent = model
	end
	-- ⚠️ ПРОКЛАДКА НЕ УПРАВЛЯЕТ РИГОМ: краба двигает серверный контроллер
	-- (корень заякорен), анимации — Motor6D.Transform на клиенте
	hum.EvaluateStateMachine = false
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.MaxHealth = PROXY_HP
	hum.Health = PROXY_HP
	local busy = false
	hum.HealthChanged:Connect(function(hp)
		if busy or hp >= PROXY_HP then return end
		busy = true
		local dmg = PROXY_HP - hp
		hum.Health = PROXY_HP
		busy = false
		local crabHp = model:GetAttribute("CrabHealth") or 0
		if crabHp <= 0 then return end
		local player = attackerOf(model, hum)
		if player then model:SetAttribute("CrabLastAttacker", player.UserId) end
		model:SetAttribute("CrabHealth", math.max(0, crabHp - dmg))
	end)
end

-- ═══════════ пули (револьвер, пушки) по крабам ═══════════
--[[ ⚠️ ПУЛЯ ЛЕТИТ СКВОЗЬ КРАБА: ShipCombat ловит её по Touched, а детали рига
     касаний не дают (и корень двигается телепортом 10 раз в секунду — пуля на
     320 studs/с между кадрами его просто перепрыгивает). Поэтому снаряды ведём
     сами: каждый кадр отрезок «прошлая точка → текущая» против центра каждого
     живого краба. Урон — как у ShipCombat (100 × DmgMult: револьвер = 20),
     стрелок — ObjectValue creator пули. Касания у краба выключены (CanTouch),
     чтобы тот же выстрел не засчитался второй раз через Humanoid-прокладку. ]]
local BULLET_NAMES = { ["Bullet_Cannon"] = true, ["Cannon Shot"] = true }
local BULLET_DAMAGE = 100
local bullets = {}   -- [part] = прошлая позиция

local function damageCrab(crab, player, dmg)
	local hp = crab:GetAttribute("CrabHealth") or 0
	if hp <= 0 then return end
	if player then crab:SetAttribute("CrabLastAttacker", player.UserId) end
	crab:SetAttribute("CrabHealth", math.max(0, hp - dmg))
end
_G.CrabDamage = damageCrab

workspace.ChildAdded:Connect(function(c)
	if c:IsA("BasePart") and BULLET_NAMES[c.Name] then bullets[c] = c.Position end
end)

game:GetService("RunService").Heartbeat:Connect(function()
	if next(bullets) == nil then return end
	local crabs = CollectionService:GetTagged("CrabNPC")
	for ball, prev in pairs(bullets) do
		if not ball.Parent then bullets[ball] = nil continue end
		local cur = ball.Position
		local seg = cur - prev
		local len = seg.Magnitude
		local hitCrab
		if len > 1e-3 then
			local dir = seg / len
			for _, crab in ipairs(crabs) do
				local root = crab:FindFirstChild("HumanoidRootPart")
				if root and (crab:GetAttribute("CrabHealth") or 0) > 0 then
					local r = 1.8 * (crab:GetAttribute("CrabRigScale") or 1) + 0.4
					local t = math.clamp((root.Position - prev):Dot(dir), 0, len)
					if (prev + dir * t - root.Position).Magnitude <= r then hitCrab = crab break end
				end
			end
		end
		if hitCrab then
			bullets[ball] = nil
			local tag = ball:FindFirstChild("creator")
			local player = tag and tag:IsA("ObjectValue") and tag.Value
			if not (typeof(player) == "Instance" and player:IsA("Player")) then
				player = Players:GetPlayerByUserId(ball:GetAttribute("FiredBy") or 0)
			end
			damageCrab(hitCrab, player, BULLET_DAMAGE * (ball:GetAttribute("DmgMult") or 1))
			ball:Destroy()
		else
			bullets[ball] = cur
		end
	end
end)

-- ═══════════ крабы по маркерам острова ═══════════
local RESET = { "CrabRagdoll", "CrabLootDropped", "CrabMotionTarget", "CrabLastAttacker",
	"CrabTargetUserId", "CrabAnimationT", "CrabAnimation", "CrabState", "CrabActivity", "CrabSwimming" }

local function npcFolder()
	local f = workspace:FindFirstChild("CrabNPCs")
	if not f then
		f = Instance.new("Folder")
		f.Name = "CrabNPCs"
		f.Parent = workspace
	end
	return f
end

-- ═══════════ сундук отмели: один, как у фермеров ═══════════
--[[ Модель сундука та же, что у острова фермеров (FarmersWoodChestV1), поэтому
     и поведение то же: ChestSetup ставит шарнир крышки LidHinge, открытие —
     твин крышки на −100° за 0.9 с, атрибуты GlowStarted/TargetOpen/GlowOpenedAt
     зажигают свечение у клиента (ShoalChestGlow → FarmersIsland/ChestGlow),
     награда — монеты и пара ресурсов с «салютом» иконок. Один раз на сундук. ]]
local TweenService = game:GetService("TweenService")
local spawnShoalChest
local ChestSetup = require(ReplicatedStorage:WaitForChild("FarmersIsland"):WaitForChild("ChestSetup"))

local function giveChestLoot(player, chest)
	local coins = math.random(40, 80)
	if _G.AddPirate then pcall(_G.AddPirate, player, coins) end
	local pool = { { "Log", 3 }, { "Plastic", 2 }, { "Rope", 1 }, { "Stone", 2 }, { "Iron_Ingot", 1 }, { "Leaves", 4 } }
	local got, icons = {}, { "rbxassetid://93617165412571" }
	for _ = 1, 2 do
		local pick = table.remove(pool, math.random(#pool))
		if _G.AddResourceToInventory then pcall(_G.AddResourceToInventory, player, pick[1], pick[2], nil) end
		table.insert(got, pick[1] .. " x" .. pick[2])
		if typeof(_G.GetItemIcon) == "function" then
			local id = _G.GetItemIcon(pick[1])
			if type(id) == "string" and id ~= "" then table.insert(icons, id) end
		end
	end
	if _G.SendInventory then pcall(_G.SendInventory, player) end
	local body = chest:FindFirstChild("Chest_Body", true)
	local ok, FX = pcall(function() return require(ReplicatedStorage:WaitForChild("LootBurstFX", 5)) end)
	if ok and FX and body then pcall(FX.play, body, icons, { heightOffset = 1.5 }) end
	print(("%s отмель: %s открыл сундук — %d монет, %s"):format(LOG, player.Name, coins, table.concat(got, ", ")))
end

-- шаблон сундука: у отмели — из её пакета, у кратера — из ИСХОДНОГО острова
-- (в клоне его нет: ChestSpawner вместе с ChestTemplate внутри снесён при спавне)
local function chestTemplateFor(island)
	if island.Name == SHOAL_NAME then
		return packPath(shoalPack(), "Island", SHOAL_NAME, "ChestSpawner", "ChestTemplate")
			or (function()
				local src = _G.ShoalIslandTemplate()
				return src and src:FindFirstChild("ChestTemplate", true)
			end)()
	end
	local src = craterTemplate()
	return (src and src:FindFirstChild("ChestTemplate", true)) or island:FindFirstChild("ChestTemplate", true)
end

local spawnOneChest
spawnShoalChest = function(island, count)
	count = count or 1
	local spotsFolder = island:FindFirstChild("ChestSpawns")
	local template = chestTemplateFor(island)
	if not (spotsFolder and template) then
		warn(("%s %s: нет %s — сундуков не будет"):format(LOG, island.Name, spotsFolder and "ChestTemplate" or "ChestSpawns"))
		return
	end
	local live = island:FindFirstChild("ActiveChests")
	if not live then
		live = Instance.new("Folder")
		live.Name = "ActiveChests"
		live.Parent = island
	end
	live:ClearAllChildren()
	local spots = {}
	for _, sp in ipairs(spotsFolder:GetChildren()) do if sp:IsA("BasePart") then table.insert(spots, sp) end end
	if #spots == 0 then return end
	-- случайные места без повторов
	for i = #spots, 2, -1 do
		local j = math.random(i)
		spots[i], spots[j] = spots[j], spots[i]
	end
	local n = 0
	for i = 1, math.min(count, #spots) do
		if spawnOneChest(island, live, spots[i], template) then n += 1 end
	end
	island:SetAttribute("ActiveChestCount", n)
end

spawnOneChest = function(island, live, spot, template)
	local chest = template:Clone()
	chest.Name = "Chest_" .. spot.Name
	for _, d in ipairs(chest:GetDescendants()) do
		if d:IsA("BaseScript") then d:Destroy()
		elseif d:IsA("BasePart") then
			-- ⚠️ ШАБЛОН В ПАКЕТЕ СКРЫТ (прозрачный): родной спавнер при установке
			-- делал видимым всё, кроме направляющих крышки — повторяем его правило,
			-- иначе сундук стоял невидимкой без коллизии
			d.Anchored = true
			local guide = d.Name:find("Lid") and d.Name ~= "Chest_Lid"
			d.Transparency = guide and 1 or 0
			d.CanCollide = not guide
			d.CanQuery = not guide
		end
	end
	-- как в пакете: низ сундука на платформу спота
	chest.Parent = live
	local cf, size = chest:GetBoundingBox()
	local relative = chest:GetPivot():ToObjectSpace(cf)
	chest:PivotTo(spot.CFrame * CFrame.new(0, size.Y / 2, 0) * relative:Inverse())
	-- крышку держит только шарнир: сварки крышки с корпусом мешали бы ему
	local lid = chest:FindFirstChild("Chest_Lid", true)
	for _, w in ipairs(chest:GetDescendants()) do
		if w:IsA("WeldConstraint") and lid and (w.Part0 == lid or w.Part1 == lid) then w:Destroy() end
	end
	local okSetup, err = pcall(ChestSetup.apply, chest)
	if not okSetup then warn(LOG .. " " .. island.Name .. ": ChestSetup упал: " .. tostring(err)) return false end
	chest:SetAttribute("ShoalChest", true)
	chest:SetAttribute("SpawnId", spot.Name)

	local body = chest:FindFirstChild("Chest_Body", true)
	local prompt = body and body:FindFirstChild("ChestPrompt")
	local hinge = body and body:FindFirstChild("LidHinge")
	if not (prompt and hinge) then return false end
	local consumed = false
	prompt.Triggered:Connect(function(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if consumed or not chest:IsDescendantOf(workspace) or not root or not hum or hum.Health <= 0
			or (root.Position - body.Position).Magnitude > 14 then return end
		consumed = true
		prompt.Enabled = false
		chest:SetAttribute("Consumed", true)
		chest:SetAttribute("OpenedBy", player.UserId)
		local stamp = workspace:GetServerTimeNow()
		chest:SetAttribute("TargetOpen", true)
		chest:SetAttribute("GlowStarted", stamp)
		TweenService:Create(hinge, TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ C0 = hinge:GetAttribute("ClosedC0") * CFrame.Angles(math.rad(-100), 0, 0) }):Play()
		chest:SetAttribute("IsOpen", true)
		chest:SetAttribute("GlowOpenedAt", stamp + 0.9)
		giveChestLoot(player, chest)
	end)
	print(("%s %s: сундук на %s"):format(LOG, island.Name, spot.Name))
	return true
end

local populated = setmetatable({}, { __mode = "k" })

local function populate(island)
	if populated[island] then return end
	local shoal = island.Name == SHOAL_NAME
	local crater = CRATER_NAMES[island.Name] == true
	local markers = island:FindFirstChild((shoal or crater) and "CrabSpawns" or "CrabTransferSpawns", true)
	-- у кратера своих крабов нет: берём рига из пакета острова крабов
	local units = packPath(shoal and shoalPack() or pack(), "Units")
	if not (markers and units) then
		warn(("%s %s: нет %s — крабов не будет"):format(LOG, island.Name,
			markers and "ServerStorage.CrabIsland_Transfer.Units" or "маркеров CrabTransferSpawns"))
		return
	end
	populated[island] = true
	local spawned = {}
	for _, marker in ipairs(markers:GetChildren()) do
		local tplName = marker:IsA("BasePart") and (marker:GetAttribute("TemplateName") or (shoal and "ShoalCrab")
			or (crater and (units:FindFirstChild("CrabTemplate") and "CrabTemplate" or "Crab1")))
		local tpl = tplName and units:FindFirstChild(tplName)
		local root0 = tpl and tpl:FindFirstChild("HumanoidRootPart")
		if not root0 then
			warn(("%s маркер %s: нет шаблона краба «%s»"):format(LOG, marker.Name, tostring(tplName)))
			continue
		end
		local crab = tpl:Clone()
		-- AnimalStabilizer не трогает: краба ведёт свой контроллер
		crab:SetAttribute("_AnimalStabilized", true)
		for _, k in ipairs(RESET) do crab:SetAttribute(k, nil) end
		-- кратер: трое разного размера и силы (как в CraterCrabSpawner пакета)
		local cfgC = crater and (CRATER_CRABS[tonumber(marker.Name:match("%d+")) or 0] or CRATER_CRABS[2]) or nil
		if cfgC then
			local old = crab:GetAttribute("CrabRigScale") or 0.85
			pcall(function() crab:ScaleTo(crab:GetScale() * cfgC.size / old) end)
			crab:SetAttribute("CrabRigScale", cfgC.size)
		end
		local hp = (cfgC and cfgC.hp) or marker:GetAttribute("CrabHealth") or crab:GetAttribute("CrabMaxHealth") or crab:GetAttribute("CrabHealth") or 60
		crab:SetAttribute("CrabHealth", hp)
		crab:SetAttribute("CrabMaxHealth", marker:GetAttribute("CrabMaxHealth") or hp)
		crab:SetAttribute("CrabAIEnabled", true)
		local link = Instance.new("ObjectValue")
		link.Name = "CrabIsland"
		link.Value = island
		link.Parent = crab
		if shoal then crab:SetAttribute("SandyShoalCrab", true) end
		local root = crab:FindFirstChild("HumanoidRootPart")
		root.Anchored = true
		-- CFrame маркера — поза HumanoidRootPart, а не отметка ног
		-- (у кратера маркер лежит на земле: корень поднимаем, как в его спавнере)
		local pose = cfgC and (marker.CFrame * CFrame.new(0, 1.45 * cfgC.size, 0)) or marker.CFrame
		crab:PivotTo(pose * root.CFrame:ToObjectSpace(crab:GetPivot()))
		enableScripts(crab)   -- ⚠️ CrabClient (RunContext Client) тоже: без него краб не анимируется
		bridgeHumanoid(crab)
		-- табличка «Crab4 120 HP» — отладка тестового плейса, в игре не нужна;
		-- её может пересоздать скрипт рига, поэтому ловим и новые.
		-- Касания выключены: пули считает трекер выше, не Touched (без двойного урона).
		for _, d in ipairs(crab:GetDescendants()) do
			if d:IsA("BillboardGui") then d:Destroy()
			elseif d:IsA("BasePart") then d.CanTouch = false end
		end
		crab.DescendantAdded:Connect(function(d)
			if d:IsA("BillboardGui") then task.defer(function() if d.Parent then d:Destroy() end end) end
		end)
		crab.Parent = npcFolder()
		CollectionService:AddTag(crab, "CrabNPC")
		table.insert(spawned, crab)
	end
	print(("%s остров %s: крабов %d"):format(LOG, island.Name, #spawned))
	if shoal then task.spawn(spawnShoalChest, island, 1) end
	if crater then task.spawn(spawnShoalChest, island, CRATER_CHESTS) end
	-- ВРЕМЕННАЯ ДИАГНОСТИКА: 90 с после спавна раз в 6 с — что делает каждый краб
	-- и почему не шагает (блок — причина из CrabGroupAI.move)
	task.spawn(function()
		for _ = 1, 15 do
			task.wait(6)
			if not island.Parent then return end
			if typeof(_G.CrabDebug) == "function" then
				for _, line in ipairs(_G.CrabDebug()) do print(LOG .. " [диаг] " .. line) end
			else
				warn(LOG .. " [диаг] _G.CrabDebug нет — CrabGroupAI не запущен?")
			end
		end
	end)
	-- остров ушёл — крабы с ним
	island.Destroying:Connect(function()
		for _, c in ipairs(spawned) do if c.Parent then c:Destroy() end end
	end)
	island.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			for _, c in ipairs(spawned) do if c.Parent then c:Destroy() end end
		end
	end)
end

local function isCrabIsland(child)
	return child:IsA("Model") and (child.Name == ISLAND_NAME or child.Name == SHOAL_NAME or CRATER_NAMES[child.Name] == true)
end
workspace.ChildAdded:Connect(function(child)
	if isCrabIsland(child) then task.defer(populate, child) end
end)
for _, child in ipairs(workspace:GetChildren()) do
	if isCrabIsland(child) then task.defer(populate, child) end
end

-- ═══════════ иконка клешни: модель Crab_Claw в ReplicatedStorage ═══════════
task.spawn(function()
	if ReplicatedStorage:FindFirstChild("Crab_Claw") then return end
	local src = packPart("Units", "CrabTemplate") or packPart("Units", "Crab1")
	local claw = src and src:FindFirstChild("LeftClaw", true)
	local finger = src and src:FindFirstChild("LeftFinger", true)
	if not (claw and finger) then return end
	local m = Instance.new("Model")
	m.Name = "Crab_Claw"
	for _, part in ipairs({ claw, finger }) do
		local c = part:Clone()
		for _, d in ipairs(c:GetDescendants()) do
			if not (d:IsA("DataModelMesh") or d:IsA("SurfaceAppearance") or d:IsA("Texture") or d:IsA("Decal")) then d:Destroy() end
		end
		c.Anchored = true
		c.CanCollide = false
		c.Transparency = 0
		c.Parent = m
	end
	m.Parent = ReplicatedStorage
end)

-- ═══════════ кнопка настроек ═══════════
_G.CrabIslandSpawn = function(player)
	if not pack() then return false, "нет папки CrabIsland_Transfer ни в ServerStorage, ни в ReplicatedStorage" end
	if not _G.CrabIslandTemplate() then return false, "в пакете нет Island/" .. ISLAND_NAME end
	if typeof(_G.SpawnIsland) ~= "function" then return false, "нет _G.SpawnIsland" end
	local ok, why = _G.SpawnIsland({ test = true, name = ISLAND_NAME })
	if not ok then return false, why end
	-- тестовая сабля: для проверки боя (основное оружие тоже бьёт)
	local saber = packPart("Weapons", "Тестовая сабля")
	if saber and player and player.Parent then
		local bag = player:FindFirstChildOfClass("Backpack")
		local has = (bag and bag:FindFirstChild(saber.Name)) or (player.Character and player.Character:FindFirstChild(saber.Name))
		if bag and not has then
			local tool = saber:Clone()
			enableScripts(tool)
			tool.Parent = bag
		end
	end
	return true
end

_G.CraterIslandSpawn = function(player)
	local t = craterTemplate()
	if not t then return false, "нет модели Crater_Island в ReplicatedStorage / ServerStorage" end
	if typeof(_G.SpawnIsland) ~= "function" then return false, "нет _G.SpawnIsland" end
	return _G.SpawnIsland({ test = true, name = "Crater_Island" })
end

_G.ShoalIslandSpawn = function(player)
	if not shoalPack() then return false, "нет папки SandyShoal_Transfer ни в ServerStorage, ни в ReplicatedStorage" end
	if not _G.ShoalIslandTemplate() then return false, "в пакете нет Island/" .. SHOAL_NAME end
	if typeof(_G.SpawnIsland) ~= "function" then return false, "нет _G.SpawnIsland" end
	return _G.SpawnIsland({ test = true, name = SHOAL_NAME })
end

print(("%s готов: пакет %s"):format(LOG, pack() and ("найден: " .. pack():GetFullName()) or "НЕ найден (CrabIsland_Transfer в ServerStorage / ReplicatedStorage)"))
