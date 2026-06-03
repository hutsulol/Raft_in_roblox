-- InfectedMilitarySpawner.server.lua
-- Periodically spawns one "Infected Military" hostile NPC near the
-- player raft. Kept intentionally simple (no boarding raft, no
-- approach driver) — the goal is to give the recruitment system a
-- second NPC type to filter on. Behaviour beyond spawning is
-- inherited from the rig's existing scripts (ZombieScript, etc.).

local rs                = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local TEMPLATE_NAME      = "Infected Military"
local SPAWN_INTERVAL     = 240
local FIRST_SPAWN_DELAY  = 60
local SPAWN_RADIUS       = 28

local function getBoat()
	return workspace:FindFirstChild("Raft")
end

local function spawnGuard()
	local template = rs:FindFirstChild(TEMPLATE_NAME)
	if not template then
		-- Template missing in this build — quietly skip rather than spam.
		return
	end

	local boat = getBoat()
	if not boat or not boat.PrimaryPart then return end

	local angle = math.random() * math.pi * 2
	local pos = boat.PrimaryPart.Position
		+ Vector3.new(math.cos(angle) * SPAWN_RADIUS, 4, math.sin(angle) * SPAWN_RADIUS)

	local guard = template:Clone()
	guard:PivotTo(CFrame.new(pos))
	CollectionService:AddTag(guard, "HostilePirate")
	-- Drives recruitment / blood / mercenary filtering — see NpcTypes.
	guard:SetAttribute("NpcType", "Infected Military")
	guard.Parent = workspace
end

task.wait(FIRST_SPAWN_DELAY)
spawnGuard()

while true do
	task.wait(SPAWN_INTERVAL)
	spawnGuard()
end
