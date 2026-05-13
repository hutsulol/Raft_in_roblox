-- FruitBushClient.client.lua
-- Shows "[E] Collect Pineapple" when the player walks up to a fruit
-- bush, and fires HarvestFruit on E press. Server-side validation
-- (range / cooldown / inventory grant) lives in
-- ServerScriptService/FruitBushSystem.server.lua — this file is
-- pure UX.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local harvestEvent = ReplicatedStorage:WaitForChild("HarvestFruit")

-- Same prefix table the server uses (kept in sync manually — both are
-- short and this avoids replicating a config module just for one
-- shared constant).
local HARVESTABLE_PREFIXES = {
	{ prefix = "PineApple", display = "Pineapple" },
}

local PICKUP_RANGE = 12

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

-- Walk a Model's descendants once and pick up every nested Model that
-- matches a harvestable prefix. Pre-filters by ancestor name to avoid
-- a full workspace scan every frame.
local currentTarget = nil
local function findNearestBush()
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, nil end
	local playerPos = hrp.Position

	local closest, closestEntry, closestDist = nil, nil, PICKUP_RANGE

	local function considerModel(m)
		local entry = matchHarvestable(m)
		if not entry then return end
		if m:GetAttribute("FruitCooldown") then return end
		local d = (playerPos - m:GetPivot().Position).Magnitude
		if d < closestDist then
			closest, closestEntry, closestDist = m, entry, d
		end
	end

	-- Walk every top-level workspace child and recurse only into
	-- Model children (Trees Folder, Island_1, Raft, etc.) for the
	-- harvest scan. PartCount on islands is high but the
	-- IsA("Model") fast-path keeps this lightweight.
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

	return closest, closestEntry
end

RunService.Heartbeat:Connect(function()
	local bush, entry = findNearestBush()
	currentTarget = bush
	if bush and entry then
		hintLabel.Text    = "[E] Collect " .. entry.display
		hintLabel.Visible = true
	else
		hintLabel.Visible = false
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode ~= Enum.KeyCode.E then return end
	if not currentTarget or not currentTarget.Parent then return end
	harvestEvent:FireServer(currentTarget)
end)
