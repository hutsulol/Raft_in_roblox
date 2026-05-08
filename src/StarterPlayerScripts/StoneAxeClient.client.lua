-- StoneAxeClient.client.lua
-- Client-side glue for the Stone_Axe tool: highlights choppable
-- trees on hover, swaps the mouse cursor to the axe icon while
-- aiming, fires "ChopTree" on click under a 0.8 s cooldown, and
-- renders Raft-style item-drop notifications in the bottom-right
-- as the server dispenses drops on every swing.
--
-- Animation is handled by the in-tool Script
-- (src/Stone_Axe ( Tool )/Script). This file owns ONLY the chop
-- game logic + client-side HUD.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()
local camera = workspace.CurrentCamera

local chopTreeEvent = ReplicatedStorage:WaitForChild("ChopTree")

-- ─── Tunables ─────────────────────────────────────────────────────────
local CHOP_COOLDOWN  = 0.8     -- per the user's brief
local CHOP_AIM_RANGE = 200     -- studs of mouse-ray raycast

-- Mouse cursor icons. The axe icon swaps in only while the cursor is
-- actively over a Choppable tree (per user request — replaces the
-- default circle with an axe so the player reads "I can chop this").
local CURSOR_AXE     = "rbxassetid://102927945165446"
local CURSOR_DEFAULT = ""    -- empty = Roblox default cursor

-- ─── Resource icons + display names (mirrors InventoryUI) ──────────
-- Local copy to avoid the cross-script dependency. The five tree-drop
-- resources are the only ones that show up in our notifications, so
-- the small duplication is cheap. If a notification fires for a
-- resource we don't have an icon for the row simply renders text-only.
local RESOURCE_ICONS = {
	Log     = "rbxassetid://110032041583533",
	Leaves  = "rbxassetid://96691360298069",
	Plank   = "rbxassetid://118108820731466",
}

local DISPLAY_NAMES = {
	Log     = "Log",
	Leaves  = "Leaves",
	Plank   = "Plank",
	Sapling = "Sapling",
	Banana  = "Banana",
	Coconut = "Coconut",
}

-- ─── State ────────────────────────────────────────────────────────────
local axeEquipped     = false
local currentTool     = nil
local highlightedTree = nil
local highlightBox    = nil
local choppingCooldown = false

-- ─── HUD root ────────────────────────────────────────────────────────
local playerGui = player:WaitForChild("PlayerGui")
local hintGui = Instance.new("ScreenGui")
hintGui.Name = "StoneAxeHud"
hintGui.DisplayOrder = 51
hintGui.IgnoreGuiInset = true
hintGui.ResetOnSpawn = false
hintGui.Parent = playerGui

-- "Aim at trees / Click to chop" hint at the bottom centre.
local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "HintText"
hintLabel.AnchorPoint = Vector2.new(0.5, 1)
hintLabel.Position = UDim2.new(0.5, 0, 0.8, 0)
hintLabel.Size = UDim2.new(0, 300, 0, 40)
hintLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
hintLabel.BackgroundTransparency = 0.4
hintLabel.Text = ""
hintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
hintLabel.TextSize = 18
hintLabel.Font = Enum.Font.GothamBold
hintLabel.Visible = false
hintLabel.Parent = hintGui

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 8)
hintCorner.Parent = hintLabel

-- ─── Drop-notification stack (Raft-style, bottom-right) ───────────
-- Each notification is a small wood-toned card with "+N | icon |
-- name". Up to ~6 are visible at once; older ones fade and slide
-- off the bottom as new ones come in. UIListLayout handles the
-- vertical stacking and shifting; per-card task.delay handles the
-- fade-out + cleanup.
local NOTIF_LIFETIME = 3.5    -- seconds before fade
local NOTIF_FADE     = 0.6    -- fade duration after lifetime
local NOTIF_HEIGHT   = 38
local NOTIF_WIDTH    = 220
local NOTIF_GAP      = 6

local notifContainer = Instance.new("Frame")
notifContainer.Name = "DropNotifications"
notifContainer.AnchorPoint = Vector2.new(1, 1)
notifContainer.Position = UDim2.new(1, -16, 1, -110)  -- above the hotbar
notifContainer.Size = UDim2.fromOffset(NOTIF_WIDTH, 380)
notifContainer.BackgroundTransparency = 1
notifContainer.Parent = hintGui

local notifLayout = Instance.new("UIListLayout")
notifLayout.FillDirection = Enum.FillDirection.Vertical
notifLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
notifLayout.VerticalAlignment   = Enum.VerticalAlignment.Bottom
notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifLayout.Padding   = UDim.new(0, NOTIF_GAP)
notifLayout.Parent = notifContainer

local notifOrder = 0

local function showDropNotif(resourceName, count)
	if (count or 0) <= 0 then return end
	notifOrder = notifOrder + 1

	local card = Instance.new("Frame")
	card.Name = "Drop_" .. resourceName
	card.Size = UDim2.fromOffset(NOTIF_WIDTH, NOTIF_HEIGHT)
	card.BackgroundColor3 = Color3.fromRGB(38, 28, 20)
	card.BackgroundTransparency = 0.15
	card.BorderSizePixel = 0
	card.LayoutOrder = notifOrder
	card.Parent = notifContainer

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(180, 140, 80)
	stroke.Thickness = 1
	stroke.Parent = card

	-- "+N" prefix in green (positive feedback colour, matches the
	-- in-game inventory affordable-cost colour).
	local countLabel = Instance.new("TextLabel")
	countLabel.Position = UDim2.fromOffset(8, 0)
	countLabel.Size = UDim2.fromOffset(40, NOTIF_HEIGHT)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "+" .. tostring(count)
	countLabel.TextColor3 = Color3.fromRGB(180, 240, 130)
	countLabel.TextSize = 18
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextXAlignment = Enum.TextXAlignment.Left
	countLabel.Parent = card

	-- Resource icon. Empty image for resources we don't have an
	-- asset id for (Sapling / Banana / Coconut today) — they still
	-- render the count + name correctly.
	local iconBox = Instance.new("ImageLabel")
	iconBox.Position = UDim2.fromOffset(50, 4)
	iconBox.Size = UDim2.fromOffset(NOTIF_HEIGHT - 8, NOTIF_HEIGHT - 8)
	iconBox.BackgroundTransparency = 1
	iconBox.Image = RESOURCE_ICONS[resourceName] or ""
	iconBox.ScaleType = Enum.ScaleType.Fit
	iconBox.Parent = card

	-- Resource name (right of the icon).
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Position = UDim2.fromOffset(NOTIF_HEIGHT - 8 + 56, 0)
	nameLabel.Size = UDim2.fromOffset(
		NOTIF_WIDTH - (NOTIF_HEIGHT - 8 + 56) - 8,
		NOTIF_HEIGHT)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = DISPLAY_NAMES[resourceName] or resourceName
	nameLabel.TextColor3 = Color3.fromRGB(255, 240, 220)
	nameLabel.TextSize = 14
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card

	task.delay(NOTIF_LIFETIME, function()
		local steps = 12
		for i = 0, steps do
			if not card.Parent then return end
			local a = i / steps
			card.BackgroundTransparency = 0.15 + a * 0.85
			stroke.Transparency        = a
			countLabel.TextTransparency = a
			nameLabel.TextTransparency  = a
			iconBox.ImageTransparency   = a
			task.wait(NOTIF_FADE / steps)
		end
		if card.Parent then card:Destroy() end
	end)
end

-- ─── Highlight (green outline so it reads as "wood" not "rock") ───
local function createHighlight()
	if highlightBox then highlightBox:Destroy() end
	highlightBox = Instance.new("Highlight")
	highlightBox.FillTransparency = 1
	highlightBox.OutlineColor = Color3.fromRGB(120, 220, 90)
	highlightBox.OutlineTransparency = 0
	highlightBox.Parent = playerGui
end

local function clearHighlight()
	if highlightBox then highlightBox.Adornee = nil end
	highlightedTree = nil
end

-- ─── Resolve a Choppable tree from the raycast hit ────────────────
local function findChoppableTree(instance)
	if not instance then return nil end
	local current = instance
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("Choppable") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- ─── Per-frame highlight + cursor update ─────────────────────────
local function updateHighlight()
	if not axeEquipped then
		clearHighlight()
		mouse.Icon = CURSOR_DEFAULT
		return
	end

	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}
	if player.Character then table.insert(filterList, player.Character) end
	params.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * CHOP_AIM_RANGE, params)
	if result and result.Instance then
		local tree = findChoppableTree(result.Instance)
		if tree then
			highlightedTree = tree
			if highlightBox then highlightBox.Adornee = tree end
			mouse.Icon = CURSOR_AXE
			hintLabel.Text = "Click to chop tree"
			hintLabel.Visible = true
			return
		end
	end

	clearHighlight()
	mouse.Icon = CURSOR_DEFAULT
	hintLabel.Text = "Aim at trees on islands to chop"
	hintLabel.Visible = true
end

-- ─── Tool equip / unequip plumbing ────────────────────────────────
local function onToolEquipped(tool)
	if tool.Name == "Stone_Axe" then
		axeEquipped = true
		currentTool = tool
		createHighlight()
		hintLabel.Visible = true
	end
end

local function onToolUnequipped(tool)
	if tool.Name == "Stone_Axe" then
		axeEquipped = false
		currentTool = nil
		clearHighlight()
		mouse.Icon = CURSOR_DEFAULT
		hintLabel.Visible = false
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
		if child:IsA("Tool") and child.Name == "Stone_Axe" then
			onToolEquipped(child)
			break
		end
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

RunService.RenderStepped:Connect(function()
	if axeEquipped then
		updateHighlight()
	end
end)

-- ─── Click → chop (0.8 s cooldown) ────────────────────────────────
mouse.Button1Down:Connect(function()
	if not axeEquipped then return end
	if choppingCooldown then return end
	if not highlightedTree then return end

	choppingCooldown = true
	chopTreeEvent:FireServer(highlightedTree)

	task.delay(CHOP_COOLDOWN, function()
		choppingCooldown = false
	end)
end)

-- ─── Server feedback → notifications ──────────────────────────────
-- Server sends a per-hit drops table { resourceName = count, ... }
-- plus the post-hit health (0 means the tree just fell). Render one
-- notification per resource so the player sees them stack in the
-- bottom right Raft-style.
chopTreeEvent.OnClientEvent:Connect(function(action, drops, healthLeft)
	if action == "drops" then
		if type(drops) == "table" then
			for resourceName, count in pairs(drops) do
				showDropNotif(resourceName, count)
			end
		end

		if (healthLeft or 0) <= 0 then
			-- Tree felled — clear the highlight, play wood-break SFX
			-- on top of the per-hit one for a satisfying final
			-- sound. Mirrors the Pick-Axe Rock_Crush flourish.
			clearHighlight()
			local logTemplate = ReplicatedStorage:FindFirstChild("Log")
			local woodBreak = logTemplate and logTemplate:FindFirstChild("Wood Break", true)
			if woodBreak and woodBreak:IsA("Sound") then
				local clone = woodBreak:Clone()
				clone.Parent = SoundService
				clone:Play()
				Debris:AddItem(clone, 5)
			end
		end
	end
end)
