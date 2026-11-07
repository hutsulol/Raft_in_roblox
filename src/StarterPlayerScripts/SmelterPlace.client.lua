local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ПЛАВИЛЬНЯ: НАВОДКА И КЛИКИ (зеркало GrillFoodPlace, упрощённое).

	  • В руках руда/водоросли (Tool с атрибутом MaterialResource), курсор на
	    плавильне, слот пуст → призрак-заготовка (raw-слой) подсвечивается
	    ЗЕЛЁНЫМ. ЛКМ — поставить (SmelterAction "place").
	  • Партия доплавилась (state "done"), курсор на плавильне → расплав
	    подсвечивается ЗОЛОТЫМ. ЛКМ — забрать (SmelterAction "collect").

	Клик ловим ContextActionService'ом: ClickDetector не срабатывает, пока
	экипирован Tool — с рудой в руках по печи нельзя было бы кликнуть вообще
	(тот же урок, что у мангала). Всё состояние читается из атрибутов модели
	(их пишет SmelterSystem), клиент ничего не решает — только показывает и
	просит.
]]

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local RunService           = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))
local camera = workspace.CurrentCamera

local actionEvent = ReplicatedStorage:WaitForChild("SmelterAction", 10)
if not actionEvent then
	warn("[Плавильня/клиент] нет ремоута SmelterAction — установка сырья работать не будет")
	return
end

--[[ ⚠️ ПРИЦЕЛ НА ТЕЛЕФОНЕ ИДЁТ ЧЕРЕЗ ОБЩИЙ МОДУЛЬ.
     Печь ищется одной строкой — лучом из курсора. Курсора на телефоне нет, там
     место выбирает тап, а действие подтверждает кнопка. Вся эта механика лежит
     в TouchPlace; на компьютере модуль не делает ничего. ]]
--[[ ⚠️ МЕХАНИКУ БЕРЁМ ИЗ HudScale, А ЖДЁМ — С ТАЙМАУТОМ. ДВЕ ЛОВУШКИ РАЗОМ.
     Первая: WaitForChild без второго аргумента ждёт ВЕЧНО, и не доехавший
     модуль остановил бы ВЕСЬ этот скрипт — предмет в руках есть, а поставить
     нельзя ничем и нигде, причём молча.
     Вторая, из-за которой правка и не работала на телефоне: НОВЫЙ файл до
     запущенной сессии Rojo доезжает не всегда. Правки существующих файлов
     синкаются, а новый инстанс появляется в плейсе только после
     переподключения — и ставилки честно откатывались на мышь, то есть на то
     самое поведение, от которого уходили.
     Поэтому спрашиваем сначала HudScale: он в плейсе давно и синкается штатно,
     а вся механика постановки живёт теперь в нём (HudScale.Place). Отдельный
     TouchPlace остаётся запасным именем — кто его нашёл, получит то же самое.
     Не нашли ни того, ни другого — работаем по-старому, мышью. ]]
-- касание без мыши = телефон; считаем сами, не завися от общего модуля
local IS_TOUCH = game:GetService("UserInputService").TouchEnabled
	and not game:GetService("UserInputService").MouseEnabled

local TouchPlace do
	local rs = game:GetService("ReplicatedStorage")
	local function grab(name, field)
		local mod = rs:FindFirstChild(name) or rs:WaitForChild(name, 5)
		if not mod then return nil end
		local ok, res = pcall(require, mod)
		if not ok then return nil end
		if field then res = (type(res) == "table") and res[field] or nil end
		return (type(res) == "table") and res or nil
	end

	TouchPlace = grab("HudScale", "Place") or grab("TouchPlace") or {
		isPhone = function() return false end,
		ray = function(m)
			local cam = workspace.CurrentCamera
			if not (cam and m) then return nil end
			return cam:ViewportPointToRay(m.X, m.Y)
		end,
		setHit = function() end,
		begin  = function() end,
		finish = function() end,
		active = function() return false end,
	}
	if not TouchPlace.begin or TouchPlace.isPhone() == nil then
		warn("[Установка] механика постановки не найдена — ставим по-старому, мышью")
	end
end

local RAY_DIST = 250
local REACH    = 14

-- Диагностика: печатает, где обрывается цепочка «сырьё в руках → курсор на
-- печи → призрак → клик». Выключить, когда механика устоится.
local SMELTER_DEBUG = true
local lastDebug = ""
local function dbg(msg)
	if not SMELTER_DEBUG or msg == lastDebug then return end
	lastDebug = msg
	print("[Плавильня/клиент] " .. msg)
end

-- ключ материала → какой слой подсвечивать и каким «kind» просить сервер
local MATERIALS = {
	Iron_Ore = { kind = "iron",    rawName = "raft_smelter_iron_raw",
		stateAttr = "IronState",    progAttr = "IronProg",
		moltenName = "raft_smelter_iron_molten" },
	Seaweed  = { kind = "seaweed", rawName = "raft_smelter_seaweed_raw",
		stateAttr = "SeaweedState", progAttr = "SeaweedProg",
		moltenName = "raft_smelter_seaweed_molten" },
}

-- ── подсветка готового (сбор) ──
local highlight = Instance.new("Highlight")
highlight.Name = "SmelterHighlight"
highlight.FillTransparency = 0.55
highlight.OutlineTransparency = 0
highlight.Enabled = false
highlight.Parent = player:WaitForChild("PlayerGui")

local GREEN = Color3.fromRGB(80, 220, 90)
local GOLD  = Color3.fromRGB(255, 200, 60)

local function showHighlight(target, color)
	highlight.Adornee = target
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.Enabled = true
end

local function hideHighlight()
	highlight.Enabled = false
	highlight.Adornee = nil
end

--[[ ⚠️ ПОДСКАЗОК ПЛАВИЛЬНИ БОЛЬШЕ НЕТ — НИ ОДНОЙ, ПО ПРОСЬБЕ ВЛАДЕЛЬЦА.
     Строка внизу экрана («положи руду или водоросли и подкинь бревно»,
     «плавится… ~40 сек» и прочие) спорила за место с подсказкой квеста и
     статусом установки, особенно на телефоне. Всё, что она сообщала, и так
     видно: зелёный призрак показывает, куда ляжет заготовка, золотая подсветка —
     что расплав готов, огонь виден по самой печи.
     Раньше тут стоял выключатель SHOW_HINTS, но сам ScreenGui продолжал
     создаваться. Теперь не создаётся вовсе, а setHint остался пустой заглушкой:
     вызовов полтора десятка, и вырезать каждый — лишний риск на ровном месте. ]]
local function setHint(_) end

--[[ ⚠️ ДОБИВАЕМ ЧУЖИЕ КОПИИ ПОДСКАЗКИ.
     StarterPlayerScripts в default.project.json помечен $ignoreUnknownInstances:
     старый дубль этого скрипта, once залитый в плейс руками, Rojo не удаляет —
     он живёт своей жизнью и рисует свой ScreenGui «SmelterHint». Именно так
     подсказки и остались на экране после того, как их выключили в исходнике.
     Сносим и то, что уже есть, и то, что появится: гуй строится один раз при
     старте скрипта, поэтому после сноса дубль его не пересоздаёт. ]]
local playerGui = player:WaitForChild("PlayerGui")
local HINT_GUI_NAME = "SmelterHint"

local function killForeignHint(inst)
	if inst:IsA("ScreenGui") and inst.Name == HINT_GUI_NAME then
		inst:Destroy()
	end
end

playerGui.ChildAdded:Connect(killForeignHint)
for _, g in ipairs(playerGui:GetChildren()) do killForeignHint(g) end

-- Подстраховка на случай дубля с ДРУГИМ именем гуя: полминуты после входа
-- ищем чужую строку по самому тексту подсказки. Дальше не сканируем — дубль
-- создаёт свой гуй при старте, позже взяться ему неоткуда.
task.spawn(function()
	local MARKS = { "Положи руду", "Плавится", "Огонь погас", "переплавлено", "Клей готов" }
	for _ = 1, 30 do
		task.wait(1)
		for _, g in ipairs(playerGui:GetChildren()) do
			if g:IsA("ScreenGui") then
				for _, d in ipairs(g:GetDescendants()) do
					if d:IsA("TextLabel") and d.Visible and d.Name == "HintText" then
						for _, mark in ipairs(MARKS) do
							if string.find(d.Text, mark, 1, true) then g:Destroy() break end
						end
					end
				end
			end
		end
	end
end)

-- ── зелёный призрак сырья (установка) ──
-- В пустой печи заготовка ПОЛНОСТЬЮ невидима (сервер держит Transparency=1), и
-- Highlight на невидимой детали не нарисуется. Поэтому «куда встанет» показывает
-- ЛОКАЛЬНЫЙ клон слоя: зелёный, полупрозрачный, каждый кадр приклеенный к
-- оригиналу (плот плывёт — призрак едет с ним).
-- объявлена заранее: её зовёт кнопка подтверждения на телефоне, а тело лежит
-- внизу, рядом с привязкой клика
local onPlaceClick

local ghost = nil
local ghostFor = nil      -- какой raw-слой отображаем
local ghostSync = {}      -- [клон BasePart] = оригинал BasePart

local function destroyGhost()
	if ghost then ghost:Destroy() end
	ghost, ghostFor, ghostSync = nil, nil, {}
end

local function collectParts(container, out)
	if container:IsA("BasePart") then table.insert(out, container) end
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(out, d) end
	end
	return out
end

local function ensureGhost(raw)
	if ghostFor == raw then return end
	destroyGhost()
	ghostFor = raw
	ghost = raw:Clone()
	ghost.Name = "SmelterMaterialGhost"

	local srcParts = collectParts(raw, {})
	local cloneParts = collectParts(ghost, {})
	for i, cp in ipairs(cloneParts) do
		cp.Transparency = 0.45
		cp.Color = GREEN
		cp.CanCollide = false
		cp.CanQuery = false
		cp.Anchored = true
		if srcParts[i] then ghostSync[cp] = srcParts[i] end
	end
	for _, d in ipairs(ghost:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ParticleEmitter")
			or d:IsA("ProximityPrompt") or d:IsA("Weld") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	ghost.Parent = workspace
end

local function syncGhost()
	for cp, op in pairs(ghostSync) do
		if cp.Parent and op.Parent then
			cp.CFrame = op.CFrame
		end
	end
end

-- ── что в руках ──
local function heldMaterial()
	local char = player.Character
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	if not tool then return nil end
	local key = tool:GetAttribute("MaterialResource")
	return MATERIALS[key] and key or nil
end

--[[ ⚠️ СЕАНС ДЕРЖИМ ПО СЫРЬЮ В РУКАХ, А НЕ ПО ПРИЗРАКУ.
     У остальных ставилок призрак рождается вместе с тулом, и открывать сеанс
     логично там. Здесь наоборот: призрак появляется, только когда прицел УЖЕ на
     печи, а прицел на телефоне задаёт тап — и тап модуль ловит лишь внутри
     сеанса. Открой сеанс из ensureGhost — он не откроется никогда: целиться
     нечем, печь не найдётся, призрака не будет. Вдобавок destroyGhost зовётся
     почти каждый кадр, а finish() забывает выбранную точку — прицел бы стирался
     на месте. Поэтому момент берём тот же по смыслу, что и у эталона: игрок
     взял в руки то, что собирается положить. ]]
local touchSession = false
local function updateTouchSession()
	local want = heldMaterial() ~= nil
	if want == touchSession then return end
	touchSession = want
	if want then
		TouchPlace.begin({
			confirm = function() if onPlaceClick then onPlaceClick() end end,
			-- призрак стоит на самой печи и мог бы принять тап на себя
			ignore  = function() return ghost end,
		})
	else
		TouchPlace.finish()
	end
end

-- ⚠️ ПОЗИЦИЯ ПЕЧИ — ПО ЖИВОЙ ДЕТАЛИ, НЕ GetPivot. WorldPivot модели без
-- PrimaryPart статичен: он запомнился в точке установки, а плот с приваренной
-- печью уплывает — и «расстояние до печи» росло с каждой секундой дрейфа
-- («плавильня под курсором, но слишком далеко» у стоящего вплотную игрока).
local function smelterPos(smelter)
	local body = smelter:FindFirstChild("raft_smelter_body", true)
	local part = body and (body:IsA("BasePart") and body
		or body:FindFirstChildWhichIsA("BasePart", true))
	part = part or smelter:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

-- ── плавильня под курсором ──
-- список печей в мире (обновляется раз в 2 сек — для запасного поиска)
local smelterCache, smelterCacheT = {}, -10
local function allSmelters()
	if os.clock() - smelterCacheT > 2 then
		smelterCache = {}
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("Model") and d.Name:lower():find("raft_smelter", 1, true) then
				table.insert(smelterCache, d)
			end
		end
		smelterCacheT = os.clock()
	end
	return smelterCache
end

local function smelterUnderMouse()
	--[[ 1) честный луч. На компьютере — из курсора, как и был. На телефоне, пока
	     идёт сеанс установки, — в выбранную тапом точку: курсора там нет, а
	     Mouse.X/Y показывает последнее касание (джойстик, кнопку камеры), и руда
	     уезжала в печь, на которую игрок не смотрел.
	     Сеанса нет (руки пусты, забираем готовый расплав) — целимся по-старому,
	     этот путь модуль не трогает. ]]
	local ray = TouchPlace.ray(mouse)
	if not ray then
		-- телефон, место ещё не выбрано: считаем, что под прицелом пусто
		if TouchPlace.active() then return nil end
		ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	if player.Character then table.insert(ignore, player.Character) end
	if ghost then table.insert(ignore, ghost) end
	params.FilterDescendantsInstances = ignore

	local res = workspace:Raycast(ray.Origin, ray.Direction * RAY_DIST, params)
	if res and res.Instance then
		local node = res.Instance
		while node and node ~= workspace do
			if node:IsA("Model") and node.Name:lower():find("raft_smelter", 1, true) then
				--[[ ⚠️ ПРИЗРАК — НЕ ПЕЧЬ, ХОТЯ ЗОВУТ ИХ ОДИНАКОВО.
				     Пока игрок несёт плавильню, на палубе висит её полупрозрачная
				     копия с тем же именем. Этот поиск находил её и начинал вести
				     себя как с готовой печью: «положи руду и подкинь бревно», хотя
				     ставить её ещё только собираются. Метку ставит сама ставилка
				     при создании призрака (PlacementGhost). ]]
				if node:GetAttribute("PlacementGhost") then return nil end
				return node
			end
			node = node.Parent
		end
	end

	-- 2) запасной путь: луч мог упереться в чужой невидимый меш — берём печь
	-- рядом с игроком, чей центр на экране близко к курсору
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local best, bestPx
	for _, m in ipairs(allSmelters()) do
		local pos = m.Parent and smelterPos(m)
		if pos and (pos - hrp.Position).Magnitude <= REACH + 8 then
			local sp, onScreen = camera:WorldToViewportPoint(pos)
			if onScreen then
				local px = (Vector2.new(sp.X, sp.Y) - Vector2.new(mouse.X, mouse.Y)).Magnitude
				if px < 200 and (not bestPx or px < bestPx) then
					best, bestPx = m, px
				end
			end
		end
	end
	return best
end

local function inReach(smelter)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local pos = smelterPos(smelter)
	if not pos then return false end
	return (hrp.Position - pos).Magnitude <= REACH + 8
end

-- ── решение кадра: что подсветить и что сделает клик ──
local pending = nil   -- { action = "place"|"collect", smelter, kind }

local RU_DONE = { iron = "Железо переплавлено", seaweed = "Клей готов" }

local function think()
	pending = nil
	updateTouchSession()
	local smelter = smelterUnderMouse()
	if not smelter then
		hideHighlight()
		destroyGhost()
		setHint(nil)
		local held = heldMaterial()
		if held then dbg("в руках " .. held .. ", но курсор не на плавильне") end
		return
	end
	if not inReach(smelter) then
		hideHighlight()
		destroyGhost()
		setHint(nil)
		dbg("плавильня под курсором, но слишком далеко")
		return
	end

	-- 1) в руках сырьё и его слот пуст → зелёный призрак заготовки, клик ставит
	local heldKey = heldMaterial()
	if heldKey then
		local mat = MATERIALS[heldKey]
		local state = smelter:GetAttribute(mat.stateAttr) or "none"
		if state == "none" then
			local raw = smelter:FindFirstChild(mat.rawName, true)
			if raw then
				ensureGhost(raw)
				syncGhost()
				hideHighlight()
				pending = { action = "place", smelter = smelter, kind = mat.kind }
				setHint("ЛКМ — положить в печь")
				dbg("призрак " .. heldKey .. " показан — клик ставит")
				return
			else
				dbg("в модели печи нет слоя " .. mat.rawName)
			end
		else
			dbg("слот " .. mat.kind .. " занят (" .. tostring(state) .. ")")
		end
	end
	destroyGhost()

	-- 2) есть готовый расплав → золотой, клик забирает (железо в приоритете
	-- произвольно: обе партии подряд забираются двумя кликами)
	for _, mat in pairs(MATERIALS) do
		if smelter:GetAttribute(mat.stateAttr) == "done" then
			local molten = smelter:FindFirstChild(mat.moltenName, true)
			if molten then
				showHighlight(molten, GOLD)
				pending = { action = "collect", smelter = smelter, kind = mat.kind }
				setHint((RU_DONE[mat.kind] or "Готово") .. " — ЛКМ забрать")
				return
			end
		end
	end

	hideHighlight()

	-- 3) просто смотрим на печь: раньше тут зажигалась строка внизу экрана
	-- («положи руду…», «плавится… ~40 сек»). Подсказки убраны совсем, поэтому и
	-- считать их нечего: состояние печи видно по огню, призраку и подсветке.
end

RunService.RenderStepped:Connect(think)

-- ── клик ──
-- Тело общее: на компьютере его зовёт ЛКМ, на телефоне — кнопка «ПОСТАВИТЬ».
function onPlaceClick()
	if not pending then return end
	dbg("клик: " .. pending.action .. " (" .. pending.kind .. ")")
	actionEvent:FireServer(pending.action, pending.smelter, pending.kind)
end

-- Привязка живёт постоянно, но пропускает ввод дальше, пока прицел не на деле:
-- так не воюем с другими системами за ЛКМ.
ContextActionService:BindActionAtPriority("SmelterClick",
	function(_, state, input)
		if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
		if not pending then return Enum.ContextActionResult.Pass end
		--[[ ⚠️ НА ТЕЛЕФОНЕ ТАП НЕ КЛАДЁТ — ОН ВЫБИРАЕТ МЕСТО.
		     Касание Roblox отдаёт сюда тем же MouseButton1, поэтому руда падала в
		     печь по координатам ПРОШЛОГО тапа: игрок ещё целился, а сырьё уже
		     ушло. Пока идёт сеанс, ввод пропускаем дальше (сунутый он помечается
		     обработанным, и модуль его не увидел бы) — тапом двигают прицел, а
		     кладёт кнопка. Условие про АКТИВНЫЙ сеанс: с пустыми руками сеанса
		     нет, и готовый расплав забирается тапом как раньше. ]]
		--[[ ⚠️ Спрашиваем СВОЁ состояние, а не модуль: сырьё в руках значит, что
		     идёт укладка, и палец в ней только целится. Не поднялся модуль —
		     всё равно не кладём вслепую (см. IS_TOUCH). ]]
		if IS_TOUCH and heldMaterial() then
			return Enum.ContextActionResult.Pass
		end
		onPlaceClick()
		return Enum.ContextActionResult.Sink
	end,
	false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)

print("[Плавильня/клиент] загружен")
