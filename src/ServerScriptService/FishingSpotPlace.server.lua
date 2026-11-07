--[[
	РЫБАЦКОЕ МЕСТО — установка на плот (сервер). Правила сетки — FishingSpotGrid:
	строго одна клетка пола, поворот четвертями, впереди — свободная вода.
	Призрак — FishingSpotPlace.client, CupAction "placeFishingSpot" (tile, quarter).
	Кто рыбачит на поставленном месте — RaftFishing (рыбак или выживший).

	_G.FishingFrontReserved(pos) — клетка с центром pos — вода перед станцией:
	BuildingSystem не даёт строить там пол и сеть.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetFind  = require(ReplicatedStorage:WaitForChild("AssetFind"))
local PlaceCheck = require(ReplicatedStorage:WaitForChild("PlaceCheck"))
local RaftShake  = require(ReplicatedStorage:WaitForChild("RaftShake"))
local G          = require(ReplicatedStorage:WaitForChild("FishingSpotGrid"))

local LOG = "[Рыбацкое место]"
local MAX_DIST = 60
local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

local function notify(player, title, body)
	if typeof(_G.NotifyPlayer) == "function" then
		_G.NotifyPlayer(player, { type = "warn", icon = "no", title = title, body = body })
	end
end

-- приварить к плоту без рывка (рецепт RaftShake)
local function weldToRaft(model, raft)
	local primary = raft.PrimaryPart
	local lin, ang = primary.AssemblyLinearVelocity, primary.AssemblyAngularVelocity
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	for _, p in ipairs(parts) do p.Anchored = true; p.Massless = true end
	for _, p in ipairs(parts) do
		local w = Instance.new("WeldConstraint")
		w.Part0 = p
		w.Part1 = primary
		w.Parent = p
	end
	for _, p in ipairs(parts) do p.Anchored = false end
	primary.AssemblyLinearVelocity = lin
	primary.AssemblyAngularVelocity = ang
	RaftShake.notify()
end

cupActionEvent.OnServerEvent:Connect(function(player, action, hit, quarter)
	if action ~= "placeFishingSpot" then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	if not (hrp and tool and tool.Name == G.NAME) then return end
	local raft = workspace:FindFirstChild("Raft")
	if not (raft and raft.PrimaryPart) then return end
	if typeof(hit) ~= "Instance" or not hit:IsDescendantOf(raft) then return end
	quarter = type(quarter) == "number" and math.floor(quarter) % 4 or G.DEFAULT_QUARTER
	local tile = G.topTileOf(hit, raft)
	if not (tile and G.isTile(tile, raft)) then
		notify(player, "Только на пол", "Рыбацкое место ставится на клетку пола плота")
		return
	end
	local tpl = AssetFind.find(G.NAME)
	if not tpl then warn(LOG .. " нет шаблона " .. G.NAME) return end

	local model = tpl:Clone()
	model.Name = G.NAME
	local front = G.pose(model, raft, tile, quarter)
	if not front then model:Destroy() warn(LOG .. " не вышло поставить по клетке") return end
	if (model:GetPivot().Position - hrp.Position).Magnitude > MAX_DIST then model:Destroy() return end
	if G.frontReserved(raft, G.tilePos(tile)) then
		model:Destroy()
		notify(player, "Здесь вода для рыбака", "Эта клетка — место для заброса соседней станции")
		return
	end
	local why = G.frontProblem(raft, front, { model })
	if why then
		model:Destroy()
		notify(player, "Сюда нельзя", why)
		return
	end
	if PlaceCheck.refuseIfBlocked(model, raft, player) then return end

	model.Parent = raft
	weldToRaft(model, raft)   -- рыбака заведёт RaftFishing
	tool:Destroy()
	if typeof(_G.SendInventory) == "function" then pcall(_G.SendInventory, player) end
	if typeof(_G.OnQuestEvent) == "function" then pcall(_G.OnQuestEvent, player, "placed:FishingSpot", 1) end
	if typeof(_G.MerchantStoryEvent) == "function" then pcall(_G.MerchantStoryEvent, "placed:FishingSpot", player) end
	local base = G.basePart(model)
	print(("%s %s поставил рыбацкое место (четверть %d), верх основания %.2f")
		:format(LOG, player.Name, quarter, base and base.CFrame.UpVector.Y or -9))
end)

--[[ ДАТЧИК «ПЛОТ СТОИТ». После установки станции плот перестал плыть, а
     причина в шаблоне не нашлась (всё без коллизии и без массы). Если плот
     стоит, хотя его не держат ни якорь, ни посадка, ни рейс, — раз в 10 с
     пишем в Output, что заякорено в его сборке и что торчит под водой. Плюс
     страховка: детали станций и рыбака на плоту никогда не заякорены. ]]
task.spawn(function()
	local lastReport = 0
	while true do
		task.wait(3)
		local raft = workspace:FindFirstChild("Raft")
		local primary = raft and raft.PrimaryPart
		if primary then
			for _, child in ipairs(raft:GetChildren()) do
				if child.Name == G.NAME and not child:GetAttribute("FS_TiltReported") then
					-- станция завалилась: один раз пишем, как она стоит относительно плота
					local base = G.basePart(child)
					if base and base.CFrame.UpVector.Y < 0.9 then
						child:SetAttribute("FS_TiltReported", true)
						local rel = G.flatFrame(raft):ToObjectSpace(base.CFrame)
						local ex, ey, ez = rel:ToEulerAnglesYXZ()
						warn(("%s станция наклонена: верх основания %.2f, поворот к плоту (%.0f, %.0f, %.0f), сварок у основания %d")
							:format(LOG, base.CFrame.UpVector.Y, math.deg(ex), math.deg(ey), math.deg(ez), #base:GetJoints()))
					end
				end
				if child.Name == G.NAME then
					for _, d in ipairs(child:GetDescendants()) do
						if d:IsA("BasePart") and d.Anchored then d.Anchored = false end
					end
				end
			end
			-- рыбака не трогаем: поплавок и летящая рыба заякорены намеренно
			-- (не приварены к плоту, их водит клиент — FishingService)
			local v = primary.AssemblyLinearVelocity
			local held = raft:GetAttribute("SailHold") or raft:GetAttribute("BoardingHold")
				or (tonumber(raft:GetAttribute("AnchorDepth")) or 0) > 0.05
			if Vector3.new(v.X, 0, v.Z).Magnitude < 0.5 and not held and os.clock() - lastReport > 10 then
				lastReport = os.clock()
				local anchored, names = {}, {}
				for _, p in ipairs(primary:GetConnectedParts(true)) do
					if p.Anchored then table.insert(anchored, p:GetFullName()) end
					local top = G.topTileOf(p, raft)
					names[(top and top.Name) or p:GetFullName()] = true
				end
				local list = {}
				for n in pairs(names) do table.insert(list, n) end
				warn(("%s плот стоит (скорость %.2f), не держат ни якорь, ни посадка. Заякорено в сборке: %s. Масса %.0f. В сборке: %s")
					:format(LOG, v.Magnitude, #anchored > 0 and table.concat(anchored, ", ") or "ничего",
						primary.AssemblyMass, table.concat(list, ", ")))
			end
		end
	end
end)

_G.FishingFrontReserved = function(pos)
	return G.frontReserved(workspace:FindFirstChild("Raft"), pos)
end

print(LOG .. " готово: строго на клетку пола, впереди — вода (1×2)")
