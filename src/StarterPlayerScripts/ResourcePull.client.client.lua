local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))
local camera = workspace.CurrentCamera

local collectEvent = ReplicatedStorage:WaitForChild("CollectResource")
local collectNotify = ReplicatedStorage:WaitForChild("CollectNotify")

--[[ ⚠️ ДО ЦЕЛИ НАДО ЕЩЁ ДОСТАТЬ, И СЧИТАТЬ ЭТО ОБЯЗАН КЛИЕНТ.
     Прицельный луч бьёт на 200 студов — столько нужно, чтобы разглядеть и
     подсветить бревно вдалеке. А добыть его сервер разрешает с 60
     (ResourceSpawner, COLLECT_RANGE) и лишний удар просто молча выбрасывает.
     Клиент об этом не знал: рука махала, летели щепки, звучал «хруст» — вся
     обратная связь удара была, кроме самого удара. Ровно на это и жаловались.

     ⚠️ МЕРЯЕМ ТЕМ ЖЕ СПОСОБОМ, ЧТО И СЕРВЕР.
     От HumanoidRootPart игрока (не от камеры: в третьем лице она позади) до
     пивота модели или позиции детали — буквально как в ResourceSpawner. Иначе
     на границе появится полоса, где клиент бить разрешает, а сервер отбрасывает.

     ⚠️ ЗАПАСА НЕТ, И ЭТО ОСОЗНАННО.
     Сначала я дал клиенту восемь студов сверх серверных — на задержку реплики
     плывущего бревна. Вышло ровно то, на что жаловались: рука махала примерно
     на пять студов дальше, чем засчитывался удар, то есть обещание удара снова
     оказалось шире самого удара, просто на меньшей дистанции.
     Граница у анимации и у добычи должна быть одна. Ценой этого редкий удар в
     упор к границе может пропасть из-за лага — но «махнул и ничего» на кромке
     заметно меньше, чем стабильная зона обмана. ]]
local REACH_SLACK = 0

local function reachLimit()
	local v = ReplicatedStorage:GetAttribute("ResourceCollectRange")
	return (tonumber(v) or 60) + REACH_SLACK
end

local function distanceTo(resource)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and resource) then return nil end
	local pos
	if resource:IsA("Model") then
		pos = resource:GetPivot().Position
	elseif resource:IsA("BasePart") then
		pos = resource.Position
	else
		return nil
	end
	return (hrp.Position - pos).Magnitude
end

-- Дотягиваемся ли до цели. Бочка — исключение: её замок сервер открывает
-- раньше собственной проверки дистанции (ResourceSpawner, ветка BarrelLocked),
-- и глушить клик по ней клиентом значило бы отобрать вскрытие издалека.
local function withinReach(resource)
	if not resource then return false end
	if resource:GetAttribute("BarrelLocked") then return true end
	local d = distanceTo(resource)
	return (d == nil) or (d <= reachLimit())
end

local currentHighlight = nil
local currentTarget = nil
local hitPart = nil
local progressBillboards = {}

-- ⚠️ НА ТЕЛЕФОНЕ ЛУЧ ИДЁТ ИЗ ТОЧКИ ТАПА, А НЕ ИЗ «МЫШИ».
-- С мыши позиция известна всегда, поэтому подсветка успевает посчитаться в кадре
-- ДО нажатия и клик работал по ней. На телефоне курсора нет вовсе: мышь встаёт в
-- точку тапа в тот же кадр, что и само нажатие, — цель посчитаться не успевала, и
-- первый тап уходил в пустоту. Поэтому позицию можно передать снаружи: обработчик
-- касания даёт её прямо из события.
local function getResourceUnderMouse(atX, atY)
	local ray = camera:ScreenPointToRay(atX or mouse.X, atY or mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {player.Character}

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	if not result or not result.Instance then
		return nil, nil, nil
	end

	local hit = result.Instance

	-- ПИЯВКА — НЕ РЕСУРС (держать равным серверной проверке в ResourceSpawner).
	-- Она внутри модели заражённого бревна с тегом Resource, поэтому наведение и
	-- клик по ней считались добычей бревна: и подсветка не та, и урон не туда.
	if hit:FindFirstAncestor("leech_rigged") then
		return nil, nil, nil
	end

	if CollectionService:HasTag(hit, "Resource") then
		return hit, hit, result.Position
	end

	local model = hit:FindFirstAncestorOfClass("Model")
	if model and CollectionService:HasTag(model, "Resource") then
		return model, hit, result.Position
	end

	return nil, nil, nil
end

-- Все предметы ОДНОЙ сети: улов добывается кучей, поэтому и подсвечивается кучей.
-- Ссылку на сеть кладёт сервер в ObjectValue "CaughtNet" внутри ресурса.
local function netSiblings(resource)
	local nv = resource:FindFirstChild("CaughtNet")
	local net = nv and nv.Value
	if not net then return { resource } end
	local list = {}
	for _, res in ipairs(CollectionService:GetTagged("Resource")) do
		if res.Parent then
			local v = res:FindFirstChild("CaughtNet")
			if v and v.Value == net then list[#list + 1] = res end
		end
	end
	if #list == 0 then list[1] = resource end
	return list
end

local function clearHighlight()
	if currentHighlight then
		-- currentHighlight — список: у кучи в сети подсвечен каждый предмет
		if type(currentHighlight) == "table" then
			for _, h in ipairs(currentHighlight) do
				if h and h.Parent then h:Destroy() end
			end
		else
			currentHighlight:Destroy()
		end
		currentHighlight = nil
	end
	currentTarget = nil
	hitPart = nil
end

local function getAdornee(resource)
	-- ⚠️ У ОСЬМИНОГА ПИВОТ — ЭТО НЕПОДВИЖНЫЙ ЯКОРЬ.
	-- Его PrimaryPart — невидимый HumanoidRootPart: он заанкорен и стоит на месте,
	-- а качается, всплывает и тонет ГОЛОВА, её двигает сустав. Полоса, привязанная
	-- к якорю, так и висела в стороне, пока туша ходила вверх-вниз. Цепляем к тому,
	-- что действительно движется.
	if resource:GetAttribute("IsOctopus") then
		local head = resource:FindFirstChild("head", true)
		if head and head:IsA("BasePart") then return head end
	end
	if resource:IsA("Model") and resource.PrimaryPart then
		return resource.PrimaryPart
	elseif resource:IsA("BasePart") then
		return resource
	end
	local first = resource:FindFirstChildWhichIsA("BasePart", true)
	return first or resource
end

local function getOrCreateProgressUI(resource)
	if progressBillboards[resource] then
		return progressBillboards[resource]
	end

	local adornee = getAdornee(resource)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(4, 0, 0.5, 0)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = adornee
	billboard.Parent = playerGui

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bg.BackgroundTransparency = 0.3
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	fill.BackgroundTransparency = 0.1
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.3, 0)
	fillCorner.Parent = fill

	progressBillboards[resource] = billboard
	return billboard
end

-- ⚠️ ПОЛОСА ПРОЧНОСТИ ТОЖЕ РЕАГИРУЕТ НА УДАР.
-- Раньше она просто плавно уезжала, и удар читался только по самому предмету.
-- Теперь на каждое попадание она дёргается и краснеет: без этого при быстрых
-- кликах не видно, засчитался удар или нет.
local barShakeK = {}   -- [ресурс] = сколько ещё тряски осталось

local function punchProgress(billboard, bg)
	if not (billboard and bg) then return end
	-- вспышка: цвет уходит в белый и возвращается к зелёному
	local fill = bg:FindFirstChild("Fill")
	if fill then
		fill.BackgroundColor3 = Color3.fromRGB(255, 245, 200)
		TweenService:Create(fill, TweenInfo.new(0.18),
			{ BackgroundColor3 = Color3.fromRGB(80, 200, 80) }):Play()
	end
	-- рывок вверх и обратно: у BillboardGui это StudsOffset, он экранный, поэтому
	-- смещение видно при любом положении предмета
	billboard.StudsOffset = Vector3.new(0, 3.35, 0)
	TweenService:Create(billboard, TweenInfo.new(0.16, Enum.EasingStyle.Back,
		Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 3, 0) }):Play()
end

local function updateProgress(resource, clicks, maxClicks)
	local billboard = getOrCreateProgressUI(resource)
	local bg = billboard:FindFirstChildWhichIsA("Frame")
	local fill = bg:FindFirstChild("Fill")

	local ratio = clicks / maxClicks
	TweenService:Create(fill, TweenInfo.new(0.15), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
	punchProgress(billboard, bg)
end

local function removeProgress(resource)
	if progressBillboards[resource] then
		progressBillboards[resource]:Destroy()
		progressBillboards[resource] = nil
	end
end

-- ⚠️ ПОЛОСА НЕ ПРОСТО ГАСНЕТ — ОНА СТАНОВИТСЯ НАДПИСЬЮ.
-- Осьминога бьют три десятка раз, и просто исчезнувшая полоса читается как
-- «сорвалось», а не «добил»: туша при этом ещё разваливается на куски, то есть
-- на экране движение, а итога нет. Слово держится секунду и уходит вверх.
local function defeatProgress(resource)
	local billboard = progressBillboards[resource]
	if not billboard then return end
	progressBillboards[resource] = nil    -- дальше борд живёт сам и сам себя убирает

	local bg = billboard:FindFirstChildWhichIsA("Frame")
	if bg then
		local fill = bg:FindFirstChild("Fill")
		if fill then fill:Destroy() end
		bg.BackgroundTransparency = 1
	end

	-- Борд под полосу узкий (4 × 0.5 стада), в него слово влезает мелким. Раз
	-- полосы больше нет, места можно занять сколько нужно — надпись читается с
	-- той же дистанции, с которой по осьминогу били.
	billboard.Size = UDim2.new(9, 0, 2.2, 0)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "ПОБЕЖДЁН"
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 235, 150)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.15
	label.Parent = bg or billboard

	TweenService:Create(billboard, TweenInfo.new(1.4),
		{ StudsOffset = Vector3.new(0, 5, 0) }):Play()
	task.delay(0.9, function()
		if not label.Parent then return end
		TweenService:Create(label, TweenInfo.new(0.5),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	Debris:AddItem(billboard, 1.6)
end

-- ⚠️ rbxasset://, А НЕ rbxassetid://.
-- Это встроенный в клиент всплеск (тот же, что у падения игрока в воду): он не
-- требует прав на ассет и не может отвалиться с «User is not authorized» —
-- этим в проекте уже отмечена не одна чужая звуковая айдишка. Тон занижен: на
-- полной скорости это плюх с ботинка, а тут тонет туша. Если в SoundService
-- положат свой звук «Octopus_Death», играем его — как у Plastic Break.
local function playOctopusDeathSound()
	local custom = (SoundService:FindFirstChild("Octopus_Death") or SoundService:FindFirstChild("Octopus_Death", true))
	local snd
	if custom and custom:IsA("Sound") then
		snd = custom:Clone()
	else
		snd = Instance.new("Sound")
		snd.SoundId = "rbxasset://sounds/impact_water.mp3"
		snd.Volume = 1.8
		snd.PlaybackSpeed = 0.5
	end
	snd.Parent = SoundService
	snd:Play()
	Debris:AddItem(snd, 6)
end

local RESOURCE_ICONS = {
	Log = "rbxassetid://116178347748793",
	Plastic = "rbxassetid://132919988751848",
	Leaves = "rbxassetid://96691360298069",
	Compost = "rbxassetid://78760258555926",
}

local function showCollectedPopup(worldPos, resType, resAmount)
	local screenPos, onScreen = camera:WorldToScreenPoint(worldPos)
	if not onScreen then return end

	local amount = resAmount or 1
	local iconId = RESOURCE_ICONS[resType or "Log"] or "rbxassetid://116178347748793"

	local screenGui = Instance.new("ScreenGui")
	screenGui.Parent = playerGui

	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, 120, 0, 50)
	container.Position = UDim2.new(0, screenPos.X - 60, 0, screenPos.Y - 25)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 50, 1, 0)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = "+ " .. tostring(amount)
	label.TextColor3 = Color3.fromRGB(255, 220, 100)
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = container

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0, 40, 0, 40)
	icon.Position = UDim2.new(0, 55, 0.5, -20)
	icon.BackgroundTransparency = 1
	icon.Image = iconId
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = container

	local startY = screenPos.Y - 25
	local tweenUp = TweenService:Create(container, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, screenPos.X - 60, 0, startY - 50),
	})
	local tweenFadeText = TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	local tweenFadeIcon = TweenService:Create(icon, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		ImageTransparency = 1,
	})
	tweenUp:Play()
	tweenFadeText:Play()
	tweenFadeIcon:Play()
	tweenUp.Completed:Connect(function()
		screenGui:Destroy()
	end)
end

local lastResourcePositions = {}

-- ─── Break-sound playback (client-side) ──────────────────────────────────────
-- Sounds are played on the client (not the server) so the local player gets
-- zero-latency feedback on the final hit. The server tells every client when
-- a resource breaks ("broke" notify) and the local player additionally
-- predicts the last hit on the click itself, so the sound plays the instant
-- the player presses the mouse instead of after a server round-trip.

local function playBreakSound(resType, resource)
	if resType == "Leaves" then
		if resource and resource.Parent then
			local ruinSound = resource:FindFirstChild("Ruin_Leaves", true)
			if ruinSound and ruinSound:IsA("Sound") then
				local clone = ruinSound:Clone()
				clone.Parent = workspace
				clone:Play()
				Debris:AddItem(clone, 5)
			end
		end
	elseif resType == "Log" then
		if resource and resource.Parent then
			local woodBreak = resource:FindFirstChild("Wood Break", true)
			if woodBreak and woodBreak:IsA("Sound") then
				local clone = woodBreak:Clone()
				clone.Parent = workspace
				clone:Play()
				Debris:AddItem(clone, 5)
			end
		end
	elseif resType == "Plastic" then
		local plasticBreak = (SoundService:FindFirstChild("Plastic Break") or SoundService:FindFirstChild("Plastic Break", true))
		if plasticBreak and plasticBreak:IsA("Sound") then
			local clone = plasticBreak:Clone()
			clone.Parent = SoundService
			clone:Play()
			Debris:AddItem(clone, 5)
		end
	elseif resType == "Rock" then
		local rockCrush = (SoundService:FindFirstChild("Rock_Crush") or SoundService:FindFirstChild("Rock_Crush", true))
		if rockCrush and rockCrush:IsA("Sound") then
			local clone = rockCrush:Clone()
			clone.Parent = SoundService
			clone:Play()
			Debris:AddItem(clone, 5)
		end
	end
end

-- Weak tables so destroyed resources are GC'd out automatically.
local localClicksSent = setmetatable({}, {__mode = "k"})
local clicksNeeded = setmetatable({}, {__mode = "k"})
local predictedBreaks = setmetatable({}, {__mode = "k"})

collectNotify.OnClientEvent:Connect(function(action, resource, arg3, arg4)
	if action == "progress" then
		-- arg3 = clicks, arg4 = maxClicks
		updateProgress(resource, arg3, arg4)
		-- Sync local prediction state with the server's authoritative count.
		-- Use max() so an in-flight optimistic increment from a recent click
		-- doesn't get overwritten by a slightly older "progress" reply.
		localClicksSent[resource] = math.max(localClicksSent[resource] or 0, arg3)
		clicksNeeded[resource] = arg4
		local adornee = getAdornee(resource)
		if adornee and adornee:IsA("BasePart") then
			lastResourcePositions[resource] = adornee.Position
		end
	elseif action == "collected" then
		-- arg3 = resType, arg4 = resAmount
		local worldPos = lastResourcePositions[resource]
		if not worldPos then
			local adornee = getAdornee(resource)
			if adornee and adornee:IsA("BasePart") then
				worldPos = adornee.Position
			end
		end
		removeProgress(resource)
		clearHighlight()
		lastResourcePositions[resource] = nil
		if worldPos then
			showCollectedPopup(worldPos, arg3, arg4)
		end
	elseif action == "inventoryFull" then
		local screenGui = Instance.new("ScreenGui")
		screenGui.DisplayOrder = 60
		screenGui.IgnoreGuiInset = true
		screenGui.Parent = playerGui

		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, 0.4, 0)
		label.Size = UDim2.new(0, 280, 0, 40)
		label.BackgroundTransparency = 1
		label.Text = "Инвентарь полон!"
		label.TextColor3 = Color3.fromRGB(255, 80, 80)
		label.TextSize = 24
		label.Font = Enum.Font.GothamBold
		label.TextStrokeTransparency = 0.4
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.Parent = screenGui

		task.spawn(function()
			task.wait(1.2)
			for i = 0, 10 do
				label.TextTransparency = i / 10
				label.TextStrokeTransparency = 0.4 + (i / 10) * 0.6
				task.wait(0.04)
			end
			screenGui:Destroy()
		end)
	elseif action == "progressClear" then
		-- общий бар кучи в сети: сервер добил улов → снимаем бар с модели сети
		removeProgress(resource)
		localClicksSent[resource] = nil
		clicksNeeded[resource] = nil

	elseif action == "broke" then
		-- ⚠️ У ОСЬМИНОГА СМЕРТЬ СВОЯ, А НЕ «звук по типу ресурса».
		-- По типу он «Meat» — это нужно обвязке для иконки, но плюх мясного
		-- куска на добитую тушу не годится. И полосу ему снимать некому:
		-- «collected» для него сервер не шлёт, добычу выдаёт OctopusKilled.
		if typeof(resource) == "Instance" and resource:GetAttribute("IsOctopus") then
			predictedBreaks[resource] = nil
			defeatProgress(resource)
			playOctopusDeathSound()
			clearHighlight()
			return
		end
		-- arg3 = resType. The clicker pre-played this on prediction, so we
		-- consume the flag and skip; everyone else plays the sound now.
		if predictedBreaks[resource] then
			predictedBreaks[resource] = nil
		else
			playBreakSound(arg3, resource)
		end
	end
end)

RunService.RenderStepped:Connect(function()
	local resource, part = getResourceUnderMouse()

	if resource == currentTarget then
		return
	end

	clearHighlight()

	if resource then
		currentTarget = resource
		hitPart = part
		-- подсвечиваем ВСЮ кучу в сети (для одиночного ресурса это он сам)
		local hls = {}
		for _, res in ipairs(netSiblings(resource)) do
			-- ⚠️ ТОЛЬКО ОБВОДКА, БЕЗ ЗАЛИВКИ.
			-- Заливка перекрашивала сам предмет и съедала его собственный цвет:
			-- осьминог под курсором становился белесым пятном, по которому не
			-- прочесть ни морду, ни щупальца. Обводка показывает, ЧТО наведено,
			-- не подменяя предмет — так же сделана квестовая подсветка
			-- (Quests/TrackerCard).
			-- ⚠️ Обводка всегда белая. Я пробовал красить недосягаемые цели в
			-- оранжевый — по просьбе владельца убрано: цветовая тревога на
			-- каждом дальнем бревне мельтешит сильнее, чем помогает.
			local highlight = Instance.new("Highlight")
			highlight.FillTransparency = 1
			highlight.OutlineColor = Color3.new(1, 1, 1)
			highlight.OutlineTransparency = 0
			highlight.Parent = res
			hls[#hls + 1] = highlight
		end
		currentHighlight = hls
	end
end)

-- ═══════════ ВЗМАХ ПРАВОЙ РУКОЙ ПРИ УДАРЕ ═══════════
-- ⚠️ СДЕЛАНО ПО ОБРАЗЦУ ОГНЕМЁТА (FlamethrowerClient) И КАРТЫ (MapItem).
-- Два предыдущих захода не работали, потому что исходили из обычного рига:
--   • первый крутил Motor6D — их у здешнего персонажа НЕТ НИ ОДНОГО (это прямо
--     сказал лог), части держит AnimationConstraint;
--   • второй писал в C0 — у AnimationConstraint такого поля нет вовсе.
-- Рабочий приём в проекте один и тот же: найти «сустав» по имени ДЕТАЛИ, писать
-- в его Transform, делать это ПОСЛЕ аниматора (BindToRenderStep с приоритетом
-- Character + 1) и повторять в Stepped — у физического рига Transform это ЦЕЛЬ
-- для решателя, и на шаге физики он берёт то, что осталось от аниматора.
--
-- Задержки между ударами нет, поэтому взмах короткий и каждый клик запускает его
-- заново: жмёшь чаще — рука машет чаще. Отсчёт по времени, а не твином: повторный
-- клик просто сдвигает начало, и рука не застревает на полпути прерванного твина.
local SWING_TIME  = 0.16   -- полный цикл: замах и возврат
-- ⚠️ ЗНАК ПО X: ПОЛОЖИТЕЛЬНЫЙ — ВПЕРЁД-ВНИЗ.
-- Первый заход брал минус, и рука уходила ВВЕРХ И НАЗАД, за плечо. Отсчёт идёт от
-- штатной роблоксовской позы «рука вытянута вперёд», то есть от горизонтали:
-- минус поднимает её над головой, плюс опускает вперёд и вниз — это и есть удар.
-- Ровно та же логика знаков расписана в POSE_IDLE у огнемёта.
local SWING_X = 110        -- градусов: размах удара вперёд-вниз
-- Боковая составляющая: она и делает движение ДУГОЙ, а не прямой линией.
-- Правая рука сперва уходит наружу (вправо), затем проносится внутрь, к центру и
-- дальше влево — то есть рубит по косой, как и нарисовано.
local SWING_SIDE = 38      -- градусов в каждую сторону от оси

-- Имена детали правой руки на всех ригах, которые встречаются в проекте.
local ARM_NAMES = { ["Right Arm"] = true, ["RightUpperArm"] = true }

local swingStart, armJoint, physicalRig, scannedChar = nil, nil, false, nil

-- Ищем ровно так же, как collectMotors у огнемёта: по ДЕТАЛИ, к которой сустав
-- приделан, и принимаем все три вида сочленений, что бывают у здешних ригов.
local function findArmJoint(char)
	physicalRig = false
	for _, d in ipairs(char:GetDescendants()) do
		local limb
		if d:IsA("AnimationConstraint") then
			limb = d.Attachment1 and d.Attachment1.Parent and d.Attachment1.Parent.Name
			if limb and ARM_NAMES[limb] then
				physicalRig = true
				return d
			end
		elseif d:IsA("Motor6D") then
			limb = d.Part1 and d.Part1.Name
			if limb and ARM_NAMES[limb] then return d end
		elseif d:IsA("Bone") then
			if ARM_NAMES[d.Name] then return d end
		end
	end
	return nil
end

local function bindArm(char)
	swingStart, armJoint, scannedChar = nil, nil, char
	if not char then return end
	armJoint = findArmJoint(char)
end

-- ═══════════ ВСПЛЕСК В ТОЧКЕ УДАРА ═══════════
-- ⚠️ РИСУЕМ ЛОКАЛЬНО, БЕЗ РЕМОУТА.
-- Точка попадания известна прямо здесь, в момент клика. Гонять её на сервер и
-- обратно ради искр значило бы показывать их с задержкой круга — то есть ровно
-- там, где предмет уже уплыл. Чужие удары и так видны по тряске самого предмета.
--
-- Цвет берём у РЕСУРСА: щепки от бревна должны быть деревянными, а от листвы —
-- зелёными. Один и тот же серый пшик на всё выглядел бы как ошибка.
local HIT_COLORS = {
	Log     = Color3.fromRGB(150, 100, 55),
	Leaves  = Color3.fromRGB(90, 190, 80),
	Compost = Color3.fromRGB(110, 80, 45),
	Plastic = Color3.fromRGB(200, 210, 225),
	Stone   = Color3.fromRGB(160, 160, 165),
	Barrel  = Color3.fromRGB(150, 100, 55),
}

local hitFxTemplate
local function makeHitFxTemplate()
	local p = Instance.new("Part")
	p.Name = "HitFx"
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false

	local burst = Instance.new("ParticleEmitter")
	burst.Name = "Burst"
	burst.Rate = 0
	burst.Speed = NumberRange.new(7, 13)
	burst.Lifetime = NumberRange.new(0.18, 0.34)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Drag = 6
	burst.Rotation = NumberRange.new(0, 360)
	burst.RotSpeed = NumberRange.new(-240, 240)
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.32),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	burst.LightEmission = 0.35
	burst.Parent = p

	-- короткая вспышка: она и «ставит точку» удара, пока щепки разлетаются
	local flash = Instance.new("PointLight")
	flash.Name = "Flash"
	flash.Range = 7
	flash.Brightness = 2
	flash.Parent = p

	return p
end

local function playHitFx(worldPos, resType)
	if typeof(worldPos) ~= "Vector3" then return end
	if not hitFxTemplate then hitFxTemplate = makeHitFxTemplate() end

	local colour = HIT_COLORS[resType or ""] or Color3.fromRGB(220, 220, 220)
	local fx = hitFxTemplate:Clone()
	fx.CFrame = CFrame.new(worldPos)
	fx.Parent = workspace

	local burst = fx:FindFirstChild("Burst")
	if burst then
		burst.Color = ColorSequence.new(colour)
		burst:Emit(14)
	end
	local flash = fx:FindFirstChild("Flash")
	if flash then
		flash.Color = colour
		TweenService:Create(flash, TweenInfo.new(0.18), { Brightness = 0 }):Play()
	end
	Debris:AddItem(fx, 0.8)
end

local function swing()
	local char = player.Character
	if not char then return end
	-- пересобираем при смене персонажа: старый сустав уже мёртв
	if scannedChar ~= char or not (armJoint and armJoint.Parent) then bindArm(char) end
	if armJoint then swingStart = os.clock() end
end

-- Один и тот же расчёт для обоих мест записи: и при отрисовке, и на шаге физики.
local function applySwing()
	if not (swingStart and armJoint and armJoint.Parent) then return false end
	local t = (os.clock() - swingStart) / SWING_TIME
	if t >= 1 then
		armJoint.Transform = CFrame.identity
		swingStart = nil
		return false
	end
	-- Размах: sin(pi·t) даёт 0 → 1 → 0 за цикл — резкий удар и такой же возврат.
	local x = SWING_X * math.sin(t * math.pi)
	-- ⚠️ ДУГА ДЕЛАЕТСЯ ВТОРОЙ ГАРМОНИКОЙ, А НЕ ВТОРЫМ ЗАМАХОМ.
	-- sin(2π·t) за тот же цикл проходит 0 → +1 → 0 → −1 → 0: рука уходит вправо,
	-- к середине удара возвращается на ось и дальше проносится влево, к центру.
	-- Получается косой мах по дуге. Обычный sin(π·t) здесь дал бы отклонение в одну
	-- сторону — то есть ту же прямую, только наклонную.
	local z = SWING_SIDE * math.sin(t * 2 * math.pi)
	armJoint.Transform = CFrame.Angles(math.rad(x), 0, math.rad(z))
	return true
end

--[[ ⚠️ МАХ РУКОЙ ОТДАЁМ НАРУЖУ — ОН НУЖЕН НЕ ТОЛЬКО ЗДЕСЬ.
     Лебёдка якоря крутится теми же движениями: игрок бьёт по вороту, а не
     нажимает кнопку в воздухе. Заводить там вторую такую же анимацию значило
     бы развести две копии одного маха — и они разошлись бы при первой же
     правке, как это уже случилось с подсветкой ресурсов.
     Отдаём ГОТОВУЮ: она сама пересобирается при смене персонажа и сама
     умеет физический риг. Имя в общем стиле проекта — _G.PlayHammerSwing
     рядом делает то же для молотка. ]]
_G.PlayResourceSwing = swing

RunService:BindToRenderStep("ResourceSwing",
	Enum.RenderPriority.Character.Value + 1, applySwing)

-- Физический риг читает цель на шаге физики, а не при отрисовке: без повтора
-- решатель возьмёт то, что оставил аниматор, и взмаха снова не будет видно.
RunService.Stepped:Connect(function()
	if physicalRig then applySwing() end
end)

player.CharacterAdded:Connect(function(char)
	swingStart, armJoint, scannedChar = nil, nil, nil
	task.defer(bindArm, char)
end)
bindArm(player.Character)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	-- ⚠️ ТАП ПРИНИМАЕМ НАРАВНЕ С ЛКМ.
	-- Здесь стоял только MouseButton1, а он на телефоне не приходит НИКОГДА —
	-- отсюда «с телефона нельзя добывать ресурсы». Touch даёт то же событие.
	-- ⚠️ и правый курок геймпада: курсор на нём заперт в центре (GamepadAdapter),
	-- поэтому mouse.X/Y ниже уже указывают в прицел
	local isHit = GamepadInput.isPrimary(input)
	if isHit then
		-- на телефоне цель считаем по точке касания: подсветка в этом кадре ещё не
		-- успела обновиться, потому что курсора, который ходил бы заранее, нет
		if input.UserInputType == Enum.UserInputType.Touch then
			local pos = input.Position
			local t, p = getResourceUnderMouse(pos.X, pos.Y)
			if t and p then currentTarget, hitPart = t, p end
		end
		--[[ ⚠️ НЕ ДОСТАЁМ — НЕ МАШЕМ ВООБЩЕ.
		     Гейт стоит ДО swing(), и это важно: под ним же остаются щепки,
		     предсказание звука поломки и сама отправка на сервер. Прикрыть один
		     замах было бы полумерой — ложная обратная связь просто стала бы
		     тише, а локальный счётчик кликов всё равно уезжал бы вперёд
		     серверного и потом срывал «хруст» по целому бревну. ]]
		if currentTarget and hitPart and not withinReach(currentTarget) then
			return
		end

		if currentTarget and hitPart then
			swing()
			-- Client-side prediction: if this click will be the last one
			-- (based on the server's last reported click count), play the
			-- break sound immediately so the local player gets zero-latency
			-- audio feedback instead of waiting ~400ms for the server
			-- round-trip. The "broke" notify from the server will arrive
			-- shortly after and be skipped via the predictedBreaks flag.
			local resource = currentTarget
			local prev = localClicksSent[resource] or 0
			local needed = clicksNeeded[resource] or math.huge
			-- ⚠️ СЧИТАЕМ УРОН, А НЕ КЛИКИ.
			-- Сила игрока снимает за удар больше одного очка прочности (см.
			-- Strength.server). Пока здесь прибавлялась единица, предсказание
			-- отставало ровно во столько раз, во сколько прокачана сила: предмет
			-- разлетался молча, а «хруст» звучал уже после серверного ответа.
			local power = player:GetAttribute("HitPower") or 1
			local nextCount = prev + power
			localClicksSent[resource] = nextCount
			-- УЛОВ В СЕТИ НЕ ПРЕДСКАЗЫВАЕМ: там бьётся вся куча разом, и её цена
			-- (первый предмет целиком + доля за каждый следующий) известна только
			-- серверу. По старому одиночному счётчику звук поломки срывался
			-- раньше времени — предмет ещё цел, а «хруст» уже прозвучал.
			-- Ждём серверный "broke": он придёт ровно в момент развала кучи.
			local inNet = resource:GetAttribute("CaughtInNet") == true
			if not inNet and nextCount >= needed and not predictedBreaks[resource] then
				local resType = resource:GetAttribute("ResourceType") or "Log"
				playBreakSound(resType, resource)
				predictedBreaks[resource] = true
			end
			local _, _, hitPos = getResourceUnderMouse() -- exact spot clicked, drives the hit-shake
			-- всплеск рисуем СРАЗУ, до отправки: обратный путь через сервер занял бы
			-- пол-круга, и искры вспыхнули бы там, откуда предмет уже уплыл
			playHitFx(hitPos, resource:GetAttribute("ResourceType"))
			collectEvent:FireServer(hitPart, hitPos)
		end
	end
end)