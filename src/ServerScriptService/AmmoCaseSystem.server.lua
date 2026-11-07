-- AmmoCaseSystem.server.lua
-- Ящик с патронами (Workspace.Ammo_case). При нажатии E:
--   1) отпадают лямки lyamka_1 / lyamka_2 (снимаем велды → падают физикой);
--   2) через 0.5 c крышка `top` ПРОСТО ОТЛЕТАЕТ (как у обычных ящиков дайвера) — импульс
--      вверх-назад, без шарниров;
--   3) вылетает иконка снарядов;
--   4) игроку пополняются ЗАПАСНЫЕ патроны на ВСЕХ его пушках до максимума
--      (обойма/магазин Configs.Ammo НЕ трогается — только Configs.ReserveAmmo);
--   5) через 2 c ящик плавно растворяется и исчезает.
--
-- Спавн копий (дайвер 25% / волна 50%): шаблон берётся из ReplicatedStorage.Ammo_case.
-- _G.SpawnAmmoCase(поз, "sea"|"deck").

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")
local TweenService      = game:GetService("TweenService")
local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

local AMMO_ICON  = "rbxassetid://109564189076821"
local PROMPT_KEY = Enum.KeyCode.E
local OPEN_RANGE = 10
local STRAP_DELAY = 0.5   -- пауза между падением лямок и открытием крышки
local OPEN_TIME   = 0.45  -- длительность откидывания крышки

-- Максимум ЗАПАСНЫХ патронов по базовому имени оружия (обойму не трогаем).
-- Revolver: Configs.ReserveAmmo max = 18 (RevolverServer.RESERVE).
-- Pirate_Gun: спавн-запас = 9. Для новых стволов — Configs.MaxReserveAmmo или MagSize*3.
local MAX_RESERVE = {
	Revolver   = 18,
	Pirate_Gun = 9,
	PirateGun  = 9,
}

local setupDone = setmetatable({}, { __mode = "k" })

-- "Revolver (6/18)" → "Revolver"
local function baseName(name)
	return (name:gsub("%s*%b()%s*$", ""))
end

-- снять любые велды, где part — Part0/Part1 (иначе крышку/лямку держит велд)
local function clearWelds(part, root)
	for _, d in ipairs(root:GetDescendants()) do
		if (d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") or d:IsA("ManualWeld"))
			and (d.Part0 == part or d.Part1 == part) then
			d:Destroy()
		end
	end
end

local function raftPrimary()
	local r = workspace:FindFirstChild("Raft")
	return r and r.PrimaryPart
end

-- плавное исчезновение всей модели (после открытия)
local function fadeAndDestroy(model, dur)
	dur = dur or 1.0
	local info = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		elseif d:IsA("Decal") or d:IsA("Texture") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	Debris:AddItem(model, dur + 0.2)
end

-- ── пополнение запасных патронов на всех пушках игрока ──
local function refillAmmo(player)
	local containers = {}
	if player.Character then table.insert(containers, player.Character) end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then table.insert(containers, bp) end

	local guns = 0
	for _, cont in ipairs(containers) do
		for _, tool in ipairs(cont:GetChildren()) do
			if tool:IsA("Tool") then
				local cfg = tool:FindFirstChild("Configs")
				local reserve = cfg and cfg:FindFirstChild("ReserveAmmo")
				if reserve and reserve:IsA("IntValue") then
					local maxCfg = cfg:FindFirstChild("MaxReserveAmmo")
					local mag    = cfg:FindFirstChild("MagSize")
					local maxV = (maxCfg and maxCfg.Value)
						or MAX_RESERVE[baseName(tool.Name)]
						or (mag and mag.Value * 3)
						or reserve.Value
					if maxV > reserve.Value then reserve.Value = maxV end -- обойма (Ammo) не трогается
					guns += 1
				end
			end
		end
	end
	print(("[AmmoCase] %s: запасные патроны пополнены на %d пушках"):format(player.Name, guns))
	-- ⚠️ С СЕРВЕРА — ЧЕРЕЗ NotifyPlayer, А НЕ _G.Notify.
	-- _G.Notify объявлен в клиентском NotificationCenter, и на сервере его просто
	-- нет: этот отказ до игрока не доходил вовсе.
	if guns == 0 and _G.NotifyPlayer then
		_G.NotifyPlayer(player, { type = "warn", icon = "🔫", title = "Нет оружия",
			body = "Патроны пополнять некому — возьми оружие" })
	end
end

-- Наружу: тем же путём патроны выдаёт бочка (BarrelSystem) и меню настроек.
-- Правила «сколько максимум в запасе у какого ствола» должны жить в ОДНОМ
-- месте, иначе новый ствол придётся прописывать в трёх файлах.
_G.RefillReserveAmmo = function(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	refillAmmo(player)
end

-- ── вылет иконки снарядов (по мотивам ящиков дайвера) ──
local function flyAmmoIcon(caseRef)
	if not caseRef then return end
	local baseY = caseRef.Size.Y / 2 + 0.6
	local bb = Instance.new("BillboardGui")
	bb.Name = "AmmoPrize"
	bb.Adornee = caseRef          -- едет вместе с кейсом/плотом
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.new(1.4, 0, 1.4, 0)
	bb.StudsOffset = Vector3.new(0, baseY, 0)
	bb.Parent = caseRef
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = AMMO_ICON
	img.Parent = bb

	task.spawn(function()
		local D_RISE, D_GROW, D_HOLD, D_FADE = 0.45, 0.3, 0.7, 0.4
		local RISE, GROW = 3.0, 1.1
		local t0 = os.clock()
		while bb.Parent do
			local dt = RunService.Heartbeat:Wait()
			local t = os.clock() - t0
			if t < D_RISE then                       -- вылетает вверх, крутясь
				local a = 1 - (1 - t / D_RISE) ^ 2
				bb.StudsOffset = Vector3.new(0, baseY + RISE * a, 0)
				img.Rotation = (img.Rotation + 540 * dt) % 360
			elseif t < D_RISE + D_GROW then          -- растёт, вращение замирает
				local a = (t - D_RISE) / D_GROW
				bb.Size = UDim2.new(1.4 + GROW * a, 0, 1.4 + GROW * a, 0)
				local r = img.Rotation % 360; if r > 180 then r = r - 360 end
				img.Rotation = r * (1 - a)
			elseif t < D_RISE + D_GROW + D_HOLD then  -- висит
				img.Rotation = 0
			elseif t < D_RISE + D_GROW + D_HOLD + D_FADE then -- тает
				img.ImageTransparency = (t - (D_RISE + D_GROW + D_HOLD)) / D_FADE
			else
				bb:Destroy(); break
			end
		end
	end)
end

-- ── открытие: крышка просто ОТЛЕТАЕТ (как у обычных ящиков дайвера) ──
-- Никаких шарниров — снимаем велды крышки, разанкориваем и придаём импульс вверх-назад
-- (от лямок), крышка улетает и падает. Просто и без проблем с направлением.
local function popLid(model, top, frontRef)
	clearWelds(top, model)
	top.Anchored = false
	top.CanCollide = true
	top.Massless = false

	-- отлёт НАЗАД — от лямок (они спереди)
	local away
	if frontRef then
		local v = top.Position - frontRef
		away = Vector3.new(v.X, 0, v.Z)
	end
	away = (away and away.Magnitude > 1e-3) and away.Unit or Vector3.new(0, 0, 1)
	top.AssemblyLinearVelocity  = away * 10 + Vector3.new(0, 14, 0)
	top.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))
	Debris:AddItem(top, 5)
end

-- ── падение лямок ──
local function dropStrap(strap, model)
	if not strap then return end
	for _, d in ipairs(strap:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = false; d.CanCollide = true end
	end
	if strap:IsA("BasePart") then strap.Anchored = false; strap.CanCollide = true end
	clearWelds(strap, model)
	-- модель-лямка: снять велды со всех её партов
	if strap:IsA("Model") then
		for _, d in ipairs(strap:GetDescendants()) do
			if d:IsA("BasePart") then clearWelds(d, model) end
		end
	end
	-- лёгкий толчок наружу, чтобы «отскочили»
	local part = strap:IsA("BasePart") and strap or strap:FindFirstChildWhichIsA("BasePart", true)
	if part then
		part.AssemblyLinearVelocity = Vector3.new(math.random(-6, 6), 4, math.random(-6, 6))
	end
	Debris:AddItem(strap, 6) -- убрать упавшие лямки через 6 c
end

-- ── настройка одного ящика ──
local function findCaseRef(model, top, strapSet)
	local named = model:FindFirstChild("case")
	if named and named:IsA("BasePart") then return named end
	if model.PrimaryPart then return model.PrimaryPart end
	local best, bestVol
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= top and not strapSet[d] then
			local vol = d.Size.X * d.Size.Y * d.Size.Z
			if not bestVol or vol > bestVol then best, bestVol = d, vol end
		end
	end
	return best
end

local function setup(model)
	if setupDone[model] then return end
	local top = model:FindFirstChild("top")
	if not (top and top:IsA("BasePart")) then
		warn("[AmmoCase] в " .. model:GetFullName() .. " нет BasePart 'top' — пропуск")
		return
	end
	local straps, strapSet = {}, {}
	for _, d in ipairs(model:GetChildren()) do
		if d.Name:lower():match("^lyamka") then
			straps[#straps + 1] = d
			strapSet[d] = true
			if d:IsA("Model") then
				for _, p in ipairs(d:GetDescendants()) do if p:IsA("BasePart") then strapSet[p] = true end end
			end
		end
	end
	local caseRef = findCaseRef(model, top, strapSet)
	if not caseRef then
		warn("[AmmoCase] в " .. model:GetFullName() .. " не найдено тело кейса — пропуск")
		return
	end
	setupDone[model] = true

	-- prompt: авторский, если есть, иначе создаём на теле кейса
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Открыть"
		prompt.ObjectText = "Ящик с патронами"
		prompt.KeyboardKeyCode = PROMPT_KEY
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = OPEN_RANGE
		prompt.RequiresLineOfSight = false
		prompt.Parent = caseRef
	end

	prompt.Triggered:Connect(function(player)
		if model:GetAttribute("AmmoCaseOpened") then return end
		model:SetAttribute("AmmoCaseOpened", true)
		prompt.Enabled = false

		-- запомнить, ГДЕ лямки (они спереди) ДО падения — по ним определим «назад»
		local frontRef
		do
			local sum, n = Vector3.zero, 0
			for _, s in ipairs(straps) do
				local part = s:IsA("BasePart") and s or s:FindFirstChildWhichIsA("BasePart", true)
				if part then sum += part.Position; n += 1 end
			end
			if n > 0 then frontRef = sum / n end
		end
		-- 1) лямки отпадают
		for _, s in ipairs(straps) do dropStrap(s, model) end
		-- 2) пауза, затем крышка отлетает + иконка + патроны
		task.delay(STRAP_DELAY, function()
			popLid(model, top, frontRef)
			flyAmmoIcon(caseRef)
			refillAmmo(player)
			-- через 2 c после открытия ящик плавно растворяется и исчезает
			task.delay(2, function()
				if model.Parent then fadeAndDestroy(model, 1.0) end
			end)
		end)
	end)

	print("[AmmoCase] готов: " .. model:GetFullName()
		.. (" (лямок: %d)"):format(#straps))
end

-- ── шаблон для спавна (дайвер 25% / волна 50%) — из ReplicatedStorage ──
local template
local function getTemplate()
	if template and template.Parent then return template end
	local src = AssetFind.find("Ammo_case")
	if not src then
		-- запас: клон первого ящика из Workspace, если в RS нет
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("Model") and d.Name == "Ammo_case" then src = d; break end
		end
	end
	if not src then return nil end
	template = src:Clone()
	template.Name = "Ammo_case_Template"
	template.Parent = ServerStorage
	return template
end

-- поставить модель ВЕРТИКАЛЬНО так, чтобы НИЗ её габаритов оказался в точке dropPos.
-- Через bounding box — устойчиво к кривому origin у tripo-меша (иначе улетала «в небо»).
local function placeUprightBottomAt(m, dropPos)
	local pivot = m:GetPivot()
	local boxCF, size = m:GetBoundingBox()
	local desiredCenter = CFrame.new(dropPos.X, dropPos.Y + size.Y / 2, dropPos.Z)
	m:PivotTo(desiredCenter * boxCF:Inverse() * pivot)
end

-- _G.SpawnAmmoCase(pos, mode): "sea" (плавает, не тонет) | "deck" (варится к плоту)
local function spawnAmmoCase(dropPos, mode)
	local tpl = getTemplate()
	if not tpl then
		warn("[AmmoCase] нет шаблона: положи модель Ammo_case в ReplicatedStorage")
		return nil
	end
	local m = tpl:Clone()
	m.Name = "Ammo_case"
	local body = m.PrimaryPart or m:FindFirstChild("case") or m:FindFirstChildWhichIsA("BasePart")
	if not body then m:Destroy(); return nil end
	m.PrimaryPart = body

	-- жёсткая сборка: всё варится к body (крышку/лямки освободит clearWelds при открытии)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			if p ~= body then
				local w = Instance.new("WeldConstraint")
				w.Name = "_AmmoAssembly"; w.Part0 = body; w.Part1 = p; w.Parent = body
			end
		end
	end
	body.Anchored = true -- держим, пока ставим на место
	m.Parent = workspace
	placeUprightBottomAt(m, dropPos)

	if mode == "deck" then
		local raftPP = raftPrimary()
		if raftPP then
			local w = Instance.new("WeldConstraint")
			w.Name = "_AmmoRaftWeld"; w.Part0 = raftPP; w.Part1 = body; w.Parent = body
			body.Anchored = false -- велд к плоту держит → ящик едет с плотом
		end
	else
		-- МОРЕ: плавает на месте (не тонет), лёгкое покачивание. Якорь = без физ-багов.
		local rest = body.CFrame
		local baseY = rest.Position.Y
		task.spawn(function()
			local t0 = os.clock()
			while m.Parent and body.Parent do
				RunService.Heartbeat:Wait()
				local t = os.clock() - t0
				body.CFrame = CFrame.new(rest.Position.X, baseY + math.sin(t * 1.3) * 0.35, rest.Position.Z)
					* (rest - rest.Position)
			end
		end)
	end

	setup(m) -- сделать открываемым (prompt + механика)
	return m
end

_G.SpawnAmmoCase = function(posOrCF, mode)
	local pos = (typeof(posOrCF) == "CFrame") and posOrCF.Position or posOrCF
	return spawnAmmoCase(pos, mode or "sea")
end

-- ── поиск ящиков в Workspace (уже стоящие на плоту) ──
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("Model") and d.Name == "Ammo_case" then setup(d) end
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") and d.Name == "Ammo_case" then task.defer(setup, d) end
end)

print("[AmmoCaseSystem] loaded")
