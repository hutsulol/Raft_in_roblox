local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = require(ReplicatedStorage:WaitForChild("SetupRemotes"))

local REGROW_TIME = 20
local CRAFT_MATERIAL = "Plank"
local CRAFT_AMOUNT = 1
local PLACEMENT_RANGE = 20

local bushTemplate = ReplicatedStorage:WaitForChild("BushTemplate")

local function setupBush(bush)
	local grapes = bush:WaitForChild("Grapes")
	local clickDetector = bush:WaitForChild("ClickDetector")
	local handle = grapes:WaitForChild("Handle")
	local sound = handle:WaitForChild("Sound")

	local grapesVisible = true

	clickDetector.MaxActivationDistance = 8

	clickDetector.MouseClick:Connect(function(player)
		if not grapesVisible then return end

		grapesVisible = false
		handle.Transparency = 1
		sound:Play()
		clickDetector.MaxActivationDistance = 0

		local backpack = player:FindFirstChild("Backpack")
		if backpack and not backpack:FindFirstChild("[GRAPES]") then
			local grapeTool = ReplicatedStorage:WaitForChild("[GRAPES]"):Clone()
			grapeTool.Parent = backpack
		end

		task.delay(REGROW_TIME, function()
			if bush and bush.Parent then
				handle.Transparency = 0
				clickDetector.MaxActivationDistance = 8
				grapesVisible = true
			end
		end)
	end)
end

for _, bush in ipairs(workspace:GetDescendants()) do
	if bush.Name == "bush" and bush:IsA("Model") then
		setupBush(bush)
	end
end

workspace.DescendantAdded:Connect(function(obj)
	if obj.Name == "bush" and obj:IsA("Model") then
		task.defer(function()
			setupBush(obj)
		end)
	end
end)

remotes.CraftBush.OnServerEvent:Connect(function(player)
	local character = player.Character
	if not character then return end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end

	local backpack = player:FindFirstChild("Backpack")
	local foundPlanks = {}

	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item.Name == CRAFT_MATERIAL then
				table.insert(foundPlanks, item)
				if #foundPlanks >= CRAFT_AMOUNT then break end
			end
		end
	end

	if character then
		for _, item in ipairs(character:GetChildren()) do
			if item.Name == CRAFT_MATERIAL and #foundPlanks < CRAFT_AMOUNT then
				table.insert(foundPlanks, item)
				if #foundPlanks >= CRAFT_AMOUNT then break end
			end
		end
	end

	if #foundPlanks < CRAFT_AMOUNT then return end

	for _, plank in ipairs(foundPlanks) do
		plank:Destroy()
	end

	local newBush = bushTemplate:Clone()
	local placementCF = humanoidRootPart.CFrame * CFrame.new(0, 0, -6)
	newBush:PivotTo(CFrame.new(placementCF.Position.X, humanoidRootPart.Position.Y - 3, placementCF.Position.Z))
	newBush.Parent = workspace
end)
