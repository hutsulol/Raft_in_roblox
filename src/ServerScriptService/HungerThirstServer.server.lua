local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = require(ReplicatedStorage:WaitForChild("SetupRemotes"))

local MAX_HUNGER = 100
local MAX_THIRST = 100
local HUNGER_DRAIN_RATE = 1
local THIRST_DRAIN_RATE = 1.5
local DRAIN_INTERVAL = 3
local STARVE_DAMAGE = 5
local DEHYDRATE_DAMAGE = 5
local GRAPE_HUNGER_RESTORE = 25
local GRAPE_HP_REGEN = 10

local playerStats = {}

local function initPlayer(player)
	playerStats[player] = {
		hunger = MAX_HUNGER,
		thirst = MAX_THIRST,
	}
	remotes.UpdateHunger:FireClient(player, MAX_HUNGER, MAX_HUNGER)
	remotes.UpdateThirst:FireClient(player, MAX_THIRST, MAX_THIRST)
end

local function cleanupPlayer(player)
	playerStats[player] = nil
end

Players.PlayerAdded:Connect(function(player)
	initPlayer(player)

	player.CharacterAdded:Connect(function()
		playerStats[player].hunger = MAX_HUNGER
		playerStats[player].thirst = MAX_THIRST
		remotes.UpdateHunger:FireClient(player, MAX_HUNGER, MAX_HUNGER)
		remotes.UpdateThirst:FireClient(player, MAX_THIRST, MAX_THIRST)
	end)
end)

Players.PlayerRemoving:Connect(cleanupPlayer)

remotes.EatGrapes.OnServerEvent:Connect(function(player)
	local stats = playerStats[player]
	if not stats then return end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	stats.hunger = math.min(stats.hunger + GRAPE_HUNGER_RESTORE, MAX_HUNGER)
	remotes.UpdateHunger:FireClient(player, stats.hunger, MAX_HUNGER)

	local currentHP = humanoid.Health
	local maxHP = humanoid.MaxHealth
	local targetHP = math.min(currentHP + GRAPE_HP_REGEN, maxHP)

	task.spawn(function()
		local regenPerTick = 1
		while humanoid and humanoid.Health > 0 and humanoid.Health < targetHP do
			humanoid.Health = math.min(humanoid.Health + regenPerTick, targetHP)
			task.wait(0.2)
		end
	end)
end)

while true do
	task.wait(DRAIN_INTERVAL)

	for player, stats in pairs(playerStats) do
		local character = player.Character
		if not character then continue end

		local humanoid = character:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then continue end

		stats.hunger = math.max(stats.hunger - HUNGER_DRAIN_RATE, 0)
		stats.thirst = math.max(stats.thirst - THIRST_DRAIN_RATE, 0)

		remotes.UpdateHunger:FireClient(player, stats.hunger, MAX_HUNGER)
		remotes.UpdateThirst:FireClient(player, stats.thirst, MAX_THIRST)

		if stats.hunger <= 0 then
			humanoid:TakeDamage(STARVE_DAMAGE)
		end

		if stats.thirst <= 0 then
			humanoid:TakeDamage(DEHYDRATE_DAMAGE)
		end
	end
end
