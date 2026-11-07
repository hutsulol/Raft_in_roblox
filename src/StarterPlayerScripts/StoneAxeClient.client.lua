-- StoneAxeClient.client.lua
-- Client-side glue for the Stone_Axe tool: highlights choppable
-- trees on hover, swaps the mouse cursor to the axe icon while
-- aiming, fires "ChopTree" on click under a 0.8 s cooldown, and
-- renders Raft-style item-drop notifications in the bottom-right
-- as the server dispenses drops on every swing.
--
-- Animation is handled by the in-tool Script
-- (src/Stone_Axe ( Tool )/Script). This file owns ONLY the chop
-- game logic + client-side HUD.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))
local camera = workspace.CurrentCamera

local chopTreeEvent = ReplicatedStorage:WaitForChild("ChopTree")
-- Боевой замах (AxeCombat): каменный топор бьёт и по живому — пиявка и т.п.
local axeSwingEvent = ReplicatedStorage:WaitForChild("AxeSwing")
local AxeTools      = require(ReplicatedStorage:WaitForChild("AxeTools"))
local AssetFind     = require(ReplicatedStorage:WaitForChild("AssetFind"))
-- Разбор плота (RaftDemolish): тем же топором ломаем пол и постройки
local demolishEvent = ReplicatedStorage:WaitForChild("RaftDemolish")

-- ─── Tunables ─────────────────────────────────────────────────────────
local CHOP_COOLDOWN  = 0.8     -- per the user's brief
local CHOP_AIM_RANGE = 200     -- studs of mouse-ray raycast

--[[ ⚠️ ДАЛЬНОСТЬ УДАРА ЗНАЕТ И КЛИЕНТ, И ЭТО НЕ ДУБЛИРОВАНИЕ РАДИ ДУБЛИРОВАНИЯ.
     Прицел бьёт лучом на 200 студов — столько нужно, чтобы подсветить дерево на
     острове издалека. А рубить сервер разрешает с 15 (StoneAxe.server.lua,
     CHOP_RANGE), и до сих пор клиент об этом не знал: игрок кликал по далёкому
     бревну, персонаж махал топором, событие улетало на сервер и там молча
     отбрасывалось. Со стороны — «бью, а не рубится».
     Держим то же число здесь: расстояние считаем от той же точки, что и сервер
     (GetPivot модели), иначе на кромке клиент и сервер разойдутся во мнениях. ]]
local CHOP_RANGE = 15

-- Custom axe cursor. mouse.Icon would render the asset at its
-- native upload size (huge), so we hide the system cursor while
-- aiming at a tree and draw our own size-controlled ImageLabel
-- that follows the mouse position. 40×40 pixels — small enough to
-- not obscure the tree, big enough to read as an axe.
local CURSOR_AXE_ASSET = "rbxassetid://102927945165446"
local CURSOR_AXE_SIZE  = 40

-- ─── State ────────────────────────────────────────────────────────────
local axeEquipped     = false
local currentTool     = nil
local highlightedTree = nil
local highlightBox    = nil
local choppingCooldown = false
-- Деталь постройки/пола плота под прицелом. Живёт отдельно от дерева:
-- дерево рубится своим событием, плот разбирается своим.
local demolishPart    = nil
local demolishCooldown = false

-- ─── HUD root ────────────────────────────────────────────────────────
local playerGui = player:WaitForChild("PlayerGui")
local hintGui = Instance.new("ScreenGui")
hintGui.Name = "StoneAxeHud"
hintGui.DisplayOrder = 51
hintGui.IgnoreGuiInset = true
hintGui.ResetOnSpawn = false
hintGui.Parent = playerGui

-- Separate ScreenGui for the axe cursor with IgnoreGuiInset = false
-- so its (0, 0) lines up with mouse.X / mouse.Y exactly. The cursor
-- needs to track the system cursor pixel-accurately, so we don't
-- want the topbar inset shifting it.
local cursorGui = Instance.new("ScreenGui")
cursorGui.Name = "StoneAxeCursor"
cursorGui.DisplayOrder = 1000
cursorGui.IgnoreGuiInset = false
cursorGui.ResetOnSpawn = false
cursorGui.Parent = playerGui

local axeCursor = Instance.new("ImageLabel")
axeCursor.Name = "AxeIcon"
axeCursor.AnchorPoint = Vector2.new(0.5, 0.5)
axeCursor.Size = UDim2.fromOffset(CURSOR_AXE_SIZE, CURSOR_AXE_SIZE)
axeCursor.BackgroundTransparency = 1
axeCursor.Image = CURSOR_AXE_ASSET
axeCursor.ScaleType = Enum.ScaleType.Fit
axeCursor.Visible = false
axeCursor.ZIndex = 100
axeCursor.Parent = cursorGui

-- "Aim at trees / Click to chop" hint at the bottom centre.
local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "HintText"
hintLabel.AnchorPoint = Vector2.new(0.5, 1)
hintLabel.Position = UDim2.new(0.5, 0, 0.8, 0)
hintLabel.Size = UDim2.new(0, 300, 0, 40)
hintLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
hintLabel.BackgroundTransparency = 0.4
hintLabel.Text = ""
hintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
hintLabel.TextSize = 18
hintLabel.Font = Enum.Font.GothamBold
hintLabel.Visible = false
hintLabel.Parent = hintGui

-- ⚠️ Подсказка уступает диалогу: пока собеседник говорит, она поднимается
-- над его окном. Правило одно на всю игру — см. ReplicatedStorage/HudDock.
local HudDock = require(game:GetService("ReplicatedStorage"):WaitForChild("HudDock"))
HudDock.keepAbove(hintLabel, 12)

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 8)
hintCorner.Parent = hintLabel

-- Drop notifications now live in StarterPlayerScripts/InventoryNotify.
-- That file listens to the InventoryNotify RemoteEvent which the
-- server fires from inside _G.AddResourceToInventory, so every pickup
-- (tree chop / stone mine / ocean pull / shovel / floor pickup)
-- gets the same Raft-style bottom-right card without per-tool
-- duplication. Stone_Axe just calls the inventory-add helper for each
-- drop and the cards appear automatically.

-- ─── Highlight ───────────────────────────────────────────────────
-- Зелёная обводка = дерево (добыча), оранжевая = разбор своего плота.
-- Цвет разный намеренно: удар по палубе необратим, и его нельзя путать
-- с обычной рубкой.
local OUTLINE_TREE     = Color3.fromRGB(120, 220, 90)
local OUTLINE_DEMOLISH = Color3.fromRGB(240, 150, 55)

local function createHighlight()
	if highlightBox then highlightBox:Destroy() end
	highlightBox = Instance.new("Highlight")
	highlightBox.FillTransparency = 1
	highlightBox.OutlineColor = OUTLINE_TREE
	highlightBox.OutlineTransparency = 0
	highlightBox.Parent = playerGui
end

local function clearHighlight()
	if highlightBox then highlightBox.Adornee = nil end
	highlightedTree = nil
	demolishPart = nil
end

-- ─── Цель разбора плота ───────────────────────────────────────────
-- Прямой ребёнок Raft, которому принадлежит деталь под курсором: клетка
-- пола (Raft_part / Net_Part / BuildType="raft") или постройка. Списки
-- защищённого и проверку дистанции держит СЕРВЕР (RaftDemolish) — здесь
-- только подсветка, поэтому промах по защищённому объекту максимум
-- покажет лишнюю обводку, но сломать его не даст.
local DEMOLISH_SKIP = { monolit_aquamen = true }
local function findDemolishTarget(instance)
	local raft = workspace:FindFirstChild("Raft")
	if not raft or not instance or not instance:IsDescendantOf(raft) then return nil end
	local node = instance
	while node.Parent and node.Parent ~= raft do
		node = node.Parent
	end
	if node.Parent ~= raft then return nil end
	if node == raft.PrimaryPart then return nil end
	local n = node.Name:lower()
	if DEMOLISH_SKIP[n] or n:find("monolit") or n:find("board") or n:find("community") then
		return nil
	end
	if node:GetAttribute("NoDemolish") then return nil end
	--[[ Стартовый плот: сервер при запуске публикует прямоугольник его досок
	     атрибутами плота (RaftDemolish, snapshotStarter). Проверяем тем же
	     правилом, чтобы стартовая доска не подсвечивалась как цель — сервер
	     её всё равно не даст сломать, но игрок не должен тыкать в пустоту. ]]
	local isTile = node.Name == "Raft_part" or node.Name == "Net_Part"
		or node:GetAttribute("BuildType") == "raft"
	if isTile and node:GetAttribute("StarterTile") then return nil end   -- помечена сервером
	local minX = raft:GetAttribute("StarterMinX")
	if isTile and type(minX) == "number" and raft.PrimaryPart then
		local rp = raft.PrimaryPart
		local yaw = rp:GetAttribute("RestYaw")
		if type(yaw) ~= "number" then
			local _, y = rp.CFrame:ToEulerAnglesYXZ()
			yaw = y
		end
		local pos
		if node:IsA("Model") then
			-- по деталям, не по пивоту: пивот модели без PrimaryPart не едет за плотом
			local ok, cf = pcall(function() return node:GetBoundingBox() end)
			pos = ok and cf and cf.Position or nil
		elseif node:IsA("BasePart") then
			pos = node.Position
		end
		if pos then
			local l = (CFrame.new(rp.Position) * CFrame.Angles(0, yaw, 0)):PointToObjectSpace(pos)
			if l.X >= minX and l.X <= raft:GetAttribute("StarterMaxX")
				and l.Z >= raft:GetAttribute("StarterMinZ") and l.Z <= raft:GetAttribute("StarterMaxZ") then
				return nil
			end
		end
	end
	return node
end

-- ─── Resolve a Choppable tree from the raycast hit ────────────────
local function findChoppableTree(instance)
	if not instance then return nil end
	local current = instance
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("Choppable") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Pick what to outline for a given Choppable model. Planted Bed_T*
-- wrappers carry the bed art (Center / Model / Earth) alongside the
-- actual tree, so highlighting the whole wrapper outlines the stones
-- and dirt too. Skip past the bed's static children and return the
-- first dynamic one (Palm Tree, Banana Tree, …) so only the tree
-- itself gets the outline. Free-standing trees on islands don't have
-- these static children and fall through to the wrapper.
local TREE_BED_STATIC = { Center = true, Model = true, Earth = true }
local function findHighlightTarget(tree)
	if not tree then return nil end
	-- ⚠️ ТОЛЬКО У ГРЯДКИ. У вольного дерева (пальма острова крабов: ствол и
	-- листья отдельными деталями) «первый ребёнок» — одна его часть, и
	-- подсвечивалась только она. Нет деталей грядки — обводим дерево целиком.
	local isBed = false
	for _, child in tree:GetChildren() do
		if TREE_BED_STATIC[child.Name] then isBed = true break end
	end
	if not isBed then return tree end
	for _, child in tree:GetChildren() do
		if not TREE_BED_STATIC[child.Name] and not child:GetAttribute("IsBush") then
			return child
		end
	end
	return tree
end

-- ─── Cursor swap helper ──────────────────────────────────────────
-- showAxeCursor(true)  → hide the system cursor and follow the
--                        mouse with our 40×40 axe ImageLabel
-- showAxeCursor(false) → restore the system cursor + hide our icon
local function showAxeCursor(show)
	if show then
		UserInputService.MouseIconEnabled = false
		axeCursor.Position = UDim2.fromOffset(mouse.X, mouse.Y)
		axeCursor.Visible = true
	else
		UserInputService.MouseIconEnabled = true
		axeCursor.Visible = false
	end
end

-- ─── Per-frame highlight + cursor update ─────────────────────────
local function updateHighlight()
	if not axeEquipped then
		clearHighlight()
		showAxeCursor(false)
		return
	end

	-- Always track the mouse position so the moment we DO show the
	-- axe cursor it lands at the right pixel without a stale frame.
	axeCursor.Position = UDim2.fromOffset(mouse.X, mouse.Y)

	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}
	if player.Character then table.insert(filterList, player.Character) end
	params.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * CHOP_AIM_RANGE, params)
	if result and result.Instance then
		local tree = findChoppableTree(result.Instance)
		if tree then
			demolishPart = nil
			highlightedTree = tree
			if highlightBox then
				highlightBox.Adornee = findHighlightTarget(tree)
				highlightBox.OutlineColor = OUTLINE_TREE
			end
			showAxeCursor(true)
			hintLabel.Text = "Кликай, чтобы рубить дерево"
			hintLabel.Visible = true
			return
		end

		-- ПОСТРОЙКА ИЛИ ПОЛ ПЛОТА — та же иконка топора, но обводка
		-- оранжевая, чтобы разбор своего плота нельзя было спутать с рубкой.
		local target = findDemolishTarget(result.Instance)
		if target then
			highlightedTree = nil
			demolishPart = result.Instance
			if highlightBox then
				highlightBox.Adornee = target
				highlightBox.OutlineColor = OUTLINE_DEMOLISH
			end
			showAxeCursor(true)
			hintLabel.Text = "Кликай, чтобы разобрать"
			hintLabel.Visible = true
			return
		end
	end

	clearHighlight()
	showAxeCursor(false)
	hintLabel.Text = "Наведись на деревья на острове, чтобы рубить"
	hintLabel.Visible = true
end

-- ─── Tool equip / unequip plumbing ────────────────────────────────
-- Наводка на дерево работает для ЛЮБОГО рубящего топора (ReplicatedStorage.AxeTools),
-- а не только для каменного: новый топор иначе не видел бы деревьев.
--[[ ⚠️ ЗАМАХ ИГРАЕТ КЛИЕНТ, А НЕ СКРИПТ ВНУТРИ ТУЛА.
     Раньше анимацию запускал серверный скрипт тула по Tool.Activated — то есть
     на КАЖДЫЙ клик, что бы под прицелом ни было. Отменить это клиент не мог:
     Activated приходит от движка, и к моменту, когда клиент понимает «цель
     далеко», рука уже пошла. Поэтому замах переехал сюда, где известно и куда
     смотрит игрок, и как далеко до цели.
     Трек грузится на своём Animator: анимации, запущенные на собственном
     персонаже, движок реплицирует остальным сам. ]]
local chopTrack = nil

local function loadChopTrack(tool)
	chopTrack = nil
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (hum and tool) then return end

	local an = hum:FindFirstChildOfClass("Animator")
	if not an then
		an = Instance.new("Animator")
		an.Parent = hum
	end

	-- имена те же, что искал скрипт тула: сперва под риг, потом запасные
	local anim = tool:FindFirstChild("HitTree" .. hum.RigType.Name)
		or tool:FindFirstChild("HitTreeR6")
		or tool:FindFirstChildWhichIsA("Animation", true)
	if not (anim and anim:IsA("Animation") and anim.AnimationId ~= "") then return end

	local ok, tr = pcall(function() return an:LoadAnimation(anim) end)
	if ok and tr then
		tr.Priority = Enum.AnimationPriority.Action
		tr.Looped = false
		chopTrack = tr
	end
end

--[[ Свист замаха лежит внутри самого тула (Handle). Имена перебираем те же,
     что искал скрипт тула: авторы называли звук по-разному. ]]
local function findSwingSound(tool)
	local handle = tool and tool:FindFirstChild("Handle")
	local where = handle or tool
	if not where then return nil end
	for _, n in ipairs({ "Swing", "SwingSound", "Whoosh" }) do
		local snd = where:FindFirstChild(n, true)
		if snd and snd:IsA("Sound") then return snd end
	end
	return nil
end

local function playChop()
	--[[ ⚠️ ЗВУК ИДЁТ ВМЕСТЕ С ЗАМАХОМ, А НЕ ОТДЕЛЬНО ОТ НЕГО.
	     Раньше и трек, и свист запускал скрипт тула на каждый клик. Замах уехал
	     сюда — свист обязан уехать следом, иначе получится ровно та же ложь для
	     игрока, только на слух: звук удара есть, удара нет.
	     Звук проигрывается локально, поэтому соседи его не слышат; сама анимация
	     реплицируется движком, так что со стороны замах виден. Свист замаха —
	     обратная связь бьющему, ради неё отдельный ремоут не заводим. ]]
	local snd = findSwingSound(currentTool)
	if snd then pcall(function() snd:Play() end) end

	if not chopTrack then return end
	pcall(function()
		chopTrack:Stop(0)
		chopTrack:Play(0.05)
	end)
end

local function onToolEquipped(tool)
	if AxeTools.isChopper(tool) then
		axeEquipped = true
		currentTool = tool
		createHighlight()
		hintLabel.Visible = true
		loadChopTrack(tool)
	end
end

local function onToolUnequipped(tool)
	if AxeTools.isChopper(tool) then
		axeEquipped = false
		currentTool = nil
		clearHighlight()
		showAxeCursor(false)
		hintLabel.Visible = false
		if chopTrack then
			pcall(function() chopTrack:Stop(0.1) end)
			chopTrack = nil
		end
	end
end

local function setupCharacter(char)
	if not char then return end

	-- ⚠️ СБРОС НА КАЖДОМ РЕСПАВНЕ. Если игрок умер С ТОПОРОМ В РУКАХ, старый
	-- персонаж уносит тул с собой, а состояние курсора оставалось включённым:
	-- иконка топора висела перед глазами навсегда и не убиралась даже сменой
	-- оружия. Здесь единственное место, где точно известно, что рук больше нет.
	axeEquipped = false
	currentTool = nil
	clearHighlight()
	showAxeCursor(false)
	hintLabel.Visible = false

	local hum = char:FindFirstChildWhichIsA("Humanoid") or char:WaitForChild("Humanoid", 5)
	if hum then
		hum.Died:Connect(function()
			axeEquipped = false
			currentTool = nil
			clearHighlight()
			showAxeCursor(false)
			hintLabel.Visible = false
		end)
	end

	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then onToolEquipped(child) end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then onToolUnequipped(child) end
	end)
	for _, child in char:GetChildren() do
		if AxeTools.isChopper(child) then
			onToolEquipped(child)
			break
		end
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

RunService.RenderStepped:Connect(function()
	if axeEquipped then
		updateHighlight()
	end
end)

-- ─── Click → chop (0.8 s cooldown) ────────────────────────────────
--[[ Далеко ли цель под прицелом. nil — цели нет вовсе (удар в пустоту). ]]
local function aimDistance()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local target
	if highlightedTree then
		-- та же точка, что и на сервере: середина модели, а не место попадания луча
		target = highlightedTree:GetPivot().Position
	elseif demolishPart then
		target = demolishPart.Position
	end
	if not target then return nil end
	return (hrp.Position - target).Magnitude
end

GamepadInput.onPrimary(mouse, function()
	if not axeEquipped then return end
	if choppingCooldown then return end

	--[[ ⚠️ ЦЕЛЬ ДАЛЕКО — НЕ МАШЕМ ВОВСЕ.
	     Персонаж бил топором по бревну за полсотни студов: анимация играла,
	     событие уходило, сервер его отбрасывал по своей проверке дальности.
	     Впустую махать — это не «честная попытка», а обман: игрок думает, что
	     удар не засчитался из-за лагов, и продолжает бить.
	     Удар В ПУСТОТУ при этом остаётся: там цели нет, дальность не при чём, и
	     махнуть топором по воздуху (или по подплывшей пиявке) игрок вправе. ]]
	local dist = aimDistance()
	if dist and dist > CHOP_RANGE then
		hintLabel.Text = "Слишком далеко — подойди ближе"
		hintLabel.Visible = true
		return
	end

	-- Замах играем сами: сервер про прицел ничего не знает (см. loadChopTrack)
	playChop()

	-- Боевой замах на КАЖДЫЙ клик: сервер (AxeCombat) сам решит, попал ли кто-то
	-- живой в конус, и сам режет частоту своим кулдауном. Без этого каменный
	-- топор вообще не наносил урона — клики без дерева под прицелом просто
	-- ничего не отправляли.
	axeSwingEvent:FireServer()

	-- РАЗБОР ПЛОТА: свой кулдаун и своё событие. Сервер решает, можно ли
	-- ломать эту цель, — здесь только отправка.
	if demolishPart then
		if not demolishCooldown then
			demolishCooldown = true
			demolishEvent:FireServer(demolishPart)
			task.delay(0.35, function() demolishCooldown = false end)
		end
		return
	end

	if not highlightedTree then return end

	choppingCooldown = true
	chopTreeEvent:FireServer(highlightedTree)

	task.delay(CHOP_COOLDOWN, function()
		choppingCooldown = false
	end)
end)

-- ─── Server feedback → tree-fell SFX + highlight clear ───────────
-- Drop notifications now come through InventoryNotify (server fires
-- one event per inventory add inside _G.AddResourceToInventory).
-- We keep this listener only for the felled-tree polish: a final
-- wood-break sound + highlight clear when health reaches 0.
chopTreeEvent.OnClientEvent:Connect(function(action, _, healthLeft)
	if action == "drops" and (healthLeft or 0) <= 0 then
		clearHighlight()
		local logTemplate = AssetFind.find("Log")
		local woodBreak = logTemplate and logTemplate:FindFirstChild("Wood Break", true)
		if woodBreak and woodBreak:IsA("Sound") then
			local clone = woodBreak:Clone()
			clone.Parent = SoundService
			clone:Play()
			Debris:AddItem(clone, 5)
		end
	end
end)