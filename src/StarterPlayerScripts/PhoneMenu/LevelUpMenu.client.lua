-- LevelUpMenu.client.lua
-- Full-screen overlay shown when the player levels up. Displays the
-- level transition, instant rewards, and newly unlocked recipes.
-- Styled to match the Phone menu theme.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local levelUpEvent = ReplicatedStorage:WaitForChild("LevelUp")

-- ─── Theme (matches PhoneMenu) ───────────────────────────────────────────
local COLOR_BG          = Color3.fromRGB(5, 15, 35)
local COLOR_PANEL       = Color3.fromRGB(10, 25, 55)
local COLOR_PANEL_EDGE  = Color3.fromRGB(80, 180, 255)
local COLOR_ACCENT      = Color3.fromRGB(120, 210, 255)
local COLOR_TEXT        = Color3.fromRGB(220, 240, 255)
local COLOR_TEXT_DIM    = Color3.fromRGB(140, 180, 220)
local COLOR_BAR_BG      = Color3.fromRGB(15, 35, 70)
local COLOR_GOLD        = Color3.fromRGB(255, 220, 100)

local FONT_TITLE = Enum.Font.GothamBold
local FONT_BODY  = Enum.Font.Gotham

-- ─── Icons ───────────────────────────────────────────────────────────────
local ICON_LOG          = "rbxassetid://110032041583533"
local ICON_UPGRADE_PT   = "rbxassetid://89809613033816" -- star / pick-axe style

-- ─── Per-level unlock definitions ────────────────────────────────────────
-- Each entry lists the recipes / items that become available at that level.
-- `icon` is the same rbxassetid used in the crafting system.
local LEVEL_UNLOCKS = {
	[4] = {
		{ name = "Work Bench",    icon = "rbxassetid://104306543647624" },
		{ name = "Paddle",        icon = "rbxassetid://93358108538106"  },
	},
	[5] = {
		{ name = "Cup",           icon = "rbxassetid://99673504095026"  },
		{ name = "Water Purifier", icon = "rbxassetid://90221080738714" },
	},
	[6] = {
		{ name = "Garden Bed",    icon = "rbxassetid://77159786623285"  },
		{ name = "Grape Bush",    icon = "rbxassetid://100755665041729" },
	},
	[7] = {
		{ name = "Furnace",       icon = "rbxassetid://117760352651529" },
		{ name = "Shovel",        icon = "rbxassetid://91548954831391"  },
	},
	[8] = {
		{ name = "Fishing Rod",   icon = "" },
		{ name = "Wooden Spear",  icon = "rbxassetid://110032041583533" },
	},
}

-- ─── Small UI helpers ────────────────────────────────────────────────────

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
end

local function stroke(parent, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 1.5
	s.Color     = color or COLOR_PANEL_EDGE
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

-- ─── Build and show the level-up screen ──────────────────────────────────

local activeGui = nil -- prevent stacking

local function showLevelUp(oldLevel, newLevel)
	-- Tear down any existing overlay
	if activeGui then
		activeGui:Destroy()
		activeGui = nil
	end

	-- Collect all unlocks across the level range (handles multi-level jumps)
	local unlocks = {}
	for lvl = oldLevel + 1, newLevel do
		local defs = LEVEL_UNLOCKS[lvl]
		if defs then
			for _, u in defs do
				table.insert(unlocks, u)
			end
		end
	end

	-- ── ScreenGui ─────────────────────────────────────────────────────
	local gui = Instance.new("ScreenGui")
	gui.Name = "LevelUpGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui
	activeGui = gui

	-- ── Dark backdrop ────────────────────────────────────────────────
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.BackgroundColor3 = COLOR_BG
	backdrop.BackgroundTransparency = 0.25
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.Parent = gui

	-- ── Central panel ────────────────────────────────────────────────
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = COLOR_PANEL
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromOffset(420, 0) -- height set dynamically
	-- Start above the screen for slide-in animation
	panel.Position = UDim2.new(0.5, 0, -0.5, 0)
	panel.Parent = gui
	corner(panel, 14)
	stroke(panel, 2, COLOR_PANEL_EDGE)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, 24)
	pad.PaddingBottom = UDim.new(0, 24)
	pad.PaddingLeft   = UDim.new(0, 28)
	pad.PaddingRight  = UDim.new(0, 28)
	pad.Parent = panel

	-- ── Title: "Your level has increased!" ───────────────────────────
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 30)
	title.Position = UDim2.fromOffset(0, 0)
	title.Font = FONT_TITLE
	title.TextSize = 24
	title.TextColor3 = COLOR_GOLD
	title.Text = "Your level has increased!"
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Parent = panel

	-- ── Level transition: "3 -> 4" ───────────────────────────────────
	local levelText = Instance.new("TextLabel")
	levelText.BackgroundTransparency = 1
	levelText.Size = UDim2.new(1, 0, 0, 36)
	levelText.Position = UDim2.fromOffset(0, 36)
	levelText.Font = FONT_TITLE
	levelText.TextSize = 32
	levelText.TextColor3 = COLOR_ACCENT
	levelText.Text = tostring(oldLevel) .. "  →  " .. tostring(newLevel)
	levelText.TextXAlignment = Enum.TextXAlignment.Center
	levelText.Parent = panel

	local yOffset = 86

	-- ── Instant Rewards section ──────────────────────────────────────
	local rewardsLabel = Instance.new("TextLabel")
	rewardsLabel.BackgroundTransparency = 1
	rewardsLabel.Size = UDim2.new(1, 0, 0, 22)
	rewardsLabel.Position = UDim2.fromOffset(0, yOffset)
	rewardsLabel.Font = FONT_TITLE
	rewardsLabel.TextSize = 16
	rewardsLabel.TextColor3 = COLOR_TEXT_DIM
	rewardsLabel.Text = "Instant Rewards"
	rewardsLabel.TextXAlignment = Enum.TextXAlignment.Left
	rewardsLabel.Parent = panel

	yOffset = yOffset + 28

	-- Rewards row container
	local rewardsRow = Instance.new("Frame")
	rewardsRow.BackgroundColor3 = COLOR_BAR_BG
	rewardsRow.BackgroundTransparency = 0.3
	rewardsRow.BorderSizePixel = 0
	rewardsRow.Size = UDim2.new(1, 0, 0, 56)
	rewardsRow.Position = UDim2.fromOffset(0, yOffset)
	rewardsRow.Parent = panel
	corner(rewardsRow, 8)

	-- Reward items laid out horizontally
	local rewardDefs = {
		{ icon = ICON_UPGRADE_PT, text = "+1 Upgrade Point" },
		{ icon = ICON_LOG,        text = "+5 Logs" },
	}

	local rewardItemWidth = math.floor(364 / #rewardDefs)
	for i, def in rewardDefs do
		local item = Instance.new("Frame")
		item.BackgroundTransparency = 1
		item.Size = UDim2.fromOffset(rewardItemWidth, 56)
		item.Position = UDim2.fromOffset((i - 1) * rewardItemWidth, 0)
		item.Parent = rewardsRow

		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromOffset(36, 36)
		icon.Position = UDim2.fromOffset(12, 10)
		icon.Image = def.icon
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = item

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(1, -56, 0, 56)
		lbl.Position = UDim2.fromOffset(54, 0)
		lbl.Font = FONT_BODY
		lbl.TextSize = 14
		lbl.TextColor3 = COLOR_TEXT
		lbl.Text = def.text
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = item
	end

	yOffset = yOffset + 68

	-- ── Unlocked section (only if there are unlocks) ─────────────────
	if #unlocks > 0 then
		local unlockLabel = Instance.new("TextLabel")
		unlockLabel.BackgroundTransparency = 1
		unlockLabel.Size = UDim2.new(1, 0, 0, 22)
		unlockLabel.Position = UDim2.fromOffset(0, yOffset)
		unlockLabel.Font = FONT_TITLE
		unlockLabel.TextSize = 16
		unlockLabel.TextColor3 = COLOR_GOLD
		unlockLabel.Text = "Unlocked"
		unlockLabel.TextXAlignment = Enum.TextXAlignment.Left
		unlockLabel.Parent = panel

		yOffset = yOffset + 28

		-- Unlocked items row
		local unlockRow = Instance.new("Frame")
		unlockRow.BackgroundColor3 = COLOR_BAR_BG
		unlockRow.BackgroundTransparency = 0.3
		unlockRow.BorderSizePixel = 0
		unlockRow.Size = UDim2.new(1, 0, 0, 80)
		unlockRow.Position = UDim2.fromOffset(0, yOffset)
		unlockRow.Parent = panel
		corner(unlockRow, 8)

		-- Layout unlock items evenly
		local itemWidth = math.floor(364 / math.max(#unlocks, 1))
		for i, u in unlocks do
			local cell = Instance.new("Frame")
			cell.BackgroundTransparency = 1
			cell.Size = UDim2.fromOffset(itemWidth, 80)
			cell.Position = UDim2.fromOffset((i - 1) * itemWidth, 0)
			cell.Parent = unlockRow

			local icon = Instance.new("ImageLabel")
			icon.BackgroundTransparency = 1
			icon.Size = UDim2.fromOffset(44, 44)
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.Position = UDim2.new(0.5, 0, 0, 6)
			icon.Image = u.icon
			icon.ScaleType = Enum.ScaleType.Fit
			icon.Parent = cell

			local nameLbl = Instance.new("TextLabel")
			nameLbl.BackgroundTransparency = 1
			nameLbl.Size = UDim2.new(1, 0, 0, 18)
			nameLbl.Position = UDim2.fromOffset(0, 54)
			nameLbl.Font = FONT_BODY
			nameLbl.TextSize = 13
			nameLbl.TextColor3 = COLOR_TEXT
			nameLbl.Text = u.name
			nameLbl.TextXAlignment = Enum.TextXAlignment.Center
			nameLbl.Parent = cell
		end

		yOffset = yOffset + 92
	end

	-- ── Continue button ──────────────────────────────────────────────
	yOffset = yOffset + 8
	local continueBtn = Instance.new("TextButton")
	continueBtn.Name = "ContinueButton"
	continueBtn.BackgroundColor3 = COLOR_BAR_BG
	continueBtn.BorderSizePixel = 0
	continueBtn.Size = UDim2.new(1, 0, 0, 36)
	continueBtn.Position = UDim2.fromOffset(0, yOffset)
	continueBtn.Font = FONT_TITLE
	continueBtn.TextSize = 17
	continueBtn.TextColor3 = COLOR_ACCENT
	continueBtn.Text = "Continue"
	continueBtn.AutoButtonColor = true
	continueBtn.Parent = panel
	corner(continueBtn, 8)
	stroke(continueBtn, 1.5, COLOR_PANEL_EDGE)

	yOffset = yOffset + 36

	-- Set final panel height (content + top/bottom padding)
	local totalHeight = yOffset + 24 + 24
	panel.Size = UDim2.fromOffset(420, totalHeight)

	-- ── ANIMATION: slide in from top ─────────────────────────────────
	local targetPos = UDim2.new(0.5, 0, 0.5, 0)

	local slideIn = TweenService:Create(
		panel,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = targetPos }
	)
	slideIn:Play()

	-- Also fade in the backdrop
	backdrop.BackgroundTransparency = 1
	TweenService:Create(
		backdrop,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.25 }
	):Play()

	-- ── Close handler ────────────────────────────────────────────────
	local function closeMenu()
		if not activeGui or activeGui ~= gui then return end

		-- Instant fade out: panel and backdrop transparency 0 → 1
		local fadePanel = TweenService:Create(
			panel,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		local fadeBackdrop = TweenService:Create(
			backdrop,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)

		-- Fade all text / images inside the panel
		for _, desc in panel:GetDescendants() do
			if desc:IsA("TextLabel") or desc:IsA("TextButton") then
				TweenService:Create(desc, TweenInfo.new(0.2), {
					TextTransparency = 1,
					BackgroundTransparency = 1,
				}):Play()
			elseif desc:IsA("ImageLabel") then
				TweenService:Create(desc, TweenInfo.new(0.2), {
					ImageTransparency = 1,
				}):Play()
			elseif desc:IsA("Frame") then
				TweenService:Create(desc, TweenInfo.new(0.2), {
					BackgroundTransparency = 1,
				}):Play()
			elseif desc:IsA("UIStroke") then
				TweenService:Create(desc, TweenInfo.new(0.2), {
					Transparency = 1,
				}):Play()
			end
		end

		fadePanel:Play()
		fadeBackdrop:Play()
		fadeBackdrop.Completed:Wait()

		gui:Destroy()
		if activeGui == gui then
			activeGui = nil
		end
	end

	continueBtn.MouseButton1Click:Connect(closeMenu)

	-- Also close on E or Escape
	local inputConn
	inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.E
			or input.KeyCode == Enum.KeyCode.Escape
			or input.KeyCode == Enum.KeyCode.Return then
			closeMenu()
			if inputConn then
				inputConn:Disconnect()
				inputConn = nil
			end
		end
	end)
end

-- ─── Listen for level-up events ──────────────────────────────────────────
levelUpEvent.OnClientEvent:Connect(showLevelUp)
