--//Pirate_Gun — BackendScript (server)
--//Based on Mineloxer's gun kit, but the hitscan ray is replaced by a physical
--//cannon charge. We spawn a "Bullet_Cannon" from the Handle's pivot; ShipCombat
--//(ServerScriptService) already watches that part and applies ship zone-damage +
--//water splash for anything named Bullet_Cannon carrying a "creator" plus the
--//DmgMult / SplashRadius attributes. So no damage code lives here — just spawning.

--//── tunables (cannon charge) ──
local DMG_MULT      = 1 / 3 -- 3× weaker than the mounted Cannon (ShipCombat scales by this)
local SPLASH_RADIUS = 6     -- studs of area damage on the water (also the splash explosion size)
local LAUNCH_SPEED  = 180   -- launch power; the charge then arcs under gravity
local MUZZLE_CLEAR  = 2     -- studs ahead of the pivot to spawn (clear of the gun)
local DESPAWN       = 7     -- seconds before an un-hit charge is removed
--//aim tilt
local MAX_PITCH     = math.rad(70) -- max up/down arm rotation
local TILT_SIGN     = -1           -- flip sign if the gun tilts the wrong way
--//отдача (СИЛЬНАЯ — это ручная пушка): на выстреле ствол дёргается назад + вверх, затем
--//плавно возвращается. У АК-47 (WeaponFeel.client) отдача заметно слабее.
local RECOIL_BACK   = 0.9          -- studs назад (положительное = назад к игроку)
local RECOIL_UP     = math.rad(13) -- вверх
local RECOIL_DECAY  = 9            -- скорость возврата (1/сек; больше = быстрее)

--//Services\\--
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")
local RunService        = game:GetService("RunService")

local UpgradeConfig = require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig"))
local MuzzleFX      = require(ReplicatedStorage:WaitForChild("MuzzleFX")) -- дульный залп (общий)

--//Variables\\--
local player
local tool = script.Parent.Parent
local handle = tool:WaitForChild("Handle")
local lastShot = tick()
local equipped = false
local reloading = false
local kickRecoil -- forward-declared (аим-секция ниже); shoot() дёргает отдачу

--//Folders\\--
local configs = tool:WaitForChild("Configs")
local remotes = tool:WaitForChild("Remotes")

--//Configs\\--
local ammo = configs:WaitForChild("Ammo")
local reserveAmmo = configs:WaitForChild("ReserveAmmo")
local magSize = configs:WaitForChild("MagSize")
local fireRate = configs:WaitForChild("FireRate")
local reloadTime = configs:WaitForChild("ReloadTime")

--//Remotes\\--
local canShootRemote = remotes:WaitForChild("CanShoot")
local canReloadRemote = remotes:WaitForChild("CanReload")
local reloadRemote = remotes:WaitForChild("Reload")
local shootRemote = remotes:WaitForChild("Shoot")

--//created at runtime so you don't have to add it in Studio; the client waits for it
local aimRemote = remotes:FindFirstChild("Aim")
if not aimRemote then
	aimRemote = Instance.new("RemoteEvent")
	aimRemote.Name = "Aim"
	aimRemote.Parent = remotes
end

--//Sounds\\--
local emptySound = handle:WaitForChild("EmptySound")
local reloadSound = handle:WaitForChild("ReloadSound")
local shootSound = handle:WaitForChild("ShootSound")

--//── hand-cannon feel (overrides the kit's Studio Config values + AK-47 fire sound) ──
--// 3 rounds in the mag, 9 in reserve, ~1 s between shots, and a cannon-charge "boom".
local SHOOT_SOUND_ID = "rbxassetid://3802269741" -- cannon-charge blast (Creator Store; swap if you like)
magSize.Value     = 3
ammo.Value        = 3   -- start full
reserveAmmo.Value = 9
fireRate.Value    = 60  -- canShoot waits 60/FireRate s between shots → 60/60 = 1 s
shootSound.SoundId = SHOOT_SOUND_ID

--//Functions\\--
local function canReload()
	--//Return true if gun can be reloaded, else return false
	if ammo.Value < magSize.Value then --//Not full ammo
		if reserveAmmo.Value > 0 then --//Have any ammo to reload with
			if not reloading then --//Not currently reloading
				if equipped then --//Gun is equipped in the first place
					return true
				end
			end
		end
	end
	return false
end

local function reload()
	if not canReload() then return end

	reloading = true
	reloadSound:Play()

	--//Handle ammo
	local needed = magSize.Value - ammo.Value
	reserveAmmo.Value = reserveAmmo.Value - needed
	ammo.Value = magSize.Value

	--//Ensure reserveAmmo doesn't go negative
	if reserveAmmo.Value < 0 then
		ammo.Value = ammo.Value + reserveAmmo.Value
		reserveAmmo.Value = 0
	end

	task.wait(reloadTime.Value)
	reloading = false
end

local function canShoot(_plr, playSound)
	--//Return true if gun can be shot, else return false
	-- прокачка темпа (лобби, меню «Прокачка оружия»): +8% скорострельности за уровень
	local rofMult = UpgradeConfig.rofMultFor(
		(player and player:GetAttribute(UpgradeConfig.ATTR_PREFIX .. "Pirate_Gun")) or 0)
	if math.abs(lastShot - tick()) > (60 / (fireRate.Value * rofMult)) then --//Fire rate / debounce
		if not reloading then
			if equipped then
				if ammo.Value > 0 then
					return true
				else
					if playSound then
						emptySound:Play()
					end
				end
			end
		end
	end
	return false
end

--//дульный залп (вспышка+искры+дым) вынесен в общий модуль ReplicatedStorage.MuzzleFX

--//Spawn the cannon charge (adapted from CannonControl.fireCannon). The part is
--//named "Bullet_Cannon" + tagged with a "creator" so ShipCombat damages ships and
--//bursts on the water; DmgMult / SplashRadius tell it how hard.
local function fireCharge(dir)
	local origin = handle:GetPivot().Position + dir * MUZZLE_CLEAR
	MuzzleFX.burst(origin, dir) -- вспышка + искры + дым на дуле

	local template = ReplicatedStorage:FindFirstChild("Bullet_Cannon")
	local ball
	if template then
		ball = template:Clone()
	else
		ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(1.8, 1.8, 1.8)
		ball.Color = Color3.fromRGB(25, 25, 28)
		ball.Material = Enum.Material.Slate
	end
	ball.Name = "Bullet_Cannon" -- ShipCombat detects this name

	local root = (ball:IsA("BasePart") and ball) or ball.PrimaryPart or ball:FindFirstChildWhichIsA("BasePart")
	for _, d in ipairs(ball:IsA("BasePart") and { ball } or ball:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			if d ~= root then -- weld a multi-part template so it flies as one
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = d
				w.Parent = d
			end
		end
	end

	if root then
		-- прокачка ручной пушки (лобби, меню «Прокачка оружия») + бонус ВЫЖИВШЕГО (2 ур.)
		local upgStars = (player and player:GetAttribute(UpgradeConfig.ATTR_PREFIX .. "Pirate_Gun")) or 0
		root:SetAttribute("DmgMult", DMG_MULT * UpgradeConfig.multFor(upgStars) * UpgradeConfig.survivorWeaponMult(player)) -- ShipCombat scales ship/impact damage
		root:SetAttribute("SplashRadius", SPLASH_RADIUS) -- ...and bursts on the water surface
	end

	if ball:IsA("Model") then
		if not ball.PrimaryPart and root then ball.PrimaryPart = root end
		ball:PivotTo(CFrame.new(origin))
	else
		ball.CFrame = CFrame.new(origin)
	end
	if root then root.AssemblyLinearVelocity = dir * LAUNCH_SPEED end

	--//faint smoke trail so the charge is easy to track as it arcs
	if root then
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailA0"
		a0.Position = Vector3.new(0, 0.35, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailA1"
		a1.Position = Vector3.new(0, -0.35, 0)
		a1.Parent = root
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.35
		trail.Color = ColorSequence.new(Color3.fromRGB(220, 220, 225))
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		trail.Parent = root
	end

	local creator = Instance.new("ObjectValue")
	creator.Name = "creator"
	creator.Value = player
	creator.Parent = root or ball -- on the part, so ShipCombat's watcher sees it

	ball.Parent = workspace
	Debris:AddItem(ball, DESPAWN)
end

--//Fired by the client with the world-space aim direction (unit vector).
local function shoot(_plr, dir)
	if not canShoot(player, true) then return end
	if typeof(dir) ~= "Vector3" then return end
	if dir.Magnitude < 0.001 then return end
	dir = dir.Unit

	--//Handling
	lastShot = tick()
	ammo.Value = ammo.Value - 1
	shootSound:Play()
	fireCharge(dir)
	if kickRecoil then kickRecoil() end -- визуальная отдача
end

--//── aim tilt ──
--//The character RIG joints are read-only here: the raft pins the character's network
--//ownership, so neither client nor server may write a Motor6D.C0 (both throw "C0 is
--//read only"). So instead of swinging the arm, we pitch the GUN itself via the Tool's
--//Grip — a plain Tool property, server-writable + replicated, so the barrel follows
--//the camera for everyone.
local baseGrip = tool.Grip
local currentPitch = 0 -- последний угол прицела
local recoil = 0       -- 0..1, затухает после выстрела
local recoilConn

--//Grip = прицел (наклон ствола) + отдача (сдвиг назад/вверх). Пишется и при прицеле,
--//и покадрово во время затухания отдачи.
local function applyGrip()
	tool.Grip = baseGrip
		* CFrame.Angles(currentPitch + RECOIL_UP * recoil, 0, 0)
		* CFrame.new(0, 0, -RECOIL_BACK * recoil) -- -Z = назад (к игроку), это отдача
end

--//Client sends camera pitch → tilt the gun's grip so the barrel points where you aim.
local function onAim(plr, pitch)
	if plr ~= player or not equipped then return end
	if typeof(pitch) ~= "number" then return end
	--//if the gun rolls/yaws instead of pitching, move `pitch` to a different axis
	currentPitch = math.clamp(pitch, -MAX_PITCH, MAX_PITCH) * TILT_SIGN
	applyGrip()
end

--//толчок отдачи на выстреле + плавное затухание (Grip пишем покадрово ТОЛЬКО пока
--//отдача есть, чтобы не гнать репликацию грипа каждый кадр без нужды)
kickRecoil = function()
	recoil = 1
	if recoilConn then return end
	recoilConn = RunService.Heartbeat:Connect(function(dt)
		recoil = math.max(0, recoil - dt * RECOIL_DECAY)
		applyGrip()
		if recoil <= 0 and recoilConn then
			recoilConn:Disconnect(); recoilConn = nil
		end
	end)
end

local function resetAim()
	currentPitch = 0
	recoil = 0
	if recoilConn then recoilConn:Disconnect(); recoilConn = nil end
	tool.Grip = baseGrip
end

local function equip()
	equipped = true
	player = Players:GetPlayerFromCharacter(tool.Parent)
end

local function dequip()
	equipped = false
	resetAim()
end

--//Event listeners\\--
tool.Equipped:Connect(equip)
tool.Unequipped:Connect(dequip)
shootRemote.OnServerEvent:Connect(shoot)
reloadRemote.OnServerEvent:Connect(reload)
aimRemote.OnServerEvent:Connect(onAim)
canShootRemote.OnServerInvoke = canShoot
canReloadRemote.OnServerInvoke = canReload
