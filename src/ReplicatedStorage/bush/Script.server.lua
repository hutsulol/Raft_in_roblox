local grape = script.Parent.grapes
local sound = script.Parent.Union.Sound
click = script.Parent.ClickDetector

Toolname = "[GRAPES]"

function onClicked(Player)
	grape.Transparency = 1
	sound:Play()
	click.MaxActivationDistance = 0
	
	if not Player.Backpack:FindFirstChild(Toolname) then
		local Tool = game.Lighting[Toolname]:clone()
		Tool.Parent = Player.Backpack
	end
	
	wait(10)
	
	click.MaxActivationDistance = 8
	grape.Transparency = 0
	
end

script.Parent.ClickDetector.MouseClick:connect(onClicked)