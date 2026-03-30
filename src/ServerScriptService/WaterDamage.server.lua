local Players = game:GetService("Players")

local DAMAGE_PERCENT = 0.10  -- 10% of max health per second
local CHECK_INTERVAL = 1

local function isOverWater(rootPart)
	-- Raycast down from character's feet to check if they're standing on something solid
	local rayOrigin = rootPart.Position
	local rayDirection = Vector3.new(0, -20, 0) -- check 20 studs below
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Exclude the character model
	params.FilterDescendantsInstances = {rootPart.Parent}

	local result = workspace:Raycast(rayOrigin, rayDirection, params)
	if result and result.Instance then
		-- Hit something solid below — check if it's a raft part or other solid ground
		-- If it's water (Terrain) or nothing, they're over water
		if result.Instance:IsA("Terrain") then
			return true
		end
		return false -- standing on a solid part (raft, pirate raft, etc.)
	end

	-- Nothing below at all — over open water
	return true
end

local function damageIfInWater(humanoid, rootPart)
	if not humanoid or humanoid.Health <= 0 then return end
	if not rootPart then return end

	if isOverWater(rootPart) then
		local damage = humanoid.MaxHealth * DAMAGE_PERCENT
		humanoid:TakeDamage(damage)
	end
end

while true do
	task.wait(CHECK_INTERVAL)

	-- Damage players in water
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			local hum = char:FindFirstChildWhichIsA("Humanoid")
			local hrp = char:FindFirstChild("HumanoidRootPart")
			damageIfInWater(hum, hrp)
		end
	end

	-- Damage NPCs (pirates etc.) in water
	for _, obj in workspace:GetChildren() do
		if obj:IsA("Model") and not Players:GetPlayerFromCharacter(obj) then
			local hum = obj:FindFirstChildWhichIsA("Humanoid")
			if hum then
				local hrp = obj:FindFirstChild("HumanoidRootPart")
				damageIfInWater(hum, hrp)
			end
		end
	end
end
