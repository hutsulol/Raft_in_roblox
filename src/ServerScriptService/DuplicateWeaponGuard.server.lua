-- DuplicateWeaponGuard.server.lua
-- ОДИН ствол на игрока — не два.
--
-- Оружие приходит из BackPackPickUp.giveStarterGuns — свои Revolver/PirateGun/
-- Torch при подборе рюкзака (клоны шаблонов из ReplicatedStorage). Плюс
-- KeepToolsOnDeath возвращает пережившие смерть тулы через StarterGear.
--
-- Раньше был и второй источник: StarterPack.Pirate_Gun, который Roblox выдавал
-- сам на КАЖДОМ спавне. Его создавал не скрипт, а сам Rojo — узел был объявлен в
-- default.project.json и восстанавливался при каждой синхронизации, сколько его
-- ни удаляй из Explorer. Причём без Handle: узел содержал одну папку Scripts,
-- отсюда «Infinite yield ... Pirate_Gun:WaitForChild("Handle")» в логе. Узел
-- убран, но сама уборка дубликатов нужна и дальше — из-за StarterGear.
--
-- Два ОДИНАКОВЫХ тула в инвентаре не уживаются: внутри каждого свои клиентские
-- скрипты, и второй экземпляр перебивает первому биндинги —
-- ContextActionService:BindAction("PirateGunReload", ...) во FrontendScript и
-- ScreenGui с тем же именем в GUIScript. Снаружи это выглядит как «один ствол
-- нормальный, второй не работает».
--
-- Скрипт не решает, какой источник правильный (оба нужны в своих сценариях), а
-- просто оставляет ОДИН экземпляр каждого оружия — самый полный. Обычные предметы
-- (еда, ресурсы, стройка) не трогаются: они складываются штуками, и дубликаты у
-- них законны.

local Players = game:GetService("Players")

-- Ключ = имя без счётчика патронов и без подчёркиваний: Revolver (6) → Revolver,
-- Pirate_Gun и PirateGun → PirateGun (это один и тот же ствол под двумя именами).
local WATCH = { PirateGun = true, Revolver = true, Torch = true }

local function weaponKey(tool)
	local n = tool.Name:gsub("%s*%(%d+%)%s*$", ""):gsub("_", "")
	return WATCH[n] and n or nil
end

-- «Полнота» тула: с ручкой и с большим числом потрохов — тот, что реально рабочий.
-- Пустышка (Tool без Handle и скриптов) проигрывает всегда. Экипированный выигрывает
-- при прочих равных: убирать предмет прямо из рук — худший вариант из возможных.
local function completeness(tool, equipped)
	local n = #tool:GetDescendants()
	if tool:FindFirstChild("Handle") then n += 1000 end
	if equipped then n += 1 end
	return n
end

-- Чистим СПИСОК тулов, а не контейнер: рюкзак и руки — один инвентарь, но
-- перекладывать их между собой нельзя. Экипировка в Roblox и есть перенос тула из
-- рюкзака в персонажа, так что любое «выравнивание по рюкзаку» = мгновенный
-- расэкип: игрок жмёт слот, а предмет тут же уходит назад.
local function sweepList(list)
	local best, bestScore, drop = {}, {}, {}
	for _, e in ipairs(list) do
		local key = weaponKey(e.tool)
		if key then
			local score = completeness(e.tool, e.equipped)
			if not best[key] then
				best[key], bestScore[key] = e.tool, score
			elseif score > bestScore[key] then
				table.insert(drop, best[key])
				best[key], bestScore[key] = e.tool, score
			else
				table.insert(drop, e.tool)
			end
		end
	end
	for _, t in ipairs(drop) do
		print(("[WeaponGuard] убран дубликат %s (%d потрохов, Handle=%s)")
			:format(t.Name, #t:GetDescendants(), tostring(t:FindFirstChild("Handle") ~= nil)))
		t:Destroy()
	end
end

local function sweepPlayer(player)
	local list = {}
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then
		for _, t in ipairs(bp:GetChildren()) do
			if t:IsA("Tool") then table.insert(list, { tool = t, equipped = false }) end
		end
	end
	local char = player.Character
	if char then
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") then table.insert(list, { tool = t, equipped = true }) end
		end
	end
	sweepList(list)

	-- StarterGear чистим отдельно: иначе дубликат вернётся после смерти
	local sg = player:FindFirstChild("StarterGear")
	if sg then
		local sl = {}
		for _, t in ipairs(sg:GetChildren()) do
			if t:IsA("Tool") then table.insert(sl, { tool = t, equipped = false }) end
		end
		sweepList(sl)
	end
end

-- Выдача идёт пачкой (StarterPack, потом три тула из рюкзака), поэтому не бросаемся
-- на каждый ChildAdded, а откладываем разбор на конец кадра.
local function watch(player)
	local pending = false
	local function queue()
		if pending then return end
		pending = true
		task.delay(0.25, function()
			pending = false
			pcall(sweepPlayer, player)
		end)
	end

	local function hook(container)
		if container then container.ChildAdded:Connect(queue) end
	end

	hook(player:FindFirstChildOfClass("Backpack"))
	player.ChildAdded:Connect(function(c)
		if c:IsA("Backpack") or c:IsA("StarterGear") then
			hook(c)
			queue()
		end
	end)
	player.CharacterAdded:Connect(function(char)
		hook(char)
		queue()
	end)
	if player.Character then hook(player.Character) end
	queue()
end

Players.PlayerAdded:Connect(watch)
for _, p in ipairs(Players:GetPlayers()) do watch(p) end

print("[WeaponGuard] ready")
