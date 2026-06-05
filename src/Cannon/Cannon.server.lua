local cannon = script.Parent

local function findPartNamed(name)
	for _, d in cannon:GetDescendants() do
		if d:IsA("BasePart") and d.Name == name then
			return d
		end
	end
	return nil
end

local raft = workspace:FindFirstChild("Raft")
local raftLocalCF = cannon:GetAttribute("RaftLocalCF")
if raft and raft.PrimaryPart and typeof(raftLocalCF) == "CFrame" then
	cannon:PivotTo(raft.PrimaryPart.CFrame:ToWorldSpace(raftLocalCF))
end

local main = findPartNamed("Main")
local baseplate = findPartNamed("Baseplate")

if raft and raft.PrimaryPart and not cannon:GetAttribute("Welded") then
	local primary = raft.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity

	for _, part in cannon:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	for _, part in cannon:GetDescendants() do
		if part:IsA("BasePart") and part ~= main then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = primary
			weld.Parent = part
		end
	end

	if main then
		local anchorPart = baseplate or primary
		local recoilWeld = Instance.new("Weld")
		recoilWeld.Name = "RecoilWeld"
		recoilWeld.Part0 = anchorPart
		recoilWeld.Part1 = main
		recoilWeld.C0 = anchorPart.CFrame:ToObjectSpace(main.CFrame)
		recoilWeld.Parent = main
	end

	for _, part in cannon:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	primary.AssemblyLinearVelocity = linVel
	primary.AssemblyAngularVelocity = angVel

	cannon:SetAttribute("Welded", true)
end
