local switch = script.Parent
local gunBarrelOne = script.Parent.Parent.GunBarrel.One

local debounce = false
local gunOne = true

local cannonBall = Instance.new("Part")
cannonBall.Size = Vector3.new(1,1,1)
cannonBall.BrickColor = BrickColor.new(1) -- medium blue
cannonBall.Shape = 0
cannonBall.BottomSurface = 0
cannonBall.TopSurface = 0
cannonBall.Name = "Cannon Shot"
cannonBall.Elasticity = .1
cannonBall.Reflectance = 0
cannonBall.Friction = 0

function fire(player)

	local sound = script.Parent:findFirstChild("GunSound")
	if sound == nil then
		sound = Instance.new("Sound")
		sound.Name = "GunSound"
		sound.SoundId = "http://www.roblox.com/asset?id=2101148"
		sound.Volume = 1
		sound.Parent = script.Parent
	end
	sound:play()



	
	local missile = Instance.new("Part")


	local barrel

	if gunOne == true then
		barrel = gunBarrelOne
		gunOne = true
	
	end
	
	local spawnPos = barrel.CFrame * Vector3.new(6, 0, 0)

	local dx = math.random(50,50)
	local dy = math.random(0,0)
	local dz = math.random(0,0)
	local mag = math.random(750,750)

	local v = barrel.CFrame:vectorToWorldSpace(Vector3.new(mag + dx,dy,dz))
	
	local missile = cannonBall:clone()

	missile.Position = spawnPos
	missile.Velocity = v


	
	local new_script = script.Parent.CannonBall:clone()
	new_script.Disabled = false
	new_script.Parent = missile

	local creator_tag = Instance.new("ObjectValue")
	creator_tag.Value = player
	creator_tag.Name = "creator"
	creator_tag.Parent = missile
	


	missile.Parent = game.Workspace


end

function onClicked()
	if debounce == false then
		debounce = true
		switch.BrickColor = BrickColor.new(21)
		-- let slip the dogs of war
		fire(player)
		wait(5)

		wait(1)
		debounce = false
		switch.BrickColor = BrickColor.new(37)
	end
end


script.Parent.ClickDetector.MouseClick:connect(onClicked)


