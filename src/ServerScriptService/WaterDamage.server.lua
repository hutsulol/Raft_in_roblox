local Players = game:GetService("Players")

local DAMAGE_PERCENT = 0.10  -- 10% of max health per second
local CHECK_INTERVAL = 1

local function damageIfInWater(humanoid, rootPart)
	if not humanoid or humanoid.Health <= 0 then return end
	if not rootPart then return end

	-- Water level = raft surface. Standing on raft, HRP is ~3 studs above raft center.
	-- In water, HRP is at or below raft center level.
	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end

	local waterY = raft.PrimaryPart.Position.Y
	if rootPart.Position.Y < waterY then
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
