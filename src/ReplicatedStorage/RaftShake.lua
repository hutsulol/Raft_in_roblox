local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	Удержание игрока на палубе, когда сборка плота перестраивается.

	⚠️ ПЕРСОНАЖА УДЕРЖИВАЕТ КЛИЕНТ, А НЕ СЕРВЕР.
	Плот и персонаж — РАЗНЫЕ физические сборки. Любая операция, которая добавляет
	или убирает деталь, приваренную к плоту (поставили клетку, подменили стадию
	очистителя, выросла грядка, сварился обед в печи), на шаг физики сбивает ход
	сборки плота. Стоящий на палубе игрок в этот момент продолжает лететь с прежней
	скоростью — и уезжает по доскам «по инерции». Снаружи это выглядит как рывок или
	«пролагивание».

	Плоту скорость возвращает сам сервер: каждая такая операция обёрнута в снимок
	AssemblyLinearVelocity/AssemblyAngularVelocity до и восстановление после. А вот
	персонажа оттуда не удержать: он принадлежит СВОЕМУ клиенту (network ownership),
	и серверная запись в HumanoidRootPart.CFrame тут же перебивается репликацией с
	него. Поэтому держать место обязан владелец персонажа — то есть его клиент.

	Отсюда разделение обязанностей:
		СЕРВЕР  RaftShake.notify()  — рядом с восстановлением скорости плота
		КЛИЕНТ  RaftShake.listen()  — один раз при старте, дальше само

	⚠️ ОПОВЕЩЕНИЕ ШИРОКОВЕЩАТЕЛЬНОЕ, А НЕ ТОМУ, КТО НАЖАЛ.
	На плоту стоят все. Раньше место держал только тот клиент, который сам поставил
	постройку, — соседа при этом всё равно утаскивало. К тому же половина перестроек
	вообще не привязана к нажатию: очиститель меняет модель через 20 секунд после
	заливки, урожай подрастает сам. Знать заранее, когда тряхнёт, клиент не может —
	поэтому сервер говорит всем.

	Локально (без сервера) можно позвать RaftShake.hold() — так делает стройка,
	у неё момент установки известен на кадр раньше, чем ответ сервера.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local EVENT_NAME = "RaftShook"

local RaftShake = {}

-- Сборка перестраивается не мгновенно: destroy → clone → weld растянуты на
-- несколько шагов физики, и вернуть игрока надо на каждом из них.
--
-- ⚠️ ОКНО ШИРЕ, ЧЕМ У СТРОЙКИ (там хватало восьми кадров).
-- Стройка зовёт удержание САМА, в кадре нажатия, — то есть заведомо раньше рывка.
-- А по сети оповещение и сама перестройка приезжают к клиенту примерно вместе, с
-- разбросом в кадр-другой в любую сторону. Узкое окно могло закончиться РАНЬШЕ,
-- чем доедет рывок, и удержание прошло бы вхолостую. Держать дольше безопасно:
-- цикл всё равно обрывается на первом же шаге игрока, так что уйти можно сразу.
local HOLD_FRAMES = 16
-- Нижняя граница — чтобы не дёргать персонажа на ровном месте (микродрожь палубы
-- на волне есть всегда). Верхняя — чтобы НЕ ОТМЕНИТЬ настоящий перенос: лёг в
-- кровать, сел в лодку, телепорт на остров. Там смещение сразу большое.
local DRIFT_MIN, DRIFT_MAX = 0.08, 8

-- ─── Сервер ───

local function serverEvent()
	local e = ReplicatedStorage:FindFirstChild(EVENT_NAME)
	if not e then
		e = Instance.new("RemoteEvent")
		e.Name = EVENT_NAME
		e.Parent = ReplicatedStorage
	end
	return e
end

--[[ Зовётся на сервере сразу после того, как сборке плота вернули скорость.

     ⚠️ И ЕЩЁ РАЗ ВОЗВРАЩАЕТ СКОРОСТЬ — ПОСЛЕ ШАГА ФИЗИКИ.
     Roblox пересобирает сборку не в момент создания сварки, а на следующем шаге
     физики; скорость, возвращённая в том же кадре, достаётся ещё СТАРОЙ сборке.
     Молоток (BuildingSystem.placeWithVelocityPreserved) повторял запись на
     Heartbeat, а остальные постройки — нет: бочка, грядка, декор, ферма, пугало
     ставились с рывком плота. Теперь повтор делает сам notify — его зовут все,
     кто вернул скорость. Вертикаль не трогаем: её ведёт сервопривод высоты
     BoatMovement, чужая запись по Y столкнула бы плот с ватерлинии. ]]
function RaftShake.notify()
	if not RunService:IsServer() then return end
	local ok, e = pcall(serverEvent)
	if ok and e then e:FireAllClients() end
	local raft = workspace:FindFirstChild("Raft")
	local primary = raft and raft.PrimaryPart
	if primary then
		local lin, ang = primary.AssemblyLinearVelocity, primary.AssemblyAngularVelocity
		RunService.Heartbeat:Once(function()
			if not primary.Parent then return end
			local v = primary.AssemblyLinearVelocity
			primary.AssemblyLinearVelocity = Vector3.new(lin.X, v.Y, lin.Z)
			primary.AssemblyAngularVelocity = ang
		end)
	end
end

--[[ ПРИВАРИТЬ МОДЕЛЬ (или деталь) К ПЛОТУ БЕЗ РЫВКА — тот же рецепт, что у молотка
     (BuildingSystem.weldToRaft + placeWithVelocityPreserved):
       • все детали Massless: иначе сборка уравнивает импульс и плот теряет ход;
       • сварка, пока детали ещё заякорены, и только потом отпустить;
       • владелец физики деталей — сервер, как у самого плота;
       • скорость плота — снимок до и возврат после, второй раз после шага физики
         (notify), и клиенты удерживают стоящих на палубе игроков.
     Только на сервере. Модель уже должна стоять на месте (PivotTo сделан). ]]
function RaftShake.attach(obj, raft)
	if not RunService:IsServer() then return end
	local primary = raft and raft.PrimaryPart
	if not (obj and primary) then return end
	local lin, ang = primary.AssemblyLinearVelocity, primary.AssemblyAngularVelocity
	local parts = {}
	if obj:IsA("BasePart") then table.insert(parts, obj) end
	for _, d in ipairs(obj:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	for _, p in ipairs(parts) do
		p.Anchored = true
		p.Massless = true
	end
	for _, p in ipairs(parts) do
		local w = Instance.new("WeldConstraint")
		w.Part0 = p
		w.Part1 = primary
		w.Parent = p
	end
	if obj.Parent ~= raft and not obj:IsDescendantOf(raft) then obj.Parent = raft end
	for _, p in ipairs(parts) do
		p.Anchored = false
		pcall(function() p:SetNetworkOwner(nil) end)
	end
	primary.AssemblyLinearVelocity = lin
	primary.AssemblyAngularVelocity = ang
	RaftShake.notify()
end

-- ─── Клиент ───

local holding = false

--[[ Держать персонажа на его месте ОТНОСИТЕЛЬНО плота несколько кадров. ]]
function RaftShake.hold()
	if not RunService:IsClient() then return end
	if holding then return end   -- две тряски подряд — не два спорящих цикла

	local player = Players.LocalPlayer
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local raft = workspace:FindFirstChild("Raft")
	local prim = raft and raft.PrimaryPart
	if not (hrp and hum and prim) then return end

	-- ⚠️ ТОЛЬКО СТОЯЩЕГО. У идущего смещение за кадр — это его собственный шаг, и
	-- «возврат на место» дрался бы с управлением: игрок жал бы вперёд, а его
	-- откидывало назад. Тряска ловится в тот момент, когда с чем-то взаимодействуют,
	-- а взаимодействуют стоя.
	if hum.MoveDirection.Magnitude > 0.1 then return end
	-- В прыжке и в воде игрок не опирается на палубу — там держать нечего.
	local state = hum:GetState()
	if state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Swimming then
		return
	end

	local rel = prim.CFrame:ToObjectSpace(hrp.CFrame)
	local frames = 0
	holding = true

	local conn
	conn = RunService.Heartbeat:Connect(function()
		frames += 1
		if frames > HOLD_FRAMES or not hrp.Parent or not prim.Parent
			or hum.MoveDirection.Magnitude > 0.1 then
			conn:Disconnect()
			holding = false
			return
		end
		local want = prim.CFrame * rel
		local drift = (hrp.Position - want.Position).Magnitude
		if drift > DRIFT_MIN and drift < DRIFT_MAX then
			-- ⚠️ ДЕРЖИМ ТОЛЬКО МЕСТО, ПОВОРОТ НЕ ТРОГАЕМ.
			-- Здесь писался весь CFrame из снимка, вместе с поворотом, — и каждое
			-- удержание разворачивало персонажа туда, куда он смотрел в момент
			-- снимка. На телефоне это читается как «игра сама поворачивает экран
			-- вперёд»: перестройки сборки идут по ходу игры (грядка, очиститель,
			-- печь), и на каждой вид отщёлкивало обратно.
			-- Смысл удержания — не дать УЕХАТЬ по палубе; куда игрок смотрит, его
			-- дело. Поворот берём текущий, а не из снимка.
			hrp.CFrame = CFrame.new(want.Position) * hrp.CFrame.Rotation
		end
	end)
end

--[[ Подписка на серверные оповещения. Звать один раз, из клиентского скрипта. ]]
function RaftShake.listen()
	if not RunService:IsClient() then return end
	task.spawn(function()
		-- WaitForChild с таймаутом: если события нет (сервер ещё не поднял свои
		-- системы), лучше выйти, чем повиснуть здесь навсегда — молчаливое
		-- зависание на WaitForChild уже съедало в этом проекте целые скрипты.
		local e = ReplicatedStorage:WaitForChild(EVENT_NAME, 30)
		if not e then
			warn("RaftShake: не дождался " .. EVENT_NAME .. ", удержание на палубе выключено")
			return
		end
		e.OnClientEvent:Connect(RaftShake.hold)
	end)
end

return RaftShake
