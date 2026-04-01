-- BedScript: place this Script inside the bed part
-- Player touches bed at night → lies down. Jump to stand up.
-- While sleeping, night passes 20x faster.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cooldown = 3
local CurrentPlayer = nil
local CallbackHandler = nil
local CName = 'BedCooldown'

local function isNight()
	local clock = Lighting.ClockTime
	return clock >= 18 or clock < 6
end

local function getSleepingCount()
	local val = ReplicatedStorage:FindFirstChild("SleepingPlayers")
	if not val then
		val = Instance.new("IntValue")
		val.Name = "SleepingPlayers"
		val.Value = 0
		val.Parent = ReplicatedStorage
	end
	return val
end

function StandupFromBed()
	if CurrentPlayer ~= nil and script.Parent:FindFirstChild("WeldConstraint") then
		-- Decrement sleeping count
		local sc = getSleepingCount()
		sc.Value = math.max(0, sc.Value - 1)

		local C = Instance.new("StringValue", CurrentPlayer)
		C.Name = CName
		game.Debris:AddItem(C, Cooldown)
		script.Parent.WeldConstraint:Remove()
		if CallbackHandler ~= nil then
			CallbackHandler:disconnect()
			CallbackHandler = nil
		end
		CurrentPlayer.Humanoid.PlatformStand = false
		CurrentPlayer.HumanoidRootPart.CFrame = script.Parent.CFrame * CFrame.Angles(0, math.rad(180), 0) + Vector3.new(0, 5, 0)
		CurrentPlayer.HumanoidRootPart.Anchored = true
		wait()
		CurrentPlayer.HumanoidRootPart.Anchored = false
		CurrentPlayer = nil
	end
end

function LayToBed(character)
	if character ~= nil and not script.Parent:FindFirstChild("WeldConstraint") then
		-- Only allow sleeping at night
		if not isNight() then return end

		CurrentPlayer = character
		CurrentPlayer.HumanoidRootPart.CFrame = script.Parent.CFrame * CFrame.Angles(math.rad(90), 0, math.rad(-90))
		CurrentPlayer.Humanoid.PlatformStand = true
		local Weld = Instance.new("WeldConstraint", script.Parent)
		Weld.Part0 = script.Parent
		Weld.Part1 = character.HumanoidRootPart

		-- Increment sleeping count
		local sc = getSleepingCount()
		sc.Value = sc.Value + 1

		CallbackHandler = CurrentPlayer.Humanoid.Changed:Connect(function(property)
			if CurrentPlayer ~= nil and property == 'Jump' then
				StandupFromBed()
			end
		end)

		-- Auto stand up when night ends (day arrives)
		task.spawn(function()
			while CurrentPlayer ~= nil do
				if not isNight() then
					StandupFromBed()
					break
				end
				task.wait(0.5)
			end
		end)
	end
end

script.Parent.Touched:Connect(function(hit)
	local Character = hit.Parent
	if Character:FindFirstChild("Humanoid") and CurrentPlayer == nil and not Character:FindFirstChild(CName) then
		LayToBed(Character)
	end
end)
