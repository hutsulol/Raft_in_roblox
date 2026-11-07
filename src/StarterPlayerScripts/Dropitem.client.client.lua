local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))
local ItemNamesRu = nil
pcall(function() ItemNamesRu = require(game:GetService("ReplicatedStorage"):WaitForChild("ItemNamesRu", 5)) end)

local dropEvent = ReplicatedStorage:WaitForChild("DropItem")
local pickupEvent = ReplicatedStorage:WaitForChild("PickupDroppedItem")

local HOTBAR_SLOTS = 8

--[[ ⚠️ НА ТЕЛЕФОНЕ ПОДБОР БЫЛ НЕВОЗМОЖЕН ВООБЩЕ.
     Подбор висел только на клавише E, а на телефоне её нет: предмет
     подсвечивался, подсказка звала нажать E — и на этом всё кончалось.
     Признак тот же, что во всём проекте: есть касания и нет мыши. Планшет
     с мышью сюда не попадёт и останется с клавишей. ]]
local IS_PHONE = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local currentHighlight = nil
local currentTarget = nil
local promptBillboard = nil

-- Shared flag: when true, InventoryUI should NOT toggle on E press
_G.SuppressInventoryToggle = false

--[[ Луч пускаем по ТОЧКЕ ЭКРАНА, а не жёстко по курсору: на телефоне
     курсора нет, а палец бьёт в произвольное место кадра. Подсветка
     по-прежнему ходит за курсором, подбор — за пальцем. ]]
local function getDroppedItemAt(sx, sy)
	local ray = camera:ScreenPointToRay(sx, sy)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		params.FilterDescendantsInstances = {player.Character}
	end

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	if not result or not result.Instance then
		return nil, nil
	end

	local hit = result.Instance

	if CollectionService:HasTag(hit, "DroppedItem") then
		return hit, hit
	end

	local model = hit:FindFirstAncestorOfClass("Model")
	if model and CollectionService:HasTag(model, "DroppedItem") then
		return model, hit
	end

	return nil, nil
end

local function getDroppedItemUnderMouse()
	return getDroppedItemAt(mouse.X, mouse.Y)
end

local function clearHighlight()
	if currentHighlight then
		currentHighlight:Destroy()
		currentHighlight = nil
	end
	if promptBillboard then
		promptBillboard:Destroy()
		promptBillboard = nil
	end
	currentTarget = nil
	-- Defer the flag reset so InventoryUI's InputBegan handler
	-- still sees it as true during the same frame
	task.defer(function()
		if currentTarget == nil then
			_G.SuppressInventoryToggle = false
		end
	end)
end

local function getAdornee(resource)
	if resource:IsA("Model") and resource.PrimaryPart then
		return resource.PrimaryPart
	elseif resource:IsA("BasePart") then
		return resource
	end
	return resource:FindFirstChildWhichIsA("BasePart", true) or resource
end

--[[ ⚠️ ДОБИВАЕМ СТАРУЮ КОПИЮ ЭТОГО СКРИПТА.
     StarterPlayerScripts помечен $ignoreUnknownInstances: дубль, когда-то залитый
     в плейс руками, Rojo не удаляет. Он рисует свою табличку «Press E to pick
     up / Leaves» поверх нашей — отсюда «пишется на двух языках». Глушим сам
     дубль (скрипт-тёзка, не мы) и на всякий случай сносим чужие таблички с
     английским текстом, если он успел их создать до нас. ]]
do
	local function killTwin(inst)
		if inst ~= script and inst:IsA("LocalScript") and inst.Name:lower():find("dropitem", 1, true) then
			inst.Disabled = true
			inst:Destroy()
			print("[Подбор] удалён дубль скрипта: " .. inst:GetFullName())
		end
	end
	local scripts = player:FindFirstChild("PlayerScripts")
	if scripts then
		for _, d in ipairs(scripts:GetDescendants()) do killTwin(d) end
		scripts.DescendantAdded:Connect(killTwin)
	end
	local function killForeignPrompt(inst)
		if not inst:IsA("BillboardGui") then return end
		task.defer(function()
			if not inst.Parent then return end
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("TextLabel") and d.Text:find("Press E to pick up", 1, true) then
					inst:Destroy()
					return
				end
			end
		end)
	end
	playerGui.ChildAdded:Connect(killForeignPrompt)
	for _, g in ipairs(playerGui:GetChildren()) do killForeignPrompt(g) end
end

local function createPrompt(resource)
	if promptBillboard then promptBillboard:Destroy() end

	local adornee = getAdornee(resource)

	--[[ ⚠️ РАЗМЕР В ПИКСЕЛЯХ, А НЕ В СТУДАХ.
	     Табличка 5×1.2 студа с TextScaled на телефоне и с расстояния ужималась
	     до нескольких пикселей: буквы с обводкой наезжали друг на друга в
	     нечитаемую кашу («не видно, что написано, буквы друг на друге»).
	     Пиксельный размер одинаков на любой дистанции, кегль фиксированный. ]]
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(240, 58)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.MaxDistance = 60
	billboard.AlwaysOnTop = true
	billboard.Adornee = adornee
	billboard.Parent = playerGui

	--[[ ⚠️ НА ТЕЛЕФОНЕ СТРОКИ ПРО E НЕТ.
	     Она не только бесполезна (клавиши нет), но и налезала на название
	     предмета: обе надписи с TextScaled, и на маленькой табличке они
	     сливались в кашу. Остаётся одно название, во всю высоту. ]]
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.5, 0)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Visible = not IS_PHONE
	label.Text = "Нажми " .. GamepadInput.keyLabel(Enum.KeyCode.E) .. ", чтобы подобрать"
	label.TextColor3 = Color3.fromRGB(255, 220, 100)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.Parent = billboard

	-- Show item name below
	local resType = resource:GetAttribute("ResourceType") or "Item"
	local resAmount = resource:GetAttribute("ResourceAmount") or 1
	-- по-русски, если имя известно словарю; служебный ключ вроде «SmallContainer» игроку не показываем
	local ru = ItemNamesRu and ItemNamesRu.lookup and ItemNamesRu.lookup(resType)
	local displayText = (type(ru) == "string" and ru ~= "") and ru or resType:gsub("_", " ")
	if resAmount > 1 then
		displayText = displayText .. " x" .. resAmount
	end

	local nameLabel = Instance.new("TextLabel")
	-- без строки про E название занимает табличку целиком
	nameLabel.Size = UDim2.new(1, 0, IS_PHONE and 0.9 or 0.4, 0)
	nameLabel.Position = UDim2.new(0, 0, IS_PHONE and 0.05 or 0.55, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayText
	nameLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 16
	nameLabel.Parent = billboard

	promptBillboard = billboard
end

-- Find which hotbar slot the mouse is hovering over
local function getHoveredHotbarSlot()
	local hotbarGui = playerGui:FindFirstChild("HotbarGui")
	if not hotbarGui then return nil end
	local bar = hotbarGui:FindFirstChild("Hotbar")
	if not bar then return nil end

	local mousePos = UserInputService:GetMouseLocation()

	for i = 1, HOTBAR_SLOTS do
		local slot = bar:FindFirstChild("HotbarSlot_" .. i)
		if slot then
			local absPos = slot.AbsolutePosition
			local absSize = slot.AbsoluteSize
			if mousePos.X >= absPos.X and mousePos.X <= absPos.X + absSize.X
				and mousePos.Y >= absPos.Y and mousePos.Y <= absPos.Y + absSize.Y then
				return i
			end
		end
	end

	return nil
end

-- Raycast from mouse to get world drop position
local function getMouseWorldPosition()
	local mPos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mPos.X, mPos.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local char = player.Character
	if char then rayParams.FilterDescendantsInstances = {char} end
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	return result and result.Position or nil
end

-- Highlight dropped items under mouse
RunService.RenderStepped:Connect(function()
	local resource, part = getDroppedItemUnderMouse()

	if resource == currentTarget then
		return
	end

	clearHighlight()

	if resource then
		currentTarget = resource
		_G.SuppressInventoryToggle = true

		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(255, 220, 100)
		highlight.FillTransparency = 0.5
		highlight.OutlineColor = Color3.fromRGB(255, 220, 100)
		highlight.OutlineTransparency = 0
		highlight.Parent = resource
		currentHighlight = highlight

		createPrompt(resource)
	end
end)

--[[ Один подбор на оба способа: клавишу и палец. Раньше тело подбора жило
     прямо в обработчике клавиши, и добавить тап значило скопировать его
     вторым куском — вместе с тонкостью про LastPickupTime ниже. ]]
local function pickUp(resource)
	if not (resource and resource.Parent) then return false end
	local hitPart = resource
	if hitPart:IsA("Model") then
		hitPart = hitPart.PrimaryPart or hitPart:FindFirstChildWhichIsA("BasePart")
	end
	if not hitPart then return false end
	pickupEvent:FireServer(hitPart)
	-- ⚠️ Отметку ставим ДО clearHighlight (он откладывает сброс флага):
	-- инвентарь читает её и не открывается в тот же кадр, что и подбор.
	_G.LastPickupTime = os.clock()
	clearHighlight()
	return true
end

-- Input handling
UserInputService.InputBegan:Connect(function(input, processed)
	--[[ ⚠️ ТАП — ПОЛНОЦЕННЫЙ СПОСОБ ПОДБОРА, А НЕ ДУБЛЬ КЛАВИШИ.
	     Бьём лучом ровно туда, куда попал палец, а не туда, где стоит
	     невидимый курсор: подсветка обновляется в RenderStepped и на первом
	     касании ещё указывает в прежнее место.
	     processed = true означает, что палец попал в интерфейс (хотбар,
	     кнопки) — там подбирать нечего. ]]
	if IS_PHONE and not processed
		and input.UserInputType == Enum.UserInputType.Touch then
		local res = getDroppedItemAt(input.Position.X, input.Position.Y)
		if res then
			pickUp(res)
			return
		end
	end

	-- E key pickup - don't check 'processed' because our billboard GUI causes it to be true
	if GamepadInput.isKey(input, Enum.KeyCode.E) then
		if currentTarget and currentTarget.Parent then
			pickUp(currentTarget)
			return
		end
	end

	-- Q key drop from hovered hotbar slot
	if processed then return end
	if GamepadInput.isKey(input, Enum.KeyCode.Q) then
		-- While a full-screen overlay (e.g. the phone) is up the Q
		-- key is reserved for that overlay's own binding — the BACK
		-- hotkey on every phone sub-page uses Q. Dropping the hovered
		-- hotbar item when the player is navigating the phone menu
		-- is the bug this guard prevents.
		local phone = _G.PhoneScreenGui
		if phone and phone:IsA("ScreenGui") and phone.Enabled then
			return
		end

		local slotIndex = getHoveredHotbarSlot()
		if not slotIndex then return end

		local slotData = _G.InventorySlotData
		if not slotData then return end

		local data = slotData[slotIndex]
		if not data then return end

		if data.type == "resource" then
			if data.count <= 1 then
				slotData[slotIndex] = nil
			else
				data.count = data.count - 1
			end
			local dropPos = getMouseWorldPosition()
			dropEvent:FireServer(data.name, 1, dropPos)
		elseif data.type == "tool" then
			slotData[slotIndex] = nil
			local dropPos = getMouseWorldPosition()
			dropEvent:FireServer(data.toolName, 1, dropPos)
		end
	end
end)

-- ─── "Inventory full!" popup ───
local fullGui = Instance.new("ScreenGui")
fullGui.Name = "InventoryFullHint"
fullGui.ResetOnSpawn = false   -- иначе Roblox удаляет окно при смерти, а скрипт живёт дальше с мёртвым объектом
fullGui.DisplayOrder = 60
fullGui.IgnoreGuiInset = true
fullGui.Parent = playerGui

local fullLabel = Instance.new("TextLabel")
fullLabel.Name = "FullText"
fullLabel.AnchorPoint = Vector2.new(0.5, 0.5)
fullLabel.Position = UDim2.new(0.5, 0, 0.4, 0)
fullLabel.Size = UDim2.new(0, 280, 0, 40)
fullLabel.BackgroundTransparency = 1
fullLabel.Text = "Инвентарь полон!"
fullLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
fullLabel.TextSize = 24
fullLabel.Font = Enum.Font.GothamBold
fullLabel.TextStrokeTransparency = 0.4
fullLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
fullLabel.Visible = false
fullLabel.Parent = fullGui

pickupEvent.OnClientEvent:Connect(function(action)
	if action == "inventoryFull" then
		fullLabel.Visible = true
		fullLabel.TextTransparency = 0
		fullLabel.TextStrokeTransparency = 0.4
		task.spawn(function()
			task.wait(1.2)
			for i = 0, 10 do
				fullLabel.TextTransparency = i / 10
				fullLabel.TextStrokeTransparency = 0.4 + (i / 10) * 0.6
				task.wait(0.04)
			end
			fullLabel.Visible = false
			fullLabel.TextTransparency = 0
			fullLabel.TextStrokeTransparency = 0.4
		end)
	end
end)