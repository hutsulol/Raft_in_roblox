--[[
	ПАКИ ДЕКОРА: право крафтить набор предметов (вкладка крафта открывается
	только владельцу пака).

	Пак «Дефолт» — RaftDecor_all (ReplicatedStorage): гирлянда, цветок в банке,
	шезлонг, фонарь, спасательный круг, коврик, полка, указатель, стол-катушка,
	табурет, штурвал. Рецепты — InventoryCrafting (category = "DecorPack",
	requires = "DecorPack_Default"), установка — DecorPlace.

	Владение — атрибут игрока DecorPack_<Имя> (его читают вкладка инвентаря и
	проверка крафта на сервере) и запись в DataStore, чтобы пак не терялся между
	заходами. Сейчас пак выдаёт кнопка админа в настройках (_G.GrantDecorPack);
	позже сюда же пойдёт покупка за Robux.
]]

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local LOG = "[Паки декора]"
local PACKS = { Default = true }

--[[ ⚠️ МОДЕЛИ ПАКА — В ReplicatedStorage. Сервер (DecorPlace) и иконки крафта
     ищут их только там; пак, оставленный в Workspace, давал «шаблона … нет» —
     предмет крафтился, но не ставился, иконок не было, а сами модели плавали в
     море. Если пак лежит в мире — переносим его сами, один раз при старте. ]]
local PACK_MODELS = { "RaftDecor_all" }
local ReplicatedStorage = game:GetService("ReplicatedStorage")
for _, name in ipairs(PACK_MODELS) do
	local inWorld = workspace:FindFirstChild(name)
	if inWorld and not ReplicatedStorage:FindFirstChild(name) then
		inWorld.Parent = ReplicatedStorage
		print(("%s %s перенесён из Workspace в ReplicatedStorage"):format(LOG, name))
	elseif not ReplicatedStorage:FindFirstChild(name) then
		warn(("%s нет модели %s ни в ReplicatedStorage, ни в Workspace — предметы пака не поставятся"):format(LOG, name))
	end
end

local store
pcall(function() store = DataStoreService:GetDataStore("DecorPacksV1") end)

local function key(player) return "u_" .. player.UserId end

local function apply(player, owned)
	for name in pairs(PACKS) do
		player:SetAttribute("DecorPack_" .. name, owned[name] == true or nil)
	end
end

--[[ DecorPacksLoaded — «владение паками уже прочитано». Его ждёт выдача пака из
     ежедневки лобби (PirateProgression): иначе она не знает, есть ли пак, и
     показывала бы «пак получен» тому, у кого он давно есть. ]]
local function load(player)
	if store then
		local ok, data = pcall(function() return store:GetAsync(key(player)) end)
		if ok and type(data) == "table" then apply(player, data) end
	end
	player:SetAttribute("DecorPacksLoaded", true)
end
Players.PlayerAdded:Connect(load)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(load, p) end

-- выдать пак (кнопка админа; дальше — покупка)
_G.GrantDecorPack = function(player, name)
	name = name or "Default"
	if not PACKS[name] then return false, "нет такого пака" end
	player:SetAttribute("DecorPack_" .. name, true)
	if store then
		task.spawn(function()
			pcall(function()
				store:UpdateAsync(key(player), function(old)
					old = type(old) == "table" and old or {}
					old[name] = true
					return old
				end)
			end)
		end)
	end
	if typeof(_G.NotifyPlayer) == "function" then
		_G.NotifyPlayer(player, { type = "success", icon = "ok", title = "Пак «Дефолт» получен",
			body = "В крафте появилась вкладка «Пак: Дефолт» — декор для плота" })
	end
	print(("%s %s получил пак %s"):format(LOG, player.Name, name))
	return true
end

print(LOG .. " готово: DecorPack_<Имя> на игроке, пак «Дефолт» — RaftDecor_all")
