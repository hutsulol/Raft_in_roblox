-- BarrelSystem.server.lua
-- БОЧКА С ЗАМКОМ.
--
-- Бочка приплывает по морю как обычный предмет (ResourceSpawner), но кликами
-- НЕ собирается — на ней атрибут BarrelLocked, и обычный сбор его уважает.
-- Вскрывается мини-игрой: по кольцу бежит стрелка, игрок останавливает её в
-- подсвеченном секторе. Нужно ROUNDS попаданий ПОДРЯД; промах сбрасывает
-- прогресс, а с каждым успехом сектор уже и стрелка быстрее.
--
-- Что здесь, а что на клиенте:
--   • сервер решает, где сектор, сколько раундов, что внутри и кто занял бочку;
--   • клиент только крутит стрелку и рисует кольцо (BarrelLockUI).
-- Угол остановки приходит с клиента: соблазна читерить тут немного (добыча
-- бытовая), а гонять его через задержку сети означало бы бить мимо на пинге.
-- Сервер всё равно проверяет попадание сам, по СВОЕМУ сектору.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris            = game:GetService("Debris")

local LootBurstFX = require(ReplicatedStorage:WaitForChild("LootBurstFX"))
local AssetFind   = require(ReplicatedStorage:WaitForChild("AssetFind"))
-- Бочка могла лежать в сети, то есть быть приваренной к плоту: её уход — это
-- перестройка сборки, и игрока на палубе от рывка держит его клиент (RaftShake).
local RaftShake   = require(ReplicatedStorage:WaitForChild("RaftShake"))

local LOG_TAG = "[Barrel]"

-- ─── Вскрытие: щепки, звук, салют добычи ───
-- Звуки взяты встроенные (rbxasset), чтобы механика работала сразу и не зависела
-- от загруженных ассетов. Меняются одной строкой.
-- ЗВУК ОДИН — лязг сорванного замка.
-- Раньше поверх него игрался ещё и «Wood Break» (те же два ассета, что у укусов
-- пиявки по плоту). Звучало это то как ломающееся дерево, то как атака зомби, и
-- сбивало с толку: игрок слышал знакомый звук угрозы там, где ничего не
-- происходит. Оставлен только лязг — он единственный про замок.
local LOCK_POP_ID   = "rbxasset://sounds/metal.ogg"
local CHIP_COUNT    = 14     -- клёпок/щепок, разлетающихся при вскрытии
local CHIP_SPEED    = 22
local CHIP_LIFETIME = 1.4
local CHIP_SIZE     = 0.45

-- Иконки для «салюта» добычи. На сервере _G.GetItemIcon недоступен (он живёт в
-- клиентском InventoryUI), поэтому держим свою таблицу — те же ID, что у сети.
local LOOT_ICONS = {
	Log     = "rbxassetid://116178347748793",
	Leaves  = "rbxassetid://96691360298069",
	Plastic = "rbxassetid://132919988751848",
	Stone   = "rbxassetid://96450657403376",
	Potato  = "rbxassetid://114389346130909",
	Beet    = "rbxassetid://80108091374305",
	Rubbish = "rbxassetid://134054228230432",
}

-- ─── Настройки мини-игры ───
local ROUNDS        = 3     -- попаданий подряд, чтобы сбить замок
--[[ Один промах — и бочка идёт на дно вместе с содержимым. Замок должен быть
     ставкой, а не бесконечной попыткой: без лимита достаточно было бы тыкать
     наугад, пока не повезёт.
     Было две ошибки, стало одна — по указанию владельца, вместе с замедлением
     стрелки: игра стала спокойнее по темпу и жёстче по цене ошибки. Клиент
     сам подписывает «Последняя попытка!», когда остаётся одна, так что при
     единице предупреждение видно с самого начала — это ожидаемо и верно. ]]
local MAX_MISSES    = 1
-- ⚠️ У СЕССИИ ОБЯЗАН БЫТЬ СРОК ГОДНОСТИ.
-- Раньше сессия жила, пока клиент сам не пришлёт "stop". Игрок, который начал
-- вскрывать и отвлёкся (или уплыл вместе с плотом, или умер), оставлял бочку
-- занятой НАВСЕГДА: другим летело «Бочку уже вскрывают», а сам он больше не мог
-- открыть НИ ОДНУ бочку — tryStart отсекает по своей же незакрытой сессии.
-- В одиночку это почти незаметно, а в команде хватает одного такого клика.
local ROUND_TIMEOUT = 15    -- сек на раунд без ответа клиента
local SINK_SPEED    = 7     -- студов в секунду, пока тонет
local SINK_TIME     = 2.2   -- сколько тонет, прежде чем исчезнуть
local SINK_SOUND_ID = "rbxasset://sounds/impact_water.mp3"
-- 50 = дистанция клика по плавающему ресурсу в ResourceSpawner. Бочка дрейфует
-- в море рядом с плотом, и при 16 студах до неё было не дотянуться вообще.
local REACH         = 50
--[[ Сектор с каждым раундом уже, стрелка быстрее. Длина таблицы = ROUNDS.
     ⚠️ ЗЕЛЁНАЯ ЗОНА ШИРЕ ПРЕЖНЕЙ НА 20% (было 90/60/38). Стрелка разогнана до
     162/210/264 градусов в секунду, и на этих скоростях третий раунд упирался
     не в реакцию, а в задержку сети: 38 градусов при 264 гр/с — это 144 мс на
     весь клик, меньше, чем путь пакета до сервера и обратно на плохом канале.
     Расширять надо ВСЕ три числа одинаково: раунды читаются как нарастающая
     сложность, и подтянув только последний, мы сломали бы эту кривую. ]]
local SECTOR_DEG    = { 108, 72, 46 }

--[[ ⚠️ ПЕРВЫЕ ТРИ ДНЯ СЕКТОР ВДВОЕ ШИРЕ — ЭТО ОБУЧЕНИЕ, А НЕ ПОБЛАЖКА.
     Замок бочки — единственная мини-игра на реакцию во всей игре, и правила её
     нигде не объясняются: первую бочку игрок вскрывает вслепую, а цена ошибки
     сразу максимальная — один промах, и бочка тонет со всей добычей. На телефоне
     к этому добавляется палец, который закрывает половину циферблата.
     Широкий сектор в начале даёт понять САМО ПРАВИЛО (кликать надо в зелёном),
     не отнимая при этом ничего у опытного игрока: с четвёртого дня числа
     возвращаются к боевым, и разница чувствуется как рост сложности, а не как
     отнятая фора.
     Потолок нужен, чтобы удвоение первого раунда не превратило круг в мишень
     размером с круг: 90 → 180 это уже половина циферблата. ]]
local EASY_DAYS     = 3     -- по какой день включительно действует поблажка
local EASY_SECTOR_K = 2     -- во сколько раз шире сектор в эти дни
local MAX_SECTOR    = 240   -- шире не отдаём ни при каких множителях

--[[ День ведёт DayNightCircle (IntValue в ReplicatedStorage, стартует с 1).
     ⚠️ ИЩЕМ ЛЕНИВО, А НЕ НА ЗАГРУЗКЕ: порядок запуска серверных скриптов не
     определён, и на старте значения может ещё не быть. Один FindFirstChild на
     раунд — это трижды за бочку, платить за него нечем. ]]
local dayValue = nil
local function currentDay()
	if not (dayValue and dayValue.Parent) then
		dayValue = ReplicatedStorage:FindFirstChild("DayCount")
	end
	return (dayValue and tonumber(dayValue.Value)) or 1
end
--[[ ⚠️ СКОРОСТЬ СТРЕЛКИ ПРАВИЛАСЬ ДВАЖДЫ — ВОТ ВСЯ ИСТОРИЯ ЧИСЕЛ.
     Изначально было 200/260/330, и последний раунд читался как лотерея: сектор
     к третьему кругу и так вдвое уже первого, а стрелка успевала проскочить его
     за время реакции. Замедлили примерно на треть — до 135/175/220.
     Теперь, когда первые три дня сектор вдвое шире (см. EASY_DAYS), запас на
     реакцию появился и там, где его не хватало, и замок стал вялым. Поднимаем
     на 20% от нынешних чисел — по просьбе владельца.
     Прогрессия сохраняется в любом случае: каждый раунд быстрее предыдущего, а
     до исходных 200/260/330 всё равно не дотягиваем — целиться по-прежнему
     можно, а не угадывать. ]]
local SPEED_DEG     = { 162, 210, 264 } -- градусов в секунду (было 135/175/220)

-- ─── Добыча ───
-- ⚠️ СПИСОК ЗАКРЫТЫЙ: ЧЕГО ЗДЕСЬ НЕТ, ТОГО В БОЧКЕ НЕ БЫВАЕТ.
-- Раньше сюда же попадали железные слитки, патроны и монеты «редкой» строкой, и
-- бочка превращалась в лотерею на всё сразу. Теперь в ней только то, что
-- логично выловить из моря: сырьё, мусор и овощи.
local BARREL_LOOT = {
	"Leaves", "Log", "Plastic", "Potato", "Beet", "Rubbish", "Stone",
}

-- Сколько ПРЕДМЕТОВ всего и на сколько РАЗНЫХ видов их раскладывать.
-- Считаем именно так, а не «по строке на вид»: иначе три вида по 3–5 штук дают
-- полтора десятка предметов, и бочка перестаёт быть мелкой находкой.
local LOOT_TOTAL_MIN, LOOT_TOTAL_MAX = 3, 6
local LOOT_KINDS_MIN, LOOT_KINDS_MAX = 1, 3
-- потолок на вид: шесть камней из одной бочки — перебор (владелец)
local LOOT_CAP = { Stone = 2 }

-- Разложить total предметов по kinds видам так, чтобы каждому досталось хотя бы
-- по одному. Возвращает { [ключ] = сколько }.
local function rollBarrelLoot()
	local total = math.random(LOOT_TOTAL_MIN, LOOT_TOTAL_MAX)
	local kinds = math.random(LOOT_KINDS_MIN, math.min(LOOT_KINDS_MAX, total))

	-- выбираем разные виды: тасуем копию списка и берём сверху
	local pool = table.clone(BARREL_LOOT)
	for i = #pool, 2, -1 do
		local j = math.random(i)
		pool[i], pool[j] = pool[j], pool[i]
	end

	local out = {}
	local left = total
	for i = 1, kinds do
		-- последнему достаётся весь остаток, остальным — случайная доля, но так,
		-- чтобы на каждый оставшийся вид хватило хотя бы по одному предмету
		local take
		if i == kinds then
			take = left
		else
			take = math.random(1, left - (kinds - i))
		end
		local cap = LOOT_CAP[pool[i]]
		if cap and take > cap then take = cap end
		out[pool[i]] = take
		left -= take
	end
	-- остаток после потолков — первому виду без потолка, иначе пропадает
	if left > 0 then
		for i = 1, kinds do
			if not LOOT_CAP[pool[i]] then out[pool[i]] += left break end
		end
	end
	return out
end

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

-- клиент → сервер: "start" | "stop" (угол) | "cancel"
-- сервер → клиент: "begin" (раунд), "hit", "miss", "opened", "denied"
local lockEvent = ensureRemote("BarrelLock")

local sessions = {}  -- [player] = { barrel, round, sectorStart, sectorSize, speed }
local busy     = {}  -- [barrel]  = player, чтобы двое не вскрывали одну бочку

-- ─── Шаблон бочки ───
-- Спавнер берёт модели из ReplicatedStorage, а бочку авторски положили в
-- Workspace — там она просто стоит на плоту и в море не попадает. Вместо того
-- чтобы требовать ручного переноса (и молча ничего не спавнить, пока его не
-- сделали), подхватываем копию сами. Оригинал в Workspace не трогаем: он мог
-- быть поставлен туда намеренно, как декор.
local function ensureBarrelTemplate()
	if AssetFind.find("Barrel") then return true end

	local src
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == "Barrel" and (d:IsA("Model") or d:IsA("BasePart"))
			and not d:FindFirstAncestorWhichIsA("Tool") then
			src = d
			break
		end
	end
	if not src then
		warn(LOG_TAG .. " модели 'Barrel' нет ни в ReplicatedStorage, ни в Workspace — "
			.. "бочки спавниться не будут")
		return false
	end

	if not src.Archivable then src.Archivable = true end
	local copy = src:Clone()
	if not copy then
		warn(LOG_TAG .. " не удалось склонировать 'Barrel' из Workspace")
		return false
	end
	copy.Name = "Barrel"
	copy.Parent = ReplicatedStorage
	print(LOG_TAG .. " шаблон 'Barrel' скопирован из Workspace в ReplicatedStorage ("
		.. src:GetFullName() .. ") — оригинал оставлен на месте")
	return true
end

ensureBarrelTemplate()

-- ─── Вспомогательное ───
local function barrelRoot(barrel)
	if barrel:IsA("BasePart") then return barrel end
	return barrel.PrimaryPart or barrel:FindFirstChildWhichIsA("BasePart", true)
end

local function nearBarrel(player, barrel)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local root = barrelRoot(barrel)
	if not hrp or not root then return false end
	return (hrp.Position - root.Position).Magnitude <= REACH
end

-- ─── Выдача добычи ───
-- Патроны и монеты — не ресурсы инвентаря, поэтому идут своими путями.
local function giveLoot(player, key, amount, atPos)
	if key == "Pirate" then
		if _G.AddPirate then
			_G.AddPirate(player, amount)
		else
			player:SetAttribute("Pirate", (player:GetAttribute("Pirate") or 0) + amount)
		end
		return ("%d Пиратов"):format(amount)
	elseif key == "Ammo" then
		-- Пополняет запас на всех стволах до максимума (общая функция из
		-- AmmoCaseSystem — правила «сколько максимум» живут там одни).
		if _G.RefillReserveAmmo then
			_G.RefillReserveAmmo(player)
			return "патроны пополнены"
		end
		-- Ящика с патронами в мире нет — не теряем награду молча, даём железо.
		key, amount = "Iron_Ingot", 1
	end

	if _G.AddResourceToInventory then
		_G.AddResourceToInventory(player, key, amount, atPos)
	end
	return ("%d %s"):format(amount, key)
end

-- ЭФФЕКТ ВСКРЫТИЯ.
-- Играем на ОТДЕЛЬНОЙ детали, а не на самой бочке: бочка через мгновение
-- удаляется, и звук с иконками, висящие на ней, оборвались бы на середине.
local function playOpenFX(pos, iconKeys)
	local anchor = Instance.new("Part")
	anchor.Name = "BarrelFX"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = workspace
	Debris:AddItem(anchor, 5)

	local pop = Instance.new("Sound")
	pop.SoundId = LOCK_POP_ID
	pop.Volume = 0.7
	pop.PlaybackSpeed = 1.25 + math.random() * 0.1
	pop.RollOffMaxDistance = 110
	pop.Parent = anchor
	pop:Play()

	-- Щепки: разлетаются вверх конусом и падают под своей тяжестью.
	for _ = 1, CHIP_COUNT do
		local chip = Instance.new("Part")
		chip.Size = Vector3.new(CHIP_SIZE, CHIP_SIZE * 0.4, CHIP_SIZE * 1.6)
		chip.Color = Color3.fromRGB(104, 72, 42)
		chip.Material = Enum.Material.Wood
		chip.CanCollide = false
		chip.CanQuery = false
		chip.CFrame = CFrame.new(pos) * CFrame.Angles(
			math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
		chip.Parent = workspace
		local dir = Vector3.new(
			math.random() - 0.5,
			math.random() * 0.8 + 0.5,
			math.random() - 0.5).Unit
		chip.AssemblyLinearVelocity = dir * CHIP_SPEED
		chip.AssemblyAngularVelocity = Vector3.new(
			math.random(-14, 14), math.random(-14, 14), math.random(-14, 14))
		Debris:AddItem(chip, CHIP_LIFETIME)
	end

	-- Салют иконок добычи — тот же эффект, что показывает сеть и ящик дайвера.
	local icons = {}
	for _, key in ipairs(iconKeys) do
		local id = LOOT_ICONS[key]
		if id then table.insert(icons, id) end
	end
	if #icons > 0 then
		LootBurstFX.play(anchor, icons, { heightOffset = 1.4 })
	end
end

-- УТОПИТЬ БОЧКУ.
-- Двигаем каждую деталь напрямую, а не через Model:PivotTo: WorldPivot модели
-- не едет вместе с физикой, и после дрейфа по морю пивот показывает совсем не
-- туда, где бочка на самом деле.
local function sinkBarrel(barrel)
	if not barrel.Parent then return end
	barrel:SetAttribute("BarrelLocked", nil) -- больше не кликается
	barrel:SetAttribute("BarrelSunk", true)  -- и не вскрывается заново, пока тонет
	CollectionService:RemoveTag(barrel, "Resource")

	-- ⚠️ СНИМАЕМ ВСЕ ТОЧКИ ВЗАИМОДЕЙСТВИЯ.
	-- Бочка тонет SINK_TIME секунд и всё это время лежит в Workspace. С живыми
	-- ClickDetector'ами по ней можно было кликнуть ещё раз и начать вскрытие
	-- заново — кольцо всплывало обратно поверх уведомления «ушла на дно», и со
	-- стороны выглядело так, будто UI не закрылся.
	for _, d in ipairs(barrel:GetDescendants()) do
		if d:IsA("ClickDetector") or d:IsA("ProximityPrompt") then d:Destroy() end
	end

	local parts = {}
	if barrel:IsA("BasePart") then table.insert(parts, barrel) end
	for _, d in ipairs(barrel:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	if #parts == 0 then barrel:Destroy() return end

	-- ⚠️ СНАЧАЛА ОТРЫВАЕМ БОЧКУ ОТ ВСЕГО ЧУЖОГО, И ТОЛЬКО ПОТОМ ТОПИМ.
	-- Бочку, попавшую в сеть, ResourceSpawner ПРИВАРИВАЕТ к полотну
	-- (WeldConstraint улов → сеть), а сама сеть приварена к плоту. Ниже мы ставим
	-- Anchored и каждый кадр двигаем CFrame — а это, по правилам движка, двигает
	-- ВСЮ сварную сборку разом. То есть не справившийся с замком игрок утаскивал
	-- под воду весь плот вместе с постройками. Ровно про это предупреждение в
	-- GameDesign: не анкорить и не двигать CFrame у приваренной к плоту детали.
	--
	-- Рвём только стыки НАРУЖУ: один конец наш, другой чужой. Внутренние
	-- (деталь бочки ↔ деталь бочки) оставляем — они держат бочку целой, чтобы она
	-- шла на дно одним предметом, а не рассыпалась досками.
	local ours = {}
	for _, p in ipairs(parts) do ours[p] = true end

	-- Собираем стыки наружу ОДНИМ СПИСКОМ, а рвём потом. Так мы успеваем узнать,
	-- к чему бочка была привязана, ДО того как связь исчезнет: снимок хода плота
	-- ниже читается именно с той детали (Assembly*Velocity относится ко всей
	-- сборке, поэтому годится любая её деталь).
	local outward, host = {}, nil

	local function collect(j)
		local ok, a, b = pcall(function() return j.Part0, j.Part1 end)
		if not ok or not (a and b) then return end
		if ours[a] ~= ours[b] then
			outward[j] = true
			host = host or (ours[a] and b or a)
		end
	end

	for _, d in ipairs(barrel:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("JointInstance") then collect(d) end
	end
	-- Сварку могли повесить и НЕ внутри бочки. GetJoints находит стык по детали,
	-- где бы он ни лежал, — так мы не зависим от того, кто кого куда положил.
	for _, p in ipairs(parts) do
		local ok, joints = pcall(function() return p:GetJoints() end)
		if ok and joints then
			for _, j in ipairs(joints) do collect(j) end
		end
	end

	-- ⚠️ ХОД ПЛОТА СНИМАЕМ ДО РАЗРЫВА, ВОЗВРАЩАЕМ ПОСЛЕ.
	-- Уход детали из сборки — та же перестройка, что и её появление: физика
	-- пересобирает сборку и на шаг отнимает у неё ход. Плот дёргается, а стоящего
	-- на палубе игрока уносит по доскам «по инерции» — тот же эффект, что был у
	-- очистителя, грядки и стройки, и лечится он тем же способом (RaftShake).
	local lin, ang
	if host then
		lin, ang = host.AssemblyLinearVelocity, host.AssemblyAngularVelocity
	end

	for j in pairs(outward) do j:Destroy() end

	if host and host.Parent then
		host.AssemblyLinearVelocity = lin
		host.AssemblyAngularVelocity = ang
	end
	if host then RaftShake.notify() end   -- персонажа удержит его собственный клиент

	-- И ВЫПИСЫВАЕМ ИЗ УЛОВА СЕТИ. Признак «лежу в сети» — атрибут CaughtInNet:
	-- по нему сеть собирает свою кучу (netGroup в ResourceSpawner) и по нему же
	-- считает, сколько в ней места. Не сняв его, мы бы оставили тонущую бочку
	-- числиться уловом: клик по соседнему бревну «вытряхивал» бы и её, а место в
	-- сети держалось бы занятым, пока сборщик мусора не дойдёт до записи.
	barrel:SetAttribute("CaughtInNet", nil)
	local caught = barrel:FindFirstChild("CaughtNet")
	if caught then caught:Destroy() end


	local snd = Instance.new("Sound")
	snd.SoundId = SINK_SOUND_ID
	snd.Volume = 0.7
	snd.PlaybackSpeed = 0.75
	snd.RollOffMaxDistance = 90
	snd.Parent = parts[1]
	snd:Play()

	for _, p in ipairs(parts) do
		p.Anchored = true  -- чтобы вода и волны не мешали ровному погружению
		p.CanCollide = false
	end

	task.spawn(function()
		local t0 = os.clock()
		while barrel.Parent and os.clock() - t0 < SINK_TIME do
			local dt = task.wait()
			local delta = Vector3.new(0, -SINK_SPEED * dt, 0)
			for _, p in ipairs(parts) do
				if p.Parent then p.CFrame = p.CFrame + delta end
			end
		end
		if barrel.Parent then barrel:Destroy() end
	end)
end

local function openBarrel(player, barrel)
	local root = barrelRoot(barrel)
	local pos = root and root.Position or nil

	local given, keys = {}, {}
	for key, amount in pairs(rollBarrelLoot()) do
		table.insert(given, giveLoot(player, key, amount, pos))
		table.insert(keys, key)
	end

	if _G.SendInventory then _G.SendInventory(player) end

	print(("%s %s вскрыл бочку: %s"):format(
		LOG_TAG, player.Name, table.concat(given, ", ")))

	-- Клиенту достаточно факта вскрытия: он просто закрывает кольцо. Что именно
	-- выпало, игрок видит по салюту иконок над бочкой и по инвентарю.
	lockEvent:FireClient(player, "opened")
	busy[barrel] = nil

	-- Эффект ЗАПУСКАЕМ ДО удаления бочки, но живёт он на своей детали, поэтому
	-- переживёт её (см. playOpenFX).
	if pos then playOpenFX(pos, keys) end
	barrel:Destroy()
end

-- ─── Раунд ───
local function beginRound(player)
	local s = sessions[player]
	if not s then return end
	local i = math.clamp(s.round, 1, ROUNDS)
	s.sectorSize  = SECTOR_DEG[i] or SECTOR_DEG[#SECTOR_DEG]
	s.speed       = SPEED_DEG[i] or SPEED_DEG[#SPEED_DEG]

	-- первые дни — широкий сектор, см. EASY_DAYS
	local day = currentDay()
	if day <= EASY_DAYS then
		local wide = math.min(s.sectorSize * EASY_SECTOR_K, MAX_SECTOR)
		if wide ~= s.sectorSize then
			print(("[Barrel] день %d: раунд %d — сектор %d° вместо %d° (обучение)")
				:format(day, s.round, wide, s.sectorSize))
			s.sectorSize = wide
		end
	end
	-- Сектор ставим случайно, но не вплотную к старту стрелки (0°), иначе
	-- первый раунд иногда выигрывался мгновенным кликом без реакции.
	s.sectorStart = math.random(40, 320)
	s.deadline = os.clock() + ROUND_TIMEOUT
	lockEvent:FireClient(player, "begin", {
		barrel     = s.barrel,   -- клиент вешает кольцо НАД НЕЙ, а не на весь экран
		round      = s.round,
		rounds     = ROUNDS,
		sectorStart = s.sectorStart,
		sectorSize  = s.sectorSize,
		speed       = s.speed,
		--[[ ⚠️ ЦЕНУ ОШИБКИ СООБЩАЕМ ЗАРАНЕЕ, А НЕ ПОСЛЕ ПРОМАХА.
		     Пока промахов было два, клиент узнавал об опасности из сообщения
		     «miss» и успевал написать «Последняя попытка!». С одним промахом
		     такого сообщения не будет вовсе: первый же мимо — и бочка тонет,
		     то есть предупреждение опоздало бы навсегда. Отдаём остаток
		     попыток прямо в раунде. ]]
		missesLeft = math.max(MAX_MISSES - (s.misses or 0), 0),
	})
end

local function endSession(player, reason)
	local s = sessions[player]
	if not s then return end
	if s.barrel and busy[s.barrel] == player then busy[s.barrel] = nil end
	if s.conn then s.conn:Disconnect() end
	sessions[player] = nil
	if reason then lockEvent:FireClient(player, reason) end
end

--[[ ⚠️ СТОРОЖ СЕССИЙ — ЭТО НЕ ПЕРЕСТРАХОВКА, А ЕДИНСТВЕННЫЙ ВЫХОД.
     Клиентский "stop" приходит не всегда: вкладка свернулась, персонаж умер,
     плот уплыл, игрока выкинуло сетью. Любой такой случай раньше оставлял
     бочку занятой навсегда. Здесь сессия снимается сама — по сроку раунда и
     по уходу из радиуса. ]]
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for player, s in pairs(sessions) do
			local dead = (s.deadline and now > s.deadline)
				or not player.Parent
				or not s.barrel
				or not s.barrel.Parent
				or not nearBarrel(player, s.barrel)
			if dead then
				print(("%s сессия %s снята сторожем (протухла или игрок ушёл)")
					:format(LOG_TAG, player.Name))
				endSession(player, "cancel")
			end
		end
	end
end)

-- смерть/респавн тоже закрывают вскрытие: персонажа больше нет, кольцо висит зря
Players.PlayerAdded:Connect(function(plr)
	plr.CharacterRemoving:Connect(function() endSession(plr, "cancel") end)
end)
for _, plr in ipairs(Players:GetPlayers()) do
	plr.CharacterRemoving:Connect(function() endSession(plr, "cancel") end)
end

-- Попал ли угол в сектор. Всё в градусах, с переносом через 360.
local function inSector(angle, start, size)
	local d = (angle - start) % 360
	return d <= size
end

lockEvent.OnServerEvent:Connect(function(player, action, arg)
	-- Действия "start" здесь нет намеренно: сессию начинает только клик по
	-- бочке (CollectResource → _G.StartBarrelLock либо ClickDetector), и оба
	-- пути идут через tryStart с его проверками. Отдельный вход, дёргаемый
	-- клиентом, был бы просто дублем тех же проверок.
	if action == "stop" then
		local s = sessions[player]
		if not s then return end
		if not s.barrel.Parent then endSession(player, "cancel") return end
		if not nearBarrel(player, s.barrel) then
			endSession(player, "denied")
			return
		end
		local angle = tonumber(arg)
		if not angle then return end
		angle = angle % 360

		if inSector(angle, s.sectorStart, s.sectorSize) then
			s.round = s.round + 1
			if s.round > ROUNDS then
				local barrel = s.barrel
				if s.conn then s.conn:Disconnect() end
				sessions[player] = nil
				openBarrel(player, barrel)
			else
				lockEvent:FireClient(player, "hit", s.round - 1)
				beginRound(player)
			end
		else
			-- ПРОМАХ СБРАСЫВАЕТ СЕРИЮ, а на MAX_MISSES бочка уходит на дно
			-- вместе с содержимым: право на ошибку ограничено, иначе можно
			-- было бы долбить наугад, пока не повезёт.
			s.misses = (s.misses or 0) + 1
			if s.misses >= MAX_MISSES then
				local barrel = s.barrel
				if s.conn then s.conn:Disconnect() end
				sessions[player] = nil
				busy[barrel] = nil
				lockEvent:FireClient(player, "sunk")
				sinkBarrel(barrel)
				print(("%s %s упустил бочку — ушла на дно"):format(LOG_TAG, player.Name))
				return
			end
			s.round = 1
			lockEvent:FireClient(player, "miss", MAX_MISSES - s.misses)
			beginRound(player)
		end
		return

	elseif action == "cancel" then
		endSession(player)
		return
	end
end)

Players.PlayerRemoving:Connect(function(player)
	endSession(player)
end)

-- ─── Подсказка на бочке ───
-- ProximityPrompt, а НЕ ClickDetector: последний не срабатывает, пока у игрока
-- экипирован Tool, и с топором в руках бочку было бы не открыть.
-- Prompt.Triggered и ClickDetector.MouseClick приходят уже на сервере, поэтому
-- сессию запускаем прямо здесь, без похода через ремоут.
local function tryStart(player, barrel)
	if sessions[player] then return end
	if not barrel.Parent then return end
	-- утонувшая бочка ещё пару секунд лежит в мире — вскрывать её нельзя
	if barrel:GetAttribute("BarrelSunk") then return end
	-- ⚠️ ЗАЯВКА БЕЗ ЖИВОЙ СЕССИИ — ЭТО МУСОР, А НЕ ЗАНЯТАЯ БОЧКА.
	-- Отказ выдаём, только если тот игрок ДЕЙСТВИТЕЛЬНО вскрывает именно эту
	-- бочку прямо сейчас. Иначе заявка снимается: без этого одна оборванная
	-- попытка запирала бочку для всей команды до конца сессии сервера.
	local claimer = busy[barrel]
	if claimer and claimer ~= player then
		local cs = sessions[claimer]
		if not claimer.Parent or not cs or cs.barrel ~= barrel then
			busy[barrel] = nil
		else
			lockEvent:FireClient(player, "denied", "Бочку уже вскрывают")
			return
		end
	end
	-- Далеко — просто молчим. Раньше здесь летело уведомление «Слишком далеко»,
	-- и оно выскакивало на любой промах мимо бочки: полезной информации ноль,
	-- а экран засоряется.
	if not nearBarrel(player, barrel) then return end
	busy[barrel] = player
	local s = { barrel = barrel, round = 1, misses = 0 }
	sessions[player] = s

	-- БОЧКА МОЖЕТ ИСЧЕЗНУТЬ ПРЯМО ВО ВРЕМЯ ВСКРЫТИЯ: она разбивается о корпус
	-- плота, как любой плавающий ресурс. Без этой подписки кольцо продолжало бы
	-- висеть в воздухе над пустым местом до следующего клика.
	s.conn = barrel.AncestryChanged:Connect(function()
		if barrel.Parent then return end
		if sessions[player] ~= s then return end
		sessions[player] = nil
		busy[barrel] = nil
		if s.conn then s.conn:Disconnect() end
		lockEvent:FireClient(player, "cancel")
	end)

	print(("%s %s начал вскрывать бочку"):format(LOG_TAG, player.Name))
	beginRound(player)
end

-- Основной вход: клик по плавающей бочке приходит через штатный CollectResource
-- в ResourceSpawner, тот зовёт эту функцию вместо обычного сбора.
_G.StartBarrelLock = function(player, barrel)
	if typeof(player) ~= "Instance" or typeof(barrel) ~= "Instance" then return end
	tryStart(player, barrel)
end

-- ОТКРЫВАЕТСЯ ПРОСТО КЛИКОМ.
-- Клавиши E здесь намеренно нет: основной вход — обычный клик по плавающему
-- ресурсу (CollectResource → _G.StartBarrelLock), тот же, которым собирают
-- брёвна. ClickDetector на деталях оставлен как запасной путь для случая, когда
-- в руках ничего не экипировано (с Tool он молчит и один тянуть не может).
local function attachPrompt(barrel)
	if not barrel:GetAttribute("BarrelLocked") then return end
	local root = barrelRoot(barrel)
	if not root then
		warn(LOG_TAG .. " у бочки нет ни одной детали — взаимодействовать не с чем: "
			.. barrel:GetFullName())
		return
	end

	-- Клик вешаем на КАЖДУЮ деталь: по мелкой бочке легко попасть мимо той
	-- единственной, что считается корневой.
	local parts = {}
	if barrel:IsA("BasePart") then table.insert(parts, barrel) end
	for _, d in ipairs(barrel:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	for _, p in ipairs(parts) do
		if not p:FindFirstChildOfClass("ClickDetector") then
			local cd = Instance.new("ClickDetector")
			cd.MaxActivationDistance = REACH
			cd.Parent = p
			cd.MouseClick:Connect(function(player) tryStart(player, barrel) end)
		end
	end

	print(("%s бочка готова к вскрытию: %s (деталей %d)")
		:format(LOG_TAG, barrel:GetFullName(), #parts))
end

CollectionService:GetInstanceAddedSignal("Resource"):Connect(function(inst)
	task.defer(function()
		if inst.Parent then attachPrompt(inst) end
	end)
end)
for _, inst in ipairs(CollectionService:GetTagged("Resource")) do
	attachPrompt(inst)
end

print(LOG_TAG .. " ready (замок с кольцом, " .. ROUNDS .. " раунда)")
