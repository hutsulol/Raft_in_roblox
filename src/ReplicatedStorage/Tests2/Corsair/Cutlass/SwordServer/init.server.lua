--!strict

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RNG = Random.new()

local Sword = script.Parent
local Handle = Sword.Handle

local HandleThrowClone = Handle:Clone() do
	HandleThrowClone.Name = "ThrownSword"
	HandleThrowClone.ElectricityLight:Destroy()
	HandleThrowClone.SwordSlash:Destroy()
	HandleThrowClone.Lightning:Destroy()
	HandleThrowClone.Unsheath:Destroy()
	
	HandleThrowClone.CanCollide = true
	HandleThrowClone.Massless = false
	HandleThrowClone.Massless = true
	
	local Attachment = Instance.new("Attachment", HandleThrowClone)
	Attachment.Name = "Constraints"
	
	local AngularVel = Instance.new("AngularVelocity", Attachment)
	AngularVel.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	AngularVel.AngularVelocity = Vector3.new(0, 0, 16)
	AngularVel.Attachment0 = Attachment
	AngularVel.MaxTorque = 100
	
	local LinearVel = Instance.new("LinearVelocity", Attachment)
	LinearVel.Attachment0 = Attachment
end

local UserPlayer: Player? = nil
local UserCharacter: Model? = nil
local UserHumanoid: Humanoid? = nil

local Electricity = false
local JetBoots = false
local Equipped = false

local SwordTexture = Handle.TextureID

local Commands = {
	ThrowSword = 1,
	SetElectric = 2,
	JetBoots = 3,
}

local Grips = {
	Default = CFrame.new(-0.899999976, 1.29999995, 0, -5.73245273e-08, 0.669130623, -0.74314481, 1.12211744e-07, -0.74314481, -0.669130623, -1, -1.21747178e-07, -3.24838929e-08),
	Lunging = CFrame.new(-0.899999976, 1.29999995, 0, -5.73245273e-08, -0.743144751, -0.669130564, 1.12211744e-07, -0.669130564, 0.743144751, -1, -3.24838929e-08, 1.21747178e-07),
}

local Sounds = {
	Lightning = Handle:WaitForChild("Lightning"),
	Unsheath = Handle:WaitForChild("Unsheath"),
	Slash = Handle:WaitForChild("SwordSlash"),
	Lunge = Handle:WaitForChild("SwordLunge"),
}

local DamageValues = {
	BaseDamage = 5,
	SlashDamage = 10,
	LungeDamage = 30
}

local ThrownSwordDamage = DamageValues.BaseDamage
local ThrowCooldown = 8.0

local ElectricityActiveTime = 17.0
local ElectricityCooldown = 10.4
local ElectricDamageMul = 1.5

local JetBootsCooldown = 10
local JetBootsPower = 80
local JetBootsTime = 0.75

local Damage = DamageValues.BaseDamage
local LastAttack = 0

local AllActionsDebounce = 0
local ElectricityDebounce = 0
local JetBootsDebounce = 0
local ThrowDebounce = 0

-- POop
local ThunderHumanoidUser: Humanoid? = nil

-------------------------------------------------------------------------------------------------------------------

local function onHumanoidKilled(target: Humanoid)
	local character = target.Parent :: Model
	if Electricity and character then
		Sounds.Lightning:Play()
		
		if not character:FindFirstChild("ThunderDeathEffect") then
			local deathEffect = script.ThunderDeathEffect:Clone()
			deathEffect.Parent = target.Parent
			deathEffect.Enabled = true
		end
	end
end

local function tagHumanoid(target: Humanoid)
	if not (UserPlayer) then
		return
	end

	local previous = target:FindFirstChild("creator")
	if previous then
		previous:Destroy()
	end

	local new = Instance.new("ObjectValue")
	new.Value = UserPlayer or UserCharacter
	new.Name = "creator"

	Debris:AddItem(new, 5.0)
	new.Parent = target
end

local function isTeammate(other: Player): boolean
	if (not UserPlayer) or (other.Neutral) then
		return false
	end

	return UserPlayer.Team == other.Team
end

local function checkIfAlive(): boolean
	if UserHumanoid then
		return UserHumanoid.Health > 0.0
	end

	return false
end

local function doToolAnim(value: "None" | "Slash" | "Lunge")
	if not (UserPlayer and UserHumanoid) then
		return
	end

	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = value

	anim.Parent = Sword
	Debris:AddItem(anim, 0.25)
end

local function hitPart(hit: BasePart, source: BasePart)
	local projectile = source.Name == "ThrownSword"
	
	if
		not (UserCharacter and UserHumanoid)
		or not (hit and hit.Parent)
		or (not checkIfAlive())
		or (not Equipped and not projectile)
	then
		return
	end

	local rightArm = UserCharacter:FindFirstChild("Right Arm") or UserCharacter:FindFirstChild("RightHand")
	local rightGrip = rightArm and rightArm:FindFirstChild("RightGrip")

	local character = hit.Parent :: Model
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	local player = Players:GetPlayerFromCharacter(character)

	if
		(not humanoid or humanoid.Health <= 0)
		or (not(rightArm and rightGrip) and not projectile)
		or (character == UserCharacter)
		or (player and isTeammate(player))
	then
		return
	end

	local damageDealing = Damage
	if projectile then
		damageDealing = DamageValues.SlashDamage
	end
	
	damageDealing *= if Electricity
		then ElectricDamageMul
		else 1.0

	tagHumanoid(humanoid)
	humanoid:TakeDamage(damageDealing)
	
	if humanoid.Health <= 0.0 then
		onHumanoidKilled(humanoid)
	end
end

-------------------------------------------------------------------------------------------------------------------

local function attack()
	Damage = DamageValues.SlashDamage
	doToolAnim("Slash")
	Sounds.Slash:Play()
end

local function lunge()
	Damage = DamageValues.LungeDamage
	doToolAnim("Lunge")
	Sounds.Lunge:Play()

	if (UserHumanoid and UserHumanoid.RootPart) and checkIfAlive() then
		local Force = Instance.new("BodyVelocity")
		Force.MaxForce = Vector3.new(0, 4000, 0)
		Force.Velocity = Vector3.new(0, 10, 0)
		Force.Name = "SwordForce"

		Force.Parent = UserHumanoid.RootPart
		Debris:AddItem(Force, 0.4)
	end

	task.wait(0.2)
	Sword.Grip = Grips.Lunging
	task.wait(0.6)
	Sword.Grip = Grips.Default

	Damage = DamageValues.SlashDamage
end

local function throwSword()
	if not Sword:GetAttribute("SwordThrowEnabled") then
		return
	end
	
	if
		(not Sword.Enabled)
		or (Electricity or JetBoots)
		or (AllActionsDebounce > tick())
		or (ThrowDebounce > tick())
	then
		return
	end
	
	if not (UserHumanoid and UserHumanoid.RootPart) then
		return
	end

	local rootPart = UserHumanoid.RootPart
	local rootCFrame = rootPart.CFrame
	local rootLook = rootCFrame.LookVector

	local new = HandleThrowClone:Clone()
	local linearVel = new.Constraints.LinearVelocity :: LinearVelocity
	linearVel.VectorVelocity = rootLook * 31
	new.SwordLunge:Play()

	new.CFrame = CFrame.lookAt(rootCFrame.Position, rootCFrame.Position + rootLook) * CFrame.Angles(math.pi / 2, 0, 0)
	new.CFrame += rootLook * 6
	new.Parent = workspace
	new.Archivable = false
	new.Touched:Connect(function(hit: BasePart)
		hitPart(hit, new)
	end)

	Debris:AddItem(new, 5.0)
	if UserPlayer then
		new:SetNetworkOwner(UserPlayer)
	end
	
	doToolAnim("Lunge")
	ThrowDebounce = tick() + ThrowCooldown
	AllActionsDebounce = tick() + 1
end

local function setElectric()
	if not Sword:GetAttribute("ElectricityEnabled") then
		return
	end
	
	if
		(Electricity or JetBoots)
		or (ElectricityDebounce > tick())
		or (AllActionsDebounce > tick())
	then
		return
	end

	Electricity = true
	Handle.ElectricityLight.Enabled = true
	Handle.TextureID = ""
	ThunderHumanoidUser = UserHumanoid
	
	if ThunderHumanoidUser then
		ThunderHumanoidUser.WalkSpeed += 8
	end

	local t = ElectricityActiveTime
	while Equipped and (t > 0) do
		t -= task.wait()
	end
	
	if ThunderHumanoidUser then
		ThunderHumanoidUser.WalkSpeed -= 8
	end

	AllActionsDebounce = tick() + 1
	ElectricityDebounce = tick() + ElectricityCooldown
	Handle.ElectricityLight.Enabled = false
	Handle.TextureID = SwordTexture
	Electricity = false
end

local function swingSword()
	Sword.Enabled = false
	local Tick = tick()

	if (Tick - LastAttack < 0.2) then
		lunge()
	else
		attack()
	end

	LastAttack = Tick
	Damage = DamageValues.BaseDamage
	Sword.Enabled = true
end

local function jetBoots()
	if not Sword:GetAttribute("JetBootsEnabled") then
		return
	end
	
	if
		(Electricity)
		or (JetBootsDebounce > tick())
		or (AllActionsDebounce > tick())
		or not(UserHumanoid and UserHumanoid.RootPart)
	then
		return
	end
	
	local rootPart = UserHumanoid.RootPart
	
	local propulsion = Instance.new("BodyVelocity")
	propulsion.MaxForce = Vector3.new(0, 4000, 0)
	propulsion.Velocity = Vector3.yAxis * JetBootsPower
	Debris:AddItem(propulsion, JetBootsTime)
	propulsion.Name = "JetBootsVelocity"
	
	task.spawn(function()
		for i = 1, 16 do
			local exhaust = Instance.new("Part")
			exhaust.Position = rootPart.Position - Vector3.yAxis * (rootPart.Size.Y * 3)
			exhaust.AssemblyAngularVelocity = RNG:NextUnitVector() * RNG:NextNumber(5, 20)
			exhaust.AssemblyLinearVelocity = -Vector3.yAxis * 20
			exhaust.BrickColor = Handle.BrickColor
			exhaust.Shape = Enum.PartType.Cylinder
			exhaust.Name = "JetBootsExhaust"
			exhaust.Size = Vector3.one
			exhaust.Archivable = false
			exhaust.CanQuery = false
			
			local tag = Instance.new("ObjectValue")
			tag.Value = UserPlayer or UserCharacter
			tag.Name = "creator"
			tag.Parent = exhaust
			
			local exhaustScript = script.ExhaustScript:Clone()
			exhaustScript.Parent = exhaust
			exhaustScript.Enabled = true
			
			exhaust.Parent = workspace.Terrain
			task.wait(1/24)
		end
	end)
	
	JetBootsDebounce = tick() + JetBootsCooldown
	AllActionsDebounce = tick() + 1
	propulsion.Parent = rootPart
end

local function doCommand(cmd: number)
	if not(Equipped and Sword.Enabled and checkIfAlive()) then
		return
	end
	
	if cmd == Commands.ThrowSword then
		throwSword()
	elseif cmd == Commands.SetElectric then
		setElectric()
	elseif cmd == Commands.JetBoots then
		jetBoots()
	end
end

-------------------------------------------------------------------------------------------------------------------

local function onPlayerCommandReceived(requester: Player, cmd: number)
	if (requester ~= UserPlayer) then
		return
	end
	
	doCommand(cmd)
end

local function onEquipped()
	UserCharacter = Sword.Parent
	UserHumanoid = UserCharacter and UserCharacter:FindFirstChildWhichIsA("Humanoid")
	UserPlayer = UserCharacter and Players:GetPlayerFromCharacter(UserCharacter)

	if not checkIfAlive() then
		return
	end

	Equipped = true
	AllActionsDebounce = tick() + 1
	Sounds.Unsheath:Play()
end

local function onUnequipped()
	Sword.Grip = Grips.Default
	Equipped = false
end

script.ClientCommand.OnServerEvent:Connect(onPlayerCommandReceived)
script.Command.Event:Connect(doCommand)

Sword.Unequipped:Connect(onUnequipped)
Sword.Activated:Connect(swingSword)
Sword.Equipped:Connect(onEquipped)

Handle.Touched:Connect(function(hit: BasePart)
	hitPart(hit, Handle)
end)