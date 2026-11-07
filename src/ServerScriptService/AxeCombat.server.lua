-- AxeCombat.server.lua
-- Боевой топор (Tool "Axe"). Обслуживается СНАРУЖИ тула (как RevolverServer): Rojo плохо
-- «усыновляет» тулы, добавленные в Studio, поэтому внутрь ничего не кладём — скрипты-
-- заглушки внутри тула можно удалить. Анимации играет клиент (AxeClient), сервер только
-- валидирует замах и раздаёт урон.
--
-- Урон: атрибут Damage на туле, или IntValue/NumberValue "damage" внутри тула, иначе 15.
-- Цели: любые Humanoid в конусе перед игроком, КРОМЕ игроков и дружественных НПС
-- (RaftFriendly-атрибут, дайвер/механик/корсары/животные).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AxeTools = require(ReplicatedStorage:WaitForChild("AxeTools"))

local RANGE      = 8     -- дальность удара (студы)
local ARC_DOT    = 0.35  -- конус: dot(взгляд, направление на цель) больше этого = в дуге
-- КД чуть больше задержки попадания: при 0.55 быстрые клики успевали засчитать
-- второй удар до того, как доигрывался замах первого — визуально один взмах, а
-- урона два. Те же числа продублированы в RaftDemolish (удар по постройкам).
local COOLDOWN   = 0.8   -- сек между ударами (клиент шлёт чаще — сервер режет)
local DEFAULT_DMG = 15

local FRIENDLY_NAMES = { -- модели, которые топор НЕ бьёт (по началу имени, без регистра)
	"diver", "engeneer", "engineer", "corsair", "cow",
}

local swingRemote = ReplicatedStorage:FindFirstChild("AxeSwing")
if not swingRemote then
	swingRemote = Instance.new("RemoteEvent")
	swingRemote.Name = "AxeSwing"
	swingRemote.Parent = ReplicatedStorage
end

-- Список топоров общий на весь проект (ReplicatedStorage.AxeTools): любой топор
-- оттуда бьёт этим же конусом, рубка деревьев у него своя (StoneAxe).
local function heldAxe(player)
	return AxeTools.held(player)
end

local function axeDamage(tool)
	local attr = tonumber(tool:GetAttribute("Damage"))
	if attr then return attr end
	local v = tool:FindFirstChild("damage") or tool:FindFirstChild("Damage")
	if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then return v.Value end
	return DEFAULT_DMG
end

local function isFriendly(model)
	if model:GetAttribute("RaftFriendly") then return true end
	-- ⚠️ ДИЧЬ БЬЁМ, ДЕКОРАЦИЮ — НЕТ.
	-- «cow» в списке ниже стоит с тех пор, когда корова была живой декорацией.
	-- Но на островах она — добыча со здоровьем, полоской ХП и дропом мяса, и по
	-- одному имени топор отказывался её трогать: квест «убей корову» был
	-- невыполним ничем, кроме пушки. Флаг ставит тот, кто зверя ПОСТАВИЛ
	-- (spawnAnimal), поэтому любая посторонняя модель с именем «Cow» остаётся
	-- неприкосновенной, как и была.
	if model:GetAttribute("Huntable") then return false end
	local n = model.Name:lower()
	for _, f in ipairs(FRIENDLY_NAMES) do
		if n:sub(1, #f) == f then return true end
	end
	return false
end

-- теснейшая модель-предок с Humanoid (как humanoidOf в ShipCombat)
local function humanoidOf(part)
	local inst = part
	while inst and inst ~= workspace do
		if inst:IsA("Model") then
			--[[ ⚠️ НЕ РЕКУРСИВНО. Поиск вглубь находил Humanoid у чужой модели:
			     деталь земли острова → предок «остров» → внутри него, в папке
			     Animals, корова. Замах у любой детали острова бил корову за
			     полкарты («корова умирает, когда машу топором в другом месте»).
			     Humanoid ищем только среди прямых детей каждой модели-предка;
			     вложенные риги всё равно найдутся — мы поднимаемся по цепочке. ]]
			local hum = inst:FindFirstChildWhichIsA("Humanoid")
			if hum then return hum, inst end
		end
		inst = inst.Parent
	end
	return nil
end

local lastSwing = setmetatable({}, { __mode = "k" }) -- [player] = os.clock()

-- САМ УДАР: конус, урон, отдача. Вынесен в функцию, потому что у каменного
-- топора удар засчитывается с задержкой (см. ниже) — и конус надо мерить в
-- МОМЕНТ ПОПАДАНИЯ, по тому, где игрок и цели стоят сейчас, а не на замахе.
local function strike(player, tool)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local dmg = axeDamage(tool)
	local look = hrp.CFrame.LookVector

	-- все Humanoid-цели в радиусе, затем фильтр по конусу перед игроком
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local done = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(hrp.Position, RANGE, params)) do
		local hum, model = humanoidOf(part)
		if hum and model and not done[model] and hum.Health > 0
			and not Players:GetPlayerFromCharacter(model)
			and not isFriendly(model) then
			done[model] = true
			local to = model:GetPivot().Position - hrp.Position
			local flat = Vector3.new(to.X, 0, to.Z)
			if flat.Magnitude < 2 or flat.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit) > ARC_DOT then
				model:SetAttribute("LastHitBy", player.UserId)   -- кто бил последним (IslandQuestSystem)
				hum:TakeDamage(dmg)
				-- лёгкая отдача от удара (не для приваренных к плоту — их держит велд)
				local root = hum.RootPart or model.PrimaryPart
				-- AssemblyRootPart == root — цель свободное тело. Приваренную к чему-то
				-- (пиявка на бревне/сети) не толкаем: пинок ушёл бы всей сборке,
				-- вплоть до плота целиком.
				if root and not root.Anchored and root.AssemblyRootPart == root then
					local away = flat.Magnitude > 0.1 and flat.Unit or look
					root.AssemblyLinearVelocity = root.AssemblyLinearVelocity
						+ away * 8 + Vector3.new(0, 4, 0)
				end
			end
		end
	end
end

-- Задержка попадания — у ВСЕХ топоров, не только каменного: урон проходил в
-- первый же кадр, когда лезвие ещё за головой. Теперь удар засчитывается там,
-- где по анимации топор доходит до цели.
local HIT_DELAY = 0.7

swingRemote.OnServerEvent:Connect(function(player)
	local tool = heldAxe(player)
	if not tool then return end
	local now = os.clock()
	if lastSwing[player] and now - lastSwing[player] < COOLDOWN then return end
	lastSwing[player] = now

	task.delay(HIT_DELAY, function()
		-- удар засчитываем, только если топор всё ещё в руках
		if player.Parent and heldAxe(player) == tool then
			strike(player, tool)
		end
	end)
end)

print("[AxeCombat] ready (Tool 'Axe': урон в конусе, анимации на клиенте)")
