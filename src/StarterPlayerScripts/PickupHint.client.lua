local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local PICKUP_TAG = "PickupHint"
local PICKUP_DISTANCE = 12
local PICKUP_KEY = Enum.KeyCode.E
local KEY_ICON = "rbxassetid://89189791827999"

local pickupEvent = ReplicatedStorage:WaitForChild("TaggedPickupRequest")

local gui = Instance.new("ScreenGui")
gui.Name = "PickupHintGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local holder = Instance.new("Frame")
holder.BackgroundTransparency = 1
holder.Size = UDim2.fromOffset(170, 52)
holder.AnchorPoint = Vector2.new(0.5, 1)
holder.Visible = false
holder.Parent = gui

local keyImage = Instance.new("ImageLabel")
keyImage.BackgroundTransparency = 1
keyImage.Size = UDim2.fromOffset(22, 22)
keyImage.AnchorPoint = Vector2.new(0.5, 0)
keyImage.Position = UDim2.fromScale(0.5, 0)
keyImage.Image = KEY_ICON
keyImage.Parent = holder

local txt = Instance.new("TextLabel")
txt.BackgroundTransparency = 1
txt.Size = UDim2.new(1, 0, 0, 20)
txt.Position = UDim2.fromOffset(0, 24)
txt.Font = Enum.Font.GothamSemibold
txt.TextSize = 12
txt.TextColor3 = Color3.fromRGB(255, 238, 196)
txt.TextStrokeTransparency = 0.5
txt.Text = "Pick up"
txt.Parent = holder

local function resolveTarget(inst)
	if not inst then return nil end
	if CollectionService:HasTag(inst, PICKUP_TAG) then return inst end
	local model = inst:FindFirstAncestorWhichIsA("Model")
	while model do
		if CollectionService:HasTag(model, PICKUP_TAG) then return model end
		model = model.Parent and model.Parent:FindFirstAncestorWhichIsA("Model")
	end
	local cur = inst
	while cur and cur ~= workspace do
		if CollectionService:HasTag(cur, PICKUP_TAG) then return cur end
		cur = cur.Parent
	end
	return nil
end

local currentTarget = nil

RunService.RenderStepped:Connect(function()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not camera then
		holder.Visible = false
		currentTarget = nil
		return
	end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {char}
	params.IgnoreWater = true

	local result = Workspace:Raycast(ray.Origin, ray.Direction * PICKUP_DISTANCE, params)
	local hit = result and result.Instance
	local target = resolveTarget(hit)

	if target and target:IsDescendantOf(workspace) then
		local pos
		if target:IsA("Model") then
			local ok, cf = pcall(function() return target:GetPivot() end)
			pos = ok and cf.Position or nil
		elseif target:IsA("BasePart") then
			pos = target.Position
		end
		if pos and (pos - hrp.Position).Magnitude <= PICKUP_DISTANCE then
			currentTarget = target
			local name = target:GetAttribute("PickupDisplayName") or target.Name
			txt.Text = "Pick up: " .. tostring(name)
			holder.Position = UDim2.fromOffset(mousePos.X, mousePos.Y + 26)
			holder.Visible = true
			return
		end
	end

	holder.Visible = false
	currentTarget = nil
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode ~= PICKUP_KEY then return end
	if not currentTarget then return end
	pickupEvent:FireServer(currentTarget)
end)
