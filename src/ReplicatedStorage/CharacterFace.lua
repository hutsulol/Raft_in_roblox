--[[
	МИМИКА ЖИТЕЛЕЙ R6 — ОБЩАЯ БАЗА (хендоффы рыбака Fisherman_Classic_V1 и
	пирата Pirate_Animations_V2: API и временная шкала у них одинаковые). Лицо —
	обычный Decal Head.face, рисунки — StringValue в папке FaceTextures САМОЙ
	модели (ключи Idle_0 … SleepingBreath_3, суффикс 0–3 = насколько закрыты
	глаза). Рисунки у каждого персонажа свои, состояния и переходы — общие.
	FishermanFace — старое имя этого же модуля (ссылка сюда).

	Сервер: Face.Set(rig, "FallingAsleep") — пишет атрибуты FaceEmotion и
	FaceEmotionStartedAt (серверное время); клиент (FishermanFaceAnimator)
	сам считает фазу — поздно зашедший видит тот же кадр.
	Face.Sleep(rig, asleep) — для AI: засыпает/просыпается только на переходе.

	Имена: Idle, Happy, Focused, Surprised, Sad, Angry, Tired, FallingAsleep,
	Sleeping, WakingUp.
]]

local Face = {}
Face.Names = { "Idle", "Happy", "Focused", "Surprised", "Sad", "Angry", "Tired", "FallingAsleep", "Sleeping", "WakingUp" }
local valid = {}
for _, name in ipairs(Face.Names) do valid[name] = true end

-- у модели есть мимика этого пака?
-- (или HD-лицо Cold Cap: HDFaceCarrier + атлас, кадр — атрибут FaceSpriteKey)
function Face.Has(rig)
	return rig ~= nil and (rig:FindFirstChild("FaceTextures") ~= nil or rig:FindFirstChild("HDFaceCarrier") ~= nil)
end

function Face.Set(rig, name)
	if not (Face.Has(rig) and valid[name]) then return end
	-- повторный Set перезапускает переход
	rig:SetAttribute("FaceEmotionStartedAt", workspace:GetServerTimeNow())
	rig:SetAttribute("FaceEmotion", name)
end

-- сменить эмоцию, только если она другая (не перезапускать каждый кадр)
function Face.Ensure(rig, name)
	if Face.Has(rig) and rig:GetAttribute("FaceEmotion") ~= name then Face.Set(rig, name) end
end

local ASLEEP = { FallingAsleep = true, Sleeping = true }
function Face.Sleep(rig, asleep)
	if not Face.Has(rig) then return end
	local now = ASLEEP[rig:GetAttribute("FaceEmotion")] == true
	if asleep and not now then Face.Set(rig, "FallingAsleep")
	elseif not asleep and now then Face.Set(rig, "WakingUp") end
end

-- чистая раскладка по времени: спрайт, степень век 0–3, можно ли моргать
function Face.Evaluate(name, elapsed)
	elapsed = math.max(0, elapsed)
	if name == "FallingAsleep" then
		if elapsed < .7 then return "Tired", 0, false end
		if elapsed < 1.6 then return "Yawning", 1, false end
		if elapsed < 2.1 then return "Tired", 1, false end
		if elapsed < 2.6 then return "Tired", 2, false end
		name = "Sleeping"
	elseif name == "WakingUp" then
		if elapsed < .35 then return "Sleeping", 3, false end
		if elapsed < .65 then return "Tired", 2, false end
		if elapsed < 1.1 then return "Tired", 1, false end
		if elapsed < 1.7 then return "Yawning", 0, false end
		if elapsed < 2 then return "Tired", 0, false end
		if elapsed < 2.18 then return "Tired", 3, false end
		if elapsed < 2.6 then return "Tired", 0, false end
		name = "Idle"
	end
	if name == "Sleeping" then
		return math.sin(elapsed * 1.8) > .35 and "SleepingBreath" or "Sleeping", 3, false
	end
	if not valid[name] then name = "Idle" end
	return name, 0, true
end

return Face
