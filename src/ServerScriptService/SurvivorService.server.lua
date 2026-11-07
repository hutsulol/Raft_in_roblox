--[[
	ВЫЖИВШИЕ (КАПИТАНЫ) — сервер. Окно — SurvivorsUI.client (хендофф
	design_handoff_survivors, «Управление выжившими»), данные — SurvivorDefs.

	Сервер — источник истины:
	  • команда игрока: { uid, def, salary } в DataStore SurvivorsV1 (до 8 человек;
	    новичок начинает с Капитаном Розой);
	  • здания — то, что реально стоит на плоту. Сейчас это фермы (RaftFarmService):
	    одно рабочее место. Нанятый по умолчанию фермер место НЕ занимает — его
	    заменяет назначенный выживший;
	  • назначение живёт АТРИБУТАМИ НА ДОМЕ ФЕРМЫ (SurvivorKey, WorkerModel,
	    WorkerName, WorkerWage, IncomeBonus) — они сохраняются вместе с плотом, и
	    после перезахода на ферме снова работает тот же выживший.
	Назначили → RaftFarmService пересобирает ферму: фермер исчезает, в доме
	появляется модель выжившего и выходит на работу.

	Remotes (ReplicatedStorage):
	  SurvivorsRF (RemoteFunction): "state" | "assign", uid, buildingId|nil |
	    "save", uid, salary | "fire", uid → { ok, why, state }
	  SurvivorsChanged (RemoteEvent, S→C): состояние поменялось — перечитать
	_G.SurvivorTemplate(defId) — модель выжившего (её клонирует ферма)
	_G.GrantSurvivor(player, defId) — добавить в команду (кнопка админа)
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")
local HttpService       = game:GetService("HttpService")

local D = require(ReplicatedStorage:WaitForChild("SurvivorDefs"))
local LOG = "[Выжившие]"

local function remote(class, name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local rf      = remote("RemoteFunction", "SurvivorsRF")
local changed = remote("RemoteEvent", "SurvivorsChanged")
-- новый выживший в команде → попап «Новый персонаж!» (NewCharacterPopup.client)
local unlocked = remote("RemoteEvent", "SurvivorUnlocked")


local crews = {}   -- [player] = { list = { { uid, def, salary } } }

-- ═══════════ модели в Workspace ═══════════
--[[ ⚠️ СЦЕНА ПОРТРЕТА И МОДЕЛЬ — У КАЖДОГО КЛИЕНТА ВСЕГДА (Persistent). В плейсе
     StreamingEnabled: сцена стоит далеко от плота, и без этого клиент её бы не
     получил — предпросмотр в окне показывал бы пустое море. ]]
for _, def in pairs(D.CATALOG) do
	if not def.stage then continue end   -- модель в ReplicatedStorage (рыбак): сцены нет
	task.spawn(function()
		local stage
		for _ = 1, 40 do
			stage = D.find(def.stage)
			if stage then break end
			task.wait(0.5)
		end
		if not stage then
			warn(("%s в Workspace нет сцены %s — предпросмотр и работник «%s» недоступны")
				:format(LOG, table.concat(def.stage, "."), def.name))
			return
		end
		for _, m in ipairs(stage:IsA("Model") and { stage } or stage:GetChildren()) do
			if m:IsA("Model") then m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end
		end
	end)
end

--[[ ═══ COLD CAP: ШАБЛОН ГОТОВИМ ОДИН РАЗ ═══
     • Лежит в ReplicatedStorage (оттуда же берёт превью «Команды»). Положили
       в Workspace — переносим: в мире он стоял бы посреди моря статуей.
     • ⚠️ Его скрипты — RunContext = Client, а такие работают и в ReplicatedStorage.
       Демо-аниматор, аура и следы крутились бы на невидимом шаблоне у каждого
       клиента — выключаем (Enabled реплицируется). Работнику нужные включаются
       обратно (keepScripts).
     • Реквизит рабочих клипов (WorkProps) прячет демо-аниматор; без него весь
       реквизит висел бы на герое — прячем сами. ]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
for defId, def in pairs(D.CATALOG) do
	if not def.hdFace then continue end
	task.spawn(function()
		local name = def.model[#def.model]
		local m
		for _ = 1, 60 do
			m = D.find(def.model) or workspace:FindFirstChild(name, true)
			if m then break end
			task.wait(0.5)
		end
		if not m then
			warn(("%s модели %s нет ни в ReplicatedStorage, ни в Workspace — житель «%s» недоступен"):format(LOG, name, def.name))
			return
		end
		if m.Parent ~= ReplicatedStorage then
			print(("%s %s: шаблон перенесён из %s в ReplicatedStorage"):format(LOG, name, m.Parent:GetFullName()))
			m.Parent = ReplicatedStorage
		end
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BaseScript") then
				d.Enabled = false
				--[[ ⚠️ МЕТКА «ОСТАВИТЬ У РАБОТНИКА». Рыбалка (FishingService) и ферма
				     (RaftFarmService) при создании работника удаляют ВСЕ скрипты модели.
				     У Cold Cap так пропадали HD-лицо и аура: лицо застывало на улыбке,
				     и во сне (zzz) глаза оставались открытыми. Помеченные — не трогают. ]]
				if def.keepScripts and def.keepScripts[d.Name] then d:SetAttribute("KeepOnWorker", true) end
			end
		end
		local props = m:FindFirstChild("WorkProps")
		if props then
			for _, p in ipairs(props:GetDescendants()) do
				if p:IsA("BasePart") then p.Transparency = 1 end
			end
		end
		-- рисованное лицо — SurfaceGui на HDFaceCarrier; Decal под ним не нужен
		local head = m:FindFirstChild("Head")
		local face = head and head:FindFirstChild("face")
		if face and m:FindFirstChild("HDFaceCarrier") then face.Transparency = 1 end
		print(("%s %s готов (житель %s)"):format(LOG, name, defId))
	end)
end

--[[ ШАБЛОН ДЛЯ РАБОТЫ: та же модель, но без оружия (Tool) — на рыбалке в руках
     удочка, а не сабля. Готовится один раз и лежит в ServerStorage. ]]
local ServerStorage = game:GetService("ServerStorage")
local workerTemplates = {}
_G.SurvivorWorkerTemplate = function(defId)
	local cached = workerTemplates[defId]
	if cached and cached.Parent then return cached end
	local src = _G.SurvivorTemplate(defId)
	if not src then return nil end
	local m = src:Clone()
	local def = D.CATALOG[defId]
	local keep = def and def.keepScripts or {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BaseScript") and keep[d.Name] then
			d.Enabled = true   -- в шаблоне выключен (см. Cold Cap выше)
		elseif d:IsA("Tool") or d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	-- ⚠️ корень Cold Cap заякорен под демо-аниматор; работника двигает команда
	local root = m:FindFirstChild("HumanoidRootPart")
	if root and def and def.hdFace then root.Anchored = false end
	local props = m:FindFirstChild("WorkProps")
	if props and def and def.hdFace then props:Destroy() end
	m.ModelStreamingMode = Enum.ModelStreamingMode.Default
	local folder = ServerStorage:FindFirstChild("SurvivorWorkerTemplates") or Instance.new("Folder")
	folder.Name = "SurvivorWorkerTemplates"
	folder.Parent = ServerStorage
	m.Name = defId
	m.Parent = folder
	workerTemplates[defId] = m
	return m
end

-- свой R6 без стандартных поворотов суставов (Роза) — клипы пересчитывает клиент
_G.SurvivorNeedsRetarget = function(defId)
	local def = D.CATALOG[defId]
	return def ~= nil and def.retarget == true
end

_G.SurvivorTemplate = function(defId)
	local def = D.CATALOG[defId]
	local m = def and D.find(def.model)
	return (m and m:IsA("Model")) and m or nil
end

-- ═══════════ команда игрока ═══════════

--[[ ⚠️ КОМАНДА ЖИВЁТ В СЕЙВЕ ПЛОТА (extras.crew, RaftSaveSystem), А НЕ В СВОЁМ
     DataStore. Раньше был отдельный SurvivorsV1 «навсегда»: начал новую игру —
     а Роза из прошлого забега уже в команде, хотя сюжет её не выдавал. Теперь
     команда — часть забега, как этап сюжета торговца и номер дня.
     saveCrew оставлен как точка «команда изменилась»: сохранит её автосейв плота. ]]
local function saveCrew(_player) end

local function cleanList(raw)
	local list = {}
	for _, s in ipairs(type(raw) == "table" and raw or {}) do
		if type(s) == "table" and D.CATALOG[s.def] and type(s.uid) == "string" then
			table.insert(list, { uid = s.uid, def = s.def, salary = math.clamp(tonumber(s.salary) or 0, 0, D.SALARY_MAX) })
		end
	end
	return list
end

local function loadCrew(player)
	-- ⚠️ НОВИЧОК НАЧИНАЕТ БЕЗ ЖИТЕЛЕЙ: первого дарит сюжет торговца (MerchantStory).
	-- Сейв плота мог восстановить команду раньше нас — не затираем.
	if not crews[player] then crews[player] = { list = {} } end
end

_G.SurvivorCrewExport = function(player)
	local crew = crews[player]
	if not crew then return nil end
	local hasDaily = crew.daily and next(crew.daily) ~= nil
	if #crew.list == 0 and not hasDaily then return nil end
	return { list = crew.list, daily = hasDaily and crew.daily or nil }
end

local function cleanDaily(raw)
	local daily = {}
	for defId, v in pairs(type(raw) == "table" and raw or {}) do
		if v == true and D.CATALOG[defId] then daily[defId] = true end
	end
	return daily
end

-- сколько жителей в команде (MerchantStory: «Команда» открыта сразу, если кто-то есть)
_G.SurvivorCrewSize = function(player)
	return crews[player] and #crews[player].list or 0
end

_G.SurvivorCrewRestore = function(player, data)
	crews[player] = {
		list = cleanList(type(data) == "table" and data.list),
		daily = cleanDaily(type(data) == "table" and data.daily),
	}
	-- в сейве уже есть команда — кнопка открыта сразу (не первый запуск)
	if #crews[player].list > 0 then player:SetAttribute("TeamUnlocked", true) end
	changed:FireClient(player)
	print(("%s %s: команда из сейва плота — %d"):format(LOG, player.Name, #crews[player].list))
end

local function findSurvivor(player, uid)
	local crew = crews[player]
	if not crew then return nil end
	for i, s in ipairs(crew.list) do
		if s.uid == uid then return s, i end
	end
	return nil
end

local function survivorKey(player, uid) return player.UserId .. ":" .. uid end

-- ═══════════ здания на плоту ═══════════
local function raftFlat()
	local raft = workspace:FindFirstChild("Raft")
	local p = raft and raft.PrimaryPart
	if not p then return nil end
	return CFrame.new(p.Position) * CFrame.Angles(0, p:GetAttribute("RestYaw") or 0, 0)
end

-- где на плоту стоит здание (для подписи карточки)
local function placeOf(model)
	local flat = raftFlat()
	if not flat then return "На плоту" end
	local ok, cf = pcall(function() return model:GetPivot() end)
	if not ok then return "На плоту" end
	local p = flat:PointToObjectSpace(cf.Position)
	if math.abs(p.X) < 8 and math.abs(p.Z) < 8 then return "Центр" end
	if math.abs(p.Z) >= math.abs(p.X) then
		return p.Z < 0 and "Передний край" or "Задний край"
	end
	return p.X < 0 and "Левый край" or "Правый край"
end

local function scanBuildings()
	local out = {}
	if typeof(_G.RaftFarmList) == "function" then
		for _, f in ipairs(_G.RaftFarmList()) do
			local kind = D.BUILDINGS.farm
			local who = f.hut:GetAttribute("SurvivorKey")
			table.insert(out, {
				id = "farm:" .. tostring(f.id), kind = "farm", name = kind.name, cap = kind.cap,
				place = placeOf(f.hut), hut = f.hut,
				workers = (type(who) == "string" and who ~= "") and { who } or {},
			})
		end
	end
	if typeof(_G.RaftFishingList) == "function" then
		for _, f in ipairs(_G.RaftFishingList()) do
			local kind = D.BUILDINGS.fishing
			local who = f.spot:GetAttribute("SurvivorKey")
			table.insert(out, {
				id = "fishing:" .. tostring(f.id), kind = "fishing", name = kind.name, cap = kind.cap,
				place = placeOf(f.spot), hut = f.spot,
				workers = (type(who) == "string" and who ~= "") and { who } or {},
			})
		end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

local function buildingOf(player, uid, buildings)
	local k = survivorKey(player, uid)
	for _, b in ipairs(buildings) do
		for _, w in ipairs(b.workers) do
			if w == k then return b end
		end
	end
	return nil
end

-- снять работника с фермы: атрибуты дома прочь, вернётся обычный фермер
-- пересобрать работника здания по его атрибутам (ферма или рыбацкое место)
local function respawnWorker(b)
	if b.kind == "fishing" then
		if typeof(_G.RaftFishingRespawn) == "function" then _G.RaftFishingRespawn(b.hut) end
	elseif typeof(_G.RaftFarmRespawnWorker) == "function" then
		_G.RaftFarmRespawnWorker(b.hut)
	end
end

-- снять работника: атрибуты здания прочь — вернётся обычный фермер / рыбак
local function clearHut(b)
	for _, a in ipairs({ "SurvivorKey", "WorkerModel", "WorkerName", "WorkerWage", "IncomeBonus" }) do
		b.hut:SetAttribute(a, nil)
	end
	respawnWorker(b)
end

-- ═══════════ состояние для окна ═══════════
--[[ ⚠️ ОДИН КАПИТАН — ОДНА ЗАПИСЬ. Выжившие из каталога — именные персонажи:
     двух Капитанов Роз в команде быть не может. Нигде это не проверялось, и
     админская кнопка выдачи (SettingsMenuActions) клала в команду вторую копию
     поверх той, что новичок получает сам при первом входе, — в окне появлялись
     два одинаковых капитана, один «Отдых», другой при деле.
     ПОЧЕМУ ЧИСТИМ ЗДЕСЬ, А НЕ ПРИ ЗАГРУЗКЕ: выбрасывать надо не «вторую», а
     ЛИШНЮЮ — здание ссылается на работника ключом UserId:uid (атрибут
     SurvivorKey на доме), и если выкинуть именно ту копию, что назначена,
     назначение осиротеет: в окне никого, а на плоту работает. На момент
     loadCrew плот ещё собирается и зданий не видно, а здесь они уже в
     buildings — значит, видно, какую копию трогать нельзя.
     Дубли, уже лежащие в DataStore, чинятся тем же проходом: список
     перезаписывается, поэтому на следующем входе их не будет. ]]
local function dedupeCrew(player, buildings)
	local crew = crews[player]
	if not (crew and #crew.list > 1) then return false end
	local keepIdx, drop = {}, {}
	for i, s in ipairs(crew.list) do
		local prev = keepIdx[s.def]
		if not prev then
			keepIdx[s.def] = i
		elseif buildingOf(player, s.uid, buildings) and not buildingOf(player, crew.list[prev].uid, buildings) then
			table.insert(drop, prev)      -- работает эта копия — оставляем её
			keepIdx[s.def] = i
		else
			table.insert(drop, i)
		end
	end
	if #drop == 0 then return false end
	table.sort(drop, function(x, y) return x > y end)   -- с конца, иначе индексы съедут
	for _, i in ipairs(drop) do
		--[[ Если обе копии успели куда-то устроиться, одна всё равно уходит — и её
		     здание осталось бы с ключом на выжившего, которого больше нет: в окне
		     место свободно, а на плоту работает «призрак», снять которого нечем.
		     Поэтому здание выбрасываемой копии честно освобождаем — туда вернётся
		     обычный фермер или рыбак, и место можно занять заново. ]]
		local b = buildingOf(player, crew.list[i].uid, buildings)
		if b then clearHut(b) end
		table.remove(crew.list, i)
	end
	saveCrew(player)
	print(("%s %s: убрано одинаковых выживших — %d"):format(LOG, player.Name, #drop))
	return true
end

local function publicState(player)
	local crew = crews[player] or { list = {} }
	local buildings = scanBuildings()
	if dedupeCrew(player, buildings) then crew = crews[player] or { list = {} } end
	local survivors = {}
	for _, s in ipairs(crew.list) do
		local def = D.CATALOG[s.def]
		local b = buildingOf(player, s.uid, buildings)
		local mood = D.mood(def, s.salary, b == nil)
		local bonuses = {}
		for _, bn in ipairs(def.bonuses) do
			table.insert(bonuses, { sign = bn.sign, value = bn.value, label = bn.label, type = bn.type })
		end
		table.insert(survivors, {
			uid = s.uid, def = s.def, name = def.name, level = def.level, hp = def.hp,
			salary = s.salary, mood = mood, speed = b and D.speed(mood) or nil, xp = D.xp(def.level),
			bonuses = bonuses, buildingId = b and b.id or nil, job = b and b.name or "Отдых",
		})
	end
	local bOut = {}
	for _, b in ipairs(buildings) do
		table.insert(bOut, { id = b.id, kind = b.kind, name = b.name, place = b.place, cap = b.cap,
			used = #b.workers, hut = b.hut })
	end
	return {
		coins = player:GetAttribute("Pirate") or 0,
		max = D.MAX_CREW,
		survivors = survivors,
		buildings = bOut,
	}
end

-- ═══════════ действия ═══════════
local busy = {}
rf.OnServerInvoke = function(player, action, a1, a2)
	if action == "state" then return publicState(player) end
	if busy[player] then return { ok = false, why = "Подожди секунду" } end
	if type(a1) ~= "string" then return { ok = false, why = "bad" } end
	busy[player] = true
	local result = (function()
		local s, idx = findSurvivor(player, a1)
		if not s then return { ok = false, why = "Такого выжившего нет" } end
		local def = D.CATALOG[s.def]
		local buildings = scanBuildings()
		local cur = buildingOf(player, s.uid, buildings)

		if action == "assign" then
			if a2 == nil then
				if cur then clearHut(cur) end
				return { ok = true }
			end
			if type(a2) ~= "string" then return { ok = false, why = "bad" } end
			local target
			for _, b in ipairs(buildings) do
				if b.id == a2 then target = b end
			end
			if not target then return { ok = false, why = "Здания уже нет" } end
			if cur == target then return { ok = true } end
			if #target.workers >= target.cap then return { ok = false, why = "Все места заняты" } end
			if cur then clearHut(cur) end
			local hut = target.hut
			hut:SetAttribute("SurvivorKey", survivorKey(player, s.uid))
			hut:SetAttribute("WorkerModel", s.def)
			hut:SetAttribute("WorkerName", def.name)
			if target.kind == "farm" then
				hut:SetAttribute("WorkerWage", D.wagePerHour(s.salary))
				hut:SetAttribute("IncomeBonus", D.bonusAmount(def, "farmIncome"))
			else
				hut:SetAttribute("IncomeBonus", D.bonusAmount(def, "fishIncome"))   -- FishingService: к выручке
			end
			respawnWorker(target)
			print(("%s %s: %s → %s (%s)"):format(LOG, player.Name, def.name, target.name, target.place))
			if target.kind == "fishing" then
				if typeof(_G.OnQuestEvent) == "function" then pcall(_G.OnQuestEvent, player, "assigned:Fisher", 1) end
				if typeof(_G.MerchantStoryEvent) == "function" then pcall(_G.MerchantStoryEvent, "assigned:Fisher", player) end
			end
			return { ok = true }

		elseif action == "save" then
			local v = tonumber(a2)
			if not v then return { ok = false, why = "bad" } end
			v = math.clamp(math.floor(v / D.SALARY_STEP + 0.5) * D.SALARY_STEP, 0, D.SALARY_MAX)
			s.salary = v
			if cur then
				cur.hut:SetAttribute("WorkerWage", D.wagePerHour(v))   -- ставка фермы — сразу
			end
			saveCrew(player)
			return { ok = true }

		elseif action == "fire" then
			if cur then clearHut(cur) end
			table.remove(crews[player].list, idx)
			saveCrew(player)
			print(("%s %s выгнал %s"):format(LOG, player.Name, def.name))
			return { ok = true }
		end
		return { ok = false, why = "bad" }
	end)()
	busy[player] = nil
	result.state = publicState(player)
	return result
end

-- есть ли этот житель в команде (таверна не выдаёт того, кто уже есть)
_G.SurvivorOwned = function(player, defId)
	for _, s in ipairs(crews[player] and crews[player].list or {}) do
		if s.def == defId then return true end
	end
	return false
end

-- silent = true: без попапа «Новый персонаж» (капитан аккаунта, полученный раньше —
-- например, в лобби, где попап уже сыгран)
_G.GrantSurvivor = function(player, defId, silent)
	defId = defId or "rose"
	local crew = crews[player]
	if not (crew and D.CATALOG[defId]) then return false, "нет такого выжившего" end
	if #crew.list >= D.MAX_CREW then return false, "команда полная" end
	for _, s in ipairs(crew.list) do
		if s.def == defId then return false, "этот выживший уже в команде" end
	end
	table.insert(crew.list, { uid = HttpService:GenerateGUID(false):sub(1, 8), def = defId, salary = D.CATALOG[defId].salary })
	saveCrew(player)
	player:SetAttribute("TeamUnlocked", true)   -- первый житель открывает «Команду»
	changed:FireClient(player)
	if not silent then unlocked:FireClient(player, defId) end
	-- капитан навсегда на аккаунте (PirateProgression → PirateProgress_v1.captains)
	if typeof(_G.SaveCaptain) == "function" then _G.SaveCaptain(player, defId) end
	-- отметка «в этом забеге уже выдан»: уволил — при перезаходе не вернётся
	crew.daily = crew.daily or {}
	crew.daily[defId] = true
	return true
end

--[[ ═══ КАПИТАНЫ АККАУНТА → КОМАНДА ЗАБЕГА (при входе в океан) ═══
     owned — { [defId] = true } из общей базы (PirateProgress_v1.captains). Каждый
     встаёт в команду МОЛЧА (попап сыгран там, где капитана получили — в лобби или
     в этом же забеге). Отметка crew.daily[defId] едет в сейв плота: уволенный
     в этом забеге не возвращается при перезаходе, в новом забеге придёт снова.
     Заодно капитаны, что уже стоят в команде (старые сохранения), дописываются
     в базу аккаунта — так база «объединяется» без ручного переноса. ]]
_G.SyncAccountCaptains = function(player, owned)
	local crew = crews[player]
	if not crew then return end
	crew.daily = crew.daily or {}
	for _, s in ipairs(crew.list) do
		crew.daily[s.def] = true
		if not owned[s.def] and typeof(_G.SaveCaptain) == "function" then _G.SaveCaptain(player, s.def) end
	end
	for defId in pairs(owned) do
		if D.CATALOG[defId] and not crew.daily[defId] then
			local ok, why = _G.GrantSurvivor(player, defId, true)
			print(("%s %s: капитан аккаунта %s → %s"):format(LOG, player.Name, defId, ok and "в команде" or tostring(why)))
		end
	end
end

--[[ Житель из ежедневки лобби (PirateProgression → dailyItems.hero_rose).
     Выдаётся ОДИН РАЗ ЗА ЗАБЕГ: отметка crew.daily[defId] едет в сейв плота
     вместе с командой. Уволил — не вернётся; новая игра — придёт снова (команда
     и есть часть забега). Уже в команде — просто ставим отметку. Команда полная —
     отметку не ставим, попробуем при следующем входе. ]]
_G.GrantDailySurvivor = function(player, defId)
	local crew = crews[player]
	if not (crew and D.CATALOG[defId]) then return false, "нет команды или жителя" end
	crew.daily = crew.daily or {}
	if crew.daily[defId] then return false, "уже выдан в этом забеге" end
	if _G.SurvivorOwned(player, defId) then
		crew.daily[defId] = true
		return false, "уже в команде"
	end
	local ok, why = _G.GrantSurvivor(player, defId)
	if ok then crew.daily[defId] = true end
	return ok, why
end

--[[ ⚠️ ДОМ МОГ ПОДНЯТЬСЯ РАНЬШЕ НАС. Плот из сохранения собирается при старте, и
     ферма могла выпустить обычного фермера до того, как здесь появился
     _G.SurvivorTemplate. Раз в несколько секунд сверяем: на доме записан
     выживший, а работает не он — пересобираем работника. ]]
task.spawn(function()
	while true do
		task.wait(4)
		if typeof(_G.RaftFarmList) == "function" and typeof(_G.RaftFarmRespawnWorker) == "function" then
			for _, f in ipairs(_G.RaftFarmList()) do
				local want = f.hut:GetAttribute("WorkerModel")
				local isSurvivor = f.worker and f.worker:GetAttribute("SurvivorWorker") ~= nil
				if want and not isSurvivor and _G.SurvivorTemplate(want) then
					_G.RaftFarmRespawnWorker(f.hut)
				end
			end
		end
		if typeof(_G.RaftFishingList) == "function" and typeof(_G.RaftFishingRespawn) == "function" then
			for _, f in ipairs(_G.RaftFishingList()) do
				local want = f.spot:GetAttribute("WorkerModel")
				local cur = f.npc and f.npc:GetAttribute("SurvivorWorker")
				if want and f.npc and cur ~= want and _G.SurvivorTemplate(want) then
					_G.RaftFishingRespawn(f.spot)
				end
			end
		end
	end
end)

Players.PlayerAdded:Connect(loadCrew)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(loadCrew, p) end
Players.PlayerRemoving:Connect(function(p)
	busy[p] = nil
	-- ⚠️ НЕ СРАЗУ: сейв плота на выходе (RaftSaveSystem) читает команду через
	-- _G.SurvivorCrewExport, а порядок обработчиков PlayerRemoving не задан
	task.delay(30, function() crews[p] = nil end)
end)

print(LOG .. " готово: команда игрока, здания плота (фермы), назначение заменяет фермера")
