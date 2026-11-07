--[[
	ПОДСКАЗКА КВЕСТА «ПЕРВЫЙ ЖИТЕЛЬ» (story_assign_fisher, сюжет торговца).
	«?» на трекере (TrackerCard) включает её через _G.TeamHintSetEnabled.

	Шаги считаются из того, что сейчас на экране:
	  1. окно «Команда» закрыто → золотое кольцо пульсирует вокруг кнопки «Команда»;
	  2. окно открыто → баннер: нажми на жителя, в «Место работы» выбери
	     «Рыбацкое место» — житель сразу пойдёт рыбачить.
	Квест закрылся — подсказка гаснет сама.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local QUEST_ID = "story_assign_fisher"
local GOLD = Color3.fromHex("FFD95A")
local OUTLINE = Color3.fromHex("0D2A4F")

local enabled = false
local questOpen = false

local gui = Instance.new("ScreenGui")
gui.Name = "TeamHintGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000   -- поверх окна «Команда»
gui.Enabled = false
gui.Parent = playerGui

local ring = Instance.new("Frame")
ring.Name = "Ring"
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.BackgroundTransparency = 1
ring.Parent = gui
Instance.new("UICorner", ring).CornerRadius = UDim.new(0, 16)
local ringStroke = Instance.new("UIStroke")
ringStroke.Color = GOLD
ringStroke.Thickness = 4
ringStroke.Parent = ring

local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 132)   -- ниже часов и дня
banner.Size = UDim2.fromOffset(560, 46)
banner.BackgroundColor3 = OUTLINE
banner.BackgroundTransparency = 0.1
banner.TextColor3 = Color3.new(1, 1, 1)
banner.Font = Enum.Font.GothamBold
banner.TextSize = 17
banner.TextWrapped = true
banner.Parent = gui
Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 12)
local bannerStroke = Instance.new("UIStroke")
bannerStroke.Color = GOLD
bannerStroke.Thickness = 2
bannerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
bannerStroke.Parent = banner

local function visibleGui(obj)
	if not (obj and obj:IsA("GuiObject") and obj.Visible and obj.AbsoluteSize.X > 2) then return false end
	local sg = obj:FindFirstAncestorWhichIsA("LayerCollector")
	return sg ~= nil and sg.Enabled
end
local function find(guiName, childName)
	local root = playerGui:FindFirstChild(guiName)
	if not root then return nil end
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == childName and visibleGui(d) then return d end
	end
	return nil
end

-- кольцо вокруг элемента. ⚠️ AbsolutePosition отсчитывается от низа топбара даже у
-- ScreenGui с IgnoreGuiInset, а кольцо (тоже IgnoreGuiInset) — от верха экрана:
-- прибавляем инсет, иначе кольцо висело на строку выше (вокруг «Карты»)
local function ringAround(obj)
	local inset = GuiService:GetGuiInset()
	local pad = 8 + 3 * math.sin(os.clock() * 6)
	local c = obj.AbsolutePosition + obj.AbsoluteSize * 0.5 + Vector2.new(0, inset.Y)
	ring.Position = UDim2.fromOffset(c.X, c.Y)
	ring.Size = UDim2.fromOffset(obj.AbsoluteSize.X + pad * 2, obj.AbsoluteSize.Y + pad * 2)
	ring.Visible = true
end

RunService.RenderStepped:Connect(function()
	local on = enabled and questOpen
	gui.Enabled = on
	if not on then return end
	local open = typeof(_G.IsSurvivorsOpen) == "function" and _G.IsSurvivorsOpen()
	ring.Visible = false
	-- окно открыто — баннер внизу, чтобы не закрывать заголовок «Выжившие»
	banner.Position = open and UDim2.new(0.5, 0, 1, -110) or UDim2.new(0.5, 0, 0, 132)
	if not open then
		local btn = find("SurvivorsButtonGui", "SurvivorsButton")
		banner.Text = btn and "Открой «Команду» — там твой первый житель" or "Кнопка «Команда» появится вместе с жителем"
		if btn then ringAround(btn) end
		return
	end
	-- в окне: карточка рыбацкого места (страница жителя) → иначе строка жителя (список)
	local card = find("SurvivorsGui", "BuildingCard_fishing")
	if card then
		banner.Text = "Выбери «Рыбацкое место» — житель сразу пойдёт рыбачить"
		ringAround(card)
		return
	end
	local row = find("SurvivorsGui", "SurvivorRow")
	if row then
		banner.Text = "Нажми на жителя"
		ringAround(row)
		return
	end
	banner.Text = "Вернись к списку жителей"
end)

-- квест на трекере и не закрыт? (снимок QuestState)
local questEvent = ReplicatedStorage:WaitForChild("QuestState", 30)
if questEvent then
	questEvent.OnClientEvent:Connect(function(action, snapshot)
		if action ~= "state" or type(snapshot) ~= "table" then return end
		local open = false
		for _, q in ipairs(snapshot.quests or {}) do
			if q.id == QUEST_ID and not q.completed then open = true end
		end
		-- квест только что появился — подсказка горит сразу, искать «?» не надо
		if open and not questOpen then enabled = true end
		questOpen = open
		if not open then enabled = false end
	end)
end

_G.TeamHintSetEnabled = function(on) enabled = on == true end
_G.TeamHintEnabled = function() return enabled end

print("[TeamHint] подсказка «Первый житель» готова («?» на трекере)")
