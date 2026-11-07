--[[ AnchorRig — ОДНО МЕСТО, ГДЕ РЕШАЕТСЯ, ЧТО У ЛЕБЁДКИ ВИСИТ НА ТРОСЕ.

     Раньше это решали три файла независимо: постройка (BuildingSystem),
     призрак (AnchorBuildSystem) и сама лебёдка (AnchorInteraction). Правила
     в них разошлись, и получилось наглядно: рама висела свободно, а якорь
     был приварен к плоту — то есть ровно наоборот. Поэтому теперь правило
     живёт здесь, а те трое только спрашивают.

     ⚠️ ПОЧЕМУ НЕ «ДАЛЬНИЙ КОНЕЦ ТРОСА».
     Казалось бы, надёжно: RopeConstraint лежит в одной детали, вторая —
     груз. Но в модели он может лежать и в самом якоре, и тогда правило
     переворачивается — мы это уже проходили. Геометрия честнее: якорь ВИСИТ,
     то есть он ниже точки подвеса, что бы там ни лежало.

     ⚠️ КАК ПЕРЕОПРЕДЕЛИТЬ РУКАМИ.
     Если автоматика однажды выберет не ту деталь, в Studio ставится атрибут
     AnchorHang = true на нужную — он старше всех правил ниже и переживёт
     любую перерисовку модели. ]]

local AnchorRig = {}

-- слова в имени детали: первый список говорит «это груз», второй — «нет, рама»
local ANCHOR_WORDS = { "anchor", "якор", "yakor", "hook" }
local NOT_ANCHOR_WORDS = {
	"deck", "доск", "настил", "frame", "рам", "wheel", "колес", "drum",
	"бараб", "stand", "base", "pillar", "log", "rope", "трос", "верев",
	"handle", "ручк", "axle", "ось",
}

local function hasWord(name, list)
	local low = string.lower(name)
	for _, w in ipairs(list) do
		if string.find(low, w, 1, true) then return true end
	end
	return false
end

-- ⚠️ ОБЪЯВЛЕНО ДО AnchorRig.rope, И ЭТО ВАЖНО: в Lua нет подъёма, а rope()
-- зовёт эту функцию — стоя ниже, она была бы там nil.
-- обе детали, между которыми натянут трос; любая может оказаться nil —
-- у ненастроенного констрейнта аттачей нет вовсе
local function ropeEnds(rope)
	if not rope then return nil, nil end
	local a0 = rope.Attachment0 and rope.Attachment0.Parent
	local a1 = rope.Attachment1 and rope.Attachment1.Parent
	if a0 and not a0:IsA("BasePart") then a0 = nil end
	if a1 and not a1:IsA("BasePart") then a1 = nil end
	return a0, a1
end
AnchorRig.ropeEnds = ropeEnds

--[[ ⚠️ ТРОСОВ В МОДЕЛИ МОЖЕТ БЫТЬ НЕ ОДИН.
     Раньше брался ПЕРВЫЙ попавшийся в обходе — а в модели рядом с рабочим
     тросом легко живёт декоративный (намотка на барабане, оснастка рамы).
     Тянешь длину не у того — лебёдка «не работает», и по логу это никак не
     отличить от заваренного якоря.
     Поэтому сначала ищем трос, который ДЕРЖИТ ГРУЗ: лежит в нём самом или
     привязан к нему аттачем. Только если такого нет — берём первый. ]]
function AnchorRig.rope(model)
	if not model then return nil end
	local weight = AnchorRig.hangingByName(model)
	if weight then
		for _, d in model:GetDescendants() do
			if d:IsA("RopeConstraint") then
				local a0, a1 = ropeEnds(d)
				if d.Parent == weight or d:IsDescendantOf(weight)
					or a0 == weight or a1 == weight then return d end
			end
		end
	end
	local inner = model:FindFirstChild("anchor")
	if inner then
		local rc = inner:FindFirstChildOfClass("RopeConstraint")
		if rc then return rc end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("RopeConstraint") then return d end
	end
	return nil
end

--[[ Правила, которым трос НЕ НУЖЕН. Отдельно от hangingPart, потому что
     ими пользуется сама rope(): иначе получилось бы кольцо «чтобы найти
     трос, найди груз; чтобы найти груз, найди трос». ]]
function AnchorRig.hangingByName(model)
	if not model then return nil end

	-- 1. ручное указание — старше всего остального
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("AnchorHang") then return d end
	end

	--[[ 2. ДЕТАЛЬ, НАЗВАННАЯ КАК САМА МОДЕЛЬ, — ЭТО ГРУЗ.
	     Так собран Raft_anchor: внутри модели «Raft_anchor» лежат деталь
	     «Raft_anchor» (сам якорь, он один и висит) и «Raft_anchor_deck»,
	     «Raft_anchor_wheel» и прочая рама. Правило владельца дословно:
	     свободен только Raft_anchor, всё остальное закреплено.
	     Стоит выше поиска по словам: «Raft_anchor_deck» тоже содержит
	     «anchor», и списками исключений это пришлось бы вечно догонять. ]]
	local exact = model:FindFirstChild(model.Name)
	if exact and exact:IsA("BasePart") then return exact end

	-- 3. старая модель: там груз — целая подмодель «anchor»
	if model.Name == "Anchor_part" then
		local inner = model:FindFirstChild("anchor")
		if inner then return inner end
	end

	-- 4. по имени детали, но только если оно не про раму
	local byName
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and hasWord(d.Name, ANCHOR_WORDS)
			and not hasWord(d.Name, NOT_ANCHOR_WORDS) then
			if not byName or d.Position.Y < byName.Position.Y then byName = d end
		end
	end
	if byName then return byName end

	return nil
end

function AnchorRig.hangingPart(model)
	local byName = AnchorRig.hangingByName(model)
	if byName then return byName end
	-- 5. геометрия: из двух концов троса груз — тот, что НИЖЕ
	local a0, a1 = ropeEnds(AnchorRig.rope(model))
	if a0 and a1 and a0 ~= a1 then
		return (a0.Position.Y <= a1.Position.Y) and a0 or a1
	end
	return a0 or a1
end

--[[ ⚠️ ГРУЗ ОБЯЗАН БЫТЬ СВОБОДЕН — ПРОВЕРЯЕМ, А НЕ НАДЕЕМСЯ.
     Прибить якорь к плоту умеют сразу несколько систем: страховочный сварщик,
     загрузка сейва, сама постановка. Симптом у всех один и снаружи
     неотличим — трос удлиняется, якорь стоит.
     Столкновения снимаем отдельно: с CanCollide якорь упирается в настил
     плота, сквозь который ему и надо пройти, и «не опускается» уже по
     совершенно другой причине. ]]
function AnchorRig.free(model)
	local part = AnchorRig.hangingPart(model)
	if not part then return nil, "груз не найден" end

	local parts = {}
	if part:IsA("BasePart") then
		table.insert(parts, part)
	else
		for _, d in part:GetDescendants() do
			if d:IsA("BasePart") then table.insert(parts, d) end
		end
	end

	local done = {}
	local unanchored, welds, collided = 0, 0, 0
	for _, p in ipairs(parts) do
		if p.Anchored then p.Anchored = false; unanchored += 1 end
		if p.CanCollide then p.CanCollide = false; collided += 1 end
		p.Massless = false
		p:SetAttribute("NoRaftWeld", true)
		for _, d in ipairs(p:GetChildren()) do
			if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") then
				d:Destroy()
				welds += 1
			end
		end
	end
	-- сварку могли повесить и в чужой детали — ищем по всей модели
	for _, d in model:GetDescendants() do
		if d:IsA("WeldConstraint") or d:IsA("Weld") then
			for _, p in ipairs(parts) do
				if d.Part0 == p or d.Part1 == p then
					d:Destroy()
					welds += 1
					break
				end
			end
		end
	end

	if unanchored > 0 then table.insert(done, "снят якорь") end
	if welds > 0 then table.insert(done, ("сварок снято %d"):format(welds)) end
	if collided > 0 then table.insert(done, "выключены столкновения") end
	return part, (#done > 0) and table.concat(done, ", ") or nil
end

--[[ ⚠️ НЕНАСТРОЕННЫЙ ТРОС ВЫГЛЯДИТ КАК СЛОМАННАЯ ЛЕБЁДКА.
     У RopeConstraint без Attachment0/Attachment1 длина меняется, а держать
     ему нечего: якорь просто стоит на месте, и в логе это ничем не пахнет.
     Чиним один раз при первой встрече: вешаем аттачи на деталь подвеса и на
     груз. Точки берём в их центрах — трос короткий, разница не видна, а
     угадывать место крепления по геометрии смысла нет. ]]
function AnchorRig.ensureRope(model)
	local rope = AnchorRig.rope(model)
	if not rope then return nil, "троса в модели нет" end
	local a0, a1 = ropeEnds(rope)
	if a0 and a1 and a0 ~= a1 then return rope, nil end

	local weight = AnchorRig.hangingPart(model)
	if weight and not weight:IsA("BasePart") then
		weight = weight:FindFirstChildWhichIsA("BasePart", true)
	end
	local top = rope.Parent
	if not (top and top:IsA("BasePart")) or top == weight then
		top = nil
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= weight
				and (not top or d.Position.Y > top.Position.Y) then
				top = d
			end
		end
	end
	if not (weight and top) then return rope, "трос не к чему привязать" end

	local function attach(part, name)
		local a = part:FindFirstChild(name)
		if not (a and a:IsA("Attachment")) then
			a = Instance.new("Attachment")
			a.Name = name
			a.Parent = part
		end
		return a
	end
	rope.Attachment0 = attach(top, "AnchorRopeTop")
	rope.Attachment1 = attach(weight, "AnchorRopeWeight")
	return rope, ("трос подвязан: «%s» → «%s»"):format(top.Name, weight.Name)
end

--[[ Разбор модели одной пачкой строк: кто заякорен, кто приварен, как
     подвязан трос. Печатается один раз — чтобы не гадать по симптомам. ]]
function AnchorRig.describe(model)
	if not model then return "модели нет" end
	local rope = AnchorRig.rope(model)
	local hang = AnchorRig.hangingPart(model)
	local lines = { ("модель «%s»"):format(model.Name) }

	local a0, a1 = ropeEnds(rope)
	if rope then
		table.insert(lines, ("  трос в «%s»: A0=%s A1=%s длина=%.2f"):format(
			rope.Parent and rope.Parent.Name or "?",
			a0 and a0.Name or "нет", a1 and a1.Name or "нет", rope.Length))
	else
		table.insert(lines, "  троса нет")
	end
	table.insert(lines, ("  груз: %s"):format(hang and hang.Name or "НЕ НАЙДЕН"))

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local welds = 0
			for _, w in ipairs(d:GetChildren()) do
				if w:IsA("WeldConstraint") or w:IsA("Weld") then welds += 1 end
			end
			table.insert(lines, ("  · %s | заякорена=%s сварок=%d столкн=%s | Y=%.1f"):format(
				d.Name, tostring(d.Anchored), welds, tostring(d.CanCollide), d.Position.Y))
		end
	end
	return table.concat(lines, "\n")
end

return AnchorRig
