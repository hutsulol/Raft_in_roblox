local Tool = script.Parent

function OnButton1Down(mouse)
	if Tool.Enabled then
		mouse.Icon = 'rbxasset://textures\\GunCursor.png'
	else
		mouse.Icon = 'rbxasset://textures\\GunWaitCursor.png'
	end
	while not Tool.Enabled do
		Tool.Changed:wait()
	end
	if Tool.Enabled then
		mouse.Icon = 'rbxasset://textures\\GunCursor.png'
	end
end

function OnEquipped(mouse)
	if mouse == nil then
		print("Mouse not found")
		return 
	end

	mouse.Icon = 'rbxasset://textures\\GunCursor.png'
	mouse.Button1Down:connect(function() OnButton1Down(mouse) end)
end


Tool.Equipped:connect(OnEquipped)
