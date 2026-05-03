-- InfectedMilitaryRigPatch.server.lua
-- Applies the gameplay parameters the design demands to every
-- Infected Military rig in the world, regardless of how the rig
-- entered (manual placement, spawner clone, Respawn re-parent).
--
-- This file lives in ServerScriptService so it always reaches the
-- game even when Rojo can't overwrite scripts baked inside the rig
-- (e.g. the rig already ships with a script named "NPC AI" with a
-- space, which Rojo can't address from a `NpcAi.script` source file).
--
-- Patches applied per rig:
--   • NpcType attribute + HostilePirate tag → recruitment client /
--     server can resolve the rig and the recruit hint can fire.
--   • Humanoid MaxHealth = 1 + bar/name display turned off → the
--     rig is killable in one hit and doesn't show a stray HP bar.
--   • Internal "NPC AI" / "NpcAi" Scripts disabled → no AK-47
--     bullets, no damage to the player.
--
-- Adding a second rig type would mean either repeating this pattern
-- or generalising the matcher to walk NpcTypes — kept narrow on
-- purpose so accidental matches against unrelated models (the
-- player rig, decor, etc.) cannot strip their AI scripts.

local CollectionService = game:GetService("CollectionService")

local TYPE_ID = "Infected Military"
local NAME_ALIASES = {
	["Infected Military"]  = true,
	["Infected_Military"]  = true,
}

local function isInfectedMilitaryRig(inst)
	if not inst:IsA("Model") then return false end
	if inst:GetAttribute("NpcType") == TYPE_ID then return true end
	if NAME_ALIASES[inst.Name] then return true end
	return false
end

local function patchRig(rig)
	if rig:GetAttribute("InfectedMilitaryPatched") then return end
	rig:SetAttribute("InfectedMilitaryPatched", true)

	-- Recruitment plumbing.
	rig:SetAttribute("NpcType", TYPE_ID)
	if not CollectionService:HasTag(rig, "HostilePirate") then
		CollectionService:AddTag(rig, "HostilePirate")
	end

	-- HP and bar.
	local hum = rig:FindFirstChildWhichIsA("Humanoid")
	if hum then
		hum.MaxHealth = 1
		hum.Health    = 1
		hum.HealthDisplayType    = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.DisplayDistanceType  = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayDistance = 0
		hum.NameDisplayDistance   = 0
	end

	-- Disable damage-producing AI scripts. The rbxl ships with a
	-- Script named "NPC AI" (space) that fires AK-47 bullets dealing
	-- random 10–50 damage; matching by both spellings covers the
	-- Studio name and any Rojo-synced sibling.
	for _, child in rig:GetChildren() do
		if (child:IsA("Script") or child:IsA("LocalScript"))
			and (child.Name == "NPC AI" or child.Name == "NpcAi") then
			child.Disabled = true
		end
	end
end

local function tryPatch(inst)
	if isInfectedMilitaryRig(inst) then
		-- task.defer so the rig has a tick to assemble its children
		-- (Humanoid, scripts) before we look for them.
		task.defer(patchRig, inst)
	end
end

for _, d in workspace:GetDescendants() do tryPatch(d) end
workspace.DescendantAdded:Connect(tryPatch)
