--[[
	ТАВЕРНА — СОЗДАНИЕ ЖИТЕЛЕЙ (сервер). Хендофф IslandHall_Integration_V25.
	Константы и тайминг — IslandHallConfig. Сцену (интерьер, работников, двери,
	сферу, сборку жителя) рисует каждый клиент сам — IslandHallClient.

	Цикл: Charging → Ready → Revealing → Cooldown → Charging. Прогресс считается
	от RecruitStartedAt (серверное время, оно же Unix-время — переживает
	перезаход и сейв плота). Подготовка: 2 / 1,5 / 1 / 1 игровых дня по уровню.

	Выдача ОДНОКРАТНАЯ: при нажатии сервер пишет в здание PendingGrant (кого
	выдать) — он сохраняется вместе с плотом. Выдаёт сервер сам, по своему
	таймеру, когда житель вышел; PendingGrant снимается ДО выдачи. Повторные и
	одновременные нажатия отбиваются состоянием (не Ready — нечего забирать).
	Выдача — _G.GrantSurvivor (SurvivorService): он же показывает игроку попап
	«Новый персонаж!».

	API: RemoteEvent IslandHallAction("Claim", hall)
	     _G.IslandHallSkip(player) — настройки: подготовка готова сразу
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage:WaitForChild("IslandHallConfig"))
local Anim = require(ReplicatedStorage:WaitForChild("RecruitAnimations"))
local LOG = "[Таверна]"

local remote = ReplicatedStorage:FindFirstChild("IslandHallAction")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "IslandHallAction"
	remote.Parent = ReplicatedStorage
end

local function now() return workspace:GetServerTimeNow() end
local function raft() return workspace:FindFirstChild("Raft") end

local function notify(player, kind, title, body)
	if player and typeof(_G.NotifyPlayer) == "function" then
		_G.NotifyPlayer(player, { type = kind, icon = kind == "success" and "ok" or "no", title = title, body = body })
	end
end

-- владелец плота; если владельца нет вовсе (прямой заход в Studio) — любой на борту
local function canUse(player)
	if typeof(_G.IsRaftOwner) ~= "function" or _G.IsRaftOwner(player) then return true end
	for _, p in ipairs(Players:GetPlayers()) do
		if _G.IsRaftOwner(p) then return false end
	end
	return true
end
local function ownerPlayer()
	for _, p in ipairs(Players:GetPlayers()) do
		if typeof(_G.IsRaftOwner) ~= "function" or _G.IsRaftOwner(p) then return p end
	end
	return Players:GetPlayers()[1]
end

local function level(hall) return math.clamp(tonumber(hall:GetAttribute("Level")) or 0, 0, 3) end

local function charge(hall)
	hall:SetAttribute("RecruitState", "Charging")
	hall:SetAttribute("RecruitCycleDuration", C.cycleSeconds(level(hall)))
	hall:SetAttribute("RecruitStartedAt", now())
	hall:SetAttribute("RecruitProgress", 0)
end

-- кого выдать: по весам, но без тех, кто уже в команде игрока (иначе выдача
-- упрётся в «этот выживший уже в команде»). Все уже есть — из всех.
local function pickResident(player)
	local pool = {}
	for _, r in ipairs(C.RESIDENTS) do
		local owned = player and typeof(_G.SurvivorOwned) == "function" and _G.SurvivorOwned(player, r.def)
		if not owned then table.insert(pool, r) end
	end
	if #pool == 0 then pool = C.RESIDENTS end
	local total = 0
	for _, r in ipairs(pool) do total += r.weight end
	local x = Random.new():NextNumber() * total
	for _, r in ipairs(pool) do
		x -= r.weight
		if x <= 0 then return r.def end
	end
	return pool[1].def
end

local granting = setmetatable({}, { __mode = "k" })

local function grant(hall, player)
	local def = hall:GetAttribute("PendingGrant")
	if type(def) ~= "string" or def == "" or granting[hall] then return end
	player = (player and player.Parent) and player or ownerPlayer()
	if not player then return end   -- некому: PendingGrant ждёт до входа владельца
	granting[hall] = true
	hall:SetAttribute("PendingGrant", nil)   -- снимаем ДО выдачи: второй раз не выдаст
	local ok, why = false, "SurvivorService не загружен"
	if typeof(_G.GrantSurvivor) == "function" then
		local worked, a, b = pcall(_G.GrantSurvivor, player, def)
		if worked then ok, why = a, b else why = tostring(a) end
	end
	granting[hall] = nil
	if ok then
		print(("%s %s получил жителя %s"):format(LOG, player.Name, def))
	else
		notify(player, "warn", "Житель не пришёл", tostring(why))
		warn(("%s выдача %s игроку %s не удалась: %s"):format(LOG, def, player.Name, tostring(why)))
	end
end

local function revealLength(variant)
	return C.walkStart() + (Anim.Duration[variant] or 3) + C.CELEBRATE
end

local busy = setmetatable({}, { __mode = "k" })

local function reveal(hall, player)
	if busy[hall] then return end
	busy[hall] = true
	local seq = (tonumber(hall:GetAttribute("RecruitSeq")) or 0) + 1
	local variant = (seq - 1) % 6 + 1
	local def = pickResident(player)
	hall:SetAttribute("RecruitSeq", seq)
	hall:SetAttribute("PendingGrant", def)        -- сохраняется с плотом: выдача переживёт сбой
	hall:SetAttribute("RevealDef", def)
	hall:SetAttribute("RevealVariant", variant)
	hall:SetAttribute("RevealStartedAt", now())
	hall:SetAttribute("RecruitState", "Revealing")
	print(("%s %s: житель %s, выход «%s»"):format(LOG, player.Name, def, Anim.Names[variant] or "?"))
	task.delay(revealLength(variant), function()
		if hall.Parent then
			grant(hall, player)
			hall:SetAttribute("RecruitState", "Cooldown")
			task.wait(0.7)
			if hall.Parent then charge(hall) end
		end
		busy[hall] = nil
	end)
end

local lastRequest = {}
remote.OnServerEvent:Connect(function(player, action, hall)
	if action ~= "Claim" then return end
	local t = os.clock()
	if t - (lastRequest[player] or 0) < 0.25 then return end
	lastRequest[player] = t
	if typeof(hall) ~= "Instance" or not CollectionService:HasTag(hall, C.TAG) then return end
	local r = raft()
	if not (r and hall:IsDescendantOf(r)) then return end
	if not canUse(player) then notify(player, "warn", "Не твой плот", "Жителей принимает владелец плота") return end
	if hall:GetAttribute("RecruitState") ~= "Ready" or busy[hall] or hall:GetAttribute("Building") then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local origin = hall:FindFirstChild("AssemblyOrigin")
	if not (root and origin) or (root.Position - origin.Position).Magnitude > 30 then return end
	reveal(hall, player)
end)
Players.PlayerRemoving:Connect(function(p) lastRequest[p] = nil end)

-- здание на плоту: метка, состояние; из сейва — продолжить заряд или довыдать
local function adopt(hall)
	if CollectionService:HasTag(hall, C.TAG) then return end
	CollectionService:AddTag(hall, C.TAG)
	local state = hall:GetAttribute("RecruitState")
	if state == "Revealing" or state == "Cooldown" or type(hall:GetAttribute("RecruitStartedAt")) ~= "number" then
		-- сцена прервалась (сейв/перезаход): если житель был обещан — выдадим, заряд заново
		charge(hall)
	else
		hall:SetAttribute("RecruitCycleDuration", C.cycleSeconds(level(hall)))
	end
	if hall:GetAttribute("PendingGrant") then
		task.delay(3, function() if hall.Parent then grant(hall, nil) end end)
	end
	-- уровень сменился посреди заряда: доля прогресса сохраняется, срок — по новому уровню
	hall:GetAttributeChangedSignal("Level"):Connect(function()
		if hall:GetAttribute("RecruitState") ~= "Charging" then return end
		local old = tonumber(hall:GetAttribute("RecruitCycleDuration")) or C.cycleSeconds(0)
		local frac = math.clamp((now() - (hall:GetAttribute("RecruitStartedAt") or now())) / old, 0, 1)
		local new = C.cycleSeconds(level(hall))
		hall:SetAttribute("RecruitCycleDuration", new)
		hall:SetAttribute("RecruitStartedAt", now() - frac * new)
	end)
	print(("%s здание на плоту: уровень %d, подготовка %d с"):format(LOG, level(hall), C.cycleSeconds(level(hall))))
end

local function consider(inst)
	if inst:IsA("Model") and inst.Name == C.NAME then
		task.defer(function()
			local r = raft()
			if inst.Parent and r and inst:IsDescendantOf(r) and not inst:GetAttribute("PlacementGhost") then adopt(inst) end
		end)
	end
end
workspace.DescendantAdded:Connect(consider)
for _, d in ipairs(workspace:GetDescendants()) do consider(d) end

-- заряд → готово (и довыдача, когда владелец зашёл)
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, hall in ipairs(CollectionService:GetTagged(C.TAG)) do
			if hall.Parent and hall:GetAttribute("RecruitState") == "Charging" then
				local dur = tonumber(hall:GetAttribute("RecruitCycleDuration")) or C.cycleSeconds(level(hall))
				local p = math.clamp((now() - (hall:GetAttribute("RecruitStartedAt") or now())) / dur, 0, 1)
				hall:SetAttribute("RecruitProgress", math.floor(p * 1000) / 1000)
				if p >= 1 then hall:SetAttribute("RecruitState", "Ready") end
			end
			if hall.Parent and hall:GetAttribute("PendingGrant") and not busy[hall] then grant(hall, nil) end
		end
	end
end)

-- настройки: «скипнуть подготовку жителя»
_G.IslandHallSkip = function(player)
	if not canUse(player) then return 0 end
	local n = 0
	for _, hall in ipairs(CollectionService:GetTagged(C.TAG)) do
		if hall.Parent and hall:GetAttribute("RecruitState") == "Charging" then
			local dur = tonumber(hall:GetAttribute("RecruitCycleDuration")) or C.cycleSeconds(level(hall))
			hall:SetAttribute("RecruitStartedAt", now() - dur - 1)
			n += 1
		end
	end
	return n
end

print(LOG .. " готово: подготовка " .. C.cycleSeconds(0) .. "/" .. C.cycleSeconds(1) .. "/" .. C.cycleSeconds(2) .. " с, выдача через GrantSurvivor")
