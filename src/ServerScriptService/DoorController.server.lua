-- DoorController.server.lua
-- Centralized setup for placed Door_Wood models.
--
-- Exposes _G.SetupDoor(doorModel, raft). The stock Studio door template
-- ships with a Script that tweens `hinge.CFrame` directly, but two things
-- break once the door is welded into the raft's moving assembly:
--   1. The open-goal CFrame is captured in world space at script load and
--      goes stale as the raft drifts.
--   2. Tweening a weld-constrained part forces the physics engine to
--      re-solve the whole raft every step — ~0.5s server freeze per click.
--
-- Neither Motor6D-with-C0-tween nor HingeConstraint-with-Motor kept the
-- swinging Base attached to the raft: the joint systems' soft physics let
-- Base drift away as the raft moved. Instead, we use a kinematic follower:
--   * Doorframe (including Hinge) is rigidly WeldConstraint'd to the raft
--     and unanchored — follows the raft through normal physics.
--   * Base stays ANCHORED. Every Heartbeat we set
--       base.CFrame = hinge.CFrame * CFrame.Angles(0, angle, 0) * offset
--     where `offset` is the original closed-position transform from hinge
--     to base. The hinge's CFrame is already kept up-to-date by the weld,
--     so this formula pins Base to the raft while letting us rotate it
--     around the hinge's Y axis by any angle.
--   * A NumberValue holds the current angle; TweenService interpolates it
--     when the ProximityPrompt fires.

local RunService = game:GetService("RunService")
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

	-- Weld the Doorframe (walls, lintel, hinge pivot) rigidly to the raft.
	if doorframe:IsA("BasePart") then
		weldPart(doorframe, raft.PrimaryPart)
	end
	for _, desc in doorframe:GetDescendants() do
		if desc:IsA("BasePart") then
			weldPart(desc, raft.PrimaryPart)
		end
	end

	-- Weld Base's children (handles, prompt parts, etc.) to Base so they
	-- move with it — but they need to stay anchored along with Base.
	for _, desc in base:GetDescendants() do
		if desc:IsA("BasePart") then
			weldPart(desc, base)
		end
	end

	-- Unanchor the Doorframe so it physically follows the raft via the welds.
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

	-- Base stays anchored — we drive its CFrame kinematically each frame.
	base.Anchored = true
	for _, desc in base:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
		end
	end

	-- Closed-position offset from hinge to base, captured in hinge's local
	-- frame. Rotating the offset around Y before applying it gives us the
	-- swung position.
	local hingeToBaseOffset = hinge.CFrame:ToObjectSpace(base.CFrame)

	-- Angle state is a NumberValue so TweenService can interpolate it.
	local angleValue = Instance.new("NumberValue")
	angleValue.Name = "DoorAngle"
	angleValue.Value = 0
	angleValue.Parent = doorModel

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not doorModel.Parent or not hinge.Parent or not base.Parent then
			if conn then conn:Disconnect(); conn = nil end
			return
		end
		local rot = CFrame.Angles(0, angleValue.Value, 0)
		base.CFrame = hinge.CFrame * rot * hingeToBaseOffset
	end)

	doorModel.AncestryChanged:Connect(function(_, parent)
		if not parent and conn then
			conn:Disconnect()
			conn = nil
		end
	end)

	-- Wire the ProximityPrompt. Tween the angle NumberValue; the Heartbeat
	-- updater picks up the new value and applies it to Base.
	local prompt = base:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then return end

	prompt.ActionText = "Open"
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	prompt.Triggered:Connect(function()
		local target
		if prompt.ActionText == "Close" then
			target = 0
			prompt.ActionText = "Open"
		else
			target = math.rad(90)
			prompt.ActionText = "Close"
		end
		TweenService:Create(angleValue, tweenInfo, {Value = target}):Play()
	end)
end

_G.SetupDoor = setupDoor
