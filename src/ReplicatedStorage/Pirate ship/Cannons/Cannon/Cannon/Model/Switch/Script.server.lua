function onClicked()
	script.Parent.Parent.Flame.Transparency = 0.1
	wait(0.00000000000001)
	script.Parent.Parent.Flame.Transparency = 0.2
	wait(0.00000000000001)
	script.Parent.Parent.Flame.Transparency = 0.4
	wait(0.00000000000001)
	script.Parent.Parent.Flame.Transparency = 0.6
	wait(0.00000000000001)
	script.Parent.Parent.Flame.Transparency = 0.8
	wait(0.00000000000001)
	script.Parent.Parent.Flame.Transparency = 0.7
	wait(0.00000000000001)
	script.Parent.Parent.Flame.Transparency = 1
	wait(0.00000000000001)
	script.Parent.Parent.Flame.Smoke.Enabled=true
	wait(0.7) 
	script.Parent.Parent.Flame.Smoke.Enabled=false
	
end
script.Parent.ClickDetector.MouseClick:connect(onClicked)
