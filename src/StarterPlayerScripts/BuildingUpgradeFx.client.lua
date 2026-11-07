--[[
	СБОРКА УЛУЧШЕНИЯ (клиент): новые детали постройки прилетают по дуге, садятся с
	пружинкой, искрами и звуком; устаревшие улетают. Основа стоит на месте.

	⚠️ НАСТОЯЩИЕ ДЕТАЛИ НЕ ДВИГАЕМ: они приварены к плоту, и сдвиг одной повёл бы
	всю сборку. Летят заякоренные клиентские копии; их место каждый кадр считается
	от ТЕКУЩЕГО пивота модели (плот плывёт и поворачивает). Настоящую деталь
	сервер показывает в конце шага (BuildingUpgradeServer) — тогда копия исчезает.

	Шаг сборки описывают атрибуты постройки: BuildFrom, BuildTo, BuildStart
	(серверное время), BuildDuration. Порядок и тайминг — BuildingLevels, тот же
	у сервера. Опоздавший клиент сразу видит конечное состояние.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local L = require(ReplicatedStorage:WaitForChild("BuildingLevels"))

local GOLD = Color3.fromRGB(255, 211, 91)
local TEAL = Color3.fromRGB(93, 240, 221)
local SOUNDS = {
	Wood   = { "rbxassetid://9120882327", 0.22 },
	Mallet = { "rbxassetid://9120904883", 0.16 },
	Metal  = { "rbxassetid://9116919223", 0.18 },
	Finish = { "rbxassetid://9116673438", 0.2 },
}
local rng = Random.new()

local fxFolder = Instance.new("Folder")
fxFolder.Name = "BuildingUpgradeFx"
fxFolder.Parent = workspace

local function now() return workspace:GetServerTimeNow() end

-- звук у самой постройки, с затуханием по расстоянию
--[[ ⚠️ ЗВУКИ ГРУЗИМ ЗАРАНЕЕ. Каждый стук создавал новый Sound — первый раз Roblox
     его ещё скачивал, и стройка начиналась в тишине, звук догонял через ~1 с.
     Заготовки висят в SoundService и прогружены при входе; играем их копии. ]]
local soundBank = Instance.new("Folder")
soundBank.Name = "BuildingUpgradeSounds"
soundBank.Parent = game:GetService("SoundService")
for name, spec in pairs(SOUNDS) do
	local t = Instance.new("Sound")
	t.Name = name
	t.SoundId = spec[1]
	t.Volume = spec[2]
	t.Parent = soundBank
end
task.spawn(function()
	pcall(function() game:GetService("ContentProvider"):PreloadAsync(soundBank:GetChildren()) end)
end)

local function sound(anchor, name, rate, volume)
	local spec = SOUNDS[name]
	if not (spec and anchor and anchor.Parent) then return end
	local tpl = soundBank:FindFirstChild(name)
	local s = tpl and tpl:Clone() or Instance.new("Sound")
	s.SoundId = spec[1]
	s.Volume = volume or spec[2]
	s.PlaybackSpeed = rate or rng:NextNumber(0.92, 1.1)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = 90
	s.Parent = anchor
	s:Play()
	Debris:AddItem(s, 4)
end

local function glow(adornee, color, seconds)
	local h = Instance.new("Highlight")
	h.Adornee = adornee
	h.FillColor = color
	h.OutlineColor = Color3.fromRGB(255, 246, 194)
	h.FillTransparency = 0.48
	h.OutlineTransparency = 0.08
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = fxFolder
	TweenService:Create(h, TweenInfo.new(seconds), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	Debris:AddItem(h, seconds + 0.1)
end

local function sparks(part)
	local a = Instance.new("Attachment")
	a.Parent = part
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(GOLD, TEAL)
	e.LightEmission = 1
	e.Lifetime = NumberRange.new(0.3, 0.65)
	e.Speed = NumberRange.new(0.5, 2)
	e.Drag = 3
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
	e.Parent = a
	e:Emit(12)
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Brightness = 2
	light.Range = 3
	light.Parent = a
	TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 0 }):Play()
end

-- заякоренная копия детали для полёта
local function ghostOf(p, texture)
	local c = p:Clone()
	for _, d in ipairs(c:GetDescendants()) do
		if not (d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture")) then d:Destroy() end
	end
	c.Anchored = true
	c.CanCollide = false
	c.CanQuery = false
	c.CanTouch = false
	c.Massless = true
	c.Transparency = 1
	c.LocalTransparencyModifier = 0
	if texture and c:IsA("MeshPart") then pcall(function() c.TextureID = texture end) end
	c.Parent = fxFolder
	return c
end

local running = setmetatable({}, { __mode = "k" })

local function play(model)
	local from, to = model:GetAttribute("BuildFrom"), model:GetAttribute("BuildTo")
	local t0, dur = model:GetAttribute("BuildStart"), model:GetAttribute("BuildDuration")
	if type(from) ~= "number" or type(to) ~= "number" or type(t0) ~= "number" or type(dur) ~= "number" or dur <= 0 then return end
	if now() > t0 + dur then return end   -- опоздали: сервер уже показал итог
	local key = t0 .. ":" .. to
	if running[model] == key then return end
	running[model] = key

	local anchor = model.PrimaryPart or model:FindFirstChild("AssemblyOrigin")
	local added, removed, kept = L.diff(model, from, to)
	local texture = L.texture(model, to)
	--[[ ⚠️ ОТСЧЁТ — ОТ САМОЙ ДЕТАЛИ AssemblyOrigin, А НЕ ОТ GetPivot(). Пивот
	     модели без PrimaryPart — застывший мировой CFrame: плот уплывал, а
	     летящие детали оставались висеть над водой. Деталь приварена к плоту. ]]
	local origin = model:FindFirstChild("AssemblyOrigin") or anchor
	if not origin then running[model] = nil return end
	local pivot = origin.CFrame
	local items = {}

	-- уходящие: копия улетает, настоящая для нас прячется до серверного решения
	for _, p in ipairs(removed) do
		local c = ghostOf(p, nil)
		c.Transparency = 0
		p.LocalTransparencyModifier = 1
		glow(c, TEAL, 0.6)
		table.insert(items, { kind = "out", part = p, ghost = c, rel = pivot:ToObjectSpace(p.CFrame), size = p.Size, t = t0 })
	end
	-- прилетающие
	for i, p in ipairs(added) do
		local rel = pivot:ToObjectSpace(p.CFrame)
		local off, rot = L.flightOffset(model, p, rel)
		table.insert(items, { kind = "in", part = p, ghost = ghostOf(p, texture), rel = rel, size = p.Size,
			off = off, rot = rot, t = t0 + L.startOf(i, #removed > 0), metal = L.isMetal(p) })
	end

	-- фон стройки: редкие стуки, пока идёт шаг
	task.spawn(function()
		local beat = 0
		while running[model] == key and now() < t0 + dur - L.TAIL do
			beat += 1
			sound(anchor, beat % 4 == 0 and "Metal" or "Wood", rng:NextNumber(0.88, 1.12), beat % 4 == 0 and 0.09 or 0.12)
			task.wait(beat % 3 == 0 and 0.75 or rng:NextNumber(0.3, 0.46))
		end
	end)

	local conn
	local function finish()
		if conn then conn:Disconnect(); conn = nil end
		for _, it in ipairs(items) do
			if it.ghost then it.ghost:Destroy() end
			if it.kind == "out" then it.part.LocalTransparencyModifier = 0 end
		end
		if running[model] == key then running[model] = nil end
	end

	conn = RunService.RenderStepped:Connect(function()
		if not model.Parent or running[model] ~= key then finish() return end
		local t = now()
		local base = origin.CFrame
		for _, it in ipairs(items) do
			local c = it.ghost
			if c then
				if it.kind == "out" then
					local u = math.clamp((t - it.t) / L.REMOVE, 0, 1)
					local away = it.rel + Vector3.new(-1, 1.45, -0.5) * u
					c.CFrame = base * away
					c.Size = it.size * (1 - 0.82 * u)
					c.Transparency = u >= 1 and 1 or 0
				else
					local u = (t - it.t) / L.FLY
					if u < 0 then
						c.Transparency = 1
					elseif u < 1 then
						if not it.started then it.started = true; glow(c, GOLD, 1.1) end
						local e = 1 - (1 - u) ^ 3
						local goal = it.rel.Position
						local start = goal + it.off
						local control = (start + goal) / 2 + Vector3.new(0, 0.65, 0)
						local pos = (1 - e) ^ 2 * start + 2 * (1 - e) * e * control + e * e * goal
						c.Transparency = 0
						c.CFrame = base * (CFrame.new(pos) * it.rel.Rotation
							* CFrame.Angles(it.rot.X * (1 - e), it.rot.Y * (1 - e), it.rot.Z * (1 - e)))
						c.Size = it.size * (0.7 + 0.3 * e)
					else
						if not it.landed then
							it.landed = true
							sparks(c)
							sound(anchor, it.metal and "Metal" or "Mallet", rng:NextNumber(0.96, 1.16), 0.19)
						end
						-- посадка: короткое пружинящее сжатие
						local s = math.clamp((t - it.t - L.FLY) / L.SETTLE, 0, 1)
						local bump = math.sin(s * math.pi) * 0.035
						c.Transparency = 0
						c.CFrame = base * it.rel
						c.Size = it.size * (1 + bump)
						-- сервер показал настоящую деталь — копия больше не нужна
						if it.part.Transparency < 1 then c:Destroy(); it.ghost = nil end
					end
				end
			end
		end
		if t > t0 + dur + 1.5 then finish() end
	end)

	-- конец шага: отделка пробегает по всей постройке, финальный звук
	task.delay(math.max(0, t0 + dur - L.TAIL - now()), function()
		if not model.Parent then return end
		glow(model, TEAL, 0.8)
		sound(anchor, "Finish", 1.65, 0.2)
	end)
	-- страховка: всё убрать, даже если сервер не ответил
	task.delay(math.max(0, t0 + dur + 2 - now()), finish)
end

-- сервер пишет BuildStart последним (после BuildFrom/To/Duration) — по нему и стартуем
local function watch(model)
	model:GetAttributeChangedSignal("BuildStart"):Connect(function()
		task.defer(play, model)
	end)
	task.defer(play, model)
end

for _, m in ipairs(CollectionService:GetTagged(L.TAG)) do watch(m) end
CollectionService:GetInstanceAddedSignal(L.TAG):Connect(watch)
