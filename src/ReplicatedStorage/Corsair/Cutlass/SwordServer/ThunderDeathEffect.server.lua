--!strict

local Figure = script.Parent :: Model
local Parts = {} :: { BasePart }

local COLOR = Color3.fromRGB(9, 137, 207)
local TAU = math.pi	* 2

for _, part in Figure:GetChildren() do
	if part:IsA("BasePart") then
		table.insert(Parts, part)
	end
end

task.wait(1.0)

local angOffset = math.random() * TAU
for i, part: BasePart in ipairs(Parts) do
	local bodyVel = Instance.new("BodyVelocity")
	local ang = TAU * (i / #Parts)

	bodyVel.MaxForce = (Vector3.one * part.Mass * workspace.Gravity)
	bodyVel.Velocity = CFrame.Angles(0, ang + angOffset, 0 ).LookVector * 31
	bodyVel.Parent = part
	
	pcall(part.SetNetworkOwner, part, nil)
	part.Color = COLOR
end
