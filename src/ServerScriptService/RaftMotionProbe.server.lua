--[[ ЗОНД РЫВКОВ ПЛОТА (сервер). Плот «телепортирует назад» — а кто виноват,
     по логу не видно. Каждый кадр сравниваем, где плот оказался, с тем, где
     он должен быть по своей скорости; расхождение больше JUMP студов — рывок.
     Пишем всё, что может его объяснить: хозяин сети, корень сборки, якоря,
     масса, сколько секунд после старта и после автосейва, был ли зонд крена.
     Не чаще раза в секунду, чтобы не заваливать консоль. ]]
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local JUMP = 2.5
local startT, lastLog, prevPos, prevVel = os.clock(), 0, nil, nil

RunService.Heartbeat:Connect(function(dt)
	local raft = Workspace:FindFirstChild("Raft")
	local pp = raft and raft.PrimaryPart
	if not pp then prevPos = nil return end
	local pos, vel = pp.Position, pp.AssemblyLinearVelocity
	if prevPos and dt > 0 and dt < 0.5 then
		local expected = prevPos + prevVel * dt
		local jump = (pos - expected).Magnitude
		if jump > JUMP and os.clock() - lastLog > 1 then
			lastLog = os.clock()
			local root = pp.AssemblyRootPart or pp
			local ok, owner = pcall(function() return root:GetNetworkOwner() end)
			local anchored, n = 0, 0
			for _, d in ipairs(raft:GetDescendants()) do
				if d:IsA("BasePart") then n += 1 if d.Anchored then anchored += 1 end end
			end
			local lastSave = Workspace:GetAttribute("LastAutosaveAt")
			warn(("[RaftJump/сервер] рывок %.1f студов (по скорости ждали %.1f, получили %.1f) | хозяин %s | корень %s | деталей %d, заякорено %d | масса %.0f | %.0f с после старта | автосейв %s с назад | dt %.3f")
				:format(jump, (prevVel * dt).Magnitude, (pos - prevPos).Magnitude, ok and tostring(owner) or "?", root.Name, n, anchored,
					root.AssemblyMass, os.clock() - startT, lastSave and ("%.0f"):format(os.clock() - lastSave) or "не было", dt))
		end
	end
	prevPos, prevVel = pos, vel
end)
print("[RaftJump/сервер] зонд рывков плота включён (порог " .. JUMP .. " студов)")
