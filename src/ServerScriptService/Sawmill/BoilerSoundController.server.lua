-- BoilerSoundController
-- Lives inside the sawmill model as a child of the "Boiler" part.
-- Sets BoilerSound.Volume = 0.5 while the sawmill is processing,
-- and 0 when idle.

local IDLE_VOLUME = 0
local ACTIVE_VOLUME = 0.5

local boiler = script.Parent
local sound = boiler:WaitForChild("BoilerSound")

-- Walk up to find the sawmill model (the one carrying the SawmillState attribute
-- or tagged "Sawmill").
local CollectionService = game:GetService("CollectionService")
local sawmill = boiler
while sawmill do
	if sawmill:GetAttribute("SawmillState") ~= nil or CollectionService:HasTag(sawmill, "Sawmill") then
		break
	end
	sawmill = sawmill.Parent
end
if not sawmill then
	sawmill = boiler.Parent
end

sound.Looped = true
sound.PlayOnRemove = false

local function apply()
	local state = sawmill:GetAttribute("SawmillState")
	if state == "processing" then
		sound.Volume = ACTIVE_VOLUME
		if not sound.Playing then
			sound:Play()
		end
	else
		sound.Volume = IDLE_VOLUME
		sound:Stop()
	end
end

apply()

sawmill:GetAttributeChangedSignal("SawmillState"):Connect(apply)
