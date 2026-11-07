--[[
	РЫБАЦКОЕ МЕСТО НА ПЛОТУ (Raft_fishing_spot) — кто на нём работает.

	Логика вылова, анимации и выплата — FishingService (пакет Fisherman_R6).
	Здесь только запуск станции на каждом месте, которое стоит на плоту:
	  • рыбачит ТОЛЬКО назначенный житель: игрок ставит его в окне «Команда»
	    (SurvivorService), на модели места атрибуты WorkerModel / WorkerName —
	    рыбачит модель этого выжившего; без жителя станция стоит пустой (FishingService принимает любой R6/R15-шаблон, позы
	    адаптирует FishingRig). Атрибуты сохраняются вместе с плотом.

	API для выживших:
	  _G.RaftFishingList() — места на плоту { spot, id, npc }
	  _G.RaftFishingRespawn(spot) — сменить работника по атрибутам места
]]

local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Service = require(RS:WaitForChild("FishingService"))
local C = require(RS:WaitForChild("FishingConfig"))
RS:WaitForChild(C.TemplateName)
RS:WaitForChild("FishermanFish")

local spots = {}   -- [spot] = true — места, которые мы знаем

-- шаблон работника: выживший (без оружия в руках) или обычный рыбак
local function options(spot)
	local want = spot:GetAttribute("WorkerModel")
	if type(want) == "string" and want ~= "" and typeof(_G.SurvivorWorkerTemplate) == "function" then
		local tpl = _G.SurvivorWorkerTemplate(want)
		if tpl then return { Template = tpl }, true end
		warn("[Fishing] модели выжившего «" .. want .. "» нет — рыбачит обычный рыбак")
	end
	return nil, false
end

local function launch(spot)
	if Service.get(spot) then return end
	if spot:GetAttribute("Building") then return end   -- идёт улучшение (BuildingUpgradeServer): запустит по окончании
	--[[ ⚠️ БЕЗ ЖИТЕЛЯ СТАНЦИЯ ПУСТАЯ. Раньше на любом поставленном месте сразу
	     работал нанятый рыбак (Fisher_R6). Теперь рыбачит только житель, которого
	     назначили в «Команде» (WorkerModel пишет SurvivorService): сюжет торговца
	     на этом и построен — поставил место, а рыбачить некому. ]]
	local want = spot:GetAttribute("WorkerModel")
	if type(want) ~= "string" or want == "" then return end
	-- станция с уровнями: сначала BuildingUpgradeServer выставит уровень (какая катушка
	-- видна), иначе рыбак взял бы удочку уровня 0. Он сам перезапустит станцию.
	if spot:FindFirstChild("PermanentBase") and not game:GetService("CollectionService"):HasTag(spot, "UpgradableBuilding") then return end
	local opts, isSurvivor = options(spot)
	local ok, res = pcall(Service.start, spot, opts)
	if not ok then warn("[Fishing] " .. tostring(res)) return end
	if res and res.npc then
		if isSurvivor then
			res.npc:SetAttribute("Role", spot:GetAttribute("WorkerName") or "ВЫЖИВШИЙ")
			res.npc:SetAttribute("SurvivorFace", true)   -- мимика лица (SurvivorsUI.client)
			res.npc:SetAttribute("SurvivorWorker", spot:GetAttribute("WorkerModel"))
		end
	end
end

local function register(m)
	if not m:IsA("Model") or m.Name ~= C.ModelName then return end
	task.defer(function()
		if not m:IsDescendantOf(workspace) then return end
		local raft = workspace:FindFirstChild("Raft")
		if not raft or not m:IsDescendantOf(raft) then return end
		if m:GetAttribute("PlacementGhost") then return end
		if not m:FindFirstChild("wp_sit", true) or not m:FindFirstChild("wp_sit_look", true)
			or not m:FindFirstChild("wp_rod_grip", true) or not Service.hasRod(m) then
			return
		end
		if not m:GetAttribute("SpotId") then m:SetAttribute("SpotId", HttpService:GenerateGUID(false):sub(1, 8)) end
		spots[m] = true
		launch(m)
	end)
end
workspace.DescendantAdded:Connect(register)
for _, m in ipairs(workspace:GetDescendants()) do register(m) end
-- Models can arrive before their descendants during loading/synchronization.
task.spawn(function()
	while true do
		task.wait(5)
		local raft = workspace:FindFirstChild("Raft")
		if raft then for _, m in ipairs(raft:GetDescendants()) do register(m) end end
	end
end)

_G.RaftFishingList = function()
	local out = {}
	for spot in pairs(spots) do
		if spot.Parent and spot:IsDescendantOf(workspace) then
			local s = Service.get(spot)
			table.insert(out, { spot = spot, id = spot:GetAttribute("SpotId"), npc = s and s.npc or nil })
		else
			spots[spot] = nil
		end
	end
	return out
end

--[[ Сменить уровень станции, не снимая рыбака с плота: он отпускает удочку и
     берёт копию с деталей нового уровня. Зовётся ПОСЛЕ L.apply (детали уже
     переключены). Возвращает false, если станции нет — тогда зовущий может
     откатиться на полный перезапуск. ]]
_G.RaftFishingRelevel = function(spot)
	if not (typeof(spot) == "Instance" and spots[spot]) then return false end
	local s = Service.get(spot)
	if not (s and s.relevel) then return false end
	local ok, res = pcall(function() return s:relevel() end)
	if not ok then warn("[Fishing] смена уровня: " .. tostring(res)) return false end
	return res ~= false
end

--[[ Сменить работника: останавливаем станцию (её цикл гаснет на ближайшем
     ожидании, рыбак и временные предметы убираются, удочка возвращается на
     место) и, когда она освободилась, запускаем заново по атрибутам. ]]
_G.RaftFishingRespawn = function(spot)
	if not (typeof(spot) == "Instance" and spots[spot]) then return false end
	local s = Service.get(spot)
	if s then s:stop() end
	task.spawn(function()
		for _ = 1, 100 do
			if not Service.get(spot) then break end
			task.wait(0.1)
		end
		if spot.Parent then launch(spot) end
	end)
	return true
end
