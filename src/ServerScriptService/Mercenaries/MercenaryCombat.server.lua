-- MercenaryCombat.server.lua
-- Drives combat for summoned mercenaries. The Pirate_2 template that
-- mercenaries are cloned from doesn't ship with a ZombieScript, so we
-- can't reuse the legacy AI loop the hostile pirates run. Instead this
-- polls every "SpawnedMercenary"-tagged model, finds the closest
-- "HostilePirate"-tagged enemy, and has the mercenary walk up to it and
-- attack until the enemy is dead.
--
-- The hostile pirates target mercenaries through the role-aware
-- SearchForTarget in Enemy_Pirate/Zombie.script, so combat is mutual.
--
-- Note: this issues Humanoid:MoveTo on every tick during combat, which
-- overrides the fishing-walk loop in MercenaryMovement when an enemy is
-- in range. The bobber will be left floating until combat ends — that's
-- intentional for now (combat > fishing).

local CollectionService = game:GetService("CollectionService")

local DETECTION_RANGE = 80   -- studs; how far mercenaries will engage
local ATTACK_RANGE    = 5.5  -- studs; close enough to swing
local ATTACK_DAMAGE   = 8
local ATTACK_COOLDOWN = 1.2  -- seconds between swings
local SCAN_INTERVAL   = 0.15 -- seconds between combat ticks

local lastAttack = {} -- [mercenaryModel] = tick()
local prepared  = {} -- [mercenaryModel] = true, once humanoid forced walkable
local debugged  = {} -- [mercenaryModel] = true, once enemy engage print fired

local DEBUG = true

local function prepareMercenary(merc, hum)
	if prepared[merc] then return end
	prepared[merc] = true
	-- The Pirate_2 template doesn't ship with a ZombieScript, so nothing
	-- configures the Humanoid on spawn. If the template happens to have
	-- WalkSpeed = 0 or a disabled Running state, MoveTo silently does
	-- nothing. Force a sane movement config so combat can actually run.
	if hum.WalkSpeed <= 0 then
		hum.WalkSpeed = 12
	end
	hum.PlatformStand = false
	hum.Sit = false
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Running, true)
		hum:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, true)
		hum:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
		hum:ChangeState(Enum.HumanoidStateType.Running)
	end)
	if DEBUG then
		print(string.format(
			"[MercenaryCombat] prepared %s (WalkSpeed=%.1f, Health=%.1f)",
			merc.Name, hum.WalkSpeed, hum.Health
		))
	end
end

local function getTorso(model)
	-- Mercenaries and hostile pirates are both R6 clones, so Torso is
	-- the reliable reference. Fall back for safety.
	return model:FindFirstChild("Torso")
		or model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChild("UpperTorso")
end

local function getHumanoid(model)
	return model:FindFirstChildOfClass("Humanoid")
end

local function isAlive(model)
	local hum = getHumanoid(model)
	return hum ~= nil and hum.Health > 0, hum
end

local function findNearestHostile(merc, myPos)
	local closest, closestDist = nil, nil
	for _, pirate in CollectionService:GetTagged("HostilePirate") do
		if pirate ~= merc and pirate:IsDescendantOf(workspace) then
			local alive = isAlive(pirate)
			if alive then
				local torso = getTorso(pirate)
				if torso then
					local d = (torso.Position - myPos).Magnitude
					if d < DETECTION_RANGE and (closestDist == nil or d < closestDist) then
						closest, closestDist = pirate, d
					end
				end
			end
		end
	end
	return closest, closestDist
end

local function swingAt(merc, targetHumanoid)
	-- Direct damage application (same approach the baked ZombieScript
	-- uses for its own Attack). Also kicks the equipped tool's Activated
	-- event so the sword slash animation / sound plays alongside.
	targetHumanoid:TakeDamage(ATTACK_DAMAGE)

	local tool = merc:FindFirstChildWhichIsA("Tool")
	if tool then
		pcall(function()
			tool:Activate()
		end)
	end
end

local function tickMercenary(merc)
	if not merc:IsDescendantOf(workspace) then return end

	-- If the mercenary ships with its own embedded Combat script (the
	-- Pirate_2 template does, after src/Pirate_2/Combat.script is synced),
	-- let that script drive the rig instead — otherwise we'd swing twice
	-- per cooldown and deal double damage.
	if merc:FindFirstChild("Combat") then return end

	local alive, hum = isAlive(merc)
	if not alive or not hum then return end

	local myTorso = getTorso(merc)
	if not myTorso then return end

	prepareMercenary(merc, hum)

	local target, dist = findNearestHostile(merc, myTorso.Position)
	if not target then return end

	if DEBUG and not debugged[merc] then
		debugged[merc] = true
		print(string.format(
			"[MercenaryCombat] %s engaging %s at %.1f studs",
			merc.Name, target.Name, dist
		))
	end

	local targetTorso = getTorso(target)
	local targetHum = getHumanoid(target)
	if not targetTorso or not targetHum then return end

	if dist > ATTACK_RANGE then
		-- Chase
		hum:MoveTo(targetTorso.Position)
	else
		-- In range: stop moving and swing on cooldown
		hum:MoveTo(myTorso.Position)
		local now = tick()
		if now - (lastAttack[merc] or 0) >= ATTACK_COOLDOWN then
			lastAttack[merc] = now
			swingAt(merc, targetHum)
		end
	end
end

task.spawn(function()
	while true do
		for _, merc in CollectionService:GetTagged("SpawnedMercenary") do
			tickMercenary(merc)
		end
		task.wait(SCAN_INTERVAL)
	end
end)

CollectionService:GetInstanceRemovedSignal("SpawnedMercenary"):Connect(function(merc)
	lastAttack[merc] = nil
	prepared[merc]   = nil
	debugged[merc]   = nil
end)

if DEBUG then
	CollectionService:GetInstanceAddedSignal("SpawnedMercenary"):Connect(function(merc)
		print("[MercenaryCombat] saw new mercenary:", merc:GetFullName())
	end)
	-- Dump current tag snapshot on startup so we can confirm the driver
	-- is running and that tags are actually present.
	print(string.format(
		"[MercenaryCombat] online — mercenaries=%d, hostile pirates=%d",
		#CollectionService:GetTagged("SpawnedMercenary"),
		#CollectionService:GetTagged("HostilePirate")
	))
end
