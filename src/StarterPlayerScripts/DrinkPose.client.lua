local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ПОЗА ПИТЬЯ: правая рука к лицу, голова слегка вниз.

	⚠️ СДЕЛАНО ПО ОБРАЗЦУ ОГНЕМЁТА (FlamethrowerClient), А НЕ ЧЕРЕЗ Animation.
	У здешнего рига нет Motor6D — части держит AnimationConstraint со своим
	Transform. Поэтому:
	  • «сустав» ищем по ИМЕНИ ДЕТАЛИ и принимаем все три вида сочленений;
	  • пишем в Transform, а не в C0 (у AnimationConstraint его нет вовсе);
	  • пишем ПОСЛЕ аниматора — BindToRenderStep с приоритетом Character + 1 —
	    и повторяем в Stepped: у физического рига Transform это ЦЕЛЬ для
	    решателя, и на шаге физики он берёт то, что осталось от аниматора.

	Когда пить: сервер (ThirstSystem) на время глотка ставит на персонажа атрибут
	Drinking. Он же отмеряет длительность и ровно столько же подливает шкалу воды,
	поэтому поза и наполнение идут секунда в секунду — без своих таймеров здесь.
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- ⚠️ ТАБЛИЦЫ РАЗДЕЛЕНЫ ПО РИГАМ, И ЗНАКИ У НИХ РАЗНЫЕ.
-- Первый заход держал один набор на оба рига и с углом −118 у плеча. Обе вещи
-- были неверны, и вместе давали руку, заброшенную за голову, — со стороны
-- «перевёрнуто на 180°». Разбор по образцу огнемёта (FlamethrowerClient, POSE и
-- POSE_IDLE):
--   • у R6 минус по X ПОДНИМАЕТ руку, у R15 — наоборот, поднимает плюс;
--   • шкала сжатая: у R6 всего +25 это уже рука вертикально вниз. Значит подъём
--     к лицу — это ДЕСЯТКИ градусов, а не сотня; −118 прокручивало руку далеко
--     за вертикаль.
-- Z подводит кисть внутрь, к середине лица: без него рука поднимается сбоку и
-- сосуд оказывается у уха, а не у рта.
-- ⚠️ ЗНАК ПО X — ПОЛОЖИТЕЛЬНЫЙ: ЭТО «ВПЕРЁД И ВВЕРХ», К ЛИЦУ.
-- Проверено на этом же риге взмахом при добыче: там +110 бьёт вперёд, а минус
-- уводил руку назад за плечо. Здесь я сначала поставил минус — и рука пошла ОТ
-- рта. Ещё и величину взял вдвое меньше нужной, поэтому движение было едва
-- заметным. Тянемся к лицу: подъём большой, Z уводит кисть внутрь, к середине.
-- ⚠️ ВБОК ВЕДЁТ Y, А НЕ Z. Z — ЭТО ПРОКРУТ РУКИ ВОКРУГ СЕБЯ.
-- Оба знака по Z дали одно и то же: сосуд уезжал влево, причём плюс сильнее
-- минуса. Так себя ведёт не смещение, а КРУЧЕНИЕ: рука стоит на месте, а бутылка
-- в кисти заметает дугу — чем больше угол, тем дальше её конец уходит вбок.
-- Ось подъёма (X) уже занята, значит вбок остаётся Y, и Z обнуляем: лишний
-- прокрут только разворачивал бутылку мимо рта.
-- Разбор осей, как он сложился по правкам:
--   X — подъём руки вперёд-вверх, к лицу;
--   Y — увод кисти вбок, к середине тела (рука доходит до головы);
--   Z — ПРОКРУТ вокруг оси руки. Сама рука при нём не двигается, зато конец
--       сосуда описывает дугу — им и доворачиваем горлышко от уха ко рту.
-- Прокрут вешаем на ПРЕДПЛЕЧЬЕ (у R15 оно есть): это ближе к запястью, и
-- разворачивается именно кисть, а не всё плечо вместе с локтем.
local POSE = {
	R6 = {
		["Right Arm"] = { 86, 58, -28 },
		["Head"]      = { 22,  0,   0 },   -- голова вниз, навстречу сосуду
	},
	R15 = {
		RightUpperArm = { 78, 54,   0 },
		-- ⚠️ ВЕРНУЛ 74: 90° ДВИГАЛИ ВСЮ РУКУ, А НЕ КИСТЬ.
		-- Предплечье — это ЛОКОТЬ. Догибая его, я уводил вперёд всё, что ниже
		-- локтя, и поза, которая была почти собрана, разъезжалась. Наклон самой
		-- кисти делается запястьем — ниже отдельной строкой.
		RightLowerArm = { 74,  0, -28 },
		-- Запястье: держим в нуле как базу, а доворот приходит поправкой на сосуд
		-- (VESSEL_TUNE.wrist) — у кружки и бутылки он разный.
		RightHand     = {  0,  0,   0 },
		Head          = { 22,  0,   0 },
	},
}

-- ⚠️ ПОЗА ЗАВИСИТ ОТ СОСУДА, И ОДНОЙ НА ДВОИХ НЕ ВЫХОДИТ.
-- Кружка маленькая: чтобы она дошла до рта, руку надо поднять ВЫШЕ. Бутылка
-- длинная — ей хватает меньшего подъёма, зато горлышко нужно чуть дальше увести
-- к центру. С общей позой одно из двух всегда мимо: кружка не доносит, бутылка
-- перебирает. Поправки прибавляются к суставу, который держит подъём.
-- Поправок ДВЕ, потому что и различий два:
--   lift  — насколько выше/ниже поднимается вся рука (плечо);
--   wrist — насколько сильнее согнута кисть (предплечье). Она решает, во что
--           упирается край сосуда: в рот или в шею. У кружки край широкий и
--           близко к кисти, поэтому её надо доворачивать сильнее, чем бутылку с
--           длинным горлышком.
local VESSEL_TUNE = {
	Cup         = { lift = {  18,  0, 0 }, wrist = { 22, 0, 0 } },
	WaterBottle = { lift = { -12, 10, 0 }, wrist = { 14, 0, 0 } },
}
-- ⚠️ КИСТЬ — ЭТО ЗАПЯСТЬЕ (RightHand), А НЕ ПРЕДПЛЕЧЬЕ.
-- Поправка стояла на RightLowerArm, но это локоть: он уводит всю нижнюю половину
-- руки, а не поворачивает кисть. Отсюда и «ты двинул всю руку». У R6 отдельной
-- кисти нет вовсе — там рука одна деталь, и обе поправки поневоле идут в плечо.
local LIFT_JOINT  = { R6 = "Right Arm", R15 = "RightUpperArm" }
local WRIST_JOINT = { R6 = "Right Arm", R15 = "RightHand" }

local BLEND_IN  = 9    -- скорость набора позы (1/сек)
local BLEND_OUT = 6    -- и возврата

local joints, scanned, physicalRig = {}, nil, false
local rig = "R6"
local k = 0            -- 0 = обычная поза, 1 = пьёт

local function collectJoints(char)
	joints, scanned, physicalRig = {}, char, false
	if not char then return end
	-- ⚠️ РИГ ОПРЕДЕЛЯЕМ ПО ДЕТАЛИ РУКИ, ДА ЕЩЁ И В ГЛУБИНУ.
	-- Здесь стояла проверка на прямого ребёнка «UpperTorso». У здешнего рига его
	-- нет — и скрипт решал, что это R6, брал набор с ключом «Right Arm», а деталь
	-- в модели называется RightUpperArm. Совпадений ноль, поза не применялась
	-- вовсе: игрок видел обычную стойку и принимал её за «анимацию оглядывания».
	-- Спрашиваем ровно про ту деталь, которую собираемся крутить.
	if char:FindFirstChild("RightUpperArm", true) then
		rig = "R15"
	elseif char:FindFirstChild("Right Arm", true) then
		rig = "R6"
	else
		rig = char:FindFirstChild("UpperTorso", true) and "R15" or "R6"
	end
	local set = POSE[rig]

	-- ⚠️ ИМЯ ДЕТАЛИ ИЩЕМ С ДВУХ КОНЦОВ, А НЕ ТОЛЬКО ЧЕРЕЗ Attachment1.
	-- Голова так и не наклонялась: у её сочленения нужная деталь оказывается не
	-- всегда на том конце, что у руки. Проверяем оба конца и, если не вышло, само
	-- имя сочленения — «Neck», «Head» и т.п.
	local function limbOf(d)
		if d:IsA("AnimationConstraint") then
			for _, att in ipairs({ d.Attachment1, d.Attachment0 }) do
				local nm = att and att.Parent and att.Parent.Name
				if nm and set[nm] then physicalRig = true return nm end
			end
		elseif d:IsA("Motor6D") then
			for _, p in ipairs({ d.Part1, d.Part0 }) do
				if p and set[p.Name] then return p.Name end
			end
		elseif d:IsA("Bone") then
			if set[d.Name] then return d.Name end
		end
		-- запасной путь: по имени самого сочленения («Neck» держит голову)
		if d:IsA("AnimationConstraint") or d:IsA("Motor6D") then
			local n = d.Name:lower()
			if set["Head"] and (n:find("neck") or n == "head") then
				if d:IsA("AnimationConstraint") then physicalRig = true end
				return "Head"
			end
		end
		return nil
	end

	for _, d in ipairs(char:GetDescendants()) do
		local limb = limbOf(d)
		-- первая находка на деталь и остаётся: у руки сочленение одно, а
		-- перезаписывать его случайным вторым совпадением незачем
		if limb and not joints[limb] then joints[limb] = d end
	end

	-- Печатаем и найденное, и НЕДОСТАЮЩЕЕ: пустой список сам по себе не говорит,
	-- ошиблись ли мы ригом или не нашли конкретный сустав.
	local found, missing = {}, {}
	for name in pairs(set) do
		if joints[name] then found[#found + 1] = name else missing[#missing + 1] = name end
	end
	table.sort(found); table.sort(missing)
	print(("[Питьё] риг %s | найдено: %s | не найдено: %s"):format(rig,
		(#found > 0) and table.concat(found, ", ") or "ничего",
		(#missing > 0) and table.concat(missing, ", ") or "—"))
end

-- Какой сосуд сейчас в руках. Любой тул с атрибутом CupState — сосуд; его вид
-- говорит CupBase (его же ставит WaterBottleSystem при сборке бутылки).
local function heldVessel()
	local char = player.Character
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	if not tool or tool:GetAttribute("CupState") == nil then return nil end
	local base = tool:GetAttribute("CupBase")
	return (typeof(base) == "string" and base ~= "") and base or "Cup"
end

--[[ ⚠️ КРУЖКУ ПОДНОСИМ КО РТУ НАПРЯМУЮ, А НЕ ТОЛЬКО УГЛАМИ РУКИ.
     Новая кружка (тул Cup: Handle + WaterFresh/WaterSalty) крупнее старой, и
     подобранные под старую углы руки ставили её перед подбородком боком — пили
     «мимо». Теперь на время глотка сварка хвата (RightGrip) ставит кружку так,
     что её край у губ, а сама она наклонена к лицу на SIP_TILT: считаем от головы
     и от габарита самой кружки. Рука при этом поднимается к лицу позой выше.
     После глотка сварка возвращается как было. Только для кружки (CupBase = Cup):
     у бутылки свой подобранный хват. ]]
local SIP_TILT = math.rad(65)
local gripState = nil   -- { weld, c0 } — исходный C0 хвата, пока подносим
local function sipCup()
	local char = player.Character
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	if not (tool and heldVessel() == "Cup") then return end
	local handle = tool:FindFirstChild("Handle")
	local head = char:FindFirstChild("Head")
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	local weld = hand and hand:FindFirstChild("RightGrip")
	if not (handle and head and weld and weld:IsA("JointInstance")) then return end
	if not gripState or gripState.weld ~= weld then gripState = { weld = weld, c0 = weld.C0 } end
	local size = handle.Size
	local h = size.Y
	-- край кружки — у рта: чуть ниже центра головы и перед лицом
	local rim = Vector3.new(0, -head.Size.Y * 0.18, -(head.Size.Z * 0.5 + 0.05))
	local want = head.CFrame * CFrame.new(rim) * CFrame.Angles(SIP_TILT, 0, 0) * CFrame.new(0, -h / 2, 0)
	-- Part0 (кисть) * C0 = Part1 (кружка) * C1  →  C0 = кисть⁻¹ · кружка · C1
	local target = hand.CFrame:Inverse() * want * weld.C1
	weld.C0 = gripState.c0:Lerp(target, k)
end
local function releaseCup()
	if gripState and gripState.weld.Parent then gripState.weld.C0 = gripState.c0 end
	gripState = nil
end

local function applyPose()
	if k <= 0.001 then return false end
	local set = POSE[rig]
	local tune = VESSEL_TUNE[heldVessel() or ""]
	local liftName  = LIFT_JOINT[rig]
	local wristName = WRIST_JOINT[rig]
	for name, joint in pairs(joints) do
		local a = set[name]
		if joint.Parent and a then
			local x, y, z = a[1], a[2], a[3]
			if tune then
				-- у R6 оба сустава — один и тот же, поэтому поправки складываются
				if name == liftName then
					local d = tune.lift
					x, y, z = x + d[1], y + d[2], z + d[3]
				end
				if name == wristName then
					local d = tune.wrist
					x, y, z = x + d[1], y + d[2], z + d[3]
				end
			end
			local target = CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
			joint.Transform = CFrame.identity:Lerp(target, k)
		end
	end
	sipCup()
	return true
end

local function relaxPose()
	for _, joint in pairs(joints) do
		if joint.Parent then joint.Transform = CFrame.identity end
	end
	releaseCup()
end

RunService:BindToRenderStep("DrinkPose", Enum.RenderPriority.Character.Value + 1, function(dt)
	local char = player.Character
	if not char then return end
	-- пересборку ведёт bindWhenReady; здесь только страховка на смену тела
	if scanned ~= char then bindWhenReady(char) end

	local want = (char:GetAttribute("Drinking") == true) and 1 or 0
	local speed = (want == 1) and BLEND_IN or BLEND_OUT
	local prev = k
	k = k + (want - k) * math.clamp(dt * speed, 0, 1)

	if not applyPose() and prev > 0.001 then
		-- доехали до нуля — снимаем поза-цель, иначе рука так и останется поднятой
		relaxPose()
	end
end)

-- Физический риг читает цель на шаге физики: без повтора решатель возьмёт то,
-- что оставил аниматор, и поза не появится.
RunService.Stepped:Connect(function()
	if physicalRig and k > 0.001 then applyPose() end
end)

-- ⚠️ ЖДЁМ РИГ, А НЕ ЛОВИМ ОДНИМ ЗАМЕРОМ.
-- Сочленения появляются не одновременно с персонажем: единственная попытка на
-- CharacterAdded регулярно приходила на полусобранное тело и находила пустоту.
local function bindWhenReady(char)
	if not char then return end
	task.spawn(function()
		for _ = 1, 40 do          -- до ~8 секунд
			if char.Parent == nil then return end
			collectJoints(char)
			if next(joints) then return end
			task.wait(0.2)
		end
	end)
end

player.CharacterAdded:Connect(function(char)
	joints, scanned, k = {}, nil, 0
	bindWhenReady(char)
end)
bindWhenReady(player.Character)

print("[Питьё] поза готова: рука к лицу, голова вниз (атрибут Drinking)")
