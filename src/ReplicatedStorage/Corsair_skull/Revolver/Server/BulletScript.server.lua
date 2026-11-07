local Bullet = script.Parent
local NearbyBulletSound = Bullet:WaitForChild('NearbyBulletSound')

local Damage = Bullet:WaitForChild("Damage")

local Damaged = false
Bullet.Touched:Connect(function(hit)
	
	local CharHum = hit.Parent:FindFirstChildOfClass("Humanoid")
	
	if hit and CharHum and CharHum.Health > 0 and Damaged == false then
		
		Damaged = true
		
		CharHum.Health = CharHum.Health - Damage.Value
		NearbyBulletSound:Play()
		
	end
	wait(0.1)
	Bullet:Destroy()
end)

while wait(1.5) do
	Bullet:Destroy()
end