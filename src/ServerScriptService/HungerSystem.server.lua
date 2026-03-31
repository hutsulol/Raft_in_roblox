local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")

-- ─── Config ───
local MAX_HUNGER = 100
local HUNGER_DRAIN_AMOUNT = 2
local HUNGER_DRAIN_INTERVAL = 15 -- lose 2 hunger every 15 seconds
local EAT_RESTORE = 20
local HUNGER_DAMAGE = 5 -- damage per second at 0 hunger
local HP_REGEN_AMOUNT = 5 -- HP restored when eating
local GRAPE_REGROW_TIME = 20

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
		grapeTool.TextureId = "rbxassetid://108688760959398"
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
		-- Player places a bush on a garden bed
		local tool = char:FindFirstChildWhichIsA("Tool")
		if not tool or (tool.Name ~= "bush" and tool.Name ~= "Bush") then return end

		-- target is the garden bed instance (sent from client)
		if not target or not target:IsA("Model") or not target:GetAttribute("IsGarden") then return end

		local raft = workspace:FindFirstChild("Raft")
		if not raft or not raft.PrimaryPart then return end

		-- Check garden doesn't already have a bush
		for _, child in target:GetChildren() do
			if child:GetAttribute("IsBush") then return end
		end

		local template = rs:FindFirstChild("bush")
		if not template then
			warn("HungerSystem: bush template not found in ReplicatedStorage")
			return
		end

		local bush = template:Clone()
		bush.Name = "Bush"
		bush:SetAttribute("IsBush", true)
		bush:SetAttribute("GrapesAvailable", target:GetAttribute("IsWatered") == true)
		bush:SetAttribute("PlacedBy", player.UserId)

		-- Remove any existing scripts inside the bush
		for _, desc in bush:GetDescendants() do
			if desc:IsA("Script") or desc:IsA("LocalScript") then
				desc:Destroy()
			end
		end

		-- Reset WorldPivot to identity rotation
		if bush:IsA("Model") then
			local bbCF = bush:GetBoundingBox()
			bush.WorldPivot = CFrame.new(bbCF.Position)
		end

		-- Position on top of garden bed center
		local gardenCF, gardenSize = target:GetBoundingBox()
		local bushSize = bush:GetExtentsSize()
		local topY = gardenCF.Position.Y + gardenSize.Y / 2 + bushSize.Y / 2
		local _, raftYaw, _ = raft.PrimaryPart.CFrame:ToEulerAnglesYXZ()

		-- Apply template rotation for bush (same as client ghost)
		local bushBBCF = bush:GetBoundingBox()
		local bushTemplateRot = bushBBCF.Rotation

		bush:PivotTo(CFrame.new(gardenCF.Position.X, topY, gardenCF.Position.Z) * CFrame.Angles(0, raftYaw, 0) * bushTemplateRot)
		bush.Parent = target -- parent bush to the garden bed

		-- Weld to raft
		for _, part in bush:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raft.PrimaryPart
				weld.Parent = part
			end
		end

		-- Setup click detector for grape picking
		setupBushClickDetector(bush)

		-- Remove tool from player
		tool:Destroy()
	end
end)
