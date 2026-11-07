--[[
	ЯХТА ТОРГОВЦА — анимация торговца на клиенте (пак Merchant_Yacht_Transfer,
	Client.luau без демо-меню). Тело — Motor6D.Transform, лицо — элементы
	SurfaceGui MerchantFace; ассетов анимаций нет, всё процедурно.

	Жест задаёт сервер (MerchantYacht.server): атрибуты MerchantAction и
	ActionTime на модели. Время — workspace:GetServerTimeNow(), поэтому у всех
	игроков торговец двигается одинаково. Моргание идёт всегда, по своему
	расписанию, и сменой жеста не сбрасывается.

	Яхта приходит и уходит — модель каждый рейс новая. Ловим её появление в
	Workspace и отвязываемся при удалении (и при выгрузке стримингом): вечных
	соединений на удалённые суставы и GUI нет. Окно магазина — MerchantShopUI.
]]

local RunService = game:GetService("RunService")

local NAME = "MerchantYacht"
local JOINTS = { "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip", "Neck" }

--[[ E У ПРИЛАВКА → ОКНО МАГАЗИНА ТОРГОВЦА (MerchantShopUI — то самое, что раньше
     открывалось только кнопкой в настройках). Открываем сразу на клиенте, без
     круга через сервер; сервер на тот же Triggered только машет рукой (Greet), а
     каждую покупку проверяет сам: стоянка, прилавок, цена, остаток. ]]
local promptBound = setmetatable({}, { __mode = "k" })
local function bindPrompt(scene)
	local yacht = scene:WaitForChild("Yacht", 10)
	local sign = yacht and yacht:WaitForChild("ShopSign", 10)
	local point = sign and sign:WaitForChild("ShopPromptPoint", 10)
	local prompt = point and point:WaitForChild("ProximityPrompt", 10)
	if not prompt or promptBound[prompt] then return end   -- после стриминга не вешаем второй раз
	promptBound[prompt] = true
	local talking = false
	prompt.Triggered:Connect(function()
		if scene:GetAttribute("VoyageState") ~= "Moored" or talking then return end
		--[[ СНАЧАЛА РАЗГОВОР, ПОТОМ ЛАВКА. Сюжет (MerchantStory.server) пишет в
		     Workspace.MerchantTalk ключ речи этого визита (DialogueDefs) и номер
		     визита. Речь звучит один раз за визит; дочитал — открывается лавка. ]]
		local key = workspace:GetAttribute("MerchantTalk")
		local visitId = tostring(workspace:GetAttribute("MerchantTalkVisit") or "")
		if type(key) == "string" and key ~= "" and scene:GetAttribute("TalkSeen") ~= key .. visitId
			and typeof(_G.StartLocalDialogue) == "function" then
			scene:SetAttribute("TalkSeen", key .. visitId)   -- только у этого клиента
			talking = true
			_G.StartLocalDialogue(key)
			task.wait(0.2)
			local deadline = os.clock() + 90
			while typeof(_G.DialogueCurrentKey) == "function" and _G.DialogueCurrentKey() == key and os.clock() < deadline do
				task.wait(0.1)
			end
			talking = false
			if scene:GetAttribute("VoyageState") ~= "Moored" then return end
		end
		if typeof(_G.OpenMerchantShop) == "function" then
			_G.OpenMerchantShop()
		else
			warn("[Яхта торговца] окно магазина (MerchantShopUI) не загружено")
		end
	end)
end

--[[ ⚠️ ХОД ЯХТЫ НА ПОДХОДЕ И УХОДЕ — ЗДЕСЬ, У КЛИЕНТА.
     Когда сервер двигал её каждый кадр, позиции доезжали по сети рывками и не
     в такт плоту — яхту трясло. Сервер пишет маршрут в атрибуты (MerchantYacht.
     server), а мы ведём её сами относительно плота, каким его видим мы. На
     стоянке яхта приварена к плоту и едет с ним сама — тут не трогаем. ]]
local function smooth(u) return u * u * (3 - 2 * u) end

local function raftFlat(raft)
	local p = raft.PrimaryPart
	return CFrame.new(p.Position) * CFrame.Angles(0, p:GetAttribute("RestYaw") or 0, 0)
end

local function waterY(x, z, fallback, ignore)
	local params = RaycastParams.new()
	params.IgnoreWater = false
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local res = workspace:Raycast(Vector3.new(x, fallback + 120, z), Vector3.new(0, -600, 0), params)
	if res and res.Material == Enum.Material.Water then return res.Position.Y end
	return fallback
end

local function hullCF(scene)
	local state = scene:GetAttribute("VoyageState")
	local raft = workspace:FindFirstChild("Raft")
	if raft and not raft.PrimaryPart then raft = nil end
	local now = workspace:GetServerTimeNow()
	if state == "Approaching" then
		local startRel, dockRel = scene:GetAttribute("StartRel"), scene:GetAttribute("DockRel")
		local t0, dur = scene:GetAttribute("VoyageT0"), scene:GetAttribute("ApproachTime")
		if not (raft and startRel and dockRel and t0 and dur) then return nil end
		local u = smooth(math.clamp((now - t0) / dur, 0, 1))
		local flat = raftFlat(raft)
		local target = flat * dockRel
		local cf = (flat * startRel):Lerp(target, u)
		-- высота: на старте — вода под яхтой, к причалу — высота от плота
		local wy = waterY(cf.Position.X, cf.Position.Z, target.Position.Y, { raft, scene })
		return CFrame.new(cf.Position.X, wy + (target.Position.Y - wy) * u, cf.Position.Z) * cf.Rotation
	elseif state == "Moored" then
		-- у борта: та же точка причала, что в конце подхода, каждый кадр — гладко
		-- вместе с плотом (к плоту яхта не приварена). На мели — стоит, где встала.
		if scene:GetAttribute("Stranded") then return nil end
		local dockRel = scene:GetAttribute("DockRel")
		if not (raft and dockRel) then return nil end
		return raftFlat(raft) * dockRel
	elseif state == "Leaving" then
		local t0, dur, dist = scene:GetAttribute("LeaveT0"), scene:GetAttribute("LeaveTime"), scene:GetAttribute("ApproachDist")
		if not (t0 and dur and dist) then return nil end
		local u = math.clamp((now - t0) / dur, 0, 1)
		local from, dir
		local leaveRel, outRel = scene:GetAttribute("LeaveRel"), scene:GetAttribute("OutRel")
		if raft and leaveRel and outRel then
			local flat = raftFlat(raft)
			from, dir = flat * leaveRel, flat:VectorToWorldSpace(outRel)
		else
			from, dir = scene:GetAttribute("LeaveFrom"), scene:GetAttribute("LeaveDir")
			if not (from and dir) then return nil end
		end
		return from + dir * (dist * u * u)   -- отходит с разгоном
	end
	return nil
end

local moveBound = setmetatable({}, { __mode = "k" })
local function bindMove(scene)
	if moveBound[scene] then return end   -- после стриминга не вешаем второй раз
	moveBound[scene] = true
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not scene.Parent then conn:Disconnect() return end
		local pivotOff = scene:GetAttribute("PivotOff")
		if not pivotOff then return end
		local cf = hullCF(scene)
		if cf then scene:PivotTo(cf * pivotOff) end
	end)
end

local function bind(scene)
	task.spawn(bindPrompt, scene)
	bindMove(scene)
	local npc = scene:WaitForChild("Merchant", 10)
	local torso = npc and npc:WaitForChild("Torso", 10)
	local canvas = npc and npc:WaitForChild("FaceCanvas", 10)
	local face = canvas and canvas:WaitForChild("MerchantFace", 10)
	if not (torso and face) then return end

	local joints = {}
	for _, name in ipairs(JOINTS) do
		local j = torso:WaitForChild(name, 10)
		if not j then return end
		j.C0 = j:GetAttribute("RestC0") or j.C0
		joints[name] = j
	end
	local function jointPose(name, x, y, z, alpha)
		local j = joints[name]
		local rot = j.C0.Rotation
		local target = rot:Inverse() * CFrame.Angles(math.rad(x), math.rad(y or 0), math.rad(z or 0)) * rot
		j.Transform = j.Transform:Lerp(target, alpha)
	end

	-- у лица по две пары Eye и Glint с одинаковыми именами — различаем по X
	local eyes, glints = {}, {}
	for _, v in ipairs(face:GetChildren()) do
		if v.Name == "Eye" then table.insert(eyes, v) elseif v.Name == "Glint" then table.insert(glints, v) end
	end
	table.sort(eyes, function(a, b) return a.Position.X.Offset < b.Position.X.Offset end)
	table.sort(glints, function(a, b) return a.Position.X.Offset < b.Position.X.Offset end)
	local mouth, teeth = face:FindFirstChild("Smile"), face:FindFirstChild("Teeth")
	local browL, browR = face:FindFirstChild("LeftBrow"), face:FindFirstChild("RightBrow")
	local mustL, mustR = face:FindFirstChild("MustacheL"), face:FindFirstChild("MustacheR")
	if not (mouth and teeth and browL and browR and mustL and mustR) then return end

	local facial = { eye = 52, width = 132, height = 27, brow = -10, lift = 0 }
	local function animateFace(dt, state, t)
		-- неровное 12-секундное расписание моргания, иногда двойное
		local phase = workspace:GetServerTimeNow() % 12
		local blink = 0
		for _, start in ipairs({ 1.8, 5.9, 9.6, 9.98 }) do
			local b = (phase - start) / 0.19
			if b >= 0 and b <= 1 then blink = math.max(blink, math.sin(b * math.pi)) end
		end
		local eye, width, height, brow, lift = 52, 132, 26, -10, 0
		local speaking = false
		if state == "Greet" then eye = 57; width = 148; height = 38; brow = -15; lift = -7; speaking = t < 1.8
		elseif state == "Talk" then eye = 50; width = 124; height = 29; brow = -7; lift = -3; speaking = true
		elseif state == "ShowGoods" then eye = 58; width = 140; height = 32; brow = -17; lift = -8; speaking = t < 2.5
		elseif state == "CountCoins" then eye = 40; width = 98; height = 13; brow = 10; lift = 8
		elseif state == "GiveItem" then eye = 47; width = 143; height = 30; brow = -12; speaking = t < 1.6
		elseif state == "Thanks" then eye = 30; width = 158; height = 40; brow = -16; lift = -5; speaking = t < 1.5
		elseif state == "Rest" then eye = 44; width = 110; height = 15; brow = -2; lift = 5 end   -- не щёлочки: 22 px читались как «глаз нет»
		if speaking then
			-- слоги с паузами: только картинка, без звука
			local phrase = t % 1.65
			local syllable = math.max(0, math.sin(t * 17) + 0.32 * math.sin(t * 29))
			local opening = phrase < 1.25 and syllable or 0
			height = 15 + opening * 46
			width = width - opening * 19
			lift = lift + 2 * math.sin(t * 9)
		end
		local a = 1 - math.exp(-dt * 18)
		local goal = { eye = eye, width = width, height = height, brow = brow, lift = lift }
		for key, value in pairs(goal) do facial[key] = facial[key] + (value - facial[key]) * a end
		for i, e in ipairs(eyes) do
			local h = math.max(4, facial.eye * (1 - blink))
			local x = i == 1 and 157 or 319
			e.Size = UDim2.fromOffset(31, h)
			e.Position = UDim2.fromOffset(x, 209 - h / 2)
			local g = glints[i]
			if g then
				g.Visible = h > 24
				g.Position = UDim2.fromOffset(x + 7, 209 - h / 2 + 5)
			end
		end
		browL.Rotation = facial.brow
		browR.Rotation = -facial.brow * 0.8
		browL.Position = UDim2.fromOffset(126, 145 + facial.lift)
		browR.Position = UDim2.fromOffset(294, 141 + facial.lift)
		mouth.Size = UDim2.fromOffset(facial.width, facial.height)
		mouth.Position = UDim2.fromOffset(258 - facial.width / 2, 318)
		mouth.Rotation = -3
		teeth.Size = UDim2.fromOffset(facial.width * 0.78, math.min(12, facial.height * 0.32))
		teeth.Position = UDim2.fromOffset(258 - facial.width * 0.39, 319)
		teeth.Visible = facial.height > 21
		mustL.Rotation = -12 - facial.height * 0.035
		mustR.Rotation = 12 + facial.height * 0.035
	end

	local conn
	conn = RunService.PreSimulation:Connect(function(dt)
		if not (scene.Parent and torso.Parent and face.Parent) then
			conn:Disconnect()
			-- стриминг выгрузил торговца, а яхта осталась: вернётся — привяжемся заново
			if scene.Parent then _G.MerchantYachtRebind(scene) end
			return
		end
		-- далеко — не тратим кадр (поза вернётся плавно, когда подплывём)
		local cam = workspace.CurrentCamera
		if cam and (cam.CFrame.Position - torso.Position).Magnitude > 250 then return end
		local t = workspace:GetServerTimeNow() - (scene:GetAttribute("ActionTime") or 0)
		local state = scene:GetAttribute("MerchantAction") or "SitIdle"
		animateFace(dt, state, t)
		local r, l, h, hy, rz, lz = 20, 20, 2 * math.sin(t * 1.4), 5 * math.sin(t * 0.5), -4, 4
		if state == "Greet" then r = 110; rz = -15 + 12 * math.sin(t * 10); hy = -8
		elseif state == "Talk" then r = 30 + 10 * math.sin(t * 3); l = 25 + 8 * math.sin(t * 3 + 2); h = 4 * math.sin(t * 4)
		elseif state == "ShowGoods" then r = 55; rz = -24; l = 28; hy = -20
		elseif state == "CountCoins" then r = 50 + 6 * math.sin(t * 7); l = 46; h = 18; rz = 8
		elseif state == "GiveItem" then
			local v = math.sin(math.clamp(t / 2.4, 0, 1) * math.pi)
			r = 20 + 55 * v; l = 25; h = 6 * v
		elseif state == "Thanks" then r = 45; l = 25; h = 10 * math.sin(t * 6)
		elseif state == "Rest" then r = 12; l = 12; h = -8; hy = 12 * math.sin(t * 0.6) end
		local a = 1 - math.exp(-dt * 14)
		jointPose("Right Hip", 90, 0, -3, a)
		jointPose("Left Hip", 90, 0, 3, a)
		jointPose("Right Shoulder", r, 0, rz, a)
		jointPose("Left Shoulder", l, 0, lz, a)
		jointPose("Neck", h, hy, 0, a)
	end)
	scene.AncestryChanged:Connect(function()
		if not scene:IsDescendantOf(workspace) and conn then conn:Disconnect() end
	end)
end

local bound = setmetatable({}, { __mode = "k" })
local function try(child)
	if child.Name ~= NAME or not child:IsA("Model") or bound[child] then return end
	bound[child] = true
	task.spawn(bind, child)
end
_G.MerchantYachtRebind = function(scene)
	bound[scene] = nil
	local c
	c = scene.DescendantAdded:Connect(function(d)
		if d.Name == "Torso" or d.Name == "MerchantFace" then
			c:Disconnect()
			task.wait(0.5)
			try(scene)
		end
	end)
end
workspace.ChildAdded:Connect(try)
for _, c in ipairs(workspace:GetChildren()) do try(c) end
