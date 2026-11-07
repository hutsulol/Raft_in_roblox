ball = script.Parent
damage = 150

function onTouched(hit)


	local humanoid = hit.Parent:findFirstChild("Humanoid")
	if humanoid~=nil then
		tagHumanoid(humanoid)
		humanoid.Health = humanoid.Health - damage
		wait(0.00000001)
		untagHumanoid(humanoid)
		connection:disconnect()
	else
		damage = damage / 2
		if damage < 2 then
			connection:disconnect()
			ball.Parent = nil
		end
	end

	if math.random(1,1) == 1 then
		explosion = Instance.new("Explosion")
		explosion.BlastRadius = 15
		explosion.BlastPressure = 600000 -- these are really wussy units
		explosion.Position = script.Parent.Position
		explosion.Parent = game.Workspace
		connection:disconnect()
		ball.Parent = nil
		cancollide = true
	end

end

function tagHumanoid(humanoid)
	-- todo: make tag expire
	local tag = ball:findFirstChild("creator")
	if tag ~= nil then
		local new_tag = tag:clone()
		new_tag.Parent = humanoid
	end
end


function untagHumanoid(humanoid)
	if humanoid ~= nil then
		local tag = humanoid:findFirstChild("creator")
		if tag ~= nil then
			tag.Parent = nil
		end
	end
end

connection = ball.Touched:connect(onTouched)

r = game:service("RunService")
t, s = r.Stepped:wait()
d = t + 5.0 - s
while t < d do
	t = r.Stepped:wait()
end

ball.Parent = nil