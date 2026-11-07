-- WeaponFeel.client.lua
-- Визуальный фидбек стрелкового оружия В РУКЕ (клиент, только для локального игрока):
--   1) ствол ПОДНИМАЕТСЯ/ОПУСКАЕТСЯ за прицелом (наклон грипа за курсором) — как у Pirate Gun;
--   2) ОТДАЧА — оружие дёргается назад+вверх при выстреле и плавно возвращается.
--
-- Работает с оружием на базе AK-kit (признак — папка Configs с полем Ammo). Стволы, у
-- которых УЖЕ есть свой серверный прицел (Remotes.Aim, напр. Pirate Gun), пропускаются —
-- ими занимается их собственный BackendScript (там же своя, более сильная отдача).
-- Выстрел ловим по уменьшению Configs.Ammo — работает и для одиночных, и для автоматических.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()

local MAX_PITCH = math.rad(70) -- предел наклона ствола вверх/вниз
local TILT_SIGN = -1           -- как у Pirate Gun (тот же kit); если наклон в обратную сторону — поставь 1

-- сила отдачи по имени оружия: back = назад (студы), up = вверх (рад), decay = скорость возврата
local RECOIL = {
	["AK-47"] = { back = 0.35, up = math.rad(5), decay = 12 }, -- у автомата отдача СЛАБАЯ
}
local DEFAULT_RECOIL = { back = 0.35, up = math.rad(5), decay = 12 }

local function attach(tool)
	if not tool:IsA("Tool") then return end
	local handle = tool:FindFirstChild("Handle")
	if not handle then return end
	-- источник патронов: AK-kit (Configs.Ammo) ИЛИ Corsair (Values.Bullets, напр. Revolver)
	local configs = tool:FindFirstChild("Configs")
	local ammo = configs and configs:FindFirstChild("Ammo")
	if not ammo then
		local values = tool:FindFirstChild("Values")
		ammo = values and values:FindFirstChild("Bullets")
	end
	if not ammo then return end -- не стрелковое оружие — пропускаем
	local remotes = tool:FindFirstChild("Remotes")
	if remotes and remotes:FindFirstChild("Aim") then return end -- свой серверный прицел (Pirate Gun)

	local recipe = RECOIL[tool.Name] or DEFAULT_RECOIL
	local baseGrip = tool.Grip
	local recoil = 0            -- 0..1, затухает
	local prevAmmo = ammo.Value
	local conns = {}

	table.insert(conns, ammo.Changed:Connect(function(v)
		if v < prevAmmo then recoil = 1 end -- патронов стало меньше → был выстрел → толчок
		prevAmmo = v
	end))

	table.insert(conns, RunService.RenderStepped:Connect(function(dt)
		if not tool.Parent then return end
		-- прицел: наклон ствола к точке под курсором (1-е и 3-е лицо — через mouse.Hit)
		local dir = mouse.Hit.Position - handle:GetPivot().Position
		local pitch = 0
		if dir.Magnitude > 0.001 then
			pitch = math.clamp(math.asin(math.clamp(dir.Unit.Y, -1, 1)), -MAX_PITCH, MAX_PITCH) * TILT_SIGN
		end
		-- отдача затухает к нулю
		recoil = math.max(0, recoil - dt * recipe.decay)
		tool.Grip = baseGrip
			* CFrame.Angles(pitch + recipe.up * recoil, 0, 0)
			* CFrame.new(0, 0, -recipe.back * recoil) -- -Z = назад (к игроку), это отдача
	end))

	local unequipConn
	unequipConn = tool.Unequipped:Connect(function()
		for _, c in conns do c:Disconnect() end
		if unequipConn then unequipConn:Disconnect() end
		if tool.Parent then tool.Grip = baseGrip end -- вернуть исходный грип
	end)
end

local function hookChar(char)
	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then attach(c) end
	end)
	for _, c in char:GetChildren() do
		if c:IsA("Tool") then attach(c) end
	end
end

if player.Character then hookChar(player.Character) end
player.CharacterAdded:Connect(hookChar)
