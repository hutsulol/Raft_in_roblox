--[[
	ВИНЬЕТКА УРОНА: красная кромка по краям экрана, тем плотнее, чем меньше здоровья.

	⚠️ ЧЕТЫРЕ ГРАДИЕНТНЫЕ КРОМКИ ВМЕСТО КАРТИНКИ.
	Раньше эффект был одним ImageLabel с растянутой на экран PNG-виньеткой. На
	телефоне (широкий и низкий экран) картинка ложилась криво: красным была
	только узкая полоса у левого края, остальной экран чистый — владелец
	прислал скриншот. Кромки из фреймов с UIGradient от этого не зависят: каждая
	считается в долях экрана и накрывает свою сторону целиком при любом
	соотношении сторон. Тот же приём уже работает у ядовитой воды
	(WaterVignette.client.lua).

	Файл исторически называется WaterVingette (с опечаткой) — имя оставлено,
	чтобы не плодить дубликаты скриптов в плейсе (см. память о $ignoreUnknownInstances).
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RED       = Color3.fromRGB(200, 20, 20)
local EDGE      = 0.32   -- доля экрана под кромку с каждой стороны
local MAX_ALPHA = 0.85   -- плотность у самого края при нуле здоровья

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DamageVignette"
screenGui.ResetOnSpawn = false   -- иначе Roblox удаляет окно при смерти, а скрипт живёт дальше с мёртвым объектом
screenGui.DisplayOrder = 100
screenGui.IgnoreGuiInset = true
-- ⚠️ ДО САМОЙ КРОМКИ ЭКРАНА. По умолчанию ScreenGui не заходит в «безопасную»
-- зону iPhone (чёлка, скруглённые углы, полоса жеста внизу) — у краёв оставалась
-- чистая рамка, и виньетка выглядела обрезанной. None отдаёт весь экран.
pcall(function() screenGui.ScreenInsets = Enum.ScreenInsets.None end)
screenGui.Parent = playerGui

local edges = {}
local function makeEdge(pos, size, rotation)
	local f = Instance.new("Frame")
	f.Name = "Edge"
	f.BackgroundColor3 = RED
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	f.Parent = screenGui
	local g = Instance.new("UIGradient")
	g.Rotation = rotation   -- плотно у края экрана → прозрачно к центру
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.55, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	table.insert(edges, f)
end
makeEdge(UDim2.fromScale(0, 0),        UDim2.fromScale(1, EDGE), 90)    -- верх
makeEdge(UDim2.fromScale(0, 1 - EDGE), UDim2.fromScale(1, EDGE), -90)   -- низ
makeEdge(UDim2.fromScale(0, 0),        UDim2.fromScale(EDGE, 1), 0)     -- лево
makeEdge(UDim2.fromScale(1 - EDGE, 0), UDim2.fromScale(EDGE, 1), 180)   -- право

-- Track current opacity for smooth transitions (1 = невидимо, 0 = максимум)
local currentTransparency = 1
local targetTransparency = 1

local function onCharacterAdded(char)
	local hum = char:WaitForChild("Humanoid")

	hum.HealthChanged:Connect(function(newHealth)
		local ratio = newHealth / math.max(1, hum.MaxHealth)
		-- Full health = fully transparent (1), no health = fully visible (0)
		targetTransparency = ratio
	end)

	-- Initialize
	targetTransparency = hum.Health / math.max(1, hum.MaxHealth)
end

local char = player.Character
if char then
	task.spawn(onCharacterAdded, char)
end
player.CharacterAdded:Connect(function(newChar)
	currentTransparency = 1
	targetTransparency = 1
	onCharacterAdded(newChar)
end)

-- Smooth interpolation loop
RunService.Heartbeat:Connect(function(dt)
	currentTransparency = currentTransparency + (targetTransparency - currentTransparency) * math.min(1, dt * 5)
	-- плотность кромки: чем меньше здоровья, тем ближе к MAX_ALPHA
	local alpha = 1 - (1 - currentTransparency) * MAX_ALPHA
	for _, f in ipairs(edges) do
		f.BackgroundTransparency = alpha
	end
end)
