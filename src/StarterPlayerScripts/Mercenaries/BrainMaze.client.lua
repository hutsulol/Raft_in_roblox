-- BrainMaze.client.lua
-- Full-screen "brain hacking" recruitment UI.
-- Opens after the defeat dialogue. The player will navigate a maze
-- shaped like a brain to recruit the pirate.
-- For now: visual only (maze generation + rendering, no movement).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════════
-- Colors
-- ═══════════════════════════════════════════════════════════════════════
local COLOR_BG         = Color3.fromRGB(195, 215, 240)
local COLOR_BRAIN_FILL = Color3.fromRGB(210, 228, 248)
local COLOR_WALL       = Color3.fromRGB(100, 160, 220)
local COLOR_WALL_OUTER = Color3.fromRGB(70, 130, 200)
local COLOR_PLAYER     = Color3.fromRGB(255, 255, 255)
local COLOR_EXIT       = Color3.fromRGB(120, 255, 200)
local COLOR_DIALOG_BG  = Color3.fromRGB(230, 240, 250)
local COLOR_DIALOG_EDGE = Color3.fromRGB(140, 170, 210)
local COLOR_TIMER_BG   = Color3.fromRGB(230, 240, 250)
local COLOR_SKILL      = Color3.fromRGB(120, 90, 220)
local COLOR_TEXT       = Color3.fromRGB(40, 50, 80)
local DEFEAT_ICON      = "rbxassetid://90285585534580"

-- ═══════════════════════════════════════════════════════════════════════
-- Brain shape mask (ellipse approximation)
-- ═══════════════════════════════════════════════════════════════════════
-- The brain is modeled as two overlapping ellipses (left/right hemisphere)
-- with a slight downward bulge. Grid cells inside the mask are part of
-- the maze; cells outside are empty.

local GRID_COLS = 30
local GRID_ROWS = 22

local function isInsideBrain(col, row)
	local nx = (col - 0.5) / GRID_COLS
	local ny = (row - 0.5) / GRID_ROWS

	-- Left hemisphere: ellipse centered at (0.44, 0.46), radii (0.38, 0.44)
	local lx = (nx - 0.44) / 0.38
	local ly = (ny - 0.46) / 0.44
	local inLeft = (lx * lx + ly * ly) <= 1

	-- Right hemisphere: ellipse centered at (0.56, 0.46), radii (0.38, 0.44)
	local rx = (nx - 0.56) / 0.38
	local ry = (ny - 0.46) / 0.44
	local inRight = (rx * rx + ry * ry) <= 1

	-- Brain stem: small ellipse at bottom center
	local sx = (nx - 0.50) / 0.08
	local sy = (ny - 0.88) / 0.14
	local inStem = (sx * sx + sy * sy) <= 1

	return inLeft or inRight or inStem
end

-- ═══════════════════════════════════════════════════════════════════════
-- Maze generation (recursive backtracker / DFS)
-- ═══════════════════════════════════════════════════════════════════════
-- Each cell stores { top=bool, right=bool, bottom=bool, left=bool }
-- where true = wall present.

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
		local neighbors = {}
		if cellExists(r - 1, c) and not grid[r - 1][c].visited then
			table.insert(neighbors, { r = r - 1, c = c, wall = "top", opposite = "bottom" })
		end
		if cellExists(r + 1, c) and not grid[r + 1][c].visited then
			table.insert(neighbors, { r = r + 1, c = c, wall = "bottom", opposite = "top" })
		end
		if cellExists(r, c - 1) and not grid[r][c - 1].visited then
			table.insert(neighbors, { r = r, c = c - 1, wall = "left", opposite = "right" })
		end
		if cellExists(r, c + 1) and not grid[r][c + 1].visited then
			table.insert(neighbors, { r = r, c = c + 1, wall = "right", opposite = "left" })
		end
		return neighbors
	end

	-- Start from a cell near bottom-center (brain stem area)
	local startCell = valid[1]
	local bestDist = math.huge
	for _, v in valid do
		local dist = math.abs(v.c - GRID_COLS / 2) + math.abs(v.r - GRID_ROWS)
		if dist < bestDist then
			bestDist = dist
			startCell = v
		end
	end

	local stack = { startCell }
	grid[startCell.r][startCell.c].visited = true

	while #stack > 0 do
		local current = stack[#stack]
		local neighbors = getUnvisitedNeighbors(current.r, current.c)

		if #neighbors > 0 then
			local next = neighbors[math.random(#neighbors)]
			grid[current.r][current.c][next.wall] = false
			grid[next.r][next.c][next.opposite] = false
			grid[next.r][next.c].visited = true
			table.insert(stack, next)
		else
			table.remove(stack)
		end
	end

	return grid
end

-- ═══════════════════════════════════════════════════════════════════════
-- Find spawn and exit positions
-- ═══════════════════════════════════════════════════════════════════════

local function findSpawnAndExit(grid)
	local spawnR, spawnC = nil, nil
	local exitR, exitC = nil, nil
	local bestSpawnDist = math.huge
	local bestExitRow = GRID_ROWS

	-- Spawn: bottommost cell closest to center
	for r = GRID_ROWS, 1, -1 do
		for c = 1, GRID_COLS do
			if grid[r] and grid[r][c] then
				local dist = math.abs(c - GRID_COLS / 2) + (GRID_ROWS - r) * 0.5
				if r > (spawnR or 0) or (r == spawnR and dist < bestSpawnDist) then
					spawnR, spawnC = r, c
					bestSpawnDist = dist
				end
			end
		end
		if spawnR then break end
	end

	-- Exit: topmost cell closest to center
	for r = 1, GRID_ROWS do
		for c = 1, GRID_COLS do
			if grid[r] and grid[r][c] then
				if not exitR or r < exitR or (r == exitR and math.abs(c - GRID_COLS / 2) < math.abs(exitC - GRID_COLS / 2)) then
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

	-- ── ScreenGui ────────────────────────────────────────────────
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrainMazeGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 95
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	-- Full-screen background
	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = COLOR_BG
	bg.BackgroundTransparency = 0
	bg.BorderSizePixel = 0
	bg.Parent = gui

	-- ── Brain maze container (center-right) ──────────────────────
	local MAZE_W = 500
	local MAZE_H = 400

	local mazeFrame = Instance.new("Frame")
	mazeFrame.Name = "MazeContainer"
	mazeFrame.Size = UDim2.fromOffset(MAZE_W, MAZE_H)
	mazeFrame.Position = UDim2.new(0.55, -MAZE_W / 2, 0.52, -MAZE_H / 2)
	mazeFrame.BackgroundColor3 = COLOR_BRAIN_FILL
	mazeFrame.BackgroundTransparency = 0.3
	mazeFrame.BorderSizePixel = 0
	mazeFrame.ClipsDescendants = true
	mazeFrame.Parent = bg

	Instance.new("UICorner", mazeFrame).CornerRadius = UDim.new(0, 20)

	local mazeStroke = Instance.new("UIStroke")
	mazeStroke.Thickness = 2
	mazeStroke.Color = COLOR_WALL_OUTER
	mazeStroke.Transparency = 0.3
	mazeStroke.Parent = mazeFrame

	-- ── Render maze walls ────────────────────────────────────────
	local cellW = MAZE_W / GRID_COLS
	local cellH = MAZE_H / GRID_ROWS
	local WALL_THICKNESS = 2

	-- Draw brain outline (subtle) — cells that border empty space
	-- get a thicker outer wall
	for r = 1, GRID_ROWS do
		for c = 1, GRID_COLS do
			local cell = grid[r] and grid[r][c]
			if not cell then continue end

			local x = (c - 1) * cellW
			local y = (r - 1) * cellH

			-- Top wall
			if cell.top then
				local w = Instance.new("Frame")
				w.Size = UDim2.fromOffset(cellW + WALL_THICKNESS, WALL_THICKNESS)
				w.Position = UDim2.fromOffset(x, y)
				w.BackgroundColor3 = COLOR_WALL
				w.BackgroundTransparency = 0.2
				w.BorderSizePixel = 0
				w.Parent = mazeFrame
			end

			-- Left wall
			if cell.left then
				local w = Instance.new("Frame")
				w.Size = UDim2.fromOffset(WALL_THICKNESS, cellH + WALL_THICKNESS)
				w.Position = UDim2.fromOffset(x, y)
				w.BackgroundColor3 = COLOR_WALL
				w.BackgroundTransparency = 0.2
				w.BorderSizePixel = 0
				w.Parent = mazeFrame
			end

			-- Right wall (only for rightmost cells or cells bordering empty)
			if cell.right and (c == GRID_COLS or not (grid[r] and grid[r][c + 1])) then
				local w = Instance.new("Frame")
				w.Size = UDim2.fromOffset(WALL_THICKNESS, cellH + WALL_THICKNESS)
				w.Position = UDim2.fromOffset(x + cellW, y)
				w.BackgroundColor3 = COLOR_WALL
				w.BackgroundTransparency = 0.2
				w.BorderSizePixel = 0
				w.Parent = mazeFrame
			end

			-- Bottom wall (only for bottommost cells or cells bordering empty)
			if cell.bottom and (r == GRID_ROWS or not (grid[r + 1] and grid[r + 1][c])) then
				local w = Instance.new("Frame")
				w.Size = UDim2.fromOffset(cellW + WALL_THICKNESS, WALL_THICKNESS)
				w.Position = UDim2.fromOffset(x, y + cellH)
				w.BackgroundColor3 = COLOR_WALL
				w.BackgroundTransparency = 0.2
				w.BorderSizePixel = 0
				w.Parent = mazeFrame
			end
		end
	end

	-- ── Draw brain outer boundary (thicker) ──────────────────────
	for r = 1, GRID_ROWS do
		for c = 1, GRID_COLS do
			local cell = grid[r] and grid[r][c]
			if not cell then continue end

			local x = (c - 1) * cellW
			local y = (r - 1) * cellH
			local OUTER = 3

			-- Check each direction for brain boundary
			if not (grid[r - 1] and grid[r - 1][c]) then
				local w = Instance.new("Frame")
				w.Size = UDim2.fromOffset(cellW + OUTER, OUTER)
				w.Position = UDim2.fromOffset(x, y)
				w.BackgroundColor3 = COLOR_WALL_OUTER
				w.BorderSizePixel = 0
				w.Parent = mazeFrame
			end
			if not (grid[r + 1] and grid[r + 1][c]) then
				local w = Instance.new("Frame")
				w.Size = UDim2.fromOffset(cellW + OUTER, OUTER)
				w.Position = UDim2.fromOffset(x, y + cellH)
				w.BackgroundColor3 = COLOR_WALL_OUTER
				w.BorderSizePixel = 0
				w.Parent = mazeFrame
			end
			if not (grid[r] and grid[r][c - 1]) then
				local w = Instance.new("Frame")
				w.Size = UDim2.fromOffset(OUTER, cellH + OUTER)
				w.Position = UDim2.fromOffset(x, y)
				w.BackgroundColor3 = COLOR_WALL_OUTER
				w.BorderSizePixel = 0
				w.Parent = mazeFrame
			end
			if not (grid[r] and grid[r][c + 1]) then
				local w = Instance.new("Frame")
				w.Size = UDim2.fromOffset(OUTER, cellH + OUTER)
				w.Position = UDim2.fromOffset(x + cellW, y)
				w.BackgroundColor3 = COLOR_WALL_OUTER
				w.BorderSizePixel = 0
				w.Parent = mazeFrame
			end
		end
	end

	-- ── Exit marker (green glow at top) ──────────────────────────
	if exitR and exitC then
		local ex = (exitC - 1) * cellW + cellW / 2
		local ey = (exitR - 1) * cellH + cellH / 2
		local exitDot = Instance.new("Frame")
		exitDot.Size = UDim2.fromOffset(12, 12)
		exitDot.Position = UDim2.fromOffset(ex - 6, ey - 6)
		exitDot.BackgroundColor3 = COLOR_EXIT
		exitDot.BorderSizePixel = 0
		exitDot.Parent = mazeFrame
		Instance.new("UICorner", exitDot).CornerRadius = UDim.new(0.5, 0)

		local exitGlow = Instance.new("UIStroke")
		exitGlow.Thickness = 3
		exitGlow.Color = COLOR_EXIT
		exitGlow.Transparency = 0.4
		exitGlow.Parent = exitDot
	end

	-- ── Player dot (white circle at spawn) ───────────────────────
	if spawnR and spawnC then
		local px = (spawnC - 1) * cellW + cellW / 2
		local py = (spawnR - 1) * cellH + cellH / 2
		local PLAYER_SIZE = 10

		local playerDot = Instance.new("Frame")
		playerDot.Name = "PlayerDot"
		playerDot.Size = UDim2.fromOffset(PLAYER_SIZE, PLAYER_SIZE)
		playerDot.Position = UDim2.fromOffset(px - PLAYER_SIZE / 2, py - PLAYER_SIZE / 2)
		playerDot.BackgroundColor3 = COLOR_PLAYER
		playerDot.BorderSizePixel = 0
		playerDot.ZIndex = 5
		playerDot.Parent = mazeFrame
		Instance.new("UICorner", playerDot).CornerRadius = UDim.new(0.5, 0)

		local playerStroke = Instance.new("UIStroke")
		playerStroke.Thickness = 2
		playerStroke.Color = Color3.fromRGB(180, 190, 210)
		playerStroke.Parent = playerDot
	end

	-- ── Timer (top center) ───────────────────────────────────────
	local timerFrame = Instance.new("Frame")
	timerFrame.Size = UDim2.fromOffset(100, 36)
	timerFrame.Position = UDim2.new(0.55, -50, 0.06, 0)
	timerFrame.BackgroundColor3 = COLOR_TIMER_BG
	timerFrame.BackgroundTransparency = 0.1
	timerFrame.BorderSizePixel = 0
	timerFrame.Parent = bg
	Instance.new("UICorner", timerFrame).CornerRadius = UDim.new(0, 8)

	local timerStroke = Instance.new("UIStroke")
	timerStroke.Thickness = 1.5
	timerStroke.Color = COLOR_DIALOG_EDGE
	timerStroke.Parent = timerFrame

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Size = UDim2.new(1, 0, 1, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "00:50"
	timerLabel.TextColor3 = COLOR_TEXT
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextSize = 20
	timerLabel.Parent = timerFrame

	-- ── Dialog box (top-left) ────────────────────────────────────
	local dialogFrame = Instance.new("Frame")
	dialogFrame.Size = UDim2.fromOffset(280, 90)
	dialogFrame.Position = UDim2.fromOffset(20, 20)
	dialogFrame.BackgroundColor3 = COLOR_DIALOG_BG
	dialogFrame.BackgroundTransparency = 0.05
	dialogFrame.BorderSizePixel = 0
	dialogFrame.Parent = bg
	Instance.new("UICorner", dialogFrame).CornerRadius = UDim.new(0, 10)

	local dialogStroke = Instance.new("UIStroke")
	dialogStroke.Thickness = 1.5
	dialogStroke.Color = COLOR_DIALOG_EDGE
	dialogStroke.Parent = dialogFrame

	-- Pirate icon (inside dialog)
	local iconFrame = Instance.new("Frame")
	iconFrame.Size = UDim2.fromOffset(60, 60)
	iconFrame.Position = UDim2.fromOffset(10, 15)
	iconFrame.BackgroundTransparency = 1
	iconFrame.BorderSizePixel = 0
	iconFrame.Parent = dialogFrame
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 6)

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Thickness = 1.5
	iconStroke.Color = Color3.fromRGB(200, 160, 60)
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
	speechBubble.Size = UDim2.fromOffset(185, 55)
	speechBubble.Position = UDim2.fromOffset(80, 18)
	speechBubble.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	speechBubble.BackgroundTransparency = 0.05
	speechBubble.BorderSizePixel = 0
	speechBubble.Parent = dialogFrame
	Instance.new("UICorner", speechBubble).CornerRadius = UDim.new(0, 8)

	local speechStroke = Instance.new("UIStroke")
	speechStroke.Thickness = 1
	speechStroke.Color = COLOR_DIALOG_EDGE
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
		btn.Size = UDim2.fromOffset(160, 44)
		btn.Position = UDim2.new(0, 20, 1, posY)
		btn.BackgroundColor3 = COLOR_SKILL
		btn.Text = text
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 16
		btn.BorderSizePixel = 0
		btn.Parent = bg
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
		local s = Instance.new("UIStroke")
		s.Thickness = 1.5
		s.Color = Color3.fromRGB(90, 60, 180)
		s.Parent = btn
		return btn
	end

	local skill1Btn = makeSkillBtn("Skill 1", -120)
	local skill2Btn = makeSkillBtn("Skill 2", -66)

	-- ── Close button (top-right, temporary for testing) ──────────
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(36, 36)
	closeBtn.Position = UDim2.new(1, -50, 0, 14)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 18
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = bg
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

	-- ── Slide-in animation ───────────────────────────────────────
	bg.BackgroundTransparency = 1
	mazeFrame.Position = UDim2.new(0.55, -MAZE_W / 2, 1.5, 0)

	TweenService:Create(bg, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0,
	}):Play()
	TweenService:Create(mazeFrame, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.55, -MAZE_W / 2, 0.52, -MAZE_H / 2),
	}):Play()

	-- ── Close logic ──────────────────────────────────────────────
	local closed = false

	local function closeMaze(result)
		if closed then return end
		closed = true

		TweenService:Create(bg, TweenInfo.new(0.3), {
			BackgroundTransparency = 1,
		}):Play()

		for _, desc in gui:GetDescendants() do
			if desc:IsA("TextLabel") or desc:IsA("TextButton") then
				TweenService:Create(desc, TweenInfo.new(0.2), {
					TextTransparency = 1, BackgroundTransparency = 1,
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

	-- Escape to close
	local escConn
	escConn = game:GetService("UserInputService").InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			closeMaze("closed")
			if escConn then escConn:Disconnect() end
		end
	end)
end

-- Expose globally so RecruitmentSystem can call it
_G.OpenBrainMaze = openBrainMaze
