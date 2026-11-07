-- AxeTools.lua  (ReplicatedStorage, общий модуль)
-- ЕДИНЫЙ СПИСОК ТОПОРОВ.
--
-- Возможности топора размазаны по восьми системам: урон в конусе (AxeCombat),
-- рубка деревьев (StoneAxe), разбор построек плота (RaftDemolish), разрушаемые
-- объекты (DestructibleSystem), анимации замаха (AxeClient), сохранение тулов
-- (RaftSaveSystem) и два клиентских помощника. Раньше каждая знала имена тулов
-- сама — и новый топор работал наполовину: где-то его узнавали, где-то нет.
--
-- ДОБАВИТЬ ТОПОР = дописать имя СЮДА. Больше нигде ничего править не нужно.

local AxeTools = {}

-- Всё, что считается топором: урон, разбор плота, разрушаемые объекты, анимации.
AxeTools.NAMES = {
	Axe       = true,   -- боевой
	Stone_Axe = true,   -- каменный
	Fire_Axe  = true,   -- огненный
}

-- Топоры, которыми РУБЯТ ДЕРЕВЬЯ. Это отдельный список: боевой «Axe» деревья не
-- рубит и раньше, и расширять ему возможности заодно с новым топором незачем.
AxeTools.CHOPPERS = {
	Stone_Axe = true,
	Fire_Axe  = true,
}

function AxeTools.isAxeName(name)
	if type(name) ~= "string" then return false end
	-- «^Axe» оставлено ради вариантов вида Axe_2/AxeLvl3, они уже были в проекте
	return AxeTools.NAMES[name] == true or name:match("^Axe") ~= nil
end

function AxeTools.isAxe(tool)
	return tool ~= nil and tool:IsA("Tool") and AxeTools.isAxeName(tool.Name)
end

function AxeTools.isChopper(tool)
	return tool ~= nil and tool:IsA("Tool") and AxeTools.CHOPPERS[tool.Name] == true
end

-- Топор В РУКАХ у игрока (или nil). Один и тот же способ поиска во всех системах.
function AxeTools.held(player)
	local char = player and player.Character
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	return AxeTools.isAxe(tool) and tool or nil
end

return AxeTools
