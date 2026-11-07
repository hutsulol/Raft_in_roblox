--[[
	GateSwing.client.lua — клиентская половина калитки (см. GateController.server).

	Сервер решает, открыта калитка или нет, и пишет на створку атрибуты
	GateOpen / GateT / GateSign. Позу считает клиент: Motor6D.Transform, выставленный
	сервером, клиентам не реплицируется, а свой персонаж сталкивается с тем, что видит
	его клиент. Поэтому без этого скрипта калитка откроется «на сервере», а игрок
	упрётся в закрытую.

	Движение — по времени, не твином: открытие с лёгким перелётом и возвратом (створка
	доходит до упора и чуть отыгрывает назад), закрытие — со стуком о столб в конце.
	Фаза берётся от серверного времени, поэтому у всех игроков калитка движется одинаково,
	а вошедший позже сразу видит её в конечном положении.
]]

local RunService = game:GetService("RunService")

local function isLeaf(name)
	return string.sub(name, -5) == "_leaf" and string.find(name, "_gate", 1, true) ~= nil
end
local DEFAULT_ANGLE, DEFAULT_TIME = 95, 0.6

local tracked = {}

local function track(leaf)
	if tracked[leaf] then return end
	tracked[leaf] = { motor = nil, rescan = 0, from = 0, angle = 0, lastT = nil, lastOpen = nil }
end

local function discover(inst)
	if inst:IsA("BasePart") and isLeaf(inst.Name) then
		track(inst)
	end
end

for _, d in ipairs(workspace:GetDescendants()) do discover(d) end
workspace.DescendantAdded:Connect(discover)

-- 0..1 -> 0..1 с перелётом ~6% и возвратом
local function easeOutBack(x)
	local c1, c3 = 1.2, 2.2
	local y = x - 1
	return 1 + c3 * y * y * y + c1 * y * y
end

-- закрытие: разгон, удар о столб, маленький отскок
local function easeBounce(x)
	if x < 0.8 then
		local y = x / 0.8
		return y * y
	end
	local y = (x - 0.8) / 0.2
	return 1 - 0.05 * math.sin(y * math.pi)
end

RunService.PreSimulation:Connect(function(dt)
	for leaf, g in pairs(tracked) do
		if not leaf:IsDescendantOf(workspace) then
			tracked[leaf] = nil
			continue
		end
		if not (g.motor and g.motor.Parent) then
			g.rescan -= dt
			if g.rescan > 0 then continue end
			g.rescan = 0.5 -- сустав создаёт сервер, он может доехать позже створки
			g.motor = leaf:FindFirstChild("GateHinge")
			if not (g.motor and g.motor:IsA("Motor6D")) then
				g.motor = nil
				continue
			end
		end
		local open = leaf:GetAttribute("GateOpen") == true
		local stamp = leaf:GetAttribute("GateT")
		local sign = tonumber(leaf:GetAttribute("GateSign")) or 1
		local full = math.rad(tonumber(leaf:GetAttribute("GateAngle")) or DEFAULT_ANGLE)
		local dur = math.max(tonumber(leaf:GetAttribute("GateTime")) or DEFAULT_TIME, 0.05)

		if stamp ~= g.lastT or open ~= g.lastOpen then
			g.lastT, g.lastOpen = stamp, open
			g.from = g.angle -- с того места, где створка сейчас (её могли дёрнуть на полпути)
		end
		local t = 1
		if type(stamp) == "number" then
			t = math.clamp((workspace:GetServerTimeNow() - stamp) / dur, 0, 1)
		end
		local goal = open and full or 0
		local k = open and easeOutBack(t) or easeBounce(t)
		g.angle = g.from + (goal - g.from) * k
		g.motor.Transform = CFrame.Angles(0, sign * g.angle, 0)
	end
end)
