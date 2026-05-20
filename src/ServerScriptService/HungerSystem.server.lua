local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")

-- ─── Config ───
local MAX_HUNGER = 100
local HUNGER_DRAIN_AMOUNT = 2
local HUNGER_DRAIN_INTERVAL = 15 -- lose 2 hunger every 15 seconds
local EAT_RESTORE = 20
local HUNGER_DAMAGE = 0.625 -- damage per tick at 0 hunger (5 / 8)
local HP_REGEN_AMOUNT = 5 -- HP restored when eating
local GRAPE_REGROW_TIME = 20

local HP_REGEN_INTERVAL = 1 -- base: regen every 1 second
local HP_REGEN_PER_TICK = 1 -- heal 1 HP per tick (1% of 100 max)
local HP_REGEN_SLOW_MULT = 5 -- 5x slower when hunger < 50%

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

local hungerEvent = getOrCreate("HungerUpdate")
local bushActionEvent = getOrCreate("BushAction")

-- ─── Player Hunger Data ───
local hungerData = {}

-- Expose drain function for other systems (e.g. radiation)
_G.DrainHunger = function(player, amount)
	if hungerData[player] then
		hungerData[player] = math.max(0, hungerData[player] - amount)
		hungerEvent:FireClient(player, hungerData[player], MAX_HUNGER)
	end
end

-- Public helper for consumable systems (FoodSystem, future cookware…)
-- to refill hunger + optionally regen a slice of HP, mirroring the
-- effect the grape-eat path applies inline below.
_G.RestoreHunger = function(player, hungerAmount, hpAmount)
	hungerAmount = tonumber(hungerAmount) or 0
	if hungerData[player] and hungerAmount > 0 then
		hungerData[player] = math.min(MAX_HUNGER, hungerData[player] + hungerAmount)
		hungerEvent:FireClient(player, hungerData[player], MAX_HUNGER)
	end
	hpAmount = tonumber(hpAmount) or 0
	if hpAmount > 0 then
		local char = player.Character
		local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
		if hum then
			hum.Health = math.min(hum.MaxHealth, hum.Health + hpAmount)
		end
	end
end

local function initPlayer(player)
	hungerData[player] = MAX_HUNGER
	hungerEvent:FireClient(player, hungerData[player], MAX_HUNGER)
end

Players.PlayerAdded:Connect(function(player)
	initPlayer(player)
	player.CharacterAdded:Connect(function()
		hungerData[player] = MAX_HUNGER
		hungerEvent:FireClient(player, MAX_HUNGER, MAX_HUNGER)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	hungerData[player] = nil
end)

for _, player in Players:GetPlayers() do
	initPlayer(player)
	player.CharacterAdded:Connect(function()
		hungerData[player] = MAX_HUNGER
		hungerEvent:FireClient(player, MAX_HUNGER, MAX_HUNGER)
	end)
end

-- ─── Hunger Drain Loop ───
task.spawn(function()
	while true do
		task.wait(HUNGER_DRAIN_INTERVAL)
		for _, player in Players:GetPlayers() do
			if hungerData[player] then
				hungerData[player] = math.max(0, hungerData[player] - HUNGER_DRAIN_AMOUNT)
				hungerEvent:FireClient(player, hungerData[player], MAX_HUNGER)

				if hungerData[player] <= 0 then
					local char = player.Character
					if char then
						local hum = char:FindFirstChildWhichIsA("Humanoid")
						if hum and hum.Health > 0 then
							hum:TakeDamage(HUNGER_DAMAGE)
						end
					end
				end
			end
		end
	end
end)

-- ─── Disable default Roblox health regen ───
-- Remove the default "Health" script from each character
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		local defaultHealth = char:WaitForChild("Health", 3)
		if defaultHealth and defaultHealth:IsA("Script") then
			defaultHealth:Destroy()
		end
	end)
end)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function(char)
		local defaultHealth = char:WaitForChild("Health", 3)
		if defaultHealth and defaultHealth:IsA("Script") then
			defaultHealth:Destroy()
		end
	end)
	-- Also handle current character
	if player.Character then
		local defaultHealth = player.Character:FindFirstChild("Health")
		if defaultHealth and defaultHealth:IsA("Script") then
			defaultHealth:Destroy()
		end
	end
end

-- ─── Health Regen Loop (slowed when hunger < 50%) ───
task.spawn(function()
	while true do
		task.wait(HP_REGEN_INTERVAL)
		for _, player in Players:GetPlayers() do
			local char = player.Character
			if not char then continue end
			local hum = char:FindFirstChildWhichIsA("Humanoid")
			if not hum or hum.Health <= 0 or hum.Health >= hum.MaxHealth then continue end

			local hunger = hungerData[player] or 0
			local hungerRatio = hunger / MAX_HUNGER

			-- At 0 hunger, no regen (already taking damage)
			if hunger <= 0 then continue end

			-- Below 50% hunger: regen 5x slower (only heal every 5th tick)
			if hungerRatio < 0.5 then
				-- Use a counter attribute to track slow ticks
				local counter = (player:GetAttribute("_regenCounter") or 0) + 1
				if counter < HP_REGEN_SLOW_MULT then
					player:SetAttribute("_regenCounter", counter)
					continue
				end
				player:SetAttribute("_regenCounter", 0)
			end

			hum.Health = math.min(hum.MaxHealth, hum.Health + HP_REGEN_PER_TICK)
		end
	end
end)

-- ─── Setup ClickDetector on a bush for grape picking ───
local function setupBushClickDetector(bush)
	local cd = bush:FindFirstChildWhichIsA("ClickDetector", true)
	if not cd then
		cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = 8
		if bush.PrimaryPart then
			cd.Parent = bush.PrimaryPart
		elseif bush:FindFirstChildWhichIsA("BasePart") then
			cd.Parent = bush:FindFirstChildWhichIsA("BasePart")
		else
			cd.Parent = bush
		end
	end

	cd.MouseClick:Connect(function(clickPlayer)
		if bush:GetAttribute("GrapesAvailable") == false then return end

		-- Bush must be on a watered garden bed to produce fruit
		local garden = bush.Parent
		if garden and garden:GetAttribute("IsGarden") and not garden:GetAttribute("IsWatered") then
			return
		end

		-- Hide grapes
		bush:SetAttribute("GrapesAvailable", false)
		local grapes = bush:FindFirstChild("grapes") or bush:FindFirstChild("Grapes")
		if grapes then
			if grapes:IsA("BasePart") then
				grapes.Transparency = 1
			elseif grapes:IsA("Model") then
				for _, p in grapes:GetDescendants() do
					if p:IsA("BasePart") then p.Transparency = 1 end
				end
			end
		end

		-- Give grape tool
		local grapeTool = Instance.new("Tool")
		grapeTool.Name = "[GRAPES]"
		grapeTool.CanBeDropped = false
		grapeTool.TextureId = "rbxassetid://137478230275649"
		grapeTool:SetAttribute("IsGrape", true)

		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(1, 1, 1)
		handle.Color = Color3.fromRGB(100, 0, 150)
		handle.Shape = Enum.PartType.Ball
		handle.Parent = grapeTool

		local backpack = clickPlayer:FindFirstChild("Backpack")
		if backpack then
			grapeTool.Parent = backpack
		end

		-- Regrow (only if garden is watered)
		task.delay(GRAPE_REGROW_TIME, function()
			if not bush or not bush.Parent then return end

			local g = bush.Parent
			local isWatered = g and g:GetAttribute("IsGarden") and g:GetAttribute("IsWatered") == true

			if isWatered then
				bush:SetAttribute("GrapesAvailable", true)
				if grapes then
					if grapes:IsA("BasePart") then
						grapes.Transparency = 0
					elseif grapes:IsA("Model") then
						for _, p in grapes:GetDescendants() do
							if p:IsA("BasePart") then p.Transparency = 0 end
						end
					end
				end
			else
				-- Garden is dry; poll until it's watered again
				task.spawn(function()
					while bush and bush.Parent do
						task.wait(3)
						local g2 = bush.Parent
						if g2 and g2:GetAttribute("IsGarden") and g2:GetAttribute("IsWatered") == true then
							bush:SetAttribute("GrapesAvailable", true)
							if grapes then
								if grapes:IsA("BasePart") then
									grapes.Transparency = 0
								elseif grapes:IsA("Model") then
									for _, p in grapes:GetDescendants() do
										if p:IsA("BasePart") then p.Transparency = 0 end
									end
								end
							end
							break
						end
					end
				end)
			end
		end)
	end)
end

-- ─── Handle Actions ───
bushActionEvent.OnServerEvent:Connect(function(player, action, target)
	local char = player.Character
	if not char then return end

	if action == "eatGrape" then
		-- Player has [GRAPES] tool equipped, eats it
		local tool = char:FindFirstChildWhichIsA("Tool")
		if not tool then return end
		if tool.Name ~= "[GRAPES]" and tool.Name ~= "Grapes" then return end

		-- Restore hunger
		if hungerData[player] then
			hungerData[player] = math.min(MAX_HUNGER, hungerData[player] + EAT_RESTORE)
			hungerEvent:FireClient(player, hungerData[player], MAX_HUNGER)
		end

		-- Regenerate HP
		local hum = char:FindFirstChildWhichIsA("Humanoid")
		if hum then
			hum.Health = math.min(hum.MaxHealth, hum.Health + HP_REGEN_AMOUNT)
		end

		-- Destroy the grape tool
		tool:Destroy()

	elseif action == "placeBush" then
		-- Player places a bush on a garden bed. Two kinds are accepted:
		--   * Berry bush — equipped Tool is the "bush" / "Bush" stub
		--     crafted from the workbench.
		--   * Pineapple bush — equipped Tool is a Pineapple_Seed (the
		--     same Tool the player drops into the leaf bag); planting
		--     it on a regular Garden grows a harvestable PineApple
		--     bush instead of starting tree growth.
		local tool = char:FindFirstChildWhichIsA("Tool")
		if not tool then return end

		local templateName, finalBushName, questEvent
		if tool.Name == "bush" or tool.Name == "Bush" then
			templateName  = "bush"
			finalBushName = "Bush"
			questEvent    = "planted:BerryBush"
		elseif tool.Name == "Pineapple_Bush_Seed" then
			templateName  = "PineApple leaves"
			finalBushName = "PineApple leaves"
			questEvent    = "planted:PineappleBush"
		else
			return
		end

		-- target is the garden bed instance (sent from client). Must be
		-- a regular Garden — tree beds carry IsGarden=true too (the
		-- watering pipeline is shared) so we explicitly reject them
		-- here. Bushes belong on the small flat Garden, never on the
		-- tree-sized Bed_T.
		if not target or not target:IsA("Model") or not target:GetAttribute("IsGarden") then return end
		if target:GetAttribute("IsBedGardenForTree") then return end

		local raft = workspace:FindFirstChild("Raft")
		if not raft or not raft.PrimaryPart then return end

		-- Check garden doesn't already have a bush
		for _, child in target:GetChildren() do
			if child:GetAttribute("IsBush") then return end
		end

		local template = rs:FindFirstChild(templateName)
			or rs:FindFirstChild(templateName, true)
		if not template then
			warn(("HungerSystem: bush template %q not found in ReplicatedStorage"):format(templateName))
			return
		end

		local gardenIsWatered = target:GetAttribute("IsWatered") == true

		local bush = template:Clone()
		bush.Name = finalBushName
		bush:SetAttribute("IsBush", true)
		bush:SetAttribute("PlacedBy", player.UserId)
		-- GrapesAvailable is berry-specific (drives the hidden-when-dry
		-- grape-mesh logic below). The pineapple bush is harvested
		-- through FruitBushSystem instead — it picks the model up via
		-- the HarvestableFruitBush tag, applied automatically on parent.
		if templateName == "bush" then
			bush:SetAttribute("GrapesAvailable", gardenIsWatered)
		end

		-- Remove any existing scripts inside the bush
		for _, desc in bush:GetDescendants() do
			if desc:IsA("Script") or desc:IsA("LocalScript") then
				desc:Destroy()
			end
		end

		-- If garden is dry, hide grape parts so the berry bush looks
		-- fruitless. Pineapple bushes get their fruit-visibility logic
		-- from FruitBushSystem's cooldown loop instead, so skip there.
		if templateName == "bush" and not gardenIsWatered then
			local grapes = bush:FindFirstChild("grapes") or bush:FindFirstChild("Grapes")
			if grapes then
				if grapes:IsA("BasePart") then
					grapes.Transparency = 1
				elseif grapes:IsA("Model") then
					for _, p in grapes:GetDescendants() do
						if p:IsA("BasePart") then p.Transparency = 1 end
					end
				end
			end
		end

		-- Reset WorldPivot to identity rotation
		if bush:IsA("Model") then
			local bbCF = bush:GetBoundingBox()
			bush.WorldPivot = CFrame.new(bbCF.Position)
		end

		-- Position bush planted in garden bed (center at garden top surface)
		local gardenCF, gardenSize = target:GetBoundingBox()
		local topY = gardenCF.Position.Y + gardenSize.Y / 2
		local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0

		-- Apply template rotation for bush (same as client ghost)
		local bushBBCF = bush:GetBoundingBox()
		local bushTemplateRot = bushBBCF.Rotation

		bush:PivotTo(CFrame.new(gardenCF.Position.X, topY, gardenCF.Position.Z) * CFrame.Angles(0, restYaw, 0) * bushTemplateRot)
		bush.Parent = target -- parent bush to the garden bed

		-- Quest hook: questEvent string is picked per-kind at the top so
		-- "planted:BerryBush" / "planted:PineappleBush" can be tracked
		-- separately by quest objectives.
		if questEvent and typeof(_G.OnQuestEvent) == "function" then
			pcall(_G.OnQuestEvent, player, questEvent, 1)
		end

		-- T13/T15/T16: snapshot velocity, force-anchor (templates may
		-- be unanchored), weld while anchored, then unanchor.
		-- T32: also set CanCollide = false on bush parts. PivotTo
		-- positions the bush's bbox centre at the garden's top
		-- surface, so the bush's lower half sits INSIDE the garden
		-- bed's soil parts. With both bush and garden welded to the
		-- raft and both colliding (same Raft group), Roblox's solver
		-- applies separation forces through their welds — those
		-- propagate as torque on the raft. Bushes are decorative +
		-- pickup-only (player clicks grapes to harvest), so collision
		-- isn't needed.
		local primary = raft.PrimaryPart
		local linVel = primary.AssemblyLinearVelocity
		local angVel = primary.AssemblyAngularVelocity

		for _, part in bush:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
			end
		end
		for _, part in bush:GetDescendants() do
			if part:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raft.PrimaryPart
				weld.Parent = part
			end
		end
		for _, part in bush:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end

		primary.AssemblyLinearVelocity  = linVel
		primary.AssemblyAngularVelocity = angVel

		-- Setup click detector for grape picking — berry bush only.
		-- Pineapple bushes are harvested via E (FruitBushSystem).
		if templateName == "bush" then
			setupBushClickDetector(bush)
		end

		-- Mark Consumed before Destroy so BushSeedSystem's refund hook
		-- (AncestryChanged → AddResourceToInventory) doesn't return
		-- the seed once we've successfully used it for placement.
		tool:SetAttribute("Consumed", true)
		tool:Destroy()
	end
end)
