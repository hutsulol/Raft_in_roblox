-- PaddleController.client.lua
-- Detects when the player uses the Paddle tool and sends the paddle
-- direction to the server so the raft can be steered.
--
-- Validation rules (added on player request — paddle no longer works
-- standing on dry land or aiming at planks/walls/decoration):
--   • The mouse target must be terrain water. We raycast from the
--     mouse with IgnoreWater=false; the hit must come back as
--     Material.Water.
--   • The player has to be facing the water — the cursor target must
--     be in front of the character, not directly behind, otherwise
--     the paddle stroke is rejected. "In front" = forward dot the
--     vector toward the click point is positive.
--
-- These rules are enforced by toggling Tool.Enabled every frame based
-- on the live validation result. When Tool.Enabled is false the click
-- doesn't fire Activated on either the client OR the server — which
-- means the in-Tool Script never plays the row animation / sound, the
-- raft never gets a PaddleAction, and the cooldown isn't even started.
-- That's the "everything is gated together" behaviour the user asked
-- for, instead of the previous "animation plays but boat doesn't move"
-- inconsistency.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local COOLDOWN = 1.0 -- seconds between paddle strokes
-- Maximum stud distance from the character to the water hit point.
-- Without this the paddle would still register valid as long as the
-- cursor was over water somewhere — the player could stand in the
-- middle of the raft and still "paddle" the edge from far away.
-- Tightened so the player has to actually be near the water's edge.
local MAX_REACH = 6
local lastPaddleTime = 0
local currentTool = nil

local waterRayParams = RaycastParams.new()
waterRayParams.FilterType = Enum.RaycastFilterType.Exclude
waterRayParams.IgnoreWater = false

local function getCharacterFilter()
	local char = player.Character
	if char then return {char} end
	return {}
end

-- Returns true iff the cursor is currently hovering terrain water AND
-- the character is facing it. Used both by the live Tool.Enabled gate
-- and by the on-Activated re-check.
local function canPaddleNow()
	if not currentTool or currentTool.Name ~= "Paddle" then return false end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return false end

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	waterRayParams.FilterDescendantsInstances = getCharacterFilter()
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, waterRayParams)
	if not result then return false end
	if result.Material ~= Enum.Material.Water then return false end

	local hitPoint = result.Position
	local toClick = Vector3.new(hitPoint.X - hrp.Position.X, 0, hitPoint.Z - hrp.Position.Z)
	if toClick.Magnitude < 1 then return false end
	-- Reach gate: the water point must be within arm's length of the
	-- character. Standing in the middle of the raft and clicking a
	-- distant patch of ocean should NOT count as a valid paddle.
	if toClick.Magnitude > MAX_REACH then return false end
	local forward = hrp.CFrame.LookVector
	local flatForward = Vector3.new(forward.X, 0, forward.Z)
	if flatForward.Magnitude < 0.01 then return false end
	if flatForward.Unit:Dot(toClick.Unit) <= 0.2 then return false end

	return true, hitPoint
end

local function onActivated()
	-- Tool.Enabled gate already filtered out invalid clicks at the
	-- Roblox level, but re-validate here in case the gate flickered
	-- between the click frame and Activated dispatch.
	local ok, hitPoint = canPaddleNow()
	if not ok or not hitPoint then return end

	local now = tick()
	if now - lastPaddleTime < COOLDOWN then return end

	local paddleEvent = ReplicatedStorage:FindFirstChild("PaddleAction")
	if not paddleEvent then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end
	local raftPos = raft.PrimaryPart.Position
	local direction = Vector3.new(hitPoint.X - raftPos.X, 0, hitPoint.Z - raftPos.Z)
	if direction.Magnitude < 1 then return end
	direction = direction.Unit

	lastPaddleTime = now
	paddleEvent:FireServer(direction)
end

-- Per-frame: keep Tool.Enabled in sync with the validation. During
-- the post-stroke cooldown we also keep it disabled so the player
-- can't spam the swing animation while the boost is still decaying.
RunService.RenderStepped:Connect(function()
	if not currentTool or currentTool.Name ~= "Paddle" then return end
	if not currentTool.Parent then return end

	local inCooldown = (tick() - lastPaddleTime) < COOLDOWN
	local shouldEnable = (not inCooldown) and canPaddleNow()
	if currentTool.Enabled ~= shouldEnable then
		currentTool.Enabled = shouldEnable
	end
end)

local function setupTool(tool)
	if tool.Name ~= "Paddle" then return end
	currentTool = tool
	tool.Activated:Connect(onActivated)
end

local function onCharacter(char)
	if not char then return end

	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			setupTool(child)
		end
	end)

	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child == currentTool then
			currentTool = nil
		end
	end)

	for _, child in char:GetChildren() do
		if child:IsA("Tool") then
			setupTool(child)
		end
	end
end

if player.Character then onCharacter(player.Character) end
player.CharacterAdded:Connect(onCharacter)
