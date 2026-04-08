-- DoorController.server.lua
-- Centralized setup + open/close animation for placed Door_Wood models.
--
-- Exposes _G.SetupDoor(doorModel, raft), which BuildingSystem and
-- RaftSaveSystem call instead of the standard "weld every part to the raft"
-- routine. The stock Studio door template ships with a Script that tweens
-- `hinge.CFrame` using world coordinates captured at script-load time. Two
-- things break when that runs on our moving raft:
--
--   1. The "open" goal CFrame is frozen in world space, so as soon as the
--      raft drifts, playing the tween warps the door back toward the old
--      origin.
--   2. Our build system welds the hinge (and every other part) rigidly to
--      the raft's PrimaryPart. Tweening a weld-constrained part's CFrame
--      forces the physics engine to re-solve the whole raft assembly every
--      step of the tween, producing a ~half-second server freeze.
--
-- Instead, we:
--   * destroy the baked-in script
--   * weld the Doorframe (everything except the swinging panel) to the raft
--   * create a Motor6D between Hinge and Base so the panel pivots about the
--     hinge's world position — this is a relative, kinematic joint and does
--     not fight the assembly
--   * tween the Motor6D's C0 on prompt triggers

local TweenService = game:GetService("TweenService")

local function weldPart(part, target)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part
	w.Part1 = target
	w.Parent = part
end

local function setupDoor(doorModel, raft)
	if not doorModel or not raft or not raft.PrimaryPart then return end

	local doorframe = doorModel:FindFirstChild("Doorframe")
	local base = doorModel:FindFirstChild("Base")
	if not (doorframe and base) then
		warn("[DoorController] Missing Doorframe or Base under " .. doorModel:GetFullName())
		return
	end
	local hinge = doorframe:FindFirstChild("Hinge")
	if not hinge or not hinge:IsA("BasePart") then
		warn("[DoorController] Missing Doorframe.Hinge BasePart under " .. doorModel:GetFullName())
		return
	end
	if not base:IsA("BasePart") then
		warn("[DoorController] Base must be a BasePart under " .. doorModel:GetFullName())
		return
	end

	-- Replace the template's static-world tween script.
	for _, desc in doorModel:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end

	-- Weld the doorframe (and every BasePart inside it — walls, lintel,
	-- hinge pivot) rigidly to the raft.
	if doorframe:IsA("BasePart") then
		weldPart(doorframe, raft.PrimaryPart)
	end
	for _, desc in doorframe:GetDescendants() do
		if desc:IsA("BasePart") then
			weldPart(desc, raft.PrimaryPart)
		end
	end

	-- Make the swinging Base a rigid sub-assembly: any decorative children
	-- (handles, invisible prompt parts) weld to Base itself so they rotate
	-- with it rather than staying frozen to the raft.
	for _, desc in base:GetDescendants() do
		if desc:IsA("BasePart") then
			weldPart(desc, base)
		end
	end

	-- Motor6D pivoting Base around the hinge's world position.
	--
	--   Part1.CFrame = Part0.CFrame * C0 * C1:Inverse()
	--
	-- We want the shared joint frame to sit at the hinge's world pose, so in
	-- Hinge's local space C0 is identity and in Base's local space C1 is the
	-- hinge expressed relative to the base. Rotating C0 then rotates Base
	-- about the hinge's Y axis.
	local motor = Instance.new("Motor6D")
	motor.Name = "DoorMotor"
	motor.Part0 = hinge
	motor.Part1 = base
	motor.C0 = CFrame.new()
	motor.C1 = base.CFrame:ToObjectSpace(hinge.CFrame)
	motor.Parent = hinge

	-- Unanchor everything; the weld network + motor hold the assembly.
	for _, desc in doorModel:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			pcall(function() desc:SetNetworkOwner(nil) end)
		end
	end

	-- Wire the ProximityPrompt. We tween the motor's C0, not the hinge's
	-- world CFrame, so this is cheap and frame-rate-safe.
	local prompt = base:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then return end

	local closedC0 = motor.C0
	local openC0 = closedC0 * CFrame.Angles(0, math.rad(90), 0)
	local tweenInfo = TweenInfo.new(0.5)

	prompt.ActionText = "Open"
	prompt.Triggered:Connect(function()
		if prompt.ActionText == "Close" then
			TweenService:Create(motor, tweenInfo, {C0 = closedC0}):Play()
			prompt.ActionText = "Open"
		else
			TweenService:Create(motor, tweenInfo, {C0 = openC0}):Play()
			prompt.ActionText = "Close"
		end
	end)
end

_G.SetupDoor = setupDoor
