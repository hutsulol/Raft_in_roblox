--[[
	ТАВЕРНА — СЦЕНА НА КЛИЕНТЕ (хендофф IslandHall_Integration_V25:
	HallRecruitmentFX + AltarOrbFX + EmotionController + рабочая часть
	IslandHallDemo, без демо-меню, кнопок бесплатных уровней и захвата камеры).

	⚠️ ВСЁ ОТ ТОЧКИ AssemblyOrigin, КАЖДЫЙ КАДР. Здание приварено к плоту и
	плывёт; сервер в нём ничего не двигает. Двери и сфера — локальные копии
	(серверные спрятаны LocalTransparencyModifier), интерьер, работники и житель —
	локальные модели. Их поза хранится в осях здания и переводится в мир от
	текущего origin — ни одна деталь не отстаёт от плота.

	Состояние — атрибуты здания (IslandHallService): RecruitState, RecruitStartedAt,
	RecruitCycleDuration, RevealStartedAt, RevealVariant, RevealDef. Сборка жителя
	идёт по общему расписанию IslandHallConfig от RevealStartedAt: опоздавший
	клиент видит ту же фазу, что и все.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local C = require(ReplicatedStorage:WaitForChild("IslandHallConfig"))
local Anim = require(ReplicatedStorage:WaitForChild("RecruitAnimations"))
local Workshop = require(ReplicatedStorage:WaitForChild("IslandHallWorkshop"))
local D = require(ReplicatedStorage:WaitForChild("SurvivorDefs"))
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))
local remote = ReplicatedStorage:WaitForChild("IslandHallAction")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GOLD = Color3.fromRGB(255, 207, 85)
local function now() return workspace:GetServerTimeNow() end
local function smooth(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end

-- ═══ звук: позиционный, у каждой таверны свой ═══
local SOUNDS = {
	Charge = 0.52, Transfer1 = 0.42, Transfer2 = 0.42, Transfer3 = 0.42,
	Solid1 = 0.38, Solid2 = 0.38, Solid3 = 0.38, Complete = 0.65,
}
local bank = Instance.new("Folder")
bank.Name = "IslandHallAudio"
bank.Parent = game:GetService("SoundService")
local templates = {}
for name, vol in pairs(SOUNDS) do
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = C.asset(name)
	s.Volume = vol
	s.RollOffMinDistance = 7
	s.RollOffMaxDistance = 45
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.Parent = bank
	templates[name] = s
end
task.spawn(function() pcall(function() game:GetService("ContentProvider"):PreloadAsync(bank:GetChildren()) end) end)
local rng = Random.new()
local function playCue(name, part, pitch)
	if not (templates[name] and part and part.Parent) then return nil end
	local s = templates[name]:Clone()
	s.PlaybackSpeed = pitch or 1
	s.Parent = part
	s:Play()
	Debris:AddItem(s, 10)
	return s
end

-- ═══ искры: пять своих частиц (glint, wisp, flecks, swirl, ember) ═══
local SPARKS = { { "SparkGlint", 0.30, 3 }, { "SparkWisp", 0.34, 2 }, { "SparkFlecks", 0.26, 3 }, { "SparkSwirl", 0.32, 2 }, { "SparkEmber", 0.19, 5 } }
local function burst(part)
	if not (part and part.Parent) then return end
	local a = Instance.new("Attachment")
	a.Parent = part
	for i, style in ipairs(SPARKS) do
		local e = Instance.new("ParticleEmitter")
		e.Texture = C.asset(style[1])
		local size = style[2] * rng:NextNumber(0.8, 1.15)
		e.Rate = 0
		e.Lifetime = NumberRange.new(0.28, 0.55 + i * 0.035)
		e.Speed = NumberRange.new(0.7 + i * 0.12, 1.7 + i * 0.18)
		e.Drag = 3
		e.SpreadAngle = Vector2.new(180, 180)
		e.LightEmission = 0.85
		e.Rotation = NumberRange.new(-180, 180)
		e.RotSpeed = NumberRange.new(-110, 110)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.35), NumberSequenceKeypoint.new(0.14, size, size * 0.22),
			NumberSequenceKeypoint.new(0.55, size * 0.6, size * 0.12), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.14, 0.12),
			NumberSequenceKeypoint.new(0.55, 0.4), NumberSequenceKeypoint.new(1, 1) })
		e.Parent = a
		e:Emit(style[3] + rng:NextInteger(0, 1))
	end
	Debris:AddItem(a, 1)
end

-- ═══ R6: подготовка рига к постановке (корень заякорен, суставы — Motor6D) ═══
local function prepareRig(model, scale)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") then d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	model.PrimaryPart = root
	root.PivotOffset = CFrame.identity
	pcall(function() model:ScaleTo(scale) end)
	for _, n in ipairs({ "RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" }) do
		local j = model:FindFirstChild(n, true)
		if j and j:IsA("Motor6D") and j.Part0 and j.Part1 then j.Part1.CFrame = j.Part0.CFrame * j.C0 * j.C1:Inverse() end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.AutoRotate = false
		hum.BreakJointsOnDeath = false
		hum.PlatformStand = true
		pcall(function() hum.EvaluateStateMachine = false end)
	end
	local motors = {}
	for _, j in ipairs(model:GetDescendants()) do
		if j:IsA("Motor6D") then motors[j.Name] = { joint = j, base = j.C0, rotation = j.C0.Rotation } end
	end
	return motors
end

-- ═══ лицо работников (EmotionController хендоффа): обычное, моргание, рабочие эмоции ═══
local function makeFace(rig)
	local head = rig:FindFirstChild("Head")
	if not head then return nil end
	for _, d in ipairs(head:GetChildren()) do
		if d:IsA("Decal") then d.Transparency = 1 end   -- старый декаль скрыт: без двойных глаз
	end
	local canvas = Instance.new("Part")
	canvas.Name = "ExpressionSurface"
	canvas.Size = Vector3.new(head.Size.X, head.Size.Y, 0.01)
	canvas.Transparency = 1
	canvas.CanCollide = false; canvas.CanTouch = false; canvas.CanQuery = false; canvas.Massless = true
	canvas.CFrame = head.CFrame * CFrame.new(0, 0, -head.Size.Z * 0.63)
	canvas.Parent = head
	local weld = Instance.new("WeldConstraint"); weld.Part0 = head; weld.Part1 = canvas; weld.Parent = canvas
	local gui = Instance.new("SurfaceGui")
	gui.Name = "AnimatedFace"; gui.Face = Enum.NormalId.Front; gui.CanvasSize = Vector2.new(512, 256)
	gui.LightInfluence = 1; gui.Parent = canvas
	local ink = Color3.fromRGB(24, 17, 14)
	local function shape(parent, name, x, y, w, h, color, radius, rotation)
		local f = Instance.new("Frame")
		f.Name = name; f.AnchorPoint = Vector2.new(0.5, 0.5); f.Position = UDim2.fromOffset(x, y); f.Size = UDim2.fromOffset(w, h)
		f.BackgroundColor3 = color; f.BorderSizePixel = 0; f.Rotation = rotation or 0; f.Parent = parent
		if radius then local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(radius, 0); c.Parent = f end
		return f
	end
	for _, name in ipairs({ "Happy", "Focused", "Effort" }) do
		local frame = Instance.new("Frame")
		frame.Name = name; frame.Size = UDim2.fromScale(1, 1); frame.BackgroundTransparency = 1; frame.Visible = name == "Happy"; frame.Parent = gui
		local eyeHeight = name == "Effort" and 21 or 46
		for _, side in ipairs({ -1, 1 }) do
			local x = 256 + side * 54
			local eye = shape(frame, side == -1 and "EyeL" or "EyeR", x, 107, 23, eyeHeight, ink, 0.5, name == "Effort" and side * 12 or 0)
			eye:SetAttribute("OpenHeight", eyeHeight)
			local glint = shape(eye, "Glint", 0, 0, 7, 10, Color3.fromRGB(255, 255, 247), 0.5)
			glint.Position = UDim2.fromScale(0.36, 0.28)
			shape(frame, "Brow", x, 73, 35, 7, ink, 0.5, name == "Happy" and side * 9 or -side * 22)
		end
		if name == "Happy" then
			local mouth = shape(frame, "Mouth", 257, 165, 105, 60, ink, 0.4, -4)
			shape(mouth, "Teeth", 53, 13, 86, 15, Color3.fromRGB(255, 250, 237), 0.35)
			shape(mouth, "Tongue", 56, 46, 50, 19, Color3.fromRGB(218, 60, 65), 0.5)
		elseif name == "Focused" then
			shape(frame, "Mouth", 261, 167, 67, 10, ink, 0.5, -6)
			shape(frame, "Corner", 291, 162, 9, 15, ink, 0.5, 15)
		else
			local mouth = shape(frame, "Mouth", 258, 163, 86, 33, ink, 0.25)
			shape(mouth, "Teeth", 43, 16, 73, 22, Color3.fromRGB(249, 241, 216), 0.15)
			for i = 1, 3 do shape(mouth, "ToothLine", 17 + i * 14, 16, 2, 21, ink) end
			shape(frame, "Sweat", 333, 98, 9, 20, Color3.fromRGB(136, 221, 238), 0.5, 12)
		end
		shape(frame, "Scar", 162, 165, 38, 5, Color3.fromRGB(138, 75, 41), nil, -46)
		shape(frame, "ScarCross", 160, 164, 25, 5, Color3.fromRGB(138, 75, 41), nil, 40)
	end
	local nextBlink, blinkUntil = os.clock() + rng:NextNumber(2, 4), 0
	return function(action)
		local t = os.clock()
		if t >= nextBlink then blinkUntil = t + 0.14; nextBlink = t + rng:NextNumber(3.2, 5.2) end
		local mode = ({ Hammer = "Effort", Read = "Focused", Channel = "Focused" })[action] or "Happy"
		for _, frame in ipairs(gui:GetChildren()) do
			if frame:IsA("Frame") then
				frame.Visible = frame.Name == mode
				for _, eyeName in ipairs({ "EyeL", "EyeR" }) do
					local eye = frame:FindFirstChild(eyeName)
					if eye then
						eye.Size = UDim2.fromOffset(eye.Size.X.Offset, t < blinkUntil and 4 or eye:GetAttribute("OpenHeight"))
						eye.Glint.Visible = t >= blinkUntil
					end
				end
			end
		end
	end
end

-- позы R6 (RecruitAnimations) → C0 суставов, плавно
local function applyPose(motors, targetPose, dt)
	local alpha = 1 - math.exp(-14 * math.min(dt, 0.1))
	for name, d in pairs(motors) do
		local target = CFrame.new(d.base.Position) * (targetPose[name] or CFrame.identity) * d.rotation
		d.joint.C0 = d.joint.C0:Lerp(target, alpha)
	end
end

-- общий Bloom на камеру для всех сфер
local bloom = nil
local bloomUsers = 0

-- ═══ одна таверна ═══
local scenes = {}

local function setup(hall)
	if scenes[hall] then return end
	local origin = hall:WaitForChild("AssemblyOrigin", 10)
	local altar = hall:WaitForChild("RecruitAltar", 10)
	local doorsSrc = hall:WaitForChild("RecruitDoors", 10)
	local crystalSrc = hall:WaitForChild("RecruitCrystal", 10)
	if not (origin and altar and doorsSrc and crystalSrc) or scenes[hall] then return end
	local S = { conns = {} }
	scenes[hall] = S
	local folder = Instance.new("Folder")
	folder.Name = "IslandHallScene"
	folder.Parent = workspace
	S.folder = folder
	local base = origin.CFrame
	local function relOf(cf) return base:ToObjectSpace(cf) end

	-- серверные двери и сфера спрятаны: двигаются их локальные копии
	local function hideSource(model)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = 1
			elseif d:IsA("Light") then d.Enabled = false end
		end
	end
	local function localCopy(model)
		local c = model:Clone()
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("BaseScript") then d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.LocalTransparencyModifier = 0
			end
		end
		c.Parent = folder
		hideSource(model)
		return c
	end

	-- двери: петля + детали в осях петли, пружина по углу
	S.hinges = {}
	for _, src in ipairs(doorsSrc:GetChildren()) do
		if src:IsA("Model") then
			local m = localCopy(src)
			local hinge = m:FindFirstChild("Hinge") or m:FindFirstChildWhichIsA("BasePart")
			local hingeRel = relOf(hinge.CFrame)
			local partsRel = {}
			for _, p in ipairs(m:GetDescendants()) do
				if p:IsA("BasePart") then partsRel[p] = hingeRel:ToObjectSpace(relOf(p.CFrame)) end
			end
			table.insert(S.hinges, { hingeRel = hingeRel, parts = partsRel, sign = src.Name == "LeftDoor" and 1 or -1, angle = 0, velocity = 0 })
		end
	end

	-- сфера: копия RecruitCrystal, поза в осях здания
	local crystal = localCopy(crystalSrc)
	local pivot = crystal:FindFirstChild("CrystalPivot") or crystal:FindFirstChildWhichIsA("BasePart")
	local orb = crystal:FindFirstChild("GoldenSphere")
	crystal.PrimaryPart = pivot
	local home = relOf(pivot.CFrame)
	local orbMesh = orb and orb:FindFirstChildOfClass("SpecialMesh")
	if orbMesh then
		if C.ASSETS.OrbMesh.published then orbMesh.MeshId = C.asset("OrbMesh") end
		if C.ASSETS.OrbTexture.published then orbMesh.TextureId = C.asset("OrbTexture") end
		orbMesh.VertexColor = Vector3.new(1.45, 1.35, 1.1)
	end
	local orbBase = orbMesh and orbMesh.Scale or Vector3.one
	local orbLight = pivot:FindFirstChildOfClass("PointLight")   -- свой свет сферы (AltarWarmth) у копии
	if not orbLight then
		orbLight = Instance.new("PointLight"); orbLight.Color = Color3.fromRGB(255, 214, 120); orbLight.Parent = pivot
	end
	orbLight.Enabled = true
	-- светящаяся оболочка, ореол, орбиты, искры (AltarOrbFX)
	local shell, shellMesh
	if orb then
		shell = orb:Clone()
		shell.Name = "LuminousSurface"; shell.Material = Enum.Material.Neon; shell.Color = Color3.fromRGB(255, 224, 45); shell.Transparency = 0.25
		shell.Parent = folder
		shellMesh = shell:FindFirstChildOfClass("SpecialMesh")
		if shellMesh then shellMesh.TextureId = "" end
	end
	local function sprite(name, image, color, size)
		local a = Instance.new("Attachment"); a.Name = name; a.Parent = pivot
		local gui = Instance.new("BillboardGui"); gui.Name = name; gui.Adornee = a; gui.Size = UDim2.fromScale(size, size)
		gui.AlwaysOnTop = false; gui.LightInfluence = 0; gui.MaxDistance = 100; gui.Parent = folder
		local im = Instance.new("ImageLabel"); im.BackgroundTransparency = 1; im.Size = UDim2.fromScale(1, 1)
		im.Image = image; im.ImageColor3 = color; im.Parent = gui
		return { a = a, gui = gui, im = im }
	end
	local glow = sprite("SoftHalo", C.asset("GlowSoft"), Color3.fromRGB(255, 207, 24), 4.1)
	local skin = sprite("SurfaceGlow", C.asset("GlowSoft"), Color3.fromRGB(255, 228, 70), 2.8)
	local tracks = {}
	for band = 1, 3 do
		local nodes, beams = {}, {}
		for j = 0, 48 do
			local at = Instance.new("Attachment"); at.Name = "EnergyPath"; at.Parent = pivot; nodes[j + 1] = at
			if j > 0 then
				local b = Instance.new("Beam"); b.Attachment0 = nodes[j]; b.Attachment1 = at; b.FaceCamera = true
				b.Width0 = 0.018; b.Width1 = 0.018; b.Color = ColorSequence.new(Color3.fromRGB(255, 220, 70)); b.LightEmission = 1
				b.Brightness = 1.3; b.Transparency = NumberSequence.new(0.38); b.Parent = folder; beams[j] = b
			end
		end
		tracks[band] = { nodes = nodes, beams = beams }
	end
	local sprites = {}
	for i = 1, 30 do
		local s = sprite("OrbitSpark_" .. i, C.asset("Spark"), Color3.new(1, 1, 1), i <= 6 and 1.7 or 1.25)
		s.phase = i * 2.39996; s.r = i <= 6 and 1.36 or 1.7 + (i % 4) * 0.13; s.band = (i - 1) % 3 + 1
		table.insert(sprites, s)
	end
	bloomUsers += 1
	if not bloom then
		bloom = Instance.new("BloomEffect"); bloom.Name = "AltarBloom"; bloom.Intensity = 0.45; bloom.Size = 40; bloom.Threshold = 1.2
		bloom.Parent = workspace.CurrentCamera
	end

	-- интерьер
	local ws = Workshop.Build(folder)

	-- работники
	S.workers = {}
	local workerTpl = AssetFind.find(C.WORKER)
	if workerTpl then
		for role = 1, 2 do
			local npc = workerTpl:Clone()
			npc.Name = role == 1 and "AltarMaster" or "AltarAssistant"
			local motors = prepareRig(npc, C.SCALE)
			if motors then
				npc.Parent = folder
				local x = role == 1 and -3.6 or 3.6
				local p = Vector3.new(x, 2.4, 0.7)
				table.insert(S.workers, { npc = npc, role = role, motors = motors, face = makeFace(npc),
					rel = CFrame.lookAt(p, Vector3.new(0, 2.4, 2.55)) })
			end
		end
	end

	-- табличка на алтаре (SurfaceGui на физической табличке, не билборд)
	local plaque = altar:FindFirstChild("RecruitProgressPlaque", true)
	local ui = Instance.new("SurfaceGui")
	ui.Name = "IslandHallPlaque"; ui.Adornee = plaque; ui.Face = Enum.NormalId.Front
	ui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize; ui.CanvasSize = Vector2.new(270, 100)
	ui.LightInfluence = 0; ui.Brightness = 1.3; ui.AlwaysOnTop = false; ui.Active = true; ui.MaxDistance = 65
	ui.ResetOnSpawn = false; ui.Parent = playerGui
	S.ui = ui
	local panel = Instance.new("Frame"); panel.Size = UDim2.fromScale(1, 1); panel.BackgroundTransparency = 0.2; panel.BackgroundColor3 = Color3.fromRGB(33, 27, 25); panel.Parent = ui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 13)
	local stroke = Instance.new("UIStroke"); stroke.Color = GOLD; stroke.Thickness = 2; stroke.Parent = panel
	local label = Instance.new("TextLabel"); label.BackgroundTransparency = 1; label.Size = UDim2.new(1, 0, 0, 27)
	label.TextColor3 = GOLD; label.TextSize = 15; label.Font = Enum.Font.GothamBold; label.Parent = panel
	local track = Instance.new("Frame"); track.Position = UDim2.fromOffset(13, 33); track.Size = UDim2.new(1, -26, 0, 14)
	track.BackgroundColor3 = Color3.fromRGB(67, 53, 32); track.BorderSizePixel = 0; track.Parent = panel
	local bar = Instance.new("Frame"); bar.Size = UDim2.fromScale(0, 1); bar.BackgroundColor3 = GOLD; bar.BorderSizePixel = 0; bar.Parent = track
	local button = Instance.new("TextButton"); button.Size = UDim2.new(1, -20, 0, 30); button.Position = UDim2.fromOffset(10, 56)
	button.BackgroundColor3 = GOLD; button.TextColor3 = Color3.fromRGB(48, 31, 18); button.Font = Enum.Font.GothamBold; button.TextSize = 14; button.Parent = panel
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)
	table.insert(S.conns, button.Activated:Connect(function()
		if hall:GetAttribute("RecruitState") == "Ready" then remote:FireServer("Claim", hall) end
	end))

	-- житель: локальная модель, сцена по расписанию от RevealStartedAt
	S.resident = nil
	local function dropResident()
		if S.resident then S.resident.npc:Destroy(); S.resident = nil end
	end
	local function makeResident(startedAt)
		dropResident()
		local def = D.CATALOG[hall:GetAttribute("RevealDef") or "rose"]
		local tpl = def and D.find(def.model)
		if not (tpl and tpl:IsA("Model")) then return end
		local npc = tpl:Clone()
		npc.Name = "NewResident"
		for _, d in ipairs(npc:GetDescendants()) do
			if d:IsA("BillboardGui") or d:IsA("ProximityPrompt") then d:Destroy() end
		end
		local motors = prepareRig(npc, C.SCALE)
		if not motors then npc:Destroy() return end
		-- скрыт до сборки: запомнить исходную прозрачность
		local orig = {}
		for _, d in ipairs(npc:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then orig[d] = d.Transparency; d.Transparency = 1
			elseif d:IsA("SurfaceGui") then orig[d] = d.Enabled; d.Enabled = false end
		end
		--[[ ⚠️ КОСТЮМ — ОТДЕЛЬНЫЕ ДЕТАЛИ, ПРИВАРЕННЫЕ К ТЕЛУ. У Розы (Rose Couture)
		     сотня деталей одежды и аксессуаров не вложена в руки/ноги, а приварена к
		     ним. Раньше открывались только сами части тела — житель выходил «голым».
		     Каждой детали — хозяин: ближайшая из шести частей R6; открывается с ним. ]]
		local limbs = {}
		for _, n in ipairs(C.PARTS) do
			local l = npc:FindFirstChild(n)
			if l and l:IsA("BasePart") then limbs[n] = l end
		end
		local owner = {}
		for d in pairs(orig) do
			local part = d:IsA("BasePart") and d or d:FindFirstAncestorWhichIsA("BasePart")
			local best, bestD = nil, math.huge
			if part then
				for n, l in pairs(limbs) do
					if part == l or part:IsDescendantOf(l) then best, bestD = n, -1 break end
					local dist = (part.Position - l.Position).Magnitude
					if dist < bestD then best, bestD = n, dist end
				end
			end
			if part and part.Name == "HumanoidRootPart" then best = nil end
			owner[d] = best
		end
		npc.Parent = folder
		S.resident = { npc = npc, motors = motors, orig = orig, owner = owner, startedAt = startedAt, variant = math.clamp(hall:GetAttribute("RevealVariant") or 1, 1, 6),
			stage = 0, solid = 0, fxStage = 0 }
	end
	local function showPart(r, name)
		for d, v in pairs(r.orig) do
			if r.owner[d] == name and d.Parent then
				if d:IsA("SurfaceGui") then d.Enabled = v ~= false else d.Transparency = v end
			end
		end
		-- одежда и лицо — вместе с телом, не раньше
	end

	-- перелёт энергии от сферы к части тела + растущая оболочка (голова — по своему мешу)
	local function assemblePart(r, name)
		local target = r.npc:FindFirstChild(name)
		if not (target and target:IsA("BasePart")) then return end
		local fx = Instance.new("Model"); fx.Name = "EnergyAssembly_" .. name; fx.Parent = folder
		Debris:AddItem(fx, 1.3)
		local knots = {}
		for i = 1, 18 do
			local p = Instance.new("Part"); p.Name = "Energy"; p.Shape = Enum.PartType.Ball; p.Size = Vector3.one * 0.13
			p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false
			p.Material = Enum.Material.Neon; p.Color = Color3.fromRGB(255, 223, 66)
			p.Position = pivot.Position   -- сразу у сферы: иначе первый кадр в (0,0,0) мира
			p.Parent = fx
			local a = Instance.new("Attachment", p); local b = Instance.new("Attachment", p); a.Position = Vector3.new(0, 0.07, 0); b.Position = -a.Position
			local trail = Instance.new("Trail"); trail.Attachment0 = a; trail.Attachment1 = b; trail.Lifetime = 0.16
			trail.Color = ColorSequence.new(p.Color); trail.LightEmission = 1; trail.FaceCamera = true
			trail.Transparency = NumberSequence.new(0, 1)
			--[[ ⚠️ ХВОСТ ВКЛЮЧАЕМ ПОСЛЕ ПЕРВОЙ ПОСТАНОВКИ. Иначе он рисует перелёт шарика
			     из точки создания — через всю карту тянулся длинный жёлтый луч. ]]
			trail.Enabled = false
			trail.Parent = p
			knots[i] = p
		end
		local isHead = name == "Head"
		local forming = isHead and target:Clone() or Instance.new("Part")
		for _, child in ipairs(forming:GetChildren()) do
			if not child:IsA("DataModelMesh") then child:Destroy() end
		end
		local headMesh = forming:FindFirstChildOfClass("SpecialMesh")
		local headMeshScale = headMesh and headMesh.Scale
		if headMesh then headMesh.TextureId = "" end
		if forming:IsA("MeshPart") then pcall(function() forming.TextureID = "" end) end
		forming.Name = "FormingLimb"; forming.Anchored = true; forming.CastShadow = false
		forming.CanCollide = false; forming.CanTouch = false; forming.CanQuery = false; forming.Material = Enum.Material.Neon
		forming.Color = Color3.fromRGB(255, 224, 76); forming.Transparency = 1; forming.Parent = fx
		local elapsed, conn = 0, nil
		conn = RunService.RenderStepped:Connect(function(dt)
			elapsed += dt
			if not target.Parent or elapsed > 0.82 or not fx.Parent then conn:Disconnect(); fx:Destroy(); return end
			local start = pivot.Position
			local finish = target.Position
			for i, p in ipairs(knots) do
				local u = math.clamp((elapsed - (i - 1) * 0.008) / 0.42, 0, 1)
				local mid = (start + finish) * 0.5 + Vector3.new(0, 1.4, 0)
				local center = (1 - u) ^ 2 * start + 2 * (1 - u) * u * mid + u * u * finish
				local a = u * math.pi * 5 + i * 2.4
				local radius = math.sin(u * math.pi) * 0.24
				p.Position = center + Vector3.new(math.cos(a) * radius, math.sin(a) * radius, 0)
				p.Transparency = u >= 1 and 1 or 0
				local tr = p:FindFirstChildOfClass("Trail")
				if tr and not tr.Enabled then tr:Clear(); tr.Enabled = true end
			end
			local growth = math.clamp((elapsed - 0.36) / 0.29, 0, 1)
			local baseAlpha = isHead and 0.38 or 0.12
			forming.Transparency = growth > 0 and (elapsed > 0.65 and baseAlpha + (1 - baseAlpha) * math.clamp((elapsed - 0.65) / 0.17, 0, 1) or baseAlpha) or 1
			forming.Size = Vector3.new(target.Size.X, target.Size.Y * math.max(0.01, growth), target.Size.Z) * (isHead and 1 or 1.025)
			if headMesh and headMesh.MeshType == Enum.MeshType.FileMesh then
				headMesh.Scale = headMeshScale * Vector3.new(1, math.max(0.01, growth), 1)
			end
			forming.CFrame = target.CFrame * CFrame.new(0, -target.Size.Y * (1 - growth) * 0.5, 0)
		end)
	end

	S.chargeSound = nil
	local clock, orbitClock, visualScale, lift, pulse, discharge = 0, 0, 0.2, 0, 0, 0
	local stateBefore = ""
	local revealSeen = nil

	table.insert(S.conns, RunService.RenderStepped:Connect(function(dt)
		if not (hall.Parent and origin.Parent) then return end
		dt = math.min(dt, 0.1)
		local o = origin.CFrame
		local t = now()
		local state = hall:GetAttribute("RecruitState") or "Charging"
		local level = math.clamp(tonumber(hall:GetAttribute("Level")) or 0, 0, 3)
		local p = tonumber(hall:GetAttribute("RecruitProgress")) or 0
		if state == "Charging" then
			p = math.clamp((t - (hall:GetAttribute("RecruitStartedAt") or t)) / (hall:GetAttribute("RecruitCycleDuration") or 1000), 0, 1)
		elseif state == "Ready" then p = 1 end

		-- табличка
		bar.Size = UDim2.fromScale(p, 1)
		local left = math.max(0, (hall:GetAttribute("RecruitCycleDuration") or 0) * (1 - p))
		local mins = math.floor(left / 60)
		label.Text = state == "Ready" and "НОВЫЙ ЖИТЕЛЬ ГОТОВ!" or state == "Revealing" and "ВСТРЕЧАЕМ ЖИТЕЛЯ"
			or ("ПОДГОТОВКА ЖИТЕЛЯ  %d%%"):format(math.floor(p * 100))
		button.Text = state == "Ready" and "ПОЛУЧИТЬ ЖИТЕЛЯ" or state == "Revealing" and "ВЫХОДИТ…"
			or state == "Cooldown" and "…" or ("ОСТАЛОСЬ %d:%02d"):format(mins, math.floor(left % 60))
		local canClaim = state == "Ready" and not hall:GetAttribute("Building")
		button.Active = canClaim
		button.AutoButtonColor = canClaim
		button.BackgroundTransparency = canClaim and (0.08 + 0.06 * math.sin(t * 4)) or 0.6

		-- сцена появления: по расписанию от RevealStartedAt
		local revealAt = hall:GetAttribute("RevealStartedAt")
		local rt = (state == "Revealing" and type(revealAt) == "number") and (t - revealAt) or nil
		if rt and revealSeen ~= revealAt then
			revealSeen = revealAt
			if rt < 1.5 then
				if S.chargeSound then S.chargeSound:Destroy() end
				S.chargeSound = playCue("Charge", pivot)
				burst(pivot)
			end
		end
		if rt and rt >= C.OPEN and not S.resident then makeResident(revealAt) end
		if S.resident and (not rt or S.resident.startedAt ~= revealAt) then
			-- житель вышел и порадовался — исчезает; дальше попап «Новый персонаж!» (сервер)
			dropResident()
		end
		local spent, assembling = 0, false
		local r = S.resident
		if r and rt then
			for i, name in ipairs(C.PARTS) do
				local st = C.partStart(i)
				if rt >= st then
					spent = i
					if r.fxStage < i then
						r.fxStage = i
						if rt - st < 0.4 then   -- опоздавший клиент не гоняет старые перелёты
							discharge = 1
							playCue("Transfer" .. rng:NextInteger(1, 3), pivot, rng:NextNumber(0.94, 1.04))
							assemblePart(r, name)
						end
					end
				end
				if rt >= st + C.PART and r.solid < i then
					r.solid = i
					showPart(r, name)
					local body = r.npc:FindFirstChild(name)
					if rt - st - C.PART < 0.4 and body then
						burst(body)
						if name == "Head" then
							if S.chargeSound and S.chargeSound.Parent then
								TweenService:Create(S.chargeSound, TweenInfo.new(0.3), { Volume = 0 }):Play()
								Debris:AddItem(S.chargeSound, 0.4)
							end
							playCue("Complete", body)
						else
							playCue("Solid" .. rng:NextInteger(1, 3), body, rng:NextNumber(0.94, 1.06))
						end
					end
				end
			end
			assembling = rt < C.assembledAt()
			-- поза и место: сборка у алтаря → выход одной из шести походок → радость
			local v = r.variant
			local walkAt = C.walkStart()
			local dur = Anim.Duration[v] or 3
			local mode, elapsed, rel
			local from = CFrame.new(C.EXIT_FROM)
			local to = CFrame.new(C.EXIT_TO)
			if rt < walkAt then
				mode, elapsed, rel = "Appear", rt - C.OPEN, from
			elseif rt < walkAt + dur then
				local u = math.clamp((rt - walkAt) / dur, 0, 1)
				local e, side, hop, yaw = Anim.Travel(v, u)
				mode, elapsed = "Walk", rt - walkAt
				rel = from:Lerp(to, e) * CFrame.new(side, hop, 0) * CFrame.Angles(0, yaw, 0)
			else
				mode, elapsed, rel = "Celebrate", rt - walkAt - dur, to
			end
			-- лицом к выходу (фасад здания смотрит в −Z)
			r.npc:PivotTo(o * rel)
			applyPose(r.motors, Anim.Pose(0, v, mode, elapsed, false), dt)
		end

		-- двери: пружина по углу (разгон, перелёт, успокоение)
		local target = math.rad(state == "Revealing" and 103 or (state == "Charging" or state == "Ready") and 80 or 0)
		local doorParts, doorCF = {}, {}
		for _, h in ipairs(S.hinges) do
			local remaining = dt
			while remaining > 0 do
				local step = math.min(remaining, 1 / 120); remaining -= step
				local acc = (target - h.angle) * 105 - h.velocity * 15
				h.velocity += acc * step; h.angle += h.velocity * step
			end
			local hingeCF = o * h.hingeRel * CFrame.Angles(0, h.angle * h.sign, 0)
			for part, rel in pairs(h.parts) do
				table.insert(doorParts, part); table.insert(doorCF, hingeCF * rel)
			end
		end
		if #doorParts > 0 then workspace:BulkMoveTo(doorParts, doorCF, Enum.BulkMoveMode.FireCFrameChanged) end

		-- сфера: заряд 0.2…1, на сборке теряет по доле на каждую часть, поднимается
		clock += dt
		local targetScale = 0.2 + 0.8 * p
		if state == "Revealing" then targetScale = 1 - 0.8 * spent / 6
		elseif state == "Cooldown" then targetScale = 0.2 end
		if state == "Charging" or state == "Ready" then visualScale = targetScale
		else visualScale += (targetScale - visualScale) * (1 - math.exp(-24 * dt)) end
		lift += ((assembling and 0.65 or 0) - lift) * (1 - math.exp(-6 * dt))
		if state ~= stateBefore and state == "Revealing" then pulse = 1 end
		stateBefore = state
		pulse = math.max(0, pulse - dt * 1.25)
		discharge = math.max(0, discharge - dt * 2.2)
		local strength = 0.35 + 0.65 * p
		if state == "Revealing" then strength = 0.2 + 0.6 * (1 - spent / 6) end
		if state == "Cooldown" then strength = 0.12 end
		orbitClock += dt * (state == "Revealing" and 3.8 or 0.65 + p * 0.8)
		local beat = 0.5 + 0.5 * math.sin(clock * 2.8)
		crystal:PivotTo(o * home * CFrame.new(0, lift + math.sin(clock * 2.8) * 0.10 * visualScale, 0)
			* CFrame.Angles(0.32 + math.sin(clock * 0.65) * 0.16, clock * 1.25, 0.22))
		if orbMesh then orbMesh.Scale = orbBase * visualScale end
		if shell and orb then
			shell.CFrame = orb.CFrame
			if shellMesh then shellMesh.Scale = orbBase * visualScale * 1.006 end
			shell.Transparency = 0.8 - strength * 0.58 - 0.04 * beat - 0.12 * discharge
		end
		local cam = workspace.CurrentCamera
		local toCamera = (cam.CFrame.Position - pivot.Position).Unit
		glow.a.WorldPosition = pivot.Position + toCamera * (1.34 * visualScale)
		skin.a.WorldPosition = pivot.Position + toCamera * (1.35 * visualScale)
		skin.gui.Size = UDim2.fromScale(2.8 * visualScale, 2.8 * visualScale)
		glow.im.ImageTransparency = 0.86 - strength * 0.62 - 0.06 * beat - 0.15 * discharge
		local halo = (3.5 + strength * 2 + beat * 0.35 + pulse + discharge * 0.6) * visualScale
		glow.gui.Size = UDim2.fromScale(halo, halo)
		skin.im.ImageTransparency = 0.8 - strength * 0.42 - 0.06 * beat
		orbLight.Brightness = 0.25 + strength * 1.15 + discharge * 0.45
		orbLight.Range = 6 + strength * 3
		for band, tr in ipairs(tracks) do
			local rot = CFrame.Angles(0.45 + band * 0.55 + math.sin(orbitClock * 0.45 + band) * 0.3, band * 1.02 + orbitClock * (band % 2 == 0 and -0.8 or 0.65), 0.35 + orbitClock * 0.22)
			for j, node in ipairs(tr.nodes) do
				local a = (j - 1) / 48 * math.pi * 2
				local rr = (1.34 + discharge * 0.12) * visualScale
				node.Position = rot:VectorToWorldSpace(Vector3.new(math.cos(a) * rr, math.sin(a) * rr, 0))
			end
			for j, b in ipairs(tr.beams) do
				local wave = 0.5 + 0.5 * math.sin(j / 48 * math.pi * 2 - clock * 3 + band * 2)
				b.Width0 = (0.015 + wave * 0.012) * visualScale; b.Width1 = b.Width0
				b.Brightness = (0.5 + strength * 1.5) + wave * 0.8 + discharge
			end
		end
		for i, s in ipairs(sprites) do
			s.gui.Enabled = i <= math.floor(3 + 27 * p) or state == "Revealing"
			local a = clock * 0.65 + s.phase
			local radius = s.r * visualScale
			local sz = (i <= 6 and 1.7 or 1.25) * math.max(0.4, visualScale)
			s.gui.Size = UDim2.fromScale(sz, sz)
			s.a.Position = CFrame.Angles(0.45 + s.band * 0.55, s.band * 1.02, 0.35):VectorToWorldSpace(Vector3.new(math.cos(a) * radius, math.sin(a) * radius, 0))
			s.im.Rotation = t * (i % 2 == 0 and 35 or -40) + i * 27
			local facing = pivot.CFrame:VectorToWorldSpace(s.a.Position.Unit):Dot(toCamera)
			local fade = math.clamp((0.22 - facing) / 0.32, 0, 1)
			s.im.ImageTransparency = math.max(fade, 0.08 + (0.5 + 0.5 * math.sin(t * 2 + i)) * 0.23)
		end

		-- работники: цикл ~40 с; на появлении жителя расступаются
		local cycleT = t % 40
		local offsets = {}
		for _, w in ipairs(S.workers) do
			local _, action, phase = Anim.WorkerFrame(w.role, cycleT)
			local yielding = state == "Revealing" or state == "Cooldown"
			local goal
			if yielding then
				local side = w.role == 1 and -1 or 1
				goal = CFrame.lookAt(Vector3.new(side * 3.6, 2.4, 1.3), Vector3.new(0, 2.4, -4))
				action = "Yield"
			else
				goal = (Anim.WorkerFrame(w.role, cycleT))
			end
			w.rel = w.rel:Lerp(goal, 1 - math.exp(-(yielding and 5 or 12) * dt))
			w.npc:PivotTo(o * w.rel)
			applyPose(w.motors, Anim.Pose(w.role, 1, yielding and "Yield" or nil, cycleT, state == "Charging"), dt)
			-- руки к инструментам: ступка (мастер) и кристалл (помощник)
			if not yielding and (action == "Prepare" or action == "Study") then
				local strengthW = math.clamp(phase / 0.65, 0, 1)
				local side = w.role == 1 and -1 or 1
				local toolOffset = Vector3.zero
				if action == "Prepare" then
					toolOffset = w.role == 1 and Vector3.new(math.cos(phase * 5) * 0.1, math.sin(phase * 5) * 0.065, math.sin(phase * 5) * 0.1)
						or Vector3.new(0, math.sin(phase * 3) * 0.1, 0)
					offsets[w.role == 1 and "Pestle" or "FocusCrystal"] = toolOffset
				end
				local right = Vector3.new(side * 5.65, 3.53, 2.7) + toolOffset
				local leftH = Vector3.new(side * 5.4, 3.08, 3.1)
				if action == "Study" then right = Vector3.new(side * 5.8, 3.05, 3.5 + math.sin(phase * 2) * 0.13); leftH = Vector3.new(side * 5.5, 3.02, 3.8) end
				for _, entry in ipairs({ { "Right Shoulder", right }, { "Left Shoulder", leftH } }) do
					local d = w.motors[entry[1]]
					if d and d.joint.Part0 and d.joint.Part1 then
						local joint = d.joint
						local shoulder = (joint.Part0.CFrame * CFrame.new(d.base.Position)).Position
						local tgt = o:PointToWorldSpace(entry[2])
						local up = (shoulder - tgt).Unit
						local axis = joint.Part0.CFrame.LookVector:Cross(up).Unit
						local back = axis:Cross(up).Unit
						local center = shoulder - up * (joint.Part1.Size.Y / 2)
						local cf = CFrame.fromMatrix(center, axis, up, back)
						joint.C0 = joint.C0:Lerp(joint.Part0.CFrame:ToObjectSpace(cf) * joint.C1, strengthW)
					end
				end
			end
			if w.face then w.face(action) end
		end

		-- интерьер: все детали одним BulkMoveTo от текущего origin
		Workshop.Update(ws, o, level, t, offsets)
	end))

	-- уборка: здание снесли / выгрузилось
	table.insert(S.conns, hall.AncestryChanged:Connect(function(_, parent)
		if not parent then
			for _, c in ipairs(S.conns) do c:Disconnect() end
			if S.chargeSound then S.chargeSound:Destroy() end
			folder:Destroy()
			ui:Destroy()
			scenes[hall] = nil
			bloomUsers -= 1
			if bloomUsers <= 0 and bloom then bloom:Destroy(); bloom = nil end
		end
	end))
end

for _, h in ipairs(CollectionService:GetTagged(C.TAG)) do task.spawn(setup, h) end
CollectionService:GetInstanceAddedSignal(C.TAG):Connect(function(h) task.spawn(setup, h) end)

print("[Таверна/клиент] сцена готова: интерьер, работники, двери, сфера, сборка жителя")
