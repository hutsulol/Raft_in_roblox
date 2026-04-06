local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local rs = ReplicatedStorage

local sawmillActionEvent = Instance.new("RemoteEvent")
sawmillActionEvent.Name = "SawmillAction"
sawmillActionEvent.Parent = rs

-- Constants
local PROCESS_TIME = 5          -- seconds for log to travel to saw blade
local SAW_TIME = 2              -- seconds for sawing animation
local OUTPUT_TIME = 3           -- seconds for planks to travel to claimer
local HEXAGON_SPIN_SPEED = 2    -- rotations per second (in radians/frame)
local SAW_SPIN_SPEED = 8        -- saw blade spins faster
local PLANKS_PER_LOG = 2        -- how many planks per log

-- Track active sawmills and their state
local sawmillStates = {} -- [sawmill] = {state, logModel, plankModel}

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

-- Weld all parts of a model to raft primary part
local function weldToRaft(obj, raft)
	for _, part in obj:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = raft.PrimaryPart
			weld.Parent = part
		end
	end
end

-- Find key parts inside the sawmill model
local function getSawmillParts(sawmill)
	local parts = {
		hexagonPlacer = nil,
		hexagonClaimer = nil,
		sawBlade = nil,
		hexagons = {},
	}

	for _, child in sawmill:GetDescendants() do
		if child.Name == "Hexagon_placer" then
			parts.hexagonPlacer = child
		elseif child.Name == "Hexagon_claimer" then
			parts.hexagonClaimer = child
		elseif child.Name == "SawBlade" then
			parts.sawBlade = child
		elseif child.Name == "Hexagon" and child:IsA("BasePart") then
			table.insert(parts.hexagons, child)
		end
	end

	return parts
end

-- Place sawmill on raft
sawmillActionEvent.OnServerEvent:Connect(function(player, action, data)
	if action == "placeSawmill" then
		local char = player.Character
		if not char then return end
		local tool = char:FindFirstChildWhichIsA("Tool")
		if not tool or tool.Name ~= "Sawmill" then return end
		if typeof(data) ~= "CFrame" then return end

		local raft = getRaft()
		if not raft or not raft.PrimaryPart then return end

		local template = rs:FindFirstChild("Sawmill")
		if not template then return end

		local sawmill = template:Clone()
		sawmill.Name = "Sawmill"

		-- Remove scripts from clone
		for _, desc in sawmill:GetDescendants() do
			if desc:IsA("Script") or desc:IsA("LocalScript") then
				desc:Destroy()
			end
		end

		-- Reset pivot to bounding box center
		if sawmill:IsA("Model") then
			local bbCF = sawmill:GetBoundingBox()
			sawmill.WorldPivot = CFrame.new(bbCF.Position)
		end

		local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(data)
		sawmill:PivotTo(worldCF)
		sawmill.Parent = raft

		-- Weld to raft
		weldToRaft(sawmill, raft)

		-- Mark as sawmill for interaction detection
		sawmill:SetAttribute("IsSawmill", true)
		sawmill:SetAttribute("SawmillState", "idle") -- idle, processing, ready
		sawmill:SetAttribute("PlanksReady", 0)
		CollectionService:AddTag(sawmill, "Sawmill")

		tool:Destroy()

	elseif action == "loadLog" then
		-- Player wants to load a log into the sawmill
		local char = player.Character
		if not char or not char:FindFirstChild("HumanoidRootPart") then return end

		-- data = the sawmill model (sent as the Hexagon_placer part)
		if not data or not data.Parent then return end

		-- Find the sawmill model
		local sawmill = nil
		local current = data
		while current and current ~= workspace do
			if current:GetAttribute("IsSawmill") then
				sawmill = current
				break
			end
			current = current.Parent
		end
		if not sawmill then return end

		-- Check state
		local state = sawmill:GetAttribute("SawmillState")
		if state ~= "idle" then return end

		-- Check distance
		local hrp = char.HumanoidRootPart
		local sawmillPos = sawmill:GetPivot().Position
		if (hrp.Position - sawmillPos).Magnitude > 20 then return end

		-- Check inventory
		local inv = _G.GetInventory and _G.GetInventory(player)
		if not inv then return end
		if (inv.Log or 0) < 1 then return end

		-- Deduct log
		inv.Log = inv.Log - 1
		if _G.SendInventory then _G.SendInventory(player) end

		-- Start processing
		sawmill:SetAttribute("SawmillState", "processing")

		-- Get sawmill parts
		local parts = getSawmillParts(sawmill)
		if not parts.hexagonPlacer then return end

		local raft = getRaft()
		if not raft or not raft.PrimaryPart then return end

		-- Clone log template and position at placer
		local logTemplate = rs:FindFirstChild("Log")
		if not logTemplate then return end

		local logClone = logTemplate:Clone()
		logClone.Name = "SawmillLog"

		-- Position the log at the hexagon placer
		local placerCF = parts.hexagonPlacer.CFrame
		if parts.hexagonPlacer:IsA("Model") then
			placerCF = parts.hexagonPlacer:GetPivot()
		end

		logClone:PivotTo(placerCF + Vector3.new(0, 1, 0))
		logClone.Parent = sawmill

		-- Weld log to raft initially
		for _, p in logClone:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.CanCollide = false
				local w = Instance.new("WeldConstraint")
				w.Part0 = p
				w.Part1 = raft.PrimaryPart
				w.Parent = p
			end
		end

		-- Store state
		sawmillStates[sawmill] = {
			logClone = logClone,
			parts = parts,
		}

		-- Notify clients to start animation
		sawmillActionEvent:FireAllClients("startProcessing", sawmill)

		-- Run the conveyor process
		task.spawn(function()
			-- Phase 1: Log moves from placer toward saw blade
			if parts.sawBlade then
				local sawBladeCF
				if parts.sawBlade:IsA("Model") then
					sawBladeCF = parts.sawBlade:GetPivot()
				else
					sawBladeCF = parts.sawBlade.CFrame
				end

				-- Move log to saw blade position
				local startCF = logClone:GetPivot()
				local endCF = CFrame.new(sawBladeCF.Position) * startCF.Rotation

				for t = 0, 1, 1 / (PROCESS_TIME * 30) do
					if not logClone or not logClone.Parent then return end
					local interpCF = startCF:Lerp(endCF, t)

					-- Remove old welds and re-weld at new position
					for _, p in logClone:GetDescendants() do
						if p:IsA("WeldConstraint") then p:Destroy() end
					end
					logClone:PivotTo(interpCF)
					for _, p in logClone:GetDescendants() do
						if p:IsA("BasePart") then
							p.Anchored = false
							p.CanCollide = false
							local w = Instance.new("WeldConstraint")
							w.Part0 = p
							w.Part1 = raft.PrimaryPart
							w.Parent = p
						end
					end
					task.wait(1 / 30)
				end
			end

			-- Phase 2: Sawing - destroy log, create planks
			task.wait(SAW_TIME)

			if logClone and logClone.Parent then
				logClone:Destroy()
			end

			-- Clone plank template
			local plankTemplate = rs:FindFirstChild("plank")
			if not plankTemplate then
				-- Sawmill still finishes even without plank model
				sawmill:SetAttribute("SawmillState", "ready")
				sawmill:SetAttribute("PlanksReady", PLANKS_PER_LOG)
				sawmillActionEvent:FireAllClients("stopProcessing", sawmill)
				return
			end

			local plankClone = plankTemplate:Clone()
			plankClone.Name = "SawmillPlank"

			-- Position at saw blade
			local sawPos
			if parts.sawBlade then
				if parts.sawBlade:IsA("Model") then
					sawPos = parts.sawBlade:GetPivot().Position
				else
					sawPos = parts.sawBlade.CFrame.Position
				end
			else
				sawPos = sawmill:GetPivot().Position
			end

			plankClone:PivotTo(CFrame.new(sawPos) * CFrame.Angles(0, sawmill:GetPivot().Rotation:ToEulerAnglesYXZ()))
			plankClone.Parent = sawmill

			for _, p in plankClone:GetDescendants() do
				if p:IsA("BasePart") then
					p.Anchored = false
					p.CanCollide = false
					local w = Instance.new("WeldConstraint")
					w.Part0 = p
					w.Part1 = raft.PrimaryPart
					w.Parent = p
				end
			end

			-- Phase 3: Move planks to claimer
			if parts.hexagonClaimer then
				local claimerCF
				if parts.hexagonClaimer:IsA("Model") then
					claimerCF = parts.hexagonClaimer:GetPivot()
				else
					claimerCF = parts.hexagonClaimer.CFrame
				end

				local startCF2 = plankClone:GetPivot()
				local endCF2 = CFrame.new(claimerCF.Position) * startCF2.Rotation

				for t = 0, 1, 1 / (OUTPUT_TIME * 30) do
					if not plankClone or not plankClone.Parent then return end
					local interpCF = startCF2:Lerp(endCF2, t)

					for _, p in plankClone:GetDescendants() do
						if p:IsA("WeldConstraint") then p:Destroy() end
					end
					plankClone:PivotTo(interpCF)
					for _, p in plankClone:GetDescendants() do
						if p:IsA("BasePart") then
							p.Anchored = false
							p.CanCollide = false
							local w = Instance.new("WeldConstraint")
							w.Part0 = p
							w.Part1 = raft.PrimaryPart
							w.Parent = p
						end
					end
					task.wait(1 / 30)
				end
			end

			-- Ready for pickup
			sawmill:SetAttribute("SawmillState", "ready")
			sawmill:SetAttribute("PlanksReady", PLANKS_PER_LOG)

			if sawmillStates[sawmill] then
				sawmillStates[sawmill].plankClone = plankClone
			end

			-- Stop conveyor animation
			sawmillActionEvent:FireAllClients("stopProcessing", sawmill)
		end)

	elseif action == "claimPlanks" then
		-- Player picks up planks from the claimer
		local char = player.Character
		if not char or not char:FindFirstChild("HumanoidRootPart") then return end

		if not data or not data.Parent then return end

		-- Find the sawmill model
		local sawmill = nil
		local current = data
		while current and current ~= workspace do
			if current:GetAttribute("IsSawmill") then
				sawmill = current
				break
			end
			current = current.Parent
		end
		if not sawmill then return end

		local state = sawmill:GetAttribute("SawmillState")
		if state ~= "ready" then return end

		local planksReady = sawmill:GetAttribute("PlanksReady") or 0
		if planksReady <= 0 then return end

		-- Check distance
		local hrp = char.HumanoidRootPart
		local sawmillPos = sawmill:GetPivot().Position
		if (hrp.Position - sawmillPos).Magnitude > 20 then return end

		-- Add planks to inventory
		local inv = _G.GetInventory and _G.GetInventory(player)
		if not inv then return end
		inv.Plank = (inv.Plank or 0) + planksReady

		-- Clean up plank model
		if sawmillStates[sawmill] and sawmillStates[sawmill].plankClone then
			sawmillStates[sawmill].plankClone:Destroy()
			sawmillStates[sawmill].plankClone = nil
		end

		-- Also clean up any SawmillPlank children
		for _, child in sawmill:GetChildren() do
			if child.Name == "SawmillPlank" then
				child:Destroy()
			end
		end

		-- Reset state
		sawmill:SetAttribute("SawmillState", "idle")
		sawmill:SetAttribute("PlanksReady", 0)
		sawmillStates[sawmill] = nil

		if _G.SendInventory then _G.SendInventory(player) end
	end
end)
