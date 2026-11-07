--!strict

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local Part = script.Parent :: BasePart
local CreatorTag = Part:FindFirstChildWhichIsA("ObjectValue")
local UserPlayer = CreatorTag and CreatorTag.Value :: Player?

local function tagHumanoid(target: Humanoid)
	if not (UserPlayer) then
		return
	end

	local previous = target:FindFirstChild("creator")
	if previous then
		previous:Destroy()
	end

	local new = Instance.new("ObjectValue")
	new.Value = UserPlayer
	new.Name = "creator"

	Debris:AddItem(new, 5.0)
	new.Parent = target
end

local function isTeammate(other: Player): boolean
	if (not UserPlayer) or (other.Neutral) then
		return false
	end

	return UserPlayer.Team == other.Team
end

local function hitPart(hit: BasePart)
	local character = hit.Parent :: Model
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	local player = Players:GetPlayerFromCharacter(character)
	
	if
		(not humanoid or humanoid.Health <= 0)
		or (player and isTeammate(player))
		or (UserPlayer and character == UserPlayer.Character)
	then
		return
	end
	
	tagHumanoid(humanoid)
	humanoid:TakeDamage(1.0)
end

local touchConnection = Part.Touched:Connect(hitPart)

task.wait(1.5)
Part.BrickColor = BrickColor.new("Black")
touchConnection:Disconnect()
task.wait(0.5)
Part:Destroy()
