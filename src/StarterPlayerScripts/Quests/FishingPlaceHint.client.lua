--[[
	ПОДСКАЗКА КВЕСТА «ПОСТАВЬ РЫБАЦКОЕ МЕСТО» (story_fishing_place, сюжет торговца).
	«?» на трекере (TrackerCard) включает её через _G.FishingPlaceHintSetEnabled.

	Шаги считаются из того, что у игрока сейчас:
	  1. тула Raft_fishing_spot нет вовсе → «Забери подарок у торговца»;
	  2. тул в рюкзаке/хотбаре → золотое кольцо вокруг его слота хотбара и
	     «Возьми в руки — нажми N»;
	  3. тул в руках → как ставить: клетка пола у края, впереди вода,
	     R — повернуть, ЛКМ — поставить (FishingSpotPlace.client).
	Квест закрылся — подсказка гаснет сама.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local QUEST_ID = "story_fishing_place"
local TOOL = "Raft_fishing_spot"
local GOLD = Color3.fromHex("FFD95A")
local OUTLINE = Color3.fromHex("0D2A4F")

local enabled = false
local questOpen = false

local gui = Instance.new("ScreenGui")
gui.Name = "FishingPlaceHintGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
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
banner.Size = UDim2.fromOffset(600, 50)
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

-- слот хотбара, где лежит рыбацкое место: его иконка-модель помечена IconSrc
-- (InventoryUI.renderSlot пишет полное имя шаблона)
local function hotbarSlot()
	local hg = playerGui:FindFirstChild("HotbarGui")
	local bar = hg and hg:FindFirstChild("Hotbar")
	if not bar then return nil end
	for _, slot in ipairs(bar:GetChildren()) do
		if slot:IsA("GuiObject") and slot.Name:match("^HotbarSlot_%d+$") then
			for _, d in ipairs(slot:GetDescendants()) do
				local src = d:GetAttribute("IconSrc")
				if type(src) == "string" and src:sub(-#TOOL) == TOOL then return slot end
			end
		end
	end
	return nil
end

-- ⚠️ AbsolutePosition отсчитан от низа топбара даже в ScreenGui с IgnoreGuiInset,
-- а кольцо (IgnoreGuiInset) — от верха экрана: прибавляем инсет
local function ringAround(obj)
	local inset = GuiService:GetGuiInset()
	local pad = 6 + 3 * math.sin(os.clock() * 6)
	local c = obj.AbsolutePosition + obj.AbsoluteSize * 0.5 + Vector2.new(0, inset.Y)
	ring.Position = UDim2.fromOffset(c.X, c.Y)
	ring.Size = UDim2.fromOffset(obj.AbsoluteSize.X + pad * 2, obj.AbsoluteSize.Y + pad * 2)
	ring.Visible = true
end

RunService.RenderStepped:Connect(function()
	local on = enabled and questOpen
	gui.Enabled = on
	if not on then return end
	ring.Visible = false
	local char = player.Character
	local held = char and char:FindFirstChild(TOOL)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local inBag = backpack and backpack:FindFirstChild(TOOL)
	if held then
		banner.Text = "Наведи на клетку пола у края плота — впереди должна быть вода.  R — повернуть,  ЛКМ — поставить"
		return
	end
	if inBag then
		local slot = hotbarSlot()
		if slot then
			local n = slot.Name:match("%d+")
			banner.Text = ("Возьми «Рыбацкое место» в руки — нажми %s или кликни по слоту"):format(n or "на слот")
			ringAround(slot)
		else
			banner.Text = "Возьми «Рыбацкое место» в руки — оно в инвентаре (E)"
		end
		return
	end
	banner.Text = "Забери подарок у торговца: подойди к прилавку его яхты и нажми E"
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

_G.FishingPlaceHintSetEnabled = function(on) enabled = on == true end
_G.FishingPlaceHintEnabled = function() return enabled end

print("[FishingHint] подсказка «Поставь рыбацкое место» готова («?» на трекере)")
