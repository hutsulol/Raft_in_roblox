-- TreeFarmBoard.client.lua
-- Вешает клики на кнопки борда «ДОБЫЧА ДЕРЕВА» (Tree_Farm). Логику и тексты/видимость
-- GUI считает сервер (TreeFarmSystem.server.lua) — здесь только клики → RemoteEvent.
--
-- Борды находим по тегу "TreeFarmBoard" (его ставит сервер) — так нет гонки загрузки
-- между стартом скрипта и репликацией модели. Печатает в Output, что навесил.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local TreeFarmAction = ReplicatedStorage:WaitForChild("TreeFarmAction")

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
						TreeFarmAction:FireServer("buy", board, cat, false)
					end)
				end
				if max and max:IsA("GuiButton") then
					max.MouseButton1Click:Connect(function()
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
