-- ScarecrowSway: движения пугала Raft_scarecrow кодом. LocalScript, StarterPlayerScripts.
--
-- Ничего загружать не нужно, клипов нет: это пружина. Тело качается на шесте в
-- точке, где его держат подкосы, голова с шляпой кивает на шее с запаздыванием.
--   * удар      — пугало отшатывается от бьющего, болтается и затихает, летит солома;
--   * птица села — наклоняется под её весом в сторону той руки и слегка проседает,
--                  пока птица сидит — так и стоит; улетела — выпрямляется с отмашкой;
--   * простой   — едва заметно ходит на ветру.
--
-- Скрипт сам находит любой MeshPart "raft_scarecrow_base"; рядом (в той же модели)
-- должны лежать "raft_scarecrow_body" и "raft_scarecrow_head". Имена не менять.
-- Настоящие тело и голова не трогаются (остаются для коллизии, лучей и сервера):
-- скрипт прячет их у клиента и качает свои копии. Поэтому пугало может быть
-- заякорено, приварено к плоту, ехать вместе с ним — всё равно.
--
-- КАК ДЁРГАТЬ (атрибуты на модели пугала — родителе мешей; ставит сервер):
--   Hit        любое изменение значения = удар (удобно: Hit = os.clock() или счётчик)
--   HitFrom    Vector3, откуда били (мировая точка). Нет — от ближайшего игрока.
--   Health     число: уменьшилось — тоже удар (если у вас так ведётся прочность)
--   BirdsLeft / BirdsRight / BirdsHead   сколько птиц сидит на руке/руке/шляпе
--   SwayEnabled  false — стоит как вкопанное
--   SwayDistance дальше этого от камеры не анимируется (по умолчанию 150)
-- Humanoid внутри модели тоже слушается: упало Health — удар.
-- С клиента (мгновенный отклик на свой клик): _G.ScarecrowHit(model, fromPosition)
--
-- ПТИЦЫ МОДЕЛЬЮ: положите птицу (Model или BasePart, заякоренную, без коллизии) в
-- папку "Perched" внутри модели пугала и дайте ей атрибут Perch = "Left" | "Right" |
-- "Head". Скрипт сам посадит её на руку/шляпу, будет возить вместе с наклоном и
-- посчитает её вес. Убрали из папки — улетела.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- размеры модели в её единицах (1.0 = плитка пола), от подошвы
local BASE_W = 0.32 -- крестовина 0.32 x 0.32: по ней считается масштаб
local PIVOT_H = 0.19 -- тут подкосы держат шест: ось качания тела
local NECK_H = 0.55 -- шея: ось кивка головы
-- насесты: x вдоль рук (+x — та рука, что ниже), y назад, z вверх
local PERCH = {
	Left = { part = "body", p = Vector3.new(-0.24, 0.02, 0.560) },
	Right = { part = "body", p = Vector3.new(0.24, 0.02, 0.530) },
	Head = { part = "head", p = Vector3.new(0.01, 0.02, 0.772) },
}

local K_BODY, C_BODY = 60, 2.4 -- жёсткость и затухание тела: ~1.2 Гц, 5-6 качаний
local K_HEAD, C_HEAD = 120, 5.0
local HEAD_LAG = 0.55 -- насколько голова отстаёт от рывков тела
local HIT_KICK = 1.15 -- рад/с
local MAX_TILT = 0.20
local BIRD_LEAN, BIRD_NOD = 0.055, 0.035 -- рад на птицу
local STRAW = Color3.fromRGB(226, 190, 96)

local active = {}

local function horizontal(v, up)
	local h = v - up * v:Dot(up)
	return if h.Magnitude > 1e-4 then h.Unit else nil
end

-- Вертикаль основания — ось, чей размер не равен двум другим (0.195 против 0.32 x 0.32)
local function frameOf(base, body, head)
	local s, cf = base.Size, base.CFrame
	local axes = { { cf.RightVector, s.X }, { cf.UpVector, s.Y }, { -cf.LookVector, s.Z } }
	local dXY, dXZ, dYZ = math.abs(s.X - s.Y), math.abs(s.X - s.Z), math.abs(s.Y - s.Z)
	local odd = 2 -- X и Z равны: высота в Y (обычный импорт)
	if dXY < dXZ and dXY <= dYZ then
		odd = 3
	elseif dYZ < dXZ and dYZ < dXY then
		odd = 1
	end
	local up, height = axes[odd][1], axes[odd][2]
	if up.Y < 0 then
		up = -up
	end
	local width = axes[odd % 3 + 1][2]
	-- руки — самая длинная ось тела; при обычном импорте это локальная X меша = +x модели
	local bs, bcf = body.Size, body.CFrame
	local right = bcf.RightVector
	if bs.Y > bs.X and bs.Y > bs.Z then
		right = bcf.UpVector
	elseif bs.Z > bs.X and bs.Z > bs.Y then
		right = -bcf.LookVector
	end
	right = horizontal(right, up) or horizontal(Vector3.xAxis, up) or Vector3.zAxis
	-- знак оси рук импорт может перевернуть (у чайки так и вышло). Меряем: шляпа сдвинута набок,
	-- поэтому центр головы смещён от шеста в сторону +x модели — туда и должен смотреть right.
	if head and (head.Position - base.Position):Dot(right) < 0 then
		right = -right
	end
	local face = right:Cross(up) -- куда смотрит лицо (−y модели)
	local scale = width / BASE_W
	local origin = base.Position - up * (height / 2)
	return origin, up, right, face, scale
end

local function tiltCF(pivot, up, right, face, tr, tf)
	local d = right * tr + face * tf
	local a = d.Magnitude
	if a < 1e-5 then
		return CFrame.identity
	end
	local axis = up:Cross(d / a)
	return CFrame.new(pivot) * CFrame.fromAxisAngle(axis, a) * CFrame.new(-pivot)
end

local function ghost(part, folder)
	local c = part:Clone()
	for _, d in c:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("LuaSourceContainer") or d:IsA("Attachment") then
			d:Destroy()
		end
	end
	c.Name = part.Name .. "_sway"
	c.Anchored = true
	c.CanCollide = false
	c.CanTouch = false
	c.CanQuery = false
	c.Parent = folder
	return c
end

local function start(base)
	if active[base] then
		return
	end
	local root = base.Parent
	if not root then
		return
	end
	local body = root:FindFirstChild("raft_scarecrow_body", true)
	local head = root:FindFirstChild("raft_scarecrow_head", true)
	if not (body and head and body:IsA("BasePart") and head:IsA("BasePart")) then
		return
	end
	active[base] = true

	local folder = Instance.new("Folder")
	folder.Name = "ScarecrowSway_Client"
	folder.Parent = root
	local gBody, gHead = ghost(body, folder), ghost(head, folder)

	-- состояние пружин: наклон вправо (r) и вперёд (f), скорости; у головы — относительно тела
	local tr, tf, vr, vf = 0, 0, 0, 0
	local hr, hf, hvr, hvf = 0, 0, 0, 0
	local shake = 0 -- мелкая дрожь сразу после удара
	local birds = { Left = 0, Right = 0, Head = 0 }
	local bits = {}
	local lastHealth = root:GetAttribute("Health")
	local pendingHits = {}
	local awake = true

	local function nearestPlayerPos(origin)
		local best, bestD
		for _, plr in Players:GetPlayers() do
			local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local d = (hrp.Position - origin).Magnitude
				if d < 30 and (not bestD or d < bestD) then
					best, bestD = hrp.Position, d
				end
			end
		end
		return best
	end

	local lastHitAt = 0
	local function queueHit(from)
		if os.clock() - lastHitAt < 0.12 then
			return -- Hit и Health обычно меняются разом: это один удар, не два
		end
		lastHitAt = os.clock()
		table.insert(pendingHits, from or root:GetAttribute("HitFrom") or false)
	end

	local conns = {}
	table.insert(conns, root:GetAttributeChangedSignal("Hit"):Connect(function()
		queueHit(nil)
	end))
	table.insert(conns, root:GetAttributeChangedSignal("Health"):Connect(function()
		local h = root:GetAttribute("Health")
		if type(h) == "number" and type(lastHealth) == "number" and h < lastHealth then
			queueHit(nil)
		end
		lastHealth = h
	end))
	local humanoid = root:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		local hp = humanoid.Health
		table.insert(conns, humanoid.HealthChanged:Connect(function(new)
			if new < hp then
				queueHit(nil)
			end
			hp = new
		end))
	end
	active[base] = { hit = queueHit, root = root }

	local function strawBurst(at, dir, up, scale)
		for i = 1, 7 do
			local p = Instance.new("Part")
			p.Size = Vector3.new(0.006, 0.006, 0.06 + 0.04 * math.random()) * scale
			p.Color = STRAW
			p.Material = Enum.Material.SmoothPlastic
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.CastShadow = false
			p.Parent = folder
			local spread = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
			table.insert(bits, {
				part = p,
				pos = at + spread * 0.12 * scale,
				vel = (dir * (0.5 + math.random()) + up * (0.9 + math.random()) + spread * 1.2) * 0.9 * scale,
				spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
				rate = (math.random() - 0.5) * 14,
				age = 0,
				life = 0.55 + 0.35 * math.random(),
				scale = scale,
			})
		end
	end

	local connection
	connection = RunService.PreRender:Connect(function(dt)
		if not (base:IsDescendantOf(workspace) and body:IsDescendantOf(root) and head:IsDescendantOf(root)) then
			connection:Disconnect()
			for _, c in conns do
				c:Disconnect()
			end
			folder:Destroy()
			active[base] = nil
			return
		end
		local origin, up, right, face, scale = frameOf(base, body, head)
		local camera = workspace.CurrentCamera
		local far = camera and (camera.CFrame.Position - origin).Magnitude > (root:GetAttribute("SwayDistance") or 150)
		local on = root:GetAttribute("SwayEnabled") ~= false and not far
		if on ~= awake then
			awake = on
			gBody.LocalTransparencyModifier = on and 0 or 1
			gHead.LocalTransparencyModifier = on and 0 or 1
		end
		body.LocalTransparencyModifier = on and 1 or 0
		head.LocalTransparencyModifier = on and 1 or 0
		if not on then
			table.clear(pendingHits)
			return
		end

		-- удары: толчок ОТ бьющего + дрожь + солома
		for _, from in pendingHits do
			local src = if typeof(from) == "Vector3" then from else nearestPlayerPos(origin)
			local dir = src and horizontal(origin - src, up)
			if not dir then
				local a = math.random() * 2 * math.pi
				dir = right * math.cos(a) + face * math.sin(a)
			end
			vr += dir:Dot(right) * HIT_KICK
			vf += dir:Dot(face) * HIT_KICK
			shake = 1
			strawBurst(origin + up * (0.42 * scale), dir, up, scale)
		end
		table.clear(pendingHits)

		-- птицы: атрибуты + модели в папке Perched
		local perched = root:FindFirstChild("Perched")
		local seated = { Left = {}, Right = {}, Head = {} }
		if perched then
			for _, b in perched:GetChildren() do
				local where = b:GetAttribute("Perch")
				if seated[where] and (b:IsA("Model") or b:IsA("BasePart")) then
					table.insert(seated[where], b)
				end
			end
		end
		for name, list in seated do
			local n = #list + (root:GetAttribute("Birds" .. name) or 0)
			local delta = n - birds[name]
			if delta ~= 0 then
				-- села — толчок вниз-в сторону, улетела — отмашка обратно
				local kick = 0.45 * delta
				if name == "Left" then
					vr -= kick
				elseif name == "Right" then
					vr += kick
				else
					vf += kick * 0.7
				end
				birds[name] = n
			end
		end
		local now = workspace:GetServerTimeNow()
		local breeze = 0.006 * math.sin(now * 0.9) + 0.003 * math.sin(now * 2.3 + 1)
		local goalR = math.clamp((birds.Right - birds.Left) * BIRD_LEAN, -0.13, 0.13) + breeze
		local goalF = math.clamp(birds.Head * BIRD_NOD + (birds.Left + birds.Right) * 0.012, 0, 0.09) + breeze * 0.6

		-- пружины мелкими шагами: длинный кадр не должен их взорвать
		local left = math.min(dt, 0.1)
		while left > 1e-5 do
			local h = math.min(left, 1 / 120)
			left -= h
			local ar = -K_BODY * (tr - goalR) - C_BODY * vr
			local af = -K_BODY * (tf - goalF) - C_BODY * vf
			vr += ar * h
			vf += af * h
			tr = math.clamp(tr + vr * h, -MAX_TILT, MAX_TILT)
			tf = math.clamp(tf + vf * h, -MAX_TILT, MAX_TILT)
			hvr += (-K_HEAD * hr - C_HEAD * hvr - HEAD_LAG * ar) * h
			hvf += (-K_HEAD * hf - C_HEAD * hvf - HEAD_LAG * af) * h
			hr = math.clamp(hr + hvr * h, -0.25, 0.25)
			hf = math.clamp(hf + hvf * h, -0.25, 0.25)
		end
		shake = math.max(0, shake - dt * 3.5)
		local jit = shake * shake * 0.03 * math.sin(now * 55)

		local bodyT = tiltCF(origin + up * (PIVOT_H * scale), up, right, face, tr + jit, tf)
		local headT = bodyT * tiltCF(origin + up * (NECK_H * scale), up, right, face, hr - jit * 1.5, hf)
		gBody.CFrame = bodyT * body.CFrame
		gHead.CFrame = headT * head.CFrame

		-- сидящие птицы едут вместе с рукой/шляпой
		for name, list in seated do
			local spec = PERCH[name]
			local T = if spec.part == "head" then headT else bodyT
			for i, b in list do
				local p = spec.p
				local along = (i - 1) * 0.06 * (if name == "Left" then 1 elseif name == "Right" then -1 else 0)
				local world = origin + (right * (p.X + along) + up * p.Z - face * p.Y) * scale
				local yaw = b:GetAttribute("PerchYaw") or 0
				local cf = T * CFrame.fromMatrix(world, -right, up) * CFrame.Angles(0, math.rad(yaw), 0)
				if b:IsA("Model") then
					b:PivotTo(cf)
				else
					b.CFrame = cf
				end
			end
		end

		-- солома
		for i = #bits, 1, -1 do
			local s = bits[i]
			s.age += dt
			if s.age >= s.life then
				s.part:Destroy()
				table.remove(bits, i)
			else
				s.vel -= up * (3.2 * s.scale * dt)
				s.pos += s.vel * dt
				s.part.CFrame = CFrame.new(s.pos) * s.spin * CFrame.Angles(s.rate * s.age, 0, s.rate * 0.7 * s.age)
				s.part.Transparency = math.clamp((s.age / s.life - 0.6) / 0.4, 0, 1)
			end
		end
	end)
end

-- мгновенный отклик с клиента (например из обработчика своего клика)
_G.ScarecrowHit = function(model, fromPosition)
	for _, entry in active do
		if type(entry) == "table" and (entry.root == model or (model and model:IsDescendantOf(entry.root))) then
			entry.hit(fromPosition)
		end
	end
end

local function discover(instance)
	if instance:IsA("MeshPart") and instance.Name == "raft_scarecrow_base" then
		task.defer(start, instance)
	end
end

for _, instance in workspace:GetDescendants() do
	discover(instance)
end
workspace.DescendantAdded:Connect(discover)
