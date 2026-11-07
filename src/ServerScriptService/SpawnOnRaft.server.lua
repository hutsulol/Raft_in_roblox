-- SpawnOnRaft.server.lua
-- ИГРОК ПОЯВЛЯЕТСЯ НА ПЛОТУ И ВМЕСТЕ С НИМ — а не там, где плот был секунду назад.
--
-- ⚠️ ПРИЧИНА ЖАЛОБЫ НЕ В ТОЧКЕ СПАВНА, А В СКОРОСТИ.
-- Точка появления — SpawnLocation внутри плота, она едет вместе с ним, и с этим
-- всё в порядке. Беда в том, что персонаж рождается СТОЯЩИМ НА МЕСТЕ, а палуба
-- под ним идёт восемь студов в секунду. Дальше одно из двух, и оба видели:
--   • трение пытается утащить персонажа за палубой, гуманоид теряет равновесие и
--     заваливается — это и есть «заспавнило лежачим»;
--   • палуба уезжает быстрее, чем персонаж успевает зацепиться, и он остаётся за
--     кормой — «плот уплыл, пока я понял, куда попал».
-- У игрока с плохой связью второе неизбежно: пока клиент грузится, физику его
-- персонажа никто не считает — он висит в мировых координатах, а плот идёт. К
-- моменту, когда клиент оживает, до плота уже сотня студов открытой воды.
--
-- ⚠️ ПОЭТОМУ ДЕРЖИМ, А НЕ «СТАВИМ ОДИН РАЗ».
-- Разовая установка в момент появления лечит только быстрый клиент: медленный
-- всё равно проснётся в море, потому что плот ушёл ПОСЛЕ неё. Держим персонажа
-- на палубе до тех пор, пока он не начнёт двигаться сам — это и есть признак,
-- что клиент взял управление. Никакого отдельного сигнала «я загрузился» не
-- нужно: MoveDirection приходит от клиента и молчит ровно до тех пор, пока тот
-- не готов.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ ── ПЛОТ СТОИТ, ПОКА НЕ ЗАГРУЗИЛИСЬ ВСЕ ──
     Удержания одного персонажа не хватило: на слабом канале клиент оживает
     позже, чем кончается ожидание, и человек просыпается в открытой воде —
     плот к тому времени в сотне студов. Поэтому ждёт сам плот: пока хоть один
     из вошедших не доложил о готовности, BoardingHold на модели плота держит
     скорость в нуле (см. BoatMovement).
     Признаков готовности три, годится любой:
       • клиент погасил экран загрузки и дёрнул RaftBoardingReady — самый
         честный: экран гаснет, когда игра загружена, персонаж есть и вокруг
         него догрузился мир (ReplicatedFirst/TeleportLoadingScreen);
       • персонаж пошёл или прыгнул — управление уже у игрока;
       • вышло время ожидания — иначе один не догрузившийся держал бы плот
         вечно, а остальным играть.
     Таймаут общий и щедрый: не догрузился за минуту — это уже не загрузка. ]]
local MAX_WAIT = 60

local readyEvent = ReplicatedStorage:FindFirstChild("RaftBoardingReady")
if not readyEvent then
	readyEvent = Instance.new("RemoteEvent")
	readyEvent.Name = "RaftBoardingReady"
	readyEvent.Parent = ReplicatedStorage
end

local ready    = {}   -- [player] = true, когда игрок точно в игре
local deadline = {}   -- [player] = момент, после которого ждать перестаём

local function markReady(player, why)
	if ready[player] then return end
	ready[player] = true
	print(("[Спавн] %s: готов (%s)"):format(player.Name, why))
end

readyEvent.OnServerEvent:Connect(function(player)
	markReady(player, "клиент догрузился")
end)

-- Верхний предел ожидания — MAX_WAIT выше: он же предел стоянки плота.
local HOLD_STEP  = 0.2
-- Над пивотом плота: сам SpawnLocation лежит в палубе, персонажа ставим выше.
local SPAWN_UP   = 4
-- Разводим соседей по кругу, иначе двое вошедших разом стоят в одной точке и
-- расталкиваются физикой — со стороны это «меня выкинуло с плота».
local SPREAD     = 2.5

local function raftPrimary()
	local raft = workspace:FindFirstChild("Raft")
	return raft and raft.PrimaryPart
end

--[[ Куда именно ставить этого игрока. Смещение постоянное для конкретного
     UserId: при повторном спавне человек оказывается на том же месте, а не
     скачет по палубе. ]]
local function spotFor(player, pp)
	local i = player.UserId % 4
	local angle = i * (math.pi / 2)
	local off = Vector3.new(math.cos(angle) * SPREAD, SPAWN_UP, math.sin(angle) * SPREAD)
	return pp.Position + off
end

--[[ Поставить персонажа на палубу: место, СКОРОСТЬ ПЛОТА и вертикальная поза.

     ⚠️ СКОРОСТЬ ВАЖНЕЕ КООРДИНАТЫ. Поставить в нужную точку с нулевой скоростью
     значит повторить исходную беду: следующий же кадр палуба уедет из-под ног.
     Наследуем ход плота — тот же приём, что при вставании с кровати.

     ⚠️ ПОВОРОТ БЕРЁМ ТОЛЬКО ПО РЫСКАНИЮ. Если персонаж лежит, его собственный
     поворот содержит заваленные оси: перенеси мы его целиком — он останется
     лежать, только на новом месте. Горизонтальное направление взгляда при этом
     сохраняем: разворачивать человека лицом в другую сторону без причины
     неприятно. ]]
local function plant(player, char)
	local pp = raftPrimary()
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (pp and hrp and hum) then return false end
	if hum.Health <= 0 then return false end

	local target = spotFor(player, pp)
	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then flat = Vector3.new(0, 0, -1) end

	hrp.CFrame = CFrame.lookAt(target, target + flat.Unit)
	hrp.AssemblyLinearVelocity = pp.AssemblyLinearVelocity
	hrp.AssemblyAngularVelocity = Vector3.zero

	-- поднимаем, если завалился: PlatformStand и «упавшие» состояния сами не
	-- проходят, гуманоид встаёт физически и около секунды лежит боком
	hum.PlatformStand = false
	local st = hum:GetState()
	if st == Enum.HumanoidStateType.FallingDown
		or st == Enum.HumanoidStateType.Ragdoll
		or st == Enum.HumanoidStateType.Physics
		or st == Enum.HumanoidStateType.PlatformStanding then
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	return true
end

--[[ Клиент взял управление? Единственный честный признак на сервере — персонаж
     ПОШЁЛ. MoveDirection приходит от клиента и до его готовности равен нулю.
     Прыжок считаем тем же признаком: с джойстика и с клавиатуры он приходит
     раньше ходьбы. ]]
local function playerInControl(hum)
	if hum.MoveDirection.Magnitude > 0.1 then return true end
	if hum.Jump then return true end
	return false
end

local function onCharacter(player, char)
	local hum = char:WaitForChild("Humanoid", 10)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not (hum and hrp) then return end

	-- первая установка — сразу, ещё до всяких ожиданий
	plant(player, char)

	-- ⚠️ ДЕРЖИМ, ПОКА ИГРОК НЕ ГОТОВ, А НЕ ФИКСИРОВАННЫЕ 12 СЕКУНД.
	-- Плот всё это время стоит (BoardingHold), так что долгое удержание никому
	-- не мешает: раньше персонажа отпускали по таймеру, и он оставался за кормой.
	local heldFor = 0
	while char.Parent and player.Parent and hum.Health > 0 and heldFor < MAX_WAIT do
		if playerInControl(hum) then
			markReady(player, "персонаж пошёл сам")
			break
		end
		--[[ ⚠️ КЛИЕНТ ОТОЗВАЛСЯ — ОТПУСКАЕМ СРАЗУ, БЕЗ ЗАПАСА.
		     Здесь стояла пара секунд «на всякий случай», и они-то и выглядели как
		     телепортация: живой клиент уже рисует персонажа, палуба тащит его
		     трением, а сервер каждые 0.2 секунды возвращает его в исходную точку.
		     Десять рывков подряд — ровно те «первые две секунды дёргает».
		     Пока клиент молчит, подстановка не видна никому: рисовать некому. ]]
		if ready[player] then break end
		task.wait(HOLD_STEP)
		heldFor += HOLD_STEP
		plant(player, char)
	end

	--[[ ⚠️ ПОСЛЕДНЯЯ УСТАНОВКА — ПОСЛЕ ВЫХОДА ИЗ ЦИКЛА, А НЕ ВМЕСТО НЕГО.
	     Игрок мог тронуться в тот самый кадр, когда плот качнуло: отпустить его
	     без финальной подстановки скорости значит отдать ровно ту рассинхронизацию,
	     от которой мы весь цикл и держались. Координату при этом не трогаем —
	     он уже идёт сам, и дёргать его на месте нельзя. ]]
	if char.Parent and hum.Health > 0 then
		local pp = raftPrimary()
		if pp and (hrp.Position - pp.Position).Magnitude < 120 then
			hrp.AssemblyLinearVelocity = pp.AssemblyLinearVelocity
		end
		hum.PlatformStand = false
	end

	print(("[Спавн] %s: держали на палубе %.1f с (%s)")
		:format(player.Name, heldFor,
			heldFor >= MAX_WAIT and "вышло время ожидания"
				or (ready[player] and "игрок в игре" or "персонаж отпущен")))
end

--[[ Кто-то ещё грузится? Возвращаем такого игрока, иначе nil.
     Ушедшие и просроченные не считаются: плот не должен стоять из-за того,
     кого уже нет или кто не догрузился за минуту. ]]
local function stillBoarding()
	local now = os.clock()
	for _, plr in ipairs(Players:GetPlayers()) do
		if not ready[plr] then
			local dl = deadline[plr]
			if dl and now < dl then return plr end
		end
	end
	return nil
end

task.spawn(function()
	while true do
		task.wait(0.25)
		local raft = workspace:FindFirstChild("Raft")
		if raft then
			local who  = stillBoarding()
			local want = who ~= nil
			if (raft:GetAttribute("BoardingHold") == true) ~= want then
				raft:SetAttribute("BoardingHold", want or nil)
				if want then
					print(("[Спавн] плот ждёт: %s ещё грузится"):format(who.Name))
				else
					print("[Спавн] все на борту — плот пошёл")
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	ready[player]    = nil
	deadline[player] = nil
end)

local function bind(player)
	deadline[player] = os.clock() + MAX_WAIT
	player.CharacterAdded:Connect(function(char)
		task.spawn(onCharacter, player, char)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

for _, p in Players:GetPlayers() do bind(p) end
Players.PlayerAdded:Connect(bind)

print("[Спавн] сторож готов: держим персонажа на палубе, пока клиент не взял управление")
