-- AnchorUI.client.lua
-- Wooden-panel UI that appears when the player stands near an anchor
-- on the raft. Displays depth as a percentage, E lowers the rope one
-- step, Q raises it one step. The server (AnchorInteraction) clamps
-- the rope to [MIN_ROPE, MAX_ROPE] and flips the raft's
-- AnchorDeployed attribute when any rope hits MAX_ROPE, so this file
-- just drives the UI and the input → RemoteEvent hop.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse  = player:GetMouse()
local camera = workspace.CurrentCamera

local anchorEvent = ReplicatedStorage:WaitForChild("AnchorAction")

local MIN_ROPE          = 5
local MAX_ROPE          = 11
local HOVER_RANGE       = 60    -- studs; cap on the cursor raycast

local COLORS = {
	panelBg    = Color3.fromRGB(139, 109, 63),
	panelDark  = Color3.fromRGB(100, 75, 40),
	title      = Color3.fromRGB(255, 245, 220),
	track      = Color3.fromRGB(80, 58, 30),
	fillShallow = Color3.fromRGB(90, 190, 110),
	fillDeep    = Color3.fromRGB(230, 80, 70),
	hintBg     = Color3.fromRGB(30, 22, 10),
	keyBg      = Color3.fromRGB(200, 170, 90),
	keyText    = Color3.fromRGB(40, 28, 12),
	hintText   = Color3.fromRGB(255, 245, 220),
}

-- ─── UI construction ────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "AnchorUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 6
gui.Enabled = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -120)
panel.Size = UDim2.fromOffset(340, 96)
panel.BackgroundColor3 = COLORS.panelBg
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
do
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.panelDark
	stroke.Thickness = 3
	stroke.Parent = panel
end

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 22)
title.Position = UDim2.new(0, 10, 0, 8)
title.BackgroundTransparency = 1
title.Text = "Anchor"
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = COLORS.title
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local pctLabel = Instance.new("TextLabel")
pctLabel.Size = UDim2.new(0, 80, 0, 22)
pctLabel.Position = UDim2.new(1, -90, 0, 8)
pctLabel.BackgroundTransparency = 1
pctLabel.Text = "0%"
pctLabel.Font = Enum.Font.GothamBold
pctLabel.TextSize = 18
pctLabel.TextColor3 = COLORS.title
pctLabel.TextXAlignment = Enum.TextXAlignment.Right
pctLabel.Parent = panel

-- Progress track
local track = Instance.new("Frame")
track.Size = UDim2.new(1, -20, 0, 14)
track.Position = UDim2.new(0, 10, 0, 36)
track.BackgroundColor3 = COLORS.track
track.BorderSizePixel = 0
track.Parent = panel
Instance.new("UICorner", track).CornerRadius = UDim.new(0, 6)

local fill = Instance.new("Frame")
fill.Size = UDim2.new(0, 0, 1, 0)
fill.BackgroundColor3 = COLORS.fillShallow
fill.BorderSizePixel = 0
fill.Parent = track
Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)

-- Key hints row
local hintsRow = Instance.new("Frame")
hintsRow.Size = UDim2.new(1, -20, 0, 28)
hintsRow.Position = UDim2.new(0, 10, 1, -36)
hintsRow.BackgroundTransparency = 1
hintsRow.Parent = panel

local function makeHint(parent, keyText, hintText, xScale)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(0.5, -4, 1, 0)
	row.Position = UDim2.new(xScale, xScale == 0 and 0 or 4, 0, 0)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local keyPill = Instance.new("Frame")
	keyPill.Size = UDim2.fromOffset(28, 28)
	keyPill.BackgroundColor3 = COLORS.keyBg
	keyPill.BorderSizePixel = 0
	keyPill.Parent = row
	Instance.new("UICorner", keyPill).CornerRadius = UDim.new(0, 6)

	local keyLbl = Instance.new("TextLabel")
	keyLbl.Size = UDim2.new(1, 0, 1, 0)
	keyLbl.BackgroundTransparency = 1
	keyLbl.Text = keyText
	keyLbl.Font = Enum.Font.GothamBold
	keyLbl.TextSize = 16
	keyLbl.TextColor3 = COLORS.keyText
	keyLbl.Parent = keyPill

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -36, 1, 0)
	hint.Position = UDim2.new(0, 36, 0, 0)
	hint.BackgroundTransparency = 1
	hint.Text = hintText
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 15
	hint.TextColor3 = COLORS.hintText
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Parent = row
end

makeHint(hintsRow, "E", "Lower",  0)
makeHint(hintsRow, "Q", "Raise", 0.5)

-- ─── Anchor discovery ───────────────────────────────────────────────
local function findCenterOfSticks(anchorModel)
	local sticks = anchorModel:FindFirstChild("sticks")
	if sticks then
		local c = sticks:FindFirstChild("Center of sticks", true)
		if c and c:IsA("BasePart") then return c end
	end
	local c = anchorModel:FindFirstChild("Center of sticks", true)
	if c and c:IsA("BasePart") then return c end
	return nil
end

local function findRope(anchorModel)
	local inner = anchorModel:FindFirstChild("anchor")
	if inner then
		local rc = inner:FindFirstChildOfClass("RopeConstraint")
		if rc then return rc end
	end
	for _, d in anchorModel:GetDescendants() do
		if d:IsA("RopeConstraint") then return d end
	end
	return nil
end

-- Walks up from the cursor's hit instance looking for a Wooden_Wheel
-- whose ancestor model is an Anchor_part. Returns the Anchor_part
-- model, or nil.
local function anchorFromInstance(inst)
	local cur = inst
	while cur do
		if cur:IsA("Model") and cur.Name == "Wooden_Wheel" then
			local anchor = cur:FindFirstAncestorOfClass("Model")
			if anchor and anchor.Name == "Anchor_part" then
				return anchor
			end
			-- Wooden_Wheel might be a direct child of Anchor_part too.
			if cur.Parent and cur.Parent.Name == "Anchor_part" then
				return cur.Parent
			end
		end
		cur = cur.Parent
	end
	return nil
end

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function anchorUnderCursor()
	local char = player.Character
	if not char then return nil end
	raycastParams.FilterDescendantsInstances = { char }

	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * HOVER_RANGE, raycastParams)
	if not result or not result.Instance then return nil end
	return anchorFromInstance(result.Instance)
end

-- ─── Render loop ────────────────────────────────────────────────────
local currentAnchor

local function updateUI()
	local anchor = anchorUnderCursor()
	currentAnchor = anchor
	-- Mirror the E-suppression trick PhoneMenu / ContainerUI use so the
	-- inventory toggle doesn't fire alongside "lower anchor".
	_G.SuppressInventoryToggle = anchor ~= nil or nil
	if not anchor then
		gui.Enabled = false
		return
	end
	gui.Enabled = true
	local rope = findRope(anchor)
	local length = rope and rope.Length or MIN_ROPE
	local range  = math.max(0.001, MAX_ROPE - MIN_ROPE)
	local pct    = math.clamp((length - MIN_ROPE) / range, 0, 1)
	fill.Size = UDim2.new(pct, 0, 1, 0)
	fill.BackgroundColor3 = COLORS.fillShallow:Lerp(COLORS.fillDeep, pct)
	pctLabel.Text = string.format("%d%%", math.floor(pct * 100 + 0.5))
end

RunService.RenderStepped:Connect(updateUI)

-- ─── Input ──────────────────────────────────────────────────────────
-- The wheel's HingeConstraint is pulsed by AnchorInteraction.server
-- on "lower"/"raise", so all we do here is forward the key press.
local function playRopeSound()
	local template = SoundService:FindFirstChild("low_rope")
	if not template or not template:IsA("Sound") then return end
	local clone = template:Clone()
	clone.Parent = SoundService
	clone:Play()
	Debris:AddItem(clone, 5)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	-- Only act while the UI is visible (i.e. cursor is on the wheel).
	if not currentAnchor then return end
	if input.KeyCode == Enum.KeyCode.E then
		anchorEvent:FireServer("lower", currentAnchor)
		playRopeSound()
	elseif input.KeyCode == Enum.KeyCode.Q then
		anchorEvent:FireServer("raise", currentAnchor)
		playRopeSound()
	end
end)
