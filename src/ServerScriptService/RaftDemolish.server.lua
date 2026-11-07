-- RaftDemolish.server.lua
-- РАЗБОР ПЛОТА ТОПОРОМ (как в Raft): удары топором по постройке или по клетке
-- пола ломают её. Над целью, пока по ней бьют, висит полоска прочности; когда
-- она кончается — объект исчезает СРАЗУ, без анимации падения.
--
-- Прочность живёт в атрибуте DemolishHP и СБРАСЫВАЕТСЯ, если по цели не били
-- DECAY_AFTER секунд. Это сделано намеренно: у построек уже есть своя прочность
-- ObstacleHP — её грызут абордажники, а механик её ремонтирует. Если бы разбор
-- шёл по тому же счётчику, механик молча «залечивал» бы то, что игрок ломает.
--
-- Пол разбирается через RaftDetach: вместе с клеткой уходит всё, что держалось
-- только через неё, иначе в море оставались бы висеть отрезанные доски.
--
-- Клиент (StoneAxeClient) присылает деталь, по которой кликнул; выбор цели,
-- проверку дистанции и весь урон считает сервер.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LOG_TAG = "[RaftDemolish]"

-- ─── Настройки ────────────────────────────────────────────────────
local DAMAGE_PER_HIT = 20
local HP_FLOOR       = 60    -- прочность клетки пола
local HP_BUILDING    = 80    -- прочность постройки
local HIT_RANGE      = 20
-- КД и задержка попадания — те же, что у топора по живым целям (AxeCombat).
-- КД теперь на ИГРОКА, а не на цель: при 0.35 на цель быстрые клики засчитывали
-- два удара за один взмах, а по соседним постройкам можно было лупить вообще без
-- перерыва. Задержка отодвигает урон к моменту, где по анимации лезвие доходит.
local HIT_COOLDOWN   = 0.8   -- минимум между ударами игрока
local HIT_DELAY      = 0.7   -- через сколько после замаха засчитывается урон
local DECAY_AFTER    = 6     -- через сколько секунд без удара прочность восстановится

-- общий список топоров на весь проект (ReplicatedStorage.AxeTools)
local AxeTools = require(game:GetService("ReplicatedStorage"):WaitForChild("AxeTools"))
local AXE_TOOLS = setmetatable({}, { __index = function(_, name)
	return AxeTools.isAxeName(name) or nil
end })

-- Что ломать НЕЛЬЗЯ ни при каких условиях: сюжетные и служебные объекты.
local PROTECTED = {
	monolit_aquamen = true, monolith = true,
}
local function isProtected(model)
	local n = model.Name:lower()
	if PROTECTED[n] then return true end
	if n:find("board") or n:find("community") then return true end -- доска объявлений
	if n:find("monolit") then return true end
	if model:GetAttribute("NoDemolish") then return true end
	return false
end

local FLOOR_NAMES = { Raft_part = true, Net_Part = true }
local function isFloorTile(model)
	return FLOOR_NAMES[model.Name] or model:GetAttribute("BuildType") == "raft"
end

local hitEvent = ReplicatedStorage:FindFirstChild("RaftDemolish")
if not hitEvent then
	hitEvent = Instance.new("RemoteEvent")
	hitEvent.Name = "RaftDemolish"
	hitEvent.Parent = ReplicatedStorage
end

local function raft() return workspace:FindFirstChild("Raft") end

-- ─── Цель разбора: прямой ребёнок плота, которому принадлежит деталь ──
local function demolishTargetOf(part)
	local r = raft()
	if not r or not part or not part:IsDescendantOf(r) then return nil end
	local node = part
	while node.Parent and node.Parent ~= r do
		node = node.Parent
	end
	if node.Parent ~= r then return nil end
	if node == r.PrimaryPart then return nil end -- сам корень плота
	if isProtected(node) then return nil end
	return node
end

--[[ ⚠️ СТАРТОВЫЙ ПЛОТ ЛОМАТЬ НЕЛЬЗЯ — ВЕСЬ, А НЕ ТОЛЬКО ЯДРО.
     Раньше защищалась одна клетка под PrimaryPart. Игрок разобрал остальные
     восемь и остался на одной доске, которая ни плывёт толком, ни тонет,
     — «зависли и не тонут». Владелец решил: девять досок, с которыми плот
     приходит, неприкосновенны; ломать можно только то, что поставил сам.

     ⚠️ ПОЧЕМУ НЕ МЕТКА НА ДОСКЕ И НЕ СПИСОК КЛЕТОК ИЗ ГОЛОВЫ.
     Метка на модели не переживает загрузку сейва: RaftSaveSystem пересоздаёт
     доски из данных заново, и метка бы пропала. Список «клетки от −1 до 1»
     держится на догадке, что PrimaryPart стоит в центре, — а стартовую
     модель могут перерисовать. Поэтому при запуске сервера ЗАПОМИНАЕМ
     ПРЯМОУГОЛЬНИК, который занимают доски в этот момент, в системе координат
     плота (в покое, без крена). Любая доска, чей центр попадает в него, —
     стартовая, откуда бы она ни взялась: из модели или из сейва.
     Строить игрок в эти секунды ещё не может (молоток надо скрафтить),
     так что снимок — это ровно стартовая модель.
     Прямоугольник публикуется атрибутами плота: по ним клиент топора
     не подсвечивает стартовые доски как цель. ]]
local GRID = 10                 -- шаг клетки, как в BuildingSystem
local STARTER_PAD = GRID * 0.5 + 1.5   -- полклетки + допуск на люфт
local starterBox = nil          -- { minX, maxX, minZ, maxZ } в кадре покоя

-- кадр плота в покое: позиция PrimaryPart, поворот только вокруг вертикали
local function restFrame(rp)
	local yaw = rp:GetAttribute("RestYaw")
	if type(yaw) ~= "number" then
		local _, y = rp.CFrame:ToEulerAnglesYXZ()
		yaw = y
	end
	return CFrame.new(rp.Position) * CFrame.Angles(0, yaw, 0)
end

--[[ ⚠️ ЦЕНТР — ПО ДЕТАЛЯМ, А НЕ ПО ПИВОТУ.
     У модели без PrimaryPart GetPivot возвращает сохранённый WorldPivot, и он
     НЕ едет за физикой: плот отплыл, а пивот двух клеток (центральной и той,
     что под монолитом) остался на месте старта — и они «выпали» из
     защищённого прямоугольника, их снова можно было сломать. GetBoundingBox
     считает по настоящим позициям деталей. ]]
local function centreOf(model)
	if model:IsA("Model") then
		local ok, cf = pcall(function() return model:GetBoundingBox() end)
		if ok and cf then return cf.Position end
		local p = model:FindFirstChildWhichIsA("BasePart", true)
		return p and p.Position or nil	elseif model:IsA("BasePart") then
		return model.Position
	end
	return nil
end

local function snapshotStarter(r)
	local rp = r.PrimaryPart
	if not rp then return end
	local frame = restFrame(rp)
	local minX, maxX, minZ, maxZ
	local n = 0
	for _, child in ipairs(r:GetChildren()) do
		if isFloorTile(child) or child == rp then
			local pos = centreOf(child)
			if pos then
				local l = frame:PointToObjectSpace(pos)
				minX = math.min(minX or l.X, l.X); maxX = math.max(maxX or l.X, l.X)
				minZ = math.min(minZ or l.Z, l.Z); maxZ = math.max(maxZ or l.Z, l.Z)
				n += 1
				-- прямая метка на клетке: пока её не пересоздал сейв, геометрия не нужна
				child:SetAttribute("StarterTile", true)
			end
		end
	end
	if n == 0 then return end
	starterBox = {
		minX = minX - STARTER_PAD, maxX = maxX + STARTER_PAD,
		minZ = minZ - STARTER_PAD, maxZ = maxZ + STARTER_PAD,
	}
	r:SetAttribute("StarterMinX", starterBox.minX)
	r:SetAttribute("StarterMaxX", starterBox.maxX)
	r:SetAttribute("StarterMinZ", starterBox.minZ)
	r:SetAttribute("StarterMaxZ", starterBox.maxZ)
	print(("[RaftDemolish] стартовый плот: досок %d, защищён прямоугольник "
		.. "X %.1f…%.1f Z %.1f…%.1f (кадр покоя)"):format(n,
		starterBox.minX, starterBox.maxX, starterBox.minZ, starterBox.maxZ))
end

-- Стартовая ли это доска: внутри запомненного прямоугольника. Пока снимка
-- нет (первые секунды сервера) — защищаем всё, что рядом с ядром: лучше
-- лишний отказ, чем разобранный под собой плот.
local function isStarterTile(model)
	local r = raft()
	local rp = r and r.PrimaryPart
	if not (rp and isFloorTile(model)) then return false end
	if rp:IsDescendantOf(model) then return true end
	if model:GetAttribute("StarterTile") then return true end   -- помечена снимком
	local pos = centreOf(model)
	if not pos then return false end
	if not starterBox then
		local dx, dz = pos.X - rp.Position.X, pos.Z - rp.Position.Z
		return (dx * dx + dz * dz) < (GRID * 1.6) ^ 2
	end
	local l = restFrame(rp):PointToObjectSpace(pos)
	local inside = l.X >= starterBox.minX and l.X <= starterBox.maxX
		and l.Z >= starterBox.minZ and l.Z <= starterBox.maxZ
	if not inside then
		-- журнал: если стартовую клетку всё же пропустили, здесь видно, почему
		print(("%s клетка %s без метки, в кадре покоя X %.1f Z %.1f — вне прямоугольника X %.1f…%.1f Z %.1f…%.1f → можно ломать")
			:format(LOG_TAG, model.Name, l.X, l.Z, starterBox.minX, starterBox.maxX, starterBox.minZ, starterBox.maxZ))
	end
	return inside
end

-- снимок при запуске: ждём плот, его корень и RestYaw от BoatMovement
task.spawn(function()
	local r = workspace:WaitForChild("Raft", 30)
	if not r then return end
	local t0 = os.clock()
	while os.clock() - t0 < 30 and not (r.PrimaryPart and r.PrimaryPart:GetAttribute("RestYaw")) do
		task.wait(0.5)
	end
	snapshotStarter(r)
end)

-- ─── Полоска прочности ────────────────────────────────────────────
local function showBar(model, hp, maxHP)
	local main, height
	if model:IsA("Model") then
		main = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		local ok, _, size = pcall(function() return model:GetBoundingBox() end)
		height = (ok and size and size.Y) or 4
	else
		main, height = model, model.Size.Y
	end
	if not main then return end

	local bb = model:FindFirstChild("DemolishHPBar")
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "DemolishHPBar"
		bb.Size = UDim2.fromOffset(110, 14)
		bb.AlwaysOnTop = true
		bb.StudsOffsetWorldSpace = Vector3.new(0, height * 0.5 + 2, 0)
		bb.Adornee = main
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
		bg.BorderSizePixel = 0
		bg.Parent = bb
		local fl = Instance.new("Frame")
		fl.Name = "Fill"
		fl.BackgroundColor3 = Color3.fromRGB(235, 150, 55) -- оранжевый: разбор, не бой
		fl.BorderSizePixel = 0
		fl.Parent = bg
		bb.Parent = model
	end
	local bg = bb:FindFirstChildWhichIsA("Frame")
	local fl = bg and bg:FindFirstChild("Fill")
	if fl then fl.Size = UDim2.fromScale(math.clamp(hp / maxHP, 0, 1), 1) end
end

local function clearBar(model)
	local bb = model:FindFirstChild("DemolishHPBar")
	if bb then bb:Destroy() end
end

-- ─── Удар ─────────────────────────────────────────────────────────
local lastHitAt  = {}                                       -- [model] = os.clock(), для DECAY_AFTER
local lastSwing  = setmetatable({}, { __mode = "k" })       -- [player] = os.clock(), КД замаха

-- Урон приходит НЕ в момент клика, а через HIT_DELAY. За это время игрок мог
-- убрать топор, отойти или добить цель другим ударом, поэтому всё проверяем
-- заново — иначе отложенный урон прилетал бы «из ниоткуда».
local function applyDemolishHit(player, part, target)
	if not target.Parent then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not part.Parent then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or not AXE_TOOLS[tool.Name] then return end
	if (hrp.Position - part.Position).Magnitude > HIT_RANGE then return end

	lastHitAt[target] = os.clock()

	local maxHP = isFloorTile(target) and HP_FLOOR or HP_BUILDING
	local hp = tonumber(target:GetAttribute("DemolishHP")) or maxHP
	hp = hp - DAMAGE_PER_HIT

	if hp > 0 then
		target:SetAttribute("DemolishHP", hp)
		showBar(target, hp, maxHP)
		-- Не добили — прочность восстановится сама. Иначе полуразобранные
		-- постройки копились бы по всему плоту, а игрок не понимал, почему
		-- одна ломается с одного удара, а другая с четырёх.
		task.delay(DECAY_AFTER + 0.1, function()
			if target.Parent and (os.clock() - (lastHitAt[target] or 0)) >= DECAY_AFTER then
				target:SetAttribute("DemolishHP", nil)
				clearBar(target)
			end
		end)
		return
	end

	-- Добили.
	lastHitAt[target] = nil
	clearBar(target)

	-- УБИРАЕМ ТОЛЬКО ТО, ПО ЧЕМУ БИЛИ. Каскад «унести всё, что держалось через
	-- эту клетку» здесь не нужен и опасен: тайлы приварены НАПРЯМУЮ к
	-- PrimaryPart, а не друг к другу, поэтому соседи от удаления одной клетки
	-- физически не страдают. Расчёт связности при этом ошибался и сносил
	-- половину плота — игрок ломал одну доску и терял почти всё.
	-- (Каскад остался у пиявки: там сеть догрызают, и висящий в море отрезанный
	-- кусок — реальная проблема, а тонет он медленно и заметно.)
	print(("%s %s разобрал %s"):format(LOG_TAG, player.Name, target.Name))
	target:Destroy()
end

hitEvent.OnServerEvent:Connect(function(player, part)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or not AXE_TOOLS[tool.Name] then return end

	local target = demolishTargetOf(part)
	if not target then return end
	if isStarterTile(target) then return end   -- стартовый плот неприкосновенен

	if (hrp.Position - part.Position).Magnitude > HIT_RANGE then return end

	local now = os.clock()
	if now - (lastSwing[player] or 0) < HIT_COOLDOWN then return end
	lastSwing[player] = now

	task.delay(HIT_DELAY, function()
		applyDemolishHit(player, part, target)
	end)
end)

Players.PlayerRemoving:Connect(function()
	-- чистим кэш ударов от уже удалённых моделей
	for model in pairs(lastHitAt) do
		if not model.Parent then lastHitAt[model] = nil end
	end
end)

print(LOG_TAG .. " ready (топор разбирает пол и постройки плота)")
