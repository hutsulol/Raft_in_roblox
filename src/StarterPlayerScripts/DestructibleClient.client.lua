-- DestructibleClient.client.lua
-- Sister to StoneAxeClient. When an axe-class Tool is equipped this
-- raycasts from the mouse to find a Destructible-tagged Model,
-- highlights the SPECIFIC BasePart the player is aiming at (so the
-- player can target individual chunks), and fires DestructibleHit on
-- click. The server side handles damage, snap-off + fade, and
-- model cleanup once every part is broken.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local TAG = "Destructible"
local HIT_RANGE = 18
local AIM_RANGE = 200
local CLICK_COOLDOWN = 0.45

local AXE_TOOLS = {
	["Stone_Axe"] = true,
	["Axe"] = true,
}

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

local hitEvent = ReplicatedStorage:WaitForChild("DestructibleHit")

local axeEquipped = false
local highlightedPart = nil
local highlightedModel = nil
local highlight = nil
local cooldown = false

local function ensureHighlight()
	if highlight and highlight.Parent then return end
	highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.6
	highlight.FillColor = Color3.fromRGB(255, 180, 80)
	highlight.OutlineColor = Color3.fromRGB(255, 240, 160)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = playerGui
end

local function clearHighlight()
	if highlight then highlight.Adornee = nil end
	highlightedPart = nil
	highlightedModel = nil
end

local function findDestructibleModel(instance)
	local current = instance
	while current and current ~= workspace do
		if current:IsA("Model") and CollectionService:HasTag(current, TAG) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function onToolEquipped(tool)
	if AXE_TOOLS[tool.Name] then
		axeEquipped = true
		ensureHighlight()
	end
end

local function onToolUnequipped(tool)
	if AXE_TOOLS[tool.Name] then
		axeEquipped = false
		clearHighlight()
	end
end

local function setupCharacter(char)
	if not char then return end
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then onToolEquipped(child) end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then onToolUnequipped(child) end
	end)
	for _, child in char:GetChildren() do
		if child:IsA("Tool") and AXE_TOOLS[child.Name] then
			onToolEquipped(child)
			break
		end
	end
end

local existingChar = player.Character
if existingChar then setupCharacter(existingChar) end
player.CharacterAdded:Connect(setupCharacter)

RunService.RenderStepped:Connect(function()
	if not axeEquipped then
		if highlightedPart then clearHighlight() end
		return
	end

	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		params.FilterDescendantsInstances = { player.Character }
	end

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * AIM_RANGE, params)
	if result and result.Instance and result.Instance:IsA("BasePart") then
		local model = findDestructibleModel(result.Instance)
		if model and not result.Instance:GetAttribute("PartBroken") then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and (hrp.Position - result.Instance.Position).Magnitude <= HIT_RANGE then
				highlightedPart = result.Instance
				highlightedModel = model
				if highlight then highlight.Adornee = result.Instance end
				return
			end
		end
	end
	clearHighlight()
end)

mouse.Button1Down:Connect(function()
	if not axeEquipped then return end
	if cooldown then return end
	if not highlightedPart or not highlightedModel then return end
	if not highlightedPart.Parent or not highlightedModel.Parent then return end

	cooldown = true
	hitEvent:FireServer(highlightedModel, highlightedPart)
	task.delay(CLICK_COOLDOWN, function()
		cooldown = false
	end)
end)
