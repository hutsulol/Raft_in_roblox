--[[
	FarmBlock — переключатель вариантов блока фермы Raft_farm_block. ModuleScript, ReplicatedStorage.

	В одной модели лежит ВСЁ сразу, каждый вариант — свой меш:
		raft_farm_soil / raft_farm_soil_cover / raft_farm_soil_grass     три стадии грядки
		raft_farm_soil_cover_blades / raft_farm_soil_grass_blades        поросль и трава этих стадий —
		                                                                  отдельно, БЕЗ коллизии: по ним ходят
		raft_farm_fence_<ребро>                                           забор на каждом из 8 рёбер
		raft_farm_gate_<ребро> / …_hinge / …_leaf                         калитка на каждом из 8 рёбер
	Рёбра: n1 n2 e1 e2 s1 s2 w1 w2 — сторона блока и какая из двух её клеток.

	Игра показывает нужное, остальное спрятано (прозрачность 1, без коллизии, лучей и касаний).
	Состояние лежит АТРИБУТАМИ на модели — их и сохранять:
		Soil      "bare" | "cover" | "grass" | "none"
		Edge_n1 … Edge_w2   "fence" | "gate" | "none"

	Звать с сервера:
		local FarmBlock = require(ReplicatedStorage.FarmBlock)
		FarmBlock.init(model)                     -- один раз после установки: земля, забор кругом, калитка на n2
		FarmBlock.setSoil(model, "grass")         -- стадия грядки
		FarmBlock.setEdge(model, "w1", "none")    -- убрать забор слева, первая клетка
		FarmBlock.setEdge(model, "w2", "none")
		FarmBlock.setEdge(model, "s1", "gate")    -- калитка на южной стороне
		FarmBlock.setSide(model, "w", "none")     -- обе клетки стороны сразу
		FarmBlock.apply(model)                    -- привести модель к атрибутам (после загрузки сохранения)

	Можно и без модуля: просто поменять атрибут в скрипте или в Studio — модуль следит за
	атрибутами блоков, которым делали init/apply, и сам перестроит вид.
]]

local FarmBlock = {}

FarmBlock.EDGES = { "n1", "n2", "e1", "e2", "s1", "s2", "w1", "w2" }
FarmBlock.SOILS = { bare = "raft_farm_soil", cover = "raft_farm_soil_cover", grass = "raft_farm_soil_grass" }
-- что растёт на стадии: видно вместе с её землёй, но сквозь это ходят и кликают.
-- Пока трава была одним мешем с землёй, грядка сталкивалась по высоте травы.
FarmBlock.GROWTH = { cover = "raft_farm_soil_cover_blades", grass = "raft_farm_soil_grass_blades" }
FarmBlock.DEFAULT_GATE = "n2"

local watched = setmetatable({}, { __mode = "k" })

local function index(model)
	local byName = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 10) == "raft_farm_" then
			byName[d.Name] = d
		end
	end
	return byName
end

-- solid = false: деталь только рисуется (трава) — ни коллизии, ни лучей, ни касаний
local function show(part, on, solid)
	if not part then return end
	local hard = on and solid ~= false
	-- исходную прозрачность помним: у детали она могла быть не ноль
	if part:GetAttribute("ShownTransparency") == nil then
		part:SetAttribute("ShownTransparency", part.Transparency < 1 and part.Transparency or 0)
	end
	part.Transparency = on and part:GetAttribute("ShownTransparency") or 1
	part.CanCollide = hard
	part.CanQuery = hard
	part.CanTouch = hard
	part.CastShadow = on
	part:SetAttribute("FarmHidden", not on) -- GateController по нему прячет подсказку у скрытой калитки
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			d.Enabled = on and part:GetAttribute("GateLocked") ~= true
		elseif d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") then
			-- ничего: прозрачность детали прячет и их
		end
	end
end

function FarmBlock.apply(model)
	local parts = index(model)
	local soil = model:GetAttribute("Soil") or "bare"
	for key, name in pairs(FarmBlock.SOILS) do
		show(parts[name], key == soil)
	end
	for key, name in pairs(FarmBlock.GROWTH) do
		show(parts[name], key == soil, false)   -- в старой модели (трава в одном меше с землёй) этих деталей нет
	end
	for _, edge in ipairs(FarmBlock.EDGES) do
		local kind = model:GetAttribute("Edge_" .. edge) or "none"
		show(parts["raft_farm_fence_" .. edge], kind == "fence")
		local gate = kind == "gate"
		show(parts["raft_farm_gate_" .. edge], gate)
		show(parts["raft_farm_gate_" .. edge .. "_hinge"], gate)
		local leaf = parts["raft_farm_gate_" .. edge .. "_leaf"]
		show(leaf, gate)
		if leaf and not gate and leaf:GetAttribute("GateOpen") == true and _G.SetGate then
			_G.SetGate(leaf, false) -- спрятанная калитка закрывается: покажут снова — будет закрытой
		end
	end
	if not watched[model] then
		watched[model] = true
		model.AttributeChanged:Connect(function(name)
			if name == "Soil" or string.sub(name, 1, 5) == "Edge_" then
				FarmBlock.apply(model)
			end
		end)
	end
end

function FarmBlock.init(model)
	if model:GetAttribute("Soil") == nil then model:SetAttribute("Soil", "bare") end
	for _, edge in ipairs(FarmBlock.EDGES) do
		if model:GetAttribute("Edge_" .. edge) == nil then
			model:SetAttribute("Edge_" .. edge, edge == FarmBlock.DEFAULT_GATE and "gate" or "fence")
		end
	end
	FarmBlock.apply(model)
end

function FarmBlock.setSoil(model, stage)
	assert(stage == "none" or FarmBlock.SOILS[stage], "FarmBlock.setSoil: стадия bare | cover | grass | none")
	model:SetAttribute("Soil", stage)
	FarmBlock.apply(model)
end

function FarmBlock.setEdge(model, edge, kind)
	assert(table.find(FarmBlock.EDGES, edge), "FarmBlock.setEdge: ребро n1 n2 e1 e2 s1 s2 w1 w2")
	assert(kind == "fence" or kind == "gate" or kind == "none", "FarmBlock.setEdge: fence | gate | none")
	if model:GetAttribute("Edge_" .. edge) == kind then return end
	model:SetAttribute("Edge_" .. edge, kind)
	FarmBlock.apply(model)
end

function FarmBlock.setSide(model, side, kind)
	FarmBlock.setEdge(model, side .. "1", kind)
	FarmBlock.setEdge(model, side .. "2", kind)
end

function FarmBlock.getEdge(model, edge)
	return model:GetAttribute("Edge_" .. edge) or "none"
end

-- это блок фермы? (по наличию любой из трёх грядок)
function FarmBlock.is(model)
	if not (model and model:IsA("Model")) then return false end
	for _, name in pairs(FarmBlock.SOILS) do
		if model:FindFirstChild(name, true) then return true end
	end
	return false
end

return FarmBlock
