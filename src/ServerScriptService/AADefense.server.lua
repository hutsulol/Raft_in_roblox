-- AADefense.server.lua
-- Raft anti-air ("ПВО"): the pre-placed Deffender_* turrets shoot down incoming
-- enemy shells (ShipShell / Magma_ball) before they reach the raft.
--   • Load with logs — press E on the turret (max 3). Each loaded shell shows one
--     of the 3 "Wooden_Snaryad" barrels.
--   • The WHOLE turret (base + barrels + loaded shells) rotates as one rigid unit
--     to face the nearest enemy ship. It rides the raft (welded), so it stays in
--     sync and never needs a nudge.
--   • When that ship fires, it launches a loaded shell as a real physics projectile
--     (velocity + gravity, like a cannon) out of the barrel. A hit detonates the
--     incoming round in the sky. Accuracy is tunable (ACCURACY).
--   • Pressing E lights up the action radius (dashed circle outline).

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradeConfig = require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig"))

-- ── tunables ──
local AA_PREFIX       = "Deffender_"      -- AA turret models (Deffender_1, Deffender_2, …)
local BASE_NAME       = "Deffender"       -- the mount part used as the rigid root
local BARREL_PREFIX   = "Wooden_Snaryad"  -- the 3 loadable shells / barrels
local MAX_AMMO        = 3
local LOG_ITEM        = "Log"
local YAW_LIMIT       = math.rad(25)      -- field of view: ±25° (50° forward cone)
local YAW_SPEED       = math.rad(45)      -- turret turn rate (deg/s) — slow + smooth
local RANGE           = 120               -- studs the turret watches / can hit within
local ACCURACY        = 0.8               -- chance an interception connects (8/10)
local INTERCEPT_SPEED = 340               -- launched-shell muzzle speed (studs/s)
local KILL_RADIUS     = 22                -- how close the shot must pass the round to kill it
local SCAN_INTERVAL   = 0.1
local RANGE_SHOW_TIME = 3
local RING_DASHES     = 40
local SHELL_NAMES     = { ShipShell = true, Magma_ball = true }
local SHIP_PREFIXES   = { "Ship_enemy", "Magma_Ship" }

local recOf = {}
local activeShells = {}
local activeShips = {}

-- Our cannon shells carry a "creator" ObjectValue (set by CannonControl); enemy ship
-- shells don't. So the AA never targets or detonates on our own rounds — even though a
-- magma-cannon shell's inner part is still named "Magma_ball".
local function isFriendlyShell(part)
	local inst = part
	while inst and inst.Parent and inst.Parent ~= workspace do
		inst = inst.Parent
	end
	return inst ~= nil and inst:FindFirstChild("creator", true) ~= nil
end

local function longestAxisDir(cf, size)
	if size.Z >= size.X and size.Z >= size.Y then return cf.LookVector
	elseif size.X >= size.Y then return cf.RightVector
	else return cf.UpVector end
end

local function shipPos(m)
	if m.PrimaryPart then return m.PrimaryPart.Position end
	local ok, cf = pcall(function() return m:GetPivot() end)
	return ok and cf.Position or nil
end

-- signed yaw (around world-up) to turn the turret's rest forward onto targetPos
local function computeYaw(rec, targetPos)
	local rp = rec.raftPart
	if not (rp and rp.Parent) then return nil end
	local fwd = rp.CFrame:VectorToWorldSpace(rec.fwdLocal)
	fwd = Vector3.new(fwd.X, 0, fwd.Z)
	if fwd.Magnitude < 1e-3 then return nil end
	fwd = fwd.Unit
	local pivot = rp.CFrame:PointToWorldSpace(rec.pivotLocal)
	local toT = Vector3.new(targetPos.X - pivot.X, 0, targetPos.Z - pivot.Z)
	if toT.Magnitude < 1e-3 then return nil end
	toT = toT.Unit
	return math.atan2(fwd:Cross(toT).Y, fwd:Dot(toT))
end

-- ── action radius (dashed circle outline) ──
local function showRange(rec)
	for _, d in ipairs(rec.ringDashes) do d.Transparency = 0.15 end
	rec.ringShownAt = os.clock()
	if rec.ringTask then return end
	rec.ringTask = true
	task.spawn(function()
		while os.clock() - (rec.ringShownAt or 0) < RANGE_SHOW_TIME do task.wait(0.2) end
		for _, d in ipairs(rec.ringDashes) do if d.Parent then d.Transparency = 1 end end
		rec.ringTask = nil
	end)
end

-- show the E prompt only while there's a free slot (hidden when fully loaded)
local function updatePrompt(rec)
	if rec.prompt then rec.prompt.Enabled = rec.ammo < MAX_AMMO end
end

-- ── load (E) ──
local function loadAA(rec, plr)
	showRange(rec)
	if rec.ammo >= MAX_AMMO then
		if _G.NotifyPlayer then
			_G.NotifyPlayer(plr, { type = "info", icon = "🎯", title = "ПВО заряжено",
				body = "Все снаряды на месте" })
		end
		return
	end
	-- ⚠️ ОТКАЗ ГОВОРИТ О СЕБЕ ВСЛУХ.
	-- Раньше нажатие E без брёвен просто ничего не делало: подсказка на месте,
	-- клавиша нажимается, ничего не происходит — и понять, что не хватает
	-- ресурса, было неоткуда.
	local inv = _G.GetInventory and _G.GetInventory(plr)
	if not inv or (inv[LOG_ITEM] or 0) < 1 then
		if _G.NotifyPlayer then
			_G.NotifyPlayer(plr, { type = "warn", icon = "log", title = "Нет брёвен",
				body = "Для снаряда нужно бревно" })
		end
		return
	end
	if _G.RemoveResourceFromInventory then
		_G.RemoveResourceFromInventory(plr, LOG_ITEM, 1)
	else
		inv[LOG_ITEM] = (inv[LOG_ITEM] or 0) - 1
	end
	if _G.SendInventory then _G.SendInventory(plr) end
	for _, b in ipairs(rec.barrels) do
		if not b.loaded then
			b.loaded = true
			b.part.Transparency = b.origT
			rec.ammo += 1
			break
		end
	end
	updatePrompt(rec)
end

local function pickBarrel(rec, targetPos)
	local best, bestDot = nil, -2
	for _, b in ipairs(rec.barrels) do
		if b.loaded then
			local dir = targetPos - b.part.Position
			if dir.Magnitude > 1e-3 then
				local d = longestAxisDir(b.part.CFrame, b.part.Size).Unit:Dot(dir.Unit)
				if d > bestDot then bestDot = d; best = b end
			end
		end
	end
	return best
end

-- refill a fired slot with a fresh HIDDEN shell so it can be reloaded — no visible
-- swap (the player sees the real shell fly out, not a new one pop in its place)
local function respawnSlot(rec, b)
	local newPart = b.template:Clone()
	newPart.Anchored = false
	newPart.Massless = true
	newPart.CanCollide = false
	newPart.Transparency = 1
	newPart:SetAttribute("_NoHighlight", true)
	newPart.CFrame = rec.root.CFrame * b.restRel
	newPart.Parent = rec.model
	local w = Instance.new("WeldConstraint"); w.Part0 = rec.root; w.Part1 = newPart; w.Parent = newPart
	b.part = newPart
	b.loaded = false
end

-- launch the ACTUAL loaded shell out of the barrel, keeping its own angle/orientation
local function fireInterceptor(rec, shell)
	local b = pickBarrel(rec, shell.Position)
	if not b then return end
	local real = b.part
	rec.ammo -= 1

	-- detach the real shell from the turret and fling it with physics. It keeps its
	-- own orientation; direction = from the mount out through the shell (its real angle).
	for _, d in ipairs(rec.model:GetDescendants()) do
		if (d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D")) and (d.Part0 == real or d.Part1 == real) then
			d:Destroy()
		end
	end
	-- aim the launch at where the round WILL be (lead + counter gravity drop) so it
	-- actually connects. The shell still keeps its own orientation as it flies.
	local muzzle = real.Position
	local svel = shell.AssemblyLinearVelocity
	local flightT = math.max((shell.Position - muzzle).Magnitude / INTERCEPT_SPEED, 0.05)
	-- прокачка ПВО (меню «Прокачка оружия» в лобби): турели общие для
	-- команды плота, поэтому берём лучший уровень среди игроков сервера.
	-- +3% точности и +10% радиуса подрыва за звезду.
	local upgStars = 0
	for _, p in ipairs(Players:GetPlayers()) do
		local s = p:GetAttribute(UpgradeConfig.ATTR_PREFIX .. "Deffender") or 0
		if s > upgStars then upgStars = s end
	end
	local killRadius = KILL_RADIUS * (1 + 0.10 * upgStars)
	local willHit = math.random() <= math.min(0.98, ACCURACY + 0.03 * upgStars)
	local aimPoint = shell.Position + svel * flightT + Vector3.new(0, 0.5 * workspace.Gravity * flightT * flightT, 0)
	if not willHit then
		aimPoint += Vector3.new(math.random(-22, 22), math.random(-8, 18), math.random(-22, 22))
	end
	local dir = aimPoint - muzzle
	dir = (dir.Magnitude > 1e-3) and dir.Unit or Vector3.new(0, 1, 0)
	real.Massless = false -- give it mass so gravity arcs it
	real.CanCollide = false
	real.CanQuery = false
	real.Parent = workspace
	real.AssemblyLinearVelocity = dir * INTERCEPT_SPEED

	respawnSlot(rec, b) -- hidden refill, ready to load again
	updatePrompt(rec)

	local dead = false
	local function detonate()
		if dead then return end
		dead = true
		if willHit and shell.Parent then
			local exp = Instance.new("Explosion")
			exp.Position = shell.Position
			exp.BlastPressure = 0
			exp.BlastRadius = 8
			exp.Parent = workspace
			shell:Destroy()
		end
		if real.Parent then
			local poof = Instance.new("Explosion")
			poof.Position = real.Position
			poof.BlastPressure = 0
			poof.BlastRadius = 3
			poof.Parent = workspace
			real:Destroy()
		end
	end
	real.Touched:Connect(function(hit) if SHELL_NAMES[hit.Name] and not isFriendlyShell(hit) then detonate() end end)
	task.spawn(function()
		local t = 0
		while not dead and real.Parent and t < 4 do
			local dt = RunService.Heartbeat:Wait()
			t += dt
			if willHit and shell.Parent and (real.Position - shell.Position).Magnitude < killRadius then
				detonate()
				return
			end
		end
		if not dead and real.Parent then real:Destroy() end
	end)
end

-- ── per-turret brain ──
local function engageLoop(rec)
	while rec.model.Parent do
		task.wait(SCAN_INTERVAL)
		if not (rec.raftPart and rec.raftPart.Parent) then continue end
		local pivot = rec.pivotWorld()

		-- 1) a loaded turret fires at the nearest incoming shell
		if rec.ammo > 0 then
			local target, targetD, targetYaw = nil, RANGE, 0
			for shell in pairs(activeShells) do
				if not shell.Parent then
					activeShells[shell] = nil
				elseif not shell:GetAttribute("AA_engaged") then
					local dist = (shell.Position - pivot).Magnitude
					if dist <= targetD then
						local yaw = computeYaw(rec, shell.Position)
						if yaw and math.abs(yaw) <= YAW_LIMIT then target, targetD, targetYaw = shell, dist, yaw end
					end
				end
			end
			if target then
				rec.tgtYaw = targetYaw
				target:SetAttribute("AA_engaged", true)
				fireInterceptor(rec, target)
				continue
			end
		end

		-- 2) otherwise face the nearest enemy ship (so it's ready to react)
		local bestYaw, bestD = nil, RANGE
		for m in pairs(activeShips) do
			if not m.Parent then
				activeShips[m] = nil
			else
				local pos = shipPos(m)
				if pos then
					local dist = (pos - pivot).Magnitude
					if dist <= bestD then
						local yaw = computeYaw(rec, pos)
						if yaw and math.abs(yaw) <= YAW_LIMIT then bestYaw, bestD = yaw, dist end
					end
				end
			end
		end
		rec.tgtYaw = bestYaw or 0
	end
	recOf[rec.model] = nil
end

-- ── setup a turret ──
local function setupAA(model)
	if recOf[model] then return end

	-- the turret must ride the raft (so its rotation assembly stays awake + synced)
	local raft = workspace:FindFirstChild("Raft")
	local raftPart = raft and raft.PrimaryPart
	if not raftPart then warn("[AADefense] no Raft.PrimaryPart yet for " .. model.Name); return end

	model:SetAttribute("_NoHighlight", true)

	local root = model.PrimaryPart or model:FindFirstChild(BASE_NAME)
	if not (root and root:IsA("BasePart")) then
		local big, bigVol = nil, -1
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local v = d.Size.X * d.Size.Y * d.Size.Z
				if v > bigVol then bigVol = v; big = d end
			end
		end
		root = big
	end
	if not root then warn("[AADefense] no parts in " .. model.Name); return end

	local barrels, allParts = {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			allParts[#allParts + 1] = d
			if d.Name:sub(1, #BARREL_PREFIX) == BARREL_PREFIX then table.insert(barrels, d) end
		end
	end
	table.sort(barrels, function(a, b) return a.Name < b.Name end)
	if #barrels == 0 then warn("[AADefense] no barrels in " .. model.Name); return end

	local basePart = model:FindFirstChild(BASE_NAME) or root
	local barrelCentroid = Vector3.zero
	for _, b in ipairs(barrels) do barrelCentroid += b.Position end
	barrelCentroid /= #barrels

	-- make the WHOLE model one rigid, massless body welded to its root, then attach
	-- the root to the raft with a Motor6D we rotate. Massless → the (light) raft
	-- stays the assembly root, so the motor turns the turret, not the raft.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") then d:Destroy() end
	end
	for _, p in ipairs(allParts) do
		p.Anchored = false
		p.Massless = true
		p:SetAttribute("_NoHighlight", true)
		if p ~= root then
			local w = Instance.new("WeldConstraint"); w.Part0 = root; w.Part1 = p; w.Parent = p
		end
	end
	local motor = Instance.new("Motor6D")
	motor.Name = "AAyaw"
	motor.Part0 = raftPart
	motor.Part1 = root
	local restC0 = raftPart.CFrame:Inverse() * root.CFrame
	motor.C0 = restC0
	motor.Parent = root

	-- rotation pivot (the mount) + rest forward, stored in the raft part's frame
	local pivotLocal = raftPart.CFrame:PointToObjectSpace(basePart.Position)
	local fwdW = barrelCentroid - basePart.Position
	fwdW = Vector3.new(fwdW.X, 0, fwdW.Z)
	if fwdW.Magnitude < 0.1 then fwdW = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z) end
	if fwdW.Magnitude < 0.1 then fwdW = Vector3.new(0, 0, -1) end
	local fwdLocal = raftPart.CFrame:VectorToObjectSpace(fwdW.Unit)

	-- loaded-shell visibility (ammo). Start empty.
	local brecs = {}
	for _, b in ipairs(barrels) do
		local tmpl = b:Clone() -- clean copy used to refill the slot after firing the real shell
		for _, d in ipairs(tmpl:GetDescendants()) do
			if d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") then d:Destroy() end
		end
		tmpl.Parent = nil
		brecs[#brecs + 1] = {
			part = b, loaded = false, origT = b.Transparency,
			restRel = root.CFrame:Inverse() * b.CFrame, template = tmpl,
		}
		b.Transparency = 1
	end

	local rec = {
		model = model, root = root, motor = motor, raftPart = raftPart, restC0 = restC0,
		pivotLocal = pivotLocal, fwdLocal = fwdLocal, barrels = brecs, ammo = 0,
		ringDashes = {}, curYaw = 0, tgtYaw = 0,
	}
	rec.pivotWorld = function() return raftPart.CFrame:PointToWorldSpace(pivotLocal) end
	recOf[model] = rec

	-- dashed FOV cone (±YAW_LIMIT around the rest forward) out to RANGE, welded to the
	-- RAFT so it stays fixed (it shows the field of view, and does NOT spin with the turret)
	local center = basePart.Position
	local coneFwd = Vector3.new(fwdW.X, 0, fwdW.Z).Unit
	local function dirAt(a)
		local c, s = math.cos(a), math.sin(a)
		return Vector3.new(coneFwd.X * c - coneFwd.Z * s, 0, coneFwd.X * s + coneFwd.Z * c).Unit
	end
	local function addDash(a, b)
		local d = b - a
		local len = d.Magnitude
		if len < 0.05 then return end
		local dash = Instance.new("Part")
		dash.Name = "AARingDash"
		dash.Size = Vector3.new(0.5, 0.4, len)
		dash.CFrame = CFrame.lookAt(a + d * 0.5, b)
		dash.Anchored = false
		dash.Massless = true
		dash.CanCollide = false
		dash.CanQuery = false
		dash.CastShadow = false
		dash.Material = Enum.Material.Neon
		dash.Color = Color3.fromRGB(90, 200, 255)
		dash.Transparency = 1
		dash:SetAttribute("_NoHighlight", true)
		dash.Parent = model
		local w = Instance.new("WeldConstraint"); w.Part0 = raftPart; w.Part1 = dash; w.Parent = dash
		rec.ringDashes[#rec.ringDashes + 1] = dash
	end
	local ARC_SEGS = 28
	for i = 0, ARC_SEGS - 1 do
		if i % 2 == 0 then -- dash / gap along the far arc
			local a1 = -YAW_LIMIT + (i / ARC_SEGS) * (2 * YAW_LIMIT)
			local a2 = -YAW_LIMIT + ((i + 1) / ARC_SEGS) * (2 * YAW_LIMIT)
			addDash(center + dirAt(a1) * RANGE, center + dirAt(a2) * RANGE)
		end
	end
	local EDGE_SEGS = 12
	for _, edge in ipairs({ -YAW_LIMIT, YAW_LIMIT }) do
		local endP = center + dirAt(edge) * RANGE
		for i = 0, EDGE_SEGS - 1 do
			if i % 2 == 0 then -- dash / gap along each side edge
				addDash(center + (endP - center) * (i / EDGE_SEGS), center + (endP - center) * ((i + 1) / EDGE_SEGS))
			end
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AALoadPrompt"
	prompt.ActionText = "Зарядить (бревно)"
	prompt.ObjectText = "ПВО"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = basePart
	prompt.Triggered:Connect(function(plr) loadAA(rec, plr) end)
	rec.prompt = prompt
	updatePrompt(rec)

	task.spawn(function() engageLoop(rec) end)
	print("[AADefense] set up turret: " .. model:GetFullName() .. " (" .. #barrels .. " barrels)")
end

-- ── smooth rotation: turn the whole rigid turret toward tgtYaw via the Motor6D ──
RunService.Heartbeat:Connect(function(dt)
	for _, rec in pairs(recOf) do
		local rp = rec.raftPart
		if rp and rp.Parent and rec.root.Parent then
			local tgt = math.clamp(rec.tgtYaw or 0, -YAW_LIMIT, YAW_LIMIT)
			local diff = tgt - (rec.curYaw or 0)
			local step = YAW_SPEED * dt
			if math.abs(diff) <= step then rec.curYaw = tgt
			else rec.curYaw = (rec.curYaw or 0) + math.sign(diff) * step end
			local pivot = rp.CFrame:PointToWorldSpace(rec.pivotLocal)
			local restRootCF = rp.CFrame * rec.restC0
			local desired = CFrame.new(pivot) * CFrame.Angles(0, rec.curYaw, 0) * CFrame.new(pivot):Inverse() * restRootCF
			rec.motor.C0 = rp.CFrame:Inverse() * desired
		end
	end
end)

-- ── discovery ──
local function isEnemyShipName(name)
	for _, p in ipairs(SHIP_PREFIXES) do
		if name:sub(1, #p) == p then return true end
	end
	return false
end
local function trackShell(d)
	if d:IsA("BasePart") and SHELL_NAMES[d.Name] and not isFriendlyShell(d) then -- never our own shells
		activeShells[d] = true
		d.Destroying:Connect(function() activeShells[d] = nil end)
	end
end
local function trackShip(m)
	if m:IsA("Model") and isEnemyShipName(m.Name) then
		activeShips[m] = true
		m.AncestryChanged:Connect(function() if not m.Parent then activeShips[m] = nil end end)
	end
end
local function isAA(inst)
	return inst:IsA("Model") and inst.Name:sub(1, #AA_PREFIX) == AA_PREFIX
end

task.spawn(function()
	local raft = workspace:WaitForChild("Raft", 30)
	if raft then while not raft.PrimaryPart do task.wait(0.2) end end
	print("[AADefense] loaded — scanning for ПВО turrets")
	for _, d in ipairs(workspace:GetDescendants()) do
		if isAA(d) then setupAA(d) end
		trackShell(d)
		trackShip(d)
	end
	workspace.DescendantAdded:Connect(function(d)
		if isAA(d) then
			task.defer(function() if d.Parent then setupAA(d) end end)
		else
			trackShell(d)
			trackShip(d)
		end
	end)
end)
