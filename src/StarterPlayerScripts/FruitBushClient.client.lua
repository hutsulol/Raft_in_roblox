-- FruitBushClient.client.lua
-- Handles every "press E next to a thing on the raft / island" loop
-- that doesn't fit the existing tool-based interactions:
--
--   * Harvest a fruit-bearing model (PineApple leaves → 1-2 Pineapples
--     + 1 Pineapple_Seed, cooldown).
--   * Plant a seed on a watered Bed_Garden_For_Tree → kicks off the
--     four-stage tree growth timer on the server (GardenSystem).
--
-- Server-side validation (range / cooldown / inventory grant / etc.)
-- lives in ServerScriptService/FruitBushSystem + GardenSystem; this
-- file is pure UX (hint label + E dispatch).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local harvestEvent     = ReplicatedStorage:WaitForChild("HarvestFruit")
local gardenActionEvent = ReplicatedStorage:WaitForChild("GardenAction")

local HARVESTABLE_PREFIXES = {
	{ prefix = "PineApple", display = "Pineapple" },
}

local PICKUP_RANGE = 12
local PLANT_RANGE  = 12

local SEED_NAMES = { "Pineapple_Seed", "Banana_Seed", "Coconut_Seed" }

-- ─── Hint label ───
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "FruitBushHint"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder   = 45
screenGui.Parent         = playerGui

local hintLabel = Instance.new("TextLabel")
hintLabel.AnchorPoint            = Vector2.new(0.5, 1)
hintLabel.Position               = UDim2.new(0.5, 0, 0.78, 0)
hintLabel.Size                   = UDim2.new(0, 280, 0, 36)
hintLabel.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
hintLabel.BackgroundTransparency = 0.4
hintLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
hintLabel.Font                   = Enum.Font.GothamBold
hintLabel.TextSize               = 18
hintLabel.Text                   = ""
hintLabel.Visible                = false
hintLabel.Parent                 = screenGui

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 8)
hintCorner.Parent       = hintLabel

local function matchHarvestable(model)
	if not model or not model:IsA("Model") then return nil end
	for _, entry in ipairs(HARVESTABLE_PREFIXES) do
		if string.find(model.Name, entry.prefix, 1, true) then
			return entry
		end
	end
	return nil
end

-- We use the same _G.InventorySlotData InventoryUI publishes (read-
-- only here) to figure out if the player owns any seed. It's a
-- snapshot of slot contents — fast to scan and updates as the server
-- pushes inventory diffs back through InventoryUpdate.
local function playerHasSeed()
	local slots = _G.InventorySlotData
	if typeof(slots) ~= "table" then return false end
	for _, data in pairs(slots) do
		if data and data.type == "resource" and data.count and data.count > 0 then
			for _, seedName in ipairs(SEED_NAMES) do
				if data.name == seedName then return true end
			end
		end
	end
	return false
end

local currentAction = nil  -- "harvest" | "plant"
local currentTarget = nil

local function findInteraction()
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local playerPos = hrp.Position

	local bestHarvest, bestHarvestEntry, bestHarvestDist = nil, nil, PICKUP_RANGE
	local bestPlantBed, bestPlantDist = nil, PLANT_RANGE
	local hasSeed = playerHasSeed()

	local function considerModel(m)
		-- Harvestable fruit bushes (PineApple leaves).
		local entry = matchHarvestable(m)
		if entry and not m:GetAttribute("FruitCooldown") then
			local d = (playerPos - m:GetPivot().Position).Magnitude
			if d < bestHarvestDist then
				bestHarvest, bestHarvestEntry, bestHarvestDist = m, entry, d
			end
		end

		-- Tree garden beds the player can plant on.
		if hasSeed
			and m:GetAttribute("IsBedGardenForTree")
			and m:GetAttribute("IsWatered")
			and not m:GetAttribute("GrowthStage")
		then
			local d = (playerPos - m:GetPivot().Position).Magnitude
			if d < bestPlantDist then
				bestPlantBed, bestPlantDist = m, d
			end
		end
	end

	for _, top in workspace:GetChildren() do
		if top:IsA("Model") then
			considerModel(top)
			for _, descendant in top:GetDescendants() do
				if descendant:IsA("Model") then
					considerModel(descendant)
				end
			end
		end
	end

	-- Pick whichever is closer; harvest wins ties so the planting
	-- prompt doesn't suppress a ripe bush you're standing next to.
	if bestHarvest and (not bestPlantBed or bestHarvestDist <= bestPlantDist) then
		currentAction = "harvest"
		currentTarget = bestHarvest
		hintLabel.Text    = "[E] Collect " .. bestHarvestEntry.display
		hintLabel.Visible = true
	elseif bestPlantBed then
		currentAction = "plant"
		currentTarget = bestPlantBed
		hintLabel.Text    = "[E] Plant Seed"
		hintLabel.Visible = true
	else
		currentAction = nil
		currentTarget = nil
		hintLabel.Visible = false
	end
end

RunService.Heartbeat:Connect(findInteraction)

UserInputService.InputBegan:Connect(function(input, processed)
	if UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode ~= Enum.KeyCode.E then return end
	if not currentTarget or not currentTarget.Parent then return end

	if currentAction == "harvest" then
		harvestEvent:FireServer(currentTarget)
	elseif currentAction == "plant" then
		gardenActionEvent:FireServer("plantSeed", currentTarget)
	end
end)
