--[[
	FarmFence.server.lua — забор блока фермы сам подстраивается под соседние блоки.
	НЕОБЯЗАТЕЛЬНЫЙ скрипт: он всего лишь зовёт FarmBlock.setEdge(). Хотите переключать
	забор своими скриптами — не ставьте его или выключите блоку (AutoFence = false).

	Работает с моделью Raft_farm_block (в ней забор и калитка есть на всех восьми рёбрах,
	нужное показывается, лишнее спрятано). Ничего не создаёт и не удаляет — только
	переключает видимость, поэтому сборку плота не трясёт.

	Правила
	  * У блока 2×2 восемь рёбер клеток. Ребро ОБЩЕЕ, если за ним, в полуклетке наружу,
	    лежит другая грядка. Блоки можно ставить вровень и со сдвигом на клетку.
	  * Общее ребро — пусто, наружное — забор.
	  * Калитка одна на блок: на «родном» ребре (атрибут GateHome, по умолчанию n2), а если
	    оно стало общим — на ближайшем наружном. Блок, окружённый со всех сторон, —
	    без забора и без калитки.
	  * Соседом считается любая грядка: Raft_farm_block, Raft_soil*, Raft_soil*_fenced.
	  * Состояние выводится из расположения блоков: пересчёт при постройке/сносе и раз в
	    секунду. Результат пишется в атрибуты Edge_* модели (см. FarmBlock).

	Атрибуты на модели блока:
	  AutoFence  false — этот блок не трогать (забором управляете сами)
	  GateHome   "n1".."w2" — где калитке стоять, пока это ребро наружное; "none" — блок без калитки
	Оси не предполагаются: «вверх» — тонкая ось грядки, «наружу» — от центра грядки к секции.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FarmBlock = require(ReplicatedStorage:WaitForChild("FarmBlock"))

local LOG = "[FarmFence]"
local RECHECK = 1.0
local SOIL_NAMES = {
	raft_farm_soil = true, raft_farm_soil_cover = true, raft_farm_soil_grass = true,
	raft_soil = true, raft_soil_cover = true, raft_soil_grass = true,
}

local blocks = {} -- модель блока -> { soil = деталь грядки (любая из трёх), edges = { n1 = деталь забора, … } }
local plain = {} -- грядки-соседи без переключаемого забора: деталь -> true
local dirty = true

local function axes(soil)
	local s, cf = soil.Size, soil.CFrame
	local a = { { cf.XVector, s.X }, { cf.YVector, s.Y }, { cf.ZVector, s.Z } }
	table.sort(a, function(p, q) return p[2] < q[2] end) -- тонкая ось — вертикаль
	local up = a[1][1]
	if up.Y < 0 then up = -up end
	return up, a[2][1], a[3][1], (a[2][2] + a[3][2]) / 2
end

local function register(soil)
	local model = soil.Parent
	if not model then return end
	if string.sub(soil.Name, 1, 10) ~= "raft_farm_" then
		plain[soil] = true
		dirty = true
		soil.AncestryChanged:Connect(function()
			if not soil:IsDescendantOf(workspace) then plain[soil] = nil; dirty = true end
		end)
		return
	end
	if blocks[model] then return end
	local edges = {}
	for _, e in ipairs(FarmBlock.EDGES) do
		edges[e] = model:FindFirstChild("raft_farm_fence_" .. e, true)
	end
	-- землю для замеров берём «голую»: у варианта с травой габарит раздут травинками
	local ref = model:FindFirstChild("raft_farm_soil", true) or soil
	blocks[model] = { soil = ref, edges = edges }
	FarmBlock.init(model)
	dirty = true
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then blocks[model] = nil; dirty = true end
	end)
	print(LOG .. " блок " .. model:GetFullName())
end

local function occupied(q, exceptModel)
	local function inside(soil)
		local up, a1, a2, side = axes(soil)
		local d = q - soil.Position
		return math.abs(d:Dot(a1)) < side * 0.49 and math.abs(d:Dot(a2)) < side * 0.49 and math.abs(d:Dot(up)) < side * 0.5
	end
	for model, b in pairs(blocks) do
		if model ~= exceptModel and b.soil:IsDescendantOf(workspace) and inside(b.soil) then return true end
	end
	for soil in pairs(plain) do
		if soil:IsDescendantOf(workspace) and inside(soil) then return true end
	end
	return false
end

local function refresh()
	for model, b in pairs(blocks) do
		if model:GetAttribute("AutoFence") ~= false and b.soil:IsDescendantOf(workspace) then
			local up, a1, a2, side = axes(b.soil)
			local tile = side / 2
			local want, outer, pos = {}, {}, {}
			for _, e in ipairs(FarmBlock.EDGES) do
				local part = b.edges[e]
				if part then
					local d = part.Position - b.soil.Position
					local c1, c2 = d:Dot(a1), d:Dot(a2)
					local n = (math.abs(c1) >= math.abs(c2)) and a1 * math.sign(c1) or a2 * math.sign(c2)
					pos[e] = part.Position
					local shared = occupied(part.Position + n * (tile * 0.55), model)
					want[e] = shared and "none" or "fence"
					if not shared then table.insert(outer, e) end
				end
			end
			local home = model:GetAttribute("GateHome") or FarmBlock.DEFAULT_GATE
			if home ~= "none" and pos[home] and #outer > 0 then
				local at = home
				if want[home] == "none" then
					local best
					for _, e in ipairs(outer) do
						local dist = (pos[e] - pos[home]).Magnitude
						if not best or dist < best then best, at = dist, e end
					end
				end
				want[at] = "gate"
			end
			for e, kind in pairs(want) do
				if FarmBlock.getEdge(model, e) ~= kind then
					FarmBlock.setEdge(model, e, kind)
				end
			end
		end
	end
end

local function discover(inst)
	if inst:IsA("BasePart") and SOIL_NAMES[inst.Name] then
		-- дать модели доехать целиком и встать на место (стройка двигает её после вставки)
		task.delay(0.4, function()
			if inst:IsDescendantOf(workspace) then register(inst) end
		end)
	end
end

for _, d in ipairs(workspace:GetDescendants()) do discover(d) end
workspace.DescendantAdded:Connect(discover)

task.spawn(function()
	while true do
		local ok, err = pcall(refresh)
		if not ok then warn(LOG .. " " .. tostring(err)) end
		dirty = false
		local waited = 0
		while waited < RECHECK and not dirty do
			waited += task.wait(0.1)
		end
	end
end)

_G.RefreshFarmFence = function() dirty = true end
print(LOG .. " ready")
