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
local CollectionService = game:GetService("CollectionService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local harvestEvent     = ReplicatedStorage:WaitForChild("HarvestFruit")
local gardenActionEvent = ReplicatedStorage:WaitForChild("GardenAction")

-- Server tags every harvestable bush with this tag in
-- FruitBushSystem.server.lua. Lets us enumerate them in O(N tagged)
-- instead of walking the whole workspace tree each frame.
local HARVESTABLE_TAG = "HarvestableFruitBush"

-- Display label for the hint, keyed by Name prefix on the tagged
-- model. Order matters only when two prefixes both match — first hit
-- wins. Keep in sync with the server's HARVESTABLE table.
local HARVESTABLE_DISPLAY = {
	{ prefix = "PineApple", display = "Pineapple" },
}

local function displayFor(model)
	for _, entry in ipairs(HARVESTABLE_DISPLAY) do
		if string.find(model.Name, entry.prefix, 1, true) then
			return entry.display
		end
	end
	return "Fruit"
end

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

	local bestHarvest, bestHarvestDist = nil, PICKUP_RANGE
	local bestPlantBed, bestPlantDist  = nil, PLANT_RANGE
	local hasSeed = playerHasSeed()

	-- Harvestable bushes are enumerated via CollectionService — the
	-- server tags any matching Model (PineApple leaves nested inside
	-- Island_1, a Trees Folder, or anywhere else in workspace).
	for _, bush in CollectionService:GetTagged(HARVESTABLE_TAG) do
		if bush.Parent and bush:IsDescendantOf(workspace) and not bush:GetAttribute("FruitCooldown") then
			local d = (playerPos - bush:GetPivot().Position).Magnitude
			if d < bestHarvestDist then
				bestHarvest, bestHarvestDist = bush, d
			end
		end
	end

	-- Tree garden beds live on the raft; walking the raft's children
	-- is cheap and avoids tagging every placement individually.
	if hasSeed then
		local raft = workspace:FindFirstChild("Raft")
		if raft then
			for _, m in raft:GetChildren() do
				if m:IsA("Model")
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
		end
	end

	-- Harvest wins on ties so a ripe bush right next to a waterable
	-- bed doesn't get hidden.
	if bestHarvest and (not bestPlantBed or bestHarvestDist <= bestPlantDist) then
		currentAction = "harvest"
		currentTarget = bestHarvest
		hintLabel.Text    = "[E] Collect " .. displayFor(bestHarvest)
		hintLabel.Visible = true
		-- While the prompt is visible, claim E away from InventoryUI's
		-- toggle handler. The flag's deferred check there reads this
		-- as "another script is using E" and skips toggleInventory().
		_G.SuppressInventoryToggle = true
	elseif bestPlantBed then
		currentAction = "plant"
		currentTarget = bestPlantBed
		hintLabel.Text    = "[E] Plant Seed"
		hintLabel.Visible = true
		_G.SuppressInventoryToggle = true
	else
		currentAction = nil
		currentTarget = nil
		hintLabel.Visible = false
		_G.SuppressInventoryToggle = false
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
