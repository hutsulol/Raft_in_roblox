-- RaftSaveSystem.server.lua
-- Saves and loads raft layout + inventory using DataStoreService.
-- Place in ServerScriptService of the OCEAN sub-place.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local RaftShared = require(ReplicatedStorage:WaitForChild("RaftSaveShared"))
-- УКРЕПЛЁННЫЙ ПОЛ: сохраняется как floors.kind = "iron" (тем же полем, что и сеть)
local RaftReinforce = require(ReplicatedStorage:WaitForChild("RaftReinforce"))

-- Маркер версии: если этой строки НЕТ в Output океана при старте
-- сервера — плейс НЕ синхронизирован с актуальным кодом сохранений.
print("[RaftSave] loaded v-slots (AUTO_SLOT=" .. tostring(RaftShared.AUTO_SLOT)
	.. ", MAX_SLOTS=" .. tostring(RaftShared.MAX_SLOTS) .. ")")

-- Per-player ownership tracking. Forward-declared up here (T18) so
-- savePlayerData (defined further down) captures the same local as
-- the join-time + leave-time wiring at line ~750. Previously the
-- function captured a nil global, and PlayerRemoving / BindToClose
-- crashed with "attempt to index nil with Instance" trying to read
-- playerIsRaftOwner[player].
local playerIsRaftOwner = {} -- [player] = true/false
-- наружу: капитан плота (RaftCrew даёт ему право высадить игрока)
_G.IsRaftOwner = function(player) return playerIsRaftOwner[player] == true end
--[[ ⚠️ ЧЕЙ ЭТО ПЛОТ — НУЖНО ЗНАТЬ И ПРИ СОХРАНЕНИИ, А НЕ ТОЛЬКО ПРИ ЗАГРУЗКЕ.
     Гость приезжает в сейв владельца, и его собственные вещи должны лечь в
     хранилище, привязанное к ЭТОМУ плоту и слоту: иначе, вернувшись к другу
     завтра, он начнёт с пустыми руками (ровно на это и пожаловались).
     Пишем сюда владельца сейва в момент входа — на выходе teleportData уже
     недоступен. ]]
local playerSaveOwner = {} -- [player] = userId владельца сейва

-- Активный слот сейва этого игрока (из TeleportData.saveSlot).
-- Владелец пишет/грузит свой плот в этот слот; не-владелец всегда
-- работает со слотом 1 своего ключа (как было раньше).
local playerActiveSlot = {} -- [player] = 1..MAX_SLOTS

--[[ ⚠️ АВТОСЕЙВ ПИШЕТ В ТОТ СЛОТ, ИЗ КОТОРОГО СЕССИЯ ЗАГРУЖЕНА.
     Раньше автосейв всегда шёл в слот «АВТО» (3), а активный слот в индексе
     не трогал. Загрузил слот 1, играл два дня, вышел — плот ушёл в слот 3, а
     «Продолжить» в лобби снова поднимал слот 1: игрок видел мир на момент
     первого выхода. Лобби считает «слот = игра» (пустой слот = новая игра в
     нём), значит и продолжение той же игры обязано ложиться в её слот.
     Слот сессии один на сервер: у гостей он тот же, что у хозяина. Свежая игра
     без загрузки (обычный пад) слота не имеет — она, как и прежде, идёт в
     «АВТО», и активным слотом становится он, чтобы «Продолжить» её нашёл. ]]
local sessionSlot = nil -- слот, из которого поднят этот сервер (nil = новая игра)
local function autosaveSlot(player, forcedSlot)
	if forcedSlot then return sessionSlot or forcedSlot end
	return playerActiveSlot[player] or 1
end

--[[ ⚠️ НЕ ПЕРЕЗАПИСЫВАЕМ ГОСТЕВОЙ КЛЮЧ, ЕСЛИ НЕ СМОГЛИ ЕГО ПРОЧИТАТЬ.
     Чтение вещей гостя может не удаться (троттлинг DataStore при парном заходе).
     Игрок остаётся с пустыми руками — и через две минуты автосейв кладёт эту
     пустоту в тот же ключ поверх целых вещей. Один неудачный запрос стирал бы
     весь инвентарь друга навсегда. Пока чтение не подтвердилось, гостю запись
     запрещена: лучше не сохранить эту сессию, чем потерять предыдущие. ]]
local guestLoadFailed = {} -- [player] = true, если GetAsync гостя упал

local raftStore = nil
local storeOk, storeErr = pcall(function()
	raftStore = DataStoreService:GetDataStore("RaftSaveData_v1")
end)
if not storeOk then
	warn("[RaftSave] Failed to get DataStore: " .. tostring(storeErr))
else
	print("[RaftSave] DataStore connected OK")
end

local AUTOSAVE_INTERVAL = 60 -- seconds (было 120: сессия в минуту-две оставалась без автосейва)

-- Keep the map's original raft transform so a "new game" (or missing save)
-- can always start from the intended spawn position.
local INITIAL_RAFT_CFRAME = nil
--[[ Что стояло на плоту при старте сервера (стол механика, тотем, стартовые
     клетки): это часть карты, оно есть в каждом новом сервере само, и в сейв
     «1 в 1» его писать нельзя — иначе при загрузке появится второй экземпляр. ]]
local MAP_FIXED = setmetatable({}, { __mode = "k" })
do
	local raft = workspace:FindFirstChild("Raft")
	if raft and raft.PrimaryPart then
		INITIAL_RAFT_CFRAME = raft.PrimaryPart.CFrame
		for _, child in ipairs(raft:GetChildren()) do MAP_FIXED[child] = true end
	end
end

-- ─── Slot layout sync: client sends slot positions to server ───
local slotLayoutEvent = Instance.new("RemoteEvent")
slotLayoutEvent.Name = "SlotLayoutSync"
slotLayoutEvent.Parent = ReplicatedStorage

local cachedSlotLayouts = {} -- [player] = slotData table

slotLayoutEvent.OnServerEvent:Connect(function(player, slotLayout)
	if typeof(slotLayout) == "table" then
		cachedSlotLayouts[player] = slotLayout
		-- Reconcile pending deltas: compare layout totals against the
		-- server's actual inventory.  If the layout is missing items
		-- (client couldn't fit them into slotData), keep a delta so
		-- the server still knows those slots are "spoken for".
		if _G.ReconcilePendingDeltas then
			_G.ReconcilePendingDeltas(player)
		end
	end
end)

-- Expose the cached client slot layout to other server scripts (notably
-- InventoryManager, which uses it to compute capacity/empty-slot checks
-- based on the player's actual visual layout rather than server-side
-- quantities). User-driven stack splitting (e.g. 30 stones across
-- 3 slots of 28+1+1) is invisible to the quantity-based math, so the
-- layout is the only accurate source of truth for how many slots are
-- occupied and how much same-type partial space exists.
_G.GetClientSlotLayout = function(player)
	return cachedSlotLayouts[player]
end

-- ─── CFrame serialization ───
local function serializeCFrame(cf)
	return {cf:GetComponents()} -- 12 numbers
end

local function deserializeCFrame(t)
	if not t or #t < 12 then return CFrame.new() end
	return CFrame.new(unpack(t))
end

-- ─── Grid lattice phase ───
-- Mirror of the BuildingSystem helper: snap the grid origin onto the actual
-- Raft_part tile lattice so saved tiles restore aligned even when the raft's
-- PrimaryPart (e.g. a SpawnLocation) drifted a fraction of a cell off the
-- tiles in Studio. Returns (0, 0) when the PrimaryPart is already aligned.
local function getGridPhase(raft, gridSize)
	local primary = raft and raft.PrimaryPart
	if not primary then return 0, 0 end
	local restYaw = primary:GetAttribute("RestYaw")
	if not restYaw then
		local _, yaw, _ = primary.CFrame:ToEulerAnglesYXZ()
		restYaw = yaw
	end
	local flatCF = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0)

	-- ГОЛОСОВАНИЕ БОЛЬШИНСТВОМ — держать РАВНЫМ копиям getGridPhase в
	-- BuildingSystem (сервер/клиент): «первая попавшаяся» доска могла быть
	-- кривой из прошлых сессий и задать другую фазу, чем у стройки
	local counts, reps = {}, {}
	for _, child in raft:GetChildren() do
		if child.Name == "Raft_part" then
			--[[ ⚠️ ТОЧКА КЛЕТКИ — КАК У СТРОЙКИ: PrimaryPart, иначе центр бокса.
			     Здесь стоял GetPivot(), а у клетки пола пивот сдвинут от центра
			     примерно на два студа (см. BuildingSystem). Фаза сетки при загрузке
			     выходила другой, чем при стройке, и всё, что ставится по сетке —
			     стены, новые клетки, — вставало со сдвигом относительно настила:
			     «после загрузки постройки не такие, как были». Правило теперь
			     дословно то же, что в getGridPhase системы стройки. ]]
			local pos
			if child:IsA("Model") then
				local pp = child.PrimaryPart
				if pp then
					pos = pp.Position
				else
					local ok, bb = pcall(function() return child:GetBoundingBox() end)
					pos = ok and bb.Position or nil
				end
			elseif child:IsA("BasePart") then
				pos = child.Position
			end
			if pos then
				local lp = flatCF:PointToObjectSpace(pos)
				local function canon(v)
					local p = (v - math.round(v / gridSize) * gridSize) % gridSize
					if p > gridSize / 2 then p -= gridSize end
					return p
				end
				local px, pz = canon(lp.X), canon(lp.Z)
				local key = (math.round(px * 4) % (gridSize * 4)) .. "_"
					.. (math.round(pz * 4) % (gridSize * 4))
				counts[key] = (counts[key] or 0) + 1
				reps[key] = reps[key] or { px, pz }
			end
		end
	end
	local bestKey, bestN
	for k, n in pairs(counts) do
		if not bestN or n > bestN then bestKey, bestN = k, n end
	end
	if bestKey then return reps[bestKey][1], reps[bestKey][2] end
	return 0, 0
end

-- ⚠️ ВАРИАНТЫ СТЕН НА РЕБРЕ КЛЕТКИ — ОДИН СПИСОК НА ВСЕ.
-- Окно, листва, ограда и полустена отличаются от глухой стены только моделью.
-- Заводить каждой свой массив в сейве значит менять формат сохранения при каждой
-- новой стене; вместо этого они лежат в edgeWalls с полем kind, и следующая
-- добавляется одной строкой здесь и одной — в BuildingSystem.
-- Имена моделей держать теми же, что в BuildingSystem: по ним ищется шаблон.
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))
local WallDefs = require(ReplicatedStorage:WaitForChild("RaftWallDefs"))
local EDGE_WALL_NAMES = WallDefs.EdgeWalls

local function findEdgeWallTemplate(kind)
	local def = EDGE_WALL_NAMES[kind]
	return def and WallDefs.findModel(ReplicatedStorage, def.names) or nil
end

--[[ ⚠️ КАДР ПОКОЯ ПЛОТА — ОДНА ФУНКЦИЯ НА СОХРАНЕНИЕ И ЗАГРУЗКУ.
     Позиция корня и только рыскание (RestYaw): крен от волны в него не входит,
     поэтому сохранённое «где стояло» не зависит от того, как плот качнуло в
     момент сейва, а при загрузке — от того, как качнуло при загрузке. ]]
--[[ ⚠️ СИСТЕМА КООРДИНАТ СЕЙВА — ПОЛНЫЙ CFrame PrimaryPart ПЛОТА.
     Здесь был «кадр покоя» из RestYaw. Но PrimaryPart плота наклонена на 90°,
     и её рыскание, взятое разложением Эйлера, вырождено (BoatMovement об этом
     предупреждает): между сессиями оно не совпадает с реальным поворотом
     настила. Диагностика показала: опорные детали встают ровно туда, куда
     просит сейв, — а весь набор всё равно повёрнут на 90° относительно палубы.
     Настил приварен к PrimaryPart намертво, эта связь одинакова в любой сессии,
     поэтому считаем всё относительно самой PrimaryPart. Так работал старый
     путь предметов, и очиститель с лежанкой вставали верно. ]]
local function restFrameOf(raft)
	return raft.PrimaryPart.CFrame
end

--[[ ⚠️ СЕЙВ «1 В 1»: КАЖДАЯ ПОСТРОЙКА — ГДЕ СТОЯЛА, ТАМ И ВСТАНЕТ.
     Прежний формат хранил клетки и стены как координаты сетки, а предметы —
     по списку известных имён, и восстанавливал всё пересчётом: своя формула на
     пол, своя на стену, своя на сеть, свои поправки пивотов. Каждая из них
     расходилась со стройкой по-своему: клетки вставали боком, стены не на
     том ребре, сеть уезжала, а лежанка и мангал не сохранялись вовсе, потому
     что их не было в списке. Владелец: «пусть сохраняются так, как стояли».
     Теперь у КАЖДОГО ребёнка плота (кроме карты, NPC и брошенных предметов)
     пишем имя, пивот относительно кадра покоя и все атрибуты. Клон того же
     шаблона, поставленный PivotTo в тот же относительный пивот, повторяет
     оригинал точно: конвенция пивота у шаблона и у экземпляра одна.
     Старые сейвы без поля placed читаются прежним путём. ]]
local function attrsOf(inst)
	local out = {}
	for k, v in pairs(inst:GetAttributes()) do
		local t = typeof(v)
		if t == "string" or t == "number" or t == "boolean" then out[k] = v end
	end
	return out
end

--[[ ⚠️ ОПОРНАЯ ДЕТАЛЬ ВМЕСТО ПИВОТА И БОКСА.
     Пивот у моделей без PrimaryPart застывает и не едет за плотом; габаритный
     бокс без PrimaryPart выровнен по миру, а не по модели — и всё, что стройка
     поворачивала по-своему (клетка на 90°, стена на 0/90, сеть со своим
     фиксом), при загрузке теряло поворот: плот вставал «на 90°». Единственное,
     что честно едет с плотом и точно повторяется у клона того же шаблона, —
     сама ДЕТАЛЬ. Берём PrimaryPart, а без него — первую BasePart по порядку
     обхода (у клона порядок тот же), и запоминаем её CFrame в кадре покоя.
     При загрузке двигаем клон целиком так, чтобы эта деталь встала туда же:
     delta = want * ref.CFrame⁻¹, PivotTo(delta * pivot) — тот же приём, что у
     сторожа поз в RaftRelocate. ]]
--[[ ⚠️ PrimaryPart В РАСЧЁТ НЕ БЕРЁМ. У экземпляра на плоту его назначают
     серверные системы уже после постановки (RaftStaticWeld, стройка), а у
     шаблона в хранилище его нет. «Та же деталь» у клона оказывалась другой —
     бревно вместо настила, — и разница их поворотов давала те самые 90°.
     Берём первую BasePart по обходу и запоминаем ПУТЬ по именам от корня
     модели: он одинаков у экземпляра и у клона. ]]
local function pathOf(root, part)
	local names = {}
	local node = part
	while node and node ~= root do
		table.insert(names, 1, node.Name)
		node = node.Parent
	end
	return table.concat(names, "/")
end
local function byPath(root, path)
	local node = root
	for name in string.gmatch(path, "[^/]+") do
		node = node and node:FindFirstChild(name)
	end
	return node and node:IsA("BasePart") and node or nil
end

local function refPartOf(inst)
	if inst:IsA("BasePart") then return inst, 0 end
	local i = 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			i += 1
			return d, i
		end
	end
	return nil, nil
end

-- та же деталь у клона: PrimaryPart (-1), сама деталь (0) или n-я BasePart
local function refPartByIndex(inst, idx)
	if idx == 0 then return inst:IsA("BasePart") and inst or nil end
	if idx == -1 then return inst.PrimaryPart or refPartOf(inst) end
	local i = 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			i += 1
			if i == idx then return d end
		end
	end
	return (refPartOf(inst))
end

--[[ Мебель карты (стол, тотем, бочка топлива, любой декор плота): экземпляр
     есть в каждом сервере, клонировать нельзя, но ПОЛОЖЕНИЕ пишем — игрок
     двигает станцию и тотем, бочку могло сдвинуть. Стартовые клетки пола и
     NPC не трогаем: клетки стоят по сетке, NPC ходят сами. ]]
local FLOOR_NAMES_FIXED = { Raft_part = true, Net_Part = true }
local function isMovableFixed(child)
	return not FLOOR_NAMES_FIXED[child.Name]
end

--[[ РЕВИЗИЯ «ОТСТАВШИХ» ДЕТАЛЕЙ. В сейве у сети и стены центр бокса оказался
     на 370 студов от плота: внутри модели есть деталь, оставшаяся на точке
     спавна. Такая деталь — кандидат на рывки плота. Печатаем, что это. ]]
local function reportStrayParts(raft, why)
	local pp = raft and raft.PrimaryPart
	if not pp then return end
	local rootAsm = pp.AssemblyRootPart or pp
	local n, checked = 0, 0
	for _, child in ipairs(raft:GetChildren()) do
		local isNpc = child:IsA("Model") and child:FindFirstChildWhichIsA("Humanoid", true) ~= nil
		if (child:IsA("Model") or child:IsA("BasePart")) and not isNpc then
			for _, d in ipairs(child:IsA("Model") and child:GetDescendants() or { child }) do
				if d:IsA("BasePart") and not d:GetAttribute("NoRaftWeld") then
					checked += 1
					if d.AssemblyRootPart ~= rootAsm then
						n += 1
						local welds = {}
						for _, w in ipairs(d:GetChildren()) do
							if w:IsA("WeldConstraint") then
								table.insert(welds, ("%s→%s en=%s act=%s"):format(w.Part0 and w.Part0.Name or "nil", w.Part1 and w.Part1.Name or "nil", tostring(w.Enabled), tostring(w.Active)))
							end
						end
						print(("[RaftSave/ревизия %s] НЕ В СБОРКЕ ПЛОТА: %s | %s | Anchored=%s | сборка=%s | от плота %.0f | сварок: %s")
							:format(why, child.Name, d:GetFullName(), tostring(d.Anchored), d.AssemblyRootPart and d.AssemblyRootPart.Name or "—",
								(d.Position - pp.Position).Magnitude, #welds > 0 and table.concat(welds, "; ") or "нет"))
					end
				end
			end
		end
	end
	print(("[RaftSave/ревизия %s] проверено деталей %d, вне сборки плота %d, корень сборки плота: %s (Anchored=%s)")
		:format(why, checked, n, rootAsm.Name, tostring(pp.Anchored)))
end

local function collectPlaced(raft)
	reportStrayParts(raft, "сбор")
	local rest = restFrameOf(raft)
	do
		local _, ry = rest:ToEulerAnglesYXZ()
		local px, py, pz = raft.PrimaryPart.CFrame:ToEulerAnglesYXZ()
		print(("[RaftSave/сбор 1в1] кадр покоя: pos (%.1f, %.1f, %.1f) yaw %.1f° | PrimaryPart euler (%.0f, %.0f, %.0f)")
			:format(rest.X, rest.Y, rest.Z, math.deg(ry), math.deg(px), math.deg(py), math.deg(pz)))
	end
	local list = {}
	for _, child in ipairs(raft:GetChildren()) do
		local fixed = MAP_FIXED[child] == true
		if child ~= raft.PrimaryPart and (not fixed or isMovableFixed(child))
			and (child:IsA("Model") or child:IsA("BasePart"))
			and not (child:IsA("Model") and child:FindFirstChildWhichIsA("Humanoid", true))
			and not child:HasTag("DroppedItem") and not child:GetAttribute("NoSave")
			-- рюкзак стартового комплекта: часть карты, живёт своим сценарием (BackPackPickUp)
			and not (child.Name:lower():find("backpack", 1, true) or child:FindFirstChild("BackpackPrompt", true)) then
			--[[ ⚠️ ЖИВАЯ ГЕОМЕТРИЯ, А НЕ ПИВОТ. У модели без PrimaryPart WorldPivot
			     — застывший мировой CFrame с момента постановки: плот уплыл, детали
			     уехали с ним, пивот остался. Сохранённый по нему сейв ставил стены
			     столбом. GetBoundingBox считается по деталям, а его ориентация —
			     та же, что у пивота (она у плота с запертым рысканием не меняется). ]]
			local ref, idx = refPartOf(child)
			if ref then
				local rel = rest:ToObjectSpace(ref.CFrame)
				local attrs = attrsOf(child)
				local rope = child:IsA("Model") and child:FindFirstChildWhichIsA("RopeConstraint", true) or nil
				if rope then attrs.SavedRopeLength = rope.Length end   -- якорь: глубина троса
				table.insert(list, { name = child.Name, cf = serializeCFrame(rel), ri = idx,
					rp = (ref ~= child) and pathOf(child, ref) or nil,
					attrs = attrs, fixed = fixed or nil })
				print(("[RaftSave/сбор 1в1] %s%s | опорная деталь %s в кадре покоя (%.1f, %.1f, %.1f)")
					:format(child.Name, fixed and " (карта)" or "", (ref ~= child) and pathOf(child, ref) or ref.Name, rel.X, rel.Y, rel.Z) .. ((function() local ex, ey, ez = rel:ToEulerAnglesYXZ() return (" euler (%.0f, %.0f, %.0f)"):format(math.deg(ex), math.deg(ey), math.deg(ez)) end)()))
			end
		end
	end
	return list
end

--[[ МИР: ОСТРОВА, ДОМА, ВЫШКИ, ЖИТЕЛИ.
     Острова пишем относительно плота: при загрузке плот стоит на точке карты,
     а острова встают на тех же расстояниях и в тех же сторонах, что были.
     Дома и вышки — относительно СВОЕГО острова (ближайшего), чтобы точно лечь
     на его сушу. Зачищенные и изученные острова помечены атрибутами, их
     ставит карта и зачистка; гарнизон на зачищенных при загрузке не выходит. ]]
local function nearestIslandIndex(list, pos)
	local best, bestD
	for i, m in ipairs(list) do
		local c = m:GetAttribute("LandCenter")
		if typeof(c) ~= "Vector3" then c = m:GetPivot().Position end
		local r = tonumber(m:GetAttribute("LandRadius")) or 300
		local d = (Vector3.new(c.X, 0, c.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
		if d <= r + 80 and (not bestD or d < bestD) then best, bestD = i, d end
	end
	return best
end

local function collectWorldData(player)
	local raft = workspace:FindFirstChild("Raft")
	if not (raft and raft.PrimaryPart) then return nil end
	local rp = raft.PrimaryPart.Position
	local models = typeof(_G.ListMapIslands) == "function" and _G.ListMapIslands() or {}
	local islands = {}
	for _, m in ipairs(models) do
		table.insert(islands, {
			name = m.Name,
			cf = serializeCFrame(m:GetPivot()),
			cleared = m:GetAttribute("Cleared") == true,
			seen = m:GetAttribute("MapSeen") == true,
			prisonersFreed = m:GetAttribute("PrisonersFreed") == true or nil,
			keep = m:GetAttribute("KeepAlive") == true or nil,
			-- высота центра суши: пивот модели после клона может встать иначе, а суша
			-- обязана лечь на ту же высоту к воде
			ly = typeof(m:GetAttribute("LandCenter")) == "Vector3" and m:GetAttribute("LandCenter").Y or nil,
		})
	end
	local function relTo(cf)
		local i = nearestIslandIndex(models, cf.Position)
		if i then return i, serializeCFrame(models[i]:GetPivot():ToObjectSpace(cf)) end
		return nil, nil
	end
	local houses = {}
	for _, h in ipairs(typeof(_G.HouseExport) == "function" and _G.HouseExport() or {}) do
		local i, rel = relTo(h.cf)
		table.insert(houses, { cf = serializeCFrame(h.cf), isle = i, rel = rel, level = h.level, capacity = h.capacity, residents = h.residents })
	end
	local rigs = {}
	for _, r in ipairs(typeof(_G.OilRigExport) == "function" and _G.OilRigExport() or {}) do
		local i, rel = relTo(r.cf)
		table.insert(rigs, { cf = serializeCFrame(r.cf), isle = i, rel = rel })
	end
	-- фермы: положение относительно своего острова плюс состояние (запасы, овцы)
	local farms = {}
	for _, f in ipairs(typeof(_G.FarmExport) == "function" and _G.FarmExport() or {}) do
		local i, rel = relTo(f.cf)
		f.cf, f.isle, f.rel = serializeCFrame(f.cf), i, rel
		table.insert(farms, f)
	end
	print(("[RaftSave/мир] островов %d, домов %d, вышек %d, ферм %d"):format(#islands, #houses, #rigs, #farms))
	return {
		raftPos = { rp.X, rp.Y, rp.Z },
		islands = islands, houses = houses, rigs = rigs, farms = farms,
		villagers = tonumber(player:GetAttribute("Villagers")),
		seed = typeof(_G.GetWorldSeed) == "function" and _G.GetWorldSeed() or nil,
	}
end

local function restoreWorldData(player, world)
	if type(world) ~= "table" then return end
	task.spawn(function()
		for _ = 1, 60 do
			if typeof(_G.SpawnIsland) == "function" then break end
			task.wait(0.5)
		end
		local raft = workspace:FindFirstChild("Raft")
		if not (raft and raft.PrimaryPart and typeof(_G.SpawnIsland) == "function") then
			warn("[RaftSave/мир] спавнер островов не поднялся — мир не восстановлен")
			return
		end
		if type(world.seed) == "table" and typeof(_G.SetWorldSeed) == "function" then
			pcall(_G.SetWorldSeed, world.seed.seed, world.seed.step)
		end
		local rp = raft.PrimaryPart.Position
		local saved = world.raftPos and Vector3.new(world.raftPos[1], world.raftPos[2], world.raftPos[3]) or rp
		local delta = Vector3.new(rp.X - saved.X, 0, rp.Z - saved.Z)
		local placed = {}
		for i, rec in ipairs(world.islands or {}) do
			local cf = deserializeCFrame(rec.cf) + delta
			local ok, why, island = _G.SpawnIsland({
				name = rec.name, cframe = cf, cleared = rec.cleared == true, keepAlive = rec.keep == true,
				attrs = { MapSeen = rec.seen == true or nil, PrisonersFreed = rec.prisonersFreed or nil },
			})
			if ok and island then
				placed[i] = island
				local c = island:GetAttribute("LandCenter")
				-- ⚠️ ВЫСОТУ ПРАВИМ ПО ЦЕНТРУ СУШИ. Остров из сейва вставал чуть ниже:
				-- пивот у клона считается иначе, чем у оригинала. Центр суши считает
				-- спавнер по плиткам после постановки — по нему и выравниваем.
				if typeof(c) == "Vector3" and type(rec.ly) == "number" then
					local dy = rec.ly - c.Y
					if math.abs(dy) > 0.05 then
						island:PivotTo(island:GetPivot() + Vector3.new(0, dy, 0))
						c = c + Vector3.new(0, dy, 0)
						island:SetAttribute("LandCenter", c)
						print(("[RaftSave/мир] остров %s: высота суши поправлена на %+.2f"):format(tostring(rec.name), dy))
					end
				end
				if typeof(c) ~= "Vector3" then c = island:GetPivot().Position end
				print(("[RaftSave/мир] остров %s: центр %.0f %.0f %.0f, до плота %.0f, зачищен=%s, keep=%s"):format(
					tostring(rec.name), c.X, c.Y, c.Z, (c - rp).Magnitude, tostring(rec.cleared == true), tostring(rec.keep == true)))
				if rec.cleared and typeof(_G.OnIslandCleared) == "function" then
					task.delay(2, function() if island.Parent then pcall(_G.OnIslandCleared, island) end end)
				end
			else
				warn(("[RaftSave/мир] остров %s не поднят: %s"):format(tostring(rec.name), tostring(why)))
			end
		end
		local function worldCF(rec)
			local isle = rec.isle and placed[rec.isle]
			if isle and rec.rel then return isle:GetPivot() * deserializeCFrame(rec.rel) end
			return deserializeCFrame(rec.cf) + delta
		end
		task.wait(1)   -- островам дать встать до построек на них
		local nh, nr = 0, 0
		for _, rec in ipairs(world.houses or {}) do
			if typeof(_G.HouseRestore) == "function" and pcall(_G.HouseRestore, worldCF(rec), rec) then nh += 1 end
		end
		for _, rec in ipairs(world.rigs or {}) do
			if typeof(_G.OilRigRestore) == "function" and pcall(_G.OilRigRestore, worldCF(rec), player) then nr += 1 end
		end
		-- фермы — ПОСЛЕ домов: жители с профессией «Фермер» уже восстановлены, и
		-- ферма при подъёме найдёт своего работника по сохранённому id
		local nf = 0
		for _, rec in ipairs(world.farms or {}) do
			if typeof(_G.FarmRestore) == "function" then
				local ok, err = pcall(_G.FarmRestore, worldCF(rec), rec, player)
				if ok and err then nf += 1 else warn("[RaftSave/мир] ферма не поднята: " .. tostring(err)) end
			end
		end
		if typeof(_G.FarmReconcile) == "function" then pcall(_G.FarmReconcile) end
		-- остров с постройками игрока спавнер не сносит, даже если в сейве флага не было
		local list = {}
		for _, isle in pairs(placed) do table.insert(list, isle) end
		for _, rec in ipairs(world.houses or {}) do
			local i = nearestIslandIndex(list, worldCF(rec).Position)
			if i then list[i]:SetAttribute("KeepAlive", true) end
		end
		for _, rec in ipairs(world.rigs or {}) do
			local i = nearestIslandIndex(list, worldCF(rec).Position)
			if i then list[i]:SetAttribute("KeepAlive", true) end
		end
		for _, rec in ipairs(world.farms or {}) do
			local i = nearestIslandIndex(list, worldCF(rec).Position)
			if i then list[i]:SetAttribute("KeepAlive", true) end
		end
		if world.villagers then
			task.delay(1, function() if player.Parent then player:SetAttribute("Villagers", world.villagers) end end)
		end
		print(("[RaftSave/мир] восстановлено: островов %d, домов %d, вышек %d, ферм %d, жителей-валюты %s")
			:format(#placed, nh, nr, nf, tostring(world.villagers)))
	end)
end

--[[ «ВСЁ ОСТАЛЬНОЕ»: ящик патронов, флаги мира и игрока, экипировка, бак нефти,
     жажда/голод/радиация/здоровье, час суток, ящики водолаза, еда на мангале.
     У владельца — всё; у гостя — только личное (флаги, экипировка, выживание). ]]
-- TeamLives — жизни команды (DeathPenalty): без сейва перезаход возвращал бы все три
local WS_FLAGS  = { "WaveClearedNight", "OutpostIsleScene", "StartIsleScene",
	"TeamMaxPlayers", "TeamLivesSpent", "TeamLivesBonus" }
-- сюжетные метки игрока: имена из констант OutpostIsleStory (ATTR_HELP и др.)
local PLR_FLAGS = { "RobotQuest1Done", "DiverQuestGiven", "FreshWaterHintGiven", "WeaponPickups",
	"OutpostFlamerHelped", "OutpostFlamerWakeHint", "OutpostFuelGiven", "OutpostBurnOpened" }
local OilCanisterMod = nil
pcall(function() OilCanisterMod = require(ReplicatedStorage:WaitForChild("OilCanister", 5)) end)

local function collectExtras(player, guest)
	local e = { plrFlags = {}, survival = {} }
	for _, k in ipairs(PLR_FLAGS) do
		local v = player:GetAttribute(k)
		local t = typeof(v)
		if t == "string" or t == "number" or t == "boolean" then e.plrFlags[k] = v end
	end
	e.equipment = typeof(_G.EquipmentExport) == "function" and _G.EquipmentExport(player) or nil
	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	e.survival = {
		thirst = typeof(_G.GetThirst) == "function" and _G.GetThirst(player) or nil,
		hunger = typeof(_G.GetHunger) == "function" and _G.GetHunger(player) or nil,
		health = hum and hum.Health > 0 and hum.Health or nil,
		radiation = typeof(_G.GetRadiationLeft) == "function" and _G.GetRadiationLeft(player) or nil,
	}
	if guest then return e end
	e.wsFlags = {}
	for _, k in ipairs(WS_FLAGS) do
		local v = workspace:GetAttribute(k)
		local t = typeof(v)
		if t == "string" or t == "number" or t == "boolean" then e.wsFlags[k] = v end
	end
	local case = workspace:FindFirstChild("Ammo_case")
	e.ammoCaseOpened = (case == nil) or case:GetAttribute("AmmoCaseOpened") == true
	if OilCanisterMod then
		local okT, tank = pcall(OilCanisterMod.findTank, workspace)
		if okT and tank then e.oilMl = tonumber(tank:GetAttribute(OilCanisterMod.TANK_ATTR)) end
	end
	e.dayClock = typeof(_G.GetDayClock) == "function" and _G.GetDayClock() or nil
	e.dayCount = typeof(_G.GetDayCount) == "function" and _G.GetDayCount() or nil
	-- сюжет торговца (MerchantStory): этап живёт вместе с забегом, как номер дня
	e.merchantStory = typeof(_G.MerchantStoryExport) == "function" and _G.MerchantStoryExport() or nil
	-- команда жителей (SurvivorService) — тоже часть забега: новая игра = пустая команда
	e.crew = typeof(_G.SurvivorCrewExport) == "function" and _G.SurvivorCrewExport(player) or nil
	e.crates = typeof(_G.DiverExportCrates) == "function" and _G.DiverExportCrates() or nil
	e.grills = typeof(_G.GrillExport) == "function" and _G.GrillExport() or nil
	return e
end

local function restoreExtras(player, e, isOwner)
	if type(e) ~= "table" then return end
	for k, v in pairs(e.plrFlags or {}) do pcall(function() player:SetAttribute(k, v) end) end
	-- экипировка и выживание — когда персонаж на месте
	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		char:WaitForChild("Humanoid", 10)
		task.wait(1.5)
		if not player.Parent then return end
		if e.equipment and typeof(_G.EquipmentRestore) == "function" then pcall(_G.EquipmentRestore, player, e.equipment) end
		local s = e.survival or {}
		if s.thirst and typeof(_G.SetThirst) == "function" then pcall(_G.SetThirst, player, s.thirst) end
		if s.hunger and typeof(_G.SetHunger) == "function" then pcall(_G.SetHunger, player, s.hunger) end
		local hum = char:FindFirstChildWhichIsA("Humanoid")
		if hum and s.health and s.health > 0 then hum.Health = math.min(hum.MaxHealth, s.health) end
		if s.radiation and s.radiation > 0 and typeof(_G.SetRadiationLeft) == "function" then pcall(_G.SetRadiationLeft, player, s.radiation) end
	end)
	if not isOwner then return end
	for k, v in pairs(e.wsFlags or {}) do pcall(function() workspace:SetAttribute(k, v) end) end
	if e.ammoCaseOpened then
		local case = workspace:FindFirstChild("Ammo_case")
		if case then case:Destroy(); print("[RaftSave/extra] ящик патронов уже вскрыт — убран") end
	end
	if e.oilMl and OilCanisterMod then
		task.delay(2, function()
			local okT, tank = pcall(OilCanisterMod.findTank, workspace)
			if okT and tank then tank:SetAttribute(OilCanisterMod.TANK_ATTR, e.oilMl) end
		end)
	end
	if e.dayClock and typeof(_G.SetDayClock) == "function" then pcall(_G.SetDayClock, e.dayClock) end
	if e.dayCount and typeof(_G.SetDayCount) == "function" then
		-- сначала точка отсчёта рекорда, потом сам счётчик: его Changed сразу
		-- пересчитывает рекорд
		if typeof(_G.SetRunDaysJoin) == "function" then pcall(_G.SetRunDaysJoin, player, e.dayCount) end
		pcall(_G.SetDayCount, e.dayCount)
		print("[RaftSave/extra] день из сейва: " .. tostring(e.dayCount))
	end
	if type(e.merchantStory) == "table" and typeof(_G.MerchantStoryRestore) == "function" then
		pcall(_G.MerchantStoryRestore, e.merchantStory)
	end
	-- старый сейв без команды → команда пустая (жителей выдаёт сюжет)
	if isOwner and typeof(_G.SurvivorCrewRestore) == "function" then
		pcall(_G.SurvivorCrewRestore, player, type(e.crew) == "table" and e.crew or {})
	end
	task.delay(3, function()
		local nc, ng = 0, 0
		for _, rec in ipairs(e.crates or {}) do
			if typeof(_G.DiverRestoreCrate) == "function" and pcall(_G.DiverRestoreCrate, rec) then nc += 1 end
		end
		for _, rec in ipairs(e.grills or {}) do
			if typeof(_G.GrillRestore) == "function" then
				local ok, n = pcall(_G.GrillRestore, rec)
				if ok then ng += (tonumber(n) or 0) end
			end
		end
		print(("[RaftSave/extra] восстановлено: ящиков водолаза %d, еды на мангале %d, час суток %s, нефти %s мл")
			:format(nc, ng, tostring(e.dayClock), tostring(e.oilMl)))
	end)
end

-- ─── Collect raft data ───
local function collectRaftData(player)
	local raft = workspace:FindFirstChild("Raft")
	if not raft then
		warn("[RaftSave] No Raft model in workspace")
		return nil
	end
	if not raft.PrimaryPart then
		warn("[RaftSave] Raft has no PrimaryPart")
		return nil
	end
	print("[RaftSave] Found Raft with " .. #raft:GetChildren() .. " children")

	local raftCF = raft.PrimaryPart.CFrame
	local data = {
		floors = {},
		walls = {},
		beams = {},
		wallPanels = {},
		wallArches = {},
		edgeWalls = {},
		doors = {},
		objects = {},
		placed = collectPlaced(raft),
	}

	for _, child in raft:GetChildren() do
		local buildType = child:GetAttribute("BuildType")

		if buildType == "raft" then
			local gx = child:GetAttribute("GridX")
			local gz = child:GetAttribute("GridZ")
			if gx and gz then
				-- kind различает доску и сеть: обе живут в floors как полноценный пол
				table.insert(data.floors, { gx = gx, gz = gz, kind = child:GetAttribute("TileKind") })
				local lp = raftCF:PointToObjectSpace(child:IsA("Model") and child:GetBoundingBox().Position or child.Position)
				print(("[RaftSave/сбор] клетка %s gx=%s gz=%s kind=%s | центр в осях плота (%.1f, %.1f, %.1f)"):format(child.Name, tostring(gx), tostring(gz), tostring(child:GetAttribute("TileKind")), lp.X, lp.Y, lp.Z))
			end

		elseif buildType == "beam" then
			local cx = child:GetAttribute("CornerX")
			local cz = child:GetAttribute("CornerZ")
			if cx and cz then
				table.insert(data.beams, {cx = cx, cz = cz})
			end

		elseif buildType == "wall_panel" then
			local cx1 = child:GetAttribute("BeamCX1")
			local cz1 = child:GetAttribute("BeamCZ1")
			local cx2 = child:GetAttribute("BeamCX2")
			local cz2 = child:GetAttribute("BeamCZ2")
			if cx1 and cz1 and cx2 and cz2 then
				table.insert(data.wallPanels, {cx1 = cx1, cz1 = cz1, cx2 = cx2, cz2 = cz2})
				local wp = raftCF:ToObjectSpace(child:GetPivot())
				local _, wy = wp:ToEulerAnglesYXZ()
				print(("[RaftSave/сбор] стена %s (%.1f,%.1f)-(%.1f,%.1f) | в осях плота (%.1f, %.1f, %.1f) поворот %.0f°"):format(child.Name, cx1, cz1, cx2, cz2, wp.X, wp.Y, wp.Z, math.deg(wy)))
			end

		elseif buildType == "wall_arch" then
			local cx1 = child:GetAttribute("BeamCX1")
			local cz1 = child:GetAttribute("BeamCZ1")
			local cx2 = child:GetAttribute("BeamCX2")
			local cz2 = child:GetAttribute("BeamCZ2")
			if cx1 and cz1 and cx2 and cz2 then
				table.insert(data.wallArches, {cx1 = cx1, cz1 = cz1, cx2 = cx2, cz2 = cz2})
			end

		-- ⚠️ ВАРИАНТЫ СТЕН — ОДНИМ СПИСКОМ С ПОМЕТКОЙ ВИДА.
		-- Окно, листва и ограда отличаются только моделью, поэтому заводить каждому
		-- свой массив в сейве значит трогать формат при каждой новой стене. Вид
		-- лежит полем kind, и следующая добавляется строкой в EDGE_WALL_NAMES ниже.
		elseif EDGE_WALL_NAMES[buildType] then
			local cx1 = child:GetAttribute("BeamCX1")
			local cz1 = child:GetAttribute("BeamCZ1")
			local cx2 = child:GetAttribute("BeamCX2")
			local cz2 = child:GetAttribute("BeamCZ2")
			if cx1 and cz1 and cx2 and cz2 then
				table.insert(data.edgeWalls,
					{cx1 = cx1, cz1 = cz1, cx2 = cx2, cz2 = cz2, kind = buildType})
				local wp = raftCF:ToObjectSpace(child:GetPivot())
				local _, wy = wp:ToEulerAnglesYXZ()
				print(("[RaftSave/сбор] ограда %s %s (%.1f,%.1f)-(%.1f,%.1f) | в осях плота (%.1f, %.1f, %.1f) поворот %.0f°"):format(child.Name, buildType, cx1, cz1, cx2, cz2, wp.X, wp.Y, wp.Z, math.deg(wy)))
			end

		elseif buildType == "door" then
			local cx1 = child:GetAttribute("BeamCX1")
			local cz1 = child:GetAttribute("BeamCZ1")
			local cx2 = child:GetAttribute("BeamCX2")
			local cz2 = child:GetAttribute("BeamCZ2")
			if cx1 and cz1 and cx2 and cz2 then
				table.insert(data.doors, {cx1 = cx1, cz1 = cz1, cx2 = cx2, cz2 = cz2})
			end

		elseif buildType == "wall" then
			local gx = child:GetAttribute("GridX")
			local gz = child:GetAttribute("GridZ")
			local wk = child:GetAttribute("WallKey")
			if gx and gz and wk then
				local side = tonumber(wk:match("_(%d+)$"))
				if side then
					table.insert(data.walls, {gx = gx, gz = gz, side = side})
				end
			end

		elseif child:IsA("Model") or child:IsA("BasePart") then
			-- Placed objects (Furnace, WorkBench, Bed, Garden, Purifier/Destitalor, bush)
			local name = child.Name
			local knownObjects = {
				Furnace = true, WorkBench = true, Bed = true,
				Garden = true, Destitalor = true, Purifier = true, bush = true,
			}
			-- Also match purifier variants
			if knownObjects[name] or name:find("Destitalor") or name:find("Garden") then
				--[[ ⚠️ СОХРАНЯЕМ ПИВОТ, А НЕ ЦЕНТР ГАБАРИТНОГО БОКСА.
				     Раньше писали GetBoundingBox(), а при загрузке ставили его через
				     PivotTo — то есть как пивот. У моделей из FBX пивот повёрнут и
				     смещён относительно бокса (у грядки, например, на −90° по X), и
				     после загрузки очиститель, грядка и лежанка вставали перевёрнутыми
				     и сдвинутыми. Теперь пишем ровно то, что потом и ставим. Флаг pv
				     отличает новый формат: старые сейвы без него читаются как раньше. ]]
				local objCF
				if child:IsA("Model") then
					objCF = child:GetPivot()
				else
					objCF = child.CFrame
				end
				local localCF = raftCF:ToObjectSpace(objCF)

				local objData = {
					name = name,
					cf = serializeCFrame(localCF),
					pv = true,   -- cf — пивот модели (новый формат)
				}

				-- Save garden state
				if child:GetAttribute("IsGarden") then
					objData.isGarden = true
					objData.isWatered = child:GetAttribute("IsWatered") or false
				end

				-- Save purifier state
				if child:GetAttribute("WaterType") then
					objData.waterLevel = child:GetAttribute("WaterLevel") or 0
					objData.waterType = child:GetAttribute("WaterType") or "none"
				end

				table.insert(data.objects, objData)
			end
		end
	end

	print("[RaftSave] Collected: " .. #data.floors .. " floors, " .. #data.beams .. " beams, " .. #data.wallPanels .. " wallPanels, " .. #data.wallArches .. " arches, " .. #data.edgeWalls .. " edgeWalls, " .. #data.doors .. " doors, " .. #data.walls .. " walls(legacy), " .. #data.objects .. " objects")
	return data
end

-- ─── Collect inventory data ───
local function collectInventoryData(player)
	local inv = _G.GetInventory and _G.GetInventory(player)
	if not inv then return {} end

	local data = {}
	for key, value in inv do
		if typeof(value) == "number" then
			data[key] = value
		end
	end
	return data
end

-- ─── Collect tools from Backpack + Character ───
--[[ ⚠️ ИНСТРУМЕНТ В РУКАХ ПРИ ВЫХОДЕ. Сбор смотрит в рюкзак и в персонажа,
     но на PlayerRemoving персонаж нередко уже удалён — и всё, что было в
     руках (весло), в автосейв не попадало; в рюкзаке при этом всё цело.
     Держим снимок последнего живого списка: он обновляется каждым
     сохранением по таймеру и при смене экипировки, а при выходе берётся,
     если живой список оказался короче. ]]
local lastToolsSnapshot = setmetatable({}, { __mode = "k" })

local function collectToolData(player)
	local tools = {}
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character

	if backpack then
		for _, item in backpack:GetChildren() do
			if item:IsA("Tool") then
				table.insert(tools, item.Name)
			end
		end
	end
	if char then
		for _, item in char:GetChildren() do
			if item:IsA("Tool") then
				table.insert(tools, item.Name)
			end
		end
	end

	local snap = lastToolsSnapshot[player]
	if char and char.Parent then
		lastToolsSnapshot[player] = table.clone(tools)
	elseif snap and #snap > #tools then
		print(("[RaftSave] персонажа уже нет — беру снимок инструментов (%d вместо %d)"):format(#snap, #tools))
		tools = table.clone(snap)
	end
	print("[RaftSave] Collected " .. #tools .. " tools: " .. table.concat(tools, ", "))
	return tools
end

--[[ СОСТОЯНИЕ ИНСТРУМЕНТОВ: прочность и патроны.
     Список имён (tools) восстанавливал тулы из шаблонов — с полной прочностью
     и полной обоймой: вышел с пустым барабаном, вошёл с полным. Рядом с
     именами пишем toolsState: атрибуты тула (Durability, CupState, …) и
     числовые значения из папки Configs (Ammo, ReserveAmmo, MagSize). При
     загрузке применяем к восстановленному тулу с тем же именем. ]]
local function toolStateOf(tool)
	local rec = { name = tool.Name, attrs = {}, cfg = {} }
	for k, v in pairs(tool:GetAttributes()) do
		local t = typeof(v)
		if t == "string" or t == "number" or t == "boolean" then rec.attrs[k] = v end
	end
	local c = tool:FindFirstChild("Configs")
	if c then
		for _, v in ipairs(c:GetChildren()) do
			if v:IsA("IntValue") or v:IsA("NumberValue") then rec.cfg[v.Name] = v.Value end
		end
	end
	return rec
end
local lastToolsStateSnapshot = setmetatable({}, { __mode = "k" })
local function collectToolState(player)
	local list = {}
	local char = player.Character
	local bp = player:FindFirstChild("Backpack")
	if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then table.insert(list, toolStateOf(t)) end end end
	if char and char.Parent then
		for _, t in ipairs(char:GetChildren()) do if t:IsA("Tool") then table.insert(list, toolStateOf(t)) end end
		lastToolsStateSnapshot[player] = list
	else
		local snap = lastToolsStateSnapshot[player]
		if snap and #snap > #list then list = snap end
	end
	return list
end
local function applyToolState(player, states)
	if type(states) ~= "table" then return 0 end
	local bp = player:FindFirstChild("Backpack")
	if not bp then return 0 end
	local used = {}
	local n = 0
	for _, rec in ipairs(states) do
		for _, t in ipairs(bp:GetChildren()) do
			if t:IsA("Tool") and not used[t] and t.Name == rec.name then
				used[t] = true
				for k, v in pairs(rec.attrs or {}) do pcall(function() t:SetAttribute(k, v) end) end
				local c = t:FindFirstChild("Configs")
				if not c and next(rec.cfg or {}) then c = Instance.new("Folder"); c.Name = "Configs"; c.Parent = t end
				for k, v in pairs(rec.cfg or {}) do
					local x = c:FindFirstChild(k)
					if not x then x = Instance.new("IntValue"); x.Name = k; x.Parent = c end
					x.Value = v
				end
				n += 1
				break
			end
		end
	end
	return n
end

-- снимок обновляем и при смене экипировки: взял/убрал/выбросил — список свежий
local function watchToolsOf(player)
	local function refresh()
		task.defer(function()
			if not player.Parent then return end
			local char = player.Character
			if not (char and char.Parent) then return end
			local list = {}
			local bp = player:FindFirstChild("Backpack")
			if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then table.insert(list, t.Name) end end end
			for _, t in ipairs(char:GetChildren()) do if t:IsA("Tool") then table.insert(list, t.Name) end end
			lastToolsSnapshot[player] = list
			lastToolsStateSnapshot[player] = collectToolState(player)
		end)
	end
	local function hook(container)
		if not container then return end
		container.ChildAdded:Connect(refresh)
		container.ChildRemoved:Connect(refresh)
	end
	hook(player:FindFirstChild("Backpack"))
	player.ChildAdded:Connect(function(c) if c.Name == "Backpack" then hook(c) end end)
	if player.Character then hook(player.Character) end
	player.CharacterAdded:Connect(function(c) hook(c); refresh() end)
end
Players.PlayerAdded:Connect(watchToolsOf)
for _, plr in ipairs(Players:GetPlayers()) do watchToolsOf(plr) end

-- ─── Save player data ───
-- forcedSlot: автосейв (выход/таймер/шатдаун) пишет в слот «АВТО»
-- (RaftShared.AUTO_SLOT); ручное сохранение — nil → активный слот.
--[[ ⚠️ ВЕЩИ ГОСТЯ ЛЕЖАТ В СВОЁМ КЛЮЧЕ, А НЕ В СЕЙВЕ ВЛАДЕЛЬЦА.
     Соблазн дописать их в сейв хозяина велик — всё в одном месте. Но тогда
     чужие инвентари растят его запись (лимит на ключ конечен), а главное — их
     пишет сервер владельца, и при вылете хозяина вещи гостя не сохранятся вовсе.
     Свой ключ решает оба вопроса: гость сам пишет и сам читает, размер сейва
     владельца не меняется.
     В ключе три части, и каждая обязательна: чьи вещи, чей плот, какой слот.
     Без владельца вещи из разных компаний смешались бы, без слота — вещи из
     разных сохранений одного и того же друга. ]]
--[[ ⚠️ ВЕЩИ ГОСТЯ ПОМЕЧАЕМ СЕССИЕЙ СЕРВЕРА.
     Гость, заходящий в игру друга БЕЗ загрузки сейва, раньше всегда получал
     вещи по ключу «гость × хозяин × слот». Задумано это для перезахода в
     ТЕКУЩУЮ игру, но новая игра без загрузки пишется в тот же слот «АВТО» —
     и в свежий забег приезжали вещи из прошлого («зашёл в новую игру, а
     предметы со старой»). Теперь сохранённые вещи несут id сессии сервера, и
     без загрузки сейва они возвращаются только в ТУ ЖЕ сессию. JobId в Studio
     пустой, поэтому id свой — GUID на старт сервера. ]]
local SESSION_ID = game:GetService("HttpService"):GenerateGUID(false)

local function guestKey(guestUserId, ownerUserId, slot)
	return ("guest_%d_%d_%d"):format(guestUserId, ownerUserId, slot)
end

--[[ ⚠️ ОТЧЁТ О ПОСЛЕДНЕМ АВТОСЕЙВЕ — В ХРАНИЛИЩЕ, А НЕ ТОЛЬКО В КОНСОЛИ.
     Приватный сервер закрывается вместе с последним игроком, и что случилось
     с сейвом на выходе, увидеть негде. Пишем короткий итог в отдельный ключ и
     печатаем его при следующем входе: «прошлый выход: …». ]]
local function exitReport(player, text)
	if not raftStore then return end
	pcall(function()
		raftStore:SetAsync("exitlog_" .. player.UserId, { t = os.time(), text = text })
	end)
end

local function savePlayerData(player, forcedSlot)
	if not raftStore then
		warn("[RaftSave] No DataStore, cannot save for " .. player.Name)
		return false
	end

	-- Only the raft owner gets raft data saved (prevents duplication exploit)
	local isOwner = playerIsRaftOwner[player]
	if isOwner == nil then isOwner = true end -- fallback for direct joins

	--[[ Гость в чужом плоту НЕ пишет в свой ключ: раньше не-владелец
	     перезаписывал свой слот-1 пустым плотом (raft=nil) и терял СВОЙ
	     сохранённый плот. Мульти-слот: чужая сессия не трогает свой сейв.
	     ⚠️ НО ВЕЩИ ЕГО СОХРАНЯЕМ — в отдельный гостевой ключ.
	     Плот по-прежнему только у владельца (иначе дубликат плота), а инвентарь,
	     инструменты и раскладка слотов принадлежат самому игроку: вернувшись в
	     ту же игру друга, он должен найти их на месте. ]]
	if not isOwner then
		local ownerId = playerSaveOwner[player]
		--[[ ⚠️ ГОСТЬ ЛОЖИТСЯ В ТОТ ЖЕ СЛОТ, ЧТО И ПЛОТ ХОЗЯИНА В ЭТОМ ЖЕ ВЫЗОВЕ.
		     Здесь стоял «слот сессии, а не forcedSlot» — и это была та самая
		     ошибка, из-за которой вещи друга пропадали каждый раз.
		     Смотрите, как расходились ключи: играли в слоте 1, на выходе автосейв
		     кладёт ПЛОТ хозяина в слот «АВТО» (3), а вещи гостя уходили в слот 1.
		     Назавтра хозяин выбирает в меню самый свежий сейв — тот самый «АВТО»
		     — и вся компания приезжает со saveSlot = 3. Гость ищет свои вещи по
		     ключу …_3, а лежат они в …_1. Ключи расходились КАЖДУЮ сессию, то
		     есть найтись вещи не могли в принципе.
		     Правило теперь одно: чем помечен снимок плота, тем помечены и вещи
		     гостя. Что грузится — то и находится. ]]
		local slot = math.clamp(math.floor(autosaveSlot(player, tonumber(forcedSlot))), 1, RaftShared.MAX_SLOTS)
		if not ownerId then
			print("[RaftSave] Гость " .. player.Name .. ": владелец сейва неизвестен — вещи не сохраняю")
			exitReport(player, "гость: владелец сейва неизвестен — вещи НЕ сохранены")
			return true
		end
		-- см. guestLoadFailed: пустой инвентарь после неудачного чтения не должен
		-- затереть целые вещи
		if guestLoadFailed[player] then
			print("[RaftSave] Гость " .. player.Name .. ": прошлое чтение вещей не удалось — НЕ перезаписываю сохранённое")
			return true
		end

		local guestData = {
			inventory = collectInventoryData(player),
			tools = collectToolData(player),
			toolsState = collectToolState(player),
			extra = collectExtras(player, true),
			slotLayout = cachedSlotLayouts[player] or {},
			hasBackpack = player:GetAttribute("HasBackpack") == true,
			savedAt = os.time(),
			session = SESSION_ID,   -- см. SESSION_ID: без загрузки сейва вещи вернутся только в эту сессию
		}
		local ok, err = pcall(function()
			raftStore:SetAsync(guestKey(player.UserId, ownerId, slot), guestData)
		end)
		if ok then
			print(("[RaftSave] Гость %s: вещи сохранены (плот %d, слот %d)")
				:format(player.Name, ownerId, slot))
			exitReport(player, ("гость: вещи сохранены, плот %d, слот %d, инструментов %d"):format(ownerId, slot, #guestData.tools))
		else
			warn(("[RaftSave] Гость %s: вещи не сохранились — %s"):format(player.Name, tostring(err)))
			exitReport(player, "гость: SetAsync не удался: " .. tostring(err))
		end
		return true
	end

	workspace:SetAttribute("LastAutosaveAt", os.clock())   -- для зонда рывков (RaftMotionProbe)
	local okC, raftData = pcall(collectRaftData, player)
	if not okC then
		warn("[RaftSave] сбор плота упал: " .. tostring(raftData))
		exitReport(player, "сбор плота упал: " .. tostring(raftData))
		return false
	end
	local invData = collectInventoryData(player)
	local toolData = collectToolData(player)

	print("[RaftSave] Collecting data for " .. player.Name .. " - raft: " .. tostring(raftData ~= nil) .. ", tools: " .. #toolData)

	-- Skip if there's truly nothing to save
	if not raftData and (not invData or next(invData) == nil) and #toolData == 0 then
		print("[RaftSave] No data to save for " .. player.Name)
		return true
	end

	local saveData = {
		inventory = invData,
		tools = toolData,
		toolsState = collectToolState(player),
		slotLayout = cachedSlotLayouts[player] or {},
		raft = raftData,
		-- рюкзак подобран (гейт инвентаря) — атрибут игрока
		hasBackpack = player:GetAttribute("HasBackpack") == true,
		--[[ ⚠️ РЮКЗАК РАЗОБРАН — ЭТО СВОЙСТВО ПЛОТА, А НЕ ИГРОКА.
		     Иначе при возврате в свою же игру рюкзак лежит нетронутым и выдаёт
		     второй комплект: сохранённый флаг игрока закрывает гейт инвентаря, но
		     не мешает подобрать модель заново (см. BackPackPickUp). ]]
		backpackTaken = workspace:GetAttribute("BackpackTaken") == true,
		-- кто уже получил стартовый комплект из рюкзака (UserId через запятую, см. BackPackPickUp)
		backpackTakenBy = workspace:GetAttribute("BackpackTakenBy"),
		--[[ ⚠️ СИЛА — ЧАСТЬ ЭТОГО ПЛОТА, А НЕ АККАУНТА.
		     Уровень силы и накопленные удары сохраняются вместе с сейвом:
		     вернулся к своей игре — сила при тебе, начал новую — качаешь заново.
		     Своего хранилища у силы нет намеренно (см. Characteristics/Stats/
		     Strength.server.lua), иначе прогресс перетекал бы между забегами. ]]
		strength = _G.GetStrengthSave and _G.GetStrengthSave(player) or nil,
		-- статус монолита: серверно-общий (сохраняем в сейве владельца)
		monolith = {
			repaired = (_G.IsMonolithRepaired and _G.IsMonolithRepaired()) or false,
			levels = (_G.GetMonolithUpgradeLevels and _G.GetMonolithUpgradeLevels()) or nil,
		},
		--[[ ⚠️ ДНИ ЗАБЕГА — СВОЙСТВО ПЛОТА, КАК И СИЛА.
		     Счётчик дней сервера начинается с единицы при каждом старте, поэтому без
		     этого поля возвращение к своему сохранению обнуляло бы прожитые дни, и
		     рекорд выживания навсегда упирался бы в длину одной сессии. ]]
		daysSurvived = _G.GetRunDays and _G.GetRunDays(player) or nil,
		-- механик разбужен: день пробуждения лежит в Workspace (EngineerSystem)
		engineerWokeDay = workspace:GetAttribute("EngineerWokeDay"),
		world = collectWorldData(player),
		extra = collectExtras(player, false),
		savedAt = os.time(),
	}

	local slot = math.clamp(math.floor(autosaveSlot(player, tonumber(forcedSlot))), 1, RaftShared.MAX_SLOTS)
	local key = RaftShared.slotKey(player.UserId, slot)
	local success, err = pcall(function()
		raftStore:SetAsync(key, saveData)
	end)

	-- Отметить слот в индексе (время сохранения) — только когда есть плот
	if success and raftData then
		pcall(function()
			raftStore:UpdateAsync(RaftShared.indexKey(player.UserId), function(old)
				local idx = RaftShared.normalizeIndex(old)
				local entry = idx.slots[slot] or { name = RaftShared.defaultSlotName(slot) }
				entry.savedAt = os.time()
				idx.slots[slot] = entry
				-- активным становится слот, куда легла игра: «Продолжить» поднимет её
				idx.activeSlot = slot
				return idx
			end)
		end)
	end

	if success then
		print("[RaftSave] Saved data for " .. player.Name .. " (slot " .. slot .. ")")
		if forcedSlot then exitReport(player, ("ок: слот %d, плот=%s, объектов 1в1=%d, инструментов %d (%s)"):format(slot, tostring(raftData ~= nil), raftData and raftData.placed and #raftData.placed or 0, #toolData, table.concat(toolData, ","))) end
	else
		warn("[RaftSave] Failed to save for " .. player.Name .. ": " .. tostring(err))
		exitReport(player, "SetAsync не удался: " .. tostring(err))
		-- Studio without API access: every SetAsync fails anyway, and the periodic save burst
		-- (collect + several stores at once) stalls the server for over a second — the stall
		-- kicked the raft physics ("прыжки ровно на 5-й день" = the FIRST autosave at t=120s).
		-- Disable further autosaves for this session after the first such failure.
		if tostring(err):find("API access") or tostring(err):find("StudioAccessToApis") then
			_G.__RaftSaveDisabled = true
			warn("[RaftSave] Studio API access is off — autosave DISABLED for this session (no data would save anyway)")
		end
	end

	return success
end

-- ─── Load player data ───
local function loadPlayerData(player)
	if not raftStore then
		warn("[RaftSave] No DataStore, cannot load for " .. player.Name)
		return nil
	end
	local key = RaftShared.slotKey(player.UserId, playerActiveSlot[player] or 1)
	local success, data = pcall(function()
		return raftStore:GetAsync(key)
	end)

	if success and data then
		print(string.format("[RaftSave] Loaded save for %s key=%s raft=%s (saved at %s)",
			player.Name, key, tostring(data.raft ~= nil), tostring(data.savedAt)))
		return data
	elseif not success then
		warn("[RaftSave] DataStore read failed for " .. player.Name .. " key=" .. key .. ": " .. tostring(data))
	else
		print("[RaftSave] No save data at key=" .. key .. " for " .. player.Name)
	end
	return nil
end

--[[ ⚠️ ПЛОТ ПЕРЕНОСИМ ЗАЯКОРЕННЫМ — ИНАЧЕ ДЕКОР ОСТАЁТСЯ ЛЕЖАТЬ.
     Вот вся история «стол механика перевёрнут». PivotTo переносит детали модели
     разом, но скорости не обнуляет и физику не ждёт. Всё, что стоит на палубе
     НЕ приваренным, в этот момент — отдельное тело: рывок телепорта оно
     отрабатывает как удар и заваливается набок. А приварить его успевают только
     на третьей секунде (RaftStaticWeld ждёт, пока физика соберёт сборки) — и
     сварка честно фиксирует ту позу, в которой застала. Дальше станция лежит
     уже навсегда: ни один механизм её не поднимает.
     Вдвоём это ловится чаще, потому что второй игрок приносит второй запрос к
     DataStore и второй повод дёрнуть плот — уже посреди игры.
     Поэтому: запоминаем, что было заякорено, якорим всё (скорости обнуляются),
     переносим и через кадр возвращаем якоря как было. ]]
local raftPlaced = false   -- плот уже поставлен на место в этой сессии

--[[ ⚠️ ФЛАГ «СЕРВЕР ЗАКОНЧИЛ С ПЛОТОМ» — НА workspace, А НЕ НА МОДЕЛИ ПЛОТА.
     Его ждёт экран загрузки (ReplicatedFirst/TeleportLoadingScreen), прежде чем
     греть содержимое палубы и гасить шторку: греть плот раньше бессмысленно —
     половины деталей ещё нет, и игрок выходит в мир на прозрачных досках.
     На самой модели Raft держать нельзя: при StreamingEnabled модель доезжает до
     клиента ПОЗЖЕ атрибута на ней, и клиент будет ждать инстанс, чтобы прочитать
     «уже не жди». workspace есть всегда.
     ⚠️ СТАВИМ ВО ВСЕХ ИСХОДАХ, ВКЛЮЧАЯ АВАРИЙНЫЕ. До конца пересборки доходят
     далеко не все пути: сейва может не быть вовсе, GetAsync может не ответить,
     в сейве может не оказаться плота, а второму игроку пересобирать уже нечего.
     Флаг только в успешной ветке означал бы вечную шторку у всех остальных. ]]
local function markRaftReady(why)
	if workspace:GetAttribute("RaftReady") then return end
	workspace:SetAttribute("RaftReady", true)
	print("[RaftSave] плот готов для клиента: " .. tostring(why))
end

--[[ ⚠️ ВЛАДЕНИЕ ФИЗИКОЙ ПЛОТА — ТОЛЬКО СЕРВЕР.
     Когда к плоту привариваются два десятка деталей из сейва, сборка
     пересобирается (корень стал raft_floor), и Roblox сбрасывает её сетевого
     владельца в «авто»: ближайший игрок, стоящий на палубе, начинает вести
     физику плота, а сервер — свою. Два хозяина тянут плот по очереди — те
     самые рывки после загрузки. BoatMovement закрепляет владение только при
     старте, поэтому повторяем после перестройки и после снятия якорей. ]]
local function claimRaftForServer(raft, why)
	local pp = raft and raft.PrimaryPart
	if not pp then return end
	local n = 0
	for _, d in ipairs(raft:GetDescendants()) do
		if d:IsA("BasePart") and not d.Anchored then
			if pcall(function() d:SetNetworkOwner(nil) end) then n += 1 end
		end
	end
	local root = pp.AssemblyRootPart or pp
	print(("[RaftSave] владение плотом закреплено за сервером (%s): деталей %d, корень сборки %s"):format(tostring(why), n, root.Name))
end

--[[ СТОРОЖ ВЛАДЕНИЯ. После загрузки плот минуту шёл ровно, потом рывки
     возвращались: сборка пересобирается и позже (сеть приваривает пойманное
     бревно, автосейв, новые постройки), и владение снова уходит клиенту.
     Раз в секунду проверяем хозяина сборки; ушёл к игроку — возвращаем
     серверу и пишем, кто и когда отобрал: по этим строкам видно виновника. ]]
local ownerWatchStarted = false
local function startOwnerWatch(raft)
	if ownerWatchStarted then return end
	ownerWatchStarted = true
	task.spawn(function()
		local reclaimed, lastLog = 0, 0
		while raft.Parent do
			task.wait(1)
			local pp = raft.PrimaryPart
			if pp and not pp.Anchored then
				local root = pp.AssemblyRootPart or pp
				local ok, owner = pcall(function() return root:GetNetworkOwner() end)
				if ok and owner ~= nil then
					pcall(function() root:SetNetworkOwner(nil) end)
					reclaimed += 1
					if os.clock() - lastLog > 5 then
						lastLog = os.clock()
						print(("[RaftSave/владение] плот вёл %s (корень %s) — вернул серверу (всего возвратов %d)")
							:format(tostring(owner), root.Name, reclaimed))
					end
				end
			end
		end
	end)
end

local function pivotRaftSafely(raft, cf, why)
	local wasAnchored = {}
	for _, d in ipairs(raft:GetDescendants()) do
		if d:IsA("BasePart") then
			wasAnchored[d] = d.Anchored
			d.Anchored = true
		end
	end

	--[[ ⚠️ ПЕРЕНОСИМ ТАК, ЧТОБЫ В cf ВСТАЛА САМА PrimaryPart, А НЕ ПИВОТ МОДЕЛИ.
	     cf — это CFrame PrimaryPart, снятый при старте. Model:PivotTo ставит в cf
	     ПИВОТ модели, а он у плота = PrimaryPart.CFrame * PivotOffset, и у этой
	     детали PivotOffset повёрнут. В итоге PrimaryPart оказывалась развёрнутой
	     на разницу — зонд писал «deck tilted 90°, capsizing — snapped upright»,
	     после чего плот ещё секунды дёргался между спасением зонда и
	     AlignOrientation («плот лагает после загрузки»). Двигаем разницей, как
	     сторож поз: delta = cf * PP⁻¹, и весь плот едет за PrimaryPart. ]]
	local pp = raft.PrimaryPart
	local delta = cf * pp.CFrame:Inverse()
	raft:PivotTo(delta * raft:GetPivot())
	do
		local ex, ey, ez = pp.CFrame:ToEulerAnglesYXZ()
		local tx, ty, tz = cf:ToEulerAnglesYXZ()
		print(("[RaftSave] перенос: PrimaryPart euler стало (%.0f, %.0f, %.0f), цель (%.0f, %.0f, %.0f)")
			:format(math.deg(ex), math.deg(ey), math.deg(ez), math.deg(tx), math.deg(ty), math.deg(tz)))
	end
	raftPlaced = true

	task.spawn(function()
		task.wait(0.15)
		local freed = 0
		for part, anchored in pairs(wasAnchored) do
			if part.Parent and not anchored then
				part.Anchored = false
				freed += 1
			end
		end
		-- ⚠️ В ТОМ ЖЕ КАДРЕ: всё свободное на палубе приваривается к плоту до
		-- первого шага физики — иначе стол механика и тотем успевают лечь.
		if typeof(_G.RaftRelocateRestoreAll) == "function" then
			pcall(_G.RaftRelocateRestoreAll, why)   -- стол/тотем: в эталон и приварить
		end
		if typeof(_G.RaftStaticWeldNow) == "function" then
			pcall(_G.RaftStaticWeldNow, why)
		end
		print(("[RaftSave] Плот перенесён под якорем (%s): отпущено деталей %d")
			:format(tostring(why), freed))
		claimRaftForServer(raft, why)
		startOwnerWatch(raft)
		-- и ещё раз через пару секунд: RaftStaticWeld доваривает своё на 3-й секунде
		task.delay(4, function() if raft.Parent then claimRaftForServer(raft, "повтор через 4 с") end end)
	end)
end

-- ─── Rebuild raft from saved data ───
local function rebuildRaft(player, saveData)
	if not saveData or not saveData.raft then markRaftReady("сейв без плота") return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then markRaftReady("плота нет или он без PrimaryPart") return end

	local rs = ReplicatedStorage
	local raftData = saveData.raft

	-- Always start from the map's initial raft position, even when loading a save.
	-- We persist raft layout and objects, but not world drift position.
	if INITIAL_RAFT_CFRAME then
		--[[ ⚠️ ВЫСОТА — ТЕКУЩАЯ, А НЕ СО СТАРТА СЕРВЕРА. INITIAL снят в первый
		     кадр, когда плот ещё не осел на воде. Возврат туда ронял плот с
		     высоты спавна, и первые секунды после загрузки он прыгал и дёргался
		     (зонд: «Y swing 2.6 studs»). X, Z и поворот берём начальные, Y — ту,
		     на которой плот уже держится. ]]
		local cur = raft.PrimaryPart.CFrame
		local target = CFrame.new(INITIAL_RAFT_CFRAME.X, cur.Y, INITIAL_RAFT_CFRAME.Z) * INITIAL_RAFT_CFRAME.Rotation
		pivotRaftSafely(raft, target, "перестройка из сейва")
		print("[RaftSave] Reset raft position to initial map spawn before rebuild")
	elseif raftData.raftPosition then
		-- Backward compatibility if initial CFrame wasn't captured for any reason.
		local savedCF = deserializeCFrame(raftData.raftPosition)
		pivotRaftSafely(raft, savedCF, "старый сейв с позицией")
		print("[RaftSave] Restored raft position from legacy save to " .. tostring(savedCF.Position))
	end

	local raftCF = raft.PrimaryPart.CFrame
	-- Store RestCFrame and RestYaw for BuildingSystem (in case BoatForwardMovement hasn't set them yet)
	if not raft.PrimaryPart:GetAttribute("RestCFrame") then
		raft.PrimaryPart:SetAttribute("RestCFrame", raftCF)
	end
	if not raft.PrimaryPart:GetAttribute("RestYaw") then
		local _, iy, _ = raftCF:ToEulerAnglesYXZ()
		raft.PrimaryPart:SetAttribute("RestYaw", iy)
	end
	-- Use RestCFrame for stable grid offsets (same approach as BuildingSystem)
	local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or raftCF
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)

	-- ⚠️ ШАБЛОНЫ ИЩЕМ ПО ИМЕНИ, А НЕ ПО МЕСТУ (AssetFind).
	-- Модели в хранилище разложены по папкам, прямое FindFirstChild их не видит —
	-- сейв тогда восстанавливается пустым, без единого признака в логе.
	local floorTemplate = AssetFind.find("Raft_part")
	-- шаблон, имя в мире и поворот — из общего модуля (RaftNetFit): раньше поправка
	-- поворота лежала числом в трёх файлах и после смены модели разъехалась
	local NetFit = require(rs:WaitForChild("RaftNetFit"))
	local netTemplate = AssetFind.find(table.unpack(NetFit.TEMPLATE_NAMES))
	local NET_ROT_FIX = NetFit.rotFix(netTemplate)
	-- пивот доски смещён от центра тайла, у сети — в центре: приводим к центру клетки
	local function pivotCenterDelta(template, scale)
		if not template or not template:IsA("Model") then return Vector3.zero end
		local ok, delta = pcall(function()
			local bbCF = template:GetBoundingBox()
			return template:GetPivot():ToObjectSpace(bbCF).Position
		end)
		return ok and (delta * (scale or 1)) or Vector3.zero
	end
	local wallTemplate = AssetFind.find("Wood_wall")
	local beamTemplate = AssetFind.find("beam")
	-- ⚠️ СПИСКИ ИМЁН — КАК В BuildingSystem.
	-- Здесь стояли ТОЛЬКО старые имена (wall_model_wood), хотя стройка давно
	-- ставит raft_wall: загрузка сейва восстанавливала стены прежней моделью, а
	-- если старой в хранилище уже нет — не восстанавливала вовсе.
	local wallPanelTemplate = AssetFind.find("raft_wall", "Raft_wall", "wall_model_wood")
	local wallArchTemplate = AssetFind.find("raft_wall_arch", "Raft_wall_arch", "wall_model_wood_arch")
	local doorTemplate = AssetFind.find("raft_door", "Raft_door", "Door_Wood")

	-- Grid size + масштабы ДОЛЖНЫ совпадать с системой стройки, иначе плот
	-- встаёт на чужую решётку и стройка ломается. НОВЫЙ ПЛОТ: клетка 10,
	-- Raft_part уже размером с клетку (масштаб 1), балки от старого плота
	-- дотягиваются 1.28. BuildingSystem публикует GridSize на шаблоне Raft_part.
	local GRID_SIZE = 10
	local TILE_SCALE = 1
	local BEAM_SCALE = 1.28
	local FLOOR_HEIGHT = 0
	if floorTemplate then
		GRID_SIZE = floorTemplate:GetAttribute("GridSize") or GRID_SIZE
		if floorTemplate:IsA("Model") then
			FLOOR_HEIGHT = floorTemplate:GetExtentsSize().Y
		elseif floorTemplate:IsA("BasePart") then
			FLOOR_HEIGHT = floorTemplate.Size.Y
		end
	end

	-- Snap restored tiles onto the real Raft_part lattice (see getGridPhase),
	-- so a PrimaryPart nudged off the tile centres can't shift the rebuild.
	local phaseX, phaseZ = getGridPhase(raft, GRID_SIZE)

	-- Beam measurements
	local BEAM_HEIGHT = 0
	local BEAM_INSET = 0
	if beamTemplate then
		if beamTemplate:IsA("Model") then
			local size = beamTemplate:GetExtentsSize()
			BEAM_HEIGHT = size.Y
			BEAM_INSET = math.max(size.X, size.Z) / 2
		elseif beamTemplate:IsA("BasePart") then
			BEAM_HEIGHT = beamTemplate.Size.Y
			BEAM_INSET = math.max(beamTemplate.Size.X, beamTemplate.Size.Z) / 2
		end
	end

	-- Высоты — тем же общим замером, что у стройки и у превью (RaftWallDefs)
	local PANEL_HEIGHT = WallDefs.heightOf(wallPanelTemplate)
	local ARCH_HEIGHT = WallDefs.heightOf(wallArchTemplate)
	local DOOR_HEIGHT = WallDefs.heightOf(doorTemplate)

	-- Floor offsets for beam inset calculation
	local function isFloorOccupied(gx, gz)
		if gx == 0 and gz == 0 then return true end
		if raftData.floors then
			for _, f in raftData.floors do
				if f.gx == gx and f.gz == gz then return true end
			end
		end
		return false
	end

	local function computeBeamInset(cx, cz)
		local insetX, insetZ = 0, 0
		local hasPlusX = isFloorOccupied(cx + 0.5, cz - 0.5) or isFloorOccupied(cx + 0.5, cz + 0.5)
		local hasMinusX = isFloorOccupied(cx - 0.5, cz - 0.5) or isFloorOccupied(cx - 0.5, cz + 0.5)
		if hasMinusX and not hasPlusX then insetX = -BEAM_INSET
		elseif hasPlusX and not hasMinusX then insetX = BEAM_INSET end

		local hasPlusZ = isFloorOccupied(cx - 0.5, cz + 0.5) or isFloorOccupied(cx + 0.5, cz + 0.5)
		local hasMinusZ = isFloorOccupied(cx - 0.5, cz - 0.5) or isFloorOccupied(cx + 0.5, cz - 0.5)
		if hasMinusZ and not hasPlusZ then insetZ = -BEAM_INSET
		elseif hasPlusZ and not hasMinusZ then insetZ = BEAM_INSET end

		return insetX, insetZ
	end

	local function localToWorldPos(studX, studZ)
		local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(studX + phaseX, 0, studZ + phaseZ))
		local localOffset = restCF:VectorToObjectSpace(worldOffset)
		return (raftCF * CFrame.new(localOffset)).Position
	end

	-- Save load: snapshot velocity + 3-pass anchor/weld/unanchor per
	-- item (T13/T15/T16/T24) so replaying the save doesn't bleed
	-- momentum out of the raft assembly.
	local primary = raft.PrimaryPart

	local function weldAndUnanchor(clone)
		local linVel = primary.AssemblyLinearVelocity
		local angVel = primary.AssemblyAngularVelocity
		if clone:IsA("Model") then
			-- Pass 0: force-anchor every part (saved state may have
			-- unanchored values from when we last saved).
			for _, part in clone:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = true
				end
			end
			-- Pass 1: weld every part while still anchored.
			-- (детали с NoRaftWeld — груз якоря на тросе — остаются свободными)
			--[[ ⚠️ НЕВЕСОМЫМИ — КАК ПРИ СТРОЙКЕ. BuildingSystem ставит Massless на всё,
			     что приваривает к плоту, иначе сборка чувствует вес каждой стены.
			     Загрузчик этого не делал: после сейва плот кренился на 9° в сторону
			     стен (зонд: assemblyMass 1704) и еле шёл — «лаганно после загрузки»,
			     а наклонённая палуба читалась как «перевёрнутые постройки». ]]
			for _, part in clone:GetDescendants() do
				if part:IsA("BasePart") and not part:GetAttribute("NoRaftWeld") then
					part.Massless = true
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = primary
					weld.Part1 = part
					weld.Parent = part
				end
			end
			-- Pass 2: unanchor (parts inherit raft velocity via the weld).
			for _, part in clone:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = false
				end
			end
		else
			clone.Anchored = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = clone
			weld.Parent = clone
			clone.Anchored = false
		end
		primary.AssemblyLinearVelocity  = linVel
		primary.AssemblyAngularVelocity = angVel
	end

	-- ВЫСОТА ЦЕНТРА ГАБАРИТОВ доски палубы над пивотом PrimaryPart, голосованием
	-- (держать логику равной deckCenterRestY в BuildingSystem: геометрия к
	-- геометрии, конвенции пивотов шаблона и досок сокращаются)
	local tileY = 0
	do
		local restRot = restCF - restCF.Position
		local counts, reps = {}, {}
		for _, child in raft:GetChildren() do
			if child.Name == "Raft_part" and child ~= raft.PrimaryPart then
				local centerPos
				if child:IsA("Model") then
					local ok, bb = pcall(function() return child:GetBoundingBox() end)
					centerPos = ok and bb.Position or nil
				elseif child:IsA("BasePart") then
					centerPos = child.Position
				end
				if centerPos then
					local rel = raft.PrimaryPart.CFrame:PointToObjectSpace(centerPos)
					local y = restRot:VectorToWorldSpace(rel).Y
					local key = math.round(y * 4)
					counts[key] = (counts[key] or 0) + 1
					reps[key] = reps[key] or y
				end
			end
		end
		local bestKey, bestN
		for k, n in pairs(counts) do
			if not bestN or n > bestN then bestKey, bestN = k, n end
		end
		tileY = bestKey and reps[bestKey] or 0
	end
	local tilePivotDelta = pivotCenterDelta(floorTemplate, TILE_SCALE)

	--[[ ⚠️ ПОВОРОТ КЛЕТКИ — КАК У БОЛЬШИНСТВА ДОСОК ПАЛУБЫ (копия
	     getTileRotationCorrection из BuildingSystem, держать равной). Пивот модели
	     Raft_part не совпадает с её лежащей геометрией: без этой поправки стройка
	     ставила доску вертикально — и ровно так же загрузчик, у которого поправки
	     не было, ставил восстановленные клетки пола боком и вверх ногами
	     («после загрузки постройки перевёрнуты»). Относительный поворот
	     примари→доска постоянен (сварка), качка на него не влияет. ]]
	local tileRotFix = CFrame.new()
	do
		local primary = raft.PrimaryPart
		local counts, reps = {}, {}
		for _, child in raft:GetChildren() do
			if child.Name == "Raft_part" and child ~= primary then
				local tileCF
				if child:IsA("Model") then
					tileCF = child:GetPivot()
				elseif child:IsA("BasePart") then
					tileCF = child.CFrame
				end
				if tileCF then
					local rot = primary.CFrame:ToObjectSpace(tileCF).Rotation
					local xv, yv = rot.XVector, rot.YVector
					local key = string.format("%d,%d,%d|%d,%d,%d",
						math.round(xv.X * 10), math.round(xv.Y * 10), math.round(xv.Z * 10),
						math.round(yv.X * 10), math.round(yv.Y * 10), math.round(yv.Z * 10))
					counts[key] = (counts[key] or 0) + 1
					reps[key] = reps[key] or rot
				end
			end
		end
		local bestKey, bestN
		for k, n in pairs(counts) do
			if not bestN or n > bestN then bestKey, bestN = k, n end
		end
		if bestKey then tileRotFix = reps[bestKey] end
	end

	-- Полувысота клетки пола: стены ставятся на ВЕРХ настила (tileY — его центр).
	local tileHalfY = 0
	do
		local ref = floorTemplate
		for _, child in raft:GetChildren() do
			if child.Name == "Raft_part" and child ~= raft.PrimaryPart then ref = child break end
		end
		if ref then
			if ref:IsA("Model") then
				local ok, _, size = pcall(function() return ref:GetBoundingBox() end)
				if ok and size then tileHalfY = size.Y * 0.5 end
			elseif ref:IsA("BasePart") then
				tileHalfY = ref.Size.Y * 0.5
			end
		end
	end

	-- ═══ СЕЙВ «1 В 1» (см. collectPlaced): ставим всё по сохранённому пивоту ═══
	if type(raftData.placed) == "table" then
		local rest = restFrameOf(raft)
		do
			local _, ry = rest:ToEulerAnglesYXZ()
			local px, py, pz = raft.PrimaryPart.CFrame:ToEulerAnglesYXZ()
			print(("[RaftSave/загрузка 1в1] кадр покоя: pos (%.1f, %.1f, %.1f) yaw %.1f° | PrimaryPart euler (%.0f, %.0f, %.0f)")
				:format(rest.X, rest.Y, rest.Z, math.deg(ry), math.deg(px), math.deg(py), math.deg(pz)))
		end
		local placedN, missing = 0, {}
		-- имена в мире отличаются от имён шаблонов: сеть переименована при
		-- установке, стартовая клетка и построенная зовутся одинаково
		local function templateFor(name)
			if name == NetFit.PLACED_NAME then return netTemplate end
			if name == "Raft_part" then return floorTemplate end
			if name == "Raft_anchor" then return AssetFind.find("Raft_anchor", "Anchor_part") end
			if name == "Purifier" then return AssetFind.find("Destitalor") end
			if name == "Bed" then return AssetFind.find("Raft_bed_leaf") end
			return AssetFind.find(name)
		end
		-- поставить модель так, чтобы её опорная деталь встала в want (кадр мира)
		local function moveByRef(inst, idx, want, path)
			local ref = (type(path) == "string" and inst:IsA("Model")) and byPath(inst, path) or nil
			if not ref then ref = refPartByIndex(inst, idx) end
			if not ref then return false end
			local delta = want * ref.CFrame:Inverse()
			if inst:IsA("Model") then inst:PivotTo(delta * inst:GetPivot()) else inst.CFrame = want end
			return true
		end
		-- переносимая мебель карты (стол, тотем): двигаем СУЩЕСТВУЮЩИЙ экземпляр
		local function moveFixed(rec)
			local inst = nil
			for _, child in ipairs(raft:GetChildren()) do
				if MAP_FIXED[child] and child.Name == rec.name then inst = child break end
			end
			if not inst then return false end
			-- снять сварки с плотом, заякорить, перенести, приварить заново
			local inModel = {}
			for _, d in ipairs(inst:GetDescendants()) do if d:IsA("BasePart") then inModel[d] = true end end
			for _, d in ipairs(raft:GetDescendants()) do
				if d:IsA("WeldConstraint") or d:IsA("Weld") then
					local a, b = d.Part0 and inModel[d.Part0], d.Part1 and inModel[d.Part1]
					if (a or b) and not (a and b) then d:Destroy() end
				end
			end
			for d in pairs(inModel) do d.Anchored = true end
			local want = rest:ToWorldSpace(deserializeCFrame(rec.cf))
			moveByRef(inst, rec.ri or -1, want, rec.rp)
			weldAndUnanchor(inst)
			if typeof(_G.RaftRelocateRecapture) == "function" then pcall(_G.RaftRelocateRecapture, inst) end
			return true
		end
		local seenAt = {}   -- [name] = { Vector3, ... }: защита от дублей в сейве
		local function isDuplicate(rec)
			local cfv = deserializeCFrame(rec.cf).Position
			local list = seenAt[rec.name]
			if list then
				for _, v in ipairs(list) do
					if (v - cfv).Magnitude < 0.5 then return true end
				end
			else
				list = {}
				seenAt[rec.name] = list
			end
			table.insert(list, cfv)
			return false
		end
		local dupes = 0
		for _, rec in ipairs(raftData.placed) do
			if type(rec.name) == "string" and not rec.fixed and isDuplicate(rec) then
				dupes += 1
				continue
			end
			if rec.fixed then
				if moveFixed(rec) then placedN += 1 else missing[#missing + 1] = tostring(rec.name) .. "(карта)" end
				continue
			end
			local template = type(rec.name) == "string" and templateFor(rec.name) or nil
			if not template then
				missing[#missing + 1] = tostring(rec.name)
			else
				local clone = template:Clone()
				clone.Name = rec.name
				-- скрипты шаблонов на плоту не нужны: ими управляют серверные системы
				for _, d in ipairs(clone:GetDescendants()) do
					if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
				end
				if type(rec.attrs) == "table" then
					for k, v in pairs(rec.attrs) do pcall(function() clone:SetAttribute(k, v) end) end
					local len = tonumber(rec.attrs.SavedRopeLength)
					local rope = len and clone:IsA("Model") and clone:FindFirstChildWhichIsA("RopeConstraint", true) or nil
					if rope then rope.Length = len end
				end
				-- УКРЕПЛЁННЫЙ ПОЛ: метка приехала атрибутом, а меш с текстурой — нет:
				-- такой пол грузился обычным на вид. apply йилдит (грузит ассет) —
				-- отдельным потоком, как в старом пути загрузки.
				if rec.attrs and rec.attrs.TileKind == RaftReinforce.KIND then
					task.spawn(function() RaftReinforce.apply(clone) end)
				end
				local worldCF = rest:ToWorldSpace(deserializeCFrame(rec.cf))
				if rec.ri ~= nil then
					moveByRef(clone, rec.ri, worldCF, rec.rp)   -- по опорной детали (новый формат)
				elseif clone:IsA("Model") then
					if rec.box then
						local cb = clone:GetBoundingBox()
						clone:PivotTo(worldCF * cb:ToObjectSpace(clone:GetPivot()))
					else
						clone:PivotTo(worldCF)
					end
				else
					clone.CFrame = worldCF
				end
				clone.Parent = raft
				do -- факт: где опорная деталь оказалась (в тех же осях, что при сборе)
					local ref = (type(rec.rp) == "string" and clone:IsA("Model")) and byPath(clone, rec.rp) or refPartByIndex(clone, rec.ri or 1)
					if ref then
						local got = rest:ToObjectSpace(ref.CFrame)
						local want = deserializeCFrame(rec.cf)
						local gx, gy, gz = got:ToEulerAnglesYXZ()
						local wx, wy, wz = want:ToEulerAnglesYXZ()
						print(("[RaftSave/загрузка 1в1] %s [%s] хотели (%.1f, %.1f, %.1f) euler (%.0f, %.0f, %.0f) → вышло (%.1f, %.1f, %.1f) euler (%.0f, %.0f, %.0f)")
							:format(rec.name, tostring(rec.rp), want.X, want.Y, want.Z, math.deg(wx), math.deg(wy), math.deg(wz), got.X, got.Y, got.Z, math.deg(gx), math.deg(gy), math.deg(gz)))
					end
				end
				weldAndUnanchor(clone)
				placedN += 1
			end
		end
		claimRaftForServer(raft, "после сейва 1в1")
		task.delay(20, function() if raft.Parent then reportStrayParts(raft, "20 с после загрузки") end end)
		print(("[RaftSave] сейв 1в1: поставлено %d, дублей пропущено %d, без шаблона: %s")
			:format(placedN, dupes, #missing > 0 and table.concat(missing, ", ") or "—"))
		-- рюкзак из старых сейвов (тогда он писался как постройка) — снести клон
		for _, child in ipairs(raft:GetChildren()) do
			if not MAP_FIXED[child] and child.Name:lower():find("backpack", 1, true) then child:Destroy() end
		end
		-- сеточный путь ниже — только для старых сейвов: здесь всё уже стоит
		raftData.floors, raftData.beams, raftData.wallPanels, raftData.wallArches = nil, nil, nil, nil
		raftData.edgeWalls, raftData.doors, raftData.walls, raftData.objects = nil, nil, nil, nil
	end

	-- Place floors (skip origin 0,0 which already exists)
	if floorTemplate and raftData.floors then
		for _, floor in raftData.floors do
			if not (floor.gx == 0 and floor.gz == 0) then
				local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(floor.gx * GRID_SIZE + phaseX, 0, floor.gz * GRID_SIZE + phaseZ))
					+ Vector3.new(0, tileY, 0) -- на уровень ЦЕНТРОВ геометрии досок
				local localOffset = restCF:VectorToObjectSpace(worldOffset)
				-- клетка = центр геометрии; пивот отводим на его смещение от центра
				-- как в стройке: поворот доски палубы, затем отвод пивота от центра
				local worldCF = raftCF * CFrame.new(localOffset) * tileRotFix * CFrame.new(-tilePivotDelta)

				-- СЕТЬ или доска: сеть берёт свой шаблон, свою ориентацию и НЕ
				-- масштабируется (Net_Part уже размером с тайл, доска — нет).
				local isNet = (floor.kind == "net") and netTemplate ~= nil
				local clone = (isNet and netTemplate or floorTemplate):Clone()
				-- ⚠️ ТЕ ЖЕ ДВЕ ПОПРАВКИ, ЧТО ПРИ ЖИВОЙ УСТАНОВКЕ: поворот (гасим поворот
				-- пивота модели) и центрирование (пивот не в центре геометрии, иначе
				-- сеть встаёт ниже настила). Масштаб сети не нужен — см. RaftNetFit.
				if isNet then
					local centerPos = (worldCF * CFrame.new(pivotCenterDelta(floorTemplate, TILE_SCALE))).Position
					worldCF = CFrame.new(centerPos) * (worldCF * NET_ROT_FIX).Rotation
						* CFrame.new(-pivotCenterDelta(netTemplate, 1))
				elseif clone:IsA("Model") and TILE_SCALE ~= 1 then
					clone:ScaleTo(TILE_SCALE) -- как живая установка (при 1 не трогаем)
				end
				if clone:IsA("Model") then clone:PivotTo(worldCF) else clone.CFrame = worldCF end
				do
					local c = clone:IsA("Model") and clone:GetBoundingBox().Position or clone.Position
					local lp = raftCF:PointToObjectSpace(c)
					print(("[RaftSave/загрузка] клетка gx=%s gz=%s kind=%s → центр в осях плота (%.1f, %.1f, %.1f)"):format(tostring(floor.gx), tostring(floor.gz), tostring(floor.kind), lp.X, lp.Y, lp.Z))
				end
				-- имя в мире не зависит от имени шаблона: по нему сеть узнают восемь
				-- систем, и старые сейвы должны грузиться так же (BuildingSystem.server)
				if isNet then clone.Name = NetFit.PLACED_NAME end
				clone:SetAttribute("GridX", floor.gx)
				clone:SetAttribute("GridZ", floor.gz)
				clone:SetAttribute("BuildType", "raft")
				if isNet then clone:SetAttribute("TileKind", "net") end
				clone.Parent = raft
				weldAndUnanchor(clone)
				-- УКРЕПЛЁННЫЙ ПОЛ: тайл тот же, отличается только меш с текстурой.
				-- apply йилдит (грузит ассет), поэтому отдельным потоком — иначе
				-- каждая укреплённая доска тормозила бы всю загрузку плота.
				if floor.kind == RaftReinforce.KIND then
					task.spawn(function() RaftReinforce.apply(clone) end)
				end
			end
		end
	end

	-- Place beams
	if beamTemplate and raftData.beams then
		for _, beam in raftData.beams do
			local insetX, insetZ = computeBeamInset(beam.cx, beam.cz)
			local studX = beam.cx * GRID_SIZE + insetX + 1
			local studZ = beam.cz * GRID_SIZE + insetZ
			local worldPos = localToWorldPos(studX, studZ)
			worldPos = worldPos + Vector3.new(0, BEAM_HEIGHT * BEAM_SCALE / 2, 0) -- как живая установка

			local bCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw, 0)
			local clone = beamTemplate:Clone()
			if clone:IsA("Model") then clone:ScaleTo(BEAM_SCALE) end -- как живая установка
			clone:SetAttribute("BuildType", "beam")
			clone:SetAttribute("BeamKey", string.format("%.1f_%.1f", beam.cx, beam.cz))
			clone:SetAttribute("CornerX", beam.cx)
			clone:SetAttribute("CornerZ", beam.cz)
			if clone:IsA("Model") then clone:PivotTo(bCF) else clone.CFrame = bCF end
			clone.Parent = raft
			weldAndUnanchor(clone)
		end
	end

	-- Helper to build the normalized span string used by both walls and arches
	local function spanKeyStr(cx1, cz1, cx2, cz2)
		local a1, b1, a2, b2 = cx1, cz1, cx2, cz2
		if a1 > a2 or (a1 == a2 and b1 > b2) then
			a1, b1, a2, b2 = a2, b2, a1, b1
		end
		return string.format("%.1f_%.1f_%.1f_%.1f", a1, b1, a2, b2)
	end

	-- Place wall panels
	if wallPanelTemplate and raftData.wallPanels then
		for _, wp in raftData.wallPanels do
			-- Балок нет: середина ребра прямо по сетке, стена — на верху настила
			local midStudX = (wp.cx1 + wp.cx2) / 2 * GRID_SIZE
			local midStudZ = (wp.cz1 + wp.cz2) / 2 * GRID_SIZE
			local worldPos = localToWorldPos(midStudX, midStudZ)
			worldPos = worldPos + Vector3.new(0, tileY + tileHalfY + PANEL_HEIGHT / 2 - WallDefs.SINK, 0)

			local sideAngle = (wp.cx1 == wp.cx2) and math.rad(90) or 0
			local wCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)

			local clone = wallPanelTemplate:Clone()
			local sk = spanKeyStr(wp.cx1, wp.cz1, wp.cx2, wp.cz2)
			clone:SetAttribute("BuildType", "wall_panel")
			clone:SetAttribute("WallPanelKey", "wp_" .. sk)
			clone:SetAttribute("WallSpanKey", sk)
			clone:SetAttribute("BeamCX1", wp.cx1)
			clone:SetAttribute("BeamCZ1", wp.cz1)
			clone:SetAttribute("BeamCX2", wp.cx2)
			clone:SetAttribute("BeamCZ2", wp.cz2)
			if clone:IsA("Model") then clone:PivotTo(WallDefs.pivotForCentre(clone, wCF)) else clone.CFrame = wCF end
			do
				local lc = raftCF:ToObjectSpace(clone:GetPivot())
				local _, wy = lc:ToEulerAnglesYXZ()
				print(("[RaftSave/загрузка] стена (%.1f,%.1f)-(%.1f,%.1f) sideAngle=%.0f restYaw=%.0f → в осях плота (%.1f, %.1f, %.1f) поворот %.0f°"):format(wp.cx1, wp.cz1, wp.cx2, wp.cz2, math.deg(sideAngle), math.deg(restYaw), lc.X, lc.Y, lc.Z, math.deg(wy)))
			end
			clone.Parent = raft
			weldAndUnanchor(clone)
		end
	end

	-- Place wall arches
	if wallArchTemplate and raftData.wallArches then
		for _, wa in raftData.wallArches do
			-- Балок нет: середина ребра прямо по сетке, стена — на верху настила
			local midStudX = (wa.cx1 + wa.cx2) / 2 * GRID_SIZE
			local midStudZ = (wa.cz1 + wa.cz2) / 2 * GRID_SIZE
			local worldPos = localToWorldPos(midStudX, midStudZ)
			worldPos = worldPos + Vector3.new(0, tileY + tileHalfY + ARCH_HEIGHT / 2 - WallDefs.SINK, 0)

			local sideAngle = (wa.cx1 == wa.cx2) and math.rad(90) or 0
			local aCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)

			local clone = wallArchTemplate:Clone()
			local sk = spanKeyStr(wa.cx1, wa.cz1, wa.cx2, wa.cz2)
			clone:SetAttribute("BuildType", "wall_arch")
			clone:SetAttribute("WallArchKey", "wa_" .. sk)
			clone:SetAttribute("WallSpanKey", sk)
			clone:SetAttribute("BeamCX1", wa.cx1)
			clone:SetAttribute("BeamCZ1", wa.cz1)
			clone:SetAttribute("BeamCX2", wa.cx2)
			clone:SetAttribute("BeamCZ2", wa.cz2)
			if clone:IsA("Model") then clone:PivotTo(WallDefs.pivotForCentre(clone, aCF)) else clone.CFrame = aCF end
			clone.Parent = raft
			weldAndUnanchor(clone)
		end
	end

	-- Варианты стен: окно, листва, ограда, полустена. Геометрия та же, что у
	-- глухой стены, различаются моделью и высотой — поэтому один цикл на все.
	if raftData.edgeWalls then
		for _, ew in raftData.edgeWalls do
			local template = findEdgeWallTemplate(ew.kind)
			if template then
				local h = WallDefs.heightOf(template)

				local midStudX = (ew.cx1 + ew.cx2) / 2 * GRID_SIZE
				local midStudZ = (ew.cz1 + ew.cz2) / 2 * GRID_SIZE
				local worldPos = localToWorldPos(midStudX, midStudZ)
				worldPos = worldPos + Vector3.new(0, tileY + tileHalfY + h / 2 - WallDefs.SINK, 0)

				local sideAngle = (ew.cx1 == ew.cx2) and math.rad(90) or 0
				local eCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)

				local clone = template:Clone()
				local sk = spanKeyStr(ew.cx1, ew.cz1, ew.cx2, ew.cz2)
				clone:SetAttribute("BuildType", ew.kind)
				clone:SetAttribute("WallSpanKey", sk)
				clone:SetAttribute("BeamCX1", ew.cx1)
				clone:SetAttribute("BeamCZ1", ew.cz1)
				clone:SetAttribute("BeamCX2", ew.cx2)
				clone:SetAttribute("BeamCZ2", ew.cz2)
				if clone:IsA("Model") then clone:PivotTo(WallDefs.pivotForCentre(clone, eCF)) else clone.CFrame = eCF end
				do
					local lc = raftCF:ToObjectSpace(clone:GetPivot())
					local _, wy = lc:ToEulerAnglesYXZ()
					print(("[RaftSave/загрузка] ограда %s (%.1f,%.1f)-(%.1f,%.1f) sideAngle=%.0f → в осях плота (%.1f, %.1f, %.1f) поворот %.0f°"):format(tostring(ew.kind), ew.cx1, ew.cz1, ew.cx2, ew.cz2, math.deg(sideAngle), lc.X, lc.Y, lc.Z, math.deg(wy)))
				end
				clone.Parent = raft
				weldAndUnanchor(clone)
			end
		end
	end

	-- Place doors (each door must correspond to a wall arch on the same span)
	if doorTemplate and raftData.doors then
		for _, dr in raftData.doors do
			-- Балок нет: середина ребра прямо по сетке, стена — на верху настила
			local midStudX = (dr.cx1 + dr.cx2) / 2 * GRID_SIZE
			local midStudZ = (dr.cz1 + dr.cz2) / 2 * GRID_SIZE
			local worldPos = localToWorldPos(midStudX, midStudZ)
			worldPos = worldPos + Vector3.new(0, tileY + tileHalfY + DOOR_HEIGHT / 2 - WallDefs.SINK, 0)

			local sideAngle = (dr.cx1 == dr.cx2) and math.rad(90) or 0
			local dCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)

			local clone = doorTemplate:Clone()
			local sk = spanKeyStr(dr.cx1, dr.cz1, dr.cx2, dr.cz2)
			clone:SetAttribute("BuildType", "door")
			clone:SetAttribute("DoorKey", "dr_" .. sk)
			clone:SetAttribute("BeamCX1", dr.cx1)
			clone:SetAttribute("BeamCZ1", dr.cz1)
			clone:SetAttribute("BeamCX2", dr.cx2)
			clone:SetAttribute("BeamCZ2", dr.cz2)
			if clone:IsA("Model") then clone:PivotTo(WallDefs.pivotForCentre(clone, dCF)) else clone.CFrame = dCF end
			clone.Parent = raft
			-- Route through DoorController so the restored door uses a
			-- Motor6D hinge instead of being rigidly welded.
			if _G.SetupDoor then
				_G.SetupDoor(clone, raft)
			else
				weldAndUnanchor(clone)
			end
		end
	end

	-- Place objects
	if raftData.objects then
		for _, obj in raftData.objects do
			local template = AssetFind.find(obj.name)
			if not template then
				-- Try common name variants
				if obj.name == "Purifier" then template = AssetFind.find("Destitalor") end
				-- Кровать сохраняется под именем "Bed", а модель у неё теперь другая
				-- (BedCrafting.BED_TEMPLATE). Без этой строки восстановленный плот
				-- оставался бы без кровати вовсе.
				if obj.name == "Bed" then template = AssetFind.find("Raft_bed_leaf") end
			end
			if template then
				local clone = template:Clone()
				local localCF = deserializeCFrame(obj.cf)
				local worldCF = raftCF * localCF

				if clone:IsA("Model") then
					if obj.pv then
						clone:PivotTo(worldCF)
					else
						-- старый сейв: cf — центр габаритного бокса; ставим клон так, чтобы
						-- его бокс совпал с сохранённым, а поворот берём у шаблона (стоит)
						local bb = clone:GetBoundingBox()
						local pivotFromBox = bb:ToObjectSpace(clone:GetPivot())
						local _, yaw = worldCF:ToEulerAnglesYXZ()
						local boxCF = CFrame.new(worldCF.Position) * CFrame.Angles(0, yaw, 0)
						clone:PivotTo(boxCF * pivotFromBox)
					end
				else
					clone.CFrame = worldCF
				end

				-- Restore attributes
				if obj.isGarden then
					clone:SetAttribute("IsGarden", true)
					clone:SetAttribute("IsWatered", obj.isWatered or false)
				end

				if obj.waterLevel then
					clone:SetAttribute("WaterLevel", obj.waterLevel)
					clone:SetAttribute("WaterType", obj.waterType or "none")
				end

				clone.Parent = raft
				weldAndUnanchor(clone)
			end
		end
	end

	print("[RaftSave] Rebuilt raft for " .. player.Name)
	markRaftReady("перестроен из сейва")
end

local function resetRaftToInitialPosition()
	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart or not INITIAL_RAFT_CFRAME then return end

	pivotRaftSafely(raft, INITIAL_RAFT_CFRAME, "сейва нет — старт с карты")
	raft.PrimaryPart:SetAttribute("RestCFrame", INITIAL_RAFT_CFRAME)
	local _, iy, _ = INITIAL_RAFT_CFRAME:ToEulerAnglesYXZ()
	raft.PrimaryPart:SetAttribute("RestYaw", iy)
	print("[RaftSave] Reset raft to initial map position")
end

-- ─── Restore inventory ───
local function restoreInventory(player, saveData)
	if not saveData or not saveData.inventory then return end

	local inv = _G.GetInventory and _G.GetInventory(player)
	if not inv then return end

	-- Only restore keys that already exist in the inventory table.
	-- _G.GetInventory() guarantees every known RESOURCE_NAMES key exists
	-- and strips any unknown keys, so this naturally rejects legacy/bad
	-- keys that would otherwise create invisible slots on the server
	-- (counted toward capacity but never rendered by the client).
	for key, value in saveData.inventory do
		if typeof(value) == "number" and inv[key] ~= nil then
			inv[key] = value
		end
	end

	if _G.SendInventory then
		_G.SendInventory(player)
	end

	print("[RaftSave] Restored inventory for " .. player.Name)
end

-- ─── Restore tools ───
local function restoreTools(player, saveData)
	if not saveData or not saveData.tools then return end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	-- Tools cloned from ReplicatedStorage templates
	local cloneableTools = {
		["Pick-Axe"] = true, ["Hammer"] = true, ["Axe"] = true,
		["Hook"] = true, ["Machete"] = true, ["Wooden_Spear"] = true,
		["Cup"] = true, ["Destitalor"] = true, ["Wood_Knife"] = true,
		["Stone_Axe"] = true, ["Fire_Axe"] = true,
	}

	-- Placeholder tools (placement items) — create a simple Tool with transparent Handle
	local placeholderTools = {
		["WorkBench"] = true, ["Garden"] = true, ["Bed_T"] = true,
		["Furnace"] = true, ["Bed"] = true, ["bush"] = true,
	}

	-- РАЗМЕЩАЕМОЕ ОРУЖИЕ: имя тула совпадает с именем МОДЕЛИ пушки в
	-- ReplicatedStorage, поэтому клонировать по имени НЕЛЬЗЯ — раньше сюда
	-- попадала ветка «unknown tool», она находила по имени целую модель турели
	-- и клонировала её в рюкзак; при экипировке модель вываливалась в мир у ног
	-- игрока без якорей и сварки — тот самый «пулемёт развалился на старте».
	-- Пересоздаём пустой размещаемый тул с иконкой (как CanonSystem при подборе).
	local placeableWeaponIcons = {
		["Cannon"]           = "rbxassetid://118236242385241",
		["Deffender"]        = "rbxassetid://86928740553428",
		["MagmaCannon"]      = "rbxassetid://97658619335375",
		["Big_Magma_Cannon"] = "rbxassetid://90669361199026",
		["Pulemet_lvl_1"]    = "rbxassetid://106277044945645",
		["Pulemet_lvl_2"]    = "rbxassetid://79105833790080",
	}
	local function makePlaceholderTool(toolName, icon)
		local tool = Instance.new("Tool")
		tool.Name = toolName
		tool.CanBeDropped = false
		if icon then tool.TextureId = icon end
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(1, 1, 1)
		handle.Transparency = 1
		handle.CanCollide = false
		handle.Parent = tool
		return tool
	end

	for _, toolName in saveData.tools do
		if placeableWeaponIcons[toolName] then
			local tool = makePlaceholderTool(toolName, placeableWeaponIcons[toolName])
			tool.Parent = backpack
			print("[RaftSave] Restored placeable weapon tool: " .. toolName)
		elseif cloneableTools[toolName] then
			local template = AssetFind.find(toolName)
			if template then
				local clone = template:Clone()
				clone.Parent = backpack
				print("[RaftSave] Restored tool: " .. toolName)
			else
				warn("[RaftSave] Tool template not found: " .. toolName)
			end
		elseif placeholderTools[toolName] then
			-- Recreate placeholder placement tool
			local tool = Instance.new("Tool")
			tool.Name = toolName
			tool.CanBeDropped = false
			tool.RequiresHandle = true
			local handle = Instance.new("Part")
			handle.Name = "Handle"
			handle.Size = Vector3.new(1, 1, 1)
			handle.Transparency = 1
			handle.CanCollide = false
			handle.Parent = tool
			tool.Parent = backpack
			print("[RaftSave] Restored placeholder tool: " .. toolName)
		else
			-- Unknown tool — клонируем из ReplicatedStorage ТОЛЬКО если это
			-- действительно Tool. Модель с совпавшим именем в рюкзак класть
			-- нельзя (см. placeableWeaponIcons выше) — вместо этого делаем
			-- пустой размещаемый тул, чтобы предмет не потерялся.
			local template = AssetFind.find(toolName)
			if template and template:IsA("Tool") then
				local clone = template:Clone()
				clone.Parent = backpack
				print("[RaftSave] Restored unknown tool: " .. toolName)
			elseif template then
				local tool = makePlaceholderTool(toolName, nil)
				tool.Parent = backpack
				warn("[RaftSave] Шаблон '" .. toolName .. "' — не Tool (" .. template.ClassName .. "), выдал пустой размещаемый тул")
			else
				warn("[RaftSave] Could not restore tool: " .. toolName)
			end
		end
	end

	local applied = applyToolState(player, saveData.toolsState)
	print("[RaftSave] Restored " .. #saveData.tools .. " tools for " .. player.Name .. " (состояние применено к " .. applied .. ")")
end

-- Track whether the raft has already been rebuilt from a save (for group loads)
local raftRebuiltFromSave = false

-- Per-player ownership tracking (only the owner gets raft data saved).
-- The local was forward-declared at the top of the file (T18) so
-- savePlayerData's upvalue resolves to the right slot.

-- ─── Load save data by UserId key ───
local function loadPlayerDataByUserId(userId, slot)
	if not raftStore then
		warn("[RaftSave] No DataStore, cannot load for userId " .. tostring(userId))
		return nil
	end
	local key = RaftShared.slotKey(userId, slot or 1)
	local success, data = pcall(function()
		return raftStore:GetAsync(key)
	end)

	if success and data then
		print("[RaftSave] Loaded save data for userId " .. tostring(userId))
		return data
	elseif not success then
		warn("[RaftSave] DataStore read failed for userId " .. tostring(userId) .. ": " .. tostring(data))
	end
	return nil
end

-- ─── On player join: check teleport data for load flag ───
Players.PlayerAdded:Connect(function(player)
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData
	if raftStore then
		task.spawn(function()
			local ok, rep = pcall(function() return raftStore:GetAsync("exitlog_" .. player.UserId) end)
			if ok and type(rep) == "table" then
				print(("[RaftSave] прошлый автосейв %s (%d с назад): %s"):format(player.Name, os.time() - (tonumber(rep.t) or os.time()), tostring(rep.text)))
			else
				print("[RaftSave] прошлый автосейв " .. player.Name .. ": отчёта нет")
			end
		end)
	end

	-- Сторож для экрана загрузки: что бы ни случилось с DataStore, клиент не ждёт
	-- отмашки дольше пятнадцати секунд. Ставится ДО чтения сейва — именно чтение
	-- и может подвиснуть на троттлинге.
	task.delay(15, function() markRaftReady("сторож: 15 с от входа") end)

	-- ДИАГНОСТИКА: что реально пришло в TeleportData. Если loadSave не
	-- true — телепорт был НЕ из меню сохранений (напр. старый per-room
	-- Script на паде шлёт «новую игру» без loadSave) → плот не грузится.
	if teleportData then
		print(string.format("[RaftSave] JOIN %s teleportData: loadSave=%s saveSlot=%s saveOwnerId=%s raftOwnerId=%s fromRoom=%s",
			player.Name, tostring(teleportData.loadSave), tostring(teleportData.saveSlot),
			tostring(teleportData.saveOwnerId), tostring(teleportData.raftOwnerId), tostring(teleportData.fromRoom)))
	else
		print("[RaftSave] JOIN " .. player.Name .. " — NO teleportData (прямой заход)")
		markRaftReady("прямой заход, сейв не грузим")
		-- сторож владения нужен и без сейва: любая новая сварка (лужа магмы,
		-- улов сети, постройка) может отдать плот клиенту
		do
			local raft = workspace:FindFirstChild("Raft")
			if raft and raft.PrimaryPart then startOwnerWatch(raft) end
		end
	end

	-- Determine if this player is the raft owner
	if teleportData and teleportData.raftOwnerId then
		playerIsRaftOwner[player] = (teleportData.raftOwnerId == player.UserId)
		--[[ ⚠️ ВЛАДЕЛЬЦА ПЛОТА ЗАПОМИНАЕМ ЗДЕСЬ, А НЕ В ВЕТКЕ ЗАГРУЗКИ.
		     Сначала я ставил его только там, где грузится сейв. Но гость чаще
		     всего приезжает в НОВУЮ игру друга: сейва ещё нет, ветка загрузки не
		     выполняется, владелец остаётся неизвестным — и на выходе вещи гостя
		     не сохранялись вовсе. Ровно это и увидели: у хозяина всё на месте, у
		     друга пустой инвентарь.
		     Владелец плота известен всегда — он приезжает в данных телепорта. ]]
		playerSaveOwner[player] = teleportData.raftOwnerId
		print("[RaftSave] Player " .. player.Name .. " isRaftOwner: " .. tostring(playerIsRaftOwner[player]) .. " (ownerId=" .. tostring(teleportData.raftOwnerId) .. ")")
	else
		-- No teleport data (direct join or testing) — treat as owner
		playerIsRaftOwner[player] = true
	end

	-- Активный слот сейва (какой слот владельца грузим/пишем)
	local saveSlot = math.clamp(math.floor(tonumber(teleportData and teleportData.saveSlot) or 1), 1, RaftShared.MAX_SLOTS)
	playerActiveSlot[player] = saveSlot

	--[[ ГОСТЬ ВЕРНУЛСЯ В ИГРУ ДРУГА БЕЗ ЗАГРУЗКИ СЕЙВА (хозяин продолжает
	     текущую игру). Его вещи лежат в своём ключе по владельцу и слоту —
	     достаём их и здесь, иначе он входит с пустыми руками. ]]
	if teleportData and not teleportData.loadSave and playerIsRaftOwner[player] == false and teleportData.raftOwnerId then
		local ownerId = teleportData.raftOwnerId
		task.spawn(function()
			task.wait(1)
			local key = guestKey(player.UserId, ownerId, saveSlot)
			local ok, guestData = pcall(function() return raftStore:GetAsync(key) end)
			if not ok then
				guestLoadFailed[player] = true
				warn(("[RaftSave] Гость %s: вещи не загрузились (без сейва) — %s"):format(player.Name, tostring(guestData)))
				return
			end
			if type(guestData) ~= "table" or not player.Parent then
				print(("[RaftSave] Гость %s: вещей по ключу %s нет — начинает с пустыми"):format(player.Name, key))
				return
			end
			-- новая игра хозяина (сейв не грузили): вещи из ПРОШЛОЙ игры не отдаём
			if guestData.session ~= SESSION_ID then
				print(("[RaftSave] Гость %s: вещи по ключу %s из другой игры — новая игра, начинает с пустыми"):format(player.Name, key))
				return
			end
			restoreInventory(player, guestData)
			restoreTools(player, guestData)
			restoreExtras(player, guestData.extra, false)
			if guestData.hasBackpack then player:SetAttribute("HasBackpack", true) end
			if guestData.slotLayout and next(guestData.slotLayout) then
				cachedSlotLayouts[player] = guestData.slotLayout
				task.wait(0.5)
				slotLayoutEvent:FireClient(player, "restore", guestData.slotLayout)
			end
			print(("[RaftSave] Гость %s: вещи восстановлены без загрузки сейва (плот %d, слот %d)"):format(player.Name, ownerId, saveSlot))
		end)
	end

	if teleportData and teleportData.loadSave then
		-- Determine whose save to load
		local saveOwnerId = teleportData.saveOwnerId
		local isOwner = (not saveOwnerId) or (saveOwnerId == player.UserId)
		-- уточняем: грузим сейв конкретного игрока, вещи гостя привяжем к нему
		playerSaveOwner[player] = saveOwnerId or teleportData.raftOwnerId or player.UserId
		sessionSlot = sessionSlot or saveSlot

		print("[RaftSave] Player " .. player.Name .. " loading save (owner: " .. tostring(saveOwnerId or player.UserId) .. ", isOwner: " .. tostring(isOwner) .. ", slot: " .. saveSlot .. ")")

		-- Load save data (owner's save for group, or own save for solo)
		local saveData
		if saveOwnerId and saveOwnerId ~= player.UserId then
			saveData = loadPlayerDataByUserId(saveOwnerId, saveSlot)
		else
			saveData = loadPlayerData(player)
		end

		--[[ Сейв просили, но его нет — ставим плот на стартовую точку карты, а не
		     оставляем как есть.
		     ⚠️ РОВНО ОДИН РАЗ ЗА СЕССИЮ, И ЭТО ВТОРАЯ ПОЛОВИНА ИСТОРИИ СО СТОЛОМ.
		     Проверка стояла без всякой защиты и срабатывала на КАЖДОМ входе. Плот
		     всё время плывёт вперёд, поэтому второй игрок, чьё чтение DataStore
		     не удалось (а вдвоём запросов вдвое больше, и троттлинг реален),
		     телепортировал плот назад к точке рождения посреди игры — со всем
		     незакреплённым добром на палубе.
		     Смысл у сброса ровно один: поставить плот ДО начала игры. Если он уже
		     поставлен — трогать его нельзя ни под каким предлогом. Отдельный флаг
		     нужен именно свой: raftRebuiltFromSave поднимать здесь нельзя, иначе
		     сейв хозяина, приехавшего вторым, уже не поднимется. ]]
		if not saveData and not raftPlaced then
			resetRaftToInitialPosition()
		elseif not saveData then
			print("[RaftSave] " .. player.Name .. ": сейва нет, но плот уже стоит — не двигаю")
		end
		if not saveData then markRaftReady("сейв не загрузился") end

		--[[ ⚠️ «РЮКЗАК РАЗОБРАН» ПОДНИМАЕМ СРАЗУ, А НЕ ПОСЛЕ ОЖИДАНИЯ ПЕРСОНАЖА.
		     Флаг стоял ниже, в ветке восстановления вещей — за task.wait(1) и
		     ожиданием спавна. Всю эту секунду плот считался неразобранным, и
		     добежавший до рюкзака гость получал второй комплект оружия в игре,
		     где рюкзак давно вскрыт. Знание приходит вместе с сейвом — значит и
		     применять его надо тем же кадром. ]]
		if isOwner and saveData and type(saveData.backpackTakenBy) == "string" then
			workspace:SetAttribute("BackpackTakenBy", saveData.backpackTakenBy)
		elseif isOwner and saveData and (saveData.backpackTaken or saveData.hasBackpack) then
			-- старый сейв без списка: комплект точно получал хозяин
			workspace:SetAttribute("BackpackTakenBy", tostring(player.UserId))
		end
		if isOwner and saveData and (saveData.backpackTaken or saveData.hasBackpack) then
			workspace:SetAttribute("BackpackTaken", true)
			-- владельцу — личный флаг: по нему клиент прячет модель рюкзака на плоту
			-- (гость без флага рюкзак видит и может «подобрать», вещей второй раз не будет)
			player:SetAttribute("HasBackpack", true)
			print("[RaftSave] Плот помним разобранным: второй комплект из рюкзака не выйдет")
		end

		--[[ ⚠️ СИЛУ ВОССТАНАВЛИВАЕМ ВЛАДЕЛЬЦУ СЕЙВА, А НЕ ПЕРВОМУ ВОШЕДШЕМУ.
		     Сначала я поставил это в ветку «первый игрок поднял плот» — она
		     выполняется один раз на сервер, и в компании владелец, зашедший
		     вторым, остался бы без своей прокачки, а поднявший плот гость
		     получил бы её вместо него.
		     Сила персональная: в чужом сейве она не наследуется — гость качает
		     свою. Поэтому условие простое: это моя игра, и в ней есть сила. ]]
		if isOwner and saveData and _G.ApplyStrengthSave
			and type(saveData.strength) == "table" then
			pcall(_G.ApplyStrengthSave, player, saveData.strength)
		end

		-- Свой сейв — продолжение того же забега: прожитые дни не начинаются
		-- заново. Чужой (гость на чужом плоту) — начинаются: чужие дни в его
		-- рекорд не переезжают.
		if isOwner and type(saveData) == "table" and _G.SetRunDaysBase then
			pcall(_G.SetRunDaysBase, player, saveData.daysSurvived)
		end

		-- Rebuild raft only once (the first player to join triggers it)
		if saveData and not raftRebuiltFromSave then
			raftRebuiltFromSave = true
			rebuildRaft(player, saveData)

			-- Восстановление статуса монолита — серверно-общее, ОДИН раз на
			-- сервер. Монолит и DiverShop поднимаются асинхронно, поэтому
			-- ждём готовности глобалов, потом применяем: сначала «починен»
			-- (чтобы разбудить дайвера), затем уровни улучшений.
			--[[ Механик: если в сейве он уже разбужен, будим без сцены и диалога —
			     сразу на дежурство. Ручку даёт EngineerSystem, он поднимается
			     асинхронно, поэтому ждём. ]]
			local wokeDay = tonumber(saveData.engineerWokeDay)
			if wokeDay then
				task.spawn(function()
					for _ = 1, 60 do
						if typeof(_G.RestoreEngineerAwake) == "function" then break end
						task.wait(0.5)
					end
					if typeof(_G.RestoreEngineerAwake) == "function" then
						local ok, err = pcall(_G.RestoreEngineerAwake, wokeDay)
						print("[RaftSave] механик из сейва: " .. (ok and "разбужен" or ("ошибка " .. tostring(err))))
					else
						warn("[RaftSave] _G.RestoreEngineerAwake не появился — механик останется спать")
					end
				end)
			end
			if saveData.world and isOwner then restoreWorldData(player, saveData.world) end
			local mono = saveData.monolith
			if type(mono) == "table" then
				task.spawn(function()
					for _ = 1, 60 do -- до ~30с ожидания готовности
						if _G.GetMonolith and _G.GetMonolith() then break end
						task.wait(0.5)
					end
					if mono.repaired and _G.RestoreMonolithRepaired then
						pcall(_G.RestoreMonolithRepaired)
					end
					if mono.levels and _G.RestoreMonolithUpgrades then
						pcall(_G.RestoreMonolithUpgrades, mono.levels)
					end
					print("[RaftSave] Monolith state restored (repaired=" .. tostring(mono.repaired) .. ")")
				end)
			end
		end

		-- Второй и следующий игрок: плот подняли до нас, ждать ему нечего.
		markRaftReady("плот уже собран")

		-- Wait for character to spawn, then move to raft
		local char = player.Character or player.CharacterAdded:Wait()
		local hrp = char:WaitForChild("HumanoidRootPart", 10)

		local raft = workspace:FindFirstChild("Raft")
		if hrp and raft and raft.PrimaryPart then
			--[[ ⚠️ БЕРЁМ ТОЧКУ, А НЕ ЦЕЛЫЙ CFrame ПЛОТА — ИНАЧЕ ИГРОК ЛОЖИТСЯ.
			     Здесь стояло `raft.PrimaryPart.CFrame + Vector3.new(0, 5, 0)`.
			     Сложение с вектором сдвигает точку, но СОХРАНЯЕТ ПОВОРОТ, а
			     PrimaryPart плота — это SpawnLocation, лежащий плашмя: в его
			     повороте зашит тангаж 90°. Персонаж получал этот тангаж целиком
			     и появлялся лёжа лицом в палубу — ровно та жалоба «иногда
			     спавнит игрока в лежачем состоянии», и «иногда» здесь означает
			     «когда грузится сохранение».
			     Ставим вертикально и с ходом плота: без скорости палуба уедет
			     из-под ног следующим же кадром (см. SpawnOnRaft). ]]
			local pp = raft.PrimaryPart
			local target = pp.Position + Vector3.new(0, 5, 0)
			local look = hrp.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude < 0.05 then flat = Vector3.new(0, 0, -1) end
			hrp.CFrame = CFrame.lookAt(target, target + flat.Unit)
			hrp.AssemblyLinearVelocity = pp.AssemblyLinearVelocity
			print("[RaftSave] Moved " .. player.Name .. " to saved raft")
		end

		--[[ ⚠️ ГОСТЮ ВОЗВРАЩАЕМ ЕГО СОБСТВЕННЫЕ ВЕЩИ, А НЕ ХОЗЯЙСКИЕ.
		     Инвентарь владельца гостю отдавать нельзя — это дубликат добра на
		     ровном месте. Но и с пустыми руками начинать нечестно: он уже играл
		     в этой самой игре, и его вещи лежат в своём гостевом ключе.
		     Плот при этом остаётся хозяйский — гость его не сохраняет и не
		     восстанавливает, здесь только инвентарь, инструменты и раскладка. ]]
		--[[ ⚠️ ВЕЩИ ГОСТЯ НЕ ЗАВИСЯТ ОТ ТОГО, ПОДНЯЛСЯ ЛИ ПЛОТ ХОЗЯИНА.
		     Здесь стояло ещё и условие `saveData` — сейв владельца в этом слоте.
		     Но лежат вещи гостя в СВОЁМ ключе, к хозяйскому сейву отношения не
		     имеют, и одна неудачная выдача DataStore по чужому ключу оставляла
		     друга с пустыми руками на ровном месте. Достаточно знать, чей это
		     плот. ]]
		if not isOwner and saveOwnerId then
			task.spawn(function()
				task.wait(1)
				local key = guestKey(player.UserId, saveOwnerId, saveSlot)
				local ok, guestData = pcall(function() return raftStore:GetAsync(key) end)
				if not ok then
					-- запрещаем запись до конца сессии: см. guestLoadFailed
					guestLoadFailed[player] = true
					warn(("[RaftSave] Гость %s: вещи не загрузились — %s (сохранение вещей отключено, чтобы не затереть их пустотой)")
						:format(player.Name, tostring(guestData)))
					return
				end
				if type(guestData) ~= "table" or not player.Parent then
					print(("[RaftSave] Гость %s: вещей по ключу %s нет"):format(player.Name, key))
					return
				end

				restoreInventory(player, guestData)
				restoreTools(player, guestData)
				restoreExtras(player, guestData.extra, false)
				if guestData.hasBackpack then
					player:SetAttribute("HasBackpack", true)
				end
				--[[ ⚠️ ПЕРВЫМ АРГУМЕНТОМ ИДЁТ ДЕЙСТВИЕ, А НЕ САМА РАСКЛАДКА.
				     Клиент читает (action, layout) и ждёт action == "restore"
				     (InventoryUI). Раскладка, отправленная первым аргументом,
				     молча пропадала: у владельца строкой ниже всё правильно, у
				     гостя предметы каждый раз раскладывались заново. ]]
				if guestData.slotLayout and next(guestData.slotLayout) then
					cachedSlotLayouts[player] = guestData.slotLayout
					task.wait(0.5)
					slotLayoutEvent:FireClient(player, "restore", guestData.slotLayout)
				end
				print(("[RaftSave] Гость %s: вещи восстановлены (плот %d, слот %d)")
					:format(player.Name, saveOwnerId, saveSlot))
			end)
		end

		-- Restore inventory and tools only for the save owner (or solo player)
		if saveData and isOwner then
			task.wait(1)
			restoreInventory(player, saveData)
			restoreTools(player, saveData)
			restoreExtras(player, saveData.extra, true)

			-- рюкзак уже подобран → снимаем гейт инвентаря (промпт на
			-- статичной модели сам заглушится, клиент скроет модель)
			if saveData.hasBackpack then
				player:SetAttribute("HasBackpack", true)
			end

			-- Send saved slot layout to client AND pre-populate the
			-- server cache so capacity checks work immediately (before
			-- the client round-trips the layout back via FireServer).
			if saveData.slotLayout and next(saveData.slotLayout) then
				cachedSlotLayouts[player] = saveData.slotLayout
				task.wait(0.5)
				slotLayoutEvent:FireClient(player, "restore", saveData.slotLayout)
				print("[RaftSave] Sent slot layout to " .. player.Name)
			end
		end
	end
	--[[ Отмашка «сейв забега к игроку применён» (во всех исходах: сейва нет,
	     новая игра, гость). Её ждёт выдача наград ежедневки (PirateProgression):
	     команда жителей приезжает из сейва и ЗАМЕНЯЕТ текущую — Роза, выданная
	     раньше, пропала бы. ]]
	player:SetAttribute("RaftSaveApplied", true)
end)

-- ─── Ручное сохранение (кнопка в игре) ───
-- Клиент шлёт "ManualRaftSave"; сервер сохраняет активный слот и
-- отвечает FireClient(player, ok) для UI. Дебаунс 3с на игрока.
local manualSaveEvent = Instance.new("RemoteEvent")
manualSaveEvent.Name = "ManualRaftSave"
manualSaveEvent.Parent = ReplicatedStorage

local lastManualSave = {} -- [player] = os.clock()
manualSaveEvent.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if lastManualSave[player] and now - lastManualSave[player] < 3 then
		manualSaveEvent:FireClient(player, false, "Подожди…")
		return
	end
	lastManualSave[player] = now
	if _G.__RaftSaveDisabled then
		manualSaveEvent:FireClient(player, false, "Сохранение недоступно")
		return
	end
	local ok = savePlayerData(player)

	--[[ ⚠️ РУЧНОЕ СОХРАНЕНИЕ СНИМАЕТ И ВЕЩИ ДРУЗЕЙ, ИНАЧЕ СЛОТ НЕПОЛНЫЙ.
	     Кнопка сохраняла только того, кто её нажал. Хозяин жал «сохранить» в
	     слот 1, плот туда ложился, а вещи гостей — нет; вернувшись в этот слот,
	     компания находила плот на месте и друга с пустыми руками. Слот — это
	     снимок ИГРЫ, а не одного игрока: раз пишем плот, пишем и тех, кто на нём
	     живёт, тем же числом слота. ]]
	if ok and playerIsRaftOwner[player] ~= false then
		local slot = playerActiveSlot[player] or 1
		for _, other in Players:GetPlayers() do
			if other ~= player and playerIsRaftOwner[other] == false then
				task.spawn(savePlayerData, other, slot)
			end
		end
	end

	if ok then
		manualSaveEvent:FireClient(player, true)
	else
		manualSaveEvent:FireClient(player, false, "Не удалось сохранить")
	end
end)

-- ─── Save on player leaving ─── (автосейв → слот «АВТО»)
Players.PlayerRemoving:Connect(function(player)
	print("[RaftSave] PlayerRemoving → автосейв " .. player.Name .. " в слот АВТО (" .. tostring(RaftShared.AUTO_SLOT) .. ")")
	local ok = savePlayerData(player, RaftShared.AUTO_SLOT)
	print("[RaftSave] PlayerRemoving автосейв " .. player.Name .. " результат: " .. tostring(ok))
	cachedSlotLayouts[player] = nil
	playerIsRaftOwner[player] = nil
	playerSaveOwner[player] = nil
	playerActiveSlot[player] = nil
	guestLoadFailed[player] = nil
	lastManualSave[player] = nil
end)

-- ─── Autosave ───
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		if not _G.__RaftSaveDisabled then
			for _, player in Players:GetPlayers() do
				task.spawn(savePlayerData, player, RaftShared.AUTO_SLOT)
			end
		end
	end
end)

-- ─── Save on server shutdown ─── (автосейв → слот «АВТО»)
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		savePlayerData(player, RaftShared.AUTO_SLOT)
	end
end)