--[[
	ЯХТА ТОРГОВЦА — рейс к плоту (ТЗ «Интеграция яхты с торговцем R6», 04.10.2026).

	Модель — ServerStorage.MerchantYacht (пак Merchant_Yacht_Transfer, без демо-
	скриптов: Server и Animate вырезаны из .rbxmx). Магазин и экономика — уже
	существующий MerchantShop.server: цены, остатки, «пираты», выдача в инвентарь.
	Здесь только корабль, торговец на нём и связь с магазином.

	Рейс (атрибут VoyageState на модели):
	  Approaching  идёт от горизонта к причальному месту у борта плота. Цель
	               считается В КАДРЕ ПЛОТА каждый кадр — плот плывёт, яхта
	               догоняет без скачков (интерполяция от старта к живой цели).
	  Moored       стоит у борта на фиксированном месте в кадре плота: едет вместе
	               с ним, высота — от плота, т.е. по той же воде. Торговля открыта.
	  Leaving      отходит от борта на горизонт и удаляется.

	Причальное место: сторона плота (одна из четырёх в его кадре), у которой
	коридор подхода свободен от островов и чужих построек; нос — к плоту,
	между носом и краем палубы зазор. Все четыре заняты — визит отменяется.

	Движение кинематическое: корпус заякорен, ход — PivotTo всей модели (вместе
	с торговцем). Физическую плавучесть не включаем — корпус под неё не собран.

	Связь с магазином:
	  _G.MerchantYachtVisit(onMoored, onCancel) — MerchantShop зовёт при «торговец приплыл»;
	                                     onMoored() — встал у борта, onCancel() — не дошёл
	  _G.MerchantYachtLeave()          — время вышло, уходит
	  _G.MerchantYachtNear(player)     — игрок у прилавка (проверка покупки)
	  _G.MerchantYachtAction(name, s)  — жест торговца (Greet, CountCoins, …)
	  _G.MerchantYachtState()          — "none" / "Approaching" / "Moored" / "Leaving"
]]

local Players           = game:GetService("Players")
local RaftShake = require(game:GetService("ReplicatedStorage"):WaitForChild("RaftShake"))   -- сварка с плотом без рывка
local RunService        = game:GetService("RunService")
local ServerStorage     = game:GetService("ServerStorage")

local LOG = "[Яхта торговца]"

-- ═══════════ настройки (ТЗ 4.10) ═══════════
local CFG = {
	APPROACH_DIST  = 140,   -- откуда начинает подход: от причального места, studs
	APPROACH_TIME  = 22,    -- длительность подхода, с
	LEAVE_TIME     = 16,    -- длительность ухода, с
	BOW_GAP        = 1.5,   -- зазор между носом и краем палубы
	SHOP_RADIUS    = 18,    -- до прилавка, чтобы покупать
	CORRIDOR_W     = 14,    -- ширина проверяемого коридора подхода (корпус 11.5)
	CORRIDOR_H     = 12,
}

-- геометрия модели пака: HullRoot — ватерлиния, нос в −Z, корма в +Z
local HULL_BOW  = 14.9    -- от HullRoot до носа

local ACTIONS = { SitIdle = 4, Greet = 2.2, Talk = 4, ShowGoods = 3, CountCoins = 3, GiveItem = 2.4, Thanks = 2, Rest = 4 }

local voyage = nil   -- { model, hull, pivotOff, dockRel, state, t0, startCF, ... }

local function raftModel()
	local r = workspace:FindFirstChild("Raft")
	return (r and r:IsA("Model") and r.PrimaryPart) and r or nil
end

-- кадр плота без качки: позиция PrimaryPart + курс RestYaw (BoatMovement пишет его каждый кадр)
local function raftFlat(raft)
	local p = raft.PrimaryPart
	return CFrame.new(p.Position) * CFrame.Angles(0, p:GetAttribute("RestYaw") or 0, 0)
end

local function waterSurfaceAt(x, z, fallbackY, ignore)
	local params = RaycastParams.new()
	params.IgnoreWater = false
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local res = workspace:Raycast(Vector3.new(x, fallbackY + 120, z), Vector3.new(0, -600, 0), params)
	if res and res.Material == Enum.Material.Water then return res.Position.Y end
	return fallbackY
end

-- ═══════════ жесты торговца: один таймер на всё (ТЗ 6) ═══════════
local actionToken = 0
local function action(name, duration)
	if not (voyage and voyage.model.Parent) then return end
	local m = voyage.model
	m:SetAttribute("MerchantAction", name)
	m:SetAttribute("ActionTime", workspace:GetServerTimeNow())
	actionToken += 1
	local my = actionToken
	duration = duration or ACTIONS[name] or 2
	if name ~= "SitIdle" and duration > 0 then
		task.delay(duration, function()
			if my == actionToken and voyage and voyage.model.Parent then
				voyage.model:SetAttribute("MerchantAction", "SitIdle")
				voyage.model:SetAttribute("ActionTime", workspace:GetServerTimeNow())
			end
		end)
	end
end
-- цепочка жестов (покупка: считает монеты → отдаёт → благодарит)
local function actionChain(list)
	actionToken += 1
	local my = actionToken
	task.spawn(function()
		for _, step in ipairs(list) do
			if my ~= actionToken then return end
			action(step[1], step[2] + 0.05)
			my = actionToken
			task.wait(step[2])
			if my ~= actionToken then return end
		end
	end)
end

-- ═══════════ причальное место ═══════════
--[[ Габарит плота в его кадре по всем деталям (стены, сети, якорь тоже торчат
     за палубу). Для каждой из четырёх сторон: где край, где середина палубы
     вдоль борта (по клеткам пола у этого края — у Г-образного плота середина
     общего габарита может висеть над водой). ]]
local function raftExtents(raft, flat)
	local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	local tiles = {}
	for _, d in ipairs(raft:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local cf = flat:ToObjectSpace(d.CFrame)
			local s = d.Size * 0.5
			local h = Vector3.new(
				math.abs(cf.XVector.X) * s.X + math.abs(cf.YVector.X) * s.Y + math.abs(cf.ZVector.X) * s.Z,
				math.abs(cf.XVector.Y) * s.X + math.abs(cf.YVector.Y) * s.Y + math.abs(cf.ZVector.Y) * s.Z,
				math.abs(cf.XVector.Z) * s.X + math.abs(cf.YVector.Z) * s.Y + math.abs(cf.ZVector.Z) * s.Z)
			mn = mn:Min(cf.Position - h)
			mx = mx:Max(cf.Position + h)
			local top = d
			while top.Parent ~= raft and top.Parent do top = top.Parent end
			if top == raft.PrimaryPart or top.Name == "Raft_part" or top:GetAttribute("BuildType") == "raft" then
				table.insert(tiles, cf.Position)
			end
		end
	end
	return mn, mx, tiles
end

-- четыре стороны: ось наружу в кадре плота
local SIDES = {
	{ out = Vector3.new(1, 0, 0),  axis = "X", along = "Z" },
	{ out = Vector3.new(-1, 0, 0), axis = "X", along = "Z" },
	{ out = Vector3.new(0, 0, 1),  axis = "Z", along = "X" },
	{ out = Vector3.new(0, 0, -1), axis = "Z", along = "X" },
}

--[[ Коридор подхода свободен? Бокс шириной с корпус от причального места до
     точки старта: всё, что не плот, не вода и не игроки, — помеха (острова,
     скалы, чужие катера). Одного луча по центру мало — корпус широкий. ]]
local function corridorFree(fromPos, toPos, raft, waterY)
	local d = toPos - fromPos
	local len = d.Magnitude
	if len < 1 then return true end
	local mid = (fromPos + toPos) / 2
	local cf = CFrame.lookAt(Vector3.new(mid.X, waterY + 2, mid.Z), Vector3.new(toPos.X, waterY + 2, toPos.Z))
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { raft }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	params.FilterDescendantsInstances = ignore
	local parts = workspace:GetPartBoundsInBox(cf, Vector3.new(CFG.CORRIDOR_W, CFG.CORRIDOR_H, len), params)
	for _, part in ipairs(parts) do
		-- помеха — крупное и неподвижное (остров, скала, чужой катер); плавающие
		-- брёвна и бочки вокруг плота не в счёт (их и так полно)
		if part.CanCollide and part.Anchored and not part:IsA("Terrain")
			and math.max(part.Size.X, part.Size.Y, part.Size.Z) > 6 then
			return false, part
		end
	end
	return true
end

-- выбрать сторону; вернёт dockRel (кадр HullRoot у причала в кадре плота) или nil
local function pickDock(raft)
	local flat = raftFlat(raft)
	local mn, mx, tiles = raftExtents(raft, flat)
	if #tiles == 0 then return nil, "у плота нет пола" end
	local waterY = waterSurfaceAt(flat.Position.X, flat.Position.Z, flat.Position.Y - 1.5, { raft })
	local dockY = waterY - flat.Position.Y

	-- порядок сторон: правый борт, корма, левый, нос (в кадре плота); первая свободная
	local order = { 1, 3, 2, 4 }
	local why = "все борта закрыты"
	-- ⚠️ борт лодочника (RaidCourier, атрибут плота CourierSide = ±1 по X) занят:
	-- яхта и лодка вставали в одну точку, одна в другой
	local courierSide = raft:GetAttribute("CourierSide")
	for _, i in ipairs(order) do
		local side = SIDES[i]
		local sgn = (side.axis == "X" and side.out.X or side.out.Z)
		if side.axis == "X" and courierSide == sgn then
			why = "борт занят лодочником"
			continue
		end
		local edge = sgn > 0 and (side.axis == "X" and mx.X or mx.Z) or (side.axis == "X" and mn.X or mn.Z)
		-- середина пола вдоль этого борта: клетки, ближайшие к краю
		local best = -math.huge
		for _, t in ipairs(tiles) do
			local c = (side.axis == "X" and t.X or t.Z) * sgn
			if c > best then best = c end
		end
		local sum, n = 0, 0
		for _, t in ipairs(tiles) do
			if (side.axis == "X" and t.X or t.Z) * sgn >= best - 6 then
				sum += (side.along == "X" and t.X or t.Z)
				n += 1
			end
		end
		local along = n > 0 and sum / n or 0
		local hullDist = edge * sgn + CFG.BOW_GAP + HULL_BOW
		local pos = side.out * hullDist
		pos = side.along == "X" and Vector3.new(along, dockY, pos.Z) or Vector3.new(pos.X, dockY, along)
		-- нос (−Z модели) смотрит на плот, т.е. против side.out
		local dockRel = CFrame.lookAt(pos, pos - side.out)
		local dockW = flat * dockRel
		local startW = dockW.Position + flat:VectorToWorldSpace(side.out) * CFG.APPROACH_DIST
		-- коридор: от кормы яхты у причала до старта
		local sternW = dockW.Position + flat:VectorToWorldSpace(side.out) * (HULL_BOW + 2)
		local ok, by = corridorFree(sternW, startW, raft, waterY)
		if ok then return dockRel, side end
		why = "коридор закрыт: " .. by:GetFullName()
	end
	return nil, why
end

-- ═══════════ модель ═══════════
local function makeYacht()
	local tpl = ServerStorage:FindFirstChild("MerchantYacht")
	if not tpl then
		warn(LOG .. " нет ServerStorage.MerchantYacht — торговец приплывает без яхты")
		return nil
	end
	local m = tpl:Clone()
	-- демо-логики в копии быть не должно (ТЗ 2, 5): ни скриптов, ни Animate
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then d:Destroy() end
	end
	--[[ ⚠️ ЦЕЛИКОМ И ВСЕГДА У КАЖДОГО КЛИЕНТА (Persistent). В плейсе StreamingEnabled:
	     на подходе и уходе клиент ведёт яхту сам, а серверная копия стоит в 140+
	     студах. Детали доезжали по одной и в разное время, клиентский PivotTo
	     сдвигал только приехавшие — опоздавшие вставали со смещением, и лодка
	     «разваливалась». Persistent: модель приходит одним куском и не выгружается. ]]
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	m:SetAttribute("DemoMode", false)
	m:SetAttribute("MerchantAction", "SitIdle")
	m:SetAttribute("ActionTime", workspace:GetServerTimeNow())
	m:SetAttribute("VoyageState", "Approaching")
	local yacht = m:FindFirstChild("Yacht")
	local hull = yacht and yacht:FindFirstChild("HullRoot")
	if not hull then
		warn(LOG .. " в модели нет Yacht.HullRoot")
		m:Destroy()
		return nil
	end
	-- торговец не тонет и не толкается: тело на суставах, корень заякорен
	local npc = m:FindFirstChild("Merchant")
	local hum = npc and npc:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		hum.BreakJointsOnDeath = false
		-- на стоянке торговец в сборке плота: стоящий Humanoid толкал бы её своей «балансировкой»
		hum.PlatformStand = true
		hum.EvaluateStateMachine = false
	end
	return m, hull
end

local function promptOf(m)
	local sign = m:FindFirstChild("Yacht") and m.Yacht:FindFirstChild("ShopSign")
	local pt = sign and sign:FindFirstChild("ShopPromptPoint")
	return pt and pt:FindFirstChildOfClass("ProximityPrompt")
end

local function counterOf(m)
	local y = m:FindFirstChild("Yacht")
	return y and y:FindFirstChild("ShopCounter")
end

-- поставить HullRoot в мировой кадр (двигаем ВСЮ модель — с торговцем, ТЗ 2)
local function placeHull(v, hullCF)
	v.model:PivotTo(hullCF * v.pivotOff)
end

--[[ ⚠️ НА СТОЯНКЕ ЯХТА ПРИВАРЕНА К ПЛОТУ, А НЕ ДВИГАЕТСЯ PivotTo.
     Сервер переставлял заякоренную модель каждый кадр, а плот у клиента едет
     своей физикой: позиции яхты доезжали по сети рывками и не в такт плоту —
     «сильно трясёт». Приваренная, она становится частью сборки плота и у
     клиента едет вместе с ним, гладко. Рецепт тот же, что у предметов
     (RaftShake): заякорить → сварить → отпустить, скорость плота вернуть.
     Свариваем только то, что было заякорено: руки, ноги и голова торговца
     висят на Motor6D — свари их, и анимация встанет. Без массы и коллизий —
     чтобы яхта не утяжеляла плот и не цеплялась корпусом за острова. ]]
local function weldToRaft(v, raft)
	local primary = raft.PrimaryPart
	local lin, ang = primary.AssemblyLinearVelocity, primary.AssemblyAngularVelocity
	v.anchored, v.welds = {}, {}
	for _, d in ipairs(v.model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Massless = true
			d.CanCollide = false
			--[[ ⚠️ БЕЗ СИЛ ВОДЫ. Корпус сидит в воде; приваренный, он — часть
			     сборки плота, и вода тормозила весь плот («плот стоит», пока яхта
			     у борта). Детали самого плота так метит BoatMovement — яхту метим сами. ]]
			pcall(function() d.EnableFluidForces = false end)
			d.CollisionGroup = "Raft"
			if d.Anchored then table.insert(v.anchored, d) end
		end
	end
	for _, p in ipairs(v.anchored) do
		local w = Instance.new("WeldConstraint")
		w.Name = "MerchantYachtWeld"
		w.Part0 = p
		w.Part1 = primary
		w.Parent = p
		table.insert(v.welds, w)
	end
	for _, p in ipairs(v.anchored) do p.Anchored = false end
	-- владелец физики — один вызов на всю сборку плота, а не на каждую из ~80 деталей
	-- яхты: серия переназначений по одной детали и давала рывок плота при швартовке
	task.defer(function()
		pcall(function() if primary:GetNetworkOwner() ~= nil then primary:SetNetworkOwner(nil) end end)
	end)
	primary.AssemblyLinearVelocity = lin
	primary.AssemblyAngularVelocity = ang
	v.weldedTo = primary
	RaftShake.notify()
end

-- отцепить от плота (уход, плот пропал): сначала заякорить, потом резать сварку
local function unweld(v)
	if not v.welds then return end
	for _, p in ipairs(v.anchored) do
		if p.Parent then p.Anchored = true end
	end
	local primary = v.weldedTo
	local lin, ang
	if primary and primary.Parent then lin, ang = primary.AssemblyLinearVelocity, primary.AssemblyAngularVelocity end
	for _, w in ipairs(v.welds) do w:Destroy() end
	v.welds, v.weldedTo = nil, nil
	if lin then
		primary.AssemblyLinearVelocity = lin
		primary.AssemblyAngularVelocity = ang
		RaftShake.notify()
	end
end

local function endVoyage(reason)
	local v = voyage
	if not v then return end
	voyage = nil
	if v.conn then v.conn:Disconnect() end
	unweld(v)
	if v.promptConn then v.promptConn:Disconnect() end
	if v.model then v.model:Destroy() end
	-- до швартовки не дошла (плот пропал, ошибка) — магазин должен об этом знать
	if not v.moored and v.onCancel then task.spawn(v.onCancel, reason) end
	print(("%s рейс окончен: %s"):format(LOG, tostring(reason)))
end

local function setState(v, s)
	v.state = s
	v.model:SetAttribute("VoyageState", s)
	local prompt = promptOf(v.model)
	if prompt then prompt.Enabled = (s == "Moored") end
end


--[[ ⚠️ НА ПОДХОДЕ И УХОДЕ ЯХТУ ДВИГАЕТ КЛИЕНТ, НЕ СЕРВЕР.
     Сервер переставлял её каждый кадр — по сети кадры доезжали рывками и не в
     такт плоту, который у клиента едет своей физикой: «пока плывёт — трясёт».
     Теперь сервер только пишет маршрут в атрибуты (VoyageT0, StartRel, DockRel,
     LeaveRel/LeaveFrom, …), а каждый клиент сам ведёт яхту относительно СВОЕГО
     плота (MerchantYachtClient) — гладко, кадр в кадр. Серверная копия стоит
     на месте без коллизий (о невидимую яхту плот не ударится) и встаёт на
     причал одним PivotTo в момент швартовки, после чего приваривается. ]]
local function startLeaving(v, raft)
	unweld(v)
	v.state = "Leaving"
	local m = v.model
	local prompt = promptOf(m)
	if prompt then prompt.Enabled = false end
	-- у борта серверная копия стоит там, где пришвартовалась; реальное место —
	-- от плота (expectedHull). С него и уходим, переставив копию.
	if raft and v.moored and not v.stranded and v.dockRel then
		placeHull(v, raftFlat(raft) * v.dockRel)
	end
	if raft and not v.stranded then
		-- уходим ровно оттуда, где стоит сейчас (с креном плота), — без скачка
		m:SetAttribute("LeaveRel", raftFlat(raft):ToObjectSpace(v.hull.CFrame))
		m:SetAttribute("LeaveFrom", nil)
	else
		m:SetAttribute("LeaveRel", nil)
		m:SetAttribute("LeaveFrom", v.hull.CFrame)
		m:SetAttribute("LeaveDir", -v.hull.CFrame.LookVector)
	end
	m:SetAttribute("LeaveT0", workspace:GetServerTimeNow())
	v.t0 = workspace:GetServerTimeNow()
	m:SetAttribute("VoyageState", "Leaving")
end

local function step(v)
	local raft = raftModel()
	local now = workspace:GetServerTimeNow()
	if v.state == "Approaching" then
		if not raft then startLeaving(v, nil) return end
		if now - v.t0 >= CFG.APPROACH_TIME then
			placeHull(v, raftFlat(raft) * v.dockRel)
			setState(v, "Moored")
			v.moored = true
			--[[ ⚠️ К ПЛОТУ БОЛЬШЕ НЕ ПРИВАРИВАЕМ. Сварка ~80 деталей перестраивала
			     сборку плота — в момент швартовки плот «микрофризил», а корпус в воде
			     тормозил его. Теперь у борта яхту каждый кадр ставит КЛИЕНТ (как на
			     подходе: raftFlat * DockRel, MerchantYachtClient), а сервер раз в
			     0,1 с подтягивает свою копию — для прилавка и подсказки. Сборка
			     плота не меняется вовсе. (weldToRaft оставлен на всякий случай.) ]]
			-- где прилавок и габарит яхты относительно корпуса: дальше сервер считает
			-- их от плота математически, не двигая свою копию (иначе подсказка «E»
			-- прыгала между серверной и клиентской позицией)
			local counter = counterOf(v.model)
			if counter then v.counterRel = v.hull.CFrame:ToObjectSpace(counter.CFrame) end
			local okBox, bcf, bsize = pcall(function() return (v.model:FindFirstChild("Yacht") or v.model):GetBoundingBox() end)
			if okBox and bcf then v.boxRel, v.boxSize = v.hull.CFrame:ToObjectSpace(bcf), bsize end
			action("Greet", ACTIONS.Greet)
			print(LOG .. " встала у борта")
			if v.onMoored then task.spawn(v.onMoored) end
		end
	elseif v.state == "Moored" then
		if v.stranded then
			-- осталась у берега: плот уплыл далеко — торговец уходит (лавка закрывается,
			-- сюжет перенесёт визит на завтра)
			if raft and raft.PrimaryPart and (raft.PrimaryPart.Position - v.hull.Position).Magnitude > 120 then
				if typeof(_G.MerchantDepart) == "function" and _G.MerchantDepart() then return end
				startLeaving(v, nil)
			end
			return
		end
		if not raft then startLeaving(v, nil) return end
		-- серверная копия стоит, где встала; где яхта на самом деле — считаем от плота
		local expected = raftFlat(raft) * v.dockRel
		v.expectedHull = expected
		--[[ ⚠️ ОСТРОВ. Приваренная яхта ехала с плотом сквозь берег. Раз в 0,2 с
		     щупаем корпус: зашёл в твёрдую неподвижную деталь не с плота и не с
		     яхты (скала, суша острова) — отцепляемся. Яхта остаётся у берега, плот
		     плывёт дальше сам: сварка срезана, скорость плота возвращена. ]]
		if now - (v.lastShoreCheck or 0) >= 0.2 then
			v.lastShoreCheck = now
			local okBox, cf, size = v.boxRel ~= nil, v.boxRel and expected * v.boxRel, v.boxSize
			if okBox and cf then
				local params = OverlapParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { v.model, raft }
				for _, p in ipairs(workspace:GetPartBoundsInBox(cf, size * 0.85, params)) do
					if p.Anchored and p.CanCollide and p.Transparency < 1 and not p:FindFirstAncestorWhichIsA("Tool")
						and not (p.Parent and p.Parent:FindFirstChildOfClass("Humanoid")) then
						v.stranded = true
						placeHull(v, expected)   -- серверная копия — туда, где яхта задела берег
						v.model:SetAttribute("Stranded", true)   -- клиенты перестают вести её за плотом
						unweld(v)
						print(("%s задела берег (%s) — отцепилась, плот плывёт дальше"):format(LOG, p:GetFullName()))
						break
					end
				end
			end
		end
	elseif v.state == "Leaving" then
		if now - v.t0 >= CFG.LEAVE_TIME then endVoyage("ушла за горизонт") end
	end
end

-- ═══════════ API для магазина ═══════════
-- куда (в кадре плота) смотрит борт, у которого яхта: лодочник выбирает другой
_G.MerchantYachtOut = function()
	return voyage and voyage.outRel or nil
end

_G.MerchantYachtState = function()
	return voyage and voyage.state or "none"
end

--[[ ⚠️ ГДЕ ЯХТА — ТАМ НЕ СТРОИМ. Пока торговец идёт к плоту, стоит у борта или
     отходит, полоса воды «корма у борта → точка старта» занята: клетка пола или
     сеть там легли бы прямо в корпус, а на отходе сбили бы яхте ход.
     _G.MerchantYachtBlocks(worldPos) — true, если точка в этой полосе
     (BuildingSystem: пол и сеть). Считаем в кадре плота: яхта движется с ним. ]]
local BLOCK_PAD = 4   -- запас по бокам и у носа, studs
_G.MerchantYachtBlocks = function(worldPos)
	local v = voyage
	if not (v and v.dockRel and v.outRel) or v.stranded then return false end
	local raft = raftModel()
	if not raft then return false end
	local rel = raftFlat(raft):PointToObjectSpace(worldPos) - v.dockRel.Position
	local out = v.outRel
	local along = rel.X * out.X + rel.Z * out.Z            -- от HullRoot наружу
	local side = math.abs(rel.X * out.Z - rel.Z * out.X)   -- поперёк
	return along >= -(HULL_BOW + BLOCK_PAD) and along <= CFG.APPROACH_DIST
		and side <= CFG.CORRIDOR_W / 2 + BLOCK_PAD
end

_G.MerchantYachtVisit = function(onMoored, onCancel)
	if voyage then endVoyage("новый визит") end
	local raft = raftModel()
	if not raft then return false, "нет плота" end
	local dockRel, sideOrWhy = pickDock(raft)
	if not dockRel then
		warn(LOG .. " визит отменён: " .. tostring(sideOrWhy))
		return false, sideOrWhy
	end
	local model, hull = makeYacht()
	if not model then return false, "нет модели" end
	local v = {
		model = model, hull = hull, state = "Approaching", t0 = workspace:GetServerTimeNow(), onMoored = onMoored, onCancel = onCancel,
		pivotOff = hull.CFrame:ToObjectSpace(model:GetPivot()),
		dockRel = dockRel, outRel = sideOrWhy.out,
	}
	v.startRel = dockRel + sideOrWhy.out * CFG.APPROACH_DIST
	voyage = v
	placeHull(v, raftFlat(raft) * v.startRel)
	-- маршрут для клиентов (они ведут яхту сами, см. step)
	model:SetAttribute("PivotOff", v.pivotOff)
	model:SetAttribute("StartRel", v.startRel)
	model:SetAttribute("DockRel", v.dockRel)
	model:SetAttribute("OutRel", v.outRel)
	model:SetAttribute("VoyageT0", v.t0)
	model:SetAttribute("ApproachTime", CFG.APPROACH_TIME)
	model:SetAttribute("LeaveTime", CFG.LEAVE_TIME)
	model:SetAttribute("ApproachDist", CFG.APPROACH_DIST)
	-- серверная копия на подходе стоит на месте: без коллизий, чтобы плот в неё не врезался
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.CanCollide = false end
	end
	setState(v, "Approaching")
	model.Parent = workspace

	local prompt = promptOf(model)
	if prompt then
		prompt.MaxActivationDistance = CFG.SHOP_RADIUS
		prompt.RequiresLineOfSight = false
		prompt.ActionText = "Торговать"
		prompt.ObjectText = "Морская лавка"
		v.promptConn = prompt.Triggered:Connect(function(player)
			if v ~= voyage or v.state ~= "Moored" then return end
			-- окно открывает клиент сам (MerchantYachtClient); здесь только приветствие
			action("Greet", ACTIONS.Greet)
			print(("%s %s открыл лавку"):format(LOG, player.Name))
		end)
	end
	v.conn = RunService.Heartbeat:Connect(function()
		if v ~= voyage then return end
		local ok, err = pcall(step, v)
		if not ok then
			warn(LOG .. " ошибка хода: " .. tostring(err))
			endVoyage("ошибка")
		end
	end)
	print(("%s вышла к плоту, сторона %s%d"):format(LOG, sideOrWhy.axis, sideOrWhy.out.X + sideOrWhy.out.Z))
	return true
end

_G.MerchantYachtLeave = function()
	local v = voyage
	if not v or v.state == "Leaving" then return end
	action("Thanks", ACTIONS.Thanks)
	startLeaving(v, raftModel())
end

-- игрок у прилавка? Яхты нет вовсе (модель не нашлась) — не мешаем магазину
_G.MerchantYachtNear = function(player)
	if not voyage then return ServerStorage:FindFirstChild("MerchantYacht") == nil end
	if voyage.state ~= "Moored" then return false end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	-- у борта яхту ведут клиенты: прилавок считаем от плота, а не по серверной копии
	if not voyage.stranded and voyage.expectedHull and voyage.counterRel then
		return (hrp.Position - (voyage.expectedHull * voyage.counterRel).Position).Magnitude <= CFG.SHOP_RADIUS + 6
	end
	local counter = counterOf(voyage.model)
	return counter ~= nil and (hrp.Position - counter.Position).Magnitude <= CFG.SHOP_RADIUS + 6
end

_G.MerchantYachtAction = function(name, duration)
	if ACTIONS[name] then action(name, duration) end
end
_G.MerchantYachtPurchase = function()
	actionChain({ { "CountCoins", 1.2 }, { "GiveItem", 2.4 }, { "Thanks", 2 } })
end

print(LOG .. " готова: _G.MerchantYachtVisit / Leave / Near / Action")
