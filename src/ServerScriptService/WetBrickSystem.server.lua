-- WetBrickSystem.server.lua
-- Place a Wet Brick on the raft, wait 10s, it becomes a Dry Brick.
-- Press E on a dry brick to pick it up into the inventory.

local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DRY_TIME = 10 -- seconds
local PICKUP_RANGE = 10
local WET_COLOR = Color3.fromRGB(96, 70, 50)
local DRY_COLOR = Color3.fromRGB(180, 130, 90)
local BRICK_SIZE = Vector3.new(3, 1.4, 2)
local DRY_BRICK_ICON = "rbxassetid://129896663405682"

local wetBrickAction = rs:FindFirstChild("WetBrickAction")
if not wetBrickAction then
	wetBrickAction = Instance.new("RemoteEvent")
	wetBrickAction.Name = "WetBrickAction"
	wetBrickAction.Parent = rs
end

-- ─── Helpers ────────────────────────────────────────────────
local function findOrCreateBrickModel(stage)
	local templateName = stage == "dry" and "Dry_Brick" or "Wet_Brick"
	local template = rs:FindFirstChild(templateName)
	if template then
		local clone = template:Clone()
		clone.Name = templateName
		return clone
	end

	-- Fallback: simple Part-based model
	local model = Instance.new("Model")
	model.Name = templateName
	local part = Instance.new("Part")
	part.Name = "Handle"
	part.Size = BRICK_SIZE
	part.Material = Enum.Material.Sand
	part.Color = stage == "dry" and DRY_COLOR or WET_COLOR
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = true
	part.Parent = model
	model.PrimaryPart = part
	return model
end

local function weldToRaft(model, raft)
	if not raft or not raft.PrimaryPart then return end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			-- Massless: placed bricks don't disturb the raft buoyancy (T12).
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = raft.PrimaryPart
			weld.Parent = part
		end
	end
end

local function stripScripts(model)
	for _, desc in model:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end
end

local function removeProximityPrompts(model)
	for _, desc in model:GetDescendants() do
		if desc:IsA("ProximityPrompt") then
			desc:Destroy()
		end
	end
end

local function getModelAnchorPart(model)
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

-- ─── Drying transition: replace wet model with dry model at same CFrame ───
local function transitionToDry(brickModel)
	if not brickModel or not brickModel.Parent then return end
	if brickModel:GetAttribute("IsDry") then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft then return end

	local anchor = getModelAnchorPart(brickModel)
	if not anchor then return end
	local savedCF = anchor.CFrame

	local dryModel = findOrCreateBrickModel("dry")
	stripScripts(dryModel)
	if dryModel:IsA("Model") then
		local bbCF = dryModel:GetBoundingBox()
		dryModel.WorldPivot = CFrame.new(bbCF.Position)
	end
	dryModel:PivotTo(savedCF)
	dryModel.Parent = raft
	weldToRaft(dryModel, raft)
	dryModel:SetAttribute("IsDry", true)
	dryModel:SetAttribute("IsWetBrick", true)

	-- Add Dry! billboard above
	local anchorDry = getModelAnchorPart(dryModel)
	if anchorDry then
		local bb = Instance.new("BillboardGui")
		bb.Name = "DryLabel"
		bb.Adornee = anchorDry
		bb.Size = UDim2.new(0, 110, 0, 36)
		bb.StudsOffset = Vector3.new(0, 2.5, 0)
		bb.AlwaysOnTop = true
		bb.Parent = anchorDry

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 0.3
		label.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		label.Text = "Dry! [E]"
		label.TextColor3 = Color3.fromRGB(255, 220, 100)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.BorderSizePixel = 0
		label.Parent = bb

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = label

		-- Proximity prompt for pickup (E)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pick up"
		prompt.ObjectText = "Dry Brick"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = PICKUP_RANGE
		prompt.RequiresLineOfSight = false
		prompt.Parent = anchorDry

		prompt.Triggered:Connect(function(player)
			if not dryModel.Parent then return end
			-- Distance check
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			if (hrp.Position - anchorDry.Position).Magnitude > PICKUP_RANGE then return end

			_G.AddResourceToInventory(player, "Dry_Brick", 1, anchorDry.Position)
			dryModel:Destroy()
		end)
	end

	brickModel:Destroy()
end

-- ─── Place a wet brick ───
wetBrickAction.OnServerEvent:Connect(function(player, action, target)
	if action ~= "placeWetBrick" then return end
	if typeof(target) ~= "CFrame" then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Wet_Brick" then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end

	local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

	local wetModel = findOrCreateBrickModel("wet")
	stripScripts(wetModel)
	removeProximityPrompts(wetModel)
	if wetModel:IsA("Model") then
		local bbCF = wetModel:GetBoundingBox()
		wetModel.WorldPivot = CFrame.new(bbCF.Position)
	end
	wetModel:PivotTo(worldCF)
	wetModel.Parent = raft
	weldToRaft(wetModel, raft)
	wetModel:SetAttribute("IsWetBrick", true)
	wetModel:SetAttribute("IsDry", false)
	wetModel:SetAttribute("PlacedAt", tick())

	tool:Destroy()

	task.delay(DRY_TIME, function()
		if wetModel and wetModel.Parent then
			transitionToDry(wetModel)
		end
	end)
end)

-- ─── Ensure inventory fields ───
local function ensureFields(player)
	task.wait(2)
	local inv = _G.GetInventory and _G.GetInventory(player)
	if inv then
		if inv.Wet_Brick == nil then inv.Wet_Brick = 0 end
		if inv.Dry_Brick == nil then inv.Dry_Brick = 0 end
	end
end

Players.PlayerAdded:Connect(function(p) task.spawn(ensureFields, p) end)
for _, p in Players:GetPlayers() do task.spawn(ensureFields, p) end

-- ─── Set tool icon when crafted ───
-- (the InventoryCrafting "placeable" branch sets TextureId from recipe.icon, so this is automatic)

return DRY_BRICK_ICON
