-- LootBurstFX.lua (ModuleScript, вызывается С СЕРВЕРА)
-- «Салют добычи»: иконки предметов вылетают вверх из точки, крутясь и расходясь
-- веером, затем вырастают, замирают ровно и растворяются.
--
-- Это выжимка эффекта, который играет ящик дайвера (DiverSystem, PRIZE ICONS).
-- Вынесено отдельно, чтобы сеть могла показать то же самое, не трогая рабочий
-- код дайвера. BillboardGui адорнится к парту, поэтому эффект едет вместе с
-- плотом; всё создаётся на сервере и реплицируется само.

local RunService   = game:GetService("RunService")
local Debris       = game:GetService("Debris")

local LootBurstFX = {}

local FAN_BY_N = {
	{ 0 },
	{ -1.5, 1.5 },
	{ -2.4, 0, 2.4 },
	{ -3.4, -1.15, 1.15, 3.4 },
}

-- anchor: BasePart, к которому крепим эффект (едет вместе с ним)
-- icons:  массив либо строк rbxassetid, либо таблиц { image = id, scale = 1.1 }.
--         scale — множитель итогового размера: одна иконка на тип, но если
--         предметов этого типа несколько, она вылетает чуть крупнее.
-- opts:   { heightOffset = число студов над якорем }
function LootBurstFX.play(anchor, icons, opts)
	if not (anchor and anchor:IsA("BasePart")) then return end
	if type(icons) ~= "table" or #icons == 0 then return end
	opts = opts or {}
	local baseY = opts.heightOffset or 0.6

	local n = math.min(#icons, 4)
	local fan = FAN_BY_N[n]
	local BIG   = (n == 1 and 3.0) or (n == 4 and 2.0) or 2.3 -- итоговый размер, студы
	local START = (n == 1) and 1.5 or 1.2                     -- размер на вылете

	for i = 1, n do
		-- иконка может прийти строкой или таблицей { image, scale }
		local entry = icons[i]
		local imageId = (type(entry) == "table") and entry.image or entry
		local iconScale = (type(entry) == "table" and tonumber(entry.scale)) or 1
		local bigSize = BIG * iconScale

		local bb = Instance.new("BillboardGui")
		bb.Name = "LootBurst" .. i
		bb.Adornee = anchor
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.Size = UDim2.new(START, 0, START, 0) -- единицы BillboardGui = студы
		bb.StudsOffset = Vector3.new(0, baseY, 0)
		bb.Parent = anchor

		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = imageId or ""
		img.Parent = bb

		local fanX = fan[i]
		task.spawn(function()
			local D_RISE, D_GROW, D_HOLD, D_FADE = 0.5, 0.35, 0.55, 0.35
			local riseY = 2.8 + (i - 1) * 0.2 -- лёгкий разброс высот, чтобы не «штамп»
			local SPIN = 540                  -- град/с на вылете
			local rot, growStartRot = 0, nil
			local t0 = os.clock()
			while bb.Parent do
				local dt = RunService.Heartbeat:Wait()
				local t = os.clock() - t0
				if t < D_RISE then           -- вылет вверх с вращением, расходясь веером
					local a = 1 - (1 - t / D_RISE) ^ 2
					bb.StudsOffset = Vector3.new(fanX * a, baseY + riseY * a, 0)
					rot += SPIN * dt
					img.Rotation = rot % 360
				elseif t < D_RISE + D_GROW then -- растёт, вращение тормозит до ровного
					local a = (t - D_RISE) / D_GROW
					if not growStartRot then
						growStartRot = img.Rotation % 360
						if growStartRot > 180 then growStartRot -= 360 end -- кратчайший путь к 0
					end
					local e = 1 - (1 - a) ^ 3
					local s = START + (bigSize - START) * e
					bb.Size = UDim2.new(s, 0, s, 0)
					img.Rotation = growStartRot * (1 - e)
				elseif t < D_RISE + D_GROW + D_HOLD then -- висит ровно
					img.Rotation = 0
				elseif t < D_RISE + D_GROW + D_HOLD + D_FADE then -- тает
					local a = (t - D_RISE - D_GROW - D_HOLD) / D_FADE
					img.ImageTransparency = a
					bb.StudsOffset = Vector3.new(fanX, baseY + riseY + a * 0.8, 0)
				else
					break
				end
			end
			if bb.Parent then bb:Destroy() end
		end)

		Debris:AddItem(bb, 3) -- страховка, если цикл прервётся
	end
end

return LootBurstFX
