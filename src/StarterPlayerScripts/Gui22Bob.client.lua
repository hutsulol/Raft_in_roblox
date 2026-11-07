-- Gui22Bob.client.lua
-- Плавающий индикатор по системе тегов.
--   • На модель вешается тег "Gui22".
--   • Внутри ищется BillboardGui, и плавно качается его StudsOffset (вверх на
--     0.3 студа и обратно, ≈2 сек на цикл).
-- ВАЖНО: качаем СВОЙСТВО GUI (StudsOffset), а НЕ CFrame/Anchored парта. Раньше
-- скрипт ставил part.Anchored = true и двигал CFrame — но если этот парт
-- приварен к плоту (рюкзак на плоту), заякоренный парт замораживает ВСЮ сварную
-- сборку плота на клиенте (сервер при этом плот двигает → рассинхрон, плот
-- «стоит»). StudsOffset — чистая косметика, физику не трогает, плот плывёт.

local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")

local TAG        = "Gui22" -- тег на модели
local RISE       = 0.3     -- на сколько студов подниматься (по StudsOffset)
local HALF_CYCLE = 1       -- секунд на пол-цикла (вверх 1с + вниз 1с = 2с)

local TWEEN_INFO = TweenInfo.new(
	HALF_CYCLE,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.InOut,
	-1,   -- повтор бесконечно
	true  -- reverses: автоматически возвращает в нижнюю точку
)

-- [model] = true (ожидание GUI)  ИЛИ  { tween, gui, base }
local active = {}

-- Найти BillboardGui внутри модели (или сама модель, если это он).
local function findGui(model)
	if model:IsA("BillboardGui") then
		return model
	end
	return model:FindFirstChildWhichIsA("BillboardGui", true)
end

-- Остановить качание и вернуть индикатор в нижнюю точку.
local function stop(model)
	local rec = active[model]
	if rec == nil then return end
	active[model] = nil
	if type(rec) == "table" then
		if rec.tween then rec.tween:Cancel() end
		if rec.gui and rec.gui.Parent then
			rec.gui.StudsOffset = rec.base
		end
	end
end

-- Запустить качание для модели (GUI может появиться чуть позже — подождём).
local function start(model)
	if active[model] ~= nil then return end
	active[model] = true -- занимаем слот, чтобы не стартовать дважды

	task.spawn(function()
		local gui
		for _ = 1, 30 do -- до ~3 сек ждём появления GUI (стриминг)
			if not CollectionService:HasTag(model, TAG) or model.Parent == nil then
				if active[model] == true then active[model] = nil end
				return
			end
			gui = findGui(model)
			if gui then break end
			task.wait(0.1)
		end
		-- Слот мог быть снят (untag/destroy) пока ждали, или GUI так и не нашёлся.
		if gui == nil or active[model] ~= true then
			if active[model] == true then active[model] = nil end
			return
		end

		local base = gui.StudsOffset -- нижняя (исходная) точка
		local tween = TweenService:Create(gui, TWEEN_INFO, {
			StudsOffset = base + Vector3.new(0, RISE, 0),
		})
		active[model] = { tween = tween, gui = gui, base = base }
		tween:Play()
	end)
end

-- Уже размеченные модели + те, что появятся/разметятся позже.
for _, model in ipairs(CollectionService:GetTagged(TAG)) do
	start(model)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(start)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(stop)
