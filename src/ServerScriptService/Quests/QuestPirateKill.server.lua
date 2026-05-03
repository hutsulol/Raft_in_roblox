-- QuestPirateKill.server.lua
-- Phase I6: credits "pirate:kill" quest progress when a HostilePirate
-- dies. The combat path itself (mercenaries vs. pirates, players
-- swinging tools) is split across multiple systems and the project
-- doesn't have a single damage-attribution hook, so we listen to the
-- pirate humanoid's Died event and credit the closest player within
-- a generous range. The heuristic is good enough for a single-raft
-- session — if you're near a pirate when it dies, the kill is
-- effectively yours.
--
-- We deliberately keep this in a tiny dedicated file (rather than
-- bolting onto PirateSpawner) so the quest path stays out of the
-- combat-spawning code, and the gameplay file isn't on the hook for
-- a quest-system regression.

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")

local KILL_CREDIT_RANGE = 80   -- studs; pirates and rafts cluster
                                -- close enough that 80 covers the
                                -- whole engagement area without
                                -- crediting a player on a different
                                -- raft.

local function pirateRoot(model)
	return model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
end

local function creditClosestPlayer(pirate)
	local root = pirateRoot(pirate)
	if not root then return end
	local center = root.Position

	local closest, closestDist
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - center).Magnitude
			if d < KILL_CREDIT_RANGE and (not closestDist or d < closestDist) then
				closest = p
				closestDist = d
			end
		end
	end

	if closest and typeof(_G.OnQuestEvent) == "function" then
		pcall(_G.OnQuestEvent, closest, "pirate:kill", 1)
	end
end

local handled = setmetatable({}, { __mode = "k" })   -- weak so dead pirate
                                                      -- models don't pin

local function watch(pirate)
	if handled[pirate] then return end
	handled[pirate] = true
	local hum = pirate:FindFirstChildWhichIsA("Humanoid")
	if not hum then
		-- Wait briefly in case the humanoid is parented after the tag.
		hum = pirate:WaitForChild("Humanoid", 5)
	end
	if not hum then return end
	hum.Died:Connect(function()
		-- Defer one tick so other Died handlers (loot drops, etc.)
		-- don't race the credit lookup if they reposition the model.
		task.defer(creditClosestPlayer, pirate)
	end)
end

-- Existing pirates already in workspace when this script loads.
for _, pirate in CollectionService:GetTagged("HostilePirate") do
	watch(pirate)
end
-- Future spawns.
CollectionService:GetInstanceAddedSignal("HostilePirate"):Connect(watch)
