-- QuestMenu.client.lua
-- Full-screen quest log opened by the left-side QuestEntryButton or
-- the J key. Builds incrementally across B1 → B10 so each commit is
-- testable on its own.
--
-- B1 scope: lazy ScreenGui host + _G.OpenQuestMenu / _G.CloseQuestMenu
-- stubs that flip the host's Enabled flag. Nothing visible yet —
-- B2 lands the wood panel, B3 the tab rail, etc.
--
-- DisplayOrder 110 sits above PhoneMenu (200? actually phone uses
-- 200 for its main screenGui; the OnboardingTooltip uses 200 too,
-- and QuestNotificationGui uses 8). Lifting QuestMenu to 110 keeps
-- it ABOVE in-game HUD and the QuestEntryButton (90) but BELOW the
-- phone if both happen to be open — phone takes precedence as the
-- bigger, more deliberate UI.
--
-- Public API (final shape across B1 → B10):
--   _G.OpenQuestMenu()    -- show the menu (no-op if already open)
--   _G.CloseQuestMenu()   -- hide the menu (no-op if already hidden)

local Players = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SCREENGUI_DISPLAY_ORDER = 110

-- ─── Wood/paper palette (matches OnboardingTooltip + Claude Design
-- handoff) ────────────────────────────────────────────────────────────
local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_WOOD_DARK    = Color3.fromRGB( 91,  58,  34)
local COLOR_WOOD_MID     = Color3.fromRGB(138, 106,  68)
local COLOR_WOOD_BASE    = Color3.fromRGB(176, 138,  92)
local COLOR_PAPER        = Color3.fromRGB(233, 217, 184)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(243, 230, 204)

-- ─── Layout constants ────────────────────────────────────────────────
local PANEL_W      = 540
local PANEL_H      = 360
local PANEL_RADIUS = 18
local PANEL_PAD    = 14

-- Tab rail (left half of the panel content). Three vertical tabs:
-- "Quests", "History", "Challenges". Width tuned so a long label
-- like "Challenges" fits without clipping at our 14-px font.
local TAB_RAIL_W   = 130
local TAB_HEIGHT   = 38
local TAB_GAP      = 6
local TAB_RADIUS   = 8
-- Y offset where the tab list starts inside the rail. Leaves room
-- above for the QUESTS header (B7) so the first tab doesn't sit
-- directly under it.
local TAB_LIST_TOP = 56

-- Right-side content area sits to the right of the tab rail with a
-- small gap so the rail's active-tab fill doesn't kiss the content
-- card. Each tab's content lives inside as a child Frame; only the
-- one matching activeTabId is Visible at any time (B9).
local CONTENT_GAP   = 12
local CONTENT_RADIUS = 12

-- Header (top-left of the panel content). Scroll/parchment glyph
-- followed by the "QUESTS" label. Same on every tab — only the right
-- pane swaps content. Reuses the supplied quest icon asset shrunk
-- down so the menu shell has a consistent visual language with the
-- entry button.
local HEADER_HEIGHT     = 36
local HEADER_GLYPH_SIZE = 30
local HEADER_GLYPH_GAP  = 8
local QUEST_ICON_ASSET  = "rbxassetid://121862782555497"

-- ─── Tab catalog ─────────────────────────────────────────────────────
-- Order = vertical order in the rail. id is used as the key for the
-- right-side content swap (B6) and the active-tab tracking (B9).
local TABS = {
	{ id = "quests",     label = "Quests"     },
	{ id = "history",    label = "History"    },
	{ id = "challenges", label = "Challenges" },
}

-- Lazy build: the ScreenGui isn't created until the menu is first
-- opened. Cuts the cost of one always-resident GUI for players who
-- never open the quest log. Panel + tabs + content are also built
-- once during ensureScreenGui's first call.
local screenGui
local panel         -- the wood panel root (built in B2)
local tabRail       -- container for the left-side tab buttons (B3)
local tabHandles    -- [id] = { tile, dot } populated by B3 / B5
local activeTabId   -- which tab is currently selected (default = first
                    -- entry in TABS, applied by buildTabRail)
local contentRoot   -- right-side content frame (built in B6)
local contentPages  -- [id] = Frame; one per tab, only the active one
                    -- is Visible. Populated lazily by Phases D / E /
                    -- F / G — B6 just creates the empty container.

-- ─── Tab visual states (B4) ─────────────────────────────────────────
-- Active tab: paper-light fill, wood-darkest text + a small wood-dark
-- dot to the left of the label. Reads as a "page" tab pinned to the
-- rail. Inactive tabs: fully transparent background, paper-light
-- text, no dot. Hover on inactive: paper-fill at 0.6 transparency
-- (handled at the click site) so the player gets feedback without it
-- looking like a second active tab.
local TAB_DOT_SIZE   = 6
local TAB_DOT_INSET  = 12   -- distance from the tab's left edge to the dot's centre

local function paintTab(id)
	local h = tabHandles[id]
	if not h or not h.tile then return end
	local tile = h.tile
	local dot  = h.dot
	if id == activeTabId then
		tile.BackgroundTransparency = 0
		tile.BackgroundColor3 = COLOR_PAPER_LIGHT
		tile.TextColor3 = COLOR_WOOD_DARKEST
		if dot then dot.Visible = true end
	else
		tile.BackgroundTransparency = 1
		tile.TextColor3 = COLOR_PAPER_LIGHT
		if dot then dot.Visible = false end
	end
end

local function repaintAllTabs()
	if not tabHandles then return end
	for id in pairs(tabHandles) do
		paintTab(id)
	end
end

local function setActiveTab(id)
	if not tabHandles or not tabHandles[id] then return end
	if activeTabId == id then return end
	activeTabId = id
	repaintAllTabs()
end

-- ─── Tab rail (B3) ───────────────────────────────────────────────────
-- Vertical strip on the left side of the panel content. Each tab is a
-- TextButton holding a label; visual states (active vs inactive
-- fills, the leading dot indicator) layer on in B4 / B5. Click
-- handlers are stubbed for B3 — the real "swap content" path lands
-- in B9.
local function buildTabRail(parent)
	tabRail = Instance.new("Frame")
	tabRail.Name = "TabRail"
	tabRail.AnchorPoint = Vector2.new(0, 0)
	tabRail.Position = UDim2.fromOffset(0, 0)
	tabRail.Size = UDim2.new(0, TAB_RAIL_W, 1, 0)
	tabRail.BackgroundTransparency = 1
	tabRail.BorderSizePixel = 0
	tabRail.ZIndex = 4
	tabRail.Parent = parent

	tabHandles = {}

	for i, tab in ipairs(TABS) do
		local y = TAB_LIST_TOP + (i - 1) * (TAB_HEIGHT + TAB_GAP)

		local tile = Instance.new("TextButton")
		tile.Name = "Tab_" .. tab.id
		tile.AnchorPoint = Vector2.new(0, 0)
		tile.Position = UDim2.fromOffset(0, y)
		tile.Size = UDim2.new(1, 0, 0, TAB_HEIGHT)
		tile.AutoButtonColor = false
		tile.BackgroundTransparency = 1
		tile.BorderSizePixel = 0
		tile.Font = Enum.Font.GothamBold
		tile.TextSize = 14
		tile.TextColor3 = COLOR_PAPER_LIGHT
		tile.TextXAlignment = Enum.TextXAlignment.Left
		tile.TextYAlignment = Enum.TextYAlignment.Center
		tile.Text = "    " .. tab.label   -- leading spaces leave room for the dot indicator (B5)
		tile.ZIndex = 5
		tile.Parent = tabRail

		local tCorner = Instance.new("UICorner")
		tCorner.CornerRadius = UDim.new(0, TAB_RADIUS)
		tCorner.Parent = tile

		-- Active-tab dot indicator. Lives inside the tile so it gets
		-- the rail's transparent background when the tab isn't
		-- active; paintTab toggles its Visible flag.
		local dot = Instance.new("Frame")
		dot.Name = "ActiveDot"
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.new(0, TAB_DOT_INSET, 0.5, 0)
		dot.Size = UDim2.fromOffset(TAB_DOT_SIZE, TAB_DOT_SIZE)
		dot.BackgroundColor3 = COLOR_WOOD_DARK
		dot.BorderSizePixel = 0
		dot.Visible = false
		dot.ZIndex = tile.ZIndex + 1
		dot.Parent = tile
		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = dot

		tabHandles[tab.id] = { tile = tile, dot = dot }

		tile.MouseButton1Click:Connect(function()
			setActiveTab(tab.id)
		end)

		-- Inactive-tab hover feedback: faint paper wash so the player
		-- knows the tab is interactive without it looking like a
		-- second active tab. paintTab() snaps it back on MouseLeave.
		tile.MouseEnter:Connect(function()
			if tab.id == activeTabId then return end
			tile.BackgroundTransparency = 0.6
			tile.BackgroundColor3 = COLOR_PAPER_LIGHT
		end)
		tile.MouseLeave:Connect(function()
			paintTab(tab.id)
		end)
	end

	-- Seed the default active tab. paintTab requires tabHandles[id]
	-- to exist, which it now does.
	activeTabId = TABS[1].id
	repaintAllTabs()

	return tabRail
end

-- ─── Right-side content root (B6) ───────────────────────────────────
-- Single container that stays put while tabs swap their inner Frames.
-- Phase D / E / F / G mount per-tab page Frames into contentPages
-- keyed by tab id; B9 toggles their .Visible based on activeTabId.
-- Today the placeholder per-tab Frame is empty so the menu shell is
-- visually complete on its own and Phase B is independently shippable.
local function buildContentRoot(parent)
	contentRoot = Instance.new("Frame")
	contentRoot.Name = "Content"
	contentRoot.AnchorPoint = Vector2.new(0, 0)
	contentRoot.Position = UDim2.fromOffset(TAB_RAIL_W + CONTENT_GAP, 0)
	contentRoot.Size = UDim2.new(1, -(TAB_RAIL_W + CONTENT_GAP), 1, 0)
	contentRoot.BackgroundColor3 = COLOR_PAPER
	contentRoot.BackgroundTransparency = 0.15
	contentRoot.BorderSizePixel = 0
	contentRoot.ClipsDescendants = true
	contentRoot.ZIndex = 4
	contentRoot.Parent = parent

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0, CONTENT_RADIUS)
	cCorner.Parent = contentRoot

	local cStroke = Instance.new("UIStroke")
	cStroke.Color = COLOR_WOOD_DARK
	cStroke.Thickness = 2
	cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cStroke.Parent = contentRoot

	contentPages = {}
	for _, tab in ipairs(TABS) do
		local page = Instance.new("Frame")
		page.Name = "Page_" .. tab.id
		page.Size = UDim2.fromScale(1, 1)
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.Visible = (tab.id == activeTabId)
		page.ZIndex = 5
		page.Parent = contentRoot
		contentPages[tab.id] = page
	end

	return contentRoot
end

-- ─── QUESTS header (B7) ─────────────────────────────────────────────
-- Top-left of the panel content: scroll/parchment glyph (the supplied
-- quest icon asset, shrunk) + "QUESTS" label. Same on every tab.
-- Lives inside the tab rail's column so the label sits flush above
-- the first tab; the dot indicator aligns with the QUESTS column.
local function buildHeader(parent)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.AnchorPoint = Vector2.new(0, 0)
	header.Position = UDim2.fromOffset(0, 0)
	header.Size = UDim2.new(0, TAB_RAIL_W, 0, HEADER_HEIGHT)
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.ZIndex = 5
	header.Parent = parent

	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.AnchorPoint = Vector2.new(0, 0.5)
	glyph.Position = UDim2.new(0, 0, 0.5, 0)
	glyph.Size = UDim2.fromOffset(HEADER_GLYPH_SIZE, HEADER_GLYPH_SIZE)
	glyph.BackgroundTransparency = 1
	glyph.BorderSizePixel = 0
	glyph.Image = QUEST_ICON_ASSET
	glyph.ScaleType = Enum.ScaleType.Fit
	glyph.ZIndex = 6
	glyph.Parent = header

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, HEADER_GLYPH_SIZE + HEADER_GLYPH_GAP, 0.5, 0)
	label.Size = UDim2.new(1, -(HEADER_GLYPH_SIZE + HEADER_GLYPH_GAP), 1, 0)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = COLOR_PAPER_LIGHT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = "QUESTS"
	label.ZIndex = 6
	label.Parent = header

	return header
end

local function buildPanel(parent)
	-- Outer wood panel: same recipe as the onboarding tooltip's
	-- panel — wood-base fill, 3 px wood-dark border, inner 1 px
	-- white-18% inset highlight stroke. Centred in the screen via
	-- AnchorPoint (0.5, 0.5).
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

	-- Inner highlight (mockup's `.tip::before` trick): 1 px white-18%
	-- inset stroke 2 px from the outer border so the panel feels
	-- raised. Sized to overlap the parent's UIPadding so it kisses
	-- the visible edge instead of the padded box.
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

	buildHeader(panel)
	buildTabRail(panel)
	buildContentRoot(panel)

	return panel
end

local function ensureScreenGui()
	if screenGui and screenGui.Parent then return screenGui end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "QuestMenuGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = SCREENGUI_DISPLAY_ORDER
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false   -- shown only after openQuestMenu()
	screenGui.Parent = playerGui

	buildPanel(screenGui)
	return screenGui
end

local function openQuestMenu()
	local gui = ensureScreenGui()
	gui.Enabled = true
end

local function closeQuestMenu()
	if not screenGui then return end
	screenGui.Enabled = false
end

_G.OpenQuestMenu  = openQuestMenu
_G.CloseQuestMenu = closeQuestMenu
