-- RadiationSystem: ensures RadiationUpdate RemoteEvent exists
-- Main radiation logic is handled by WaterDamage.server.lua
local rs = game:GetService("ReplicatedStorage")

local radiationEvent = rs:FindFirstChild("RadiationUpdate")
if not radiationEvent then
	radiationEvent = Instance.new("RemoteEvent")
	radiationEvent.Name = "RadiationUpdate"
	radiationEvent.Parent = rs
end
