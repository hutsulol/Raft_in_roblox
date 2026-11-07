-- BedScript: place this Script inside the bed part
-- Player touches bed at night → lies down. Jump to stand up.
-- While sleeping, night passes 20x faster.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cooldown = 3
local CurrentPlayer = nil
local CallbackHandler = nil
local CName = 'BedCooldown'
local SavedMassless = nil

local function isNight()
	local clock = Lighting.ClockTime
	return clock >= 18 or clock < 6
end

-- Спать можно только ПОСЛЕ зачистки волны: иначе ночь можно было бы проспать
-- целиком вместе с наградой, ни разу не приняв бой.
-- ПОЛОЖИТЕЛЬНЫЙ сигнал: WaveDirector пишет в Workspace.WaveClearedNight номер
-- ночи, волна которой уже перебита. Спать можно, только если это ТЕКУЩАЯ ночь.
--
-- Раньше здесь читался флаг «волна активна», и на закате была гонка: ночь
-- наступает мгновенно, а WaveDirector опрашивает время раз в 0.5с — игрок,
-- стоящий на кровати, успевал лечь до выставления флага и просыпал всю волну.
-- При отсутствующем атрибуте (0) сравнение не сойдётся, и спать нельзя — то
-- есть по умолчанию ЗАПРЕЩЕНО, а не разрешено.
local function waveUncleared()
	local dc = ReplicatedStorage:FindFirstChild("DayCount")
	local night = dc and dc.Value or 0
	return (workspace:GetAttribute("WaveClearedNight") or 0) ~= night
end

local function getSleepingCount()
	local val = ReplicatedStorage:FindFirstChild("SleepingPlayers")
	if not val then
		val = Instance.new("IntValue")
		val.Name = "SleepingPlayers"
		val.Value = 0
		val.Parent = ReplicatedStorage
	end
	return val
end

function StandupFromBed()
	if CurrentPlayer ~= nil and script.Parent:FindFirstChild("WeldConstraint") then
		-- Decrement sleeping count
		local sc = getSleepingCount()
		sc.Value = math.max(0, sc.Value - 1)

		-- ПЕРСОНАЖ МОГ УМЕРЕТЬ ВО СНЕ. Тогда HumanoidRootPart уже уничтожен, и
		-- обращение к нему ниже роняло эту функцию — CurrentPlayer оставался
		-- ненулевым, а кровать была занята призраком до конца раунда.
		local hrp = CurrentPlayer:FindFirstChild("HumanoidRootPart")
		local hum = CurrentPlayer:FindFirstChildWhichIsA("Humanoid")
		if not (hrp and hum and hum.Health > 0) then
			script.Parent.WeldConstraint:Remove()
			if CallbackHandler ~= nil then
				CallbackHandler:disconnect()
				CallbackHandler = nil
			end
			SavedMassless = nil
			CurrentPlayer = nil
			return
		end

		local C = Instance.new("StringValue", CurrentPlayer)
		C.Name = CName
		game.Debris:AddItem(C, Cooldown)

		-- Anchor HRP first so removing the weld can't transfer momentum to the raft
		CurrentPlayer.HumanoidRootPart.Anchored = true
		script.Parent.WeldConstraint:Remove()

		if CallbackHandler ~= nil then
			CallbackHandler:disconnect()
			CallbackHandler = nil
		end

		-- Compute a stand-up position above the bed without inheriting bed orientation
		local bedPos = script.Parent.Position
		local standCF = CFrame.new(bedPos + Vector3.new(0, 5, 0))
		CurrentPlayer.HumanoidRootPart.CFrame = standCF
		CurrentPlayer.Humanoid.PlatformStand = false

		-- Restore mass on character parts
		if SavedMassless then
			for part, wasMassless in pairs(SavedMassless) do
				if part and part.Parent then
					part.Massless = wasMassless
				end
			end
			SavedMassless = nil
		end

		wait()
		CurrentPlayer.HumanoidRootPart.Anchored = false
		CurrentPlayer = nil
	end
end

function LayToBed(character)
	if character ~= nil and not script.Parent:FindFirstChild("WeldConstraint") then
		-- Only allow sleeping at night
		if not isNight() then return end
		-- …и только когда волна этой ночи полностью перебита
		if waveUncleared() then return end

		CurrentPlayer = character

		-- Make all character parts massless so the player's weight cannot
		-- apply torque to the raft via the weld constraint
		SavedMassless = {}
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				SavedMassless[part] = part.Massless
				part.Massless = true
			end
		end

		CurrentPlayer.HumanoidRootPart.CFrame = script.Parent.CFrame * CFrame.Angles(math.rad(90), 0, math.rad(-90))
		CurrentPlayer.Humanoid.PlatformStand = true
		local Weld = Instance.new("WeldConstraint", script.Parent)
		Weld.Part0 = script.Parent
		Weld.Part1 = character.HumanoidRootPart

		-- Increment sleeping count
		local sc = getSleepingCount()
		sc.Value = sc.Value + 1

		CallbackHandler = CurrentPlayer.Humanoid.Changed:Connect(function(property)
			if CurrentPlayer ~= nil and property == 'Jump' then
				StandupFromBed()
			end
		end)

		-- Auto stand up when night ends (day arrives)
		task.spawn(function()
			while CurrentPlayer ~= nil do
				if not isNight() then
					StandupFromBed()
					break
				end
				task.wait(0.5)
			end
		end)
	end
end

script.Parent.Touched:Connect(function(hit)
	local Character = hit.Parent
	if Character:FindFirstChild("Humanoid") and CurrentPlayer == nil and not Character:FindFirstChild(CName) then
		LayToBed(Character)
	end
end)