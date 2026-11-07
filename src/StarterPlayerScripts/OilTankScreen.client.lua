local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ЭКРАН ТОПЛИВНОГО БАКА.

	На детали Oil_screen лежит готовый SurfaceGui с каплей и цифрой. Здесь только
	цифра: сколько ЛИТРОВ сейчас в баке (атрибут OilStored на модели бака).

	Текст ПОДГОНЯЕТСЯ ПОД ЭКРАН сам: TextScaled растягивает надпись по рамке, и
	«50» занимает столько же места, сколько «12.4», — вручную подбирать размер под
	каждое значение не нужно.

	Считает клиент: цифра — производная от атрибута, который и так реплицируется.
	Гонять по сети ещё и текст десять раз в секунду во время залива незачем.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OilCanister = require(ReplicatedStorage:WaitForChild("OilCanister"))

local function findLabel(tank)
	local screen = OilCanister.findTankPart(tank, OilCanister.TANK_SCREEN)
	if not screen then return nil end
	local gui = screen:FindFirstChildWhichIsA("SurfaceGui")
	return gui and gui:FindFirstChildWhichIsA("TextLabel", true) or nil
end

task.spawn(function()
	local tank, label
	for _ = 1, 60 do
		tank = OilCanister.findTank(workspace)
		label = tank and findLabel(tank)
		if label then break end
		task.wait(1)
	end
	if not label then
		warn("[Бак] не нашёл TextLabel в SurfaceGui на " .. OilCanister.TANK_SCREEN[1])
		return
	end

	-- Надпись сама ужимается под рамку, длина значения роли не играет.
	label.TextScaled = true
	label.RichText = false

	local function redraw()
		label.Text = OilCanister.formatLitres(OilCanister.tankStored(tank))
	end

	tank:GetAttributeChangedSignal(OilCanister.TANK_ATTR):Connect(redraw)
	redraw()
end)
