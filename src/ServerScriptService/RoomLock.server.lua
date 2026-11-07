--[[
	ЗАМОК КОМНАТЫ: сервер принимает ровно ту компанию, ради которой создан.

	Лобби отправляет группу телепортом и кладёт в TeleportData её размер
	(playerCount). Первый приехавший запирает сервер на это число: соло — на
	одного, вдвоём — на двоих. Кто приедет сверх — уезжает В СВОЙ собственный
	свежий сервер, с теми же данными телепорта, с которыми приехал сюда.

	⚠️ ИМЕННО В СВОЙ, А НЕ ОБРАТНО В ЛОББИ.
	Первая версия возвращала лишнего в лобби, и со стороны игрока это выглядело
	как «запустило к чужому и сразу выкинуло, а свою игру так и не начало».
	Замок обязан не только не пускать чужого, но и довести человека туда, куда он
	собирался. В лобби высаживаем только если своего сервера выдать не вышло.

	⚠️ ЗАЧЕМ ЗАМОК, ЕСЛИ СЕРВЕР И ТАК ЗАРЕЗЕРВИРОВАН.
	Резерв (ReserveServer) закрывает главную дыру — публичный матчмейкинг, из-за
	которого двое, запускавшие соло по очереди, оказывались на одном плоту. Но
	резерв — обещание Roblox, а не наше: он не выдаётся в Studio, может не
	выдаться в рантайме (тогда лобби честно ругается в лог и всё равно отправляет
	игроков, чтобы никто не застрял), и попасть в чужую комнату можно ещё
	несколькими путями мимо матчмейкинга. Замок — наша собственная проверка на
	стороне назначения: он не зависит ни от чего внешнего.

	⚠️ НЕ ЗНАЕМ РАЗМЕР — НИКОГО НЕ ТРОГАЕМ.
	Зашли напрямую (Studio, тест по кнопке Play) — TeleportData пуст, размера
	нет. В этом случае замок не запирается вовсе: выгонять игрока из-за того, что
	мы не смогли прочитать его данные, — худшее из возможных поведений.

	⚠️ СЧИТАЕМ МЕСТА, А НЕ ИМЁНА.
	Список UserId группы лобби не передаёт, да он и не нужен: сервер закрытый,
	снаружи в него никто не приедет. Задача замка — не пустить ЛИШНЕГО, и для
	этого достаточно числа занятых мест. Заодно это правильно ведёт себя при
	перезаходе: игрок вышел — место освободилось, вернулся — сел на своё.
]]

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local Workspace       = game:GetService("Workspace")

local LOG = "[Комната]"

-- Сколько мест в этой комнате. 0 — размер неизвестен, замок выключен.
local capacity = 0

-- Куда возвращать лишнего. Тем же способом, что и «Выйти в лобби» в RaftHealth:
-- жёсткой константы нет, зато Roblox помнит, откуда игрок телепортировался.
local function lobbyPlaceId()
	for _, p in ipairs(Players:GetPlayers()) do
		local ok, data = pcall(function() return p:GetJoinData() end)
		local src = ok and data and tonumber(data.SourcePlaceId)
		if src and src > 0 and src ~= game.PlaceId then return src end
	end
	return nil
end

local function joinData(player)
	local ok, data = pcall(function() return player:GetJoinData() end)
	if not ok or type(data) ~= "table" then return nil end
	return data.TeleportData
end

-- Сколько раз игрока уже перекидывали. Защита от карусели: если своё место
-- почему-то не даётся, лучше высадить в лобби, чем гонять по кругу.
local MAX_HOPS = 2

-- Вернуть в лобби. Запасной путь, когда своего сервера выдать не вышло.
local function sendBack(player, why)
	local placeId = lobbyPlaceId()
	if not placeId then
		warn(("%s %s лишний (%s), но лобби неизвестно — оставляем его здесь")
			:format(LOG, player.Name, why))
		return
	end
	warn(("%s %s → обратно в лобби (%s)"):format(LOG, player.Name, why))
	pcall(function()
		TeleportService:TeleportAsync(placeId, { player })
	end)
end

-- ⚠️ ЛИШНЕГО НЕ ВЫСАЖИВАЕМ, А ОТПРАВЛЯЕМ В ЕГО СОБСТВЕННЫЙ МИР.
-- Первая версия просто возвращала его в лобби — и с точки зрения игрока это
-- выглядело как «запустило к чужому и сразу выкинуло, а свою игру так и не
-- начало». Замок обязан не только не пускать, но и доводить человека туда, куда
-- он собирался: резервируем ему свежий сервер и пересылаем ТЕ ЖЕ данные
-- телепорта, с которыми он приехал, — иначе потеряется и выбранный сейв, и
-- размер комнаты, и он приедет в чужой по смыслу мир.
local function forwardToOwnServer(player, td)
	local hops = (td and tonumber(td.roomHop)) or 0
	if hops >= MAX_HOPS then
		sendBack(player, "своё место не выдаётся, попыток исчерпано")
		return
	end

	local okReserve, code = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not (okReserve and code) then
		-- В Studio резерва нет вовсе, и это нормально: там просто в лобби.
		sendBack(player, "ReserveServer не дал сервер: " .. tostring(code))
		return
	end

	local data = {}
	if type(td) == "table" then
		for k, v in pairs(td) do data[k] = v end
	end
	data.roomHop = hops + 1

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	options:SetTeleportData(data)

	warn(("%s %s приехал сверх мест (%d) — отправляем в его собственный мир")
		:format(LOG, player.Name, capacity))
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not ok then
		warn(("%s переслать %s не вышло: %s"):format(LOG, player.Name, tostring(err)))
		sendBack(player, "телепорт не прошёл")
	end
end

-- ⚠️ ГЛАВНАЯ СТРОКА ДЛЯ РАЗБОРА «ПОЧЕМУ Я ПОПАЛ К ЧУЖОМУ».
-- game.PrivateServerId непустой РОВНО тогда, когда сервер зарезервированный.
-- Пусто — значит лобби отправило игрока в общий матчмейкинг, и виноват не замок,
-- а телепорт на той стороне: либо ReserveServer не дал кода, либо сработал не тот
-- код лобби. Пустая строка тут закрывает половину возможных причин сразу.
local function logArrival(player, td)
	local private = game.PrivateServerId

	-- ⚠️ ЧТО СКАЗАЛО ЛОББИ. Три разных ответа — три разные причины:
	--   «да»    — лобби резерв получило, а сервер всё равно общий: значит код
	--             применился не к тому телепорту (ищи чужой _G.OnRoomFull);
	--   «нет»   — ReserveServer не выдал сервер, причина в логе ЛОББИ;
	--   «поля нет» — отправлял код СТАРЕЕ правки: в плейсе лобби лежит старая
	--             версия, её надо пересинкать и опубликовать.
	local said
	if td == nil then said = "данных нет (прямой заход)"
	elseif td.reserved == true then said = "лобби: резерв ПОЛУЧЕН"
	elseif td.reserved == false then said = "лобби: резерв НЕ ВЫДАЛСЯ"
	else said = "лобби: ПОЛЯ НЕТ — в плейсе лобби старый код!" end

	local okSrc, src = pcall(function() return player:GetJoinData().SourcePlaceId end)
	print(("%s %s зашёл | сервер %s | %s | мест %s | в мире %d | это место %d | из места %s")
		:format(LOG, player.Name,
			(private ~= "" and "ПРИВАТНЫЙ (" .. private:sub(1, 8) .. "…)"
				or "ОБЩИЙ — телепорт был без резерва!"),
			said,
			tostring(td and td.playerCount or "?"),
			#Players:GetPlayers(),
			game.PlaceId,
			tostring(okSrc and src or "?")))
end

local function onPlayer(player)
	local td = joinData(player)
	logArrival(player, td)

	-- ⚠️ ЗАПИРАЕМ ПО ПЕРВОМУ, У КОГО ЕСТЬ ДАННЫЕ, А НЕ ПО ПЕРВОМУ ВОШЕДШЕМУ.
	-- Порядок прибытия группы не гарантирован, и первым может оказаться тот, чьи
	-- данные почему-то не прочитались. Тогда размер возьмём у следующего.
	if capacity == 0 then
		local want = td and tonumber(td.playerCount)
		if want and want > 0 then
			capacity = want
			Workspace:SetAttribute("RoomCapacity", capacity)
			print(("%s комната заперта на %d игрок(ов) — по данным телепорта от %s")
				:format(LOG, capacity, player.Name))
		end
		return   -- тот, кто задал размер, всегда свой
	end

	-- Место есть — проходи. Считаем ПОСЛЕ входа, поэтому текущий уже в списке.
	if #Players:GetPlayers() <= capacity then return end

	forwardToOwnServer(player, td)
end

Players.PlayerAdded:Connect(onPlayer)
-- Кто-то мог войти, пока скрипт грузился.
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayer, p)
end
