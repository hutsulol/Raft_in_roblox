--[[
	БУТЫЛКА ДЛЯ ВОДЫ — предмет рюкзака.

	⚠️ БУТЫЛКА — ЭТО ТА ЖЕ «КРУЖКА», ТОЛЬКО ДРУГОЙ МОДЕЛИ.
	Вся механика воды (зачерпнуть из океана, залить в очиститель, набрать чистую,
	выпить, полить грядку) смотрит НЕ на имя тула, а на атрибут CupState. Значит
	новый сосуд не требует ни одной новой ветки: достаточно создать Tool с
	CupState и CupBase — и он немедленно умеет всё то же, что кружка.
	Свой обработчик здесь только один — сборка Tool из модели заказчика.

	⚠️ МОДЕЛЬ ЗАБИРАЕМ ИЗ WORKSPACE В ХРАНИЛИЩЕ.
	Заказчик кладёт новые модели прямо на карту (Item_WaterBottle). Клонировать
	надо из ReplicatedStorage, иначе шаблон так и лежит посреди плота и виден в
	игре. Переносим один раз при загрузке — как это делает кровать.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local MODEL_NAME = "Item_WaterBottle"
local TOOL_NAME  = "WaterBottle"
-- Сколько глотков держит бутылка. У кружки один — бутылка на то и бутылка.
local CHARGES    = 2
-- Иконка в хотбаре. Пустая строка = Roblox нарисует сам меш; свой id можно
-- вписать сюда, и он подхватится без других правок.
local TOOL_ICON  = ""

local function findModel()
	local m = ReplicatedStorage:FindFirstChild(MODEL_NAME)
		or ReplicatedStorage:FindFirstChild(MODEL_NAME, true)
	if m then return m end

	m = Workspace:FindFirstChild(MODEL_NAME) or Workspace:FindFirstChild(MODEL_NAME, true)
	if m then
		m.Parent = ReplicatedStorage
		print(("[Бутылка] модель %s перенесена из Workspace в ReplicatedStorage")
			:format(MODEL_NAME))
		return m
	end
	return nil
end

-- ⚠️ САМАЯ КРУПНАЯ ДЕТАЛЬ СТАНОВИТСЯ HANDLE.
-- Tool держит игрока за деталь с именем Handle, остальные к ней приваривают.
-- Брать первую попавшуюся нельзя: у бутылки три меша (сама бутылка, этикетка,
-- вода внутри), и если ручкой окажется этикетка, предмет повиснет в руке боком.
local function buildTool(model)
	local biggest, bestVol
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if not bestVol or v > bestVol then biggest, bestVol = d, v end
		end
	end
	if not biggest then
		warn("[Бутылка] в модели нет ни одной детали — тул не собрать")
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	if TOOL_ICON ~= "" then tool.TextureId = TOOL_ICON end

	local clone = model:Clone()
	local handle
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.Massless = true
			if d.Name == biggest.Name then handle = d end
		end
	end
	handle = handle or clone:FindFirstChildWhichIsA("BasePart", true)
	if not handle then clone:Destroy() return nil end

	handle.Name = "Handle"
	-- переносим детали в сам Tool и привариваем к ручке: модель-обёртка внутри
	-- Tool не нужна, а сварка нужна — иначе части разлетятся при экипировке
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") and d ~= handle then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = handle, d
			w.Parent = d
		end
	end
	handle.Parent = tool
	for _, d in ipairs(clone:GetChildren()) do
		if d ~= handle then d.Parent = tool end
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") and d.Parent == clone then d.Parent = tool end
	end
	clone:Destroy()

	-- НЕСКОЛЬКО АТРИБУТОВ — И БУТЫЛКА УМЕЕТ ВСЁ, ЧТО КРУЖКА.
	-- ⚠️ ВЫДАЁТСЯ ПОЛНОЙ И НА ДВА ГЛОТКА.
	-- Она больше кружки, в этом и смысл предмета: CupMax = 2 против 1 у кружки.
	-- Пустая бутылка на старте отправляла бы игрока к очистителю, которого у него
	-- ещё нет, — то есть первый же глоток воды был бы недоступен.
	tool:SetAttribute("CupBase", TOOL_NAME)
	tool:SetAttribute("CupMax", CHARGES)
	tool:SetAttribute("CupState", "fresh")
	tool:SetAttribute("CupCharges", CHARGES)
	tool.Name = TOOL_NAME .. " (Fresh Water)"
	return tool
end

local template
local function getTemplate()
	if template and template.Parent then return template end
	local model = findModel()
	if not model then
		warn(("[Бутылка] модели %s нет ни в ReplicatedStorage, ни в Workspace")
			:format(MODEL_NAME))
		return nil
	end
	template = buildTool(model)
	if template then
		template.Parent = ReplicatedStorage
		print("[Бутылка] шаблон собран: " .. template:GetFullName())
	end
	return template
end

-- Наружу: выдать бутылку игроку. Тем же путём, что и остальные тулы, чтобы
-- сработала защита от переполнения рюкзака.
_G.GiveWaterBottle = function(player)
	local tpl = getTemplate()
	if not tpl then return false end
	local tool = tpl:Clone()
	if _G.GiveToolOrDrop then
		_G.GiveToolOrDrop(player, tool)
	else
		tool.Parent = player:FindFirstChildOfClass("Backpack") or player.Character
	end
	return true
end

task.defer(getTemplate)

print("[Бутылка] готова: тот же сосуд, что кружка (_G.GiveWaterBottle)")
