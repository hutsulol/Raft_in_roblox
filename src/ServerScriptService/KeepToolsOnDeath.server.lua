-- KeepToolsOnDeath.server.lua
-- СОХРАНИТЬ ИНСТРУМЕНТЫ ПРИ СМЕРТИ.
--
-- ⚠️ ГЛАВНОЕ, ЧТО ЗДЕСЬ НАДО ПОНИМАТЬ ПРО ROBLOX:
-- рюкзак игрока (Backpack) при респавне НЕ переживает смерть. Движок удаляет
-- его вместе со старым персонажем и создаёт заново, наполняя из StarterPack и
-- StarterGear. Всё, что игрок подобрал по ходу игры и что лежало только в
-- Backpack, пропадает — как и то, что было в руках (экипированный Tool вообще
-- лежит внутри модели персонажа и удаляется вместе с ней).
--
-- Поэтому одного «вернуть из рук в рюкзак» мало — это была первая, неверная
-- версия этого скрипта. Работает так: в момент смерти снимаем всё с рук, а
-- затем СНИМАЕМ СЛЕПОК рюкзака в StarterGear — именно из него движок наполнит
-- новый рюкзак после возрождения.
--
-- Чего в слепок НЕ кладём:
--   • тулы из StarterPack — движок и так выдаёт их каждый респавн, копия дала
--     бы дубликат;
--   • еду и семена, «одолженные» из стака: их возвращает в инвентарь FoodSystem
--     (refundFood), и копия превратилась бы в дублирование ресурса;
--   • переносимые постройки (RelocateItem) — они лежат на складе сервера,
--     клонировать их нельзя.

local Players = game:GetService("Players")
local StarterPack = game:GetService("StarterPack")

local LOG_TAG = "[KeepTools]"

local function inStarterPack(name)
	for _, d in ipairs(StarterPack:GetChildren()) do
		if d:IsA("Tool") and d.Name == name then return true end
	end
	return false
end

-- Тул, который имеет смысл переносить через смерть.
local function keepable(tool)
	if not tool:IsA("Tool") then return false end
	if tool:GetAttribute("FoodResource") then return false end
	if tool:GetAttribute("BushSeedResource") then return false end
	if tool:GetAttribute("RelocateItem") then return false end
	if inStarterPack(tool.Name) then return false end
	return true
end

-- ⚠️ СЛЕПОК СНИМАЕТСЯ БЕЗ ЕДИНОГО YIELD.
--
-- В первой версии я до слепка делал UnequipTools и task.wait() — и терял почти
-- всё: движок начинает разбирать рюкзак сразу после смерти, а за время
-- ожидания часть тулов успевала исчезнуть. Спасалось то, что осталось, — по
-- логу это было 2 предмета из целого набора.
--
-- Поэтому сначала синхронно копируем ВСЁ (и рюкзак, и то, что в руках), и лишь
-- потом занимаемся возвратами. Ожидание кадра ради еды не нужно: одолженные из
-- стака тулы отсеиваются по атрибуту, а не по тому, успел ли их вернуть
-- FoodSystem.
local function rescueTools(player, character)
	local gear = player:FindFirstChildOfClass("StarterGear")
	if not gear then
		warn(LOG_TAG .. " у " .. player.Name .. " нет StarterGear — переносить некуда")
		return
	end

	-- Слепок каждый раз ПОЛНЫЙ: иначе накопились бы копии от прошлых смертей.
	gear:ClearAllChildren()

	local saved, skipped = {}, {}
	local function take(container)
		if not container then return end
		for _, t in ipairs(container:GetChildren()) do
			if t:IsA("Tool") then
				if keepable(t) then
					-- Archivable правим локально: без него Clone() вернёт nil.
					if not t.Archivable then t.Archivable = true end
					local ok, clone = pcall(function() return t:Clone() end)
					if ok and clone then
						clone.Parent = gear
						table.insert(saved, t.Name)
					else
						table.insert(skipped, t.Name .. " (клон не вышел)")
					end
				else
					table.insert(skipped, t.Name)
				end
			end
		end
	end

	take(player:FindFirstChildOfClass("Backpack"))
	take(character) -- то, что было в руках: снять его мы ещё не успели

	print(("%s %s: перенесено [%s] | пропущено [%s]"):format(
		LOG_TAG, player.Name,
		table.concat(saved, ", "), table.concat(skipped, ", ")))

	-- Теперь можно и разоружить: еда вернётся в стак через FoodSystem, а в
	-- слепок она не попала — он уже снят.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function() humanoid:UnequipTools() end)
	end
end

local function watch(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end
		humanoid.Died:Connect(function()
			rescueTools(player, character)
		end)
	end)
end

Players.PlayerAdded:Connect(watch)
for _, p in ipairs(Players:GetPlayers()) do
	watch(p)
	-- Игрок мог зайти до старта скрипта — цепляемся к уже живому персонажу.
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function() rescueTools(p, char) end)
	end
end

print(LOG_TAG .. " ready (слепок рюкзака в StarterGear при смерти)")
