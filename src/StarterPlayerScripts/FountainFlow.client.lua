-- FountainFlow: живая вода для RaftGold_fountain. LocalScript, StarterPlayerScripts.
--
-- Ничего загружать не нужно: струи — Beam без текстуры, капли/брызги/круги —
-- клиентские Part. Скрипт сам находит в Workspace любой MeshPart с именем
-- "raftgold_fountain" (и те, что появятся позже: постройка, стриминг).
-- Размер, поворот и движение плота берутся с самого меша каждый кадр,
-- поэтому фонтан можно масштабировать, крутить и возить на плоту.
--
-- Атрибуты на модели фонтана (родитель меша), все необязательны:
--   FlowEnabled   boolean  false = вода стоит (показываются статичные струи меша)
--   FlowDistance  number   дальше этого расстояния от камеры эффект спит (по умолчанию 140)
--   StreamTexture string   "rbxassetid://..." — полосатая текстура для струй (RaftGold_stream.png)
--   SoundId       string   "rbxassetid://..." — зацикленный звук воды

local RunService = game:GetService("RunService")

-- размеры модели в её собственных единицах (1.0 = плитка пола), от подошвы
local H_TOTAL = 0.457 -- высота меша: по ней считается масштаб
local H_POOL = 0.090 -- зеркало нижней чаши
local H_BOWL = 0.337 -- зеркало верхней чаши
local H_TIP = 0.457 -- макушка золотого навершия
local JET_R0, JET_H0 = 0.128, 0.340 -- струя срывается с края верхней чаши
local JET_VR, JET_VH, JET_G = 0.062, 0.060, -0.310 -- r = R0 + VR*t, h = H0 + VH*t + G*t*t, t = 0..1
local JETS = 6
local DROPS_PER_JET, SPLASH_PER_JET, RINGS_PER_JET = 5, 3, 2
local TOP_DROPS = 10
local JET_PERIOD = 0.85 -- секунд на полёт капли

local WATER = Color3.fromRGB(176, 228, 242)
local FOAM = Color3.fromRGB(235, 250, 255)

local active = {}

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function fxPart(shape, color, transparency, parent)
	return make("Part", {
		Shape = shape,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.15,
		Transparency = transparency,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		Massless = true,
		Size = Vector3.new(0.1, 0.1, 0.1),
	}, parent)
end

-- Вертикаль меша — та его локальная ось, чей размер не равен двум другим
-- (0.457 против 0.564 x 0.564): импорт FBX может положить высоту в любую ось.
local function upAxis(part)
	local s, cf = part.Size, part.CFrame
	local dXY, dXZ, dYZ = math.abs(s.X - s.Y), math.abs(s.X - s.Z), math.abs(s.Y - s.Z)
	local up, height
	if dXZ <= dXY and dXZ <= dYZ then
		up, height = cf.UpVector, s.Y
	elseif dYZ <= dXY then
		up, height = cf.RightVector, s.X
	else
		up, height = cf.LookVector, s.Z
	end
	if up.Y < 0 then
		up = -up
	end
	return up, height
end

local function pulse(u, lo, hi)
	-- прозрачность вдоль струи с бегущим плотным сгустком в точке u
	local keys = { NumberSequenceKeypoint.new(0, lo) }
	for _, k in { { u - 0.14, lo }, { u, hi }, { u + 0.14, lo } } do
		if k[1] > 0.01 and k[1] < 0.99 then
			table.insert(keys, NumberSequenceKeypoint.new(k[1], k[2]))
		end
	end
	table.insert(keys, NumberSequenceKeypoint.new(1, lo + 0.1))
	return NumberSequence.new(keys)
end

local function start(mesh)
	if active[mesh] then
		return
	end
	local root = mesh.Parent
	if not root then
		return
	end
	active[mesh] = true

	local runtime = make("Folder", { Name = "FountainFlow_Client" }, root)
	local anchor = fxPart(Enum.PartType.Block, WATER, 1, runtime)
	anchor.Name = "FlowAnchor"

	local jets = {}
	for k = 1, JETS do
		local a = (k - 1) * 2 * math.pi / JETS + 0.3
		local jet = {
			dir = Vector3.new(math.cos(a), 0, math.sin(a)),
			a0 = make("Attachment", { Name = "Jet" .. k .. "_A" }, anchor),
			a1 = make("Attachment", { Name = "Jet" .. k .. "_B" }, anchor),
			drops = {},
			splashes = {},
			rings = {},
		}
		jet.beam = make("Beam", {
			Attachment0 = jet.a0,
			Attachment1 = jet.a1,
			Color = ColorSequence.new(FOAM, WATER),
			LightEmission = 0.25,
			LightInfluence = 0.8,
			FaceCamera = true,
			Segments = 14,
			TextureMode = Enum.TextureMode.Wrap,
			TextureSpeed = 2.2,
		}, anchor)
		for i = 1, DROPS_PER_JET do
			jet.drops[i] = fxPart(Enum.PartType.Ball, FOAM, 0.15, runtime)
		end
		for i = 1, SPLASH_PER_JET do
			jet.splashes[i] = fxPart(Enum.PartType.Ball, FOAM, 0.1, runtime)
		end
		for i = 1, RINGS_PER_JET do
			jet.rings[i] = fxPart(Enum.PartType.Cylinder, FOAM, 0.6, runtime)
		end
		jets[k] = jet
	end
	local topDrops, bowlRings = {}, {}
	for i = 1, TOP_DROPS do
		topDrops[i] = fxPart(Enum.PartType.Ball, FOAM, 0.1, runtime)
	end
	for i = 1, 3 do
		bowlRings[i] = fxPart(Enum.PartType.Cylinder, FOAM, 0.6, runtime)
	end
	local sound = make("Sound", { Name = "Water", Looped = true, Volume = 0.35, RollOffMaxDistance = 60, RollOffMinDistance = 6 }, anchor)

	local all = {}
	for _, p in runtime:GetChildren() do
		if p:IsA("BasePart") and p ~= anchor then
			table.insert(all, p)
		end
	end

	local shown = true
	local lastScale = 0
	local function setShown(on)
		if shown == on then
			return
		end
		shown = on
		for _, p in all do
			p.LocalTransparencyModifier = on and 0 or 1
		end
		for _, jet in jets do
			jet.beam.Enabled = on
		end
		if on and sound.SoundId ~= "" then
			sound:Play()
		else
			sound:Stop()
		end
	end

	local connection
	connection = RunService.PreRender:Connect(function()
		if not mesh:IsDescendantOf(workspace) then
			connection:Disconnect()
			runtime:Destroy()
			active[mesh] = nil
			return
		end
		local up, height = upAxis(mesh)
		local s = height / H_TOTAL -- стадов на единицу модели
		local base = mesh.Position - up * (height / 2)
		local camera = workspace.CurrentCamera
		local far = camera and (camera.CFrame.Position - base).Magnitude > (root:GetAttribute("FlowDistance") or 140)
		local enabled = root:GetAttribute("FlowEnabled") ~= false and not far

		-- статичные струи меша — запасной вид: видны, только когда живые выключены
		local static = root:FindFirstChild("raftgold_fountain_jets", true)
		if static and static:IsA("BasePart") then
			static.LocalTransparencyModifier = enabled and 1 or 0
		end
		setShown(enabled)
		if not enabled then
			return
		end

		local soundId = root:GetAttribute("SoundId") or ""
		if sound.SoundId ~= soundId then
			sound.SoundId = soundId
			if soundId ~= "" then
				sound:Play()
			end
		end
		local texture = root:GetAttribute("StreamTexture") or ""

		-- базис фонтана: e1/e2 в плоскости чаш, up по оси
		local ref = mesh.CFrame.RightVector -- ось самого меша: эффект поворачивается вместе с плотом
		if math.abs(ref:Dot(up)) > 0.9 then
			ref = mesh.CFrame.LookVector
		end
		local e1 = (ref - up * ref:Dot(up)).Unit
		local e2 = e1:Cross(up) -- правая тройка (e1, up, e2), иначе CFrame выйдет зеркальным
		local frame = CFrame.fromMatrix(base, e1, up, e2)
		anchor.CFrame = frame
		local function at(dir, r, h)
			return frame * Vector3.new(dir.X * r * s, h * s, dir.Z * r * s)
		end

		local now = workspace:GetServerTimeNow()
		local rescale = math.abs(s - lastScale) > 1e-4
		lastScale = s

		for k, jet in jets do
			local d = jet.dir
			if rescale then
				-- кубическая Безье бима ровно повторяет параболу: касательные в концах,
				-- плечи |v|/3 и 2/3*|v/2 + g|
				local tan = Vector3.new(-d.Z, 0, d.X)
				local v0 = (d * JET_VR + Vector3.yAxis * JET_VH)
				local v1 = (d * JET_VR * 0.5 + Vector3.yAxis * (JET_VH * 0.5 + JET_G))
				jet.a0.CFrame = CFrame.fromMatrix(Vector3.new(d.X * JET_R0, JET_H0, d.Z * JET_R0) * s, v0.Unit, tan)
				jet.a1.CFrame = CFrame.fromMatrix(
					Vector3.new(d.X * (JET_R0 + JET_VR), JET_H0 + JET_VH + JET_G, d.Z * (JET_R0 + JET_VR)) * s,
					v1.Unit,
					tan
				)
				jet.beam.CurveSize0 = v0.Magnitude / 3 * s
				jet.beam.CurveSize1 = v1.Magnitude * 2 / 3 * s
				jet.beam.TextureLength = 0.12 * s
			end
			local wob = 1 + 0.12 * math.sin(now * 11 + k * 1.7) + 0.06 * math.sin(now * 23 + k)
			jet.beam.Width0 = 0.020 * s * wob
			jet.beam.Width1 = 0.030 * s * (2 - wob)
			jet.beam.Texture = texture
			jet.beam.Transparency = pulse((now / JET_PERIOD + k / JETS) % 1, 0.45, 0.12)

			for i, p in jet.drops do
				local t = (now / JET_PERIOD + (i - 1) / DROPS_PER_JET + k * 0.37) % 1
				local side = 0.006 * math.sin(i * 2.4 + k)
				local pos = at(d, JET_R0 + JET_VR * t, JET_H0 + JET_VH * t + JET_G * t * t)
					+ (e1 * -d.Z + e2 * d.X) * side * s
				local size = (0.010 + 0.006 * ((i * 7 + k * 3) % 5) / 4) * s
				p.Size = Vector3.new(size, size, size)
				p.Position = pos
			end
			local hit = at(d, JET_R0 + JET_VR, H_POOL)
			for i, p in jet.splashes do
				local u = (now * 1.9 + (i - 1) / SPLASH_PER_JET + k * 0.21) % 1
				local a = i * 2.399 + k
				local size = (0.013 * (1 - u) + 0.004) * s
				p.Size = Vector3.new(size, size, size)
				p.Position = hit
					+ (e1 * math.cos(a) + e2 * math.sin(a)) * (0.030 * u * s)
					+ up * ((0.004 + 0.11 * u * (1 - u)) * s)
				p.Transparency = 0.1 + 0.9 * u * u
			end
			for i, p in jet.rings do
				local u = (now * 0.8 + (i - 1) / RINGS_PER_JET + k * 0.13) % 1
				local dia = (0.02 + 0.10 * u) * s
				p.Size = Vector3.new(0.0015 * s, dia, dia)
				p.CFrame = CFrame.fromMatrix(hit + up * ((0.0015 + 0.0004 * i) * s), up, e1)
				p.Transparency = 0.7 + 0.3 * u
			end
		end

		-- навершие бьёт ключом: капли взлетают над макушкой и падают в верхнюю чашу
		for i, p in topDrops do
			local t = (now * 1.25 + (i - 1) / TOP_DROPS) % 1
			local a = i * 2.399
			local reach = 0.045 + 0.030 * ((i * 5) % 7) / 6
			local h = H_TIP + 0.075 * 4 * t * (1 - t) * (1 - 0.35 * t) - (H_TIP - H_BOWL) * t * t
			local size = (0.011 * (1 - 0.4 * t)) * s
			p.Size = Vector3.new(size, size, size)
			p.Position = at(Vector3.new(math.cos(a), 0, math.sin(a)), reach * t, h)
		end
		for i, p in bowlRings do
			local u = (now * 0.7 + (i - 1) / 3) % 1
			local dia = (0.06 + 0.15 * u) * s
			p.Size = Vector3.new(0.0015 * s, dia, dia)
			p.CFrame = CFrame.fromMatrix(at(Vector3.xAxis, 0, H_BOWL + 0.0015 + 0.0004 * i), up, e1)
			p.Transparency = 0.72 + 0.28 * u
		end
	end)
end

local function discover(instance)
	if instance:IsA("MeshPart") and instance.Name == "raftgold_fountain" then
		task.defer(start, instance)
	end
end

for _, instance in workspace:GetDescendants() do
	discover(instance)
end
workspace.DescendantAdded:Connect(discover)
