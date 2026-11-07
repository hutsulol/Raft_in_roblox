-- Shovel @ JDLENL 3/22/20
-- If you use this in your game, consider mentioning me in the description! I'd appreciate it.


local MouseData = Instance.new("RemoteFunction",script.Parent)
local KeyEvent = Instance.new("RemoteEvent",script.Parent)
local Tool = script.Parent
local Gui = script.SoilGUI
local Handle = Tool.Handle

local Settings = require(script.Parent.Settings)

local Hitting = false

function Swing()
	local Anim = Instance.new("StringValue")
	Anim.Name = "toolanim"
	Anim.Value = "Slash"
	Anim.Parent = Tool
end

function CreateDust(Pos)
	local Attach = Instance.new("Attachment",workspace.Terrain)
	Attach.Position = Pos
	local Dust = script.DigSmoke:Clone()
	Dust.Parent = Attach
	Dust.Enabled = true
	game.Debris:AddItem(Attach,2)
end

script.Parent.Equipped:Connect(function()
	Handle.AllowPlacement.Value = Settings.AllowPlacement
	if Settings.GuiEnabled then
		local Player = game.Players:GetPlayerFromCharacter(Tool.Parent)
		Gui.Parent = Player.PlayerGui
		KeyEvent:FireClient(Player,Gui,Settings.Soil)
	end
	Tool.ToolTip = "Dig out terrain! " .. (Settings.AllowPlacement and "Press E to place soil." or "")
	Hitting = false
end)

script.Parent.Unequipped:Connect(function()
	if Settings.GuiEnabled then
		Gui.Parent = script
	end
	Hitting = false
end)

script.Parent.Activated:Connect(function()
	if not Tool.Enabled then return end
	Swing()
	local Player = game.Players:GetPlayerFromCharacter(Tool.Parent)
	if Player.Character.Humanoid.Health <= 0 then return end
	if Player then
		local Target,HitPos = MouseData:InvokeClient(Player)
		if Target and (HitPos - Handle.Position).Magnitude <= Settings.ReachDistance then
			if Target == workspace.Terrain then
				Tool.Enabled = false
				CreateDust(HitPos)
				workspace.Terrain:FillBall(HitPos,Settings.DigSize,Enum.Material.Air)
				Handle.Dig:Play()
				if Settings.ConsumeSoil then
					Settings.Soil = Settings.Soil + 1
				end
				if Settings.GuiEnabled then
					KeyEvent:FireClient(Player,Gui,Settings.Soil)
				end
				if Settings.Hunger then
					Player.Hunger.Value = math.clamp(Player.Hunger.Value - Settings.DigHunger,0,100)
				end
				wait(Settings.Cooldown)
				Tool.Enabled = true
			end
		end
	end
end)

KeyEvent.OnServerEvent:Connect(function(Player,Target,HitPos)
	if not Tool.Enabled then return end
	if Player.Character.Humanoid.Health <= 0 then return end
	if Settings.AllowPlacement and Target and (HitPos - Handle.Position).Magnitude <= Settings.ReachDistance then
		if (not Settings.ConsumeSoil) or (Settings.ConsumeSoil and Settings.Soil > 0) then
			Tool.Enabled = false
			Settings.Soil = Settings.Soil - 1
			Handle.Dig:Play()
			Swing()
			workspace.Terrain:FillBall(HitPos,Settings.PlaceSize,Settings.SoilMaterial)
			if Settings.GuiEnabled then
				KeyEvent:FireClient(Player,Gui,Settings.Soil)
			end
			if Settings.Hunger then
				Player.Hunger.Value = math.clamp(Player.Hunger.Value - Settings.PlaceHunger,0,100)
			end
			wait(Settings.PlacementCooldown)
			Tool.Enabled = true
		end
	end
end)

Handle.Touched:Connect(function(Part)
	if Settings.AllowDamage then
		if Part.Parent and Part.Parent:FindFirstChild"Humanoid" then
			if Hitting then return end
			if Part.Parent.Humanoid.Health > 0 then
				Part.Parent.Humanoid:TakeDamage(Settings.Damage)
				Handle.Bonk:Play()
				Hitting = true
				if Settings.DeathMessagesEnabled then
					local flag = Instance.new("ObjectValue",Part.Parent.Humanoid)
					flag.Name = Settings.DeathMessageFlag
					flag.Value = game.Players:GetPlayerFromCharacter(Tool.Parent)
					game.Debris:AddItem(flag,Settings.HitCooldown)
				end
				delay(Settings.HitCooldown,function()
					Hitting = false
				end)
			end
		end
	end
end)