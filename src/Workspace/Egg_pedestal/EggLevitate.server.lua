-- EggLevitate.server.lua  (inside Workspace.Egg_pedestal)
-- Levitates ONLY the egg. The egg is detached from the raft assembly and
-- anchored (so it never jitters the raft / never drags the pedestal), then a
-- script keeps it glued above the pedestal each frame + a bob, so it rides the
-- floating raft. We only READ the pedestal's position — we never modify the
-- pedestal (no parts, no welds, no tags), so it can't glow/disappear from us.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local model = script.Parent
local egg = model:WaitForChild("egg")

if egg:IsA("Model") and not egg.PrimaryPart then
	local p = egg:FindFirstChildWhichIsA("BasePart", true)
	if p then egg.PrimaryPart = p end
end

-- The pedestal is now its own top-level model; use it as the follow target.
local pedestal = workspace:WaitForChild("pedestal")
local pedPart = (pedestal:IsA("BasePart") and pedestal) or pedestal.PrimaryPart or pedestal:FindFirstChildWhichIsA("BasePart", true)
local eggPart = (egg:IsA("BasePart") and egg) or egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart", true)
if not pedPart or not eggPart then return end

-- Detach ONLY the egg from everything else, so anchoring it can't freeze the
-- raft (an anchored part welded into the raft assembly freezes the whole raft).
-- Scan the WHOLE workspace: the egg's weld may be parented anywhere (e.g. inside
-- the now-separate pedestal model), so a narrow search would miss it. We only
-- remove welds with exactly one side in the egg — raft/pedestal welds are kept.
local function inEgg(p) return p ~= nil and (p == egg or p:IsDescendantOf(egg)) end
local removed = 0
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") then
		local a, b = d.Part0, d.Part1
		if (inEgg(a) and not inEgg(b)) or (inEgg(b) and not inEgg(a)) then
			d:Destroy()
			removed += 1
		end
	end
end
print(string.format("[EggLevitate] detached egg from world: removed %d weld(s)", removed))

-- Anchored + driven by PivotTo every frame, so collision MUST be off or the
-- moving egg shoves the player off the raft. It's decorative — no collision.
for _, d in ipairs(egg:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Anchored = true
		d.CanCollide = false
	end
end
if egg:IsA("BasePart") then
	egg.Anchored = true
	egg.CanCollide = false
end

-- Rest pose of the egg relative to the pedestal (which floats with the raft).
local relCF = pedPart.CFrame:ToObjectSpace(egg:GetPivot())

local DIP, AMP = 0.5, 0.7
local nv = Instance.new("NumberValue")
nv.Name = "BobDriver"
nv.Value = 0
nv.Parent = script
local dip = TweenService:Create(nv, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Value = -DIP })
dip.Completed:Connect(function()
	TweenService:Create(nv, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Value = -DIP + AMP }):Play()
end)
dip:Play()

RunService.Heartbeat:Connect(function()
	if not eggPart.Parent or not pedPart.Parent then return end
	egg:PivotTo((pedPart.CFrame * relCF) + Vector3.new(0, nv.Value, 0))
end)
