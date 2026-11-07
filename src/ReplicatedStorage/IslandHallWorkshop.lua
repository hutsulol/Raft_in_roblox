--[[
	ИНТЕРЬЕР ТАВЕРНЫ (клиент) — AltarWorkshop из хендоффа V25, переделанный под плот.

	Детали строятся ОДИН раз на клиенте (IslandHallClient) в осях здания: у каждой
	своя поза rel относительно AssemblyOrigin. Каждый кадр Update ставит их все
	одним BulkMoveTo в origin * rel — плот плывёт, интерьер едет вместе с ним.
	Уровень декора — WorkshopLevel (0…3), не LevelMask: новые вещи «выпрыгивают»
	за 0,62 с с Back-easing и подъёмом 0,35 студа, старые стоят на месте.
	Руки работников тянутся к ступке и кристаллу (IK в осях торса), свечи мерцают.
]]

local W = {}

local wood = Color3.fromRGB(83, 49, 32)
local brass = Color3.fromRGB(181, 127, 48)
local cream = Color3.fromRGB(238, 216, 162)

function W.Build(folder)
	local entries = {}
	local byName = {}
	local tier = 0
	local function part(name, pos, size, color, material, shape, rotation)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		if shape then p.Shape = shape end
		p.Transparency = 1
		local e = { part = p, tier = tier, rel = CFrame.new(pos) * (rotation or CFrame.identity), size = size }
		table.insert(entries, e)
		byName[name] = byName[name] or e
		p.Parent = folder
		return p, e
	end
	local function cylinder(name, x, y, z, r, h, color, material)
		return part(name, Vector3.new(x, y, z), Vector3.new(h, r * 2, r * 2), color, material, Enum.PartType.Cylinder, CFrame.Angles(0, 0, math.pi / 2))
	end
	local function candle(x, y, z, h)
		cylinder("CandleSaucer", x, y, z, 0.24, 0.08, brass, Enum.Material.Metal)
		cylinder("Wax", x, y + h / 2, z, 0.13, h, cream)
		local flame, e = part("CandleFlame", Vector3.new(x, y + h + 0.12, z), Vector3.new(0.13, 0.29, 0.13), Color3.fromRGB(255, 184, 55), Enum.Material.Neon, Enum.PartType.Ball)
		e.flame = x * 3 + z * 2 + h
		local light = Instance.new("PointLight")
		light.Color = flame.Color
		light.Brightness = 0.45
		light.Range = 5
		light.Shadows = false
		light.Enabled = false
		light.Parent = flame
	end
	for _, side in ipairs({ -1, 1 }) do
		local x = side * 6
		tier = 0
		part("RitualTable", Vector3.new(x, 2.65, 3.6), Vector3.new(1.9, 0.23, 3.6), wood, Enum.Material.Wood)
		tier = 1
		part("VelvetRunner", Vector3.new(x, 2.78, 3.6), Vector3.new(1.36, 0.025, 3.3), Color3.fromRGB(82, 36, 75), Enum.Material.Fabric)
		tier = 0
		for _, dx in ipairs({ -0.7, 0.7 }) do
			for _, dz in ipairs({ -1.45, 1.45 }) do
				part("TableLeg", Vector3.new(x + dx, 1.3, 3.6 + dz), Vector3.new(0.18, 2.6, 0.18), wood, Enum.Material.Wood)
				tier = 1
				part("BrassFoot", Vector3.new(x + dx, 0.17, 3.6 + dz), Vector3.new(0.22, 0.32, 0.22), brass, Enum.Material.Metal)
				tier = 0
			end
		end
		tier = 1
		part("TableLowerShelf", Vector3.new(x, 0.8, 3.6), Vector3.new(1.65, 0.12, 3.2), wood, Enum.Material.Wood)
		for i = 1, 3 do
			part("StoredBook", Vector3.new(x, 0.93 + i * 0.14, 4.15), Vector3.new(0.95, 0.12, 0.67),
				({ Color3.fromRGB(69, 73, 79), Color3.fromRGB(109, 46, 49), Color3.fromRGB(70, 99, 77) })[i])
		end
		tier = 0; candle(x - 0.4, 2.82, 4.75, 0.66)
		tier = 1; candle(x + 0.35, 2.82, 4.7, 0.44)
		part("WallShelf", Vector3.new(x, 5.45, 6.85), Vector3.new(2.25, 0.16, 1.05), wood, Enum.Material.Wood)
		for i = 1, 4 do
			part("Grimoire", Vector3.new(x - 0.78 + i * 0.28, 5.95, 6.95), Vector3.new(0.22, 0.85, 0.58), Color3.fromRGB(45 + i * 14, 49, 67 + i * 9))
			part("BookClasp", Vector3.new(x - 0.78 + i * 0.28, 5.94, 6.64), Vector3.new(0.14, 0.12, 0.045), brass, Enum.Material.Metal)
		end
		candle(x + 0.75, 5.57, 6.75, 0.55)
		for i = 1, 3 do
			tier = i == 1 and 0 or 1
			local bx = x + (i - 2) * 0.44
			cylinder("EssenceBottle", bx, 3.02, 4.05, 0.15, 0.42, Color3.fromRGB(53 + i * 22, 115, 129 + i * 20), Enum.Material.Glass)
			cylinder("Cork", bx, 3.28, 4.05, 0.09, 0.12, wood)
		end
	end
	tier = 0
	cylinder("MortarBase", -5.8, 2.91, 2.7, 0.45, 0.25, Color3.fromRGB(72, 67, 84), Enum.Material.Slate)
	for i = 1, 12 do
		local a = i * math.pi / 6
		part("MortarRim", Vector3.new(-5.8 + math.cos(a) * 0.36, 3.1, 2.7 + math.sin(a) * 0.36), Vector3.new(0.19, 0.25, 0.19), Color3.fromRGB(103, 94, 112), Enum.Material.Slate)
	end
	cylinder("CrystalPowder", -5.8, 3.08, 2.7, 0.29, 0.025, Color3.fromRGB(160, 116, 240), Enum.Material.Neon)
	cylinder("Pestle", -5.8, 3.42, 2.7, 0.1, 0.58, cream, Enum.Material.Marble)
	cylinder("FocusBase", 5.8, 2.9, 2.7, 0.53, 0.18, brass, Enum.Material.Metal)
	part("FocusCrystal", Vector3.new(5.8, 3.33, 2.7), Vector3.new(0.43, 0.63, 0.43), Color3.fromRGB(126, 214, 243), Enum.Material.Neon, nil, CFrame.Angles(0, math.pi / 4, math.pi / 4))
	for i = 1, 16 do
		local a = i * math.pi / 8
		part("FocusRing", Vector3.new(5.8 + math.cos(a) * 0.49, 3.13, 2.7 + math.sin(a) * 0.49), Vector3.new(0.16, 0.07, 0.09), brass, Enum.Material.Metal, nil, CFrame.Angles(0, -a, 0))
	end
	for _, side in ipairs({ -1, 1 }) do
		part("OpenBookCover", Vector3.new(side * 6, 2.87, 3.55), Vector3.new(0.92, 0.12, 0.57), Color3.fromRGB(87, 39, 42))
		for _, page in ipairs({ -1, 1 }) do
			part("Parchment", Vector3.new(side * 6 + page * 0.23, 2.95, 3.55), Vector3.new(0.43, 0.035, 0.52), cream, nil, nil, CFrame.Angles(0, 0, -page * 0.12))
			for line = 1, 4 do
				part("InkLine", Vector3.new(side * 6 + page * 0.23, 2.98, 3.33 + line * 0.08), Vector3.new(0.29, 0.012, 0.018), Color3.fromRGB(84, 65, 63))
			end
		end
	end
	-- Уровень 2: аптечный шкаф, эссенции, звёздная карта
	tier = 2
	part("ApothecaryCabinet", Vector3.new(0, 1.25, 7.32), Vector3.new(4.7, 2.5, 0.85), wood, Enum.Material.Wood)
	for _, x in ipairs({ -1.15, 1.15 }) do
		part("CabinetDoor", Vector3.new(x, 1.27, 6.85), Vector3.new(2.15, 2.12, 0.09), Color3.fromRGB(111, 70, 45), Enum.Material.Wood)
		part("CabinetHandle", Vector3.new(x * 0.5, 1.3, 6.77), Vector3.new(0.12, 0.34, 0.08), brass, Enum.Material.Metal)
	end
	part("CabinetTop", Vector3.new(0, 2.58, 7.3), Vector3.new(4.9, 0.18, 1.0), wood, Enum.Material.Wood)
	for i = -2, 2 do
		cylinder("LargeEssence", i * 0.52, 2.96, 7.24, 0.18, 0.58, Color3.fromRGB(103 + i * 14, 111, 163), Enum.Material.Glass)
		cylinder("EssenceSeal", i * 0.52, 3.3, 7.24, 0.13, 0.12, brass, Enum.Material.Metal)
	end
	candle(-1.95, 2.72, 7.25, 0.78); candle(1.95, 2.72, 7.25, 0.58)
	part("StarChart", Vector3.new(0, 5.65, 7.72), Vector3.new(3.1, 2.9, 0.08), Color3.fromRGB(37, 39, 69))
	for _, x in ipairs({ -1.62, 1.62 }) do part("ChartFrame", Vector3.new(x, 5.65, 7.63), Vector3.new(0.13, 3.15, 0.13), brass, Enum.Material.Metal) end
	for _, y in ipairs({ 4.1, 7.2 }) do part("ChartFrame", Vector3.new(0, y, 7.63), Vector3.new(3.35, 0.13, 0.13), brass, Enum.Material.Metal) end
	for i = 1, 16 do
		local a = i * math.pi / 8
		part("ChartOrbit", Vector3.new(math.cos(a) * 1.1, 5.65 + math.sin(a) * 1.1, 7.64), Vector3.new(0.27, 0.035, 0.025), cream, nil, nil, CFrame.Angles(0, 0, a + math.pi / 2))
	end
	for i = 1, 7 do
		part("ChartStar", Vector3.new(math.sin(i * 4) * 0.9, 5.65 + math.cos(i * 2) * 0.88, 7.61), Vector3.new(0.1, 0.1, 0.03), cream, nil, nil, CFrame.Angles(0, 0, math.pi / 4))
	end
	-- Уровень 3: позолоченные резонаторы, отделка столов, символы на стене
	tier = 3
	for _, side in ipairs({ -1, 1 }) do
		local x = side * 3.25
		cylinder("ResonatorFoot", x, 0.15, 6.2, 0.42, 0.3, brass, Enum.Material.Metal)
		cylinder("ResonatorColumn", x, 1.47, 6.2, 0.19, 2.4, Color3.fromRGB(56, 52, 73), Enum.Material.Slate)
		cylinder("ResonatorCrown", x, 2.73, 6.2, 0.4, 0.16, brass, Enum.Material.Metal)
		part("ResonatorGem", Vector3.new(x, 3.18, 6.2), Vector3.new(0.38, 0.65, 0.38), Color3.fromRGB(205, 157, 245), Enum.Material.Neon, nil, CFrame.Angles(0, math.pi / 4, math.pi / 4))
		for i = 1, 20 do
			local a = i * math.pi / 10
			part("ResonatorHalo", Vector3.new(x + math.cos(a) * 0.52, 3.2 + math.sin(a) * 0.52, 6.2), Vector3.new(0.18, 0.065, 0.065), brass, Enum.Material.Metal, nil, CFrame.Angles(0, 0, a + math.pi / 2))
		end
		for _, z in ipairs({ 1.84, 5.36 }) do part("GildedTableEdge", Vector3.new(side * 6, 2.68, z), Vector3.new(1.95, 0.13, 0.09), brass, Enum.Material.Metal) end
		for i = 1, 7 do
			part("WallSigil", Vector3.new(side * (2.0 + i * 0.13), 4.25 + i * 0.35, 7.58), Vector3.new(0.16, 0.16, 0.065), brass, Enum.Material.Metal, nil, CFrame.Angles(0, 0, math.pi / 4))
		end
	end
	return { entries = entries, byName = byName, level = nil }
end

-- мебель, сквозь которую не пройти (коллизия локальная — у своего персонажа)
local SOLID = { RitualTable = true, TableLeg = true, ApothecaryCabinet = true, CabinetTop = true,
	ResonatorFoot = true, ResonatorColumn = true, MortarBase = true, FocusBase = true }

local function backOut(u)
	return 1 + 2.70158 * (u - 1) ^ 3 + 1.70158 * (u - 1) ^ 2
end

--[[ Кадр интерьера. origin — CFrame AssemblyOrigin; level — Level здания;
     t — время цикла работников; offsets[name] — сдвиг инструмента (ступка/кристалл). ]]
function W.Update(ws, origin, level, t, offsets)
	local now = os.clock()
	if ws.level ~= level then
		local index = 0
		for _, e in ipairs(ws.entries) do
			if ws.level ~= nil and e.tier > ws.level and e.tier <= level then
				index += 1
				e.start = now + math.min(index * 0.012, 0.5)
			else
				e.start = nil
			end
		end
		ws.level = level
	end
	local parts, cfs = {}, {}
	for _, e in ipairs(ws.entries) do
		local p = e.part
		local visible = e.tier <= level
		local rel = e.rel
		if offsets and offsets[p.Name] then rel = CFrame.new(offsets[p.Name]) * rel end
		if e.start and visible then
			local u = math.clamp((now - e.start) / 0.62, 0, 1)
			p.Size = e.size * (0.22 + 0.78 * backOut(u))
			rel = CFrame.new(0, (1 - u) * 0.35, 0) * rel
			p.Transparency = 1 - math.clamp(u * 5, 0, 1)
			if u >= 1 then e.start = nil; p.Size = e.size end
		else
			p.Transparency = visible and 0 or 1
		end
		local solid = visible and SOLID[p.Name] == true
		if p.CanCollide ~= solid then p.CanCollide = solid end
		if e.flame and visible then
			local f = t * 7 + e.flame
			p.Size = Vector3.new(0.13, 0.27 + math.sin(f) * 0.035, 0.13)
			local light = p:FindFirstChildOfClass("PointLight")
			if light then
				light.Enabled = p.Transparency < 0.5
				light.Brightness = 0.42 + 0.08 * math.sin(f) + 0.035 * math.sin(f * 2.3)
			end
		end
		table.insert(parts, p)
		table.insert(cfs, origin * rel)
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

return W
