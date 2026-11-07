Tool = script.Parent

local field = nil

local Humanoid = Tool.Parent

local debounce = false

function Heal()
	
	local vCharacter = Tool.Parent

	wait(2.2)
	
	script.Parent.Handle.Eating:Play()

	local human = vCharacter:FindFirstChild("Humanoid")
	
	if (human ~= nil) then
		
		human.Health = human.MaxHealth
		
	end

end

Tool.Enabled = true

if debounce == false then
	
	debounce = true
	
	function onActivated()

	if not Tool.Enabled then
		return
	end

	Tool.Enabled = true

	Heal()
	
	wait(0.8)
	
	Tool:Destroy()
	
	wait(0.1)
	
	debounce = false

end

end

script.Parent.Activated:connect(onActivated)







