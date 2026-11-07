--[[
	ИЗНОС ИНСТРУМЕНТОВ И ОРУЖИЯ.

	Одно применение — минус единица прочности. Дошло до нуля — тул ломается и
	исчезает, игроку уходит уведомление.

	ЛОВИМ Tool.Activated НА СЕРВЕРЕ. Это единственная точка, общая для всех тулов:
	топор шлёт свой ремоут, ствол — свой, у еды и вовсе собственный скрипт внутри
	модели, и цепляться к каждой системе отдельно значило бы забыть половину.
	Activated же реплицируется на сервер при любом клике с тулом в руках (этим уже
	пользуется FoodSystem), поэтому счёт применений одинаково работает для всего.

	Что изнашивается и с каким запасом — в ReplicatedStorage.ToolDurability.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")

local ToolDurability = require(ReplicatedStorage:WaitForChild("ToolDurability"))
local AssetFind      = require(ReplicatedStorage:WaitForChild("AssetFind"))

-- Клик засчитывается не чаще, чем раз в это время. Без окна серия быстрых кликов
-- «в молоко» (замах ещё на перезарядке, урона нет) съедала бы прочность за секунды.
local MIN_USE_INTERVAL = 0.15

local brokenEvent = ReplicatedStorage:FindFirstChild("ToolBroken")
if not brokenEvent then
	brokenEvent = Instance.new("RemoteEvent")
	brokenEvent.Name = "ToolBroken"
	brokenEvent.Parent = ReplicatedStorage
end

-- Слабые ключи: тул уничтожили — записи уходят вместе с ним, чистить руками
-- ничего не надо.
local hooked  = setmetatable({}, { __mode = "k" })
local lastUse = setmetatable({}, { __mode = "k" })

local function ownerOf(tool)
	local parent = tool.Parent
	if not parent then return nil end
	local player = Players:GetPlayerFromCharacter(parent)   -- в руках
	if player then return player end
	if parent:IsA("Backpack") then return parent.Parent end -- в рюкзаке
	return nil
end

-- ЗВУК ПОЛОМКИ ПО МАТЕРИАЛУ. Ищем по цепочке из ToolDurability.BREAK_SOUNDS:
-- сперва звуки, которые в игре уже есть, и только потом встроенный в клиент.
-- Возвращает ГОТОВЫЙ К ИГРЕ клон (оригинал не трогаем, иначе правка тона осталась
-- бы на нём во всей остальной игре) или nil.
local function buildBreakSound(material)
	local spec = ToolDurability.BREAK_SOUNDS[material] or ToolDurability.BREAK_SOUNDS.wood
	if not spec then return nil end
	local src

	for _, pair in ipairs(spec.templates or {}) do
		local model = AssetFind.find(pair[1])
		local snd = model and model:FindFirstChild(pair[2], true)
		if snd and snd:IsA("Sound") then src = snd break end
	end
	if not src then
		for _, name in ipairs(spec.service or {}) do
			local snd = SoundService:FindFirstChild(name, true)
			if snd and snd:IsA("Sound") then src = snd break end
		end
	end

	local clone
	if src then
		clone = src:Clone()
	else
		for _, id in ipairs(spec.ids or {}) do
			clone = Instance.new("Sound")
			clone.SoundId = id
			break
		end
	end
	if not clone then return nil end

	clone.Volume = spec.volume or 1
	clone.PlaybackSpeed = spec.pitch or 1
	return clone, spec.start or 0
end

-- Играем 3D-звуком в точке поломки, как это делает рубка деревьев: слышно всем
-- рядом, а не только владельцу.
local function playBreakSound(material, position)
	if not position then return end
	local snd, start = buildBreakSound(material)
	if not snd then
		warn(("[Прочность] нет звука поломки для материала «%s»"):format(tostring(material)))
		return
	end
	local attach = Instance.new("Attachment")
	attach.WorldPosition = position
	attach.Parent = workspace.Terrain
	snd.Parent = attach
	-- ⚠️ TimePosition ставится ПОСЛЕ Play: до старта движок его сбрасывает, и
	-- обрезка тишины в начале файла не срабатывает (уже наступали на это).
	snd.TimePosition = start
	snd:Play()
	snd.TimePosition = start
	Debris:AddItem(attach, (snd.TimeLength > 0 and snd.TimeLength or 2) + 0.5)
end

local function breakTool(tool)
	local player = ownerOf(tool)
	local name = tool.Name
	local material = ToolDurability.materialFor(name)

	-- позицию берём ДО Destroy: у рукояти она точнее, чем у игрока
	local handle = tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart")
	local pos = handle and handle.Position
	if not pos and player and player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		pos = hrp and hrp.Position
	end

	if player then
		brokenEvent:FireClient(player, name)
	end
	print(("[Прочность] %s (%s) сломался у %s")
		:format(name, material, player and player.Name or "?"))
	tool:Destroy()
	playBreakSound(material, pos)
end

local function spend(tool)
	local cur = tool:GetAttribute(ToolDurability.ATTR_CUR)
	if type(cur) ~= "number" then return end

	local now = os.clock()
	local prev = lastUse[tool]
	if prev and now - prev < MIN_USE_INTERVAL then return end
	lastUse[tool] = now

	cur = math.max(0, cur - ToolDurability.costFor(tool.Name))
	tool:SetAttribute(ToolDurability.ATTR_CUR, cur)
	if cur <= 0 then breakTool(tool) end
end

local function initTool(tool)
	if not tool:IsA("Tool") then return end
	local max = ToolDurability.maxFor(tool.Name)
	if not max then return end   -- расходники и постройки не изнашиваются

	if type(tool:GetAttribute(ToolDurability.ATTR_MAX)) ~= "number" then
		tool:SetAttribute(ToolDurability.ATTR_MAX, max)
	end
	if type(tool:GetAttribute(ToolDurability.ATTR_CUR)) ~= "number" then
		-- ПОДОБРАННЫЙ ТУЛ МОЖЕТ ПРИЙТИ УЖЕ ПОТРЁПАННЫМ: если Durability уже стоит,
		-- не восстанавливаем его до максимума.
		tool:SetAttribute(ToolDurability.ATTR_CUR, tool:GetAttribute(ToolDurability.ATTR_MAX))
	end

	if hooked[tool] then return end
	hooked[tool] = true
	tool.Activated:Connect(function() spend(tool) end)
end

-- Тулы приходят отовсюду: крафт, рюкзак с лутом, выдача при спавне, подбор с
-- земли. Поэтому не перечисляем источники, а слушаем сам контейнер игрока.
local function watchContainer(container)
	if not container then return end
	for _, d in ipairs(container:GetDescendants()) do initTool(d) end
	container.DescendantAdded:Connect(initTool)
end

local function onPlayer(player)
	watchContainer(player:FindFirstChildOfClass("Backpack"))
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then watchContainer(child) end
	end)
	local function onChar(char) watchContainer(char) end
	if player.Character then onChar(player.Character) end
	player.CharacterAdded:Connect(onChar)
end

for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end
Players.PlayerAdded:Connect(onPlayer)

print("[Прочность] износ тулов включён (оружие "
	.. ToolDurability.DEFAULT_MAX .. ", огнестрел " .. ToolDurability.FIREARM_MAX .. ")")
