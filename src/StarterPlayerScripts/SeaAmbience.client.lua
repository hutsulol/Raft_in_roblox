-- SeaAmbience.client.lua
-- Эмбиент океана. РАНЬШЕ: 3D-звук в парте, телепортируемом под камеру каждые 0.12с —
-- каждый скачок парта пересчитывал панораму/допплер → звук «лагал» и рвался при движении
-- камеры. ТЕПЕРЬ: звук ЕДИНЫЙ И 2D (в SoundService, без позиции — нечему прыгать), а
-- затухание считаем сами: дистанция от камеры до воды под ней → целевая громкость,
-- к которой звук ПЛАВНО подтягивается (никаких ступенек).
-- Звук: «Дальние волны 1 — спокойный рокот открытого океана» (выбран из подборки 03.07).

local Workspace    = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local RunService   = game:GetService("RunService")

local SEA_SOUND_ID = "rbxassetid://9120621792"
local SEA_VOL      = 0.55 -- максимальная громкость у самой воды
local SEA_MIN_DIST = 25   -- ближе к воде — полная громкость
local SEA_MAX_DIST = 180  -- дальше — полная тишина
local SMOOTH       = 4    -- скорость подтяжки громкости (1/с); больше = быстрее

local sea = Instance.new("Sound")
sea.Name = "SeaAmbience"
sea.SoundId = SEA_SOUND_ID
sea.Looped = true
sea.Volume = 0 -- вплывает плавно после загрузки
sea.Parent = SoundService -- 2D: без панорамы и допплера, звук единый
sea:Play()

-- воду ищем только по террейну — луч проходит сквозь плот/предметы/персонажей
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { Workspace.Terrain }
params.IgnoreWater = false

local lastWaterPos = nil -- последняя известная точка воды (ушёл вглубь острова → затухает)

task.spawn(function()
	local raft = Workspace:WaitForChild("Raft", 10)
	local pp = raft and raft.PrimaryPart
	if pp then lastWaterPos = pp.Position end -- разумный старт, пока всё грузится
	while true do
		task.wait(0.1)
		local cam = Workspace.CurrentCamera
		local from = cam and cam.CFrame.Position
		if from then
			local res = Workspace:Raycast(from + Vector3.new(0, 2, 0), Vector3.new(0, -500, 0), params)
			if res and res.Material == Enum.Material.Water then
				lastWaterPos = res.Position
			end
		end
	end
end)

-- громкость: каждый кадр плавно тянемся к целевой (звук непрерывный, без ступенек)
RunService.RenderStepped:Connect(function(dt)
	local cam = Workspace.CurrentCamera
	if not cam or not lastWaterPos then return end
	local dist = (cam.CFrame.Position - lastWaterPos).Magnitude
	local k = 1 - math.clamp((dist - SEA_MIN_DIST) / (SEA_MAX_DIST - SEA_MIN_DIST), 0, 1)
	-- пользовательская громкость из меню настроек (слайдер «Громкость океана»)
	local userScale = _G.OceanVolumeScale
	if type(userScale) ~= "number" then userScale = 1 end
	local target = SEA_VOL * k * userScale
	sea.Volume = sea.Volume + (target - sea.Volume) * math.min(1, SMOOTH * dt)
end)
