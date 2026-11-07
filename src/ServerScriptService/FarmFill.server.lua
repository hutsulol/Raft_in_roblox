--[[
	FarmFill.server.lua — уровень воды в корыте и шерсти в ящике.

	В моделях Raft_farm_trough, Raft_wool_bin и Raft_fishing_spot каждый уровень заполнения лежит
	отдельным мешем (как стадии грядки в Raft_farm_block):
		raft_farm_trough_water_1..3      вода: треть, две трети, полное
		raft_wool_bin_wool_1..4          шерсть: четверть … с горкой
		raft_fishing_catch_1..4          улов: пара рыбин … через край
	Этот скрипт показывает ОДИН меш по атрибутам модели, остальные прячет:
		корыто   Water / WaterMax   (их уже пишет RaftFarmService; WaterMax по умолчанию 100)
		ящик     Wool  / WoolMax    (WoolMax по умолчанию 16)
		улов     Fish  / FishMax    (FishMax по умолчанию 12)
	Ноль — всё спрятано; любое количество больше нуля — хотя бы первый уровень.

	Меши уровней никогда не сталкиваются и не ловят лучи: вода и шерсть — картинка,
	кликают и упираются в само корыто и сам ящик. Ничего не создаётся и не
	двигается, меняется только прозрачность — сборку плота это не трясёт.

	Класть в ServerScriptService. Из других скриптов: _G.SetFarmFill(model, stage).
]]

local LOG = "[FarmFill]"

-- имя модели → префикс мешей уровня, атрибут количества, атрибут максимума, максимум по умолчанию
local KINDS = {
	Raft_farm_trough = { prefix = "raft_farm_trough_water_", amount = "Water", max = "WaterMax", default = 100 },
	Raft_wool_bin    = { prefix = "raft_wool_bin_wool_",     amount = "Wool",  max = "WoolMax",  default = 16 },
	-- рыбацкий уголок: улов в ящике (Raft_fishing_spot, четыре уровня)
	Raft_fishing_spot = { prefix = "raft_fishing_catch_",    amount = "Fish",  max = "FishMax",  default = 12 },
}

local bound = setmetatable({}, { __mode = "k" })

local function stages(model, prefix)
	local list = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and string.sub(d.Name, 1, #prefix) == prefix then
			local n = tonumber(string.sub(d.Name, #prefix + 1))
			if n then list[n] = d end
		end
	end
	return list
end

local function show(model, kind, stage)
	for n, part in pairs(stages(model, kind.prefix)) do
		-- исходную прозрачность помним: воде её ставят около 0.25
		if part:GetAttribute("ShownTransparency") == nil then
			part:SetAttribute("ShownTransparency", part.Transparency < 1 and part.Transparency or 0)
		end
		local on = n == stage
		part.Transparency = on and part:GetAttribute("ShownTransparency") or 1
		part.CastShadow = on
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
	if model:GetAttribute("FillStage") ~= stage then model:SetAttribute("FillStage", stage) end
end

local function refresh(model, kind)
	local count = 0
	for n in pairs(stages(model, kind.prefix)) do count = math.max(count, n) end
	if count == 0 then return end
	local have = tonumber(model:GetAttribute(kind.amount)) or 0
	local max = tonumber(model:GetAttribute(kind.max)) or kind.default
	local stage = 0
	if have > 0 and max > 0 then
		stage = math.clamp(math.ceil(have / max * count - 1e-6), 1, count)
	end
	show(model, kind, stage)
end

local function bind(model)
	local kind = KINDS[model.Name]
	if not kind or bound[model] then return end
	bound[model] = true
	refresh(model, kind)
	model:GetAttributeChangedSignal(kind.amount):Connect(function() refresh(model, kind) end)
	model:GetAttributeChangedSignal(kind.max):Connect(function() refresh(model, kind) end)
	-- меши могут доехать после самой модели (клон, загрузка сохранения)
	model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then task.defer(refresh, model, kind) end
	end)
end

local function discover(inst)
	if inst:IsA("Model") and KINDS[inst.Name] then
		task.defer(bind, inst)
	end
end

for _, d in ipairs(workspace:GetDescendants()) do discover(d) end
workspace.DescendantAdded:Connect(discover)

-- показать конкретный уровень руками (0 — пусто), в обход атрибутов количества
_G.SetFarmFill = function(model, stage)
	local kind = model and KINDS[model.Name]
	if not kind then
		warn(LOG .. " не корыто и не ящик шерсти: " .. tostring(model))
		return
	end
	show(model, kind, math.max(0, math.floor(tonumber(stage) or 0)))
end

print(LOG .. " ready")
