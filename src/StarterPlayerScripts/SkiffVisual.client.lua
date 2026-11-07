--[[
	РЫБАЦКАЯ ЛОДКА: ГЛАДКАЯ КАРТИНКА НА КЛИЕНТЕ.

	Сервер публикует только СОСТОЯНИЕ лодки (откуда, куда, когда вышла — атрибуты
	модели) и переставляет детали редко. Положение по этому состоянию клиент
	считает сам КАЖДЫЙ КАДР по общим часам — формула одна на всех (модуль
	SkiffMotion), поэтому расхождения с сервером нет, а ход получается идеально
	ровным: рывки репликации, от которых тряслась и лодка, и стоящий на ней
	игрок, исчезают как явление.

	Здесь же переносим игрока по палубе — ТЕМ ЖЕ сдвигом и В ТОМ ЖЕ кадре, что и
	саму лодку. Порядок важен: иначе игрок и палуба разъезжаются на кадр, и это
	снова читается как дрожь.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local Motion = require(ReplicatedStorage:WaitForChild("SkiffMotion"))

local player = Players.LocalPlayer

local LIVE_NAME = "Boat_Skiff_Live"
local HULL_NAME = "boat_skiff"
local CHEF_NAME = "Boat_Skiff_Chef"
local FLOOR_RAY = -8    -- вниз от корня: ноги + запас на качку
local REACH     = 90

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = true

-- слепок модели: относительные позиции деталей снимаем один раз
local views = setmetatable({}, { __mode = "k" })

local function buildView(model)
	local hull = model:FindFirstChild(HULL_NAME, true)
	if not hull or not hull:IsA("BasePart") then return nil end

	local chef = model:FindFirstChild(CHEF_NAME, true)
	-- Текущее положение лодки по её же состоянию: относительные смещения
	-- считаем ОТ НЕГО, а не от произвольного кадра, — тогда клиентская и
	-- серверная раскладка совпадают до студа.
	local now = Workspace:GetServerTimeNow()
	local origin = Motion.originCF(model, now)
	if not origin then return nil end

	local v = { model = model, hull = hull, chef = chef, parts = {} }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not (chef and d:IsDescendantOf(chef)) then
			table.insert(v.parts, { part = d, rel = origin:ToObjectSpace(d.CFrame) })
		end
	end
	if chef then
		v.rig = Motion.buildRig(chef)
	end
	return v
end

local function carryPlayer(model, delta, oldOrigin)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if not (hrp and hum and hum.Health > 0) then return end
	if (hrp.Position - oldOrigin.Position).Magnitude > REACH then return end

	rayParams.FilterDescendantsInstances = { model }
	if not Workspace:Raycast(hrp.Position, Vector3.new(0, FLOOR_RAY, 0), rayParams) then return end

	-- ⚠️ ТОЛЬКО ГОРИЗОНТАЛЬ И РЫСКАНИЕ. Крен и подъём на волне — это вращение
	-- вокруг центра лодки, и на удалении от него оно швыряло бы игрока
	-- вверх-вниз. Высоту держит обычная коллизия палубы.
	local step = Vector3.new(delta.pos.X, 0, delta.pos.Z)
	local spin = delta.yaw
	local pivot = Vector3.new(oldOrigin.Position.X, hrp.Position.Y, oldOrigin.Position.Z)
	local rot = CFrame.Angles(0, spin, 0)
	local newPos = pivot + rot:VectorToWorldSpace(hrp.Position - pivot) + step
	hrp.CFrame = CFrame.new(newPos) * rot * (hrp.CFrame - hrp.CFrame.Position)
end

local function yawOf(cf)
	local lv = cf.LookVector
	return math.atan2(-lv.X, -lv.Z)
end

RunService.RenderStepped:Connect(function()
	local now = Workspace:GetServerTimeNow()

	for _, model in ipairs(Workspace:GetChildren()) do
		if model:IsA("Model") and model.Name == LIVE_NAME then
			local v = views[model]
			if not v then
				v = buildView(model)
				if v then views[model] = v end
			end
			if v and v.hull.Parent then
				local origin = Motion.originCF(model, now)
				if origin then
					-- сдвиг за кадр — для переноса игрока
					local prev = v.lastOrigin
					if prev then
						local d = {
							pos = origin.Position - prev.Position,
							yaw = (function()
								local a = yawOf(origin) - yawOf(prev)
								return math.atan2(math.sin(a), math.cos(a))
							end)(),
						}
						carryPlayer(model, d, prev)
					end
					v.lastOrigin = origin

					for _, e in ipairs(v.parts) do
						if e.part.Parent then e.part.CFrame = origin * e.rel end
					end
					if v.rig and v.chef and v.chef.Parent then
						local chefRel = model:GetAttribute("ChefRel")
						if chefRel then
							Motion.applyRig(v.rig, origin * chefRel, Motion.chefPose(model, now))
						end
					end
				end
			end
		end
	end
end)
