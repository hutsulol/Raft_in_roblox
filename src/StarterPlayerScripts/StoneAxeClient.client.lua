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
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()
local camera = workspace.CurrentCamera

local chopTreeEvent = ReplicatedStorage:WaitForChild("ChopTree")

-- ─── Tunables ─────────────────────────────────────────────────────────
local CHOP_COOLDOWN  = 0.8     -- per the user's brief
local CHOP_AIM_RANGE = 200     -- studs of mouse-ray raycast

-- Custom axe cursor. mouse.Icon would render the asset at its
-- native upload size (huge), so we hide the system cursor while
-- aiming at a tree and draw our own size-controlled ImageLabel
-- that follows the mouse position. 40×40 pixels — small enough to
-- not obscure the tree, big enough to read as an axe.
local CURSOR_AXE_ASSET = "rbxassetid://102927945165446"
local CURSOR_AXE_SIZE  = 40

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

-- Separate ScreenGui for the axe cursor with IgnoreGuiInset = false
-- so its (0, 0) lines up with mouse.X / mouse.Y exactly. The cursor
-- needs to track the system cursor pixel-accurately, so we don't
-- want the topbar inset shifting it.
local cursorGui = Instance.new("ScreenGui")
cursorGui.Name = "StoneAxeCursor"
cursorGui.DisplayOrder = 1000
cursorGui.IgnoreGuiInset = false
cursorGui.ResetOnSpawn = false
cursorGui.Parent = playerGui

local axeCursor = Instance.new("ImageLabel")
axeCursor.Name = "AxeIcon"
axeCursor.AnchorPoint = Vector2.new(0.5, 0.5)
axeCursor.Size = UDim2.fromOffset(CURSOR_AXE_SIZE, CURSOR_AXE_SIZE)
axeCursor.BackgroundTransparency = 1
axeCursor.Image = CURSOR_AXE_ASSET
axeCursor.ScaleType = Enum.ScaleType.Fit
axeCursor.Visible = false
axeCursor.ZIndex = 100
axeCursor.Parent = cursorGui

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

-- Drop notifications now live in StarterPlayerScripts/InventoryNotify.
-- That file listens to the InventoryNotify RemoteEvent which the
-- server fires from inside _G.AddResourceToInventory, so every pickup
-- (tree chop / stone mine / ocean pull / shovel / floor pickup)
-- gets the same Raft-style bottom-right card without per-tool
-- duplication. Stone_Axe just calls the inventory-add helper for each
-- drop and the cards appear automatically.

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

-- Pick what to outline for a given Choppable model. Planted Bed_T*
-- wrappers carry the bed art (Center / Model / Earth) alongside the
-- actual tree, so highlighting the whole wrapper outlines the stones
-- and dirt too. Skip past the bed's static children and return the
-- first dynamic one (Palm Tree, Banana Tree, …) so only the tree
-- itself gets the outline. Free-standing trees on islands don't have
-- these static children and fall through to the wrapper.
local TREE_BED_STATIC = { Center = true, Model = true, Earth = true }
local function findHighlightTarget(tree)
	if not tree then return nil end
	for _, child in tree:GetChildren() do
		if not TREE_BED_STATIC[child.Name] and not child:GetAttribute("IsBush") then
			return child
		end
	end
	return tree
end

-- ─── Cursor swap helper ──────────────────────────────────────────
-- showAxeCursor(true)  → hide the system cursor and follow the
--                        mouse with our 40×40 axe ImageLabel
-- showAxeCursor(false) → restore the system cursor + hide our icon
local function showAxeCursor(show)
	if show then
		UserInputService.MouseIconEnabled = false
		axeCursor.Position = UDim2.fromOffset(mouse.X, mouse.Y)
		axeCursor.Visible = true
	else
		UserInputService.MouseIconEnabled = true
		axeCursor.Visible = false
	end
end

-- ─── Per-frame highlight + cursor update ─────────────────────────
local function updateHighlight()
	if not axeEquipped then
		clearHighlight()
		showAxeCursor(false)
		return
	end

	-- Always track the mouse position so the moment we DO show the
	-- axe cursor it lands at the right pixel without a stale frame.
	axeCursor.Position = UDim2.fromOffset(mouse.X, mouse.Y)

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
			if highlightBox then highlightBox.Adornee = findHighlightTarget(tree) end
			showAxeCursor(true)
			hintLabel.Text = "Click to chop tree"
			hintLabel.Visible = true
			return
		end
	end

	clearHighlight()
	showAxeCursor(false)
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
		showAxeCursor(false)
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

-- ─── Server feedback → tree-fell SFX + highlight clear ───────────
-- Drop notifications now come through InventoryNotify (server fires
-- one event per inventory add inside _G.AddResourceToInventory).
-- We keep this listener only for the felled-tree polish: a final
-- wood-break sound + highlight clear when health reaches 0.
chopTreeEvent.OnClientEvent:Connect(function(action, _, healthLeft)
	if action == "drops" and (healthLeft or 0) <= 0 then
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
end)
