-- SwimmingPirate.server.lua
-- Boarding swimmers: ReplicatedStorage.Swimming_Hero NPCs surface from UNDER the water
-- around the raft, swim after it, leap aboard, and attack the nearest player.
--   • Spawn submerged → rise smoothly so they're seen emerging from the sea (not popping in).
--   • Each picks a RANDOM one of the model's swim animations.
--   • They chase the moving raft, board with a jump, then hunt the player on deck.
-- Movement is kinematic (we drive the anchored HumanoidRootPart) so it's smooth on the
-- force-driven raft; the rig stays unanchored so the swim animation poses it.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local EnemyHealthBar    = require(ReplicatedStorage:WaitForChild("EnemyHealthBar"))
local WaterSpawn        = require(ReplicatedStorage:WaitForChild("WaterSpawn"))
local AssetFind         = require(ReplicatedStorage:WaitForChild("AssetFind"))

local TEMPLATE          = "Swimming_Hero"
local SPAWN_INTERVAL    = 30     -- seconds between spawn attempts
local MAX_ACTIVE        = 1      -- max swimmers at once
local SPAWN_MARGIN      = 100    -- how far BEYOND the raft's edge they surface (было 40 — слишком близко, атаковали сразу)
                                --  — при скорости 11 и ночи в 30с пират просто НЕ УСПЕВАЛ доплыть
                                --  до уплывающего плота; 40 = виден издали, но гарантированно доплывает
local SUBMERGE_DEPTH    = 7      -- spawn this far UNDER the water, then rise
local EMERGE_TIME       = 1.3    -- seconds to rise from underwater to the surface
local SWIM_Y_OFFSET     = 1      -- swim with the head/shoulders above water (so it's visible)
local SWIM_SPEED        = 10     -- cruise: чуть быстрее плота (~8 ст/с), догоняет даже сзади
local SPRINT_SPEED      = 15     -- speeds up CLOSE to the raft, to close the last gap and climb aboard
local SPRINT_NEAR       = 15     -- within this gap to the raft's edge → sprint (so it can board)
local SPRINT_HYST       = 6      -- hysteresis band so the mode can't flicker at the boundary
local BOARD_MARGIN      = 1      -- only boards once within 1 stud of the nearest Raft_part
local BOARD_TIME        = 0.55   -- jump duration
local BOARD_FORWARD     = 5      -- studs onto the deck the jump carries them (lands near the edge)
local BOARD_HEIGHT      = 6      -- jump arc height
local BOARD_REACH       = 4      -- if it hugs within (this + BOARD_MARGIN) of the edge for BOARD_STICK, board anyway
local BOARD_STICK       = 0.45   -- seconds hugging the edge before it jumps on regardless (so it ALWAYS climbs on)
local DECK_RISE         = 3      -- deck height above the raft's PrimaryPart
local WALK_SPEED        = 10     -- chase-the-player speed on deck (было 14 — медленнее игрока, можно кайтить)
local ATTACK_DIST       = 5      -- melee reach
local ATTACK_DAMAGE     = 12
local ATTACK_INTERVAL   = 1.3    -- seconds between hits
local OBSTACLE_HP       = 120    -- HP on first hit; at ATTACK_DAMAGE (12) that's ~10 hits to destroy
local OBSTACLE_REACH    = 3.5    -- a wall/building this close in its path gets smashed instead of blocking it
local PIRATE_HP         = 100
local GIB_SPEED         = 32     -- on death the corpse parts fly this fast, away from the attacker
local GIB_UP            = 16     -- + an upward kick
local PIRATE_DROP       = 2      -- Pirate coins dropped on death
-- Under-raft safety: a BOARDED pirate (real physics, CanCollide on) that slips UNDER the raft
-- shoves the buoyancy spring and makes the raft bounce unnaturally. If one ends up inside the
-- raft's footprint AND clearly below the water line, kill it — stop its collision, fling it down,
-- remove it. ВАЖНО: проверка работает ТОЛЬКО после посадки на плот (boarded). Плывущего/
-- заходящего пирата (он ещё в воде, у поверхности) она НЕ трогает — иначе он пропадал, не
-- запрыгнув. Порог глубины увеличен, чтобы срабатывало «реально под водой», а не «в воде».
local UNDER_INSET       = 1.5    -- shrink the raft footprint test inward (studs)
local UNDER_DEPTH       = 4      -- this far below the water line + inside footprint = «реально под плотом» (было 2)
local UNDER_CHECK       = 0.15   -- seconds between under-raft checks
local EJECT_DOWN        = 120    -- studs/s downward fling when ejected
local EJECT_REMOVE      = 1      -- seconds before the ejected pirate is removed

local function lerp(a, b, t) return a + (b - a) * t end

-- ── rig helpers (same shape ShipCombat uses for drowning pirates) ──
local function findRig(model)
	if model:FindFirstChild("Torso") or model:FindFirstChild("Head") then return model end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Model") and (d:FindFirstChild("Torso") or d:FindFirstChild("Head")) then return d end
	end
	return model
end

local function ensureHumanoid(model)
	local hum = model:FindFirstChildWhichIsA("Humanoid", true)
	local rig = findRig(model)
	if not hum then
		local torso = rig:FindFirstChild("Torso") or rig:FindFirstChild("UpperTorso") or rig:FindFirstChildWhichIsA("BasePart")
		if not torso then return nil, nil end
		if not rig:FindFirstChild("HumanoidRootPart") then
			local hrp = Instance.new("Part")
			hrp.Name = "HumanoidRootPart"
			hrp.Size = Vector3.new(2, 2, 1)
			hrp.Transparency = 1
			hrp.CFrame = torso.CFrame
			hrp.Parent = rig
		end
		hum = Instance.new("Humanoid")
		hum.Parent = rig
	end
	hum.MaxHealth = PIRATE_HP
	-- ⚠️ ЗДОРОВЬЕ ВЫСТАВЛЯЕМ ТОЛЬКО ОДИН РАЗ ЗА ЖИЗНЬ.
	-- Конвейер перезапускается, когда пират сваливается за борт и плывёт назад —
	-- и на каждом перезапуске он лечился до полного. Из-за этого горящий уходил
	-- тушиться в море и возвращался как новенький, обнулив весь нанесённый урон.
	if not model:GetAttribute("HpInit") then
		model:SetAttribute("HpInit", true)
		hum.Health = PIRATE_HP
	end
	hum.BreakJointsOnDeath = false
	local hrp = rig:FindFirstChild("HumanoidRootPart") or hum.RootPart
	return hum, hrp
end

local function waterSurfaceAt(x, z, fallbackY, ignore)
	local params = RaycastParams.new()
	params.IgnoreWater = false
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local res = workspace:Raycast(Vector3.new(x, fallbackY + 100, z), Vector3.new(0, -500, 0), params)
	if res and res.Material == Enum.Material.Water then return res.Position.Y end
	return fallbackY
end

local function nearestPlayer(pos)
	local best, bestD = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - pos).Magnitude
			if d < bestD then best, bestD = plr, d end
		end
	end
	return best
end

-- load the model's phase animations by name → { swim, jump, walk, attack }
local function loadTracks(hum, model)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	for _, t in ipairs(animator:GetPlayingAnimationTracks()) do t:Stop(0) end -- no competing pose
	local KEYS = { swim = { "swim" }, jump = { "jump" }, walk = { "walk", "run" }, attack = { "attack", "atk" } }
	local tracks = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Animation") and d.AnimationId ~= "" then
			local ln = d.Name:lower()
			for key, pats in pairs(KEYS) do
				if not tracks[key] then
					for _, p in ipairs(pats) do
						if ln:find(p) then
							local ok, tr = pcall(function() return animator:LoadAnimation(d) end)
							if ok and tr then tr.Priority = Enum.AnimationPriority.Action; tracks[key] = tr end
							break
						end
					end
				end
			end
		end
	end
	return tracks
end

-- small HP bar above the pirate's head, tracking its Humanoid health
local function setupHealthBar(pirate, hum, hrp)
	local head = pirate:FindFirstChild("Head", true) or hrp
	if not head then return end
	-- второй раз не вешаем: конвейер перезапускается, когда пират сваливается за
	-- борт и плывёт обратно, а полос над головой должна остаться одна
	if pirate:FindFirstChild("PirateHP", true) then return end
	local hb = EnemyHealthBar.new({
		name = "ПИРАТ",
		maxHp = math.max(hum.MaxHealth, 1),
		cur = hum.Health,
		difficulty = 1,
		surface = true, -- SurfaceGui: масштабируется с расстоянием (не раздувается издалека)
	})
	-- gib()/eject ищут бар по имени "PirateHP" (FindFirstChild ..., true) — задаём его в attach
	hb.attach(head, 2.4, "PirateHP")
	local function upd() hb.setHP(hum.Health, hum.MaxHealth) end
	hum.HealthChanged:Connect(upd)
	upd()
end

-- rig for kinematic movement + animation: anchor only the root, free the rest so the
-- Motor6D-driven swim pose shows; nothing collides (we move it by hand).
local function setupPirate(pirate)
	local hum, hrp = ensureHumanoid(pirate)
	if not hum or not hrp then return nil, nil end
	hrp = hum.RootPart or hrp
	-- NOTHING is anchored: anchored parts ignore Motor6D poses, which is why most of the
	-- rig stood still. We keep the pirate in place by driving the root's CFrame (+ zeroing
	-- its velocity) each frame instead, so the swim animation poses the WHOLE rig.
	for _, d in ipairs(pirate:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.Massless = (d ~= hrp) -- light limbs follow the kinematic root cleanly
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d.Disabled = true -- kill any default Animate/AI baked into the model
		end
	end
	pcall(function() pirate.PrimaryPart = hrp end)
	hum.EvaluateStateMachine = false -- stop the Humanoid's default states fighting our tracks
	hum.AutoRotate = false
	-- never flip into water/swim physics — on/near the deck it must walk like on land
	pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false) end)
	local tracks = loadTracks(hum, pirate)
	setupHealthBar(pirate, hum, hrp)

	local gibbed = false
	local function gib()
		if gibbed or hum.Health > 0 then return end
		gibbed = true
		local pos = hrp.Position
		local plr = nearestPlayer(pos)
		-- fling away from the attacker (damage from the front → gibs fly backward)
		local away = Vector3.new(math.random(-10, 10) / 10, 0, math.random(-10, 10) / 10)
		local php = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if php then
			local d = Vector3.new(pos.X - php.Position.X, 0, pos.Z - php.Position.Z)
			if d.Magnitude > 0.1 then away = d.Unit end
		end
		away = (away.Magnitude > 0.1) and away.Unit or Vector3.new(0, 0, 1)
		local bar = pirate:FindFirstChild("PirateHP", true)
		if bar then bar:Destroy() end
		-- break the rig into gibs that fly off + spin, then clean up
		for _, j in ipairs(pirate:GetDescendants()) do
			if j:IsA("Motor6D") or j:IsA("Weld") or j:IsA("WeldConstraint") then j:Destroy() end
		end
		for _, d in ipairs(pirate:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.CanCollide = true -- gibs are solid → they land/tumble on the deck
				d.Massless = false
				local spread = Vector3.new(math.random(-35, 35) / 100, math.random(0, 25) / 100, math.random(-35, 35) / 100)
				d.AssemblyLinearVelocity = (away + spread).Unit * GIB_SPEED + Vector3.new(0, GIB_UP, 0)
				d.AssemblyAngularVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))
			end
		end
		if _G.SpawnPirateCoins and plr then _G.SpawnPirateCoins(pos, plr, PIRATE_DROP) end
		game:GetService("Debris"):AddItem(pirate, 3)
	end
	-- ⚠️ СМЕРТЬ ПОДПИСЫВАЕМ РОВНО ОДИН РАЗ ЗА ЖИЗНЬ.
	-- Конвейер перезапускается (сошёл за борт — поплыл обратно), а каждый заход
	-- вешал ЕЩЁ ОДНУ подписку на смерть. Все они срабатывали разом: девять
	-- перезапусков — девять выплат, и с одного пирата сыпалось +18 монет вместо
	-- двух. Полосу здоровья это дёргало по той же причине.
	if not pirate:GetAttribute("DeathWired") then
		pirate:SetAttribute("DeathWired", true)
		-- Died doesn't fire while EvaluateStateMachine is off, so gib on HP hitting 0
		hum.HealthChanged:Connect(function(h) if h <= 0 then gib() end end)
		hum.Died:Connect(gib)
	end
	return hum, hrp, tracks
end

-- aim the root horizontally along `dir` while keeping height `y`
local function faceMove(hrp, x, y, z, dir)
	local p = Vector3.new(x, y, z)
	if dir.Magnitude > 0.01 then
		hrp.CFrame = CFrame.lookAt(p, p + Vector3.new(dir.X, 0, dir.Z).Unit)
	else
		hrp.CFrame = CFrame.new(p) * (hrp.CFrame - hrp.CFrame.Position)
	end
	hrp.AssemblyLinearVelocity = Vector3.zero  -- kinematic root: hold position now that it's unanchored
	hrp.AssemblyAngularVelocity = Vector3.zero
end

-- a smashed building: bind ALL its parts into ONE rigid body (so parts held only by anchoring,
-- like a pillar's bark around its core, stay attached), cut only the welds tying it to the raft,
-- then unanchor it so gravity drops the whole piece. Cleared a few seconds later.
local function breakBuilding(root)
	root:SetAttribute("Broken", true) -- so pirates stop targeting it while it falls
	local bar = root:FindFirstChild("ObstacleHPBar")
	if bar then bar:Destroy() end -- the broken/falling piece shows no HP bar
	local parts = {}
	if root:IsA("BasePart") then table.insert(parts, root) end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	if #parts == 0 then root:Destroy() return end
	-- 1) weld every part to one hub so the model is a SINGLE rigid body and drops as one piece.
	-- This only ADDS welds (existing internal welds are left intact); it catches parts that were
	-- only anchored with no weld to their neighbours.
	local hub = (root:IsA("Model") and root.PrimaryPart) or parts[1]
	for _, p in ipairs(parts) do
		if p ~= hub then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = hub, p
			w.Parent = hub
		end
	end
	-- 2) cut ONLY welds with EXACTLY ONE end inside the model — those tie it to the raft. Welds
	-- with both ends inside (its own parts, including the ones just added) are kept.
	local inModel = {}
	for _, p in ipairs(parts) do inModel[p] = true end
	local raftModel = workspace:FindFirstChild("Raft") or root
	for _, d in ipairs(raftModel:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") or d:IsA("Snap") then
			local ai = d.Part0 and inModel[d.Part0]
			local bi = d.Part1 and inModel[d.Part1]
			if (ai or bi) and not (ai and bi) then d:Destroy() end
		end
	end
	-- 3) unanchor + give weight so gravity drops the whole rigid model
	for _, p in ipairs(parts) do
		p.Anchored = false
		p.Massless = false
	end
	game:GetService("Debris"):AddItem(root, 4) -- falls for a few seconds, then vanishes
end

-- startOnDeck = его закинуло сразу на плот (горящий охранник удачно прыгнул).
-- Тогда «вынырнуть», «доплыть» и «запрыгнуть» пропускаются целиком: иначе
-- выныривание стащило бы его с палубы обратно под воду, а прыжок — за борт.
local function runPirate(pirate, waterY, startOnDeck)
	local hum, hrp, tracks = setupPirate(pirate)
	if not hum or not hrp then pirate:Destroy(); return end
	local swimY = waterY + SWIM_Y_OFFSET

	-- under-raft watchdog: if the pirate gets stuck under the raft, kill it (see UNDER_* config).
	-- `boarded` включается только ПОСЛЕ посадки на плот — до этого (пока плывёт/заходит) пирата
	-- не убиваем, даже если он на миг оказался в воде под кромкой плота.
	local ejected = false
	local boarded = false
	-- ⚠️ ВЫБРОС ИЗ-ПОД ПЛОТА ОТКЛЮЧЁН (UNDER_EJECT_ENABLED = false).
	-- Это вторая, СОБСТВЕННАЯ копия той же логики, что была в RaftUnderGuard:
	-- пират, оказавшийся ниже воды в габаритах плота, отправлялся вниз и
	-- удалялся. После переделки плота зона считается неверно (габаритная коробка
	-- берётся вместе с мачтами и монолитом, а waterY — от старой геометрии), и
	-- пираты «тонули» на подходе, не добравшись до борта.
	-- Отключение RaftUnderGuard эту копию не выключало — она живёт здесь.
	local UNDER_EJECT_ENABLED = false
	task.spawn(function()
		local Debris = game:GetService("Debris")
		while UNDER_EJECT_ENABLED and pirate.Parent and not ejected do
			task.wait(UNDER_CHECK)
			if hum.Health <= 0 then break end
			local r = workspace:FindFirstChild("Raft")
			if r and r.PrimaryPart then
				local cf, size = r:GetBoundingBox()
				local lp = cf:PointToObjectSpace(hrp.Position)
				local insideXZ = math.abs(lp.X) <= size.X * 0.5 - UNDER_INSET
					and math.abs(lp.Z) <= size.Z * 0.5 - UNDER_INSET
				if boarded and insideXZ and hrp.Position.Y < waterY - UNDER_DEPTH then
					ejected = true -- makes alive() false → the AI loops below stop driving the rig
					local bar = pirate:FindFirstChild("PirateHP", true)
					if bar then bar:Destroy() end
					-- stop shoving the raft instantly, then send it straight down and clear it
					for _, d in ipairs(pirate:GetDescendants()) do
						if d:IsA("BasePart") then
							d.CanCollide = false
							d.AssemblyLinearVelocity = Vector3.new(0, -EJECT_DOWN, 0)
						end
					end
					Debris:AddItem(pirate, EJECT_REMOVE)
				end
			end
		end
	end)

	task.spawn(function()
		local function raft() return workspace:FindFirstChild("Raft") end
		local function raftPart() local r = raft(); return r and r.PrimaryPart end
		local function raftCenter() return (_G.GetRaftCenter and _G.GetRaftCenter()) or (raftPart() and raftPart().Position) end
		-- the closest point on the NEAREST Raft_part to `from`, recomputed every call (no cache,
		-- no cross-script _G) so it re-fixes on a newly-built piece the instant you place one
		local function nearestRaftPoint(from)
			local r = raft()
			if not r then return nil end
			local best, bestD
			for _, p in ipairs(r:GetChildren()) do
				if p:IsA("BasePart") and p.Name:lower() == "raft_part" then -- case-insensitive
					local lp = p.CFrame:PointToObjectSpace(from)
					local h = p.Size * 0.5
					local wp = p.CFrame:PointToWorldSpace(Vector3.new(
						math.clamp(lp.X, -h.X, h.X), math.clamp(lp.Y, -h.Y, h.Y), math.clamp(lp.Z, -h.Z, h.Z)))
					local d = (wp - from).Magnitude
					if not bestD or d < bestD then best, bestD = wp, d end
				end
			end
			if best then return best end
			-- no part matched by name → nearest point on the raft's bounding-box EDGE (still an
			-- edge, NEVER the centre) so it always heads to a side, not the middle
			local cf, size = r:GetBoundingBox()
			local lp = cf:PointToObjectSpace(from)
			local h = size * 0.5
			return cf:PointToWorldSpace(Vector3.new(
				math.clamp(lp.X, -h.X, h.X), math.clamp(lp.Y, -h.Y, h.Y), math.clamp(lp.Z, -h.Z, h.Z)))
		end
		-- HP bar above a damaged building — only appears once it drops below full (buildings
		-- don't regen, so it stays until destroyed)
		local function showObstacleHP(model, hp, maxHP)
			local main, height
			if model:IsA("Model") then
				main = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
				local _, size = model:GetBoundingBox()
				height = size.Y
			else
				main, height = model, model.Size.Y
			end
			if not main then return end
			local bb = model:FindFirstChild("ObstacleHPBar")
			if not bb then
				bb = Instance.new("BillboardGui")
				bb.Name = "ObstacleHPBar"
				bb.Size = UDim2.fromOffset(100, 12)
				bb.AlwaysOnTop = true
				bb.StudsOffsetWorldSpace = Vector3.new(0, height * 0.5 + 1.5, 0)
				bb.Adornee = main
				local bg = Instance.new("Frame")
				bg.Size = UDim2.fromScale(1, 1)
				bg.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
				bg.BorderSizePixel = 0
				bg.Parent = bb
				local fl = Instance.new("Frame")
				fl.Name = "Fill"
				fl.BackgroundColor3 = Color3.fromRGB(225, 80, 60)
				fl.BorderSizePixel = 0
				fl.Parent = bg
				bb.Parent = model
			end
			local bg = bb:FindFirstChildWhichIsA("Frame")
			local fl = bg and bg:FindFirstChild("Fill")
			if fl then fl.Size = UDim2.fromScale(math.clamp(hp / maxHP, 0, 1), 1) end
		end
		-- the raft-mounted building a hit part belongs to, or nil if it's the floor, the
		-- community board (never breakable), or not mounted on the raft
		local function buildingRootOf(part)
			local raftModel = raft()
			local root = part
			while root.Parent and root.Parent ~= raftModel and root.Parent ~= workspace do
				root = root.Parent
			end
			if root.Parent ~= raftModel then return nil end
			local n = root.Name:lower()
			if n == "raft_part" then return nil end                       -- the floor
			if n:find("board") or n:find("community") then return nil end -- protect the community board
			-- ⚠️ НЕПРИКАСАЕМЫЕ: топливный бак и ремонтная станция.
			-- Их ломать нельзя — без бака встают огнемёт и катера, без станции
			-- нечем чинить сам плот, и партия превращается в тупик.
			if n:find("oilbarrel") or n:find("oil_barrel") or n:find("oiltank")
				or n:find("repair") or n:find("ремонт") then return nil end
			if root:GetAttribute("Unbreakable") then return nil end       -- пометка из Studio
			if root:GetAttribute("Broken") then return nil end -- already smashed + falling
			return root
		end
		-- the breakable on-deck building right in the pirate's path along `dir`, or nil
		local function obstacleInFront(dir)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local excl = { pirate }
			for _, pl in ipairs(Players:GetPlayers()) do if pl.Character then table.insert(excl, pl.Character) end end
			params.FilterDescendantsInstances = excl
			local res = workspace:Raycast(hrp.Position, dir * OBSTACLE_REACH, params)
			if not res or not res.Instance then return nil end
			if res.Instance:FindFirstAncestor(TEMPLATE) then return nil end -- another pirate
			return buildingRootOf(res.Instance)
		end
		-- smash a building: gives it HP on the first hit, shows its bar, removes it at 0
		local function damageObstacle(root, dmg)
			local hp = (root:GetAttribute("ObstacleHP") or OBSTACLE_HP) - dmg
			if hp <= 0 then
				breakBuilding(root) -- detach from the raft, let it fall, then it's cleared
			else
				root:SetAttribute("ObstacleHP", hp)
				showObstacleHP(root, hp, OBSTACLE_HP)
			end
		end
		local alive = function() return pirate.Parent and hum.Health > 0 and not ejected end
		local function raftRadius() -- approx horizontal half-size, so we stop at the near edge
			local r = raft()
			if not r then return 14 end
			local _, size = r:GetBoundingBox()
			return math.max(size.X, size.Z) * 0.5
		end
		-- swap the active animation between phases (swim → jump → walk → attack)
		local current
		-- ⚠️ ЗАПАСНОЙ КАНАЛ АНИМАЦИИ — КЛИПЫ ИЗ ТАБЛИЦЫ.
		-- Морской пират несёт свои опубликованные анимации внутри модели, а вот
		-- охранник, спрыгнувший с горящего катера, — нет: его на катере
		-- анимировал серверный проигрыватель поз. Без этого канала он плыл,
		-- лез и дрался абсолютно неподвижным. Клип пишем атрибутом, позу считает
		-- клиент (см. PirateIslandAnim), имена — из PirateCrewClips.
		-- ⚠️ НИКАКИХ ТАБЛИЦ ПО ТРЕКАМ КАК КЛЮЧАМ.
		-- Первая версия строила соответствие «трек → имя клипа», и когда треков в
		-- модели не было (ровно наш случай), ключ оказывался nil — Lua падал
		-- прямо здесь, поток абордажа умирал, и пират тонул неуправляемым.
		-- Имя клипа теперь приходит третьим аргументом у каждого вызова play.
		local useClips = not (tracks.swim or tracks.walk or tracks.attack)
		if useClips then pirate:SetAttribute("CrewAnim", true) end

		local function play(track, looped, clipName)
			if useClips then
				local name = clipName or "MeleeIdle"
				if pirate:GetAttribute("Clip") ~= name then
					pirate:SetAttribute("Clip", name)
					pirate:SetAttribute("ClipT", workspace:GetServerTimeNow())
				end
				return
			end
			if not track or current == track then return end
			if current then current:Stop(0.15) end
			current = track
			track.Looped = looped ~= false
			track:Play(0.15)
			track:AdjustSpeed(1) -- default speed each switch; the approach overrides it per-frame
		end
		play(tracks.swim or tracks.walk, true, "MeleeRun") -- SWIM the whole approach; only walks once aboard

		-- 1) EMERGE — rise from underwater to the surface, drifting toward the raft
		local t, startY = 0, hrp.Position.Y
		while t < EMERGE_TIME and alive() and not startOnDeck do
			local dt = RunService.Heartbeat:Wait()
			t += dt
			local rp = raftPart()
			local pos = hrp.Position
			local c = raftCenter()
			local dir = (c and (c - pos)) or hrp.CFrame.LookVector
			dir = Vector3.new(dir.X, 0, dir.Z)
			dir = (dir.Magnitude > 0.01) and dir.Unit or Vector3.new(0, 0, 1)
			local step = dir * (SWIM_SPEED * 0.4 * dt)
			faceMove(hrp, pos.X + step.X, lerp(startY, swimY, math.min(t / EMERGE_TIME, 1)), pos.Z + step.Z, dir)
		end

		-- 2) SWIM — head for the raft and stop at its near EDGE (it boards the raft itself,
		-- it doesn't beeline to the player). It only hunts the player after boarding.
		local sprinting = false
		local nearT = 0 -- time spent hugging the edge → board even if it can't nail the last stud
		while alive() and not startOnDeck do
			local dt = RunService.Heartbeat:Wait()
			local rp = raftPart()
			if not rp then break end
			local pos = hrp.Position
			-- head to the NEAREST point ON the raft (its whole bounding box — any shape/size,
			-- tracked as you build) and stop BOARD_MARGIN short of that edge.
			local near = nearestRaftPoint(pos) or raftCenter() or rp.Position
			local toNear = Vector3.new(near.X - pos.X, 0, near.Z - pos.Z)
			local gap = toNear.Magnitude - BOARD_MARGIN
			if gap <= 0 then break end -- reached the raft's edge → board
			-- can't always nail the last stud on a moving raft; if it's hugged the edge a moment,
			-- jump aboard anyway so it ALWAYS climbs on, even right up against the edge
			if gap < BOARD_REACH then nearT += dt else nearT = 0 end
			if nearT > BOARD_STICK then break end
			local dir = (toNear.Magnitude > 0.01) and toNear.Unit or Vector3.new(0, 0, 1)
			-- обход островов: не плывём сквозь сушу к плоту (пока не у самого борта)
			if gap > BOARD_REACH then
				dir = WaterSpawn.steer(pos, dir, 16, { pirate, raftPart() and raftPart().Parent })
			end
			-- Chase the raft's REAL current position (no prediction → can't end up under it).
			-- Speed UP when CLOSE so it can close the final gap on a moving raft and climb on;
			-- cruise (slower, killable) while still approaching. Hysteresis so it can't flicker.
			if gap < SPRINT_NEAR then sprinting = true
			elseif gap > SPRINT_NEAR + SPRINT_HYST then sprinting = false end
			-- АДАПТИВНЫЙ КРУИЗ: держим постоянную скорость СБЛИЖЕНИЯ, а не свою — игрок
			-- веслом может развернуть плот в любой момент. Плот идёт НАВСТРЕЧУ пирату →
			-- тот притормаживает (сближение не взрывное); плот убегает → догоняет быстрее.
			local speed
			if sprinting then
				speed = SPRINT_SPEED
			else
				local rv = rp.AssemblyLinearVelocity
				-- dir·скорость плота: >0 — плот удаляется, <0 — идёт навстречу
				local raftAway = Vector3.new(rv.X, 0, rv.Z):Dot(dir)
				speed = math.clamp(SWIM_SPEED + raftAway, 3, 16)
			end
			if current then current:AdjustSpeed(speed / SWIM_SPEED) end -- match the walk anim to speed
			local move = math.min(speed * dt, gap) -- stop at the edge, never swim under
			faceMove(hrp, pos.X + dir.X * move, swimY, pos.Z + dir.Z * move, dir)
		end

		-- 3) BOARD — leap from the water onto the deck (arc) with the jump animation
		-- ⚠️ ГОРЯЩИЙ НА ПАЛУБУ НЕ ЛЕЗЕТ.
		-- Он и приплыл сюда тушиться: заберётся обратно с огнём — снова побежит
		-- к воде, и так по кругу. Ждём в воде, пока пламя не собьётся.
		while alive() and pirate:GetAttribute("OnFire") do
			play(tracks.swim or tracks.walk, true, "MeleeRun")
			task.wait(0.2)
		end

		local rp = raftPart()
		if rp and alive() and not startOnDeck then
			play(tracks.jump, false, "Fire_Shake")
			local startPos = hrp.Position
			local c = nearestRaftPoint(startPos) or raftCenter() or rp.Position -- board toward the nearest piece, not centre
			local toC = Vector3.new(c.X - startPos.X, 0, c.Z - startPos.Z)
			local dir = (toC.Magnitude > 0.01) and toC.Unit or Vector3.new(0, 0, 1)
			-- land point stored in the raft's frame so the jump tracks the MOVING deck
			-- (otherwise it lands where the deck used to be → behind/under the raft)
			local landLocal = rp.CFrame:PointToObjectSpace(startPos + dir * BOARD_FORWARD)
			local bt = 0
			while bt < BOARD_TIME and alive() do
				local dt = RunService.Heartbeat:Wait()
				bt += dt
				local a = math.min(bt / BOARD_TIME, 1)
				local now = raftPart() or rp
				local land = now.CFrame:PointToWorldSpace(landLocal)
				local deckY = now.Position.Y + DECK_RISE
				local y = lerp(startPos.Y, deckY, a) + BOARD_HEIGHT * math.sin(a * math.pi)
				local faceDir = Vector3.new(land.X - hrp.Position.X, 0, land.Z - hrp.Position.Z)
				faceMove(hrp, lerp(startPos.X, land.X, a), y, lerp(startPos.Z, land.Z, a),
					faceDir.Magnitude > 0.01 and faceDir or dir)
			end
		end

		-- ⚠️ СТАВИМ ЕГО НА ПАЛУБУ ДО ВКЛЮЧЕНИЯ ФИЗИКИ.
		-- Прыжок кончается у самой кромки, и стоило включить столкновения, как
		-- тело задевало борт и сваливалось ПОД плот — оттуда оно потом долго
		-- выкарабкивалось. Луч вниз находит настил, и мы садим пирата ровно на
		-- него; не нашёл (перелетел за борт) — оставляем как есть, доплывёт.
		do
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { pirate }
			local from = hrp.Position + Vector3.new(0, 14, 0)
			local hit = workspace:Raycast(from, Vector3.new(0, -40, 0), params)
			if hit and hit.Instance and hit.Instance:IsDescendantOf(workspace) then
				local deck = hit.Instance:FindFirstAncestor("Raft") and hit.Position or nil
				if deck then
					hrp.CFrame = CFrame.new(deck + Vector3.new(0, 3.5, 0)) * (hrp.CFrame - hrp.CFrame.Position)
				end
			end
			for _, d in ipairs(pirate:GetDescendants()) do
				if d:IsA("BasePart") then
					d.AssemblyLinearVelocity = Vector3.zero
				end
			end
		end

		-- once aboard, switch to REAL physics so it walks the deck, collides with walls,
		-- and rides the moving raft like the player (uncollide/kinematic was for the water only)
		for _, d in ipairs(pirate:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Massless = false
				d.CanCollide = (d ~= hrp) and (d:FindFirstAncestorWhichIsA("Tool") == nil)
			end
		end
		hum.EvaluateStateMachine = true
		hum.AutoRotate = true
		hum.WalkSpeed = WALK_SPEED
		boarded = true -- теперь (и только теперь) сторож под-плотом может его убрать

		-- ⚠️ ПАДАТЬ И ЛЕЖАТЬ ЕМУ НЕЛЬЗЯ.
		-- После жёсткой посадки Humanoid уходил в FallingDown и не поднимался
		-- обратно: пират валялся на боку до конца жизни. Эти состояния ему не
		-- нужны вовсе — он либо стоит и дерётся, либо плывёт.
		hum.PlatformStand = false
		pcall(function()
			hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)

		-- ⚠️ СТОРОЖ «ПОД ПЛОТОМ»: ВЫТАЛКИВАЕМ НАВЕРХ, А НЕ УБИВАЕМ.
		-- Заплыв под плот, он упирался в него телом, и плот вставал колом (тот же
		-- эффект, из-за которого когда-то отключили RaftUnderGuard). Проверяем
		-- габарит и глубину: оказался внутри и ниже палубы — ставим на настил.
		task.spawn(function()
			while alive() and pirate.Parent do
				task.wait(0.3)
				local r = workspace:FindFirstChild("Raft")
				local rp3 = r and r.PrimaryPart
				if rp3 then
					local cf, size = r:GetBoundingBox()
					local lp = cf:PointToObjectSpace(hrp.Position)
					local inside = math.abs(lp.X) <= size.X * 0.5 and math.abs(lp.Z) <= size.Z * 0.5
					local deckY = rp3.Position.Y + DECK_RISE
					if inside and hrp.Position.Y < deckY - 3 then
						hrp.CFrame = CFrame.new(hrp.Position.X, deckY + 3, hrp.Position.Z)
							* (hrp.CFrame - hrp.CFrame.Position)
						hrp.AssemblyLinearVelocity = Vector3.zero
					end
				end
			end
		end)

		-- ⚠️ ЧЕМ ОН БЬЁТ. Клип удара выбираем по тому, что у него в руках: с
		-- револьвером махать саблей — то, что и бросилось в глаза. Оружие ищем
		-- один раз: на палубе оно уже не поменяется.
		local hasGun = false
		for _, d in ipairs(pirate:GetDescendants()) do
			local n = d.Name:lower()
			if n:find("revolver") or n:find("pistol") or n:find("gun") or n:find("rifle") then
				hasGun = true
				break
			end
		end
		-- В упор из револьвера не палят — бьют тем, что в руке: тычок стволом и
		-- удар прикладом, вперемешку. Сабельный замах остаётся тем, у кого сабля.
		local GUN_MELEE = { "Melee_Jab", "Melee_Bash" }
		local meleeIx = 0
		local function attackClip()
			if not hasGun then return "SabreSwing" end
			meleeIx = meleeIx % #GUN_MELEE + 1
			return GUN_MELEE[meleeIx]
		end
		local WALK_CLIP = hasGun and "PistolWalk" or "MeleeRun"

		-- 4) ATTACK — walk after the nearest player (Humanoid physics), melee on a cooldown
		local lastAtk, lockedObst, obstSeen = 0, nil, 0
		local overboard = false
		local inWaterFor = 0   -- сколько подряд он в воде за бортом
		while alive() do
			local dt = RunService.Heartbeat:Wait()
			local rp2 = raftPart()
			local plr = nearestPlayer(hrp.Position)
			local char = plr and plr.Character
			local target = char and char:FindFirstChild("HumanoidRootPart")

			-- ⚠️ ГОРИТ — ВЕСЬ ЦИКЛ БОЯ ПРОПУСКАЕМ.
			-- Раньше проверка стояла только в ветке «в упор», и пока он бежал за
			-- игроком, его MoveTo спорил с бегом к воде: тушиться он не уходил.
			-- Теперь пока пламя на нём, им целиком распоряжается огнемёт — тот
			-- и гонит его в океан, а погаснув, пират возвращается к абордажу.
			if pirate:GetAttribute("OnFire") then
				-- ничего не делаем: ни шагу, ни удара

			elseif target and rp2 then
				local deckY = rp2.Position.Y + DECK_RISE
				local pos = hrp.Position
				local flat = Vector3.new(target.Position.X - pos.X, 0, target.Position.Z - pos.Z)
				local dist = flat.Magnitude
				local dir = (dist > 0.01) and flat.Unit or hrp.CFrame.LookVector
				if dist > ATTACK_DIST then
					local obst = obstacleInFront(dir)
					if obst and obst.Parent then lockedObst, obstSeen = obst, os.clock() end
					-- keep smashing the locked obstacle across brief raycast misses (0.3s grace);
					-- drop it once it's broken/gone or hasn't been seen for a moment
					local fresh = lockedObst and lockedObst.Parent and not lockedObst:GetAttribute("Broken")
						and (os.clock() - obstSeen < 0.3)
					if fresh then -- a wall/building blocks the path → smash through it
						play(tracks.attack, true, attackClip())
						hum:MoveTo(hrp.Position)
						-- one hit per attack SWING (the anim's length) so EVERY swing lands damage
						local swing = (tracks.attack and tracks.attack.Length > 0.1) and tracks.attack.Length or 0.7
						if os.clock() - lastAtk > swing then
							lastAtk = os.clock()
							damageObstacle(lockedObst, ATTACK_DAMAGE)
						end
					else
						lockedObst = nil
						play(tracks.walk, true, WALK_CLIP) -- walking toward the player
						hum:MoveTo(target.Position) -- Humanoid pathing: collides with walls, rides the raft
					end
				else
					play(tracks.attack, true, attackClip()) -- in reach → attack
					hum:MoveTo(hrp.Position) -- hold position and swing
					if os.clock() - lastAtk > ATTACK_INTERVAL then
						lastAtk = os.clock()
						local phum = char:FindFirstChildOfClass("Humanoid")
						if phum and phum.Health > 0 then phum:TakeDamage(ATTACK_DAMAGE) end
					end
				end
			end

			-- ⚠️ ОКАЗАЛСЯ В ВОДЕ — ВОЗВРАЩАЕМСЯ К ПЛАВАНИЮ, А НЕ ХОДИМ ПО НЕЙ.
			-- На палубе он живёт обычной физикой Humanoid, а плавание у него
			-- отключено (иначе у самой кромки он «плыл» вместо ходьбы). Стоило
			-- ему сойти за борт — тушиться или просто оступиться, — и он шагал
			-- по поверхности моря и не мог догнать уплывающий плот. Теперь такой
			-- случай ловим и запускаем конвейер заново: подплыть → запрыгнуть.
			-- ⚠️ ПЕРЕЗАПУСК ТОЛЬКО ПОСЛЕ ВЫДЕРЖКИ.
			-- Мгновенная проверка срабатывала и когда он просто стоял у кромки:
			-- конвейер перезапускался, пират тут же снова оказывался на палубе —
			-- и так по кругу. Считаем, сколько он НЕПРЕРЫВНО пробыл в воде за
			-- пределами плота, и уходим плыть только если это всерьёз.
			if rp2 and hrp.Position.Y <= waterY + 1.5 then
				local cf, size = raft():GetBoundingBox()
				local lp = cf:PointToObjectSpace(hrp.Position)
				local outside = math.abs(lp.X) > size.X * 0.5 + 1 or math.abs(lp.Z) > size.Z * 0.5 + 1
				inWaterFor = outside and (inWaterFor + dt) or 0
			else
				inWaterFor = 0
			end
			if inWaterFor >= 0.8 then
				overboard = true
				break
			end
		end

		-- сошёл за борт: снова кинематика и весь путь к плоту сначала
		if overboard and alive() then
			task.wait(0.2)
			local wy = waterSurfaceAt(hrp.Position.X, hrp.Position.Z, waterY, { pirate })
			runPirate(pirate, wy, false)
		end
	end)
end

-- ── spawner ──
local function activeCount()
	local n = 0
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m.Name == TEMPLATE then n += 1 end
	end
	return n
end

-- a horizontal unit direction. With dirOverride → that side (plus a little angular jitter so a
-- multi-enemy wave fans out instead of stacking); without → a fully random side (old behaviour).
local function waveSideDir(dirOverride, spread)
	if dirOverride then
		local base = Vector3.new(dirOverride.X, 0, dirOverride.Z)
		if base.Magnitude > 0.05 then
			base = base.Unit
			local j = (math.random() - 0.5) * (spread or 0)
			local c, s = math.cos(j), math.sin(j)
			return Vector3.new(base.X * c - base.Z * s, 0, base.X * s + base.Z * c)
		end
	end
	local a = math.random() * math.pi * 2
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

local warned = false
local function spawnPirate(dirOverride, hpMult)
	local raft = workspace:FindFirstChild("Raft")
	local rp = raft and raft.PrimaryPart
	if not rp then return end
	local template = AssetFind.find(TEMPLATE)
	if not template then
		if not warned then
			warned = true
			warn("[SwimmingPirate] no '" .. TEMPLATE .. "' model in ReplicatedStorage — can't spawn swimmers")
		end
		return
	end
	local center = (_G.GetRaftCenter and _G.GetRaftCenter()) or rp.Position
	-- radius of the REAL welded raft (ShipCombat filters out broken-off strays); the whole-model
	-- bounding box stretches over drifted-away pieces and put spawns further out than the ships
	local rad = _G.GetRaftRadius and _G.GetRaftRadius()
	if not rad then
		local _, rsize = raft:GetBoundingBox()
		rad = math.max(rsize.X, rsize.Z) * 0.5
	end
	local dir = waveSideDir(dirOverride, 0.6)
	-- НОРМИРУЕМ ВРЕМЯ ПОДХОДА: если плот плывёт НАВСТРЕЧУ точке спавна, скорость сближения =
	-- скорость плота + скорость пирата, и фиксированный отступ съедался за пару секунд.
	-- Отступ = скорость сближения × целевое время → подход занимает ~одинаково с любой стороны.
	local APPROACH_TIME = 14
	local vel = rp.AssemblyLinearVelocity or Vector3.zero
	local closing = SWIM_SPEED + Vector3.new(vel.X, 0, vel.Z):Dot(Vector3.new(dir.X, 0, dir.Z).Unit)
	closing = math.max(closing, 2)
	local spawnDist = rad + math.clamp(closing * APPROACH_TIME, 60, 280)
	-- НЕ спавним на суше острова: подбираем ближайший чистый угол над водой
	local xz = WaterSpawn.pick(center, dir, spawnDist, rp.Position.Y + 80, { raft })
	local waterY = waterSurfaceAt(xz.X, xz.Z, rp.Position.Y, { raft })
	print(("[WaveDebug] pirate: center=(%.0f, %.0f) rad=%.0f spawn=(%.0f, %.0f) dir=(%.2f, %.2f)"):format(
		center.X, center.Z, rad, xz.X, xz.Z, dir.X, dir.Z))

	local pirate = template:Clone()
	pirate.Name = TEMPLATE
	pirate:SetAttribute("WaterImmune", true) -- they live in the sea — ToxicWater must not hurt them
	if pirate:IsA("Model") and not pirate.PrimaryPart then
		pirate.WorldPivot = CFrame.new(pirate:GetBoundingBox().Position)
	end
	-- start UNDER the water, facing the raft, so it's seen rising out of the sea
	local startPos = Vector3.new(xz.X, waterY - SUBMERGE_DEPTH, xz.Z)
	pcall(function() pirate:PivotTo(CFrame.lookAt(startPos, Vector3.new(center.X, startPos.Y, center.Z))) end)
	pirate.Parent = workspace
	runPirate(pirate, waterY)
	-- tougher on later nights: WaveDirector passes an HP multiplier (the HP bar reads MaxHealth live)
	if hpMult and hpMult ~= 1 then
		local hum = pirate:FindFirstChildWhichIsA("Humanoid", true)
		if hum then
			hum.MaxHealth = PIRATE_HP * hpMult
			hum.Health = hum.MaxHealth
		end
	end
	return pirate -- WaveDirector tracks wave participants until they're all dead
end

local SPAWN_ENABLED = false -- TEMP: swimming pirates OFF (set true to re-enable)
task.spawn(function()
	while true do
		task.wait(SPAWN_INTERVAL)
		if SPAWN_ENABLED and activeCount() < MAX_ACTIVE then
			spawnPirate()
		end
	end
end)

-- wave control: WaveDirector spawns a swimmer on demand from a chosen side (continuous loop above stays off)
_G.SpawnSwimmingPirate = function(dir, hpMult) return spawnPirate(dir, hpMult) end

-- ЧУЖОЙ НПС СТАНОВИТСЯ АБОРДАЖНИКОМ.
-- Охранник с горящего катера прыгает в море — и дальше ему нужен ровно этот
-- конвейер: плыть к плоту, забраться, драться. Модель уже есть в мире, поэтому
-- спавн пропускаем и запускаем на ней тот же runPirate.
-- ⚠️ ЖДЁМ, ПОКА ОН РЕАЛЬНО УПАДЁТ В ВОДУ. Запустить плавание в воздухе значит
-- сразу задать ему высоту поверхности и оборвать прыжок на полпути — сперва
-- даём телу долететь, и только потом передаём управление.
_G.SwimBoarderFrom = function(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return false end
	if model:GetAttribute("Boarding") then return false end
	model:SetAttribute("Boarding", true)
	model:SetAttribute("WaterImmune", true)

	task.spawn(function()
		local hum = model:FindFirstChildWhichIsA("Humanoid", true)
		local hrp = (hum and hum.RootPart) or model:FindFirstChild("HumanoidRootPart", true)
		if not (hum and hrp) then return end
		if not model.PrimaryPart then
			model.WorldPivot = CFrame.new(model:GetBoundingBox().Position)
		end
		if model.Parent ~= workspace then model.Parent = workspace end

		local rp = workspace:FindFirstChild("Raft")
		rp = rp and rp.PrimaryPart

		-- ждём касания воды, но не дольше полутора секунд: дуга прыжка короткая,
		-- а дольше ждать нельзя — тело всё это время падает физикой
		local deadline = os.clock() + 1.5
		local waterY
		repeat
			task.wait(0.05)
			if not (model.Parent and hum.Health > 0) then return end
			local y = waterSurfaceAt(hrp.Position.X, hrp.Position.Z,
				rp and rp.Position.Y or hrp.Position.Y, { model })
			if hrp.Position.Y <= y + 2 then waterY = y end
		until waterY or os.clock() > deadline

		waterY = waterY or waterSurfaceAt(hrp.Position.X, hrp.Position.Z,
			rp and rp.Position.Y or hrp.Position.Y, { model })

		-- ПОПАЛ ПРЯМО НА ПЛОТ? Тогда плыть некуда — сразу в бой.
		-- ⚠️ ПРОВЕРЯЕМ ДО ПОСТАНОВКИ НА ВОДУ, иначе сами же стащим его с палубы.
		local raft = workspace:FindFirstChild("Raft")
		local onDeck = false
		if raft and hrp.Position.Y > waterY + 1 then
			local cf, size = raft:GetBoundingBox()
			local lp = cf:PointToObjectSpace(hrp.Position)
			onDeck = math.abs(lp.X) <= size.X * 0.5 and math.abs(lp.Z) <= size.Z * 0.5
		end

		-- ⚠️ СТАВИМ ЕГО НА ПОВЕРХНОСТЬ И ГАСИМ СКОРОСТЬ.
		-- Дальше движение кинематическое — руками двигаем корень каждый кадр, —
		-- но до этого тело падало физикой и успевало уйти вниз. Без сброса оно
		-- продолжало тонуть: остаточная скорость спорит с нашей постановкой, и
		-- со стороны пират просто уходит на дно вместо того, чтобы плыть.
		if not onDeck then
			local center = (rp and rp.Position) or hrp.Position
			local face = Vector3.new(center.X, waterY, center.Z)
			local from = Vector3.new(hrp.Position.X, waterY - 1, hrp.Position.Z)
			pcall(function()
				model:PivotTo(CFrame.lookAt(from, (from - face).Magnitude > 1 and face or from + Vector3.new(0, 0, 1)))
			end)
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.AssemblyLinearVelocity = Vector3.zero
				d.AssemblyAngularVelocity = Vector3.zero
			end
		end

		print(("[Абордаж] охранник %s (y=%.1f, поверхность %.1f)"):format(
			onDeck and "запрыгнул прямо на плот — сразу в бой" or "в воде — поплыл к плоту",
			hrp.Position.Y, waterY))
		runPirate(model, waterY, onDeck)
	end)
	return true
end

print("[SwimmingPirate] loaded")
