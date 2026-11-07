--[[
	SeagullAnim.client.lua — играет клипы чаек. Сервер (SeagullAI) только называет клип
	атрибутами, позу считает клиент — протокол зверей из ANIMATIONS.md §6:
		Clip                  цикл; сервер пишет только при смене имени
		ClipOnce + ClipOnceT  разовый; ловится ПО СМЕНЕ МЕТКИ, после него возвращается цикл

	Клипы — SeagullClips (формат CowClips), проигрыватель — SeagullAnimator (близнец
	CowAnimator), пишет прямо в Motor6D.Transform. Публикация анимаций не нужна.

	Чайки находятся по тегу "Seagull". Суставы могут доехать по репликации ПОЗЖЕ модели —
	пока их меньше, чем надо, пересканируем раз в секунду (а не кэшируем «0 из 12» навсегда).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SeagullRig = require(ReplicatedStorage:WaitForChild("SeagullRig"))
local SeagullAnimator = require(ReplicatedStorage:WaitForChild("SeagullAnimator"))

local TAG = "Seagull"
local MOTORS = SeagullRig.MOTORS -- ключ клипа (деталь) → имя сустава
local REQUIRED = { Torso = true } -- обязателен только корень; остальное — по наличию

local attached = {}

local function attach(model)
	if attached[model] then return end
	local a = { motors = {}, missing = true, rescanT = 0, onceActive = false, lastOnceT = nil, anim = nil }

	local function rescan()
		local total, found = 0, 0
		for key, motorName in pairs(MOTORS) do
			total += 1
			if not (a.motors[key] and a.motors[key].Parent) then
				a.motors[key] = nil
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("Motor6D") and d.Name == motorName then
						a.motors[key] = d
						break
					end
				end
			end
			if a.motors[key] then found += 1 end
		end
		a.complete = found == total
		a.missing = false
		for key in pairs(REQUIRED) do
			if not a.motors[key] then a.missing = true end
		end
	end

	local function wantLoop()
		local name = model:GetAttribute("Clip")
		return (type(name) == "string" and SeagullAnimator.has(name)) and name or "Idle"
	end

	function a.step(dt)
		if a.missing or not a.complete then
			a.rescanT -= dt
			if a.rescanT <= 0 then
				a.rescanT = 1
				rescan()
			end
			if a.missing then return end
		end
		if not a.anim then
			local scale = model:GetAttribute("RigScale")
			if type(scale) ~= "number" then return end -- атрибут ещё не доехал
			a.anim = SeagullAnimator.new(a.motors, scale)
			a.lastOnceT = model:GetAttribute("ClipOnceT") -- разовый, сыгранный до нашего прихода, не повторяем
			a.anim:play(wantLoop(), 0)
		end

		local onceT = model:GetAttribute("ClipOnceT")
		if onceT ~= a.lastOnceT then
			a.lastOnceT = onceT
			local name = model:GetAttribute("ClipOnce")
			if type(name) == "string" and SeagullAnimator.has(name) then
				a.onceActive = true
				a.anim:play(name, 0.08)
			end
		end
		if not a.onceActive then
			-- скорость цикла задаёт сервер (ClipSpeed): озирание — тот же Idle, но медленно
			local want = wantLoop()
			local speed = (want == "Idle") and model:GetAttribute("ClipSpeed") or 1
			if type(speed) ~= "number" then speed = 1 end
			if a.anim.name ~= want then
				a.anim:play(want, 0.35, speed)
			else
				a.anim.speed = speed
			end
		end

		a.anim:step(dt)
		if a.onceActive and a.anim.finished then
			a.onceActive = false -- разовый доиграл: вернуть цикл (у трупа это «Dead» — держит последний кадр)
			a.anim:play(wantLoop(), 0.15)
		end
	end

	attached[model] = a
end

local function detach(model)
	attached[model] = nil
end

for _, m in ipairs(CollectionService:GetTagged(TAG)) do attach(m) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(attach)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(detach)

-- Transform читает физика: пишем перед её шагом
RunService.PreSimulation:Connect(function(dt)
	for model, a in pairs(attached) do
		if not model:IsDescendantOf(workspace) then
			attached[model] = nil
		else
			a.step(dt)
		end
	end
end)

-- ⚠️ СИДЯЩУЮ ПТИЦУ ВЕДЁТ КЛИЕНТ (см. setPerch в SeagullAI). Плот качается, серверная
-- позиция приходит рывками — поэтому корень ставится здесь, каждый кадр, от детали, на
-- которой чайка сидит: той самой, что клиент уже видит плавно. Пока PerchPart пуст
-- (полёт, посадка, взлёт, падение) — не трогаем, птицу ведёт сервер. На пугале её возит
-- ScarecrowSway, там PerchPart не ставится.
RunService.PreRender:Connect(function()
	for model in pairs(attached) do
		local ref = model:FindFirstChild("PerchPart")
		local part = ref and ref.Value
		local rel = model:GetAttribute("PerchRel")
		if part and typeof(rel) == "CFrame" and part:IsDescendantOf(workspace) then
			local root = model.PrimaryPart
			if root then
				root.CFrame = part.CFrame * rel
			end
		end
	end
end)
