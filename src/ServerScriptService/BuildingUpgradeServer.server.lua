--[[
	УЛУЧШЕНИЕ ПОСТРОЕК ПЛОТА (сервер): рыбацкое место и домик фермера, уровни 0…3.
	Данные и правила — BuildingLevels. Табличка над постройкой —
	BuildingUpgradeBillboard.client, полёт деталей и звук — BuildingUpgradeFx.client.

	Атрибуты постройки (их же пишет сейв плота, RaftSaveSystem.attrsOf):
	  Level         — подтверждённый уровень (сохраняется)
	  BuildingName  — подпись на табличке
	  Building      — идёт сборка (новые покупки отклоняются)
	  BuildFrom / BuildTo / BuildStart / BuildDuration — текущий шаг сборки;
	                  клиенты по ним рисуют полёт деталей и прогресс
	Покупка: RemoteEvent UpgradeBuilding(model). Клиент цену не выбирает: сервер
	сверяет владельца плота, уровень и баланс и списывает pirate один раз.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local L = require(ReplicatedStorage:WaitForChild("BuildingLevels"))
local LOG = "[Улучшение построек]"

local remote = ReplicatedStorage:FindFirstChild("UpgradeBuilding")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "UpgradeBuilding"
	remote.Parent = ReplicatedStorage
end

local function raft() return workspace:FindFirstChild("Raft") end

local function isBuilding(m)
	return m:IsA("Model") and L.KINDS[m.Name] ~= nil and not m:GetAttribute("PlacementGhost")
		and raft() ~= nil and m:IsDescendantOf(raft())
end

-- постройка с плота: метка, имя, уровень из сохранения — сразу, без анимации
local function adopt(m)
	if CollectionService:HasTag(m, L.TAG) then return end
	if #L.pieces(m) == 0 then
		local tpl = require(ReplicatedStorage:WaitForChild("AssetFind")).find(m.Name)
		warn(("%s %s без уровней (нет деталей с LevelMask) — старая модель, таблички не будет. Поставь заново; шаблон сейчас: %s%s")
			:format(LOG, m:GetFullName(), tpl and tpl:GetFullName() or "—",
				tpl and (tpl:FindFirstChild("PermanentBase") and " (с уровнями)" or " (СТАРЫЙ, без уровней)") or ""))
		return
	end
	local level = math.clamp(math.floor(tonumber(m:GetAttribute("Level")) or 0), 0, L.MAX)
	m:SetAttribute("Level", level)
	m:SetAttribute("CurrentLevel", level)
	m:SetAttribute("BuildingName", L.KINDS[m.Name].name)
	m:SetAttribute("Building", false)
	L.apply(m, level)
	CollectionService:AddTag(m, L.TAG)
	print(("%s табличка: %s, уровень %d, деталей уровней %d"):format(LOG, m:GetFullName(), level, #L.pieces(m)))
	-- рыбак ждал уровня (RaftFishing.launch) — запускаем
	if m.Name == "Raft_fishing_spot" and typeof(_G.RaftFishingRespawn) == "function" then
		task.defer(function() pcall(_G.RaftFishingRespawn, m) end)
	end
end

local function consider(inst)
	if inst:IsA("Model") and L.KINDS[inst.Name] then
		task.defer(function()
			if inst.Parent and isBuilding(inst) then adopt(inst) end
		end)
	end
end
workspace.DescendantAdded:Connect(consider)
for _, d in ipairs(workspace:GetDescendants()) do consider(d) end

--[[ ⚠️ РЫБАКА НА ВРЕМЯ УЛУЧШЕНИЯ СТАВИМ НА ПАУЗУ, А НЕ ПЕРЕСОЗДАЁМ.
     Держать удочку, пока меняются её детали, нельзя — в руке копия, снятая со
     старого уровня. Раньше ради этого станцию останавливали целиком: рыбак
     уничтожался и собирался заново. Для плота это две перестройки сборки подряд
     (работник ушёл → пришёл) плюс возврат владения физикой серверу — плот
     проседал и дёргался ровно в момент апгрейда.
     Теперь рыбак с плота не уходит: пауза → он сам возвращает удочку на место и
     встаёт (отметка FishingParked) → меняем детали → обновляем копию удочки
     (_G.RaftFishingRelevel) → снимаем паузу. Сборка плота не меняется вовсе. ]]
local function holdFisher(spot)
	if spot.Name ~= "Raft_fishing_spot" then return end
	spot:SetAttribute("FishingPaused", true)
	local deadline = os.clock() + 15
	while os.clock() < deadline do
		-- станции может не быть вовсе (рыбака не назначили) — тогда и ждать нечего
		local running = false
		if typeof(_G.RaftFishingList) == "function" then
			for _, e in ipairs(_G.RaftFishingList()) do
				if e.spot == spot and e.npc and e.npc.Parent then running = true end
			end
		end
		if not running or spot:GetAttribute("FishingParked") then return end
		task.wait(0.2)
	end
	warn(LOG .. " рыбак не встал на паузу за 15 с — меняю детали как есть")
end
local function releaseFisher(spot)
	if spot.Name ~= "Raft_fishing_spot" then return end
	--[[ Копию удочки пересобираем ПОСЛЕ смены деталей. Если станции нет или
	     пересобрать не вышло — откатываемся на полный перезапуск: лучше рывок
	     плота, чем рыбак со старой удочкой. ]]
	local ok = false
	if typeof(_G.RaftFishingRelevel) == "function" then
		ok = _G.RaftFishingRelevel(spot) == true
	end
	spot:SetAttribute("FishingPaused", false)
	if not ok and typeof(_G.RaftFishingRespawn) == "function" then
		pcall(_G.RaftFishingRespawn, spot)
	end
end

-- один уровень: from → from+1
local function runStep(m, from, to)
	local _, removed = L.diff(m, from, to)
	local dur = L.duration(m, from, to)
	m:SetAttribute("BuildFrom", from)
	m:SetAttribute("BuildTo", to)
	m:SetAttribute("BuildDuration", dur)
	m:SetAttribute("BuildStart", workspace:GetServerTimeNow())
	-- устаревшие детали уходят первыми (клиент показывает их отлёт сам)
	task.wait(L.REMOVE)
	for _, p in ipairs(removed) do if p.Parent then p.Transparency = 1; p.CanQuery = false end end
	task.wait(math.max(0, dur - L.REMOVE))
	--[[ ⚠️ УРОВЕНЬ — СРАЗУ, НЕ ДОЖИДАЯСЬ РЫБАКА. Раньше здесь ждали, пока рыбак
	     отложит удочку и встанет; ночью спящий тянул до 15 с, и табличка висела
	     на «99%». Рыбака доводим в фоне после стройки (см. обработчик ниже). ]]
	L.apply(m, to)
	m:SetAttribute("Level", to)
	m:SetAttribute("CurrentLevel", to)
end

local busy = setmetatable({}, { __mode = "k" })

remote.OnServerEvent:Connect(function(player, m)
	if typeof(m) ~= "Instance" or not CollectionService:HasTag(m, L.TAG) or not isBuilding(m) then return end
	-- владелец плота; если владельца нет вовсе (прямой заход в Studio) — разрешаем
	if typeof(_G.IsRaftOwner) == "function" and not _G.IsRaftOwner(player) then
		local anyOwner = false
		for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
			if _G.IsRaftOwner(p) then anyOwner = true end
		end
		if anyOwner then
			if typeof(_G.NotifyPlayer) == "function" then
				_G.NotifyPlayer(player, { type = "warn", icon = "no", title = "Не твой плот", body = "Улучшать постройки может владелец плота" })
			end
			return
		end
	end
	if busy[m] or m:GetAttribute("Building") then return end
	local level = m:GetAttribute("Level") or 0
	if level >= L.MAX then return end
	local cost = L.Costs[level]
	if not cost then return end
	if typeof(_G.SpendPirate) ~= "function" then warn(LOG .. " нет _G.SpendPirate") return end

	busy[m] = true
	local okSpend, spent = pcall(_G.SpendPirate, player, cost)
	if not (okSpend and spent) then
		busy[m] = nil
		if typeof(_G.NotifyPlayer) == "function" then
			_G.NotifyPlayer(player, { type = "warn", icon = "no", title = "Не хватает пиратов", body = "Улучшение стоит " .. L.formatNum(cost) })
		end
		return
	end
	m:SetAttribute("Building", true)
	m:SetAttribute("BuildStart", workspace:GetServerTimeNow())
	m:SetAttribute("BuildDuration", 0)
	--[[ Рыбак встаёт на паузу СРАЗУ: удочку он возвращает (~5 с) параллельно со
	     сборкой, а не после неё — иначе табличка 5 с висела на «100%».
	     holdFisher в конце шага лишь дождётся, если он ещё не успел. ]]
	if m.Name == "Raft_fishing_spot" then m:SetAttribute("FishingPaused", true) end
	print(("%s %s: %s %d → %d за %d pirate"):format(LOG, player.Name, m.Name, level, level + 1, cost))

	task.spawn(function()
		local ok, err = xpcall(function()
			runStep(m, level, level + 1)
		end, debug.traceback)
		if not ok then
			-- оплачено, но стройка сорвалась: уровень всё равно выдаём (деньги не теряются)
			warn(LOG .. " сбой сборки, ставлю уровень сразу: " .. tostring(err))
			if m.Parent then
				L.apply(m, level + 1)
				m:SetAttribute("Level", level + 1)
				m:SetAttribute("CurrentLevel", level + 1)
			end
		end
		if m.Parent then m:SetAttribute("Building", false) end
		busy[m] = nil
		-- рыбак: дождаться, пока отложит удочку (вернёт деталям видимость СТАРОГО
		-- уровня), поставить уровень ещё раз поверх и пересобрать удочку в руке
		if m.Name == "Raft_fishing_spot" then
			holdFisher(m)
			if m.Parent then L.apply(m, m:GetAttribute("Level") or level + 1) end
		end
		releaseFisher(m)
	end)
end)

print(LOG .. " готово: уровни 0–" .. L.MAX .. ", RemoteEvent UpgradeBuilding")
