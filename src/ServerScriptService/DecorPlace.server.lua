--[[
	УСТАНОВКА ДЕКОРА НА ПЛОТ (стулья, стол — вкладка «Декор» крафта). Копия
	установщика пугала на список DECOR: имя тула = имя модели. Правила те же,
	что у остальных построек плота: проверка «место занято» (PlaceCheck), сварка
	к плоту, сейв общим путём «1в1», разборка топором.
	(Ниже — исходная шапка пугала.)
	УСТАНОВКА ПУГАЛА НА ПЛОТ. Тул-заготовку "Raft_scarecrow" даёт крафт
	(InventoryCrafting, «Технологии»), призрак ведёт ScarecrowPlace.client, сюда
	приходит CupAction "placeScarecrow" с позой относительно PrimaryPart плота.

	Поведения у пугала на сервере нет: качает его клиент (ScarecrowSway), чаек на
	него сажает SeagullAI — оба находят его сами по MeshPart "raft_scarecrow_base".
	Сохранение — общим путём «1в1» (RaftSaveSystem ищет шаблон по имени модели).
	Разбирается топором, как любая постройка плота (RaftDemolish).
]]

local RaftShake = require(game:GetService("ReplicatedStorage"):WaitForChild("RaftShake"))   -- постройка без рывка плота
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetFind  = require(ReplicatedStorage:WaitForChild("AssetFind"))
local PlaceCheck = require(ReplicatedStorage:WaitForChild("PlaceCheck"))

local DECOR = { Raft_chair = true, Raft_chair_leaf = true, Raft_table_leaves = true,
	-- предметы загона фермы: ставятся ТОЛЬКО на грядку (FarmPropRules)
	Raft_farm_trough = true, Raft_wool_bin = true,
	-- пак декора «Дефолт» (RaftDecor_all)
	RaftDecor_bunting = true, RaftDecor_can_flower = true, RaftDecor_deckchair = true, RaftDecor_lantern = true, RaftDecor_lifebuoy = true, RaftDecor_rug = true, RaftDecor_shelf = true, RaftDecor_sign = true, RaftDecor_spool_table = true, RaftDecor_stool = true, RaftDecor_wheel = true }

--[[ ПАК ДЕКОРА: по README пака — коврику, гирлянде и цветку коллизия не нужна
     (о них спотыкались бы), у фонаря стекло светится и внутри тёплый свет. ]]
local DECOR_NOCOLLIDE = { RaftDecor_rug = true, RaftDecor_bunting = true, RaftDecor_can_flower = true }
local function dressDecor(model)
	if DECOR_NOCOLLIDE[model.Name] then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.CanCollide = false end
		end
	end
	if model.Name == "RaftDecor_lantern" then
		local glass = model:FindFirstChild("raftdecor_lantern_glass", true)
		if glass and glass:IsA("BasePart") then
			glass.Material = Enum.Material.Neon
			glass.Color = Color3.fromRGB(255, 196, 120)
			if not glass:FindFirstChildOfClass("PointLight") then
				local l = Instance.new("PointLight")
				l.Color = Color3.fromRGB(255, 190, 120)
				l.Range = 14
				l.Brightness = 1.6
				l.Shadows = true
				l.Parent = glass
			end
		end
	end
end
local FarmPropRules = require(ReplicatedStorage:WaitForChild("FarmPropRules"))
local MAX_DIST = 60

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

cupActionEvent.OnServerEvent:Connect(function(player, action, target)
	if action ~= "placeDecor" then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	if not (hrp and tool and DECOR[tool.Name]) then return end
	local NAME = tool.Name
	local raft = workspace:FindFirstChild("Raft")
	if not (raft and raft.PrimaryPart) or typeof(target) ~= "CFrame" then return end

	local template = AssetFind.find(NAME)
	if not template then
		warn("[Декор] шаблона " .. NAME .. " нет в ReplicatedStorage — ставить нечего")
		return
	end
	local primary = raft.PrimaryPart
	local worldCF = primary.CFrame:ToWorldSpace(target)
	if (worldCF.Position - hrp.Position).Magnitude > MAX_DIST then return end

	local model = template:Clone()
	model.Name = NAME
	if model:IsA("Model") then
		local bbCF = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(bbCF.Position)
	end
	model:PivotTo(worldCF)
	if FarmPropRules.NAMES[NAME] then
		--[[ ⚠️ КОРЫТО И ЯЩИК — ТОЛЬКО НА ГРЯДКУ, и PlaceCheck им не подходит:
		     он считает блок фермы постройкой и не пустил бы в загон вовсе. ]]
		local ok, why = FarmPropRules.check(model, { char })
		if not ok then
			if typeof(_G.NotifyPlayer) == "function" then
				_G.NotifyPlayer(player, { type = "warn", icon = "no", title = "Сюда нельзя", body = why })
			end
			model:Destroy()
			return
		end
		-- уровни заполнения (FarmFill): пустые
		if NAME == "Raft_farm_trough" then
			model:SetAttribute("Water", 0)
			model:SetAttribute("WaterMax", 100)
		elseif NAME == "Raft_wool_bin" then
			model:SetAttribute("Wool", 0)
			model:SetAttribute("WoolMax", 16)
		end
	elseif PlaceCheck.WALL_NAMES[NAME] then
		--[[ ШТУРВАЛ, КРУГ, ПОЛКА — ТОЛЬКО НА СТЕНУ. PlaceCheck им не подходит:
		     вплотную к стене он видит саму стену и отказал бы. Проверяем, что
		     за предметом действительно стена плота, а не воздух. ]]
		if not PlaceCheck.hasWallBehind(model, raft, char) then
			if typeof(_G.NotifyPlayer) == "function" then
				_G.NotifyPlayer(player, { type = "warn", icon = "no", title = "Сюда нельзя",
					body = "Вешается только на стену плота" })
			end
			model:Destroy()
			return
		end
	elseif PlaceCheck.FLOORING[NAME] and not PlaceCheck.onFloor(model, raft) then
		-- коврик — только на пол, не на предметы
		if typeof(_G.NotifyPlayer) == "function" then
			_G.NotifyPlayer(player, { type = "warn", icon = "no", title = "Сюда нельзя",
				body = "Коврик кладётся только на пол" })
		end
		model:Destroy()
		return
	elseif PlaceCheck.refuseIfBlocked(model, raft, player) then return end   -- в предмет ставить нельзя
	dressDecor(model)
	model.Parent = raft

	-- как у плавильни: заякорить → приварить к плоту → отпустить, скорость вернуть
	local linVel, angVel = primary.AssemblyLinearVelocity, primary.AssemblyAngularVelocity
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	for _, part in ipairs(parts) do part.Anchored = true end
	for _, part in ipairs(parts) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = primary
		weld.Parent = part
		part.Massless = true
	end
	for _, part in ipairs(parts) do part.Anchored = false end
	primary.AssemblyLinearVelocity = linVel
	primary.AssemblyAngularVelocity = angVel
	RaftShake.notify()   -- скорость ещё раз после шага физики + удержать игроков (RaftShake)

	tool:Destroy()
	print(("[Декор] %s поставил %s на плот"):format(player.Name, NAME))
end)

--[[ СТУЛЬЯ — СИДЕНИЯ. В модель кладём невидимый Seat над сиденьем: сесть и
     встать умеет сам Roblox, поза сидя — штатная анимация персонажа, а
     сидящий приварен к сиденью и едет с плотом. Seat ставится на ЛЮБОЙ стул в
     плоту — и поставленный сейчас, и приехавший из сейва (сейв клонирует
     шаблон без него). Высота — по габариту модели: сиденье примерно на 45%
     высоты стула; своя деталь «Seat»/«seat» в модели, если есть, важнее. ]]
local SEATED = { Raft_chair = true, Raft_chair_leaf = true, RaftDecor_deckchair = true, RaftDecor_stool = true }
local SEAT_HEIGHT = 0.45   -- доля высоты стула, где сиденье

local function ensureSeat(model)
	if not (model:IsA("Model") and SEATED[model.Name]) then return end
	if model:FindFirstChild("ChairSeat") then return end
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then return end
	local cf, size = model:GetBoundingBox()
	local seatPart = model:FindFirstChild("Seat", true) or model:FindFirstChild("seat", true)
	local pos = seatPart and seatPart:IsA("BasePart") and (seatPart.Position + Vector3.new(0, seatPart.Size.Y * 0.5, 0))
		or (cf.Position + Vector3.new(0, -size.Y * 0.5 + size.Y * SEAT_HEIGHT, 0))
	local pivot = model:GetPivot()
	local seat = Instance.new("Seat")
	seat.Name = "ChairSeat"
	seat.Size = Vector3.new(math.max(1.5, size.X * 0.6), 0.4, math.max(1.5, size.Z * 0.6))
	seat.CFrame = CFrame.lookAt(pos, pos + pivot.LookVector)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanQuery = false
	seat.Massless = true
	seat.Anchored = anchor.Anchored
	seat.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = seat
	weld.Parent = seat
	seat.Anchored = false
end

task.spawn(function()
	local raft = workspace:WaitForChild("Raft", 60)
	if not raft then return end
	for _, c in ipairs(raft:GetChildren()) do ensureSeat(c) end
	raft.ChildAdded:Connect(function(c) task.defer(ensureSeat, c) end)
end)

print("[Декор] готово: крафт «Декор» → тул с именем модели → установка на плот; стулья — сиденья")
