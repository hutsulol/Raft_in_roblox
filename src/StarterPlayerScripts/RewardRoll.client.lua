-- RewardRoll.client.lua
-- Post-wave reward roll: a button plays a ~5s "slot machine" of possible buildings
-- (cannon / AA) near the TOP of the screen — each prize pulses 75%→100%→75% from
-- its centre and swaps to the next (~0.4s each) over a spinning, multicolour glow.
-- It lands on a winner; the player picks Оставить (→ choose a hotbar slot to receive
-- it) or Выбросить (nothing).

local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local ContentProvider  = game:GetService("ContentProvider")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- разблокировки пушек (куплены в лобби; атрибут WUnlock_<id> реплицируется сюда)
local UpgradeConfig = require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig"))
-- заглушка на время загрузки иконки приза (незагруженная картинка = пустое место)

-- ── assets / prize pool ──
local GLOW_IMG = "rbxassetid://72482422954169"
-- `stars`   = rating shown under the prize (0..STAR_MAX; .5 steps render a half-star).
-- `chance`  = BASE drop weight; shown as a % under the name AND used to pick the winner.
-- `antiAir` = marks the ПВО (Deffender).
-- БАЛАНС по дням (см. buildPool/spin):
--   • ДЕНЬ 1: РОВНО 50/50 — либо Пушка, либо Пулемёт. Больше в первую ночь ничего.
--   • ДЕНЬ 2+: полный рандом по базовым шансам ниже (в сумме 100).
local ITEMS = {
	{ name = "Cannon",           label = "Пушка",               img = "rbxassetid://118236242385241", stars = 0.5, chance = 38 },
	{ name = "Deffender",        label = "ПВО",                 img = "rbxassetid://86928740553428",  stars = 0.5, chance = 24, antiAir = true },
	{ name = "Pulemet_lvl_1",    label = "Пулемёт",             img = "rbxassetid://106277044945645", stars = 1.5, chance = 14 },
	{ name = "MagmaCannon",      label = "Магма-пушка",         img = "rbxassetid://97658619335375",  stars = 0.5, chance = 12 },
	{ name = "Big_Magma_Cannon", label = "Большая магма-пушка", img = "rbxassetid://90669361199026",  stars = 2,   chance = 7 },
	-- ЭПИЧЕСКИЙ: самый редкий в пуле, урон вдвое выше обычного пулемёта (см. TurretSystem)
	{ name = "Pulemet_lvl_2",    label = "Пулемёт II",          img = "rbxassetid://79105833790080",  stars = 3,   chance = 5 },
}
-- что может выпасть в ПЕРВУЮ ночь (поровну между этими)
local FIRST_NIGHT = { Cannon = true, Pulemet_lvl_1 = true }

-- the pool actually in play for the CURRENT spin (rebuilt each spin from the day rules): a list of
-- item tables with their EFFECTIVE chance for that day. Everything below rolls against this pool.
local activePool = ITEMS
local activeTotal = 0
local function recomputeTotal()
	activeTotal = 0
	for _, it in ipairs(activePool) do activeTotal += (it.chance or 0) end
end
recomputeTotal()

-- Build the day's pool. Первая ночь — только Пушка/Пулемёт по 50%; дальше базовые шансы.
local function buildPool(night)
	-- prefer the wave's actual night number (passed by the crate); fall back to the live day counter
	local n = tonumber(night)
	local firstDay
	if n then
		firstDay = n <= 1
	else
		local dayCount = ReplicatedStorage:FindFirstChild("DayCount")
		firstDay = dayCount and dayCount.Value <= 1
	end
	if not firstDay then
		local pool = {}
		-- ЗАБЛОКИРОВАННЫЕ пушки (Пулемёт II, Магма-пушка) в пул не попадают, пока
		-- игрок не купил разблокировку в лобби. Показанный % считается как
		-- chance/activeTotal — значит после покупки проценты ВСЕХ призов
		-- пересчитываются сами, без ручной правки весов.
		for _, it in ipairs(ITEMS) do
			if UpgradeConfig.isUnlocked(player, it.name) then pool[#pool + 1] = it end
		end
		return pool
	end
	-- ПЕРВАЯ НОЧЬ: ровно 50/50 — либо Пушка, либо Пулемёт; остальное не выпадает
	local pool = {}
	for _, it in ipairs(ITEMS) do
		if FIRST_NIGHT[it.name] and UpgradeConfig.isUnlocked(player, it.name) then
			local entry = {}
			for k, v in pairs(it) do entry[k] = v end
			entry.chance = 50
			pool[#pool + 1] = entry
		end
	end
	return pool
end
-- ⚠️ СКОРОСТЬ ПРОКРУТА — ОДНОЙ РУЧКОЙ, А НЕ ТРЕМЯ ЧИСЛАМИ.
-- Длительность прокрута, шаг между призами и отскок карточки связаны: ускорь
-- одно, забыв другое — и приз не успеет вырасти до того, как его сменит
-- следующий, или наоборот застынет на месте. Всё считается от SPIN_SPEED.
local SPIN_SPEED = 1.5   -- во сколько раз быстрее прежнего темпа
local ROLL_TIME = 5   / SPIN_SPEED   -- полная длительность прокрута (сек)
local PER_ITEM  = 0.4 / SPIN_SPEED   -- сколько показывается каждый приз
local GLOW_BASE = 230    -- glow base size (px)
local MIN_SCALE = 0.75   -- prize shrinks to this; grows to 1.0 (never disappears)

-- star rating shown under each prize — only EARNED stars are drawn (no empty slots)
local STAR_FULL = "rbxassetid://128165533748650"
local STAR_HALF = "rbxassetid://104758515646132"
local STAR_MAX  = 5      -- ratings are clamped to at most this many stars
local STAR_SIZE = 34     -- px per star
local STAR_GAP  = 4      -- px between stars

-- Preload every prize icon (+ the glow) up front so they appear instantly when the
-- roulette opens — otherwise they pop in blank for the first frames while streaming.
task.spawn(function()
	local assets = { GLOW_IMG, STAR_FULL, STAR_HALF }
	for _, item in ipairs(ITEMS) do assets[#assets + 1] = item.img end
	local holders = {}
	for _, id in ipairs(assets) do
		local img = Instance.new("ImageLabel")
		img.Image = id
		holders[#holders + 1] = img
	end
	pcall(function() ContentProvider:PreloadAsync(holders) end)
	for _, h in ipairs(holders) do h:Destroy() end
	--[[ ⚠️ СКАЧАТЬ МАЛО — НАДО НАРИСОВАТЬ. PreloadAsync кладёт картинку в память,
	     но в видеопамять она попадает при первой отрисовке: на прокруте каждая
	     пушка «прогружалась» на глазах, пока барабан её показывал. Рисуем все
	     призы скрыто на полке иконок (ModelIcon.warmImages) — как иконки
	     инвентаря, — и держим там всю игру. ]]
	pcall(function()
		require(ReplicatedStorage:WaitForChild("ModelIcon", 10)).warmImages(assets)
	end)
end)

local claimEvent = ReplicatedStorage:FindFirstChild("RewardClaim")
if not claimEvent then
	claimEvent = Instance.new("RemoteEvent")
	claimEvent.Name = "RewardClaim"
	claimEvent.Parent = ReplicatedStorage
end

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

-- ── UI ──
local screen = new("ScreenGui", { Name = "RewardRoll", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40 }, playerGui)

-- the roulette is now opened by the reward CRATE reaching the player, not by a manual button —
-- the 🎁 stays hidden (kept only so the spin/close code has something to toggle)
local triggerBtn = new("TextButton", {
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, -40),
	Size = UDim2.fromOffset(58, 58), BackgroundColor3 = Color3.fromRGB(255, 190, 70),
	Text = "🎁", TextSize = 30, Font = Enum.Font.GothamBlack, AutoButtonColor = true, Visible = false,
}, screen)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, triggerBtn)
new("UIStroke", { Color = Color3.fromRGB(120, 80, 10), Thickness = 2 }, triggerBtn)

--[[ ⚠️ НА ТЕЛЕФОНЕ ВСЮ ЦЕРЕМОНИЮ УЖИМАЕМ ЦЕЛИКОМ.
     Панель 340×250, приз в 150 пикселей, надписи кеглем 32 и кнопки по 560 в
     ширину — всё это рисовалось под монитор и на экране в четыреста пикселей
     высотой занимало половину кадра: пушка закрывала и остров, и хотбар, а
     «ВЫБРОСИТЬ» уезжала под другие элементы.
     Масштаб вешаем на весь ScreenGui, а не правим полтора десятка чисел:
     внутренняя вёрстка (свечение, звёзды, ряд кнопок) остаётся ровно такой же,
     просто меньше. На компьютере множитель равен единице. ]]
do
	local ok, Hud = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("HudScale", 5))
	end)
	if ok and Hud and Hud.isPhone and Hud.isPhone() then
		Hud.applyScaleLive(screen, Hud.iconFactor)
	end
end

-- roll panel: near the TOP of the screen
local panel = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
	Size = UDim2.fromOffset(340, 250), BackgroundTransparency = 1, Visible = false,
}, screen)

-- glow behind the prize — keep its OWN colours (no tint), rotates + breathes
local glow = new("ImageLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 95),
	Size = UDim2.fromOffset(GLOW_BASE, GLOW_BASE), BackgroundTransparency = 1,
	Image = GLOW_IMG, ZIndex = 1,
}, panel)

-- prize image — anchored at its CENTRE so the UIScale grows/shrinks from the middle
local itemImg = new("ImageLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 95),
	Size = UDim2.fromOffset(150, 150), BackgroundTransparency = 1, ZIndex = 3,
}, panel)
local itemScale = new("UIScale", { Scale = MIN_SCALE }, itemImg)

local label = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 192),
	Size = UDim2.fromOffset(340, 32), BackgroundTransparency = 1, ZIndex = 3,
	Font = Enum.Font.GothamBlack, TextSize = 26, TextColor3 = Color3.fromRGB(255, 255, 255),
	TextStrokeColor3 = Color3.fromRGB(0, 0, 0), TextStrokeTransparency = 0.4, Text = "",
}, panel)

-- drop-chance line under the name (blue, like the reference) — odds come from each item's `chance`
local chanceLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 224),
	Size = UDim2.fromOffset(340, 24), BackgroundTransparency = 1, ZIndex = 3,
	Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = Color3.fromRGB(90, 200, 255),
	TextStrokeColor3 = Color3.fromRGB(0, 0, 0), TextStrokeTransparency = 0.4, Text = "",
}, panel)

-- star rating row — a CHILD of the prize image so it scales & flies WITH the cannon (linked),
-- pinned to the cannon's bottom edge so it overlaps the image by half. Only EARNED stars are
-- drawn (full stars + one trailing half).
local starRow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 0),
	Size = UDim2.fromOffset(0, STAR_SIZE), BackgroundTransparency = 1, ZIndex = 6,
}, itemImg)
-- rebuild the row for `rating`: floor(rating) full stars + one half when the remainder ≥ .5
local function setStars(rating)
	for _, c in ipairs(starRow:GetChildren()) do
		if c:IsA("ImageLabel") then c:Destroy() end
	end
	rating = math.clamp(tonumber(rating) or 0, 0, STAR_MAX)
	local full = math.floor(rating)
	local half = (rating - full) >= 0.5
	local count = full + (half and 1 or 0)
	starRow.Size = UDim2.fromOffset(math.max(count * STAR_SIZE + (count - 1) * STAR_GAP, 0), STAR_SIZE)
	for i = 1, count do
		new("ImageLabel", {
			BackgroundTransparency = 1, ZIndex = 6,
			Position = UDim2.fromOffset((i - 1) * (STAR_SIZE + STAR_GAP), 0),
			Size = UDim2.fromOffset(STAR_SIZE, STAR_SIZE),
			Image = (half and i == count) and STAR_HALF or STAR_FULL,
		}, starRow)
	end
end

local function choiceBtn(txt, color, x)
	local b = new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, x, 0, 252),
		Size = UDim2.fromOffset(130, 44), BackgroundColor3 = color, Text = txt,
		Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 4, Visible = false, AutoButtonColor = true,
	}, panel)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2, Transparency = 0.5 }, b)
	return b
end
local keepBtn = choiceBtn("ОСТАВИТЬ", Color3.fromRGB(90, 200, 120), -70)
local skipBtn = choiceBtn("ВЫБРОСИТЬ", Color3.fromRGB(210, 80, 70), 70)   -- было «СКИПНУТЬ»: игроки не понимали

-- slot-pick prompt (shown after Keep)
local pickHint = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -195),
	Size = UDim2.fromOffset(560, 44), BackgroundTransparency = 1, Visible = false,
	Font = Enum.Font.GothamBlack, TextSize = 32, TextColor3 = Color3.fromRGB(255, 255, 255),
	TextStrokeColor3 = Color3.fromRGB(0, 0, 0), TextStrokeTransparency = 0.35, Text = "ВЫБЕРИТЕ СЛОТ",
}, screen)
local cancelBtn = new("TextButton", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -145),
	Size = UDim2.fromOffset(180, 46), BackgroundColor3 = Color3.fromRGB(235, 120, 50),
	Text = "ОТМЕНИТЬ", Font = Enum.Font.GothamBlack, TextSize = 20,
	TextColor3 = Color3.fromRGB(255, 255, 255), Visible = false, AutoButtonColor = true,
}, screen)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, cancelBtn)

-- ── animated FX ──
local fxT = 0
local pickBtns = {}
local picking = false
RunService.RenderStepped:Connect(function(dt)
	fxT += dt
	if panel.Visible then
		glow.Rotation = (glow.Rotation + dt * 55) % 360
		local s = 1 + 0.12 * math.sin(fxT * 2.2)
		glow.Size = UDim2.fromOffset(GLOW_BASE * s, GLOW_BASE * s)
	end
	if picking then
		local a = 0.45 + 0.22 * math.sin(fxT * 6)
		for _, b in ipairs(pickBtns) do b.BackgroundTransparency = a end
	end
end)

-- ── the roll ──
-- ── ЗВУК РУЛЕТКИ ──
-- ⚠️ ЗВУКИ ЗАГРУЖЕННЫЕ, И ЭТО СТОИТ ПРОВЕРИТЬ ПОСЛЕ ПЕРВОГО ЖЕ ЗАПУСКА.
-- В отличие от встроенных rbxasset:// эти живут на сайте, и если у плейса нет
-- прав на ассет, звука просто не будет — в логе появится «User is not authorized
-- to access Asset» с этим id. Таких строк в проекте уже хватает у чужих звуков.
local TICK_SOUND = "rbxassetid://84029268482132"    -- щелчок на каждой смене приза
local LAND_SOUND = "rbxassetid://126557239554258"   -- приз выпал

local tickSfx = new("Sound", {
	Name = "RollTick", SoundId = TICK_SOUND, Volume = 0.35,
}, screen)
local landSfx = new("Sound", {
	Name = "RollLand", SoundId = LAND_SOUND, Volume = 0.8, PlaybackSpeed = 0.85,
}, screen)

-- ⚠️ ЩЕЛЧОК С РАСТУЩИМ ТОНОМ, А НЕ ОДИН И ТОТ ЖЕ ЗВУК N РАЗ.
-- Ровные одинаковые щелчки звучат как часы и никуда не ведут. Барабан должен
-- «дотягиваться» до конца: чем ближе остановка, тем выше тон — тогда даже с
-- закрытыми глазами слышно, что вот-вот выпадет. progress 0..1 — доля пройденного.
local function playTick(progress)
	tickSfx.PlaybackSpeed = 1.0 + math.clamp(progress, 0, 1) * 0.25
	tickSfx.TimePosition = 0
	pcall(function() tickSfx:Play() end)
end

local spinning = false
local current = nil
local function showPrize(it)
	itemImg.Image = it.img
	label.Text = it.label
	setStars(it.stars or 0)
	local pct = (activeTotal > 0) and (it.chance or 0) / activeTotal * 100 or 0
	chanceLabel.Text = string.format("%d%% шанс", math.floor(pct + 0.5))
end
local function tweenScale(to, dur)
	TweenService:Create(itemScale, TweenInfo.new(dur, Enum.EasingStyle.Quad), { Scale = to }):Play()
end
-- pick a prize that isn't the one just shown (so it never repeats back-to-back)
local function pickDifferent(exclude)
	if #activePool <= 1 then return activePool[1] end
	local it
	repeat it = activePool[math.random(#activePool)] until it ~= exclude
	return it
end

-- pick the WINNER weighted by each item's `chance` (so the shown % is the real odds);
-- retried a few times so it still differs from the last flashed prize when possible
local function pickWeighted(exclude)
	if activeTotal <= 0 then return pickDifferent(exclude) end
	for _ = 1, 8 do
		local r = math.random() * activeTotal
		local acc = 0
		for _, it in ipairs(activePool) do
			acc += (it.chance or 0)
			if r <= acc then
				if it ~= exclude then return it end
				break
			end
		end
	end
	return pickDifferent(exclude)
end

local function spin(night)
	if spinning then return end
	spinning = true
	activePool = buildPool(night) -- this night's weapons: night 1 excludes ПВО & beefs the Cannon; later = all
	recomputeTotal()
	current = nil
	panel.Visible = true
	keepBtn.Visible = false
	skipBtn.Visible = false
	triggerBtn.Visible = false
	itemImg.Visible = true
	glow.Visible = true
	label.Visible = true
	chanceLabel.Visible = true
	starRow.Visible = true

	local last = nil
	local elapsed = 0
	local rollSpan = math.max(ROLL_TIME - PER_ITEM, PER_ITEM)
	while elapsed < ROLL_TIME - PER_ITEM do
		local it = pickDifferent(last)
		last = it
		showPrize(it)
		playTick(elapsed / rollSpan)   -- тон растёт к концу прокрутки
		itemScale.Scale = MIN_SCALE
		-- Отскок карточки тоже привязан к темпу: доли от PER_ITEM, а не свои числа.
		tweenScale(1.0, PER_ITEM * 0.5)                                        -- вырасти до 100%
		task.delay(PER_ITEM * 0.55, function() tweenScale(MIN_SCALE, PER_ITEM * 0.375) end)
		task.wait(PER_ITEM)
		elapsed += PER_ITEM
	end

	-- land on the winner — weighted by this day's effective `chance`, different from the last shown.
	-- The pool already encodes the day rules (day 1: no ПВО + beefed Cannon; later days: everything).
	local winner = pickWeighted(last)
	showPrize(winner)
	-- Удар выпадения — вместе с показом победителя, а не после кнопок: звук должен
	-- совпасть с моментом, когда барабан ВСТАЛ, иначе он читается как отдельное
	-- событие, к рулетке не относящееся.
	landSfx.TimePosition = 0
	pcall(function() landSfx:Play() end)
	itemScale.Scale = MIN_SCALE
	tweenScale(1.0, 0.3)
	current = winner          -- set BEFORE the buttons appear (so Keep always works)
	task.wait(0.32)
	keepBtn.Visible = true
	skipBtn.Visible = true
	spinning = false
end

triggerBtn.MouseButton1Click:Connect(spin)

-- ── close / slot pick ──
local function endPick()
	for _, b in ipairs(pickBtns) do if b.Parent then b:Destroy() end end
	pickBtns = {}
	picking = false
	pickHint.Visible = false
	cancelBtn.Visible = false
end
local function closeAll()
	endPick()
	panel.Visible = false
	current = nil
end

-- highlight every hotbar slot; clicking one grants the prize into the inventory
local function beginPick()
	local bar = playerGui:FindFirstChild("Hotbar", true)
	if not bar then
		if current then claimEvent:FireServer(current.name) end -- no hotbar found → just grant
		closeAll()
		return
	end
	picking = true
	pickHint.Visible = true
	cancelBtn.Visible = true
	for i = 1, 8 do
		local slot = bar:FindFirstChild("HotbarSlot_" .. i)
		if slot and slot:IsA("GuiObject") then
			-- overlay is a child of the slot (fills it exactly — no alignment math)
			local btn = new("TextButton", {
				Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, 0),
				BackgroundColor3 = Color3.fromRGB(255, 235, 120), BackgroundTransparency = 0.5,
				Text = "", ZIndex = 50, AutoButtonColor = false,
			}, slot)
			new("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)
			new("UIStroke", { Color = Color3.fromRGB(255, 240, 140), Thickness = 3 }, btn)
			local slotIndex = i
			btn.MouseButton1Click:Connect(function()
				if current then
					-- bump this slot's item into the grid + route the won tool here,
					-- then have the server hand the tool over
					if _G.RewardClaimToSlot then _G.RewardClaimToSlot(current.name, slotIndex) end
					claimEvent:FireServer(current.name)
				end
				closeAll()
			end)
			table.insert(pickBtns, btn)
		end
	end
end

keepBtn.MouseButton1Click:Connect(function()
	-- hide the roll, ask the player to pick a hotbar slot
	itemImg.Visible = false
	glow.Visible = false
	label.Visible = false
	chanceLabel.Visible = false
	starRow.Visible = false
	keepBtn.Visible = false
	skipBtn.Visible = false
	panel.Visible = false
	beginPick()
end)
skipBtn.MouseButton1Click:Connect(closeAll) -- skip: no reaction
cancelBtn.MouseButton1Click:Connect(closeAll)

-- ── entry point ──
-- The reward crate (RewardCrate.server) flies to the player and, on arrival, fires OpenWeaponCrate.
-- That is now the ONLY way the roulette opens — one spin per crate, i.e. one per cleared wave.
task.spawn(function()
	local openCrate = ReplicatedStorage:WaitForChild("OpenWeaponCrate", 30)
	if openCrate then
		openCrate.OnClientEvent:Connect(function(night) spin(night) end)
	end
end)

-- ⚠️ ТЕСТОВОЙ КНОПКИ «ЛАКИ-БЛОК» ЗДЕСЬ БОЛЬШЕ НЕТ.
-- Она стояла справа сверху и была доступна ВСЕМ: на телефоне админом не
-- зайти, а проверять полёт ящика и рулетку надо было именно оттуда. Тесты
-- прошли — кнопка убрана вместе с серверной веткой, которая пускала это
-- действие без проверки прав (SettingsMenuActions, слово TEST_LUCKY).
-- Ящик по-прежнему прилетает своим ходом: от разбитого корабля и по
-- событию OpenWeaponCrate выше.
