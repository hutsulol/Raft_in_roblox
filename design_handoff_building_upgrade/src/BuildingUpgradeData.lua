-- ReplicatedStorage/BuildingUpgradeData (ModuleScript)
-- Уровни: множитель прибыли и цена перехода на следующий уровень.

local M = {}

M.Mults = { [0] = 1, [1] = 1.5, [2] = 2, [3] = 3, [4] = 4.5, [5] = 6 }
M.Costs = { [0] = 500, [1] = 1500, [2] = 4000, [3] = 10000, [4] = 25000 } -- цена с уровня N на N+1
M.MaxLevel = 5
M.BuildTime = 2 -- секунд

function M.FormatMult(m: number): string
	local s = (m % 1 == 0) and tostring(math.floor(m)) or string.format("%.1f", m)
	return "×" .. s:gsub("%.", ",")
end

function M.FormatNum(n: number): string
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", ""))
end

return M
