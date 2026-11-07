local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ЭКРАН СМЕРТИ — по хендоффу design_handoff_death_screen/HANDOFF.md.

	Сцены приходят с сервера (DeathPenalty.server.lua) одним RemoteEvent DeathScene:
	  penalty — штраф пиратами: сердце вырывается из HUD, крупное «−N» с монетой;
	  death   — списана жизнь команды: ряд из трёх сердец, одно ломается; при
	            последней — предложение экстра-жизни за Robux и кнопки;
	  revive  — «ВЫ ЖИВЫ!», зелёный отблеск, сердце бьётся;
	  lobby   — чёрный экран «Возвращаемся в лобби…».
	Игрок ничего не нажимает, кроме выбора на последней жизни.

	⚠️ ВСЁ РИСУЕТСЯ КОДОМ, БЕЗ КАРТИНОК. Сердце — повёрнутый квадрат и два круга
	(как в хендоффе), осколки и искры — простые Frame. Значит, ассетов грузить
	не надо и сцена работает в любом плейсе.
	⚠️ ЗВУКИ — ВСТРОЕННЫЕ rbxasset://sounds. Каталожные звуки в этом плейсе не
	авторизованы (см. Output: «not authorized to access Asset»), встроенные есть
	всегда.
	Референс 1586×820; масштаб = высота экрана / 820, не меньше 0.45.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote    = ReplicatedStorage:WaitForChild("DeathScene")
local action    = ReplicatedStorage:WaitForChild("DeathSceneAction")

local hex = Color3.fromHex
local C = {
	RED = hex("E5484D"), EMPTY_LINE = hex("3A3F4A"), EMPTY_FILL = hex("0F1D2C"), INK = hex("14261A"),
	DIM = hex("0B1A2A"), GREEN = hex("7AE04D"), GREEN_DARK = hex("48B428"), GREEN_SHADOW = hex("2A6E14"),
	GREY = hex("4A5578"), GREY_DARK = hex("323A54"), GREY_SHADOW = hex("1B2035"),
	GOLD = hex("FFD54A"), WHITE = Color3.new(1, 1, 1), LOBBY = hex("050607"),
}
local FONT = Enum.Font.FredokaOne
local COIN_ICON = "rbxassetid://93617165412571"   -- монета пиратов из HUD

-- ═══════════ звук ═══════════
local SND = {
	crack   = { "rbxasset://sounds/snap.mp3",                0.55, 0.85 },
	rip     = { "rbxasset://sounds/swordlunge.wav",          0.45, 0.7  },
	shatter = { "rbxasset://sounds/glassbreak.wav",          0.5,  0.9  },
	thud    = { "rbxasset://sounds/action_jump_land.mp3",    0.7,  0.6  },
	coins   = { "rbxasset://sounds/electronicpingshort.wav", 0.4,  0.55 },
	warn    = { "rbxasset://sounds/bass.wav",                0.5,  0.8  },
	revive  = { "rbxasset://sounds/victory.wav",             0.5,  1.0  },
	beat    = { "rbxasset://sounds/action_jump_land.mp3",    0.35, 0.45 },
	click   = { "rbxasset://sounds/button.wav",              0.5,  1.0  },
}
local function play(key, delay)
	local d = SND[key]
	if not d then return end
	task.delay(delay or 0, function()
		local s = Instance.new("Sound")
		s.SoundId, s.Volume, s.PlaybackSpeed = d[1], d[2], d[3]
		s.Parent = SoundService
		s:Play()
		s.Ended:Once(function() s:Destroy() end)
		task.delay(6, function() if s.Parent then s:Destroy() end end)
	end)
end

-- ═══════════ помощники ═══════════
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function tw(o, t, props, style, dir, delay)
	local tween = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad,
		dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
	tween:Play()
	return tween
end

local function scaleOf(obj)
	return obj:FindFirstChildOfClass("UIScale") or new("UIScale", { Scale = 1 }, obj)
end

-- прозрачность всего поддерева: фон, текст, картинка
local function fade(obj, t, to, delay, dir)
	local list = { obj }
	for _, d in ipairs(obj:GetDescendants()) do table.insert(list, d) end
	for _, d in ipairs(list) do
		if d:IsA("GuiObject") and d.BackgroundTransparency < 1 or (d:IsA("GuiObject") and to < 1 and d:GetAttribute("Bg")) then
			tw(d, t, { BackgroundTransparency = to }, nil, dir, delay)
		end
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			tw(d, t, { TextTransparency = to }, nil, dir, delay)
		elseif d:IsA("ImageLabel") then
			tw(d, t, { ImageTransparency = to }, nil, dir, delay)
		elseif d:IsA("UIStroke") then
			tw(d, t, { Transparency = to }, nil, dir, delay)
		end
	end
end

-- «падение» из scale 3 с посадкой Back Out (как sickText)
local function drop(obj, delay, t)
	local s = scaleOf(obj)
	s.Scale = 3
	obj.Visible = false
	task.delay(delay, function()
		if not obj.Parent then return end
		obj.Visible = true
		tw(s, t or 0.7, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
end

-- Сердце размером S: квадрат S/2 под 45° + два круга. outline — обводка-тройка ×1.16
local function heartShape(parent, S, color, z)
	local f = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(S, S * 0.85), ZIndex = z }, parent)
	local function piece(props)
		props.BackgroundColor3 = color
		props.BorderSizePixel = 0
		props.ZIndex = z
		return new("Frame", props, f)
	end
	piece({ Size = UDim2.fromOffset(S / 2, S / 2), Position = UDim2.fromOffset(S * 0.25, S * 0.2), Rotation = 45 })
	local a = piece({ Size = UDim2.fromOffset(S / 2, S / 2), Position = UDim2.fromOffset(S * 0.073, S * 0.023) })
	local b = piece({ Size = UDim2.fromOffset(S / 2, S / 2), Position = UDim2.fromOffset(S * 0.427, S * 0.023) })
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, a)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
	return f
end

local function heart(parent, S, kind, z)
	z = z or 10
	local box = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(S, S * 0.85) }, parent)
	local outlineColor = (kind == "empty") and C.EMPTY_LINE or C.INK
	local out = heartShape(box, S, outlineColor, z)
	out.AnchorPoint = Vector2.new(0.5, 0.55)
	out.Position = UDim2.fromScale(0.5, 0.55)
	new("UIScale", { Scale = 1.16 }, out)
	local fillColor = (kind == "empty") and C.EMPTY_FILL or (kind == "green" and C.GREEN or C.RED)
	heartShape(box, S, fillColor, z + 1)
	if kind ~= "empty" then
		local gl = new("Frame", { BackgroundColor3 = C.WHITE, BackgroundTransparency = 0.4, BorderSizePixel = 0,
			Size = UDim2.fromOffset(S * 0.15, S * 0.15), Position = UDim2.fromOffset(S * 0.2, S * 0.14), ZIndex = z + 2 }, box)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, gl)
	end
	return box
end

local CRACKS = { { 0.47, 0.12, 18 }, { 0.5, 0.32, -24 }, { 0.46, 0.48, 14 } }
local function crack(box, S, delay)
	for i, c in ipairs(CRACKS) do
		task.delay(delay + (i - 1) * 0.05, function()
			if not box.Parent then return end
			new("Frame", { BackgroundColor3 = C.INK, BorderSizePixel = 0, ZIndex = 20,
				Size = UDim2.fromOffset(S * 0.06, S * 0.22), Position = UDim2.fromOffset(S * c[1], S * c[2]), Rotation = c[3] }, box)
		end)
	end
	play("crack", delay)
end

-- осколки/искры: n штук из точки, разлёт на k×размер
local function burst(parent, centre, n, sizeMin, sizeMax, k, colors, delay, dur, round)
	for i = 1, n do
		local sz = sizeMin + (sizeMax - sizeMin) * math.random()
		local ang = math.rad(-90 + (-75 + 150 * (i - 1) / math.max(n - 1, 1)))
		if round then ang = (i - 1) / n * math.pi * 2 end
		local p = new("Frame", { BackgroundColor3 = colors[(i - 1) % #colors + 1], BorderSizePixel = 0, ZIndex = 30,
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(sz, sz), Position = centre,
			BackgroundTransparency = 1 }, parent)
		if round then new("UICorner", { CornerRadius = UDim.new(1, 0) }, p) end
		task.delay(delay, function()
			if not p.Parent then return end
			p.BackgroundTransparency = 0
			tw(p, dur, {
				Position = centre + UDim2.fromOffset(math.cos(ang) * sz * k, math.sin(ang) * sz * k),
				Rotation = 280, BackgroundTransparency = 1,
			})
			task.delay(dur + 0.1, function() if p.Parent then p:Destroy() end end)
		end)
	end
end

local function label(parent, text, size, color, shadowOff)
	local holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(1200, size * 1.25) }, parent)
	new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, shadowOff or 3),
		Font = FONT, TextSize = size, TextColor3 = C.INK, Text = text, ZIndex = 11 }, holder)
	new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		Font = FONT, TextSize = size, TextColor3 = color or C.WHITE, Text = text, ZIndex = 12 }, holder)
	return holder
end

-- ═══════════ каркас сцены ═══════════
local current   -- ScreenGui активной сцены

local function stage()
	if current then current:Destroy() end
	local gui = new("ScreenGui", { Name = "DeathScreenGui", IgnoreGuiInset = true, ResetOnSpawn = false,
		DisplayOrder = 200, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	current = gui
	local dim = new("Frame", { Name = "Dim", BackgroundColor3 = C.DIM, BackgroundTransparency = 1,
		BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 1 }, gui)
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1586, 820)
	local k = math.max(0.45, vp.Y / 820)
	local centre = new("Frame", { Name = "Center", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromOffset(1300, 560), ZIndex = 5 }, gui)
	new("UIScale", { Scale = k }, centre)
	local col = new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 18) }, centre)
	local _ = col
	return gui, dim, centre, k
end

-- красная виньетка: четыре полосы с градиентом
local function vignette(gui)
	local parts = {}
	local function strip(size, pos, anchor, rot)
		local f = new("Frame", { BackgroundColor3 = C.RED, BorderSizePixel = 0, Size = size, Position = pos,
			AnchorPoint = anchor, BackgroundTransparency = 1, ZIndex = 2 }, gui)
		new("UIGradient", { Rotation = rot, Transparency = NumberSequence.new(0.45, 1) }, f)
		table.insert(parts, f)
	end
	strip(UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0), Vector2.new(0, 0), 90)
	strip(UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 1), Vector2.new(0, 1), -90)
	strip(UDim2.fromScale(0.14, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), 0)
	strip(UDim2.fromScale(0.14, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0), 180)
	for _, f in ipairs(parts) do
		tw(f, 0.45, { BackgroundTransparency = 0 })
		task.delay(0.45, function()
			if f.Parent then
				TweenService:Create(f, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ BackgroundTransparency = 0.55 }):Play()
			end
		end)
	end
	return parts
end

-- сердце вырывается из бейджа полосы здоровья (общий зачин)
local function ripHudHeart(gui, k)
	local S = 27 * math.max(k, 0.7)
	local at = UDim2.new(0.018, 23 * k, 0.95, -23 * k)
	local h = heart(gui, S, "red", 40)
	h.AnchorPoint = Vector2.new(0.5, 0.5)
	h.Position = at
	crack(h, S, 0.05)
	task.delay(0.15, function()
		if not h.Parent then return end
		play("rip")
		local s = scaleOf(h)
		tw(h, 0.15, { Position = at + UDim2.fromOffset(0, -0.8 * S), Rotation = -10 })
		tw(s, 0.15, { Scale = 1.2 })
		task.delay(0.15, function()
			if not h.Parent then return end
			tw(h, 0.35, { Position = at + UDim2.fromOffset(0.6 * S, -9 * S), Rotation = 28 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tw(s, 0.35, { Scale = 0.5 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			fade(h, 0.35, 1, 0, Enum.EasingDirection.In)
			task.delay(0.4, function() if h.Parent then h:Destroy() end end)
		end)
	end)
	burst(gui, at, 6, 18 * k, 26 * k, 5, { C.RED, C.INK }, 0.12, 0.6, false)
end

local function closeScene(gui, dim, centre, at)
	task.delay(at, function()
		if not gui.Parent then return end
		tw(scaleOf(centre), 0.5, { Scale = scaleOf(centre).Scale * 0.55 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		fade(centre, 0.5, 1, 0, Enum.EasingDirection.In)
		tw(dim, 0.5, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.1)
		for _, d in ipairs(gui:GetChildren()) do
			if d:IsA("Frame") and d ~= dim and d ~= centre then tw(d, 0.4, { BackgroundTransparency = 1 }) end
		end
		task.delay(0.65, function()
			if gui.Parent then gui:Destroy() end
			if current == gui then current = nil end
		end)
	end)
end

-- ═══════════ СЦЕНА: штраф пиратами (3.6 с) ═══════════
local function playPenalty(d)
	local gui, dim, centre, k = stage()
	tw(dim, 0.45, { BackgroundTransparency = 0.45 })
	ripHudHeart(gui, k)

	local row = new("Frame", { LayoutOrder = 1, BackgroundTransparency = 1, Size = UDim2.fromOffset(700, 130) }, centre)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local num = label(row, "−" .. tostring(d.penalty), 120, C.RED, 4)
	num.LayoutOrder = 1
	num.Size = UDim2.fromOffset(60 + 70 * #tostring(d.penalty), 130)
	local coin = new("ImageLabel", { LayoutOrder = 2, BackgroundTransparency = 1, Image = COIN_ICON,
		Size = UDim2.fromOffset(96, 96), ScaleType = Enum.ScaleType.Fit, ZIndex = 12 }, row)
	drop(row, 0.5)
	play("thud", 0.5)
	play("coins", 0.75)
	-- монета крутится и оседает
	task.delay(0.55, function()
		if coin.Parent then
			TweenService:Create(coin, TweenInfo.new(0.45, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 1, true),
				{ Size = UDim2.fromOffset(4, 96) }):Play()
		end
	end)

	local cap = label(centre, d.partial and "Пираты кончились" or ("Смерть стоила " .. d.penalty .. " пиратов"), 38, C.WHITE, 2)
	cap.LayoutOrder = 2
	fade(cap, 0, 1)
	fade(cap, 0.5, 0, 1.2)
	if d.partial then
		local warnLbl = label(centre, "Дальше смерть забирает жизни команды", 30, C.GOLD, 2)
		warnLbl.LayoutOrder = 3
		fade(warnLbl, 0, 1)
		fade(warnLbl, 0.5, 0, 1.7)
		play("warn", 1.7)
	end
	closeScene(gui, dim, centre, 3.0)
end

--[[ ⚠️ ЖИЗНИ КОНЧИЛИСЬ — ИГРЫ ЗА ЭКРАНОМ БОЛЬШЕ НЕТ. Персонаж уже возрождён
     сервером, и под полупрозрачной плашкой игрок бегал по плоту, пока висело
     «Забег окончен». Теперь экран уходит в чёрное, управление снимаем до
     ответа (купить жизнь → возвращаем; в лобби → телепорт). ]]
local controlsOff = false
local function setControls(on)
	controlsOff = not on
	pcall(function()
		local pm = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		local c = pm:GetControls()
		if on then c:Enable() else c:Disable() end
	end)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and not on then hum:Move(Vector3.zero) end
end
-- возродился во время экрана конца — снова без управления
player.CharacterAdded:Connect(function()
	if controlsOff then task.defer(setControls, false) end
end)

-- ═══════════ СЦЕНА: жизнь команды (4.0 с) / предложение ═══════════
local function playDeath(d)
	local total = math.clamp(math.floor(tonumber(d.livesTotal) or 3), 1, 10)
	local livesBefore = math.clamp(tonumber(d.livesBefore) or 1, 1, total)
	local livesAfter = livesBefore - 1
	local offer = livesAfter <= 0
	local gui, dim, centre, k = stage()
	-- конец забега — сплошной чёрный, мир за экраном не виден
	if offer then dim.BackgroundColor3 = Color3.new(0, 0, 0) end
	tw(dim, offer and 0.8 or 0.45, { BackgroundTransparency = offer and 0 or 0.4 })
	if offer then setControls(false) end
	vignette(gui)
	ripHudHeart(gui, k)

	-- жизней от 2 до 7+ (зависит от числа игроков): сердца мельче, чтобы ряд влезал
	local S = (total <= 3) and 120 or (total <= 5) and 100 or 84
	local gap = (total <= 3) and 32 or 22
	local row = new("Frame", { LayoutOrder = 1, BackgroundTransparency = 1, Size = UDim2.fromOffset(S * total + gap * (total - 1), S) }, centre)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local slots = {}
	for i = 1, total do
		local slot = new("Frame", { LayoutOrder = i, BackgroundTransparency = 1, Size = UDim2.fromOffset(S, S * 0.85) }, row)
		local empty = heart(slot, S, "empty", 10)
		fade(empty, 0, 1)
		fade(empty, 0.35, 0, 0.5 + (i - 1) * 0.08)
		local red
		if i <= livesBefore then
			red = heart(slot, S, "red", 14)
			drop(red, 0.5 + (i - 1) * 0.08)
			play("thud", 0.5 + (i - 1) * 0.08)
		end
		slots[i] = { slot = slot, red = red }
	end

	-- ломается крайнее из оставшихся
	local victim = slots[livesBefore]
	if victim.red then
		crack(victim.red, S, 1.05)
		task.delay(1.1, function()
			if not victim.red.Parent then return end
			local s = scaleOf(victim.red)
			tw(s, 0.2, { Scale = 1.22 }); tw(victim.red, 0.2, { Rotation = -7 })
			task.delay(0.2, function()
				if not victim.red.Parent then return end
				play("shatter")
				tw(s, 0.4, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				tw(victim.red, 0.4, { Rotation = 5 })
				fade(victim.red, 0.4, 1, 0, Enum.EasingDirection.In)
			end)
		end)
		task.delay(1.35, function()
			if not row.Parent then return end
			local ap, as = victim.slot.AbsolutePosition, victim.slot.AbsoluteSize
			burst(gui, UDim2.fromOffset(ap.X + as.X / 2, ap.Y + as.Y / 2), 10, 24 * k, 42 * k, 5, { C.RED, C.INK }, 0, 0.7, false)
		end)
	end
	-- целые пульсируют
	for i = 1, livesAfter do
		local r = slots[i].red
		if r then
			task.delay(1.3, function()
				if r.Parent then
					TweenService:Create(scaleOf(r), TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.05 }):Play()
				end
			end)
		end
	end

	local title = label(centre, offer and "ЖИЗНИ КОМАНДЫ КОНЧИЛИСЬ" or ("Осталось жизней: " .. livesAfter), offer and 75 or 80, C.WHITE, 3)
	title.LayoutOrder = 2
	drop(title, 1.15)
	play("thud", 1.15)
	local capText = offer and (d.price and "Купить экстра-жизнь за Robux и продолжить забег?" or "Забег окончен")
		or (livesAfter == 1 and "Последняя жизнь команды — берегите её" or "Команда потеряла одну жизнь")
	local cap = label(centre, capText, 34, C.WHITE, 2)
	cap.LayoutOrder = 3
	fade(cap, 0, 1)
	fade(cap, 0.5, 0, 1.7)
	if livesAfter == 1 or offer then play("warn", 1.7) end

	if not offer then
		closeScene(gui, dim, centre, 3.4)
		return
	end

	-- кнопки: «Купить ◈ N» и «Нет, в лобби»
	local btnRow = new("Frame", { LayoutOrder = 4, BackgroundTransparency = 1, Size = UDim2.fromOffset(900, 90) }, centre)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 24), SortOrder = Enum.SortOrder.LayoutOrder }, btnRow)
	local function button(order, text, top, bot, shadow, size)
		local holder = new("Frame", { LayoutOrder = order, BackgroundTransparency = 1, Size = UDim2.fromOffset(size, 78) }, btnRow)
		new("Frame", { BackgroundColor3 = shadow, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, 5), ZIndex = 11 }, holder)
			:SetAttribute("Bg", true)
		new("UICorner", { CornerRadius = UDim.new(0, 18) }, holder:FindFirstChildOfClass("Frame"))
		--[[ ⚠️ ГРАДИЕНТ — НА КНОПКЕ БЕЗ ТЕКСТА. UIGradient красит и текст своего
		     объекта: белое «Нет, в лобби» становилось серым на сером и сливалось.
		     Кнопка несёт фон и градиент, надпись — отдельная метка поверх. ]]
		local b = new("TextButton", { BackgroundColor3 = C.WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), AutoButtonColor = true,
			Text = "", ZIndex = 12 }, holder)
		new("UICorner", { CornerRadius = UDim.new(0, 18) }, b)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(top, bot) }, b)
		new("UIStroke", { Thickness = 3, Color = C.INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		local tl = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, 0),
			Font = FONT, TextSize = order == 1 and 36 or 30, TextColor3 = C.WHITE, Text = text, ZIndex = 13 }, holder)
		new("UIStroke", { Thickness = 2, Color = C.INK, Transparency = 0.2 }, tl)
		return holder, b
	end
	local buyHolder, buyBtn, noBtn
	if d.price then
		buyHolder, buyBtn = button(1, "Купить  ◈ " .. tostring(d.price), C.GREEN, C.GREEN_DARK, C.GREEN_SHADOW, 360)
	end
	local _, nb = button(2, "Нет, в лобби", C.GREY, C.GREY_DARK, C.GREY_SHADOW, 300)
	noBtn = nb
	btnRow.Visible = false
	task.delay(2.0, function()
		if not btnRow.Parent then return end
		btnRow.Visible = true
		local s = scaleOf(btnRow); s.Scale = 0.6
		tw(s, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		if buyHolder then
			task.delay(0.5, function()
				if buyHolder.Parent then
					TweenService:Create(scaleOf(buyHolder), TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.04 }):Play()
				end
			end)
		end
	end)
	if buyBtn then
		buyBtn.Activated:Connect(function() play("click"); action:FireServer("buy") end)
	end
	noBtn.Activated:Connect(function() play("click"); action:FireServer("decline") end)
end

-- ═══════════ СЦЕНА: оживление (3.7 с) ═══════════
local function playRevive()
	local gui, dim, centre, k = stage()
	setControls(true)   -- купил экстра-жизнь: забег продолжается, управление обратно
	tw(dim, 0.3, { BackgroundTransparency = 0.4 })
	local flash = new("Frame", { BackgroundColor3 = C.GREEN, BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1), ZIndex = 3 }, gui)
	tw(flash, 0.27, { BackgroundTransparency = 0.72 }, nil, nil, 0.2)
	tw(flash, 0.63, { BackgroundTransparency = 1 }, nil, nil, 0.47)
	play("revive", 0.15)

	local S = 130
	local slot = new("Frame", { LayoutOrder = 1, BackgroundTransparency = 1, Size = UDim2.fromOffset(S, S * 0.85) }, centre)
	local big = heart(slot, S, "red", 14)
	local s = scaleOf(big); s.Scale = 0.3; big.Rotation = -20
	task.delay(0.1, function()
		if not big.Parent then return end
		tw(s, 0.8, { Scale = 1 }, Enum.EasingStyle.Back)
		tw(big, 0.8, { Rotation = 0 }, Enum.EasingStyle.Back)
	end)
	task.delay(0.45, function()
		if not slot.Parent then return end
		local ap, as = slot.AbsolutePosition, slot.AbsoluteSize
		burst(gui, UDim2.fromOffset(ap.X + as.X / 2, ap.Y + as.Y / 2), 12, 26 * k, 45 * k, 7, { C.GREEN, C.GOLD, C.WHITE }, 0, 0.9, true)
	end)
	-- сердце бьётся: два удара по 1.1 с
	for beat = 0, 1 do
		local t0 = 0.9 + beat * 1.1
		play("beat", t0); play("beat", t0 + 0.33)
		task.delay(t0, function() if big.Parent then tw(s, 0.16, { Scale = 1.18 }, Enum.EasingStyle.Sine) end end)
		task.delay(t0 + 0.16, function() if big.Parent then tw(s, 0.17, { Scale = 1 }, Enum.EasingStyle.Sine) end end)
		task.delay(t0 + 0.33, function() if big.Parent then tw(s, 0.16, { Scale = 1.12 }, Enum.EasingStyle.Sine) end end)
		task.delay(t0 + 0.5, function() if big.Parent then tw(s, 0.3, { Scale = 1 }, Enum.EasingStyle.Sine) end end)
	end
	local title = label(centre, "ВЫ ЖИВЫ!", 90, C.GREEN, 3)
	title.LayoutOrder = 2
	drop(title, 0.6)
	local cap = label(centre, "Экстра-жизнь активирована. Забег продолжается", 34, C.WHITE, 2)
	cap.LayoutOrder = 3
	fade(cap, 0, 1)
	fade(cap, 0.5, 0, 1.2)
	closeScene(gui, dim, centre, 3.1)
end

-- ═══════════ СЦЕНА: лобби (остаётся до телепорта) ═══════════
local function playLobby()
	local gui, _, centre = stage()
	local black = new("Frame", { BackgroundColor3 = C.LOBBY, BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1), ZIndex = 4 }, gui)
	tw(black, 0.5, { BackgroundTransparency = 0 })
	local text = new("TextLabel", { LayoutOrder = 1, BackgroundTransparency = 1, Size = UDim2.fromOffset(1200, 90),
		Font = Enum.Font.PermanentMarker, TextSize = 70, TextColor3 = C.WHITE, Text = "Возвращаемся в лобби", TextTransparency = 1, ZIndex = 12 }, centre)
	local boat = new("TextLabel", { LayoutOrder = 2, BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 100),
		Font = FONT, TextSize = 90, TextColor3 = C.WHITE, Text = "⛵", TextTransparency = 1, ZIndex = 12 }, centre)
	local done = new("TextLabel", { LayoutOrder = 3, BackgroundTransparency = 1, Size = UDim2.fromOffset(1200, 40),
		Font = FONT, TextSize = 30, TextColor3 = C.WHITE, Text = "Забег завершён", TextTransparency = 1, ZIndex = 12 }, centre)
	tw(text, 0.4, { TextTransparency = 0 }, nil, nil, 0.3)
	tw(boat, 0.4, { TextTransparency = 0 }, nil, nil, 0.45)
	tw(done, 0.4, { TextTransparency = 0.3 }, nil, nil, 0.6)
	task.delay(0.6, function()
		if boat.Parent then
			TweenService:Create(boat, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 4 }):Play()
		end
	end)
	task.spawn(function()
		local n = 0
		while gui.Parent do
			n = n % 3 + 1
			text.Text = "Возвращаемся в лобби" .. string.rep(".", n)
			task.wait(0.45)
		end
	end)
end

remote.OnClientEvent:Connect(function(d)
	if type(d) ~= "table" then return end
	local ok, err = pcall(function()
		if d.scene == "penalty" then playPenalty(d)
		elseif d.scene == "death" then playDeath(d)
		elseif d.scene == "revive" then playRevive()
		elseif d.scene == "lobby" then playLobby() end
	end)
	if not ok then warn("[Экран смерти] " .. tostring(err)) end
end)

print("[Экран смерти] готов: штраф пиратами, жизни команды, экстра-жизнь, лобби")
