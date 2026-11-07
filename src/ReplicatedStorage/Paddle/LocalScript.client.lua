local CanAttack = true


script.Parent.Equipped:Connect(function()
     local idle = script.Parent.Parent.Humanoid:LoadAnimation(script.Idle)
     local attack = script.Parent.Parent.Humanoid:LoadAnimation(script.Attack)


idle:Play()
end)


script.Parent.Activated:Connect(function()
     local idle = script.Parent.Parent.Humanoid:LoadAnimation(script.Idle)
     local attack = script.Parent.Parent.Humanoid:LoadAnimation(script.Attack)


if CanAttack == true then
    attack:Play()
    idle:Stop()
CanAttack = false
wait(1)
attack:Stop()
idle:Play()
CanAttack = true
script.Parent.CanDamage.Value = true
end
end)