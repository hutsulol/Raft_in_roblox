--[[
	ПОЗЫ АВАТАРА В МЕНЮ «КОМАНДА» ДЛЯ ОБЫЧНОГО R6 (хендофф Pirate_Animations_V2,
	CharacterPresentation с Menu=true). Процедурно, без AnimationId: дыхание,
	стойка, повороты головы; у профиля "Pirate" — перенос веса и жест к полям
	шляпы. Общие для всех: засыпание (голова клонится), сон с дыханием,
	пробуждение с потягиванием — по атрибутам FaceEmotion/FaceEmotionStartedAt
	копии (CharacterFace).

	Только для витринной копии (SurvivorsUI): у живого NPC суставы ведут клипы
	работы, их не трогаем. Лицо копии рисует общий FishermanFaceAnimator.

	local poser = CharacterPoses.new("Pirate")
	local deltas = poser:Step(rig, t)   -- { [имя Motor6D] = CFrame }
	-- C0 = CFrame.new(base.Position) * delta * base.Rotation
]]

local CharacterPoses = {}
CharacterPoses.__index = CharacterPoses

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

function CharacterPoses.new(profile)
	return setmetatable({ profile = profile, lastState = nil, changedAt = 0, from = {}, applied = {} }, CharacterPoses)
end

-- t — время витрины (с), отсчёт дыхания и жестов
function CharacterPoses:Step(rig, t)
	local now = workspace:GetServerTimeNow()
	local state = rig:GetAttribute("FaceEmotion") or "Idle"
	local elapsed = now - (rig:GetAttribute("FaceEmotionStartedAt") or now)
	if state ~= self.lastState then
		self.lastState = state
		self.changedAt = now
		self.from = table.clone(self.applied)
	end
	local a, rad = CFrame.Angles, math.rad
	local breathing = math.sin(t * 1.7)
	local sleep = state == "Sleeping" and 1 or 0
	if state == "FallingAsleep" then sleep = smooth(elapsed / 2.6) end
	if state == "WakingUp" then sleep = 1 - smooth(elapsed / 2.6) end
	local pirate = self.profile == "Pirate"
	local cycle = t % 10
	local salute = smooth((cycle - 3) / .65) * (1 - smooth((cycle - 5.2) / .8)) * (1 - sleep) * (pirate and 1 or 0)
	local wake = state == "WakingUp" and math.sin(math.clamp(elapsed / 2.6, 0, 1) * math.pi) or 0
	local yawn = state == "FallingAsleep" and math.sin(math.clamp(elapsed / 2.1, 0, 1) * math.pi) or 0
	local pose = {
		RootJoint = CFrame.new(0, .025 * breathing, 0) * a(rad(-3 - 8 * sleep), 0, rad((pirate and 4 or 0) * (1 - sleep))),
		Neck = a(rad(3 - 19 * sleep + 10 * wake + breathing), rad((pirate and -9 or 0) * (1 - sleep) + 3 * math.sin(t * .45)), rad(-5 * sleep)),
		["Right Shoulder"] = a(rad(8 + 137 * salute + 135 * wake + 65 * yawn), 0, rad(5 - 24 * salute - 25 * wake)),
		["Left Shoulder"] = a(rad((pirate and 22 or 5) * (1 - sleep) + 135 * wake), 0, rad((pirate and 17 or -5) * (1 - sleep) + 25 * wake)),
		["Right Hip"] = a(rad(-3), 0, rad(5 * (1 - sleep))),
		["Left Hip"] = a(rad(3), 0, rad(-5 * (1 - sleep))),
	}
	local blend = smooth((now - self.changedAt) / .3)
	local out = {}
	for name, target in pairs(pose) do
		local delta = (self.from[name] or CFrame.identity):Lerp(target, blend)
		self.applied[name] = delta
		out[name] = delta
	end
	return out
end

return CharacterPoses
