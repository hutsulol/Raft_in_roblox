-- BrainMaze.client.lua
-- Full-screen "brain hacking" recruitment UI.
-- Side-view brain silhouette with glowing neural pathway maze.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════════
-- Dark sci-fi neural theme
-- ═══════════════════════════════════════════════════════════════════════
local COLOR_BG           = Color3.fromRGB(10, 16, 34)
local COLOR_BRAIN_FILL   = Color3.fromRGB(16, 30, 56)
local COLOR_WALL         = Color3.fromRGB(0, 145, 190)
local COLOR_WALL_OUTER   = Color3.fromRGB(0, 200, 245)
local COLOR_GLOW         = Color3.fromRGB(0, 175, 225)
local COLOR_NODE         = Color3.fromRGB(80, 215, 255)
local COLOR_PLAYER       = Color3.fromRGB(255, 255, 255)
local COLOR_EXIT         = Color3.fromRGB(80, 255, 170)
local COLOR_DIALOG_BG    = Color3.fromRGB(14, 24, 46)
local COLOR_DIALOG_EDGE  = Color3.fromRGB(0, 130, 170)
local COLOR_SKILL        = Color3.fromRGB(90, 55, 190)
local COLOR_TEXT          = Color3.fromRGB(170, 215, 255)
local DEFEAT_ICON        = "rbxassetid://90285585534580"

-- ═══════════════════════════════════════════════════════════════════════
-- Brain shape — side view profile facing LEFT
-- ═══════════════════════════════════════════════════════════════════════
-- Modeled as overlapping ellipses: cerebrum dome, frontal lobe, temporal
-- lobe, occipital area, cerebellum, brain stem, plus a subtractive notch
-- between cerebrum and cerebellum.

local GRID_COLS = 40
local GRID_ROWS = 32

local function isInsideBrain(col, row)
	local nx = (col - 0.5) / GRID_COLS
	local ny = (row - 0.5) / GRID_ROWS

	-- 1) Main cerebrum dome (frontal + parietal)
	local e1x = (nx - 0.40) / 0.38
	local e1y = (ny - 0.30) / 0.28
	local inCerebrum = (e1x * e1x + e1y * e1y) <= 1

	-- 2) Frontal lobe — curves down at the front
	local e2x = (nx - 0.08) / 0.10
	local e2y = (ny - 0.48) / 0.17
	local inFrontal = (e2x * e2x + e2y * e2y) <= 1

	-- 3) Frontal-temporal bridge
	local e3x = (nx - 0.14) / 0.12
	local e3y = (ny - 0.54) / 0.13
	local inFTBridge = (e3x * e3x + e3y * e3y) <= 1

	-- 4) Temporal lobe (lower front shelf)
	local e4x = (nx - 0.30) / 0.20
	local e4y = (ny - 0.63) / 0.08
	local inTemporal = (e4x * e4x + e4y * e4y) <= 1

	-- 5) Occipital area (back of cerebrum)
	local e5x = (nx - 0.74) / 0.17
	local e5y = (ny - 0.38) / 0.24
	local inOccipital = (e5x * e5x + e5y * e5y) <= 1

	-- 6) Cerebellum (smaller rounded mass, back-bottom)
	local e6x = (nx - 0.78) / 0.13
	local e6y = (ny - 0.72) / 0.11
	local inCerebellum = (e6x * e6x + e6y * e6y) <= 1

	-- 7) Brain stem (narrow, descends downward)
	local e7x = (nx - 0.64) / 0.05
	local e7y = (ny - 0.88) / 0.10
	local inStem = (e7x * e7x + e7y * e7y) <= 1

	-- 8) Bridge connecting cerebellum region to main brain
	local e8x = (nx - 0.68) / 0.07
	local e8y = (ny - 0.58) / 0.09
	local inBridge = (e8x * e8x + e8y * e8y) <= 1

	-- Subtractive: notch between cerebrum and cerebellum
	local s1x = (nx - 0.88) / 0.08
	local s1y = (ny - 0.54) / 0.06
	local inNotch = (s1x * s1x + s1y * s1y) <= 1

	local inside = inCerebrum or inFrontal or inFTBridge or inTemporal
		or inOccipital or inCerebellum or inStem or inBridge
	if inNotch then inside = false end

	return inside
end

-- ═══════════════════════════════════════════════════════════════════════
-- Maze generation — DFS recursive backtracker
-- ═══════════════════════════════════════════════════════════════════════

local function generateMaze()
	local grid = {}
	local valid = {}

	for r = 1, GRID_ROWS do
		grid[r] = {}
		for c = 1, GRID_COLS do
			if isInsideBrain(c, r) then
				grid[r][c] = { top = true, right = true, bottom = true, left = true, visited = false }
				table.insert(valid, { r = r, c = c })
			end
		end
	end

	if #valid == 0 then return grid end

	local function cellExists(r, c)
		return grid[r] and grid[r][c]
	end

	local function getUnvisitedNeighbors(r, c)
		local nb = {}
		if cellExists(r - 1, c) and not grid[r - 1][c].visited then
			table.insert(nb, { r = r - 1, c = c, wall = "top", opposite = "bottom" })
		end
		if cellExists(r + 1, c) and not grid[r + 1][c].visited then
			table.insert(nb, { r = r + 1, c = c, wall = "bottom", opposite = "top" })
		end
		if cellExists(r, c - 1) and not grid[r][c - 1].visited then
			table.insert(nb, { r = r, c = c - 1, wall = "left", opposite = "right" })
		end
		if cellExists(r, c + 1) and not grid[r][c + 1].visited then
			table.insert(nb, { r = r, c = c + 1, wall = "right", opposite = "left" })
		end
		return nb
	end

	-- Start from the brain stem area (bottom-center-right)
	local startCell = valid[1]
	local bestDist = math.huge
	for _, v in valid do
		local dist = math.abs(v.c - GRID_COLS * 0.64) + math.abs(v.r - GRID_ROWS)
		if dist < bestDist then
			bestDist = dist
			startCell = v
		end
	end

	local stack = { startCell }
	grid[startCell.r][startCell.c].visited = true

	while #stack > 0 do
		local cur = stack[#stack]
		local nb = getUnvisitedNeighbors(cur.r, cur.c)

		if #nb > 0 then
			local nxt = nb[math.random(#nb)]
			grid[cur.r][cur.c][nxt.wall] = false
			grid[nxt.r][nxt.c][nxt.opposite] = false
			grid[nxt.r][nxt.c].visited = true
			table.insert(stack, nxt)
		else
			table.remove(stack)
		end
	end

	return grid
end

-- ═══════════════════════════════════════════════════════════════════════
-- Find spawn (brain stem) and exit (top of cerebrum)
-- ═══════════════════════════════════════════════════════════════════════

local function findSpawnAndExit(grid)
	local spawnR, spawnC, exitR, exitC

	for r = GRID_ROWS, 1, -1 do
		for c = 1, GRID_COLS do
			if grid[r] and grid[r][c] then
				if not spawnR or r > spawnR
					or (r == spawnR and math.abs(c - GRID_COLS * 0.64) < math.abs(spawnC - GRID_COLS * 0.64)) then
					spawnR, spawnC = r, c
				end
			end
		end
		if spawnR then break end
	end

	for r = 1, GRID_ROWS do
		for c = 1, GRID_COLS do
			if grid[r] and grid[r][c] then
				if not exitR or r < exitR
					or (r == exitR and math.abs(c - GRID_COLS * 0.42) < math.abs(exitC - GRID_COLS * 0.42)) then
					exitR, exitC = r, c
				end
			end
		end
		if exitR then break end
	end

	return spawnR, spawnC, exitR, exitC
end

-- ═══════════════════════════════════════════════════════════════════════
-- Public: open the brain maze UI
-- ═══════════════════════════════════════════════════════════════════════

local mazeOpen = false

local function openBrainMaze(pirate, onComplete)
	if mazeOpen then return end
	mazeOpen = true
	_G.SuppressInventoryToggle = true

	local grid = generateMaze()
	local spawnR, spawnC, exitR, exitC = findSpawnAndExit(grid)

	local MAZE_W = 580
	local MAZE_H = 450
	local cellW = MAZE_W / GRID_COLS
	local cellH = MAZE_H / GRID_ROWS
	local WALL_PX = 2
	local OUTER_PX = 3

	-- ── ScreenGui ────────────────────────────────────────────────
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrainMazeGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 95
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	-- Full-screen dark background
	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = COLOR_BG
	bg.BorderSizePixel = 0
	bg.Parent = gui

	-- ── Maze container (invisible, positions everything) ─────────
	local mazeFrame = Instance.new("Frame")
	mazeFrame.Name = "MazeContainer"
	mazeFrame.Size = UDim2.fromOffset(MAZE_W, MAZE_H)
	mazeFrame.Position = UDim2.new(0.54, -MAZE_W / 2, 0.52, -MAZE_H / 2)
	mazeFrame.BackgroundTransparency = 1
	mazeFrame.BorderSizePixel = 0
	mazeFrame.ClipsDescendants = false
	mazeFrame.Parent = bg

	-- ── Brain fill — merge runs per row for performance ──────────
	for r = 1, GRID_ROWS do
		local runStart = nil
		for c = 1, GRID_COLS + 1 do
			local inBrain = grid[r] and grid[r][c]
			if inBrain and not runStart then
				runStart = c
			elseif not inBrain and runStart then
				local fill = Instance.new("Frame")
				fill.Size = UDim2.fromOffset((c - runStart) * cellW + 1, cellH + 1)
				fill.Position = UDim2.fromOffset((runStart - 1) * cellW, (r - 1) * cellH)
				fill.BackgroundColor3 = COLOR_BRAIN_FILL
				fill.BackgroundTransparency = 0.15
				fill.BorderSizePixel = 0
				fill.ZIndex = 1
				fill.Parent = mazeFrame
				runStart = nil
			end
		end
	end

	-- ── Render inner maze walls ──────────────────────────────────
	for r = 1, GRID_ROWS do
		for c = 1, GRID_COLS do
			local cell = grid[r] and grid[r][c]
			if not cell then continue end

			local x = (c - 1) * cellW
			local y = (r - 1) * cellH
			local isExit = (r == exitR and c == exitC)

			if cell.top and not isExit then
				local w = Instance.new("Frame")
				w.Size = UDim2.fromOffset(cellW + WALL_PX, WALL_PX)
				w.Position = UDim2.fromOffset(x, y)
				w.BackgroundColor3 = COLOR_WALL
				w.BackgroundTransparency = 0.35
				w.BorderSizePixel = 0
				w.ZIndex = 3
				w.Parent = mazeFrame
			end

			if cell.left then
				local w = Instance.new("Frame")
				w.Size = UDim2.fromOffset(WALL_PX, cellH + WALL_PX)
				w.Position = UDim2.fromOffset(x, y)
				w.BackgroundColor3 = COLOR_WALL
				w.BackgroundTransparency = 0.35
				w.BorderSizePixel = 0
				w.ZIndex = 3
				w.Parent = mazeFrame
			end

			if cell.right and (c == GRID_COLS or not (grid[r] and grid[r][c + 1])) then
				local w = Instance.new("Frame")
				w.Size = UDim2.fromOffset(WALL_PX, cellH + WALL_PX)
				w.Position = UDim2.fromOffset(x + cellW, y)
				w.BackgroundColor3 = COLOR_WALL
				w.BackgroundTransparency = 0.35
				w.BorderSizePixel = 0
				w.ZIndex = 3
				w.Parent = mazeFrame
			end

			if cell.bottom and (r == GRID_ROWS or not (grid[r + 1] and grid[r + 1][c])) then
				local w = Instance.new("Frame")
				w.Size = UDim2.fromOffset(cellW + WALL_PX, WALL_PX)
				w.Position = UDim2.fromOffset(x, y + cellH)
				w.BackgroundColor3 = COLOR_WALL
				w.BackgroundTransparency = 0.35
				w.BorderSizePixel = 0
				w.ZIndex = 3
				w.Parent = mazeFrame
			end
		end
	end

	-- ── Glowing brain outline ────────────────────────────────────
	for r = 1, GRID_ROWS do
		for c = 1, GRID_COLS do
			local cell = grid[r] and grid[r][c]
			if not cell then continue end

			local x = (c - 1) * cellW
			local y = (r - 1) * cellH

			local function drawBorder(px, py, pw, ph)
				-- Soft glow behind
				local glow = Instance.new("Frame")
				glow.Size = UDim2.fromOffset(pw + 6, ph + 6)
				glow.Position = UDim2.fromOffset(px - 3, py - 3)
				glow.BackgroundColor3 = COLOR_GLOW
				glow.BackgroundTransparency = 0.75
				glow.BorderSizePixel = 0
				glow.ZIndex = 2
				glow.Parent = mazeFrame

				-- Solid bright line
				local line = Instance.new("Frame")
				line.Size = UDim2.fromOffset(pw, ph)
				line.Position = UDim2.fromOffset(px, py)
				line.BackgroundColor3 = COLOR_WALL_OUTER
				line.BackgroundTransparency = 0
				line.BorderSizePixel = 0
				line.ZIndex = 4
				line.Parent = mazeFrame
			end

			local isExit = (r == exitR and c == exitC)

			if not (grid[r - 1] and grid[r - 1][c]) then
				if not isExit then
					drawBorder(x, y, cellW + OUTER_PX, OUTER_PX)
				end
			end
			if not (grid[r + 1] and grid[r + 1][c]) then
				drawBorder(x, y + cellH, cellW + OUTER_PX, OUTER_PX)
			end
			if not (grid[r] and grid[r][c - 1]) then
				drawBorder(x, y, OUTER_PX, cellH + OUTER_PX)
			end
			if not (grid[r] and grid[r][c + 1]) then
				drawBorder(x + cellW, y, OUTER_PX, cellH + OUTER_PX)
			end
		end
	end

	-- ── Exit opening — small glow just outside the gap ──────────
	if exitR and exitC then
		local ex = (exitC - 1) * cellW + cellW / 2
		local ey = (exitR - 1) * cellH - 12

		local exitGlow = Instance.new("Frame")
		exitGlow.Size = UDim2.fromOffset(cellW + 4, 8)
		exitGlow.Position = UDim2.fromOffset(ex - (cellW + 4) / 2, ey - 4)
		exitGlow.BackgroundColor3 = COLOR_EXIT
		exitGlow.BackgroundTransparency = 0.5
		exitGlow.BorderSizePixel = 0
		exitGlow.ZIndex = 6
		exitGlow.Parent = mazeFrame
		Instance.new("UICorner", exitGlow).CornerRadius = UDim.new(0.5, 0)

		TweenService:Create(exitGlow, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			BackgroundTransparency = 0.2,
		}):Play()

		local arrow = Instance.new("TextLabel")
		arrow.Size = UDim2.fromOffset(20, 16)
		arrow.Position = UDim2.fromOffset(ex - 10, ey - 20)
		arrow.BackgroundTransparency = 1
		arrow.Text = "EXIT"
		arrow.TextColor3 = COLOR_EXIT
		arrow.Font = Enum.Font.GothamBold
		arrow.TextSize = 9
		arrow.ZIndex = 7
		arrow.Parent = mazeFrame
	end

	-- ── Player dot (white + cyan glow) ───────────────────────────
	if spawnR and spawnC then
		local px = (spawnC - 1) * cellW + cellW / 2
		local py = (spawnR - 1) * cellH + cellH / 2

		local pGlow = Instance.new("Frame")
		pGlow.Size = UDim2.fromOffset(20, 20)
		pGlow.Position = UDim2.fromOffset(px - 10, py - 10)
		pGlow.BackgroundColor3 = COLOR_GLOW
		pGlow.BackgroundTransparency = 0.6
		pGlow.BorderSizePixel = 0
		pGlow.ZIndex = 8
		pGlow.Parent = mazeFrame
		Instance.new("UICorner", pGlow).CornerRadius = UDim.new(0.5, 0)

		local pDot = Instance.new("Frame")
		pDot.Name = "PlayerDot"
		pDot.Size = UDim2.fromOffset(10, 10)
		pDot.Position = UDim2.fromOffset(px - 5, py - 5)
		pDot.BackgroundColor3 = COLOR_PLAYER
		pDot.BorderSizePixel = 0
		pDot.ZIndex = 9
		pDot.Parent = mazeFrame
		Instance.new("UICorner", pDot).CornerRadius = UDim.new(0.5, 0)
	end

	-- ── Timer (top center, dark panel) ───────────────────────────
	local timerFrame = Instance.new("Frame")
	timerFrame.Size = UDim2.fromOffset(115, 42)
	timerFrame.Position = UDim2.new(0.54, -57, 0.04, 0)
	timerFrame.BackgroundColor3 = COLOR_DIALOG_BG
	timerFrame.BorderSizePixel = 0
	timerFrame.Parent = bg
	Instance.new("UICorner", timerFrame).CornerRadius = UDim.new(0, 10)

	local timerStroke = Instance.new("UIStroke")
	timerStroke.Thickness = 1.5
	timerStroke.Color = COLOR_DIALOG_EDGE
	timerStroke.Transparency = 0.25
	timerStroke.Parent = timerFrame

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Size = UDim2.new(1, 0, 1, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "00:50"
	timerLabel.TextColor3 = COLOR_TEXT
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextSize = 22
	timerLabel.Parent = timerFrame

	-- ── Dialog box (top-left) ────────────────────────────────────
	local dialogFrame = Instance.new("Frame")
	dialogFrame.Size = UDim2.fromOffset(310, 90)
	dialogFrame.Position = UDim2.fromOffset(20, 60)
	dialogFrame.BackgroundColor3 = COLOR_DIALOG_BG
	dialogFrame.BorderSizePixel = 0
	dialogFrame.Parent = bg
	Instance.new("UICorner", dialogFrame).CornerRadius = UDim.new(0, 10)

	local dialogStroke = Instance.new("UIStroke")
	dialogStroke.Thickness = 1.5
	dialogStroke.Color = COLOR_DIALOG_EDGE
	dialogStroke.Transparency = 0.15
	dialogStroke.Parent = dialogFrame

	-- Pirate icon
	local iconFrame = Instance.new("Frame")
	iconFrame.Size = UDim2.fromOffset(62, 62)
	iconFrame.Position = UDim2.fromOffset(10, 14)
	iconFrame.BackgroundTransparency = 1
	iconFrame.BorderSizePixel = 0
	iconFrame.Parent = dialogFrame
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 6)

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Thickness = 1.5
	iconStroke.Color = COLOR_DIALOG_EDGE
	iconStroke.Parent = iconFrame

	local iconImg = Instance.new("ImageLabel")
	iconImg.Size = UDim2.new(1, 0, 1, 0)
	iconImg.BackgroundTransparency = 1
	iconImg.Image = DEFEAT_ICON
	iconImg.ScaleType = Enum.ScaleType.Stretch
	iconImg.Parent = iconFrame
	Instance.new("UICorner", iconImg).CornerRadius = UDim.new(0, 6)

	-- Speech bubble
	local speechBubble = Instance.new("Frame")
	speechBubble.Size = UDim2.fromOffset(210, 58)
	speechBubble.Position = UDim2.fromOffset(82, 16)
	speechBubble.BackgroundColor3 = Color3.fromRGB(12, 22, 42)
	speechBubble.BorderSizePixel = 0
	speechBubble.Parent = dialogFrame
	Instance.new("UICorner", speechBubble).CornerRadius = UDim.new(0, 8)

	local speechStroke = Instance.new("UIStroke")
	speechStroke.Thickness = 1
	speechStroke.Color = COLOR_DIALOG_EDGE
	speechStroke.Transparency = 0.4
	speechStroke.Parent = speechBubble

	local speechLabel = Instance.new("TextLabel")
	speechLabel.Size = UDim2.new(1, -16, 1, -10)
	speechLabel.Position = UDim2.fromOffset(8, 5)
	speechLabel.BackgroundTransparency = 1
	speechLabel.Text = "What are you doing in my head?!"
	speechLabel.TextColor3 = COLOR_TEXT
	speechLabel.Font = Enum.Font.GothamBold
	speechLabel.TextSize = 13
	speechLabel.TextWrapped = true
	speechLabel.TextXAlignment = Enum.TextXAlignment.Left
	speechLabel.Parent = speechBubble

	-- ── Skill buttons (bottom-left) ──────────────────────────────
	local function makeSkillBtn(text, posY)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromOffset(170, 46)
		btn.Position = UDim2.new(0, 20, 1, posY)
		btn.BackgroundColor3 = COLOR_SKILL
		btn.Text = text
		btn.TextColor3 = Color3.fromRGB(210, 225, 255)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 16
		btn.BorderSizePixel = 0
		btn.Parent = bg
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
		local s = Instance.new("UIStroke")
		s.Thickness = 1.5
		s.Color = Color3.fromRGB(60, 35, 150)
		s.Parent = btn
		return btn
	end

	makeSkillBtn("Skill 1", -130)
	makeSkillBtn("Skill 2", -72)

	-- ── Close button (top-right) ─────────────────────────────────
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(38, 38)
	closeBtn.Position = UDim2.new(1, -52, 0, 14)
	closeBtn.BackgroundColor3 = Color3.fromRGB(170, 45, 45)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 18
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = bg
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

	-- ── Ambient background stars ─────────────────────────────────
	local stars = {}
	for _ = 1, 40 do
		local star = Instance.new("Frame")
		star.Size = UDim2.fromOffset(2, 2)
		star.Position = UDim2.new(math.random() * 0.96 + 0.02, 0, math.random() * 0.94 + 0.03, 0)
		star.BackgroundColor3 = COLOR_NODE
		star.BackgroundTransparency = 0.7
		star.BorderSizePixel = 0
		star.ZIndex = 0
		star.Parent = bg
		Instance.new("UICorner", star).CornerRadius = UDim.new(0.5, 0)
		table.insert(stars, star)
	end

	task.spawn(function()
		while gui.Parent do
			for _, s in stars do
				if not s.Parent then continue end
				TweenService:Create(s, TweenInfo.new(
					1 + math.random() * 2,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut
				), {
					BackgroundTransparency = math.random(50, 92) / 100,
				}):Play()
			end
			task.wait(2)
		end
	end)

	-- ── Slide-in animation ───────────────────────────────────────
	bg.BackgroundTransparency = 1
	mazeFrame.Position = UDim2.new(0.54, -MAZE_W / 2, 1.5, 0)

	-- Hide text/buttons initially
	for _, desc in gui:GetDescendants() do
		if desc:IsA("TextLabel") then
			desc.TextTransparency = 1
		elseif desc:IsA("TextButton") then
			desc.TextTransparency = 1
			desc.BackgroundTransparency = 1
		elseif desc:IsA("ImageLabel") then
			desc.ImageTransparency = 1
		end
	end

	TweenService:Create(bg, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0,
	}):Play()

	TweenService:Create(mazeFrame, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.54, -MAZE_W / 2, 0.52, -MAZE_H / 2),
	}):Play()

	task.delay(0.3, function()
		for _, desc in gui:GetDescendants() do
			if desc:IsA("TextLabel") then
				TweenService:Create(desc, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
			elseif desc:IsA("TextButton") then
				TweenService:Create(desc, TweenInfo.new(0.4), { TextTransparency = 0, BackgroundTransparency = 0 }):Play()
			elseif desc:IsA("ImageLabel") then
				TweenService:Create(desc, TweenInfo.new(0.4), { ImageTransparency = 0 }):Play()
			end
		end
	end)

	-- ── Close logic ──────────────────────────────────────────────
	local closed = false

	local function closeMaze(result)
		if closed then return end
		closed = true

		TweenService:Create(bg, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()

		for _, desc in gui:GetDescendants() do
			if desc:IsA("TextLabel") or desc:IsA("TextButton") then
				TweenService:Create(desc, TweenInfo.new(0.2), {
					TextTransparency = 1, BackgroundTransparency = 1,
				}):Play()
			elseif desc:IsA("ImageLabel") then
				TweenService:Create(desc, TweenInfo.new(0.2), { ImageTransparency = 1 }):Play()
			elseif desc:IsA("Frame") then
				TweenService:Create(desc, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
			elseif desc:IsA("UIStroke") then
				TweenService:Create(desc, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			end
		end

		task.delay(0.35, function()
			gui:Destroy()
			mazeOpen = false
			_G.SuppressInventoryToggle = false
			if onComplete then
				onComplete(result or "closed")
			end
		end)
	end

	closeBtn.MouseButton1Click:Connect(function()
		closeMaze("closed")
	end)

	local escConn
	escConn = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			closeMaze("closed")
			if escConn then escConn:Disconnect() end
		end
	end)
end

_G.OpenBrainMaze = openBrainMaze
