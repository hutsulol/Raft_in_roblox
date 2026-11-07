-- Shovel - Client Controls @ JDLENL 3/22/20
-- If you use this in your game, consider mentioning me in the description! I'd appreciate it.

local Tool = script.Parent
local Player = game.Players.LocalPlayer
local Mouse = Player:GetMouse()
local UIS = game:GetService("UserInputService")
local Handle = Tool:WaitForChild("Handle")
local CanPlace = Handle:WaitForChild"AllowPlacement"
local GUI

Tool:WaitForChild("RemoteFunction").OnClientInvoke = function(...)
	return Mouse.Target,Mouse.Hit.p
end

local _C

Tool.Equipped:Connect(function()
	_C = UIS.InputBegan:Connect(function(Input,GPE)
		if GPE then return end
		if not CanPlace.Value then return end
		if Input.UserInputType == Enum.UserInputType.Keyboard then
			if Input.KeyCode == Enum.KeyCode.E then
				Tool:WaitForChild("RemoteEvent"):FireServer(Mouse.Target,Mouse.Hit.p)
			end
		end
	end)
end)

Tool.Unequipped:Connect(function()
	if not CanPlace.Value then return end
	_C:Disconnect()
	_C = nil
end)

Tool:WaitForChild("RemoteEvent").OnClientEvent:Connect(function(Gui,SoilCount)
	GUI = Gui
	if SoilCount then
		GUI.TextLabel.Text = "Почва: "..SoilCount
	end
end)