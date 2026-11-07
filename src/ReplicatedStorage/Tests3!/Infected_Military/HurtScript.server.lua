Humanoid = script.Parent:WaitForChild("Humanoid")
Sound = Humanoid.Parent.Head:WaitForChild("Hurt")
CurrentHealth = Humanoid.Health

function HealthChanged(Health)
	local Change = math.abs(CurrentHealth - Health)
	if CurrentHealth > Health then
		Sound.Pitch = 1 + (math.random()*0.1)
		Sound:Play()
		script.Parent.DelayToStealth.Value = 5
	end
	CurrentHealth = Humanoid.Health
end

Humanoid.HealthChanged:connect(HealthChanged)