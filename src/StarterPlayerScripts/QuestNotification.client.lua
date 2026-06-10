-- QuestNotification.client.lua
-- Уведомления о выполненных квестах. С редизайна (Фаза 5) сами карточки рисует
-- NotificationCenter (_G.Notify, единый стиль) — здесь остались только наблюдатели
-- за квестами и тонкий форвардер со звуком. Старый API сохранён:
--   _G.ShowQuestNotification(subtitle, title, opts)  -- opts: {icon, sound, duration}

local Players      = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

-- ─── Звук (как раньше: SoundService/Sound_Menu/<name>) ───────────────────
local function playSound(name)
	local soundFolder = SoundService:FindFirstChild("Sound_Menu")
	local sound = soundFolder and soundFolder:FindFirstChild(name or "Completed_Quest")
	if sound then sound:Play() end
end

-- ─── Форвардер в NotificationCenter ──────────────────────────────────────
local function notify(subtitleText, titleText, opts)
	opts = opts or {}
	playSound(opts.sound)
	task.spawn(function()
		local t0 = os.clock()
		while not _G.Notify and os.clock() - t0 < 5 do
			task.wait(0.1)
		end
		if _G.Notify then
			_G.Notify({
				type = "success",
				icon = opts.icon or "🎯",
				title = titleText or "Task completed!",
				body = subtitleText or "",
				duration = opts.duration,
			})
		else
			warn("[QuestNotification] _G.Notify не найден — NotificationCenter.client.lua не загрузился")
		end
	end)
end

_G.ShowQuestNotification = notify

-- ─── Watch quest completions ─────────────────────────────────────────────
local connections = {}

local function watchQuest(questFolder)
	local completed = questFolder:FindFirstChild("Completed")
	local label     = questFolder:FindFirstChild("Label")
	if not completed or not label then return end

	-- Only fire when flipping from false → true
	local conn = completed:GetPropertyChangedSignal("Value"):Connect(function()
		if completed.Value == true then
			notify(label.Value)
		end
	end)
	table.insert(connections, conn)
end

local function bindFolder(folder)
	-- Disconnect old watchers
	for _, conn in connections do
		conn:Disconnect()
	end
	table.clear(connections)

	-- Watch existing quests
	for _, child in folder:GetChildren() do
		if child:IsA("Folder") and child.Name:sub(1, 6) == "Quest_" then
			watchQuest(child)
		end
	end

	-- Watch for new quests (e.g. after a reset)
	local addedConn = folder.ChildAdded:Connect(function(child)
		if child:IsA("Folder") and child.Name:sub(1, 6) == "Quest_" then
			watchQuest(child)
		end
	end)
	table.insert(connections, addedConn)
end

-- ─── Initial bind ────────────────────────────────────────────────────────
task.spawn(function()
	local folder = player:WaitForChild("DailyQuests")
	bindFolder(folder)

	-- Re-bind when the folder is replaced (quest reset / new day)
	player.ChildAdded:Connect(function(child)
		if child.Name == "DailyQuests" and child:IsA("Folder") then
			bindFolder(child)
		end
	end)
end)
