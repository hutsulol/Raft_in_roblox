local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")

-- ─── Config ───
local RADIATION_DURATION = 60 -- seconds
local HUNGER_DRAIN_MULTIPLIER = 3 -- hunger drains 3x faster while sick

-- ─── Remote Events ───
local function getOrCreate(name)
	local e = rs:FindFirstChild(name)
	if not e then
		e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = rs
	end
	return e
end

local radiationEvent = getOrCreate("RadiationUpdate")

-- ─── Radiation State ───
local radiationData = {} -- player → { active, endTime }

-- ─── Apply radiation sickness to a player ───
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

	-- Set attribute so other scripts (combat, tools) can check
	player:SetAttribute("RadiationSick", true)

	-- Notify client
	radiationEvent:FireClient(player, true, RADIATION_DURATION, RADIATION_DURATION)

	-- Timer loop
	task.spawn(function()
		while radiationData[player] and radiationData[player].active do
			task.wait(1)
			if not player.Parent then break end -- player left

			local remaining = radiationData[player].endTime - tick()
			if remaining <= 0 then
				-- Sickness ended
				radiationData[player].active = false
				player:SetAttribute("RadiationSick", false)
				radiationEvent:FireClient(player, false, 0, RADIATION_DURATION)
				break
			end

			-- Update client with remaining time
			radiationEvent:FireClient(player, true, remaining, RADIATION_DURATION)
		end
	end)
end

-- Expose globally so other scripts can trigger radiation
_G.ApplyRadiation = applyRadiation

-- ─── Increased hunger drain while sick ───
-- We hook into the hunger system by periodically draining extra hunger
task.spawn(function()
	while true do
		task.wait(5) -- extra drain every 5 seconds
		for _, player in Players:GetPlayers() do
			if radiationData[player] and radiationData[player].active then
				-- Access hunger data via _G if available
				if _G.DrainHunger then
					_G.DrainHunger(player, 2) -- extra 2 hunger every 5s
				end
			end
		end
	end
end)

-- ─── Cleanup on player leave ───
Players.PlayerRemoving:Connect(function(player)
	radiationData[player] = nil
end)
