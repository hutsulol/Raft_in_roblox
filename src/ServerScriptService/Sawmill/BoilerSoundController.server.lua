-- BoilerSoundController
-- Lives inside the sawmill model as a child of the "Boiler" part.
-- Controls all sawmill sounds (BoilerSound, SawSound):
--   processing -> Volume = active value, Playing
--   idle       -> Volume = 0, Stopped

local CollectionService = game:GetService("CollectionService")

-- Sound name -> volume while sawmill is processing
local SOUND_VOLUMES = {
	BoilerSound = 0.5,
	SawSound = 1,
}

local boiler = script.Parent

-- Walk up to find the sawmill model.
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

local function collectSounds()
	local sounds = {}
	for _, desc in sawmill:GetDescendants() do
		if desc:IsA("Sound") and SOUND_VOLUMES[desc.Name] then
			table.insert(sounds, desc)
		end
	end
	return sounds
end

local function apply()
	local processing = sawmill:GetAttribute("SawmillState") == "processing"
	for _, sound in collectSounds() do
		sound.Looped = true
		sound.PlayOnRemove = false
		if processing then
			sound.Volume = SOUND_VOLUMES[sound.Name]
			if not sound.Playing then
				sound:Play()
			end
		else
			sound.Volume = 0
			sound:Stop()
		end
	end
end

apply()

sawmill:GetAttributeChangedSignal("SawmillState"):Connect(apply)

-- Re-apply if a relevant sound is added later
sawmill.DescendantAdded:Connect(function(desc)
	if desc:IsA("Sound") and SOUND_VOLUMES[desc.Name] then
		apply()
	end
end)
