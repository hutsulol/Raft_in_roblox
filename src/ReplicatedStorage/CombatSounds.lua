-- CombatSounds.lua  (ReplicatedStorage, shared)
-- ONE place for all combat SFX so they stay tidy instead of turning into a wall of noise:
--   • every sound is POSITIONAL (3D, distance-attenuated) → far-away shots are quiet;
--   • each category is THROTTLED (min seconds between plays) → a burst of shots/hits/destroys
--     can't stack on top of itself;
--   • moderate volumes so nothing drowns the rest.
-- Server scripts call:  CombatSounds.play("cannon", worldPosition)
-- All sound ids are Creator Store SFX (swap freely below).

local Debris       = game:GetService("Debris")
local Workspace    = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local CombatSounds = {}

-- category → id / volume / pitch / maxDist / length (cleanup) / throttle (min s between plays)
local SOUNDS = {
	cannon   = { id = "rbxassetid://3802269741", volume = 0.45, pitch = 1.05, maxDist = 220, length = 3, throttle = 0.06 }, -- player cannon
	magma    = { id = "rbxassetid://9114444008", volume = 0.55, pitch = 1.00, maxDist = 240, length = 3, throttle = 0.06 }, -- fire cannon / fire ship (fiery torch whoosh)
	shipFire = { id = "rbxassetid://3802269741", volume = 0.40, pitch = 0.80, maxDist = 320, length = 3, throttle = 0.10 }, -- enemy ship cannon (deeper)
	bulletWood = { id = "rbxasset://sounds/snap.mp3", volume = 0.28, pitch = 1.15, maxDist = 120, length = 1, throttle = 0.04 }, -- пуля в доску катера
	ricochet   = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.18, pitch = 1.6, maxDist = 120, length = 1, throttle = 0.05 }, -- рикошет пули
	hit      = { id = "rbxassetid://9120802004", volume = 0.50, pitch = 1.00, maxDist = 240, length = 2, throttle = 0.08 }, -- projectile hits a ship (wood)
	downed   = { id = "rbxassetid://9119701508", volume = 0.60, pitch = 0.90, maxDist = 340, length = 4, throttle = 0.20 }, -- ship destroyed
	sink     = { id = "rbxassetid://9120584388", volume = 0.30, pitch = 0.90, maxDist = 320, length = 2.0, throttle = 0.20, loop = true, fade = 2.0 }, -- ship sinking: quiet, loops 2s, then fades 0.3→0 over 2s
	-- ЛЕДЯНОЙ КОРАБЛЬ. Звуки сосульки — ВСТРОЕННЫЕ ассеты Roblox (rbxasset:// грузятся
	-- всегда), пара и громкости ВЫБРАНЫ АВТОРОМ через дев-тюнер (сухой треск + тихий
	-- водяной бум). frostBreath пока каталожный: если молчит — скажи, заменю на встроенный.
	frostBreath = { id = "rbxassetid://9125574563", volume = 0.55, pitch = 1.00, maxDist = 260, length = 2.6, throttle = 0.30 }, -- морозный выдох из пасти (холодный ветер/вьюга)
	iceShatter  = { id = "rbxasset://sounds/snap.mp3",         volume = 0.50, pitch = 1.0, maxDist = 240, length = 2.0, throttle = 0.05 }, -- сухой ледяной треск
	iceBoom     = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.05, pitch = 0.6, maxDist = 280, length = 3.0, throttle = 0.08 }, -- едва слышный водяной бум под треском
	-- ПУЛЕМЁТ: стреляет ДЕРЕВЯШКАМИ → не пороховой хлопок, а сухой деревянный «тук»
	-- (встроенный треск на пониженном питче). Тихо + pitchVar: очередь 8 выстр/с не должна
	-- превращаться в кашу, а разброс питча убирает «механическую» одинаковость.
	woodShot    = { id = "rbxasset://sounds/snap.mp3", volume = 0.32, pitch = 0.72, pitchVar = 0.12,
	                maxDist = 230, length = 1.0, throttle = 0.05 },
	-- ПУЛЕМЁТ II (эпический): настоящий ствол, не деревяшка → берём пушечный сэмпл на
	-- ВЫСОКОМ питче (получается сухой резкий «крак» вместо баса), тихо и коротко —
	-- на темпе 8 выстр/с выстрелы накладываются и складываются в очередь.
	mgShot      = { id = "rbxassetid://3802269741", volume = 0.22, pitch = 1.75, pitchVar = 0.10,
	                maxDist = 280, length = 0.7, throttle = 0.05 },
	-- РЕВОЛЬВЕР морпеха: тот же пушечный сэмпл, но ниже и громче винтовочного —
	-- одиночный тяжёлый хлопок вместо сухого треска очереди. Темп у револьвера
	-- низкий, поэтому громкость можно позволить, а throttle держим коротким.
	pistolShot  = { id = "rbxassetid://3802269741", volume = 0.38, pitch = 1.15, pitchVar = 0.08,
	                maxDist = 280, length = 1.0, throttle = 0.05 },
	-- САБЛЯ пиратов острова: классический слэш из ВСТРОЕННЫХ ассетов (rbxasset://
	-- грузится всегда, в т.ч. в неопубликованном плейсе). Раньше замах играл «hit» —
	-- деревянный удар по кораблю, тот же, что у пожирателя плота, и читался как он.
	sabre       = { id = "rbxasset://sounds/swordslash.wav", volume = 0.5, pitch = 1.0, pitchVar = 0.06,
	                maxDist = 200, length = 1.0, throttle = 0.05 },
	-- свист замаха (начало атаки); сам «слэш» играет только при ПОПАДАНИИ
	sabreWhoosh = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.35, pitch = 1.05, pitchVar = 0.08,
	                maxDist = 160, length = 1.0, throttle = 0.05 },
}

local lastPlayed = {} -- category → os.clock() of its last play (for throttling)

function CombatSounds.play(category, position)
	local cfg = SOUNDS[category]
	if not cfg or typeof(position) ~= "Vector3" then return end
	local now = os.clock()
	if now - (lastPlayed[category] or 0) < cfg.throttle then return end -- anti-spam / anti-mush
	lastPlayed[category] = now

	local emitter = Instance.new("Part")
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CanTouch = false
	emitter.Transparency = 1
	emitter.Size = Vector3.new(1, 1, 1)
	emitter.CFrame = CFrame.new(position)
	emitter.Parent = Workspace

	local s = Instance.new("Sound")
	s.SoundId = cfg.id
	s.Volume = cfg.volume
	-- pitchVar (необязательный): случайный разброс питча ±var — очередь одинаковых
	-- выстрелов перестаёт звучать «механически»
	s.PlaybackSpeed = cfg.pitch + (cfg.pitchVar and (math.random() * 2 - 1) * cfg.pitchVar or 0)
	s.Looped = cfg.loop == true
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMaxDistance = cfg.maxDist
	s.Parent = emitter
	s:Play()

	-- smooth tail: play at full volume for `length` s, THEN fade Volume → 0 over `fade` s and only
	-- remove the emitter once that fade has fully finished (Tween.Completed) — so the sound is
	-- already silent when it's destroyed and never cuts off abruptly.
	if cfg.fade and cfg.fade > 0 then
		task.delay(cfg.length, function()
			if not s.Parent then return end
			local tw = TweenService:Create(s, TweenInfo.new(cfg.fade, Enum.EasingStyle.Linear), { Volume = 0 })
			tw.Completed:Connect(function()
				if emitter.Parent then emitter:Destroy() end
			end)
			tw:Play()
		end)
		Debris:AddItem(emitter, cfg.length + cfg.fade + 2) -- safety net if the tween is interrupted
	else
		Debris:AddItem(emitter, cfg.length) -- short one-shot: clean up after it finishes
	end
end

return CombatSounds
