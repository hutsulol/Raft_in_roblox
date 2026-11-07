-- MuzzleFX.lua  (ReplicatedStorage, shared module)
-- Общий дульный залп для стволов: огненная вспышка + разлетающиеся искры + дым наружу.
-- Серверный (видят все игроки): эмиттеры на дуле включаются очень коротким окном
-- (server :Emit НЕ реплицируется, а enabled-Rate — да).
--
-- Использование:  require(ReplicatedStorage.MuzzleFX).burst(origin, dir)
--   origin — мировая точка дула (Vector3), dir — направление выстрела (Vector3).

local Debris = game:GetService("Debris")

local MuzzleFX = {}

-- opts.smoke = false → без дыма (напр. револьвер). По умолчанию дым есть (пушка и т.п.)
-- opts.scale — размер залпа (1 = пушка). Ручному стволу нужен куда меньший:
--   у револьвера scale ≈ 0.35, иначе вспышка размером с пушечную.
function MuzzleFX.burst(origin, dir, opts)
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or dir.Magnitude < 1e-4 then return end
	dir = dir.Unit
	local withSmoke = not (opts and opts.smoke == false)
	local s = (opts and tonumber(opts.scale)) or 1

	local holder = Instance.new("Part")
	holder.Name = "MuzzleFX"
	holder.Anchored = true; holder.CanCollide = false; holder.CanQuery = false; holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.lookAt(origin, origin + dir) -- Front (-Z) смотрит вдоль dir
	holder.Parent = workspace

	-- короткая вспышка света
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 180, 95); light.Brightness = 8; light.Range = 17 * s
	light.Parent = holder
	task.delay(0.06, function() light.Enabled = false end)

	-- ОГОНЬ — короткая оранжевая вспышка из дула
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 205, 120), Color3.fromRGB(255, 95, 25))
	fire.LightEmission = 1
	fire.LightInfluence = 0
	fire.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.6 * s),
		NumberSequenceKeypoint.new(1, 0.2 * s),
	})
	fire.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	fire.Lifetime = NumberRange.new(0.05, 0.11)
	fire.Rate = 350
	fire.Speed = NumberRange.new(7 * s, 13 * s)
	fire.SpreadAngle = Vector2.new(20, 20)
	fire.Rotation = NumberRange.new(0, 360)
	fire.EmissionDirection = Enum.NormalId.Front
	fire.Parent = holder

	-- ИСКРЫ — яркие, летят наружу веером, живут мгновение
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 232, 150), Color3.fromRGB(255, 140, 40))
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8 * s),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new(0.1)
	sparks.Lifetime = NumberRange.new(0.08, 0.22)
	sparks.Rate = 600
	sparks.Speed = NumberRange.new(30 * s, 65 * s)
	sparks.SpreadAngle = Vector2.new(28, 28)
	sparks.Acceleration = Vector3.new(0, -35, 0) -- искры чуть падают
	sparks.EmissionDirection = Enum.NormalId.Front
	sparks.Parent = holder

	-- пыхнули огнём+искрами и выключили (очень короткий залп)
	task.delay(0.05, function() fire.Enabled = false; sparks.Enabled = false end)

	-- ДЫМ выходит наружу из дула: короткая пыхтелка (у револьвера отключён)
	if withSmoke then
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(130, 130, 135), Color3.fromRGB(60, 60, 65))
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.15, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		smoke.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.3 * s),
			NumberSequenceKeypoint.new(1, 4.5 * s),
		})
		smoke.Lifetime = NumberRange.new(0.6, 1.1)
		smoke.Rate = 140
		smoke.Speed = NumberRange.new(10 * s, 16 * s)
		smoke.SpreadAngle = Vector2.new(14, 14)
		smoke.Acceleration = Vector3.new(0, 5, 0)
		smoke.LightEmission = 0.1
		smoke.EmissionDirection = Enum.NormalId.Front
		smoke.Parent = holder
		task.delay(0.12, function() smoke.Enabled = false end)
	end

	Debris:AddItem(holder, 1.6)
end

return MuzzleFX
