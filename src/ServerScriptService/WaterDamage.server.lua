local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")

local DAMAGE_PERCENT = 0.10  -- 10% of max health per second
local CHECK_INTERVAL = 1
local SPAWN_IMMUNITY = 5     -- seconds of immunity after spawning
local WATER_GRACE = 2        -- seconds in water before damage starts
local MAX_VIGNETTE_TIME = 10 -- seconds in water for max vignette intensity
local RADIATION_HIT_THRESHOLD = 3
local RADIATION_DURATION = 60

local vignetteEvent = rs:FindFirstChild("WaterVignette")
if not vignetteEvent then
	vignetteEvent = Instance.new("RemoteEvent")
	vignetteEvent.Name = "WaterVignette"
	vignetteEvent.Parent = rs
end

-- Create the RadiationUpdate RemoteEvent here so it definitely exists
local radiationEvent = rs:FindFirstChild("RadiationUpdate")
if not radiationEvent then
	radiationEvent = Instance.new("RemoteEvent")
	radiationEvent.Name = "RadiationUpdate"
	radiationEvent.Parent = rs
end

local spawnTimes = {}  -- player -> time they spawned/respawned
local waterTimes = {}  -- humanoid -> time they entered water
local waterHitCounts = {} -- player -> number of ocean damage ticks
local radiationData = {} -- player -> { active, endTime }

-- ─── Apply radiation sickness directly ───
local function applyRadiation(player)
	if radiationData[player] and radiationData[player].active then
		-- Already sick — reset timer
		radiationData[player].endTime = tick() + RADIATION_DURATION
		radiationEvent:FireClient(player, true, RADIATION_DURATION, RADIATION_DURATION)
		return
	end

	radiationData[player] = {
		active = true,
		endTime = tick() + RADIATION_DURATION,
	}

	player:SetAttribute("RadiationSick", true)
	radiationEvent:FireClient(player, true, RADIATION_DURATION, RADIATION_DURATION)

	-- Timer loop
	task.spawn(function()
		while radiationData[player] and radiationData[player].active do
			task.wait(1)
			if not player.Parent then break end

			local remaining = radiationData[player].endTime - tick()
			if remaining <= 0 then
				radiationData[player].active = false
				player:SetAttribute("RadiationSick", false)
				radiationEvent:FireClient(player, false, 0, RADIATION_DURATION)
				break
			end

			radiationEvent:FireClient(player, true, remaining, RADIATION_DURATION)

			-- Extra hunger drain while sick
			if _G.DrainHunger then
				_G.DrainHunger(player, 1)
			end
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	spawnTimes[player] = tick()
	player.CharacterAdded:Connect(function()
		spawnTimes[player] = tick()
		waterHitCounts[player] = 0
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	spawnTimes[player] = nil
	waterHitCounts[player] = nil
	radiationData[player] = nil
end)

for _, player in Players:GetPlayers() do
	spawnTimes[player] = tick()
	player.CharacterAdded:Connect(function()
		spawnTimes[player] = tick()
		waterHitCounts[player] = 0
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

	if player and spawnTimes[player] then
		if tick() - spawnTimes[player] < SPAWN_IMMUNITY then
			return
		end
	end

	if isOverWater(rootPart) then
		if not waterTimes[humanoid] then
			waterTimes[humanoid] = tick()
		end
		if tick() - waterTimes[humanoid] >= WATER_GRACE then
			local damage = humanoid.MaxHealth * DAMAGE_PERCENT
			humanoid:TakeDamage(damage)

			if player then
				waterHitCounts[player] = (waterHitCounts[player] or 0) + 1
				if waterHitCounts[player] >= RADIATION_HIT_THRESHOLD then
					waterHitCounts[player] = 0
					applyRadiation(player)
				end
			end
		end
	else
		waterTimes[humanoid] = nil
	end
end

while true do
	task.wait(CHECK_INTERVAL)

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			local hum = char:FindFirstChildWhichIsA("Humanoid")
			local hrp = char:FindFirstChild("HumanoidRootPart")
			damageHumanoid(hum, hrp, player)

			local intensity = 0
			if hum and waterTimes[hum] then
				local timeInWater = tick() - waterTimes[hum]
				intensity = math.clamp(timeInWater / MAX_VIGNETTE_TIME, 0, 1)
			end
			vignetteEvent:FireClient(player, intensity)
		end
	end

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
