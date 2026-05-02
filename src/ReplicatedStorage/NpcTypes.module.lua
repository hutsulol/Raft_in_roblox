-- NpcTypes.module.lua
-- Central registry for recruitable hostile NPC types.
--
-- Each entry maps the spawned model's identifier (its template Name) to:
--   • mercName    : the StringValue placed in player.Mercenaries when recruited
--   • bloodType   : the BloodType attribute stamped on collected FullCapsules
--   • bloodLabel  : human-readable label shown in the inventory tooltip
--   • displayName : title shown in the recruitment / dialogue UI
--   • dialogueId  : key into the per-NPC dialogue catalog (RecruitmentSystem.client)
--
-- Adding a new recruitable enemy is a one-entry change here plus a model
-- template under ReplicatedStorage. Recruitment, blood capsules and the
-- mercenary phone menu all read from this table — no other file needs
-- a hardcoded NPC name.

local NpcTypes = {}

NpcTypes.Types = {
	["Pirate lvl1"] = {
		mercName    = "Pirate lvl1",
		bloodType   = "Pirate lvl1",
		bloodLabel  = "Pirate Blood",
		displayName = "Pirate",
		dialogueId  = "pirate",
	},
	["SCP Guard Killer"] = {
		mercName    = "SCP Guard Killer",
		bloodType   = "SCP Guard Killer",
		bloodLabel  = "SCP Guard Blood",
		displayName = "SCP Guard Killer",
		dialogueId  = "scp_guard",
	},
}

-- Resolve an NPC type by its NpcType attribute (preferred) or, as a
-- fallback for legacy spawns, by its Model.Name. Returns nil when the
-- model is not a registered recruitable.
function NpcTypes.resolve(model)
	if typeof(model) ~= "Instance" then return nil end
	local id = model:GetAttribute("NpcType")
	if id and NpcTypes.Types[id] then return NpcTypes.Types[id] end
	if NpcTypes.Types[model.Name] then return NpcTypes.Types[model.Name] end
	return nil
end

-- Lookup by blood type tag (used by inventory display and DNA matching).
function NpcTypes.byBloodType(bloodType)
	if typeof(bloodType) ~= "string" then return nil end
	for _, info in pairs(NpcTypes.Types) do
		if info.bloodType == bloodType then return info end
	end
	return nil
end

return NpcTypes
