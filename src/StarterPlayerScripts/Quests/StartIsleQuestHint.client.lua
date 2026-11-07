local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ПОДСКАЗКА КВЕСТА «ДИКАЯ КОРОВА» (startisle_cow).

	Кнопка «?» на HUD-трекере подсвечивает золотым контуром корову, а когда она
	добыта — упавшее с неё мясо.

	⚠️ У «ЗЕМЛИ ПО КУРСУ» ПОДСКАЗКИ НЕТ, И ЭТО НАРОЧНО.
	Сначала она подсвечивала остров целиком — контур на всю скалу с рельефом,
	сквозь стены, во весь экран. Искать там нечего: остров и так стоит прямо по
	курсу и виден с плота, а золотая глыба на пол-горизонта только мешает
	смотреть. У этого квеста «?» просто открывает меню квестов, как у любого
	другого квеста без своей подсказки.

	⚠️ У «МЯСА НА УГЛЯХ» ПОДСКАЗКА СВОЯ, ОТДЕЛЬНЫМ ФАЙЛОМ.
	Там не «подсветить предмет», а провести по шагам: собрать мангал, поставить,
	разжечь, положить мясо. Это другой каркас — кольцо по элементам интерфейса и
	баннер с текстом шага, как у молотка (см. StartIsleGrillHint.client.lua).

	⚠️ ЦЕЛЬ У КВЕСТА ОДНА, НО ПО ХОДУ ДЕЛА МЕНЯЕТСЯ.
	Живая корова превращается в лежащее мясо, и подсветка должна перейти на него.

	⚠️ ЦЕЛЬ ИЩЕМ ЗАНОВО, А НЕ ОДИН РАЗ.
	Цели в мире может ещё не быть, когда подсказку включают, и она меняется по
	ходу: корова умирает и оборачивается дропом. Поэтому пока подсказка горит —
	переспрашиваем мир раз в полсекунды.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local GOLD = Color3.fromRGB(255, 210, 58)
local RESCAN = 0.5     -- как часто переспрашиваем мир, пока подсказка горит

local ISLAND_NAME = "StartIsle_SCENE"
local COW_NAME    = "Cow_Cow_1"

local COW_ID   = "startisle_cow"

local questStateEvent = ReplicatedStorage:WaitForChild("QuestState", 30)

-- [questId] = true, пока квест виден в снапшоте и не закрыт
local questVisible = {}
-- [questId] = true, пока подсказка горит
local enabled = {}

-- ── пул подсветок ──
-- Целей может быть больше одной: с коровы падает два куска мяса, и подсветить
-- только первый значит соврать. Highlight'ы переиспользуем, а не создаём заново:
-- движок рисует ограниченное их число, и мусор из старых съедает лимит.
local pool = {}

local function highlight(targets)
	for i, inst in ipairs(targets) do
		local h = pool[i]
		if not h then
			h = Instance.new("Highlight")
			h.Name = "StartIsleHintGlow"
			h.FillColor = GOLD
			h.FillTransparency = 0.75
			h.OutlineColor = GOLD
			h.OutlineTransparency = 0
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.Parent = Workspace
			pool[i] = h
		end
		h.Adornee = inst
		h.Enabled = true
	end
	-- лишние гасим, но не уничтожаем
	for i = #targets + 1, #pool do
		pool[i].Adornee = nil
		pool[i].Enabled = false
	end
end

-- ── поиск целей ──
local function findIsland()
	local m = Workspace:FindFirstChild(ISLAND_NAME)
	return (m and m:IsA("Model")) and m or nil
end

local function findCow()
	local island = findIsland()
	local animals = island and island:FindFirstChild("Animals")
	local cow = animals and animals:FindFirstChild(COW_NAME)
	if not cow then return nil end
	-- мёртвую подсвечивать незачем: цель сместилась на то, что с неё упало
	local hum = cow:FindFirstChildWhichIsA("Humanoid")
	if hum and hum.Health <= 0 then return nil end
	return cow
end

-- Мясо, упавшее с туши. Дроп кладут в саму модель острова (см. spawnDrops в
-- AnimalLife), поэтому ищем там, а не по всему миру: на плоту может лежать
-- выброшенный кусок, и подсказка увела бы игрока обратно на плот.
local function findMeatDrops()
	local island = findIsland()
	if not island then return {} end
	local found = {}
	for _, d in ipairs(island:GetChildren()) do
		if d.Name == "Meat" or d.Name:sub(1, 5) == "Meat_" then
			table.insert(found, d)
		end
	end
	return found
end

-- Что подсвечивать. Возвращает список целей — пустой значит «цели в мире сейчас
-- нет», и это не ошибка: остров ещё не всплыл или мясо уже подобрали.
local function targetsFor(questId)
	if questId == COW_ID then
		local cow = findCow()
		if cow then return { cow } end
		return findMeatDrops()
	end
	return {}
end

local function apply()
	local targets = {}
	for questId, on in pairs(enabled) do
		if on then
			for _, t in ipairs(targetsFor(questId)) do
				table.insert(targets, t)
			end
		end
	end
	highlight(targets)
end

-- ── общий цикл переспроса ──
task.spawn(function()
	while true do
		task.wait(RESCAN)
		local any = false
		for _, on in pairs(enabled) do
			if on then any = true break end
		end
		if any then apply() end
	end
end)

-- ── состояние квестов ──
if questStateEvent then
	questStateEvent.OnClientEvent:Connect(function(action, payload)
		if action ~= "state" or type(payload) ~= "table" then return end

		local seen = {}
		for _, q in ipairs(payload.quests or {}) do
			if q.id == COW_ID then
				seen[q.id] = true
				questVisible[q.id] = not ((q.completed == true) or (q.rewardPending == true))
			end
		end
		for _, id in ipairs({ COW_ID }) do
			if not seen[id] then questVisible[id] = false end
			-- квест закрыт или пропал из списка: его подсветка гаснет сама
			if enabled[id] and not questVisible[id] then enabled[id] = false end
		end
		apply()
	end)
end

-- ── ручки для трекера ──
-- Имена должны совпадать с таблицей HINTS в TrackerCard.client.lua.
local function makeHandles(questId, setName, getName, onEnable)
	_G[setName] = function(on)
		if on and not questVisible[questId] then
			enabled[questId] = false
			apply()
			return
		end
		enabled[questId] = on and true or false
		if enabled[questId] and onEnable then onEnable() end
		apply()
	end
	_G[getName] = function() return enabled[questId] == true end
end

makeHandles(COW_ID,   "StartIsleCowHintSetEnabled",   "StartIsleCowHintEnabled")

print("[StartIsleHint] подсказка «Дикая корова» готова («?» на трекере)")
