local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[ ЗОНД РЫВКОВ ПЛОТА (клиент). Игрок видит рывок на СВОЁМ экране; если сервер
     рывка не видел, значит дело в репликации и интерполяции, а не в физике.
     Та же проверка, что на сервере: положение против ожидаемого по скорости. ]]
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local JUMP = 2.5
local lastLog, prevPos, prevVel = 0, nil, nil

-- ⚠️ СВОДКА ПЕРВЫХ СЕКУНД ХОДА. Мелкая дрожь (0.3–1 студ на кадр) под порог
-- JUMP не попадает, а именно её видно «первые 5 секунд». Считаем с момента,
-- когда плот тронулся: кадров с микрорывком, худший из них, и по секундам.
local MICRO = 0.35
local SUMMARY_SEC = 12
local runT0, microN, microMax, perSec = nil, 0, 0, {}
-- отдельно вертикальная дрожь: положение по Y против ожидаемого по скорости
local yJitN, yJitMax, yFlips, lastDy = 0, 0, 0, 0
-- по секундам: средняя РЕПЛИЦИРОВАННАЯ скорость против ФАКТИЧЕСКОГО пути.
-- Если скорость ≈ 0, а путь ≈ 8 — клиент между пакетами не дотягивает
-- (скорость не доезжает), и каждый пакет — рывок на 0.4 стада.
local secV, secD, secN, secStill = {}, {}, {}, {}
local perSecDone = false

RunService.RenderStepped:Connect(function(dt)
	local raft = Workspace:FindFirstChild("Raft")
	local pp = raft and raft.PrimaryPart
	if not pp then prevPos = nil return end
	local pos, vel = pp.Position, pp.AssemblyLinearVelocity
	if prevPos and dt > 0 and dt < 0.5 then
		local jump = (pos - (prevPos + prevVel * dt)).Magnitude
		local dy = pos.Y - prevPos.Y
		local yErr = math.abs(dy - prevVel.Y * dt)
		if yErr > 0.004 then yJitN += 1; yJitMax = math.max(yJitMax, yErr) end
		if (dy > 0.001 and lastDy < -0.001) or (dy < -0.001 and lastDy > 0.001) then yFlips += 1 end
		lastDy = dy
		if not runT0 and vel.Magnitude > 0.5 then runT0 = os.clock() end
		if runT0 then
			local t = os.clock() - runT0
			if t <= SUMMARY_SEC then
				local sec = math.floor(t) + 1
				secV[sec] = (secV[sec] or 0) + vel.Magnitude
				secD[sec] = (secD[sec] or 0) + (pos - prevPos).Magnitude
				secN[sec] = (secN[sec] or 0) + 1
				if (pos - prevPos).Magnitude < 0.001 then secStill[sec] = (secStill[sec] or 0) + 1 end
				if jump > MICRO then
					microN += 1
					microMax = math.max(microMax, jump)
					local sec = math.floor(t) + 1
					perSec[sec] = (perSec[sec] or 0) + 1
				end
			elseif not perSecDone then
				perSecDone = true
				local cols = {}
				for i = 1, SUMMARY_SEC do cols[i] = tostring(perSec[i] or 0) end
				local vd = {}
				for i = 1, SUMMARY_SEC do
					local n = secN[i] or 1
					vd[i] = ("%d:v%.1f/d%.1f/стоп%d"):format(i, (secV[i] or 0) / n, secD[i] or 0, secStill[i] or 0)
				end
				print("[RaftJump/клиент] скорость по пакетам против пути (v — реплицированная, d — фактическая студ/с, стоп — кадров без движения): " .. table.concat(vd, " "))
				local ok, owner = pcall(function() return pp:GetNetworkOwner() end)
				print(("[RaftJump/клиент] первые %d с хода: микрорывков (>%.2f студа/кадр) %d, худший %.2f | по секундам: %s | хозяин на клиенте: %s | по Y: кадров с дрожью %d, худшая %.3f, смен направления %d")
					:format(SUMMARY_SEC, MICRO, microN, microMax, table.concat(cols, " "), ok and tostring(owner) or "?", yJitN, yJitMax, yFlips))
			end
		end
		if jump > JUMP and os.clock() - lastLog > 1 then
			lastLog = os.clock()
			local back = (pos - prevPos):Dot(prevVel.Magnitude > 0.01 and prevVel.Unit or Vector3.zero) < 0
			warn(("[RaftJump/клиент] рывок %.1f студов %s | скорость %.1f | dt %.3f"):format(
				jump, back and "НАЗАД" or "вперёд/вбок", vel.Magnitude, dt))
		end
	end
	prevPos, prevVel = pos, vel
end)
