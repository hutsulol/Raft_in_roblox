local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local rs = ReplicatedStorage

local sawmillActionEvent = Instance.new("RemoteEvent")
sawmillActionEvent.Name = "SawmillAction"
sawmillActionEvent.Parent = rs

-- Constants
local PROCESS_TIME = 5          -- seconds for log to travel to saw blade
local SAW_TIME = 2              -- seconds for sawing
local OUTPUT_TIME = 3           -- seconds for planks to travel to claimer
local PLANKS_PER_LOG = 2        -- planks output per log

-- Track active sawmills
local sawmillStates = {}

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

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

-- Get world position of a part or model
local function getPartPosition(part)
	if part:IsA("Model") then
		return part:GetPivot().Position
	else
		return part.CFrame.Position
	end
end

local function getPartCFrame(part)
	if part:IsA("Model") then
		return part:GetPivot()
	else
		return part.CFrame
	end
end

-- Smoothly move a model from point A to B over duration, welded to raft
local function moveModelAlongBelt(model, startPos, endPos, duration, raft, sawmillYaw)
	if not model or not model.Parent then return end
	if not raft or not raft.PrimaryPart then return end

	-- Orient the log/plank lying down along the belt direction
	local direction = (endPos - startPos)
	local flatDir = Vector3.new(direction.X, 0, direction.Z).Unit
	local logCF = CFrame.new(startPos) * CFrame.lookAt(Vector3.zero, flatDir) * CFrame.Angles(0, 0, math.rad(90))

	-- Set initial position with lying orientation
	model:PivotTo(CFrame.new(startPos, startPos + flatDir) * CFrame.Angles(0, 0, math.rad(90)))

	-- Anchor all parts for smooth movement (no physics jitter)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
		end
	end

	local elapsed = 0
	local steps = math.ceil(duration * 30)
	local startCF = model:GetPivot()
	local endCF = CFrame.new(endPos, endPos + flatDir) * CFrame.Angles(0, 0, math.rad(90))

	for i = 1, steps do
		if not model or not model.Parent then return end
		local t = i / steps
		model:PivotTo(startCF:Lerp(endCF, t))
		task.wait(1 / 30)
	end

	-- Final: weld to raft so it moves with the raft
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = p
			w.Part1 = raft.PrimaryPart
			w.Parent = p
		end
	end
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

		for _, desc in sawmill:GetDescendants() do
			if desc:IsA("Script") or desc:IsA("LocalScript") then
				desc:Destroy()
			end
		end

		if sawmill:IsA("Model") then
			local bbCF = sawmill:GetBoundingBox()
			sawmill.WorldPivot = CFrame.new(bbCF.Position)
		end

		local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(data)
		sawmill:PivotTo(worldCF)
		sawmill.Parent = raft
		weldToRaft(sawmill, raft)

		sawmill:SetAttribute("IsSawmill", true)
		sawmill:SetAttribute("SawmillState", "idle")
		sawmill:SetAttribute("PlanksReady", 0)
		CollectionService:AddTag(sawmill, "Sawmill")

		tool:Destroy()

	elseif action == "loadLog" then
		local char = player.Character
		if not char or not char:FindFirstChild("HumanoidRootPart") then return end

		if not data or not data.Parent then return end

		-- data can be the sawmill itself or a descendant
		local sawmill = nil
		if data:GetAttribute("IsSawmill") then
			sawmill = data
		else
			local current = data
			while current and current ~= workspace do
				if current:GetAttribute("IsSawmill") then
					sawmill = current
					break
				end
				current = current.Parent
			end
		end
		if not sawmill then return end

		if sawmill:GetAttribute("SawmillState") ~= "idle" then return end

		-- Distance check
		local hrp = char.HumanoidRootPart
		if (hrp.Position - sawmill:GetPivot().Position).Magnitude > 25 then return end

		-- Inventory check
		local inv = _G.GetInventory and _G.GetInventory(player)
		if not inv then return end
		if (inv.Log or 0) < 1 then return end

		inv.Log = inv.Log - 1
		if _G.SendInventory then _G.SendInventory(player) end

		sawmill:SetAttribute("SawmillState", "processing")

		local parts = getSawmillParts(sawmill)
		local raft = getRaft()
		if not raft or not raft.PrimaryPart then return end

		-- Notify clients to start spinning
		sawmillActionEvent:FireAllClients("startProcessing", sawmill)

		task.spawn(function()
			-- Get positions
			local placerPos = parts.hexagonPlacer and getPartPosition(parts.hexagonPlacer) or sawmill:GetPivot().Position
			local sawBladePos = parts.sawBlade and getPartPosition(parts.sawBlade) or sawmill:GetPivot().Position
			local claimerPos = parts.hexagonClaimer and getPartPosition(parts.hexagonClaimer) or sawmill:GetPivot().Position

			-- Lift start position slightly above the belt
			placerPos = placerPos + Vector3.new(0, 1.5, 0)
			sawBladePos = sawBladePos + Vector3.new(0, 1.5, 0)
			claimerPos = claimerPos + Vector3.new(0, 1.5, 0)

			-- Phase 1: Spawn log and move it to saw blade
			local logTemplate = rs:FindFirstChild("Log")
			if not logTemplate then
				sawmill:SetAttribute("SawmillState", "idle")
				sawmillActionEvent:FireAllClients("stopProcessing", sawmill)
				return
			end

			local logClone = logTemplate:Clone()
			logClone.Name = "SawmillLog"
			logClone:PivotTo(CFrame.new(placerPos))
			logClone.Parent = sawmill

			moveModelAlongBelt(logClone, placerPos, sawBladePos, PROCESS_TIME, raft)

			-- Phase 2: Sawing - destroy log, wait
			task.wait(SAW_TIME / 2)
			if logClone and logClone.Parent then
				logClone:Destroy()
			end
			task.wait(SAW_TIME / 2)

			-- Phase 3: Spawn planks and move to claimer
			local plankTemplate = rs:FindFirstChild("plank")
			if plankTemplate then
				local plankClone = plankTemplate:Clone()
				plankClone.Name = "SawmillPlank"
				plankClone:PivotTo(CFrame.new(sawBladePos))
				plankClone.Parent = sawmill

				moveModelAlongBelt(plankClone, sawBladePos, claimerPos, OUTPUT_TIME, raft)

				if sawmillStates[sawmill] then
					sawmillStates[sawmill].plankClone = plankClone
				else
					sawmillStates[sawmill] = { plankClone = plankClone }
				end
			end

			-- Ready for pickup
			sawmill:SetAttribute("SawmillState", "ready")
			sawmill:SetAttribute("PlanksReady", PLANKS_PER_LOG)

			sawmillActionEvent:FireAllClients("stopProcessing", sawmill)
		end)

	elseif action == "claimPlanks" then
		local char = player.Character
		if not char or not char:FindFirstChild("HumanoidRootPart") then return end

		if not data or not data.Parent then return end

		local sawmill = nil
		if data:GetAttribute("IsSawmill") then
			sawmill = data
		else
			local current = data
			while current and current ~= workspace do
				if current:GetAttribute("IsSawmill") then
					sawmill = current
					break
				end
				current = current.Parent
			end
		end
		if not sawmill then return end

		if sawmill:GetAttribute("SawmillState") ~= "ready" then return end

		local planksReady = sawmill:GetAttribute("PlanksReady") or 0
		if planksReady <= 0 then return end

		local hrp = char.HumanoidRootPart
		if (hrp.Position - sawmill:GetPivot().Position).Magnitude > 25 then return end

		local inv = _G.GetInventory and _G.GetInventory(player)
		if not inv then return end
		inv.Plank = (inv.Plank or 0) + planksReady

		-- Clean up plank model
		if sawmillStates[sawmill] and sawmillStates[sawmill].plankClone then
			if sawmillStates[sawmill].plankClone.Parent then
				sawmillStates[sawmill].plankClone:Destroy()
			end
		end
		for _, child in sawmill:GetChildren() do
			if child.Name == "SawmillPlank" then
				child:Destroy()
			end
		end

		sawmill:SetAttribute("SawmillState", "idle")
		sawmill:SetAttribute("PlanksReady", 0)
		sawmillStates[sawmill] = nil

		if _G.SendInventory then _G.SendInventory(player) end
	end
end)
