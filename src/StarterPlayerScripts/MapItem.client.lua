local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ПИРАТСКАЯ КАРТА В РУКАХ (Item_Map) — по клавише M.

	Нажал M — персонаж поднимает карту перед собой и читает; нажал ещё раз —
	опускает и убирает. Ходить с картой можно: ноги ведёт обычная анимация
	ходьбы, мы трогаем только руки и голову.

	⚠️ ЛИСТ ВИСИТ НА КИСТИ, НО ПОВОРОТ БЕРЁТ ОТ КОРПУСА.
	Привязать к кисти нужно, иначе при ходьбе руки и голова качаются, а лист
	стоит на месте — и выглядит, будто он летает сам по себе. Но и наследовать
	поворот кисти нельзя: кисть в этой позе завалена, лист висел наискось.
	Поэтому Motor6D к RightHand есть, а C0 пересчитывается каждый кадр: точка
	крепления едет за кистью, а разворот берётся от корпуса — лист всегда стоит
	прямо, печатной стороной к игроку.

	⚠️ У РИГА НЕТ Motor6D — ЭТО НОВЫЙ ФИЗИЧЕСКИЙ РИГ ROBLOX.
	Части держат BallSocketConstraint, а анимация задаётся целевым Transform у
	AnimationConstraint. Ищем сустав по части на стороне Attachment1 — той,
	которую он двигает. Motor6D и Bone оставлены на случай других ригов: у всех
	трёх одинаковое поле .Transform.

	⚠️ ЗНАК ПОВОРОТА ПО X В ROBLOX ОБРАТЕН ИНСТРУКЦИИ.
	Числа в ITEM_MAP_ROBLOX.md сняты из Blender: там подъём руки вперёд — минус,
	в Roblox — плюс (ось X, правило правой руки: -Y уходит в -Z, то есть вперёд).
	С минусом руки уезжали за спину. Голова наоборот: там минус = взгляд вниз.

	⚠️ ПОЗА ПИШЕТСЯ ДВАЖДЫ ЗА КАДР.
	Штатный Animate крутит те же суставы. RenderStepped не годится — он идёт до
	шага аниматора; нужен BindToRenderStep с приоритетом Character + 1. А у
	физического рига цель ещё и забирает решатель на шаге физики, поэтому ту же
	позу повторяем в Stepped — последним значением перед физикой.

	Всё локально: карту и позу видит сам игрок.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")

local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

local player = Players.LocalPlayer

local MODEL_NAME = "Item_Map"     -- модель из поставки
local TOOL_NAME  = "Map"          -- или сразу Tool с листом внутри
local KEY        = Enum.KeyCode.M

-- ⚠️ ДЕНЬ ОТКРЫТИЯ. Пока тестируем — карта доступна сразу. Чтобы выдавать её с
-- пятого дня, поставь 5 (и OPEN_FROM_DAY = 5 в MapButton.client.lua).
local REQUIRE_DAY = nil

local OPEN_TIME  = 0.53   -- поднимает (длительность MapOpen)
local CLOSE_TIME = 0.67   -- опускает (MapClose)

-- ── где висит лист ──
-- ⚠️ ВЫСОТУ ЗАДАЁТ КОРПУС, А НЕ КИСТЬ. Если считать место листа прямо от кисти,
-- он уезжает туда же, куда рука, и от первого лица пропадает из виду. Поэтому
-- база — фиксированная точка перед грудью, а от кисти берётся только тряска
-- (быстрое отклонение от её же усреднённого положения) — при ходьбе лист
-- качается вместе с рукой, но всегда остаётся перед глазами.
local READ_OFFSET = Vector3.new(0, 0.62, -1.35)     -- перед грудью, чуть ниже глаз
local LOW_OFFSET  = Vector3.new(0.7, -0.55, -0.45)  -- у бедра, пока не поднял
local HAND_FOLLOW = 1.0    -- насколько лист повторяет тряску руки
local HAND_MAX    = 0.35   -- студов, дальше не пускаем — иначе мотает
local HAND_SMOOTH = 0.03   -- скорость усреднения (вызовов два за кадр)
-- Наклон листа по X. ⚠️ НЕ ВЫПРЯМЛЯТЬ: лист держится развёрнутым к игроку
-- сверху, и это то, как надо — пробовал ставить вертикально, стало хуже.
local READ_TILT = 18     -- читает
local LOW_TILT  = 74     -- опущен у бедра

-- ── поза чтения, градусы (оси Roblox) ──
local POSE = {
	R6 = {
		["Right Arm"] = { 58, 0, -18 },
		["Left Arm"]  = { 58, 0, 18 },
		["Head"]      = { -24, 0, 0 },
	},
	R15 = {
		RightUpperArm = { 34, 0, -14 },
		LeftUpperArm  = { 34, 0, 14 },
		RightLowerArm = { 72, 0, 0 },
		LeftLowerArm  = { 72, 0, 0 },
		Head          = { -22, 0, 0 },
	},
}

local function rigOf(hum)
	return (hum.RigType == Enum.HumanoidRigType.R15) and "R15" or "R6"
end

-- Лист. В поставке он может лежать как угодно: голым Tool «Map», моделью
-- «Item_Map» с Tool'ом внутри или просто мешем — берём первую подходящую деталь.
local function partOf(root)
	if root:IsA("BasePart") then return root end
	local handle = root:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then return handle end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

local function findMapPart()
	-- по имени, а не по месту: модели разложены по папкам (см. AssetFind)
	-- ⚠️ ИМЕНА ПЕРЕБИРАЕМ ПООТДЕЛЬНОСТИ, как и в цикле ниже. Один вызов
	-- find(MODEL_NAME, TOOL_NAME) вернул бы ровно одного кандидата, и если бы у
	-- него не нашлось детали (partOf вернул nil), второе имя уже не проверялось бы.
	-- Запасной прямой поиск — для случая, когда карта лежит папкой: find нарочно
	-- отдаёт только Model/BasePart/Tool, а partOf умеет спускаться в любой корень.
	for _, name in ipairs({ MODEL_NAME, TOOL_NAME }) do
		local root = AssetFind.find(name) or ReplicatedStorage:FindFirstChild(name)
		local part = root and partOf(root)
		if part then return part end
	end
	for _, where in ipairs({ Workspace, game:GetService("StarterPack") }) do
		for _, name in ipairs({ MODEL_NAME, TOOL_NAME }) do
			local root = where:FindFirstChild(name)
			local part = root and partOf(root)
			if part then return part end
		end
	end
	return nil
end

local function dayNow()
	local dc = ReplicatedStorage:FindFirstChild("DayCount")
	return (dc and tonumber(dc.Value)) or 1
end

-- ── состояние ──
local holding = false     -- карта в руках
local phase   = "idle"    -- "open" | "read" | "close"
local phaseT  = 0
local lastK   = 0         -- насколько поза раскрыта в последнем кадре
local sheet   = nil       -- клон листа
local grip    = nil       -- Motor6D кисть → лист
local handSmooth = nil    -- усреднённое положение кисти, чтобы вычесть тряску
local motors  = {}        -- суставы текущего персонажа
local rig     = "R6"
local scanned = nil       -- для какого персонажа уже искали суставы

local function collectMotors(char)
	motors = {}
	scanned = char
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	if not hum then return end
	rig = rigOf(hum)
	local set = POSE[rig]

	local classes, jointNames = {}, {}
	for _, d in ipairs(char:GetDescendants()) do
		classes[d.ClassName] = (classes[d.ClassName] or 0) + 1
		local limb
		if d:IsA("AnimationConstraint") then
			limb = d.Attachment1 and d.Attachment1.Parent and d.Attachment1.Parent.Name
		elseif d:IsA("Motor6D") then
			limb = d.Part1 and d.Part1.Name
		elseif d:IsA("Bone") then
			limb = d.Name
		end
		if limb then
			if #jointNames < 40 then table.insert(jointNames, d.ClassName .. "→" .. limb) end
			if set[limb] then motors[limb] = d end
		end
	end

	-- пусто — риг устроен ещё как-то; вывалим устройство персонажа, чтобы не гадать
	if not next(motors) then
		local parts = {}
		for cls, n in pairs(classes) do table.insert(parts, cls .. "×" .. n) end
		table.sort(parts)
		warn("[Карта] суставов для позы нет. Внутри персонажа: " .. table.concat(parts, ", "))
		warn("[Карта] найденные суставы: "
			.. (#jointNames > 0 and table.concat(jointNames, ", ") or "ни одного"))
	end
end

local function angles(t)
	return CFrame.Angles(math.rad(t[1]), math.rad(t[2]), math.rad(t[3]))
end

-- k = 0 (руки опущены) … 1 (карта перед лицом). Сверху живое покачивание и
-- медленное «всматривание» — то, что делает MapIdle.
local function applyPose(k, t)
	lastK = k
	local set = POSE[rig]
	local lean = 0.5 + 0.5 * math.sin(t * 1.15)   -- 0..1, подтягивает лист ближе
	local sway = math.sin(t * 0.85) * 3           -- руки чуть качаются
	local look = math.sin(t * 0.55) * 6           -- взгляд бродит по листу

	for name, motor in pairs(motors) do
		local base = set[name]
		if base then
			local extraX, extraY
			if name == "Head" then
				extraX, extraY = -4 * lean, look
			else
				extraX = 4 * lean
				extraY = (name:find("Right") and -sway or sway)
			end
			local target = angles({ base[1] + extraX, base[2] + extraY, base[3] })
			motor.Transform = CFrame.identity:Lerp(target, k)
		end
	end

	-- Сам лист: место от корпуса, тряска от кисти, разворот от корпуса.
	if grip and grip.Parent and grip.Part0 then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local hand = grip.Part0
			-- отклонение кисти от собственного усреднённого положения: медленный
			-- подъём руки в среднее уходит, быстрая тряска при шаге остаётся
			local handLocal = root.CFrame:PointToObjectSpace(hand.Position)
			handSmooth = handSmooth and handSmooth:Lerp(handLocal, HAND_SMOOTH) or handLocal
			local wobble = (handLocal - handSmooth) * HAND_FOLLOW
			if wobble.Magnitude > HAND_MAX then
				wobble = wobble.Unit * HAND_MAX
			end

			local base = LOW_OFFSET:Lerp(READ_OFFSET, k) + wobble
			local tilt = LOW_TILT + (READ_TILT - LOW_TILT) * k
			-- Доворот на 180° — рисунок в меше нанесён вверх ногами. Крутим вокруг
			-- собственной оси листа (последним множителем), чтобы наклон не поехал.
			local want = root.CFrame.Rotation
				* CFrame.Angles(math.rad(tilt), math.rad(sway * 0.5), math.rad(sway * 0.4))
				* CFrame.Angles(0, math.pi, 0)
			-- C0 задаётся в осях кисти, поэтому нужную мировую позу переводим в них
			grip.C0 = hand.CFrame:Inverse() * (CFrame.new(root.CFrame * base) * want)
		end
	end
end

local function relaxPose()
	for _, motor in pairs(motors) do
		motor.Transform = CFrame.identity
	end
end

-- ── взять / убрать ──
local function dropSheet()
	if grip then grip:Destroy() end
	if sheet then sheet:Destroy() end
	grip, sheet, handSmooth = nil, nil, nil
end

local function equipMap()
	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if not (char and hum and hum.Health > 0) then return false end
	if not char:FindFirstChild("HumanoidRootPart") then return false end

	local hand = char:FindFirstChild(rigOf(hum) == "R15" and "RightHand" or "Right Arm")
	if not hand or not hand:IsA("BasePart") then
		warn("[Карта] у персонажа нет правой кисти — не к чему привязать лист")
		return false
	end

	local src = findMapPart()
	if not src then
		warn("[Карта] не нашёл ни «" .. MODEL_NAME .. "», ни Tool «" .. TOOL_NAME
			.. "» в ReplicatedStorage / Workspace / StarterPack")
		return false
	end

	collectMotors(char)

	dropSheet()
	sheet = src:Clone()
	sheet.Name = "MapSheet"
	-- клон тащит за собой сварки исходника и скрипты — иначе приваримся к плоту
	for _, d in ipairs(sheet:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("ProximityPrompt")
			or d:IsA("BaseScript") or d:IsA("Attachment") then
			d:Destroy()
		end
	end
	sheet.Anchored = false     -- держится на суставе, как обычный предмет в руке
	sheet.CanCollide = false
	sheet.CanQuery = false
	sheet.CanTouch = false
	sheet.Massless = true
	sheet.CFrame = hand.CFrame
	-- ⚠️ ЛЕЖИТ В WORKSPACE, А НЕ В ПЕРСОНАЖЕ.
	-- От первого лица штатный TransparencyController гасит все детали своего
	-- персонажа (щадит только то, что внутри Tool) — лист внутри модели просто
	-- пропадал из виду. Сустав от парента не зависит, привязка к кисти цела.
	sheet.Parent = Workspace

	grip = Instance.new("Motor6D")
	grip.Name = "MapGrip"
	grip.Part0 = hand
	grip.Part1 = sheet
	grip.Parent = hand
	applyPose(0, os.clock())   -- поставить лист сразу, чтобы не мигнул в кисти
	return true
end

-- поднять и убрать лист САМИ ПО СЕБЕ, без окна карты. Через них окно и зовёт нас
-- обратно, когда его закрывают крестиком — и без них получалась бы петля.
local function raise()
	if holding then return true end
	if not equipMap() then return false end
	holding = true
	phase, phaseT = "open", 0
	return true
end

local function putAway()
	if not holding then return end
	holding = false
	phase, phaseT = "close", 0
end

-- ⚠️ ЛИСТ В РУКАХ И ОКНО КАРТЫ — ОДИН ЖЕСТ, А НЕ ДВА.
-- Раньше _G.OpenMapMenu объявляли ОБА скрипта — этот и MapMenu. Кто загрузился
-- последним, тот и выигрывал: клавиша поднимала бумагу, а меню не открывалось
-- вовсе (или наоборот). Точка входа теперь одна и делает обе вещи.
local function toggle()
	if REQUIRE_DAY and dayNow() < REQUIRE_DAY then return end
	local menuOpen = (typeof(_G.MapMenuIsOpen) == "function") and _G.MapMenuIsOpen() or false
	if holding or menuOpen then
		putAway()
		if typeof(_G.MapMenuClose) == "function" then pcall(_G.MapMenuClose) end
	else
		-- лист может не найтись (модели нет в ReplicatedStorage) — окно всё равно
		-- открываем: смотреть карту важнее, чем держать бумагу
		raise()
		if typeof(_G.MapMenuOpen) == "function" then pcall(_G.MapMenuOpen) end
	end
end

-- кнопка карты в HUD зовёт то же самое, что клавиша
_G.OpenMapMenu = toggle
_G.MapItemPutAway = putAway

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == KEY then toggle() end
end)

-- смерть/респавн: карта остаётся от старого тела, состояние сбрасываем
player.CharacterAdded:Connect(function()
	dropSheet()
	holding, phase, motors, scanned = false, "idle", {}, nil
end)

-- ── покадровая поза, после аниматора ──
RunService:BindToRenderStep("MapPose", Enum.RenderPriority.Character.Value + 1, function(dt)
	if phase == "idle" then return end
	local char = player.Character
	if not char or not char.Parent then
		dropSheet()
		phase, holding, motors, scanned = "idle", false, {}, nil
		return
	end
	if scanned ~= char then collectMotors(char) end   -- один раз на персонажа

	phaseT += dt
	local t = os.clock()

	if phase == "open" then
		local k = math.clamp(phaseT / OPEN_TIME, 0, 1)
		applyPose(k * k * (3 - 2 * k), t)      -- мягкий вход, без рывка
		if k >= 1 then phase = "read" end
	elseif phase == "read" then
		applyPose(1, t)
	else
		local k = math.clamp(phaseT / CLOSE_TIME, 0, 1)
		applyPose(1 - k * k * (3 - 2 * k), t)
		if k >= 1 then
			relaxPose()
			dropSheet()
			phase = "idle"
		end
	end
end)

-- та же поза последним значением перед физикой — см. шапку
RunService.Stepped:Connect(function()
	if phase == "idle" or not next(motors) then return end
	applyPose(lastK, os.clock())
end)

print("[Карта] M — взять/убрать (поза считается кодом, опубликованные анимации не нужны)")
