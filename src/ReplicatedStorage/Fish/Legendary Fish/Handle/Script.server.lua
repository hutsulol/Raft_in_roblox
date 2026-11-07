local fish = script.Parent

local function getCF(obj)
	if obj:IsA("Model") then
		return obj:GetPivot()
	elseif obj:IsA("BasePart") then
		return obj.CFrame
	end
	error("script.Parent должен быть Model или BasePart")
end

local function setCF(obj, cf)
	if obj:IsA("Model") then
		obj:PivotTo(cf)
	else
		obj.CFrame = cf
	end
end

local shift = Vector3.new(0.05, 0, 0)
local minPause, maxPause = 0.4, 1.6
local minBursts, maxBursts = 2, 6

-- 1 раз: кладём рыбу на бок (исправленная ось)
do
	local cf = getCF(fish)
	cf = cf * CFrame.Angles(math.rad(-90), 0, 0) -- было по неверной оси
	setCF(fish, cf)
end

while true do
	wait(math.random() * (maxPause - minPause) + minPause)

	local bursts = math.random(minBursts, maxBursts)
	local dt = 0.09
	local accel = 0.82

	for i = 1, bursts do
		local ang = math.rad(math.random(8, 18))
		local cf = getCF(fish)

		cf = cf + shift
		cf = cf * CFrame.Angles(0, ang, 0)
		setCF(fish, cf)
		wait(dt)

		cf = getCF(fish)
		cf = cf - shift
		cf = cf * CFrame.Angles(0, -ang, 0)
		setCF(fish, cf)
		wait(dt)

		dt = math.max(0.02, dt * accel)
	end
end