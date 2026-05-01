-- WorkbenchUI.client.lua
-- Crafting menu for the workbench. Wood/paper styling matches QuestMenu
-- and OnboardingTooltip so all the in-world UIs read as one set.
--
-- Layout: tab rail (categories + search) on the left, scrolling recipe
-- grid in the centre, detail panel with quantity stepper on the right.
-- A small material strip floats below the panel as a quick inventory
-- readout. Lazy-builds on first open and toggles ScreenGui.Enabled
-- afterwards so we don't pay to rebuild every time the player walks
-- up to the bench.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local craftEvent         = ReplicatedStorage:WaitForChild("CraftItem")
local inventoryEvent     = ReplicatedStorage:WaitForChild("InventoryUpdate")
local openWorkbenchEvent = ReplicatedStorage:WaitForChild("OpenWorkbench")

-- ─── Wood/paper palette (matches QuestMenu) ─────────────────────────
local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_WOOD_DARK    = Color3.fromRGB( 91,  58,  34)
local COLOR_WOOD_MID     = Color3.fromRGB(138, 106,  68)
local COLOR_WOOD_BASE    = Color3.fromRGB(176, 138,  92)
local COLOR_PAPER        = Color3.fromRGB(233, 217, 184)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(243, 230, 204)
local COLOR_GREEN_OK     = Color3.fromRGB( 96, 148,  72)
local COLOR_RED_BAD      = Color3.fromRGB(168,  64,  56)

-- ─── Layout constants ───────────────────────────────────────────────
local SCREENGUI_DISPLAY_ORDER = 105
local PANEL_W      = 820
local PANEL_H      = 500
local PANEL_RADIUS = 18
local PANEL_PAD    = 14

local TAB_RAIL_W = 140
local DETAIL_W   = 240
local CONTENT_GAP = 12
-- Top strip inside the panel reserved for the close button. Pushes
-- the three columns down so they line up below the X with breathing
-- room, instead of having the X overlap the column edges.
local HEADER_STRIP_H = 32

local TAB_HEIGHT = 42
local TAB_GAP    = 6
local TAB_RADIUS = 10
local TAB_DOT_SIZE  = 6
local TAB_DOT_INSET = 12

local SEARCH_HEIGHT = 34
local CARD_W = 110
local CARD_H = 130
local CARD_GAP = 12
local CARD_RADIUS = 10

local CLOSE_BTN_SIZE   = 28
local CLOSE_BTN_RADIUS = 8

local INVENTORY_BAR_H = 56

-- ─── Asset ids ──────────────────────────────────────────────────────
local LOG_ICON = "rbxassetid://110032041583533"
local COST_ICONS = {
	Log         = LOG_ICON,
	Stone       = "rbxassetid://134781813180973",
	Plastic     = "rbxassetid://132919988751848",
	Iron_Ore    = "rbxassetid://73676755288746",
	Iron_Ingot  = "rbxassetid://72890243946368",
	Plank       = "rbxassetid://118108820731466",
	Leaves      = "rbxassetid://96691360298069",
	Rope        = "rbxassetid://78492721752628",
	Sand        = "rbxassetid://92407877736322",
	Clay        = "rbxassetid://129473903672183",
	Wet_Brick   = "rbxassetid://77999856849195",
	Dry_Brick   = "rbxassetid://129896663405682",
}

-- ─── Recipe catalog (client-side, mirrors CraftingSystem) ───────────
-- category drives the tab filter; description is shown in the right
-- detail panel. Server is the source of truth for whether a recipe is
-- actually craftable — entries here just need to match by `name`.
local recipes = {
	{ name = "Wood_Knife",       displayName = "Wood Knife",       icon = "rbxassetid://110032041583533", costs = {Log = 2},                category = "tools",      description = "A sharp blade with a wooden handle. Useful for cutting things." },
	{ name = "Bed",              displayName = "Bed",              icon = "rbxassetid://85069521486600",  costs = {Log = 2},                category = "structures", description = "A simple bed for resting and setting your respawn." },
	{ name = "Furnace",          displayName = "Furnace",          icon = "rbxassetid://117760352651529", costs = {Stone = 10, Log = 5},    category = "structures", description = "Smelts ores into usable ingots." },
	{ name = "Sawmill",          displayName = "Sawmill",          icon = "rbxassetid://75858978626954",  costs = {Log = 1},                category = "structures", description = "Processes logs into planks." },
	{ name = "SmallContainer",   displayName = "Small Container",  icon = "rbxassetid://86632287242518",  costs = {Log = 1},                category = "storage",    description = "A small container for storing items." },
	{ name = "PlasticContainer", displayName = "Plastic Container", icon = "rbxassetid://98308527317479", costs = {Plastic = 5},            category = "storage",    description = "A large container for storing items." },
	{ name = "Anchor_part",      displayName = "Anchor",           icon = "rbxassetid://120414328052740", costs = {Log = 1},                category = "structures", description = "Stops the raft from drifting on the current." },
}

local CATEGORIES = {
	{ id = "all",        label = "All",        glyph = "▦" },
	{ id = "tools",      label = "Tools",      glyph = "🔨" },
	{ id = "storage",    label = "Storage",    glyph = "📦" },
	{ id = "structures", label = "Structures", glyph = "🏠" },
	{ id = "equipment",  label = "Equipment",  glyph = "🛡" },
	{ id = "decor",      label = "Decor",      glyph = "🌿" },
}

-- Materials shown in the floating bottom strip. Order = display order.
local INVENTORY_BAR_ITEMS = { "Log", "Plank", "Stone", "Plastic", "Rope" }

-- ─── State ──────────────────────────────────────────────────────────
local inventory       = {}
local selectedRecipe  = nil
local craftQuantity   = 1
local activeCategory  = "all"
local searchQuery     = ""
local isOpen          = false

-- ─── UI handles ─────────────────────────────────────────────────────
local screenGui
local backdrop
local panel
local panelScale
local categoryHandles      -- [id] = { tile, glyph, label, dot, stroke }
local recipeListFrame      -- ScrollingFrame holding recipe cards
local recipeCards          -- [name] = { card, refs }
local searchBox
local detailPanel
local detailRefs           -- bag of detail-panel widget refs
local invBarRefs           -- [item] = { count, icon }
local fadeTargets
local backdropFadeTarget

-- Forward declarations so build* closures can reference these before
-- their real implementations are defined further down. Reassigned in
-- place so click handlers always see the latest version.
local closeUI
local repaintRecipeList
local repaintDetailPanel
local repaintSelectionStrokes

-- ─── Helpers ────────────────────────────────────────────────────────
local function canAfford(recipe, qty)
	if not recipe or not recipe.costs then return false end
	qty = qty or 1
	for item, amount in recipe.costs do
		if (inventory[item] or 0) < amount * qty then
			return false
		end
	end
	return true
end

local function maxCraftable(recipe)
	if not recipe or not recipe.costs then return 0 end
	local m = math.huge
	for item, amount in recipe.costs do
		if amount > 0 then
			local can = math.floor((inventory[item] or 0) / amount)
			if can < m then m = can end
		end
	end
	if m == math.huge then return 0 end
	return m
end

local function recipeMatchesFilter(r)
	if activeCategory ~= "all" and r.category ~= activeCategory then
		return false
	end
	if searchQuery ~= "" then
		local hay = string.lower(r.displayName or r.name or "")
		if not string.find(hay, searchQuery, 1, true) then
			return false
		end
	end
	return true
end

-- ─── Panel shell ────────────────────────────────────────────────────
local function buildBackdrop(parent)
	backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.55
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.ZIndex = 1
	backdrop.Parent = parent

	backdrop.MouseButton1Click:Connect(function()
		if isOpen and closeUI then
			closeUI()
		end
	end)
end

local function buildCloseButton(parent)
	local btn = Instance.new("TextButton")
	btn.Name = "CloseButton"
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, PANEL_PAD - 8, 0, -(PANEL_PAD - 8))
	btn.Size = UDim2.fromOffset(CLOSE_BTN_SIZE, CLOSE_BTN_SIZE)
	btn.BackgroundColor3 = COLOR_WOOD_MID
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.ZIndex = 12
	btn.Parent = parent

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, CLOSE_BTN_RADIUS)
	c.Parent = btn

	local s = Instance.new("UIStroke")
	s.Color = COLOR_WOOD_DARK
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = btn

	local g = Instance.new("TextLabel")
	g.BackgroundTransparency = 1
	g.Size = UDim2.fromScale(1, 1)
	g.Font = Enum.Font.GothamBold
	g.TextSize = 16
	g.TextColor3 = COLOR_PAPER_LIGHT
	g.Text = "✕"
	g.ZIndex = 13
	g.Parent = btn

	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = COLOR_WOOD_DARK
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = COLOR_WOOD_MID
	end)
	btn.MouseButton1Click:Connect(function()
		if closeUI then closeUI() end
	end)
end

-- ─── Tab rail ───────────────────────────────────────────────────────
local function paintCategoryTab(id)
	local h = categoryHandles and categoryHandles[id]
	if not h then return end
	-- Both states use dark wood text on a paper-tinted button — only
	-- the fill brightness + stroke weight change so the rail reads as
	-- a coherent set of paper buttons (matches the reference design).
	if id == activeCategory then
		h.tile.BackgroundColor3       = COLOR_PAPER_LIGHT
		h.tile.BackgroundTransparency = 0
		h.stroke.Color                = COLOR_WOOD_DARKEST
		h.stroke.Thickness            = 2
		h.label.TextColor3            = COLOR_WOOD_DARKEST
		h.glyph.TextColor3            = COLOR_WOOD_DARKEST
		h.dot.Visible                 = true
	else
		h.tile.BackgroundColor3       = COLOR_PAPER_LIGHT
		h.tile.BackgroundTransparency = 0.45
		h.stroke.Color                = COLOR_WOOD_DARK
		h.stroke.Thickness            = 1.5
		h.label.TextColor3            = COLOR_WOOD_DARKEST
		h.glyph.TextColor3            = COLOR_WOOD_DARKEST
		h.dot.Visible                 = false
	end
end

local function repaintAllCategoryTabs()
	if not categoryHandles then return end
	for id in pairs(categoryHandles) do
		paintCategoryTab(id)
	end
end

local function setActiveCategory(id)
	if activeCategory == id then return end
	activeCategory = id
	repaintAllCategoryTabs()
	if repaintRecipeList then repaintRecipeList() end
end

local function buildSearchBox(parent, y)
	local box = Instance.new("Frame")
	box.Name = "SearchBox"
	box.AnchorPoint = Vector2.new(0, 1)
	box.Position = UDim2.new(0, 0, 1, 0)
	box.Size = UDim2.new(1, 0, 0, SEARCH_HEIGHT)
	box.BackgroundColor3 = COLOR_PAPER
	box.BackgroundTransparency = 0.25
	box.BorderSizePixel = 0
	box.ZIndex = 5
	box.Parent = parent

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = box

	local s = Instance.new("UIStroke")
	s.Color = COLOR_WOOD_DARK
	s.Thickness = 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = box

	local glyph = Instance.new("TextLabel")
	glyph.BackgroundTransparency = 1
	glyph.AnchorPoint = Vector2.new(0, 0.5)
	glyph.Position = UDim2.new(0, 10, 0.5, 0)
	glyph.Size = UDim2.fromOffset(18, 18)
	glyph.Font = Enum.Font.GothamBold
	glyph.TextSize = 14
	glyph.TextColor3 = COLOR_WOOD_DARK
	glyph.Text = "⌕"
	glyph.ZIndex = 6
	glyph.Parent = box

	local input = Instance.new("TextBox")
	input.Name = "Input"
	input.AnchorPoint = Vector2.new(0, 0.5)
	input.Position = UDim2.new(0, 32, 0.5, 0)
	input.Size = UDim2.new(1, -40, 1, -8)
	input.BackgroundTransparency = 1
	input.Font = Enum.Font.Gotham
	input.TextSize = 13
	input.TextColor3 = COLOR_WOOD_DARKEST
	input.PlaceholderColor3 = COLOR_WOOD_MID
	input.PlaceholderText = "Search..."
	input.ClearTextOnFocus = false
	input.Text = ""
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.ZIndex = 6
	input.Parent = box

	input:GetPropertyChangedSignal("Text"):Connect(function()
		searchQuery = string.lower(input.Text or "")
		if repaintRecipeList then repaintRecipeList() end
	end)

	searchBox = input
	return box
end

local function buildTabRail(parent)
	-- Rail fills the parent (railHolder applies its own UIPadding so
	-- this Frame sits inside the holder's padded inner box).
	local rail = Instance.new("Frame")
	rail.Name = "CategoryRail"
	rail.AnchorPoint = Vector2.new(0, 0)
	rail.Position = UDim2.fromOffset(0, 0)
	rail.Size = UDim2.fromScale(1, 1)
	rail.BackgroundTransparency = 1
	rail.BorderSizePixel = 0
	rail.ZIndex = 4
	rail.Parent = parent

	categoryHandles = {}

	local listHeight = #CATEGORIES * TAB_HEIGHT + (#CATEGORIES - 1) * TAB_GAP

	for i, cat in ipairs(CATEGORIES) do
		local y = (i - 1) * (TAB_HEIGHT + TAB_GAP)

		local tile = Instance.new("TextButton")
		tile.Name = "Cat_" .. cat.id
		tile.AnchorPoint = Vector2.new(0, 0)
		tile.Position = UDim2.fromOffset(0, y)
		tile.Size = UDim2.new(1, 0, 0, TAB_HEIGHT)
		tile.AutoButtonColor = false
		tile.BackgroundTransparency = 1
		tile.BorderSizePixel = 0
		tile.Text = ""
		tile.ZIndex = 5
		tile.Parent = rail

		local tCorner = Instance.new("UICorner")
		tCorner.CornerRadius = UDim.new(0, TAB_RADIUS)
		tCorner.Parent = tile

		local tStroke = Instance.new("UIStroke")
		tStroke.Color = COLOR_WOOD_DARK
		tStroke.Thickness = 1.5
		tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tStroke.Parent = tile

		local glyph = Instance.new("TextLabel")
		glyph.Name = "Glyph"
		glyph.AnchorPoint = Vector2.new(0, 0.5)
		glyph.Position = UDim2.new(0, 12, 0.5, 0)
		glyph.Size = UDim2.fromOffset(20, 20)
		glyph.BackgroundTransparency = 1
		glyph.Font = Enum.Font.GothamBold
		glyph.TextSize = 18
		glyph.TextColor3 = COLOR_WOOD_DARKEST
		glyph.Text = cat.glyph or ""
		glyph.ZIndex = tile.ZIndex + 1
		glyph.Parent = tile

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.new(0, 38, 0.5, 0)
		label.Size = UDim2.new(1, -38 - (TAB_DOT_INSET + TAB_DOT_SIZE + 4), 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 16
		label.TextColor3 = COLOR_WOOD_DARKEST
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = cat.label
		label.ZIndex = tile.ZIndex + 1
		label.Parent = tile

		local dot = Instance.new("Frame")
		dot.Name = "ActiveDot"
		dot.AnchorPoint = Vector2.new(1, 0.5)
		dot.Position = UDim2.new(1, -TAB_DOT_INSET, 0.5, 0)
		dot.Size = UDim2.fromOffset(TAB_DOT_SIZE, TAB_DOT_SIZE)
		dot.BackgroundColor3 = COLOR_WOOD_DARK
		dot.BorderSizePixel = 0
		dot.Visible = false
		dot.ZIndex = tile.ZIndex + 2
		dot.Parent = tile
		local dCorner = Instance.new("UICorner")
		dCorner.CornerRadius = UDim.new(1, 0)
		dCorner.Parent = dot

		categoryHandles[cat.id] = {
			tile = tile, glyph = glyph, label = label, dot = dot, stroke = tStroke,
		}

		tile.MouseButton1Click:Connect(function()
			setActiveCategory(cat.id)
		end)
		tile.MouseEnter:Connect(function()
			if cat.id == activeCategory then return end
			tile.BackgroundColor3       = COLOR_PAPER_LIGHT
			tile.BackgroundTransparency = 0.15
		end)
		tile.MouseLeave:Connect(function()
			paintCategoryTab(cat.id)
		end)
	end

	-- Search box pinned to the bottom of the rail.
	buildSearchBox(rail, listHeight + 12)

	repaintAllCategoryTabs()
	return rail
end

-- ─── Recipe card ────────────────────────────────────────────────────
local function buildRecipeCard(parent, recipe)
	local card = Instance.new("TextButton")
	card.Name = "Recipe_" .. recipe.name
	card.AutoButtonColor = false
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundColor3 = COLOR_PAPER
	card.BackgroundTransparency = 0
	card.BorderSizePixel = 0
	card.Text = ""
	card.ZIndex = 7
	card.Parent = parent

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0, CARD_RADIUS)
	cCorner.Parent = card

	local cStroke = Instance.new("UIStroke")
	cStroke.Color = COLOR_WOOD_DARK
	cStroke.Thickness = 1.5
	cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cStroke.Parent = card

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 8)
	icon.Size = UDim2.fromOffset(56, 56)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = recipe.icon or ""
	icon.ZIndex = card.ZIndex + 1
	icon.Parent = card

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 0, 70)
	name.Size = UDim2.new(1, -10, 0, 16)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 12
	name.TextColor3 = COLOR_WOOD_DARKEST
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = recipe.displayName or recipe.name
	name.ZIndex = card.ZIndex + 1
	name.Parent = card

	-- Cost row at the bottom of the card. Built dynamically from
	-- recipe.costs so multi-resource recipes (Furnace) get one icon
	-- + count chip per resource.
	local costRow = Instance.new("Frame")
	costRow.Name = "CostRow"
	costRow.AnchorPoint = Vector2.new(0.5, 1)
	costRow.Position = UDim2.new(0.5, 0, 1, -8)
	costRow.Size = UDim2.new(1, -10, 0, 18)
	costRow.BackgroundTransparency = 1
	costRow.ZIndex = card.ZIndex + 1
	costRow.Parent = card

	local costLayout = Instance.new("UIListLayout")
	costLayout.FillDirection = Enum.FillDirection.Horizontal
	costLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	costLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	costLayout.Padding = UDim.new(0, 6)
	costLayout.SortOrder = Enum.SortOrder.LayoutOrder
	costLayout.Parent = costRow

	local costEntries = {}
	local order = 0
	for item, amount in recipe.costs do
		order = order + 1
		local entry = Instance.new("Frame")
		entry.BackgroundTransparency = 1
		entry.Size = UDim2.fromOffset(40, 18)
		entry.LayoutOrder = order
		entry.ZIndex = card.ZIndex + 1
		entry.Parent = costRow

		local cIcon = Instance.new("ImageLabel")
		cIcon.AnchorPoint = Vector2.new(0, 0.5)
		cIcon.Position = UDim2.new(0, 0, 0.5, 0)
		cIcon.Size = UDim2.fromOffset(16, 16)
		cIcon.BackgroundTransparency = 1
		cIcon.ScaleType = Enum.ScaleType.Fit
		cIcon.Image = COST_ICONS[item] or ""
		cIcon.ZIndex = card.ZIndex + 2
		cIcon.Parent = entry

		local cLabel = Instance.new("TextLabel")
		cLabel.AnchorPoint = Vector2.new(0, 0.5)
		cLabel.Position = UDim2.new(0, 19, 0.5, 0)
		cLabel.Size = UDim2.new(1, -19, 1, 0)
		cLabel.BackgroundTransparency = 1
		cLabel.Font = Enum.Font.GothamBold
		cLabel.TextSize = 12
		cLabel.TextColor3 = COLOR_WOOD_DARKEST
		cLabel.TextXAlignment = Enum.TextXAlignment.Left
		cLabel.Text = tostring(amount)
		cLabel.ZIndex = card.ZIndex + 2
		cLabel.Parent = entry

		table.insert(costEntries, { item = item, amount = amount, label = cLabel, icon = cIcon })
	end

	return card, {
		card = card, stroke = cStroke, icon = icon, name = name, costEntries = costEntries,
	}
end

local function selectRecipe(recipe)
	selectedRecipe = recipe
	craftQuantity = 1
	if repaintSelectionStrokes then repaintSelectionStrokes() end
	if repaintDetailPanel then repaintDetailPanel() end
end

local function buildRecipeList(parent)
	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "RecipeList"
	listFrame.AnchorPoint = Vector2.new(0, 0)
	listFrame.Position = UDim2.fromOffset(0, 0)
	listFrame.Size = UDim2.fromScale(1, 1)
	listFrame.BackgroundColor3 = COLOR_PAPER
	listFrame.BackgroundTransparency = 0.35
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 4
	listFrame.ScrollBarImageColor3 = COLOR_WOOD_DARK
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.CanvasSize = UDim2.new()
	listFrame.ZIndex = 5
	listFrame.Parent = parent

	local lCorner = Instance.new("UICorner")
	lCorner.CornerRadius = UDim.new(0, 12)
	lCorner.Parent = listFrame

	local lStroke = Instance.new("UIStroke")
	lStroke.Color = COLOR_WOOD_DARK
	lStroke.Thickness = 2
	lStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	lStroke.Parent = listFrame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft   = UDim.new(0, 12)
	pad.PaddingRight  = UDim.new(0, 12)
	pad.Parent = listFrame

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
	grid.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.Parent = listFrame

	recipeListFrame = listFrame
	recipeCards = {}

	for _, r in ipairs(recipes) do
		local card, refs = buildRecipeCard(listFrame, r)
		recipeCards[r.name] = refs
		card.MouseButton1Click:Connect(function()
			selectRecipe(r)
		end)
	end

	return listFrame
end

-- ─── Detail panel ──────────────────────────────────────────────────
local function buildDetailPanel(parent)
	local d = Instance.new("Frame")
	d.Name = "DetailPanel"
	d.Size = UDim2.new(1, 0, 1, 0)
	d.BackgroundColor3 = COLOR_PAPER
	d.BackgroundTransparency = 0.15
	d.BorderSizePixel = 0
	d.ZIndex = 5
	d.Parent = parent

	local dCorner = Instance.new("UICorner")
	dCorner.CornerRadius = UDim.new(0, 12)
	dCorner.Parent = d

	local dStroke = Instance.new("UIStroke")
	dStroke.Color = COLOR_WOOD_DARK
	dStroke.Thickness = 2
	dStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dStroke.Parent = d

	local dPad = Instance.new("UIPadding")
	dPad.PaddingTop    = UDim.new(0, 14)
	dPad.PaddingBottom = UDim.new(0, 14)
	dPad.PaddingLeft   = UDim.new(0, 14)
	dPad.PaddingRight  = UDim.new(0, 14)
	dPad.Parent = d

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Position = UDim2.fromOffset(0, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = COLOR_WOOD_DARKEST
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = ""
	title.ZIndex = 6
	title.Parent = d

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 32)
	icon.Size = UDim2.fromOffset(110, 110)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = ""
	icon.ZIndex = 6
	icon.Parent = d

	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.AnchorPoint = Vector2.new(0, 0)
	desc.Position = UDim2.fromOffset(0, 150)
	desc.Size = UDim2.new(1, 0, 0, 40)
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 12
	desc.TextColor3 = COLOR_WOOD_DARK
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.Text = ""
	desc.ZIndex = 6
	desc.Parent = d

	local reqHeader = Instance.new("TextLabel")
	reqHeader.Name = "RequiresHeader"
	reqHeader.AnchorPoint = Vector2.new(0, 0)
	reqHeader.Position = UDim2.fromOffset(0, 196)
	reqHeader.Size = UDim2.new(1, 0, 0, 16)
	reqHeader.BackgroundTransparency = 1
	reqHeader.Font = Enum.Font.GothamBold
	reqHeader.TextSize = 13
	reqHeader.TextColor3 = COLOR_WOOD_DARKEST
	reqHeader.TextXAlignment = Enum.TextXAlignment.Left
	reqHeader.Text = "Requires"
	reqHeader.ZIndex = 6
	reqHeader.Parent = d

	local reqList = Instance.new("Frame")
	reqList.Name = "RequiresList"
	reqList.AnchorPoint = Vector2.new(0, 0)
	reqList.Position = UDim2.fromOffset(0, 216)
	reqList.Size = UDim2.new(1, 0, 0, 70)
	reqList.BackgroundColor3 = COLOR_PAPER_LIGHT
	reqList.BackgroundTransparency = 0.35
	reqList.BorderSizePixel = 0
	reqList.ZIndex = 6
	reqList.Parent = d
	local rCorner = Instance.new("UICorner")
	rCorner.CornerRadius = UDim.new(0, 8)
	rCorner.Parent = reqList
	local rPad = Instance.new("UIPadding")
	rPad.PaddingTop = UDim.new(0, 8)
	rPad.PaddingBottom = UDim.new(0, 8)
	rPad.PaddingLeft = UDim.new(0, 10)
	rPad.PaddingRight = UDim.new(0, 10)
	rPad.Parent = reqList
	local rLayout = Instance.new("UIListLayout")
	rLayout.FillDirection = Enum.FillDirection.Vertical
	rLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rLayout.Padding = UDim.new(0, 4)
	rLayout.Parent = reqList

	-- Quantity stepper
	local stepRow = Instance.new("Frame")
	stepRow.Name = "Stepper"
	stepRow.AnchorPoint = Vector2.new(0, 1)
	stepRow.Position = UDim2.new(0, 0, 1, -54)
	stepRow.Size = UDim2.new(1, 0, 0, 38)
	stepRow.BackgroundTransparency = 1
	stepRow.ZIndex = 6
	stepRow.Parent = d

	local function makeStepBtn(name, glyph, posX)
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.fromOffset(38, 38)
		b.Position = UDim2.fromOffset(posX, 0)
		b.AutoButtonColor = false
		b.BackgroundColor3 = COLOR_PAPER_LIGHT
		b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBold
		b.TextSize = 18
		b.TextColor3 = COLOR_WOOD_DARKEST
		b.Text = glyph
		b.ZIndex = 7
		b.Parent = stepRow
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
		local s = Instance.new("UIStroke"); s.Color = COLOR_WOOD_DARK; s.Thickness = 1.5
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = b
		return b
	end

	local minusBtn = makeStepBtn("Minus", "−", 0)
	local qtyLabel = Instance.new("TextLabel")
	qtyLabel.Name = "Qty"
	qtyLabel.AnchorPoint = Vector2.new(0.5, 0)
	qtyLabel.Position = UDim2.new(0.5, 0, 0, 0)
	qtyLabel.Size = UDim2.fromOffset(80, 38)
	qtyLabel.BackgroundColor3 = COLOR_PAPER_LIGHT
	qtyLabel.BackgroundTransparency = 0.2
	qtyLabel.BorderSizePixel = 0
	qtyLabel.Font = Enum.Font.GothamBold
	qtyLabel.TextSize = 18
	qtyLabel.TextColor3 = COLOR_WOOD_DARKEST
	qtyLabel.Text = "1"
	qtyLabel.ZIndex = 7
	qtyLabel.Parent = stepRow
	local qC = Instance.new("UICorner"); qC.CornerRadius = UDim.new(0, 8); qC.Parent = qtyLabel
	local qS = Instance.new("UIStroke"); qS.Color = COLOR_WOOD_DARK; qS.Thickness = 1.5
	qS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; qS.Parent = qtyLabel

	local plusBtn = Instance.new("TextButton")
	plusBtn.Name = "Plus"
	plusBtn.AnchorPoint = Vector2.new(1, 0)
	plusBtn.Position = UDim2.new(1, 0, 0, 0)
	plusBtn.Size = UDim2.fromOffset(38, 38)
	plusBtn.AutoButtonColor = false
	plusBtn.BackgroundColor3 = COLOR_PAPER_LIGHT
	plusBtn.BorderSizePixel = 0
	plusBtn.Font = Enum.Font.GothamBold
	plusBtn.TextSize = 18
	plusBtn.TextColor3 = COLOR_WOOD_DARKEST
	plusBtn.Text = "+"
	plusBtn.ZIndex = 7
	plusBtn.Parent = stepRow
	local pC = Instance.new("UICorner"); pC.CornerRadius = UDim.new(0, 8); pC.Parent = plusBtn
	local pS = Instance.new("UIStroke"); pS.Color = COLOR_WOOD_DARK; pS.Thickness = 1.5
	pS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; pS.Parent = plusBtn

	-- Craft button
	local craftBtn = Instance.new("TextButton")
	craftBtn.Name = "CraftButton"
	craftBtn.AnchorPoint = Vector2.new(0, 1)
	craftBtn.Position = UDim2.new(0, 0, 1, 0)
	craftBtn.Size = UDim2.new(1, 0, 0, 42)
	craftBtn.AutoButtonColor = false
	craftBtn.BackgroundColor3 = COLOR_WOOD_DARK
	craftBtn.BorderSizePixel = 0
	craftBtn.Font = Enum.Font.GothamBold
	craftBtn.TextSize = 16
	craftBtn.TextColor3 = COLOR_PAPER_LIGHT
	craftBtn.Text = "Craft"
	craftBtn.ZIndex = 7
	craftBtn.Parent = d
	local cC = Instance.new("UICorner"); cC.CornerRadius = UDim.new(0, 10); cC.Parent = craftBtn
	local cS = Instance.new("UIStroke"); cS.Color = COLOR_WOOD_DARKEST; cS.Thickness = 2
	cS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; cS.Parent = craftBtn

	-- Empty placeholder shown when nothing selected.
	local empty = Instance.new("TextLabel")
	empty.Name = "EmptyState"
	empty.Size = UDim2.new(1, 0, 1, 0)
	empty.BackgroundTransparency = 1
	empty.Font = Enum.Font.GothamMedium
	empty.TextSize = 14
	empty.TextColor3 = COLOR_WOOD_MID
	empty.TextWrapped = true
	empty.TextXAlignment = Enum.TextXAlignment.Center
	empty.TextYAlignment = Enum.TextYAlignment.Center
	empty.Text = "Select a recipe\nto see details."
	empty.ZIndex = 8
	empty.Parent = d

	detailPanel = d
	detailRefs = {
		root = d, title = title, icon = icon, desc = desc,
		reqHeader = reqHeader, reqList = reqList,
		stepRow = stepRow, minusBtn = minusBtn, plusBtn = plusBtn, qtyLabel = qtyLabel,
		craftBtn = craftBtn, empty = empty,
	}

	minusBtn.MouseButton1Click:Connect(function()
		if not selectedRecipe then return end
		craftQuantity = math.max(1, craftQuantity - 1)
		if repaintDetailPanel then repaintDetailPanel() end
	end)
	plusBtn.MouseButton1Click:Connect(function()
		if not selectedRecipe then return end
		local maxQ = math.max(1, maxCraftable(selectedRecipe))
		craftQuantity = math.min(maxQ, craftQuantity + 1)
		if repaintDetailPanel then repaintDetailPanel() end
	end)

	craftBtn.MouseButton1Click:Connect(function()
		if not selectedRecipe then return end
		local qty = math.min(craftQuantity, maxCraftable(selectedRecipe))
		if qty <= 0 then return end
		-- Server validates each request independently and re-checks the
		-- inventory snapshot, so loop-firing is safe even if a sibling
		-- script consumes the same materials between fires.
		for i = 1, qty do
			craftEvent:FireServer("craft", selectedRecipe.name)
		end
	end)

	return d
end

-- ─── Inventory bar ──────────────────────────────────────────────────
local function buildInventoryBar(parent)
	local bar = Instance.new("Frame")
	bar.Name = "InventoryBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 1, 12)
	-- Width auto-tuned to the item count below.
	bar.Size = UDim2.fromOffset(#INVENTORY_BAR_ITEMS * 70 + 24, INVENTORY_BAR_H)
	bar.BackgroundColor3 = COLOR_WOOD_BASE
	bar.BorderSizePixel = 0
	bar.ZIndex = 4
	bar.Parent = parent

	local bC = Instance.new("UICorner"); bC.CornerRadius = UDim.new(0, 12); bC.Parent = bar
	local bS = Instance.new("UIStroke"); bS.Color = COLOR_WOOD_DARK; bS.Thickness = 2
	bS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; bS.Parent = bar

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12); pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 6); pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = bar

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = bar

	invBarRefs = {}
	for i, item in ipairs(INVENTORY_BAR_ITEMS) do
		local cell = Instance.new("Frame")
		cell.Name = "Cell_" .. item
		cell.Size = UDim2.fromOffset(58, 40)
		cell.BackgroundTransparency = 1
		cell.LayoutOrder = i
		cell.ZIndex = 5
		cell.Parent = bar

		local icon = Instance.new("ImageLabel")
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 0, 0.5, 0)
		icon.Size = UDim2.fromOffset(28, 28)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = COST_ICONS[item] or ""
		icon.ZIndex = 6
		icon.Parent = cell

		local count = Instance.new("TextLabel")
		count.AnchorPoint = Vector2.new(0, 0.5)
		count.Position = UDim2.new(0, 32, 0.5, 0)
		count.Size = UDim2.new(1, -32, 1, 0)
		count.BackgroundTransparency = 1
		count.Font = Enum.Font.GothamBold
		count.TextSize = 14
		count.TextColor3 = COLOR_PAPER_LIGHT
		count.TextXAlignment = Enum.TextXAlignment.Left
		count.Text = "0"
		count.ZIndex = 6
		count.Parent = cell

		invBarRefs[item] = { count = count, icon = icon }
	end

	return bar
end

-- ─── Reactive paint paths ───────────────────────────────────────────
repaintRecipeList = function()
	if not recipeCards then return end
	local order = 0
	for _, r in ipairs(recipes) do
		local refs = recipeCards[r.name]
		if refs then
			local visible = recipeMatchesFilter(r)
			refs.card.Visible = visible
			if visible then
				order = order + 1
				refs.card.LayoutOrder = order
				local affordable = canAfford(r)
				-- Affordability is signalled via text colour, not card
				-- opacity — fading the whole card just makes it blend
				-- into the panel and hides which item is which.
				refs.card.BackgroundTransparency = 0
				refs.icon.ImageTransparency = 0
				if affordable then
					refs.name.TextColor3 = COLOR_WOOD_DARKEST
				else
					refs.name.TextColor3 = COLOR_WOOD_MID
				end
				for _, ce in ipairs(refs.costEntries) do
					if (inventory[ce.item] or 0) >= ce.amount then
						ce.label.TextColor3 = COLOR_WOOD_DARKEST
					else
						ce.label.TextColor3 = COLOR_RED_BAD
					end
				end
				if selectedRecipe and selectedRecipe.name == r.name then
					refs.stroke.Color = COLOR_WOOD_DARKEST
					refs.stroke.Thickness = 3
					refs.card.BackgroundColor3 = COLOR_PAPER_LIGHT
				else
					refs.stroke.Color = COLOR_WOOD_DARK
					refs.stroke.Thickness = 1.5
					refs.card.BackgroundColor3 = COLOR_PAPER
				end
			end
		end
	end
end

repaintSelectionStrokes = function()
	repaintRecipeList()
end

repaintDetailPanel = function()
	if not detailRefs then return end
	if not selectedRecipe then
		detailRefs.empty.Visible = true
		detailRefs.title.Text = ""
		detailRefs.icon.Image = ""
		detailRefs.desc.Text = ""
		detailRefs.reqHeader.Visible = false
		detailRefs.reqList.Visible = false
		detailRefs.stepRow.Visible = false
		detailRefs.craftBtn.Visible = false
		return
	end
	detailRefs.empty.Visible = false
	detailRefs.reqHeader.Visible = true
	detailRefs.reqList.Visible = true
	detailRefs.stepRow.Visible = true
	detailRefs.craftBtn.Visible = true

	detailRefs.title.Text = selectedRecipe.displayName or selectedRecipe.name
	detailRefs.icon.Image = selectedRecipe.icon or ""
	detailRefs.desc.Text  = selectedRecipe.description or ""

	-- Rebuild requirements rows. Cheap (≤ 3 entries) so we destroy +
	-- recreate instead of diffing.
	for _, child in ipairs(detailRefs.reqList:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	local order = 0
	for item, amount in selectedRecipe.costs do
		order = order + 1
		local need = amount * craftQuantity
		local have = inventory[item] or 0
		local row = Instance.new("Frame")
		row.Name = "Req_" .. item
		row.Size = UDim2.new(1, 0, 0, 22)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.ZIndex = 7
		row.Parent = detailRefs.reqList

		local rIcon = Instance.new("ImageLabel")
		rIcon.AnchorPoint = Vector2.new(0, 0.5)
		rIcon.Position = UDim2.new(0, 0, 0.5, 0)
		rIcon.Size = UDim2.fromOffset(20, 20)
		rIcon.BackgroundTransparency = 1
		rIcon.ScaleType = Enum.ScaleType.Fit
		rIcon.Image = COST_ICONS[item] or ""
		rIcon.ZIndex = 8
		rIcon.Parent = row

		local rLabel = Instance.new("TextLabel")
		rLabel.AnchorPoint = Vector2.new(0, 0.5)
		rLabel.Position = UDim2.new(0, 26, 0.5, 0)
		rLabel.Size = UDim2.new(1, -26, 1, 0)
		rLabel.BackgroundTransparency = 1
		rLabel.Font = Enum.Font.GothamBold
		rLabel.TextSize = 13
		rLabel.TextXAlignment = Enum.TextXAlignment.Left
		rLabel.Text = string.format("%d/%d", have, need)
		rLabel.TextColor3 = (have >= need) and COLOR_GREEN_OK or COLOR_RED_BAD
		rLabel.ZIndex = 8
		rLabel.Parent = row
	end

	-- Quantity stepper bounds + button enable states.
	local maxQ = maxCraftable(selectedRecipe)
	if craftQuantity > math.max(1, maxQ) then
		craftQuantity = math.max(1, maxQ)
	end
	detailRefs.qtyLabel.Text = tostring(craftQuantity)

	local function setBtnEnabled(btn, enabled)
		btn.AutoButtonColor = false
		if enabled then
			btn.BackgroundColor3 = COLOR_PAPER_LIGHT
			btn.TextColor3 = COLOR_WOOD_DARKEST
		else
			btn.BackgroundColor3 = COLOR_PAPER
			btn.TextColor3 = COLOR_WOOD_MID
		end
	end
	setBtnEnabled(detailRefs.minusBtn, craftQuantity > 1)
	setBtnEnabled(detailRefs.plusBtn,  craftQuantity < maxQ)

	local affordable = canAfford(selectedRecipe, craftQuantity)
	if affordable then
		detailRefs.craftBtn.BackgroundColor3 = COLOR_WOOD_DARK
		detailRefs.craftBtn.TextColor3       = COLOR_PAPER_LIGHT
	else
		detailRefs.craftBtn.BackgroundColor3 = COLOR_WOOD_MID
		detailRefs.craftBtn.TextColor3       = COLOR_PAPER
	end
end

local function repaintInventoryBar()
	if not invBarRefs then return end
	for item, refs in pairs(invBarRefs) do
		refs.count.Text = tostring(inventory[item] or 0)
	end
end

local function repaintAll()
	repaintRecipeList()
	repaintDetailPanel()
	repaintInventoryBar()
end

-- ─── Panel build ────────────────────────────────────────────────────
local function buildPanel(parent)
	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.BackgroundColor3 = COLOR_WOOD_BASE
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Parent = parent

	local pCorner = Instance.new("UICorner")
	pCorner.CornerRadius = UDim.new(0, PANEL_RADIUS)
	pCorner.Parent = panel

	local pStroke = Instance.new("UIStroke")
	pStroke.Color = COLOR_WOOD_DARK
	pStroke.Thickness = 3
	pStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	pStroke.Parent = panel

	local pPad = Instance.new("UIPadding")
	pPad.PaddingTop    = UDim.new(0, PANEL_PAD)
	pPad.PaddingBottom = UDim.new(0, PANEL_PAD)
	pPad.PaddingLeft   = UDim.new(0, PANEL_PAD)
	pPad.PaddingRight  = UDim.new(0, PANEL_PAD)
	pPad.Parent = panel

	-- Inner highlight (matches QuestMenu).
	local highlight = Instance.new("Frame")
	highlight.Name = "InnerHighlight"
	highlight.AnchorPoint = Vector2.new(0.5, 0.5)
	highlight.Position = UDim2.fromScale(0.5, 0.5)
	highlight.Size = UDim2.new(1, (PANEL_PAD - 2) * 2, 1, (PANEL_PAD - 2) * 2)
	highlight.BackgroundTransparency = 1
	highlight.BorderSizePixel = 0
	highlight.ZIndex = 3
	highlight.Parent = panel
	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, PANEL_RADIUS - 4)
	hCorner.Parent = highlight
	local hStroke = Instance.new("UIStroke")
	hStroke.Color = Color3.fromRGB(255, 255, 255)
	hStroke.Thickness = 1
	hStroke.Transparency = 0.82
	hStroke.Parent = highlight

	-- Three-column grid: rail | center | detail. All three holders
	-- start at HEADER_STRIP_H so the close button gets a clean
	-- empty band along the top of the panel; their bottoms align so
	-- the visible boxes are the same height (matches the reference).
	local railHolder = Instance.new("Frame")
	railHolder.Name = "RailHolder"
	railHolder.Position = UDim2.fromOffset(0, HEADER_STRIP_H)
	railHolder.Size = UDim2.new(0, TAB_RAIL_W, 1, -HEADER_STRIP_H)
	-- Paper-tinted box so the rail visually matches the centre + detail
	-- columns (the reference renders all three as the same paper card).
	railHolder.BackgroundColor3 = COLOR_PAPER
	railHolder.BackgroundTransparency = 0.35
	railHolder.BorderSizePixel = 0
	railHolder.ZIndex = 4
	railHolder.Parent = panel
	local rhCorner = Instance.new("UICorner")
	rhCorner.CornerRadius = UDim.new(0, 12)
	rhCorner.Parent = railHolder
	local rhStroke = Instance.new("UIStroke")
	rhStroke.Color = COLOR_WOOD_DARK
	rhStroke.Thickness = 2
	rhStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rhStroke.Parent = railHolder
	local rhPad = Instance.new("UIPadding")
	rhPad.PaddingTop    = UDim.new(0, 12)
	rhPad.PaddingBottom = UDim.new(0, 12)
	rhPad.PaddingLeft   = UDim.new(0, 10)
	rhPad.PaddingRight  = UDim.new(0, 10)
	rhPad.Parent = railHolder
	buildTabRail(railHolder)

	local centerHolder = Instance.new("Frame")
	centerHolder.Name = "CenterHolder"
	centerHolder.Position = UDim2.fromOffset(TAB_RAIL_W + CONTENT_GAP, HEADER_STRIP_H)
	centerHolder.Size = UDim2.new(1, -(TAB_RAIL_W + DETAIL_W + 2 * CONTENT_GAP), 1, -HEADER_STRIP_H)
	centerHolder.BackgroundTransparency = 1
	centerHolder.ZIndex = 4
	centerHolder.Parent = panel
	buildRecipeList(centerHolder)

	local detailHolder = Instance.new("Frame")
	detailHolder.Name = "DetailHolder"
	detailHolder.AnchorPoint = Vector2.new(1, 0)
	detailHolder.Position = UDim2.new(1, 0, 0, HEADER_STRIP_H)
	detailHolder.Size = UDim2.new(0, DETAIL_W, 1, -HEADER_STRIP_H)
	detailHolder.BackgroundTransparency = 1
	detailHolder.ZIndex = 4
	detailHolder.Parent = panel
	buildDetailPanel(detailHolder)

	buildCloseButton(panel)
	buildInventoryBar(panel)
end

-- ─── Open / close lifecycle ─────────────────────────────────────────
local OPEN_INFO  = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function captureFadeTargets()
	fadeTargets = {}
	local function visit(node)
		if node:IsA("Frame") and node.BackgroundTransparency < 1 then
			table.insert(fadeTargets, { inst = node, prop = "BackgroundTransparency", rest = node.BackgroundTransparency })
		elseif node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
			table.insert(fadeTargets, { inst = node, prop = "TextTransparency", rest = node.TextTransparency })
			if node.BackgroundTransparency < 1 then
				table.insert(fadeTargets, { inst = node, prop = "BackgroundTransparency", rest = node.BackgroundTransparency })
			end
		elseif node:IsA("ImageLabel") or node:IsA("ImageButton") then
			table.insert(fadeTargets, { inst = node, prop = "ImageTransparency", rest = node.ImageTransparency })
			if node.BackgroundTransparency < 1 then
				table.insert(fadeTargets, { inst = node, prop = "BackgroundTransparency", rest = node.BackgroundTransparency })
			end
		elseif node:IsA("UIStroke") and node.Transparency < 1 then
			table.insert(fadeTargets, { inst = node, prop = "Transparency", rest = node.Transparency })
		end
	end
	visit(panel)
	for _, child in ipairs(panel:GetDescendants()) do
		visit(child)
	end
end

local function setFadeAll(value)
	if not fadeTargets then return end
	for _, t in ipairs(fadeTargets) do
		if t.inst.Parent then t.inst[t.prop] = value end
	end
end

local function ensureScreenGui()
	if screenGui and screenGui.Parent then return screenGui end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "WorkbenchGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = SCREENGUI_DISPLAY_ORDER
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	buildBackdrop(screenGui)
	buildPanel(screenGui)
	return screenGui
end

local function openUI()
	local gui = ensureScreenGui()
	if isOpen then return end
	isOpen = true

	if not panelScale then
		panelScale = Instance.new("UIScale")
		panelScale.Scale = 1
		panelScale.Parent = panel
		captureFadeTargets()
		backdropFadeTarget = backdrop and backdrop.BackgroundTransparency or 0.55
	end

	-- Pull a fresh inventory snapshot from the server before painting.
	craftEvent:FireServer("requestRecipes")

	repaintAll()

	gui.Enabled = true
	setFadeAll(1)
	if backdrop then backdrop.BackgroundTransparency = 1 end
	panelScale.Scale = 0.94

	for _, t in ipairs(fadeTargets) do
		if t.inst.Parent then
			TweenService:Create(t.inst, OPEN_INFO, { [t.prop] = t.rest }):Play()
		end
	end
	if backdrop then
		TweenService:Create(backdrop, OPEN_INFO, { BackgroundTransparency = backdropFadeTarget }):Play()
	end
	TweenService:Create(panelScale, OPEN_INFO, { Scale = 1.0 }):Play()
end

closeUI = function()
	if not screenGui or not isOpen then return end
	isOpen = false

	for _, t in ipairs(fadeTargets or {}) do
		if t.inst.Parent then
			TweenService:Create(t.inst, CLOSE_INFO, { [t.prop] = 1 }):Play()
		end
	end
	if backdrop then
		TweenService:Create(backdrop, CLOSE_INFO, { BackgroundTransparency = 1 }):Play()
	end
	if panelScale then
		TweenService:Create(panelScale, CLOSE_INFO, { Scale = 0.96 }):Play()
	end

	task.delay(CLOSE_INFO.Time + 0.02, function()
		if not isOpen and screenGui then
			screenGui.Enabled = false
		end
	end)
end

-- ─── Wires ──────────────────────────────────────────────────────────
openWorkbenchEvent.OnClientEvent:Connect(function()
	if isOpen then closeUI() else openUI() end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not isOpen then return end
	-- Don't steal Escape / E from chat or text boxes (search field).
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Escape then
		_G.SuppressInventoryToggle = true
		closeUI()
		task.delay(0.25, function()
			_G.SuppressInventoryToggle = false
		end)
	end
end)

inventoryEvent.OnClientEvent:Connect(function(inv)
	inventory = inv or {}
	repaintAll()
end)

craftEvent.OnClientEvent:Connect(function(action, data, inv)
	if action == "recipes" then
		if inv then
			inventory = inv
		end
		repaintAll()
	elseif action == "success" then
		-- Lightweight floating "Crafted!" toast — same message surface as
		-- before so other systems' expectations don't break.
		local toastGui = Instance.new("ScreenGui")
		toastGui.Name = "CraftToast"
		toastGui.ResetOnSpawn = false
		toastGui.Parent = playerGui

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0, 300, 0, 50)
		label.Position = UDim2.new(0.5, -150, 0.3, 0)
		label.BackgroundTransparency = 1
		label.Text = "Crafted!"
		label.TextColor3 = COLOR_PAPER_LIGHT
		label.TextStrokeTransparency = 0.4
		label.TextStrokeColor3 = COLOR_WOOD_DARKEST
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Parent = toastGui

		local tween = TweenService:Create(label, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, -150, 0.25, 0),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			toastGui:Destroy()
		end)
	end
end)
