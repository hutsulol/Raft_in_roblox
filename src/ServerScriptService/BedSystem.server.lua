--[[
	BedSystem.server.lua
	Handles bed interaction: player lies down on touch, jumps to stand up.
	While sleeping at night, signals DayNightCycle to speed up time 20x.
	This script is placed in ServerScriptService and finds all beds via tag/attribute.

	Each bed part must have the attribute "IsBed" = true.
	The bed script from inside the model is replaced by this centralized version.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Cooldown = 3
local CName = "BedCooldown"

local sleepingCount = ReplicatedStorage:WaitForChild("SleepingPlayers")

-- Track which bed each player is using
local bedOccupants = {} -- [bedPart] = character
local playerBeds = {} -- [player] = bedPart

local function isNight()
	local dayDuration = 60
	local fullCycle = dayDuration + 120
	-- We check via Lighting.ClockTime instead
	local clock = game:GetService("Lighting").ClockTime
	return clock >= 18 or clock < 6
end

local function standUp(bedPart)
	local character = bedOccupants[bedPart]
	if not character then return end

	local weld = bedPart:FindFirstChild("WeldConstraint")
	if weld then weld:Destroy() end

	-- Add cooldown
	local C = Instance.new("StringValue")
	C.Name = CName
	C.Parent = character
	game.Debris:AddItem(C, Cooldown)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = bedPart.CFrame * CFrame.Angles(0, math.rad(180), 0) + Vector3.new(0, 5, 0)
		hrp.Anchored = true
		task.wait()
		hrp.Anchored = false
	end

	-- Find the player for this character
	local player = Players:GetPlayerFromCharacter(character)
	if player and playerBeds[player] == bedPart then
		playerBeds[player] = nil
		player:SetAttribute("Sleeping", false)
	end

	bedOccupants[bedPart] = nil
	sleepingCount.Value = math.max(0, sleepingCount.Value - 1)
end

local function layDown(bedPart, character)
	if bedOccupants[bedPart] then return end
	if character:FindFirstChild(CName) then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then return end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	-- Don't allow sleeping in two beds
	if playerBeds[player] then return end

	bedOccupants[bedPart] = character
	playerBeds[player] = bedPart

	hrp.CFrame = bedPart.CFrame * CFrame.Angles(math.rad(90), 0, math.rad(-90))
	humanoid.PlatformStand = true

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bedPart
	weld.Part1 = hrp
	weld.Parent = bedPart

	player:SetAttribute("Sleeping", true)
	sleepingCount.Value = sleepingCount.Value + 1

	-- Listen for jump to stand up
	local conn
	conn = humanoid.Changed:Connect(function(property)
		if property == "Jump" and bedOccupants[bedPart] == character then
			conn:Disconnect()
			standUp(bedPart)
		end
	end)
end

-- Setup a bed part
local function setupBed(bedPart)
	bedPart.Touched:Connect(function(hit)
		local character = hit.Parent
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and not bedOccupants[bedPart] and not character:FindFirstChild(CName) then
			layDown(bedPart, character)
		end
	end)
end

-- Find all existing beds and watch for new ones
for _, bed in ipairs(CollectionService:GetTagged("Bed")) do
	setupBed(bed)
end

CollectionService:GetInstanceAddedSignal("Bed"):Connect(setupBed)

-- Also support beds with IsBed attribute (for placed beds)
local function scanForBeds(parent)
	for _, child in ipairs(parent:GetDescendants()) do
		if child:GetAttribute("IsBed") and child:IsA("BasePart") then
			if not CollectionService:HasTag(child, "Bed") then
				CollectionService:AddTag(child, "Bed")
				setupBed(child)
			end
		end
	end
end

scanForBeds(workspace)
workspace.DescendantAdded:Connect(function(desc)
	if desc:GetAttribute("IsBed") and desc:IsA("BasePart") then
		task.wait() -- let it settle
		if not CollectionService:HasTag(desc, "Bed") then
			CollectionService:AddTag(desc, "Bed")
			setupBed(desc)
		end
	end
end)

-- Clean up when player leaves
Players.PlayerRemoving:Connect(function(player)
	local bedPart = playerBeds[player]
	if bedPart then
		bedOccupants[bedPart] = nil
		playerBeds[player] = nil
		sleepingCount.Value = math.max(0, sleepingCount.Value - 1)
	end
end)
