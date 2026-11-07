-- RaftHealth.server.lua
-- Raft hit points. Max HP scales with the raft's size: each Raft_part = 10 HP
-- (so a bigger raft endures more enemy fire). Enemy ships call _G.DamageRaft().
-- When HP hits 0 the run ends: clients show the game-over screen with a choice —
-- «Возродиться» (девпродукт за Robux: полный ХП плота + респавн всей команды)
-- или «В лобби». По таймауту выбора все едут в лобби.

local Players            = game:GetService("Players")
local TeleportService    = game:GetService("TeleportService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local HP_PER_PART      = 10  -- each Raft_part is worth this much HP
local GAMEOVER_TIMEOUT = 60  -- сек на выбор «возродиться / в лобби», потом всех в лобби
--[[ ⚠️ ВОЗВРАЩАЕМ В ЛОББИ СВОЕЙ СРЕДЫ, А НЕ ВСЕГДА В ПРОД.
     Здесь стояло прод-лобби одним числом на все три океана: проигравший на деве
     или стейдже улетал к живым игрокам в прод. Пара «океан ↔ лобби» описана в
     BuildInfo, оттуда её и спрашиваем.
     Число ниже — запасное, для Studio с чужим или нулевым PlaceId; ноль
     означал бы «никуда»: забег кончается, экран показывается, а игрок остаётся
     в мёртвом океане. ]]
local LOBBY_PLACE_ID = 81459221324058
do
	local ok, BuildInfo = pcall(function()
		return require(ReplicatedStorage:WaitForChild("BuildInfo", 5))
	end)
	if ok and BuildInfo and BuildInfo.lobbyPlace then
		LOBBY_PLACE_ID = BuildInfo.lobbyPlace(LOBBY_PLACE_ID)
	end
end
-- ⚠️ Девпродукт «возрождение плота»: Creator Dashboard → опыт → Monetization →
-- Developer Products → создать и вписать ID сюда. Пока 0 — кнопка возрождает
-- БЕСПЛАТНО в Studio и у админов/владельца (тест), у обычного игрока пишет
-- «Возрождение пока недоступно».
local REVIVE_PRODUCT_ID = 0
-- БЕТА: урон по плоту ВКЛЮЧЁН — без него проигрыш невозможен и вся оборона
-- декоративна. Вернуть неуязвимость (например, для съёмки) — поставить true.
local INVINCIBLE = false

local raft = workspace:WaitForChild("Raft")

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local gameOverEvent = ensureRemote("RaftDestroyed")     -- сервер → все: экран game over (timeout, productId)
local revivedEvent  = ensureRemote("RaftRevived")        -- сервер → все: плот возрождён, спрятать экран
local actionEvent   = ensureRemote("RaftGameOverAction") -- клиент → сервер: "revive" | "lobby"

-- ── max HP from raft size ──
-- Укреплённый пол (TileKind = "iron", см. ReplicatedStorage.RaftReinforce) стоит
-- дороже обычной доски и держит больше: в этом весь смысл укрепления.
local HP_PER_PART_IRON = 25

local function totalHP()
	local hp = 0
	for _, c in ipairs(raft:GetChildren()) do
		-- сеть — полноценный тайл пола, тоже даёт HP плоту
		if c.Name == "Raft_part" or c.Name == "Net_Part" then
			hp += (c:GetAttribute("TileKind") == "iron") and HP_PER_PART_IRON or HP_PER_PART
		elseif c:GetAttribute("BuildType") == "floor_upper" then
			-- пол второго этажа — тоже настил: даёт плоту HP как обычная доска.
			-- (атрибут ставится до Parent; пересчёт дёргает сама стройка и сторож опор)
			hp += HP_PER_PART
		end
	end
	return math.max(hp, HP_PER_PART)
end

local function recomputeMax()
	local maxHP = totalHP()
	local oldMax = raft:GetAttribute("MaxHP") or maxHP
	raft:SetAttribute("MaxHP", maxHP)
	local hp = raft:GetAttribute("HP")
	if hp == nil then
		raft:SetAttribute("HP", maxHP) -- start full
	elseif maxHP > oldMax then
		raft:SetAttribute("HP", math.min(maxHP, hp + (maxHP - oldMax))) -- building repairs a bit
	else
		raft:SetAttribute("HP", math.min(hp, maxHP))
	end
end
recomputeMax()
-- Укрепление не добавляет детей плоту, а меняет атрибут уже стоящего тайла —
-- ChildAdded на него не сработает, поэтому BuildingSystem дёргает пересчёт сам.
_G.RecomputeRaftHP = recomputeMax
raft.ChildAdded:Connect(function(d) if d.Name == "Raft_part" or d.Name == "Raft_floor_upper" then recomputeMax() end end)
raft.ChildRemoved:Connect(function(d) if d.Name == "Raft_part" or d.Name == "Raft_floor_upper" then task.defer(recomputeMax) end end)

-- ── game over ──
local gameEnded = false
local gameOverGen = 0 -- поколение game over: возрождение отменяет отложенный телепорт

-- КУДА ВОЗВРАЩАТЬ. LOBBY_PLACE_ID вписывают вручную, но он почти всегда 0 —
-- из-за этого кнопка «Выйти в лобби» молча писала warn и не делала ничего.
-- Резервный путь: игрок пришёл сюда телепортом из лобби, и Roblox помнит
-- откуда — GetJoinData().SourcePlaceId. Так лобби определяется само, без
-- ручной настройки; константа остаётся как приоритетное переопределение.
local function resolveLobbyPlaceId(players)
	if LOBBY_PLACE_ID > 0 then return LOBBY_PLACE_ID end
	for _, p in ipairs(players) do
		local ok, data = pcall(function() return p:GetJoinData() end)
		local src = ok and data and tonumber(data.SourcePlaceId)
		if src and src > 0 and src ~= game.PlaceId then return src end
	end
	-- никто не телепортировался (прямой заход в Studio) — спросим у любого игрока
	for _, p in ipairs(Players:GetPlayers()) do
		local ok, data = pcall(function() return p:GetJoinData() end)
		local src = ok and data and tonumber(data.SourcePlaceId)
		if src and src > 0 and src ~= game.PlaceId then return src end
	end
	return nil
end

-- Возвращает true, если телепорт реально запущен.
local function teleportToLobby(players)
	if #players == 0 then return false end
	local placeId = resolveLobbyPlaceId(players)
	if not placeId then
		warn("[RaftHealth] лобби не определено: LOBBY_PLACE_ID = 0 и игроки зашли "
			.. "напрямую (без телепорта из лобби) — впиши ID лобби в RaftHealth.server.lua")
		return false
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, players)
	end)
	if not ok then
		warn("[RaftHealth] телепорт в лобби (" .. tostring(placeId) .. ") не удался: " .. tostring(err))
		return false
	end
	return true
end

-- наружу: конец забега по жизням команды (DeathPenalty) уезжает в лобби тем же путём
_G.TeleportAllToLobby = function()
	return teleportToLobby(Players:GetPlayers())
end
-- и выборочно: капитан высадил игрока (RaftCrew)
_G.TeleportPlayersToLobby = function(list)
	return teleportToLobby(list)
end

local function gameOver()
	if gameEnded then return end
	gameEnded = true
	gameOverGen += 1
	local gen = gameOverGen
	gameOverEvent:FireAllClients(GAMEOVER_TIMEOUT, REVIVE_PRODUCT_ID)
	-- Никто не выбрал возрождение за отведённое время — всех в лобби.
	task.delay(GAMEOVER_TIMEOUT, function()
		if gameEnded and gen == gameOverGen then
			teleportToLobby(Players:GetPlayers())
		end
	end)
end

-- Возрождение: полный ХП плота + респавн всех мёртвых игроков. Идемпотентно:
-- поздний чек (Roblox может донести его с задержкой) просто ещё раз лечит плот.
local function reviveRaft()
	raft:SetAttribute("HP", raft:GetAttribute("MaxHP") or 0)
	local wasEnded = gameEnded
	if gameEnded then
		gameEnded = false
		gameOverGen += 1 -- отменяет отложенный телепорт в лобби
		revivedEvent:FireAllClients()
	end
	-- Респавн — под ПИКОМ «вспышки всплытия» на клиентах (~2s после события):
	-- экран в этот момент полностью залит светом, и раскрытие показывает уже
	-- живую команду, а не телепорт персонажа на глазах у игрока.
	task.delay(wasEnded and 2 or 0, function()
		for _, p in ipairs(Players:GetPlayers()) do
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if not (hum and hum.Health > 0) then
				pcall(function() p:LoadCharacter() end)
			end
		end
	end)
end

-- ── public API ──
_G.DamageRaft = function(amount)
	if INVINCIBLE or gameEnded then return end -- INVINCIBLE: raft ignores all damage (testing)
	local hp = math.max((raft:GetAttribute("HP") or 0) - (amount or 0), 0)
	raft:SetAttribute("HP", hp)
	if hp <= 0 then gameOver() end
end

_G.GetRaftHP = function()
	return raft:GetAttribute("HP") or 0, raft:GetAttribute("MaxHP") or 0
end

-- ── ТЕСТ: ручное отнятие ХП кнопкой (RaftDamageDebugUI.client) ──
-- Пишем в атрибут НАПРЯМУЮ: мимо INVINCIBLE (иначе кнопка молчит) и мимо gameOver
-- (тестовый урон не должен заканчивать ран). Только для админов/Studio.
local testRemote = ReplicatedStorage:FindFirstChild("RaftDamageTest")
if not testRemote then
	testRemote = Instance.new("RemoteEvent")
	testRemote.Name = "RaftDamageTest"
	testRemote.Parent = ReplicatedStorage
end

local RunService = game:GetService("RunService")
local adminIds
local function isAdmin(player)
	if adminIds == nil then
		local ok, cfg = pcall(function()
			return require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig", 5))
		end)
		adminIds = (ok and cfg and cfg.ADMIN_USER_IDS) or {}
	end
	return RunService:IsStudio()
		or table.find(adminIds, player.UserId) ~= nil
		or (game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId)
end

testRemote.OnServerEvent:Connect(function(player, amount)
	if not isAdmin(player) then return end
	amount = math.clamp(tonumber(amount) or 10, 1, 100)
	local hp = math.max((raft:GetAttribute("HP") or 0) - amount, 0)
	raft:SetAttribute("HP", hp)
	print(("[RaftHealth] TEST: -%d хп → %d/%d"):format(amount, hp, raft:GetAttribute("MaxHP") or 0))
end)

-- ── выбор на экране «плот разрушен» ──
actionEvent.OnServerEvent:Connect(function(player, action)
	if not gameEnded then return end
	if action == "lobby" then
		-- уезжает только нажавший: остальные ещё могут купить возрождение
		if not teleportToLobby({ player }) then
			-- ОБЯЗАТЕЛЬНО СООБЩИТЬ КЛИЕНТУ. Экран уже уехал вверх в анимации
			-- ухода, и без ответа игрок оставался перед пустотой, думая, что
			-- кнопка не работает. Возвращаем экран и показываем причину.
			actionEvent:FireClient(player, "lobbyFailed")
		end
	elseif action == "revive" then
		if REVIVE_PRODUCT_ID > 0 then
			pcall(function()
				MarketplaceService:PromptProductPurchase(player, REVIVE_PRODUCT_ID)
			end)
		elseif isAdmin(player) then
			-- Раньше здесь стояла проверка ТОЛЬКО на Studio, и в самом плеере
			-- кнопка молча упиралась в «недоступно» — проверить возрождение было
			-- нечем, пока не создан девпродукт. isAdmin покрывает и Studio, и
			-- админов, и владельца места (та же проверка, что у тестовых кнопок).
			print("[RaftHealth] бесплатное возрождение для " .. player.Name
				.. " (REVIVE_PRODUCT_ID не задан)")
			reviveRaft()
		else
			warn("[RaftHealth] REVIVE_PRODUCT_ID не задан — создай девпродукт и впиши ID в RaftHealth.server.lua")
			actionEvent:FireClient(player, "reviveUnavailable")
		end
	end
end)

-- Начисление покупки идёт через единый ProcessReceipt в WoodBoostProducts —
-- регистрируем свой продукт в его реестре (скрипты стартуют параллельно, ждём).
if REVIVE_PRODUCT_ID > 0 then
	task.spawn(function()
		local deadline = os.clock() + 30
		while _G.RegisterProductHandler == nil and os.clock() < deadline do
			task.wait(0.2)
		end
		if _G.RegisterProductHandler then
			_G.RegisterProductHandler(REVIVE_PRODUCT_ID, function(buyer)
				print(("[RaftHealth] %s купил возрождение плота"):format(buyer.Name))
				reviveRaft()
				return true
			end)
		else
			warn("[RaftHealth] _G.RegisterProductHandler не появился (WoodBoostProducts) — чек возрождения некому обработать")
		end
	end)
end
