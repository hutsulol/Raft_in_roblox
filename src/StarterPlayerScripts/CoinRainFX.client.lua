local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ДОЖДЬ ИЗ МОНЕТ НА ЭКРАНЕ.

	Сервер говорит «этому игроку упало N монет» — здесь монеты сыплются СВЕРХУ
	ВНИЗ по экрану, в случайных местах, разного размера и с разной скоростью.
	Это чистое празднование: сами монеты игроку уже начислены, ловить их не надо и
	нельзя, они ни на что не влияют.

	⚠️ ПОЧЕМУ НЕ ТРЁХМЕРНЫЙ РАЗЛЁТ, КАК У ПИРАТОВ.
	Обычная выдача (_G.SpawnPirateCoins) кидает настоящие детали от трупа врага и
	притягивает их к убийце. С осьминогом это плохо читается: он тонет далеко от
	плота и часто под водой, монеты уходят под поверхность и в туман, и игрок не
	понимает, дали ему что-нибудь или нет. Экранный дождь виден при любой камере и
	с любого расстояния.

	⚠️ КОЛИЧЕСТВО НА ЭКРАНЕ ОГРАНИЧЕНО.
	Монет может прийти сколько угодно, а полсотни падающих картинок разом — это уже
	не праздник, а помеха: под ними не видно игру. Показываем не больше MAX_DROPS,
	растянув их по времени; число в уведомлении всё равно точное.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local COIN_ICON = "rbxassetid://93617165412571"   -- та же монета, что в чипе баланса

-- ⚠️ НА ЭКРАНЕ ВСЕГДА ГОРСТКА, СКОЛЬКО БЫ НИ НАЧИСЛИЛИ.
-- Монет за осьминога дают шесть-восемь десятков; высыпь их все — экран зальёт
-- сплошным потоком, за которым не видно ни воды, ни плота, и «праздник» станет
-- помехой. Показываем горстку, и не ровно одну и ту же: постоянное число сразу
-- читается как счётчик, а разброс — как настоящая россыпь.
local DROPS_MIN   = 8
local DROPS_MAX   = 12
local SPAWN_SPAN  = 1.1     -- за сколько секунд высыпать всю пачку
local FALL_MIN    = 1.5     -- сколько летит от верха до низа
local FALL_MAX    = 2.4
local SIZE_MIN    = 54      -- пикселей; ниже — сливается с фоном
local SIZE_MAX    = 92
local SIDE_MARGIN = 0.06    -- не роняем вплотную к краям экрана

-- ⚠️ ЗВУКИ ВСТРОЕННЫЕ В ДВИЖОК (rbxasset://), А НЕ ЗАГРУЖЕННЫЕ АССЕТЫ.
-- Они лежат в самом клиенте Roblox: не грузятся по сети, не зависят от прав на
-- ассет и не могут выдать «User is not authorized to access Asset» — этой ошибки
-- в логе проекта и так хватает у чужих звуков.
local REWARD_SOUND = "rbxasset://sounds/electronicpingshort.wav"   -- «тебе дали»
local COIN_SOUND   = "rbxasset://sounds/switch3.wav"               -- щелчок на монету

local rng = Random.new()

local gui = Instance.new("ScreenGui")
gui.Name = "CoinRainGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
-- ⚠️ НИЖЕ ВСЕХ МЕНЮ, НО ВЫШЕ HUD.
-- Монеты не должны падать поверх открытого инвентаря или карты — там игрок
-- читает, а не любуется. Порядок выбран между HUD (80–90) и меню (110+).
gui.DisplayOrder = 95
gui.Parent = playerGui

local rewardSfx = Instance.new("Sound")
rewardSfx.Name = "CoinRainReward"
rewardSfx.SoundId = REWARD_SOUND
rewardSfx.Volume = 0.6
rewardSfx.Parent = gui

-- ⚠️ ЩЕЛЧОК НА МОНЕТУ — ТИХИЙ И С РАЗНЫМ ТОНОМ.
-- Одинаковый звук восемь раз подряд звучит как заедающая кнопка. Случайный тон
-- превращает его в звон горсти монет, а низкая громкость держит его фоном под
-- главным «дзынь» награды, а не спорит с ним.
local coinSfx = Instance.new("Sound")
coinSfx.Name = "CoinRainTick"
coinSfx.SoundId = COIN_SOUND
coinSfx.Volume = 0.18
coinSfx.Parent = gui

-- Одна монета: падает сверху вниз, слегка сносится вбок и крутится.
local function dropCoin()
	local size = rng:NextInteger(SIZE_MIN, SIZE_MAX)
	local startX = SIDE_MARGIN + rng:NextNumber() * (1 - SIDE_MARGIN * 2)
	-- снос вбок за полёт: маленький, иначе монета уходит с экрана боком
	local driftX = (rng:NextNumber() - 0.5) * 0.12
	local fall = FALL_MIN + rng:NextNumber() * (FALL_MAX - FALL_MIN)

	coinSfx.PlaybackSpeed = 0.85 + rng:NextNumber() * 0.5
	coinSfx.TimePosition = 0
	pcall(function() coinSfx:Play() end)

	local coin = Instance.new("ImageLabel")
	coin.Name = "Coin"
	coin.AnchorPoint = Vector2.new(0.5, 0.5)
	coin.Position = UDim2.new(startX, 0, 0, -size)   -- стартуем ВЫШЕ верхней кромки
	coin.Size = UDim2.fromOffset(size, size)
	coin.BackgroundTransparency = 1
	coin.Image = COIN_ICON
	coin.ScaleType = Enum.ScaleType.Fit
	coin.Rotation = rng:NextInteger(-25, 25)
	coin.Parent = gui

	-- ⚠️ ПАДЕНИЕ — ЛИНЕЙНОЕ, А НЕ «ПО ЗАТУХАНИЮ».
	-- Со стандартным сглаживанием монета у нижней кромки заметно тормозит, будто
	-- упирается в невидимый пол. Свободное падение так не выглядит.
	local fallInfo = TweenInfo.new(fall, Enum.EasingStyle.Linear)
	TweenService:Create(coin, fallInfo, {
		Position = UDim2.new(startX + driftX, 0, 1, size),
		Rotation = coin.Rotation + rng:NextInteger(-160, 160),
	}):Play()

	-- Растворяется в последней трети пути, чтобы не «врезаться» в край экрана.
	TweenService:Create(coin, TweenInfo.new(fall * 0.35, Enum.EasingStyle.Quad,
		Enum.EasingDirection.In, 0, false, fall * 0.65), { ImageTransparency = 1 }):Play()

	Debris:AddItem(coin, fall + 0.3)
end

local function rain(count)
	-- Число падающих монет НЕ равно начисленному: см. DROPS_MIN/MAX выше.
	local n = rng:NextInteger(DROPS_MIN, DROPS_MAX)

	-- Главный звук — один и сразу: он про «тебе дали награду», а не про каждую
	-- отдельную монету. Щелчки монет идут под ним, по мере падения.
	rewardSfx.TimePosition = 0
	pcall(function() rewardSfx:Play() end)

	for i = 1, n do
		-- разносим по времени, иначе вся пачка падает одной шеренгой
		task.delay((i - 1) / n * SPAWN_SPAN + rng:NextNumber() * 0.12, dropCoin)
	end
end

_G.PlayCoinRain = rain   -- наружу: пригодится другим событиям, не только осьминогу

local event = ReplicatedStorage:WaitForChild("CoinRain", 30)
if event then
	event.OnClientEvent:Connect(function(count)
		rain(count)
	end)
else
	warn("[Дождь монет] нет ремоута CoinRain — эффект не придёт с сервера")
end

print("[Дождь монет] готов (экранный дождь вместо разлёта деталей)")
