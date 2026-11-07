local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ЛОДОЧНИК С НАГРАДОЙ РЕЙДА — клиент: отрисовка и UI.

	⚠️ ДЕТАЛИ ЛОДОЧНИКА СТАВИТ КЛИЕНТ. Сервер (RaidCourier) публикует логику
	атрибутами в кадре плота, а мы каждый кадр переводим её в мир через ПЛОТ,
	КОТОРЫЙ ВИДИМ МЫ, — поэтому лодка у борта и лодочник на палубе едут вместе с
	плотом без рывков. Позы, гребля, подъём ящика и мимика — авторский
	CourierPerformance (копия в ReplicatedStorage/RaidCourier).

	UI «Награда с рейдов» — в RewardAdsController (табличка по макету пакета
	raft-reward-ads).
]]
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer
local pack = ReplicatedStorage:WaitForChild("RaidCourier")
local Config = require(pack:WaitForChild("Config"))
local Performance = require(pack:WaitForChild("CourierPerformance"))
local folder = workspace:WaitForChild("RaidCouriers")

local function now() return workspace:GetServerTimeNow() end

local function raftFrame()
	local raft = workspace:FindFirstChild("Raft")
	local pp = raft and raft.PrimaryPart
	if not pp then return nil end
	local yaw = pp:GetAttribute("RestYaw")
	if type(yaw) ~= "number" then
		local _, y = pp.CFrame:ToEulerAnglesYXZ()
		yaw = y
	end
	return CFrame.new(pp.Position) * CFrame.Angles(0, yaw, 0)
end

-- ═══════════ отрисовка ═══════════
local couriers = {}   -- [model] = state

local function attach(m)
	if couriers[m] or not m:IsA("Model") then return end
	local rig
	local t0 = os.clock()
	repeat
		for _, n in ipairs(Config.RIG_NAMES) do rig = rig or m:FindFirstChild(n) end
		if not rig then task.wait(0.1) end
	until rig or os.clock() - t0 > 10
	local boat = m:WaitForChild(Config.BOAT_NAME, 10)
	if not (rig and boat) then return end
	-- модуль автора ждёт сцену с NormalDummy и Rowboat — это и есть наша модель
	local ok, perf = pcall(Performance.new, m)
	if not ok then warn("[Лодочник/клиент] не собрал анимацию: " .. tostring(perf)) return end
	couriers[m] = { perf = perf, rig = rig, boatRel = nil, rootRel = nil, oarRel = {}, fade = 0 }
end

local function detach(m) couriers[m] = nil end
for _, m in ipairs(folder:GetChildren()) do task.spawn(attach, m) end
folder.ChildAdded:Connect(function(m) task.spawn(attach, m) end)
folder.ChildRemoved:Connect(detach)

local function lerpCF(a, b, k) if not a then return b end return a:Lerp(b, k) end

local function placeBoat(st, m, boatCF)
	local boat = m[Config.BOAT_NAME]
	boat:PivotTo(boatCF)
	-- вёсла — отдельные модели: вне гребли держим их там, где их оставила гребля
	for _, name in ipairs({ "LeftOar", "RightOar" }) do
		local oar = boat:FindFirstChild(name)
		if oar and st.oarRel[name] then oar:PivotTo(boatCF * st.oarRel[name]) end
	end
end

RunService.PreRender:Connect(function(dt)
	local F = raftFrame()
	if not F then return end
	local t = now()
	for m, st in pairs(couriers) do
		if not m.Parent then couriers[m] = nil continue end
		local mode = m:GetAttribute("State") or "Rowing"
		local boatRelAttr = m:GetAttribute("BoatRel")
		if typeof(boatRelAttr) ~= "CFrame" then continue end
		-- сервер шлёт позу 20 раз в секунду: догоняем её мягко, а не шагами
		st.boatRel = lerpCF(st.boatRel, boatRelAttr, math.min(1, dt * 10))
		local boatCF = F * st.boatRel
		local perf = st.perf
		local root = perf.root
        perf.emptyHanded = m:GetAttribute("CargoGranted") == true
        -- Apply the cargo state locally in the same frame as the procedural pose.
        local carrying = mode == "Walking" or mode == "Delivered" or mode == "Returning"
            or mode == "Disembarking" or mode == "Boarding"
        perf.joint.Enabled = carrying and not perf.emptyHanded
        perf.box.BoxRoot.Anchored = not perf.joint.Enabled
        if perf.emptyHanded and not st.cargoHidden then
            st.cargoHidden = true
            for _, d in ipairs(perf.box:GetDescendants()) do
                if d:IsA("BasePart") then d.LocalTransparencyModifier = 1
                elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then d.Enabled = false end
            end
        end
        if mode ~= st.mode then
            if mode == "Returning" then st.rootRel = m:GetAttribute("RootRel") end
            if mode == "Sitting" then
                -- ⚠️ ИСХОДНЫЕ ПОЗЫ ПОСАДКИ — ОДИН РАЗ НА ВХОДЕ, В ОСЯХ ЛОДКИ (v4):
                -- мировая поза из демо на плывущем плоте устаревала бы каждый кадр
                perf.sitFromRel = boatCF:ToObjectSpace(root.CFrame)
                perf.sitBody = perf.rj.C0
                perf.sitRight, perf.sitLeft = perf.right.C0, perf.left.C0
                perf.sitRH, perf.sitLH = perf.rh.C0, perf.lh.C0
                perf.sitNeck = perf.neck.C0
                perf.sitOars = {}
                local boat = m[Config.BOAT_NAME]
                for _, name in ipairs({ "LeftOar", "RightOar" }) do
                    local oar = boat:FindFirstChild(name)
                    perf.sitOars[name] = oar and boatCF:ToObjectSpace(oar:GetPivot())
                        or (st.oarRel[name] or CFrame.identity)
                end
            end
            st.mode = mode
        end

		if mode == "Sitting" then
			m[Config.BOAT_NAME]:PivotTo(boatCF)   -- вёсла ведёт сама поза посадки
			local p = math.clamp((t - (m:GetAttribute("SitT0") or t)) / Config.SIT_TIME, 0, 1)
			perf:Step("Sitting", dt, boatCF, p)
		elseif mode == "OarsReady" then
			perf:Step("OarsReady", dt, boatCF, 0)
		elseif mode == "Rowing" or mode == "Docking" or mode == "Waiting" or mode == "Departing" or mode == "Leaving" then
			perf:Step((mode == "Departing" or mode == "Leaving") and "Rowing" or mode, dt, boatCF, 0)
			local boat = m[Config.BOAT_NAME]
			for _, name in ipairs({ "LeftOar", "RightOar" }) do
				local oar = boat:FindFirstChild(name)
				if oar then st.oarRel[name] = boatCF:ToObjectSpace(oar:GetPivot()) end
			end
		elseif mode == "Pickup" or mode == "Putdown" then
			placeBoat(st, m, boatCF)
			if mode == "Putdown" then
				-- укладка: участок подъёма p = 1 → PUTDOWN_TO (только опустить и отпустить)
				local f = math.clamp((t - (m:GetAttribute("PickupT0") or t)) / Config.PUTDOWN_TIME, 0, 1)
				perf:Step("Pickup", dt, boatCF, 1 - (1 - Config.PUTDOWN_TO) * f)
			else
				local p = math.clamp((t - (m:GetAttribute("PickupT0") or t)) / Config.PICKUP_TIME, 0, 1)
				perf:Step("Pickup", dt, boatCF, p)
			end
		elseif mode == "Disembarking" or mode == "Boarding" then
			placeBoat(st, m, boatCF)
			local a, b = m:GetAttribute("DisFrom"), m:GetAttribute("DisTo")
			if typeof(a) == "CFrame" and typeof(b) == "CFrame" then
				local f = math.clamp((t - (m:GetAttribute("DisT0") or t)) / Config.DISEMBARK_TIME, 0, 1)
				local arc = mode == "Boarding" and Config.BOARD_ARC or 0.45
				root.CFrame = F * a:Lerp(b, f) + Vector3.new(0, math.sin(f * math.pi) * arc, 0)
			end
			perf:Step("Disembarking", dt, boatCF, 1)
		else -- Walking / Delivered / Returning
			placeBoat(st, m, boatCF)
			local rel = m:GetAttribute("RootRel")
			if typeof(rel) == "CFrame" then
				local prev = st.rootRel
				st.rootRel = lerpCF(st.rootRel, rel, math.min(1, dt * 12))
				root.CFrame = F * st.rootRel
				local speed = prev and ((st.rootRel.Position - prev.Position).Magnitude / math.max(dt, 1e-3)) or 0
				perf.walkSpeed = (m:GetAttribute("WalkSpeed") or 0) > 0 and math.min(speed, Config.WALK_SPEED * 1.3) or 0
			end
			perf:Step(mode == "Returning" and "Walking" or mode, dt, boatCF, 1)
		end

		-- уплывает: тает
		if mode == "Leaving" then
			st.fade = math.min(1, st.fade + dt / 1.1)
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then d.LocalTransparencyModifier = (st.cargoHidden and d:IsDescendantOf(perf.box)) and 1 or st.fade
				elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then d.Enabled = st.fade < 0.5 end
			end
		end
	end
end)

-- UI «Награда с рейдов» — RewardAdsController (табличка по макету RewardAds)

print("[Лодочник/клиент] готов: рисую лодочников по плоту, UI награды — своему получателю")
