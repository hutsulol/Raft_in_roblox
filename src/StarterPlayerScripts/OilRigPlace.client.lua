local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ОСТРОВНЫЕ ПОСТРОЙКИ — постановка из меню молотка.

	Выбрал в молотке «Остров → Нефтевышка» или «Остров → Дом» — появляется призрак
	на суше; зелёный значит поставится, красный нет. ЛКМ ставит, R разворачивает.

	⚠️ ОДИН СКРИПТ НА ВСЕ ОСТРОВНЫЕ ПОСТРОЙКИ.
	Дом отличается от вышки ровно тремя вещами: модель, глубина посадки и на какой
	RemoteEvent слать клик. Всё остальное — призрак, подсветка, поворот, проверка
	места — совпадает дословно, поэтому лежит в одной таблице KINDS, а не во
	второй копии этого файла.

	⚠️ ЭТО НЕ СЕТКА ПЛОТА. Молоток строит по клеткам, а остров — свободный
	рельеф. Поэтому пункт меню общий, а призрак и проверку ведёт этот скрипт:
	сеточная логика к рельефу неприменима, и мешать их нельзя. Сам молоток при
	выборе островной постройки свой призрак прячет (см. BuildingSystem.client).

	⚠️ ПОВОРОТ — ЧЕРЕЗ ContextActionService, А НЕ InputBegan.
	Меню стройки открыто, и клавишу R общий обработчик получает уже съеденной
	(processed = true) — ровно на это когда-то напоролся причал. Через
	ContextActionService она доходит всегда.

	⚠️ ПРИЗРАК СТОИТ НА ПОВЕРХНОСТИ, А НЕ СЕРЕДИНОЙ В НЕЙ.
	Пивот модели не на подошве, и без пересчёта вышка тонула в грунте наполовину.
	Считаем расстояние от пивота до низа габарита и садим низ на точку прицела.
]]

local Players               = game:GetService("Players")
local ReplicatedStorage     = game:GetService("ReplicatedStorage")
local RunService            = game:GetService("RunService")
local UserInputService      = game:GetService("UserInputService")
local ContextActionService  = game:GetService("ContextActionService")
local Workspace             = game:GetService("Workspace")

local Defs      = require(ReplicatedStorage:WaitForChild("OilRigDefs"))
local HouseDefs = require(ReplicatedStorage:WaitForChild("HouseDefs"))
local FarmDefs  = require(ReplicatedStorage:WaitForChild("FarmDefs"))
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

local player = Players.LocalPlayer
local mouse = player:GetMouse()
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))

local REACH = 90

-- buildType из меню → что ставим. sink — насколько утапливаем в грунт: у вышки
-- сваи уходят вниз на полтора студа, у дома в землю садится только цоколь.
local KINDS = {
	-- ⚠️ ГЛУБИНА ПОСАДКИ ВЫШКИ — НЕ НА ГЛАЗ, А ИЗ МОДЕЛИ.
	-- OilRig/README.md, раздел 2: земля z = 0, настил z = 0.55 м, сваи уходят до
	-- −1.30 м. При импорте ×3 это 3.9 студа под землёй. Стояло 1.5 — вышка
	-- поднималась на 2.4 студа выше задуманного, и нижняя ступень крыльца висела
	-- в воздухе.
	oilrig = {
		model = Defs.STATION,  sink = 3.9,
		event = ReplicatedStorage:WaitForChild("OilRigPlace"),
		icon = "🛢️", okTitle = "Вышка поставлена", okBody = "Рабочие вышли на смену",
		noBody = "нужна суша острова",
	},
	house = {
		model = HouseDefs.MODEL, sink = HouseDefs.SINK,
		event = ReplicatedStorage:WaitForChild("HousePlace"),
		icon = "🏠", okTitle = "Дом построен", okBody = "Жители будут ночевать здесь",
		noBody = "нужна ровная суша острова",
	},
	-- ферма: та же постановка, но допуск по уклону строже — ограда жёсткая
	farm = {
		model = FarmDefs.MODEL, modelAlt = FarmDefs.MODEL_ALT, sink = FarmDefs.SINK, flatTol = FarmDefs.FLAT_TOL,
		event = ReplicatedStorage:WaitForChild("FarmPlace"),
		icon = "🐑", okTitle = "Ферма построена", okBody = "Назначь жителю профессию «Фермер» в доме",
		noBody = "нужна ровная суша острова",
	},
}

local ghost, bottomDrop, ghostSize = nil, 0, Vector3.zero
local ghostKind = nil       -- для какого вида собран текущий призрак
local rot, canPlace, bound = 0, false, false

local function chosen()
	local item = _G.BuildSelectedItem
	local kind = item and KINDS[item.buildType]
	if kind then return item.buildType, kind end
	return nil
end

local function template(kind)
	return AssetFind.find(kind.model)
		or (kind.modelAlt and AssetFind.find(kind.modelAlt))
		or Workspace:FindFirstChild(kind.model)
end

local function dropGhost()
	if ghost then ghost:Destroy() end
	ghost = nil
	ghostKind = nil
end

local function buildGhost(id, kind)
	local tpl = template(kind)
	if not tpl then return end
	dropGhost()
	ghost = tpl:Clone()
	ghost.Name = "IslandGhost"
	ghostKind = id

	for _, d in ipairs(ghost:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Material = Enum.Material.Neon
			d.Transparency = 0.5
			-- ⚠️ СНИМАЕМ ТЕКСТУРУ. Пока на детали есть атлас (TextureID) или
			-- SurfaceAppearance, свойство Color не видно вовсе — призрак так и
			-- оставался серым, и зелёный/красный вердикт не читался.
			if d:IsA("MeshPart") then d.TextureID = "" end
		elseif d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture")
			or d:IsA("BaseScript") or d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end

	local bbCF, size = ghost:GetBoundingBox()
	ghostSize = size
	bottomDrop = ghost:GetPivot().Position.Y - (bbCF.Position.Y - size.Y * 0.5)
	ghost.Parent = Workspace
end

local function tint(ok)
	if not ghost then return end
	local col = ok and Color3.fromRGB(90, 235, 120) or Color3.fromRGB(235, 80, 70)
	for _, d in ipairs(ghost:GetDescendants()) do
		if d:IsA("BasePart") then d.Color = col end
	end
end

-- Та же проверка, что на сервере: под углами настила должна быть суша острова,
-- воды быть не должно. Здесь она только красит призрак, решает всё равно сервер.
local rayParams = RaycastParams.new()
rayParams.IgnoreWater = false
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- ⚠️ ТРИ УСЛОВИЯ, ТЕ ЖЕ ЧТО НА СЕРВЕРЕ: суша, ровно, свободно.
-- Одной проверки «не вода» мало — на склоне вышка встаёт враспор, а камни и
-- пальмы она просто прошивала насквозь.
-- допуски держим ровно как на сервере, иначе призрак зелёный, а клик отказывает
local FLAT_TOL = 6
local CHECK_HEIGHT = 10

local function isGround(inst)
	local n = inst.Name
	return n:sub(1, #Defs.TILE_PREFIX) == Defs.TILE_PREFIX
		or n:sub(1, 13) == "Island_seabed"
end

local function spotLooksOK(cf, flatTol)
	flatTol = flatTol or FLAT_TOL
	local half = ghostSize * 0.5
	local pts = {
		Vector3.new(-half.X, 0, -half.Z), Vector3.new(half.X, 0, -half.Z),
		Vector3.new(-half.X, 0, half.Z),  Vector3.new(half.X, 0, half.Z),
		Vector3.zero,
	}
	local land, lowest, highest = 0, math.huge, -math.huge
	for _, p in ipairs(pts) do
		local from = cf:PointToWorldSpace(p) + Vector3.new(0, 60, 0)
		local hit = Workspace:Raycast(from, Vector3.new(0, -160, 0), rayParams)
		if not hit or hit.Material == Enum.Material.Water then return false end
		if hit.Instance.Name:sub(1, #Defs.TILE_PREFIX) == Defs.TILE_PREFIX then land += 1 end
		lowest = math.min(lowest, hit.Position.Y)
		highest = math.max(highest, hit.Position.Y)
	end
	if land < 3 or highest - lowest > flatTol then return false end
	-- сам игрок внутри габарита — призрак красный (сервер откажет так же)
	do
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local l = cf:PointToObjectSpace(hrp.Position)
			if math.abs(l.X) <= half.X + 1.5 and math.abs(l.Z) <= half.Z + 1.5 then return false end
		end
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ghost, player.Character }
	params.MaxParts = 40
	local h = math.min(ghostSize.Y, CHECK_HEIGHT)
	local boxCF = cf * CFrame.new(0, h * 0.5 + 1, 0)
	for _, part in ipairs(Workspace:GetPartBoundsInBox(boxCF,
		Vector3.new(ghostSize.X * 0.8, h, ghostSize.Z * 0.8), params)) do
		-- ⚠️ ТО ЖЕ ПРАВИЛО, ЧТО НА СЕРВЕРЕ (Defs.isDecor).
		-- Трава, ракушки и мелкие камни местом не считаются. Раньше здесь стояла
		-- своя проверка «любая деталь с коллизией», и призрак краснел почти везде.
		if not isGround(part) and not Defs.isDecor(part) then return false end
	end
	return true
end

local function bindRotate(on)
	if on and not bound then
		bound = true
		ContextActionService:BindAction("OilRigRotate", function(_, state)
			if state == Enum.UserInputState.Begin then rot = (rot + 1) % 4 end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	elseif not on and bound then
		bound = false
		ContextActionService:UnbindAction("OilRigRotate")
	end
end

RunService.RenderStepped:Connect(function()
	local id, kind = chosen()
	if not id then
		dropGhost()
		bindRotate(false)
		canPlace = false
		return
	end
	-- переключились с вышки на дом (или обратно) — призрак пересобираем
	if not ghost or ghostKind ~= id then buildGhost(id, kind) end
	if not ghost then return end
	bindRotate(true)

	local char = player.Character
	rayParams.FilterDescendantsInstances = { ghost, char }
	local hit = Workspace:Raycast(mouse.UnitRay.Origin, mouse.UnitRay.Direction * REACH, rayParams)
	if not hit then
		ghost.Parent = nil
		canPlace = false
		return
	end
	ghost.Parent = Workspace

	-- низ постройки на точку прицела, опоры чуть в грунт
	local pos = hit.Position + Vector3.new(0, bottomDrop - kind.sink, 0)
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(rot * 90), 0)
	pcall(function() ghost:PivotTo(cf) end)

	-- ⚠️ ТОЛЬКО СУША ОСТРОВА. Без этой проверки призрак липнул к настилу плота:
	-- луч бьёт во всё подряд, а плот ближе всего.
	local onTile = hit.Instance.Name:sub(1, #Defs.TILE_PREFIX) == Defs.TILE_PREFIX
	canPlace = onTile and spotLooksOK(cf, kind.flatTol)
	tint(canPlace)
end)

-- ⚠️ КЛИК ОТПРАВЛЯЕМ ДАЖЕ НА КРАСНОМ.
-- Раньше по красному призраку клик просто ничего не делал, и игрок оставался
-- гадать, что не так. Сервер всё равно проверяет сам и в отказе называет
-- причину — пусть лучше скажет её вслух.
UserInputService.InputBegan:Connect(function(input, processed)
	local _, kind = chosen()
	if processed or not kind or not ghost then return end
	if GamepadInput.isPrimary(input) then
		kind.event:FireServer(ghost:GetPivot())
	end
end)

--[[ ОТКАЗЫ — В МЕНЮ МОЛОТКА. Игрок кликает по красному призраку много раз
     подряд, и стопка уведомлений сбоку вырастала в столб. Тост меню один и
     перезаписывается. Причины различаются цветом и значком: пираты — красный,
     рельеф — оранжевый, остальное — синий. ]]
local DENY_LOOK = {
	{ find = "пират",  color = Color3.fromRGB(196, 52, 52),  text = "🏴‍☠️ Остров под пиратами — сначала освободи его" },
	{ find = "грунт",  color = Color3.fromRGB(214, 122, 32), text = "⛰️ Настил уходит под грунт — выбери место ровнее" },
	{ find = "в воде", color = Color3.fromRGB(214, 122, 32), text = "🌊 Угол постройки в воде — отодвинь от берега" },
	{ find = "пусто",  color = Color3.fromRGB(214, 122, 32), text = "🕳️ Под опорой пусто — нужна суша острова" },
	{ find = "стоишь", color = Color3.fromRGB(214, 122, 32), text = "🚶 Отойди: ты стоишь на месте постройки" },
	{ find = "стоит",  color = Color3.fromRGB(214, 122, 32), text = "🚶 На месте постройки стоит игрок" },
}
local function denyLook(why)
	local w = tostring(why or ""):lower()
	for _, e in ipairs(DENY_LOOK) do
		if w:find(e.find, 1, true) then return e.text, e.color end
	end
	return nil, nil
end

for _, kind in pairs(KINDS) do
	kind.event.OnClientEvent:Connect(function(action, why)
		if action == "denied" then
			local text, color = denyLook(why)
			text = text or ("🚫 Здесь нельзя: " .. tostring(why or kind.noBody))
			if typeof(_G.BuildToast) == "function" and _G.BuildingScreenGui then
				_G.BuildToast(text, color, 2.5)
			elseif _G.Notify then
				_G.Notify({ type = "warn", icon = kind.icon, title = "Здесь нельзя", body = text })
			end
			return
		end
		if not _G.Notify then return end
		if action == "placed" then
			_G.Notify({ type = "success", icon = kind.icon, title = kind.okTitle,
				body = kind.okBody })
		end
	end)
end

print("[Остров/клиент] в молотке «Остров»: Нефтевышка, Дом и Ферма. ЛКМ ставит, R разворачивает")
