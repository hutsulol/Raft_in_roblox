print("Hello world!")

Character = script.Parent
Humanoid = Character.Humanoid
Torso = Character.Torso
mode = Instance.new("Model")
mode.Name = "Raggy"
mode.Parent = game.Workspace
face = 145952218

function OnDeath()
	
Humanoid.Died:connect(OnDeath)
end