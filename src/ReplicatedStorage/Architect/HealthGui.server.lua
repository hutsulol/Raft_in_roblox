if game:GetService("Players"):FindFirstChild(script.Parent.Name):FindFirstChild("PlayerGui"):FindFirstChild("NewHealthGui") ~= nil then
	game:GetService("Players"):FindFirstChild(script.Parent.Name):FindFirstChild("PlayerGui"):FindFirstChild("NewHealthGui"):Destroy()
end

NewHealthGui = Instance.new("ScreenGui",game:GetService("Players"):FindFirstChild(script.Parent.Name):FindFirstChild("PlayerGui"))
NewHealthGui.Name = "NewHealthGui"
Background = Instance.new("Frame",NewHealthGui)
Background.Name = "Background"
Background.Position = UDim2.new(0.5, -80, 1, -27)
Background.Size = UDim2.new(0,155,0,25)
Background.Style = Enum.FrameStyle.RobloxRound
Bar = Instance.new("TextLabel",Background)
Bar.Name = "Bar"
Bar.Position = UDim2.new(0,-5,0,-5)
Bar.Size = UDim2.new(0,149,0,20)
Bar.BackgroundColor3 = Color3.new(0,0.78431379795074,0)
Bar.BorderSizePixel = 0
Bar.Text = "  Здоровье"
Bar.Font = Enum.Font.ArialBold
Bar.FontSize = Enum.FontSize.Size18
Bar.TextXAlignment = Enum.TextXAlignment.Left
Bar.TextColor3 = Color3.new(0.97254908084869,0.97254908084869,0.97254908084869)
Percent = Instance.new("TextLabel", Bar)
Percent.Name = "Percent"
Percent.Position = UDim2.new(1,0,0.5,0)
Percent.Text = "100% "
Percent.Font = Enum.Font.ArialBold
Percent.FontSize = Enum.FontSize.Size18
Percent.TextXAlignment = Enum.TextXAlignment.Right
Percent.TextColor3 = Color3.new(0.97254908084869,0.97254908084869,0.97254908084869)
Hurt = Instance.new("Frame", NewHealthGui)
Hurt.Name = "Hurt"
Hurt.Size = UDim2.new(1,0,1,0)
Hurt.BackgroundColor3 = Color3.new(0.6,0,0)
Hurt.BackgroundTransparency = 1
Hurt.BorderSizePixel = 0

if game:GetService("Players"):FindFirstChild(script.Parent.Name):FindFirstChild("PlayerGui"):FindFirstChild("HealthGUI") ~= nil then
	game:GetService("Players"):FindFirstChild(script.Parent.Name):FindFirstChild("PlayerGui"):FindFirstChild("HealthGUI"):Destroy()
end

if not script.Parent:FindFirstChild("Humanoid") then
	repeat wait() until script.Parent:FindFirstChild("Humanoid")
end

humanoid = script.Parent.Humanoid
player = game:GetService("Players"):FindFirstChild(script.Parent.Name)
char = script.Parent
oldhealth = humanoid.Health/humanoid.MaxHealth
hover = false

function hit()
	Hurt.BackgroundTransparency = 0.7
	coroutine.resume(coroutine.create(function() for i = 1,10 do if i > 6 then wait(0.05);Hurt.BackgroundTransparency = i/10 end end end)) --<3 coroutines
end

function healthUpdate()
	local newhealth = humanoid.Health/humanoid.MaxHealth --gets percent so it's more accurate when comparing
	if oldhealth > newhealth then
		hit()
	end
	Bar.Size = UDim2.new(0,149*newhealth,0,20)
	Bar.Text = " Здоровье"
	Percent.Text = math.floor(newhealth*100).."%"
	if hover then
		Bar.Text = " Жив"
		Percent.Text = "("..math.floor(humanoid.Health).."/"..humanoid.MaxHealth..")"
	end
	if newhealth < .63 then
		Bar.Text = ""
	end
	if newhealth < .25 then
		Percent.Text = ""
	end
	k = 0.78431379795074-(1-((humanoid.Health*2)/humanoid.MaxHealth))
	h = 1-((humanoid.Health*2)/humanoid.MaxHealth)
	if k < 0 then
		k = 0
	end
	if h < 0 then
		h = 0
		k = 0.78431379795074
	end
	if newhealth >= .1 and newhealth < .15 then
		h = h+.2
		k = k+.2
	end
	if newhealth >= .15 and newhealth < .2 then
		h = h+.3
		k = k+.3
	end
	if newhealth >= .2 and newhealth < .375 then
		h = h+.4
		k = k+.4
	end
	if k > 1 or (newhealth >= .375 and newhealth < .4) then
		k = 0.9
	end
	if newhealth >= .4 and newhealth < .5 then
		k = 0.825
	end
	if h > 1 then
		k = 1
	end
	Bar.BackgroundColor3 = Color3.new(h,k,0)
	if humanoid.Health == 0 then
		Bar.Text = " Мёртв"
		Percent.Text = ""
		if hover then
			Percent.Text = "(0/"..humanoid.MaxHealth..")"
		end
	end
	if newhealth < .45 then
		Bar.Text = ""
	end
	if newhealth < .25 and humanoid.Health ~= 0 then
		Percent.Text = ""
	end
	oldhealth = newhealth
end

healthUpdate()
Background.MouseEnter:connect(function()hover = true;healthUpdate() end)
Background.MouseLeave:connect(function()hover = false;healthUpdate() end)
humanoid.HealthChanged:connect(healthUpdate)