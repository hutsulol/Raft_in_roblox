local jelly = script.Parent

local function getCF(obj)
	if obj:IsA("Model") then
		return obj:GetPivot()
	elseif obj:IsA("BasePart") then -- Part / UnionOperation / MeshPart
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

-- Один раз повернуть на бок
local cf = getCF(jelly)
cf = cf * CFrame.Angles(math.rad(-90), 0, 0) -- основная ось, как у рыбы
setCF(jelly, cf)