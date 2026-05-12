-- InventoryNotify.client.lua
-- Generic "+N item" notification stack — listens on the
-- InventoryNotify RemoteEvent and renders a Raft-style bottom-right
-- card for every inventory add the server reports. Used by tree
-- chopping, stone mining, ocean pulls, shovel digging, floor pickups,
-- fishing — anything that routes through _G.AddResourceToInventory.
-- Container takeouts (SmallContainerSystem / PlasticContainerSystem /
-- MercenaryEquipment) pass silent=true so chest extraction doesn't
-- spam this stack.
--
-- This file used to live inside StoneAxeClient.client.lua as the
-- chop-only notification path; it's now its own module so every
-- pickup gets the same UI without per-tool duplication.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local notifyEvent = ReplicatedStorage:WaitForChild("InventoryNotify")

-- ─── Resource → display-name overrides ───────────────────────────
-- Mirrors the small subset of overrides the inventory UI applies for
-- snake_case / multi-word items. Resources we don't list here render
-- using their raw name, which is fine for "Log", "Stone", "Plastic",
-- "Coconut", "Sapling", etc. that already read naturally.
local DISPLAY_NAMES = {
	Iron_Ore       = "Iron Ore",
	Iron_Ingot     = "Iron Ingot",
	Wet_Brick      = "Wet Brick",
	Dry_Brick      = "Dry Brick",
	Blue_Fish      = "Blue Fish",
	Carp_Fish      = "Carp Fish",
	Foil_Fish      = "Foil Fish",
	Jelly_Fish     = "Jelly Fish",
	Legendary_Fish = "Legendary Fish",
	Seabass_Fish   = "Seabass Fish",
	Tilapia_Fish   = "Tilapia Fish",
	Fish_Bones     = "Fish Bones",
	Wood_Knife     = "Wood Knife",
	["Pick-Axe"]   = "Pick-Axe",
	Stone_Axe      = "Stone Axe",
}

local function displayName(rawName)
	return DISPLAY_NAMES[rawName] or rawName
end

local function iconFor(rawName)
	-- _G.GetItemIcon is published by InventoryUI for the merc backpack
	-- + this notify stack. Returns "" for items without an asset id
	-- (Banana / Coconut / Sapling today) — the card still renders the
	-- count + name correctly.
	if typeof(_G.GetItemIcon) == "function" then
		return _G.GetItemIcon(rawName) or ""
	end
	return ""
end

-- ─── HUD root ────────────────────────────────────────────────────
local hud = Instance.new("ScreenGui")
hud.Name = "InventoryNotify"
hud.DisplayOrder = 60
hud.IgnoreGuiInset = true
hud.ResetOnSpawn = false
hud.Parent = playerGui

local NOTIF_LIFETIME = 3.0
local NOTIF_FADE     = 0.5
local NOTIF_HEIGHT   = 48
local NOTIF_WIDTH    = 220
local NOTIF_GAP      = 2

local container = Instance.new("Frame")
container.Name = "Stack"
container.AnchorPoint = Vector2.new(1, 1)
container.Position = UDim2.new(1, -16, 1, -110)   -- above the hotbar
container.Size = UDim2.fromOffset(NOTIF_WIDTH, 380)
container.BackgroundTransparency = 1
container.Parent = hud

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.VerticalAlignment   = Enum.VerticalAlignment.Bottom
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding   = UDim.new(0, NOTIF_GAP)
layout.Parent = container

-- ─── Per-item dedup ───────────────────────────────────────────────
-- Burst pickups (ocean pull → 3 logs in quick succession) shouldn't
-- spawn 3 separate cards. Track an active card per item name; if the
-- card still exists, bump its count instead of stacking duplicates.
local activeCards = {}    -- [itemName] = { card, countLabel, total, fadeAt }
local notifOrder  = 0

local function showNotif(rawName, count)
	if (count or 0) <= 0 then return end

	local existing = activeCards[rawName]
	if existing and existing.card.Parent then
		existing.total = existing.total + count
		existing.countLabel.Text = "+" .. tostring(existing.total)
		-- Reset the fade timer so the bumped total stays on screen
		-- the full lifetime, rather than fading at the original
		-- card's deadline.
		existing.bumpedAt = tick()
		return
	end

	notifOrder = notifOrder + 1

	-- Reference layout (from the user's screenshot): wide-ish beige
	-- parchment card, tight stacking, "+N" in big bold cream on the
	-- LEFT, icon centred horizontally inside the card, item name in
	-- the right column. Sharp corners (no UICorner), partly
	-- transparent from the start so the cards layer over the world
	-- like the reference, and text rendered with TextScaled so the
	-- content adapts to a fixed-size rectangle (the user's brief:
	-- "адаптация текста под прямоугольник, не наоборот").
	local card = Instance.new("Frame")
	card.Name = "Drop_" .. rawName
	card.Size = UDim2.fromOffset(NOTIF_WIDTH, NOTIF_HEIGHT)
	card.BackgroundColor3 = Color3.fromRGB(126, 100, 68)
	card.BackgroundTransparency = 0.2
	card.BorderSizePixel = 0
	card.LayoutOrder = notifOrder
	card.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(92, 64, 36)
	stroke.Thickness = 1.4
	stroke.Transparency = 0.1
	stroke.Parent = card

	-- Tight three-column layout: "+N" • icon • name. The name
	-- column gets a large MaxTextSize so short names ("Log",
	-- "Stone") grow with TextScaled to fill the column without
	-- leaving a big empty gap on the right — the user explicitly
	-- asked for "no empty space at all".
	local PAD_LEFT   = 8
	local COUNT_W    = 36
	local ICON_GAP   = 4
	local ICON_SIZE  = NOTIF_HEIGHT - 12   -- 36 px in a 48 px card
	local NAME_GAP   = 6
	local PAD_RIGHT  = 6

	-- Fixed text sizes (not TextScaled) so every card reads the
	-- same regardless of name length. The user complained the
	-- previous TextScaled path produced unreadable "Log" when a
	-- longer name in another card pulled the auto-scaled size
	-- down. 26 px for "+N", 22 px for the name — both safely
	-- readable at the 48 px card height.
	-- Count uses TextScaled so the number adapts to the column:
	-- "+1" renders at full 26 px, "+30" / "+999" shrink down to fit
	-- without bleeding into the icon. The size constraint caps the
	-- upper end so short text doesn't blow up into a giant glyph.
	local countLabel = Instance.new("TextLabel")
	countLabel.Position = UDim2.fromOffset(PAD_LEFT, 0)
	countLabel.Size = UDim2.fromOffset(COUNT_W, NOTIF_HEIGHT)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "+" .. tostring(count)
	countLabel.TextColor3 = Color3.fromRGB(250, 240, 215)
	countLabel.TextScaled = true
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextXAlignment = Enum.TextXAlignment.Left
	countLabel.TextYAlignment = Enum.TextYAlignment.Center
	countLabel.Parent = card

	local countSizeCap = Instance.new("UITextSizeConstraint")
	countSizeCap.MaxTextSize = 26
	countSizeCap.MinTextSize = 12
	countSizeCap.Parent = countLabel

	-- Icon column — vertically centred 30x30 box.
	local iconX = PAD_LEFT + COUNT_W + ICON_GAP
	local iconBox = Instance.new("ImageLabel")
	iconBox.Position = UDim2.fromOffset(iconX, (NOTIF_HEIGHT - ICON_SIZE) / 2)
	iconBox.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	iconBox.BackgroundTransparency = 1
	iconBox.Image = iconFor(rawName)
	iconBox.ScaleType = Enum.ScaleType.Fit
	iconBox.Parent = card

	-- Name column — fixed 22 px so the text is always readable.
	-- Wraps to two lines if a long name like "Пальмовый лист" or
	-- "Legendary Fish" can't fit a single 22 px line in the
	-- column. The 48 px card height comfortably hosts two 22 px
	-- lines with breathing room.
	local nameX = iconX + ICON_SIZE + NAME_GAP
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Position = UDim2.fromOffset(nameX, 0)
	nameLabel.Size = UDim2.fromOffset(NOTIF_WIDTH - nameX - PAD_RIGHT, NOTIF_HEIGHT)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayName(rawName)
	nameLabel.TextColor3 = Color3.fromRGB(250, 240, 215)
	nameLabel.TextSize = 22
	nameLabel.Font = Enum.Font.GothamSemibold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.TextWrapped = true
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card

	local rec = {
		card       = card,
		countLabel = countLabel,
		total      = count,
		bumpedAt   = tick(),
	}
	activeCards[rawName] = rec

	task.spawn(function()
		-- Polling fade: re-check bumpedAt each loop so a fresh pickup
		-- on the same item resets the timer cleanly. Card lifetime is
		-- measured from the most recent bump.
		while card.Parent do
			local since = tick() - rec.bumpedAt
			if since >= NOTIF_LIFETIME then break end
			task.wait(NOTIF_LIFETIME - since)
		end
		if not card.Parent then return end
		local steps = 10
		for i = 0, steps do
			if not card.Parent then return end
			local a = i / steps
			card.BackgroundTransparency = 0.2 + a * 0.8
			stroke.Transparency        = 0.1 + a * 0.9
			countLabel.TextTransparency = a
			nameLabel.TextTransparency  = a
			iconBox.ImageTransparency   = a
			task.wait(NOTIF_FADE / steps)
		end
		if card.Parent then card:Destroy() end
		if activeCards[rawName] == rec then
			activeCards[rawName] = nil
		end
	end)
end

notifyEvent.OnClientEvent:Connect(function(itemName, count)
	if typeof(itemName) ~= "string" or itemName == "" then return end
	if (tonumber(count) or 0) <= 0 then return end
	showNotif(itemName, count)
end)
