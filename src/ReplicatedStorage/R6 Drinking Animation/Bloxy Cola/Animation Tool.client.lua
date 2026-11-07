local tool = script.Parent
local Eatanim = Instance.new("Animation")
local almaanim = Instance.new("Animation")
Eatanim.AnimationId = "http://www.roblox.com/Asset?ID=17076358998"
almaanim.AnimationId = "http://www.roblox.com/Asset?ID=17089919626"
local track

tool.Activated:Connect(function()
    track = script.Parent.Parent.Humanoid:LoadAnimation(Eatanim)
    track.Priority = Enum.AnimationPriority.Action
    track.Looped = false
    track:Play()
end)

tool.Equipped:Connect(function()
	
	track = script.Parent.Parent.Humanoid:LoadAnimation(almaanim)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	track:Play()
	
end)