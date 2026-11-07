-- BackpackGuide.client.lua
-- Навигация к рюкзаку-туториалу: цепочка БЕЛЫХ стрелок-шевронов «бежит» по палубе от ног
-- игрока к рюкзаку (как маркеры пути в других играх). Никакого текста над рюкзаком —
-- подпись автор добавил в саму модель. Пока игрок НЕ подобрал рюкзак (атрибут
-- HasBackpack), стрелки ведут к нему; в момент подбора всё исчезает. Чисто локально.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local player = Players.LocalPlayer
local MODEL_NAME = "BackPack"

-- уже подобран (в т.ч. восстановлен из сейва) — дорожка не нужна
if player:GetAttribute("HasBackpack") then return end

-- ── вид дорожки ──
local ARROWS   = 8    -- шевронов в пуле (дальние просто прячутся)
local SPACING  = 6    -- студов между стрелками
local SPEED    = 5    -- студов/с — стрелки «бегут» в сторону рюкзака
local HOVER    = 0.25 -- высота над палубой
local ANG      = 50   -- раскрытие «уголка» шеврона (градусы)
local MIN_DIST = 5    -- ближе этого дорожку не рисуем (промпт уже виден)

local function findBackpackModel()
	local direct = Workspace:FindFirstChild(MODEL_NAME)
	if direct then return direct end
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == MODEL_NAME then return d end
	end
	return nil
end

-- самый крупный парт модели — целевая точка (парт "BillboardGui" прозрачный и качается)
local function findAnchorPart(model)
	if model:IsA("BasePart") then return model end
	local best, bestVolume = nil, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "BillboardGui" then
			local s = d.Size
			local v = s.X * s.Y * s.Z
			if v > bestVolume then best, bestVolume = d, v end
		end
	end
	return best
end

local function lerp(a, b, t) return a + (b - a) * t end

task.spawn(function()
	-- рюкзак может появляться не сразу — ждём до ~30 секунд
	local model, part
	for _ = 1, 60 do
		model = findBackpackModel()
		part = model and findAnchorPart(model)
		if part then break end
		task.wait(0.5)
	end
	if not part then return end -- карта без рюкзака (лобби)
	if player:GetAttribute("HasBackpack") then return end

	-- ── пул шевронов: каждый — два белых неоновых бруска «уголком» ──
	-- Создано LocalScript'ом → существует только у этого игрока.
	local folder = Instance.new("Folder")
	folder.Name = "BackpackGuideArrows"
	folder.Parent = Workspace

	local function makeArm()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.new(1, 1, 1)
		p.Size = Vector3.new(1.4, 0.1, 0.35)
		p.Transparency = 1
		p.Parent = folder
		return p
	end
	local chevrons = {}
	for i = 1, ARROWS do
		chevrons[i] = { L = makeArm(), R = makeArm() }
	end

	local function hideChevron(c)
		c.L.Transparency = 1
		c.R.Transparency = 1
	end

	-- ── обновление дорожки каждый кадр ──
	local t = 0
	local renderConn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not (hrp and part.Parent) then
			for _, c in ipairs(chevrons) do hideChevron(c) end
			return
		end

		local from = hrp.Position - Vector3.new(0, 2.6, 0) -- от ног
		local to = part.Position
		local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
		local len = flat.Magnitude
		if len < MIN_DIST then
			for _, c in ipairs(chevrons) do hideChevron(c) end
			return
		end
		local dir = flat.Unit

		-- стрелки «бегут» к рюкзаку: смещение по пути растёт со временем и зацикливается
		local offset = (t * SPEED) % SPACING
		for i = 1, ARROWS do
			local c = chevrons[i]
			local s = offset + (i - 1) * SPACING
			if s < len - 2 then
				local pos = Vector3.new(from.X, 0, from.Z) + dir * s
				local y = lerp(from.Y, to.Y, s / len) + HOVER
				pos = Vector3.new(pos.X, y, pos.Z)
				local base = CFrame.lookAt(pos, pos + dir)
				-- плавный вход/выход на концах дорожки
				local edge = math.clamp(math.min(s / SPACING, (len - 2 - s) / SPACING), 0, 1)
				local tr = lerp(1, 0.1, edge)
				c.L.Transparency = tr
				c.R.Transparency = tr
				c.L.CFrame = base * CFrame.new(-0.45, 0, -0.05) * CFrame.Angles(0, math.rad(ANG), 0)
				c.R.CFrame = base * CFrame.new(0.45, 0, -0.05) * CFrame.Angles(0, math.rad(-ANG), 0)
			else
				hideChevron(c)
			end
		end
	end)

	-- ── уборка: рюкзак подобран или модель исчезла ──
	local done = false
	local function cleanup()
		if done then return end
		done = true
		renderConn:Disconnect()
		folder:Destroy()
	end
	player:GetAttributeChangedSignal("HasBackpack"):Connect(function()
		if player:GetAttribute("HasBackpack") then cleanup() end
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then cleanup() end
	end)
end)
