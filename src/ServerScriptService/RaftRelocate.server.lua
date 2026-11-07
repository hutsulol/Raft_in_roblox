-- RaftRelocate.server.lua
-- ПЕРЕНОС ТОТЕМА ВОДОЛАЗОВ И РЕМОНТНОЙ СТАНЦИИ — по схеме пушек и факелов:
--   подошёл → в углу появилась кнопка с ценой → клик списывает пиратов, объект
--   уходит с плота и превращается в предмет в инвентаре → достал предмет,
--   навёл призрак, кликнул — объект встал на новое место.
--
-- ВАЖНО: объект НЕ пересоздаётся из шаблона, а прячется на складе и
-- возвращается тем же самым инстансом. Тотем несёт состояние (починен ли он,
-- уровни улучшений дайверов), и клон из шаблона это состояние потерял бы —
-- игрок заплатил бы за перенос и получил обратно сломанный монолит.
--
-- Если игрок вышел с «предметом» в руках, объект возвращается на плот, а не
-- пропадает вместе с ним.

local RaftShake = require(game:GetService("ReplicatedStorage"):WaitForChild("RaftShake"))   -- постройка без рывка плота
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LOG_TAG = "[RaftRelocate]"

-- Что переносим и почём (монеты «Пираты»).
-- icon — картинка кнопки переноса (как у факела) и предмета в инвентаре
local MOVABLE = {
	Monolit_Aquamen     = { price = 150, label = "Тотем водолазов",   icon = "rbxassetid://101627643091058" },
	Raft_repair_station = { price = 100, label = "Ремонтная станция", icon = "rbxassetid://101982188096798" },
	-- бак с нефтью: объект переносится тем же инстансом, запас нефти (атрибут) остаётся
	OilBarrel_SCENE     = { price = 80,  label = "Бочка с нефтью",    icon = "rbxassetid://119117779885584" },
}
local function specFor(nameOrModel)
	local n = typeof(nameOrModel) == "Instance" and nameOrModel.Name or tostring(nameOrModel)
	n = n:lower()
	for key, spec in pairs(MOVABLE) do
		if n == key:lower() then return spec, key end
	end
	return nil
end

local evt = ReplicatedStorage:FindFirstChild("RaftRelocate")
if not evt then
	evt = Instance.new("RemoteEvent")
	evt.Name = "RaftRelocate"
	evt.Parent = ReplicatedStorage
end

-- Склад «в руках»: сюда уезжает поднятый объект вместе со всем состоянием.
--
-- Лежит он в ReplicatedStorage, а НЕ в ServerStorage, намеренно: клиенту нужно
-- показать призрак того, что он несёт, а склонировать он может только то, что
-- видит. Шаблона монолита в ReplicatedStorage нет, поэтому призрак строить было
-- не из чего — и предмет становилось невозможно поставить вообще.
-- ReplicatedStorage не рендерится, так что «в мире» объект при этом не виден.
local stashFolder = ReplicatedStorage:FindFirstChild("RelocateStash")
if not stashFolder then
	stashFolder = Instance.new("Folder")
	stashFolder.Name = "RelocateStash"
	stashFolder.Parent = ReplicatedStorage
end

local stash = {}   -- [player] = Model
local busy  = {}   -- защита от двойного клика

local function raft() return workspace:FindFirstChild("Raft") end

-- ПИВОТ → ЦЕНТР ГАБАРИТОВ.
--
-- PivotTo двигает ПИВОТ модели, а не её геометрию. У модели без PrimaryPart пивот
-- — это WorldPivot, и в Studio он сплошь и рядом остаётся в нуле мира или сбоку от
-- меша. Тогда PivotTo(worldCF) ставит в точку клика ПУСТОЕ МЕСТО, а сам тотем
-- уезжает на то же смещение в сторону — игрок платит, предмет из рук пропадает, а
-- на плоту ничего не появляется. Ровно это и есть «поставил, но не поставилось».
--
-- Клиент точно так же нормализует пивот у призрака (createGhost), поэтому без этой
-- строки предпросмотр и результат считались бы по РАЗНЫМ точкам отсчёта. Условие
-- «нет PrimaryPart» здесь и там обязано совпадать.
--[[ ⚠️ ГОРИЗОНТАЛЬНЫЙ ПОВОРОТ ПЛОТА, А НЕ ВЕСЬ ЕГО CFrame.
     PrimaryPart плота — SpawnLocation, лежащий плашмя: его собственный поворот
     содержит тангаж 90°, и локальная ось Y смотрит вбок. Поставить объект
     «по плоту», умножив на этот CFrame, значит положить объект на бок — ровно
     это и происходило с ремонтной станцией при входе в игру.
     Берём только рыскание. Сначала спрашиваем RestYaw (его пишет BoatMovement и
     считает честно, целым CFrame), а если атрибута ещё нет — раскладываем сами,
     но не через ToEulerAngles: у повёрнутого на 90° парта разложение вырождено,
     рыскание и крен становятся неразличимы. Горизонтальная проекция «вперёд»
     такой особенности не имеет; если и она выродилась — берём «вправо». ]]
local function raftYaw(raft)
	local pp = raft and raft.PrimaryPart
	if not pp then return 0 end

	local rest = pp:GetAttribute("RestYaw")
	if typeof(rest) == "number" then return rest end

	local look = pp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then
		local right = pp.CFrame.RightVector
		flat = Vector3.new(right.X, 0, right.Z)
	end
	if flat.Magnitude < 0.05 then return 0 end
	flat = flat.Unit
	-- у CFrame.Angles(0, y, 0) LookVector = (-sin y, 0, -cos y)
	return math.atan2(-flat.X, -flat.Z)
end

-- Поставить объект в точку, стоя ровно: высота — мировая, поворот — только по плоту.
local function flatCF(pos, raft)
	return CFrame.new(pos) * CFrame.Angles(0, raftYaw(raft), 0)
end

local function normalizePivot(model)
	if not model:IsA("Model") or model.PrimaryPart then return end
	local bb = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(bb.Position)
end

--[[ ⚠️ ЭТАЛОННУЮ ПОЗУ СНИМАЕМ С КАРТЫ, ПОКА ФИЗИКА ЕЁ НЕ ИСПОРТИЛА.
     «Поставить ровно» нельзя вычислить: у ремонтной станции своя авторская
     осевая система, и любой придуманный нами «ровный» поворот — угадывание.
     Ровно так и вышло с flatCF: он задаёт нулевые тангаж и крен, то есть ту же
     самую позу, что и голый CFrame.new(), и от заваливания не спасает вовсе.
     Зато правильная поза УЖЕ ЕСТЬ — она лежит в карте. Снимаем её в первые
     кадры сервера, до того как плот тронется, и храним относительно плота:
     дальше её можно вернуть в любой момент и при любой качке. ]]
--[[ ⚠️ ОБЫЧНАЯ ТАБЛИЦА, А НЕ СЛАБАЯ — И ЭТО НЕ НЕБРЕЖНОСТЬ.
     Здесь стояло `setmetatable({}, { __mode = "k" })` «чтобы удалённая модель
     уносила запись с собой», и это была ошибка с прямыми последствиями: в
     Roblox ссылка на Instance из Lua — обёртка, и сборщик мусора вправе снять
     её, пока на неё никто не смотрит из кода, ХОТЯ САМ ОБЪЕКТ ЖИВ И СТОИТ НА
     ПЛОТУ. Эталон исчезал молча, сторож переставал видеть «где должно быть», и
     ниже срабатывал запасной путь — «положить в центр палубы». Станция и тотем
     уезжали с места на ровном месте.
     Моделей тут две, живут они всю сессию — держать их сильной ссылкой ничего
     не стоит. Запись убираем явно, когда модель уничтожают. ]]
local restRel = {}   -- [model] = { part, cf }

local function refPart(model)
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function captureRest(model, r)
	local pp = r and r.PrimaryPart
	local ref = model and model.Parent and refPart(model)
	if not (pp and ref) then return false end
	if restRel[model] == nil then
		-- запись держит модель сильной ссылкой: снимаем её сами, когда объект
		-- уничтожают, иначе таблица переживёт сам объект
		model.Destroying:Connect(function() restRel[model] = nil end)
	end
	restRel[model] = { part = ref, cf = pp.CFrame:ToObjectSpace(ref.CFrame) }
	return true
end

-- Загрузчик сейва подвинул постройку туда, где её оставил игрок: эталон —
-- заново, иначе сторож вернул бы её на место из карты.
_G.RaftRelocateRecapture = function(model)
	local r = raft()
	if r and model and specFor(model) then captureRest(model, r) end
end

--[[ Вернуть объект в эталонную позу.
     ⚠️ ДВИГАЕМ РАЗНИЦЕЙ, А НЕ ПИВОТОМ. У модели без PrimaryPart WorldPivot не
     следует за деталями: физика повалила модель — пивот остался стоять ровно, и
     PivotTo(ровно) вернёт лежащую модель лежащей, только в другом месте. Поэтому
     считаем, каким преобразованием опорная деталь попадёт туда, где стояла, и
     этим же преобразованием двигаем модель целиком — поза восстанавливается
     точно, вместе с поворотом. ]]
local function restoreRest(model, r)
	local rel = restRel[model]
	local pp = r and r.PrimaryPart
	if not (rel and pp and rel.part.Parent) then return false end
	local want  = pp.CFrame:ToWorldSpace(rel.cf)
	local delta = want * rel.part.CFrame:Inverse()
	model:PivotTo(delta * model:GetPivot())
	return true
end

-- Насколько объект ушёл от эталона: наклон в градусах и снос в студах.
-- Качка не мешает: и текущая поза, и эталон меряются относительно самого плота.
local function restDrift(model, r)
	local rel = restRel[model]
	local pp = r and r.PrimaryPart
	if not (rel and pp and rel.part.Parent) then return nil end
	local cur = pp.CFrame:ToObjectSpace(rel.part.CFrame)
	local dot = math.clamp(cur.UpVector:Dot(rel.cf.UpVector), -1, 1)
	return math.deg(math.acos(dot)), (cur.Position - rel.cf.Position).Magnitude
end

local function makeTool(key, spec)
	local tool = Instance.new("Tool")
	tool.Name = key
	tool.CanBeDropped = false
	tool:SetAttribute("RelocateItem", true)
	-- в хотбаре — иконка объекта, а не голое имя
	if spec and spec.icon then tool.TextureId = spec.icon end
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Parent = tool
	return tool
end

-- Снять со всех деталей модели сварки, ведущие НАРУЖУ (к плоту).
local function cutExternalWelds(model, scope)
	local inModel = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then inModel[d] = true end
	end
	for _, d in ipairs(scope:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Snap") then
			local a = d.Part0 and inModel[d.Part0]
			local b = d.Part1 and inModel[d.Part1]
			if (a or b) and not (a and b) then d:Destroy() end
		end
	end
end

local function weldToRaft(model, r)
	local primary = r.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	for _, p in ipairs(parts) do p.Anchored = true end
	for _, p in ipairs(parts) do
		p.Massless = true   -- без массы: иначе сборка теряет ход (рывок плота)
		local w = Instance.new("WeldConstraint")
		w.Name = "RaftStaticWeld"
		w.Part0, w.Part1 = primary, p
		w.Parent = p
	end
	for _, p in ipairs(parts) do
		p.Anchored = false
		pcall(function() p:SetNetworkOwner(nil) end)
	end
	primary.AssemblyLinearVelocity  = linVel
	primary.AssemblyAngularVelocity = angVel
	RaftShake.notify()   -- скорость ещё раз после шага физики + удержать игроков (RaftShake)
end

-- Вернуть спрятанный объект на плот (выход игрока, потеря тула и т.п.).
local function restoreFromStash(player, atCF)
	local model = stash[player]
	stash[player] = nil
	if not model or not model.Parent then return end
	local r = raft()
	if not r or not r.PrimaryPart then
		model:Destroy()
		return
	end
	model.Parent = r
	--[[ Если у объекта есть эталонная поза (а она есть у всего, что стояло на
	     карте, и у всего, что игрок сам ставил), возвращаем ровно её: и точку, и
	     поворот. Придумывать позу заново незачем — она известна. ]]
	if not atCF and restoreRest(model, r) then
		weldToRaft(model, r)
		return
	end
	normalizePivot(model)
	--[[ ⚠️ «НА ШЕСТЬ СТУДОВ ВЫШЕ» СЧИТАЕМ В МИРЕ, А НЕ В ОСЯХ ПЛОТА.
	     Было `r.PrimaryPart.CFrame * CFrame.new(0, 6, 0)`: у повёрнутого
	     PrimaryPart локальный Y смотрит вбок, поэтому объект уезжал с палубы
	     вбок, да ещё и получал весь поворот плота вместе с тангажом 90° —
	     то есть возвращался лежащим. ]]
	model:PivotTo(atCF or flatCF(r.PrimaryPart.Position + Vector3.new(0, 6, 0), r))
	weldToRaft(model, r)
end

evt.OnServerEvent:Connect(function(player, action, arg)
	-- ── ПОДБОР: объект → предмет в инвентаре ──
	if action == "pickup" then
		if busy[player] then return end
		local model = arg
		if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
		local r = raft()
		if not r or model.Parent ~= r then return end
		local spec, key = specFor(model)
		if not spec then return end
		if stash[player] then return end -- уже что-то несёт
		--[[ ⚠️ ПЕРЕНОСИТЬ МОЖНО ТОЛЬКО РАБОЧУЮ ПОСТРОЙКУ. Тотем — после починки
		     монолита, станцию — после пробуждения механика. Пока NPC спит у своей
		     постройки, он к ней привязан позой и сценой пробуждения; унести её
		     из-под него значило бы оставить спящего посреди палубы. Проснувшийся
		     NPC читает положение постройки живьём и сам идёт к новому месту. ]]
		if key == "Monolit_Aquamen" and not (_G.IsMonolithRepaired and _G.IsMonolithRepaired()) then
			evt:FireClient(player, "denied", "Сначала почини монолит")
			return
		end
		if key == "Raft_repair_station" and not workspace:GetAttribute("EngineerWokeDay") then
			evt:FireClient(player, "denied", "Сначала разбуди механика")
			return
		end

		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local rp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if not rp or (rp.Position - hrp.Position).Magnitude > 16 then return end

		busy[player] = true
		-- ТУЛ ДЕЛАЕМ ДО СПИСАНИЯ: если бы он не создался после оплаты, игрок
		-- остался бы и без монет, и без постройки.
		local tool = makeTool(key, spec)
		if not (_G.SpendPirate and _G.SpendPirate(player, spec.price)) then
			tool:Destroy()
			busy[player] = nil
			evt:FireClient(player, "denied", ("Нужно %d пиратов"):format(spec.price))
			return
		end

		cutExternalWelds(model, r)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored = true end
		end
		-- Нормализуем ДО отправки клиенту: он строит призрак клоном этой самой
		-- модели, и пивот приедет к нему уже правильный.
		normalizePivot(model)
		model.Parent = stashFolder
		stash[player] = model

		if _G.GiveToolOrDrop then
			_G.GiveToolOrDrop(player, tool)
		else
			tool.Parent = player:FindFirstChildOfClass("Backpack")
		end
		if _G.SendInventory then _G.SendInventory(player) end
		busy[player] = nil
		-- Отдаём клиенту САМ объект: из него он строит призрак, точно повторяющий
		-- то, что игрок несёт (шаблона в ReplicatedStorage может и не быть).
		evt:FireClient(player, "picked", model, spec.label)
		print(("%s %s подобрал %s за %d пиратов"):format(LOG_TAG, player.Name, key, spec.price))
		return
	end

	-- ── УСТАНОВКА: предмет → объект на плоту ──
	if action ~= "place" then return end
	local model = stash[player]
	if not model then return end
	if typeof(arg) ~= "CFrame" then return end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or not tool:GetAttribute("RelocateItem") then return end

	local r = raft()
	if not r or not r.PrimaryPart then return end
	local worldCF = r.PrimaryPart.CFrame:ToWorldSpace(arg)
	if (hrp.Position - worldCF.Position).Magnitude > 100 then return end

	stash[player] = nil
	model.Parent = r
	normalizePivot(model)
	model:PivotTo(worldCF)
	weldToRaft(model, r)
	-- игрок сам выбрал место — теперь эталон здесь, и сторож будет держать
	-- объект именно в этой позе, а не в той, что была на карте
	captureRest(model, r)
	tool:Destroy()
	if _G.SendInventory then _G.SendInventory(player) end
	evt:FireClient(player, "placed")
	-- Логируем и точку клика, и фактический центр габаритов: если они разойдутся,
	-- значит объект опять встал не туда, и видно это будет сразу, а не на глаз.
	local bb = model:GetBoundingBox()
	print(("%s %s установил %s: цель (%.1f, %.1f, %.1f), факт (%.1f, %.1f, %.1f)"):format(
		LOG_TAG, player.Name, model.Name,
		worldCF.Position.X, worldCF.Position.Y, worldCF.Position.Z,
		bb.Position.X, bb.Position.Y, bb.Position.Z))
end)

-- Игрок ушёл, не поставив — возвращаем объект на плот, а не теряем вместе с ним.
Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
	if stash[player] then restoreFromStash(player) end
end)

-- Клиенту нужен каталог: что переносимо, почём и как называется.
evt.OnServerEvent:Connect(function(player, action)
	if action ~= "catalog" then return end
	local list = {}
	for key, spec in pairs(MOVABLE) do
		list[key] = { price = spec.price, label = spec.label, icon = spec.icon }
	end
	evt:FireClient(player, "catalog", list)
end)

-- ── ВОЗВРАТ УЛЕТЕВШИХ ОБЪЕКТОВ ──
-- Пока пивот не нормализовался (см. normalizePivot), перенесённый тотем улетал в
-- небо или за борт: предмет из рук пропадал, на палубе не появлялось ничего, а
-- подобрать его заново нельзя — он вне радиуса подбора. В уже испорченных сейвах
-- тотем так и остался бы потерян навсегда, поэтому один раз после старта
-- возвращаем такие объекты на палубу.
local function deckTopY(r)
	local best
	for _, c in ipairs(r:GetChildren()) do
		if c.Name == "Raft_part" or c:GetAttribute("BuildType") == "raft" then
			local top
			if c:IsA("BasePart") then
				top = c.Position.Y + c.Size.Y * 0.5
			elseif c:IsA("Model") then
				local cf, sz = c:GetBoundingBox()
				top = cf.Position.Y + sz.Y * 0.5
			end
			if top and (not best or top > best) then best = top end
		end
	end
	return best
end

local TILT_LIMIT  = 20   -- градусов от эталона: дальше объект считается заваленным
local DRIFT_LIMIT = 6    -- студов от эталонной точки: дальше — уехал с места
local WATCH_STEP  = 8    -- как часто сторож смотрит (объектов двое, это даром)

--[[ ⚠️ СКОЛЬКО РАЗ СТОРОЖУ ПОЗВОЛЕНО ТРОГАТЬ ОДИН ОБЪЕКТ.
     Если правка не помогла и объект снова «плохой» — значит плох не объект, а
     мерка. Молча дёргать мебель игрока каждые восемь секунд хуже, чем один раз
     сказать в лог и отступиться. ]]
local FIX_LIMIT = 3
local fixCount = {}
-- объект, плохо стоявший на прошлом замере: двигаем только по двум подряд
local suspect  = {}

-- Поднять объект: срезать чужие сварки, поставить в эталон (или, если эталона
-- нет, в центр палубы по-старому) и приварить заново.
local function putBack(child, r, why)
	cutExternalWelds(child, r)
	for _, d in ipairs(child:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end

	local how
	if restoreRest(child, r) then
		how = "в эталонную позу"
	else
		--[[ ⚠️ ЭТОТ ПУТЬ — КРАЙНИЙ, И ОН ЗАМЕТЕН ИГРОКУ.
		     Он ставит объект в центр палубы «ровно», то есть двигает его с
		     насиженного места. Пока эталон терялся (см. слабую таблицу выше),
		     сюда попадали здоровые объекты — и владелец видел уехавшую станцию.
		     Теперь сюда попадает только то, у чего эталона не было никогда, и
		     об этом пишется отдельно. ]]
		local deck = deckTopY(r) or r.PrimaryPart.Position.Y
		local center = (_G.GetRaftCenter and _G.GetRaftCenter()) or r.PrimaryPart.Position
		local _, sz = child:GetBoundingBox()
		normalizePivot(child)
		child:PivotTo(flatCF(Vector3.new(center.X, deck + sz.Y * 0.5, center.Z), r))
		how = "В ЦЕНТР ПАЛУБЫ (эталона не было!)"
	end

	weldToRaft(child, r)
	captureRest(child, r)   -- поза снова считается правильной
	fixCount[child] = (fixCount[child] or 0) + 1
	warn(("%s %s поправлен %s — %s (правка %d из %d)")
		:format(LOG_TAG, child.Name, how, why, fixCount[child], FIX_LIMIT))
	if fixCount[child] >= FIX_LIMIT then
		warn(("%s %s: лимит правок исчерпан — больше сторож его не трогает. Если объект и правда стоит криво, дело в мерке, а не в объекте")
			:format(LOG_TAG, child.Name))
	end
end

--[[ ⚠️ СТОРОЖ РАБОТАЕТ ВСЮ ИГРУ, А НЕ ОДИН РАЗ НА ШЕСТОЙ СЕКУНДЕ.
     Разовый проход не мог помочь ни разу в жалобе «стол опять перевёрнут»:
     станцию валит перенос плота, а он случается на входе игрока — то есть
     позже, иногда сильно позже. Проверка стоит копейки, а ловит любой случай.

     ⚠️ И КРИТЕРИЙ ТЕПЕРЬ ВКЛЮЧАЕТ НАКЛОН. Раньше «потерянным» считался только
     улетевший объект: выше палубы на 8 студов или дальше радиуса на 15.
     Лежащая на своём месте станция не подходила ни под одно условие — её никто
     не поднимал, и владелец видел ровно то, о чём писал.

     ⚠️ НО СТОРОЖ, КОТОРЫЙ ОШИБАЕТСЯ, ХУЖЕ ОТСУТСТВУЮЩЕГО. Первая его версия
     переставила игроку и станцию, и тотем — здоровые, стоявшие на палубе.
     Отсюда три правила, и каждое куплено этой поломкой:
       • есть эталон — судим ТОЛЬКО по нему, второе мнение по габаритам вредно;
       • двигаем лишь то, что плохо стоит два замера подряд;
       • трогаем один объект не больше FIX_LIMIT раз за сессию.
     И на каждое решение в логе печатаются числа, по которым оно принято. ]]
task.spawn(function()
	task.wait(6)
	while true do
		local ok, err = pcall(function()
			local r = raft()
			if not r or not r.PrimaryPart then return end
			local center = (_G.GetRaftCenter and _G.GetRaftCenter()) or r.PrimaryPart.Position
			local rad = (_G.GetRaftRadius and _G.GetRaftRadius()) or 60
			local deck = deckTopY(r)

			for _, child in ipairs(r:GetChildren()) do
				if child:IsA("Model") and specFor(child)
					and (fixCount[child] or 0) < FIX_LIMIT then

					local tilt, drift = restDrift(child, r)
					local why

					if tilt then
						--[[ ⚠️ ЕСТЬ ЭТАЛОН — СУДИМ ТОЛЬКО ПО НЕМУ.
						     Здесь стояло `elseif`: объект с эталоном, но в
						     пределах допуска, проваливался в старую проверку
						     «улетел с плота» — и она его двигала. Ровно это и
						     увидел владелец: станция стояла на месте, сторож
						     объявил её «вне плота» и переставил.
						     Эталон точнее любой мерки по габаритам: он знает,
						     где объект стоял НА САМОМ ДЕЛЕ. Если по нему всё в
						     порядке — трогать нечего, и второе мнение тут
						     вредно. ]]
						if tilt > TILT_LIMIT or drift > DRIFT_LIMIT then
							why = ("наклон %.0f° (предел %d), снос %.1f студа (предел %d)")
								:format(tilt, TILT_LIMIT, drift, DRIFT_LIMIT)
						end
					elseif deck then
						--[[ Эталона нет вовсе — только тогда старая проверка
						     «улетел с плота». Печатаем ЧИСЛА, по которым принято
						     решение: спор «он же стоял на палубе» решается одной
						     строкой лога, а не догадками. ]]
						local bb, sz = child:GetBoundingBox()
						local offXZ = (Vector3.new(bb.Position.X, 0, bb.Position.Z)
							- Vector3.new(center.X, 0, center.Z)).Magnitude
						local tooHigh = bb.Position.Y > deck + sz.Y * 0.5 + 8
						local tooFar  = offXZ > rad + 15
						if tooHigh or tooFar then
							why = ("эталона нет; над палубой %+.1f (предел %.1f), от центра %.1f (предел %.1f)")
								:format(bb.Position.Y - deck, sz.Y * 0.5 + 8, offXZ, rad + 15)
						end
					end

					--[[ ⚠️ ПОДТВЕРЖДЕНИЕ ВТОРЫМ ЗАМЕРОМ, А НЕ ПО ПЕРВОМУ ЖЕ.
					     Плот качает, объект может на мгновение оказаться не там
					     — например, пока физика собирает сборку после сварки.
					     Дёрнуть мебель по такому мгновению — та самая жалоба.
					     Двигаем только то, что плохо стоит ДВА замера подряд,
					     то есть восемь секунд кряду. ]]
					if why then
						if suspect[child] then
							suspect[child] = nil
							putBack(child, r, why)
						else
							suspect[child] = true
							print(("%s %s под подозрением: %s — проверю ещё раз через %d с")
								:format(LOG_TAG, child.Name, why, WATCH_STEP))
						end
					else
						suspect[child] = nil
					end
				end
			end
		end)
		if not ok then
			warn(LOG_TAG .. " сторож построек споткнулся: " .. tostring(err))
		end
		task.wait(WATCH_STEP)
	end
end)

--[[ ⚠️ ПРОВЕРКА ПОЗ ПО ТРЕБОВАНИЮ — ДЛЯ ЗАГРУЗКИ СЕЙВА.
     Сторож выше смотрит раз в 8 с и правит только со второго замера, то есть
     через 16 с после падения. При загрузке сейва стол механика и тотем
     успевали лечь ещё до страховочной приварки, и игрок выходил на палубу к
     лежащему столу. Загрузчик зовёт эту ручку сразу после переноса плота:
     всё, что ушло от эталона, ставится обратно и приваривается тут же. ]]
_G.RaftRelocateRestoreAll = function(why)
	local r = raft()
	if not (r and r.PrimaryPart) then return 0 end
	local fixed = 0
	for _, child in ipairs(r:GetChildren()) do
		if child:IsA("Model") and specFor(child) and restRel[child] then
			local tilt, drift = restDrift(child, r)
			if tilt and (tilt > 5 or drift > 1.5) then
				cutExternalWelds(child, r)
				for _, d in ipairs(child:GetDescendants()) do
					if d:IsA("BasePart") then d.Anchored = true end
				end
				restoreRest(child, r)
				weldToRaft(child, r)
				fixed += 1
				print(("%s %s: поставлен в эталон (%s) — был наклон %.0f°, снос %.1f")
					:format(LOG_TAG, child.Name, tostring(why), tilt, drift))
			elseif tilt then
				print(("%s %s: стоит по эталону (%s) — наклон %.0f°, снос %.1f")
					:format(LOG_TAG, child.Name, tostring(why), tilt, drift))
			end
		end
	end
	return fixed
end

--[[ Снимаем эталон в первые кадры сервера: плот ещё не тронулся, всё стоит так,
     как расставлено в карте. Позже это уже не «эталон», а то, что осталось. ]]
task.spawn(function()
	local r
	for _ = 1, 50 do
		r = raft()
		if r and r.PrimaryPart then break end
		task.wait(0.1)
	end
	if not (r and r.PrimaryPart) then
		warn(LOG_TAG .. " плот не найден — эталонные позы построек не сняты")
		return
	end
	local taken = 0
	for _, child in ipairs(r:GetChildren()) do
		if child:IsA("Model") and specFor(child) and captureRest(child, r) then
			taken += 1
			print(("%s эталонная поза снята: %s"):format(LOG_TAG, child.Name))
		end
	end
	if taken == 0 then
		-- одна строка в логе вместо гадания: сторож молчит не потому, что всё
		-- хорошо, а потому, что переносимых построек в плоту не нашлось
		warn(LOG_TAG .. " переносимых построек в плоту не найдено — сторож позы работать не будет")
	end
end)

print(LOG_TAG .. " ready (подбор в инвентарь + установка, как у пушек)")
