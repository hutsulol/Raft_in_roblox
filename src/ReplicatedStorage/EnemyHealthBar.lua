-- EnemyHealthBar.lua  (ReplicatedStorage, shared module)
-- Единый HP-бар для ВСЕХ врагов (корабли, зомби, пираты, монстры) по дизайну
-- "HP Bar Roblox.dc.html": табличка с именем сверху → полоса HP (тёмный корпус,
-- чёрная рамка, градиентная заливка green→yellow→red с бликом и числом по центру) →
-- ряд звёзд сложности снизу (картинки-звёзды, как в других гуи).
--
-- Использование (сервер):
--   local EnemyHealthBar = require(ReplicatedStorage:WaitForChild("EnemyHealthBar"))
--   local hb = EnemyHealthBar.new({ name = "ПИРАТСКИЙ КОРАБЛЬ", maxHp = 100, difficulty = 2 })
--   hb.gui.StudsOffset = Vector3.new(0, 2.4, 0)   -- или .StudsOffsetWorldSpace
--   hb.gui.Parent = adorneePart
--   hb.setHP(cur, max)                            -- при каждом изменении HP
--
-- НЕ AlwaysOnTop: бар не светит сквозь стены — если враг за препятствием, бар скрыт.
-- Шрифты: число — LuckiestGuy (как в дизайне); имя — GothamBlack (LuckiestGuy без
-- кириллицы, поэтому русские имена жирным кириллическим). Звёзды — картинка-ассет.

local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")

-- ── СЕРВЕРНАЯ ПОДТЯЖКА БОРДОВ НПС ─────────────────────────────────────────
-- Борд НПС — заякоренный парт: его CFrame каждый кадр ставит клиент
-- (EnemyHPBillboard), а на сервере парт так и остаётся там, где был создан. Для
-- островных пиратов это неважно — они стоят на месте. А матросы уплывают вместе с
-- катером через весь океан, и борд остаётся у точки спавна. В океане включён
-- StreamingEnabled, а он раздаёт клиенту только то, что рядом ПО СЕРВЕРНЫМ
-- координатам: борд уплывшего матроса до игрока просто не доезжает — отсюда
-- «у матросов нет HP». Поэтому сервер редко (SYNC_DT) подтягивает парт к голове:
-- точный CFrame всё равно ставит клиент, серверу достаточно, чтобы стриминг
-- считал борд «рядом с игроком».
local boards    = {}   -- [парт борда] = голова НПС
local SYNC_DT   = 0.4  -- сек между проверками
local SYNC_MOVE = 6    -- студов: ближе не трогаем, чтобы не гонять трафик зря

if RunService:IsServer() then
	task.spawn(function()
		while true do
			task.wait(SYNC_DT)
			for part, head in pairs(boards) do
				if not part.Parent or not head.Parent then
					boards[part] = nil
				else
					local up = part:GetAttribute("UpStuds") or 2.4
					local want = head.Position + Vector3.new(0, up, 0)
					if (part.Position - want).Magnitude > SYNC_MOVE then
						part.CFrame = CFrame.new(want)
					end
				end
			end
		end
	end)
end

local EnemyHealthBar = {}

local FONT_NUM  = Enum.Font.LuckiestGuy  -- число HP (латиница/цифры) — точный дизайн
local FONT_NAME = Enum.Font.GothamBlack  -- имя врага (кириллица-safe, жирный)

-- звезда сложности — тот же ассет, что в других гуи (RewardRoll)
local STAR_IMG  = "rbxassetid://128165533748650"

-- палитра из дизайна
local NAME_BG = Color3.fromRGB(14, 31, 48)   -- #0e1f30
local BAR_BG  = Color3.fromRGB(10, 24, 38)    -- #0a1826
local BLACK   = Color3.fromRGB(0, 0, 0)
local WHITE   = Color3.fromRGB(255, 255, 255)

-- цвета заливки по остатку HP: light / mid / dark (для вертикального градиента)
local function hpColors(pct)
	if pct > 0.5 then
		return Color3.fromRGB(111, 220, 95), Color3.fromRGB(53, 180, 53), Color3.fromRGB(31, 122, 36)
	elseif pct > 0.25 then
		return Color3.fromRGB(255, 215, 111), Color3.fromRGB(232, 185, 58), Color3.fromRGB(176, 132, 21)
	else
		return Color3.fromRGB(240, 122, 106), Color3.fromRGB(212, 53, 53), Color3.fromRGB(143, 29, 29)
	end
end

-- opts: { name, maxHp, cur?, difficulty? (1-5 или nil = без звёзд), width?, barHeight?, maxDistance? }
function EnemyHealthBar.new(opts)
	opts = opts or {}
	local width  = opts.width or 140
	local barH   = opts.barHeight or 22
	local nameH  = 17
	local starSz = 14
	local gap    = 4
	local hasStars = opts.difficulty ~= nil
	local totalH = nameH + gap + barH + (hasStars and (gap + starSz) or 0)

	local isSurface = opts.surface == true
	local host       -- вешаем на врага: BillboardGui (корабли) или Part с SurfaceGui (НПС)
	local guiParent  -- контейнер для UI

	if isSurface then
		-- НПС/пираты: SurfaceGui на тонком парте → бар МАСШТАБИРУЕТСЯ С РАССТОЯНИЕМ (как часть
		-- мира), а не остаётся огромным издалека, как экранный BillboardGui. Разворотом к
		-- камере занимается клиентский EnemyHPBillboard (тег "EnemyHPBoard").
		local PPS = 40
		local part = Instance.new("Part")
		part.Name = "EnemyHPBoard"
		part.Size = Vector3.new(width / PPS, totalH / PPS, 0.05)
		part.Transparency = 1
		part.CanCollide = false; part.CanQuery = false; part.CanTouch = false
		part.Massless = true; part.Anchored = true; part.CastShadow = false
		local sg = Instance.new("SurfaceGui")
		sg.Name = "EnemyHP"
		sg.Face = Enum.NormalId.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = PPS
		sg.LightInfluence = 0
		sg.AlwaysOnTop = false
		sg.Parent = part
		host = part
		guiParent = sg
	else
		local bb = Instance.new("BillboardGui")
		bb.Name = "EnemyHP"
		bb.Size = UDim2.fromOffset(width, totalH)
		bb.AlwaysOnTop = false -- НЕ сквозь стены: враг за препятствием → бар скрыт
		bb.LightInfluence = 0
		bb.MaxDistance = opts.maxDistance or 250
		host = bb
		guiParent = bb
	end

	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = guiParent
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, gap)
	list.Parent = root

	-- ── табличка с именем ──
	local namePlate = Instance.new("Frame")
	namePlate.LayoutOrder = 1
	namePlate.BackgroundColor3 = NAME_BG
	namePlate.AutomaticSize = Enum.AutomaticSize.X
	namePlate.Size = UDim2.fromOffset(0, nameH)
	namePlate.ZIndex = 2
	namePlate.Parent = root
	local nStroke = Instance.new("UIStroke")
	nStroke.Color = BLACK; nStroke.Thickness = 2; nStroke.Parent = namePlate
	local nPad = Instance.new("UIPadding")
	nPad.PaddingLeft = UDim.new(0, 8); nPad.PaddingRight = UDim.new(0, 8)
	nPad.Parent = namePlate
	-- раскладка таблички: [глаз][текст] — глаз виден только в режиме слежки
	local nList = Instance.new("UIListLayout")
	nList.FillDirection = Enum.FillDirection.Horizontal
	nList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	nList.VerticalAlignment = Enum.VerticalAlignment.Center
	nList.SortOrder = Enum.SortOrder.LayoutOrder
	nList.Padding = UDim.new(0, 4)
	nList.Parent = namePlate

	-- ИКОНКА ГЛАЗА, нарисованная фреймами: у шрифта нет глифа глаза (вместо него
	-- рисовался бы пустой прямоугольник-тофу), а внешний ассет — лишняя зависимость.
	local eye = Instance.new("Frame")
	eye.Name = "EyeIcon"
	eye.LayoutOrder = 1
	eye.Size = UDim2.fromOffset(26, 15) -- крупно: на SurfaceGui мелкая иконка не читается
	eye.BackgroundColor3 = WHITE
	eye.BorderSizePixel = 0
	eye.Visible = false
	eye.ZIndex = 3
	eye.Parent = namePlate
	local eyeCorner = Instance.new("UICorner")
	eyeCorner.CornerRadius = UDim.new(1, 0) -- линза
	eyeCorner.Parent = eye
	local eStroke = Instance.new("UIStroke")
	eStroke.Color = BLACK; eStroke.Thickness = 1.5; eStroke.Parent = eye
	local pupil = Instance.new("Frame")
	pupil.AnchorPoint = Vector2.new(0.5, 0.5)
	pupil.Position = UDim2.fromScale(0.5, 0.5)
	pupil.Size = UDim2.fromOffset(10, 10)
	pupil.BackgroundColor3 = BLACK
	pupil.BorderSizePixel = 0
	pupil.ZIndex = 4
	pupil.Parent = eye
	local pCorner = Instance.new("UICorner")
	pCorner.CornerRadius = UDim.new(1, 0)
	pCorner.Parent = pupil

	local nameLbl = Instance.new("TextLabel")
	nameLbl.LayoutOrder = 2
	nameLbl.BackgroundTransparency = 1
	nameLbl.AutomaticSize = Enum.AutomaticSize.X
	nameLbl.Size = UDim2.fromScale(0, 1)
	nameLbl.Font = FONT_NAME
	nameLbl.TextSize = 12
	nameLbl.TextColor3 = WHITE
	nameLbl.TextStrokeColor3 = BLACK
	nameLbl.TextStrokeTransparency = 0
	nameLbl.Text = opts.name or "ВРАГ"
	nameLbl.ZIndex = 3
	nameLbl.Parent = namePlate

	-- ── полоса HP ──
	local bar = Instance.new("Frame")
	bar.LayoutOrder = 2
	bar.Size = UDim2.fromOffset(width, barH)
	bar.BackgroundColor3 = BAR_BG
	bar.ZIndex = 2
	bar.Parent = root
	local bStroke = Instance.new("UIStroke")
	bStroke.Color = BLACK; bStroke.Thickness = 2; bStroke.Parent = bar

	-- заливка: отступ 2px по краям, ширина = pct (см. setHP)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Position = UDim2.fromOffset(2, 2)
	fill.Size = UDim2.new(1, -4, 1, -4)
	fill.BorderSizePixel = 0
	fill.ZIndex = 3
	fill.Parent = bar
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90 -- вертикальный: светлый сверху → тёмный снизу
	grad.Parent = fill
	-- блик сверху заливки
	local gloss = Instance.new("Frame")
	gloss.Position = UDim2.fromOffset(3, 2)
	gloss.Size = UDim2.new(1, -6, 0, 4)
	gloss.BackgroundColor3 = WHITE
	gloss.BackgroundTransparency = 0.65
	gloss.BorderSizePixel = 0
	gloss.ZIndex = 4
	gloss.Parent = fill

	-- число HP по центру всей полосы
	local numLbl = Instance.new("TextLabel")
	numLbl.BackgroundTransparency = 1
	numLbl.Size = UDim2.fromScale(1, 1)
	numLbl.Font = FONT_NUM
	numLbl.TextSize = 14
	numLbl.TextColor3 = WHITE
	numLbl.TextStrokeColor3 = BLACK
	numLbl.TextStrokeTransparency = 0
	numLbl.ZIndex = 5
	numLbl.Parent = bar

	-- ── звёзды сложности (картинка-ассет) ──
	local starLbls = {}
	if hasStars then
		local starRow = Instance.new("Frame")
		starRow.LayoutOrder = 3
		starRow.BackgroundTransparency = 1
		starRow.AutomaticSize = Enum.AutomaticSize.X
		starRow.Size = UDim2.fromOffset(0, starSz)
		starRow.ZIndex = 2
		starRow.Parent = root
		local sList = Instance.new("UIListLayout")
		sList.FillDirection = Enum.FillDirection.Horizontal
		sList.VerticalAlignment = Enum.VerticalAlignment.Center
		sList.SortOrder = Enum.SortOrder.LayoutOrder
		sList.Padding = UDim.new(0, 3)
		sList.Parent = starRow
		for i = 1, 5 do
			local s = Instance.new("ImageLabel")
			s.BackgroundTransparency = 1
			s.Size = UDim2.fromOffset(starSz, starSz)
			s.Image = STAR_IMG
			s.LayoutOrder = i
			s.ZIndex = 3
			s.Parent = starRow
			starLbls[i] = s
		end
	end

	local handle = { gui = host, surface = isSurface }

	-- Привязать бар над головой врага. Для SurfaceGui парт варится в модель врага и
	-- помечается тегом — клиент (EnemyHPBillboard) держит его над головой лицом к камере.
	-- Для BillboardGui (корабли) — просто Adornee + StudsOffset (можно и вручную через .gui).
	function handle.attach(head, upStuds, name)
		if not head then return end
		upStuds = upStuds or 2.4
		if name then host.Name = name end
		if isSurface then
			local ov = Instance.new("ObjectValue")
			ov.Name = "HeadRef"; ov.Value = head; ov.Parent = host
			host:SetAttribute("UpStuds", upStuds)
			host.CFrame = CFrame.new(head.Position + Vector3.new(0, upStuds, 0))
			host.Parent = head:FindFirstAncestorWhichIsA("Model") or head
			CollectionService:AddTag(host, "EnemyHPBoard")
			if RunService:IsServer() then boards[host] = head end
		else
			host.Adornee = head
			host.StudsOffset = Vector3.new(0, upStuds, 0)
			host.Parent = head:FindFirstAncestorWhichIsA("Model") or head
		end
	end

	local baseName = opts.name or "ВРАГ"

	function handle.setHP(cur, max)
		-- возврат из режима слежки: прячем глаз, возвращаем имя врага
		eye.Visible = false
		nameLbl.Text = baseName
		max = math.max(max or 1, 1)
		cur = math.clamp(cur or 0, 0, max)
		local pct = cur / max
		local light, mid, dark = hpColors(pct)
		-- ширина = pct от (полоса − 4px отступа), слева отступ 2px
		fill.Size = UDim2.new(pct, -4, 1, -4)
		fill.Visible = pct > 0
		fill.BackgroundColor3 = mid
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, light),
			ColorSequenceKeypoint.new(0.45, mid),
			ColorSequenceKeypoint.new(1, dark),
		})
		numLbl.Text = math.floor(cur + 0.5) .. " / " .. math.floor(max + 0.5)
	end

	function handle.setName(s)
		nameLbl.Text = s or ""
	end

	function handle.setDifficulty(n)
		for i = 1, 5 do
			local s = starLbls[i]
			if s then
				-- заработанные звёзды яркие, пустые — тусклые
				s.ImageTransparency = (i <= (n or 0)) and 0 or 0.72
			end
		end
	end

	-- ── РЕЖИМ СЛЕЖКИ ──
	-- Пока враг только «замечает» игрока, полоса показывает накопление слежки
	-- (жёлтая, без цифр). После первого урона хозяин переключает бар в HP
	-- обычным setHP — и обратно он уже не возвращается.
	function handle.setTracking(pct)
		pct = math.clamp(pct or 0, 0, 1)
		fill.Size = UDim2.new(pct, -4, 1, -4)
		fill.Visible = pct > 0
		local light = Color3.fromRGB(255, 236, 150)
		local mid   = Color3.fromRGB(255, 200, 46)
		local dark  = Color3.fromRGB(190, 140, 20)
		fill.BackgroundColor3 = mid
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, light),
			ColorSequenceKeypoint.new(0.45, mid),
			ColorSequenceKeypoint.new(1, dark),
		})
		numLbl.Text = ""     -- в режиме слежки цифр нет
		nameLbl.Text = ""    -- вместо имени — иконка глаза
		eye.Visible = true
	end

	-- показать/скрыть бар целиком (до начала слежки над головой пусто)
	function handle.setVisible(on)
		root.Visible = on and true or false
	end

	function handle.destroy()
		-- host, а не bb: у NPC бар живёт в SurfaceGui-парте, и bb там nil —
		-- прежний вариант падал с ошибкой при смерти врага
		host:Destroy()
	end

	-- инициализация
	handle.setHP(opts.cur or opts.maxHp, opts.maxHp)
	if hasStars then handle.setDifficulty(opts.difficulty) end

	return handle
end

return EnemyHealthBar
