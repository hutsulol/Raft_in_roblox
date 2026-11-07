--------------------- TEMPLATE BLADE WEAPON ---------------------------
-- Waits for the child of the specified parent
local function WaitForChild(parent, childName)
	while not parent:FindFirstChild(childName) do parent.ChildAdded:wait() end
	return parent[childName]
end


local SLASH_DAMAGE = 150
local DOWNSTAB_DAMAGE = 150
local THROWING_DAMAGE = 150
local HOLD_TO_THROW_TIME = 0.38


local Damage = 20

local MyHumanoid = nil
local MyTorso = nil
local MyCharacter = nil
local MyPlayer = nil

local Tool = script.Parent
local Handle = WaitForChild(Tool, 'Handle')

local BlowConnection
local Button1DownConnection
local Button1UpConnection

local PlayStabPunch
local PlayDownStab
local PlayThrow
local PlayThrowCharge

local IconUrl = Tool.TextureId  -- URL to the weapon knife icon asset

local DebrisService = Game:GetService('Debris')
local PlayersService = Game:GetService('Players')

local SlashSound

local HitPlayers = {}

local LeftButtonDownTime = nil

local Attacking = false

function Blow(hit)
	if Attacking then
		BlowDamage(hit, Damage)
	end
end

function BlowDamage(hit, damage)
	local humanoid = hit.Parent:FindFirstChild('Humanoid')
	local player = PlayersService:GetPlayerFromCharacter(hit.Parent)
	if humanoid == nil then
		Handle.WallHit:Play()
		wait(0.1)
		if game.Workspace.Handle == nil then
		else
			game.Workspace.Handle:Destroy()
		end
	else
		if humanoid.Health == 0 then
		else
			Handle.Ragdoll:clone().Parent = hit.Parent
			humanoid.Health = 0
			Handle.DeadPlayer:Play()
			Handle.DeadSound:Play()
		end
		wait(0.1)
		if game.Workspace.Handle == nil then
		else
			game.Workspace.Handle:Destroy()
		end
	end
	if humanoid ~= nil and MyHumanoid ~= nil and humanoid ~= MyHumanoid then
		if not MyPlayer.Neutral then 		
			-- Ignore teammates hit
			if player and player ~= MyPlayer and player.TeamColor == MyPlayer.TeamColor then
				return
			end
		end
		-- final check, make sure weapon is in-hand
		local rightArm = MyCharacter:FindFirstChild('Right Arm')
		if (rightArm ~= nil) then
			-- Check if the weld exists between the hand and the weapon
			local joint = rightArm:FindFirstChild('RightGrip')
			if (joint ~= nil and (joint.Part0 == Handle or joint.Part1 == Handle)) then
				-- Make sure you only hit them once per swing
				if player and not HitPlayers[player] then
					TagHumanoid(humanoid, MyPlayer)
					print("Sending " .. damage)
					humanoid:TakeDamage(damage)
					Handle.Splat.Volume = 1
					Handle.Splat:Play()
					HitPlayers[player] = true
				end
			end
		end
	end
end
function TagHumanoid(humanoid, player)
	-- Add more tags here to customize what tags are available.
	while humanoid:FindFirstChild('creator') do
		humanoid:FindFirstChild('creator'):Destroy()
	end 

	local creatorTag = Instance.new('ObjectValue')
	creatorTag.Value = player
	creatorTag.Name = 'creator'
	creatorTag.Parent = humanoid
	DebrisService:AddItem(creatorTag, 1.5)

	local weaponIconTag = Instance.new('StringValue')
	weaponIconTag.Value = IconUrl
	weaponIconTag.Name = 'icon'
	weaponIconTag.Parent = creatorTag
	DebrisService:AddItem(weaponIconTag, 1.5)
end

function HardAttack()
	Handle.Attack:Play()
	if PlayStabPunch then
		PlayStabPunch.Value = true
		wait(1.0)
		PlayStabPunch.Value = false
	end
end

function NormalAttack()
	Damage = DOWNSTAB_DAMAGE
	KnifeDown()
	Handle.Attack:Play()
	if PlayDownStab then
		PlayDownStab.Value = true
		wait(1.0)
		PlayDownStab.Value = false
	end
	KnifeUp()
end

function ThrowAttack()
	KnifeOut()
	if PlayThrow then
		PlayThrow.Value = true
		wait(0.3)
		if not Handle then return end
		local throwingHandle = Handle:Clone()
		DebrisService:AddItem(throwingHandle, 5)
		throwingHandle.Parent = Workspace
		Handle.Throw:Play()
		if MyCharacter and MyHumanoid then
			throwingHandle.Velocity = (MyHumanoid.TargetPoint - throwingHandle.CFrame.p).unit * 300
			-- set the orientation to the direction it is being thrown in
			throwingHandle.CFrame = CFrame.new(throwingHandle.CFrame.p, throwingHandle.CFrame.p + throwingHandle.Velocity) * CFrame.Angles(0, 0, math.rad(-90))
			local floatingForce = Instance.new('BodyForce', throwingHandle)
			floatingForce.force = Vector3.new(0, 196.2 * throwingHandle:GetMass() * 0.98, 0)
			local spin = Instance.new('BodyAngularVelocity', throwingHandle)
			spin.angularvelocity = throwingHandle.CFrame:vectorToWorldSpace(Vector3.new(0, -400, 0))
		end
		Handle.Transparency = 1
		-- Wait so that the knife has left the thrower's general area
		wait(0.08)
		if throwingHandle then
			local touchedConn = throwingHandle.Touched:connect(function(hit) print("hit throw") BlowDamage(hit, THROWING_DAMAGE) end)
		end
		-- must check if it still exists since we waited
		if throwingHandle then
			throwingHandle.CanCollide = true
		end
		wait(0.6)
		if Handle and PlayThrow then
			Handle.Transparency = 0
			PlayThrow.Value = false
		end
	end
	KnifeUp()
end

function KnifeUp()
	Tool.GripForward = Vector3.new(0, 0, -1)
	Tool.GripRight = Vector3.new(1, 0, 0)
	Tool.GripUp = Vector3.new(0, 1, 0)
end

function KnifeDown()
	Tool.GripForward = Vector3.new(0, 0, -1)
	Tool.GripRight = Vector3.new(1, 0, 0)
	Tool.GripUp = Vector3.new(0, -1, 0)
end

function KnifeOut()
	Tool.GripForward = Vector3.new(0, 0, -1)
	Tool.GripRight = Vector3.new(1, 0, 0)
	Tool.GripUp = Vector3.new(0, 1, 0)
end

Tool.Enabled = true

function OnLeftButtonDown()
	LeftButtonDownTime = time()
end

function OnLeftButtonUp()
	if not Tool.Enabled then return end
	-- Reset the list of hit players every time we start a new attack
	HitPlayers = {}
	if PlayThrowCharge then
		PlayThrowCharge.Value = false
	end
	if Tool.Enabled and MyHumanoid and MyHumanoid.Health > 0 then
		Tool.Enabled = false
		local currTime = time()
		if LeftButtonDownTime and currTime - LeftButtonDownTime > HOLD_TO_THROW_TIME and
			currTime - LeftButtonDownTime < 1.15 then
		else
			Attacking = true
			if math.random(1, 2) == 1 then
				HardAttack()
			else
				NormalAttack()
			end
			Attacking = false
		end
		Tool.Enabled = true
	end
end

function OnRightButtonDown()
	RightButtonDownTime = time()
    if PlayThrowCharge then
		PlayThrowCharge.Value = true
	end
end

function OnRightButtonUp()
		if not Tool.Enabled then return end
	-- Reset the list of hit players every time we start a new attack
	HitPlayers = {}
	if PlayThrowCharge then
		PlayThrowCharge.Value = false
	end
	if Tool.Enabled and MyHumanoid and MyHumanoid.Health > 0 then
		Tool.Enabled = false
		local currTime = time()
		if RightButtonDownTime and currTime - RightButtonDownTime > HOLD_TO_THROW_TIME and
			currTime - RightButtonDownTime < 1.15 then
			ThrowAttack()
		else
			Attacking = true
			if math.random(1, 2) == 1 then
			else
			end
			Attacking = false
		end
		Tool.Enabled = true
	end
end

function OnEquipped(mouse)
	PlayStabPunch = WaitForChild(Tool, 'PlayStabPunch')
	PlayDownStab = WaitForChild(Tool, 'PlayDownStab')
	PlayThrow = WaitForChild(Tool, 'PlayThrow')
	PlayThrowCharge = WaitForChild(Tool, 'PlayThrowCharge')
Handle.Equip:Play()
	BlowConnection = Handle.Touched:connect(Blow)
	MyCharacter = Tool.Parent
	MyTorso = MyCharacter:FindFirstChild('Torso')
	MyHumanoid = MyCharacter:FindFirstChild('Humanoid')
	MyPlayer = PlayersService.LocalPlayer
	if mouse then
		Button1DownConnection = mouse.Button1Down:connect(OnLeftButtonDown)
		Button1UpConnection = mouse.Button1Up:connect(OnLeftButtonUp)
		Button2DownConnection = mouse.Button2Down:connect(OnRightButtonDown)
		Button2UpConnection = mouse.Button2Up:connect(OnRightButtonUp)
	end
	KnifeUp()
end

function OnUnequipped()
	-- Unequip logic here
	if BlowConnection then
		BlowConnection:disconnect()
		BlowConnection = nil
	end
	if Button1DownConnection then
		Button1DownConnection:disconnect()
		Button1DownConnection = nil
	end
	if Button1UpConnection then
		Button1UpConnection:disconnect()
		Button1UpConnection = nil
	end
	if Button2UpConnection then
		Button2UpConnection:disconnect()
		Button2UpConnection = nil
	end
	if Button2DownConnection then
		Button2DownConnection:disconnect()
		Button2DownConnection = nil
	end
	MyHumanoid = nil
end


Tool.Equipped:connect(OnEquipped)
Tool.Unequipped:connect(OnUnequipped)
