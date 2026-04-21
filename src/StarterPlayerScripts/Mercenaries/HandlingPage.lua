-- HandlingPage.lua
-- Placeholder ModuleScript for the mercenary Handling sub-page.
--
-- Intentionally minimal — opens a blank holo page with a BACK button so
-- MercenariesMenu can route the "HANDLING" pill here. The real layout
-- (slot tiles, character viewport, detail + DNA cards) lands in later
-- steps. Steps 2-8 will fill this module in from scratch using the
-- Claude Design MercHandlingPage.jsx spec.

local HandlingPage = {}

-- Module-level ref to the open page Frame (if any) so close() can tear
-- it down from outside build().
local activePage = nil

-- Destroys the current Handling page. Safe to call when nothing is
-- open.
function HandlingPage.close()
	if activePage then
		activePage:Destroy()
		activePage = nil
	end
end

-- ctx fields (all optional — the placeholder only actually uses
-- screenGui, mercName and onBack; the rest are passed through so
-- subsequent steps can hook into the rig pipeline without changing
-- the caller):
--   screenGui             — ScreenGui to parent the page under
--   mercName              — currently selected merc (for the title)
--   mercNames             — full roster list
--   theme                 — MERC_THEMES[mercName] or DEFAULT_THEME
--   onBack()              — invoked when BACK is pressed
--   hidePhonePanels()     — phone-panel hide hook
--   detachCachedViewports() — rig-cache detach hook
--   buildMercViewport()   — rig builder
function HandlingPage.build(ctx)
	ctx = ctx or {}
	local screenGui = ctx.screenGui
	if not screenGui then
		warn("[HandlingPage] build called without ctx.screenGui")
		return
	end

	if activePage then activePage:Destroy() end

	local page = Instance.new("Frame")
	page.Name = "HandlingPage"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundColor3 = Color3.fromRGB(4, 8, 16)
	page.BackgroundTransparency = 0.05
	page.BorderSizePixel = 0
	page.ZIndex = 50
	page.Parent = screenGui
	activePage = page

	if ctx.hidePhonePanels then ctx.hidePhonePanels() end

	-- Minimal centred title so we can see which merc the page is for
	-- and confirm the route works. Gets replaced by the real layout in
	-- Step 2 onward.
	local title = Instance.new("TextLabel")
	title.Name = "Placeholder"
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.Size = UDim2.fromOffset(500, 60)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.TextColor3 = Color3.fromRGB(190, 220, 245)
	title.Text = string.format(
		"HANDLING · %s",
		tostring(ctx.mercName or "—"):upper()
	)
	title.ZIndex = 51
	title.Parent = page

	-- Minimal BACK button top-left — returns to the mercenaries roster
	-- via ctx.onBack(). Closes this page first so the roster rebuild
	-- starts from a clean slate.
	local backBtn = Instance.new("TextButton")
	backBtn.Name = "BackButton"
	backBtn.AnchorPoint = Vector2.new(0, 0)
	backBtn.Position = UDim2.new(0, 20, 0, 30)
	backBtn.Size = UDim2.fromOffset(88, 34)
	backBtn.BackgroundColor3 = Color3.fromRGB(10, 24, 44)
	backBtn.BackgroundTransparency = 0.28
	backBtn.BorderSizePixel = 0
	backBtn.AutoButtonColor = true
	backBtn.Font = Enum.Font.GothamBold
	backBtn.TextSize = 13
	backBtn.TextColor3 = Color3.fromRGB(220, 240, 255)
	backBtn.Text = "← BACK"
	backBtn.ZIndex = 51
	backBtn.Parent = page
	local bStroke = Instance.new("UIStroke")
	bStroke.Color     = Color3.fromRGB(75, 100, 125)
	bStroke.Thickness = 1
	bStroke.Parent    = backBtn

	backBtn.MouseButton1Click:Connect(function()
		HandlingPage.close()
		if ctx.onBack then ctx.onBack() end
	end)
end

return HandlingPage
