-- Handles Bed crafting and placement with sleep behavior
local rs = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local WORKBENCH_RANGE = 15
local BED_COOLDOWN = 3

local craftEvent = rs:WaitForChild("CraftItem")
local cupActionEvent = rs:WaitForChild("CupAction")

local function findWorkBench()
	for _, v in workspace:GetDescendants() do
		if v:IsA("Model") and v.Name == "WorkBench" then
			return v
		end
	end
	return nil
end

local function getWorkBenchPos()
	local wb = findWorkBench()
	if not wb then return nil end
	if wb.PrimaryPart then
		return wb.PrimaryPart.Position
	end
	local part = wb:FindFirstChildWhichIsA("BasePart", true)
	if part then return part.Position end
	return wb:GetPivot().Position
end

local function isNight()
	local clock = Lighting.ClockTime
	return clock >= 18 or clock < 6
end

local function getSleepingCount()
	local val = rs:FindFirstChild("SleepingPlayers")
	if not val then
		val = Instance.new("IntValue")
		val.Name = "SleepingPlayers"
		val.Value = 0
		val.Parent = rs
	end
	return val
end

-- ─── Setup bed behavior on a placed bed ───
local function setupBedBehavior(bedPart)
	local currentPlayer = nil
	local callbackHandler = nil

	local function standUp()
		if currentPlayer ~= nil and bedPart:FindFirstChild("BedWeld") then
			local sc = getSleepingCount()
			sc.Value = math.max(0, sc.Value - 1)

			local cooldownTag = Instance.new("StringValue", currentPlayer)
			cooldownTag.Name = "BedCooldown"
			game.Debris:AddItem(cooldownTag, BED_COOLDOWN)

			bedPart:FindFirstChild("BedWeld"):Destroy()

			if callbackHandler then
				callbackHandler:Disconnect()
				callbackHandler = nil
			end

			currentPlayer.Humanoid.PlatformStand = false
			currentPlayer.HumanoidRootPart.CFrame = bedPart.CFrame * CFrame.Angles(0, math.rad(180), 0) + Vector3.new(0, 5, 0)
			currentPlayer.HumanoidRootPart.Anchored = true
			task.wait()
			currentPlayer.HumanoidRootPart.Anchored = false
			currentPlayer = nil
		end
	end

	local function layDown(character)
		if character == nil or bedPart:FindFirstChild("BedWeld") then return end
		if not isNight() then return end

		currentPlayer = character
		currentPlayer.HumanoidRootPart.CFrame = bedPart.CFrame * CFrame.Angles(math.rad(90), 0, math.rad(-90))
		currentPlayer.Humanoid.PlatformStand = true

		local weld = Instance.new("WeldConstraint")
		weld.Name = "BedWeld"
		weld.Part0 = bedPart
		weld.Part1 = character.HumanoidRootPart
		weld.Parent = bedPart

		local sc = getSleepingCount()
		sc.Value = sc.Value + 1

		callbackHandler = currentPlayer.Humanoid.Changed:Connect(function(property)
			if currentPlayer ~= nil and property == "Jump" then
				standUp()
			end
		end)

		-- Auto stand up when night ends
		task.spawn(function()
			while currentPlayer ~= nil do
				if not isNight() then
					standUp()
					break
				end
				task.wait(0.5)
			end
		end)
	end

	bedPart.Touched:Connect(function(hit)
		local character = hit.Parent
		if character and character:FindFirstChild("Humanoid") and currentPlayer == nil and not character:FindFirstChild("BedCooldown") then
			layDown(character)
		end
	end)
end

-- ─── Crafting handler ───
craftEvent.OnServerEvent:Connect(function(player, action, data)
	if action ~= "craft" or data ~= "Bed" then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local wbPos = getWorkBenchPos()
	if not wbPos then return end

	local dist = (char.HumanoidRootPart.Position - wbPos).Magnitude
	if dist > WORKBENCH_RANGE then return end

	local inv = _G.GetInventory and _G.GetInventory(player) or {}
	if (inv.Log or 0) < 2 then return end

	if _G.RemoveResourceFromInventory then
		_G.RemoveResourceFromInventory(player, "Log", 2)
	else
		inv.Log = inv.Log - 2
	end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	local tool = Instance.new("Tool")
	tool.Name = "Bed"
	tool.CanBeDropped = false
	tool.TextureId = "rbxassetid://110032041583533"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.Parent = tool

	if _G.GiveToolOrDrop then
		_G.GiveToolOrDrop(player, tool)
	else
		tool.Parent = backpack
	end

	if _G.SendInventory then
		_G.SendInventory(player)
	end

	craftEvent:FireClient(player, "success", "Bed")
end)

-- ─── Placement handler ───
cupActionEvent.OnServerEvent:Connect(function(player, action, target)
	if action ~= "placeBed" then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Bed" then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end
	if typeof(target) ~= "CFrame" then return end

	local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

	local template = rs:FindFirstChild("Bed")
	if not template then return end

	local bed = template:Clone()
	bed.Name = "Bed"

	-- Remove existing scripts from clone
	for _, desc in bed:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end

	-- Reset WorldPivot
	if bed:IsA("Model") then
		local bbCF = bed:GetBoundingBox()
		bed.WorldPivot = CFrame.new(bbCF.Position)
	end

	bed:PivotTo(worldCF)
	bed.Parent = raft

	-- Find the main part for bed behavior
	local bedPart = bed.PrimaryPart or bed:FindFirstChildWhichIsA("BasePart", true)

	-- T13/T15/T16: snapshot raft velocity, force-anchor every part
	-- (templates may be authored unanchored), weld while anchored,
	-- then unanchor in a third pass so the new parts inherit the
	-- raft's velocity through the rigid weld instead of starting at
	-- zero. Without these guards, placing the bed (~5 parts) drains
	-- enough momentum out of the raft assembly to kick the buoyancy
	-- spring into a sustained vertical bob.
	local primary = raft.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity

	for _, part in bed:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	for _, part in bed:GetDescendants() do
		if part:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = raft.PrimaryPart
			weld.Parent = part
		end
	end
	for _, part in bed:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	primary.AssemblyLinearVelocity  = linVel
	primary.AssemblyAngularVelocity = angVel

	-- Setup bed sleep behavior directly
	if bedPart then
		setupBedBehavior(bedPart)
	end

	tool:Destroy()
end)
