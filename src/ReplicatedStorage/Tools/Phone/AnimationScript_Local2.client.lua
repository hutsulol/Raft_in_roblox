wait(.5)

local humanoid = game.Players.LocalPlayer.Character.Humanoid
local animation = script.Animation
local animator = humanoid:LoadAnimation(animation)

if not humanoid then
	script.Parent.AnimationScript_Local.Disabled=false
	script.Disabled = true
end

script.Parent.Equipped:Connect(function()
	animator:Play()
	script.Parent.Handle.Sound:Play()
end)

script.Parent.Unequipped:Connect(function()
	animator:Stop()
	script.Parent.Handle.Sound:Stop()
end)