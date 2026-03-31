local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = {}

local remoteEvents = {
	"UpdateHunger",
	"UpdateThirst",
	"EatGrapes",
	"CraftBush",
}

for _, name in ipairs(remoteEvents) do
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then
		remotes[name] = existing
	else
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = ReplicatedStorage
		remotes[name] = remote
	end
end

return remotes
