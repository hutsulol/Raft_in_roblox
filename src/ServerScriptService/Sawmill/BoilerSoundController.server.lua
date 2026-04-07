-- BoilerSoundController
-- Lives in its own folder so it only handles sawmill BoilerSound playback.
-- Watches every sawmill's SawmillState attribute (set by SawmillSystem.server.lua)
-- and plays the BoilerSound only while the sawmill is processing.

local CollectionService = game:GetService("CollectionService")

local function findBoilerSound(sawmill)
	for _, desc in sawmill:GetDescendants() do
		if desc:IsA("Sound") and desc.Name == "BoilerSound" then
			return desc
		end
	end
	return nil
end

local function applyState(sawmill, sound)
	local state = sawmill:GetAttribute("SawmillState")
	if state == "processing" then
		if not sound.Playing then
			sound.Looped = true
			sound:Play()
		end
	else
		if sound.Playing then
			sound:Stop()
		end
	end
end

local function setupSawmill(sawmill)
	-- Wait for the BoilerSound to be present (model may still be loading)
	local sound = findBoilerSound(sawmill)
	if not sound then
		local conn
		conn = sawmill.DescendantAdded:Connect(function(desc)
			if desc:IsA("Sound") and desc.Name == "BoilerSound" then
				conn:Disconnect()
				setupSawmill(sawmill)
			end
		end)
		return
	end

	-- Force sound off until processing begins
	sound.Looped = true
	sound.PlayOnRemove = false
	sound:Stop()

	applyState(sawmill, sound)

	sawmill:GetAttributeChangedSignal("SawmillState"):Connect(function()
		if sound.Parent then
			applyState(sawmill, sound)
		end
	end)
end

for _, sawmill in CollectionService:GetTagged("Sawmill") do
	task.spawn(setupSawmill, sawmill)
end

CollectionService:GetInstanceAddedSignal("Sawmill"):Connect(function(sawmill)
	task.spawn(setupSawmill, sawmill)
end)
