local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")

local DAMAGE_PERCENT = 0.10  -- 10% of max health per second
local CHECK_INTERVAL = 1
local SPAWN_IMMUNITY = 5     -- seconds of immunity after spawning
local WATER_GRACE = 2        -- seconds in water before damage starts
local MAX_VIGNETTE_TIME = 10 -- seconds in water for max vignette intensity

local vignetteEvent = rs:FindFirstChild("WaterVignette")
if not vignetteEvent then
	vignetteEvent = Instance.new("RemoteEvent")
	vignetteEvent.Name = "WaterVignette"
	vignetteEvent.Parent = rs
end

local spawnTimes = {}  -- player -> time they spawned/respawned
local waterTimes = {}  -- humanoid -> time they entered water

Players.PlayerAdded:Connect(function(player)
	spawnTimes[player] = tick()
	player.CharacterAdded:Connect(function()
		spawnTimes[player] = tick()
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	spawnTimes[player] = nil
end)

-- Initialize for players already in game
for _, player in Players:GetPlayers() do
	spawnTimes[player] = tick()
	player.CharacterAdded:Connect(function()
		spawnTimes[player] = tick()
	end)
end

local function isOverWater(rootPart)
	local rayOrigin = rootPart.Position
	local rayDirection = Vector3.new(0, -20, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {rootPart.Parent}

	local result = workspace:Raycast(rayOrigin, rayDirection, params)
	if result and result.Instance then
		if result.Instance:IsA("Terrain") then
			return true
		end
		return false
	end

	return true
end

local function damageHumanoid(humanoid, rootPart, player)
	if not humanoid or humanoid.Health <= 0 then return end
	if not rootPart then return end

	-- Spawn immunity for players
	if player and spawnTimes[player] then
		if tick() - spawnTimes[player] < SPAWN_IMMUNITY then
			return
		end
	end

	if isOverWater(rootPart) then
		-- Track when they first entered water
		if not waterTimes[humanoid] then
			waterTimes[humanoid] = tick()
		end
		-- Only damage after grace period
		if tick() - waterTimes[humanoid] >= WATER_GRACE then
			local damage = humanoid.MaxHealth * DAMAGE_PERCENT
			humanoid:TakeDamage(damage)
		end
	else
		-- Back on solid ground, reset water timer
		waterTimes[humanoid] = nil
	end
end

while true do
	task.wait(CHECK_INTERVAL)

	-- Damage players in water and send vignette intensity
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			local hum = char:FindFirstChildWhichIsA("Humanoid")
			local hrp = char:FindFirstChild("HumanoidRootPart")
			damageHumanoid(hum, hrp, player)

			-- Send vignette intensity based on time in water
			local intensity = 0
			if hum and waterTimes[hum] then
				local timeInWater = tick() - waterTimes[hum]
				intensity = math.clamp(timeInWater / MAX_VIGNETTE_TIME, 0, 1)
			end
			vignetteEvent:FireClient(player, intensity)
		end
	end

	-- Damage NPCs in water
	for _, obj in workspace:GetChildren() do
		if obj:IsA("Model") and not Players:GetPlayerFromCharacter(obj) then
			local hum = obj:FindFirstChildWhichIsA("Humanoid")
			if hum then
				local hrp = obj:FindFirstChild("HumanoidRootPart")
				damageHumanoid(hum, hrp, nil)
			end
		end
	end
end
