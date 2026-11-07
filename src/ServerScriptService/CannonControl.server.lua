-- CannonControl.server.lua
-- Player cannon control. The barrel (the part named "Main") is attached to its
-- carriage with a Motor6D, so it rides the raft smoothly with the physics solver
-- and we aim it just by setting the motor's Transform — no anchoring, no per-frame
-- CFrame, so nothing jitters or drifts while the raft sails. Press F to take over:
-- A/D turn left/right, W/S tilt up/down (each capped at 25°). LMB fires a
-- "Bullet_Cannon" from the muzzle (ShipCombat damages ships/enemies), X cancels.
-- The barrel keeps whatever angle it was left at.

local RaftShake = require(game:GetService("ReplicatedStorage"):WaitForChild("RaftShake"))   -- постройка без рывка плота
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatSounds      = require(ReplicatedStorage:WaitForChild("CombatSounds"))
local UpgradeConfig     = require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig"))
local AssetFind         = require(ReplicatedStorage:WaitForChild("AssetFind"))

local MIN_POWER, MAX_POWER = 90, 340
local PROMPT_TEXT = "Управлять пушкой"
local SHIP_PREFIX = "Ship_enemy"
local BARREL_FLIP = false -- set true if shells leave the breech instead of the muzzle

-- aim limits (radians) relative to the barrel's resting pose — 25° to each side
local YAW_LIMIT = math.rad(25)
local PITCH_MIN, PITCH_MAX = -math.rad(25), math.rad(25)
local MUZZLE_CLEAR = 2 -- studs ahead of the pivot to spawn the shell (clear of the barrel)

local ctrlEvent = ReplicatedStorage:FindFirstChild("CannonControl")
if not ctrlEvent then
	ctrlEvent = Instance.new("RemoteEvent")
	ctrlEvent.Name = "CannonControl"
	ctrlEvent.Parent = ReplicatedStorage
end

local controlling = {} -- [player] = cannon
local recOf = {}       -- [cannon] = { cannon, main, carriage, motor, prompt, yaw, pitch }

-- placed models this script controls → how each one fires. magma = burning shell that
-- ignites the target; dmgMult / burnMult scale the impact + fire damage ShipCombat applies.
local CANNON_TYPES = {
	Cannon           = { magma = false, dmgMult = 1, burnMult = 1 },
	MagmaCannon      = { magma = true,  dmgMult = 1, burnMult = 1 },
	Big_Magma_Cannon = { magma = true,  dmgMult = 2, burnMult = 2, flip = true, aimZ = true, splash = 18 },
}
local function cannonKind(inst) -- returns spec, typeName if it's a controllable cannon, else nil
	local n = inst.Name
	if CANNON_TYPES[n] then return CANNON_TYPES[n], n end
	local best, bestLen, bestName
	for name, spec in pairs(CANNON_TYPES) do -- prefix match (e.g. "MagmaCannon_2"); longest wins
		if n:sub(1, #name) == name and (not bestLen or #name > bestLen) then best, bestLen, bestName = spec, #name, name end
	end
	return best, bestName
end

local function findMain(cannon)
	if cannon:IsA("BasePart") and cannon.Name == "Main" then return cannon end
	return cannon:FindFirstChild("Main", true)
end

-- the part the barrel is mounted to: its weld partner that's INSIDE the cannon (NOT the
-- raft — CanonSystem welds every part to the raft, so we must skip those), else the
-- biggest other cannon part.
local function findCarriage(cannon, main)
	for _, d in ipairs(cannon:GetDescendants()) do
		if d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") then
			local other
			if d.Part0 == main then other = d.Part1 elseif d.Part1 == main then other = d.Part0 end
			if other and other:IsA("BasePart") and other:IsDescendantOf(cannon) then return other end
		end
	end
	local best, bestVol
	for _, d in ipairs(cannon:GetDescendants()) do
		if d:IsA("BasePart") and d ~= main then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if not bestVol or v > bestVol then best, bestVol = d, v end
		end
	end
	return best
end

-- Attach the barrel to its carriage with a Motor6D (once). At Transform = identity
-- the barrel sits exactly at its rest pose; we rotate it by setting Transform.
local function ensureRec(cannon)
	local rec = recOf[cannon]
	if rec and rec.main and rec.main.Parent and rec.motor and rec.motor.Parent then return rec end
	local main = findMain(cannon)
	if not main or not main:IsA("BasePart") then return nil end
	local carriage = findCarriage(cannon, main)
	if not carriage or carriage == main then return nil end

	-- free the barrel from rigid joints, then re-attach it with our motor
	for _, d in ipairs(cannon:GetDescendants()) do
		if (d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D")) and (d.Part0 == main or d.Part1 == main) then
			d:Destroy()
		end
	end

	-- Weld every OTHER part rigidly to the carriage so the whole base is ONE immobile
	-- body. The parts may arrive loose (a model whose base pieces aren't welded), which
	-- otherwise makes them drift/fall once unanchored.
	for _, p in ipairs(cannon:GetDescendants()) do
		if p:IsA("BasePart") and p ~= main and p ~= carriage then
			p.Anchored = false
			p.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Name = "CannonRigid"
			w.Part0 = carriage
			w.Part1 = p
			w.Parent = p
		end
	end

	-- Keep the carriage (hence the whole welded base) attached to the raft so it rides
	-- along smoothly; if there's no raft, anchor it so it stays put on land.
	local raft = workspace:FindFirstChild("Raft")
	if raft and raft.PrimaryPart then
		carriage.Anchored = false
		carriage.Massless = true
		local linVel, angVel = raft.PrimaryPart.AssemblyLinearVelocity, raft.PrimaryPart.AssemblyAngularVelocity
		local w = Instance.new("WeldConstraint")
		w.Name = "CannonToRaft"
		w.Part0 = raft.PrimaryPart
		w.Part1 = carriage
		w.Parent = carriage
		-- скорость плота: возврат сразу и ещё раз после шага физики (RaftShake)
		raft.PrimaryPart.AssemblyLinearVelocity = linVel
		raft.PrimaryPart.AssemblyAngularVelocity = angVel
		RaftShake.notify()
	else
		carriage.Anchored = true
	end

	main.Anchored = false
	-- Make the barrel massless + lowest root priority so the (possibly tiny) raft
	-- always stays the assembly root. A Motor6D moves the lighter side of the
	-- joint, so without this a heavy barrel on a light raft turns the RAFT.
	main.Massless = true
	main.RootPriority = -127

	local motor = Instance.new("Motor6D")
	motor.Name = "CannonAim"
	motor.Part0 = carriage
	motor.Part1 = main
	local restC0 = carriage.CFrame:Inverse() * main.CFrame -- rest pose; aiming rotates this
	motor.C0 = restC0
	motor.C1 = CFrame.new()
	motor.Parent = main

	local kindSpec = cannonKind(cannon)
	rec = { cannon = cannon, main = main, carriage = carriage, motor = motor, restC0 = restC0,
		aimZ = kindSpec ~= nil and kindSpec.aimZ == true, yaw = 0, pitch = 0 }
	recOf[cannon] = rec
	return rec
end

-- barrel's forward axis (its longest side), from a CFrame + Size
local function forwardAxis(cf, size)
	local fwd
	if size.Z >= size.X and size.Z >= size.Y then fwd = cf.LookVector
	elseif size.X >= size.Y then fwd = cf.RightVector
	else fwd = cf.UpVector end
	if BARREL_FLIP then fwd = -fwd end
	return fwd
end

local function aim(rec, yaw, pitch)
	rec.yaw = math.clamp(yaw, -YAW_LIMIT, YAW_LIMIT)
	rec.pitch = math.clamp(pitch, PITCH_MIN, PITCH_MAX)
	if rec.motor and rec.motor.Parent then
		-- Rotate via C0 (the stable, replicated joint pose). The massless barrel is
		-- the lighter side, so only IT turns; the raft stays put and it moves
		-- smoothly with the raft (same physics assembly → no jitter, no drift).
		-- aimZ cannons (Big_Magma_Cannon) have their length along local X, so up/down
		-- tilt is around Z (not X) — otherwise pitch just rolls the barrel.
		local ang = rec.aimZ and CFrame.Angles(0, rec.yaw, -rec.pitch) or CFrame.Angles(rec.pitch, rec.yaw, 0)
		rec.motor.C0 = rec.restC0 * ang
	end
end

-- ── freeze player ──
local function freeze(plr, on)
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = on and 0 or 16
		hum.JumpPower = on and 0 or 50
		hum.AutoRotate = not on
	end
	plr:SetAttribute("_CannonControl", on or nil)
end

local function exitAim(plr)
	local cannon = controlling[plr]
	if not cannon then return end
	controlling[plr] = nil
	local rec = recOf[cannon]
	if rec and rec.prompt then rec.prompt.Enabled = true end -- show the F prompt again
	freeze(plr, false)
	ctrlEvent:FireClient(plr, "exit")
end

local function enterAim(plr, cannon)
	if controlling[plr] then return end
	local rec = ensureRec(cannon)
	if not rec then return end
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if (hrp.Position - rec.main.Position).Magnitude > 16 then return end
	controlling[plr] = cannon
	if rec.prompt then rec.prompt.Enabled = false end -- hide the big F prompt while aiming
	freeze(plr, true)
	local spec = cannonKind(cannon)
	ctrlEvent:FireClient(plr, "enter", cannon, rec.main, rec.carriage, rec.restC0, rec.yaw, rec.pitch, spec ~= nil and spec.flip == true, spec ~= nil and spec.aimZ == true)
end

local function fireCannon(rec, plr, power)
	local m = rec.main
	local spec, kindName = cannonKind(rec.cannon)
	spec = spec or { magma = false, dmgMult = 1, burnMult = 1 }
	local fwd = forwardAxis(m.CFrame, m.Size)
	if spec.flip then fwd = -fwd end -- Big_Magma_Cannon's barrel is modelled facing the other way
	local origin = m:GetPivot().Position + fwd * MUZZLE_CLEAR -- fire from the barrel's pivot

	-- a magma cannon fires a burning shell (Magma_ball look + ignites targets); a normal
	-- cannon fires the slate Bullet_Cannon. Either way the part is named "Bullet_Cannon"
	-- so ShipCombat's watcher damages ships/enemies; the magma one is flagged "Magma".
	local isMagma = spec.magma
	local ball
	local template = (isMagma and AssetFind.find("Magma_ball"))
		or AssetFind.find("Bullet_Cannon")
	if template then
		ball = template:Clone()
	else
		ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(1.8, 1.8, 1.8)
		ball.Color = isMagma and Color3.fromRGB(255, 90, 20) or Color3.fromRGB(25, 25, 28)
		ball.Material = isMagma and Enum.Material.Neon or Enum.Material.Slate
	end
	ball.Name = "Bullet_Cannon" -- ShipCombat detects this → damages ships/enemies

	local root = (ball:IsA("BasePart") and ball) or ball.PrimaryPart or ball:FindFirstChildWhichIsA("BasePart")
	for _, d in ipairs(ball:IsA("BasePart") and { ball } or ball:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			if isMagma then
				d.CanQuery = false
				if d ~= root then -- weld a multi-part Magma_ball so it flies as ONE (root lands the hit)
					local w = Instance.new("WeldConstraint")
					w.Part0 = root
					w.Part1 = d
					w.Parent = d
				end
			end
		end
	end
	if root then
		-- прокачка пушки стрелявшим игроком (лобби, меню «Прокачка оружия»)
		local upgStars = (plr and plr:GetAttribute(UpgradeConfig.ATTR_PREFIX .. (kindName or "Cannon"))) or 0
		local upgMult = UpgradeConfig.multFor(upgStars)
		-- ВЫЖИВШИЙ (2 ур.): +урон оружия — сюда же входят пушки
		local survMult = UpgradeConfig.survivorWeaponMult(plr)
		root:SetAttribute("DmgMult", (spec.dmgMult or 1) * upgMult * survMult)   -- ShipCombat scales impact damage
		root:SetAttribute("BurnMult", (spec.burnMult or 1) * upgMult * survMult)  -- ...and burn damage
		if spec.splash then root:SetAttribute("SplashRadius", spec.splash) end -- area blast (Big_Magma_Cannon)
		if isMagma then
			root:SetAttribute("Magma", true) -- ShipCombat sets the hit target on fire
			if not root:FindFirstChildOfClass("Fire") then
				local fire = Instance.new("Fire")
				fire.Size = 6
				fire.Heat = 12
				fire.Color = Color3.fromRGB(255, 120, 30)
				fire.SecondaryColor = Color3.fromRGB(200, 40, 10)
				fire.Parent = root
			end
		end
	end
	if ball:IsA("Model") then
		if not ball.PrimaryPart and root then ball.PrimaryPart = root end
		ball:PivotTo(CFrame.new(origin))
	else
		ball.CFrame = CFrame.new(origin)
	end
	if root then root.AssemblyLinearVelocity = fwd * power end
	CombatSounds.play(isMagma and "magma" or "cannon", origin) -- cannon report (fire or normal)

	local creator = Instance.new("ObjectValue")
	creator.Name = "creator"
	creator.Value = plr
	creator.Parent = root or ball -- on the part, so ShipCombat's watcher sees it
	ball.Parent = workspace
	task.delay(7, function() if ball.Parent then ball:Destroy() end end)

	local flash = Instance.new("Explosion")
	flash.Position = origin
	flash.BlastPressure = 0
	flash.BlastRadius = 3
	flash.Parent = workspace
end

ctrlEvent.OnServerEvent:Connect(function(plr, action, a, b, c)
	local cannon = controlling[plr]
	if not cannon then return end
	local rec = recOf[cannon]
	if not rec then return end
	if action == "aim" then
		if typeof(a) == "number" and typeof(b) == "number" then aim(rec, a, b) end
	elseif action == "fire" then
		-- ("fire", power, yaw, pitch) — lock in the final aim, then fire from the muzzle
		if typeof(b) == "number" and typeof(c) == "number" then aim(rec, b, c) end
		local power = (typeof(a) == "number") and math.clamp(a, MIN_POWER, MAX_POWER) or MIN_POWER
		fireCannon(rec, plr, power)
		exitAim(plr)
	elseif action == "cancel" then
		exitAim(plr)
	end
end)

-- ── take over placed cannons ──
local function takeover(cannon)
	if cannon:GetAttribute("_Controlled") then return end
	if not ensureRec(cannon) then return end -- attach the motor BEFORE disabling old scripts
	cannon:SetAttribute("_Controlled", true)
	local rec = recOf[cannon]

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CannonControlPrompt"
	prompt.ActionText = PROMPT_TEXT
	prompt.ObjectText = "Пушка"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = rec.main
	prompt.Triggered:Connect(function(plr) enterAim(plr, cannon) end)
	rec.prompt = prompt

	-- kill the old load/fire script + its prompt + its leftover "Not loaded" UI
	local function purge()
		for _, d in ipairs(cannon:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") then
				d.Disabled = true
			elseif d:IsA("ProximityPrompt") and d ~= prompt then
				d:Destroy()
			elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
				d:Destroy()
			end
		end
	end
	purge()
	cannon.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") and d ~= prompt then
			task.defer(function() if d.Parent then d:Destroy() end end)
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d.Disabled = true
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			task.defer(function() if d.Parent then d:Destroy() end end)
		end
	end)

	print("[CannonControl] took over: " .. cannon:GetFullName())
end

local function underEnemyShip(inst)
	local m = inst.Parent
	while m and m ~= workspace do
		if m:IsA("Model") and m.Name:sub(1, #SHIP_PREFIX) == SHIP_PREFIX then return true end
		m = m.Parent
	end
	return false
end
local function scan(inst)
	if (inst:IsA("BasePart") or inst:IsA("Model")) and cannonKind(inst) ~= nil and not underEnemyShip(inst) then
		takeover(inst)
	end
end
print("[CannonControl] loaded — scanning for player cannons")
for _, d in ipairs(workspace:GetDescendants()) do scan(d) end
workspace.DescendantAdded:Connect(scan)

Players.PlayerRemoving:Connect(exitAim)
