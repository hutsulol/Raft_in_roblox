-- BackHotkey.lua (ModuleScript)
-- Shared helper: mount a "Q" hotkey next to a BACK button, so pages
-- reachable via BACK can also be dismissed with a Q keypress.
--
-- Usage from a LocalScript (e.g. HandlingPage.client.lua):
--   -- Defensive require so a missing / slow-syncing module never
--   -- blocks the rest of the page (see Mercenaries folder for the
--   -- established pattern):
--   local BackHotkey = { attach = function() end }
--   do
--       local ok, mod = pcall(function()
--           local inst = script.Parent:WaitForChild("BackHotkey", 2)
--           return inst and require(inst) or nil
--       end)
--       if ok and typeof(mod) == "table" and typeof(mod.attach) == "function" then
--           BackHotkey = mod
--       end
--   end
--
--   local function triggerBack()
--       closeHandlingPage()
--       if ctx.onBack then ctx.onBack() end
--   end
--   backBtn.MouseButton1Click:Connect(triggerBack)
--   BackHotkey.attach(backBtn, triggerBack, {
--       activeConnections = activeConnections,   -- recommended, so the
--                                                -- UIS listener detaches
--                                                -- when the page closes
--       color       = COLOR_TEXT,
--       haloColor   = HOLO_EDGE,
--       fontTitle   = FONT_TITLE,
--   })
--
-- Visual: a 20×20 "Q" glyph rendered just outside the right edge of
-- backBtn, vertically centred. When Q is pressed a soft halo circle
-- behind the glyph flashes in and tweens back out — mirrors the
-- "AFTER PRESSING Q" state in the design mockup.

local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

local BackHotkey = {}

local DEFAULT_FONT       = Enum.Font.GothamBold
local DEFAULT_COLOR      = Color3.fromRGB(220, 240, 255)
local DEFAULT_HALO_COLOR = Color3.fromRGB(190, 220, 245)
local HINT_SIZE          = 20
local HINT_GAP           = 8

function BackHotkey.attach(backBtn, onBack, options)
	assert(typeof(backBtn) == "Instance", "backBtn must be a GuiButton")
	assert(typeof(onBack) == "function", "onBack must be a function")
	options = options or {}

	local color     = options.color     or DEFAULT_COLOR
	local haloColor = options.haloColor or DEFAULT_HALO_COLOR
	local fontTitle = options.fontTitle or DEFAULT_FONT
	-- Put the hint above the button's own label/glyph (which typically
	-- sit at backBtn.ZIndex + 1) so it stays legible even if anything
	-- passes over it. Caller can override explicitly via options.zIndex.
	local zIndex    = options.zIndex    or (backBtn.ZIndex or 1) + 2

	-- Hint container sits just outside the BACK button's right edge,
	-- vertically centred on it. Parented to backBtn so any movement
	-- of the button (responsive scale, reposition) carries the hint
	-- with it — no manual re-layout needed.
	local hint = Instance.new("Frame")
	hint.Name = "QHint"
	hint.AnchorPoint = Vector2.new(0, 0.5)
	hint.Position = UDim2.new(1, HINT_GAP, 0.5, 0)
	hint.Size = UDim2.fromOffset(HINT_SIZE, HINT_SIZE)
	hint.BackgroundTransparency = 1
	hint.BorderSizePixel = 0
	hint.ZIndex = zIndex
	hint.Parent = backBtn

	-- Halo circle behind the letter — invisible by default, tweens in
	-- on Q press. Corner radius = 50% for a perfect circle.
	local halo = Instance.new("Frame")
	halo.Name = "QHalo"
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Position = UDim2.fromScale(0.5, 0.5)
	halo.Size = UDim2.fromScale(1, 1)
	halo.BackgroundColor3 = haloColor
	halo.BackgroundTransparency = 1
	halo.BorderSizePixel = 0
	halo.ZIndex = zIndex
	halo.Parent = hint
	local haloCorner = Instance.new("UICorner")
	haloCorner.CornerRadius = UDim.new(1, 0)
	haloCorner.Parent = halo

	local letter = Instance.new("TextLabel")
	letter.Name = "QLetter"
	letter.BackgroundTransparency = 1
	letter.BorderSizePixel = 0
	letter.Size = UDim2.fromScale(1, 1)
	letter.Font = fontTitle
	letter.TextSize = 14
	letter.TextColor3 = color
	letter.TextXAlignment = Enum.TextXAlignment.Center
	letter.TextYAlignment = Enum.TextYAlignment.Center
	letter.Text = "Q"
	letter.ZIndex = zIndex + 1
	letter.Parent = hint

	-- Briefly brighten the halo, then fade it back out. Matches the
	-- "AFTER PRESSING Q" state in the mockup (the rest of the visual
	-- — default / hover / pressed — is already handled by the BACK
	-- button's own AutoButtonColor / stroke treatment).
	local function flashHalo()
		halo.BackgroundTransparency = 0.35
		TweenService:Create(halo,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }):Play()
	end

	-- Walk up the ancestry: if any GuiObject ancestor is not Visible
	-- (or the button itself is Visible=false), the button isn't on
	-- screen and Q shouldn't fire. This keeps the Mercenaries BACK
	-- listener quiet while a HandlingPage / WeaponSelectPage / etc.
	-- overlay is on top — both pages register a Q listener, but only
	-- the visible one reacts.
	local function isButtonOnScreen()
		if not hint.Parent then return false end
		local node = backBtn
		while node and node ~= game do
			if node:IsA("GuiObject") and node.Visible == false then
				return false
			end
			node = node.Parent
		end
		return true
	end

	local conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode ~= Enum.KeyCode.Q then return end
		if not isButtonOnScreen() then return end
		-- Don't fire if the button's Active flag is off (disabled state).
		if backBtn:IsA("GuiButton") and backBtn.Active == false then return end
		flashHalo()
		-- Wrap in a task.spawn so an error inside onBack doesn't leave
		-- the hotkey listener stuck holding the InputBegan call stack.
		task.spawn(onBack)
	end)

	-- Register for cleanup if the caller hands us their active-
	-- connections table (the standard pattern across the phone pages).
	if typeof(options.activeConnections) == "table" then
		table.insert(options.activeConnections, conn)
	end

	-- Also self-clean if the hint (therefore backBtn) is destroyed
	-- without the caller's own cleanup path running.
	hint.AncestryChanged:Connect(function(_, newParent)
		if newParent == nil and conn.Connected then
			conn:Disconnect()
		end
	end)

	return {
		hint    = hint,
		halo    = halo,
		letter  = letter,
		flash   = flashHalo,
		disconnect = function()
			if conn.Connected then conn:Disconnect() end
		end,
	}
end

return BackHotkey
