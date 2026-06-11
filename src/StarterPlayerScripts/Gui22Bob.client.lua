-- Gui22Bob.client.lua
-- Плавающий индикатор по системе тегов.
--   • На модель вешается тег "Gui22".
--   • Внутри ищется парт с именем "BillboardGui".
--   • Его текущее положение = НИЖНЯЯ точка. Парт плавно поднимается на 0.3 студа
--     вверх и возвращается обратно — зацикленно, не быстро (≈2 сек на полный цикл).
-- Чистая косметика: крутится на клиенте через TweenService, без нагрузки на сеть.

local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")

local TAG        = "Gui22"        -- тег на модели
local PART_NAME  = "BillboardGui" -- какой парт качаем
local RISE       = 0.3            -- на сколько студов подниматься
local HALF_CYCLE = 1             -- секунд на пол-цикла (вверх 1с + вниз 1с = 2с)

-- Бесконечный твин с возвратом: вверх (Sine In/Out) → вниз → ...
local TWEEN_INFO = TweenInfo.new(
	HALF_CYCLE,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.InOut,
	-1,   -- повтор бесконечно
	true  -- reverses: автоматически возвращает в нижнюю точку
)

-- [model] = true (ожидание парта)  ИЛИ  { tween, part, base }
local active = {}

-- Найти внутри модели парт-носитель BillboardGui (или сама модель, если это он).
local function findPart(model)
	if model:IsA("BasePart") and model.Name == PART_NAME then
		return model
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == PART_NAME then
			return d
		end
	end
	return nil
end

-- Остановить качание и вернуть парт в нижнюю точку.
local function stop(model)
	local rec = active[model]
	if rec == nil then return end
	active[model] = nil
	if type(rec) == "table" then
		if rec.tween then rec.tween:Cancel() end
		if rec.part and rec.part.Parent then
			rec.part.CFrame = rec.base
		end
	end
end

-- Запустить качание для модели (парт может появиться чуть позже — подождём).
local function start(model)
	if active[model] ~= nil then return end
	active[model] = true -- занимаем слот, чтобы не стартовать дважды

	task.spawn(function()
		local part
		for _ = 1, 30 do -- до ~3 сек ждём появления парта (стриминг)
			if not CollectionService:HasTag(model, TAG) or model.Parent == nil then
				if active[model] == true then active[model] = nil end
				return
			end
			part = findPart(model)
			if part then break end
			task.wait(0.1)
		end
		-- Слот мог быть снят (untag/destroy) пока ждали.
		if part == nil or active[model] ~= true then
			if active[model] == true then active[model] = nil end
			return
		end

		local base = part.CFrame          -- нижняя (исходная) точка
		part.Anchored = true              -- локально, чтобы твин не дрался с физикой
		local tween = TweenService:Create(part, TWEEN_INFO, {
			CFrame = base + Vector3.new(0, RISE, 0),
		})
		active[model] = { tween = tween, part = part, base = base }
		tween:Play()
	end)
end

-- Уже размеченные модели + те, что появятся/разметятся позже.
for _, model in ipairs(CollectionService:GetTagged(TAG)) do
	start(model)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(start)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(stop)
