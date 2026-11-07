-- MonolithUIKit.lua (ReplicatedStorage ModuleScript)
-- Shared design system for the Diver Monolith window, replicated 1:1 from the Claude Design files
-- "Меню починки монолита / Меню улучшений монолита" (.dc.html, v2 with the aging overlay + repair
-- transition). All colors/sizes below are the EXACT values from that file. Font: design = Fredoka
-- 500/600/700 → closest Roblox family WITH Cyrillic is Nunito (500→Medium, 600→SemiBold, 700→Bold).

local TweenService = game:GetService("TweenService")
-- общая кнопка закрытия: одна на все меню океана (см. UITheme.closeButton)
local UITheme = require(game:GetService("ReplicatedStorage"):WaitForChild("UITheme"))

local K = {}

-- ── design tokens (from the .dc.html v3 — the darker, richer palette) ──
K.C = {
	panel       = Color3.fromHex("3d81c6"), -- panel bg
	panelBorder = Color3.fromHex("1e4f88"), -- panel border (3px)
	block       = Color3.fromHex("549ad9"), -- inner blocks / upgrade rows
	blockBorder = Color3.fromHex("3c7ab2"),
	tile        = Color3.fromHex("9cc7eb"), -- icon tiles
	tileBorder  = Color3.fromHex("16324e"),
	navy        = Color3.fromHex("16395c"), -- level badge (the close button is UITheme.closeButton now)
	navyHover   = Color3.fromHex("1f4e79"),
	green       = Color3.fromHex("12b512"), -- buttons + affordable pills
	greenLedge  = Color3.fromHex("0f7c0c"), -- hard bottom shadow of green buttons
	red         = Color3.fromHex("d84f40"), -- unaffordable pills
	gray        = Color3.fromHex("8a97a4"), -- disabled button
	grayLedge   = Color3.fromHex("6b7584"),
	sub         = Color3.fromHex("cfe4f7"), -- subtitles / effect text
	white       = Color3.new(1, 1, 1),
	shadow      = Color3.fromRGB(20, 60, 110),  -- text-shadow rgba(20,60,110,0.4)
	web         = Color3.fromRGB(240, 248, 255), -- cobweb strands
	dust        = Color3.fromRGB(70, 85, 100),   -- dust/dirt specks
}

-- panel geometry (fixed, per design)
K.PANEL_W, K.PANEL_H = 860, 470

-- ── font: Nunito (Cyrillic) with a safe fallback to Gotham ──
local nunitoOk = pcall(function()
	local _ = Font.fromName("Nunito", Enum.FontWeight.Bold)
end)
function K.font(weight)
	if nunitoOk then
		local ok, f = pcall(function() return Font.fromName("Nunito", weight) end)
		if ok then return f end
	end
	if weight == Enum.FontWeight.Bold or weight == Enum.FontWeight.ExtraBold then
		return Font.fromEnum(Enum.Font.GothamBold)
	end
	return Font.fromEnum(Enum.Font.GothamMedium)
end
K.W500, K.W600, K.W700 = Enum.FontWeight.Medium, Enum.FontWeight.SemiBold, Enum.FontWeight.Bold

function K.corner(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = i; return c end
function K.stroke(i, col, th)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = i; return s
end

-- text label with the design's offset text-shadow (a twin label 2px below, 40% dark-blue)
function K.label(parent, p)
	local function mk(isShadow)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(p.x or 0, (p.y or 0) + (isShadow and (p.shadowDy or 2) or 0))
		t.Size = UDim2.fromOffset(p.w or 200, p.h or 24)
		t.FontFace = K.font(p.weight or K.W500)
		t.Text = p.text or ""
		t.TextSize = p.size or 16
		t.TextColor3 = isShadow and K.C.shadow or (p.color or K.C.white)
		t.TextTransparency = isShadow and 0.6 or 0
		t.TextXAlignment = p.xalign or Enum.TextXAlignment.Left
		t.TextYAlignment = p.yalign or Enum.TextYAlignment.Top
		t.TextWrapped = p.wrap or false
		t.Parent = parent
		return t
	end
	local shadow = nil
	if p.shadow then shadow = mk(true) end
	local main = mk(false)
	return main, shadow
end

-- icon tile (84px on repair, 60px on upgrades) with a color-emoji icon
function K.tile(parent, px, emoji, emojiPx, radius)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(px, px)
	f.BackgroundColor3 = K.C.tile
	K.corner(f, radius or 12); K.stroke(f, K.C.tileBorder, 2)
	local e = Instance.new("TextLabel")
	e.BackgroundTransparency = 1; e.Size = UDim2.fromScale(1, 1)
	e.Font = Enum.Font.SourceSans; e.Text = emoji; e.TextSize = emojiPx
	e.TextColor3 = K.C.white; e.Parent = f
	f.Parent = parent
	return f
end

-- rounded cost pill: "🪵 5 Дерево" (green = affordable, red = not)
function K.pill(parent, p)
	local f = Instance.new("TextLabel")
	f.BackgroundColor3 = p.bg or K.C.green
	f.Size = UDim2.fromOffset(10, p.h or 32)
	f.AutomaticSize = Enum.AutomaticSize.X
	f.FontFace = K.font(K.W600)
	f.Text = (p.icon and (p.icon .. "  ") or "") .. (p.text or "")
	f.TextSize = p.textSize or 15
	f.TextColor3 = K.C.white
	K.corner(f, p.radius or 14)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, p.padX or 14); pad.PaddingRight = UDim.new(0, p.padX or 14)
	pad.Parent = f
	f.Parent = parent
	return f
end

-- chunky 3D button, v2 style: borderless solid fill with a COLORED hard bottom ledge
-- (box-shadow 0 4px 0 #2fa244) and a press-down animation
function K.button(parent, p)
	local ledgeH = p.ledge or 4
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(p.w or 200, (p.h or 52) + ledgeH)
	holder.Parent = parent

	local ledge = Instance.new("Frame")
	ledge.BackgroundColor3 = p.ledgeColor or K.C.greenLedge
	ledge.Position = UDim2.fromOffset(0, ledgeH)
	ledge.Size = UDim2.fromOffset(p.w or 200, p.h or 52)
	K.corner(ledge, p.radius or 24)
	ledge.Parent = holder

	local btn = Instance.new("TextButton")
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = p.bg or K.C.green
	btn.Size = UDim2.fromOffset(p.w or 200, p.h or 52)
	btn.FontFace = K.font(K.W700)
	btn.Text = p.text or ""
	btn.TextSize = p.textSize or 21
	btn.TextColor3 = K.C.white
	K.corner(btn, p.radius or 24)
	btn.Parent = holder

	local up = UDim2.fromOffset(0, 0)
	local down = UDim2.fromOffset(0, ledgeH - 1)
	btn.MouseButton1Down:Connect(function() btn.Position = down end)
	local function release() btn.Position = up end
	btn.MouseButton1Up:Connect(release); btn.MouseLeave:Connect(release)

	local api = { holder = holder, btn = btn, ledge = ledge }
	function api.setStyle(bg, ledgeColor) btn.BackgroundColor3 = bg; ledge.BackgroundColor3 = ledgeColor end
	return api
end

-- a thin line segment between two panel-local points (for the cobwebs)
local function lineSeg(parent, x1, y1, x2, y2, thickness, color, transparency)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 0.5 then return end
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
	f.Size = UDim2.fromOffset(len, thickness)
	f.Rotation = math.deg(math.atan2(dy, dx))
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f:SetAttribute("_baseT", transparency) -- remembered so the overlay can reset/evaporate reliably
	f.BorderSizePixel = 0
	f.Parent = parent
end

-- cobweb geometry from the design SVG (150×150 space): 4 spokes + 3 arcs of 3 quadratic segments
local WEB_SPOKES = { { 0, 0, 150, 12 }, { 0, 0, 128, 78 }, { 0, 0, 70, 132 }, { 0, 0, 14, 150 } }
local WEB_ARCS = {
	{ { 44.8, 3.6, 38, 16, 38.4, 23.4 }, { 38.4, 23.4, 31, 33, 21.1, 39.7 }, { 21.1, 39.7, 13, 43, 4.2, 44.8 } },
	{ { 84.7, 6.8, 74, 28, 72.6, 44.2 }, { 72.6, 44.2, 58, 62, 39.9, 75.1 }, { 39.9, 75.1, 25, 82, 7.9, 84.7 } },
	{ { 124.5, 10, 108, 40, 106.8, 65 }, { 106.8, 65, 85, 92, 58.6, 110.4 }, { 58.6, 110.4, 37, 121, 11.6, 124.5 } },
}

-- draw one cobweb into `parent` through the point transform `tf(x, y) → px, py`
local function drawWeb(parent, tf, transparency)
	local th = 1.5
	for _, s in ipairs(WEB_SPOKES) do
		local x1, y1 = tf(s[1], s[2]); local x2, y2 = tf(s[3], s[4])
		lineSeg(parent, x1, y1, x2, y2, th, K.C.web, transparency)
	end
	for _, arc in ipairs(WEB_ARCS) do
		for _, q in ipairs(arc) do
			-- quadratic bezier (p0, c, p1) ≈ two segments through the t=0.5 point
			local mx = 0.25 * q[1] + 0.5 * q[3] + 0.25 * q[5]
			local my = 0.25 * q[2] + 0.5 * q[4] + 0.25 * q[6]
			local x0, y0 = tf(q[1], q[2]); local xm, ym = tf(mx, my); local x1, y1 = tf(q[5], q[6])
			lineSeg(parent, x0, y0, xm, ym, th, K.C.web, transparency)
			lineSeg(parent, xm, ym, x1, y1, th, K.C.web, transparency)
		end
	end
end

-- dust specks from the design SVG (panel-local coordinates, 860×470)
local DUST_CIRCLES = {
	{ 210, 440, 4 }, { 238, 448, 2.5 }, { 256, 442, 3 }, { 640, 52, 2.5 },
	{ 662, 44, 3.5 }, { 120, 180, 2.5 }, { 470, 120, 2.5 }, { 500, 300, 3 },
}
local DUST_ELLIPSES = { { 230, 452, 42, 7 }, { 600, 455, 30, 6 } }

-- the AGING OVERLAY: corner cobwebs + dust over the panel while the monolith is broken.
-- Returns an api: reset() re-shows everything; fadeOut(dur) EVAPORATES it — every strand and speck
-- gets its own transparency tween while the whole layer drifts upward like vapor. Per-element tweens
-- (instead of one CanvasGroup GroupTransparency) so the dissolve is guaranteed to render everywhere.
function K.agingOverlay(panel)
	local root = Instance.new("Frame")
	root.Name = "AgingOverlay"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ClipsDescendants = true
	root.ZIndex = 6
	root.Parent = panel

	-- top-left web (150×150 at -2,-2), strands at 80% alpha
	drawWeb(root, function(x, y) return x - 2, y - 2 end, 0.2)
	-- bottom-right web (scaled to 105×105, rotated 180°, at bottom:-2 right:-2), 70% alpha
	drawWeb(root, function(x, y)
		return (K.PANEL_W + 2) - 0.7 * x, (K.PANEL_H + 2) - 0.7 * y
	end, 0.3)

	for _, c in ipairs(DUST_CIRCLES) do
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromOffset(c[1], c[2])
		d.Size = UDim2.fromOffset(c[3] * 2, c[3] * 2)
		d.BackgroundColor3 = K.C.dust; d.BackgroundTransparency = 0.78
		d:SetAttribute("_baseT", 0.78)
		d.BorderSizePixel = 0
		K.corner(d, math.ceil(c[3]))
		d.Parent = root
	end
	for _, e in ipairs(DUST_ELLIPSES) do
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromOffset(e[1], e[2])
		d.Size = UDim2.fromOffset(e[3] * 2, e[4] * 2)
		d.BackgroundColor3 = K.C.dust; d.BackgroundTransparency = 0.86
		d:SetAttribute("_baseT", 0.86)
		d.BorderSizePixel = 0
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.5, 0); c.Parent = d
		d.Parent = root
	end

	local api = { frame = root }

	function api.reset()
		root.Visible = true
		root.Position = UDim2.fromOffset(0, 0)
		for _, d in ipairs(root:GetChildren()) do
			if d:IsA("Frame") then d.BackgroundTransparency = d:GetAttribute("_baseT") or 0 end
		end
	end

	function api.fadeOut(dur)
		local info = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(root, info, { Position = UDim2.fromOffset(0, -10) }):Play()
		for _, d in ipairs(root:GetChildren()) do
			if d:IsA("Frame") then
				TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
			end
		end
		task.delay(dur, function() root.Visible = false end)
	end

	return api
end

-- the window shell: dimmed backdrop, centered 860×470 panel with stud-dot pattern, close button,
-- LEFT content region (500 wide) and the RIGHT 280px render slot. Titles live inside the state
-- frames (the two states have different headers), not in the shell.
function K.window(playerGui, name)
	local W, H = K.PANEL_W, K.PANEL_H

	local gui = Instance.new("ScreenGui")
	gui.Name = name; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40; gui.Enabled = false; gui.Parent = playerGui

	local backdrop = Instance.new("TextButton")
	backdrop.Text = ""; backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0); backdrop.BackgroundTransparency = 0.45
	backdrop.Size = UDim2.fromScale(1, 1); backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.Active = true
	panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(W, H)
	panel.BackgroundColor3 = K.C.panel
	K.corner(panel, 22); K.stroke(panel, K.C.panelBorder, 3)
	panel.Parent = gui

	local scale = Instance.new("UIScale"); scale.Parent = panel
	local function fit()
		local vp = gui.AbsoluteSize
		scale.Scale = math.clamp(math.min(vp.X / (W + 100), vp.Y / (H + 140)), 0.45, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit); fit()

	-- stud pattern: white dots r≈6.5px at 7% opacity, straight 48px grid, first center at (12,12)
	local dots = Instance.new("Frame")
	dots.BackgroundTransparency = 1; dots.Size = UDim2.fromScale(1, 1)
	dots.ClipsDescendants = true; dots.Parent = panel
	for gy = 0, math.ceil(H / 48) do
		for gx = 0, math.ceil(W / 48) do
			local d = Instance.new("Frame")
			d.BackgroundColor3 = K.C.white; d.BackgroundTransparency = 0.93
			d.Size = UDim2.fromOffset(13, 13)
			d.Position = UDim2.fromOffset(12 + gx * 48 - 6, 12 + gy * 48 - 6)
			d.BorderSizePixel = 0
			K.corner(d, 7)
			d.Parent = dots
		end
	end

	-- RIGHT: 280px render slot (block-styled; the live diver preview goes inside)
	local right = Instance.new("Frame")
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.new(1, -26, 0, 24)
	right.Size = UDim2.new(0, 280, 1, -48)
	right.BackgroundColor3 = K.C.block
	K.corner(right, 14); K.stroke(right, K.C.blockBorder, 2)
	right.ClipsDescendants = true
	right.Parent = panel

	-- LEFT content region (panel padding 24/26, gap 22 before the right slot → 500 wide)
	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.Position = UDim2.fromOffset(26, 24)
	left.Size = UDim2.new(1, -26 - 280 - 22 - 26, 1, -48)
	left.Parent = panel

	--[[ ── CLOSE: единый крестик на все меню океана ──
	     Кнопку целиком собирает UITheme.closeButton, эталоном владелец назвал
	     инвентарь. Своя сборка здесь была третьим по счёту вариантом крестика
	     (картинка 62 px с ростом на наведении), и игрок видел один и тот же
	     элемент управления разным в каждом окне.
	     Размер сюда НЕ передаётся намеренно: он живёт в UITheme.CLOSE_SIZE, иначе
	     меню снова разъедутся — так это и вышло в прошлый раз.
	     Родителем остаётся сама панель окна (у панели нет ClipsDescendants; режет
	     детей только вложенный `dots`), посадка обычная — правый верхний угол, её
	     задаёт умолчание модуля. ZIndex 10 сохранён: панель рисует поверх себя
	     точечный узор и правый слот, кнопка должна остаться над ними. ]]
	local close = UITheme.closeButton({ parent = panel, zIndex = 10 })

	local function hide() gui.Enabled = false end
	close.MouseButton1Click:Connect(hide)
	backdrop.MouseButton1Click:Connect(hide)

	return { gui = gui, panel = panel, left = left, right = right, close = close }
end

return K
