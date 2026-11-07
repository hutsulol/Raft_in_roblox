--[[
	СВЕЧЕНИЕ СУНДУКА ПЕСЧАНОЙ ОТМЕЛИ — то же, что у сундуков острова фермеров
	(ReplicatedStorage/FarmersIsland/ChestGlow): голубые лучи, искры и свет из
	открытой крышки. Открывает сундук сервер (CrabIsland.server): крышка на
	шарнире LidHinge и атрибуты GlowStarted / TargetOpen / GlowOpenedAt — этот
	скрипт лишь цепляет эффект к каждому сундуку отмели.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChestGlow = require(ReplicatedStorage:WaitForChild("FarmersIsland"):WaitForChild("ChestGlow"))

-- отмель и кратер: у обоих сундуки ставит CrabIsland.server в ActiveChests
local ISLAND_NAMES = { Sandy_Shoal_Island = true, Crater_Island = true, Crater = true, Forgotten_Crater_Island = true }
local started = setmetatable({}, { __mode = "k" })

local function attach(chest)
	if started[chest] or not chest:IsA("Model") then return end
	started[chest] = true
	task.spawn(function() pcall(ChestGlow.attach, chest) end)
end

local function hook(island)
	if not (island:IsA("Model") and ISLAND_NAMES[island.Name]) then return end
	task.spawn(function()
		local live = island:WaitForChild("ActiveChests", 30)
		if not live then return end
		live.ChildAdded:Connect(attach)
		for _, c in ipairs(live:GetChildren()) do attach(c) end
	end)
end

workspace.ChildAdded:Connect(hook)
for _, c in ipairs(workspace:GetChildren()) do hook(c) end
