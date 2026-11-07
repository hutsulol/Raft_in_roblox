sp = script.Parent

Mesh = false -- If true will load BC 2.0 Arm meshes as well.
Shirt = true -- If true will load the user's shirt to the arms as well

function onEquipped(mouse)
	local Player = game:GetService("Players").LocalPlayer	
	local Cam = game.Workspace.CurrentCamera
	
	local Arms = Instance.new("Model")
	Arms.Name = "Arms"
	Arms.Parent = Cam
	
	if Shirt == true then
		local Humanoid = Instance.new("Humanoid")
		Humanoid.MaxHealth = 0
		Humanoid.Health = 0
		Humanoid.Name = ""
		Humanoid.Parent = Arms
			--Packages bro
for i,v in ipairs(Player.Character:GetChildren()) do
if v.className == "CharacterMesh" or v.className == "Shirt" then
baws = v:clone()
baws.Parent = Arms
else
end
end
end
	local RightArm = Player.Character:FindFirstChild("Right Arm"):clone()
	RightArm.Name = "Right Arm"
	RightArm.Transparency = 0
RightArm.CanCollide = false
RightArm.TopSurface = 0
RightArm.BottomSurface = 0
	
	local w = Instance.new("Weld")
	w.Part0 = RightArm
	w.Part1 = Player.Character:FindFirstChild("Right Arm")
	w.C0 = CFrame.new()
	w.C1 = CFrame.new()
	w.Parent = RightArm	
	RightArm.Parent = Arms
		
	local LeftArm = Player.Character:FindFirstChild("Left Arm"):clone()
	LeftArm.Name = "Left Arm"
	LeftArm.Transparency = 0	
LeftArm.CanCollide = false
LeftArm.TopSurface = 0
LeftArm.BottomSurface = 0
	
	local w = Instance.new("Weld")
	w.Part0 = LeftArm
	w.Part1 = Player.Character:FindFirstChild("Left Arm")
	w.C0 = CFrame.new()
	w.C1 = CFrame.new()
	w.Parent = LeftArm	
	LeftArm.Parent = Arms
	
	if Mesh ~= false then
		local LeftArmMesh = script:FindFirstChild("LeftArm")
		LeftArmMesh.Parent = LeftArm
		local RightArmMesh = script:FindFirstChild("RightArm")
		RightArmMesh.Parent = RightArm
	else end
				
end

function onUnequipped(mouse)
	local Player = game:GetService("Players").LocalPlayer		
	local Cam = script.Parent
	for _, Model in pairs(game.Workspace.CurrentCamera:GetChildren()) do
		if Model.Name == "Arms" then
			Model:remove()
		else end
	end	
end

sp.Equipped:connect(onEquipped)
sp.Unequipped:connect(onUnequipped)
