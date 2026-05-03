-- DoorController.server.lua
-- Centralized setup for placed Door_Wood models.
--
-- Exposes _G.SetupDoor(doorModel, raft). The stock Studio door template
-- ships with a Script that tweens `hinge.CFrame` directly, which breaks on
-- our moving raft in two ways:
--   1. The "open" goal CFrame is captured in world space at script load and
--      goes stale as the raft drifts, so opening the door warps it back
--      toward the original spawn spot.
--   2. Tweening a weld-constrained part's CFrame forces the physics engine
--      to re-solve the whole raft assembly every step — ~0.5s server freeze.
--
-- The fix, modelled on SawmillSystem's spinning parts which already work
-- correctly on the moving raft:
--   * destroy the template's baked-in script
--   * WeldConstraint Doorframe (and every BasePart inside it, including the
--     Hinge pivot) rigidly to raft.PrimaryPart — puts the frame in the
--     raft's rigid assembly
--   * create a Motor6D(Part0 = raft.PrimaryPart, Part1 = Base) with C0/C1
--     set up so the joint's pivot lies exactly at the Hinge. This is the
--     critical bit: a Motor6D pulls Part1 into the same physics assembly
--     as Part0, so Base inherits the raft's motion automatically — no
--     manual CFrame follower, no joint drift.
--   * tween motor.Transform (NOT motor.C0) to swing the door. Tweening
--     Transform is a pose-level operation; it does not rebuild the
--     assembly each step the way tweening C0 does.
--
-- Both previous attempts at Motor6D drove the swing by retargeting C0,
-- which is what made them slow and drifty. Transform doesn't have those
-- problems — it's exactly what Roblox's own animation system uses to
-- drive character joints on moving platforms.

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

	local raftPart = raft.PrimaryPart

	-- Kill the template's static-world tween script.
	for _, desc in doorModel:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end

	-- Weld the Doorframe (walls, lintel, Hinge pivot) rigidly to the raft.
	if doorframe:IsA("BasePart") then
		weldPart(doorframe, raftPart)
	end
	for _, desc in doorframe:GetDescendants() do
		if desc:IsA("BasePart") then
			weldPart(desc, raftPart)
		end
	end

	-- Decorative children of Base (handles, prompt parts, etc.) weld to
	-- Base so they swing with the panel.
	for _, desc in base:GetDescendants() do
		if desc:IsA("BasePart") then
			weldPart(desc, base)
		end
	end

	-- Motor6D joining Base into the raft assembly. The pivot sits at the
	-- Hinge's world position:
	--
	--   Motor6D formula:  Part1 = Part0 * C0 * Transform * C1:Inverse()
	--
	-- We want Part0 * C0 to equal hinge.CFrame (so the joint's rotation
	-- axis passes through the hinge), which means
	--   C0 = raftPart⁻¹ · hinge
	-- Then at Transform = Identity we want Part1 = base.CFrame, so
	--   hinge * C1:Inverse() = base   ⇒   C1 = base⁻¹ · hinge
	-- With these choices, setting Transform = CFrame.Angles(0, angle, 0)
	-- swings Base around the hinge's world Y axis by `angle` radians.
	local hingeInRaft = raftPart.CFrame:Inverse() * hinge.CFrame
	local hingeInBase = base.CFrame:Inverse() * hinge.CFrame

	local motor = Instance.new("Motor6D")
	motor.Name = "DoorHinge"
	motor.Part0 = raftPart
	motor.Part1 = base
	motor.C0 = hingeInRaft
	motor.C1 = hingeInBase
	motor.Transform = CFrame.new()
	motor.Parent = raftPart

	-- Unanchor every part so the whole door is simulated as part of the
	-- raft's assembly. Pin network ownership to the server to match how
	-- the rest of the build system handles placed parts.
	if doorframe:IsA("BasePart") then
		doorframe.Anchored = false
		pcall(function() doorframe:SetNetworkOwner(nil) end)
	end
	for _, desc in doorframe:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			pcall(function() desc:SetNetworkOwner(nil) end)
		end
	end
	base.Anchored = false
	pcall(function() base:SetNetworkOwner(nil) end)
	for _, desc in base:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			pcall(function() desc:SetNetworkOwner(nil) end)
		end
	end

	-- Wire the ProximityPrompt. Tween the motor's Transform between the
	-- closed (Identity) and open (±90° around Y) poses.
	local prompt = base:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then return end
	prompt.ActionText = "Open"
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local closedCF = CFrame.new()
	local openCF = CFrame.Angles(0, math.rad(90), 0)

	prompt.Triggered:Connect(function()
		local target
		if prompt.ActionText == "Close" then
			target = closedCF
			prompt.ActionText = "Open"
		else
			target = openCF
			prompt.ActionText = "Close"
		end
		TweenService:Create(motor, tweenInfo, {Transform = target}):Play()
	end)
end

_G.SetupDoor = setupDoor
