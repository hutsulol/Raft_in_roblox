-----------------
--| Constants |--
-----------------

local BULLET_PART_SIZE = Vector3.new(0.8, 0.8, 0.8)

-----------------
--| Variables |--
-----------------

local PlayersService = game:GetService('Players')

local MyPlayer

local Tool = script.Parent
local ToolHandle = Tool:WaitForChild('Handle')

local ToolValues = Tool:WaitForChild("Values")

local ToolName = ToolValues:WaitForChild("GunOriginalName")
local ToolDamage = ToolValues:WaitForChild("Damage")
local ToolMaxBullets = ToolValues:WaitForChild("MaxBullets")
local ToolBullets = ToolValues:WaitForChild("Bullets")
local Reloading = ToolValues:WaitForChild("Reloading")

local ShotEffect = ToolHandle:WaitForChild('ShotEffect')
local Attachment0 = ToolHandle:WaitForChild('Attachment0')
local BulletScript = script:WaitForChild('BulletScript')
local LightShotEffect = ToolHandle:WaitForChild("LightShotEffect")

local MouseLoc = Tool:WaitForChild("MouseLoc",10)

local ShootSound = ToolHandle:WaitForChild('ShootSound')
local ReloadSound = ToolHandle:WaitForChild('ReloadSound')

local Bullet = Instance.new('Part') do
	Bullet.Size = BULLET_PART_SIZE
	Bullet.Name = 'Bullet'
	Bullet.Anchored = true
	Bullet.CanCollide = false
	Bullet.Transparency = 1
	
	local creatorTag = Instance.new('ObjectValue', Bullet)
	creatorTag.Value = MyPlayer
	creatorTag.Name = 'creator'
	local iconTag = Instance.new('StringValue', creatorTag)
	iconTag.Value = Tool.TextureId
	iconTag.Name = 'icon'
	
	local BulletScriptClone = BulletScript:Clone()
	BulletScriptClone.Parent = Bullet
	BulletScriptClone.Enabled = true
	
	local NearbyBulletSound = Instance.new('Sound', Bullet)
	NearbyBulletSound.Name = 'NearbyBulletSound'
	NearbyBulletSound.SoundId = 'rbxassetid://4612378521'
	NearbyBulletSound.RollOffMaxDistance = 180
	NearbyBulletSound.RollOffMinDistance = 60
	NearbyBulletSound.Volume = 2.5
	
	local LightEffect = Instance.new('PointLight', Bullet)
	LightEffect.Name = "LightEffect"
	LightEffect.Shadows = true
	LightEffect.Brightness = 2.5
	LightEffect.Range = 2.5
	LightEffect.Color = Color3.new(1, 0.803922, 0.686275)
	LightEffect.Enabled = true
	
	local BulletDamage = ToolDamage:Clone()
	ToolDamage:Clone()
	BulletDamage.Parent = Bullet
	
	local Attachment1 = Instance.new('Attachment', Bullet)
	Attachment1.Name = 'Attachment1'
end

-----------------
--| Functions |--
-----------------

local function OnActivated()
	local myModel = MyPlayer.Character
	
	local myHumanoid = myModel:FindFirstChildOfClass("Humanoid")
	
	if Tool.Enabled and myModel and myHumanoid and myHumanoid.Health > 0 and ToolBullets.Value > 0 and Reloading.Value == false then
		
		Tool.Enabled = false
		ToolBullets.Value = ToolBullets.Value - 1
		
		local Pos = MouseLoc:InvokeClient(MyPlayer)
		
		local BulletClone = Bullet:Clone()
		Bullet:Clone()
		BulletClone.Parent = workspace
		BulletClone.Position = Pos
		
		local Attachment1Clone = BulletClone:FindFirstChild('Attachment1')
		ShotEffect.Attachment1 = Attachment1Clone
		LightShotEffect.Enabled = true
		
		ShootSound:Play()
		wait(0.25)
		ShotEffect.Attachment1 = nil
		LightShotEffect.Enabled = false
		
		wait(0.5)
		
		Tool.Enabled = true
		
	elseif ToolBullets.Value == 0 and Reloading.Value == false then
		
		Tool.Enabled = false
		Reloading.Value = true
		
		ReloadSound:Play()
		
		while ReloadSound.IsPlaying do
			wait()
		end
		
		ToolBullets.Value = ToolMaxBullets.Value
		
		Tool.Enabled = true
		Reloading.Value = false
		
	end
end

function OnEquipped()
	MyPlayer = PlayersService:GetPlayerFromCharacter(Tool.Parent)
end

--------------------
--| Script Logic |--
--------------------

Tool.Equipped:Connect(OnEquipped)
Tool.Activated:Connect(OnActivated)

wait(ToolName)
while true do
	wait()
	local GunNewName = ToolName.Value .. ' ' ..  '(' .. ToolBullets.Value .. ')'
	Tool.Name = GunNewName
end
