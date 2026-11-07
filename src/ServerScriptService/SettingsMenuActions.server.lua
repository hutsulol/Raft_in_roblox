-- SettingsMenuActions.server.lua
-- Серверная часть меню настроек (SettingsMenu.client):
--   • setBalance N — установить баланс пиратской валюты (атрибут "Pirate");
--   • grant key N  — выдать ресурс: Log/Plastic/Leaves → инвентарь, Torch → Tool
--     в руки/рюкзак, Ammo → пополнить ЗАПАСНЫЕ патроны на всех пушках (обойму не трогаем).
-- Баланс и выдача — инструменты теста: доступны админам/владельцу/Studio (как RaftDamageTest).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

local remote = ReplicatedStorage:FindFirstChild("SettingsAction")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "SettingsAction"
	remote.Parent = ReplicatedStorage
end

-- ── права: Studio / админы из конфига / владелец плейса ──
-- ⚠️ НЕУДАЧНЫЙ require НЕ КЭШИРУЕМ.
-- Раньше при осечке (конфиг не успел появиться) в adminIds навсегда оседал
-- пустой список, и дальше не помогало уже ничего — на живом сервере это выглядит
-- как «в Studio работает, в игре нет».
local adminIds
local function adminList()
	if adminIds then return adminIds end
	local ok, cfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig", 5))
	end)
	local list = ok and cfg and cfg.ADMIN_USER_IDS
	if list then adminIds = list end
	return list or {}
end

-- ⚠️ ВЛАДЕЛЕЦ ГРУППОВОГО ПЛЕЙСА — ТОЖЕ ВЛАДЕЛЕЦ.
-- Проверка была только на CreatorType == User. Если игра лежит под ГРУППОЙ,
-- CreatorId — это id группы, и сравнение с UserId не совпадёт никогда: в Studio
-- всё работало по флагу IsStudio, а в живой игре тихо отказывало.
local function isPlaceOwner(player)
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function() return player:GetRankInGroup(game.CreatorId) end)
		return ok and rank == 255
	end
	return false
end

local function isAdmin(player)
	return RunService:IsStudio()
		or table.find(adminList(), player.UserId) ~= nil
		or isPlaceOwner(player)
end

-- Стакающиеся ресурсы: уходят прямо в инвентарь через _G.AddResourceToInventory.
-- Ключи обязаны совпадать с RESOURCE_NAMES в InventoryManager — иначе выдача
-- молча не долетит до слота. Сырая рыба и мясо здесь ради теста мангала/костра.
local STACKABLE = {
	Log = true, Plastic = true, Leaves = true, Stone = true,
	Blue_Fish = true, Carp_Fish = true, Tilapia_Fish = true, Meat = true,
	-- Овощи для грядки: сажаются и собираются тем же ключом
	Potato = true, Beet = true,
	Rubbish = true,   -- мусор: сырьё для гвоздей (тест крафта)
	-- плавильня: водоросли и руда — проверить полный цикл плавки
	Seaweed = true, Iron_Ore = true,
}

-- размещаемые постройки: имя → иконка тула (выдаются как награда после волны)
local PLACEABLE_ICONS = {
	Cannon        = "rbxassetid://118236242385241",
	Deffender     = "rbxassetid://86928740553428",
	Pulemet_lvl_1 = "rbxassetid://106277044945645",
	Pulemet_lvl_2 = "rbxassetid://79105833790080",
}

-- ── пополнение запасных патронов (та же логика, что у ящика с патронами) ──
local MAX_RESERVE = { Revolver = 18, Pirate_Gun = 9, PirateGun = 9 }
local function baseName(name)
	return (name:gsub("%s*%b()%s*$", ""))
end
local function refillAmmo(player)
	local containers = {}
	if player.Character then table.insert(containers, player.Character) end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then table.insert(containers, bp) end
	local guns = 0
	for _, cont in ipairs(containers) do
		for _, tool in ipairs(cont:GetChildren()) do
			if tool:IsA("Tool") then
				local cfg = tool:FindFirstChild("Configs")
				local reserve = cfg and cfg:FindFirstChild("ReserveAmmo")
				if reserve and reserve:IsA("IntValue") then
					local maxCfg = cfg:FindFirstChild("MaxReserveAmmo")
					local mag    = cfg:FindFirstChild("MagSize")
					local maxV = (maxCfg and maxCfg.Value)
						or MAX_RESERVE[baseName(tool.Name)]
						or (mag and mag.Value * 3)
						or reserve.Value
					if maxV > reserve.Value then reserve.Value = maxV end
					guns += 1
				end
			end
		end
	end
	return guns
end

-- ⚠️ ОТКАЗ ОБЪЯСНЯЕТ СЕБЯ, А НЕ МОЛЧИТ.
-- Прежний `if not isAdmin then return end` не оставлял ни следа: в живой игре
-- кнопки просто ничего не делали, и понять, что дело в правах, было неоткуда.
-- Пишем и игроку, и в лог сервера — один раз на человека, чтобы не засорять.
local warnedNoRights = {}

--[[ ⚠️ ЗДЕСЬ БЫЛА ЛАЗЕЙКА: ЛАКИ-БЛОК ВЫЗЫВАЛСЯ БЕЗ ПРОВЕРКИ ПРАВ.
     Так было сделано ради тестов с телефона (админом туда не зайти), и это
     же означало, что любой игрок мог вызывать себе ящик сколько угодно —
     достаточно было отправить действие руками, без всякой кнопки.
     Тесты прошли, кнопка убрана (RewardRoll.client), лазейка закрыта.
     Возвращать это в таком виде нельзя: выдача награды не должна зависеть
     от того, есть ли у игрока кнопка. ]]

remote.OnServerEvent:Connect(function(player, action, a, b)

	if not isAdmin(player) then
		if not warnedNoRights[player.UserId] then
			warnedNoRights[player.UserId] = true
			warn(("[SettingsMenu] %s (id %d): нет прав на тестовые действия. "
				.. "Впиши id в WeaponUpgradeConfig.ADMIN_USER_IDS или заходи владельцем плейса.")
				:format(player.Name, player.UserId))
		end
		if _G.NotifyPlayer then
			_G.NotifyPlayer(player, { type = "warn", icon = "🔒",
				title = "Только для разработчика",
				body = "Тестовые кнопки работают у админов и владельца игры" })
		end
		return
	end

	if action == "setBalance" then
		local v = math.floor(tonumber(a) or 0)
		v = math.clamp(v, 0, 1e9)
		player:SetAttribute("Pirate", v)
		-- сторож баланса иначе примет это за чужую запись и вернёт прежнее число
		if _G.AcceptPirateBalance then _G.AcceptPirateBalance(player) end
		print(("[SettingsMenu] %s: баланс = %d"):format(player.Name, v))

	elseif action == "grant" then
		local key = tostring(a)
		local n = math.clamp(math.floor(tonumber(b) or 1), 1, 999)

		if STACKABLE[key] then
			if _G.AddResourceToInventory then
				_G.AddResourceToInventory(player, key, n, nil)
				print(("[SettingsMenu] %s: выдано %s x%d"):format(player.Name, key, n))
			end

		elseif key == "Torch" then
			local tpl = AssetFind.find("Torch")
			if tpl and tpl:IsA("Tool") then
				for _ = 1, math.min(n, 5) do -- не больше 5 факелов за раз (тулы, не стак)
					local tool = tpl:Clone()
					if _G.GiveToolOrDrop then
						_G.GiveToolOrDrop(player, tool)
					else
						tool.Parent = player:FindFirstChildOfClass("Backpack") or player.Character
					end
				end
				print(("[SettingsMenu] %s: выдано Torch x%d"):format(player.Name, math.min(n, 5)))
			end

		elseif key == "WaterBottle" then
		-- Бутылка собирается из модели заказчика (WaterBottleSystem) и работает как
		-- кружка: тот же CupState, те же действия с водой.
		local given = 0
		for _ = 1, math.min(n, 5) do
			if _G.GiveWaterBottle and _G.GiveWaterBottle(player) then given += 1 end
		end
		print(("[SettingsMenu] %s: выдано WaterBottle x%d"):format(player.Name, given))

	elseif key == "Ammo" then
			local guns = refillAmmo(player)
			print(("[SettingsMenu] %s: патроны пополнены на %d пушках"):format(player.Name, guns))

		elseif PLACEABLE_ICONS[key] then
			-- размещаемые тулы — ровно как их выдаёт RewardSystem после волны:
			-- пустой Tool с иконкой + невидимый Handle, ставится через CanonPlacer
			local ICONS = PLACEABLE_ICONS
			local count = math.min(n, 3)
			for _ = 1, count do
				local tool = Instance.new("Tool")
				tool.Name = key
				tool.CanBeDropped = false
				tool.TextureId = ICONS[key]
				local handle = Instance.new("Part")
				handle.Name = "Handle"
				handle.Size = Vector3.new(1, 1, 1)
				handle.Transparency = 1
				handle.Parent = tool
				if _G.GiveToolOrDrop then
					_G.GiveToolOrDrop(player, tool)
				else
					tool.Parent = player:FindFirstChildOfClass("Backpack") or player.Character
				end
			end
			if _G.SendInventory then _G.SendInventory(player) end
			print(("[SettingsMenu] %s: выдано %s x%d"):format(player.Name, key, count))

		elseif key == "Revolver" or key == "Pirate_Gun" then
			-- стрелковое — клоны авторских тулов из ReplicatedStorage (как BackPackPickUp)
			local src = AssetFind.find(key)
			if not src and key == "Pirate_Gun" then
				src = AssetFind.find("PirateGun")
			end
			if src and src:IsA("Tool") then
				local count = math.min(n, 3)
				for _ = 1, count do
					local tool = src:Clone()
					if _G.GiveToolOrDrop then
						_G.GiveToolOrDrop(player, tool)
					else
						tool.Parent = player:FindFirstChildOfClass("Backpack") or player.Character
					end
				end
				if _G.SendInventory then _G.SendInventory(player) end
				print(("[SettingsMenu] %s: выдано %s x%d"):format(player.Name, key, count))
			else
				warn("[SettingsMenu] шаблон " .. key .. " не найден в ReplicatedStorage")
			end
		end

	elseif action == "killRaft" then
		-- ТЕСТ: мгновенно уничтожить плот — через штатный _G.DamageRaft, чтобы
		-- отработал весь game-over флоу (экран «Плот пошёл ко дну», возрождение,
		-- уход в лобби). В отличие от RaftDamageTest НЕ обходит gameOver.
		if _G.DamageRaft then
			_G.DamageRaft(1e9)
			print(("[SettingsMenu] %s: плот уничтожен (тест анимаций)"):format(player.Name))
		else
			warn("[SettingsMenu] _G.DamageRaft не найден (RaftHealth.server.lua не загружен?)")
		end

	elseif action == "startNight" then
		-- ТЕСТ: перемотать сутки к началу ночи. Ждать полный день ради проверки
		-- ночной волны — 380 секунд, поэтому кнопка.
		-- a — номер дня: «ночь 7-го дня» проверяет поздние волны без семи
		-- реальных суток. Счётчик ставится ДО перемотки, чтобы волна и вывески
		-- увидели уже новый день; рекорды на таком сервере StartNightNow гасит.
		local day = math.floor(tonumber(a) or 0)
		-- ⚠️ 67 — ТАЙНЫЙ КОД: ночь пятого дня, а в волне только ледяной корабль
		-- (WaveDirector._G.SetSecretWave). По сути обычный день 5, просто волна другая.
		if day == 67 then
			day = 5
			if typeof(_G.SetSecretWave) == "function" then _G.SetSecretWave("frost") end
			print(("[SettingsMenu] %s: секретная волна — только ледяной корабль"):format(player.Name))
		end
		if day >= 1 and typeof(_G.SetDayCount) == "function" then
			_G.SetDayCount(day)
			print(("[SettingsMenu] %s: день переставлен на %d (тест)"):format(player.Name, day))
		end
		if _G.StartNightNow then
			local ok, why = _G.StartNightNow()
			print(("[SettingsMenu] %s: ночь сейчас — %s"):format(
				player.Name, ok and "запущена" or tostring(why)))
		else
			warn("[SettingsMenu] _G.StartNightNow не найден (DayNightCircle не загружен?)")
		end

	elseif action == "spawnPatrol" then
		-- ТЕСТ: выслать патрульный катер прямо сейчас, ПЕРЕД НОСОМ плота и близко.
		-- Штатно он приходит раз в 5–8 минут с горизонта — ждать этого ради проверки
		-- экипажа незачем. test = true ещё и убирает предыдущий катер, чтобы кнопка
		-- срабатывала каждый раз.
		if _G.SpawnPatrolBoat then
			local ok, why = _G.SpawnPatrolBoat({ test = true })
			print(("[SettingsMenu] %s: катер патруля — %s"):format(
				player.Name, ok and "вышел" or tostring(why)))
		else
			warn("[SettingsMenu] _G.SpawnPatrolBoat не найден (PiratePatrolBoat не загружен?)")
		end

	elseif action == "spawnCargo" then
		-- ТЕСТ: грузовой катер под обыск. Он подходит, глушит мотор и стоит, так что
		-- спавним его так же близко, как патрульный.
		if _G.SpawnCargoBoat then
			local ok, why = _G.SpawnCargoBoat({ test = true })
			print(("[SettingsMenu] %s: грузовой катер — %s"):format(
				player.Name, ok and "вышел" or tostring(why)))
		else
			warn("[SettingsMenu] _G.SpawnCargoBoat не найден (PiratePatrolBoat не загружен?)")
		end

	elseif action == "spawnTerraceIsle" then
		-- ТЕСТ: остров-терраса. Гарнизон, поле вируса и взрывоопасную перегонку
		-- расставляет TerraceIsland.server.lua по маркерам внутри модели.
		if _G.SpawnIsland then
			local ok, why = _G.SpawnIsland({ test = true, name = "TerraceIsle_SCENE" })
			print(("[SettingsMenu] %s: остров-терраса — %s"):format(
				player.Name, ok and "поднят" or tostring(why)))
		else
			warn("[SettingsMenu] _G.SpawnIsland не найден (WorldEventSpawner не загружен?)")
		end

	elseif action == "spawnFarmersIsle" then
		-- ТЕСТ: остров фермеров (пакет Farmers_Island_Transfer). Гарнизон из
		-- наших пиратов по площадкам ставит IslandCrews.
		if _G.SpawnIsland then
			local ok, why = _G.SpawnIsland({ test = true, name = "Farmers_Game_Water" })
			print(("[SettingsMenu] %s: остров фермеров — %s"):format(
				player.Name, ok and "поднят" or tostring(why)))
		else
			warn("[SettingsMenu] _G.SpawnIsland не найден (WorldEventSpawner не загружен?)")
		end

	elseif action == "spawnNetSheep" then
		-- ТЕСТ: овца для сеткомёта — ногами на поверхность в 8 студах перед игроком
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and typeof(_G.NetCaptureSpawn) == "function" then
			local from = hrp.Position + hrp.CFrame.LookVector * 8 + Vector3.new(0, 6, 0)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { char }
			local hit = workspace:Raycast(from, Vector3.new(0, -40, 0), params)
			local pos = hit and hit.Position or (hrp.Position + hrp.CFrame.LookVector * 8 - Vector3.new(0, 3, 0))
			local ok, why = _G.NetCaptureSpawn(pos)
			print(("[SettingsMenu] %s: овца для сеткомёта — %s"):format(player.Name, ok and "поставлена" or tostring(why)))
		else
			warn("[SettingsMenu] _G.NetCaptureSpawn не найден (NetCaptureServer не загружен?)")
		end

	elseif action == "spawnCrabIsle" then
		-- ТЕСТ: остров крабов (пакет ServerStorage.CrabIsland_Transfer) — 4 краба
		-- по маркерам CrabTransferSpawns и тестовая сабля в рюкзак (CrabIsland.server)
		if typeof(_G.CrabIslandSpawn) == "function" then
			local ok, why = _G.CrabIslandSpawn(player)
			print(("[SettingsMenu] %s: остров крабов — %s"):format(player.Name, ok and "поднят" or tostring(why)))
		else
			warn("[SettingsMenu] _G.CrabIslandSpawn не найден (CrabIsland.server не загружен?)")
		end

	elseif action == "grantDecorPack" then
		-- ТЕСТ: пак декора «Дефолт» (DecorPacks.server) — вкладка крафта с 11 предметами
		if typeof(_G.GrantDecorPack) == "function" then
			_G.GrantDecorPack(player, "Default")
		else
			warn("[SettingsMenu] _G.GrantDecorPack не найден (DecorPacks.server не загружен?)")
		end

	elseif action == "spawnCraterIsle" then
		-- ТЕСТ: забытый кратер (Crater_Island) — сторожа, крабы, 2 сундука
		if typeof(_G.CraterIslandSpawn) == "function" then
			local ok, why = _G.CraterIslandSpawn(player)
			if ok then
				print(("[SettingsMenu] %s: кратер поставлен"):format(player.Name))
			else
				warn("[SettingsMenu] кратер не поставлен: " .. tostring(why))
				if typeof(_G.NotifyPlayer) == "function" then
					_G.NotifyPlayer(player, { type = "warn", icon = "no", title = "Кратер не появился", body = tostring(why) })
				end
			end
		else
			warn("[SettingsMenu] _G.CraterIslandSpawn не найден (CrabIsland.server не загружен?)")
		end

	elseif action == "spawnShoalIsle" then
		-- ТЕСТ: песчаная отмель (пакет SandyShoal_Transfer) — 1 краб, 1 сундук
		if typeof(_G.ShoalIslandSpawn) == "function" then
			local ok, why = _G.ShoalIslandSpawn(player)
			print(("[SettingsMenu] %s: песчаная отмель — %s"):format(player.Name, ok and "поднята" or tostring(why)))
		else
			warn("[SettingsMenu] _G.ShoalIslandSpawn не найден (CrabIsland.server не загружен?)")
		end

	elseif action == "giveFishingSpot" then
		-- ТЕСТ: рыбацкое место — тул-заготовка, ставится как декор (DecorPlace)
		local tool = Instance.new("Tool")
		tool.Name = "Raft_fishing_spot"
		tool.CanBeDropped = false
		tool:SetAttribute("PreviewModel", "Raft_fishing_spot")   -- иконка — сама модель
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(1, 1, 1)
		handle.Transparency = 1
		handle.CanCollide = false
		handle.Massless = true
		handle.Parent = tool
		if typeof(_G.GiveToolOrDrop) == "function" then
			_G.GiveToolOrDrop(player, tool)
		else
			tool.Parent = player:FindFirstChildOfClass("Backpack")
		end
		print(("[SettingsMenu] %s: выдано рыбацкое место"):format(player.Name))

	elseif action == "skipToMerchant" then
		-- ТЕСТ: сюжет торговца — сразу день и время следующего визита (MerchantStory)
		local ok, a, b = false, "сюжет не загружен", nil
		if typeof(_G.MerchantStorySkipToVisit) == "function" then ok, a, b = _G.MerchantStorySkipToVisit() end
		if typeof(_G.NotifyPlayer) == "function" then
			_G.NotifyPlayer(player, ok
				and { type = "success", icon = "ok", title = "День " .. tostring(a) .. ", вечер", body = "Торговец сейчас поплывёт (" .. tostring(b) .. ")" }
				or { type = "warn", icon = "no", title = "Не перемотано", body = tostring(a) })
		end

	elseif action == "giveIslandHall" then
		-- ТЕСТ: таверна (IslandHall) — 2×2 на пол плота, ставит FarmBlockPlace
		if typeof(_G.GiveIslandHall) == "function" then _G.GiveIslandHall(player) end
		print(("[SettingsMenu] %s: выдана таверна"):format(player.Name))

	elseif action == "skipRecruit" then
		-- ТЕСТ: подготовка жителя в таверне — сразу готово (IslandHallService)
		local n = typeof(_G.IslandHallSkip) == "function" and _G.IslandHallSkip(player) or 0
		if typeof(_G.NotifyPlayer) == "function" then
			_G.NotifyPlayer(player, n > 0 and { type = "success", icon = "ok", title = "Житель готов", body = "Нажми «Получить жителя» на алтаре таверны" }
				or { type = "warn", icon = "no", title = "Нечего ускорять", body = "Нет таверны, которая готовит жителя" })
		end

	elseif action == "grantSurvivor" then
		-- ТЕСТ: выживший в команду (SurvivorService): "rose" | "pirate" | "coldcap"
		local NAMES = { rose = "Капитан Роза", pirate = "Пират Билли Шквал", coldcap = "Cold Cap" }
		local defId = NAMES[a] and a or "rose"
		local defName = NAMES[defId]
		local ok, why = false, "SurvivorService не загружен"
		if typeof(_G.GrantSurvivor) == "function" then ok, why = _G.GrantSurvivor(player, defId) end
		if typeof(_G.NotifyPlayer) == "function" then
			_G.NotifyPlayer(player, ok and { type = "success", icon = "ok", title = defName .. " в команде", body = "Кнопка «Команда» слева" }
				or { type = "warn", icon = "no", title = "Не добавлен", body = tostring(why) })
		end

	elseif action == "spawnMerchantYacht" then
		-- ТЕСТ: яхта торговца заново — прежний визит (если был) обрывается
		local ok, why = false, "MerchantShop.server не загружен"
		-- по сюжету (MerchantStory): с тем товаром и речью, что положены этапу истории
		if typeof(_G.MerchantStoryVisitNow) == "function" then ok, why = _G.MerchantStoryVisitNow()
		elseif typeof(_G.MerchantForceArrive) == "function" then ok, why = _G.MerchantForceArrive() end
		if typeof(_G.NotifyPlayer) == "function" then
			_G.NotifyPlayer(player, ok
				and { type = "success", icon = "ok", title = "Яхта торговца плывёт", body = "Подойдёт к борту плота через ~20 с" }
				or { type = "warn", icon = "no", title = "Яхта не вышла", body = tostring(why) })
		end
		print(("[SettingsMenu] %s: яхта торговца → %s"):format(player.Name, ok and "плывёт" or tostring(why)))

	elseif action == "spawnMerchant" then
		-- ТЕСТ: торговец приплывает (MerchantShop.server) и окно открывается нажавшему
		if typeof(_G.MerchantArrive) == "function" then
			-- яхта идёт к плоту ~20 с; лавка откроется по E у прилавка, когда встанет у борта
			local ok, why = _G.MerchantArrive()
			if typeof(_G.NotifyPlayer) == "function" then
				_G.NotifyPlayer(player, ok
					and { type = "success", icon = "ok", title = "Торговец плывёт", body = "Яхта подойдёт к борту плота" }
					or { type = "warn", icon = "no", title = "Торговец не приплыл", body = tostring(why) })
			end
			print(("[SettingsMenu] %s: торговец → %s"):format(player.Name, ok and "плывёт" or tostring(why)))
		else
			warn("[SettingsMenu] _G.MerchantArrive не найден (MerchantShop.server не загружен?)")
		end

	elseif action == "giveFarmBlock" then
		-- ТЕСТ: тул-заготовка блока фермы 2×2 (FarmBlockPlace.server)
		if typeof(_G.GiveFarmBlock) == "function" then
			_G.GiveFarmBlock(player)
			print(("[SettingsMenu] %s: выдан блок фермы"):format(player.Name))
		else
			warn("[SettingsMenu] _G.GiveFarmBlock не найден (FarmBlockPlace.server не загружен?)")
		end

	elseif action == "giveFarmerHut" then
		-- ТЕСТ: дом фермера (FarmBlockPlace.server → RaftFarmService)
		if typeof(_G.GiveFarmerHut) == "function" then
			_G.GiveFarmerHut(player)
			print(("[SettingsMenu] %s: выдан дом фермера"):format(player.Name))
		else
			warn("[SettingsMenu] _G.GiveFarmerHut не найден (FarmBlockPlace.server не загружен?)")
		end

	elseif action == "raidCourier" then
		-- ТЕСТ: лодочник с наградой рейда (RaidCourier) — стартует, когда игрок на плоту
		if typeof(_G.RequestRaidCourier) == "function" then
			local ok, why = _G.RequestRaidCourier(player, "тест из настроек")
			print(("[SettingsMenu] %s: лодочник — %s"):format(player.Name, ok and "в очереди" or tostring(why)))
		else
			warn("[SettingsMenu] _G.RequestRaidCourier не найден (RaidCourier не загружен?)")
		end

	elseif action == "spawnSkiff" then
		-- ТЕСТ: рыбацкая лодка. Мирная: проходит мимо плота и уходит, улов из
		-- сети можно забрать по прочтению.
		if _G.SpawnFishingSkiff then
			local ok, why = _G.SpawnFishingSkiff()
			print(("[SettingsMenu] %s: рыбацкая лодка — %s"):format(
				player.Name, ok and "вышла" or tostring(why)))
		else
			warn("[SettingsMenu] _G.SpawnFishingSkiff не найден (FishingSkiff не загружен?)")
		end

	elseif action == "spawnIsland" then
		-- ТЕСТ: поднять тропический остров прямо сейчас. Штатно он приходит раз в
		-- 5–7 минут и встаёт за 1800 студов — «еле видно на горизонте», и доплыть до
		-- него ради проверки долго. test = true ставит его ближе и по курсу.
		if _G.SpawnIsland then
			local ok, why = _G.SpawnIsland({ test = true, name = "TropicIsland_SCENE" })
			print(("[SettingsMenu] %s: тропический остров — %s"):format(
				player.Name, ok and "поднят" or tostring(why)))
		else
			warn("[SettingsMenu] _G.SpawnIsland не найден (WorldEventSpawner не загружен?)")
		end

	elseif action == "spawnShipIsle" then
		-- ТЕСТ: остров-верфь. Гарнизон из четверых, маршруты по маркерам и грядки
		-- вируса расставляет ShipIsle.server.lua по содержимому модели.
		if _G.SpawnIsland then
			local ok, why = _G.SpawnIsland({ test = true, name = "ShipIsle_SCENE" })
			print(("[SettingsMenu] %s: остров-верфь — %s"):format(
				player.Name, ok and "поднят" or tostring(why)))
		else
			warn("[SettingsMenu] _G.SpawnIsland не найден (WorldEventSpawner не загружен?)")
		end

	elseif action == "startIsleNow" then
		-- ТЕСТ: вся сцена стартового острова прямо сейчас. Штатно она играет на
		-- ВТОРОЙ день на 30% дня — это минут десять ожидания, и проверять по нему
		-- катсцену с квестами невозможно. Кнопка поднимает остров тем же кодом,
		-- что и расписание: катсцена, мысль, квест — всё на месте.
		if _G.StartIsleNow then
			local ok, why = _G.StartIsleNow()
			print(("[SettingsMenu] %s: стартовый остров — %s"):format(
				player.Name, ok and "поднят" or tostring(why)))
		else
			warn("[SettingsMenu] _G.StartIsleNow не найден (StartIsleStory не загрузился?)")
		end

	elseif action == "spawnOctopus" then
		-- ТЕСТ: поднять осьминога рядом с плотом прямо сейчас, не дожидаясь цикла.
		if _G.SpawnOctopus then
			local ok, why = _G.SpawnOctopus()
			print(("[SettingsMenu] %s: осьминог — %s"):format(
				player.Name, ok and "поднят" or tostring(why)))
		else
			warn("[SettingsMenu] _G.SpawnOctopus не найден (OctopusSpawner не загружен?)")
		end

	elseif action == "spawnSmallIsle" then
		-- ТЕСТ: малый остров. Двое пиратов с настоящими обходами и ребёнок в
		-- клетке — расставляет IslandCrews.server.lua по маркерам модели.
		if _G.SpawnIsland then
			local ok, why = _G.SpawnIsland({ test = true, name = "SmallIsle_SCENE" })
			print(("[SettingsMenu] %s: малый остров — %s"):format(
				player.Name, ok and "поднят" or tostring(why)))
		else
			warn("[SettingsMenu] _G.SpawnIsland не найден (WorldEventSpawner не загружен?)")
		end

	elseif action == "spawnPirateIsland" then
		-- ТЕСТ: пиратский лагерь. Гарнизон, пленных и живность расставляет
		-- PirateIsland.server.lua сам, по маркерам внутри модели.
		if _G.SpawnIsland then
			local ok, why = _G.SpawnIsland({ test = true, name = "PirateIsland_SCENE" })
			print(("[SettingsMenu] %s: пиратский остров — %s"):format(
				player.Name, ok and "поднят" or tostring(why)))
		else
			warn("[SettingsMenu] _G.SpawnIsland не найден (WorldEventSpawner не загружен?)")
		end

	elseif action == "outpostNow" then
		-- ТЕСТ: сцена острова-аванпоста целиком, не дожидаясь третьего дня.
		-- Катсцена, гарнизон, поле вируса и вся цепочка квестов — как в игре.
		if _G.OutpostIsleNow then
			local ok, why = _G.OutpostIsleNow()
			print(("[SettingsMenu] %s: аванпост — %s"):format(
				player.Name, ok and "поднят" or tostring(why)))
		else
			warn("[SettingsMenu] _G.OutpostIsleNow не найден (OutpostIsleStory не загрузился?)")
		end

	elseif action == "outpostMeet" then
		--[[ ТЕСТ: сразу к разговору с повстанцем.
		     ⚠️ ЕСЛИ ОСТРОВА ЕЩЁ НЕТ — ПОДНИМАЕМ ЕГО ЗДЕСЬ ЖЕ.
		     Повстанец выходит НА остров: без острова кнопка отвечала бы «ещё не
		     поднят», и тестировать разговор пришлось бы двумя нажатиями с
		     ожиданием между ними. Пауза — на то, чтобы модель успела встать в
		     мир, иначе встреча не найдёт, где земля. ]]
		if _G.OutpostMeetNow then
			task.spawn(function()
				if _G.OutpostIsleNow then pcall(_G.OutpostIsleNow) end
				task.wait(1.5)
				local ok, why = _G.OutpostMeetNow(player)
				-- пояснение печатаем и при успехе: чаще всего ответ здесь —
				-- «выйдет, когда игрок сойдёт на остров», и без него кнопка
				-- выглядит сработавшей вхолостую
				print(("[SettingsMenu] %s: встреча с повстанцем — %s%s"):format(
					player.Name, ok and "условия сняты" or "не вышло",
					(why ~= nil and why ~= "") and (" (" .. tostring(why) .. ")") or ""))
			end)
		else
			warn("[SettingsMenu] _G.OutpostMeetNow не найден (OutpostIsleStory не загрузился?)")
		end

	elseif action == "magmaTest" then
		-- ТЕСТ: шар магмы падает прямо на игрока. Штатно этим бьёт огненный
		-- корабль, но ждать его волну ради того, чтобы посмотреть удар, — полдня.
		-- Летит и рвётся тем же кодом, что боевой снаряд: осколки, столб огня и
		-- горящая лужа один в один. Урона от попадания нет, лужа палубу жжёт.
		if _G.MagmaTestStrike then
			local ok, why = _G.MagmaTestStrike(player)
			print(("[SettingsMenu] %s: магма — %s"):format(
				player.Name, ok and "сброшена" or tostring(why)))
		else
			warn("[SettingsMenu] _G.MagmaTestStrike не найден (ShipCombat не загрузился?)")
		end
	end
end)

print("[SettingsMenuActions] ready")
