-- WaveTelegraph.client.lua
-- The wave-telegraph FOG: a storm FRONT far on the side tonight's wave will come from (WaveDir).
-- Rises at 60% of the day (server flags workspace.WaveTelegraph), STAYS through the night while the
-- wave is alive, and slowly dissipates once the player clears every ship and mob. Lightning volleys
-- (1–3 bolts at once) strike inside it. On the FIRST rise a short cutscene watches the fog gather.
-- Purely visual, client-side. Server publishes: WaveDir (Vector3) + WaveTelegraph (bool).

local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local Players    = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ── look (tweak freely) ──
local DIST          = 450   -- studs from the raft (recedes with it — unreachable)
local HEIGHT        = 85    -- storm front height
local WIDTH         = 260   -- span across the horizon on that side
local DEPTH         = 70    -- THIN front-to-back → the smoke concentrates into a READABLE wall
local RISE_TIME     = 10    -- seconds the fog takes to build up to full density ("поднимается")
local DISSIPATE_TIME = 8    -- seconds the fog takes to melt away once the wave is cleared
local CUTSCENE_TIME = 6     -- first-day cutscene length: the camera watches the fog gather
local MYSTERY_SOUND_ID = "" -- ← вставь сюда свой rbxassetid для загадочного звука; пусто = процедурный
                            -- низкий "ветер" из встроенного звука (гарантированно грузится)
local THUNDER_SOUND_ID = "" -- ← свой rbxassetid для грома; пусто = процедурные глухие раскаты

-- ── СВОИ ТЕКСТУРЫ ШТОРМА ──
-- Исходники нарисованы и лежат в test/: Fog_cloud.png (клуб тумана, 512²) и
-- Lightning_bolts.png (лист из 4 разрядов, 4×512×1024). Загрузи их в Roblox и
-- впиши id сюда. Пусто = запасной вариант: встроенный дым для тумана и старые
-- молнии из деталей — так эффект работает и без загруженных картинок.
local FOG_TEXTURE  = "rbxassetid://87941251355571"    -- клуб тумана
local BOLT_TEXTURE = "rbxassetid://104013527850230"   -- лист молний (4 варианта в ряд)
-- ⚠️ РАЗМЕР КАДРА СЧИТАЕТСЯ ПО ЗАГРУЖЕННОЙ КАРТИНКЕ, А НЕ ПО ИСХОДНИКУ.
-- Roblox ужимает загружаемые изображения так, чтобы ни одна сторона не была
-- больше 1024: наш лист 2048×1024 лёг в 1024×512, то есть кадр стал 256×512.
-- С исходными 512×1024 три смещения из четырёх уходили за край картинки, и
-- молния просто не рисовалась.
local BOLT_COLS, BOLT_W, BOLT_H = 4, 256, 512

local function makeEmitter(src, cfg)
	local p = Instance.new("ParticleEmitter")
	p.Texture = (FOG_TEXTURE ~= "") and FOG_TEXTURE or "rbxasset://textures/particles/smoke_main.dds"
	p.Color = cfg.color
	p.LightEmission = 0.05
	p.LightInfluence = 0.55
	p.Size = cfg.size
	p.Transparency = cfg.transparency
	p.Rate = 0
	p.Lifetime = cfg.lifetime
	p.Speed = cfg.speed
	p.SpreadAngle = cfg.spread
	p.EmissionDirection = Enum.NormalId.Top
	p.Acceleration = Vector3.new(0, cfg.riseAccel, 0)
	p.Rotation = NumberRange.new(0, 360)
	p.RotSpeed = NumberRange.new(-16, 16)
	p.Parent = src
	return p
end

local function build()
	local model = Instance.new("Model")
	model.Name = "WaveTelegraph"

	-- LOW DENSE BANK: the rolling sea-fog base — darker, more opaque, hugging the water
	local bank = Instance.new("Part")
	bank.Name = "Bank"
	bank.Anchored = true; bank.CanCollide = false; bank.CanQuery = false; bank.CanTouch = false
	bank.CastShadow = false; bank.Transparency = 1
	bank.Size = Vector3.new(WIDTH, HEIGHT * 0.35, DEPTH)
	bank.Parent = model
	model.PrimaryPart = bank

	-- TALL STORM WALL rising behind the bank — bigger, bluer, softer
	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Anchored = true; wall.CanCollide = false; wall.CanQuery = false; wall.CanTouch = false
	wall.CastShadow = false; wall.Transparency = 1
	wall.Size = Vector3.new(WIDTH, HEIGHT, DEPTH)
	wall.Parent = model
	local weld = Instance.new("WeldConstraint") -- keeps the two anchored parts logically grouped
	weld.Part0 = bank; weld.Part1 = wall; weld.Parent = bank

	local bankEm = makeEmitter(bank, {
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(62, 70, 84)),    -- dark storm base
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(112, 120, 134)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(168, 176, 188)),
		}),
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 55),
			NumberSequenceKeypoint.new(0.4, 90),
			NumberSequenceKeypoint.new(1, 130),
		}),
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.3),  -- DENSE — this is the readable body
			NumberSequenceKeypoint.new(0.75, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		}),
		lifetime = NumberRange.new(4, 7),
		speed = NumberRange.new(1, 3),
		spread = Vector2.new(85, 85),
		riseAccel = 1.2,
	})
	local wallEm = makeEmitter(wall, {
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(84, 94, 114)),   -- blue-slate towers
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(130, 140, 158)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(184, 192, 206)),
		}),
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 90),
			NumberSequenceKeypoint.new(0.5, 150),
			NumberSequenceKeypoint.new(1, 210),
		}),
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.55),
			NumberSequenceKeypoint.new(0.8, 0.65),
			NumberSequenceKeypoint.new(1, 1),
		}),
		lifetime = NumberRange.new(6, 10),
		speed = NumberRange.new(2, 5),
		spread = Vector2.new(60, 60),
		riseAccel = 2.2,
	})

	return model, bank, { { em = bankEm, max = 60 }, { em = wallEm, max = 34 } }
end

local effect, fogCore, emitters = build()

-- fog density 0..1 drives every emitter
local density = 0
local function setDensity(a)
	density = a
	for _, r in ipairs(emitters) do
		r.em.Rate = r.max * a
	end
end

-- ── state ──
local visible = false
local dissipating = false
local riseT0 = 0
local dissT0 = 0
local densAtDissipate = 0
local lastDir = Vector3.new(1, 0, 0) -- the fog KEEPS its side while dissipating

-- "Туман поднимается..." — lower-third cinematic line (kept OUT of the top HUD area)
local function fogToast()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "FogToastGui"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 120; gui.Parent = pg
	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.Position = UDim2.fromScale(0.5, 0.72)
	lbl.Size = UDim2.fromOffset(640, 50)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = "Туман поднимается..."
	lbl.TextSize = 32
	lbl.TextColor3 = Color3.fromRGB(214, 222, 230)
	lbl.TextStrokeColor3 = Color3.fromRGB(15, 22, 30)
	lbl.TextStrokeTransparency = 1
	lbl.TextTransparency = 1
	lbl.Parent = gui
	TweenService:Create(lbl, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0, TextStrokeTransparency = 0.35 }):Play()
	task.delay(4.5, function()
		TweenService:Create(lbl, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(1.3)
		gui:Destroy()
	end)
end

-- the mysterious sound: your asset if MYSTERY_SOUND_ID is set, otherwise a deep slowed wind
local function mysterySound(long)
	if long then
		-- the opening STING of the cutscene: a deep double "whoom" swell as the fog begins to rise
		local whoom = Instance.new("Sound")
		whoom.SoundId = "rbxasset://sounds/impact_water.mp3"
		whoom.PlaybackSpeed = 0.16
		whoom.Volume = 0.45
		whoom.Parent = Workspace
		whoom:Play()
		task.delay(1.4, function()
			local w2 = whoom:Clone()
			w2.PlaybackSpeed = 0.11; w2.Volume = 0.3; w2.Parent = Workspace
			w2:Play()
			task.delay(10, function() w2:Destroy() end)
		end)
		task.delay(10, function() whoom:Destroy() end)
	end
	local s = Instance.new("Sound")
	if MYSTERY_SOUND_ID ~= "" then
		s.SoundId = MYSTERY_SOUND_ID
		s.Volume = 0.45
	else
		s.SoundId = "rbxasset://sounds/action_falling.mp3"
		s.Looped = true
		s.PlaybackSpeed = 0.42
		s.Volume = 0
	end
	s.Parent = Workspace
	s:Play()
	if s.Looped then
		local dur = long and CUTSCENE_TIME or 3
		TweenService:Create(s, TweenInfo.new(1.4), { Volume = 0.42 }):Play()
		task.delay(dur - 1.2, function()
			TweenService:Create(s, TweenInfo.new(1.2), { Volume = 0 }):Play()
		end)
		task.delay(dur + 0.3, function() s:Destroy() end)
	else
		task.delay(12, function() s:Destroy() end)
	end
end

local strikeVolley -- assigned below; forward-declared for the cutscene

-- Вернуть камеру игроку. ⚠️ ОДНОГО CameraType=Custom МАЛО: если игрок УМЕР во
-- время катсцены, CameraSubject остаётся у старого, уничтоженного Humanoid — и
-- камера замирает на месте смерти, к новому персонажу не приходит. Поэтому
-- subject возвращаем явно, дождавшись респавна, если он ещё идёт.
local function giveCameraBack()
	local cam = Workspace.CurrentCamera
	if cam then cam.CameraType = Enum.CameraType.Custom end
	task.spawn(function()
		local plr = Players.LocalPlayer
		local char = plr.Character or plr.CharacterAdded:Wait()
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
		local cam2 = Workspace.CurrentCamera
		if hum and cam2 then cam2.CameraSubject = hum end
	end)
end

-- FIRST-DAY CUTSCENE: fast smooth blend in → slow lateral dolly + push-in → fast smooth blend back
local cutsceneShown = false
local function playCutscene(dir)
	local cam = Workspace.CurrentCamera
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (cam and hrp) then return end
	local look = Vector3.new(dir.X, 0, dir.Z)
	look = (look.Magnitude > 0.05) and look.Unit or Vector3.new(1, 0, 0)
	local side = Vector3.new(-look.Z, 0, look.X)

	local BLEND_IN, BLEND_OUT = 0.6, 0.8
	local relReturn = hrp.CFrame:ToObjectSpace(cam.CFrame)
	local function playerCamCF() return hrp.CFrame * relReturn end
	-- the shot FLIES TOWARD the fog: from just behind the player it travels ~190 studs out over the
	-- water (fog stands at DIST=450 → ends visibly close to the wall), climbing and drifting sideways
	local function sceneCF(e)
		local p = hrp.Position
		local travel = -10 + 200 * e
		local lateral = (e * 2 - 1) * 9
		local lift = 6 + 10 * e
		local camPos = p + Vector3.new(0, lift, 0) + look * travel + side * lateral
		local target = p + look * (DIST * 0.9) + side * lateral * 0.3 + Vector3.new(0, 30, 0)
		return CFrame.lookAt(camPos, target)
	end

	cam.CameraType = Enum.CameraType.Scriptable
	mysterySound(true)
	fogToast()
	task.delay(1.6, function() if strikeVolley then strikeVolley() end end)
	task.delay(4.1, function() if strikeVolley then strikeVolley() end end)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not (hrp.Parent and cam) then
			conn:Disconnect()
			giveCameraBack()   -- игрок умер посреди сцены: камеру — новому персонажу
			return
		end
		local t = os.clock() - t0
		if t < BLEND_IN then
			local a = t / BLEND_IN
			a = a * a * (3 - 2 * a)
			cam.CFrame = playerCamCF():Lerp(sceneCF(0), a)
		elseif t < BLEND_IN + CUTSCENE_TIME then
			local e = (t - BLEND_IN) / CUTSCENE_TIME
			e = e * e * (3 - 2 * e)
			cam.CFrame = sceneCF(e)
		elseif t < BLEND_IN + CUTSCENE_TIME + BLEND_OUT then
			local a = (t - BLEND_IN - CUTSCENE_TIME) / BLEND_OUT
			a = a * a * (3 - 2 * a)
			cam.CFrame = sceneCF(1):Lerp(playerCamCF(), a)
		else
			conn:Disconnect()
			giveCameraBack()
			-- сцена доиграла: через 3 секунды игрок «думает вслух» про туман
			-- (реплика FogThought, чисто клиентская — см. DialogueUI/DialogueDefs)
			task.delay(3, function()
				if _G.StartLocalDialogue then
					_G.StartLocalDialogue("FogThought")
				end
			end)
		end
	end)
end

-- ── fog lifecycle ──
local function beginShow()
	visible = true
	dissipating = false
	riseT0 = os.clock()
	setDensity(0)
	effect.Parent = Workspace
	-- ⚠️ КАТСЦЕНА — НА ПЕРВЫЙ ТУМАН, А НЕ НА ПЕРВЫЙ ДЕНЬ.
	-- Туман теперь поднимается только с пятого дня (WaveDirector.SIEGE_FROM_DAY),
	-- и проверка «день == 1» не срабатывала бы никогда: игрок так и не увидел бы
	-- вступление к осаде. Показываем его тогда, когда стена встала впервые.
	local dc = ReplicatedStorage:FindFirstChild("DayCount")
	if not cutsceneShown and dc then
		cutsceneShown = true
		task.delay(1, function() -- the fog needs a moment to become visible first
			if visible and not dissipating then playCutscene(lastDir) end
		end)
	else
		mysterySound(false)
	end
end

-- ── ТЕСТОВЫЙ ПОКАЗ (кнопка в настройках) ──
-- Туман штатно поднимает СЕРВЕР (атрибут WaveTelegraph), а рисует его клиент.
-- Для проверки текстур ждать 60% дня незачем: держим свой таймер, который
-- включает туман здесь же, ничего не трогая на сервере. Настройки — тоже
-- клиентский скрипт, поэтому зовут эту функцию напрямую.
local testUntil = 0
_G.TestStormFog = function(seconds)
	testUntil = os.clock() + (tonumber(seconds) or 45)
	-- курс шторма мог ещё не приходить с сервера — ставим сами, чтобы стена
	-- встала перед носом плота, а не в случайную сторону
	local raft = Workspace:FindFirstChild("Raft")
	local rp = raft and raft.PrimaryPart
	if rp then
		local lv = rp.CFrame.LookVector
		local flat = Vector3.new(lv.X, 0, lv.Z)
		lastDir = (flat.Magnitude > 0.01) and flat.Unit or Vector3.new(0, 0, -1)
	end
	return true
end

RunService.RenderStepped:Connect(function()
	local active = Workspace:GetAttribute("WaveTelegraph")
	if not active and os.clock() < testUntil then active = true end
	local dir = Workspace:GetAttribute("WaveDir")
	local raft = Workspace:FindFirstChild("Raft")
	local rp = raft and raft.PrimaryPart

	if active and typeof(dir) == "Vector3" then lastDir = dir end

	-- ⚠️ ФРОНТ СТОИТ ОТ ЗРИТЕЛЯ, А НЕ ОТ ПЛОТА.
	-- Раньше место считалось от плота, и стоило уплыть на остров, как туман
	-- оказывался в двух шагах — в него можно было зайти. Отсчёт от персонажа
	-- держит стену на одном и том же удалении, куда бы игрок ни забрался, и она
	-- честно остаётся недостижимой.
	local viewChar = Players.LocalPlayer.Character
	local viewHrp = viewChar and viewChar:FindFirstChild("HumanoidRootPart")
	local anchor = (viewHrp and viewHrp.Position) or (rp and rp.Position)

	if anchor and visible then
		local c = anchor
		local pos = Vector3.new(c.X + lastDir.X * DIST, c.Y, c.Z + lastDir.Z * DIST)
		-- the front FACES the raft (thin depth toward you, full width across the horizon)
		local face = CFrame.lookAt(pos, Vector3.new(c.X, pos.Y, c.Z))
		effect:PivotTo(face * CFrame.new(0, HEIGHT * 0.2, 0))
		local wall = effect:FindFirstChild("Wall")
		if wall then wall.CFrame = face * CFrame.new(0, HEIGHT * 0.45, -DEPTH * 0.6) end
	end

	if active and anchor then
		if not visible then beginShow() end
		if dissipating then -- came back before fully melting → resume rising from here
			dissipating = false
			riseT0 = os.clock() - density * RISE_TIME
		end
		setDensity(math.clamp((os.clock() - riseT0) / RISE_TIME, 0, 1))
	elseif visible then
		if not dissipating then
			dissipating = true
			dissT0 = os.clock()
			densAtDissipate = density
		end
		local a = 1 - math.clamp((os.clock() - dissT0) / DISSIPATE_TIME, 0, 1)
		setDensity(densAtDissipate * a)
		if a <= 0 and os.clock() - dissT0 > DISSIPATE_TIME + 10 then
			effect.Parent = nil
			visible = false
			dissipating = false
		end
	end
end)

-- ── LIGHTNING: volleys of 1–3 bolts striking different spots inside the front ──
local BOLT_COLOR    = Color3.fromRGB(205, 228, 255)
local LIGHTNING_MIN = 1.2 -- seconds between volleys (random in [MIN, MAX])
local LIGHTNING_MAX = 3.5

local function boltSegment(model, a, b, thick, transparency)
	local seg = Instance.new("Part")
	seg.Anchored = true; seg.CanCollide = false; seg.CanQuery = false; seg.CanTouch = false
	seg.CastShadow = false
	seg.Material = Enum.Material.Neon
	seg.Color = BOLT_COLOR
	seg.Transparency = transparency
	seg.Size = Vector3.new(thick, thick, (b - a).Magnitude)
	seg.CFrame = CFrame.lookAt((a + b) / 2, b)
	seg.Parent = model
end

-- ── НАРИСОВАННАЯ МОЛНИЯ ──
-- Спрайт из листа (4 варианта) на плашке-биллборде: всегда лицом к камере, с
-- готовым свечением и ответвлениями. Разряд из деталей (ниже) остаётся запасным
-- вариантом на случай, если текстура не загружена.
local function spriteBolt(topWorld, bottomY)
	local height = math.max(topWorld.Y - bottomY, 10)
	local anchor = Instance.new("Part")
	anchor.Name = "FogLightning"
	anchor.Anchored = true; anchor.CanCollide = false; anchor.CanQuery = false
	anchor.CanTouch = false; anchor.CastShadow = false; anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(topWorld.X, bottomY + height * 0.5, topWorld.Z)
	anchor.Parent = Workspace

	local bb = Instance.new("BillboardGui")
	bb.Adornee = anchor
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 3000
	-- Scale у BillboardGui — студы; кадр вдвое выше своей ширины
	bb.Size = UDim2.fromScale(height * (BOLT_W / BOLT_H), height)
	bb.Parent = anchor

	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = BOLT_TEXTURE
	img.ImageRectSize = Vector2.new(BOLT_W, BOLT_H)
	img.ImageRectOffset = Vector2.new(math.random(0, BOLT_COLS - 1) * BOLT_W, 0)
	img.ImageColor3 = BOLT_COLOR
	img.Parent = bb

	-- мерцание: вспышка → почти гаснет → добивка → исчезла
	task.spawn(function()
		task.wait(0.07)
		img.ImageTransparency = 0.75
		task.wait(0.05)
		img.ImageTransparency = 0.1
		task.wait(0.08)
		img.ImageTransparency = 0.55
		task.wait(0.06)
		anchor:Destroy()
	end)
	return anchor
end

local function strikeBolt()
	local src = fogCore
	if not (visible and src and src.Parent) then return end
	-- ⚠️ БЬЁТ ПО БЛИЖНЕЙ КРОМКЕ ФРОНТА, А НЕ ВНУТРИ НЕГО.
	-- Раньше разряд рождался в глубине тумана — и туман же его и закрывал:
	-- частицы перед ним перекрывают спрайт, молнии не было видно вовсе.
	local cam = Workspace.CurrentCamera
	local toCam = cam and (cam.CFrame.Position - src.Position) * Vector3.new(1, 0, 1)
	local nearDir = (toCam and toCam.Magnitude > 1) and toCam.Unit or Vector3.new(0, 0, 1)
	local side = Vector3.new(-nearDir.Z, 0, nearDir.X)
	local base = src.Position
		+ nearDir * (DEPTH * 0.42)
		+ side * ((math.random() - 0.5) * WIDTH * 0.7)
	local topWorld = Vector3.new(base.X, src.Position.Y + HEIGHT * 0.35, base.Z)
	local bottomY = src.Position.Y - HEIGHT * 0.25

	if BOLT_TEXTURE ~= "" then
		spriteBolt(topWorld, bottomY)
		local flash = Instance.new("PointLight")
		flash.Color = BOLT_COLOR; flash.Brightness = 18; flash.Range = 300
		flash.Parent = src
		task.delay(0.1, function() flash.Brightness = 6 end)
		task.delay(0.26, function() flash:Destroy() end)
		return
	end

	local segs = math.random(4, 6)
	local totalH = topWorld.Y - bottomY
	local model = Instance.new("Model")
	model.Name = "FogLightning"
	local prev = topWorld
	local mid = nil
	for i = 1, segs do
		local nxt = Vector3.new(topWorld.X + (math.random() - 0.5) * 26, topWorld.Y - totalH * i / segs,
			topWorld.Z + (math.random() - 0.5) * 26)
		if i == segs then nxt = Vector3.new(nxt.X, bottomY, nxt.Z) end
		boltSegment(model, prev, nxt, 2.2, 0)     -- the core
		boltSegment(model, prev, nxt, 6.5, 0.75)  -- soft glow shell around it
		if i == math.ceil(segs / 2) then mid = nxt end
		prev = nxt
	end
	-- a side branch half the time — real lightning forks
	if mid and math.random() < 0.5 then
		local dir2 = Vector3.new((math.random() - 0.5) * 2, -0.6, (math.random() - 0.5) * 2).Unit
		local b1 = mid + dir2 * (10 + math.random() * 8)
		local b2 = b1 + Vector3.new((math.random() - 0.5) * 10, -(8 + math.random() * 8), (math.random() - 0.5) * 10)
		boltSegment(model, mid, b1, 1.3, 0.2)
		boltSegment(model, b1, b2, 1.1, 0.35)
	end
	model.Parent = Workspace
	-- the cloud lights up from inside (transient — only for the strike)
	local flash = Instance.new("PointLight")
	flash.Color = BOLT_COLOR; flash.Brightness = 18; flash.Range = 300
	flash.Parent = src
	task.spawn(function()
		task.wait(0.08)
		for _, p in ipairs(model:GetChildren()) do p.Transparency = 1 end
		flash.Brightness = 3
		task.wait(0.06)
		for _, p in ipairs(model:GetChildren()) do p.Transparency = math.min(p.Size.X > 3 and 0.85 or 0.35, 1) end
		flash.Brightness = 12
		task.wait(0.08)
		model:Destroy()
		flash:Destroy()
	end)
end

-- THUNDER: positional (rolls in FROM the fog side), slightly delayed after the flash like real
-- thunder. One boom per volley; triples hit harder. Procedural = two deep-pitched built-in layers
-- (muffled crack + long low rumble); drop your own id into THUNDER_SOUND_ID to replace it.
local function thunder(intensity)
	local src = fogCore
	if not (src and src.Parent) then return end
	task.delay(0.3 + math.random() * 0.25, function()
		if not src.Parent then return end
		if THUNDER_SOUND_ID ~= "" then
			local s = Instance.new("Sound")
			s.SoundId = THUNDER_SOUND_ID
			s.Volume = 0.18 + 0.06 * intensity  -- тише (было 0.35 + 0.12)
			s.PlaybackSpeed = 0.9 + math.random() * 0.2
			s.RollOffMinDistance = 400; s.RollOffMaxDistance = 6000
			s.Parent = src
			s:Play()
			task.delay(8, function() s:Destroy() end)
			return
		end
		local crack = Instance.new("Sound") -- the muffled clap
		crack.SoundId = "rbxasset://sounds/impact_water.mp3"
		crack.PlaybackSpeed = 0.32 + math.random() * 0.08
		crack.Volume = 0.06 + 0.02 * intensity  -- ещё тише (было 0.11 + 0.04)
		crack.RollOffMinDistance = 400; crack.RollOffMaxDistance = 6000
		crack.Parent = src
		crack:Play()
		local rumble = Instance.new("Sound") -- the long low roll after it
		rumble.SoundId = "rbxasset://sounds/impact_water.mp3"
		rumble.PlaybackSpeed = 0.13 + math.random() * 0.04
		rumble.Volume = 0.05 + 0.02 * intensity  -- ещё тише (было 0.1 + 0.04)
		rumble.RollOffMinDistance = 400; rumble.RollOffMaxDistance = 6000
		rumble.Parent = src
		task.delay(0.18, function() rumble:Play() end)
		task.delay(10, function() crack:Destroy(); rumble:Destroy() end)
	end)
end

-- a volley: 1–3 bolts, each in its own spot, near-simultaneous (tiny natural offsets) + one thunder
strikeVolley = function()
	local n = ({ 1, 2, 2, 3 })[math.random(4)] -- 25% single, 50% double, 25% triple
	for i = 1, n do
		task.delay((i - 1) * 0.12 + math.random() * 0.08, strikeBolt)
	end
	thunder(n)
end

task.spawn(function()
	while true do
		task.wait(LIGHTNING_MIN + math.random() * (LIGHTNING_MAX - LIGHTNING_MIN))
		if visible and density > 0.25 then
			strikeVolley()
		end
	end
end)
