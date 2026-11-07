local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- TreeFarmBoard.client.lua
-- Вешает клики на кнопки борда «ДОБЫЧА ДЕРЕВА» (Tree_Farm). Логику и тексты/видимость
-- GUI считает сервер (TreeFarmSystem.server.lua) — здесь только клики → RemoteEvent.
--
-- Борды находим по тегу "TreeFarmBoard" (его ставит сервер) — так нет гонки загрузки
-- между стартом скрипта и репликацией модели. Печатает в Output, что навесил.

local Players           = game:GetService("Players")

-- Во время катсцены зачистки острова покупки заблокированы: камера уведена от
-- игрока, а доска остаётся кликабельной — так улучшение покупалось вслепую.
-- Флаг ставит сервер (IslandClearSystem), здесь только гасим клики.
local function inCutscene()
	return Players.LocalPlayer:GetAttribute("InCutscene") == true
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Если RemoteEvent не появился — серверный TreeFarmSystem.server.lua не запущен
-- (не лежит в ServerScriptService / заменён другим скриптом / упал с ошибкой).
-- Без него кнопки борда работать не могут — кричим об этом прямо в Output.
local TreeFarmAction = ReplicatedStorage:WaitForChild("TreeFarmAction", 15)
if not TreeFarmAction then
	warn("[TreeFarmBoard] НЕТ RemoteEvent 'TreeFarmAction' спустя 15 сек — "
		.. "TreeFarmSystem.server.lua не работает на сервере. Проверь, что он лежит "
		.. "в ServerScriptService и в Output нет красных ошибок от [TreeFarm]. "
		.. "Кнопка «Начать» без него не работает.")
	return
end

-- Должно совпадать с CFG в TreeFarmSystem.server.lua.
local CFG = {
	BOARD_PART = "Part",
	UNWORK_GUI = "Unwork",
	WORK_GUI   = "Work",
	WORK_FRAME = "Frame",
}
local CAT_FRAMES = { Speed = "Speed", Workers = "Workers", Rest = "Rest_time" }

local function findDeep(root, name)
	if not root then return nil end
	return root:FindFirstChild(name) or root:FindFirstChild(name, true)
end

-- Собрать все кнопки в поддереве.
local function allButtons(root)
	local list = {}
	if root then
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("GuiButton") then table.insert(list, d) end
		end
	end
	return list
end

-- Найти кнопку «построить» в Unwork: по имени/тексту (Начать/Start/Build/Открыть),
-- иначе первую кнопку.
local function findBuildButton(unwork)
	local btns = allButtons(unwork)
	for _, b in ipairs(btns) do
		local nm = string.lower(b.Name)
		local tx = string.lower((b:IsA("TextButton") and b.Text) or "")
		if nm:find("start") or nm:find("build") or nm:find("buy") or nm:find("begin")
			or tx:find("начать") or tx:find("start") or tx:find("открыть") then
			return b
		end
	end
	return btns[1]
end

local wired = {}

local function wireBoard(board)
	if wired[board] then return end
	wired[board] = true

	local part = board:WaitForChild(CFG.BOARD_PART, 10) or findDeep(board, CFG.BOARD_PART) or board

	-- Кнопка «Начать» в Unwork → построить.
	local unwork = part:WaitForChild(CFG.UNWORK_GUI, 10) or findDeep(part, CFG.UNWORK_GUI)
	local buildBtn = unwork and findBuildButton(unwork)
	if buildBtn then
		buildBtn.MouseButton1Click:Connect(function()
			if inCutscene() then return end
			print("[TreeFarmBoard] клик «Начать» →", board:GetFullName())
			TreeFarmAction:FireServer("build", board)
		end)
		print("[TreeFarmBoard] кнопка постройки навешена:", buildBtn:GetFullName())
	else
		warn("[TreeFarmBoard] НЕ нашёл кнопку постройки в", unwork and unwork:GetFullName() or (board:GetFullName() .. "/" .. CFG.UNWORK_GUI))
	end

	-- Кнопки Buy/Max по категориям в Work.
	local work = part:WaitForChild(CFG.WORK_GUI, 10) or findDeep(part, CFG.WORK_GUI)
	local frame = work and (findDeep(work, CFG.WORK_FRAME) or work)
	if frame then
		for cat, frameName in pairs(CAT_FRAMES) do
			local catFrame = findDeep(frame, frameName)
			if catFrame then
				local buy = catFrame:FindFirstChild("Buy", true)
				local max = catFrame:FindFirstChild("Max", true)
				if buy and buy:IsA("GuiButton") then
					buy.MouseButton1Click:Connect(function()
						if inCutscene() then return end
						TreeFarmAction:FireServer("buy", board, cat, false)
					end)
				end
				if max and max:IsA("GuiButton") then
					max.MouseButton1Click:Connect(function()
						if inCutscene() then return end
						TreeFarmAction:FireServer("buy", board, cat, true)
					end)
				end
			end
		end
	end
end

-- Существующие борды + появляющиеся позже (надёжно, через тег).
for _, b in ipairs(CollectionService:GetTagged("TreeFarmBoard")) do
	task.spawn(wireBoard, b)
end
CollectionService:GetInstanceAddedSignal("TreeFarmBoard"):Connect(function(b)
	task.spawn(wireBoard, b)
end)

-- Контрольный выстрел для отладки: если сервер за 10 сек не пометил ни одного
-- борда тегом — что-то не так на серверной стороне (борд не найден по имени
-- Tree_Farm или TreeFarmSystem упал) — пишем об этом явно.
task.delay(10, function()
	if #CollectionService:GetTagged("TreeFarmBoard") == 0 then
		warn("[TreeFarmBoard] за 10 сек сервер не пометил ни одного борда "
			.. "Tree_Farm тегом 'TreeFarmBoard' — клики вешать не на что. "
			.. "Смотри сводку [TreeFarm] в Output сервера.")
	end
end)