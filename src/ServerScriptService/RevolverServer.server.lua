-- RevolverServer.server.lua  (ServerScriptService)
-- Обслуживает револьвер СНАРУЖИ, не влезая внутрь тула (Rojo плохо «усыновляет» тулы,
-- добавленные в Studio вручную, и плодит дубликаты). Работает с ЛЮБЫМ Tool, чьё имя
-- начинается на "Revolver": стрельба (быстрая пуля Bullet_Cannon → урон кораблям через
-- ShipCombat), 6 в барабане / 18 в запасе, перезарядка, дульный залп (MuzzleFX).
-- Патроны хранит в тул.Configs.Ammo/ReserveAmmo (создаёт при необходимости) — их читает
-- WeaponFeel (для отдачи) и клиент (для отображения).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local UpgradeConfig = require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig"))
local MuzzleFX      = require(ReplicatedStorage:WaitForChild("MuzzleFX"))

-- ── тюнинг ──
local MAG          = 6
local RESERVE      = 18
local COOLDOWN     = 0.4     -- сек между выстрелами
local RELOAD_TIME  = 1.6
local DMG_MULT     = 1 / 5   -- слабее ручной пушки за выстрел
local SPLASH       = 0       -- пуля НЕ взрывается (0 = без всплеска/взрыва на воде)
local SPEED        = 320     -- быстрая пуля, почти плоско
local DESPAWN      = 5

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = ReplicatedStorage end
	return r
end
local fireRemote   = ensureRemote("RevolverFire")
local reloadRemote = ensureRemote("RevolverReload")

local function isRevolver(t)
	return t ~= nil and t:IsA("Tool") and t.Name:match("^Revolver") ~= nil
end
local function heldRevolver(player)
	local c = player.Character
	local t = c and c:FindFirstChildWhichIsA("Tool")
	return isRevolver(t) and t or nil
end

-- ── ТОЧКА ДУЛА (откуда пуля и вспышка) ──
-- Раньше брали центр Handle + 2 студа по прицелу → вспышка «из середины револьвера».
-- Порядок: авторская точка Muzzle/Tip/FirePoint (как ищет корсарский CombatScript) →
-- иначе КРАЙ самой длинной оси Handle (это ствол), причём тот конец, что смотрит ПО выстрелу.
local function muzzlePos(tool, handle, dir)
	local m = tool:FindFirstChild("Muzzle", true)
		or tool:FindFirstChild("Tip", true)
		or tool:FindFirstChild("FirePoint", true)
	if m then
		if m:IsA("Attachment") then return m.WorldPosition end
		if m:IsA("BasePart") then return m.Position end
	end
	if not handle then return nil end
	local cf, sz = handle.CFrame, handle.Size
	local axes = {
		{ v = cf.RightVector, h = sz.X * 0.5 },
		{ v = cf.UpVector,    h = sz.Y * 0.5 },
		{ v = cf.LookVector,  h = sz.Z * 0.5 },
	}
	table.sort(axes, function(a, b) return a.h > b.h end)
	local a = axes[1] -- самая длинная ось = ствол
	local sign = (a.v:Dot(dir) >= 0) and 1 or -1 -- конец по направлению стрельбы = дуло
	return cf.Position + a.v * (a.h * sign)
end

-- патроны живут в тул.Configs.Ammo/ReserveAmmo/MagSize (создаём, если их нет)
local function cfg(tool)
	local c = tool:FindFirstChild("Configs")
	if not c then c = Instance.new("Folder"); c.Name = "Configs"; c.Parent = tool end
	local function v(name, def)
		local x = c:FindFirstChild(name)
		if not x then x = Instance.new("IntValue"); x.Name = name; x.Value = def; x.Parent = c end
		return x
	end
	return v("Ammo", MAG), v("ReserveAmmo", RESERVE), v("MagSize", MAG)
end

local function initTool(tool)
	local ammo, reserve, mag = cfg(tool)
	if not tool:GetAttribute("RevInit") then
		tool:SetAttribute("RevInit", true)
		ammo.Value = MAG; reserve.Value = RESERVE; mag.Value = MAG
	end
	return ammo, reserve, mag
end

local lastShot  = setmetatable({}, { __mode = "k" }) -- [tool] = tick
local reloadingF = setmetatable({}, { __mode = "k" })

-- инициализируем патроны при экипировке (чтобы клиент сразу видел 6/18)
local function watchChar(char)
	char.ChildAdded:Connect(function(c)
		if isRevolver(c) then initTool(c) end
	end)
	for _, c in char:GetChildren() do
		if isRevolver(c) then initTool(c) end
	end
end
Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(watchChar)
	if plr.Character then watchChar(plr.Character) end
end)
for _, plr in Players:GetPlayers() do
	plr.CharacterAdded:Connect(watchChar)
	if plr.Character then watchChar(plr.Character) end
end

fireRemote.OnServerEvent:Connect(function(player, dir)
	local tool = heldRevolver(player)
	if not tool then return end
	local ammo = initTool(tool)
	if reloadingF[tool] then return end
	if ammo.Value <= 0 then return end
	if lastShot[tool] and (tick() - lastShot[tool]) < COOLDOWN then return end
	if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.001 then return end

	lastShot[tool] = tick()
	ammo.Value = ammo.Value - 1
	dir = dir.Unit

	local handle = tool:FindFirstChild("Handle")
	local ss = handle and handle:FindFirstChild("ShootSound")
	if ss then ss:Play() end

	-- пуля и вспышка стартуют РОВНО с дула (а не из центра меша)
	local origin = muzzlePos(tool, handle, dir)
	if not origin then
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		origin = (hrp and hrp.Position or Vector3.zero) + dir * 2
	end
	-- у револьвера без дыма и МЕЛКИЙ залп: 1.0 — размер пушечного, для ручного ствола велик
	MuzzleFX.burst(origin, dir, { smoke = false, scale = 0.35 })

	-- пираты острова слышат хлопок и идут проверить точку (см. PirateIslandAI)
	if _G.PirateIslandShot then
		pcall(_G.PirateIslandShot, origin)
	end

	local ball = Instance.new("Part")
	ball.Name = "Bullet_Cannon" -- ShipCombat ловит по имени
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.4, 0.4, 0.4)
	ball.Color = Color3.fromRGB(70, 55, 40)
	ball.Material = Enum.Material.Metal
	ball.CanCollide = false
	ball:SetAttribute("DmgMult", DMG_MULT * UpgradeConfig.survivorWeaponMult(player))
	ball:SetAttribute("SplashRadius", SPLASH)
	ball:SetAttribute("NoExplode", true) -- пуля не взрывается (см. ShipCombat)
	-- кто стрелял: по этому TerraceIsland начисляет монеты за подожжённое поле
	ball:SetAttribute("FiredBy", player.UserId)
	ball.CFrame = CFrame.new(origin, origin + dir)

	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.2, 0); a0.Parent = ball
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.2, 0); a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0; trail.Attachment1 = a1
	trail.Lifetime = 0.15
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 150))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	trail.Parent = ball

	local creator = Instance.new("ObjectValue")
	creator.Name = "creator"; creator.Value = player; creator.Parent = ball

	ball.Parent = workspace
	ball.AssemblyLinearVelocity = dir * SPEED
	Debris:AddItem(ball, DESPAWN)
end)

reloadRemote.OnServerEvent:Connect(function(player)
	local tool = heldRevolver(player)
	if not tool then return end
	local ammo, reserve, mag = initTool(tool)
	if reloadingF[tool] then return end
	if ammo.Value >= mag.Value or reserve.Value <= 0 then return end

	reloadingF[tool] = true
	local handle = tool:FindFirstChild("Handle")
	local rs = handle and handle:FindFirstChild("ReloadSound")
	if rs then rs:Play() end

	task.wait(RELOAD_TIME)
	if tool.Parent then -- ещё существует
		local need = mag.Value - ammo.Value
		local take = math.min(need, reserve.Value)
		ammo.Value = ammo.Value + take
		reserve.Value = reserve.Value - take
	end
	reloadingF[tool] = nil
end)

print("[RevolverServer] ready")
