local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local rs = ReplicatedStorage

local sawmillActionEvent = Instance.new("RemoteEvent")
sawmillActionEvent.Name = "SawmillAction"
sawmillActionEvent.Parent = rs

-- Constants
local PROCESS_TIME = 5
local SAW_TIME = 2
local OUTPUT_TIME = 3
local PLANKS_PER_LOG = 2

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

local function getSawmillParts(sawmill)
	local parts = {
		hexagonPlacer = nil,
		hexagonClaimer = nil,
		sawBlade = nil,
	}
	for _, child in sawmill:GetDescendants() do
		if child.Name == "Hexagon_placer" then parts.hexagonPlacer = child end
		if child.Name == "Hexagon_claimer" then parts.hexagonClaimer = child end
		if child.Name == "SawBlade" then parts.sawBlade = child end
	end
	return parts
end

local function getPartPosition(part)
	if part:IsA("Model") then
		return part:GetPivot().Position
	end
	return part.CFrame.Position
end

-- Animate a model sliding from A to B (anchored, in workspace)
local function slideModel(model, startPos, endPos, duration)
	if not model or not model.Parent then return end

	local dir = (endPos - startPos)
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	if flatDir.Magnitude < 0.01 then
		flatDir = Vector3.new(1, 0, 0)
	end
	flatDir = flatDir.Unit

	-- Build start/end CFrames: lying on its side, oriented along the belt
	local startCF = CFrame.lookAt(startPos, startPos + flatDir) * CFrame.Angles(0, 0, math.rad(90))
	local endCF = CFrame.lookAt(endPos, endPos + flatDir) * CFrame.Angles(0, 0, math.rad(90))

	-- Anchor everything so physics doesn't interfere
	if model:IsA("BasePart") then
		model.Anchored = true
		model.CanCollide = false
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
		end
	end

	model:PivotTo(startCF)

	local steps = math.max(1, math.ceil(duration * 30))
	for i = 1, steps do
		if not model or not model.Parent then return end
		model:PivotTo(startCF:Lerp(endCF, i / steps))
		task.wait(1 / 30)
	end
end

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

		local hrp = char.HumanoidRootPart
		if (hrp.Position - sawmill:GetPivot().Position).Magnitude > 25 then return end

		local inv = _G.GetInventory and _G.GetInventory(player)
		if not inv then return end
		if (inv.Log or 0) < 1 then return end

		inv.Log = inv.Log - 1
		if _G.SendInventory then _G.SendInventory(player) end

		sawmill:SetAttribute("SawmillState", "processing")

		local parts = getSawmillParts(sawmill)
		local raft = getRaft()
		if not raft or not raft.PrimaryPart then return end

		sawmillActionEvent:FireAllClients("startProcessing", sawmill)

		task.spawn(function()
			-- Get world positions of key parts
			local placerPos = parts.hexagonPlacer and getPartPosition(parts.hexagonPlacer) or sawmill:GetPivot().Position
			local sawBladePos = parts.sawBlade and getPartPosition(parts.sawBlade) or sawmill:GetPivot().Position
			local claimerPos = parts.hexagonClaimer and getPartPosition(parts.hexagonClaimer) or sawmill:GetPivot().Position

			-- Raise slightly above the belt surface
			placerPos = placerPos + Vector3.new(0, 1.5, 0)
			sawBladePos = sawBladePos + Vector3.new(0, 1.5, 0)
			claimerPos = claimerPos + Vector3.new(0, 1.5, 0)

			-- Phase 1: Spawn log in WORKSPACE (not inside sawmill) and slide it
			local logTemplate = rs:FindFirstChild("Log")
			if not logTemplate then
				sawmill:SetAttribute("SawmillState", "idle")
				sawmillActionEvent:FireAllClients("stopProcessing", sawmill)
				return
			end

			local logClone = logTemplate:Clone()
			logClone.Name = "SawmillLog"
			-- Ensure PrimaryPart is set for PivotTo to work
			if logClone:IsA("Model") and not logClone.PrimaryPart then
				local first = logClone:FindFirstChildWhichIsA("BasePart")
				if first then logClone.PrimaryPart = first end
			end
			logClone.Parent = workspace

			slideModel(logClone, placerPos, sawBladePos, PROCESS_TIME)

			-- Phase 2: Destroy log, sawing pause
			if logClone and logClone.Parent then
				logClone:Destroy()
			end
			task.wait(SAW_TIME)

			-- Phase 3: Spawn planks and slide to claimer
			local plankTemplate = rs:FindFirstChild("plank")
			local plankClone = nil
			if plankTemplate then
				plankClone = plankTemplate:Clone()
				plankClone.Name = "SawmillPlank"
				if plankClone:IsA("Model") and not plankClone.PrimaryPart then
					local first = plankClone:FindFirstChildWhichIsA("BasePart")
					if first then plankClone.PrimaryPart = first end
				end
				plankClone.Parent = workspace

				slideModel(plankClone, sawBladePos, claimerPos, OUTPUT_TIME)
			end

			-- Ready for pickup
			sawmill:SetAttribute("SawmillState", "ready")
			sawmill:SetAttribute("PlanksReady", PLANKS_PER_LOG)
			sawmillStates[sawmill] = { plankClone = plankClone }

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

		sawmill:SetAttribute("SawmillState", "idle")
		sawmill:SetAttribute("PlanksReady", 0)
		sawmillStates[sawmill] = nil

		if _G.SendInventory then _G.SendInventory(player) end
	end
end)
