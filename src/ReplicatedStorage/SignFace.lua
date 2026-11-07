--[[
	Куда вешать SurfaceGui на плоскую табличку.

	⚠️ Front НЕ ПОДХОДИТ.
	Как деталь развёрнута внутри модели, заранее неизвестно, а постройку ещё и
	крутят при установке. Прибьёшь надпись к Front — на половине поворотов она
	окажется с изнанки. Берём самую тонкую ось детали (это и есть плоскость
	экрана) и из двух её сторон ту, что смотрит наружу от центра постройки.

	Общий для вышки и дома: правило одно, и расходиться двум копиям незачем.
]]

local SignFace = {}

function SignFace.of(part, model)
	local s = part.Size
	local axis, outward, inward
	if s.Z <= s.X and s.Z <= s.Y then
		axis, outward, inward = Vector3.new(0, 0, -1), Enum.NormalId.Front, Enum.NormalId.Back
	elseif s.X <= s.Y then
		axis, outward, inward = Vector3.new(1, 0, 0), Enum.NormalId.Right, Enum.NormalId.Left
	else
		axis, outward, inward = Vector3.new(0, 1, 0), Enum.NormalId.Top, Enum.NormalId.Bottom
	end
	local normal = part.CFrame:VectorToWorldSpace(axis)
	local centre = model and model:GetPivot().Position or part.Position
	local fromCentre = part.Position - centre
	return (fromCentre:Dot(normal) >= 0) and outward or inward
end

return SignFace
