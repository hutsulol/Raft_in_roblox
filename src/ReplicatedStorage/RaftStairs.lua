--[[
	ЛЕСТНИЦА НА ВТОРОЙ ЭТАЖ (модель Raft_stairs, молоток → «Floors» → «Лестница»).
	Общий модуль: одна и та же поза у призрака (BuildingSystem.client) и у
	сервера (BuildingSystem.server), иначе лестница вставала бы не туда, куда
	показывал призрак.

	Модель запечена под сетку (D:/Roblox/test/src/bake_stairs.py): 10 студов
	поперёк клетки, выход на 7.745 над настилом — верх стены (7.782 − SINK 0.35)
	плюс пол второго этажа (0.41 − SINK 0.1), то есть ровно на его верх.
	Ставится на ЛЮБУЮ клетку пола, центром габарита в центр клетки, низом на
	настил; R поворачивает на четверть.

	raft_stairs_ramp — невидимая наклонная плоскость, по которой персонаж
	поднимается (по ступеням он бы спотыкался). В призраке её нет вовсе, в
	поставленной лестнице она прозрачная, но твёрдая.
]]

local RaftStairs = {}

RaftStairs.NAME = "Raft_stairs"
RaftStairs.RAMP = "raft_stairs_ramp"
RaftStairs.COSTS = { Log = 6, Rope = 1 }

-- верх детали по вертикали мира (для наклонных брёвен настила тоже)
local function partTop(p)
	local cf, sz = p.CFrame, p.Size
	local up = Vector3.yAxis
	return cf.Position.Y + math.abs(cf.RightVector:Dot(up)) * sz.X * 0.5
		+ math.abs(cf.UpVector:Dot(up)) * sz.Y * 0.5
		+ math.abs(cf.LookVector:Dot(up)) * sz.Z * 0.5
end

-- центр клетки: PrimaryPart тайла, иначе самая крупная деталь
function RaftStairs.tileCenter(tile)
	if tile:IsA("BasePart") then return tile.Position end
	if tile.PrimaryPart then return tile.PrimaryPart.Position end
	local best, vol = nil, -1
	for _, d in ipairs(tile:GetDescendants()) do
		if d:IsA("BasePart") and d.Size.X * d.Size.Y * d.Size.Z > vol then best, vol = d, d.Size.X * d.Size.Y * d.Size.Z end
	end
	return best and best.Position
end

-- верх настила клетки — по видимым деталям тайла
function RaftStairs.tileTop(tile)
	local best
	local parts = tile:IsA("BasePart") and { tile } or tile:GetDescendants()
	for _, p in ipairs(parts) do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local y = partTop(p)
			if not best or y > best then best = y end
		end
	end
	return best
end

--[[ Куда поставить центр габарита модели: над центром клетки, низом на
     настил, поворот — RestYaw плота + rot четвертей. model — сама модель
     (её высота), с пивотом в центре габарита (prepare). ]]
function RaftStairs.placeCF(raft, tile, rot, model)
	local primary = raft.PrimaryPart
	local yaw = primary:GetAttribute("RestYaw")
	if not yaw then
		local _, y = primary.CFrame:ToEulerAnglesYXZ()
		yaw = y
	end
	local c, top = RaftStairs.tileCenter(tile), RaftStairs.tileTop(tile)
	if not (c and top) then return nil end
	--[[ ⚠️ УТАПЛИВАЕМ, КАК СТЕНЫ. Верх клетки по габариту — это верх скоб и
	     верёвок на досках, а не самих досок: лестница висела над полом ровно на
	     их высоту. Стены от того же верха опускают на WallDefs.SINK — берём то же
	     число, чтобы лестница стояла на одном уровне со стенами. ]]
	local okW, WallDefs = pcall(require, script.Parent:WaitForChild("RaftWallDefs"))
	-- пол второго этажа — тонкая плита без скоб сверху: там утапливаем чуть-чуть
	local upper = tile.Name == "Raft_floor_upper" or tile:GetAttribute("BuildType") == "floor_upper"
	top -= upper and 0.1 or ((okW and WallDefs.SINK) or 0.35)
	local _, size = RaftStairs.bounds(model)
	return CFrame.new(c.X, top + size.Y * 0.5, c.Z) * CFrame.Angles(0, yaw + math.rad(90 * ((rot or 0) % 4)), 0)
end

--[[ ⚠️ ГАБАРИТ БЕЗ РАМПЫ. Невидимая рампа уходит ниже ступеней: по общему
     габариту модели на настил ложился её низ, и видимая лестница висела над
     полом. У призрака рампы нет вовсе — он стоял ровно, а поставленная
     лестница нет. Считаем габарит только по видимым деталям, в осях мира. ]]
function RaftStairs.bounds(model)
	local mn, mx
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= RaftStairs.RAMP then
			local h = d.Size * 0.5
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local p = d.CFrame * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
						mn = mn and mn:Min(p) or p
						mx = mx and mx:Max(p) or p
					end
				end
			end
		end
	end
	if not mn then
		local cf, size = model:GetBoundingBox()
		return cf.Position, size
	end
	return (mn + mx) * 0.5, mx - mn
end

-- пивот модели — в центр габарита ВИДИМЫХ деталей, без наклона
function RaftStairs.prepare(model)
	if model:IsA("Model") then
		local c = RaftStairs.bounds(model)
		model.WorldPivot = CFrame.new(c)
	end
	return model
end

return RaftStairs
