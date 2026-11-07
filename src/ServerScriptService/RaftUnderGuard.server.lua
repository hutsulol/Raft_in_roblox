-- RaftUnderGuard.server.lua
--
-- ⚠️ ОТКЛЮЧЁН. Этот сторож убивал мобов, подошедших к плоту.
--
-- Что он делал: каждые 0.1 с сканировал объём под палубой и ВЫБРАСЫВАЛ оттуда
-- всё чужое — детали вниз, а NPC вниз И УДАЛЯЛ через секунду. Задумывался он
-- против объектов, застрявших под корпусом: они упирались в него и раскачивали
-- плот.
--
-- Почему сломался. Объём считался так:
--   верх     = PrimaryPart.Position.Y - 1
--   стороны  = max(размерX, размерZ) плота — КВАДРАТ по большей стороне
-- Оба допущения перестали быть верными после переделки плота: PrimaryPart
-- (лежащее на боку бревно) теперь стоит на другой высоте относительно настила,
-- поэтому «объём под палубой» поднялся к уровню воды, а квадрат по большей
-- стороне накрывает воду далеко за бортом у неквадратного плота. Пираты и
-- зомби, подплывающие к плоту, попадали в эту зону и умирали, не дойдя.
--
-- Сама причина, ради которой сторож писался, скорее всего уже неактуальна:
-- BoatMovement отключил на корпусе плавучесть (EnableFluidForces = false) и
-- держит высоту скоростным сервоприводом, так что подпёртый снизу предмет
-- больше не качает плот пружиной.
--
-- ЕСЛИ плот снова начнёт подпрыгивать от застрявших под ним предметов —
-- включать не «как было», а сперва починив геометрию: верх объёма брать от
-- РЕАЛЬНОГО уровня палубы, стороны — по X и Z раздельно, и NPC не удалять,
-- а выталкивать в сторону.
local ENABLED = false

local Players   = game:GetService("Players")
local Debris    = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

if not ENABLED then
	print("[RaftUnderGuard] отключён (убивал мобов у плота — см. комментарий в файле)")
	return
end

local CHECK      = 0.1   -- seconds between sweeps
local INSET      = 2     -- shrink the footprint test inward (studs)
local TOP_GAP    = 1     -- the volume starts this far below the deck (so deck-walkers aren't caught)
local DEPTH      = 15    -- how far down the "under" volume reaches
local EJECT_DOWN = 120   -- studs/s downward fling
local REMOVE     = 1     -- seconds before an ejected NPC is removed

local function getRaft()
	local r = Workspace:FindFirstChild("Raft")
	if r and r.PrimaryPart then return r end
	return nil
end

-- the NPC rig (a Model directly holding a Humanoid) a part belongs to, or nil for a loose part
local function npcModelOf(part)
	local inst = part
	while inst and inst ~= Workspace do
		if inst:IsA("Model") and inst:FindFirstChildOfClass("Humanoid") then return inst end
		inst = inst.Parent
	end
	return nil
end

local function flingDown(part)
	part.CanCollide = false -- stop shoving the raft this instant
	part.AssemblyLinearVelocity = Vector3.new(0, -EJECT_DOWN, 0)
end

local function ejectModel(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then flingDown(d) end
	end
	Debris:AddItem(model, REMOVE)
end

task.spawn(function()
	local r = getRaft()
	while not r do task.wait(0.5); r = getRaft() end

	local handled = {}
	while true do
		task.wait(CHECK)
		r = getRaft()
		if r and r.PrimaryPart then
			local rootPart = r.PrimaryPart
			local raftRoot = rootPart.AssemblyRootPart -- the whole raft (incl. welded-on parts)
			local center = (_G.GetRaftCenter and _G.GetRaftCenter()) or rootPart.Position
			local _, size = r:GetBoundingBox()
			local half = math.max(size.X, size.Z) * 0.5 - INSET
			if half > 1 then
				local boxCFrame = CFrame.new(center.X, rootPart.Position.Y - TOP_GAP - DEPTH * 0.5, center.Z)
				local boxSize = Vector3.new(half * 2, DEPTH, half * 2)

				local params = OverlapParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				local exclude = { r }
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr.Character then exclude[#exclude + 1] = plr.Character end
				end
				params.FilterDescendantsInstances = exclude
				params.MaxParts = 80

				local parts = Workspace:GetPartBoundsInBox(boxCFrame, boxSize, params)
				table.clear(handled)
				for _, part in ipairs(parts) do
					-- skip anchored geometry and anything that's part of the raft assembly
					-- ДРЕЙФУЮЩИЕ РЕСУРСЫ НЕ ТРОГАЕМ. Они в коллизионной группе
				-- "FloatingResource", которая НЕ сталкивается с "Raft" — корпус они
				-- не шатают, и топить их незачем. Из-за этого правила бревно и
				-- листва, подплывая к сети (сеть — часть плота, поэтому её площадь
				-- попадает в подплотную зону), улетали вниз ещё ДО того, как сеть
				-- успевала их поймать.
				if part.CollisionGroup ~= "FloatingResource"
					and not part.Anchored and part.AssemblyRootPart ~= raftRoot then
						local npc = npcModelOf(part)
						if npc then
							-- friendly divers work UNDER the raft on purpose — never eject or delete them
							if npc.Name ~= "Diver" and not npc:GetAttribute("RaftFriendly") then
								if not handled[npc] then
									handled[npc] = true
									ejectModel(npc)
								end
							end
						else
							flingDown(part)
						end
					end
				end
			end
		end
	end
end)

print("[RaftUnderGuard] active")
