--[[
	ЛИЦО РЫБАКА (клиент). Один обработчик на все модели в мире с папкой
	FaceTextures (выживший-рыбак на станции, на ферме, в превью «Команды»).
	Эмоцию задаёт сервер атрибутами FaceEmotion / FaceEmotionStartedAt
	(FishermanFace.Set), фазу перехода и моргание считаем здесь. Текстуру
	Head.face меняем только при смене кадра.

	⚠️ Больше НИКТО не пишет Head.face.Texture у этих моделей — иначе мигание.
]]

local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Face = require(ReplicatedStorage:WaitForChild("CharacterFace"))   -- общая мимика жителей R6

local rigs = {}        -- [model] = { face, textures, nextBlink, blinkStart }
local preloaded = {}   -- [url] = true
local rng = Random.new()

local function preload(textures)
	local urls = {}
	for _, v in ipairs(textures:GetChildren()) do
		if v:IsA("StringValue") and not preloaded[v.Value] then
			preloaded[v.Value] = true
			table.insert(urls, v.Value)
		end
	end
	if #urls > 0 then
		task.spawn(function() pcall(function() ContentProvider:PreloadAsync(urls) end) end)
	end
end

--[[ ═══ HD-ЛИЦО COLD CAP (HDFaceCarrier) ═══
     Рисует лицо его же HDFaceSync по атрибуту FaceSpriteKey («Idle_0», «Sad_2»…).
     В демо-плейсе этот ключ считал CorsairAnimator, но на плоту он выключен (он
     держит корень на якоре и тянет героя к точке старта). Поэтому ключ считаем
     здесь — той же шкалой Face.Evaluate и тем же морганием, что у рыбака.
     Модель с ВКЛЮЧЁННЫМ демо-аниматором (витрина) не трогаем: он считает сам. ]]
-- атлас эмоций и новое лицо Cold Cap качаем сразу: атлас огромный, а без него
-- сон/грусть/удивление нечем показать
task.spawn(function()
	local a = Instance.new("ImageLabel"); a.Image = "rbxassetid://103054870643875"
	local b = Instance.new("ImageLabel"); b.Image = "rbxassetid://79705652476370"
	pcall(function() ContentProvider:PreloadAsync({ a, b, "rbxassetid://129069088437323", "rbxassetid://84963886485704", "rbxassetid://105117069614865" }) end)
end)

local function trackHD(carrier)
	if carrier.Name ~= "HDFaceCarrier" or not carrier:IsA("BasePart") then return end
	local rig = carrier.Parent
	if not (rig and rig:IsA("Model")) then return end
	local demo = rig:FindFirstChild("CorsairAnimator")
	if demo and demo:IsA("BaseScript") and demo.Enabled then return end
	-- превью «Команды» едет за камерой: следов там быть не должно
	local inPreview = rig.Parent ~= nil and rig.Parent.Name == "SurvivorPreviewScene"
	if rigs[rig] and rigs[rig].hd then return end
	rigs[rig] = { hd = true, noTrail = inPreview, nextBlink = workspace:GetServerTimeNow() + rng:NextNumber(2.8, 5) }
	print(("[Cold Cap/клиент] HD-лицо и морозные следы: %s"):format(rig:GetFullName()))
end

local function track(folder)
	if folder.Name == "HDFaceCarrier" then trackHD(folder) return end
	if folder.Name ~= "FaceTextures" or not folder:IsA("Folder") then return end
	local rig = folder.Parent
	if not (rig and rig:IsA("Model")) or rigs[rig] ~= nil then return end
	if rig:FindFirstChild("HDFaceCarrier") then return end   -- HD-лицо ведёт trackHD
	--[[ ⚠️ ГОЛОВУ ЖДЁМ, А НЕ ПРОВЕРЯЕМ ОДИН РАЗ. В плейсе StreamingEnabled: модель
	     приезжает по частям, и папка FaceTextures бывала раньше головы — рыбак так
	     и оставался с одним лицом, сон не закрывал глаза. ]]
	rigs[rig] = false   -- «ждём», чтобы не запускать второй раз
	task.spawn(function()
		local head = rig:WaitForChild("Head", 30)
		local face = head and head:WaitForChild("face", 30)
		if not (face and face:IsA("Decal") and rig.Parent) then rigs[rig] = nil return end
		--[[ ⚠️ У МОДЕЛИ С HD-ЛИЦОМ ЭТА ВЕТКА НЕ НУЖНА. Если папка FaceTextures (старая
		     модель Cold Cap FaceV7) приехала раньше HDFaceCarrier, эта ветка после
		     ожидания головы ПЕРЕЗАПИСЫВАЛА запись HD-лица — и у работника не
		     считались ни кадр лица (сон, моргание), ни морозные следы. ]]
		local carrier = rig:FindFirstChild("HDFaceCarrier")
		if carrier then trackHD(carrier) return end
		if rigs[rig] and rigs[rig].hd then return end
		preload(folder)
		rigs[rig] = { face = face, textures = folder, nextBlink = workspace:GetServerTimeNow() + rng:NextNumber(2.8, 5) }
	end)
end

workspace.DescendantAdded:Connect(track)
for _, d in ipairs(workspace:GetDescendants()) do track(d) end

local stepTrail   -- морозные следы Cold Cap (ниже)

RunService.Heartbeat:Connect(function(dt)
	local now = workspace:GetServerTimeNow()
	for rig, s in pairs(rigs) do
		if not s then
			-- ещё ждём голову (track)
		elseif not (rig.Parent and (s.hd or s.face.Parent) and rig:IsDescendantOf(workspace)) then
			rigs[rig] = nil
		else
			local name = rig:GetAttribute("FaceEmotion") or "Idle"
			local start = rig:GetAttribute("FaceEmotionStartedAt") or now
			local sprite, lid, canBlink = Face.Evaluate(name, now - start)
			if canBlink then
				if now >= s.nextBlink then s.blinkStart = now; s.nextBlink = now + rng:NextNumber(2.8, 5.5) end
				if s.blinkStart then
					local dt = now - s.blinkStart
					if dt < .045 then lid = 1
					elseif dt < .08 then lid = 2
					elseif dt < .15 then lid = 3
					elseif dt < .19 then lid = 2
					elseif dt < .24 then lid = 1
					else s.blinkStart = nil end
				end
			else
				s.blinkStart = nil
				s.nextBlink = now + rng:NextNumber(2.8, 5.5)
			end
			if s.hd then
				-- кадр HD-лица: пишем атрибут только при смене (его слушает HDFaceSync)
				local key = sprite .. "_" .. lid
				if s.key ~= key then
					s.key = key
					rig:SetAttribute("FaceSpriteKey", key)   -- HDFaceSync тут же перерисует лицо
					--[[ ⚠️ АТЛАС ЕЩЁ НЕ ПРИЕХАЛ — ВЕКИ ДЕЛАЕМ НА НОВОМ ЛИЦЕ V7.
					     Атлас эмоций огромный (4096×2560): на плоту он грузится дольше
					     10 с, которые ему даёт HDFaceSync, и тот сдаётся («HD face atlas
					     failed to load»). Сон/зевок/грусть рисуются только из атласа —
					     без него на месте лица пусто или улыбка с открытыми глазами.
					     Пока атлас не загружен, держим V7 и закрываем веки по кадру
					     (lid 0..3 — как поджатие полосы глаз в самом HDFaceSync).
					     Атлас доехал — не вмешиваемся, эмоции показывает он. ]]
					local carrier = rig:FindFirstChild("HDFaceCarrier")
					local g = carrier and carrier:FindFirstChild("HDFace")
					local vp = g and g:FindFirstChild("FaceViewport")
					local atlas = vp and vp:FindFirstChild("AtlasExpression")
					local portrait = g and g:FindFirstChild("PortraitV7")
					if atlas and portrait and not atlas.IsLoaded then
						local open = ({ [0] = 1, [1] = 0.65, [2] = 0.2, [3] = 0.025 })[lid] or 1
						portrait.Visible = true
						vp.Visible = false
						local eyes = portrait:FindFirstChild("Eyes")
						if eyes then
							eyes.Size = UDim2.fromScale(1, 190 / 1280 * open)
							eyes.Position = UDim2.fromScale(0, (500 + 95 * (1 - open)) / 1280)
						end
					end
				end
				--[[ ⚠️ ИСХОДНУЮ КАРТИНКУ ЛИЦА (Expression) ПРЯЧЕМ САМИ. Она лежит ПОВЕРХ
				     атласа эмоций, и HDFaceSync прячет её, только если атлас (4096×2560)
				     успел загрузиться за 10 с, — иначе навсегда оставалось лицо с
				     открытыми глазами: спит (zzz), а глаза открыты. Атлас уже создан
				     (FaceViewport) — Expression больше не нужна. ]]
				if not s.exprHidden then
					local carrier = rig:FindFirstChild("HDFaceCarrier")
					local g = carrier and carrier:FindFirstChild("HDFace")
					local ex = g and g:FindFirstChild("Expression")
					if ex and g:FindFirstChild("FaceViewport") then
						ex.Visible = false
						s.exprHidden = true
					end
				end
				if not s.noTrail then stepTrail(rig, s, dt) end
			else
				local value = s.textures:FindFirstChild(sprite .. "_" .. lid)
				if value and s.face.Texture ~= value.Value then s.face.Texture = value.Value end
			end
		end
	end
end)

--[[ ═══ МОРОЗНЫЕ СЛЕДЫ COLD CAP — ОТНОСИТЕЛЬНО ПЛОТА ═══
     Оригинальный FrostFootsteps меряет шаги по движению торса в МИРЕ и кладёт
     заякоренные следы в мир. На плывущем плоту это ломается дважды: стоящий
     герой «шагает» вместе с плотом (следы сыплются без конца), а сами следы
     остаются позади в море. Здесь путь меряем в системе координат плота
     (Raft.PrimaryPart), и каждый след каждый кадр ставим туда же относительно
     плота. Вид — как у оригинала: иней (Hoarfrost) + облачко пара, живёт ~2 с.
     Атрибут FrostTrailEnabled = false у модели выключает новые следы. ]]
local TweenService = game:GetService("TweenService")
local HOARFROST = "rbxassetid://129069088437323"
local VAPOR = "rbxassetid://84963886485704"
local CRYSTAL = "rbxassetid://105117069614865"   -- кристаллы и ледяная пыль
local trailFolder = Instance.new("Folder")
trailFolder.Name = "ColdCapRaftTrail"
trailFolder.Parent = workspace
local plates = {}   -- [plate] = { ref = BasePart, offset = CFrame }

local function raftRef()
	local raft = workspace:FindFirstChild("Raft")
	return raft and raft.PrimaryPart
end

local function footprint(rig, legName, ref)
	local leg = rig:FindFirstChild(legName)
	local torso = rig:FindFirstChild("Torso")
	if not (leg and torso) then return end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rig, trailFolder }
	local hit = workspace:Raycast(leg.Position + Vector3.new(0, 1, 0), Vector3.new(0, -4, 0), params)
	if not hit then return end
	local n = hit.Normal
	local at = hit.Position
	--[[ ⚠️ ЛУЧ УШЁЛ НИЖЕ ПОДОШВЫ — СЛЕД НА ВЫСОТУ СТОПЫ. Настил фермы не ловит
	     лучи (CanQuery выключен, чтобы не мешать кликам), и луч проходил сквозь
	     него до палубы плота: след создавался, но лежал ПОД полом — невидимый. ]]
	local footY = leg.Position.Y - leg.Size.Y / 2
	if at.Y < footY - 0.25 then
		at = Vector3.new(at.X, footY, at.Z)
		n = Vector3.yAxis
	end
	local tangent = torso.CFrame.RightVector - n * torso.CFrame.RightVector:Dot(n)
	if tangent.Magnitude < 0.01 then return end
	local size = Vector3.new(rng:NextNumber(1.1, 1.75), 0.01, rng:NextNumber(1.15, 1.8))
	local plate = Instance.new("Part")
	plate.Name = "FrostPrint"
	plate.Size = size * 0.72
	plate.Transparency = 1
	plate.Anchored, plate.CanCollide, plate.CanTouch, plate.CanQuery, plate.CastShadow = true, false, false, false, false
	-- 0.08, а не 0.025: ноги работника чуть утоплены в траву фермы — тонкий след уходил под неё
	plate.CFrame = CFrame.fromMatrix(at + n * 0.08, tangent.Unit, n) * CFrame.Angles(0, rng:NextNumber(-math.pi, math.pi), 0)
	plate.Parent = trailFolder
	TweenService:Create(plate, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = size }):Play()

	-- ⬇ дальше — вид из FrostFootsteps.luau (хендофф handoff_coldcap) без изменений:
	-- иней рассыпается на 16 осколков и тает, пар, кристаллы и ледяная пыль
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(512, 512)
	gui.LightInfluence = 0.25
	gui.AlwaysOnTop = false
	gui.Parent = plate
	for y = 0, 3 do
		for x = 0, 3 do
			local clip = Instance.new("Frame")
			clip.Name = "IceFragment"
			clip.Size = UDim2.fromScale(0.25, 0.25)
			clip.Position = UDim2.fromScale(x / 4, y / 4)
			clip.BackgroundTransparency = 1
			clip.BorderSizePixel = 0
			clip.ClipsDescendants = true
			clip.Parent = gui
			local im = Instance.new("ImageLabel")
			im.BackgroundTransparency = 1
			im.Size = UDim2.fromScale(4, 4)
			im.Position = UDim2.fromScale(-x, -y)
			im.Image = HOARFROST
			im.ImageTransparency = 1
			im.ImageColor3 = Color3.fromRGB(230, 241, 246)
			im.Parent = clip
			-- ⚠️ ЯРЧЕ И ДОЛЬШЕ ИСХОДНИКА (там 0.55–0.68 и таяние через 0.7 с): на светлых
			-- досках и траве плота такой иней не было видно вовсе
			TweenService:Create(im, TweenInfo.new(0.18), { ImageTransparency = rng:NextNumber(0.45, 0.58) }):Play()
			task.delay(1.6 + rng:NextNumber(0, 0.4), function()
				if not plate.Parent then return end
				local duration = rng:NextNumber(0.6, 0.9)
				TweenService:Create(im, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { ImageTransparency = 1 }):Play()
				TweenService:Create(clip, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					Position = UDim2.fromScale(x / 4 + (x - 1.5) * 0.012, y / 4 + (y - 1.5) * 0.012),
				}):Play()
			end)
		end
	end
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, 0.08, 0)
	att.Parent = plate
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "ColdVapor"
	mist.Texture = VAPOR
	mist.Rate = 0
	mist.Lifetime = NumberRange.new(0.9, 1.4)
	mist.Speed = NumberRange.new(0.15, 0.35)
	mist.EmissionDirection = Enum.NormalId.Top
	mist.SpreadAngle = Vector2.new(22, 22)
	mist.Rotation = NumberRange.new(-25, 25)
	mist.RotSpeed = NumberRange.new(-15, 15)
	mist.Acceleration = Vector3.new(0, 0.12, 0)
	mist.Drag = 0.5
	mist.Color = ColorSequence.new(Color3.fromRGB(228, 239, 246))
	mist.LightEmission, mist.LightInfluence = 0.08, 0.15
	-- ⚠️ ЧАСТИЦЫ ЕДУТ СО СЛЕДОМ: в мировых осях они отставали от плывущего плота («по инерции»)
	mist.LockedToPart = true
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.65), NumberSequenceKeypoint.new(0.45, 1.1), NumberSequenceKeypoint.new(1, 1.45) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.65), NumberSequenceKeypoint.new(0.5, 0.78), NumberSequenceKeypoint.new(1, 1) })
	mist.Parent = att
	mist:Emit(2)
	local crystals = Instance.new("ParticleEmitter")
	crystals.Name = "RisingFrostCrystals"
	crystals.Texture = CRYSTAL
	crystals.Rate = 0
	crystals.Lifetime = NumberRange.new(0.7, 1.2)
	crystals.Speed = NumberRange.new(0.25, 0.55)
	crystals.EmissionDirection = Enum.NormalId.Top
	crystals.SpreadAngle = Vector2.new(40, 40)
	crystals.Acceleration = Vector3.new(0, 0.2, 0)
	crystals.Rotation = NumberRange.new(0, 360)
	crystals.RotSpeed = NumberRange.new(-100, 100)
	crystals.LockedToPart = true
	crystals.LightEmission, crystals.LightInfluence = 0.1, 0
	crystals.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.035), NumberSequenceKeypoint.new(0.2, 0.075, 0.025), NumberSequenceKeypoint.new(1, 0.025) })
	crystals.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(0.55, 0.65), NumberSequenceKeypoint.new(1, 1) })
	crystals.Parent = att
	local dust = crystals:Clone()
	dust.Name = "FineFrostDust"
	dust.Color = ColorSequence.new(Color3.fromRGB(225, 239, 245))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.018), NumberSequenceKeypoint.new(0.3, 0.04), NumberSequenceKeypoint.new(1, 0) })
	dust.Speed = NumberRange.new(0.2, 0.55)
	dust.SpreadAngle = Vector2.new(70, 70)
	dust.Lifetime = NumberRange.new(0.55, 1)
	dust.LightEmission = 0.12
	dust.Parent = att
	dust:Emit(rng:NextInteger(5, 8))
	task.delay(0.05, function() if plate.Parent then crystals:Emit(rng:NextInteger(2, 4)) end end)
	task.delay(0.3, function() if plate.Parent then mist:Emit(1); dust:Emit(rng:NextInteger(3, 5)) end end)
	if not rig:GetAttribute("FrostTrailLogged") then
		rig:SetAttribute("FrostTrailLogged", true)
		print(("[Cold Cap] морозный след на плоту: %s (относительно палубы: %s)"):format(rig:GetFullName(), tostring(ref ~= nil)))
	end
	if ref then plates[plate] = { ref = ref, offset = ref.CFrame:ToObjectSpace(plate.CFrame) } end
	game:GetService("Debris"):AddItem(plate, 3.2)
end

stepTrail = function(rig, s, dt)
	local torso = rig:FindFirstChild("Torso")
	if not torso then return end
	local ref = raftRef()
	-- позиция торса в системе плота (без плота — в мире)
	local p = ref and ref.CFrame:PointToObjectSpace(torso.Position) or torso.Position
	local last, lastRef = s.trailLast, s.trailRef
	s.trailLast, s.trailRef = p, ref
	s.trailCool = (s.trailCool or 0) + dt
	if not last or lastRef ~= ref then s.trailTravel = 0 return end
	local d = p - last
	if ref then d = ref.CFrame:VectorToWorldSpace(d) end
	local delta = Vector3.new(d.X, 0, d.Z).Magnitude
	if delta > 5 then s.trailTravel = 0 return end   -- телепорт
	--[[ ⚠️ НОЛЬ ЗА КАДР — ЕЩЁ НЕ «СТОИТ». Работника двигает сервер, а позы приходят
	     пакетами реже кадра: между ними смещение нулевое. Раньше путь от этого
	     обнулялся каждый второй кадр и до шага (0.85) почти не дорастал — следов
	     не было. Обнуляем, только если стоит дольше 0.4 с. ]]
	if delta < 0.002 then
		s.trailIdle = (s.trailIdle or 0) + dt
		if s.trailIdle > 0.4 then s.trailTravel = 0 end
		return
	end
	s.trailIdle = 0
	s.trailTravel = (s.trailTravel or 0) + delta
	if s.trailTravel >= 0.85 and s.trailCool >= 0.12 then
		s.trailTravel, s.trailCool = 0, 0
		if rig:GetAttribute("FrostTrailEnabled") ~= false then
			s.trailLeft = not s.trailLeft
			footprint(rig, s.trailLeft and "Left Leg" or "Right Leg", ref)
		end
	end
end

-- следы едут вместе с плотом
RunService.Heartbeat:Connect(function()
	for plate, f in pairs(plates) do
		if not plate.Parent or not f.ref.Parent then
			plates[plate] = nil
		else
			plate.CFrame = f.ref.CFrame * f.offset
		end
	end
end)

print("[Лицо рыбака] мимика FaceTextures готова")
