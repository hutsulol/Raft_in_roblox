local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local COOLDOWN = 3
local lastFire = -1e9

local function fire(count)
	local now = os.clock()
	if now - lastFire < COOLDOWN then return end
	lastFire = now
	if typeof(_G.PlayCoinRain) == "function" then
		_G.PlayCoinRain(count or 20)
	end
end

local function findCount(container)
	if not container then return nil end
	for _, d in container:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and typeof(d.Text) == "string" then
			local n = string.match(d.Text, "онет[^%d]*(%d+)")
			if n then return tonumber(n) end
		end
	end
	return nil
end

playerGui.DescendantAdded:Connect(function(inst)
	if not (inst:IsA("TextLabel") or inst:IsA("TextButton")) then return end

	local function handle()
		if not inst.Parent then return false end
		if typeof(inst.Text) ~= "string" or not string.find(inst.Text, "сьминог") then
			return false
		end
		fire(findCount(inst.Parent))
		return true
	end

	task.defer(function()
		if handle() then return end
		task.wait(0.15)
		handle()
	end)
end)
