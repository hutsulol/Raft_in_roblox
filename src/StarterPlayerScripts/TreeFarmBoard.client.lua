-- TreeFarmBoard.client.lua
-- Вешает клики на кнопки борда «ДОБЫЧА ДЕРЕВА» (Tree_Farm). Логику и тексты/видимость
-- GUI считает сервер (TreeFarmSystem.server.lua) — здесь только клики → RemoteEvent.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TreeFarmAction = ReplicatedStorage:WaitForChild("TreeFarmAction")

-- Должно совпадать с CFG в TreeFarmSystem.server.lua.
local CFG = {
	BOARD_NAME = "Tree_Farm",
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

-- Найти кнопку: по точному имени; иначе первый TextButton в поддереве.
local function findButton(root, name)
	local byName = root and root:FindFirstChild(name, true)
	if byName and byName:IsA("GuiButton") then return byName end
	if root then
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("GuiButton") then return d end
		end
	end
	return nil
end

local wired = {}

local function wireBoard(board)
	if wired[board] then return end
	wired[board] = true

	local part = findDeep(board, CFG.BOARD_PART) or board

	-- Кнопка «Начать» в Unwork → построить.
	local unwork = findDeep(part, CFG.UNWORK_GUI)
	local buildBtn = unwork and findButton(unwork, "Buy")  -- имя кнопки может отличаться
	if buildBtn then
		buildBtn.MouseButton1Click:Connect(function()
			TreeFarmAction:FireServer("build", board)
		end)
	end

	-- Кнопки Buy/Max по категориям в Work.
	local work = findDeep(part, CFG.WORK_GUI)
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

for _, m in ipairs(workspace:GetDescendants()) do
	if m:IsA("Model") and m.Name == CFG.BOARD_NAME then
		wireBoard(m)
	end
end
workspace.DescendantAdded:Connect(function(m)
	if m:IsA("Model") and m.Name == CFG.BOARD_NAME then
		task.wait(0.2)
		wireBoard(m)
	end
end)
